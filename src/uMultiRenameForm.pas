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

    procedure BuildUI;
    function MakeCard(AParent: TFmxObject; const ATitle: string): TRectangle;
    function MakeLabel(AParent: TFmxObject; const ACaption: string;
      AX, AY, AW, AH: Single; ABold: Boolean = False): TText;
    function MakeEdit(AParent: TFmxObject; AX, AY, AW, AH: Single): TFluentEdit;
    function MakeTok(AParent: TFmxObject; const ACaption, AHint: string): TFluentButton;
    procedure Place(ACtrl: TControl; AX, AY, AW, AH: Single);
    procedure LayoutBlocks;
    procedure BlocksResize(Sender: TObject);
    procedure TokenClick(Sender: TObject);
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
  Caption := 'Пакетное переименование файлов';
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
    MakeLabel(Result, ATitle, INSET, 8, 400, 20, True);
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
  Result.Hint := AHint;
  Result.ShowHint := True;
  Place(Result, 0, 0, BW, 30);
end;

procedure TMultiRenameForm.LayoutBlocks;
var
  W, Col, X2, YTok, YBot, EW, TX, TY: Single;
  I: Integer;
  Ch: TFmxObject;
  C: TControl;
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
    for I := 0 to FBlkTok.ChildrenCount - 1 do
    begin
      Ch := FBlkTok.Children[I];
      if Ch is TFluentButton then
      begin
        C := TControl(Ch);
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
  FBtnClose := CreateFluentButton(Self, Footer, '', 'Закрыть', fbkStandard, 110, CloseClick);
  FBtnClose.Align := TAlignLayout.Right;
  FBtnStart := CreateFluentButton(Self, Footer, '', 'Выполнить', fbkAccent, 148, StartClick);
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

  FBlkName := MakeCard(FBlocks, 'Маска имени файла');
  FEdName := MakeEdit(FBlkName, INSET, 34, 200, EDIT_H);
  FEdName.Text := '[N]';
  FLastMask := FEdName;

  FBlkExt := MakeCard(FBlocks, 'Расширение');
  FEdExt := MakeEdit(FBlkExt, INSET, 34, 200, EDIT_H);
  FEdExt.Text := '[E]';

  FBlkTok := MakeCard(FBlocks, '');
  MakeTok(FBlkTok, '[N]', 'Имя файла без расширения');
  MakeTok(FBlkTok, '[E]', 'Расширение файла');
  MakeTok(FBlkTok, '[C]', 'Счётчик (старт / шаг / знаки)');
  MakeTok(FBlkTok, '[P]', 'Имя родительской папки');
  MakeTok(FBlkTok, '[Y]', 'Год, 4 цифры (2026)');
  MakeTok(FBlkTok, '[y]', 'Год, 2 цифры (26)');
  MakeTok(FBlkTok, '[M]', 'Месяц (01–12)');
  MakeTok(FBlkTok, '[D]', 'День (01–31)');
  MakeTok(FBlkTok, '[h]', 'Час (00–23)');
  MakeTok(FBlkTok, '[m]', 'Минута');
  MakeTok(FBlkTok, '[s]', 'Секунда');
  MakeTok(FBlkTok, '[N-2]', 'Первые два символа имени');
  MakeTok(FBlkTok, '[N2-]', 'Имя со второго символа');
  MakeTok(FBlkTok, '[N1-4]', 'Символы 1–4 имени');
  MakeTok(FBlkTok, '[Nlower]', 'Имя в нижнем регистре');
  MakeTok(FBlkTok, '[Nupper]', 'Имя в ВЕРХНЕМ регистре');
  MakeTok(FBlkTok, '[Nfirstupper]', 'Имя с заглавной первой буквы');
  MakeTok(FBlkTok, '[Elower]', 'Расширение в нижнем регистре');
  MakeTok(FBlkTok, '[Eupper]', 'Расширение в ВЕРХНЕМ регистре');

  FBlkCnt := MakeCard(FBlocks, 'Счётчик [C]');
  MakeLabel(FBlkCnt, 'Старт:', INSET, 34, LAB_W, EDIT_H);
  FEdStart := MakeEdit(FBlkCnt, INSET + LAB_W, 34, CNT_EDIT_W, EDIT_H);
  FEdStart.Text := '1';
  MakeLabel(FBlkCnt, 'Шаг:', INSET, 68, LAB_W, EDIT_H);
  FEdStep := MakeEdit(FBlkCnt, INSET + LAB_W, 68, CNT_EDIT_W, EDIT_H);
  FEdStep.Text := '1';
  MakeLabel(FBlkCnt, 'Знаков:', INSET, 102, LAB_W, EDIT_H);
  FEdDigits := MakeEdit(FBlkCnt, INSET + LAB_W, 102, CNT_EDIT_W, EDIT_H);
  FEdDigits.Text := '3';

  FBlkFind := MakeCard(FBlocks, 'Найти и заменить');
  MakeLabel(FBlkFind, 'Искать:', INSET, 34, LAB_W, EDIT_H);
  FEdFind := MakeEdit(FBlkFind, INSET + LAB_W, 34, 200, EDIT_H);
  MakeLabel(FBlkFind, 'Заменить:', INSET, 68, LAB_W, EDIT_H);
  FEdReplace := MakeEdit(FBlkFind, INSET + LAB_W, 68, 200, EDIT_H);
  FCbCase := TFluentCheckRow.Create(Self);
  FCbCase.Setup(FBlkFind, 'С учетом регистра', False);
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

procedure TMultiRenameForm.CollectParams;
begin
  if (FEngine = nil) or (FEdName = nil) or (FEdExt = nil) then
    Exit;
  FEngine.NameMask := FEdName.Text;
  FEngine.ExtMask := FEdExt.Text;
  FEngine.FindText := FEdFind.Text;
  FEngine.ReplaceText := FEdReplace.Text;
  FEngine.CaseSensitive := Assigned(FCbCase) and FCbCase.Checked;
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
    FStatus.Text := Format('Файлов: %d    Коллизий: %d', [N, C])
  else
    FStatus.Text := Format('Файлов: %d', [N]);
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
    Canvas.FillText(Head, 'Исходное имя', False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Head := TRectF.Create(Mid + 6, 0, W - 8, ROW_H);
    Canvas.FillText(Head, 'Новое имя', False, 1, [], TTextAlign.Leading, TTextAlign.Center);
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
        NewCaption := NewCaption + '    ⚠  Коллизия';
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
    FStatus.Text := 'Нечего переименовывать (коллизии или имена не изменились)';
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
