unit uNetworkVfs;

// Сетевая VFS без форм и панелей. Колбэк всегда ставится в очередь главного потока.
// Пример из UI: BindNetworkBrowse(Fs, Path, ApplyItems, ShowError). Отмена: Fs.Cancel.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Threading;

type
  TNetworkItemType = (nitWorkgroup, nitServer, nitShare, nitDirectory, nitFile);

  TNetworkItem = record
    Name: string;
    FullPath: string;
    ItemType: TNetworkItemType;
    Size: Int64;
    ModifiedDate: TDateTime;
    IsReadable: Boolean;
    IsWritable: Boolean;
    Comment: string;
    ResType: Cardinal;
    ShareType: Cardinal;
    FromShare: Boolean;
    FromWNet: Boolean;
  end;

  TNetworkItemList = TArray<TNetworkItem>;

  TNetworkOperationCallback = reference to procedure(const AItems: TNetworkItemList; const AError: string);

  INetSlot = interface
    function Accept(AGen: Integer): Boolean;
    function NextGen: Integer;
    procedure Kill;
  end;

  TNetJob = class(TInterfacedObject)
  public
    Slot: INetSlot;
    Gen: Integer;
    OnBrowse: TNetworkOperationCallback;
    OnProgress: TProc<Int64, Int64>;
    OnComplete: TProc<Boolean, string>;
    Items: TList<TNetworkItem>;
    Error: string;
    Ok: Boolean;
    Browse: Boolean;
    FCancel: Integer;
    FPosted: Integer;
    FCopyCancel: LongBool;
    constructor Create(ASlot: INetSlot; AGen: Integer);
    destructor Destroy; override;
    procedure RequestCancel;
    function Stopped: Boolean;
    function TryOwnResult: Boolean;
  end;

  TNetworkFileSystem = class
  private
    FSlot: INetSlot;
    FJob: TNetJob;
    FTask: ITask;
    procedure RetireJob;
    function BeginJob(const ACallback: TNetworkOperationCallback; ABrowse: Boolean): TNetJob;
    procedure RunJob(AJob: TNetJob; const AWork: TProc; ATimeout: Cardinal);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BrowseAsync(const APath: string; ACallback: TNetworkOperationCallback); virtual; abstract;
    procedure CopyFileAsync(const ASource, ADest: string; AOnProgress: TProc<Int64, Int64>;
      AOnComplete: TProc<Boolean, string>); virtual; abstract;
    procedure Cancel; virtual;
  end;

  TSMBProvider = class(TNetworkFileSystem)
  public
    procedure BrowseAsync(const APath: string; ACallback: TNetworkOperationCallback); override;
    procedure CopyFileAsync(const ASource, ADest: string; AOnProgress: TProc<Int64, Int64>;
      AOnComplete: TProc<Boolean, string>); override;
  end;

  TFTPProvider = class(TNetworkFileSystem)
  public
    procedure BrowseAsync(const APath: string; ACallback: TNetworkOperationCallback); override;
    procedure CopyFileAsync(const ASource, ADest: string; AOnProgress: TProc<Int64, Int64>;
      AOnComplete: TProc<Boolean, string>); override;
  end;

  TWebDAVProvider = class(TNetworkFileSystem)
  public
    procedure BrowseAsync(const APath: string; ACallback: TNetworkOperationCallback); override;
    procedure CopyFileAsync(const ASource, ADest: string; AOnProgress: TProc<Int64, Int64>;
      AOnComplete: TProc<Boolean, string>); override;
  end;

  TNetworkHost = record
    Address: string;
    Name: string;
    Mac: string;
    Vendor: string;
    HasFTP: Boolean;
    HasSMB: Boolean;
    HasWebAdmin: Boolean;
    IsRouter: Boolean;
    { 80 і 443 окремо: сторінка роутера — http, і лише 443 дає https. }
    Port80: Boolean;
    Port443: Boolean;
  end;

  // Пинг подсети, порты 21 / 445 / 80 / 443 и MAC. Только частные адреса, не шире 254 узлов.
  TNetworkDiscovery = class
  private
    FSlot: INetSlot;
    FJob: TNetJob;
    FTask: ITask;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ScanAsync(const ASubnet: string; AOnHost: TProc<TNetworkHost>;
      AOnDone: TProc<string>);
    procedure Cancel;
  end;

  { Строка классической сети. Свой обход, сканер её не трогает. }
  TClassicRow = record
    Name: string;
    FullPath: string;
    IsShare: Boolean;
  end;

  TClassicNet = class
  private
    FSlot: INetSlot;
    FJob: TNetJob;
    FTask: ITask;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(AOnRow: TProc<TClassicRow>; AOnDone: TProc<string>);
    procedure Cancel;
  end;

{ Текст «нет доступа» с кодом Windows после #1. На экране код снимается. }
function NetLogonText(ACode: Cardinal): string;
function NetLogonCodeOf(const AText: string; out ACode: Cardinal): Boolean;
function NetLogonPlain(const AText: string): string;
{ Одна строка. Сырой текст сокета становится «нет связи» или «нет доступа». }
function HumanNetError(const AText: string): string;
{ 0 — административные ($), 1 — шары, 2 — принтеры, 3 — факс, сканер и прочее. }
function HostResourceGroup(const AItem: TNetworkItem): Integer;
function UncServerRoot(const AUnc: string): string;
function PromptShareLogon(AOwner: NativeUInt; const AUnc: string;
  ACode: Cardinal): Boolean;
{ Короткий пінг. Ім'я спочатку розбирається в IPv4. }
function ProbeHostAlive(const AHost: string): Boolean;
function RouterPageUrl(const AHost: TNetworkHost): string;
{ Літера вже мапленої шари, інакше порожньо. Таблиця MPR, без опитування шари. }
function MappedLetterFor(const AUnc: string): string;
function MapNetworkShare(const AUnc, ALetter: string; ARestore: Boolean;
  out ACode: Cardinal): Boolean;
function UnmapNetworkShare(const ALetter: string; out ACode: Cardinal): Boolean;
function PrinterIsQueued(const AUnc: string): Boolean;
{ True — черга щойно створена. AAlready — вже була, другу не створюємо. }
function ConnectPrinter(const AUnc: string; out AAlready: Boolean;
  out ACode: Cardinal): Boolean;
function MakeDefaultPrinter(const AUnc: string; out ACode: Cardinal): Boolean;
function RemovePrinter(const AUnc: string; out ACode: Cardinal): Boolean;

procedure BindNetworkBrowse(AFs: TNetworkFileSystem; const APath: string;
  const AApply: TProc<TNetworkItemList>; const AFail: TProc<string>);

// Первые три октета частного IPv4. Пусто, если локальной подсети нет.
function LocalSubnetPrefix: string;
function IsPrivateIp(const AIp: string): Boolean;

implementation

uses
  Winapi.Windows,
  Winapi.Winsock,
  Winapi.IpHlpApi,
  System.StrUtils,
  Winapi.IpRtrMib,
  System.SyncObjs,
  System.DateUtils,
  System.Net.URLClient,
  System.Net.HttpClient,
  System.NetEncoding,
  IdComponent,
  IdFTP,
  IdFTPCommon,
  IdFTPList,
  IdAllFTPListParsers,
  uLang;

const
  NET_WAIT_MS = 12000;
  PING_MS = 200;
  PORT_MS = 200;
  SCAN_CAP = 254;
  PRINTER_ENUM_LOCAL = 2;
  PRINTER_ENUM_CONNECTIONS = 4;
  { У Winapi.Windows немає ERROR_PRINTER_ALREADY_EXISTS. }
  ERR_PRINTER_ALREADY = 1801;

type
  { Win32 PRINTER_INFO_4: два вказівники і DWORD, без хвостового вирівнювання. }
  TPrinterInfo4 = packed record
    pPrinterName: PChar;
    pServerName: PChar;
    Attributes: DWORD;
  end;
  PPrinterInfo4 = ^TPrinterInfo4;

  TNetSlot = class(TInterfacedObject, INetSlot)
  private
    FGen: Integer;
    FDead: Integer;
  public
    function Accept(AGen: Integer): Boolean;
    function NextGen: Integer;
    procedure Kill;
  end;

  TNetSeed = record
    Remote: string;
    Comment: string;
    Provider: string;
    ResType: DWORD;
    Display: DWORD;
    Usage: DWORD;
  end;

  TFtpProgress = class
  public
    Ftp: TIdFTP;
    Job: TNetJob;
    OnProgress: TProc<Int64, Int64>;
    Total: Int64;
    procedure BeginWork(ASender: TObject; AWorkMode: TWorkMode; AWorkCountMax: Int64);
    procedure Work(ASender: TObject; AWorkMode: TWorkMode; AWorkCount: Int64);
  end;

function CleanError(const AMessage: string): string;
var
  S: string;
  I: Integer;
begin
  S := Trim(AMessage);
  for I := 1 to Length(S) do
    if (S[I] < ' ') and (S[I] <> #10) and (S[I] <> #13) then
      S[I] := ' ';
  S := Trim(S);
  if S = '' then
    S := L('net.err');
  Result := HumanNetError(S);
end;

function HumanNetError(const AText: string): string;
var
  S, Low: string;
begin
  S := NetLogonPlain(AText);
  S := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
  S := StringReplace(S, #10, ' ', [rfReplaceAll]);
  S := StringReplace(S, #13, ' ', [rfReplaceAll]);
  while Pos('  ', S) > 0 do
    S := StringReplace(S, '  ', ' ', [rfReplaceAll]);
  S := Trim(S);
  Low := LowerCase(S);
  if (Pos('socket', Low) > 0) or (Pos('10054', Low) > 0) or (Pos('10060', Low) > 0) or
     (Pos('10061', Low) > 0) or (Pos('10053', Low) > 0) or (Pos('10051', Low) > 0) or
     (Pos('10065', Low) > 0) or (Pos('connection reset', Low) > 0) or
     (Pos('timed out', Low) > 0) or (Pos('timeout', Low) > 0) or
     (Pos('# 100', Low) > 0) then
  begin
    if (Pos('access', Low) > 0) or (Pos('denied', Low) > 0) or
       (Pos('logon', Low) > 0) or (Pos('password', Low) > 0) then
      Exit(L('op.noaccess'));
    Exit(L('drive.link'));
  end;
  if S = '' then
    S := L('net.err');
  if Length(S) > 180 then
    S := Copy(S, 1, 180);
  Result := S;
end;

function NetLogonText(ACode: Cardinal): string;
begin
  Result := L('op.noaccess') + #1 + IntToStr(ACode);
end;

function NetLogonCodeOf(const AText: string; out ACode: Cardinal): Boolean;
var
  P: Integer;
begin
  ACode := 0;
  Result := False;
  P := Pos(#1, AText);
  if (P <= 1) or (Copy(AText, 1, P - 1) <> L('op.noaccess')) then
    Exit;
  ACode := StrToIntDef(Copy(AText, P + 1, 12), 0);
  Result := (ACode = ERROR_ACCESS_DENIED) or (ACode = ERROR_LOGON_FAILURE) or
    (ACode = ERROR_INVALID_PASSWORD) or
    (ACode = ERROR_SESSION_CREDENTIAL_CONFLICT);
end;

function NetLogonPlain(const AText: string): string;
var
  P: Integer;
begin
  P := Pos(#1, AText);
  if P > 0 then
    Result := Copy(AText, 1, P - 1)
  else
    Result := AText;
end;

function UncServerRoot(const AUnc: string): string;
var
  S: string;
  P: Integer;
begin
  Result := '';
  S := Trim(AUnc);
  if S = '' then
    Exit;
  if StartsText('network://', S) or StartsText('network:\\', S) then
  begin
    Delete(S, 1, 10);
    while (S <> '') and ((S[1] = '/') or (S[1] = '\')) do
      Delete(S, 1, 1);
  end
  else if S.StartsWith('\\') then
    Delete(S, 1, 2)
  else if Pos('://', S) > 0 then
    Exit;
  P := Pos('\', S);
  if P = 0 then
    P := Pos('/', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  P := Pos('@', S);
  if P > 0 then
    S := Copy(S, P + 1, MaxInt);
  if (S <> '') and (S[1] <> '[') then
  begin
    P := Pos(':', S);
    if P > 0 then
      S := Copy(S, 1, P - 1);
  end;
  S := Trim(S);
  if S = '' then
    Exit;
  Result := '\\' + S;
end;

function PromptShareLogon(AOwner: NativeUInt; const AUnc: string;
  ACode: Cardinal): Boolean;
var
  Root: string;
  Res: TNetResource;
  Status: DWORD;
begin
  Result := False;
  Root := UncServerRoot(AUnc);
  if Root = '' then
    Exit;
  if ACode = ERROR_SESSION_CREDENTIAL_CONFLICT then
    WNetCancelConnection2(PChar(Root), 0, False);
  FillChar(Res, SizeOf(Res), 0);
  Res.dwType := RESOURCETYPE_DISK;
  Res.lpRemoteName := PChar(Root);
  Status := WNetAddConnection3(HWND(AOwner), Res, nil, nil,
    CONNECT_INTERACTIVE or CONNECT_PROMPT);
  Result := Status = NO_ERROR;
end;

function RouterPageUrl(const AHost: TNetworkHost): string;
begin
  if (AHost.Address <> '') and AHost.Port443 and not AHost.Port80 then
    Result := 'https://' + AHost.Address
  else
    Result := 'http://' + AHost.Address;
end;

function MappedLetterFor(const AUnc: string): string;
var
  C: Char;
  Mask, Len: DWORD;
  Buf: array[0..1023] of Char;
  Want, Got: string;
begin
  Result := '';
  Want := ExcludeTrailingPathDelimiter(Trim(AUnc));
  if Want = '' then
    Exit;
  Mask := GetLogicalDrives;
  for C := 'A' to 'Z' do
  begin
    if (Mask and (1 shl (Ord(C) - Ord('A')))) = 0 then
      Continue;
    Len := Length(Buf);
    FillChar(Buf, SizeOf(Buf), 0);
    if WNetGetConnection(PChar(string(C) + ':'), Buf, Len) <> NO_ERROR then
      Continue;
    Got := ExcludeTrailingPathDelimiter(string(PChar(@Buf[0])));
    if SameText(Got, Want) then
      Exit(string(C) + ':');
  end;
end;

function MapNetworkShare(const AUnc, ALetter: string; ARestore: Boolean;
  out ACode: Cardinal): Boolean;
var
  Res: TNetResource;
  Local, Remote: string;
  Flags: DWORD;
begin
  ACode := ERROR_INVALID_PARAMETER;
  Result := False;
  Remote := ExcludeTrailingPathDelimiter(Trim(AUnc));
  if (ALetter = '') or (Remote = '') then
    Exit;
  Local := UpCase(ALetter[1]) + ':';
  FillChar(Res, SizeOf(Res), 0);
  Res.dwType := RESOURCETYPE_DISK;
  Res.lpLocalName := PChar(Local);
  Res.lpRemoteName := PChar(Remote);
  Flags := 0;
  if ARestore then
    Flags := CONNECT_UPDATE_PROFILE;
  { Пароль не передаємо і не пишемо: чужу шару питає системний діалог. }
  ACode := WNetAddConnection2(Res, nil, nil, Flags);
  Result := ACode = NO_ERROR;
end;

function UnmapNetworkShare(const ALetter: string; out ACode: Cardinal): Boolean;
var
  Local: string;
begin
  ACode := ERROR_INVALID_PARAMETER;
  Result := False;
  if ALetter = '' then
    Exit;
  Local := UpCase(ALetter[1]) + ':';
  ACode := WNetCancelConnection2(PChar(Local), CONNECT_UPDATE_PROFILE, False);
  Result := ACode = NO_ERROR;
end;

function EnumPrintersW(Flags: DWORD; Name: PChar; Level: DWORD; pPrinterEnum: Pointer;
  cbBuf: DWORD; var pcbNeeded, pcReturned: DWORD): BOOL; stdcall;
  external 'winspool.drv' name 'EnumPrintersW';
function AddPrinterConnectionW(pName: PChar): BOOL; stdcall;
  external 'winspool.drv' name 'AddPrinterConnectionW';
function DeletePrinterConnectionW(pName: PChar): BOOL; stdcall;
  external 'winspool.drv' name 'DeletePrinterConnectionW';
function SetDefaultPrinterW(pszPrinter: PChar): BOOL; stdcall;
  external 'winspool.drv' name 'SetDefaultPrinterW';

function SameUnc(const A, B: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(Trim(A)),
    ExcludeTrailingPathDelimiter(Trim(B)));
end;

function PrinterIsQueued(const AUnc: string): Boolean;
var
  Need, Got: DWORD;
  Buf: TBytes;
  P: PByte;
  Info: PPrinterInfo4;
  I: Integer;
begin
  Result := False;
  if Trim(AUnc) = '' then
    Exit;
  Need := 0;
  Got := 0;
  EnumPrintersW(PRINTER_ENUM_LOCAL or PRINTER_ENUM_CONNECTIONS, nil, 4, nil, 0,
    Need, Got);
  if Need = 0 then
    Exit;
  SetLength(Buf, Need);
  Got := 0;
  if not EnumPrintersW(PRINTER_ENUM_LOCAL or PRINTER_ENUM_CONNECTIONS, nil, 4,
       @Buf[0], Length(Buf), Need, Got) then
    Exit;
  P := @Buf[0];
  for I := 0 to Integer(Got) - 1 do
  begin
    Info := PPrinterInfo4(P);
    if (Info <> nil) and (Info.pPrinterName <> nil) and
       SameUnc(string(Info.pPrinterName), AUnc) then
      Exit(True);
    Inc(P, SizeOf(TPrinterInfo4));
  end;
end;

function ConnectPrinter(const AUnc: string; out AAlready: Boolean;
  out ACode: Cardinal): Boolean;
begin
  AAlready := False;
  ACode := 0;
  Result := False;
  if Trim(AUnc) = '' then
    Exit;
  if PrinterIsQueued(AUnc) then
  begin
    AAlready := True;
    Exit;
  end;
  if AddPrinterConnectionW(PChar(AUnc)) then
    Exit(True);
  ACode := GetLastError;
  if ACode = ERR_PRINTER_ALREADY then
  begin
    AAlready := True;
    ACode := 0;
  end;
end;

function MakeDefaultPrinter(const AUnc: string; out ACode: Cardinal): Boolean;
begin
  ACode := 0;
  Result := (Trim(AUnc) <> '') and SetDefaultPrinterW(PChar(AUnc));
  if not Result then
    ACode := GetLastError;
end;

function RemovePrinter(const AUnc: string; out ACode: Cardinal): Boolean;
begin
  ACode := 0;
  Result := (Trim(AUnc) <> '') and DeletePrinterConnectionW(PChar(AUnc));
  if not Result then
    ACode := GetLastError;
end;

function NetStatusText(AStatus: DWORD): string;
begin
  if (AStatus = ERROR_ACCESS_DENIED) or (AStatus = ERROR_LOGON_FAILURE) or
     (AStatus = ERROR_INVALID_PASSWORD) or
     (AStatus = ERROR_SESSION_CREDENTIAL_CONFLICT) then
    Exit(NetLogonText(AStatus));
  case AStatus of
    ERROR_BAD_NETPATH, ERROR_BAD_NET_NAME:
      Result := L('net.path.missing');
    ERROR_NO_NETWORK, ERROR_NO_NET_OR_BAD_PATH:
      Result := L('net.unreachable');
    ERROR_NOT_CONTAINER:
      Result := L('net.notcontainer');
  else
    Result := CleanError(SysErrorMessage(AStatus));
  end;
end;

procedure QueueResult(AJob: TNetJob);
var
  Items: TNetworkItemList;
  Err: string;
  Ok: Boolean;
  Gen: Integer;
  Slot: INetSlot;
  BrowseCb: TNetworkOperationCallback;
  DoneCb: TProc<Boolean, string>;
  IsBrowse: Boolean;
begin
  Items := nil;
  if (AJob.Items <> nil) and AJob.Browse and (AJob.Error = '') then
    Items := AJob.Items.ToArray;
  Err := AJob.Error;
  Ok := AJob.Ok;
  Gen := AJob.Gen;
  Slot := AJob.Slot;
  BrowseCb := AJob.OnBrowse;
  DoneCb := AJob.OnComplete;
  IsBrowse := AJob.Browse;
  TThread.Queue(nil,
    procedure
    begin
      if (Slot <> nil) and not Slot.Accept(Gen) then
        Exit;
      if IsBrowse then
      begin
        if Assigned(BrowseCb) then
          BrowseCb(Items, Err);
      end
      else if Assigned(DoneCb) then
        DoneCb(Ok, Err);
    end);
end;

procedure QueueProgress(AJob: TNetJob; ADone, ATotal: Int64);
var
  Cb: TProc<Int64, Int64>;
  Gen: Integer;
  Slot: INetSlot;
  DoneN, TotalN: Int64;
begin
  if (AJob = nil) or not Assigned(AJob.OnProgress) then
    Exit;
  if not AJob.Slot.Accept(AJob.Gen) then
    Exit;
  Cb := AJob.OnProgress;
  Gen := AJob.Gen;
  Slot := AJob.Slot;
  DoneN := ADone;
  TotalN := ATotal;
  TThread.Queue(nil,
    procedure
    begin
      if (Slot <> nil) and not Slot.Accept(Gen) then
        Exit;
      if Assigned(Cb) then
        Cb(DoneN, TotalN);
    end);
end;

function SmbCopyProgress(TotalFileSize, TotalBytesTransferred, StreamSize,
  StreamBytesTransferred: Int64; dwStreamNumber, dwCallbackReason: DWORD;
  hSourceFile, hDestinationFile: THandle; lpData: Pointer): DWORD; stdcall;
var
  Job: TNetJob;
begin
  Result := PROGRESS_CONTINUE;
  if lpData = nil then
    Exit;
  Job := TNetJob(lpData);
  if Job.Stopped or Job.FCopyCancel then
    Exit(PROGRESS_CANCEL);
  QueueProgress(Job, TotalBytesTransferred, TotalFileSize);
end;

function TNetSlot.Accept(AGen: Integer): Boolean;
begin
  Result := (FDead = 0) and (FGen = AGen);
end;

function TNetSlot.NextGen: Integer;
begin
  Result := TInterlocked.Increment(FGen);
end;

procedure TNetSlot.Kill;
begin
  TInterlocked.Exchange(FDead, 1);
end;

constructor TNetJob.Create(ASlot: INetSlot; AGen: Integer);
begin
  inherited Create;
  Slot := ASlot;
  Gen := AGen;
  Items := TList<TNetworkItem>.Create;
  Ok := False;
  Browse := True;
end;

destructor TNetJob.Destroy;
begin
  Items.Free;
  inherited;
end;

procedure TNetJob.RequestCancel;
begin
  TInterlocked.Exchange(FCancel, 1);
  FCopyCancel := True;
end;

function TNetJob.Stopped: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancel, 0, 0) <> 0;
end;

function TNetJob.TryOwnResult: Boolean;
begin
  Result := TInterlocked.CompareExchange(FPosted, 1, 0) = 0;
end;

procedure TFtpProgress.BeginWork(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCountMax: Int64);
begin
  Total := AWorkCountMax;
end;

procedure TFtpProgress.Work(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCount: Int64);
begin
  if (Job <> nil) and Job.Stopped then
  begin
    if Job.Error = '' then
      Job.Error := L('op.cancelled');
    if Ftp <> nil then
      Ftp.Abort;
    Exit;
  end;
  QueueProgress(Job, AWorkCount, Total);
end;

constructor TNetworkFileSystem.Create;
begin
  inherited Create;
  FSlot := TNetSlot.Create;
end;

destructor TNetworkFileSystem.Destroy;
begin
  Cancel;
  if FSlot <> nil then
    FSlot.Kill;
  FTask := nil;
  FJob := nil;
  FSlot := nil;
  inherited;
end;

procedure TNetworkFileSystem.Cancel;
begin
  RetireJob;
end;

procedure TNetworkFileSystem.RetireJob;
var
  Old: TNetJob;
begin
  if FTask <> nil then
  begin
    FTask.Cancel;
    FTask := nil;
  end;
  Old := FJob;
  FJob := nil;
  if Old = nil then
    Exit;
  Old.RequestCancel;
  if Old.TryOwnResult then
  begin
    if Old.Error = '' then
      Old.Error := L('op.cancelled');
    Old.Ok := False;
    QueueResult(Old);
  end;
end;

function TNetworkFileSystem.BeginJob(const ACallback: TNetworkOperationCallback;
  ABrowse: Boolean): TNetJob;
begin
  RetireJob;
  Result := TNetJob.Create(FSlot, FSlot.NextGen);
  Result.OnBrowse := ACallback;
  Result.Browse := ABrowse;
  FJob := Result;
end;

procedure TNetworkFileSystem.RunJob(AJob: TNetJob; const AWork: TProc;
  ATimeout: Cardinal);
var
  Task: ITask;
begin
  Task := TTask.Run(
    procedure
    var
      Thr: TThread;
      Finished: Boolean;
    begin
      Thr := TThread.CreateAnonymousThread(
        procedure
        begin
          try
            AWork();
          except
            on E: Exception do
              if AJob.Error = '' then
                AJob.Error := CleanError(E.Message);
          end;
        end);
      Thr.FreeOnTerminate := False;
      Thr.Start;
      Finished := WaitForSingleObject(Thr.Handle, ATimeout) = WAIT_OBJECT_0;
      if not Finished then
      begin
        AJob.RequestCancel;
        Thr.FreeOnTerminate := True;
        if AJob.TryOwnResult then
        begin
          if AJob.Error = '' then
            AJob.Error := L('net.timeout');
          AJob.Ok := False;
          QueueResult(AJob);
        end;
      end
      else
      begin
        Thr.Free;
        if AJob.TryOwnResult then
        begin
          if AJob.Stopped and (AJob.Error = '') then
            AJob.Error := L('op.cancelled');
          if not AJob.Browse then
            AJob.Ok := AJob.Error = '';
          QueueResult(AJob);
        end;
      end;
    end);
  FTask := Task;
end;

function IsNetworkRoot(const APath: string): Boolean;
var
  S: string;
begin
  S := Trim(APath);
  Result := (S = '') or (S = '\') or (S = '\\') or (S = '/') or
    SameText(S, 'network') or SameText(S, 'Сеть');
end;

function ItemKind(ADisplay, AUsage: DWORD): TNetworkItemType;
begin
  case ADisplay of
    RESOURCEDISPLAYTYPE_SERVER:
      Result := nitServer;
    RESOURCEDISPLAYTYPE_SHARE, RESOURCEDISPLAYTYPE_SHAREADMIN:
      Result := nitShare;
    RESOURCEDISPLAYTYPE_FILE:
      Result := nitFile;
    RESOURCEDISPLAYTYPE_DIRECTORY:
      Result := nitDirectory;
    RESOURCEDISPLAYTYPE_DOMAIN, RESOURCEDISPLAYTYPE_GROUP,
    RESOURCEDISPLAYTYPE_NETWORK, RESOURCEDISPLAYTYPE_ROOT,
    RESOURCEDISPLAYTYPE_GENERIC:
      Result := nitWorkgroup;
  else
    if (AUsage and RESOURCEUSAGE_CONTAINER) <> 0 then
      Result := nitWorkgroup
    else
      Result := nitShare;
  end;
end;

procedure AddNetItem(const ASeed: TNetSeed; AItems: TList<TNetworkItem>);
var
  Item: TNetworkItem;
begin
  Item := Default(TNetworkItem);
  if ASeed.Comment <> '' then
    Item.Name := ASeed.Comment
  else
    Item.Name := ASeed.Remote;
  Item.FullPath := ASeed.Remote;
  Item.ItemType := ItemKind(ASeed.Display, ASeed.Usage);
  if Item.Name = '' then
    Item.Name := Item.FullPath;
  if (Item.ItemType = nitServer) and (Item.FullPath <> '') and
     not Item.FullPath.StartsWith('\\') then
    Item.FullPath := '\\' + Item.FullPath;
  if Item.FullPath = '' then
    Item.FullPath := Item.Name;
  if Item.Name = '' then
    Exit;
  Item.IsReadable := True;
  Item.IsWritable := Item.ItemType in [nitShare, nitDirectory, nitFile];
  AItems.Add(Item);
end;

function ReadSeeds(AParent: PNetResource; AJob: TNetJob; AUsage: DWORD;
  out AStatus: DWORD): TArray<TNetSeed>;
var
  H: THandle;
  Buf: TBytes;
  Count, Size, Status: DWORD;
  P: PNetResource;
  I, N: Integer;
  Seed: TNetSeed;
begin
  Result := nil;
  AStatus := NO_ERROR;
  H := 0;
  Status := WNetOpenEnum(RESOURCE_GLOBALNET, RESOURCETYPE_ANY, AUsage, AParent, H);
  // Повтор без фильтра контейнера: часть сетей отдаёт узлы только так.
  if (Status <> NO_ERROR) and (AUsage <> 0) then
    Status := WNetOpenEnum(RESOURCE_GLOBALNET, RESOURCETYPE_ANY, 0, AParent, H);
  if Status <> NO_ERROR then
  begin
    AStatus := Status;
    if H <> 0 then
      WNetCloseEnum(H);
    Exit;
  end;
  try
    SetLength(Buf, 32768);
    N := 0;
    repeat
      if AJob.Stopped then
        Break;
      Count := $FFFFFFFF;
      Size := Length(Buf);
      Status := WNetEnumResource(H, Count, @Buf[0], Size);
      if Status = ERROR_MORE_DATA then
      begin
        if (Size <= DWORD(Length(Buf))) or (Size > 1024 * 1024) then
          Size := DWORD(Length(Buf)) * 2;
        if Size > 1024 * 1024 then
          Break;
        SetLength(Buf, Size);
        Continue;
      end;
      if Status <> NO_ERROR then
        Break;
      P := @Buf[0];
      for I := 0 to Integer(Count) - 1 do
      begin
        if AJob.Stopped then
          Break;
        Seed := Default(TNetSeed);
        if P.lpRemoteName <> nil then
          Seed.Remote := P.lpRemoteName;
        if P.lpComment <> nil then
          Seed.Comment := P.lpComment;
        if P.lpProvider <> nil then
          Seed.Provider := P.lpProvider;
        Seed.ResType := P.dwType;
        Seed.Display := P.dwDisplayType;
        Seed.Usage := P.dwUsage;
        SetLength(Result, N + 1);
        Result[N] := Seed;
        Inc(N);
        Inc(P);
      end;
    until False;
    if (Status <> NO_ERROR) and (Status <> ERROR_NO_MORE_ITEMS) and
       (Status <> ERROR_MORE_DATA) then
      AStatus := Status;
  finally
    if H <> 0 then
      WNetCloseEnum(H);
  end;
end;

procedure FillFromSeeds(const ASeeds: TArray<TNetSeed>; AItems: TList<TNetworkItem>);
var
  I: Integer;
begin
  for I := 0 to High(ASeeds) do
    AddNetItem(ASeeds[I], AItems);
end;

function SeedMatches(const ASeed: TNetSeed; const APath: string): Boolean;
var
  Remote, Name: string;
begin
  Remote := ExcludeTrailingPathDelimiter(ASeed.Remote);
  Name := ASeed.Comment;
  if Name = '' then
    Name := ExtractFileName(Remote);
  Result := SameText(Remote, APath) or SameText(Name, APath) or
    SameText(ASeed.Remote, APath);
end;

const
  STYPE_DISKTREE = 0;
  STYPE_PRINTQ = 1;
  STYPE_DEVICE = 2;
  STYPE_IPC = 3;
  STYPE_SPECIAL = $80000000;
  NET_MAX_PREFERRED = DWORD($FFFFFFFF);
  NERR_SUCCESS = 0;

type
  TShareInfo1 = packed record
    NetName: PWideChar;
    ShareType: DWORD;
    Remark: PWideChar;
  end;
  PShareInfo1 = ^TShareInfo1;

function NetShareEnum(ServerName: PWideChar; Level: DWORD; var Buf: Pointer;
  PrefMaxLen: DWORD; EntriesRead, TotalEntries, ResumeHandle: PDWORD): DWORD; stdcall;
  external 'netapi32.dll' name 'NetShareEnum';
function NetApiBufferFree(Buffer: Pointer): DWORD; stdcall;
  external 'netapi32.dll' name 'NetApiBufferFree';

type
  TServerInfo101 = packed record
    PlatformId: DWORD;
    Name: PWideChar;
    VerMajor: DWORD;
    VerMinor: DWORD;
    ServerType: DWORD;
    Comment: PWideChar;
  end;
  PServerInfo101 = ^TServerInfo101;

function NetServerGetInfo(ServerName: PWideChar; Level: DWORD; var Buf: Pointer): DWORD; stdcall;
  external 'netapi32.dll' name 'NetServerGetInfo';

function HostResourceGroup(const AItem: TNetworkItem): Integer;
var
  Name, Blob: string;
  Kind: Cardinal;
begin
  Name := Trim(AItem.Name);
  Blob := LowerCase(Name + ' ' + AItem.Comment);
  if (Name <> '') and (Name[Length(Name)] = '$') then
    Exit(0);
  if (Pos('fax', Blob) > 0) or (Pos('факс', Blob) > 0) or
     (Pos('scanner', Blob) > 0) or (Pos('сканер', Blob) > 0) or
     (Pos('сканув', Blob) > 0) then
    Exit(3);
  Kind := AItem.ShareType and $7FFFFFFF;
  if (AItem.ResType = RESOURCETYPE_PRINT) or
     (AItem.FromShare and (Kind = STYPE_PRINTQ)) then
    Exit(2);
  if AItem.FromShare and (Kind = STYPE_IPC) then
    Exit(0);
  if (AItem.ResType = RESOURCETYPE_DISK) or
     (AItem.FromShare and (Kind = STYPE_DISKTREE)) then
    Exit(1);
  Result := 3;
end;

function NetbiosName(const AIp: string): string;
var
  S: TSocket;
  Addr: TSockAddrIn;
  Query: array[0..49] of Byte;
  Buf: array[0..1023] of Byte;
  Fd: TFDSet;
  Tv: TTimeVal;
  From: TSockAddr;
  FromLen, N, I, Count, J: Integer;
  P: PByte;
  Nm: string;
  Flags: Word;
  Host: MarshaledAString;
begin
  Result := '';
  Host := MarshaledAString(AnsiString(AIp));
  S := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if S = INVALID_SOCKET then
    Exit;
  try
    FillChar(Query, SizeOf(Query), 0);
    Query[0] := $80;
    Query[5] := 1;
    Query[12] := 32;
    Query[13] := Ord('C');
    Query[14] := Ord('K');
    for I := 15 to 44 do
      Query[I] := Ord('A');
    Query[47] := $21;
    Query[49] := 1;
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(137);
    Addr.sin_addr.S_addr := inet_addr(Host);
    if sendto(S, Query, SizeOf(Query), 0, Addr, SizeOf(Addr)) = SOCKET_ERROR then
      Exit;
    FD_ZERO(Fd);
    FD_SET(S, Fd);
    Tv.tv_sec := 0;
    Tv.tv_usec := 250000;
    if select(0, @Fd, nil, nil, @Tv) <= 0 then
      Exit;
    FromLen := SizeOf(From);
    N := recvfrom(S, Buf, SizeOf(Buf), 0, From, FromLen);
    // Вопрос: 12 байт заголовка, 34 байта имени, 4 байта типа.
    // Ответ сжимает имя указателем из 2 байт, дальше тип, класс, TTL, длина.
    if N < 63 then
      Exit;
    Count := Buf[62];
    if (Count <= 0) or (Count > 40) then
      Exit;
    P := @Buf[63];
    for I := 0 to Count - 1 do
    begin
      if NativeInt(P) + 18 > NativeInt(@Buf[0]) + N then
        Break;
      Nm := '';
      for J := 0 to 14 do
        if (P[J] >= 32) and (P[J] < 127) then
          Nm := Nm + Char(P[J]);
      Nm := Trim(Nm);
      Flags := (Word(P[16]) shl 8) or P[17];
      if (P[15] = 0) and ((Flags and $8000) = 0) and (Nm <> '') and
         not SameText(Nm, AIp) then
        Exit(Nm);
      Inc(P, 18);
    end;
  finally
    closesocket(S);
  end;
end;

function HostNameBlank(const AHost: TNetworkHost): Boolean;
begin
  Result := (Trim(AHost.Name) = '') or SameText(Trim(AHost.Name), AHost.Address);
end;

function SmbServerName(const AIp: string): string;
var
  Buf: Pointer;
  Info: PServerInfo101;
  Status: DWORD;
  Server, Nm, Comment: string;
begin
  Result := '';
  if AIp = '' then
    Exit;
  Buf := nil;
  Server := '\\' + AIp;
  Status := NetServerGetInfo(PWideChar(Server), 101, Buf);
  if (Status <> NERR_SUCCESS) or (Buf = nil) then
    Exit;
  try
    Info := PServerInfo101(Buf);
    Nm := '';
    Comment := '';
    if Info.Name <> nil then
      Nm := Trim(string(Info.Name));
    if Info.Comment <> nil then
      Comment := Trim(string(Info.Comment));
    if (Nm <> '') and not SameText(Nm, AIp) then
      Result := Nm
    else if (Comment <> '') and not SameText(Comment, AIp) then
      Result := Comment;
    if Length(Result) > 48 then
      Result := Trim(Copy(Result, 1, 48));
  finally
    NetApiBufferFree(Buf);
  end;
end;

function HttpDeviceTitle(const AIp: string): string;
const
  Limit = 8192;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  Text, Low, Raw: string;
  P, Q, I: Integer;
begin
  Result := '';
  if AIp = '' then
    Exit;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 800;
    Client.ResponseTimeout := 800;
    Client.HandleRedirects := True;
    Client.MaxRedirects := 1;
    Client.UserAgent := 'VibeCmd';
    try
      Resp := Client.Get('http://' + AIp + '/');
    except
      Exit;
    end;
    if (Resp = nil) or (Resp.StatusCode = 404) then
      Exit;
    try
      Text := Resp.ContentAsString;
    except
      Exit;
    end;
    if Length(Text) > Limit then
      SetLength(Text, Limit);
    Low := LowerCase(Text);
    P := Pos('<title', Low);
    if P <= 0 then
      Exit;
    Q := PosEx('>', Low, P);
    if Q <= 0 then
      Exit;
    I := PosEx('</title', Low, Q + 1);
    if I <= Q then
      Exit;
    Raw := Trim(Copy(Text, Q + 1, I - Q - 1));
    Raw := Raw.Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ');
    while Pos('  ', Raw) > 0 do
      Raw := Raw.Replace('  ', ' ');
    if Raw = '' then
      Exit;
    if SameText(Raw, AIp) then
      Exit;
    if SameText(Raw, '403 Forbidden') or SameText(Raw, '404 Not Found') or
       SameText(Raw, '401 Unauthorized') or StartsText('Index of', Raw) then
      Exit;
    if Length(Raw) > 48 then
      Raw := Trim(Copy(Raw, 1, 48));
    Result := Raw;
  finally
    Client.Free;
  end;
end;

procedure SaveFoundHost(AList: TList<TNetworkHost>; ALock: TCriticalSection;
  const AHost: TNetworkHost);
var
  I: Integer;
begin
  if (AList = nil) or (ALock = nil) or (AHost.Address = '') then
    Exit;
  ALock.Enter;
  try
    for I := 0 to AList.Count - 1 do
      if SameText(AList[I].Address, AHost.Address) then
      begin
        AList[I] := AHost;
        Exit;
      end;
    AList.Add(AHost);
  finally
    ALock.Leave;
  end;
end;

procedure QueueNetHost(ASlot: INetSlot; AGen: Integer; AOnHost: TProc<TNetworkHost>;
  const AHost: TNetworkHost);
var
  One: TNetworkHost;
  Cb: TProc<TNetworkHost>;
  G: Integer;
  Sl: INetSlot;
begin
  if not Assigned(AOnHost) then
    Exit;
  One := AHost;
  Cb := AOnHost;
  G := AGen;
  Sl := ASlot;
  TThread.Queue(nil,
    procedure
    begin
      if (Sl <> nil) and not Sl.Accept(G) then
        Exit;
      Cb(One);
    end);
end;

function NodeJunk(const ASeed: TNetSeed): Boolean;
var
  Blob: string;
begin
  Blob := LowerCase(ASeed.Remote + '|' + ASeed.Comment + '|' + ASeed.Provider);
  Result := (Pos('dlna', Blob) > 0) or (Pos('youtube', Blob) > 0) or
    (Pos('wsd', Blob) > 0) or (Pos('function discovery', Blob) > 0) or
    (Pos('web client', Blob) > 0) or (Pos('terminal services', Blob) > 0) or
    (Pos('media device', Blob) > 0) or (Pos('multimedia', Blob) > 0) or
    (Pos('медиаустрой', Blob) > 0) or (Pos('мультимедиа', Blob) > 0) or
    (Pos('устройства мультимедиа', Blob) > 0);
end;

function HostItemExists(AJob: TNetJob; const APath, AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AJob = nil) or (AJob.Items = nil) then
    Exit;
  for I := 0 to AJob.Items.Count - 1 do
    if SameText(AJob.Items[I].FullPath, APath) or
       ((AName <> '') and SameText(AJob.Items[I].Name, AName)) then
      Exit(True);
end;

procedure AddHostItem(AJob: TNetJob; const AName, APath, AComment: string;
  ARes, AShare: Cardinal; AFromShare, AFromWNet: Boolean);
var
  Item: TNetworkItem;
begin
  if (AJob = nil) or (AJob.Items = nil) or (AName = '') or (APath = '') then
    Exit;
  if HostItemExists(AJob, APath, AName) then
    Exit;
  Item := Default(TNetworkItem);
  Item.Name := AName;
  Item.FullPath := APath;
  Item.Comment := AComment;
  Item.ResType := ARes;
  Item.ShareType := AShare;
  Item.FromShare := AFromShare;
  Item.FromWNet := AFromWNet;
  Item.ItemType := nitShare;
  Item.IsReadable := True;
  Item.IsWritable := ARes <> RESOURCETYPE_PRINT;
  AJob.Items.Add(Item);
end;

function ListHostResources(const AServer: string; AJob: TNetJob;
  out AStatus: DWORD): Boolean;
var
  Buf: Pointer;
  Read, Total, Resume, Kind: DWORD;
  Info: PShareInfo1;
  I: Integer;
  Server, ShareName, Remark, Path: string;
  Res: Cardinal;
  Parent: TNetResource;
  Seeds: TArray<TNetSeed>;
  Seed: TNetSeed;
  Got: Boolean;
begin
  Result := False;
  AStatus := NO_ERROR;
  if (AJob = nil) or (AJob.Items = nil) then
    Exit;
  Server := ExcludeTrailingPathDelimiter(Trim(AServer));
  if not Server.StartsWith('\\') then
    Server := '\\' + Server;
  if Server = '\\' then
    Exit;
  Got := False;
  Resume := 0;
  repeat
    if AJob.Stopped then
      Exit;
    Buf := nil;
    Read := 0;
    Total := 0;
    AStatus := NetShareEnum(PWideChar(Server), 1, Buf, NET_MAX_PREFERRED,
      @Read, @Total, @Resume);
    if (AStatus <> NERR_SUCCESS) and (AStatus <> ERROR_MORE_DATA) then
    begin
      if Buf <> nil then
        NetApiBufferFree(Buf);
      Break;
    end;
    Got := True;
    Info := PShareInfo1(Buf);
    for I := 0 to Integer(Read) - 1 do
    begin
      if AJob.Stopped then
        Break;
      if Info.NetName <> nil then
      begin
        ShareName := Trim(Info.NetName);
        Remark := '';
        if Info.Remark <> nil then
          Remark := Trim(Info.Remark);
        Kind := Info.ShareType and not STYPE_SPECIAL;
        if Kind = STYPE_PRINTQ then
          Res := RESOURCETYPE_PRINT
        else if (Kind = STYPE_DISKTREE) or (Kind = STYPE_IPC) then
          Res := RESOURCETYPE_DISK
        else
          Res := 0;
        if ShareName <> '' then
          AddHostItem(AJob, ShareName, Server + '\' + ShareName, Remark, Res,
            Info.ShareType, True, False);
      end;
      Inc(Info);
    end;
    if Buf <> nil then
      NetApiBufferFree(Buf);
  until AStatus <> ERROR_MORE_DATA;
  if AJob.Stopped then
    Exit;
  FillChar(Parent, SizeOf(Parent), 0);
  Parent.dwScope := RESOURCE_GLOBALNET;
  Parent.dwType := RESOURCETYPE_ANY;
  Parent.dwDisplayType := RESOURCEDISPLAYTYPE_SERVER;
  Parent.dwUsage := 0;
  Parent.lpRemoteName := PChar(Server);
  Seeds := ReadSeeds(@Parent, AJob, 0, Kind);
  if (not Got) and (AJob.Items.Count = 0) and (Kind <> NO_ERROR) and
     (Kind <> ERROR_NO_MORE_ITEMS) then
    AStatus := Kind;
  for I := 0 to High(Seeds) do
  begin
    if AJob.Stopped then
      Break;
    Seed := Seeds[I];
    if NodeJunk(Seed) then
      Continue;
    Path := ExcludeTrailingPathDelimiter(Trim(Seed.Remote));
    if (Path = '') or SameText(Path, Server) then
      Continue;
    ShareName := '';
    if Path <> '' then
    begin
      ShareName := Path;
      if LastDelimiter('\', ShareName) > 0 then
        ShareName := Copy(ShareName, LastDelimiter('\', ShareName) + 1, MaxInt);
      ShareName := Trim(ShareName);
    end;
    if ShareName = '' then
      ShareName := Trim(Seed.Comment);
    if ShareName = '' then
      Continue;
    Remark := Trim(Seed.Comment);
    if SameText(Remark, ShareName) then
      Remark := '';
    AddHostItem(AJob, ShareName, Path, Remark, Seed.ResType, 0, False, True);
  end;
  Result := AJob.Items.Count > 0;
  if Got and (AStatus = ERROR_MORE_DATA) then
    AStatus := NO_ERROR;
  if Result then
    AStatus := NO_ERROR
  else if Got then
  begin
    AStatus := NO_ERROR;
    Result := True;
  end;
end;

procedure SmbBrowse(AJob: TNetJob; const APath: string);
var
  Seeds: TArray<TNetSeed>;
  Status: DWORD;
  Parent: TNetResource;
  Match, Tail, Spec: string;
  Found: Boolean;
  I: Integer;
  H: THandle;
  Data: TWin32FindData;
  Item: TNetworkItem;
  LocalFt: TFileTime;
  Sys: TSystemTime;
begin
  if IsNetworkRoot(APath) then
  begin
    Seeds := ReadSeeds(nil, AJob, RESOURCEUSAGE_CONTAINER, Status);
    if (Status <> NO_ERROR) and (Length(Seeds) = 0) then
      AJob.Error := NetStatusText(Status)
    else
      FillFromSeeds(Seeds, AJob.Items);
    Exit;
  end;

  Tail := Trim(APath);
  if Tail.StartsWith('\\') then
  begin
    Match := ExcludeTrailingPathDelimiter(Tail);
    if not Copy(Match, 3, MaxInt).Contains('\') then
    begin
      { Диск, IPC$, принтеры и то, что реально отдал WNet. DLNA сюда не входит. }
      if not ListHostResources(Match, AJob, Status) then
      begin
        if AJob.Stopped then
          Exit;
        if (AJob.Items = nil) or (AJob.Items.Count = 0) then
          AJob.Error := NetStatusText(Status);
      end;
      Exit;
    end;

    Spec := IncludeTrailingPathDelimiter(Match) + '*';
    H := FindFirstFile(PChar(Spec), Data);
    if H = INVALID_HANDLE_VALUE then
    begin
      AJob.Error := NetStatusText(GetLastError);
      Exit;
    end;
    try
      repeat
        if AJob.Stopped then
          Break;
        if (StrComp(Data.cFileName, '.') = 0) or (StrComp(Data.cFileName, '..') = 0) then
          Continue;
        Item := Default(TNetworkItem);
        Item.Name := Data.cFileName;
        Item.FullPath := IncludeTrailingPathDelimiter(Match) + Item.Name;
        if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          Item.ItemType := nitDirectory
        else
          Item.ItemType := nitFile;
        Item.Size := (Int64(Data.nFileSizeHigh) shl 32) or Data.nFileSizeLow;
        if FileTimeToLocalFileTime(Data.ftLastWriteTime, LocalFt) and
           FileTimeToSystemTime(LocalFt, Sys) then
          Item.ModifiedDate := SystemTimeToDateTime(Sys);
        Item.IsReadable := True;
        Item.IsWritable := (Data.dwFileAttributes and FILE_ATTRIBUTE_READONLY) = 0;
        AJob.Items.Add(Item);
      until not FindNextFile(H, Data);
    finally
      Winapi.Windows.FindClose(H);
    end;
    Exit;
  end;

  Seeds := ReadSeeds(nil, AJob, RESOURCEUSAGE_CONTAINER, Status);
  if (Status <> NO_ERROR) and (Length(Seeds) = 0) then
  begin
    AJob.Error := NetStatusText(Status);
    Exit;
  end;
  Found := False;
  for I := 0 to High(Seeds) do
    if SeedMatches(Seeds[I], Tail) then
    begin
      FillChar(Parent, SizeOf(Parent), 0);
      Parent.dwScope := RESOURCE_GLOBALNET;
      Parent.dwType := Seeds[I].ResType;
      Parent.dwDisplayType := Seeds[I].Display;
      Parent.dwUsage := Seeds[I].Usage;
      Parent.lpRemoteName := PChar(Seeds[I].Remote);
      if Seeds[I].Provider <> '' then
        Parent.lpProvider := PChar(Seeds[I].Provider);
      Seeds := ReadSeeds(@Parent, AJob, RESOURCEUSAGE_CONTAINER, Status);
      if (Status <> NO_ERROR) and (Length(Seeds) = 0) then
        AJob.Error := NetStatusText(Status)
      else
        FillFromSeeds(Seeds, AJob.Items);
      Found := True;
      Break;
    end;
  if not Found then
    AJob.Error := L('net.group.missing');
end;

procedure SmbCopy(AJob: TNetJob; const ASource, ADest: string);
begin
  AJob.FCopyCancel := False;
  if not CopyFileEx(PChar(ASource), PChar(ADest), @SmbCopyProgress, AJob,
       @AJob.FCopyCancel, 0) then
  begin
    if AJob.Stopped or (GetLastError = ERROR_REQUEST_ABORTED) then
    begin
      if AJob.Error = '' then
        AJob.Error := L('op.cancelled');
    end
    else if AJob.Error = '' then
      AJob.Error := NetStatusText(GetLastError);
  end;
end;

procedure TSMBProvider.BrowseAsync(const APath: string;
  ACallback: TNetworkOperationCallback);
var
  Job: TNetJob;
  Path: string;
begin
  Path := APath;
  Job := BeginJob(ACallback, True);
  RunJob(Job,
    procedure
    begin
      SmbBrowse(Job, Path);
    end, NET_WAIT_MS);
end;

procedure TSMBProvider.CopyFileAsync(const ASource, ADest: string;
  AOnProgress: TProc<Int64, Int64>; AOnComplete: TProc<Boolean, string>);
var
  Job: TNetJob;
  Source, Dest: string;
begin
  Source := ASource;
  Dest := ADest;
  Job := BeginJob(nil, False);
  Job.OnProgress := AOnProgress;
  Job.OnComplete := AOnComplete;
  RunJob(Job,
    procedure
    begin
      SmbCopy(Job, Source, Dest);
    end, NET_WAIT_MS);
end;

function FtpParts(const AUrl: string; out AUser, APassword, AHost: string;
  out APort: Integer; out APath: string): Boolean;
var
  U: TURI;
begin
  Result := False;
  AUser := '';
  APassword := '';
  AHost := '';
  APort := 21;
  APath := '/';
  if AUrl.Trim.StartsWith('sftp://', True) then
    Exit;
  try
    U := TURI.Create(AUrl.Trim);
  except
    Exit;
  end;
  if not SameText(U.Scheme, 'ftp') then
    Exit;
  AUser := U.Username;
  APassword := U.Password;
  AHost := U.Host;
  APort := U.Port;
  if APort <= 0 then
    APort := 21;
  APath := U.Path;
  if APath = '' then
    APath := '/';
  Result := AHost <> '';
end;

function FtpChildUrl(const AUser, APassword, AHost: string; APort: Integer;
  const ADir, AName: string): string;
var
  U: TURI;
  Dir: string;
begin
  Dir := ADir;
  if (Dir = '') or (Dir = '/') then
    Dir := '/' + AName
  else
    Dir := ExcludeTrailingPathDelimiter(Dir) + '/' + AName;
  U := Default(TURI);
  U.Scheme := 'ftp';
  U.Username := AUser;
  U.Password := APassword;
  U.Host := AHost;
  U.Port := APort;
  U.Path := Dir;
  Result := U.ToString;
end;

procedure FtpBrowse(AJob: TNetJob; const AUrl: string);
var
  User, Password, Host, Path: string;
  Port: Integer;
  Ftp: TIdFTP;
  I: Integer;
  Entry: TIdFTPListItem;
  Item: TNetworkItem;
begin
  if AUrl.Trim.StartsWith('sftp://', True) then
  begin
    AJob.Error := L('net.sftp.unsupported');
    Exit;
  end;
  if not FtpParts(AUrl, User, Password, Host, Port, Path) then
  begin
    AJob.Error := L('net.need.ftp');
    Exit;
  end;
  Ftp := TIdFTP.Create(nil);
  try
    Ftp.Host := Host;
    Ftp.Port := Port;
    Ftp.Passive := True;
    Ftp.ConnectTimeout := 8000;
    Ftp.ReadTimeout := 8000;
    if User = '' then
    begin
      Ftp.Username := 'anonymous';
      Ftp.Password := 'anonymous@';
    end
    else
    begin
      Ftp.Username := User;
      Ftp.Password := Password;
    end;
    // Connect с AutoLogin сам шлёт OPTS UTF8 ON и переключает кодировку списка.
    Ftp.Connect;
    try
      if AJob.Stopped then
      begin
        AJob.Error := L('op.cancelled');
        Exit;
      end;
      if (Path <> '') and (Path <> '/') then
        Ftp.ChangeDir(Path);
      Ftp.List;
      for I := 0 to Ftp.DirectoryListing.Count - 1 do
      begin
        if AJob.Stopped then
        begin
          AJob.Error := L('op.cancelled');
          Break;
        end;
        Entry := Ftp.DirectoryListing[I];
        if (Entry.FileName = '') or (Entry.FileName = '.') or (Entry.FileName = '..') then
          Continue;
        Item := Default(TNetworkItem);
        Item.Name := Entry.FileName;
        Item.FullPath := FtpChildUrl(User, Password, Host, Port, Path, Entry.FileName);
        if Entry.ItemType in [ditDirectory, ditSymbolicLinkDir] then
          Item.ItemType := nitDirectory
        else
          Item.ItemType := nitFile;
        Item.Size := Entry.Size;
        Item.ModifiedDate := Entry.ModifiedDate;
        Item.IsReadable := True;
        Item.IsWritable := True;
        AJob.Items.Add(Item);
      end;
    finally
      Ftp.Disconnect;
    end;
  finally
    Ftp.Free;
  end;
end;

procedure FtpCopy(AJob: TNetJob; const ASource, ADest: string;
  AOnProgress: TProc<Int64, Int64>);
var
  User, Password, Host, Path, Remote: string;
  Port: Integer;
  Ftp: TIdFTP;
  Tick: TFtpProgress;
  Download: Boolean;
begin
  Download := FtpParts(ASource, User, Password, Host, Port, Path);
  if not Download then
  begin
    if not FtpParts(ADest, User, Password, Host, Port, Path) then
    begin
      AJob.Error := L('net.need.ftp');
      Exit;
    end;
  end;
  if Download and ADest.Trim.StartsWith('ftp://', True) then
  begin
    AJob.Error := L('net.ftp.both');
    Exit;
  end;
  Ftp := TIdFTP.Create(nil);
  Tick := TFtpProgress.Create;
  try
    Tick.Ftp := Ftp;
    Tick.Job := AJob;
    Tick.OnProgress := AOnProgress;
    Ftp.OnWorkBegin := Tick.BeginWork;
    Ftp.OnWork := Tick.Work;
    Ftp.Host := Host;
    Ftp.Port := Port;
    Ftp.Passive := True;
    Ftp.TransferType := ftBinary;
    Ftp.ConnectTimeout := 8000;
    Ftp.ReadTimeout := 8000;
    if User = '' then
    begin
      Ftp.Username := 'anonymous';
      Ftp.Password := 'anonymous@';
    end
    else
    begin
      Ftp.Username := User;
      Ftp.Password := Password;
    end;
    Ftp.Connect;
    try
      if Download then
      begin
        Remote := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
        if (Remote <> '') and (Remote <> Path) then
          Ftp.ChangeDir(ExtractFilePath(Path).Replace('\', '/'));
        if Remote = '' then
          Remote := Path;
        Ftp.Get(Remote, ADest, True, False);
      end
      else
      begin
        Remote := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
        if Remote = '' then
          Remote := ExtractFileName(ASource);
        Ftp.Put(ASource, Remote, False);
      end;
    finally
      Ftp.Disconnect;
    end;
  finally
    Tick.Free;
    Ftp.Free;
  end;
end;

procedure TFTPProvider.BrowseAsync(const APath: string;
  ACallback: TNetworkOperationCallback);
var
  Job: TNetJob;
  Path: string;
begin
  Path := APath;
  Job := BeginJob(ACallback, True);
  RunJob(Job,
    procedure
    begin
      FtpBrowse(Job, Path);
    end, NET_WAIT_MS);
end;

procedure TFTPProvider.CopyFileAsync(const ASource, ADest: string;
  AOnProgress: TProc<Int64, Int64>; AOnComplete: TProc<Boolean, string>);
var
  Job: TNetJob;
  Source, Dest: string;
  Progress: TProc<Int64, Int64>;
begin
  Source := ASource;
  Dest := ADest;
  Progress := AOnProgress;
  Job := BeginJob(nil, False);
  Job.OnProgress := AOnProgress;
  Job.OnComplete := AOnComplete;
  RunJob(Job,
    procedure
    begin
      FtpCopy(Job, Source, Dest, Progress);
    end, NET_WAIT_MS);
end;

function DavParts(const AUrl: string; out AUser, APassword, ABase: string): Boolean;
var
  U: TURI;
begin
  Result := False;
  try
    U := TURI.Create(Trim(AUrl));
  except
    Exit;
  end;
  if not (SameText(U.Scheme, 'http') or SameText(U.Scheme, 'https')) then
    Exit;
  AUser := U.Username;
  APassword := U.Password;
  ABase := U.ToString;
  Result := U.Host <> '';
end;

function TagValue(const ABlock, ALocal: string): string;
var
  S, Low, Key: string;
  P, Q: Integer;
begin
  Result := '';
  S := ABlock;
  Low := LowerCase(S);
  Key := LowerCase(ALocal);
  P := Pos(Key, Low);
  if P = 0 then
    Exit;
  P := Pos('>', S, P);
  if P = 0 then
    Exit;
  Q := Pos('<', S, P + 1);
  if Q <= P then
    Exit;
  Result := Trim(Copy(S, P + 1, Q - P - 1));
  Result := Result.Replace('&amp;', '&').Replace('&lt;', '<').Replace('&gt;', '>');
end;

function DavHref(const AHref, APage, AUser, APassword: string): string;
var
  Base, Target: TURI;
  AbsUrl: string;
begin
  if AHref.StartsWith('http://', True) or AHref.StartsWith('https://', True) then
    AbsUrl := AHref
  else
  begin
    Base := TURI.Create(APage);
    AbsUrl := TURI.PathRelativeToAbs(AHref, Base);
  end;
  if (AUser = '') or AbsUrl.Contains('@') then
    Exit(AbsUrl);
  Target := TURI.Create(AbsUrl);
  Target.Username := AUser;
  Target.Password := APassword;
  Result := Target.ToString;
end;

procedure DavBrowse(AJob: TNetJob; const AUrl: string);
const
  Body =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<d:propfind xmlns:d="DAV:"><d:prop>' +
    '<d:displayname/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/>' +
    '</d:prop></d:propfind>';
var
  User, Password, Page: string;
  Client: THTTPClient;
  Req: IHTTPRequest;
  Resp: IHTTPResponse;
  Source: TBytesStream;
  Text, Block, Href, Name, SelfPath, Child: string;
  P, Q: Integer;
  Item: TNetworkItem;
  Headers: TNetHeaders;
begin
  if not DavParts(AUrl, User, Password, Page) then
  begin
    AJob.Error := L('net.need.http');
    Exit;
  end;
  Client := THTTPClient.Create;
  Source := TBytesStream.Create(TEncoding.UTF8.GetBytes(Body));
  try
    Client.ConnectionTimeout := 8000;
    Client.ResponseTimeout := 8000;
    if User <> '' then
    begin
      SetLength(Headers, 1);
      Headers[0] := TNetHeader.Create('Authorization',
        'Basic ' + TNetEncoding.Base64.Encode(User + ':' + Password).Replace(#13, '').Replace(#10, ''));
    end;
    Req := Client.GetRequest('PROPFIND', Page);
    Req.AddHeader('Depth', '1');
    Req.AddHeader('Content-Type', 'application/xml; charset=utf-8');
    Req.SourceStream := Source;
    Resp := Client.Execute(Req, nil, Headers);
    if AJob.Stopped then
    begin
      AJob.Error := L('op.cancelled');
      Exit;
    end;
    if not (Resp.StatusCode in [200, 207]) then
    begin
      case Resp.StatusCode of
        401: AJob.Error := L('net.dav.auth');
        403: AJob.Error := L('net.dav.denied');
        404: AJob.Error := L('net.dav.missing');
      else
        AJob.Error := 'WebDAV: ' + IntToStr(Resp.StatusCode);
      end;
      Exit;
    end;
    Text := Resp.ContentAsString;
    SelfPath := TURI.Create(Page).Path;
    P := 1;
    while True do
    begin
      if AJob.Stopped then
      begin
        AJob.Error := L('op.cancelled');
        Break;
      end;
      Q := Pos('<', Text, P);
      if Q = 0 then
        Break;
      if not LowerCase(Copy(Text, Q, 12)).Contains('response') then
      begin
        P := Q + 1;
        Continue;
      end;
      P := Pos('>', Text, Q);
      Q := Pos('response>', LowerCase(Text), P);
      if Q = 0 then
        Break;
      Block := Copy(Text, P, Q - P);
      P := Q + 9;
      Href := TagValue(Block, 'href');
      if Href = '' then
        Continue;
      Child := DavHref(Href, Page, User, Password);
      if SameText(TURI.Create(Child).Path, SelfPath) then
        Continue;
      Item := Default(TNetworkItem);
      Name := TagValue(Block, 'displayname');
      if Name = '' then
        Name := ExtractFileName(ExcludeTrailingPathDelimiter(TURI.Create(Child).Path.Replace('/', '\')));
      if (Name = '') or (Name = '.') or (Name = '..') then
        Continue;
      Item.Name := Name;
      Item.FullPath := Child;
      if LowerCase(Block).Contains('collection') then
        Item.ItemType := nitDirectory
      else
        Item.ItemType := nitFile;
      Item.Size := StrToInt64Def(TagValue(Block, 'getcontentlength'), 0);
      try
        if TagValue(Block, 'getlastmodified') <> '' then
          Item.ModifiedDate := HttpToDate(TagValue(Block, 'getlastmodified'), False);
      except
        Item.ModifiedDate := 0;
      end;
      Item.IsReadable := True;
      Item.IsWritable := True;
      AJob.Items.Add(Item);
    end;
  finally
    Source.Free;
    Client.Free;
  end;
end;

procedure DavCopy(AJob: TNetJob; const ASource, ADest: string;
  AOnProgress: TProc<Int64, Int64>);
var
  User, Password, Page: string;
  Client: THTTPClient;
  Headers: TNetHeaders;
  Stream: TFileStream;
  Resp: IHTTPResponse;
  Download: Boolean;
begin
  Download := DavParts(ASource, User, Password, Page);
  if not Download then
  begin
    if not DavParts(ADest, User, Password, Page) then
    begin
      AJob.Error := L('net.need.http');
      Exit;
    end;
  end;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 8000;
    Client.ResponseTimeout := 8000;
    if User <> '' then
    begin
      SetLength(Headers, 1);
      Headers[0] := TNetHeader.Create('Authorization',
        'Basic ' + TNetEncoding.Base64.Encode(User + ':' + Password).Replace(#13, '').Replace(#10, ''));
    end;
    Client.ReceiveDataCallback :=
      procedure(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean)
      begin
        AAbort := AJob.Stopped;
        if AAbort and (AJob.Error = '') then
          AJob.Error := L('op.cancelled');
        QueueProgress(AJob, AReadCount, AContentLength);
      end;
    if Download then
    begin
      Stream := TFileStream.Create(ADest, fmCreate);
      try
        Resp := Client.Get(Page, Stream, Headers);
        if not (Resp.StatusCode in [200, 201, 204]) and (AJob.Error = '') then
          AJob.Error := 'WebDAV: ' + IntToStr(Resp.StatusCode);
      finally
        Stream.Free;
      end;
    end
    else
    begin
      Stream := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
      try
        Resp := Client.Put(Page, Stream, nil, Headers);
        if not (Resp.StatusCode in [200, 201, 204]) and (AJob.Error = '') then
          AJob.Error := 'WebDAV: ' + IntToStr(Resp.StatusCode);
        QueueProgress(AJob, Stream.Size, Stream.Size);
      finally
        Stream.Free;
      end;
    end;
  finally
    Client.Free;
  end;
end;

procedure TWebDAVProvider.BrowseAsync(const APath: string;
  ACallback: TNetworkOperationCallback);
var
  Job: TNetJob;
  Path: string;
begin
  Path := APath;
  Job := BeginJob(ACallback, True);
  RunJob(Job,
    procedure
    begin
      DavBrowse(Job, Path);
    end, NET_WAIT_MS);
end;

procedure TWebDAVProvider.CopyFileAsync(const ASource, ADest: string;
  AOnProgress: TProc<Int64, Int64>; AOnComplete: TProc<Boolean, string>);
var
  Job: TNetJob;
  Source, Dest: string;
  Progress: TProc<Int64, Int64>;
begin
  Source := ASource;
  Dest := ADest;
  Progress := AOnProgress;
  Job := BeginJob(nil, False);
  Job.OnProgress := AOnProgress;
  Job.OnComplete := AOnComplete;
  RunJob(Job,
    procedure
    begin
      DavCopy(Job, Source, Dest, Progress);
    end, NET_WAIT_MS);
end;

function Octets(const AIp: string; out A, B, C, D: Integer): Boolean;
var
  P: TArray<string>;
begin
  Result := False;
  P := AIp.Split(['.']);
  if Length(P) <> 4 then
    Exit;
  A := StrToIntDef(P[0], -1);
  B := StrToIntDef(P[1], -1);
  C := StrToIntDef(P[2], -1);
  D := StrToIntDef(P[3], -1);
  Result := (A >= 0) and (A <= 255) and (B >= 0) and (B <= 255) and
    (C >= 0) and (C <= 255) and (D >= 0) and (D <= 255);
end;

function IsPrivateIp(const AIp: string): Boolean;
var
  A, B, C, D: Integer;
begin
  Result := False;
  if not Octets(AIp, A, B, C, D) then
    Exit;
  if A = 10 then
    Exit(True);
  if (A = 172) and (B >= 16) and (B <= 31) then
    Exit(True);
  if (A = 192) and (B = 168) then
    Exit(True);
  if (A = 169) and (B = 254) then
    Exit(True);
end;

function IpFromDword(AValue: DWORD): string;
var
  Bytes: array[0..3] of Byte absolute AValue;
begin
  Result := Format('%d.%d.%d.%d', [Bytes[0], Bytes[1], Bytes[2], Bytes[3]]);
end;

function LocalSubnetPrefix: string;
var
  Size: ULONG;
  Mem: TBytes;
  Table: PMIB_IPADDRTABLE;
  Row: PMibIpAddrRow;
  I: Integer;
  Ip: string;
  A, B, C, D: Integer;
begin
  Result := '';
  Size := 0;
  if GetIpAddrTable(nil, Size, False) <> ERROR_INSUFFICIENT_BUFFER then
    Exit;
  SetLength(Mem, Size);
  Table := PMIB_IPADDRTABLE(@Mem[0]);
  if GetIpAddrTable(Table, Size, False) <> NO_ERROR then
    Exit;
  Row := @Table.table[0];
  for I := 0 to Integer(Table.dwNumEntries) - 1 do
  begin
    Ip := IpFromDword(Row.dwAddr);
    if IsPrivateIp(Ip) and Octets(Ip, A, B, C, D) and (D <> 0) then
      Exit(Format('%d.%d.%d', [A, B, C]));
    Inc(Row);
  end;
end;

function BuildHostList(const ASubnet: string; out AError: string): TArray<string>;
var
  S, Left, Right, Prefix: string;
  Dash, A1, B1, C1, D1, A2, B2, C2, D2, I, N: Integer;
begin
  Result := nil;
  AError := '';
  S := Trim(ASubnet);
  if S = '' then
  begin
    Prefix := LocalSubnetPrefix;
    if Prefix = '' then
    begin
      AError := L('net.subnet.none');
      Exit;
    end;
    S := Prefix;
  end;
  Dash := Pos('-', S);
  if Dash > 0 then
  begin
    Left := Trim(Copy(S, 1, Dash - 1));
    Right := Trim(Copy(S, Dash + 1, MaxInt));
    if not Octets(Left, A1, B1, C1, D1) or not Octets(Right, A2, B2, C2, D2) then
    begin
      AError := L('net.subnet.bad');
      Exit;
    end;
    if (A1 <> A2) or (B1 <> B2) or (C1 <> C2) or (D2 < D1) then
    begin
      AError := L('net.subnet.range');
      Exit;
    end;
  end
  else if Octets(S, A1, B1, C1, D1) then
  begin
    D1 := 1;
    D2 := 254;
  end
  else
  begin
    Prefix := S.TrimRight(['.']);
    if not Octets(Prefix + '.1', A1, B1, C1, D1) then
    begin
      AError := L('net.subnet.bad');
      Exit;
    end;
    D1 := 1;
    D2 := 254;
  end;
  if (D2 - D1 + 1) > SCAN_CAP then
  begin
    AError := L('net.subnet.wide');
    Exit;
  end;
  N := 0;
  for I := D1 to D2 do
  begin
    Left := Format('%d.%d.%d.%d', [A1, B1, C1, I]);
    if not IsPrivateIp(Left) then
    begin
      AError := L('net.subnet.local');
      Exit(nil);
    end;
    SetLength(Result, N + 1);
    Result[N] := Left;
    Inc(N);
  end;
end;

function OuiVendor(const AMac: string): string;
var
  P: string;
begin
  P := UpperCase(Copy(AMac, 1, 8));
  if (P = '00-0C-29') or (P = '00-50-56') or (P = '00-05-69') then
    Exit('VMware');
  if P = '08-00-27' then
    Exit('VirtualBox');
  if (P = 'B8-27-EB') or (P = 'DC-A6-32') or (P = 'E4-5F-01') then
    Exit('Raspberry Pi');
  if (P = '00-1A-11') or (P = '3C-5A-B4') or (P = 'F4-F5-D8') then
    Exit('Google');
  if (P = '00-17-88') or (P = 'B0-C5-54') then
    Exit('Philips Hue');
  { Порожньо: підпис «невідомий» ставить список уже поточною мовою. }
  Result := '';
end;

function IcmpCreateFile: THandle; stdcall; external 'iphlpapi.dll' name 'IcmpCreateFile';
function IcmpCloseHandle(IcmpHandle: THandle): BOOL; stdcall; external 'iphlpapi.dll' name 'IcmpCloseHandle';
function IcmpSendEcho(IcmpHandle: THandle; DestinationAddress: ULONG;
  RequestData: Pointer; RequestSize: Word; RequestOptions: Pointer;
  ReplyBuffer: Pointer; ReplySize: DWORD; Timeout: DWORD): DWORD; stdcall;
  external 'iphlpapi.dll' name 'IcmpSendEcho';

function PingHost(const AIp: string; ATimeout: DWORD = PING_MS): Boolean;
var
  Icmp: THandle;
  Dest: u_long;
  Req: AnsiString;
  Reply: array[0..63] of Byte;
  Addr: MarshaledAString;
begin
  Result := False;
  Addr := MarshaledAString(AnsiString(AIp));
  Dest := inet_addr(Addr);
  if DWORD(Dest) = INADDR_NONE then
    Exit;
  Icmp := IcmpCreateFile;
  if Icmp = INVALID_HANDLE_VALUE then
    Exit;
  try
    Req := 'VIBE';
    Result := IcmpSendEcho(Icmp, Dest, PAnsiChar(Req), Length(Req), nil,
      @Reply[0], SizeOf(Reply), ATimeout) > 0;
  finally
    IcmpCloseHandle(Icmp);
  end;
end;

function HostToIPv4(const AHost: string): string;
var
  H: PHostEnt;
  Addr: TInAddr;
  P: PAnsiChar;
begin
  Result := Trim(AHost);
  if Result = '' then
    Exit;
  if Cardinal(inet_addr(MarshaledAString(AnsiString(Result)))) <> Cardinal(INADDR_NONE) then
    Exit;
  H := gethostbyname(MarshaledAString(AnsiString(Result)));
  if (H = nil) or (H^.h_addr_list = nil) then
    Exit('');
  P := H^.h_addr_list^;
  if P = nil then
    Exit('');
  Move(P^, Addr, SizeOf(Addr));
  Result := string(inet_ntoa(Addr));
end;

function ProbeHostAlive(const AHost: string): Boolean;
var
  Data: TWSAData;
  Started: Boolean;
  Ip: string;
begin
  Result := False;
  Started := WSAStartup($0202, Data) = 0;
  try
    Ip := HostToIPv4(AHost);
    if Ip = '' then
      Exit;
    Result := PingHost(Ip, 800);
  finally
    if Started then
      WSACleanup;
  end;
end;

function PortOpen(const AIp: string; APort: Word): Boolean;
var
  S: TSocket;
  Addr: TSockAddrIn;
  Mode: u_long;
  Fd: TFDSet;
  Tv: TTimeVal;
  Err, Len: Integer;
  Host: MarshaledAString;
begin
  Result := False;
  Host := MarshaledAString(AnsiString(AIp));
  S := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if S = INVALID_SOCKET then
    Exit;
  try
    Mode := 1;
    if ioctlsocket(S, FIONBIO, Mode) <> 0 then
      Exit;
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(APort);
    Addr.sin_addr.S_addr := inet_addr(Host);
    connect(S, Addr, SizeOf(Addr));
    FD_ZERO(Fd);
    FD_SET(S, Fd);
    Tv.tv_sec := 0;
    Tv.tv_usec := PORT_MS * 1000;
    if select(0, nil, @Fd, nil, @Tv) <= 0 then
      Exit;
    Err := 0;
    Len := SizeOf(Err);
    if getsockopt(S, SOL_SOCKET, SO_ERROR, MarshaledAString(@Err), Len) <> 0 then
      Exit;
    Result := Err = 0;
  finally
    closesocket(S);
  end;
end;

function HostMac(const AIp: string): string;
var
  Dest: u_long;
  Buf: array[0..7] of Byte;
  Len: ULONG;
  Host: MarshaledAString;
begin
  Result := '';
  Host := MarshaledAString(AnsiString(AIp));
  Dest := inet_addr(Host);
  if DWORD(Dest) = INADDR_NONE then
    Exit;
  FillChar(Buf, SizeOf(Buf), 0);
  Len := 6;
  if SendARP(Dest, 0, PULONG(@Buf[0]), Len) <> NO_ERROR then
    Exit;
  if Len < 6 then
    Exit;
  Result := Format('%.2X-%.2X-%.2X-%.2X-%.2X-%.2X',
    [Buf[0], Buf[1], Buf[2], Buf[3], Buf[4], Buf[5]]);
end;

constructor TNetworkDiscovery.Create;
begin
  inherited Create;
  FSlot := TNetSlot.Create;
end;

destructor TNetworkDiscovery.Destroy;
begin
  Cancel;
  if FSlot <> nil then
    FSlot.Kill;
  FSlot := nil;
  FTask := nil;
  inherited;
end;

procedure TNetworkDiscovery.Cancel;
begin
  if FTask <> nil then
  begin
    FTask.Cancel;
    FTask := nil;
  end;
  if FJob <> nil then
    FJob.RequestCancel;
end;

procedure TNetworkDiscovery.ScanAsync(const ASubnet: string;
  AOnHost: TProc<TNetworkHost>; AOnDone: TProc<string>);
var
  Job: TNetJob;
  Subnet: string;
  OnHost: TProc<TNetworkHost>;
  OnDone: TProc<string>;
begin
  if FJob <> nil then
    FJob.RequestCancel;
  if FTask <> nil then
    FTask.Cancel;
  Subnet := ASubnet;
  OnHost := AOnHost;
  OnDone := AOnDone;
  Job := TNetJob.Create(FSlot, FSlot.NextGen);
  FJob := Job;
  FTask := TTask.Run(
    procedure
    var
      Hosts: TArray<string>;
      Err: string;
      Data: TWSAData;
      Started: Boolean;
      Gen: Integer;
      Slot: INetSlot;
      Found: TList<TNetworkHost>;
      FoundLock: TCriticalSection;
      WebCount, K: Integer;
      Pick, One: TNetworkHost;
      Title: string;
    begin
      Started := False;
      Err := '';
      Gen := Job.Gen;
      Slot := Job.Slot;
      Found := TList<TNetworkHost>.Create;
      FoundLock := TCriticalSection.Create;
      try
        try
        Hosts := BuildHostList(Subnet, Err);
        // Ошибка подсети и сбой сокетов не выходят из процедуры: ниже всё равно
        // закрываются сокеты и в главный поток уходит OnDone.
        if Err = '' then
        begin
          if WSAStartup($0202, Data) <> 0 then
            Err := L('net.sockets')
          else
          begin
            Started := True;
            if Length(Hosts) > 0 then
              TParallel.&For(0, High(Hosts),
          procedure(I: Integer)
          var
            Host: TNetworkHost;
            Ip, Extra: string;
            A, B, C, D: Integer;
          begin
            if Job.Stopped then
              Exit;
            Ip := Hosts[I];
            if not PingHost(Ip) then
              Exit;
            if Job.Stopped then
              Exit;
            Host := Default(TNetworkHost);
            Host.Address := Ip;
            Host.HasFTP := PortOpen(Ip, 21);
            Host.HasSMB := PortOpen(Ip, 445);
            Host.Port80 := PortOpen(Ip, 80);
            Host.Port443 := PortOpen(Ip, 443);
            Host.HasWebAdmin := Host.Port80 or Host.Port443;
            Host.Mac := HostMac(Ip);
            if Host.Mac <> '' then
              Host.Vendor := OuiVendor(Host.Mac);
            if Octets(Ip, A, B, C, D) and (D = 1) then
              Host.IsRouter := True;
            { Строка с IP сразу. Имя дорисовывается в ту же запись. }
            SaveFoundHost(Found, FoundLock, Host);
            QueueNetHost(Slot, Gen, OnHost, Host);
            if Job.Stopped then
              Exit;
            Extra := NetbiosName(Ip);
            if (Extra <> '') and not Job.Stopped then
            begin
              Host.Name := Extra;
              SaveFoundHost(Found, FoundLock, Host);
              QueueNetHost(Slot, Gen, OnHost, Host);
            end;
            if Job.Stopped then
              Exit;
            if Host.HasSMB and HostNameBlank(Host) then
            begin
              Extra := SmbServerName(Ip);
              if (Extra <> '') and not Job.Stopped then
              begin
                Host.Name := Extra;
                SaveFoundHost(Found, FoundLock, Host);
                QueueNetHost(Slot, Gen, OnHost, Host);
              end;
            end;
            if Job.Stopped or not Host.IsRouter or not HostNameBlank(Host) then
              Exit;
            Extra := HttpDeviceTitle(Ip);
            if (Extra <> '') and not Job.Stopped then
            begin
              Host.Name := Extra;
              SaveFoundHost(Found, FoundLock, Host);
              QueueNetHost(Slot, Gen, OnHost, Host);
            end;
          end);
                if not Job.Stopped then
                begin
                  WebCount := 0;
                  Pick := Default(TNetworkHost);
                  FoundLock.Enter;
                  try
                    for K := 0 to Found.Count - 1 do
                    begin
                      One := Found[K];
                      if One.IsRouter or One.HasSMB or not One.HasWebAdmin then
                        Continue;
                      Inc(WebCount);
                      Pick := One;
                    end;
                  finally
                    FoundLock.Leave;
                  end;
                  if (WebCount = 1) and not Job.Stopped then
                  begin
                    Pick.IsRouter := True;
                    if HostNameBlank(Pick) then
                    begin
                      Title := HttpDeviceTitle(Pick.Address);
                      if Title <> '' then
                        Pick.Name := Title;
                    end;
                    if not Job.Stopped then
                    begin
                      SaveFoundHost(Found, FoundLock, Pick);
                      QueueNetHost(Slot, Gen, OnHost, Pick);
                    end;
                  end;
                end;
            if Job.Stopped and (Err = '') then
              Err := L('op.cancelled');
          end;
        end;
      except
        on E: Exception do
          if Err = '' then
            Err := CleanError(E.Message);
      end;
      if Started then
        WSACleanup;
      if Assigned(OnDone) then
        TThread.Queue(nil,
          procedure
          begin
            if (Slot <> nil) and not Slot.Accept(Gen) then
              Exit;
            OnDone(Err);
          end);
      finally
        FoundLock.Free;
        Found.Free;
      end;
    end);
end;

procedure QueueClassicRow(ASlot: INetSlot; AGen: Integer;
  AOnRow: TProc<TClassicRow>; const ARow: TClassicRow);
var
  One: TClassicRow;
  Cb: TProc<TClassicRow>;
  G: Integer;
  Sl: INetSlot;
begin
  if not Assigned(AOnRow) or (ARow.FullPath = '') then
    Exit;
  One := ARow;
  Cb := AOnRow;
  G := AGen;
  Sl := ASlot;
  TThread.Queue(nil,
    procedure
    begin
      if (Sl <> nil) and not Sl.Accept(G) then
        Exit;
      Cb(One);
    end);
end;

function ClassicBlob(const ASeed: TNetSeed): string;
begin
  Result := LowerCase(ASeed.Remote + '|' + ASeed.Comment + '|' + ASeed.Provider);
end;

function ClassicJunk(const ASeed: TNetSeed): Boolean;
var
  Blob: string;
begin
  if ASeed.ResType = RESOURCETYPE_PRINT then
    Exit(True);
  Blob := ClassicBlob(ASeed);
  Result := (Pos('dlna', Blob) > 0) or (Pos('youtube', Blob) > 0) or
    (Pos('wsd', Blob) > 0) or (Pos('function discovery', Blob) > 0) or
    (Pos('web client', Blob) > 0) or (Pos('terminal services', Blob) > 0) or
    (Pos('media device', Blob) > 0) or (Pos('multimedia', Blob) > 0) or
    (Pos('медиаустрой', Blob) > 0) or (Pos('мультимедиа', Blob) > 0) or
    (Pos('устройства мультимедиа', Blob) > 0);
end;

function ClassicServerName(const ARemote: string): string;
var
  S: string;
  P: Integer;
begin
  S := Trim(ARemote);
  if S.StartsWith('\\') then
    Delete(S, 1, 2);
  P := Pos('\', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  Result := Trim(S);
end;

function ClassicShareName(const ARemote: string): string;
var
  S: string;
  P: Integer;
begin
  S := ExcludeTrailingPathDelimiter(Trim(ARemote));
  P := LastDelimiter('\', S);
  if P > 0 then
    Result := Trim(Copy(S, P + 1, MaxInt))
  else
    Result := '';
end;

function ClassicIsShare(const ASeed: TNetSeed): Boolean;
begin
  Result := (ASeed.Display = RESOURCEDISPLAYTYPE_SHARE) or
    (ASeed.Display = RESOURCEDISPLAYTYPE_SHAREADMIN);
  if not Result then
    Exit;
  if ASeed.ResType = RESOURCETYPE_PRINT then
    Exit(False);
  Result := (ASeed.ResType = RESOURCETYPE_DISK) or (ASeed.ResType = RESOURCETYPE_ANY);
  if Result then
    Result := ClassicShareName(ASeed.Remote) <> '';
end;

function ClassicIsContainer(const ASeed: TNetSeed): Boolean;
begin
  if (ASeed.Display = RESOURCEDISPLAYTYPE_SERVER) or
     (ASeed.Display = RESOURCEDISPLAYTYPE_SHARE) or
     (ASeed.Display = RESOURCEDISPLAYTYPE_SHAREADMIN) or
     (ASeed.Display = RESOURCEDISPLAYTYPE_FILE) or
     (ASeed.Display = RESOURCEDISPLAYTYPE_DIRECTORY) then
    Exit(False);
  Result := ((ASeed.Usage and RESOURCEUSAGE_CONTAINER) <> 0) or
    (ASeed.Display = RESOURCEDISPLAYTYPE_DOMAIN) or
    (ASeed.Display = RESOURCEDISPLAYTYPE_GROUP) or
    (ASeed.Display = RESOURCEDISPLAYTYPE_NETWORK) or
    (ASeed.Display = RESOURCEDISPLAYTYPE_ROOT) or
    (ASeed.Display = RESOURCEDISPLAYTYPE_GENERIC);
end;

constructor TClassicNet.Create;
begin
  inherited Create;
  FSlot := TNetSlot.Create;
end;

destructor TClassicNet.Destroy;
begin
  Cancel;
  if FSlot <> nil then
    FSlot.Kill;
  FSlot := nil;
  FTask := nil;
  inherited;
end;

procedure TClassicNet.Cancel;
begin
  if FSlot <> nil then
    FSlot.NextGen;
  if FTask <> nil then
  begin
    FTask.Cancel;
    FTask := nil;
  end;
  if FJob <> nil then
    FJob.RequestCancel;
end;

procedure WalkClassic(AJob: TNetJob; ASlot: INetSlot; AGen: Integer;
  AOnRow: TProc<TClassicRow>; AVisited: TStringList; AParent: PNetResource;
  ADepth: Integer);
var
  Seeds: TArray<TNetSeed>;
  Status: DWORD;
  I: Integer;
  Seed: TNetSeed;
  Row: TClassicRow;
  Host, Share, Key, Remote, Provider: string;
  Child: TNetResource;
begin
  if (AJob = nil) or (ADepth > 4) or AJob.Stopped then
    Exit;
  Seeds := ReadSeeds(AParent, AJob, 0, Status);
  for I := 0 to High(Seeds) do
  begin
    if AJob.Stopped then
      Exit;
    Seed := Seeds[I];
    if ClassicJunk(Seed) then
      Continue;
    if Seed.Display = RESOURCEDISPLAYTYPE_SERVER then
    begin
      Host := ClassicServerName(Seed.Remote);
      if Host = '' then
        Host := Trim(Seed.Comment);
      if Host = '' then
        Continue;
      Row := Default(TClassicRow);
      Row.Name := Host;
      Row.FullPath := 'network://' + Host;
      Row.IsShare := False;
      QueueClassicRow(ASlot, AGen, AOnRow, Row);
      Continue;
    end;
    if ClassicIsShare(Seed) then
    begin
      Share := ClassicShareName(Seed.Remote);
      Row := Default(TClassicRow);
      Row.Name := Share;
      Row.FullPath := ExcludeTrailingPathDelimiter(Seed.Remote);
      Row.IsShare := True;
      QueueClassicRow(ASlot, AGen, AOnRow, Row);
      Continue;
    end;
    if not ClassicIsContainer(Seed) then
      Continue;
    Remote := Seed.Remote;
    Provider := Seed.Provider;
    Key := Remote;
    if Key = '' then
      Key := Provider + '/' + Seed.Comment;
    if Key = '' then
      Continue;
    if (AVisited <> nil) and (AVisited.IndexOf(Key) >= 0) then
      Continue;
    if AVisited <> nil then
      AVisited.Add(Key);
    FillChar(Child, SizeOf(Child), 0);
    Child.dwScope := RESOURCE_GLOBALNET;
    Child.dwType := Seed.ResType;
    Child.dwDisplayType := Seed.Display;
    Child.dwUsage := Seed.Usage;
    if Remote <> '' then
      Child.lpRemoteName := PChar(Remote);
    if Provider <> '' then
      Child.lpProvider := PChar(Provider);
    WalkClassic(AJob, ASlot, AGen, AOnRow, AVisited, @Child, ADepth + 1);
  end;
end;

procedure TClassicNet.Start(AOnRow: TProc<TClassicRow>; AOnDone: TProc<string>);
var
  Job: TNetJob;
  OnRow: TProc<TClassicRow>;
  OnDone: TProc<string>;
begin
  if FJob <> nil then
    FJob.RequestCancel;
  if FTask <> nil then
    FTask.Cancel;
  if FSlot <> nil then
    FSlot.NextGen;
  OnRow := AOnRow;
  OnDone := AOnDone;
  Job := TNetJob.Create(FSlot, FSlot.NextGen);
  FJob := Job;
  FTask := TTask.Run(
    procedure
    var
      Gen: Integer;
      Slot: INetSlot;
      Visited: TStringList;
      Err: string;
    begin
      Err := '';
      Gen := Job.Gen;
      Slot := Job.Slot;
      Visited := TStringList.Create;
      Visited.CaseSensitive := False;
      try
        try
          WalkClassic(Job, Slot, Gen, OnRow, Visited, nil, 0);
        except
          on E: Exception do
            if Err = '' then
              Err := CleanError(E.Message);
        end;
      finally
        Visited.Free;
      end;
      if Assigned(OnDone) then
        TThread.Queue(nil,
          procedure
          begin
            if (Slot <> nil) and not Slot.Accept(Gen) then
              Exit;
            OnDone(Err);
          end);
    end);
end;

procedure BindNetworkBrowse(AFs: TNetworkFileSystem; const APath: string;
  const AApply: TProc<TNetworkItemList>; const AFail: TProc<string>);
begin
  if AFs = nil then
    Exit;
  AFs.BrowseAsync(APath,
    procedure(const AItems: TNetworkItemList; const AError: string)
    begin
      if AError <> '' then
      begin
        if Assigned(AFail) then
          AFail(AError);
      end
      else if Assigned(AApply) then
        AApply(AItems);
    end);
end;

end.
