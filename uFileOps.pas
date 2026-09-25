unit uFileOps;

{
  Базовые файловые операции: копирование, перемещение, удаление,
  создание папки. Выполняются в фоновом потоке, чтобы не блокировать UI.
  V!be: engine + окно прогресса (конфликты там).
  Тихий: без progress/Shell-диалогов; конфликты имён — uConflictDialog.
  Проводник: SHFileOperation с диалогами Windows.
}

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils,
  System.Generics.Collections, uFileModel, uAppSettings
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.ShellAPI{$ENDIF};

type
  TFileOpDoneProc = reference to procedure(Success: Boolean; const ErrorMsg: string);

  TOpItemStatus = (oisOk, oisSkipped, oisConflictPending, oisError);

  TFileOpItemDoneProc = reference to procedure(const APath: string;
    AStatus: TOpItemStatus);

  TConflictAction = (caSkip, caAutoName, caOverwrite);

  TConflictItem = record
    SourcePath: string;
    DestPath: string;
    SourceSize: Int64;
    DestSize: Int64;
    SourceTime: TDateTime;
    DestTime: TDateTime;
    SourceIsDir: Boolean;
    DestIsDir: Boolean;
  end;

procedure CopyPathSync(const ASource, ADestDir: string);
procedure CopyPathAsync(const ASource, ADestDir: string; AOnDone: TFileOpDoneProc);
procedure CopyPathsAsync(const ASources: TArray<string>; const ADestDir: string;
  AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc = nil);
procedure MovePathAsync(const ASource, ADestDir: string; AOnDone: TFileOpDoneProc);
procedure MovePathsAsync(const ASources: TArray<string>; const ADestDir: string;
  AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc = nil);
function CountOpLeaves(const ASources: TArray<string>): Integer;
function ListFileOpBusy: Boolean;
function RestoreVibeCopyFromBackground: Boolean;
function RestoreVibeDeleteFromBackground: Boolean;
procedure CancelListFileOps;
procedure DeletePathAsync(const APath: string; AOnDone: TFileOpDoneProc;
  APermanent: Boolean = False);
procedure DeletePathsAsync(const APaths: TArray<string>; AOnDone: TFileOpDoneProc;
  APermanent: Boolean = False);
function CreateNewFolder(const AParentDir, ABaseName: string): string;
function RenamePath(const AOldPath, ANewName: string; out ANewPath: string): Boolean;
procedure ArchivePathsAsync(const ASources: TArray<string>; const AZipFile: string;
  AOnDone: TFileOpDoneProc);
procedure ArchivePathsSync(const ASources: TArray<string>; const AZipFile: string);
procedure ArchiveInnerToZipFile(const ASrcPath, ADestZip: string);
procedure DeletePathSync(const APath: string; APermanent: Boolean = False);
procedure SetFileOpMode(AMode: TFileOpMode);
function GetFileOpMode: TFileOpMode;
procedure SetFileOpOwnerWnd(AWnd: NativeUInt);

implementation

uses
  System.SyncObjs, System.DateUtils, FMX.Types, FMX.Forms,
  uFileOpEngine, uFileOpProgressForm, uArchiveEngine, uConflictDialog;

procedure CopyDirRecursive(const ASrc, ADst: string); forward;
procedure DeletePathCore(const APath: string; APermanent: Boolean); forward;
procedure ArchivePathsCore(const ASources: TArray<string>; const AZipFile: string); forward;
procedure CopyPathCore(const ASource, ADestDir: string); forward;

var
  GFileOpMode: TFileOpMode = fomVibe;
  GFileOpWnd: NativeUInt = 0;
  GListOpBusy: Boolean = False;
  GListOpCancel: Boolean = False;

procedure SetFileOpMode(AMode: TFileOpMode);
begin
  GFileOpMode := AMode;
end;

function GetFileOpMode: TFileOpMode;
begin
  Result := GFileOpMode;
end;

procedure SetFileOpOwnerWnd(AWnd: NativeUInt);
begin
  GFileOpWnd := AWnd;
end;

function ListFileOpBusy: Boolean;
begin
  Result := GListOpBusy;
end;

function RestoreVibeCopyFromBackground: Boolean;
begin
  Result := RestoreVibeBackground(okCopy);
end;

function RestoreVibeDeleteFromBackground: Boolean;
begin
  Result := RestoreVibeBackground(okDelete);
end;

procedure CancelListFileOps;
begin
  GListOpCancel := True;
end;

function IsOfficeLockName(const APath: string): Boolean;
var
  N: string;
begin
  N := TPath.GetFileName(APath);
  Result := StartsText('~$', N);
end;

function OpIsDir(const APath: string): Boolean;
begin
  Result := TDirectory.Exists(APath) or
    ((not TFile.Exists(APath)) and ArchivePathIsFolder(APath));
end;

function OpExists(const APath: string): Boolean;
begin
  Result := TFile.Exists(APath) or TDirectory.Exists(APath) or ArchivePathExists(APath);
end;

function CountOneLeaves(const APath: string): Integer;
var
  F: string;
  N: Integer;
  B: Int64;
begin
  Result := 0;
  if TDirectory.Exists(APath) then
  begin
    try
      for F in TDirectory.GetFiles(APath) do
        Inc(Result, CountOneLeaves(F));
      for F in TDirectory.GetDirectories(APath) do
        Inc(Result, CountOneLeaves(F));
    except
    end;
    if Result = 0 then
      Result := 1;
  end
  else if TFile.Exists(APath) then
    Result := 1
  else if ScanArchivePath(APath, N, B) then
  begin
    Result := N;
    if Result <= 0 then
      Result := 1;
  end
  else
    Result := 1;
end;

function CountOpLeaves(const ASources: TArray<string>): Integer;
var
  S: string;
begin
  Result := 0;
  for S in ASources do
    Inc(Result, CountOneLeaves(S));
  if Result < 1 then
    Result := 1;
end;

function CanShellDiskPath(const APath: string): Boolean;
var
  Z, Inner: string;
begin
  Result := False;
  if APath = '' then
    Exit;
  if IsVirtualShellPath(APath) or IsPortableDevicePath(APath) then
    Exit;
  if SplitArchivePath(APath, Z, Inner) and (Inner <> '') then
    Exit;
  Result := True;
end;

procedure SplitDiskSources(const ASources: TArray<string>;
  out ADisk, AOther: TArray<string>);
var
  S: string;
  Disk, Other: TList<string>;
begin
  Disk := TList<string>.Create;
  Other := TList<string>.Create;
  try
    for S in ASources do
      if CanShellDiskPath(S) and (TFile.Exists(S) or TDirectory.Exists(S)) then
        Disk.Add(S)
      else
        Other.Add(S);
    ADisk := Disk.ToArray;
    AOther := Other.ToArray;
  finally
    Disk.Free;
    Other.Free;
  end;
end;

{$IFDEF MSWINDOWS}
function ShellFlags(AAllowUndo: Boolean): FILEOP_FLAGS;
begin
  case GFileOpMode of
    fomExplorer:
      Result := FOF_NOCONFIRMMKDIR;
  else
    { Quiet и V!be: без диалогов проводника. }
    Result := FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI or
      FOF_NOCONFIRMMKDIR;
  end;
  if AAllowUndo then
    Result := Result or FOF_ALLOWUNDO;
end;

function ShellFileOp(AFunc: UINT; const AFrom: TArray<string>;
  const ATo: string; AAllowUndo: Boolean): Boolean;
var
  Op: TSHFileOpStruct;
  FromStr, ToStr, S: string;
begin
  Result := False;
  if Length(AFrom) = 0 then
    Exit(True);
  FromStr := '';
  for S in AFrom do
    FromStr := FromStr + ExcludeTrailingPathDelimiter(S) + #0;
  FromStr := FromStr + #0;
  ToStr := '';
  if ATo <> '' then
    ToStr := ExcludeTrailingPathDelimiter(ATo) + #0#0;
  FillChar(Op, SizeOf(Op), 0);
  Op.Wnd := HWND(GFileOpWnd);
  Op.wFunc := AFunc;
  Op.pFrom := PChar(FromStr);
  if ATo <> '' then
    Op.pTo := PChar(ToStr);
  Op.fFlags := ShellFlags(AAllowUndo);
  Result := (SHFileOperation(Op) = 0) and not Op.fAnyOperationsAborted;
end;
{$ENDIF}

function UseShellDiskOps: Boolean;
begin
  Result := GFileOpMode in [fomQuiet, fomExplorer];
end;

function TryZipItem(const APath: string; out AZip, AInner: string): Boolean;
begin
  Result := SplitArchivePath(APath, AZip, AInner) and
    (DetectArchiveKind(AZip) <> akNone);
end;

procedure CopyPathCore(const ASource, ADestDir: string);
var
  TargetName: string;
begin
  TargetName := TPath.GetFileName(ExcludeTrailingPathDelimiter(ASource));
  if not ArchiveInvolved(ASource, ADestDir) then
  begin
    if IsVirtualShellPath(ASource) or IsPortableDevicePath(ASource) or
       IsVirtualShellPath(ADestDir) or IsPortableDevicePath(ADestDir) then
    begin
      if not TDirectory.Exists(ASource) and not TFile.Exists(ASource) then
      begin
        if ShellTransfer(ASource, ADestDir) then
          Exit;
        raise Exception.Create('Не удалось скопировать с устройства: ' + TargetName);
      end;
      if IsVirtualShellPath(ADestDir) or IsPortableDevicePath(ADestDir) then
      begin
        if ShellTransfer(ASource, ADestDir) then
          Exit;
        raise Exception.Create('Не удалось скопировать на устройство: ' + TargetName);
      end;
    end;
  end;
  CopyArchiveEntry(ASource, ADestDir);
end;

procedure CopyDirRecursive(const ASrc, ADst: string);
var
  F: string;
  SubDir: string;
begin
  TDirectory.CreateDirectory(ADst);
  for F in TDirectory.GetFiles(ASrc) do
    TFile.Copy(F, TPath.Combine(ADst, TPath.GetFileName(F)), True);
  for SubDir in TDirectory.GetDirectories(ASrc) do
    CopyDirRecursive(SubDir, TPath.Combine(ADst, TPath.GetFileName(SubDir)));
end;

procedure CopyPathSync(const ASource, ADestDir: string);
begin
  CopyPathCore(ASource, ADestDir);
end;

procedure CopyPathAsync(const ASource, ADestDir: string; AOnDone: TFileOpDoneProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      ErrMsg: string;
      Ok: Boolean;
    begin
      Ok := True;
      ErrMsg := '';
      try
        CopyPathCore(ASource, ADestDir);
      except
        on E: Exception do
        begin
          Ok := False;
          ErrMsg := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then AOnDone(Ok, ErrMsg);
        end);
    end).Start;
end;

procedure MovePathAsync(const ASource, ADestDir: string; AOnDone: TFileOpDoneProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      ErrMsg: string;
      Ok: Boolean;
    begin
      Ok := True;
      ErrMsg := '';
      try
        CopyPathCore(ASource, ADestDir);
        DeletePathCore(ASource, True);
      except
        on E: Exception do
        begin
          Ok := False;
          ErrMsg := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then AOnDone(Ok, ErrMsg);
        end);
    end).Start;
end;

{$IFDEF MSWINDOWS}
function ShellDeletePath(const APath: string; APermanent: Boolean): Boolean;
begin
  Result := ShellFileOp(FO_DELETE, [APath], '', not APermanent);
end;
{$ENDIF}

procedure DeletePathCore(const APath: string; APermanent: Boolean);
var
  Z, Inner: string;
begin
  if TryZipItem(APath, Z, Inner) and (Inner <> '') then
  begin
    DeleteArchiveEntry(APath);
    Exit;
  end;

  {$IFDEF MSWINDOWS}
  if UseShellDiskOps then
  begin
    if not ShellDeletePath(APath, APermanent) then
    begin
      if APermanent then
      begin
        if TDirectory.Exists(APath) then
          TDirectory.Delete(APath, True)
        else
          TFile.Delete(APath);
      end
      else
        raise Exception.Create('Не удалось переместить в корзину');
    end;
    Exit;
  end;
  if not APermanent then
  begin
    if not ShellDeletePath(APath, False) then
      raise Exception.Create('Не удалось переместить в корзину');
    Exit;
  end;
  {$ENDIF}
  if TDirectory.Exists(APath) then
    TDirectory.Delete(APath, True)
  else
    TFile.Delete(APath);
end;

procedure DeletePathAsync(const APath: string; AOnDone: TFileOpDoneProc;
  APermanent: Boolean);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      ErrMsg: string;
      Ok: Boolean;
    begin
      Ok := True;
      ErrMsg := '';
      try
        DeletePathCore(APath, APermanent);
      except
        on E: Exception do
        begin
          Ok := False;
          ErrMsg := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then AOnDone(Ok, ErrMsg);
        end);
    end).Start;
end;

function CreateNewFolder(const AParentDir, ABaseName: string): string;
var
  Candidate, Z, Inner: string;
  N: Integer;
begin
  if TryZipItem(AParentDir, Z, Inner) then
  begin
    Result := CreateArchiveFolder(AParentDir, ABaseName);
    Exit;
  end;

  Candidate := TPath.Combine(AParentDir, ABaseName);
  N := 1;
  while TDirectory.Exists(Candidate) do
  begin
    Inc(N);
    Candidate := TPath.Combine(AParentDir, ABaseName + ' (' + IntToStr(N) + ')');
  end;
  TDirectory.CreateDirectory(Candidate);
  Result := Candidate;
end;

function RenamePath(const AOldPath, ANewName: string; out ANewPath: string): Boolean;
var
  ParentDir, Z, Inner: string;
begin
  Result := False;
  ANewPath := '';
  if (AOldPath = '') or (ANewName = '') then
    Exit;

  if TryZipItem(AOldPath, Z, Inner) and (Inner <> '') then
  begin
    try
      RenameArchiveEntry(AOldPath, ANewName, ANewPath);
      Result := ANewPath <> '';
    except
      Result := False;
    end;
    Exit;
  end;

  ParentDir := ExtractFilePath(ExcludeTrailingPathDelimiter(AOldPath));
  ANewPath := TPath.Combine(ParentDir, ANewName);
  if SameText(AOldPath, ANewPath) then
    Exit(True);
  try
    if TDirectory.Exists(AOldPath) then
      TDirectory.Move(AOldPath, ANewPath)
    else
      TFile.Move(AOldPath, ANewPath);
    Result := True;
  except
    Result := False;
  end;
end;

procedure ArchivePathsCore(const ASources: TArray<string>; const AZipFile: string);
begin
  { Quiet/Explorer: всегда новый архив, существующий dest перезаписывается.
    Vibe идёт через ArchiveAll + DecideConflict, не сюда. Допись не делаем. }
  PackToArchive(ASources, AZipFile, True);
end;

procedure ArchiveInnerToZipFile(const ASrcPath, ADestZip: string);
begin
  CopyArchiveEntry(ASrcPath, ADestZip);
end;

procedure ArchivePathsSync(const ASources: TArray<string>; const AZipFile: string);
begin
  ArchivePathsCore(ASources, AZipFile);
end;

procedure DeletePathSync(const APath: string; APermanent: Boolean);
begin
  DeletePathCore(APath, APermanent);
end;

procedure ArchivePathsAsync(const ASources: TArray<string>; const AZipFile: string;
  AOnDone: TFileOpDoneProc);
var
  Snapshot: TArray<string>;
  ZipPath: string;
begin
  Snapshot := Copy(ASources);
  ZipPath := AZipFile;
  if GFileOpMode = fomVibe then
  begin
    RunVibeOperation(okArchive, Snapshot, ZipPath, AOnDone);
    Exit;
  end;
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: string;
      Fine: Boolean;
    begin
      Fine := True;
      Err := '';
      try
        ArchivePathsCore(Snapshot, ZipPath);
      except
        on E: Exception do
        begin
          Fine := False;
          Err := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then
            AOnDone(Fine, Err);
        end);
    end).Start;
end;

procedure CopyVibeList(const ASources: TArray<string>; const ADestDir: string);
var
  Src: string;
begin
  for Src in ASources do
    CopyPathCore(Src, ADestDir);
end;

procedure ClearReadonlyAttr(const APath: string);
{$IFDEF MSWINDOWS}
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(APath));
  if (Attr <> INVALID_FILE_ATTRIBUTES) and
     ((Attr and FILE_ATTRIBUTE_READONLY) <> 0) then
    SetFileAttributes(PChar(APath), Attr and not FILE_ATTRIBUTE_READONLY);
{$ELSE}
begin
{$ENDIF}
end;

function SameVolumePath(const A, B: string): Boolean;
var
  RA, RB: string;
begin
  RA := ExtractFileDrive(A);
  RB := ExtractFileDrive(B);
  Result := (RA <> '') and SameText(RA, RB);
end;

function DestNameOf(const ADestDir, ASrc: string): string;
begin
  Result := TPath.Combine(ADestDir,
    TPath.GetFileName(ExcludeTrailingPathDelimiter(ASrc)));
end;

procedure FillPathMeta(const APath: string; out ASize: Int64; out ATime: TDateTime;
  out AIsDir: Boolean);
{$IFDEF MSWINDOWS}
var
  Data: TWin32FileAttributeData;
  Loc: TFileTime;
  ST: TSystemTime;
{$ENDIF}
var
  Parent: string;
  Kids: TArray<TArcChild>;
  C: TArcChild;
  Leaf: string;
begin
  ASize := 0;
  ATime := 0;
  AIsDir := OpIsDir(APath);
{$IFDEF MSWINDOWS}
  if GetFileAttributesEx(PChar(APath), GetFileExInfoStandard, @Data) then
  begin
    AIsDir := (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0;
    ASize := (Int64(Data.nFileSizeHigh) shl 32) or Int64(Data.nFileSizeLow);
    if FileTimeToLocalFileTime(Data.ftLastWriteTime, Loc) and
       FileTimeToSystemTime(Loc, ST) then
      ATime := SystemTimeToDateTime(ST);
    Exit;
  end;
{$ENDIF}
  if TFile.Exists(APath) then
  try
    ASize := TFile.GetSize(APath);
    ATime := TFile.GetLastWriteTime(APath);
  except
  end
  else if TDirectory.Exists(APath) then
  try
    ATime := TDirectory.GetLastWriteTime(APath);
  except
  end
  else
  begin
    Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(APath)));
    Leaf := TPath.GetFileName(ExcludeTrailingPathDelimiter(APath));
    if ListArchiveChildren(Parent, Kids) then
      for C in Kids do
        if SameText(C.Name, Leaf) then
        begin
          AIsDir := C.IsDir;
          ASize := C.Size;
          ATime := C.Modified;
          Break;
        end;
  end;
end;

function NextAutoName(const APath: string): string;
var
  Dir, FileName, Base, Ext, Core: string;
  N, Num, I: Integer;
begin
  Dir := ExtractFilePath(APath);
  FileName := TPath.GetFileName(APath);
  Ext := ExtractFileExt(FileName);
  Base := ChangeFileExt(FileName, '');
  if (Base = '') and (Length(FileName) > 1) and (FileName[1] = '.') then
  begin
    Base := FileName;
    Ext := '';
  end;
  Num := 1;  { name (1).ext, name (2).ext, ... }
  if (Length(Base) >= 4) and (Base[Length(Base)] = ')') then
  begin
    I := Length(Base) - 1;
    while (I > 0) and (Base[I] >= '0') and (Base[I] <= '9') do
      Dec(I);
    if (I >= 2) and (Base[I] = '(') and (Base[I - 1] = ' ') and (I < Length(Base) - 1) then
    begin
      Core := Copy(Base, 1, I - 2);
      Num := StrToIntDef(Copy(Base, I + 1, Length(Base) - I - 1), 0) + 1;
      if Num < 1 then Num := 1;
      Base := Core;
    end;
  end;
  N := Num;
  repeat
    Result := TPath.Combine(Dir, Format('%s (%d)%s', [Base, N, Ext]));
    Inc(N);
    if N > 10000 then
      Break;
  until not OpExists(Result);
end;

procedure CopyFileToDest(const ASrc, ADestPath: string);
var
  DestDir, Name, SrcName, Local, Tmp, TmpDir: string;
begin
  DestDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(ADestPath)));
  Name := TPath.GetFileName(ADestPath);
  SrcName := TPath.GetFileName(ExcludeTrailingPathDelimiter(ASrc));

  if ArchiveInvolved(ASrc, DestDir) then
  begin
    if SameText(SrcName, Name) then
    begin
      CopyArchiveEntry(ASrc, DestDir);
      Exit;
    end;
    if TFile.Exists(ASrc) then
      Local := ASrc
    else if not MaterializeArchiveFile(ASrc, Local) then
      raise Exception.Create('Не удалось прочитать: ' + SrcName);
    if SameText(TPath.GetFileName(Local), Name) then
    begin
      CopyArchiveEntry(Local, DestDir);
      Exit;
    end;
    TmpDir := TPath.Combine(TPath.GetTempPath, 'VibeCmd');
    ForceDirectories(TmpDir);
    Tmp := TPath.Combine(TmpDir, Name);
    if TFile.Exists(Tmp) then
    begin
      ClearReadonlyAttr(Tmp);
      TFile.Delete(Tmp);
    end;
    TFile.Copy(Local, Tmp, True);
    try
      CopyArchiveEntry(Tmp, DestDir);
    finally
      try
        TFile.Delete(Tmp);
      except
      end;
    end;
    Exit;
  end;

  ForceDirectories(DestDir);
  if TFile.Exists(ADestPath) then
    ClearReadonlyAttr(ADestPath);
  if TFile.Exists(ASrc) then
    TFile.Copy(ASrc, ADestPath, True)
  else if MaterializeArchiveFile(ASrc, Local) then
    TFile.Copy(Local, ADestPath, True)
  else
    CopyPathCore(ASrc, DestDir);
end;

function TryRemoveEmpty(const APath: string): Boolean;
begin
  Result := False;
  if not TDirectory.Exists(APath) then
    Exit(True);
  try
    if (Length(TDirectory.GetFiles(APath)) = 0) and
       (Length(TDirectory.GetDirectories(APath)) = 0) then
    begin
      TDirectory.Delete(APath, False);
      Result := True;
    end;
  except
    Result := False;
  end;
end;

type
  TListOpJob = class
    Sources: TArray<string>;
    DestDir: string;
    Move: Boolean;
    OnDone: TFileOpDoneProc;
    OnItem: TFileOpItemDoneProc;
    Conflicts: TList<TConflictItem>;
    Errors: TStringList;
    OrigFolders: TStringList;
    function Cancelled: Boolean;
    procedure Notify(const APath: string; AStatus: TOpItemStatus);
    function ListChildren(const APath: string; out AKids: TArray<string>): Boolean;
    function Process(const ASrc, ADestDir: string): TOpItemStatus;
    procedure AddConflict(const ASrc, ADst: string);
    function ApplyOne(const AIt: TConflictItem; AAct: TConflictAction): TOpItemStatus;
    function AskConflicts(out AActs: TArray<TConflictAction>): Boolean;
    procedure Run;
  end;

function TListOpJob.Cancelled: Boolean;
begin
  Result := GListOpCancel or Application.Terminated;
end;

procedure TListOpJob.Notify(const APath: string; AStatus: TOpItemStatus);
var
  P: string;
  S: TOpItemStatus;
  Cb: TFileOpItemDoneProc;
begin
  if not Assigned(OnItem) then
    Exit;
  P := APath;
  S := AStatus;
  Cb := OnItem;
  TThread.Queue(nil,
    procedure
    begin
      Cb(P, S);
    end);
end;

function TListOpJob.ListChildren(const APath: string; out AKids: TArray<string>): Boolean;
var
  F: string;
  Kids: TArray<TArcChild>;
  C: TArcChild;
  L: TList<string>;
begin
  SetLength(AKids, 0);
  L := TList<string>.Create;
  try
    if TDirectory.Exists(APath) then
    begin
      try
        for F in TDirectory.GetFiles(APath) do
          L.Add(F);
        for F in TDirectory.GetDirectories(APath) do
          L.Add(F);
      except
        on E: Exception do
        begin
          Errors.Add(TPath.GetFileName(APath) + ': ' + E.Message);
          Exit(False);
        end;
      end;
    end
    else if ListArchiveChildren(APath, Kids) then
    begin
      for C in Kids do
        L.Add(TPath.Combine(APath, C.Name));
    end
    else
      Exit(False);
    AKids := L.ToArray;
    Result := True;
  finally
    L.Free;
  end;
end;

procedure TListOpJob.AddConflict(const ASrc, ADst: string);
var
  It: TConflictItem;
begin
  It := Default(TConflictItem);
  It.SourcePath := ASrc;
  It.DestPath := ADst;
  FillPathMeta(ASrc, It.SourceSize, It.SourceTime, It.SourceIsDir);
  FillPathMeta(ADst, It.DestSize, It.DestTime, It.DestIsDir);
  It.SourceIsDir := False;
  Conflicts.Add(It);
end;

function TListOpJob.Process(const ASrc, ADestDir: string): TOpItemStatus;
var
  Dest, Child: string;
  SrcDir, DstDir, DstExists: Boolean;
  Kids: TArray<string>;
  ChildSt: TOpItemStatus;
  AnySkip, AnyErr, AnyPend, AnyOk: Boolean;
begin
  Result := oisError;
  if Cancelled then
    Exit(oisSkipped);
  if IsOfficeLockName(ASrc) then
  begin
    Notify(ASrc, oisError);
    Exit(oisError);
  end;
  if not OpExists(ASrc) then
  begin
    Errors.Add(TPath.GetFileName(ASrc) + ': источник исчез');
    Notify(ASrc, oisError);
    Exit(oisError);
  end;

  Dest := DestNameOf(ADestDir, ASrc);
  if SameText(ExcludeTrailingPathDelimiter(ASrc), ExcludeTrailingPathDelimiter(Dest)) then
  begin
    Notify(ASrc, oisSkipped);
    Exit(oisSkipped);
  end;

  SrcDir := OpIsDir(ASrc);
  DstExists := OpExists(Dest);
  DstDir := OpIsDir(Dest);

  if SrcDir then
  begin
    if DstExists and not DstDir then
    begin
      Errors.Add(TPath.GetFileName(ASrc) + ': тип не совпадает');
      Notify(ASrc, oisError);
      Exit(oisError);
    end;
    if not DstExists then
    try
      if TDirectory.Exists(ADestDir) or CanShellDiskPath(ADestDir) then
        ForceDirectories(Dest)
      else
        CreateArchiveFolder(ADestDir,
          TPath.GetFileName(ExcludeTrailingPathDelimiter(ASrc)));
    except
      on E: Exception do
      begin
        Errors.Add(TPath.GetFileName(ASrc) + ': ' + E.Message);
        Notify(ASrc, oisError);
        Exit(oisError);
      end;
    end;
    DstDir := True;
    DstExists := True;
  end;

  if not DstExists then
  begin
    try
      if Move and (not ArchiveInvolved(ASrc, ADestDir)) and
         TFile.Exists(ASrc) and SameVolumePath(ASrc, Dest) then
        TFile.Move(ASrc, Dest)
      else
      begin
        CopyPathCore(ASrc, ADestDir);
        if Move then
          DeletePathCore(ASrc, True);
      end;
      Result := oisOk;
    except
      on E: Exception do
      begin
        Errors.Add(TPath.GetFileName(ASrc) + ': ' + E.Message);
        Result := oisError;
      end;
    end;
    Notify(ASrc, Result);
    Exit;
  end;

  if SrcDir and DstDir then
  begin
    if not ListChildren(ASrc, Kids) then
    begin
      Notify(ASrc, oisError);
      Exit(oisError);
    end;
    AnySkip := False;
    AnyErr := False;
    AnyPend := False;
    AnyOk := False;
    for Child in Kids do
    begin
      if Cancelled then
      begin
        AnySkip := True;
        Continue;
      end;
      ChildSt := Process(Child, Dest);
      case ChildSt of
        oisOk: AnyOk := True;
        oisSkipped: AnySkip := True;
        oisConflictPending: AnyPend := True;
        oisError: AnyErr := True;
      end;
    end;
    if AnyErr then
      Result := oisError
    else if AnyPend then
      Result := oisConflictPending
    else if AnySkip then
      Result := oisSkipped
    else if AnyOk or (Length(Kids) = 0) then
      Result := oisOk
    else
      Result := oisSkipped;
    if Move and (Result = oisOk) then
      TryRemoveEmpty(ASrc);
    if OrigFolders.IndexOf(ASrc) >= 0 then
      Notify(ASrc, Result);
    Exit;
  end;

  if SrcDir <> DstDir then
  begin
    Errors.Add(TPath.GetFileName(ASrc) + ': тип не совпадает');
    Notify(ASrc, oisError);
    Exit(oisError);
  end;

  AddConflict(ASrc, Dest);
  Notify(ASrc, oisConflictPending);
  Result := oisConflictPending;
end;

function TListOpJob.ApplyOne(const AIt: TConflictItem; AAct: TConflictAction): TOpItemStatus;
var
  Dest: string;
begin
  Result := oisSkipped;
  if Cancelled then
    Exit;
  if not OpExists(AIt.SourcePath) then
  begin
    Errors.Add(TPath.GetFileName(AIt.SourcePath) + ': источник исчез');
    Notify(AIt.SourcePath, oisSkipped);
    Exit(oisSkipped);
  end;
  if AAct = caSkip then
  begin
    Notify(AIt.SourcePath, oisSkipped);
    Exit(oisSkipped);
  end;

  Dest := AIt.DestPath;
  if AAct = caAutoName then
  begin
    Dest := NextAutoName(AIt.DestPath);
    if (Dest = '') or SameText(ExcludeTrailingPathDelimiter(Dest),
       ExcludeTrailingPathDelimiter(AIt.DestPath)) then
    begin
      Errors.Add(TPath.GetFileName(AIt.SourcePath) + ': не удалось подобрать имя');
      Notify(AIt.SourcePath, oisError);
      Exit(oisError);
    end;
{$IFDEF MSWINDOWS}
    if (Length(Dest) > MAX_PATH) and not StartsText('\\?\', Dest) then
    begin
      Errors.Add(TPath.GetFileName(AIt.SourcePath) + ': имя длиннее MAX_PATH');
      Notify(AIt.SourcePath, oisError);
      Exit(oisError);
    end;
{$ENDIF}
  end
  else if not OpExists(Dest) then
  begin
    { dest исчез — как чистый }
  end;

  try
    CopyFileToDest(AIt.SourcePath, Dest);
    if Move then
      DeletePathCore(AIt.SourcePath, True);
    Result := oisOk;
  except
    on E: Exception do
    begin
      Errors.Add(TPath.GetFileName(AIt.SourcePath) + ': ' + E.Message);
      Result := oisError;
    end;
  end;
  Notify(AIt.SourcePath, Result);
end;

function TListOpJob.AskConflicts(out AActs: TArray<TConflictAction>): Boolean;
var
  Ev: TEvent;
  Ok: Boolean;
  Acts: TArray<TConflictAction>;
  Snapshot: TArray<TConflictItem>;
  I: Integer;
begin
  Result := False;
  SetLength(AActs, Conflicts.Count);
  for I := 0 to Conflicts.Count - 1 do
    AActs[I] := caSkip;
  if Conflicts.Count = 0 then
    Exit(True);
  if Cancelled then
    Exit(False);

  Snapshot := Conflicts.ToArray;
  Ev := TEvent.Create(nil, True, False, '');
  Ok := False;
  TThread.Queue(nil,
    procedure
    begin
      try
        if not Application.Terminated then
          Ok := ShowConflictDialog(Application.MainForm, Snapshot, Acts);
      finally
        Ev.SetEvent;
      end;
    end);
  while Ev.WaitFor(200) = wrTimeout do
    if Cancelled then
    begin
      Ev.Free;
      Exit(False);
    end;
  Ev.Free;
  if Length(Acts) = Length(AActs) then
    AActs := Acts;
  Result := Ok;
end;

procedure TListOpJob.Run;
var
  Src: string;
  Fine: Boolean;
  Err: string;
  Acts: TArray<TConflictAction>;
  I: Integer;
  DoneCb: TFileOpDoneProc;
begin
  Fine := True;
  Err := '';
  DoneCb := OnDone;
  Conflicts := TList<TConflictItem>.Create;
  Errors := TStringList.Create;
  OrigFolders := TStringList.Create;
  OrigFolders.CaseSensitive := False;
  try
    try
      for Src in Sources do
        if OpIsDir(Src) then
          OrigFolders.Add(Src);
      for Src in Sources do
      begin
        if Cancelled then
          Break;
        Process(Src, DestDir);
      end;
      if (Conflicts.Count > 0) and not Cancelled then
      begin
        if AskConflicts(Acts) then
        begin
          for I := 0 to Conflicts.Count - 1 do
          begin
            if Cancelled then
              Break;
            if I <= High(Acts) then
              ApplyOne(Conflicts[I], Acts[I])
            else
              ApplyOne(Conflicts[I], caSkip);
          end;
        end
        else
          for I := 0 to Conflicts.Count - 1 do
            Notify(Conflicts[I].SourcePath, oisSkipped);
      end;
      if not Cancelled then
        for Src in Sources do
          if OrigFolders.IndexOf(Src) >= 0 then
            Notify(Src, oisOk);
      if Cancelled then
      begin
        Fine := False;
        Err := 'Отменено';
      end
      else if Errors.Count > 0 then
      begin
        Fine := False;
        Err := Errors[0];
        if Errors.Count > 1 then
          Err := Err + Format(' (+%d)', [Errors.Count - 1]);
      end;
    except
      on E: Exception do
      begin
        Fine := False;
        Err := E.Message;
      end;
    end;
  finally
    Conflicts.Free;
    Errors.Free;
    OrigFolders.Free;
    TThread.Queue(nil,
      procedure
      begin
        GListOpBusy := False;
        if Assigned(DoneCb) then
          DoneCb(Fine, Err);
      end);
  end;
end;

procedure RunQuietCopyMove(const ASources: TArray<string>; const ADestDir: string;
  AMove: Boolean; AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc);
var
  Job: TListOpJob;
begin
  if Length(ASources) = 0 then
  begin
    if Assigned(AOnDone) then
      AOnDone(True, '');
    Exit;
  end;
  if GListOpBusy then
    Exit;
  GListOpBusy := True;
  GListOpCancel := False;
  Job := TListOpJob.Create;
  Job.Sources := Copy(ASources);
  Job.DestDir := ADestDir;
  Job.Move := AMove;
  Job.OnDone := AOnDone;
  Job.OnItem := AOnItemDone;
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        Job.Run;
      finally
        Job.Free;
      end;
    end).Start;
end;

procedure CopyPathsAsync(const ASources: TArray<string>; const ADestDir: string;
  AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc);
var
  Snapshot, Disk, Other: TArray<string>;
  Dest: string;
  Ok: Boolean;
  ErrMsg: string;
begin
  Snapshot := Copy(ASources);
  Dest := ADestDir;
  { V!be — свой движок и прогресс (конфликты в progress-форме). }
  if GFileOpMode = fomVibe then
  begin
    RunVibeOperation(okCopy, Snapshot, Dest, AOnDone, False, AOnItemDone);
    Exit;
  end;
  { Тихий — без progress и без Shell UI; конфликты имён через uConflictDialog. }
  if GFileOpMode = fomQuiet then
  begin
    RunQuietCopyMove(Snapshot, Dest, False, AOnDone, AOnItemDone);
    Exit;
  end;
  SplitDiskSources(Snapshot, Disk, Other);
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (Length(Disk) > 0) and CanShellDiskPath(Dest) and
     TDirectory.Exists(Dest) then
  begin
    if GFileOpMode = fomExplorer then
    begin
      Ok := True;
      ErrMsg := '';
      try
        if not ShellFileOp(FO_COPY, Disk, Dest, True) then
        begin
          Ok := False;
          ErrMsg := 'Копирование отменено или не удалось';
        end
        else
          CopyVibeList(Other, Dest);
      except
        on E: Exception do
        begin
          Ok := False;
          ErrMsg := E.Message;
        end;
      end;
      if Ok and Assigned(AOnItemDone) then
        for var S in Snapshot do
          AOnItemDone(S, oisOk);
      if Assigned(AOnDone) then
        AOnDone(Ok, ErrMsg);
      Exit;
    end;
  end;
{$ENDIF}
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: string;
      Fine: Boolean;
      Src: string;
    begin
      Fine := True;
      Err := '';
      try
{$IFDEF MSWINDOWS}
        if UseShellDiskOps and (Length(Disk) > 0) and CanShellDiskPath(Dest) and
           TDirectory.Exists(Dest) then
        begin
          if not ShellFileOp(FO_COPY, Disk, Dest, True) then
            CopyVibeList(Disk, Dest);
          CopyVibeList(Other, Dest);
        end
        else
{$ENDIF}
          for Src in Snapshot do
            CopyPathCore(Src, Dest);
      except
        on E: Exception do
        begin
          Fine := False;
          Err := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then
            AOnDone(Fine, Err);
        end);
    end).Start;
end;

procedure MovePathsAsync(const ASources: TArray<string>; const ADestDir: string;
  AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc);
var
  Snapshot, Disk, Other: TArray<string>;
  Dest: string;
  Ok: Boolean;
  ErrMsg: string;
  Src: string;
begin
  Snapshot := Copy(ASources);
  Dest := ADestDir;
  if GFileOpMode = fomVibe then
  begin
    RunVibeOperation(okMove, Snapshot, Dest, AOnDone, False, AOnItemDone);
    Exit;
  end;
  if GFileOpMode = fomQuiet then
  begin
    RunQuietCopyMove(Snapshot, Dest, True, AOnDone, AOnItemDone);
    Exit;
  end;
  SplitDiskSources(Snapshot, Disk, Other);
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (Length(Disk) > 0) and CanShellDiskPath(Dest) and
     TDirectory.Exists(Dest) then
  begin
    if GFileOpMode = fomExplorer then
    begin
      Ok := True;
      ErrMsg := '';
      try
        if not ShellFileOp(FO_MOVE, Disk, Dest, True) then
        begin
          Ok := False;
          ErrMsg := 'Перемещение отменено или не удалось';
        end
        else
          for Src in Other do
          begin
            CopyPathCore(Src, Dest);
            DeletePathCore(Src, True);
          end;
      except
        on E: Exception do
        begin
          Ok := False;
          ErrMsg := E.Message;
        end;
      end;
      if Ok and Assigned(AOnItemDone) then
        for var S in Snapshot do
          AOnItemDone(S, oisOk);
      if Assigned(AOnDone) then
        AOnDone(Ok, ErrMsg);
      Exit;
    end;
  end;
{$ENDIF}
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: string;
      Fine: Boolean;
      P: string;
    begin
      Fine := True;
      Err := '';
      try
{$IFDEF MSWINDOWS}
        if UseShellDiskOps and (Length(Disk) > 0) and CanShellDiskPath(Dest) and
           TDirectory.Exists(Dest) then
        begin
          if not ShellFileOp(FO_MOVE, Disk, Dest, True) then
            for P in Disk do
            begin
              CopyPathCore(P, Dest);
              DeletePathCore(P, True);
            end;
          for P in Other do
          begin
            CopyPathCore(P, Dest);
            DeletePathCore(P, True);
          end;
        end
        else
{$ENDIF}
          for P in Snapshot do
          begin
            CopyPathCore(P, Dest);
            DeletePathCore(P, True);
          end;
      except
        on E: Exception do
        begin
          Fine := False;
          Err := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then
            AOnDone(Fine, Err);
        end);
    end).Start;
end;

procedure DeleteDiskList(const APaths: TArray<string>; APermanent: Boolean);
var
  P: string;
begin
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (Length(APaths) > 0) then
  begin
    if ShellFileOp(FO_DELETE, APaths, '', not APermanent) then
      Exit;
    if not APermanent then
      raise Exception.Create('Удаление отменено или не удалось');
  end;
{$ENDIF}
  for P in APaths do
    DeletePathCore(P, APermanent);
end;

procedure DeletePathsAsync(const APaths: TArray<string>; AOnDone: TFileOpDoneProc;
  APermanent: Boolean);
var
  Snapshot: TArray<string>;
  Disk, Other: TArray<string>;
  Ok: Boolean;
  ErrMsg: string;
begin
  Snapshot := Copy(APaths);
  if GFileOpMode = fomVibe then
  begin
    RunVibeOperation(okDelete, Snapshot, '', AOnDone, APermanent);
    Exit;
  end;
  SplitDiskSources(Snapshot, Disk, Other);
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (GFileOpMode = fomExplorer) and (Length(Disk) > 0) then
  begin
    Ok := True;
    ErrMsg := '';
    try
      DeleteDiskList(Disk, APermanent);
      DeleteDiskList(Other, APermanent);
    except
      on E: Exception do
      begin
        Ok := False;
        ErrMsg := E.Message;
      end;
    end;
    if Assigned(AOnDone) then
      AOnDone(Ok, ErrMsg);
    Exit;
  end;
{$ENDIF}
  TThread.CreateAnonymousThread(
    procedure
    var
      Err, P, Z, Inner: string;
      Fine: Boolean;
      ByZip: TObjectDictionary<string, TStringList>;
      Regular: TStringList;
      Inners: TStringList;
      Pair: TPair<string, TStringList>;
      DropList: TArray<string>;
      K: Integer;
    begin
      Fine := True;
      Err := '';
      ByZip := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
      Regular := TStringList.Create;
      try
        try
          for P in Snapshot do
            if TryZipItem(P, Z, Inner) and (Inner <> '') then
            begin
              if not ByZip.TryGetValue(Z, Inners) then
              begin
                Inners := TStringList.Create;
                ByZip.Add(Z, Inners);
              end;
              Inners.Add(P);
            end
            else
              Regular.Add(P);

          for Pair in ByZip do
          begin
            SetLength(DropList, Pair.Value.Count);
            for K := 0 to Pair.Value.Count - 1 do
              DropList[K] := Pair.Value[K];
            DeleteArchiveEntries(DropList);
          end;

          SetLength(DropList, Regular.Count);
          for K := 0 to Regular.Count - 1 do
            DropList[K] := Regular[K];
          DeleteDiskList(DropList, APermanent);
        except
          on E: Exception do
          begin
            Fine := False;
            Err := E.Message;
          end;
        end;
      finally
        Regular.Free;
        ByZip.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(AOnDone) then
            AOnDone(Fine, Err);
        end);
    end).Start;
end;

end.
