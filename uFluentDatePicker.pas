unit uFluentDatePicker;

{
  Поле даты с выпадающим календарём. Пустое значение допустимо .
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.DateUtils,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  uAppSettings, uThemeManager, uFluentChrome, uFluentEdit, uFileSearch;

type
  TFluentDatePicker = class(TLayout)
  private
    FColors: TThemeColors;
    FEdit: TFluentEdit;
    FBtn: TFluentButton;
    FPopup: TPopup;
    FHost: TRectangle;
    FPaint: TPaintBox;
    FView: TDate;
    FPicked: TDate;
    FHasPicked: Boolean;
    FOnChange: TNotifyEvent;
    FOnEditKeyDown: TKeyEvent;
    FOnEditSubmit: TNotifyEvent;
    FHoverCell: Integer;
    function GetText: string;
    procedure SetText(const AValue: string);
    procedure BtnClick(Sender: TObject);
    procedure EditChanged(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure EditSubmit(Sender: TObject);
    procedure CalPaint(Sender: TObject; Canvas: TCanvas);
    procedure CalMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure CalMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure CalMouseLeave(Sender: TObject);
    procedure CalMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure SyncFromEdit;
    procedure ApplyPicked(ADate: TDate; ANotify: Boolean);
    procedure ClearDate(ANotify: Boolean);
    procedure OpenPopup;
    function GridStart: TDate;
    function CellAt(X, Y: Single): Integer;
    function HeaderBtnAt(X, Y: Single): Integer;
    function FooterBtnAt(X, Y: Single): Integer;
    procedure NotifyChange;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyTheme(const AColors: TThemeColors);
    function TryGetDate(out ADate: TDateTime): Boolean;
    function HasDate: Boolean;
    procedure SetDate(ADate: TDateTime);
    procedure Clear;
    property Text: string read GetText write SetText;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnEditKeyDown: TKeyEvent read FOnEditKeyDown write FOnEditKeyDown;
    property OnEditSubmit: TNotifyEvent read FOnEditSubmit write FOnEditSubmit;
  end;

implementation

const
  CAL_W     = 278;
  CAL_H     = 300;
  PAD       = 10;
  HEADER_H  = 34;
  WEEK_H    = 22;
  CELL_W    = 36;
  CELL_H    = 30;
  FOOT_H    = 32;
  ICON_CAL  = '';

constructor TFluentDatePicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := 28;
  HitTest := True;
  FColors := GetThemeColors(atSystem);
  FView := Date;
  FHoverCell := -1;

  FEdit := CreateFluentEdit(AOwner, Self);
  FEdit.Align := TAlignLayout.Client;
  FEdit.FillMode := fefSubtle;
  FEdit.Margins.Rect := TRectF.Create(0, 0, 4, 0);
  FEdit.OnChange := EditChanged;
  FEdit.OnKeyDown := EditKeyDown;
  FEdit.OnSubmit := EditSubmit;
  FEdit.Hint := 'дд.мм.гггг';

  FBtn := TFluentButton.Create(AOwner);
  FBtn.Setup(Self, ICON_CAL, '', fbkSubtle, BtnClick);
  FBtn.Align := TAlignLayout.Right;
  FBtn.Width := 28;
  FBtn.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FBtn.Hint := 'Выбрать дату';

  FPopup := TPopup.Create(AOwner);
  FPopup.Parent := Self;
  FPopup.PlacementTarget := Self;
  FPopup.Placement := TPlacement.Bottom;
  FPopup.Width := CAL_W;
  FPopup.Height := CAL_H;

  FHost := TRectangle.Create(AOwner);
  FHost.Parent := FPopup;
  FHost.Align := TAlignLayout.Client;
  FHost.XRadius := 8;
  FHost.YRadius := 8;
  FHost.Stroke.Kind := TBrushKind.Solid;
  FHost.Stroke.Thickness := 1;
  FHost.Fill.Kind := TBrushKind.Solid;
  FHost.Padding.Rect := TRectF.Create(0, 0, 0, 0);

  FPaint := TPaintBox.Create(AOwner);
  FPaint.Parent := FHost;
  FPaint.Align := TAlignLayout.Client;
  FPaint.OnPaint := CalPaint;
  FPaint.OnMouseDown := CalMouseDown;
  FPaint.OnMouseMove := CalMouseMove;
  FPaint.OnMouseLeave := CalMouseLeave;
  FPaint.OnMouseWheel := CalMouseWheel;
end;

function TFluentDatePicker.GetText: string;
begin
  if Assigned(FEdit) then
    Result := FEdit.Text
  else
    Result := '';
end;

procedure TFluentDatePicker.SetText(const AValue: string);
begin
  if Assigned(FEdit) then
    FEdit.Text := AValue;
  SyncFromEdit;
end;

procedure TFluentDatePicker.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  if Assigned(FEdit) then
    FEdit.ApplyTheme(AColors);
  if Assigned(FBtn) then
    FBtn.ApplyTheme(AColors);
  if Assigned(FHost) then
  begin
    FHost.Fill.Color := AColors.CardBackground;
    FHost.Stroke.Color := AColors.CardStroke;
  end;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TFluentDatePicker.NotifyChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TFluentDatePicker.SyncFromEdit;
var
  D: TDateTime;
begin
  if Trim(FEdit.Text) = '' then
  begin
    FHasPicked := False;
    Exit;
  end;
  if TryParseSearchDate(FEdit.Text, D) then
  begin
    FPicked := DateOf(D);
    FHasPicked := True;
    FView := FPicked;
  end;
end;

procedure TFluentDatePicker.ApplyPicked(ADate: TDate; ANotify: Boolean);
var
  S: string;
begin
  FPicked := DateOf(ADate);
  FHasPicked := True;
  FView := FPicked;
  S := FormatDateTime('dd.mm.yyyy', FPicked);
  if FEdit.Text <> S then
  begin
    FEdit.OnChange := nil;
    try
      FEdit.Text := S;
    finally
      FEdit.OnChange := EditChanged;
    end;
  end;
  if ANotify then
    NotifyChange;
end;

procedure TFluentDatePicker.ClearDate(ANotify: Boolean);
begin
  FHasPicked := False;
  if FEdit.Text <> '' then
  begin
    FEdit.OnChange := nil;
    try
      FEdit.Text := '';
    finally
      FEdit.OnChange := EditChanged;
    end;
  end;
  if ANotify then
    NotifyChange;
end;

procedure TFluentDatePicker.SetDate(ADate: TDateTime);
begin
  if ADate <= 0 then
    ClearDate(False)
  else
    ApplyPicked(ADate, False);
end;

procedure TFluentDatePicker.Clear;
begin
  ClearDate(True);
end;

function TFluentDatePicker.HasDate: Boolean;
var
  D: TDateTime;
begin
  Result := TryGetDate(D);
end;

function TFluentDatePicker.TryGetDate(out ADate: TDateTime): Boolean;
begin
  ADate := 0;
  Result := False;
  if Trim(FEdit.Text) = '' then
    Exit;
  Result := TryParseSearchDate(FEdit.Text, ADate);
  if Result then
    ADate := DateOf(ADate);
end;

procedure TFluentDatePicker.EditChanged(Sender: TObject);
begin
  SyncFromEdit;
  NotifyChange;
end;

procedure TFluentDatePicker.EditSubmit(Sender: TObject);
begin
  if Assigned(FPopup) and FPopup.IsOpen then
    FPopup.IsOpen := False;
  if Assigned(FOnEditSubmit) then
    FOnEditSubmit(Self);
end;

procedure TFluentDatePicker.EditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if (Key = vkEscape) and Assigned(FPopup) and FPopup.IsOpen then
  begin
    FPopup.IsOpen := False;
    Key := 0;
    Exit;
  end;
  if Assigned(FOnEditKeyDown) then
    FOnEditKeyDown(Sender, Key, KeyChar, Shift);
end;

procedure TFluentDatePicker.OpenPopup;
begin
  SyncFromEdit;
  if FHasPicked then
    FView := StartOfTheMonth(FPicked)
  else
    FView := StartOfTheMonth(Date);
  FHoverCell := -1;
  FPopup.IsOpen := True;
  FPaint.Repaint;
end;

procedure TFluentDatePicker.BtnClick(Sender: TObject);
begin
  if FPopup.IsOpen then
    FPopup.IsOpen := False
  else
    OpenPopup;
end;

function TFluentDatePicker.GridStart: TDate;
var
  First: TDate;
begin
  First := StartOfTheMonth(FView);
  Result := First - (DayOfTheWeek(First) - 1);
end;

function TFluentDatePicker.CellAt(X, Y: Single): Integer;
var
  GridTop, GX, GY: Single;
  Col, Row: Integer;
begin
  Result := -1;
  GridTop := PAD + HEADER_H + WEEK_H;
  GX := X - PAD;
  GY := Y - GridTop;
  if (GX < 0) or (GY < 0) then
    Exit;
  Col := Trunc(GX / CELL_W);
  Row := Trunc(GY / CELL_H);
  if (Col < 0) or (Col > 6) or (Row < 0) or (Row > 5) then
    Exit;
  Result := Row * 7 + Col;
end;

function TFluentDatePicker.HeaderBtnAt(X, Y: Single): Integer;
begin
  Result := 0;
  if (Y < PAD) or (Y > PAD + HEADER_H) then
    Exit;
  if X < PAD + 36 then
    Result := -1
  else if X > CAL_W - PAD - 36 then
    Result := 1;
end;

function TFluentDatePicker.FooterBtnAt(X, Y: Single): Integer;
var
  Top: Single;
begin
  Result := 0;
  Top := CAL_H - PAD - FOOT_H;
  if Y < Top then
    Exit;
  if X < CAL_W * 0.5 then
    Result := 1
  else
    Result := 2;
end;

procedure TFluentDatePicker.CalPaint(Sender: TObject; Canvas: TCanvas);
const
  Days: array[0..6] of string = ('Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс');
var
  I, Col, Row, M: Integer;
  D, First, Today: TDate;
  R, Cell: TRectF;
  S: string;
  ThisMonth, IsSel, IsToday, IsHover: Boolean;
  GridTop: Single;
begin
  if Canvas = nil then
    Exit;
  Canvas.BeginScene;
  try
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := FColors.CardBackground;
    Canvas.FillRect(TRectF.Create(0, 0, CAL_W, CAL_H), 0, 0, [], 1);

    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := 13;
    Canvas.Fill.Color := FColors.TextColor;
    R := TRectF.Create(PAD + 36, PAD, CAL_W - PAD - 36, PAD + HEADER_H);
    S := FormatDateTime('mmmm yyyy', StartOfTheMonth(FView));
    S := AnsiUpperCase(Copy(S, 1, 1)) + Copy(S, 2, MaxInt);
    Canvas.FillText(R, S, False, 1, [], TTextAlign.Center, TTextAlign.Center);

    Canvas.Font.Family := FluentIconFamily;
    Canvas.Font.Size := 12;
    R := TRectF.Create(PAD, PAD, PAD + 36, PAD + HEADER_H);
    Canvas.FillText(R, '', False, 1, [], TTextAlign.Center, TTextAlign.Center);
    R := TRectF.Create(CAL_W - PAD - 36, PAD, CAL_W - PAD, PAD + HEADER_H);
    Canvas.FillText(R, '', False, 1, [], TTextAlign.Center, TTextAlign.Center);

    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := 11;
    Canvas.Fill.Color := FColors.SubTextColor;
    for I := 0 to 6 do
    begin
      R := TRectF.Create(PAD + I * CELL_W, PAD + HEADER_H,
        PAD + (I + 1) * CELL_W, PAD + HEADER_H + WEEK_H);
      Canvas.FillText(R, Days[I], False, 1, [], TTextAlign.Center, TTextAlign.Center);
    end;

    First := StartOfTheMonth(FView);
    M := MonthOf(First);
    Today := Date;
    D := GridStart;
    GridTop := PAD + HEADER_H + WEEK_H;
    for I := 0 to 41 do
    begin
      Col := I mod 7;
      Row := I div 7;
      Cell := TRectF.Create(
        PAD + Col * CELL_W + 2,
        GridTop + Row * CELL_H + 2,
        PAD + (Col + 1) * CELL_W - 2,
        GridTop + (Row + 1) * CELL_H - 2);
      ThisMonth := MonthOf(D) = M;
      IsToday := DateOf(D) = Today;
      IsSel := FHasPicked and (DateOf(D) = DateOf(FPicked));
      IsHover := I = FHoverCell;

      if IsSel then
      begin
        Canvas.Fill.Color := FColors.SelectionColor;
        Canvas.FillRect(Cell, 6, 6, AllCorners, 1);
        Canvas.Fill.Color := FColors.OnAccentTextColor;
      end
      else if IsHover and ThisMonth then
      begin
        Canvas.Fill.Color := FColors.ItemHover;
        Canvas.FillRect(Cell, 6, 6, AllCorners, 1);
        Canvas.Fill.Color := FColors.TextColor;
      end
      else if ThisMonth then
        Canvas.Fill.Color := FColors.TextColor
      else
        Canvas.Fill.Color := FColors.DisabledTextColor;

      if IsToday and not IsSel then
      begin
        Canvas.Stroke.Kind := TBrushKind.Solid;
        Canvas.Stroke.Color := FColors.SelectionColor;
        Canvas.Stroke.Thickness := 1;
        Canvas.DrawRect(Cell, 6, 6, AllCorners, 1);
        Canvas.Stroke.Kind := TBrushKind.None;
      end;

      Canvas.Font.Size := 12;
      Canvas.FillText(Cell, IntToStr(DayOf(D)), False, 1, [],
        TTextAlign.Center, TTextAlign.Center);
      D := D + 1;
    end;

    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := FColors.DividerColor;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(
      TPointF.Create(PAD, CAL_H - PAD - FOOT_H),
      TPointF.Create(CAL_W - PAD, CAL_H - PAD - FOOT_H), 1);

    Canvas.Font.Size := 12;
    Canvas.Fill.Color := FColors.SelectionColor;
    R := TRectF.Create(PAD, CAL_H - PAD - FOOT_H, CAL_W * 0.5, CAL_H - PAD);
    Canvas.FillText(R, 'Сегодня', False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Canvas.Fill.Color := FColors.SubTextColor;
    R := TRectF.Create(CAL_W * 0.5, CAL_H - PAD - FOOT_H, CAL_W - PAD, CAL_H - PAD);
    Canvas.FillText(R, 'Очистить', False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
  finally
    Canvas.EndScene;
  end;
end;

procedure TFluentDatePicker.CalMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
var
  C: Integer;
begin
  C := CellAt(X, Y);
  if C <> FHoverCell then
  begin
    FHoverCell := C;
    FPaint.Repaint;
  end;
end;

procedure TFluentDatePicker.CalMouseLeave(Sender: TObject);
begin
  if FHoverCell <> -1 then
  begin
    FHoverCell := -1;
    FPaint.Repaint;
  end;
end;

procedure TFluentDatePicker.CalMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  if WheelDelta > 0 then
    FView := IncMonth(FView, -1)
  else
    FView := IncMonth(FView, 1);
  Handled := True;
  FPaint.Repaint;
end;

procedure TFluentDatePicker.CalMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Nav, Foot, Cell: Integer;
  D: TDate;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  Nav := HeaderBtnAt(X, Y);
  if Nav <> 0 then
  begin
    FView := IncMonth(FView, Nav);
    FPaint.Repaint;
    Exit;
  end;
  Foot := FooterBtnAt(X, Y);
  if Foot = 1 then
  begin
    ApplyPicked(Date, True);
    FPopup.IsOpen := False;
    Exit;
  end;
  if Foot = 2 then
  begin
    ClearDate(True);
    FPopup.IsOpen := False;
    Exit;
  end;
  Cell := CellAt(X, Y);
  if Cell >= 0 then
  begin
    D := GridStart + Cell;
    ApplyPicked(D, True);
    FPopup.IsOpen := False;
  end;
end;

end.
