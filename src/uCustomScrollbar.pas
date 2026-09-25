unit uCustomScrollbar;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Layouts, FMX.Graphics, FMX.ScrollBox,
  uAppSettings, uThemeManager;

type
  TCustomFileScrollbar = class
  private
    FScrollBox: TCustomScrollBox;
    FPresented: TCustomPresentedScrollBox;
    FTrack: TControl;
    FThumb: TRectangle;
    FTimer: TTimer;
    FIsDragging: Boolean;
    FDragStart: Single;
    FDragStartPos: Single;
    FThemeColors: TThemeColors;
    FOrientation: TOrientation;
    FThick: Single;
    FExtContent: Single;
    FExtView: Single;
    FExtPos: Single;
    FOnExtScroll: TProc<Single>;

    function AdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;
    function TrackCtrl: TControl;
    function ViewSize: Single;
    function ContentSize: Single;
    function Viewport: Single;
    procedure SetViewport(AValue: Single);
    procedure ApplyThumbChrome;
    procedure TimerTick(Sender: TObject);
    procedure ThumbMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure ThumbMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure ThumbMouseEnter(Sender: TObject);
    procedure ThumbMouseLeave(Sender: TObject);
    procedure InitThumb(AParent: TFmxObject);
  public
    constructor Create(AParent: TFmxObject; AScrollBox: TCustomScrollBox); overload;
    constructor Create(AParent: TFmxObject; APresented: TCustomPresentedScrollBox); overload;
    constructor CreateForTrack(AParent: TFmxObject; ATrack: TControl;
      AOrientation: TOrientation); overload;
    destructor Destroy; override;
    procedure UpdateThumb;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SetColor(AColor: TAlphaColor);
    procedure SetExternalMetrics(AContent, AView, APos: Single);
    property Orientation: TOrientation read FOrientation write FOrientation;
    property OnExternalScroll: TProc<Single> read FOnExtScroll write FOnExtScroll;
  end;

implementation

uses
  System.Math, FMX.Forms, Winapi.Windows;

procedure TCustomFileScrollbar.InitThumb(AParent: TFmxObject);
begin
  FThemeColors := GetThemeColors(atSystem);
  FOrientation := TOrientation.Vertical;
  FThick := 5;

  FThumb := TRectangle.Create(AParent);
  FThumb.Parent := AParent;
  FThumb.Align := TAlignLayout.None;
  FThumb.Width := 5;
  FThumb.XRadius := 2.5;
  FThumb.YRadius := 2.5;
  FThumb.Stroke.Kind := TBrushKind.None;
  FThumb.Fill.Kind := TBrushKind.Solid;
  FThumb.Fill.Color := AdjustAlpha(FThemeColors.SubTextColor, 90);
  FThumb.Visible := False;
  FThumb.HitTest := True;

  FTimer := TTimer.Create(nil);
  FTimer.Interval := 10;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;

  FThumb.OnMouseDown := ThumbMouseDown;
  FThumb.OnMouseUp := ThumbMouseUp;
  FThumb.OnMouseEnter := ThumbMouseEnter;
  FThumb.OnMouseLeave := ThumbMouseLeave;
end;

constructor TCustomFileScrollbar.Create(AParent: TFmxObject; AScrollBox: TCustomScrollBox);
begin
  inherited Create;
  FScrollBox := AScrollBox;
  InitThumb(AParent);
end;

constructor TCustomFileScrollbar.Create(AParent: TFmxObject; APresented: TCustomPresentedScrollBox);
begin
  inherited Create;
  FPresented := APresented;
  InitThumb(AParent);
end;

constructor TCustomFileScrollbar.CreateForTrack(AParent: TFmxObject; ATrack: TControl;
  AOrientation: TOrientation);
begin
  inherited Create;
  FTrack := ATrack;
  InitThumb(AParent);
  FOrientation := AOrientation;
end;

destructor TCustomFileScrollbar.Destroy;
begin
  FTimer.Free;
  if Assigned(FThumb) then
  begin
    FThumb.OnMouseDown := nil;
    FThumb.OnMouseUp := nil;
    FThumb.Parent := nil;
    FreeAndNil(FThumb);
  end;
  inherited;
end;

function TCustomFileScrollbar.AdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.Color := AColor;
  Rec.A := AAlpha;
  Result := Rec.Color;
end;

function TCustomFileScrollbar.TrackCtrl: TControl;
begin
  if Assigned(FPresented) then
    Result := FPresented
  else if Assigned(FScrollBox) then
    Result := FScrollBox
  else
    Result := FTrack;
end;

function TCustomFileScrollbar.ViewSize: Single;
var
  C: TControl;
begin
  if FTrack <> nil then
    Exit(FExtView);
  C := TrackCtrl;
  if C = nil then
    Exit(0);
  if FOrientation = TOrientation.Vertical then
    Result := C.Height
  else
    Result := C.Width;
end;

function TCustomFileScrollbar.ContentSize: Single;
begin
  if FTrack <> nil then
    Exit(FExtContent);
  if Assigned(FPresented) then
  begin
    if FOrientation = TOrientation.Vertical then
      Result := FPresented.ContentBounds.Height
    else
      Result := FPresented.ContentBounds.Width;
  end
  else if Assigned(FScrollBox) then
  begin
    if FOrientation = TOrientation.Vertical then
      Result := FScrollBox.ContentBounds.Height
    else
      Result := FScrollBox.ContentBounds.Width;
  end
  else
    Result := 0;
end;

function TCustomFileScrollbar.Viewport: Single;
begin
  if FTrack <> nil then
    Exit(FExtPos);
  if Assigned(FPresented) then
  begin
    if FOrientation = TOrientation.Vertical then
      Result := FPresented.ViewportPosition.Y
    else
      Result := FPresented.ViewportPosition.X;
  end
  else if Assigned(FScrollBox) then
  begin
    if FOrientation = TOrientation.Vertical then
      Result := FScrollBox.ViewportPosition.Y
    else
      Result := FScrollBox.ViewportPosition.X;
  end
  else
    Result := 0;
end;

procedure TCustomFileScrollbar.SetViewport(AValue: Single);
var
  P: TPointF;
  MaxScroll: Single;
begin
  MaxScroll := ContentSize - ViewSize;
  if MaxScroll < 0 then
    MaxScroll := 0;
  AValue := EnsureRange(AValue, 0, MaxScroll);
  if Assigned(FOnExtScroll) then
  begin
    FExtPos := AValue;
    FOnExtScroll(AValue);
    Exit;
  end;
  if Assigned(FPresented) then
  begin
    P := FPresented.ViewportPosition;
    if FOrientation = TOrientation.Vertical then
      P.Y := AValue
    else
      P.X := AValue;
    FPresented.ViewportPosition := P;
  end
  else if Assigned(FScrollBox) then
  begin
    P := FScrollBox.ViewportPosition;
    if FOrientation = TOrientation.Vertical then
      P.Y := AValue
    else
      P.X := AValue;
    FScrollBox.ViewportPosition := P;
  end;
end;

procedure TCustomFileScrollbar.SetExternalMetrics(AContent, AView, APos: Single);
begin
  if SameValue(FExtContent, AContent, 0.5) and SameValue(FExtView, AView, 0.5) and
     SameValue(FExtPos, APos, 0.5) then
  begin
    if Assigned(FThumb) and FThumb.Visible and (AView > 0) and (AContent > AView) then
      Exit;
  end;
  FExtContent := AContent;
  FExtView := AView;
  FExtPos := APos;
  UpdateThumb;
end;

procedure TCustomFileScrollbar.ApplyTheme(const AColors: TThemeColors);
begin
  FThemeColors := AColors;
  if Assigned(FThumb) and not FIsDragging then
    ApplyThumbChrome;
end;

procedure TCustomFileScrollbar.SetColor(AColor: TAlphaColor);
begin
  if Assigned(FThumb) then
    FThumb.Fill.Color := AColor;
end;

procedure TCustomFileScrollbar.ApplyThumbChrome;
begin
  if not Assigned(FThumb) then
    Exit;
  if FIsDragging then
    FThumb.Fill.Color := FThemeColors.SelectionColor
  else if FThick >= 8 then
    FThumb.Fill.Color := AdjustAlpha(FThemeColors.SelectionColor, 190)
  else
    FThumb.Fill.Color := AdjustAlpha(FThemeColors.SubTextColor, 90);
  UpdateThumb;
end;

procedure TCustomFileScrollbar.UpdateThumb;
var
  C: TControl;
  TrackLen, Cont, ThumbLen, ThumbOff, MaxScroll, Ox, Oy, NX, NY, NW, NH: Single;
begin
  C := TrackCtrl;
  if (C = nil) or not Assigned(FThumb) then
    Exit;
  if (csDestroying in C.ComponentState) or not C.Visible then
  begin
    FThumb.Visible := False;
    Exit;
  end;
  try

  TrackLen := ViewSize;
  Cont := ContentSize;
  if (TrackLen <= 0) or (Cont <= TrackLen) then
  begin
    FThumb.Visible := False;
    Exit;
  end;

  FThumb.Visible := True;
  ThumbLen := Max(20, (TrackLen / Cont) * TrackLen);
  MaxScroll := Cont - TrackLen;
  if MaxScroll > 0 then
    ThumbOff := (Viewport / MaxScroll) * (TrackLen - ThumbLen)
  else
    ThumbOff := 0;
  if FThick < 5 then
    FThick := 5;

  { Thumb is parented either to the track itself (local 0,0) or to the
    track's parent (file panel) — then Position of the track is needed. }
  if FThumb.Parent = C then
  begin
    Ox := 0;
    Oy := 0;
  end
  else
  begin
    Ox := C.Position.X;
    Oy := C.Position.Y;
  end;

  if FOrientation = TOrientation.Vertical then
  begin
    NX := Ox + C.Width - 5 - (FThick / 2);
    NY := Oy + ThumbOff;
    NW := FThick;
    NH := ThumbLen;
  end
  else
  begin
    NX := Ox + ThumbOff;
    NY := Oy + C.Height - 5 - (FThick / 2);
    NW := ThumbLen;
    NH := FThick;
  end;
  { SetBounds/BringToFront на каждом тике → Realign родителя → stack overflow. }
  if not (SameValue(FThumb.Position.X, NX, 0.4) and
          SameValue(FThumb.Position.Y, NY, 0.4) and
          SameValue(FThumb.Width, NW, 0.4) and
          SameValue(FThumb.Height, NH, 0.4)) then
    FThumb.SetBounds(NX, NY, NW, NH);
  except
    if Assigned(FThumb) then
      FThumb.Visible := False;
  end;
end;

procedure TCustomFileScrollbar.ThumbMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    FIsDragging := True;
    if FOrientation = TOrientation.Vertical then
      FDragStart := Screen.MousePos.Y
    else
      FDragStart := Screen.MousePos.X;
    FDragStartPos := Viewport;
    FThumb.Fill.Color := FThemeColors.SelectionColor;
    FTimer.Enabled := True;
  end;
end;

procedure TCustomFileScrollbar.ThumbMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    FIsDragging := False;
    FTimer.Enabled := False;
    FThick := 5;
    ApplyThumbChrome;
  end;
end;

procedure TCustomFileScrollbar.ThumbMouseEnter(Sender: TObject);
begin
  FThick := 8;
  ApplyThumbChrome;
end;

procedure TCustomFileScrollbar.ThumbMouseLeave(Sender: TObject);
begin
  if not FIsDragging then
  begin
    FThick := 5;
    ApplyThumbChrome;
  end;
end;

procedure TCustomFileScrollbar.TimerTick(Sender: TObject);
var
  TrackLen, Cont, ThumbLen, MaxScroll, Scale, Cur, NewPos: Single;
begin
  if not FIsDragging or not Assigned(FThumb) or (TrackCtrl = nil) then
    Exit;

  if (GetAsyncKeyState(VK_LBUTTON) and $8000) = 0 then
  begin
    FIsDragging := False;
    FTimer.Enabled := False;
    FThick := 5;
    ApplyThumbChrome;
    Exit;
  end;

  TrackLen := ViewSize;
  Cont := ContentSize;
  if Cont <= TrackLen then
    Exit;

  ThumbLen := Max(20, (TrackLen / Cont) * TrackLen);
  MaxScroll := Cont - TrackLen;
  if TrackLen - ThumbLen <= 0 then
    Exit;

  if FOrientation = TOrientation.Vertical then
    Cur := Screen.MousePos.Y
  else
    Cur := Screen.MousePos.X;
  Scale := MaxScroll / (TrackLen - ThumbLen);
  NewPos := FDragStartPos + ((Cur - FDragStart) * Scale);
  SetViewport(NewPos);
  UpdateThumb;
end;

end.
