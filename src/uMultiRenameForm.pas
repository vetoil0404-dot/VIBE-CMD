unit uMultiRenameForm;

{
  Fluent-окно группового переименования (аналог Ctrl+M в Total Commander).

  Блоки с явными Position/Size — без Align.Top (FMX кладёт последний
  созданный вверх и из-за этого всё «разъезжается»). Константы сетки
  в начале implementation; LayoutBlocks пересчитывает ширину колонок.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics,
  FMX.StdCtrls,
  {$IFDEF MSWINDOWS}Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,{$ENDIF}
  uAppSettings, uThemeManager, uFluentChrome, uFluentEdit, uFileModel, uMultiRename,
  uCustomScrollbar;

type
  TMultiRenameForm = class(TForm)
  private
    FColors: TThemeColors;
    FEngine: TMultiRenameEngine;
    FRenamed: Integer;
    FEnterTick: UInt64;
    FLastMask: TFluentEdit;

    FRoot: TLayout;

    FBlocks: TLayout;
    FBlkName, FBlkExt, FBlkTok, FBlkCnt, FBlkFind, FBlkPreview: TRectangle;

    FEdName, FEdExt, FEdFind, FEdReplace: TFluentEdit;
    FEdStart, FEdStep, FEdDigits: TFluentEdit;
    FCbCase: TFluentCheckRow;

    FPreviewBox: TVertScrollBox;
    FPreviewPaint: TPaintBox;
    FPreviewScroll: TCustomFileScrollbar;
    FStatus: TText;
    FBtnStart, FBtnClose: TFluentButton;
    FCaseMode: TRenameCaseMode;
    FCaseBtns: array[0..3] of TFluentButton;

    procedure BuildUI;
    function MakeCard(AParent: TFmxObject; const ATitle: string): TRectangle;
    function MakeLabel(AParent: TFmxObject; const ACaption: string;
      AX, AY, AW, AH: Single; ABold: Boolean = False): TText;
    function MakeEdit(AParent: TFmxObject; AX, AY, AW, AH: Single): TFluentEdit;
    function MakeTok(AParent: TFmxObject; const ACaption, AHint: string): TFluentButton;
    function MakeCase(const ACaption, AHint: string; AMode: TRenameCaseMode;
      AWidth: Single): TFluentButton;
    procedure Place(ACtrl: TControl; AX, AY, AW, AH: Single);
    procedure LayoutBlocks;
    procedure BlocksResize(Sender: TObject);
    procedure TokenClick(Sender: TObject);
    procedure CaseClick(Sender: TObject);
    procedure MaskFocus(Sender: TObject);
    procedure ParamChanged(Sender: TObject);
    procedure CollectParams;
    procedure RefreshPreview;
    procedure PreviewPaint(Sender: TObject; Canvas: TCanvas);
    procedure PreviewBoxResize(Sender: TObject);
    procedure PreviewViewportChange(Sender: TObject;
      const OldViewportPosition, NewViewportPosition: TPointF;
      const ContentSizeChanged: Boolean);
    procedure StartClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure EnterApply(Sender: TObject);
    procedure ApplyNativeChrome;
    procedure ThemeTree(AObj: TFmxObject; const AColors: TThemeColors);
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent; const AEntries: TArray<TFileEntry>;
      const AColors: TThemeColors); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme(const AColors: TThemeColors);
    property RenamedCount: Integer read FRenamed;
  end;

implementation

uses
  uLang, uLangBind;

const
  { --- сетка: правьте эти числа --- }
  GAP        = 10;
  INSET      = 12;
  NAME_H     = 80;
  TOK_H      = 86;
  CNT_H      = 136;
  TOK_W      = 48;
  TOK_GAP    = 6;
  ROW_H      = 26;
  LAB_W      = 86;
  CNT_EDIT_W = 88;
  EDIT_H     = 28;

constructor TMultiRenameForm.Create(AOwner: TComponent;
  const AEntries: TArray<TFileEntry>; const AColors: TThemeColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  FEngine := TMultiRenameEngine.Create;
  FEngine.LoadEntries(AEntries);
  FRenamed := 0;
  Width := 920;
  Height := 700;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  TrForm(Self, 'rename.title');
  ShowHint := True;
  Position := TFormPosition.OwnerFormCenter;
  BuildUI;
  ApplyTheme(FColors);
  RefreshPreview;
  ApplyNativeChrome;
end;

destructor TMultiRenameForm.Destroy;
begin
  FreeAndNil(FPreviewScroll);
  FreeAndNil(FEngine);
  inherited;
end;

procedure TMultiRenameForm.ApplyNativeChrome;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  Corner: Integer;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    Corner := 2;
    DwmSetWindowAttribute(Wnd, 33, @Corner, SizeOf(Corner));
  end;
  {$ENDIF}
end;

procedure TMultiRenameForm.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TMultiRenameForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
  LayoutBlocks;
end;

procedure TMultiRenameForm.Place(ACtrl: TControl; AX, AY, AW, AH: Single);
begin
  if ACtrl = nil then
    Exit;
  ACtrl.Align := TAlignLayout.None;
  ACtrl.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  ACtrl.Position.X := AX;
  ACtrl.Position.Y := AY;
  ACtrl.Width := AW;
  ACtrl.Height := AH;
end;

function TMultiRenameForm.MakeCard(AParent: TFmxObject; const ATitle: string): TRectangle;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.None;
  Result.XRadius := 10;
  Result.YRadius := 10;
  Result.Stroke.Kind := TBrushKind.Solid;
  Result.Stroke.Thickness := 1;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.Tag := 1;
  if ATitle <> '' then
    TrText(MakeLabel(Result, ATitle, INSET, 8, 400, 20, True), ATitle);
end;

function TMultiRenameForm.MakeLabel(AParent: TFmxObject; const ACaption: string;
  AX, AY, AW, AH: Single; ABold: Boolean): TText;
begin
  Result := TText.Create(Self);
  Result.Parent := AParent;
  Result.HitTest := False;
  Result.Text := ACaption;
  if ABold then
    Result.Tag := 9
  else
    Result.Tag := 8;
  ApplyFluentText(Result, 12, ABold);
  Result.TextSettings.HorzAlign := TTextAlign.Leading;
  Result.TextSettings.VertAlign := TTextAlign.Center;
  Place(Result, AX, AY, AW, AH);
end;

function TMultiRenameForm.MakeEdit(AParent: TFmxObject; AX, AY, AW, AH: Single): TFluentEdit;
begin
  Result := CreateFluentEdit(Self, AParent);
  Result.FillMode := fefSubtle;
  Result.OnEnter := MaskFocus;
  Place(Result, AX, AY, AW, AH);
end;

function TMultiRenameForm.MakeTok(AParent: TFmxObject; const ACaption, AHint: string): TFluentButton;
var
  BW: Single;
begin
  BW := Max(TOK_W, Length(ACaption) * 8 + 18);
  Result := CreateFluentButton(Self, AParent, '', ACaption, fbkSubtle, BW, TokenClick);
  Result.TagString := ACaption;
  TrHint(Result, AHint);
  Place(Result, 0, 0, BW, 30);
end;

function TMultiRenameForm.MakeCase(const ACaption, AHint: string;
  AMode: TRenameCaseMode; AWidth: Single): TFluentButton;
var
  I, J: Integer;
  Obj, Inner: TFmxObject;
begin
  Result := CreateFluentButton(Self, FBlkTok, '', ACaption, fbkSubtle, AWidth, CaseClick);
  Result.Tag := Ord(AMode);
  TrHint(Result, AHint);
  for I := 0 to Result.ChildrenCount - 1 do
  begin
    Obj := Result.Children[I];
    if Obj is TText then
      TText(Obj).TextSettings.HorzAlign := TTextAlign.Center
    else
      for J := 0 to Obj.ChildrenCount - 1 do
      begin
        Inner := Obj.Children[J];
        if Inner is TText then
          TText(Inner).TextSettings.HorzAlign := TTextAlign.Center;
      end;
  end;
  Place(Result, 0, 0, AWidth, 30);
end;

procedure TMultiRenameForm.LayoutBlocks;
var
  W, Col, X2, YTok, YBot, EW, TX, TY: Single;
  I: Integer;
  Ch: TFmxObject;
  C: TControl;
  CaseRow: Boolean;
begin
  if FBlocks = nil then
    Exit;
  W := FBlocks.Width;
  if W < 80 then
    W := 860;
  Col := (W - GAP) * 0.5;
  X2 := Col + GAP;
  YTok := NAME_H + GAP;
  YBot := YTok + TOK_H + GAP;

  Place(FBlkName, 0, 0, Col, NAME_H);
  Place(FBlkExt, X2, 0, Col, NAME_H);
  Place(FBlkTok, 0, YTok, W, TOK_H);
  Place(FBlkCnt, 0, YBot, Col, CNT_H);
  Place(FBlkFind, X2, YBot, Col, CNT_H);

  EW := Max(60, Col - INSET * 2);
  Place(FEdName, INSET, 34, EW, EDIT_H);
  Place(FEdExt, INSET, 34, EW, EDIT_H);

  if Assigned(FBlkTok) then
  begin
    TX := INSET;
    TY := 10;
    CaseRow := False;
    for I := 0 to FBlkTok.ChildrenCount - 1 do
    begin
      Ch := FBlkTok.Children[I];
      if Ch is TFluentButton then
      begin
        C := TControl(Ch);
        { Кнопки регистра (Tag <> 0) всегда с новой строки, одним рядом. }
        if (C.Tag <> 0) and not CaseRow then
        begin
          if TX > INSET then
          begin
            TX := INSET;
            TY := TY + 30 + TOK_GAP;
          end;
          CaseRow := True;
        end;
        if (TX > INSET) and (TX + C.Width > W - INSET) then
        begin
          TX := INSET;
          TY := TY + 30 + TOK_GAP;
        end;
        Place(C, TX, TY, C.Width, 30);
        TX := TX + C.Width + TOK_GAP;
      end;
    end;
  end;

  Place(FEdStart, INSET + LAB_W, 34, CNT_EDIT_W, EDIT_H);
  Place(FEdStep, INSET + LAB_W, 68, CNT_EDIT_W, EDIT_H);
  Place(FEdDigits, INSET + LAB_W, 102, CNT_EDIT_W, EDIT_H);

  EW := Max(60, Col - INSET * 2 - LAB_W);
  Place(FEdFind, INSET + LAB_W, 34, EW, EDIT_H);
  Place(FEdReplace, INSET + LAB_W, 68, EW, EDIT_H);
  if Assigned(FCbCase) then
    Place(FCbCase, INSET, 100, 240, 28);
end;

procedure TMultiRenameForm.BlocksResize(Sender: TObject);
begin
  LayoutBlocks;
end;

procedure TMultiRenameForm.BuildUI;
var
  Footer: TLayout;
begin
  FRoot := TLayout.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Padding.Rect := TRectF.Create(18, 14, 18, 14);

  { низ: Выполнить / Закрыть справа }
  Footer := TLayout.Create(Self);
  Footer.Parent := FRoot;
  Footer.Align := TAlignLayout.Bottom;
  Footer.Height := 42;
  Footer.Margins.Top := 10;
  FBtnClose := CreateFluentButton(Self, Footer, '', L('rename.close'), fbkStandard, 110, CloseClick);
  TrButton(FBtnClose, 'rename.close');
  FBtnClose.Align := TAlignLayout.Right;
  FBtnStart := CreateFluentButton(Self, Footer, '', L('rename.go'), fbkAccent, 148, StartClick);
  TrButton(FBtnStart, 'rename.go');
  FBtnStart.Align := TAlignLayout.Right;
  FBtnStart.Margins.Right := 8;
  FStatus := TText.Create(Self);
  FStatus.Parent := Footer;
  FStatus.Align := TAlignLayout.Client;
  FStatus.HitTest := False;
  ApplyFluentText(FStatus, 12, False);
  FStatus.TextSettings.HorzAlign := TTextAlign.Leading;
  FStatus.TextSettings.VertAlign := TTextAlign.Center;

  { превью занимает оставшееся место }
  FBlkPreview := TRectangle.Create(Self);
  FBlkPreview.Parent := FRoot;
  FBlkPreview.Align := TAlignLayout.Client;
  FBlkPreview.XRadius := 10;
  FBlkPreview.YRadius := 10;
  FBlkPreview.Stroke.Kind := TBrushKind.Solid;
  FBlkPreview.Fill.Kind := TBrushKind.Solid;
  FBlkPreview.Padding.Rect := TRectF.Create(8, 6, 8, 8);
  FBlkPreview.Margins.Top := 4;
  FBlkPreview.Tag := 1;
  FPreviewBox := TVertScrollBox.Create(Self);
  FPreviewBox.Parent := FBlkPreview;
  FPreviewBox.Align := TAlignLayout.Client;
  FPreviewBox.ShowScrollBars := False;
  FPreviewBox.AniCalculations.AutoShowing := False;
  FPreviewBox.OnResize := PreviewBoxResize;
  FPreviewBox.OnViewportPositionChange := PreviewViewportChange;
  FPreviewScroll := TCustomFileScrollbar.Create(FBlkPreview, FPreviewBox);
  FPreviewPaint := TPaintBox.Create(Self);
  FPreviewPaint.Parent := FPreviewBox;
  FPreviewPaint.Align := TAlignLayout.Top;
  FPreviewPaint.Height := 80;
  FPreviewPaint.OnPaint := PreviewPaint;

  { верхние блоки — абсолютная сетка }
  FBlocks := TLayout.Create(Self);
  FBlocks.Parent := FRoot;
  FBlocks.Align := TAlignLayout.Top;
  FBlocks.Height := NAME_H + GAP + TOK_H + GAP + CNT_H;
  FBlocks.Margins.Bottom := GAP;
  FBlocks.OnResize := BlocksResize;

  FBlkName := MakeCard(FBlocks, 'rename.mask');
  FEdName := MakeEdit(FBlkName, INSET, 34, 200, EDIT_H);
  FEdName.Text := '[N]';
  FLastMask := FEdName;

  FBlkExt := MakeCard(FBlocks, 'rename.ext');
  FEdExt := MakeEdit(FBlkExt, INSET, 34, 200, EDIT_H);
  FEdExt.Text := '[E]';

  FBlkTok := MakeCard(FBlocks, '');
  MakeTok(FBlkTok, '[N]', 'rename.tok.n');
  MakeTok(FBlkTok, '[E]', 'rename.tok.e');
  MakeTok(FBlkTok, '[C]', 'rename.tok.c');
  MakeTok(FBlkTok, '[P]', 'rename.tok.p');
  MakeTok(FBlkTok, '[Y]', 'rename.tok.Y');
  MakeTok(FBlkTok, '[y]', 'rename.tok.y');
  MakeTok(FBlkTok, '[M]', 'rename.tok.M');
  MakeTok(FBlkTok, '[D]', 'rename.tok.D');
  MakeTok(FBlkTok, '[h]', 'rename.tok.h');
  MakeTok(FBlkTok, '[m]', 'rename.tok.m');
  MakeTok(FBlkTok, '[s]', 'rename.tok.s');
  MakeTok(FBlkTok, '[N-2]', 'rename.tok.nhead');
  MakeTok(FBlkTok, '[N2-]', 'rename.tok.ntail');
  MakeTok(FBlkTok, '[N1-4]', 'rename.tok.nrange');
  FCaseBtns[0] := MakeCase('АА', 'rename.case.upper', rcUpper, 52);
  FCaseBtns[1] := MakeCase('аа', 'rename.case.lower', rcLower, 52);
  FCaseBtns[2] := MakeCase('Аа', 'rename.case.first', rcFirstUpper, 52);
  FCaseBtns[3] := MakeCase('Аа Аа', 'rename.case.words', rcWords, 84);

  FBlkCnt := MakeCard(FBlocks, 'rename.counter');
  TrText(MakeLabel(FBlkCnt, 'rename.start', INSET, 34, LAB_W, EDIT_H), 'rename.start');
  FEdStart := MakeEdit(FBlkCnt, INSET + LAB_W, 34, CNT_EDIT_W, EDIT_H);
  FEdStart.Text := '1';
  TrText(MakeLabel(FBlkCnt, 'rename.step', INSET, 68, LAB_W, EDIT_H), 'rename.step');
  FEdStep := MakeEdit(FBlkCnt, INSET + LAB_W, 68, CNT_EDIT_W, EDIT_H);
  FEdStep.Text := '1';
  TrText(MakeLabel(FBlkCnt, 'rename.digits', INSET, 102, LAB_W, EDIT_H), 'rename.digits');
  FEdDigits := MakeEdit(FBlkCnt, INSET + LAB_W, 102, CNT_EDIT_W, EDIT_H);
  FEdDigits.Text := '3';

  FBlkFind := MakeCard(FBlocks, 'rename.find');
  TrText(MakeLabel(FBlkFind, 'rename.search', INSET, 34, LAB_W, EDIT_H), 'rename.search');
  FEdFind := MakeEdit(FBlkFind, INSET + LAB_W, 34, 200, EDIT_H);
  TrText(MakeLabel(FBlkFind, 'rename.replace', INSET, 68, LAB_W, EDIT_H), 'rename.replace');
  FEdReplace := MakeEdit(FBlkFind, INSET + LAB_W, 68, 200, EDIT_H);
  FCbCase := TFluentCheckRow.Create(Self);
  FCbCase.Setup(FBlkFind, L('rename.casesens'), False);
  TrCheck(FCbCase, 'rename.casesens');
  FCbCase.OnChange := ParamChanged;
  Place(FCbCase, INSET, 100, 240, 28);

  FEdName.OnChange := ParamChanged;
  FEdExt.OnChange := ParamChanged;
  FEdFind.OnChange := ParamChanged;
  FEdReplace.OnChange := ParamChanged;
  FEdStart.OnChange := ParamChanged;
  FEdStep.OnChange := ParamChanged;
  FEdDigits.OnChange := ParamChanged;
  FEdName.OnSubmit := EnterApply;
  FEdExt.OnSubmit := EnterApply;
  FEdFind.OnSubmit := EnterApply;
  FEdReplace.OnSubmit := EnterApply;
  FEdStart.OnSubmit := EnterApply;
  FEdStep.OnSubmit := EnterApply;
  FEdDigits.OnSubmit := EnterApply;
  LayoutBlocks;
end;

procedure TMultiRenameForm.MaskFocus(Sender: TObject);
begin
  if Sender is TFluentEdit then
    if (Sender = FEdName) or (Sender = FEdExt) then
      FLastMask := TFluentEdit(Sender);
end;

procedure TMultiRenameForm.TokenClick(Sender: TObject);
begin
  if FLastMask = nil then
    FLastMask := FEdName;
  if Sender is TFluentButton then
    FLastMask.InsertSnippet(TFluentButton(Sender).TagString);
end;

procedure TMultiRenameForm.CaseClick(Sender: TObject);
var
  Mode: TRenameCaseMode;
  I: Integer;
begin
  if not (Sender is TFluentButton) then
    Exit;
  Mode := TRenameCaseMode(TFluentButton(Sender).Tag);
  if Mode = FCaseMode then
    Mode := rcKeep;
  FCaseMode := Mode;
  for I := 0 to High(FCaseBtns) do
    if FCaseBtns[I] <> nil then
      FCaseBtns[I].SetSelected(TRenameCaseMode(FCaseBtns[I].Tag) = FCaseMode);
  RefreshPreview;
end;

procedure TMultiRenameForm.CollectParams;
begin
  if (FEngine = nil) or (FEdName = nil) or (FEdExt = nil) then
    Exit;
  FEngine.NameMask := FEdName.Text;
  FEngine.ExtMask := FEdExt.Text;
  FEngine.FindText := FEdFind.Text;
  FEngine.ReplaceText := FEdReplace.Text;
  FEngine.CaseSensitive := Assigned(FCbCase) and FCbCase.Checked;
  FEngine.CaseMode := FCaseMode;
  FEngine.UseRegex := False;
  FEngine.CounterStart := StrToIntDef(Trim(FEdStart.Text), 1);
  FEngine.CounterStep := StrToIntDef(Trim(FEdStep.Text), 1);
  FEngine.CounterDigits := EnsureRange(StrToIntDef(Trim(FEdDigits.Text), 3), 1, 12);
end;

procedure TMultiRenameForm.ParamChanged(Sender: TObject);
begin
  RefreshPreview;
end;

procedure TMultiRenameForm.RefreshPreview;
var
  N, C: Integer;
begin
  if (FEngine = nil) or (FEdName = nil) or (FPreviewPaint = nil) or (FStatus = nil) then
    Exit;
  CollectParams;
  FEngine.RebuildPreview;
  N := Length(FEngine.Items);
  C := FEngine.CollisionCount;
  FPreviewPaint.Height := Max(80, (N + 1) * ROW_H + 8);
  if Assigned(FPreviewScroll) then
    FPreviewScroll.UpdateThumb;
  if C > 0 then
    FStatus.Text := Lf('rename.filescoll', [N, C])
  else
    FStatus.Text := Lf('rename.files', [N]);
  FPreviewPaint.Repaint;
end;

procedure TMultiRenameForm.PreviewBoxResize(Sender: TObject);
begin
  if Assigned(FPreviewScroll) then
    FPreviewScroll.UpdateThumb;
end;

procedure TMultiRenameForm.PreviewViewportChange(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF;
  const ContentSizeChanged: Boolean);
begin
  if Assigned(FPreviewScroll) then
    FPreviewScroll.UpdateThumb;
end;

procedure TMultiRenameForm.PreviewPaint(Sender: TObject; Canvas: TCanvas);
var
  I: Integer;
  Y, W, Mid: Single;
  ROld, RNew, Head: TRectF;
  Items: TArray<TRenameItem>;
  NewCaption: string;
begin
  if (Canvas = nil) or (FEngine = nil) then
    Exit;
  Items := FEngine.Items;
  W := FPreviewPaint.Width;
  Mid := W * 0.5;
  Canvas.BeginScene;
  try
    Canvas.Fill.Color := FColors.PanelBackground;
    Canvas.FillRect(TRectF.Create(0, 0, W, FPreviewPaint.Height), 0, 0, [], 1);
    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := 12;
    Head := TRectF.Create(8, 0, Mid - 6, ROW_H);
    Canvas.Fill.Color := FColors.SubTextColor;
    Canvas.FillText(Head, L('rename.oldname'), False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Head := TRectF.Create(Mid + 6, 0, W - 8, ROW_H);
    Canvas.FillText(Head, L('rename.newname'), False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Canvas.Stroke.Color := FColors.DividerColor;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(TPointF.Create(Mid, 4), TPointF.Create(Mid, FPreviewPaint.Height - 4), 1);
    for I := 0 to High(Items) do
    begin
      Y := (I + 1) * ROW_H;
      ROld := TRectF.Create(8, Y, Mid - 6, Y + ROW_H);
      RNew := TRectF.Create(Mid + 6, Y, W - 8, Y + ROW_H);
      NewCaption := Items[I].NewName;
      if Items[I].Collision then
      begin
        Canvas.Fill.Color := ThemeAdjustAlpha(FColors.DangerColor, $40);
        Canvas.FillRect(TRectF.Create(0, Y, W, Y + ROW_H), 0, 0, [], 1);
        Canvas.Fill.Color := FColors.DangerColor;
        NewCaption := NewCaption + '    ⚠  ' + L('rename.collision');
      end
      else if Odd(I) then
      begin
        Canvas.Fill.Color := FColors.ItemAltBackground;
        Canvas.FillRect(TRectF.Create(0, Y, W, Y + ROW_H), 0, 0, [], 1);
        Canvas.Fill.Color := FColors.TextColor;
      end
      else
        Canvas.Fill.Color := FColors.TextColor;
      Canvas.FillText(ROld, Items[I].OldName, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
      Canvas.FillText(RNew, NewCaption, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    end;
  finally
    Canvas.EndScene;
  end;
end;

procedure TMultiRenameForm.EnterApply(Sender: TObject);
begin
  if (FRenamed > 0) or (GetTickCount64 - FEnterTick < 250) then
    Exit;
  FEnterTick := GetTickCount64;
  StartClick(Sender);
end;

procedure TMultiRenameForm.KeyDown(var Key: Word; var KeyChar: Char;
  Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    EnterApply(nil);
    Exit;
  end;
  inherited;
end;

procedure TMultiRenameForm.StartClick(Sender: TObject);
var
  N: Integer;
begin
  CollectParams;
  N := FEngine.ApplyRenames;
  FRenamed := N;
  RefreshPreview;
  if N > 0 then
    ModalResult := mrOk
  else
    FStatus.Text := L('rename.nothing');
end;

procedure TMultiRenameForm.CloseClick(Sender: TObject);
begin
  if FRenamed > 0 then
    ModalResult := mrOk
  else
    ModalResult := mrCancel;
end;

procedure TMultiRenameForm.ThemeTree(AObj: TFmxObject; const AColors: TThemeColors);
var
  I: Integer;
  Ch: TFmxObject;
begin
  if AObj = nil then
    Exit;
  if AObj is TFluentButton then
    TFluentButton(AObj).ApplyTheme(AColors)
  else if AObj is TFluentEdit then
    TFluentEdit(AObj).ApplyTheme(AColors)
  else if AObj is TFluentCheckRow then
    TFluentCheckRow(AObj).ApplyTheme(AColors)
  else if (AObj is TRectangle) and (TRectangle(AObj).Tag = 1) then
  begin
    TRectangle(AObj).Fill.Color := AColors.CardBackground;
    TRectangle(AObj).Stroke.Color := AColors.CardStroke;
  end
  else if AObj is TText then
  begin
    if TText(AObj).Tag = 8 then
      TText(AObj).TextSettings.FontColor := AColors.SubTextColor
    else if TText(AObj).Tag = 9 then
      TText(AObj).TextSettings.FontColor := AColors.TextColor;
  end;
  for I := 0 to AObj.ChildrenCount - 1 do
  begin
    Ch := AObj.Children[I];
    ThemeTree(Ch, AColors);
  end;
end;

procedure TMultiRenameForm.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  if Assigned(FStatus) then
    FStatus.TextSettings.FontColor := AColors.SubTextColor;
  ApplyNativeChrome;
  ThemeTree(FRoot, AColors);
  if Assigned(FPreviewScroll) then
    FPreviewScroll.ApplyTheme(AColors);
  if Assigned(FPreviewPaint) then
    FPreviewPaint.Repaint;
end;

end.
