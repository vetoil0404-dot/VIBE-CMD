unit uFileOps;

{
  Базовые файловые операции: копирование, перемещение, удаление,
  создание папки. Выполняются в фоновом потоке, чтобы не блокировать UI.
  V!be: engine + окно прогресса (конфликты там).
  Тихий: без progress/Shell-диалогов; конфликты имён — uConflictDialog.
  Проводник: диалог Windows из своего STA-потока, без привязки к нашему окну.
  Тихий и Проводник показывают процесс на пилюле средней панели.
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
  uFileOpEngine, uArchiveEngine, uConflictDialog, uLang, uNetworkVfs
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

procedure DrainQuietFileOps; forward;

procedure CancelListFileOps;
begin
  GListOpClosing := True;
  GListOpCancel := True;
  DrainQuietFileOps;
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
        raise Exception.Create(L('ops.recycle'));
    end;
    Exit;
  end;
  if not APermanent then
  begin
    if not ShellDeletePath(APath, False) then
      raise Exception.Create(L('ops.recycle'));
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
  ParentDir, Z, Inner, Temp, Err: string;
  IsDir: Boolean;

  procedure MoveEntry(const AFrom, ATo: string);
  begin
    if IsDir then
      TDirectory.Move(AFrom, ATo)
    else
      TFile.Move(AFrom, ATo);
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
  IsDir := TDirectory.Exists(AOldPath);
  { NTFS не меняет регистр прямым Move: имя для системы то же. }
  if SameText(AOldPath, ANewPath) then
  begin
    Temp := CaseTempPath(ParentDir,
      ExtractFileName(ExcludeTrailingPathDelimiter(AOldPath)));
    if Temp = '' then
      Exit;
    try
      MoveEntry(AOldPath, Temp);
    except
      Exit;
    end;
    try
      MoveEntry(Temp, ANewPath);
      Result := True;
    except
      on E: Exception do
      begin
        Err := E.Message;
        try
          MoveEntry(Temp, AOldPath);
          Result := False;
        except
          on E2: Exception do
            raise Exception.Create(Err + sLineBreak + E2.Message);
        end;
      end;
    end;
    Exit;
  end;
  try
    MoveEntry(AOldPath, ANewPath);
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
      raise Exception.Create(Lf('ops.readfail', [SrcName]));
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

type
  TListOpJob = class
    Sources: TArray<string>;
    DestDir: string;
    Move: Boolean;
    OnDone: TFileOpDoneProc;
    OnItem: TFileOpItemDoneProc;
    TrackId: Integer;
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

var
  GQuietWait: TList<TListOpJob>;

procedure DrainQuietFileOps;
var
  Job: TListOpJob;
begin
  if GQuietWait = nil then
    Exit;
  while GQuietWait.Count > 0 do
  begin
    Job := GQuietWait[0];
    GQuietWait.Delete(0);
    Job.Free;
  end;
end;

procedure PumpQuietQueue; forward;

function TListOpJob.Cancelled: Boolean;
begin
  Result := GListOpCancel or Application.Terminated or
    FileOpTrackCancelled(TrackId);
end;

procedure TListOpJob.Notify(const APath: string; AStatus: TOpItemStatus);
var
  P: string;
  S: TOpItemStatus;
  Cb: TFileOpItemDoneProc;
begin
  if (AStatus in [oisError, oisSkipped]) and (APath <> '') then
    ProbeLivePath(APath);
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
    Errors.Add(Lf('ops.gone', [TPath.GetFileName(ASrc)]));
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
      Errors.Add(Lf('ops.typemismatch', [TPath.GetFileName(ASrc)]));
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
      if Move then
        EmitLiveOp(lokMove, ASrc, Dest, True, 0, 0)
      else
        EmitLiveOp(lokCopy, ASrc, Dest, True, 0, 0);
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
      if Move then
        EmitLiveOp(lokMove, ASrc, Dest, False, -1, 0)
      else
        EmitLiveOp(lokCopy, ASrc, Dest, False, -1, 0);
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
    Errors.Add(Lf('ops.typemismatch', [TPath.GetFileName(ASrc)]));
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
    Errors.Add(Lf('ops.gone', [TPath.GetFileName(AIt.SourcePath)]));
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
      Errors.Add(Lf('ops.noname', [TPath.GetFileName(AIt.SourcePath)]));
      Notify(AIt.SourcePath, oisError);
      Exit(oisError);
    end;
{$IFDEF MSWINDOWS}
    if (Length(Dest) > MAX_PATH) and not StartsText('\\?\', Dest) then
    begin
      Errors.Add(Lf('ops.longname', [TPath.GetFileName(AIt.SourcePath)]));
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
    if Move then
      EmitLiveOp(lokMove, AIt.SourcePath, Dest, False, AIt.SourceSize, AIt.SourceTime)
    else
      EmitLiveOp(lokCopy, AIt.SourcePath, Dest, False, AIt.SourceSize, AIt.SourceTime);
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
  EndId: Integer;
begin
  Fine := True;
  Err := '';
  DoneCb := OnDone;
  EndId := TrackId;
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
        Err := L('op.cancelled');
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
        FileOpTrackEnd(EndId);
        GListOpBusy := False;
        if Assigned(DoneCb) then
          DoneCb(Fine, Err);
        PumpQuietQueue;
      end);
  end;
end;

procedure StartQuietJob(Job: TListOpJob); forward;

procedure StartQuietJob(Job: TListOpJob);
begin
  if GListOpClosing or Application.Terminated then
  begin
    Job.Free;
    Exit;
  end;
  GListOpBusy := True;
  GListOpCancel := False;
  FileOpTrackRunning(Job.TrackId);
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

procedure PumpQuietQueue;
var
  Job: TListOpJob;
begin
  if GListOpBusy or (GQuietWait = nil) or (GQuietWait.Count = 0) then
    Exit;
  Job := GQuietWait[0];
  GQuietWait.Delete(0);
  StartQuietJob(Job);
end;

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

procedure RunQuietCopyMove(const ASources: TArray<string>; const ADestDir: string;
  AMove: Boolean; AOnDone: TFileOpDoneProc; AOnItemDone: TFileOpItemDoneProc);
var
  Job: TListOpJob;
  Kind: TFileOpKind;
begin
  if Length(ASources) = 0 then
  begin
    if Assigned(AOnDone) then
      AOnDone(True, '');
    Exit;
  end;
  if AMove then
    Kind := okMove
  else
    Kind := okCopy;
  Job := TListOpJob.Create;
  Job.Sources := Copy(ASources);
  Job.DestDir := ADestDir;
  Job.Move := AMove;
  Job.OnDone := AOnDone;
  Job.OnItem := AOnItemDone;
  Job.TrackId := StartOpTrack(Kind, Job.Sources, ADestDir, GListOpBusy);
  if GListOpBusy then
  begin
    if GQuietWait = nil then
      GQuietWait := TList<TListOpJob>.Create;
    GQuietWait.Add(Job);
    Exit;
  end;
  StartQuietJob(Job);
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
  { V!be — свой движок и прогресс (конфликты в progress-форме). }
  if GFileOpMode = fomVibe then
  begin
    LaunchVibe(okCopy, Snapshot, Dest, AOnDone, False, AOnItemDone);
    Exit;
  end;
  { Тихий — без progress и без Shell UI; конфликты имён через uConflictDialog. }
  if GFileOpMode = fomQuiet then
  begin
    RunQuietCopyMove(Snapshot, Dest, False, AOnDone, AOnItemDone);
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
  if GFileOpMode = fomVibe then
  begin
    LaunchVibe(okMove, Snapshot, Dest, AOnDone, False, AOnItemDone);
    Exit;
  end;
  if GFileOpMode = fomQuiet then
  begin
    RunQuietCopyMove(Snapshot, Dest, True, AOnDone, AOnItemDone);
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
  if GFileOpMode = fomVibe then
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

function RestoreOneItem(const APath: string): Boolean;
var
  Item: IShellItem;
  Menu: IContextMenu;
  ICI: TCMInvokeCommandInfo;
begin
  Result := False;
  if not ShellItemFromPath(APath, Item) then
    Exit;
  if Failed(Item.BindToHandler(nil, BHID_SFUIObject, IID_IContextMenu, Menu)) or
     (Menu = nil) then
    Exit;
  FillChar(ICI, SizeOf(ICI), 0);
  ICI.cbSize := SizeOf(ICI);
  ICI.fMask := 0;
  ICI.lpVerb := PAnsiChar(AnsiString('undelete'));
  ICI.nShow := SW_SHOWNORMAL;
  Result := Succeeded(Menu.InvokeCommand(ICI));
end;

function RestoreBatch(const APaths: TArray<string>): Boolean;
var
  Bin: IShellItem;
  Folder: IShellFolder;
  Item: IShellItem;
  AbsPidl, RelPidl: PItemIDList;
  Rel: TArray<PItemIDList>;
  Menu: IContextMenu;
  ICI: TCMInvokeCommandInfo;
  I, N: Integer;
begin
  Result := False;
  if not ShellItemFromPath(RecycleBinPath, Bin) then
    Exit;
  if Failed(Bin.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, Folder)) or
     (Folder = nil) then
    Exit;
  SetLength(Rel, Length(APaths));
  N := 0;
  for I := 0 to High(APaths) do
  begin
    AbsPidl := nil;
    Item := nil;
    if not ShellItemFromPath(APaths[I], Item) then
      Continue;
    if Failed(SHGetIDListFromObject(Item, AbsPidl)) or (AbsPidl = nil) then
      Continue;
    RelPidl := ILClone(ILFindLastID(AbsPidl));
    CoTaskMemFree(AbsPidl);
    if RelPidl = nil then
      Continue;
    Rel[N] := RelPidl;
    Inc(N);
  end;
  if N = 0 then
    Exit;
  try
    if Failed(Folder.GetUIObjectOf(0, N, Rel[0], IID_IContextMenu, nil, Menu)) or
       (Menu = nil) then
      Exit;
    FillChar(ICI, SizeOf(ICI), 0);
    ICI.cbSize := SizeOf(ICI);
    ICI.lpVerb := PAnsiChar(AnsiString('undelete'));
    ICI.nShow := SW_SHOWNORMAL;
    Result := Succeeded(Menu.InvokeCommand(ICI));
  finally
    for I := 0 to N - 1 do
      ILFree(Rel[I]);
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
var
  I: Integer;
  Any: Boolean;
begin
  AError := '';
  Result := False;
  if Length(APaths) = 0 then
  begin
    AError := L('bin.norestore');
    Exit;
  end;
  {$IFDEF MSWINDOWS}
  if RestoreBatch(APaths) then
    Exit(True);
  Any := False;
  for I := 0 to High(APaths) do
    if RestoreOneItem(APaths[I]) then
      Any := True;
  Result := Any;
  if not Result then
    AError := L('bin.fail');
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

procedure PushRecycleUndo(const AItems: TArray<string>);
const
  MaxUndo = 16;
var
  Batch: TUndoDelete;
  Mark: TFileTime;
begin
  if (Length(AItems) = 0) or (GUndoLock = nil) then
    Exit;
  FillChar(Mark, SizeOf(Mark), 0);
  GetSystemTimeAsFileTime(Mark);
  Batch.Sources := Copy(AItems);
  Batch.Mark := Int64(Mark.dwLowDateTime) or (Int64(Mark.dwHighDateTime) shl 32);
  GUndoLock.Enter;
  try
    if GUndo = nil then
      GUndo := TList<TUndoDelete>.Create;
    GUndo.Add(Batch);
    while GUndo.Count > MaxUndo do
      GUndo.Delete(0);
  finally
    GUndoLock.Leave;
  end;
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
  Tick30s = Int64(30) * 10000000;
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
  Origin, Parse, Name, S: string;
  Item2: IShellItem2;
  P: PWideChar;
  FT: TFileTime;
  Stamp, Floor: Int64;
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
      Origin := UpperCase(ExcludeTrailingPathDelimiter(Trim(S)));
      if Origin = '' then
        Continue;
      WantPath.AddOrSetValue(Origin, 0);
      Name := UpperCase(ExtractFileName(Origin));
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
    Floor := ABatch.Mark - Tick30s;
    Fetched := 0;
    while Enum.Next(1, Child, Fetched) = S_OK do
    try
      ChildItem := nil;
      if Failed(SHCreateItemWithParent(ParentPidl, Folder, Child, IID_IShellItem,
         ChildItem)) or (ChildItem = nil) then
        Continue;
      Origin := '';
      Name := '';
      Stamp := 0;
      Item2 := nil;
      if Supports(ChildItem, IShellItem2, Item2) then
      begin
        P := nil;
        if Succeeded(Item2.GetString(KeyFrom, P)) and (P <> nil) then
        begin
          Origin := UpperCase(ExcludeTrailingPathDelimiter(Trim(string(P))));
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
        Name := UpperCase(ExtractFileName(StringReplace(string(P), '/', '\',
          [rfReplaceAll])));
        CoTaskMemFree(P);
      end;
      if (Stamp <> 0) and (Stamp < Floor) then
        Continue;
      if (Origin = '') or not WantPath.ContainsKey(Origin) then
      begin
        if (Name = '') or not WantName.ContainsKey(Name) or (Stamp = 0) then
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
    if GUndoLock <> nil then
    begin
      GUndoLock.Enter;
      try
        if GUndo = nil then
          GUndo := TList<TUndoDelete>.Create;
        GUndo.Add(Batch);
      finally
        GUndoLock.Leave;
      end;
    end;
    AError := L('bin.fail');
    Exit(False);
  end;
  Result := RestoreRecycleItems(Found, AError);
  if not Result and (AError = '') then
    AError := L('bin.fail');
end;

procedure NotifyRecycleBinChanged;
begin
  {$IFDEF MSWINDOWS}
  SHUpdateRecycleBinIcon;
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
  if GQuietWait <> nil then
  begin
    while GQuietWait.Count > 0 do
    begin
      GQuietWait[0].Free;
      GQuietWait.Delete(0);
    end;
    FreeAndNil(GQuietWait);
  end;

end.
