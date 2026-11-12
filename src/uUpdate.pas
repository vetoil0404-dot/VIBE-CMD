unit uUpdate;

{
  Проверка релиза GitHub и замена только exe.
  Адрес репозитория лежит в настройках. Токен не хранится.
  Помощник ждёт выход процесса: иначе новый экземпляр
  прилипает к старому окну и оба закрываются.
}

interface

uses
  FMX.Forms, uAppSettings;

procedure ArmAutoUpdate(AOwner: TCommonCustomForm; ASettings: TAppSettings);
procedure CheckUpdatesNow(AOwner: TCommonCustomForm; ASettings: TAppSettings);
procedure StopUpdate;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.StrUtils,
  System.IOUtils, System.JSON, System.Zip, System.Hash, System.SyncObjs,
  System.Net.HttpClient, System.Net.URLClient,
  Winapi.Windows, Winapi.ShellAPI,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.Dialogs,
  FMX.Platform.Win,
  uLang, uLangBind, uThemeManager, uFluentChrome, uFileOpEngine;

const
  MAX_UPDATE_BYTES = 256 * 1024 * 1024;
  APPLY_PS =
    '$ErrorActionPreference = ''Stop''' + sLineBreak +
    '$pidWait = [int]$args[0]' + sLineBreak +
    '$src = $args[1]' + sLineBreak +
    '$dst = $args[2]' + sLineBreak +
    'while (Get-Process -Id $pidWait -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }' + sLineBreak +
    'Start-Sleep -Milliseconds 400' + sLineBreak +
    'if (-not (Test-Path -LiteralPath $src)) { exit 1 }' + sLineBreak +
    '$srcLen = (Get-Item -LiteralPath $src).Length' + sLineBreak +
    'if ($srcLen -le 0) { exit 1 }' + sLineBreak +
    'Copy-Item -LiteralPath $src -Destination $dst -Force' + sLineBreak +
    '$dstLen = (Get-Item -LiteralPath $dst).Length' + sLineBreak +
    'if ($srcLen -ne $dstLen) { exit 1 }' + sLineBreak +
    'Start-Process -FilePath $dst' + sLineBreak +
    'Remove-Item -LiteralPath $src -Force' + sLineBreak +
    'Remove-Item -LiteralPath $PSCommandPath -Force' + sLineBreak;

type
  TCheckKind = (ckNewer, ckSame, ckNoFile, ckFail);

  TVer = record
    P: array[0..7] of Integer;
    N: Integer;
  end;

  TRelease = class
    Tag, Title, Body, Published: string;
    AssetName, AssetUrl, ShaUrl: string;
    AssetSize: Int64;
  end;

  TUpdateOffer = class(TForm)
  private
    FColors: TThemeColors;
    FTag, FUrl, FSha, FAsset, FReady: string;
    FSize: Int64;
    FJobId: Integer;
    FBusy, FInstalling, FUserCancel, FCloseAfter: Boolean;
    FTitle, FHave, FWhen, FBody, FStatus, FProg: TText;
    FTrack, FFill: TRectangle;
    FBtnUpdate, FBtnLater, FBtnSkip, FBtnCancel: TFluentButton;
    procedure LaterClick(Sender: TObject);
    procedure SkipClick(Sender: TObject);
    procedure UpdateClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure HandleClose(Sender: TObject; var Action: TCloseAction);
    procedure ShowBusy;
    procedure ShowIdle;
    procedure StartDownload;
    procedure TryInstall(const APayload: string);
  protected
    procedure DoShow; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  public
    procedure Init(AInfo: TRelease);
    procedure SetProgress(ARead, ATotal: Int64);
    procedure FinishDownload(AOk: Boolean; const APath, AKey: string;
      AStopped: Boolean; AJob: Integer);
    function Busy: Boolean;
    destructor Destroy; override;
  end;

  TToast = class(TForm)
  private
    procedure Tick(Sender: TObject);
    procedure HandleClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure DoShow; override;
  public
    procedure Init(const AText: string);
    destructor Destroy; override;
  end;

  TDownJob = class
  public
    Url, ShaUrl, WorkName: string;
    Expect: Int64;
    Epoch, JobId: Integer;
    Client: THTTPClient;
    LastReport: Int64;
    TooBig, WantProgress: Boolean;
    MaxBytes: Int64;
    procedure OnData(const Sender: TObject; AContentLength, AReadCount: Int64;
      var Abort: Boolean);
    function Stopped: Boolean;
    function Download(const AUrl, ADest: string; AMax: Int64; AProgress: Boolean;
      out AStatus: Integer; out AContentLen: Int64): Boolean;
    procedure Run;
  end;

var
  GAlive: Integer;
  GCheckBusy: Integer;
  GManualWait: Integer;
  GAutoQueued: Integer;
  GEpoch: Integer;
  GSettings: TAppSettings;
  GMain: TCommonCustomForm;
  GOffer: TUpdateOffer;
  GToast: TToast;

function UpdateAlive: Boolean;
begin
  Result := TInterlocked.CompareExchange(GAlive, 0, 0) <> 0;
end;

function UpdateRoot: string;
begin
  Result := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath, 'VibeCmd');
  Result := System.IOUtils.TPath.Combine(Result, 'update');
  if not TDirectory.Exists(Result) then
    TDirectory.CreateDirectory(Result);
end;

procedure TryDelete(const APath: string);
begin
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    TFile.Delete(APath);
  except
  end;
end;

procedure WipeDir(const ADir: string);
begin
  if (ADir = '') or not TDirectory.Exists(ADir) then
    Exit;
  try
    TDirectory.Delete(ADir, True);
  except
  end;
end;

function FileLen(const APath: string): Int64;
var
  Fs: TFileStream;
begin
  Result := -1;
  try
    Fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      Result := Fs.Size;
    finally
      Fs.Free;
    end;
  except
  end;
end;

function HasSig(const APath: string; A0, A1: Byte): Boolean;
var
  Fs: TFileStream;
  B: array[0..1] of Byte;
begin
  Result := False;
  try
    Fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if Fs.Size < 2 then
        Exit;
      Fs.ReadBuffer(B, 2);
      Result := (B[0] = A0) and (B[1] = A1);
    finally
      Fs.Free;
    end;
  except
  end;
end;

procedure LiftForm(AForm: TCommonCustomForm);
var
  W: HWND;
begin
  if AForm = nil then
    Exit;
  W := FormToHWND(AForm);
  if W = 0 then
    Exit;
  EnableWindow(W, True);
  SetWindowPos(W, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW);
end;

procedure PostProgress(AJob: Integer; ARead, ATotal: Int64);
begin
  TThread.Queue(nil,
    procedure
    begin
      if not UpdateAlive or (GOffer = nil) or (GOffer.FJobId <> AJob) then
        Exit;
      GOffer.SetProgress(ARead, ATotal);
    end);
end;

function ExeFileVersion: string;
var
  Dummy, Sz: DWORD;
  Buf: Pointer;
  Info: PVSFixedFileInfo;
  Len: UINT;
begin
  Result := '1.0.0';
  Sz := GetFileVersionInfoSize(PChar(ParamStr(0)), Dummy);
  if Sz = 0 then
    Exit;
  GetMem(Buf, Sz);
  try
    if GetFileVersionInfo(PChar(ParamStr(0)), 0, Sz, Buf) and
       VerQueryValue(Buf, '\', Pointer(Info), Len) and (Info <> nil) then
      Result := Format('%d.%d.%d', [HiWord(Info.dwFileVersionMS),
        LoWord(Info.dwFileVersionMS), HiWord(Info.dwFileVersionLS)]);
  finally
    FreeMem(Buf);
  end;
end;

function ParseVer(const ATag: string; out V: TVer): Boolean;
var
  S, Part: string;
  I, N: Integer;
begin
  Result := False;
  FillChar(V, SizeOf(V), 0);
  S := Trim(ATag);
  if S = '' then
    Exit;
  if (S[1] = 'v') or (S[1] = 'V') then
    Delete(S, 1, 1);
  I := Pos('-', S);
  if I > 0 then
    S := Copy(S, 1, I - 1);
  I := Pos('+', S);
  if I > 0 then
    S := Copy(S, 1, I - 1);
  S := Trim(S);
  if S = '' then
    Exit;
  Part := '';
  for I := 1 to Length(S) do
  begin
    if CharInSet(S[I], ['0'..'9']) then
      Part := Part + S[I]
    else if S[I] = '.' then
    begin
      if (Part = '') or (V.N >= 8) then
        Exit;
      if not TryStrToInt(Part, N) or (N < 0) then
        Exit;
      V.P[V.N] := N;
      Inc(V.N);
      Part := '';
    end
    else
      Exit;
  end;
  if (Part = '') or (V.N >= 8) then
    Exit;
  if not TryStrToInt(Part, N) or (N < 0) then
    Exit;
  V.P[V.N] := N;
  Inc(V.N);
  Result := V.N > 0;
end;

function VerCmp(const A, B: TVer): Integer;
var
  I, C, AV, BV: Integer;
begin
  C := A.N;
  if B.N > C then
    C := B.N;
  for I := 0 to C - 1 do
  begin
    AV := 0;
    BV := 0;
    if I < A.N then
      AV := A.P[I];
    if I < B.N then
      BV := B.P[I];
    if AV > BV then
      Exit(1);
    if AV < BV then
      Exit(-1);
  end;
  Result := 0;
end;

function SkipHas(const AList, ATag: string): Boolean;
var
  S, P: string;
  K: Integer;
begin
  Result := False;
  if (AList = '') or (ATag = '') then
    Exit;
  S := AList;
  while S <> '' do
  begin
    K := Pos('|', S);
    if K > 0 then
    begin
      P := Copy(S, 1, K - 1);
      Delete(S, 1, K);
    end
    else
    begin
      P := S;
      S := '';
    end;
    if P = ATag then
      Exit(True);
  end;
end;

function WildMatch(const AText, APat: string): Boolean;
var
  T, P: string;
  Ti, Pi, StarT, StarP: Integer;
begin
  T := LowerCase(AText);
  P := LowerCase(APat);
  while Pos('**', P) > 0 do
    P := StringReplace(P, '**', '*', [rfReplaceAll]);
  Ti := 1;
  Pi := 1;
  StarT := 0;
  StarP := 0;
  while Ti <= Length(T) do
  begin
    if (Pi <= Length(P)) and (P[Pi] = '*') then
    begin
      Inc(Pi);
      StarP := Pi;
      StarT := Ti;
    end
    else if (Pi <= Length(P)) and (P[Pi] = T[Ti]) then
    begin
      Inc(Pi);
      Inc(Ti);
    end
    else if StarP > 0 then
    begin
      Inc(StarT);
      Ti := StarT;
      Pi := StarP;
    end
    else
      Exit(False);
  end;
  while (Pi <= Length(P)) and (P[Pi] = '*') do
    Inc(Pi);
  Result := Pi > Length(P);
end;

function SplitMask(const AMask: string): TArray<string>;
var
  S, P: string;
  K, N: Integer;
begin
  S := Trim(AMask);
  if S = '' then
    S := DEFAULT_UPDATE_MASK;
  SetLength(Result, 0);
  while S <> '' do
  begin
    K := Pos(';', S);
    if K > 0 then
    begin
      P := Trim(Copy(S, 1, K - 1));
      Delete(S, 1, K);
    end
    else
    begin
      P := Trim(S);
      S := '';
    end;
    if P = '' then
      Continue;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := P;
  end;
end;

function NormalizeRepo(const ARepo: string; out AOwner, AName: string): Boolean;
var
  S: string;
  P: Integer;

  function PartOk(const X: string): Boolean;
  var
    K: Integer;
  begin
    Result := (X <> '') and (X <> '.') and (X <> '..');
    if not Result then
      Exit;
    for K := 1 to Length(X) do
      if not CharInSet(X[K], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']) then
        Exit(False);
  end;

begin
  Result := False;
  AOwner := '';
  AName := '';
  S := Trim(ARepo);
  S := StringReplace(S, '\', '/', [rfReplaceAll]);
  if StartsText('https://github.com/', S) then
    Delete(S, 1, Length('https://github.com/'))
  else if StartsText('http://github.com/', S) then
    Delete(S, 1, Length('http://github.com/'))
  else if StartsText('github.com/', S) then
    Delete(S, 1, Length('github.com/'));
  if EndsText('.git', S) then
    Delete(S, Length(S) - 3, 4);
  while (S <> '') and (S[Length(S)] = '/') do
    Delete(S, Length(S), 1);
  if (S = '') or (Pos(' ', S) > 0) or (Pos('@', S) > 0) or (Pos('..', S) > 0) then
    Exit;
  P := Pos('/', S);
  if (P <= 1) or (P = Length(S)) or (Pos('/', Copy(S, P + 1, MaxInt)) > 0) then
    Exit;
  AOwner := Copy(S, 1, P - 1);
  AName := Copy(S, P + 1, MaxInt);
  Result := PartOk(AOwner) and PartOk(AName);
end;

function JsonStr(O: TJSONObject; const K: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if O = nil then
    Exit;
  V := O.GetValue(K);
  if (V = nil) or (V is TJSONNull) then
    Exit;
  Result := V.Value;
end;

function JsonBool(O: TJSONObject; const K: string): Boolean;
begin
  Result := SameText(JsonStr(O, K), 'true');
end;

function SafeName(const AName: string): string;
var
  S: string;
  I: Integer;
  C: Char;
begin
  S := ExtractFileName(StringReplace(AName, '/', '\', [rfReplaceAll]));
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-', ' ']) then
      Result := Result + C;
  end;
  Result := Trim(Result);
  if (Result = '') or (Result = '.') or (Result = '..') then
    Result := 'update.bin';
end;

function ShortBody(const S: string): string;
const
  Lim = 520;
var
  T: string;
  I: Integer;
begin
  T := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  T := StringReplace(T, #13, #10, [rfReplaceAll]);
  T := Trim(T);
  if Length(T) <= Lim then
    Exit(T);
  Result := Copy(T, 1, Lim);
  I := LastDelimiter(' '#10, Result);
  if I > Lim div 2 then
    SetLength(Result, I - 1);
  Result := TrimRight(Result) + '…';
end;

function DateOnly(const AIso: string): string;
begin
  Result := Trim(AIso);
  if (Length(Result) >= 10) and (Result[5] = '-') and (Result[8] = '-') then
    Result := Copy(Result, 1, 10);
end;

function HttpString(const AUrl: string; out AStatus: Integer; out ABody: string): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Result := False;
  AStatus := 0;
  ABody := '';
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 8000;
    Client.ResponseTimeout := 15000;
    Client.HandleRedirects := True;
    Client.UserAgent := 'VibeCmd';
    SetLength(Headers, 2);
    Headers[0] := TNetHeader.Create('Accept', 'application/vnd.github+json');
    Headers[1] := TNetHeader.Create('X-GitHub-Api-Version', '2022-11-28');
    try
      Resp := Client.Get(AUrl, nil, Headers);
    except
      Exit;
    end;
    if Resp = nil then
      Exit;
    AStatus := Resp.StatusCode;
    if AStatus <> 200 then
      Exit;
    try
      ABody := Resp.ContentAsString;
    except
      Exit;
    end;
    Result := ABody <> '';
  finally
    Client.Free;
  end;
end;

function FindShaUrl(Arr: TJSONArray; const AName: string): string;
var
  I: Integer;
  Item: TJSONObject;
begin
  Result := '';
  if Arr = nil then
    Exit;
  for I := 0 to Arr.Count - 1 do
  begin
    if not (Arr.Items[I] is TJSONObject) then
      Continue;
    Item := TJSONObject(Arr.Items[I]);
    if SameText(JsonStr(Item, 'name'), AName + '.sha256') then
      Exit(JsonStr(Item, 'browser_download_url'));
  end;
end;

function SizeMatches(AGot, AContentLen, AJsonSize: Int64): Boolean;
begin
  if (AGot <= 0) or (AGot > MAX_UPDATE_BYTES) then
    Exit(False);
  if AContentLen > MAX_UPDATE_BYTES then
    Exit(False);
  if AContentLen > 0 then
    Exit(AGot = AContentLen);
  if AJsonSize > 0 then
    Exit(AGot = AJsonSize);
  Result := False;
end;

function ParseSha(const AText: string): string;
var
  I, J, N: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if CharInSet(AText[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
    begin
      J := I;
      while (J <= Length(AText)) and
            CharInSet(AText[J], ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(J);
      N := J - I;
      if N = 64 then
        Exit(Copy(AText, I, 64));
      I := J;
    end
    else
      Inc(I);
  end;
end;

function HashOk(const AFile, AShaFile: string): Boolean;
var
  Want, Got, Text: string;
begin
  Result := False;
  try
    Text := TFile.ReadAllText(AShaFile, TEncoding.UTF8);
  except
    try
      Text := TFile.ReadAllText(AShaFile);
    except
      Exit;
    end;
  end;
  Want := ParseSha(Text);
  if Want = '' then
    Exit;
  try
    Got := THashSHA2.GetHashStringFromFile(AFile);
  except
    Exit;
  end;
  Result := SameText(Want, Got);
end;

function SafeRel(const AName: string; out ARel: string): Boolean;
begin
  ARel := StringReplace(AName, '/', '\', [rfReplaceAll]);
  Result := False;
  if ARel = '' then
    Exit;
  if (ARel[1] = '\') or (Pos(':', ARel) > 0) or (Pos('..', ARel) > 0) then
    Exit;
  Result := True;
end;

function ExtractSafe(const AZip, ADest: string): Boolean;
var
  Z: TZipFile;
  I: Integer;
  Rel, Full, Root: string;
  Stream: TStream;
  Header: TZipHeader;
  Fs: TFileStream;
  Wrote: Int64;
begin
  Result := False;
  Root := IncludeTrailingPathDelimiter(System.IOUtils.TPath.GetFullPath(ADest));
  TDirectory.CreateDirectory(ADest);
  Wrote := 0;
  Z := TZipFile.Create;
  try
    try
      Z.Open(AZip, zmRead);
      for I := 0 to Z.FileCount - 1 do
      begin
        if not SafeRel(Z.FileName[I], Rel) then
          Exit;
        if Rel[Length(Rel)] = '\' then
        begin
          Full := System.IOUtils.TPath.GetFullPath(System.IOUtils.TPath.Combine(ADest, Copy(Rel, 1, Length(Rel) - 1)));
          if not StartsText(Root, IncludeTrailingPathDelimiter(Full)) then
            Exit;
          TDirectory.CreateDirectory(Full);
          Continue;
        end;
        Full := System.IOUtils.TPath.GetFullPath(System.IOUtils.TPath.Combine(ADest, Rel));
        if not StartsText(Root, Full) then
          Exit;
        TDirectory.CreateDirectory(ExtractFilePath(Full));
        Stream := nil;
        Z.Read(I, Stream, Header, True);
        try
          Fs := TFileStream.Create(Full, fmCreate);
          try
            if (Stream <> nil) and (Stream.Size > 0) then
            begin
              Stream.Position := 0;
              Fs.CopyFrom(Stream, Stream.Size);
              Wrote := Wrote + Fs.Size;
              if Wrote > MAX_UPDATE_BYTES then
                Exit;
            end;
          finally
            Fs.Free;
          end;
        finally
          Stream.Free;
        end;
      end;
      Result := True;
    except
      Result := False;
    end;
  finally
    Z.Free;
    if not Result then
      WipeDir(ADest);
  end;
end;

function FindInnerExe(const ARoot: string): string;
var
  Files, Exes: TArray<string>;
  I: Integer;
  Best: string;
begin
  Result := '';
  if not TDirectory.Exists(ARoot) then
    Exit;
  Files := TDirectory.GetFiles(ARoot, '*', TSearchOption.soAllDirectories);
  Best := '';
  SetLength(Exes, 0);
  for I := 0 to High(Files) do
  begin
    if not EndsText('.exe', Files[I]) then
      Continue;
    if SameText(ExtractFileName(Files[I]), 'VibeCmd.exe') and
       ((Best = '') or (Length(Files[I]) < Length(Best))) then
      Best := Files[I];
    SetLength(Exes, Length(Exes) + 1);
    Exes[High(Exes)] := Files[I];
  end;
  if Best <> '' then
    Exit(Best);
  if Length(Exes) = 1 then
    Exit(Exes[0]);
  for I := 0 to High(Files) do
    if HasSig(Files[I], $4D, $5A) then
      Exit(Files[I]);
end;

function SwapBlocked: Boolean;
var
  I: Integer;
  F: TCommonCustomForm;
begin
  Result := FileOpHubCount > 0;
  if Result then
    Exit;
  for I := 0 to Screen.FormCount - 1 do
  begin
    F := Screen.Forms[I];
    if (F <> nil) and F.Visible and (Pos('Conflict', F.ClassName) > 0) then
      Exit(True);
  end;
end;

function DirWritable(const ADir: string): Boolean;
var
  P: string;
  Fs: TFileStream;
begin
  Result := False;
  P := System.IOUtils.TPath.Combine(ADir, 'VibeCmd.write.tmp');
  try
    Fs := TFileStream.Create(P, fmCreate);
    Fs.Free;
    TryDelete(P);
    Result := True;
  except
    Result := False;
  end;
end;

function PowerShellPath: string;
begin
  Result := System.IOUtils.TPath.Combine(GetEnvironmentVariable('SystemRoot'),
    'System32\WindowsPowerShell\v1.0\powershell.exe');
  if not TFile.Exists(Result) then
    Result := 'powershell.exe';
end;

function StartHelper(const ASrc, ADst: string; AElevate: Boolean): Boolean;
var
  Script, Params, Ps, Op: string;
  Code: NativeInt;
begin
  Result := False;
  if (ASrc = '') or (ADst = '') then
    Exit;
  if (Pos('"', ASrc) > 0) or (Pos('"', ADst) > 0) then
    Exit;
  Script := System.IOUtils.TPath.Combine(UpdateRoot, Format('apply-%d-%d.ps1',
    [GetCurrentProcessId, Integer(GetTickCount)]));
  if Pos('"', Script) > 0 then
    Exit;
  TFile.WriteAllText(Script, APPLY_PS, TEncoding.UTF8);
  Ps := PowerShellPath;
  Params := Format('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s" %d "%s" "%s"',
    [Script, GetCurrentProcessId, ASrc, ADst]);
  if AElevate then
    Op := 'runas'
  else
    Op := 'open';
  Code := NativeInt(ShellExecute(0, PChar(Op), PChar(Ps), PChar(Params), nil, SW_HIDE));
  Result := Code > 32;
  if not Result then
    TryDelete(Script);
end;

procedure RequestRestart;
begin
  TThread.ForceQueue(nil,
    procedure
    var
      I: Integer;
      F: TCommonCustomForm;
      WaitModal: Boolean;
    begin
      WaitModal := False;
      for I := Screen.FormCount - 1 downto 0 do
      begin
        F := Screen.Forms[I];
        if (F = nil) or (F = GMain) or (F = GOffer) or not F.Visible then
          Continue;
        if TFmxFormState.Modal in F.FormState then
        begin
          F.ModalResult := mrCancel;
          WaitModal := True;
        end
        else
          F.Close;
      end;
      if WaitModal then
        TThread.ForceQueue(nil,
          procedure
          begin
            if (GMain <> nil) and not (csDestroying in GMain.ComponentState) then
              GMain.Close;
          end)
      else if (GMain <> nil) and not (csDestroying in GMain.ComponentState) then
        GMain.Close;
    end);
end;

function FetchRelease(const AOwner, AName, AMask, ASkip: string; APre: Boolean;
  AInfo: TRelease): TCheckKind;
type
  TCand = record
    Tag, Title, Body, Published: string;
    AssetName, AssetUrl, ShaUrl: string;
    AssetSize: Int64;
    Ver: TVer;
  end;
var
  Url, Body: string;
  Status: Integer;
  Root: TJSONValue;
  Masks: TArray<string>;
  Cands: TArray<TCand>;
  Cur: TVer;
  SawGap: Boolean;

  procedure AddCand(O: TJSONObject);
  var
    C: TCand;
    Arr: TJSONArray;
    M, I: Integer;
    Item: TJSONObject;
    Name, Link: string;
    V: TJSONValue;
  begin
    if (O = nil) or JsonBool(O, 'draft') then
      Exit;
    if JsonBool(O, 'prerelease') and not APre then
      Exit;
    C.Tag := JsonStr(O, 'tag_name');
    if not ParseVer(C.Tag, C.Ver) then
      Exit;
    C.Title := JsonStr(O, 'name');
    C.Body := JsonStr(O, 'body');
    C.Published := JsonStr(O, 'published_at');
    C.AssetName := '';
    C.AssetUrl := '';
    C.ShaUrl := '';
    C.AssetSize := 0;
    V := O.GetValue('assets');
    if V is TJSONArray then
      Arr := TJSONArray(V)
    else
      Arr := nil;
    if Arr <> nil then
      for M := 0 to High(Masks) do
      begin
        if C.AssetUrl <> '' then
          Break;
        for I := 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[I] is TJSONObject) then
            Continue;
          Item := TJSONObject(Arr.Items[I]);
          Name := JsonStr(Item, 'name');
          if (Name = '') or EndsText('.sha256', Name) then
            Continue;
          if not WildMatch(Name, Masks[M]) then
            Continue;
          Link := JsonStr(Item, 'browser_download_url');
          if Link = '' then
            Continue;
          C.AssetName := Name;
          C.AssetUrl := Link;
          C.AssetSize := StrToInt64Def(JsonStr(Item, 'size'), 0);
          C.ShaUrl := FindShaUrl(Arr, Name);
          Break;
        end;
      end;
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := C;
  end;

  procedure SortCands;
  var
    I, J: Integer;
    C: TCand;
  begin
    for I := 1 to High(Cands) do
    begin
      C := Cands[I];
      J := I;
      while (J > 0) and (VerCmp(Cands[J - 1].Ver, C.Ver) < 0) do
      begin
        Cands[J] := Cands[J - 1];
        Dec(J);
      end;
      Cands[J] := C;
    end;
  end;

var
  I: Integer;
begin
  Result := ckFail;
  if not ParseVer(ExeFileVersion, Cur) then
    Exit;
  Masks := SplitMask(AMask);
  if Length(Masks) = 0 then
    Exit;
  if APre then
    Url := Format('https://api.github.com/repos/%s/%s/releases?per_page=20', [AOwner, AName])
  else
    Url := Format('https://api.github.com/repos/%s/%s/releases/latest', [AOwner, AName]);
  if not HttpString(Url, Status, Body) then
    Exit;
  Root := TJSONObject.ParseJSONValue(Body, True, False);
  if Root = nil then
    Exit;
  try
    SetLength(Cands, 0);
    if Root is TJSONArray then
    begin
      for I := 0 to TJSONArray(Root).Count - 1 do
        if TJSONArray(Root).Items[I] is TJSONObject then
          AddCand(TJSONObject(TJSONArray(Root).Items[I]));
    end
    else if Root is TJSONObject then
      AddCand(TJSONObject(Root));
  finally
    Root.Free;
  end;
  SortCands;
  SawGap := False;
  for I := 0 to High(Cands) do
  begin
    if VerCmp(Cands[I].Ver, Cur) <= 0 then
      Break;
    if SkipHas(ASkip, Cands[I].Tag) then
      Continue;
    if Cands[I].AssetUrl = '' then
    begin
      SawGap := True;
      Continue;
    end;
    AInfo.Tag := Cands[I].Tag;
    AInfo.Title := Cands[I].Title;
    AInfo.Body := Cands[I].Body;
    AInfo.Published := Cands[I].Published;
    AInfo.AssetName := Cands[I].AssetName;
    AInfo.AssetUrl := Cands[I].AssetUrl;
    AInfo.ShaUrl := Cands[I].ShaUrl;
    AInfo.AssetSize := Cands[I].AssetSize;
    Exit(ckNewer);
  end;
  if SawGap then
    Result := ckNoFile
  else
    Result := ckSame;
end;

procedure RememberCheck;
begin
  if not UpdateAlive or (GSettings = nil) then
    Exit;
  GSettings.UpdateLastCheck := FormatDateTime('yyyy-mm-dd', Date);
  try
    GSettings.SaveAsync;
  except
  end;
end;

procedure RememberSkip(const ATag: string);
begin
  if not UpdateAlive or (GSettings = nil) or (ATag = '') then
    Exit;
  if SkipHas(GSettings.UpdateSkip, ATag) then
    Exit;
  if GSettings.UpdateSkip = '' then
    GSettings.UpdateSkip := ATag
  else
    GSettings.UpdateSkip := GSettings.UpdateSkip + '|' + ATag;
  try
    GSettings.SaveAsync;
  except
  end;
end;

procedure ShowNote(const AText: string);
var
  T: TToast;
begin
  if not UpdateAlive or (AText = '') then
    Exit;
  if GToast <> nil then
  begin
    GToast.Free;
    GToast := nil;
  end;
  T := TToast.CreateNew(nil);
  try
    T.Init(AText);
  except
    T.Free;
    Exit;
  end;
  GToast := T;
  T.Show;
  LiftForm(T);
end;

procedure ShowOffer(AInfo: TRelease);
var
  F: TUpdateOffer;
begin
  if not UpdateAlive or (AInfo = nil) or (AInfo.AssetUrl = '') then
    Exit;
  if (GOffer <> nil) and GOffer.Busy then
    Exit;
  if GOffer <> nil then
  begin
    GOffer.Free;
    GOffer := nil;
  end;
  F := TUpdateOffer.CreateNew(nil);
  try
    F.Init(AInfo);
  except
    F.Free;
    Exit;
  end;
  GOffer := F;
  F.Show;
  LiftForm(F);
end;

procedure RunCheck(AManual: Boolean);
var
  Repo, Mask, Skip, Owner, Name: string;
  Pre: Boolean;
  Info: TRelease;
begin
  if not UpdateAlive or (GSettings = nil) then
    Exit;
  if TInterlocked.CompareExchange(GCheckBusy, 1, 0) <> 0 then
  begin
    if AManual then
      TInterlocked.Exchange(GManualWait, 1);
    Exit;
  end;
  TInterlocked.Exchange(GManualWait, 0);
  Repo := Trim(GSettings.UpdateRepo);
  Mask := Trim(GSettings.UpdateMask);
  Skip := GSettings.UpdateSkip;
  Pre := GSettings.UpdatePrerelease;
  if Repo = '' then
  begin
    TInterlocked.Exchange(GCheckBusy, 0);
    if AManual then
      ShowNote(L('upd.repoempty'));
    Exit;
  end;
  if not NormalizeRepo(Repo, Owner, Name) then
  begin
    RememberCheck;
    TInterlocked.Exchange(GCheckBusy, 0);
    if AManual then
      ShowNote(L('upd.fail'));
    Exit;
  end;
  Info := TRelease.Create;
  try
    TThread.CreateAnonymousThread(procedure
    var
      Kind: TCheckKind;
    begin
      Kind := ckFail;
      try
        Kind := FetchRelease(Owner, Name, Mask, Skip, Pre, Info);
      except
        Kind := ckFail;
      end;
      TThread.Queue(nil,
        procedure
        var
          WantNote: Boolean;
        begin
          try
            if not UpdateAlive then
              Exit;
            RememberCheck;
            WantNote := AManual or (TInterlocked.Exchange(GManualWait, 0) <> 0);
            if Kind = ckNewer then
              ShowOffer(Info)
            else if WantNote then
              case Kind of
                ckNoFile: ShowNote(L('upd.nofile'));
                ckSame: ShowNote(L('upd.latest'));
              else
                ShowNote(L('upd.fail'));
              end;
          finally
            Info.Free;
            TInterlocked.Exchange(GCheckBusy, 0);
          end;
        end);
    end).Start;
  except
    Info.Free;
    TInterlocked.Exchange(GCheckBusy, 0);
    if AManual then
      ShowNote(L('upd.fail'));
  end;
end;

procedure ArmAutoUpdate(AOwner: TCommonCustomForm; ASettings: TAppSettings);
begin
  if AOwner <> nil then
    GMain := AOwner;
  if ASettings <> nil then
    GSettings := ASettings;
  TInterlocked.Exchange(GAlive, 1);
  if TInterlocked.CompareExchange(GAutoQueued, 1, 0) <> 0 then
    Exit;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not UpdateAlive or (GSettings = nil) or not GSettings.UpdateAuto then
        Exit;
      if GSettings.UpdateLastCheck = FormatDateTime('yyyy-mm-dd', Date) then
        Exit;
      RunCheck(False);
    end);
end;

procedure CheckUpdatesNow(AOwner: TCommonCustomForm; ASettings: TAppSettings);
begin
  if AOwner <> nil then
    GMain := AOwner;
  if ASettings <> nil then
    GSettings := ASettings;
  TInterlocked.Exchange(GAlive, 1);
  RunCheck(True);
end;

procedure StopUpdate;
var
  F: TUpdateOffer;
  T: TToast;
begin
  TInterlocked.Exchange(GAlive, 0);
  TInterlocked.Increment(GEpoch);
  F := GOffer;
  GOffer := nil;
  if F <> nil then
    F.Free;
  T := GToast;
  GToast := nil;
  if T <> nil then
    T.Free;
end;

function TDownJob.Stopped: Boolean;
begin
  Result := (Epoch <> TInterlocked.CompareExchange(GEpoch, 0, 0)) or not UpdateAlive;
end;

procedure TDownJob.OnData(const Sender: TObject; AContentLength, AReadCount: Int64;
  var Abort: Boolean);
begin
  if Stopped or TooBig then
  begin
    Abort := True;
    Exit;
  end;
  if (AContentLength > MaxBytes) or (AReadCount > MaxBytes) then
  begin
    TooBig := True;
    Abort := True;
    Exit;
  end;
  if not WantProgress then
    Exit;
  if (AContentLength > 0) and (AReadCount < AContentLength) and
     (AReadCount - LastReport < 262144) then
    Exit;
  LastReport := AReadCount;
  PostProgress(JobId, AReadCount, AContentLength);
end;

function TDownJob.Download(const AUrl, ADest: string; AMax: Int64;
  AProgress: Boolean; out AStatus: Integer; out AContentLen: Int64): Boolean;
var
  Fs: TFileStream;
  Resp: IHTTPResponse;
begin
  Result := False;
  AStatus := 0;
  AContentLen := 0;
  TooBig := False;
  LastReport := 0;
  WantProgress := AProgress;
  MaxBytes := AMax;
  if Stopped then
    Exit;
  Fs := TFileStream.Create(ADest, fmCreate);
  try
    Client.OnReceiveData := OnData;
    try
      Resp := Client.Get(AUrl, Fs, nil);
    except
      Resp := nil;
    end;
    if Resp <> nil then
    begin
      AStatus := Resp.StatusCode;
      AContentLen := Resp.ContentLength;
    end;
    Result := (AStatus = 200) and not Stopped and not TooBig;
  finally
    Client.OnReceiveData := nil;
    Fs.Free;
  end;
  if not Result then
    TryDelete(ADest);
end;

procedure TDownJob.Run;
var
  Root, Part, Final, ShaPath, Unpack, ExePath, ErrKey: string;
  Status: Integer;
  CL, Got: Int64;
  Ok, Good, WasStop: Boolean;
  Path, Key: string;
  JobN: Integer;
begin
  Ok := False;
  ErrKey := 'upd.bad';
  ExePath := '';
  Unpack := '';
  Part := '';
  Final := '';
  JobN := JobId;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 8000;
    Client.ResponseTimeout := 600000;
    Client.HandleRedirects := True;
    Client.MaxRedirects := 5;
    Client.UserAgent := 'VibeCmd';
    try
      if not Stopped and (Expect <= MAX_UPDATE_BYTES) then
      begin
        Root := UpdateRoot;
        Final := System.IOUtils.TPath.Combine(Root, IntToStr(Epoch) + '-' + WorkName);
        Part := Final + '.part';
        TryDelete(Part);
        if not Download(Url, Part, MAX_UPDATE_BYTES, True, Status, CL) then
        begin
          if not Stopped then
            ErrKey := 'upd.fail';
        end
        else
        begin
          Got := FileLen(Part);
          if not SizeMatches(Got, CL, Expect) then
            TryDelete(Part)
          else
          begin
            TryDelete(Final);
            TFile.Move(Part, Final);
            Part := '';
            if ShaUrl <> '' then
            begin
              ShaPath := Final + '.sha256';
              if not Download(ShaUrl, ShaPath, 65536, False, Status, CL) or
                 not HashOk(Final, ShaPath) then
              begin
                TryDelete(ShaPath);
                TryDelete(Final);
                Final := '';
              end
              else
                TryDelete(ShaPath);
            end;
            if Final <> '' then
            begin
              if HasSig(Final, $50, $4B) then
              begin
                Unpack := System.IOUtils.TPath.Combine(Root, 'unpack-' + IntToStr(Epoch));
                WipeDir(Unpack);
                if not ExtractSafe(Final, Unpack) then
                begin
                  TryDelete(Final);
                  Final := '';
                end
                else
                begin
                  TryDelete(Final);
                  Final := '';
                  ExePath := FindInnerExe(Unpack);
                  if (ExePath = '') or not HasSig(ExePath, $4D, $5A) then
                  begin
                    WipeDir(Unpack);
                    ExePath := '';
                  end
                  else
                    Ok := True;
                end;
              end
              else if HasSig(Final, $4D, $5A) then
              begin
                ExePath := Final;
                Ok := True;
              end
              else
              begin
                TryDelete(Final);
                Final := '';
              end;
            end;
          end;
        end;
      end;
    except
      Ok := False;
      ErrKey := 'upd.bad';
      ExePath := '';
      TryDelete(Part);
      TryDelete(Final);
      if Unpack <> '' then
        WipeDir(Unpack);
    end;
  finally
    Client.Free;
    Client := nil;
  end;
  WasStop := Stopped;
  Good := Ok and (ExePath <> '') and not WasStop;
  if WasStop then
    Good := False;
  Path := ExePath;
  Key := ErrKey;
  TThread.Queue(nil,
    procedure
    begin
      if not UpdateAlive or (GOffer = nil) or (GOffer.FJobId <> JobN) then
      begin
        TryDelete(Path);
        Exit;
      end;
      GOffer.FinishDownload(Good, Path, Key, WasStop, JobN);
    end);
end;

procedure TUpdateOffer.Init(AInfo: TRelease);
var
  Root, Foot: TLayout;
begin
  FTag := AInfo.Tag;
  FUrl := AInfo.AssetUrl;
  FSha := AInfo.ShaUrl;
  FAsset := AInfo.AssetName;
  FSize := AInfo.AssetSize;
  FReady := '';
  FJobId := 0;
  FBusy := False;
  FInstalling := False;
  FColors := GetThemeColors(ActiveAppTheme);
  Width := 560;
  Height := 540;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Position := TFormPosition.MainFormCenter;
  OnClose := HandleClose;
  TrForm(Self, 'upd.title');
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := FColors.Background;

  Root := TLayout.Create(Self);
  Root.Parent := Self;
  Root.Align := TAlignLayout.Client;
  Root.Padding.Rect := TRectF.Create(18, 14, 18, 14);

  Foot := TLayout.Create(Self);
  Foot.Parent := Root;
  Foot.Align := TAlignLayout.Bottom;
  Foot.Height := 48;
  FBtnUpdate := CreateFluentButton(Self, Foot, '', L('upd.update'), fbkAccent, 130, UpdateClick);
  TrButton(FBtnUpdate, 'upd.update');
  FBtnLater := CreateFluentButton(Self, Foot, '', L('upd.later'), fbkSubtle, 110, LaterClick);
  TrButton(FBtnLater, 'upd.later');
  FBtnSkip := CreateFluentButton(Self, Foot, '', L('upd.skip'), fbkSubtle, 220, SkipClick);
  TrButton(FBtnSkip, 'upd.skip');
  FBtnCancel := CreateFluentButton(Self, Foot, '', L('upd.cancel'), fbkSubtle, 120, CancelClick);
  TrButton(FBtnCancel, 'upd.cancel');
  FBtnCancel.Visible := False;

  { Первый Align=Top остаётся сверху, каждый следующий встаёт сразу под ним. }
  FTitle := TText.Create(Self);
  FTitle.Parent := Root;
  FTitle.Align := TAlignLayout.Top;
  FTitle.Height := 30;
  FTitle.HitTest := False;
  ApplyFluentText(FTitle, 18, True);
  FTitle.TextSettings.FontColor := FColors.TextColor;
  TrText(FTitle, 'upd.title');

  FStatus := TText.Create(Self);
  FStatus.Parent := Root;
  FStatus.Align := TAlignLayout.Top;
  FStatus.Height := 40;
  FStatus.WordWrap := True;
  FStatus.HitTest := False;
  ApplyFluentText(FStatus, 13, False);
  FStatus.TextSettings.FontColor := FColors.DangerColor;
  FStatus.Text := '';

  FProg := TText.Create(Self);
  FProg.Parent := Root;
  FProg.Align := TAlignLayout.Top;
  FProg.Height := 22;
  FProg.HitTest := False;
  ApplyFluentText(FProg, 12, False);
  FProg.TextSettings.FontColor := FColors.SubTextColor;
  FProg.Text := '';

  FTrack := TRectangle.Create(Self);
  FTrack.Parent := Root;
  FTrack.Align := TAlignLayout.Top;
  FTrack.Height := 8;
  FTrack.Margins.Rect := TRectF.Create(0, 4, 0, 6);
  FTrack.XRadius := 4;
  FTrack.YRadius := 4;
  FTrack.Stroke.Kind := TBrushKind.None;
  FTrack.Fill.Color := FColors.ControlFill;
  FTrack.ClipChildren := True;
  FTrack.HitTest := False;
  FFill := TRectangle.Create(Self);
  FFill.Parent := FTrack;
  FFill.Align := TAlignLayout.Left;
  FFill.Width := 0;
  FFill.Stroke.Kind := TBrushKind.None;
  FFill.Fill.Color := FColors.SelectionColor;
  FFill.HitTest := False;

  FBody := TText.Create(Self);
  FBody.Parent := Root;
  FBody.Align := TAlignLayout.Top;
  FBody.Height := 180;
  FBody.WordWrap := True;
  FBody.HitTest := False;
  ApplyFluentText(FBody, 13, False);
  FBody.TextSettings.VertAlign := TTextAlign.Leading;
  FBody.TextSettings.FontColor := FColors.TextColor;
  FBody.Text := ShortBody(AInfo.Body);

  FWhen := TText.Create(Self);
  FWhen.Parent := Root;
  FWhen.Align := TAlignLayout.Top;
  FWhen.Height := 22;
  FWhen.HitTest := False;
  ApplyFluentText(FWhen, 12, False);
  FWhen.TextSettings.FontColor := FColors.SubTextColor;
  if DateOnly(AInfo.Published) <> '' then
    FWhen.Text := Lf('upd.when', [DateOnly(AInfo.Published)])
  else
    FWhen.Text := '';

  FHave := TText.Create(Self);
  FHave.Parent := Root;
  FHave.Align := TAlignLayout.Top;
  FHave.Height := 24;
  FHave.HitTest := False;
  ApplyFluentText(FHave, 14, False);
  FHave.TextSettings.FontColor := FColors.TextColor;
  FHave.Text := Lf('upd.have', [AInfo.Tag, ExeFileVersion]);
end;

procedure TUpdateOffer.DoShow;
begin
  inherited;
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  LiftForm(Self);
end;

procedure TUpdateOffer.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    Key := 0;
    LaterClick(nil);
    Exit;
  end;
  inherited;
end;

function TUpdateOffer.Busy: Boolean;
begin
  Result := FBusy or FInstalling;
end;

destructor TUpdateOffer.Destroy;
begin
  TInterlocked.Increment(GEpoch);
  if GOffer = Self then
    GOffer := nil;
  inherited;
end;

procedure TUpdateOffer.HandleClose(Sender: TObject; var Action: TCloseAction);
begin
  if FBusy then
  begin
    Action := TCloseAction.caNone;
    FCloseAfter := True;
    TInterlocked.Increment(GEpoch);
    Hide;
    Exit;
  end;
  Action := TCloseAction.caFree;
end;

procedure TUpdateOffer.ShowBusy;
begin
  FBusy := True;
  FBtnUpdate.Visible := False;
  FBtnLater.Visible := False;
  FBtnSkip.Visible := False;
  FBtnCancel.Visible := True;
  FStatus.Text := '';
  FFill.Width := 0;
  FProg.Text := '';
end;

procedure TUpdateOffer.ShowIdle;
begin
  FBusy := False;
  FBtnUpdate.Visible := True;
  FBtnUpdate.Enabled := True;
  FBtnLater.Visible := True;
  FBtnSkip.Visible := True;
  FBtnCancel.Visible := False;
end;

procedure TUpdateOffer.SetProgress(ARead, ATotal: Int64);
var
  P: Integer;
begin
  if (FTrack = nil) or (FFill = nil) or (FProg = nil) then
    Exit;
  if ATotal > 0 then
    P := Integer(EnsureRange(ARead * 100 div ATotal, Int64(0), Int64(100)))
  else
    P := 0;
  FProg.Text := Lf('upd.progress', [P]);
  if ATotal > 0 then
    FFill.Width := FTrack.Width * P / 100
  else
    FFill.Width := 0;
end;

procedure TUpdateOffer.LaterClick(Sender: TObject);
begin
  Close;
end;

procedure TUpdateOffer.SkipClick(Sender: TObject);
begin
  if FBusy then
    Exit;
  RememberSkip(FTag);
  Close;
end;

procedure TUpdateOffer.CancelClick(Sender: TObject);
begin
  FUserCancel := True;
  TInterlocked.Increment(GEpoch);
end;

procedure TUpdateOffer.StartDownload;
var
  J: TDownJob;
  Ep, Id: Integer;
begin
  if FBusy or FInstalling or (FUrl = '') then
    Exit;
  Ep := TInterlocked.Increment(GEpoch);
  Inc(FJobId);
  Id := FJobId;
  FReady := '';
  FUserCancel := False;
  FCloseAfter := False;
  ShowBusy;
  J := TDownJob.Create;
  J.Url := FUrl;
  J.ShaUrl := FSha;
  J.WorkName := SafeName(FAsset);
  J.Expect := FSize;
  J.Epoch := Ep;
  J.JobId := Id;
  TThread.CreateAnonymousThread(procedure
  begin
    try
      J.Run;
    finally
      J.Free;
    end;
  end).Start;
end;

procedure TUpdateOffer.UpdateClick(Sender: TObject);
begin
  if FBusy or FInstalling or not UpdateAlive then
    Exit;
  if FReady <> '' then
    TryInstall(FReady)
  else
    StartDownload;
end;

procedure TUpdateOffer.TryInstall(const APayload: string);
var
  Staged, Dir: string;
  Elevated, StagedCopy: Boolean;
begin
  if FInstalling or not UpdateAlive then
    Exit;
  if SwapBlocked then
  begin
    FStatus.Text := L('upd.busy');
    FReady := APayload;
    ShowIdle;
    Exit;
  end;
  if not TFile.Exists(APayload) or not HasSig(APayload, $4D, $5A) then
  begin
    FStatus.Text := L('upd.bad');
    FReady := '';
    TryDelete(APayload);
    ShowIdle;
    Exit;
  end;
  FInstalling := True;
  FBtnUpdate.Enabled := False;
  Dir := ExtractFilePath(ParamStr(0));
  Elevated := False;
  Staged := '';
  StagedCopy := False;
  if DirWritable(Dir) then
  begin
    Staged := System.IOUtils.TPath.Combine(Dir, 'VibeCmd.new.exe');
    try
      if not SameText(System.IOUtils.TPath.GetFullPath(APayload), System.IOUtils.TPath.GetFullPath(Staged)) then
      begin
        TFile.Copy(APayload, Staged, True);
        StagedCopy := True;
      end;
    except
      Staged := '';
    end;
    if (Staged <> '') and (FileLen(Staged) <> FileLen(APayload)) then
    begin
      if StagedCopy then
        TryDelete(Staged);
      Staged := '';
    end;
  end;
  if Staged = '' then
  begin
    Staged := APayload;
    if MessageDlg(L('upd.admin'), TMsgDlgType.mtConfirmation, mbYesNo, 0) <> mrYes then
    begin
      FInstalling := False;
      FReady := APayload;
      ShowIdle;
      Exit;
    end;
    Elevated := True;
  end
  else if StagedCopy then
    TryDelete(APayload);
  FReady := Staged;
  if not StartHelper(Staged, ParamStr(0), Elevated) then
  begin
    FInstalling := False;
    if not Elevated then
      FStatus.Text := L('upd.fail');
    ShowIdle;
    Exit;
  end;
  Hide;
  RequestRestart;
end;

procedure TUpdateOffer.FinishDownload(AOk: Boolean; const APath, AKey: string;
  AStopped: Boolean; AJob: Integer);
begin
  if AJob <> FJobId then
  begin
    TryDelete(APath);
    Exit;
  end;
  FBusy := False;
  if not UpdateAlive or AStopped or FCloseAfter or not Visible then
  begin
    TryDelete(APath);
    FReady := '';
    if FCloseAfter or not Visible or not UpdateAlive then
    begin
      TThread.ForceQueue(nil,
        procedure
        begin
          if GOffer <> nil then
            GOffer.Close;
        end);
      Exit;
    end;
    FUserCancel := False;
    ShowIdle;
    Exit;
  end;
  if not AOk then
  begin
    TryDelete(APath);
    FReady := '';
    FStatus.Text := L(AKey);
    ShowIdle;
    Exit;
  end;
  FReady := APath;
  TryInstall(APath);
end;

procedure TToast.Init(const AText: string);
var
  Colors: TThemeColors;
  Root: TLayout;
  Tx: TText;
  Timer: TTimer;
begin
  Width := 440;
  Height := 120;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Position := TFormPosition.MainFormCenter;
  Caption := 'V!BE CMD';
  OnClose := HandleClose;
  Colors := GetThemeColors(ActiveAppTheme);
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := Colors.Background;
  Root := TLayout.Create(Self);
  Root.Parent := Self;
  Root.Align := TAlignLayout.Client;
  Root.Padding.Rect := TRectF.Create(16, 12, 16, 12);
  Tx := TText.Create(Self);
  Tx.Parent := Root;
  Tx.Align := TAlignLayout.Client;
  Tx.WordWrap := True;
  Tx.HitTest := False;
  ApplyFluentText(Tx, 14, False);
  Tx.TextSettings.HorzAlign := TTextAlign.Leading;
  Tx.TextSettings.VertAlign := TTextAlign.Center;
  Tx.TextSettings.FontColor := Colors.TextColor;
  Tx.Text := AText;
  Timer := TTimer.Create(Self);
  Timer.Interval := 2200;
  Timer.OnTimer := Tick;
  Timer.Enabled := True;
end;

procedure TToast.DoShow;
begin
  inherited;
  ApplyNativeWindowChrome(FormToHWND(Self), GetThemeColors(ActiveAppTheme).IsDark);
  LiftForm(Self);
end;

procedure TToast.Tick(Sender: TObject);
begin
  if Sender is TTimer then
    TTimer(Sender).Enabled := False;
  Close;
end;

procedure TToast.HandleClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caFree;
end;

destructor TToast.Destroy;
begin
  if GToast = Self then
    GToast := nil;
  inherited;
end;

end.
