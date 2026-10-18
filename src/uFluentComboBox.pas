unit uFluentComboBox;

{
  Fluent-комбо: капсула TFluentEdit, шеврон и свой список.
  Не TComboBox и не VCL.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Graphics, FMX.Layouts, FMX.Effects,
  uThemeManager, uFluentChrome, uFluentEdit;

type
  TFluentComboBox = class(TLayout)
  private
    FFrame: TRectangle;
    FGlyph: TText;
    FEdit: TFluentEdit;
    FPrompt: TText;
    FDropBtn: TRectangle;
    FChevron: TText;
    FPopup: TPopup;
    FListHost: TRectangle;
    FClip: TLayout;
    FList: TLayout;
    FShadow: TShadowEffect;
    FItems: TStringList;
    FItemIndex: Integer;
    FHi: Integer;
    FScroll: Integer;
    FMaxVisible: Integer;
    FBar: TLayout;
    FThumb: TRectangle;
    FBarTimer: TTimer;
    FBarDrag: Boolean;
    FBarDragY: Single;
    FBarDragScroll: Integer;
    FBarThick: Single;
    FBarTrack: Single;
    FBarBusy: Boolean;
    FDropListOnly: Boolean;
    FSuggest: Boolean;
    FSilence: Boolean;
    FTextPrompt: string;
    FFooterCaption: string;
    FGlyphText: string;
    FColors: TThemeColors;
    FOnChange: TNotifyEvent;
    FOnSelChange: TNotifyEvent;
    FOnSubmit: TNotifyEvent;
    FOnDrop: TNotifyEvent;
    FOnEscape: TNotifyEvent;
    FOnFooter: TNotifyEvent;
    FOnClosedWheel: TMouseWheelEvent;
    FOnEditorKey: TKeyEvent;
    FCloseTick: TTimer;
    procedure CloseTick(Sender: TObject);
    procedure ItemsChanged(Sender: TObject);
    procedure EditChanged(Sender: TObject);
    procedure EditSubmit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure EditEnter(Sender: TObject);
    procedure EditExit(Sender: TObject);
    procedure EditMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure EditMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure DropClick(Sender: TObject);
    procedure DropEnter(Sender: TObject);
    procedure DropLeave(Sender: TObject);
    procedure RowDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure RowEnter(Sender: TObject);
    procedure SetText(const AValue: string);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetTextPrompt(const AValue: string);
    procedure SetFooterCaption(const AValue: string);
    procedure SetGlyph(const AValue: string);
    procedure SetDropListOnly(const AValue: Boolean);
    procedure SetFillMode(const AValue: TFluentEditFill);
    function GetText: string;
    function GetFillMode: TFluentEditFill;
    procedure SyncPrompt;
    procedure SyncGlyph;
    procedure RebuildDrop;
    procedure PaintRows;
    procedure ScrollToHi;
    procedure ApplyListY;
    procedure PlaceListBar;
    procedure ListHostResize(Sender: TObject);
    procedure BarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ThumbMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ThumbMouseEnter(Sender: TObject);
    procedure ThumbMouseLeave(Sender: TObject);
    procedure BarTick(Sender: TObject);
    procedure CloseDrop;
    procedure AcceptSource(ASource: Integer);
    function RowCount: Integer;
    function RowSource(ARow: Integer): Integer;
  protected
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure OpenDrop;
    procedure CloseList;
    function IsDropOpen: Boolean;
    procedure FocusEditor;
    function EditorFocused: Boolean;
    property Text: string read GetText write SetText;
    property Items: TStringList read FItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property TextPrompt: string read FTextPrompt write SetTextPrompt;
    property FooterCaption: string read FFooterCaption write SetFooterCaption;
    property Glyph: string read FGlyphText write SetGlyph;
    property DropListOnly: Boolean read FDropListOnly write SetDropListOnly;
    property Suggest: Boolean read FSuggest write FSuggest;
    property FillMode: TFluentEditFill read GetFillMode write SetFillMode;
    property MaxVisible: Integer read FMaxVisible write FMaxVisible;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelChange: TNotifyEvent read FOnSelChange write FOnSelChange;
    property OnSubmit: TNotifyEvent read FOnSubmit write FOnSubmit;
    property OnDrop: TNotifyEvent read FOnDrop write FOnDrop;
    property OnEscape: TNotifyEvent read FOnEscape write FOnEscape;
    property OnFooter: TNotifyEvent read FOnFooter write FOnFooter;
    property OnClosedWheel: TMouseWheelEvent read FOnClosedWheel write FOnClosedWheel;
    property OnEditorKey: TKeyEvent read FOnEditorKey write FOnEditorKey;
  end;

implementation

uses
  FMX.Forms, Winapi.Windows;

const
  RowH = 28;
  BarW = 10;
  DropShadowL = 14;
  DropShadowT = 10;
  DropShadowR = 14;
  DropShadowB = 16;

type
  TComboDropPopup = class(TPopup)
  protected
    procedure ApplyStyle; override;
  end;

procedure TComboDropPopup.ApplyStyle;
begin
  inherited;
  { Стиль попапа подставляет Padding фона и сдвигает список. }
  Padding.Rect := TRectF.Create(0, 0, 0, 0);
end;

constructor TFluentComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := True;
  FMaxVisible := 8;
  FItemIndex := -1;
  FHi := -1;
  FScroll := 0;
  FSuggest := False;
  FDropListOnly := False;
  FColors := GetThemeColors(ActiveAppTheme);

  FFrame := TRectangle.Create(Self);
  FFrame.Parent := Self;
  FFrame.Align := TAlignLayout.Client;
  FFrame.XRadius := 4;
  FFrame.YRadius := 4;
  FFrame.Stroke.Kind := TBrushKind.Solid;
  FFrame.Stroke.Thickness := 1;
  FFrame.Fill.Kind := TBrushKind.Solid;
  FFrame.HitTest := False;
  FFrame.ClipChildren := True;

  FGlyph := TText.Create(Self);
  FGlyph.Parent := FFrame;
  FGlyph.Align := TAlignLayout.Left;
  FGlyph.Width := 0;
  FGlyph.HitTest := False;
  FGlyph.Visible := False;
  FGlyph.TextSettings.Font.Family := FluentIconFamily;
  FGlyph.TextSettings.Font.Size := 12;
  FGlyph.TextSettings.HorzAlign := TTextAlign.Center;
  FGlyph.TextSettings.VertAlign := TTextAlign.Center;

  FDropBtn := TRectangle.Create(Self);
  FDropBtn.Parent := FFrame;
  FDropBtn.Align := TAlignLayout.Right;
  FDropBtn.Width := 28;
  FDropBtn.Fill.Kind := TBrushKind.Solid;
  FDropBtn.Fill.Color := TAlphaColors.Null;
  FDropBtn.Stroke.Kind := TBrushKind.None;
  FDropBtn.HitTest := True;
  FDropBtn.Cursor := crHandPoint;
  FDropBtn.OnClick := DropClick;
  FDropBtn.OnMouseEnter := DropEnter;
  FDropBtn.OnMouseLeave := DropLeave;

  FChevron := TText.Create(Self);
  FChevron.Parent := FDropBtn;
  FChevron.Align := TAlignLayout.Client;
  FChevron.HitTest := False;
  FChevron.Text := #$E70D;
  FChevron.TextSettings.Font.Family := FluentIconFamily;
  FChevron.TextSettings.Font.Size := 10;
  FChevron.TextSettings.HorzAlign := TTextAlign.Center;
  FChevron.TextSettings.VertAlign := TTextAlign.Center;

  FEdit := TFluentEdit.Create(Self);
  FEdit.Parent := FFrame;
  FEdit.Align := TAlignLayout.Client;
  FEdit.FillMode := fefSubtle;
  FEdit.OnChange := EditChanged;
  FEdit.OnSubmit := EditSubmit;
  FEdit.OnKeyDown := EditKeyDown;
  FEdit.OnEnter := EditEnter;
  FEdit.OnExit := EditExit;
  FEdit.OnMouseDown := EditMouseDown;
  FEdit.OnMouseWheel := EditMouseWheel;

  FPrompt := TText.Create(Self);
  FPrompt.Parent := FFrame;
  FPrompt.Align := TAlignLayout.Client;
  FPrompt.HitTest := False;
  FPrompt.Visible := False;
  FPrompt.TextSettings.Font.Family := FluentFontFamily;
  FPrompt.TextSettings.Font.Size := 13;
  FPrompt.TextSettings.HorzAlign := TTextAlign.Leading;
  FPrompt.TextSettings.VertAlign := TTextAlign.Center;
  FPrompt.Margins.Right := 28;

  FItems := TStringList.Create;
  FItems.OnChange := ItemsChanged;

  FCloseTick := TTimer.Create(Self);
  FCloseTick.Interval := 60;
  FCloseTick.Enabled := False;
  FCloseTick.OnTimer := CloseTick;

  FPopup := TComboDropPopup.Create(Self);
  FPopup.Parent := Self;
  FPopup.Padding.Rect := TRectF.Create(0, 0, 0, 0);
  FPopup.BorderWidth := 0;
  { Поле тени слева. Без сдвига карточка стоит правее поля. }
  FPopup.HorizontalOffset := -DropShadowL;
  FPopup.PlacementTarget := Self;
  FPopup.Placement := TPlacement.Bottom;
  FPopup.DragWithParent := True;

  FListHost := TRectangle.Create(Self);
  FListHost.Parent := FPopup;
  FListHost.Align := TAlignLayout.Client;
  FListHost.Margins.Rect := TRectF.Create(DropShadowL, DropShadowT,
    DropShadowR, DropShadowB);
  FListHost.XRadius := 8;
  FListHost.YRadius := 8;
  FListHost.Stroke.Kind := TBrushKind.Solid;
  FListHost.Stroke.Thickness := 1;
  FListHost.Fill.Kind := TBrushKind.Solid;
  FListHost.Padding.Rect := TRectF.Create(4, 4, 4, 4);
  FListHost.ClipChildren := True;

  FShadow := TShadowEffect.Create(FListHost);
  FShadow.Parent := FListHost;
  ApplyFluentShadow(FShadow, FColors.IsDark);

  FClip := TLayout.Create(Self);
  FClip.Parent := FListHost;
  FClip.Align := TAlignLayout.Client;
  FClip.ClipChildren := True;
  FClip.HitTest := False;

  FList := TLayout.Create(Self);
  FList.Parent := FClip;
  FList.Align := TAlignLayout.None;
  FList.HitTest := True;

  { Дорожка справа от строк. Не ребёнок FList: иначе уедет вместе со списком. }
  FBar := TLayout.Create(Self);
  FBar.Parent := FListHost;
  FBar.Align := TAlignLayout.Right;
  FBar.Width := BarW;
  FBar.HitTest := True;
  FBar.Visible := False;
  FBar.ClipChildren := True;
  FBar.OnMouseDown := BarMouseDown;

  FThumb := TRectangle.Create(Self);
  FThumb.Parent := FBar;
  FThumb.Align := TAlignLayout.None;
  FThumb.HitTest := True;
  FThumb.Visible := False;
  FThumb.Stroke.Kind := TBrushKind.None;
  FThumb.Fill.Kind := TBrushKind.Solid;
  FThumb.XRadius := 2.5;
  FThumb.YRadius := 2.5;
  FThumb.Cursor := crSizeNS;
  FThumb.OnMouseDown := ThumbMouseDown;
  FThumb.OnMouseEnter := ThumbMouseEnter;
  FThumb.OnMouseLeave := ThumbMouseLeave;

  FBarThick := 5;
  FBarTimer := TTimer.Create(Self);
  FBarTimer.Interval := 10;
  FBarTimer.Enabled := False;
  FBarTimer.OnTimer := BarTick;

  FListHost.OnResize := ListHostResize;

  ApplyTheme(FColors);
  SyncPrompt;
end;

destructor TFluentComboBox.Destroy;
begin
  FBarDrag := False;
  if Assigned(FBarTimer) then
  begin
    FBarTimer.Enabled := False;
    FBarTimer.OnTimer := nil;
  end;
  FItems.OnChange := nil;
  FEdit.OnChange := nil;
  FEdit.OnSubmit := nil;
  FPopup.IsOpen := False;
  FItems.Free;
  inherited;
end;

procedure TFluentComboBox.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  FFrame.Fill.Color := AColors.ControlFill;
  FFrame.Stroke.Color := AColors.ControlStroke;
  FEdit.ApplyTheme(AColors);
  FEdit.Fill.Kind := TBrushKind.None;
  FGlyph.TextSettings.FontColor := AColors.SubTextColor;
  FChevron.TextSettings.FontColor := AColors.TextColor;
  FPrompt.TextSettings.FontColor := AColors.SubTextColor;
  FListHost.Fill.Color := AColors.CardBackground;
  FListHost.Stroke.Color := AColors.CardStroke;
  ApplyFluentShadow(FShadow, AColors.IsDark);
  if FPopup.IsOpen then
  begin
    PaintRows;
    PlaceListBar;
  end;
  Repaint;
end;

function TFluentComboBox.GetText: string;
begin
  Result := FEdit.Text;
end;

procedure TFluentComboBox.SetText(const AValue: string);
begin
  FSilence := True;
  try
    FEdit.Text := AValue;
  finally
    FSilence := False;
  end;
  if FItems.IndexOf(AValue) <> FItemIndex then
    FItemIndex := FItems.IndexOf(AValue);
  SyncPrompt;
end;

procedure TFluentComboBox.SetItemIndex(const AValue: Integer);
var
  V: Integer;
  Fire: Boolean;
begin
  V := AValue;
  if (V < 0) or (V >= FItems.Count) then
    V := -1;
  Fire := V <> FItemIndex;
  FItemIndex := V;
  FSilence := True;
  try
    if V >= 0 then
      FEdit.Text := FItems[V];
  finally
    FSilence := False;
  end;
  SyncPrompt;
  if Fire and Assigned(FOnSelChange) then
    FOnSelChange(Self);
end;

procedure TFluentComboBox.SetTextPrompt(const AValue: string);
begin
  FTextPrompt := AValue;
  FPrompt.Text := AValue;
  SyncPrompt;
end;

procedure TFluentComboBox.SetFooterCaption(const AValue: string);
begin
  FFooterCaption := AValue;
  if FPopup.IsOpen then
    RebuildDrop;
end;

procedure TFluentComboBox.SetGlyph(const AValue: string);
begin
  FGlyphText := AValue;
  SyncGlyph;
end;

procedure TFluentComboBox.SetDropListOnly(const AValue: Boolean);
begin
  FDropListOnly := AValue;
end;

procedure TFluentComboBox.SetFillMode(const AValue: TFluentEditFill);
begin
  FEdit.FillMode := AValue;
  FEdit.ApplyTheme(FColors);
  FEdit.Fill.Kind := TBrushKind.None;
  case AValue of
    fefSolid:
      FFrame.Fill.Color := FColors.AddressBackground;
  else
    FFrame.Fill.Color := FColors.ControlFill;
  end;
end;

function TFluentComboBox.GetFillMode: TFluentEditFill;
begin
  Result := FEdit.FillMode;
end;

procedure TFluentComboBox.SyncGlyph;
begin
  FGlyph.Text := FGlyphText;
  FGlyph.Visible := FGlyphText <> '';
  if FGlyph.Visible then
    FGlyph.Width := 26
  else
    FGlyph.Width := 0;
  FPrompt.Margins.Left := FGlyph.Width + 8;
  FEdit.Margins.Left := 4;
  if FGlyph.Visible then
    FEdit.Margins.Left := 0;
end;

procedure TFluentComboBox.SyncPrompt;
begin
  FPrompt.Visible := (FEdit.Text = '') and (FTextPrompt <> '') and
    not FEdit.IsFocused;
  FPrompt.Text := FTextPrompt;
end;

procedure TFluentComboBox.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := -1;
  if FPopup.IsOpen then
    RebuildDrop;
end;

procedure TFluentComboBox.EditChanged(Sender: TObject);
begin
  SyncPrompt;
  if FSilence then
    Exit;
  FItemIndex := -1;
  if Assigned(FOnChange) then
    FOnChange(Self);
  if FSuggest and FEdit.IsFocused then
  begin
    if FPopup.IsOpen then
      RebuildDrop
    else
      OpenDrop;
    if RowCount = 0 then
      CloseDrop;
  end;
end;

procedure TFluentComboBox.EditSubmit(Sender: TObject);
var
  Src: Integer;
begin
  if FPopup.IsOpen and (FHi >= 0) and (FHi < RowCount) then
  begin
    Src := RowSource(FHi);
    AcceptSource(Src);
    if (Src >= 0) and Assigned(FOnSubmit) then
      FOnSubmit(Self);
    Exit;
  end;
  CloseDrop;
  if Assigned(FOnSubmit) then
    FOnSubmit(Self);
end;

procedure TFluentComboBox.EditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if FDropListOnly and not FSuggest and (KeyChar >= #32) and
     not (ssCtrl in Shift) and not (ssAlt in Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    OpenDrop;
    Exit;
  end;

  { Page Up/Down редактор не ест. Отдаём владельцу, пока фокус в поле. }
  if ((Key = vkPrior) or (Key = vkNext)) and Assigned(FOnEditorKey) then
  begin
    FOnEditorKey(Self, Key, KeyChar, Shift);
    if Key = 0 then
      Exit;
  end;

  if Key = vkDown then
  begin
    if not FPopup.IsOpen then
      OpenDrop
    else if FHi < RowCount - 1 then
    begin
      Inc(FHi);
      while (FHi < RowCount) and (RowSource(FHi) = -3) do
        Inc(FHi);
      if FHi >= RowCount then
        FHi := RowCount - 1;
      ScrollToHi;
      PaintRows;
    end;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  if Key = vkUp then
  begin
    if FPopup.IsOpen and (FHi > 0) then
    begin
      Dec(FHi);
      while (FHi > 0) and (RowSource(FHi) = -3) do
        Dec(FHi);
      ScrollToHi;
      PaintRows;
    end;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  if Key = vkEscape then
  begin
    if FPopup.IsOpen then
      CloseDrop
    else if Assigned(FOnEscape) then
      FOnEscape(Self);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  if (Key = vkReturn) and FPopup.IsOpen then
  begin
    Key := 0;
    KeyChar := #0;
  end;
end;

procedure TFluentComboBox.EditEnter(Sender: TObject);
begin
  SyncPrompt;
end;

procedure TFluentComboBox.CloseTick(Sender: TObject);
begin
  FCloseTick.Enabled := False;
  if csDestroying in ComponentState then
    Exit;
  if FPopup.IsOpen and not FEdit.IsFocused then
    CloseDrop;
end;

procedure TFluentComboBox.EditExit(Sender: TObject);
begin
  SyncPrompt;
  if Assigned(FCloseTick) then
  begin
    FCloseTick.Enabled := False;
    FCloseTick.Enabled := True;
  end;
end;

procedure TFluentComboBox.EditMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if (Button = TMouseButton.mbLeft) and FDropListOnly then
    OpenDrop;
end;

procedure TFluentComboBox.EditMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  if not FPopup.IsOpen then
    Exit;
  if WheelDelta > 0 then
  begin
    if FScroll > 0 then
      Dec(FScroll);
  end
  else if FScroll < Max(0, RowCount - FMaxVisible) then
    Inc(FScroll);
  ApplyListY;
  PlaceListBar;
  Handled := True;
end;

procedure TFluentComboBox.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  if FPopup.IsOpen then
    EditMouseWheel(Self, Shift, WheelDelta, Handled)
  else if Assigned(FOnClosedWheel) then
    FOnClosedWheel(Self, Shift, WheelDelta, Handled);
  if not Handled then
    inherited;
end;

procedure TFluentComboBox.DropClick(Sender: TObject);
begin
  if FPopup.IsOpen then
    CloseDrop
  else
    OpenDrop;
  if FEdit.CanFocus then
    FEdit.SetFocus;
end;

procedure TFluentComboBox.DropEnter(Sender: TObject);
begin
  FDropBtn.Fill.Color := FColors.ControlFillHover;
end;

procedure TFluentComboBox.DropLeave(Sender: TObject);
begin
  FDropBtn.Fill.Color := TAlphaColors.Null;
end;

function TFluentComboBox.RowCount: Integer;
begin
  Result := FList.ControlsCount;
end;

function TFluentComboBox.RowSource(ARow: Integer): Integer;
begin
  Result := -1;
  if (ARow < 0) or (ARow >= FList.ControlsCount) then
    Exit;
  Result := FList.Controls[ARow].Tag;
end;

procedure TFluentComboBox.PaintRows;
var
  I: Integer;
  Row: TRectangle;
  T: TText;
  Hot: Boolean;
begin
  for I := 0 to FList.ControlsCount - 1 do
  begin
    if not (FList.Controls[I] is TRectangle) then
      Continue;
    Row := TRectangle(FList.Controls[I]);
    Hot := I = FHi;
    if Hot then
      Row.Fill.Color := FColors.SelectionColor
    else
      Row.Fill.Color := TAlphaColors.Null;
    if (Row.ControlsCount > 0) and (Row.Controls[0] is TText) then
    begin
      T := TText(Row.Controls[0]);
      if Row.Tag = -2 then
        T.TextSettings.FontColor := FColors.SubTextColor
      else if Hot then
        T.TextSettings.FontColor := FColors.OnAccentTextColor
      else
        T.TextSettings.FontColor := FColors.TextColor;
    end;
  end;
end;

procedure TFluentComboBox.ApplyListY;
begin
  FList.Position.Y := 0 - FScroll * RowH;
end;

procedure TFluentComboBox.PlaceListBar;
var
  I, N, MaxScroll, Vis: Integer;
  Need: Boolean;
  RowW, TrackH, ThumbLen, Travel, Off, Thick: Single;
begin
  if FBarBusy or (FBar = nil) or (FThumb = nil) or (FList = nil) then
    Exit;
  FBarBusy := True;
  try
    N := RowCount;
    Vis := Max(1, FMaxVisible);
    Need := N > FMaxVisible;
    if Need and not FBar.Visible then
      FBar.BringToFront;
    FBar.Visible := Need;
    if Need then
      RowW := Max(40, Width - 8 - BarW)
    else
      RowW := Max(40, Width - 8);
    if not SameValue(FList.Width, RowW, 0.5) then
    begin
      FList.Width := RowW;
      for I := 0 to N - 1 do
        if (FList.Controls[I] is TControl) and (FList.Controls[I].Tag <> -3) then
          TControl(FList.Controls[I]).Width := RowW;
    end;
    if not Need then
    begin
      FThumb.Visible := False;
      Exit;
    end;
    TrackH := FBar.Height;
    if TrackH < RowH then
      TrackH := Min(N, Vis) * RowH;
    FBarTrack := TrackH;
    ThumbLen := TrackH * Vis / N;
    if ThumbLen < 18 then
      ThumbLen := 18;
    if ThumbLen > TrackH then
      ThumbLen := TrackH;
    MaxScroll := Max(0, N - FMaxVisible);
    if FScroll > MaxScroll then
      FScroll := MaxScroll;
    if FScroll < 0 then
      FScroll := 0;
    Travel := TrackH - ThumbLen;
    if (MaxScroll > 0) and (Travel > 0) then
      Off := (FScroll / MaxScroll) * Travel
    else
      Off := 0;
    Thick := FBarThick;
    if Thick < 5 then
      Thick := 5;
    if Thick > BarW then
      Thick := BarW;
    FThumb.Visible := True;
    if not (SameValue(FThumb.Position.X, (BarW - Thick) / 2, 0.4) and
            SameValue(FThumb.Position.Y, Off, 0.4) and
            SameValue(FThumb.Width, Thick, 0.4) and
            SameValue(FThumb.Height, ThumbLen, 0.4)) then
      FThumb.SetBounds((BarW - Thick) / 2, Off, Thick, ThumbLen);
    if FColors.IsDark then
      FThumb.Fill.Color := $72FFFFFF
    else
      FThumb.Fill.Color := $66000000;
    ApplyListY;
  finally
    FBarBusy := False;
  end;
end;

procedure TFluentComboBox.ListHostResize(Sender: TObject);
begin
  if Assigned(FPopup) and FPopup.IsOpen then
    PlaceListBar;
end;

procedure TFluentComboBox.ThumbMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  FBarDrag := True;
  FBarDragY := Screen.MousePos.Y;
  FBarDragScroll := FScroll;
  FBarThick := 8;
  if Assigned(FBarTimer) then
    FBarTimer.Enabled := True;
  PlaceListBar;
end;

procedure TFluentComboBox.BarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  MaxScroll: Integer;
begin
  if (Button <> TMouseButton.mbLeft) or (FThumb = nil) then
    Exit;
  if FThumb.Visible and (Y >= FThumb.Position.Y) and
     (Y <= FThumb.Position.Y + FThumb.Height) then
  begin
    ThumbMouseDown(Sender, Button, Shift, X, Y);
    Exit;
  end;
  MaxScroll := Max(0, RowCount - FMaxVisible);
  if Y < FThumb.Position.Y then
    FScroll := Max(0, FScroll - Max(1, FMaxVisible))
  else
    FScroll := Min(MaxScroll, FScroll + Max(1, FMaxVisible));
  PlaceListBar;
end;

procedure TFluentComboBox.ThumbMouseEnter(Sender: TObject);
begin
  FBarThick := 8;
  PlaceListBar;
end;

procedure TFluentComboBox.ThumbMouseLeave(Sender: TObject);
begin
  if FBarDrag then
    Exit;
  FBarThick := 5;
  PlaceListBar;
end;

procedure TFluentComboBox.BarTick(Sender: TObject);
var
  N, MaxScroll: Integer;
  ThumbLen, Travel, Delta: Single;
begin
  if (csDestroying in ComponentState) or not FBarDrag then
  begin
    FBarDrag := False;
    if Assigned(FBarTimer) then
      FBarTimer.Enabled := False;
    Exit;
  end;
  if (GetAsyncKeyState(VK_LBUTTON) and $8000) = 0 then
  begin
    FBarDrag := False;
    FBarTimer.Enabled := False;
    FBarThick := 5;
    PlaceListBar;
    Exit;
  end;
  N := RowCount;
  if N <= FMaxVisible then
    Exit;
  MaxScroll := N - FMaxVisible;
  ThumbLen := FBarTrack * Max(1, FMaxVisible) / N;
  if ThumbLen < 18 then
    ThumbLen := 18;
  if ThumbLen > FBarTrack then
    ThumbLen := FBarTrack;
  Travel := FBarTrack - ThumbLen;
  if (Travel <= 0) or (MaxScroll <= 0) then
    Exit;
  Delta := Screen.MousePos.Y - FBarDragY;
  FScroll := EnsureRange(Round(FBarDragScroll + Delta / Travel * MaxScroll), 0, MaxScroll);
  PlaceListBar;
end;

procedure TFluentComboBox.ScrollToHi;
var
  MaxScroll: Integer;
begin
  if FHi < FScroll then
    FScroll := FHi;
  if FHi >= FScroll + FMaxVisible then
    FScroll := FHi - FMaxVisible + 1;
  MaxScroll := Max(0, RowCount - FMaxVisible);
  FScroll := EnsureRange(FScroll, 0, MaxScroll);
  ApplyListY;
  PlaceListBar;
end;

procedure TFluentComboBox.RebuildDrop;
var
  I, N, Shown: Integer;
  Q: string;
  Row: TRectangle;
  Cap: TText;
  Take: Boolean;

  procedure AddSep;
  var
    Line: TRectangle;
  begin
    Line := TRectangle.Create(Self);
    Line.Align := TAlignLayout.None;
    Line.Parent := FList;
    Line.SetBounds(10, Shown * RowH + (RowH - 1) / 2, Max(40, Width - 28), 1);
    Line.Stroke.Kind := TBrushKind.None;
    Line.Fill.Kind := TBrushKind.Solid;
    Line.Fill.Color := FColors.DividerColor;
    Line.HitTest := False;
    Line.Tag := -3;
    Inc(Shown);
  end;

  procedure AddRow(const ACaption: string; ASource: Integer);
  begin
    Row := TRectangle.Create(Self);
    { Align=Top сортирует по текущему Top. Новый пункт с Top=0 встаёт в индекс 1,
      не в конец: 1, затем 4, 3, 2. Позиция задаётся явно. }
    Row.Align := TAlignLayout.None;
    Row.SetBounds(0, Shown * RowH, Max(40, Width - 8), RowH);
    Row.Parent := FList;
    Row.XRadius := 4;
    Row.YRadius := 4;
    Row.Stroke.Kind := TBrushKind.None;
    Row.Fill.Kind := TBrushKind.Solid;
    Row.Fill.Color := TAlphaColors.Null;
    Row.HitTest := True;
    Row.Cursor := crHandPoint;
    Row.Tag := ASource;
    Row.OnMouseDown := RowDown;
    Row.OnMouseEnter := RowEnter;
    Cap := TText.Create(Row);
    Cap.Parent := Row;
    Cap.Align := TAlignLayout.Client;
    Cap.Margins.Rect := TRectF.Create(10, 0, 8, 0);
    Cap.HitTest := False;
    Cap.Text := ACaption;
    Cap.TextSettings.Font.Family := FluentFontFamily;
    Cap.TextSettings.Font.Size := 13;
    Cap.TextSettings.HorzAlign := TTextAlign.Leading;
    Cap.TextSettings.VertAlign := TTextAlign.Center;
    Cap.TextSettings.Trimming := TTextTrimming.Character;
    Inc(Shown);
  end;

begin
  while FList.ControlsCount > 0 do
    FList.Controls[0].Free;
  Shown := 0;
  Q := '';
  if FSuggest then
    Q := AnsiLowerCase(FEdit.Text);
  for I := 0 to FItems.Count - 1 do
  begin
    if (Q = '') and (FItems[I] = '-') then
    begin
      AddSep;
      Continue;
    end;
    Take := True;
    if Q <> '' then
      Take := Pos(Q, AnsiLowerCase(FItems[I])) > 0;
    if Take then
      AddRow(FItems[I], I);
  end;
  if (FFooterCaption <> '') and (FItems.Count > 0) and
     ((Q = '') or (Shown > 0)) then
    AddRow(FFooterCaption, -2);

  N := FList.ControlsCount;
  FList.Width := Max(40, Width - 8);
  FList.Height := N * RowH;
  FList.Position.X := 0;
  for I := 0 to N - 1 do
    if FList.Controls[I] is TControl then
      TControl(FList.Controls[I]).Width := FList.Width;
  FHi := -1;
  for I := 0 to N - 1 do
    if FList.Controls[I].Tag = FItemIndex then
      FHi := I;
  if (FHi < 0) and (N > 0) then
    FHi := 0;
  while (FHi < N) and (RowSource(FHi) = -3) do
    Inc(FHi);
  if FHi >= N then
    FHi := 0;
  FScroll := 0;
  ScrollToHi;
  PaintRows;

  if N <= 0 then
  begin
    FPopup.Height := 0;
    Exit;
  end;
  FPopup.Width := Width + DropShadowL + DropShadowR;
  FPopup.Height := Min(N, Max(1, FMaxVisible)) * RowH + 8 + DropShadowT + DropShadowB;
end;

procedure TFluentComboBox.CloseDrop;
begin
  FBarDrag := False;
  if Assigned(FBarTimer) then
    FBarTimer.Enabled := False;
  FBarThick := 5;
  FPopup.IsOpen := False;
  FDropBtn.Fill.Color := TAlphaColors.Null;
end;

procedure TFluentComboBox.CloseList;
begin
  CloseDrop;
end;

function TFluentComboBox.IsDropOpen: Boolean;
begin
  Result := Assigned(FPopup) and FPopup.IsOpen;
end;

procedure TFluentComboBox.OpenDrop;
begin
  if Assigned(FOnDrop) then
    FOnDrop(Self);
  RebuildDrop;
  if RowCount = 0 then
  begin
    CloseDrop;
    Exit;
  end;
  FPopup.IsOpen := True;
  PlaceListBar;
  PaintRows;
end;

procedure TFluentComboBox.AcceptSource(ASource: Integer);
begin
  if ASource = -3 then
    Exit;
  CloseDrop;
  if ASource = -2 then
  begin
    if Assigned(FOnFooter) then
      FOnFooter(Self);
    Exit;
  end;
  if (ASource < 0) or (ASource >= FItems.Count) then
    Exit;
  FSilence := True;
  try
    FItemIndex := ASource;
    FEdit.Text := FItems[ASource];
  finally
    FSilence := False;
  end;
  SyncPrompt;
  if Assigned(FOnSelChange) then
    FOnSelChange(Self);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TFluentComboBox.RowDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  if Sender is TControl then
    AcceptSource(TControl(Sender).Tag);
end;

procedure TFluentComboBox.RowEnter(Sender: TObject);
var
  I: Integer;
begin
  if not (Sender is TControl) then
    Exit;
  for I := 0 to FList.ControlsCount - 1 do
    if FList.Controls[I] = Sender then
    begin
      if FHi <> I then
      begin
        FHi := I;
        PaintRows;
      end;
      Break;
    end;
end;

procedure TFluentComboBox.FocusEditor;
begin
  if FEdit.CanFocus then
    FEdit.SetFocus;
  FEdit.SelectAll;
  SyncPrompt;
end;

function TFluentComboBox.EditorFocused: Boolean;
begin
  Result := FEdit.IsFocused;
end;

end.
