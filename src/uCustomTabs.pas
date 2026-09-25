unit uCustomTabs;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Layouts, FMX.Graphics, FMX.StdCtrls,
  uAppSettings, uThemeManager;

type
  TTabCloseEvent = procedure(Sender: TObject; AIndex: Integer; var ACanClose: Boolean) of object;
  TTabChangeEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TTabReorderEvent = procedure(Sender: TObject; AFromIndex, AToIndex: Integer) of object;
  TTabDragQueryEvent = procedure(Sender: TObject; AIndex: Integer; var APath: string) of object;

  TCustomTabsBar = class
  private
    FContainer: TRectangle;
    FScrollBox: THorzScrollBox;
    FTabsLayout: TLayout;
    FNavCluster: TLayout;
    FAddButton: TRectangle;
    FAddLabel: TLabel;
    FBtnPrev: TRectangle;
    FBtnNext: TRectangle;
    FPrevLabel: TLabel;
    FNextLabel: TLabel;
    FDropLine: TRectangle;

    FTitles: TStringList;
    FIconPaths: TStringList;
    FDataList: TList;
    FActiveIndex: Integer;
    FHoverIndex: Integer;
    FThemeColors: TThemeColors;
    FIgnoreClick: Boolean;
    FShowIcons: Boolean;
    FShellIconsReady: Boolean;
    FEqualWidth: Boolean;
    FInLayout: Boolean;

    FOnTabChange: TTabChangeEvent;
    FOnTabClose: TTabCloseEvent;
    FOnTabAdd: TProc;
    FOnTabReorder: TTabReorderEvent;
    FOnTabDragQuery: TTabDragQueryEvent;
    FBusy: TList<Boolean>;
    FBusyTimer: TTimer;
    FBusyFrame: Integer;

    procedure RebuildTabs;
    procedure BusyTick(Sender: TObject);
    procedure PaintTabSpinner(Sender: TObject; Canvas: TCanvas);
    procedure UpdateLayoutSizes;
    procedure UpdateNavButtons;
    procedure TabClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure PrevClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure TabMouseEnter(Sender: TObject);
    procedure TabMouseLeave(Sender: TObject);
    procedure CloseMouseEnter(Sender: TObject);
    procedure CloseMouseLeave(Sender: TObject);
    procedure AddMouseEnter(Sender: TObject);
    procedure AddMouseLeave(Sender: TObject);
    procedure NavMouseEnter(Sender: TObject);
    procedure NavMouseLeave(Sender: TObject);
    procedure ApplyTabColors(ATabRect: TRectangle; AIsActive, AIsHover: Boolean);
    procedure TabsMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure ScrollBoxResize(Sender: TObject);
    procedure ContainerResize(Sender: TObject);
    procedure ScrollBoxApplyStyle(Sender: TObject);
    procedure LayoutChrome;
    procedure ScrollByDelta(ADelta: Single);
    function MakeNavButton(AParent: TFmxObject; const ACaption: string;
      AOnClick: TNotifyEvent; out ALabel: TLabel): TRectangle;
  public
    constructor Create(AParent: TFmxObject);
    destructor Destroy; override;

    function AddTab(const ATitle: string; AData: Pointer = nil;
      const AIconPath: string = ''; ASelect: Boolean = True): Integer;
    procedure RemoveTab(AIndex: Integer);
    procedure SelectTab(AIndex: Integer);
    procedure MoveTab(AFromIndex, AInsertBefore: Integer);
    procedure SetTabTitle(AIndex: Integer; const ATitle: string);
    procedure SetTabIconPath(AIndex: Integer; const AIconPath: string);
    procedure SetTabInfo(AIndex: Integer; const ATitle, AIconPath: string);
    function GetTabData(AIndex: Integer): Pointer;
    procedure SetTabData(AIndex: Integer; AData: Pointer);
    function TabCount: Integer;
    function HitInsertIndex(const AAbsPoint: TPointF): Integer;
    procedure ShowDropHint(AInsertBefore: Integer);
    procedure HideDropHint;
    procedure BeginTabDrag(AIndex: Integer; AControl: TControl);
    procedure NotifyDragEnded;

    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SetTabChrome(AShowIcons, AEqualWidth: Boolean);
    procedure AllowShellIcons;
    procedure SetTabBusy(AIndex: Integer; ABusy: Boolean);

    property ActiveIndex: Integer read FActiveIndex write SelectTab;
    property Container: TRectangle read FContainer;
    property OnTabChange: TTabChangeEvent read FOnTabChange write FOnTabChange;
    property OnTabClose: TTabCloseEvent read FOnTabClose write FOnTabClose;
    property OnTabAdd: TProc read FOnTabAdd write FOnTabAdd;
    property OnTabReorder: TTabReorderEvent read FOnTabReorder write FOnTabReorder;
    property OnTabDragQuery: TTabDragQueryEvent read FOnTabDragQuery write FOnTabDragQuery;
  end;

function IsTabDragActive: Boolean;
function TabDragSourceIs(ABar: TCustomTabsBar): Boolean;
function TabDragSourceBar: TCustomTabsBar;
function TabDragSourceIndex: Integer;
function TabDragPath: string;
procedure ClearTabDrag;

implementation

uses
  System.Math, FMX.Controls.Presentation, FMX.TextLayout, UCoreEngine, uFileModel;

const
  TAB_WIDTH = 156;
  TAB_GAP = 4;
  TAB_DRAG_THRESHOLD = 8;

function MeasureTabText(const AText: string): Single;
var
  L: TTextLayout;
begin
  L := TTextLayoutManager.DefaultTextLayout.Create;
  try
    L.BeginUpdate;
    try
      L.Font.Family := FluentFontFamily;
      L.Font.Size := 12;
      L.WordWrap := False;
      L.Text := AText;
    finally
      L.EndUpdate;
    end;
    Result := Ceil(L.TextWidth);
  finally
    L.Free;
  end;
end;

type
  TTabDragInfo = record
    Active: Boolean;
    SourceBar: TCustomTabsBar;
    SourceIndex: Integer;
    Path: string;
    Title: string;
  end;

  TTabChrome = class(TRectangle)
  private
    FBar: TCustomTabsBar;
    FPressed: Boolean;
    FDragged: Boolean;
    FDownPt: TPointF;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure DragEnd; override;
  end;

var
  GTabDrag: TTabDragInfo;

function IsTabDragActive: Boolean;
begin
  Result := GTabDrag.Active;
end;

function TabDragSourceIs(ABar: TCustomTabsBar): Boolean;
begin
  Result := GTabDrag.Active and (GTabDrag.SourceBar = ABar);
end;

function TabDragSourceBar: TCustomTabsBar;
begin
  Result := GTabDrag.SourceBar;
end;

function TabDragSourceIndex: Integer;
begin
  Result := GTabDrag.SourceIndex;
end;

function TabDragPath: string;
begin
  Result := GTabDrag.Path;
end;

procedure ClearTabDrag;
begin
  GTabDrag.Active := False;
  GTabDrag.SourceBar := nil;
  GTabDrag.SourceIndex := -1;
  GTabDrag.Path := '';
  GTabDrag.Title := '';
end;

procedure TTabChrome.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    FPressed := True;
    FDragged := False;
    FDownPt := TPointF.Create(X, Y);
    if Assigned(FBar) then
      FBar.FIgnoreClick := False;
  end;
end;

procedure TTabChrome.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FPressed and not FDragged and Assigned(FBar) and (ssLeft in Shift) then
    if (Abs(X - FDownPt.X) >= TAB_DRAG_THRESHOLD) or
       (Abs(Y - FDownPt.Y) >= TAB_DRAG_THRESHOLD) then
    begin
      FDragged := True;
      FPressed := False;
      FBar.FIgnoreClick := True;
      FBar.BeginTabDrag(Tag, Self);
      if IsTabDragActive then
        BeginAutoDrag;
    end;
end;

procedure TTabChrome.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FPressed := False;
end;

procedure TTabChrome.DragEnd;
begin
  inherited;
  if Assigned(FBar) then
    FBar.NotifyDragEnded;
end;

function TCustomTabsBar.MakeNavButton(AParent: TFmxObject; const ACaption: string;
  AOnClick: TNotifyEvent; out ALabel: TLabel): TRectangle;
begin
  Result := TRectangle.Create(FContainer);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Left;
  Result.Width := 26;
  Result.Margins.Rect := TRectF.Create(2, 4, 0, 4);
  Result.XRadius := 6;
  Result.YRadius := 6;
  Result.Stroke.Kind := TBrushKind.None;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.HitTest := True;
  Result.Cursor := crHandPoint;
  Result.OnClick := AOnClick;
  Result.OnMouseEnter := NavMouseEnter;
  Result.OnMouseLeave := NavMouseLeave;

  ALabel := TLabel.Create(Result);
  ALabel.Parent := Result;
  ALabel.Align := TAlignLayout.Client;
  ALabel.Text := ACaption;
  ALabel.TextAlign := TTextAlign.Center;
  ALabel.TextSettings.Font.Family := FluentFontFamily;
  ALabel.TextSettings.Font.Size := 14;
  ALabel.StyledSettings := ALabel.StyledSettings -
    [TStyledSetting.Family, TStyledSetting.Size, TStyledSetting.FontColor];
  ALabel.HitTest := False;
end;

constructor TCustomTabsBar.Create(AParent: TFmxObject);
begin
  inherited Create;
  FTitles := TStringList.Create;
  FIconPaths := TStringList.Create;
  FDataList := TList.Create;
  FBusy := TList<Boolean>.Create;
  FBusyFrame := 0;
  FBusyTimer := TTimer.Create(nil);
  FBusyTimer.Interval := 70;
  FBusyTimer.Enabled := False;
  FBusyTimer.OnTimer := BusyTick;
  FActiveIndex := -1;
  FHoverIndex := -1;
  FIgnoreClick := False;
  FShowIcons := True;
  FShellIconsReady := False;
  FEqualWidth := True;
  FInLayout := False;
  FThemeColors := GetThemeColors(atSystem);

  FContainer := TRectangle.Create(nil);
  FContainer.Parent := AParent;
  FContainer.Align := TAlignLayout.Top;
  FContainer.Height := 34;
  FContainer.Stroke.Kind := TBrushKind.None;
  FContainer.Fill.Kind := TBrushKind.Solid;
  FContainer.Fill.Color := TAlphaColors.Null;
  FContainer.OnMouseWheel := TabsMouseWheel;
  FContainer.OnResize := ContainerResize;

  FNavCluster := TLayout.Create(FContainer);
  FNavCluster.Parent := FContainer;
  FNavCluster.Align := TAlignLayout.None;
  FNavCluster.Width := 56;
  FNavCluster.Height := 34;
  FNavCluster.Visible := False;


      FBtnPrev := MakeNavButton(FNavCluster, '‹', PrevClick, FPrevLabel);
  FBtnPrev.Visible := False;
  FBtnNext := MakeNavButton(FNavCluster, '›', NextClick, FNextLabel);
  FBtnNext.Visible := False;


  FAddButton := TRectangle.Create(FContainer);
  FAddButton.Parent := FContainer;
  FAddButton.Align := TAlignLayout.None;
  FAddButton.Width := 28;
  FAddButton.Height := 26;
  FAddButton.Position.Point := TPointF.Create(0, 4);
  FAddButton.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FAddButton.XRadius := 14;
  FAddButton.YRadius := 14;
  FAddButton.Stroke.Kind := TBrushKind.None;
  FAddButton.Fill.Kind := TBrushKind.Solid;
  FAddButton.HitTest := True;
  FAddButton.Cursor := crHandPoint;
  FAddButton.OnClick := AddClick;
  FAddButton.OnMouseEnter := AddMouseEnter;
  FAddButton.OnMouseLeave := AddMouseLeave;
  FAddButton.Hint := 'Новая вкладка';
  FAddButton.ShowHint := True;

  FAddLabel := TLabel.Create(FAddButton);
  FAddLabel.Parent := FAddButton;
  FAddLabel.Align := TAlignLayout.Client;
  FAddLabel.Text := '';
  FAddLabel.TextAlign := TTextAlign.Center;
  FAddLabel.TextSettings.Font.Family := FluentIconFamily;
  FAddLabel.TextSettings.Font.Size := 14;
  FAddLabel.StyledSettings := FAddLabel.StyledSettings -
    [TStyledSetting.Family, TStyledSetting.Size, TStyledSetting.FontColor];
  FAddLabel.HitTest := False;

  FScrollBox := THorzScrollBox.Create(FContainer);
  FScrollBox.Parent := FContainer;
  FScrollBox.Align := TAlignLayout.Client;
  FScrollBox.ShowScrollBars := False;
  FScrollBox.Margins.Rect := TRectF.Create(6, 0, 36, 0);
  FScrollBox.OnMouseWheel := TabsMouseWheel;
  FScrollBox.OnResize := ScrollBoxResize;
  FScrollBox.OnApplyStyleLookup := ScrollBoxApplyStyle;
  FScrollBox.AniCalculations.Animation := False;
  FScrollBox.ApplyStyleLookup;
  ScrollBoxApplyStyle(FScrollBox);

  FTabsLayout := TLayout.Create(FScrollBox);
  FTabsLayout.Parent := FScrollBox;
  FTabsLayout.Align := TAlignLayout.Left;
  FTabsLayout.Height := 34;
  FTabsLayout.OnMouseWheel := TabsMouseWheel;

  ApplyTheme(FThemeColors);
end;

destructor TCustomTabsBar.Destroy;
begin
  if Assigned(FBusyTimer) then
    FBusyTimer.Enabled := False;
  FreeAndNil(FBusyTimer);
  FreeAndNil(FBusy);
  FTitles.Free;
  FIconPaths.Free;
  FDataList.Free;
  if Assigned(FContainer) and (FContainer.Owner = nil) then
    FContainer.Free;
  inherited;
end;

procedure TCustomTabsBar.ApplyTabColors(ATabRect: TRectangle; AIsActive, AIsHover: Boolean);
var
  J, K: Integer;
  Child: TControl;
  CloseBtn: TRectangle;
begin
  if AIsActive then
    ATabRect.Fill.Color := FThemeColors.HeaderBackground
  else if AIsHover then
    ATabRect.Fill.Color := BlendColors(FThemeColors.HeaderBackground,
      FThemeColors.Background, 0.28)
  else
    ATabRect.Fill.Color := BlendColors(FThemeColors.HeaderBackground,
      FThemeColors.Background, 0.5);

  for J := 0 to ATabRect.ControlsCount - 1 do
  begin
    Child := ATabRect.Controls[J];
    if Child is TLabel then
    begin
      if AIsActive then
        TLabel(Child).TextSettings.FontColor := FThemeColors.TextColor
      else
        TLabel(Child).TextSettings.FontColor := FThemeColors.SubTextColor;
    end
    else if Child is TImage then
    begin
      if AIsActive then
      begin
        TImage(Child).Width := 22;
        TImage(Child).Margins.Rect := TRectF.Create(8, 4, 2, 4);
      end
      else
      begin
        TImage(Child).Width := 14;
        TImage(Child).Margins.Rect := TRectF.Create(10, 8, 2, 8);
      end;
    end
    else if Child is TRectangle then
    begin
      if TRectangle(Child).Align = TAlignLayout.Right then
      begin
        CloseBtn := TRectangle(Child);
        CloseBtn.Fill.Color := TAlphaColors.Null;
        for K := 0 to CloseBtn.ControlsCount - 1 do
          if CloseBtn.Controls[K] is TLabel then
            TLabel(CloseBtn.Controls[K]).TextSettings.FontColor := FThemeColors.SubTextColor;
      end;
    end;
  end;
end;

procedure TCustomTabsBar.SetTabChrome(AShowIcons, AEqualWidth: Boolean);
begin
  if (FShowIcons = AShowIcons) and (FEqualWidth = AEqualWidth) then
    Exit;
  FShowIcons := AShowIcons;
  FEqualWidth := AEqualWidth;
  RebuildTabs;
end;

procedure TCustomTabsBar.BusyTick(Sender: TObject);
var
  I: Integer;
  Any: Boolean;
  C: TFmxObject;
  P: TPaintBox;
begin
  Any := False;
  for I := 0 to FBusy.Count - 1 do
    if FBusy[I] then
    begin
      Any := True;
      Break;
    end;
  if not Any then
  begin
    FBusyTimer.Enabled := False;
    Exit;
  end;
  FBusyFrame := (FBusyFrame + 1) mod 8;
  if not Assigned(FTabsLayout) then
    Exit;
  for I := 0 to FTabsLayout.ControlsCount - 1 do
  begin
    C := FTabsLayout.Controls[I];
    if C is TTabChrome then
    begin
      for var J := 0 to TTabChrome(C).ControlsCount - 1 do
        if (TTabChrome(C).Controls[J] is TPaintBox) and
           (TTabChrome(C).Controls[J].Tag = 1001) then
        begin
          P := TPaintBox(TTabChrome(C).Controls[J]);
          P.Repaint;
        end;
    end;
  end;
end;

procedure TCustomTabsBar.PaintTabSpinner(Sender: TObject; Canvas: TCanvas);
var
  Box: TPaintBox;
  C: TPointF;
  I: Integer;
  Ang, R, DotR: Single;
  P: TPointF;
  Dist: Integer;
  Alpha: Byte;
begin
  if not (Sender is TPaintBox) then
    Exit;
  Box := TPaintBox(Sender);
  C := TPointF.Create(Box.Width * 0.5, Box.Height * 0.5);
  R := Min(Box.Width, Box.Height) * 0.32;
  DotR := Max(1.2, R * 0.22);
  Canvas.Fill.Kind := TBrushKind.Solid;
  for I := 0 to 7 do
  begin
    Ang := (I / 8) * Pi * 2 - Pi / 2;
    Dist := (I - FBusyFrame + 8) mod 8;
    Alpha := 40 + Dist * 26;
    if Alpha > 220 then
      Alpha := 220;
    P := TPointF.Create(C.X + Cos(Ang) * R, C.Y + Sin(Ang) * R);
    Canvas.Fill.Color := TAlphaColor(Cardinal(Alpha) shl 24 or $FFFFFF);
    Canvas.FillEllipse(TRectF.Create(P.X - DotR, P.Y - DotR, P.X + DotR, P.Y + DotR), 1);
  end;
end;

procedure TCustomTabsBar.SetTabBusy(AIndex: Integer; ABusy: Boolean);
var
  Any: Boolean;
  I: Integer;
begin
  if (AIndex < 0) or (AIndex >= FBusy.Count) then
    Exit;
  if FBusy[AIndex] = ABusy then
    Exit;
  FBusy[AIndex] := ABusy;
  RebuildTabs;
  Any := False;
  for I := 0 to FBusy.Count - 1 do
    if FBusy[I] then
    begin
      Any := True;
      Break;
    end;
  FBusyTimer.Enabled := Any;
end;

procedure TCustomTabsBar.AllowShellIcons;
begin
  if FShellIconsReady then
    Exit;
  FShellIconsReady := True;
  if FShowIcons and (FTitles.Count > 0) then
    RebuildTabs;
end;

procedure TCustomTabsBar.ApplyTheme(const AColors: TThemeColors);
var
  I: Integer;
  TabRect: TRectangle;
begin
  FThemeColors := AColors;
  FContainer.Fill.Kind := TBrushKind.Solid;
  FContainer.Fill.Color := TAlphaColors.Null;
  FAddButton.Fill.Color := FThemeColors.ControlFill;
  FAddLabel.TextSettings.FontColor := FThemeColors.TextColor;
  if Assigned(FBtnPrev) then
    FBtnPrev.Fill.Color := FThemeColors.ControlFill;
  if Assigned(FBtnNext) then
    FBtnNext.Fill.Color := FThemeColors.ControlFill;
  if Assigned(FPrevLabel) then
    FPrevLabel.TextSettings.FontColor := FThemeColors.TextColor;
  if Assigned(FNextLabel) then
    FNextLabel.TextSettings.FontColor := FThemeColors.TextColor;

  for I := 0 to FTabsLayout.ControlsCount - 1 do
    if FTabsLayout.Controls[I] is TRectangle then
    begin
      TabRect := TRectangle(FTabsLayout.Controls[I]);
      ApplyTabColors(TabRect, I = FActiveIndex, I = FHoverIndex);
    end;
  UpdateNavButtons;
end;

function TCustomTabsBar.TabCount: Integer;
begin
  Result := FTitles.Count;
end;

function TCustomTabsBar.AddTab(const ATitle: string; AData: Pointer;
  const AIconPath: string; ASelect: Boolean): Integer;
begin
  FTitles.Add(ATitle);
  FIconPaths.Add(AIconPath);
  FDataList.Add(AData);
  FBusy.Add(False);
  Result := FTitles.Count - 1;
  RebuildTabs;
  if ASelect then
    SelectTab(Result);
end;

procedure TCustomTabsBar.RemoveTab(AIndex: Integer);
var
  CanClose, DeletedActive: Boolean;
begin
  if (AIndex < 0) or (AIndex >= FTitles.Count) then Exit;

  CanClose := True;
  if Assigned(FOnTabClose) then
    FOnTabClose(Self, AIndex, CanClose);

  if not CanClose then Exit;

  DeletedActive := AIndex = FActiveIndex;
  FTitles.Delete(AIndex);
  FIconPaths.Delete(AIndex);
  FDataList.Delete(AIndex);
  if (AIndex >= 0) and (AIndex < FBusy.Count) then
    FBusy.Delete(AIndex);

  if DeletedActive then
  begin
    if FActiveIndex >= FTitles.Count then
      FActiveIndex := FTitles.Count - 1;
  end
  else if AIndex < FActiveIndex then
    Dec(FActiveIndex);

  RebuildTabs;
  if FActiveIndex >= 0 then
    SelectTab(FActiveIndex)
  else if Assigned(FOnTabChange) then
    FOnTabChange(Self, -1);
end;

procedure TCustomTabsBar.SelectTab(AIndex: Integer);
begin
  if FTitles.Count = 0 then
  begin
    FActiveIndex := -1;
    Exit;
  end;

  if AIndex < 0 then AIndex := 0;
  if AIndex >= FTitles.Count then AIndex := FTitles.Count - 1;

  FActiveIndex := AIndex;
  RebuildTabs;

  if Assigned(FOnTabChange) then
    FOnTabChange(Self, FActiveIndex);
end;

procedure TCustomTabsBar.SetTabTitle(AIndex: Integer; const ATitle: string);
begin
  if (AIndex >= 0) and (AIndex < FTitles.Count) then
  begin
    FTitles[AIndex] := ATitle;
    RebuildTabs;
  end;
end;

procedure TCustomTabsBar.SetTabIconPath(AIndex: Integer; const AIconPath: string);
begin
  if (AIndex >= 0) and (AIndex < FIconPaths.Count) then
  begin
    FIconPaths[AIndex] := AIconPath;
    RebuildTabs;
  end;
end;

procedure TCustomTabsBar.SetTabInfo(AIndex: Integer; const ATitle, AIconPath: string);
begin
  if (AIndex < 0) or (AIndex >= FTitles.Count) then
    Exit;
  FTitles[AIndex] := ATitle;
  if AIndex < FIconPaths.Count then
    FIconPaths[AIndex] := AIconPath;
  RebuildTabs;
end;

function TCustomTabsBar.GetTabData(AIndex: Integer): Pointer;
begin
  if (AIndex >= 0) and (AIndex < FDataList.Count) then
    Result := FDataList[AIndex]
  else
    Result := nil;
end;

procedure TCustomTabsBar.SetTabData(AIndex: Integer; AData: Pointer);
begin
  if (AIndex >= 0) and (AIndex < FDataList.Count) then
    FDataList[AIndex] := AData;
end;

procedure TCustomTabsBar.MoveTab(AFromIndex, AInsertBefore: Integer);
var
  NewIdx: Integer;
  Title, Icon: string;
  Data: Pointer;
begin
  if (AFromIndex < 0) or (AFromIndex >= FTitles.Count) then
    Exit;
  if AInsertBefore < 0 then
    AInsertBefore := 0;
  if AInsertBefore > FTitles.Count then
    AInsertBefore := FTitles.Count;

  NewIdx := AInsertBefore;
  if AInsertBefore > AFromIndex then
    Dec(NewIdx);
  if (NewIdx = AFromIndex) or (NewIdx < 0) or (NewIdx >= FTitles.Count) then
    Exit;

  Title := FTitles[AFromIndex];
  Icon := FIconPaths[AFromIndex];
  Data := FDataList[AFromIndex];
  FTitles.Delete(AFromIndex);
  FIconPaths.Delete(AFromIndex);
  FDataList.Delete(AFromIndex);
  FTitles.Insert(NewIdx, Title);
  FIconPaths.Insert(NewIdx, Icon);
  FDataList.Insert(NewIdx, Data);
  if (AFromIndex >= 0) and (AFromIndex < FBusy.Count) then
  begin
    var BusyFlag := FBusy[AFromIndex];
    FBusy.Delete(AFromIndex);
    if NewIdx > FBusy.Count then
      FBusy.Add(BusyFlag)
    else
      FBusy.Insert(NewIdx, BusyFlag);
  end;

  if FActiveIndex = AFromIndex then
    FActiveIndex := NewIdx
  else
  begin
    if AFromIndex < FActiveIndex then
      Dec(FActiveIndex);
    if NewIdx <= FActiveIndex then
      Inc(FActiveIndex);
  end;

  RebuildTabs;
  if Assigned(FOnTabReorder) then
    FOnTabReorder(Self, AFromIndex, NewIdx);
end;

function TCustomTabsBar.HitInsertIndex(const AAbsPoint: TPointF): Integer;
var
  I: Integer;
  R: TRectF;
begin
  Result := FTitles.Count;
  for I := 0 to FTabsLayout.ControlsCount - 1 do
    if FTabsLayout.Controls[I] is TTabChrome then
    begin
      R := FTabsLayout.Controls[I].AbsoluteRect;
      if AAbsPoint.X < (R.Left + R.Right) * 0.5 then
        Exit(I);
    end;
end;

procedure TCustomTabsBar.ShowDropHint(AInsertBefore: Integer);
var
  X: Single;
  C: TControl;
  Local: TPointF;
begin
  if not Assigned(FContainer) then
    Exit;
  if FDropLine = nil then
  begin
    FDropLine := TRectangle.Create(FContainer);
    FDropLine.Parent := FContainer;
    FDropLine.Align := TAlignLayout.None;
    FDropLine.Width := 3;
    FDropLine.HitTest := False;
    FDropLine.Stroke.Kind := TBrushKind.None;
    FDropLine.Fill.Kind := TBrushKind.Solid;
    FDropLine.XRadius := 1;
    FDropLine.YRadius := 1;
  end;
  FDropLine.Fill.Color := FThemeColors.SelectionColor;
  FDropLine.Visible := True;
  FDropLine.BringToFront;

  X := 6;
  if (AInsertBefore >= 0) and (AInsertBefore < FTabsLayout.ControlsCount) then
    X := FTabsLayout.Controls[AInsertBefore].Position.X
  else if FTabsLayout.ControlsCount > 0 then
  begin
    C := FTabsLayout.Controls[FTabsLayout.ControlsCount - 1];
    X := C.Position.X + C.Width;
  end;

  Local := FContainer.AbsoluteToLocal(FTabsLayout.LocalToAbsolute(TPointF.Create(X, 0)));
  FDropLine.SetBounds(Local.X - 1, 5, 3, FContainer.Height - 8);
end;

procedure TCustomTabsBar.HideDropHint;
begin
  if Assigned(FDropLine) then
    FDropLine.Visible := False;
end;

procedure TCustomTabsBar.BeginTabDrag(AIndex: Integer; AControl: TControl);
var
  Path: string;
begin
  if (AIndex < 0) or (AIndex >= FTitles.Count) or (AControl = nil) then
    Exit;

  Path := '';
  if AIndex < FIconPaths.Count then
    Path := FIconPaths[AIndex];
  if Assigned(FOnTabDragQuery) then
    FOnTabDragQuery(Self, AIndex, Path);
  if Path = '' then
    Exit;

  GTabDrag.Active := True;
  GTabDrag.SourceBar := Self;
  GTabDrag.SourceIndex := AIndex;
  GTabDrag.Path := Path;
  GTabDrag.Title := FTitles[AIndex];
end;

procedure TCustomTabsBar.NotifyDragEnded;
begin
  HideDropHint;
  if GTabDrag.Active and (GTabDrag.SourceBar = Self) then
    ClearTabDrag;
end;

procedure TCustomTabsBar.TabClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FIgnoreClick then
  begin
    FIgnoreClick := False;
    Exit;
  end;
  if Sender is TComponent then
  begin
    Idx := TComponent(Sender).Tag;
    SelectTab(Idx);
  end;
end;

procedure TCustomTabsBar.CloseClick(Sender: TObject);
var
  Idx: Integer;
begin
  if Sender is TComponent then
  begin
    Idx := TComponent(Sender).Tag;
    RemoveTab(Idx);
  end;
end;

procedure TCustomTabsBar.AddClick(Sender: TObject);
begin
  if Assigned(FOnTabAdd) then
    FOnTabAdd();
end;

procedure TCustomTabsBar.PrevClick(Sender: TObject);
begin
  ScrollByDelta(-160);
end;

procedure TCustomTabsBar.NextClick(Sender: TObject);
begin
  ScrollByDelta(160);
end;

procedure TCustomTabsBar.ScrollByDelta(ADelta: Single);
var
  MaxX, NewX: Single;
begin
  if not Assigned(FScrollBox) then Exit;
  MaxX := Max(0, FTabsLayout.Width - FScrollBox.Width);
  NewX := EnsureRange(FScrollBox.ViewportPosition.X + ADelta, 0, MaxX);
  FScrollBox.ViewportPosition := TPointF.Create(NewX, 0);
  UpdateNavButtons;
end;

procedure TCustomTabsBar.TabsMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  if WheelDelta > 0 then
    ScrollByDelta(-120)
  else
    ScrollByDelta(120);
  Handled := True;
end;

procedure TCustomTabsBar.ScrollBoxResize(Sender: TObject);
begin
  UpdateLayoutSizes;
  UpdateNavButtons;
end;

procedure TCustomTabsBar.ContainerResize(Sender: TObject);
begin
  UpdateLayoutSizes;
  UpdateNavButtons;
end;

procedure TCustomTabsBar.ScrollBoxApplyStyle(Sender: TObject);
var
  Obj: TFmxObject;
begin
  if FScrollBox = nil then
    Exit;
  Obj := FScrollBox.FindStyleResource('background');
  if Obj is TRectangle then
  begin
    TRectangle(Obj).Fill.Kind := TBrushKind.None;
    TRectangle(Obj).Stroke.Kind := TBrushKind.None;
  end;
end;

procedure TCustomTabsBar.LayoutChrome;
var
  W, AddSlot, ClusterW: Single;
  Overflow: Boolean;
begin
  if not Assigned(FContainer) or not Assigned(FAddButton) then
    Exit;
  W := FContainer.Width;
  if W < 40 then
    Exit;
  AddSlot := 36;
  Overflow := Assigned(FTabsLayout) and Assigned(FScrollBox) and
    (FTabsLayout.Width > (W - AddSlot - 8) + 2);
  FAddButton.Position.Point := TPointF.Create(W - 32, 4);
  FAddButton.Height := Max(20, FContainer.Height - 8);
  if Overflow then
  begin
    ClusterW := 56;
    FNavCluster.Visible := True;
    FNavCluster.Width := ClusterW;
    FNavCluster.Height := FContainer.Height;
    FNavCluster.Position.Point := TPointF.Create(W - AddSlot - ClusterW, 0);
    FBtnPrev.Visible := True;
    FBtnNext.Visible := True;
    FScrollBox.Margins.Right := AddSlot + ClusterW;
  end
  else
  begin
    FNavCluster.Visible := False;
    FBtnPrev.Visible := False;
    FBtnNext.Visible := False;
    FScrollBox.Margins.Right := AddSlot;
  end;
end;

procedure TCustomTabsBar.AddMouseEnter(Sender: TObject);
begin
  FAddButton.Fill.Color := FThemeColors.ControlFillHover;
end;

procedure TCustomTabsBar.AddMouseLeave(Sender: TObject);
begin
  FAddButton.Fill.Color := FThemeColors.ControlFill;
end;

procedure TCustomTabsBar.NavMouseEnter(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FThemeColors.ControlFillHover;
end;

procedure TCustomTabsBar.NavMouseLeave(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FThemeColors.ControlFill;
end;

procedure TCustomTabsBar.TabMouseEnter(Sender: TObject);
begin
  if Sender is TComponent then
  begin
    FHoverIndex := TComponent(Sender).Tag;
    if (FHoverIndex >= 0) and (FHoverIndex < FTabsLayout.ControlsCount) and
       (FTabsLayout.Controls[FHoverIndex] is TRectangle) then
      ApplyTabColors(TRectangle(FTabsLayout.Controls[FHoverIndex]),
        FHoverIndex = FActiveIndex, True);
  end;
end;

procedure TCustomTabsBar.TabMouseLeave(Sender: TObject);
var
  Idx: Integer;
begin
  if Sender is TComponent then
  begin
    Idx := TComponent(Sender).Tag;
    if FHoverIndex = Idx then
      FHoverIndex := -1;
    if (Idx >= 0) and (Idx < FTabsLayout.ControlsCount) and
       (FTabsLayout.Controls[Idx] is TRectangle) then
      ApplyTabColors(TRectangle(FTabsLayout.Controls[Idx]),
        Idx = FActiveIndex, False);
  end;
end;

procedure TCustomTabsBar.CloseMouseEnter(Sender: TObject);
var
  CloseBtn: TRectangle;
  K: Integer;
begin
  if Sender is TRectangle then
  begin
    CloseBtn := TRectangle(Sender);
    CloseBtn.Fill.Color := FThemeColors.DangerColor;
    for K := 0 to CloseBtn.ControlsCount - 1 do
      if CloseBtn.Controls[K] is TLabel then
        TLabel(CloseBtn.Controls[K]).TextSettings.FontColor := TAlphaColors.White;
  end;
end;

procedure TCustomTabsBar.CloseMouseLeave(Sender: TObject);
var
  CloseBtn: TRectangle;
  K: Integer;
begin
  if Sender is TRectangle then
  begin
    CloseBtn := TRectangle(Sender);
    CloseBtn.Fill.Color := TAlphaColors.Null;
    for K := 0 to CloseBtn.ControlsCount - 1 do
      if CloseBtn.Controls[K] is TLabel then
        TLabel(CloseBtn.Controls[K]).TextSettings.FontColor := FThemeColors.SubTextColor;
  end;
end;

procedure TCustomTabsBar.UpdateLayoutSizes;
var
  I: Integer;
  Right: Single;
begin
  Right := 0;
  for I := 0 to FTabsLayout.ControlsCount - 1 do
    Right := Max(Right, FTabsLayout.Controls[I].Position.X + FTabsLayout.Controls[I].Width);
  FTabsLayout.Width := Max(Right + 4, 1);
end;

procedure TCustomTabsBar.UpdateNavButtons;
var
  CanLeft, CanRight: Boolean;
  MaxX: Single;
begin
  if FInLayout or not Assigned(FScrollBox) or not Assigned(FNavCluster) then
    Exit;
  FInLayout := True;
  try
    LayoutChrome;
    if FNavCluster.Visible then
    begin
      MaxX := Max(0, FTabsLayout.Width - FScrollBox.Width);
      CanLeft := FScrollBox.ViewportPosition.X > 1;
      CanRight := FScrollBox.ViewportPosition.X < MaxX - 1;
      FBtnPrev.Opacity := IfThen(CanLeft, 1.0, 0.35);
      FBtnNext.Opacity := IfThen(CanRight, 1.0, 0.35);
      FBtnPrev.HitTest := CanLeft;
      FBtnNext.HitTest := CanRight;
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TCustomTabsBar.RebuildTabs;
var
  I: Integer;
  TabRect, CloseBtn: TRectangle;
  Lbl, CloseLbl: TLabel;
  IconImg: TImage;
  IconBmp: FMX.Graphics.TBitmap;
  ShowClose: Boolean;
begin
  while FTabsLayout.ControlsCount > 0 do
    FTabsLayout.Controls[0].Free;

  ShowClose := FTitles.Count > 1;

  var X := 0.0;
  for I := 0 to FTitles.Count - 1 do
  begin
    TabRect := TTabChrome.Create(FTabsLayout);
    TTabChrome(TabRect).FBar := Self;
    TabRect.Parent := FTabsLayout;
    TabRect.Align := TAlignLayout.None;
    var HasIcon := FShowIcons and FShellIconsReady and (I < FIconPaths.Count) and
      (FIconPaths[I] <> '');
    var TW: Single := TAB_WIDTH;
    if not FEqualWidth then
    begin
      TW := MeasureTabText(FTitles[I]) + 16;
      if ShowClose then
        TW := TW + 28;
      if HasIcon then
      begin
        if I = FActiveIndex then
          TW := TW + 36
        else
          TW := TW + 28;
      end;
      if TW < 72 then
        TW := 72;
      if TW > 280 then
        TW := 280;
    end;
    TabRect.SetBounds(X, 4, TW, Max(FTabsLayout.Height - 4, 26));
    X := X + TW + TAB_GAP;
    TabRect.XRadius := 8;
    TabRect.YRadius := 8;
    TabRect.Corners := [TCorner.TopLeft, TCorner.TopRight];
    TabRect.Stroke.Kind := TBrushKind.None;
    TabRect.Fill.Kind := TBrushKind.Solid;
    TabRect.Tag := I;
    TabRect.HitTest := True;
    TabRect.Cursor := crHandPoint;
    TabRect.OnClick := TabClick;
    TabRect.OnMouseEnter := TabMouseEnter;
    TabRect.OnMouseLeave := TabMouseLeave;
    TabRect.OnMouseWheel := TabsMouseWheel;

    { Сначала подпись (Client), потом крестик (Right), иконка в конце (Left):
      FMX раскладывает Align с конца списка — иначе текст оказывается под иконкой. }
    Lbl := TLabel.Create(TabRect);
    Lbl.Parent := TabRect;
    Lbl.Align := TAlignLayout.Client;
    if ShowClose then
      Lbl.Margins.Rect := TRectF.Create(4, 0, 4, 0)
    else
      Lbl.Margins.Rect := TRectF.Create(6, 0, 8, 0);
    Lbl.Text := FTitles[I];
    Lbl.StyledSettings := Lbl.StyledSettings -
      [TStyledSetting.Family, TStyledSetting.Size, TStyledSetting.FontColor];
    Lbl.TextSettings.Font.Family := FluentFontFamily;
    Lbl.TextSettings.Font.Size := 12;
    Lbl.TextSettings.WordWrap := False;
    Lbl.TextSettings.Trimming := TTextTrimming.Character;
    Lbl.Tag := I;
    Lbl.HitTest := False;

    if ShowClose then
    begin
      CloseBtn := TRectangle.Create(TabRect);
      CloseBtn.Parent := TabRect;
      CloseBtn.Align := TAlignLayout.Right;
      CloseBtn.Width := 20;
      CloseBtn.Margins.Rect := TRectF.Create(0, 6, 6, 6);
      CloseBtn.XRadius := 4;
      CloseBtn.YRadius := 4;
      CloseBtn.Stroke.Kind := TBrushKind.None;
      CloseBtn.Fill.Kind := TBrushKind.Solid;
      CloseBtn.Tag := I;
      CloseBtn.HitTest := True;
      CloseBtn.Cursor := crHandPoint;
      CloseBtn.OnClick := CloseClick;
      CloseBtn.OnMouseEnter := CloseMouseEnter;
      CloseBtn.OnMouseLeave := CloseMouseLeave;

      CloseLbl := TLabel.Create(CloseBtn);
      CloseLbl.Parent := CloseBtn;
      CloseLbl.Align := TAlignLayout.Client;
      CloseLbl.Text := '×';
      CloseLbl.TextAlign := TTextAlign.Center;
      CloseLbl.TextSettings.Font.Family := FluentFontFamily;
      CloseLbl.TextSettings.Font.Size := 13;
      CloseLbl.StyledSettings := CloseLbl.StyledSettings -
        [TStyledSetting.Family, TStyledSetting.Size, TStyledSetting.FontColor];
      CloseLbl.HitTest := False;
    end;

    if (I < FBusy.Count) and FBusy[I] then
    begin
      var Spin := TPaintBox.Create(TabRect);
      Spin.Parent := TabRect;
      Spin.Align := TAlignLayout.Left;
      Spin.Width := 18;
      Spin.Margins.Rect := TRectF.Create(8, 6, 2, 6);
      Spin.HitTest := False;
      Spin.Tag := 1001;
      Spin.OnPaint := PaintTabSpinner;
    end
    else if HasIcon then
    begin
      IconImg := TImage.Create(TabRect);
      IconImg.Parent := TabRect;
      IconImg.Align := TAlignLayout.Left;
      if I = FActiveIndex then
      begin
        IconImg.Width := 22;
        IconImg.Margins.Rect := TRectF.Create(8, 4, 2, 4);
      end
      else
      begin
        IconImg.Width := 14;
        IconImg.Margins.Rect := TRectF.Create(10, 8, 2, 8);
      end;
      IconImg.WrapMode := TImageWrapMode.Fit;
      IconImg.HitTest := False;
      if not IsRemotePath(FIconPaths[I]) then
      begin
        IconBmp := nil;
        try
          GetFileIconBitmap(FIconPaths[I], True, IconBmp);
          if Assigned(IconBmp) then
            IconImg.Bitmap.Assign(IconBmp);
        finally
          IconBmp.Free;
        end;
      end;
    end;

    ApplyTabColors(TabRect, I = FActiveIndex, I = FHoverIndex);
  end;

  UpdateLayoutSizes;
  UpdateNavButtons;
  TThread.ForceQueue(nil,
    procedure
    begin
      if Assigned(FScrollBox) and Assigned(FNavCluster) then
      begin
        UpdateLayoutSizes;
        UpdateNavButtons;
      end;
    end);
end;

initialization
  ClearTabDrag;

end.
