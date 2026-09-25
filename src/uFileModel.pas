unit uFileModel;

{
  Модель одной записи каталога + быстрая фоновая загрузка списка каталога.
}

interface

uses
  System.SysUtils, System.IOUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections,
  System.Generics.Defaults, System.DateUtils, System.Types, System.Math,
  System.Zip;

function IsVirtualShellPath(const APath: string): Boolean;
function IsPortableDevicePath(const APath: string): Boolean;
function IsDeviceNamespacePath(const APath: string): Boolean;
function IsThisPCPath(const APath: string): Boolean;
function TryBindShellItem(const APath: string; out AItem: IUnknown): Boolean;
function IsDriveRoot(const APath: string): Boolean;
function DriveMemoryKey(const APath: string): string;
function ComputerFolderPath: string;
function DisplayNameForPath(const APath: string): string;
function IsArchiveExt(const AExt: string): Boolean;
function IsArchiveFileName(const AName: string): Boolean;
function IsOfficeLockFile(const APath: string): Boolean;
function IsZipFamily(const AExt: string): Boolean;
function SplitArchivePath(const APath: string; out AArchive, AInner: string): Boolean;
function IsBrowsablePath(const APath: string): Boolean;
function IsUncPath(const APath: string): Boolean;
function IsRemotePath(const APath: string): Boolean;
function IsListablePath(const APath: string): Boolean;
function ParentOfBrowsablePath(const APath: string): string;
function NetworkFolderPath: string;
function MaterializeFile(const APath: string; out ALocalPath: string): Boolean;
function ShellTransfer(const ASource, ADestDir: string): Boolean;
procedure BeginArchiveAccess(const AZipPath: string);
procedure EndArchiveAccess(const AZipPath: string);
function IsArchiveBusy: Boolean;
function OpenSharedFileStream(const AFileName: string; AWrite: Boolean;
  ACreate: Boolean = False): TStream;
function OpenZipRead(const AZipPath: string): TZipFile;
function OpenZipWrite(const AZipPath: string): TZipFile;

type
  TDriveKind = (dkUnknown, dkSSD, dkHDD, dkRemovable, dkNetwork, dkOptical,
    dkDevice, dkNetHood);

  TDriveInfo = record
    Root: string;
    Letter: string;
    VolumeName: string;
    Kind: TDriveKind;
    TotalBytes: Int64;
    FreeBytes: Int64;
    Ready: Boolean;
  end;

  TFileEntry = record
    Name: string;
    FullPath: string;
    IsDirectory: Boolean;
    Size: Int64;
    FreeBytes: Int64;
    Modified: TDateTime;
    Extension: string;
    Attributes: Integer;
    IsHidden: Boolean;
    IsSystem: Boolean;
    NeedsCustomIcon: Boolean;
    IconKey: string;
    DisplayName: string;
    DisplayType: string;
    DisplaySize: string;
    DisplayDate: string;
    function IsDimmed: Boolean;
    class function FromPath(const APath: string): TFileEntry; static;
    class function FromSearchRec(const APath: string; const ASearchRec: TSearchRec): TFileEntry; static;
    class function FromDrive(const AInfo: TDriveInfo): TFileEntry; static;
  end;

  TFileEntryList = TList<TFileEntry>;

  TSortField = (sfName, sfExt, sfSize, sfDate);

  TDirLoadThread = class(TThread)
  private
    FPath: string;
    FOnDone: TProc<TFileEntryList>;
    FOnError: TProc<string>;
    FOnChunk: TProc<TFileEntryList, Boolean>;
    FOnProgress: TProc<Integer>;
    FErrorMsg: string;
    FShowHidden: Boolean;
    FBranch: Boolean;
    FErrSent: Boolean;
    FProbeGate: TEvent;
    procedure SendError(const AMsg: string);
    procedure EmitSlice(AList: TFileEntryList; AFrom: Integer; ADone: Boolean);
    procedure NoteProgress(ACount: Integer);
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
    constructor Create(const APath: string; AOnDone: TProc<TFileEntryList>;
      AOnError: TProc<string>; AShowHidden: Boolean = False;
      ABranch: Boolean = False; AOnChunk: TProc<TFileEntryList, Boolean> = nil;
      AOnProgress: TProc<Integer> = nil);
  end;

procedure SortEntries(List: TFileEntryList; Field: TSortField; Ascending: Boolean);
procedure PrepareFileEntry(var AEntry: TFileEntry);
function IsCompatibilityJunction(AAttr: Integer): Boolean;
function FormatFileSize(Size: Int64): string;
function DriveKindCaption(AKind: TDriveKind): string;
function DrivePlaceTitle(const AInfo: TDriveInfo): string;
function FormatDrivePair(ALeft, ARight: Int64): string;
function FormatDriveFreeUsed(AFree, ATotal: Int64): string;
function CollectAllPlaces(AIncludeNetwork: Boolean): TArray<TDriveInfo>;
function CollectDriveLetters: TArray<TDriveInfo>;
function TryListComputerPlaces(AList: TFileEntryList; AIncludeNetwork: Boolean = True): Boolean;

implementation

uses
  System.StrUtils, uArchiveEngine
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.ShlObj, Winapi.ActiveX{$ENDIF};

const
  CLSID_ThisPC = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}';
  ThisPCParsingName = 'shell:::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';
  WpdInterfaceGuid = '{6ac27878-a6fa-4155-ba85-f98f491d4f33}';
  FILEOP_NOUI = $0004 or $0010 or $0400 or $0200;
  PKEY_ItemSize: TPropertyKey = (fmtid: '{B725F130-47EF-101A-A5F1-02608C9EEBAC}'; pid: 12);
  PKEY_ItemDateModified: TPropertyKey = (fmtid: '{B725F130-47EF-101A-A5F1-02608C9EEBAC}'; pid: 14);

type
  IPortableDeviceManager = interface(IUnknown)
    ['{A1567595-4C2F-4574-A6FA-ECEF917B9A40}']
    function GetDevices(pPnPDeviceIDs: Pointer; var pcPnPDeviceIDs: DWORD): HRESULT; stdcall;
    function RefreshDeviceList: HRESULT; stdcall;
    function GetDeviceFriendlyName(pszPnPDeviceID: PWideChar;
      pDeviceFriendlyName: PWideChar; var pcchDeviceFriendlyName: DWORD): HRESULT; stdcall;
    function GetDeviceDescription(pszPnPDeviceID: PWideChar;
      pDeviceDescription: PWideChar; var pcchDeviceDescription: DWORD): HRESULT; stdcall;
    function GetDeviceManufacturer(pszPnPDeviceID: PWideChar;
      pDeviceManufacturer: PWideChar; var pcchDeviceManufacturer: DWORD): HRESULT; stdcall;
  end;

var
  GZipMapLock: TCriticalSection;
  GZipBusy: Integer;
  GPidlLock: TCriticalSection;
  GPidlMap: TDictionary<string, TBytes>;
  GDriveTypeLock: TCriticalSection;
  GDriveTypeCache: TDictionary<string, Cardinal>;

type
  TSharedFileStream = class(THandleStream)
  public
    destructor Destroy; override;
  end;

  TSharedZip = class(TZipFile)
  private
    FOwnStream: TStream;
  public
    destructor Destroy; override;
    procedure OpenShared(const AFileName: string; AWrite: Boolean);
  end;

destructor TSharedFileStream.Destroy;
var
  H: THandle;
begin
  H := Handle;
  inherited;
  if (H <> 0) and (H <> INVALID_HANDLE_VALUE) then
    FileClose(H);
end;

function OpenSharedFileStream(const AFileName: string; AWrite, ACreate: Boolean): TStream;
{$IFDEF MSWINDOWS}
var
  H: THandle;
  Access, Share, Disp, Err: DWORD;
  Attempt: Integer;
begin
  if AWrite then
    Access := GENERIC_READ or GENERIC_WRITE
  else
    Access := GENERIC_READ;
  Share := FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE;
  if ACreate then
    Disp := CREATE_ALWAYS
  else
    Disp := OPEN_EXISTING;
  for Attempt := 1 to 8 do
  begin
    H := CreateFile(PChar(AFileName), Access, Share, nil, Disp,
      FILE_ATTRIBUTE_NORMAL, 0);
    if H <> INVALID_HANDLE_VALUE then
      Break;
    Err := GetLastError;
    if ((Err = ERROR_SHARING_VIOLATION) or (Err = ERROR_LOCK_VIOLATION)) and
       (Attempt < 8) then
    begin
      Sleep(30 * Attempt);
      Continue;
    end;
    raise EFOpenError.CreateFmt('Cannot open file "%s". %s',
      [AFileName, SysErrorMessage(Err)]);
  end;
  Result := TSharedFileStream.Create(H);
end;
{$ELSE}
var
  Mode: Word;
  FS: TFileStream;
begin
  if ACreate then
  begin
    FS := TFileStream.Create(AFileName, fmCreate);
    FS.Free;
    Result := TFileStream.Create(AFileName, fmOpenReadWrite or fmShareDenyNone);
  end
  else
  begin
    if AWrite then
      Mode := fmOpenReadWrite or fmShareDenyNone
    else
      Mode := fmOpenRead or fmShareDenyNone;
    Result := TFileStream.Create(AFileName, Mode);
  end;
end;
{$ENDIF}

destructor TSharedZip.Destroy;
begin
  inherited;
  FreeAndNil(FOwnStream);
end;

procedure TSharedZip.OpenShared(const AFileName: string; AWrite: Boolean);
var
  ZMode: TZipMode;
begin
  if AWrite then
    ZMode := zmReadWrite
  else
    ZMode := zmRead;
  FOwnStream := OpenSharedFileStream(AFileName, AWrite, False);
  try
    Open(FOwnStream, ZMode);
  except
    FreeAndNil(FOwnStream);
    raise;
  end;
end;

procedure BeginArchiveAccess(const AZipPath: string);
begin
  GZipMapLock.Enter;
  Inc(GZipBusy);
end;

procedure EndArchiveAccess(const AZipPath: string);
begin
  if GZipBusy > 0 then
    Dec(GZipBusy);
  GZipMapLock.Leave;
end;

function IsArchiveBusy: Boolean;
begin
  Result := GZipBusy > 0;
end;

function OpenZipRead(const AZipPath: string): TZipFile;
var
  Z: TSharedZip;
begin
  Z := TSharedZip.Create;
  try
    Z.UTF8Support := True;
    Z.OpenShared(AZipPath, False);
  except
    Z.Free;
    raise;
  end;
  Result := Z;
end;

function OpenZipWrite(const AZipPath: string): TZipFile;
var
  Z: TSharedZip;
begin
  Z := TSharedZip.Create;
  try
    Z.UTF8Support := True;
    Z.OpenShared(AZipPath, True);
  except
    Z.Free;
    raise;
  end;
  Result := Z;
end;

function IsPortableDevicePath(const APath: string): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(APath));
  if L = '' then
    Exit(False);
  Result := (Pos(WpdInterfaceGuid, L) > 0) or (Pos('usb#vid_', L) > 0) or
    (Pos('\?\usb#', L) > 0) or (Pos('\?\swd#', L) > 0) or
    (Pos('\?\wpdbusenum#', L) > 0) or (Pos('umb#', L) > 0) or
    (Pos('portabledevice', L) > 0);
end;

function IsDeviceNamespacePath(const APath: string): Boolean;
var
  U, Rest: string;
  I: Integer;
begin
  if IsPortableDevicePath(APath) then
    Exit(True);
  U := UpperCase(Trim(APath));
  I := Pos(CLSID_ThisPC, U);
  if I <= 0 then
    Exit(False);
  Rest := Trim(Copy(Trim(APath), I + Length(CLSID_ThisPC), MaxInt));
  while (Rest <> '') and CharInSet(Rest[1], ['\', '/', ' ']) do
    Delete(Rest, 1, 1);
  Result := Rest <> '';
end;

function IsWin32FsPath(const APath: string): Boolean;
var
  P: string;
begin
  P := Trim(APath);
  if Length(P) < 3 then
    Exit(False);
  if IsPortableDevicePath(P) then
    Exit(False);
  if (P[2] = ':') and CharInSet(P[1], ['A'..'Z', 'a'..'z']) then
    Exit(True);
  Result := StartsText('\\', P) and not StartsText('\\?\usb#', P) and
    not StartsText('\\?\wpdbusenum#', P) and not StartsText('\\?\swd#', P);
end;

function IsVirtualShellPath(const APath: string): Boolean;
var
  L: string;
begin
  L := Trim(APath);
  if L = '' then
    Exit(False);
  Result := StartsText('::', L) or (Pos('::{', L) > 0) or
    StartsText('shell:', L) or SameText(L, '\\') or SameText(L, 'Network') or
    IsPortableDevicePath(L);
end;

function IsThisPCPath(const APath: string): Boolean;
var
  P, U: string;
  I: Integer;
begin
  { Только корень «Этот компьютер». Путь устройства внутри него
    содержит тот же CLSID, но после закрывающей скобки есть хвост. }
  P := ExcludeTrailingPathDelimiter(Trim(APath));
  if P = '' then
    Exit(False);
  U := UpperCase(P);
  I := Pos(CLSID_ThisPC, U);
  if I <= 0 then
    Exit(False);
  Result := Trim(Copy(P, I + Length(CLSID_ThisPC), MaxInt)) = '';
end;

function ExtractWpdId(const APath: string): string; forward;

function IsDriveRoot(const APath: string): Boolean;
var
  P: string;
begin
  P := ExcludeTrailingPathDelimiter(Trim(APath));
  Result := (Length(P) = 2) and (P[2] = ':') and
    CharInSet(P[1], ['A'..'Z', 'a'..'z']);
end;

function DriveMemoryKey(const APath: string): string;
var
  P, D, Id: string;
begin
  Result := '';
  P := Trim(APath);
  if (P = '') or IsThisPCPath(P) then
    Exit;
  if IsPortableDevicePath(P) then
  begin
    Id := ExtractWpdId(P);
    if Id <> '' then
      Exit(LowerCase(Id));
    Exit(LowerCase(ExcludeTrailingPathDelimiter(P)));
  end;
  if IsVirtualShellPath(P) then
    Exit;
  D := ExtractFileDrive(P);
  if D = '' then
    Exit;
  if StartsStr('\\', D) then
    Result := LowerCase(ExcludeTrailingPathDelimiter(D))
  else if (Length(D) >= 2) and (D[2] = ':') then
    Result := UpperCase(D[1]) + ':\'
  else
    Result := LowerCase(ExcludeTrailingPathDelimiter(D));
end;

function ComputerFolderPath: string;
begin
  { Каноническое parsing-имя Этот компьютер: shell::: + CLSID.
    SIGDN_DESKTOPABSOLUTEPARSING даёт ::CLSID, и SHCreateItemFromParsingName
    его иногда не открывает. }
  Result := ThisPCParsingName;
end;

function NormShellKey(const APath: string): string;
begin
  Result := LowerCase(Trim(APath));
  if StartsText('shell:', Result) then
    Delete(Result, 1, 6);
  while EndsText('\', Result) do
    SetLength(Result, Length(Result) - 1);
end;

function ExtractWpdId(const APath: string): string;
var
  L: string;
  A, B: Integer;
begin
  Result := '';
  L := LowerCase(APath);
  A := Pos('usb#vid_', L);
  if A = 0 then
    A := Pos('wpdbusenum#', L);
  if A = 0 then
    A := Pos('\?\usb#', L);
  if A = 0 then
    A := Pos(WpdInterfaceGuid, L);
  if A = 0 then
    Exit;
  B := Pos(WpdInterfaceGuid, L);
  if B >= A then
    Result := Copy(L, A, B + Length(WpdInterfaceGuid) - A)
  else
    Result := Copy(L, A, MaxInt);
end;

{$IFDEF MSWINDOWS}
function ShellItemName(const AItem: IShellItem; ASig: DWORD): string; forward;

procedure PidlCachePut(const AKey: string; APidl: PItemIDList);
var
  K: string;
  N: UINT;
  B: TBytes;
begin
  K := NormShellKey(AKey);
  if (K = '') or (APidl = nil) or (GPidlMap = nil) then
    Exit;
  N := ILGetSize(APidl);
  if N < 2 then
    Exit;
  SetLength(B, N);
  Move(APidl^, B[0], N);
  GPidlLock.Enter;
  try
    GPidlMap.AddOrSetValue(K, B);
  finally
    GPidlLock.Leave;
  end;
end;

function PidlCacheGet(const AKey: string; out AItem: IShellItem): Boolean;
var
  K: string;
  B: TBytes;
  Pidl: PItemIDList;
begin
  Result := False;
  AItem := nil;
  K := NormShellKey(AKey);
  if (K = '') or (GPidlMap = nil) then
    Exit;
  GPidlLock.Enter;
  try
    if not GPidlMap.TryGetValue(K, B) then
    begin
      K := ExtractWpdId(AKey);
      if (K = '') or not GPidlMap.TryGetValue(K, B) then
        Exit;
    end;
  finally
    GPidlLock.Leave;
  end;
  if Length(B) < 2 then
    Exit;
  Pidl := CoTaskMemAlloc(Length(B));
  if Pidl = nil then
    Exit;
  Move(B[0], Pidl^, Length(B));
  try
    Result := Succeeded(SHCreateItemFromIDList(Pidl, IID_IShellItem, AItem)) and
      Assigned(AItem);
  finally
    CoTaskMemFree(Pidl);
  end;
end;

procedure RememberShellItem(const AItem: IShellItem);
var
  Pidl: PItemIDList;
  Parse, Wpd: string;
begin
  if AItem = nil then
    Exit;
  Pidl := nil;
  if Failed(SHGetIDListFromObject(AItem, Pidl)) or (Pidl = nil) then
    Exit;
  try
    Parse := ShellItemName(AItem, SIGDN_DESKTOPABSOLUTEPARSING);
    PidlCachePut(Parse, Pidl);
    Wpd := ExtractWpdId(Parse);
    if Wpd <> '' then
      PidlCachePut(Wpd, Pidl);
    if Parse <> '' then
    begin
      PidlCachePut('::{' + CLSID_ThisPC + '}\' + Parse, Pidl);
      PidlCachePut(ThisPCParsingName + '\' + Parse, Pidl);
    end;
  finally
    CoTaskMemFree(Pidl);
  end;
end;

function ShellUiHwnd: HWND;
begin
  Result := GetForegroundWindow;
  if Result = 0 then
    Result := GetActiveWindow;
end;

function ShellItemName(const AItem: IShellItem; ASig: DWORD): string;
var
  W: LPWSTR;
begin
  Result := '';
  if (AItem <> nil) and Succeeded(AItem.GetDisplayName(ASig, W)) then
  begin
    Result := W;
    CoTaskMemFree(W);
  end;
end;

procedure AddParseCandidate(var AList: TArray<string>; const AValue: string);
var
  I: Integer;
  V: string;
begin
  V := Trim(AValue);
  if V = '' then
    Exit;
  for I := 0 to High(AList) do
    if SameText(AList[I], V) then
      Exit;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := V;
end;

function ShellParseCandidates(const APath: string): TArray<string>;
var
  P: string;
begin
  SetLength(Result, 0);
  P := Trim(APath);
  AddParseCandidate(Result, P);
  if P = '' then
    Exit;
  if StartsText('shell:', P) and (Length(P) > 6) then
    AddParseCandidate(Result, Copy(P, 7, MaxInt));
  if IsPortableDevicePath(P) then
  begin
    if not StartsText('shell:', P) and (Pos('::{', P) = 0) then
    begin
      AddParseCandidate(Result, ThisPCParsingName + '\' + P);
      AddParseCandidate(Result, '::{' + CLSID_ThisPC + '}\' + P);
    end;
    if StartsText('\\?\', P) then
    begin
      AddParseCandidate(Result, ThisPCParsingName + '\' + P);
      AddParseCandidate(Result, '::{' + CLSID_ThisPC + '}\' + P);
    end;
  end;
end;

function TryBindThisPC(out AItem: IShellItem; out AFolder: IShellFolder): Boolean;
var
  Pidl: PItemIDList;
begin
  Result := False;
  AItem := nil;
  AFolder := nil;
  Pidl := nil;
  if Failed(SHGetSpecialFolderLocation(0, CSIDL_DRIVES, Pidl)) or (Pidl = nil) then
    Exit;
  try
    Result := Succeeded(SHCreateItemFromIDList(Pidl, IID_IShellItem, AItem)) and
      Assigned(AItem) and
      Succeeded(AItem.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, AFolder));
  finally
    CoTaskMemFree(Pidl);
  end;
end;

function MatchShellChild(const AItem: IShellItem; const APath: string): Boolean;
var
  Parse, Disp, Want, Id, Have: string;
begin
  Result := False;
  if AItem = nil then
    Exit;
  Parse := ShellItemName(AItem, SIGDN_DESKTOPABSOLUTEPARSING);
  Disp := ShellItemName(AItem, SIGDN_NORMALDISPLAY);
  Want := Trim(APath);
  if (Parse <> '') and (SameText(Parse, Want) or SameText(NormShellKey(Parse), NormShellKey(Want))) then
    Exit(True);
  if (Disp <> '') and SameText(Disp, Want) then
    Exit(True);
  Id := ExtractWpdId(Want);
  Have := ExtractWpdId(Parse);
  if (Id <> '') and (Have <> '') and SameText(Id, Have) then
    Exit(True);
  if (Disp <> '') and (Pos(LowerCase(Disp), LowerCase(Want)) > 0) then
    Exit(True);
end;

function WalkThisPCForPath(const APath: string; out AItem: IShellItem): Boolean;
var
  Root: IShellItem;
  Folder: IShellFolder;
  Enum: IEnumIDList;
  Child, ParentPidl: PItemIDList;
  Fetched: ULONG;
  ChildItem: IShellItem;
  Flags: DWORD;
  OwnerWnd: HWND;
begin
  Result := False;
  AItem := nil;
  if not TryBindThisPC(Root, Folder) then
    Exit;
  ParentPidl := nil;
  SHGetIDListFromObject(Root, ParentPidl);
  OwnerWnd := ShellUiHwnd;
  Flags := SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN or
    SHCONTF_STORAGE or SHCONTF_NAVIGATION_ENUM;
  if Failed(Folder.EnumObjects(OwnerWnd, Flags, Enum)) or (Enum = nil) then
    if Failed(Folder.EnumObjects(OwnerWnd, SHCONTF_FOLDERS or SHCONTF_STORAGE or
      SHCONTF_INCLUDEHIDDEN, Enum)) then
    begin
      if Assigned(ParentPidl) then
        CoTaskMemFree(ParentPidl);
      Exit;
    end;
  Fetched := 0;
  while Enum.Next(1, Child, Fetched) = S_OK do
  try
    ChildItem := nil;
    if Failed(SHCreateItemWithParent(ParentPidl, Folder, Child, IID_IShellItem, ChildItem)) then
      Continue;
    RememberShellItem(ChildItem);
    if MatchShellChild(ChildItem, APath) then
    begin
      AItem := ChildItem;
      Result := True;
      Break;
    end;
  finally
    CoTaskMemFree(Child);
  end;
  if Assigned(ParentPidl) then
    CoTaskMemFree(ParentPidl);
end;

function TryCreateShellItem(const APath: string; out AItem: IShellItem): Boolean; forward;

function TryBindShellItem(const APath: string; out AItem: IUnknown): Boolean;
var
  SI: IShellItem;
begin
  AItem := nil;
  Result := TryCreateShellItem(APath, SI) and Assigned(SI);
  if Result then
    AItem := SI;
end;

function TryCreateShellItem(const APath: string; out AItem: IShellItem): Boolean;
var
  Cands: TArray<string>;
  C: string;
  Pidl: PItemIDList;
  Attr: DWORD;
  Desk: IShellFolder;
  Eaten: ULONG;
begin
  AItem := nil;
  Result := False;
  if Trim(APath) = '' then
    Exit;
  if PidlCacheGet(APath, AItem) then
    Exit(True);
  Cands := ShellParseCandidates(APath);
  for C in Cands do
  begin
    if PidlCacheGet(C, AItem) then
      Exit(True);
    if Succeeded(SHCreateItemFromParsingName(PChar(C), nil, IID_IShellItem, AItem)) and
       Assigned(AItem) then
    begin
      RememberShellItem(AItem);
      Exit(True);
    end;
    AItem := nil;
    Pidl := nil;
    Attr := 0;
    if Succeeded(SHParseDisplayName(PChar(C), nil, Pidl, 0, Attr)) and (Pidl <> nil) then
    try
      if Succeeded(SHCreateItemFromIDList(Pidl, IID_IShellItem, AItem)) and
         Assigned(AItem) then
      begin
        RememberShellItem(AItem);
        Exit(True);
      end;
      AItem := nil;
    finally
      CoTaskMemFree(Pidl);
    end;
    if Succeeded(SHGetDesktopFolder(Desk)) then
    begin
      Pidl := nil;
      Eaten := 0;
      Attr := 0;
      if Succeeded(Desk.ParseDisplayName(ShellUiHwnd, nil, PChar(C), Eaten, Pidl, Attr)) and
         (Pidl <> nil) then
      try
        if Succeeded(SHCreateItemFromIDList(Pidl, IID_IShellItem, AItem)) and
           Assigned(AItem) then
        begin
          RememberShellItem(AItem);
          Exit(True);
        end;
        AItem := nil;
      finally
        CoTaskMemFree(Pidl);
      end;
    end;
  end;
  if not IsThisPCPath(APath) and
     (IsPortableDevicePath(APath) or (Pos(CLSID_ThisPC, UpperCase(APath)) > 0)) then
    Result := WalkThisPCForPath(APath, AItem);
end;

function FileTimeToLocalDT(const FT: TFileTime): TDateTime;
var
  Local: TFileTime;
  ST: TSystemTime;
begin
  Result := 0;
  if (FT.dwLowDateTime = 0) and (FT.dwHighDateTime = 0) then
    Exit;
  if not FileTimeToLocalFileTime(FT, Local) then
    Exit;
  if not FileTimeToSystemTime(Local, ST) then
    Exit;
  try
    Result := SystemTimeToDateTime(ST);
  except
    Result := 0;
  end;
end;

procedure FillShellEntryProps(const AItem: IShellItem; var AEntry: TFileEntry);
var
  Item2: IShellItem2;
  Sz: ULONGLONG;
  FT: TFileTime;
begin
  if AItem = nil then
    Exit;
  if not Supports(AItem, IShellItem2, Item2) then
    Exit;
  Sz := 0;
  if Succeeded(Item2.GetUInt64(PKEY_ItemSize, Sz)) then
    AEntry.Size := Int64(Sz);
  FillChar(FT, SizeOf(FT), 0);
  if Succeeded(Item2.GetFileTime(PKEY_ItemDateModified, FT)) then
    AEntry.Modified := FileTimeToLocalDT(FT);
end;
{$ENDIF}

function DisplayNameForPath(const APath: string): string;
{$IFDEF MSWINDOWS}
var
  Item: IShellItem;
{$ENDIF}
begin
  if IsThisPCPath(APath) then
    Exit('Этот компьютер');
  if SameText(APath, '\\') or SameText(APath, 'Network') or
     (IsUncPath(APath) and (Length(ExcludeTrailingPathDelimiter(APath)) <= 2)) then
    Exit('Сеть');
  {$IFDEF MSWINDOWS}
  if IsVirtualShellPath(APath) and TryCreateShellItem(APath, Item) then
  begin
    Result := ShellItemName(Item, SIGDN_NORMALDISPLAY);
    if Result <> '' then
      Exit;
  end;
  {$ENDIF}
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if Result = '' then
  begin
    if IsDriveRoot(APath) then
      Result := IncludeTrailingPathDelimiter(APath)
    else if IsPortableDevicePath(APath) then
      Result := 'Устройство'
    else
      Result := APath;
  end;
end;

function IsArchiveExt(const AExt: string): Boolean;
begin
  Result := MatchText(AExt, ['.zip', '.zipx', '.cbz', '.jar', '.apk', '.ear',
    '.war', '.rar', '.7z', '.tar', '.gz', '.tgz', '.cab', '.lzh', '.iso',
    '.xz', '.bz2', '.tbz', '.txz', '.wim']);
end;

function IsArchiveFileName(const AName: string): Boolean;
var
  L: string;
begin
  L := LowerCase(AName);
  Result := IsArchiveExt(ExtractFileExt(L)) or EndsText('.tar.gz', L) or
    EndsText('.tar.bz2', L) or EndsText('.tar.xz', L);
end;

function IsOfficeLockFile(const APath: string): Boolean;
var
  Name: string;
begin
  { Excel/Word/PowerPoint: ~$имя.xlsx — скрытый lock владельца, не документ. }
  Name := ExtractFileName(APath);
  Result := (Length(Name) >= 2) and (Name[1] = '~') and (Name[2] = '$');
end;

function IsZipFamily(const AExt: string): Boolean;
begin
  Result := MatchText(AExt, ['.zip', '.zipx', '.cbz', '.jar', '.apk', '.ear', '.war']);
end;

function SplitArchivePath(const APath: string; out AArchive, AInner: string): Boolean;
var
  Rest, Part, Acc: string;
  Slash: Integer;
begin
  Result := False;
  AArchive := '';
  AInner := '';
  Rest := ExcludeTrailingPathDelimiter(APath);
  if Rest = '' then
    Exit;
  if TFile.Exists(Rest) and IsArchiveExt(ExtractFileExt(Rest)) then
  begin
    AArchive := Rest;
    Exit(True);
  end;

  Acc := '';
  if (Length(Rest) >= 2) and (Rest[2] = ':') then
  begin
    Acc := Copy(Rest, 1, 2);
    Delete(Rest, 1, 2);
    if (Rest <> '') and (Rest[1] = '\') then
    begin
      Acc := Acc + '\';
      Delete(Rest, 1, 1);
    end;
  end;

  while Rest <> '' do
  begin
    Slash := Pos('\', Rest);
    if Slash > 0 then
    begin
      Part := Copy(Rest, 1, Slash - 1);
      Delete(Rest, 1, Slash);
    end
    else
    begin
      Part := Rest;
      Rest := '';
    end;
    if Acc = '' then
      Acc := Part
    else if EndsText('\', Acc) then
      Acc := Acc + Part
    else
      Acc := Acc + '\' + Part;
    if TFile.Exists(Acc) and IsArchiveExt(ExtractFileExt(Acc)) then
    begin
      AArchive := Acc;
      AInner := Rest;
      Exit(True);
    end;
    if not TDirectory.Exists(Acc) then
      Break;
  end;
end;

function IsUncPath(const APath: string): Boolean;
begin
  Result := (Length(APath) >= 2) and (APath[1] = '\') and (APath[2] = '\');
end;

function DriveRootOf(const APath: string): string;
var
  S: string;
  P, Slash: Integer;
begin
  S := Trim(APath);
  Result := '';
  if S = '' then
    Exit;
  if IsUncPath(S) then
  begin
    S := ExcludeTrailingPathDelimiter(S);
    if Length(S) <= 2 then
      Exit(S);
    P := 3;
    while (P <= Length(S)) and (S[P] <> '\') do
      Inc(P);
    if P > Length(S) then
      Exit(S);
    Slash := P + 1;
    while (Slash <= Length(S)) and (S[Slash] <> '\') do
      Inc(Slash);
    Result := Copy(S, 1, Slash - 1);
    Exit;
  end;
  if (Length(S) >= 2) and (S[2] = ':') then
    Result := UpperCase(S[1]) + ':\';
end;

function IsRemotePath(const APath: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Root: string;
  DT: Cardinal;
{$ENDIF}
begin
  if IsUncPath(APath) then
    Exit(True);
{$IFDEF MSWINDOWS}
  Root := DriveRootOf(APath);
  if Root = '' then
    Exit(False);
  DT := 0;
  if Assigned(GDriveTypeLock) and Assigned(GDriveTypeCache) then
  begin
    GDriveTypeLock.Enter;
    try
      if GDriveTypeCache.TryGetValue(Root, DT) then
        Exit(DT = DRIVE_REMOTE);
    finally
      GDriveTypeLock.Leave;
    end;
  end;
  DT := GetDriveType(PChar(Root));
  if Assigned(GDriveTypeLock) and Assigned(GDriveTypeCache) then
  begin
    GDriveTypeLock.Enter;
    try
      GDriveTypeCache.AddOrSetValue(Root, DT);
    finally
      GDriveTypeLock.Leave;
    end;
  end;
  Result := DT = DRIVE_REMOTE;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function IsListablePath(const APath: string): Boolean;
var
  Arc, Inner: string;
begin
  Result := Trim(APath) <> '';
  if not Result then
    Exit;
  if IsUncPath(APath) or IsRemotePath(APath) or IsVirtualShellPath(APath) or
     IsPortableDevicePath(APath) or IsThisPCPath(APath) then
    Exit(True);
  Result := TDirectory.Exists(APath) or SplitArchivePath(APath, Arc, Inner);
end;

function IsBrowsablePath(const APath: string): Boolean;
begin
  Result := Trim(APath) <> '';
  if not Result then
    Exit;
  if IsUncPath(APath) or IsRemotePath(APath) or IsVirtualShellPath(APath) or
     IsPortableDevicePath(APath) or IsThisPCPath(APath) then
    Exit(True);
  if TDirectory.Exists(APath) then
    Exit(True);
  if TFile.Exists(APath) and IsArchiveFileName(APath) then
    Exit(True);
  Result := ArchiveCanEnter(APath);
end;

function NetworkFolderPath: string;
{$IFDEF MSWINDOWS}
var
  Pidl: PItemIDList;
  Item: IShellItem;
  Name: LPWSTR;
begin
  Result := '\\';
  Pidl := nil;
  if Failed(SHGetSpecialFolderLocation(0, CSIDL_NETWORK, Pidl)) then
    Exit;
  try
    if Succeeded(SHCreateItemFromIDList(Pidl, IID_IShellItem, Item)) and
       Succeeded(Item.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, Name)) then
    begin
      Result := Name;
      CoTaskMemFree(Name);
    end;
  finally
    CoTaskMemFree(Pidl);
  end;
end;
{$ELSE}
begin
  Result := '\\';
end;
{$ENDIF}

function ParentOfBrowsablePath(const APath: string): string;
{$IFDEF MSWINDOWS}
var
  Item, Parent: IShellItem;
  Comp: string;
begin
  Result := ExtractFileDir(ExcludeTrailingPathDelimiter(APath));
  if IsThisPCPath(APath) then
  begin
    Result := '';
    Exit;
  end;
  if IsDriveRoot(APath) then
  begin
    Result := ComputerFolderPath;
    Exit;
  end;
  if SameText(APath, NetworkFolderPath) or SameText(APath, '\\') or
     SameText(APath, 'Network') then
  begin
    Result := ComputerFolderPath;
    Exit;
  end;
  if not IsVirtualShellPath(APath) then
    Exit;
  if TryCreateShellItem(APath, Item) and Assigned(Item) and
     Succeeded(Item.GetParent(Parent)) and Assigned(Parent) then
  begin
    Result := ShellItemName(Parent, SIGDN_DESKTOPABSOLUTEPARSING);
    if Result = '' then
      Result := ShellItemName(Parent, SIGDN_FILESYSPATH);
    if IsThisPCPath(Result) or (Result = '') then
    begin
      Result := ComputerFolderPath;
      Exit;
    end;
    Comp := NetworkFolderPath;
    if SameText(Result, Comp) and IsPortableDevicePath(APath) then
    begin
      Result := ComputerFolderPath;
      Exit;
    end;
    if Result <> '' then
      Exit;
  end;
  if IsPortableDevicePath(APath) then
  begin
    Result := ComputerFolderPath;
    Exit;
  end;
  if (Length(APath) > 2) and (APath[1] = '\') and (APath[2] = '\') then
  begin
    Result := NetworkFolderPath;
    if Result = '' then
      Result := '\\';
  end;
end;
{$ELSE}
begin
  Result := ExtractFileDir(ExcludeTrailingPathDelimiter(APath));
end;
{$ENDIF}

function ShellName(Pidl: PItemIDList; ASig: Cardinal): string;
var
  W: LPWSTR;
begin
  Result := '';
  if (Pidl <> nil) and Succeeded(SHGetNameFromIDList(Pidl, Integer(ASig), W)) then
  begin
    Result := W;
    CoTaskMemFree(W);
  end;
end;

function TryEnumNetworkFallback(AList: TFileEntryList): Boolean;
{$IFDEF MSWINDOWS}
var
  hEnum: THandle;
  Buf: array[0..32767] of Byte;
  Count, Size, Status: DWORD;
  P: PNetResource;
  I: Integer;
  Entry: TFileEntry;
  Remote: string;
begin
  Result := False;
  if WNetOpenEnum(RESOURCE_CONTEXT, RESOURCETYPE_ANY, 0, nil, hEnum) <> NO_ERROR then
    if WNetOpenEnum(RESOURCE_GLOBALNET, RESOURCETYPE_DISK, 0, nil, hEnum) <> NO_ERROR then
      Exit;
  try
    repeat
      Count := $FFFFFFFF;
      Size := SizeOf(Buf);
      Status := WNetEnumResource(hEnum, Count, @Buf[0], Size);
      if (Status <> NO_ERROR) and (Status <> ERROR_MORE_DATA) then
        Break;
      Result := True;
      P := @Buf[0];
      for I := 0 to Integer(Count) - 1 do
      begin
        Entry := Default(TFileEntry);
        Entry.IsDirectory := True;
        if P.lpRemoteName <> nil then
          Remote := P.lpRemoteName
        else
          Remote := '';
        if Remote <> '' then
        begin
          Entry.FullPath := Remote;
          Entry.Name := ExtractFileName(ExcludeTrailingPathDelimiter(Remote));
          if Entry.Name = '' then
            Entry.Name := Remote;
        end
        else if P.lpComment <> nil then
        begin
          Entry.Name := P.lpComment;
          Entry.FullPath := Entry.Name;
        end;
        if Entry.Name <> '' then
        begin
          PrepareFileEntry(Entry);
          AList.Add(Entry);
        end;
        Inc(P);
      end;
    until Status <> ERROR_MORE_DATA;
  finally
    WNetCloseEnum(hEnum);
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function ShouldSkipListedEntry(AAttr: Integer; AShowHidden: Boolean): Boolean;
begin
  if IsCompatibilityJunction(AAttr) then
    Exit(True);
  if AShowHidden then
    Exit(False);
  Result := ((AAttr and faHidden) <> 0) or ((AAttr and faSysFile) <> 0);
end;

function TryListLogicalDrives(AList: TFileEntryList): Boolean; forward;

{$IFDEF MSWINDOWS}
const
  IOCTL_STORAGE_QUERY_PROPERTY = $002D1400;
  StorageDeviceSeekPenaltyProperty = 7;

type
  TStoragePropertyQuery = packed record
    PropertyId: DWORD;
    QueryType: DWORD;
  end;

  TSeekPenaltyDesc = packed record
    Version: DWORD;
    Size: DWORD;
    IncursSeekPenalty: Byte;
    Reserved: array[0..2] of Byte;
  end;

function DriveIncursSeekPenalty(const ARoot: string): Boolean;
var
  H: THandle;
  Q: TStoragePropertyQuery;
  D: TSeekPenaltyDesc;
  Ret: DWORD;
  Dev: string;
begin
  Result := True;
  if Length(ARoot) < 2 then
    Exit;
  Dev := '\\.\' + Copy(ARoot, 1, 2);
  H := CreateFile(PChar(Dev), 0, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    FillChar(Q, SizeOf(Q), 0);
    Q.PropertyId := StorageDeviceSeekPenaltyProperty;
    Q.QueryType := 0;
    FillChar(D, SizeOf(D), 0);
    if DeviceIoControl(H, IOCTL_STORAGE_QUERY_PROPERTY, @Q, SizeOf(Q),
      @D, SizeOf(D), Ret, nil) then
      Result := D.IncursSeekPenalty <> 0;
  finally
    CloseHandle(H);
  end;
end;

function QueryDrive(const ARoot: string; AType: UINT): TDriveInfo;
var
  LabelBuf: array[0..MAX_PATH] of Char;
  Dummy: DWORD;
  Total, FreeForCaller, TotalFree: Int64;
begin
  Result := Default(TDriveInfo);
  Result.Root := IncludeTrailingPathDelimiter(ARoot);
  Result.Letter := UpperCase(Copy(ARoot, 1, 2));
  Result.Kind := dkUnknown;
  Result.Ready := False;

  case AType of
    DRIVE_REMOVABLE: Result.Kind := dkRemovable;
    DRIVE_REMOTE:    Result.Kind := dkNetwork;
    DRIVE_CDROM:     Result.Kind := dkOptical;
    DRIVE_RAMDISK:   Result.Kind := dkSSD;
    DRIVE_FIXED:
      if DriveIncursSeekPenalty(Result.Root) then
        Result.Kind := dkHDD
      else
        Result.Kind := dkSSD;
  end;

  if AType = DRIVE_REMOTE then
  begin
    Result.Ready := True;
    Exit;
  end;

  FillChar(LabelBuf, SizeOf(LabelBuf), 0);
  if GetVolumeInformation(PChar(Result.Root), LabelBuf, Length(LabelBuf),
    nil, Dummy, Dummy, nil, 0) then
    Result.VolumeName := string(LabelBuf);

  if GetDiskFreeSpaceEx(PChar(Result.Root), FreeForCaller, Total, @TotalFree) then
  begin
    Result.Ready := True;
    Result.TotalBytes := Total;
    Result.FreeBytes := TotalFree;
  end;
end;

function CollectDrives: TArray<TDriveInfo>;
var
  Mask: DWORD;
  I: Integer;
  Root: string;
  DT: UINT;
  Info: TDriveInfo;
begin
  SetLength(Result, 0);
  Mask := GetLogicalDrives;
  for I := 0 to 25 do
  begin
    if (Mask and (1 shl I)) = 0 then
      Continue;
    Root := Char(Ord('A') + I) + ':\';
    DT := GetDriveType(PChar(Root));
    case DT of
      DRIVE_REMOVABLE, DRIVE_FIXED, DRIVE_REMOTE, DRIVE_CDROM, DRIVE_RAMDISK: ;
    else
      Continue;
    end;
    Info := QueryDrive(Root, DT);
    if not Info.Ready and
       ((DT = DRIVE_REMOVABLE) or (DT = DRIVE_CDROM) or (DT = DRIVE_REMOTE)) then
      Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Info;
  end;
end;

function CollectDriveLetters: TArray<TDriveInfo>;
var
  Mask: DWORD;
  I: Integer;
  Info: TDriveInfo;
begin
  SetLength(Result, 0);
  Mask := GetLogicalDrives;
  for I := 0 to 25 do
  begin
    if (Mask and (1 shl I)) = 0 then
      Continue;
    Info := Default(TDriveInfo);
    Info.Root := Char(Ord('A') + I) + ':\';
    Info.Letter := Char(Ord('A') + I) + ':';
    Info.Kind := dkUnknown;
    Info.Ready := True;
    Info.TotalBytes := 0;
    Info.FreeBytes := 0;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Info;
  end;
end;

procedure AddDevicePlace(var AList: TArray<TDriveInfo>; const ARoot, AName: string);
var
  I: Integer;
  Info: TDriveInfo;
begin
  if Trim(ARoot) = '' then
    Exit;
  for I := 0 to High(AList) do
    if SameText(AList[I].Root, ARoot) then
      Exit;
  Info := Default(TDriveInfo);
  Info.Kind := dkDevice;
  Info.Root := ARoot;
  Info.Letter := '';
  Info.VolumeName := AName;
  if Info.VolumeName = '' then
    Info.VolumeName := 'Устройство';
  Info.Ready := True;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := Info;
end;

function WpdFriendlyName(const AMgr: IPortableDeviceManager; const AId: string): string;
var
  N: DWORD;
  Buf: array of Char;
begin
  Result := '';
  if (AMgr = nil) or (AId = '') then
    Exit;
  N := 0;
  AMgr.GetDeviceFriendlyName(PWideChar(AId), nil, N);
  if N = 0 then
    Exit;
  SetLength(Buf, N + 1);
  if Succeeded(AMgr.GetDeviceFriendlyName(PWideChar(AId), @Buf[0], N)) then
    Result := Trim(string(Buf));
end;

procedure CollectWpdDevices(var AList: TArray<TDriveInfo>);
const
  CLSID_PortableDeviceManager: TGUID = '{0AF10CEC-2ECD-4B91-BD63-AA10C6B1E0C7}';
var
  Mgr: IPortableDeviceManager;
  Count: DWORD;
  Ids: array of PWideChar;
  I: Integer;
  Id, Name, Root: string;
  Item: IShellItem;
begin
  if Failed(CoCreateInstance(CLSID_PortableDeviceManager, nil, CLSCTX_INPROC_SERVER,
      IPortableDeviceManager, Mgr)) or (Mgr = nil) then
    Exit;
  Count := 0;
  Mgr.GetDevices(nil, Count);
  if Count = 0 then
    Exit;
  SetLength(Ids, Count);
  FillChar(Ids[0], Count * SizeOf(PWideChar), 0);
  if Failed(Mgr.GetDevices(@Ids[0], Count)) then
    Exit;
  for I := 0 to Integer(Count) - 1 do
  begin
    if Ids[I] = nil then
      Continue;
    try
      Id := Ids[I];
      Name := WpdFriendlyName(Mgr, Id);
      Root := '';
      if WalkThisPCForPath(Id, Item) and Assigned(Item) then
      begin
        RememberShellItem(Item);
        Root := ShellItemName(Item, SIGDN_DESKTOPABSOLUTEPARSING);
        if Name = '' then
          Name := ShellItemName(Item, SIGDN_NORMALDISPLAY);
      end;
      if Root = '' then
        Root := '::{' + CLSID_ThisPC + '}\' + Id;
      AddDevicePlace(AList, Root, Name);
    finally
      CoTaskMemFree(Ids[I]);
    end;
  end;
end;

function CollectPortableDevices: TArray<TDriveInfo>;
var
  Desk, Comp: IShellFolder;
  PidlComp, Child: PItemIDList;
  Enum: IEnumIDList;
  Fetched: ULONG;
  Item: IShellItem;
  Parse, Display, Fs, LowParse: string;
  Flags: DWORD;
begin
  SetLength(Result, 0);
  PidlComp := nil;
  if Failed(SHGetDesktopFolder(Desk)) then
    Exit;
  if Failed(SHGetSpecialFolderLocation(0, CSIDL_DRIVES, PidlComp)) then
    Exit;
  try
    if Failed(Desk.BindToObject(PidlComp, nil, IID_IShellFolder, Comp)) then
      Exit;
    Flags := SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN or
      SHCONTF_STORAGE;
    if Failed(Comp.EnumObjects(0, Flags, Enum)) then
      if Failed(Comp.EnumObjects(0, SHCONTF_FOLDERS or SHCONTF_INCLUDEHIDDEN, Enum)) then
        Exit;
    Fetched := 0;
    while Enum.Next(1, Child, Fetched) = S_OK do
    try
      Item := nil;
      if Failed(SHCreateItemWithParent(PidlComp, Comp, Child, IID_IShellItem, Item)) then
        Continue;
      RememberShellItem(Item);
      Parse := ShellItemName(Item, SIGDN_DESKTOPABSOLUTEPARSING);
      Display := ShellItemName(Item, SIGDN_NORMALDISPLAY);
      Fs := ShellItemName(Item, SIGDN_FILESYSPATH);
      if Parse = '' then
        Parse := Fs;
      if Parse = '' then
        Continue;
      if IsDriveRoot(Parse) or IsDriveRoot(Fs) then
        Continue;
      LowParse := LowerCase(Parse);
      if (Pos('f02c1a0d', LowParse) > 0) or SameText(Display, 'Сеть') or
         SameText(Display, 'Network') then
        Continue;
      if IsWin32FsPath(Fs) and TDirectory.Exists(Fs) and not IsDriveRoot(Fs) and
         not IsPortableDevicePath(Parse) then
        Continue;
      AddDevicePlace(Result, Parse, Display);
    finally
      CoTaskMemFree(Child);
    end;
  finally
    CoTaskMemFree(PidlComp);
  end;
  CollectWpdDevices(Result);
end;

function MakeNetworkPlace: TDriveInfo;
begin
  Result := Default(TDriveInfo);
  Result.Kind := dkNetHood;
  Result.Root := NetworkFolderPath;
  Result.Letter := '';
  Result.VolumeName := 'Сеть';
  Result.Ready := True;
end;

function CollectAllPlaces(AIncludeNetwork: Boolean): TArray<TDriveInfo>;
var
  Drives, Devs: TArray<TDriveInfo>;
  I, N: Integer;
begin
  Drives := CollectDrives;
  Devs := CollectPortableDevices;
  N := Length(Drives) + Length(Devs);
  if AIncludeNetwork then
    Inc(N);
  SetLength(Result, N);
  for I := 0 to High(Drives) do
    Result[I] := Drives[I];
  for I := 0 to High(Devs) do
    Result[Length(Drives) + I] := Devs[I];
  if AIncludeNetwork then
    Result[N - 1] := MakeNetworkPlace;
end;
{$ELSE}
function CollectDriveLetters: TArray<TDriveInfo>;
begin
  SetLength(Result, 0);
end;

function CollectAllPlaces(AIncludeNetwork: Boolean): TArray<TDriveInfo>;
var
  Net: TDriveInfo;
begin
  SetLength(Result, 0);
  if not AIncludeNetwork then
    Exit;
  Net := Default(TDriveInfo);
  Net.Kind := dkNetHood;
  Net.Root := '\\';
  Net.VolumeName := 'Сеть';
  Net.Ready := True;
  SetLength(Result, 1);
  Result[0] := Net;
end;
{$ENDIF}

function TryListComputerPlaces(AList: TFileEntryList; AIncludeNetwork: Boolean): Boolean;
var
  Places: TArray<TDriveInfo>;
  I: Integer;
begin
  Result := False;
  if not Assigned(AList) then
    Exit;
  Places := CollectAllPlaces(AIncludeNetwork);
  if Length(Places) = 0 then
    Exit(TryListLogicalDrives(AList));
  for I := 0 to High(Places) do
    AList.Add(TFileEntry.FromDrive(Places[I]));
  Result := AList.Count > 0;
end;

function TryListLogicalDrives(AList: TFileEntryList): Boolean;
{$IFDEF MSWINDOWS}
var
  Mask: DWORD;
  I: Integer;
  Root: string;
  DT: UINT;
  Entry: TFileEntry;
  LabelBuf: array[0..MAX_PATH] of Char;
  Dummy: DWORD;
begin
  Result := False;
  if not Assigned(AList) then
    Exit;
  Mask := GetLogicalDrives;
  for I := 0 to 25 do
  begin
    if (Mask and (1 shl I)) = 0 then
      Continue;
    Root := Char(Ord('A') + I) + ':\';
    DT := GetDriveType(PChar(Root));
    case DT of
      DRIVE_REMOVABLE, DRIVE_FIXED, DRIVE_REMOTE, DRIVE_CDROM, DRIVE_RAMDISK: ;
    else
      Continue;
    end;
    Entry := Default(TFileEntry);
    Entry.FullPath := Root;
    Entry.IsDirectory := True;
    FillChar(LabelBuf, SizeOf(LabelBuf), 0);
    if GetVolumeInformation(PChar(Root), LabelBuf, Length(LabelBuf),
      nil, Dummy, Dummy, nil, 0) and (LabelBuf[0] <> #0) then
      Entry.Name := string(LabelBuf) + ' (' + Char(Ord('A') + I) + ':)'
    else
      Entry.Name := Root;
    PrepareFileEntry(Entry);
    AList.Add(Entry);
    Result := True;
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function TryBindShellFolder(const AItem: IShellItem; out AFolder: IShellFolder): Boolean;
begin
  AFolder := nil;
  Result := Assigned(AItem) and
    Succeeded(AItem.BindToHandler(nil, BHID_SFObject, IID_IShellFolder, AFolder)) and
    Assigned(AFolder);
end;

function TryEnumShell(const AFolder: IShellFolder; AFlags: DWORD;
  out AEnum: IEnumIDList): Boolean;
var
  OwnerWnd: HWND;
begin
  AEnum := nil;
  Result := False;
  if AFolder = nil then
    Exit;
  OwnerWnd := ShellUiHwnd;
  Result := Succeeded(AFolder.EnumObjects(OwnerWnd, AFlags, AEnum)) and Assigned(AEnum);
  if not Result then
    Result := Succeeded(AFolder.EnumObjects(0, AFlags, AEnum)) and Assigned(AEnum);
end;

function AddEntryFromShellItem(const AItem: IShellItem; const AFallbackPath: string;
  AList: TFileEntryList; AShowHidden: Boolean): Boolean;
var
  Entry: TFileEntry;
  Disp, Fs, AbsParse: string;
  Attr: DWORD;
  IsFolder: Boolean;
begin
  Result := False;
  if (AItem = nil) or (AList = nil) then
    Exit;
  RememberShellItem(AItem);
  Disp := ShellItemName(AItem, SIGDN_NORMALDISPLAY);
  AbsParse := ShellItemName(AItem, SIGDN_DESKTOPABSOLUTEPARSING);
  Fs := ShellItemName(AItem, SIGDN_FILESYSPATH);
  if Disp = '' then
    Exit;
  Entry := Default(TFileEntry);
  Entry.Name := Disp;
  if IsWin32FsPath(Fs) and (TDirectory.Exists(Fs) or TFile.Exists(Fs)) then
    Entry.FullPath := Fs
  else if AbsParse <> '' then
    Entry.FullPath := AbsParse
  else if Fs <> '' then
    Entry.FullPath := Fs
  else
    Entry.FullPath := AFallbackPath;
  Attr := SFGAO_FOLDER or SFGAO_STREAM or SFGAO_HIDDEN or SFGAO_FILESYSTEM;
  if Failed(AItem.GetAttributes(Attr, Attr)) then
    Attr := SFGAO_FOLDER;
  if not AShowHidden and ((Attr and SFGAO_HIDDEN) <> 0) and
     not IsPortableDevicePath(Entry.FullPath) and not IsDriveRoot(Fs) then
    Exit;
  IsFolder := (Attr and SFGAO_FOLDER) <> 0;
  if IsFolder and ((Attr and SFGAO_STREAM) <> 0) and IsWin32FsPath(Fs) and
     TFile.Exists(Fs) and not TDirectory.Exists(Fs) then
    IsFolder := False;
  Entry.IsDirectory := IsFolder;
  Entry.IsHidden := (Attr and SFGAO_HIDDEN) <> 0;
  if not Entry.IsDirectory then
    Entry.Extension := TPath.GetExtension(Entry.Name);
  FillShellEntryProps(AItem, Entry);
  PrepareFileEntry(Entry);
  AList.Add(Entry);
  Result := True;
end;

function TryListEnumItems(const AItem: IShellItem; AList: TFileEntryList;
  AShowHidden: Boolean): Boolean;
var
  Enum: IEnumShellItems;
  Child: IShellItem;
  Fetched: Longint;
  N: Integer;
begin
  Result := False;
  if (AItem = nil) or (AList = nil) then
    Exit;
  if Failed(AItem.BindToHandler(nil, BHID_EnumItems, IEnumShellItems, Enum)) and
     Failed(AItem.BindToHandler(nil, BHID_StorageEnum, IEnumShellItems, Enum)) then
    Exit;
  Result := True;
  N := 0;
  Fetched := 0;
  while Enum.Next(1, Child, @Fetched) = S_OK do
  begin
    if AddEntryFromShellItem(Child, '', AList, AShowHidden) then
      Inc(N);
    Child := nil;
  end;
  if N = 0 then
    Result := False;
end;

function TryListShellFolder(const APath: string; AList: TFileEntryList;
  AShowHidden: Boolean = False): Boolean;
{$IFDEF MSWINDOWS}
const
  EnumFlags = SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or
    SHCONTF_INCLUDEHIDDEN or SHCONTF_STORAGE;
var
  Parse: string;
  Item, ChildItem: IShellItem;
  Folder: IShellFolder;
  Enum: IEnumIDList;
  Child, ParentPidl: PItemIDList;
  Fetched: ULONG;
  Dummy: DWORD;
  IsNet: Boolean;
begin
  Result := False;
  if not Assigned(AList) or (APath = '') then
    Exit;
  Parse := APath;
  IsNet := SameText(Parse, '\\') or SameText(Parse, 'Network') or
    SameText(Parse, NetworkFolderPath);
  if IsNet then
    Parse := NetworkFolderPath
  else if IsThisPCPath(Parse) then
    Parse := ThisPCParsingName;

  if not TryCreateShellItem(Parse, Item) then
  begin
    if IsNet then
      Result := TryEnumNetworkFallback(AList)
    else if IsThisPCPath(APath) then
      Result := TryListLogicalDrives(AList);
    Exit;
  end;

  RememberShellItem(Item);
  if TryListEnumItems(Item, AList, AShowHidden or IsPortableDevicePath(Parse)) then
    Exit(True);

  ParentPidl := nil;
  if Failed(SHGetIDListFromObject(Item, ParentPidl)) then
  begin
    Dummy := 0;
    SHParseDisplayName(PChar(Parse), nil, ParentPidl, 0, Dummy);
  end;

  if not TryBindShellFolder(Item, Folder) then
  begin
    if Assigned(ParentPidl) then
      CoTaskMemFree(ParentPidl);
    if IsNet then
      Result := TryEnumNetworkFallback(AList)
    else if IsThisPCPath(APath) then
      Result := TryListLogicalDrives(AList);
    Exit;
  end;

  if not TryEnumShell(Folder, EnumFlags, Enum) then
    if not TryEnumShell(Folder, SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or
      SHCONTF_STORAGE or SHCONTF_NAVIGATION_ENUM, Enum) then
      if not TryEnumShell(Folder, SHCONTF_FOLDERS or SHCONTF_INCLUDEHIDDEN or
        SHCONTF_STORAGE, Enum) then
      begin
        if Assigned(ParentPidl) then
          CoTaskMemFree(ParentPidl);
        if IsNet then
          Result := TryEnumNetworkFallback(AList)
        else if IsThisPCPath(APath) then
          Result := TryListLogicalDrives(AList);
        Exit;
      end;

  Result := True;
  Fetched := 0;
  while Enum.Next(1, Child, Fetched) = S_OK do
  try
    ChildItem := nil;
    { pidlParent может быть nil — тогда достаточно IShellFolder. }
    if Failed(SHCreateItemWithParent(ParentPidl, Folder, Child, IID_IShellItem, ChildItem)) or
       (ChildItem = nil) then
      Continue;
    AddEntryFromShellItem(ChildItem, IncludeTrailingPathDelimiter(Parse) +
      ShellItemName(ChildItem, SIGDN_NORMALDISPLAY), AList,
      AShowHidden or IsPortableDevicePath(Parse));
  finally
    CoTaskMemFree(Child);
  end;

  if Assigned(ParentPidl) then
    CoTaskMemFree(ParentPidl);

  if IsNet and (AList.Count = 0) then
    Result := TryEnumNetworkFallback(AList) or Result
  else if IsThisPCPath(APath) and (AList.Count = 0) then
    Result := TryListLogicalDrives(AList) or Result;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function ListZipFolder(const AZip, AInner: string; AList: TFileEntryList): Boolean;
var
  Zip: TZipFile;
  I, Slash: Integer;
  Name, Rel, Prefix, First: string;
  Dirs: TStringList;
  Entry: TFileEntry;
begin
  Result := False;
  if not Assigned(AList) or not TFile.Exists(AZip) then
    Exit;
  Zip := nil;
  Dirs := nil;
  BeginArchiveAccess(AZip);
  try
    Zip := OpenZipRead(AZip);
    Dirs := TStringList.Create;
    Dirs.Sorted := True;
    Dirs.Duplicates := dupIgnore;
    Result := True;
    Prefix := StringReplace(AInner, '\', '/', [rfReplaceAll]);
    if (Prefix <> '') and not EndsText('/', Prefix) then
      Prefix := Prefix + '/';

    for I := 0 to Zip.FileCount - 1 do
    begin
      Name := StringReplace(Zip.FileName[I], '\', '/', [rfReplaceAll]);
      if Prefix <> '' then
      begin
        if not StartsText(Prefix, Name) then
          Continue;
        Rel := Copy(Name, Length(Prefix) + 1, MaxInt);
      end
      else
        Rel := Name;
      if Rel = '' then
        Continue;
      if EndsText('/', Rel) then
      begin
        Rel := ExcludeTrailingPathDelimiter(StringReplace(Rel, '/', '\', [rfReplaceAll]));
        Slash := Pos('\', Rel);
        if Slash > 0 then
          Rel := Copy(Rel, 1, Slash - 1);
        if Rel <> '' then
          Dirs.Add(Rel);
        Continue;
      end;
      Slash := Pos('/', Rel);
      if Slash > 0 then
      begin
        First := Copy(Rel, 1, Slash - 1);
        if First <> '' then
          Dirs.Add(First);
        Continue;
      end;
      Entry := Default(TFileEntry);
      Entry.Name := Rel;
      if AInner <> '' then
        Entry.FullPath := AZip + '\' + AInner + '\' + Rel
      else
        Entry.FullPath := AZip + '\' + Rel;
      Entry.IsDirectory := False;
      Entry.Extension := TPath.GetExtension(Rel);
      Entry.Size := Zip.FileInfo[I].UncompressedSize64;
      PrepareFileEntry(Entry);
      AList.Add(Entry);
    end;

    for I := 0 to Dirs.Count - 1 do
    begin
      Entry := Default(TFileEntry);
      Entry.Name := Dirs[I];
      if AInner <> '' then
        Entry.FullPath := AZip + '\' + AInner + '\' + Dirs[I]
      else
        Entry.FullPath := AZip + '\' + Dirs[I];
      Entry.IsDirectory := True;
      PrepareFileEntry(Entry);
      AList.Add(Entry);
    end;
  finally
    Dirs.Free;
    Zip.Free;
    EndArchiveAccess(AZip);
  end;
end;

function TryListArchive(const APath: string; AList: TFileEntryList): Boolean;
var
  Arc, Inner: string;
  Kids: TArray<TArcChild>;
  I: Integer;
  Entry: TFileEntry;
begin
  Result := False;
  if not Assigned(AList) or not SplitArchivePath(APath, Arc, Inner) then
    Exit;
  try
    if not ListArchiveChildren(APath, Kids) then
    begin
      if Inner = '' then
        Result := TryListShellFolder(Arc, AList)
      else
        Result := TryListShellFolder(APath, AList);
      Exit;
    end;
  except
    on E: Exception do
    begin
      if (Inner = '') and TryListShellFolder(Arc, AList) then
        Exit(True);
      raise;
    end;
  end;
  Result := True;
  for I := 0 to High(Kids) do
  begin
    Entry := Default(TFileEntry);
    Entry.Name := Kids[I].Name;
    if Inner <> '' then
      Entry.FullPath := ExcludeTrailingPathDelimiter(APath) + '\' + Kids[I].Name
    else
      Entry.FullPath := Arc + '\' + Kids[I].Name;
    Entry.IsDirectory := Kids[I].IsDir;
    Entry.Size := Kids[I].Size;
    Entry.Modified := Kids[I].Modified;
    Entry.Extension := TPath.GetExtension(Kids[I].Name);
    PrepareFileEntry(Entry);
    AList.Add(Entry);
  end;
end;

function UniqueTempPath(const AName: string): string;
var
  Dir, Base, Ext: string;
  N: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'TCClone');
  ForceDirectories(Dir);
  Base := TPath.GetFileNameWithoutExtension(AName);
  if Base = '' then
    Base := 'file';
  Ext := TPath.GetExtension(AName);
  Result := TPath.Combine(Dir, Base + Ext);
  N := 1;
  while TFile.Exists(Result) do
  begin
    Result := TPath.Combine(Dir, Format('%s_%d%s', [Base, N, Ext]));
    Inc(N);
  end;
end;

function ExtractZipFile(const AZip, AInner: string; out ALocal: string): Boolean;
var
  Zip: TZipFile;
  Inner, Name, Have: string;
  I: Integer;
  Stm: TStream;
  Hdr: TZipHeader;
  FS: TFileStream;
begin
  Result := False;
  ALocal := '';
  if not TFile.Exists(AZip) or (AInner = '') then
    Exit;
  Inner := StringReplace(AInner, '\', '/', [rfReplaceAll]);
  while StartsText('/', Inner) do
    Delete(Inner, 1, 1);
  if EndsText('/', Inner) then
    Exit;
  Name := Inner;
  I := LastDelimiter('/', Name);
  if I > 0 then
    Name := Copy(Name, I + 1, MaxInt);
  if Name = '' then
    Exit;
  Zip := nil;
  BeginArchiveAccess(AZip);
  try
    Zip := OpenZipRead(AZip);
    for I := 0 to Zip.FileCount - 1 do
    begin
      Have := StringReplace(Zip.FileName[I], '\', '/', [rfReplaceAll]);
      while StartsText('/', Have) do
        Delete(Have, 1, 1);
      if EndsText('/', Have) then
        Continue;
      if not SameText(Have, Inner) then
        Continue;
      ALocal := UniqueTempPath(Name);
      Zip.Read(I, Stm, Hdr);
      try
        FS := TFileStream.Create(ALocal, fmCreate);
        try
          if Stm.Size > 0 then
            FS.CopyFrom(Stm, 0);
        finally
          FS.Free;
        end;
      finally
        Stm.Free;
      end;
      Result := TFile.Exists(ALocal);
      Exit;
    end;
  finally
    Zip.Free;
    EndArchiveAccess(AZip);
  end;
end;

function ExtractShellStream(const AItem: IShellItem; const ALocal: string): Boolean;
var
  Stm: IStream;
  FS: TFileStream;
  Buf: array[0..65535] of Byte;
  ReadN: FixedUInt;
begin
  Result := False;
  if (AItem = nil) or Failed(AItem.BindToHandler(nil, BHID_Stream, IStream, Stm)) then
    Exit;
  FS := TFileStream.Create(ALocal, fmCreate);
  try
    repeat
      ReadN := 0;
      if Failed(Stm.Read(@Buf[0], SizeOf(Buf), @ReadN)) then
        Break;
      if ReadN > 0 then
        FS.WriteBuffer(Buf[0], ReadN);
    until ReadN = 0;
    Result := True;
  finally
    FS.Free;
  end;
end;

function ShellCopyToFolder(const AItem: IShellItem; const ADestDir: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Op: IFileOperation;
  Dest: IShellItem;
  Hr: HRESULT;
  NeedUninit: Boolean;
begin
  Result := False;
  if (AItem = nil) or (ADestDir = '') then
    Exit;
  Hr := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  NeedUninit := Hr = S_OK;
  try
    ForceDirectories(ADestDir);
    if Failed(CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_ALL,
        IFileOperation, Op)) or (Op = nil) then
      Exit;
    Op.SetOperationFlags(FILEOP_NOUI);
    if not TryCreateShellItem(ADestDir, Dest) then
      if Failed(SHCreateItemFromParsingName(PChar(ADestDir), nil, IID_IShellItem, Dest)) then
        Exit;
    if Failed(Op.CopyItem(AItem, Dest, nil, nil)) then
      Exit;
    Result := Succeeded(Op.PerformOperations);
  finally
    if NeedUninit then
      CoUninitialize;
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function ExtractShellItemToTemp(const AParse: string; out ALocal: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Item: IShellItem;
  Name, TmpDir, Copied: string;
begin
  Result := False;
  ALocal := '';
  if not TryCreateShellItem(AParse, Item) then
    Exit;
  Name := ShellItemName(Item, SIGDN_NORMALDISPLAY);
  if (Name = '') or (Pos('::', Name) > 0) or (Pos('#', Name) > 0) then
    Name := ExtractFileName(StringReplace(AParse, '/', '\', [rfReplaceAll]));
  if (Name = '') or (Pos('::', Name) > 0) or (Pos('#', Name) > 0) then
    Name := 'item.bin';
  ALocal := UniqueTempPath(Name);
  if ExtractShellStream(Item, ALocal) and TFile.Exists(ALocal) then
    Exit(True);
  if TFile.Exists(ALocal) then
    TFile.Delete(ALocal);
  TmpDir := TPath.Combine(TPath.GetTempPath, 'TCClone');
  ForceDirectories(TmpDir);
  if ShellCopyToFolder(Item, TmpDir) then
  begin
    Copied := TPath.Combine(TmpDir, Name);
    if TFile.Exists(Copied) then
    begin
      ALocal := Copied;
      Exit(True);
    end;
    if TDirectory.Exists(Copied) then
    begin
      ALocal := Copied;
      Exit(True);
    end;
  end;
  ALocal := '';
end;
{$ELSE}
begin
  Result := False;
  ALocal := '';
end;
{$ENDIF}

function ShellTransfer(const ASource, ADestDir: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Item: IShellItem;
  Local: string;
begin
  Result := False;
  if (ASource = '') or (ADestDir = '') then
    Exit;
  if IsWin32FsPath(ASource) and IsWin32FsPath(ADestDir) and
     (TFile.Exists(ASource) or TDirectory.Exists(ASource)) and
     TDirectory.Exists(ADestDir) then
    Exit(False);
  if TryCreateShellItem(ASource, Item) and ShellCopyToFolder(Item, ADestDir) then
    Exit(True);
  if MaterializeFile(ASource, Local) and TFile.Exists(Local) and
     TDirectory.Exists(ADestDir) then
  begin
    TFile.Copy(Local, TPath.Combine(ADestDir, ExtractFileName(Local)), True);
    Exit(True);
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

function MaterializeFile(const APath: string; out ALocalPath: string): Boolean;
var
  Arc, Inner: string;
begin
  ALocalPath := APath;
  Result := TFile.Exists(APath);
  if Result then
    Exit;
  if SplitArchivePath(APath, Arc, Inner) and (Inner <> '') then
  begin
    Result := MaterializeArchiveFile(APath, ALocalPath);
    if not Result then
      Result := ExtractShellItemToTemp(APath, ALocalPath);
    Exit;
  end;
  if IsVirtualShellPath(APath) or IsPortableDevicePath(APath) then
    Result := ExtractShellItemToTemp(APath, ALocalPath);
end;

function ExtNeedsCustomIcon(const AExt: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(AExt);
  Result := (Ext = '.exe') or (Ext = '.lnk') or (Ext = '.ico') or
    (Ext = '.url') or (Ext = '.scr') or (Ext = '.cpl') or
    (Ext = '.dll') or (Ext = '.msi') or (Ext = '.ocx') or
    (Ext = '.icl') or (Ext = '.pif') or (Ext = '.com') or
    (Ext = '.msc') or (Ext = '.sys');
end;

procedure ApplyEntryAttributes(var AEntry: TFileEntry; AAttr: Integer);
begin
  AEntry.Attributes := AAttr;
  AEntry.IsHidden := (AAttr and faHidden) <> 0;
  AEntry.IsSystem := (AAttr and faSysFile) <> 0;
end;

procedure PrepareFileEntry(var AEntry: TFileEntry);
var
  Ext: string;
begin
  Ext := LowerCase(AEntry.Extension);
  if AEntry.IsDirectory then
  begin
    AEntry.IconKey := '#dir';
    { На шаре не тянуть SHGetFileInfo по полному UNC — только тип #dir. }
    AEntry.NeedsCustomIcon := not IsRemotePath(AEntry.FullPath);
    AEntry.DisplayName := AEntry.Name;
    if AEntry.Extension <> '' then
      AEntry.DisplayType := AEntry.Extension
    else
      AEntry.DisplayType := 'Папка';
    if AEntry.FreeBytes > 0 then
      AEntry.DisplaySize := FormatDriveFreeUsed(AEntry.FreeBytes, AEntry.Size)
    else
      AEntry.DisplaySize := '';
  end
  else
  begin
    if Ext = '' then
      AEntry.IconKey := '#file'
    else
      AEntry.IconKey := Ext;
    AEntry.NeedsCustomIcon := ExtNeedsCustomIcon(Ext);
    AEntry.DisplayName := ChangeFileExt(AEntry.Name, '');
    AEntry.DisplayType := UpperCase(Copy(AEntry.Extension, 2, 10));
    AEntry.DisplaySize := FormatFileSize(AEntry.Size);
  end;
  if AEntry.Modified > 0 then
    AEntry.DisplayDate := FormatDateTime('dd.mm.yyyy HH:nn', AEntry.Modified)
  else
    AEntry.DisplayDate := '';
end;

function TFileEntry.IsDimmed: Boolean;
begin
  Result := IsHidden or IsSystem;
end;

class function TFileEntry.FromPath(const APath: string): TFileEntry;
var
  IsDir: Boolean;
  Attr: Integer;
begin
  Result := Default(TFileEntry);
  Result.FullPath := APath;
  Result.Name := TPath.GetFileName(APath);

  try
    IsDir := TDirectory.Exists(APath);
  except
    IsDir := False;
  end;

  Result.IsDirectory := IsDir;
  Result.FreeBytes := 0;

{$IFDEF MSWINDOWS}
  Attr := Integer(GetFileAttributes(PChar(APath)));
  if DWORD(Attr) <> INVALID_FILE_ATTRIBUTES then
    ApplyEntryAttributes(Result, Attr);
{$ENDIF}

  if IsDir then
  begin
    Result.Size := 0;
    Result.Extension := '';
    try
      Result.Modified := TDirectory.GetLastWriteTime(APath);
    except
      Result.Modified := 0;
    end;
  end
  else
  begin
    try
      Result.Size := TFile.GetSize(APath);
    except
      Result.Size := 0;
    end;

    try
      Result.Extension := TPath.GetExtension(APath);
    except
      Result.Extension := '';
    end;

    try
      Result.Modified := TFile.GetLastWriteTime(APath);
    except
      Result.Modified := 0;
    end;
  end;
  PrepareFileEntry(Result);
end;

function IsCompatibilityJunction(AAttr: Integer): Boolean;
begin
  { Documents and Settings и пр.: Hidden + System + Reparse/Junction. }
  Result := ((AAttr and faHidden) <> 0) and
    ((AAttr and faSysFile) <> 0) and
    ((AAttr and faSymLink) <> 0);
end;

class function TFileEntry.FromSearchRec(const APath: string; const ASearchRec: TSearchRec): TFileEntry;
var
  IsDir: Boolean;
begin
  Result := Default(TFileEntry);
  Result.FullPath := APath;
  Result.Name := ASearchRec.Name;
  IsDir := (ASearchRec.Attr and faDirectory) <> 0;
  Result.IsDirectory := IsDir;
  Result.FreeBytes := 0;
  ApplyEntryAttributes(Result, ASearchRec.Attr);

  if IsDir then
  begin
    Result.Size := 0;
    Result.Extension := '';
  end
  else
  begin
    Result.Size := ASearchRec.Size;
    try
      Result.Extension := TPath.GetExtension(ASearchRec.Name);
    except
      Result.Extension := '';
    end;
  end;

  try
    Result.Modified := FileDateToDateTime(ASearchRec.Time);
  except
    Result.Modified := 0;
  end;
  PrepareFileEntry(Result);
end;

function FormatFileSize(Size: Int64): string;
const
  KB = 1024;
  MB = KB * 1024;
  GB = MB * Int64(1024);
  TB = GB * Int64(1024);
begin
  if Size >= TB then
    Result := FormatFloat('0.00', Size / TB) + ' Tb'
  else if Size >= GB then
    Result := FormatFloat('0.00', Size / GB) + ' Gb'
  else if Size >= MB then
    Result := FormatFloat('0.00', Size / MB) + ' Mb'
  else if Size >= KB then
    Result := FormatFloat('0.00', Size / KB) + ' Kb'
  else
    Result := IntToStr(Size) + ' b';
end;

function DriveKindCaption(AKind: TDriveKind): string;
begin
  case AKind of
    dkSSD:       Result := 'SSD';
    dkHDD:       Result := 'HDD';
    dkRemovable: Result := 'USB';
    dkNetwork:   Result := 'Сеть';
    dkOptical:   Result := 'DVD';
    dkDevice:    Result := 'Устройство';
    dkNetHood:   Result := 'Сеть';
  else
    Result := 'Диск';
  end;
end;

function DrivePlaceTitle(const AInfo: TDriveInfo): string;
var
  Name: string;
begin
  Name := Trim(AInfo.VolumeName);
  if Name = '' then
    Name := DriveKindCaption(AInfo.Kind);
  if AInfo.Letter <> '' then
    Result := AInfo.Letter + '  ' + Name
  else
    Result := Name;
end;

function FormatDrivePair(ALeft, ARight: Int64): string;
var
  LeftS, RightS, LeftVal, LeftUnit, RightVal, RightUnit: string;
  P: Integer;
begin
  LeftS := FormatFileSize(ALeft);
  RightS := FormatFileSize(ARight);
  P := LastDelimiter(' ', LeftS);
  if P > 1 then
  begin
    LeftVal := Copy(LeftS, 1, P - 1);
    LeftUnit := Copy(LeftS, P + 1, MaxInt);
  end
  else
  begin
    LeftVal := LeftS;
    LeftUnit := '';
  end;
  P := LastDelimiter(' ', RightS);
  if P > 1 then
  begin
    RightVal := Copy(RightS, 1, P - 1);
    RightUnit := Copy(RightS, P + 1, MaxInt);
  end
  else
  begin
    RightVal := RightS;
    RightUnit := '';
  end;
  if (LeftUnit <> '') and SameText(LeftUnit, RightUnit) then
    Result := LeftVal + ' / ' + RightVal + ' ' + RightUnit
  else
    Result := LeftS + ' / ' + RightS;
end;

function FormatDriveFreeUsed(AFree, ATotal: Int64): string;
var
  Used: Int64;
begin
  if ATotal <= 0 then
  begin
    Result := '';
    Exit;
  end;
  Used := ATotal - AFree;
  if Used < 0 then
    Used := 0;
  Result := FormatDrivePair(AFree, Used);
end;

class function TFileEntry.FromDrive(const AInfo: TDriveInfo): TFileEntry;
begin
  Result := Default(TFileEntry);
  Result.FullPath := AInfo.Root;
  Result.Name := DrivePlaceTitle(AInfo);
  Result.IsDirectory := True;
  Result.Size := AInfo.TotalBytes;
  Result.FreeBytes := AInfo.FreeBytes;
  Result.Extension := DriveKindCaption(AInfo.Kind);
  Result.Modified := 0;
  PrepareFileEntry(Result);
end;

procedure SortEntries(List: TFileEntryList; Field: TSortField; Ascending: Boolean);
var
  Comparer: IComparer<TFileEntry>;
  Mult: Integer;
begin
  if Ascending then Mult := 1 else Mult := -1;

  Comparer := TComparer<TFileEntry>.Construct(
    function(const A, B: TFileEntry): Integer
    begin
      if A.IsDirectory <> B.IsDirectory then
      begin
        if A.IsDirectory then Exit(-1) else Exit(1);
      end;

      case Field of
        sfName: Result := CompareText(A.Name, B.Name);
        sfExt:  Result := CompareText(A.Extension, B.Extension);
        sfSize: Result := CompareValue(A.Size, B.Size);
        sfDate: Result := CompareDateTime(A.Modified, B.Modified);
      else
        Result := 0;
      end;
      Result := Result * Mult;
    end);

  List.Sort(Comparer);
end;

{ TDirLoadThread }

procedure CollectBranchFiles(const ARoot: string; AList: TFileEntryList;
  AShowHidden: Boolean; AAbort: TFunc<Boolean>);
var
  Stack: TStringList;
  Dir, Full, Rel, RootSlash: string;
  SR: TSearchRec;
  Entry: TFileEntry;
begin
  if (ARoot = '') or (AList = nil) then
    Exit;
  RootSlash := IncludeTrailingPathDelimiter(ARoot);
  Stack := TStringList.Create;
  try
    Stack.Add(ARoot);
    while Stack.Count > 0 do
    begin
      if Assigned(AAbort) and AAbort then
        Exit;
      Dir := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if System.SysUtils.FindFirst(TPath.Combine(Dir, '*.*'), faAnyFile, SR) <> 0 then
        Continue;
      try
        repeat
          if Assigned(AAbort) and AAbort then
            Exit;
          if (SR.Name = '.') or (SR.Name = '..') then
            Continue;
          if ShouldSkipListedEntry(SR.Attr, AShowHidden) then
            Continue;
          Full := TPath.Combine(Dir, SR.Name);
          if (SR.Attr and faDirectory) <> 0 then
            Stack.Add(Full)
          else
          begin
            Entry := TFileEntry.FromSearchRec(Full, SR);
            if StartsText(RootSlash, Full) then
              Rel := Copy(Full, Length(RootSlash) + 1, MaxInt)
            else
              Rel := SR.Name;
            Entry.Name := Rel;
            PrepareFileEntry(Entry);
            AList.Add(Entry);
          end;
        until System.SysUtils.FindNext(SR) <> 0;
      finally
        System.SysUtils.FindClose(SR);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

procedure ListZipBranch(const AZip, AInner: string; AList: TFileEntryList);
var
  Items: TArray<TArcItem>;
  I: Integer;
  Rel, Prefix, Path: string;
  Entry: TFileEntry;
begin
  if AList = nil then
    Exit;
  if AInner <> '' then
    Path := AZip + '\' + AInner
  else
    Path := AZip;
  Prefix := ArcNorm(AInner);
  Items := ListArchiveBranch(Path);
  for I := 0 to High(Items) do
  begin
    if Items[I].IsDir then
      Continue;
    Rel := Items[I].Path;
    if Prefix <> '' then
    begin
      if SameText(Rel, Prefix) then
        Rel := ArcLeaf(Rel)
      else if StartsText(Prefix + '/', Rel) then
        Rel := Copy(Rel, Length(Prefix) + 2, MaxInt)
      else
        Continue;
    end;
    if Rel = '' then
      Continue;
    Entry := Default(TFileEntry);
    Entry.Name := StringReplace(Rel, '/', '\', [rfReplaceAll]);
    if AInner <> '' then
      Entry.FullPath := AZip + '\' + StringReplace(AInner, '/', '\', [rfReplaceAll]) +
        '\' + Entry.Name
    else
      Entry.FullPath := AZip + '\' + Entry.Name;
    Entry.IsDirectory := False;
    Entry.Extension := TPath.GetExtension(Rel);
    Entry.Size := Items[I].Size;
    Entry.Modified := Items[I].Modified;
    PrepareFileEntry(Entry);
    AList.Add(Entry);
  end;
end;

constructor TDirLoadThread.Create(const APath: string;
  AOnDone: TProc<TFileEntryList>; AOnError: TProc<string>;
  AShowHidden: Boolean; ABranch: Boolean;
  AOnChunk: TProc<TFileEntryList, Boolean>; AOnProgress: TProc<Integer>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPath := APath;
  FOnDone := AOnDone;
  FOnError := AOnError;
  FOnChunk := AOnChunk;
  FOnProgress := AOnProgress;
  FShowHidden := AShowHidden;
  FBranch := ABranch;
  FErrSent := False;
  FProbeGate := nil;
end;

destructor TDirLoadThread.Destroy;
begin
  if Assigned(FProbeGate) then
  begin
    FProbeGate.SetEvent;
    FreeAndNil(FProbeGate);
  end;
  inherited;
end;

procedure TDirLoadThread.SendError(const AMsg: string);
begin
  if FErrSent then
    Exit;
  FErrSent := True;
  FErrorMsg := AMsg;
  Queue(
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(FErrorMsg);
    end);
end;

procedure TDirLoadThread.NoteProgress(ACount: Integer);
var
  N: Integer;
begin
  if not Assigned(FOnProgress) then
    Exit;
  N := ACount;
  Queue(
    procedure
    begin
      if Assigned(FOnProgress) then
        FOnProgress(N);
    end);
end;

procedure TDirLoadThread.EmitSlice(AList: TFileEntryList; AFrom: Integer; ADone: Boolean);
var
  Slice: TFileEntryList;
  I: Integer;
  DoneFlag: Boolean;
begin
  if not Assigned(FOnChunk) then
    Exit;
  Slice := TFileEntryList.Create;
  if Assigned(AList) then
    for I := Max(0, AFrom) to AList.Count - 1 do
      Slice.Add(AList[I]);
  DoneFlag := ADone;
  Queue(
    procedure
    begin
      try
        if Assigned(FOnChunk) then
          FOnChunk(Slice, DoneFlag)
        else
          Slice.Free;
      except
        Slice.Free;
      end;
    end);
end;

function NetIsOfflineCode(ACode: DWORD): Boolean;
begin
  Result := (ACode = ERROR_BAD_NETPATH) or (ACode = ERROR_BAD_NET_NAME) or
    (ACode = ERROR_NETWORK_UNREACHABLE) or (ACode = ERROR_NO_NET_OR_BAD_PATH) or
    (ACode = ERROR_NOT_READY) or (ACode = ERROR_NO_NETWORK) or
    (ACode = ERROR_UNEXP_NET_ERR) or (ACode = ERROR_NETNAME_DELETED) or
    (ACode = ERROR_DEV_NOT_EXIST) or (ACode = 53) or (ACode = 64) or
    (ACode = 67) or (ACode = 1203) or (ACode = 1231) or (ACode = 1222);
end;

function NetErrorText(ACode: DWORD): string;
begin
  if (ACode = ERROR_ACCESS_DENIED) or (ACode = ERROR_NETWORK_ACCESS_DENIED) or
     (ACode = ERROR_LOGON_FAILURE) then
    Result := 'Нет доступа'
  else if NetIsOfflineCode(ACode) then
    Result := 'Сервер не отвечает'
  else if ACode <> 0 then
    Result := 'Не удалось открыть папку'
  else
    Result := 'Сервер не отвечает';
end;

procedure TDirLoadThread.Execute;
var
  SearchRec: System.SysUtils.TSearchRec;
  Entries: TFileEntryList;
  FullPath: string;
  ListToPass: TFileEntryList;
  Arc, Inner: string;
  NeedCom: Boolean;
  Remote: Boolean;
  RC, LastChunk, ErrCode: Integer;
  LastEmit: Cardinal;
begin
  Remote := IsRemotePath(FPath);
{$IFDEF MSWINDOWS}
  NeedCom := (not Remote) and Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
{$ELSE}
  NeedCom := False;
{$ENDIF}
  Entries := TFileEntryList.Create;
  LastChunk := 0;
  try
    try
      if FBranch then
      begin
        if SplitArchivePath(FPath, Arc, Inner) then
          ListZipBranch(Arc, Inner, Entries)
        else if (not IsVirtualShellPath(FPath)) and
                (Remote or TDirectory.Exists(FPath)) then
          CollectBranchFiles(FPath, Entries, FShowHidden,
            function: Boolean
            begin
              Result := Terminated;
            end)
        else
          raise Exception.Create('Ветвь каталога недоступна: ' + FPath);
      end
      else if IsThisPCPath(FPath) then
      begin
        if not TryListComputerPlaces(Entries, True) then
          raise Exception.Create('Не удалось открыть: Этот компьютер');
      end
      else if SplitArchivePath(FPath, Arc, Inner) then
      begin
        if not TryListArchive(FPath, Entries) then
          raise Exception.Create('Не удалось открыть архив: ' + Arc);
      end
      else if (not IsVirtualShellPath(FPath)) and
              (Remote or (not Remote and TDirectory.Exists(FPath))) then
      begin
        if Remote then
        begin
          FProbeGate := TEvent.Create(nil, True, False, '');
          TThread.CreateAnonymousThread(
            procedure
            begin
              if Assigned(FProbeGate) and
                 (FProbeGate.WaitFor(4000) <> wrSignaled) then
                if not Terminated then
                begin
                  Terminate;
                  SendError('Сервер не отвечает');
                end;
            end).Start;
        end;
        RC := System.SysUtils.FindFirst(TPath.Combine(FPath, '*.*'), faAnyFile, SearchRec);
{$IFDEF MSWINDOWS}
        ErrCode := GetLastError;
{$ELSE}
        ErrCode := RC;
{$ENDIF}
        if Assigned(FProbeGate) then
          FProbeGate.SetEvent;
        if Terminated then
        begin
          if RC = 0 then
            System.SysUtils.FindClose(SearchRec);
          Abort;
        end;
        if RC <> 0 then
        begin
          if Remote then
          begin
{$IFDEF MSWINDOWS}
            if (ErrCode = ERROR_PATH_NOT_FOUND) and not IsUncPath(FPath) then
            begin
              if not TryListShellFolder(FPath, Entries, FShowHidden) then
                raise Exception.Create(NetErrorText(ErrCode));
            end
            else
              raise Exception.Create(NetErrorText(ErrCode));
{$ELSE}
            raise Exception.Create('Не удалось открыть: ' + FPath);
{$ENDIF}
          end
          else if Entries.Count = 0 then
            TryListShellFolder(FPath, Entries, FShowHidden);
        end
        else
        try
          LastChunk := 0;
          LastEmit := TThread.GetTickCount;
          repeat
            if Terminated then
              Break;
            if (SearchRec.Name = '.') or (SearchRec.Name = '..') then
            begin
              { skip }
            end
            else if not ShouldSkipListedEntry(SearchRec.Attr, FShowHidden) then
            begin
              FullPath := TPath.Combine(FPath, SearchRec.Name);
              Entries.Add(TFileEntry.FromSearchRec(FullPath, SearchRec));
              if Remote then
                if (Entries.Count - LastChunk >= 300) or
                   ((Entries.Count > LastChunk) and
                    (TThread.GetTickCount - LastEmit >= 1000)) then
                begin
                  EmitSlice(Entries, LastChunk, False);
                  NoteProgress(Entries.Count);
                  LastChunk := Entries.Count;
                  LastEmit := TThread.GetTickCount;
                end;
            end;
          until System.SysUtils.FindNext(SearchRec) <> 0;
        finally
          System.SysUtils.FindClose(SearchRec);
        end;
        if (not Remote) and (Entries.Count = 0) then
          TryListShellFolder(FPath, Entries, FShowHidden);
      end
      else if not TryListShellFolder(FPath, Entries, FShowHidden) then
      begin
        if not IsVirtualShellPath(FPath) then
          raise Exception.Create('Не удалось открыть: ' + FPath);
      end;

      if Terminated then
      begin
        if Remote and (Entries.Count > LastChunk) then
        begin
          EmitSlice(Entries, LastChunk, False);
          NoteProgress(Entries.Count);
        end;
        FreeAndNil(Entries);
        Queue(
          procedure
          begin
            if Assigned(FOnDone) then
              FOnDone(nil);
          end);
        Exit;
      end;

      if Remote and Assigned(FOnChunk) then
      begin
        EmitSlice(Entries, LastChunk, True);
        NoteProgress(Entries.Count);
        FreeAndNil(Entries);
        Queue(
          procedure
          begin
            if Assigned(FOnDone) then
              FOnDone(nil);
          end);
        Exit;
      end;

      ListToPass := Entries;
      Entries := nil;

      { Queue, не Synchronize: иначе Refresh.WaitFor на UI даёт взаимную блокировку. }
      Queue(
        procedure
        begin
          try
            if Assigned(FOnDone) then
              FOnDone(ListToPass)
            else
              ListToPass.Free;
          except
            ListToPass.Free;
          end;
        end);

    except
      on E: EAbort do
      begin
        FreeAndNil(Entries);
        if not FErrSent then
          Queue(
            procedure
            begin
              if Assigned(FOnDone) then
                FOnDone(nil);
            end);
      end;
      on E: Exception do
        SendError(E.Message);
    end;
  finally
    if Assigned(FProbeGate) then
      FProbeGate.SetEvent;
    Entries.Free;
{$IFDEF MSWINDOWS}
    if NeedCom then
      CoUninitialize;
{$ENDIF}
  end;
end;

initialization
  GZipMapLock := TCriticalSection.Create;
  GPidlLock := TCriticalSection.Create;
  GPidlMap := TDictionary<string, TBytes>.Create;
  GDriveTypeLock := TCriticalSection.Create;
  GDriveTypeCache := TDictionary<string, Cardinal>.Create;

finalization
  FreeAndNil(GDriveTypeCache);
  FreeAndNil(GDriveTypeLock);
  FreeAndNil(GPidlMap);
  FreeAndNil(GPidlLock);
  FreeAndNil(GZipMapLock);

end.
