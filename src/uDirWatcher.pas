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
  CheckSynchronize;
  FStopEvent.Free;
  inherited;
end;

procedure TDirWatcher.StopThread;
var
  T: TThread;
  N: Integer;
  Remote: Boolean;
begin
  if FThread = nil then
    Exit;
  T := FThread;
  FThread := nil;
  Remote := FRemote;
  T.Terminate;
  FStopEvent.SetEvent;
  if not Remote then
  begin
    T.WaitFor;
    T.Free;
    Exit;
  end;
  N := 0;
  while (not T.Finished) and (N < 8) do
  begin
    Sleep(30);
    Inc(N);
  end;
  if T.Finished then
    T.Free
  else
    T.FreeOnTerminate := True;
end;

procedure TDirWatcher.Stop;
begin
  StopThread;
  FPath := '';
end;

procedure TDirWatcher.Watch(const APath: string);
var
  Norm: string;
  Remote: Boolean;
begin
  Norm := ExcludeTrailingPathDelimiter(APath);
  if SameText(Norm, FPath) and Assigned(FThread) then
    Exit;

  StopThread;
  FPath := Norm;
  FRemote := False;
  if FPath = '' then
    Exit;
  try
    Remote := (Length(Norm) >= 2) and (Norm[1] = '\') and (Norm[2] = '\');
{$IFDEF MSWINDOWS}
    if not Remote and (Length(Norm) >= 2) and (Norm[2] = ':') then
      Remote := GetDriveType(PChar(UpperCase(Norm[1]) + ':\')) = DRIVE_REMOTE;
{$ENDIF}
  except
    Remote := False;
  end;
  FRemote := Remote;
  if not Remote then
  begin
    if not TDirectory.Exists(FPath) then
    begin
      FPath := '';
      Exit;
    end;
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
