unit uHtmlThumb;

{
  Снимок HTML для плитки: тот же вид, что страница в QV, потом уменьшение.
  Скрипты включены. Чужой URL не грузим. Окно хоста остаётся за экраном.
  Кадр после NavigationCompleted и document.readyState, без общей паузы.
  500 мс только если страница рисует себя: canvas или requestAnimationFrame.
  Жёсткий край 2.5 с от Navigate. HtmlPageMs — аварийный край вызова, не сон.
}

interface

uses
  FMX.Graphics;

type
  { htkIcon — иконка, без повтора. htkEmpty — пустой кадр или ошибка навигации,
    плитка может заказать ещё раз. htkReady — кадр в ABitmap. }
  THtmlThumbKind = (htkIcon, htkEmpty, htkReady);

function IsHtmlPageThumbExt(const AExt: string): Boolean;
function RenderHtmlPageThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap; out AKind: THtmlThumbKind): Boolean;
procedure ShutdownHtmlThumbs;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils,
  System.Math, System.Types, System.UITypes, System.StrUtils,
  {$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.Messages, Winapi.ActiveX, Winapi.WebView2,
  Winapi.EdgeUtils,
  {$ENDIF}
  FMX.Types, FMX.Skia, System.Skia;

const
  HtmlThumbHost = 'vibe.thumb';
  HtmlViewW = 960;
  HtmlViewH = 720;
  { От Navigate. Дальше кадр, который есть, или отказ. }
  HtmlNavMs = 2500;
  { Потолок ожидания DOMContentLoaded / readyState, не от старта навигации. }
  HtmlDomMs = 1500;
  HtmlPollMs = 50;
  HtmlPaintMs = 500;
  { Аварийный край вызова при живом WebView. Удачный кадр его не ждёт. }
  HtmlPageMs = 4000;
  HtmlInitMs = 12000;
  HtmlCallerInitMs = 20000;
  HtmlMaxBytes = 2 * 1024 * 1024;
  HtmlProbeJs =
    '(function(){var p=false;try{if(document.querySelector("canvas"))p=true;' +
    'if(!p){var n=document.scripts,i,t;for(i=0;i<n.length;i++){t=n[i].text||"";' +
    'if(t.indexOf("requestAnimationFrame")>=0){p=true;break}}}}catch(e){}' +
    'return (document.readyState||"")+(p?"|paint":"|still")})()';
  HtmlStateJs = 'document.readyState';

function IsHtmlPageThumbExt(const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  Result := (E = '.htm') or (E = '.html') or (E = '.xhtml');
end;

function HtmlLooksMarked(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  I, N: Integer;
begin
  Result := False;
  if APath = '' then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(4096), FS.Size));
      if N < 1 then
        Exit;
      SetLength(Buf, N);
      FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
  except
    Exit(False);
  end;
  I := 0;
  if (N >= 3) and (Buf[0] = $EF) and (Buf[1] = $BB) and (Buf[2] = $BF) then
    I := 3;
  while (I < N) and (Buf[I] in [9, 10, 13, 32]) do
    Inc(I);
  Result := (I < N) and (Buf[I] = Ord('<'));
end;

{$IFDEF MSWINDOWS}

function PastTick(ADeadline: Cardinal): Boolean;
begin
  Result := Integer(GetTickCount - ADeadline) >= 0;
end;

procedure CoFreeStr(P: PWideChar);
begin
  if P <> nil then
    CoTaskMemFree(P);
end;

function EncodePathSegment(const S: string): string;
var
  B: TBytes;
  I: Integer;
begin
  B := TEncoding.UTF8.GetBytes(S);
  Result := '';
  for I := 0 to High(B) do
    if ((B[I] >= Ord('A')) and (B[I] <= Ord('Z'))) or
       ((B[I] >= Ord('a')) and (B[I] <= Ord('z'))) or
       ((B[I] >= Ord('0')) and (B[I] <= Ord('9'))) or
       (B[I] in [Ord('-'), Ord('.'), Ord('_'), Ord('~')]) then
      Result := Result + Char(B[I])
    else
      Result := Result + '%' + IntToHex(B[I], 2);
end;

type
  THtmlHost = class;

  THtmlEnvHandler = class(TInterfacedObject,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
  public
    Host: THtmlHost;
    function Invoke(errorCode: HResult;
      const createdEnv: ICoreWebView2Environment): HResult; stdcall;
  end;

  THtmlCtlHandler = class(TInterfacedObject,
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)
  public
    Host: THtmlHost;
    function Invoke(errorCode: HResult;
      const createdCtl: ICoreWebView2Controller): HResult; stdcall;
  end;

  THtmlNavHandler = class(TInterfacedObject,
    ICoreWebView2NavigationCompletedEventHandler)
  public
    Host: THtmlHost;
    Epoch: Integer;
    function Invoke(const sender: ICoreWebView2;
      const args: ICoreWebView2NavigationCompletedEventArgs): HResult; stdcall;
  end;

  THtmlStartHandler = class(TInterfacedObject,
    ICoreWebView2NavigationStartingEventHandler)
  public
    Host: THtmlHost;
    function Invoke(const sender: ICoreWebView2;
      const args: ICoreWebView2NavigationStartingEventArgs): HResult; stdcall;
  end;

  THtmlResHandler = class(TInterfacedObject,
    ICoreWebView2WebResourceRequestedEventHandler)
  public
    Host: THtmlHost;
    function Invoke(const sender: ICoreWebView2;
      const args: ICoreWebView2WebResourceRequestedEventArgs): HResult; stdcall;
  end;

  THtmlWinHandler = class(TInterfacedObject,
    ICoreWebView2NewWindowRequestedEventHandler)
  public
    function Invoke(const sender: ICoreWebView2;
      const args: ICoreWebView2NewWindowRequestedEventArgs): HResult; stdcall;
  end;

  THtmlCapHandler = class(TInterfacedObject,
    ICoreWebView2CapturePreviewCompletedHandler)
  public
    Host: THtmlHost;
    Epoch: Integer;
    function Invoke(errorCode: HResult): HResult; stdcall;
  end;

  THtmlScriptHandler = class(TInterfacedObject,
    ICoreWebView2ExecuteScriptCompletedHandler)
  public
    Host: THtmlHost;
    Epoch: Integer;
    function Invoke(errorCode: HResult; AJson: PWideChar): HResult; stdcall;
  end;

  THtmlDomHandler = class(TInterfacedObject,
    ICoreWebView2DOMContentLoadedEventHandler)
  public
    Host: THtmlHost;
    Epoch: Integer;
    function Invoke(const sender: ICoreWebView2;
      const args: ICoreWebView2DOMContentLoadedEventArgs): HResult; stdcall;
  end;

  THtmlHost = class(TThread)
  public
    FWork: TEvent;
    FFinished: TEvent;
    FStopped: TEvent;
    FReady: TEvent;
    FQuit: Boolean;
    FCancel: Integer;
    FNoWeb: Boolean;
    FEnvReady: Boolean;
    FOk: Boolean;
    FBlank: Boolean;
    FSignaled: Boolean;
    FPath: string;
    FW: Integer;
    FH: Integer;
    FOut: FMX.Graphics.TBitmap;
    FEpoch: Integer;
    FNavDone: Boolean;
    FNavOK: Boolean;
    FCapDone: Boolean;
    FCapOK: Boolean;
    FCapGen: Integer;
    FScriptDone: Boolean;
    FScriptOK: Boolean;
    FScriptGen: Integer;
    FScriptText: string;
    FDomDone: Boolean;
    FWnd: HWND;
    FEnv: ICoreWebView2Environment;
    FCtl: ICoreWebView2Controller;
    FWeb: ICoreWebView2;
    FCapStream: IStream;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
    function Cancelled: Boolean;
    function AllowUri(const AUri: string): Boolean;
    procedure SignalEnd;
    procedure Arm(const APath: string; AWidth, AHeight: Integer);
    function TakeBmp: FMX.Graphics.TBitmap;
  private
    FUserData: string;
    procedure Pump(ADeadline: Cardinal; const ADone: TFunc<Boolean>);
    function WaitBudget(AMs, ADeadline: Cardinal): Boolean;
    function EnsureEngine(ADeadline: Cardinal): Boolean;
    function GrabPng(out ABytes: TBytes): Boolean;
    function RunScript(const AJs: string; ADeadline: Cardinal;
      out AText: string): Boolean;
    function WaitReady(ADeadline: Cardinal): Boolean;
    procedure DoJob;
    function FitPng(const ABytes: TBytes): FMX.Graphics.TBitmap;
  end;

var
  GHtmlGate: TCriticalSection;
  GHtmlHost: THtmlHost;
  GHtmlBroken: Boolean;

function THtmlEnvHandler.Invoke(errorCode: HResult;
  const createdEnv: ICoreWebView2Environment): HResult;
begin
  if (Host <> nil) and Succeeded(errorCode) then
    Host.FEnv := createdEnv;
  Result := S_OK;
end;

function THtmlCtlHandler.Invoke(errorCode: HResult;
  const createdCtl: ICoreWebView2Controller): HResult;
begin
  if (Host <> nil) and Succeeded(errorCode) then
    Host.FCtl := createdCtl;
  Result := S_OK;
end;

function THtmlNavHandler.Invoke(const sender: ICoreWebView2;
  const args: ICoreWebView2NavigationCompletedEventArgs): HResult;
var
  Ok: Integer;
begin
  Ok := 0;
  if (Host <> nil) and (Epoch = Host.FEpoch) and (args <> nil) then
  begin
    args.Get_IsSuccess(Ok);
    Host.FNavOK := Ok <> 0;
    Host.FNavDone := True;
  end;
  Result := S_OK;
end;

function THtmlStartHandler.Invoke(const sender: ICoreWebView2;
  const args: ICoreWebView2NavigationStartingEventArgs): HResult;
var
  Uri: PWideChar;
  S: string;
begin
  Result := S_OK;
  if (Host = nil) or (args = nil) then
    Exit;
  Uri := nil;
  if Failed(args.Get_uri(Uri)) then
    Exit;
  S := string(Uri);
  CoFreeStr(Uri);
  if not Host.AllowUri(S) then
    args.Set_Cancel(1);
end;

function THtmlResHandler.Invoke(const sender: ICoreWebView2;
  const args: ICoreWebView2WebResourceRequestedEventArgs): HResult;
var
  Req: ICoreWebView2WebResourceRequest;
  Uri: PWideChar;
  S: string;
  Empty: IStream;
  Resp: ICoreWebView2WebResourceResponse;
begin
  Result := S_OK;
  if (Host = nil) or (args = nil) or (Host.FEnv = nil) then
    Exit;
  if Failed(args.Get_Request(Req)) or (Req = nil) then
    Exit;
  Uri := nil;
  if Failed(Req.Get_uri(Uri)) then
    Exit;
  S := string(Uri);
  CoFreeStr(Uri);
  if Host.AllowUri(S) then
    Exit;
  Empty := nil;
  Resp := nil;
  if Failed(CreateStreamOnHGlobal(0, True, Empty)) then
    Exit;
  if Succeeded(Host.FEnv.CreateWebResourceResponse(Empty, 403, 'blocked', '',
    Resp)) and (Resp <> nil) then
    args.Set_Response(Resp);
end;

function THtmlWinHandler.Invoke(const sender: ICoreWebView2;
  const args: ICoreWebView2NewWindowRequestedEventArgs): HResult;
begin
  if args <> nil then
    args.Set_Handled(1);
  Result := S_OK;
end;

function THtmlCapHandler.Invoke(errorCode: HResult): HResult;
begin
  if (Host <> nil) and (Epoch = Host.FCapGen) then
  begin
    Host.FCapOK := Succeeded(errorCode);
    Host.FCapDone := True;
  end;
  Result := S_OK;
end;

function THtmlScriptHandler.Invoke(errorCode: HResult; AJson: PWideChar): HResult;
begin
  if (Host <> nil) and (Epoch = Host.FScriptGen) then
  begin
    Host.FScriptOK := Succeeded(errorCode);
    if AJson <> nil then
      Host.FScriptText := string(AJson)
    else
      Host.FScriptText := '';
    Host.FScriptDone := True;
  end;
  Result := S_OK;
end;

function THtmlDomHandler.Invoke(const sender: ICoreWebView2;
  const args: ICoreWebView2DOMContentLoadedEventArgs): HResult;
begin
  if (Host <> nil) and (Epoch = Host.FEpoch) then
    Host.FDomDone := True;
  Result := S_OK;
end;

constructor THtmlHost.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWork := TEvent.Create(nil, False, False, '');
  FFinished := TEvent.Create(nil, True, False, '');
  FStopped := TEvent.Create(nil, True, False, '');
  FReady := TEvent.Create(nil, True, False, '');
end;

destructor THtmlHost.Destroy;
begin
  FWork.Free;
  FFinished.Free;
  FStopped.Free;
  FReady.Free;
  FOut.Free;
  inherited;
end;

function THtmlHost.Cancelled: Boolean;
begin
  Result := FQuit or (TInterlocked.CompareExchange(FCancel, 0, 0) <> 0);
end;

function THtmlHost.AllowUri(const AUri: string): Boolean;
begin
  Result := StartsText('https://' + HtmlThumbHost, AUri) or
    StartsText('http://' + HtmlThumbHost, AUri) or
    StartsText('about:', AUri) or StartsText('data:', AUri);
end;

procedure THtmlHost.SignalEnd;
begin
  if FSignaled then
    Exit;
  FSignaled := True;
  if not FOk then
    FreeAndNil(FOut);
  FFinished.SetEvent;
end;

procedure THtmlHost.Arm(const APath: string; AWidth, AHeight: Integer);
begin
  FSignaled := False;
  FOk := False;
  FBlank := False;
  FreeAndNil(FOut);
  FFinished.ResetEvent;
  TInterlocked.Exchange(FCancel, 0);
  FPath := APath;
  FW := AWidth;
  FH := AHeight;
  FWork.SetEvent;
end;

function THtmlHost.TakeBmp: FMX.Graphics.TBitmap;
begin
  Result := nil;
  if not FOk then
  begin
    FreeAndNil(FOut);
    Exit;
  end;
  Result := FOut;
  FOut := nil;
  FOk := False;
end;

procedure THtmlHost.Pump(ADeadline: Cardinal; const ADone: TFunc<Boolean>);
var
  Msg: TMsg;
  Dummy: THandle;
begin
  while not Cancelled do
  begin
    if Assigned(ADone) and ADone() then
      Exit;
    if PastTick(ADeadline) then
      Exit;
    Dummy := 0;
    MsgWaitForMultipleObjects(0, Dummy, False, 40, QS_ALLINPUT);
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      if Msg.message = WM_QUIT then
      begin
        FQuit := True;
        Exit;
      end;
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    if Assigned(ADone) and ADone() then
      Exit;
  end;
end;

function THtmlHost.WaitBudget(AMs, ADeadline: Cardinal): Boolean;
var
  Left, Slice: Cardinal;
begin
  Result := False;
  if Cancelled or PastTick(ADeadline) then
    Exit;
  Left := ADeadline - GetTickCount;
  if Integer(Left) <= 0 then
    Exit;
  if Left < AMs then
    Slice := Left
  else
    Slice := AMs;
  if Slice < 1 then
    Exit;
  Pump(GetTickCount + Slice, nil);
  Result := not Cancelled;
end;

function NearBlack(B, G, R: Byte): Boolean;
begin
  Result := (B <= 32) and (G <= 32) and (R <= 32);
end;

function LightPix(B, G, R: Byte): Boolean;
begin
  Result := (B >= 210) and (G >= 210) and (R >= 210);
end;

function PngIsEmpty(const ABytes: TBytes): Boolean;
var
  Img: ISkImage;
  Info: TSkImageInfo;
  Pix: TBytes;
  W, H, N, I, TopH, TopN, TopLight, RestN, RestBlack, Same: Integer;
  P: PByte;
  Bg, C: Cardinal;
begin
  Result := True;
  if Length(ABytes) < 8 then
    Exit;
  Img := TSkImage.MakeFromEncoded(ABytes);
  if (Img = nil) or (Img.Width < 8) or (Img.Height < 8) then
    Exit;
  W := Img.Width;
  H := Img.Height;
  Info := TSkImageInfo.Create(W, H, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
  SetLength(Pix, Int64(W) * H * 4);
  if not Img.ReadPixels(Info, @Pix[0], NativeUInt(W) * 4) then
    Exit;
  N := W * H;
  TopH := Max(8, H div 16);
  if TopH > H div 3 then
    TopH := H div 3;
  I := (TopH + (H - TopH) div 2) * W + (W div 2);
  if (I < 0) or (I >= N) then
    I := N div 2;
  P := @Pix[I * 4];
  Bg := Cardinal(P[0]) or (Cardinal(P[1]) shl 8) or (Cardinal(P[2]) shl 16);
  Same := 0;
  TopN := 0;
  TopLight := 0;
  RestN := 0;
  RestBlack := 0;
  P := @Pix[0];
  for I := 0 to N - 1 do
  begin
    C := Cardinal(P[0]) or (Cardinal(P[1]) shl 8) or (Cardinal(P[2]) shl 16);
    if C = Bg then
      Inc(Same);
    if I < TopH * W then
    begin
      Inc(TopN);
      if LightPix(P[0], P[1], P[2]) then
        Inc(TopLight);
    end
    else
    begin
      Inc(RestN);
      if NearBlack(P[0], P[1], P[2]) then
        Inc(RestBlack);
    end;
    Inc(P, 4);
  end;
  if (N > 0) and (Int64(Same) * 100 > Int64(N) * 97) then
    Exit;
  if (RestN > 0) and (TopN > 0) and
     (Int64(RestBlack) * 100 > Int64(RestN) * 97) and
     (Int64(TopLight) * 100 > Int64(TopN) * 20) and
     NearBlack(Byte(Bg), Byte(Bg shr 8), Byte(Bg shr 16)) then
    Exit;
  Result := False;
end;

function ScriptJsonStr(const ARaw: string): string;
var
  N: Integer;
begin
  Result := Trim(ARaw);
  N := Length(Result);
  if (N >= 2) and (Result[1] = '"') and (Result[N] = '"') then
    Result := Copy(Result, 2, N - 2);
end;

procedure SplitProbe(const ARaw: string; out AState: string; out APaint: Boolean);
var
  S: string;
  P: Integer;
begin
  S := ScriptJsonStr(ARaw);
  P := Pos('|', S);
  if P > 0 then
  begin
    AState := Copy(S, 1, P - 1);
    APaint := SameText(Copy(S, P + 1, MaxInt), 'paint');
  end
  else
  begin
    AState := S;
    APaint := False;
  end;
end;

function EarlierTick(A, B: Cardinal): Cardinal;
begin
  if Integer(A - B) <= 0 then
    Result := A
  else
    Result := B;
end;

function THtmlHost.GrabPng(out ABytes: TBytes): Boolean;
var
  CapObj: THtmlCapHandler;
  CapH: ICoreWebView2CapturePreviewCompletedHandler;
  Stat: TStatStg;
  Pos: LargeUInt;
  N: FixedUInt;
  Gen: Integer;
begin
  Result := False;
  SetLength(ABytes, 0);
  if Cancelled or (FWeb = nil) then
    Exit;
  FCapStream := nil;
  if Failed(CreateStreamOnHGlobal(0, True, FCapStream)) then
    Exit;
  Inc(FCapGen);
  Gen := FCapGen;
  FCapDone := False;
  FCapOK := False;
  CapObj := THtmlCapHandler.Create;
  CapObj.Host := Self;
  CapObj.Epoch := Gen;
  CapH := CapObj;
  if Failed(FWeb.CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG,
    FCapStream, CapH)) then
  begin
    FCapStream := nil;
    Exit;
  end;
  Pump(GetTickCount + 800,
    function: Boolean
    begin
      Result := FCapDone and (FCapGen = Gen);
    end);
  if Cancelled or (not FCapOK) or (FCapGen <> Gen) or (FCapStream = nil) then
  begin
    FCapStream := nil;
    Exit;
  end;
  try
    FillChar(Stat, SizeOf(Stat), 0);
    if Failed(FCapStream.Stat(Stat, STATFLAG_NONAME)) then
      Exit;
    if (Stat.cbSize < 8) or (Stat.cbSize > 16 * 1024 * 1024) then
      Exit;
    SetLength(ABytes, Integer(Stat.cbSize));
    Pos := 0;
    FCapStream.Seek(0, STREAM_SEEK_SET, Pos);
    N := 0;
    if Failed(FCapStream.Read(@ABytes[0], Length(ABytes), @N)) or (N < 8) then
    begin
      SetLength(ABytes, 0);
      Exit;
    end;
    if Integer(N) < Length(ABytes) then
      SetLength(ABytes, Integer(N));
    Result := True;
  finally
    FCapStream := nil;
  end;
end;

function THtmlHost.RunScript(const AJs: string; ADeadline: Cardinal;
  out AText: string): Boolean;
var
  Obj: THtmlScriptHandler;
  H: ICoreWebView2ExecuteScriptCompletedHandler;
  Gen: Integer;
begin
  Result := False;
  AText := '';
  if Cancelled or (FWeb = nil) or PastTick(ADeadline) or (AJs = '') then
    Exit;
  Inc(FScriptGen);
  Gen := FScriptGen;
  FScriptDone := False;
  FScriptOK := False;
  FScriptText := '';
  Obj := THtmlScriptHandler.Create;
  Obj.Host := Self;
  Obj.Epoch := Gen;
  H := Obj;
  if Failed(FWeb.ExecuteScript(PChar(AJs), H)) then
    Exit;
  Pump(ADeadline,
    function: Boolean
    begin
      Result := FScriptDone and (FScriptGen = Gen);
    end);
  if Cancelled or (not FScriptOK) or (FScriptGen <> Gen) then
    Exit;
  AText := FScriptText;
  Result := True;
end;

function THtmlHost.WaitReady(ADeadline: Cardinal): Boolean;
var
  Text, State: string;
  Paint: Boolean;
  Limit: Cardinal;
begin
  Text := '';
  State := '';
  Paint := False;
  if RunScript(HtmlProbeJs, ADeadline, Text) then
    SplitProbe(Text, State, Paint);
  if SameText(State, 'complete') then
    Exit(Paint);
  { interactive значит DOMContentLoaded уже был, даже если подписка опоздала. }
  if SameText(State, 'interactive') then
    FDomDone := True;
  Limit := EarlierTick(GetTickCount + HtmlDomMs, ADeadline);
  while (not Cancelled) and (not FDomDone) and (not SameText(State, 'complete')) and
        (not PastTick(Limit)) do
  begin
    if not WaitBudget(HtmlPollMs, Limit) then
      Break;
    if Cancelled or PastTick(Limit) then
      Break;
    if RunScript(HtmlStateJs, Limit, Text) then
    begin
      State := ScriptJsonStr(Text);
      if SameText(State, 'complete') or SameText(State, 'interactive') then
        Break;
    end;
  end;
  if Paint or Cancelled or PastTick(ADeadline) then
    Exit(Paint);
  if RunScript(HtmlProbeJs, ADeadline, Text) then
    SplitProbe(Text, State, Paint);
  Result := Paint;
end;

function THtmlHost.EnsureEngine(ADeadline: Cardinal): Boolean;
var
  Cls, Existing: TWndClass;
  EnvObj: THtmlEnvHandler;
  CtlObj: THtmlCtlHandler;
  StartObj: THtmlStartHandler;
  ResObj: THtmlResHandler;
  WinObj: THtmlWinHandler;
  EnvH: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
  CtlH: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
  StartH: ICoreWebView2NavigationStartingEventHandler;
  ResH: ICoreWebView2WebResourceRequestedEventHandler;
  WinH: ICoreWebView2NewWindowRequestedEventHandler;
  Settings: ICoreWebView2Settings;
  Ctl2: ICoreWebView2Controller2;
  Bounds: tagRECT;
  Loader: string;
  Color: COREWEBVIEW2_COLOR;
  Tok: EventRegistrationToken;
begin
  Result := FEnvReady and (FWeb <> nil);
  if Result or FNoWeb or Cancelled then
    Exit;
  Loader := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'WebView2Loader.dll';
  if TFile.Exists(Loader) then
    SetWebView2Path(Loader);
  if not IsEdgeAvailable then
  begin
    FNoWeb := True;
    Exit;
  end;
  if FWnd = 0 then
  begin
    FillChar(Cls, SizeOf(Cls), 0);
    Cls.lpfnWndProc := @DefWindowProc;
    Cls.hInstance := HInstance;
    Cls.lpszClassName := 'VibeHtmlThumbHost';
    if not GetClassInfo(HInstance, Cls.lpszClassName, Existing) then
      RegisterClass(Cls);
    FWnd := CreateWindowEx(WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE, 'VibeHtmlThumbHost',
      'vibe-html-thumb', WS_POPUP, -32000, -32000, HtmlViewW, HtmlViewH,
      0, 0, HInstance, nil);
    if FWnd = 0 then
    begin
      FNoWeb := True;
      Exit;
    end;
  end;
  FUserData := TPath.Combine(TPath.GetTempPath, 'vibecmd-html-thumb');
  try
    ForceDirectories(FUserData);
  except
    FNoWeb := True;
    Exit;
  end;
  EnvObj := THtmlEnvHandler.Create;
  EnvObj.Host := Self;
  EnvH := EnvObj;
  FEnv := nil;
  if Failed(CreateCoreWebView2EnvironmentWithOptions(nil, PChar(FUserData), nil,
    EnvH)) then
  begin
    FNoWeb := True;
    Exit;
  end;
  Pump(ADeadline,
    function: Boolean
    begin
      Result := FEnv <> nil;
    end);
  if (FEnv = nil) or Cancelled or PastTick(ADeadline) then
  begin
    if FEnv = nil then
      FNoWeb := True;
    Exit;
  end;
  CtlObj := THtmlCtlHandler.Create;
  CtlObj.Host := Self;
  CtlH := CtlObj;
  FCtl := nil;
  if Failed(FEnv.CreateCoreWebView2Controller(FWnd, CtlH)) then
  begin
    FNoWeb := True;
    Exit;
  end;
  Pump(ADeadline,
    function: Boolean
    begin
      Result := FCtl <> nil;
    end);
  if (FCtl = nil) or Cancelled then
  begin
    if FCtl = nil then
      FNoWeb := True;
    Exit;
  end;
  Bounds.Left := 0;
  Bounds.Top := 0;
  Bounds.Right := HtmlViewW;
  Bounds.Bottom := HtmlViewH;
  FCtl.Set_Bounds(Bounds);
  FCtl.Set_IsVisible(1);
  if Succeeded(FCtl.QueryInterface(ICoreWebView2Controller2, Ctl2)) and
     (Ctl2 <> nil) then
  begin
    Color.A := 255;
    Color.R := 255;
    Color.G := 255;
    Color.B := 255;
    Ctl2.Set_DefaultBackgroundColor(Color);
  end;
  if Failed(FCtl.Get_CoreWebView2(FWeb)) or (FWeb = nil) then
  begin
    FNoWeb := True;
    Exit;
  end;
  Settings := nil;
  if Succeeded(FWeb.Get_Settings(Settings)) and (Settings <> nil) then
  begin
    Settings.Set_IsScriptEnabled(1);
    Settings.Set_AreDefaultScriptDialogsEnabled(0);
    Settings.Set_IsWebMessageEnabled(0);
    Settings.Set_AreDevToolsEnabled(0);
    Settings.Set_IsStatusBarEnabled(0);
    Settings.Set_IsBuiltInErrorPageEnabled(0);
  end;
  StartObj := THtmlStartHandler.Create;
  StartObj.Host := Self;
  StartH := StartObj;
  Tok.value := 0;
  FWeb.add_NavigationStarting(StartH, Tok);
  ResObj := THtmlResHandler.Create;
  ResObj.Host := Self;
  ResH := ResObj;
  Tok.value := 0;
  FWeb.add_WebResourceRequested(ResH, Tok);
  FWeb.AddWebResourceRequestedFilter('*', COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  WinObj := THtmlWinHandler.Create;
  WinH := WinObj;
  Tok.value := 0;
  FWeb.add_NewWindowRequested(WinH, Tok);
  ShowWindow(FWnd, SW_SHOWNOACTIVATE);
  SetWindowPos(FWnd, HWND_BOTTOM, -32000, -32000, HtmlViewW, HtmlViewH,
    SWP_NOACTIVATE or SWP_NOOWNERZORDER);
  FEnvReady := True;
  Result := True;
end;

function THtmlHost.FitPng(const ABytes: TBytes): FMX.Graphics.TBitmap;
var
  Img: ISkImage;
  S, Dw, Dh, L, T: Single;
  R: TRectF;
  Bmp: FMX.Graphics.TBitmap;
begin
  Result := nil;
  if (Length(ABytes) < 8) or (FW < 8) or (FH < 8) then
    Exit;
  Img := TSkImage.MakeFromEncoded(ABytes);
  if (Img = nil) or (Img.Width < 1) or (Img.Height < 1) then
    Exit;
  Bmp := FMX.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(FW, FH);
    S := Min(FW / Img.Width, FH / Img.Height);
    Dw := Img.Width * S;
    Dh := Img.Height * S;
    L := (FW - Dw) / 2;
    T := (FH - Dh) / 2;
    R := RectF(L, T, L + Dw, T + Dh);
    Bmp.SkiaDraw(
      procedure(const C: ISkCanvas)
      begin
        C.Clear(TAlphaColors.White);
        C.DrawImageRect(Img, R, TSkSamplingOptions.Medium);
      end, True);
    if Bmp.Width > 0 then
    begin
      Result := Bmp;
      Bmp := nil;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure THtmlHost.DoJob;
var
  Deadline: Cardinal;
  Folder, Url: string;
  WV3: ICoreWebView2_3;
  WV2: ICoreWebView2_2;
  NavObj: THtmlNavHandler;
  NavH: ICoreWebView2NavigationCompletedEventHandler;
  DomObj: THtmlDomHandler;
  DomH: ICoreWebView2DOMContentLoadedEventHandler;
  Tok, DomTok: EventRegistrationToken;
  Bytes: TBytes;
  Epoch: Integer;
  Paint: Boolean;
begin
  if Cancelled or FNoWeb or (FPath = '') or (FW < 8) or (FH < 8) then
    Exit;
  Deadline := GetTickCount + HtmlInitMs;
  if not FEnvReady then
  begin
    if not EnsureEngine(Deadline) then
      Exit;
  end;
  if Cancelled or (FWeb = nil) then
    Exit;
  Inc(FEpoch);
  Epoch := FEpoch;
  FNavDone := False;
  FNavOK := False;
  FDomDone := False;
  FCapDone := False;
  FCapOK := False;
  Folder := ExcludeTrailingPathDelimiter(ExtractFileDir(FPath));
  if Folder = '' then
    Exit;
  if Length(Folder) = 2 then
    Folder := Folder + '\';
  if Failed(FWeb.QueryInterface(ICoreWebView2_3, WV3)) or (WV3 = nil) then
    Exit;
  WV3.ClearVirtualHostNameToFolderMapping(PChar(HtmlThumbHost));
  if Failed(WV3.SetVirtualHostNameToFolderMapping(PChar(HtmlThumbHost),
    PChar(Folder), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW)) then
    Exit;
  NavObj := THtmlNavHandler.Create;
  NavObj.Host := Self;
  NavObj.Epoch := Epoch;
  NavH := NavObj;
  Tok.value := 0;
  if Failed(FWeb.add_NavigationCompleted(NavH, Tok)) then
    Exit;
  DomTok.value := 0;
  WV2 := nil;
  DomH := nil;
  try
    if Succeeded(FWeb.QueryInterface(ICoreWebView2_2, WV2)) and (WV2 <> nil) then
    begin
      DomObj := THtmlDomHandler.Create;
      DomObj.Host := Self;
      DomObj.Epoch := Epoch;
      DomH := DomObj;
      if Failed(WV2.add_DOMContentLoaded(DomH, DomTok)) then
        DomTok.value := 0;
    end;
    Url := 'https://' + HtmlThumbHost + '/' + EncodePathSegment(ExtractFileName(FPath));
    Deadline := GetTickCount + HtmlNavMs;
    if Failed(FWeb.Navigate(PChar(Url))) then
    begin
      FBlank := True;
      Exit;
    end;
    Pump(Deadline,
      function: Boolean
      begin
        Result := FNavDone and (FEpoch = Epoch);
      end);
    if Cancelled or (FEpoch <> Epoch) then
      Exit;
    if not FNavOK then
    begin
      FBlank := True;
      Exit;
    end;
    Paint := False;
    if not PastTick(Deadline) then
      Paint := WaitReady(Deadline);
    if Paint and (not Cancelled) and (not PastTick(Deadline)) then
      WaitBudget(HtmlPaintMs, Deadline);
    if Cancelled or (FEpoch <> Epoch) then
      Exit;
    SetLength(Bytes, 0);
    if (not GrabPng(Bytes)) or PngIsEmpty(Bytes) then
    begin
      if not Cancelled then
        FBlank := True;
      Exit;
    end;
    FOut := FitPng(Bytes);
    FOk := (FOut <> nil) and (FOut.Width > 0) and not Cancelled;
    if not FOk then
    begin
      FreeAndNil(FOut);
      if not Cancelled then
        FBlank := True;
    end;
  finally
    if (WV2 <> nil) and (DomTok.value <> 0) then
      WV2.remove_DOMContentLoaded(DomTok);
    if (FWeb <> nil) and (Tok.value <> 0) then
      FWeb.remove_NavigationCompleted(Tok);
    FCapStream := nil;
  end;
end;

procedure THtmlHost.Execute;
var
  Msg: TMsg;
begin
  if Failed(CoInitializeEx(nil, COINIT_APARTMENTTHREADED)) then
  begin
    FNoWeb := True;
    FReady.SetEvent;
    FStopped.SetEvent;
    Exit;
  end;
  try
    PeekMessage(Msg, 0, 0, 0, PM_NOREMOVE);
    FReady.SetEvent;
    while not FQuit do
    begin
      if FWork.WaitFor(200) <> wrSignaled then
        Continue;
      if FQuit then
        Break;
      try
        DoJob;
      except
        FOk := False;
        FreeAndNil(FOut);
        if not Cancelled then
          FBlank := True;
      end;
      SignalEnd;
    end;
    if FCtl <> nil then
    begin
      try
        FCtl.Close;
      except
      end;
    end;
    FWeb := nil;
    FCtl := nil;
    FEnv := nil;
    if FWnd <> 0 then
    begin
      DestroyWindow(FWnd);
      FWnd := 0;
    end;
  finally
    CoUninitialize;
    FStopped.SetEvent;
  end;
end;

function EnsureHtmlHost: Boolean;
begin
  Result := False;
  if GHtmlBroken then
    Exit;
  if GHtmlHost = nil then
  begin
    GHtmlHost := THtmlHost.Create;
    GHtmlHost.Start;
  end;
  if GHtmlHost.FReady.WaitFor(3000) <> wrSignaled then
    Exit;
  Result := not GHtmlHost.FNoWeb;
  if GHtmlHost.FNoWeb then
    GHtmlBroken := True;
end;

{$ENDIF}

function RenderHtmlPageThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap; out AKind: THtmlThumbKind): Boolean;
{$IFDEF MSWINDOWS}
var
  WaitMs: Cardinal;
  Shot: FMX.Graphics.TBitmap;
  Sz: Int64;
{$ENDIF}
begin
  Result := False;
  AKind := htkIcon;
  if (ABitmap = nil) or (AWidth < 8) or (AHeight < 8) or (APath = '') then
    Exit;
  if not IsHtmlPageThumbExt(ExtractFileExt(APath)) then
    Exit;
  if not HtmlLooksMarked(APath) then
    Exit;
  {$IFDEF MSWINDOWS}
  try
    Sz := TFile.GetSize(APath);
  except
    Exit;
  end;
  if Sz > HtmlMaxBytes then
    Exit;
  if GHtmlBroken then
    Exit;
  if not EnsureHtmlHost then
    Exit;
  GHtmlGate.Enter;
  try
    if GHtmlBroken or (GHtmlHost = nil) or GHtmlHost.FQuit or GHtmlHost.FNoWeb then
      Exit;
    { Тёплый хост: HtmlPageMs только обрывает зависший снимок. Кадр приходит раньше. }
    if GHtmlHost.FEnvReady then
      WaitMs := HtmlPageMs
    else
      WaitMs := HtmlCallerInitMs;
    GHtmlHost.Arm(APath, AWidth, AHeight);
    if GHtmlHost.FFinished.WaitFor(WaitMs) <> wrSignaled then
    begin
      TInterlocked.Exchange(GHtmlHost.FCancel, 1);
      if GHtmlHost.FFinished.WaitFor(1500) <> wrSignaled then
      begin
        GHtmlBroken := True;
        Exit;
      end;
      Shot := GHtmlHost.TakeBmp;
      if Assigned(Shot) and (Shot.Width > 0) then
      begin
        try
          ABitmap.Assign(Shot);
          Result := ABitmap.Width > 0;
          if Result then
            AKind := htkReady;
        finally
          Shot.Free;
        end;
        Exit;
      end;
      if not GHtmlHost.FNoWeb then
        AKind := htkEmpty;
      Exit;
    end;
    if GHtmlHost.FNoWeb then
      GHtmlBroken := True;
    Shot := GHtmlHost.TakeBmp;
    if Assigned(Shot) and (Shot.Width > 0) then
    begin
      try
        ABitmap.Assign(Shot);
        Result := ABitmap.Width > 0;
        if Result then
          AKind := htkReady
        else if GHtmlHost.FBlank then
          AKind := htkEmpty;
      finally
        Shot.Free;
      end;
      Exit;
    end;
    if GHtmlHost.FBlank then
      AKind := htkEmpty;
  finally
    GHtmlGate.Leave;
  end;
  {$ELSE}
  if APath = '' then
    Exit;
  {$ENDIF}
end;

procedure ShutdownHtmlThumbs;
begin
  {$IFDEF MSWINDOWS}
  if GHtmlHost = nil then
    Exit;
  { Сначала отмена, без замка: снимок сам держит замок, пока ждёт поток. }
  GHtmlHost.FQuit := True;
  TInterlocked.Exchange(GHtmlHost.FCancel, 1);
  GHtmlHost.FWork.SetEvent;
  if (GHtmlGate = nil) or not GHtmlGate.TryEnter then
    Exit;
  try
    if (GHtmlHost <> nil) and
       (GHtmlHost.FStopped.WaitFor(0) = wrSignaled) then
      FreeAndNil(GHtmlHost);
  finally
    GHtmlGate.Leave;
  end;
  {$ENDIF}
end;

initialization
  {$IFDEF MSWINDOWS}
  GHtmlGate := TCriticalSection.Create;
  {$ENDIF}

finalization
  ShutdownHtmlThumbs;
  {$IFDEF MSWINDOWS}
  FreeAndNil(GHtmlGate);
  {$ENDIF}

end.
