unit uSettingsForm;

{
  Fluent Settings: master-detail (категории слева, страница справа).
  Свои чекбоксы и карточки — без системных TEdit/TCheckBox.
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Types, System.Math,
  System.Generics.Collections,
  FMX.Graphics, FMX.Forms, FMX.Layouts, FMX.StdCtrls, FMX.Objects, FMX.Types,
  {$IFDEF MSWINDOWS}Winapi.Windows, FMX.Platform.Win,{$ENDIF}
  uAppSettings, uThemeManager, uFluentChrome, uFluentEdit, uLang, uLangBind;

type
  TSettingsApply = (saBands, saPanels, saBehavior, saFileOp);
  TSettingsApplySet = set of TSettingsApply;
  TOptionsChangedProc = reference to procedure(const AApply: TSettingsApplySet);
  TThemeChangedProc = reference to procedure(NewTheme: TAppTheme);

  TSettingsForm = class(TForm)
  private
    FSettings: TAppSettings;
    FSaveTimer: TTimer;
    FOnThemeChanged: TThemeChangedProc;
    FOnOptionsChanged: TOptionsChangedProc;
    FOnTintChanged: TProc;
    FOnOpacityChanged: TProc;
    FColors: TThemeColors;
    FPage: Integer;

    FRoot: TLayout;
    FBody: TLayout;
    FNav: TRectangle;
    FNavStack: TLayout;
    FNavBtns: array[0..3] of TFluentButton;
    FContent: TRectangle;
    FPages: array[0..3] of TVertScrollBox;
    FFooter: TLayout;
    FBtnClose: TFluentButton;

    FCardSystem, FCardLight, FCardDark: TRectangle;
    FCardMatNormal, FCardMatAcrylic, FCardMatMica: TRectangle;
    FTintCard: TRectangle;
    FTintSlider: TPaintBox;
    FTintHint: TText;
    FCbTint: TFluentCheckRow;
    FTintHold: Integer;
    FTintDrag: Boolean;
    FTintSync: Boolean;
    FOpacitySlider: TPaintBox;
    FCbOpacity: TFluentCheckRow;
    FOpacityHold: Integer;
    FOpacityDrag: Boolean;
    FOpacitySync: Boolean;
    FCbDock, FCbMid, FCbDrives, FCbDriveHome, FCbFn, FCbQuick, FCbCmd: TFluentCheckRow;
    FCbFollow: TFluentCheckRow;
    FCbSelExplorer, FCbSelVibe: TFluentCheckRow;
    FCbHidden, FCbFolderSize, FCbNetwork: TFluentCheckRow;
    FCbAutoStart, FCbSingleInstance: TFluentCheckRow;
    FCbOpQuiet, FCbOpExplorer, FCbOpVibe: TFluentCheckRow;
    FCbTabIcons, FCbEqualTabs: TFluentCheckRow;
    FCbDockLeft, FCbDockCenter, FCbDockFree, FCbDockSeps: TFluentCheckRow;
    FFontSizeEdit: TFluentEdit;
    FLangCard: TRectangle;
    FLangRows: TList<TFluentCheckRow>;
    FOnLanguageChanged: TProc;

    procedure BuildUI;
    procedure BuildNav;
    procedure BuildPages;
    function AddPage: TVertScrollBox;
    function AddCard(AParent: TFmxObject; const AKey: string): TRectangle;
    function AddCheck(AParent: TFmxObject; const AKey: string;
      AChecked: Boolean; AOnChange: TNotifyEvent): TFluentCheckRow;
    procedure RebuildLangPage;
    procedure BuildThemeCard(var ACard: TRectangle; AParent: TFmxObject;
      const AKey: string; ATheme: TAppTheme);
    procedure BuildMaterialCard(var ACard: TRectangle; AParent: TFmxObject;
      const AKey: string; AMaterial: TWindowMaterial; APreview: TAlphaColor);
    procedure BuildTintCard(AParent: TFmxObject);
    procedure TintTrack(out TrackL, TrackR: Single);
    function TintFromSliderX(X: Single): Integer;
    procedure PaintTintSlider(Sender: TObject; Canvas: TCanvas);
    procedure TintSliderDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure TintSliderMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure TintSliderUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure TintSliderDblClick(Sender: TObject);
    procedure TintEnabledClick(Sender: TObject);
    procedure SyncTintCheck;
    procedure ApplyTintLive(AValue: Integer; ASave: Boolean);
    procedure SyncTintHint;
    procedure LockTintOrder;
    procedure OpacityTrack(out TrackL, TrackR: Single);
    function OpacityFromSliderX(X: Single): Integer;
    procedure PaintOpacitySlider(Sender: TObject; Canvas: TCanvas);
    procedure OpacitySliderDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure OpacitySliderMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure OpacitySliderUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure OpacitySliderDblClick(Sender: TObject);
    procedure OpacityEnabledClick(Sender: TObject);
    procedure SyncOpacityCheck;
    procedure ApplyOpacityLive(AValue: Integer; ASave: Boolean);
    procedure NavClick(Sender: TObject);
    procedure ShowPage(AIndex: Integer);
    procedure ThemeCardClick(Sender: TObject);
    procedure MaterialCardClick(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
    procedure DockAlignClick(Sender: TObject);
    procedure FileOpModeClick(Sender: TObject);
    procedure MouseModeClick(Sender: TObject);
    procedure LangClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure SaveTimerTick(Sender: TObject);
    procedure ScheduleSave;
    procedure CollectFromUI;
    procedure UpdateThemeCards;
    procedure UpdateMaterialCards;
    function ThemeOfCard(ACard: TRectangle): TAppTheme;
    procedure ApplyNativeChrome;
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent; ASettings: TAppSettings;
      AOnThemeChanged: TThemeChangedProc); reintroduce;
    destructor Destroy; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ApplyLanguage;
    property OnOptionsChanged: TOptionsChangedProc read FOnOptionsChanged write FOnOptionsChanged;
    property OnLanguageChanged: TProc read FOnLanguageChanged write FOnLanguageChanged;
    property OnTintChanged: TProc read FOnTintChanged write FOnTintChanged;
    property OnOpacityChanged: TProc read FOnOpacityChanged write FOnOpacityChanged;
  end;

implementation

constructor TSettingsForm.Create(AOwner: TComponent; ASettings: TAppSettings;
  AOnThemeChanged: TThemeChangedProc);
begin
  inherited CreateNew(AOwner);
  FSettings := ASettings;
  FOnThemeChanged := AOnThemeChanged;
  Width := 860;
  Height := 620;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  TrForm(Self, 'set.title');
  Position := TFormPosition.OwnerFormCenter;
  FColors := GetThemeColors(FSettings.Theme);
  FPage := 0;
  FSaveTimer := TTimer.Create(Self);
  FSaveTimer.Interval := 350;
  FSaveTimer.Enabled := False;
  FSaveTimer.OnTimer := SaveTimerTick;
  BuildUI;
  ApplyTheme(FColors);
  ShowPage(0);
  ApplyNativeChrome;
end;

procedure TSettingsForm.ApplyNativeChrome;
begin
  {$IFDEF MSWINDOWS}
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  {$ENDIF}
end;

procedure TSettingsForm.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TSettingsForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
end;

function TSettingsForm.AddPage: TVertScrollBox;
begin
  Result := TVertScrollBox.Create(Self);
  Result.Parent := FContent;
  Result.Align := TAlignLayout.Client;
  Result.ShowScrollBars := False;
  Result.Padding.Rect := TRectF.Create(20, 16, 16, 16);
  Result.Visible := False;
end;

function TSettingsForm.AddCard(AParent: TFmxObject; const AKey: string): TRectangle;
var
  Cap: TText;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Top;
  Result.XRadius := 10;
  Result.YRadius := 10;
  Result.Stroke.Kind := TBrushKind.Solid;
  Result.Stroke.Thickness := 1;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.Margins.Rect := TRectF.Create(0, 0, 0, 12);
 Result.Padding.Rect := TRectF.Create(16, 0, 16, 12); // поставил по top = 0 , и текст стал наместо на верх
  Result.Height := 56;

  Cap := TText.Create(Self);
  Cap.Parent := Result;
  Cap.Align := TAlignLayout.Top;
  Cap.Height := 22;
  Cap.HitTest := False;
  Cap.Tag := 7;
  ApplyFluentText(Cap, 13, True);
  Cap.TextSettings.HorzAlign := TTextAlign.Leading;
  if AKey <> '' then
    TrText(Cap, AKey);
end;

function TSettingsForm.AddCheck(AParent: TFmxObject; const AKey: string;
  AChecked: Boolean; AOnChange: TNotifyEvent): TFluentCheckRow;
begin
  Result := TFluentCheckRow.Create(Self);
  Result.Setup(AParent, L(AKey), AChecked);
  Result.OnChange := AOnChange;
  Result.ApplyTheme(FColors);
  TrCheck(Result, AKey);
end;

procedure TSettingsForm.BuildThemeCard(var ACard: TRectangle; AParent: TFmxObject;
  const AKey: string; ATheme: TAppTheme);
var
  Preview, Swatch1, Swatch2, AccentBar: TRectangle;
  Lbl: TText;
  PreviewColors: TThemeColors;
begin
  PreviewColors := GetThemeColors(ATheme);
  ACard := TRectangle.Create(Self);
  ACard.Parent := AParent;
  ACard.Align := TAlignLayout.Left;
  ACard.Width := 148;
  ACard.Margins.Rect := TRectF.Create(0, 0, 12, 0);
  ACard.XRadius := 10;
  ACard.YRadius := 10;
  ACard.Stroke.Kind := TBrushKind.Solid;
  ACard.Stroke.Thickness := 1.5;
  ACard.Fill.Kind := TBrushKind.Solid;
  ACard.Cursor := crHandPoint;
  ACard.HitTest := True;
  ACard.Tag := Ord(ATheme);
  ACard.OnClick := ThemeCardClick;

  Preview := TRectangle.Create(Self);
  Preview.Parent := ACard;
  Preview.Align := TAlignLayout.Top;
  Preview.Height := 72;
  Preview.Margins.Rect := TRectF.Create(8, 0, 8, 0);
  Preview.XRadius := 6;
  Preview.YRadius := 6;
  Preview.Stroke.Kind := TBrushKind.None;
  Preview.Fill.Color := PreviewColors.Background;
  Preview.HitTest := False;
  Preview.ClipChildren := True;

  AccentBar := TRectangle.Create(Self);
  AccentBar.Parent := Preview;
  AccentBar.Align := TAlignLayout.Top;
  AccentBar.Height := 4;
  AccentBar.Stroke.Kind := TBrushKind.None;
  AccentBar.Fill.Color := PreviewColors.SelectionColor;
  AccentBar.HitTest := False;

  Swatch1 := TRectangle.Create(Self);
  Swatch1.Parent := Preview;
  Swatch1.Align := TAlignLayout.Left;
  Swatch1.Width := 52;
  Swatch1.Margins.Rect := TRectF.Create(8, 16, 4, 12);
  Swatch1.XRadius := 4;
  Swatch1.YRadius := 4;
  Swatch1.Stroke.Kind := TBrushKind.None;
  Swatch1.Fill.Color := PreviewColors.CardBackground;
  Swatch1.HitTest := False;

  Swatch2 := TRectangle.Create(Self);
  Swatch2.Parent := Preview;
  Swatch2.Align := TAlignLayout.Client;
  Swatch2.Margins.Rect := TRectF.Create(0, 16, 8, 12);
  Swatch2.XRadius := 4;
  Swatch2.YRadius := 4;
  Swatch2.Stroke.Kind := TBrushKind.None;
  Swatch2.Fill.Color := PreviewColors.CardBackground;
  Swatch2.HitTest := False;

  Lbl := TText.Create(Self);
  Lbl.Parent := ACard;
  Lbl.Align := TAlignLayout.Client;
  Lbl.HitTest := False;
  ApplyFluentText(Lbl, 13, False);
  Lbl.TextSettings.HorzAlign := TTextAlign.Center;
  Lbl.TextSettings.VertAlign := TTextAlign.Center;
  TrText(Lbl, AKey);
end;

procedure TSettingsForm.BuildMaterialCard(var ACard: TRectangle; AParent: TFmxObject;
  const AKey: string; AMaterial: TWindowMaterial; APreview: TAlphaColor);
var
  Preview, Glass: TRectangle;
  Lbl: TText;
begin
  ACard := TRectangle.Create(Self);
  ACard.Parent := AParent;
  ACard.Align := TAlignLayout.Left;
  ACard.Width := 148;
  ACard.Margins.Rect := TRectF.Create(0, 0, 12, 0);
  ACard.XRadius := 10;
  ACard.YRadius := 10;
  ACard.Stroke.Kind := TBrushKind.Solid;
  ACard.Stroke.Thickness := 1.5;
  ACard.Fill.Kind := TBrushKind.Solid;
  ACard.Cursor := crHandPoint;
  ACard.HitTest := True;
  ACard.Tag := Ord(AMaterial);
  ACard.OnClick := MaterialCardClick;

  Preview := TRectangle.Create(Self);
  Preview.Parent := ACard;
  Preview.Align := TAlignLayout.Top;
  Preview.Height := 36;
  Preview.Margins.Rect := TRectF.Create(8, 4, 8, 0);
  Preview.XRadius := 6;
  Preview.YRadius := 6;
  Preview.Stroke.Kind := TBrushKind.None;
  Preview.Fill.Color := APreview;
  Preview.HitTest := False;
  Preview.ClipChildren := True;

  if AMaterial <> wmNormal then
  begin
    Glass := TRectangle.Create(Self);
    Glass.Parent := Preview;
    Glass.Align := TAlignLayout.Client;
    Glass.Margins.Rect := TRectF.Create(10, 8, 10, 8);
    Glass.XRadius := 4;
    Glass.YRadius := 4;
    Glass.Stroke.Kind := TBrushKind.Solid;
    Glass.Stroke.Color := $55FFFFFF;
    Glass.Stroke.Thickness := 1;
    Glass.Fill.Color := $66FFFFFF;
    Glass.HitTest := False;
  end;

  Lbl := TText.Create(Self);
  Lbl.Parent := ACard;
  Lbl.Align := TAlignLayout.Client;
  Lbl.HitTest := False;
  ApplyFluentText(Lbl, 13, False);
  Lbl.TextSettings.HorzAlign := TTextAlign.Center;
  Lbl.TextSettings.VertAlign := TTextAlign.Center;
  TrText(Lbl, AKey);
end;

procedure TSettingsForm.BuildTintCard(AParent: TFmxObject);
var
  I: Integer;
begin
  FTintCard := AddCard(AParent, '');
  for I := 0 to FTintCard.ControlsCount - 1 do
    if (FTintCard.Controls[I] is TText) and (TText(FTintCard.Controls[I]).Tag = 7) then
    begin
      TText(FTintCard.Controls[I]).Visible := False;
      TText(FTintCard.Controls[I]).Height := 0;
    end;
  if Assigned(FSettings) and (FSettings.ColorTint >= 0) then
    FTintHold := FSettings.ColorTint
  else
    FTintHold := 200;
  if Assigned(FSettings) and (FSettings.Transparency > 0) then
    FOpacityHold := FSettings.Transparency
  else
    FOpacityHold := 40;
  FTintHint := TText.Create(Self);
  FTintHint.Parent := FTintCard;
  FTintHint.Align := TAlignLayout.Top;
  FTintHint.Height := 34;
  FTintHint.Margins.Rect := TRectF.Create(0, 4, 0, 0);
  TrText(FTintHint, 'set.tint.hint');
  FTintHint.HitTest := False;
  FTintHint.Tag := 8;
  FTintHint.WordWrap := True;
  ApplyFluentText(FTintHint, 12, False);
  FTintHint.TextSettings.HorzAlign := TTextAlign.Leading;
  FTintHint.TextSettings.VertAlign := TTextAlign.Leading;
  FOpacitySlider := TPaintBox.Create(Self);
  FOpacitySlider.Parent := FTintCard;
  FOpacitySlider.Align := TAlignLayout.Top;
  FOpacitySlider.Height := 36;
  FOpacitySlider.Margins.Rect := TRectF.Create(0, 2, 0, 0);
  FOpacitySlider.Cursor := crHandPoint;
  FOpacitySlider.OnPaint := PaintOpacitySlider;
  FOpacitySlider.OnMouseDown := OpacitySliderDown;
  FOpacitySlider.OnMouseMove := OpacitySliderMove;
  FOpacitySlider.OnMouseUp := OpacitySliderUp;
  FOpacitySlider.OnDblClick := OpacitySliderDblClick;
  FCbOpacity := AddCheck(FTintCard, 'set.opacity',
    Assigned(FSettings) and (FSettings.Transparency > 0), OpacityEnabledClick);
  FOpacitySlider.Visible := False;
  FOpacitySlider.Height := 0;
  FOpacitySlider.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FCbOpacity.Visible := False;
  FCbOpacity.Height := 0;
  FTintSlider := TPaintBox.Create(Self);
  FTintSlider.Parent := FTintCard;
  FTintSlider.Align := TAlignLayout.Top;
  FTintSlider.Height := 36;
  FTintSlider.Margins.Rect := TRectF.Create(0, 2, 0, 0);
  FTintSlider.Cursor := crHandPoint;
  FTintSlider.OnPaint := PaintTintSlider;
  FTintSlider.OnMouseDown := TintSliderDown;
  FTintSlider.OnMouseMove := TintSliderMove;
  FTintSlider.OnMouseUp := TintSliderUp;
  FTintSlider.OnDblClick := TintSliderDblClick;
  FCbTint := AddCheck(FTintCard, 'set.tint',
    Assigned(FSettings) and (FSettings.ColorTint >= 0), TintEnabledClick);
  SyncTintHint;
end;

procedure TSettingsForm.LockTintOrder;
var
  I: Integer;
begin
  if not Assigned(FTintCard) then
    Exit;
  { Align=Top берёт текущий Top, а не порядок детей.
    Меньший Top оказывается выше. Флажок прозрачности — сразу над полоской. }
  FTintCard.BeginUpdate;
  try
    if Assigned(FCbTint) then
      FCbTint.Position.Y := 0;
    if Assigned(FTintSlider) then
      FTintSlider.Position.Y := 10;
    if Assigned(FCbOpacity) then
      FCbOpacity.Position.Y := 20;
    if Assigned(FOpacitySlider) then
      FOpacitySlider.Position.Y := 30;
    if Assigned(FTintHint) then
      FTintHint.Position.Y := 40;
    for I := 0 to FTintCard.ControlsCount - 1 do
      if (FTintCard.Controls[I] is TText) and
         (TText(FTintCard.Controls[I]).Tag = 7) then
        TText(FTintCard.Controls[I]).Position.Y := 80;
  finally
    FTintCard.EndUpdate;
  end;
end;

function HueSwatch(Hue: Single): TAlphaColor;
var
  Rec: TAlphaColorRec;
  Hp, C, X, M, Rf, Gf, Bf, F: Single;
  Sector: Integer;
begin
  Hp := Hue / 60;
  Sector := Trunc(Hp) mod 6;
  if Sector < 0 then
    Sector := Sector + 6;
  F := Hp - Trunc(Hp);
  C := 1;
  if (Sector mod 2) = 0 then
    X := C * F
  else
    X := C * (1 - F);
  M := 0;
  case Sector of
    0: begin Rf := C; Gf := X; Bf := 0; end;
    1: begin Rf := X; Gf := C; Bf := 0; end;
    2: begin Rf := 0; Gf := C; Bf := X; end;
    3: begin Rf := 0; Gf := X; Bf := C; end;
    4: begin Rf := X; Gf := 0; Bf := C; end;
  else
    begin Rf := C; Gf := 0; Bf := X; end;
  end;
  Rec.A := 255;
  Rec.R := EnsureRange(Round((Rf + M) * 255), 0, 255);
  Rec.G := EnsureRange(Round((Gf + M) * 255), 0, 255);
  Rec.B := EnsureRange(Round((Bf + M) * 255), 0, 255);
  Result := Rec.Color;
end;

procedure TSettingsForm.TintTrack(out TrackL, TrackR: Single);
begin
  TrackL := 4;
  TrackR := 48;
  if Assigned(FTintSlider) then
    TrackR := FTintSlider.Width - 52;
  if TrackR < TrackL + 40 then
    TrackR := TrackL + 40;
end;

function TSettingsForm.TintFromSliderX(X: Single): Integer;
var
  TrackL, TrackR: Single;
begin
  TintTrack(TrackL, TrackR);
  Result := EnsureRange(Round((X - TrackL) / (TrackR - TrackL) * 359), 0, 359);
end;

procedure TSettingsForm.PaintTintSlider(Sender: TObject; Canvas: TCanvas);
var
  TrackL, TrackR, ThumbX, MidY: Single;
  Bar, R: TRectF;
  Grad: TGradient;
  Stop: TGradientPoint;
  I: Integer;
  Caption: string;
begin
  if not Assigned(FTintSlider) or not Assigned(FSettings) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.CardBackground;
  Canvas.FillRect(FTintSlider.LocalRect, 0, 0, [], 1);
  TintTrack(TrackL, TrackR);
  MidY := FTintSlider.Height / 2;
  Bar := TRectF.Create(TrackL, MidY - 5, TrackR, MidY + 5);
  Grad := TGradient.Create;
  try
    Grad.Style := TGradientStyle.Linear;
    Grad.StartPosition.X := 0;
    Grad.StartPosition.Y := 0;
    Grad.StopPosition.X := 1;
    Grad.StopPosition.Y := 0;
    Grad.Points.Clear;
    for I := 0 to 6 do
    begin
      Stop := TGradientPoint(Grad.Points.Add);
      Stop.Offset := I / 6;
      Stop.Color := HueSwatch(I * 60);
    end;
    Canvas.Fill.Kind := TBrushKind.Gradient;
    Canvas.Fill.Gradient.Assign(Grad);
  finally
    Grad.Free;
  end;
  Canvas.FillRect(Bar, 4, 4, AllCorners, 1);
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [];
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.SubTextColor;
  if FSettings.ColorTint < 0 then
    Caption := L('set.tint.off')
  else
    Caption := IntToStr(FSettings.ColorTint) + '°';
  R := TRectF.Create(FTintSlider.Width - 46, 0, FTintSlider.Width, FTintSlider.Height);
  Canvas.FillText(R, Caption, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
  if FSettings.ColorTint >= 0 then
  begin
    ThumbX := TrackL + (TrackR - TrackL) * (FSettings.ColorTint / 359);
    Canvas.Fill.Color := $FF1A1A1A;
    Canvas.FillEllipse(TRectF.Create(ThumbX - 8, MidY - 8, ThumbX + 8, MidY + 8), 1);
    Canvas.Fill.Color := HueSwatch(FSettings.ColorTint);
    Canvas.FillEllipse(TRectF.Create(ThumbX - 5, MidY - 5, ThumbX + 5, MidY + 5), 1);
  end;
end;

procedure TSettingsForm.ApplyTintLive(AValue: Integer; ASave: Boolean);
var
  Next: Integer;
  WasPainting, NowPainting: Boolean;
  Plain, Live: TThemeColors;
begin
  if not Assigned(FSettings) then
    Exit;
  if AValue < 0 then
    Next := -1
  else
    Next := EnsureRange(AValue, 0, 359);
  if FSettings.ColorTint = Next then
  begin
    if Assigned(FTintSlider) then
      FTintSlider.Repaint;
    if ASave then
      ScheduleSave;
    Exit;
  end;

  WasPainting := False;
  if FSettings.ColorTint >= 0 then
  begin
    ConfigureThemeTint(FSettings.ColorTint, FSettings.WindowMaterial);
    Plain := GetThemeColors(FSettings.Theme, False);
    Live := GetThemeColors(FSettings.Theme);
    WasPainting := ThemeTintPaintsControls(Live, Plain);
  end;

  FSettings.ColorTint := Next;
  ConfigureThemeTint(Next, FSettings.WindowMaterial);
  Plain := GetThemeColors(FSettings.Theme, False);
  Live := GetThemeColors(FSettings.Theme);
  NowPainting := ThemeTintPaintsControls(Live, Plain);
  if WasPainting or NowPainting then
  begin
    if Assigned(FOnThemeChanged) then
      FOnThemeChanged(FSettings.Theme);
    ApplyTheme(Live);
  end
  else
  begin
    { Оттенок красит только фон. Панели, док и кнопки не трогаем. }
    FColors := Live;
    Fill.Color := Live.Background;
    if Assigned(FContent) then
      FContent.Fill.Color := Live.LayerBackground;
    if Assigned(FOnTintChanged) then
      FOnTintChanged();
    if Assigned(FTintSlider) then
      FTintSlider.Repaint;
  end;
  if Next >= 0 then
    FTintHold := Next;
  SyncTintCheck;
  if ASave then
    ScheduleSave;
end;

procedure TSettingsForm.TintSliderDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  FTintDrag := True;
  if Assigned(FTintSlider) and Assigned(FTintSlider.Root) then
    FTintSlider.Root.Captured := FTintSlider;
  ApplyTintLive(TintFromSliderX(X), False);
end;

procedure TSettingsForm.TintSliderMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if FTintDrag then
    ApplyTintLive(TintFromSliderX(X), False);
end;

procedure TSettingsForm.TintSliderUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  if FTintDrag then
    ApplyTintLive(TintFromSliderX(X), True);
  FTintDrag := False;
  if Assigned(FTintSlider) and Assigned(FTintSlider.Root) and
     Assigned(FTintSlider.Root.Captured) and
     (FTintSlider.Root.Captured.GetObject = FTintSlider) then
    FTintSlider.Root.Captured := nil;
end;

procedure TSettingsForm.TintSliderDblClick(Sender: TObject);
begin
  FTintDrag := False;
  ApplyTintLive(-1, True);
end;

procedure TSettingsForm.TintEnabledClick(Sender: TObject);
begin
  if FTintSync or not Assigned(FSettings) or not Assigned(FCbTint) then
    Exit;
  if FCbTint.Checked then
  begin
    if FSettings.ColorTint < 0 then
    begin
      if (FTintHold < 0) or (FTintHold > 359) then
        FTintHold := 200;
      ApplyTintLive(FTintHold, True);
    end;
  end
  else if FSettings.ColorTint >= 0 then
  begin
    FTintHold := FSettings.ColorTint;
    ApplyTintLive(-1, True);
  end;
end;

procedure TSettingsForm.SyncTintCheck;
begin
  if not Assigned(FCbTint) or not Assigned(FSettings) then
    Exit;
  FTintSync := True;
  try
    FCbTint.Checked := FSettings.ColorTint >= 0;
  finally
    FTintSync := False;
  end;
end;

procedure TSettingsForm.SyncTintHint;
var
  ShowHint: Boolean;
begin
  if not Assigned(FTintCard) then
    Exit;
  ShowHint := Assigned(FSettings) and (FSettings.WindowMaterial <> wmNormal);
  if Assigned(FTintHint) then
  begin
    FTintHint.Visible := ShowHint;
    if ShowHint then
    begin
      FTintHint.Height := 34;
      FTintHint.Margins.Rect := TRectF.Create(0, 4, 0, 0);
    end
    else
    begin
      FTintHint.Height := 0;
      FTintHint.Margins.Rect := TRectF.Create(0, 0, 0, 0);
    end;
  end;
  if ShowHint then
    FTintCard.Height := 124
  else
    FTintCard.Height := 86;
  if Assigned(FTintSlider) then
    FTintSlider.Repaint;
  if Assigned(FOpacitySlider) then
    FOpacitySlider.Repaint;
  LockTintOrder;
end;

procedure TSettingsForm.OpacityTrack(out TrackL, TrackR: Single);
begin
  TrackL := 4;
  TrackR := 48;
  if Assigned(FOpacitySlider) then
    TrackR := FOpacitySlider.Width - 52;
  if TrackR < TrackL + 40 then
    TrackR := TrackL + 40;
end;

function TSettingsForm.OpacityFromSliderX(X: Single): Integer;
var
  TrackL, TrackR: Single;
begin
  OpacityTrack(TrackL, TrackR);
  Result := EnsureRange(Round((X - TrackL) / (TrackR - TrackL) * 100), 0, 100);
end;

procedure TSettingsForm.PaintOpacitySlider(Sender: TObject; Canvas: TCanvas);
var
  TrackL, TrackR, ThumbX, MidY: Single;
  Bar, R: TRectF;
  Grad: TGradient;
  Stop: TGradientPoint;
  Caption: string;
begin
  if not Assigned(FOpacitySlider) or not Assigned(FSettings) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.CardBackground;
  Canvas.FillRect(FOpacitySlider.LocalRect, 0, 0, [], 1);
  OpacityTrack(TrackL, TrackR);
  MidY := FOpacitySlider.Height / 2;
  Bar := TRectF.Create(TrackL, MidY - 5, TrackR, MidY + 5);
  Grad := TGradient.Create;
  try
    Grad.Style := TGradientStyle.Linear;
    Grad.StartPosition.X := 0;
    Grad.StartPosition.Y := 0;
    Grad.StopPosition.X := 1;
    Grad.StopPosition.Y := 0;
    Grad.Points.Clear;
    Stop := TGradientPoint(Grad.Points.Add);
    Stop.Offset := 0;
    Stop.Color := ThemeAdjustAlpha(FColors.TextColor, 230);
    Stop := TGradientPoint(Grad.Points.Add);
    Stop.Offset := 1;
    Stop.Color := ThemeAdjustAlpha(FColors.TextColor, 28);
    Canvas.Fill.Kind := TBrushKind.Gradient;
    Canvas.Fill.Gradient.Assign(Grad);
  finally
    Grad.Free;
  end;
  Canvas.FillRect(Bar, 4, 4, AllCorners, 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := FColors.CardStroke;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(Bar, 4, 4, AllCorners, 1);
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [];
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.SubTextColor;
  if FSettings.Transparency <= 0 then
    Caption := L('set.opacity.off')
  else
    Caption := IntToStr(FSettings.Transparency) + '%';
  R := TRectF.Create(FOpacitySlider.Width - 46, 0, FOpacitySlider.Width, FOpacitySlider.Height);
  Canvas.FillText(R, Caption, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
  if FSettings.Transparency > 0 then
  begin
    ThumbX := TrackL + (TrackR - TrackL) * (FSettings.Transparency / 100);
    Canvas.Fill.Color := $FF1A1A1A;
    Canvas.FillEllipse(TRectF.Create(ThumbX - 8, MidY - 8, ThumbX + 8, MidY + 8), 1);
    Canvas.Fill.Color := FColors.TextColor;
    Canvas.FillEllipse(TRectF.Create(ThumbX - 5, MidY - 5, ThumbX + 5, MidY + 5), 1);
  end;
end;

procedure TSettingsForm.ApplyOpacityLive(AValue: Integer; ASave: Boolean);
var
  Next: Integer;
begin
  if not Assigned(FSettings) then
    Exit;
  if AValue <= 0 then
    Next := 0
  else
    Next := EnsureRange(AValue, 1, 100);
  if FSettings.Transparency = Next then
  begin
    if Assigned(FOpacitySlider) then
      FOpacitySlider.Repaint;
    if ASave then
      ScheduleSave;
    Exit;
  end;

  FSettings.Transparency := Next;
  ConfigureWindowOpacity(Next);
  if Next > 0 then
    FOpacityHold := Next;
  SyncOpacityCheck;
  if Assigned(FOpacitySlider) then
    FOpacitySlider.Repaint;
  if FSettings.WindowMaterial = wmNormal then
  begin
    if Assigned(FOnOpacityChanged) then
      FOnOpacityChanged()
    else if Assigned(FOnThemeChanged) then
      FOnThemeChanged(FSettings.Theme);
  end
  else if Assigned(FOnThemeChanged) then
    FOnThemeChanged(FSettings.Theme);
  if ASave then
    ScheduleSave;
end;

procedure TSettingsForm.OpacitySliderDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  FOpacityDrag := True;
  if Assigned(FOpacitySlider) and Assigned(FOpacitySlider.Root) then
    FOpacitySlider.Root.Captured := FOpacitySlider;
  ApplyOpacityLive(OpacityFromSliderX(X), False);
end;

procedure TSettingsForm.OpacitySliderMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if FOpacityDrag then
    ApplyOpacityLive(OpacityFromSliderX(X), False);
end;

procedure TSettingsForm.OpacitySliderUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  if FOpacityDrag then
    ApplyOpacityLive(OpacityFromSliderX(X), True);
  FOpacityDrag := False;
  if Assigned(FOpacitySlider) and Assigned(FOpacitySlider.Root) and
     Assigned(FOpacitySlider.Root.Captured) and
     (FOpacitySlider.Root.Captured.GetObject = FOpacitySlider) then
    FOpacitySlider.Root.Captured := nil;
end;

procedure TSettingsForm.OpacitySliderDblClick(Sender: TObject);
begin
  FOpacityDrag := False;
  ApplyOpacityLive(0, True);
end;

procedure TSettingsForm.OpacityEnabledClick(Sender: TObject);
begin
  if FOpacitySync or not Assigned(FSettings) or not Assigned(FCbOpacity) then
    Exit;
  if FCbOpacity.Checked then
  begin
    if FSettings.Transparency <= 0 then
    begin
      if (FOpacityHold <= 0) or (FOpacityHold > 100) then
        FOpacityHold := 40;
      ApplyOpacityLive(FOpacityHold, True);
    end;
  end
  else if FSettings.Transparency > 0 then
  begin
    FOpacityHold := FSettings.Transparency;
    ApplyOpacityLive(0, True);
  end;
end;

procedure TSettingsForm.SyncOpacityCheck;
begin
  if not Assigned(FCbOpacity) or not Assigned(FSettings) then
    Exit;
  FOpacitySync := True;
  try
    FCbOpacity.Checked := FSettings.Transparency > 0;
  finally
    FOpacitySync := False;
  end;
end;

procedure TSettingsForm.BuildNav;
const
  Keys: array[0..3] of string = (
    'set.nav.general', 'set.nav.view', 'set.nav.ops', 'set.nav.lang');
  Icons: array[0..3] of string = ('', '', #$E8C8, #$E774);
var
  I: Integer;
begin
  FNav := TRectangle.Create(Self);
  FNav.Parent := FBody;
  FNav.Align := TAlignLayout.Left;
  FNav.Width := 232;
  FNav.XRadius := 10;
  FNav.YRadius := 10;
  FNav.Stroke.Kind := TBrushKind.Solid;
  FNav.Fill.Kind := TBrushKind.Solid;
  FNav.Margins.Rect := TRectF.Create(0, 0, 12, 0);
  FNav.Padding.Rect := TRectF.Create(8, 10, 8, 10);

  FNavStack := TLayout.Create(Self);
  FNavStack.Parent := FNav;
  FNavStack.Align := TAlignLayout.Top;
  FNavStack.Height := 4 * 44;

  for I := 0 to 3 do
  begin
    FNavBtns[I] := CreateFluentButton(Self, FNavStack, Icons[I], L(Keys[I]),
      fbkSubtle, 212, NavClick);
    FNavBtns[I].Align := TAlignLayout.Top;
    FNavBtns[I].Height := 40;
    FNavBtns[I].Tag := I;
    FNavBtns[I].Margins.Rect := TRectF.Create(0, 0, 0, 4);
    TrButton(FNavBtns[I], Keys[I]);
  end;
end;

procedure TSettingsForm.BuildPages;
var
  Card, Row: TRectangle;
  Hint: TText;
begin
  FContent := TRectangle.Create(Self);
  FContent.Parent := FBody;
  FContent.Align := TAlignLayout.Client;
  FContent.XRadius := 10;
  FContent.YRadius := 10;
  FContent.Stroke.Kind := TBrushKind.Solid;
  FContent.Fill.Kind := TBrushKind.Solid;

  FPages[0] := AddPage;
  FPages[1] := AddPage;
  FPages[2] := AddPage;
  FPages[3] := AddPage;

  { Список в карточке идёт снизу вверх: последний пункт оказывается сверху. }
  Card := AddCard(FPages[0], 'set.card.ui');
  Card.Height := 22 + 7 * 36 + 16;
  FCbCmd := AddCheck(Card, 'set.ui.cmdline', FSettings.ShowCommandLine, OptionChanged);
  FCbFn := AddCheck(Card, 'set.ui.fn', FSettings.ShowFnBar, OptionChanged);
  FCbQuick := AddCheck(Card, 'set.ui.viewbtns', FSettings.ShowQuickAccess, OptionChanged);
  FCbDriveHome := AddCheck(Card, 'set.ui.drivehome', FSettings.ShowDriveHome, OptionChanged);
  FCbDriveHome.Visible := False;
  FCbDriveHome.Height := 0;
  FCbNetwork := AddCheck(Card, 'set.ui.network', FSettings.ShowNetworkButton, OptionChanged);
  FCbDrives := AddCheck(Card, 'set.ui.drives', FSettings.ShowDriveBar, OptionChanged);
  FCbMid := AddCheck(Card, 'set.ui.mid', FSettings.ShowMidBar, OptionChanged);
  FCbDock := AddCheck(Card, 'set.ui.dock', FSettings.ShowDock, OptionChanged);

  Card := AddCard(FPages[0], 'set.card.behavior');
  Card.Height := 22 + 4 * 36 + 16;
  FCbFolderSize := AddCheck(Card, 'set.beh.foldersize', FSettings.ShowFolderSizes, OptionChanged);
  FCbHidden := AddCheck(Card, 'set.beh.hidden', FSettings.ShowHiddenFiles, OptionChanged);
  FCbSingleInstance := AddCheck(Card, 'set.beh.single', FSettings.SingleInstance, OptionChanged);
  FCbAutoStart := AddCheck(Card, 'set.beh.autorun', FSettings.AutoStart, OptionChanged);

  Card := AddCard(FPages[0], 'set.card.tabs');
  Card.Height := 22 + 2 * 36 + 16;
  FCbEqualTabs := AddCheck(Card, 'set.tabs.equal', FSettings.EqualTabWidth, OptionChanged);
  FCbTabIcons := AddCheck(Card, 'set.tabs.icons', FSettings.ShowTabIcons, OptionChanged);

  Card := AddCard(FPages[0], 'set.card.dock');
  Card.Height := 22 + 4 * 36 + 16;
  FCbDockSeps := AddCheck(Card, 'set.dock.seps', FSettings.DockShowSeparators, OptionChanged);
  FCbDockFree := AddCheck(Card, 'set.dock.free', FSettings.DockAlign = daFree, DockAlignClick);
  FCbDockCenter := AddCheck(Card, 'set.dock.center', FSettings.DockAlign = daCenter, DockAlignClick);
  FCbDockLeft := AddCheck(Card, 'set.dock.left', FSettings.DockAlign = daLeft, DockAlignClick);

  Card := AddCard(FPages[0], 'set.card.select');
  Card.Height := 22 + 2 * 36 + 16;
  FCbSelVibe := AddCheck(Card, 'set.sel.vibe',
    FSettings.MouseSelectMode <> msmExplorer, MouseModeClick);
  FCbSelExplorer := AddCheck(Card, 'set.sel.explorer',
    FSettings.MouseSelectMode = msmExplorer, MouseModeClick);

  Card := AddCard(FPages[0], 'set.card.view');
  Card.Height := 22 + 36 + 16;
  FCbFollow := AddCheck(Card, 'set.view.follow',
    FSettings.FollowCursor, OptionChanged);

  { --- Вид и темы --- }
  Card := AddCard(FPages[1], 'set.card.theme');
  Card.Height := 22 + 126 + 12;
  Row := TRectangle.Create(Self);
  Row.Parent := Card;
  Row.Align := TAlignLayout.Top;
  Row.Height := 126;
  Row.Stroke.Kind := TBrushKind.None;
  Row.Fill.Color := TAlphaColors.Null;
  BuildThemeCard(FCardSystem, Row, 'set.theme.system', atSystem);
  BuildThemeCard(FCardLight, Row, 'set.theme.light', atLight);
  BuildThemeCard(FCardDark, Row, 'set.theme.dark', atDark);

  BuildTintCard(FPages[1]);

  if WindowsVersion >= 11 then
  begin
    Card := AddCard(FPages[1], 'set.card.material');
    Card.Height := 22 + 78 + 12;
    Row := TRectangle.Create(Self);
    Row.Parent := Card;
    Row.Align := TAlignLayout.Top;
    Row.Height := 78;
    Row.Stroke.Kind := TBrushKind.None;
    Row.Fill.Color := TAlphaColors.Null;
    BuildMaterialCard(FCardMatNormal, Row, 'set.mat.normal', wmNormal, $FF3B3B3B);
    BuildMaterialCard(FCardMatAcrylic, Row, 'set.mat.acrylic', wmAcrylic, $FF5A7A9A);
    BuildMaterialCard(FCardMatMica, Row, 'set.mat.mica', wmMica, $FF4A5560);
  end
  else
  begin
    FCardMatNormal := nil;
    FCardMatAcrylic := nil;
    FCardMatMica := nil;
  end;

  Card := AddCard(FPages[1], 'set.card.font');
  Card.Height := 22 + 40 + 16;
  Hint := TText.Create(Self);
  Hint.Parent := Card;
  Hint.Align := TAlignLayout.Top;
  Hint.Height := 20;
  Hint.HitTest := False;
  Hint.Tag := 8;
  ApplyFluentText(Hint, 12, False);
  TrText(Hint, 'set.font.size');
  FFontSizeEdit := CreateFluentEdit(Self, Card);
  FFontSizeEdit.Align := TAlignLayout.Top;
  FFontSizeEdit.Height := 32;
  FFontSizeEdit.FillMode := fefSubtle;
  FFontSizeEdit.Text := IntToStr(FSettings.ListFontSize);
  FFontSizeEdit.OnChange := OptionChanged;

  Card := AddCard(FPages[2], 'set.card.ops');
  Card.Height := 22 + 3 * 36 + 16;
  FCbOpVibe := AddCheck(Card, 'set.ops.vibe', FSettings.FileOpMode = fomVibe, FileOpModeClick);
  FCbOpExplorer := AddCheck(Card, 'set.ops.explorer', FSettings.FileOpMode = fomExplorer, FileOpModeClick);
  FCbOpQuiet := AddCheck(Card, 'set.ops.quiet', FSettings.FileOpMode = fomQuiet, FileOpModeClick);

  FLangCard := AddCard(FPages[3], 'lang.title');
  FLangRows := TList<TFluentCheckRow>.Create;
  RebuildLangPage;
end;

procedure TSettingsForm.BuildUI;
begin
  FRoot := TLayout.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Padding.Rect := TRectF.Create(18, 14, 18, 14);

  FFooter := TLayout.Create(Self);
  FFooter.Parent := FRoot;
  FFooter.Align := TAlignLayout.Bottom;
  FFooter.Height := 40;
  FFooter.Margins.Top := 10;
  FBtnClose := CreateFluentButton(Self, FFooter, '', L('set.close'), fbkAccent, 120, CloseClick);
  TrButton(FBtnClose, 'set.close');
  FBtnClose.Align := TAlignLayout.Right;
  FBtnClose.Margins.Rect := TRectF.Create(0, 0, 0, 0);

  FBody := TLayout.Create(Self);
  FBody.Parent := FRoot;
  FBody.Align := TAlignLayout.Client;

  BuildNav;
  BuildPages;
end;

procedure TSettingsForm.NavClick(Sender: TObject);
begin
  if Sender is TFluentButton then
    ShowPage(TFluentButton(Sender).Tag);
end;

procedure TSettingsForm.ShowPage(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FPages)) then
    Exit;
  if AIndex = 3 then
    RebuildLangPage;
  FPage := AIndex;
  for I := 0 to High(FPages) do
  begin
    FPages[I].Visible := I = AIndex;
    FNavBtns[I].SetSelected(I = AIndex);
  end;
end;

function TSettingsForm.ThemeOfCard(ACard: TRectangle): TAppTheme;
begin
  Result := TAppTheme(ACard.Tag);
end;

procedure TSettingsForm.UpdateThemeCards;
  procedure StyleCard(ACard: TRectangle);
  var
    Selected: Boolean;
    I, J: Integer;
    PreviewColors: TThemeColors;
    Child: TFmxObject;
    Prev, Bar: TRectangle;
  begin
    if ACard = nil then
      Exit;
    Selected := ThemeOfCard(ACard) = FSettings.Theme;
    PreviewColors := GetThemeColors(ThemeOfCard(ACard));
    if Selected then
    begin
      ACard.Stroke.Color := FColors.SelectionColor;
      ACard.Stroke.Thickness := 2;
      ACard.Fill.Color := FColors.AccentSubtle;
    end
    else
    begin
      ACard.Stroke.Color := FColors.CardStroke;
      ACard.Stroke.Thickness := 1;
      ACard.Fill.Color := FColors.CardBackground;
    end;
    for I := 0 to ACard.ControlsCount - 1 do
    begin
      Child := ACard.Controls[I];
      if Child is TText then
        TText(Child).TextSettings.FontColor := FColors.TextColor
      else if Child is TRectangle then
      begin
        Prev := TRectangle(Child);
        Prev.Fill.Color := PreviewColors.Background;
        for J := 0 to Prev.ControlsCount - 1 do
          if Prev.Controls[J] is TRectangle then
          begin
            Bar := TRectangle(Prev.Controls[J]);
            if Bar.Align = TAlignLayout.Top then
              Bar.Fill.Color := PreviewColors.SelectionColor
            else
              Bar.Fill.Color := PreviewColors.CardBackground;
          end;
      end;
    end;
  end;
begin
  StyleCard(FCardSystem);
  StyleCard(FCardLight);
  StyleCard(FCardDark);
end;

procedure TSettingsForm.UpdateMaterialCards;
  procedure StyleCard(ACard: TRectangle);
  var
    Selected: Boolean;
    I: Integer;
  begin
    if ACard = nil then
      Exit;
    Selected := TWindowMaterial(ACard.Tag) = FSettings.WindowMaterial;
    if Selected then
    begin
      ACard.Stroke.Color := FColors.SelectionColor;
      ACard.Stroke.Thickness := 2;
      ACard.Fill.Color := FColors.AccentSubtle;
    end
    else
    begin
      ACard.Stroke.Color := FColors.CardStroke;
      ACard.Stroke.Thickness := 1;
      ACard.Fill.Color := FColors.CardBackground;
    end;
    for I := 0 to ACard.ControlsCount - 1 do
      if ACard.Controls[I] is TText then
        TText(ACard.Controls[I]).TextSettings.FontColor := FColors.TextColor;
  end;
begin
  StyleCard(FCardMatNormal);
  StyleCard(FCardMatAcrylic);
  StyleCard(FCardMatMica);
end;

procedure TSettingsForm.ThemeCardClick(Sender: TObject);
var
  NewTheme: TAppTheme;
begin
  if not (Sender is TRectangle) then
    Exit;
  NewTheme := TAppTheme(TRectangle(Sender).Tag);
  FSettings.Theme := NewTheme;
  ScheduleSave;
  if Assigned(FOnThemeChanged) then
    FOnThemeChanged(NewTheme);
  ApplyTheme(GetThemeColors(NewTheme));
end;

procedure TSettingsForm.MaterialCardClick(Sender: TObject);
begin
  if not (Sender is TRectangle) then
    Exit;
  FSettings.WindowMaterial := TWindowMaterial(TRectangle(Sender).Tag);
  if FSettings.WindowMaterial = wmNormal then
    FSettings.Transparency := 0
  else
    FSettings.Transparency := 100;
  ConfigureThemeTint(FSettings.ColorTint, FSettings.WindowMaterial);
  ConfigureWindowOpacity(FSettings.Transparency);
  ScheduleSave;
  UpdateMaterialCards;
  SyncTintHint;
  { Материал влияет на chrome главного окна — обновляем тему, не весь layout. }
  if Assigned(FOnThemeChanged) then
    FOnThemeChanged(FSettings.Theme)
  else if Assigned(FOnOptionsChanged) then
    FOnOptionsChanged([saBands, saPanels, saBehavior, saFileOp]);
  ApplyTheme(GetThemeColors(FSettings.Theme));
end;

procedure TSettingsForm.CollectFromUI;
var
  N: Integer;
begin
  FSettings.ShowDock := FCbDock.Checked;
  FSettings.ShowMidBar := FCbMid.Checked;
  FSettings.ShowDriveBar := FCbDrives.Checked;
  FSettings.ShowDriveHome := FCbDriveHome.Checked;
  FSettings.ShowFnBar := FCbFn.Checked;
  FSettings.ShowQuickAccess := FCbQuick.Checked;
  FSettings.ShowCommandLine := FCbCmd.Checked;
  FSettings.FollowCursor := FCbFollow.Checked;
  if FCbSelExplorer.Checked then
    FSettings.MouseSelectMode := msmExplorer
  else
    FSettings.MouseSelectMode := msmVibe;
  FSettings.ShowNetworkButton := FCbNetwork.Checked;
  FSettings.ShowHiddenFiles := FCbHidden.Checked;
  FSettings.ShowFolderSizes := FCbFolderSize.Checked;
  FSettings.AutoStart := FCbAutoStart.Checked;
  FSettings.SingleInstance := FCbSingleInstance.Checked;
  FSettings.ShowTabIcons := FCbTabIcons.Checked;
  FSettings.EqualTabWidth := FCbEqualTabs.Checked;
  FSettings.DockShowSeparators := FCbDockSeps.Checked;
  if FCbDockFree.Checked then
    FSettings.DockAlign := daFree
  else if FCbDockCenter.Checked then
    FSettings.DockAlign := daCenter
  else
    FSettings.DockAlign := daLeft;
  if FCbOpQuiet.Checked then
    FSettings.FileOpMode := fomQuiet
  else if FCbOpExplorer.Checked then
    FSettings.FileOpMode := fomExplorer
  else
    FSettings.FileOpMode := fomVibe;
  N := StrToIntDef(Trim(FFontSizeEdit.Text), FSettings.ListFontSize);
  FSettings.ListFontSize := EnsureRange(N, 10, 22);
end;

procedure TSettingsForm.MouseModeClick(Sender: TObject);
begin
  if Sender = FCbSelExplorer then
  begin
    FCbSelExplorer.Checked := True;
    FCbSelVibe.Checked := False;
  end
  else
  begin
    FCbSelExplorer.Checked := False;
    FCbSelVibe.Checked := True;
  end;
  OptionChanged(Sender);
end;

procedure TSettingsForm.RebuildLangPage;
var
  Langs: TArray<TLangChoice>;
  I, N: Integer;
  Row: TFluentCheckRow;
  Saved: string;
begin
  if (FLangCard = nil) or (FLangRows = nil) then
    Exit;
  while FLangRows.Count > 0 do
  begin
    Row := FLangRows[0];
    FLangRows.Delete(0);
    Row.Parent := nil;
    Row.Free;
  end;
  Saved := 'system';
  if Assigned(FSettings) then
    Saved := FSettings.Language;
  Langs := AvailableLanguages;
  N := Length(Langs) + 1;
  FLangCard.Height := 22 + N * 36 + 16;
  { Align=Top: первый добавленный оказывается снизу. }
  Row := TFluentCheckRow.Create(Self);
  Row.Setup(FLangCard, L('lang.system'), SameText(Saved, 'system'));
  Row.TagString := 'system';
  Row.OnChange := LangClick;
  Row.ApplyTheme(FColors);
  FLangRows.Add(Row);
  for I := High(Langs) downto 0 do
  begin
    Row := TFluentCheckRow.Create(Self);
    Row.Setup(FLangCard, Langs[I].Name, SameText(Saved, Langs[I].Code));
    Row.TagString := Langs[I].Code;
    Row.OnChange := LangClick;
    Row.ApplyTheme(FColors);
    FLangRows.Add(Row);
  end;
end;

procedure TSettingsForm.ApplyLanguage;
var
  I: Integer;
  Saved: string;
begin
  if Assigned(FTintSlider) then
    FTintSlider.Repaint;
  { Карточки и пункты меню обновляет uLangBind. Здесь только «как в системе»:
    имя берётся из текущего словаря, а названия языков — из их файлов. }
  if (FLangRows = nil) or (FLangRows.Count = 0) then
    Exit;
  Saved := 'system';
  if Assigned(FSettings) then
    Saved := FSettings.Language;
  for I := 0 to FLangRows.Count - 1 do
    if SameText(FLangRows[I].TagString, 'system') then
      FLangRows[I].SetCaption(L('lang.system'));
  for I := 0 to FLangRows.Count - 1 do
    FLangRows[I].Checked := SameText(FLangRows[I].TagString, Saved);
end;

procedure TSettingsForm.LangClick(Sender: TObject);
var
  Code: string;
  I: Integer;
begin
  if not (Sender is TFluentCheckRow) then
    Exit;
  Code := TFluentCheckRow(Sender).TagString;
  if Code = '' then
    Exit;
  if FLangRows <> nil then
    for I := 0 to FLangRows.Count - 1 do
      FLangRows[I].Checked := SameText(FLangRows[I].TagString, Code);
  if not Assigned(FSettings) or SameText(FSettings.Language, Code) then
    Exit;
  FSettings.Language := Code;
  SetLanguage(Code);
  ApplyLanguage;
  if Assigned(FOnLanguageChanged) then
    FOnLanguageChanged();
  ScheduleSave;
end;

procedure TSettingsForm.FileOpModeClick(Sender: TObject);
begin
  if Sender = FCbOpQuiet then
  begin
    FCbOpQuiet.Checked := True;
    FCbOpExplorer.Checked := False;
    FCbOpVibe.Checked := False;
  end
  else if Sender = FCbOpExplorer then
  begin
    FCbOpQuiet.Checked := False;
    FCbOpExplorer.Checked := True;
    FCbOpVibe.Checked := False;
  end
  else if Sender = FCbOpVibe then
  begin
    FCbOpQuiet.Checked := False;
    FCbOpExplorer.Checked := False;
    FCbOpVibe.Checked := True;
  end;
  OptionChanged(Sender);
end;

procedure TSettingsForm.DockAlignClick(Sender: TObject);
begin
  if Sender = FCbDockLeft then
  begin
    FCbDockLeft.Checked := True;
    FCbDockCenter.Checked := False;
    FCbDockFree.Checked := False;
  end
  else if Sender = FCbDockCenter then
  begin
    FCbDockLeft.Checked := False;
    FCbDockCenter.Checked := True;
    FCbDockFree.Checked := False;
  end
  else if Sender = FCbDockFree then
  begin
    FCbDockLeft.Checked := False;
    FCbDockCenter.Checked := False;
    FCbDockFree.Checked := True;
  end;
  OptionChanged(Sender);
end;

procedure TSettingsForm.ScheduleSave;
begin
  if Assigned(FSettings) then
    FSettings.MarkPrefsDirty;
  if not Assigned(FSaveTimer) then
  begin
    if Assigned(FSettings) then
      FSettings.SaveAsync;
    Exit;
  end;
  FSaveTimer.Enabled := False;
  FSaveTimer.Enabled := True;
end;

procedure TSettingsForm.SaveTimerTick(Sender: TObject);
begin
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;
  if Assigned(FSettings) then
    FSettings.SaveAsync;
end;

procedure TSettingsForm.OptionChanged(Sender: TObject);
type
  TUiSnap = record
    ShowDock, ShowMidBar, ShowFnBar, ShowCommandLine: Boolean;
    DockShowSeparators: Boolean;
    DockAlign: TDockAlign;
    ShowDriveBar, ShowDriveHome, ShowQuickAccess, ShowNetworkButton: Boolean;
    ShowTabIcons, EqualTabWidth, ShowHiddenFiles, ShowFolderSizes: Boolean;
    MouseSelectMode: TMouseSelectMode;
    ListFontSize: Integer;
    AutoStart, SingleInstance: Boolean;
    FileOpMode: TFileOpMode;
  end;

  function Snap: TUiSnap;
  begin
    Result.ShowDock := FSettings.ShowDock;
    Result.ShowMidBar := FSettings.ShowMidBar;
    Result.ShowFnBar := FSettings.ShowFnBar;
    Result.ShowCommandLine := FSettings.ShowCommandLine;
    Result.DockShowSeparators := FSettings.DockShowSeparators;
    Result.DockAlign := FSettings.DockAlign;
    Result.ShowDriveBar := FSettings.ShowDriveBar;
    Result.ShowDriveHome := FSettings.ShowDriveHome;
    Result.ShowQuickAccess := FSettings.ShowQuickAccess;
    Result.ShowNetworkButton := FSettings.ShowNetworkButton;
    Result.ShowTabIcons := FSettings.ShowTabIcons;
    Result.EqualTabWidth := FSettings.EqualTabWidth;
    Result.ShowHiddenFiles := FSettings.ShowHiddenFiles;
    Result.ShowFolderSizes := FSettings.ShowFolderSizes;
    Result.MouseSelectMode := FSettings.MouseSelectMode;
    Result.ListFontSize := FSettings.ListFontSize;
    Result.AutoStart := FSettings.AutoStart;
    Result.SingleInstance := FSettings.SingleInstance;
    Result.FileOpMode := FSettings.FileOpMode;
  end;

  function Diff(const A, B: TUiSnap): TSettingsApplySet;
  begin
    Result := [];
    if (A.ShowDock <> B.ShowDock) or (A.ShowMidBar <> B.ShowMidBar) or
       (A.ShowFnBar <> B.ShowFnBar) or (A.ShowCommandLine <> B.ShowCommandLine) or
       (A.DockAlign <> B.DockAlign) or
       (A.DockShowSeparators <> B.DockShowSeparators) then
      Include(Result, saBands);
    { Диски и кнопки вида живут в панели, не в полосах формы. }
    if (A.ShowDriveBar <> B.ShowDriveBar) or (A.ShowDriveHome <> B.ShowDriveHome) or
       (A.ShowQuickAccess <> B.ShowQuickAccess) or
       (A.ShowNetworkButton <> B.ShowNetworkButton) or
       (A.ShowTabIcons <> B.ShowTabIcons) or (A.EqualTabWidth <> B.EqualTabWidth) or
       (A.ShowHiddenFiles <> B.ShowHiddenFiles) or
       (A.ShowFolderSizes <> B.ShowFolderSizes) or
       (A.MouseSelectMode <> B.MouseSelectMode) or
       (A.ListFontSize <> B.ListFontSize) then
      Include(Result, saPanels);
    if (A.AutoStart <> B.AutoStart) or (A.SingleInstance <> B.SingleInstance) then
      Include(Result, saBehavior);
    if A.FileOpMode <> B.FileOpMode then
      Include(Result, saFileOp);
  end;

var
  Apply: TSettingsApplySet;
begin
  if not Assigned(FSettings) then
    Exit;
  var Before := Snap;
  CollectFromUI;
  ScheduleSave;
  Apply := Diff(Before, Snap);
  if (Apply <> []) and Assigned(FOnOptionsChanged) then
    FOnOptionsChanged(Apply);
end;

procedure TSettingsForm.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TSettingsForm.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    Key := 0;
    Close;
    Exit;
  end;
  inherited;
end;

destructor TSettingsForm.Destroy;
begin
  { «Закрыть» само не пишет. Таймер 350 мс мог ещё не сработать — дописать здесь. }
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;
  if Assigned(FSettings) then
  try
    FSettings.FlushPrefs;
  except
  end;
  FreeAndNil(FLangRows);
  inherited;
end;

procedure TSettingsForm.ApplyTheme(const AColors: TThemeColors);
var
  I: Integer;
  procedure PaintCard(ACard: TRectangle);
  var
    J: Integer;
    C: TFmxObject;
  begin
    if ACard = nil then
      Exit;
    ACard.Fill.Color := AColors.CardBackground;
    ACard.Stroke.Color := AColors.CardStroke;
    for J := 0 to ACard.ControlsCount - 1 do
    begin
      C := ACard.Controls[J];
      if (C is TText) and (TText(C).Tag = 7) then
        TText(C).TextSettings.FontColor := AColors.TextColor
      else if (C is TText) and (TText(C).Tag = 8) then
        TText(C).TextSettings.FontColor := AColors.SubTextColor
      else if C is TFluentCheckRow then
        TFluentCheckRow(C).ApplyTheme(AColors);
    end;
  end;
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  ApplyNativeChrome;
  FNav.Fill.Color := AColors.CardBackground;
  FNav.Stroke.Color := AColors.CardStroke;
  FContent.Fill.Color := AColors.LayerBackground;
  FContent.Stroke.Color := AColors.CardStroke;
  FBtnClose.ApplyTheme(AColors);
  for I := 0 to High(FNavBtns) do
    FNavBtns[I].ApplyTheme(AColors);
  if Assigned(FFontSizeEdit) then
    FFontSizeEdit.ApplyTheme(AColors);

  for var P := 0 to High(FPages) do
    if Assigned(FPages[P]) then
      for I := 0 to FPages[P].Content.ControlsCount - 1 do
        if FPages[P].Content.Controls[I] is TRectangle then
          PaintCard(TRectangle(FPages[P].Content.Controls[I]));

  UpdateThemeCards;
  UpdateMaterialCards;
  SyncTintHint;
end;

end.

