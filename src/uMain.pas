unit uMain;

interface

uses
Winapi.Windows, Winapi.Messages, Winapi.DwmApi, Winapi.UxTheme,
  Winapi.ShlObj, System.Win.ComObj, FMX.Platform.Win,
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils, System.Types,
  System.Generics.Collections,
  FMX.Forms, FMX.Types, FMX.Layouts, FMX.StdCtrls, FMX.Objects,
  FMX.Controls, FMX.ListBox, FMX.Graphics, FMX.Dialogs, System.Math,
  FMX.TextLayout, FMX.Effects,
  FileSelectionManager,

  uAppSettings, uLang, uThemeManager, uFluentChrome, uFluentEdit, uFluentComboBox,
  uFilePanel, uThumbCache,
  uIconCache, uMetaCache, uFolderSize,
  uQuickViewForm, uLaunchDock,
  uSettingsForm, uFileOps, uFileOpEngine, uFileModel, UCoreEngine, uMultiRenameForm, uSearchForm
  , uWinBrowserDrop;

type
  TMainForm = class(TForm)
  private
    FSettings: TAppSettings;
    FColors: TThemeColors;

    FTopStack: TLayout;
    FTitleBar: TRectangle;
    FTitleLine: TRectangle;
    FDock: TLaunchDock;
    FAppIcon: TImage;
    FLogoV: TText;
    FLogoBang: TText;
    FTitleText: TText;
    FSubtitleText: TText;
    FCaptionBar: TLayout;
    FQuickSearch: TFluentComboBox;
    FSearchHist: TStringList;
    FSearchDebounce: TTimer;
    FBtnSettings: TRectangle;
    FBtnMin: TRectangle;
    FBtnMax: TRectangle;
    FBtnClose: TRectangle;

    FMidBar: TRectangle;
    FMidGroup: TLayout;
    FCmdQuickView: TFluentButton;
    FCmdCopy: TFluentButton;
    FCmdMove: TFluentButton;
    FCmdDelete: TFluentButton;
    FCmdNewFolder: TFluentButton;
    FCmdRename: TFluentButton;
    FCmdArchive: TFluentButton;
    FCmdSearch: TFluentButton;
    FSearchForm: TSearchForm;
    FCmdRefresh: TFluentButton;
    FCmdDetails: TFluentButton;
    FCmdTiles: TFluentButton;
    FCmdSelect: TFluentButton;
    FSelMenu: TFluentPopupMenu;
    FLastSelectMask: string;
    FOpPill: TRectangle;
    FOpPillIcon: TText;
    FOpPillText: TText;
    FOpPillArc: TPaintBox;
    FOpPop: TPopup;
    FOpHost: TRectangle;
    FOpBody: TLayout;
    FOpRows: TObjectList<TObject>;
    FOpTimer: TTimer;
    FOpScrollY: Single;
    FOpViewH: Single;
    FMidStackH: Single;
    FOpPillTop: Single;

    FFnBar: TRectangle;
    FFnCells: array[0..6] of TLayout;
    FFnButtons: array[0..6] of TFluentButton;
    FCmdBar: TLayout;
    FCmdBack: TRectangle;
    FCmdTopLine: TRectangle;
    FCmdIcon: TText;
    FCmdPath: TText;
    FCmdSplit: TRectangle;
    FCmdEdit: TFluentEdit;
    FCmdHist: TStringList;
    FCmdHistPos: Integer;
    FCmdDraft: string;
    FCmdPrompt: string;

    FWorkArea: TLayout;
    FCenterCluster: TLayout;
    FLeftPanel: TFilePanel;
    FRightPanel: TFilePanel;
    FSplitterL: TRectangle;
    FSplitterR: TRectangle;
    FSplitGripL: TRectangle;
    FSplitGripR: TRectangle;
    FSplitDragging: Boolean;
    FSplitStartX: Single;
    FSplitStartLeftW: Single;

    FActivePanel: TFilePanel;
    FQuickView: TQuickViewForm;
    FLeftPanelRatio: Single;
    FChromeWatch: TSystemChromeWatcher;
    FFrameHooked: Boolean;
    FOldWndProc: Pointer;
    FPendingMaximized: Boolean;
    FCenterAtShow: Boolean;
    FCenterOnRestore: Boolean;
    FStartupDone: Boolean;
    FFading: Boolean;
    FStartupPhase: Integer;
    FFirstPaintLogged: Boolean;
    FLeftReady: Boolean;
    FRightReady: Boolean;
    FSessionTimer: TTimer;
    FSessionDirty: Boolean;
    FSessionSnap: Boolean;
    FSessionSaved: Boolean;
    FFadeTimer: TTimer;
    FStartupTimer: TTimer;
    FIdlePlusTimer: TTimer;
    FStaleTimer: TTimer;
    FPreviewDebounce: TTimer;
    FPreviewPending: string;
    FPreviewWindowPending: string;
    FFadeStart: UInt64;
    FLastHistNavTick: UInt64;

    procedure BuildTitleBar;
    procedure LayoutQuickSearch;
    procedure UsePanel(APanel: TFilePanel; AFocus: Boolean);
    procedure SearchChanged(Sender: TObject);
    procedure SearchDebounceTick(Sender: TObject);
    procedure SearchSubmit(Sender: TObject);
    procedure SearchSelected(Sender: TObject);
    procedure SearchEscape(Sender: TObject);
    procedure SearchDrop(Sender: TObject);
    procedure SearchClearHistory(Sender: TObject);
    procedure RememberSearch(const AText: string);
    procedure BuildDock;
    procedure BuildMidBar;
    procedure BuildFunctionBar;
    procedure BuildCommandLine;
    procedure CmdBarResize(Sender: TObject);
    procedure LayoutCmdBar;
    procedure SyncCmdPath;
    procedure BuildWorkArea;
    procedure LayoutFunctionBar;
    procedure LayoutWorkArea;
    procedure ApplyLeftPanelWidth(AWidth: Single);
    function CenterBandWidth: Single;
    procedure ApplyCenterBandLayout;
    procedure BuildOpPill;
    procedure LayoutMidButtons;
    procedure LayoutOpPill;
    function OpPillOnRail: Boolean;
    procedure ParkOpPill;
    procedure RefreshOpUi;
    procedure OpHubChanged(Sender: TObject);
    procedure OpTick(Sender: TObject);
    procedure OpPillClick(Sender: TObject);
    procedure OpPillPaint(Sender: TObject; Canvas: TCanvas);
    procedure ToggleOpPop;
    procedure OpenOpPop;
    procedure SyncOpRows;
    procedure OpRowClick(Sender: TObject);
    procedure OpRowCloseClick(Sender: TObject);
    procedure OpRowEnter(Sender: TObject);
    procedure OpRowLeave(Sender: TObject);
    procedure OpWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean);
    function OpenBackgroundKind(AKind: TFileOpKind): Boolean;
    function MakeMidButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TFluentButton;
    function MakeSideSplitter(AAlign: TAlignLayout): TRectangle;

    procedure OnSettingsClick(Sender: TObject);
    procedure OnMinClick(Sender: TObject);
    procedure OnMaxClick(Sender: TObject);
    procedure OnCloseClick(Sender: TObject);
    procedure WinBtnEnter(Sender: TObject);
    procedure WinBtnLeave(Sender: TObject);
    function MakeWinBtn(AParent: TFmxObject; const AGlyph: string;
      AOnClick: TNotifyEvent): TRectangle;
    procedure LoadTitleIcon;
    procedure ApplyCustomFrame;
    procedure HideFmxAppWindow;
    procedure UpdateWindowButtons;
    function WindowAnimEnabled: Boolean;
    function CaptionHitTest(const AFormPt: TPointF): NativeInt;
    function IsWindowMaximized: Boolean;
    function CurrentWorkArea: TRectF;
    procedure CaptureNormalGeometry;
    procedure ApplyStartupGeometry;
    function CalcMinWindowHeight: Integer;
    procedure ApplyMinWindowHeight;
    function NativeScale: Single;
    procedure ApplyNativeWindowRect;
    procedure ApplySavedWindowRect;
    procedure CenterNormalWindow;
    procedure PersistWindowState;
    procedure NativeSysCommand(ACmd: NativeUInt);
    procedure StartStartupFade;
    procedure FadeTick(Sender: TObject);
    procedure FinishStartupFade;
    procedure KickFolderSizes;
    procedure MarkSessionDirty;
    procedure SnapshotSession;
    procedure SessionTimerTick(Sender: TObject);
    procedure StartupIdleTick(Sender: TObject);
    procedure StartupIdlePlusTick(Sender: TObject);
    procedure StartupStaleTick(Sender: TObject);
    procedure LeftListReady(Sender: TObject);
    procedure RightListReady(Sender: TObject);
    procedure StyleLogoText(AText: TText; ASize: Single; ABold: Boolean);
    procedure OnBtnCopyClick(Sender: TObject);
    procedure OnBtnMoveClick(Sender: TObject);
    procedure RunCopyMove(const ASources: TArray<string>; const ADestDir: string;
      AMove: Boolean; ASrcPanel, ADestPanel: TFilePanel);
    procedure PanelDropCopyMove(Sender: TObject; const ADest: string;
      const ASources: TArray<string>; AMove: Boolean; ASourcePanel: TFilePanel);
    procedure DockCopyToFolder(Sender: TObject; const ADest: string;
      const AFiles: TArray<string>);
    function PanelForPaths(const APaths: TArray<string>): TFilePanel;
    procedure OnBtnDeleteClick(Sender: TObject);
    procedure OnBtnNewFolderClick(Sender: TObject);
    procedure OnBtnRefreshClick(Sender: TObject);
    procedure OnBtnViewDetailsClick(Sender: TObject);
    procedure OnBtnViewTilesClick(Sender: TObject);
    procedure OnBtnViewClick(Sender: TObject);
    procedure OnBtnQuickViewToggle(Sender: TObject);
    procedure OnBtnOpenClick(Sender: TObject);
    procedure OnBtnRenameClick(Sender: TObject);
    procedure ShowMultiRename;
    procedure OnBtnArchiveClick(Sender: TObject);
    procedure OnBtnSearchClick(Sender: TObject);
    procedure OnBtnSelectClick(Sender: TObject);
    procedure OnSelAll(Sender: TObject);
    procedure OnSelNone(Sender: TObject);
    procedure OnSelInvert(Sender: TObject);
    procedure OnSelMask(Sender: TObject);
    procedure OnUnselMask(Sender: TObject);
    procedure OnSelExt(Sender: TObject);
    procedure OnUnselExt(Sender: TObject);
    procedure OnSelFiles(Sender: TObject);
    procedure OnSelFolders(Sender: TObject);
    procedure OnSelCompare(Sender: TObject);
    procedure OnSelModeExplorer(Sender: TObject);
    procedure OnSelModeVibe(Sender: TObject);
    procedure SetMouseSelectMode(AExplorer: Boolean);
    procedure PanelMouseModePick(Sender: TObject; AExplorer: Boolean);
    procedure BuildSelMenu;
    procedure AskSelectMask(ASelect: Boolean);
    procedure ShowSearch;
    procedure SearchFormClosed(Sender: TObject; var Action: TCloseAction);
    procedure SearchStateChanged(Sender: TObject);
    procedure HistoryShortcut(ADelta: Integer; AFromMouse: Boolean = False);
    function PanelAtCursor: TFilePanel;
    procedure CloseDriveHomes;
    procedure PanelActivate(Sender: TObject);

    procedure LeftPanelPathChanged(Sender: TObject; const APath: string);
    procedure RightPanelPathChanged(Sender: TObject; const APath: string);

    procedure PanelQuickView(Sender: TObject; const APath: string);
    procedure PanelCursorChanged(Sender: TObject);
    procedure PreviewDebounceTick(Sender: TObject);
    procedure ArmPreviewDebounce;
    function QuickViewFollows: Boolean;
    procedure FollowQuickViewWindow(const APath: string);
    procedure FollowActivePanelPreview;
    procedure CloseColumnQuickView;
    procedure ApplyPanelView(APanel: TFilePanel; AMode: TPanelViewMode);
    procedure PanelStatusView(Sender: TObject; AMode: TPanelViewMode);
    procedure TogglePanelQuickView;
    procedure ShowQuickViewWindow(const APath: string);
    procedure ShowQuickViewForPath(const APath: string);
    function PreviewWantsKeys: Boolean;

    procedure ApplyLanguage;
    procedure ApplyThemeToAll(const AColors: TThemeColors);
    procedure ApplyWindowBackground;
    procedure ApplyBandLayout;
    procedure ApplyPanelSettings;
    procedure ApplyDriveOptions;
    procedure ApplySessionBehavior;
    procedure CmdLineSubmit(Sender: TObject);
    procedure CmdLineCancel(Sender: TObject);
    procedure CmdHistStep(ADelta: Integer);
    procedure RememberCmd(const ACmd: string);
    function CmdLineFocused: Boolean;
    function TryCmdLineDrop(const AScreen: TPointF; const APaths: TArray<string>): Boolean;
    procedure InsertCmdDrop(const APaths: TArray<string>);
    procedure OnThemeChangedFromSettings(NewTheme: TAppTheme);
    procedure HandleSystemChromeChanged;
    procedure UpdateViewButtons;

    function OtherPanel(APanel: TFilePanel): TFilePanel;

    procedure SplitterMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure SplitterMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure SplitterMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure SplitterMouseEnter(Sender: TObject);
    procedure SplitterMouseLeave(Sender: TObject);
    procedure WorkAreaResize(Sender: TObject);
    procedure FormResizeHandler(Sender: TObject);
    procedure DockOpenFolder(Sender: TObject; const APath: string);
    procedure DockGoToObject(Sender: TObject; const APath: string);
    procedure DockStatus(Sender: TObject; const AText: string);
    procedure DockChanged(Sender: TObject);

  protected
    procedure CreateHandle; override;
    procedure DestroyHandle; override;
    procedure DoShow; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;
  GHookForm: TMainForm;

procedure NoteAppStart;
function TryActivateRunningInstance: Boolean;
procedure StartupLog(const AStage: string);

implementation

uses
  Winapi.MultiMon,
  System.Win.Registry, System.IniFiles,
  FMX.Platform,
  uFileOpProgressForm, uDriveBar;

const
  APP_MUTEX_NAME = 'Local\VibeCmd.SingleInstance';
  APP_WND_PROP = 'VibeCmdMain';
  TITLEBAR_HEIGHT = 40;
  CAPTION_BTN_W = 47;
  APP_VERSION_FALLBACK = '1.0.0';
  VIBE_NEON = $FF00D4FF;
  VIBE_MONO_FONT = 'Cascadia Mono';
  ICON_CHROME_MIN = #$E921;
  ICON_CHROME_MAX = #$E922;
  ICON_CHROME_RESTORE = #$E923;
  ICON_CHROME_CLOSE = #$E8BB;
  ICON_CHROME_SETTINGS = #$E713;
  FNBAR_HEIGHT = 42;
  CMDLINE_HEIGHT = 36;
  CMD_HIST_MAX = 24;
  CMD_PROMPT_ICON = #$E756;
  MIDBAR_WIDTH = 40;
  OP_PILL_H = 32;
  SPLITTER_WIDTH = 4;
  CENTER_CLUSTER_WIDTH = SPLITTER_WIDTH + MIDBAR_WIDTH + SPLITTER_WIDTH;
  MIN_PANEL_WIDTH = 180;
  WORK_PAD_L = 8;
  WORK_PAD_T = 6;
  WORK_PAD_R = 8;
  WORK_PAD_B = 4;

  MIDBAR_TOP = 38;
  MIDBAR_BOTTOM = 8;
  MID_BTN_Y0 = 4;
  MIN_WINDOW_SLACK = 8;
  MIN_WINDOW_FLOOR = 480;
  MIN_WINDOW_HEIGHT = 700;

var
  GAppStartTick: UInt64;
{$IFDEF MSWINDOWS}
  GAppMutex: THandle;
  GFoundWnd: Winapi.Windows.HWND;
{$ENDIF}

procedure StartupLog(const AStage: string);
begin
  {$IFDEF MSWINDOWS}
  if GAppStartTick = 0 then
    GAppStartTick := GetTickCount64;
  OutputDebugString(PChar(Format('VIBE %4d ms  %s',
    [GetTickCount64 - GAppStartTick, AStage])));
  {$ENDIF}
end;

procedure NoteAppStart;
begin
  {$IFDEF MSWINDOWS}
  GAppStartTick := GetTickCount64;
  OutputDebugString(PChar('VIBE    0 ms  process'));
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
function EnumVibeWnd(Wnd: Winapi.Windows.HWND; Data: LPARAM): BOOL; stdcall;
begin
  if GetProp(Wnd, PChar(APP_WND_PROP)) <> 0 then
  begin
    GFoundWnd := Wnd;
    Result := False;
  end
  else
    Result := True;
end;
{$ENDIF}

function TryActivateRunningInstance: Boolean;
{$IFDEF MSWINDOWS}
var
  Wnd: Winapi.Windows.HWND;
  Pid: DWORD;
  Started: UInt64;
  Held: THandle;
begin
  Result := False;
  if not SingleInstanceWanted then
    Exit;
  Started := GetTickCount64;
  while True do
  begin
    Held := CreateMutex(nil, True, APP_MUTEX_NAME);
    if Held = 0 then
      Exit;
    if GetLastError <> ERROR_ALREADY_EXISTS then
    begin
      GAppMutex := Held;
      Exit;
    end;
    { Чужой хэндл не держим: иначе мьютекс живёт, пока мы ждём. }
    CloseHandle(Held);
    GFoundWnd := 0;
    Winapi.Windows.EnumWindows(@EnumVibeWnd, 0);
    if GFoundWnd = 0 then
      GFoundWnd := Winapi.Windows.FindWindow(nil, PChar('V!BE CMD'));
    Wnd := GFoundWnd;
    if (Wnd <> 0) and IsWindowVisible(Wnd) then
    begin
      GetWindowThreadProcessId(Wnd, Pid);
      if Pid <> 0 then
        AllowSetForegroundWindow(Pid);
      if IsIconic(Wnd) then
        Winapi.Windows.ShowWindow(Wnd, SW_RESTORE)
      else
        Winapi.Windows.ShowWindow(Wnd, SW_SHOW);
      SetForegroundWindow(Wnd);
      BringWindowToTop(Wnd);
      Result := True;
      Exit;
    end;
    if GetTickCount64 - Started >= 300 then
    begin
      with TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'VibeSetting.ini') do
      try
        SetLanguage(ReadString('Main', 'Language', 'system'));
      finally
        Free;
      end;
      MessageBox(0, PChar(L('main.stillclosing')),
        'V!BE CMD', MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND);
      Result := True;
      Exit;
    end;
    Sleep(40);
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  StartupLog('Create');
  Caption := 'V!BE CMD';
  BorderStyle := TFmxFormBorderStyle.Sizeable;
  BorderIcons := [TBorderIcon.biSystemMenu, TBorderIcon.biMinimize, TBorderIcon.biMaximize];
  Visible := False;

  FSettings := TAppSettings.Create;
  FSettings.Load;
  SetLanguage(FSettings.Language);
  ConfigureThemeTint(FSettings.ColorTint, FSettings.WindowMaterial);
  SeedDockIfNeeded(FSettings);
  SetActiveAppTheme(FSettings.Theme);
  SetFileOpMode(FSettings.FileOpMode);

  Constraints.MinHeight := MIN_WINDOW_FLOOR;
  Constraints.MaxHeight := 0;
  ApplyStartupGeometry;

  FLeftPanelRatio := FSettings.SplitterPos;
  if FLeftPanelRatio <= 0 then FLeftPanelRatio := 0.5;

  FColors := GetThemeColors(FSettings.Theme);
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := FColors.Background;

  BuildTitleBar;
  BuildDock;
  BuildFunctionBar;
  BuildCommandLine;
  BuildWorkArea;

  OnResize := FormResizeHandler;

  if FSettings.ActivePanel = 1 then
    FActivePanel := FRightPanel
  else
    FActivePanel := FLeftPanel;

  if Assigned(FLeftPanel) then
    FLeftPanel.OnListReady := LeftListReady;
  if Assigned(FRightPanel) then
    FRightPanel.OnListReady := RightListReady;

  ApplyThemeToAll(FColors);
  ApplyDriveOptions;
  FFadeTimer := TTimer.Create(Self);
  FFadeTimer.Interval := 16;
  FFadeTimer.Enabled := False;
  FFadeTimer.OnTimer := FadeTick;
  FStartupTimer := TTimer.Create(Self);
  FStartupTimer.Interval := 1;
  FStartupTimer.Enabled := False;
  FStartupTimer.OnTimer := StartupIdleTick;
  FIdlePlusTimer := TTimer.Create(Self);
  FIdlePlusTimer.Interval := 500;
  FIdlePlusTimer.Enabled := False;
  FIdlePlusTimer.OnTimer := StartupIdlePlusTick;
  FStaleTimer := TTimer.Create(Self);
  FStaleTimer.Interval := 80;
  FStaleTimer.Enabled := False;
  FStaleTimer.OnTimer := StartupStaleTick;
  FSessionTimer := TTimer.Create(Self);
  FSessionTimer.Interval := 1200;
  FSessionTimer.Enabled := False;
  FSessionTimer.OnTimer := SessionTimerTick;
  FQuickView := nil;
  FChromeWatch := nil;
  SetFileOpHubChanged(OpHubChanged);
  if Assigned(FOpTimer) then
    FOpTimer.Enabled := True;
end;

destructor TMainForm.Destroy;
begin
  SetFileOpHubChanged(nil);
  if Assigned(FOpTimer) then
    FOpTimer.Enabled := False;
  FreeAndNil(FOpRows);
  CancelListFileOps;
  if Assigned(FSearchForm) then
  begin
    FSearchForm.OnClose := nil;
    FSearchForm.OnGoToHit := nil;
    FSearchForm.OnFeedToPanel := nil;
    FSearchForm.OnStateChange := nil;
    FreeAndNil(FSearchForm);
  end;
  FreeAndNil(FChromeWatch);

  if Assigned(FSettings) then
  begin
    if not FSessionSaved then
    begin
      if FSessionDirty or not FSessionSnap then
        SnapshotSession;
      try
        FSettings.SaveSession;
      except
      end;
    end;
    FreeAndNil(FSettings);
  end;
  if Assigned(FSearchDebounce) then
    FSearchDebounce.Enabled := False;
  FreeAndNil(FSearchHist);
  FreeAndNil(FCmdHist);

  { Флаг стоп и сброс очереди. Потоки не ждём. }
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.Shutdown;
  if Assigned(GlobalIconCache) then
    GlobalIconCache.Shutdown;
  if Assigned(GlobalMetaCache) then
    GlobalMetaCache.Shutdown;
  if Assigned(GlobalFolderSizes) then
    GlobalFolderSizes.Shutdown;

  if Assigned(FQuickView) then FQuickView.Free;
  {$IFDEF MSWINDOWS}
  if FFrameHooked and (FOldWndProc <> nil) then
  begin
    SetWindowLongPtr(FormToHWND(Self), GWL_WNDPROC, NativeInt(FOldWndProc));
    FFrameHooked := False;
    FOldWndProc := nil;
  end;
  GHookForm := nil;
  UninstallFormDropTarget(Self);
  {$ENDIF}
  inherited;
end;

procedure TMainForm.CreateHandle;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  Ex: NativeInt;
{$ENDIF}
begin
  inherited;
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    SetProp(Wnd, PChar(APP_WND_PROP), 1);
    SetFileOpOwnerWnd(Wnd);
    ShowWindow(Wnd, SW_HIDE);
    Ex := GetWindowLong(Wnd, GWL_EXSTYLE) or WS_EX_LAYERED;
    SetWindowLong(Wnd, GWL_EXSTYLE, Ex);
    SetLayeredWindowAttributes(Wnd, 0, 0, LWA_ALPHA);
    if FColors.IsDark then
      SetClassLongPtr(Wnd, -10, NativeInt(GetStockObject(BLACK_BRUSH)))
    else
      SetClassLongPtr(Wnd, -10, NativeInt(GetStockObject(LTGRAY_BRUSH)));
  end;
  {$ENDIF}
  ApplyCustomFrame;
  {$IFDEF MSWINDOWS}
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  InstallFormDropTarget(Self);
  {$ENDIF}
  ApplyMinWindowHeight;
  StartupLog('Handle');
end;

procedure TMainForm.DestroyHandle;
begin
  {$IFDEF MSWINDOWS}
  UninstallFormDropTarget(Self);
  {$ENDIF}
  inherited;
end;

procedure TMainForm.DoShow;
begin
  {$IFDEF MSWINDOWS}
  if FormToHWND(Self) <> 0 then
  begin
    SetWindowLong(FormToHWND(Self), GWL_EXSTYLE,
      GetWindowLong(FormToHWND(Self), GWL_EXSTYLE) or WS_EX_LAYERED);
    SetLayeredWindowAttributes(FormToHWND(Self), 0, 0, LWA_ALPHA);
  end;
  {$ENDIF}
  inherited;
  { Тема, полосы и раскладка уже стоят с конструктора. Здесь только альфа и fade. }
  UpdateViewButtons;
  if not FStartupDone then
    StartStartupFade;
  StartupLog('DoShow');
  if Assigned(FStartupTimer) and (FStartupPhase < 2) then
  begin
    FStartupPhase := 1;
    FStartupTimer.Enabled := True;
  end;
end;

procedure TMainForm.DoClose(var CloseAction: TCloseAction);
begin
  if Assigned(FSessionTimer) then
    FSessionTimer.Enabled := False;
  if FSessionDirty or not FSessionSnap then
    SnapshotSession
  else
    PersistWindowState;
  try
    Visible := False;
{$IFDEF MSWINDOWS}
    if FormToHWND(Self) <> 0 then
      ShowWindow(FormToHWND(Self), SW_HIDE);
    if GAppMutex <> 0 then
    begin
      CloseHandle(GAppMutex);
      GAppMutex := 0;
    end;
{$ENDIF}
  except
  end;
  Application.Terminate;
  CancelListFileOps;
  DismissFileOpProgress;
  if Assigned(FLeftPanel) then
    FLeftPanel.CancelPendingIO;
  if Assigned(FRightPanel) then
    FRightPanel.CancelPendingIO;
  try
    if Assigned(FSettings) then
      FSettings.SaveSession;
  except
  end;
  FSessionSaved := True;
  inherited;
end;

function ReadAppVersion: string;
{$IFDEF MSWINDOWS}
var
  Dummy, Sz: DWORD;
  Buf: Pointer;
  Info: PVSFixedFileInfo;
  Len: UINT;
{$ENDIF}
begin
  Result := APP_VERSION_FALLBACK;
  {$IFDEF MSWINDOWS}
  Sz := GetFileVersionInfoSize(PChar(ParamStr(0)), Dummy);
  if Sz = 0 then
    Exit;
  GetMem(Buf, Sz);
  try
    if GetFileVersionInfo(PChar(ParamStr(0)), 0, Sz, Buf) and
       VerQueryValue(Buf, '\', Pointer(Info), Len) and Assigned(Info) then
      Result := Format('%d.%d.%d', [HiWord(Info.dwFileVersionMS),
        LoWord(Info.dwFileVersionMS), HiWord(Info.dwFileVersionLS)]);
  finally
    FreeMem(Buf);
  end;
  {$ENDIF}
end;

procedure TMainForm.StyleLogoText(AText: TText; ASize: Single; ABold: Boolean);
begin
  AText.TextSettings.Font.Family := VIBE_MONO_FONT;
  AText.TextSettings.Font.Size := ASize;
  if ABold then
    AText.TextSettings.Font.Style := [TFontStyle.fsBold]
  else
    AText.TextSettings.Font.Style := [];
  AText.TextSettings.HorzAlign := TTextAlign.Leading;
  AText.HitTest := False;
  AText.WordWrap := False;
end;

function TMainForm.MakeWinBtn(AParent: TFmxObject; const AGlyph: string;
  AOnClick: TNotifyEvent): TRectangle;
var
  Glyph: TText;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Right;
  Result.Width := CAPTION_BTN_W;
  Result.Stroke.Kind := TBrushKind.None;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.Fill.Color := TAlphaColors.Null;
  Result.XRadius := 0;
  Result.YRadius := 0;
  Result.HitTest := True;
  Result.Cursor := crHandPoint;
  Result.OnClick := AOnClick;
  Result.OnMouseEnter := WinBtnEnter;
  Result.OnMouseLeave := WinBtnLeave;
  Glyph := TText.Create(Self);
  Glyph.Parent := Result;
  Glyph.Align := TAlignLayout.Client;
  Glyph.HitTest := False;
  Glyph.Text := AGlyph;
  Glyph.Font.Family := FluentIconFamily;
  Glyph.Font.Size := 10;
  Glyph.TextSettings.HorzAlign := TTextAlign.Center;
  Glyph.TextSettings.VertAlign := TTextAlign.Center;
  Result.TagObject := Glyph;
  Result.Margins.Top := -10;
  Result.Margins.Left := 0;
end;

procedure TMainForm.LoadTitleIcon;
var
  Bmp: FMX.Graphics.TBitmap;
begin
  if FAppIcon = nil then
    Exit;
  Bmp := nil;
  try
    GetAppIconBitmap(Bmp, 32);
    if Assigned(Bmp) and (Bmp.Width > 0) then
      FAppIcon.Bitmap.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

function AlphaToColorRef(C: TAlphaColor): COLORREF;
var
  R: TAlphaColorRec;
begin
  R.Color := C;
  Result := R.R or (R.G shl 8) or (R.B shl 16);
end;

function FrameWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
const
  XBTN_BACK = 1;
  XBTN_FORWARD = 2;
  FAPPCOMMAND_MOUSE = $8000;
  FAPPCOMMAND_MASK  = $F000;
  WM_REFRESH_FOCUS = WM_USER + 101;
var
  Params: PNCCalcSizeParams;
  Frame: Integer;
  PT: TPoint;
  FormPt: TPointF;
  Scale: Single;
  Hit: NativeInt;
  Cmd: NativeUInt;
  NavDelta: Integer;
  XBtn: Word;
  KeyState: TKeyboardState;
begin
  if (GHookForm = nil) or (GHookForm.FOldWndProc = nil) then
    Exit(DefWindowProc(hWnd, Msg, wParam, lParam));

  case Msg of

   WM_CLOSE:
  begin
    TThread.ForceQueue(nil,
      procedure
      begin
        if GHookForm <> nil then
          GHookForm.Close
        else
          Application.Terminate;
      end);
    Exit(0);
  end;

  WM_REFRESH_FOCUS:
    begin
      // 1. Сбрасываем системные очереди Windows
      SendMessage(hWnd, WM_CANCELMODE, 0, 0);

      // 2. ГРУБАЯ СИЛА: Обнуляем состояние клавиши Alt (VK_MENU) в памяти потока
      // Это лечит "инвертированный Альт", когда FMX думает, что кнопка зажата.
      GetKeyboardState(KeyState);
      KeyState[VK_MENU] := 0;  // Снимаем флаг нажатия
      KeyState[VK_LMENU] := 0;
      KeyState[VK_RMENU] := 0;
      SetKeyboardState(KeyState); // Записываем обратно

      // 3. Программный "клик" альта для синхронизации очереди
      keybd_event(VK_MENU, $38, KEYEVENTF_KEYUP, 0);

      // 4. Возвращаем фокус
      Winapi.Windows.SetFocus(hWnd);
      if GHookForm.FActivePanel <> nil then
        GHookForm.FActivePanel.SetFocus;

      Exit(0);
    end;


     WM_ACTIVATE:
    begin
      if LoWord(wParam) = WA_INACTIVE then
      begin
        if (GetForegroundWindow <> 0) and
           (GetAncestor(GetForegroundWindow, GA_ROOT) <> hWnd) and
           Assigned(GHookForm) then
          GHookForm.CloseDriveHomes;
      end
      else
      begin
        // Как только окно активировалось, сбрасываем системные флаги
      //  SendMessage(hWnd, WM_CANCELMODE, 0, 0);
        PostMessage(hWnd, WM_REFRESH_FOCUS, 0, 0);
      end;
    end;



    WM_SYSKEYDOWN:
      if wParam = VK_F5 then
      begin
        TThread.ForceQueue(nil,
          procedure
          begin
            if Assigned(GHookForm) then
              GHookForm.OnBtnArchiveClick(nil);
          end);
        Exit(0);
      end
      else if wParam = VK_F7 then
      begin
        TThread.ForceQueue(nil,
          procedure
          begin
            if Assigned(GHookForm) then
              GHookForm.OnBtnSearchClick(nil);
          end);
        Exit(0);
      end
      else if (wParam = VK_F1) and (GetKeyState(VK_CONTROL) >= 0) and
              Assigned(GHookForm) and Assigned(GHookForm.FLeftPanel) and
              GHookForm.FLeftPanel.DriveHomeEnabled then
      begin
        TThread.ForceQueue(nil,
          procedure
          begin
            if Assigned(GHookForm) and Assigned(GHookForm.FLeftPanel) then
              GHookForm.FLeftPanel.ToggleDriveHome;
          end);
        Exit(0);
      end
      else if (wParam = VK_F2) and (GetKeyState(VK_CONTROL) >= 0) and
              Assigned(GHookForm) and Assigned(GHookForm.FRightPanel) and
              GHookForm.FRightPanel.DriveHomeEnabled then
      begin
        TThread.ForceQueue(nil,
          procedure
          begin
            if Assigned(GHookForm) and Assigned(GHookForm.FRightPanel) then
              GHookForm.FRightPanel.ToggleDriveHome;
          end);
        Exit(0);
      end
      else if (wParam = VK_LEFT) or (wParam = VK_RIGHT) then
      begin
        if wParam = VK_LEFT then
          NavDelta := -1
        else
          NavDelta := 1;
        TThread.ForceQueue(nil,
          procedure
          begin
            if Assigned(GHookForm) then
              GHookForm.HistoryShortcut(NavDelta);
          end);
        Exit(0);
      end;


    WM_XBUTTONDOWN, WM_XBUTTONDBLCLK, WM_NCXBUTTONDOWN, WM_NCXBUTTONDBLCLK:
      begin
        XBtn := HiWord(NativeUInt(wParam));
        if (XBtn = XBTN_BACK) or (XBtn = XBTN_FORWARD) then
        begin
          if (Msg = WM_XBUTTONDOWN) or (Msg = WM_NCXBUTTONDOWN) then
          begin
            if XBtn = XBTN_BACK then
              NavDelta := -1
            else
              NavDelta := 1;
            TThread.ForceQueue(nil,
              procedure
              begin
                if Assigned(GHookForm) then
                  GHookForm.HistoryShortcut(NavDelta, True);
              end);
          end;
          Exit(1);
        end;
      end;
    WM_XBUTTONUP, WM_NCXBUTTONUP:
      begin
        XBtn := HiWord(NativeUInt(wParam));
        if (XBtn = XBTN_BACK) or (XBtn = XBTN_FORWARD) then
          Exit(1);
      end;
    WM_APPCOMMAND:
      begin
        Cmd := HiWord(NativeUInt(lParam)) and $0FFF;
        if (Cmd = APPCOMMAND_BROWSER_BACKWARD) or (Cmd = APPCOMMAND_BROWSER_FORWARD) then
        begin
          { X-кнопки мыши: DefWindowProc шлёт APPCOMMAND на MouseUp.
            Ход уже сделан на MouseDown — не повторять. Клавиатура — отдельно. }
          if (HiWord(NativeUInt(lParam)) and FAPPCOMMAND_MASK) = FAPPCOMMAND_MOUSE then
            Exit(1);
          if Cmd = APPCOMMAND_BROWSER_BACKWARD then
            NavDelta := -1
          else
            NavDelta := 1;
          TThread.ForceQueue(nil,
            procedure
            begin
              if Assigned(GHookForm) then
                GHookForm.HistoryShortcut(NavDelta, True);
            end);
          Exit(1);
        end;
      end;


    WM_SYSCOMMAND:
      begin
        Cmd := NativeUInt(wParam) and $FFF0;
        if Cmd = SC_CLOSE then
        begin
          PostMessage(hWnd, WM_CLOSE, 0, 0);
          Exit(0);
        end;

        if (Cmd = SC_MAXIMIZE) or (Cmd = SC_RESTORE) or (Cmd = SC_MINIMIZE) then
        begin
          if Cmd = SC_MAXIMIZE then
            GHookForm.CaptureNormalGeometry;

          Result := DefWindowProc(hWnd, Msg, wParam, lParam);

          TThread.ForceQueue(nil,
            procedure
            var
              LPlacement: TWindowPlacement;
              Maxed: Boolean;
            begin
              if (GHookForm = nil) or (hWnd = 0) or not Assigned(GHookForm.FSettings) then
                Exit;
              { showCmd после восстановления с панели часто SW_SHOWNORMAL,
                хотя окно уже развёрнуто. Ориентир — само окно. }
              Maxed := IsZoomed(hWnd);
              if (not Maxed) and IsIconic(hWnd) then
              begin
                FillChar(LPlacement, SizeOf(LPlacement), 0);
                LPlacement.length := SizeOf(LPlacement);
                if GetWindowPlacement(hWnd, @LPlacement) then
                  Maxed := (LPlacement.flags and WPF_RESTORETOMAXIMIZED) <> 0;
              end;
              GHookForm.FSettings.WindowMaximized := Maxed;
              { Поверх IsZoomed не писать ни wsNormal, ни wsMaximized:
                FMX от wsMaximized снимает разворот и ставит его снова. }
              if (not IsZoomed(hWnd)) and (not Maxed) then
                GHookForm.WindowState := TWindowState.wsNormal;
              GHookForm.UpdateWindowButtons;
              PostMessage(hWnd, WM_REFRESH_FOCUS, 0, 0);
            end);
          Exit;
        end;





      end;

    WM_NCCALCSIZE:
      if wParam <> 0 then
      begin
        Params := PNCCalcSizeParams(lParam);
        Frame := GetSystemMetrics(SM_CXFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
        if Frame < 1 then Frame := 8;
        Params.rgrc[0].Left := Params.rgrc[0].Left + Frame;
        Params.rgrc[0].Right := Params.rgrc[0].Right - Frame;
        Params.rgrc[0].Bottom := Params.rgrc[0].Bottom - Frame;
        if IsZoomed(hWnd) then
          Params.rgrc[0].Top := Params.rgrc[0].Top + Frame;
        Exit(0);
      end;

    WM_NCHITTEST:
      begin
        Result := CallWindowProc(GHookForm.FOldWndProc, hWnd, Msg, wParam, lParam);
        if (Result = HTCLIENT) or (Result = HTNOWHERE) or (Result = HTCAPTION) then
        begin
          PT.X := Smallint(LoWord(DWORD(lParam)));
          PT.Y := Smallint(HiWord(DWORD(lParam)));
          Winapi.Windows.ScreenToClient(hWnd, PT);
          Scale := 1;
          if (GHookForm.Handle <> nil) and (GHookForm.Handle is TWinWindowHandle) then
            Scale := TWinWindowHandle(GHookForm.Handle).Scale;
          if Scale <= 0 then
            Scale := 1;
          FormPt := TPointF.Create(PT.X / Scale, PT.Y / Scale);
          Hit := GHookForm.CaptionHitTest(FormPt);
          if Hit <> 0 then
            Exit(Hit);
        end;
        Exit;
      end;
    WM_ERASEBKGND:
      Exit(1);
    WM_DEVICECHANGE:
      if ((wParam = $8000) or (wParam = $8004)) and Assigned(GHookForm.FDock) then
        GHookForm.FDock.NotifyDevicesChanged;
  end;
  if (Msg = WM_PAINT) and not GHookForm.FFirstPaintLogged then
  begin
    GHookForm.FFirstPaintLogged := True;
    StartupLog('first paint');
  end;
  Result := CallWindowProc(GHookForm.FOldWndProc, hWnd, Msg, wParam, lParam);
end;
procedure TMainForm.ApplyCustomFrame;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  Style: NativeInt;
  Corner: Integer;
  Margins: TMargins;
  CapColor: COLORREF;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  if Wnd = 0 then
    Exit;
  GHookForm := Self;
  Style := GetWindowLong(Wnd, GWL_STYLE);
  Style := Style or WS_CAPTION or WS_THICKFRAME or WS_MINIMIZEBOX or
    WS_MAXIMIZEBOX or WS_SYSMENU or WS_OVERLAPPED;
  SetWindowLong(Wnd, GWL_STYLE, Style);
  var Ex := GetWindowLong(Wnd, GWL_EXSTYLE);
  Ex := (Ex or WS_EX_APPWINDOW) and not WS_EX_TOOLWINDOW;
  if FFading or (not FStartupDone) or not Assigned(FSettings) or
     (FSettings.WindowMaterial = wmNormal) then
    Ex := Ex or WS_EX_LAYERED
  else
    Ex := Ex and not NativeInt(WS_EX_LAYERED);
  SetWindowLong(Wnd, GWL_EXSTYLE, Ex);
  if FFading or (not FStartupDone) then
    SetLayeredWindowAttributes(Wnd, 0, 0, LWA_ALPHA);
  var TransitionsOff: BOOL := False;
  DwmSetWindowAttribute(Wnd, 3, @TransitionsOff, SizeOf(TransitionsOff));

  if not FFrameHooked then
  begin
    FOldWndProc := Pointer(GetWindowLongPtr(Wnd, GWL_WNDPROC));
    SetWindowLongPtr(Wnd, GWL_WNDPROC, NativeInt(@FrameWndProc));
    FFrameHooked := True;
  end;

  Corner := 2;
  DwmSetWindowAttribute(Wnd, 33, @Corner, SizeOf(Corner));
  if Assigned(FSettings) then
    ApplyWindowMaterial(Wnd, FSettings.WindowMaterial, FColors.IsDark)
  else
    ApplyWindowMaterial(Wnd, wmNormal, FColors.IsDark);
  if (not Assigned(FSettings)) or (FSettings.WindowMaterial = wmNormal) then
  begin
    FillChar(Margins, SizeOf(Margins), 0);
    Margins.cyBottomHeight := 1;
    DwmExtendFrameIntoClientArea(Wnd, Margins);
    CapColor := AlphaToColorRef(FColors.TitleBarBackground);
    DwmSetWindowAttribute(Wnd, 35, @CapColor, SizeOf(CapColor));
    DwmSetWindowAttribute(Wnd, 34, @CapColor, SizeOf(CapColor));
  end;

  SetWindowPos(Wnd, 0, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
  HideFmxAppWindow;
  {$ENDIF}
end;

procedure TMainForm.HideFmxAppWindow;
{ FMX создаёт служебное TFMAppClass (0x0, WS_EX_APPWINDOW, тот же MAINICON)
  и показывает его. Вместе с нашей формой на таскбаре получается два превью. }
{$IFDEF MSWINDOWS}
var
  AppWnd, FormWnd: HWND;
  Taskbar: ITaskbarList;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  AppWnd := ApplicationHWND;
  FormWnd := FormToHWND(Self);

  if (AppWnd = 0) or (AppWnd = FormWnd) then Exit;

  SetWindowLong(AppWnd, GWL_EXSTYLE,
    GetWindowLong(AppWnd, GWL_EXSTYLE) or WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_NOACTIVATE);
  SetLayeredWindowAttributes(AppWnd, 0, 0, LWA_ALPHA);
  SetWindowLong(AppWnd, GWL_STYLE,
    GetWindowLong(AppWnd, GWL_STYLE) and not (WS_CAPTION or WS_BORDER or WS_THICKFRAME));
  SetWindowText(AppWnd, '');
  SetWindowPos(AppWnd, 0, -32000, -32000, 0, 0, SWP_HIDEWINDOW or SWP_NOSIZE or SWP_NOACTIVATE);

  if FormWnd <> 0 then
    SetWindowLongPtr(FormWnd, GWLP_HWNDPARENT, 0);

  try
    Taskbar := CreateComObject(CLSID_TaskbarList) as ITaskbarList;
    if Assigned(Taskbar) then
    begin
      Taskbar.HrInit;
      Taskbar.DeleteTab(AppWnd);
    end;
  except
  end;
  {$ENDIF}
end;

function TMainForm.CaptionHitTest(const AFormPt: TPointF): NativeInt;
var
  CapR, BtnR: TRectF;
begin
  Result := 0;
  if Assigned(FQuickSearch) and FQuickSearch.Visible and
     FQuickSearch.AbsoluteRect.Contains(AFormPt) then
    Exit(HTCLIENT);
  if (FCaptionBar <> nil) and FCaptionBar.Visible then
  begin
    BtnR := FCaptionBar.AbsoluteRect;
    if BtnR.Contains(AFormPt) then
      Exit(HTCLIENT);
  end;
  if (FTitleBar <> nil) and FTitleBar.Visible then
  begin
    CapR := FTitleBar.AbsoluteRect;
    if CapR.Contains(AFormPt) then
    begin
      if (not IsWindowMaximized) and (AFormPt.Y <= CapR.Top + 6) then
        Exit(HTTOP);
      Exit(HTCAPTION);
    end;
  end;
end;

function TMainForm.IsWindowMaximized: Boolean;
begin
  {$IFDEF MSWINDOWS}
  if FormToHWND(Self) <> 0 then
    Exit(IsZoomed(FormToHWND(Self)));
  {$ENDIF}
  Result := WindowState = TWindowState.wsMaximized;
end;

function TMainForm.CurrentWorkArea: TRectF;
{$IFDEF MSWINDOWS}
var
  R: TRect;
{$ENDIF}
begin
  { SPI_GETWORKAREA — рабочая область только основного монитора.
    Сохранённое окно по ней не проверять: второй монитор сюда не попадает. }
  Result := TRectF.Create(0, 0, 1280, 800);
  {$IFDEF MSWINDOWS}
  if SystemParametersInfo(SPI_GETWORKAREA, 0, @R, 0) then
    Result := TRectF.Create(R.Left, R.Top, R.Right, R.Bottom);
  {$ELSE}
  if Screen <> nil then
    Result := TRectF.Create(0, 0, Screen.Width, Screen.Height);
  {$ENDIF}
end;

procedure TMainForm.CaptureNormalGeometry;
begin
  if (csDestroying in ComponentState) or not Assigned(FSettings) then
    Exit;

  {$IFDEF MSWINDOWS}
  var hWnd := FormToHWND(Self);
  if hWnd <> 0 then
  begin
    // Если окно свернуто или развернуто — НЕ сохраняем геометрию,
    // иначе координаты "развернутого" окна перезапишут "нормальные".
    if IsZoomed(hWnd) or IsIconic(hWnd) or (WindowState = TWindowState.wsMaximized) then
      Exit;
  end;
  {$ENDIF}

  FSettings.WindowLeft := Round(Left);
  FSettings.WindowTop := Round(Top);
  FSettings.WindowWidth := Round(Width);
  FSettings.WindowHeight := Max(Round(Height), Round(Constraints.MinHeight));
end;

function TMainForm.NativeScale: Single;
begin
  Result := 1;
  {$IFDEF MSWINDOWS}
  if (Handle <> nil) and (Handle is TWinWindowHandle) then
  begin
    Result := TWinWindowHandle(Handle).Scale;
    if Result < 0.5 then
      Result := 1;
  end;
  {$ENDIF}
end;

procedure TMainForm.ApplyStartupGeometry;
var
  WA: TRectF;
  Scale, W, H, L, T: Single;
begin
  W := FSettings.WindowWidth;
  H := FSettings.WindowHeight;
  if W < 400 then
    W := 1200;
  if H < MIN_WINDOW_FLOOR then
    H := MIN_WINDOW_FLOOR;

  FPendingMaximized := FSettings.WindowMaximized;
  FCenterOnRestore := FPendingMaximized;
  { Позиции нет, только если в ini не было Left/Top. Отрицательные — левый или верхний монитор. }
  FCenterAtShow := (not FSettings.WindowPosSaved) and (not FPendingMaximized);
  Position := TFormPosition.Designed;
  Width := Round(W);
  Height := Round(H);

  if FSettings.WindowPosSaved then
  begin
    { До хэндла FMX обрежет Left по основному экрану. Это только подсказка.
      В настройки не пишем: иначе пропадёт отрицательная координата.
      Итог ставит ApplySavedWindowRect уже по хэндлу. }
    Left := FSettings.WindowLeft;
    Top := FSettings.WindowTop;
    Exit;
  end;

  { Первый запуск. CurrentWorkArea здесь — основной монитор, это и нужно. }
  Scale := NativeScale;
  WA := CurrentWorkArea;
  if Scale > 0 then
    WA := TRectF.Create(WA.Left / Scale, WA.Top / Scale, WA.Right / Scale, WA.Bottom / Scale);
  if WA.Width < 200 then
    WA := TRectF.Create(0, 0, 1280, 800);
  if FPendingMaximized then
  begin
    if W > WA.Width * 0.92 then
      W := Min(1200, Max(480, WA.Width * 0.72));
    if H > WA.Height * 0.92 then
      H := Min(Max(MIN_WINDOW_HEIGHT, 700), Max(MIN_WINDOW_HEIGHT, WA.Height * 0.72));
  end
  else
  begin
    if W > WA.Width then
      W := WA.Width;
    if H > WA.Height then
      H := WA.Height;
  end;
  L := WA.Left + (WA.Width - W) / 2;
  T := WA.Top + (WA.Height - H) / 2;
  Width := Round(W);
  Height := Round(H);
  Left := Round(L);
  Top := Round(T);
  FSettings.WindowLeft := Left;
  FSettings.WindowTop := Top;
  FSettings.WindowWidth := Width;
  FSettings.WindowHeight := Height;
end;

function TMainForm.CalcMinWindowHeight: Integer;
const
  CmdGap = 4;
var
  TopH, BotH, Need, Stack: Single;

  function ChromeFrameHeight: Single;
  {$IFDEF MSWINDOWS}
  var
    Px: Integer;
    Scale, Measured: Single;
    Wnd: HWND;
  {$ENDIF}
  begin
    { WM_NCCALCSIZE отступает только снизу. Высота формы — внешняя,
      клиент короче на эту рамку. }
    {$IFDEF MSWINDOWS}
    Px := GetSystemMetrics(SM_CXFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
    if Px < 1 then
      Px := 8;
    Scale := NativeScale;
    if Scale < 0.5 then
      Scale := 1;
    Result := Px / Scale;
    Wnd := FormToHWND(Self);
    if (Wnd <> 0) and (not IsZoomed(Wnd)) and (not IsIconic(Wnd)) and
       (ClientHeight > 0) and (Height > ClientHeight) then
    begin
      Measured := Height - ClientHeight;
      if (Measured > 0) and (Measured < Result + 12) then
        Result := Measured;
    end;
    {$ELSE}
    Result := 0;
    {$ENDIF}
  end;

begin
  { Поля рабочей области и отступ кнопок тоже занимают высоту.
    Футер панели лежит внутри карточки и сюда не входит. }
  TopH := TITLEBAR_HEIGHT;
  if (not Assigned(FSettings)) or FSettings.ShowDock then
    TopH := TopH + DOCK_HEIGHT;
  BotH := 0;
  if (not Assigned(FSettings)) or FSettings.ShowFnBar then
    BotH := BotH + FNBAR_HEIGHT;
  if Assigned(FSettings) and FSettings.ShowCommandLine then
    BotH := BotH + CMDLINE_HEIGHT + CmdGap;
  Need := TopH + BotH;
  if (not Assigned(FSettings)) or FSettings.ShowMidBar then
  begin
    Stack := FMidStackH;
    if Stack < 0 then
      Stack := 0;
    Need := Need + WORK_PAD_T + MIDBAR_TOP + MID_BTN_Y0 + Stack +
      MIDBAR_BOTTOM + WORK_PAD_B + MIN_WINDOW_SLACK;
  end;
  Result := Ceil(Need + ChromeFrameHeight);
  if Result < MIN_WINDOW_FLOOR then
    Result := MIN_WINDOW_FLOOR;
end;

procedure TMainForm.ApplyMinWindowHeight;
var
  MinH: Integer;
begin
  if csDestroying in ComponentState then
    Exit;
  MinH := CalcMinWindowHeight;
  if Constraints.MinHeight <> MinH then
    Constraints.MinHeight := MinH;
  {$IFDEF MSWINDOWS}
  if (not IsWindowMaximized) and
     ((FormToHWND(Self) = 0) or not IsIconic(FormToHWND(Self))) and
     (Height < MinH) then
    Height := MinH;
  {$ELSE}
  if (not IsWindowMaximized) and (Height < MinH) then
    Height := MinH;
  {$ENDIF}
  LayoutMidButtons;
end;

procedure TMainForm.ApplyNativeWindowRect;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  Mon: HMONITOR;
  Info: TMonitorInfo;
  Scale: Single;
  PxW, PxH, L, T, WaW, WaH: Integer;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if not FCenterAtShow then
    Exit;
  Wnd := FormToHWND(Self);
  if (Wnd = 0) or IsZoomed(Wnd) or IsIconic(Wnd) then
    Exit;
  Scale := NativeScale;
  Mon := MonitorFromWindow(Wnd, MONITOR_DEFAULTTONEAREST);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if not GetMonitorInfo(Mon, @Info) then
    Exit;
  PxW := Max(1, Round(Width * Scale));
  PxH := Max(1, Round(Height * Scale));
  WaW := Info.rcWork.Right - Info.rcWork.Left;
  WaH := Info.rcWork.Bottom - Info.rcWork.Top;
  if WaW < 200 then
    Exit;
  if PxW > WaW then
    PxW := WaW;
  if PxH > WaH then
    PxH := WaH;
  L := Info.rcWork.Left + (WaW - PxW) div 2;
  T := Info.rcWork.Top + (WaH - PxH) div 2;
  SetWindowPos(Wnd, 0, L, T, PxW, PxH, SWP_NOZORDER or SWP_NOACTIVATE);
  FCenterAtShow := False;
  Left := Round(L / Scale);
  Top := Round(T / Scale);
  if Abs(Width - PxW / Scale) > 1 then
    Width := Round(PxW / Scale);
  if Abs(Height - PxH / Scale) > 1 then
    Height := Round(PxH / Scale);
  if Assigned(FSettings) then
  begin
    FSettings.WindowLeft := Left;
    FSettings.WindowTop := Top;
    FSettings.WindowWidth := Round(Width);
    FSettings.WindowHeight := Round(Height);
  end;
  {$ENDIF}
end;

type
  PMonWorkScan = ^TMonWorkScan;
  TMonWorkScan = record
    Saved: TRect;
    Hit: Boolean;
    BestArea: Int64;
    BestWork: TRect;
    BestMon: HMONITOR;
  end;

{ stdcall: вложенная процедура сюда не годится. r — весь монитор, не rcWork. }
function EnumMonWork(hm: HMONITOR; dc: HDC; r: PRect; l: LPARAM): Boolean; stdcall;
var
  Info: TMonitorInfo;
  Scan: PMonWorkScan;
  Lft, Tp, Rt, Bt: Integer;
  Area: Int64;
begin
  Result := True;
  if (l = 0) or (hm = 0) then
    Exit;
  Scan := PMonWorkScan(l);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if not GetMonitorInfo(hm, @Info) then
    Exit;
  if (Info.rcWork.Right <= Info.rcWork.Left) or
     (Info.rcWork.Bottom <= Info.rcWork.Top) then
    Exit;
  Lft := Max(Scan.Saved.Left, Info.rcWork.Left);
  Tp := Max(Scan.Saved.Top, Info.rcWork.Top);
  Rt := Min(Scan.Saved.Right, Info.rcWork.Right);
  Bt := Min(Scan.Saved.Bottom, Info.rcWork.Bottom);
  if (Rt <= Lft) or (Bt <= Tp) then
    Exit;
  Area := Int64(Rt - Lft) * Int64(Bt - Tp);
  if (not Scan.Hit) or (Area > Scan.BestArea) then
  begin
    Scan.Hit := True;
    Scan.BestArea := Area;
    Scan.BestWork := Info.rcWork;
    Scan.BestMon := hm;
  end;
end;

procedure TMainForm.ApplySavedWindowRect;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  Info: TMonitorInfo;
  Scan: TMonWorkScan;
  Scale, MonScale: Single;
  DipW, DipH, MinDip: Integer;
  Saved: TRect;
  WorkW, WorkH, PxW, PxH, MinPx, FitL, FitT: Integer;
  Dp: TPointF;

  function ScaleOf(AMon: HMONITOR): Single;
  var
    Svc: IFMXMultiDisplayService;
    I: Integer;
    Disp: TDisplay;
  begin
    Result := 0;
    if (AMon = 0) or
       not TPlatformServices.Current.SupportsPlatformService(IFMXMultiDisplayService, Svc) then
      Exit;
    for I := 0 to Svc.DisplayCount - 1 do
    begin
      Disp := Svc.Displays[I];
      if Disp.Id = NativeUInt(AMon) then
        Exit(Disp.Scale);
    end;
  end;

  function RectAt(AScale: Single): TRect;
  var
    Org: TPoint;
  begin
    Org := DpToPx(PointF(FSettings.WindowLeft, FSettings.WindowTop));
    if AScale < 0.5 then
      AScale := 1;
    Result.Left := Org.X;
    Result.Top := Org.Y;
    Result.Right := Org.X + Max(1, Round(DipW * AScale));
    Result.Bottom := Org.Y + Max(1, Round(DipH * AScale));
  end;

  procedure Collect(const ARect: TRect);
  begin
    Scan.Saved := ARect;
    Scan.Hit := False;
    Scan.BestArea := 0;
    Scan.BestMon := 0;
    EnumDisplayMonitors(0, nil, EnumMonWork, LPARAM(@Scan));
  end;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if (not Assigned(FSettings)) or (not FSettings.WindowPosSaved) then
    Exit;
  Wnd := FormToHWND(Self);
  if Wnd = 0 then
    Exit;

  DipW := FSettings.WindowWidth;
  DipH := FSettings.WindowHeight;
  if DipW < 400 then
    DipW := 1200;
  if DipH < MIN_WINDOW_FLOOR then
    DipH := MIN_WINDOW_FLOOR;

  { Размер — масштаб монитора, на котором лежит прямоугольник, не масштаб хэндла.
    Хэндл до SetWindowPos ещё на основном экране. }
  Scale := NativeScale;
  if Scale < 0.5 then
    Scale := 1;
  Saved := RectAt(Scale);
  MonScale := ScaleOf(MonitorFromRect(@Saved, MONITOR_DEFAULTTONEAREST));
  if MonScale >= 0.5 then
    Scale := MonScale;
  Saved := RectAt(Scale);
  Collect(Saved);
  if Scan.Hit then
  begin
    MonScale := ScaleOf(Scan.BestMon);
    if (MonScale >= 0.5) and (Abs(MonScale - Scale) > 0.01) then
    begin
      Scale := MonScale;
      Saved := RectAt(Scale);
      Collect(Saved);
    end;
  end;

  if not Scan.Hit then
  begin
    Scan.BestMon := MonitorFromRect(@Saved, MONITOR_DEFAULTTONEAREST);
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    if (Scan.BestMon = 0) or (not GetMonitorInfo(Scan.BestMon, @Info)) then
      Exit;
    if (Info.rcWork.Right <= Info.rcWork.Left) or
       (Info.rcWork.Bottom <= Info.rcWork.Top) then
      Exit;
    Scan.BestWork := Info.rcWork;
    MonScale := ScaleOf(Scan.BestMon);
    if (MonScale >= 0.5) and (Abs(MonScale - Scale) > 0.01) then
    begin
      Scale := MonScale;
      Saved := RectAt(Scale);
      { Другой масштаб меняет размер: прямоугольник мог начать пересекать rcWork. }
      Collect(Saved);
      if not Scan.Hit then
        Scan.BestWork := Info.rcWork;
    end;
  end;

  WorkW := Scan.BestWork.Right - Scan.BestWork.Left;
  WorkH := Scan.BestWork.Bottom - Scan.BestWork.Top;
  if (WorkW < 1) or (WorkH < 1) then
    Exit;

  PxW := Saved.Right - Saved.Left;
  PxH := Saved.Bottom - Saved.Top;
  MinDip := Round(Constraints.MinHeight);
  if MinDip < MIN_WINDOW_FLOOR then
    MinDip := MIN_WINDOW_FLOOR;
  MinPx := Max(1, Round(MinDip * Scale));
  if PxW > WorkW then
    PxW := WorkW;
  if PxH > WorkH then
    PxH := WorkH;
  if PxH < MinPx then
    PxH := MinPx;
  if PxW < 1 then
    PxW := 1;

  { Сначала правый и нижний край, потом левый и верхний: заголовок остаётся у Work.Top. }
  FitL := Saved.Left;
  FitT := Saved.Top;
  if FitL + PxW > Scan.BestWork.Right then
    FitL := Scan.BestWork.Right - PxW;
  if FitT + PxH > Scan.BestWork.Bottom then
    FitT := Scan.BestWork.Bottom - PxH;
  if FitL < Scan.BestWork.Left then
    FitL := Scan.BestWork.Left;
  if FitT < Scan.BestWork.Top then
    FitT := Scan.BestWork.Top;

  SetWindowPos(Wnd, 0, FitL, FitT, PxW, PxH, SWP_NOZORDER or SWP_NOACTIVATE);

  { Не переписывать ini, если пиксели те же: иначе DIP округляется на каждом старте.
    Сдвиг пишем сразу: закрытие в развёрнутом виде геометрию не снимает. }
  if (Abs(FitL - Saved.Left) <= 1) and (Abs(FitT - Saved.Top) <= 1) and
     (Abs(PxW - (Saved.Right - Saved.Left)) <= 1) and
     (Abs(PxH - (Saved.Bottom - Saved.Top)) <= 1) then
    Exit;
  Dp := PxToDp(Point(FitL, FitT));
  FSettings.WindowLeft := Round(Dp.X);
  FSettings.WindowTop := Round(Dp.Y);
  FSettings.WindowWidth := Max(1, Round(PxW / Scale));
  FSettings.WindowHeight := Max(1, Round(PxH / Scale));
  {$ENDIF}
end;

procedure TMainForm.CenterNormalWindow;
begin
  if (csDestroying in ComponentState) or IsWindowMaximized then
    Exit;
  FCenterAtShow := True;
  ApplyNativeWindowRect;
  CaptureNormalGeometry;
  FCenterOnRestore := False;
end;

procedure TMainForm.PersistWindowState;
begin
  if not Assigned(FSettings) then
    Exit;
  FSettings.WindowMaximized := IsWindowMaximized;
  if not FSettings.WindowMaximized then
    CaptureNormalGeometry;
end;

procedure TMainForm.NativeSysCommand(ACmd: NativeUInt);
begin
  {$IFDEF MSWINDOWS}
  PostMessage(FormToHWND(Self), WM_SYSCOMMAND, ACmd, 0);
  {$ENDIF}
end;

procedure TMainForm.StartStartupFade;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  ShowCmd: Integer;
{$ENDIF}
begin
  FFading := True;
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    SetWindowLong(Wnd, GWL_EXSTYLE, GetWindowLong(Wnd, GWL_EXSTYLE) or WS_EX_LAYERED);
    SetLayeredWindowAttributes(Wnd, 0, 0, LWA_ALPHA);
  end;
  {$ENDIF}
  Visible := True;
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    SetWindowLong(Wnd, GWL_EXSTYLE, GetWindowLong(Wnd, GWL_EXSTYLE) or WS_EX_LAYERED);
    SetLayeredWindowAttributes(Wnd, 0, 0, LWA_ALPHA);
    { Visible := True уже мог вернуть окно на основной экран. Ставим место до показа. }
    if not FCenterAtShow then
      ApplySavedWindowRect;
    if FPendingMaximized then
      ShowCmd := SW_SHOWMAXIMIZED
    else
      ShowCmd := SW_SHOWNA;
    FPendingMaximized := False;
    ShowWindow(Wnd, ShowCmd);
    if ShowCmd <> SW_SHOWMAXIMIZED then
    begin
      { ShowWindow снова может сдвинуть на основной. Развёрнутое не трогаем:
        его монитор уже задан прямоугольником перед SW_SHOWMAXIMIZED. }
      if FCenterAtShow then
        ApplyNativeWindowRect
      else
        ApplySavedWindowRect;
    end;
    if WindowAnimEnabled then
    begin
      FFadeStart := GetTickCount64;
      if Assigned(FFadeTimer) then
        FFadeTimer.Enabled := True;
    end
    else
      FinishStartupFade;
  end;
  HideFmxAppWindow;
  UpdateWindowButtons;
  {$ELSE}
  FStartupDone := True;
  FFading := False;
  Visible := True;
  KickFolderSizes;
  {$ENDIF}
end;

procedure TMainForm.FadeTick(Sender: TObject);
{$IFDEF MSWINDOWS}
var
  T: Single;
  Alpha: Byte;
  Wnd: HWND;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  T := (GetTickCount64 - FFadeStart) / 280;
  if T >= 1 then
  begin
    FinishStartupFade;
    Exit;
  end;
  Alpha := Byte(Round((1 - Power(1 - T, 3)) * 255));
  if Alpha < 1 then
    Alpha := 1;
  if Wnd <> 0 then
    SetLayeredWindowAttributes(Wnd, 0, Alpha, LWA_ALPHA);
  {$ENDIF}
end;

procedure TMainForm.StartupIdleTick(Sender: TObject);
begin
  if Assigned(FStartupTimer) then
    FStartupTimer.Enabled := False;
  if FStartupPhase >= 2 then
    Exit;
  FStartupPhase := 2;
  if Assigned(GlobalIconCache) then
  begin
    GlobalIconCache.EnableTypeFetch;
    GlobalIconCache.EnableCustomFetch;
  end;
  if Assigned(FDock) and Assigned(FSettings) then
    FDock.LoadItems(FSettings.DockItems, FSettings.DockItemX,
      FSettings.DockKinds, FSettings.DockCaptions, FSettings.DockIcons,
      FSettings.DockIconLocked);
  if Assigned(FLeftPanel) then
    FLeftPanel.StartDeferredDrives;
  if Assigned(FRightPanel) then
    FRightPanel.StartDeferredDrives;
  if Assigned(FLeftPanel) and Assigned(FSettings) then
    FLeftPanel.RestoreTabs(FSettings.Left);
  if Assigned(FRightPanel) and Assigned(FSettings) then
    FRightPanel.RestoreTabs(FSettings.Right);
  if Assigned(FLeftPanel) then
    FLeftPanel.LoadActiveTab;
  if Assigned(FIdlePlusTimer) then
    FIdlePlusTimer.Enabled := True;
  MarkSessionDirty;
end;

procedure TMainForm.LeftListReady(Sender: TObject);
begin
  if FLeftReady then
    Exit;
  FLeftReady := True;
  StartupLog('left list ready');
  if Assigned(FRightPanel) then
    FRightPanel.LoadActiveTab;
end;

procedure TMainForm.RightListReady(Sender: TObject);
begin
  if FRightReady then
    Exit;
  FRightReady := True;
  StartupLog('right list ready');
end;

procedure TMainForm.StartupIdlePlusTick(Sender: TObject);
begin
  if Assigned(FIdlePlusTimer) then
    FIdlePlusTimer.Enabled := False;
  if FStartupPhase >= 3 then
    Exit;
  FStartupPhase := 3;
  if FChromeWatch = nil then
    FChromeWatch := TSystemChromeWatcher.Create(
      procedure
      begin
        HandleSystemChromeChanged;
      end);
  if Assigned(GlobalIconCache) then
    GlobalIconCache.EnableCustomFetch;
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.EnableWorkers;
  if Assigned(FLeftPanel) then
  begin
    FLeftPanel.EnableDirWatch;
    FLeftPanel.AllowTabShellIcons;
    FLeftPanel.AddSlowPlaces;
    FLeftPanel.InvalidateView;
  end;
  if Assigned(FRightPanel) then
  begin
    FRightPanel.EnableDirWatch;
    FRightPanel.AllowTabShellIcons;
    FRightPanel.AddSlowPlaces;
    FRightPanel.InvalidateView;
  end;
  if Assigned(FStaleTimer) then
    FStaleTimer.Enabled := True;
end;

procedure TMainForm.StartupStaleTick(Sender: TObject);
var
  LeftBusy, RightBusy: Boolean;
begin
  if not FLeftReady or not FRightReady then
    Exit;
  LeftBusy := False;
  RightBusy := False;
  if Assigned(FLeftPanel) then
    LeftBusy := FLeftPanel.LoadNextStaleTab;
  if Assigned(FRightPanel) then
    RightBusy := FRightPanel.LoadNextStaleTab;
  if (not LeftBusy) and (not RightBusy) and Assigned(FStaleTimer) then
    FStaleTimer.Enabled := False;
end;

procedure TMainForm.FinishStartupFade;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
{$ENDIF}
begin
  if Assigned(FFadeTimer) then
    FFadeTimer.Enabled := False;
  FFading := False;
  FStartupDone := True;
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    SetLayeredWindowAttributes(Wnd, 0, 255, LWA_ALPHA);
    if Assigned(FSettings) and (FSettings.WindowMaterial <> wmNormal) then
      ApplyCustomFrame;
  end;
  {$ENDIF}
  KickFolderSizes;
end;

procedure TMainForm.BuildTitleBar;
var
  TitleBlock, LogoRow: TLayout;
begin
  FTopStack := TLayout.Create(Self);
  FTopStack.Parent := Self;
  FTopStack.Align := TAlignLayout.Top;
  FTopStack.Height := TITLEBAR_HEIGHT + DOCK_HEIGHT;
  FTopStack.HitTest := False;

  FTitleBar := TRectangle.Create(Self);
  FTitleBar.Parent := FTopStack;
  FTitleBar.Align := TAlignLayout.Top;
  FTitleBar.Height := TITLEBAR_HEIGHT;
  FTitleBar.Stroke.Kind := TBrushKind.None;
  FTitleBar.Stroke.Thickness := 0;
  FTitleBar.Fill.Kind := TBrushKind.Solid;
  FTitleBar.HitTest := True;

  FCaptionBar := TLayout.Create(Self);
  FCaptionBar.Parent := FTitleBar;
  FCaptionBar.Align := TAlignLayout.Right;
  FCaptionBar.Width := CAPTION_BTN_W * 4;
  FCaptionBar.HitTest := True;

  FBtnClose := MakeWinBtn(FCaptionBar, ICON_CHROME_CLOSE, OnCloseClick);
  FBtnMax := MakeWinBtn(FCaptionBar, ICON_CHROME_MAX, OnMaxClick);
  FBtnMin := MakeWinBtn(FCaptionBar, ICON_CHROME_MIN, OnMinClick);
  FBtnSettings := MakeWinBtn(FCaptionBar, ICON_CHROME_SETTINGS, OnSettingsClick);

  FAppIcon := TImage.Create(Self);
  FAppIcon.Parent := FTitleBar;
  FAppIcon.Align := TAlignLayout.Left;
  FAppIcon.Width := 28;
  FAppIcon.HitTest := False;
  FAppIcon.WrapMode := TImageWrapMode.Fit;
  LoadTitleIcon;

  TitleBlock := TLayout.Create(Self);
  TitleBlock.Parent := FTitleBar;
  TitleBlock.Align := TAlignLayout.Left;
  TitleBlock.Width := 200;
  TitleBlock.HitTest := False;

  LogoRow := TLayout.Create(Self);
  LogoRow.Parent := TitleBlock;
  LogoRow.Align := TAlignLayout.Top;
  LogoRow.Height := 18;
  LogoRow.HitTest := False;

  FTitleText := TText.Create(Self);
  FTitleText.Parent := LogoRow;
  FTitleText.Align := TAlignLayout.Client;
  FTitleText.Text := 'V!BE CMD';
  StyleLogoText(FTitleText, 13, True);
  FTitleText.TextSettings.VertAlign := TTextAlign.Trailing;

  FSubtitleText := TText.Create(Self);
  FSubtitleText.Parent := TitleBlock;
  FSubtitleText.Align := TAlignLayout.Client;
  FSubtitleText.Text := ReadAppVersion;
  StyleLogoText(FSubtitleText, 8, False);
  FSubtitleText.TextSettings.VertAlign := TTextAlign.Leading;

  FAppIcon.Margins.Rect := TRectF.Create(20, 6, 6, 6);
  TitleBlock.Margins.Rect := TRectF.Create(2, 6, 0, 3);

  FSearchHist := TStringList.Create;
  FSearchHist.CaseSensitive := False;
  if Assigned(FSettings) then
    for var I := 0 to High(FSettings.SearchHistory) do
      if FSettings.SearchHistory[I] <> '' then
        FSearchHist.Add(FSettings.SearchHistory[I]);

  FSearchDebounce := TTimer.Create(Self);
  FSearchDebounce.Interval := 120;
  FSearchDebounce.Enabled := False;
  FSearchDebounce.OnTimer := SearchDebounceTick;

  FQuickSearch := TFluentComboBox.Create(Self);
  FQuickSearch.Parent := FTitleBar;
  FQuickSearch.Suggest := True;
  FQuickSearch.TextPrompt := L('main.search.prompt');
  FQuickSearch.Glyph := #$E721;
  FQuickSearch.Items.Assign(FSearchHist);
  if FSearchHist.Count > 0 then
    FQuickSearch.FooterCaption := L('main.search.clear');
  FQuickSearch.OnChange := SearchChanged;
  FQuickSearch.OnSelChange := SearchSelected;
  FQuickSearch.OnSubmit := SearchSubmit;
  FQuickSearch.OnEscape := SearchEscape;
  FQuickSearch.OnDrop := SearchDrop;
  FQuickSearch.OnFooter := SearchClearHistory;
  LayoutQuickSearch;

  FTitleLine := nil;
end;

procedure TMainForm.LayoutQuickSearch;
var
  LeftLimit, RightLimit, Avail, W, X: Single;
begin
  if (FQuickSearch = nil) or (FTitleBar = nil) or (FCaptionBar = nil) then
    Exit;
  LeftLimit := 168;
  RightLimit := FTitleBar.Width - FCaptionBar.Width - 8;
  Avail := RightLimit - LeftLimit;
  if Avail < 80 then
    Avail := 80;
  W := FTitleBar.Width * 0.36;
  if W > 360 then
    W := 360;
  if W < 220 then
    W := 220;
  if W > Avail then
    W := Avail;
  FQuickSearch.Align := TAlignLayout.None;
  FQuickSearch.Width := W;
  FQuickSearch.Height := 28;
  X := (FTitleBar.Width - W) / 2;
  if X < LeftLimit then
    X := LeftLimit;
  if X + W > RightLimit then
    X := RightLimit - W;
  FQuickSearch.Position.X := X;
  FQuickSearch.Position.Y := (TITLEBAR_HEIGHT - 28) / 2;
end;

procedure TMainForm.UsePanel(APanel: TFilePanel; AFocus: Boolean);
var
  Switched: Boolean;
begin
  if not Assigned(APanel) then
    Exit;
  Switched := FActivePanel <> APanel;
  if Switched then
  begin
    if Assigned(FActivePanel) and FActivePanel.HasFilter then
      FActivePanel.ClearFilter;
    FActivePanel := APanel;
    if Assigned(FQuickSearch) and (FQuickSearch.Text <> '') then
      APanel.ApplyNameFilter(FQuickSearch.Text);
  end;
  if APanel = FLeftPanel then
  begin
    FLeftPanel.SetActive(True);
    if Assigned(FRightPanel) then
      FRightPanel.SetActive(False);
  end
  else
  begin
    if Assigned(FRightPanel) then
      FRightPanel.SetActive(True);
    if Assigned(FLeftPanel) then
      FLeftPanel.SetActive(False);
  end;
  UpdateViewButtons;
  if AFocus and APanel.CanFocus then
    APanel.SetFocus;
  SyncCmdPath;
  if Assigned(FOpPill) and FOpPill.Visible and not OpPillOnRail then
    LayoutOpPill;
  { После текущего клика: курсор уже сдвинут, окно берёт итоговый файл. }
  if Switched then
    TThread.ForceQueue(nil,
      procedure
      begin
        FollowActivePanelPreview;
      end);
end;

procedure TMainForm.SearchChanged(Sender: TObject);
begin
  if not Assigned(FSearchDebounce) then
    Exit;
  FSearchDebounce.Enabled := False;
  FSearchDebounce.Enabled := True;
end;

procedure TMainForm.SearchDebounceTick(Sender: TObject);
begin
  FSearchDebounce.Enabled := False;
  if Assigned(FActivePanel) and Assigned(FQuickSearch) then
    FActivePanel.ApplyNameFilter(FQuickSearch.Text);
end;

procedure TMainForm.SearchSubmit(Sender: TObject);
begin
  if Assigned(FSearchDebounce) then
    FSearchDebounce.Enabled := False;
  if not Assigned(FQuickSearch) then
    Exit;
  RememberSearch(FQuickSearch.Text);
  if Assigned(FActivePanel) then
    FActivePanel.ApplyNameFilter(FQuickSearch.Text);
end;

procedure TMainForm.SearchSelected(Sender: TObject);
begin
  if Assigned(FSearchDebounce) then
    FSearchDebounce.Enabled := False;
  if Assigned(FActivePanel) and Assigned(FQuickSearch) then
    FActivePanel.ApplyNameFilter(FQuickSearch.Text);
end;

procedure TMainForm.SearchEscape(Sender: TObject);
begin
  if Assigned(FSearchDebounce) then
    FSearchDebounce.Enabled := False;
  if Assigned(FQuickSearch) then
    FQuickSearch.Text := '';
  if Assigned(FActivePanel) then
    FActivePanel.ClearFilter;
  if Assigned(FActivePanel) and FActivePanel.CanFocus then
    FActivePanel.SetFocus;
end;

procedure TMainForm.SearchDrop(Sender: TObject);
begin
  if not Assigned(FQuickSearch) or not Assigned(FSearchHist) then
    Exit;
  FQuickSearch.Items.Assign(FSearchHist);
  if FSearchHist.Count > 0 then
    FQuickSearch.FooterCaption := L('main.search.clear')
  else
    FQuickSearch.FooterCaption := '';
end;

procedure TMainForm.SearchClearHistory(Sender: TObject);
begin
  if Assigned(FSearchHist) then
    FSearchHist.Clear;
  if Assigned(FQuickSearch) then
  begin
    FQuickSearch.Items.Clear;
    FQuickSearch.FooterCaption := '';
  end;
  if Assigned(FSettings) then
  begin
    SetLength(FSettings.SearchHistory, 0);
    try
      FSettings.SaveSearchHistory;
    except
    end;
  end;
end;

procedure TMainForm.RememberSearch(const AText: string);
var
  I: Integer;
  S: string;
begin
  S := Trim(AText);
  if (S = '') or not Assigned(FSearchHist) then
    Exit;
  for I := FSearchHist.Count - 1 downto 0 do
    if SameText(FSearchHist[I], S) then
      FSearchHist.Delete(I);
  FSearchHist.Insert(0, S);
  while FSearchHist.Count > 12 do
    FSearchHist.Delete(FSearchHist.Count - 1);
  if Assigned(FQuickSearch) then
  begin
    FQuickSearch.Items.Assign(FSearchHist);
    FQuickSearch.FooterCaption := L('main.search.clear');
  end;
  if Assigned(FSettings) then
  begin
    SetLength(FSettings.SearchHistory, FSearchHist.Count);
    for I := 0 to FSearchHist.Count - 1 do
      FSettings.SearchHistory[I] := FSearchHist[I];
    try
      FSettings.SaveSearchHistory;
    except
    end;
  end;
end;

procedure TMainForm.WinBtnEnter(Sender: TObject);
begin
  if not (Sender is TRectangle) then
    Exit;
  if Sender = FBtnClose then
  begin
    TRectangle(Sender).Fill.Color := $FFE81123;
    if TRectangle(Sender).TagObject is TText then
      TText(TRectangle(Sender).TagObject).TextSettings.FontColor := TAlphaColors.White;
  end
  else
    TRectangle(Sender).Fill.Color := FColors.ItemHover;
end;

procedure TMainForm.WinBtnLeave(Sender: TObject);
begin
  if not (Sender is TRectangle) then
    Exit;
  TRectangle(Sender).Fill.Color := TAlphaColors.Null;
  if TRectangle(Sender).TagObject is TText then
    TText(TRectangle(Sender).TagObject).TextSettings.FontColor := FColors.TextColor;
end;

function TMainForm.WindowAnimEnabled: Boolean;
begin
  Result := True;
end;

procedure TMainForm.OnMinClick(Sender: TObject);
begin
  {$IFDEF MSWINDOWS}
  if WindowAnimEnabled then
    NativeSysCommand(SC_MINIMIZE)
  else
    ShowWindow(FormToHWND(Self), SW_SHOWMINIMIZED);
  {$ELSE}
  WindowState := TWindowState.wsMinimized;
  {$ENDIF}
end;

procedure TMainForm.OnMaxClick(Sender: TObject);
begin
  {$IFDEF MSWINDOWS}
  if IsZoomed(FormToHWND(Self)) then
    NativeSysCommand(SC_RESTORE)
  else
    NativeSysCommand(SC_MAXIMIZE);
  {$ELSE}
  if WindowState = TWindowState.wsMaximized then
    WindowState := TWindowState.wsNormal
  else
    WindowState := TWindowState.wsMaximized;
  {$ENDIF}
  UpdateWindowButtons;
end;

procedure TMainForm.OnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.UpdateWindowButtons;
var
  Glyph: TText;
begin
  if (FBtnMax = nil) or not (FBtnMax.TagObject is TText) then
    Exit;
  Glyph := TText(FBtnMax.TagObject);
  if IsWindowMaximized then
    Glyph.Text := ICON_CHROME_RESTORE
  else
    Glyph.Text := ICON_CHROME_MAX;
end;

procedure TMainForm.BuildDock;
begin
  FDock := TLaunchDock.Create(Self);
  FDock.Parent := FTopStack;
  FDock.Align := TAlignLayout.Client;
  FDock.OnOpenFolder := DockOpenFolder;
  FDock.OnGoToObject := DockGoToObject;
  FDock.OnStatus := DockStatus;
  FDock.OnChanged := DockChanged;
  FDock.OnCopyToFolder := DockCopyToFolder;
  FDock.ApplyDockOptions(FSettings.DockAlign, FSettings.DockShowSeparators);
  FDock.Margins.Top:=6;

end;

procedure TMainForm.DockOpenFolder(Sender: TObject; const APath: string);
begin
  if Assigned(FActivePanel) and (APath <> '') then
    FActivePanel.Navigate(APath);
end;

procedure TMainForm.DockGoToObject(Sender: TObject; const APath: string);
var
  ParentDir: string;
begin
  if not Assigned(FActivePanel) or (APath = '') then
    Exit;
  if TDirectory.Exists(APath) then
    FActivePanel.Navigate(APath)
  else
  begin
    ParentDir := ExtractFileDir(APath);
    if ParentDir = '' then
      ParentDir := APath;
    FActivePanel.Navigate(ParentDir, APath);
  end;
end;

procedure TMainForm.DockStatus(Sender: TObject; const AText: string);
begin
  if Assigned(FActivePanel) then
    FActivePanel.ShowNotice(AText);
end;

procedure TMainForm.DockChanged(Sender: TObject);
begin
  if not Assigned(FSettings) or not Assigned(FDock) then
    Exit;
  { До LoadItems контрол ещё пуст: не затирать стартовый набор. }
  if FStartupPhase < 2 then
    Exit;
  FSettings.DockSeedPending := False;
  { CollectState — быстро (только массивы в памяти). }
  FDock.CollectState(FSettings.DockItems, FSettings.DockItemX,
    FSettings.DockKinds, FSettings.DockCaptions, FSettings.DockIcons,
    FSettings.DockIconLocked);
  FSettings.DockAlign := FDock.AlignMode;
  FSettings.DockShowSeparators := FDock.ShowSeparators;
  { Запись INI в фоне — не блокирует UI после reorder/drop. }
  FSettings.SaveDockAsync;
  MarkSessionDirty;
end;

procedure TMainForm.MarkSessionDirty;
begin
  if (csDestroying in ComponentState) or not Assigned(FSettings) then
    Exit;
  if FStartupPhase < 2 then
    Exit;
  FSessionDirty := True;
  if Assigned(FSessionTimer) and not FSessionTimer.Enabled then
    FSessionTimer.Enabled := True;
end;

procedure TMainForm.SnapshotSession;
var
  HI: Integer;
begin
  if not Assigned(FSettings) then
    Exit;
  if Assigned(FSearchHist) then
  begin
    SetLength(FSettings.SearchHistory, FSearchHist.Count);
    for HI := 0 to FSearchHist.Count - 1 do
      FSettings.SearchHistory[HI] := FSearchHist[HI];
  end;
  PersistWindowState;
  FSettings.SplitterPos := FLeftPanelRatio;
  if FActivePanel = FRightPanel then
    FSettings.ActivePanel := 1
  else
    FSettings.ActivePanel := 0;
  if (FStartupPhase >= 2) and Assigned(FLeftPanel) then
    FLeftPanel.CaptureTabs(FSettings.Left);
  if (FStartupPhase >= 2) and Assigned(FRightPanel) then
    FRightPanel.CaptureTabs(FSettings.Right);
  if (FStartupPhase >= 2) and Assigned(FDock) then
  begin
    FDock.CollectState(FSettings.DockItems, FSettings.DockItemX,
      FSettings.DockKinds, FSettings.DockCaptions, FSettings.DockIcons,
      FSettings.DockIconLocked);
    FSettings.DockAlign := FDock.AlignMode;
    FSettings.DockShowSeparators := FDock.ShowSeparators;
    FSettings.DockSeedPending := False;
  end;
  FSessionDirty := False;
  FSessionSnap := True;
  if Assigned(FSessionTimer) then
    FSessionTimer.Enabled := False;
end;

procedure TMainForm.SessionTimerTick(Sender: TObject);
begin
  if Assigned(FSessionTimer) then
    FSessionTimer.Enabled := False;
  if (csDestroying in ComponentState) or not FSessionDirty then
    Exit;
  SnapshotSession;
  if Assigned(FSettings) then
  try
    FSettings.SaveSessionAsync;
  except
  end;
end;

procedure TMainForm.KickFolderSizes;
begin
  AllowFolderSizeWalks;
  if Assigned(FLeftPanel) then
    FLeftPanel.ArmFolderSizes;
  if Assigned(FRightPanel) then
    FRightPanel.ArmFolderSizes;
end;

function TMainForm.MakeMidButton(const AIcon, AHint: string;
  AOnClick: TNotifyEvent): TFluentButton;
begin
  Result := CreateFluentButton(Self, FMidGroup, AIcon, '', fbkSubtle, 32, AOnClick);
  Result.Align := TAlignLayout.None;
  Result.Height := 32;
  Result.Hint := AHint;
  Result.ShowHint := True;
end;

function TMainForm.MakeSideSplitter(AAlign: TAlignLayout): TRectangle;
var
  Grip: TRectangle;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := FCenterCluster;
  Result.Align := AAlign;
  Result.Width := SPLITTER_WIDTH;
  Result.Margins.Rect := TRectF.Create(0, MIDBAR_TOP, 0, MIDBAR_BOTTOM);
  Result.Stroke.Kind := TBrushKind.None;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.Fill.Color := TAlphaColors.Null;
  Result.HitTest := True;
  Result.Cursor := crHSplit;
  Result.XRadius := 3;
  Result.YRadius := 3;
  Result.AutoCapture := True;
  Result.OnMouseDown := SplitterMouseDown;
  Result.OnMouseMove := SplitterMouseMove;
  Result.OnMouseUp := SplitterMouseUp;
  Result.OnMouseEnter := SplitterMouseEnter;
  Result.OnMouseLeave := SplitterMouseLeave;

  Grip := TRectangle.Create(Self);
  Grip.Parent := Result;
  Grip.Align := TAlignLayout.Center;
  Grip.Width := 2;
  Grip.Height := 28;
  Grip.HitTest := False;
  Grip.Stroke.Kind := TBrushKind.None;
  Grip.Fill.Kind := TBrushKind.Solid;
  Grip.XRadius := 1;
  Grip.YRadius := 1;
  Grip.Tag := 3;
  if AAlign = TAlignLayout.Left then
    FSplitGripL := Grip
  else
    FSplitGripR := Grip;
end;

type
  TOpRow = class
  public
    Id: Integer;
    Box: TRectangle;
    Ico: TText;
    Title: TText;
    Sub: TText;
    Pct: TText;
    Track: TRectangle;
    Fill: TRectangle;
    XBtn: TRectangle;
  end;

function MeasurePillText(const AText: string; ASize: Single): Single;
var
  L: TTextLayout;
begin
  Result := 40;
  if AText = '' then
    Exit;
  L := TTextLayoutManager.DefaultTextLayout.Create;
  try
    L.Font.Family := FluentFontFamily;
    L.Font.Size := ASize;
    L.Text := AText;
    Result := L.TextWidth;
  finally
    L.Free;
  end;
end;

function OpCountWord(N: Integer): string;
begin
  Result := LCount(N, 'main.ops.one', 'main.ops.few', 'main.ops.many');
end;

procedure TMainForm.OpHubChanged(Sender: TObject);
begin
  RefreshOpUi;
end;

procedure TMainForm.OpTick(Sender: TObject);
begin
  FileOpHubPumpViews;
  RefreshOpUi;
end;

procedure TMainForm.RefreshOpUi;
begin
  LayoutOpPill;
  if Assigned(FOpPop) and FOpPop.IsOpen then
    SyncOpRows;
end;

function TMainForm.OpPillOnRail: Boolean;
begin
  Result := Assigned(FOpPill) and
    ((FOpPill.Parent = FMidGroup) or (FOpPill.Parent = FMidBar));
end;

procedure TMainForm.ParkOpPill;
begin
  if not Assigned(FOpPill) or not Assigned(FMidGroup) then
    Exit;
  if FOpPill.Parent <> FMidGroup then
    FOpPill.Parent := FMidGroup;
  FOpPill.SetBounds(4, FOpPillTop, MIDBAR_WIDTH - 8, OP_PILL_H);
  FOpPill.Visible := False;
end;

procedure TMainForm.LayoutMidButtons;
var
  Y0, Avail, Y: Single;
begin
  if not Assigned(FMidBar) or not Assigned(FMidGroup) then
    Exit;
  Y0 := MID_BTN_Y0;
  if FMidStackH <= 0 then
    FMidStackH := FMidGroup.Height;
  Avail := FMidBar.Height - Y0;
  if Avail < FMidStackH then
    Y := Y0
  else
    Y := Y0 + (Avail - FMidStackH) / 2;
  FMidGroup.Align := TAlignLayout.None;
  FMidGroup.SetBounds(0, Y, MIDBAR_WIDTH, FMidStackH);
end;

procedure TMainForm.OpPillClick(Sender: TObject);
begin
  ToggleOpPop;
end;

procedure TMainForm.ToggleOpPop;
begin
  if not Assigned(FOpPop) then
    Exit;
  if FOpPop.IsOpen then
    FOpPop.IsOpen := False
  else
    OpenOpPop;
end;

function TMainForm.OpenBackgroundKind(AKind: TFileOpKind): Boolean;
begin
  Result := (GetFileOpMode = fomVibe) and FileOpHubHasBackground(AKind);
  if Result then
    ToggleOpPop;
end;

procedure TMainForm.OpPillPaint(Sender: TObject; Canvas: TCanvas);
var
  R: TRectF;
  V: TFileOpJobView;
  StartA, Sweep: Single;
begin
  if not Assigned(FOpPillArc) or not FOpPillArc.Visible then
    Exit;
  if FileOpHubCount <> 1 then
    Exit;
  V := FileOpHubView(0);
  if V.Danger then
    Exit;
  R := TRectF.Create(2, 2, FOpPillArc.Width - 2, FOpPillArc.Height - 2);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := 2;
  Canvas.Stroke.Color := FColors.SelectionColor;
  Canvas.Fill.Kind := TBrushKind.None;
  if V.Indeterminate then
  begin
    StartA := FileOpHubSpin;
    Sweep := 90;
  end
  else
  begin
    StartA := -90;
    Sweep := 360 * V.Percent / 100;
    if Sweep < 2 then
      Sweep := 2;
  end;
  Canvas.DrawArc(R.CenterPoint, TPointF.Create(R.Width / 2, R.Height / 2),
    StartA, Sweep, 1);
end;

procedure TMainForm.OpRowEnter(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FColors.ItemHover;
end;

procedure TMainForm.OpRowLeave(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := TAlphaColors.Null;
end;

procedure TMainForm.OpRowClick(Sender: TObject);
var
  Id: Integer;
begin
  if not (Sender is TFmxObject) then
    Exit;
  Id := TFmxObject(Sender).Tag;
  if Assigned(FOpPop) then
    FOpPop.IsOpen := False;
  FileOpHubRestore(Id);
end;

procedure TMainForm.OpRowCloseClick(Sender: TObject);
var
  Id: Integer;
begin
  if not (Sender is TFmxObject) then
    Exit;
  Id := TFmxObject(Sender).Tag;
  FileOpHubDismiss(Id);
  RefreshOpUi;
end;

procedure TMainForm.OpWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  MaxY: Single;
begin
  Handled := True;
  if FileOpHubCount <= 1 then
    Exit;
  if WheelDelta > 0 then
    FOpScrollY := FOpScrollY - 56
  else
    FOpScrollY := FOpScrollY + 56;
  MaxY := FileOpHubCount * 56 - FOpViewH;
  if MaxY < 0 then
    MaxY := 0;
  if FOpScrollY < 0 then
    FOpScrollY := 0;
  if FOpScrollY > MaxY then
    FOpScrollY := MaxY;
  if Assigned(FOpBody) then
    FOpBody.Position.Y := -FOpScrollY;
end;

procedure TMainForm.SyncOpRows;
const
  RowH = 56;
  BodyW = 320;
var
  I, N: Integer;
  V: TFileOpJobView;
  R: TOpRow;
  Same: Boolean;
  XCap: TText;
  BarW: Single;
begin
  if not Assigned(FOpBody) or not Assigned(FOpRows) then
    Exit;
  N := FileOpHubCount;
  Same := FOpRows.Count = N;
  if Same then
    for I := 0 to N - 1 do
      if TOpRow(FOpRows[I]).Id <> FileOpHubView(I).Id then
      begin
        Same := False;
        Break;
      end;
  if not Same then
  begin
    for I := FOpRows.Count - 1 downto 0 do
    begin
      R := TOpRow(FOpRows[I]);
      FreeAndNil(R.Box);
    end;
    FOpRows.Clear;
    for I := 0 to N - 1 do
    begin
      V := FileOpHubView(I);
      R := TOpRow.Create;
      R.Id := V.Id;
      R.Box := TRectangle.Create(Self);
      R.Box.Parent := FOpBody;
      R.Box.Align := TAlignLayout.None;
      R.Box.Stroke.Kind := TBrushKind.None;
      R.Box.Fill.Color := TAlphaColors.Null;
      R.Box.HitTest := True;
      R.Box.Cursor := crHandPoint;
      R.Box.Tag := V.Id;
      R.Box.OnClick := OpRowClick;
      R.Box.OnMouseEnter := OpRowEnter;
      R.Box.OnMouseLeave := OpRowLeave;
      R.Box.OnMouseWheel := OpWheel;

      R.Ico := TText.Create(Self);
      R.Ico.Parent := R.Box;
      R.Ico.Align := TAlignLayout.None;
      R.Ico.HitTest := False;
      R.Ico.SetBounds(8, 8, 18, 18);
      R.Ico.TextSettings.Font.Family := FluentIconFamily;
      R.Ico.TextSettings.Font.Size := 14;
      R.Ico.TextSettings.HorzAlign := TTextAlign.Center;
      R.Ico.TextSettings.VertAlign := TTextAlign.Center;

      R.Title := TText.Create(Self);
      R.Title.Parent := R.Box;
      R.Title.Align := TAlignLayout.None;
      R.Title.HitTest := False;
      R.Title.SetBounds(32, 6, BodyW - 120, 18);
      ApplyFluentText(R.Title, 13, True);
      R.Title.TextSettings.HorzAlign := TTextAlign.Leading;
      R.Title.TextSettings.VertAlign := TTextAlign.Center;
      R.Title.TextSettings.Trimming := TTextTrimming.Character;
      R.Title.TextSettings.WordWrap := False;

      R.Sub := TText.Create(Self);
      R.Sub.Parent := R.Box;
      R.Sub.Align := TAlignLayout.None;
      R.Sub.HitTest := False;
      R.Sub.SetBounds(32, 24, BodyW - 48, 16);
      ApplyFluentText(R.Sub, 11, False);
      R.Sub.TextSettings.HorzAlign := TTextAlign.Leading;
      R.Sub.TextSettings.VertAlign := TTextAlign.Center;
      R.Sub.TextSettings.Trimming := TTextTrimming.Character;
      R.Sub.TextSettings.WordWrap := False;

      R.Pct := TText.Create(Self);
      R.Pct.Parent := R.Box;
      R.Pct.Align := TAlignLayout.None;
      R.Pct.HitTest := False;
      R.Pct.SetBounds(BodyW - 78, 8, 42, 16);
      ApplyFluentText(R.Pct, 11, False);
      R.Pct.TextSettings.HorzAlign := TTextAlign.Trailing;
      R.Pct.TextSettings.VertAlign := TTextAlign.Center;

      R.XBtn := TRectangle.Create(Self);
      R.XBtn.Parent := R.Box;
      R.XBtn.Align := TAlignLayout.None;
      R.XBtn.SetBounds(BodyW - 30, 6, 22, 22);
      R.XBtn.XRadius := 4;
      R.XBtn.YRadius := 4;
      R.XBtn.Stroke.Kind := TBrushKind.None;
      R.XBtn.Fill.Color := TAlphaColors.Null;
      R.XBtn.HitTest := True;
      R.XBtn.Cursor := crHandPoint;
      R.XBtn.Tag := V.Id;
      R.XBtn.OnClick := OpRowCloseClick;
      XCap := TText.Create(Self);
      XCap.Parent := R.XBtn;
      XCap.Align := TAlignLayout.Client;
      XCap.HitTest := False;
      XCap.Text := #$E8BB;
      XCap.TextSettings.Font.Family := FluentIconFamily;
      XCap.TextSettings.Font.Size := 10;
      XCap.TextSettings.HorzAlign := TTextAlign.Center;
      XCap.TextSettings.VertAlign := TTextAlign.Center;

      R.Track := TRectangle.Create(Self);
      R.Track.Parent := R.Box;
      R.Track.Align := TAlignLayout.None;
      R.Track.SetBounds(32, 48, BodyW - 44, 3);
      R.Track.XRadius := 1.5;
      R.Track.YRadius := 1.5;
      R.Track.Stroke.Kind := TBrushKind.None;
      R.Track.HitTest := False;
      R.Track.ClipChildren := True;
      R.Fill := TRectangle.Create(Self);
      R.Fill.Parent := R.Track;
      R.Fill.Align := TAlignLayout.Left;
      R.Fill.Width := 0;
      R.Fill.Stroke.Kind := TBrushKind.None;
      R.Fill.HitTest := False;
      FOpRows.Add(R);
    end;
  end;

  FOpBody.Width := BodyW;
  FOpBody.Height := N * RowH;
  if FOpBody.Position.Y <> -FOpScrollY then
    FOpBody.Position.Y := -FOpScrollY;
  for I := 0 to FOpRows.Count - 1 do
  begin
    R := TOpRow(FOpRows[I]);
    if I > N - 1 then
      Continue;
    V := FileOpHubView(I);
    R.Box.SetBounds(0, I * RowH, BodyW, RowH);
    R.Ico.Text := V.IconText;
    R.Title.Text := V.Title;
    R.Sub.Text := V.Detail;
    R.Pct.Text := V.PercentText;
    R.Title.TextSettings.FontColor := FColors.TextColor;
    R.Sub.TextSettings.FontColor := FColors.SubTextColor;
    R.Pct.TextSettings.FontColor := FColors.SubTextColor;
    R.Ico.TextSettings.FontColor := FColors.TextColor;
    if Assigned(R.XBtn) and (R.XBtn.ChildrenCount > 0) and
       (R.XBtn.Children[0] is TText) then
      TText(R.XBtn.Children[0]).TextSettings.FontColor := FColors.SubTextColor;
    if V.Danger then
    begin
      R.Title.TextSettings.FontColor := FColors.DangerColor;
      R.Fill.Fill.Color := FColors.DangerColor;
    end
    else
      R.Fill.Fill.Color := FColors.SelectionColor;
    R.Track.Fill.Color := FColors.ControlFill;
    BarW := R.Track.Width;
    if V.State = jsQueued then
      R.Fill.Width := 0
    else if V.Indeterminate then
      R.Fill.Width := BarW * 0.25
    else
      R.Fill.Width := BarW * V.Percent / 100;
  end;
end;

procedure TMainForm.OpenOpPop;
const
  BodyW = 320;
  RowH = 56;
  PadL = 18;
  PadT = 14;
  PadR = 18;
  PadB = 22;
var
  N, Vis: Integer;
  H, Room: Single;
  OpenRight: Boolean;
begin
  N := FileOpHubCount;
  if (N = 0) or not Assigned(FOpPop) or not Assigned(FOpPill) then
    Exit;
  FOpScrollY := 0;
  Vis := N;
  if Vis > 5 then
    Vis := 5;
  H := Vis * RowH;
  if not OpPillOnRail then
  begin
    Room := FOpPill.AbsoluteRect.Top - 12;
    if (Room > RowH) and (H > Room) then
      H := Room;
  end;
  FOpViewH := H;
  SyncOpRows;
  FOpPop.Width := BodyW + PadL + PadR;
  FOpPop.Height := H + PadT + PadB;
  FOpPop.PlacementTarget := FOpPill;
  if OpPillOnRail then
  begin
    OpenRight := Assigned(FActivePanel) and (FActivePanel = FLeftPanel);
    if OpenRight then
      FOpPop.Placement := TPlacement.RightCenter
    else
      FOpPop.Placement := TPlacement.LeftCenter;
    FOpPop.HorizontalOffset := -(PadL - 2);
    FOpPop.VerticalOffset := (PadB - PadT) / 2;
  end
  else
  begin
    FOpPop.Placement := TPlacement.Top;
    FOpPop.HorizontalOffset := 0;
    FOpPop.VerticalOffset := -(PadB - 4);
  end;
  FOpPop.IsOpen := True;
end;

procedure TMainForm.LayoutOpPill;
var
  N, I, RunN, QueN, BadN: Integer;
  V: TFileOpJobView;
  OnRail: Boolean;
  Cap: string;
  W, Foot, TopY, BtnLeft, TextEnd, GapL, GapR, X: Single;
  Panel: TFilePanel;
  Host: TFmxObject;

  procedure ClearFootInsets;
  begin
    if Assigned(FLeftPanel) then
      FLeftPanel.SetStatusRightInset(4);
    if Assigned(FRightPanel) then
      FRightPanel.SetStatusRightInset(4);
  end;

begin
  if not Assigned(FOpPill) then
    Exit;
  N := FileOpHubCount;
  if N = 0 then
  begin
    if Assigned(FOpPop) and FOpPop.IsOpen then
      FOpPop.IsOpen := False;
    ClearFootInsets;
    ParkOpPill;
    LayoutMidButtons;
    Exit;
  end;
  RunN := 0;
  QueN := 0;
  BadN := 0;
  for I := 0 to N - 1 do
  begin
    V := FileOpHubView(I);
    if V.Danger then
      Inc(BadN)
    else if V.State = jsQueued then
      Inc(QueN)
    else
      Inc(RunN);
  end;
  OnRail := Assigned(FMidBar) and FMidBar.Visible and
    not (Assigned(FSettings) and not FSettings.ShowMidBar);
  FOpPill.Visible := True;
  FOpPill.Align := TAlignLayout.None;
  if OnRail then
  begin
    if FOpPill.Parent <> FMidGroup then
      FOpPill.Parent := FMidGroup;
    FOpPill.SetBounds(4, FOpPillTop, MIDBAR_WIDTH - 8, OP_PILL_H);
    FOpPillText.Visible := False;
    FOpPillArc.Visible := (N = 1) and (BadN = 0);
    FOpPillIcon.Visible := True;
    FOpPillIcon.SetBounds(0, 0, FOpPill.Width, FOpPill.Height);
    if N = 1 then
    begin
      V := FileOpHubView(0);
      FOpPillIcon.Text := V.IconText;
      FOpPillIcon.TextSettings.Font.Family := FluentIconFamily;
      FOpPillIcon.TextSettings.Font.Size := 14;
      FOpPillIcon.TextSettings.Font.Style := [];
      if V.PercentText <> '' then
        FOpPill.Hint := V.Title + ' · ' + V.PercentText
      else
        FOpPill.Hint := V.Title;
    end
    else
    begin
      if BadN > 0 then
        FOpPillIcon.Text := '!'
      else
        FOpPillIcon.Text := IntToStr(N);
      FOpPillIcon.TextSettings.Font.Family := FluentFontFamily;
      FOpPillIcon.TextSettings.Font.Size := 12;
      FOpPillIcon.TextSettings.Font.Style := [TFontStyle.fsBold];
      FOpPill.Hint := L('main.ops.hint');
    end;
    ClearFootInsets;
  end
  else
  begin
    Panel := FActivePanel;
    if not Assigned(Panel) then
      Panel := FLeftPanel;
    Host := nil;
    Foot := 32;
    BtnLeft := 0;
    if Assigned(Panel) then
    begin
      Host := Panel.FooterHost;
      Foot := Panel.FooterOffset;
      BtnLeft := Panel.ViewButtonsLeft;
    end;
    if Host = nil then
    begin
      if Assigned(Panel) then
        Host := Panel.CardHost;
      if Host = nil then
      begin
        FOpPill.Visible := False;
        ClearFootInsets;
        LayoutMidButtons;
        Exit;
      end;
    end;
    if FOpPill.Parent <> Host then
      FOpPill.Parent := Host;
    if (BadN > 0) and (N = 1) then
    begin
      V := FileOpHubView(0);
      Cap := V.Title;
    end
    else if N = 1 then
    begin
      V := FileOpHubView(0);
      Cap := V.Title;
      if V.PercentText <> '' then
        Cap := Cap + '  ' + V.PercentText;
    end
    else if (RunN = 0) and (BadN = 0) then
      Cap := Lf('main.ops.queue', [QueN])
    else
      Cap := OpCountWord(N);
    W := 36 + MeasurePillText(Cap, 12);
    if W < 132 then
      W := 132;
    if W > 220 then
      W := 220;
    if Panel.FooterHost = nil then
    begin
      ClearFootInsets;
      TopY := Panel.Height - Foot - 8 - 28;
      if TopY < 8 then
        TopY := 8;
      FOpPill.SetBounds(10, TopY, W, 28);
    end
    else
    begin
      if (BtnLeft < W + 16) and (Host is TControl) and
         (TControl(Host).Width > 140) then
        BtnLeft := TControl(Host).Width - 102;
      TextEnd := 12 + MeasurePillText(Panel.StatusCaption, 11);
      if TextEnd > BtnLeft - 16 then
        TextEnd := BtnLeft - 16;
      if TextEnd < 12 then
        TextEnd := 12;
      GapL := TextEnd + 8;
      GapR := BtnLeft - 8;
      if GapR - GapL >= W then
        X := GapL + (GapR - GapL - W) / 2
      else
      begin
        X := GapR - W;
        if W > GapR - 8 then
          W := GapR - 8;
        if W < 96 then
          W := 96;
        X := GapR - W;
      end;
      if X < 6 then
        X := 6;
      TopY := (Foot - 28) / 2;
      if TopY < 1 then
        TopY := 1;
      FOpPill.SetBounds(X, TopY, W, 28);
      if Assigned(FLeftPanel) and (FLeftPanel <> Panel) then
        FLeftPanel.SetStatusRightInset(4);
      if Assigned(FRightPanel) and (FRightPanel <> Panel) then
        FRightPanel.SetStatusRightInset(4);
      if Host is TControl then
        Panel.SetStatusRightInset(TControl(Host).Width - X + 8)
      else
        Panel.SetStatusRightInset(BtnLeft - X + 8);
    end;
    FOpPillArc.Visible := False;
    FOpPillIcon.Visible := True;
    FOpPillIcon.SetBounds(8, 0, 18, 28);
    FOpPillIcon.TextSettings.Font.Family := FluentIconFamily;
    FOpPillIcon.TextSettings.Font.Size := 14;
    FOpPillIcon.TextSettings.Font.Style := [];
    if N = 1 then
      FOpPillIcon.Text := FileOpHubView(0).IconText
    else if BadN > 0 then
      FOpPillIcon.Text := '!'
    else
      FOpPillIcon.Text := #$E8B7;
    FOpPillText.Visible := True;
    FOpPillText.SetBounds(30, 0, W - 40, 28);
    FOpPillText.Text := Cap;
    if N = 1 then
      FOpPill.Hint := Cap
    else
      FOpPill.Hint := L('main.ops.hint');
  end;
  if BadN > 0 then
  begin
    FOpPill.Fill.Color := FColors.DangerColor;
    FOpPillIcon.TextSettings.FontColor := FColors.OnAccentTextColor;
    FOpPillText.TextSettings.FontColor := FColors.OnAccentTextColor;
  end
  else if (not OnRail) or (N >= 2) then
  begin
    FOpPill.Fill.Color := FColors.AccentSubtle;
    FOpPillIcon.TextSettings.FontColor := FColors.TextColor;
    FOpPillText.TextSettings.FontColor := FColors.TextColor;
  end
  else
  begin
    FOpPill.Fill.Color := FColors.ControlFill;
    FOpPillIcon.TextSettings.FontColor := FColors.TextColor;
    FOpPillText.TextSettings.FontColor := FColors.TextColor;
  end;
  FOpPill.Stroke.Color := FColors.CardStroke;
  FOpPill.BringToFront;
  if FOpPillArc.Visible then
    FOpPillArc.Repaint;
  LayoutMidButtons;
end;

procedure TMainForm.BuildOpPill;
var
  Fx: TShadowEffect;
begin
  if not Assigned(FOpRows) then
    FOpRows := TObjectList<TObject>.Create(True);
  FOpPill := TRectangle.Create(Self);
  FOpPill.Parent := FMidGroup;
  FOpPill.Align := TAlignLayout.None;
  FOpPill.Visible := False;
  FOpPill.SetBounds(4, FOpPillTop, MIDBAR_WIDTH - 8, OP_PILL_H);
  FOpPill.HitTest := True;
  FOpPill.Cursor := crHandPoint;
  FOpPill.XRadius := 8;
  FOpPill.YRadius := 8;
  FOpPill.Stroke.Kind := TBrushKind.Solid;
  FOpPill.Stroke.Thickness := 1;
  FOpPill.Fill.Color := FColors.ControlFill;
  FOpPill.OnClick := OpPillClick;
  FOpPill.ShowHint := True;
  FOpPill.Hint := L('main.ops.hint');

  FOpPillArc := TPaintBox.Create(Self);
  FOpPillArc.Parent := FOpPill;
  FOpPillArc.Align := TAlignLayout.Client;
  FOpPillArc.HitTest := False;
  FOpPillArc.OnPaint := OpPillPaint;

  FOpPillIcon := TText.Create(Self);
  FOpPillIcon.Parent := FOpPill;
  FOpPillIcon.Align := TAlignLayout.None;
  FOpPillIcon.HitTest := False;
  FOpPillIcon.TextSettings.HorzAlign := TTextAlign.Center;
  FOpPillIcon.TextSettings.VertAlign := TTextAlign.Center;

  FOpPillText := TText.Create(Self);
  FOpPillText.Parent := FOpPill;
  FOpPillText.Align := TAlignLayout.None;
  FOpPillText.HitTest := False;
  FOpPillText.Visible := False;
  ApplyFluentText(FOpPillText, 12, False);
  FOpPillText.TextSettings.HorzAlign := TTextAlign.Leading;
  FOpPillText.TextSettings.VertAlign := TTextAlign.Center;
  FOpPillText.TextSettings.Trimming := TTextTrimming.Character;
  FOpPillText.TextSettings.WordWrap := False;

  FOpPop := TPopup.Create(Self);
  FOpPop.Parent := Self;
  FOpPop.Placement := TPlacement.RightCenter;
  FOpHost := TRectangle.Create(Self);
  FOpHost.Parent := FOpPop;
  FOpHost.Align := TAlignLayout.Client;
  FOpHost.Margins.Rect := TRectF.Create(18, 14, 18, 22);
  FOpHost.XRadius := 8;
  FOpHost.YRadius := 8;
  FOpHost.Stroke.Kind := TBrushKind.Solid;
  FOpHost.Stroke.Thickness := 1;
  FOpHost.Fill.Color := FColors.CardBackground;
  FOpHost.Stroke.Color := FColors.CardStroke;
  FOpHost.ClipChildren := True;
  FOpHost.OnMouseWheel := OpWheel;
  Fx := TShadowEffect.Create(FOpHost);
  Fx.Parent := FOpHost;
  ApplyFluentShadow(Fx, FColors.IsDark);

  FOpBody := TLayout.Create(Self);
  FOpBody.Parent := FOpHost;
  FOpBody.Align := TAlignLayout.None;
  FOpBody.SetBounds(0, 0, 320, 0);
  FOpBody.HitTest := False;
  FOpBody.OnMouseWheel := OpWheel;

  FOpTimer := TTimer.Create(Self);
  FOpTimer.Interval := 150;
  FOpTimer.OnTimer := OpTick;
  FOpTimer.Enabled := True;
end;

procedure TMainForm.BuildMidBar;
const
  BTN_H = 32;
  BTN_GAP = 3;
  DIV_GAP = 8;
var
  Y: Single;

  procedure PlaceBtn(ABtn: TFluentButton);
  begin
    ABtn.SetBounds(4, Y, MIDBAR_WIDTH - 8, BTN_H);
    Y := Y + BTN_H + BTN_GAP;
  end;

  procedure AddDivider;
  var
    Divider: TRectangle;
  begin
    Y := Y + DIV_GAP - BTN_GAP;
    Divider := TRectangle.Create(Self);
    Divider.Parent := FMidGroup;
    Divider.Align := TAlignLayout.None;
    Divider.SetBounds(6, Y, MIDBAR_WIDTH - 12, 1);
    Divider.Stroke.Kind := TBrushKind.None;
    Divider.Fill.Kind := TBrushKind.Solid;
    Divider.HitTest := False;
    Divider.Tag := 2;
    Y := Y + 1 + DIV_GAP;
  end;

begin
  FMidBar := TRectangle.Create(Self);
  FMidBar.Parent := FCenterCluster;
  FMidBar.Align := TAlignLayout.Client;
  FMidBar.Margins.Rect := TRectF.Create(0, MIDBAR_TOP, 0, MIDBAR_BOTTOM);
  FMidBar.Stroke.Kind := TBrushKind.None;
  FMidBar.Fill.Kind := TBrushKind.Solid;
  FMidBar.XRadius := 6;
  FMidBar.YRadius := 6;
  FMidBar.HitTest := True;
  FMidBar.ClipChildren := True;

  FMidGroup := TLayout.Create(Self);
  FMidGroup.Parent := FMidBar;
  FMidGroup.Align := TAlignLayout.None;
  FMidGroup.Width := MIDBAR_WIDTH;

  Y := 0;
  FCmdCopy := MakeMidButton('', L('cmd.copy'), OnBtnCopyClick);
  PlaceBtn(FCmdCopy);
  FCmdMove := MakeMidButton('', L('cmd.move'), OnBtnMoveClick);
  PlaceBtn(FCmdMove);

  FCmdRename := MakeMidButton('', L('cmd.rename'), OnBtnRenameClick);
  PlaceBtn(FCmdRename);
  FCmdArchive := MakeMidButton('', L('cmd.archive'), OnBtnArchiveClick);
  PlaceBtn(FCmdArchive);
  AddDivider;
  FCmdDelete := MakeMidButton('', L('cmd.delete'), OnBtnDeleteClick);
  PlaceBtn(FCmdDelete);
  AddDivider;
  FCmdNewFolder := MakeMidButton('', L('cmd.newfolder'), OnBtnNewFolderClick);
  PlaceBtn(FCmdNewFolder);
  AddDivider;
  FCmdSearch := MakeMidButton('', L('cmd.search'), OnBtnSearchClick);
  FCmdSearch.ClickWhileBusy := True;
  PlaceBtn(FCmdSearch);
  FCmdSelect := MakeMidButton(#$E9D5, L('cmd.select'), OnBtnSelectClick);
  PlaceBtn(FCmdSelect);
  FCmdRefresh := MakeMidButton('', L('cmd.refresh'), OnBtnRefreshClick);
  PlaceBtn(FCmdRefresh);
  AddDivider;
  FCmdQuickView := MakeMidButton('', L('cmd.quickview'), OnBtnQuickViewToggle);
  PlaceBtn(FCmdQuickView);
  FCmdDetails := MakeMidButton('', L('cmd.details'), OnBtnViewDetailsClick);
  PlaceBtn(FCmdDetails);
  FCmdTiles := MakeMidButton('', L('cmd.tiles'), OnBtnViewTilesClick);
  PlaceBtn(FCmdTiles);
  { Место пилюли занято всегда: показ только Visible, кнопки не прыгают. }
  AddDivider;
  FOpPillTop := Y;
  Y := Y + BTN_H + BTN_GAP;

  FMidGroup.Height := Y;
  FMidStackH := Y;
  BuildOpPill;
  ApplyMinWindowHeight;

  FLastSelectMask := '*.*';
  FSelMenu := TFluentPopupMenu.Create(Self);
  FSelMenu.Parent := Self;
  BuildSelMenu;
end;

procedure TMainForm.BuildSelMenu;
  function Mark(AOn: Boolean): string;
  begin
    if AOn then
      Result := #$2713
    else
      Result := '';
  end;
begin
  if FSelMenu = nil then
    Exit;
  FSelMenu.ClearItems;
  FSelMenu.AddItem(L('main.sel.all'), 'Ctrl+A', OnSelAll);
  FSelMenu.AddItem(L('main.sel.compare'), '', OnSelCompare);
  FSelMenu.AddSeparator;
  FSelMenu.AddItem(L('main.sel.folders'), '', OnSelFolders);
  FSelMenu.AddItem(L('main.sel.files'), '', OnSelFiles);
  FSelMenu.AddItem(L('main.sel.unext'), 'Alt+-', OnUnselExt);
  FSelMenu.AddItem(L('main.sel.ext'), 'Alt++', OnSelExt);
  FSelMenu.AddItem(L('main.sel.unmask'), '-', OnUnselMask);
  FSelMenu.AddItem(L('main.sel.mask'), '+', OnSelMask);
  FSelMenu.AddSeparator;
  FSelMenu.AddItem(L('main.sel.invert'), '*', OnSelInvert);
  FSelMenu.AddItem(L('main.sel.none'), 'Ctrl+-', OnSelNone);
  FSelMenu.AddSeparator;
  FSelMenu.AddItem(L('set.sel.vibe'),
    Mark(FSettings.MouseSelectMode <> msmExplorer), OnSelModeVibe);
  FSelMenu.AddItem(L('set.sel.explorer'),
    Mark(FSettings.MouseSelectMode = msmExplorer), OnSelModeExplorer);
end;

procedure TMainForm.SetMouseSelectMode(AExplorer: Boolean);
var
  Mode: TMouseSelectMode;
begin
  if AExplorer then
    Mode := msmExplorer
  else
    Mode := msmVibe;
  if FSettings.MouseSelectMode = Mode then
    Exit;
  FSettings.MouseSelectMode := Mode;
  if Assigned(FLeftPanel) then
    FLeftPanel.SetExplorerMouse(AExplorer);
  if Assigned(FRightPanel) then
    FRightPanel.SetExplorerMouse(AExplorer);
  FSettings.SaveAsync;
end;

procedure TMainForm.PanelMouseModePick(Sender: TObject; AExplorer: Boolean);
begin
  SetMouseSelectMode(AExplorer);
end;

procedure TMainForm.OnSelModeExplorer(Sender: TObject);
begin
  SetMouseSelectMode(True);
end;

procedure TMainForm.OnSelModeVibe(Sender: TObject);
begin
  SetMouseSelectMode(False);
end;

procedure TMainForm.BuildFunctionBar;
const
  Keys: array[0..6] of string = ('F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8');
  CapKeys: array[0..6] of string = (
    'fn.rename', 'fn.view', 'fn.search', 'fn.copy', 'fn.move',
    'fn.newfolder', 'fn.delete');
var
  I: Integer;
  Handlers: array[0..6] of TNotifyEvent;
begin
  FFnBar := TRectangle.Create(Self);
  FFnBar.Parent := Self;
  FFnBar.Align := TAlignLayout.Bottom;
  FFnBar.Height := FNBAR_HEIGHT;
  FFnBar.Stroke.Kind := TBrushKind.None;
  FFnBar.Fill.Kind := TBrushKind.Solid;
  FFnBar.Padding.Rect := TRectF.Create(0, 5, 0, 6);

  Handlers[0] := OnBtnRenameClick;
  Handlers[1] := OnBtnViewClick;
  Handlers[2] := OnBtnSearchClick;
  Handlers[3] := OnBtnCopyClick;
  Handlers[4] := OnBtnMoveClick;
  Handlers[5] := OnBtnNewFolderClick;
  Handlers[6] := OnBtnDeleteClick;

  for I := 0 to 6 do
  begin
    FFnCells[I] := TLayout.Create(Self);
    FFnCells[I].Parent := FFnBar;
    FFnCells[I].Align := TAlignLayout.None;
    FFnCells[I].Width := 140;
    FFnCells[I].Height := 32;

    FFnButtons[I] := TFluentButton.Create(Self);
    FFnButtons[I].Setup(FFnCells[I], '', L(CapKeys[I]), fbkKey, Handlers[I]);
    FFnButtons[I].Align := TAlignLayout.Client;
    FFnButtons[I].Margins.Rect := TRectF.Create(3, 0, 3, 0);
    FFnButtons[I].SetHotkey(Keys[I]);
  end;
end;

procedure TMainForm.BuildWorkArea;
begin
  FWorkArea := TLayout.Create(Self);
  FWorkArea.Parent := Self;
  FWorkArea.Align := TAlignLayout.Client;
  FWorkArea.OnResize := WorkAreaResize;

  FLeftPanel := TFilePanel.Create(Self);
  FLeftPanel.Parent := FWorkArea;
  FLeftPanel.Align := TAlignLayout.None;
  FLeftPanel.OnPathChanged := LeftPanelPathChanged;
  FLeftPanel.OnQuickView := PanelQuickView;
  FLeftPanel.OnCursorChange := PanelCursorChanged;
  FLeftPanel.OnStatusView := PanelStatusView;
  FLeftPanel.OnMouseModePick := PanelMouseModePick;

  FRightPanel := TFilePanel.Create(Self);
  FRightPanel.Parent := FWorkArea;
  FRightPanel.Align := TAlignLayout.None;
  FRightPanel.OnPathChanged := RightPanelPathChanged;
  FRightPanel.OnQuickView := PanelQuickView;
  FRightPanel.OnCursorChange := PanelCursorChanged;
  FRightPanel.OnStatusView := PanelStatusView;
  FRightPanel.OnMouseModePick := PanelMouseModePick;

  FCenterCluster := TLayout.Create(Self);
  FCenterCluster.Parent := FWorkArea;
  FCenterCluster.Align := TAlignLayout.None;
  FCenterCluster.HitTest := False;
  FCenterCluster.Width := CENTER_CLUSTER_WIDTH;

  FSplitterL := MakeSideSplitter(TAlignLayout.Left);
  FSplitterR := MakeSideSplitter(TAlignLayout.Right);
  BuildMidBar;

  FLeftPanel.OnActivate := PanelActivate;
  FRightPanel.OnActivate := PanelActivate;
  FLeftPanel.OnDropCopyMove := PanelDropCopyMove;
  FRightPanel.OnDropCopyMove := PanelDropCopyMove;

  FLeftPanel.SetActive(True);
  FRightPanel.SetActive(False);
  FActivePanel := FLeftPanel;
  LayoutWorkArea;
end;

procedure TMainForm.BuildCommandLine;
begin
  FCmdHist := TStringList.Create;
  FCmdHistPos := -1;

  FCmdBar := TLayout.Create(Self);
  FCmdBar.Parent := Self;
  FCmdBar.Align := TAlignLayout.Bottom;
  FCmdBar.Height := CMDLINE_HEIGHT;
  FCmdBar.Margins.Top := 4;
  FCmdBar.Visible := False;
  FCmdBar.HitTest := True;
  FCmdBar.OnResize := CmdBarResize;

  FCmdBack := TRectangle.Create(Self);
  FCmdBack.Align := TAlignLayout.None;
  FCmdBack.Parent := FCmdBar;
  FCmdBack.Stroke.Kind := TBrushKind.None;
  FCmdBack.Fill.Kind := TBrushKind.Solid;
  FCmdBack.HitTest := True;

  FCmdTopLine := TRectangle.Create(Self);
  FCmdTopLine.Align := TAlignLayout.None;
  FCmdTopLine.Parent := FCmdBar;
  FCmdTopLine.Stroke.Kind := TBrushKind.None;
  FCmdTopLine.Fill.Kind := TBrushKind.Solid;
  FCmdTopLine.HitTest := False;

  FCmdIcon := TText.Create(Self);
  FCmdIcon.Align := TAlignLayout.None;
  FCmdIcon.Parent := FCmdBar;
  FCmdIcon.HitTest := False;
  FCmdIcon.WordWrap := False;
  FCmdIcon.Text := CMD_PROMPT_ICON;
  FCmdIcon.TextSettings.Font.Family := FluentIconFamily;
  FCmdIcon.Font.Family := FluentIconFamily;
  FCmdIcon.TextSettings.Font.Size := 16;
  FCmdIcon.Font.Size := 16;
  FCmdIcon.TextSettings.HorzAlign := TTextAlign.Center;
  FCmdIcon.TextSettings.VertAlign := TTextAlign.Center;

  FCmdPath := TText.Create(Self);
  FCmdPath.Align := TAlignLayout.None;
  FCmdPath.Parent := FCmdBar;
  FCmdPath.HitTest := True;
  FCmdPath.ShowHint := True;
  FCmdPath.WordWrap := False;
  FCmdPath.TextSettings.Trimming := TTextTrimming.None;
  FCmdPath.TextSettings.HorzAlign := TTextAlign.Trailing;
  FCmdPath.TextSettings.VertAlign := TTextAlign.Center;
  ApplyFluentText(FCmdPath, 13, False);

  FCmdSplit := TRectangle.Create(Self);
  FCmdSplit.Align := TAlignLayout.None;
  FCmdSplit.Parent := FCmdBar;
  FCmdSplit.Stroke.Kind := TBrushKind.None;
  FCmdSplit.Fill.Kind := TBrushKind.Solid;
  FCmdSplit.HitTest := False;
  FCmdSplit.Visible := False;

  FCmdEdit := TFluentEdit.Create(Self);
  FCmdEdit.Align := TAlignLayout.None;
  FCmdEdit.FillMode := fefSubtle;
  FCmdEdit.OnSubmit := CmdLineSubmit;
  FCmdEdit.OnCancel := CmdLineCancel;
  FCmdEdit.Parent := FCmdBar;
  { Док уже записал свой хук. Обёртка зовёт его, если точка не на строке. }
  RegisterFileDragDropHook(TryCmdLineDrop);
end;

procedure TMainForm.CmdBarResize(Sender: TObject);
begin
  LayoutCmdBar;
end;

function FormatCmdPrompt(const APath: string): string;
begin
  Result := APath;
  if Result = '' then
    Exit;
  { Корень диска остаётся C:\> . У остальных слэш перед > не нужен. }
  if not ((Length(Result) = 3) and (Result[2] = ':') and
          ((Result[3] = '\') or (Result[3] = '/'))) then
    Result := ExcludeTrailingPathDelimiter(Result);
  if (Length(Result) = 2) and (Result[2] = ':') then
    Result := Result + '\';
  Result := Result + '>';
end;

function FitCmdPathTail(const AText: string; AMaxW: Single): string;
var
  Lo, Hi, Mid: Integer;
begin
  Result := AText;
  if AText = '' then
    Exit;
  if (AMaxW <= 0) or (MeasurePillText(AText, 13) <= AMaxW) then
    Exit;
  Lo := 1;
  Hi := Length(AText);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if MeasurePillText(Copy(AText, Mid, MaxInt), 13) <= AMaxW then
      Hi := Mid
    else
      Lo := Mid + 1;
  end;
  Result := Copy(AText, Lo, MaxInt);
end;

function QuoteCmdToken(const AToken: string): string;
var
  I: Integer;
  Need: Boolean;
  C: Char;
begin
  Need := False;
  for I := 1 to Length(AToken) do
  begin
    C := AToken[I];
    if (C <= ' ') or (Pos(C, '&^(),;="''%!<>|') > 0) then
    begin
      Need := True;
      Break;
    end;
  end;
  if not Need then
    Exit(AToken);
  Result := '"' + StringReplace(AToken, '"', '""', [rfReplaceAll]) + '"';
end;

function CmdDropToken(const APath: string; AFull: Boolean): string;
var
  P, Name: string;
begin
  Result := '';
  P := APath;
  if P = '' then
    Exit;
  if not ((Length(P) = 3) and (P[2] = ':') and
          ((P[3] = '\') or (P[3] = '/'))) then
    P := ExcludeTrailingPathDelimiter(P);
  Name := ExtractFileName(P);
  if (Name = '.') or (Name = '..') then
    Exit;
  if Name = '' then
  begin
    if (Length(P) >= 2) and (P[2] = ':') then
      Name := P
    else
      Exit;
  end;
  if AFull then
    Result := QuoteCmdToken(P)
  else
    Result := QuoteCmdToken(Name);
end;

procedure TMainForm.LayoutCmdBar;
const
  PathX = 32;
  Gap = 2;
  RightPad = 8;
  MinEdit = 160;
var
  W, H, PathW, EditW, EditX, Avail, MaxPath, TextW: Single;
  Shown: string;
begin
  if not Assigned(FCmdBar) or not Assigned(FCmdIcon) or not Assigned(FCmdPath) or
     not Assigned(FCmdEdit) then
    Exit;
  W := FCmdBar.Width;
  H := FCmdBar.Height;
  if (W < 8) or (H < 8) then
    Exit;
  Avail := W - PathX - Gap - RightPad;
  if Avail > MinEdit + 48 then
    MaxPath := Avail - MinEdit
  else
    MaxPath := Max(36, Avail * 0.42);
  Shown := FitCmdPathTail(FCmdPrompt, MaxPath);
  if Shown = '' then
    PathW := 0
  else
  begin
    TextW := MeasurePillText(Shown, 13) + 2;
    PathW := Min(MaxPath, TextW);
  end;
  EditX := PathX + PathW + Gap;
  EditW := Max(0, W - EditX - RightPad);
  if Assigned(FCmdBack) then
    FCmdBack.SetBounds(0, 0, W, H);
  if Assigned(FCmdTopLine) then
    FCmdTopLine.SetBounds(0, 0, W, 1);
  FCmdIcon.SetBounds(8, (H - 18) / 2, 18, 18);
  if FCmdPath.Text <> Shown then
    FCmdPath.Text := Shown;
  FCmdPath.SetBounds(PathX, 0, PathW, H);
  if Assigned(FCmdSplit) then
    FCmdSplit.Visible := False;
  FCmdEdit.SetBounds(EditX, (H - 28) / 2, EditW, 28);
end;

procedure TMainForm.SyncCmdPath;
var
  P: string;
begin
  if not Assigned(FCmdPath) or not Assigned(FActivePanel) then
    Exit;
  if FActivePanel.IsPathEditing or FActivePanel.IsInlineRenaming then
    Exit;
  P := FActivePanel.CurrentPath;
  FCmdPrompt := FormatCmdPrompt(P);
  FCmdPath.Hint := P;
  LayoutCmdBar;
end;

function TMainForm.TryCmdLineDrop(const AScreen: TPointF;
  const APaths: TArray<string>): Boolean;
var
  Local: TPointF;
begin
  Result := False;
  if Assigned(FCmdBar) and FCmdBar.Visible and (FCmdBar.Height >= 8) then
  begin
    Local := FCmdBar.ScreenToLocal(AScreen);
    if (Local.X >= 0) and (Local.Y >= 0) and
       (Local.X < FCmdBar.Width) and (Local.Y < FCmdBar.Height) then
    begin
      { False: выделение панели остаётся, копии нет — строка не панель. }
      InsertCmdDrop(APaths);
      Exit;
    end;
  end;
  if Assigned(FDock) then
    Result := FDock.TryAcceptExternalDrop(AScreen, APaths);
end;

procedure TMainForm.InsertCmdDrop(const APaths: TArray<string>);
var
  Body, Token, Chunk, Lead, Trail: string;
  S: string;
  FromI, ToI: Integer;
  Full: Boolean;
begin
  if not Assigned(FCmdEdit) or (Length(APaths) = 0) then
    Exit;
  Full := (GetKeyState(VK_SHIFT) and $8000) <> 0;
  Body := '';
  for S in APaths do
  begin
    Token := CmdDropToken(S, Full);
    if Token = '' then
      Continue;
    if Body <> '' then
      Body := Body + ' ';
    Body := Body + Token;
  end;
  if Body = '' then
    Exit;
  FCmdEdit.QueryInsertPoint(FromI, ToI);
  Lead := '';
  Trail := ' ';
  if (FromI > 0) and (FromI <= Length(FCmdEdit.Text)) and
     (FCmdEdit.Text[FromI] <> ' ') then
    Lead := ' ';
  if (ToI < Length(FCmdEdit.Text)) and (FCmdEdit.Text[ToI + 1] = ' ') then
    Trail := '';
  Chunk := Lead + Body + Trail;
  FCmdEdit.InsertSnippet(Chunk);
  FCmdHistPos := -1;
end;

function TMainForm.CmdLineFocused: Boolean;
begin
  Result := Assigned(FCmdEdit) and FCmdEdit.IsFocused;
end;

procedure TMainForm.RememberCmd(const ACmd: string);
begin
  if (ACmd = '') or not Assigned(FCmdHist) then
    Exit;
  FCmdHist.Add(ACmd);
  while FCmdHist.Count > CMD_HIST_MAX do
    FCmdHist.Delete(0);
  FCmdHistPos := -1;
  FCmdDraft := '';
end;

procedure TMainForm.CmdHistStep(ADelta: Integer);
begin
  if not Assigned(FCmdEdit) or not Assigned(FCmdHist) or (FCmdHist.Count = 0) then
    Exit;
  if FCmdHistPos < 0 then
  begin
    if ADelta > 0 then
      Exit;
    FCmdDraft := FCmdEdit.Text;
    FCmdHistPos := FCmdHist.Count - 1;
  end
  else
  begin
    FCmdHistPos := FCmdHistPos + ADelta;
    if FCmdHistPos >= FCmdHist.Count then
    begin
      FCmdHistPos := -1;
      FCmdEdit.Text := FCmdDraft;
      Exit;
    end;
    if FCmdHistPos < 0 then
      FCmdHistPos := 0;
  end;
  FCmdEdit.Text := FCmdHist[FCmdHistPos];
end;

procedure TMainForm.CmdLineCancel(Sender: TObject);
begin
  if Assigned(FActivePanel) and FActivePanel.CanFocus then
    FActivePanel.SetFocus;
end;

procedure TMainForm.LayoutFunctionBar;
const
  KeyGap = 3;
var
  I: Integer;
  CellW, CellH, Origin, Span: Single;
begin
  if not Assigned(FFnBar) then
    Exit;
  { Край кнопок совпадает с краем файловой панели. Поля кнопок — только зазор между ними. }
  Origin := WORK_PAD_L - KeyGap;
  Span := FFnBar.Width - WORK_PAD_L - WORK_PAD_R + KeyGap * 2;
  if Span < 7 then
    Span := 7;
  CellW := Max(70, Span / 7);
  CellH := FFnBar.Height - FFnBar.Padding.Top - FFnBar.Padding.Bottom;
  if CellH < 24 then
    CellH := 24;
  for I := 0 to 6 do
    if Assigned(FFnCells[I]) then
      FFnCells[I].SetBounds(Origin + I * CellW, FFnBar.Padding.Top, CellW, CellH);
end;

function TMainForm.CenterBandWidth: Single;
begin
  if Assigned(FSettings) and not FSettings.ShowMidBar then
    Result := SPLITTER_WIDTH
  else
    Result := CENTER_CLUSTER_WIDTH;
end;

procedure TMainForm.ApplyCenterBandLayout;
begin
  if not Assigned(FCenterCluster) then
    Exit;
  if Assigned(FSettings) and not FSettings.ShowMidBar then
  begin
    if Assigned(FMidBar) then
      FMidBar.Visible := False;
    if Assigned(FSplitterR) then
      FSplitterR.Visible := False;
    if Assigned(FSplitterL) then
    begin
      FSplitterL.Visible := True;
      FSplitterL.Align := TAlignLayout.Client;
      FSplitterL.Margins.Rect := TRectF.Create(0, 0, 0, 0);
    end;
    FCenterCluster.Width := SPLITTER_WIDTH;
  end
  else
  begin
    if Assigned(FMidBar) then
      FMidBar.Visible := True;
    if Assigned(FSplitterR) then
    begin
      FSplitterR.Visible := True;
      FSplitterR.Align := TAlignLayout.Right;
      FSplitterR.Width := SPLITTER_WIDTH;
      FSplitterR.Margins.Rect := TRectF.Create(0, MIDBAR_TOP, 0, MIDBAR_BOTTOM);
    end;
    if Assigned(FSplitterL) then
    begin
      FSplitterL.Visible := True;
      FSplitterL.Align := TAlignLayout.Left;
      FSplitterL.Width := SPLITTER_WIDTH;
      FSplitterL.Margins.Rect := TRectF.Create(0, MIDBAR_TOP, 0, MIDBAR_BOTTOM);
    end;
    FCenterCluster.Width := CENTER_CLUSTER_WIDTH;
  end;
  LayoutOpPill;
end;

procedure TMainForm.LayoutWorkArea;
var
  InnerW, InnerH, PanelSpace, LeftW, RightW, MinPanel, X, BandW: Single;
begin
  if not Assigned(FWorkArea) or not Assigned(FLeftPanel) or
     not Assigned(FRightPanel) or not Assigned(FCenterCluster) then
    Exit;

  InnerW := FWorkArea.Width - WORK_PAD_L - WORK_PAD_R;
  InnerH := FWorkArea.Height - WORK_PAD_T - WORK_PAD_B;
  if (InnerW < 40) or (InnerH < 40) then
    Exit;

  BandW := CenterBandWidth;
  PanelSpace := InnerW - BandW;
  if PanelSpace < 2 then
    PanelSpace := 2;
  MinPanel := Min(MIN_PANEL_WIDTH, PanelSpace / 2);
  if FLeftPanelRatio <= 0 then
    FLeftPanelRatio := 0.5;
  LeftW := EnsureRange(Round(PanelSpace * FLeftPanelRatio), MinPanel, PanelSpace - MinPanel);
  RightW := PanelSpace - LeftW;

  X := WORK_PAD_L;
  FLeftPanel.SetBounds(X, WORK_PAD_T, LeftW, InnerH);
  X := X + LeftW;
  FCenterCluster.SetBounds(X, WORK_PAD_T, BandW, InnerH);
  X := X + BandW;
  FRightPanel.SetBounds(X, WORK_PAD_T, RightW, InnerH);
  LayoutOpPill;
end;

procedure TMainForm.ApplyLeftPanelWidth(AWidth: Single);
var
  InnerW, PanelSpace, MinPanel, LeftW: Single;
begin
  if not Assigned(FWorkArea) then
    Exit;
  InnerW := FWorkArea.Width - WORK_PAD_L - WORK_PAD_R;
  PanelSpace := InnerW - CenterBandWidth;
  if PanelSpace < 2 then
    Exit;
  MinPanel := Min(MIN_PANEL_WIDTH, PanelSpace / 2);
  LeftW := EnsureRange(AWidth, MinPanel, PanelSpace - MinPanel);
  if PanelSpace > 0 then
    FLeftPanelRatio := LeftW / PanelSpace;
  LayoutWorkArea;
end;

procedure TMainForm.WorkAreaResize(Sender: TObject);
begin
  if not FSplitDragging then
    LayoutWorkArea;
end;

procedure TMainForm.SplitterMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  AbsPt: TPointF;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  if Sender is TControl then
    AbsPt := TControl(Sender).LocalToAbsolute(TPointF.Create(X, Y))
  else
    AbsPt := TPointF.Create(X, Y);
  FSplitDragging := True;
  FSplitStartX := FWorkArea.AbsoluteToLocal(AbsPt).X;
  FSplitStartLeftW := FLeftPanel.Width;
end;

procedure TMainForm.SplitterMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  AbsPt: TPointF;
begin
  if not FSplitDragging then
    Exit;
  if Sender is TControl then
    AbsPt := TControl(Sender).LocalToAbsolute(TPointF.Create(X, Y))
  else
    AbsPt := TPointF.Create(X, Y);
  ApplyLeftPanelWidth(FSplitStartLeftW + (FWorkArea.AbsoluteToLocal(AbsPt).X - FSplitStartX));
end;

procedure TMainForm.SplitterMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if not FSplitDragging then
    Exit;
  FSplitDragging := False;
  if (FLeftPanel.Width + FRightPanel.Width) > 0 then
    FLeftPanelRatio := FLeftPanel.Width / (FLeftPanel.Width + FRightPanel.Width);
end;

procedure TMainForm.SplitterMouseEnter(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FColors.ControlFillHover;
end;

procedure TMainForm.SplitterMouseLeave(Sender: TObject);
begin
  if FSplitDragging then
    Exit;
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := TAlphaColors.Null;
end;

procedure TMainForm.FormResizeHandler(Sender: TObject);
begin
  MarkSessionDirty;
  UpdateWindowButtons;
  LayoutQuickSearch;
  LayoutWorkArea;

  CaptureNormalGeometry;

  LayoutFunctionBar;
  LayoutCmdBar;
end;

procedure TMainForm.LeftPanelPathChanged(Sender: TObject; const APath: string);
begin
  MarkSessionDirty;
  UsePanel(FLeftPanel, False);
end;

procedure TMainForm.RightPanelPathChanged(Sender: TObject; const APath: string);
begin
  MarkSessionDirty;
  UsePanel(FRightPanel, False);
end;

procedure TMainForm.PanelQuickView(Sender: TObject; const APath: string);
begin
  TogglePanelQuickView;
end;

procedure TMainForm.OnBtnQuickViewToggle(Sender: TObject);
begin
  TogglePanelQuickView;
end;

procedure TMainForm.TogglePanelQuickView;
var
  Src, Dst: TFilePanel;
  Entry: TFileEntry;
  Path: string;
begin
  if not Assigned(FActivePanel) then
    Exit;
  Src := FActivePanel;
  Dst := OtherPanel(Src);
  if Src.IsPreviewActive then
  begin
    Src.HidePreview;
    UpdateViewButtons;
    Exit;
  end;
  if Dst.IsPreviewActive then
  begin
    Dst.HidePreview;
    UpdateViewButtons;
    Exit;
  end;
  Path := '';
  if Src.GetFocusedEntry(Entry) then
    Path := Entry.FullPath
  else
    Path := Src.CurrentPath;
  Dst.ShowPreview(Path);
  UpdateViewButtons;
end;

procedure TMainForm.ArmPreviewDebounce;
begin
  if FPreviewDebounce = nil then
  begin
    FPreviewDebounce := TTimer.Create(Self);
    FPreviewDebounce.Interval := 300;
    FPreviewDebounce.OnTimer := PreviewDebounceTick;
  end;
  FPreviewDebounce.Enabled := False;
  FPreviewDebounce.Enabled := True;
end;

function TMainForm.QuickViewFollows: Boolean;
begin
  Result := Assigned(FSettings) and FSettings.FollowCursor and
    Assigned(FQuickView) and FQuickView.Visible;
end;

procedure TMainForm.FollowQuickViewWindow(const APath: string);
begin
  if (APath = '') or not QuickViewFollows then
    Exit;
  FQuickView.FollowFile(APath);
end;

procedure TMainForm.FollowActivePanelPreview;
var
  Entry: TFileEntry;
  Path: string;
begin
  if csDestroying in ComponentState then
    Exit;
  if not QuickViewFollows then
    Exit;
  if not Assigned(FActivePanel) or FActivePanel.IsOffline then
  begin
    FPreviewWindowPending := '';
    Exit;
  end;
  if not FActivePanel.GetFocusedEntry(Entry) then
  begin
    FPreviewWindowPending := '';
    Exit;
  end;
  Path := Entry.FullPath;
  if IsRemotePath(Path) or IsRemotePath(FActivePanel.CurrentPath) then
  begin
    FPreviewWindowPending := Path;
    if not (Assigned(FPreviewDebounce) and FPreviewDebounce.Enabled) then
    begin
      FPreviewPending := '';
      ArmPreviewDebounce;
    end;
    Exit;
  end;
  FPreviewWindowPending := '';
  FQuickView.FollowFile(Path);
end;

procedure TMainForm.CloseColumnQuickView;
begin
  if Assigned(FLeftPanel) and FLeftPanel.IsPreviewActive then
    FLeftPanel.HidePreview;
  if Assigned(FRightPanel) and FRightPanel.IsPreviewActive then
    FRightPanel.HidePreview;
end;

procedure TMainForm.ApplyPanelView(APanel: TFilePanel; AMode: TPanelViewMode);
begin
  if not Assigned(APanel) then
    Exit;
  CloseColumnQuickView;
  if APanel.ViewMode <> AMode then
    APanel.SetViewMode(AMode);
  if APanel.CanFocus then
    APanel.SetFocus;
  UpdateViewButtons;
end;

procedure TMainForm.PanelStatusView(Sender: TObject; AMode: TPanelViewMode);
begin
  if Sender is TFilePanel then
    ApplyPanelView(TFilePanel(Sender), AMode);
end;

procedure TMainForm.PanelCursorChanged(Sender: TObject);
var
  Other: TFilePanel;
  Entry: TFileEntry;
  ColumnPath, WindowPath: string;
  ColumnOn, HasEntry, Remote: Boolean;
begin
  MarkSessionDirty;
  if Sender <> FActivePanel then
    Exit;
  SyncCmdPath;
  if not Assigned(FActivePanel) then
    Exit;
  Other := OtherPanel(FActivePanel);
  ColumnOn := (Other <> nil) and Other.IsPreviewActive;
  HasEntry := FActivePanel.GetFocusedEntry(Entry);
  if HasEntry then
  begin
    ColumnPath := Entry.FullPath;
    WindowPath := Entry.FullPath;
  end
  else
  begin
    ColumnPath := FActivePanel.CurrentPath;
    WindowPath := '';
  end;
  if not QuickViewFollows then
    WindowPath := '';
  if FActivePanel.IsOffline then
  begin
    FPreviewWindowPending := '';
    Exit;
  end;
  if (not ColumnOn) and (WindowPath = '') then
  begin
    FPreviewWindowPending := '';
    Exit;
  end;
  Remote := IsRemotePath(ColumnPath) or IsRemotePath(FActivePanel.CurrentPath);
  if (WindowPath <> '') and IsRemotePath(WindowPath) then
    Remote := True;
  if Remote then
  begin
    if ColumnOn then
      FPreviewPending := ColumnPath
    else
      FPreviewPending := '';
    FPreviewWindowPending := WindowPath;
    ArmPreviewDebounce;
    Exit;
  end;
  if Assigned(FPreviewDebounce) then
    FPreviewDebounce.Enabled := False;
  FPreviewPending := '';
  FPreviewWindowPending := '';
  if ColumnOn then
    Other.PreviewFile(ColumnPath);
  if WindowPath <> '' then
    FollowQuickViewWindow(WindowPath);
end;

procedure TMainForm.PreviewDebounceTick(Sender: TObject);
var
  Other: TFilePanel;
  ColumnPath, WindowPath: string;
begin
  if Assigned(FPreviewDebounce) then
    FPreviewDebounce.Enabled := False;
  ColumnPath := FPreviewPending;
  WindowPath := FPreviewWindowPending;
  FPreviewPending := '';
  FPreviewWindowPending := '';
  if (ColumnPath = '') and (WindowPath = '') then
    Exit;
  if Assigned(FActivePanel) and FActivePanel.IsOffline then
    Exit;
  Other := OtherPanel(FActivePanel);
  if (ColumnPath <> '') and (Other <> nil) and Other.IsPreviewActive then
    Other.PreviewFile(ColumnPath);
  if WindowPath <> '' then
    FollowQuickViewWindow(WindowPath);
end;

procedure TMainForm.ShowQuickViewWindow(const APath: string);
begin
  if APath = '' then
    Exit;
  if not Assigned(FQuickView) then
    FQuickView := TQuickViewForm.Create(Self);
  FQuickView.ApplyTheme(FColors);
  FQuickView.ShowFile(APath);
end;

procedure TMainForm.ShowQuickViewForPath(const APath: string);
begin
  ShowQuickViewWindow(APath);
end;

function TMainForm.PreviewWantsKeys: Boolean;
begin
  Result := False;
  if Assigned(FQuickView) and FQuickView.Active then
    Exit(True);
  if Assigned(FLeftPanel) and FLeftPanel.PreviewHasFocus then
    Exit(True);
  if Assigned(FRightPanel) and FRightPanel.PreviewHasFocus then
    Exit(True);
end;

function TMainForm.OtherPanel(APanel: TFilePanel): TFilePanel;
begin
  if APanel = FLeftPanel then
    Result := FRightPanel
  else
    Result := FLeftPanel;
end;

procedure TMainForm.OnSettingsClick(Sender: TObject);
var
  Frm: TSettingsForm;
begin
  Frm := TSettingsForm.Create(Self, FSettings, OnThemeChangedFromSettings);
  try
    Frm.OnOptionsChanged :=
      procedure(const AApply: TSettingsApplySet)
      begin
        if saFileOp in AApply then
          SetFileOpMode(FSettings.FileOpMode);
        if saBands in AApply then
          ApplyBandLayout;
        if saPanels in AApply then
          ApplyPanelSettings;
        if saBehavior in AApply then
          ApplySessionBehavior;
      end;
    Frm.OnTintChanged :=
      procedure
      begin
        ApplyWindowBackground;
      end;
    Frm.OnLanguageChanged :=
      procedure
      begin
        ApplyLanguage;
      end;
    Frm.ApplyTheme(FColors);
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

function CmdStartsWithCmd(const ACmd: string): Boolean;
var
  S: string;
begin
  S := Trim(ACmd);
  Result := False;
  if S = '' then
    Exit;
  if (S <> '') and (S[1] = '"') then
    Delete(S, 1, 1);
  if Length(S) < 3 then
    Exit;
  if not SameText(Copy(S, 1, 3), 'cmd') then
    Exit;
  if Length(S) = 3 then
    Exit(True);
  Result := CharInSet(S[4], [' ', #9, '.', '"']);
end;

function NormalizeCmdPath(const APath: string): string;
var
  S, Part: string;
  Parts: TArray<string>;
  Stack: TList<string>;
  Unc: Boolean;
  I: Integer;
begin
  S := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
  Unc := (Length(S) >= 2) and (S[1] = '\') and (S[2] = '\');
  Parts := S.Split(['\']);
  Stack := TList<string>.Create;
  try
    for I := 0 to High(Parts) do
    begin
      Part := Parts[I];
      if (Part = '') or (Part = '.') then
        Continue;
      if Part = '..' then
      begin
        if Unc and (Stack.Count <= 2) then
          Continue;
        if (not Unc) and (Stack.Count = 1) and (Length(Stack[0]) = 2) and
           (Stack[0][2] = ':') then
          Continue;
        if Stack.Count > 0 then
          Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      Stack.Add(Part);
    end;
    Result := '';
    for I := 0 to Stack.Count - 1 do
    begin
      if Result <> '' then
        Result := Result + '\';
      Result := Result + Stack[I];
    end;
    if Unc then
      Result := '\\' + Result;
    if (not Unc) and (Length(Result) = 2) and (Result[2] = ':') then
      Result := Result + '\';
  finally
    Stack.Free;
  end;
end;

function CombineCmdPath(const ABase, ARel: string): string;
var
  Rel, Base, Root: string;
  P, N: Integer;
begin
  Rel := Trim(ARel);
  if Length(Rel) >= 2 then
    if (Rel[1] = '"') and (Rel[Length(Rel)] = '"') then
      Rel := Trim(Copy(Rel, 2, Length(Rel) - 2));
  Rel := StringReplace(Rel, '/', '\', [rfReplaceAll]);
  if Rel = '' then
    Exit(ABase);
  if Length(Rel) >= 2 then
    if ((Rel[1] = '\') and (Rel[2] = '\')) or (Rel[2] = ':') then
      Exit(NormalizeCmdPath(Rel));
  Base := ABase;
  if Rel[1] = '\' then
  begin
    if (Length(Base) >= 2) and (Base[2] = ':') then
      Exit(NormalizeCmdPath(Copy(Base, 1, 2) + Rel));
    if (Length(Base) >= 2) and (Base[1] = '\') and (Base[2] = '\') then
    begin
      Root := Base;
      P := 3;
      N := 0;
      while P <= Length(Base) do
      begin
        if Base[P] = '\' then
        begin
          Inc(N);
          if N = 2 then
          begin
            Root := Copy(Base, 1, P - 1);
            Break;
          end;
        end;
        Inc(P);
      end;
      Root := ExcludeTrailingPathDelimiter(Root);
      Exit(NormalizeCmdPath(Root + Rel));
    end;
  end;
  Result := NormalizeCmdPath(IncludeTrailingPathDelimiter(Base) + Rel);
end;

function ParseCmdCd(const ACmd, ABase: string; out ATarget: string): Integer;
var
  S, Rest: string;
begin
  { 0 — не cd, 1 — cd без пути, 2 — есть путь. }
  Result := 0;
  ATarget := '';
  S := Trim(ACmd);
  if Length(S) < 2 then
    Exit;
  if (UpCase(S[1]) <> 'C') or (UpCase(S[2]) <> 'D') then
    Exit;
  if Length(S) > 2 then
  begin
    if not CharInSet(S[3], [' ', #9, '.', '\', '/']) then
      Exit;
    Rest := Trim(Copy(S, 3, MaxInt));
  end
  else
    Rest := '';
  if Length(Rest) >= 2 then
    if (Rest[1] = '/') and (UpCase(Rest[2]) = 'D') then
      if Length(Rest) = 2 then
        Rest := ''
      else if Rest[3] <= ' ' then
        Rest := Trim(Copy(Rest, 3, MaxInt));
  if Rest <> '' then
    if Rest[1] = '"' then
  begin
    if Rest[Length(Rest)] = '"' then
      Rest := Copy(Rest, 2, Length(Rest) - 2)
    else
      Rest := Copy(Rest, 2, MaxInt);
    Rest := Trim(Rest);
  end;
  if Rest = '' then
    Exit(1);
  ATarget := CombineCmdPath(ABase, Rest);
  Result := 2;
end;

function LaunchCmdLine(const ACmd, AWorkDir: string): Boolean;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Line, Work: string;
  Dir: PChar;
  Flags: DWORD;
begin
  Result := False;
  { Окно консоли только у cmd. Остальное запускает скрытый cmd /c. }
  if CmdStartsWithCmd(ACmd) then
  begin
    Line := ACmd;
    Flags := CREATE_NEW_CONSOLE;
  end
  else
  begin
    Line := 'cmd.exe /c ' + ACmd;
    Flags := CREATE_NO_WINDOW;
  end;
  UniqueString(Line);
  Work := AWorkDir;
  if (Work = '') or IsThisPCPath(Work) or IsVirtualShellPath(Work) then
    Dir := nil
  else
  begin
    if Length(Work) >= 2 then
    begin
      if (Work[2] = ':') and (Length(ExcludeTrailingPathDelimiter(Work)) = 2) then
        Work := Copy(Work, 1, 2) + '\'
      else
        Work := ExcludeTrailingPathDelimiter(Work);
    end
    else
      Work := ExcludeTrailingPathDelimiter(Work);
    Dir := PChar(Work);
  end;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(Line), nil, nil, False, Flags,
    nil, Dir, SI, PI) then
    Exit;
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  Result := True;
end;

procedure TMainForm.CmdLineSubmit(Sender: TObject);
var
  Cmd, Target, Base: string;
  CdKind: Integer;
begin
  if not Assigned(FCmdEdit) then
    Exit;
  Cmd := Trim(FCmdEdit.Text);
  if Cmd = '' then
    Exit;
  RememberCmd(Cmd);
  Base := '';
  if Assigned(FActivePanel) then
    Base := FActivePanel.CurrentPath;
  CdKind := ParseCmdCd(Cmd, Base, Target);
  if CdKind = 1 then
    Exit;
  if CdKind = 2 then
  begin
    if not Assigned(FActivePanel) then
      Exit;
    if not IsListablePath(Target) then
    begin
      FActivePanel.ShowNotice(L('main.notice.nofolder'));
      Exit;
    end;
    FActivePanel.Navigate(Target);
    FCmdEdit.Text := '';
    FCmdHistPos := -1;
    Exit;
  end;
  if not LaunchCmdLine(Cmd, Base) then
  begin
    if Assigned(FActivePanel) then
      FActivePanel.ShowNotice(L('main.notice.nolaunch'));
    Exit;
  end;
  FCmdEdit.Text := '';
  FCmdHistPos := -1;
end;

procedure TMainForm.ApplyWindowBackground;
var
  Chrome: TThemeColors;
{$IFDEF MSWINDOWS}
  CapColor: COLORREF;
  Wnd: HWND;
{$ENDIF}
begin
  if not Assigned(FSettings) then
    Exit;
  FColors := GetThemeColors(FSettings.Theme);
  Chrome := FColors;
  TintChromeForMaterial(Chrome, FSettings.WindowMaterial);
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := Chrome.Background;
  if Assigned(FTitleBar) then
    FTitleBar.Fill.Color := Chrome.TitleBarBackground;
  {$IFDEF MSWINDOWS}
  if (FSettings.WindowMaterial = wmNormal) and (FFrameHooked or FStartupDone) then
  begin
    Wnd := FormToHWND(Self);
    if Wnd <> 0 then
    begin
      CapColor := AlphaToColorRef(Chrome.TitleBarBackground);
      DwmSetWindowAttribute(Wnd, 35, @CapColor, SizeOf(CapColor));
      DwmSetWindowAttribute(Wnd, 34, @CapColor, SizeOf(CapColor));
    end;
  end;
  {$ENDIF}
end;

procedure TMainForm.ApplyBandLayout;
var
  I: Integer;
  FnH: Single;
begin
  if not Assigned(FSettings) then
    Exit;
  if Assigned(FDock) then
  begin
    FDock.Visible := FSettings.ShowDock;
    FDock.ApplyDockOptions(FSettings.DockAlign, FSettings.DockShowSeparators);
    if Assigned(FTopStack) then
      if FSettings.ShowDock then
        FTopStack.Height := TITLEBAR_HEIGHT + DOCK_HEIGHT
      else
        FTopStack.Height := TITLEBAR_HEIGHT;
  end;
  ApplyCenterBandLayout;

  if Assigned(FCmdBar) then
  begin
    FCmdBar.Visible := FSettings.ShowCommandLine;
    if FSettings.ShowCommandLine then
    begin
      FCmdBar.Height := CMDLINE_HEIGHT;
      FCmdBar.Margins.Top := 4;
    end
    else
    begin
      FCmdBar.Height := 0;
      FCmdBar.Margins.Top := 0;
    end;
  end;
  FnH := 0;
  if FSettings.ShowFnBar then
    FnH := FNBAR_HEIGHT;
  if Assigned(FFnBar) then
  begin
    FFnBar.Visible := FSettings.ShowFnBar;
    if FSettings.ShowFnBar then
      FFnBar.Height := FnH;
  end;
  for I := 0 to 6 do
    if Assigned(FFnCells[I]) then
      FFnCells[I].Visible := FSettings.ShowFnBar;

  LayoutWorkArea;
  LayoutFunctionBar;
  LayoutCmdBar;
  SyncCmdPath;
  ApplyMinWindowHeight;
end;

procedure TMainForm.ApplyPanelSettings;
begin
  if not Assigned(FSettings) then
    Exit;
  if Assigned(FLeftPanel) then
    FLeftPanel.ApplyUiSettings(FSettings);
  if Assigned(FRightPanel) then
    FRightPanel.ApplyUiSettings(FSettings);
end;

procedure TMainForm.ApplyDriveOptions;
begin
  if not Assigned(FSettings) then
    Exit;
  SetFileOpMode(FSettings.FileOpMode);
  ApplyBandLayout;
  ApplyPanelSettings;
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.Configure(FSettings.ThumbCacheEnabled, FSettings.ThumbCacheMaxItems);
  ApplySessionBehavior;
end;

procedure TMainForm.ApplySessionBehavior;
{$IFDEF MSWINDOWS}
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunValue = 'VibeCmd';
var
  Reg: TRegistry;
  Want, Have: string;
  H: THandle;
{$ENDIF}
begin
  if not Assigned(FSettings) then
    Exit;
  FSettings.SaveBehavior;
  {$IFDEF MSWINDOWS}
  if FSettings.SingleInstance then
  begin
    if GAppMutex = 0 then
    begin
      H := CreateMutex(nil, True, APP_MUTEX_NAME);
      if H <> 0 then
        GAppMutex := H;
    end;
  end
  else if GAppMutex <> 0 then
  begin
    CloseHandle(GAppMutex);
    GAppMutex := 0;
  end;

  Want := '"' + ParamStr(0) + '"';
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(RunKey, FSettings.AutoStart) then
      Exit;
    try
      Have := '';
      if Reg.ValueExists(RunValue) then
        Have := Reg.ReadString(RunValue);
      if FSettings.AutoStart then
      begin
        if not SameText(Have, Want) then
          Reg.WriteString(RunValue, Want);
      end
      else if Have <> '' then
        Reg.DeleteValue(RunValue);
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  {$ENDIF}
end;

procedure TMainForm.OnThemeChangedFromSettings(NewTheme: TAppTheme);
begin
  FSettings.Theme := NewTheme;
  ConfigureThemeTint(FSettings.ColorTint, FSettings.WindowMaterial);
  FColors := GetThemeColors(NewTheme);
  ApplyThemeToAll(FColors);
end;

procedure TMainForm.HandleSystemChromeChanged;
begin
  FColors := GetThemeColors(FSettings.Theme);
  ApplyThemeToAll(FColors);
  if Assigned(FQuickView) then
    FQuickView.ApplyTheme(FColors);
end;

procedure TMainForm.UpdateViewButtons;
begin
  if not Assigned(FActivePanel) then
    Exit;
  if Assigned(FCmdDetails) then
    FCmdDetails.SetSelected(FActivePanel.ViewMode = vmDetails);
  if Assigned(FCmdTiles) then
    FCmdTiles.SetSelected(FActivePanel.ViewMode = vmTiles);
  if Assigned(FCmdQuickView) then
    FCmdQuickView.SetSelected(Assigned(FLeftPanel) and Assigned(FRightPanel) and
      (FLeftPanel.IsPreviewActive or FRightPanel.IsPreviewActive));
end;

procedure TMainForm.ApplyLanguage;
begin
  if Assigned(FCmdCopy) then
    FCmdCopy.Hint := L('cmd.copy');
  if Assigned(FCmdMove) then
    FCmdMove.Hint := L('cmd.move');
  if Assigned(FCmdRename) then
    FCmdRename.Hint := L('cmd.rename');
  if Assigned(FCmdArchive) then
    FCmdArchive.Hint := L('cmd.archive');
  if Assigned(FCmdDelete) then
    FCmdDelete.Hint := L('cmd.delete');
  if Assigned(FCmdNewFolder) then
    FCmdNewFolder.Hint := L('cmd.newfolder');
  if Assigned(FCmdSearch) then
    FCmdSearch.Hint := L('cmd.search');
  if Assigned(FCmdSelect) then
    FCmdSelect.Hint := L('cmd.select');
  if Assigned(FCmdRefresh) then
    FCmdRefresh.Hint := L('cmd.refresh');
  if Assigned(FCmdQuickView) then
    FCmdQuickView.Hint := L('cmd.quickview');
  if Assigned(FCmdDetails) then
    FCmdDetails.Hint := L('cmd.details');
  if Assigned(FCmdTiles) then
    FCmdTiles.Hint := L('cmd.tiles');
  if Assigned(FFnButtons[0]) then
    FFnButtons[0].SetCaption(L('fn.rename'));
  if Assigned(FFnButtons[1]) then
    FFnButtons[1].SetCaption(L('fn.view'));
  if Assigned(FFnButtons[2]) then
    FFnButtons[2].SetCaption(L('fn.search'));
  if Assigned(FFnButtons[3]) then
    FFnButtons[3].SetCaption(L('fn.copy'));
  if Assigned(FFnButtons[4]) then
    FFnButtons[4].SetCaption(L('fn.move'));
  if Assigned(FFnButtons[5]) then
    FFnButtons[5].SetCaption(L('fn.newfolder'));
  if Assigned(FFnButtons[6]) then
    FFnButtons[6].SetCaption(L('fn.delete'));
  BuildSelMenu;
  if Assigned(FOpPill) then
    FOpPill.Hint := L('main.ops.hint');
  if Assigned(FQuickSearch) then
  begin
    FQuickSearch.TextPrompt := L('main.search.prompt');
    FQuickSearch.FooterCaption := L('main.search.clear');
  end;
  if Assigned(FLeftPanel) then
    FLeftPanel.ApplyLanguage;
  if Assigned(FRightPanel) then
    FRightPanel.ApplyLanguage;
  if Assigned(FDock) then
    FDock.ApplyLanguage;
  if Assigned(FQuickView) then
    FQuickView.ApplyLanguage;
end;

procedure TMainForm.ApplyThemeToAll(const AColors: TThemeColors);
var
  I: Integer;
  Chrome, PanelColors: TThemeColors;
begin
  FColors := AColors;
  SetActiveAppTheme(FSettings.Theme);
  Chrome := AColors;
  TintChromeForMaterial(Chrome, FSettings.WindowMaterial);
  PanelColors := AColors;
  PanelColors.PanelBackground := Chrome.PanelBackground;
  PanelColors.HeaderBackground := Chrome.HeaderBackground;
  { Смешение вкладок читает Background. Та же альфа, что у шапки,
    иначе полупрозрачный заголовок и плотный фон дают более густую вкладку. }
  PanelColors.Background := ThemeAdjustAlpha(AColors.Background,
    TAlphaColorRec(Chrome.HeaderBackground).A);
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := Chrome.Background;
  {$IFDEF MSWINDOWS}
  if FFrameHooked or FStartupDone then
  begin
    ApplyNativeWindowChrome(FormToHWND(Self), AColors.IsDark);
    ApplyCustomFrame;
  end;
  {$ENDIF}

  FTitleBar.Fill.Color := Chrome.TitleBarBackground;
  if Assigned(FTitleLine) then
    FTitleLine.Visible := False;
  if Assigned(FLogoV) then
    FLogoV.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FLogoBang) then
    FLogoBang.TextSettings.FontColor := VIBE_NEON;
  FTitleText.TextSettings.FontColor := AColors.TextColor;
  FSubtitleText.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FQuickSearch) then
    FQuickSearch.ApplyTheme(AColors);
  if Assigned(FBtnSettings) and (FBtnSettings.TagObject is TText) then
    TText(FBtnSettings.TagObject).TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnMin) and (FBtnMin.TagObject is TText) then
    TText(FBtnMin.TagObject).TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnMax) and (FBtnMax.TagObject is TText) then
    TText(FBtnMax.TagObject).TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnClose) and (FBtnClose.TagObject is TText) then
    TText(FBtnClose.TagObject).TextSettings.FontColor := AColors.TextColor;

  if Assigned(FDock) then
    FDock.ApplyTheme(Chrome);
  FMidBar.Fill.Color := Chrome.ToolbarBackground;
  if Assigned(FSplitGripL) then
    FSplitGripL.Fill.Color := AColors.DividerColor;
  if Assigned(FSplitGripR) then
    FSplitGripR.Fill.Color := AColors.DividerColor;
  FCmdQuickView.ApplyTheme(AColors);
  FCmdCopy.ApplyTheme(AColors);
  FCmdMove.ApplyTheme(AColors);
  FCmdDelete.ApplyTheme(AColors);
  FCmdNewFolder.ApplyTheme(AColors);
  FCmdRename.ApplyTheme(AColors);
  FCmdArchive.ApplyTheme(AColors);
  FCmdSearch.ApplyTheme(AColors);
  FCmdRefresh.ApplyTheme(AColors);
  FCmdDetails.ApplyTheme(AColors);
  FCmdTiles.ApplyTheme(AColors);
  if Assigned(FCmdSelect) then
    FCmdSelect.ApplyTheme(AColors);
  if Assigned(FSelMenu) then
    FSelMenu.ApplyTheme(AColors);
  if Assigned(FOpHost) then
  begin
    FOpHost.Fill.Color := AColors.CardBackground;
    FOpHost.Stroke.Color := AColors.CardStroke;
    for var Si := 0 to FOpHost.ChildrenCount - 1 do
      if FOpHost.Children[Si] is TShadowEffect then
        ApplyFluentShadow(TShadowEffect(FOpHost.Children[Si]), AColors.IsDark);
  end;
  if Assigned(FOpPill) and FOpPill.Visible then
    LayoutOpPill;

  if Assigned(FMidGroup) then
    for I := 0 to FMidGroup.ControlsCount - 1 do
      if (FMidGroup.Controls[I] is TRectangle) and
         (TRectangle(FMidGroup.Controls[I]).Tag = 2) then
        TRectangle(FMidGroup.Controls[I]).Fill.Color := AColors.DividerColor;

  FFnBar.Fill.Color := Chrome.FooterBackground;
  if Assigned(FCmdBack) then
    FCmdBack.Fill.Color := AColors.PanelBackground;
  if Assigned(FCmdTopLine) then
    FCmdTopLine.Fill.Color := AColors.DividerColor;
  if Assigned(FCmdSplit) then
    FCmdSplit.Fill.Color := AColors.DividerColor;
  if Assigned(FCmdIcon) then
  begin
    FCmdIcon.TextSettings.FontColor := AColors.SubTextColor;
    FCmdIcon.Color := AColors.SubTextColor;
  end;
  if Assigned(FCmdPath) then
  begin
    FCmdPath.TextSettings.FontColor := AColors.SubTextColor;
    FCmdPath.Color := AColors.SubTextColor;
  end;
  if Assigned(FCmdEdit) then
    FCmdEdit.ApplyTheme(AColors);
  for I := 0 to 6 do
    if Assigned(FFnButtons[I]) then
      FFnButtons[I].ApplyTheme(AColors);

  FLeftPanel.ApplyTheme(PanelColors);
  FRightPanel.ApplyTheme(PanelColors);
  if Assigned(FSearchForm) then
    FSearchForm.ApplyTheme(AColors);
  UpdateViewButtons;
end;

function TMainForm.PanelForPaths(const APaths: TArray<string>): TFilePanel;
var
  Ent: TArray<TFileEntry>;
  I, J: Integer;
  Hit: Integer;
begin
  Result := nil;
  if Length(APaths) = 0 then
    Exit;
  Hit := 0;
  if Assigned(FActivePanel) then
  begin
    Ent := FActivePanel.SelectedEntries;
    for I := 0 to High(APaths) do
      for J := 0 to High(Ent) do
        if SameText(APaths[I], Ent[J].FullPath) then
          Inc(Hit);
    if Hit > 0 then
      Exit(FActivePanel);
  end;
  Result := FActivePanel;
end;

procedure TMainForm.RunCopyMove(const ASources: TArray<string>; const ADestDir: string;
  AMove: Boolean; ASrcPanel, ADestPanel: TFilePanel);
var
  FocusPath: string;
  Src, Dest: TFilePanel;
begin
  if Length(ASources) = 0 then
    Exit;

  Src := ASrcPanel;
  Dest := ADestPanel;
  if Assigned(Src) and Src.IsOffline then
  begin
    Src.ShowNotice(L('main.notice.nolink'));
    Exit;
  end;
  if Assigned(Dest) and Dest.IsOffline then
  begin
    Dest.ShowNotice(L('main.notice.nolink'));
    Exit;
  end;

  FocusPath := '';
  if AMove and Assigned(Src) then
    FocusPath := Src.FocusPathAfterRemove(ASources);

  if AMove then
    MovePathsAsync(ASources, ADestDir,
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if Assigned(Dest) then
          Dest.Refresh;
        if Assigned(Src) then
          Src.Refresh(FocusPath);
        if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> L('op.cancelled')) then
        begin
          if Assigned(Src) then
            Src.ShowNotice(ErrorMsg)
          else if Assigned(Dest) then
            Dest.ShowNotice(ErrorMsg);
        end;
      end,
      procedure(const APath: string; AStatus: TOpItemStatus)
      begin
        if (AStatus in [oisOk, oisSkipped]) and Assigned(Src) then
          Src.DeselectByPath(APath);
      end)
  else
    CopyPathsAsync(ASources, ADestDir,
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if Assigned(Dest) then
          Dest.Refresh;
        if Assigned(Src) then
          Src.InvalidateView;
        if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> L('op.cancelled')) then
        begin
          if Assigned(Src) then
            Src.ShowNotice(ErrorMsg)
          else if Assigned(Dest) then
            Dest.ShowNotice(ErrorMsg);
        end;
      end,
      procedure(const APath: string; AStatus: TOpItemStatus)
      begin
        if (AStatus in [oisOk, oisSkipped]) and Assigned(Src) then
          Src.DeselectByPath(APath);
      end);
end;

procedure TMainForm.PanelDropCopyMove(Sender: TObject; const ADest: string;
  const ASources: TArray<string>; AMove: Boolean; ASourcePanel: TFilePanel);
var
  DestPanel: TFilePanel;
begin
  if Sender is TFilePanel then
    DestPanel := TFilePanel(Sender)
  else
    DestPanel := nil;
  RunCopyMove(ASources, ADest, AMove, ASourcePanel, DestPanel);
end;

procedure TMainForm.DockCopyToFolder(Sender: TObject; const ADest: string;
  const AFiles: TArray<string>);
var
  Src: TFilePanel;
  DestPanel: TFilePanel;
begin
  Src := PanelForPaths(AFiles);
  DestPanel := nil;
  if Assigned(FLeftPanel) and SameText(
       ExcludeTrailingPathDelimiter(FLeftPanel.CurrentPath),
       ExcludeTrailingPathDelimiter(ADest)) then
    DestPanel := FLeftPanel
  else if Assigned(FRightPanel) and SameText(
       ExcludeTrailingPathDelimiter(FRightPanel.CurrentPath),
       ExcludeTrailingPathDelimiter(ADest)) then
    DestPanel := FRightPanel;
  RunCopyMove(AFiles, ADest, False, Src, DestPanel);
end;

procedure TMainForm.OnBtnCopyClick(Sender: TObject);
var
  Entries: TArray<TFileEntry>;
  Paths: TArray<string>;
  I: Integer;
begin
  if not Assigned(FActivePanel) or not FActivePanel.HasSelection then
  begin
    OpenBackgroundKind(okCopy);
    Exit;
  end;
  Entries := FActivePanel.SelectedEntries;
  if Length(Entries) = 0 then
    Exit;
  SetLength(Paths, Length(Entries));
  for I := 0 to High(Entries) do
    Paths[I] := Entries[I].FullPath;
  RunCopyMove(Paths, OtherPanel(FActivePanel).CurrentPath, False,
    FActivePanel, OtherPanel(FActivePanel));
end;

procedure TMainForm.OnBtnMoveClick(Sender: TObject);
var
  Entries: TArray<TFileEntry>;
  Paths: TArray<string>;
  I: Integer;
begin
  if not Assigned(FActivePanel) or not FActivePanel.HasSelection then
  begin
    OpenBackgroundKind(okMove);
    Exit;
  end;
  Entries := FActivePanel.SelectedEntries;
  if Length(Entries) = 0 then
    Exit;
  SetLength(Paths, Length(Entries));
  for I := 0 to High(Entries) do
    Paths[I] := Entries[I].FullPath;
  RunCopyMove(Paths, OtherPanel(FActivePanel).CurrentPath, True,
    FActivePanel, OtherPanel(FActivePanel));
end;

procedure TMainForm.OnBtnDeleteClick(Sender: TObject);
var
  Entries: TArray<TFileEntry>;
  Panel: TFilePanel;
  Permanent: Boolean;
  Paths: TArray<string>;
  FocusPath: string;
  I: Integer;
begin
  if Assigned(FActivePanel) and FActivePanel.TryForgetNetworkRecent then
    Exit;
  if not Assigned(FActivePanel) or not FActivePanel.HasSelection then
  begin
    OpenBackgroundKind(okDelete);
    Exit;
  end;
  Entries := FActivePanel.SelectedEntries;
  if Length(Entries) = 0 then Exit;
  Panel := FActivePanel;
  {$IFDEF MSWINDOWS}
  Permanent := (GetKeyState(VK_SHIFT) and $8000) <> 0;
  {$ELSE}
  Permanent := False;
  {$ENDIF}
  SetLength(Paths, Length(Entries));
  for I := 0 to High(Entries) do
    Paths[I] := Entries[I].FullPath;
  FocusPath := Panel.FocusPathAfterRemove(Paths);

  DeletePathsAsync(Paths,
    procedure(Success: Boolean; const ErrorMsg: string)
    begin
      Panel.Refresh(FocusPath);
      if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> L('op.cancelled')) then
        Panel.ShowNotice(ErrorMsg);
    end, Permanent);
end;

procedure TMainForm.OnBtnNewFolderClick(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.CreateNewFolderInPlace;
end;

procedure TMainForm.OnBtnRefreshClick(Sender: TObject);
begin
  if Assigned(FLeftPanel) then
    FLeftPanel.InvalidateFolderSizes;
  if Assigned(FRightPanel) then
    FRightPanel.InvalidateFolderSizes;
  FLeftPanel.Refresh;
  FRightPanel.Refresh;
end;

procedure TMainForm.OnBtnViewDetailsClick(Sender: TObject);
begin
  ApplyPanelView(FActivePanel, vmDetails);
end;

procedure TMainForm.OnBtnViewTilesClick(Sender: TObject);
begin
  ApplyPanelView(FActivePanel, vmTiles);
end;

procedure TMainForm.OnBtnViewClick(Sender: TObject);
var
  FocusedEntry: TFileEntry;
begin
  if Assigned(FActivePanel) and FActivePanel.GetFocusedEntry(FocusedEntry) then
    ShowQuickViewWindow(FocusedEntry.FullPath);
end;

procedure TMainForm.OnBtnOpenClick(Sender: TObject);
begin
  FActivePanel.OpenSelected;
end;

procedure TMainForm.ShowMultiRename;
var
  Entries: TArray<TFileEntry>;
  Frm: TMultiRenameForm;
begin
  if not Assigned(FActivePanel) then
    Exit;
  Entries := FActivePanel.SelectedEntries;
  if Length(Entries) = 0 then
    Exit;
  Frm := TMultiRenameForm.Create(Self, Entries, FColors);
  try
    if Frm.ShowModal = mrOk then
      FActivePanel.Refresh('');
  finally
    Frm.Free;
  end;
end;

procedure TMainForm.OnBtnRenameClick(Sender: TObject);
begin
  if not Assigned(FActivePanel) then
    Exit;
  if FActivePanel.HasMultiSelection then
    ShowMultiRename
  else
    FActivePanel.StartInlineRename;
end;

procedure TMainForm.OnBtnArchiveClick(Sender: TObject);
var
  Entries: TArray<TFileEntry>;
  Paths: TArray<string>;
  DestDir, ZipName, ZipPath: string;
  I: Integer;
  Panel: TFilePanel;
begin
  if not Assigned(FActivePanel) or not FActivePanel.HasSelection then
  begin
    OpenBackgroundKind(okArchive);
    Exit;
  end;
  Entries := FActivePanel.SelectedEntries;
  if Length(Entries) = 0 then Exit;

  SetLength(Paths, Length(Entries));
  for I := 0 to High(Entries) do
    Paths[I] := Entries[I].FullPath;

  if Length(Entries) = 1 then
    ZipName := ChangeFileExt(Entries[0].Name, '') + '.zip'
  else
    ZipName := 'Archive.zip';

  Panel := FActivePanel;
  DestDir := OtherPanel(Panel).CurrentPath;
  ZipPath := IncludeTrailingPathDelimiter(DestDir) + ZipName;

  ArchivePathsAsync(Paths, ZipPath,
    procedure(Success: Boolean; const ErrorMsg: string)
    begin
      if Success then
      begin
        Panel.ClearSelection;
        OtherPanel(Panel).Refresh;
      end;
    end);
end;

procedure TMainForm.SearchFormClosed(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caFree;
  if FSearchForm = Sender then
    FSearchForm := nil;
  if Assigned(FCmdSearch) then
  begin
    FCmdSearch.HoldHover(False);
    FCmdSearch.EndBusy;
  end;
end;

procedure TMainForm.SearchStateChanged(Sender: TObject);
begin
  if not Assigned(FCmdSearch) then
    Exit;
  FCmdSearch.HoldHover(Assigned(FSearchForm) and FSearchForm.InBackground);
  if Assigned(FSearchForm) and FSearchForm.Running then
    FCmdSearch.StartBusy
  else
    FCmdSearch.EndBusy;
end;

procedure TMainForm.ShowSearch;
begin
  if not Assigned(FActivePanel) then
    Exit;
  if Assigned(FSearchForm) then
  begin
    FSearchForm.ApplyTheme(FColors);
    FSearchForm.RestoreFromBackground;
    Exit;
  end;
  FSearchForm := TSearchForm.Create(Self, FActivePanel.CurrentPath, FColors);
  FSearchForm.OnClose := SearchFormClosed;
  FSearchForm.OnStateChange := SearchStateChanged;
  FSearchForm.OnGoToHit :=
    procedure(APath, ADir: string; AIsDir: Boolean)
    begin
      if not Assigned(FActivePanel) or (APath = '') then
        Exit;
      if AIsDir then
        FActivePanel.Navigate(APath)
      else
        FActivePanel.Navigate(ADir, APath);
    end;
  FSearchForm.OnFeedToPanel :=
    procedure(ARoot: string; AList: TFileEntryList)
    begin
      if Assigned(FActivePanel) then
        FActivePanel.ShowSearchHits(ARoot, AList)
      else if Assigned(AList) then
        AList.Free;
    end;
  FSearchForm.Show;
end;

procedure TMainForm.OnBtnSearchClick(Sender: TObject);
begin
  ShowSearch;
end;

procedure TMainForm.OnBtnSelectClick(Sender: TObject);
begin
  if Assigned(FSelMenu) and Assigned(FCmdSelect) then
  begin
    BuildSelMenu;
    FSelMenu.ApplyTheme(FColors);
    { Меню на стороне неактивной панели: активна левая — открыть вправо. }
    FSelMenu.PopupNear(FCmdSelect, Assigned(FActivePanel) and
      (FActivePanel = FLeftPanel));
  end;
end;

procedure TMainForm.OnSelAll(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.SelectAllItems;
end;

procedure TMainForm.OnSelNone(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.ClearSelection;
end;

procedure TMainForm.OnSelInvert(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.InvertSelection;
end;

procedure TMainForm.AskSelectMask(ASelect: Boolean);
var
  Mask: string;
  Title: string;
begin
  if not Assigned(FActivePanel) then
    Exit;
  Mask := FLastSelectMask;
  if Mask = '' then
    Mask := '*.*';
  if ASelect then
    Title := L('main.sel.mask')
  else
    Title := L('main.sel.unmask');
  if not FluentInputQuery(Title, L('main.mask.prompt'), Mask, FColors, Self) then
    Exit;
  Mask := Trim(Mask);
  if Mask = '' then
    Exit;
  FLastSelectMask := Mask;
  FActivePanel.SelectByWildcard(Mask, ASelect);
end;

procedure TMainForm.OnSelMask(Sender: TObject);
begin
  AskSelectMask(True);
end;

procedure TMainForm.OnUnselMask(Sender: TObject);
begin
  AskSelectMask(False);
end;

procedure TMainForm.OnSelExt(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.SelectSameExtension(True);
end;

procedure TMainForm.OnUnselExt(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.SelectSameExtension(False);
end;

procedure TMainForm.OnSelFiles(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.SelectFilesOnly;
end;

procedure TMainForm.OnSelFolders(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.SelectFoldersOnly;
end;

procedure TMainForm.OnSelCompare(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.CompareDirectories(OtherPanel(FActivePanel));
end;

function TMainForm.PanelAtCursor: TFilePanel;
var
  P: TPointF;
begin
  Result := FActivePanel;
  P := ScreenToClient(Screen.MousePos);
  if Assigned(FLeftPanel) and FLeftPanel.AbsoluteRect.Contains(P) then
    Result := FLeftPanel
  else if Assigned(FRightPanel) and FRightPanel.AbsoluteRect.Contains(P) then
    Result := FRightPanel;
end;

procedure TMainForm.HistoryShortcut(ADelta: Integer; AFromMouse: Boolean);
var
  Panel: TFilePanel;
  NowTick: UInt64;
begin
  NowTick := GetTickCount64;
  if NowTick - FLastHistNavTick < 120 then
    Exit;
  FLastHistNavTick := NowTick;
  if AFromMouse then
    Panel := PanelAtCursor
  else
    Panel := FActivePanel;
  if not Assigned(Panel) then
    Exit;
  if Panel.IsPathEditing or Panel.IsInlineRenaming then
    Exit;
  if ADelta < 0 then
    Panel.HistoryBack
  else
    Panel.HistoryForward;
end;

procedure TMainForm.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    if Assigned(FOpPop) and FOpPop.IsOpen then
    begin
      FOpPop.IsOpen := False;
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
    if (Assigned(FLeftPanel) and FLeftPanel.DriveHomeIsOpen) or
       (Assigned(FRightPanel) and FRightPanel.DriveHomeIsOpen) then
    begin
      CloseDriveHomes;
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
  end;
  if CmdLineFocused then
  begin
    if ((Key = vkUp) or (Key = vkDown)) and
       not (ssAlt in Shift) and not (ssCtrl in Shift) then
    begin
      if Key = vkUp then
        CmdHistStep(-1)
      else
        CmdHistStep(1);
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
    if (Key = vkF5) and not (ssAlt in Shift) then
    begin
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
    if Key = vkTab then
    begin
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
    inherited;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  var ShiftStr := '';
  if ssCtrl in Shift then ShiftStr := ShiftStr + 'Ctrl + ';
  if ssAlt in Shift then ShiftStr := ShiftStr + 'Alt + ';
  if ssShift in Shift then ShiftStr := ShiftStr + 'Shift + ';

 // Caption := Format('Debug -> Key: %d (0x%x) | Char: "%s" | Shift: [%s]',     [Key, Key, KeyChar, ShiftStr]);


  if KeyChar = '*' then Key := vkMultiply;
  if KeyChar = '+' then Key := vkAdd;
  if KeyChar = '-' then Key := vkSubtract;
  if Key = 9 then Key := 442;

  if (Key = vkF5) and (ssAlt in Shift) then
  begin
    OnBtnArchiveClick(nil);
    Key := 0;
    Exit;
  end;
  if (Key = vkF7) and (ssAlt in Shift) then
  begin
    OnBtnSearchClick(nil);
    Key := 0;
    Exit;
  end;
  if (Key = vkF1) and (ssAlt in Shift) and not (ssCtrl in Shift) then
  begin
    if Assigned(FLeftPanel) and FLeftPanel.ToggleDriveHome then
    begin
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
  end;
  if (Key = vkF2) and (ssAlt in Shift) and not (ssCtrl in Shift) then
  begin
    if Assigned(FRightPanel) and FRightPanel.ToggleDriveHome then
    begin
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
  end;
  if (Key = vkF5) and not (ssAlt in Shift) and
     not (Assigned(FActivePanel) and
       (FActivePanel.IsPathEditing or FActivePanel.IsInlineRenaming)) and
     not (Assigned(FQuickSearch) and FQuickSearch.EditorFocused) then
  begin
    Key := 0;
    KeyChar := #0;
    OnBtnCopyClick(nil);
    Exit;
  end;
  if (Key = vkF6) and not (ssAlt in Shift) and
     not (Assigned(FActivePanel) and
       (FActivePanel.IsPathEditing or FActivePanel.IsInlineRenaming)) and
     not (Assigned(FQuickSearch) and FQuickSearch.EditorFocused) then
  begin
    Key := 0;
    KeyChar := #0;
    OnBtnMoveClick(nil);
    Exit;
  end;
  if (Key = vkLeft) and (ssAlt in Shift) then
  begin
    HistoryShortcut(-1);
    Key := 0;
    Exit;
  end;
  if (Key = vkRight) and (ssAlt in Shift) then
  begin
    HistoryShortcut(1);
    Key := 0;
    Exit;
  end;

  inherited;

  if Key = 0 then
    Exit;

  if (ssCtrl in Shift) and not (ssAlt in Shift) and
     ((Key = vkF) or (Key = vkE)) then
  begin
    if Assigned(FQuickSearch) then
    begin
      FQuickSearch.FocusEditor;
      Key := 0;
      Exit;
    end;
  end;

  if Assigned(FActivePanel) and
     (FActivePanel.IsPathEditing or FActivePanel.IsInlineRenaming) then
    Exit;

  if Assigned(FActivePanel) and FActivePanel.PreviewEditKey(Key, Shift) then
  begin
    Key := 0;
    Exit;
  end;

  if Assigned(FQuickSearch) and FQuickSearch.EditorFocused then
  begin
    if (Key <> 442) and ((Key < vkF2) or (Key > vkF9)) then
      Exit;
  end;

  if PreviewWantsKeys then
  begin
    case Key of
      vkUp, vkDown, vkLeft, vkRight, vkHome, vkEnd, vkPrior, vkNext,
      vkInsert, vkReturn, vkBack:
        Exit;
      vkC, vkX, vkV:
        if ssCtrl in Shift then
          Exit;
    end;
    if KeyChar = ' ' then
      Exit;
  end;

  if Assigned(FActivePanel) and FActivePanel.HandleSelectionKey(Key, Shift) then
  begin
    Key := 0;
    FActivePanel.UpdateStatusText;
    Exit;
  end;

  if not (ssCtrl in Shift) and not (ssAlt in Shift) then
  begin
    if Key = vkAdd then
    begin
      AskSelectMask(True);
      Key := 0;
      Exit;
    end;
    if Key = vkSubtract then
    begin
      AskSelectMask(False);
      Key := 0;
      Exit;
    end;
  end;

  if (Key = vkF1) and (ssCtrl in Shift) and (ssShift in Shift) then
  begin
    if Assigned(FActivePanel) then
    begin
      if FActivePanel.ViewMode = vmDetails then
        FActivePanel.SetViewMode(vmTiles)
      else
        FActivePanel.SetViewMode(vmDetails);
      UpdateViewButtons;
    end;
    Key := 0;
  end
  else if (Key = vkQ) and (ssCtrl in Shift) then
  begin
    TogglePanelQuickView;
    Key := 0;
  end
  else if Key = vkF2 then
  begin
    OnBtnRenameClick(nil);
    Key := 0;
  end
  else if Key = vkF3 then
  begin
    OnBtnViewClick(nil);
    Key := 0;
  end
  else if Key = vkF4 then
  begin
    OnBtnSearchClick(nil);
    Key := 0;
  end
  else if Key = vkF5 then
  begin
    if ssAlt in Shift then
      OnBtnArchiveClick(nil)
    else
      OnBtnCopyClick(nil);
    Key := 0;
  end
  else if Key = vkF7 then
  begin
    if ssAlt in Shift then
      OnBtnSearchClick(nil)
    else
      OnBtnNewFolderClick(nil);
    Key := 0;
  end
  else if (Key = vkF8) or (Key = vkDelete) then
  begin
    OnBtnDeleteClick(nil);
    Key := 0;
  end
  else if Key = vkF9 then
  begin
    OnBtnRenameClick(nil);
    Key := 0;
  end
  else if (Key = vkB) and (ssCtrl in Shift) then
  begin
    if Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
      FActivePanel.ToggleBranchView;
    Key := 0;
  end
  else if (Key = vkM) and (ssCtrl in Shift) then
  begin
    if Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
      ShowMultiRename;
    Key := 0;
  end
  else if (Key = vkC) and (ssCtrl in Shift) then
  begin
    if Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
      FActivePanel.CopySelectionToClipboard(False);
    Key := 0;
  end
  else if (Key = vkX) and (ssCtrl in Shift) then
  begin
    if Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
      FActivePanel.CopySelectionToClipboard(True);
    Key := 0;
  end
  else if (Key = vkV) and (ssCtrl in Shift) then
  begin
    if (Screen.ActiveForm = nil) or (Screen.ActiveForm = Self) then
      if Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
        FActivePanel.HandlePaste;
    Key := 0;
  end
  else if (Key = vkT) and (ssCtrl in Shift) then
  begin
    if Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
      FActivePanel.AddTab;
    Key := 0;
  end
  else if Key = 442 then
  begin
    if FActivePanel = FLeftPanel then
      UsePanel(FRightPanel, True)
    else
      UsePanel(FLeftPanel, True);
    Key := 0;
  end
  else if Key = vkUp then
  begin
    if FActivePanel.ViewMode = vmDetails then
      FActivePanel.MoveSelection(-1, Shift)
    else
      FActivePanel.MoveSelectionGrid(0, -1, Shift);
    Key := 0;
  end
  else if Key = vkDown then
  begin
    if FActivePanel.ViewMode = vmDetails then
      FActivePanel.MoveSelection(1, Shift)
    else
      FActivePanel.MoveSelectionGrid(0, 1, Shift);
    Key := 0;
  end
  else if Key = vkLeft then
  begin
    if FActivePanel.ViewMode <> vmDetails then
      FActivePanel.MoveSelectionGrid(-1, 0, Shift);
    Key := 0;
  end
  else if Key = vkRight then
  begin
    if FActivePanel.ViewMode <> vmDetails then
      FActivePanel.MoveSelectionGrid(1, 0, Shift);
    Key := 0;
  end
  else if (Key = vkReturn) and (ssAlt in Shift) then
  begin
    if Assigned(FActivePanel) and not (ssCtrl in Shift) then
      FActivePanel.CountCursorFolder;
    Key := 0;
    KeyChar := #0;
  end
  else if Key = vkReturn then
  begin
    FActivePanel.OpenSelected;
    Key := 0;
  end
  else if Key = vkBack then
  begin
    FActivePanel.GoBack;
    Key := 0;
  end
  else if Key = vkHome then
  begin
    FActivePanel.MoveHome(Shift);
    Key := 0;
  end
  else if Key = vkEnd then
  begin
    FActivePanel.MoveEnd(Shift);
    Key := 0;
  end
  else if Key = vkPrior then
  begin
    FActivePanel.MovePage(-1, Shift);
    Key := 0;
  end
  else if Key = vkNext then
  begin
    FActivePanel.MovePage(1, Shift);
    Key := 0;
  end
  else if Key = vkInsert then
  begin
    if (ssShift in Shift) and
       ((Screen.ActiveForm = nil) or (Screen.ActiveForm = Self)) and
       Assigned(FActivePanel) and not FActivePanel.IsPathEditing then
      FActivePanel.HandlePaste
    else
      FActivePanel.ToggleCurrentAndMove;
    Key := 0;
  end
  else if KeyChar = ' ' then
  begin
    FActivePanel.ToggleCurrentAndMove;
    Key := 0;
  end;
end;

procedure TMainForm.CloseDriveHomes;
begin
  if Assigned(FLeftPanel) then
    FLeftPanel.CloseDriveHome;
  if Assigned(FRightPanel) then
    FRightPanel.CloseDriveHome;
end;

procedure TMainForm.PanelActivate(Sender: TObject);
begin
  CloseDriveHomes;
  if Assigned(FLeftPanel) then
    FLeftPanel.CancelPathEdit;
  if Assigned(FRightPanel) then
    FRightPanel.CancelPathEdit;
  if Sender is TFilePanel then
    UsePanel(TFilePanel(Sender), True);
end;

initialization

finalization
  {$IFDEF MSWINDOWS}
  if GAppMutex <> 0 then
  begin
    CloseHandle(GAppMutex);
    GAppMutex := 0;
  end;
  {$ENDIF}

end.

