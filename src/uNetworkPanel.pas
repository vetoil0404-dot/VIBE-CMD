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
    FHist: TStringList;
    FItems: TNetworkItemList;
    FSeq: Integer;
    FScanning: Boolean;
    FBrowsing: Boolean;
    FDidScan: Boolean;
    FScanError: Boolean;
    FError: string;
    FSubnet: string;
    FBrowsePath: string;
    FOnChange: TNotifyEvent;
    FOnPrefs: TNotifyEvent;
    procedure Changed;
    procedure PutHost(AList: TList<TNetworkHost>; const AHost: TNetworkHost);
    function HostSeen(const AAddr: string): Boolean;
    function Remember(const APath: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure CancelJobs;
    procedure Stop;
    procedure Scan(const ASubnet: string);
    procedure Browse(const APath: string);
    procedure AddAddress(const AText: string);
    procedure Forget(const APath: string);
    function IsRecentRow(const APath: string): Boolean;
    procedure NoteOpened(const APath: string);
    procedure LoadPrefs(const ASubnet, AHistory: string);
    procedure FillRoot(AList: TFileEntryList);
    procedure FillBrowse(AList: TFileEntryList);
    function StatusText(const AViewPath: string): string;
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
  if AHost.HasSMB then
  begin
    Result := 'SMB';
    if AHost.HasFTP then
      Result := Result + ' · FTP';
    Exit;
  end;
  if AHost.HasFTP then
    Exit('FTP');
  if AHost.IsRouter then
    Exit(L('net.flag.host'));
  if AHost.HasWebAdmin then
    Exit('Web');
  Result := L('net.flag.host');
end;

function HostIconKey(const AHost: TNetworkHost): string;
begin
  if AHost.IsRouter then
    Exit('#router');
  if AHost.HasFTP and not AHost.HasSMB then
    Exit('#ftp');
  Result := '#computer';
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
  else if SameText(ATitle, 'Недавние') then
    E.DisplayName := L('net.recent')
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
  E.DisplaySize := FlagText(AHost);
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
  FSmb := TSMBProvider.Create;
  FFtp := TFTPProvider.Create;
  FDav := TWebDAVProvider.Create;
  FHosts := TList<TNetworkHost>.Create;
  FExtra := TList<TNetworkHost>.Create;
  FHist := TStringList.Create;
  FHist.CaseSensitive := False;
end;

destructor TNetworkSession.Destroy;
begin
  FOnChange := nil;
  FOnPrefs := nil;
  CancelJobs;
  FDiscovery.Free;
  FSmb.Free;
  FFtp.Free;
  FDav.Free;
  FHosts.Free;
  FExtra.Free;
  FHist.Free;
  inherited;
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

function TNetworkSession.HostSeen(const AAddr: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if AAddr = '' then
    Exit;
  for I := 0 to FHosts.Count - 1 do
    if SameText(FHosts[I].Address, AAddr) then
      Exit(True);
  for I := 0 to FExtra.Count - 1 do
    if SameText(FExtra[I].Address, AAddr) then
      Exit(True);
end;

procedure TNetworkSession.CancelJobs;
begin
  Inc(FSeq);
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
var
  WasScan: Boolean;
begin
  if not FScanning and not FBrowsing then
    Exit;
  WasScan := FScanning;
  CancelJobs;
  FError := L('op.cancelled');
  FScanError := WasScan;
  Changed;
end;

procedure TNetworkSession.Scan(const ASubnet: string);
var
  Token: Integer;
  Use: string;
begin
  CancelJobs;
  Token := FSeq;
  Use := Trim(ASubnet);
  if Use = '' then
    Use := LocalSubnetPrefix;
  FSubnet := Use;
  FHosts.Clear;
  FError := '';
  FScanError := False;
  FScanning := True;
  FBrowsing := False;
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
      if AErr = '' then
      begin
        FDidScan := True;
        FError := '';
        FScanError := False;
        if Assigned(FOnPrefs) then
          FOnPrefs(Self);
      end
      else
      begin
        FError := AErr;
        FScanError := True;
        if not SameText(AErr, L('op.cancelled')) then
          FDidScan := True;
      end;
      Changed;
    end);
end;

procedure TNetworkSession.Browse(const APath: string);
var
  Token: Integer;
  Host, Target: string;
  Fs: TNetworkFileSystem;
  Known: TNetworkHost;
  I: Integer;
begin
  CancelJobs;
  Token := FSeq;
  if not SameText(FBrowsePath, APath) then
    SetLength(FItems, 0);
  FBrowsePath := APath;
  FError := '';
  FScanError := False;
  FBrowsing := True;
  FScanning := False;
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
      if Token <> FSeq then
        Exit;
      FBrowsing := False;
      FItems := AItems;
      FError := '';
      if not Remember(FBrowsePath) then
        Changed;
    end,
    procedure(AErr: string)
    begin
      if Token <> FSeq then
        Exit;
      FBrowsing := False;
      FError := AErr;
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
  if FScanning then
    Exit(LCount(FHosts.Count, 'net.scan.one', 'net.scan.few', 'net.scan.many'));
  if (FError <> '') and (FScanError or not ViewRoot) then
    Exit(FError);
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
  Dim: Boolean;
  HistName, HistIp, HistKind, HistIcon: string;

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
    AIcon := '#computer';
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
          AIcon := '#dir';
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
        AIcon := '#ftp';
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

begin
  if AList = nil then
    Exit;
  FHosts.Sort(TComparer<TNetworkHost>.Construct(
    function(const L, R: TNetworkHost): Integer
    begin
      Result := CompareText(IpSortKey(L.Address), IpSortKey(R.Address));
    end));
  AddHead(AList, 'Компьютеры');
  for I := 0 to FHosts.Count - 1 do
    AddPc(AList, FHosts[I], False);
  for I := 0 to FExtra.Count - 1 do
  begin
    Host := FExtra[I].Address;
    Dim := False;
    for var J := 0 to FHosts.Count - 1 do
      if SameText(FHosts[J].Address, Host) then
        Dim := True;
    if (Host <> '') and not Dim then
      AddPc(AList, FExtra[I], False);
  end;
  if FHist.Count = 0 then
    Exit;
  AddHead(AList, 'Недавние');
  for I := 0 to FHist.Count - 1 do
  begin
    Host := HostOfPath(FHist[I]);
    if StartsText('network://', FHist[I]) and (Host <> '') and HostSeen(Host) then
      Continue;
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
  end;
end;

procedure TNetworkSession.FillBrowse(AList: TFileEntryList);
var
  I, P: Integer;
  Item: TNetworkItem;
  E: TFileEntry;
  Caption, Tail: string;
begin
  if AList = nil then
    Exit;
  for I := 0 to High(FItems) do
  begin
    Item := FItems[I];
    if (Item.Name = '.') or (Item.Name = '..') then
      Continue;
    E := Default(TFileEntry);
    Caption := Item.Name;
    Tail := ExcludeTrailingPathDelimiter(Item.FullPath);
    P := LastDelimiter('/\', Tail);
    if (P > 0) and (Copy(Tail, P + 1, MaxInt) <> '') then
      Caption := Copy(Tail, P + 1, MaxInt);
    if Caption = '' then
      Caption := Item.FullPath;
    E.Name := Caption;
    E.DisplayName := Caption;
    E.FullPath := Item.FullPath;
    if E.FullPath = '' then
      E.FullPath := Item.Name;
    E.IsDirectory := Item.ItemType <> nitFile;
    E.Size := Item.Size;
    E.Modified := Item.ModifiedDate;
    if E.IsDirectory then
    begin
      E.FreeBytes := 1;
      if Item.ItemType = nitServer then
        E.IconKey := '#computer'
      else
        E.IconKey := '#dir';
      if Item.ItemType = nitShare then
        E.DisplayType := L('net.share')
      else if Item.ItemType = nitServer then
        E.DisplayType := L('net.node')
      else
        E.DisplayType := L('model.folder');
    end
    else
    begin
      E.Extension := ExtractFileExt(Caption);
      E.DisplayType := UpperCase(Copy(E.Extension, 2, 12));
      if Item.Size > 0 then
        E.DisplaySize := FormatFileSize(Item.Size);
    end;
    if Item.ModifiedDate > 0 then
      E.DisplayDate := FormatDateTime('dd.mm.yyyy HH:nn', Item.ModifiedDate);
    AList.Add(E);
  end;
end;

end.
