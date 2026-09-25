unit uCodeView;

{
  Просмотр кода: моноширинный поток, номера строк, выделение, подсветка.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  FMX.Platform, FMX.TextLayout,
  uAppSettings, uThemeManager, uTextCode, uCustomScrollbar, uFluentChrome;

type
  TCodeView = class(TLayout)
  private
    FPaint: TPaintBox;
    FVbar: TScrollBar;
    FHbar: TScrollBar;
    FVScroll: TCustomFileScrollbar;
    FHScroll: TCustomFileScrollbar;
    FMenu: TFluentPopupMenu;
    FColors: TThemeColors;
    FLines: TArray<string>;
    FStates: TArray<TLineState>;
    FLang: TTextLang;
    FHighlight: Boolean;
    FWrap: Boolean;
    FFace: string;
    FFontSize: Single;
    FLineH: Single;
    FCharW: Single;
    FGutter: Single;
    FMaxCols: Integer;
    FRowStart: TArray<Integer>;
    FColsPer: Integer;
    FCaretL: Integer;
    FCaretC: Integer;
    FAnchL: Integer;
    FAnchC: Integer;
    FHasCaret: Boolean;
    FDrag: Boolean;
    FUpdating: Boolean;
    FClicks: Integer;
    FClickTick: UInt64;
    FOnStatus: TNotifyEvent;
    procedure PaintCode(Sender: TObject; Canvas: TCanvas);
    procedure ScrollChanged(Sender: TObject);
    procedure ExtVScroll(AValue: Single);
    procedure ExtHScroll(AValue: Single);
    procedure SyncBars;
    procedure MeasureFont(Canvas: TCanvas);
    function ViewW: Single;
    function ViewH: Single;
    function ContentW: Single;
    procedure RebuildRows;
    function ContentH: Single;
    function DispCols(const S: string): Integer;
    function ColToDisp(const S: string; ACol: Integer): Integer;
    function DispToCol(const S: string; ADisp: Integer): Integer;
    function HitPos(X, Y: Single; out ALine, ACol: Integer): Boolean;
    procedure SetCaret(ALine, ACol: Integer; AExtend, ANotify: Boolean);
    procedure SelectWord(ALine, ACol: Integer);
    procedure SelectLine(ALine: Integer);
    procedure ClampCaret;
    procedure EnsureCaretVisible;
    procedure NotifyStatus;
    function NormRange(out L1, C1, L2, C2: Integer): Boolean;
    procedure MenuCopy(Sender: TObject);
    procedure MenuAll(Sender: TObject);
    procedure ShowMenu(X, Y: Single);
  protected
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetLines(const ALines: TArray<string>; ALang: TTextLang;
      AHighlight, AWrap: Boolean; AMaxCols: Integer);
    procedure SetHighlight(AOn: Boolean);
    procedure SetWrap(AOn: Boolean);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure Clear;
    procedure CopySelection;
    procedure SelectAll;
    function HasSelection: Boolean;
    function SelectedText: string;
    function CaretLine: Integer;
    function CaretCol: Integer;
    function SelCount: Integer;
    property OnStatus: TNotifyEvent read FOnStatus write FOnStatus;
    property Highlight: Boolean read FHighlight;
    property Wrap: Boolean read FWrap;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

const
  SB_GAP = 10;

function PickMonoFace: string;
{$IFDEF MSWINDOWS}
  function Installed(const AName: string): Boolean;
  var
    DC: HDC;
    Font, Old: HFONT;
    Buf: array[0..127] of Char;
  begin
    Result := False;
    Font := CreateFont(-16, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
      FIXED_PITCH or FF_DONTCARE, PChar(AName));
    if Font = 0 then
      Exit;
    DC := GetDC(0);
    try
      Old := SelectObject(DC, Font);
      GetTextFace(DC, Length(Buf), Buf);
      SelectObject(DC, Old);
      Result := SameText(string(Buf), AName);
    finally
      ReleaseDC(0, DC);
      DeleteObject(Font);
    end;
  end;
{$ENDIF}
begin
  Result := 'Consolas';
  {$IFDEF MSWINDOWS}
  if Installed('Cascadia Mono') then
    Result := 'Cascadia Mono'
  else if Installed('Consolas') then
    Result := 'Consolas'
  else
    Result := 'Courier New';
  {$ENDIF}
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
    ((C >= '0') and (C <= '9')) or (C = '_');
end;

constructor TCodeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;
  ClipChildren := True;
  FFace := PickMonoFace;
  FFontSize := 13;
  FLineH := 13 * 1.35;
  FCharW := 8;
  FGutter := 36;
  FCaretL := 0;
  FCaretC := 0;
  FAnchL := 0;
  FAnchC := 0;
  FColors := GetThemeColors(atSystem);

  FVbar := TScrollBar.Create(Self);
  FVbar.Parent := Self;
  FVbar.Orientation := TOrientation.Vertical;
  FVbar.Align := TAlignLayout.None;
  FVbar.Width := 0;
  FVbar.Visible := False;
  FVbar.HitTest := False;
  FVbar.OnChange := ScrollChanged;

  FHbar := TScrollBar.Create(Self);
  FHbar.Parent := Self;
  FHbar.Orientation := TOrientation.Horizontal;
  FHbar.Align := TAlignLayout.None;
  FHbar.Height := 0;
  FHbar.Visible := False;
  FHbar.HitTest := False;
  FHbar.OnChange := ScrollChanged;

  FPaint := TPaintBox.Create(Self);
  FPaint.Parent := Self;
  FPaint.Align := TAlignLayout.Client;
  FPaint.HitTest := False;
  FPaint.OnPaint := PaintCode;

  FVScroll := TCustomFileScrollbar.CreateForTrack(Self, Self, TOrientation.Vertical);
  FVScroll.OnExternalScroll := ExtVScroll;
  FHScroll := TCustomFileScrollbar.CreateForTrack(Self, Self, TOrientation.Horizontal);
  FHScroll.OnExternalScroll := ExtHScroll;

  FMenu := TFluentPopupMenu.Create(Self);
  FMenu.Parent := Self;
  FMenu.ApplyTheme(FColors);
end;

destructor TCodeView.Destroy;
begin
  if Assigned(FPaint) then
    FPaint.OnPaint := nil;
  FreeAndNil(FVScroll);
  FreeAndNil(FHScroll);
  inherited;
end;

procedure TCodeView.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  if Assigned(FVScroll) then
    FVScroll.ApplyTheme(AColors);
  if Assigned(FHScroll) then
    FHScroll.ApplyTheme(AColors);
  if Assigned(FMenu) then
    FMenu.ApplyTheme(AColors);
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TCodeView.Clear;
begin
  SetLength(FLines, 0);
  SetLength(FStates, 0);
  FHasCaret := False;
  FDrag := False;
  if Assigned(FVbar) then
    FVbar.Value := 0;
  if Assigned(FHbar) then
    FHbar.Value := 0;
  if Assigned(FPaint) then
    FPaint.Repaint;
  NotifyStatus;
end;

procedure TCodeView.SetLines(const ALines: TArray<string>; ALang: TTextLang;
  AHighlight, AWrap: Boolean; AMaxCols: Integer);
begin
  FLines := Copy(ALines);
  FLang := ALang;
  FHighlight := AHighlight;
  FWrap := AWrap;
  FMaxCols := Max(1, AMaxCols);
  if FHighlight and (FLang <> tlNone) then
    FStates := ScanLineStates(FLines, FLang)
  else
    SetLength(FStates, 0);
  FCaretL := 0;
  FCaretC := 0;
  FAnchL := 0;
  FAnchC := 0;
  FHasCaret := Length(FLines) > 0;
  FDrag := False;
  if Assigned(FVbar) then
    FVbar.Value := 0;
  if Assigned(FHbar) then
    FHbar.Value := 0;
  RebuildRows;
  SyncBars;
  if Assigned(FPaint) then
    FPaint.Repaint;
  NotifyStatus;
end;

procedure TCodeView.SetHighlight(AOn: Boolean);
begin
  FHighlight := AOn;
  if FHighlight and (FLang <> tlNone) and (Length(FStates) <> Length(FLines)) then
    FStates := ScanLineStates(FLines, FLang);
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TCodeView.SetWrap(AOn: Boolean);
begin
  FWrap := AOn;
  if FWrap and Assigned(FHbar) then
    FHbar.Value := 0;
  RebuildRows;
  SyncBars;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

function TCodeView.ViewW: Single;
begin
  Result := Max(1, Width - SB_GAP);
end;

function TCodeView.ViewH: Single;
begin
  Result := Max(1, Height - SB_GAP);
end;

procedure TCodeView.RebuildRows;
var
  I, N, Acc: Integer;
begin
  SetLength(FRowStart, Length(FLines) + 1);
  if not FWrap then
  begin
    for I := 0 to Length(FLines) do
      FRowStart[I] := I;
    FColsPer := 0;
    Exit;
  end;
  FColsPer := Max(8, Trunc((ViewW - FGutter - 8) / Max(1, FCharW)));
  Acc := 0;
  for I := 0 to High(FLines) do
  begin
    FRowStart[I] := Acc;
    N := DispCols(FLines[I]);
    if N <= 0 then
      N := 1
    else
      N := Max(1, (N + FColsPer - 1) div FColsPer);
    Inc(Acc, N);
  end;
  if Length(FLines) = 0 then
    FRowStart[0] := 0
  else
    FRowStart[Length(FLines)] := Acc;
end;

function TCodeView.ContentH: Single;
begin
  if Length(FRowStart) = Length(FLines) + 1 then
    Result := Max(FLineH, FRowStart[Length(FLines)] * FLineH + 8)
  else
    Result := Max(FLineH, Length(FLines) * FLineH + 8);
end;

function TCodeView.ContentW: Single;
begin
  if FWrap then
    Result := ViewW
  else
    Result := FGutter + FMaxCols * FCharW + 24;
end;

procedure TCodeView.SyncBars;
begin
  if FUpdating or not Assigned(FHbar) or not Assigned(FVbar) then
    Exit;
  FUpdating := True;
  try
    FVbar.Max := Max(0, ContentH - ViewH);
    FHbar.Max := Max(0, ContentW - ViewW);
    if FVbar.Value > FVbar.Max then
      FVbar.Value := FVbar.Max;
    if FHbar.Value > FHbar.Max then
      FHbar.Value := FHbar.Max;
    FVbar.SmallChange := FLineH;
    FHbar.SmallChange := FCharW * 4;
  finally
    FUpdating := False;
  end;
  if Assigned(FVScroll) then
    FVScroll.SetExternalMetrics(ContentH, ViewH, FVbar.Value);
  if Assigned(FHScroll) then
    FHScroll.SetExternalMetrics(ContentW, ViewW, FHbar.Value);
end;

procedure TCodeView.ScrollChanged(Sender: TObject);
begin
  if not FUpdating and Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TCodeView.ExtVScroll(AValue: Single);
begin
  if not Assigned(FVbar) then
    Exit;
  FVbar.Value := AValue;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TCodeView.ExtHScroll(AValue: Single);
begin
  if not Assigned(FHbar) then
    Exit;
  FHbar.Value := AValue;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TCodeView.Resize;
begin
  inherited;
  if FWrap then
    RebuildRows;
  SyncBars;
end;

procedure TCodeView.MeasureFont(Canvas: TCanvas);
begin
  Canvas.Font.Family := FFace;
  Canvas.Font.Size := FFontSize;
  Canvas.Font.Style := [];
  FCharW := Max(1, Canvas.TextWidth('0'));
  FLineH := FFontSize * 1.35;
  if Length(FLines) > 0 then
    FGutter := 14 + Max(2, Length(IntToStr(Length(FLines)))) * FCharW
  else
    FGutter := 14 + 2 * FCharW;
end;

function TCodeView.DispCols(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] = #9 then
      Inc(Result, 4)
    else
      Inc(Result);
end;

function TCodeView.ColToDisp(const S: string; ACol: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Min(ACol, Length(S)) do
    if S[I] = #9 then
      Inc(Result, 4)
    else
      Inc(Result);
end;

function TCodeView.DispToCol(const S: string; ADisp: Integer): Integer;
var
  I, D: Integer;
begin
  D := 0;
  Result := 0;
  for I := 1 to Length(S) do
  begin
    if D >= ADisp then
      Exit(I - 1);
    if S[I] = #9 then
      Inc(D, 4)
    else
      Inc(D);
    Result := I;
  end;
end;

function TCodeView.HitPos(X, Y: Single; out ALine, ACol: Integer): Boolean;
var
  S: string;
  Disp: Integer;
begin
  Result := False;
  ALine := 0;
  ACol := 0;
  if Length(FLines) = 0 then
    Exit;
  Disp := Trunc((Y + FVbar.Value) / FLineH);
  if Disp < 0 then
    Disp := 0;
  ALine := 0;
  if FWrap and (Length(FRowStart) = Length(FLines) + 1) then
  begin
    while (ALine < High(FLines)) and (FRowStart[ALine + 1] <= Disp) do
      Inc(ALine);
    Disp := (Disp - FRowStart[ALine]) * FColsPer +
      Trunc((X + FHbar.Value - FGutter) / FCharW);
  end
  else
  begin
    ALine := Disp;
    Disp := Trunc((X + FHbar.Value - FGutter) / FCharW);
  end;
  if ALine > High(FLines) then
    ALine := High(FLines);
  S := FLines[ALine];
  if Disp < 0 then
    Disp := 0;
  ACol := DispToCol(S, Disp);
  Result := True;
end;

procedure TCodeView.ClampCaret;
begin
  if Length(FLines) = 0 then
  begin
    FCaretL := 0;
    FCaretC := 0;
    FHasCaret := False;
    Exit;
  end;
  FCaretL := EnsureRange(FCaretL, 0, High(FLines));
  FCaretC := EnsureRange(FCaretC, 0, Length(FLines[FCaretL]));
  FHasCaret := True;
end;

procedure TCodeView.SetCaret(ALine, ACol: Integer; AExtend, ANotify: Boolean);
begin
  if not AExtend then
  begin
    FAnchL := ALine;
    FAnchC := ACol;
  end;
  FCaretL := ALine;
  FCaretC := ACol;
  ClampCaret;
  if not AExtend then
  begin
    FAnchL := FCaretL;
    FAnchC := FCaretC;
  end;
  EnsureCaretVisible;
  if Assigned(FPaint) then
    FPaint.Repaint;
  if ANotify then
    NotifyStatus;
end;

procedure TCodeView.EnsureCaretVisible;
var
  Y: Single;
begin
  if not FHasCaret or not Assigned(FVbar) then
    Exit;
  if (FCaretL >= 0) and (FCaretL < Length(FRowStart)) then
    Y := FRowStart[FCaretL] * FLineH
  else
    Y := FCaretL * FLineH;
  if Y < FVbar.Value then
    FVbar.Value := Y
  else if Y + FLineH > FVbar.Value + ViewH then
    FVbar.Value := Y + FLineH - ViewH;
  SyncBars;
end;

procedure TCodeView.NotifyStatus;
begin
  if Assigned(FOnStatus) then
    FOnStatus(Self);
end;

function TCodeView.NormRange(out L1, C1, L2, C2: Integer): Boolean;
begin
  L1 := FAnchL;
  C1 := FAnchC;
  L2 := FCaretL;
  C2 := FCaretC;
  if (L1 > L2) or ((L1 = L2) and (C1 > C2)) then
  begin
    L1 := FCaretL;
    C1 := FCaretC;
    L2 := FAnchL;
    C2 := FAnchC;
  end;
  Result := FHasCaret and ((L1 <> L2) or (C1 <> C2)) and (Length(FLines) > 0);
end;

function TCodeView.HasSelection: Boolean;
var
  L1, C1, L2, C2: Integer;
begin
  Result := NormRange(L1, C1, L2, C2);
end;

function TCodeView.SelectedText: string;
var
  L1, C1, L2, C2, I: Integer;
  SB: TStringBuilder;
begin
  Result := '';
  if not NormRange(L1, C1, L2, C2) then
    Exit;
  SB := TStringBuilder.Create;
  try
    if L1 = L2 then
      SB.Append(Copy(FLines[L1], C1 + 1, C2 - C1))
    else
    begin
      SB.Append(Copy(FLines[L1], C1 + 1, MaxInt));
      for I := L1 + 1 to L2 - 1 do
      begin
        SB.AppendLine;
        SB.Append(FLines[I]);
      end;
      SB.AppendLine;
      SB.Append(Copy(FLines[L2], 1, C2));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TCodeView.CaretLine: Integer;
begin
  if FHasCaret then
    Result := FCaretL + 1
  else
    Result := 0;
end;

function TCodeView.CaretCol: Integer;
begin
  if FHasCaret then
    Result := FCaretC + 1
  else
    Result := 0;
end;

function TCodeView.SelCount: Integer;
begin
  Result := Length(SelectedText);
end;

procedure TCodeView.CopySelection;
var
  Svc: IFMXClipboardService;
  S: string;
begin
  S := SelectedText;
  if S = '' then
    Exit;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Svc.SetClipboard(S);
end;

procedure TCodeView.SelectAll;
begin
  if Length(FLines) = 0 then
    Exit;
  FAnchL := 0;
  FAnchC := 0;
  FCaretL := High(FLines);
  FCaretC := Length(FLines[FCaretL]);
  FHasCaret := True;
  if Assigned(FPaint) then
    FPaint.Repaint;
  NotifyStatus;
end;

procedure TCodeView.SelectWord(ALine, ACol: Integer);
var
  S: string;
  A, B: Integer;
begin
  if (ALine < 0) or (ALine > High(FLines)) then
    Exit;
  S := FLines[ALine];
  if S = '' then
  begin
    SetCaret(ALine, 0, False, True);
    Exit;
  end;
  A := EnsureRange(ACol, 0, Length(S) - 1);
  if not IsWordChar(S[A + 1]) then
  begin
    SetCaret(ALine, ACol, False, True);
    Exit;
  end;
  B := A;
  while (A > 0) and IsWordChar(S[A]) do
    Dec(A);
  if not IsWordChar(S[A + 1]) then
    Inc(A);
  while (B < Length(S)) and IsWordChar(S[B + 1]) do
    Inc(B);
  FAnchL := ALine;
  FAnchC := A;
  FCaretL := ALine;
  FCaretC := B;
  FHasCaret := True;
  if Assigned(FPaint) then
    FPaint.Repaint;
  NotifyStatus;
end;

procedure TCodeView.SelectLine(ALine: Integer);
begin
  if (ALine < 0) or (ALine > High(FLines)) then
    Exit;
  FAnchL := ALine;
  FAnchC := 0;
  FCaretL := ALine;
  FCaretC := Length(FLines[ALine]);
  FHasCaret := True;
  if Assigned(FPaint) then
    FPaint.Repaint;
  NotifyStatus;
end;

procedure TCodeView.MenuCopy(Sender: TObject);
begin
  CopySelection;
end;

procedure TCodeView.MenuAll(Sender: TObject);
begin
  SelectAll;
end;

procedure TCodeView.ShowMenu(X, Y: Single);
begin
  if FMenu = nil then
    Exit;
  FMenu.ClearItems;
  FMenu.AddItem('Копировать', 'Ctrl+C', MenuCopy);
  FMenu.AddItem('Выделить всё', 'Ctrl+A', MenuAll);
  FMenu.ApplyTheme(FColors);
  FMenu.PopupAtCursor;
end;

procedure TCodeView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  L, C: Integer;
  NowTick: UInt64;
begin
  inherited;
  if CanFocus then
    SetFocus;
  if not HitPos(X, Y, L, C) then
    Exit;
  if Button = TMouseButton.mbRight then
  begin
    if not HasSelection then
      SetCaret(L, C, False, True);
    ShowMenu(X, Y);
    Exit;
  end;
  if Button <> TMouseButton.mbLeft then
    Exit;
  NowTick := TThread.GetTickCount64;
  if (NowTick - FClickTick < 450) and (L = FCaretL) then
    Inc(FClicks)
  else
    FClicks := 1;
  FClickTick := NowTick;
  if FClicks >= 3 then
  begin
    FClicks := 0;
    SelectLine(L);
    Exit;
  end;
  if FClicks = 2 then
  begin
    SelectWord(L, C);
    Exit;
  end;
  FDrag := True;
  SetCaret(L, C, ssShift in Shift, True);
  if Assigned(Root) then
    Root.Captured := Self;
end;

procedure TCodeView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  L, C: Integer;
begin
  inherited;
  if not FDrag then
    Exit;
  if HitPos(X, Y, L, C) then
    SetCaret(L, C, True, False);
end;

procedure TCodeView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FDrag then
    NotifyStatus;
  FDrag := False;
  if Assigned(Root) and Assigned(Root.Captured) and (Root.Captured.GetObject = Self) then
    Root.Captured := nil;
end;

procedure TCodeView.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  if ssShift in Shift then
    FHbar.Value := EnsureRange(FHbar.Value - WheelDelta / 4, 0, FHbar.Max)
  else
    FVbar.Value := EnsureRange(FVbar.Value - WheelDelta / 4, 0, FVbar.Max);
  Handled := True;
  SyncBars;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TCodeView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  L, C, Page: Integer;
  Extend: Boolean;
begin
  if Length(FLines) = 0 then
  begin
    inherited;
    Exit;
  end;
  Extend := ssShift in Shift;
  L := FCaretL;
  C := FCaretC;
  Page := Max(1, Trunc(ViewH / FLineH) - 1);
  case Key of
    vkLeft:
      if C > 0 then
        Dec(C)
      else if L > 0 then
      begin
        Dec(L);
        C := Length(FLines[L]);
      end;
    vkRight:
      if C < Length(FLines[L]) then
        Inc(C)
      else if L < High(FLines) then
      begin
        Inc(L);
        C := 0;
      end;
    vkUp:
      if L > 0 then
        Dec(L);
    vkDown:
      if L < High(FLines) then
        Inc(L);
    vkHome:
      if ssCtrl in Shift then
      begin
        L := 0;
        C := 0;
      end
      else
        C := 0;
    vkEnd:
      if ssCtrl in Shift then
      begin
        L := High(FLines);
        C := Length(FLines[L]);
      end
      else
        C := Length(FLines[L]);
    vkPrior:
      L := Max(0, L - Page);
    vkNext:
      L := Min(High(FLines), L + Page);
    vkA:
      if ssCtrl in Shift then
      begin
        SelectAll;
        Key := 0;
        KeyChar := #0;
        Exit;
      end
      else
      begin
        inherited;
        Exit;
      end;
    vkC, vkInsert:
      if ssCtrl in Shift then
      begin
        CopySelection;
        Key := 0;
        KeyChar := #0;
        Exit;
      end
      else
      begin
        inherited;
        Exit;
      end;
  else
    inherited;
    Exit;
  end;
  if L <> FCaretL then
    C := Min(C, Length(FLines[EnsureRange(L, 0, High(FLines))]));
  SetCaret(L, C, Extend, True);
  Key := 0;
  KeyChar := #0;
end;

procedure TCodeView.PaintCode(Sender: TObject; Canvas: TCanvas);
var
  I, First, Last, X0, D1, D2, L1, C1, L2, C2, P, Row, CaretDisp: Integer;
  Y, X: Single;
  S, Piece: string;
  Toks: TArray<TTextToken>;
  T: Integer;
  Enter: TLineState;
  Role: TTextRole;
  Sel: Boolean;
  R: TRectF;
begin
  if (Canvas = nil) or (FPaint = nil) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FPaint.LocalRect, 0, 0, [], 1);
  MeasureFont(Canvas);
  if Length(FLines) = 0 then
    Exit;
  RebuildRows;
  SyncBars;
  First := Max(0, Trunc(FVbar.Value / FLineH));
  Last := Min(High(FLines), First + Trunc(ViewH / FLineH) + 2);
  if FWrap and (Length(FRowStart) = Length(FLines) + 1) then
  begin
    First := 0;
    while (First < High(FLines)) and (FRowStart[First + 1] <= Trunc(FVbar.Value / FLineH)) do
      Inc(First);
    Last := First;
    while (Last < High(FLines)) and
          (FRowStart[Last] * FLineH - FVbar.Value < ViewH + FLineH) do
      Inc(Last);
  end;
  Sel := NormRange(L1, C1, L2, C2);
  Canvas.Fill.Color := FColors.HeaderBackground;
  Canvas.FillRect(RectF(0, 0, FGutter - 6, FPaint.Height), 0, 0, [], 1);
  for I := First to Last do
  begin
    if FWrap and (I < Length(FRowStart)) then
      Y := FRowStart[I] * FLineH - FVbar.Value
    else
      Y := I * FLineH - FVbar.Value;
    S := FLines[I];
    Canvas.Font.Family := FFace;
    Canvas.Font.Size := FFontSize;
    Canvas.Font.Style := [];
    Canvas.Fill.Color := FColors.SubTextColor;
    Canvas.FillText(RectF(4, Y, FGutter - 8, Y + FLineH), IntToStr(I + 1),
      False, 1, [], TTextAlign.Trailing, TTextAlign.Leading);
    if Sel and (I >= L1) and (I <= L2) then
    begin
      if I = L1 then
        D1 := ColToDisp(S, C1)
      else
        D1 := 0;
      if I = L2 then
        D2 := ColToDisp(S, C2)
      else
        D2 := Max(DispCols(S), D1 + 1);
      R := RectF(FGutter + D1 * FCharW - FHbar.Value, Y,
        FGutter + D2 * FCharW - FHbar.Value, Y + FLineH);
      Canvas.Fill.Color := FColors.SelectionColor;
      Canvas.FillRect(R, 0, 0, [], 0.45);
    end;
    if FWrap and (FColsPer > 0) and (DispCols(S) > FColsPer) then
    begin
      Piece := StringReplace(S, #9, '    ', [rfReplaceAll]);
      P := 1;
      Row := 0;
      if Sel and (I >= L1) and (I <= L2) then
        Canvas.Fill.Color := FColors.SelectionTextColor
      else
        Canvas.Fill.Color := FColors.TextColor;
      while P <= Length(Piece) do
      begin
        Canvas.FillText(RectF(FGutter, Y + Row * FLineH,
          FGutter + FColsPer * FCharW + 4, Y + (Row + 1) * FLineH),
          Copy(Piece, P, FColsPer), False, 1, [],
          TTextAlign.Leading, TTextAlign.Leading);
        Inc(P, FColsPer);
        Inc(Row);
      end;
      if FHasCaret and (I = FCaretL) and IsFocused then
      begin
        CaretDisp := ColToDisp(S, FCaretC);
        Row := CaretDisp div FColsPer;
        X := FGutter + (CaretDisp mod FColsPer) * FCharW;
        Canvas.Stroke.Kind := TBrushKind.Solid;
        Canvas.Stroke.Color := FColors.TextColor;
        Canvas.Stroke.Thickness := 1;
        Canvas.DrawLine(PointF(X, Y + Row * FLineH + 1),
          PointF(X, Y + (Row + 1) * FLineH - 1), 1);
      end;
      Continue;
    end;
    Enter := lsNormal;
    if I < Length(FStates) then
      Enter := FStates[I];
    SetLength(Toks, 0);
    if FHighlight then
      Toks := TokenizeLine(S, FLang, Enter);
    X0 := 0;
    X := FGutter - FHbar.Value;
    if Length(Toks) = 0 then
    begin
      Piece := StringReplace(S, #9, '    ', [rfReplaceAll]);
      if Sel and (I >= L1) and (I <= L2) then
        Canvas.Fill.Color := FColors.SelectionTextColor
      else
        Canvas.Fill.Color := FColors.TextColor;
      Canvas.FillText(RectF(X, Y, X + Length(Piece) * FCharW + 4, Y + FLineH),
        Piece, False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
    end
    else
    begin
      T := 0;
      while X0 < Length(S) do
      begin
        Role := trNormal;
        if (T <= High(Toks)) and (Toks[T].Start = X0) then
        begin
          Role := Toks[T].Role;
          Piece := Copy(S, X0 + 1, Toks[T].Len);
          Inc(X0, Toks[T].Len);
          Inc(T);
        end
        else
        begin
          Piece := S[X0 + 1];
          Inc(X0);
        end;
        Piece := StringReplace(Piece, #9, '    ', [rfReplaceAll]);
        if Sel and (I >= L1) and (I <= L2) then
          Canvas.Fill.Color := FColors.SelectionTextColor
        else
          Canvas.Fill.Color := TextRoleColor(Role, FColors);
        Canvas.FillText(RectF(X, Y, X + Length(Piece) * FCharW + 4, Y + FLineH),
          Piece, False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
        X := X + Length(Piece) * FCharW;
      end;
    end;
    if FHasCaret and (I = FCaretL) and IsFocused then
    begin
      X := FGutter + ColToDisp(S, FCaretC) * FCharW - FHbar.Value;
      Canvas.Stroke.Kind := TBrushKind.Solid;
      Canvas.Stroke.Color := FColors.TextColor;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawLine(PointF(X, Y + 1), PointF(X, Y + FLineH - 1), 1);
    end;
  end;
end;

end.
