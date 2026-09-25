unit uMain;

interface

uses
Winapi.Windows, Winapi.Messages, Winapi.DwmApi, Winapi.UxTheme,
  Winapi.ShlObj, System.Win.ComObj, FMX.Platform.Win,
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils, System.Types,
  FMX.Forms, FMX.Types, FMX.Layouts, FMX.StdCtrls, FMX.Objects,
  FMX.Controls, FMX.ListBox, FMX.Graphics, FMX.Dialogs, System.Math,
  FileSelectionManager,

  uAppSettings, uThemeManager, uFluentChrome, uFluentEdit, uFluentComboBox,
  uFilePanel, uThumbCache,
  uIconCache, uMetaCache,
  uQuickViewForm, uLaunchDock,
  uSettingsForm, uFileOps, uFileModel, UCoreEngine, uMultiRenameForm, uSearchForm
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

    FFnBar: TRectangle;
    FFnCells: array[0..6] of TLayout;
    FFnButtons: array[0..6] of TFluentButton;
    FCmdLine: TRectangle;
    FCmdEdit: TFluentEdit;

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
    FCenterOnRestore: Boolean;
    FStartupDone: Boolean;
    FFading: Boolean;
    FStartupPhase: Integer;
    FFirstPaintLogged: Boolean;
    FLeftReady: Boolean;
    FRightReady: Boolean;
    FFadeTimer: TTimer;
    FStartupTimer: TTimer;
    FIdlePlusTimer: TTimer;
    FStaleTimer: TTimer;
    FPreviewDebounce: TTimer;
    FPreviewPending: string;
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
    procedure BuildWorkArea;
    procedure LayoutFunctionBar;
    procedure LayoutWorkArea;
    procedure ApplyLeftPanelWidth(AWidth: Single);
    function CenterBandWidth: Single;
    procedure ApplyCenterBandLayout;
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
    procedure CenterNormalWindow;
    procedure PersistWindowState;
    procedure NativeSysCommand(ACmd: NativeUInt);
    procedure StartStartupFade;
    procedure FadeTick(Sender: TObject);
    procedure FinishStartupFade;
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
    procedure AskSelectMask(ASelect: Boolean);
    procedure ShowSearch;
    procedure SearchFormClosed(Sender: TObject; var Action: TCloseAction);
    procedure SearchStateChanged(Sender: TObject);
    procedure HistoryShortcut(ADelta: Integer; AFromMouse: Boolean = False);
    function PanelAtCursor: TFilePanel;
    procedure PanelActivate(Sender: TObject);

    procedure LeftPanelPathChanged(Sender: TObject; const APath: string);
    procedure RightPanelPathChanged(Sender: TObject; const APath: string);

    procedure PanelQuickView(Sender: TObject; const APath: string);
    procedure PanelCursorChanged(Sender: TObject);
    procedure PreviewDebounceTick(Sender: TObject);
    procedure TogglePanelQuickView;
    procedure ShowQuickViewWindow(const APath: string);
    procedure ShowQuickViewForPath(const APath: string);
    function PreviewWantsKeys: Boolean;

    procedure ApplyThemeToAll(const AColors: TThemeColors);
    procedure ApplyDriveOptions;
    procedure CmdLineSubmit(Sender: TObject);
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
  MIDBAR_WIDTH = 40;
  SPLITTER_WIDTH = 4;
  CENTER_CLUSTER_WIDTH = SPLITTER_WIDTH + MIDBAR_WIDTH + SPLITTER_WIDTH;
  MIN_PANEL_WIDTH = 180;
  WORK_PAD_L = 8;
  WORK_PAD_T = 6;
  WORK_PAD_R = 8;
  WORK_PAD_B = 4;

  MIDBAR_TOP = 38;
  MIDBAR_BOTTOM = 8;
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
begin
  Result := False;
  GAppMutex := CreateMutex(nil, True, APP_MUTEX_NAME);
  if (GAppMutex = 0) or (GetLastError <> ERROR_ALREADY_EXISTS) then
    Exit;
  GFoundWnd := 0;
  Winapi.Windows.EnumWindows(@EnumVibeWnd, 0);
  if GFoundWnd = 0 then
    GFoundWnd := Winapi.Windows.FindWindow(nil, PChar('V!BE CMD'));
  Wnd := GFoundWnd;
  if Wnd <> 0 then
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
  end;
  Result := True;
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
  SetActiveAppTheme(FSettings.Theme);
  SetFileOpMode(FSettings.FileOpMode);

  Constraints.MinHeight := MIN_WINDOW_HEIGHT;
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
  FQuickView := nil;
  FChromeWatch := nil;
end;

destructor TMainForm.Destroy;
begin
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

  { Сначала сохранить настройки (пока объекты живы), потом гасить кэши. }
  if Assigned(FSettings) then
  begin
    if Assigned(FSearchHist) then
    begin
      SetLength(FSettings.SearchHistory, FSearchHist.Count);
      for var HI := 0 to FSearchHist.Count - 1 do
        FSettings.SearchHistory[HI] := FSearchHist[HI];
    end;
    PersistWindowState;
    FSettings.SplitterPos := FLeftPanelRatio;
    if FActivePanel = FRightPanel then
      FSettings.ActivePanel := 1
    else
      FSettings.ActivePanel := 0;
    if Assigned(FLeftPanel) then
      FLeftPanel.CaptureTabs(FSettings.Left);
    if Assigned(FRightPanel) then
      FRightPanel.CaptureTabs(FSettings.Right);
    if Assigned(FDock) then
    begin
      FDock.CollectState(FSettings.DockItems, FSettings.DockItemX,
        FSettings.DockKinds, FSettings.DockCaptions, FSettings.DockIcons,
        FSettings.DockIconLocked);
      FSettings.DockAlign := FDock.AlignMode;
      FSettings.DockShowSeparators := FDock.ShowSeparators;
    end;
    try
      FSettings.Save;
    except
    end;
    FreeAndNil(FSettings);
  end;
  if Assigned(FSearchDebounce) then
    FSearchDebounce.Enabled := False;
  FreeAndNil(FSearchHist);

  { Shutdown кэшей короткий (FShuttingDown + малый timeout). }
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.Shutdown;
  if Assigned(GlobalIconCache) then
    GlobalIconCache.Shutdown;
  if Assigned(GlobalMetaCache) then
    GlobalMetaCache.Shutdown;

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
  ApplyCustomFrame;
  {$IFDEF MSWINDOWS}
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  {$ENDIF}
  LayoutWorkArea;
  LayoutQuickSearch;
  if Assigned(FLeftPanel) and Assigned(FRightPanel) then
  begin
    if FActivePanel = FRightPanel then
    begin
      FRightPanel.SetActive(True);
      FLeftPanel.SetActive(False);
    end
    else
    begin
      FActivePanel := FLeftPanel;
      FLeftPanel.SetActive(True);
      FRightPanel.SetActive(False);
    end;
  end;
  LayoutFunctionBar;
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
  { Сразу убрать окно — пользователь не ждёт Shutdown/Save. }
  try
    Visible := False;
{$IFDEF MSWINDOWS}
  if FormToHWND(Self) <> 0 then
  ShowWindow(FormToHWND(Self), SW_HIDE);
{$ENDIF}
  except
  end;
  CancelListFileOps;
  PersistWindowState;
  inherited;
  Application.Terminate;
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
      if LoWord(wParam) <> WA_INACTIVE then
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
       if (NativeUInt(wParam) and $FFF0) = SC_CLOSE then
  begin
    PostMessage(hWnd, WM_CLOSE, 0, 0);
    Exit(0);
  end;

        // ИСПРАВЛЕНИЕ: Используем DefWindowProc вместо FMX обработчика для системных кнопок
        if (Cmd = SC_MAXIMIZE) or (Cmd = SC_RESTORE) or (Cmd = SC_MINIMIZE) then
        begin
          if Cmd = SC_MAXIMIZE then
            GHookForm.CaptureNormalGeometry;

          // Важно: Вызываем DefWindowProc, чтобы Windows сама управляла состоянием HWND
          Result := DefWindowProc(hWnd, Msg, wParam, lParam);

          // Синхронизируем состояние FMX и настроек ПОСЛЕ того как Windows изменила окно
          TThread.ForceQueue(nil,
            procedure
            var
              LPlacement: TWindowPlacement;
            begin
              if (GHookForm <> nil) and (hWnd <> 0) then
              begin
                LPlacement.length := SizeOf(LPlacement);
                if GetWindowPlacement(hWnd, @LPlacement) then
                begin
                  // Синхронизируем флаг
                  GHookForm.FSettings.WindowMaximized := (LPlacement.showCmd = SW_SHOWMAXIMIZED);
                  // Принудительно уведомляем FMX о смене состояния, чтобы он не конфликтовал
                  if GHookForm.FSettings.WindowMaximized then
                    GHookForm.WindowState := TWindowState.wsMaximized
                  else if LPlacement.showCmd = SW_SHOWNORMAL then
                    GHookForm.WindowState := TWindowState.wsNormal;
                end;
                GHookForm.UpdateWindowButtons;
                // Лечим баг с фокусом и залипшим Alt
                PostMessage(hWnd, WM_REFRESH_FOCUS, 0, 0);
              end;
            end);
          Exit;
        end;





      if Cmd = SC_MINIMIZE then
      begin
        if not IsZoomed(hWnd) then
          GHookForm.CaptureNormalGeometry;
        Exit(DefWindowProc(hWnd, Msg, wParam, lParam));
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
  FSettings.WindowHeight := Max(Round(Height), MIN_WINDOW_HEIGHT);
end;

procedure TMainForm.ApplyStartupGeometry;
var
  WA: TRectF;
  W, H, L, T: Single;
begin
  WA := CurrentWorkArea;
  if WA.Width < 200 then
    WA := TRectF.Create(0, 0, 1280, 800);
  W := FSettings.WindowWidth;
  H := FSettings.WindowHeight;
  if W < 400 then
    W := 1200;
  if H < MIN_WINDOW_HEIGHT then
    H := MIN_WINDOW_HEIGHT;

  FPendingMaximized := FSettings.WindowMaximized;
  FCenterOnRestore := FPendingMaximized;
  if FPendingMaximized then
  begin
    if W > WA.Width * 0.92 then
      W := Min(1200, Max(480, WA.Width * 0.72));
    if H > WA.Height * 0.92 then
      H := Min(Max(MIN_WINDOW_HEIGHT, 700), Max(MIN_WINDOW_HEIGHT, WA.Height * 0.72));
    L := WA.Left + (WA.Width - W) / 2;
    T := WA.Top + (WA.Height - H) / 2;
  end
  else
  begin
    L := FSettings.WindowLeft;
    T := FSettings.WindowTop;
    if L + Min(W, 160) < WA.Left then
      L := WA.Left;
    if T < WA.Top then
      T := WA.Top;
    if L > WA.Right - 80 then
      L := WA.Right - Min(W, WA.Width);
    if T > WA.Bottom - 40 then
      T := WA.Top;
  end;
  Width := Round(W);
  Height := Round(H);
  Left := Round(L);
  Top := Round(T);
  FSettings.WindowLeft := Left;
  FSettings.WindowTop := Top;
  FSettings.WindowWidth := Width;
  FSettings.WindowHeight := Height;
end;

procedure TMainForm.CenterNormalWindow;
var
  WA: TRectF;
  W, H: Single;
begin
  if (csDestroying in ComponentState) or IsWindowMaximized then
    Exit;
  WA := CurrentWorkArea;
  W := FSettings.WindowWidth;
  H := Max(FSettings.WindowHeight, MIN_WINDOW_HEIGHT);
  if W < 400 then
    W := 1200;
  if W > WA.Width * 0.92 then
    W := Min(1200, Max(480, WA.Width * 0.72));
  if H > WA.Height * 0.92 then
    H := Min(Max(MIN_WINDOW_HEIGHT, 700), Max(MIN_WINDOW_HEIGHT, WA.Height * 0.72));
  Left := Round(WA.Left + (WA.Width - W) / 2);
  Top := Round(WA.Top + (WA.Height - H) / 2);
  Width := Round(W);
  Height := Round(H);
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
    if FPendingMaximized then
      ShowCmd := SW_SHOWMAXIMIZED
    else
      ShowCmd := SW_SHOWNA;
    FPendingMaximized := False;
    ShowWindow(Wnd, ShowCmd);
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
  FQuickSearch.TextPrompt := 'Поиск в панели';
  FQuickSearch.Glyph := #$E721;
  FQuickSearch.Items.Assign(FSearchHist);
  if FSearchHist.Count > 0 then
    FQuickSearch.FooterCaption := 'Очистить историю';
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
begin
  if not Assigned(APanel) then
    Exit;
  if FActivePanel <> APanel then
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
    FQuickSearch.FooterCaption := 'Очистить историю'
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
    FQuickSearch.FooterCaption := 'Очистить историю';
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
  { CollectState — быстро (только массивы в памяти). }
  FDock.CollectState(FSettings.DockItems, FSettings.DockItemX,
    FSettings.DockKinds, FSettings.DockCaptions, FSettings.DockIcons,
    FSettings.DockIconLocked);
  FSettings.DockAlign := FDock.AlignMode;
  FSettings.DockShowSeparators := FDock.ShowSeparators;
  { Запись INI в фоне — не блокирует UI после reorder/drop. }
  FSettings.SaveDockAsync;
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

  FMidGroup := TLayout.Create(Self);
  FMidGroup.Parent := FMidBar;
  FMidGroup.Align := TAlignLayout.VertCenter;
  FMidGroup.Width := MIDBAR_WIDTH;

  Y := 0;
  FCmdCopy := MakeMidButton('', 'Копировать (F5)', OnBtnCopyClick);
  PlaceBtn(FCmdCopy);
  FCmdMove := MakeMidButton('', 'Переместить (F6)', OnBtnMoveClick);
  PlaceBtn(FCmdMove);
  FCmdDelete := MakeMidButton('', 'Удалить (F8)', OnBtnDeleteClick);
  PlaceBtn(FCmdDelete);
  AddDivider;
  FCmdRename := MakeMidButton('', 'Переименовать (F2)', OnBtnRenameClick);
  PlaceBtn(FCmdRename);
  FCmdArchive := MakeMidButton('', 'Архивировать (Alt+F5)', OnBtnArchiveClick);
  PlaceBtn(FCmdArchive);
  AddDivider;
  FCmdNewFolder := MakeMidButton('', 'Новая папка (F7)', OnBtnNewFolderClick);
  PlaceBtn(FCmdNewFolder);
  FCmdSearch := MakeMidButton('', 'Поиск (F4)', OnBtnSearchClick);
  PlaceBtn(FCmdSearch);
  FCmdSelect := MakeMidButton(#$E9D5, 'Выделение', OnBtnSelectClick);
  PlaceBtn(FCmdSelect);
  AddDivider;
  FCmdRefresh := MakeMidButton('', 'Обновить', OnBtnRefreshClick);
  PlaceBtn(FCmdRefresh);
  FCmdQuickView := MakeMidButton('', 'Быстрый просмотр (Ctrl+Q)', OnBtnQuickViewToggle);
  PlaceBtn(FCmdQuickView);
  FCmdDetails := MakeMidButton('', 'Подробно', OnBtnViewDetailsClick);
  PlaceBtn(FCmdDetails);
  FCmdTiles := MakeMidButton('', 'Плитки', OnBtnViewTilesClick);
  PlaceBtn(FCmdTiles);

  FMidGroup.Height := Y;

  FLastSelectMask := '*.*';
  FSelMenu := TFluentPopupMenu.Create(Self);
  FSelMenu.Parent := Self;

 FSelMenu.AddItem('Выделить всё', 'Ctrl+A', OnSelAll);

  FSelMenu.AddItem('Сравнить каталоги', '', OnSelCompare);

  FSelMenu.AddSeparator;
  FSelMenu.AddItem('Выделить только папки', '', OnSelFolders);
  FSelMenu.AddItem('Выделить только файлы', '', OnSelFiles);
   FSelMenu.AddItem('Снять с таким же типом', 'Alt+-', OnUnselExt);
   FSelMenu.AddItem('Выделить с таким же типом', 'Alt++', OnSelExt);
   FSelMenu.AddItem('Снять по маске...', '-', OnUnselMask);
  FSelMenu.AddItem('Выделить по маске...', '+', OnSelMask);



 FSelMenu.AddSeparator;

   FSelMenu.AddItem('Инвертировать', '*', OnSelInvert);
  FSelMenu.AddItem('Снять всё', 'Ctrl+-', OnSelNone);

end;

procedure TMainForm.BuildFunctionBar;
const
  Caps: array[0..6] of string =
    ('Переименовать', 'Просмотр', 'Поиск', 'Копирование', 'Переместить',
     'Новая папка', 'Удалить');
  Keys: array[0..6] of string = ('F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8');
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
  FFnBar.Padding.Rect := TRectF.Create(8, 5, 8, 6);

  FCmdLine := TRectangle.Create(Self);
  FCmdLine.Parent := FFnBar;
  FCmdLine.Align := TAlignLayout.Top;
  FCmdLine.Height := 30;
  FCmdLine.Stroke.Kind := TBrushKind.None;
  FCmdLine.Fill.Color := TAlphaColors.Null;
  FCmdLine.Visible := False;
  FCmdEdit := CreateFluentEdit(Self, FCmdLine);
  FCmdEdit.Align := TAlignLayout.Client;
  FCmdEdit.FillMode := fefSubtle;
  FCmdEdit.OnSubmit := CmdLineSubmit;

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
    FFnButtons[I].Setup(FFnCells[I], '', Caps[I], fbkKey, Handlers[I]);
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

  FRightPanel := TFilePanel.Create(Self);
  FRightPanel.Parent := FWorkArea;
  FRightPanel.Align := TAlignLayout.None;
  FRightPanel.OnPathChanged := RightPanelPathChanged;
  FRightPanel.OnQuickView := PanelQuickView;
  FRightPanel.OnCursorChange := PanelCursorChanged;

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

procedure TMainForm.LayoutFunctionBar;
var
  I: Integer;
  CellW, TopY, CellH: Single;
begin
  if not Assigned(FFnBar) then
    Exit;
  TopY := 0;
  if Assigned(FCmdLine) and FCmdLine.Visible then
    TopY := FCmdLine.Height;
  CellW := Max(70, (FFnBar.Width - FFnBar.Padding.Left - FFnBar.Padding.Right) / 7);
  CellH := FFnBar.Height - FFnBar.Padding.Top - FFnBar.Padding.Bottom - TopY;
  if CellH < 24 then
    CellH := 24;
  for I := 0 to 6 do
    if Assigned(FFnCells[I]) then
      FFnCells[I].SetBounds(I * CellW, TopY, CellW, CellH);
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
  UpdateWindowButtons;
  LayoutQuickSearch;
  LayoutWorkArea;

  CaptureNormalGeometry;

  LayoutFunctionBar;
end;

procedure TMainForm.LeftPanelPathChanged(Sender: TObject; const APath: string);
begin
  UsePanel(FLeftPanel, False);
end;

procedure TMainForm.RightPanelPathChanged(Sender: TObject; const APath: string);
begin
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

procedure TMainForm.PanelCursorChanged(Sender: TObject);
var
  Other: TFilePanel;
  Entry: TFileEntry;
  Path: string;
begin
  if Sender <> FActivePanel then
    Exit;
  Other := OtherPanel(FActivePanel);
  if (Other = nil) or not Other.IsPreviewActive then
    Exit;
  if Assigned(FActivePanel) and FActivePanel.IsOffline then
    Exit;
  if FActivePanel.GetFocusedEntry(Entry) then
    Path := Entry.FullPath
  else
    Path := FActivePanel.CurrentPath;
  if IsRemotePath(Path) or (Assigned(FActivePanel) and IsRemotePath(FActivePanel.CurrentPath)) then
  begin
    FPreviewPending := Path;
    if FPreviewDebounce = nil then
    begin
      FPreviewDebounce := TTimer.Create(Self);
      FPreviewDebounce.Interval := 300;
      FPreviewDebounce.OnTimer := PreviewDebounceTick;
    end;
    FPreviewDebounce.Enabled := False;
    FPreviewDebounce.Enabled := True;
    Exit;
  end;
  Other.PreviewFile(Path);
end;

procedure TMainForm.PreviewDebounceTick(Sender: TObject);
var
  Other: TFilePanel;
begin
  if Assigned(FPreviewDebounce) then
    FPreviewDebounce.Enabled := False;
  if FPreviewPending = '' then
    Exit;
  if Assigned(FActivePanel) and FActivePanel.IsOffline then
    Exit;
  Other := OtherPanel(FActivePanel);
  if (Other <> nil) and Other.IsPreviewActive then
    Other.PreviewFile(FPreviewPending);
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
      procedure
      begin
        { Без ApplyThemeToAll — полная перерисовка темы на каждый чекбокс вешала UI. }
        SetFileOpMode(FSettings.FileOpMode);
        ApplyDriveOptions;
      end;
    Frm.ApplyTheme(FColors);
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

procedure TMainForm.CmdLineSubmit(Sender: TObject);
var
  Cmd: string;
begin
  if not Assigned(FCmdEdit) then
    Exit;
  Cmd := Trim(FCmdEdit.Text);
  if Cmd = '' then
    Exit;
  OpenFileWithDefaultApp(Cmd);
end;

procedure TMainForm.ApplyDriveOptions;
var
  I: Integer;
  FnH: Single;
begin
  SetFileOpMode(FSettings.FileOpMode);
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

  if Assigned(FCmdLine) then
    FCmdLine.Visible := FSettings.ShowCommandLine;
  FnH := 0;
  if FSettings.ShowFnBar then
    FnH := FnH + FNBAR_HEIGHT;
  if FSettings.ShowCommandLine then
    FnH := FnH + 30;
  if Assigned(FFnBar) then
  begin
    FFnBar.Visible := FSettings.ShowFnBar or FSettings.ShowCommandLine;
    FFnBar.Height := FnH;
  end;
  for I := 0 to 6 do
    if Assigned(FFnCells[I]) then
      FFnCells[I].Visible := FSettings.ShowFnBar;

  if Assigned(FLeftPanel) then
    FLeftPanel.ApplyUiSettings(FSettings);
  if Assigned(FRightPanel) then
    FRightPanel.ApplyUiSettings(FSettings);
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.Configure(FSettings.ThumbCacheEnabled, FSettings.ThumbCacheMaxItems);
  LayoutWorkArea;
  LayoutFunctionBar;
end;

procedure TMainForm.OnThemeChangedFromSettings(NewTheme: TAppTheme);
begin
  FSettings.Theme := NewTheme;
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

procedure TMainForm.ApplyThemeToAll(const AColors: TThemeColors);
var
  I: Integer;
  Chrome: TThemeColors;
begin
  FColors := AColors;
  SetActiveAppTheme(FSettings.Theme);
  Chrome := AColors;
  TintChromeForMaterial(Chrome, FSettings.WindowMaterial);
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

  if Assigned(FMidGroup) then
    for I := 0 to FMidGroup.ControlsCount - 1 do
      if (FMidGroup.Controls[I] is TRectangle) and
         (TRectangle(FMidGroup.Controls[I]).Tag = 2) then
        TRectangle(FMidGroup.Controls[I]).Fill.Color := AColors.DividerColor;

  FFnBar.Fill.Color := Chrome.FooterBackground;
  if Assigned(FCmdEdit) then
    FCmdEdit.ApplyTheme(AColors);
  for I := 0 to 6 do
    if Assigned(FFnButtons[I]) then
      FFnButtons[I].ApplyTheme(AColors);

  FLeftPanel.ApplyTheme(AColors);
  FRightPanel.ApplyTheme(AColors);
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
  Btn: TFluentButton;
  N, I: Integer;
  FolderRoots: TArray<string>;
  FocusPath: string;
  Src, Dest: TFilePanel;
begin
  if Length(ASources) = 0 then
    Exit;
  if AMove then
    Btn := FCmdMove
  else
    Btn := FCmdCopy;
  if Assigned(Btn) and Btn.Busy then
    Exit;
  if ListFileOpBusy then
    Exit;

  Src := ASrcPanel;
  Dest := ADestPanel;
  if Assigned(Src) and Src.IsOffline then
  begin
    Src.ShowNotice('Нет связи');
    Exit;
  end;
  if Assigned(Dest) and Dest.IsOffline then
  begin
    Dest.ShowNotice('Нет связи');
    Exit;
  end;
  SetLength(FolderRoots, 0);
  for I := 0 to High(ASources) do
    if (not IsRemotePath(ASources[I])) and TDirectory.Exists(ASources[I]) then
    begin
      SetLength(FolderRoots, Length(FolderRoots) + 1);
      FolderRoots[High(FolderRoots)] := ASources[I];
    end;

  N := 0;
  for I := 0 to High(ASources) do
    if IsRemotePath(ASources[I]) then
    begin
      N := 1;
      Break;
    end;
  if (N = 0) and IsRemotePath(ADestDir) then
    N := 1;
  if N = 0 then
    N := CountOpLeaves(ASources)
  else
    N := Max(Length(ASources), 1);
  if Assigned(Btn) then
    Btn.StartBusy(Max(N, 1));

  FocusPath := '';
  if AMove and Assigned(Src) then
    FocusPath := Src.FocusPathAfterRemove(ASources);

  if AMove then
    MovePathsAsync(ASources, ADestDir,
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if Assigned(Btn) then
          while Btn.Busy do
            Btn.EndBusy;
        if Assigned(Dest) then
          Dest.Refresh;
        if Assigned(Src) then
          Src.Refresh(FocusPath);
        if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') then
        begin
          if Assigned(Src) then
            Src.ShowNotice(ErrorMsg)
          else if Assigned(Dest) then
            Dest.ShowNotice(ErrorMsg);
        end;
      end,
      procedure(const APath: string; AStatus: TOpItemStatus)
      var
        J: Integer;
        IsFolder: Boolean;
      begin
        { Снять выделение после копирования / после ответа в окне конфликта. }
        if (AStatus in [oisOk, oisSkipped]) and Assigned(Src) then
          Src.DeselectByPath(APath);
        if AStatus = oisConflictPending then
          Exit;
        IsFolder := False;
        for J := 0 to High(FolderRoots) do
          if SameText(FolderRoots[J], APath) then
          begin
            IsFolder := True;
            Break;
          end;
        if (not IsFolder) and Assigned(Btn) then
          Btn.EndBusy;
      end)
  else
    CopyPathsAsync(ASources, ADestDir,
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if Assigned(Btn) then
          while Btn.Busy do
            Btn.EndBusy;
        if Assigned(Dest) then
          Dest.Refresh;
        if Assigned(Src) then
          Src.InvalidateView;
        if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') then
        begin
          if Assigned(Src) then
            Src.ShowNotice(ErrorMsg)
          else if Assigned(Dest) then
            Dest.ShowNotice(ErrorMsg);
        end;
      end,
      procedure(const APath: string; AStatus: TOpItemStatus)
      var
        J: Integer;
        IsFolder: Boolean;
      begin
        { Снять выделение после копирования / после ответа в окне конфликта. }
        if (AStatus in [oisOk, oisSkipped]) and Assigned(Src) then
          Src.DeselectByPath(APath);
        if AStatus = oisConflictPending then
          Exit;
        IsFolder := False;
        for J := 0 to High(FolderRoots) do
          if SameText(FolderRoots[J], APath) then
          begin
            IsFolder := True;
            Break;
          end;
        if (not IsFolder) and Assigned(Btn) then
          Btn.EndBusy;
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
  if (GetFileOpMode = fomVibe) and RestoreVibeCopyFromBackground then
    Exit;
  if not Assigned(FActivePanel) or not FActivePanel.HasSelection then
    Exit;
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
    Exit;
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
  if (GetFileOpMode = fomVibe) and RestoreVibeDeleteFromBackground then
    Exit;
  if not FActivePanel.HasSelection then Exit;
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

  FCmdDelete.StartBusy(1);
  DeletePathsAsync(Paths,
    procedure(Success: Boolean; const ErrorMsg: string)
    begin
      Panel.Refresh(FocusPath);
      if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') then
        Panel.ShowNotice(ErrorMsg);
      FCmdDelete.EndBusy;
    end, Permanent);
end;

procedure TMainForm.OnBtnNewFolderClick(Sender: TObject);
begin
  if Assigned(FActivePanel) then
    FActivePanel.CreateNewFolderInPlace;
end;

procedure TMainForm.OnBtnRefreshClick(Sender: TObject);
begin
  FLeftPanel.Refresh;
  FRightPanel.Refresh;
end;

procedure TMainForm.OnBtnViewDetailsClick(Sender: TObject);
begin
  FActivePanel.SetViewMode(vmDetails);
  UpdateViewButtons;
end;

procedure TMainForm.OnBtnViewTilesClick(Sender: TObject);
begin
  FActivePanel.SetViewMode(vmTiles);
  UpdateViewButtons;
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
  if not Assigned(FActivePanel) or not FActivePanel.HasSelection then Exit;
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

  FCmdArchive.StartBusy(1);
  ArchivePathsAsync(Paths, ZipPath,
    procedure(Success: Boolean; const ErrorMsg: string)
    begin
      if Success then
      begin
        Panel.ClearSelection;
        OtherPanel(Panel).Refresh;
      end;
      FCmdArchive.EndBusy;
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
    Title := 'Выделить по маске'
  else
    Title := 'Снять по маске';
  if not FluentInputQuery(Title, 'Маска файлов (* ? ;):', Mask, FColors, Self) then
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
  else if Key = vkF6 then
  begin
    OnBtnMoveClick(nil);
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

procedure TMainForm.PanelActivate(Sender: TObject);
begin
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

