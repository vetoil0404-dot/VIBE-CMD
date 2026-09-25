unit uDocumentView;

{
  Owner-draw просмотр документа: страницы как бумажные листы.
  Не использовать в плитках панели.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  FMX.Platform, FMX.Forms, FMX.TextLayout,
  uAppSettings, uThemeManager, uDocumentData, uCustomScrollbar, uFluentChrome;

type
  TDocumentView = class(TLayout)
  private
    FPaint: TPaintBox;
    FHbar: TScrollBar;
    FVbar: TScrollBar;
    FVScroll: TCustomFileScrollbar;
    FHScroll: TCustomFileScrollbar;
    FDoc: TDocDocument;
    FColors: TThemeColors;
    FUpdating: Boolean;
    FBusy: Boolean;
    FPainting: Boolean;
    FLayoutTimer: TTimer;
    FScale: Single;
    FPad: Single;
    FGap: Single;
    FActivePage: Integer;
    FLines: TArray<string>;
    FCaretL: Integer;
    FCaretC: Integer;
    FAnchL: Integer;
    FAnchC: Integer;
    FHasCaret: Boolean;
    FDrag: Boolean;
    FClicks: Integer;
    FClickTick: UInt64;
    FMenu: TFluentPopupMenu;
    FOnStatus: TNotifyEvent;
    procedure PaintPages(Sender: TObject; Canvas: TCanvas);
    function HitDoc(X, Y: Single; out ALine, ACol: Integer): Boolean;
    procedure SetCaretDoc(ALine, ACol: Integer; AExtend: Boolean);
    function DocRange(out L1, C1, L2, C2: Integer): Boolean;
    procedure NotifyStatus;
    procedure RevealLine(ALine: Integer);
    procedure MenuCopy(Sender: TObject);
    procedure MenuAll(Sender: TObject);
    procedure AdoptLayoutLines;
    procedure ScrollChanged(Sender: TObject);
    procedure SyncBars;
    procedure SyncCustomScroll;
    procedure ExtVScroll(AValue: Single);
    procedure ExtHScroll(AValue: Single);
    procedure QueueLayout;
    procedure LayoutTimerTick(Sender: TObject);
    function PageW: Single;
    function PageH: Single;
    function ContentW: Single;
    function ContentH: Single;
    function ViewW: Single;
    function ViewH: Single;
    function PaperRect(AIndex: Integer): TRectF;
    procedure EnsurePageVisible(AIndex: Integer);
    procedure CopyText;
    procedure UpdateScale;
  protected
    procedure Resize; override;
    procedure DoRealign; override;
    procedure SetVisible(const Value: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetDocument(ADoc: TDocDocument);
    procedure Clear;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SyncNow;
    procedure GoToPage(AIndex: Integer);
    function PageCount: Integer;
    function ActivePage: Integer;
    procedure SetSourceLines(const ALines: TArray<string>);
    procedure CopySelection;
    procedure SelectAllText;
    function HasTextSelection: Boolean;
    function SelectedText: string;
    function CaretLine: Integer;
    function CaretCol: Integer;
    function SelCount: Integer;
    property OnStatus: TNotifyEvent read FOnStatus write FOnStatus;
  end;

implementation

const
  SB_GAP = 10;

constructor TDocumentView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;
  ClipChildren := True;
  FScale := 1;
  FPad := 22;
  FGap := 18;
  FActivePage := 0;
  FColors := GetThemeColors(atSystem);

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
  FPaint.OnPaint := PaintPages;
  FPaint.SendToBack;

  FVScroll := TCustomFileScrollbar.CreateForTrack(Self, Self, TOrientation.Vertical);
  FVScroll.OnExternalScroll := ExtVScroll;
  FHScroll := TCustomFileScrollbar.CreateForTrack(Self, Self, TOrientation.Horizontal);
  FHScroll.OnExternalScroll := ExtHScroll;

  FLayoutTimer := TTimer.Create(Self);
  FLayoutTimer.Interval := 16;
  FLayoutTimer.Enabled := False;
  FLayoutTimer.OnTimer := LayoutTimerTick;

  FMenu := TFluentPopupMenu.Create(Self);
  FMenu.Parent := Self;
  FMenu.ApplyTheme(FColors);
end;

destructor TDocumentView.Destroy;
begin
  if Assigned(FLayoutTimer) then
  begin
    FLayoutTimer.Enabled := False;
    FLayoutTimer.OnTimer := nil;
  end;
  FDoc := nil;
  if Assigned(FPaint) then
    FPaint.OnPaint := nil;
  FreeAndNil(FVScroll);
  FreeAndNil(FHScroll);
  inherited;
end;

procedure TDocumentView.Clear;
begin
  FDoc := nil;
  FActivePage := 0;
  SetLength(FLines, 0);
  FHasCaret := False;
  FDrag := False;
  if Assigned(FHbar) then
    FHbar.Value := 0;
  if Assigned(FVbar) then
    FVbar.Value := 0;
  if Assigned(FPaint) and not FPainting then
    FPaint.Repaint;
end;

procedure TDocumentView.AdoptLayoutLines;
var
  I, J, Line, Col: Integer;
  Page: TDocLaidPage;
  It: TDocPaintItem;
  Y: Single;
begin
  if (FDoc = nil) or (FDoc.Pages = nil) then
    Exit;
  for I := 0 to FDoc.Pages.Count - 1 do
  begin
    Page := FDoc.Pages[I];
    if (Page = nil) or (Page.Items = nil) then
      Continue;
    for J := 0 to Page.Items.Count - 1 do
      if (Page.Items[J] <> nil) and (Page.Items[J].Kind = dpkText) and
         (Page.Items[J].SrcLine >= 0) then
        Exit;
  end;
  SetLength(FLines, 0);
  Line := -1;
  for I := 0 to FDoc.Pages.Count - 1 do
  begin
    Page := FDoc.Pages[I];
    if (Page = nil) or (Page.Items = nil) then
      Continue;
    Y := -10000;
    Col := 0;
    for J := 0 to Page.Items.Count - 1 do
    begin
      It := Page.Items[J];
      if (It = nil) or (It.Kind <> dpkText) or (It.Text = '') then
        Continue;
      if Abs(It.Y - Y) > 1.5 then
      begin
        Inc(Line);
        Y := It.Y;
        Col := 0;
        SetLength(FLines, Line + 1);
        FLines[Line] := '';
      end;
      It.SrcLine := Line;
      It.SrcCol := Col;
      It.SrcEnd := Line;
      FLines[Line] := FLines[Line] + It.Text;
      Inc(Col, Length(It.Text));
    end;
  end;
  FCaretL := 0;
  FCaretC := 0;
  FAnchL := 0;
  FAnchC := 0;
  FHasCaret := Length(FLines) > 0;
end;

procedure TDocumentView.SetDocument(ADoc: TDocDocument);
begin
  FDoc := nil;
  FActivePage := 0;
  SetLength(FLines, 0);
  FHasCaret := False;
  FDrag := False;
  if Assigned(FHbar) then
    FHbar.Value := 0;
  if Assigned(FVbar) then
    FVbar.Value := 0;
  FDoc := ADoc;
  if Assigned(FDoc) then
  try
    if FDoc.Pages.Count = 0 then
      FDoc.BuildLayout;
    AdoptLayoutLines;
  except
    FDoc := nil;
    if Assigned(FPaint) then
      FPaint.Repaint;
    Exit;
  end;
  SyncNow;
end;

procedure TDocumentView.ApplyTheme(const AColors: TThemeColors);
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

function TDocumentView.PageCount: Integer;
begin
  if Assigned(FDoc) then
    Result := FDoc.Pages.Count
  else
    Result := 0;
end;

function TDocumentView.ActivePage: Integer;
begin
  Result := FActivePage;
end;

function TDocumentView.PageW: Single;
var
  I: Integer;
begin
  Result := 794;
  if not Assigned(FDoc) then
    Exit;
  for I := 0 to FDoc.Pages.Count - 1 do
    Result := Max(Result, FDoc.Pages[I].PaperW);
end;

function TDocumentView.PageH: Single;
begin
  Result := 1123;
  if Assigned(FDoc) and (FDoc.Pages.Count > 0) then
    Result := FDoc.Pages[0].PaperH;
end;

procedure TDocumentView.UpdateScale;
var
  Avail: Single;
begin
  Avail := Max(80, ViewW - FPad * 2);
  if PageW > 1 then
    FScale := Avail / PageW
  else
    FScale := 1;
  if FScale > 1.15 then
    FScale := 1.15;
  if FScale < 0.28 then
    FScale := 0.28;
end;

function TDocumentView.ViewW: Single;
begin
  if Assigned(FPaint) and (FPaint.Width >= 1) then
    Result := FPaint.Width
  else
    Result := Max(1, Width);
end;

function TDocumentView.ViewH: Single;
begin
  if Assigned(FPaint) and (FPaint.Height >= 1) then
    Result := FPaint.Height
  else
    Result := Max(1, Height);
end;

function TDocumentView.ContentW: Single;
begin
  Result := FPad * 2 + PageW * FScale;
end;

function TDocumentView.ContentH: Single;
var
  I: Integer;
begin
  Result := FPad;
  if not Assigned(FDoc) or (FDoc.Pages.Count = 0) then
    Exit(FPad * 2 + PageH * FScale);
  for I := 0 to FDoc.Pages.Count - 1 do
    Result := Result + FDoc.Pages[I].PaperH * FScale + FGap;
  Result := Result + FPad;
end;

function TDocumentView.PaperRect(AIndex: Integer): TRectF;
var
  I: Integer;
  Y, W, H, X: Single;
begin
  Result := TRectF.Empty;
  if (FDoc = nil) or (AIndex < 0) or (AIndex >= FDoc.Pages.Count) then
    Exit;
  if not Assigned(FHbar) or not Assigned(FVbar) then
    Exit;
  Y := FPad;
  for I := 0 to AIndex - 1 do
    Y := Y + FDoc.Pages[I].PaperH * FScale + FGap;
  W := FDoc.Pages[AIndex].PaperW * FScale;
  H := FDoc.Pages[AIndex].PaperH * FScale;
  X := Max(FPad, (ViewW - W) / 2);
  Result := TRectF.Create(X - FHbar.Value, Y - FVbar.Value, 0, 0);
  Result.Width := W;
  Result.Height := H;
end;

procedure TDocumentView.QueueLayout;
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

procedure TDocumentView.LayoutTimerTick(Sender: TObject);
begin
  if Assigned(FLayoutTimer) then
    FLayoutTimer.Enabled := False;
  if (csDestroying in ComponentState) or not Visible then
    Exit;
  SyncNow;
end;

procedure TDocumentView.SyncBars;
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
    FHbar.SmallChange := 48;
    FVbar.SmallChange := 48;
  finally
    FUpdating := False;
  end;
  SyncCustomScroll;
end;

procedure TDocumentView.SyncNow;
begin
  if FBusy or (csDestroying in ComponentState) or not Assigned(FPaint) then
    Exit;
  if (Width < 4) or (Height < 4) then
    Exit;
  FBusy := True;
  try
    UpdateScale;
    SyncBars;
    if Assigned(FPaint) and not FPainting then
      FPaint.Repaint;
  finally
    FBusy := False;
  end;
end;

procedure TDocumentView.SyncCustomScroll;
begin
  if Assigned(FVScroll) then
    FVScroll.SetExternalMetrics(ContentH, ViewH, FVbar.Value);
  if Assigned(FHScroll) then
    FHScroll.SetExternalMetrics(ContentW, ViewW, FHbar.Value);
end;

procedure TDocumentView.ExtVScroll(AValue: Single);
begin
  if FBusy or FPainting or not Assigned(FVbar) then
    Exit;
  FVbar.Value := AValue;
  if Assigned(FPaint) and not FPainting then
    FPaint.Repaint;
end;

procedure TDocumentView.ExtHScroll(AValue: Single);
begin
  if FBusy or FPainting or not Assigned(FHbar) then
    Exit;
  FHbar.Value := AValue;
  if Assigned(FPaint) and not FPainting then
    FPaint.Repaint;
end;

procedure TDocumentView.Resize;
begin
  inherited;
  QueueLayout;
end;

procedure TDocumentView.DoRealign;
begin
  inherited;
  QueueLayout;
end;

procedure TDocumentView.SetVisible(const Value: Boolean);
begin
  inherited;
  if Value then
    QueueLayout;
end;

procedure TDocumentView.ScrollChanged(Sender: TObject);
begin
  if not FUpdating and not FPainting and not FBusy and Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TDocumentView.EnsurePageVisible(AIndex: Integer);
var
  R: TRectF;
begin
  if FDoc = nil then
    Exit;
  AIndex := EnsureRange(AIndex, 0, Max(0, FDoc.Pages.Count - 1));
  FActivePage := AIndex;
  R := PaperRect(AIndex);
  if R.Top < FPad then
    FVbar.Value := FVbar.Value + (R.Top - FPad);
  if R.Bottom > ViewH - 8 then
    FVbar.Value := FVbar.Value + (R.Bottom - ViewH + 8);
  FVbar.Value := EnsureRange(FVbar.Value, 0, FVbar.Max);
  SyncCustomScroll;
end;

procedure TDocumentView.GoToPage(AIndex: Integer);
begin
  EnsurePageVisible(AIndex);
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TDocumentView.CopyText;
var
  Svc: IFMXClipboardService;
begin
  if Length(FLines) > 0 then
  begin
    CopySelection;
    Exit;
  end;
  if not Assigned(FDoc) then
    Exit;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit;
  Svc.SetClipboard(Copy(FDoc.PlainText, 1, 256 * 1024));
end;

procedure TDocumentView.NotifyStatus;
begin
  if Assigned(FOnStatus) then
    FOnStatus(Self);
end;

procedure TDocumentView.SetSourceLines(const ALines: TArray<string>);
begin
  FLines := Copy(ALines);
  FCaretL := 0;
  FCaretC := 0;
  FAnchL := 0;
  FAnchC := 0;
  FHasCaret := Length(FLines) > 0;
  FDrag := False;
  NotifyStatus;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

function TDocumentView.DocRange(out L1, C1, L2, C2: Integer): Boolean;
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
  Result := FHasCaret and (Length(FLines) > 0) and ((L1 <> L2) or (C1 <> C2));
end;

function TDocumentView.HasTextSelection: Boolean;
var
  L1, C1, L2, C2: Integer;
begin
  Result := DocRange(L1, C1, L2, C2);
end;

function TDocumentView.SelectedText: string;
var
  L1, C1, L2, C2, I: Integer;
  SB: TStringBuilder;
begin
  Result := '';
  if not DocRange(L1, C1, L2, C2) then
    Exit;
  L1 := EnsureRange(L1, 0, High(FLines));
  L2 := EnsureRange(L2, 0, High(FLines));
  C1 := EnsureRange(C1, 0, Length(FLines[L1]));
  C2 := EnsureRange(C2, 0, Length(FLines[L2]));
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

function TDocumentView.CaretLine: Integer;
begin
  if FHasCaret then
    Result := FCaretL + 1
  else
    Result := 0;
end;

function TDocumentView.CaretCol: Integer;
begin
  if FHasCaret then
    Result := FCaretC + 1
  else
    Result := 0;
end;

function TDocumentView.SelCount: Integer;
begin
  Result := Length(SelectedText);
end;

procedure TDocumentView.CopySelection;
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

procedure TDocumentView.SelectAllText;
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

procedure TDocumentView.MenuCopy(Sender: TObject);
begin
  CopySelection;
end;

procedure TDocumentView.MenuAll(Sender: TObject);
begin
  SelectAllText;
end;

function TDocumentView.HitDoc(X, Y: Single; out ALine, ACol: Integer): Boolean;
var
  I, J: Integer;
  Page: TDocLaidPage;
  It: TDocPaintItem;
  PR, IR: TRectF;
  Local: Single;
begin
  Result := False;
  ALine := 0;
  ACol := 0;
  if (FDoc = nil) or (Length(FLines) = 0) then
    Exit;
  for I := 0 to FDoc.Pages.Count - 1 do
  begin
    Page := FDoc.Pages[I];
    if (Page = nil) or (Page.Items = nil) then
      Continue;
    PR := PaperRect(I);
    if (Y < PR.Top - 4) or (Y > PR.Bottom + 4) then
      Continue;
    for J := 0 to Page.Items.Count - 1 do
    begin
      It := Page.Items[J];
      if (It = nil) or (It.Kind <> dpkText) or (It.SrcLine < 0) then
        Continue;
      IR := TRectF.Create(
        PR.Left + It.X * FScale,
        PR.Top + It.Y * FScale,
        PR.Left + (It.X + Max(It.W, 1)) * FScale,
        PR.Top + (It.Y + Max(It.H, 1)) * FScale);
      if not IR.Contains(PointF(X, Y)) then
        Continue;
      ALine := EnsureRange(It.SrcLine, 0, High(FLines));
      Local := (X - IR.Left) / Max(1, IR.Width) * Max(1, Length(It.Text));
      ACol := It.SrcCol + Trunc(Local);
      ACol := EnsureRange(ACol, 0, Length(FLines[ALine]));
      Exit(True);
    end;
  end;
end;

procedure TDocumentView.RevealLine(ALine: Integer);
var
  I, J: Integer;
  Page: TDocLaidPage;
  It: TDocPaintItem;
  PR: TRectF;
  Y: Single;
begin
  if (FDoc = nil) or not Assigned(FVbar) then
    Exit;
  for I := 0 to FDoc.Pages.Count - 1 do
  begin
    Page := FDoc.Pages[I];
    if (Page = nil) or (Page.Items = nil) then
      Continue;
    for J := 0 to Page.Items.Count - 1 do
    begin
      It := Page.Items[J];
      if (It = nil) or (It.SrcLine <> ALine) then
        Continue;
      PR := PaperRect(I);
      Y := PR.Top + It.Y * FScale;
      if Y < 8 then
        FVbar.Value := EnsureRange(FVbar.Value + Y - 12, 0, FVbar.Max)
      else if Y > ViewH - 24 then
        FVbar.Value := EnsureRange(FVbar.Value + (Y - ViewH + 28), 0, FVbar.Max);
      SyncCustomScroll;
      Exit;
    end;
  end;
end;

procedure TDocumentView.SetCaretDoc(ALine, ACol: Integer; AExtend: Boolean);
begin
  if Length(FLines) = 0 then
    Exit;
  ALine := EnsureRange(ALine, 0, High(FLines));
  ACol := EnsureRange(ACol, 0, Length(FLines[ALine]));
  if not AExtend then
  begin
    FAnchL := ALine;
    FAnchC := ACol;
  end;
  FCaretL := ALine;
  FCaretC := ACol;
  FHasCaret := True;
  RevealLine(ALine);
  if Assigned(FPaint) then
    FPaint.Repaint;
  NotifyStatus;
end;

procedure TDocumentView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  I, L, C: Integer;
  R: TRectF;
  NowTick: UInt64;
  S: string;
  A, B: Integer;
begin
  inherited;
  if CanFocus then
    SetFocus;
  if (X > Width - SB_GAP) or (Y > Height - SB_GAP) then
    Exit;
  if FDoc = nil then
    Exit;
  for I := 0 to FDoc.Pages.Count - 1 do
  begin
    R := PaperRect(I);
    if R.Contains(TPointF.Create(X, Y)) then
    begin
      FActivePage := I;
      Break;
    end;
  end;
  if (Length(FLines) > 0) and HitDoc(X, Y, L, C) then
  begin
    if Button = TMouseButton.mbRight then
    begin
      if not HasTextSelection then
        SetCaretDoc(L, C, False);
      if Assigned(FMenu) then
      begin
        FMenu.ClearItems;
        FMenu.AddItem('Копировать', 'Ctrl+C', MenuCopy);
        FMenu.AddItem('Выделить всё', 'Ctrl+A', MenuAll);
        FMenu.ApplyTheme(FColors);
        FMenu.PopupAtCursor;
      end;
      Exit;
    end;
    if Button = TMouseButton.mbLeft then
    begin
      NowTick := TThread.GetTickCount64;
      if (NowTick - FClickTick < 450) and (L = FCaretL) then
        Inc(FClicks)
      else
        FClicks := 1;
      FClickTick := NowTick;
      if FClicks >= 3 then
      begin
        FClicks := 0;
        FAnchL := L;
        FAnchC := 0;
        FCaretL := L;
        FCaretC := Length(FLines[L]);
        FHasCaret := True;
        if Assigned(FPaint) then
          FPaint.Repaint;
        NotifyStatus;
        Exit;
      end;
      if FClicks = 2 then
      begin
        S := FLines[L];
        A := EnsureRange(C, 0, Max(0, Length(S) - 1));
        B := A;
        if (S <> '') and (((S[A + 1] >= 'A') and (S[A + 1] <= 'Z')) or
           ((S[A + 1] >= 'a') and (S[A + 1] <= 'z')) or
           ((S[A + 1] >= '0') and (S[A + 1] <= '9')) or (S[A + 1] = '_')) then
        begin
          while (A > 0) and (((S[A] >= 'A') and (S[A] <= 'Z')) or
             ((S[A] >= 'a') and (S[A] <= 'z')) or
             ((S[A] >= '0') and (S[A] <= '9')) or (S[A] = '_')) do
            Dec(A);
          if not (((S[A + 1] >= 'A') and (S[A + 1] <= 'Z')) or
             ((S[A + 1] >= 'a') and (S[A + 1] <= 'z')) or
             ((S[A + 1] >= '0') and (S[A + 1] <= '9')) or (S[A + 1] = '_')) then
            Inc(A);
          while (B < Length(S)) and (((S[B + 1] >= 'A') and (S[B + 1] <= 'Z')) or
             ((S[B + 1] >= 'a') and (S[B + 1] <= 'z')) or
             ((S[B + 1] >= '0') and (S[B + 1] <= '9')) or (S[B + 1] = '_')) do
            Inc(B);
          FAnchL := L;
          FAnchC := A;
          FCaretL := L;
          FCaretC := B;
          FHasCaret := True;
          if Assigned(FPaint) then
            FPaint.Repaint;
          NotifyStatus;
          Exit;
        end;
      end;
      FDrag := True;
      SetCaretDoc(L, C, ssShift in Shift);
      if Assigned(Root) then
        Root.Captured := Self;
      Exit;
    end;
  end;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TDocumentView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  L, C: Integer;
begin
  inherited;
  if not FDrag then
    Exit;
  if HitDoc(X, Y, L, C) then
    SetCaretDoc(L, C, True);
end;

procedure TDocumentView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDrag := False;
  if Assigned(Root) and Assigned(Root.Captured) and (Root.Captured.GetObject = Self) then
    Root.Captured := nil;
end;

procedure TDocumentView.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
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

procedure TDocumentView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  Handled: Boolean;
  L, C, Page: Integer;
  Extend: Boolean;
begin
  if Length(FLines) > 0 then
  begin
    Extend := ssShift in Shift;
    L := FCaretL;
    C := FCaretC;
    Page := 12;
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
        if (L <= High(FLines)) and (C < Length(FLines[L])) then
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
        else if L <= High(FLines) then
          C := Length(FLines[L]);
      vkPrior:
        L := Max(0, L - Page);
      vkNext:
        L := Min(High(FLines), L + Page);
      vkA:
        if ssCtrl in Shift then
        begin
          SelectAllText;
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
    if (L >= 0) and (L <= High(FLines)) then
      C := Min(C, Length(FLines[L]));
    SetCaretDoc(L, C, Extend);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  Handled := True;
  case Key of
    vkUp:
      FVbar.Value := EnsureRange(FVbar.Value - 40, 0, FVbar.Max);
    vkDown:
      FVbar.Value := EnsureRange(FVbar.Value + 40, 0, FVbar.Max);
    vkLeft:
      FHbar.Value := EnsureRange(FHbar.Value - 40, 0, FHbar.Max);
    vkRight:
      FHbar.Value := EnsureRange(FHbar.Value + 40, 0, FHbar.Max);
    vkPrior:
      begin
        GoToPage(FActivePage - 1);
        Key := 0;
        KeyChar := #0;
        Exit;
      end;
    vkNext:
      begin
        GoToPage(FActivePage + 1);
        Key := 0;
        KeyChar := #0;
        Exit;
      end;
    vkHome:
      GoToPage(0);
    vkEnd:
      GoToPage(PageCount - 1);
    vkC:
      if ssCtrl in Shift then
        CopyText
      else
        Handled := False;
  else
    Handled := False;
  end;
  if Handled then
  begin
    Key := 0;
    KeyChar := #0;
    SyncCustomScroll;
    if Assigned(FPaint) then
      FPaint.Repaint;
  end
  else
    inherited;
end;

procedure TDocumentView.PaintPages(Sender: TObject; Canvas: TCanvas);
var
  I, J, SelL, SelC1, SelL2, SelC2: Integer;
  Doc: TDocDocument;
  Page: TDocLaidPage;
  PR, IR, Sh: TRectF;
  It: TDocPaintItem;
  State: TCanvasSaveState;
  Fam: string;
  LabelR: TRectF;
begin
  if FPainting or (csDestroying in ComponentState) or not Assigned(FPaint) or
     (FPaint.Width < 2) or (FPaint.Height < 2) or (Canvas = nil) then
    Exit;
  FPainting := True;
  try
  try
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FPaint.LocalRect, 0, 0, [], 1);
  Doc := FDoc;
  if (Doc = nil) or (Doc.Pages = nil) or (Doc.Pages.Count = 0) then
  begin
    Canvas.Fill.Color := FColors.SubTextColor;
    Canvas.Font.Family := 'Segoe UI';
    Canvas.Font.Size := 13;
    Canvas.FillText(FPaint.LocalRect, 'Нет страниц', False, 1, [], TTextAlign.Center, TTextAlign.Center);
    Exit;
  end;

  Canvas.Font.Family := 'Calibri';
  for I := 0 to Doc.Pages.Count - 1 do
  begin
    if FDoc <> Doc then
      Break;
    Page := Doc.Pages[I];
    if (Page = nil) or (Page.Items = nil) then
      Continue;
    PR := PaperRect(I);
    if PR.Bottom < -20 then
      Continue;
    if PR.Top > ViewH + 20 then
      Break;

    Sh := PR;
    Sh.Offset(5, 5);
    Canvas.Fill.Color := $33000000;
    Canvas.FillRect(Sh, 2, 2, AllCorners, 1);

    Canvas.Fill.Color := $FFFFFFFF;
    Canvas.FillRect(PR, 1, 1, AllCorners, 1);
    Canvas.Stroke.Kind := TBrushKind.Solid;
    if I = FActivePage then
      Canvas.Stroke.Color := FColors.SelectionColor
    else
      Canvas.Stroke.Color := $FFD0D0D0;
    Canvas.Stroke.Thickness := IfThen(I = FActivePage, 2, 1);
    Canvas.DrawRect(PR, 1, 1, AllCorners, 1);

    State := Canvas.SaveState;
    try
      Canvas.IntersectClipRect(PR);
      for J := 0 to Page.Items.Count - 1 do
      begin
        It := Page.Items[J];
        if It = nil then
          Continue;
        IR := TRectF.Create(
          PR.Left + It.X * FScale,
          PR.Top + It.Y * FScale,
          PR.Left + (It.X + Max(It.W, 0.5)) * FScale,
          PR.Top + (It.Y + Max(It.H, 0.5)) * FScale);
        case It.Kind of
          dpkFill:
            begin
              Canvas.Fill.Color := It.Fill;
              Canvas.FillRect(IR, 0, 0, [], 1);
            end;
          dpkLine:
            begin
              Canvas.Stroke.Color := It.Stroke;
              if It.Stroke = 0 then
                Canvas.Stroke.Color := $FF333333;
              if It.W + 0.01 < It.H then
              begin
                Canvas.Stroke.Thickness := Max(1, It.W * FScale);
                Canvas.DrawLine(TPointF.Create(IR.Left, IR.Top),
                  TPointF.Create(IR.Left, IR.Bottom), 1);
              end
              else
              begin
                Canvas.Stroke.Thickness := Max(1, Min(It.H, 2) * FScale);
                Canvas.DrawLine(TPointF.Create(IR.Left, IR.Top),
                  TPointF.Create(IR.Right, IR.Top), 1);
              end;
            end;
          dpkImage:
            if Assigned(It.Bitmap) and (It.Bitmap.Width > 0) then
              Canvas.DrawBitmap(It.Bitmap, It.Bitmap.Bounds, IR, 1, True);
          dpkText:
            begin
              Fam := It.Style.FontName;
              if Fam = '' then
                Fam := 'Calibri';
              Canvas.Fill.Kind := TBrushKind.Solid;
              Canvas.Font.Family := Fam;
              Canvas.Font.Size := Max(7, It.Style.SizePt * DocViewFontMul * FScale);
              Canvas.Font.Style := [];
              if It.Style.Bold then
                Canvas.Font.Style := Canvas.Font.Style + [TFontStyle.fsBold];
              if It.Style.Italic then
                Canvas.Font.Style := Canvas.Font.Style + [TFontStyle.fsItalic];
              if It.Style.HasColor then
                Canvas.Fill.Color := It.Style.Color
              else
                Canvas.Fill.Color := $FF222222;
              if IR.Width < Canvas.Font.Size then
                IR.Right := IR.Left + Max(Canvas.Font.Size, Length(It.Text) * Canvas.Font.Size * 0.6);
              if IR.Height < Canvas.Font.Size then
                IR.Bottom := IR.Top + Canvas.Font.Size * 1.35;
              if (It.SrcLine >= 0) and (Length(FLines) > 0) and
                 DocRange(SelL, SelC1, SelL2, SelC2) and
                 (It.SrcLine >= SelL) and (It.SrcLine <= SelL2) and
                 (It.SrcCol < IfThen(It.SrcLine < SelL2, MaxInt, SelC2)) and
                 (It.SrcCol + Length(It.Text) > IfThen(It.SrcLine > SelL, 0, SelC1)) then
              begin
                Canvas.Fill.Color := FColors.SelectionColor;
                Canvas.FillRect(IR, 0, 0, [], 1);
                if It.Style.HasColor then
                  Canvas.Fill.Color := It.Style.Color
                else
                  Canvas.Fill.Color := $FF222222;
              end;
              Canvas.FillText(IR, It.Text, False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
            end;
        end;
      end;
    finally
      Canvas.RestoreState(State);
    end;

    LabelR := TRectF.Create(PR.Left, PR.Bottom + 2, PR.Right, PR.Bottom + 16);
    Canvas.Fill.Color := FColors.SubTextColor;
    Canvas.Font.Family := 'Segoe UI';
    Canvas.Font.Size := 10;
    Canvas.Font.Style := [];
    Canvas.FillText(LabelR, Format('Страница %d из %d', [I + 1, Doc.Pages.Count]),
      False, 1, [], TTextAlign.Center, TTextAlign.Leading);
  end;
  except
  end;
  finally
    FPainting := False;
  end;
end;

end.
