unit uFileSearch;

{
  Фоновый поиск файлов и папок по маске в указанном каталоге/диске
  с необязательным фильтром по дате изменения (включительно)
  и поиском текста внутри файла (BOM, UTF-8, Windows-1251, без исключения).
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  System.Masks, System.DateUtils, System.IOUtils, System.StrUtils, System.Types
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

type
  TSearchHit = record
    Name: string;
    Dir: string;
    FullPath: string;
    Size: Int64;
    Modified: TDateTime;
    IsDirectory: Boolean;
  end;

  TSearchParams = record
    Root: string;
    Mask: string;
    Recursive: Boolean;
    UseDate: Boolean;
    HasFrom: Boolean;
    HasTo: Boolean;
    DateFrom: TDateTime;
    DateTo: TDateTime;
    UseText: Boolean;
    TextQuery: string;
  end;

  TSearchHitsProc = reference to procedure(const AHits: TArray<TSearchHit>);
  TSearchTextProc = reference to procedure(const AText: string);
  TSearchDoneProc = reference to procedure(AFound: Integer; AStopped: Boolean);

  TFileSearchEngine = class
  private
    FThread: TThread;
    FLock: TCriticalSection;
    function GetRunning: Boolean;
    procedure DestroyThread;
  public
    OnHits: TSearchHitsProc;
    OnProgress: TSearchTextProc;
    OnDone: TSearchDoneProc;
    constructor Create;
    destructor Destroy; override;
    procedure Start(const AParams: TSearchParams);
    procedure Stop;
    property Running: Boolean read GetRunning;
  end;

function NormalizeSearchMask(const AMask: string): TArray<string>;
function TryParseSearchDate(const S: string; out ADate: TDateTime): Boolean;
function PickSearchFolder(AOwnerWnd: NativeUInt; const ATitle, AStart: string): string;

implementation

uses
  System.Math, uSpreadsheetData
  {$IFDEF MSWINDOWS}, Winapi.ShlObj, Winapi.ActiveX{$ENDIF};

const
  BUF_SIZE = 48;
  FLUSH_MS = 140;
  MAX_HITS = 20000;
  MAX_TEXT_BYTES = 16 * 1024 * 1024;

type
  TSearchThread = class(TThread)
  private
    FParams: TSearchParams;
    FMasks: TArray<string>;
    FBuf: TArray<TSearchHit>;
    FBufN: Integer;
    FFound: Integer;
    FLastFlush: UInt64;
    FLastProg: UInt64;
    FOnHits: TSearchHitsProc;
    FOnProgress: TSearchTextProc;
    FOnDone: TSearchDoneProc;
    procedure FlushHits;
    procedure ReportProgress(const ADir: string);
    procedure ScanDir(const ADir: string; AStack: TStack<string>);
    function NameMatches(const AName: string): Boolean;
    function DateMatches(AStamp: TDateTime): Boolean;
    function FileContainsQuery(const APath: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AParams: TSearchParams; const AMasks: TArray<string>;
      AOnHits: TSearchHitsProc; AOnProgress: TSearchTextProc; AOnDone: TSearchDoneProc);
  end;

function FileTimeToLocalDateTime(const FT: TFileTime): TDateTime;
{$IFDEF MSWINDOWS}
var
  Local: TFileTime;
  ST: TSystemTime;
begin
  Result := 0;
  if (FT.dwLowDateTime = 0) and (FT.dwHighDateTime = 0) then
    Exit;
  if not FileTimeToLocalFileTime(FT, Local) then
    Exit;
  if not FileTimeToSystemTime(Local, ST) then
    Exit;
  try
    Result := SystemTimeToDateTime(ST);
  except
    Result := 0;
  end;
end;
{$ELSE}
begin
  Result := 0;
end;
{$ENDIF}

function IsSkipDirName(const AName: string): Boolean;
begin
  Result := SameText(AName, '$Recycle.Bin') or
    SameText(AName, 'System Volume Information') or
    SameText(AName, 'Recovery') or
    SameText(AName, 'Config.Msi');
end;

function NormalizeSearchMask(const AMask: string): TArray<string>;
var
  Raw, Part, P: string;
  Parts: TArray<string>;
  List: TList<string>;
begin
  Raw := Trim(AMask);
  if Raw = '' then
    Raw := '*.*';
  Parts := Raw.Split([';', '|']);
  List := TList<string>.Create;
  try
    for Part in Parts do
    begin
      P := Trim(Part);
      if P = '' then
        Continue;
      if (Pos('*', P) = 0) and (Pos('?', P) = 0) then
        P := '*' + P + '*';
      List.Add(P);
    end;
    if List.Count = 0 then
      List.Add('*.*');
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TryParseSearchDate(const S: string; out ADate: TDateTime): Boolean;
var
  T: string;
  Parts: TArray<string>;
  Y, M, D: Integer;
begin
  ADate := 0;
  T := Trim(S);
  if T = '' then
    Exit(False);
  if TryStrToDate(T, ADate) then
    Exit(True);
  T := StringReplace(T, '/', '.', [rfReplaceAll]);
  T := StringReplace(T, '-', '.', [rfReplaceAll]);
  Parts := T.Split(['.']);
  if Length(Parts) <> 3 then
    Exit(False);
  if Length(Trim(Parts[0])) = 4 then
  begin
    Y := StrToIntDef(Trim(Parts[0]), 0);
    M := StrToIntDef(Trim(Parts[1]), 0);
    D := StrToIntDef(Trim(Parts[2]), 0);
  end
  else
  begin
    D := StrToIntDef(Trim(Parts[0]), 0);
    M := StrToIntDef(Trim(Parts[1]), 0);
    Y := StrToIntDef(Trim(Parts[2]), 0);
    if (Y >= 0) and (Y < 100) then
      Y := 2000 + Y;
  end;
  Result := TryEncodeDate(Y, M, D, ADate);
end;

function PickSearchFolder(AOwnerWnd: NativeUInt; const ATitle, AStart: string): string;
{$IFDEF MSWINDOWS}
var
  Dlg: IFileOpenDialog;
  Item: IShellItem;
  Path: PWideChar;
  Opt: DWORD;
  Start: string;
begin
  Result := '';
  if Failed(CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER,
      IFileOpenDialog, Dlg)) then
    Exit;
  Dlg.SetTitle(PWideChar(ATitle));
  Dlg.GetOptions(Opt);
  Dlg.SetOptions(Opt or FOS_PICKFOLDERS or FOS_FORCEFILESYSTEM);
  Start := ExcludeTrailingPathDelimiter(AStart);
  if (Start <> '') and TDirectory.Exists(Start) then
    if Succeeded(SHCreateItemFromParsingName(PWideChar(Start), nil, IShellItem, Item)) then
      Dlg.SetFolder(Item);
  if Failed(Dlg.Show(HWND(AOwnerWnd))) then
    Exit;
  if Failed(Dlg.GetResult(Item)) then
    Exit;
  if Succeeded(Item.GetDisplayName(SIGDN_FILESYSPATH, Path)) then
  begin
    Result := Path;
    CoTaskMemFree(Path);
  end;
end;
{$ELSE}
begin
  Result := '';
end;
{$ENDIF}

{ TSearchThread }

constructor TSearchThread.Create(const AParams: TSearchParams;
  const AMasks: TArray<string>; AOnHits: TSearchHitsProc;
  AOnProgress: TSearchTextProc; AOnDone: TSearchDoneProc);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FParams := AParams;
  FMasks := AMasks;
  FOnHits := AOnHits;
  FOnProgress := AOnProgress;
  FOnDone := AOnDone;
  SetLength(FBuf, BUF_SIZE);
end;

function TSearchThread.NameMatches(const AName: string): Boolean;
var
  M: string;
begin
  for M in FMasks do
    try
      if MatchesMask(AName, M) then
        Exit(True);
    except
    end;
  Result := False;
end;

function MatchGlobPartAt(const AText: string; APos: Integer; const APart: string): Boolean;
var
  I: Integer;
begin
  if (APos < 1) or (APos + Length(APart) - 1 > Length(AText)) then
    Exit(False);
  for I := 1 to Length(APart) do
    if (APart[I] <> '?') and (APart[I] <> AText[APos + I - 1]) then
      Exit(False);
  Result := True;
end;

function FindGlobPart(const AText, APart: string; AFrom: Integer): Integer;
var
  I, Last: Integer;
begin
  if APart = '' then
    Exit(AFrom);
  if Pos('?', APart) = 0 then
    Exit(PosEx(APart, AText, AFrom));
  Last := Length(AText) - Length(APart) + 1;
  for I := AFrom to Last do
    if MatchGlobPartAt(AText, I, APart) then
      Exit(I);
  Result := 0;
end;

function TextContainsQuery(const AText, AQuery: string): Boolean;
var
  T, Q: string;
  Parts: TArray<string>;
  Start, Idx, I: Integer;
begin
  Q := Trim(AQuery);
  if Q = '' then
    Exit(True);
  if (Pos('*', Q) = 0) and (Pos('?', Q) = 0) then
    Exit(ContainsText(AText, Q));
  T := AnsiLowerCase(AText);
  Q := AnsiLowerCase(Q);
  Parts := Q.Split(['*']);
  Start := 1;
  for I := 0 to High(Parts) do
  begin
    if Parts[I] = '' then
      Continue;
    Idx := FindGlobPart(T, Parts[I], Start);
    if Idx <= 0 then
      Exit(False);
    Start := Idx + Length(Parts[I]);
  end;
  Result := True;
end;

function IsBinarySearchExt(const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  Result :=
    (E = '.exe') or (E = '.dll') or (E = '.sys') or (E = '.drv') or
    (E = '.ocx') or (E = '.cpl') or (E = '.scr') or (E = '.com') or
    (E = '.msi') or (E = '.efi') or (E = '.bin') or
    (E = '.png') or (E = '.jpg') or (E = '.jpeg') or (E = '.gif') or
    (E = '.bmp') or (E = '.ico') or (E = '.webp') or (E = '.tif') or
    (E = '.tiff') or (E = '.psd') or (E = '.heic') or (E = '.heif') or
    (E = '.mp3') or (E = '.wav') or (E = '.flac') or (E = '.ogg') or
    (E = '.m4a') or (E = '.aac') or (E = '.wma') or (E = '.opus') or
    (E = '.mp4') or (E = '.avi') or (E = '.mkv') or (E = '.mov') or
    (E = '.wmv') or (E = '.webm') or (E = '.m4v') or (E = '.flv') or
    (E = '.zip') or (E = '.rar') or (E = '.7z') or (E = '.gz') or
    (E = '.bz2') or (E = '.xz') or (E = '.iso') or (E = '.cab') or
    (E = '.tar') or (E = '.tgz') or (E = '.lz') or (E = '.zst') or
    (E = '.pdf') or (E = '.doc') or (E = '.xls') or (E = '.ppt') or
    (E = '.docx') or (E = '.xlsx') or (E = '.pptx') or
    (E = '.ttf') or (E = '.otf') or (E = '.woff') or (E = '.woff2') or
    (E = '.db') or (E = '.sqlite') or (E = '.mdb') or
    (E = '.obj') or (E = '.lib') or (E = '.pdb') or (E = '.res') or
    (E = '.class') or (E = '.jar') or (E = '.pyc') or
    (E = '.apk') or (E = '.ipa') or (E = '.img') or (E = '.vhd') or
    (E = '.vhdx') or (E = '.vmdk') or (E = '.pak');
end;

function BytesLookBinary(const ABytes: TBytes): Boolean;
var
  I, N, Ctrl: Integer;
begin
  N := Length(ABytes);
  if N = 0 then
    Exit(False);
  if N > 4096 then
    N := 4096;
  Ctrl := 0;
  for I := 0 to N - 1 do
  begin
    if ABytes[I] = 0 then
      Exit(True);
    if (ABytes[I] < 32) and not (ABytes[I] in [9, 10, 13]) then
      Inc(Ctrl);
  end;
  Result := Ctrl * 10 >= N;
end;

function BytesContainQuery(const ABytes: TBytes; const AQuery: string): Boolean;
var
  S, EncName: string;
begin
  if (Length(ABytes) = 0) or (Trim(AQuery) = '') then
    Exit(False);
  S := DecodeLooseText(ABytes, EncName);
  Result := TextContainsQuery(S, AQuery);
end;

function TSearchThread.FileContainsQuery(const APath: string): Boolean;
var
  FS: TFileStream;
  N: Int64;
  Bytes: TBytes;
  Got: Integer;
begin
  Result := False;
  if Terminated or (Trim(FParams.TextQuery) = '') then
    Exit;
  if IsBinarySearchExt(ExtractFileExt(APath)) then
    Exit(False);
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    Exit(False);
  end;
  try
    N := FS.Size;
    if N <= 0 then
      Exit(False);
    if N > MAX_TEXT_BYTES then
      N := MAX_TEXT_BYTES;
    SetLength(Bytes, N);
    Got := FS.Read(Bytes[0], Integer(N));
    if Got <= 0 then
      Exit(False);
    if Got < N then
      SetLength(Bytes, Got);
  finally
    FS.Free;
  end;
  if Terminated then
    Exit(False);
  if BytesLookBinary(Bytes) then
    Exit(False);
  Result := BytesContainQuery(Bytes, FParams.TextQuery);
end;

function TSearchThread.DateMatches(AStamp: TDateTime): Boolean;
var
  D: TDateTime;
begin
  if not FParams.UseDate then
    Exit(True);
  if AStamp <= 0 then
    Exit(False);
  D := DateOf(AStamp);
  { С и По — календарные дни, обе границы включительно.
    Пустая С: всё до По. Пустая По: всё с С. }
  if FParams.HasFrom and (D < DateOf(FParams.DateFrom)) then
    Exit(False);
  if FParams.HasTo and (D > DateOf(FParams.DateTo)) then
    Exit(False);
  Result := True;
end;

procedure TSearchThread.FlushHits;
var
  Copy: TArray<TSearchHit>;
  I, N: Integer;
begin
  if FBufN = 0 then
    Exit;
  N := FBufN;
  SetLength(Copy, N);
  for I := 0 to N - 1 do
    Copy[I] := FBuf[I];
  FBufN := 0;
  FLastFlush := GetTickCount64;
  TThread.Queue(Self,
    procedure
    begin
      if Assigned(FOnHits) then
        FOnHits(Copy);
    end);
end;

procedure TSearchThread.ReportProgress(const ADir: string);
var
  NowTick: UInt64;
  Text: string;
begin
  NowTick := GetTickCount64;
  if NowTick - FLastProg < 90 then
    Exit;
  FLastProg := NowTick;
  Text := ADir;
  TThread.Queue(Self,
    procedure
    begin
      if Assigned(FOnProgress) then
        FOnProgress(Text);
    end);
end;

procedure TSearchThread.ScanDir(const ADir: string; AStack: TStack<string>);
var
  Rec: TSearchRec;
  FullPath: string;
  Hit: TSearchHit;
  IsDir: Boolean;
  Stamp: TDateTime;
begin
  ReportProgress(ADir);
  if System.SysUtils.FindFirst(TPath.Combine(ADir, '*.*'), faAnyFile, Rec) <> 0 then
    Exit;
  try
    repeat
      if Terminated then
        Break;
      if (Rec.Name = '.') or (Rec.Name = '..') then
        Continue;

      IsDir := (Rec.Attr and faDirectory) <> 0;
      FullPath := TPath.Combine(ADir, Rec.Name);

      if IsDir and FParams.Recursive and (AStack <> nil) and
         ((Rec.Attr and faSymLink) = 0) and not IsSkipDirName(Rec.Name) then
        AStack.Push(FullPath);

      {$IFDEF MSWINDOWS}
      Stamp := FileTimeToLocalDateTime(Rec.FindData.ftLastWriteTime);
      {$ELSE}
      Stamp := Rec.TimeStamp;
      {$ENDIF}

      if NameMatches(Rec.Name) and DateMatches(Stamp) then
      begin
        if FParams.UseText then
        begin
          if IsDir or not FileContainsQuery(FullPath) then
            Continue;
          if Terminated then
            Break;
        end;
        Inc(FFound);
        if FFound <= MAX_HITS then
        begin
          Hit.Name := Rec.Name;
          Hit.Dir := ADir;
          Hit.FullPath := FullPath;
          Hit.IsDirectory := IsDir;
          Hit.Modified := Stamp;
          if IsDir then
            Hit.Size := 0
          else
            Hit.Size := Rec.Size;
          if FBufN >= Length(FBuf) then
            SetLength(FBuf, FBufN + BUF_SIZE);
          FBuf[FBufN] := Hit;
          Inc(FBufN);
          if (FBufN >= BUF_SIZE) or (GetTickCount64 - FLastFlush >= FLUSH_MS) then
            FlushHits;
        end;
      end;
    until System.SysUtils.FindNext(Rec) <> 0;
  finally
    System.SysUtils.FindClose(Rec);
  end;
end;

procedure TSearchThread.Execute;
var
  Stack: TStack<string>;
  Root: string;
  Stopped: Boolean;
  Total: Integer;
begin
  FLastFlush := GetTickCount64;
  FLastProg := 0;
  Root := ExcludeTrailingPathDelimiter(FParams.Root);
  if (Length(Root) = 2) and (Root[2] = ':') then
    Root := Root + PathDelim;
  if not TDirectory.Exists(Root) then
  begin
    TThread.Queue(Self,
      procedure
      begin
        if Assigned(FOnDone) then
          FOnDone(0, True);
      end);
    Exit;
  end;

  Stack := TStack<string>.Create;
  try
    Stack.Push(Root);
    while (Stack.Count > 0) and not Terminated do
      ScanDir(Stack.Pop, Stack);
    FlushHits;
  finally
    Stack.Free;
  end;

  Stopped := Terminated;
  Total := FFound;
  TThread.Queue(Self,
    procedure
    begin
      if Assigned(FOnDone) then
        FOnDone(Total, Stopped);
    end);
end;

{ TFileSearchEngine }

constructor TFileSearchEngine.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TFileSearchEngine.Destroy;
begin
  Stop;
  FLock.Free;
  inherited;
end;

function TFileSearchEngine.GetRunning: Boolean;
begin
  FLock.Enter;
  try
    Result := Assigned(FThread) and not FThread.Finished;
  finally
    FLock.Leave;
  end;
end;

procedure TFileSearchEngine.Start(const AParams: TSearchParams);
var
  Masks: TArray<string>;
  Hits: TSearchHitsProc;
  Prog: TSearchTextProc;
  Done: TSearchDoneProc;
begin
  Stop;
  Masks := NormalizeSearchMask(AParams.Mask);
  Hits := OnHits;
  Prog := OnProgress;
  Done := OnDone;
  FLock.Enter;
  try
    FThread := TSearchThread.Create(AParams, Masks, Hits, Prog, Done);
    FThread.Start;
  finally
    FLock.Leave;
  end;
end;

procedure TFileSearchEngine.DestroyThread;
var
  T: TThread;
begin
  FLock.Enter;
  try
    T := FThread;
    FThread := nil;
  finally
    FLock.Leave;
  end;
  if T = nil then
    Exit;
  T.Terminate;
  T.WaitFor;
  TThread.RemoveQueuedEvents(T);
  T.Free;
end;

procedure TFileSearchEngine.Stop;
begin
  DestroyThread;
end;

end.
