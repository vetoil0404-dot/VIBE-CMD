unit uSpreadsheetGrid;

{
  Owner-draw FMX-грид для Quick View. Не использовать в плитках панели.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  FMX.Platform, FMX.Forms,
  uAppSettings, uThemeManager, uSpreadsheetData, uCustomScrollbar;

type
  TSpreadsheetGrid = class(TLayout)
  private
    FPaint: TPaintBox;
    FHbar: TScrollBar;
    FVbar: TScrollBar;
    FVScroll: TCustomFileScrollbar;
    FHScroll: TCustomFileScrollbar;
    FSheet: TSpreadSheet;
    FColors: TThemeColors;
    FColW: Single;
    FRowH: Single;
    FHeadH: Single;
    FHeadW: Single;
    FActiveRow: Integer;
    FActiveCol: Integer;
    FUpdating: Boolean;
    FBusy: Boolean;
    FPainting: Boolean;
    FLayoutTimer: TTimer;
    procedure PaintGrid(Sender: TObject; Canvas: TCanvas);
    procedure ScrollChanged(Sender: TObject);
    procedure SyncBars;
    procedure SyncCustomScroll;
    procedure ExtVScroll(AValue: Single);
    procedure ExtHScroll(AValue: Single);
    function ContentW: Single;
    function ContentH: Single;
    function ViewW: Single;
    function ViewH: Single;
    function RowH(ARow: Integer): Single;
    function RowOff(ARow: Integer): Single;
    function ColW(ACol: Integer): Single;
    function ColOff(ACol: Integer): Single;
    function CellRect(ARow, ACol: Integer): TRectF;
    procedure HitCell(X, Y: Single; out ARow, ACol: Integer);
    procedure CopyActive;
    procedure EnsureActiveVisible;
    procedure QueueLayout;
    procedure LayoutTimerTick(Sender: TObject);
  protected
    procedure Resize; override;
    procedure DoRealign; override;
    procedure SetVisible(const Value: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetSheet(ASheet: TSpreadSheet);
    procedure Clear;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SyncNow;
  end;

implementation

const
  SB_GAP = 10;

constructor TSpreadsheetGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;
  FColW := 78;
  FRowH := 22;
  FHeadH := 22;
  FHeadW := 42;
  FActiveRow := 1;
  FActiveCol := 1;
  FColors := GetThemeColors(atSystem);
  ClipChildren := True;

  FVbar := TScrollBar.Create(Self);
  FVbar.Parent := Self;
  FVbar.Orientation := TOrientation.Vertical;
  FVbar.Align := TAlignLayout.None;
  FVbar.Width := 0;
  FVbar.Height := 0;
  FVbar.Visible := False;
  FVbar.HitTest := False;
  FVbar.ViewportSize := 0;
  FVbar.OnChange := ScrollChanged;

  FHbar := TScrollBar.Create(Self);
  FHbar.Parent := Self;
  FHbar.Orientation := TOrientation.Horizontal;
  FHbar.Align := TAlignLayout.None;
  FHbar.Width := 0;
  FHbar.Height := 0;
  FHbar.Visible := False;
  FHbar.HitTest := False;
  FHbar.ViewportSize := 0;
  FHbar.OnChange := ScrollChanged;

  FPaint := TPaintBox.Create(Self);
  FPaint.Parent := Self;
  FPaint.Align := TAlignLayout.Client;
  FPaint.HitTest := False;
  FPaint.OnPaint := PaintGrid;
  FPaint.SendToBack;

  FVScroll := TCustomFileScrollbar.CreateForTrack(Self, Self, TOrientation.Vertical);
  FVScroll.OnExternalScroll := ExtVScroll;
  FHScroll := TCustomFileScrollbar.CreateForTrack(Self, Self, TOrientation.Horizontal);
  FHScroll.OnExternalScroll := ExtHScroll;

  FLayoutTimer := TTimer.Create(Self);
  FLayoutTimer.Interval := 16;
  FLayoutTimer.Enabled := False;
  FLayoutTimer.OnTimer := LayoutTimerTick;
end;

destructor TSpreadsheetGrid.Destroy;
begin
  if Assigned(FLayoutTimer) then
  begin
    FLayoutTimer.Enabled := False;
    FLayoutTimer.OnTimer := nil;
  end;
  FSheet := nil;
  if Assigned(FPaint) then
    FPaint.OnPaint := nil;
  FreeAndNil(FVScroll);
  FreeAndNil(FHScroll);
  inherited;
end;

procedure TSpreadsheetGrid.Clear;
begin
  FSheet := nil;
  FActiveRow := 1;
  FActiveCol := 1;
  if Assigned(FHbar) then
    FHbar.Value := 0;
  if Assigned(FVbar) then
    FVbar.Value := 0;
  if Assigned(FPaint) and not FPainting then
    FPaint.Repaint;
end;

procedure TSpreadsheetGrid.SetSheet(ASheet: TSpreadSheet);
begin
  FSheet := nil;
  FActiveRow := 1;
  FActiveCol := 1;
  if Assigned(FHbar) then
    FHbar.Value := 0;
  if Assigned(FVbar) then
    FVbar.Value := 0;
  FSheet := ASheet;
  if Assigned(FSheet) then
  try
    FSheet.RecalcRowHeights(0, 0, 0);
  except
  end;
  SyncNow;
end;

procedure TSpreadsheetGrid.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  if Assigned(FVScroll) then
    FVScroll.ApplyTheme(AColors);
  if Assigned(FHScroll) then
    FHScroll.ApplyTheme(AColors);
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

function TSpreadsheetGrid.ContentW: Single;
begin
  if Assigned(FSheet) then
    Result := FHeadW + FSheet.TotalWidth + 8
  else
    Result := FHeadW + FColW + 8;
end;

function TSpreadsheetGrid.ContentH: Single;
begin
  if Assigned(FSheet) then
    Result := FHeadH + FSheet.TotalHeight + 8
  else
    Result := FHeadH + FRowH + 8;
end;

function TSpreadsheetGrid.RowH(ARow: Integer): Single;
begin
  if Assigned(FSheet) then
    Result := FSheet.RowHeight(ARow)
  else
    Result := FRowH;
end;

function TSpreadsheetGrid.RowOff(ARow: Integer): Single;
begin
  if Assigned(FSheet) then
    Result := FSheet.RowTop(ARow)
  else
    Result := (ARow - 1) * FRowH;
end;

function TSpreadsheetGrid.ColW(ACol: Integer): Single;
begin
  if Assigned(FSheet) then
    Result := FSheet.ColWidth(ACol)
  else
    Result := FColW;
end;

function TSpreadsheetGrid.ColOff(ACol: Integer): Single;
begin
  if Assigned(FSheet) then
    Result := FSheet.ColLeft(ACol)
  else
    Result := (ACol - 1) * FColW;
end;

function TSpreadsheetGrid.ViewW: Single;
begin
  if Assigned(FPaint) and (FPaint.Width >= 1) then
    Result := FPaint.Width
  else
    Result := Max(1, Width);
end;

function TSpreadsheetGrid.ViewH: Single;
begin
  if Assigned(FPaint) and (FPaint.Height >= 1) then
    Result := FPaint.Height
  else
    Result := Max(1, Height);
end;

procedure TSpreadsheetGrid.QueueLayout;
begin
  if FBusy or FUpdating or FPainting then
    Exit;
  if (csDestroying in ComponentState) or not Visible then
    Exit;
  if (Width < 4) or (Height < 4) then
    Exit;
  if Assigned(FLayoutTimer) then
  begin
    FLayoutTimer.Enabled := False;
    FLayoutTimer.Enabled := True;
  end;
end;

procedure TSpreadsheetGrid.LayoutTimerTick(Sender: TObject);
begin
  if Assigned(FLayoutTimer) then
    FLayoutTimer.Enabled := False;
  if (csDestroying in ComponentState) or not Visible then
    Exit;
  SyncNow;
end;

procedure TSpreadsheetGrid.SyncBars;
begin
  if FUpdating or not Assigned(FHbar) or not Assigned(FVbar) then
    Exit;
  FUpdating := True;
  try
    FHbar.ViewportSize := 0;
    FVbar.ViewportSize := 0;
    FHbar.Max := Max(0, ContentW - ViewW);
    FVbar.Max := Max(0, ContentH - ViewH);
    if FHbar.Value > FHbar.Max then
      FHbar.Value := FHbar.Max;
    if FVbar.Value > FVbar.Max then
      FVbar.Value := FVbar.Max;
    if FHbar.Max <= 0 then
      FHbar.Value := 0;
    if FVbar.Max <= 0 then
      FVbar.Value := 0;
    FHbar.SmallChange := FColW;
    FVbar.SmallChange := FRowH;
  finally
    FUpdating := False;
  end;
  SyncCustomScroll;
end;

procedure TSpreadsheetGrid.SyncNow;
begin
  if FBusy or (csDestroying in ComponentState) or not Assigned(FPaint) then
    Exit;
  if (Width < 4) or (Height < 4) then
    Exit;
  FBusy := True;
  try
    SyncBars;
    if Assigned(FPaint) and not FPainting then
      FPaint.Repaint;
  finally
    FBusy := False;
  end;
end;

procedure TSpreadsheetGrid.SyncCustomScroll;
begin
  if Assigned(FVScroll) then
    FVScroll.SetExternalMetrics(ContentH, ViewH, FVbar.Value);
  if Assigned(FHScroll) then
    FHScroll.SetExternalMetrics(ContentW, ViewW, FHbar.Value);
end;

procedure TSpreadsheetGrid.ExtVScroll(AValue: Single);
begin
  if FBusy or FPainting or not Assigned(FVbar) then
    Exit;
  FVbar.Value := AValue;
  if Assigned(FPaint) and not FPainting then
    FPaint.Repaint;
end;

procedure TSpreadsheetGrid.ExtHScroll(AValue: Single);
begin
  if FBusy or FPainting or not Assigned(FHbar) then
    Exit;
  FHbar.Value := AValue;
  if Assigned(FPaint) and not FPainting then
    FPaint.Repaint;
end;

procedure TSpreadsheetGrid.Resize;
begin
  inherited;
  QueueLayout;
end;

procedure TSpreadsheetGrid.DoRealign;
begin
  inherited;
  QueueLayout;
end;

procedure TSpreadsheetGrid.SetVisible(const Value: Boolean);
begin
  inherited;
  if Value then
    QueueLayout;
end;

procedure TSpreadsheetGrid.ScrollChanged(Sender: TObject);
begin
  if not FUpdating and not FPainting and not FBusy and Assigned(FPaint) then
    FPaint.Repaint;
end;

function TSpreadsheetGrid.CellRect(ARow, ACol: Integer): TRectF;
var
  X, Y, Hx, Vy: Single;
begin
  Hx := 0;
  Vy := 0;
  if Assigned(FHbar) then
    Hx := FHbar.Value;
  if Assigned(FVbar) then
    Vy := FVbar.Value;
  X := FHeadW + ColOff(ACol) - Hx;
  Y := FHeadH + RowOff(ARow) - Vy;
  Result := TRectF.Create(X, Y, X + ColW(ACol), Y + RowH(ARow));
end;

procedure TSpreadsheetGrid.HitCell(X, Y: Single; out ARow, ACol: Integer);
var
  Cy, Cx, Acc: Single;
  R, C, MaxR, MaxC: Integer;
begin
  Cx := X - FHeadW + FHbar.Value;
  ACol := 1;
  MaxC := 1;
  if Assigned(FSheet) then
    MaxC := Max(1, FSheet.ColCount);
  Acc := 0;
  for C := 1 to MaxC do
  begin
    Acc := Acc + ColW(C);
    if Cx < Acc then
    begin
      ACol := C;
      Break;
    end;
    ACol := C;
  end;
  Cy := Y - FHeadH + FVbar.Value;
  ARow := 1;
  MaxR := 1;
  if Assigned(FSheet) then
    MaxR := Max(1, FSheet.RowCount);
  Acc := 0;
  for R := 1 to MaxR do
  begin
    Acc := Acc + RowH(R);
    if Cy < Acc then
    begin
      ARow := R;
      Break;
    end;
    ARow := R;
  end;
  if Assigned(FSheet) then
  begin
    ACol := EnsureRange(ACol, 1, Max(1, FSheet.ColCount));
    ARow := EnsureRange(ARow, 1, Max(1, FSheet.RowCount));
  end
  else
  begin
    ACol := 1;
    ARow := 1;
  end;
end;

procedure TSpreadsheetGrid.EnsureActiveVisible;
var
  R: TRectF;
begin
  R := CellRect(FActiveRow, FActiveCol);
  if R.Right > ViewW then
    FHbar.Value := FHbar.Value + (R.Right - ViewW);
  if R.Left < FHeadW then
    FHbar.Value := FHbar.Value - (FHeadW - R.Left);
  if R.Bottom > ViewH then
    FVbar.Value := FVbar.Value + (R.Bottom - ViewH);
  if R.Top < FHeadH then
    FVbar.Value := FVbar.Value - (FHeadH - R.Top);
  SyncCustomScroll;
end;

procedure TSpreadsheetGrid.CopyActive;
var
  Svc: IFMXClipboardService;
  Cell: TSpreadCell;
begin
  if not Assigned(FSheet) then
    Exit;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit;
  Cell := FSheet.Cell(FActiveRow, FActiveCol);
  Svc.SetClipboard(Cell.Value);
end;

procedure TSpreadsheetGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if CanFocus then
    SetFocus;
  if Button <> TMouseButton.mbLeft then
    Exit;
  if (X > Width - SB_GAP) or (Y > Height - SB_GAP) then
    Exit;
  HitCell(X, Y, FActiveRow, FActiveCol);
  EnsureActiveVisible;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TSpreadsheetGrid.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  if ssShift in Shift then
    FHbar.Value := EnsureRange(FHbar.Value - WheelDelta / 4, 0, FHbar.Max)
  else
    FVbar.Value := EnsureRange(FVbar.Value - WheelDelta / 4, 0, FVbar.Max);
  Handled := True;
  SyncCustomScroll;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TSpreadsheetGrid.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  MaxR, MaxC: Integer;
  R: Integer;
  Line: string;
  C: Integer;
  Svc: IFMXClipboardService;
  Handled: Boolean;
begin
  MaxR := 1;
  MaxC := 1;
  if Assigned(FSheet) then
  begin
    MaxR := Max(1, FSheet.RowCount);
    MaxC := Max(1, FSheet.ColCount);
  end;
  Handled := True;
  case Key of
    vkLeft:
      FActiveCol := Max(1, FActiveCol - 1);
    vkRight:
      FActiveCol := Min(MaxC, FActiveCol + 1);
    vkUp:
      FActiveRow := Max(1, FActiveRow - 1);
    vkDown:
      FActiveRow := Min(MaxR, FActiveRow + 1);
    vkPrior:
      FActiveRow := Max(1, FActiveRow - Max(1, Trunc(ViewH / FRowH) - 1));
    vkNext:
      FActiveRow := Min(MaxR, FActiveRow + Max(1, Trunc(ViewH / FRowH) - 1));
    vkHome:
      if ssCtrl in Shift then
      begin
        FActiveRow := 1;
        FActiveCol := 1;
      end
      else
        FActiveCol := 1;
    vkEnd:
      if ssCtrl in Shift then
      begin
        FActiveRow := MaxR;
        FActiveCol := MaxC;
      end
      else
        FActiveCol := MaxC;
    vkC:
      if ssCtrl in Shift then
      begin
        if ssShift in Shift then
        begin
          if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) and
             Assigned(FSheet) then
          begin
            Line := '';
            for R := 1 to FSheet.RowCount do
            begin
              if R > 1 then
                Line := Line + sLineBreak;
              for C := 1 to FSheet.ColCount do
              begin
                if C > 1 then
                  Line := Line + #9;
                Line := Line + FSheet.Cell(R, C).Value;
              end;
            end;
            Svc.SetClipboard(Copy(Line, 1, 256 * 1024));
          end;
        end
        else
          CopyActive;
      end
      else
        Handled := False;
  else
    Handled := False;
  end;
  if Handled then
  begin
    Key := 0;
    KeyChar := #0;
    EnsureActiveVisible;
    if Assigned(FPaint) then
      FPaint.Repaint;
  end
  else
    inherited;
end;

procedure TSpreadsheetGrid.PaintGrid(Sender: TObject; Canvas: TCanvas);
var
  Rows, Cols, R, C, R0, C0, R1, C1: Integer;
  CR, HR, VR: TRectF;
  Cell: TSpreadCell;
  Img: TSpreadImage;
  Align: TTextAlign;
  ImgR: TRectF;
  FillC, TextC, SheetLine, SheetText, SheetBg, SheetAlt: TAlphaColor;
  HeadBg, HeadText, HeadLine: TAlphaColor;
  Sheet: TSpreadSheet;
  HVal, VVal: Single;
begin
  if FPainting or (csDestroying in ComponentState) or not Assigned(FPaint) or
     (FPaint.Width < 2) or (FPaint.Height < 2) or (Canvas = nil) then
    Exit;
  FPainting := True;
  try
  try
  HVal := 0;
  VVal := 0;
  if Assigned(FHbar) then
    HVal := FHbar.Value;
  if Assigned(FVbar) then
    VVal := FVbar.Value;
  { Тело таблицы всегда светлое (зебра Excel). Цвета заливки и текста ячеек
    из файла не меняем. Шапка A/B/C и столбец 1,2,3 — тёмные в тёмной теме. }
  SheetBg := $FFFFFFFF;
  SheetAlt := $FFF3F3F3;
  SheetLine := $FFD0D0D0;
  SheetText := $FF222222;
  if FColors.IsDark then
  begin
    HeadBg := FColors.HeaderBackground;
    HeadText := FColors.TextColor;
    HeadLine := $FF4A4A4A;
  end
  else
  begin
    HeadBg := FColors.HeaderBackground;
    HeadText := FColors.TextColor;
    HeadLine := $FFD0D0D0;
  end;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FPaint.LocalRect, 0, 0, [], 1);
  Rows := 1;
  Cols := 1;
  Sheet := FSheet;
  if Assigned(Sheet) then
  begin
    Rows := Max(1, Sheet.RowCount);
    Cols := Max(1, Sheet.ColCount);
  end;
  C0 := 1;
  while (C0 < Cols) and (ColOff(C0 + 1) < HVal) do
    Inc(C0);
  C1 := C0;
  while (C1 < Cols) and (ColOff(C1) < HVal + ViewW) do
    Inc(C1);
  R0 := 1;
  while (R0 < Rows) and (RowOff(R0 + 1) < VVal) do
    Inc(R0);
  R1 := R0;
  while (R1 < Rows) and (RowOff(R1) < VVal + ViewH) do
    Inc(R1);

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := 1;
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 12;

  for R := R0 to R1 do
    for C := C0 to C1 do
    begin
      CR := CellRect(R, C);
      Cell := Default(TSpreadCell);
      if Assigned(Sheet) and (FSheet = Sheet) then
        Cell := Sheet.Cell(R, C);
      if Cell.HasFill then
        FillC := Cell.FillColor
      else if Odd(R) then
        FillC := SheetAlt
      else
        FillC := SheetBg;
      Canvas.Fill.Color := FillC;
      Canvas.FillRect(CR, 0, 0, [], 1);
      Canvas.Stroke.Color := SheetLine;
      Canvas.DrawRect(CR, 0, 0, [], 1);
      if Assigned(Sheet) and (FSheet = Sheet) then
      begin
        Img := Sheet.ImageAt(R, C);
        if Assigned(Img) and Assigned(Img.Bitmap) and (Img.Bitmap.Width > 0) then
        begin
          ImgR := CR;
          ImgR.Inflate(-3, -3);
          ImgR := FitAspectRect(ImgR, Img.Bitmap.Width, Img.Bitmap.Height);
          Canvas.DrawBitmap(Img.Bitmap, Img.Bitmap.Bounds, ImgR, 1, True);
        end
        else if Cell.Value <> '' then
        begin
          if Cell.Kind = sckNumber then
            Align := TTextAlign.Trailing
          else
            Align := TTextAlign.Leading;
          if Cell.HasTextColor then
            TextC := Cell.TextColor
          else
            TextC := SheetText;
          Canvas.Fill.Color := TextC;
          Canvas.FillText(TRectF.Create(CR.Left + 4, CR.Top + 2, CR.Right - 4, CR.Bottom - 2),
            Cell.Value, True, 1, [], Align, TTextAlign.Leading);
        end;
      end;
    end;

  Canvas.Fill.Color := HeadBg;
  Canvas.FillRect(TRectF.Create(0, 0, ViewW, FHeadH), 0, 0, [], 1);
  Canvas.FillRect(TRectF.Create(0, 0, FHeadW, ViewH), 0, 0, [], 1);

  Canvas.Stroke.Color := HeadLine;
  for C := C0 to C1 do
  begin
    HR := TRectF.Create(FHeadW + ColOff(C) - HVal, 0,
      FHeadW + ColOff(C) + ColW(C) - HVal, FHeadH);
    Canvas.Fill.Color := HeadBg;
    Canvas.FillRect(HR, 0, 0, [], 1);
    Canvas.DrawRect(HR, 0, 0, [], 1);
    Canvas.Fill.Color := HeadText;
    Canvas.FillText(HR, ColIndexToName(C), False, 1, [], TTextAlign.Center, TTextAlign.Center);
  end;
  for R := R0 to R1 do
  begin
    VR := TRectF.Create(0, FHeadH + RowOff(R) - VVal, FHeadW,
      FHeadH + RowOff(R) + RowH(R) - VVal);
    Canvas.Fill.Color := HeadBg;
    Canvas.FillRect(VR, 0, 0, [], 1);
    Canvas.DrawRect(VR, 0, 0, [], 1);
    Canvas.Fill.Color := HeadText;
    Canvas.FillText(VR, IntToStr(R), False, 1, [], TTextAlign.Center, TTextAlign.Center);
  end;
  Canvas.Fill.Color := HeadBg;
  Canvas.FillRect(TRectF.Create(0, 0, FHeadW, FHeadH), 0, 0, [], 1);
  Canvas.Stroke.Color := HeadLine;
  Canvas.DrawRect(TRectF.Create(0, 0, FHeadW, FHeadH), 0, 0, [], 1);

  CR := CellRect(FActiveRow, FActiveCol);
  Canvas.Stroke.Color := FColors.SelectionColor;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(CR, 0, 0, [], 1);
  Canvas.Stroke.Thickness := 1;

  Canvas.Stroke.Color := FColors.CardStroke;
  Canvas.Stroke.Thickness := 1.5;
  Canvas.DrawRect(TRectF.Create(FHeadW, FHeadH,
    Min(ViewW, FHeadW + ContentW - FHeadW - 8 - HVal),
    Min(ViewH, FHeadH + ContentH - FHeadH - 8 - VVal)), 0, 0, [], 1);
  except
  end;
  finally
    FPainting := False;
  end;
end;

end.
