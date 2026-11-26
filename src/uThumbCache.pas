unit uThumbCache;

interface

uses

  System.ZLib ,
 Winapi.Windows, Winapi.ShlObj, Winapi.ActiveX,
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.SyncObjs, System.DateUtils, System.StrUtils,
  System.Math, System.UITypes, System.Types,
  FMX.Graphics, FMX.Types, FMX.Skia, System.Skia,
  UCoreEngine, uFileModel, uSpreadsheetData, uDocumentData, uPdfium,
  uPsdPreview, uTextCode;

function TryLoadSvgDom(const APath: string; out ADom: ISkSVGDOM): Boolean;
function ReadSvgText(const APath: string): string;
function ReadSvgSourceBytes(const APath: string; AMax: Integer): TBytes;
function RenderSvgThumbRaw(const APath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  ATrustContent: Boolean = False): Boolean;
function IsThumbCandidate(const APath: string; AIsDir: Boolean = False;
  const ANameHint: string = ''): Boolean;
{ TIF більший за 1 ГБ: свій декодер не запускати. Кадр лише з IFD1 або SubIFD. }
function TiffOverDecoderLimit(const APath: string): Boolean;
function TryTiffEmbeddedPixels(const APath: string; AMaxEdge: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
function LooksLikeLottieFile(const APath: string): Boolean;
function ReadLottieJsonBytes(const APath: string; AMax: Integer;
  AAllowPartial: Boolean = False): TBytes;
function RenderLottieStill(const APath: string; AProgress: Double): FMX.Graphics.TBitmap;
function TrySvgImageSize(const APath: string; out W, H: Integer): Boolean;
function TryLottieImageSize(const APath: string; out W, H: Integer): Boolean;

type
  TThumbReadyProc = reference to procedure(const APath: string; ABitmap: TBitmap);

  TThumbStamp = record
    Age: TDateTime;
    Bytes: Int64;
  end;

  THtmlBlankNote = record
    Stamp: TThumbStamp;
    Count: Integer;
  end;

  TCachedThumb = record
    Bitmap: TBitmap;
    Stamp: TThumbStamp;
  end;

  TThumbJob = record
    Path: string;
    Size: Integer;
    Stamp: TThumbStamp;
    NameHint: string;
    OnReady: TThumbReadyProc;
  end;

  TThumbFocusSlot = record
    Paths: TArray<string>;
    Hints: TArray<string>;
    Size: Integer;
  end;

  TThumbCache = class
  private
    FCache: TDictionary<string, TCachedThumb>;
    FNoThumb: TDictionary<string, TThumbStamp>;
    FHtmlBlank: TDictionary<string, THtmlBlankNote>;
    FSniffMiss: TDictionary<string, THtmlBlankNote>;
    { Великий TIF без кадру: перший промах не в FNoThumb. }
    FHugeMiss: TDictionary<string, THtmlBlankNote>;
    FPending: TDictionary<string, Boolean>;
    FWait: TQueue<TThumbJob>;
    { HTML окремо: один теплий WebView2 і не тримає загальні воркери. }
    FHtmlWait: TQueue<TThumbJob>;
    FLock: TCriticalSection;
    FShuttingDown: Boolean;
    FBusy: Integer;
    FHtmlBusy: Integer;
    FQueued: Integer;
    FEnabled: Boolean;
    FWorkersEnabled: Boolean;
    FMaxItems: Integer;
    FGeneration: Integer;
    { Кнопка «Оновити»: пізній декод не повертає кадр і FNoThumb у скинуту папку. }
    FThumbEpoch: Integer;
    FEpochAt: Integer;
    FEpochFolder: array[0..15] of string;
    FEpochValue: array[0..15] of Integer;
    FOrder: TStringList;
    { Старий шлях кадру, який вже перейменували. Пізній декод кладе результат на новий.
      Якщо розширення змінилось, аліаса немає: старий кадр на новий тип не пишеться. }
    FAlias: TDictionary<string, string>;
    { Розширення до проміжного імені перейменування. Кінцеве інше розширення кадр не успадковує. }
    FCarryExt: TDictionary<string, string>;
    FSlots: TDictionary<TObject, TThumbFocusSlot>;
    FSlotOrder: TList<TObject>;
    procedure TouchLocked(const APath: string);
    procedure EvictLocked;
    function CanCacheFile(const APath: string; const ANameHint: string = ''): Boolean;
    function ReadStamp(const APath: string; out AStamp: TThumbStamp): Boolean;
    function SameStamp(const A, B: TThumbStamp): Boolean;
    procedure RemoveCachedLocked(const APath: string);
    procedure NoteHtmlBlankLocked(const APath: string; const AStamp: TThumbStamp);
    procedure NoteSniffMissLocked(const APath: string; const AStamp: TThumbStamp);
    procedure NoteHugeTiffMissLocked(const APath: string; const AStamp: TThumbStamp);
    procedure DropQueuedLocked(const APath: string);
    function FolderResetSince(const APath: string; AStarted: Integer): Boolean;
    procedure DiscardRenamedLocked(const AOldPath, AOldWant: string);
    procedure EnqueueJobLocked(const AJob: TThumbJob);
    function ResolveAliasLocked(const APath: string): string;
    procedure PumpJobs;
    procedure PumpHtml;
    procedure StartJob(const AJob: TThumbJob; AHtmlLane: Boolean);
    procedure RememberSlot(AOwner: TObject; const APaths, ANameHints: TArray<string>;
      ASize: Integer);
    procedure RebuildFromSlots(AFirst: TObject);
  public
    constructor Create;
    destructor Destroy; override;

    function TryGet(const APath: string; out ABitmap: FMX.Graphics.TBitmap): Boolean;
    { Слот панели: видимые плитки сверху вниз. Общая очередь — объединение слотов.
      Хвост, которого нет ни в одном слоте, снимается. Уже запущенный поток не останавливается. }
    procedure Focus(AOwner: TObject; const APaths, ANameHints: TArray<string>;
      ASize: Integer);
    procedure ReleaseFocus(AOwner: TObject);
    procedure RequestAsync(const APath: string; ASize: Integer; AOnReady: TThumbReadyProc;
      const ANameHint: string = '');
    function HasWork: Boolean;
    function PendingCount: Integer;
    function Generation: Integer;
    procedure Invalidate(const APath: string);
    procedure InvalidateFolder(const AFolder: string);
    { Кадр зі старого шляху на новий, якщо тип той самий.
      Інше розширення кадр не успадковує: плитка малює новий тип. }
    procedure Retarget(const AOldPath, ANewPath: string);
    procedure Shutdown;
    function Quiescent: Boolean;
    procedure Clear;
    procedure Configure(AEnabled: Boolean; AMaxItems: Integer);
    procedure EnableWorkers;
    function ItemCount: Integer;
    function WorkersEnabled: Boolean;

    property ShuttingDown: Boolean read FShuttingDown;
    property Enabled: Boolean read FEnabled;
  end;

var
  GlobalThumbCache: TThumbCache;

implementation

uses
  System.Zip, uVecPreview, uDxfPreview, uHtmlThumb, uArchiveEngine, uImageSniff,
  uMeshPreview, uHdrPreview;

const
  ThumbSniffMaxBytes = Int64(50) * 1024 * 1024;
  ThumbSniffHeadBytes = 8192;
  ThumbSniffHeadMs = 200;

type
  TSniffRender = (srNone, srFrame, srSoft, srSlow);

function IsSvgThumbExt(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.svg') or (Ext = '.svgz') or (Ext = '.ai');
end;

function ThumbExtOf(const APath, ANameHint: string): string;
var
  Name: string;
begin
  Result := LowerCase(ExtractFileExt(APath));
  if Result <> '' then
    Exit;
  if ANameHint <> '' then
    Result := LowerCase(ExtractFileExt(ANameHint));
  if Result <> '' then
    Exit;
  Name := ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll]));
  Result := LowerCase(ExtractFileExt(Name));
end;

function IsMetaThumbExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.emf') or (AExt = '.wmf');
end;

function IsCdrThumbExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.cdr') or (AExt = '.cdt');
end;

function IsRasterThumbExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.jpg') or (AExt = '.jpeg') or (AExt = '.jpe') or
    (AExt = '.jfif') or (AExt = '.png') or (AExt = '.gif') or (AExt = '.bmp') or
    (AExt = '.dib') or (AExt = '.webp') or (AExt = '.tif') or (AExt = '.tiff') or
    (AExt = '.heic') or (AExt = '.heif') or (AExt = '.avif') or
    (AExt = '.jxl') or (AExt = '.tga');
end;

{$IFDEF MSWINDOWS}
const
  ShellThumbHandler = '{E357FCCD-A995-4576-B01F-234630154E96}';
  ShellExtractImage = '{BB2E617C-0920-11d1-9A0B-00C04FC2D6C1}';

var
  GShellThumbCS: TCriticalSection;
  GShellThumbMap: TDictionary<string, Boolean>;

function ShellClassOpen(const APath: string; out AKey: HKEY): Boolean;
begin
  Result := RegOpenKeyEx(HKEY_CLASSES_ROOT, PChar(APath), 0, KEY_READ, AKey) = 0;
  if not Result then
    Result := RegOpenKeyEx(HKEY_CLASSES_ROOT, PChar(APath), 0,
      KEY_READ or KEY_WOW64_64KEY, AKey) = 0;
end;

function ShellClassExists(const APath: string): Boolean;
var
  K: HKEY;
begin
  Result := ShellClassOpen(APath, K);
  if Result then
    RegCloseKey(K);
end;

function ShellClassValue(const APath, AName: string): string;
var
  K: HKEY;
  Typ, N: DWORD;
  Buf: array[0..511] of Char;
begin
  Result := '';
  if not ShellClassOpen(APath, K) then
    Exit;
  try
    N := SizeOf(Buf);
    Typ := 0;
    if AName = '' then
    begin
      if RegQueryValueEx(K, nil, nil, @Typ, @Buf[0], @N) <> 0 then
        Exit;
    end
    else if RegQueryValueEx(K, PChar(AName), nil, @Typ, @Buf[0], @N) <> 0 then
      Exit;
    if (Typ = REG_SZ) or (Typ = REG_EXPAND_SZ) then
      Result := PChar(@Buf[0]);
  finally
    RegCloseKey(K);
  end;
end;

function ShellThumbOnClass(const AClass: string): Boolean;
begin
  Result := (AClass <> '') and
    (ShellClassExists(AClass + '\ShellEx\' + ShellThumbHandler) or
     ShellClassExists(AClass + '\ShellEx\' + ShellExtractImage));
end;

function ExtHasShellThumbnail(const AExt: string): Boolean;
var
  Prog, Cur, Perceived: string;
begin
  Result := False;
  if (AExt = '') or (AExt[1] <> '.') then
    Exit;
  if not Assigned(GShellThumbCS) then
    Exit;
  GShellThumbCS.Enter;
  try
    if Assigned(GShellThumbMap) and GShellThumbMap.TryGetValue(AExt, Result) then
      Exit;
  finally
    GShellThumbCS.Leave;
  end;
  Result := ShellThumbOnClass(AExt) or
    ShellThumbOnClass('SystemFileAssociations\' + AExt);
  if not Result then
  begin
    Prog := ShellClassValue(AExt, '');
    if (Prog <> '') and (Prog[1] <> '.') then
    begin
      Cur := ShellClassValue(Prog + '\CurVer', '');
      if Cur <> '' then
        Prog := Cur;
      Result := ShellThumbOnClass(Prog);
      if not Result then
        Perceived := ShellClassValue(Prog, 'PerceivedType');
    end;
  end;
  if not Result then
  begin
    if Perceived = '' then
      Perceived := ShellClassValue(AExt, 'PerceivedType');
    if Perceived = '' then
      Perceived := ShellClassValue('SystemFileAssociations\' + AExt, 'PerceivedType');
    Perceived := LowerCase(Perceived);
    if (Perceived = 'image') or (Perceived = 'video') or (Perceived = 'audio') then
      Result := ShellThumbOnClass('SystemFileAssociations\' + Perceived);
  end;
  GShellThumbCS.Enter;
  try
    if Assigned(GShellThumbMap) then
      GShellThumbMap.AddOrSetValue(AExt, Result);
  finally
    GShellThumbCS.Leave;
  end;
end;
{$ENDIF}

function ThumbExtBlocksSniff(const AExt: string): Boolean;
begin
  Result := IsArchiveExt(AExt) or IsMeshExt(AExt) or
    MatchText(AExt, [
      '.exe', '.dll', '.ocx', '.scr', '.sys', '.lnk', '.url', '.ico',
      '.tgs', '.lottie',
      '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.webm', '.m4v', '.mpg',
      '.mpeg', '.3gp', '.mts',
      '.mp3', '.wav', '.flac', '.wma', '.aac', '.ogg', '.m4a', '.opus',
      '.mid', '.midi', '.weba',
      '.ttf', '.otf', '.ttc', '.woff', '.woff2', '.fon', '.eot',
      '.xls', '.xlsb', '.xlt', '.xltx', '.xltm', '.doc', '.ppt', '.pptm',
      '.ppsx']);
end;

function ThumbSniffPathBlocked(const APath: string): Boolean;
begin
  Result := IsRecycleBinPath(APath) or IsRecycleItemPath(APath) or
    IsPortableDevicePath(APath) or IsDeviceNamespacePath(APath) or
    IsVirtualShellPath(APath) or IsThisPCPath(APath);
end;

function ThumbExtHasNativePreview(const AExt: string): Boolean;
begin
  Result := IsRasterThumbExt(AExt) or IsHdrExt(AExt) or IsMetaThumbExt(AExt) or
    IsCdrThumbExt(AExt) or IsPdfThumbExt(AExt) or IsSvgThumbExt(AExt) or
    IsPsdThumbExt(AExt) or IsSpreadsheetThumbExt(AExt) or
    IsDocumentThumbExt(AExt) or IsHtmlPageThumbExt(AExt) or
    IsListedTextExt(AExt) or
    (AExt = '.cur') or (AExt = '.dxf');
end;

{ Невідоме розширення без shell-кадру: нюхати. Відоме — лише якщо свій декодер уже впав.
  Великий невідомий файл не нюхати: лишити іконку і не йти в shell. }
function ThumbShouldSniff(const APath, AExt: string; ANativeTried: Boolean;
  ABytes: Int64; var ASkipShell: Boolean): Boolean;
begin
  ASkipShell := False;
  Result := False;
  if ThumbExtBlocksSniff(AExt) or ThumbSniffPathBlocked(APath) then
    Exit;
  if ThumbExtHasNativePreview(AExt) then
    Exit(ANativeTried);
  {$IFDEF MSWINDOWS}
  if ExtHasShellThumbnail(AExt) then
    Exit(False);
  {$ENDIF}
  ASkipShell := True;
  if ABytes > ThumbSniffMaxBytes then
    Exit(False);
  Result := True;
end;

function IsThumbCandidate(const APath: string; AIsDir: Boolean;
  const ANameHint: string): Boolean;
var
  Ext, Arc, Inner: string;
begin
  Result := False;
  if APath = '' then
    Exit;
  if SplitArchivePath(APath, Arc, Inner) and (Inner <> '') then
  begin
    if AIsDir then
      Exit;
    Ext := ThumbExtOf(APath, ANameHint);
    Result := IsRasterThumbExt(Ext) or IsHdrExt(Ext) or IsMetaThumbExt(Ext) or
      IsCdrThumbExt(Ext) or
      (Ext = '.cur') or (Ext = '.dxf') or
      (Ext = '.pdf') or (Ext = '.svg') or (Ext = '.svgz') or (Ext = '.ai') or
      (Ext = '.psd') or (Ext = '.psb') or
      IsMeshExt(Ext) or
      (Ext = '.xlsx') or (Ext = '.xls') or (Ext = '.xlsm') or
      (Ext = '.csv') or (Ext = '.tsv') or
      (Ext = '.docx') or (Ext = '.doc') or (Ext = '.pptx') or (Ext = '.ppt') or
      (Ext = '.htm') or (Ext = '.html') or (Ext = '.xhtml') or
      (Ext = '.tgs') or (Ext = '.lottie') or (Ext = '.json') or
      IsListedTextExt(Ext);
    Exit;
  end;
  if IsThisPCPath(APath) then
    Exit;
  if AIsDir then
  begin
    Result := not IsDriveRoot(APath) and not IsPortableDevicePath(APath) and
      not IsDeviceNamespacePath(APath);
    Exit;
  end;
  Ext := ThumbExtOf(APath, ANameHint);
  if Ext = '' then
  begin
    if ThumbSniffPathBlocked(APath) then
      Exit;
    Exit(True);
  end;
  if IsArchiveExt(Ext) then
    Exit(True);
  { exe/lnk/ico — jumbo из IconCache, не полный decode и не shell-thumb. }
  Result :=
    (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') or (Ext = '.jfif') or
    (Ext = '.png') or (Ext = '.gif') or (Ext = '.bmp') or (Ext = '.dib') or
    (Ext = '.webp') or (Ext = '.tif') or (Ext = '.tiff') or (Ext = '.tga') or
    (Ext = '.heic') or (Ext = '.heif') or (Ext = '.avif') or
    (Ext = '.jxl') or (Ext = '.dds') or IsHdrExt(Ext) or
    (Ext = '.wmf') or (Ext = '.emf') or
    (Ext = '.cur') or (Ext = '.dxf') or
    (Ext = '.cdr') or (Ext = '.cdt') or
    (Ext = '.pdf') or (Ext = '.svg') or (Ext = '.svgz') or (Ext = '.ai') or
    (Ext = '.psd') or (Ext = '.psb') or
    IsMeshExt(Ext) or
    (Ext = '.xlsx') or (Ext = '.xls') or (Ext = '.xlsm') or
    (Ext = '.csv') or (Ext = '.tsv') or
    (Ext = '.tgs') or (Ext = '.lottie') or (Ext = '.json') or
    (Ext = '.htm') or (Ext = '.html') or (Ext = '.xhtml') or
    (Ext = '.docx') or (Ext = '.doc') or (Ext = '.pptx') or (Ext = '.ppt') or
    (Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or (Ext = '.mov') or
    (Ext = '.wmv') or (Ext = '.webm') or
    (IsListedTextExt(Ext) and not IsRemotePath(APath));
  if Result then
    Exit;
  { exe/lnk/ico остаются jumbo-иконками, не системным превью.
    .cur — кадр курсора через BestCursorFrame, не значок типа. }
  if (Ext = '.exe') or (Ext = '.dll') or (Ext = '.ocx') or (Ext = '.scr') or
     (Ext = '.lnk') or (Ext = '.ico') or (Ext = '.sys') or
     (Ext = '.url') then
    Exit;
  {$IFDEF MSWINDOWS}
  Result := ExtHasShellThumbnail(Ext);
  {$ENDIF}
  if Result or ThumbExtBlocksSniff(Ext) or ThumbSniffPathBlocked(APath) then
    Exit;
  Result := True;
end;

function CopyHeadAscii(const ABytes: TBytes; AMax: Integer): string;
var
  I, N: Integer;
begin
  N := Min(Length(ABytes), AMax);
  SetLength(Result, N);
  for I := 0 to N - 1 do
    if ABytes[I] < 128 then
      Result[I + 1] := Char(ABytes[I])
    else
      Result[I + 1] := ' ';
end;

function ExtractXmlEncodingName(const ABytes: TBytes): string;
var
  Head: string;
  P, Q: Integer;
  Quote: Char;
begin
  Result := '';
  Head := LowerCase(CopyHeadAscii(ABytes, 512));
  P := Pos('encoding=', Head);
  if P <= 0 then
    Exit;
  P := P + Length('encoding=');
  if P > Length(Head) then
    Exit;
  Quote := Head[P];
  if (Quote <> '"') and (Quote <> '''') then
    Exit;
  Inc(P);
  Q := P;
  while (Q <= Length(Head)) and (Head[Q] <> Quote) do
    Inc(Q);
  if Q > Length(Head) then
    Exit;
  Result := Trim(Copy(Head, P, Q - P));
end;

function EncodingFromName(const AName: string; out AOwned: Boolean): TEncoding;
var
  N: string;
begin
  Result := nil;
  AOwned := False;
  N := LowerCase(Trim(AName));
  if (N = '') or (N = 'utf-8') or (N = 'utf8') then
    Result := TEncoding.UTF8
  else if (N = 'utf-16') or (N = 'utf-16le') or (N = 'utf16') then
    Result := TEncoding.Unicode
  else if N = 'utf-16be' then
    Result := TEncoding.BigEndianUnicode
  else
  try
    if (N = 'windows-1251') or (N = 'cp1251') then
      Result := TEncoding.GetEncoding(1251)
    else if N = 'windows-1252' then
      Result := TEncoding.GetEncoding(1252)
    else if (N = 'iso-8859-1') or (N = 'latin1') then
      Result := TEncoding.GetEncoding(28591)
    else if N = 'iso-8859-5' then
      Result := TEncoding.GetEncoding(28595)
    else if N = 'koi8-r' then
      Result := TEncoding.GetEncoding(20866)
    else
      Result := TEncoding.GetEncoding(AName);
    AOwned := Assigned(Result) and (Result <> TEncoding.UTF8) and
      (Result <> TEncoding.Unicode) and (Result <> TEncoding.BigEndianUnicode) and
      (Result <> TEncoding.ANSI) and (Result <> TEncoding.ASCII) and
      (Result <> TEncoding.Default);
  except
    Result := nil;
    AOwned := False;
  end;
end;

function MaybeDecompressGzip(const ABytes: TBytes): TBytes;
var
  Src, Dst: TBytesStream;
  Z: TDecompressionStream;
  Buf: array[0..16383] of Byte;
  N: Integer;
begin
  Result := ABytes;
  if Length(ABytes) < 4 then
    Exit;
  if (ABytes[0] <> $1F) or (ABytes[1] <> $8B) then
    Exit;
  Src := TBytesStream.Create(ABytes);
  Dst := TBytesStream.Create;
  try
    Src.Position := 0;
    Z := TDecompressionStream.Create(Src, 15 + 16);
    try
      repeat
        N := Z.Read(Buf[0], SizeOf(Buf));
        if N > 0 then
          Dst.WriteBuffer(Buf[0], N);
      until N = 0;
    finally
      Z.Free;
    end;
    SetLength(Result, Dst.Size);
    if Dst.Size > 0 then
      Move(Dst.Memory^, Result[0], Dst.Size);
  except
    Result := ABytes;
  end;
  Src.Free;
  Dst.Free;
end;

function BytesToSvgString(const ABytes: TBytes): string;
var
  Enc: TEncoding;
  Owned: Boolean;
  Bom: Integer;
  Name: string;
begin
  Result := '';
  if Length(ABytes) = 0 then
    Exit;
  Enc := nil;
  Owned := False;
  Bom := 0;
  try
    if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and
      (ABytes[2] = $BF) then
    begin
      Enc := TEncoding.UTF8;
      Bom := 3;
    end
    else if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    begin
      Enc := TEncoding.Unicode;
      Bom := 2;
    end
    else if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    begin
      Enc := TEncoding.BigEndianUnicode;
      Bom := 2;
    end
    else
    begin
      Name := ExtractXmlEncodingName(ABytes);
      if Name <> '' then
        Enc := EncodingFromName(Name, Owned);
      if Enc = nil then
      begin
        if TEncoding.UTF8.IsBufferValid(ABytes) then
          Enc := TEncoding.UTF8
        else
          Enc := TEncoding.ANSI;
      end;
    end;

    try
      Result := Enc.GetString(ABytes, Bom, Length(ABytes) - Bom);
    except
      if Enc <> TEncoding.ANSI then
      try
        Result := TEncoding.ANSI.GetString(ABytes);
      except
        Result := '';
      end;
    end;
  finally
    if Owned then
      Enc.Free;
  end;
end;

function ReadSvgText(const APath: string): string;
var
  Bytes: TBytes;
begin
  Result := '';
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    Bytes := MaybeDecompressGzip(TFile.ReadAllBytes(APath));
    if Length(Bytes) = 0 then
      Exit;
    Result := BytesToSvgString(Bytes);
  except
    Result := '';
  end;
end;

function ReadSvgSourceBytes(const APath: string; AMax: Integer): TBytes;
var
  FS: TFileStream;
  N, Got: Integer;
  Head: TBytes;
  Z: TDecompressionStream;
begin
  Result := nil;
  if (APath = '') or (AMax < 64) or not TFile.Exists(APath) then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < 1 then
        Exit;
      SetLength(Head, 2);
      if FS.Size >= 2 then
        FS.ReadBuffer(Head[0], 2);
      FS.Position := 0;
      if (FS.Size >= 2) and (Head[0] = $1F) and (Head[1] = $8B) then
      begin
        Z := TDecompressionStream.Create(FS, 31);
        try
          SetLength(Result, AMax);
          Got := 0;
          while Got < AMax do
          begin
            N := Z.Read(Result[Got], AMax - Got);
            if N <= 0 then
              Break;
            Inc(Got, N);
          end;
          SetLength(Result, Got);
        finally
          Z.Free;
        end;
      end
      else
      begin
        N := Integer(Min(FS.Size, Int64(AMax)));
        SetLength(Result, N);
        if N > 0 then
          FS.ReadBuffer(Result[0], N);
      end;
    finally
      FS.Free;
    end;
  except
    Result := nil;
  end;
end;

function SkipWs(const S: string; var I: Integer): Boolean;
begin
  while (I <= Length(S)) and (S[I] <= ' ') do
    Inc(I);
  Result := I <= Length(S);
end;

function CssNameIsUseful(const AName: string): Boolean;
begin
  Result := not ((AName = '') or (AName = 'enable-background') or
    AName.StartsWith('-') or (AName = 'src') or (AName = 'unicode-bidi') or
    (AName = 'direction') or (AName = 'clip') or (AName = 'filter') or
    (AName = 'mask') or (AName = 'marker') or (AName = 'marker-start') or
    (AName = 'marker-mid') or (AName = 'marker-end'));
end;

procedure MergeCssProps(const Dst: TDictionary<string, string>;
  const Src: TDictionary<string, string>);
var
  Pair: TPair<string, string>;
begin
  if Src = nil then
    Exit;
  for Pair in Src do
    Dst.AddOrSetValue(Pair.Key, Pair.Value);
end;

procedure ParseInlineStyle(const AStyle: string; const Dst: TDictionary<string, string>);
var
  I, N, Start, Depth: Integer;
  Item, Name, Value: string;
  C: Char;
begin
  I := 1;
  N := Length(AStyle);
  while I <= N do
  begin
    Start := I;
    Depth := 0;
    while I <= N do
    begin
      C := AStyle[I];
      if C = '(' then
        Inc(Depth)
      else if (C = ')') and (Depth > 0) then
        Dec(Depth)
      else if (C = ';') and (Depth = 0) then
        Break;
      Inc(I);
    end;
    Item := Trim(Copy(AStyle, Start, I - Start));
    if I <= N then
      Inc(I);
    if Item = '' then
      Continue;
    Start := Pos(':', Item);
    if Start <= 1 then
      Continue;
    Name := LowerCase(Trim(Copy(Item, 1, Start - 1)));
    Value := Trim(Copy(Item, Start + 1, MaxInt));
    if (Length(Value) >= 2) and (Value[1] = Value[Length(Value)]) and
      ((Value[1] = '"') or (Value[1] = '''')) then
      Value := Copy(Value, 2, Length(Value) - 2);
    if CssNameIsUseful(Name) and (Value <> '') then
      Dst.AddOrSetValue(Name, Value);
  end;
end;

procedure ParseCssRules(const ACss: string;
  const Rules: TObjectDictionary<string, TDictionary<string, string>>);
var
  I, N, Start, Depth: Integer;
  SelPart, Body, Sel, Key: string;
  Props: TDictionary<string, string>;
  Sels: TArray<string>;
  C: Char;
  InComment: Boolean;
begin
  I := 1;
  N := Length(ACss);
  InComment := False;
  while I <= N do
  begin
    if InComment then
    begin
      if (I < N) and (ACss[I] = '*') and (ACss[I + 1] = '/') then
      begin
        InComment := False;
        Inc(I, 2);
      end
      else
        Inc(I);
      Continue;
    end;
    if (I < N) and (ACss[I] = '/') and (ACss[I + 1] = '*') then
    begin
      InComment := True;
      Inc(I, 2);
      Continue;
    end;
    if ACss[I] <= ' ' then
    begin
      Inc(I);
      Continue;
    end;
    if ACss[I] = '@' then
    begin
      while (I <= N) and (ACss[I] <> '{') and (ACss[I] <> ';') do
        Inc(I);
      if (I <= N) and (ACss[I] = ';') then
      begin
        Inc(I);
        Continue;
      end;
      Depth := 0;
      while I <= N do
      begin
        if ACss[I] = '{' then
          Inc(Depth)
        else if ACss[I] = '}' then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Inc(I);
            Break;
          end;
        end;
        Inc(I);
      end;
      Continue;
    end;
    Start := I;
    while (I <= N) and (ACss[I] <> '{') do
      Inc(I);
    if I > N then
      Break;
    SelPart := Trim(Copy(ACss, Start, I - Start));
    Inc(I);
    Start := I;
    Depth := 1;
    while (I <= N) and (Depth > 0) do
    begin
      C := ACss[I];
      if C = '{' then
        Inc(Depth)
      else if C = '}' then
        Dec(Depth);
      Inc(I);
    end;
    Body := Trim(Copy(ACss, Start, I - Start - 1));
    if (SelPart = '') or (Body = '') then
      Continue;
    Sels := SelPart.Split([',']);
    for Sel in Sels do
    begin
      Key := LowerCase(Trim(Sel));
      if (Key = '') or Key.Contains(' ') or Key.Contains('>') or
        Key.Contains('[') or Key.Contains(':') then
        Continue;
      if not Rules.TryGetValue(Key, Props) then
      begin
        Props := TDictionary<string, string>.Create;
        Rules.Add(Key, Props);
      end;
      ParseInlineStyle(Body, Props);
    end;
  end;
end;

function ExtractAndRemoveStyles(var Svg: string): string;
var
  Low, Inner: string;
  P, TagEnd, CloseP, CloseEnd: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    P := 1;
    while True do
    begin
      Low := LowerCase(Svg);
      P := Pos('<style', Low, P);
      if P = 0 then
        Break;
      if (P + 6 <= Length(Svg)) and
        not CharInSet(Svg[P + 6], [' ', '>', '/', #9, #10, #13]) then
      begin
        Inc(P, 6);
        Continue;
      end;
      TagEnd := Pos('>', Svg, P);
      if TagEnd = 0 then
        Break;
      CloseP := Pos('</style>', LowerCase(Svg), TagEnd);
      if CloseP = 0 then
        Break;
      CloseEnd := CloseP + Length('</style>') - 1;
      Inner := Trim(Copy(Svg, TagEnd + 1, CloseP - TagEnd - 1));
      Low := LowerCase(Inner);
      if Low.StartsWith('<![cdata[') then
      begin
        Delete(Inner, 1, 9);
        if Inner.EndsWith(']]>') then
          SetLength(Inner, Length(Inner) - 3);
        Inner := Trim(Inner);
      end;
      if Inner <> '' then
      begin
        SB.Append(Inner);
        SB.AppendLine;
      end;
      Delete(Svg, P, CloseEnd - P + 1);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RemoveDoctype(const ASvg: string): string;
var
  Low: string;
  P, Q, Depth: Integer;
begin
  Result := ASvg;
  Low := LowerCase(Result);
  P := Pos('<!doctype', Low);
  if P = 0 then
    Exit;
  Q := P + 9;
  Depth := 0;
  while Q <= Length(Result) do
  begin
    if Result[Q] = '[' then
      Inc(Depth)
    else if Result[Q] = ']' then
    begin
      if Depth > 0 then
        Dec(Depth);
    end
    else if (Result[Q] = '>') and (Depth = 0) then
    begin
      Delete(Result, P, Q - P + 1);
      Exit;
    end;
    Inc(Q);
  end;
end;

function FindTagEnd(const S: string; AStart: Integer): Integer;
var
  I: Integer;
  Quote: Char;
begin
  Result := 0;
  I := AStart;
  Quote := #0;
  while I <= Length(S) do
  begin
    if Quote <> #0 then
    begin
      if S[I] = Quote then
        Quote := #0;
    end
    else if (S[I] = '"') or (S[I] = '''') then
      Quote := S[I]
    else if S[I] = '>' then
      Exit(I);
    Inc(I);
  end;
end;

function LocalTagName(const AName: string): string;
var
  P: Integer;
begin
  P := Pos(':', AName);
  if P > 0 then
    Result := LowerCase(Copy(AName, P + 1, MaxInt))
  else
    Result := LowerCase(AName);
end;

procedure ParseTagAttributes(const ATag: string; const Attrs: TStringList;
  const Lookup: TDictionary<string, string>; out AName: string;
  out ASelfClose: Boolean);
var
  I, N, Start: Integer;
  AttrName, AttrVal: string;
  Quote: Char;
begin
  AName := '';
  ASelfClose := False;
  Attrs.Clear;
  Lookup.Clear;
  I := 2;
  N := Length(ATag);
  SkipWs(ATag, I);
  Start := I;
  while (I <= N) and not CharInSet(ATag[I], [' ', #9, #10, #13, '/', '>']) do
    Inc(I);
  AName := Copy(ATag, Start, I - Start);
  while SkipWs(ATag, I) do
  begin
    if (ATag[I] = '/') or (ATag[I] = '>') then
    begin
      ASelfClose := ATag[I] = '/';
      Break;
    end;
    Start := I;
    while (I <= N) and not CharInSet(ATag[I], [' ', #9, #10, #13, '=', '/', '>']) do
      Inc(I);
    AttrName := Copy(ATag, Start, I - Start);
    SkipWs(ATag, I);
    AttrVal := '';
    if (I <= N) and (ATag[I] = '=') then
    begin
      Inc(I);
      SkipWs(ATag, I);
      if I > N then
        Break;
      if (ATag[I] = '"') or (ATag[I] = '''') then
      begin
        Quote := ATag[I];
        Inc(I);
        Start := I;
        while (I <= N) and (ATag[I] <> Quote) do
          Inc(I);
        AttrVal := Copy(ATag, Start, I - Start);
        if I <= N then
          Inc(I);
      end
      else
      begin
        Start := I;
        while (I <= N) and not CharInSet(ATag[I], [' ', #9, #10, #13, '/', '>']) do
          Inc(I);
        AttrVal := Copy(ATag, Start, I - Start);
      end;
    end;
    if AttrName <> '' then
    begin
      Attrs.Add(AttrName + '=' + AttrVal);
      Lookup.AddOrSetValue(LowerCase(AttrName), AttrVal);
    end;
  end;
end;

function QuoteXmlAttr(const AValue: string): string;
begin
  if Pos('"', AValue) > 0 then
    Result := '''' + AValue + ''''
  else
    Result := '"' + AValue + '"';
end;

function RebuildTag(const AName: string; const Attrs: TStringList;
  ASelfClose: Boolean): string;
var
  SB: TStringBuilder;
  I, Eq: Integer;
  Nm, Val: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<');
    SB.Append(AName);
    for I := 0 to Attrs.Count - 1 do
    begin
      Eq := Pos('=', Attrs[I]);
      if Eq <= 0 then
        Continue;
      Nm := Copy(Attrs[I], 1, Eq - 1);
      Val := Copy(Attrs[I], Eq + 1, MaxInt);
      if SameText(Nm, 'class') or SameText(Nm, 'style') then
        Continue;
      SB.Append(' ');
      SB.Append(Nm);
      SB.Append('=');
      SB.Append(QuoteXmlAttr(Val));
    end;
    if ASelfClose then
      SB.Append('/>')
    else
      SB.Append('>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure ApplySelector(const Rules: TObjectDictionary<string, TDictionary<string, string>>;
  const Selector: string; const Dst: TDictionary<string, string>);
var
  Props: TDictionary<string, string>;
begin
  if Rules.TryGetValue(Selector, Props) then
    MergeCssProps(Dst, Props);
end;

function FlattenSvgForSkia(const ASvg: string): string;
var
  Svg, Css, Tag, TagName, ClassList, IdVal, StyleVal, Cls, Sel: string;
  Rules: TObjectDictionary<string, TDictionary<string, string>>;
  Applied, Lookup: TDictionary<string, string>;
  Attrs: TStringList;
  SB: TStringBuilder;
  I, TagEnd, P: Integer;
  SelfClose: Boolean;
  Pair: TPair<string, string>;
  Classes: TArray<string>;
  Low: string;
begin
  Svg := RemoveDoctype(ASvg);
  Css := ExtractAndRemoveStyles(Svg);
  Low := LowerCase(Svg);
  if (Css = '') and (Pos('style=', Low) = 0) then
    Exit(Svg);

  Rules := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
  Applied := TDictionary<string, string>.Create;
  Lookup := TDictionary<string, string>.Create;
  Attrs := TStringList.Create;
  SB := TStringBuilder.Create(Length(Svg) + 256);
  try
    ParseCssRules(Css, Rules);
    I := 1;
    while I <= Length(Svg) do
    begin
      if Svg[I] <> '<' then
      begin
        SB.Append(Svg[I]);
        Inc(I);
        Continue;
      end;
      if (I + 3 <= Length(Svg)) and (Copy(Svg, I, 4) = '<!--') then
      begin
        P := Pos('-->', Svg, I + 4);
        if P = 0 then
        begin
          SB.Append(Copy(Svg, I, MaxInt));
          Break;
        end;
        SB.Append(Copy(Svg, I, P + 2 - I + 1));
        I := P + 3;
        Continue;
      end;
      if (I < Length(Svg)) and ((Svg[I + 1] = '/') or (Svg[I + 1] = '?') or
        (Svg[I + 1] = '!')) then
      begin
        TagEnd := FindTagEnd(Svg, I);
        if TagEnd = 0 then
        begin
          SB.Append(Copy(Svg, I, MaxInt));
          Break;
        end;
        SB.Append(Copy(Svg, I, TagEnd - I + 1));
        I := TagEnd + 1;
        Continue;
      end;
      TagEnd := FindTagEnd(Svg, I);
      if TagEnd = 0 then
      begin
        SB.Append(Copy(Svg, I, MaxInt));
        Break;
      end;
      Tag := Copy(Svg, I, TagEnd - I + 1);
      ParseTagAttributes(Tag, Attrs, Lookup, TagName, SelfClose);
      Applied.Clear;
      ApplySelector(Rules, LocalTagName(TagName), Applied);
      if Lookup.TryGetValue('class', ClassList) then
      begin
        Classes := ClassList.Split([' ', #9, #10, #13]);
        for Cls in Classes do
        begin
          Sel := Trim(Cls);
          if Sel <> '' then
            ApplySelector(Rules, '.' + LowerCase(Sel), Applied);
        end;
      end;
      if Lookup.TryGetValue('id', IdVal) and (IdVal <> '') then
        ApplySelector(Rules, '#' + LowerCase(IdVal), Applied);
      if Lookup.TryGetValue('style', StyleVal) then
        ParseInlineStyle(StyleVal, Applied);
      for Pair in Applied do
      begin
        if Lookup.ContainsKey(Pair.Key) then
        begin
          { CSS wins over presentation attributes. }
          P := 0;
          while P < Attrs.Count do
          begin
            if SameText(Copy(Attrs[P], 1, Pos('=', Attrs[P] + '=') - 1), Pair.Key) then
            begin
              Attrs[P] := Pair.Key + '=' + Pair.Value;
              Break;
            end;
            Inc(P);
          end;
        end
        else
          Attrs.Add(Pair.Key + '=' + Pair.Value);
        Lookup.AddOrSetValue(Pair.Key, Pair.Value);
      end;
      SB.Append(RebuildTag(TagName, Attrs, SelfClose));
      I := TagEnd + 1;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
    Attrs.Free;
    Lookup.Free;
    Applied.Free;
    Rules.Free;
  end;
end;

function TryLoadSvgDom(const APath: string; out ADom: ISkSVGDOM): Boolean;
var
  Text, Flat: string;
begin
  Result := False;
  ADom := nil;
  Text := ReadSvgText(APath);
  if Pos('<svg', LowerCase(Text)) = 0 then
    Exit;
  try
    Flat := FlattenSvgForSkia(Text);
    ADom := TSkSVGDOM.Make(Flat);
    Result := Assigned(ADom) and Assigned(ADom.Root);
    if not Result then
    begin
      ADom := nil;
      if Flat <> Text then
      begin
        ADom := TSkSVGDOM.Make(Text);
        Result := Assigned(ADom) and Assigned(ADom.Root);
        if not Result then
          ADom := nil;
      end;
    end;
  except
    ADom := nil;
    Result := False;
  end;
end;

function RenderSvgThumbRaw(const APath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  ATrustContent: Boolean): Boolean;
var
  Dom: ISkSVGDOM;
  Surf: ISkSurface;
  Intr: TSizeF;
  VB: TRectF;
  Scale, Ox, Oy: Single;
  Info: TSkImageInfo;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if (AWidth < 8) or (AHeight < 8) or (APath = '') then
    Exit;
  if (not ATrustContent) and (not IsSvgThumbExt(APath)) then
    Exit;
  try
    if not TryLoadSvgDom(APath, Dom) then
      Exit;
    Intr := TSizeF.Create(AWidth, AHeight);
    if Assigned(Dom.Root) then
    begin
      Intr := Dom.Root.GetIntrinsicSize(TSizeF.Create(AWidth, AHeight), 96);
      if (Intr.Width < 1) or (Intr.Height < 1) then
      begin
        if Dom.Root.TryGetViewBox(VB) and (VB.Width > 0) and (VB.Height > 0) then
          Intr := TSizeF.Create(VB.Width, VB.Height)
        else
          Intr := TSizeF.Create(AWidth, AHeight);
      end;
    end;
    if (Intr.Width < 1) or (Intr.Height < 1) then
      Intr := TSizeF.Create(AWidth, AHeight);
    Scale := Min(AWidth / Intr.Width, AHeight / Intr.Height);
    Ox := (AWidth - Intr.Width * Scale) / 2;
    Oy := (AHeight - Intr.Height * Scale) / 2;
    Dom.SetContainerSize(Intr);
    Surf := TSkSurface.MakeRaster(AWidth, AHeight, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
    if Surf = nil then
      Exit;
    Surf.Canvas.Clear(TAlphaColors.White);
    Surf.Canvas.Translate(Ox, Oy);
    Surf.Canvas.Scale(Scale, Scale);
    Dom.Render(Surf.Canvas);
    SetLength(APixels, AWidth * AHeight * 4);
    Info := TSkImageInfo.Create(AWidth, AHeight, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
    Result := Surf.ReadPixels(Info, @APixels[0], AWidth * 4);
    if Result then
    begin
      AOutW := AWidth;
      AOutH := AHeight;
    end
    else
      SetLength(APixels, 0);
  except
    Result := False;
    SetLength(APixels, 0);
  end;
end;

const
  HugeTiffBytes = Int64(1024) * 1024 * 1024;
  TiffEmbedMax = 8 * 1024 * 1024;
  TiffEmbedEdge = 4096;

type
  TTiffEnt = record
    Tag: Word;
    Typ: Word;
    Count: UInt64;
    Val: TBytes;
    Off: Int64;
    InlineV: Boolean;
  end;

  TMiniEnt = record
    Tag: Word;
    Typ: Word;
    Count: Cardinal;
    Kind: Integer;
    InlineB: array[0..3] of Byte;
    Meta: TBytes;
    Img: TArray<TBytes>;
    ImgAt: TArray<Int64>;
  end;

  TTiffReader = class
  public
    FS: TFileStream;
    LE: Boolean;
    Big: Boolean;
    destructor Destroy; override;
    function Open(const APath: string): Boolean;
    function Slice(AOff, ALen: Int64; out ABytes: TBytes): Boolean;
    function UAt(const ABytes: TBytes; AAt, ALen: Integer): UInt64;
    function ReadNum(AOff: Int64; ALen: Integer): UInt64;
    function TypeSize(ATyp: Word): Integer;
    function ReadHeader(out AIfd0: Int64): Boolean;
    function ReadIFD(AOff: Int64; out AEnts: TArray<TTiffEnt>; out ANext: Int64): Boolean;
    function FindTag(const AEnts: TArray<TTiffEnt>; ATag: Word; out AEnt: TTiffEnt): Boolean;
    function ValueBytes(const AEnt: TTiffEnt; out ABytes: TBytes): Boolean;
    function EntInts(const AEnt: TTiffEnt; out AVals: TArray<UInt64>): Boolean;
    function EntU(const AEnt: TTiffEnt): UInt64;
    function JpegBytes(const AEnts: TArray<TTiffEnt>): TBytes;
    function RawPixels(const AEnts: TArray<TTiffEnt>; out APixels: TBytes;
      out AW, AH: Integer): Boolean;
    function BuildMini(const AEnts: TArray<TTiffEnt>): TBytes;
  end;

destructor TTiffReader.Destroy;
begin
  FS.Free;
  inherited;
end;

function TTiffReader.Open(const APath: string): Boolean;
begin
  Result := False;
  FS := nil;
  if APath = '' then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    FS := nil;
    Exit;
  end;
  Result := FS.Size >= 8;
end;

function TTiffReader.Slice(AOff, ALen: Int64; out ABytes: TBytes): Boolean;
begin
  Result := False;
  SetLength(ABytes, 0);
  if (FS = nil) or (AOff < 0) or (ALen < 0) or (ALen > TiffEmbedMax) then
    Exit;
  if AOff > FS.Size then
    Exit;
  if ALen > FS.Size - AOff then
    Exit;
  if ALen = 0 then
    Exit(True);
  try
    FS.Position := AOff;
    SetLength(ABytes, ALen);
    FS.ReadBuffer(ABytes[0], ALen);
    Result := True;
  except
    SetLength(ABytes, 0);
    Result := False;
  end;
end;

function TTiffReader.UAt(const ABytes: TBytes; AAt, ALen: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  if (AAt < 0) or (ALen < 1) or (AAt + ALen > Length(ABytes)) then
    Exit;
  if LE then
  begin
    for I := ALen - 1 downto 0 do
      Result := (Result shl 8) or ABytes[AAt + I];
  end
  else
    for I := 0 to ALen - 1 do
      Result := (Result shl 8) or ABytes[AAt + I];
end;

function TTiffReader.ReadNum(AOff: Int64; ALen: Integer): UInt64;
var
  B: TBytes;
begin
  Result := 0;
  if Slice(AOff, ALen, B) then
    Result := UAt(B, 0, ALen);
end;

function TTiffReader.TypeSize(ATyp: Word): Integer;
begin
  case ATyp of
    1, 2, 6, 7: Result := 1;
    3, 8: Result := 2;
    4, 9, 11, 13: Result := 4;
    5, 10, 12, 16, 17, 18: Result := 8;
  else
    Result := 0;
  end;
end;

function TTiffReader.ReadHeader(out AIfd0: Int64): Boolean;
var
  B: TBytes;
  Ver: UInt64;
begin
  Result := False;
  AIfd0 := 0;
  LE := True;
  Big := False;
  if not Slice(0, 8, B) then
    Exit;
  if (B[0] = Ord('I')) and (B[1] = Ord('I')) then
    LE := True
  else if (B[0] = Ord('M')) and (B[1] = Ord('M')) then
    LE := False
  else
    Exit;
  Ver := UAt(B, 2, 2);
  if Ver = 42 then
  begin
    Big := False;
    AIfd0 := Int64(UAt(B, 4, 4));
  end
  else if Ver = 43 then
  begin
    Big := True;
    if not Slice(0, 16, B) then
      Exit;
    if UAt(B, 4, 2) <> 8 then
      Exit;
    AIfd0 := Int64(UAt(B, 8, 8));
  end
  else
    Exit;
  Result := AIfd0 >= 8;
end;

function TTiffReader.ReadIFD(AOff: Int64; out AEnts: TArray<TTiffEnt>;
  out ANext: Int64): Boolean;
var
  Cnt: UInt64;
  EntSize, InlineMax, Head, NextN, I, N, Base, Sz: Integer;
  Blob, Val: TBytes;
  E: TTiffEnt;
  BytesLen: UInt64;
begin
  Result := False;
  SetLength(AEnts, 0);
  ANext := 0;
  if AOff < 8 then
    Exit;
  if Big then
  begin
    Cnt := ReadNum(AOff, 8);
    Head := 8;
    EntSize := 20;
    InlineMax := 8;
    NextN := 8;
  end
  else
  begin
    Cnt := ReadNum(AOff, 2);
    Head := 2;
    EntSize := 12;
    InlineMax := 4;
    NextN := 4;
  end;
  if (Cnt < 1) or (Cnt > 512) then
    Exit;
  N := Integer(Cnt);
  if not Slice(AOff, Head + Int64(N) * EntSize + NextN, Blob) then
    Exit;
  SetLength(AEnts, N);
  for I := 0 to N - 1 do
  begin
    Base := Head + I * EntSize;
    E.Tag := Word(UAt(Blob, Base, 2));
    E.Typ := Word(UAt(Blob, Base + 2, 2));
    if Big then
    begin
      E.Count := UAt(Blob, Base + 4, 8);
      SetLength(Val, 8);
      Move(Blob[Base + 12], Val[0], 8);
    end
    else
    begin
      E.Count := UAt(Blob, Base + 4, 4);
      SetLength(Val, 4);
      Move(Blob[Base + 8], Val[0], 4);
    end;
    E.Val := Val;
    Sz := TypeSize(E.Typ);
    E.InlineV := False;
    E.Off := 0;
    if (Sz > 0) and (E.Count > 0) and
       (E.Count <= (UInt64(TiffEmbedMax) div UInt64(Sz))) then
    begin
      BytesLen := E.Count * UInt64(Sz);
      E.InlineV := BytesLen <= UInt64(InlineMax);
      if not E.InlineV then
        E.Off := Int64(UAt(Val, 0, Length(Val)));
    end;
    AEnts[I] := E;
  end;
  ANext := Int64(UAt(Blob, Head + N * EntSize, NextN));
  Result := True;
end;

function TTiffReader.FindTag(const AEnts: TArray<TTiffEnt>; ATag: Word;
  out AEnt: TTiffEnt): Boolean;
var
  I: Integer;
begin
  Result := False;
  AEnt := Default(TTiffEnt);
  for I := 0 to High(AEnts) do
    if AEnts[I].Tag = ATag then
    begin
      AEnt := AEnts[I];
      Exit(True);
    end;
end;

function TTiffReader.ValueBytes(const AEnt: TTiffEnt; out ABytes: TBytes): Boolean;
var
  Sz: Integer;
  N: Int64;
begin
  Result := False;
  SetLength(ABytes, 0);
  Sz := TypeSize(AEnt.Typ);
  if (Sz <= 0) or (AEnt.Count < 1) then
    Exit;
  if AEnt.Count > (UInt64(TiffEmbedMax) div UInt64(Sz)) then
    Exit;
  N := Int64(AEnt.Count) * Sz;
  if AEnt.InlineV then
  begin
    if N > Length(AEnt.Val) then
      Exit;
    SetLength(ABytes, N);
    if N > 0 then
      Move(AEnt.Val[0], ABytes[0], N);
    Exit(True);
  end;
  Result := Slice(AEnt.Off, N, ABytes);
end;

function TTiffReader.EntInts(const AEnt: TTiffEnt; out AVals: TArray<UInt64>): Boolean;
var
  Sz, I, N: Integer;
  Raw: TBytes;
begin
  Result := False;
  SetLength(AVals, 0);
  Sz := TypeSize(AEnt.Typ);
  if (Sz <= 0) or (AEnt.Count < 1) or (AEnt.Count > 8192) then
    Exit;
  N := Integer(AEnt.Count);
  if not ValueBytes(AEnt, Raw) then
    Exit;
  if Length(Raw) < N * Sz then
    Exit;
  SetLength(AVals, N);
  for I := 0 to N - 1 do
    AVals[I] := UAt(Raw, I * Sz, Sz);
  Result := True;
end;

function TTiffReader.EntU(const AEnt: TTiffEnt): UInt64;
var
  V: TArray<UInt64>;
begin
  if EntInts(AEnt, V) and (Length(V) > 0) then
    Result := V[0]
  else
    Result := 0;
end;

function TTiffReader.JpegBytes(const AEnts: TArray<TTiffEnt>): TBytes;
var
  A, B, Offs, Cnts, Comp: TTiffEnt;
  Off, Len, Total: UInt64;
  VOff, VCnt: TArray<UInt64>;
  I, Dest: Integer;
  Part, All: TBytes;
begin
  SetLength(Result, 0);
  if FindTag(AEnts, 513, A) and FindTag(AEnts, 514, B) then
  begin
    Off := EntU(A);
    Len := EntU(B);
    if (Len >= 32) and (Len <= UInt64(TiffEmbedMax)) and
       Slice(Int64(Off), Int64(Len), Result) and (Length(Result) >= 2) and
       (Result[0] = $FF) and (Result[1] = $D8) then
      Exit;
    SetLength(Result, 0);
  end;
  if not FindTag(AEnts, 259, Comp) then
    Exit;
  if (EntU(Comp) <> 6) and (EntU(Comp) <> 7) then
    Exit;
  if not FindTag(AEnts, 273, Offs) or not FindTag(AEnts, 279, Cnts) then
    Exit;
  if not EntInts(Offs, VOff) or not EntInts(Cnts, VCnt) then
    Exit;
  if (Length(VOff) = 0) or (Length(VOff) <> Length(VCnt)) then
    Exit;
  Total := 0;
  for I := 0 to High(VCnt) do
  begin
    if (VCnt[I] > UInt64(TiffEmbedMax)) or
       (Total > UInt64(TiffEmbedMax) - VCnt[I]) then
      Exit;
    Total := Total + VCnt[I];
  end;
  if Total < 32 then
    Exit;
  SetLength(All, Total);
  Dest := 0;
  for I := 0 to High(VOff) do
  begin
    if not Slice(Int64(VOff[I]), Int64(VCnt[I]), Part) then
    begin
      SetLength(Result, 0);
      Exit;
    end;
    if Length(Part) > 0 then
      Move(Part[0], All[Dest], Length(Part));
    Inc(Dest, Length(Part));
  end;
  if (Length(All) >= 2) and (All[0] = $FF) and (All[1] = $D8) then
    Result := All;
end;

function TTiffReader.RawPixels(const AEnts: TArray<TTiffEnt>; out APixels: TBytes;
  out AW, AH: Integer): Boolean;
var
  Ent, Offs, Cnts: TTiffEnt;
  W, H, Spp, Photo, Rps, Row, Need, Y, X, P, DI, RY, Rows, I: Integer;
  Comp, Planar: UInt64;
  Bps, VOff, VCnt: TArray<UInt64>;
  Strips: TArray<TBytes>;
  Total: UInt64;
  G, RR, GG, BB: Byte;
  Ok: Boolean;
begin
  Result := False;
  SetLength(APixels, 0);
  AW := 0;
  AH := 0;
  if FindTag(AEnts, 254, Ent) and ((EntU(Ent) and 4) <> 0) then
    Exit;
  if not FindTag(AEnts, 256, Ent) then
    Exit;
  W := Integer(EntU(Ent));
  if not FindTag(AEnts, 257, Ent) then
    Exit;
  H := Integer(EntU(Ent));
  if (W < 1) or (H < 1) or (W > TiffEmbedEdge) or (H > TiffEmbedEdge) then
    Exit;
  Comp := 1;
  if FindTag(AEnts, 259, Ent) then
    Comp := EntU(Ent);
  if Comp <> 1 then
    Exit;
  Planar := 1;
  if FindTag(AEnts, 284, Ent) then
    Planar := EntU(Ent);
  if Planar <> 1 then
    Exit;
  Spp := 1;
  if FindTag(AEnts, 277, Ent) then
    Spp := Integer(EntU(Ent));
  if (Spp <> 1) and (Spp <> 3) and (Spp <> 4) then
    Exit;
  if not FindTag(AEnts, 258, Ent) or not EntInts(Ent, Bps) or (Length(Bps) < 1) then
    Exit;
  if (Length(Bps) <> 1) and (Length(Bps) <> Spp) then
    Exit;
  for I := 0 to High(Bps) do
    if Bps[I] <> 8 then
      Exit;
  if Spp = 1 then
    Photo := 1
  else
    Photo := -1;
  if FindTag(AEnts, 262, Ent) then
    Photo := Integer(EntU(Ent))
  else if Spp <> 1 then
    Exit;
  if (Photo <> 0) and (Photo <> 1) and (Photo <> 2) then
    Exit;
  if ((Photo = 0) or (Photo = 1)) and (Spp <> 1) then
    Exit;
  if (Photo = 2) and (Spp < 3) then
    Exit;
  Row := W * Spp;
  if (Row < 1) or (Int64(Row) * H > TiffEmbedMax) then
    Exit;
  if not FindTag(AEnts, 273, Offs) or not FindTag(AEnts, 279, Cnts) then
    Exit;
  if not EntInts(Offs, VOff) or not EntInts(Cnts, VCnt) then
    Exit;
  if (Length(VOff) < 1) or (Length(VOff) <> Length(VCnt)) then
    Exit;
  Total := 0;
  for I := 0 to High(VCnt) do
  begin
    if (VCnt[I] < 1) or (VCnt[I] > UInt64(TiffEmbedMax)) or
       (Total > UInt64(TiffEmbedMax) - VCnt[I]) then
      Exit;
    Total := Total + VCnt[I];
  end;
  Rps := H;
  if FindTag(AEnts, 278, Ent) then
  begin
    Rps := Integer(EntU(Ent));
    if Rps < 1 then
      Exit;
  end;
  SetLength(Strips, Length(VOff));
  for I := 0 to High(VOff) do
    if not Slice(Int64(VOff[I]), Int64(VCnt[I]), Strips[I]) then
      Exit;
  SetLength(APixels, Int64(W) * H * 4);
  Ok := True;
  Y := 0;
  for I := 0 to High(Strips) do
  begin
    if Y >= H then
      Break;
    Rows := Rps;
    if Y + Rows > H then
      Rows := H - Y;
    Need := Rows * Row;
    if (Need < 1) or (Length(Strips[I]) < Need) then
    begin
      Ok := False;
      Break;
    end;
    DI := 0;
    for RY := 0 to Rows - 1 do
    begin
      P := (Y + RY) * W * 4;
      for X := 0 to W - 1 do
      begin
        if Spp = 1 then
        begin
          G := Strips[I][DI];
          if Photo = 0 then
            G := Byte(255 - G);
          APixels[P] := G;
          APixels[P + 1] := G;
          APixels[P + 2] := G;
          APixels[P + 3] := 255;
          Inc(DI);
        end
        else
        begin
          RR := Strips[I][DI];
          GG := Strips[I][DI + 1];
          BB := Strips[I][DI + 2];
          APixels[P] := BB;
          APixels[P + 1] := GG;
          APixels[P + 2] := RR;
          if Spp = 4 then
            APixels[P + 3] := Strips[I][DI + 3]
          else
            APixels[P + 3] := 255;
          Inc(DI, Spp);
        end;
        Inc(P, 4);
      end;
    end;
    Inc(Y, Rows);
  end;
  if (not Ok) or (Y < H) then
  begin
    SetLength(APixels, 0);
    Exit;
  end;
  AW := W;
  AH := H;
  Result := True;
end;

function TTiffReader.BuildMini(const AEnts: TArray<TTiffEnt>): TBytes;
const
  MetaCap = 1024 * 1024;
var
  Items: TArray<TMiniEnt>;
  Ent: TTiffEnt;
  Vals, VOff, VCnt: TArray<UInt64>;
  Parts: TArray<TBytes>;
  Jpeg, Dir, Pay, Arr: TBytes;
  I, J, N, EntAt, At: Integer;
  Fit32, HasImage: Boolean;
  FileAt: Int64;
  Offs: TArray<Int64>;

  procedure Put16(var B: TBytes; AAt: Integer; V: Word);
  begin
    if LE then
    begin
      B[AAt] := Byte(V and $FF);
      B[AAt + 1] := Byte((V shr 8) and $FF);
    end
    else
    begin
      B[AAt] := Byte((V shr 8) and $FF);
      B[AAt + 1] := Byte(V and $FF);
    end;
  end;

  procedure Put32(var B: TBytes; AAt: Integer; V: Cardinal);
  begin
    if LE then
    begin
      B[AAt] := Byte(V and $FF);
      B[AAt + 1] := Byte((V shr 8) and $FF);
      B[AAt + 2] := Byte((V shr 16) and $FF);
      B[AAt + 3] := Byte((V shr 24) and $FF);
    end
    else
    begin
      B[AAt] := Byte((V shr 24) and $FF);
      B[AAt + 1] := Byte((V shr 16) and $FF);
      B[AAt + 2] := Byte((V shr 8) and $FF);
      B[AAt + 3] := Byte(V and $FF);
    end;
  end;

  procedure Put32At(var B: TBytes; AAt: Integer; V: Cardinal);
  begin
    if AAt + 3 >= Length(B) then
      Exit;
    Put32(B, AAt, V);
  end;

  function LoadPieces(const AOffs, ACnts: TArray<UInt64>;
    out AParts: TArray<TBytes>): Boolean;
  var
    K: Integer;
    Total: UInt64;
  begin
    Result := False;
    SetLength(AParts, 0);
    if (Length(AOffs) < 1) or (Length(AOffs) <> Length(ACnts)) then
      Exit;
    Total := 0;
    for K := 0 to High(ACnts) do
    begin
      if (ACnts[K] < 1) or (ACnts[K] > UInt64(TiffEmbedMax)) or
         (Total > UInt64(TiffEmbedMax) - ACnts[K]) then
        Exit;
      Total := Total + ACnts[K];
    end;
    SetLength(AParts, Length(AOffs));
    for K := 0 to High(AOffs) do
      if not Slice(Int64(AOffs[K]), Int64(ACnts[K]), AParts[K]) then
      begin
        SetLength(AParts, 0);
        Exit;
      end;
    Result := True;
  end;

  procedure Push(const AItem: TMiniEnt);
  begin
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)] := AItem;
  end;

  function MakeLongArray(ATag: Word; const AVals: TArray<UInt64>): TMiniEnt;
  var
    K: Integer;
    Raw: TBytes;
  begin
    Result := Default(TMiniEnt);
    Result.Tag := ATag;
    Result.Typ := 4;
    Result.Count := Length(AVals);
    if Length(AVals) = 1 then
    begin
      Result.Kind := 0;
      FillChar(Result.InlineB, SizeOf(Result.InlineB), 0);
      if LE then
      begin
        Result.InlineB[0] := Byte(AVals[0] and $FF);
        Result.InlineB[1] := Byte((AVals[0] shr 8) and $FF);
        Result.InlineB[2] := Byte((AVals[0] shr 16) and $FF);
        Result.InlineB[3] := Byte((AVals[0] shr 24) and $FF);
      end
      else
      begin
        Result.InlineB[0] := Byte((AVals[0] shr 24) and $FF);
        Result.InlineB[1] := Byte((AVals[0] shr 16) and $FF);
        Result.InlineB[2] := Byte((AVals[0] shr 8) and $FF);
        Result.InlineB[3] := Byte(AVals[0] and $FF);
      end;
    end
    else
    begin
      Result.Kind := 1;
      SetLength(Raw, Length(AVals) * 4);
      for K := 0 to High(AVals) do
        Put32(Raw, K * 4, Cardinal(AVals[K]));
      Result.Meta := Raw;
    end;
  end;

  function AppendPay(const Src: TBytes): Int64;
  var
    Nsrc: Integer;
  begin
    Result := Int64(14 + Length(Items) * 12 + Length(Pay));
    Nsrc := Length(Src);
    if Nsrc < 1 then
      Exit;
    At := Length(Pay);
    SetLength(Pay, At + Nsrc);
    Move(Src[0], Pay[At], Nsrc);
    if (Length(Pay) and 1) <> 0 then
    begin
      At := Length(Pay);
      SetLength(Pay, At + 1);
      Pay[At] := 0;
    end;
  end;

  function AttachPair(AOffTag, ACntTag: Word): Boolean;
  var
    OE, CE: TTiffEnt;
    M: TMiniEnt;
  begin
    Result := True;
    if not FindTag(AEnts, AOffTag, OE) then
      Exit;
    Result := False;
    if not FindTag(AEnts, ACntTag, CE) then
      Exit;
    if not EntInts(OE, VOff) or not EntInts(CE, VCnt) then
      Exit;
    if not LoadPieces(VOff, VCnt, Parts) then
      Exit;
    M := Default(TMiniEnt);
    M.Tag := AOffTag;
    M.Typ := 4;
    M.Count := Length(Parts);
    M.Kind := 2;
    M.Img := Parts;
    Push(M);
    Push(MakeLongArray(ACntTag, VCnt));
    HasImage := True;
    Result := True;
  end;

begin
  SetLength(Result, 0);
  SetLength(Items, 0);
  HasImage := False;
  for I := 0 to High(AEnts) do
  begin
    if (AEnts[I].Tag = 330) or (AEnts[I].Tag = 34665) or
       (AEnts[I].Tag = 34853) or (AEnts[I].Tag = 40965) or
       (AEnts[I].Tag = 273) or (AEnts[I].Tag = 279) or
       (AEnts[I].Tag = 324) or (AEnts[I].Tag = 325) or
       (AEnts[I].Tag = 513) or (AEnts[I].Tag = 514) then
      Continue;
    if (AEnts[I].Typ = 16) or (AEnts[I].Typ = 17) then
    begin
      if (AEnts[I].Count >= 1) and (AEnts[I].Count <= 1024) and
         EntInts(AEnts[I], Vals) then
      begin
        Fit32 := True;
        for J := 0 to High(Vals) do
          if Vals[J] > $FFFFFFFF then
            Fit32 := False;
        if Fit32 and (Length(Vals) > 0) then
          Push(MakeLongArray(AEnts[I].Tag, Vals));
      end;
      Continue;
    end;
    if (TypeSize(AEnts[I].Typ) < 1) or (AEnts[I].Count < 1) then
      Continue;
    if AEnts[I].Count > (UInt64(MetaCap) div UInt64(TypeSize(AEnts[I].Typ))) then
      Continue;
    N := Integer(AEnts[I].Count) * TypeSize(AEnts[I].Typ);
    if (N < 1) or (N > MetaCap) then
      Continue;
    if not ValueBytes(AEnts[I], Jpeg) then
      Continue;
    if Length(Jpeg) <> N then
      Continue;
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)] := Default(TMiniEnt);
    Items[High(Items)].Tag := AEnts[I].Tag;
    Items[High(Items)].Typ := AEnts[I].Typ;
    Items[High(Items)].Count := Cardinal(AEnts[I].Count);
    if N <= 4 then
    begin
      Items[High(Items)].Kind := 0;
      FillChar(Items[High(Items)].InlineB, SizeOf(Items[High(Items)].InlineB), 0);
      Move(Jpeg[0], Items[High(Items)].InlineB[0], N);
    end
    else
    begin
      Items[High(Items)].Kind := 1;
      Items[High(Items)].Meta := Jpeg;
    end;
  end;
  if FindTag(AEnts, 273, Ent) and not AttachPair(273, 279) then
    Exit;
  if FindTag(AEnts, 324, Ent) and not AttachPair(324, 325) then
    Exit;
  if FindTag(AEnts, 513, Ent) and FindTag(AEnts, 514, Ent) then
  begin
    if EntU(Ent) > 0 then
    begin
      if FindTag(AEnts, 514, Ent) then
      begin
        FileAt := 0;
        if FindTag(AEnts, 513, Ent) then
          FileAt := Int64(EntU(Ent));
        if FindTag(AEnts, 514, Ent) and
           (EntU(Ent) >= 32) and (EntU(Ent) <= UInt64(TiffEmbedMax)) and
           Slice(FileAt, Int64(EntU(Ent)), Jpeg) and (Length(Jpeg) >= 2) then
        begin
          SetLength(Parts, 1);
          Parts[0] := Jpeg;
          SetLength(Items, Length(Items) + 1);
          Items[High(Items)] := Default(TMiniEnt);
          Items[High(Items)].Tag := 513;
          Items[High(Items)].Typ := 4;
          Items[High(Items)].Count := 1;
          Items[High(Items)].Kind := 2;
          Items[High(Items)].Img := Parts;
          SetLength(Vals, 1);
          Vals[0] := Length(Jpeg);
          Push(MakeLongArray(514, Vals));
          HasImage := True;
        end;
      end;
    end;
  end;
  if not HasImage then
    Exit;
  N := Length(Items);
  if (N < 1) or (N > 512) then
    Exit;
  SetLength(Dir, 14 + N * 12);
  FillChar(Dir[0], Length(Dir), 0);
  if LE then
  begin
    Dir[0] := Ord('I');
    Dir[1] := Ord('I');
  end
  else
  begin
    Dir[0] := Ord('M');
    Dir[1] := Ord('M');
  end;
  Put16(Dir, 2, 42);
  Put32(Dir, 4, 8);
  Put16(Dir, 8, Word(N));
  SetLength(Pay, 0);
  for I := 0 to N - 1 do
  begin
    EntAt := 10 + I * 12;
    Put16(Dir, EntAt, Items[I].Tag);
    Put16(Dir, EntAt + 2, Items[I].Typ);
    Put32(Dir, EntAt + 4, Items[I].Count);
    if Items[I].Kind = 0 then
    begin
      Dir[EntAt + 8] := Items[I].InlineB[0];
      Dir[EntAt + 9] := Items[I].InlineB[1];
      Dir[EntAt + 10] := Items[I].InlineB[2];
      Dir[EntAt + 11] := Items[I].InlineB[3];
    end
    else if Items[I].Kind = 1 then
      Put32At(Dir, EntAt + 8, Cardinal(AppendPay(Items[I].Meta)))
    else
    begin
      SetLength(Offs, Length(Items[I].Img));
      for J := 0 to High(Items[I].Img) do
        Offs[J] := AppendPay(Items[I].Img[J]);
      if Length(Offs) = 1 then
        Put32At(Dir, EntAt + 8, Cardinal(Offs[0]))
      else if Length(Offs) > 1 then
      begin
        SetLength(Arr, Length(Offs) * 4);
        for J := 0 to High(Offs) do
          Put32(Arr, J * 4, Cardinal(Offs[J]));
        Put32At(Dir, EntAt + 8, Cardinal(AppendPay(Arr)));
      end;
    end;
  end;
  SetLength(Result, Length(Dir) + Length(Pay));
  if Length(Dir) > 0 then
    Move(Dir[0], Result[0], Length(Dir));
  if Length(Pay) > 0 then
    Move(Pay[0], Result[Length(Dir)], Length(Pay));
end;

function DecodeEncodedBgra(const AEnc: TBytes; out APixels: TBytes;
  out AW, AH: Integer): Boolean;
var
  Img: ISkImage;
  Info: TSkImageInfo;
begin
  Result := False;
  SetLength(APixels, 0);
  AW := 0;
  AH := 0;
  if Length(AEnc) < 8 then
    Exit;
  try
    Img := TSkImage.MakeFromEncoded(AEnc);
    if Img = nil then
      Exit;
    AW := Img.Width;
    AH := Img.Height;
    if (AW < 1) or (AH < 1) or (AW > TiffEmbedEdge) or (AH > TiffEmbedEdge) then
    begin
      AW := 0;
      AH := 0;
      Exit;
    end;
    Info := TSkImageInfo.Create(AW, AH, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
    SetLength(APixels, Int64(AW) * AH * 4);
    Result := Img.ReadPixels(Info, @APixels[0], NativeUInt(AW) * 4);
    if not Result then
    begin
      SetLength(APixels, 0);
      AW := 0;
      AH := 0;
    end;
  except
    Result := False;
    SetLength(APixels, 0);
    AW := 0;
    AH := 0;
  end;
end;

function FitBgraDown(var APixels: TBytes; var AW, AH: Integer;
  AMaxEdge: Integer): Boolean;
var
  Img: ISkImage;
  SrcInfo, DstInfo: TSkImageInfo;
  DstW, DstH: Integer;
  Scale: Double;
  Dst: TBytes;
begin
  Result := False;
  if (AW < 1) or (AH < 1) or (Length(APixels) < Int64(AW) * AH * 4) then
    Exit;
  if (AMaxEdge >= 8) and (AW <= AMaxEdge) and (AH <= AMaxEdge) then
    Exit(True);
  if AMaxEdge < 8 then
    Exit(True);
  Scale := Min(AMaxEdge / AW, AMaxEdge / AH);
  if Scale > 1 then
    Scale := 1;
  DstW := Max(1, Round(AW * Scale));
  DstH := Max(1, Round(AH * Scale));
  if (DstW = AW) and (DstH = AH) then
    Exit(True);
  try
    SrcInfo := TSkImageInfo.Create(AW, AH, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
    Img := TSkImage.MakeRasterCopy(SrcInfo, @APixels[0], NativeUInt(AW) * 4);
    if Img = nil then
      Exit;
    DstInfo := TSkImageInfo.Create(DstW, DstH, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
    SetLength(Dst, Int64(DstW) * DstH * 4);
    if not Img.ScalePixels(DstInfo, @Dst[0], NativeUInt(DstW) * 4,
      TSkSamplingOptions.Medium) then
      Exit;
    APixels := Dst;
    AW := DstW;
    AH := DstH;
    Result := True;
  except
    Result := False;
  end;
end;

function TiffOverDecoderLimit(const APath: string): Boolean;
var
  Ext: string;
  Sz: Int64;
begin
  Result := False;
  if APath = '' then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.tif') and (Ext <> '.tiff') then
    Exit;
  try
    if not TFile.Exists(APath) then
      Exit;
    Sz := TFile.GetSize(APath);
  except
    Exit;
  end;
  Result := Sz > HugeTiffBytes;
end;

function TryTiffEmbeddedPixels(const APath: string; AMaxEdge: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
var
  R: TTiffReader;
  Ifd0, Next, Next1: Int64;
  Ents0, Ents1, Ents: TArray<TTiffEnt>;
  Cands: TArray<Int64>;
  I, Edge, W, H, Area, BestArea, BestW, BestH: Integer;
  Pix, BestPix: TBytes;

  procedure AddCand(AOff: Int64);
  var
    K: Integer;
  begin
    if AOff < 8 then
      Exit;
    if AOff = Ifd0 then
      Exit;
    if (R = nil) or (R.FS = nil) or (AOff >= R.FS.Size) then
      Exit;
    if Length(Cands) >= 8 then
      Exit;
    for K := 0 to High(Cands) do
      if Cands[K] = AOff then
        Exit;
    SetLength(Cands, Length(Cands) + 1);
    Cands[High(Cands)] := AOff;
  end;

  procedure AddSubs(const AEnts: TArray<TTiffEnt>);
  var
    E: TTiffEnt;
    S: TArray<UInt64>;
    K: Integer;
  begin
    if not R.FindTag(AEnts, 330, E) then
      Exit;
    if not R.EntInts(E, S) then
      Exit;
    for K := 0 to High(S) do
      AddCand(Int64(S[K]));
  end;

  function TryOne(const AEnts: TArray<TTiffEnt>; out OP: TBytes;
    out OW, OH: Integer): Boolean;
  var
    E: TTiffEnt;
    Jpg, Mini: TBytes;
  begin
    Result := False;
    SetLength(OP, 0);
    OW := 0;
    OH := 0;
    if R.FindTag(AEnts, 254, E) and ((R.EntU(E) and 4) <> 0) then
      Exit;
    if R.FindTag(AEnts, 256, E) and (Integer(R.EntU(E)) > TiffEmbedEdge) then
      Exit;
    if R.FindTag(AEnts, 257, E) and (Integer(R.EntU(E)) > TiffEmbedEdge) then
      Exit;
    Jpg := R.JpegBytes(AEnts);
    if (Length(Jpg) > 0) and DecodeEncodedBgra(Jpg, OP, OW, OH) then
      Exit(True);
    SetLength(OP, 0);
    if R.RawPixels(AEnts, OP, OW, OH) then
      Exit(True);
    Mini := R.BuildMini(AEnts);
    if Length(Mini) > 0 then
      Result := DecodeEncodedBgra(Mini, OP, OW, OH);
  end;

begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  Edge := AMaxEdge;
  if Edge < 8 then
    Edge := 8;
  if Edge > 2048 then
    Edge := 2048;
  R := TTiffReader.Create;
  try
    try
      if not R.Open(APath) then
        Exit;
      if not R.ReadHeader(Ifd0) then
        Exit;
      if not R.ReadIFD(Ifd0, Ents0, Next) then
        Exit;
      SetLength(Cands, 0);
      AddCand(Next);
      AddSubs(Ents0);
      if Next >= 8 then
      begin
        if R.ReadIFD(Next, Ents1, Next1) then
          AddSubs(Ents1);
      end;
      BestArea := 0;
      BestW := 0;
      BestH := 0;
      SetLength(BestPix, 0);
      for I := 0 to High(Cands) do
      begin
        if not R.ReadIFD(Cands[I], Ents, Next1) then
          Continue;
        if not TryOne(Ents, Pix, W, H) then
          Continue;
        if (W < 1) or (H < 1) or (Length(Pix) < Int64(W) * H * 4) then
          Continue;
        Area := W * H;
        if Area > BestArea then
        begin
          BestArea := Area;
          BestW := W;
          BestH := H;
          SetLength(BestPix, Length(Pix));
          Move(Pix[0], BestPix[0], Length(Pix));
        end;
      end;
      if (BestArea < 1) or (Length(BestPix) < 4) then
        Exit;
      if not FitBgraDown(BestPix, BestW, BestH, Edge) then
        Exit;
      APixels := BestPix;
      AOutW := BestW;
      AOutH := BestH;
      Result := (AOutW > 0) and (AOutH > 0);
    except
      Result := False;
      SetLength(APixels, 0);
      AOutW := 0;
      AOutH := 0;
    end;
  finally
    R.Free;
  end;
end;

function RenderRasterThumbRaw(const APath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  ATrustContent: Boolean = False): Boolean;
var
  Img: ISkImage;
  Enc: TBytes;
  SrcW, SrcH, DstW, DstH: Integer;
  Scale: Double;
  Info: TSkImageInfo;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if (AWidth < 8) or (AHeight < 8) or (APath = '') then
    Exit;
  if (not ATrustContent) and (not IsRasterThumbExt(ThumbExtOf(APath, ''))) then
    Exit;
  if TiffOverDecoderLimit(APath) then
  begin
    Result := TryTiffEmbeddedPixels(APath, Min(AWidth, AHeight), APixels, AOutW, AOutH);
    Exit;
  end;
  try
    Img := TSkImage.MakeFromEncodedFile(APath);
    if Img = nil then
    begin
      Enc := TFile.ReadAllBytes(APath);
      if Length(Enc) > 0 then
        Img := TSkImage.MakeFromEncoded(Enc);
    end;
    if Img = nil then
      Exit;
    SrcW := Img.Width;
    SrcH := Img.Height;
    if (SrcW < 1) or (SrcH < 1) then
      Exit;
    Scale := Min(AWidth / SrcW, AHeight / SrcH);
    if Scale > 1 then
      Scale := 1;
    DstW := Max(1, Round(SrcW * Scale));
    DstH := Max(1, Round(SrcH * Scale));
    Info := TSkImageInfo.Create(DstW, DstH, TSkColorType.BGRA8888,
      TSkAlphaType.Unpremul);
    SetLength(APixels, Int64(DstW) * DstH * 4);
    if (DstW = SrcW) and (DstH = SrcH) then
      Result := Img.ReadPixels(Info, @APixels[0], NativeUInt(DstW) * 4)
    else
      Result := Img.ScalePixels(Info, @APixels[0], NativeUInt(DstW) * 4,
        TSkSamplingOptions.Medium);
    if Result then
    begin
      AOutW := DstW;
      AOutH := DstH;
    end
    else
      SetLength(APixels, 0);
  except
    Result := False;
    SetLength(APixels, 0);
  end;
end;

function BitmapHasInk(ABmp: TBitmap): Boolean;
var
  Data: TBitmapData;
  X, Y: Integer;
  P: PByte;
begin
  Result := False;
  if (ABmp = nil) or (ABmp.Width < 1) or (ABmp.Height < 1) then
    Exit;
  if not ABmp.Map(TMapAccess.Read, Data) then
    Exit(True);
  try
    for Y := 0 to ABmp.Height - 1 do
    begin
      P := PByte(Data.GetScanline(Y));
      for X := 0 to ABmp.Width - 1 do
      begin
        { BGRA и RGBA: альфа в последнем байте. }
        if P[3] > 12 then
          Exit(True);
        Inc(P, 4);
      end;
    end;
  finally
    ABmp.Unmap(Data);
  end;
end;

function FitThumbDown(ASrc: TBitmap; AMax: Integer): TBitmap;
var
  S: Single;
  DW, DH: Integer;
  Scaled: TBitmap;
begin
  if (ASrc = nil) or (AMax < 8) or
     ((ASrc.Width <= AMax) and (ASrc.Height <= AMax)) then
    Exit(ASrc);
  S := AMax / Max(ASrc.Width, ASrc.Height);
  DW := Max(1, Round(ASrc.Width * S));
  DH := Max(1, Round(ASrc.Height * S));
  Scaled := TBitmap.Create(DW, DH);
  try
    Scaled.SkiaDraw(
      procedure(const C: ISkCanvas)
      begin
        C.Clear(TAlphaColors.Null);
        C.Scale(S, S);
        C.DrawImage(ASrc.ToSkImage, 0, 0);
      end);
  except
    Scaled.Free;
    raise;
  end;
  ASrc.Free;
  Result := Scaled;
end;

{ Крупнейший кадр .cur. Точка прицела не рисуется.
  Полностью прозрачный кадр не кэшируем — остаётся значок типа. }
function BestCursorFrame(const APath: string; AMax: Integer): TBitmap;
var
  Frames: TArray<TBitmap>;
  Labels: TArray<string>;
  I, Best, Area, BestArea: Integer;
  Picked: TBitmap;
begin
  Result := nil;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  SetLength(Frames, 0);
  Picked := nil;
  try
    if not LoadIcoFrames(APath, Frames, Labels) then
      Exit;
    Best := -1;
    BestArea := 0;
    for I := 0 to High(Frames) do
    begin
      if Frames[I] = nil then
        Continue;
      Area := Frames[I].Width * Frames[I].Height;
      if Area > BestArea then
      begin
        BestArea := Area;
        Best := I;
      end;
    end;
    if Best >= 0 then
    begin
      Picked := Frames[Best];
      Frames[Best] := nil;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
  if Picked = nil then
    Exit;
  try
    Picked := FitThumbDown(Picked, AMax);
    if (Picked <> nil) and not BitmapHasInk(Picked) then
      FreeAndNil(Picked);
    Result := Picked;
  except
    FreeAndNil(Picked);
    Result := nil;
  end;
end;

{ TThumbCache }

constructor TThumbCache.Create;
begin
  inherited Create;
  FCache := TDictionary<string, TCachedThumb>.Create;
  FNoThumb := TDictionary<string, TThumbStamp>.Create;
  FHtmlBlank := TDictionary<string, THtmlBlankNote>.Create;
  FSniffMiss := TDictionary<string, THtmlBlankNote>.Create;
  FHugeMiss := TDictionary<string, THtmlBlankNote>.Create;
  FPending := TDictionary<string, Boolean>.Create;
  FWait := TQueue<TThumbJob>.Create;
  FHtmlWait := TQueue<TThumbJob>.Create;
  FOrder := TStringList.Create;
  FAlias := TDictionary<string, string>.Create;
  FCarryExt := TDictionary<string, string>.Create;
  FSlots := TDictionary<TObject, TThumbFocusSlot>.Create;
  FSlotOrder := TList<TObject>.Create;
  FLock := TCriticalSection.Create;
  FShuttingDown := False;
  FBusy := 0;
  FHtmlBusy := 0;
  FQueued := 0;
  FEnabled := True;
  FWorkersEnabled := False;
  FMaxItems := 400;
end;

function TThumbCache.CanCacheFile(const APath: string; const ANameHint: string): Boolean;
var
  IsDir: Boolean;
begin
  Result := False;
  if (APath = '') or IsOfficeLockFile(APath) then
    Exit;
  if IsCloudPlaceholderPath(APath) or IsBlockedReparsePath(APath) then
    Exit;
  IsDir := False;
  try
    IsDir := TDirectory.Exists(APath);
  except
  end;
  Result := IsThumbCandidate(APath, IsDir, ANameHint);
end;

function TThumbCache.ReadStamp(const APath: string; out AStamp: TThumbStamp): Boolean;
var
  Arc, Inner: string;
  Sz: Int64;
  When: TDateTime;
  Enc: Boolean;
begin
  Result := False;
  AStamp.Age := 0;
  AStamp.Bytes := 0;
  if not CanCacheFile(APath) then
    Exit;
  if SplitArchivePath(APath, Arc, Inner) and (Inner <> '') then
  begin
    if not SafeGetFileAge(Arc, AStamp.Age) then
      Exit;
    if ArchiveEntryInfo(APath, Sz, When, Enc) then
      AStamp.Bytes := Sz;
    Result := True;
    Exit;
  end;
  if not SafeGetFileAge(APath, AStamp.Age) then
    Exit;
  try
    if TFile.Exists(APath) then
      AStamp.Bytes := TFile.GetSize(APath);
  except
    AStamp.Bytes := 0;
  end;
  Result := True;
end;

function TThumbCache.SameStamp(const A, B: TThumbStamp): Boolean;
begin
  if (A.Bytes <> 0) or (B.Bytes <> 0) then
  begin
    if A.Bytes <> B.Bytes then
      Exit(False);
    { Как QV: размер + время с малым допуском. }
    Result := Abs(A.Age - B.Age) < (0.2 / 86400.0);
  end
  else
    { Без размера (MTP/FAT) — прежний допуск 2 с. }
    Result := Abs(A.Age - B.Age) < (2.1 / 86400.0);
end;

function TThumbCache.Generation: Integer;
begin
  Result := FGeneration;
end;

procedure TThumbCache.RemoveCachedLocked(const APath: string);
var
  Item: TCachedThumb;
  Idx: Integer;
begin
  if FCache.TryGetValue(APath, Item) then
  begin
    Item.Bitmap.Free;
    FCache.Remove(APath);
  end;
  FNoThumb.Remove(APath);
  FHtmlBlank.Remove(APath);
  if FSniffMiss <> nil then
    FSniffMiss.Remove(APath);
  if FHugeMiss <> nil then
    FHugeMiss.Remove(APath);
  Idx := FOrder.IndexOf(APath);
  if Idx >= 0 then
    FOrder.Delete(Idx);
end;

procedure TThumbCache.TouchLocked(const APath: string);
var
  Idx: Integer;
begin
  Idx := FOrder.IndexOf(APath);
  if Idx >= 0 then
    FOrder.Delete(Idx);
  FOrder.Add(APath);
end;

procedure TThumbCache.EvictLocked;
begin
  while (FMaxItems > 0) and (FCache.Count > FMaxItems) and (FOrder.Count > 0) do
    RemoveCachedLocked(FOrder[0]);
end;

procedure TThumbCache.Configure(AEnabled: Boolean; AMaxItems: Integer);
begin
  FLock.Enter;
  try
    FEnabled := AEnabled;
    if AMaxItems < 50 then
      AMaxItems := 50;
    FMaxItems := AMaxItems;
    EvictLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TThumbCache.EnableWorkers;
begin
  if FWorkersEnabled then
    Exit;
  FWorkersEnabled := True;
  PumpJobs;
end;

function TThumbCache.WorkersEnabled: Boolean;
begin
  Result := FWorkersEnabled;
end;

function TThumbCache.ItemCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCache.Count;
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.Quiescent: Boolean;
begin
  Result := (FBusy = 0) and (FHtmlBusy = 0) and (FQueued = 0);
end;

procedure TThumbCache.Shutdown;
begin
  FShuttingDown := True;
  ShutdownHtmlThumbs;
  FLock.Enter;
  try
    FWait.Clear;
    if FHtmlWait <> nil then
      FHtmlWait.Clear;
    FPending.Clear;
  finally
    FLock.Leave;
  end;
end;

destructor TThumbCache.Destroy;
begin
  Shutdown;
  Clear;
  FCache.Free;
  FNoThumb.Free;
  FHtmlBlank.Free;
  FSniffMiss.Free;
  FHugeMiss.Free;
  FPending.Free;
  FWait.Free;
  FHtmlWait.Free;
  FOrder.Free;
  FAlias.Free;
  FCarryExt.Free;
  FSlots.Free;
  FSlotOrder.Free;
  FLock.Free;
  inherited;
end;

procedure TThumbCache.Clear;
var
  Item: TCachedThumb;
begin
  FLock.Enter;
  try
    for Item in FCache.Values do
      Item.Bitmap.Free;
    FCache.Clear;
    FNoThumb.Clear;
    FHtmlBlank.Clear;
    if FSniffMiss <> nil then
      FSniffMiss.Clear;
    if FHugeMiss <> nil then
      FHugeMiss.Clear;
    FPending.Clear;
    FWait.Clear;
    if FHtmlWait <> nil then
      FHtmlWait.Clear;
    FOrder.Clear;
    FAlias.Clear;
    if FCarryExt <> nil then
      FCarryExt.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TThumbCache.Invalidate(const APath: string);
begin
  if APath = '' then
    Exit;
  FLock.Enter;
  try
    RemoveCachedLocked(APath);
    FPending.Remove(APath);
    Inc(FGeneration);
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.FolderResetSince(const APath: string; AStarted: Integer): Boolean;
var
  I: Integer;
  Folder: string;
begin
  Result := False;
  if APath = '' then
    Exit;
  Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(APath));
  for I := 0 to High(FEpochFolder) do
    if (FEpochValue[I] > AStarted) and (FEpochFolder[I] <> '') and
       (SameText(Folder, FEpochFolder[I]) or
        StartsText(IncludeTrailingPathDelimiter(FEpochFolder[I]), APath)) then
      Exit(True);
end;

procedure TThumbCache.InvalidateFolder(const AFolder: string);
var
  Prefix: string;
  Keys: TArray<string>;
  K: string;

  function InFolder(const APath: string): Boolean;
  begin
    Result := StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(APath))) or
      SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(APath)),
        ExcludeTrailingPathDelimiter(AFolder));
  end;

  procedure DropQueued(Q: TQueue<TThumbJob>);
  var
    Kept: TList<TThumbJob>;
    Job: TThumbJob;
  begin
    if Q = nil then
      Exit;
    Kept := TList<TThumbJob>.Create;
    try
      while Q.Count > 0 do
      begin
        Job := Q.Dequeue;
        if (not Assigned(Job.OnReady)) and InFolder(Job.Path) then
          FPending.Remove(Job.Path)
        else
          Kept.Add(Job);
      end;
      for Job in Kept do
        Q.Enqueue(Job);
    finally
      Kept.Free;
    end;
  end;

begin
  if AFolder = '' then
    Exit;
  Prefix := IncludeTrailingPathDelimiter(AFolder);
  FLock.Enter;
  try
    Keys := FCache.Keys.ToArray;
    for K in Keys do
      if StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(K))) or
         SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(K)),
           ExcludeTrailingPathDelimiter(AFolder)) then
        RemoveCachedLocked(K);
    Keys := FNoThumb.Keys.ToArray;
    for K in Keys do
      if StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(K))) or
         SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(K)),
           ExcludeTrailingPathDelimiter(AFolder)) then
        FNoThumb.Remove(K);
    Keys := FHtmlBlank.Keys.ToArray;
    for K in Keys do
      if StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(K))) or
         SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(K)),
           ExcludeTrailingPathDelimiter(AFolder)) then
        FHtmlBlank.Remove(K);
    if FSniffMiss <> nil then
    begin
      Keys := FSniffMiss.Keys.ToArray;
      for K in Keys do
        if StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(K))) or
           SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(K)),
             ExcludeTrailingPathDelimiter(AFolder)) then
          FSniffMiss.Remove(K);
    end;
    if FHugeMiss <> nil then
    begin
      Keys := FHugeMiss.Keys.ToArray;
      for K in Keys do
        if StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(K))) or
           SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(K)),
             ExcludeTrailingPathDelimiter(AFolder)) then
          FHugeMiss.Remove(K);
    end;
    DropQueued(FWait);
    DropQueued(FHtmlWait);
    Keys := FPending.Keys.ToArray;
    for K in Keys do
      if InFolder(K) then
        FPending.Remove(K);
    Inc(FThumbEpoch);
    FEpochAt := (FEpochAt + 1) and 15;
    FEpochFolder[FEpochAt] := ExcludeTrailingPathDelimiter(AFolder);
    FEpochValue[FEpochAt] := FThumbEpoch;
    Inc(FGeneration);
  finally
    FLock.Leave;
  end;
end;

procedure TThumbCache.NoteHtmlBlankLocked(const APath: string;
  const AStamp: TThumbStamp);
var
  Note: THtmlBlankNote;
  Item: TCachedThumb;
begin
  if (not FHtmlBlank.TryGetValue(APath, Note)) or
     (not SameStamp(Note.Stamp, AStamp)) then
  begin
    Note.Stamp := AStamp;
    Note.Count := 1;
  end
  else
    Inc(Note.Count);
  if Note.Count >= 2 then
  begin
    FHtmlBlank.Remove(APath);
    FNoThumb.AddOrSetValue(APath, AStamp);
    { Старий вдалий кадр лишається, але штамп оновлюємо, щоб не крутити WebView знову. }
    if FCache.TryGetValue(APath, Item) then
    begin
      Item.Stamp := AStamp;
      FCache.AddOrSetValue(APath, Item);
    end;
  end
  else
    FHtmlBlank.AddOrSetValue(APath, Note);
end;

procedure TThumbCache.NoteSniffMissLocked(const APath: string;
  const AStamp: TThumbStamp);
var
  Note: THtmlBlankNote;
begin
  if FSniffMiss = nil then
    Exit;
  if (not FSniffMiss.TryGetValue(APath, Note)) or
     (not SameStamp(Note.Stamp, AStamp)) then
  begin
    Note.Stamp := AStamp;
    Note.Count := 1;
  end
  else
    Inc(Note.Count);
  if Note.Count >= 2 then
  begin
    FSniffMiss.Remove(APath);
    RemoveCachedLocked(APath);
    FNoThumb.AddOrSetValue(APath, AStamp);
    Inc(FGeneration);
  end
  else
    FSniffMiss.AddOrSetValue(APath, Note);
end;

procedure TThumbCache.NoteHugeTiffMissLocked(const APath: string;
  const AStamp: TThumbStamp);
var
  Note: THtmlBlankNote;
begin
  if FHugeMiss = nil then
    Exit;
  if (not FHugeMiss.TryGetValue(APath, Note)) or
     (not SameStamp(Note.Stamp, AStamp)) then
  begin
    Note.Stamp := AStamp;
    Note.Count := 1;
  end
  else
    Inc(Note.Count);
  if Note.Count >= 2 then
  begin
    FHugeMiss.Remove(APath);
    RemoveCachedLocked(APath);
    FNoThumb.AddOrSetValue(APath, AStamp);
    Inc(FGeneration);
  end
  else
    FHugeMiss.AddOrSetValue(APath, Note);
end;

procedure TThumbCache.DropQueuedLocked(const APath: string);
var
  Want: string;

  procedure Keep(Q: TQueue<TThumbJob>);
  var
    Kept: TList<TThumbJob>;
    Job: TThumbJob;
  begin
    if Q = nil then
      Exit;
    Kept := TList<TThumbJob>.Create;
    try
      while Q.Count > 0 do
      begin
        Job := Q.Dequeue;
        if SameText(ExcludeTrailingPathDelimiter(Job.Path), Want) then
          FPending.Remove(Job.Path)
        else
          Kept.Add(Job);
      end;
      for Job in Kept do
        Q.Enqueue(Job);
    finally
      Kept.Free;
    end;
  end;

begin
  Want := ExcludeTrailingPathDelimiter(APath);
  Keep(FWait);
  Keep(FHtmlWait);
end;

procedure TThumbCache.EnqueueJobLocked(const AJob: TThumbJob);
begin
  if IsHtmlPageThumbExt(ThumbExtOf(AJob.Path, AJob.NameHint)) then
    FHtmlWait.Enqueue(AJob)
  else
    FWait.Enqueue(AJob);
end;

function VibeRenameTemp(const APath: string): Boolean;
var
  Name, Tail: string;
  I: Integer;
begin
  Name := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if StartsText('.__vibe_', Name) and SameText(ExtractFileExt(Name), '.tmp') then
    Exit(True);
  I := Pos('.~vibe', LowerCase(Name));
  if I < 1 then
    Exit(False);
  Tail := Copy(Name, I + Length('.~vibe'), MaxInt);
  if Tail = '' then
    Exit(True);
  for I := 1 to Length(Tail) do
    if not CharInSet(Tail[I], ['0'..'9']) then
      Exit(False);
  Result := True;
end;

procedure TThumbCache.DiscardRenamedLocked(const AOldPath, AOldWant: string);
var
  Keys: TArray<string>;
  K: string;
  I: Integer;
begin
  RemoveCachedLocked(AOldPath);
  if not SameText(AOldPath, AOldWant) then
    RemoveCachedLocked(AOldWant);
  Keys := FCache.Keys.ToArray;
  for K in Keys do
    if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
      RemoveCachedLocked(K);
  Keys := FNoThumb.Keys.ToArray;
  for K in Keys do
    if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
      FNoThumb.Remove(K);
  Keys := FHtmlBlank.Keys.ToArray;
  for K in Keys do
    if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
      FHtmlBlank.Remove(K);
  if FSniffMiss <> nil then
  begin
    Keys := FSniffMiss.Keys.ToArray;
    for K in Keys do
      if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
        FSniffMiss.Remove(K);
  end;
  if FHugeMiss <> nil then
  begin
    Keys := FHugeMiss.Keys.ToArray;
    for K in Keys do
      if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
        FHugeMiss.Remove(K);
  end;
  Keys := FPending.Keys.ToArray;
  for K in Keys do
    if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
      FPending.Remove(K);
  for I := FOrder.Count - 1 downto 0 do
    if SameText(ExcludeTrailingPathDelimiter(FOrder[I]), AOldWant) then
      FOrder.Delete(I);
  Keys := FAlias.Keys.ToArray;
  for K in Keys do
    if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) or
       SameText(ExcludeTrailingPathDelimiter(FAlias[K]), AOldWant) then
      FAlias.Remove(K);
  if FCarryExt <> nil then
  begin
    Keys := FCarryExt.Keys.ToArray;
    for K in Keys do
      if SameText(ExcludeTrailingPathDelimiter(K), AOldWant) then
        FCarryExt.Remove(K);
  end;
  DropQueuedLocked(AOldWant);
  Inc(FGeneration);
end;

function TThumbCache.ResolveAliasLocked(const APath: string): string;
var
  N: Integer;
  Next: string;
begin
  Result := APath;
  for N := 1 to 8 do
  begin
    if not FAlias.TryGetValue(Result, Next) or (Next = '') or SameStr(Next, Result) then
      Break;
    Result := Next;
  end;
end;

procedure TThumbCache.Retarget(const AOldPath, ANewPath: string);
var
  OldWant, NewKey, K, OldCache, Next, Carry, NewExt: string;
  Keys: TArray<string>;
  Item, Prev: TCachedThumb;
  I: Integer;
begin
  if FShuttingDown or (AOldPath = '') or (ANewPath = '') then
    Exit;
  OldWant := ExcludeTrailingPathDelimiter(AOldPath);
  NewKey := ANewPath;
  if SameStr(OldWant, ExcludeTrailingPathDelimiter(NewKey)) then
    Exit;
  FLock.Enter;
  try
    Carry := '';
    if (FCarryExt <> nil) and VibeRenameTemp(OldWant) then
      FCarryExt.TryGetValue(OldWant, Carry);
    if Carry = '' then
      Carry := ExtractFileExt(OldWant);
    NewExt := ExtractFileExt(ExcludeTrailingPathDelimiter(NewKey));
    { Проміжне .\~vibe ще не кінцевий тип. Інше розширення — новий кадр. }
    if (not VibeRenameTemp(NewKey)) and (not SameText(Carry, NewExt)) then
    begin
      DiscardRenamedLocked(AOldPath, OldWant);
      Exit;
    end;
    Keys := FAlias.Keys.ToArray;
    for K in Keys do
    begin
      Next := FAlias[K];
      if SameText(ExcludeTrailingPathDelimiter(Next), OldWant) then
        FAlias[K] := NewKey;
    end;
    FAlias.AddOrSetValue(AOldPath, NewKey);
    if not SameStr(AOldPath, OldWant) then
      FAlias.AddOrSetValue(OldWant, NewKey);

    OldCache := '';
    if FCache.ContainsKey(AOldPath) then
      OldCache := AOldPath
    else
    begin
      Keys := FCache.Keys.ToArray;
      for K in Keys do
        if SameText(ExcludeTrailingPathDelimiter(K), OldWant) then
        begin
          OldCache := K;
          Break;
        end;
    end;
    if OldCache <> '' then
    begin
      Item := FCache[OldCache];
      FCache.Remove(OldCache);
      if FCache.TryGetValue(NewKey, Prev) and (Prev.Bitmap <> Item.Bitmap) then
        Prev.Bitmap.Free;
      FCache.AddOrSetValue(NewKey, Item);
      if not SameStr(OldCache, AOldPath) then
        FAlias.AddOrSetValue(OldCache, NewKey);
      FNoThumb.Remove(NewKey);
    end;

    Keys := FNoThumb.Keys.ToArray;
    for K in Keys do
      if SameText(ExcludeTrailingPathDelimiter(K), OldWant) then
        FNoThumb.Remove(K);
    Keys := FHtmlBlank.Keys.ToArray;
    for K in Keys do
      if SameText(ExcludeTrailingPathDelimiter(K), OldWant) then
        FHtmlBlank.Remove(K);
    if FSniffMiss <> nil then
    begin
      Keys := FSniffMiss.Keys.ToArray;
      for K in Keys do
        if SameText(ExcludeTrailingPathDelimiter(K), OldWant) then
          FSniffMiss.Remove(K);
    end;
    if FHugeMiss <> nil then
    begin
      Keys := FHugeMiss.Keys.ToArray;
      for K in Keys do
        if SameText(ExcludeTrailingPathDelimiter(K), OldWant) then
          FHugeMiss.Remove(K);
    end;
    Keys := FPending.Keys.ToArray;
    for K in Keys do
      if SameText(ExcludeTrailingPathDelimiter(K), OldWant) then
        FPending.Remove(K);
    for I := FOrder.Count - 1 downto 0 do
      if SameText(ExcludeTrailingPathDelimiter(FOrder[I]), OldWant) then
        FOrder.Delete(I);
    if OldCache <> '' then
      TouchLocked(NewKey);
    DropQueuedLocked(OldWant);
    if (FCarryExt <> nil) and VibeRenameTemp(OldWant) then
      FCarryExt.Remove(OldWant);
    if (FCarryExt <> nil) and VibeRenameTemp(NewKey) then
      FCarryExt.AddOrSetValue(ExcludeTrailingPathDelimiter(NewKey), Carry);
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.HasWork: Boolean;
begin
  FLock.Enter;
  try
    Result := (FPending.Count > 0) or (FWait.Count > 0) or (FHtmlWait.Count > 0) or
      (FBusy > 0) or (FHtmlBusy > 0) or (FQueued > 0);
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.PendingCount: Integer;
begin
  FLock.Enter;
  try
    Result := FWait.Count + FHtmlWait.Count + FBusy + FHtmlBusy;
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.TryGet(const APath: string; out ABitmap: FMX.Graphics.TBitmap): Boolean;
var
  Item: TCachedThumb;
begin
  ABitmap := nil;
  Result := False;
  if FShuttingDown or (APath = '') then
    Exit;
  FLock.Enter;
  try
    if not FCache.TryGetValue(APath, Item) then
      Exit(False);
    ABitmap := Item.Bitmap;
    Result := Assigned(ABitmap);
  finally
    FLock.Leave;
  end;
end;

procedure TThumbCache.PumpJobs;
var
  MaxWorkers: Integer;
  Job: TThumbJob;
begin
  MaxWorkers := TThread.ProcessorCount;
  if MaxWorkers < 2 then
    MaxWorkers := 2;
  if MaxWorkers > 3 then
    MaxWorkers := 3;
  while True do
  begin
    Job.Path := '';
    Job.Size := 0;
    Job.Stamp := Default(TThumbStamp);
    Job.NameHint := '';
    Job.OnReady := nil;
    FLock.Enter;
    try
      if FShuttingDown or (FBusy >= MaxWorkers) or (FWait.Count = 0) then
        Break;
      Job := FWait.Dequeue;
      Inc(FBusy);
    finally
      FLock.Leave;
    end;
    StartJob(Job, False);
  end;
  PumpHtml;
end;

procedure TThumbCache.PumpHtml;
var
  Job: TThumbJob;
begin
  Job.Path := '';
  Job.Size := 0;
  Job.Stamp := Default(TThumbStamp);
  Job.NameHint := '';
  Job.OnReady := nil;
  FLock.Enter;
  try
    if FShuttingDown or (FHtmlBusy > 0) or (FHtmlWait.Count = 0) then
      Exit;
    Job := FHtmlWait.Dequeue;
    Inc(FHtmlBusy);
  finally
    FLock.Leave;
  end;
  StartJob(Job, True);
end;

function LooksLikeLottieBytes(const ABuf: TBytes): Boolean;
var
  I, N: Integer;
  Head: string;
  C: Byte;
begin
  Result := False;
  N := Min(Length(ABuf), 4096);
  if N < 8 then
    Exit;
  I := 0;
  if (ABuf[0] = $EF) and (ABuf[1] = $BB) and (ABuf[2] = $BF) then
    I := 3;
  while (I < N) and (ABuf[I] in [9, 10, 13, 32]) do
    Inc(I);
  if (I >= N) or (ABuf[I] <> Ord('{')) then
    Exit;
  SetLength(Head, N);
  for I := 0 to N - 1 do
  begin
    C := ABuf[I];
    if C < 128 then
      Head[I + 1] := Char(C)
    else
      Head[I + 1] := ' ';
  end;
  Head := LowerCase(Head);
  Result := (Pos('"layers"', Head) > 0) or (Pos('"assets"', Head) > 0);
end;

function LooksLikeLottieFile(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  N: Integer;
begin
  Result := False;
  if APath = '' then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(4096), FS.Size));
      if N < 8 then
        Exit;
      SetLength(Buf, N);
      FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
    Result := LooksLikeLottieBytes(Buf);
  except
    Result := False;
  end;
end;

function ReadStreamCap(AStream: TStream; AMax: Integer;
  AAllowPartial: Boolean): TBytes;
var
  Buf: TBytes;
  N, Total: Integer;
begin
  Result := nil;
  if (AStream = nil) or (AMax < 8) then
    Exit;
  SetLength(Buf, 65536);
  Total := 0;
  while Total < AMax do
  begin
    N := AStream.Read(Buf[0], Min(Length(Buf), AMax - Total));
    if N <= 0 then
      Break;
    SetLength(Result, Total + N);
    Move(Buf[0], Result[Total], N);
    Inc(Total, N);
  end;
  if (Total >= AMax) and not AAllowPartial then
  begin
    N := AStream.Read(Buf[0], 1);
    if N > 0 then
      Result := nil;
  end;
end;

function LottieExt(const APath: string): string;
begin
  Result := LowerCase(ExtractFileExt(APath));
end;

function ReadLottieJsonBytes(const APath: string; AMax: Integer;
  AAllowPartial: Boolean): TBytes;
var
  Ext: string;
  FS: TFileStream;
  Z: TDecompressionStream;
  Zip: TZipFile;
  I, Best, Score, ThisScore: Integer;
  Name: string;
  Info: TZipHeader;
  Bytes, BestBytes: TBytes;
begin
  Result := nil;
  if (APath = '') or (AMax < 8) then
    Exit;
  Ext := LottieExt(APath);
  try
    if Ext = '.tgs' then
    begin
      FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
      try
        Z := TDecompressionStream.Create(FS, 31);
        try
          Result := ReadStreamCap(Z, AMax, AAllowPartial);
        finally
          Z.Free;
        end;
      finally
        FS.Free;
      end;
      Exit;
    end;
    if Ext = '.lottie' then
    begin
      Best := -1;
      BestBytes := nil;
      Zip := TZipFile.Create;
      try
        Zip.Open(APath, zmRead);
        for I := 0 to Zip.FileCount - 1 do
        begin
          Name := LowerCase(StringReplace(Zip.FileName[I], '/', '\', [rfReplaceAll]));
          if (Name = '') or (Name[Length(Name)] = '\') then
            Continue;
          if ExtractFileExt(Name) <> '.json' then
            Continue;
          Info := Zip.FileInfo[I];
          if (not AAllowPartial) and (Info.UncompressedSize64 > UInt64(AMax)) then
            Continue;
          Zip.Read(I, Bytes);
          if Length(Bytes) = 0 then
            Continue;
          if Length(Bytes) > AMax then
          begin
            if not AAllowPartial then
              Continue;
            SetLength(Bytes, AMax);
          end;
          ThisScore := 1;
          if Pos('manifest', Name) > 0 then
            ThisScore := 0;
          if LooksLikeLottieBytes(Bytes) then
            Inc(ThisScore, 2);
          if Pos('anim', Name) > 0 then
            Inc(ThisScore);
          Score := ThisScore;
          if Score > Best then
          begin
            Best := Score;
            BestBytes := Bytes;
          end;
        end;
      finally
        Zip.Free;
      end;
      Result := BestBytes;
      Exit;
    end;
    if Ext = '.json' then
    begin
      FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
      try
        Result := ReadStreamCap(FS, AMax, AAllowPartial);
      finally
        FS.Free;
      end;
    end;
  except
    Result := nil;
  end;
end;

function SvgSideOk(W, H: Integer): Boolean;
begin
  Result := (W >= 1) and (H >= 1) and (W <= 1000000) and (H <= 1000000);
end;

function ReadSvgHead(const APath: string; AMax: Integer): string;
var
  FS: TFileStream;
  N, Got: Integer;
  Bytes: TBytes;
  Z: TDecompressionStream;
begin
  Result := '';
  if (APath = '') or (AMax < 64) then
    Exit;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size < 8 then
      Exit;
    SetLength(Bytes, 2);
    FS.ReadBuffer(Bytes[0], 2);
    FS.Position := 0;
    if (Bytes[0] = $1F) and (Bytes[1] = $8B) then
    begin
      Z := TDecompressionStream.Create(FS, 31);
      try
        SetLength(Bytes, AMax);
        Got := 0;
        while Got < AMax do
        begin
          N := Z.Read(Bytes[Got], AMax - Got);
          if N <= 0 then
            Break;
          Inc(Got, N);
        end;
        SetLength(Bytes, Got);
      finally
        Z.Free;
      end;
    end
    else
    begin
      N := Integer(Min(FS.Size, Int64(AMax)));
      SetLength(Bytes, N);
      if N > 0 then
        FS.ReadBuffer(Bytes[0], N);
    end;
  finally
    FS.Free;
  end;
  Result := BytesToSvgString(Bytes);
end;

function SvgOpenAt(const S: string; I: Integer): Boolean;
var
  J: Integer;
  Name: string;
begin
  Result := False;
  if (I < 1) or (I > Length(S)) or (S[I] <> '<') then
    Exit;
  J := I + 1;
  if (J + 3 <= Length(S)) and (LowerCase(Copy(S, J, 4)) = 'svg:') then
    Inc(J, 4);
  if J + 2 > Length(S) then
    Exit;
  Name := LowerCase(Copy(S, J, 3));
  if Name <> 'svg' then
    Exit;
  Inc(J, 3);
  if J > Length(S) then
    Exit;
  Result := CharInSet(S[J], [' ', #9, #10, #13, '>', '/']);
end;

function SvgOpenTag(const S: string; I: Integer): string;
var
  J: Integer;
  Q: Char;
begin
  Result := '';
  J := I;
  Q := #0;
  while J <= Length(S) do
  begin
    if Q <> #0 then
    begin
      if S[J] = Q then
        Q := #0;
    end
    else if (S[J] = '"') or (S[J] = '''') then
      Q := S[J]
    else if S[J] = '>' then
      Exit(Copy(S, I, J - I + 1));
    Inc(J);
  end;
end;

function FindSvgOpen(const S: string): string;
var
  I, J: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '<') and (I + 3 <= Length(S)) and (Copy(S, I, 4) = '<!--') then
    begin
      J := Pos('-->', S, I + 4);
      if J < 1 then
        Exit;
      I := J + 3;
      Continue;
    end;
    if SvgOpenAt(S, I) then
      Exit(SvgOpenTag(S, I));
    Inc(I);
  end;
end;

procedure SvgRootAttrs(const Tag: string; out AWidth, AHeight, AViewBox, AStyle: string);
var
  I, N, Start: Integer;
  Name, Value: string;
  Q: Char;
begin
  AWidth := '';
  AHeight := '';
  AViewBox := '';
  AStyle := '';
  I := 1;
  N := Length(Tag);
  while (I <= N) and (Tag[I] <> ' ') and (Tag[I] <> #9) and (Tag[I] <> #10) and
        (Tag[I] <> #13) and (Tag[I] <> '>') do
    Inc(I);
  while I <= N do
  begin
    while (I <= N) and (Tag[I] <= ' ') do
      Inc(I);
    if (I > N) or (Tag[I] = '>') or (Tag[I] = '/') then
      Break;
    Start := I;
    while (I <= N) and (Tag[I] <> '=') and (Tag[I] > ' ') and (Tag[I] <> '>') and
          (Tag[I] <> '/') do
      Inc(I);
    Name := LowerCase(Copy(Tag, Start, I - Start));
    while (I <= N) and (Tag[I] <= ' ') do
      Inc(I);
    Value := '';
    if (I <= N) and (Tag[I] = '=') then
    begin
      Inc(I);
      while (I <= N) and (Tag[I] <= ' ') do
        Inc(I);
      if (I <= N) and ((Tag[I] = '"') or (Tag[I] = '''')) then
      begin
        Q := Tag[I];
        Inc(I);
        Start := I;
        while (I <= N) and (Tag[I] <> Q) do
          Inc(I);
        Value := Copy(Tag, Start, I - Start);
        if I <= N then
          Inc(I);
      end
      else
      begin
        Start := I;
        while (I <= N) and (Tag[I] > ' ') and (Tag[I] <> '>') and (Tag[I] <> '/') do
          Inc(I);
        Value := Copy(Tag, Start, I - Start);
      end;
    end;
    if Name = 'width' then
      AWidth := Value
    else if Name = 'height' then
      AHeight := Value
    else if Name = 'viewbox' then
      AViewBox := Value
    else if Name = 'style' then
      AStyle := Value;
  end;
end;

function StyleProp(const AStyle, AName: string): string;
var
  I, N, Start: Integer;
  Key: string;
begin
  Result := '';
  I := 1;
  N := Length(AStyle);
  while I <= N do
  begin
    while (I <= N) and ((AStyle[I] <= ' ') or (AStyle[I] = ';')) do
      Inc(I);
    Start := I;
    while (I <= N) and (AStyle[I] <> ':') and (AStyle[I] <> ';') do
      Inc(I);
    Key := LowerCase(Trim(Copy(AStyle, Start, I - Start)));
    if (I <= N) and (AStyle[I] = ':') then
      Inc(I);
    while (I <= N) and (AStyle[I] <= ' ') do
      Inc(I);
    Start := I;
    while (I <= N) and (AStyle[I] <> ';') do
      Inc(I);
    if Key = AName then
      Exit(Trim(Copy(AStyle, Start, I - Start)));
    if (I <= N) and (AStyle[I] = ';') then
      Inc(I);
  end;
end;

function SvgLenPx(const S: string; out Px: Double): Boolean;
var
  I: Integer;
  Num, Suffix: string;
  V: Double;
  FS: TFormatSettings;
begin
  Result := False;
  Px := 0;
  FS := TFormatSettings.Invariant;
  I := 1;
  while (I <= Length(S)) and (S[I] <= ' ') do
    Inc(I);
  Num := '';
  if (I <= Length(S)) and ((S[I] = '+') or (S[I] = '-')) then
  begin
    Num := S[I];
    Inc(I);
  end;
  while (I <= Length(S)) and CharInSet(S[I], ['0'..'9', '.', 'e', 'E', '+', '-']) do
  begin
    Num := Num + S[I];
    Inc(I);
  end;
  if (Num = '') or (Num = '+') or (Num = '-') or (Num = '.') then
    Exit;
  if not TryStrToFloat(Num, V, FS) then
    Exit;
  if V < 0 then
    V := -V;
  Suffix := LowerCase(Trim(Copy(S, I, MaxInt)));
  if (Suffix = '') or (Suffix = 'px') then
    Px := V
  else if Suffix = 'pt' then
    Px := V * 96 / 72
  else if Suffix = 'pc' then
    Px := V * 16
  else if Suffix = 'in' then
    Px := V * 96
  else if Suffix = 'cm' then
    Px := V * 96 / 2.54
  else if Suffix = 'mm' then
    Px := V * 96 / 25.4
  else
    Exit;
  Result := Px >= 1;
end;

function ViewBoxSize(const S: string; out VW, VH: Double): Boolean;
var
  I, N: Integer;
  Num: string;
  V: array[0..3] of Double;
  FS: TFormatSettings;
  C: Char;
begin
  Result := False;
  VW := 0;
  VH := 0;
  FS := TFormatSettings.Invariant;
  N := 0;
  Num := '';
  I := 1;
  while I <= Length(S) + 1 do
  begin
    if I <= Length(S) then
      C := S[I]
    else
      C := ' ';
    if (C = ',') or (C <= ' ') then
    begin
      if Num <> '' then
      begin
        if (N >= 4) or not TryStrToFloat(Num, V[N], FS) then
          Exit;
        Inc(N);
        Num := '';
      end;
    end
    else
      Num := Num + C;
    Inc(I);
  end;
  if N <> 4 then
    Exit;
  VW := Abs(V[2]);
  VH := Abs(V[3]);
  Result := (VW >= 1) and (VH >= 1);
end;

function TrySvgImageSize(const APath: string; out W, H: Integer): Boolean;
var
  Ext, Text, Tag, Aw, Ah, Vb, Style: string;
  HasW, HasH, HasV: Boolean;
  PxW, PxH, VbW, VbH: Double;
begin
  Result := False;
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.svg') and (Ext <> '.svgz') and (Ext <> '.ai') then
    Exit;
  try
    Text := ReadSvgHead(APath, 256 * 1024);
    Tag := FindSvgOpen(Text);
    if Tag = '' then
      Exit;
    SvgRootAttrs(Tag, Aw, Ah, Vb, Style);
    if Aw = '' then
      Aw := StyleProp(Style, 'width');
    if Ah = '' then
      Ah := StyleProp(Style, 'height');
    HasW := SvgLenPx(Aw, PxW);
    HasH := SvgLenPx(Ah, PxH);
    HasV := ViewBoxSize(Vb, VbW, VbH);
    if HasW and HasH then
    begin
      W := Max(1, Round(PxW));
      H := Max(1, Round(PxH));
    end
    else if HasW and HasV then
    begin
      W := Max(1, Round(PxW));
      H := Max(1, Round(PxW * VbH / VbW));
    end
    else if HasH and HasV then
    begin
      H := Max(1, Round(PxH));
      W := Max(1, Round(PxH * VbW / VbH));
    end
    else if HasV then
    begin
      W := Max(1, Round(VbW));
      H := Max(1, Round(VbH));
    end
    else
      Exit;
    Result := SvgSideOk(W, H);
    if not Result then
    begin
      W := 0;
      H := 0;
    end;
  except
    Result := False;
    W := 0;
    H := 0;
  end;
end;

function JsonKeyNumber(const Head, Key: string; out V: Double): Boolean;
var
  P, I: Integer;
  Num: string;
  FS: TFormatSettings;
  C: Char;
begin
  Result := False;
  V := 0;
  FS := TFormatSettings.Invariant;
  P := 1;
  while P > 0 do
  begin
    P := Pos(Key, Head, P);
    if P < 1 then
      Exit;
    I := P + Length(Key);
    while (I <= Length(Head)) and (Head[I] <= ' ') do
      Inc(I);
    if (I > Length(Head)) or (Head[I] <> ':') then
    begin
      Inc(P, Length(Key));
      Continue;
    end;
    Inc(I);
    while (I <= Length(Head)) and (Head[I] <= ' ') do
      Inc(I);
    Num := '';
    while I <= Length(Head) do
    begin
      C := Head[I];
      if CharInSet(C, ['0'..'9', '.', '+', '-', 'e', 'E']) then
      begin
        Num := Num + C;
        Inc(I);
      end
      else
        Break;
    end;
    if (Num <> '') and (Num <> '+') and (Num <> '-') and (Num <> '.') and
       TryStrToFloat(Num, V, FS) and (V >= 1) and (V <= 1000000) then
      Exit(True);
    Inc(P, Length(Key));
  end;
end;

function LottieHeadText(const ABuf: TBytes): string;
var
  I, N: Integer;
  C: Byte;
begin
  N := Min(Length(ABuf), 65536);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    C := ABuf[I];
    if (C >= 32) and (C < 128) then
      Result[I + 1] := Char(C)
    else if (C = 9) or (C = 10) or (C = 13) then
      Result[I + 1] := ' '
    else
      Result[I + 1] := ' ';
  end;
end;

function TryLottieImageSize(const APath: string; out W, H: Integer): Boolean;
var
  Ext: string;
  Bytes: TBytes;
  Head: string;
  Fw, Fh: Double;
begin
  Result := False;
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.json') and (Ext <> '.lottie') and (Ext <> '.tgs') then
    Exit;
  try
    Bytes := ReadLottieJsonBytes(APath, 65536, True);
    { Чужой JSON не помечаем. У .tgs и .lottie размер композиции — это w и h,
      даже если layers лежат дальше первых 4 КБ. }
    if (Ext = '.json') and not LooksLikeLottieBytes(Bytes) then
      Exit;
    Head := LottieHeadText(Bytes);
    if not JsonKeyNumber(Head, '"w"', Fw) or not JsonKeyNumber(Head, '"h"', Fh) then
      Exit;
    W := Max(1, Round(Fw));
    H := Max(1, Round(Fh));
    Result := SvgSideOk(W, H);
    if not Result then
    begin
      W := 0;
      H := 0;
    end;
  except
    Result := False;
    W := 0;
    H := 0;
  end;
end;

function OpenLottieAnim(const APath: string): ISkottieAnimation;
var
  Bytes: TBytes;
  MS: TBytesStream;
begin
  Result := nil;
  if APath = '' then
    Exit;
  try
    if LottieExt(APath) = '.json' then
    begin
      Result := TSkottieAnimation.MakeFromFile(APath);
      if Result <> nil then
        Exit;
    end;
    Bytes := ReadLottieJsonBytes(APath, 32 * 1024 * 1024, False);
    if Length(Bytes) < 8 then
      Exit;
    MS := TBytesStream.Create(Bytes);
    try
      Result := TSkottieAnimation.MakeFromStream(MS);
    finally
      MS.Free;
    end;
  except
    Result := nil;
  end;
end;

procedure PaintLottie(const AAnim: ISkottieAnimation; ABitmap: TBitmap;
  AWidth, AHeight: Integer; AProgress: Double; AWhite: Boolean);
var
  Sz: TSizeF;
  S: Single;
  R: TRectF;
  W, H: Integer;
begin
  if (AAnim = nil) or (ABitmap = nil) or (AWidth < 1) or (AHeight < 1) then
    Exit;
  if (AProgress > 0) and (AAnim.Duration > 0) then
    AAnim.SeekFrameTime(AProgress * AAnim.Duration)
  else
    AAnim.SeekFrameTime(0);
  Sz := AAnim.Size;
  if (Sz.Width < 1) or (Sz.Height < 1) then
    Exit;
  if (AWidth = Round(Sz.Width)) and (AHeight = Round(Sz.Height)) then
  begin
    W := AWidth;
    H := AHeight;
    S := 1;
  end
  else
  begin
    W := AWidth;
    H := AHeight;
    S := Min((AWidth - 8) / Sz.Width, (AHeight - 8) / Sz.Height);
    if S <= 0 then
      S := Min(AWidth / Sz.Width, AHeight / Sz.Height);
  end;
  ABitmap.SetSize(W, H);
  R := RectF((W - Sz.Width * S) / 2, (H - Sz.Height * S) / 2, 0, 0);
  R.Right := R.Left + Sz.Width * S;
  R.Bottom := R.Top + Sz.Height * S;
  ABitmap.SkiaDraw(
    procedure(const ACanvas: ISkCanvas)
    begin
      if AWhite then
        ACanvas.Clear($FFFFFFFF)
      else
        ACanvas.Clear($00000000);
      AAnim.Render(ACanvas, R, []);
    end, True);
end;

function RenderLottieThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;
var
  Anim: ISkottieAnimation;
begin
  Result := False;
  if (ABitmap = nil) or (AWidth < 8) or (AHeight < 8) or (APath = '') then
    Exit;
  Anim := OpenLottieAnim(APath);
  if (Anim = nil) or (Anim.Size.Width < 1) or (Anim.Size.Height < 1) then
    Exit;
  PaintLottie(Anim, ABitmap, AWidth, AHeight, 0, True);
  Result := (ABitmap.Width > 0) and (ABitmap.Height > 0);
end;

function RenderLottieStill(const APath: string; AProgress: Double): TBitmap;
var
  Anim: ISkottieAnimation;
  W, H: Integer;
  S: Single;
begin
  Result := nil;
  Anim := OpenLottieAnim(APath);
  if (Anim = nil) or (Anim.Size.Width < 1) or (Anim.Size.Height < 1) then
    Exit;
  W := Max(1, Round(Anim.Size.Width));
  H := Max(1, Round(Anim.Size.Height));
  if (W > 8192) or (H > 8192) then
  begin
    S := Min(8192 / W, 8192 / H);
    W := Max(1, Round(W * S));
    H := Max(1, Round(H * S));
  end;
  Result := TBitmap.Create;
  try
    PaintLottie(Anim, Result, W, H, AProgress, False);
    if Result.Width < 1 then
      FreeAndNil(Result);
  except
    FreeAndNil(Result);
  end;
end;

function RenderSniffThumb(const APath: string; ASize: Integer;
  out ABmp: TBitmap; out ARaw: TBytes; out ARawW, ARawH: Integer): TSniffRender;
var
  Head: TBytes;
  Sig: TImageSig;
  WaitMs: Cardinal;
  Got: Boolean;
begin
  ABmp := nil;
  SetLength(ARaw, 0);
  ARawW := 0;
  ARawH := 0;
  Result := srNone;
  if (APath = '') or (ASize < 8) then
    Exit;
  WaitMs := 0;
  if IsRemotePath(APath) then
    WaitMs := ThumbSniffHeadMs;
  if not ReadFileHead(APath, ThumbSniffHeadBytes, WaitMs, Head) then
    Exit(srSlow);
  Sig := SniffImageBytes(Head);
  case Sig of
    isJpeg, isPng, isGif, isWebp, isBmp, isHeic, isAvif, isJxl:
      begin
        Got := RenderRasterThumbRaw(APath, ASize, ASize, ARaw, ARawW, ARawH, True);
        if Got and (ARawW > 0) and (Length(ARaw) > 0) then
          Result := srFrame
        else
        begin
          SetLength(ARaw, 0);
          ARawW := 0;
          ARawH := 0;
          Result := srSoft;
        end;
      end;
    isIco, isCur:
      begin
        try
          ABmp := BestCursorFrame(APath, ASize);
        except
          FreeAndNil(ABmp);
        end;
        if Assigned(ABmp) and (ABmp.Width > 0) then
          Result := srFrame
        else
        begin
          FreeAndNil(ABmp);
          Result := srSoft;
        end;
      end;
    isSvg:
      begin
        Got := RenderSvgThumbRaw(APath, ASize, ASize, ARaw, ARawW, ARawH, True);
        if Got and (ARawW > 0) and (Length(ARaw) > 0) then
          Result := srFrame
        else
        begin
          SetLength(ARaw, 0);
          ARawW := 0;
          ARawH := 0;
          Result := srSoft;
        end;
      end;
    isPdf:
      begin
        Got := RenderPdfThumbRaw(APath, ASize, ASize, ARaw, ARawW, ARawH, True);
        if Got and (ARawW > 0) and (Length(ARaw) > 0) then
          Result := srFrame
        else
        begin
          SetLength(ARaw, 0);
          ARawW := 0;
          ARawH := 0;
          Result := srSoft;
        end;
      end;
    isPe, isZip:
      Result := srNone;
  else
    if not TextBytesLookLike(Head) then
      Exit(srNone);
    ABmp := TBitmap.Create;
    try
      Got := RenderTextA4Thumb(APath, ASize, ASize, ABmp, True);
      if Got and (ABmp.Width > 0) then
        Result := srFrame
      else
      begin
        FreeAndNil(ABmp);
        Result := srSoft;
      end;
    except
      FreeAndNil(ABmp);
      Result := srSoft;
    end;
  end;
end;

procedure TThumbCache.StartJob(const AJob: TThumbJob; AHtmlLane: Boolean);
var
  Path, NameHint: string;
  Size: Integer;
  Age: TThumbStamp;
  Ready: TThumbReadyProc;
  HtmlLane: Boolean;
  StartedEpoch: Integer;
begin
  Path := AJob.Path;
  Size := AJob.Size;
  Age := AJob.Stamp;
  NameHint := AJob.NameHint;
  Ready := AJob.OnReady;
  HtmlLane := AHtmlLane;
  FLock.Enter;
  try
    StartedEpoch := FThumbEpoch;
  finally
    FLock.Leave;
  end;
  TThread.CreateAnonymousThread(
    procedure
    var
      Bmp: TBitmap;
      Success: Boolean;
      Stamp: TThumbStamp;
      Raw: TBytes;
      RawW, RawH, RenderSize: Integer;
      NeedCom: Boolean;
      Unk: IUnknown;
      Local, Ext, ReadPath, OwnTemp, ArcName, InnerName: string;
      SkipFallback, ArcEnc: Boolean;
      HtmlKind: THtmlThumbKind;
      ArcBytes, MeshCap: Int64;
      ArcWhen: TDateTime;
      NativeTried, SniffSoft, SkipShell, HugeTiff: Boolean;
      SniffKind: TSniffRender;
    begin
      Bmp := nil;
      Success := False;
      NativeTried := False;
      SniffSoft := False;
      SkipShell := False;
      HugeTiff := False;
      HtmlKind := htkIcon;
      Stamp := Age;
      RawW := 0;
      RawH := 0;
{$IFDEF MSWINDOWS}
      NeedCom := CoInitializeEx(nil, COINIT_APARTMENTTHREADED) = S_OK;
{$ELSE}
      NeedCom := False;
{$ENDIF}
      try
        try
          if not FShuttingDown then
          begin
            if not ReadStamp(Path, Stamp) then
              Stamp := Age;
            { Всегда 256 для плиток: чётко, без полного кадра 20 Мп. }
            if Size <= 48 then
              RenderSize := 64
            else
              RenderSize := 256;

            Ext := ThumbExtOf(Path, NameHint);
            SkipFallback := HtmlLane;
            HugeTiff := TiffOverDecoderLimit(Path);
            if HugeTiff then
              SkipFallback := True;
            ReadPath := Path;
            OwnTemp := '';
            if SplitArchivePath(Path, ArcName, InnerName) and (InnerName <> '') then
            begin
              SkipFallback := True;
              ReadPath := '';
              ArcBytes := 0;
              ArcEnc := False;
              MeshCap := 48 * 1024 * 1024;
              if IsMeshExt(Ext) or (Ext = '.dxf') then
                MeshCap := 64 * 1024 * 1024
              else if IsHdrExt(Ext) then
                MeshCap := 128 * 1024 * 1024;
              if ArchiveEntryInfo(Path, ArcBytes, ArcWhen, ArcEnc) and
                 (not ArcEnc) and (ArcBytes <= MeshCap) then
              begin
                Local := '';
                if MaterializeFile(Path, Local) and (Local <> '') and
                   TFile.Exists(Local) and not SameText(Local, Path) then
                begin
                  ReadPath := Local;
                  OwnTemp := Local;
                end;
              end;
            end;
            if IsHdrExt(Ext) and (Bmp = nil) and (ReadPath <> '') then
            begin
              NativeTried := True;
              try
                Bmp := RenderHdrThumb(ReadPath, RenderSize);
                Success := Assigned(Bmp) and (Bmp.Width > 0);
                if not Success then
                  FreeAndNil(Bmp);
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;
            if not Success and IsRasterThumbExt(Ext) then
            begin
              NativeTried := True;
              Success := RenderRasterThumbRaw(ReadPath, RenderSize, RenderSize, Raw, RawW, RawH);
            end;
            if not Success and (Bmp = nil) and (Ext = '.cur') then
            begin
              { Не shell: иначе в кэш попадёт значок типа, а не рисунок курсора. }
              NativeTried := True;
              SkipFallback := True;
              if ReadPath <> '' then
              try
                Bmp := BestCursorFrame(ReadPath, RenderSize);
                Success := Assigned(Bmp) and (Bmp.Width > 0);
                if not Success then
                  FreeAndNil(Bmp);
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;
            if not Success and IsPdfThumbExt(Path) then
            begin
              NativeTried := True;
              Success := RenderPdfThumbRaw(ReadPath, RenderSize, RenderSize, Raw, RawW, RawH);
            end;
            if not Success and IsSvgThumbExt(Path) then
            begin
              NativeTried := True;
              Success := RenderSvgThumbRaw(ReadPath, RenderSize, RenderSize, Raw, RawW, RawH,
                False);
            end;
            if not Success and IsPsdThumbExt(Path) then
            begin
              NativeTried := True;
              Success := RenderPsdThumbRaw(ReadPath, RenderSize, RenderSize, Raw, RawW, RawH);
            end;
            if not Success and (Bmp = nil) and IsMeshExt(Ext) then
            begin
              { 3MF: зіпсований zip лишає системну іконку. Інші сітки — ні. }
              if not SameText(Ext, '.3mf') then
                SkipFallback := True;
              if ReadPath <> '' then
              try
                Bmp := RenderMeshThumb(ReadPath, RenderSize);
                Success := Assigned(Bmp) and (Bmp.Width > 0);
                if not Success then
                  FreeAndNil(Bmp);
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;

            if not Success and (Length(Raw) = 0) then
            begin
              if IsSpreadsheetThumbExt(Path) or IsDocumentThumbExt(Path) then
              begin
                NativeTried := True;
                Bmp := TBitmap.Create;
                try
                  if IsSpreadsheetThumbExt(Path) then
                    Success := RenderSpreadsheetThumb(ReadPath, RenderSize, RenderSize, Bmp);
                  if not Success and IsDocumentThumbExt(Path) then
                    Success := RenderDocumentThumb(ReadPath, RenderSize, RenderSize, Bmp);
                  if not Success or (Bmp.Width <= 0) then
                  begin
                    Success := False;
                    FreeAndNil(Bmp);
                  end;
                except
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              end;
            end;

            if not Success and (Bmp = nil) and (Ext = '.dxf') then
            begin
              NativeTried := True;
              Bmp := TBitmap.Create;
              try
                Success := RenderDxfTile(ReadPath, RenderSize, Bmp);
                if not Success or (Bmp.Width <= 0) then
                begin
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;

            if not Success and (Bmp = nil) and IsMetaThumbExt(Ext) then
            begin
              NativeTried := True;
              Bmp := TBitmap.Create;
              try
                Success := RenderMetaTile(ReadPath, RenderSize, Bmp);
                if not Success or (Bmp.Width <= 0) then
                begin
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;

            if not Success and (Bmp = nil) and IsCdrThumbExt(Ext) then
            begin
              NativeTried := True;
              Bmp := TBitmap.Create;
              try
                { Сетевой файл: только маленькое превью из ZIP, без чтения десятков МБ. }
                Success := RenderCdrTile(ReadPath, RenderSize, Bmp, not IsRemotePath(Path));
                if not Success or (Bmp.Width <= 0) then
                begin
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;

            if not Success and (Bmp = nil) and
               ((Ext = '.tgs') or (Ext = '.lottie') or (Ext = '.json')) then
            begin
              if (Ext <> '.json') or LooksLikeLottieFile(ReadPath) then
              begin
                SkipFallback := True;
                Bmp := TBitmap.Create;
                try
                  Success := RenderLottieThumb(ReadPath, RenderSize, RenderSize, Bmp);
                  if not Success or (Bmp.Width <= 0) then
                  begin
                    Success := False;
                    FreeAndNil(Bmp);
                  end;
                except
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              end
              else if IsRemotePath(Path) then
                SkipFallback := True;
            end;

            if HtmlLane and (not Success) and (Bmp = nil) and
               IsHtmlPageThumbExt(Ext) then
            begin
              NativeTried := True;
              SkipFallback := True;
              Bmp := TBitmap.Create;
              try
                HtmlKind := htkIcon;
                Success := RenderHtmlPageThumb(ReadPath, RenderSize, RenderSize, Bmp,
                  HtmlKind);
                if not Success or (Bmp.Width <= 0) then
                begin
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;

            if not SkipFallback and not Success and (Bmp = nil) and
               IsListedTextExt(Ext) and not IsRemotePath(Path) then
            begin
              NativeTried := True;
              Bmp := TBitmap.Create;
              try
                Success := RenderTextA4Thumb(ReadPath, RenderSize, RenderSize, Bmp);
                if not Success or (Bmp.Width <= 0) then
                begin
                  Success := False;
                  FreeAndNil(Bmp);
                end;
              except
                Success := False;
                FreeAndNil(Bmp);
              end;
            end;

            { Нюх лише тут, у воркері. Відоме розширення вже спробували вище. }
            if (not HugeTiff) and (not Success) and (Bmp = nil) and (Length(Raw) = 0) and
               (HtmlKind <> htkEmpty) and (ReadPath <> '') and
               (not TDirectory.Exists(Path)) and
               ThumbShouldSniff(Path, Ext, NativeTried, Stamp.Bytes, SkipShell) then
            begin
              if SkipShell then
                SkipFallback := True;
              SniffKind := RenderSniffThumb(ReadPath, RenderSize, Bmp, Raw, RawW, RawH);
              case SniffKind of
                srFrame:
                  Success := Assigned(Bmp) or ((Length(Raw) > 0) and (RawW > 0));
                srSoft:
                  begin
                    SniffSoft := True;
                    SkipFallback := True;
                    FreeAndNil(Bmp);
                    SetLength(Raw, 0);
                  end;
                srSlow:
                  begin
                    SkipFallback := True;
                    FreeAndNil(Bmp);
                    SetLength(Raw, 0);
                  end;
              else
                FreeAndNil(Bmp);
                SetLength(Raw, 0);
              end;
            end
            else if SkipShell then
              SkipFallback := True;

{$IFDEF MSWINDOWS}
            if not SkipFallback and not Success then
            begin
              Unk := nil;
              if TryBindShellItem(Path, Unk) then
                Success := GetShellItemThumbnailRaw(Unk, RenderSize, RenderSize, Raw, RawW, RawH);
            end;
{$ENDIF}
            if not SkipFallback and not Success then
              Success := GetFileThumbnailRaw(Path, RenderSize, RenderSize, Raw, RawW, RawH);
            if Success and (Length(Raw) > 0) and (RawW > 0) and (RawH > 0) and
               TDirectory.Exists(Path) then
              ClearFolderThumbPlate(Raw, RawW, RawH);
{$IFDEF MSWINDOWS}
            if (not HugeTiff) and (not Success) and IsRasterThumbExt(Ext) and
               (IsPortableDevicePath(Path) or IsDeviceNamespacePath(Path) or
                IsVirtualShellPath(Path)) then
            begin
              Local := '';
              if MaterializeFile(Path, Local) and (Local <> '') and
                 not SameText(Local, Path) and TFile.Exists(Local) then
              try
                Success := RenderRasterThumbRaw(Local, RenderSize, RenderSize, Raw, RawW, RawH);
                if not Success then
                  Success := GetFileThumbnailRaw(Local, RenderSize, RenderSize, Raw, RawW, RawH);
              finally
                try
                  TFile.Delete(Local);
                except
                end;
              end;
            end;
            if HugeTiff and (not Success) and (Bmp = nil) and (Length(Raw) = 0) then
              Success := GetCachedShellThumbnailRaw(Path, 256, Raw, RawW, RawH);
{$ENDIF}
          end;
        except
          Success := False;
          FreeAndNil(Bmp);
          SetLength(Raw, 0);
        end;

        if OwnTemp <> '' then
          try
            TFile.Delete(OwnTemp);
          except
          end;

        if FShuttingDown then
        begin
          FreeAndNil(Bmp);
          Exit;
        end;

        AtomicIncrement(FQueued);
        TThread.Queue(nil,
          procedure
          var
            Stored: TCachedThumb;
            Old: TCachedThumb;
            UiBmp: TBitmap;
            NotifyBmp: TBitmap;
            StorePath: string;
          begin
            UiBmp := nil;
            NotifyBmp := nil;
            StorePath := Path;
            try
              if FShuttingDown or (GlobalThumbCache = nil) then
              begin
                Bmp.Free;
                Exit;
              end;

              if Success and (Length(Raw) > 0) and (RawW > 0) then
              begin
                UiBmp := TBitmap.Create;
                try
                  FillBitmapFromBgra(UiBmp, Raw, RawW, RawH);
                except
                  FreeAndNil(UiBmp);
                end;
                Success := Assigned(UiBmp) and (UiBmp.Width > 0);
              end
              else if Success and Assigned(Bmp) and (Bmp.Width > 0) then
              begin
                UiBmp := TBitmap.Create;
                try
                  UiBmp.Assign(Bmp);
                except
                  FreeAndNil(UiBmp);
                end;
                Success := Assigned(UiBmp) and (UiBmp.Width > 0);
              end;
              FreeAndNil(Bmp);

              FLock.Enter;
              try
                if (not Assigned(Ready)) and FolderResetSince(Path, StartedEpoch) then
                  FreeAndNil(UiBmp)
                else
                begin
                StorePath := ResolveAliasLocked(Path);
                FPending.Remove(Path);
                if not SameStr(StorePath, Path) then
                  FPending.Remove(StorePath);
                if Success and Assigned(UiBmp) then
                begin
                  { Кадр уже лежить на новому шляху. Другий декод його не замінює. }
                  if (not SameStr(StorePath, Path)) and FCache.ContainsKey(StorePath) then
                    FreeAndNil(UiBmp)
                  else
                  begin
                    if FCache.TryGetValue(StorePath, Old) and (Old.Bitmap <> UiBmp) then
                      Old.Bitmap.Free;
                    if not SameStr(StorePath, Path) then
                      RemoveCachedLocked(Path);
                    Stored.Bitmap := UiBmp;
                    Stored.Stamp := Stamp;
                    FCache.AddOrSetValue(StorePath, Stored);
                    FNoThumb.Remove(StorePath);
                    FNoThumb.Remove(Path);
                    FHtmlBlank.Remove(StorePath);
                    FHtmlBlank.Remove(Path);
                    if FSniffMiss <> nil then
                    begin
                      FSniffMiss.Remove(StorePath);
                      FSniffMiss.Remove(Path);
                    end;
                    if FHugeMiss <> nil then
                    begin
                      FHugeMiss.Remove(StorePath);
                      FHugeMiss.Remove(Path);
                    end;
                    TouchLocked(StorePath);
                    EvictLocked;
                    Inc(FGeneration);
                    NotifyBmp := Stored.Bitmap;
                    UiBmp := nil;
                  end;
                end
                else if (HtmlKind = htkEmpty) and SameStr(StorePath, Path) then
                begin
                  NoteHtmlBlankLocked(Path, Stamp);
                  FreeAndNil(UiBmp);
                end
                else if SniffSoft and SameStr(StorePath, Path) then
                begin
                  NoteSniffMissLocked(Path, Stamp);
                  FreeAndNil(UiBmp);
                end
                else if HugeTiff and (not Success) and SameStr(StorePath, Path) then
                begin
                  NoteHugeTiffMissLocked(Path, Stamp);
                  FreeAndNil(UiBmp);
                end
                else if SameStr(StorePath, Path) then
                begin
                  FHtmlBlank.Remove(Path);
                  if FSniffMiss <> nil then
                    FSniffMiss.Remove(Path);
                  if FHugeMiss <> nil then
                    FHugeMiss.Remove(Path);
                  FNoThumb.AddOrSetValue(Path, Stamp);
                  FreeAndNil(UiBmp);
                end
                else
                  FreeAndNil(UiBmp);
                end;
              finally
                FLock.Leave;
              end;
              if Assigned(Ready) and Assigned(NotifyBmp) then
                Ready(StorePath, NotifyBmp);
            finally
              AtomicDecrement(FQueued);
            end;
          end);
      finally
{$IFDEF MSWINDOWS}
        if NeedCom then
          CoUninitialize;
{$ENDIF}
        FLock.Enter;
        try
          if HtmlLane then
          begin
            if FHtmlBusy > 0 then
              Dec(FHtmlBusy);
          end
          else if FBusy > 0 then
            Dec(FBusy);
        finally
          FLock.Leave;
        end;
        if HtmlLane then
          PumpHtml
        else
          PumpJobs;
      end;
    end).Start;
end;

procedure TThumbCache.RememberSlot(AOwner: TObject;
  const APaths, ANameHints: TArray<string>; ASize: Integer);
var
  Slot: TThumbFocusSlot;
  I, N: Integer;
begin
  N := Length(APaths);
  SetLength(Slot.Paths, N);
  SetLength(Slot.Hints, N);
  for I := 0 to N - 1 do
  begin
    Slot.Paths[I] := APaths[I];
    if I <= High(ANameHints) then
      Slot.Hints[I] := ANameHints[I]
    else
      Slot.Hints[I] := '';
  end;
  Slot.Size := ASize;
  FSlots.AddOrSetValue(AOwner, Slot);
  if FSlotOrder.IndexOf(AOwner) < 0 then
    FSlotOrder.Add(AOwner);
end;

procedure TThumbCache.RebuildFromSlots(AFirst: TObject);
var
  Slots: TList<TThumbFocusSlot>;
  Have: TDictionary<string, TThumbStamp>;
  Remote: TDictionary<string, Boolean>;
  Emitted: TDictionary<string, Boolean>;
  Foreign: TList<TThumbJob>;
  Slot: TThumbFocusSlot;
  Job: TThumbJob;
  Item: TCachedThumb;
  St, Cached: TThumbStamp;
  Owner: TObject;
  Path: string;
  S, I: Integer;
  Got: Boolean;
begin
  if FShuttingDown or not FEnabled or not FWorkersEnabled then
    Exit;

  Slots := TList<TThumbFocusSlot>.Create;
  Have := TDictionary<string, TThumbStamp>.Create;
  Remote := TDictionary<string, Boolean>.Create;
  try
    FLock.Enter;
    try
      if (AFirst <> nil) and FSlots.TryGetValue(AFirst, Slot) then
        Slots.Add(Slot);
      for I := 0 to FSlotOrder.Count - 1 do
      begin
        Owner := FSlotOrder[I];
        if Owner = AFirst then
          Continue;
        if FSlots.TryGetValue(Owner, Slot) then
          Slots.Add(Slot);
      end;
    finally
      FLock.Leave;
    end;

    { Метку читаем только у локальных путей слотов. Сеть на UI не трогаем:
      уже готовый кадр и FNoThumb для неё не декодируются повторно. }
    for S := 0 to Slots.Count - 1 do
    begin
      Slot := Slots[S];
      for I := 0 to High(Slot.Paths) do
      begin
        Path := Slot.Paths[I];
        if (Path = '') or Have.ContainsKey(Path) or Remote.ContainsKey(Path) then
          Continue;
        if IsRemotePath(Path) then
          Remote.Add(Path, True)
        else if ReadStamp(Path, St) then
          Have.Add(Path, St);
      end;
    end;

    Emitted := TDictionary<string, Boolean>.Create;
    Foreign := TList<TThumbJob>.Create;
    try
      FLock.Enter;
      try
        while FWait.Count > 0 do
        begin
          Job := FWait.Dequeue;
          if Assigned(Job.OnReady) then
            { Диалоги конфликта и прогресса. Это не плитка панели. }
            Foreign.Add(Job)
          else
            FPending.Remove(Job.Path);
        end;
        while FHtmlWait.Count > 0 do
        begin
          Job := FHtmlWait.Dequeue;
          if Assigned(Job.OnReady) then
            Foreign.Add(Job)
          else
            FPending.Remove(Job.Path);
        end;

        for S := 0 to Slots.Count - 1 do
        begin
          Slot := Slots[S];
          for I := 0 to High(Slot.Paths) do
          begin
            Path := Slot.Paths[I];
            if (Path = '') or Emitted.ContainsKey(Path) then
              Continue;
            Emitted.Add(Path, True);
            if FPending.ContainsKey(Path) then
              Continue;

            if Remote.ContainsKey(Path) then
            begin
              if FCache.ContainsKey(Path) or FNoThumb.ContainsKey(Path) then
                Continue;
            end
            else
            begin
              Got := Have.TryGetValue(Path, St);
              if FCache.TryGetValue(Path, Item) then
              begin
                if (not Got) or SameStamp(Item.Stamp, St) then
                  Continue;
              end
              else if FNoThumb.TryGetValue(Path, Cached) then
              begin
                if (not Got) or SameStamp(Cached, St) then
                  Continue;
                FNoThumb.Remove(Path);
              end;
            end;

            Job := Default(TThumbJob);
            Job.Path := Path;
            Job.Size := Slot.Size;
            if Job.Size < 1 then
              Job.Size := 256;
            if I <= High(Slot.Hints) then
              Job.NameHint := Slot.Hints[I];
            if Have.TryGetValue(Path, St) then
              Job.Stamp := St;
            FPending.Add(Path, True);
            EnqueueJobLocked(Job);
          end;
        end;

        for I := 0 to Foreign.Count - 1 do
          EnqueueJobLocked(Foreign[I]);
      finally
        FLock.Leave;
      end;
    finally
      Emitted.Free;
      Foreign.Free;
    end;
  finally
    Slots.Free;
    Have.Free;
    Remote.Free;
  end;

  PumpJobs;
end;

procedure TThumbCache.Focus(AOwner: TObject; const APaths, ANameHints: TArray<string>;
  ASize: Integer);
begin
  if (AOwner = nil) or FShuttingDown or not FEnabled or not FWorkersEnabled then
    Exit;
  FLock.Enter;
  try
    RememberSlot(AOwner, APaths, ANameHints, ASize);
  finally
    FLock.Leave;
  end;
  RebuildFromSlots(AOwner);
end;

procedure TThumbCache.ReleaseFocus(AOwner: TObject);
var
  Idx: Integer;
begin
  if (AOwner = nil) or (FSlots = nil) then
    Exit;
  FLock.Enter;
  try
    FSlots.Remove(AOwner);
    Idx := FSlotOrder.IndexOf(AOwner);
    if Idx >= 0 then
      FSlotOrder.Delete(Idx);
  finally
    FLock.Leave;
  end;
  RebuildFromSlots(nil);
end;

procedure TThumbCache.RequestAsync(const APath: string; ASize: Integer;
  AOnReady: TThumbReadyProc; const ANameHint: string);
var
  Item: TCachedThumb;
  Current, Cached: TThumbStamp;
  HaveStamp: Boolean;
  Job: TThumbJob;
begin
  if FShuttingDown or not FEnabled or not FWorkersEnabled or (APath = '') or
     not CanCacheFile(APath, ANameHint) then
    Exit;

  FLock.Enter;
  try
    if FPending.ContainsKey(APath) then
      Exit;
  finally
    FLock.Leave;
  end;

  HaveStamp := ReadStamp(APath, Current);

  FLock.Enter;
  try
    if FPending.ContainsKey(APath) then
      Exit;

    if FCache.TryGetValue(APath, Item) then
    begin
      { Старый кадр оставляем на экране, пока новый не готов. }
      if (not HaveStamp) or SameStamp(Item.Stamp, Current) then
        Exit;
    end
    else if FNoThumb.TryGetValue(APath, Cached) then
    begin
      { MTP/shell без FileAge: не дёргать превью на каждый кадр. }
      if (not HaveStamp) or
         (SameStamp(Cached, Current) and
          not IsPdfThumbExt(APath) and not IsSvgThumbExt(APath) and
          not IsPsdThumbExt(APath) and
          not IsMetaThumbExt(ThumbExtOf(APath, ''))) then
        Exit;
      FNoThumb.Remove(APath);
    end;

    FPending.Add(APath, True);
    Job.Path := APath;
    Job.Size := ASize;
    Job.Stamp := Current;
    Job.NameHint := ANameHint;
    Job.OnReady := AOnReady;
    EnqueueJobLocked(Job);
  finally
    FLock.Leave;
  end;

  PumpJobs;
end;

initialization
  GlobalThumbCache := TThumbCache.Create;
  {$IFDEF MSWINDOWS}
  GShellThumbCS := TCriticalSection.Create;
  GShellThumbMap := TDictionary<string, Boolean>.Create;
  {$ENDIF}

finalization
  if Assigned(GlobalThumbCache) then
  begin
    GlobalThumbCache.Shutdown;
    if GlobalThumbCache.Quiescent then
    begin
      FreeAndNil(GlobalThumbCache);
      {$IFDEF MSWINDOWS}
      FreeAndNil(GShellThumbMap);
      FreeAndNil(GShellThumbCS);
      {$ENDIF}
    end;
  end
  else
  begin
    {$IFDEF MSWINDOWS}
    FreeAndNil(GShellThumbMap);
    FreeAndNil(GShellThumbCS);
    {$ENDIF}
  end;

end.

