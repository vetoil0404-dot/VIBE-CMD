unit uFileOps;

{
  Базовые файловые операции: копирование, перемещение, удаление,
  создание папки. Выполняются в фоновом потоке, чтобы не блокировать UI.
  V!be и Тихий: один engine и одна очередь. Тихий без вопроса «копировать?»
  и без диалогов проводника; спорные имена — окно uConflictDialog в конце пачки.
  Проводник: диалог Windows из своего STA-потока, без привязки к нашему окну.
  Проводник показывает процесс на пилюле средней панели.
  Тихий и V!be: локальный отказ в доступе — второе окно прав, одна пачка — один диалог.
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

  TLiveOpKind = (lokCopy, lokMove, lokDelete, lokRename);

  TLiveOpInfo = record
    Kind: TLiveOpKind;
    Source: string;
    Dest: string;
    Ok: Boolean;
    IsDir: Boolean;
    { -1: взять размер и дату из уже показанной строки, без опроса шары. }
    Size: Int64;
    Modified: TDateTime;
  end;

  TLiveOpProc = reference to procedure(const AInfo: TLiveOpInfo);

  { Результат тихого удаления одного пути. ddsElevate ждёт общего диалога. }
  TDiskDeleteStep = (ddsGone, ddsElevate, ddsFailed);

  { Без uses формы прогресса: иначе цикл uFileOps ↔ uFileOpProgressForm
    и uMain не видит FileOpHub*. }
  TVibeLaunchProc = reference to procedure(AKind: Integer;
    const ASources: TArray<string>; const ADest: string;
    AOnDone: TFileOpDoneProc; APermanent: Boolean;
    AOnItemDone: TFileOpItemDoneProc);

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

procedure SetVibeHooks(ALaunch: TVibeLaunchProc; ARestore: TFunc<Integer, Boolean>);
procedure SetFileOpHubChanged(AHandler: TNotifyEvent);
procedure NotifyFileOpHubChanged;

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
function TrySilentDiskDelete(const APath: string; APermanent: Boolean;
  out ACode: Cardinal): Boolean;
function DiskDeleteTarget(const APath: string): Boolean;
function DeleteTargetRemains(const APath: string): Boolean;
function AfterSilentDiskDelete(const APath: string; APermanent: Boolean;
  ACode: Cardinal; out AError: string): TDiskDeleteStep;
function ElevateDeniedDeletes(const APaths: TArray<string>; APermanent: Boolean;
  out ACancelled: Boolean; out AError: string): Boolean;
procedure SetFileOpMode(AMode: TFileOpMode);
function GetFileOpMode: TFileOpMode;
procedure SetFileOpOwnerWnd(AWnd: NativeUInt);
function QueryRecycleBin(out AItems, ABytes: Int64): Boolean;
function RestoreRecycleItems(const APaths: TArray<string>; out AError: string): Boolean;
function EmptyRecycleBin(out AError: string): Boolean;
function UndoLastDelete(out AError: string): Boolean;
procedure NotifyRecycleBinChanged;
procedure SetLiveOpHandler(const AHandler: TLiveOpProc);
procedure PublishLiveOp(const AInfo: TLiveOpInfo);
procedure ProbeLivePath(const APath: string);

implementation

uses
  System.SyncObjs, System.DateUtils, FMX.Types, FMX.Forms,
  uFileOpEngine, uArchiveEngine, uLang, uNetworkVfs, uFileLock
  {$IFDEF MSWINDOWS}, Winapi.ShlObj, Winapi.PropSys, Winapi.ActiveX{$ENDIF};

type
  TUndoDelete = record
    Sources: TArray<string>;
    Mark: Int64;
  end;

procedure CopyDirRecursive(const ASrc, ADst: string); forward;
procedure DeletePathCore(const APath: string; APermanent: Boolean); forward;
procedure ArchivePathsCore(const ASources: TArray<string>; const AZipFile: string); forward;
procedure CopyPathCore(const ASource, ADestDir: string); forward;
procedure RememberRecycleUndo(const ASources: TArray<string>); forward;
procedure ClearRecycleUndo; forward;
function CollectRecycleUndo(const ABatch: TUndoDelete): TArray<string>; forward;
function StartOpTrack(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; AQueued: Boolean): Integer; forward;

var
  GFileOpMode: TFileOpMode = fomVibe;
  GFileOpWnd: NativeUInt = 0;
  GListOpBusy: Boolean = False;
  GListOpCancel: Boolean = False;
  GListOpClosing: Boolean = False;
  GFileOpHubChanged: TNotifyEvent;
  GVibeLaunch: TVibeLaunchProc;
  GVibeRestore: TFunc<Integer, Boolean>;
  GUndoLock: TCriticalSection;
  GUndo: TList<TUndoDelete>;
  GLiveOp: TLiveOpProc;

type
  TLiveOpMsg = class
    Info: TLiveOpInfo;
    procedure Apply;
  end;

  TAttrProbe = class
    Path: string;
    Present: Boolean;
    procedure Apply;
  end;

  {$IFDEF MSWINDOWS}
  { Проводник: одна операция. Диск и архив идут параллельно, итог один. }
  TExplorerShell = class
    Kind: TLiveOpKind;
    Func: UINT;
    Disk, Other, Snapshot: TArray<string>;
    Dest, FailText, Err: string;
    AllowUndo, Permanent, Ok: Boolean;
    TrackId, Left: Integer;
    OnDone: TFileOpDoneProc;
    OnItem: TFileOpItemDoneProc;
    Lock: TCriticalSection;
    destructor Destroy; override;
    procedure Start;
    procedure RunDisk;
    procedure RunOther;
    procedure Note(AOk: Boolean; const AErr: string);
    procedure FinishUI;
  end;
  {$ENDIF}

procedure TLiveOpMsg.Apply;
var
  H: TLiveOpProc;
begin
  try
    H := GLiveOp;
    if Assigned(H) then
      H(Info);
  finally
    Free;
  end;
end;

procedure TAttrProbe.Apply;
var
  Info: TLiveOpInfo;
begin
  try
    if not Present then
    begin
      Info := Default(TLiveOpInfo);
      Info.Kind := lokDelete;
      Info.Source := Path;
      Info.Ok := True;
      PublishLiveOp(Info);
    end;
  finally
    Free;
  end;
end;

procedure SetLiveOpHandler(const AHandler: TLiveOpProc);
begin
  GLiveOp := AHandler;
end;

procedure PublishLiveOp(const AInfo: TLiveOpInfo);
var
  Msg: TLiveOpMsg;
  H: TLiveOpProc;
begin
  if not AInfo.Ok then
    Exit;
  if TThread.CurrentThread.ThreadID = MainThreadID then
  begin
    H := GLiveOp;
    if Assigned(H) then
      H(AInfo);
    Exit;
  end;
  Msg := TLiveOpMsg.Create;
  Msg.Info := AInfo;
  TThread.Queue(nil, Msg.Apply);
end;

procedure ProbeLivePath(const APath: string);
var
  P: string;
begin
  if APath = '' then
    Exit;
  P := APath;
  TThread.CreateAnonymousThread(
    procedure
    var
      Probe: TAttrProbe;
      Attr: Cardinal;
    begin
      Probe := TAttrProbe.Create;
      Probe.Path := P;
{$IFDEF MSWINDOWS}
      Attr := GetFileAttributes(PChar(P));
{$ELSE}
      Attr := INVALID_FILE_ATTRIBUTES;
{$ENDIF}
      Probe.Present := Attr <> INVALID_FILE_ATTRIBUTES;
      TThread.Queue(nil, Probe.Apply);
    end).Start;
end;

procedure PublishTopLevel(AKind: TLiveOpKind; const ASources: TArray<string>;
  const ADestDir: string);
var
  S, Name: string;
  Info: TLiveOpInfo;
begin
  for S in ASources do
  begin
    Info := Default(TLiveOpInfo);
    Info.Kind := AKind;
    Info.Source := S;
    Info.Ok := True;
    Info.Size := -1;
    Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(S));
    if (AKind <> lokDelete) and (ADestDir <> '') and (Name <> '') then
      Info.Dest := TPath.Combine(ExcludeTrailingPathDelimiter(ADestDir), Name);
    PublishLiveOp(Info);
  end;
end;

procedure EmitLiveOp(AKind: TLiveOpKind; const ASrc, ADst: string;
  AIsDir: Boolean; ASize: Int64; AModified: TDateTime);
var
  Info: TLiveOpInfo;
begin
  Info := Default(TLiveOpInfo);
  Info.Kind := AKind;
  Info.Source := ASrc;
  Info.Dest := ADst;
  Info.Ok := True;
  Info.IsDir := AIsDir;
  Info.Size := ASize;
  Info.Modified := AModified;
  PublishLiveOp(Info);
end;

procedure SetVibeHooks(ALaunch: TVibeLaunchProc; ARestore: TFunc<Integer, Boolean>);
begin
  GVibeLaunch := ALaunch;
  GVibeRestore := ARestore;
end;

procedure SetFileOpHubChanged(AHandler: TNotifyEvent);
begin
  GFileOpHubChanged := AHandler;
end;

procedure NotifyFileOpHubChanged;
begin
  if Assigned(GFileOpHubChanged) then
    GFileOpHubChanged(nil);
end;

procedure LaunchVibe(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; AOnDone: TFileOpDoneProc; APermanent: Boolean = False;
  AOnItemDone: TFileOpItemDoneProc = nil);
begin
  if Assigned(GVibeLaunch) then
    GVibeLaunch(Ord(AKind), ASources, ADest, AOnDone, APermanent, AOnItemDone)
  else if Assigned(AOnDone) then
    AOnDone(False, L('ops.notready'));
end;

function RestoreVibeKind(AKind: TFileOpKind): Boolean;
begin
  Result := Assigned(GVibeRestore) and GVibeRestore(Ord(AKind));
end;

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
  Result := RestoreVibeKind(okCopy);
end;

function RestoreVibeDeleteFromBackground: Boolean;
begin
  Result := RestoreVibeKind(okDelete);
end;

procedure CancelListFileOps;
begin
  GListOpClosing := True;
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

function ShellWinCode(ARet: Integer): Cardinal;
begin
  if (DWORD(ARet) and $FFFF0000) = $80070000 then
    Result := DWORD(ARet) and $FFFF
  else
    Result := DWORD(ARet);
end;

function ShellFileOpEx(AFunc: UINT; const AFrom: TArray<string>;
  const ATo: string; AFlags: FILEOP_FLAGS; out ACode: Cardinal;
  out AAborted: Boolean): Boolean;
var
  Op: TSHFileOpStruct;
  FromStr, ToStr, S: string;
  Ret: Integer;
begin
  ACode := 0;
  AAborted := False;
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
  { Проводник: 0, диалог не выключает наше окно. Тихий и V!be держат владельца. }
  if GFileOpMode = fomExplorer then
    Op.Wnd := 0
  else
    Op.Wnd := HWND(GFileOpWnd);
  Op.wFunc := AFunc;
  Op.pFrom := PChar(FromStr);
  if ATo <> '' then
    Op.pTo := PChar(ToStr);
  Op.fFlags := AFlags;
  Ret := SHFileOperation(Op);
  AAborted := Op.fAnyOperationsAborted;
  ACode := ShellWinCode(Ret);
  if AAborted and (ACode = 0) then
    ACode := ERROR_CANCELLED;
  Result := (Ret = 0) and not AAborted;
end;

function ShellFileOp(AFunc: UINT; const AFrom: TArray<string>;
  const ATo: string; AAllowUndo: Boolean): Boolean;
var
  Code: Cardinal;
  Aborted: Boolean;
begin
  Result := ShellFileOpEx(AFunc, AFrom, ATo, ShellFlags(AAllowUndo), Code, Aborted);
end;
{$ENDIF}

function UseShellDiskOps: Boolean;
begin
  Result := GFileOpMode in [fomQuiet, fomExplorer];
end;

function DeleteErrorWantsElevation(ACode: Cardinal): Boolean;
begin
  { 740 — ERROR_ELEVATION_REQUIRED, в Winapi.Windows его нет. }
  Result := (ACode = ERROR_ACCESS_DENIED) or (ACode = ERROR_PRIVILEGE_NOT_HELD) or
    (ACode = 740);
end;

function DiskShareDenied(ACode: Cardinal): Boolean;
begin
  Result := (ACode = ERROR_ACCESS_DENIED) or (ACode = ERROR_LOGON_FAILURE) or
    (ACode = ERROR_INVALID_PASSWORD) or
    (ACode = ERROR_SESSION_CREDENTIAL_CONFLICT);
end;

{$IFDEF MSWINDOWS}
function DiskDeleteIsNetwork(const APath: string): Boolean;
var
  Root, Unc: string;
  Kind: UINT;
begin
  Result := False;
  if APath = '' then
    Exit;
  if IsUncPath(APath) or IsVibeNetworkPath(APath) then
    Exit(True);
  if (Length(APath) < 2) or (APath[2] <> ':') then
    Exit;
  Root := UpCase(APath[1]) + ':\';
  Kind := GetDriveType(PChar(Root));
  if Kind = DRIVE_REMOTE then
    Exit(True);
  { Таблица подключений, без похода на шару. Пустой UNC — не сеть. }
  Unc := MappedDriveUnc(Root);
  Result := Unc <> '';
end;

function SilentDeleteFlags(AAllowUndo: Boolean): FILEOP_FLAGS;
begin
  Result := FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI or
    FOF_NOCONFIRMMKDIR;
  if AAllowUndo then
    Result := Result or FOF_ALLOWUNDO;
end;

function DeleteOpOwnerWnd: HWND;
var
  Fg: HWND;
  Pid: DWORD;
begin
  Result := HWND(GFileOpWnd);
  Fg := GetForegroundWindow;
  if Fg = 0 then
    Exit;
  Pid := 0;
  GetWindowThreadProcessId(Fg, Pid);
  if Pid = GetCurrentProcessId then
    Result := Fg;
end;

procedure RunOnUi(const AProc: TThreadProcedure);
begin
  if not Assigned(AProc) then
    Exit;
  if TThread.CurrentThread.ThreadID = MainThreadID then
    AProc()
  else
    TThread.Synchronize(nil, AProc);
end;
{$ENDIF}

function DeletePathCanElevate(const APath: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := CanShellDiskPath(APath) and IsWin32FsPath(APath) and
    not IsVibeNetworkPath(APath) and not DiskDeleteIsNetwork(APath);
{$ELSE}
  Result := False;
{$ENDIF}
end;

function DiskDeleteTarget(const APath: string): Boolean;
begin
  { Локальный диск, UNC и буква подключенной шары. Не архив и не network://. }
  Result := CanShellDiskPath(APath) and IsWin32FsPath(APath) and
    not IsVibeNetworkPath(APath);
end;

function DeleteTargetRemains(const APath: string): Boolean;
var
  Path: string;
{$IFDEF MSWINDOWS}
  Attr, Err: DWORD;
{$ENDIF}
begin
  Result := False;
  Path := ExcludeTrailingPathDelimiter(APath);
  if Path = '' then
    Exit;
{$IFDEF MSWINDOWS}
  Attr := GetFileAttributes(PChar(Path));
  if Attr <> INVALID_FILE_ATTRIBUTES then
    Exit(True);
  Err := GetLastError;
  { Отказ в атрибутах — объект есть. Нет файла — коды 2 и 3. }
  Result := (Err = ERROR_ACCESS_DENIED) or (Err = ERROR_PRIVILEGE_NOT_HELD) or
    (Err = 740);
{$ELSE}
  Result := TFile.Exists(Path) or TDirectory.Exists(Path);
{$ENDIF}
end;

function DiskDeleteFailText(ACode: Cardinal; APermanent: Boolean): string;
begin
  if ACode = ERROR_CANCELLED then
    Exit(L('op.cancelled'));
  if not APermanent then
    Exit(L('ops.recycle'));
  if DeleteErrorWantsElevation(ACode) then
    Exit(L('op.noaccess'));
  if ACode <> 0 then
  begin
    Result := Trim(SysErrorMessage(ACode));
    if Result = '' then
      Result := L('ops.delfail');
  end
  else
    Result := L('ops.delfail');
end;

function TrySilentDiskDelete(const APath: string; APermanent: Boolean;
  out ACode: Cardinal): Boolean;
{$IFDEF MSWINDOWS}
var
  Aborted: Boolean;
{$ENDIF}
begin
  ACode := 0;
{$IFDEF MSWINDOWS}
  Result := ShellFileOpEx(FO_DELETE, [APath], '',
    SilentDeleteFlags(not APermanent), ACode, Aborted);
  if Aborted and (ACode = 0) then
    ACode := ERROR_CANCELLED;
  if Aborted then
    Result := False;
{$ELSE}
  Result := False;
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
function ShareUncOf(const APath: string): string;
begin
  Result := '';
  if IsUncPath(APath) then
    Exit(APath);
  if (Length(APath) < 2) or (APath[2] <> ':') then
    Exit;
  Result := MappedDriveUnc(APath);
end;

function RetryDiskAfterLogon(const APath: string; APermanent: Boolean;
  ACode: Cardinal; out AError: string): Boolean;
var
  Unc: string;
  Code: Cardinal;
  Asked: Boolean;
begin
  AError := L('op.noaccess');
  Result := False;
  Unc := ShareUncOf(APath);
  if Unc = '' then
    Exit;
  Asked := False;
  RunOnUi(
    procedure
    begin
      Asked := PromptShareLogon(NativeUInt(DeleteOpOwnerWnd), Unc, ACode);
    end);
  if not Asked then
    Exit;
  Code := 0;
  if TrySilentDiskDelete(APath, APermanent, Code) then
    Exit(True);
  if not DeleteTargetRemains(APath) then
    Exit(True);
  AError := DiskDeleteFailText(Code, APermanent);
  if AError = '' then
    AError := L('op.noaccess');
  Result := False;
end;

function HrIsUserCancel(AHr: HRESULT): Boolean;
var
  U: Cardinal;
begin
  U := Cardinal(AHr);
  Result := (U = $800704C7) or (U = $80270000) or (U = $80270001);
end;

function ElevateOnThisThread(const APaths: TArray<string>; APermanent: Boolean;
  out ACancelled: Boolean; out AError: string): Boolean;
var
  HrInit, Hr: HRESULT;
  NeedUninit: Boolean;
  Op: IFileOperation;
  Item: IShellItem;
  Flags: DWORD;
  Added: Integer;
  P: string;
  Aborted: BOOL;
  AnyLeft: Boolean;
begin
  ACancelled := False;
  AError := '';
  Result := False;
  HrInit := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  NeedUninit := HrInit = S_OK;
  Op := nil;
  try
    try
      if Failed(CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_ALL,
          IFileOperation, Op)) or (Op = nil) then
      begin
        AError := L('op.noaccess');
        Exit;
      end;
      { Без FOF_SILENT и без FOF_NOERRORUI: иначе окна прав не будет.
        FOF_NOCONFIRMATION гасит только «точно удалить». }
      Flags := DWORD(FOF_NOCONFIRMATION) or DWORD(FOFX_SHOWELEVATIONPROMPT);
      if not APermanent then
        Flags := Flags or DWORD(FOF_ALLOWUNDO);
      Op.SetOperationFlags(Flags);
      if DeleteOpOwnerWnd <> 0 then
        Op.SetOwnerWindow(DeleteOpOwnerWnd);
      Added := 0;
      for P in APaths do
      begin
        if not DeleteTargetRemains(P) then
          Continue;
        Item := nil;
        if Succeeded(SHCreateItemFromParsingName(
            PChar(ExcludeTrailingPathDelimiter(P)), nil, IID_IShellItem, Item)) then
          if Item <> nil then
            if Succeeded(Op.DeleteItem(Item, nil)) then
              Inc(Added);
      end;
      if Added = 0 then
      begin
        AnyLeft := False;
        for P in APaths do
          if DeleteTargetRemains(P) then
            AnyLeft := True;
        if not AnyLeft then
          Exit(True);
        AError := L('op.noaccess');
        Exit;
      end;
      Hr := Op.PerformOperations;
      Aborted := False;
      Op.GetAnyOperationsAborted(Aborted);
      AnyLeft := False;
      for P in APaths do
        if DeleteTargetRemains(P) then
          AnyLeft := True;
      if not AnyLeft then
        Exit(True);
      if Aborted or HrIsUserCancel(Hr) then
      begin
        ACancelled := True;
        AError := L('op.cancelled');
        Exit;
      end;
      AError := L('op.noaccess');
    except
      on E: Exception do
      begin
        Result := False;
        if AError = '' then
          AError := E.Message;
      end;
    end;
  finally
    Op := nil;
    if NeedUninit then
      CoUninitialize;
  end;
end;
{$ENDIF}

function AfterSilentDiskDelete(const APath: string; APermanent: Boolean;
  ACode: Cardinal; out AError: string): TDiskDeleteStep;
begin
  AError := '';
  if not DeleteTargetRemains(APath) then
    Exit(ddsGone);
{$IFDEF MSWINDOWS}
  if DiskDeleteIsNetwork(APath) and DiskShareDenied(ACode) then
  begin
    if RetryDiskAfterLogon(APath, APermanent, ACode, AError) then
      Exit(ddsGone);
    Exit(ddsFailed);
  end;
{$ENDIF}
  if DeleteErrorWantsElevation(ACode) and DeletePathCanElevate(APath) then
    Exit(ddsElevate);
  AError := DiskDeleteFailText(ACode, APermanent);
  Result := ddsFailed;
end;

function ElevateDeniedDeletes(const APaths: TArray<string>; APermanent: Boolean;
  out ACancelled: Boolean; out AError: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Ok, Cancelled: Boolean;
  Err: string;
  Paths: TArray<string>;
  Perm: Boolean;
{$ENDIF}
begin
  ACancelled := False;
  AError := '';
  if Length(APaths) = 0 then
    Exit(True);
{$IFDEF MSWINDOWS}
  Paths := Copy(APaths);
  Perm := APermanent;
  Ok := False;
  Cancelled := False;
  Err := '';
  RunOnUi(
    procedure
    begin
      Ok := ElevateOnThisThread(Paths, Perm, Cancelled, Err);
    end);
  ACancelled := Cancelled;
  AError := Err;
  if AError = '' then
    AError := L('op.noaccess');
  Result := Ok;
  if Result then
    AError := '';
{$ELSE}
  AError := L('ops.delfail');
  Result := False;
{$ENDIF}
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
        raise Exception.Create(Lf('ops.copydev', [TargetName]));
      end;
      if IsVirtualShellPath(ADestDir) or IsPortableDevicePath(ADestDir) then
      begin
        if ShellTransfer(ASource, ADestDir) then
          Exit;
        raise Exception.Create(Lf('ops.copytodev', [TargetName]));
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
function ShellDeletePath(const APath: string; APermanent: Boolean;
  out ACode: Cardinal): Boolean;
var
  Aborted: Boolean;
begin
  Result := ShellFileOpEx(FO_DELETE, [APath], '', ShellFlags(not APermanent),
    ACode, Aborted);
end;
{$ENDIF}

procedure DeletePathCore(const APath: string; APermanent: Boolean);
var
  Z, Inner: string;
  {$IFDEF MSWINDOWS}
  Code: Cardinal;
  procedure FailOs(ACode: Cardinal; const AMsg: string);
  var
    E: EOSError;
  begin
    E := EOSError.Create(AMsg);
    E.ErrorCode := ACode;
    raise E;
  end;
  {$ENDIF}
begin
  if TryZipItem(APath, Z, Inner) and (Inner <> '') then
  begin
    DeleteArchiveEntry(APath);
    Exit;
  end;

  {$IFDEF MSWINDOWS}
  if UseShellDiskOps then
  begin
    if not ShellDeletePath(APath, APermanent, Code) then
    begin
      if APermanent then
      begin
        if TDirectory.Exists(APath) then
          TDirectory.Delete(APath, True)
        else if not DeleteFile(PChar(APath)) then
        begin
          Code := GetLastError;
          FailOs(Code, SysErrorMessage(Code) + sLineBreak + '[' + APath + ']');
        end;
      end
      else
        FailOs(Code, L('ops.recycle'));
    end;
    Exit;
  end;
  if not APermanent then
  begin
    if not ShellDeletePath(APath, False, Code) then
      FailOs(Code, L('ops.recycle'));
    Exit;
  end;
  if not TDirectory.Exists(APath) then
  begin
    if not DeleteFile(PChar(APath)) then
    begin
      Code := GetLastError;
      FailOs(Code, SysErrorMessage(Code) + sLineBreak + '[' + APath + ']');
    end;
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
  DeletePathsAsync([APath], AOnDone, APermanent);
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
  ParentDir, Z, Inner, Temp: string;

  function TryWinMove(const AFrom, ATo: string): Boolean;
  var
    Code: Cardinal;
  begin
    repeat
      if MoveFile(PChar(ExcludeTrailingPathDelimiter(AFrom)),
                  PChar(ExcludeTrailingPathDelimiter(ATo))) then
        Exit(True);
      Code := GetLastError;
      if FileLockOffer(AFrom, Code) <> flcRetry then
        Exit(False);
    until False;
  end;

  function CaseTempPath(const ADir, ALeaf: string): string;
  var
    N: Integer;
    Candidate: string;
  begin
    Result := '';
    N := 0;
    repeat
      if N = 0 then
        Candidate := TPath.Combine(ADir, ALeaf + '.~vibe')
      else
        Candidate := TPath.Combine(ADir, ALeaf + '.~vibe' + IntToStr(N));
      Inc(N);
      if not (TFile.Exists(Candidate) or TDirectory.Exists(Candidate)) then
        Exit(Candidate);
    until N > 10000;
  end;

begin
  Result := False;
  ANewPath := '';
  FileLockReset;
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
  { Тот же путь с тем же регистром: диск не трогаем. }
  if SameStr(AOldPath, ANewPath) then
    Exit(True);
  { NTFS не меняет регистр прямым Move: имя для системы то же. }
  if SameText(AOldPath, ANewPath) then
  begin
    Temp := CaseTempPath(ParentDir,
      ExtractFileName(ExcludeTrailingPathDelimiter(AOldPath)));
    if Temp = '' then
      Exit;
    if not TryWinMove(AOldPath, Temp) then
      Exit;
    if not TryWinMove(Temp, ANewPath) then
    begin
      if not TryWinMove(Temp, AOldPath) then
        raise Exception.Create(L('op.noaccess') + sLineBreak + Temp);
      Exit;
    end;
    Exit(True);
  end;
  Result := TryWinMove(AOldPath, ANewPath);
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
  TrackId: Integer;
begin
  Snapshot := Copy(ASources);
  ZipPath := AZipFile;
  if GFileOpMode = fomVibe then
  begin
    LaunchVibe(okArchive, Snapshot, ZipPath, AOnDone);
    Exit;
  end;
  TrackId := StartOpTrack(okArchive, Snapshot, ZipPath, False);
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: string;
      Fine: Boolean;
    begin
      Fine := True;
      Err := '';
      try
        if FileOpTrackCancelled(TrackId) then
          raise Exception.Create(L('op.cancelled'));
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
          FileOpTrackEnd(TrackId);
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


{$IFDEF MSWINDOWS}
destructor TExplorerShell.Destroy;
begin
  Lock.Free;
  inherited;
end;

procedure TExplorerShell.Note(AOk: Boolean; const AErr: string);
var
  Done: Boolean;
begin
  Done := False;
  Lock.Enter;
  try
    if not AOk then
    begin
      Ok := False;
      if Err = '' then
        Err := AErr;
    end;
    Dec(Left);
    if Left <= 0 then
      Done := True;
  finally
    Lock.Leave;
  end;
  if Done then
    TThread.Queue(nil, FinishUI);
end;

procedure TExplorerShell.FinishUI;
var
  S: string;
begin
  try
    FileOpTrackEnd(TrackId);
    if Ok then
    begin
      PublishTopLevel(Kind, Snapshot, Dest);
      { Удаление и раньше не звало OnItem: строки снимает публикация. }
      if (Kind <> lokDelete) and Assigned(OnItem) then
        for S in Snapshot do
          OnItem(S, oisOk);
    end
    else
      for S in Snapshot do
        ProbeLivePath(S);
    if Assigned(OnDone) then
      OnDone(Ok, Err);
  finally
    Free;
  end;
end;

procedure TExplorerShell.RunDisk;
var
  HrInit: HRESULT;
  NeedUninit, Fine, Aborted: Boolean;
  Code: Cardinal;
  Msg: TMsg;
  ErrText: string;
begin
  Fine := True;
  ErrText := '';
  HrInit := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  NeedUninit := HrInit = S_OK;
  try
    try
      { Очередь потока до диалога, иначе проводник не рисуется.
        После возврата SHFileOperation свой цикл не крутим. }
      PeekMessage(Msg, 0, 0, 0, PM_NOREMOVE);
      if not ShellFileOpEx(Func, Disk, Dest, ShellFlags(AllowUndo), Code, Aborted) then
      begin
        Fine := False;
        if Aborted or (Code = ERROR_CANCELLED) then
          ErrText := L('op.cancelled')
        else if FailText <> '' then
          ErrText := FailText
        else
          ErrText := L('ops.delfail');
      end;
    except
      on E: Exception do
      begin
        Fine := False;
        ErrText := E.Message;
      end;
    end;
  finally
    if NeedUninit then
      CoUninitialize;
    Note(Fine, ErrText);
  end;
end;

procedure TExplorerShell.RunOther;
var
  HrInit: HRESULT;
  NeedUninit, Fine: Boolean;
  Msg: TMsg;
  ErrText, P, Z, Inner: string;
  Zips, Rest: TList<string>;
begin
  Fine := True;
  ErrText := '';
  HrInit := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  NeedUninit := HrInit = S_OK;
  try
    try
      PeekMessage(Msg, 0, 0, 0, PM_NOREMOVE);
      if Func = FO_DELETE then
      begin
        Zips := TList<string>.Create;
        Rest := TList<string>.Create;
        try
          for P in Other do
            if TryZipItem(P, Z, Inner) and (Inner <> '') then
              Zips.Add(P)
            else
              Rest.Add(P);
          if Zips.Count > 0 then
            DeleteArchiveEntries(Zips.ToArray);
          for P in Rest do
            DeletePathCore(P, Permanent);
        finally
          Rest.Free;
          Zips.Free;
        end;
      end
      else if Func = FO_MOVE then
      begin
        for P in Other do
        begin
          CopyPathCore(P, Dest);
          DeletePathCore(P, True);
        end;
      end
      else
        CopyVibeList(Other, Dest);
    except
      on E: Exception do
      begin
        Fine := False;
        ErrText := E.Message;
      end;
    end;
  finally
    if NeedUninit then
      CoUninitialize;
    Note(Fine, ErrText);
  end;
end;

procedure TExplorerShell.Start;
var
  Parts: Integer;
begin
  Ok := True;
  Err := '';
  Parts := 0;
  if Length(Disk) > 0 then
    Inc(Parts);
  if Length(Other) > 0 then
    Inc(Parts);
  if Parts = 0 then
  begin
    FinishUI;
    Exit;
  end;
  Lock := TCriticalSection.Create;
  Left := Parts;
  if Length(Disk) > 0 then
    TThread.CreateAnonymousThread(
      procedure
      begin
        RunDisk;
      end).Start;
  if Length(Other) > 0 then
    TThread.CreateAnonymousThread(
      procedure
      begin
        RunOther;
      end).Start;
end;

procedure LaunchExplorerOp(AKind: TLiveOpKind; AFunc: UINT;
  const ADisk, AOther, ASnapshot: TArray<string>; const ADest, AFail: string;
  AAllowUndo, APermanent: Boolean; ATrack: Integer;
  AOnDone: TFileOpDoneProc; AOnItem: TFileOpItemDoneProc);
var
  Job: TExplorerShell;
begin
  Job := TExplorerShell.Create;
  Job.Kind := AKind;
  Job.Func := AFunc;
  Job.Disk := ADisk;
  Job.Other := AOther;
  Job.Snapshot := ASnapshot;
  Job.Dest := ADest;
  Job.FailText := AFail;
  Job.AllowUndo := AAllowUndo;
  Job.Permanent := APermanent;
  Job.TrackId := ATrack;
  Job.OnDone := AOnDone;
  Job.OnItem := AOnItem;
  Job.Start;
end;
{$ENDIF}

function StartOpTrack(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; AQueued: Boolean): Integer;
var
  Detail, DestName: string;
begin
  Result := 0;
  if not (GFileOpMode in [fomQuiet, fomExplorer]) then
    Exit;
  if Length(ASources) = 0 then
    Exit;
  if Length(ASources) = 1 then
    Detail := TPath.GetFileName(ExcludeTrailingPathDelimiter(ASources[0]))
  else
    Detail := LCount(Length(ASources), 'op.obj.one', 'op.obj.few', 'op.obj.many');
  if ADest <> '' then
  begin
    DestName := TPath.GetFileName(ExcludeTrailingPathDelimiter(ADest));
    if DestName = '' then
      DestName := ExcludeTrailingPathDelimiter(ADest);
    if DestName <> '' then
      Detail := Detail + ' → ' + DestName;
  end;
  Result := FileOpTrackBegin(AKind, Detail, AQueued);
end;

procedure CopyPathsAsync(const ASources: TArray<string>; const ADestDir: string;
  AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc);
var
  Snapshot, Disk, Other: TArray<string>;
  Dest: string;
  TrackId: Integer;
begin
  Snapshot := Copy(ASources);
  Dest := ADestDir;
  { V!be и Тихий — один движок, одна очередь. Проводник ниже не трогаем. }
  if GFileOpMode in [fomVibe, fomQuiet] then
  begin
    LaunchVibe(okCopy, Snapshot, Dest, AOnDone, False, AOnItemDone);
    Exit;
  end;
  TrackId := StartOpTrack(okCopy, Snapshot, Dest, False);
  SplitDiskSources(Snapshot, Disk, Other);
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (Length(Disk) > 0) and CanShellDiskPath(Dest) and
     TDirectory.Exists(Dest) then
  begin
    if GFileOpMode = fomExplorer then
    begin
      LaunchExplorerOp(lokCopy, FO_COPY, Disk, Other, Snapshot, Dest,
        L('ops.copyfail'), True, False, TrackId, AOnDone, AOnItemDone);
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
        if FileOpTrackCancelled(TrackId) then
          raise Exception.Create(L('op.cancelled'));
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
          begin
            if FileOpTrackCancelled(TrackId) then
              raise Exception.Create(L('op.cancelled'));
            CopyPathCore(Src, Dest);
          end;
      except
        on E: Exception do
        begin
          Fine := False;
          Err := E.Message;
        end;
      end;
      if Fine then
        PublishTopLevel(lokCopy, Snapshot, Dest)
      else
        for Src in Snapshot do
          ProbeLivePath(Src);
      TThread.Queue(nil,
        procedure
        begin
          FileOpTrackEnd(TrackId);
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
  TrackId: Integer;
begin
  Snapshot := Copy(ASources);
  Dest := ADestDir;
  if GFileOpMode in [fomVibe, fomQuiet] then
  begin
    LaunchVibe(okMove, Snapshot, Dest, AOnDone, False, AOnItemDone);
    Exit;
  end;
  TrackId := StartOpTrack(okMove, Snapshot, Dest, False);
  SplitDiskSources(Snapshot, Disk, Other);
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (Length(Disk) > 0) and CanShellDiskPath(Dest) and
     TDirectory.Exists(Dest) then
  begin
    if GFileOpMode = fomExplorer then
    begin
      LaunchExplorerOp(lokMove, FO_MOVE, Disk, Other, Snapshot, Dest,
        L('ops.movefail'), True, False, TrackId, AOnDone, AOnItemDone);
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
        if FileOpTrackCancelled(TrackId) then
          raise Exception.Create(L('op.cancelled'));
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
            if FileOpTrackCancelled(TrackId) then
              raise Exception.Create(L('op.cancelled'));
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
      if Fine then
        PublishTopLevel(lokMove, Snapshot, Dest)
      else
        for P in Snapshot do
          ProbeLivePath(P);
      TThread.Queue(nil,
        procedure
        begin
          FileOpTrackEnd(TrackId);
          if Assigned(AOnDone) then
            AOnDone(Fine, Err);
        end);
    end).Start;
end;

{$IFDEF MSWINDOWS}
procedure NoteDiskFail(const AErr: string; APermanent: Boolean;
  var AFirst: string);
var
  Msg: string;
begin
  Msg := AErr;
  if (not APermanent) and (Msg <> L('op.cancelled')) and
     (Msg <> L('op.noaccess')) then
    Msg := L('ops.delfail');
  if (AFirst = '') and (Msg <> '') then
    AFirst := Msg;
end;

procedure CollectDeniedDeletes(const APaths: TArray<string>; APermanent: Boolean;
  AElevate: TList<string>; var AFirst: string);
var
  P, Err: string;
  Code: Cardinal;
  Step: TDiskDeleteStep;
begin
  for P in APaths do
  begin
    if not DiskDeleteTarget(P) then
    begin
      try
        DeletePathCore(P, APermanent);
      except
        on E: Exception do
          NoteDiskFail(E.Message, APermanent, AFirst);
      end;
      Continue;
    end;
    if not DeleteTargetRemains(P) then
      Continue;
    Code := 0;
    if TrySilentDiskDelete(P, APermanent, Code) then
      Continue;
    Step := AfterSilentDiskDelete(P, APermanent, Code, Err);
    case Step of
      ddsGone: ;
      ddsElevate:
        AElevate.Add(P);
      ddsFailed:
        NoteDiskFail(Err, APermanent, AFirst);
    end;
  end;
end;

procedure FinishDeniedDeletes(AElevate: TList<string>; APermanent: Boolean;
  const AFirst: string);
var
  Cancelled: Boolean;
  ElevErr: string;
begin
  Cancelled := False;
  ElevErr := '';
  if AElevate.Count > 0 then
  begin
    if not ElevateDeniedDeletes(AElevate.ToArray, APermanent, Cancelled, ElevErr) then
    begin
      if Cancelled and (AFirst = '') then
        raise Exception.Create(L('op.cancelled'));
      if (not Cancelled) and (AFirst = '') then
        raise Exception.Create(ElevErr);
    end;
  end;
  if AFirst <> '' then
    raise Exception.Create(AFirst);
end;

procedure DeleteQuietList(const APaths: TArray<string>; APermanent: Boolean);
var
  Elevate: TList<string>;
  FirstErr: string;
  Code: Cardinal;
  Aborted: Boolean;
begin
  if ShellFileOpEx(FO_DELETE, APaths, '', SilentDeleteFlags(not APermanent),
       Code, Aborted) then
    Exit;
  if Aborted or (Code = ERROR_CANCELLED) then
    raise Exception.Create(L('op.cancelled'));
  Elevate := TList<string>.Create;
  try
    FirstErr := '';
    CollectDeniedDeletes(APaths, APermanent, Elevate, FirstErr);
    FinishDeniedDeletes(Elevate, APermanent, FirstErr);
  finally
    Elevate.Free;
  end;
end;

procedure DeleteExplorerList(const APaths: TArray<string>; APermanent: Boolean);
var
  Code: Cardinal;
  Aborted: Boolean;
begin
  { Один диалог проводника. Окно прав — то, что покажет он сам. }
  if ShellFileOpEx(FO_DELETE, APaths, '', ShellFlags(not APermanent),
       Code, Aborted) then
    Exit;
  if Aborted or (Code = ERROR_CANCELLED) then
    raise Exception.Create(L('op.cancelled'));
  raise Exception.Create(L('ops.delfail'));
end;
{$ENDIF}

procedure DeleteDiskList(const APaths: TArray<string>; APermanent: Boolean);
var
  P: string;
begin
  if Length(APaths) = 0 then
    Exit;
{$IFDEF MSWINDOWS}
  if UseShellDiskOps then
  begin
    if GFileOpMode = fomExplorer then
      DeleteExplorerList(APaths, APermanent)
    else
      DeleteQuietList(APaths, APermanent);
    Exit;
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
  TrackId: Integer;
  Caller: TFileOpDoneProc;
begin
  Snapshot := Copy(APaths);
  Caller := AOnDone;
  if not APermanent then
    AOnDone :=
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if Success then
          RememberRecycleUndo(Snapshot);
        if Assigned(Caller) then
          Caller(Success, ErrorMsg);
      end;
  if GFileOpMode in [fomVibe, fomQuiet] then
  begin
    LaunchVibe(okDelete, Snapshot, '', AOnDone, APermanent);
    Exit;
  end;
  TrackId := StartOpTrack(okDelete, Snapshot, '', False);
  SplitDiskSources(Snapshot, Disk, Other);
{$IFDEF MSWINDOWS}
  if UseShellDiskOps and (GFileOpMode = fomExplorer) then
  begin
    LaunchExplorerOp(lokDelete, FO_DELETE, Disk, Other, Snapshot, '',
      L('ops.delfail'), not APermanent, APermanent, TrackId, AOnDone, nil);
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
          if FileOpTrackCancelled(TrackId) then
            raise Exception.Create(L('op.cancelled'));
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
      if Fine then
        PublishTopLevel(lokDelete, Snapshot, '')
      else
        for P in Snapshot do
          ProbeLivePath(P);
      TThread.Queue(nil,
        procedure
        begin
          FileOpTrackEnd(TrackId);
          if Assigned(AOnDone) then
            AOnDone(Fine, Err);
        end);
    end).Start;
end;

function NormBinPath(const S: string): string;
begin
  Result := Trim(S);
  if Result = '' then
    Exit;
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  if StartsText('\\?\', Result) then
    Delete(Result, 1, 4);
  Result := UpperCase(ExcludeTrailingPathDelimiter(Result));
end;

function CombineBinPath(const ADir, AName: string): string;
var
  Dir, Name: string;
begin
  Dir := ExcludeTrailingPathDelimiter(Trim(StringReplace(ADir, '/', '\', [rfReplaceAll])));
  Name := Trim(StringReplace(AName, '/', '\', [rfReplaceAll]));
  if Name <> '' then
    Name := ExtractFileName(ExcludeTrailingPathDelimiter(Name));
  if (Dir <> '') and (Name <> '') then
    Result := Dir + '\' + Name
  else if Dir <> '' then
    Result := Dir
  else
    Result := Name;
end;

{$IFDEF MSWINDOWS}
type
  { shell32 пишет Int64 вплотную к cbSize. Без packed читаем на 4 байта мимо. }
  TSHQueryRBInfo = packed record
    cbSize: DWORD;
    i64Size: Int64;
    i64NumItems: Int64;
  end;

function SHQueryRecycleBinW(pszRootPath: PWideChar; var Info: TSHQueryRBInfo): HRESULT;
  stdcall; external 'shell32.dll' name 'SHQueryRecycleBinW';
function SHEmptyRecycleBinW(Wnd: HWND; pszRootPath: PWideChar; dwFlags: DWORD): HRESULT;
  stdcall; external 'shell32.dll' name 'SHEmptyRecycleBinW';
procedure SHUpdateRecycleBinIcon; stdcall; external 'shell32.dll' name 'SHUpdateRecycleBinIcon';

function ShellItemFromPath(const APath: string; out AItem: IShellItem): Boolean;
begin
  AItem := nil;
  Result := (Trim(APath) <> '') and
    Succeeded(SHCreateItemFromParsingName(PChar(APath), nil, IID_IShellItem, AItem)) and
    Assigned(AItem);
end;

type
  TBinHit = record
    Rel: PItemIDList;
    Body: string;
    Parse: string;
    Orig: string;
    From: string;
    Leaf: string;
    Item: IShellItem;
    WasThere: Boolean;
    Listed: Boolean;
  end;

procedure FreeBinHits(var AHits: TArray<TBinHit>);
var
  I: Integer;
begin
  for I := 0 to High(AHits) do
  begin
    if AHits[I].Rel <> nil then
      ILFree(AHits[I].Rel);
    AHits[I].Rel := nil;
    AHits[I].Item := nil;
  end;
  SetLength(AHits, 0);
end;

function RecycleBodyPresent(const APath: string): Boolean;
var
  Attr: DWORD;
begin
  Result := False;
  if APath = '' then
    Exit;
  Attr := GetFileAttributes(PChar(APath));
  Result := Attr <> INVALID_FILE_ATTRIBUTES;
end;

function RecycleFsBody(const APath: string): Boolean;
begin
  Result := IsRecycleItemPath(APath) and
    (Pos('\$RECYCLE.BIN\', UpperCase(APath)) > 0);
end;

function OpenRecycleFolder(out ABin: IShellItem; out AFolder: IShellFolder;
  out AParent: PItemIDList): Boolean;
begin
  ABin := nil;
  AFolder := nil;
  AParent := nil;
  Result := ShellItemFromPath(RecycleBinPath, ABin) and
    Succeeded(ABin.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, AFolder)) and
    (AFolder <> nil);
  if not Result then
    Exit;
  SHGetIDListFromObject(ABin, AParent);
end;

function CollectBinHits(const APaths: TArray<string>; const AFolder: IShellFolder;
  AParent: PItemIDList; out AHits: TArray<TBinHit>): Integer;
const
  KeyFrom: TPropertyKey = (
    fmtid: '{9B174B33-40FF-11D2-A27E-00C04FC30871}'; pid: 2);
var
  Want, Seen: TDictionary<string, Byte>;
  Enum: IEnumIDList;
  Child: PItemIDList;
  Fetched: ULONG;
  ChildItem: IShellItem;
  Item2: IShellItem2;
  P: PWideChar;
  S, Body, Parse, Disp, From, Key: string;
  Hit: TBinHit;
  N: Integer;
begin
  SetLength(AHits, 0);
  Result := 0;
  if (AFolder = nil) or (Length(APaths) = 0) then
    Exit;
  Want := TDictionary<string, Byte>.Create;
  Seen := TDictionary<string, Byte>.Create;
  try
    for S in APaths do
    begin
      Key := NormBinPath(S);
      if Key <> '' then
        Want.AddOrSetValue(Key, 0);
    end;
    if Want.Count = 0 then
      Exit;
    if Failed(AFolder.EnumObjects(0, SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or
       SHCONTF_INCLUDEHIDDEN or SHCONTF_STORAGE, Enum)) or (Enum = nil) then
      Exit;
    Fetched := 0;
    N := 0;
    while Enum.Next(1, Child, Fetched) = S_OK do
    try
      ChildItem := nil;
      if Failed(SHCreateItemWithParent(AParent, AFolder, Child, IID_IShellItem,
         ChildItem)) or (ChildItem = nil) then
        Continue;
      Body := '';
      Parse := '';
      Disp := '';
      From := '';
      P := nil;
      if Succeeded(ChildItem.GetDisplayName(SIGDN_FILESYSPATH, P)) and (P <> nil) then
      begin
        Body := string(P);
        CoTaskMemFree(P);
      end;
      P := nil;
      if Succeeded(ChildItem.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, P)) and
         (P <> nil) then
      begin
        Parse := string(P);
        CoTaskMemFree(P);
      end;
      if Body = '' then
        Body := Parse;
      Key := NormBinPath(Body);
      if (Key = '') or not Want.ContainsKey(Key) then
      begin
        Key := NormBinPath(Parse);
        if (Key = '') or not Want.ContainsKey(Key) then
          Continue;
      end;
      if Seen.ContainsKey(Key) then
        Continue;
      P := nil;
      if Succeeded(ChildItem.GetDisplayName(SIGDN_NORMALDISPLAY, P)) and
         (P <> nil) then
      begin
        Disp := StringReplace(string(P), '/', '\', [rfReplaceAll]);
        CoTaskMemFree(P);
      end;
      Item2 := nil;
      if Supports(ChildItem, IShellItem2, Item2) then
      begin
        P := nil;
        if Succeeded(Item2.GetString(KeyFrom, P)) and (P <> nil) then
        begin
          From := string(P);
          CoTaskMemFree(P);
        end;
      end;
      Hit := Default(TBinHit);
      Hit.Rel := ILClone(Child);
      if Hit.Rel = nil then
        Continue;
      { FILESYSPATH иногда равен исходному пути. Его нет на диске ещё до
        восстановления, и по нему нельзя решить, что элемент ушёл из Корзины. }
      Hit.Parse := Parse;
      if RecycleFsBody(Parse) then
        Hit.Body := Parse
      else if RecycleFsBody(Body) then
        Hit.Body := Body
      else
        Hit.Body := '';
      Hit.From := From;
      Hit.Leaf := Disp;
      if (Disp <> '') and
         ((Pos('\', Disp) > 0) or (Pos(':', Disp) > 0) or StartsText('\\', Disp)) then
        Hit.Orig := Disp
      else
        Hit.Orig := CombineBinPath(From, Disp);
      Hit.Item := ChildItem;
      Hit.WasThere := (Hit.Body <> '') and RecycleBodyPresent(Hit.Body);
      Hit.Listed := True;
      Seen.Add(Key, 0);
      if N > High(AHits) then
        SetLength(AHits, N + 8);
      AHits[N] := Hit;
      Inc(N);
    finally
      CoTaskMemFree(Child);
    end;
    SetLength(AHits, N);
    Result := N;
  finally
    Want.Free;
    Seen.Free;
  end;
end;

function MenuVerbId(const AMenu: IContextMenu; APop: HMENU;
  const AVerb: string): UINT;
var
  I, Count: Integer;
  Id: UINT;
  Name: string;
  WideBuf: array[0..127] of WideChar;
  AnsiBuf: array[0..127] of AnsiChar;
begin
  Result := 0;
  if (AMenu = nil) or (APop = 0) or (AVerb = '') then
    Exit;
  Count := GetMenuItemCount(APop);
  for I := 0 to Count - 1 do
  begin
    Id := GetMenuItemID(APop, I);
    if (Id = 0) or (Id = High(UINT)) then
      Continue;
    Name := '';
    FillChar(WideBuf, SizeOf(WideBuf), 0);
    if Succeeded(AMenu.GetCommandString(Id - 1, GCS_VERBW, nil,
         PAnsiChar(@WideBuf[0]), Length(WideBuf))) then
      Name := WideBuf;
    if Name = '' then
    begin
      FillChar(AnsiBuf, SizeOf(AnsiBuf), 0);
      if Succeeded(AMenu.GetCommandString(Id - 1, GCS_VERBA, nil,
           @AnsiBuf[0], Length(AnsiBuf))) then
        Name := string(AnsiBuf);
    end;
    if SameText(Name, AVerb) then
      Exit(Id);
  end;
end;

function InvokeUndeleteMenu(const AMenu: IContextMenu; out ACancelled: Boolean): Boolean;
const
  MenuFlags = CMF_NORMAL or CMF_EXPLORE or CMF_ITEMMENU;
var
  Pop: HMENU;
  ICI: TCMInvokeCommandInfoEx;
  Hr: HRESULT;
  Id: UINT;
begin
  Result := False;
  ACancelled := False;
  if AMenu = nil then
    Exit;
  Pop := CreatePopupMenu;
  if Pop = 0 then
    Exit;
  { Меню собирается до InvokeCommand. Строковый undelete без пункта в меню
    возвращает S_OK и ничего не делает, поэтому зовём только найденный id. }
  try
    Hr := AMenu.QueryContextMenu(Pop, 0, 1, $7FFF, MenuFlags);
    if Failed(Hr) then
      Exit;
    Id := MenuVerbId(AMenu, Pop, 'undelete');
    if Id = 0 then
      Exit;
    FillChar(ICI, SizeOf(ICI), 0);
    ICI.cbSize := SizeOf(ICI);
    ICI.fMask := CMIC_MASK_UNICODE;
    ICI.hwnd := DeleteOpOwnerWnd;
    ICI.nShow := SW_SHOWNORMAL;
    ICI.lpVerb := MakeIntResourceA(Id - 1);
    ICI.lpVerbW := MakeIntResource(Id - 1);
    Hr := AMenu.InvokeCommand(PCMInvokeCommandInfo(@ICI)^);
    if HrIsUserCancel(Hr) then
    begin
      ACancelled := True;
      Exit;
    end;
    Result := Succeeded(Hr);
  finally
    DestroyMenu(Pop);
  end;
end;

function InvokeUndelete(const AFolder: IShellFolder; const ARel: TArray<PItemIDList>;
  out ACancelled: Boolean): Boolean;
var
  Menu: IContextMenu;
begin
  Result := False;
  ACancelled := False;
  Menu := nil;
  if (AFolder = nil) or (Length(ARel) = 0) or (ARel[0] = nil) then
    Exit;
  if Failed(AFolder.GetUIObjectOf(DeleteOpOwnerWnd, Length(ARel), ARel[0],
       IID_IContextMenu, nil, Menu)) or (Menu = nil) then
    Exit;
  Result := InvokeUndeleteMenu(Menu, ACancelled);
end;

function InvokeUndeleteItem(const AItem: IShellItem; out ACancelled: Boolean): Boolean;
var
  Menu: IContextMenu;
begin
  Result := False;
  ACancelled := False;
  Menu := nil;
  if AItem = nil then
    Exit;
  if Failed(AItem.BindToHandler(nil, BHID_SFUIObject, IID_IContextMenu, Menu)) or
     (Menu = nil) then
    Exit;
  Result := InvokeUndeleteMenu(Menu, ACancelled);
end;

function HitStillThere(const AHit: TBinHit): Boolean;
begin
  Result := AHit.Listed;
end;

function ListedCount(const AHits: TArray<TBinHit>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AHits) do
    if AHits[I].Listed then
      Inc(Result);
end;

procedure MarkBinListed(const AFolder: IShellFolder; AParent: PItemIDList;
  var AHits: TArray<TBinHit>);
var
  Want: TDictionary<string, Integer>;
  Seen: TDictionary<Integer, Byte>;
  Enum: IEnumIDList;
  Child: PItemIDList;
  Fetched: ULONG;
  ChildItem: IShellItem;
  P: PWideChar;
  S, Key: string;
  I, Idx: Integer;

  procedure Take(const AName: string);
  begin
    Key := NormBinPath(AName);
    if (Key = '') or not Want.TryGetValue(Key, Idx) or Seen.ContainsKey(Idx) then
      Exit;
    Seen.Add(Idx, 0);
    AHits[Idx].Listed := True;
    if AHits[Idx].Rel <> nil then
      ILFree(AHits[Idx].Rel);
    AHits[Idx].Rel := ILClone(Child);
    AHits[Idx].Item := ChildItem;
  end;

begin
  for I := 0 to High(AHits) do
    AHits[I].Listed := False;
  if (AFolder = nil) or (Length(AHits) = 0) then
    Exit;
  Want := TDictionary<string, Integer>.Create;
  Seen := TDictionary<Integer, Byte>.Create;
  try
    for I := 0 to High(AHits) do
    begin
      Key := NormBinPath(AHits[I].Parse);
      if Key <> '' then
        Want.AddOrSetValue(Key, I);
      Key := NormBinPath(AHits[I].Body);
      if Key <> '' then
        Want.AddOrSetValue(Key, I);
    end;
    if Want.Count = 0 then
      Exit;
    if Failed(AFolder.EnumObjects(0, SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or
       SHCONTF_INCLUDEHIDDEN or SHCONTF_STORAGE, Enum)) or (Enum = nil) then
    begin
      for I := 0 to High(AHits) do
        AHits[I].Listed := True;
      Exit;
    end;
    Fetched := 0;
    while Enum.Next(1, Child, Fetched) = S_OK do
    try
      ChildItem := nil;
      if Failed(SHCreateItemWithParent(AParent, AFolder, Child, IID_IShellItem,
         ChildItem)) or (ChildItem = nil) then
        Continue;
      P := nil;
      S := '';
      if Succeeded(ChildItem.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, P)) and
         (P <> nil) then
      begin
        S := string(P);
        CoTaskMemFree(P);
      end;
      Take(S);
      P := nil;
      if Succeeded(ChildItem.GetDisplayName(SIGDN_FILESYSPATH, P)) and (P <> nil) then
      begin
        S := string(P);
        CoTaskMemFree(P);
        Take(S);
      end;
    finally
      CoTaskMemFree(Child);
    end;
  finally
    Want.Free;
    Seen.Free;
  end;
end;

procedure WaitBinListed(const AFolder: IShellFolder; AParent: PItemIDList;
  var AHits: TArray<TBinHit>; ATries: Integer);
var
  N: Integer;
begin
  if ATries < 1 then
    ATries := 1;
  for N := 1 to ATries do
  begin
    MarkBinListed(AFolder, AParent, AHits);
    if ListedCount(AHits) = 0 then
      Exit;
    if N < ATries then
      Sleep(80);
  end;
end;

function SiblingInfoPath(const ABody: string): string;
var
  Leaf: string;
begin
  Result := '';
  if not RecycleFsBody(ABody) then
    Exit;
  Leaf := ExtractFileName(ABody);
  if (Length(Leaf) < 3) or (Leaf[1] <> '$') or (UpCase(Leaf[2]) <> 'R') then
    Exit;
  Leaf[2] := 'I';
  Result := ExtractFileDir(ABody) + '\' + Leaf;
end;

procedure DropRestoredGhost(const AHit: TBinHit);
var
  Info, Orig: string;
begin
  if not AHit.Listed then
    Exit;
  { Тело $R уже ушло, файл на месте, а оболочка ещё показывает элемент.
    Это осиротевший $I: без него Корзина прячет запись. }
  if (AHit.Body = '') or RecycleBodyPresent(AHit.Body) then
    Exit;
  Orig := AHit.Orig;
  if (Orig = '') or not (TFile.Exists(Orig) or TDirectory.Exists(Orig)) then
    Exit;
  Info := SiblingInfoPath(AHit.Body);
  if (Info = '') or not RecycleBodyPresent(Info) then
    Exit;
  SetFileAttributes(PChar(Info), FILE_ATTRIBUTE_NORMAL);
  System.SysUtils.DeleteFile(Info);
end;

function EnsureRestoreFolder(const AFolder: string): Boolean;
begin
  Result := (AFolder <> '') and TDirectory.Exists(AFolder);
  if Result then
    Exit;
  if not IsWin32FsPath(AFolder) and not IsUncPath(AFolder) then
    Exit;
  try
    TDirectory.CreateDirectory(AFolder);
  except
    Exit;
  end;
  Result := TDirectory.Exists(AFolder);
end;

procedure PrepareRestoreFolders(const AHits: TArray<TBinHit>);
var
  I: Integer;
  Folder: string;
begin
  for I := 0 to High(AHits) do
  begin
    Folder := '';
    if AHits[I].Orig <> '' then
      Folder := ExtractFileDir(ExcludeTrailingPathDelimiter(AHits[I].Orig));
    if Folder = '' then
      Folder := ExcludeTrailingPathDelimiter(Trim(AHits[I].From));
    if Folder <> '' then
      EnsureRestoreFolder(Folder);
  end;
end;

function MoveHitsBack(const AHits: TArray<TBinHit>; const AIndex: TArray<Integer>;
  out ACancelled: Boolean): Boolean;
var
  HrInit, Hr: HRESULT;
  NeedUninit: Boolean;
  Op: IFileOperation;
  Dest: IShellItem;
  Folder, Leaf: string;
  Added, I, K: Integer;
  Aborted: BOOL;
begin
  Result := False;
  ACancelled := False;
  if Length(AIndex) = 0 then
    Exit;
  HrInit := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  NeedUninit := HrInit = S_OK;
  Op := nil;
  try
    if Failed(CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_ALL,
        IFileOperation, Op)) or (Op = nil) then
      Exit;
    Op.SetOperationFlags(DWORD(FOF_NOCONFIRMATION) or DWORD(FOF_RENAMEONCOLLISION) or
      DWORD(FOF_NOCONFIRMMKDIR) or DWORD(FOFX_SHOWELEVATIONPROMPT));
    if DeleteOpOwnerWnd <> 0 then
      Op.SetOwnerWindow(DeleteOpOwnerWnd);
    Added := 0;
    for K := 0 to High(AIndex) do
    begin
      I := AIndex[K];
      if (I < 0) or (I > High(AHits)) or (AHits[I].Item = nil) then
        Continue;
      if not HitStillThere(AHits[I]) then
        Continue;
      Folder := '';
      Leaf := '';
      if AHits[I].Orig <> '' then
      begin
        Folder := ExtractFileDir(ExcludeTrailingPathDelimiter(AHits[I].Orig));
        Leaf := ExtractFileName(ExcludeTrailingPathDelimiter(AHits[I].Orig));
      end;
      if (Folder = '') or (Leaf = '') then
      begin
        Folder := ExcludeTrailingPathDelimiter(Trim(AHits[I].From));
        Leaf := ExtractFileName(Trim(AHits[I].Leaf));
      end;
      if (Folder = '') or (Leaf = '') then
        Continue;
      if not EnsureRestoreFolder(Folder) then
        Continue;
      Dest := nil;
      if Failed(SHCreateItemFromParsingName(PChar(Folder), nil, IID_IShellItem, Dest)) or
         (Dest = nil) then
        Continue;
      if Succeeded(Op.MoveItem(AHits[I].Item, Dest, PChar(Leaf), nil)) then
        Inc(Added);
    end;
    if Added = 0 then
      Exit;
    Hr := Op.PerformOperations;
    Aborted := False;
    Op.GetAnyOperationsAborted(Aborted);
    if Aborted or HrIsUserCancel(Hr) then
    begin
      ACancelled := True;
      Exit;
    end;
    Result := Succeeded(Hr);
  finally
    Op := nil;
    if NeedUninit then
      CoUninitialize;
  end;
end;

function RestoreBinPaths(const APaths: TArray<string>; out AError: string): Boolean;
var
  Bin: IShellItem;
  Folder: IShellFolder;
  Parent: PItemIDList;
  Hits: TArray<TBinHit>;
  Rel: TArray<PItemIDList>;
  Left: TArray<Integer>;
  One: TArray<PItemIDList>;
  Cancelled: Boolean;
  Did: Boolean;
  I, N, LeftN: Integer;
begin
  AError := '';
  Result := False;
  Hits := nil;
  Parent := nil;
  Bin := nil;
  Folder := nil;
  if not OpenRecycleFolder(Bin, Folder, Parent) then
  begin
    AError := L('bin.fail');
    Exit;
  end;
  try
    if CollectBinHits(APaths, Folder, Parent, Hits) = 0 then
    begin
      AError := L('bin.fail');
      Exit;
    end;
    PrepareRestoreFolders(Hits);
    SetLength(Rel, Length(Hits));
    N := 0;
    for I := 0 to High(Hits) do
      if Hits[I].Rel <> nil then
      begin
        Rel[N] := Hits[I].Rel;
        Inc(N);
      end;
    SetLength(Rel, N);
    Cancelled := False;
    if N > 0 then
      InvokeUndelete(Folder, Rel, Cancelled);
    if Cancelled then
    begin
      AError := L('op.cancelled');
      Exit;
    end;
    { Успех — элемент исчез из оболочки, а не пропал файл по чужому пути. }
    WaitBinListed(Folder, Parent, Hits, 6);
    if ListedCount(Hits) > 0 then
    begin
      SetLength(One, 1);
      for I := 0 to High(Hits) do
      begin
        if not Hits[I].Listed then
          Continue;
        Did := False;
        Cancelled := False;
        if Hits[I].Rel <> nil then
        begin
          One[0] := Hits[I].Rel;
          Did := InvokeUndelete(Folder, One, Cancelled);
        end;
        if Cancelled then
        begin
          AError := L('op.cancelled');
          Exit;
        end;
        if not Did then
          InvokeUndeleteItem(Hits[I].Item, Cancelled);
        if Cancelled then
        begin
          AError := L('op.cancelled');
          Exit;
        end;
      end;
      WaitBinListed(Folder, Parent, Hits, 4);
    end;
    LeftN := 0;
    SetLength(Left, Length(Hits));
    for I := 0 to High(Hits) do
      if Hits[I].Listed then
      begin
        Left[LeftN] := I;
        Inc(LeftN);
      end;
    SetLength(Left, LeftN);
    if LeftN > 0 then
    begin
      MoveHitsBack(Hits, Left, Cancelled);
      if Cancelled then
      begin
        AError := L('op.cancelled');
        Exit;
      end;
      WaitBinListed(Folder, Parent, Hits, 4);
    end;
    for I := 0 to High(Hits) do
      DropRestoredGhost(Hits[I]);
    NotifyRecycleBinChanged;
    WaitBinListed(Folder, Parent, Hits, 3);
    if ListedCount(Hits) = 0 then
      Result := True
    else
      AError := L('bin.fail');
  finally
    FreeBinHits(Hits);
    if Parent <> nil then
      CoTaskMemFree(Parent);
    Folder := nil;
    Bin := nil;
  end;
end;
{$ENDIF}

function QueryRecycleBin(out AItems, ABytes: Int64): Boolean;
{$IFDEF MSWINDOWS}
var
  Info: TSHQueryRBInfo;
{$ENDIF}
begin
  AItems := 0;
  ABytes := 0;
  Result := False;
  {$IFDEF MSWINDOWS}
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if Failed(SHQueryRecycleBinW(nil, Info)) then
    Exit;
  AItems := Info.i64NumItems;
  ABytes := Info.i64Size;
  Result := True;
  {$ENDIF}
end;

function RestoreRecycleItems(const APaths: TArray<string>; out AError: string): Boolean;
begin
  AError := '';
  Result := False;
  if Length(APaths) = 0 then
  begin
    AError := L('bin.norestore');
    Exit;
  end;
  {$IFDEF MSWINDOWS}
  Result := RestoreBinPaths(APaths, AError);
  {$ELSE}
  AError := L('bin.fail');
  {$ENDIF}
end;

function EmptyRecycleBin(out AError: string): Boolean;
begin
  AError := '';
  Result := False;
  {$IFDEF MSWINDOWS}
  if Succeeded(SHEmptyRecycleBinW(0, nil, 1)) then
  begin
    ClearRecycleUndo;
    NotifyRecycleBinChanged;
    Exit(True);
  end;
  AError := L('bin.fail');
  {$ELSE}
  AError := L('bin.fail');
  {$ENDIF}
end;

procedure ClearRecycleUndo;
begin
  if GUndoLock = nil then
    Exit;
  GUndoLock.Enter;
  try
    if GUndo <> nil then
      GUndo.Clear;
  finally
    GUndoLock.Leave;
  end;
end;

procedure PushUndoBatch(const ABatch: TUndoDelete);
const
  MaxUndo = 16;
begin
  if (Length(ABatch.Sources) = 0) or (GUndoLock = nil) then
    Exit;
  GUndoLock.Enter;
  try
    if GUndo = nil then
      GUndo := TList<TUndoDelete>.Create;
    GUndo.Add(ABatch);
    while GUndo.Count > MaxUndo do
      GUndo.Delete(0);
  finally
    GUndoLock.Leave;
  end;
end;

procedure PushRecycleUndo(const AItems: TArray<string>);
var
  Batch: TUndoDelete;
  Mark: TFileTime;
begin
  if Length(AItems) = 0 then
    Exit;
  FillChar(Mark, SizeOf(Mark), 0);
  GetSystemTimeAsFileTime(Mark);
  Batch.Sources := Copy(AItems);
  Batch.Mark := Int64(Mark.dwLowDateTime) or (Int64(Mark.dwHighDateTime) shl 32);
  PushUndoBatch(Batch);
end;

function PopRecycleUndo: TUndoDelete;
begin
  Result.Sources := nil;
  Result.Mark := 0;
  if GUndoLock = nil then
    Exit;
  GUndoLock.Enter;
  try
    if (GUndo = nil) or (GUndo.Count = 0) then
      Exit;
    Result := GUndo[GUndo.Count - 1];
    GUndo.Delete(GUndo.Count - 1);
  finally
    GUndoLock.Leave;
  end;
end;

function CollectRecycleUndo(const ABatch: TUndoDelete): TArray<string>;
{$IFDEF MSWINDOWS}
const
  KeyFrom: TPropertyKey = (
    fmtid: '{9B174B33-40FF-11D2-A27E-00C04FC30871}'; pid: 2);
  KeyWhen: TPropertyKey = (
    fmtid: '{9B174B33-40FF-11D2-A27E-00C04FC30871}'; pid: 3);
  Tick3Min = Int64(180) * 10000000;
var
  WantPath, WantName: TDictionary<string, Byte>;
  Hits: TList<string>;
  Bin: IShellItem;
  Folder: IShellFolder;
  Enum: IEnumIDList;
  Child: PItemIDList;
  Fetched: ULONG;
  ChildItem: IShellItem;
  ParentPidl: PItemIDList;
  Origin, Parse, Name, Disp, S: string;
  Came, Joined, FromKey: string;
  Item2: IShellItem2;
  P: PWideChar;
  FT: TFileTime;
  Stamp: Int64;
  Exact: Boolean;
  I: Integer;
{$ENDIF}
begin
  SetLength(Result, 0);
  {$IFDEF MSWINDOWS}
  if Length(ABatch.Sources) = 0 then
    Exit;
  WantPath := TDictionary<string, Byte>.Create;
  WantName := TDictionary<string, Byte>.Create;
  Hits := TList<string>.Create;
  ParentPidl := nil;
  try
    for S in ABatch.Sources do
    begin
      Origin := NormBinPath(S);
      if Origin = '' then
        Continue;
      WantPath.AddOrSetValue(Origin, 0);
      Name := ExtractFileName(Origin);
      if Name <> '' then
        WantName.AddOrSetValue(Name, 0);
    end;
    if (WantPath.Count = 0) or not ShellItemFromPath(RecycleBinPath, Bin) then
      Exit;
    if Failed(Bin.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, Folder)) or
       (Folder = nil) then
      Exit;
    SHGetIDListFromObject(Bin, ParentPidl);
    if Failed(Folder.EnumObjects(0, SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or
       SHCONTF_INCLUDEHIDDEN or SHCONTF_STORAGE, Enum)) or (Enum = nil) then
      Exit;
    Fetched := 0;
    while Enum.Next(1, Child, Fetched) = S_OK do
    try
      ChildItem := nil;
      if Failed(SHCreateItemWithParent(ParentPidl, Folder, Child, IID_IShellItem,
         ChildItem)) or (ChildItem = nil) then
        Continue;
      Origin := '';
      Disp := '';
      Name := '';
      Stamp := 0;
      Item2 := nil;
      if Supports(ChildItem, IShellItem2, Item2) then
      begin
        P := nil;
        if Succeeded(Item2.GetString(KeyFrom, P)) and (P <> nil) then
        begin
          Origin := string(P);
          CoTaskMemFree(P);
        end;
        FillChar(FT, SizeOf(FT), 0);
        if Succeeded(Item2.GetFileTime(KeyWhen, FT)) then
          Stamp := Int64(FT.dwLowDateTime) or (Int64(FT.dwHighDateTime) shl 32);
      end;
      P := nil;
      if Succeeded(ChildItem.GetDisplayName(SIGDN_NORMALDISPLAY, P)) and
         (P <> nil) then
      begin
        { У элемента Корзины это исходный полный путь, не только имя. }
        Disp := StringReplace(string(P), '/', '\', [rfReplaceAll]);
        CoTaskMemFree(P);
      end;
      Name := UpperCase(ExtractFileName(ExcludeTrailingPathDelimiter(Disp)));
      Came := NormBinPath(Disp);
      if (Disp <> '') and (Pos('\', Disp) = 0) and (Pos(':', Disp) = 0) and
         not StartsText('\\', Disp) then
        Came := NormBinPath(CombineBinPath(Origin, Disp));
      Joined := NormBinPath(CombineBinPath(Origin, Name));
      FromKey := NormBinPath(Origin);
      { FromKey — это папка «откуда удалили». Совпадает с пачкой, только если
        свойство уже хранит полный путь, а не родительский каталог. }
      Exact := ((Came <> '') and WantPath.ContainsKey(Came)) or
        ((Joined <> '') and WantPath.ContainsKey(Joined)) or
        ((FromKey <> '') and (Name <> '') and (ExtractFileName(FromKey) = Name) and
         WantPath.ContainsKey(FromKey));
      { Дата удаления обрезана до минуты. Окно в 30 с отсекало точное совпадение. }
      if not Exact then
      begin
        if (Name = '') or not WantName.ContainsKey(Name) or (Stamp = 0) or
           (Stamp + Tick3Min < ABatch.Mark) then
          Continue;
      end;
      P := nil;
      Parse := '';
      if Succeeded(ChildItem.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, P)) and
         (P <> nil) then
      begin
        Parse := string(P);
        CoTaskMemFree(P);
      end;
      if Parse <> '' then
        Hits.Add(Parse);
    finally
      CoTaskMemFree(Child);
    end;
    SetLength(Result, Hits.Count);
    for I := 0 to Hits.Count - 1 do
      Result[I] := Hits[I];
  finally
    if Assigned(ParentPidl) then
      CoTaskMemFree(ParentPidl);
    WantPath.Free;
    WantName.Free;
    Hits.Free;
  end;
  {$ENDIF}
end;

procedure RememberRecycleUndo(const ASources: TArray<string>);
begin
  PushRecycleUndo(ASources);
end;

function UndoLastDelete(out AError: string): Boolean;
var
  Batch: TUndoDelete;
  Found: TArray<string>;
  TryN: Integer;
begin
  AError := '';
  Batch := PopRecycleUndo;
  if Length(Batch.Sources) = 0 then
  begin
    AError := L('bin.noundo');
    Exit(False);
  end;
  SetLength(Found, 0);
  for TryN := 1 to 4 do
  begin
    Found := CollectRecycleUndo(Batch);
    if Length(Found) > 0 then
      Break;
    if TryN < 4 then
      Sleep(150);
  end;
  if Length(Found) = 0 then
  begin
    PushUndoBatch(Batch);
    AError := L('bin.fail');
    Exit(False);
  end;
  Result := RestoreRecycleItems(Found, AError);
  if not Result then
  begin
    PushUndoBatch(Batch);
    if AError = '' then
      AError := L('bin.fail');
  end;
end;

procedure NotifyRecycleBinChanged;
{$IFDEF MSWINDOWS}
var
  Bin: IShellItem;
  Pidl: PItemIDList;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  SHUpdateRecycleBinIcon;
  Bin := nil;
  Pidl := nil;
  if ShellItemFromPath(RecycleBinPath, Bin) and Assigned(Bin) and
     Succeeded(SHGetIDListFromObject(Bin, Pidl)) and (Pidl <> nil) then
  try
    SHChangeNotify(SHCNE_UPDATEDIR, SHCNF_IDLIST or SHCNF_FLUSHNOWAIT, Pidl, nil);
  finally
    CoTaskMemFree(Pidl);
  end;
  {$ENDIF}
end;

initialization
  GUndoLock := TCriticalSection.Create;

finalization
  GVibeLaunch := nil;
  GVibeRestore := nil;
  GFileOpHubChanged := nil;
  FreeAndNil(GUndo);
  FreeAndNil(GUndoLock);

end.
