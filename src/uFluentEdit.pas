unit uFluentEdit;

{
  Свой однострочный Fluent-edit без нативного Windows TEdit.
  Фон прозрачный или в цветах темы — белое системное поле не используется.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Rtti,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Graphics, FMX.Platform, FMX.TextLayout,
  FMX.Forms, FMX.Layouts, FMX.Effects,
  uThemeManager, uFluentChrome;

type
  TFluentEditFill = (fefTransparent, fefSubtle, fefSolid);

  TFluentEdit = class(TRectangle)
  private
    FText: string;
    FSelStart: Integer;
    FSelLength: Integer;
    FCaretOn: Boolean;
    FBlink: TTimer;
    FTextColor: TAlphaColor;
    FSelColor: TAlphaColor;
    FCaretColor: TAlphaColor;
    FFillMode: TFluentEditFill;
    FFontSize: Single;
    FPadX: Single;
    FSelecting: Boolean;
    FScrollX: Single;
    FOnChange: TNotifyEvent;
    FOnSubmit: TNotifyEvent;
    procedure SetText(const AValue: string);
    procedure SetFontSize(const AValue: Single);
    procedure SetFillMode(const AValue: TFluentEditFill);
    procedure BlinkTick(Sender: TObject);
    procedure DeleteSelection;
    procedure InsertText(const AValue: string);
    function CaretIndex: Integer;
    procedure MoveCaret(ANewPos: Integer; AExtend: Boolean);
    function IndexAtX(AX: Single): Integer;
    function SelBounds(out AFrom, ATo: Integer): Boolean;
    function LayoutFor(const AText: string): TTextLayout;
    function PrefixWidth(ACount: Integer): Single;
    function VisibleTextWidth: Single;
    function MaxScrollX: Single;
    procedure EnsureCaretVisible;
    procedure Changed;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SelectAll;
    procedure SelectRange(AStart, ALength: Integer);
    procedure InsertSnippet(const AValue: string);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ApplyColors(AText, ASel, ACaret: TAlphaColor);
    property Text: string read FText write SetText;
    property FontSize: Single read FFontSize write SetFontSize;
    property FillMode: TFluentEditFill read FFillMode write SetFillMode;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSubmit: TNotifyEvent read FOnSubmit write FOnSubmit;
  end;

function CreateFluentEdit(AOwner: TComponent; AParent: TFmxObject): TFluentEdit;
function FluentInputQuery(const ATitle, APrompt: string; var AValue: string;
  const AColors: TThemeColors; AOwnerForm: TCommonCustomForm = nil): Boolean;

implementation

function CreateFluentEdit(AOwner: TComponent; AParent: TFmxObject): TFluentEdit;
begin
  Result := TFluentEdit.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Client;
end;

constructor TFluentEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := True;
  CanFocus := True;
  TabStop := True;
  Cursor := crIBeam;
  XRadius := 4;
  YRadius := 4;
  FFillMode := fefTransparent;
  Fill.Kind := TBrushKind.None;
  Stroke.Kind := TBrushKind.None;
  FFontSize := 13;
  FPadX := 4;
  FScrollX := 0;
  ClipChildren := True;
  FTextColor := TAlphaColors.White;
  FSelColor := $360078D4;
  FCaretColor := $FF0078D4;
  FBlink := TTimer.Create(Self);
  FBlink.Interval := 530;
  FBlink.Enabled := False;
  FBlink.OnTimer := BlinkTick;
  AutoCapture := True;
end;

destructor TFluentEdit.Destroy;
begin
  FBlink.Enabled := False;
  inherited;
end;

procedure TFluentEdit.ApplyTheme(const AColors: TThemeColors);
begin
  FTextColor := AColors.TextColor;
  FSelColor := AColors.AccentSubtle;
  FCaretColor := AColors.SelectionColor;
  case FFillMode of
    fefSubtle:
      begin
        Fill.Kind := TBrushKind.Solid;
        Fill.Color := AColors.ControlFill;
      end;
    fefSolid:
      begin
        Fill.Kind := TBrushKind.Solid;
        Fill.Color := AColors.AddressBackground;
      end;
  else
    Fill.Kind := TBrushKind.None;
  end;
  Stroke.Kind := TBrushKind.None;
  Repaint;
end;

procedure TFluentEdit.ApplyColors(AText, ASel, ACaret: TAlphaColor);
begin
  FTextColor := AText;
  FSelColor := ASel;
  FCaretColor := ACaret;
  Repaint;
end;

procedure TFluentEdit.SetFillMode(const AValue: TFluentEditFill);
begin
  if FFillMode = AValue then
    Exit;
  FFillMode := AValue;
  if FFillMode = fefTransparent then
    Fill.Kind := TBrushKind.None;
  Repaint;
end;

procedure TFluentEdit.SetFontSize(const AValue: Single);
begin
  if SameValue(FFontSize, AValue) then
    Exit;
  FFontSize := Max(9, AValue);
  Repaint;
end;

procedure TFluentEdit.SetText(const AValue: string);
begin
  if FText = AValue then
    Exit;
  FText := AValue;
  FSelStart := Length(FText);
  FSelLength := 0;
  EnsureCaretVisible;
  Changed;
  Repaint;
end;

procedure TFluentEdit.SelectAll;
begin
  SelectRange(0, Length(FText));
end;

procedure TFluentEdit.SelectRange(AStart, ALength: Integer);
begin
  FSelStart := EnsureRange(AStart, 0, Length(FText));
  FSelLength := EnsureRange(ALength, -FSelStart, Length(FText) - FSelStart);
  FCaretOn := True;
  EnsureCaretVisible;
  Repaint;
end;

function TFluentEdit.SelBounds(out AFrom, ATo: Integer): Boolean;
begin
  AFrom := FSelStart;
  ATo := FSelStart + FSelLength;
  if AFrom > ATo then
  begin
    AFrom := ATo;
    ATo := FSelStart;
  end;
  AFrom := EnsureRange(AFrom, 0, Length(FText));
  ATo := EnsureRange(ATo, 0, Length(FText));
  Result := ATo > AFrom;
end;

function TFluentEdit.CaretIndex: Integer;
begin
  Result := EnsureRange(FSelStart + FSelLength, 0, Length(FText));
end;

procedure TFluentEdit.MoveCaret(ANewPos: Integer; AExtend: Boolean);
begin
  ANewPos := EnsureRange(ANewPos, 0, Length(FText));
  if AExtend then
    FSelLength := ANewPos - FSelStart
  else
  begin
    FSelStart := ANewPos;
    FSelLength := 0;
  end;
  FCaretOn := True;
  EnsureCaretVisible;
  Repaint;
end;

function TFluentEdit.IndexAtX(AX: Single): Integer;
var
  L: TTextLayout;
  I: Integer;
  Prev, NextW, Target: Single;
begin
  Result := 0;
  Target := AX - FPadX + FScrollX;
  if Target <= 0 then
    Exit;
  L := LayoutFor(FText);
  try
    Prev := 0;
    for I := 1 to Length(FText) do
    begin
      L.Text := Copy(FText, 1, I);
      NextW := L.TextWidth;
      if Target < (Prev + NextW) * 0.5 then
        Exit(I - 1);
      Prev := NextW;
      Result := I;
    end;
  finally
    L.Free;
  end;
end;

procedure TFluentEdit.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TFluentEdit.DeleteSelection;
var
  A, B: Integer;
begin
  if not SelBounds(A, B) then
    Exit;
  Delete(FText, A + 1, B - A);
  FSelStart := A;
  FSelLength := 0;
  Changed;
  EnsureCaretVisible;
end;

procedure TFluentEdit.InsertText(const AValue: string);
begin
  DeleteSelection;
  Insert(AValue, FText, FSelStart + 1);
  FSelStart := FSelStart + Length(AValue);
  FSelLength := 0;
  Changed;
  EnsureCaretVisible;
  Repaint;
end;

procedure TFluentEdit.InsertSnippet(const AValue: string);
begin
  InsertText(AValue);
  SetFocus;
end;

function TFluentEdit.PrefixWidth(ACount: Integer): Single;
var
  L: TTextLayout;
begin
  Result := 0;
  if ACount <= 0 then
    Exit;
  L := LayoutFor(Copy(FText, 1, Min(ACount, Length(FText))));
  try
    Result := L.TextWidth;
  finally
    L.Free;
  end;
end;

function TFluentEdit.VisibleTextWidth: Single;
begin
  Result := Max(8, Width - FPadX * 2);
end;

function TFluentEdit.MaxScrollX: Single;
begin
  Result := Max(0, PrefixWidth(Length(FText)) - VisibleTextWidth);
end;

procedure TFluentEdit.EnsureCaretVisible;
var
  CX, View: Single;
begin
  View := VisibleTextWidth;
  CX := PrefixWidth(CaretIndex);
  if CX - FScrollX > View then
    FScrollX := CX - View + 2
  else if CX - FScrollX < 0 then
    FScrollX := CX;
  if PrefixWidth(Length(FText)) <= View then
    FScrollX := 0
  else
    FScrollX := EnsureRange(FScrollX, 0, MaxScrollX);
end;

function TFluentEdit.LayoutFor(const AText: string): TTextLayout;
begin
  Result := TTextLayoutManager.DefaultTextLayout.Create;
  Result.BeginUpdate;
  try
    Result.Font.Family := FluentFontFamily;
    Result.Font.Size := FFontSize;
    Result.Color := FTextColor;
    Result.WordWrap := False;
    Result.HorizontalAlign := TTextAlign.Leading;
    Result.MaxSize := TPointF.Create(Max(Width * 8, 4096), Max(Height, FFontSize + 8));
    Result.Text := AText;
    Result.TopLeft := TPointF.Create(FPadX - FScrollX, (Height - FFontSize - 2) * 0.5);
  finally
    Result.EndUpdate;
  end;
end;

procedure TFluentEdit.Paint;
var
  L: TTextLayout;
  R: TRectF;
  A, B: Integer;
  X1, X2, CX, OriginX: Single;
begin
  if csDestroying in ComponentState then
    Exit;
  inherited;
  OriginX := FPadX - FScrollX;
  Canvas.IntersectClipRect(TRectF.Create(0, 0, Width, Height));
  L := LayoutFor(FText);
  try
    if SelBounds(A, B) and IsFocused then
    begin
      L.Text := Copy(FText, 1, A);
      X1 := OriginX + L.TextWidth;
      L.Text := Copy(FText, 1, B);
      X2 := OriginX + L.TextWidth;
      L.Text := FText;
      R := TRectF.Create(X1, 3, X2, Height - 3);
      Canvas.Fill.Kind := TBrushKind.Solid;
      Canvas.Fill.Color := FSelColor;
      Canvas.FillRect(R, 2, 2, AllCorners, AbsoluteOpacity);
    end;
    L.Text := FText;
    L.Color := FTextColor;
    L.RenderLayout(Canvas);
    if IsFocused and FCaretOn then
    begin
      L.Text := Copy(FText, 1, CaretIndex);
      CX := OriginX + L.TextWidth;
      Canvas.Stroke.Kind := TBrushKind.Solid;
      Canvas.Stroke.Color := FCaretColor;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawLine(TPointF.Create(CX, 4), TPointF.Create(CX, Height - 4), AbsoluteOpacity);
    end;
  finally
    L.Free;
  end;
end;

procedure TFluentEdit.Resize;
begin
  inherited;
  EnsureCaretVisible;
end;

procedure TFluentEdit.BlinkTick(Sender: TObject);
begin
  if (csDestroying in ComponentState) or not IsFocused then
    Exit;
  FCaretOn := not FCaretOn;
  Repaint;
end;

procedure TFluentEdit.DoEnter;
begin
  inherited;
  FCaretOn := True;
  FBlink.Enabled := True;
  Repaint;
end;

procedure TFluentEdit.DoExit;
begin
  FSelecting := False;
  FBlink.Enabled := False;
  FCaretOn := False;
  inherited;
end;

procedure TFluentEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  SetFocus;
  Idx := IndexAtX(X);
  MoveCaret(Idx, ssShift in Shift);
  FSelecting := True;
end;

procedure TFluentEdit.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FSelecting and (ssLeft in Shift) then
    MoveCaret(IndexAtX(X), True);
end;

procedure TFluentEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
    FSelecting := False;
end;

procedure TFluentEdit.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
var
  MaxX: Single;
begin
  MaxX := MaxScrollX;
  if MaxX > 0 then
  begin
    FScrollX := EnsureRange(FScrollX - WheelDelta * 0.25, 0, MaxX);
    Repaint;
    Handled := True;
    Exit;
  end;
  inherited;
end;

procedure TFluentEdit.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  Svc: IFMXClipboardService;
  Clip: TValue;
  A, B: Integer;
begin
  if csDestroying in ComponentState then
    Exit;
  if (ssCtrl in Shift) and (Key = vkA) then
  begin
    SelectAll;
    Key := 0;
    Exit;
  end;
  if (ssCtrl in Shift) and (Key = vkV) then
  begin
    if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    begin
      Clip := Svc.GetClipboard;
      if not Clip.IsEmpty then
        InsertText(Clip.ToString);
    end;
    Key := 0;
    Exit;
  end;
  if (ssCtrl in Shift) and (Key = vkC) then
  begin
    if SelBounds(A, B) and
       TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
      Svc.SetClipboard(Copy(FText, A + 1, B - A));
    Key := 0;
    Exit;
  end;
  if (ssCtrl in Shift) and (Key = vkX) then
  begin
    if SelBounds(A, B) and
       TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    begin
      Svc.SetClipboard(Copy(FText, A + 1, B - A));
      DeleteSelection;
      Repaint;
    end;
    Key := 0;
    Exit;
  end;

  case Key of
    vkReturn:
      begin
        if Assigned(FOnSubmit) then
          FOnSubmit(Self);
        inherited;
        Key := 0;
        Exit;
      end;
    vkEscape:
      begin
        inherited;
        Key := 0;
        Exit;
      end;
    vkLeft:
      begin
        if not (ssShift in Shift) and SelBounds(A, B) then
          MoveCaret(A, False)
        else
          MoveCaret(CaretIndex - 1, ssShift in Shift);
        Key := 0;
      end;
    vkRight:
      begin
        if not (ssShift in Shift) and SelBounds(A, B) then
          MoveCaret(B, False)
        else
          MoveCaret(CaretIndex + 1, ssShift in Shift);
        Key := 0;
      end;
    vkHome:
      begin
        MoveCaret(0, ssShift in Shift);
        Key := 0;
      end;
    vkEnd:
      begin
        MoveCaret(Length(FText), ssShift in Shift);
        Key := 0;
      end;
    vkBack:
      begin
        if FSelLength <> 0 then
          DeleteSelection
        else if FSelStart > 0 then
        begin
          Delete(FText, FSelStart, 1);
          Dec(FSelStart);
          Changed;
        end;
        EnsureCaretVisible;
        Repaint;
        Key := 0;
      end;
    vkDelete:
      begin
        if FSelLength <> 0 then
          DeleteSelection
        else if FSelStart < Length(FText) then
        begin
          Delete(FText, FSelStart + 1, 1);
          Changed;
        end;
        EnsureCaretVisible;
        Repaint;
        Key := 0;
      end;
  else
    if (KeyChar >= #32) and not (ssCtrl in Shift) and not (ssAlt in Shift) then
    begin
      InsertText(KeyChar);
      KeyChar := #0;
      Key := 0;
    end;
  end;
  if Key <> 0 then
    inherited;
end;

type
  TFluentInputForm = class(TForm)
  private
    FAccepted: Boolean;
    FOwnerForm: TCommonCustomForm;
    FEdit: TFluentEdit;
    FBtnOk: TFluentButton;
    FBtnCancel: TFluentButton;
    procedure Finish(AOk: Boolean);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
  public
    constructor Create(const ATitle, APrompt, AValue: string;
      const AColors: TThemeColors; AOwnerForm: TCommonCustomForm); reintroduce;
    function Execute(out AValue: string): Boolean;
  end;

constructor TFluentInputForm.Create(const ATitle, APrompt, AValue: string;
  const AColors: TThemeColors; AOwnerForm: TCommonCustomForm);
var
  Card, Footer: TRectangle;
  Title, Prompt: TText;
  Shadow: TShadowEffect;
begin
  inherited CreateNew(AOwnerForm);
  FOwnerForm := AOwnerForm;
  BorderStyle := TFmxFormBorderStyle.None;
  Position := TFormPosition.Designed;
  Width := 440;
  Height := 216;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := TAlphaColors.Null;
  Transparency := True;

  Card := TRectangle.Create(Self);
  Card.Parent := Self;
  Card.Align := TAlignLayout.Client;
  Card.ClipChildren := False;

  Card.XRadius := 10;
  Card.YRadius := 10;
  Card.Fill.Kind := TBrushKind.Solid;
  Card.Fill.Color := AColors.CardBackground;
  Card.Stroke.Kind := TBrushKind.Solid;
  Card.Stroke.Color := AColors.ControlStroke;

  Shadow := TShadowEffect.Create(Card);
  Shadow.Parent := Card;
  ApplyFluentShadow(Shadow, AColors.IsDark);


  Title := TText.Create(Self);
  Title.Parent := Card;
  Title.Align := TAlignLayout.Top;
  Title.Height := 26;
  Title.Text := ATitle;
  ApplyFluentText(Title, 16, True);
  Title.TextSettings.HorzAlign := TTextAlign.Leading;
  Title.TextSettings.FontColor := AColors.TextColor;

  

  Prompt := TText.Create(Self);
  Prompt.Parent := Card;
  Prompt.Align := TAlignLayout.Top;
  Prompt.Height := 22;
  Prompt.Margins.Top := 4;
  Prompt.Text := APrompt;
  ApplyFluentText(Prompt, 12, False);
  Prompt.TextSettings.HorzAlign := TTextAlign.Leading;
  Prompt.TextSettings.FontColor := AColors.SubTextColor;

  FEdit := TFluentEdit.Create(Self);
  FEdit.Parent := Card;
  FEdit.Align := TAlignLayout.Top;
  FEdit.Height := 36;
  FEdit.Margins.Top := 10;
  FEdit.FillMode := fefSubtle;
  FEdit.ApplyTheme(AColors);
  FEdit.Text := AValue;
  FEdit.OnKeyDown := EditKeyDown;

  Footer := TRectangle.Create(Self);
  Footer.Parent := Card;
  Footer.Align := TAlignLayout.Bottom;
  Footer.Height := 40;
  Footer.Margins.Top := 12;
  Footer.Stroke.Kind := TBrushKind.None;
  Footer.Fill.Kind := TBrushKind.None;

  FBtnCancel := CreateFluentButton(Self, Footer, '', 'Отмена', fbkStandard, 100, CancelClick);
  FBtnCancel.Align := TAlignLayout.Right;
  FBtnCancel.Margins.Rect := TRectF.Create(8, 4, 0, 4);
  FBtnCancel.ApplyTheme(AColors);

  FBtnOk := CreateFluentButton(Self, Footer, '', 'ОК', fbkAccent, 100, OkClick);
  FBtnOk.Align := TAlignLayout.Right;
  FBtnOk.Margins.Rect := TRectF.Create(0, 4, 0, 4);
  FBtnOk.ApplyTheme(AColors);
  Card.Margins.Rect := TRectF.Create(18, 14, 18, 22);
  Card.Padding.Rect := TRectF.Create(18, 16, 18, 14);
  OnShow := FormShow;
end;

procedure TFluentInputForm.Finish(AOk: Boolean);
begin
  FAccepted := AOk;
  TThread.ForceQueue(nil,
    procedure
    begin
      if csDestroying in ComponentState then
        Exit;
      if AOk then
        ModalResult := mrOk
      else
        ModalResult := mrCancel;
    end);
end;

procedure TFluentInputForm.OkClick(Sender: TObject);
begin
  Finish(True);
end;

procedure TFluentInputForm.CancelClick(Sender: TObject);
begin
  Finish(False);
end;

procedure TFluentInputForm.FormShow(Sender: TObject);
var
  C: TPointF;
begin
  if Assigned(FOwnerForm) then
  begin
    C := FOwnerForm.ClientToScreen(TPointF.Create(
      FOwnerForm.ClientWidth * 0.5, FOwnerForm.ClientHeight * 0.5));
    SetBounds(Round(C.X - Width * 0.5), Round(C.Y - Height * 0.5), Width, Height);
  end;
  FEdit.SelectAll;
  FEdit.SetFocus;
end;

procedure TFluentInputForm.EditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Finish(True);
    Key := 0;
  end
  else if Key = vkEscape then
  begin
    Finish(False);
    Key := 0;
  end;
end;

function TFluentInputForm.Execute(out AValue: string): Boolean;
begin
  FAccepted := False;
  ShowModal;
  Result := FAccepted or (ModalResult = mrOk);
  if Result and Assigned(FEdit) then
    AValue := FEdit.Text;
end;

function FluentInputQuery(const ATitle, APrompt: string; var AValue: string;
  const AColors: TThemeColors; AOwnerForm: TCommonCustomForm = nil): Boolean;
var
  Dlg: TFluentInputForm;
begin
  Dlg := TFluentInputForm.Create(ATitle, APrompt, AValue, AColors, AOwnerForm);
  try
    Result := Dlg.Execute(AValue);
  finally
    Dlg.Free;
  end;
end;

end.
