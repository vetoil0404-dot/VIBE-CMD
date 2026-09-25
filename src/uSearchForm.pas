unit uSearchForm;

{
  Fluent-окно поиска файлов (аналог Alt+F7 в Total Commander).
  Оформление как у настроек и пакетного переименования: карточки,
  TFluentEdit / TFluentButton, без системных TEdit.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Generics.Collections, System.DateUtils, System.IOUtils, System.StrUtils,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics,
  FMX.StdCtrls,
  {$IFDEF MSWINDOWS}Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,{$ENDIF}
  uAppSettings, uThemeManager, uFluentChrome, uFluentEdit, uFluentDatePicker,
  uFileModel, uFileSearch, uCustomScrollbar;

type
  TSearchForm = class(TForm)
  private
    FColors: TThemeColors;
    FEngine: TFileSearchEngine;
    FHits: TList<TSearchHit>;
    FSel: Integer;
    FFound: Integer;
    FRunning: Boolean;
    FInBackground: Boolean;
    FDead: Boolean;
    FTargetPath: string;
    FTargetDir: string;
    FTargetIsDir: Boolean;
    FStartPath: string;
    FSearchRoot: string;

    FRoot: TLayout;
    FBlocks: TLayout;
    FBlkCrit, FBlkFilt, FBlkList: TRectangle;
    FEdMask, FEdPath, FEdText: TFluentEdit;
    FDtFrom, FDtTo: TFluentDatePicker;
    FCbDate, FCbRecurse, FCbText: TFluentCheckRow;
    FBtnBrowse: TFluentButton;
    FHeadPaint: TPaintBox;
    FListBox: TVertScrollBox;
    FListPaint: TPaintBox;
    FListScroll: TCustomFileScrollbar;
    FStatusRow: TLayout;
    FStatus: TText;
    FBtnStart, FBtnStop, FBtnGo, FBtnFeed, FBtnBg, FBtnClose: TFluentButton;
    FOnGoToHit: TProc<string, string, Boolean>;
    FOnFeedToPanel: TProc<string, TFileEntryList>;
    FOnStateChange: TNotifyEvent;

    procedure BuildUI;
    function MakeCard(AParent: TFmxObject; const ATitle: string): TRectangle;
    function MakeLabel(AParent: TFmxObject; const ACaption: string;
      AX, AY, AW, AH: Single; ABold: Boolean = False): TText;
    function MakeEdit(AParent: TFmxObject; AX, AY, AW, AH: Single): TFluentEdit;
    procedure Place(ACtrl: TControl; AX, AY, AW, AH: Single);
    procedure LayoutBlocks;
    procedure BlocksResize(Sender: TObject);
    procedure ApplyNativeChrome;
    procedure ThemeTree(AObj: TFmxObject; const AColors: TThemeColors);
    procedure EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure EditSubmit(Sender: TObject);
    procedure DateChanged(Sender: TObject);
    procedure TextChanged(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure GoClick(Sender: TObject);
    procedure FeedClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure BgClick(Sender: TObject);
    procedure UpdateCaption;
    procedure UpdateFeedButton;
    procedure HeadPaint(Sender: TObject; Canvas: TCanvas);
    procedure ListPaint(Sender: TObject; Canvas: TCanvas);
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ListDblClick(Sender: TObject);
    procedure HandleHits(const AHits: TArray<TSearchHit>);
    procedure HandleProgress(const AText: string);
    procedure HandleDone(AFound: Integer; AStopped: Boolean);
    procedure SetRunning(AValue: Boolean);
    procedure RefreshList;
    procedure EnsureRowVisible(AIndex: Integer);
    procedure ListBoxResize(Sender: TObject);
    procedure ListViewportChange(Sender: TObject;
      const OldViewportPosition, NewViewportPosition: TPointF;
      const ContentSizeChanged: Boolean);
    function CollectParams(out AParams: TSearchParams): Boolean;
    procedure GoToSelected;
    procedure SetStatus(const AText: string);
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent; const AStartPath: string;
      const AColors: TThemeColors); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure RestoreFromBackground;
    function StealHitsAsEntries: TFileEntryList;
    property TargetPath: string read FTargetPath;
    property TargetDir: string read FTargetDir;
    property TargetIsDir: Boolean read FTargetIsDir;
    property SearchRoot: string read FSearchRoot;
    property Running: Boolean read FRunning;
    property InBackground: Boolean read FInBackground;
    property OnGoToHit: TProc<string, string, Boolean> read FOnGoToHit write FOnGoToHit;
    property OnFeedToPanel: TProc<string, TFileEntryList> read FOnFeedToPanel write FOnFeedToPanel;
    property OnStateChange: TNotifyEvent read FOnStateChange write FOnStateChange;
  end;

implementation

const
  GAP        = 10;
  INSET      = 12;
  EDIT_H     = 28;
  LAB_W      = 92;
  CRIT_H     = 108;
  FILT_H     = 176;
  ROW_H      = 26;
  BROWSE_W   = 36;

constructor TSearchForm.Create(AOwner: TComponent; const AStartPath: string;
  const AColors: TThemeColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  FStartPath := AStartPath;
  FHits := TList<TSearchHit>.Create;
  FSel := -1;
  FEngine := TFileSearchEngine.Create;
  FEngine.OnHits := HandleHits;
  FEngine.OnProgress := HandleProgress;
  FEngine.OnDone := HandleDone;
  Width := 860;
  Height := 720;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Caption := 'Поиск файлов';
  ShowHint := True;
  Position := TFormPosition.OwnerFormCenter;
  FormStyle := TFormStyle.StayOnTop;
  BuildUI;
  ApplyTheme(FColors);
  ApplyNativeChrome;
end;

destructor TSearchForm.Destroy;
begin
  FDead := True;
  if Assigned(FEngine) then
    FEngine.Stop;
  FreeAndNil(FListScroll);
  FreeAndNil(FEngine);
  FreeAndNil(FHits);
  inherited;
end;

procedure TSearchForm.ApplyNativeChrome;
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

procedure TSearchForm.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TSearchForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
  LayoutBlocks;
  if Assigned(FEdMask) then
  begin
    FEdMask.SelectAll;
    FEdMask.SetFocus;
  end;
end;

procedure TSearchForm.Place(ACtrl: TControl; AX, AY, AW, AH: Single);
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

function TSearchForm.MakeCard(AParent: TFmxObject; const ATitle: string): TRectangle;
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
    MakeLabel(Result, ATitle, INSET, 8, 500, 20, True);
end;

function TSearchForm.MakeLabel(AParent: TFmxObject; const ACaption: string;
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

function TSearchForm.MakeEdit(AParent: TFmxObject; AX, AY, AW, AH: Single): TFluentEdit;
begin
  Result := CreateFluentEdit(Self, AParent);
  Result.FillMode := fefSubtle;
  Result.OnKeyDown := EditKeyDown;
  Result.OnSubmit := EditSubmit;
  Place(Result, AX, AY, AW, AH);
end;

procedure TSearchForm.LayoutBlocks;
var
  W, PathW, DateW: Single;
begin
  if FBlocks = nil then
    Exit;
  W := FBlocks.Width;
  if W < 80 then
    W := 800;

  Place(FBlkCrit, 0, 0, W, CRIT_H);
  Place(FBlkFilt, 0, CRIT_H + GAP, W, FILT_H);

  PathW := Max(80, W - INSET * 2 - LAB_W - BROWSE_W - 8);
  Place(FEdMask, INSET + LAB_W, 34, Max(80, W - INSET * 2 - LAB_W), EDIT_H);
  Place(FEdPath, INSET + LAB_W, 70, PathW, EDIT_H);
  Place(FBtnBrowse, INSET + LAB_W + PathW + 8, 70, BROWSE_W, EDIT_H);

  Place(FCbDate, INSET, 32, 280, 28);
  Place(FCbRecurse, INSET + 300, 32, 260, 28);
  DateW := 158;
  Place(FDtFrom, INSET + 24, 68, DateW, EDIT_H);
  Place(FDtTo, INSET + 24 + DateW + 50, 68, DateW, EDIT_H);
  Place(FCbText, INSET, 104, 320, 28);
  Place(FEdText, INSET, 136, Max(80, W - INSET * 2), EDIT_H);
end;

procedure TSearchForm.BlocksResize(Sender: TObject);
begin
  LayoutBlocks;
end;

procedure TSearchForm.BuildUI;
var
  Footer: TLayout;
  StartPath: string;
begin
  FRoot := TLayout.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Padding.Rect := TRectF.Create(18, 14, 18, 14);

  Footer := TLayout.Create(Self);
  Footer.Parent := FRoot;
  Footer.Align := TAlignLayout.Bottom;
  Footer.Height := 42;
  Footer.Margins.Top := 4;

  FBtnClose := CreateFluentButton(Self, Footer, '', 'Закрыть', fbkStandard, 110, CloseClick);
  FBtnClose.Align := TAlignLayout.Right;
  FBtnBg := CreateFluentButton(Self, Footer, '', 'В фоне', fbkStandard, 100, BgClick);
  FBtnBg.Align := TAlignLayout.Right;
  FBtnBg.Margins.Right := 8;
  FBtnBg.Hint := 'Свернуть и продолжить поиск';
  FBtnBg.ShowHint := True;
  FBtnGo := CreateFluentButton(Self, Footer, '', 'Перейти', fbkStandard, 120, GoClick);
  FBtnGo.Align := TAlignLayout.Right;
  FBtnGo.Margins.Right := 8;
  FBtnFeed := CreateFluentButton(Self, Footer, '', 'Файлы на панель', fbkStandard, 168, FeedClick);
  FBtnFeed.Align := TAlignLayout.Right;
  FBtnFeed.Margins.Right := 8;
  FBtnFeed.Hint := 'Показать найденные файлы в файловой панели';
  FBtnFeed.ShowHint := True;
  FBtnFeed.Enabled := False;
  FBtnStop := CreateFluentButton(Self, Footer, '', 'Остановить', fbkStandard, 130, StopClick);
  FBtnStop.Align := TAlignLayout.Right;
  FBtnStop.Margins.Right := 8;
  FBtnStop.Visible := False;
  FBtnStart := CreateFluentButton(Self, Footer, '', 'Начать поиск', fbkAccent, 148, StartClick);
  FBtnStart.Align := TAlignLayout.Right;
  FBtnStart.Margins.Right := 8;

  FStatusRow := TLayout.Create(Self);
  FStatusRow.Parent := FRoot;
  FStatusRow.Align := TAlignLayout.Bottom;
  FStatusRow.Height := 24;
  FStatusRow.Margins.Top := 6;
  FStatus := TText.Create(Self);
  FStatus.Parent := FStatusRow;
  FStatus.Align := TAlignLayout.Client;
  FStatus.HitTest := False;
  ApplyFluentText(FStatus, 12, False);
  FStatus.TextSettings.HorzAlign := TTextAlign.Leading;
  FStatus.TextSettings.VertAlign := TTextAlign.Center;
  FStatus.TextSettings.WordWrap := False;
  FStatus.TextSettings.Trimming := TTextTrimming.Character;
  FStatus.Text := 'Укажите маску и папку, затем начните поиск';

  FBlkList := TRectangle.Create(Self);
  FBlkList.Parent := FRoot;
  FBlkList.Align := TAlignLayout.Client;
  FBlkList.XRadius := 10;
  FBlkList.YRadius := 10;
  FBlkList.Stroke.Kind := TBrushKind.Solid;
  FBlkList.Fill.Kind := TBrushKind.Solid;
  FBlkList.Padding.Rect := TRectF.Create(8, 6, 8, 8);
  FBlkList.Margins.Top := 4;
  FBlkList.Tag := 1;

  FHeadPaint := TPaintBox.Create(Self);
  FHeadPaint.Parent := FBlkList;
  FHeadPaint.Align := TAlignLayout.Top;
  FHeadPaint.Height := ROW_H;
  FHeadPaint.HitTest := False;
  FHeadPaint.OnPaint := HeadPaint;

  FListBox := TVertScrollBox.Create(Self);
  FListBox.Parent := FBlkList;
  FListBox.Align := TAlignLayout.Client;
  FListBox.ShowScrollBars := False;
  FListBox.AniCalculations.AutoShowing := False;
  FListBox.OnResize := ListBoxResize;
  FListBox.OnViewportPositionChange := ListViewportChange;
  FListScroll := TCustomFileScrollbar.Create(FBlkList, FListBox);
  FListPaint := TPaintBox.Create(Self);
  FListPaint.Parent := FListBox;
  FListPaint.Align := TAlignLayout.Top;
  FListPaint.Height := 80;
  FListPaint.OnPaint := ListPaint;
  FListPaint.OnMouseDown := ListMouseDown;
  FListPaint.OnDblClick := ListDblClick;

  FBlocks := TLayout.Create(Self);
  FBlocks.Parent := FRoot;
  FBlocks.Align := TAlignLayout.Top;
  FBlocks.Height := CRIT_H + GAP + FILT_H;
  FBlocks.Margins.Bottom := GAP;
  FBlocks.OnResize := BlocksResize;

  FBlkCrit := MakeCard(FBlocks, 'Что искать');
  MakeLabel(FBlkCrit, 'Маска (* ? ;):', INSET, 34, LAB_W, EDIT_H);
  FEdMask := MakeEdit(FBlkCrit, INSET + LAB_W, 34, 200, EDIT_H);
  FEdMask.Text := '*.*';
  MakeLabel(FBlkCrit, 'Папка / диск:', INSET, 70, LAB_W, EDIT_H);
  FEdPath := MakeEdit(FBlkCrit, INSET + LAB_W, 70, 200, EDIT_H);
  StartPath := FStartPath;
  if (StartPath = '') or IsVirtualShellPath(StartPath) or
     not TDirectory.Exists(StartPath) then
    StartPath := 'C:\';
  FEdPath.Text := IncludeTrailingPathDelimiter(StartPath);
  FBtnBrowse := CreateFluentButton(Self, FBlkCrit, '', '...', fbkStandard, BROWSE_W, BrowseClick);
  FBtnBrowse.Hint := 'Выбрать папку';

  FBlkFilt := MakeCard(FBlocks, 'Фильтры');
  FCbDate := TFluentCheckRow.Create(Self);
  FCbDate.Setup(FBlkFilt, 'Фильтр по дате изменения', False);
  FCbRecurse := TFluentCheckRow.Create(Self);
  FCbRecurse.Setup(FBlkFilt, 'Включая подпапки', True);
  MakeLabel(FBlkFilt, 'С:', INSET, 68, 22, EDIT_H);
  FDtFrom := TFluentDatePicker.Create(Self);
  FDtFrom.Parent := FBlkFilt;
  FDtFrom.OnEditKeyDown := EditKeyDown;
  FDtFrom.OnEditSubmit := EditSubmit;
  FDtFrom.OnChange := DateChanged;
  MakeLabel(FBlkFilt, 'По:', INSET + 24 + 158 + 12, 68, 30, EDIT_H);
  FDtTo := TFluentDatePicker.Create(Self);
  FDtTo.Parent := FBlkFilt;
  FDtTo.OnEditKeyDown := EditKeyDown;
  FDtTo.OnEditSubmit := EditSubmit;
  FDtTo.OnChange := DateChanged;

  FCbText := TFluentCheckRow.Create(Self);
  FCbText.Setup(FBlkFilt, 'Искать с текстом', False);
  FCbText.OnChange := TextChanged;
  FEdText := MakeEdit(FBlkFilt, INSET, 136, 200, EDIT_H);
  FEdText.OnChange := TextChanged;
  FEdText.Hint := 'Текст или маска (* ?) внутри файла, UTF-8 / ANSI';
  FEdText.ShowHint := True;

  LayoutBlocks;
end;

procedure TSearchForm.EditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    CloseClick(nil);
    Key := 0;
  end;
end;

procedure TSearchForm.EditSubmit(Sender: TObject);
begin
  if not FRunning then
    StartClick(nil);
end;

procedure TSearchForm.DateChanged(Sender: TObject);
begin
  if (FCbDate = nil) or FCbDate.Checked then
    Exit;
  if ((FDtFrom <> nil) and FDtFrom.HasDate) or
     ((FDtTo <> nil) and FDtTo.HasDate) then
    FCbDate.Checked := True;
end;

procedure TSearchForm.TextChanged(Sender: TObject);
begin
  if FCbText = nil then
    Exit;
  if Sender = FCbText then
    Exit;
  if FCbText.Checked then
    Exit;
  if Assigned(FEdText) and (Trim(FEdText.Text) <> '') then
    FCbText.Checked := True;
end;

procedure TSearchForm.BrowseClick(Sender: TObject);
var
  Dir: string;
  Wnd: NativeUInt;
begin
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Self);
  {$ELSE}
  Wnd := 0;
  {$ENDIF}
  Dir := PickSearchFolder(Wnd, 'Папка поиска', Trim(FEdPath.Text));
  if Dir <> '' then
    FEdPath.Text := IncludeTrailingPathDelimiter(Dir);
end;

function TSearchForm.CollectParams(out AParams: TSearchParams): Boolean;
var
  Root: string;
  D1, D2: TDateTime;
  HasFrom, HasTo: Boolean;
begin
  AParams := Default(TSearchParams);
  Result := False;
  Root := Trim(FEdPath.Text);
  if (Length(Root) = 2) and (Root[2] = ':') then
    Root := Root + PathDelim;
  Root := ExcludeTrailingPathDelimiter(Root);
  if (Length(Root) = 2) and (Root[2] = ':') then
    Root := Root + PathDelim;
  if (Root = '') or not TDirectory.Exists(Root) then
  begin
    SetStatus('Укажите существующую папку или диск');
    Exit;
  end;
  AParams.Root := Root;
  AParams.Mask := Trim(FEdMask.Text);
  if AParams.Mask = '' then
    AParams.Mask := '*.*';
  AParams.Recursive := Assigned(FCbRecurse) and FCbRecurse.Checked;
  AParams.UseDate := Assigned(FCbDate) and FCbDate.Checked;
  if AParams.UseDate then
  begin
    HasFrom := Assigned(FDtFrom) and FDtFrom.TryGetDate(D1);
    HasTo := Assigned(FDtTo) and FDtTo.TryGetDate(D2);
    if not HasFrom and (Assigned(FDtFrom) and (Trim(FDtFrom.Text) <> '')) then
    begin
      SetStatus('Неверная дата «с». Формат дд.мм.гггг');
      Exit;
    end;
    if not HasTo and (Assigned(FDtTo) and (Trim(FDtTo.Text) <> '')) then
    begin
      SetStatus('Неверная дата «по». Формат дд.мм.гггг');
      Exit;
    end;
    if not HasFrom and not HasTo then
    begin
      SetStatus('Укажите дату «с» и/или «по»');
      Exit;
    end;
    if HasFrom and HasTo and (DateOf(D1) > DateOf(D2)) then
    begin
      SetStatus('Дата «с» больше даты «по»');
      Exit;
    end;
    AParams.HasFrom := HasFrom;
    AParams.HasTo := HasTo;
    if HasFrom then
      AParams.DateFrom := DateOf(D1)
    else
      AParams.DateFrom := 0;
    if HasTo then
      AParams.DateTo := DateOf(D2)
    else
      AParams.DateTo := 0;
  end;
  AParams.UseText := Assigned(FCbText) and FCbText.Checked;
  if AParams.UseText then
  begin
    AParams.TextQuery := '';
    if Assigned(FEdText) then
      AParams.TextQuery := Trim(FEdText.Text);
    if AParams.TextQuery = '' then
    begin
      SetStatus('Укажите текст для поиска в файлах');
      Exit;
    end;
  end;
  Result := True;
end;

procedure TSearchForm.SetRunning(AValue: Boolean);
begin
  FRunning := AValue;
  if Assigned(FBtnStart) then
    FBtnStart.Visible := not AValue;
  if Assigned(FBtnStop) then
    FBtnStop.Visible := AValue;
  UpdateCaption;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self);
end;

procedure TSearchForm.StartClick(Sender: TObject);
var
  Params: TSearchParams;
begin
  if FRunning then
    Exit;
  if not CollectParams(Params) then
    Exit;
  FHits.Clear;
  FSel := -1;
  FFound := 0;
  FSearchRoot := Params.Root;
  RefreshList;
  UpdateFeedButton;
  SetRunning(True);
  SetStatus('Поиск…');
  FEngine.Start(Params);
end;

procedure TSearchForm.StopClick(Sender: TObject);
begin
  if not FRunning then
    Exit;
  FEngine.Stop;
  SetRunning(False);
  SetStatus(Format('Остановлено. Найдено: %d', [FHits.Count]));
  UpdateFeedButton;
end;

procedure TSearchForm.GoClick(Sender: TObject);
begin
  GoToSelected;
end;

procedure TSearchForm.UpdateFeedButton;
begin
  if Assigned(FBtnFeed) then
    FBtnFeed.Enabled := Assigned(FHits) and (FHits.Count > 0);
end;

procedure TSearchForm.FeedClick(Sender: TObject);
begin
  if not Assigned(FHits) or (FHits.Count = 0) then
  begin
    SetStatus('Нет результатов для панели');
    Exit;
  end;
  if FRunning then
    FEngine.Stop;
  if FSearchRoot = '' then
    FSearchRoot := Trim(FEdPath.Text);
  if Assigned(FOnFeedToPanel) then
    FOnFeedToPanel(FSearchRoot, StealHitsAsEntries)
  else
    ModalResult := mrYes;
end;

function TSearchForm.StealHitsAsEntries: TFileEntryList;
var
  Hit: TSearchHit;
  Entry: TFileEntry;
  RootSlash, Rel: string;
begin
  Result := TFileEntryList.Create;
  RootSlash := IncludeTrailingPathDelimiter(FSearchRoot);
  for Hit in FHits do
  begin
    Entry := Default(TFileEntry);
    Entry.FullPath := Hit.FullPath;
    if (RootSlash <> '') and StartsText(RootSlash, Hit.FullPath) then
      Rel := Copy(Hit.FullPath, Length(RootSlash) + 1, MaxInt)
    else
      Rel := Hit.Name;
    if Rel = '' then
      Rel := Hit.Name;
    Entry.Name := Rel;
    Entry.IsDirectory := Hit.IsDirectory;
    Entry.Size := Hit.Size;
    Entry.Modified := Hit.Modified;
    if Hit.IsDirectory then
      Entry.Extension := ''
    else
      Entry.Extension := ExtractFileExt(Hit.Name);
    PrepareFileEntry(Entry);
    Result.Add(Entry);
  end;
end;

procedure TSearchForm.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TSearchForm.BgClick(Sender: TObject);
begin
  FInBackground := True;
  Hide;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self);
end;

procedure TSearchForm.RestoreFromBackground;
begin
  FInBackground := False;
  WindowState := TWindowState.wsNormal;
  if not Visible then
    Show;
  BringToFront;
  Activate;
  ApplyNativeChrome;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self);
end;

procedure TSearchForm.UpdateCaption;
begin
  if FRunning then
    Caption := Format('Поиск файлов — найдено %d', [FHits.Count])
  else if Assigned(FHits) and (FHits.Count > 0) then
    Caption := Format('Поиск файлов — %d', [FHits.Count])
  else
    Caption := 'Поиск файлов';
end;

procedure TSearchForm.DoClose(var CloseAction: TCloseAction);
begin
  if FRunning and Assigned(FEngine) then
    FEngine.Stop;
  FDead := True;
  CloseAction := TCloseAction.caFree;
  inherited;
end;

procedure TSearchForm.GoToSelected;
var
  Hit: TSearchHit;
begin
  if (FSel < 0) or (FSel >= FHits.Count) then
  begin
    SetStatus('Выберите файл в списке результатов');
    Exit;
  end;
  Hit := FHits[FSel];
  FTargetPath := Hit.FullPath;
  FTargetDir := Hit.Dir;
  FTargetIsDir := Hit.IsDirectory;
  if Assigned(FOnGoToHit) then
    FOnGoToHit(FTargetPath, FTargetDir, FTargetIsDir)
  else
  begin
    if FRunning then
      FEngine.Stop;
    ModalResult := mrOk;
  end;
end;

procedure TSearchForm.SetStatus(const AText: string);
begin
  if Assigned(FStatus) then
    FStatus.Text := AText;
end;

procedure TSearchForm.HandleHits(const AHits: TArray<TSearchHit>);
var
  H: TSearchHit;
begin
  if FDead then
    Exit;
  for H in AHits do
    FHits.Add(H);
  FFound := FHits.Count;
  RefreshList;
  UpdateFeedButton;
  UpdateCaption;
  if FRunning then
    SetStatus(Format('Найдено: %d    %s', [FHits.Count, FStatus.TagString]));
end;

procedure TSearchForm.HandleProgress(const AText: string);
begin
  if FDead then
    Exit;
  FStatus.TagString := AText;
  if FRunning then
    SetStatus(Format('Найдено: %d    %s', [FHits.Count, AText]));
end;

procedure TSearchForm.HandleDone(AFound: Integer; AStopped: Boolean);
begin
  if FDead then
    Exit;
  SetRunning(False);
  FFound := AFound;
  UpdateCaption;
  if AStopped then
    SetStatus(Format('Остановлено. Найдено: %d', [AFound]))
  else if AFound = 0 then
    SetStatus('Ничего не найдено')
  else if AFound > FHits.Count then
    SetStatus(Format('Готово. Найдено: %d (показано %d)', [AFound, FHits.Count]))
  else
    SetStatus(Format('Готово. Найдено: %d', [AFound]));
  RefreshList;
  UpdateFeedButton;
end;

procedure TSearchForm.RefreshList;
begin
  if FListPaint = nil then
    Exit;
  FListPaint.Height := Max(48, FHits.Count * ROW_H + 4);
  FListPaint.Repaint;
  if Assigned(FHeadPaint) then
    FHeadPaint.Repaint;
  if Assigned(FListScroll) then
    FListScroll.UpdateThumb;
end;

procedure TSearchForm.ListBoxResize(Sender: TObject);
begin
  if Assigned(FListScroll) then
    FListScroll.UpdateThumb;
end;

procedure TSearchForm.ListViewportChange(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF;
  const ContentSizeChanged: Boolean);
begin
  if Assigned(FListScroll) then
    FListScroll.UpdateThumb;
end;

procedure TSearchForm.EnsureRowVisible(AIndex: Integer);
var
  Y, ViewH: Single;
begin
  if (FListBox = nil) or (AIndex < 0) then
    Exit;
  Y := AIndex * ROW_H;
  ViewH := FListBox.Height;
  if Y < FListBox.ViewportPosition.Y then
    FListBox.ViewportPosition := TPointF.Create(0, Y)
  else if Y + ROW_H > FListBox.ViewportPosition.Y + ViewH then
    FListBox.ViewportPosition := TPointF.Create(0, Y + ROW_H - ViewH);
end;

procedure TSearchForm.HeadPaint(Sender: TObject; Canvas: TCanvas);
var
  W, X1, X2, X3: Single;
  R: TRectF;
begin
  if Canvas = nil then
    Exit;
  W := FHeadPaint.Width;
  X1 := W * 0.28;
  X2 := W * 0.70;
  X3 := W * 0.84;
  Canvas.BeginScene;
  try
    Canvas.Fill.Color := FColors.CardBackground;
    Canvas.FillRect(TRectF.Create(0, 0, W, ROW_H), 0, 0, [], 1);
    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := 12;
    Canvas.Fill.Color := FColors.SubTextColor;
    R := TRectF.Create(8, 0, X1 - 6, ROW_H);
    Canvas.FillText(R, 'Имя', False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    R := TRectF.Create(X1 + 4, 0, X2 - 6, ROW_H);
    Canvas.FillText(R, 'Папка', False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    R := TRectF.Create(X2 + 4, 0, X3 - 6, ROW_H);
    Canvas.FillText(R, 'Размер', False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
    R := TRectF.Create(X3 + 4, 0, W - 8, ROW_H);
    Canvas.FillText(R, 'Изменён', False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Canvas.Stroke.Color := FColors.DividerColor;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(TPointF.Create(0, ROW_H - 0.5), TPointF.Create(W, ROW_H - 0.5), 1);
  finally
    Canvas.EndScene;
  end;
end;

procedure TSearchForm.ListPaint(Sender: TObject; Canvas: TCanvas);
var
  I: Integer;
  W, Y, X1, X2, X3: Single;
  R: TRectF;
  Hit: TSearchHit;
  SizeText, DateText: string;
begin
  if Canvas = nil then
    Exit;
  W := FListPaint.Width;
  X1 := W * 0.28;
  X2 := W * 0.70;
  X3 := W * 0.84;
  Canvas.BeginScene;
  try
    Canvas.Fill.Color := FColors.PanelBackground;
    Canvas.FillRect(TRectF.Create(0, 0, W, FListPaint.Height), 0, 0, [], 1);
    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := 12;
    if FHits.Count = 0 then
    begin
      Canvas.Fill.Color := FColors.SubTextColor;
      R := TRectF.Create(8, 8, W - 8, 40);
      Canvas.FillText(R, 'Результаты появятся здесь', False, 1, [],
        TTextAlign.Leading, TTextAlign.Center);
      Exit;
    end;
    for I := 0 to FHits.Count - 1 do
    begin
      Y := I * ROW_H;
      Hit := FHits[I];
      if I = FSel then
      begin
        Canvas.Fill.Color := FColors.AccentSubtle;
        Canvas.FillRect(TRectF.Create(0, Y, W, Y + ROW_H), 0, 0, [], 1);
      end
      else if Odd(I) then
      begin
        Canvas.Fill.Color := FColors.ItemAltBackground;
        Canvas.FillRect(TRectF.Create(0, Y, W, Y + ROW_H), 0, 0, [], 1);
      end;
      Canvas.Fill.Color := FColors.TextColor;
      R := TRectF.Create(8, Y, X1 - 6, Y + ROW_H);
      Canvas.FillText(R, Hit.Name, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
      Canvas.Fill.Color := FColors.SubTextColor;
      R := TRectF.Create(X1 + 4, Y, X2 - 6, Y + ROW_H);
      Canvas.FillText(R, Hit.Dir, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
      if Hit.IsDirectory then
        SizeText := '<папка>'
      else
        SizeText := FormatFileSize(Hit.Size);
      R := TRectF.Create(X2 + 4, Y, X3 - 6, Y + ROW_H);
      Canvas.FillText(R, SizeText, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
      if Hit.Modified > 0 then
        DateText := FormatDateTime('dd.mm.yyyy hh:nn', Hit.Modified)
      else
        DateText := '';
      R := TRectF.Create(X3 + 4, Y, W - 8, Y + ROW_H);
      Canvas.FillText(R, DateText, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    end;
  finally
    Canvas.EndScene;
  end;
end;

procedure TSearchForm.ListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
begin
  Idx := Trunc(Y / ROW_H);
  if (Idx >= 0) and (Idx < FHits.Count) then
  begin
    FSel := Idx;
    FListPaint.Repaint;
  end;
end;

procedure TSearchForm.ListDblClick(Sender: TObject);
begin
  GoToSelected;
end;

procedure TSearchForm.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    CloseClick(nil);
    Key := 0;
    Exit;
  end;
  if (Key = vkReturn) and not (ssCtrl in Shift) then
  begin
    if not FRunning then
      StartClick(nil);
    Key := 0;
    Exit;
  end;
  inherited;
  if Key = 0 then
    Exit;
  if (Key = vkReturn) and (ssCtrl in Shift) then
  begin
    GoToSelected;
    Key := 0;
  end
  else if (Key = vkUp) and (FHits.Count > 0) then
  begin
    if FSel < 0 then
      FSel := 0
    else if FSel > 0 then
      Dec(FSel);
    EnsureRowVisible(FSel);
    FListPaint.Repaint;
    Key := 0;
  end
  else if (Key = vkDown) and (FHits.Count > 0) then
  begin
    if FSel < 0 then
      FSel := 0
    else if FSel < FHits.Count - 1 then
      Inc(FSel);
    EnsureRowVisible(FSel);
    FListPaint.Repaint;
    Key := 0;
  end;
end;

procedure TSearchForm.ThemeTree(AObj: TFmxObject; const AColors: TThemeColors);
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
  else if AObj is TFluentDatePicker then
    TFluentDatePicker(AObj).ApplyTheme(AColors)
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

procedure TSearchForm.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  if Assigned(FStatus) then
    FStatus.TextSettings.FontColor := AColors.SubTextColor;
  ApplyNativeChrome;
  ThemeTree(FRoot, AColors);
  if Assigned(FListScroll) then
    FListScroll.ApplyTheme(AColors);
  if Assigned(FHeadPaint) then
    FHeadPaint.Repaint;
  if Assigned(FListPaint) then
    FListPaint.Repaint;
end;

end.
