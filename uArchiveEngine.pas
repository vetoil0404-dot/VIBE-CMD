unit uArchiveEngine;

{
  Виртуальная ФС архивов: ZIP, TAR, GZ, TGZ, 7Z, RAR (и CAB/ISO через 7-Zip).
  Вложенные архивы материализуются во временный кэш.
  Запись — атомарный replace с бэкапом, без «удалил оригинал, упал на move».
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TArchiveKind = (akNone, akZip, akTar, akGz, akTgz, akSevenZ, akRar, akOther);

  TArcConflict = (acOverwrite, acSkip, acRename, acCancel);

  TArcProgressProc = reference to procedure(const AName: string; ADelta, AFileSize: Int64);
  TArcWaitProc = reference to procedure;
  TArcConflictProc = reference to function(const ASrc, ADst: string;
    ASrcSize, ADstSize: Int64; ASrcTime, ADstTime: TDateTime): TArcConflict;

  TArcItem = record
    Path: string;
    IsDir: Boolean;
    Size: Int64;
    PackedSize: Int64;
    Modified: TDateTime;
    Encrypted: Boolean;
  end;

  TArcChild = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Encrypted: Boolean;
  end;

procedure SetArchiveHooks(AProgress: TArcProgressProc; AConflict: TArcConflictProc;
  AWait: TArcWaitProc);
procedure ClearArchiveHooks;

function DetectArchiveKind(const APath: string): TArchiveKind;
function IsWritableArchiveKind(AKind: TArchiveKind): Boolean;
function SevenZipAvailable: Boolean;
function FindSevenZipExe: string;
function ArchiveKindCaption(AKind: TArchiveKind): string;

function ArchivePathIsFolder(const APath: string): Boolean;
function ArchivePathExists(const APath: string): Boolean;
function ArchiveCanEnter(const APath: string): Boolean;
function ArchiveInvolved(const ASrc, ADestDir: string): Boolean;

function ListArchiveChildren(const APath: string; out AChildren: TArray<TArcChild>): Boolean;
function ListArchiveBranch(const APath: string): TArray<TArcItem>;
function ScanArchivePath(const APath: string; out AFiles: Integer; out ABytes: Int64): Boolean;

procedure CopyArchiveEntry(const ASrcPath, ADstDir: string);
procedure DeleteArchiveEntry(const APath: string);
procedure DeleteArchiveEntries(const APaths: TArray<string>);
procedure RenameArchiveEntry(const AOldPath, ANewName: string; out ANewPath: string);
function CreateArchiveFolder(const AParentDir, ABaseName: string): string;
procedure PackToArchive(const ASources: TArray<string>; const ADestFile: string;
  AReplace: Boolean);
function MaterializeArchiveFile(const APath: string; out ALocal: string): Boolean;
procedure InvalidateArchive(const APath: string);
procedure ReplaceFileAtomic(const ADest, ATemp: string);

function ArcNorm(const AInner: string): string;
function ArcJoin(const AFolder, AName: string): string;
function ArcLeaf(const AInner: string): string;
function ArcSafeRel(const ARel: string): string;

implementation

uses
  System.IOUtils, System.StrUtils, System.SyncObjs, System.Zip, System.ZLib,
  System.DateUtils, System.Math,
  uFileModel
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const
  MEM_COPY = 8 * 1024 * 1024;
  CHUNK = 1024 * 1024;
  NEST_DIR = 'TCClone\arc';

type
  TArcRef = record
    Physical: string;
    Kind: TArchiveKind;
    Inner: string;
    DiskArchive: string;
  end;

  TCacheEnt = class
    Path: string;
    Size: Int64;
    MTime: TDateTime;
    Items: TArray<TArcItem>;
  end;

  TWatchStream = class(TStream)
  private
    FInner: TStream;
    FName: string;
    FReported: Int64;
    FOwns: Boolean;
  public
    constructor Create(AInner: TStream; AOwns: Boolean; const AName: string);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    function GetSize: Int64; override;
  end;

  TOwnedZip = class(TZipFile)
  private
    FOwnStream: TStream;
  public
    destructor Destroy; override;
    procedure OpenOwned(AStream: TStream; AMode: TZipMode);
  end;

threadvar
  GProg: TArcProgressProc;
  GConf: TArcConflictProc;
  GWait: TArcWaitProc;

var
  GLock: TCriticalSection;
  GCache: TObjectDictionary<string, TCacheEnt>;
  GNest: TDictionary<string, string>;
  GNestSrc: TDictionary<string, string>;
  G7zExe: string;
  G7zTried: Boolean;

procedure ArcCheckWait;
begin
  if Assigned(GWait) then
    GWait();
end;

procedure ArcProgress(const AName: string; ADelta, ASize: Int64);
begin
  if Assigned(GProg) and (ADelta > 0) then
    GProg(AName, ADelta, ASize);
end;

procedure SetArchiveHooks(AProgress: TArcProgressProc; AConflict: TArcConflictProc;
  AWait: TArcWaitProc);
begin
  GProg := AProgress;
  GConf := AConflict;
  GWait := AWait;
end;

procedure ClearArchiveHooks;
begin
  GProg := nil;
  GConf := nil;
  GWait := nil;
end;

{ TWatchStream }

constructor TWatchStream.Create(AInner: TStream; AOwns: Boolean; const AName: string);
begin
  inherited Create;
  FInner := AInner;
  FOwns := AOwns;
  FName := AName;
  FReported := 0;
end;

destructor TWatchStream.Destroy;
begin
  if FOwns then
    FInner.Free;
  inherited;
end;

function TWatchStream.GetSize: Int64;
begin
  Result := FInner.Size;
end;

function TWatchStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := FInner.Seek(Offset, Origin);
end;

function TWatchStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := FInner.Write(Buffer, Count);
  if Result > 0 then
    ArcProgress(FName, Result, FInner.Size);
end;

function TWatchStream.Read(var Buffer; Count: Longint): Longint;
var
  Pos: Int64;
begin
  Result := FInner.Read(Buffer, Count);
  Pos := FInner.Position;
  if Pos > FReported then
  begin
    ArcProgress(FName, Pos - FReported, FInner.Size);
    FReported := Pos;
  end;
end;

destructor TOwnedZip.Destroy;
begin
  inherited;
  FreeAndNil(FOwnStream);
end;

procedure TOwnedZip.OpenOwned(AStream: TStream; AMode: TZipMode);
begin
  Open(AStream, AMode);
  FOwnStream := AStream;
end;

function ArcNorm(const AInner: string): string;
begin
  Result := StringReplace(AInner, '\', '/', [rfReplaceAll]);
  while StartsText('/', Result) do
    Delete(Result, 1, 1);
  while EndsText('/', Result) do
    SetLength(Result, Length(Result) - 1);
end;

function ArcRaw(const AInner: string): string;
begin
  Result := StringReplace(AInner, '\', '/', [rfReplaceAll]);
  while StartsText('/', Result) do
    Delete(Result, 1, 1);
end;

function ArcJoin(const AFolder, AName: string): string;
var
  A, B: string;
begin
  A := ArcNorm(AFolder);
  B := ArcNorm(AName);
  if A = '' then
    Result := B
  else if B = '' then
    Result := A
  else
    Result := A + '/' + B;
end;

function ArcLeaf(const AInner: string): string;
var
  S: string;
  I: Integer;
begin
  S := ArcNorm(AInner);
  I := LastDelimiter('/', S);
  if I > 0 then
    Result := Copy(S, I + 1, MaxInt)
  else
    Result := S;
end;

function ArcParent(const AInner: string): string;
var
  S: string;
  I: Integer;
begin
  S := ArcNorm(AInner);
  I := LastDelimiter('/', S);
  if I > 0 then
    Result := Copy(S, 1, I - 1)
  else
    Result := '';
end;

function ArcSafeRel(const ARel: string): string;
var
  Parts: TArray<string>;
  P: string;
  Acc: TStringBuilder;
begin
  Acc := TStringBuilder.Create;
  try
    Parts := ArcNorm(ARel).Split(['/']);
    for P in Parts do
    begin
      if (P = '') or (P = '.') then
        Continue;
      if (P = '..') or (Pos(':', P) > 0) or (Pos('\', P) > 0) then
        raise Exception.Create('Некорректный путь в архиве: ' + ARel);
      if Acc.Length > 0 then
        Acc.Append('/');
      Acc.Append(P);
    end;
    Result := Acc.ToString;
  finally
    Acc.Free;
  end;
end;

function ArcToDiskPath(const ADestDir, ARel: string): string;
var
  Parts: TArray<string>;
  P: string;
begin
  Result := ExcludeTrailingPathDelimiter(ADestDir);
  Parts := ArcSafeRel(ARel).Split(['/']);
  for P in Parts do
  begin
    if P = '' then
      Continue;
    Result := Result + PathDelim + P;
  end;
end;

function IsArchiveFileName(const AName: string): Boolean;
var
  L, Ext: string;
begin
  L := LowerCase(AName);
  Ext := ExtractFileExt(L);
  Result := MatchText(Ext, ['.zip', '.zipx', '.cbz', '.jar', '.apk', '.ear',
    '.war', '.rar', '.7z', '.tar', '.gz', '.tgz', '.cab', '.lzh', '.iso',
    '.xz', '.bz2', '.tbz', '.txz', '.wim']) or
    EndsText('.tar.gz', L) or EndsText('.tar.bz2', L) or EndsText('.tar.xz', L);
end;

function DetectArchiveKind(const APath: string): TArchiveKind;
var
  L, Ext: string;
begin
  L := LowerCase(APath);
  Ext := ExtractFileExt(L);
  if EndsText('.tar.gz', L) or (Ext = '.tgz') then
    Exit(akTgz);
  if EndsText('.tar.bz2', L) or EndsText('.tar.xz', L) or (Ext = '.tbz') or
     (Ext = '.txz') then
    Exit(akOther);
  if MatchText(Ext, ['.zip', '.zipx', '.cbz', '.jar', '.apk', '.ear', '.war']) then
    Exit(akZip);
  if Ext = '.tar' then
    Exit(akTar);
  if Ext = '.gz' then
    Exit(akGz);
  if Ext = '.7z' then
    Exit(akSevenZ);
  if Ext = '.rar' then
    Exit(akRar);
  if MatchText(Ext, ['.cab', '.lzh', '.iso', '.xz', '.bz2', '.wim']) then
    Exit(akOther);
  Result := akNone;
end;

function IsWritableArchiveKind(AKind: TArchiveKind): Boolean;
begin
  Result := AKind in [akZip, akTar, akGz, akTgz, akSevenZ];
end;

function ArchiveKindCaption(AKind: TArchiveKind): string;
begin
  case AKind of
    akZip: Result := 'ZIP';
    akTar: Result := 'TAR';
    akGz: Result := 'GZ';
    akTgz: Result := 'TAR.GZ';
    akSevenZ: Result := '7Z';
    akRar: Result := 'RAR';
    akOther: Result := 'архив';
  else
    Result := '';
  end;
end;

function CacheKey(const APath: string): string;
begin
  Result := LowerCase(ExcludeTrailingPathDelimiter(APath));
end;

procedure InvalidateArchive(const APath: string);
var
  Key, Disk, Inner, NestKey, Tmp: string;
  Drop: TArray<string>;
  N, I: Integer;
begin
  if APath = '' then
    Exit;
  SplitArchivePath(APath, Disk, Inner);
  if Disk = '' then
    Disk := APath;
  Key := CacheKey(Disk);
  GLock.Enter;
  try
    GCache.Remove(Key);
    GCache.Remove(CacheKey(APath));
    N := 0;
    SetLength(Drop, 0);
    for NestKey in GNestSrc.Keys do
      if StartsText(Key + '|', NestKey) then
      begin
        Inc(N);
        SetLength(Drop, N);
        Drop[N - 1] := NestKey;
      end;
    for I := 0 to High(Drop) do
    begin
      if GNest.TryGetValue(Drop[I], Tmp) then
      try
        if TFile.Exists(Tmp) then
          TFile.Delete(Tmp);
      except
      end;
      GNest.Remove(Drop[I]);
      GNestSrc.Remove(Drop[I]);
    end;
  finally
    GLock.Leave;
  end;
end;

function FileStamp(const APath: string; out ASize: Int64; out AMTime: TDateTime): Boolean;
begin
  Result := TFile.Exists(APath);
  if not Result then
    Exit;
  try
    ASize := TFile.GetSize(APath);
    AMTime := TFile.GetLastWriteTime(APath);
  except
    ASize := 0;
    AMTime := 0;
  end;
end;

function NestDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, NEST_DIR);
  ForceDirectories(Result);
end;

function UniqueTempFile(const AName: string): string;
var
  Dir, Base, Ext: string;
  N: Integer;
begin
  Dir := NestDir;
  Base := TPath.GetFileNameWithoutExtension(AName);
  if Base = '' then
    Base := 'f';
  Ext := TPath.GetExtension(AName);
  Result := TPath.Combine(Dir, Base + Ext);
  N := 1;
  while TFile.Exists(Result) or TDirectory.Exists(Result) do
  begin
    Result := TPath.Combine(Dir, Format('%s_%d%s', [Base, N, Ext]));
    Inc(N);
  end;
end;

function UniqueTempDir: string;
var
  N: Integer;
begin
  N := 1;
  repeat
    Result := TPath.Combine(NestDir, 'x' + IntToHex(GetTickCount, 8) + '_' + IntToStr(N));
    Inc(N);
  until not TDirectory.Exists(Result);
  ForceDirectories(Result);
end;

{$IFDEF MSWINDOWS}
function ReplaceFileW(lpReplacedFileName, lpReplacementFileName, lpBackupFileName: LPCWSTR;
  dwReplaceFlags: DWORD; lpExclude, lpReserved: Pointer): BOOL; stdcall;
  external kernel32 name 'ReplaceFileW';
{$ENDIF}

procedure DeleteFileSilent(const APath: string);
begin
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    TFile.SetAttributes(APath, []);
    TFile.Delete(APath);
  except
  end;
end;

procedure ReplaceFileAtomic(const ADest, ATemp: string);
var
  Bak: string;
  Attempt: Integer;
  LastErr: string;

  function TryOnce: Boolean;
  begin
    if not TFile.Exists(ADest) then
    begin
      TFile.Move(ATemp, ADest);
      Exit(True);
    end;
    Bak := ADest + '.bak~';
    DeleteFileSilent(Bak);
{$IFDEF MSWINDOWS}
    try
      TFile.SetAttributes(ADest, []);
    except
    end;
    if ReplaceFileW(PChar(ADest), PChar(ATemp), PChar(Bak), 1, nil, nil) then
    begin
      DeleteFileSilent(Bak);
      DeleteFileSilent(ATemp);
      Exit(True);
    end;
    if MoveFileEx(PChar(ATemp), PChar(ADest), MOVEFILE_REPLACE_EXISTING or
       MOVEFILE_WRITE_THROUGH or MOVEFILE_COPY_ALLOWED) then
      Exit(True);
{$ENDIF}
    TFile.SetAttributes(ADest, []);
    TFile.Delete(ADest);
    TFile.Move(ATemp, ADest);
    Result := True;
  end;

begin
  if not TFile.Exists(ATemp) then
    raise Exception.Create('Нет временного файла архива');
  LastErr := '';
  for Attempt := 1 to 10 do
  begin
    try
      if TryOnce then
        Exit;
    except
      on E: Exception do
      begin
        LastErr := E.Message;
        if Attempt = 10 then
          raise Exception.Create('Не удалось заменить архив (файл занят): ' +
            ADest + sLineBreak + LastErr);
      end;
    end;
    Sleep(40 * Attempt);
  end;
  if LastErr <> '' then
    raise Exception.Create('Не удалось заменить архив (файл занят): ' +
      ADest + sLineBreak + LastErr)
  else
    raise Exception.Create('Не удалось заменить архив (файл занят): ' + ADest);
end;

function QuoteArg(const S: string): string;
begin
  if (Pos(' ', S) > 0) or (Pos('"', S) > 0) then
    Result := '"' + StringReplace(S, '"', '\"', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

function FindSevenZipExe: string;
var
  Cands: TArray<string>;
  S, Pf, Pfx, App: string;
{$IFDEF MSWINDOWS}
  function RegPath(ARoot: HKEY; const AKey, AVal: string): string;
  var
    K: HKEY;
    Buf: array[0..MAX_PATH] of Char;
    Sz, Typ: DWORD;
  begin
    Result := '';
    if RegOpenKeyEx(ARoot, PChar(AKey), 0, KEY_READ, K) <> 0 then
      Exit;
    try
      Sz := SizeOf(Buf);
      Typ := 0;
      if (RegQueryValueEx(K, PChar(AVal), nil, @Typ, @Buf[0], @Sz) = 0) and
         (Typ = REG_SZ) then
        Result := IncludeTrailingPathDelimiter(PChar(@Buf[0]));
    finally
      RegCloseKey(K);
    end;
  end;
{$ENDIF}
begin
  if G7zTried then
    Exit(G7zExe);
  G7zTried := True;
  G7zExe := '';
  App := ExtractFilePath(ParamStr(0));
  Pf := GetEnvironmentVariable('ProgramFiles');
  Pfx := GetEnvironmentVariable('ProgramFiles(x86)');
  Cands := [
    TPath.Combine(App, '7z.exe'),
    TPath.Combine(App, '7za.exe'),
    TPath.Combine(App, '7-Zip\7z.exe'),
    TPath.Combine(Pfx, '7-Zip\7z.exe'),
    TPath.Combine(Pf, '7-Zip\7z.exe'),
    'C:\Program Files\7-Zip\7z.exe',
    'C:\Program Files (x86)\7-Zip\7z.exe'
  ];
{$IFDEF MSWINDOWS}
  S := RegPath(HKEY_CURRENT_USER, 'Software\7-Zip', 'Path');
  if S <> '' then
  begin
    SetLength(Cands, Length(Cands) + 2);
    Cands[High(Cands) - 1] := TPath.Combine(S, '7z.exe');
    Cands[High(Cands)] := TPath.Combine(S, '7za.exe');
  end;
  S := RegPath(HKEY_LOCAL_MACHINE, 'Software\7-Zip', 'Path');
  if S <> '' then
  begin
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := TPath.Combine(S, '7z.exe');
  end;
  S := RegPath(HKEY_LOCAL_MACHINE, 'Software\WOW6432Node\7-Zip', 'Path');
  if S <> '' then
  begin
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := TPath.Combine(S, '7z.exe');
  end;
{$ENDIF}
  for S in Cands do
    if (S <> '') and TFile.Exists(S) then
    begin
      G7zExe := S;
      Break;
    end;
  Result := G7zExe;
end;

function SevenZipAvailable: Boolean;
begin
  Result := FindSevenZipExe <> '';
end;

{$IFDEF MSWINDOWS}
function RunHidden(const AExe, ACmd: string; AOutStream: TStream;
  out AText: string; ATimeoutMs: Integer): Integer;
var
  Sa: TSecurityAttributes;
  Si: TStartupInfo;
  Pi: TProcessInformation;
  OutR, OutW, ErrR, ErrW: THandle;
  Cmd: string;
  Avail, Got: DWORD;
  Buf: array[0..16383] of Byte;
  Text: TMemoryStream;
  El: Cardinal;
  ExitCode: DWORD;
begin
  Result := -1;
  AText := '';
  FillChar(Sa, SizeOf(Sa), 0);
  Sa.nLength := SizeOf(Sa);
  Sa.bInheritHandle := True;
  OutR := 0; OutW := 0; ErrR := 0; ErrW := 0;
  if not CreatePipe(OutR, OutW, @Sa, 0) then
    Exit;
  if not CreatePipe(ErrR, ErrW, @Sa, 0) then
  begin
    CloseHandle(OutR);
    CloseHandle(OutW);
    Exit;
  end;
  SetHandleInformation(OutR, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(ErrR, HANDLE_FLAG_INHERIT, 0);
  FillChar(Si, SizeOf(Si), 0);
  Si.cb := SizeOf(Si);
  Si.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  Si.wShowWindow := SW_HIDE;
  Si.hStdOutput := OutW;
  Si.hStdError := ErrW;
  Si.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  Cmd := ACmd;
  UniqueString(Cmd);
  FillChar(Pi, SizeOf(Pi), 0);
  if not CreateProcess(PChar(AExe), PChar(Cmd), nil, nil, True,
     CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT, nil, nil, Si, Pi) then
  begin
    CloseHandle(OutR); CloseHandle(OutW);
    CloseHandle(ErrR); CloseHandle(ErrW);
    Exit;
  end;
  CloseHandle(OutW);
  CloseHandle(ErrW);
  CloseHandle(Pi.hThread);
  Text := TMemoryStream.Create;
  try
    El := GetTickCount;
    repeat
      ArcCheckWait;
      Avail := 0;
      if PeekNamedPipe(OutR, nil, 0, nil, @Avail, nil) and (Avail > 0) then
      begin
        if Avail > SizeOf(Buf) then
          Avail := SizeOf(Buf);
        if ReadFile(OutR, Buf[0], Avail, Got, nil) and (Got > 0) then
        begin
          if AOutStream <> nil then
            AOutStream.WriteBuffer(Buf[0], Got)
          else
            Text.WriteBuffer(Buf[0], Got);
        end;
      end;
      Avail := 0;
      if PeekNamedPipe(ErrR, nil, 0, nil, @Avail, nil) and (Avail > 0) then
      begin
        if Avail > SizeOf(Buf) then
          Avail := SizeOf(Buf);
        if ReadFile(ErrR, Buf[0], Avail, Got, nil) and (Got > 0) then
          Text.WriteBuffer(Buf[0], Got);
      end;
      if WaitForSingleObject(Pi.hProcess, 30) = WAIT_OBJECT_0 then
      begin
        while PeekNamedPipe(OutR, nil, 0, nil, @Avail, nil) and (Avail > 0) do
        begin
          if Avail > SizeOf(Buf) then
            Avail := SizeOf(Buf);
          if not ReadFile(OutR, Buf[0], Avail, Got, nil) or (Got = 0) then
            Break;
          if AOutStream <> nil then
            AOutStream.WriteBuffer(Buf[0], Got)
          else
            Text.WriteBuffer(Buf[0], Got);
        end;
        Break;
      end;
      if (ATimeoutMs > 0) and (GetTickCount - El > Cardinal(ATimeoutMs)) then
      begin
        TerminateProcess(Pi.hProcess, 1);
        Break;
      end;
    until False;
    ExitCode := 1;
    GetExitCodeProcess(Pi.hProcess, ExitCode);
    Result := Integer(ExitCode);
    if (AOutStream = nil) and (Text.Size > 0) then
    begin
      SetString(AText, PAnsiChar(Text.Memory), Text.Size);
      AText := UTF8ToString(RawByteString(AText));
      if Pos(#0, AText) > 0 then
        AText := '';
    end
    else if Text.Size > 0 then
    begin
      SetString(AText, PAnsiChar(Text.Memory), Text.Size);
      AText := UTF8ToString(RawByteString(AText));
    end;
  finally
    Text.Free;
    CloseHandle(OutR);
    CloseHandle(ErrR);
    CloseHandle(Pi.hProcess);
  end;
end;
{$ENDIF}

function Run7z(const AArgs: string; out AText: string): Integer;
var
  Exe, Cmd: string;
begin
  Exe := FindSevenZipExe;
  if Exe = '' then
    raise Exception.Create('Для 7Z/RAR установите 7-Zip (7z.exe)');
  Cmd := QuoteArg(Exe) + ' ' + AArgs;
{$IFDEF MSWINDOWS}
  Result := RunHidden(Exe, Cmd, nil, AText, 30 * 60 * 1000);
{$ELSE}
  Result := -1;
  AText := '';
{$ENDIF}
end;

function Run7zToFile(const AArgs, AOutFile: string): Integer;
var
  Exe, Cmd, Err: string;
  FS: TFileStream;
begin
  Exe := FindSevenZipExe;
  if Exe = '' then
    raise Exception.Create('Для 7Z/RAR установите 7-Zip (7z.exe)');
  Cmd := QuoteArg(Exe) + ' ' + AArgs;
  FS := TFileStream.Create(AOutFile, fmCreate);
  try
{$IFDEF MSWINDOWS}
    Result := RunHidden(Exe, Cmd, FS, Err, 30 * 60 * 1000);
{$ELSE}
    Result := -1;
{$ENDIF}
  finally
    FS.Free;
  end;
  if (Result <> 0) and (Err <> '') then
    raise Exception.Create(Trim(Err));
end;

function Need7z(AKind: TArchiveKind): Boolean;
begin
  Result := AKind in [akSevenZ, akRar, akOther];
end;

procedure Ensure7z(AKind: TArchiveKind);
begin
  if Need7z(AKind) and not SevenZipAvailable then
    raise Exception.Create('Для открытия ' + ArchiveKindCaption(AKind) +
      ' установите 7-Zip (https://www.7-zip.org)');
end;

function OpenZip(const APath: string; AWrite, ACreate: Boolean): TZipFile;
var
  Z: TOwnedZip;
  ZMode: TZipMode;
  Stm: TStream;
  CreateNew: Boolean;
begin
  Z := TOwnedZip.Create;
  try
    Z.UTF8Support := True;
    CreateNew := ACreate or not TFile.Exists(APath);
    if CreateNew then
      ZMode := zmWrite
    else if AWrite then
      ZMode := zmReadWrite
    else
      ZMode := zmRead;
    Stm := OpenSharedFileStream(APath, AWrite or CreateNew, CreateNew);
    try
      Z.OpenOwned(Stm, ZMode);
    except
      Stm.Free;
      raise;
    end;
  except
    Z.Free;
    raise;
  end;
  Result := Z;
end;

function ZipIndexOf(Zip: TZipFile; const AInner: string): Integer;
var
  I: Integer;
  Want, Have: string;
begin
  Want := ArcNorm(AInner);
  Result := Zip.IndexOf(Want);
  if Result >= 0 then
    Exit;
  Result := Zip.IndexOf(StringReplace(Want, '/', '\', [rfReplaceAll]));
  if Result >= 0 then
    Exit;
  Result := Zip.IndexOf(Want + '/');
  if Result >= 0 then
    Exit;
  for I := 0 to Zip.FileCount - 1 do
  begin
    Have := ArcNorm(Zip.FileName[I]);
    if SameText(Have, Want) or SameText(Have, Want + '/') then
      Exit(I);
  end;
  Result := -1;
end;

function ItemModifiedFromZip(Zip: TZipFile; AIndex: Integer): TDateTime;
begin
  Result := 0;
  try
    Result := Zip.FileInfo[AIndex].ModifiedTime;
  except
    Result := 0;
  end;
end;

function ListZipItems(const AZip: string): TArray<TArcItem>;
var
  Zip: TZipFile;
  I, N: Integer;
  Name: string;
  It: TArcItem;
  Seen: TStringList;
  Pfx, Rest: string;
  Slash: Integer;
begin
  SetLength(Result, 0);
  if not TFile.Exists(AZip) then
    Exit;
  Zip := nil;
  Seen := nil;
  BeginArchiveAccess(AZip);
  try
    Zip := OpenZip(AZip, False, False);
    Seen := TStringList.Create;
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    Seen.CaseSensitive := False;
    N := 0;
    for I := 0 to Zip.FileCount - 1 do
    begin
      ArcCheckWait;
      Name := ArcNorm(Zip.FileName[I]);
      if Name = '' then
        Continue;
      It := Default(TArcItem);
      It.Path := Name;
      It.IsDir := EndsText('/', ArcRaw(Zip.FileName[I])) or
        (TFileAttribute.faDirectory in Zip.FileInfo[I].FileAttributes);
      if not It.IsDir then
      begin
        It.Size := Zip.FileInfo[I].UncompressedSize64;
        It.PackedSize := Zip.FileInfo[I].CompressedSize64;
      end;
      It.Modified := ItemModifiedFromZip(Zip, I);
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := It;
      Pfx := Name;
      repeat
        Slash := LastDelimiter('/', Pfx);
        if Slash <= 0 then
          Break;
        Pfx := Copy(Pfx, 1, Slash - 1);
        if Pfx = '' then
          Break;
        Seen.Add(Pfx);
      until False;
    end;
    for I := 0 to Seen.Count - 1 do
    begin
      Rest := Seen[I];
      It := Default(TArcItem);
      It.Path := Rest;
      It.IsDir := True;
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := It;
    end;
  finally
    Seen.Free;
    Zip.Free;
    EndArchiveAccess(AZip);
  end;
end;

function ParseOctal(const S: RawByteString): Int64;
var
  I: Integer;
  C: Byte;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    C := Byte(S[I]);
    if C = 0 then
      Break;
    if C = 32 then
      Continue;
    if (C < Ord('0')) or (C > Ord('7')) then
      Break;
    Result := Result * 8 + (C - Ord('0'));
  end;
end;

function ParseTarSize(const Fld: RawByteString): Int64;
var
  I: Integer;
  V: UInt64;
begin
  if (Length(Fld) > 0) and ((Byte(Fld[1]) and $80) <> 0) then
  begin
    V := Byte(Fld[1]) and $7F;
    for I := 2 to Length(Fld) do
      V := (V shl 8) or Byte(Fld[I]);
    Result := Int64(V);
  end
  else
    Result := ParseOctal(Fld);
end;

function RawToName(const Fld: RawByteString): string;
var
  N: Integer;
begin
  N := 0;
  while (N < Length(Fld)) and (Byte(Fld[N + 1]) <> 0) do
    Inc(N);
  Result := UTF8ToString(Copy(Fld, 1, N));
  if Result = '' then
    Result := string(Copy(Fld, 1, N));
end;

function SkipGzipHeader(AStm: TStream; out AOrig: string): Boolean;
var
  Id1, Id2, Cm, Flg, B: Byte;
  Xlen: Word;
  Mtime: Cardinal;
  Name: RawByteString;
begin
  Result := False;
  AOrig := '';
  if AStm.Read(Id1, 1) <> 1 then Exit;
  if AStm.Read(Id2, 1) <> 1 then Exit;
  if AStm.Read(Cm, 1) <> 1 then Exit;
  if AStm.Read(Flg, 1) <> 1 then Exit;
  if (Id1 <> $1F) or (Id2 <> $8B) or (Cm <> 8) then
    Exit;
  if AStm.Read(Mtime, 4) <> 4 then Exit;
  AStm.Read(B, 1);
  AStm.Read(B, 1);
  if (Flg and 4) <> 0 then
  begin
    if AStm.Read(Xlen, 2) <> 2 then Exit;
    AStm.Seek(Xlen, soCurrent);
  end;
  if (Flg and 8) <> 0 then
  begin
    Name := '';
    repeat
      if AStm.Read(B, 1) <> 1 then Exit;
      if B <> 0 then
        Name := Name + AnsiChar(B);
    until B = 0;
    AOrig := UTF8ToString(Name);
    if AOrig = '' then
      AOrig := string(Name);
  end;
  if (Flg and 16) <> 0 then
    repeat
      if AStm.Read(B, 1) <> 1 then Exit;
    until B = 0;
  if (Flg and 2) <> 0 then
    AStm.Seek(2, soCurrent);
  Result := True;
end;

function ListTarStream(AStm: TStream): TArray<TArcItem>;
var
  Hdr: array[0..511] of Byte;
  N, Got: Integer;
  Name, Prefix, LongName, PaxName: string;
  TypeFlag: AnsiChar;
  Size, Skip: Int64;
  Mtime: Int64;
  It: TArcItem;
  Zero: Boolean;
  I: Integer;
  Raw: RawByteString;
begin
  SetLength(Result, 0);
  N := 0;
  LongName := '';
  PaxName := '';
  while True do
  begin
    ArcCheckWait;
    Got := AStm.Read(Hdr[0], 512);
    if Got < 512 then
      Break;
    Zero := True;
    for I := 0 to 511 do
      if Hdr[I] <> 0 then
      begin
        Zero := False;
        Break;
      end;
    if Zero then
      Break;
    SetString(Raw, PAnsiChar(@Hdr[0]), 100);
    Name := RawToName(Raw);
    SetString(Raw, PAnsiChar(@Hdr[345]), 155);
    Prefix := RawToName(Raw);
    if (Prefix <> '') and (Name <> '') then
      Name := Prefix + '/' + Name;
    TypeFlag := AnsiChar(Hdr[156]);
    SetString(Raw, PAnsiChar(@Hdr[124]), 12);
    Size := ParseTarSize(Raw);
    SetString(Raw, PAnsiChar(@Hdr[136]), 12);
    Mtime := ParseOctal(Raw);
    if LongName <> '' then
    begin
      Name := LongName;
      LongName := '';
    end;
    if PaxName <> '' then
    begin
      Name := PaxName;
      PaxName := '';
    end;
    Skip := (Size + 511) and not Int64(511);
    if (TypeFlag = 'L') or (TypeFlag = 'x') or (TypeFlag = 'g') then
    begin
      if Size > 0 then
      begin
        SetLength(Raw, Size);
        if AStm.Read(Raw[1], Size) = Size then
        begin
          if TypeFlag = 'L' then
            LongName := ArcNorm(RawToName(Raw))
          else
            PaxName := ArcNorm(RawToName(Raw));
        end;
        if Skip > Size then
          AStm.Seek(Skip - Size, soCurrent);
      end;
      Continue;
    end;
    if (TypeFlag = 'K') or (TypeFlag = '1') or (TypeFlag = '2') or
       (TypeFlag = '3') or (TypeFlag = '4') or (TypeFlag = '6') then
    begin
      if Skip > 0 then
        AStm.Seek(Skip, soCurrent);
      Continue;
    end;
    Name := ArcNorm(Name);
    if Name <> '' then
    begin
      It := Default(TArcItem);
      It.Path := Name;
      It.IsDir := (TypeFlag = '5') or EndsText('/', Name);
      It.Size := Size;
      if Mtime > 0 then
      try
        It.Modified := UnixToDateTime(Mtime, False);
      except
        It.Modified := 0;
      end;
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := It;
    end;
    if (not (TypeFlag = '5')) and (Skip > 0) then
      AStm.Seek(Skip, soCurrent);
  end;
end;

function ListTarFile(const APath: string): TArray<TArcItem>;
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := ListTarStream(FS);
  finally
    FS.Free;
  end;
end;

function ListGzItems(const APath: string): TArray<TArcItem>;
var
  FS: TFileStream;
  Name: string;
  It: TArcItem;
begin
  SetLength(Result, 1);
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if not SkipGzipHeader(FS, Name) then
      Name := '';
  finally
    FS.Free;
  end;
  if Name = '' then
  begin
    Name := TPath.GetFileNameWithoutExtension(APath);
    if EndsText('.tar', LowerCase(Name)) then
      Name := ChangeFileExt(Name, '');
    if Name = '' then
      Name := 'data';
  end;
  It := Default(TArcItem);
  It.Path := ArcNorm(ExtractFileName(Name));
  It.IsDir := False;
  try
    It.Size := TFile.GetSize(APath);
  except
    It.Size := 0;
  end;
  try
    It.Modified := TFile.GetLastWriteTime(APath);
  except
  end;
  Result[0] := It;
end;

function ListTgzItems(const APath: string): TArray<TArcItem>;
var
  FS: TFileStream;
  Name: string;
  Z: TZDecompressionStream;
begin
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if not SkipGzipHeader(FS, Name) then
    begin
      FS.Position := 0;
      Z := TZDecompressionStream.Create(FS, 15 + 16);
    end
    else
      Z := TZDecompressionStream.Create(FS, -15);
    try
      Result := ListTarStream(Z);
    finally
      Z.Free;
    end;
  finally
    FS.Free;
  end;
end;

function Parse7zList(const AText: string): TArray<TArcItem>;
var
  Lines: TArray<string>;
  I, N: Integer;
  Line, Key, Val, Path: string;
  It: TArcItem;
  Have: Boolean;

  procedure Flush;
  begin
    if not Have or (Path = '') then
      Exit;
    It.Path := ArcNorm(Path);
    Inc(N);
    SetLength(Result, N);
    Result[N - 1] := It;
    Have := False;
    Path := '';
    It := Default(TArcItem);
  end;

  function AfterEq(const S: string): string;
  var
    P: Integer;
  begin
    P := Pos('=', S);
    if P > 0 then
      Result := Trim(Copy(S, P + 1, MaxInt))
    else
      Result := '';
  end;
begin
  SetLength(Result, 0);
  N := 0;
  Have := False;
  Path := '';
  It := Default(TArcItem);
  Lines := AText.Split([#13#10, #10]);
  for I := 0 to High(Lines) do
  begin
    Line := Trim(Lines[I]);
    if Line = '' then
    begin
      Flush;
      Continue;
    end;
    Key := LowerCase(Trim(Copy(Line, 1, Pos('=', Line) - 1)));
    Val := AfterEq(Line);
    if Key = 'path' then
    begin
      Flush;
      Path := Val;
      Have := True;
    end
    else if Key = 'folder' then
      It.IsDir := (Val = '+') or SameText(Val, 'true')
    else if Key = 'size' then
      It.Size := StrToInt64Def(Val, 0)
    else if (Key = 'packed size') or (Key = 'packedsize') then
      It.PackedSize := StrToInt64Def(Val, 0)
    else if Key = 'modified' then
    try
      It.Modified := EncodeDateTime(
        StrToIntDef(Copy(Val, 1, 4), 1900),
        StrToIntDef(Copy(Val, 6, 2), 1),
        StrToIntDef(Copy(Val, 9, 2), 1),
        StrToIntDef(Copy(Val, 12, 2), 0),
        StrToIntDef(Copy(Val, 15, 2), 0),
        StrToIntDef(Copy(Val, 18, 2), 0), 0);
    except
      It.Modified := 0;
    end
    else if Key = 'encrypted' then
      It.Encrypted := (Val = '+') or SameText(Val, 'true')
    else if Key = 'attributes' then
      if (Pos('D', Val) > 0) and (Pos('D', Val) <= 5) then
        It.IsDir := True;
  end;
  Flush;
end;

function List7zItems(const APath: string): TArray<TArcItem>;
var
  Text: string;
  Code: Integer;
begin
  Code := Run7z('l -slt -ba -sccUTF-8 -- ' + QuoteArg(APath), Text);
  if Code <> 0 then
    raise Exception.Create('Не удалось прочитать архив: ' + ExtractFileName(APath) +
      sLineBreak + Trim(Text));
  Result := Parse7zList(Text);
end;

function LoadItemsUncached(const APhysical: string; AKind: TArchiveKind): TArray<TArcItem>;
begin
  case AKind of
    akZip: Result := ListZipItems(APhysical);
    akTar: Result := ListTarFile(APhysical);
    akGz: Result := ListGzItems(APhysical);
    akTgz: Result := ListTgzItems(APhysical);
    akSevenZ, akRar, akOther:
      begin
        Ensure7z(AKind);
        Result := List7zItems(APhysical);
      end;
  else
    SetLength(Result, 0);
  end;
end;

function GetItems(const APhysical: string; AKind: TArchiveKind): TArray<TArcItem>;
var
  Key: string;
  Ent: TCacheEnt;
  Sz: Int64;
  Mt: TDateTime;
begin
  Key := CacheKey(APhysical);
  FileStamp(APhysical, Sz, Mt);
  GLock.Enter;
  try
    if GCache.TryGetValue(Key, Ent) then
      if (Ent.Size = Sz) and (Abs(Ent.MTime - Mt) < (1 / 86400)) then
        Exit(Ent.Items);
  finally
    GLock.Leave;
  end;
  Result := LoadItemsUncached(APhysical, AKind);
  GLock.Enter;
  try
    if GCache.TryGetValue(Key, Ent) then
      GCache.Remove(Key);
    Ent := TCacheEnt.Create;
    Ent.Path := APhysical;
    Ent.Size := Sz;
    Ent.MTime := Mt;
    Ent.Items := Result;
    GCache.Add(Key, Ent);
  finally
    GLock.Leave;
  end;
end;

function FindItem(const AItems: TArray<TArcItem>; const AInner: string;
  out AItem: TArcItem): Boolean;
var
  Want: string;
  I: Integer;
begin
  Want := ArcNorm(AInner);
  AItem := Default(TArcItem);
  if Want = '' then
  begin
    AItem.IsDir := True;
    Exit(True);
  end;
  for I := 0 to High(AItems) do
    if SameText(AItems[I].Path, Want) then
    begin
      AItem := AItems[I];
      Exit(True);
    end;
  for I := 0 to High(AItems) do
    if StartsText(Want + '/', AItems[I].Path) then
    begin
      AItem.Path := Want;
      AItem.IsDir := True;
      Exit(True);
    end;
  Result := False;
end;

function ItemIsArchiveFile(const AItem: TArcItem): Boolean;
begin
  Result := (not AItem.IsDir) and IsArchiveFileName(AItem.Path);
end;

procedure ExtractOneZip(const AZip, AInner, AOutFile: string);
var
  Zip: TZipFile;
  Idx: Integer;
  Stm: TStream;
  Hdr: TZipHeader;
  FS: TFileStream;
  W: TWatchStream;
begin
  ForceDirectories(ExtractFilePath(AOutFile));
  Zip := nil;
  BeginArchiveAccess(AZip);
  try
    Zip := OpenZip(AZip, False, False);
    Idx := ZipIndexOf(Zip, AInner);
    if Idx < 0 then
      raise Exception.Create('Нет в архиве: ' + AInner);
    Zip.Read(Idx, Stm, Hdr);
    try
      FS := TFileStream.Create(AOutFile, fmCreate);
      try
        W := TWatchStream.Create(FS, False, AInner);
        try
          if Stm.Size > 0 then
            W.CopyFrom(Stm, 0)
          else if Zip.FileInfo[Idx].UncompressedSize64 > 0 then
            W.CopyFrom(Stm, Zip.FileInfo[Idx].UncompressedSize64);
        finally
          W.Free;
        end;
      finally
        FS.Free;
      end;
    finally
      Stm.Free;
    end;
    try
      if ItemModifiedFromZip(Zip, Idx) > 0 then
        TFile.SetLastWriteTime(AOutFile, ItemModifiedFromZip(Zip, Idx));
    except
    end;
  finally
    Zip.Free;
    EndArchiveAccess(AZip);
  end;
end;

procedure ExtractOneTarLike(AStm: TStream; const AInner, AOutFile: string);
var
  Hdr: array[0..511] of Byte;
  Name, Prefix, LongName, PaxName: string;
  TypeFlag: AnsiChar;
  Size, Skip, Left, N: Int64;
  Got: Integer;
  I: Integer;
  Zero: Boolean;
  Raw: RawByteString;
  FS: TFileStream;
  Buf: TBytes;
  Want: string;
begin
  Want := ArcNorm(AInner);
  LongName := '';
  PaxName := '';
  SetLength(Buf, CHUNK);
  while True do
  begin
    ArcCheckWait;
    Got := AStm.Read(Hdr[0], 512);
    if Got < 512 then
      Break;
    Zero := True;
    for I := 0 to 511 do
      if Hdr[I] <> 0 then
      begin
        Zero := False;
        Break;
      end;
    if Zero then
      Break;
    SetString(Raw, PAnsiChar(@Hdr[0]), 100);
    Name := RawToName(Raw);
    SetString(Raw, PAnsiChar(@Hdr[345]), 155);
    Prefix := RawToName(Raw);
    if (Prefix <> '') and (Name <> '') then
      Name := Prefix + '/' + Name;
    TypeFlag := AnsiChar(Hdr[156]);
    SetString(Raw, PAnsiChar(@Hdr[124]), 12);
    Size := ParseTarSize(Raw);
    Skip := (Size + 511) and not Int64(511);
    if LongName <> '' then
    begin
      Name := LongName;
      LongName := '';
    end;
    if PaxName <> '' then
    begin
      Name := PaxName;
      PaxName := '';
    end;
    if (TypeFlag = 'L') or (TypeFlag = 'x') or (TypeFlag = 'g') then
    begin
      if Size > 0 then
      begin
        SetLength(Raw, Size);
        AStm.Read(Raw[1], Size);
        if TypeFlag = 'L' then
          LongName := ArcNorm(RawToName(Raw))
        else
          PaxName := ArcNorm(RawToName(Raw));
        if Skip > Size then
          AStm.Seek(Skip - Size, soCurrent);
      end;
      Continue;
    end;
    Name := ArcNorm(Name);
    if SameText(Name, Want) and (TypeFlag <> '5') then
    begin
      ForceDirectories(ExtractFilePath(AOutFile));
      FS := TFileStream.Create(AOutFile, fmCreate);
      try
        Left := Size;
        while Left > 0 do
        begin
          ArcCheckWait;
          N := Left;
          if N > Length(Buf) then
            N := Length(Buf);
          Got := AStm.Read(Buf[0], N);
          if Got <= 0 then
            Break;
          FS.WriteBuffer(Buf[0], Got);
          ArcProgress(AInner, Got, Size);
          Dec(Left, Got);
        end;
      finally
        FS.Free;
      end;
      if Skip > Size then
        AStm.Seek(Skip - Size, soCurrent);
      Exit;
    end;
    if Skip > 0 then
      AStm.Seek(Skip, soCurrent);
  end;
  raise Exception.Create('Нет в архиве: ' + AInner);
end;

procedure CopyInflated(ASrc, ADst: TStream);
var
  Buf: TBytes;
  N: Integer;
begin
  SetLength(Buf, CHUNK);
  repeat
    ArcCheckWait;
    N := ASrc.Read(Buf[0], Length(Buf));
    if N <= 0 then
      Break;
    ADst.WriteBuffer(Buf[0], N);
    ArcProgress('gz', N, 0);
  until False;
end;

procedure ExtractOneNative(const APhysical: string; AKind: TArchiveKind;
  const AInner, AOutFile: string);
var
  FS, FSOut: TFileStream;
  Z: TZDecompressionStream;
  Name: string;
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  case AKind of
    akZip:
      ExtractOneZip(APhysical, AInner, AOutFile);
    akTar:
      begin
        FS := TFileStream.Create(APhysical, fmOpenRead or fmShareDenyNone);
        try
          ExtractOneTarLike(FS, AInner, AOutFile);
        finally
          FS.Free;
        end;
      end;
    akTgz:
      begin
        FS := TFileStream.Create(APhysical, fmOpenRead or fmShareDenyNone);
        try
          if not SkipGzipHeader(FS, Name) then
          begin
            FS.Position := 0;
            Z := TZDecompressionStream.Create(FS, 15 + 16);
          end
          else
            Z := TZDecompressionStream.Create(FS, -15);
          try
            ExtractOneTarLike(Z, AInner, AOutFile);
          finally
            Z.Free;
          end;
        finally
          FS.Free;
        end;
      end;
    akGz:
      begin
        Items := GetItems(APhysical, akGz);
        if not FindItem(Items, AInner, It) and (AInner <> '') then
          if (Length(Items) = 1) and SameText(ArcLeaf(AInner), Items[0].Path) then
            It := Items[0]
          else
            raise Exception.Create('Нет в архиве: ' + AInner);
        ForceDirectories(ExtractFilePath(AOutFile));
        FS := TFileStream.Create(APhysical, fmOpenRead or fmShareDenyNone);
        try
          if not SkipGzipHeader(FS, Name) then
          begin
            FS.Position := 0;
            Z := TZDecompressionStream.Create(FS, 15 + 16);
          end
          else
            Z := TZDecompressionStream.Create(FS, -15);
          try
            FSOut := TFileStream.Create(AOutFile, fmCreate);
            try
              CopyInflated(Z, FSOut);
            finally
              FSOut.Free;
            end;
          finally
            Z.Free;
          end;
        finally
          FS.Free;
        end;
      end;
  else
    raise Exception.Create('Формат не поддержан нативно');
  end;
end;

procedure ExtractOne7z(const APhysical, AInner, AOutFile: string);
var
  Tmp, Found, Leaf: string;
  Code: Integer;
  Text: string;
begin
  Leaf := ArcLeaf(AInner);
  Tmp := UniqueTempDir;
  try
    Code := Run7z('x -y -aoa -sccUTF-8 -o' + QuoteArg(Tmp) + ' -- ' +
      QuoteArg(APhysical) + ' ' + QuoteArg(StringReplace(AInner, '/', '\', [rfReplaceAll])), Text);
    if Code <> 0 then
      raise Exception.Create('Не удалось извлечь: ' + Leaf + sLineBreak + Trim(Text));
    Found := TPath.Combine(Tmp, StringReplace(AInner, '/', PathDelim, [rfReplaceAll]));
    if not TFile.Exists(Found) then
      Found := TPath.Combine(Tmp, Leaf);
    if not TFile.Exists(Found) then
      raise Exception.Create('Не удалось извлечь: ' + Leaf);
    ForceDirectories(ExtractFilePath(AOutFile));
    if TFile.Exists(AOutFile) then
      TFile.Delete(AOutFile);
    TFile.Copy(Found, AOutFile, True);
  finally
    try
      TDirectory.Delete(Tmp, True);
    except
    end;
  end;
end;

procedure ExtractOne(const APhysical: string; AKind: TArchiveKind;
  const AInner, AOutFile: string);
begin
  ArcCheckWait;
  if Need7z(AKind) then
  begin
    Ensure7z(AKind);
    ExtractOne7z(APhysical, AInner, AOutFile);
  end
  else
    ExtractOneNative(APhysical, AKind, AInner, AOutFile);
end;

function NestKey(const APhysical, AInner: string): string;
begin
  Result := CacheKey(APhysical) + '|' + LowerCase(ArcNorm(AInner));
end;

function MaterializeInnerArchive(const APhysical: string; AKind: TArchiveKind;
  const AInner: string): string;
var
  Key, Tmp, Leaf: string;
  Sz: Int64;
  Mt: TDateTime;
begin
  Key := NestKey(APhysical, AInner);
  GLock.Enter;
  try
    if GNest.TryGetValue(Key, Tmp) and TFile.Exists(Tmp) then
    begin
      if FileStamp(APhysical, Sz, Mt) then
        Exit(Tmp);
    end;
  finally
    GLock.Leave;
  end;
  Leaf := ArcLeaf(AInner);
  if Leaf = '' then
    Leaf := 'nested.bin';
  Tmp := UniqueTempFile(Leaf);
  ExtractOne(APhysical, AKind, AInner, Tmp);
  GLock.Enter;
  try
    GNest.AddOrSetValue(Key, Tmp);
    GNestSrc.AddOrSetValue(Key, CacheKey(APhysical) + '|');
  finally
    GLock.Leave;
  end;
  Result := Tmp;
end;

function ResolvePath(const APath: string): TArcRef;
var
  Disk, Rest, Acc, Next, TryPath: string;
  Items: TArray<TArcItem>;
  It: TArcItem;
  Slash: Integer;
begin
  Result := Default(TArcRef);
  if not SplitArchivePath(APath, Disk, Rest) then
    Exit;
  Result.DiskArchive := Disk;
  Result.Physical := Disk;
  Result.Kind := DetectArchiveKind(Disk);
  Result.Inner := ArcNorm(Rest);
  if Result.Kind = akNone then
    Exit;
  Rest := ArcNorm(Rest);
  while Rest <> '' do
  begin
    ArcCheckWait;
    Items := GetItems(Result.Physical, Result.Kind);
    Slash := Pos('/', Rest);
    if Slash > 0 then
    begin
      Next := Copy(Rest, 1, Slash - 1);
      Acc := Copy(Rest, Slash + 1, MaxInt);
    end
    else
    begin
      Next := Rest;
      Acc := '';
    end;
    TryPath := Next;
    if FindItem(Items, TryPath, It) and ItemIsArchiveFile(It) then
    begin
      Result.Physical := MaterializeInnerArchive(Result.Physical, Result.Kind, TryPath);
      Result.Kind := DetectArchiveKind(Result.Physical);
      if Result.Kind = akNone then
        Result.Kind := DetectArchiveKind(TryPath);
      Result.Inner := Acc;
      Rest := Acc;
      Continue;
    end;
    if FindItem(Items, Result.Inner, It) and ItemIsArchiveFile(It) and (Acc = '') then
    begin
      Result.Physical := MaterializeInnerArchive(Result.Physical, Result.Kind, Result.Inner);
      Result.Kind := DetectArchiveKind(Result.Physical);
      if Result.Kind = akNone then
        Result.Kind := DetectArchiveKind(Result.Inner);
      Result.Inner := '';
      Rest := '';
      Break;
    end;
    Break;
  end;
end;

function ArchiveCanEnter(const APath: string): Boolean;
var
  Ref: TArcRef;
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  Result := False;
  if TDirectory.Exists(APath) then
    Exit(True);
  if TFile.Exists(APath) and IsArchiveFileName(APath) then
    Exit(True);
  Ref := ResolvePath(APath);
  if (Ref.Physical = '') or (Ref.Kind = akNone) then
    Exit;
  if Need7z(Ref.Kind) and not SevenZipAvailable then
    Exit(False);
  if Ref.Inner = '' then
    Exit(True);
  if IsArchiveFileName(APath) then
    Exit(True);
  try
    Items := GetItems(Ref.Physical, Ref.Kind);
    Result := FindItem(Items, Ref.Inner, It) and (It.IsDir or ItemIsArchiveFile(It));
  except
    Result := False;
  end;
end;

function ArchivePathIsFolder(const APath: string): Boolean;
var
  Ref: TArcRef;
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  Ref := ResolvePath(APath);
  if Ref.Physical = '' then
    Exit(False);
  if Ref.Inner = '' then
    Exit(True);
  Items := GetItems(Ref.Physical, Ref.Kind);
  Result := FindItem(Items, Ref.Inner, It) and It.IsDir;
end;

function ArchivePathExists(const APath: string): Boolean;
var
  Ref: TArcRef;
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  if TFile.Exists(APath) or TDirectory.Exists(APath) then
    Exit(True);
  Ref := ResolvePath(APath);
  if Ref.Physical = '' then
    Exit(False);
  if Ref.Inner = '' then
    Exit(TFile.Exists(Ref.Physical));
  Items := GetItems(Ref.Physical, Ref.Kind);
  Result := FindItem(Items, Ref.Inner, It);
end;

function ArchiveInvolved(const ASrc, ADestDir: string): Boolean;
var
  Z, I: string;
begin
  Result := False;
  if SplitArchivePath(ASrc, Z, I) and (I <> '') then
    Exit(True);
  if SplitArchivePath(ADestDir, Z, I) then
    Exit(True);
  if TFile.Exists(ADestDir) and IsArchiveFileName(ADestDir) then
    Exit(True);
end;

function ListArchiveChildren(const APath: string; out AChildren: TArray<TArcChild>): Boolean;
var
  Ref: TArcRef;
  Items: TArray<TArcItem>;
  I, N, Slash: Integer;
  Prefix, Rel, First: string;
  Child: TArcChild;
  Map: TDictionary<string, Integer>;
  Idx: Integer;
  It: TArcItem;
begin
  SetLength(AChildren, 0);
  Result := False;
  Ref := ResolvePath(APath);
  if (Ref.Physical = '') or (Ref.Kind = akNone) then
    Exit;
  if Need7z(Ref.Kind) then
    Ensure7z(Ref.Kind);
  Items := GetItems(Ref.Physical, Ref.Kind);
  if (Ref.Inner <> '') and FindItem(Items, Ref.Inner, It) and ItemIsArchiveFile(It) then
  begin
    Ref.Physical := MaterializeInnerArchive(Ref.Physical, Ref.Kind, Ref.Inner);
    Ref.Kind := DetectArchiveKind(Ref.Physical);
    Ref.Inner := '';
    Items := GetItems(Ref.Physical, Ref.Kind);
  end;
  Prefix := ArcNorm(Ref.Inner);
  if Prefix <> '' then
    Prefix := Prefix + '/';
  Map := TDictionary<string, Integer>.Create;
  try
    N := 0;
    for I := 0 to High(Items) do
    begin
      Rel := Items[I].Path;
      if Prefix <> '' then
      begin
        if not StartsText(Prefix, Rel) and not SameText(Rel, ArcNorm(Ref.Inner)) then
          Continue;
        if SameText(Rel, ArcNorm(Ref.Inner)) then
          Continue;
        Rel := Copy(Rel, Length(Prefix) + 1, MaxInt);
      end;
      if Rel = '' then
        Continue;
      Slash := Pos('/', Rel);
      if Slash > 0 then
      begin
        First := Copy(Rel, 1, Slash - 1);
        Child.Name := First;
        Child.IsDir := True;
        Child.Size := 0;
        Child.Modified := 0;
        Child.Encrypted := False;
      end
      else
      begin
        First := Rel;
        Child.Name := Rel;
        Child.IsDir := Items[I].IsDir;
        Child.Size := Items[I].Size;
        Child.Modified := Items[I].Modified;
        Child.Encrypted := Items[I].Encrypted;
      end;
      if First = '' then
        Continue;
      if Map.TryGetValue(LowerCase(First), Idx) then
      begin
        if Child.IsDir then
          AChildren[Idx].IsDir := True;
        Continue;
      end;
      Inc(N);
      SetLength(AChildren, N);
      AChildren[N - 1] := Child;
      Map.Add(LowerCase(First), N - 1);
    end;
    Result := True;
  finally
    Map.Free;
  end;
end;

function ListArchiveBranch(const APath: string): TArray<TArcItem>;
var
  Ref: TArcRef;
  Items: TArray<TArcItem>;
  I, N: Integer;
  Prefix: string;
begin
  SetLength(Result, 0);
  Ref := ResolvePath(APath);
  if Ref.Physical = '' then
    Exit;
  Items := GetItems(Ref.Physical, Ref.Kind);
  Prefix := ArcNorm(Ref.Inner);
  N := 0;
  for I := 0 to High(Items) do
  begin
    if Items[I].IsDir then
      Continue;
    if Prefix = '' then
    begin
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := Items[I];
    end
    else if SameText(Items[I].Path, Prefix) or StartsText(Prefix + '/', Items[I].Path) then
    begin
      Inc(N);
      SetLength(Result, N);
      Result[N - 1] := Items[I];
    end;
  end;
end;

function ScanArchivePath(const APath: string; out AFiles: Integer; out ABytes: Int64): Boolean;
var
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  AFiles := 0;
  ABytes := 0;
  Items := ListArchiveBranch(APath);
  if Length(Items) = 0 then
  begin
    if ArchivePathExists(APath) then
    begin
      AFiles := 1;
      Result := True;
    end
    else
      Result := False;
    Exit;
  end;
  for It in Items do
  begin
    Inc(AFiles);
    Inc(ABytes, It.Size);
  end;
  Result := True;
end;

function UniqueDiskName(const APath: string): string;
var
  Dir, Name, Ext: string;
  I: Integer;
begin
  Dir := ExtractFilePath(APath);
  Name := ChangeFileExt(ExtractFileName(APath), '');
  Ext := ExtractFileExt(APath);
  I := 2;
  repeat
    Result := TPath.Combine(Dir, Format('%s (%d)%s', [Name, I, Ext]));
    Inc(I);
  until not TFile.Exists(Result) and not TDirectory.Exists(Result);
end;

function UniqueInnerName(const AItems: TArray<TArcItem>; const AInner: string): string;
var
  Parent, Leaf, Ext, Base, Cand: string;
  I: Integer;
  It: TArcItem;
  function Taken(const S: string): Boolean;
  begin
    Result := FindItem(AItems, S, It);
  end;
begin
  Parent := ArcParent(AInner);
  Leaf := ArcLeaf(AInner);
  Ext := ExtractFileExt(Leaf);
  Base := ChangeFileExt(Leaf, '');
  I := 2;
  repeat
    Cand := ArcJoin(Parent, Format('%s (%d)%s', [Base, I, Ext]));
    Inc(I);
  until not Taken(Cand);
  Result := Cand;
end;

function AskConflict(const ASrc, ADst: string; ASrcSize, ADstSize: Int64;
  ASrcTime, ADstTime: TDateTime; var ADest: string): TArcConflict;
begin
  if not Assigned(GConf) then
    Exit(acOverwrite);
  Result := GConf(ASrc, ADst, ASrcSize, ADstSize, ASrcTime, ADstTime);
  if Result = acRename then
    ADest := UniqueDiskName(ADest);
end;

procedure CopyDirRecursive(const ASrc, ADst: string);
var
  F, D: string;
begin
  ForceDirectories(ADst);
  for F in TDirectory.GetFiles(ASrc) do
  begin
    ArcCheckWait;
    TFile.Copy(F, TPath.Combine(ADst, TPath.GetFileName(F)), True);
  end;
  for D in TDirectory.GetDirectories(ASrc) do
    CopyDirRecursive(D, TPath.Combine(ADst, TPath.GetFileName(D)));
end;

function DecideOutFile(const ASrcHint, AOutFile: string; ASrcSize: Int64;
  ASrcTime: TDateTime): string;
var
  Choice: TArcConflict;
  DstSize: Int64;
  DstTime: TDateTime;
begin
  Result := AOutFile;
  if not TFile.Exists(Result) then
    Exit;
  DstSize := 0;
  DstTime := 0;
  try
    DstSize := TFile.GetSize(Result);
    DstTime := TFile.GetLastWriteTime(Result);
  except
  end;
  Choice := AskConflict(ASrcHint, Result, ASrcSize, DstSize, ASrcTime, DstTime, Result);
  case Choice of
    acSkip:
      Result := '';
    acCancel:
      Abort;
    acRename:
      if TFile.Exists(Result) then
        Result := UniqueDiskName(Result);
  end;
end;

procedure ExtractPrefixToDisk(const ARef: TArcRef; const ADestDir: string);
var
  Items: TArray<TArcItem>;
  It: TArcItem;
  Prefix, Rel, OutFile, OutDir, Tmp: string;
  OnlyFile: Boolean;
  I: Integer;
begin
  ForceDirectories(ADestDir);
  Items := GetItems(ARef.Physical, ARef.Kind);
  Prefix := ArcNorm(ARef.Inner);
  OnlyFile := (Prefix <> '') and FindItem(Items, Prefix, It) and (not It.IsDir);
  if Need7z(ARef.Kind) then
  begin
    Ensure7z(ARef.Kind);
    Tmp := UniqueTempDir;
    try
      if Prefix = '' then
        Run7z('x -y -aoa -sccUTF-8 -o' + QuoteArg(Tmp) + ' -- ' + QuoteArg(ARef.Physical), Rel)
      else
        Run7z('x -y -aoa -sccUTF-8 -o' + QuoteArg(Tmp) + ' -- ' + QuoteArg(ARef.Physical) +
          ' ' + QuoteArg(StringReplace(Prefix, '/', '\', [rfReplaceAll])), Rel);
      if OnlyFile then
      begin
        OutFile := TPath.Combine(Tmp, StringReplace(Prefix, '/', PathDelim, [rfReplaceAll]));
        if not TFile.Exists(OutFile) then
          OutFile := TPath.Combine(Tmp, ArcLeaf(Prefix));
        if TFile.Exists(OutFile) then
        begin
          Rel := DecideOutFile(ARef.DiskArchive + '\' + Prefix,
            TPath.Combine(ADestDir, ArcLeaf(Prefix)), It.Size, It.Modified);
          if Rel <> '' then
            TFile.Copy(OutFile, Rel, True);
        end;
      end
      else
      begin
        OutDir := Tmp;
        if Prefix <> '' then
        begin
          OutDir := TPath.Combine(Tmp, StringReplace(Prefix, '/', PathDelim, [rfReplaceAll]));
          if not TDirectory.Exists(OutDir) then
            OutDir := Tmp;
        end;
        if TDirectory.Exists(OutDir) then
          CopyDirRecursive(OutDir, ADestDir)
        else if TFile.Exists(OutDir) then
          TFile.Copy(OutDir, TPath.Combine(ADestDir, ExtractFileName(OutDir)), True);
      end;
    finally
      try
        TDirectory.Delete(Tmp, True);
      except
      end;
    end;
    Exit;
  end;

  for I := 0 to High(Items) do
  begin
    ArcCheckWait;
    It := Items[I];
    if Prefix = '' then
      Rel := It.Path
    else if OnlyFile and SameText(It.Path, Prefix) then
      Rel := ArcLeaf(It.Path)
    else if StartsText(Prefix + '/', It.Path) then
      Rel := Copy(It.Path, Length(Prefix) + 2, MaxInt)
    else
      Continue;
    if Rel = '' then
      Continue;
    if It.IsDir then
    begin
      ForceDirectories(ArcToDiskPath(ADestDir, Rel));
      Continue;
    end;
    OutFile := ArcToDiskPath(ADestDir, Rel);
    OutFile := DecideOutFile(ARef.DiskArchive + '\' + It.Path, OutFile, It.Size, It.Modified);
    if OutFile = '' then
      Continue;
    ExtractOne(ARef.Physical, ARef.Kind, It.Path, OutFile);
    try
      if It.Modified > 0 then
        TFile.SetLastWriteTime(OutFile, It.Modified);
    except
    end;
  end;
end;

function ZipNameRemoved(const AName: string; const AInners: array of string): Boolean;
var
  Have, Prefix: string;
  I: Integer;
begin
  Have := ArcNorm(AName);
  for I := 0 to High(AInners) do
  begin
    Prefix := ArcNorm(AInners[I]);
    if Prefix = '' then
      Continue;
    if SameText(Have, Prefix) or StartsText(Prefix + '/', Have) then
      Exit(True);
  end;
  Result := False;
end;

procedure CopyStreamToZip(Dst: TZipFile; AStm: TStream; const AName: string; ASize: Int64);
var
  Tmp: string;
  FS: TFileStream;
  Mem: TMemoryStream;
  Rel: string;
begin
  Rel := ArcSafeRel(AName);
  if Rel = '' then
    Exit;
  if (ASize >= 0) and (ASize < MEM_COPY) then
  begin
    Mem := TMemoryStream.Create;
    try
      if AStm.Size > 0 then
        Mem.CopyFrom(AStm, 0)
      else if ASize > 0 then
        Mem.CopyFrom(AStm, ASize);
      Mem.Position := 0;
      Dst.Add(Mem, Rel);
    finally
      Mem.Free;
    end;
  end
  else
  begin
    Tmp := UniqueTempFile(ArcLeaf(Rel));
    FS := TFileStream.Create(Tmp, fmCreate);
    try
      if AStm.Size > 0 then
        FS.CopyFrom(AStm, 0)
      else if ASize > 0 then
        FS.CopyFrom(AStm, ASize);
    finally
      FS.Free;
    end;
    try
      Dst.Add(Tmp, Rel);
    finally
      try
        TFile.Delete(Tmp);
      except
      end;
    end;
  end;
end;

procedure RebuildZip(const AZip: string; const ADrop: array of string;
  ARenameFrom, ARenameTo: string);
var
  Src, Dst: TZipFile;
  Tmp, Name, Have, NewName, Rest, OldP, NewP: string;
  I: Integer;
  Stm: TStream;
  Hdr: TZipHeader;
begin
  Tmp := UniqueTempFile(ExtractFileName(AZip));
  OldP := ArcNorm(ARenameFrom);
  NewP := ArcNorm(ARenameTo);
  Src := nil;
  Dst := nil;
  BeginArchiveAccess(AZip);
  try
    Src := OpenZip(AZip, False, False);
    Dst := OpenZip(Tmp, True, True);
    for I := 0 to Src.FileCount - 1 do
    begin
      ArcCheckWait;
      Name := Src.FileName[I];
      Have := ArcNorm(Name);
      if ZipNameRemoved(Have, ADrop) then
        Continue;
      NewName := Have;
      if (OldP <> '') and (NewP <> '') then
      begin
        if SameText(Have, OldP) then
          NewName := NewP
        else if StartsText(OldP + '/', Have) then
        begin
          Rest := Copy(Have, Length(OldP) + 2, MaxInt);
          NewName := NewP + '/' + Rest;
        end;
      end;
      NewName := ArcSafeRel(NewName);
      if EndsText('/', ArcRaw(Name)) or
         (TFileAttribute.faDirectory in Src.FileInfo[I].FileAttributes) then
      begin
        if NewName <> '' then
          Dst.AddDirectory('', NewName + '/');
        Continue;
      end;
      Src.Read(I, Stm, Hdr);
      try
        CopyStreamToZip(Dst, Stm, NewName, Src.FileInfo[I].UncompressedSize64);
      finally
        Stm.Free;
      end;
    end;
    FreeAndNil(Dst);
    FreeAndNil(Src);
    ReplaceFileAtomic(AZip, Tmp);
  finally
    Dst.Free;
    Src.Free;
    EndArchiveAccess(AZip);
    InvalidateArchive(AZip);
    DeleteFileSilent(Tmp);
  end;
end;

procedure ZipDeleteInnerOpen(Zip: TZipFile; const AInner: string);
var
  Prefix, Have: string;
  I: Integer;
begin
  Prefix := ArcNorm(AInner);
  if Prefix = '' then
    Exit;
  for I := Zip.FileCount - 1 downto 0 do
  begin
    Have := ArcNorm(Zip.FileName[I]);
    if SameText(Have, Prefix) or StartsText(Prefix + '/', Have) then
      Zip.Delete(I);
  end;
end;

procedure AddDiskFileToZip(Zip: TZipFile; const ASrc, ARel: string);
var
  FS: TFileStream;
  W: TWatchStream;
  Rel: string;
begin
  Rel := ArcSafeRel(ARel);
  if Rel = '' then
    Rel := ExtractFileName(ASrc);
  FS := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyNone);
  try
    W := TWatchStream.Create(FS, False, ASrc);
    try
      Zip.Add(W, Rel);
    finally
      W.Free;
    end;
  finally
    FS.Free;
  end;
end;

procedure AddDiskTreeToZip(Zip: TZipFile; const ADir, AZipPrefix: string);
var
  S, Child: string;
begin
  for S in TDirectory.GetFiles(ADir) do
  begin
    ArcCheckWait;
    AddDiskFileToZip(Zip, S, ArcJoin(AZipPrefix, ExtractFileName(S)));
  end;
  for S in TDirectory.GetDirectories(ADir) do
  begin
    Child := ArcJoin(AZipPrefix, ExtractFileName(ExcludeTrailingPathDelimiter(S)));
    try
      Zip.AddDirectory('', Child + '/');
    except
    end;
    AddDiskTreeToZip(Zip, S, Child);
  end;
end;

function InnerConflictName(const AItems: TArray<TArcItem>; const ASrcHint, ADestInner: string;
  ASrcSize: Int64; ASrcTime: TDateTime): string; forward;

procedure CopyZipEntries(Src, Dst: TZipFile);
var
  I: Integer;
  Stm: TStream;
  Hdr: TZipHeader;
  Name, Have: string;
begin
  for I := 0 to Src.FileCount - 1 do
  begin
    ArcCheckWait;
    Name := Src.FileName[I];
    Have := ArcNorm(Name);
    if EndsText('/', ArcRaw(Name)) or
       (TFileAttribute.faDirectory in Src.FileInfo[I].FileAttributes) then
    begin
      if Have <> '' then
        Dst.AddDirectory('', Have + '/');
      Continue;
    end;
    Src.Read(I, Stm, Hdr);
    try
      CopyStreamToZip(Dst, Stm, Have, Src.FileInfo[I].UncompressedSize64);
    finally
      Stm.Free;
    end;
  end;
end;

procedure AddDiskSourcesToZip(Zip: TZipFile; const ASources: TArray<string>;
  const AItems: TArray<TArcItem>; ACheckConflict: Boolean);
var
  Src, Root, Use: string;
  Sz: Int64;
  Mt: TDateTime;
begin
  for Src in ASources do
  begin
    ArcCheckWait;
    if TDirectory.Exists(Src) then
    begin
      Root := ExtractFileName(ExcludeTrailingPathDelimiter(Src));
      Use := Root;
      if ACheckConflict then
      begin
        Use := InnerConflictName(AItems, Src, Root, 0, 0);
        if Use = '' then
          Continue;
        ZipDeleteInnerOpen(Zip, Use);
      end;
      try
        Zip.AddDirectory('', Use + '/');
      except
      end;
      AddDiskTreeToZip(Zip, Src, Use);
    end
    else if TFile.Exists(Src) then
    begin
      Root := ExtractFileName(Src);
      Use := Root;
      if ACheckConflict then
      begin
        Sz := 0;
        Mt := 0;
        try
          Sz := TFile.GetSize(Src);
          Mt := TFile.GetLastWriteTime(Src);
        except
        end;
        Use := InnerConflictName(AItems, Src, Root, Sz, Mt);
        if Use = '' then
          Continue;
        ZipDeleteInnerOpen(Zip, Use);
      end;
      AddDiskFileToZip(Zip, Src, Use);
    end;
  end;
end;

function InnerConflictName(const AItems: TArray<TArcItem>; const ASrcHint, ADestInner: string;
  ASrcSize: Int64; ASrcTime: TDateTime): string;
var
  It: TArcItem;
  Choice: TArcConflict;
  Dummy: string;
begin
  Result := ADestInner;
  if not FindItem(AItems, ADestInner, It) then
    Exit;
  if not Assigned(GConf) then
    Exit;
  Dummy := ADestInner;
  Choice := GConf(ASrcHint, ADestInner, ASrcSize, It.Size, ASrcTime, It.Modified);
  case Choice of
    acSkip:
      Result := '';
    acCancel:
      Abort;
    acRename:
      Result := UniqueInnerName(AItems, ADestInner);
  end;
end;

procedure AddPathToZip(const ASource, AZip, ADestInner: string);
var
  Zip: TZipFile;
  Name, Prefix, Use: string;
  Items: TArray<TArcItem>;
  Sz: Int64;
  Mt: TDateTime;
begin
  Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(ASource));
  Prefix := ArcJoin(ADestInner, Name);
  Items := GetItems(AZip, akZip);
  Sz := 0;
  Mt := 0;
  try
    if TFile.Exists(ASource) then
    begin
      Sz := TFile.GetSize(ASource);
      Mt := TFile.GetLastWriteTime(ASource);
    end;
  except
  end;
  Use := InnerConflictName(Items, ASource, Prefix, Sz, Mt);
  if Use = '' then
    Exit;
  Zip := nil;
  BeginArchiveAccess(AZip);
  try
    Zip := OpenZip(AZip, True, not TFile.Exists(AZip));
    Zip.UTF8Support := True;
    ZipDeleteInnerOpen(Zip, Use);
    if TDirectory.Exists(ASource) then
    begin
      Zip.AddDirectory('', Use + '/');
      AddDiskTreeToZip(Zip, ASource, Use);
    end
    else if TFile.Exists(ASource) then
      AddDiskFileToZip(Zip, ASource, Use);
  finally
    Zip.Free;
    EndArchiveAccess(AZip);
    InvalidateArchive(AZip);
  end;
end;

procedure CopyZipInner(const ASrcZip, ASrcInner, ADstZip, ADstInner: string);
var
  Src, Dst: TZipFile;
  Same, HeldSrc, HeldDst: Boolean;
  Prefix, Have, Rel, NewName, Tmp: string;
  I: Integer;
  Stm: TStream;
  Hdr: TZipHeader;
  Names: TStringList;
  Tmps: TStringList;
  Sz: Int64;
begin
  Same := SameText(ASrcZip, ADstZip);
  Prefix := ArcNorm(ASrcInner);
  Names := TStringList.Create;
  Tmps := TStringList.Create;
  Src := nil;
  Dst := nil;
  HeldSrc := False;
  HeldDst := False;
  try
    BeginArchiveAccess(ASrcZip);
    HeldSrc := True;
    Src := OpenZip(ASrcZip, False, False);
    for I := 0 to Src.FileCount - 1 do
    begin
      ArcCheckWait;
      Have := ArcNorm(Src.FileName[I]);
      if Prefix = '' then
        Rel := Have
      else if SameText(Have, Prefix) then
        Rel := ArcLeaf(Have)
      else if StartsText(Prefix + '/', Have) then
        Rel := Copy(Have, Length(Prefix) + 2, MaxInt)
      else
        Continue;
      if Rel = '' then
        Rel := ArcLeaf(Have);
      NewName := ArcSafeRel(ArcJoin(ADstInner, Rel));
      if EndsText('/', ArcRaw(Src.FileName[I])) or
         (TFileAttribute.faDirectory in Src.FileInfo[I].FileAttributes) then
      begin
        Names.Add(NewName + '/');
        Tmps.Add('');
        Continue;
      end;
      Src.Read(I, Stm, Hdr);
      try
        Tmp := UniqueTempFile(ArcLeaf(NewName));
        with TFileStream.Create(Tmp, fmCreate) do
        try
          Sz := Src.FileInfo[I].UncompressedSize64;
          if Stm.Size > 0 then
            CopyFrom(Stm, 0)
          else if Sz > 0 then
            CopyFrom(Stm, Sz);
        finally
          Free;
        end;
        Names.Add(NewName);
        Tmps.Add(Tmp);
      finally
        Stm.Free;
      end;
    end;
    Src.Free;
    Src := nil;
    if Same then
      Dst := OpenZip(ADstZip, True, False)
    else
    begin
      EndArchiveAccess(ASrcZip);
      HeldSrc := False;
      BeginArchiveAccess(ADstZip);
      HeldDst := True;
      Dst := OpenZip(ADstZip, True, not TFile.Exists(ADstZip));
    end;
    Dst.UTF8Support := True;
    if Names.Count = 0 then
    begin
      if Prefix <> '' then
        Dst.AddDirectory('', ArcJoin(ADstInner, ArcLeaf(Prefix)) + '/');
    end
    else
      for I := 0 to Names.Count - 1 do
      begin
        ArcCheckWait;
        ZipDeleteInnerOpen(Dst, ArcNorm(Names[I]));
        if EndsText('/', Names[I]) then
          Dst.AddDirectory('', Names[I])
        else if Tmps[I] <> '' then
          Dst.Add(Tmps[I], Names[I]);
      end;
  finally
    if Dst <> nil then
      Dst.Free;
    if Src <> nil then
      Src.Free;
    for I := 0 to Tmps.Count - 1 do
      if (Tmps[I] <> '') and TFile.Exists(Tmps[I]) then
      try
        TFile.Delete(Tmps[I]);
      except
      end;
    Tmps.Free;
    Names.Free;
    if HeldDst then
      EndArchiveAccess(ADstZip);
    if HeldSrc then
      EndArchiveAccess(ASrcZip);
    InvalidateArchive(ADstZip);
    if not Same then
      InvalidateArchive(ASrcZip);
  end;
end;

procedure SevenAdd(const AArchive, ASource, ADestInner: string);
var
  Text, Work, Rel, Args: string;
  Code: Integer;
begin
  Ensure7z(DetectArchiveKind(AArchive));
  if ADestInner = '' then
    Args := 'a -y -sccUTF-8 -- ' + QuoteArg(AArchive) + ' ' + QuoteArg(ASource)
  else
  begin
    Work := UniqueTempDir;
    try
      Rel := StringReplace(ArcJoin(ADestInner,
        TPath.GetFileName(ExcludeTrailingPathDelimiter(ASource))), '/', PathDelim, [rfReplaceAll]);
      ForceDirectories(ExtractFilePath(TPath.Combine(Work, Rel)));
      if TDirectory.Exists(ASource) then
        CopyDirRecursive(ASource, TPath.Combine(Work, Rel))
      else
        TFile.Copy(ASource, TPath.Combine(Work, Rel), True);
      Args := 'a -y -sccUTF-8 -- ' + QuoteArg(AArchive) + ' ' + QuoteArg(TPath.Combine(Work, Rel));
      { 7z stores absolute-ish paths; use -spe / relative via -w }
      Args := 'a -y -sccUTF-8 -w' + QuoteArg(Work) + ' -- ' + QuoteArg(AArchive) + ' ' + QuoteArg(Rel);
    except
      try
        TDirectory.Delete(Work, True);
      except
      end;
      raise;
    end;
  end;
  Code := Run7z(Args, Text);
  if ADestInner <> '' then
  try
    TDirectory.Delete(Work, True);
  except
  end;
  InvalidateArchive(AArchive);
  if Code <> 0 then
    raise Exception.Create('Не удалось добавить в архив' + sLineBreak + Trim(Text));
end;

procedure SevenDelete(const AArchive, AInner: string);
var
  Text: string;
  Code: Integer;
  Inner: string;
begin
  Ensure7z(DetectArchiveKind(AArchive));
  Inner := StringReplace(ArcNorm(AInner), '/', '\', [rfReplaceAll]);
  Code := Run7z('d -y -sccUTF-8 -- ' + QuoteArg(AArchive) + ' ' + QuoteArg(Inner), Text);
  InvalidateArchive(AArchive);
  if Code <> 0 then
    raise Exception.Create('Не удалось удалить из архива' + sLineBreak + Trim(Text));
end;

procedure WriteTarHeader(ADst: TStream; const AName: string; ASize: Int64;
  ATime: TDateTime; AIsDir: Boolean);
var
  H: array[0..511] of Byte;
  Nam, Pref, Raw: RawByteString;
  Sum: Integer;
  I: Integer;
  Mode, Sz, Tm: RawByteString;
  UName: UTF8String;
  Leaf, Prefix: string;
begin
  FillChar(H, SizeOf(H), 0);
  Leaf := AName;
  Prefix := '';
  if Length(UTF8String(AName)) > 100 then
  begin
    Prefix := ArcParent(AName);
    Leaf := ArcLeaf(AName);
    if Length(UTF8String(Prefix)) > 155 then
      Prefix := Copy(Prefix, 1, 155);
  end;
  UName := UTF8String(Leaf);
  Move(UName[1], H[0], Min(Length(UName), 100));
  Mode := UTF8Encode(IfThen(AIsDir, '0000755'#0, '0000644'#0));
  Move(Mode[1], H[100], Min(Length(Mode), 8));
  Raw := '0000000'#0;
  Move(Raw[1], H[108], 8);
  Move(Raw[1], H[116], 8);
  Sz := UTF8Encode(Format('%.11o', [ASize]) + #0);
  Move(Sz[1], H[124], Min(Length(Sz), 12));
  if ATime > 0 then
    Tm := UTF8Encode(Format('%.11o', [DateTimeToUnix(ATime, False)]) + #0)
  else
    Tm := '00000000000'#0;
  Move(Tm[1], H[136], Min(Length(Tm), 12));
  FillChar(H[148], 8, 32);
  if AIsDir then
    H[156] := Ord('5')
  else
    H[156] := Ord('0');
  Raw := 'ustar'#0'00';
  Move(Raw[1], H[257], 8);
  if Prefix <> '' then
  begin
    Pref := UTF8String(Prefix);
    Move(Pref[1], H[345], Min(Length(Pref), 155));
  end;
  Sum := 0;
  for I := 0 to 511 do
    Inc(Sum, H[I]);
  Nam := UTF8Encode(Format('%.6o', [Sum]) + #0 + ' ');
  Move(Nam[1], H[148], Min(Length(Nam), 8));
  ADst.WriteBuffer(H[0], 512);
end;

procedure PadTar(ADst: TStream; ASize: Int64);
var
  Pad: Integer;
  Z: array[0..511] of Byte;
begin
  Pad := (512 - (ASize mod 512)) mod 512;
  if Pad > 0 then
  begin
    FillChar(Z, SizeOf(Z), 0);
    ADst.WriteBuffer(Z[0], Pad);
  end;
end;

procedure AddFileToTar(ADst: TStream; const ADisk, ARel: string);
var
  FS: TFileStream;
  W: TWatchStream;
  Sz: Int64;
  Rel: string;
  Mt: TDateTime;
begin
  Rel := ArcSafeRel(ARel);
  Sz := TFile.GetSize(ADisk);
  Mt := TFile.GetLastWriteTime(ADisk);
  WriteTarHeader(ADst, Rel, Sz, Mt, False);
  FS := TFileStream.Create(ADisk, fmOpenRead or fmShareDenyNone);
  try
    W := TWatchStream.Create(FS, False, ADisk);
    try
      if Sz > 0 then
        ADst.CopyFrom(W, Sz);
    finally
      W.Free;
    end;
  finally
    FS.Free;
  end;
  PadTar(ADst, Sz);
end;

procedure AddDirToTar(ADst: TStream; const ADir, ARoot: string);
var
  Rel, F: string;
begin
  Rel := ArcSafeRel(ARoot);
  if Rel <> '' then
    WriteTarHeader(ADst, Rel, 0, Now, True);
  for F in TDirectory.GetFiles(ADir) do
  begin
    ArcCheckWait;
    AddFileToTar(ADst, F, ArcJoin(ARoot, ExtractFileName(F)));
  end;
  for F in TDirectory.GetDirectories(ADir) do
    AddDirToTar(ADst, F, ArcJoin(ARoot, ExtractFileName(ExcludeTrailingPathDelimiter(F))));
end;

procedure FinishTar(ADst: TStream);
var
  Z: array[0..1023] of Byte;
begin
  FillChar(Z, SizeOf(Z), 0);
  ADst.WriteBuffer(Z[0], 1024);
end;

procedure GzipFile(const ASrc, ADst: string);
var
  InS: TFileStream;
  OutS: TFileStream;
  Z: TZCompressionStream;
  W: TWatchStream;
begin
  InS := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyNone);
  OutS := TFileStream.Create(ADst, fmCreate);
  try
    Z := TZCompressionStream.Create(OutS, zcDefault, 15 + 16);
    try
      W := TWatchStream.Create(InS, False, ASrc);
      try
        Z.CopyFrom(W, 0);
      finally
        W.Free;
      end;
    finally
      Z.Free;
    end;
  finally
    OutS.Free;
    InS.Free;
  end;
end;

procedure PackTarSources(const ASources: TArray<string>; const ATar: string);
var
  FS: TFileStream;
  Src, Rel: string;
begin
  FS := TFileStream.Create(ATar, fmCreate);
  try
    for Src in ASources do
    begin
      ArcCheckWait;
      if TDirectory.Exists(Src) then
      begin
        Rel := ExtractFileName(ExcludeTrailingPathDelimiter(Src));
        AddDirToTar(FS, Src, Rel);
      end
      else if TFile.Exists(Src) then
        AddFileToTar(FS, Src, ExtractFileName(Src));
    end;
    FinishTar(FS);
  finally
    FS.Free;
  end;
end;

procedure PackToArchive(const ASources: TArray<string>; const ADestFile: string;
  AReplace: Boolean);
var
  Kind: TArchiveKind;
  Zip, SrcZip: TZipFile;
  Src, Tmp, Tmp2, Text: string;
  CreateNew, Keep: Boolean;
  Items: TArray<TArcItem>;
begin
  Kind := DetectArchiveKind(ADestFile);
  if Kind = akNone then
    Kind := akZip;
  if Kind = akRar then
    raise Exception.Create('Запись RAR не поддерживается. Используйте ZIP или 7Z.');
  if Need7z(Kind) then
    Ensure7z(Kind);
  ForceDirectories(ExtractFilePath(ADestFile));
  CreateNew := AReplace or not TFile.Exists(ADestFile);

  if Kind = akZip then
  begin
    { Пишем во временный файл, затем атомарно подменяем dest. }
    Tmp := UniqueTempFile(ExtractFileName(ADestFile));
    Keep := (not CreateNew) and TFile.Exists(ADestFile);
    Zip := nil;
    SrcZip := nil;
    BeginArchiveAccess(ADestFile);
    try
      if Keep then
      begin
        Items := GetItems(ADestFile, akZip);
        SrcZip := OpenZip(ADestFile, False, False);
        Zip := OpenZip(Tmp, True, True);
        CopyZipEntries(SrcZip, Zip);
        FreeAndNil(SrcZip);
      end
      else
      begin
        SetLength(Items, 0);
        Zip := OpenZip(Tmp, True, True);
      end;
      AddDiskSourcesToZip(Zip, ASources, Items, Keep);
      FreeAndNil(Zip);
      ReplaceFileAtomic(ADestFile, Tmp);
      InvalidateArchive(ADestFile);
    finally
      Zip.Free;
      SrcZip.Free;
      EndArchiveAccess(ADestFile);
      DeleteFileSilent(Tmp);
    end;
    for Src in ASources do
      if not TFile.Exists(Src) and not TDirectory.Exists(Src) then
        CopyArchiveEntry(Src, ADestFile);
    Exit;
  end;

  if Kind = akGz then
  begin
    if Length(ASources) <> 1 then
      raise Exception.Create('GZ содержит один файл. Для нескольких используйте ZIP или TAR.GZ.');
    Src := ASources[0];
    if TDirectory.Exists(Src) then
      raise Exception.Create('Папку в GZ упаковать нельзя. Используйте TAR.GZ или ZIP.');
    Tmp := UniqueTempFile('pack.gz');
    if TFile.Exists(Src) then
      GzipFile(Src, Tmp)
    else
    begin
      Tmp2 := UniqueTempFile(ExtractFileName(Src));
      if not MaterializeArchiveFile(Src, Tmp2) then
        raise Exception.Create('Нет файла: ' + Src);
      GzipFile(Tmp2, Tmp);
      TFile.Delete(Tmp2);
    end;
    if AReplace or not TFile.Exists(ADestFile) then
      ReplaceFileAtomic(ADestFile, Tmp)
    else
    begin
      TFile.Delete(Tmp);
      raise Exception.Create('GZ нельзя дописать. Выберите перезапись.');
    end;
    InvalidateArchive(ADestFile);
    Exit;
  end;

  if Kind in [akTar, akTgz] then
  begin
    Tmp := UniqueTempFile('pack.tar');
    PackTarSources(ASources, Tmp);
    if Kind = akTgz then
    begin
      Tmp2 := UniqueTempFile('pack.tgz');
      GzipFile(Tmp, Tmp2);
      TFile.Delete(Tmp);
      Tmp := Tmp2;
    end;
    ReplaceFileAtomic(ADestFile, Tmp);
    InvalidateArchive(ADestFile);
    Exit;
  end;

  if Kind = akSevenZ then
  begin
    Tmp := '';
    if CreateNew and TFile.Exists(ADestFile) then
    begin
      Tmp := UniqueTempFile(ExtractFileName(ADestFile));
      Text := 'a -t7z -y -sccUTF-8 -- ' + QuoteArg(Tmp);
    end
    else
      Text := 'a -t7z -y -sccUTF-8 -- ' + QuoteArg(ADestFile);
    for Src in ASources do
    begin
      if TFile.Exists(Src) or TDirectory.Exists(Src) then
        Text := Text + ' ' + QuoteArg(Src)
      else
      begin
        Tmp2 := UniqueTempFile(ExtractFileName(ExcludeTrailingPathDelimiter(Src)));
        if MaterializeArchiveFile(Src, Tmp2) then
          Text := Text + ' ' + QuoteArg(Tmp2);
      end;
    end;
    if Run7z(Text, Src) <> 0 then
      raise Exception.Create('7-Zip не смог создать архив' + sLineBreak + Trim(Src));
    if Tmp <> '' then
      ReplaceFileAtomic(ADestFile, Tmp);
    InvalidateArchive(ADestFile);
  end;
end;

procedure AddPathToArchive(const ASource, ADestArchiveDir: string);
var
  Ref: TArcRef;
  Kind: TArchiveKind;
begin
  Ref := ResolvePath(ADestArchiveDir);
  if Ref.Physical = '' then
  begin
    if TFile.Exists(ADestArchiveDir) and IsArchiveFileName(ADestArchiveDir) then
    begin
      Ref.Physical := ADestArchiveDir;
      Ref.Kind := DetectArchiveKind(ADestArchiveDir);
      Ref.Inner := '';
      Ref.DiskArchive := ADestArchiveDir;
    end
    else
      raise Exception.Create('Назначение не архив: ' + ADestArchiveDir);
  end;
  Kind := Ref.Kind;
  if Kind = akRar then
    raise Exception.Create('RAR только для чтения');
  if not IsWritableArchiveKind(Kind) then
    raise Exception.Create('Запись в этот тип архива не поддерживается');
  if Kind = akZip then
    AddPathToZip(ASource, Ref.Physical, Ref.Inner)
  else if Need7z(Kind) then
    SevenAdd(Ref.Physical, ASource, Ref.Inner)
  else
  begin
    { tar/gz/tgz: extract-modify-repack would be huge; stage via temp zip-like rebuild }
    raise Exception.Create('Добавление в ' + ArchiveKindCaption(Kind) +
      ' пока через перепаковку: используйте ZIP или 7Z для правки.');
  end;
end;

procedure DeleteArchiveEntry(const APath: string);
begin
  DeleteArchiveEntries([APath]);
end;

procedure DeleteArchiveEntries(const APaths: TArray<string>);
var
  ByArc: TObjectDictionary<string, TStringList>;
  Ref: TArcRef;
  P, Key: string;
  List: TStringList;
  Drop: TArray<string>;
  I: Integer;
  Pair: TPair<string, TStringList>;
  Kind: TArchiveKind;
begin
  ByArc := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  try
    for P in APaths do
    begin
      Ref := ResolvePath(P);
      if (Ref.Physical = '') or (Ref.Inner = '') then
        Continue;
      if Ref.Kind = akRar then
        raise Exception.Create('RAR только для чтения');
      Key := CacheKey(Ref.Physical);
      if not ByArc.TryGetValue(Key, List) then
      begin
        List := TStringList.Create;
        List.Add(Ref.Physical);
        ByArc.Add(Key, List);
      end;
      List.Add(Ref.Inner);
    end;
    for Pair in ByArc do
    begin
      if Pair.Value.Count < 2 then
        Continue;
      Kind := DetectArchiveKind(Pair.Value[0]);
      SetLength(Drop, Pair.Value.Count - 1);
      for I := 1 to Pair.Value.Count - 1 do
        Drop[I - 1] := Pair.Value[I];
      if Kind = akZip then
        RebuildZip(Pair.Value[0], Drop, '', '')
      else if Need7z(Kind) then
      begin
        for I := 0 to High(Drop) do
          SevenDelete(Pair.Value[0], Drop[I]);
      end
      else
        raise Exception.Create('Удаление из ' + ArchiveKindCaption(Kind) +
          ' не поддерживается. Распакуйте архив.');
    end;
  finally
    ByArc.Free;
  end;
end;

procedure RenameArchiveEntry(const AOldPath, ANewName: string; out ANewPath: string);
var
  Ref: TArcRef;
  NewInner: string;
begin
  ANewPath := '';
  Ref := ResolvePath(AOldPath);
  if (Ref.Physical = '') or (Ref.Inner = '') then
    raise Exception.Create('Нечего переименовывать');
  NewInner := ArcJoin(ArcParent(Ref.Inner), ANewName);
  NewInner := ArcSafeRel(NewInner);
  if Ref.Kind = akZip then
    RebuildZip(Ref.Physical, [], Ref.Inner, NewInner)
  else
    raise Exception.Create('Переименование внутри ' + ArchiveKindCaption(Ref.Kind) +
      ' не поддерживается');
  ANewPath := Ref.DiskArchive + '\' + StringReplace(NewInner, '/', '\', [rfReplaceAll]);
end;

function CreateArchiveFolder(const AParentDir, ABaseName: string): string;
var
  Ref: TArcRef;
  Zip: TZipFile;
  Name: string;
  N: Integer;
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  Ref := ResolvePath(AParentDir);
  if Ref.Physical = '' then
    raise Exception.Create('Не архив');
  Name := ArcJoin(Ref.Inner, ABaseName);
  N := 1;
  Items := GetItems(Ref.Physical, Ref.Kind);
  while FindItem(Items, Name, It) do
  begin
    Inc(N);
    Name := ArcJoin(Ref.Inner, ABaseName + ' (' + IntToStr(N) + ')');
  end;
  if Ref.Kind <> akZip then
    raise Exception.Create('Новая папка пока только в ZIP');
  Zip := nil;
  BeginArchiveAccess(Ref.Physical);
  try
    Zip := OpenZip(Ref.Physical, True, False);
    Zip.UTF8Support := True;
    Zip.AddDirectory('', Name + '/');
  finally
    Zip.Free;
    EndArchiveAccess(Ref.Physical);
    InvalidateArchive(Ref.Physical);
  end;
  Result := Ref.DiskArchive + '\' + StringReplace(Name, '/', '\', [rfReplaceAll]);
end;

function MaterializeArchiveFile(const APath: string; out ALocal: string): Boolean;
var
  Ref: TArcRef;
  Items: TArray<TArcItem>;
  It: TArcItem;
begin
  ALocal := '';
  Result := False;
  if TFile.Exists(APath) then
  begin
    ALocal := APath;
    Exit(True);
  end;
  Ref := ResolvePath(APath);
  if (Ref.Physical = '') or (Ref.Inner = '') then
    Exit;
  Items := GetItems(Ref.Physical, Ref.Kind);
  if not FindItem(Items, Ref.Inner, It) then
    Exit;
  if It.IsDir then
    Exit;
  ALocal := UniqueTempFile(ArcLeaf(Ref.Inner));
  ExtractOne(Ref.Physical, Ref.Kind, Ref.Inner, ALocal);
  Result := TFile.Exists(ALocal);
end;

procedure CopyArchiveEntry(const ASrcPath, ADstDir: string);
var
  SrcRef, DstRef: TArcRef;
  SrcZipItem, DstArc: Boolean;
  TargetName, DiskDest, Z, Inner: string;
  Items: TArray<TArcItem>;
  It: TArcItem;
  SrcFolder: Boolean;
  Local: string;
begin
  TargetName := TPath.GetFileName(ExcludeTrailingPathDelimiter(ASrcPath));
  SrcZipItem := SplitArchivePath(ASrcPath, Z, Inner) and (Inner <> '');
  DstArc := SplitArchivePath(ADstDir, Z, Inner) or
    (TFile.Exists(ADstDir) and IsArchiveFileName(ADstDir));

  if not SrcZipItem and not DstArc then
  begin
    DiskDest := TPath.Combine(ADstDir, TargetName);
    if TDirectory.Exists(ASrcPath) then
      CopyDirRecursive(ASrcPath, DiskDest)
    else
      TFile.Copy(ASrcPath, DiskDest, True);
    Exit;
  end;

  if SrcZipItem and not DstArc then
  begin
    SrcRef := ResolvePath(ASrcPath);
    if SrcRef.Physical = '' then
      raise Exception.Create('Не удалось открыть архив: ' + ASrcPath);
    Items := GetItems(SrcRef.Physical, SrcRef.Kind);
    SrcFolder := FindItem(Items, SrcRef.Inner, It) and It.IsDir;
    if not TDirectory.Exists(ADstDir) then
      ForceDirectories(ADstDir);
    if SrcFolder then
      ExtractPrefixToDisk(SrcRef, TPath.Combine(ADstDir, TargetName))
    else
      ExtractPrefixToDisk(SrcRef, ADstDir);
    Exit;
  end;

  if (not SrcZipItem) and DstArc then
  begin
    AddPathToArchive(ASrcPath, ADstDir);
    Exit;
  end;

  SrcRef := ResolvePath(ASrcPath);
  DstRef := ResolvePath(ADstDir);
  if DstRef.Physical = '' then
  begin
    DstRef.Physical := ADstDir;
    DstRef.Kind := DetectArchiveKind(ADstDir);
    DstRef.Inner := '';
    DstRef.DiskArchive := ADstDir;
  end;
  Items := GetItems(SrcRef.Physical, SrcRef.Kind);
  SrcFolder := FindItem(Items, SrcRef.Inner, It) and It.IsDir;

  if (SrcRef.Kind = akZip) and (DstRef.Kind = akZip) then
  begin
    if SrcFolder then
      CopyZipInner(SrcRef.Physical, SrcRef.Inner, DstRef.Physical,
        ArcJoin(DstRef.Inner, TargetName))
    else
      CopyZipInner(SrcRef.Physical, SrcRef.Inner, DstRef.Physical, DstRef.Inner);
    Exit;
  end;

  Local := UniqueTempDir;
  try
    if SrcFolder then
      ExtractPrefixToDisk(SrcRef, TPath.Combine(Local, TargetName))
    else
      ExtractPrefixToDisk(SrcRef, Local);
    if SrcFolder then
      AddPathToArchive(TPath.Combine(Local, TargetName), ADstDir)
    else
      AddPathToArchive(TPath.Combine(Local, TargetName), ADstDir);
  finally
    try
      TDirectory.Delete(Local, True);
    except
    end;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GCache := TObjectDictionary<string, TCacheEnt>.Create([doOwnsValues]);
  GNest := TDictionary<string, string>.Create;
  GNestSrc := TDictionary<string, string>.Create;

finalization
  ClearArchiveHooks;
  FreeAndNil(GNestSrc);
  FreeAndNil(GNest);
  FreeAndNil(GCache);
  FreeAndNil(GLock);

end.
