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
  uThemeManager, uFluentChrome, uFluentComboBox, uFileOps, uFileOpEngine, uAppSettings,
  uThumbCache, UCoreEngine;

procedure RunVibeOperation(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; AOnDone: TFileOpDoneProc; APermanent: Boolean = False;
  AOnItemDone: TFileOpItemDoneProc = nil);
function RestoreVibeBackground(AKind: TFileOpKind): Boolean;

function FileOpKindIcon(AKind: TFileOpKind): string;

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
    FToPath: TText;
    FCurLbl: TText;
    FAllLbl: TText;
    FStatus: TText;
    FStats: TText;
    FBody: TLayout;
    FFileTrack, FFileFill: TRectangle;
    FTotalTrack, FTotalFill: TRectangle;
    FFilePct, FTotalPct: TText;
    FBtnGo, FBtnPause, FBtnSkip, FBtnCancel, FBtnBg: TFluentButton;
    FKeepOpen: Boolean;
    FDeleteAsked: Boolean;
    FJobId: Integer;

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
    FConfBody: TLayout;
    FConfIcon: TText;
    FConfAskTitle, FConfAskText: TText;
    FConfFromCap, FConfFromPath: TText;
    FConfToCap, FConfToPath: TText;
    FConfMore: TText;
    FConfRowHost: array[0..7] of TLayout;
    FConfRowIco: array[0..7] of TImage;
    FConfRowName: array[0..7] of TText;
    FArchCombo: TFluentComboBox;
    FBtnConfirmYes: TFluentButton;
    FArchStem: string;
    FArchLock: Boolean;
    FArchKinds: array[0..4] of Integer;
    FArchKindCount: Integer;
    FConfExtra: Integer;

    procedure BuildUI;
    procedure BodyResize(Sender: TObject);
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
    procedure ShowConfirm(const P: TFileOpProgress);
    procedure HideDeleteConfirm;
    procedure LayoutConfirm;
    procedure ConfBodyResize(Sender: TObject);
    procedure ArchKindChanged(Sender: TObject);
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
  System.Math, System.StrUtils, System.DateUtils, FMX.Dialogs, uFileModel,
  uArchiveEngine;

type
  TFileOpJob = class
    Id: Integer;
    Kind: TFileOpKind;
    Sources: TArray<string>;
    Dest: string;
    Permanent: Boolean;
    OnDone: TFileOpDoneProc;
    OnItemDone: TFileOpItemDoneProc;
    Engine: TFileOpEngine;
    Form: TFileOpProgressForm;
    State: TFileOpJobState;
    Background: Boolean;
    Vols: TArray<string>;
    ErrorMsg: string;
    Progress: TFileOpProgress;
    DoneAt: TDateTime;
  end;

var
  GJobs: TObjectList<TFileOpJob>;
  GNextId: Integer;
  GBindJobId: Integer;
  GBindJob: TFileOpJob;
  GHubSpin: Single;

function OpVolumeKey(const APath: string): string;
var
  Arch, Inner, S: string;
  I, N: Integer;
begin
  Result := '';
  if APath = '' then
    Exit;
  if SplitArchivePath(APath, Arch, Inner) and (Arch <> '') then
    Exit('arc:' + LowerCase(ExcludeTrailingPathDelimiter(Arch)));
  S := APath;
  if StartsText('\\', S) or StartsText('//', S) then
  begin
    S := StringReplace(S, '/', '\', [rfReplaceAll]);
    N := 0;
    for I := 3 to Length(S) do
      if S[I] = '\' then
      begin
        Inc(N);
        if N = 2 then
          Exit(LowerCase(Copy(S, 1, I - 1)));
      end;
    Exit(LowerCase(ExcludeTrailingPathDelimiter(S)));
  end;
  Result := UpperCase(ExtractFileDrive(S));
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
end;

function HubFind(AId: Integer): TFileOpJob;
var
  I: Integer;
begin
  Result := nil;
  if GJobs = nil then
    Exit;
  for I := 0 to GJobs.Count - 1 do
    if GJobs[I].Id = AId then
      Exit(GJobs[I]);
end;

procedure HubTouch;
begin
  NotifyFileOpHubChanged;
end;

function HubHoldsSlot(J: TFileOpJob): Boolean;
begin
  Result := Assigned(J) and
    (J.State in [jsRunning, jsPaused, jsNeedAnswer, jsBackground]);
end;

function HubActiveCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  if GJobs = nil then
    Exit;
  for I := 0 to GJobs.Count - 1 do
    if HubHoldsSlot(GJobs[I]) then
      Inc(Result);
end;

function HubHasVol(J: TFileOpJob; const AKey: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (J = nil) or (AKey = '') then
    Exit;
  for I := 0 to High(J.Vols) do
    if SameText(J.Vols[I], AKey) then
      Exit(True);
end;

procedure HubFillVolumes(J: TFileOpJob);
var
  L: TStringList;
  S, K: string;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.CaseSensitive := False;
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    if (J.Kind = okArchive) and (J.Dest <> '') then
      L.Add('arc:' + LowerCase(ExcludeTrailingPathDelimiter(J.Dest)));
    if J.Dest <> '' then
    begin
      K := OpVolumeKey(J.Dest);
      if K <> '' then
        L.Add(K);
    end;
    for S in J.Sources do
    begin
      K := OpVolumeKey(S);
      if K <> '' then
        L.Add(K);
    end;
    if (L.Count = 0) and (Length(J.Sources) > 0) then
    begin
      K := OpVolumeKey(J.Sources[0]);
      if K <> '' then
        L.Add(K);
    end;
    SetLength(J.Vols, L.Count);
    for I := 0 to L.Count - 1 do
      J.Vols[I] := L[I];
  finally
    L.Free;
  end;
end;

function HubVolumesFree(J: TFileOpJob): Boolean;
var
  I, K: Integer;
  Other: TFileOpJob;
begin
  Result := True;
  if (GJobs = nil) or (J = nil) then
    Exit;
  for I := 0 to GJobs.Count - 1 do
  begin
    Other := GJobs[I];
    if (Other = J) or not HubHoldsSlot(Other) then
      Continue;
    for K := 0 to High(J.Vols) do
      if HubHasVol(Other, J.Vols[K]) then
        Exit(False);
  end;
end;

procedure HubLaunch(J: TFileOpJob); forward;
procedure HubPromote; forward;

procedure HubPromote;
var
  I: Integer;
begin
  if GJobs = nil then
    Exit;
  for I := 0 to GJobs.Count - 1 do
  begin
    if HubActiveCount >= 2 then
      Exit;
    if (GJobs[I].State = jsQueued) and HubVolumesFree(GJobs[I]) then
      HubLaunch(GJobs[I]);
  end;
end;

procedure HubUnlinkForm(AForm: TFileOpProgressForm);
var
  I: Integer;
  J: TFileOpJob;
begin
  if (GJobs = nil) or (AForm = nil) then
    Exit;
  for I := 0 to GJobs.Count - 1 do
  begin
    J := GJobs[I];
    if (J.Form = AForm) or ((AForm.FJobId <> 0) and (J.Id = AForm.FJobId)) then
    begin
      if J.Form = AForm then
        J.Form := nil;
      if J.Engine = AForm.FEngine then
        J.Engine := nil;
    end;
  end;
end;

procedure FireJobDone(J: TFileOpJob; AOk: Boolean; const AErr: string);
var
  Cb: TFileOpDoneProc;
begin
  if J = nil then
    Exit;
  Cb := J.OnDone;
  J.OnDone := nil;
  if Assigned(Cb) then
    Cb(AOk, AErr);
end;

procedure HubLaunch(J: TFileOpJob);
var
  Eng: TFileOpEngine;
  Frm: TFileOpProgressForm;
  Colors: TThemeColors;
  Kind: TFileOpKind;
  Perm: Boolean;
begin
  if (J = nil) or (J.State <> jsQueued) then
    Exit;
  Kind := J.Kind;
  Perm := J.Permanent;
  J.State := jsRunning;
  J.Background := False;
  Colors := GetThemeColors(ActiveAppTheme);
  Eng := TFileOpEngine.Create(Kind, J.Sources, J.Dest, Perm);
  Eng.OnItemDone := J.OnItemDone;
  Eng.SpecialCopy :=
    procedure(ASrc, ADst: string)
    begin
      if Kind = okDelete then
        DeletePathSync(ASrc, Perm)
      else if Kind <> okArchive then
        CopyPathSync(ASrc, ADst);
    end;
  GBindJobId := J.Id;
  GBindJob := J;
  try
    Frm := TFileOpProgressForm.Create(Application, Eng, J.OnDone, Colors);
  finally
    GBindJobId := 0;
    GBindJob := nil;
  end;
  J.OnDone := nil;
  J.Engine := Eng;
  J.Form := Frm;
  Frm.Show;
end;

function JobPercent(const P: TFileOpProgress; out AIndet: Boolean): Integer;
begin
  AIndet := False;
  if P.TotalBytesTotal > 0 then
    Result := EnsureRange(Round(100.0 * P.TotalBytesDone / P.TotalBytesTotal), 0, 100)
  else if P.FilesTotal > 0 then
    Result := EnsureRange(Round(100.0 * P.FilesDone / P.FilesTotal), 0, 100)
  else
  begin
    Result := 0;
    AIndet := P.Phase in [opIdle, opScan, opReady];
  end;
end;

function JobDetailText(J: TFileOpJob): string;
var
  NamePart, DestPart: string;
begin
  if J.State = jsQueued then
    Exit('ждёт');
  if J.State = jsFailed then
  begin
    if J.ErrorMsg <> '' then
      Exit(J.ErrorMsg)
    else
      Exit('Ошибка');
  end;
  if J.State = jsDone then
    Exit('Готово');
  if J.State = jsCancelled then
    Exit('Отменено');
  if J.State = jsNeedAnswer then
    Exit('Нужен ответ');
  if (J.State = jsBackground) and Assigned(J.Form) and
     Assigned(J.Form.FConfirm) and J.Form.FConfirm.Visible and not J.Form.FDeleteAsked then
    Exit('ждёт подтверждения');
  if J.Progress.FileName <> '' then
    NamePart := J.Progress.FileName
  else if Length(J.Sources) = 1 then
    NamePart := ExtractFileName(ExcludeTrailingPathDelimiter(J.Sources[0]))
  else
    NamePart := Format('%d файлов', [Length(J.Sources)]);
  DestPart := '';
  if J.Dest <> '' then
  begin
    DestPart := ExtractFileName(ExcludeTrailingPathDelimiter(J.Dest));
    if DestPart = '' then
      DestPart := ExcludeTrailingPathDelimiter(J.Dest);
  end;
  if DestPart <> '' then
    Result := NamePart + ' · ' + DestPart
  else
    Result := NamePart;
end;

function JobTitleText(J: TFileOpJob): string;
begin
  case J.State of
    jsQueued: Result := 'В очереди';
    jsNeedAnswer: Result := 'Нужен ответ';
    jsFailed: Result := 'Ошибка';
    jsDone: Result := 'Готово';
    jsCancelled: Result := 'Отменено';
  else
    Result := FileOpKindCaption(J.Kind);
  end;
end;

function JobRank(AState: TFileOpJobState): Integer;
begin
  case AState of
    jsNeedAnswer, jsFailed: Result := 0;
    jsRunning, jsPaused, jsBackground: Result := 1;
    jsQueued: Result := 2;
  else
    Result := 3;
  end;
end;

procedure HubOrdered(out AList: TArray<TFileOpJob>);
var
  I, J, N: Integer;
  Tmp: TFileOpJob;
begin
  SetLength(AList, 0);
  if GJobs = nil then
    Exit;
  N := GJobs.Count;
  SetLength(AList, N);
  for I := 0 to N - 1 do
    AList[I] := GJobs[I];
  for I := 1 to N - 1 do
  begin
    Tmp := AList[I];
    J := I;
    while (J > 0) and
      ((JobRank(AList[J - 1].State) > JobRank(Tmp.State)) or
       ((JobRank(AList[J - 1].State) = JobRank(Tmp.State)) and
        (AList[J - 1].Id > Tmp.Id))) do
    begin
      AList[J] := AList[J - 1];
      Dec(J);
    end;
    AList[J] := Tmp;
  end;
end;

function MakeView(J: TFileOpJob): TFileOpJobView;
var
  Indet: Boolean;
begin
  Result.Id := J.Id;
  Result.Kind := J.Kind;
  Result.State := J.State;
  Result.Title := JobTitleText(J);
  Result.Detail := JobDetailText(J);
  Result.IconText := FileOpKindIcon(J.Kind);
  Result.Percent := JobPercent(J.Progress, Indet);
  Result.Indeterminate := Indet and
    (J.State in [jsRunning, jsPaused, jsBackground, jsNeedAnswer]);
  Result.Danger := J.State in [jsNeedAnswer, jsFailed];
  if J.State = jsQueued then
    Result.PercentText := 'ждет'
  else if J.State = jsDone then
    Result.PercentText := ''
  else if J.State = jsFailed then
    Result.PercentText := ''
  else if Result.Indeterminate then
    Result.PercentText := '…'
  else
    Result.PercentText := Format('%d%%', [Result.Percent]);
end;

function FileOpKindIcon(AKind: TFileOpKind): string;
begin
  case AKind of
    okCopy: Result := '';
    okMove: Result := '';
    okDelete: Result := '';
    okArchive: Result := '';
  else
    Result := '';
  end;
end;

function JobShowsPill(J: TFileOpJob): Boolean;
begin
  { Пилюля только пока окно прогресса спрятано в фон.
    Успех в фоне ещё 2.5 с, ошибка в фоне — пока не закроют. }
  Result := Assigned(J) and
    ((J.State = jsBackground) or
     ((J.State = jsDone) and (J.DoneAt > 0)) or
     ((J.State = jsFailed) and J.Background));
end;

procedure HubPillList(out AList: TArray<TFileOpJob>);
var
  All: TArray<TFileOpJob>;
  I, N: Integer;
begin
  HubOrdered(All);
  N := 0;
  SetLength(AList, Length(All));
  for I := 0 to High(All) do
    if JobShowsPill(All[I]) then
    begin
      AList[N] := All[I];
      Inc(N);
    end;
  SetLength(AList, N);
end;

function FileOpHubCount: Integer;
var
  List: TArray<TFileOpJob>;
begin
  HubPillList(List);
  Result := Length(List);
end;

function FileOpHubView(AIndex: Integer): TFileOpJobView;
var
  List: TArray<TFileOpJob>;
begin
  Result := Default(TFileOpJobView);
  HubPillList(List);
  if (AIndex < 0) or (AIndex > High(List)) then
    Exit;
  Result := MakeView(List[AIndex]);
end;

function FileOpHubSpin: Single;
begin
  Result := GHubSpin;
end;

function FileOpHubHasBackground(AKind: TFileOpKind): Boolean;
var
  I: Integer;
begin
  Result := False;
  if GJobs = nil then
    Exit;
  for I := 0 to GJobs.Count - 1 do
    if (GJobs[I].Kind = AKind) and (GJobs[I].State = jsBackground) then
      Exit(True);
end;

procedure FileOpHubPumpViews;
var
  I: Integer;
  J: TFileOpJob;
  P: TFileOpProgress;
begin
  if GJobs = nil then
    Exit;
  GHubSpin := GHubSpin + 28;
  if GHubSpin >= 360 then
    GHubSpin := GHubSpin - 360;
  for I := GJobs.Count - 1 downto 0 do
  begin
    J := GJobs[I];
    if (J.State = jsDone) and (J.DoneAt > 0) and
       ((Now - J.DoneAt) * SecsPerDay >= 2.5) then
    begin
      GJobs.Delete(I);
      Continue;
    end;
    if Assigned(J.Engine) and HubHoldsSlot(J) then
    begin
      P := J.Engine.GetProgress;
      J.Progress := P;
      if J.State = jsNeedAnswer then
        { окно с вопросом не перетираем }
      else if J.Background or (J.State = jsBackground) then
        J.State := jsBackground
      else if P.Phase = opPaused then
        J.State := jsPaused
      else if J.State in [jsRunning, jsPaused] then
        J.State := jsRunning;
    end;
  end;
end;

procedure FileOpHubRestore(AId: Integer);
var
  J: TFileOpJob;
  Phase: TFileOpPhase;
begin
  J := HubFind(AId);
  if (J = nil) or (J.State = jsQueued) or (J.Form = nil) then
    Exit;
  J.Background := False;
  J.Form.FBackground := False;
  if J.State = jsBackground then
  begin
    Phase := opRun;
    if Assigned(J.Engine) then
      Phase := J.Engine.GetProgress.Phase;
    if Phase = opPaused then
      J.State := jsPaused
    else if J.Form.FConflict.Visible then
      J.State := jsNeedAnswer
    else
      J.State := jsRunning;
  end;
  J.Form.WindowState := TWindowState.wsNormal;
  if not J.Form.Visible then
    J.Form.Show;
  J.Form.BringToFront;
  J.Form.Activate;
  J.Form.ApplyNativeChrome;
  HubTouch;
end;

procedure FileOpHubDismiss(AId: Integer);
var
  J: TFileOpJob;
  Frm: TFileOpProgressForm;
begin
  J := HubFind(AId);
  if J = nil then
    Exit;
  if J.State = jsNeedAnswer then
  begin
    FileOpHubRestore(AId);
    Exit;
  end;
  if J.State = jsQueued then
  begin
    FireJobDone(J, False, 'Отменено');
    GJobs.Remove(J);
    HubPromote;
    HubTouch;
    Exit;
  end;
  if J.State in [jsDone, jsFailed, jsCancelled] then
  begin
    Frm := J.Form;
    J.Form := nil;
    J.Engine := nil;
    if Assigned(Frm) then
      Frm.FJobId := 0;
    GJobs.Remove(J);
    if Assigned(Frm) and not (csDestroying in Frm.ComponentState) then
      Frm.Close;
    HubTouch;
    Exit;
  end;
  if Assigned(J.Form) then
    J.Form.CancelClick(nil)
  else
  begin
    FireJobDone(J, False, 'Отменено');
    GJobs.Remove(J);
    HubPromote;
    HubTouch;
  end;
end;

procedure HubFinishJob(AId: Integer; ASuccess: Boolean; const AErr: string;
  AWasBg, ACloseForm: Boolean);
var
  J: TFileOpJob;
  Frm: TFileOpProgressForm;
  Drop: Boolean;
begin
  J := HubFind(AId);
  if J = nil then
    Exit;
  J.ErrorMsg := AErr;
  J.Background := AWasBg;
  Drop := False;
  if ASuccess and AWasBg then
  begin
    J.State := jsDone;
    J.DoneAt := Now;
  end
  else if ASuccess or (AErr = 'Отменено') then
  begin
    J.State := jsCancelled;
    Drop := True;
  end
  else
  begin
    J.State := jsFailed;
    J.DoneAt := 0;
  end;
  HubPromote;
  Frm := J.Form;
  if Drop then
  begin
    J.Form := nil;
    J.Engine := nil;
    if Assigned(Frm) then
      Frm.FJobId := 0;
    GJobs.Remove(J);
    J := nil;
  end
  else if ACloseForm and (J <> nil) then
  begin
    J.Form := nil;
    J.Engine := nil;
    if Assigned(Frm) then
      Frm.FJobId := 0;
  end;
  if ACloseForm and Assigned(Frm) and not (csDestroying in Frm.ComponentState) then
  begin
    Frm.Hide;
    Frm.Close;
  end;
  HubTouch;
end;

procedure HubMarkBackground(AId: Integer);
var
  J: TFileOpJob;
begin
  J := HubFind(AId);
  if J = nil then
    Exit;
  J.Background := True;
  if J.State <> jsNeedAnswer then
    J.State := jsBackground;
  HubTouch;
end;

procedure HubRaise(AId: Integer);
var
  J: TFileOpJob;
begin
  J := HubFind(AId);
  if J = nil then
    Exit;
  J.State := jsNeedAnswer;
  J.Background := False;
  if Assigned(J.Form) then
  begin
    J.Form.FBackground := False;
    J.Form.WindowState := TWindowState.wsNormal;
    if not J.Form.Visible then
      J.Form.Show;
    J.Form.BringToFront;
    J.Form.Activate;
    J.Form.ApplyNativeChrome;
  end;
  HubTouch;
end;

procedure HubAnswered(AId: Integer);
var
  J: TFileOpJob;
begin
  J := HubFind(AId);
  if (J = nil) or (J.State <> jsNeedAnswer) then
    Exit;
  if Assigned(J.Form) and J.Form.FBackground then
  begin
    J.Background := True;
    J.State := jsBackground;
  end
  else if Assigned(J.Engine) and (J.Engine.GetProgress.Phase = opPaused) then
  begin
    J.Background := False;
    J.State := jsPaused;
  end
  else
  begin
    J.Background := False;
    J.State := jsRunning;
  end;
  HubTouch;
end;

function RestoreVibeBackground(AKind: TFileOpKind): Boolean;
begin
  Result := False;
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
  J: TFileOpJob;
begin
  if Length(ASources) = 0 then
  begin
    if Assigned(AOnDone) then
      AOnDone(True, '');
    Exit;
  end;
  if GJobs = nil then
    GJobs := TObjectList<TFileOpJob>.Create(True);
  J := TFileOpJob.Create;
  J.Id := GNextId;
  Inc(GNextId);
  if GNextId < 1 then
    GNextId := 1;
  J.Kind := AKind;
  J.Sources := Copy(ASources);
  J.Dest := ADest;
  J.Permanent := APermanent;
  J.OnDone := AOnDone;
  J.OnItemDone := AOnItemDone;
  J.State := jsQueued;
  J.Background := False;
  HubFillVolumes(J);
  GJobs.Add(J);
  HubPromote;
  HubTouch;
end;

constructor TFileOpProgressForm.Create(AOwner: TComponent; AEngine: TFileOpEngine;
  AOnDone: TFileOpDoneProc; const AColors: TThemeColors);
begin
  inherited CreateNew(AOwner);
  FJobId := GBindJobId;
  FEngine := AEngine;
  if GBindJob <> nil then
  begin
    GBindJob.Form := Self;
    GBindJob.Engine := AEngine;
  end;
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
  HubUnlinkForm(Self);
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
  if FJobId > 0 then
  begin
    Left := Left + (FJobId mod 4) * 28;
    Top := Top + (FJobId mod 4) * 24;
  end;
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

procedure TFileOpProgressForm.BodyResize(Sender: TObject);
var
  Y, W: Single;

  procedure Row(ACtrl: TControl; AHeight, AGap: Single);
  begin
    if ACtrl = nil then
      Exit;
    ACtrl.Align := TAlignLayout.None;
    ACtrl.SetBounds(0, Y, W, AHeight);
    Y := Y + AHeight + AGap;
  end;

begin
  if not Assigned(FBody) then
    Exit;
  W := FBody.Width;
  if W < 8 then
    Exit;
  Y := 2;
  Row(FStats, 22, 8);
  Row(FPaths, 20, 2);
  Row(FToPath, 20, 10);
  Row(FCurLbl, 16, 4);
  Row(FFileTrack, 18, 10);
  Row(FAllLbl, 16, 4);
  Row(FTotalTrack, 18, 10);
  Row(FStatus, Max(88, FBody.Height - Y - 6), 0);
end;

procedure TFileOpProgressForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
  BodyResize(nil);
  if Assigned(FConfirm) and FConfirm.Visible then
    LayoutConfirm;
end;

procedure TFileOpProgressForm.BuildUI;
var
  Footer, Row: TLayout;
  Track: TRectangle;
  RI: Integer;

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

  FBody := TLayout.Create(Self);
  FBody.Parent := FRoot;
  FBody.Align := TAlignLayout.Client;
  FBody.OnResize := BodyResize;

  FStats := MkText(FBody, 12, False, FColors.TextColor);
  FStats.Text := '';
  FPaths := MkText(FBody, 12, False, FColors.SubTextColor);
  FPaths.Text := 'Из:';
  FToPath := MkText(FBody, 12, False, FColors.SubTextColor);
  FToPath.Text := 'В:';
  FCurLbl := MkText(FBody, 11, False, FColors.SubTextColor);
  FCurLbl.Text := 'Текущий файл';
  FFileTrack := MkTrack(FBody, FFileFill, FFilePct);
  FAllLbl := MkText(FBody, 11, False, FColors.SubTextColor);
  FAllLbl.Text := 'Всего';
  FTotalTrack := MkTrack(FBody, FTotalFill, FTotalPct);
  FStatus := MkText(FBody, 12, False, FColors.SubTextColor);
  FStatus.Text := '';
  FStatus.TextSettings.WordWrap := True;
  FStatus.TextSettings.VertAlign := TTextAlign.Leading;
  FStatus.TextSettings.Trimming := TTextTrimming.None;
  FFileName := FCurLbl;

  FRoot.Margins.Rect := TRectF.Create(16, 14, 16, 12);
  FRoot.Padding.Rect := TRectF.Create(16, 12, 16, 12);

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
  FConfirm.Fill.Color := FColors.Background;
  FConfirm.Stroke.Kind := TBrushKind.None;
  FConfirm.Padding.Rect := TRectF.Create(16, 16, 16, 16);
  FConfirm.Visible := False;
  FConfirm.HitTest := True;

  FConfBody := TLayout.Create(Self);
  FConfBody.Parent := FConfirm;
  FConfBody.Align := TAlignLayout.Client;
  FConfBody.HitTest := True;
  FConfBody.OnResize := ConfBodyResize;

  FConfIcon := TText.Create(Self);
  FConfIcon.Parent := FConfBody;
  FConfIcon.Align := TAlignLayout.None;
  FConfIcon.HitTest := False;
  FConfIcon.TextSettings.Font.Family := FluentIconFamily;
  FConfIcon.TextSettings.Font.Size := 32;
  FConfIcon.TextSettings.HorzAlign := TTextAlign.Center;
  FConfIcon.TextSettings.VertAlign := TTextAlign.Center;
  FConfIcon.TextSettings.FontColor := FColors.TextColor;
  FConfIcon.Tag := 9;

  FConfAskTitle := TText.Create(Self);
  FConfAskTitle.Parent := FConfBody;
  FConfAskTitle.Align := TAlignLayout.None;
  FConfAskTitle.HitTest := False;
  ApplyFluentText(FConfAskTitle, 16, True);
  FConfAskTitle.TextSettings.FontColor := FColors.TextColor;
  FConfAskTitle.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfAskTitle.TextSettings.VertAlign := TTextAlign.Center;
  FConfAskTitle.TextSettings.Trimming := TTextTrimming.Character;
  FConfAskTitle.Tag := 9;
  FConfAskTitle.Text := 'Подтвердить операцию?';

  FArchCombo := TFluentComboBox.Create(Self);
  FArchCombo.Parent := FConfBody;
  FArchCombo.Align := TAlignLayout.None;
  FArchCombo.DropListOnly := True;
  FArchCombo.Visible := False;
  FArchCombo.OnSelChange := ArchKindChanged;

  FConfFromCap := TText.Create(Self);
  FConfFromPath := TText.Create(Self);
  FConfToCap := TText.Create(Self);
  FConfToPath := TText.Create(Self);
  FConfFromCap.Parent := FConfBody;
  FConfFromPath.Parent := FConfBody;
  FConfToCap.Parent := FConfBody;
  FConfToPath.Parent := FConfBody;
  FConfFromCap.Text := 'Из:';
  FConfToCap.Text := 'В:';
  FConfFromCap.Align := TAlignLayout.None;
  FConfFromPath.Align := TAlignLayout.None;
  FConfToCap.Align := TAlignLayout.None;
  FConfToPath.Align := TAlignLayout.None;
  FConfFromCap.HitTest := False;
  FConfFromPath.HitTest := False;
  FConfToCap.HitTest := False;
  FConfToPath.HitTest := False;
  ApplyFluentText(FConfFromCap, 12, False);
  ApplyFluentText(FConfFromPath, 12, False);
  ApplyFluentText(FConfToCap, 12, False);
  ApplyFluentText(FConfToPath, 12, False);
  FConfFromCap.TextSettings.FontColor := FColors.SubTextColor;
  FConfFromPath.TextSettings.FontColor := FColors.SubTextColor;
  FConfToCap.TextSettings.FontColor := FColors.SubTextColor;
  FConfToPath.TextSettings.FontColor := FColors.SubTextColor;
  FConfFromCap.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfFromPath.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfToCap.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfToPath.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfFromCap.TextSettings.VertAlign := TTextAlign.Center;
  FConfFromPath.TextSettings.VertAlign := TTextAlign.Center;
  FConfToCap.TextSettings.VertAlign := TTextAlign.Center;
  FConfToPath.TextSettings.VertAlign := TTextAlign.Center;
  FConfFromCap.TextSettings.Trimming := TTextTrimming.Character;
  FConfFromPath.TextSettings.Trimming := TTextTrimming.Character;
  FConfToCap.TextSettings.Trimming := TTextTrimming.Character;
  FConfToPath.TextSettings.Trimming := TTextTrimming.Character;
  FConfFromCap.Tag := 8;
  FConfFromPath.Tag := 8;
  FConfToCap.Tag := 8;
  FConfToPath.Tag := 8;

  for RI := 0 to 7 do
  begin
    FConfRowHost[RI] := TLayout.Create(Self);
    FConfRowHost[RI].Parent := FConfBody;
    FConfRowHost[RI].Align := TAlignLayout.None;
    FConfRowHost[RI].HitTest := False;
    FConfRowHost[RI].Visible := False;
    FConfRowIco[RI] := TImage.Create(Self);
    FConfRowIco[RI].Parent := FConfRowHost[RI];
    FConfRowIco[RI].Align := TAlignLayout.None;
    FConfRowIco[RI].HitTest := False;
    FConfRowIco[RI].SetBounds(0, 2, 18, 18);
    FConfRowIco[RI].WrapMode := TImageWrapMode.Fit;
    FConfRowName[RI] := TText.Create(Self);
    FConfRowName[RI].Parent := FConfRowHost[RI];
    FConfRowName[RI].Align := TAlignLayout.None;
    FConfRowName[RI].HitTest := False;
    FConfRowName[RI].SetBounds(26, 0, 200, 22);
    ApplyFluentText(FConfRowName[RI], 12, False);
    FConfRowName[RI].TextSettings.FontColor := FColors.SubTextColor;
    FConfRowName[RI].TextSettings.HorzAlign := TTextAlign.Leading;
    FConfRowName[RI].TextSettings.VertAlign := TTextAlign.Center;
    FConfRowName[RI].TextSettings.Trimming := TTextTrimming.Character;
    FConfRowName[RI].Tag := 8;
  end;

  FConfMore := TText.Create(Self);
  FConfMore.Parent := FConfBody;
  FConfMore.Align := TAlignLayout.None;
  FConfMore.HitTest := False;
  FConfMore.Visible := False;
  ApplyFluentText(FConfMore, 12, False);
  FConfMore.TextSettings.FontColor := FColors.SubTextColor;
  FConfMore.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfMore.Tag := 8;

  FConfAskText := TText.Create(Self);
  FConfAskText.Parent := FConfBody;
  FConfAskText.Align := TAlignLayout.None;
  FConfAskText.HitTest := False;
  ApplyFluentText(FConfAskText, 12, False);
  FConfAskText.TextSettings.FontColor := FColors.SubTextColor;
  FConfAskText.TextSettings.HorzAlign := TTextAlign.Leading;
  FConfAskText.TextSettings.VertAlign := TTextAlign.Center;
  FConfAskText.TextSettings.Trimming := TTextTrimming.Character;
  FConfAskText.Tag := 8;

  Track := TRectangle.Create(Self);
  Track.Parent := FConfBody;
  Track.Align := TAlignLayout.Bottom;
  Track.Height := 42;
  Track.Stroke.Kind := TBrushKind.None;
  Track.Fill.Color := TAlphaColors.Null;
  FBtnConfirmYes := CreateFluentButton(Self, Track, '', 'Выполнить', fbkAccent, 120, ConfirmYesClick);
  FBtnConfirmYes.Align := TAlignLayout.Right;
  FBtnConfirmYes.Margins.Right := 8;
  CreateFluentButton(Self, Track, '', 'Отмена', fbkStandard, 100, ConfirmNoClick).Align := TAlignLayout.Right;
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
  FBtnGo.Enabled := (Ready or Paused) and
    not (Assigned(FConfirm) and FConfirm.Visible);
  FBtnGo.HitTest := FBtnGo.Enabled;
  if FBtnGo.Enabled then FBtnGo.Opacity := 1 else FBtnGo.Opacity := 0.4;
  FBtnPause.Enabled := Running;
  FBtnPause.HitTest := Running;
  if Running then FBtnPause.Opacity := 1 else FBtnPause.Opacity := 0.4;
  FBtnSkip.Enabled := Running;
  FBtnSkip.HitTest := Running;
  if Running then FBtnSkip.Opacity := 1 else FBtnSkip.Opacity := 0.4;
  FBtnCancel.Enabled := not FFinished;
  if Assigned(FBtnBg) then
  begin
    FBtnBg.Enabled := (not FFinished) and (not FKeepOpen) and
      not (Assigned(FConflict) and FConflict.Visible) and
      not (Assigned(FConfirm) and FConfirm.Visible);
    FBtnBg.HitTest := FBtnBg.Enabled;
    if FBtnBg.Enabled then
      FBtnBg.Opacity := 1
    else
      FBtnBg.Opacity := 0.4;
  end;
end;

procedure TFileOpProgressForm.Tick(Sender: TObject);
var
  P: TFileOpProgress;
  St: string;
begin
  if FEngine = nil then
    Exit;
  P := FEngine.GetProgress;
  if (not FFinished) and (not FKeepOpen) and (P.Phase = opReady) and
     (not FDeleteAsked) then
  begin
    if FBackground then
    begin
      FBackground := False;
      if not Visible then
        Show;
      BringToFront;
    end;
    ShowConfirm(P);
  end;
  if P.FileName <> '' then
    FCurLbl.Text := 'Текущий файл    ' + P.FileName
  else
    FCurLbl.Text := 'Текущий файл';
  if P.SourcePath <> '' then
    FPaths.Text := 'Из:   ' + P.SourcePath
  else
    FPaths.Text := 'Из:';
  if P.DestPath <> '' then
    FToPath.Text := 'В:   ' + P.DestPath
  else if FEngine.Dest <> '' then
    FToPath.Text := 'В:   ' + FEngine.Dest
  else
    FToPath.Text := 'В:';
  St := P.Status;
  if SameText(St, FileOpKindCaption(P.Kind)) or
     SameText(St, 'Подсчёт файлов…') or StartsText('Подготов', St) then
    St := '';
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
  if (P.Phase = opReady) and not FDeleteAsked and not FKeepOpen then
    ShowConfirm(P);
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
    FileOpHubDismiss(FJobId);
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
  if FFinished or FKeepOpen then
    Exit;
  if Assigned(FConflict) and FConflict.Visible then
    Exit;
  if Assigned(FConfirm) and FConfirm.Visible then
    Exit;
  if Assigned(FEngine) then
  begin
    P := FEngine.GetProgress;
    if (P.Phase = opReady) and FDeleteAsked then
      FEngine.Start;
  end;
  FBackground := True;
  HubMarkBackground(FJobId);
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
  if Assigned(FBtnBg) then
  begin
    FBtnBg.Enabled := False;
    FBtnBg.HitTest := False;
    FBtnBg.Opacity := 0.4;
  end;
  HubRaise(FJobId);
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
  if Assigned(FBtnBg) and not FFinished and not FKeepOpen then
  begin
    FBtnBg.Enabled := True;
    FBtnBg.HitTest := True;
    FBtnBg.Opacity := 1;
  end;
  HubAnswered(FJobId);
end;

function RuObjects(N: Integer): string;
var
  M, D: Integer;
begin
  if N < 0 then
    N := 0;
  M := N mod 100;
  D := M mod 10;
  if (M >= 11) and (M <= 14) then
    Result := Format('%d объектов', [N])
  else if D = 1 then
    Result := Format('%d объект', [N])
  else if (D >= 2) and (D <= 4) then
    Result := Format('%d объекта', [N])
  else
    Result := Format('%d объектов', [N]);
end;

function ArchiveStem(const APath: string): string;
var
  L: string;
begin
  L := APath;
  if EndsText('.tar.gz', L) then
    Exit(Copy(L, 1, Length(L) - 7));
  if EndsText('.tgz', L) or EndsText('.zip', L) or EndsText('.7z', L) or
     EndsText('.tar', L) or EndsText('.gz', L) then
    Exit(Copy(L, 1, Length(L) - Length(ExtractFileExt(L))));
  Result := ChangeFileExt(L, '');
end;

function ArchiveExtOf(AKind: TArchiveKind): string;
begin
  case AKind of
    akSevenZ: Result := '.7z';
    akTar: Result := '.tar';
    akTgz: Result := '.tgz';
  else
    Result := '.zip';
  end;
end;

function CommonSourceDir(AEngine: TFileOpEngine): string;
var
  I: Integer;
  D: string;
begin
  Result := '';
  if (AEngine = nil) or (AEngine.SourceCount = 0) then
    Exit;
  Result := ExcludeTrailingPathDelimiter(
    ExtractFilePath(ExcludeTrailingPathDelimiter(AEngine.SourcePath(0))));
  for I := 1 to AEngine.SourceCount - 1 do
  begin
    D := ExcludeTrailingPathDelimiter(
      ExtractFilePath(ExcludeTrailingPathDelimiter(AEngine.SourcePath(I))));
    if not SameText(D, Result) then
      Exit('Несколько папок');
  end;
end;

procedure TFileOpProgressForm.LayoutConfirm;
var
  W, Y, Limit: Single;
  I, Hidden: Integer;
begin
  if not Assigned(FConfBody) then
    Exit;
  W := FConfBody.Width;
  if W < 80 then
    Exit;
  FConfIcon.SetBounds(0, 2, 48, 48);
  if Assigned(FArchCombo) and FArchCombo.Visible then
  begin
    FArchCombo.SetBounds(W - 188, 8, 188, 32);
    FConfAskTitle.SetBounds(58, 8, Max(80, W - 58 - 200), 36);
  end
  else
    FConfAskTitle.SetBounds(58, 8, Max(80, W - 66), 36);
  Y := 58;
  FConfFromCap.SetBounds(8, Y, 32, 20);
  FConfFromPath.SetBounds(44, Y, Max(40, W - 44), 20);
  Y := Y + 22;
  if FConfToCap.Visible then
  begin
    FConfToCap.SetBounds(8, Y, 32, 20);
    FConfToPath.SetBounds(44, Y, Max(40, W - 44), 20);
    Y := Y + 22;
  end;
  Y := Y + 10;
  Limit := FConfBody.Height - 42 - 28;
  if Limit < Y + 24 then
    Limit := Y + 24;
  Hidden := 0;
  for I := 0 to 7 do
    if Assigned(FConfRowHost[I]) and (FConfRowName[I].Text <> '') then
    begin
      if Y + 24 <= Limit - 20 then
      begin
        FConfRowHost[I].Visible := True;
        FConfRowHost[I].SetBounds(40, Y, Max(40, W - 40), 24);
        if Assigned(FConfRowIco[I]) then
          FConfRowIco[I].SetBounds(0, 3, 18, 18);
        FConfRowName[I].SetBounds(26, 0, Max(40, W - 40 - 26), 24);
        Y := Y + 24;
      end
      else
      begin
        FConfRowHost[I].Visible := False;
        Inc(Hidden);
      end;
    end
    else if Assigned(FConfRowHost[I]) then
      FConfRowHost[I].Visible := False;
  if Assigned(FConfMore) then
  begin
    Hidden := Hidden + FConfExtra;
    FConfMore.Visible := Hidden > 0;
    if Hidden > 0 then
    begin
      FConfMore.Text := Format('… и ещё %d', [Hidden]);
      FConfMore.SetBounds(66, Y, Max(40, W - 66), 20);
    end;
  end;
  if Assigned(FConfAskText) then
    FConfAskText.SetBounds(8, FConfBody.Height - 42 - 24, Max(40, W - 8), 20);
end;

procedure TFileOpProgressForm.ConfBodyResize(Sender: TObject);
begin
  LayoutConfirm;
end;

procedure TFileOpProgressForm.ArchKindChanged(Sender: TObject);
var
  K: TArchiveKind;
begin
  if FArchLock or (FEngine = nil) or not Assigned(FArchCombo) then
    Exit;
  if (FArchCombo.ItemIndex < 0) or (FArchCombo.ItemIndex >= FArchKindCount) then
    Exit;
  K := TArchiveKind(FArchKinds[FArchCombo.ItemIndex]);
  if FArchStem = '' then
    FArchStem := ArchiveStem(FEngine.Dest);
  FEngine.SetDest(FArchStem + ArchiveExtOf(K));
  if Assigned(FConfToPath) then
    FConfToPath.Text := FEngine.Dest;
end;

procedure TFileOpProgressForm.ShowConfirm(const P: TFileOpProgress);
var
  N, Shown, I: Integer;
  Verb, YesCap: string;
  YesW: Single;
  Path, FromDir: string;
  IsDir: Boolean;
  Cur: TArchiveKind;

  procedure AddArch(AKind: TArchiveKind; const ACaption: string);
  begin
    if FArchKindCount > High(FArchKinds) then
      Exit;
    FArchKinds[FArchKindCount] := Ord(AKind);
    Inc(FArchKindCount);
    FArchCombo.Items.Add(ACaption);
  end;

begin
  if not Assigned(FConfirm) or FConfirm.Visible or FDeleteAsked or FKeepOpen then
    Exit;
  if FEngine = nil then
    Exit;
  N := FEngine.SourceCount;
  if N <= 0 then
    N := P.FilesTotal;
  if N <= 0 then
    N := 1;
  FConfIcon.Text := FileOpKindIcon(P.Kind);
  FConfToCap.Visible := P.Kind <> okDelete;
  FConfToPath.Visible := P.Kind <> okDelete;
  case P.Kind of
    okDelete:
      begin
        if FEngine.Permanent then
        begin
          Verb := 'Удалить навсегда ' + RuObjects(N) + '?';
          FConfAskText.Text := 'Файлы будут уничтожены без Корзины';
        end
        else
        begin
          Verb := 'Удалить ' + RuObjects(N) + ' в Корзину?';
          FConfAskText.Text := 'Можно будет восстановить из Корзины';
        end;
        YesCap := 'Удалить';
        YesW := 110;
      end;
    okMove:
      begin
        Verb := 'Переместить ' + RuObjects(N) + '?';
        FConfAskText.Text := 'К выполнению';
        YesCap := 'Переместить';
        YesW := 130;
      end;
    okArchive:
      begin
        Verb := 'Архивировать ' + RuObjects(N) + '?';
        FConfAskText.Text := 'К выполнению';
        YesCap := 'Выполнить';
        YesW := 120;
      end;
  else
    Verb := 'Копировать ' + RuObjects(N) + '?';
    FConfAskText.Text := 'К выполнению';
    YesCap := 'Копировать';
    YesW := 120;
  end;
  if P.TotalBytesTotal > 0 then
    FConfAskText.Text := FConfAskText.Text + '  ·  ' + FormatOpBytes(P.TotalBytesTotal);
  FConfAskTitle.Text := Verb;
  FromDir := CommonSourceDir(FEngine);
  if FromDir = '' then
    FromDir := P.SourcePath;
  FConfFromPath.Text := FromDir;
  FConfToPath.Text := FEngine.Dest;
  Shown := 0;
  for I := 0 to 7 do
  begin
    if I < FEngine.SourceCount then
    begin
      Path := FEngine.SourcePath(I);
      IsDir := TDirectory.Exists(Path);
      FConfRowName[I].Text := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
      SetConfFallbackIcon(Path, IsDir, FConfRowIco[I]);
      FConfRowHost[I].Visible := True;
      Inc(Shown);
    end
    else
    begin
      FConfRowName[I].Text := '';
      if Assigned(FConfRowIco[I]) then
        FConfRowIco[I].Bitmap.Assign(nil);
      FConfRowHost[I].Visible := False;
    end;
  end;
  FConfExtra := FEngine.SourceCount - Shown;
  if FConfExtra < 0 then
    FConfExtra := 0;
  if Assigned(FBtnConfirmYes) then
  begin
    FBtnConfirmYes.SetCaption(YesCap);
    FBtnConfirmYes.Width := YesW;
  end;
  FArchCombo.Visible := P.Kind = okArchive;
  if P.Kind = okArchive then
  begin
    FArchLock := True;
    try
      FArchKindCount := 0;
      FArchCombo.Items.Clear;
      AddArch(akZip, 'ZIP');
      if SevenZipAvailable then
        AddArch(akSevenZ, '7Z');
      AddArch(akTar, 'TAR');
      AddArch(akTgz, 'TAR.GZ');
      FArchStem := ArchiveStem(FEngine.Dest);
      Cur := DetectArchiveKind(FEngine.Dest);
      FArchCombo.ItemIndex := 0;
      for I := 0 to FArchKindCount - 1 do
        if FArchKinds[I] = Ord(Cur) then
        begin
          FArchCombo.ItemIndex := I;
          Break;
        end;
      if (FArchCombo.ItemIndex >= 0) and
         (FArchKinds[FArchCombo.ItemIndex] <> Ord(Cur)) then
        FEngine.SetDest(FArchStem + ArchiveExtOf(TArchiveKind(FArchKinds[FArchCombo.ItemIndex])));
      FConfToPath.Text := FEngine.Dest;
    finally
      FArchLock := False;
    end;
  end;
  FConfirm.Visible := True;
  FConfirm.BringToFront;
  LayoutConfirm;
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
    FConfirm.Fill.Color := AColors.Background;
  if Assigned(FArchCombo) then
    FArchCombo.ApplyTheme(AColors);
  ApplyNativeChrome;
  ThemeTree(FRoot, AColors);




end;

procedure TFileOpProgressForm.EngineDone(Success: Boolean; const ErrorMsg: string);
var
  Bg, CloseIt: Boolean;
begin
  if FFinished then
    Exit;
  FFinished := True;
  Bg := FBackground;
  FireDone(Success, ErrorMsg);
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  CloseIt := True;
  if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') then
  begin
    CloseIt := False;
    FKeepOpen := True;
    if not Bg then
      FStatus.Text := ErrorMsg;
    FBtnGo.SetCaption('Закрыть');
    FBtnGo.Enabled := True;
    FBtnGo.HitTest := True;
    FBtnGo.Opacity := 1;
    FBtnPause.Enabled := False;
    FBtnSkip.Enabled := False;
    if Assigned(FBtnBg) then
    begin
      FBtnBg.Enabled := False;
      FBtnBg.HitTest := False;
      FBtnBg.Opacity := 0.4;
    end;
    if Bg then
      Hide;
  end;
  HubFinishJob(FJobId, Success, ErrorMsg, Bg, CloseIt);
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
    HubFinishJob(FJobId, False, 'Отменено', FBackground, False);
  end;
  CloseAction := TCloseAction.caFree;
  inherited;
end;

procedure TFileOpProgressForm.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
var
  Ch: Char;
begin
  if Key in [vkF2..vkF8] then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
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
  GJobs := TObjectList<TFileOpJob>.Create(True);
  GNextId := 1;
  GBindJobId := 0;
  SetVibeHooks(
    procedure(AKind: Integer; const ASources: TArray<string>; const ADest: string;
      AOnDone: TFileOpDoneProc; APermanent: Boolean; AOnItemDone: TFileOpItemDoneProc)
    begin
      RunVibeOperation(TFileOpKind(AKind), ASources, ADest, AOnDone, APermanent,
        AOnItemDone);
    end,
    function(AKind: Integer): Boolean
    begin
      Result := RestoreVibeBackground(TFileOpKind(AKind));
    end);
  SetFileOpHubApi(
    function: Integer
    begin
      Result := FileOpHubCount;
    end,
    function(AIndex: Integer): TFileOpJobView
    begin
      Result := FileOpHubView(AIndex);
    end,
    procedure(AId: Integer)
    begin
      FileOpHubRestore(AId);
    end,
    procedure(AId: Integer)
    begin
      FileOpHubDismiss(AId);
    end,
    function(AKind: TFileOpKind): Boolean
    begin
      Result := FileOpHubHasBackground(AKind);
    end,
    procedure
    begin
      FileOpHubPumpViews;
    end,
    function: Single
    begin
      Result := FileOpHubSpin;
    end);

finalization
  SetVibeHooks(nil, nil);
  SetFileOpHubApi(nil, nil, nil, nil, nil, nil, nil);
  FreeAndNil(GJobs);

end.

