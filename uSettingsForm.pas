unit uSettingsForm;

{
  Fluent Settings: master-detail (категории слева, страница справа).
  Свои чекбоксы и карточки — без системных TEdit/TCheckBox.
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Types, System.Math,
  FMX.Graphics, FMX.Forms, FMX.Layouts, FMX.StdCtrls, FMX.Objects, FMX.Types,
  {$IFDEF MSWINDOWS}Winapi.Windows, FMX.Platform.Win,{$ENDIF}
  uAppSettings, uThemeManager, uFluentChrome, uFluentEdit, uThumbCache;

type
  TThemeChangedProc = reference to procedure(NewTheme: TAppTheme);

  TSettingsForm = class(TForm)
  private
    FSettings: TAppSettings;
    FSaveTimer: TTimer;
    FOnThemeChanged: TThemeChangedProc;
    FOnOptionsChanged: TProc;
    FColors: TThemeColors;
    FPage: Integer;

    FRoot: TLayout;
    FBody: TLayout;
    FNav: TRectangle;
    FNavStack: TLayout;
    FNavBtns: array[0..2] of TFluentButton;
    FContent: TRectangle;
    FPages: array[0..2] of TVertScrollBox;
    FFooter: TLayout;
    FBtnClose: TFluentButton;

    FCardSystem, FCardLight, FCardDark: TRectangle;
    FCardMatNormal, FCardMatAcrylic, FCardMatMica: TRectangle;
    FCbDock, FCbMid, FCbDrives, FCbStatus, FCbFn, FCbQuick, FCbCmd: TFluentCheckRow;
    FCbHidden, FCbNetwork: TFluentCheckRow;
    FCbOpQuiet, FCbOpExplorer, FCbOpVibe: TFluentCheckRow;
    FCbTabIcons, FCbEqualTabs: TFluentCheckRow;
    FCbDockLeft, FCbDockCenter, FCbDockFree, FCbDockSeps: TFluentCheckRow;
    FCbThumbs: TFluentCheckRow;
    FThumbLimitEdit: TFluentEdit;
    FThumbInfo: TText;
    FBtnClearCache: TFluentButton;
    FFontSizeEdit: TFluentEdit;

    procedure BuildUI;
    procedure BuildNav;
    procedure BuildPages;
    function AddPage: TVertScrollBox;
    function AddCard(AParent: TFmxObject; const ATitle: string): TRectangle;
    function AddCheck(AParent: TFmxObject; const ACaption: string;
      AChecked: Boolean; AOnChange: TNotifyEvent): TFluentCheckRow;
    procedure BuildThemeCard(var ACard: TRectangle; AParent: TFmxObject;
      const ATitle: string; ATheme: TAppTheme);
    procedure BuildMaterialCard(var ACard: TRectangle; AParent: TFmxObject;
      const ATitle: string; AMaterial: TWindowMaterial; APreview: TAlphaColor);
    procedure NavClick(Sender: TObject);
    procedure ShowPage(AIndex: Integer);
    procedure ThemeCardClick(Sender: TObject);
    procedure MaterialCardClick(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
    procedure DockAlignClick(Sender: TObject);
    procedure FileOpModeClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure SaveTimerTick(Sender: TObject);
    procedure ScheduleSave;
    procedure ClearCacheClick(Sender: TObject);
    procedure CollectFromUI;
    procedure UpdateThemeCards;
    procedure UpdateMaterialCards;
    procedure UpdateThumbInfo;
    function ThemeOfCard(ACard: TRectangle): TAppTheme;
    procedure ApplyNativeChrome;
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent; ASettings: TAppSettings;
      AOnThemeChanged: TThemeChangedProc); reintroduce;
    procedure ApplyTheme(const AColors: TThemeColors);
    property OnOptionsChanged: TProc read FOnOptionsChanged write FOnOptionsChanged;
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
  Caption := 'Настройки';
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

function TSettingsForm.AddCard(AParent: TFmxObject; const ATitle: string): TRectangle;
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
  Cap.Text := ATitle;
  Cap.HitTest := False;
  Cap.Tag := 7;
  ApplyFluentText(Cap, 13, True);
  Cap.TextSettings.HorzAlign := TTextAlign.Leading;
end;

function TSettingsForm.AddCheck(AParent: TFmxObject; const ACaption: string;
  AChecked: Boolean; AOnChange: TNotifyEvent): TFluentCheckRow;
begin
  Result := TFluentCheckRow.Create(Self);
  Result.Setup(AParent, ACaption, AChecked);
  Result.OnChange := AOnChange;
  Result.ApplyTheme(FColors);
end;

procedure TSettingsForm.BuildThemeCard(var ACard: TRectangle; AParent: TFmxObject;
  const ATitle: string; ATheme: TAppTheme);
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
  Lbl.Text := ATitle;
  Lbl.HitTest := False;
  ApplyFluentText(Lbl, 13, False);
  Lbl.TextSettings.HorzAlign := TTextAlign.Center;
  Lbl.TextSettings.VertAlign := TTextAlign.Center;
end;

procedure TSettingsForm.BuildMaterialCard(var ACard: TRectangle; AParent: TFmxObject;
  const ATitle: string; AMaterial: TWindowMaterial; APreview: TAlphaColor);
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
  Lbl.Text := ATitle;
  Lbl.HitTest := False;
  ApplyFluentText(Lbl, 13, False);
  Lbl.TextSettings.HorzAlign := TTextAlign.Center;
  Lbl.TextSettings.VertAlign := TTextAlign.Center;
end;

procedure TSettingsForm.BuildNav;
const
  Caps: array[0..2] of string = ('Основные', 'Вид и темы', 'Кэш');
  Icons: array[0..2] of string = ('', '', '');
var
  I: Integer;
begin
  FNav := TRectangle.Create(Self);
  FNav.Parent := FBody;
  FNav.Align := TAlignLayout.Left;
  FNav.Width := 208;
  FNav.XRadius := 10;
  FNav.YRadius := 10;
  FNav.Stroke.Kind := TBrushKind.Solid;
  FNav.Fill.Kind := TBrushKind.Solid;
  FNav.Margins.Rect := TRectF.Create(0, 0, 12, 0);
  FNav.Padding.Rect := TRectF.Create(8, 10, 8, 10);

  FNavStack := TLayout.Create(Self);
  FNavStack.Parent := FNav;
  FNavStack.Align := TAlignLayout.Top;
  FNavStack.Height := 3 * 44;

  for I := 0 to 2 do
  begin
    FNavBtns[I] := CreateFluentButton(Self, FNavStack, Icons[I], Caps[I],
      fbkSubtle, 188, NavClick);
    FNavBtns[I].Align := TAlignLayout.Top;
    FNavBtns[I].Height := 40;
    FNavBtns[I].Tag := I;
    FNavBtns[I].Margins.Rect := TRectF.Create(0, 0, 0, 4);
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

  { --- Основные --- }
  Card := AddCard(FPages[0], 'Элементы интерфейса');
  Card.Height := 22 + 7 * 36 + 16;

    // для правильго отображения список должен быть  в обратном порядке
    FCbCmd := AddCheck(Card, 'Командная строка', FSettings.ShowCommandLine, OptionChanged);
    FCbFn := AddCheck(Card, 'Панель функциональных клавиш', FSettings.ShowFnBar, OptionChanged);
    FCbQuick := AddCheck(Card, 'Кнопки быстрого доступа', FSettings.ShowQuickAccess, OptionChanged);
    FCbStatus := AddCheck(Card, 'Строка состояния', FSettings.ShowStatusBar, OptionChanged);
    FCbDrives := AddCheck(Card, 'Панель дисков', FSettings.ShowDriveBar, OptionChanged);
    FCbMid := AddCheck(Card, 'Вертикальная панель команд', FSettings.ShowMidBar, OptionChanged);
    FCbDock := AddCheck(Card, 'Док-панель', FSettings.ShowDock, OptionChanged);





  Card := AddCard(FPages[0], 'Поведение');
  Card.Height := 22 + 2 * 36 + 16;
  FCbHidden := AddCheck(Card, 'Показывать скрытые и системные файлы', FSettings.ShowHiddenFiles, OptionChanged);
  FCbNetwork := AddCheck(Card, 'Кнопка «Сеть» на панели дисков', FSettings.ShowNetworkButton, OptionChanged);

  Card := AddCard(FPages[0], 'Файловые операции и архиватор');
  Card.Height := 22 + 3 * 36 + 22 + 16;
  FCbOpVibe := AddCheck(Card, 'Методом V!be CMD', FSettings.FileOpMode = fomVibe, FileOpModeClick);
  FCbOpExplorer := AddCheck(Card, 'Методом Проводника', FSettings.FileOpMode = fomExplorer, FileOpModeClick);
  FCbOpQuiet := AddCheck(Card, 'Тихий режим', FSettings.FileOpMode = fomQuiet, FileOpModeClick);
  Hint := TText.Create(Self);
  Hint.Parent := Card;
  Hint.Align := TAlignLayout.Top;
  Hint.Height := 20;
  Hint.Text := 'Копирование, перемещение, удаление и упаковка в ZIP';
  Hint.HitTest := False;
  Hint.Tag := 8;
  ApplyFluentText(Hint, 12, False);

  { --- Вид --- }
  Card := AddCard(FPages[1], 'Тема оформления');
  Card.Height := 22 + 126 + 12;
  Row := TRectangle.Create(Self);
  Row.Parent := Card;
  Row.Align := TAlignLayout.Top;
  Row.Height := 126;
  Row.Stroke.Kind := TBrushKind.None;
  Row.Fill.Color := TAlphaColors.Null;
  BuildThemeCard(FCardSystem, Row, 'Как в системе', atSystem);
  BuildThemeCard(FCardLight, Row, 'Светлая', atLight);
  BuildThemeCard(FCardDark, Row, 'Тёмная', atDark);

  Card := AddCard(FPages[1], 'Материал окна');
  Card.Height := 22 + 78 + 12;
  Row := TRectangle.Create(Self);
  Row.Parent := Card;
  Row.Align := TAlignLayout.Top;
  Row.Height := 78;
  Row.Stroke.Kind := TBrushKind.None;
  Row.Fill.Color := TAlphaColors.Null;
  BuildMaterialCard(FCardMatNormal, Row, 'Нормал', wmNormal, $FF3B3B3B);
  BuildMaterialCard(FCardMatAcrylic, Row, 'Акрил', wmAcrylic, $FF5A7A9A);
  BuildMaterialCard(FCardMatMica, Row, 'Мика', wmMica, $FF4A5560);

  Card := AddCard(FPages[1], 'Вкладки панелей');
  Card.Height := 22 + 2 * 36 + 16;
    FCbEqualTabs := AddCheck(Card, 'Одинаковая ширина вкладок', FSettings.EqualTabWidth, OptionChanged);
  FCbTabIcons := AddCheck(Card, 'Показывать иконки на вкладках', FSettings.ShowTabIcons, OptionChanged);


  Card := AddCard(FPages[1], 'Шрифт списка');
  Card.Height := 22 + 40 + 16;
  Hint := TText.Create(Self);
  Hint.Parent := Card;
  Hint.Align := TAlignLayout.Top;
  Hint.Height := 20;
  Hint.Text := 'Размер шрифта (10–22)';
  Hint.HitTest := False;
  Hint.Tag := 8;
  ApplyFluentText(Hint, 12, False);
  FFontSizeEdit := CreateFluentEdit(Self, Card);
  FFontSizeEdit.Align := TAlignLayout.Top;
  FFontSizeEdit.Height := 32;
  FFontSizeEdit.FillMode := fefSubtle;
  FFontSizeEdit.Text := IntToStr(FSettings.ListFontSize);
  FFontSizeEdit.OnChange := OptionChanged;

  Card := AddCard(FPages[1], 'Док-панель');
  Card.Height := 22 + 4 * 36 + 16;
  FCbDockSeps := AddCheck(Card, 'Отображать разделители', FSettings.DockShowSeparators, OptionChanged);
  FCbDockFree := AddCheck(Card, 'Иконки произвольно', FSettings.DockAlign = daFree, DockAlignClick);
  FCbDockCenter := AddCheck(Card, 'Выравнивание по центру', FSettings.DockAlign = daCenter, DockAlignClick);
  FCbDockLeft := AddCheck(Card, 'Выравнивание слева', FSettings.DockAlign = daLeft, DockAlignClick);

  { --- Кэш --- }
  Card := AddCard(FPages[2], 'Миниатюры');
  Card.Height := 22 + 36 + 40 + 28 + 40 + 16;
  FCbThumbs := AddCheck(Card, 'Кэшировать миниатюры в режиме плиток', FSettings.ThumbCacheEnabled, OptionChanged);
  Hint := TText.Create(Self);
  Hint.Parent := Card;
  Hint.Align := TAlignLayout.Top;
  Hint.Height := 20;
  Hint.Text := 'Лимит элементов в кэше (50–4000)';
  Hint.HitTest := False;
  Hint.Tag := 8;
  ApplyFluentText(Hint, 12, False);
  FThumbLimitEdit := CreateFluentEdit(Self, Card);
  FThumbLimitEdit.Align := TAlignLayout.Top;
  FThumbLimitEdit.Height := 32;
  FThumbLimitEdit.FillMode := fefSubtle;
  FThumbLimitEdit.Text := IntToStr(FSettings.ThumbCacheMaxItems);
  FThumbLimitEdit.OnChange := OptionChanged;
  FThumbInfo := TText.Create(Self);
  FThumbInfo.Parent := Card;
  FThumbInfo.Align := TAlignLayout.Top;
  FThumbInfo.Height := 22;
  FThumbInfo.HitTest := False;
  FThumbInfo.Tag := 8;
  ApplyFluentText(FThumbInfo, 12, False);
  FBtnClearCache := CreateFluentButton(Self, Card, '', 'Очистить кэш', fbkStandard, 160, ClearCacheClick);
  FBtnClearCache.Align := TAlignLayout.Top;
  FBtnClearCache.Height := 34;
  FBtnClearCache.Margins.Rect := TRectF.Create(0, 8, 0, 0);
  UpdateThumbInfo;
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
  FBtnClose := CreateFluentButton(Self, FFooter, '', 'Закрыть', fbkAccent, 120, CloseClick);
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
  if (AIndex < 0) or (AIndex > 2) then
    Exit;
  FPage := AIndex;
  for I := 0 to 2 do
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
    I: Integer;
  begin
    Selected := ThemeOfCard(ACard) = FSettings.Theme;
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

procedure TSettingsForm.UpdateThumbInfo;
begin
  if Assigned(FThumbInfo) and Assigned(GlobalThumbCache) then
    FThumbInfo.Text := Format('Сейчас в кэше: %d миниатюр', [GlobalThumbCache.ItemCount]);
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
  ScheduleSave;
  UpdateMaterialCards;
  { Материал влияет на chrome главного окна — обновляем тему, не весь layout. }
  if Assigned(FOnThemeChanged) then
    FOnThemeChanged(FSettings.Theme)
  else if Assigned(FOnOptionsChanged) then
    FOnOptionsChanged();
end;

procedure TSettingsForm.CollectFromUI;
var
  N: Integer;
begin
  FSettings.ShowDock := FCbDock.Checked;
  FSettings.ShowMidBar := FCbMid.Checked;
  FSettings.ShowDriveBar := FCbDrives.Checked;
  FSettings.ShowBreadcrumbs := True;
  FSettings.ShowStatusBar := FCbStatus.Checked;
  FSettings.ShowFnBar := FCbFn.Checked;
  FSettings.ShowQuickAccess := FCbQuick.Checked;
  FSettings.ShowCommandLine := FCbCmd.Checked;
  FSettings.QuickViewEnabled := True;
  FSettings.WindowAnimate := True;
  FSettings.ShowNetworkButton := FCbNetwork.Checked;
  FSettings.ShowHiddenFiles := FCbHidden.Checked;
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
  FSettings.ThumbCacheEnabled := FCbThumbs.Checked;
  N := StrToIntDef(Trim(FFontSizeEdit.Text), FSettings.ListFontSize);
  FSettings.ListFontSize := EnsureRange(N, 10, 22);
  N := StrToIntDef(Trim(FThumbLimitEdit.Text), FSettings.ThumbCacheMaxItems);
  FSettings.ThumbCacheMaxItems := EnsureRange(N, 50, 4000);
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
begin
  CollectFromUI;
  ScheduleSave;
  { Применяем layout main-формы; Save уходит в фон. }
  if Assigned(FOnOptionsChanged) then
    FOnOptionsChanged();
end;

procedure TSettingsForm.ClearCacheClick(Sender: TObject);
begin
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.Clear;
  UpdateThumbInfo;
end;

procedure TSettingsForm.CloseClick(Sender: TObject);
begin
  { Подхватить текст из edit'ов, если OnChange ещё не сработал. }
  CollectFromUI;
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;
  { Всё уже пишется на лету (ScheduleSave/SaveAsync) — синхронный Save
    на Закрыть только фризит UI. Добиваем возможный pending в фоне и выходим. }
  if Assigned(FSettings) then
    FSettings.SaveAsync;
  if Assigned(FOnOptionsChanged) then
    FOnOptionsChanged();
  Close;
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
  for I := 0 to 2 do
    FNavBtns[I].ApplyTheme(AColors);
  if Assigned(FFontSizeEdit) then
    FFontSizeEdit.ApplyTheme(AColors);
  if Assigned(FThumbLimitEdit) then
    FThumbLimitEdit.ApplyTheme(AColors);
  if Assigned(FBtnClearCache) then
    FBtnClearCache.ApplyTheme(AColors);
  if Assigned(FThumbInfo) then
    FThumbInfo.TextSettings.FontColor := AColors.SubTextColor;

  if Assigned(FPages[0]) then
    for I := 0 to FPages[0].Content.ControlsCount - 1 do
      if FPages[0].Content.Controls[I] is TRectangle then
        PaintCard(TRectangle(FPages[0].Content.Controls[I]));
  if Assigned(FPages[1]) then
    for I := 0 to FPages[1].Content.ControlsCount - 1 do
      if FPages[1].Content.Controls[I] is TRectangle then
        PaintCard(TRectangle(FPages[1].Content.Controls[I]));
  if Assigned(FPages[2]) then
    for I := 0 to FPages[2].Content.ControlsCount - 1 do
      if FPages[2].Content.Controls[I] is TRectangle then
        PaintCard(TRectangle(FPages[2].Content.Controls[I]));

  UpdateThemeCards;
  UpdateMaterialCards;
end;

end.

