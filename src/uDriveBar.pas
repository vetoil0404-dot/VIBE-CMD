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
    procedure HandleEnter(Sender: TObject);
    procedure HandleLeave(Sender: TObject);
    procedure HandleDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure TrackResize(Sender: TObject);
    procedure ApplyVisual;
    procedure UpdateBar;
    procedure LoadShellIcon;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Bind(const AInfo: TDriveInfo; const AColors: TThemeColors;
      AActive: Boolean; ALite: Boolean = False);
    procedure RefreshSpace;
    procedure Enrich;
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
    FShowNetwork: Boolean;
    FMask: DWORD;
    FNeedRebuild: Boolean;
    FPopulated: Boolean;
    FReadyForFull: Boolean;
    FSpaceIdx: Integer;
    FTimer: TTimer;
    {$IFDEF MSWINDOWS}
    FWnd: HWND;
    procedure WndProc(var Message: TMessage);
    {$ENDIF}
    procedure TileClick(Sender: TObject);
    procedure TileContext(Sender: TObject; const ARoot: string);
    procedure TimerTick(Sender: TObject);
    procedure Relayout;
    procedure ApplyActive;
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
    procedure SetActivePath(const APath: string);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SetShowNetwork(AValue: Boolean);
    property ShowNetwork: Boolean read FShowNetwork write SetShowNetwork;
    property OnDriveClick: TDriveClickEvent read FOnDriveClick write FOnDriveClick;
    property OnDriveContext: TDriveClickEvent read FOnDriveContext write FOnDriveContext;
    property OnPlacesChanged: TNotifyEvent read FOnPlacesChanged write FOnPlacesChanged;
  end;

implementation

uses
  System.StrUtils, UCoreEngine;

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

function KindIcon(AKind: TDriveKind): string;
begin
  case AKind of
    dkSSD:       Result := ICON_SSD;
    dkHDD:       Result := ICON_HDD;
    dkRemovable: Result := ICON_USB;
    dkNetwork:   Result := ICON_NET;
    dkOptical:   Result := ICON_CD;
  else
    Result := ICON_HDD;
  end;
end;

function KindCaption(AKind: TDriveKind): string;
begin
  Result := DriveKindCaption(AKind);
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

procedure TDriveTile.Bind(const AInfo: TDriveInfo; const AColors: TThemeColors;
  AActive: Boolean; ALite: Boolean);
var
  Used: Int64;
  Title, Usage, NewHint: string;
begin
  FInfo := AInfo;
  FColors := AColors;
  FActive := AActive;
  if not ALite then
    LoadShellIcon
  else
    FIcon.Bitmap.SetSize(0, 0);
  Title := TileTitle(AInfo);
  if FTitle.Text <> Title then
    FTitle.Text := Title;
  if AInfo.Ready and (AInfo.TotalBytes > 0) then
  begin
    Used := AInfo.TotalBytes - AInfo.FreeBytes;
    if Used < 0 then
      Used := 0;
    Usage := FormatDriveUsage(Used, AInfo.TotalBytes);
  end
  else if AInfo.Kind = dkNetHood then
    Usage := 'Окружение'
  else if AInfo.Kind = dkDevice then
    Usage := 'Устройство'
  else if ALite then
    Usage := ''
  else
    Usage := 'Нет данных';
  if FUsage.Text <> Usage then
    FUsage.Text := Usage;
  FTrack.Visible := AInfo.Ready and (AInfo.TotalBytes > 0);
  NewHint := AInfo.Letter + ' ' + KindCaption(AInfo.Kind) + ' — ' + Usage;
  if Hint <> NewHint then
    Hint := NewHint;
  ShowHint := True;
  ApplyVisual;
  UpdateBar;
end;

procedure TDriveTile.LoadShellIcon;
var
  Bmp: FMX.Graphics.TBitmap;
begin
  if IsRemotePath(FInfo.Root) or (FInfo.Kind = dkNetwork) then
  begin
    FIcon.Bitmap.SetSize(0, 0);
    Exit;
  end;
  Bmp := nil;
  try
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
  Dummy: DWORD;
  Title: string;
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
  if IsRemotePath(FInfo.Root) then
  begin
    FInfo.Kind := dkNetwork;
    RefreshSpace;
    Exit;
  end;
  FillChar(LabelBuf, SizeOf(LabelBuf), 0);
  if GetVolumeInformation(PChar(FInfo.Root), LabelBuf, Length(LabelBuf),
    nil, Dummy, Dummy, nil, 0) and (LabelBuf[0] <> #0) then
    FInfo.VolumeName := string(LabelBuf);
  Title := TileTitle(FInfo);
  if FTitle.Text <> Title then
    FTitle.Text := Title;
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
  if IsRemotePath(FInfo.Root) or (FInfo.Kind = dkNetwork) then
  begin
    if FUsage.Text = '' then
      FUsage.Text := '…';
    FTrack.Visible := False;
    Exit;
  end;
  if not GetDiskFreeSpaceEx(PChar(FInfo.Root), FreeForCaller, Total, @TotalFree) then
    Exit;
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
  ApplyVisual;
  UpdateBar;
end;
{$ELSE}
begin
end;
{$ENDIF}

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
  X: Single;
begin
  X := 0;
  for I := 0 to FTiles.Count - 1 do
  begin
    FTiles[I].SetBounds(X, 0, TILE_W, TILE_H);
    X := X + TILE_W + TILE_GAP;
  end;
  if X > 0 then
    X := X - TILE_GAP;
  FHost.Width := Max(X, 1);
  FHost.Height := TILE_H;
  UpdateNavButtons;
end;

procedure TDriveBar.ApplyActive;
var
  I: Integer;
  Root: string;
begin
  Root := FActiveRoot;
  for I := 0 to FTiles.Count - 1 do
    case FTiles[I].Info.Kind of
      dkNetHood:
        FTiles[I].SetActive(StartsText('\\', Root) or
          SameText(Root, FTiles[I].Info.Root) or SameText(Root, 'Network'));
      dkDevice:
        FTiles[I].SetActive(SameText(Root, FTiles[I].Info.Root) or
          StartsText(FTiles[I].Info.Root, Root));
    else
      if IsVirtualShellPath(Root) or IsPortableDevicePath(Root) then
        FTiles[I].SetActive(False)
      else
        FTiles[I].SetActive(SameText(FTiles[I].Info.Root,
          IncludeTrailingPathDelimiter(ExtractFileDrive(Root))));
    end;
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
    Net.Root := '\\';
    Net.VolumeName := 'Сеть';
    Net.Ready := True;
    Tile := TDriveTile.Create(FHost);
    Tile.Parent := FHost;
    Tile.OnClick := TileClick;
    Tile.OnContext := TileContext;
    Tile.OnMouseWheel := BarMouseWheel;
    Tile.Bind(Net, FColors, False, True);
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
      if SameText(Tile.Info.Root, Places[I].Root) or
         SameText(ExcludeTrailingPathDelimiter(Tile.Info.Root),
           ExcludeTrailingPathDelimiter(Places[I].Root)) then
      begin
        Have := True;
        Break;
      end;
    if Have then
      Continue;
    Tile := TDriveTile.Create(FHost);
    Tile.Parent := FHost;
    Tile.OnClick := TileClick;
    Tile.OnContext := TileContext;
    Tile.OnMouseWheel := BarMouseWheel;
    Tile.Bind(Places[I], FColors, False, True);
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

procedure TDriveBar.SetActivePath(const APath: string);
begin
  FActiveRoot := APath;
  ApplyActive;
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

end.
