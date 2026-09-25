unit uFluentChrome;

{
  Reusable Fluent / WinUI 3 chrome: command buttons, icon buttons, F-keys.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Layouts, FMX.Graphics, FMX.Effects,
  uAppSettings, uThemeManager;

type
  TFluentButtonKind = (fbkSubtle, fbkStandard, fbkAccent, fbkNeon, fbkCommand, fbkKey);

  TFluentButton = class(TRectangle)
  private
    FKind: TFluentButtonKind;
    FColors: TThemeColors;
    FHovered: Boolean;
    FHoldHover: Boolean;
    FPressed: Boolean;
    FSelected: Boolean;
    FIcon: TText;
    FCaption: TText;
    FHotkey: TText;
    FContent: TLayout;
    FOnInvoke: TNotifyEvent;
    FBusy: Boolean;
    FBusyJobs: Integer;
    FBusyFrame: Integer;
    FBusyTimer: TTimer;
    FBusyPaint: TPaintBox;
    procedure ApplyVisual;
    procedure BusyTick(Sender: TObject);
    procedure PaintSpinner(Sender: TObject; Canvas: TCanvas);
    procedure HandleEnter(Sender: TObject);
    procedure HandleLeave(Sender: TObject);
    procedure HandleDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Setup(AParent: TFmxObject; const AIcon, ACaption: string;
      AKind: TFluentButtonKind; AOnClick: TNotifyEvent);
    procedure SetHotkey(const AText: string);
    procedure SetIcon(const AText: string);
    procedure SetCaption(const AText: string);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SetSelected(ASelected: Boolean);
    procedure HoldHover(AHold: Boolean);
    procedure StartBusy(AJobs: Integer = 1);
    procedure EndBusy;
    property Kind: TFluentButtonKind read FKind write FKind;
    property Busy: Boolean read FBusy;
  end;

function CreateFluentButton(AOwner: TComponent; AParent: TFmxObject;
  const AIcon, ACaption: string; AKind: TFluentButtonKind; AWidth: Single;
  AOnClick: TNotifyEvent): TFluentButton;

procedure ApplyFluentText(AText: TText; ASize: Single; ABold: Boolean = False);
procedure ApplyFluentShadow(AShadow: TShadowEffect; ADark: Boolean);

type
  TFluentCheckRow = class(TLayout)
  private
    FBox: TRectangle;
    FMark: TRectangle;
    FCaption: TText;
    FChecked: Boolean;
    FColors: TThemeColors;
    FOnChange: TNotifyEvent;
    procedure SetChecked(AValue: Boolean);
    procedure HandleClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Setup(AParent: TFmxObject; const ACaption: string; AChecked: Boolean);
    procedure ApplyTheme(const AColors: TThemeColors);
    property Checked: Boolean read FChecked write SetChecked;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TFluentPopupMenu = class(TPopup)
  private
    FColors: TThemeColors;
    FHost: TRectangle;
    FList: TLayout;
    FShadow: TShadowEffect;
    FItemH: Single;
    procedure ItemEnter(Sender: TObject);
    procedure ItemLeave(Sender: TObject);
    procedure ItemClick(Sender: TObject);
    procedure ApplyItemTheme(ARow: TRectangle);
    procedure SyncPopupSize;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearItems;
    procedure AddItem(const ACaption, AShortcut: string; AOnClick: TNotifyEvent);
    procedure AddSeparator;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure PopupNear(ATarget: TControl; AOpenOnRight: Boolean);
    procedure PopupAtCursor;
  end;

implementation

const
  PopupShadowL = 18;
  PopupShadowT = 14;
  PopupShadowR = 18;
  PopupShadowB = 22;
  PopupBodyW = 300;

type
  TClickHolder = class(TComponent)
  public
    Event: TNotifyEvent;
  end;

procedure ApplyFluentShadow(AShadow: TShadowEffect; ADark: Boolean);
begin
  if AShadow = nil then
    Exit;
  AShadow.Direction := 90;
  AShadow.Distance := 5;
  AShadow.Softness := 0.45;
  AShadow.ShadowColor := TAlphaColors.Black;
  if ADark then
    AShadow.Opacity := 0.55
  else
    AShadow.Opacity := 0.32;
end;

procedure ApplyFluentText(AText: TText; ASize: Single; ABold: Boolean);
begin
  if AText = nil then
    Exit;
  AText.TextSettings.Font.Family := FluentFontFamily;
  AText.TextSettings.Font.Size := ASize;
  if ABold then
    AText.TextSettings.Font.Style := [TFontStyle.fsBold]
  else
    AText.TextSettings.Font.Style := [];
end;

constructor TFluentButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := fbkSubtle;
  FColors := GetThemeColors(ActiveAppTheme);
  HitTest := True;
  Cursor := crHandPoint;
  XRadius := 6;
  YRadius := 6;
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := TAlphaColors.Null;
  OnMouseEnter := HandleEnter;
  OnMouseLeave := HandleLeave;
  OnMouseDown := HandleDown;
  OnMouseUp := HandleUp;
  OnClick := HandleClick;
end;

procedure TFluentButton.Setup(AParent: TFmxObject; const AIcon, ACaption: string;
  AKind: TFluentButtonKind; AOnClick: TNotifyEvent);
begin
  Parent := AParent;
  FKind := AKind;
  FOnInvoke := AOnClick;

  FContent := TLayout.Create(Self);
  FContent.Parent := Self;
  FContent.Align := TAlignLayout.Client;
  FContent.HitTest := False;

  if AIcon <> '' then
  begin
    FIcon := TText.Create(Self);
    FIcon.Parent := FContent;
    FIcon.Align := TAlignLayout.Left;
    if ACaption = '' then
    begin
      FIcon.Align := TAlignLayout.Client;
      FIcon.Margins.Rect := TRectF.Create(0, 0, 0, 0);
    end
    else
    begin
      FIcon.Width := 22;
      FIcon.Margins.Rect := TRectF.Create(8, 0, 0, 0);
    end;
    FIcon.Text := AIcon;
    FIcon.Font.Family := FluentIconFamily;
    FIcon.Font.Size := 14;
    FIcon.TextSettings.Font.Family := FluentIconFamily;
    FIcon.Color := FColors.TextColor;
    FIcon.TextSettings.FontColor := FColors.TextColor;
    FIcon.TextSettings.HorzAlign := TTextAlign.Center;
    FIcon.TextSettings.VertAlign := TTextAlign.Center;
    FIcon.HitTest := False;
  end;

  if ACaption <> '' then
  begin
    FCaption := TText.Create(Self);
    FCaption.Parent := FContent;
    FCaption.Align := TAlignLayout.Client;
    if AIcon = '' then
      FCaption.Margins.Rect := TRectF.Create(10, 0, 10, 0)
    else
      FCaption.Margins.Rect := TRectF.Create(6, 0, 10, 0);
    FCaption.Text := ACaption;
    ApplyFluentText(FCaption, 12, False);
    FCaption.TextSettings.HorzAlign := TTextAlign.Leading;
    FCaption.TextSettings.VertAlign := TTextAlign.Center;
    FCaption.HitTest := False;
    FCaption.WordWrap := False;
    FCaption.TextSettings.Trimming := TTextTrimming.Character;
  end;

  ApplyVisual;
end;

procedure TFluentButton.SetHotkey(const AText: string);
begin
  if FHotkey = nil then
  begin
    FHotkey := TText.Create(Self);
    FHotkey.Parent := FContent;
    FHotkey.Align := TAlignLayout.Left;
    FHotkey.Width := 28;
    FHotkey.Margins.Rect := TRectF.Create(8, 0, 0, 0);
    ApplyFluentText(FHotkey, 11, True);
    FHotkey.TextSettings.HorzAlign := TTextAlign.Leading;
    FHotkey.TextSettings.VertAlign := TTextAlign.Center;
    FHotkey.HitTest := False;
    if Assigned(FIcon) then
      FIcon.Visible := False;
    if Assigned(FCaption) then
    begin
      FCaption.Margins.Left := 4;
      FCaption.Margins.Right := 8;
    end;
  end;
  FHotkey.Text := AText;
end;

procedure TFluentButton.SetIcon(const AText: string);
begin
  if Assigned(FIcon) then
    FIcon.Text := AText;
end;

procedure TFluentButton.SetCaption(const AText: string);
begin
  if Assigned(FCaption) then
    FCaption.Text := AText;
  ApplyVisual;
end;

procedure TFluentButton.SetSelected(ASelected: Boolean);
begin
  FSelected := ASelected;
  ApplyVisual;
end;

procedure TFluentButton.HoldHover(AHold: Boolean);
begin
  if FHoldHover = AHold then
    Exit;
  FHoldHover := AHold;
  ApplyVisual;
end;

procedure TFluentButton.StartBusy(AJobs: Integer);
begin
  if AJobs < 1 then
    AJobs := 1;
  Inc(FBusyJobs, AJobs);
  if FBusy then
    Exit;
  FBusy := True;
  FBusyFrame := 0;
  if FBusyPaint = nil then
  begin
    FBusyPaint := TPaintBox.Create(Self);
    FBusyPaint.Parent := FContent;
    FBusyPaint.Align := TAlignLayout.Client;
    FBusyPaint.HitTest := False;
    FBusyPaint.OnPaint := PaintSpinner;
  end;
  FBusyPaint.Visible := True;
  FBusyPaint.BringToFront;
  if Assigned(FIcon) then
    FIcon.Visible := False;
  if FBusyTimer = nil then
  begin
    FBusyTimer := TTimer.Create(Self);
    FBusyTimer.Interval := 70;
    FBusyTimer.OnTimer := BusyTick;
  end;
  FBusyTimer.Enabled := True;
  ApplyVisual;
end;

procedure TFluentButton.EndBusy;
begin
  if FBusyJobs > 0 then
    Dec(FBusyJobs);
  if FBusyJobs > 0 then
    Exit;
  FBusyJobs := 0;
  FBusy := False;
  if Assigned(FBusyTimer) then
    FBusyTimer.Enabled := False;
  if Assigned(FBusyPaint) then
    FBusyPaint.Visible := False;
  if Assigned(FIcon) then
    FIcon.Visible := True;
  ApplyVisual;
end;

procedure TFluentButton.BusyTick(Sender: TObject);
begin
  FBusyFrame := (FBusyFrame + 1) mod 8;
  if Assigned(FBusyPaint) then
    FBusyPaint.Repaint;
end;

procedure TFluentButton.PaintSpinner(Sender: TObject; Canvas: TCanvas);
var
  C: TPointF;
  I: Integer;
  Ang, R, DotR: Single;
  P: TPointF;
  Dist: Integer;
  Alpha: Byte;
begin
  if (Canvas = nil) or (FBusyPaint = nil) then
    Exit;
  C := TPointF.Create(FBusyPaint.Width * 0.5, FBusyPaint.Height * 0.5);
  R := Min(FBusyPaint.Width, FBusyPaint.Height) * 0.28;
  DotR := Max(1.4, R * 0.22);
  Canvas.Fill.Kind := TBrushKind.Solid;
  for I := 0 to 7 do
  begin
    Ang := (I / 8) * Pi * 2 - Pi / 2;
    P := TPointF.Create(C.X + Cos(Ang) * R, C.Y + Sin(Ang) * R);
    Dist := (I - FBusyFrame + 8) mod 8;
    Alpha := Byte(50 + Round((7 - Dist) / 7 * 205));
    if Assigned(FIcon) then
      Canvas.Fill.Color := ThemeAdjustAlpha(FIcon.TextSettings.FontColor, Alpha)
    else
      Canvas.Fill.Color := ThemeAdjustAlpha(FColors.TextColor, Alpha);
    Canvas.FillEllipse(TRectF.Create(P.X - DotR, P.Y - DotR, P.X + DotR, P.Y + DotR), 1);
  end;
end;

procedure TFluentButton.ApplyTheme(const AColors: TThemeColors);
var
  Glyph: TAlphaColor;
begin
  FColors := AColors;
  if FKind = fbkAccent then
    Glyph := AColors.OnAccentTextColor
  else if FKind = fbkNeon then
    Glyph := $FF111111
  else
    Glyph := AColors.TextColor;
  if Assigned(FIcon) then
    FIcon.TextSettings.FontColor := Glyph;
  if Assigned(FCaption) then
    FCaption.TextSettings.FontColor := Glyph;
  if Assigned(FHotkey) then
    FHotkey.TextSettings.FontColor := Glyph;
  ApplyVisual;
end;

procedure TFluentButton.ApplyVisual;
begin
  { Как кнопки на статусбаре: при select/busy меняем только заливку, не цвет значка. }
  Stroke.Kind := TBrushKind.None;

  if FBusy then
    Fill.Color := FColors.ControlFillHover
  else
  case FKind of
    fbkAccent:
      begin
        if FPressed then
          Fill.Color := DarkenColor(FColors.SelectionColor, 0.10)
        else if FHovered then
          Fill.Color := FColors.AccentHover
        else
          Fill.Color := FColors.SelectionColor;
      end;
    fbkNeon:
      begin
        if FPressed then
          Fill.Color := $FF00A8CC
        else if FHovered then
          Fill.Color := $FF33DDFF
        else
          Fill.Color := $FF00D4FF;
      end;
    fbkStandard:
      begin
        Stroke.Kind := TBrushKind.Solid;
        Stroke.Color := FColors.ControlStroke;
        Stroke.Thickness := 1;
        if FPressed then
          Fill.Color := FColors.ControlFillPressed
        else if FHovered then
          Fill.Color := FColors.ControlFillHover
        else
          Fill.Color := FColors.ControlFill;
      end;
    fbkKey:
      begin
        if FPressed then
          Fill.Color := FColors.ControlFillPressed
        else if FHovered then
          Fill.Color := FColors.ControlFillHover
        else
          Fill.Color := FColors.ControlFill;
      end;
  else
    if FPressed then
      Fill.Color := FColors.ControlFillPressed
    else if FHovered or FHoldHover then
      Fill.Color := FColors.ControlFillHover
    else if FSelected then
      Fill.Color := FColors.AccentSubtle
    else
      Fill.Color := TAlphaColors.Null;
  end;
end;

procedure TFluentButton.HandleEnter(Sender: TObject);
begin
  FHovered := True;
  ApplyVisual;
end;

procedure TFluentButton.HandleLeave(Sender: TObject);
begin
  FHovered := False;
  FPressed := False;
  ApplyVisual;
end;

procedure TFluentButton.HandleDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    FPressed := True;
    ApplyVisual;
  end;
end;

procedure TFluentButton.HandleUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FPressed := False;
  ApplyVisual;
end;

procedure TFluentButton.HandleClick(Sender: TObject);
begin
  if FBusy then
    Exit;
  if Assigned(FOnInvoke) then
    FOnInvoke(Self);
end;

function CreateFluentButton(AOwner: TComponent; AParent: TFmxObject;
  const AIcon, ACaption: string; AKind: TFluentButtonKind; AWidth: Single;
  AOnClick: TNotifyEvent): TFluentButton;
begin
  Result := TFluentButton.Create(AOwner);
  Result.Setup(AParent, AIcon, ACaption, AKind, AOnClick);
  Result.Align := TAlignLayout.Left;
  Result.Width := AWidth;
  Result.Margins.Rect := TRectF.Create(2, 4, 2, 4);
end;

{ TFluentCheckRow }

constructor TFluentCheckRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := 36;
  HitTest := True;
  Cursor := crHandPoint;
  OnClick := HandleClick;
  FColors := GetThemeColors(ActiveAppTheme);

  FBox := TRectangle.Create(Self);
  FBox.Parent := Self;
  FBox.Align := TAlignLayout.Left;
  FBox.Width := 20;
  FBox.Margins.Rect := TRectF.Create(0, 8, 10, 8);
  FBox.XRadius := 4;
  FBox.YRadius := 4;
  FBox.Stroke.Kind := TBrushKind.Solid;
  FBox.Stroke.Thickness := 1;
  FBox.HitTest := False;

  FMark := TRectangle.Create(Self);
  FMark.Parent := FBox;
  FMark.Align := TAlignLayout.Client;
  FMark.Margins.Rect := TRectF.Create(5, 5, 5, 5);
  FMark.XRadius := 2;
  FMark.YRadius := 2;
  FMark.Stroke.Kind := TBrushKind.None;
  FMark.Fill.Kind := TBrushKind.Solid;
  FMark.HitTest := False;
  FMark.Visible := False;

  FCaption := TText.Create(Self);
  FCaption.Parent := Self;
  FCaption.Align := TAlignLayout.Client;
  FCaption.HitTest := False;
  ApplyFluentText(FCaption, 13, False);
  FCaption.TextSettings.HorzAlign := TTextAlign.Leading;
  FCaption.TextSettings.VertAlign := TTextAlign.Center;
end;

procedure TFluentCheckRow.Setup(AParent: TFmxObject; const ACaption: string;
  AChecked: Boolean);
begin
  Parent := AParent;
  Align := TAlignLayout.Top;
  FCaption.Text := ACaption;
  FChecked := AChecked;
  FMark.Visible := FChecked;
end;

procedure TFluentCheckRow.SetChecked(AValue: Boolean);
begin
  if FChecked = AValue then
    Exit;
  FChecked := AValue;
  FMark.Visible := FChecked;
  ApplyTheme(FColors);
end;

procedure TFluentCheckRow.HandleClick(Sender: TObject);
begin
  SetChecked(not FChecked);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TFluentCheckRow.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  FCaption.TextSettings.FontColor := AColors.TextColor;
  FMark.Fill.Color := AColors.OnAccentTextColor;
  if FChecked then
  begin
    FBox.Fill.Color := AColors.SelectionColor;
    FBox.Stroke.Color := AColors.SelectionColor;
  end
  else
  begin
    FBox.Fill.Color := AColors.ControlFill;
    FBox.Stroke.Color := AColors.ControlStroke;
  end;
end;

{ TFluentPopupMenu }

constructor TFluentPopupMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Placement := TPlacement.LeftCenter;
  ClipChildren := False;
  { FMX TPopup по умолчанию Padding=8 — вместе с полями тени сдвигало меню влево. }
  BorderWidth := 0;
  FItemH := 32;
  FColors := GetThemeColors(ActiveAppTheme);

  FHost := TRectangle.Create(Self);
  FHost.Parent := Self;
  FHost.Align := TAlignLayout.Client;
  FHost.Margins.Rect := TRectF.Create(PopupShadowL, PopupShadowT,
    PopupShadowR, PopupShadowB);
  FHost.XRadius := 8;
  FHost.YRadius := 8;
  FHost.Stroke.Kind := TBrushKind.Solid;
  FHost.Stroke.Thickness := 1;
  FHost.Fill.Kind := TBrushKind.Solid;
  FHost.Padding.Rect := TRectF.Create(6, 6, 6, 6);
  FHost.ClipChildren := False;

  FShadow := TShadowEffect.Create(FHost);
  FShadow.Parent := FHost;
  ApplyFluentShadow(FShadow, FColors.IsDark);

  FList := TLayout.Create(Self);
  FList.Parent := FHost;
  FList.Align := TAlignLayout.Top;
  FList.Height := 0;
  SyncPopupSize;
end;

procedure TFluentPopupMenu.SyncPopupSize;
begin
  Width := PopupBodyW + PopupShadowL + PopupShadowR;
  Height := FList.Height + 12 + PopupShadowT + PopupShadowB;
end;

procedure TFluentPopupMenu.ClearItems;
begin
  while FList.ControlsCount > 0 do
    FList.Controls[0].Free;
  FList.Height := 0;
  SyncPopupSize;
end;

procedure TFluentPopupMenu.ApplyItemTheme(ARow: TRectangle);
var
  I: Integer;
  T: TText;
begin
  if ARow.Tag = 2 then
  begin
    ARow.Fill.Color := FColors.DividerColor;
    Exit;
  end;
  ARow.Fill.Color := TAlphaColors.Null;
  for I := 0 to ARow.ControlsCount - 1 do
    if ARow.Controls[I] is TText then
    begin
      T := TText(ARow.Controls[I]);
      if T.Tag = 8 then
        T.TextSettings.FontColor := FColors.SubTextColor
      else
        T.TextSettings.FontColor := FColors.TextColor;
    end;
end;

procedure TFluentPopupMenu.AddSeparator;
var
  Line: TRectangle;
begin
  Line := TRectangle.Create(Self);
  Line.Parent := FList;
  Line.Align := TAlignLayout.Top;
  Line.Height := 1;
  Line.Margins.Rect := TRectF.Create(8, 6, 8, 6);
  Line.Stroke.Kind := TBrushKind.None;
  Line.Fill.Kind := TBrushKind.Solid;
  Line.HitTest := False;
  Line.Tag := 2;
  Line.Fill.Color := FColors.DividerColor;
  FList.Height := FList.Height + 13;
  SyncPopupSize;
end;

procedure TFluentPopupMenu.AddItem(const ACaption, AShortcut: string;
  AOnClick: TNotifyEvent);
var
  Row: TRectangle;
  Cap, Key: TText;
  Hold: TClickHolder;
begin
  Row := TRectangle.Create(Self);
  Row.Parent := FList;
  Row.Align := TAlignLayout.Top;
  Row.Height := FItemH;
  Row.XRadius := 6;
  Row.YRadius := 6;
  Row.Stroke.Kind := TBrushKind.None;
  Row.Fill.Kind := TBrushKind.Solid;
  Row.Fill.Color := TAlphaColors.Null;
  Row.HitTest := True;
  Row.Cursor := crHandPoint;
  Row.OnMouseEnter := ItemEnter;
  Row.OnMouseLeave := ItemLeave;
  Row.OnClick := ItemClick;
  Hold := TClickHolder.Create(Row);
  Hold.Event := AOnClick;
  Row.TagObject := Hold;

  Cap := TText.Create(Row);
  Cap.Parent := Row;
  Cap.Align := TAlignLayout.Client;
  Cap.Margins.Rect := TRectF.Create(10, 0, 8, 0);
  Cap.HitTest := False;
  Cap.Text := ACaption;
  ApplyFluentText(Cap, 13, False);
  Cap.TextSettings.HorzAlign := TTextAlign.Leading;
  Cap.TextSettings.VertAlign := TTextAlign.Center;
  Cap.TextSettings.FontColor := FColors.TextColor;

  if AShortcut <> '' then
  begin
    Key := TText.Create(Row);
    Key.Parent := Row;
    Key.Align := TAlignLayout.Right;
    Key.Width := 78;
    Key.Margins.Rect := TRectF.Create(0, 0, 10, 0);
    Key.HitTest := False;
    Key.Text := AShortcut;
    Key.Tag := 8;
    ApplyFluentText(Key, 12, False);
    Key.TextSettings.HorzAlign := TTextAlign.Trailing;
    Key.TextSettings.VertAlign := TTextAlign.Center;
    Key.TextSettings.FontColor := FColors.SubTextColor;
  end;

  FList.Height := FList.Height + FItemH;
  SyncPopupSize;
end;

procedure TFluentPopupMenu.ItemEnter(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FColors.ItemHover;
end;

procedure TFluentPopupMenu.ItemLeave(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := TAlphaColors.Null;
end;

procedure TFluentPopupMenu.ItemClick(Sender: TObject);
var
  Hold: TClickHolder;
  Ev: TNotifyEvent;
begin
  Ev := nil;
  if (Sender is TRectangle) and (TRectangle(Sender).TagObject is TClickHolder) then
  begin
    Hold := TClickHolder(TRectangle(Sender).TagObject);
    Ev := Hold.Event;
  end;
  IsOpen := False;
  if Assigned(Ev) then
    TThread.ForceQueue(nil,
      procedure
      begin
        if Assigned(Ev) then
          Ev(nil);
      end);
end;

procedure TFluentPopupMenu.ApplyTheme(const AColors: TThemeColors);
var
  I: Integer;
begin
  FColors := AColors;
  if Assigned(FHost) then
  begin
    FHost.Fill.Color := AColors.CardBackground;
    FHost.Stroke.Color := AColors.CardStroke;
  end;
  ApplyFluentShadow(FShadow, AColors.IsDark);
  if Assigned(FList) then
    for I := 0 to FList.ControlsCount - 1 do
      if FList.Controls[I] is TRectangle then
        ApplyItemTheme(TRectangle(FList.Controls[I]));
end;

procedure TFluentPopupMenu.PopupNear(ATarget: TControl; AOpenOnRight: Boolean);
const
  Gap = 2;
begin
  PlacementTarget := ATarget;
  { FMX для Left/LeftCenter применяет Offset как (Padding.Right - X),
    поэтому сдвиг к цели — отрицательный и слева, и справа. }
  if AOpenOnRight then
  begin
    Placement := TPlacement.RightCenter;
    HorizontalOffset := -(PopupShadowL - Gap);
  end
  else
  begin
    Placement := TPlacement.LeftCenter;
    HorizontalOffset := -(PopupShadowR - Gap);
  end;
  VerticalOffset := (PopupShadowB - PopupShadowT) / 2;
  IsOpen := True;
end;

procedure TFluentPopupMenu.PopupAtCursor;
begin
  PlacementTarget := nil;
  Placement := TPlacement.Mouse;
  HorizontalOffset := 4;
  VerticalOffset := 4;
  IsOpen := True;
end;

end.
