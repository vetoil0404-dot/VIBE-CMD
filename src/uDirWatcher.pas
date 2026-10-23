unit uDirWatcher;

{
  Наблюдение за каталогом через Directory Change Notifications
  (FindFirstChangeNotification / FindNextChangeNotification).
}

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

type
  TDirChangeNotify = reference to procedure(const APath: string);

  TDirWatcher = class
  private
    FPath: string;
    FOnChange: TDirChangeNotify;
    FThread: TThread;
    FStopEvent: TEvent;
    FRemote: Boolean;
    procedure StopThread;
    procedure FireChange;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Watch(const APath: string);
    procedure Stop;
    property OnChange: TDirChangeNotify read FOnChange write FOnChange;
    property Path: string read FPath;
  end;

implementation

uses
  uFileModel;

type
  TDirWatchThread = class(TThread)
  private
    FOwner: TDirWatcher;
    FPath: string;
    FStopEvent: THandle;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDirWatcher; const APath: string; AStopEvent: THandle);
    procedure Detach;
  end;

constructor TDirWatchThread.Create(AOwner: TDirWatcher; const APath: string;
  AStopEvent: THandle);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FPath := APath;
  FStopEvent := AStopEvent;
end;

procedure TDirWatchThread.Detach;
begin
  FOwner := nil;
  Terminate;
end;

procedure TDirWatchThread.Execute;
{$IFDEF MSWINDOWS}
const
  { Без ATTRIBUTES: Thumbs.db и desktop.ini иначе сыпят ложные срабатывания. }
  NotifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME or
                 FILE_NOTIFY_CHANGE_DIR_NAME or
                 FILE_NOTIFY_CHANGE_SIZE or
                 FILE_NOTIFY_CHANGE_LAST_WRITE;
var
  ChangeHandle: THandle;
  Handles: array[0..1] of THandle;
  WaitRes: DWORD;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  ChangeHandle := FindFirstChangeNotification(PChar(FPath), False, NotifyFilter);
  if ChangeHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    Handles[0] := ChangeHandle;
    Handles[1] := FStopEvent;
    while not Terminated do
    begin
      WaitRes := WaitForMultipleObjects(2, @Handles[0], False, INFINITE);
      if Terminated or (WaitRes = WAIT_OBJECT_0 + 1) or (WaitRes = WAIT_FAILED) then
        Break;
      if WaitRes = WAIT_OBJECT_0 then
      begin
        repeat
          if not FindNextChangeNotification(ChangeHandle) then
            Break;
          WaitRes := WaitForMultipleObjects(2, @Handles[0], False, 300);
        until (WaitRes <> WAIT_OBJECT_0) or Terminated;
        if Terminated or (WaitRes = WAIT_OBJECT_0 + 1) then
          Break;
        Queue(procedure
          begin
            if Assigned(FOwner) then
              FOwner.FireChange;
          end);
      end;
    end;
  finally
    FindCloseChangeNotification(ChangeHandle);
  end;
  {$ENDIF}
end;

{ TDirWatcher }

constructor TDirWatcher.Create;
begin
  inherited Create;
  FStopEvent := TEvent.Create(nil, True, False, '');
end;

destructor TDirWatcher.Destroy;
begin
  FOnChange := nil;
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TDirWatcher.StopThread;
var
  T: TThread;
  Remote: Boolean;
begin
  if FThread = nil then
    Exit;
  T := FThread;
  FThread := nil;
  Remote := FRemote;
  TDirWatchThread(T).Detach;
  if Assigned(FStopEvent) then
    FStopEvent.SetEvent;
  if not Remote then
  begin
    T.WaitFor;
    T.Free;
    if Assigned(FStopEvent) then
      FStopEvent.ResetEvent;
    Exit;
  end;
  if T.Finished then
  begin
    T.Free;
    if Assigned(FStopEvent) then
      FStopEvent.ResetEvent;
    Exit;
  end;
  { FindFirstChangeNotification по сети может не вернуться. Поток держит
    старый хэндл события, новый — для следующего Watch. }
  T.FreeOnTerminate := True;
  FStopEvent := TEvent.Create(nil, True, False, '');
end;

procedure TDirWatcher.Stop;
begin
  StopThread;
  FPath := '';
end;

procedure TDirWatcher.Watch(const APath: string);
var
  Norm: string;
begin
  Norm := ExcludeTrailingPathDelimiter(APath);
  if SameText(Norm, FPath) and Assigned(FThread) then
    Exit;

  StopThread;
  FPath := Norm;
  FRemote := False;
  if FPath = '' then
    Exit;
  if UiSkipNetworkTouch(FPath) then
  begin
    FRemote := True;
    FPath := '';
    Exit;
  end;
  if not TDirectory.Exists(FPath) then
  begin
    FPath := '';
    Exit;
  end;

  FStopEvent.ResetEvent;
  if Length(Norm) <= 3 then
    Norm := IncludeTrailingPathDelimiter(Norm);
  FThread := TDirWatchThread.Create(Self, Norm, FStopEvent.Handle);
end;

procedure TDirWatcher.FireChange;
begin
  if Assigned(FOnChange) and (FPath <> '') then
    FOnChange(FPath);
end;

end.
