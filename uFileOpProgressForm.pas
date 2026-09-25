unit uFileOpProgressForm;

{
  Плавающее Fluent-окно прогресса V!be CMD.
  Выполнить / Пауза / Пропустить / Отмена / В фоне.
  Конфликт имён — на том же окне, без второго диалога.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IOUtils,
  System.Generics.Collections,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  {$IFDEF MSWINDOWS}Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,{$ENDIF}
  uThemeManager, uFluentChrome, uFileOps, uFileOpEngine, uAppSettings,
  uThumbCache, UCoreEngine;

procedure RunVibeOperation(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; AOnDone: TFileOpDoneProc; APermanent: Boolean = False;
  AOnItemDone: TFileOpItemDoneProc = nil);
function RestoreVibeBackground(AKind: TFileOpKind): Boolean;

type
  TFileOpProgressForm = class(TForm)
  private
    FColors: TThemeColors;
    FEngine: TFileOpEngine;
    FOnDone: TFileOpDoneProc;
    FTimer: TTimer;
    FBackground: Boolean;
    FFinished: Boolean;

    FRoot: TRectangle;
    FTitle: TText;
    FFileName: TText;
    FPaths: TText;
    FStatus: TText;
    FStats: TText;
    FFileTrack, FFileFill: TRectangle;
    FTotalTrack, FTotalFill: TRectangle;
    FFilePct, FTotalPct: TText;
    FBtnGo, FBtnPause, FBtnSkip, FBtnCancel, FBtnBg: TFluentButton;
    FKeepOpen: Boolean;
    FDeleteAsked: Boolean;

    FConflict: TRectangle;
    FConfTitle: TText;
    FConfCards: TLayout;
    FSrcCard, FDstCard: TRectangle;
    FSrcCap, FDstCap: TText;
    FSrcImg, FDstImg: TImage;
    FSrcName, FDstName: TText;
    FSrcMeta, FDstMeta: TText;
    FSrcNewer, FDstNewer: TText;
    FConfGen: Integer;
    FConfPoll: TTimer;
    FConfDead: Boolean;
    FAnswer: TProc<TConflictChoice>;
    FBtnConfReplace, FBtnConfSkip, FBtnConfAuto, FBtnConfNewer: TFluentButton;
    FBtnConfAll, FBtnConfSkipAll, FBtnConfCancel: TFluentButton;

    FConfirm: TRectangle;
    FConfAskTitle, FConfAskText: TText;

    procedure BuildUI;
    procedure ApplyNativeChrome;
    procedure Tick(Sender: TObject);
    procedure PaintBars(const P: TFileOpProgress);
    procedure SyncButtons(const P: TFileOpProgress);
    procedure GoClick(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure SkipClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure BgClick(Sender: TObject);
    procedure ShowConflict(const AInfo: TFileOpConflictInfo; AAnswer: TProc<TConflictChoice>);
    procedure HideConflict;
    procedure BuildConflictCard(AParent: TFmxObject; const ACaption: string;
      out ACard: TRectangle; out ACap, ANewer: TText; out AImg: TImage;
      out AName, AMeta: TText);
    procedure SetConfFallbackIcon(const APath: string; AIsDir: Boolean; AImg: TImage);
    procedure LoadConfThumb(const APath: string; AIsDir: Boolean; AImg: TImage);
    procedure ConfPollTick(Sender: TObject);
    procedure ConfClick(Sender: TObject);
    procedure ShowDeleteConfirm(const P: TFileOpProgress);
    procedure HideDeleteConfirm;
    procedure ConfirmYesClick(Sender: TObject);
    procedure ConfirmNoClick(Sender: TObject);
    procedure EngineDone(Success: Boolean; const ErrorMsg: string);
    procedure PlaceNearOwner;
    procedure ThemeTree(AObj: TFmxObject; const AColors: TThemeColors);
    procedure FireDone(Success: Boolean; const ErrorMsg: string);
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
  public
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
    constructor Create(AOwner: TComponent; AEngine: TFileOpEngine;
      AOnDone: TFileOpDoneProc; const AColors: TThemeColors); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme(const AColors: TThemeColors);
    function TryRestore(AKind: TFileOpKind): Boolean;
  end;

implementation

uses
  System.Math, System.StrUtils, FMX.Dialogs;

type
  TQueuedOp = record
    Kind: TFileOpKind;
    Sources: TArray<string>;
    Dest: string;
    Permanent: Boolean;
    OnDone: TFileOpDoneProc;
    OnItemDone: TFileOpItemDoneProc;
  end;

var
  GActive: TFileOpProgressForm;
  GQueue: TList<TQueuedOp>;

procedure PumpQueue; forward;

function RestoreVibeBackground(AKind: TFileOpKind): Boolean;
begin
  Result := Assigned(GActive) and GActive.TryRestore(AKind);
end;

function TFileOpProgressForm.TryRestore(AKind: TFileOpKind): Boolean;
begin
  Result := FBackground and Assigned(FEngine) and (FEngine.Kind = AKind) and
    not FFinished;
  if not Result then
    Exit;
  FBackground := False;
  WindowState := TWindowState.wsNormal;
  if not Visible then
    Show;
  BringToFront;
  Activate;
  ApplyNativeChrome;
end;

procedure RunVibeOperation(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; AOnDone: TFileOpDoneProc; APermanent: Boolean;
  AOnItemDone: TFileOpItemDoneProc);
var
  Eng: TFileOpEngine;
  Frm: TFileOpProgressForm;
  Q: TQueuedOp;
  Colors: TThemeColors;
begin
  if Length(ASources) = 0 then
  begin
    if Assigned(AOnDone) then
      AOnDone(True, '');
    Exit;
  end;
  if GActive <> nil then
  begin
    if GQueue = nil then
      GQueue := TList<TQueuedOp>.Create;
    Q.Kind := AKind;
    Q.Sources := Copy(ASources);
    Q.Dest := ADest;
    Q.Permanent := APermanent;
    Q.OnDone := AOnDone;
    Q.OnItemDone := AOnItemDone;
    GQueue.Add(Q);
    Exit;
  end;
  Colors := GetThemeColors(ActiveAppTheme);
  Eng := TFileOpEngine.Create(AKind, ASources, ADest, APermanent);
  Eng.OnItemDone := AOnItemDone;
  Eng.SpecialCopy :=
    procedure(ASrc, ADst: string)
    begin
      if AKind = okDelete then
        DeletePathSync(ASrc, APermanent)
      else if AKind <> okArchive then
        CopyPathSync(ASrc, ADst);
    end;
  Frm := TFileOpProgressForm.Create(Application, Eng, AOnDone, Colors);
  GActive := Frm;
  Frm.Show;
end;

procedure PumpQueue;
var
  Q: TQueuedOp;
begin
  GActive := nil;
  if (GQueue = nil) or (GQueue.Count = 0) then
    Exit;
  Q := GQueue[0];
  GQueue.Delete(0);
  RunVibeOperation(Q.Kind, Q.Sources, Q.Dest, Q.OnDone, Q.Permanent, Q.OnItemDone);
end;

constructor TFileOpProgressForm.Create(AOwner: TComponent; AEngine: TFileOpEngine;
  AOnDone: TFileOpDoneProc; const AColors: TThemeColors);
begin
  inherited CreateNew(AOwner);
  FEngine := AEngine;
  FOnDone := AOnDone;
  FColors := AColors;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Caption := FileOpKindCaption(AEngine.Kind);
  Width := 780;
  Height := 460;
  Position := TFormPosition.Designed;
  FormStyle := TFormStyle.StayOnTop;
  FEngine.OnDone := EngineDone;
  FEngine.OnConflict :=
    procedure(const AInfo: TFileOpConflictInfo; AAnswer: TProc<TConflictChoice>)
    begin
      ShowConflict(AInfo, AAnswer);
    end;
  BuildUI;
  ApplyTheme(FColors);
  PlaceNearOwner;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 80;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  FEngine.ScanAsync;
end;

destructor TFileOpProgressForm.Destroy;
begin
  if GActive = Self then
    GActive := nil;
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  FireDone(False, 'Отменено');
  FConfDead := True;
  if Assigned(FConfPoll) then
    FConfPoll.Enabled := False;
  if Assigned(FEngine) then
  begin
    FEngine.OnDone := nil;
    FEngine.OnConflict := nil;
    FEngine.Cancel;
    FreeAndNil(FEngine);
  end;
  inherited;
end;

procedure TFileOpProgressForm.PlaceNearOwner;
var
  Own: TCommonCustomForm;
begin
  Own := nil;
  if Assigned(Owner) and (Owner is TCommonCustomForm) then
    Own := TCommonCustomForm(Owner)
  else if Assigned(Application.MainForm) then
    Own := Application.MainForm;
  if Own = nil then
  begin
    Position := TFormPosition.ScreenCenter;
    Exit;
  end;
  Left := Trunc(Own.Left + Max(20.0, (Own.Width - Width) / 2));
  Top := Trunc(Own.Top + Max(40.0, (Own.Height - Height) / 3));
end;

procedure TFileOpProgressForm.ApplyNativeChrome;
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

procedure TFileOpProgressForm.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TFileOpProgressForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TFileOpProgressForm.BuildUI;
var
  Footer, Bars, Row: TLayout;
  Track: TRectangle;

  function MkText(AParent: TFmxObject; ASize: Single; ABold: Boolean;
    AColor: TAlphaColor): TText;
  begin
    Result := TText.Create(Self);
    Result.Parent := AParent;
    Result.Align := TAlignLayout.Top;
    Result.HitTest := False;
    ApplyFluentText(Result, ASize, ABold);
    Result.TextSettings.FontColor := AColor;
    Result.TextSettings.HorzAlign := TTextAlign.Leading;
    Result.TextSettings.VertAlign := TTextAlign.Center;
    Result.TextSettings.WordWrap := False;
    Result.TextSettings.Trimming := TTextTrimming.Character;
    if AColor = FColors.SubTextColor then
      Result.Tag := 8
    else
      Result.Tag := 9;
  end;

  function MkTrack(AParent: TFmxObject; out AFill: TRectangle; out APct: TText): TRectangle;
  begin
    Result := TRectangle.Create(Self);
    Result.Parent := AParent;
    Result.Align := TAlignLayout.Top;
    Result.Height := 18;

    Result.XRadius := 9;
    Result.YRadius := 9;
    Result.Stroke.Kind := TBrushKind.None;
    Result.Fill.Color := FColors.ControlFill;
    Result.ClipChildren := True;
    Result.Tag := 4;
    AFill := TRectangle.Create(Self);
    AFill.Parent := Result;
    AFill.Align := TAlignLayout.Left;
    AFill.Width := 0;
    AFill.Stroke.Kind := TBrushKind.None;
    AFill.Fill.Color := FColors.SelectionColor;
    AFill.XRadius := 9;
    AFill.YRadius := 9;
    AFill.Tag := 3;
    APct := TText.Create(Self);
    APct.Parent := Result;
    APct.Align := TAlignLayout.Client;
    APct.HitTest := False;
    ApplyFluentText(APct, 11, True);
    APct.TextSettings.FontColor := FColors.TextColor;
    APct.TextSettings.HorzAlign := TTextAlign.Center;
    APct.Tag := 9;
     Result.Margins.Rect := TRectF.Create(0, 4, 0, 2);

  end;

begin
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := FColors.Background;

  FRoot := TRectangle.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;

  FRoot.XRadius := 12;
  FRoot.YRadius := 12;
  FRoot.Stroke.Kind := TBrushKind.Solid;
  FRoot.Stroke.Color := FColors.CardStroke;
  FRoot.Fill.Color := FColors.CardBackground;


  FTitle := MkText(FRoot, 16, True, FColors.TextColor);
  FTitle.Height := 0;
  FTitle.Visible := False;

  FFileName := MkText(FRoot, 13, True, FColors.TextColor);
  FFileName.Height := 22;
  FFileName.Text := '';

  FPaths := MkText(FRoot, 12, False, FColors.SubTextColor);
  FPaths.Height := 20;
  FPaths.Text := FEngine.Dest;

  FStatus := MkText(FRoot, 12, False, FColors.SubTextColor);
  FStatus.Height := 20;
  FStatus.Text := '';

  Bars := TLayout.Create(Self);
  Bars.Parent := FRoot;
  Bars.Align := TAlignLayout.Top;
  Bars.Height := 84;
  Bars.Margins.Top := 6;



  MkText(Bars, 11, False, FColors.SubTextColor).Height := 16;
  TText(Bars.Controls[Bars.ControlsCount - 1]).Text := 'Всего';
  TText(Bars.Controls[Bars.ControlsCount - 1]).Margins.Top := 8;
  FTotalTrack := MkTrack(Bars, FTotalFill, FTotalPct);

    MkText(Bars, 11, False, FColors.SubTextColor).Height := 16;
  TText(Bars.Controls[Bars.ControlsCount - 1]).Text := 'Текущий файл';
  FFileTrack := MkTrack(Bars, FFileFill, FFilePct);

    FRoot.Margins.Rect := TRectF.Create(16, 14, 16, 12);
    FRoot.Padding.Rect := TRectF.Create(16, 12, 16, 12);

  FStats := MkText(FRoot, 12, False, FColors.TextColor);
  FStats.Height := 24;
  FStats.Margins.Top := 4;
  FStats.Text := '';

  Footer := TLayout.Create(Self);
  Footer.Parent := FRoot;
  Footer.Align := TAlignLayout.Bottom;
  Footer.Height := 38;


  FBtnGo := CreateFluentButton(Self, Footer, '', 'Выполнить', fbkAccent, 118, GoClick);
  FBtnGo.Align := TAlignLayout.Right;
  FBtnGo.Margins.Right := 8;

  FBtnCancel := CreateFluentButton(Self, Footer, '', 'Отмена', fbkStandard, 92, CancelClick);
  FBtnCancel.Align := TAlignLayout.Right;
  FBtnCancel.Margins.Right := 8;


  FBtnBg := CreateFluentButton(Self, Footer, '', 'В фоне', fbkStandard, 92, BgClick);
  FBtnBg.Align := TAlignLayout.Right;
 
  FBtnSkip := CreateFluentButton(Self, Footer, '', 'Пропустить', fbkStandard, 110, SkipClick);
  FBtnSkip.Align := TAlignLayout.Right;
  FBtnSkip.Margins.Right := 8;
  FBtnPause := CreateFluentButton(Self, Footer, '', 'Пауза', fbkStandard, 88, PauseClick);
  FBtnPause.Align := TAlignLayout.Right;
  FBtnPause.Margins.Right := 8;


  FConflict := TRectangle.Create(Self);
  FConflict.Parent := FRoot;
  FConflict.Align := TAlignLayout.Contents;
  FConflict.XRadius := 10;
  FConflict.YRadius := 10;
  FConflict.Fill.Color := ThemeAdjustAlpha(FColors.Background, $F0);
  FConflict.Stroke.Kind := TBrushKind.None;
  FConflict.Padding.Rect := TRectF.Create(16, 12, 16, 12);
  FConflict.Visible := False;
  FConflict.HitTest := True;

  FConfTitle := MkText(FConflict, 15, True, FColors.TextColor);
  FConfTitle.Height := 24;
  FConfTitle.Text := 'Файл уже существует';

  FConfCards := TLayout.Create(Self);
  FConfCards.Parent := FConflict;
  FConfCards.Align := TAlignLayout.Client;
  FConfCards.Margins.Top := 6;
  FConfCards.Margins.Bottom := 4;

  BuildConflictCard(FConfCards, 'Новый (копируем)', FSrcCard, FSrcCap, FSrcNewer,
    FSrcImg, FSrcName, FSrcMeta);
  BuildConflictCard(FConfCards, 'Уже есть', FDstCard, FDstCap, FDstNewer,
    FDstImg, FDstName, FDstMeta);
  FSrcCard.Align := TAlignLayout.Left;
  FSrcCard.Width := 340;
  FSrcCard.Margins.Right := 8;
  FDstCard.Align := TAlignLayout.Client;
  FDstCard.Margins.Left := 8;

  FConfPoll := TTimer.Create(Self);
  FConfPoll.Interval := 80;
  FConfPoll.Enabled := False;
  FConfPoll.OnTimer := ConfPollTick;

  Track := TRectangle.Create(Self);
  Track.Parent := FConflict;
  Track.Align := TAlignLayout.Bottom;
  Track.Height := 84;
  Track.Stroke.Kind := TBrushKind.None;
  Track.Fill.Color := TAlphaColors.Null;

  Row := TLayout.Create(Self);
  Row.Parent := Track;
  Row.Align := TAlignLayout.Top;
  Row.Height := 38;
  FBtnConfNewer := CreateFluentButton(Self, Row, '', 'Новее', fbkStandard, 90, ConfClick);
  FBtnConfNewer.Align := TAlignLayout.Right;
  FBtnConfNewer.Margins.Right := 6;
  FBtnConfNewer.Tag := 6;
  FBtnConfAuto := CreateFluentButton(Self, Row, '', 'Автоимя', fbkStandard, 96, ConfClick);
  FBtnConfAuto.Align := TAlignLayout.Right;
  FBtnConfAuto.Margins.Right := 6;
  FBtnConfAuto.Tag := 3;
  FBtnConfSkip := CreateFluentButton(Self, Row, '', 'Пропустить', fbkStandard, 110, ConfClick);
  FBtnConfSkip.Align := TAlignLayout.Right;
  FBtnConfSkip.Margins.Right := 6;
  FBtnConfSkip.Tag := 2;
  FBtnConfReplace := CreateFluentButton(Self, Row, '', 'Заменить', fbkAccent, 100, ConfClick);
  FBtnConfReplace.Align := TAlignLayout.Right;
  FBtnConfReplace.Margins.Right := 6;
  FBtnConfReplace.Tag := 1;

  Row := TLayout.Create(Self);
  Row.Parent := Track;
  Row.Align := TAlignLayout.Top;
  Row.Height := 38;
  FBtnConfCancel := CreateFluentButton(Self, Row, '', 'Отмена', fbkStandard, 90, ConfClick);
  FBtnConfCancel.Align := TAlignLayout.Right;
  FBtnConfSkipAll := CreateFluentButton(Self, Row, '', 'Все пропустить', fbkStandard, 130, ConfClick);
  FBtnConfSkipAll.Align := TAlignLayout.Right;
  FBtnConfSkipAll.Margins.Right := 6;
  FBtnConfSkipAll.Tag := 5;
  FBtnConfAll := CreateFluentButton(Self, Row, '', 'Все заменить', fbkStandard, 120, ConfClick);
  FBtnConfAll.Align := TAlignLayout.Right;
  FBtnConfAll.Margins.Right := 6;
  FBtnConfAll.Tag := 4;

  FConfirm := TRectangle.Create(Self);
  FConfirm.Parent := FRoot;
  FConfirm.Align := TAlignLayout.Contents;
  FConfirm.XRadius := 10;
  FConfirm.YRadius := 10;
  FConfirm.Fill.Color := ThemeAdjustAlpha(FColors.Background, $F0);
  FConfirm.Stroke.Kind := TBrushKind.None;
  FConfirm.Padding.Rect := TRectF.Create(16, 16, 16, 16);
  FConfirm.Visible := False;
  FConfirm.HitTest := True;
  FConfAskTitle := MkText(FConfirm, 15, True, FColors.TextColor);
  FConfAskTitle.Height := 28;
  FConfAskTitle.Text := 'Удалить объекты?';
  FConfAskText := MkText(FConfirm, 12, False, FColors.SubTextColor);
  FConfAskText.Height := 48;
  FConfAskText.TextSettings.WordWrap := True;
  Track := TRectangle.Create(Self);
  Track.Parent := FConfirm;
  Track.Align := TAlignLayout.Bottom;
  Track.Height := 42;
  Track.Stroke.Kind := TBrushKind.None;
  Track.Fill.Color := TAlphaColors.Null;
  ;
  with CreateFluentButton(Self, Track, '', 'Удалить', fbkAccent, 110, ConfirmYesClick) do
  begin
    Align := TAlignLayout.Right;
    Margins.Right := 8;
  end;
  CreateFluentButton(Self, Track, '', 'Отмена', fbkStandard, 100,
  ConfirmNoClick).Align := TAlignLayout.Right

end;

procedure TFileOpProgressForm.PaintBars(const P: TFileOpProgress);
var
  W, FileR, TotR: Single;
begin
  W := FFileTrack.Width;
  if W < 8 then
    Exit;
  if P.FileBytesTotal > 0 then
    FileR := P.FileBytesDone / P.FileBytesTotal
  else
    FileR := 0;
  if P.TotalBytesTotal > 0 then
    TotR := P.TotalBytesDone / P.TotalBytesTotal
  else if P.FilesTotal > 0 then
    TotR := P.FilesDone / P.FilesTotal
  else
    TotR := 0;
  if FileR < 0 then FileR := 0;
  if FileR > 1 then FileR := 1;
  if TotR < 0 then TotR := 0;
  if TotR > 1 then TotR := 1;
  FFileFill.Width := Max(0, FileR * W);
  FTotalFill.Width := Max(0, TotR * W);
  FFilePct.Text := Format('%d%%', [Round(FileR * 100)]);
  FTotalPct.Text := Format('%d%%', [Round(TotR * 100)]);
end;

procedure TFileOpProgressForm.SyncButtons(const P: TFileOpProgress);
var
  Ready, Running, Paused: Boolean;
begin
  Ready := P.Phase = opReady;
  Running := P.Phase = opRun;
  Paused := P.Phase = opPaused;
  FBtnGo.Enabled := Ready or Paused;
  FBtnGo.HitTest := FBtnGo.Enabled;
  if FBtnGo.Enabled then FBtnGo.Opacity := 1 else FBtnGo.Opacity := 0.4;
  FBtnPause.Enabled := Running;
  FBtnPause.HitTest := Running;
  if Running then FBtnPause.Opacity := 1 else FBtnPause.Opacity := 0.4;
  FBtnSkip.Enabled := Running;
  FBtnSkip.HitTest := Running;
  if Running then FBtnSkip.Opacity := 1 else FBtnSkip.Opacity := 0.4;
  FBtnCancel.Enabled := not FFinished;
end;

procedure TFileOpProgressForm.Tick(Sender: TObject);
var
  P: TFileOpProgress;
  Q: Integer;
  St: string;
begin
  if FEngine = nil then
    Exit;
  P := FEngine.GetProgress;
  if P.FileName <> '' then
    FFileName.Text := P.FileName
  else
    FFileName.Text := '';
  if P.SourcePath <> '' then
    FPaths.Text := P.SourcePath + '  →  ' + P.DestPath
  else if FEngine.Dest <> '' then
    FPaths.Text := FEngine.Dest;
  St := P.Status;
  if SameText(St, FileOpKindCaption(P.Kind)) or
     SameText(St, 'Подсчёт файлов…') or StartsText('Подготов', St) then
    St := '';
  if Assigned(GQueue) and (GQueue.Count > 0) then
  begin
    Q := GQueue.Count;
    if St = '' then
      St := Format('в очереди %d · далее: %s',
        [Q, FileOpKindCaption(GQueue[0].Kind)])
    else
      St := St + Format('  ·  в очереди %d · далее: %s',
        [Q, FileOpKindCaption(GQueue[0].Kind)]);
  end;
  FStatus.Text := St;
  FStats.Text := Format('%d / %d   ·   %s / %s   ·   %s   ·   осталось %s',
    [P.FilesDone, P.FilesTotal, FormatOpBytes(P.TotalBytesDone),
     FormatOpBytes(P.TotalBytesTotal), FormatOpSpeed(P.SpeedBps),
     FormatOpEta(P.RemainingSec)]);
  if P.Skipped > 0 then
    FStats.Text := FStats.Text + Format('   ·   пропуск %d', [P.Skipped]);
  if P.Unchanged > 0 then
    FStats.Text := FStats.Text + Format('   ·   без изменений %d', [P.Unchanged]);
  if P.Errors > 0 then
    FStats.Text := FStats.Text + Format('   ·   ошибок %d', [P.Errors]);
  PaintBars(P);
  SyncButtons(P);
  if (P.Phase = opReady) and (P.Kind = okDelete) and not FDeleteAsked then
    ShowDeleteConfirm(P);
  if FKeepOpen then
  begin
    FBtnGo.Enabled := True;
    FBtnGo.HitTest := True;
    FBtnGo.Opacity := 1;
    FBtnGo.SetCaption('Закрыть');
  end
  else if P.Phase in [opDone, opCancel, opFail] then
    FBtnGo.Enabled := False;
end;

procedure TFileOpProgressForm.GoClick(Sender: TObject);
var
  P: TFileOpProgress;
begin
  if FKeepOpen then
  begin
    if GActive = Self then
      GActive := nil;
    PumpQueue;
    Hide;
    Close;
    Exit;
  end;
  if FEngine = nil then
    Exit;
  if FConfirm.Visible then
  begin
    ConfirmYesClick(nil);
    Exit;
  end;
  P := FEngine.GetProgress;
  if P.Phase = opReady then
    FEngine.Start
  else if P.Phase = opPaused then
    FEngine.Resume;
end;

procedure TFileOpProgressForm.PauseClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.Pause;
end;

procedure TFileOpProgressForm.SkipClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.SkipCurrent;
end;

procedure TFileOpProgressForm.CancelClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.Cancel;
end;

procedure TFileOpProgressForm.BgClick(Sender: TObject);
var
  P: TFileOpProgress;
begin
  FBackground := True;
  if Assigned(FEngine) then
  begin
    P := FEngine.GetProgress;
    if P.Phase = opReady then
      FEngine.Start;
  end;
  Hide;
end;

procedure TFileOpProgressForm.BuildConflictCard(AParent: TFmxObject;
  const ACaption: string; out ACard: TRectangle; out ACap, ANewer: TText;
  out AImg: TImage; out AName, AMeta: TText);
var
  Head: TLayout;
begin
  ACard := TRectangle.Create(Self);
  ACard.Parent := AParent;
  ACard.XRadius := 10;
  ACard.YRadius := 10;
  ACard.Stroke.Kind := TBrushKind.Solid;
  ACard.Stroke.Thickness := 1;
  ACard.Stroke.Color := FColors.CardStroke;
  ACard.Fill.Kind := TBrushKind.Solid;
  ACard.Fill.Color := FColors.CardBackground;
  ACard.Padding.Rect := TRectF.Create(12, 8, 12, 8);

  Head := TLayout.Create(Self);
  Head.Parent := ACard;
  Head.Align := TAlignLayout.Top;
  Head.Height := 20;

  ACap := TText.Create(Self);
  ACap.Parent := Head;
  ACap.Align := TAlignLayout.Client;
  ACap.HitTest := False;
  ApplyFluentText(ACap, 12, True);
  ACap.TextSettings.FontColor := FColors.SubTextColor;
  ACap.TextSettings.HorzAlign := TTextAlign.Leading;
  ACap.Text := ACaption;

  ANewer := TText.Create(Self);
  ANewer.Parent := Head;
  ANewer.Align := TAlignLayout.Right;
  ANewer.Width := 56;
  ANewer.HitTest := False;
  ApplyFluentText(ANewer, 11, True);
  ANewer.TextSettings.FontColor := FColors.SelectionColor;
  ANewer.TextSettings.HorzAlign := TTextAlign.Trailing;
  ANewer.Text := 'новее';
  ANewer.Visible := False;

  AMeta := TText.Create(Self);
  AMeta.Parent := ACard;
  AMeta.Align := TAlignLayout.Top;
  AMeta.Height := 36;
  AMeta.HitTest := False;
  ApplyFluentText(AMeta, 11, False);
  AMeta.TextSettings.FontColor := FColors.SubTextColor;
  AMeta.TextSettings.HorzAlign := TTextAlign.Leading;
  AMeta.TextSettings.WordWrap := True;
  AMeta.Margins.Top := 20;


  AImg := TImage.Create(Self);
  AImg.Parent := ACard;
  AImg.Align := TAlignLayout.Top;
  AImg.Height := 88;
  AImg.Margins.Top := 6;
  AImg.Margins.Bottom := 4;
  AImg.WrapMode := TImageWrapMode.Fit;
  AImg.HitTest := False;

  AName := TText.Create(Self);
  AName.Parent := ACard;
  AName.Align := TAlignLayout.Top;
  AName.Height := 22;
  AName.HitTest := False;
  ApplyFluentText(AName, 13, True);
  AName.TextSettings.FontColor := FColors.TextColor;
  AName.TextSettings.HorzAlign := TTextAlign.Leading;
  AName.TextSettings.Trimming := TTextTrimming.Character;
  AName.TextSettings.WordWrap := False;

  AImg.Margins.Rect := TRectF.Create(0, 40, 0, 4);
end;

procedure TFileOpProgressForm.SetConfFallbackIcon(const APath: string;
  AIsDir: Boolean; AImg: TImage);
var
  Key: string;
  Bmp: FMX.Graphics.TBitmap;
begin
  if AImg = nil then
    Exit;
  Bmp := nil;
  if AIsDir then
    Key := '#dir'
  else
    Key := ExtractFileExt(APath);
  GetTypeIconBitmap(Key, AIsDir, Bmp);
  try
    if Assigned(Bmp) then
      AImg.Bitmap.Assign(Bmp)
    else
      AImg.Bitmap.Assign(nil);
  finally
    Bmp.Free;
  end;
end;

procedure TFileOpProgressForm.LoadConfThumb(const APath: string; AIsDir: Boolean;
  AImg: TImage);
var
  Cached: FMX.Graphics.TBitmap;
  Path: string;
  Img: TImage;
  Gen: Integer;
begin
  SetConfFallbackIcon(APath, AIsDir, AImg);
  if (APath = '') or AIsDir or (GlobalThumbCache = nil) or (AImg = nil) then
    Exit;
  if GlobalThumbCache.TryGet(APath, Cached) and Assigned(Cached) then
  begin
    AImg.Bitmap.Assign(Cached);
    Exit;
  end;
  Path := APath;
  Img := AImg;
  Gen := FConfGen;
  GlobalThumbCache.RequestAsync(APath, 128,
    procedure(const AReadyPath: string; ABitmap: FMX.Graphics.TBitmap)
    begin
      if FConfDead or (Gen <> FConfGen) then
        Exit;
      if Assigned(ABitmap) and SameText(AReadyPath, Path) and Assigned(Img) then
        Img.Bitmap.Assign(ABitmap);
    end);
  if Assigned(FConfPoll) then
  begin
    FConfPoll.Tag := 0;
    FConfPoll.Enabled := True;
  end;
end;

procedure TFileOpProgressForm.ConfPollTick(Sender: TObject);
var
  Bmp: FMX.Graphics.TBitmap;
  Src, Dst: string;
begin
  if FConfDead or not FConflict.Visible then
  begin
    FConfPoll.Enabled := False;
    Exit;
  end;
  FConfPoll.Tag := FConfPoll.Tag + 1;
  if GlobalThumbCache <> nil then
  begin
    Src := '';
    Dst := '';
    if Assigned(FSrcName) then
      Src := string(FSrcName.TagString);
    if Assigned(FDstName) then
      Dst := string(FDstName.TagString);
    if (Src <> '') and GlobalThumbCache.TryGet(Src, Bmp) and Assigned(Bmp) then
      FSrcImg.Bitmap.Assign(Bmp);
    if (Dst <> '') and GlobalThumbCache.TryGet(Dst, Bmp) and Assigned(Bmp) then
      FDstImg.Bitmap.Assign(Bmp);
  end;
  if FConfPoll.Tag >= 15 then
    FConfPoll.Enabled := False;
end;

procedure TFileOpProgressForm.ShowConflict(const AInfo: TFileOpConflictInfo;
  AAnswer: TProc<TConflictChoice>);
var
  Same, Clash, SrcDir, DstDir: Boolean;
  SrcNewer, DstNewer: Boolean;
  Meta: string;
begin
  FAnswer := AAnswer;
  Inc(FConfGen);
  Clash := AInfo.TypeClash;
  if Clash then
    FConfTitle.Text := 'Имя занято другим типом'
  else
    FConfTitle.Text := 'Файл уже существует';

  SrcDir := TDirectory.Exists(AInfo.Source) and not TFile.Exists(AInfo.Source);
  DstDir := TDirectory.Exists(AInfo.Dest) and not TFile.Exists(AInfo.Dest);

  FSrcName.Text := ExtractFileName(ExcludeTrailingPathDelimiter(AInfo.Source));
  FDstName.Text := ExtractFileName(ExcludeTrailingPathDelimiter(AInfo.Dest));
  FSrcName.TagString := AInfo.Source;
  FDstName.TagString := AInfo.Dest;

  Meta := '';
  if AInfo.SrcSize > 0 then
    Meta := FormatOpBytes(AInfo.SrcSize);
  if AInfo.SrcTime > 0 then
  begin
    if Meta <> '' then
      Meta := Meta + '  ·  ';
    Meta := Meta + FormatDateTime('dd.mm.yyyy HH:nn', AInfo.SrcTime);
  end;
  if Meta = '' then
    Meta := '—';
  FSrcMeta.Text := Meta;

  Meta := '';
  if AInfo.DstSize > 0 then
    Meta := FormatOpBytes(AInfo.DstSize);
  if AInfo.DstTime > 0 then
  begin
    if Meta <> '' then
      Meta := Meta + '  ·  ';
    Meta := Meta + FormatDateTime('dd.mm.yyyy HH:nn', AInfo.DstTime);
  end;
  Same := (not Clash) and (AInfo.SrcSize = AInfo.DstSize) and (AInfo.SrcSize >= 0) and
    (Abs(AInfo.SrcTime - AInfo.DstTime) <= 2 / SecsPerDay);
  if Same then
  begin
    if Meta <> '' then
      Meta := Meta + sLineBreak;
    Meta := Meta + 'вероятно тот же файл';
  end;
  if Meta = '' then
    Meta := '—';
  FDstMeta.Text := Meta;

  SrcNewer := (not Clash) and (AInfo.SrcTime > 0) and (AInfo.DstTime > 0) and
    (AInfo.SrcTime > AInfo.DstTime);
  DstNewer := (not Clash) and (AInfo.SrcTime > 0) and (AInfo.DstTime > 0) and
    (AInfo.DstTime > AInfo.SrcTime);
  FSrcNewer.Visible := SrcNewer;
  FDstNewer.Visible := DstNewer;
  if SrcNewer then
  begin
    FSrcCard.Stroke.Color := FColors.SelectionColor;
    FSrcCard.Stroke.Thickness := 2;
  end
  else
  begin
    FSrcCard.Stroke.Color := FColors.CardStroke;
    FSrcCard.Stroke.Thickness := 1;
  end;
  if DstNewer then
  begin
    FDstCard.Stroke.Color := FColors.SelectionColor;
    FDstCard.Stroke.Thickness := 2;
  end
  else
  begin
    FDstCard.Stroke.Color := FColors.CardStroke;
    FDstCard.Stroke.Thickness := 1;
  end;

  LoadConfThumb(AInfo.Source, SrcDir, FSrcImg);
  LoadConfThumb(AInfo.Dest, DstDir, FDstImg);

  if Assigned(FBtnConfReplace) then
    FBtnConfReplace.Visible := not Clash;
  if Assigned(FBtnConfAll) then
    FBtnConfAll.Visible := not Clash;
  if Assigned(FBtnConfNewer) then
    FBtnConfNewer.Visible := not Clash;
  FConflict.Visible := True;
  FConflict.BringToFront;
  if FBackground then
  begin
    FBackground := False;
    Show;
  end;
end;

procedure TFileOpProgressForm.HideConflict;
begin
  if Assigned(FConfPoll) then
    FConfPoll.Enabled := False;
  Inc(FConfGen);
  FConflict.Visible := False;
  FAnswer := nil;
  if Assigned(FSrcImg) then
    FSrcImg.Bitmap.Assign(nil);
  if Assigned(FDstImg) then
    FDstImg.Bitmap.Assign(nil);
end;

procedure TFileOpProgressForm.ShowDeleteConfirm(const P: TFileOpProgress);
var
  N: Integer;
  Place: string;
begin
  if FConfirm.Visible or FDeleteAsked then
    Exit;
  N := P.FilesTotal;
  if N <= 0 then
    N := 1;
  if FEngine.Permanent then
  begin
    FConfAskTitle.Text := Format('Удалить навсегда %d объектов?', [N]);
    Place := 'Файлы будут уничтожены без Корзины.';
  end
  else
  begin
    FConfAskTitle.Text := Format('Удалить %d объектов в Корзину?', [N]);
    Place := 'Можно будет восстановить из Корзины.';
  end;
  if P.TotalBytesTotal > 0 then
    Place := Place + '  ' + FormatOpBytes(P.TotalBytesTotal);
  FConfAskText.Text := Place;
  FConfirm.Visible := True;
  FConfirm.BringToFront;
end;

procedure TFileOpProgressForm.HideDeleteConfirm;
begin
  FConfirm.Visible := False;
end;

procedure TFileOpProgressForm.ConfirmYesClick(Sender: TObject);
begin
  FDeleteAsked := True;
  HideDeleteConfirm;
  if Assigned(FEngine) then
    FEngine.Start;
end;

procedure TFileOpProgressForm.ConfirmNoClick(Sender: TObject);
begin
  FDeleteAsked := True;
  HideDeleteConfirm;
  if Assigned(FEngine) then
    FEngine.Cancel;
end;

procedure TFileOpProgressForm.ConfClick(Sender: TObject);
var
  Choice: TConflictChoice;
  Tag: Integer;
begin
  Tag := 0;
  if Sender is TFmxObject then
    Tag := TFmxObject(Sender).Tag;
  case Tag of
    1: Choice := ccOverwrite;
    2: Choice := ccSkip;
    3: Choice := ccAutoRename;
    4: Choice := ccOverwriteAll;
    5: Choice := ccSkipAll;
    6: Choice := ccOverwriteOlder;
  else
    Choice := ccCancel;
  end;
  if Assigned(FAnswer) then
    FAnswer(Choice);
  HideConflict;
end;

procedure TFileOpProgressForm.FireDone(Success: Boolean; const ErrorMsg: string);
var
  Cb: TFileOpDoneProc;
begin
  Cb := FOnDone;
  FOnDone := nil;
  if Assigned(Cb) then
    Cb(Success, ErrorMsg);
end;

procedure TFileOpProgressForm.ThemeTree(AObj: TFmxObject; const AColors: TThemeColors);
var
  I: Integer;
  Ch: TFmxObject;
begin
  if AObj = nil then
    Exit;
  if AObj is TFluentButton then
    TFluentButton(AObj).ApplyTheme(AColors)
  else if (AObj is TRectangle) and (TRectangle(AObj).Tag = 3) then
    TRectangle(AObj).Fill.Color := AColors.SelectionColor
  else if (AObj is TRectangle) and (TRectangle(AObj).Tag = 4) then
    TRectangle(AObj).Fill.Color := AColors.ControlFill
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

procedure TFileOpProgressForm.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  if Assigned(FRoot) then
  begin
    FRoot.Fill.Color := AColors.CardBackground;
    FRoot.Stroke.Color := AColors.CardStroke;
  end;
  if Assigned(FConflict) then
    FConflict.Fill.Color := ThemeAdjustAlpha(AColors.Background, $F0);
  if Assigned(FSrcCard) then
  begin
    FSrcCard.Fill.Color := AColors.CardBackground;
    FSrcCard.Stroke.Color := AColors.CardStroke;
  end;
  if Assigned(FDstCard) then
  begin
    FDstCard.Fill.Color := AColors.CardBackground;
    FDstCard.Stroke.Color := AColors.CardStroke;
  end;
  if Assigned(FConfirm) then
    FConfirm.Fill.Color := ThemeAdjustAlpha(AColors.Background, $F0);
  ApplyNativeChrome;
  ThemeTree(FRoot, AColors);




end;

procedure TFileOpProgressForm.EngineDone(Success: Boolean; const ErrorMsg: string);
begin
  FFinished := True;
  FireDone(Success, ErrorMsg);
  if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') and not FBackground then
    FStatus.Text := ErrorMsg;
  if FBackground or Success or (ErrorMsg = 'Отменено') then
  begin
    if Assigned(FTimer) then
      FTimer.Enabled := False;
    if GActive = Self then
      GActive := nil;
    PumpQueue;
    Hide;
    Close;
  end
  else
  begin
    FKeepOpen := True;
    FBtnGo.SetCaption('Закрыть');
    FBtnGo.Enabled := True;
    FBtnGo.HitTest := True;
    FBtnGo.Opacity := 1;
    FBtnPause.Enabled := False;
    FBtnSkip.Enabled := False;
  end;
end;

procedure TFileOpProgressForm.DoClose(var CloseAction: TCloseAction);
begin
  if not FFinished then
  begin
    FFinished := True;
    if Assigned(FEngine) then
    begin
      FEngine.OnDone := nil;
      FEngine.Cancel;
    end;
    FireDone(False, 'Отменено');
  end;
  CloseAction := TCloseAction.caFree;
  inherited;
end;

procedure TFileOpProgressForm.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
var
  Ch: Char;
begin
  inherited;
  if FKeepOpen then
  begin
    if (Key = vkReturn) or (Key = vkEscape) then
    begin
      GoClick(nil);
      Key := 0;
    end;
    Exit;
  end;
  if FConfirm.Visible then
  begin
    if Key = vkEscape then
      ConfirmNoClick(nil)
    else if Key = vkReturn then
      ConfirmYesClick(nil);
    Key := 0;
    Exit;
  end;
  if FConflict.Visible then
  begin
    Ch := UpCase(KeyChar);
    if Key = vkEscape then
      ConfClick(FBtnConfCancel)
    else if Key = vkReturn then
      ConfClick(FBtnConfSkip)
    else if (Ch = 'R') or (KeyChar = 'к') or (KeyChar = 'К') then
      ConfClick(FBtnConfReplace)
    else if (Ch = 'S') or (KeyChar = 'ы') or (KeyChar = 'Ы') then
      ConfClick(FBtnConfSkip)
    else if (Ch = 'A') or (KeyChar = 'ф') or (KeyChar = 'Ф') then
      ConfClick(FBtnConfAuto)
    else if (Ch = 'N') or (KeyChar = 'т') or (KeyChar = 'Т') then
      ConfClick(FBtnConfNewer);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if Key = vkEscape then
  begin
    CancelClick(nil);
    Key := 0;
  end
  else if (Key = vkSpace) or (Key = vkPause) then
  begin
    if FEngine.GetProgress.Phase = opRun then
      PauseClick(nil)
    else
      GoClick(nil);
    Key := 0;
  end
  else if (Key = vkReturn) then
  begin
    GoClick(nil);
    Key := 0;
  end;
end;

initialization
  GQueue := nil;
  GActive := nil;

finalization
  FreeAndNil(GQueue);

end.
