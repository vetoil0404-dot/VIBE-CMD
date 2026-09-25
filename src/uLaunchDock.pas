unit uLaunchDock;

{
  Горизонтальный launch-док сразу под title bar:
  закреплённые папки / файлы / приложения, как мини-панель задач.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math ,
  System.Generics.Collections, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.Effects,
  FMX.StdCtrls, FMX.Platform, FMX.Dialogs, FMX.Forms,
  uAppSettings, uThemeManager, uFluentChrome, uFilePanel, uFileOps, UCoreEngine;

const
  DOCK_HEIGHT = 64;
  DOCK_ICON = 54;
  DOCK_GAP = 9;
  DOCK_PAD_X = 6;
  DOCK_SIDE_MARGIN = 10;

type
  TDockKind = (dkFile, dkFolder, dkApp, dkSeparator);

const
  DOCK_SEP_TOKEN = '*SEP*';

type
  TDockOpenFolderEvent = procedure(Sender: TObject; const APath: string) of object;
  TDockGoToEvent = procedure(Sender: TObject; const APath: string) of object;
  TDockStatusEvent = procedure(Sender: TObject; const AText: string) of object;
  TDockCopyFilesEvent = procedure(Sender: TObject; const ADest: string;
    const AFiles: TArray<string>) of object;

  TLaunchDock = class(TLayout)
  private
    FIsland: TRectangle;
    FScroll: THorzScrollBox;
    FStrip: TLayout;
    FEmptyHint: TText;
    FToast: TText;
    FToastTimer: TTimer;
    FTick: TTimer;
    FTipTimer: TTimer;
    FTip: TPopup;
    FTipBox: TRectangle;
    FTipText: TText;
    FTipShadow: TShadowEffect;
    FColors: TThemeColors;
    FTiles: TObjectList<TFmxObject>;
    FAlignMode: TDockAlign;
    FShowSeps: Boolean;
    FUpdating: Boolean;
    FScrollTarget: Single;
    FWheelVel: Single;
    FDropHot: Boolean;
    FDropHotTile: TFmxObject;
    FReorderTile: TFmxObject;
    FReorderStart: TPointF;
    FReorderArmed: Boolean;
    FReorderActive: Boolean;
    FHoverTile: TFmxObject;
    FTipTile: TFmxObject;
    FMenuTile: TFmxObject;
    FOnOpenFolder: TDockOpenFolderEvent;
    FOnGoToObject: TDockGoToEvent;
    FOnStatus: TDockStatusEvent;
    FOnChanged: TNotifyEvent;
    FOnCopyToFolder: TDockCopyFilesEvent;
    FIconQueue: TList<Integer>;
    FIconLock: TObject;
    FLocalBusy: Integer;
    FRemoteBusy: Integer;
    FIdleIcons: Boolean;
    FIdleTimer: TTimer;
    FPulseTimer: TTimer;
    FSaveTimer: TTimer;
    FClickArmed: Boolean;
    FClickTile: TFmxObject;
    FClickDragged: Boolean;
    FOpenGuardPath: string;
    FOpenGuardTick: Cardinal;
    procedure BuildChrome;
    procedure ApplyIslandChrome;
    procedure RelayoutTargets;
    procedure Tick(Sender: TObject);
    procedure TipTick(Sender: TObject);
    procedure ToastTick(Sender: TObject);
    procedure HandleWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean);
    procedure IslandDragOver(Sender: TObject; const Data: TDragObject;
      const Point: TPointF; var Operation: TDragOperation);
    procedure IslandDragDrop(Sender: TObject; const Data: TDragObject; const Point: TPointF);
    procedure IslandDragLeave(Sender: TObject);
    function TryAcceptExternalDrop(const AScreen: TPointF; const APaths: TArray<string>): Boolean;
    procedure TileMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure TileMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure TileMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure TileMouseEnter(Sender: TObject);
    procedure TileMouseLeave(Sender: TObject);
    procedure MenuChangeClick(Sender: TObject);
    procedure MenuChangePictureClick(Sender: TObject);
    procedure MenuResetPictureClick(Sender: TObject);
    procedure MenuGoToClick(Sender: TObject);
    procedure MenuRemoveClick(Sender: TObject);
    procedure MenuAddSepClick(Sender: TObject);
    procedure MenuAlignLeftClick(Sender: TObject);
    procedure MenuAlignCenterClick(Sender: TObject);
    procedure MenuAlignFreeClick(Sender: TObject);
    procedure IslandMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ShowTileMenu(ATile: TFmxObject);
    procedure ShowBackgroundMenu;
    function OwnerHwnd: NativeUInt;
    function PointInIsland(const AScreen: TPointF): Boolean;
    function PointToStripX(Sender: TObject; const ALocal: TPointF): Single;
    function TileAtStripX(AX: Single): TFmxObject;
    procedure DropOnTile(ATile: TFmxObject; const AFiles: TArray<string>);
    procedure SetAlignMode(AValue: TDockAlign);
    procedure AddSeparatorAt(AIndex: Integer);
    procedure SetDropHot(AHot: Boolean);
    procedure SetDropHotTile(ATile: TFmxObject);
    procedure ShowTipFor(ATile: TFmxObject);
    procedure HideTip;
    procedure ShowToast(const AText: string);
    procedure ScheduleNotifyChanged;
    procedure NotifyChanged;
    procedure SaveTimerTick(Sender: TObject);
    procedure OpenItem(ATile: TFmxObject);
    procedure GoToItem(ATile: TFmxObject);
    procedure RemoveTile(ATile: TFmxObject; AAnimate: Boolean);
    function AddOne(const APath: string; AInsertAt: Integer; AAnimate: Boolean;
      AFreeX: Single = -1; ADeferIcon: Boolean = False): Boolean;
    procedure EnqueueIcon(ATile: TFmxObject; AForce: Boolean = False);
    procedure PumpIconQueue;
    procedure IdleIconsTick(Sender: TObject);
    procedure PulseTick(Sender: TObject);
    function TileByToken(AToken: Integer): TFmxObject;
    procedure ApplyGlyph(ATile: TFmxObject);
    function TryLoadCachedIcon(ATile: TFmxObject): Boolean;
    procedure SetCustomPicture(ATile: TFmxObject; const AFile: string);
    procedure ApplyIconResult(AToken: Integer; const ACache: string; ABroken: Boolean;
      const APixels: TBytes; AW, AH: Integer; ARemote: Boolean);
    function IsPicturePath(const APath: string): Boolean;
    procedure ForgetIconFile(const AName: string);
    function IndexOfPath(const APath: string): Integer;
    function IndexFromStripX(AX: Single): Integer;
    function CollectDataFiles(const Data: TDragObject): TArray<string>;
    procedure FinishReorder;
    procedure UpdateEmptyHint;
    procedure BindTileEvents(ATile: TControl);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ApplyDockOptions(AAlign: TDockAlign; AShowSeps: Boolean);
    procedure LoadItems(const APaths: TArray<string>; const AXs: TArray<Single>;
      const AKinds: TArray<Integer>; const ACaptions, AIcons: TArray<string>;
      const ALocked: TArray<Boolean>); overload;
    procedure LoadItems(const APaths: TArray<string>; const AXs: TArray<Single>); overload;
    procedure CollectState(out APaths: TArray<string>; out AXs: TArray<Single>;
      out AKinds: TArray<Integer>; out ACaptions, AIcons: TArray<string>;
      out ALocked: TArray<Boolean>); overload;
    procedure CollectState(out APaths: TArray<string>; out AXs: TArray<Single>); overload;
    procedure NotifyDevicesChanged;
    function CollectPaths: TArray<string>;
    property AlignMode: TDockAlign read FAlignMode write SetAlignMode;
    property ShowSeparators: Boolean read FShowSeps;
    property OnOpenFolder: TDockOpenFolderEvent read FOnOpenFolder write FOnOpenFolder;
    property OnGoToObject: TDockGoToEvent read FOnGoToObject write FOnGoToObject;
    property OnStatus: TDockStatusEvent read FOnStatus write FOnStatus;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnCopyToFolder: TDockCopyFilesEvent read FOnCopyToFolder write FOnCopyToFolder;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows, Winapi.ShellAPI, Winapi.ShlObj, Winapi.ActiveX,
  FMX.Platform.Win, System.SyncObjs, System.Hash, uFileModel, uThumbCache;
{$ELSE}
uses
  System.SyncObjs, System.Hash, uFileModel, uThumbCache;
{$ENDIF}

{$IFDEF MSWINDOWS}
function PickDockFolder(const ATitle, ACurrent: string): string;
var
  Dlg: IFileOpenDialog;
  Item: IShellItem;
  Path: PWideChar;
  Opts: DWORD;
begin
  Result := '';
  if Failed(CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER,
      IFileOpenDialog, Dlg)) then
    Exit;
  Dlg.SetTitle(PWideChar(ATitle));
  Dlg.GetOptions(Opts);
  Dlg.SetOptions(Opts or FOS_PICKFOLDERS or FOS_FORCEFILESYSTEM);
  if (ACurrent <> '') and Succeeded(SHCreateItemFromParsingName(PWideChar(ACurrent),
      nil, IID_IShellItem, Item)) then
    Dlg.SetFolder(Item);
  if Failed(Dlg.Show(0)) then
    Exit;
  if Failed(Dlg.GetResult(Item)) then
    Exit;
  if Succeeded(Item.GetDisplayName(SIGDN_FILESYSPATH, Path)) then
  try
    Result := Path;
  finally
    CoTaskMemFree(Path);
  end;
end;
{$ENDIF}

const
  SCALE_IDLE = 1.0;
  SCALE_HOVER = 1.08;
  SCALE_PRESS = 0.92;
  APPROACH = 0.28;
  SCROLL_APPROACH = 0.075;
  WHEEL_SCALE = 0.30;
  WHEEL_FRICTION = 0.82;
  CELL_W = DOCK_ICON + DOCK_GAP;
  ICON_PAD = 8;
  SEP_CELL = 32;
  SEP_LINE_W = 2;

type
  TDockTile = class(TLayout)
  public
    ItemPath: string;
    Caption: string;
    Kind: TDockKind;
    IsBroken: Boolean;
    IsSep: Boolean;
    SepLine: TRectangle;
    Bg: TRectangle;
    IconHost: TLayout;
    Icon: TImage;
    Fallback: TText;
    ScaleValue: Single;
    TargetScale: Single;
    PosX: Single;
    TargetX: Single;
    OpValue: Single;
    TargetOp: Single;
    CellW: Single;
    TargetCellW: Single;
    Removing: Boolean;
    IconPending: Boolean;
    Token: Integer;
    IconFile: string;
    IconLocked: Boolean;
    FailCount: Integer;
    LastFailTick: Cardinal;
    constructor CreateTile(AOwner: TComponent);
    destructor Destroy; override;
    procedure ApplyVisual(const AColors: TThemeColors; AHovered: Boolean);
    procedure LoadIcon;
    procedure SetupSeparator;
  end;

  TDockIconDone = class
    Dock: TLaunchDock;
    Token: Integer;
    Path: string;
    Kind: TDockKind;
    CacheName: string;
    Broken: Boolean;
    Pixels: TBytes;
    W, H: Integer;
    Remote: Boolean;
    procedure Apply;
  end;

var
  GDockToken: Integer = 1;

function KindFromName(const APath: string): TDockKind;
var
  Ext: string;
begin
  if SameText(APath, DOCK_SEP_TOKEN) then
    Exit(dkSeparator);
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext = '') or APath.EndsWith('\') or APath.EndsWith('/') then
    Exit(dkFolder);
  if (Ext = '.exe') or (Ext = '.lnk') or (Ext = '.msc') or (Ext = '.bat') or
     (Ext = '.cmd') or (Ext = '.com') or (Ext = '.msi') or (Ext = '.ps1') then
    Exit(dkApp);
  Result := dkFile;
end;

function DetectDockKind(const APath: string): TDockKind;
begin
  Result := KindFromName(APath);
end;

function DockIconsDir: string;
begin
  Result := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetHomePath, 'VibeCmd');
  Result := System.IOUtils.TPath.Combine(Result, 'DockIcons');
end;

function DockCacheName(const APath: string): string;
begin
  Result := LowerCase(THashMD5.GetHashString(AnsiLowerCase(
    ExcludeTrailingPathDelimiter(APath)))) + '.png';
end;

function DockCachePath(const AName: string): string;
begin
  Result := System.IOUtils.TPath.Combine(DockIconsDir, AName);
end;

function IsDockRemotePath(const APath: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Root: string;
  DT: Cardinal;
{$ENDIF}
begin
  Result := IsUncPath(APath);
{$IFDEF MSWINDOWS}
  if Result then
    Exit;
  Root := ExtractFileDrive(APath);
  if Root = '' then
    Exit(False);
  if Root[Length(Root)] <> '\' then
    Root := Root + '\';
  DT := GetDriveType(PChar(Root));
  { Только сетевые диски — removable/CD не считаем remote (иначе лишние задержки). }
  Result := DT = DRIVE_REMOTE;
{$ENDIF}
end;

function ProbePathExists(const APath: string; ATimeoutMs: Integer): Boolean;
var
  Gate: TEvent;
  Ok: Boolean;
begin
  Result := False;
  if APath = '' then
    Exit;
  Gate := TEvent.Create(nil, True, False, '');
  Ok := False;
  TThread.CreateAnonymousThread(
    procedure
    var
      SR: TSearchRec;
      RC: Integer;
    begin
      RC := System.SysUtils.FindFirst(APath, faAnyFile, SR);
      Ok := RC = 0;
      if RC = 0 then
        System.SysUtils.FindClose(SR);
      if not Ok then
      begin
        RC := System.SysUtils.FindFirst(System.IOUtils.TPath.Combine(APath, '*.*'), faAnyFile, SR);
        Ok := RC = 0;
        if RC = 0 then
          System.SysUtils.FindClose(SR);
      end;
      Gate.SetEvent;
    end).Start;
  if Gate.WaitFor(ATimeoutMs) = wrSignaled then
    Result := Ok;
  Gate.SetEvent;
end;


{ Letterbox: сохранить пропорции, прозрачные поля по краям. }
procedure FitIconIntoSquare(Src: FMX.Graphics.TBitmap; out Fit: FMX.Graphics.TBitmap;
  ASize: Integer = 128);
var
  Scale, Dw, Dh: Single;
  R: TRectF;
begin
  Fit := FMX.Graphics.TBitmap.Create(ASize, ASize);
  Fit.Clear(0);
  if (Src = nil) or (Src.Width < 1) or (Src.Height < 1) then
    Exit;
  Scale := Min(ASize / Src.Width, ASize / Src.Height);
  Dw := Src.Width * Scale;
  Dh := Src.Height * Scale;
  R := TRectF.Create((ASize - Dw) * 0.5, (ASize - Dh) * 0.5,
    (ASize - Dw) * 0.5 + Dw, (ASize - Dh) * 0.5 + Dh);
  if Fit.Canvas.BeginScene then
  try
    Fit.Canvas.DrawBitmap(Src, Src.Bounds, R, 1, True);
  finally
    Fit.Canvas.EndScene;
  end;
end;

function MakeDockCaption(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if Result = '' then
    Result := APath;
end;

function PathBroken(const APath: string): Boolean;
begin
  Result := not TFile.Exists(APath) and not TDirectory.Exists(APath);
end;

function SameItemPath(const A, B: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(A), ExcludeTrailingPathDelimiter(B));
end;

procedure GrayscaleBitmap(Bmp: FMX.Graphics.TBitmap);
var
  Data: TBitmapData;
  X, Y: Integer;
  C: TAlphaColorRec;
  G: Integer;
begin
  if (Bmp = nil) or Bmp.IsEmpty then
    Exit;
  if not Bmp.Map(TMapAccess.ReadWrite, Data) then
    Exit;
  try
    for Y := 0 to Bmp.Height - 1 do
      for X := 0 to Bmp.Width - 1 do
      begin
        C.Color := Data.GetPixel(X, Y);
        G := Round(0.299 * C.R + 0.587 * C.G + 0.114 * C.B);
        C.R := G;
        C.G := G;
        C.B := G;
        Data.SetPixel(X, Y, C.Color);
      end;
  finally
    Bmp.Unmap(Data);
  end;
end;

function DockApproach(var AValue: Single; ATarget, ASpeed: Single): Boolean;
begin
  AValue := AValue + (ATarget - AValue) * ASpeed;
  if Abs(ATarget - AValue) < 0.004 then
  begin
    AValue := ATarget;
    Result := True;
  end
  else
    Result := False;
end;

function TileOf(AObj: TFmxObject): TDockTile;
begin
  if AObj is TDockTile then
    Result := TDockTile(AObj)
  else
    Result := nil;
end;

{ TDockTile }

constructor TDockTile.CreateTile(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := True;
  Cursor := crHandPoint;
  CanFocus := False;
  Width := DOCK_ICON;
  Height := DOCK_ICON;
  ScaleValue := 0.8;
  TargetScale := SCALE_IDLE;
  OpValue := 0;
  TargetOp := 1;
  CellW := CELL_W;
  TargetCellW := CELL_W;
  IsSep := False;
  IconPending := False;
  IconLocked := False;
  IconFile := '';
  FailCount := 0;
  LastFailTick := 0;
  Token := AtomicIncrement(GDockToken);
  Opacity := 0;

  Bg := TRectangle.Create(Self);
  Bg.Parent := Self;
  Bg.Align := TAlignLayout.Client;
  Bg.HitTest := False;
  Bg.XRadius := 10;
  Bg.YRadius := 10;
  Bg.Stroke.Kind := TBrushKind.None;
  Bg.Fill.Kind := TBrushKind.Solid;
  Bg.Fill.Color := TAlphaColors.Null;

  IconHost := TLayout.Create(Self);
  IconHost.Parent := Self;
  IconHost.Align := TAlignLayout.Center;
  IconHost.HitTest := False;
  IconHost.Width := DOCK_ICON * ScaleValue;
  IconHost.Height := DOCK_ICON * ScaleValue;
  IconHost.Scale.X := 1;
  IconHost.Scale.Y := 1;

  Icon := TImage.Create(Self);
  Icon.Parent := IconHost;
  Icon.Align := TAlignLayout.Client;
  Icon.HitTest := False;
  Icon.WrapMode := TImageWrapMode.Fit;
  Icon.Margins.Rect := TRectF.Create(ICON_PAD, ICON_PAD, ICON_PAD, ICON_PAD);

  Fallback := TText.Create(Self);
  Fallback.Parent := IconHost;
  Fallback.Align := TAlignLayout.Client;
  Fallback.HitTest := False;
  Fallback.Visible := False;
  Fallback.TextSettings.Font.Family := FluentIconFamily;
  Fallback.TextSettings.Font.Size := 20;
  Fallback.TextSettings.HorzAlign := TTextAlign.Center;
  Fallback.TextSettings.VertAlign := TTextAlign.Center;

  SepLine := TRectangle.Create(Self);
  SepLine.Parent := Self;
  SepLine.Align := TAlignLayout.Center;
  SepLine.Width := SEP_LINE_W;
  SepLine.Height := 28;
  SepLine.XRadius := 1;
  SepLine.YRadius := 1;
  SepLine.Stroke.Kind := TBrushKind.None;
  SepLine.Fill.Kind := TBrushKind.Solid;
  SepLine.HitTest := False;
  SepLine.Visible := False;
end;

procedure TDockTile.SetupSeparator;
begin
  IsSep := True;
  Kind := dkSeparator;
  ItemPath := DOCK_SEP_TOKEN;
  Caption := 'Разделитель';
  IsBroken := False;
  Width := SEP_CELL;
  IconHost.Visible := False;
  Icon.Visible := False;
  Fallback.Visible := False;
  SepLine.Visible := True;
  Cursor := crDefault;
  TargetCellW := SEP_CELL;
  CellW := SEP_CELL;
end;

destructor TDockTile.Destroy;
begin
  inherited;
end;

procedure TDockTile.ApplyVisual(const AColors: TThemeColors; AHovered: Boolean);
begin
  if IsSep then
  begin
    Bg.Fill.Color := TAlphaColors.Null;
    SepLine.Fill.Color := AColors.DividerColor;
    if SepLine.Fill.Color = 0 then
      SepLine.Fill.Color := AColors.SubTextColor;
    Exit;
  end;
  if AHovered and not Removing then
    Bg.Fill.Color := AColors.ItemHover
  else
    Bg.Fill.Color := TAlphaColors.Null;
  if IsBroken then
    Icon.Opacity := 0.45
  else
    Icon.Opacity := 1;
  Fallback.TextSettings.FontColor := AColors.SubTextColor;
  Fallback.Opacity := Icon.Opacity;
end;

procedure TDockTile.LoadIcon;
begin
  if IsSep then
    Exit;
  if (Icon.Bitmap <> nil) and (Icon.Bitmap.Width > 0) then
  begin
    Fallback.Visible := False;
    Exit;
  end;
  case Kind of
    dkFolder: Fallback.Text := '';
    dkApp:    Fallback.Text := '';
  else
    Fallback.Text := '';
  end;
  Fallback.Visible := True;
end;

{ TLaunchDock }

constructor TLaunchDock.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  Height := DOCK_HEIGHT;
  FColors := GetThemeColors(atSystem);
  FAlignMode := daLeft;
  FShowSeps := True;
  FUpdating := False;
  FScrollTarget := 0;
  FWheelVel := 0;
  FTiles := TObjectList<TFmxObject>.Create(True);
  FIconQueue := TList<Integer>.Create;
  FIconLock := TCriticalSection.Create;
  FLocalBusy := 0;
  FRemoteBusy := 0;
  FIdleIcons := False;
  BuildChrome;
  RegisterFileDragDropHook(TryAcceptExternalDrop);

  FIdleTimer := TTimer.Create(Self);
  FIdleTimer.Interval := 3000;
  FIdleTimer.Enabled := False;
  FIdleTimer.OnTimer := IdleIconsTick;
  FPulseTimer := TTimer.Create(Self);
  FPulseTimer.Interval := 12000;
  FPulseTimer.Enabled := True;
  FPulseTimer.OnTimer := PulseTick;

  FSaveTimer := TTimer.Create(Self);
  FSaveTimer.Interval := 450;
  FSaveTimer.Enabled := False;
  FSaveTimer.OnTimer := SaveTimerTick;

  FTick := TTimer.Create(Self);
  FTick.Interval := 16;
  FTick.OnTimer := Tick;
  FTick.Enabled := True;

  FTipTimer := TTimer.Create(Self);
  FTipTimer.Interval := 400;
  FTipTimer.Enabled := False;
  FTipTimer.OnTimer := TipTick;

  FToastTimer := TTimer.Create(Self);
  FToastTimer.Interval := 1600;
  FToastTimer.Enabled := False;
  FToastTimer.OnTimer := ToastTick;
end;

destructor TLaunchDock.Destroy;
begin
  RegisterFileDragDropHook(nil);
  HideTip;
  if Assigned(FIdleTimer) then
    FIdleTimer.Enabled := False;
  if Assigned(FPulseTimer) then
    FPulseTimer.Enabled := False;
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;
  FreeAndNil(FTiles);
  FreeAndNil(FIconQueue);
  FreeAndNil(FIconLock);
  inherited;
end;

procedure TLaunchDock.BuildChrome;
begin
  FIsland := TRectangle.Create(Self);
  FIsland.Parent := Self;
  FIsland.Align := TAlignLayout.Client;
  FIsland.Margins.Rect := TRectF.Create(DOCK_SIDE_MARGIN, 0, DOCK_SIDE_MARGIN, 0);
  FIsland.XRadius := 16;
  FIsland.YRadius := 16;
  FIsland.Stroke.Kind := TBrushKind.Solid;
  FIsland.Stroke.Thickness := 1;
  FIsland.Fill.Kind := TBrushKind.Solid;
  FIsland.HitTest := True;
  FIsland.OnMouseWheel := HandleWheel;
  FIsland.OnMouseDown := IslandMouseDown;
  FIsland.OnDragOver := IslandDragOver;
  FIsland.OnDragDrop := IslandDragDrop;
  FIsland.OnDragLeave := IslandDragLeave;

  FScroll := THorzScrollBox.Create(Self);
  FScroll.Parent := FIsland;
  FScroll.Align := TAlignLayout.Client;
  FScroll.Margins.Rect := TRectF.Create(DOCK_PAD_X, 5, DOCK_PAD_X, 5);
  FScroll.ShowScrollBars := False;
  FScroll.HitTest := True;
  FScroll.OnMouseWheel := HandleWheel;
  FScroll.OnMouseDown := IslandMouseDown;
  FScroll.OnDragOver := IslandDragOver;
  FScroll.OnDragDrop := IslandDragDrop;
  FScroll.OnDragLeave := IslandDragLeave;
  FScroll.AniCalculations.Animation := False;
  FScroll.AniCalculations.BoundsAnimation := False;
  FScroll.AniCalculations.AutoShowing := False;
  FScroll.AniCalculations.TouchTracking := [];

  FStrip := TLayout.Create(Self);
  FStrip.Parent := FScroll;
  FStrip.Align := TAlignLayout.None;
  FStrip.Position.Point := TPointF.Zero;
  FStrip.Height := DOCK_ICON;
  FStrip.Width := DOCK_ICON;
  FStrip.HitTest := True;
  FStrip.OnMouseWheel := HandleWheel;
  FStrip.OnMouseDown := IslandMouseDown;
  FStrip.OnDragOver := IslandDragOver;
  FStrip.OnDragDrop := IslandDragDrop;
  FStrip.OnDragLeave := IslandDragLeave;

  FEmptyHint := TText.Create(Self);
  FEmptyHint.Parent := FIsland;
  FEmptyHint.Align := TAlignLayout.Client;
  FEmptyHint.HitTest := False;
  FEmptyHint.Text := 'Перетащите сюда файлы, папки или приложения';
  FEmptyHint.TextSettings.Font.Family := FluentFontFamily;
  FEmptyHint.TextSettings.Font.Size := 12;
  FEmptyHint.TextSettings.HorzAlign := TTextAlign.Center;
  FEmptyHint.TextSettings.VertAlign := TTextAlign.Center;

  FToast := TText.Create(Self);
  FToast.Parent := FIsland;
  FToast.Align := TAlignLayout.None;
  FToast.HitTest := False;
  FToast.Visible := False;
  FToast.TextSettings.Font.Family := FluentFontFamily;
  FToast.TextSettings.Font.Size := 11;
  FToast.TextSettings.HorzAlign := TTextAlign.Trailing;
  FToast.TextSettings.VertAlign := TTextAlign.Center;

  FTip := TPopup.Create(Self);
  FTip.Parent := Self;
  FTip.ClipChildren := False;
  FTip.BorderWidth := 0;
  FTip.Width := 220 + 36;
  FTip.Height := 28 + 36;
  FTip.Placement := TPlacement.BottomCenter;
  FTip.VerticalOffset := -14;

  FTipBox := TRectangle.Create(FTip);
  FTipBox.Parent := FTip;
  FTipBox.Align := TAlignLayout.Client;
  FTipBox.Margins.Rect := TRectF.Create(18, 14, 18, 22);
  FTipBox.XRadius := 6;
  FTipBox.YRadius := 6;
  FTipBox.Stroke.Kind := TBrushKind.Solid;
  FTipBox.Stroke.Thickness := 1;
  FTipBox.ClipChildren := False;

  FTipShadow := TShadowEffect.Create(FTipBox);
  FTipShadow.Parent := FTipBox;
  ApplyFluentShadow(FTipShadow, FColors.IsDark);

  FTipText := TText.Create(FTip);
  FTipText.Parent := FTipBox;
  FTipText.Align := TAlignLayout.Client;
  FTipText.Margins.Rect := TRectF.Create(10, 0, 10, 0);
  FTipText.TextSettings.Font.Family := FluentFontFamily;
  FTipText.TextSettings.Font.Size := 11;
  FTipText.TextSettings.HorzAlign := TTextAlign.Center;
  FTipText.TextSettings.VertAlign := TTextAlign.Center;

  ApplyIslandChrome;
end;

function TLaunchDock.OwnerHwnd: NativeUInt;
begin
  Result := 0;
  {$IFDEF MSWINDOWS}
  if Root <> nil then
    Result := NativeUInt(FormToHWND(TCommonCustomForm(Root)));
  {$ENDIF}
end;

procedure TLaunchDock.ShowTileMenu(ATile: TFmxObject);
{$IFDEF MSWINDOWS}
var
  Tile: TDockTile;
  Pop: HMENU;
  Pt: TPoint;
  Cmd: UINT;
  Wnd: HWND;
  CanEdit: Boolean;
  Flags: UINT;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Tile := TileOf(ATile);
  if Tile = nil then
    Exit;
  HideTip;
  FMenuTile := Tile;
  CanEdit := (not Tile.IsSep) and (not Tile.IsBroken);
  Wnd := HWND(OwnerHwnd);
  if Wnd = 0 then
    Wnd := GetDesktopWindow;
  Pop := CreatePopupMenu;
  if Pop = 0 then
    Exit;
  Cmd := 0;
  try
    Flags := MF_STRING;
    if not CanEdit then
      Flags := Flags or MF_GRAYED;
    if not Tile.IsSep then
      AppendMenu(Pop, Flags, 1, 'Изменить объект…');
    if not Tile.IsSep then
      AppendMenu(Pop, MF_STRING, 2, 'Изменить картинку…');
    if (not Tile.IsSep) and ((Tile.IconFile <> '') or Tile.IconLocked) then
      AppendMenu(Pop, MF_STRING, 3, 'Сбросить картинку');
    AppendMenu(Pop, Flags, 4, 'Перейти к объекту');
    AppendMenu(Pop, MF_STRING, 5, 'Убрать с дока');
    GetCursorPos(Pt);
    Cmd := UINT(TrackPopupMenuEx(Pop,
      TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_LEFTALIGN or TPM_TOPALIGN,
      Pt.X, Pt.Y, Wnd, nil));
    ReleaseCapture;
  finally
    DestroyMenu(Pop);
  end;
  case Cmd of
    1: MenuChangeClick(nil);
    2: MenuChangePictureClick(nil);
    3: MenuResetPictureClick(nil);
    4: MenuGoToClick(nil);
    5: MenuRemoveClick(nil);
  end;
  {$ENDIF}
end;

procedure TLaunchDock.ShowBackgroundMenu;
{$IFDEF MSWINDOWS}
var
  Pop: HMENU;
  Pt: TPoint;
  Cmd: UINT;
  Wnd: HWND;
  FlLeft, FlCenter, FlFree: UINT;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  HideTip;
  Wnd := HWND(OwnerHwnd);
  if Wnd = 0 then
    Wnd := GetDesktopWindow;
  Pop := CreatePopupMenu;
  if Pop = 0 then
    Exit;
  Cmd := 0;
  FlLeft := MF_STRING;
  FlCenter := MF_STRING;
  FlFree := MF_STRING;
  if FAlignMode = daLeft then
    FlLeft := FlLeft or MF_CHECKED;
  if FAlignMode = daCenter then
    FlCenter := FlCenter or MF_CHECKED;
  if FAlignMode = daFree then
    FlFree := FlFree or MF_CHECKED;
  try
    AppendMenu(Pop, MF_STRING, 1, 'Добавить разделитель');
    AppendMenu(Pop, MF_SEPARATOR, 0, nil);
    AppendMenu(Pop, FlLeft, 2, 'Иконки слева');
    AppendMenu(Pop, FlCenter, 3, 'Иконки по центру');
    AppendMenu(Pop, FlFree, 4, 'Иконки произвольно');
    GetCursorPos(Pt);
    Cmd := UINT(TrackPopupMenuEx(Pop,
      TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_LEFTALIGN or TPM_TOPALIGN,
      Pt.X, Pt.Y, Wnd, nil));
    ReleaseCapture;
  finally
    DestroyMenu(Pop);
  end;
  case Cmd of
    1: MenuAddSepClick(nil);
    2: MenuAlignLeftClick(nil);
    3: MenuAlignCenterClick(nil);
    4: MenuAlignFreeClick(nil);
  end;
  {$ENDIF}
end;

procedure TLaunchDock.ApplyIslandChrome;
begin
  if FDropHot then
  begin
    FIsland.Fill.Color := ThemeAdjustAlpha(FColors.SelectionColor, $22);
    FIsland.Stroke.Color := ThemeAdjustAlpha(FColors.SelectionColor, $80);
  end
  else
  begin
    FIsland.Fill.Color := FColors.DockBackground;
    FIsland.Stroke.Color := FColors.CardStroke;
  end;
  FEmptyHint.TextSettings.FontColor := FColors.DisabledTextColor;
  FToast.TextSettings.FontColor := FColors.TextColor;
  FTipBox.Fill.Color := FColors.CardBackground;
  FTipBox.Stroke.Color := FColors.CardStroke;
  FTipText.TextSettings.FontColor := FColors.TextColor;
  ApplyFluentShadow(FTipShadow, FColors.IsDark);
end;

procedure TLaunchDock.ApplyTheme(const AColors: TThemeColors);
var
  I: Integer;
  Tile: TDockTile;
begin
  FColors := AColors;
  ApplyIslandChrome;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if Tile <> nil then
      Tile.ApplyVisual(FColors, FHoverTile = Tile);
  end;
end;

procedure TLaunchDock.BindTileEvents(ATile: TControl);
begin
  ATile.OnMouseDown := TileMouseDown;
  ATile.OnMouseMove := TileMouseMove;
  ATile.OnMouseUp := TileMouseUp;
  ATile.OnMouseEnter := TileMouseEnter;
  ATile.OnMouseLeave := TileMouseLeave;
  ATile.OnMouseWheel := HandleWheel;
  ATile.OnDragOver := IslandDragOver;
  ATile.OnDragDrop := IslandDragDrop;
  ATile.OnDragLeave := IslandDragLeave;
end;

procedure TLaunchDock.UpdateEmptyHint;
begin
  FEmptyHint.Visible := FTiles.Count = 0;
end;

procedure TLaunchDock.LoadItems(const APaths: TArray<string>; const AXs: TArray<Single>);
var
  EmptyI: TArray<Integer>;
  EmptyS: TArray<string>;
  EmptyB: TArray<Boolean>;
begin
  SetLength(EmptyI, 0);
  SetLength(EmptyS, 0);
  SetLength(EmptyB, 0);
  LoadItems(APaths, AXs, EmptyI, EmptyS, EmptyS, EmptyB);
end;

procedure TLaunchDock.LoadItems(const APaths: TArray<string>; const AXs: TArray<Single>;
  const AKinds: TArray<Integer>; const ACaptions, AIcons: TArray<string>;
  const ALocked: TArray<Boolean>);
var
  I: Integer;
  Tile: TDockTile;
begin
  FUpdating := True;
  FIdleIcons := False;
  try
    FTiles.Clear;
    for I := 0 to High(APaths) do
    begin
      if SameText(APaths[I], DOCK_SEP_TOKEN) then
        AddSeparatorAt(-1)
      else
        AddOne(APaths[I], -1, False, -1, True);
      if FTiles.Count = 0 then
        Continue;
      Tile := TileOf(FTiles[FTiles.Count - 1]);
      if Tile = nil then
        Continue;
      if (I <= High(AXs)) then
      begin
        Tile.PosX := AXs[I];
        Tile.TargetX := AXs[I];
        Tile.Position.X := AXs[I];
      end;
      if (I <= High(AKinds)) and (AKinds[I] >= Ord(dkFile)) and
         (AKinds[I] <= Ord(dkSeparator)) then
        Tile.Kind := TDockKind(AKinds[I]);
      if (I <= High(ACaptions)) and (ACaptions[I] <> '') then
        Tile.Caption := ACaptions[I];
      if (I <= High(AIcons)) then
        Tile.IconFile := AIcons[I];
      if (I <= High(ALocked)) then
        Tile.IconLocked := ALocked[I];
      Tile.IsBroken := False;
      if not TryLoadCachedIcon(Tile) then
      begin
        ApplyGlyph(Tile);
        if not Tile.IconLocked then
          EnqueueIcon(Tile, False);
      end;
    end;
    RelayoutTargets;
    if FAlignMode <> daFree then
      for I := 0 to FTiles.Count - 1 do
      begin
        Tile := TileOf(FTiles[I]);
        if Tile <> nil then
        begin
          Tile.PosX := Tile.TargetX;
          Tile.Position.X := Tile.PosX;
        end;
      end;
    UpdateEmptyHint;
    if Assigned(FIdleTimer) then
    begin
      FIdleTimer.Enabled := False;
      FIdleTimer.Enabled := True;
    end;
    PumpIconQueue;
  finally
    FUpdating := False;
  end;
end;

procedure TLaunchDock.CollectState(out APaths: TArray<string>; out AXs: TArray<Single>);
var
  K: TArray<Integer>;
  C, Ic: TArray<string>;
  L: TArray<Boolean>;
begin
  CollectState(APaths, AXs, K, C, Ic, L);
end;

procedure TLaunchDock.CollectState(out APaths: TArray<string>; out AXs: TArray<Single>;
  out AKinds: TArray<Integer>; out ACaptions, AIcons: TArray<string>;
  out ALocked: TArray<Boolean>);
var
  I, N: Integer;
  Tile: TDockTile;
begin
  SetLength(APaths, FTiles.Count);
  SetLength(AXs, FTiles.Count);
  SetLength(AKinds, FTiles.Count);
  SetLength(ACaptions, FTiles.Count);
  SetLength(AIcons, FTiles.Count);
  SetLength(ALocked, FTiles.Count);
  N := 0;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile <> nil) and not Tile.Removing then
    begin
      if Tile.IsSep then
        APaths[N] := DOCK_SEP_TOKEN
      else if Tile.ItemPath <> '' then
        APaths[N] := Tile.ItemPath
      else
        Continue;
      AXs[N] := Tile.PosX;
      AKinds[N] := Ord(Tile.Kind);
      ACaptions[N] := Tile.Caption;
      AIcons[N] := Tile.IconFile;
      ALocked[N] := Tile.IconLocked;
      Inc(N);
    end;
  end;
  SetLength(APaths, N);
  SetLength(AXs, N);
  SetLength(AKinds, N);
  SetLength(ACaptions, N);
  SetLength(AIcons, N);
  SetLength(ALocked, N);
end;

function TLaunchDock.CollectPaths: TArray<string>;
var
  Xs: TArray<Single>;
begin
  CollectState(Result, Xs);
end;

procedure TLaunchDock.ApplyDockOptions(AAlign: TDockAlign; AShowSeps: Boolean);
begin
  FShowSeps := AShowSeps;
  FAlignMode := AAlign;
  RelayoutTargets;
end;

procedure TLaunchDock.SetAlignMode(AValue: TDockAlign);
begin
  if FAlignMode = AValue then
    Exit;
  FAlignMode := AValue;
  RelayoutTargets;
  if not FUpdating then
    ScheduleNotifyChanged;
end;

function TLaunchDock.IndexOfPath(const APath: string): Integer;
var
  I: Integer;
  Tile: TDockTile;
begin
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile <> nil) and not Tile.Removing and not Tile.IsSep and
       SameItemPath(Tile.ItemPath, APath) then
      Exit(I);
  end;
  Result := -1;
end;

procedure TLaunchDock.AddSeparatorAt(AIndex: Integer);
var
  Tile: TDockTile;
  I: Integer;
  MaxX: Single;
begin
  Tile := TDockTile.CreateTile(FStrip);
  Tile.Parent := FStrip;
  Tile.SetupSeparator;
  Tile.ApplyVisual(FColors, False);
  BindTileEvents(Tile);
  if (AIndex >= 0) and (AIndex < FTiles.Count) then
    FTiles.Insert(AIndex, Tile)
  else
    FTiles.Add(Tile);
  Tile.OpValue := 1;
  Tile.TargetOp := 1;
  Tile.Opacity := 1;
  Tile.ScaleValue := 1;
  Tile.TargetScale := 1;
  if FAlignMode = daFree then
  begin
    MaxX := 0;
    for I := 0 to FTiles.Count - 1 do
      if (FTiles[I] <> Tile) and (TileOf(FTiles[I]) <> nil) and
         TileOf(FTiles[I]).Visible then
        MaxX := Max(MaxX, TileOf(FTiles[I]).PosX + TileOf(FTiles[I]).CellW);
    Tile.PosX := MaxX;
    Tile.TargetX := MaxX;
    Tile.Position.X := MaxX;
  end;
  RelayoutTargets;
  UpdateEmptyHint;
  if not FUpdating then
    ScheduleNotifyChanged;
end;

function TLaunchDock.AddOne(const APath: string; AInsertAt: Integer; AAnimate: Boolean;
  AFreeX: Single; ADeferIcon: Boolean): Boolean;
var
  Tile: TDockTile;
  Path: string;
  I: Integer;
  MaxX: Single;
begin
  Result := False;
  Path := ExcludeTrailingPathDelimiter(Trim(APath));
  if Path = '' then
    Exit;
  if SameText(Path, DOCK_SEP_TOKEN) then
  begin
    AddSeparatorAt(AInsertAt);
    Exit(True);
  end;
  if IndexOfPath(Path) >= 0 then
    Exit;

  Tile := TDockTile.CreateTile(FStrip);
  Tile.Parent := FStrip;
  Tile.ItemPath := Path;
  Tile.Caption := MakeDockCaption(Path);
  Tile.Kind := KindFromName(Path);
  Tile.IsBroken := False;
  Tile.IconLocked := False;
  Tile.IconFile := '';
  ApplyGlyph(Tile);
  Tile.ApplyVisual(FColors, False);
  BindTileEvents(Tile);

  { СНАЧАЛА в FTiles — иначе EnqueueIcon/Pump → TileByToken = nil и job теряется. }
  if (AInsertAt >= 0) and (AInsertAt < FTiles.Count) then
    FTiles.Insert(AInsertAt, Tile)
  else
    FTiles.Add(Tile);

  if AAnimate then
  begin
    Tile.ScaleValue := 0.88;
    Tile.TargetScale := SCALE_IDLE;
    Tile.OpValue := 0.55;
    Tile.TargetOp := 1;
    Tile.Opacity := 0.55;
  end
  else
  begin
    Tile.ScaleValue := SCALE_IDLE;
    Tile.TargetScale := SCALE_IDLE;
    Tile.OpValue := 1;
    Tile.TargetOp := 1;
    Tile.Opacity := 1;
  end;

  { Кэш с диска или extract — только после попадания в FTiles. }
  if not TryLoadCachedIcon(Tile) then
  begin
    if not ADeferIcon then
      EnqueueIcon(Tile, True);
  end;

  if FAlignMode = daFree then
  begin
    if AFreeX >= 0 then
      MaxX := AFreeX
    else
    begin
      MaxX := 0;
      for I := 0 to FTiles.Count - 1 do
        if (FTiles[I] <> Tile) and (TileOf(FTiles[I]) <> nil) and
           TileOf(FTiles[I]).Visible then
          MaxX := Max(MaxX, TileOf(FTiles[I]).PosX + TileOf(FTiles[I]).CellW);
    end;
    Tile.PosX := MaxX;
    Tile.TargetX := MaxX;
    Tile.Position.X := MaxX;
  end;

  RelayoutTargets;
  if FAlignMode <> daFree then
  begin
    Tile.PosX := Tile.TargetX;
    Tile.Position.X := Tile.PosX;
  end;
  UpdateEmptyHint;
  Result := True;
end;

procedure TLaunchDock.RelayoutTargets;
var
  I: Integer;
  X, ContentW, Origin, CW: Single;
  Tile, Drag: TDockTile;
  InsertAt: Integer;
  ViewW: Single;
begin
  if FAlignMode = daFree then
  begin
    X := DOCK_ICON;
    for I := 0 to FTiles.Count - 1 do
    begin
      Tile := TileOf(FTiles[I]);
      if (Tile = nil) or Tile.Removing then
        Continue;
      Tile.Visible := (not Tile.IsSep) or FShowSeps;
      if Tile.IsSep and not FShowSeps then
        Continue;
      Tile.TargetX := Tile.PosX;
      if Tile.IsSep then
        Tile.TargetCellW := SEP_CELL
      else
        Tile.TargetCellW := CELL_W;
      X := Max(X, Tile.PosX + Tile.TargetCellW);
    end;
    FStrip.Width := Max(FScroll.Width, X + 8);
    Exit;
  end;

  Drag := TileOf(FReorderTile);
  if FReorderActive and (Drag <> nil) then
    InsertAt := IndexFromStripX(Drag.Position.X + DOCK_ICON * 0.5)
  else
    InsertAt := -1;

  ContentW := 0;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile = nil) or Tile.Removing then
      Continue;
    if FReorderActive and (Tile = Drag) then
      Continue;
    if Tile.IsSep and not FShowSeps then
      Continue;
    if Tile.IsSep then
      ContentW := ContentW + SEP_CELL
    else
      ContentW := ContentW + CELL_W;
  end;
  if FReorderActive and (Drag <> nil) then
    ContentW := ContentW + CELL_W;

  ViewW := FScroll.Width;
  if ViewW <= 0 then
    ViewW := Width;
  Origin := 0;
  if (FAlignMode = daCenter) and (ContentW < ViewW) then
    Origin := (ViewW - ContentW) / 2;

  X := Origin;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if Tile = nil then
      Continue;
    Tile.Visible := (not Tile.IsSep) or FShowSeps;
    if Tile.Removing then
    begin
      Tile.TargetCellW := 0;
      Continue;
    end;
    if Tile.IsSep and not FShowSeps then
    begin
      Tile.TargetCellW := 0;
      Continue;
    end;
    if FReorderActive and (Tile = Drag) then
      Continue;
    if Tile.IsSep then
      CW := SEP_CELL
    else
      CW := CELL_W;
    if (InsertAt >= 0) and (I = InsertAt) then
      X := X + CELL_W;
    Tile.TargetX := X;
    Tile.TargetCellW := CW;
    X := X + CW;
  end;
  FStrip.Width := Max(ViewW, Max(X - Origin + Origin, DOCK_ICON));
  if FReorderActive and (Drag <> nil) and not Drag.Removing then
    FStrip.Width := Max(FStrip.Width, X + CELL_W);
end;

function TLaunchDock.IndexFromStripX(AX: Single): Integer;
var
  I: Integer;
  Tile: TDockTile;
begin
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile = nil) or Tile.Removing then
      Continue;
    if FReorderActive and (Tile = FReorderTile) then
      Continue;
    if Tile.IsSep and not FShowSeps then
      Continue;
    if AX < Tile.TargetX + Tile.TargetCellW * 0.5 then
      Exit(I);
  end;
  Result := FTiles.Count;
end;

procedure TLaunchDock.ApplyGlyph(ATile: TFmxObject);
var
  Tile: TDockTile;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  Tile.LoadIcon;
end;

function TLaunchDock.TryLoadCachedIcon(ATile: TFmxObject): Boolean;
var
  Tile: TDockTile;
  Fn, Name: string;
  Bmp: FMX.Graphics.TBitmap;
begin
  Result := False;
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  { 1) путь из настроек; 2) детерминированное имя по ItemPath (даже если INI ещё не сохранён). }
  Name := Tile.IconFile;
  if Name = '' then
    Name := DockCacheName(Tile.ItemPath);
  Fn := DockCachePath(Name);
  if not TFile.Exists(Fn) then
    Exit;
  Bmp := FMX.Graphics.TBitmap.Create;
  try
    try
      Bmp.LoadFromFile(Fn);
      if (Bmp.Width > 0) and (Bmp.Height > 0) then
      begin
        Tile.Icon.Bitmap.Assign(Bmp);
        Tile.Fallback.Visible := False;
        if Tile.IconFile = '' then
          Tile.IconFile := Name;
        Result := True;
      end;
    except
      Result := False;
    end;
  finally
    Bmp.Free;
  end;
end;

function TLaunchDock.TileByToken(AToken: Integer): TFmxObject;
var
  I: Integer;
  Tile: TDockTile;
begin
  Result := nil;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile <> nil) and (Tile.Token = AToken) then
      Exit(Tile);
  end;
end;

procedure TLaunchDock.EnqueueIcon(ATile: TFmxObject; AForce: Boolean);
var
  Tile: TDockTile;
  Remote: Boolean;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep or Tile.IconLocked or Tile.Removing then
    Exit;
  { Cooldown после неудачных попыток — сеть не долбим постоянно. }
  if (not AForce) and (Tile.FailCount >= 2) and (Tile.LastFailTick <> 0) and
     (GetTickCount - Tile.LastFailTick < 60000) then
    Exit;
  Remote := IsDockRemotePath(Tile.ItemPath);
  if Remote and not FIdleIcons and not AForce then
    Exit;
  TMonitor.Enter(FIconLock);
  try
    if FIconQueue.IndexOf(Tile.Token) < 0 then
      FIconQueue.Add(Tile.Token);
  finally
    TMonitor.Exit(FIconLock);
  end;
  PumpIconQueue;
end;

procedure TDockIconDone.Apply;
begin
  try
    if Assigned(Dock) then
      Dock.ApplyIconResult(Token, CacheName, Broken, Pixels, W, H, Remote);
  finally
    Free;
  end;
end;

procedure TLaunchDock.PumpIconQueue;
var
  Token: Integer;
  Tile: TDockTile;
  Path: string;
  Kind: TDockKind;
  Remote: Boolean;
  Job: TDockIconDone;
begin
  if (csDestroying in ComponentState) then
    Exit;
  while True do
  begin
    Token := 0;
    TMonitor.Enter(FIconLock);
    try
      if FIconQueue.Count = 0 then
        Exit;
      Tile := TileOf(TileByToken(FIconQueue[0]));
      if Tile = nil then
      begin
        FIconQueue.Delete(0);
        Continue;
      end;
      Remote := IsDockRemotePath(Tile.ItemPath);
      if Remote then
      begin
        if FRemoteBusy >= 1 then
          Exit;
        if not FIdleIcons then
          Exit;
        Inc(FRemoteBusy);
      end
      else
      begin
        if FLocalBusy >= 3 then
          Exit;
        Inc(FLocalBusy);
      end;
      Token := FIconQueue[0];
      Path := Tile.ItemPath;
      Kind := Tile.Kind;
      FIconQueue.Delete(0);
    finally
      TMonitor.Exit(FIconLock);
    end;
    Job := TDockIconDone.Create;
    Job.Dock := Self;
    Job.Token := Token;
    Job.Path := Path;
    Job.Kind := Kind;
    Job.Remote := Remote;
    TThread.CreateAnonymousThread(
      procedure
      var
        Pix: TBytes;
        W, H: Integer;
        Ok, Local: Boolean;
      begin
{$IFDEF MSWINDOWS}
        CoInitialize(nil);
{$ENDIF}
        try
          Local := not Job.Remote;
          { Локально — быстрый Exists; сеть — extract сам отработает/упадёт. }
          if Local then
            Ok := TFile.Exists(Job.Path) or TDirectory.Exists(Job.Path)
          else
            Ok := True;
          Job.Broken := False;
          Job.CacheName := '';
          if Local and not Ok then
            Job.Broken := True
          else if ExtractDockJumboRaw(Job.Path, Job.Kind = dkFolder, Pix, W, H) and
                  (W >= 16) and (H >= 16) then
          begin
            Job.Pixels := Pix;
            Job.W := W;
            Job.H := H;
            Job.CacheName := DockCacheName(Job.Path);
          end
          else
          begin
            { Extract не дал картинку }
            if Local then
              Job.Broken := not Ok
            else
              Job.Broken := True;
          end;
        finally
{$IFDEF MSWINDOWS}
          CoUninitialize;
{$ENDIF}
        end;
        TThread.Queue(nil, Job.Apply);
      end).Start;
  end;
end;

procedure TLaunchDock.ApplyIconResult(AToken: Integer; const ACache: string;
  ABroken: Boolean; const APixels: TBytes; AW, AH: Integer; ARemote: Boolean);
var
  Tile: TDockTile;
  Bmp, Fit: FMX.Graphics.TBitmap;
  Cache: string;
begin
  TMonitor.Enter(FIconLock);
  try
    if ARemote then
    begin
      if FRemoteBusy > 0 then
        Dec(FRemoteBusy);
    end
    else if FLocalBusy > 0 then
      Dec(FLocalBusy);
  finally
    TMonitor.Exit(FIconLock);
  end;
  Tile := TileOf(TileByToken(AToken));
  if Tile = nil then
  begin
    PumpIconQueue;
    Exit;
  end;
  if Tile.IconLocked or Tile.Removing then
  begin
    PumpIconQueue;
    Exit;
  end;

  Tile.IsBroken := ABroken;
  if ABroken then
  begin
    Inc(Tile.FailCount);
    Tile.LastFailTick := GetTickCount;
  end
  else if Length(APixels) > 0 then
  begin
    Tile.FailCount := 0;
    Tile.LastFailTick := 0;
  end;

  if (Length(APixels) > 0) and (AW > 0) and (AH > 0) then
  begin
    Bmp := nil;
    RawToFmxBitmap(APixels, AW, AH, Bmp);
    if Assigned(Bmp) then
    try
      FitIconIntoSquare(Bmp, Fit, 128);
      try
        Tile.Icon.Bitmap.Assign(Fit);
        Tile.Icon.Visible := True;
        Tile.Fallback.Visible := False;
        { PNG пишем на UI-потоке — FMX Canvas на worker нельзя. }
        Cache := ACache;
        if Cache = '' then
          Cache := DockCacheName(Tile.ItemPath);
        try
          ForceDirectories(DockIconsDir);
          Fit.SaveToFile(DockCachePath(Cache));
          Tile.IconFile := Cache;
        except
          { диск полный/нет прав — иконка на экране всё равно есть }
        end;
      finally
        Fit.Free;
      end;
    finally
      Bmp.Free;
    end;
  end
  else if ACache <> '' then
  begin
    { Fallback: только имя кэша без пикселей — попробуем с диска. }
    Tile.IconFile := ACache;
    TryLoadCachedIcon(Tile);
  end;

  Tile.ApplyVisual(FColors, FHoverTile = Tile);
  { Не ScheduleNotifyChanged: IconFile допишется при следующем structural save. }
  PumpIconQueue;
end;

procedure TLaunchDock.IdleIconsTick(Sender: TObject);
var
  I: Integer;
  Tile: TDockTile;
begin
  if Assigned(FIdleTimer) then
    FIdleTimer.Enabled := False;
  FIdleIcons := True;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile <> nil) and not Tile.IsSep and not Tile.IconLocked then
      if IsDockRemotePath(Tile.ItemPath) then
        EnqueueIcon(Tile, True);
  end;
end;

procedure TLaunchDock.PulseTick(Sender: TObject);
var
  I: Integer;
  Tile: TDockTile;
begin
  if not FIdleIcons then
    Exit;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile = nil) or Tile.IsSep or not Tile.IsBroken or Tile.IconLocked then
      Continue;
    { Remote broken — только через cooldown внутри EnqueueIcon (не Force). }
    EnqueueIcon(Tile, False);
  end;
end;

procedure TLaunchDock.NotifyDevicesChanged;
var
  I: Integer;
  Tile: TDockTile;
begin
  FIdleIcons := True;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile = nil) or Tile.IsSep then
      Continue;
    if Tile.IsBroken then
      Tile.IsBroken := False;
    Tile.ApplyVisual(FColors, FHoverTile = Tile);
    if not Tile.IconLocked then
      EnqueueIcon(Tile, True);
  end;
end;

procedure TLaunchDock.Tick(Sender: TObject);
var
  I: Integer;
  Tile: TDockTile;
  ScreenPt: TPointF;
  Pt: TPoint;
  Dead: TList<TFmxObject>;
  VX, MaxX: Single;
begin
  if FileDragIsActive then
  begin
    GetCursorPos(Pt);
    ScreenPt := TPointF.Create(Pt.X, Pt.Y);
    SetDropHot(PointInIsland(ScreenPt));
    if PointInIsland(ScreenPt) then
      SetDropHotTile(TileAtStripX(FStrip.ScreenToLocal(ScreenPt).X));
  end;
  RelayoutTargets;
  VX := FScroll.ViewportPosition.X;
  MaxX := Max(0.0, FStrip.Width - FScroll.Width);
  FWheelVel := FWheelVel * WHEEL_FRICTION;
  if Abs(FWheelVel) < 0.12 then
    FWheelVel := 0;
  FScrollTarget := FScrollTarget + FWheelVel;
  if FScrollTarget > MaxX then
  begin
    FScrollTarget := MaxX;
    FWheelVel := 0;
  end
  else if FScrollTarget < 0 then
  begin
    FScrollTarget := 0;
    FWheelVel := 0;
  end;
  DockApproach(VX, FScrollTarget, SCROLL_APPROACH);
  FScroll.ViewportPosition := TPointF.Create(VX, 0);
  Dead := nil;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if Tile = nil then
      Continue;
    DockApproach(Tile.ScaleValue, Tile.TargetScale, APPROACH);
    DockApproach(Tile.OpValue, Tile.TargetOp, APPROACH);
    DockApproach(Tile.CellW, Tile.TargetCellW, APPROACH);
    if not (FReorderActive and (Tile = FReorderTile)) then
      DockApproach(Tile.PosX, Tile.TargetX, APPROACH);
    Tile.Position.X := Tile.PosX;
    Tile.Position.Y := 0;
    if Tile.IsSep then
      Tile.Width := SEP_CELL
    else
      Tile.Width := DOCK_ICON;
    Tile.Height := DOCK_ICON;
    Tile.Opacity := Tile.OpValue;
    if not Tile.IsSep then
    begin
      Tile.IconHost.Scale.X := 1;
      Tile.IconHost.Scale.Y := 1;
      Tile.IconHost.Width := DOCK_ICON * Tile.ScaleValue;
      Tile.IconHost.Height := DOCK_ICON * Tile.ScaleValue;
      Tile.IconHost.Position.X := (Tile.Width - Tile.IconHost.Width) * 0.5;
      Tile.IconHost.Position.Y := (Tile.Height - Tile.IconHost.Height) * 0.5;
    end;
    if Tile.Removing and (Tile.OpValue <= 0.02) and (Tile.CellW <= 2) then
    begin
      if Dead = nil then
        Dead := TList<TFmxObject>.Create;
      Dead.Add(Tile);
    end;
  end;
  if Assigned(Dead) then
  try
    for I := 0 to Dead.Count - 1 do
    begin
      if Dead[I] is TDockTile then
        ForgetIconFile(TDockTile(Dead[I]).IconFile);
      FTiles.Remove(Dead[I]);
    end;
    UpdateEmptyHint;
    ScheduleNotifyChanged;
  finally
    Dead.Free;
  end;
end;

procedure TLaunchDock.SetDropHot(AHot: Boolean);
begin
  if FDropHot = AHot then
  begin
    if not AHot then
      SetDropHotTile(nil);
    Exit;
  end;
  FDropHot := AHot;
  if not AHot then
    SetDropHotTile(nil);
  ApplyIslandChrome;
end;

procedure TLaunchDock.SetDropHotTile(ATile: TFmxObject);
var
  Old, NewT: TDockTile;
begin
  if FDropHotTile = ATile then
    Exit;
  Old := TileOf(FDropHotTile);
  FDropHotTile := ATile;
  NewT := TileOf(ATile);
  if (NewT <> nil) and (NewT.IsSep or NewT.Removing) then
  begin
    FDropHotTile := nil;
    NewT := nil;
  end;
  if Old <> nil then
    Old.ApplyVisual(FColors, FHoverTile = Old);
  if NewT <> nil then
    NewT.ApplyVisual(FColors, True);
end;

procedure TLaunchDock.HandleWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  { Цель смещаем сразу, скорость даёт короткий выбег — анимация доезда мягче. }
  FScrollTarget := FScrollTarget - WheelDelta * WHEEL_SCALE;
  FWheelVel := FWheelVel - WheelDelta * WHEEL_SCALE * 0.08;
  Handled := True;
end;

function TLaunchDock.PointInIsland(const AScreen: TPointF): Boolean;
var
  Local: TPointF;
  R: Single;
begin
  Result := False;
  if FIsland = nil then
    Exit;
  Local := FIsland.ScreenToLocal(AScreen);
  if (Local.X < 0) or (Local.Y < 0) or
     (Local.X >= FIsland.Width) or (Local.Y >= FIsland.Height) then
    Exit;
  { Скруглённый контур острова, а не прямоугольник всей панели. }
  R := FIsland.XRadius;
  if R > 0 then
  begin
    if (Local.X < R) and (Local.Y < R) and
       (Hypot(R - Local.X, R - Local.Y) > R) then
      Exit;
    if (Local.X > FIsland.Width - R) and (Local.Y < R) and
       (Hypot(Local.X - (FIsland.Width - R), R - Local.Y) > R) then
      Exit;
    if (Local.X < R) and (Local.Y > FIsland.Height - R) and
       (Hypot(R - Local.X, Local.Y - (FIsland.Height - R)) > R) then
      Exit;
    if (Local.X > FIsland.Width - R) and (Local.Y > FIsland.Height - R) and
       (Hypot(Local.X - (FIsland.Width - R), Local.Y - (FIsland.Height - R)) > R) then
      Exit;
  end;
  Result := True;
end;

function TLaunchDock.PointToStripX(Sender: TObject; const ALocal: TPointF): Single;
var
  AbsPt: TPointF;
begin
  if Sender is TControl then
    AbsPt := TControl(Sender).LocalToAbsolute(ALocal)
  else
    AbsPt := FIsland.LocalToAbsolute(ALocal);
  Result := FStrip.AbsoluteToLocal(AbsPt).X;
end;

function TLaunchDock.TileAtStripX(AX: Single): TFmxObject;
var
  I: Integer;
  Tile: TDockTile;
begin
  Result := nil;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile = nil) or Tile.Removing or not Tile.Visible then
      Continue;
    if (AX >= Tile.PosX) and (AX <= Tile.PosX + Tile.Width) then
      Exit(Tile);
  end;
end;

function TLaunchDock.CollectDataFiles(const Data: TDragObject): TArray<string>;
var
  I: Integer;
begin
  if FileDragIsActive then
  begin
    Result := PeekFileDragPaths;
    if Length(Result) > 0 then
      Exit;
  end;
  SetLength(Result, Length(Data.Files));
  for I := 0 to High(Data.Files) do
    Result[I] := Data.Files[I];
end;

procedure TLaunchDock.IslandDragOver(Sender: TObject; const Data: TDragObject;
  const Point: TPointF; var Operation: TDragOperation);
var
  Files: TArray<string>;
  I: Integer;
  SX: Single;
  Hit: TFmxObject;
  Tile: TDockTile;
begin
  Files := CollectDataFiles(Data);
  if Length(Files) = 0 then
  begin
    SetLength(Files, Length(Data.Files));
    for I := 0 to High(Data.Files) do
      Files[I] := Data.Files[I];
  end;
  if Length(Files) = 0 then
  begin
    Operation := TDragOperation.None;
    SetDropHot(False);
    Exit;
  end;
  Operation := TDragOperation.Copy;
  SetDropHot(True);
  SX := PointToStripX(Sender, Point);
  Hit := TileAtStripX(SX);
  Tile := TileOf(Hit);
  if (Tile <> nil) and not Tile.IsSep and ((Tile.Kind = dkFolder) or (Tile.Kind = dkApp)) then
    SetDropHotTile(Hit)
  else
    SetDropHotTile(nil);
end;

procedure TLaunchDock.IslandDragDrop(Sender: TObject; const Data: TDragObject;
  const Point: TPointF);
var
  Files: TArray<string>;
  I: Integer;
  SX: Single;
  Added: Boolean;
  S: string;
  Hit: TFmxObject;
  Tile: TDockTile;
begin
  SetDropHot(False);
  Files := CollectDataFiles(Data);
  if Length(Files) = 0 then
  begin
    SetLength(Files, Length(Data.Files));
    for I := 0 to High(Data.Files) do
      Files[I] := Data.Files[I];
  end;
  SX := PointToStripX(Sender, Point);
  Hit := TileAtStripX(SX);
  Tile := TileOf(Hit);
{$IFDEF MSWINDOWS}
  if (Tile <> nil) and not Tile.IsSep and (Length(Files) = 1) and
     IsPicturePath(Files[0]) and ((GetKeyState(VK_CONTROL) and $8000) <> 0) then
  begin
    SetCustomPicture(Tile, Files[0]);
    Exit;
  end;
{$ENDIF}
  if (Tile <> nil) and not Tile.IsSep and ((Tile.Kind = dkFolder) or (Tile.Kind = dkApp)) then
  begin
    DropOnTile(Hit, Files);
    Exit;
  end;
  Added := False;
  for S in Files do
    if AddOne(S, IndexFromStripX(SX), True, SX) then
      Added := True;
  if Added then
    ScheduleNotifyChanged;
end;

procedure TLaunchDock.IslandDragLeave(Sender: TObject);
var
  Pt: TPoint;
begin
  if FileDragIsActive then
    Exit;
  GetCursorPos(Pt);
  if not PointInIsland(TPointF.Create(Pt.X, Pt.Y)) then
    SetDropHot(False);
end;

function TLaunchDock.TryAcceptExternalDrop(const AScreen: TPointF;
  const APaths: TArray<string>): Boolean;
var
  StripPt: TPointF;
  S: string;
  Added: Boolean;
  Hit: TFmxObject;
begin
  Result := PointInIsland(AScreen);
  SetDropHot(False);
  if not Result then
    Exit;
  StripPt := FStrip.ScreenToLocal(AScreen);
  Hit := TileAtStripX(StripPt.X);
  if (Hit <> nil) and (TileOf(Hit) <> nil) and not TileOf(Hit).IsSep and
     ((TileOf(Hit).Kind = dkFolder) or (TileOf(Hit).Kind = dkApp)) then
  begin
    DropOnTile(Hit, APaths);
    Exit;
  end;
  Added := False;
  for S in APaths do
    if AddOne(S, IndexFromStripX(StripPt.X), True, StripPt.X) then
      Added := True;
  Result := Added or (Length(APaths) > 0);
  if Added then
    ScheduleNotifyChanged;
end;

procedure TLaunchDock.TileMouseEnter(Sender: TObject);
var
  Tile: TDockTile;
begin
  Tile := TileOf(Sender as TFmxObject);
  if (Tile = nil) or Tile.Removing then
    Exit;
  FHoverTile := Tile;
  if not FReorderActive then
    Tile.TargetScale := SCALE_HOVER;
  Tile.ApplyVisual(FColors, True);
  FTipTile := Tile;
  FTipTimer.Enabled := False;
  FTipTimer.Enabled := True;
end;

procedure TLaunchDock.TileMouseLeave(Sender: TObject);
var
  Tile: TDockTile;
begin
  Tile := TileOf(Sender as TFmxObject);
  if Tile = nil then
    Exit;
  if FHoverTile = Tile then
    FHoverTile := nil;
  if not FReorderActive and (FReorderTile <> Tile) then
    Tile.TargetScale := SCALE_IDLE;
  Tile.ApplyVisual(FColors, False);
  if FTipTile = Tile then
  begin
    FTipTimer.Enabled := False;
    HideTip;
  end;
end;

procedure TLaunchDock.TileMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Tile: TDockTile;
begin
  Tile := TileOf(Sender as TFmxObject);
  if (Tile = nil) or Tile.Removing then
    Exit;
  HideTip;
  FTipTimer.Enabled := False;
  if Button = TMouseButton.mbLeft then
  begin
    Tile.TargetScale := SCALE_PRESS;
    FReorderTile := Tile;
    FReorderStart := TPointF.Create(X, Y);
    FReorderArmed := True;
    FReorderActive := False;
    FClickArmed := True;
    FClickTile := Tile;
    FClickDragged := False;
    Tile.Capture;
  end
  else if Button = TMouseButton.mbRight then
  begin
    FClickArmed := False;
    FClickTile := nil;
    ShowTileMenu(Tile);
  end;
end;

procedure TLaunchDock.TileMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  Tile: TDockTile;
  StripPt: TPointF;
begin
  Tile := TileOf(Sender as TFmxObject);
  if (Tile = nil) or (FReorderTile <> Tile) or not FReorderArmed then
    Exit;
  if not (ssLeft in Shift) then
    Exit;
  if not FReorderActive then
  begin
    if (Abs(X - FReorderStart.X) > 8) or (Abs(Y - FReorderStart.Y) > 8) then
    begin
      FReorderActive := True;
      FClickDragged := True;
      Tile.TargetScale := SCALE_HOVER;
      Tile.BringToFront;
    end;
  end;
  if FReorderActive then
  begin
    StripPt := FStrip.AbsoluteToLocal(Tile.LocalToAbsolute(TPointF.Create(X, Y)));
    Tile.PosX := StripPt.X - DOCK_ICON * 0.5;
    if Tile.PosX < 0 then
      Tile.PosX := 0;
    Tile.Position.X := Tile.PosX;
  end;
end;

procedure TLaunchDock.TileMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Tile: TDockTile;
  WasReorder, Ours: Boolean;
begin
  Tile := TileOf(Sender as TFmxObject);
  if Tile = nil then
    Exit;
  Tile.ReleaseCapture;
  WasReorder := FReorderActive;
  Ours := FClickArmed and (FClickTile = Tile) and not FClickDragged and
    (Button = TMouseButton.mbLeft);
  FClickArmed := False;
  FClickTile := nil;
  FClickDragged := False;
  if FReorderActive then
    FinishReorder
  else
  begin
    FReorderArmed := False;
    FReorderTile := nil;
    if Ours then
    begin
      Tile.TargetScale := SCALE_HOVER;
      OpenItem(Tile);
    end;
  end;
  if (FHoverTile = Tile) and not WasReorder then
    Tile.TargetScale := SCALE_HOVER
  else if not WasReorder then
    Tile.TargetScale := SCALE_IDLE;
end;

procedure TLaunchDock.FinishReorder;
var
  Drag: TDockTile;
  InsertAt, OldIdx: Integer;
begin
  Drag := TileOf(FReorderTile);
  FReorderActive := False;
  FReorderArmed := False;
  FReorderTile := nil;
  if Drag = nil then
    Exit;
  if FAlignMode = daFree then
  begin
    Drag.TargetX := Drag.PosX;
    ScheduleNotifyChanged;
  end
  else
  begin
    OldIdx := FTiles.IndexOf(Drag);
    InsertAt := IndexFromStripX(Drag.PosX + DOCK_ICON * 0.5);
    if InsertAt > OldIdx then
      Dec(InsertAt);
    if InsertAt < 0 then
      InsertAt := 0;
    if InsertAt >= FTiles.Count then
      InsertAt := FTiles.Count - 1;
    if (OldIdx >= 0) and (InsertAt >= 0) and (OldIdx <> InsertAt) then
    begin
      FTiles.Move(OldIdx, InsertAt);
      ScheduleNotifyChanged;
    end;
  end;
  if FHoverTile = Drag then
    Drag.TargetScale := SCALE_HOVER
  else
    Drag.TargetScale := SCALE_IDLE;
  RelayoutTargets;
end;

procedure TLaunchDock.OpenItem(ATile: TFmxObject);
var
  Tile: TDockTile;
  Tick: Cardinal;
{$IFDEF MSWINDOWS}
  Rc: HINST;
{$ENDIF}
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  Tick := GetTickCount;
  if (FOpenGuardPath <> '') and SameItemPath(FOpenGuardPath, Tile.ItemPath) and
     (Tick - FOpenGuardTick < 400) then
    Exit;
  FOpenGuardPath := Tile.ItemPath;
  FOpenGuardTick := Tick;
  if Tile.IsBroken then
  begin
    ShowToast('Путь недоступен');
    if Assigned(FOnStatus) then
      FOnStatus(Self, 'Путь недоступен');
    Exit;
  end;
  case Tile.Kind of
    dkFolder:
      if Assigned(FOnOpenFolder) then
        FOnOpenFolder(Self, Tile.ItemPath);
  else
{$IFDEF MSWINDOWS}
    Rc := ShellExecute(0, 'open', PChar(Tile.ItemPath), nil, nil, SW_SHOWNORMAL);
    if NativeUInt(Rc) <= 32 then
    begin
      if (Rc = ERROR_FILE_NOT_FOUND) or (Rc = SE_ERR_FNF) or
         (Rc = ERROR_BAD_NETPATH) or (Rc = SE_ERR_PNF) then
      begin
        Tile.IsBroken := True;
        Tile.ApplyVisual(FColors, FHoverTile = Tile);
      end;
      ShowToast('Путь недоступен');
    end;
{$ELSE}
    OpenFileWithDefaultApp(Tile.ItemPath);
{$ENDIF}
  end;
end;

procedure TLaunchDock.GoToItem(ATile: TFmxObject);
var
  Tile: TDockTile;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  if Tile.IsBroken then
  begin
    ShowToast('Путь недоступен');
    Exit;
  end;
  if Assigned(FOnGoToObject) then
    FOnGoToObject(Self, Tile.ItemPath);
end;

procedure TLaunchDock.RemoveTile(ATile: TFmxObject; AAnimate: Boolean);
var
  Tile: TDockTile;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.Removing then
    Exit;
  if not AAnimate then
  begin
    ForgetIconFile(Tile.IconFile);
    FTiles.Remove(Tile);
    UpdateEmptyHint;
    RelayoutTargets;
    ScheduleNotifyChanged;
    Exit;
  end;
  Tile.Removing := True;
  Tile.HitTest := False;
  Tile.TargetOp := 0;
  Tile.TargetScale := 0.7;
  Tile.TargetCellW := 0;
  if FHoverTile = Tile then
    FHoverTile := nil;
  HideTip;
end;

procedure TLaunchDock.DropOnTile(ATile: TFmxObject; const AFiles: TArray<string>);
var
  Tile: TDockTile;
  S, Args: string;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep or (Length(AFiles) = 0) then
    Exit;
  case Tile.Kind of
    dkFolder:
      begin
        if Assigned(FOnCopyToFolder) then
          FOnCopyToFolder(Self, Tile.ItemPath, AFiles)
        else
          CopyPathsAsync(AFiles, Tile.ItemPath, nil);
        ShowToast('Копирование в «' + Tile.Caption + '»…');
      end;
    dkApp:
      begin
        Args := '';
        for S in AFiles do
          Args := Args + '"' + S + '" ';
        {$IFDEF MSWINDOWS}
        ShellExecute(0, 'open', PChar(Tile.ItemPath), PChar(Trim(Args)), nil, SW_SHOWNORMAL);
        {$ELSE}
        for S in AFiles do
          OpenFileWithDefaultApp(S);
        {$ENDIF}
        ShowToast('Открытие в «' + Tile.Caption + '»');
      end;
  else
    Args := '';
    for S in AFiles do
      if AddOne(S, -1, True) then
        Args := '1';
    if Args <> '' then
      ScheduleNotifyChanged;
  end;
end;

procedure TLaunchDock.IslandMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbRight then
    Exit;
  if Sender is TDockTile then
    Exit;
  ShowBackgroundMenu;
end;

procedure TLaunchDock.MenuChangeClick(Sender: TObject);
var
  Tile: TDockTile;
  Dlg: TOpenDialog;
  NewPath: string;
begin
  Tile := TileOf(FMenuTile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  NewPath := '';
  if Tile.Kind = dkFolder then
  begin
    {$IFDEF MSWINDOWS}
    NewPath := PickDockFolder('Изменить папку', Tile.ItemPath);
    {$ENDIF}
  end
  else
  begin
    Dlg := TOpenDialog.Create(Self);
    try
      Dlg.Title := 'Изменить объект';
      Dlg.Filter := 'Все файлы (*.*)|*.*|Программы (*.exe)|*.exe';
      Dlg.FileName := Tile.ItemPath;
      Dlg.InitialDir := ExtractFilePath(Tile.ItemPath);
      if Dlg.Execute and (Dlg.FileName <> '') then
        NewPath := Dlg.FileName;
    finally
      Dlg.Free;
    end;
  end;
  if NewPath = '' then
    Exit;
  Tile.ItemPath := ExcludeTrailingPathDelimiter(NewPath);
  Tile.Caption := MakeDockCaption(Tile.ItemPath);
  Tile.Kind := KindFromName(Tile.ItemPath);
  Tile.IsBroken := False;
  if not Tile.IconLocked then
  begin
    Tile.IconFile := '';
    ApplyGlyph(Tile);
    EnqueueIcon(Tile, True);
  end;
  Tile.ApplyVisual(FColors, FHoverTile = Tile);
  ScheduleNotifyChanged;
end;

function TLaunchDock.IsPicturePath(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.bmp') or
    (Ext = '.gif') or (Ext = '.webp') or (Ext = '.ico') or (Ext = '.svg') or
    (Ext = '.tif') or (Ext = '.tiff') or (Ext = '.exe') or (Ext = '.dll') or
    (Ext = '.lnk');
end;

procedure TLaunchDock.ForgetIconFile(const AName: string);
var
  I, N: Integer;
  Tile: TDockTile;
  Fn: string;
begin
  if AName = '' then
    Exit;
  N := 0;
  for I := 0 to FTiles.Count - 1 do
  begin
    Tile := TileOf(FTiles[I]);
    if (Tile <> nil) and SameText(Tile.IconFile, AName) then
      Inc(N);
  end;
  if N > 0 then
    Exit;
  Fn := DockCachePath(AName);
  if TFile.Exists(Fn) then
    try
      TFile.Delete(Fn);
    except
    end;
end;

procedure TLaunchDock.SetCustomPicture(ATile: TFmxObject; const AFile: string);
var
  Tile: TDockTile;
  Ext, Cache: string;
  Bmp: FMX.Graphics.TBitmap;
  Pix: TBytes;
  W, H: Integer;
  Fit: FMX.Graphics.TBitmap;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.IsSep or (AFile = '') then
    Exit;
  Ext := LowerCase(ExtractFileExt(AFile));
  Bmp := nil;
  if (Ext = '.exe') or (Ext = '.dll') or (Ext = '.lnk') or (Ext = '.ico') then
  begin
    if ExtractDockJumboRaw(AFile, False, Pix, W, H) then
      RawToFmxBitmap(Pix, W, H, Bmp);
  end
  else if Ext = '.svg' then
  begin
    if not RenderSvgThumbRaw(AFile, 128, 128, Pix, W, H) then
    begin
      ShowToast('SVG недоступен');
      Exit;
    end;
    RawToFmxBitmap(Pix, W, H, Bmp);
  end
  else
  begin
    Bmp := FMX.Graphics.TBitmap.Create;
    try
      Bmp.LoadFromFile(AFile);
    except
      FreeAndNil(Bmp);
    end;
  end;
  if (Bmp = nil) or (Bmp.Width < 1) then
  begin
    Bmp.Free;
    ShowToast('Не удалось открыть картинку');
    Exit;
  end;
  try
    ForceDirectories(DockIconsDir);
    Cache := DockCacheName(Tile.ItemPath + '|custom|' + AFile);
    FitIconIntoSquare(Bmp, Fit, 128);
    try
      Fit.SaveToFile(DockCachePath(Cache));
      Tile.Icon.Bitmap.Assign(Fit);
    finally
      Fit.Free;
    end;
    ForgetIconFile(Tile.IconFile);
    Tile.IconFile := Cache;
    Tile.IconLocked := True;
    Tile.FailCount := 0;
    Tile.LastFailTick := 0;
    Tile.Fallback.Visible := False;
    Tile.ApplyVisual(FColors, FHoverTile = Tile);
    ScheduleNotifyChanged;
  finally
    Bmp.Free;
  end;
end;

procedure TLaunchDock.MenuChangePictureClick(Sender: TObject);
var
  Tile: TDockTile;
  Dlg: TOpenDialog;
begin
  Tile := TileOf(FMenuTile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Изменить картинку';
    Dlg.Filter :=
      'Все картинки|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp;*.ico;*.svg;*.tif;*.tiff|' +
      'PNG|*.png|JPEG|*.jpg;*.jpeg|ICO|*.ico|SVG|*.svg|' +
      'Значки и программы|*.ico;*.exe;*.dll;*.lnk|Все файлы|*.*';
    if Dlg.Execute and (Dlg.FileName <> '') then
      SetCustomPicture(Tile, Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TLaunchDock.MenuResetPictureClick(Sender: TObject);
var
  Tile: TDockTile;
begin
  Tile := TileOf(FMenuTile);
  if (Tile = nil) or Tile.IsSep then
    Exit;
  ForgetIconFile(Tile.IconFile);
  Tile.IconFile := '';
  Tile.IconLocked := False;
  Tile.Icon.Bitmap.SetSize(0, 0);
  ApplyGlyph(Tile);
  if not Tile.IsBroken then
    EnqueueIcon(Tile, True);
  Tile.ApplyVisual(FColors, FHoverTile = Tile);
  ScheduleNotifyChanged;
end;

procedure TLaunchDock.MenuGoToClick(Sender: TObject);
begin
  GoToItem(FMenuTile);
end;

procedure TLaunchDock.MenuRemoveClick(Sender: TObject);
begin
  RemoveTile(FMenuTile, True);
end;

procedure TLaunchDock.MenuAddSepClick(Sender: TObject);
begin
  FShowSeps := True;
  AddSeparatorAt(-1);
end;

procedure TLaunchDock.MenuAlignLeftClick(Sender: TObject);
begin
  SetAlignMode(daLeft);
end;

procedure TLaunchDock.MenuAlignCenterClick(Sender: TObject);
begin
  SetAlignMode(daCenter);
end;

procedure TLaunchDock.MenuAlignFreeClick(Sender: TObject);
begin
  SetAlignMode(daFree);
end;

procedure TLaunchDock.ShowTipFor(ATile: TFmxObject);
var
  Tile: TDockTile;
  W: Single;
begin
  Tile := TileOf(ATile);
  if (Tile = nil) or Tile.Removing or FReorderActive then
    Exit;
  FTipText.Text := Tile.Caption;
  W := 80;
  if (FTipText.Canvas <> nil) then
  begin
    FTipText.Canvas.Font.Family := FluentFontFamily;
    FTipText.Canvas.Font.Size := 11;
    W := FTipText.Canvas.TextWidth(Tile.Caption);
  end;
  FTip.Width := Max(56, W + 24) + 36;
  FTip.Height := 28 + 36;
  FTip.PlacementTarget := Tile;
  FTip.BorderWidth := 0;
  FTip.VerticalOffset := -14;
  FTip.IsOpen := True;
end;

procedure TLaunchDock.HideTip;
begin
  FTip.IsOpen := False;
  FTip.PlacementTarget := nil;
  FTipTile := nil;
end;

procedure TLaunchDock.TipTick(Sender: TObject);
begin
  FTipTimer.Enabled := False;
  if FTipTile <> nil then
    ShowTipFor(FTipTile);
end;

procedure TLaunchDock.ShowToast(const AText: string);
begin
  FToast.Text := AText;
  FToast.Visible := True;
  FToast.SetBounds(FIsland.Width - 220, 4, 200, 20);
  FToastTimer.Enabled := False;
  FToastTimer.Enabled := True;
end;

procedure TLaunchDock.ToastTick(Sender: TObject);
begin
  FToastTimer.Enabled := False;
  FToast.Visible := False;
end;

procedure TLaunchDock.NotifyChanged;
begin
  { Немедленный save (например при закрытии формы). }
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TLaunchDock.ScheduleNotifyChanged;
begin
  if FUpdating or (csDestroying in ComponentState) then
    Exit;
  if not Assigned(FSaveTimer) then
  begin
    NotifyChanged;
    Exit;
  end;
  { Debounce 450ms — drop/reorder не блокируют UI записью INI. }
  FSaveTimer.Enabled := False;
  FSaveTimer.Enabled := True;
end;

procedure TLaunchDock.SaveTimerTick(Sender: TObject);
begin
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;
  if FUpdating or (csDestroying in ComponentState) then
    Exit;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

end.

