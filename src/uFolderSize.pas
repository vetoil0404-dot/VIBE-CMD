unit uFolderSize;

{
  Фоновый логический размер каталога для колонки панели и для C3.
  Сумма длин файлов, без Size on disk. Каталоги в сумму не входят.
  Симлинк и junction не разворачиваются: обход в них не заходит, цикла нет.
  Таймаут и отмена наружу числом не отдаются. Непрочитанный вложенный каталог
  пропускается, как в предварительном подсчёте файловой операции: сумма остальных
  файлов — готовый размер.
  Обходов одновременно не больше четырёх. Повтор того же ключа второй обход не ставит.
  Готовое число остаётся на экране, пока идёт повтор: ячейка не возвращается к «…».
  UNC и сетевой диск сами не считаются: автопоказ для IsRemotePath job не ставит.
  Ручной запрос одной папки (Alt+Enter) сеть не запрещает и показ размеров не требует.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs;

const
  FolderSizePendingMark = #$2026;
  FolderSizePartialMark = #$2014;
  FolderSizeDeniedMark = '<DIR>';

type
  { fssReady — «готово». Ноль байт законен только в этом статусе.
    fssError — «ошибка». fssPartial — «частично» (таймаут или отказ глубже).
    fssNone / fssPending — числа нет. }
  TFolderSizeStatus = (fssNone, fssPending, fssReady, fssError, fssPartial);

  TFolderSizeCache = class
  private type
    TSizeRec = record
      Bytes: Int64;
      Status: TFolderSizeStatus;
      Stamp: TDateTime;
      Written: TDateTime;
      Recursive: Boolean;
      Dirty: Boolean;
      { Сумма осмысленна: готовый обход или ручной сетевой таймаут. }
      HasSum: Boolean;
    end;

    TSizeJob = class
    public
      Path: string;
      Key: string;
      Remote: Boolean;
      Epoch: Integer;
      Cancel: Integer;
      Restart: Boolean;
      { Ручной запрос одной папки. Автоочередь этот флаг не ставит. }
      Manual: Boolean;
      Stamp: TDateTime;
      Owners: TList<TObject>;
      constructor Create;
      destructor Destroy; override;
      function IsCancelled: Boolean;
      procedure MarkCancel;
      procedure AddOwner(AOwner: TObject);
      function HasOwner(AOwner: TObject): Boolean;
      procedure RemoveOwner(AOwner: TObject);
    end;

    TSizeWatchThread = class(TThread)
    private
      FCache: TFolderSizeCache;
      FPath: string;
      FKey: string;
      FStop: TEvent;
      FChange: TEvent;
      FDetached: Integer;
      procedure HandOff(const ARels: TArray<string>; AOverflow: Boolean);
    protected
      procedure Execute; override;
    public
      constructor Create(ACache: TFolderSizeCache; const APath, AKey: string);
      destructor Destroy; override;
      procedure ShutdownAndFree;
    end;
  private
    FLock: TCriticalSection;
    FItems: TDictionary<string, TSizeRec>;
    FJobs: TDictionary<string, TSizeJob>;
    FQueue: TQueue<TSizeJob>;
    FEpoch: TDictionary<string, Integer>;
    FBusy: Integer;
    FAbandoned: Integer;
    FGeneration: Integer;
    FShuttingDown: Boolean;
    FOwnerRoot: TDictionary<TObject, string>;
    FWatchRefs: TDictionary<string, Integer>;
    FWatches: TDictionary<string, TSizeWatchThread>;
    FWakes: TDictionary<TObject, TProc>;
    FSortSnap: TDictionary<string, Int64>;
    { Ключ текущего ручного запроса. Одновременно один такой сетевой обход. }
    FManualKey: string;
    procedure Pump;
    procedure StartJob(AJob: TSizeJob);
    procedure FinishJob(AJob: TSizeJob; ABytes: Int64; AStatus: TFolderSizeStatus);
    function Measure(AJob: TSizeJob; out ABytes: Int64): TFolderSizeStatus;
    function Lookup(const AKey: string; AModified: TDateTime;
      out ARec: TSizeRec; out AStatus: TFolderSizeStatus): Boolean;
    { Вызывается только под FLock. Ставит повтор, не снимая уже посчитанное число. }
    function MarkDirty(const APath: string; ADescendants, AEnqueueSelf: Boolean): Boolean;
    procedure EnsureJob(AOwner: TObject; const APath, AKey: string; ARemote: Boolean);
    procedure CancelOtherManual(const AKeepKey: string);
    procedure ReleaseExceptUnder(AOwner: TObject; const ARoot: string);
    procedure WakeAll;
    procedure TrimCache;
  public
    constructor Create;
    destructor Destroy; override;
    function CellText(AOwner: TObject; const APath: string; AModified: TDateTime;
      ARemote: Boolean): string;
    { Одна папка под курсором. Сеть и выключенный показ размеров не мешают.
      Свежий fssReady берётся из кэша. Пока job этой папки идёт, второй не ставится.
      Другой незаконченный ручной сетевой обход отменяется. }
    function RequestOne(AOwner: TObject; const APath: string;
      AModified: TDateTime): TFolderSizeStatus;
    { Без постановки job. Для строки ручного запроса и строки статуса. }
    procedure Peek(const APath: string; AJobIsPending: Boolean;
      out AStatus: TFolderSizeStatus; out ABytes: Int64; out AHasSum: Boolean);
    procedure RequestFolders(AOwner: TObject; const APaths: TArray<string>;
      const AModified: TArray<TDateTime>);
    procedure Query(const APath: string; AModified: TDateTime;
      out ABytes: Int64; out AStatus: TFolderSizeStatus);
    function ReadyBytes(const APath: string; AModified: TDateTime;
      out ABytes: Int64): Boolean;
    procedure NotePanelRoot(AOwner: TObject; const APath: string);
    procedure InvalidateUnder(const APath: string);
    procedure ApplyWatch(const ARoot: string; const ARels: TArray<string>;
      AOverflow: Boolean);
    procedure Advise(AOwner: TObject; const AWake: TProc);
    procedure Unadvise(AOwner: TObject);
    function HasWork: Boolean;
    function Quiescent: Boolean;
    function Generation: Integer;
    procedure BeginSortSnapshot;
    procedure EndSortSnapshot;
    function SortSnapshotOn: Boolean;
    function SnapshotBytes(const APath: string; out ABytes: Int64): Boolean;
    procedure Shutdown;
  end;

var
  GlobalFolderSizes: TFolderSizeCache;

procedure QueryFolderSize(const APath: string; AModified: TDateTime;
  out ABytes: Int64; out AStatus: TFolderSizeStatus);
function FolderSizeReadyBytes(const APath: string; AModified: TDateTime;
  out ABytes: Int64): Boolean;
procedure SetFolderSizesShown(AOn: Boolean);
function FolderSizesShown: Boolean;
{ Обход и watch — только после первого кадра. До этого запросы копятся в панели. }
procedure AllowFolderSizeWalks;

implementation

uses
  System.IOUtils, uFileModel
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

type
  PFolderNotifyInfo = ^TFolderNotifyInfo;
  TFolderNotifyInfo = record
    NextEntryOffset: DWORD;
    Action: DWORD;
    FileNameLength: DWORD;
    FileName: array[0..0] of Char;
  end;

const
  MaxWorkers = 4;
  MaxCacheEntries = 4000;
  LocalTimeoutMs = 90000;
  RemoteTimeoutMs = 15000;
  { Ручной обход по сети короче автобюджета: панель не должна висеть. }
  ManualRemoteTimeoutMs = 8000;
  WatchCoalesceMs = 800;

var
  GFolderSizesShown: Boolean = True;
  GFolderSizesArmed: Boolean = False;

function NormFolderKey(const APath: string): string;
begin
  Result := LowerCase(ExcludeTrailingPathDelimiter(Trim(APath)));
end;

function UnderKey(const APath, ARoot: string): Boolean;
var
  P, R: string;
begin
  P := NormFolderKey(APath);
  R := NormFolderKey(ARoot);
  if (P = '') or (R = '') then
    Exit(False);
  Result := (P = R) or P.StartsWith(R + '\');
end;

function StampFresh(const ARecStamp, AEntryStamp: TDateTime): Boolean;
begin
  { Метку снять не удалось — держим запись до явной инвалидации. }
  if ARecStamp <= 0 then
    Exit(True);
  if AEntryStamp <= 0 then
    Exit(True);
  { Список — DOS-время с шагом 2 с, метка обхода точнее. Три секунды закрывают округление. }
  Result := ARecStamp + (3 / 86400) >= AEntryStamp;
end;

function DirStamp(const APath: string): TDateTime;
begin
  try
    Result := TDirectory.GetLastWriteTime(ExcludeTrailingPathDelimiter(APath));
  except
    Result := 0;
  end;
end;

function WatchableRoot(const APath: string): Boolean;
begin
  Result := (NormFolderKey(APath) <> '') and not IsDriveRoot(APath) and
    not IsRemotePath(APath);
end;

procedure QueryFolderSize(const APath: string; AModified: TDateTime;
  out ABytes: Int64; out AStatus: TFolderSizeStatus);
begin
  ABytes := 0;
  AStatus := fssNone;
  if Assigned(GlobalFolderSizes) then
    GlobalFolderSizes.Query(APath, AModified, ABytes, AStatus);
end;

function FolderSizeReadyBytes(const APath: string; AModified: TDateTime;
  out ABytes: Int64): Boolean;
begin
  ABytes := 0;
  Result := Assigned(GlobalFolderSizes) and
    GlobalFolderSizes.ReadyBytes(APath, AModified, ABytes);
end;

procedure SetFolderSizesShown(AOn: Boolean);
begin
  GFolderSizesShown := AOn;
end;

function FolderSizesShown: Boolean;
begin
  Result := GFolderSizesShown;
end;

procedure AllowFolderSizeWalks;
begin
  GFolderSizesArmed := True;
end;

{ TFolderSizeCache.TSizeJob }

constructor TFolderSizeCache.TSizeJob.Create;
begin
  inherited Create;
  Owners := TList<TObject>.Create;
end;

destructor TFolderSizeCache.TSizeJob.Destroy;
begin
  Owners.Free;
  inherited;
end;

function TFolderSizeCache.TSizeJob.IsCancelled: Boolean;
begin
  Result := TInterlocked.CompareExchange(Cancel, 0, 0) <> 0;
end;

procedure TFolderSizeCache.TSizeJob.MarkCancel;
begin
  TInterlocked.Exchange(Cancel, 1);
end;

procedure TFolderSizeCache.TSizeJob.AddOwner(AOwner: TObject);
begin
  if (AOwner <> nil) and (Owners.IndexOf(AOwner) < 0) then
    Owners.Add(AOwner);
end;

function TFolderSizeCache.TSizeJob.HasOwner(AOwner: TObject): Boolean;
begin
  Result := Owners.IndexOf(AOwner) >= 0;
end;

procedure TFolderSizeCache.TSizeJob.RemoveOwner(AOwner: TObject);
begin
  Owners.Remove(AOwner);
end;

{ TFolderSizeCache.TSizeWatchThread }

constructor TFolderSizeCache.TSizeWatchThread.Create(ACache: TFolderSizeCache;
  const APath, AKey: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FCache := ACache;
  FPath := APath;
  FKey := AKey;
  FStop := TEvent.Create(nil, True, False, '');
  FChange := TEvent.Create(nil, True, False, '');
end;

destructor TFolderSizeCache.TSizeWatchThread.Destroy;
begin
  FChange.Free;
  FStop.Free;
  inherited;
end;

procedure TFolderSizeCache.TSizeWatchThread.ShutdownAndFree;
begin
  Terminate;
  if Assigned(FStop) then
    FStop.SetEvent;
  { CreateFile по отвалившейся шаре не возвращается. Не WaitFor. }
  if Finished then
    Free
  else
  begin
    TInterlocked.Exchange(FDetached, 1);
    TInterlocked.Increment(FCache.FAbandoned);
    FreeOnTerminate := True;
  end;
end;

procedure TFolderSizeCache.TSizeWatchThread.HandOff(const ARels: TArray<string>;
  AOverflow: Boolean);
var
  Cache: TFolderSizeCache;
  Key: string;
  Rels: TArray<string>;
  Overflow: Boolean;
begin
  Cache := FCache;
  Key := FKey;
  Rels := Copy(ARels);
  Overflow := AOverflow;
  if Cache = nil then
    Exit;
  Queue(
    procedure
    begin
      if not Cache.FShuttingDown then
        Cache.ApplyWatch(Key, Rels, Overflow);
    end);
end;

procedure TFolderSizeCache.TSizeWatchThread.Execute;
{$IFDEF MSWINDOWS}
const
  NotifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
    FILE_NOTIFY_CHANGE_SIZE;
var
  Dir: THandle;
  Buf: TBytes;
  Ov: TOverlapped;
  Bytes: DWORD;
  Handles: array[0..1] of THandle;
  Rels: TList<string>;
  WaitRes: DWORD;
  Overflow: Boolean;
  Stop: Boolean;

  function Issue: Boolean;
  begin
    FillChar(Ov, SizeOf(Ov), 0);
    Ov.hEvent := FChange.Handle;
    FChange.ResetEvent;
    Bytes := 0;
    Result := ReadDirectoryChangesW(Dir, @Buf[0], Length(Buf), True, NotifyFilter,
      @Bytes, @Ov, nil);
    if not Result then
      Result := GetLastError = ERROR_IO_PENDING;
  end;

  procedure Collect;
  var
    Info: PFolderNotifyInfo;
    P, Base: PByte;
    Name: string;
    Next: DWORD;
  begin
    if Bytes = 0 then
      Exit;
    Base := @Buf[0];
    P := Base;
    while True do
    begin
      Info := PFolderNotifyInfo(P);
      SetString(Name, PChar(@Info.FileName[0]), Info.FileNameLength div SizeOf(Char));
      if Name <> '' then
        Rels.Add(Name);
      Next := Info.NextEntryOffset;
      if Next = 0 then
        Break;
      Inc(P, Next);
      if NativeUInt(P) - NativeUInt(Base) >= Bytes then
        Break;
    end;
  end;
{$ENDIF}
begin
  try
{$IFDEF MSWINDOWS}
  Dir := CreateFile(PChar(FPath), FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
  if Dir = INVALID_HANDLE_VALUE then
    Exit;
  SetLength(Buf, 65536);
  Rels := TList<string>.Create;
  try
    Handles[0] := FStop.Handle;
    Handles[1] := FChange.Handle;
    while not Terminated do
    begin
      if not Issue then
        Break;
      WaitRes := WaitForMultipleObjects(2, @Handles[0], False, INFINITE);
      if Terminated or (WaitRes = WAIT_OBJECT_0) or (WaitRes = WAIT_FAILED) then
      begin
        CancelIo(Dir);
        Break;
      end;
      if WaitRes <> WAIT_OBJECT_0 + 1 then
        Break;
      if not GetOverlappedResult(Dir, Ov, Bytes, False) then
      begin
        if GetLastError = ERROR_NOTIFY_ENUM_DIR then
        begin
          HandOff(nil, True);
          Continue;
        end;
        Break;
      end;
      Rels.Clear;
      Overflow := Bytes = 0;
      if not Overflow then
        Collect;
      Stop := False;
      while not Terminated and not Stop do
      begin
        if not Issue then
          Break;
        WaitRes := WaitForMultipleObjects(2, @Handles[0], False, WatchCoalesceMs);
        if Terminated or (WaitRes = WAIT_OBJECT_0) or (WaitRes = WAIT_FAILED) then
        begin
          CancelIo(Dir);
          Stop := True;
          Break;
        end;
        if WaitRes = WAIT_TIMEOUT then
          Break;
        if WaitRes <> WAIT_OBJECT_0 + 1 then
          Break;
        if not GetOverlappedResult(Dir, Ov, Bytes, False) then
        begin
          if GetLastError = ERROR_NOTIFY_ENUM_DIR then
            Overflow := True;
          Break;
        end;
        if Bytes = 0 then
          Overflow := True
        else
          Collect;
        if Rels.Count > 400 then
          Overflow := True;
      end;
      if Stop or Terminated then
        Break;
      if Overflow or (Rels.Count > 0) then
        HandOff(Rels.ToArray, Overflow);
    end;
  finally
    Rels.Free;
    CloseHandle(Dir);
  end;
{$ENDIF}
  finally
    if TInterlocked.Exchange(FDetached, 0) <> 0 then
      TInterlocked.Decrement(FCache.FAbandoned);
  end;
end;

{ TFolderSizeCache }

constructor TFolderSizeCache.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TDictionary<string, TSizeRec>.Create;
  FJobs := TDictionary<string, TSizeJob>.Create;
  FQueue := TQueue<TSizeJob>.Create;
  FEpoch := TDictionary<string, Integer>.Create;
  FOwnerRoot := TDictionary<TObject, string>.Create;
  FWatchRefs := TDictionary<string, Integer>.Create;
  FWatches := TDictionary<string, TSizeWatchThread>.Create;
  FWakes := TDictionary<TObject, TProc>.Create;
end;

destructor TFolderSizeCache.Destroy;
var
  Job: TSizeJob;
begin
  Shutdown;
  if FBusy = 0 then
  begin
    for Job in FJobs.Values do
      Job.Free;
    FJobs.Free;
    FQueue.Free;
    FItems.Free;
    FEpoch.Free;
    FOwnerRoot.Free;
    FWatchRefs.Free;
    FWatches.Free;
    FWakes.Free;
    FLock.Free;
  end;
  FreeAndNil(FSortSnap);
  inherited;
end;

procedure TFolderSizeCache.Shutdown;
var
  Job: TSizeJob;
  Threads: TList<TSizeWatchThread>;
  Thr: TSizeWatchThread;
begin
  FShuttingDown := True;
  Threads := TList<TSizeWatchThread>.Create;
  try
    FLock.Enter;
    try
      for Job in FJobs.Values do
      begin
        Job.MarkCancel;
        Job.Restart := False;
      end;
      FQueue.Clear;
      for Thr in FWatches.Values do
        Threads.Add(Thr);
      FWatches.Clear;
      FWatchRefs.Clear;
      FOwnerRoot.Clear;
    finally
      FLock.Leave;
    end;
    for Thr in Threads do
      Thr.ShutdownAndFree;
  finally
    Threads.Free;
  end;
end;

procedure TFolderSizeCache.WakeAll;
var
  List: TList<TProc>;
  P: TProc;
begin
  if FShuttingDown then
    Exit;
  List := TList<TProc>.Create;
  try
    FLock.Enter;
    try
      for P in FWakes.Values do
        List.Add(P);
    finally
      FLock.Leave;
    end;
    for P in List do
      if Assigned(P) then
        P();
  finally
    List.Free;
  end;
end;

procedure TFolderSizeCache.TrimCache;
var
  Pair: TPair<string, TSizeRec>;
  OldestKey: string;
  Oldest: TDateTime;
begin
  while FItems.Count > MaxCacheEntries do
  begin
    OldestKey := '';
    Oldest := EncodeDate(9999, 1, 1);
    for Pair in FItems do
      if Pair.Value.Written < Oldest then
      begin
        Oldest := Pair.Value.Written;
        OldestKey := Pair.Key;
      end;
    if OldestKey = '' then
      Break;
    FItems.Remove(OldestKey);
  end;
end;

function TFolderSizeCache.Lookup(const AKey: string; AModified: TDateTime;
  out ARec: TSizeRec; out AStatus: TFolderSizeStatus): Boolean;
var
  Job: TSizeJob;
begin
  Result := False;
  AStatus := fssNone;
  ARec := Default(TSizeRec);
  { Готовое число не выбрасывается из-за более новой метки списка: C3 и сортировка
    держат последний полный обход, пока новый не запишется поверх. }
  if FItems.TryGetValue(AKey, ARec) and ARec.Recursive and (ARec.Status = fssReady) then
  begin
    AStatus := fssReady;
    Exit(True);
  end;
  if FItems.TryGetValue(AKey, ARec) and ARec.Recursive and
     not ARec.Dirty and StampFresh(ARec.Stamp, AModified) and
     (ARec.Status in [fssError, fssPartial]) then
  begin
    AStatus := ARec.Status;
    Exit(True);
  end;
  if FJobs.TryGetValue(AKey, Job) then
  begin
    AStatus := fssPending;
    Exit(True);
  end;
end;

procedure TFolderSizeCache.Query(const APath: string; AModified: TDateTime;
  out ABytes: Int64; out AStatus: TFolderSizeStatus);
var
  Rec: TSizeRec;
begin
  ABytes := 0;
  AStatus := fssNone;
  if FShuttingDown or (APath = '') then
    Exit;
  FLock.Enter;
  try
    if not Lookup(NormFolderKey(APath), AModified, Rec, AStatus) then
      AStatus := fssNone;
    if AStatus = fssReady then
      ABytes := Rec.Bytes
    else
      ABytes := 0;
  finally
    FLock.Leave;
  end;
end;

function TFolderSizeCache.ReadyBytes(const APath: string; AModified: TDateTime;
  out ABytes: Int64): Boolean;
var
  Status: TFolderSizeStatus;
begin
  Query(APath, AModified, ABytes, Status);
  Result := Status = fssReady;
  if not Result then
    ABytes := 0;
end;

procedure TFolderSizeCache.EnsureJob(AOwner: TObject; const APath, AKey: string;
  ARemote: Boolean);
var
  Job: TSizeJob;
  Pair: TPair<TObject, string>;
begin
  if FShuttingDown or not GFolderSizesArmed or (AKey = '') or not GFolderSizesShown then
    Exit;
  { Автопоказ по UNC и сетевому диску очередь не кормит. }
  if ARemote or IsRemotePath(APath) then
    Exit;
  if FJobs.TryGetValue(AKey, Job) then
  begin
    Job.AddOwner(AOwner);
    if Job.IsCancelled and (Job.Owners.Count > 0) then
      Job.Restart := True;
    Exit;
  end;
  Job := TSizeJob.Create;
  Job.Path := ExcludeTrailingPathDelimiter(APath);
  Job.Key := AKey;
  Job.Remote := ARemote;
  FEpoch.TryGetValue(AKey, Job.Epoch);
  Job.AddOwner(AOwner);
  for Pair in FOwnerRoot do
    if (Pair.Key <> AOwner) and (Pair.Value <> '') and UnderKey(AKey, Pair.Value) then
      Job.AddOwner(Pair.Key);
  FJobs.Add(AKey, Job);
  FQueue.Enqueue(Job);
end;

function TFolderSizeCache.CellText(AOwner: TObject; const APath: string;
  AModified: TDateTime; ARemote: Boolean): string;
var
  Key: string;
  Rec: TSizeRec;
  Have, NeedJob: Boolean;
  Bytes: Int64;
begin
  if not GFolderSizesShown or FShuttingDown or (APath = '') then
    Exit(FolderSizeDeniedMark);
  if ARemote or IsRemotePath(APath) then
    Exit(FolderSizeDeniedMark);
  Key := NormFolderKey(APath);
  Have := False;
  NeedJob := True;
  Bytes := 0;
  Result := FolderSizePendingMark;
  FLock.Enter;
  try
    if FItems.TryGetValue(Key, Rec) and Rec.Recursive then
    begin
      if Rec.Status = fssReady then
      begin
        Bytes := Rec.Bytes;
        Have := True;
        NeedJob := Rec.Dirty or not StampFresh(Rec.Stamp, AModified);
      end
      else if (Rec.Status = fssError) and not Rec.Dirty and
              StampFresh(Rec.Stamp, AModified) then
      begin
        NeedJob := False;
        Result := FolderSizeDeniedMark;
      end
      else if (Rec.Status = fssPartial) and not Rec.Dirty and
              StampFresh(Rec.Stamp, AModified) then
      begin
        NeedJob := False;
        Result := FolderSizePartialMark;
      end;
    end;
    if NeedJob then
      EnsureJob(AOwner, ExcludeTrailingPathDelimiter(APath), Key, ARemote);
  finally
    FLock.Leave;
  end;
  if NeedJob then
    Pump;
  if Have then
    Result := FormatFileSize(Bytes);
end;

procedure TFolderSizeCache.CancelOtherManual(const AKeepKey: string);
var
  Job: TSizeJob;
begin
  if (FManualKey = '') or (FManualKey = AKeepKey) then
    Exit;
  if not FJobs.TryGetValue(FManualKey, Job) or not Job.Manual then
    Exit;
  { Локальный обход при включённом показе ждёт ещё и колонка. Его не рвём. }
  if not (Job.Remote or not GFolderSizesShown) then
    Exit;
  Job.MarkCancel;
  Job.Restart := False;
  Job.Owners.Clear;
end;

function TFolderSizeCache.RequestOne(AOwner: TObject; const APath: string;
  AModified: TDateTime): TFolderSizeStatus;
var
  Key, Path: string;
  Rec: TSizeRec;
  Job: TSizeJob;
  Remote, NeedPump: Boolean;
begin
  Result := fssNone;
  Path := ExcludeTrailingPathDelimiter(Trim(APath));
  Key := NormFolderKey(Path);
  if FShuttingDown or not GFolderSizesArmed or (AOwner = nil) or (Key = '') then
    Exit;
  Remote := IsRemotePath(Path);
  NeedPump := False;
  FLock.Enter;
  try
    if not FShuttingDown then
    begin
      CancelOtherManual(Key);
      FManualKey := Key;
      NeedPump := True;
      if FJobs.TryGetValue(Key, Job) then
      begin
        Job.AddOwner(AOwner);
        if Job.IsCancelled and (Job.Owners.Count > 0) then
          Job.Restart := True;
        if Remote or not GFolderSizesShown then
          Job.Manual := True;
        Result := fssPending;
      end
      else if FItems.TryGetValue(Key, Rec) and Rec.Recursive and
              (Rec.Status = fssReady) and not Rec.Dirty and
              StampFresh(Rec.Stamp, AModified) then
        Result := fssReady
      else
      begin
        Job := TSizeJob.Create;
        Job.Path := Path;
        Job.Key := Key;
        Job.Remote := Remote;
        Job.Manual := True;
        FEpoch.TryGetValue(Key, Job.Epoch);
        Job.AddOwner(AOwner);
        FJobs.Add(Key, Job);
        FQueue.Enqueue(Job);
        Result := fssPending;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if NeedPump then
    Pump;
end;

procedure TFolderSizeCache.Peek(const APath: string; AJobIsPending: Boolean;
  out AStatus: TFolderSizeStatus; out ABytes: Int64; out AHasSum: Boolean);
var
  Key: string;
  Rec: TSizeRec;
begin
  AStatus := fssNone;
  ABytes := 0;
  AHasSum := False;
  Key := NormFolderKey(APath);
  if FShuttingDown or (Key = '') then
    Exit;
  FLock.Enter;
  try
    if AJobIsPending and FJobs.ContainsKey(Key) then
    begin
      AStatus := fssPending;
      Exit;
    end;
    if not FItems.TryGetValue(Key, Rec) or not Rec.Recursive then
      Exit;
    if Rec.Status = fssReady then
    begin
      AStatus := fssReady;
      ABytes := Rec.Bytes;
      AHasSum := True;
    end
    else if Rec.Status = fssPartial then
    begin
      AStatus := fssPartial;
      AHasSum := Rec.HasSum;
      if AHasSum then
        ABytes := Rec.Bytes;
    end
    else if Rec.Status = fssError then
      AStatus := fssError;
  finally
    FLock.Leave;
  end;
end;

procedure TFolderSizeCache.RequestFolders(AOwner: TObject; const APaths: TArray<string>;
  const AModified: TArray<TDateTime>);
var
  I: Integer;
  Key, Path: string;
  Rec: TSizeRec;
  Need: Boolean;
  ModStamp: TDateTime;
begin
  if (AOwner = nil) or not GFolderSizesArmed or not GFolderSizesShown or
     FShuttingDown or (Length(APaths) = 0) then
    Exit;
  Need := False;
  FLock.Enter;
  try
    if FShuttingDown then
      Exit;
    for I := 0 to High(APaths) do
    begin
      Path := ExcludeTrailingPathDelimiter(Trim(APaths[I]));
      Key := NormFolderKey(Path);
      if (Key = '') or IsRemotePath(Path) then
        Continue;
      ModStamp := 0;
      if I <= High(AModified) then
        ModStamp := AModified[I];
      if FItems.TryGetValue(Key, Rec) and Rec.Recursive and (Rec.Status = fssReady) and
         not Rec.Dirty and StampFresh(Rec.Stamp, ModStamp) then
        Continue;
      EnsureJob(AOwner, Path, Key, False);
      Need := True;
    end;
  finally
    FLock.Leave;
  end;
  if Need then
    Pump;
end;

procedure TFolderSizeCache.Pump;
var
  Job: TSizeJob;
  Drop: Boolean;
begin
  if FShuttingDown then
    Exit;
  while True do
  begin
    Drop := False;
    FLock.Enter;
    try
      if FShuttingDown or (FQueue.Count = 0) or (FBusy >= MaxWorkers) then
        Exit;
      Job := FQueue.Dequeue;
      if (Job <> nil) and Job.IsCancelled and not Job.Restart then
      begin
        FJobs.Remove(Job.Key);
        Drop := True;
      end
      else if Job <> nil then
      begin
        if Job.IsCancelled then
          TInterlocked.Exchange(Job.Cancel, 0);
        Inc(FBusy);
      end;
    finally
      FLock.Leave;
    end;
    if Drop then
      Job.Free
    else if Job <> nil then
      StartJob(Job);
  end;
end;

procedure TFolderSizeCache.StartJob(AJob: TSizeJob);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Bytes: Int64;
      Status: TFolderSizeStatus;
    begin
      Bytes := 0;
      try
        Status := Measure(AJob, Bytes);
      except
        Status := fssError;
        Bytes := 0;
      end;
      try
        FinishJob(AJob, Bytes, Status);
      except
        FLock.Enter;
        try
          FJobs.Remove(AJob.Key);
        finally
          FLock.Leave;
        end;
        AJob.Free;
      end;
      TInterlocked.Decrement(FBusy);
      if not FShuttingDown then
        Pump;
    end).Start;
end;

procedure TFolderSizeCache.FinishJob(AJob: TSizeJob; ABytes: Int64;
  AStatus: TFolderSizeStatus);
var
  Epoch: Integer;
  Rec, Old: TSizeRec;
  Keep, Changed, Had, Store, KeepReady: Boolean;
begin
  Keep := False;
  Changed := False;
  FLock.Enter;
  try
    Epoch := 0;
    FEpoch.TryGetValue(AJob.Key, Epoch);
    Store := (not AJob.IsCancelled) and (not FShuttingDown) and (AJob.Epoch = Epoch) and
      (AStatus in [fssReady, fssError, fssPartial]);
    if Store then
    begin
      Had := FItems.TryGetValue(AJob.Key, Old);
      KeepReady := False;
      if Had then
        KeepReady := (AStatus <> fssReady) and Old.Recursive and (Old.Status = fssReady);
      { Ошибка или таймаут не затирают уже показанный полный размер и не крутят повтор. }
      if KeepReady then
      begin
        Old.Dirty := False;
        Old.Stamp := Now;
        Old.Written := Now;
        FItems.AddOrSetValue(AJob.Key, Old);
      end
      else
      begin
        Rec.HasSum := (AStatus = fssReady) or
          ((AStatus = fssPartial) and AJob.Manual and AJob.Remote);
        Rec.Bytes := 0;
        if Rec.HasSum then
          Rec.Bytes := ABytes;
        Rec.Status := AStatus;
        Rec.Stamp := AJob.Stamp;
        Rec.Written := Now;
        Rec.Recursive := True;
        Rec.Dirty := False;
        FItems.AddOrSetValue(AJob.Key, Rec);
        TrimCache;
        Changed := not Had;
        if Had then
          Changed := (not Old.Recursive) or (Old.Status <> Rec.Status) or
            (Old.HasSum <> Rec.HasSum) or
            (Rec.HasSum and (Old.Bytes <> Rec.Bytes));
      end;
    end;
    if AJob.Restart and (AJob.Owners.Count > 0) and not FShuttingDown then
    begin
      AJob.Restart := False;
      TInterlocked.Exchange(AJob.Cancel, 0);
      AJob.Stamp := 0;
      FEpoch.TryGetValue(AJob.Key, AJob.Epoch);
      FQueue.Enqueue(AJob);
      Keep := True;
    end
    else
      FJobs.Remove(AJob.Key);
  finally
    FLock.Leave;
  end;
  if not Keep then
    AJob.Free;
  { То же число панель не перерисовывает и не пересортировывает. }
  if Changed then
    TInterlocked.Increment(FGeneration);
end;

function TFolderSizeCache.Measure(AJob: TSizeJob; out ABytes: Int64): TFolderSizeStatus;
const
  MaxDepth = 128;
var
  Sum: Int64;
  Started: Cardinal;
  Budget: Cardinal;
  Seen: TDictionary<string, Boolean>;

  function TimedOut: Boolean;
  begin
    Result := Cardinal(TThread.GetTickCount - Started) >= Budget;
  end;

  function WalkDir(const ADir: string; ARoot: Boolean; ADepth: Integer): TFolderSizeStatus;
  var
    SR: TSearchRec;
    Code, N: Integer;
    Full, Key: string;
    Nested: TFolderSizeStatus;
  begin
    if AJob.IsCancelled or FShuttingDown then
      Exit(fssNone);
    if TimedOut then
      Exit(fssPartial);
    if ADepth > MaxDepth then
      Exit(fssPartial);
    Code := FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR);
    if Code <> 0 then
    begin
      { Корень недоступен — ошибки. Вложенный пропуск, как в окне операции. }
      if ARoot then
        Exit(fssError);
      Exit(fssReady);
    end;
    Result := fssReady;
    try
      N := 0;
      while Code = 0 do
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          if (SR.Attr and faDirectory) <> 0 then
          begin
            if (SR.Attr and FILE_ATTRIBUTE_REPARSE_POINT) = 0 then
            begin
              Full := IncludeTrailingPathDelimiter(ADir) + SR.Name;
              Key := NormFolderKey(Full);
              if not Seen.ContainsKey(Key) then
              begin
                Seen.Add(Key, True);
                Nested := WalkDir(Full, False, ADepth + 1);
                if Nested <> fssReady then
                  Exit(Nested);
              end;
            end;
          end
          else if SR.Size > 0 then
          begin
            if Sum > High(Int64) - SR.Size then
              Exit(fssPartial);
            Inc(Sum, SR.Size);
          end;
        end;
        Inc(N);
        if (N and 63) = 0 then
        begin
          if AJob.IsCancelled or FShuttingDown then
            Exit(fssNone);
          if TimedOut then
            Exit(fssPartial);
        end;
        Code := FindNext(SR);
      end;
    finally
      System.SysUtils.FindClose(SR);
    end;
  end;

var
  Attr: DWORD;
begin
  ABytes := 0;
  AJob.Stamp := 0;
  Sum := 0;
  if AJob.IsCancelled or FShuttingDown then
    Exit(fssNone);
  AJob.Remote := IsRemotePath(AJob.Path);
  FLock.Enter;
  try
    { События до старта уже в снимке диска. Повтор — только если каталог изменится в обходе. }
    if not AJob.IsCancelled then
      AJob.Restart := False;
  finally
    FLock.Leave;
  end;
  if AJob.IsCancelled or FShuttingDown then
    Exit(fssNone);
{$IFDEF MSWINDOWS}
  Attr := GetFileAttributes(PChar(AJob.Path));
  if (Attr <> INVALID_FILE_ATTRIBUTES) and ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
    Exit(fssError);
{$ENDIF}
  if AJob.Remote and AJob.Manual then
    Budget := ManualRemoteTimeoutMs
  else if AJob.Remote then
    Budget := RemoteTimeoutMs
  else
    Budget := LocalTimeoutMs;
  Started := TThread.GetTickCount;
  AJob.Stamp := DirStamp(AJob.Path);
  Seen := TDictionary<string, Boolean>.Create;
  try
    Seen.Add(NormFolderKey(AJob.Path), True);
    Result := WalkDir(AJob.Path, True, 0);
    if (Result = fssReady) or
       ((Result = fssPartial) and AJob.Manual and AJob.Remote) then
      ABytes := Sum;
  finally
    Seen.Free;
  end;
end;

procedure TFolderSizeCache.ReleaseExceptUnder(AOwner: TObject; const ARoot: string);
var
  Job: TSizeJob;
begin
  for Job in FJobs.Values do
  begin
    if not Job.HasOwner(AOwner) then
      Continue;
    if (ARoot <> '') and UnderKey(Job.Path, ARoot) then
      Continue;
    Job.RemoveOwner(AOwner);
    if Job.Owners.Count = 0 then
    begin
      { Смена каталога ручной обход не обрывает: кэш ещё пригодится этой строке. }
      if Job.Manual and (Job.Key = FManualKey) then
        Continue;
      Job.MarkCancel;
      Job.Restart := False;
    end;
  end;
end;

function TFolderSizeCache.MarkDirty(const APath: string; ADescendants,
  AEnqueueSelf: Boolean): Boolean;
var
  Root, Key: string;
  Keys: TList<string>;
  Rec: TSizeRec;
  Job: TSizeJob;

  function Hit(const AKey: string): Boolean;
  begin
    Result := (AEnqueueSelf and (AKey = Root)) or
      (ADescendants and AKey.StartsWith(Root + '\'));
  end;

begin
  Result := False;
  Root := NormFolderKey(APath);
  if Root = '' then
    Exit;
  Keys := TList<string>.Create;
  try
    for Key in FJobs.Keys do
      if Hit(Key) and FJobs.TryGetValue(Key, Job) then
      begin
        Job.Restart := True;
        Result := True;
      end;
    for Key in FItems.Keys do
      if Hit(Key) then
        Keys.Add(Key);
    for Key in Keys do
    begin
      if FItems.TryGetValue(Key, Rec) and not Rec.Dirty then
      begin
        Rec.Dirty := True;
        FItems.AddOrSetValue(Key, Rec);
      end;
      Result := True;
      if not FJobs.ContainsKey(Key) then
        EnsureJob(nil, Key, Key, False);
    end;
  finally
    Keys.Free;
  end;
end;

procedure TFolderSizeCache.InvalidateUnder(const APath: string);
var
  Any: Boolean;
begin
  if FShuttingDown or (NormFolderKey(APath) = '') then
    Exit;
  Any := False;
  FLock.Enter;
  try
    if not FShuttingDown then
      Any := MarkDirty(APath, True, False);
  finally
    FLock.Leave;
  end;
  if Any then
  begin
    Pump;
    WakeAll;
  end;
end;

procedure TFolderSizeCache.ApplyWatch(const ARoot: string; const ARels: TArray<string>;
  AOverflow: Boolean);
var
  Rel, Child, RootKey: string;
  P, I: Integer;
  Seen: TDictionary<string, Boolean>;
  Any: Boolean;
begin
  if FShuttingDown or (NormFolderKey(ARoot) = '') then
    Exit;
  RootKey := NormFolderKey(ARoot);
  Any := False;
  if AOverflow or (ARels = nil) or (Length(ARels) = 0) then
  begin
    FLock.Enter;
    try
      if not FShuttingDown then
        Any := MarkDirty(RootKey, True, False);
    finally
      FLock.Leave;
    end;
  end
  else
  begin
    Seen := TDictionary<string, Boolean>.Create;
    try
      FLock.Enter;
      try
        if not FShuttingDown then
          for I := 0 to High(ARels) do
          begin
            Rel := StringReplace(ARels[I], '/', '\', [rfReplaceAll]);
            P := Pos('\', Rel);
            if P <= 1 then
              Continue;
            Child := Copy(Rel, 1, P - 1);
            if (Child = '') or (Child = '.') or (Child = '..') then
              Continue;
            if Seen.ContainsKey(LowerCase(Child)) then
              Continue;
            Seen.Add(LowerCase(Child), True);
            if MarkDirty(RootKey + '\' + LowerCase(Child), True, True) then
              Any := True;
          end;
      finally
        FLock.Leave;
      end;
    finally
      Seen.Free;
    end;
  end;
  if Any then
  begin
    Pump;
    WakeAll;
  end;
end;

procedure TFolderSizeCache.NotePanelRoot(AOwner: TObject; const APath: string);
var
  Root, Prev, PrevWatch, Watch: string;
  N: Integer;
  StopThr, StartThr: TSizeWatchThread;
begin
  if (AOwner = nil) or not GFolderSizesArmed then
    Exit;
  Root := NormFolderKey(APath);
  if WatchableRoot(APath) then
    Watch := Root
  else
    Watch := '';
  StopThr := nil;
  StartThr := nil;
  FLock.Enter;
  try
    if FShuttingDown then
      Exit;
    Prev := '';
    FOwnerRoot.TryGetValue(AOwner, Prev);
    PrevWatch := '';
    if WatchableRoot(Prev) then
      PrevWatch := NormFolderKey(Prev);
    if (Prev = Root) and (PrevWatch = Watch) then
      Exit;
    if PrevWatch <> '' then
    begin
      N := 0;
      if FWatchRefs.TryGetValue(PrevWatch, N) then
      begin
        Dec(N);
        if N <= 0 then
        begin
          FWatchRefs.Remove(PrevWatch);
          FWatches.TryGetValue(PrevWatch, StopThr);
          FWatches.Remove(PrevWatch);
        end
        else
          FWatchRefs.AddOrSetValue(PrevWatch, N);
      end;
    end;
    if Root = '' then
      FOwnerRoot.Remove(AOwner)
    else
      FOwnerRoot.AddOrSetValue(AOwner, Root);
    if Watch <> '' then
    begin
      N := 0;
      FWatchRefs.TryGetValue(Watch, N);
      Inc(N);
      FWatchRefs.AddOrSetValue(Watch, N);
      if N = 1 then
      begin
        StartThr := TSizeWatchThread.Create(Self,
          IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(APath)), Watch);
        FWatches.Add(Watch, StartThr);
      end;
    end;
    ReleaseExceptUnder(AOwner, Root);
  finally
    FLock.Leave;
  end;
  if StartThr <> nil then
    StartThr.Start;
  if StopThr <> nil then
    StopThr.ShutdownAndFree;
end;

procedure TFolderSizeCache.Advise(AOwner: TObject; const AWake: TProc);
begin
  if (AOwner = nil) or FShuttingDown then
    Exit;
  FLock.Enter;
  try
    FWakes.AddOrSetValue(AOwner, AWake);
  finally
    FLock.Leave;
  end;
end;

procedure TFolderSizeCache.Unadvise(AOwner: TObject);
begin
  if AOwner = nil then
    Exit;
  FLock.Enter;
  try
    FWakes.Remove(AOwner);
  finally
    FLock.Leave;
  end;
end;

function TFolderSizeCache.HasWork: Boolean;
begin
  FLock.Enter;
  try
    Result := (FQueue.Count > 0) or (FBusy > 0);
  finally
    FLock.Leave;
  end;
end;

function TFolderSizeCache.Generation: Integer;
begin
  Result := FGeneration;
end;

function TFolderSizeCache.Quiescent: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FBusy, 0, 0) = 0) and
    (TInterlocked.CompareExchange(FAbandoned, 0, 0) = 0);
end;

procedure TFolderSizeCache.BeginSortSnapshot;
var
  Pair: TPair<string, TSizeRec>;
begin
  EndSortSnapshot;
  FSortSnap := TDictionary<string, Int64>.Create;
  if FShuttingDown then
    Exit;
  FLock.Enter;
  try
    for Pair in FItems do
      if Pair.Value.Recursive and (Pair.Value.Status = fssReady) then
        FSortSnap.AddOrSetValue(Pair.Key, Pair.Value.Bytes);
  finally
    FLock.Leave;
  end;
end;

procedure TFolderSizeCache.EndSortSnapshot;
begin
  FreeAndNil(FSortSnap);
end;

function TFolderSizeCache.SortSnapshotOn: Boolean;
begin
  Result := FSortSnap <> nil;
end;

function TFolderSizeCache.SnapshotBytes(const APath: string; out ABytes: Int64): Boolean;
begin
  ABytes := 0;
  Result := Assigned(FSortSnap) and FSortSnap.TryGetValue(NormFolderKey(APath), ABytes);
end;

initialization
  GlobalFolderSizes := TFolderSizeCache.Create;

finalization
  if Assigned(GlobalFolderSizes) then
  begin
    GlobalFolderSizes.Shutdown;
    if GlobalFolderSizes.Quiescent then
      FreeAndNil(GlobalFolderSizes);
  end;

end.
