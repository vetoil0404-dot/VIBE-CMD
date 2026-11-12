unit uFileLock;

{
  Хто тримає файл: Restart Manager і вікно «Файл зайнятий».
  Сесію не тримаємо. Мережа, FTP і кошик сюди не потрапляють.
}

interface

type
  TFileLockChoice = (flcPass, flcRetry, flcCancel);

{ 32/33 на локальному файлі — вікно. Інакше flcPass, звичайна помилка лишається. }
function FileLockOffer(const APath: string; ACode: Cardinal): TFileLockChoice;
{ Користувач натиснув «Скасувати»: пакет далі не йде. }
function FileLockHalted: Boolean;
{ Скинути прапор перед новою операцією, щоб старе «Скасувати» не чіплялось. }
procedure FileLockReset;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics,
  Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,
  uFileModel, uLang, uLangBind, uThemeManager, uFluentChrome, UCoreEngine;

const
  CCH_RM_SESSION_KEY = 32;
  CCH_RM_MAX_APP_NAME = 255;
  CCH_RM_MAX_SVC_NAME = 63;
  RmCritical = 1000;
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  TRMUniqueProcess = packed record
    Pid: DWORD;
    Started: TFileTime;
  end;

  TRMProcessInfo = packed record
    Process: TRMUniqueProcess;
    AppName: array[0..CCH_RM_MAX_APP_NAME] of WideChar;
    ServiceName: array[0..CCH_RM_MAX_SVC_NAME] of WideChar;
    AppType: DWORD;
    AppStatus: ULONG;
    SessionId: DWORD;
    Restartable: BOOL;
  end;

  TFileLocker = record
    Pid: DWORD;
    Name: string;
    Exe: string;
    User: string;
    CanEnd: Boolean;
  end;

  TFileLockForm = class(TForm)
  private
    FColors: TThemeColors;
    FPath: string;
    FItems: TArray<TFileLocker>;
    FRows: TArray<TRectangle>;
    FSel: Integer;
    FAsk: Boolean;
    FRetryPrimary: Boolean;
    FChoice: TFileLockChoice;
    FDone: Boolean;
    FRoot: TRectangle;
    FNameText, FPathText, FStatus: TText;
    FScroll: TVertScrollBox;
    FList: TLayout;
    FBtnEnd, FBtnRetry, FBtnCancel: TFluentButton;
    procedure BuildUI;
    procedure ApplyNativeChrome;
    procedure Reload;
    procedure LayoutButtons;
    procedure ApplyRowColors;
    procedure RowClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
    procedure RetryClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure Finish(AChoice: TFileLockChoice);
    function Selected: Integer;
    procedure SyncEndButton;
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent; const APath: string); reintroduce;
    property Finished: Boolean read FDone;
    property Choice: TFileLockChoice read FChoice;
  end;

function RmStartSession(var ASession: DWORD; AFlags: DWORD;
  AKey: PWideChar): DWORD; stdcall; external 'rstrtmgr.dll' name 'RmStartSession';
function RmRegisterResources(ASession: DWORD; AFiles: UINT; ANames: PPWideChar;
  AApps: UINT; AAppInfo: Pointer; AServices: UINT; AServiceNames: Pointer): DWORD;
  stdcall; external 'rstrtmgr.dll' name 'RmRegisterResources';
function RmGetList(ASession: DWORD; var ANeeded, ACount: UINT; AInfo: Pointer;
  var AReason: DWORD): DWORD; stdcall; external 'rstrtmgr.dll' name 'RmGetList';
function RmEndSession(ASession: DWORD): DWORD; stdcall;
  external 'rstrtmgr.dll' name 'RmEndSession';
function QueryFullProcessImageNameW(AProcess: THandle; AFlags: DWORD;
  AName: PWideChar; var ASize: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'QueryFullProcessImageNameW';

var
  GHalt: Boolean;

function WideText(const ABuf: array of WideChar): string;
var
  N: Integer;
begin
  N := 0;
  while (N <= High(ABuf)) and (ABuf[N] <> #0) do
    Inc(N);
  SetString(Result, PWideChar(@ABuf[0]), N);
end;

function SharingCode(ACode: Cardinal): Boolean;
begin
  Result := (ACode = ERROR_SHARING_VIOLATION) or (ACode = ERROR_LOCK_VIOLATION);
end;

function LockPathOk(const APath: string): Boolean;
var
  Path, Root: string;
begin
  Result := False;
  Path := APath;
  if Path = '' then
    Exit;
  if Path.StartsWith('\\?\') then
    Path := Copy(Path, 5, MaxInt);
  if IsUncPath(Path) or IsVibeNetworkPath(Path) then
    Exit;
  if IsRecycleBinPath(Path) or IsRecycleItemPath(Path) then
    Exit;
  if not IsWin32FsPath(Path) then
    Exit;
  if (Length(Path) < 2) or (Path[2] <> ':') then
    Exit;
  Root := UpCase(Path[1]) + ':\';
  if GetDriveType(PChar(Root)) = DRIVE_REMOTE then
    Exit;
  Result := True;
end;

function ProtectedProcess(const AExe, AName: string; APid, AAppType: DWORD): Boolean;
const
  Blocked: array[0..4] of string = (
    'csrss.exe', 'lsass.exe', 'winlogon.exe', 'services.exe', 'smss.exe');
var
  Leaf, Shown: string;
  I: Integer;
begin
  Result := True;
  if (APid = 0) or (APid = GetCurrentProcessId) or (AAppType = RmCritical) then
    Exit;
  Leaf := LowerCase(ExtractFileName(AExe));
  Shown := LowerCase(ExtractFileName(AName));
  for I := 0 to High(Blocked) do
    if (Leaf = Blocked[I]) or (Shown = Blocked[I]) then
      Exit;
  Result := False;
end;

function ProcessImage(APid: DWORD): string;
var
  H: THandle;
  N: DWORD;
  Buf: array[0..1023] of Char;
begin
  Result := '';
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, APid);
  if H = 0 then
    Exit;
  try
    N := Length(Buf);
    if QueryFullProcessImageNameW(H, 0, Buf, N) then
      SetString(Result, Buf, N);
  finally
    CloseHandle(H);
  end;
end;

function ProcessUser(APid: DWORD): string;
var
  H, Tok: THandle;
  Need: DWORD;
  Info: PTokenUser;
  Name, Dom: array[0..255] of Char;
  NameN, DomN: DWORD;
  Use: SID_NAME_USE;
begin
  Result := '';
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, APid);
  if H = 0 then
    Exit;
  try
    Tok := 0;
    if not OpenProcessToken(H, TOKEN_QUERY, Tok) then
      Exit;
    try
      Need := 0;
      GetTokenInformation(Tok, TokenUser, nil, 0, Need);
      if Need = 0 then
        Exit;
      GetMem(Info, Need);
      try
        if not GetTokenInformation(Tok, TokenUser, Info, Need, Need) then
          Exit;
        NameN := Length(Name);
        DomN := Length(Dom);
        if not LookupAccountSid(nil, Info.User.Sid, Name, NameN, Dom, DomN, Use) then
          Exit;
        if (DomN > 0) and (Dom[0] <> #0) then
          Result := Copy(string(Dom), 1, DomN) + '\' + Copy(string(Name), 1, NameN)
        else
          Result := Copy(string(Name), 1, NameN);
      finally
        FreeMem(Info);
      end;
    finally
      if Tok <> 0 then
        CloseHandle(Tok);
    end;
  finally
    CloseHandle(H);
  end;
end;

function EndProcess(APid: DWORD): Boolean;
var
  H: THandle;
begin
  Result := False;
  if (APid = 0) or (APid = GetCurrentProcessId) then
    Exit;
  H := OpenProcess(PROCESS_TERMINATE, False, APid);
  if H = 0 then
    Exit;
  try
    Result := TerminateProcess(H, 1);
  finally
    CloseHandle(H);
  end;
end;

function QueryLockers(const APath: string): TArray<TFileLocker>;
var
  Session, Reason, Res: DWORD;
  Key: array[0..CCH_RM_SESSION_KEY] of WideChar;
  Name: PWideChar;
  Needed, Count: UINT;
  Info: TArray<TRMProcessInfo>;
  I, N: Integer;
  Seen: TArray<DWORD>;
  Exe, App, User: string;
  Item: TFileLocker;

  function SeenPid(APid: DWORD): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    for K := 0 to High(Seen) do
      if Seen[K] = APid then
        Exit(True);
  end;

begin
  SetLength(Result, 0);
  if SizeOf(TRMProcessInfo) <> 668 then
    Exit;
  FillChar(Key, SizeOf(Key), 0);
  if RmStartSession(Session, 0, Key) <> ERROR_SUCCESS then
    Exit;
  try
    Name := PWideChar(APath);
    if RmRegisterResources(Session, 1, @Name, 0, nil, 0, nil) <> ERROR_SUCCESS then
      Exit;
    Needed := 0;
    Count := 0;
    Reason := 0;
    Res := RmGetList(Session, Needed, Count, nil, Reason);
    if Res = ERROR_SUCCESS then
      Exit;
    if (Res <> ERROR_MORE_DATA) or (Needed = 0) then
      Exit;
    SetLength(Info, Needed);
    Count := Needed;
    Reason := 0;
    Res := RmGetList(Session, Needed, Count, @Info[0], Reason);
    if (Res <> ERROR_SUCCESS) or (Count = 0) then
      Exit;
    if Count > UINT(Length(Info)) then
      Count := UINT(Length(Info));
    for I := 0 to Integer(Count) - 1 do
    begin
      if (Info[I].Process.Pid = 0) or SeenPid(Info[I].Process.Pid) then
        Continue;
      N := Length(Seen);
      SetLength(Seen, N + 1);
      Seen[N] := Info[I].Process.Pid;
      App := Trim(WideText(Info[I].AppName));
      Exe := ProcessImage(Info[I].Process.Pid);
      User := ProcessUser(Info[I].Process.Pid);
      Item.Pid := Info[I].Process.Pid;
      Item.Exe := Exe;
      if Exe <> '' then
        Item.Name := ExtractFileName(Exe)
      else if App <> '' then
        Item.Name := App
      else
        Item.Name := IntToStr(Item.Pid);
      Item.User := User;
      Item.CanEnd := not ProtectedProcess(Exe, Item.Name, Item.Pid, Info[I].AppType);
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Item;
    end;
  finally
    RmEndSession(Session);
  end;
end;

function FileLockHalted: Boolean;
begin
  Result := GHalt;
end;

procedure FileLockReset;
begin
  GHalt := False;
end;

constructor TFileLockForm.Create(AOwner: TComponent; const APath: string);
begin
  inherited CreateNew(AOwner);
  FPath := APath;
  FSel := -1;
  FChoice := flcCancel;
  FColors := GetThemeColors(ActiveAppTheme);
  Width := 560;
  Height := 440;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  TrForm(Self, 'lock.title');
  Position := TFormPosition.MainFormCenter;
  BuildUI;
  Reload;
  ApplyNativeChrome;
end;

procedure TFileLockForm.ApplyNativeChrome;
var
  Wnd: HWND;
  Corner: Integer;
begin
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    Corner := 2;
    DwmSetWindowAttribute(Wnd, 33, @Corner, SizeOf(Corner));
  end;
end;

procedure TFileLockForm.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TFileLockForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
  LayoutButtons;
  BringToFront;
end;

procedure TFileLockForm.DoClose(var CloseAction: TCloseAction);
begin
  if not FDone then
  begin
    FChoice := flcCancel;
    FDone := True;
  end;
  CloseAction := TCloseAction.caHide;
end;

procedure TFileLockForm.Resize;
begin
  inherited;
  LayoutButtons;
end;

procedure TFileLockForm.Finish(AChoice: TFileLockChoice);
begin
  FChoice := AChoice;
  FDone := True;
  Close;
end;

procedure TFileLockForm.RetryClick(Sender: TObject);
begin
  Finish(flcRetry);
end;

procedure TFileLockForm.CancelClick(Sender: TObject);
begin
  Finish(flcCancel);
end;

function TFileLockForm.Selected: Integer;
begin
  Result := FSel;
  if (Result < 0) or (Result > High(FItems)) then
    Result := -1;
end;

procedure TFileLockForm.SyncEndButton;
var
  At: Integer;
begin
  At := Selected;
  FBtnEnd.Visible := Length(FItems) > 0;
  FBtnEnd.Enabled := (At >= 0) and FItems[At].CanEnd;
  if FBtnEnd.Enabled then
    FBtnEnd.Opacity := 1
  else
    FBtnEnd.Opacity := 0.45;
  if FAsk then
    FBtnEnd.SetCaption(L('lock.kill.yes'))
  else
    FBtnEnd.SetCaption(L('lock.end'));
  if FRetryPrimary then
  begin
    FBtnRetry.Kind := fbkAccent;
    FBtnEnd.Kind := fbkStandard;
  end
  else
  begin
    FBtnRetry.Kind := fbkStandard;
    FBtnEnd.Kind := fbkStandard;
  end;
  FBtnRetry.ApplyTheme(FColors);
  FBtnEnd.ApplyTheme(FColors);
  FBtnCancel.ApplyTheme(FColors);
end;

procedure TFileLockForm.ApplyRowColors;
var
  I: Integer;
begin
  for I := 0 to High(FRows) do
    if I = FSel then
      FRows[I].Fill.Color := FColors.ControlFillHover
    else
      FRows[I].Fill.Color := FColors.CardBackground;
end;

procedure TFileLockForm.RowClick(Sender: TObject);
begin
  if Sender is TControl then
    FSel := TControl(Sender).Tag;
  FAsk := False;
  if FStatus.Tag = 0 then
    FStatus.Text := '';
  ApplyRowColors;
  SyncEndButton;
  LayoutButtons;
end;

procedure TFileLockForm.LayoutButtons;
var
  X: Single;

  procedure Place(ABtn: TFluentButton);
  begin
    if (ABtn = nil) or not ABtn.Visible then
      Exit;
    X := X - ABtn.Width;
    ABtn.SetBounds(X, 4, ABtn.Width, 32);
    X := X - 8;
  end;

begin
  if FBtnCancel = nil then
    Exit;
  X := FBtnCancel.ParentControl.Width - 4;
  Place(FBtnCancel);
  Place(FBtnRetry);
  Place(FBtnEnd);
end;

procedure TFileLockForm.Reload;
var
  I: Integer;
  Row: TRectangle;
  Icon: TImage;
  Cap, Sub: TText;
  Bmp: FMX.Graphics.TBitmap;
  Y: Single;
begin
  FItems := QueryLockers(FPath);
  FSel := -1;
  if not FAsk then
  begin
    if Length(FItems) = 0 then
    begin
      FStatus.Text := L('lock.unknown');
      FStatus.Tag := 1;
    end
    else if FStatus.Tag = 1 then
    begin
      FStatus.Text := '';
      FStatus.Tag := 0;
    end;
  end;
  while FList.ChildrenCount > 0 do
    FList.Children[0].Free;
  SetLength(FRows, 0);
  Y := 0;
  for I := 0 to High(FItems) do
  begin
    Row := TRectangle.Create(Self);
    Row.Parent := FList;
    Row.Align := TAlignLayout.None;
    Row.SetBounds(0, Y, Max(200, FScroll.Width - 4), 44);
    Row.XRadius := 6;
    Row.YRadius := 6;
    Row.Stroke.Kind := TBrushKind.None;
    Row.Fill.Color := FColors.CardBackground;
    Row.HitTest := True;
    Row.Tag := I;
    Row.OnClick := RowClick;
    Icon := TImage.Create(Self);
    Icon.Parent := Row;
    Icon.HitTest := False;
    Icon.SetBounds(8, 8, 28, 28);
    Icon.WrapMode := TImageWrapMode.Fit;
    Bmp := nil;
    if FItems[I].Exe <> '' then
      GetFileIconBitmap(FItems[I].Exe, False, Bmp);
    if Bmp <> nil then
    begin
      Icon.Bitmap.Assign(Bmp);
      Bmp.Free;
    end;
    Cap := TText.Create(Self);
    Cap.Parent := Row;
    Cap.HitTest := False;
    Cap.SetBounds(44, 4, 280, 20);
    ApplyFluentText(Cap, 13, True);
    Cap.TextSettings.FontColor := FColors.TextColor;
    Cap.TextSettings.HorzAlign := TTextAlign.Leading;
    Cap.TextSettings.VertAlign := TTextAlign.Center;
    Cap.TextSettings.Trimming := TTextTrimming.Character;
    Cap.Text := FItems[I].Name + '   ' + IntToStr(FItems[I].Pid);
    Sub := TText.Create(Self);
    Sub.Parent := Row;
    Sub.HitTest := False;
    Sub.SetBounds(44, 22, 360, 18);
    ApplyFluentText(Sub, 12, False);
    Sub.TextSettings.FontColor := FColors.SubTextColor;
    Sub.TextSettings.HorzAlign := TTextAlign.Leading;
    Sub.TextSettings.VertAlign := TTextAlign.Center;
    Sub.TextSettings.Trimming := TTextTrimming.Character;
    if FItems[I].User <> '' then
      Sub.Text := FItems[I].User
    else
      Sub.Text := L('lock.nouser');
    SetLength(FRows, I + 1);
    FRows[I] := Row;
    Y := Y + 48;
  end;
  FList.Height := Max(48, Y);
  if (FSel < 0) and (Length(FItems) > 0) then
  begin
    FSel := 0;
    for I := 0 to High(FItems) do
      if FItems[I].CanEnd then
      begin
        FSel := I;
        Break;
      end;
  end;
  ApplyRowColors;
  SyncEndButton;
  LayoutButtons;
end;

procedure TFileLockForm.EndClick(Sender: TObject);
var
  At: Integer;
  Name: string;
begin
  At := Selected;
  if (At < 0) or not FItems[At].CanEnd then
    Exit;
  Name := FItems[At].Name;
  if not FAsk then
  begin
    FAsk := True;
    FStatus.Tag := 0;
    FStatus.Text := Lf('lock.confirm', [Name]);
    SyncEndButton;
    LayoutButtons;
    Exit;
  end;
  FAsk := False;
  if EndProcess(FItems[At].Pid) then
  begin
    FRetryPrimary := True;
    FStatus.Text := '';
    FStatus.Tag := 0;
    Sleep(200);
  end
  else
  begin
    FStatus.Text := L('lock.killfail');
    FStatus.Tag := 0;
  end;
  Reload;
end;

procedure TFileLockForm.BuildUI;
var
  Foot: TLayout;
begin
  FRoot := TRectangle.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Stroke.Kind := TBrushKind.None;
  FRoot.Fill.Color := FColors.Background;
  FRoot.Padding.Rect := TRectF.Create(16, 12, 16, 12);

  FNameText := TText.Create(Self);
  FNameText.Parent := FRoot;
  FNameText.Align := TAlignLayout.Top;
  FNameText.Height := 24;
  FNameText.HitTest := False;
  ApplyFluentText(FNameText, 16, True);
  FNameText.TextSettings.FontColor := FColors.TextColor;
  FNameText.TextSettings.HorzAlign := TTextAlign.Leading;
  FNameText.TextSettings.VertAlign := TTextAlign.Center;
  FNameText.TextSettings.Trimming := TTextTrimming.Character;
  FNameText.Text := ExtractFileName(ExcludeTrailingPathDelimiter(FPath));

  FPathText := TText.Create(Self);
  FPathText.Parent := FRoot;
  FPathText.Align := TAlignLayout.Top;
  FPathText.Height := 36;
  FPathText.HitTest := False;
  ApplyFluentText(FPathText, 12, False);
  FPathText.TextSettings.FontColor := FColors.SubTextColor;
  FPathText.TextSettings.HorzAlign := TTextAlign.Leading;
  FPathText.TextSettings.VertAlign := TTextAlign.Leading;
  FPathText.TextSettings.Trimming := TTextTrimming.Character;
  FPathText.TextSettings.WordWrap := True;
  FPathText.Text := FPath;

  FStatus := TText.Create(Self);
  FStatus.Parent := FRoot;
  FStatus.Align := TAlignLayout.Top;
  FStatus.Height := 36;
  FStatus.HitTest := False;
  ApplyFluentText(FStatus, 13, False);
  FStatus.TextSettings.FontColor := FColors.TextColor;
  FStatus.TextSettings.HorzAlign := TTextAlign.Leading;
  FStatus.TextSettings.VertAlign := TTextAlign.Leading;
  FStatus.TextSettings.WordWrap := True;

  FScroll := TVertScrollBox.Create(Self);
  FScroll.Parent := FRoot;
  FScroll.Align := TAlignLayout.Client;
  FScroll.Margins.Rect := TRectF.Create(0, 8, 0, 8);
  FList := TLayout.Create(Self);
  FList.Parent := FScroll;
  FList.Align := TAlignLayout.Top;
  FList.Height := 48;

  Foot := TLayout.Create(Self);
  Foot.Parent := FRoot;
  Foot.Align := TAlignLayout.Bottom;
  Foot.Height := 40;
  FBtnEnd := CreateFluentButton(Self, Foot, '', L('lock.end'), fbkStandard, 168, EndClick);
  FBtnRetry := CreateFluentButton(Self, Foot, '', L('lock.retry'), fbkStandard, 120, RetryClick);
  FBtnCancel := CreateFluentButton(Self, Foot, '', L('lock.cancel'), fbkSubtle, 110, CancelClick);
  FBtnEnd.Align := TAlignLayout.None;
  FBtnRetry.Align := TAlignLayout.None;
  FBtnCancel.Align := TAlignLayout.None;
end;

procedure ShowFileLock(const APath: string; var AChoice: TFileLockChoice);
var
  Dlg: TFileLockForm;
begin
  AChoice := flcCancel;
  if (Application = nil) or (Application.MainForm = nil) or
     (csDestroying in Application.MainForm.ComponentState) then
  begin
    GHalt := True;
    Exit;
  end;
  Dlg := TFileLockForm.Create(Application.MainForm, APath);
  try
    Dlg.Show;
    while not Dlg.Finished do
    begin
      Application.ProcessMessages;
      if (Application = nil) or Application.Terminated then
      begin
        AChoice := flcCancel;
        GHalt := True;
        Exit;
      end;
      Sleep(15);
    end;
    AChoice := Dlg.Choice;
    GHalt := AChoice = flcCancel;
  finally
    Dlg.Free;
  end;
end;

function FileLockOffer(const APath: string; ACode: Cardinal): TFileLockChoice;
var
  Choice: TFileLockChoice;
  Path: string;
begin
  if not SharingCode(ACode) or not LockPathOk(APath) then
    Exit(flcPass);
  Path := APath;
  Choice := flcCancel;
  if TThread.CurrentThread.ThreadID = MainThreadID then
    ShowFileLock(Path, Choice)
  else
    TThread.Synchronize(nil,
      procedure
      begin
        ShowFileLock(Path, Choice);
      end);
  Result := Choice;
end;

end.
