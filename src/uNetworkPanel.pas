unit uNetworkPanel;

// Сессия панели «Сеть»: живые узлы, история и чтение шар. Без форм.
// Список файлов панели сюда не пишется, пока панель сама не попросит снимок.

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  uFileModel,
  uNetworkVfs,
  uLang;

type
  TNetworkSession = class
  private
    FDiscovery: TNetworkDiscovery;
    FSmb: TSMBProvider;
    FFtp: TFTPProvider;
    FDav: TWebDAVProvider;
    FHosts: TList<TNetworkHost>;
    FExtra: TList<TNetworkHost>;
    FClassic: TClassicNet;
    FClassicRows: TList<TClassicRow>;
    FClassicStarted: Boolean;
    FHist: TStringList;
    FItems: TNetworkItemList;
    FSeq: Integer;
    FBrowseSeq: Integer;
    FScanning: Boolean;
    FBrowsing: Boolean;
    FDidScan: Boolean;
    FScanError: Boolean;
    FError: string;
    FSubnet: string;
    FBrowsePath: string;
    FOwner: NativeUInt;
    FPing: TDictionary<string, string>;
    FOnChange: TNotifyEvent;
    FOnPrefs: TNotifyEvent;
    procedure ApplyPing(var AEntry: TFileEntry; const AKey: string);
    procedure Changed;
    procedure PutHost(AList: TList<TNetworkHost>; const AHost: TNetworkHost);
    function HostSeen(const AAddr: string): Boolean;
    function ClassicBlocks(const AHost: TNetworkHost): Boolean;
    function Remember(const APath: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure CancelJobs;
    procedure Stop;
    procedure Scan(const ASubnet: string);
    procedure Browse(const APath: string; APrompt: Boolean = True);
    procedure TouchClassic;
    procedure SetOwnerWindow(AOwner: NativeUInt);
    procedure AddAddress(const AText: string);
    procedure Forget(const APath: string);
    procedure ClearHistory;
    function IsRecentRow(const APath: string): Boolean;
    procedure NoteOpened(const APath: string);
    procedure NotePing(const AHost, AText, AAlso: string);
    function HostByAddress(const AAddr: string; out AHost: TNetworkHost): Boolean;
    procedure LoadPrefs(const ASubnet, AHistory: string);
    procedure FillRoot(AList: TFileEntryList);
    procedure FillBrowse(AList: TFileEntryList);
    function StatusText(const AViewPath: string): string;
    function TileLine: string;
    function HistoryText: string;
    function ResolvedSubnet: string;
    property Subnet: string read FSubnet;
    property BrowsePath: string read FBrowsePath;
    property Scanning: Boolean read FScanning;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnPrefs: TNotifyEvent read FOnPrefs write FOnPrefs;
  end;

implementation

function IpSortKey(const AAddress: string): string;
var
  P: TArray<string>;
  N: array[0..3] of Integer;
  I: Integer;
begin
  P := AAddress.Split(['.']);
  if Length(P) <> 4 then
    Exit('z' + AAddress);
  for I := 0 to 3 do
  begin
    N[I] := StrToIntDef(P[I], -1);
    if (N[I] < 0) or (N[I] > 255) then
      Exit('z' + AAddress);
  end;
  Result := 'a' + IntToHex(N[0], 2) + IntToHex(N[1], 2) +
    IntToHex(N[2], 2) + IntToHex(N[3], 2);
end;

function FlagText(const AHost: TNetworkHost): string;
begin
  Result := '';
  if AHost.HasSMB then
    Result := 'SMB';
  if AHost.HasFTP then
    if Result = '' then
      Result := 'FTP'
    else
      Result := Result + ' · FTP';
  if AHost.HasWebAdmin then
    if Result = '' then
      Result := 'Web'
    else
      Result := Result + ' · Web';
  if AHost.IsRouter then
    if Result = '' then
      Result := L('net.flag.host')
    else
      Result := Result + ' · ' + L('net.flag.host');
end;

function HostIconKey(const AHost: TNetworkHost): string;
begin
  if AHost.IsRouter then
    Exit('#stock:103');
  if AHost.HasSMB or
     ((Trim(AHost.Name) <> '') and not SameText(Trim(AHost.Name), AHost.Address)) then
    Exit('#stock:94');
  if AHost.HasFTP and not AHost.HasSMB then
    Exit('#stock:51');
  Result := '#stock:17';
end;

function HostOfPath(const APath: string): string;
var
  S: string;
  P: Integer;
begin
  if IsVibeNetworkPath(APath) then
    Exit(VibeNetworkHost(APath));
  if not IsUncPath(APath) then
    Exit('');
  S := ExcludeTrailingPathDelimiter(APath);
  if Length(S) <= 2 then
    Exit('');
  Delete(S, 1, 2);
  P := Pos('\', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  Result := S;
end;

procedure AddHead(AList: TFileEntryList; const ATitle: string);
var
  E: TFileEntry;
begin
  E := Default(TFileEntry);
  E.Name := ATitle;
  if SameText(ATitle, 'Компьютеры') then
    E.DisplayName := L('net.computers')
  else if SameText(ATitle, 'Сеть') then
    E.DisplayName := L('net.section.net')
  else if SameText(ATitle, 'Найденные') then
    E.DisplayName := L('net.found')
  else if SameText(ATitle, 'Недавние') then
    E.DisplayName := L('net.recent')
  else if SameText(ATitle, 'Админ') then
    E.DisplayName := L('net.group.admin')
  else if SameText(ATitle, 'Шари') then
    E.DisplayName := L('net.group.shares')
  else if SameText(ATitle, 'Принтеры') then
    E.DisplayName := L('net.group.print')
  else if SameText(ATitle, 'Другое') then
    E.DisplayName := L('net.group.other')
  else
    E.DisplayName := ATitle;
  E.IconKey := '#nethead';
  AList.Add(E);
end;

procedure AddPc(AList: TFileEntryList; const AHost: TNetworkHost; ADim: Boolean);
var
  E: TFileEntry;
begin
  E := Default(TFileEntry);
  E.Name := Trim(AHost.Name);
  if E.Name = '' then
    E.Name := AHost.Address;
  E.DisplayName := E.Name;
  E.FullPath := 'network://' + AHost.Address;
  E.IsDirectory := True;
  E.FreeBytes := 1;
  E.IconKey := HostIconKey(AHost);
  E.DisplayType := AHost.Address;
  if Trim(AHost.Vendor) <> '' then
    E.DisplaySize := Trim(AHost.Vendor)
  else
    E.DisplaySize := L('net.vendor.unknown');
  if FlagText(AHost) <> '' then
    E.DisplaySize := E.DisplaySize + ' · ' + FlagText(AHost);
  E.DisplayDate := AHost.Mac;
  E.IsHidden := ADim;
  AList.Add(E);
end;

function UrlHost(const AUrl: string): string;
var
  S: string;
  P: Integer;
begin
  S := Trim(AUrl);
  P := Pos('://', S);
  if P > 0 then
    Delete(S, 1, P + 2);
  P := Pos('@', S);
  if P > 0 then
    Delete(S, 1, P);
  P := Pos('/', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  P := Pos('\', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  if (S <> '') and (S[1] <> '[') then
  begin
    P := Pos(':', S);
    if P > 0 then
      S := Copy(S, 1, P - 1);
  end;
  Result := S;
end;

function FourOctets(const AHost: string): Boolean;
var
  P: TArray<string>;
  I, N: Integer;
begin
  Result := False;
  P := AHost.Split(['.']);
  if Length(P) <> 4 then
    Exit;
  for I := 0 to 3 do
  begin
    if P[I] = '' then
      Exit;
    N := StrToIntDef(P[I], -1);
    if (N < 0) or (N > 255) then
      Exit;
  end;
  Result := True;
end;

function HostLabelOk(const AHost: string): Boolean;
var
  S: string;
begin
  Result := False;
  S := Trim(AHost);
  if S = '' then
    Exit;
  if (Pos(' ', S) > 0) or (Pos('/', S) > 0) or (Pos('\', S) > 0) or
     (Pos('@', S) > 0) then
    Exit;
  if FourOctets(S) then
    Exit(IsPrivateIp(S));
  if Pos('.', S) > 0 then
    Exit;
  Result := True;
end;

function HistoryStorePath(const APath: string): string;
var
  S, Scheme, Rest: string;
  P, At: Integer;
begin
  S := Trim(APath);
  if IsUncPath(S) and not IsVibeNetworkPath(S) then
    Exit(ExcludeTrailingPathDelimiter(S));
  if StartsText('ftp://', S) or StartsText('ftps://', S) then
  begin
    P := Pos('://', S);
    Scheme := Copy(S, 1, P + 2);
    Rest := Copy(S, P + 3, MaxInt);
    At := Pos('@', Rest);
    if At > 0 then
      Delete(Rest, 1, At);
    Exit(Scheme + Rest);
  end;
  if StartsText('network://', S) or SameText(S, 'network://') then
    Exit(NormalizeVibeNetwork(S));
  Result := S;
end;

function UncShareHost(const APath: string; out AHost: string): Boolean;
var
  S, Share: string;
  P: Integer;
begin
  Result := False;
  AHost := '';
  if not IsUncPath(APath) or IsVibeNetworkPath(APath) then
    Exit;
  S := ExcludeTrailingPathDelimiter(APath);
  if Length(S) <= 2 then
    Exit;
  Delete(S, 1, 2);
  P := Pos('\', S);
  if P <= 1 then
    Exit;
  AHost := Copy(S, 1, P - 1);
  Share := Copy(S, P + 1, MaxInt);
  P := Pos('\', Share);
  if P > 0 then
    Share := Copy(Share, 1, P - 1);
  Result := (AHost <> '') and (Share <> '');
end;

function HistAllowed(const APath: string): Boolean;
var
  S, Host: string;
begin
  Result := False;
  S := HistoryStorePath(APath);
  if (S = '') or SameText(S, 'network://') then
    Exit;
  if UncShareHost(S, Host) then
    Exit(HostLabelOk(Host));
  if StartsText('network://', S) then
    Exit(HostLabelOk(VibeNetworkHost(S)));
  if StartsText('ftp://', S) or StartsText('ftps://', S) then
    Exit(HostLabelOk(UrlHost(S)));
end;

constructor TNetworkSession.Create;
begin
  inherited Create;
  FDiscovery := TNetworkDiscovery.Create;
  FClassic := TClassicNet.Create;
  FSmb := TSMBProvider.Create;
  FFtp := TFTPProvider.Create;
  FDav := TWebDAVProvider.Create;
  FHosts := TList<TNetworkHost>.Create;
  FClassicRows := TList<TClassicRow>.Create;
  FExtra := TList<TNetworkHost>.Create;
  FHist := TStringList.Create;
  FHist.CaseSensitive := False;
  FPing := TDictionary<string, string>.Create;
end;

destructor TNetworkSession.Destroy;
begin
  FOnChange := nil;
  FOnPrefs := nil;
  CancelJobs;
  if FClassic <> nil then
    FClassic.Cancel;
  FDiscovery.Free;
  FClassic.Free;
  FSmb.Free;
  FFtp.Free;
  FDav.Free;
  FHosts.Free;
  FClassicRows.Free;
  FExtra.Free;
  FHist.Free;
  FPing.Free;
  inherited;
end;

procedure TNetworkSession.ApplyPing(var AEntry: TFileEntry; const AKey: string);
var
  Key, Text: string;
begin
  if (FPing = nil) or (AKey = '') then
    Exit;
  Key := AnsiLowerCase(Trim(AKey));
  if not FPing.TryGetValue(Key, Text) or (Text = '') then
    Exit;
  { Код, не фраза: зміна мови перекладає рядок без нового пінгу. }
  if Text = 'up' then
    Text := L('panel.net.ping.up')
  else if Text = 'down' then
    Text := L('panel.net.ping.down');
  if AEntry.DisplaySize = '' then
    AEntry.DisplaySize := Text
  else if Pos(Text, AEntry.DisplaySize) = 0 then
    AEntry.DisplaySize := AEntry.DisplaySize + ' · ' + Text;
end;

procedure TNetworkSession.NotePing(const AHost, AText, AAlso: string);
var
  Key: string;
begin
  if (FPing = nil) or (AText = '') then
    Exit;
  Key := AnsiLowerCase(Trim(AHost));
  if Key <> '' then
    FPing.AddOrSetValue(Key, AText);
  Key := AnsiLowerCase(Trim(AAlso));
  if (Key <> '') and not SameText(Key, AnsiLowerCase(Trim(AHost))) then
    FPing.AddOrSetValue(Key, AText);
  if (Trim(AHost) = '') and (Trim(AAlso) = '') then
    Exit;
  Changed;
end;

function TNetworkSession.HostByAddress(const AAddr: string;
  out AHost: TNetworkHost): Boolean;
var
  I: Integer;
  Key: string;
begin
  Result := False;
  AHost := Default(TNetworkHost);
  Key := Trim(AAddr);
  if Key = '' then
    Exit;
  for I := 0 to FHosts.Count - 1 do
    if SameText(FHosts[I].Address, Key) or SameText(Trim(FHosts[I].Name), Key) then
    begin
      AHost := FHosts[I];
      Exit(True);
    end;
  for I := 0 to FExtra.Count - 1 do
    if SameText(FExtra[I].Address, Key) or SameText(Trim(FExtra[I].Name), Key) then
    begin
      AHost := FExtra[I];
      Exit(True);
    end;
end;

procedure TNetworkSession.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TNetworkSession.PutHost(AList: TList<TNetworkHost>;
  const AHost: TNetworkHost);
var
  I: Integer;
begin
  if AHost.Address = '' then
    Exit;
  for I := 0 to AList.Count - 1 do
    if SameText(AList[I].Address, AHost.Address) then
    begin
      AList[I] := AHost;
      Exit;
    end;
  AList.Add(AHost);
end;

function ClassicRowHost(const ARow: TClassicRow): string;
begin
  if ARow.IsShare then
    Result := HostOfPath(ARow.FullPath)
  else
    Result := VibeNetworkHost(ARow.FullPath);
  if Result = '' then
    Result := ARow.Name;
end;

function SameHostToken(const A, B: string): Boolean;
begin
  Result := (Trim(A) <> '') and (Trim(B) <> '') and SameText(Trim(A), Trim(B));
end;

function TNetworkSession.HostSeen(const AAddr: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if AAddr = '' then
    Exit;
  for I := 0 to FHosts.Count - 1 do
    if SameText(FHosts[I].Address, AAddr) or
       SameText(Trim(FHosts[I].Name), AAddr) then
      Exit(True);
  for I := 0 to FExtra.Count - 1 do
    if SameText(FExtra[I].Address, AAddr) or
       SameText(Trim(FExtra[I].Name), AAddr) then
      Exit(True);
  for I := 0 to FClassicRows.Count - 1 do
    if SameText(ClassicRowHost(FClassicRows[I]), AAddr) or
       SameText(FClassicRows[I].Name, AAddr) then
      Exit(True);
end;

function TNetworkSession.ClassicBlocks(const AHost: TNetworkHost): Boolean;
var
  I: Integer;
  Nm: string;
begin
  Result := False;
  Nm := Trim(AHost.Name);
  if SameText(Nm, AHost.Address) then
    Nm := '';
  for I := 0 to FClassicRows.Count - 1 do
    if SameHostToken(ClassicRowHost(FClassicRows[I]), AHost.Address) or
       SameHostToken(ClassicRowHost(FClassicRows[I]), Nm) or
       SameHostToken(FClassicRows[I].Name, AHost.Address) or
       SameHostToken(FClassicRows[I].Name, Nm) then
      Exit(True);
end;

procedure TNetworkSession.CancelJobs;
begin
  Inc(FSeq);
  Inc(FBrowseSeq);
  FScanning := False;
  FBrowsing := False;
  if FDiscovery <> nil then
    FDiscovery.Cancel;
  if FSmb <> nil then
    FSmb.Cancel;
  if FFtp <> nil then
    FFtp.Cancel;
  if FDav <> nil then
    FDav.Cancel;
end;

procedure TNetworkSession.Stop;
begin
  if not FScanning then
    Exit;
  if FDiscovery <> nil then
    FDiscovery.Cancel;
  FScanning := False;
  FDidScan := True;
  FError := '';
  FScanError := False;
  Changed;
end;

procedure TNetworkSession.SetOwnerWindow(AOwner: NativeUInt);
begin
  if AOwner <> 0 then
    FOwner := AOwner;
end;

procedure TNetworkSession.TouchClassic;
begin
  if FClassicStarted or (FClassic = nil) then
    Exit;
  FClassicStarted := True;
  FClassic.Start(
    procedure(ARow: TClassicRow)
    var
      I: Integer;
    begin
      for I := 0 to FClassicRows.Count - 1 do
        if SameText(FClassicRows[I].FullPath, ARow.FullPath) then
          Exit;
      FClassicRows.Add(ARow);
      Changed;
    end,
    procedure(AErr: string)
    begin
      if AErr <> '' then
        Changed
      else
        Changed;
    end);
end;

procedure TNetworkSession.Scan(const ASubnet: string);
var
  Token: Integer;
  Use: string;
begin
  if FDiscovery <> nil then
    FDiscovery.Cancel;
  Inc(FSeq);
  Token := FSeq;
  Use := Trim(ASubnet);
  if Use = '' then
    Use := LocalSubnetPrefix;
  FSubnet := Use;
  FHosts.Clear;
  FError := '';
  FScanError := False;
  FScanning := True;
  FDidScan := False;
  Changed;
  FDiscovery.ScanAsync(Use,
    procedure(AHost: TNetworkHost)
    begin
      if Token <> FSeq then
        Exit;
      PutHost(FHosts, AHost);
      Changed;
    end,
    procedure(AErr: string)
    begin
      if Token <> FSeq then
        Exit;
      FScanning := False;
      if (AErr = '') or SameText(AErr, L('op.cancelled')) then
      begin
        FDidScan := True;
        FError := '';
        FScanError := False;
        if (AErr = '') and Assigned(FOnPrefs) then
          FOnPrefs(Self);
      end
      else
      begin
        FError := AErr;
        FScanError := True;
        FDidScan := True;
      end;
      Changed;
    end);
end;

procedure TNetworkSession.Browse(const APath: string; APrompt: Boolean);
var
  Token: Integer;
  Host, Target: string;
  Fs: TNetworkFileSystem;
  Known: TNetworkHost;
  I: Integer;
  AllowPrompt: Boolean;
begin
  Inc(FBrowseSeq);
  Token := FBrowseSeq;
  AllowPrompt := APrompt;
  if FSmb <> nil then
    FSmb.Cancel;
  if FFtp <> nil then
    FFtp.Cancel;
  if FDav <> nil then
    FDav.Cancel;
  if not SameText(FBrowsePath, APath) then
    SetLength(FItems, 0);
  FBrowsePath := APath;
  FError := '';
  FScanError := False;
  FBrowsing := True;
  Changed;
  Host := VibeNetworkHost(APath);
  Fs := FSmb;
  Target := '';
  if StartsText('ftp://', APath) or StartsText('ftps://', APath) or
     StartsText('sftp://', APath) then
  begin
    Fs := FFtp;
    Target := APath;
  end
  else if StartsText('http://', APath) or StartsText('https://', APath) then
  begin
    Fs := FDav;
    Target := APath;
  end
  else
  begin
    Target := '\\' + Host;
    Known := Default(TNetworkHost);
    for I := 0 to FHosts.Count - 1 do
      if SameText(FHosts[I].Address, Host) then
      begin
        Known := FHosts[I];
        Break;
      end;
    if Known.HasFTP and not Known.HasSMB and (Host <> '') then
    begin
      Fs := FFtp;
      Target := 'ftp://' + Host + '/';
    end;
  end;
  if (Target = '\\') or (Target = '') then
  begin
    FBrowsing := False;
    FError := L('net.empty.addr');
    Changed;
    Exit;
  end;
  BindNetworkBrowse(Fs, Target,
    procedure(AItems: TNetworkItemList)
    begin
      if Token <> FBrowseSeq then
        Exit;
      FBrowsing := False;
      FItems := AItems;
      FError := '';
      if not Remember(FBrowsePath) then
        Changed;
    end,
    procedure(AErr: string)
    var
      Code: Cardinal;
    begin
      if Token <> FBrowseSeq then
        Exit;
      if AllowPrompt and NetLogonCodeOf(AErr, Code) and (FOwner <> 0) and
         PromptShareLogon(FOwner, Target, Code) then
      begin
        Browse(APath, False);
        Exit;
      end;
      FBrowsing := False;
      FError := NetLogonPlain(AErr);
      FScanError := False;
      SetLength(FItems, 0);
      Changed;
    end);
end;

function TNetworkSession.Remember(const APath: string): Boolean;
var
  S: string;
  I: Integer;
begin
  Result := False;
  S := HistoryStorePath(APath);
  if not HistAllowed(S) then
    Exit;
  Result := True;
  if (FHist.Count > 0) and SameText(FHist[0], S) then
  begin
    Changed;
    Exit;
  end;
  for I := FHist.Count - 1 downto 0 do
    if SameText(FHist[I], S) then
      FHist.Delete(I);
  FHist.Insert(0, S);
  while FHist.Count > 20 do
    FHist.Delete(FHist.Count - 1);
  if Assigned(FOnPrefs) then
    FOnPrefs(Self);
  Changed;
end;

procedure TNetworkSession.Forget(const APath: string);
var
  I: Integer;
  S: string;
  Hit: Boolean;
begin
  S := HistoryStorePath(APath);
  Hit := False;
  for I := FHist.Count - 1 downto 0 do
    if SameText(FHist[I], S) or SameText(FHist[I], Trim(APath)) then
    begin
      FHist.Delete(I);
      Hit := True;
    end;
  if not Hit then
    Exit;
  if Assigned(FOnPrefs) then
    FOnPrefs(Self);
  Changed;
end;

function TNetworkSession.IsRecentRow(const APath: string): Boolean;
var
  S, Host: string;
begin
  Result := False;
  S := HistoryStorePath(APath);
  if (S = '') or (FHist.IndexOf(S) < 0) then
  begin
    if FHist.IndexOf(Trim(APath)) < 0 then
      Exit;
    S := Trim(APath);
  end;
  if StartsText('network://', S) then
  begin
    Host := VibeNetworkHost(S);
    if HostSeen(Host) then
      Exit;
  end;
  Result := True;
end;

procedure TNetworkSession.NoteOpened(const APath: string);
var
  S, Body, Host, Share: string;
  P: Integer;
begin
  S := Trim(APath);
  if S = '' then
    Exit;
  if IsVibeNetworkPath(S) then
  begin
    S := NormalizeVibeNetwork(S);
    if SameText(S, 'network://') then
      Exit;
    if StartsText('network://', S) then
      Remember(S);
    Exit;
  end;
  if not IsUncPath(S) then
    Exit;
  S := ExcludeTrailingPathDelimiter(S);
  if Length(S) <= 2 then
    Exit;
  Body := Copy(S, 3, MaxInt);
  P := Pos('\', Body);
  if P <= 1 then
    Exit;
  Host := Copy(Body, 1, P - 1);
  Share := Copy(Body, P + 1, MaxInt);
  P := Pos('\', Share);
  if P > 0 then
    Share := Copy(Share, 1, P - 1);
  if (Host = '') or (Share = '') then
    Exit;
  Remember('\\' + Host + '\' + Share);
end;

procedure TNetworkSession.AddAddress(const AText: string);
var
  S, Nav, Host: string;
  P: Integer;
  H: TNetworkHost;
begin
  S := Trim(AText);
  if S = '' then
    Exit;
  if IsUncPath(S) and not IsVibeNetworkPath(S) then
    Nav := S
  else if StartsText('ftp://', S) or StartsText('ftps://', S) then
    Nav := S
  else if IsVibeNetworkPath(S) then
    Nav := NormalizeVibeNetwork(S)
  else
    Nav := 'network://' + S;
  Nav := HistoryStorePath(Nav);
  if not HistAllowed(Nav) then
    Exit;
  Host := '';
  if not UncShareHost(Nav, Host) then
  if IsUncPath(Nav) then
  begin
    Host := ExcludeTrailingPathDelimiter(Nav);
    if Length(Host) > 2 then
    begin
      Delete(Host, 1, 2);
      P := Pos('\', Host);
      if P > 0 then
        Host := Copy(Host, 1, P - 1);
    end
    else
      Host := '';
  end
  else
    Host := VibeNetworkHost(Nav);
  if (Host <> '') and HostLabelOk(Host) and
     (StartsText('network://', Nav) or IsUncPath(Nav)) then
  begin
    H := Default(TNetworkHost);
    H.Address := Host;
    H.HasSMB := True;
    PutHost(FExtra, H);
  end;
  Remember(Nav);
end;

procedure TNetworkSession.LoadPrefs(const ASubnet, AHistory: string);
var
  Parts: TArray<string>;
  I: Integer;
  S: string;
  Dirty: Boolean;
begin
  if Trim(ASubnet) <> '' then
    FSubnet := Trim(ASubnet);
  FHist.Clear;
  Dirty := False;
  if Trim(AHistory) <> '' then
  begin
    Parts := AHistory.Split(['|']);
    for I := 0 to High(Parts) do
    begin
      S := HistoryStorePath(Parts[I]);
      if not SameText(S, Trim(Parts[I])) then
        Dirty := True;
      if S = '' then
        Continue;
      if not HistAllowed(S) then
      begin
        Dirty := True;
        Continue;
      end;
      if FHist.IndexOf(S) >= 0 then
        Continue;
      if FHist.Count >= 20 then
        Break;
      FHist.Add(S);
    end;
  end;
  if Dirty and Assigned(FOnPrefs) then
    FOnPrefs(Self);
end;

function TNetworkSession.HistoryText: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FHist.Count - 1 do
  begin
    if I > 0 then
      Result := Result + '|';
    Result := Result + FHist[I];
  end;
end;

function TNetworkSession.TileLine: string;
var
  Plain: string;
begin
  if FScanning then
    Exit(L('drive.scanning'));
  Plain := HumanNetError(FError);
  if (FError <> '') and (SameText(Plain, L('drive.link')) or
     SameText(Plain, L('net.unreachable')) or SameText(Plain, L('net.sockets'))) then
    Exit(L('drive.link'));
  Result := L('drive.env');
end;

procedure TNetworkSession.ClearHistory;
begin
  if FHist.Count = 0 then
    Exit;
  FHist.Clear;
  if Assigned(FOnPrefs) then
    FOnPrefs(Self);
  Changed;
end;

function TNetworkSession.ResolvedSubnet: string;
begin
  if FSubnet <> '' then
    Result := FSubnet
  else
    Result := LocalSubnetPrefix;
end;

function TNetworkSession.StatusText(const AViewPath: string): string;
var
  ViewRoot: Boolean;
begin
  ViewRoot := IsVibeNetworkRoot(AViewPath) or (Trim(AViewPath) = '');
  if FScanning and ViewRoot then
    Exit(LCount(FHosts.Count, 'net.scan.one', 'net.scan.few', 'net.scan.many'));
  if (FError <> '') and (FScanError or not ViewRoot) then
    Exit(HumanNetError(FError));
  if FBrowsing and not ViewRoot then
    Exit(L('net.reading'));
  if ViewRoot then
    Exit(LCount(FHosts.Count, 'net.alive.one', 'net.alive.few', 'net.alive.many'));
  if Length(FItems) = 0 then
  begin
    if StartsText('network://', Trim(AViewPath)) then
      Exit(L('net.noshare'));
    Exit(L('net.empty'));
  end;
  Result := LCount(Length(FItems), 'net.items.one', 'net.items.few', 'net.items.many');
end;

procedure TNetworkSession.FillRoot(AList: TFileEntryList);
var
  I: Integer;
  E: TFileEntry;
  Host: string;
  Shown: Integer;
  NetOpen, Recent: Boolean;
  HistName, HistIp, HistKind, HistIcon: string;

  function ExtraHides(const AHost: TNetworkHost): Boolean;
  var
    N: Integer;
    Nm: string;
  begin
    Result := False;
    Nm := Trim(AHost.Name);
    if SameText(Nm, AHost.Address) then
      Nm := '';
    for N := 0 to FExtra.Count - 1 do
      if SameHostToken(FExtra[N].Address, AHost.Address) or
         SameHostToken(FExtra[N].Address, Nm) then
        Exit(True);
  end;

  function SeenName(const AAddr: string): string;
  var
    N: Integer;
  begin
    Result := '';
    if AAddr = '' then
      Exit;
    for N := 0 to FHosts.Count - 1 do
      if SameText(FHosts[N].Address, AAddr) and (Trim(FHosts[N].Name) <> '') then
        Exit(Trim(FHosts[N].Name));
    for N := 0 to FExtra.Count - 1 do
      if SameText(FExtra[N].Address, AAddr) and (Trim(FExtra[N].Name) <> '') then
        Exit(Trim(FExtra[N].Name));
  end;

  procedure DescribeHist(const APath: string; out AName, AIp, AKind, AIcon: string);
  var
    S, Body, Tail: string;
    P: Integer;
  begin
    AIcon := '#stock:94';
    AKind := L('net.node');
    AIp := '';
    AName := APath;
    if IsUncPath(APath) and not IsVibeNetworkPath(APath) then
    begin
      S := ExcludeTrailingPathDelimiter(APath);
      if Length(S) > 2 then
      begin
        Delete(S, 1, 2);
        P := Pos('\', S);
        if P > 1 then
        begin
          Body := Copy(S, 1, P - 1);
          Tail := Copy(S, P + 1, MaxInt);
          P := Pos('\', Tail);
          if P > 0 then
            Tail := Copy(Tail, 1, P - 1);
          AIp := Body;
          AName := Tail;
          if AName = '' then
            AName := Body;
          AKind := L('net.share');
          AIcon := '#stock:51';
          Exit;
        end;
      end;
    end;
    if StartsText('ftp://', APath) or StartsText('ftps://', APath) or
       StartsText('sftp://', APath) then
    begin
      if StartsText('sftp://', APath) then
        AKind := 'SFTP'
      else
      begin
        AKind := 'FTP';
        AIcon := '#stock:51';
      end;
      AIp := UrlHost(APath);
      AName := SeenName(AIp);
      if AName = '' then
        AName := AIp;
      if AName = '' then
        AName := APath;
      Exit;
    end;
    if StartsText('http://', APath) or StartsText('https://', APath) then
    begin
      AKind := 'Web';
      AIcon := '#stock:17';
      AIp := UrlHost(APath);
      AName := SeenName(AIp);
      if AName = '' then
        AName := AIp;
      if AName = '' then
        AName := APath;
      Exit;
    end;
    Body := HostOfPath(APath);
    AIp := Body;
    AName := SeenName(Body);
    if AName = '' then
      AName := Body;
    if AName = '' then
      AName := APath;
  end;

  function HistDup(const APath: string): Boolean;
  var
    H, Body: string;
    P: Integer;
  begin
    if IsUncPath(APath) and not IsVibeNetworkPath(APath) then
    begin
      Body := ExcludeTrailingPathDelimiter(APath);
      if Length(Body) > 2 then
      begin
        Delete(Body, 1, 2);
        P := Pos('\', Body);
        if (P > 1) and (Copy(Body, P + 1, MaxInt) <> '') then
          Exit(False);
      end;
    end;
    H := HostOfPath(APath);
    if H = '' then
      H := UrlHost(APath);
    Result := (H <> '') and HostSeen(H);
  end;

  procedure StampLast(const AKey: string);
  var
    Row: TFileEntry;
  begin
    if (AList.Count = 0) or (Trim(AKey) = '') then
      Exit;
    { TList<запис> віддає копію: пінг треба записати назад. }
    Row := AList[AList.Count - 1];
    ApplyPing(Row, AKey);
    AList[AList.Count - 1] := Row;
  end;

  procedure AddClassic(const ARow: TClassicRow);
  var
    Row: TFileEntry;
    HostName: string;
  begin
    Row := Default(TFileEntry);
    Row.Name := ARow.Name;
    Row.DisplayName := ARow.Name;
    Row.FullPath := ARow.FullPath;
    Row.IsDirectory := True;
    Row.FreeBytes := 1;
    if ARow.IsShare then
    begin
      Row.IconKey := '#shell:51';
      Row.NeedsCustomIcon := True;
      Row.DisplayType := HostOfPath(ARow.FullPath);
      Row.DisplaySize := L('net.share');
    end
    else
    begin
      Row.IconKey := '#stock:94';
      HostName := VibeNetworkHost(ARow.FullPath);
      if FourOctets(HostName) then
        Row.DisplayType := HostName;
    end;
    AList.Add(Row);
    if not ARow.IsShare then
      StampLast(VibeNetworkHost(ARow.FullPath));
  end;

begin
  if AList = nil then
    Exit;
  FHosts.Sort(TComparer<TNetworkHost>.Construct(
    function(const L, R: TNetworkHost): Integer
    begin
      Result := CompareText(IpSortKey(L.Address), IpSortKey(R.Address));
    end));
  FClassicRows.Sort(TComparer<TClassicRow>.Construct(
    function(const L, R: TClassicRow): Integer
    begin
      if L.IsShare <> R.IsShare then
      begin
        if L.IsShare then
          Result := 1
        else
          Result := -1;
      end
      else
        Result := CompareText(L.Name, R.Name);
    end));
  if FClassicRows.Count > 0 then
  begin
    AddHead(AList, 'Сеть');
    for I := 0 to FClassicRows.Count - 1 do
      AddClassic(FClassicRows[I]);
  end;
  NetOpen := FClassicRows.Count > 0;
  for I := 0 to FExtra.Count - 1 do
  begin
    Host := FExtra[I].Address;
    if (Host = '') or ClassicBlocks(FExtra[I]) then
      Continue;
    if not NetOpen then
    begin
      AddHead(AList, 'Сеть');
      NetOpen := True;
    end;
    E := Default(TFileEntry);
    E.Name := Host;
    E.DisplayName := Host;
    E.FullPath := 'network://' + Host;
    E.IsDirectory := True;
    E.FreeBytes := 1;
    E.IconKey := '#stock:94';
    if FourOctets(Host) then
      E.DisplayType := Host;
    AList.Add(E);
    StampLast(Host);
  end;
  Shown := 0;
  for I := 0 to FHosts.Count - 1 do
    if not ClassicBlocks(FHosts[I]) and not ExtraHides(FHosts[I]) then
      Inc(Shown);
  if FScanning or (Shown > 0) then
  begin
    AddHead(AList, 'Найденные');
    for I := 0 to FHosts.Count - 1 do
      if not ClassicBlocks(FHosts[I]) and not ExtraHides(FHosts[I]) then
      begin
        AddPc(AList, FHosts[I], False);
        StampLast(FHosts[I].Address);
      end;
  end;
  if FHist.Count = 0 then
    Exit;
  Recent := False;
  for I := 0 to FHist.Count - 1 do
  begin
    if HistDup(FHist[I]) then
      Continue;
    if not Recent then
    begin
      AddHead(AList, 'Недавние');
      if AList.Count > 0 then
      begin
        E := AList[AList.Count - 1];
        E.FullPath := 'nethead://recent';
        AList[AList.Count - 1] := E;
      end;
      Recent := True;
    end;
    Host := HostOfPath(FHist[I]);
    if Host = '' then
      Host := UrlHost(FHist[I]);
    DescribeHist(FHist[I], HistName, HistIp, HistKind, HistIcon);
    E := Default(TFileEntry);
    E.Name := HistName;
    E.DisplayName := HistName;
    E.FullPath := FHist[I];
    E.IsDirectory := True;
    E.FreeBytes := 1;
    E.IconKey := HistIcon;
    E.DisplayType := HistIp;
    E.DisplaySize := HistKind;
    E.IsHidden := FDidScan and (Host <> '') and not HostSeen(Host);
    AList.Add(E);
    if not SameText(HistKind, L('net.share')) then
    begin
      if HistIp <> '' then
        StampLast(HistIp)
      else
        StampLast(Host);
    end;
  end;
end;

procedure TNetworkSession.FillBrowse(AList: TFileEntryList);
var
  I, G: Integer;
  Item: TNetworkItem;
  Grouped: Boolean;
  Buckets: array[0..3] of TList<Integer>;
  Titles: array[0..3] of string;

  function RowCaption(const AItem: TNetworkItem): string;
  var
    S: string;
    Cut: Integer;
  begin
    S := ExcludeTrailingPathDelimiter(AItem.FullPath);
    Cut := LastDelimiter('/\', S);
    if (Cut > 0) and (Copy(S, Cut + 1, MaxInt) <> '') then
      Result := Copy(S, Cut + 1, MaxInt)
    else
      Result := AItem.Name;
    if Result = '' then
      Result := AItem.FullPath;
  end;

  function BlobHas(const AItem: TNetworkItem; const ANeedle: string): Boolean;
  begin
    Result := Pos(ANeedle, LowerCase(AItem.Name + ' ' + AItem.Comment)) > 0;
  end;

  procedure AddFlat(const AItem: TNetworkItem);
  var
    E: TFileEntry;
    Caption: string;
  begin
    E := Default(TFileEntry);
    Caption := RowCaption(AItem);
    E.Name := Caption;
    E.DisplayName := Caption;
    E.FullPath := AItem.FullPath;
    if E.FullPath = '' then
      E.FullPath := AItem.Name;
    E.IsDirectory := AItem.ItemType <> nitFile;
    E.Size := AItem.Size;
    E.Modified := AItem.ModifiedDate;
    if E.IsDirectory then
    begin
      E.FreeBytes := 1;
      if AItem.ItemType = nitServer then
        E.IconKey := '#stock:94'
      else if AItem.ItemType = nitShare then
        E.IconKey := '#stock:51'
      else
        E.IconKey := '#dir';
      if AItem.ItemType = nitShare then
        E.DisplayType := L('net.share')
      else if AItem.ItemType = nitServer then
        E.DisplayType := L('net.node')
      else
        E.DisplayType := L('model.folder');
    end
    else
    begin
      E.Extension := ExtractFileExt(Caption);
      E.DisplayType := UpperCase(Copy(E.Extension, 2, 12));
      if AItem.Size > 0 then
        E.DisplaySize := FormatFileSize(AItem.Size);
    end;
    if AItem.ModifiedDate > 0 then
      E.DisplayDate := FormatDateTime('dd.mm.yyyy HH:nn', AItem.ModifiedDate);
    AList.Add(E);
  end;

  procedure SortBucket(ABucket: TList<Integer>);
  var
    A, B, Tmp: Integer;
  begin
    for A := 0 to ABucket.Count - 2 do
      for B := A + 1 to ABucket.Count - 1 do
        if CompareText(RowCaption(FItems[ABucket[A]]),
             RowCaption(FItems[ABucket[B]])) > 0 then
        begin
          Tmp := ABucket[A];
          ABucket[A] := ABucket[B];
          ABucket[B] := Tmp;
        end;
  end;

  procedure AddGrouped(const AItem: TNetworkItem; AGroup: Integer);
  var
    Row: TFileEntry;
    Caption: string;
  begin
    Row := Default(TFileEntry);
    Caption := RowCaption(AItem);
    Row.Name := Caption;
    Row.DisplayName := Caption;
    Row.FullPath := AItem.FullPath;
    if Row.FullPath = '' then
      Row.FullPath := AItem.Name;
    case AGroup of
      0, 1:
        begin
          Row.IsDirectory := True;
          Row.FreeBytes := 1;
          Row.IconKey := '#stock:51';
          if AGroup = 0 then
            Row.DisplayType := L('net.admin')
          else
            Row.DisplayType := L('net.share');
        end;
      2:
        begin
          Row.IsDirectory := False;
          Row.IconKey := '#shell:16';
          Row.NeedsCustomIcon := True;
          Row.DisplayType := Trim(AItem.Comment);
        end;
    else
      Row.IsDirectory := False;
      Row.NeedsCustomIcon := True;
      if BlobHas(AItem, 'fax') or BlobHas(AItem, 'факс') then
        Row.IconKey := '#shell:52'
      else
        Row.IconKey := '#shell:17';
      Row.DisplayType := Trim(AItem.Comment);
    end;
    AList.Add(Row);
  end;

begin
  if AList = nil then
    Exit;
  Grouped := Length(FItems) > 0;
  for I := 0 to High(FItems) do
  begin
    Item := FItems[I];
    if (Item.Name = '.') or (Item.Name = '..') then
      Continue;
    if (Item.ItemType = nitFile) or (Item.ItemType = nitDirectory) or
       not (Item.FromShare or Item.FromWNet) then
    begin
      Grouped := False;
      Break;
    end;
  end;
  if not Grouped then
  begin
    for I := 0 to High(FItems) do
    begin
      if (FItems[I].Name = '.') or (FItems[I].Name = '..') then
        Continue;
      AddFlat(FItems[I]);
    end;
    Exit;
  end;
  for G := 0 to 3 do
    Buckets[G] := nil;
  for G := 0 to 3 do
    Buckets[G] := TList<Integer>.Create;
  try
    for I := 0 to High(FItems) do
    begin
      if (FItems[I].Name = '.') or (FItems[I].Name = '..') then
        Continue;
      Buckets[HostResourceGroup(FItems[I])].Add(I);
    end;
    Titles[0] := 'Админ';
    Titles[1] := 'Шари';
    Titles[2] := 'Принтеры';
    Titles[3] := 'Другое';
    for G := 0 to 3 do
    begin
      if Buckets[G].Count = 0 then
        Continue;
      SortBucket(Buckets[G]);
      AddHead(AList, Titles[G]);
      for I := 0 to Buckets[G].Count - 1 do
        AddGrouped(FItems[Buckets[G][I]], G);
    end;
  finally
    for G := 0 to 3 do
      Buckets[G].Free;
  end;
end;

end.
