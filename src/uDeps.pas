unit uDeps;

{
  sk4d.dll до первого вызова Skia. Нет файла — скачивание без вопроса,
  затем перезапуск. Без библиотеки программа не стартует.
  ffmpeg.exe только когда QV сохраняет ролик, и только после согласия.
  Оба файла лежат рядом с exe. Нет прав на папку — в %LOCALAPPDATA%\VibeCmd\.
  Отмена удаляет недокачанный файл.
}

interface

{ skLoaded: уже на месте. skFetched: только что скачана, нужен новый процесс.
  skBlocked: без библиотеки не стартуем. }
type
  TSk4dGate = (skLoaded, skFetched, skBlocked);

function EnsureSk4d: TSk4dGate;
{ True, если ffmpeg.exe запускается. AError пустой, если пользователь отказался. }
function EnsureFfmpeg(out AError: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles, System.StrUtils,
  System.Zip,
  System.Net.HttpClient, System.Net.URLClient,
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl,
  uAppSettings, uLang, uMetaCache;

const
  SK4D_NAME = 'sk4d.dll';
  FF_NAME = 'ffmpeg.exe';
  { Сборка против Skia4Delphi 7.3.0. Ветка main может уехать вперёд. }
  SK4D_URL_WIN32 =
    'https://raw.githubusercontent.com/skia4delphi/skia4delphi/v7.3.0/Binary/Shared/Win32/sk4d.dll';
  SK4D_URL_WIN64 =
    'https://raw.githubusercontent.com/skia4delphi/skia4delphi/v7.3.0/Binary/Shared/Win64/sk4d.dll';
  FF_URL =
    'https://github.com/ShareX/FFmpeg/releases/download/v8.1.1/ffmpeg-8.1.1-win-x64.zip';
  SK4D_MAX = 48 * 1024 * 1024;
  FF_ZIP_MAX = 140 * 1024 * 1024;
  FF_EXE_MAX = 220 * 1024 * 1024;
  IDC_CANCEL = 102;

type
  TDepDown = class
  public
    MaxBytes: Int64;
    Expect: Int64;
    Shown: Int64;
    Abort: Boolean;
    Canceled: Boolean;
    Wnd: HWND;
    Bar: HWND;
    function GetFile(const AUrl, APart: string): Boolean;
    procedure OnData(const Sender: TObject; AContentLength, AReadCount: Int64;
      var AAbort: Boolean);
  private
    procedure OpenProgress;
    procedure CloseProgress;
    procedure Pump;
  end;

var
  GClassAtom: ATOM;

function DepWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  D: TDepDown;
begin
  D := TDepDown(Pointer(GetWindowLongPtr(Wnd, GWLP_USERDATA)));
  case Msg of
    WM_COMMAND:
      if (LoWord(WParam) = IDC_CANCEL) and (D <> nil) then
      begin
        D.Abort := True;
        D.Canceled := True;
        Result := 0;
        Exit;
      end;
    WM_CLOSE:
      begin
        if D <> nil then
        begin
          D.Abort := True;
          D.Canceled := True;
        end;
        Result := 0;
        Exit;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure EnsureDepClass;
var
  W: TWndClass;
begin
  if GClassAtom <> 0 then
    Exit;
  FillChar(W, SizeOf(W), 0);
  W.lpfnWndProc := @DepWndProc;
  W.hInstance := HInstance;
  W.hCursor := LoadCursor(0, IDC_ARROW);
  W.hbrBackground := HBRUSH(COLOR_BTNFACE + 1);
  W.lpszClassName := 'VibeDepDlg';
  GClassAtom := RegisterClass(W);
end;

function LocalDepDir: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'VibeCmd');
end;

function ExeDir: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

procedure WarmLang;
var
  Ini: TIniFile;
begin
  if LanguageLoaded then
    Exit;
  Ini := TIniFile.Create(ActiveSettingsIni);
  try
    SetLanguage(Ini.ReadString('Main', 'Language', 'system'));
  finally
    Ini.Free;
  end;
end;

function AskYes(const AKey: string): Boolean;
begin
  Result := MessageBox(0, PChar(L(AKey)), 'V!BE CMD',
    MB_YESNO or MB_ICONQUESTION or MB_SETFOREGROUND) = IDYES;
end;

procedure Tell(const AText: string);
begin
  if AText = '' then
    Exit;
  MessageBox(0, PChar(AText), 'V!BE CMD',
    MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND);
end;

function HasSig(const APath: string; A0, A1: Byte): Boolean;
var
  Fs: TFileStream;
  B: array[0..1] of Byte;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
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
    Result := False;
  end;
end;

function CanWriteDir(const ADir: string): Boolean;
var
  P: string;
  Fs: TFileStream;
begin
  Result := False;
  if ADir = '' then
    Exit;
  P := TPath.Combine(ExcludeTrailingPathDelimiter(ADir), 'dep.write.tmp');
  try
    Fs := TFileStream.Create(P, fmCreate);
    Fs.Free;
    TFile.Delete(P);
    Result := True;
  except
    Result := False;
  end;
end;

function DestFor(const AName: string): string;
var
  Dir: string;
begin
  Dir := ExeDir;
  if CanWriteDir(Dir) then
    Exit(Dir + AName);
  Dir := LocalDepDir;
  ForceDirectories(Dir);
  Result := TPath.Combine(Dir, AName);
end;

function MoveOver(const ASrc, ADest: string): Boolean;
begin
  Result := False;
  try
    ForceDirectories(ExtractFilePath(ADest));
    if TFile.Exists(ADest) then
      TFile.Delete(ADest);
    try
      TFile.Move(ASrc, ADest);
    except
      TFile.Copy(ASrc, ADest, True);
      TFile.Delete(ASrc);
    end;
    Result := TFile.Exists(ADest) and (TFile.GetSize(ADest) > 0);
  except
    Result := False;
  end;
end;

procedure Wipe(const APath: string);
begin
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    TFile.Delete(APath);
  except
  end;
end;

procedure TDepDown.Pump;
var
  M: TMsg;
begin
  while PeekMessage(M, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(M);
    DispatchMessage(M);
  end;
end;

procedure TDepDown.OpenProgress;
var
  ICC: TInitCommonControlsEx;
  X, Y, W, H: Integer;
begin
  Wnd := 0;
  Bar := 0;
  ICC.dwSize := SizeOf(ICC);
  ICC.dwICC := ICC_PROGRESS_CLASS;
  InitCommonControlsEx(ICC);
  EnsureDepClass;
  if GClassAtom = 0 then
    Exit;
  W := 440;
  H := 148;
  X := (GetSystemMetrics(SM_CXSCREEN) - W) div 2;
  Y := (GetSystemMetrics(SM_CYSCREEN) - H) div 2;
  Wnd := CreateWindowEx(WS_EX_TOPMOST or WS_EX_DLGMODALFRAME, 'VibeDepDlg',
    PChar(L('dep.progress')), WS_POPUP or WS_CAPTION or WS_SYSMENU or WS_VISIBLE,
    X, Y, W, H, 0, 0, HInstance, nil);
  if Wnd = 0 then
    Exit;
  SetWindowLongPtr(Wnd, GWLP_USERDATA, LONG_PTR(NativeInt(Self)));
  CreateWindowEx(0, 'STATIC', PChar(L('dep.progress')),
    WS_CHILD or WS_VISIBLE, 16, 16, 400, 20, Wnd, 0, HInstance, nil);
  Bar := CreateWindowEx(0, PROGRESS_CLASS, nil, WS_CHILD or WS_VISIBLE,
    16, 44, 400, 18, Wnd, 101, HInstance, nil);
  CreateWindowEx(0, 'BUTTON', PChar(L('dep.cancel')),
    WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, 160, 74, 110, 28,
    Wnd, IDC_CANCEL, HInstance, nil);
  if Bar <> 0 then
    SendMessage(Bar, PBM_SETRANGE, 0, MakeLParam(0, 100));
  ShowWindow(Wnd, SW_SHOWNORMAL);
  UpdateWindow(Wnd);
  Pump;
end;

procedure TDepDown.CloseProgress;
begin
  if Wnd <> 0 then
  begin
    DestroyWindow(Wnd);
    Wnd := 0;
    Bar := 0;
  end;
end;

procedure TDepDown.OnData(const Sender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
var
  Pct: Integer;
begin
  if AContentLength > 0 then
    Expect := AContentLength;
  if (AContentLength > MaxBytes) or (AReadCount > MaxBytes) then
  begin
    Abort := True;
    AAbort := True;
  end;
  if Abort then
  begin
    AAbort := True;
    Exit;
  end;
  if (Bar <> 0) and (AReadCount - Shown >= 256 * 1024) then
  begin
    Shown := AReadCount;
    Pct := 0;
    if Expect > 0 then
      Pct := Integer((AReadCount * 100) div Expect);
    if Pct > 100 then
      Pct := 100;
    SendMessage(Bar, PBM_SETPOS, Pct, 0);
    SetWindowText(Wnd, PChar(L('dep.progress') + ' ' + IntToStr(Pct) + '%'));
  end;
  Pump;
  if Abort then
    AAbort := True;
end;

function TDepDown.GetFile(const AUrl, APart: string): Boolean;
var
  Client: THTTPClient;
  FS: TFileStream;
  Resp: IHTTPResponse;
  Sz: Int64;
begin
  Result := False;
  Expect := 0;
  Shown := 0;
  Abort := False;
  Canceled := False;
  Wipe(APart);
  Client := THTTPClient.Create;
  FS := nil;
  try
    Client.ConnectionTimeout := 8000;
    Client.ResponseTimeout := 600000;
    Client.HandleRedirects := True;
    Client.UserAgent := 'VibeCmd';
    Client.AutomaticDecompression := [];
    Client.OnReceiveData := OnData;
    FS := TFileStream.Create(APart, fmCreate);
    OpenProgress;
    try
      Resp := Client.Get(AUrl, FS);
    except
      Resp := nil;
    end;
  finally
    FS.Free;
    Client.Free;
    CloseProgress;
  end;
  if Canceled or Abort or (Resp = nil) or (Resp.StatusCode <> 200) then
  begin
    Wipe(APart);
    Exit;
  end;
  if Expect <= 0 then
    Expect := Resp.ContentLength;
  Sz := 0;
  if TFile.Exists(APart) then
    Sz := TFile.GetSize(APart);
  if (Expect <= 0) or (Sz <> Expect) or (Expect > MaxBytes) then
  begin
    Wipe(APart);
    Exit;
  end;
  Result := True;
end;

function PartFile(const AName: string): string;
var
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'VibeCmd');
  ForceDirectories(Dir);
  Result := TPath.Combine(Dir, AName + '.part');
end;

function LoadDll(const APath: string): Boolean;
begin
  Result := HasSig(APath, $4D, $5A) and (LoadLibrary(PChar(APath)) <> 0);
end;

function SkUrl: string;
begin
  {$IFDEF WIN64}
  Result := SK4D_URL_WIN64;
  {$ELSE}
  Result := SK4D_URL_WIN32;
  {$ENDIF}
end;

function EnsureSk4d: TSk4dGate;
var
  Paths: TArray<string>;
  P, Part, Dest: string;
  Down: TDepDown;
begin
  Result := skBlocked;
  WarmLang;
  Paths := [ExeDir + SK4D_NAME, TPath.Combine(LocalDepDir, SK4D_NAME)];
  for P in Paths do
    if TFile.Exists(P) and LoadDll(P) then
      Exit(skLoaded);
  Part := PartFile(SK4D_NAME);
  Down := TDepDown.Create;
  try
    Down.MaxBytes := SK4D_MAX;
    if not Down.GetFile(SkUrl, Part) then
    begin
      Tell(L('dep.sk.fail'));
      Exit(skBlocked);
    end;
  finally
    Down.Free;
  end;
  if not HasSig(Part, $4D, $5A) then
  begin
    Wipe(Part);
    Tell(L('dep.sk.fail'));
    Exit(skBlocked);
  end;
  Dest := DestFor(SK4D_NAME);
  if not MoveOver(Part, Dest) or not LoadDll(Dest) then
  begin
    Wipe(Part);
    Tell(L('dep.sk.fail'));
    Exit(skBlocked);
  end;
  Result := skFetched;
end;

function ExeRuns(const APath: string): Boolean;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
  Code: DWORD;
begin
  Result := False;
  if not HasSig(APath, $4D, $5A) then
    Exit;
  FillChar(SI, SizeOf(SI), 0);
  FillChar(PI, SizeOf(PI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  Cmd := '"' + APath + '" -hide_banner -version';
  UniqueString(Cmd);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW,
    nil, nil, SI, PI) then
    Exit;
  if WaitForSingleObject(PI.hProcess, 8000) <> WAIT_OBJECT_0 then
    TerminateProcess(PI.hProcess, 1);
  Code := 1;
  GetExitCodeProcess(PI.hProcess, Code);
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  Result := Code = 0;
end;

function ZipLeaf(const AName: string): string;
var
  S: string;
  I: Integer;
begin
  S := StringReplace(AName, '/', '\', [rfReplaceAll]);
  I := LastDelimiter('\', S);
  if I > 0 then
    Result := Copy(S, I + 1, MaxInt)
  else
    Result := S;
end;

function ExtractFfmpeg(const AZip, AOut: string): Boolean;
var
  Zip: TZipFile;
  I: Integer;
  Name: string;
  Stm: TStream;
  FS: TFileStream;
  Hdr: TZipHeader;
begin
  Result := False;
  Zip := TZipFile.Create;
  try
    try
      Zip.Open(AZip, zmRead);
    except
      Exit;
    end;
    for I := 0 to Zip.FileCount - 1 do
    begin
      Name := Zip.FileName[I];
      if (Pos('..', Name) > 0) or not SameText(ZipLeaf(Name), FF_NAME) then
        Continue;
      if EndsText('/', Name) or EndsText('\', Name) then
        Continue;
      Stm := nil;
      FS := nil;
      try
        try
          Zip.Read(I, Stm, Hdr);
          FS := TFileStream.Create(AOut, fmCreate);
          if Stm <> nil then
            FS.CopyFrom(Stm, 0);
        except
          Exit;
        end;
      finally
        FS.Free;
        Stm.Free;
      end;
      Result := HasSig(AOut, $4D, $5A) and (TFile.GetSize(AOut) > 1000000) and
        (TFile.GetSize(AOut) <= FF_EXE_MAX);
      Exit;
    end;
  finally
    Zip.Free;
  end;
end;

function EnsureFfmpeg(out AError: string): Boolean;
var
  Have, Part, ExePart, Dest: string;
  Broken: Boolean;
  Down: TDepDown;
begin
  Result := False;
  AError := '';
  WarmLang;
  Have := FindFfmpeg;
  if (Have <> '') and ExeRuns(Have) then
    Exit(True);
  Broken := (Have <> '') and TFile.Exists(Have);
  if Broken then
  begin
    if not AskYes('dep.ff.bad') then
      Exit(False);
  end
  else if not AskYes('dep.ff.ask') then
    Exit(False);
  Part := PartFile('ffmpeg.zip');
  ExePart := PartFile(FF_NAME);
  Down := TDepDown.Create;
  try
    Down.MaxBytes := FF_ZIP_MAX;
    if not Down.GetFile(FF_URL, Part) then
    begin
      if not Down.Canceled then
        AError := L('dep.ff.fail');
      Exit(False);
    end;
  finally
    Down.Free;
  end;
  Wipe(ExePart);
  if not HasSig(Part, $50, $4B) or not ExtractFfmpeg(Part, ExePart) then
  begin
    Wipe(Part);
    Wipe(ExePart);
    AError := L('dep.ff.fail');
    Exit(False);
  end;
  Wipe(Part);
  Dest := DestFor(FF_NAME);
  if not MoveOver(ExePart, Dest) or not ExeRuns(Dest) then
  begin
    Wipe(ExePart);
    AError := L('dep.ff.fail');
    Exit(False);
  end;
  Result := True;
end;

end.
