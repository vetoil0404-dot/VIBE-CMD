unit uMpvPlayer;

{
  QV media: MFPlay без libmpv.
  Видео — дочернее окно формы, вписанное в область QV с сохранением пропорций.
  Аудио — без окна, при необходимости MCI для wav/wma.
}

interface

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;

function MpvAvailable: Boolean;
function MpvExportClip(const ASrc, ADst: string; AStart, AEnd: Double;
  AVideo: Boolean; out AError: string): Boolean;

type
  TMpvSession = class
  private
    FPlayer: IUnknown;
    FWnd: HWND;
    FOwner: HWND;
    FOwnWnd: Boolean;
    FShowVideo: Boolean;
    FWantVisible: Boolean;
    FMci: Boolean;
    FCoInit: Boolean;
    FLastPos: Double;
    FLastDur: Double;
    FArSet: Boolean;
    FLastBounds: TRect;
    function EnsureCom: Boolean;
    function AsPlayer(out P: IUnknown): Boolean;
    function Mci(const ACmd: string): Boolean;
    function MciStat(const ACmd: string): string;
    function DoMciLoad(const APath: string): Boolean;
    procedure ShutdownMci;
    function CreateHost(AOwner: HWND): Boolean;
    function DoMfLoad(const APath: string): Boolean;
    procedure ShutdownMf;
    procedure ApplyVisible;
    procedure SafeUpdateVideo(P: IUnknown; ASetAr: Boolean);
  public
    destructor Destroy; override;
    function Attach(AOwnerWnd: HWND): Boolean;
    function AttachVideoWindow(AVideoWnd: HWND): Boolean;
    function LoadFile(const APath: string; AShowVideo: Boolean = True): Boolean;
    procedure Stop;
    procedure SetPaused(APaused: Boolean);
    function Paused: Boolean;
    procedure TogglePause;
    function Duration: Double;
    function Position: Double;
    procedure Seek(ASeconds: Double);
    procedure SetBoundsScreen(const ARect: TRect);
    procedure NotifyLayout;
    procedure Pump;
    function Active: Boolean;
    function HasEngine: Boolean;
  end;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils, System.Math,
  Winapi.Messages, Winapi.ActiveX, uMetaCache;

function mciSendStringW(Cmd, Ret: PWideChar; RetLen: UINT; Cb: HWND): UINT; stdcall;
  external 'winmm.dll' name 'mciSendStringW';

const
  MF_VERSION     = $20070;
  MFSTARTUP_LITE = 1;
  MFP_POS_100NS: TGUID = '{00000000-0000-0000-0000-000000000000}';
  MFP_STATE_PAUSED = 3;
  MFP_OPTION_NONE = 0;
  MFVideoARMode_PreservePicture = 1;
  CLASS_NAME: PChar = 'VibeMediaHost3';

type
  { IID из mfplay.h: a714590a-58af-430a-85bf-44f5ec838d85.
    Слоты после GetState обязательны, иначе SetAspectRatioMode попадает мимо. }
  IMFPMediaPlayer = interface(IUnknown)
    ['{A714590A-58AF-430A-85BF-44F5EC838D85}']
    function Play: HResult; stdcall;
    function Pause: HResult; stdcall;
    function Stop: HResult; stdcall;
    function FrameStep: HResult; stdcall;
    function SetPosition(const guidPositionType: TGUID; pvPosition: Pointer): HResult; stdcall;
    function GetPosition(const guidPositionType: TGUID; pvPosition: Pointer): HResult; stdcall;
    function GetDuration(const guidPositionType: TGUID; pvDuration: Pointer): HResult; stdcall;
    function SetRate(flRate: Single): HResult; stdcall;
    function GetRate(pflRate: Pointer): HResult; stdcall;
    function GetSupportedRates(fForward: BOOL; pSlow: Pointer; pFast: Pointer): HResult; stdcall;
    function GetState(out peState: UINT32): HResult; stdcall;
    function CreateMediaItemFromURL(pwszURL: PWideChar; fSync: BOOL; dwUserData: NativeUInt;
      ppMediaItem: Pointer): HResult; stdcall;
    function CreateMediaItemFromObject(pObj: IUnknown; fSync: BOOL; dwUserData: NativeUInt;
      ppMediaItem: Pointer): HResult; stdcall;
    function SetMediaItem(pItem: IUnknown): HResult; stdcall;
    function ClearMediaItem: HResult; stdcall;
    function GetMediaItem(ppItem: Pointer): HResult; stdcall;
    function GetVolume(pflVolume: Pointer): HResult; stdcall;
    function SetVolume(flVolume: Single): HResult; stdcall;
    function GetBalance(pflBalance: Pointer): HResult; stdcall;
    function SetBalance(flBalance: Single): HResult; stdcall;
    function GetMute(pfMute: Pointer): HResult; stdcall;
    function SetMute(fMute: BOOL): HResult; stdcall;
    function GetNativeVideoSize(pszVideo, pszAR: Pointer): HResult; stdcall;
    function GetIdealVideoSize(pszMin, pszMax: Pointer): HResult; stdcall;
    function SetVideoSourceRect(pnrc: Pointer): HResult; stdcall;
    function GetVideoSourceRect(pnrc: Pointer): HResult; stdcall;
    function SetAspectRatioMode(dwMode: DWORD): HResult; stdcall;
    function GetAspectRatioMode(pdwMode: Pointer): HResult; stdcall;
    function GetVideoWindow(phwnd: Pointer): HResult; stdcall;
    function UpdateVideo: HResult; stdcall;
    function SetBorderColor(Clr: COLORREF): HResult; stdcall;
    function GetBorderColor(pClr: Pointer): HResult; stdcall;
    function InsertEffect(pEffect: IUnknown; fOptional: BOOL): HResult; stdcall;
    function RemoveEffect(pEffect: IUnknown): HResult; stdcall;
    function RemoveAllEffects: HResult; stdcall;
    function Shutdown: HResult; stdcall;
  end;

  TMFStartup = function(Version: ULONG; dwFlags: DWORD): HResult; stdcall;
  TMFShutdown = function: HResult; stdcall;
  TMFPCreateMediaPlayer = function(pwszURL: PWideChar; fStartPlayback: BOOL;
    creationOptions: DWORD; pCallback: Pointer; hWnd: HWND;
    out ppMediaPlayer: Pointer): HResult; stdcall;

var
  GLock: TCriticalSection;
  GClassAtom: ATOM = 0;
  GMfPlay: HMODULE = 0;
  GMfPlat: HMODULE = 0;
  GMfTried: Boolean = False;
  GMfOk: Boolean = False;
  MFStartup: TMFStartup = nil;
  MFShutdown: TMFShutdown = nil;
  MFPCreateMediaPlayer: TMFPCreateMediaPlayer = nil;

procedure MediaLog(const S: string);
begin
  OutputDebugString(PChar('VIBE media  ' + S));
end;

procedure EnsureMf;
begin
  GLock.Enter;
  try
    if GMfTried then
      Exit;
    GMfTried := True;
    GMfPlat := LoadLibrary(PChar('mfplat.dll'));
    GMfPlay := LoadLibrary(PChar('mfplay.dll'));
    if (GMfPlat = 0) or (GMfPlay = 0) then
      Exit;
    @MFStartup := GetProcAddress(GMfPlat, 'MFStartup');
    @MFShutdown := GetProcAddress(GMfPlat, 'MFShutdown');
    @MFPCreateMediaPlayer := GetProcAddress(GMfPlay, 'MFPCreateMediaPlayer');
    if not Assigned(MFStartup) or not Assigned(MFPCreateMediaPlayer) then
      Exit;
    if Failed(MFStartup(MF_VERSION, MFSTARTUP_LITE)) then
      if Failed(MFStartup(MF_VERSION, 0)) then
        Exit;
    GMfOk := True;
    MediaLog('MFPlay ready');
  finally
    GLock.Leave;
  end;
end;

function MpvAvailable: Boolean;
begin
  EnsureMf;
  Result := GMfOk;
end;

function OverlayWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  PS: TPaintStruct;
begin
  case Msg of
    Winapi.Messages.WM_ERASEBKGND:
      Exit(1);
    Winapi.Messages.WM_PAINT:
      begin
        BeginPaint(Wnd, PS);
        EndPaint(Wnd, PS);
        Exit(0);
      end;
    Winapi.Messages.WM_NCHITTEST:
      Exit(HTTRANSPARENT);
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure EnsureClass;
var
  WC: WNDCLASS;
begin
  if GClassAtom <> 0 then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.style := CS_HREDRAW or CS_VREDRAW;
  WC.lpfnWndProc := @OverlayWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := GetStockObject(BLACK_BRUSH);
  WC.lpszClassName := CLASS_NAME;
  GClassAtom := Winapi.Windows.RegisterClass(WC);
  if GClassAtom = 0 then
    GClassAtom := 1;
end;

function TMpvSession.EnsureCom: Boolean;
var
  Hr: HResult;
begin
  if FCoInit then
    Exit(True);
  Hr := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  if Succeeded(Hr) or (Hr = HResult($00000001)) or (Hr = HResult($80010106)) then
  begin
    FCoInit := Succeeded(Hr) or (Hr = HResult($00000001));
    Exit(True);
  end;
  Result := False;
end;

function TMpvSession.AsPlayer(out P: IUnknown): Boolean;
begin
  P := FPlayer;
  Result := P <> nil;
end;

function PlayerOf(P: IUnknown): IMFPMediaPlayer;
begin
  Result := nil;
  if P = nil then
    Exit;
  try
    Result := P as IMFPMediaPlayer;
  except
    Result := nil;
  end;
  if Result = nil then
    Supports(P, IMFPMediaPlayer, Result);
end;

procedure TMpvSession.SafeUpdateVideo(P: IUnknown; ASetAr: Boolean);
var
  MP: IMFPMediaPlayer;
begin
  if not FShowVideo then
    Exit;
  MP := PlayerOf(P);
  if MP = nil then
    Exit;
  try
    if ASetAr and not FArSet then
    begin
      if Succeeded(MP.SetAspectRatioMode(MFVideoARMode_PreservePicture)) then
        FArSet := True;
    end;
    MP.UpdateVideo;
  except
  end;
end;

function TMpvSession.CreateHost(AOwner: HWND): Boolean;
begin
  Result := False;
  if AOwner = 0 then
    Exit;
  EnsureClass;
  if FOwnWnd and (FWnd <> 0) and IsWindow(FWnd) then
  begin
    if (GetWindowLong(FWnd, GWL_STYLE) and WS_CHILD) <> 0 then
    begin
      Result := True;
      Exit;
    end;
    DestroyWindow(FWnd);
    FWnd := 0;
  end;
  FWnd := CreateWindowEx(
    WS_EX_NOACTIVATE,
    CLASS_NAME, nil,
    WS_CHILD or WS_CLIPCHILDREN or WS_CLIPSIBLINGS,
    0, 0, 32, 32, AOwner, 0, HInstance, nil);
  if FWnd = 0 then
  begin
    MediaLog('CreateHost failed ' + IntToStr(GetLastError));
    Exit;
  end;
  FOwnWnd := True;
  ShowWindow(FWnd, SW_HIDE);
  Result := True;
end;

procedure TMpvSession.ApplyVisible;
begin
  if (FWnd = 0) or not IsWindow(FWnd) then
    Exit;
  if FWantVisible and FShowVideo then
    ShowWindow(FWnd, SW_SHOWNOACTIVATE)
  else
    ShowWindow(FWnd, SW_HIDE);
end;

procedure TMpvSession.ShutdownMf;
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
begin
  P := FPlayer;
  FPlayer := nil;
  FArSet := False;
  FillChar(FLastBounds, SizeOf(FLastBounds), 0);
  if P = nil then
    Exit;
  try
    MP := PlayerOf(P);
    if MP <> nil then
      MP.Stop;
  except
  end;
  P := nil;
end;

function TMpvSession.DoMfLoad(const APath: string): Boolean;
var
  Raw: Pointer;
  Hr: HResult;
  Url: string;
  Unk: IUnknown;
  Opts: DWORD;
  VideoWnd: HWND;
  MP: IMFPMediaPlayer;
begin
  Result := False;
  Raw := nil;
  ShutdownMf;
  FLastPos := 0;
  FLastDur := 0;
  FArSet := False;
  if not EnsureCom then
    Exit;
  EnsureMf;
  if not GMfOk or not Assigned(MFPCreateMediaPlayer) then
    Exit;
  if (APath = '') or not FileExists(APath) then
    Exit;

  Url := APath;
  if (Pos('#', Url) > 0) or (Pos('?', Url) > 0) then
    Url := 'file:///' + StringReplace(Url, '\', '/', [rfReplaceAll]);

  if FShowVideo then
  begin
    if (FWnd = 0) or not IsWindow(FWnd) then
    begin
      MediaLog('video hwnd missing');
      Exit;
    end;
    VideoWnd := FWnd;
    Opts := MFP_OPTION_NONE;
  end
  else
  begin
    VideoWnd := 0;
    Opts := MFP_OPTION_NONE;
  end;

  try
    Hr := MFPCreateMediaPlayer(PWideChar(Url), True, Opts, nil, VideoWnd, Raw);
  except
    Exit;
  end;

  if Failed(Hr) or (Raw = nil) then
  begin
    MediaLog(Format('MFPCreate hr=0x%x %s', [Cardinal(Hr), ExtractFileName(APath)]));
    Exit;
  end;

  Pointer(Unk) := Raw;
  FPlayer := Unk;
  Unk := nil;
  if FShowVideo then
  begin
    MP := PlayerOf(FPlayer);
    if MP <> nil then
    try
      if Succeeded(MP.SetAspectRatioMode(MFVideoARMode_PreservePicture)) then
        FArSet := True;
      MP.UpdateVideo;
    except
    end;
  end;
  MediaLog('MFPlay ok ' + ExtractFileName(APath));
  Result := True;
end;

function TMpvSession.Mci(const ACmd: string): Boolean;
begin
  Result := mciSendStringW(PWideChar(ACmd), nil, 0, 0) = 0;
end;

function TMpvSession.MciStat(const ACmd: string): string;
var
  Buf: array[0..127] of WideChar;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  if mciSendStringW(PWideChar(ACmd), @Buf[0], 128, 0) = 0 then
    Result := Trim(string(Buf))
  else
    Result := '';
end;

procedure TMpvSession.ShutdownMci;
begin
  if not FMci then
    Exit;
  try
    Mci('stop vibeaudio');
    Mci('close vibeaudio');
  except
  end;
  FMci := False;
end;

function TMpvSession.DoMciLoad(const APath: string): Boolean;
var
  Q, Ext: string;
begin
  Result := False;
  ShutdownMci;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.wav') and (Ext <> '.wma') then
    Exit;
  Q := StringReplace(APath, '"', '', [rfReplaceAll]);
  Result := Mci(Format('open "%s" type waveaudio alias vibeaudio wait', [Q]));
  if not Result then
    Result := Mci(Format('open "%s" alias vibeaudio wait', [Q]));
  if not Result then
    Exit;
  FMci := True;
  Mci('set vibeaudio time format milliseconds wait');
  Result := Mci('play vibeaudio');
  if not Result then
    ShutdownMci;
end;

destructor TMpvSession.Destroy;
begin
  FWantVisible := False;
  try
    ShutdownMci;
  except
  end;
  try
    ShutdownMf;
  except
  end;
  if FOwnWnd and (FWnd <> 0) and IsWindow(FWnd) then
    DestroyWindow(FWnd);
  FWnd := 0;
  if FCoInit then
  try
    CoUninitialize;
  except
  end;
  FCoInit := False;
  inherited;
end;

function TMpvSession.Attach(AOwnerWnd: HWND): Boolean;
begin
  FOwner := AOwnerWnd;
  Result := True;
end;

function TMpvSession.AttachVideoWindow(AVideoWnd: HWND): Boolean;
begin
  ShutdownMf;
  if FOwnWnd and (FWnd <> 0) and IsWindow(FWnd) then
    DestroyWindow(FWnd);
  FOwnWnd := False;
  FWnd := 0;
  FillChar(FLastBounds, SizeOf(FLastBounds), 0);
  if (AVideoWnd <> 0) and IsWindow(AVideoWnd) then
  begin
    FWnd := AVideoWnd;
    Result := True;
  end
  else
    Result := False;
end;

function TMpvSession.LoadFile(const APath: string; AShowVideo: Boolean): Boolean;
begin
  Result := False;
  if APath = '' then
    Exit;
  FShowVideo := AShowVideo;
  try
    ShutdownMf;
  except
  end;
  try
    ShutdownMci;
  except
  end;

  if not AShowVideo then
  begin
    FWantVisible := False;
    ApplyVisible;
    if DoMfLoad(APath) then
      Exit(True);
    if DoMciLoad(APath) then
      Exit(True);
    Exit;
  end;

  if FOwner <> 0 then
    CreateHost(FOwner);
  if (FWnd = 0) or not IsWindow(FWnd) then
  begin
    MediaLog('no host for video, fallback audio');
    FShowVideo := False;
    if DoMfLoad(APath) then
      Exit(True);
    Exit;
  end;

  FWantVisible := True;
  ApplyVisible;
  if DoMfLoad(APath) then
    Exit(True);

  FWantVisible := False;
  ApplyVisible;
  FShowVideo := False;
  if DoMfLoad(APath) then
    Exit(True);
end;

procedure TMpvSession.Stop;
begin
  FWantVisible := False;
  try
    ShutdownMci;
  except
  end;
  try
    ShutdownMf;
  except
  end;
  ApplyVisible;
  FLastPos := 0;
  FLastDur := 0;
end;

procedure TMpvSession.SetPaused(APaused: Boolean);
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
begin
  if FMci then
  begin
    if APaused then
      Mci('pause vibeaudio')
    else if not Mci('resume vibeaudio') then
      Mci('play vibeaudio');
    Exit;
  end;
  if not AsPlayer(P) then
    Exit;
  MP := PlayerOf(P);
  if MP = nil then
    Exit;
  try
    if APaused then
      MP.Pause
    else
      MP.Play;
  except
  end;
end;

function TMpvSession.Paused: Boolean;
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
  St: UINT32;
begin
  Result := False;
  if FMci then
    Exit(Pos('paused', LowerCase(MciStat('status vibeaudio mode'))) > 0);
  if not AsPlayer(P) then
    Exit;
  MP := PlayerOf(P);
  if MP = nil then
    Exit;
  try
    St := 0;
    if Succeeded(MP.GetState(St)) then
      Result := St = MFP_STATE_PAUSED;
  except
  end;
end;

procedure TMpvSession.TogglePause;
begin
  SetPaused(not Paused);
end;

function PropToSec(const Pv: TPropVariant): Double;
begin
  Result := 0;
  try
    case Pv.vt of
      VT_I8:
        Result := Pv.hVal.QuadPart / 1.0e7;
      VT_UI8:
        Result := Pv.uhVal.QuadPart / 1.0e7;
      VT_R8:
        Result := Pv.dblVal;
      VT_I4:
        if Pv.lVal > 0 then
          Result := Pv.lVal / 1.0e7;
      VT_UI4:
        if Pv.ulVal > 0 then
          Result := Pv.ulVal / 1.0e7;
    end;
  except
  end;
end;

function TMpvSession.Duration: Double;
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
  Pv: TPropVariant;
begin
  Result := FLastDur;
  if FMci then
  begin
    Result := StrToFloatDef(MciStat('status vibeaudio length'), 0) / 1000.0;
    FLastDur := Result;
    Exit;
  end;
  if not AsPlayer(P) then
    Exit;
  MP := PlayerOf(P);
  if MP = nil then
    Exit;
  FillChar(Pv, SizeOf(Pv), 0);
  try
    if Succeeded(MP.GetDuration(MFP_POS_100NS, @Pv)) then
    begin
      Result := PropToSec(Pv);
      if Result > 0 then
        FLastDur := Result;
    end;
  except
  end;
  try
    PropVariantClear(Pv);
  except
  end;
end;

function TMpvSession.Position: Double;
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
  Pv: TPropVariant;
begin
  Result := FLastPos;
  if FMci then
  begin
    Result := StrToFloatDef(MciStat('status vibeaudio position'), 0) / 1000.0;
    FLastPos := Result;
    Exit;
  end;
  if not AsPlayer(P) then
    Exit;
  MP := PlayerOf(P);
  if MP = nil then
    Exit;
  FillChar(Pv, SizeOf(Pv), 0);
  try
    if Succeeded(MP.GetPosition(MFP_POS_100NS, @Pv)) then
    begin
      Result := PropToSec(Pv);
      FLastPos := Result;
    end;
  except
  end;
  try
    PropVariantClear(Pv);
  except
  end;
end;

procedure TMpvSession.Seek(ASeconds: Double);
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
  Pv: TPropVariant;
  WasPaused: Boolean;
  Dur: Double;
begin
  if ASeconds < 0 then
    ASeconds := 0;
  Dur := Duration;
  if (Dur > 0.05) and (ASeconds > Dur) then
    ASeconds := Dur;
  FLastPos := ASeconds;

  if FMci then
  begin
    Mci(Format('seek vibeaudio to %d wait', [Max(0, Round(ASeconds * 1000))]));
    if not Paused then
      Mci('play vibeaudio');
    Exit;
  end;

  if not AsPlayer(P) then
    Exit;
  MP := PlayerOf(P);
  if MP = nil then
    Exit;

  WasPaused := Paused;
  FillChar(Pv, SizeOf(Pv), 0);
  Pv.vt := VT_I8;
  Pv.hVal.QuadPart := Round(ASeconds * 1.0e7);
  try
    MP.Pause;
    MP.SetPosition(MFP_POS_100NS, @Pv);
    if FShowVideo then
      SafeUpdateVideo(P, False);
    if not WasPaused then
      MP.Play
    else
      MP.Pause;
  except
  end;
end;

procedure TMpvSession.SetBoundsScreen(const ARect: TRect);
var
  P: IUnknown;
  MP: IMFPMediaPlayer;
  Same: Boolean;
  TL, BR: TPoint;
  Area, Fit: TRect;
  Vid, AR: TSize;
  VW, VH, AW, AH, FW, FH: Integer;
begin
  if (FWnd = 0) or not IsWindow(FWnd) or (FOwner = 0) then
    Exit;
  if (not FShowVideo) or (ARect.Width < 8) or (ARect.Height < 8) then
  begin
    ShowWindow(FWnd, SW_HIDE);
    Exit;
  end;

  TL := Point(ARect.Left, ARect.Top);
  BR := Point(ARect.Right, ARect.Bottom);
  ScreenToClient(FOwner, TL);
  ScreenToClient(FOwner, BR);
  Area := Rect(TL.X, TL.Y, BR.X, BR.Y);

  VW := 0;
  VH := 0;
  if AsPlayer(P) then
  begin
    MP := PlayerOf(P);
    if MP <> nil then
    try
      FillChar(Vid, SizeOf(Vid), 0);
      FillChar(AR, SizeOf(AR), 0);
      if Succeeded(MP.GetNativeVideoSize(@Vid, @AR)) then
      begin
        if (AR.cx > 8) and (AR.cy > 8) then
        begin
          VW := AR.cx;
          VH := AR.cy;
        end
        else if (Vid.cx > 8) and (Vid.cy > 8) then
        begin
          VW := Vid.cx;
          VH := Vid.cy;
        end;
      end;
    except
    end;
  end;

  AW := Area.Right - Area.Left;
  AH := Area.Bottom - Area.Top;
  if (VW > 8) and (VH > 8) and (AW > 8) and (AH > 8) then
  begin
    if AW / VW < AH / VH then
    begin
      FW := AW;
      FH := Round(AW * VH / VW);
    end
    else
    begin
      FH := AH;
      FW := Round(AH * VW / VH);
    end;
    if FW < 8 then
      FW := 8;
    if FH < 8 then
      FH := 8;
    Fit := Rect(
      Area.Left + (AW - FW) div 2,
      Area.Top + (AH - FH) div 2,
      Area.Left + (AW - FW) div 2 + FW,
      Area.Top + (AH - FH) div 2 + FH);
  end
  else
    Fit := Area;

  Same := (FLastBounds.Left = Fit.Left) and (FLastBounds.Top = Fit.Top) and
    (FLastBounds.Right = Fit.Right) and (FLastBounds.Bottom = Fit.Bottom);
  if not Same then
  try
    SetWindowPos(FWnd, HWND_TOP, Fit.Left, Fit.Top,
      Fit.Right - Fit.Left, Fit.Bottom - Fit.Top, SWP_NOACTIVATE);
    FLastBounds := Fit;
  except
  end;
  if FWantVisible then
    ShowWindow(FWnd, SW_SHOWNOACTIVATE);
  if (not Same) or (not FArSet) then
    if AsPlayer(P) then
      SafeUpdateVideo(P, not FArSet);
end;

procedure TMpvSession.NotifyLayout;
var
  P: IUnknown;
begin
  if not FShowVideo then
    Exit;
  if AsPlayer(P) then
    SafeUpdateVideo(P, False);
end;

procedure TMpvSession.Pump;
begin
end;

function TMpvSession.Active: Boolean;
begin
  Result := HasEngine and FWantVisible;
end;

function TMpvSession.HasEngine: Boolean;
begin
  Result := FMci or (FPlayer <> nil);
end;

function MpvExportClip(const ASrc, ADst: string; AStart, AEnd: Double;
  AVideo: Boolean; out AError: string): Boolean;
begin
  Result := ExportMediaClip(ASrc, ADst, AStart, AEnd, AVideo, AError);
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  if GMfOk and Assigned(MFShutdown) then
  try
    MFShutdown;
  except
  end;
  if GMfPlay <> 0 then
    FreeLibrary(GMfPlay);
  if GMfPlat <> 0 then
    FreeLibrary(GMfPlat);
  FreeAndNil(GLock);
{$ENDIF}

end.
