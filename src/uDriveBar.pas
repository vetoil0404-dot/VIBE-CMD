unit uDriveBar;

{
  Информативные плитки дисков: иконка типа, буква + метка,
  полоска заполненности и состояния Normal / Hover / Active.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Generics.Collections,
  System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  uThemeManager, uAppSettings, uFileModel
  {$IFDEF MSWINDOWS}, Winapi.Windows,  Winapi.Messages, Winapi.ShlObj, Winapi.ActiveX{$ENDIF};

type
  TDriveClickEvent = procedure(Sender: TObject; const ARoot: string) of object;

  TDriveTile = class(TRectangle)
  private
    FInfo: TDriveInfo;
    FColors: TThemeColors;
    FHovered: Boolean;
    FActive: Boolean;
    FIcon: TImage;
    FTitle: TText;
    FUsage: TText;
    FTrack: TRectangle;
    FFill: TRectangle;
    FOnContext: TDriveClickEvent;
    FPrefW: Single;
    FLine: string;
    procedure HandleEnter(Sender: TObject);
    procedure HandleLeave(Sender: TObject);
    procedure HandleDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure TrackResize(Sender: TObject);
    procedure ApplyVisual;
    procedure UpdateBar;
    procedure ApplyTexts;
    procedure CaptureNetwork;
    procedure LoadShellIcon;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Bind(const AInfo: TDriveInfo; const AColors: TThemeColors;
      AActive: Boolean; ALite: Boolean = False);
    procedure SetStatusLine(const AText: string);
    function PreferredWidth: Single;
    procedure RefreshSpace;
    procedure Enrich;
    function IsActive: Boolean;
    procedure AssignShellIcon(ATarget: FMX.Graphics.TBitmap);
    procedure SetActive(AActive: Boolean);
    procedure ApplyTheme(const AColors: TThemeColors);
    property Info: TDriveInfo read FInfo;
    property OnContext: TDriveClickEvent read FOnContext write FOnContext;
  end;

  TDriveBar = class(TLayout)
  private
    FScroll: THorzScrollBox;
    FBg: TRectangle;
    FHost: TLayout;
    FNavCluster: TLayout;
    FBtnPrev: TRectangle;
    FBtnNext: TRectangle;
    FPrevLabel: TLabel;
    FNextLabel: TLabel;
    FTiles: TObjectList<TDriveTile>;
    FColors: TThemeColors;
    FActiveRoot: string;
    FOnDriveClick: TDriveClickEvent;
    FOnDriveContext: TDriveClickEvent;
    FOnPlacesChanged: TNotifyEvent;
    FOnPointerDown: TNotifyEvent;
    FShowNetwork: Boolean;
    FMask: DWORD;
    FNeedRebuild: Boolean;
    FPopulated: Boolean;
    FReadyForFull: Boolean;
    FRevealPending: Boolean;
    FSpaceIdx: Integer;
    FTimer: TTimer;
    {$IFDEF MSWINDOWS}
    FWnd: HWND;
    procedure WndProc(var Message: TMessage);
    {$ENDIF}
    procedure BarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure TileClick(Sender: TObject);
    procedure TileContext(Sender: TObject; const ARoot: string);
    procedure TimerTick(Sender: TObject);
    procedure Relayout;
    procedure ApplyActive;
    procedure RevealActive;
    function CurrentMask: DWORD;
    function MakeNavButton(const ACaption: string; AOnClick: TNotifyEvent;
      out ALabel: TLabel): TRectangle;
    procedure PrevClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure ScrollByDelta(ADelta: Single);
    procedure BarMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure ScrollResize(Sender: TObject);
    procedure UpdateNavButtons;
    procedure NavEnter(Sender: TObject);
    procedure NavLeave(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Rebuild;
    procedure PopulateLetters;
    procedure StartUsageFill;
    procedure AddPortablePlaces;
    procedure RefreshUsage;
    function PlaceCount: Integer;
    function PlaceTile(AIndex: Integer): TDriveTile;
    procedure SetActivePath(const APath: string);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ApplyLanguage;
    procedure SetShowNetwork(AValue: Boolean);
    procedure SetNetworkLine(const AText: string);
    property ShowNetwork: Boolean read FShowNetwork write SetShowNetwork;
    property OnDriveClick: TDriveClickEvent read FOnDriveClick write FOnDriveClick;
    property OnDriveContext: TDriveClickEvent read FOnDriveContext write FOnDriveContext;
    property OnPlacesChanged: TNotifyEvent read FOnPlacesChanged write FOnPlacesChanged;
    property OnPointerDown: TNotifyEvent read FOnPointerDown write FOnPointerDown;
  end;

  THomePlace = record
    Caption: string;
    Path: string;
  end;

  TExplorerHome = record
    Pinned: TArray<THomePlace>;
    Frequent: TArray<THomePlace>;
  end;

function DriveKindIcon(AKind: TDriveKind): string;
{ Quick Access при открытии меню и стартовый набор дока. Не на полосе дисков. }
function ReadExplorerHome: TExplorerHome;
function UnpinHomePlace(const APath: string): Boolean;
procedure SeedDockIfNeeded(ASettings: TAppSettings);

implementation

uses
  System.StrUtils, UCoreEngine, uLang
  {$IFDEF MSWINDOWS}, Winapi.PropSys, Winapi.KnownFolders, Winapi.ShLwApi{$ENDIF};

const
  TILE_W = 156;
  TILE_H = 40;
  TILE_GAP = 6;
  BAR_H = 46;
  ICON_SSD = #$EA80;
  ICON_HDD = #$E7F4;
  ICON_USB = #$EC60;
  ICON_NET = #$E968;
  ICON_CD  = #$E958;

function DriveKindIcon(AKind: TDriveKind): string;
begin
  case AKind of
    dkSSD:       Result := ICON_SSD;
    dkHDD:       Result := ICON_HDD;
    dkRemovable: Result := ICON_USB;
    dkNetwork, dkNetHood: Result := ICON_NET;
    dkOptical:   Result := ICON_CD;
  else
    Result := ICON_HDD;
  end;
end;

function FormatDriveUsage(AUsed, ATotal: Int64): string;
begin
  if ATotal <= 0 then
    Result := ''
  else
    Result := FormatDrivePair(AUsed, ATotal);
end;

function TileTitle(const AInfo: TDriveInfo): string;
begin
  Result := DrivePlaceTitle(AInfo);
end;

{ TDriveTile }

constructor TDriveTile.Create(AOwner: TComponent);
var
  TopRow, Bottom: TLayout;
begin
  inherited Create(AOwner);
  HitTest := True;
  Cursor := crHandPoint;
  XRadius := 4;
  YRadius := 4;
  Corners := AllCorners;
  Stroke.Kind := TBrushKind.Solid;
  Stroke.Thickness := 1;
  Fill.Kind := TBrushKind.Solid;
  ClipChildren := True;
  Padding.Rect := TRectF.Create(8, 4, 8, 4);
  OnMouseEnter := HandleEnter;
  OnMouseLeave := HandleLeave;
  OnMouseDown := HandleDown;
  OnMouseUp := HandleUp;

  TopRow := TLayout.Create(Self);
  TopRow.Parent := Self;
  TopRow.Align := TAlignLayout.Top;
  TopRow.Height := 18;
  TopRow.HitTest := False;

  FIcon := TImage.Create(Self);
  FIcon.Parent := TopRow;
  FIcon.Align := TAlignLayout.Left;
  FIcon.Width := 20;
  FIcon.Margins.Rect := TRectF.Create(0, 1, 6, 1);
  FIcon.WrapMode := TImageWrapMode.Fit;
  FIcon.HitTest := False;

  FTitle := TText.Create(Self);
  FTitle.Parent := TopRow;
  FTitle.Align := TAlignLayout.Client;
  FTitle.TextSettings.Font.Family := FluentFontFamily;
  FTitle.TextSettings.Font.Size := 12;
  FTitle.TextSettings.Font.Style := [TFontStyle.fsBold];
  FTitle.TextSettings.HorzAlign := TTextAlign.Leading;
  FTitle.TextSettings.VertAlign := TTextAlign.Center;
  FTitle.TextSettings.Trimming := TTextTrimming.Character;
  FTitle.WordWrap := False;
  FTitle.HitTest := False;
  FTitle.AutoSize := False;

  Bottom := TLayout.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := TAlignLayout.Client;
  Bottom.HitTest := False;
  Bottom.Margins.Rect := TRectF.Create(0, 2, 0, 0);

  FUsage := TText.Create(Self);
  FUsage.Parent := Bottom;
  FUsage.Align := TAlignLayout.Right;
  FUsage.Width := 96;
  FUsage.Margins.Rect := TRectF.Create(6, 0, 0, 0);
  FUsage.TextSettings.Font.Family := FluentFontFamily;
  FUsage.TextSettings.Font.Size := 10;
  FUsage.TextSettings.HorzAlign := TTextAlign.Trailing;
  FUsage.TextSettings.VertAlign := TTextAlign.Center;
  FUsage.WordWrap := False;
  FUsage.HitTest := False;
  FUsage.AutoSize := False;

  FTrack := TRectangle.Create(Self);
  FTrack.Parent := Bottom;
  FTrack.Align := TAlignLayout.Client;
  FTrack.Margins.Rect := TRectF.Create(0, 3, -10, 2);
  FTrack.XRadius := 2;
  FTrack.YRadius := 2;
  FTrack.Stroke.Kind := TBrushKind.None;
  FTrack.Fill.Kind := TBrushKind.Solid;
  FTrack.HitTest := False;
  FTrack.OnResize := TrackResize;

  FFill := TRectangle.Create(Self);
  FFill.Parent := FTrack;
  FFill.Align := TAlignLayout.None;
  FFill.XRadius := 2;
  FFill.YRadius := 2;
  FFill.Stroke.Kind := TBrushKind.None;
  FFill.Fill.Kind := TBrushKind.Solid;
  FFill.HitTest := False;
  FFill.Height :=4;
end;

procedure TDriveTile.ApplyTexts;
var
  Title, NewHint: string;
begin
  Title := TileTitle(FInfo);
  if FTitle.Text <> Title then
    FTitle.Text := Title;
  NewHint := DrivePlaceHint(FInfo);
  if Hint <> NewHint then
    Hint := NewHint;
  ShowHint := NewHint <> '';
end;

procedure TDriveTile.CaptureNetwork;
begin
  if FInfo.Kind = dkNetHood then
    Exit;
  if (FInfo.Kind <> dkNetwork) and not IsRemotePath(FInfo.Root) then
    Exit;
  FInfo.Kind := dkNetwork;
  if FInfo.RemotePath = '' then
    FInfo.RemotePath := MappedDriveUnc(FInfo.Root);
end;

procedure TDriveTile.Bind(const AInfo: TDriveInfo; const AColors: TThemeColors;
  AActive: Boolean; ALite: Boolean);
var
  Used: Int64;
  Usage: string;
begin
  FInfo := AInfo;
  FColors := AColors;
  FActive := AActive;
  CaptureNetwork;
  if (not ALite) or (FInfo.Kind = dkNetwork) then
    LoadShellIcon
  else
    FIcon.Bitmap.SetSize(0, 0);
  if FInfo.Ready and (FInfo.TotalBytes > 0) then
  begin
    Used := FInfo.TotalBytes - FInfo.FreeBytes;
    if Used < 0 then
      Used := 0;
    Usage := FormatDriveUsage(Used, FInfo.TotalBytes);
  end
  else if FInfo.Kind = dkNetHood then
  begin
    if FLine <> '' then
      Usage := FLine
    else
      Usage := L('drive.env');
  end
  else if FInfo.Kind = dkDevice then
    Usage := L('drive.device')
  else if ALite or (FInfo.Kind = dkNetwork) then
    Usage := ''
  else
    Usage := L('drive.nodata');
  if FUsage.Text <> Usage then
    FUsage.Text := Usage;
  FTrack.Visible := FInfo.Ready and (FInfo.TotalBytes > 0);
  ApplyTexts;
  ApplyVisual;
  UpdateBar;
  if FInfo.Kind = dkNetHood then
    SetStatusLine(Usage);
end;

procedure TDriveTile.SetStatusLine(const AText: string);
var
  Title, Line: string;
  W: Single;
begin
  Line := Trim(AText);
  if Line = '' then
    Line := L('drive.env');
  FLine := Line;
  Title := FTitle.Text;
  if Title = '' then
    Title := TileTitle(FInfo);
  FUsage.Text := Line;
  FUsage.Align := TAlignLayout.Client;
  FUsage.TextSettings.HorzAlign := TTextAlign.Leading;
  FUsage.TextSettings.Trimming := TTextTrimming.Word;
  FTitle.TextSettings.Trimming := TTextTrimming.Word;
  FTrack.Visible := False;
  W := 8 + 20 + 6 + Max(Length(Title) * 8.2, Length(Line) * 6.4) + 12;
  if W < TILE_W then
    W := TILE_W;
  FPrefW := W;
  Hint := Title + ' — ' + Line;
  ShowHint := True;
end;

function TDriveTile.PreferredWidth: Single;
begin
  if FPrefW > TILE_W then
    Result := FPrefW
  else
    Result := TILE_W;
end;

procedure TDriveTile.LoadShellIcon;
var
  Bmp: FMX.Graphics.TBitmap;
begin
  Bmp := nil;
  try
    if FInfo.Kind = dkNetwork then
      GetNetworkDriveIconBitmap(Bmp, NetworkDriveConnected(FInfo.Root))
    else
      GetFileIconBitmap(FInfo.Root, True, Bmp);
    if Assigned(Bmp) and (Bmp.Width > 0) then
      FIcon.Bitmap.Assign(Bmp)
    else
      FIcon.Bitmap.SetSize(0, 0);
  finally
    Bmp.Free;
  end;
end;

procedure TDriveTile.Enrich;
{$IFDEF MSWINDOWS}
var
  LabelBuf: array[0..MAX_PATH] of Char;
  FsBuf: array[0..63] of Char;
  Dummy: DWORD;
begin
  if FInfo.Root = '' then
    Exit;
  if FInfo.Kind = dkNetHood then
    Exit;
  if FInfo.Kind = dkDevice then
  begin
    LoadShellIcon;
    Exit;
  end;
  if IsRemotePath(FInfo.Root) or (FInfo.Kind = dkNetwork) or
     UiSkipNetworkTouch(FInfo.Root) then
  begin
    CaptureNetwork;
    ApplyTexts;
    LoadShellIcon;
    Exit;
  end;
  FillChar(LabelBuf, SizeOf(LabelBuf), 0);
  FillChar(FsBuf, SizeOf(FsBuf), 0);
  if GetVolumeInformation(PChar(FInfo.Root), LabelBuf, Length(LabelBuf),
    nil, Dummy, Dummy, FsBuf, Length(FsBuf)) then
  begin
    if LabelBuf[0] <> #0 then
      FInfo.VolumeName := string(PChar(@LabelBuf[0]));
    if FsBuf[0] <> #0 then
      FInfo.FileSystem := string(PChar(@FsBuf[0]));
  end;
  ApplyTexts;
  LoadShellIcon;
  RefreshSpace;
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure TDriveTile.RefreshSpace;
{$IFDEF MSWINDOWS}
var
  Total, FreeForCaller, TotalFree: Int64;
  Used: Int64;
  Usage: string;
begin
  if FInfo.Root = '' then
    Exit;
  if IsRemotePath(FInfo.Root) or (FInfo.Kind = dkNetwork) or
     UiSkipNetworkTouch(FInfo.Root) then
  begin
    FTrack.Visible := False;
    if FUsage.Text <> '' then
      FUsage.Text := '';
    ApplyTexts;
    Exit;
  end;
  if not GetDiskFreeSpaceEx(PChar(FInfo.Root), FreeForCaller, Total, @TotalFree) then
  begin
    ApplyTexts;
    Exit;
  end;
  if (FInfo.TotalBytes <> Total) or (FInfo.FreeBytes <> TotalFree) then
  begin
    FInfo.TotalBytes := Total;
    FInfo.FreeBytes := TotalFree;
    FInfo.Ready := True;
    Used := Total - TotalFree;
    if Used < 0 then
      Used := 0;
    Usage := FormatDriveUsage(Used, Total);
    if FUsage.Text <> Usage then
      FUsage.Text := Usage;
  end
  else
    FInfo.Ready := True;
  FTrack.Visible := FInfo.Ready and (FInfo.TotalBytes > 0);
  ApplyTexts;
  ApplyVisual;
  UpdateBar;
end;
{$ELSE}
begin
end;
{$ENDIF}

function TDriveTile.IsActive: Boolean;
begin
  Result := FActive;
end;

procedure TDriveTile.AssignShellIcon(ATarget: FMX.Graphics.TBitmap);
begin
  if ATarget = nil then
    Exit;
  if (FIcon = nil) or (FIcon.Bitmap.Width <= 0) then
    ATarget.SetSize(0, 0)
  else
    ATarget.Assign(FIcon.Bitmap);
end;

procedure TDriveTile.SetActive(AActive: Boolean);
begin
  if FActive = AActive then
    Exit;
  FActive := AActive;
  ApplyVisual;
end;

procedure TDriveTile.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  ApplyVisual;
  UpdateBar;
end;

procedure TDriveTile.ApplyVisual;
var
  UsedRatio: Single;
  BarColor: TAlphaColor;
begin
  if FActive then
  begin
    Fill.Color := FColors.AccentSubtle;
    Stroke.Color := FColors.SelectionColor;
  end
  else if FHovered then
  begin
    Fill.Color := FColors.ControlFillHover;
    Stroke.Color := FColors.ControlStroke;
  end
  else
  begin
    { Мика: плитка не закрывает прозрачную полосу дисков своим фоном. }
    if (TAlphaColorRec(FColors.HeaderBackground).A < 255) and
       not WindowChromeIsAcrylic then
      Fill.Color := TAlphaColors.Null
    else
      Fill.Color := FColors.ControlFill;
    Stroke.Color := FColors.ControlStroke;
  end;

  FTitle.TextSettings.FontColor := FColors.TextColor;
  FUsage.TextSettings.FontColor := FColors.SubTextColor;
  FTrack.Fill.Color := ThemeAdjustAlpha(FColors.TextColor, $22);

  UsedRatio := 0;
  if FInfo.Ready and (FInfo.TotalBytes > 0) then
    UsedRatio := (FInfo.TotalBytes - FInfo.FreeBytes) / FInfo.TotalBytes;
  if UsedRatio >= 0.9 then
    BarColor := FColors.DangerColor
  else if FActive then
    BarColor := FColors.SelectionColor
  else
    BarColor := ThemeAdjustAlpha(FColors.SelectionColor, $C8);
  FFill.Fill.Color := BarColor;
end;

procedure TDriveTile.UpdateBar;
var
  Ratio, W, H: Single;
begin
  if not Assigned(FTrack) or not Assigned(FFill) then
    Exit;
  H := FTrack.Height;
  if H < 2 then
    H := 4;
  if FInfo.Ready and (FInfo.TotalBytes > 0) then
    Ratio := EnsureRange((FInfo.TotalBytes - FInfo.FreeBytes) / FInfo.TotalBytes, 0, 1)
  else
    Ratio := 0;
  W := FTrack.Width * Ratio;
  if (Ratio > 0) and (W < 4) then
    W := Min(4, FTrack.Width);
  FFill.SetBounds(0, 0, W, H);
end;

procedure TDriveTile.TrackResize(Sender: TObject);
begin
  UpdateBar;
end;

procedure TDriveTile.HandleEnter(Sender: TObject);
begin
  FHovered := True;
  ApplyVisual;
end;

procedure TDriveTile.HandleLeave(Sender: TObject);
begin
  FHovered := False;
  ApplyVisual;
end;

procedure TDriveTile.HandleDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
    Fill.Color := FColors.ControlFillPressed;
end;

procedure TDriveTile.HandleUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  ApplyVisual;
  if (Button = TMouseButton.mbRight) and Assigned(FOnContext) then
    FOnContext(Self, FInfo.Root);
end;

{ TDriveBar }

constructor TDriveBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := TAlignLayout.Top;
  Height := BAR_H;
  HitTest := True;
  OnMouseDown := BarMouseDown;
  FColors := GetThemeColors(atSystem);

  FBg := TRectangle.Create(Self);
  FBg.Parent := Self;
  FBg.Align := TAlignLayout.Contents;
  FBg.HitTest := False;
  FBg.Stroke.Kind := TBrushKind.None;
  FBg.Fill.Kind := TBrushKind.Solid;
  FBg.Fill.Color := FColors.HeaderBackground;
  FTiles := TObjectList<TDriveTile>.Create(False);
  FMask := 0;
  FNeedRebuild := False;
  FPopulated := False;
  FReadyForFull := False;
  FRevealPending := False;
  FSpaceIdx := 0;
  FShowNetwork := False;

  FNavCluster := TLayout.Create(Self);
  FNavCluster.Parent := Self;
  FNavCluster.Align := TAlignLayout.Right;
  FNavCluster.Width := 0;
  FNavCluster.Margins.Rect := TRectF.Create(0, 0, 8, 12);
  FBtnPrev := MakeNavButton('‹', PrevClick, FPrevLabel);
  FBtnNext := MakeNavButton('›', NextClick, FNextLabel);
  FBtnPrev.Visible := False;
  FBtnNext.Visible := False;

  FScroll := THorzScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := TAlignLayout.Client;
  FScroll.Margins.Rect := TRectF.Create(8, 3, 8, 3);
  FScroll.ShowScrollBars := False;
  FScroll.HitTest := True;
  FScroll.AniCalculations.Animation := False;
  FScroll.OnMouseWheel := BarMouseWheel;
  FScroll.OnMouseDown := BarMouseDown;
  FScroll.OnResize := ScrollResize;

  FHost := TLayout.Create(Self);
  FHost.Parent := FScroll;
  FHost.Align := TAlignLayout.Left;
  FHost.Height := TILE_H;
  FHost.HitTest := False;
  FHost.OnMouseWheel := BarMouseWheel;
  FBg.SendToBack;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 8000;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := False;

  {$IFDEF MSWINDOWS}
  FWnd := AllocateHWnd(WndProc);
  {$ENDIF}
end;

destructor TDriveBar.Destroy;
begin
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  {$IFDEF MSWINDOWS}
  if FWnd <> 0 then
  begin
    DeallocateHWnd(FWnd);
    FWnd := 0;
  end;
  {$ENDIF}
  FreeAndNil(FTiles);
  inherited;
end;

function TDriveBar.CurrentMask: DWORD;
begin
  {$IFDEF MSWINDOWS}
  Result := GetLogicalDrives;
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

procedure TDriveBar.Relayout;
var
  I: Integer;
  X, TileW: Single;
begin
  X := 0;
  for I := 0 to FTiles.Count - 1 do
  begin
    TileW := FTiles[I].PreferredWidth;
    FTiles[I].SetBounds(X, 0, TileW, TILE_H);
    X := X + TileW + TILE_GAP;
  end;
  if X > 0 then
    X := X - TILE_GAP;
  FHost.Width := Max(X, 1);
  FHost.Height := TILE_H;
  FRevealPending := True;
  RevealActive;
  UpdateNavButtons;
end;

function DriveTileMatches(const AInfo: TDriveInfo; const ARoot: string): Boolean;
var
  TileRoot, Path: string;
begin
  Result := False;
  if Trim(AInfo.Root) = '' then
    Exit;
  TileRoot := IncludeTrailingPathDelimiter(AInfo.Root);
  Path := IncludeTrailingPathDelimiter(ARoot);
  case AInfo.Kind of
    dkNetHood:
      Result := StartsText('\\', ARoot) or
        StartsText('network://', ARoot) or StartsText('ftp://', ARoot) or
        StartsText('ftps://', ARoot) or StartsText('http://', ARoot) or
        StartsText('https://', ARoot) or SameText(ARoot, 'Сеть') or
        SameText(ARoot, AInfo.Root) or SameText(ARoot, 'Network');
    dkDevice:
      Result := SameText(ExcludeTrailingPathDelimiter(ARoot),
          ExcludeTrailingPathDelimiter(AInfo.Root)) or
        StartsText(TileRoot, Path);
  else
    if IsVirtualShellPath(ARoot) or IsPortableDevicePath(ARoot) then
      Result := False
    else
      Result := SameText(AInfo.Root,
        IncludeTrailingPathDelimiter(ExtractFileDrive(ARoot)));
  end;
end;

procedure TDriveBar.ApplyActive;
var
  I, Best: Integer;
begin
  Best := -1;
  for I := 0 to FTiles.Count - 1 do
    if DriveTileMatches(FTiles[I].Info, FActiveRoot) then
    begin
      Best := I;
      Break;
    end;
  for I := 0 to FTiles.Count - 1 do
    FTiles[I].SetActive(I = Best);
  FRevealPending := True;
  RevealActive;
end;

procedure TDriveBar.RevealActive;
var
  I: Integer;
  ViewW, MaxX, Target: Single;
begin
  if not Assigned(FScroll) or not Assigned(FHost) then
    Exit;
  Target := 0;
  for I := 0 to FTiles.Count - 1 do
    if FTiles[I].IsActive then
    begin
      ViewW := FScroll.Width;
      MaxX := Max(0, FHost.Width - ViewW);
      Target := EnsureRange(FTiles[I].Position.X - 4, 0, MaxX);
      Break;
    end;
  if (Abs(FScroll.ViewportPosition.X - Target) > 1) or
     (Abs(FScroll.ViewportPosition.Y) > 1) then
    FScroll.ViewportPosition := TPointF.Create(Target, 0);
end;

procedure TDriveBar.SetNetworkLine(const AText: string);
var
  I: Integer;
  Need: Boolean;
  Before, After: Single;
begin
  if FTiles = nil then
    Exit;
  Need := False;
  for I := 0 to FTiles.Count - 1 do
    if FTiles[I].Info.Kind = dkNetHood then
    begin
      Before := FTiles[I].Width;
      FTiles[I].SetStatusLine(AText);
      After := FTiles[I].PreferredWidth;
      if Abs(After - Before) > 0.5 then
        Need := True;
    end;
  if Need then
    Relayout;
end;

procedure TDriveBar.SetShowNetwork(AValue: Boolean);
begin
  if FShowNetwork = AValue then
    Exit;
  FShowNetwork := AValue;
  if not FPopulated then
    Exit;
  if FReadyForFull then
    Rebuild
  else
    PopulateLetters;
end;

procedure TDriveBar.Rebuild;
var
  Drives: TArray<TDriveInfo>;
  I: Integer;
  Tile: TDriveTile;
begin
  Drives := CollectAllPlaces(FShowNetwork);
  FMask := CurrentMask;
  FTiles.Clear;
  FHost.DeleteChildren;
  for I := 0 to High(Drives) do
  begin
    Tile := TDriveTile.Create(FHost);
    Tile.Parent := FHost;
    Tile.OnClick := TileClick;
    Tile.OnContext := TileContext;
    Tile.OnMouseWheel := BarMouseWheel;
    Tile.Bind(Drives[I], FColors, False);
    FTiles.Add(Tile);
  end;
  FPopulated := True;
  FReadyForFull := True;
  Relayout;
  ApplyActive;
end;

procedure TDriveBar.PopulateLetters;
var
  Drives: TArray<TDriveInfo>;
  I: Integer;
  Tile: TDriveTile;
  Net: TDriveInfo;
begin
  Drives := CollectDriveLetters;
  FMask := CurrentMask;
  FTiles.Clear;
  FHost.DeleteChildren;
  for I := 0 to High(Drives) do
  begin
    Tile := TDriveTile.Create(FHost);
    Tile.Parent := FHost;
    Tile.OnClick := TileClick;
    Tile.OnContext := TileContext;
    Tile.OnMouseWheel := BarMouseWheel;
    Tile.Bind(Drives[I], FColors, False, True);
    FTiles.Add(Tile);
  end;
  if FShowNetwork then
  begin
    Net := Default(TDriveInfo);
    Net.Kind := dkNetHood;
    Net.Root := NetworkFolderPath;
    Net.VolumeName := 'Сеть';
    Net.Ready := True;
    Tile := TDriveTile.Create(FHost);
    Tile.Parent := FHost;
    Tile.OnClick := TileClick;
    Tile.OnContext := TileContext;
    Tile.OnMouseWheel := BarMouseWheel;
    { Не lite: у «Сети» нет Enrich, иконка нужна сразу. Корень тот же, что у CollectAllPlaces. }
    Tile.Bind(Net, FColors, False, False);
    FTiles.Add(Tile);
  end;
  FPopulated := True;
  FReadyForFull := False;
  FSpaceIdx := 0;
  Relayout;
  ApplyActive;
end;

procedure TDriveBar.StartUsageFill;
begin
  if not FPopulated then
    PopulateLetters;
  FSpaceIdx := 0;
  if Assigned(FTimer) then
  begin
    FTimer.Interval := 300;
    FTimer.OnTimer := TimerTick;
    FTimer.Enabled := True;
  end;
end;

procedure TDriveBar.AddPortablePlaces;
var
  I, FirstNew: Integer;
  Have: Boolean;
  Places: TArray<TDriveInfo>;
  Tile: TDriveTile;
begin
  if not FPopulated then
    PopulateLetters;
  FirstNew := FTiles.Count;
  Places := CollectAllPlaces(FShowNetwork);
  for I := 0 to High(Places) do
  begin
    Have := False;
    for Tile in FTiles do
      if ((Places[I].Kind = dkNetHood) and (Tile.Info.Kind = dkNetHood)) or
         SameText(Tile.Info.Root, Places[I].Root) or
         SameText(ExcludeTrailingPathDelimiter(Tile.Info.Root),
           ExcludeTrailingPathDelimiter(Places[I].Root)) then
      begin
        Have := True;
        if (Places[I].Kind = dkNetHood) and
           not SameText(Tile.Info.Root, Places[I].Root) then
          Tile.Bind(Places[I], FColors, Tile.IsActive, False);
        Break;
      end;
    if Have then
      Continue;
    Tile := TDriveTile.Create(FHost);
    Tile.Parent := FHost;
    Tile.OnClick := TileClick;
    Tile.OnContext := TileContext;
    Tile.OnMouseWheel := BarMouseWheel;
    Tile.Bind(Places[I], FColors, False, Places[I].Kind <> dkNetHood);
    FTiles.Add(Tile);
  end;
  FReadyForFull := True;
  Relayout;
  ApplyActive;
  if FTiles.Count > FirstNew then
  begin
    if FSpaceIdx > FirstNew then
      FSpaceIdx := FirstNew;
    if Assigned(FTimer) then
    begin
      FTimer.Interval := 40;
      FTimer.Enabled := True;
    end;
  end;
end;

procedure TDriveBar.RefreshUsage;
var
  I: Integer;
begin
  if FNeedRebuild or (CurrentMask <> FMask) then
  begin
    FNeedRebuild := False;
    Rebuild;
    if Assigned(FOnPlacesChanged) then
      FOnPlacesChanged(Self);
    Exit;
  end;
  for I := 0 to FTiles.Count - 1 do
    FTiles[I].RefreshSpace;
end;

function TDriveBar.PlaceCount: Integer;
begin
  if FTiles = nil then
    Result := 0
  else
    Result := FTiles.Count;
end;

function TDriveBar.PlaceTile(AIndex: Integer): TDriveTile;
begin
  Result := nil;
  if (FTiles <> nil) and (AIndex >= 0) and (AIndex < FTiles.Count) then
    Result := FTiles[AIndex];
end;

procedure TDriveBar.SetActivePath(const APath: string);
begin
  FActiveRoot := APath;
  ApplyActive;
end;

procedure TDriveBar.ApplyLanguage;
begin
  if not FPopulated then
    Exit;
  if FReadyForFull then
    Rebuild
  else
    PopulateLetters;
end;

procedure TDriveBar.ApplyTheme(const AColors: TThemeColors);
var
  I: Integer;
begin
  FColors := AColors;
  if Assigned(FBg) then
    FBg.Fill.Color := AColors.HeaderBackground;
  if Assigned(FBtnPrev) then
    FBtnPrev.Fill.Color := AColors.ControlFill;
  if Assigned(FBtnNext) then
    FBtnNext.Fill.Color := AColors.ControlFill;
  if Assigned(FPrevLabel) then
    FPrevLabel.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FNextLabel) then
    FNextLabel.TextSettings.FontColor := AColors.TextColor;
  for I := 0 to FTiles.Count - 1 do
    FTiles[I].ApplyTheme(AColors);
end;

procedure TDriveBar.BarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Assigned(FOnPointerDown) then
    FOnPointerDown(Self);
end;

procedure TDriveBar.TileClick(Sender: TObject);
begin
  if not (Sender is TDriveTile) then
    Exit;
  if Assigned(FOnDriveClick) then
    FOnDriveClick(Self, TDriveTile(Sender).Info.Root);
end;

procedure TDriveBar.TileContext(Sender: TObject; const ARoot: string);
begin
  if Assigned(FOnDriveContext) then
    FOnDriveContext(Self, ARoot);
end;

function TDriveBar.MakeNavButton(const ACaption: string; AOnClick: TNotifyEvent;
  out ALabel: TLabel): TRectangle;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := FNavCluster;
  Result.Align := TAlignLayout.Left;
  Result.Width := 26;
  Result.Margins.Rect := TRectF.Create(2, 2, 0, 2);
  Result.XRadius := 6;
  Result.YRadius := 6;
  Result.Stroke.Kind := TBrushKind.None;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.Fill.Color := FColors.ControlFill;
  Result.HitTest := True;
  Result.Cursor := crHandPoint;
  Result.OnClick := AOnClick;
  Result.OnMouseDown := BarMouseDown;
  Result.OnMouseEnter := NavEnter;
  Result.OnMouseLeave := NavLeave;
  Result.OnMouseWheel := BarMouseWheel;

  ALabel := TLabel.Create(Result);
  ALabel.Parent := Result;
  ALabel.Align := TAlignLayout.Client;
  ALabel.Text := ACaption;
  ALabel.TextAlign := TTextAlign.Center;
  ALabel.TextSettings.Font.Family := FluentFontFamily;
  ALabel.TextSettings.Font.Size := 14;
  ALabel.StyledSettings := ALabel.StyledSettings -
    [TStyledSetting.Family, TStyledSetting.Size, TStyledSetting.FontColor];
  ALabel.TextSettings.FontColor := FColors.TextColor;
  ALabel.HitTest := False;
end;

procedure TDriveBar.PrevClick(Sender: TObject);
begin
  ScrollByDelta(-TILE_W - TILE_GAP);
end;

procedure TDriveBar.NextClick(Sender: TObject);
begin
  ScrollByDelta(TILE_W + TILE_GAP);
end;

procedure TDriveBar.ScrollByDelta(ADelta: Single);
var
  MaxX, NewX: Single;
begin
  if not Assigned(FScroll) then
    Exit;
  MaxX := Max(0, FHost.Width - FScroll.Width);
  NewX := EnsureRange(FScroll.ViewportPosition.X + ADelta, 0, MaxX);
  FScroll.ViewportPosition := TPointF.Create(NewX, 0);
  UpdateNavButtons;
end;

procedure TDriveBar.BarMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  if WheelDelta > 0 then
    ScrollByDelta(-(TILE_W + TILE_GAP))
  else
    ScrollByDelta(TILE_W + TILE_GAP);
  Handled := True;
end;

procedure TDriveBar.ScrollResize(Sender: TObject);
begin
  if FRevealPending and Assigned(FScroll) and (FScroll.Width > 20) then
  begin
    RevealActive;
    FRevealPending := False;
  end;
  UpdateNavButtons;
end;

procedure TDriveBar.UpdateNavButtons;
var
  Overflow, CanLeft, CanRight: Boolean;
  MaxX: Single;
begin
  if not Assigned(FScroll) or not Assigned(FNavCluster) then
    Exit;
  Overflow := FHost.Width > FScroll.Width + 2;
  FBtnPrev.Visible := Overflow;
  FBtnNext.Visible := Overflow;
  if Overflow then
    FNavCluster.Width := 56
  else
    FNavCluster.Width := 0;
  if Overflow then
  begin
    MaxX := Max(0, FHost.Width - FScroll.Width);
    CanLeft := FScroll.ViewportPosition.X > 1;
    CanRight := FScroll.ViewportPosition.X < MaxX - 1;
    FBtnPrev.Opacity := IfThen(CanLeft, 1.0, 0.35);
    FBtnNext.Opacity := IfThen(CanRight, 1.0, 0.35);
    FBtnPrev.HitTest := CanLeft;
    FBtnNext.HitTest := CanRight;
  end;
end;

procedure TDriveBar.NavEnter(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FColors.ControlFillHover;
end;

procedure TDriveBar.NavLeave(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FColors.ControlFill;
end;

procedure TDriveBar.TimerTick(Sender: TObject);
begin
  if FSpaceIdx < FTiles.Count then
  begin
    FTiles[FSpaceIdx].Enrich;
    Inc(FSpaceIdx);
    if Assigned(FTimer) then
    begin
      FTimer.Interval := 40;
      FTimer.Enabled := True;
    end;
    Exit;
  end;
  if Assigned(FTimer) then
    FTimer.Interval := 8000;
  RefreshUsage;
end;

{$IFDEF MSWINDOWS}
procedure TDriveBar.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_DEVICECHANGE then
  begin
    FNeedRebuild := True;
    if Assigned(FTimer) then
    begin
      FTimer.Interval := 400;
      FTimer.Enabled := False;
      FTimer.Enabled := True;
    end;
    Message.Result := 1;
  end
  else
    Message.Result := DefWindowProc(FWnd, Message.Msg, Message.WParam, Message.LParam);
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
const
  FOLDERID_QuickAccess: TGUID = '{679F85CB-0220-4080-B29B-5540CC05AAB6}';
  { System.Home.IsPinned — propkey.h / wine }
  PKEY_Home_IsPinned: TPropertyKey = (
    fmtid: '{30C8EEF4-A832-41E2-AB32-E3C3CA28FD29}';
    pid: 4);
  PKEY_ItemNameDisplay: TPropertyKey = (
    fmtid: '{B725F130-47EF-101A-A5F1-02608C9EEBAC}';
    pid: 10);
  HOME_ENUM_CAP = 48;
  HOME_FREQUENT_MAX = 8;

function ShellVirtual(const APath: string): Boolean;
var
  S: string;
begin
  S := Trim(APath);
  Result := StartsText('shell:', S) or StartsText('::', S) or (Pos('::{', S) > 0);
end;

function NormalizeHomePath(const APath: string): string;
begin
  Result := Trim(StringReplace(APath, '/', '\', [rfReplaceAll]));
  if Result <> '' then
    Result := ExcludeTrailingPathDelimiter(Result);
end;

function IsHomeFilePath(const APath: string): Boolean;
var
  S: string;
begin
  S := Trim(APath);
  if (S = '') or ShellVirtual(S) then
    Exit(False);
  if (Length(S) >= 3) and (S[2] = ':') and ((S[3] = '\') or (S[3] = '/')) then
    Exit(True);
  Result := StartsText('\\', S) and (Length(S) > 2);
end;

function HomeKey(const APath: string): string;
var
  S: string;
begin
  S := NormalizeHomePath(APath);
  if (Length(S) = 2) and (S[2] = ':') then
    S := S + '\';
  Result := AnsiLowerCase(IncludeTrailingPathDelimiter(S));
end;

function ShellText(const AItem: IShellItem; ASig: DWORD): string;
var
  W: LPWSTR;
begin
  Result := '';
  if (AItem <> nil) and Succeeded(AItem.GetDisplayName(ASig, W)) and (W <> nil) then
  begin
    Result := W;
    CoTaskMemFree(W);
  end;
end;

function ItemFilePath(const AItem: IShellItem): string;
var
  Parse, Fs: string;
begin
  Result := '';
  Parse := ShellText(AItem, SIGDN_DESKTOPABSOLUTEPARSING);
  if (Parse <> '') and (not ShellVirtual(Parse)) and
     IsHomeFilePath(NormalizeHomePath(Parse)) then
    Exit(NormalizeHomePath(Parse));
  if (Parse = '') or ShellVirtual(Parse) then
  begin
    Fs := NormalizeHomePath(ShellText(AItem, SIGDN_FILESYSPATH));
    if (Fs <> '') and (not ShellVirtual(Fs)) and IsHomeFilePath(Fs) then
      Exit(Fs);
  end;
end;

function UsableHomeCaption(const ACaption: string): Boolean;
var
  S: string;
begin
  S := Trim(ACaption);
  Result := (S <> '') and (S <> '.') and (S <> '..') and not ShellVirtual(S);
end;

function ItemIsPinned(const AItem: IShellItem): Boolean;
var
  Item2: IShellItem2;
  Store: IPropertyStore;
  V: TPropVariant;
begin
  Result := False;
  if not Supports(AItem, IID_IShellItem2, Item2) then
    Exit;
  Store := nil;
  { IsPinned не лежит в быстром наборе: FASTPROPERTIESONLY отдаёт пусто,
    и закреплённые папки пропадают из списка. }
  if Failed(Item2.GetPropertyStore(Winapi.PropSys.GPS_BESTEFFORT,
       IID_IPropertyStore, Store)) or (Store = nil) then
    Exit;
  FillChar(V, SizeOf(V), 0);
  if Failed(Store.GetValue(PKEY_Home_IsPinned, V)) then
    Exit;
  try
    if V.vt = VT_BOOL then
      Result := V.boolVal
    else if (V.vt = VT_I4) or (V.vt = VT_INT) then
      Result := V.lVal <> 0
    else if V.vt = VT_UI4 then
      Result := V.ulVal <> 0;
  finally
    PropVariantClear(V);
  end;
end;

function FolderChildCaption(const AFolder: IShellFolder; AChild: PItemIDList): string;
var
  SR: TStrRet;
  W: LPWSTR;
begin
  Result := '';
  if (AFolder = nil) or (AChild = nil) then
    Exit;
  FillChar(SR, SizeOf(SR), 0);
  if Failed(AFolder.GetDisplayNameOf(AChild, SHGDN_NORMAL, SR)) then
    Exit;
  W := nil;
  if Succeeded(StrRetToStr(@SR, AChild, W)) and (W <> nil) then
  begin
    Result := Trim(W);
    CoTaskMemFree(W);
  end;
end;

function ItemPropCaption(const AItem: IShellItem): string;
var
  Item2: IShellItem2;
  Store: IPropertyStore;
  V: TPropVariant;
begin
  Result := '';
  if not Supports(AItem, IID_IShellItem2, Item2) then
    Exit;
  Store := nil;
  if Failed(Item2.GetPropertyStore(Winapi.PropSys.GPS_BESTEFFORT,
       IID_IPropertyStore, Store)) or (Store = nil) then
    Exit;
  FillChar(V, SizeOf(V), 0);
  if Failed(Store.GetValue(PKEY_ItemNameDisplay, V)) then
    Exit;
  try
    if (V.vt = VT_LPWSTR) and (V.pwszVal <> nil) then
      Result := Trim(V.pwszVal)
    else if (V.vt = VT_BSTR) and (V.bstrVal <> nil) then
      Result := Trim(string(V.bstrVal));
  finally
    PropVariantClear(V);
  end;
end;

function RawLinkTarget(const ALnk: string): string;
var
  Link: IShellLink;
  Pf: IPersistFile;
  Buf: array[0..MAX_PATH] of WideChar;
  Fd: TWin32FindDataW;
begin
  Result := '';
  if Failed(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER,
      IShellLink, Link)) then
    Exit;
  if Failed(Link.QueryInterface(IPersistFile, Pf)) then
    Exit;
  if Failed(Pf.Load(PWideChar(ALnk), STGM_READ)) then
    Exit;
  FillChar(Fd, SizeOf(Fd), 0);
  FillChar(Buf, SizeOf(Buf), 0);
  if Failed(Link.GetPath(@Buf[0], MAX_PATH, Fd, SLGP_RAWPATH)) then
    Exit;
  Result := NormalizeHomePath(string(Buf));
end;

function ChildIsFolder(const AFolder: IShellFolder; AChild: PItemIDList): Boolean;
var
  Attr: UINT;
  One: PItemIDList;
begin
  Result := True;
  if (AFolder = nil) or (AChild = nil) then
    Exit;
  One := AChild;
  Attr := SFGAO_FOLDER;
  if Failed(AFolder.GetAttributesOf(1, One, Attr)) then
    Exit;
  Result := (Attr and SFGAO_FOLDER) <> 0;
end;

function TryAddPlace(var AList: TArray<THomePlace>; ASeen: TDictionary<string, Byte>;
  const APlace: THomePlace; ALimit: Integer): Boolean;
var
  Path, Key, Cap: string;
  N: Integer;
begin
  Result := False;
  Path := NormalizeHomePath(APlace.Path);
  if not IsHomeFilePath(Path) then
    Exit;
  if (ALimit > 0) and (Length(AList) >= ALimit) then
    Exit;
  Key := HomeKey(Path);
  if (Key = '') or ASeen.ContainsKey(Key) then
    Exit;
  Cap := Trim(APlace.Caption);
  if not UsableHomeCaption(Cap) then
    Cap := ExtractFileName(Path);
  if not UsableHomeCaption(Cap) then
    Cap := Path;
  if not UsableHomeCaption(Cap) then
    Exit;
  ASeen.Add(Key, 1);
  N := Length(AList);
  SetLength(AList, N + 1);
  AList[N].Path := Path;
  AList[N].Caption := Cap;
  Result := True;
end;

function KnownPlace(const AId: TGUID; out APlace: THomePlace): Boolean;
var
  P: LPWSTR;
  Item: IShellItem;
begin
  Result := False;
  APlace.Caption := '';
  APlace.Path := '';
  P := nil;
  if Failed(SHGetKnownFolderPath(AId, KF_FLAG_DONT_VERIFY, 0, P)) or (P = nil) then
    Exit;
  try
    APlace.Path := NormalizeHomePath(string(P));
  finally
    CoTaskMemFree(P);
  end;
  if not IsHomeFilePath(APlace.Path) then
    Exit;
  if not IsUncPath(APlace.Path) then
  begin
    Item := nil;
    if Succeeded(SHCreateItemFromParsingName(PChar(APlace.Path), nil,
         IID_IShellItem, Item)) and (Item <> nil) then
      APlace.Caption := ShellText(Item, SIGDN_NORMALDISPLAY);
  end;
  Result := True;
end;

procedure AppendKnownFolders(var AList: TArray<THomePlace>);
var
  Seen: TDictionary<string, Byte>;

  procedure AddOne(const AId: TGUID);
  var
    Place: THomePlace;
  begin
    if KnownPlace(AId, Place) then
      TryAddPlace(AList, Seen, Place, 0);
  end;

begin
  Seen := TDictionary<string, Byte>.Create;
  try
    AddOne(FOLDERID_Desktop);
    AddOne(FOLDERID_Downloads);
    AddOne(FOLDERID_Documents);
    AddOne(FOLDERID_Pictures);
    AddOne(FOLDERID_Music);
    AddOne(FOLDERID_Videos);
  finally
    Seen.Free;
  end;
end;

function OpenQuickAccess(out AItem: IShellItem): Boolean;
var
  Raw: Pointer;
begin
  AItem := nil;
  Raw := nil;
  if Succeeded(SHGetKnownFolderItem(FOLDERID_QuickAccess, KF_FLAG_DONT_VERIFY, 0,
       IID_IShellItem, Raw)) and (Raw <> nil) then
  begin
    Pointer(AItem) := Raw;
    Exit(True);
  end;
  Result := Succeeded(SHCreateItemFromParsingName(
    'shell:::{679F85CB-0220-4080-B29B-5540CC05AAB6}', nil,
    IID_IShellItem, AItem)) and (AItem <> nil);
end;

function EnumQuickAccess(var APinned, AFrequent: TArray<THomePlace>): Boolean;
var
  RootItem: IShellItem;
  Folder: IShellFolder;
  ParentPidl, Child: PItemIDList;
  Enum: IEnumIDList;
  Fetched: ULONG;
  Item: IShellItem;
  Place: THomePlace;
  SeenPin, SeenFreq: TDictionary<string, Byte>;
  N: Integer;
begin
  Result := False;
  if not OpenQuickAccess(RootItem) then
    Exit;
  if Failed(RootItem.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, Folder)) or
     (Folder = nil) then
    Exit;
  ParentPidl := nil;
  if Failed(SHGetIDListFromObject(RootItem, ParentPidl)) or (ParentPidl = nil) then
    Exit;
  try
    if Failed(Folder.EnumObjects(0,
         SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN or
         SHCONTF_FASTITEMS, Enum)) or
       (Enum = nil) then
      Exit;
    Result := True;
    SeenPin := TDictionary<string, Byte>.Create;
    SeenFreq := TDictionary<string, Byte>.Create;
    try
      N := 0;
      while N < HOME_ENUM_CAP do
      begin
        Child := nil;
        Fetched := 0;
        if Enum.Next(1, Child, Fetched) <> S_OK then
          Break;
        if (Fetched = 0) or (Child = nil) then
        begin
          if Child <> nil then
            ILFree(Child);
          Break;
        end;
        Inc(N);
        try
          Item := nil;
          if Failed(SHCreateItemWithParent(ParentPidl, Folder, Child,
               IID_IShellItem, Item)) or (Item = nil) then
            Continue;
          Place.Path := ItemFilePath(Item);
          if SameText(ExtractFileExt(Place.Path), '.lnk') then
          begin
            Place.Path := RawLinkTarget(Place.Path);
            if not IsHomeFilePath(Place.Path) then
              Continue;
          end;
          if Place.Path = '' then
            Continue;
          { Недавние файлы Home не показываем. Папку без атрибута оставляем. }
          if (not ChildIsFolder(Folder, Child)) and
             (ExtractFileExt(Place.Path) <> '') then
            Continue;
          Place.Caption := FolderChildCaption(Folder, Child);
          if not UsableHomeCaption(Place.Caption) then
            Place.Caption := ShellText(Item, SIGDN_PARENTRELATIVEFORADDRESSBAR);
          if not UsableHomeCaption(Place.Caption) then
            Place.Caption := ShellText(Item, SIGDN_NORMALDISPLAY);
          if not UsableHomeCaption(Place.Caption) then
            Place.Caption := ItemPropCaption(Item);
          if IsRemotePath(Place.Path) then
            TryAddPlace(AFrequent, SeenFreq, Place, 32)
          else if ItemIsPinned(Item) then
            TryAddPlace(APinned, SeenPin, Place, 0)
          else
            TryAddPlace(AFrequent, SeenFreq, Place, 32);
        finally
          ILFree(Child);
        end;
      end;
    finally
      SeenPin.Free;
      SeenFreq.Free;
    end;
  finally
    ILFree(ParentPidl);
  end;
end;

function VerbCommandId(const AMenu: IContextMenu; APop: HMENU;
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

function InvokeMenuVerb(const AMenu: IContextMenu; APop: HMENU;
  const AVerb: string; AById: Boolean): Boolean;
var
  Id: UINT;
  ICI: TCMInvokeCommandInfoEx;
  VerbA: AnsiString;
  VerbW: string;
begin
  Result := False;
  if (AMenu = nil) or (APop = 0) or (AVerb = '') then
    Exit;
  FillChar(ICI, SizeOf(ICI), 0);
  ICI.cbSize := SizeOf(ICI);
  ICI.fMask := CMIC_MASK_UNICODE or CMIC_MASK_FLAG_NO_UI;
  ICI.nShow := SW_HIDE;
  Id := 0;
  if AById then
    Id := VerbCommandId(AMenu, APop, AVerb);
  if Id <> 0 then
  begin
    ICI.lpVerb := MakeIntResourceA(Id - 1);
    ICI.lpVerbW := MakeIntResource(Id - 1);
  end
  else if not AById then
  begin
    VerbA := AnsiString(AVerb);
    VerbW := AVerb;
    ICI.lpVerb := PAnsiChar(VerbA);
    ICI.lpVerbW := PWideChar(VerbW);
  end
  else
    Exit;
  Result := Succeeded(AMenu.InvokeCommand(PCMInvokeCommandInfo(@ICI)^));
end;

function InvokeHomeVerbs(const AMenu: IContextMenu; AAllowRemove: Boolean): Boolean;
var
  Pop: HMENU;
begin
  Result := False;
  if AMenu = nil then
    Exit;
  Pop := CreatePopupMenu;
  if Pop = 0 then
    Exit;
  try
    if Failed(AMenu.QueryContextMenu(Pop, 0, 1, $7FFF,
         CMF_NORMAL or CMF_EXPLORE or CMF_ITEMMENU or CMF_EXTENDEDVERBS)) then
      Exit;
    if InvokeMenuVerb(AMenu, Pop, 'unpinfromhome', True) then
      Exit(True);
    if AAllowRemove and InvokeMenuVerb(AMenu, Pop, 'removefromhome', True) then
      Exit(True);
    if InvokeMenuVerb(AMenu, Pop, 'unpinfromhome', False) then
      Exit(True);
    if AAllowRemove then
      Result := InvokeMenuVerb(AMenu, Pop, 'removefromhome', False);
  finally
    DestroyMenu(Pop);
  end;
end;

function InvokeHomeUnpin(const AFolder: IShellFolder; AChild: PItemIDList): Boolean;
var
  Menu: IContextMenu;
begin
  Result := False;
  if (AFolder = nil) or (AChild = nil) then
    Exit;
  // Меню самой папки содержит только «Закрепить». «Открепить» и «Удалить
  // с панели» живут у дочернего элемента Быстрого доступа.
  if Failed(AFolder.GetUIObjectOf(0, 1, AChild, IID_IContextMenu, nil, Menu)) or
     (Menu = nil) then
    Exit;
  Result := InvokeHomeVerbs(Menu, True);
end;

function HomeChildMatches(const AItem: IShellItem; const AKey: string): Boolean;
var
  Path, Fs: string;
begin
  Result := False;
  if (AItem = nil) or (AKey = '') then
    Exit;
  Path := ItemFilePath(AItem);
  if SameText(ExtractFileExt(Path), '.lnk') then
    Path := RawLinkTarget(Path);
  if HomeKey(Path) = AKey then
    Exit(True);
  Fs := NormalizeHomePath(ShellText(AItem, SIGDN_FILESYSPATH));
  if SameText(ExtractFileExt(Fs), '.lnk') then
    Fs := RawLinkTarget(Fs);
  Result := HomeKey(Fs) = AKey;
end;

function FindHomeChild(const APath: string; out AFolder: IShellFolder;
  out AChild: PItemIDList): Boolean;
var
  RootItem: IShellItem;
  Folder: IShellFolder;
  ParentPidl, Child: PItemIDList;
  Enum: IEnumIDList;
  Fetched: ULONG;
  Item: IShellItem;
  Key: string;
  N: Integer;
begin
  Result := False;
  AFolder := nil;
  AChild := nil;
  Key := HomeKey(APath);
  if (Key = '') or not OpenQuickAccess(RootItem) then
    Exit;
  if Failed(RootItem.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, Folder)) or
     (Folder = nil) then
    Exit;
  ParentPidl := nil;
  if Failed(SHGetIDListFromObject(RootItem, ParentPidl)) or (ParentPidl = nil) then
    Exit;
  try
    if Failed(Folder.EnumObjects(0,
         SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN or
         SHCONTF_FASTITEMS, Enum)) or
       (Enum = nil) then
      Exit;
    N := 0;
    while N < HOME_ENUM_CAP do
    begin
      Child := nil;
      Fetched := 0;
      if Enum.Next(1, Child, Fetched) <> S_OK then
        Break;
      if (Fetched = 0) or (Child = nil) then
      begin
        if Child <> nil then
          ILFree(Child);
        Break;
      end;
      Inc(N);
      try
        Item := nil;
        if Failed(SHCreateItemWithParent(ParentPidl, Folder, Child,
             IID_IShellItem, Item)) or (Item = nil) then
          Continue;
        if not HomeChildMatches(Item, Key) then
          Continue;
        AFolder := Folder;
        AChild := ILClone(Child);
        Result := AChild <> nil;
        Exit;
      finally
        ILFree(Child);
      end;
    end;
  finally
    ILFree(ParentPidl);
  end;
end;
{$ENDIF}

function UnpinHomePlace(const APath: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Folder: IShellFolder;
  Child: PItemIDList;
  Item: IShellItem;
  Menu: IContextMenu;
{$ENDIF}
begin
  Result := False;
  {$IFDEF MSWINDOWS}
  Folder := nil;
  Child := nil;
  if FindHomeChild(APath, Folder, Child) then
  try
    Result := InvokeHomeUnpin(Folder, Child);
  finally
    ILFree(Child);
  end;
  if Result then
    Exit;
  Item := nil;
  if Failed(SHCreateItemFromParsingName(PChar(NormalizeHomePath(APath)), nil,
       IID_IShellItem, Item)) or (Item = nil) then
    Exit;
  if Failed(Item.BindToHandler(nil, BHID_SFUIObject, IID_IContextMenu, Menu)) or
     (Menu = nil) then
    Exit;
  Result := InvokeHomeVerbs(Menu, False);
  {$ENDIF}
end;

function ReadExplorerHome: TExplorerHome;
{$IFDEF MSWINDOWS}
var
  RawFreq: TArray<THomePlace>;
  Seen: TDictionary<string, Byte>;
  I: Integer;
  Ok: Boolean;
{$ENDIF}
begin
  SetLength(Result.Pinned, 0);
  SetLength(Result.Frequent, 0);
  {$IFDEF MSWINDOWS}
  SetLength(RawFreq, 0);
  try
    Ok := EnumQuickAccess(Result.Pinned, RawFreq);
    if (not Ok) or (Length(Result.Pinned) = 0) then
    begin
      SetLength(Result.Pinned, 0);
      AppendKnownFolders(Result.Pinned);
    end;
    Seen := TDictionary<string, Byte>.Create;
    try
      for I := 0 to High(Result.Pinned) do
        Seen.AddOrSetValue(HomeKey(Result.Pinned[I].Path), 1);
      for I := 0 to High(RawFreq) do
      begin
        if Length(Result.Frequent) >= HOME_FREQUENT_MAX then
          Break;
        TryAddPlace(Result.Frequent, Seen, RawFreq[I], HOME_FREQUENT_MAX);
      end;
    finally
      Seen.Free;
    end;
  except
    SetLength(Result.Pinned, 0);
    SetLength(Result.Frequent, 0);
    try
      AppendKnownFolders(Result.Pinned);
    except
      SetLength(Result.Pinned, 0);
    end;
  end;
  {$ENDIF}
end;

procedure SeedDockIfNeeded(ASettings: TAppSettings);
var
  Home: TExplorerHome;
  Paths, Caps: TArray<string>;
  I, N: Integer;
  HasBin: Boolean;
begin
  if (ASettings = nil) or not ASettings.DockSeedPending then
    Exit;
  Home := ReadExplorerHome;
  N := Length(Home.Pinned);
  SetLength(Paths, N);
  SetLength(Caps, N);
  HasBin := False;
  for I := 0 to N - 1 do
  begin
    Paths[I] := Home.Pinned[I].Path;
    Caps[I] := Home.Pinned[I].Caption;
    if IsRecycleBinPath(Paths[I]) then
      HasBin := True;
  end;
  if not HasBin then
  begin
    SetLength(Paths, N + 1);
    SetLength(Caps, N + 1);
    Paths[N] := RecycleBinPath;
    Caps[N] := L('bin.title');
  end;
  ASettings.CommitDockSeed(Paths, Caps);
end;

end.
