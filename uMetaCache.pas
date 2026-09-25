unit uMetaCache;

{
  Для плиток: размер картинки (1200×1600) и длительность медиа (00:15).
  Чтение в фоне через IPropertyStore / заголовок файла, UI не блокируется.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs;

function FormatMediaClock(ASeconds: Double): string;
function IsImageMetaExt(const AExt: string): Boolean;
function IsAudioMetaExt(const AExt: string): Boolean;
function IsVideoMetaExt(const AExt: string): Boolean;
function IsMediaMetaExt(const AExt: string): Boolean;
function ProbeMediaDuration(const APath: string): Double;
function BuildWavePeaks(const APath: string; ACount: Integer): TArray<Single>;
function ExportMediaClip(const ASrc, ADst: string; AStart, AEnd: Double;
  AVideo: Boolean; out AError: string): Boolean;
function FindFfmpeg: string;

type
  TMetaCache = class
  private
    FLock: TCriticalSection;
    FItems: TDictionary<string, string>;
    FPending: TDictionary<string, Boolean>;
    FQueue: TQueue<string>;
    FBusy: Integer;
    FGeneration: Integer;
    FShuttingDown: Boolean;
    procedure Pump;
    procedure StartJob(const APath: string);
  public
    constructor Create;
    destructor Destroy; override;
    function TryGet(const APath: string; out AText: string): Boolean;
    procedure RequestAsync(const APath: string);
    function HasWork: Boolean;
    function Generation: Integer;
    procedure Invalidate(const APath: string);
    procedure Shutdown;
  end;

var
  GlobalMetaCache: TMetaCache;

implementation

uses
  System.IOUtils, System.Math, System.StrUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj{$ENDIF};

const
  PKEY_ImageW: TPropertyKey = (fmtid: '{6444048F-4C8B-11D1-8B70-080036B11A03}'; pid: 3);
  PKEY_ImageH: TPropertyKey = (fmtid: '{6444048F-4C8B-11D1-8B70-080036B11A03}'; pid: 4);
  PKEY_VideoW: TPropertyKey = (fmtid: '{64440491-4C8B-11D1-8B70-080036B11A03}'; pid: 3);
  PKEY_VideoH: TPropertyKey = (fmtid: '{64440491-4C8B-11D1-8B70-080036B11A03}'; pid: 4);
  PKEY_Duration: TPropertyKey = (fmtid: '{64440490-4C8B-11D1-8B70-080036B11A03}'; pid: 3);
  GPS_BESTEFFORT = $40;
  MaxWorkers = 2;

function FormatMediaClock(ASeconds: Double): string;
var
  T: Integer;
begin
  if ASeconds < 0 then
    ASeconds := 0;
  T := Round(ASeconds);
  if T >= 3600 then
    Result := Format('%d:%.2d:%.2d', [T div 3600, (T div 60) mod 60, T mod 60])
  else
    Result := Format('%.2d:%.2d', [T div 60, T mod 60]);
end;


function IsImageMetaExt(const AExt: string): Boolean;
begin
  Result := MatchText(AExt, ['.jpg', '.jpeg', '.jpe', '.jfif', '.png', '.bmp',
    '.gif', '.tif', '.tiff', '.webp', '.ico', '.heic', '.heif', '.jxl', '.tga',
    '.avif', '.psd', '.psb', '.svg', '.svgz']);
end;

function IsAudioMetaExt(const AExt: string): Boolean;
begin
  Result := MatchText(AExt, ['.mp3', '.wav', '.flac', '.wma', '.aac', '.ogg',
    '.m4a', '.opus', '.mid', '.midi']);
end;

function IsVideoMetaExt(const AExt: string): Boolean;
begin
  Result := MatchText(AExt, ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm',
    '.m4v', '.mpg', '.mpeg', '.3gp', '.mts']);
end;

function IsMediaMetaExt(const AExt: string): Boolean;
begin
  Result := IsAudioMetaExt(AExt) or IsVideoMetaExt(AExt);
end;

function ReadU16BE(FS: TStream): Word;
var
  B: array[0..1] of Byte;
begin
  FS.ReadBuffer(B, 2);
  Result := (B[0] shl 8) or B[1];
end;

function ReadU32BE(FS: TStream): Cardinal;
var
  B: array[0..3] of Byte;
begin
  FS.ReadBuffer(B, 4);
  Result := (B[0] shl 24) or (B[1] shl 16) or (B[2] shl 8) or B[3];
end;

function ReadU16LE(FS: TStream): Word;
var
  B: array[0..1] of Byte;
begin
  FS.ReadBuffer(B, 2);
  Result := B[0] or (B[1] shl 8);
end;

function ReadU32LE(FS: TStream): Cardinal;
var
  B: array[0..3] of Byte;
begin
  FS.ReadBuffer(B, 4);
  Result := B[0] or (B[1] shl 8) or (B[2] shl 16) or (B[3] shl 24);
end;

function TryReadImageSize(const APath: string; out W, H: Integer): Boolean;
var
  FS: TFileStream;
  Sig: array[0..11] of Byte;
  Marker, Len: Word;
  Ext: string;
begin
  Result := False;
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < 24 then
        Exit;
      FillChar(Sig, SizeOf(Sig), 0);
      FS.ReadBuffer(Sig, Min(12, FS.Size));
      FS.Position := 0;
      if (Sig[0] = $FF) and (Sig[1] = $D8) then
      begin
        FS.Position := 2;
        while FS.Position + 4 < FS.Size do
        begin
          if FS.Read(Sig, 1) <> 1 then
            Break;
          if Sig[0] <> $FF then
            Continue;
          repeat
            if FS.Read(Sig, 1) <> 1 then
              Exit;
          until Sig[0] <> $FF;
          Marker := Sig[0];
          if Marker in [$C0, $C1, $C2, $C3, $C9, $CA, $CB] then
          begin
            ReadU16BE(FS);
            FS.Read(Sig, 1);
            H := ReadU16BE(FS);
            W := ReadU16BE(FS);
            Result := (W > 0) and (H > 0);
            Exit;
          end;
          if Marker = $DA then
            Exit;
          Len := ReadU16BE(FS);
          if Len < 2 then
            Exit;
          FS.Position := FS.Position + Len - 2;
        end;
      end
      else if (Sig[0] = $89) and (Sig[1] = Ord('P')) then
      begin
        FS.Position := 16;
        W := Integer(ReadU32BE(FS));
        H := Integer(ReadU32BE(FS));
        Result := (W > 0) and (H > 0);
      end
      else if (Sig[0] = Ord('G')) and (Sig[1] = Ord('I')) and (Sig[2] = Ord('F')) then
      begin
        FS.Position := 6;
        W := ReadU16LE(FS);
        H := ReadU16LE(FS);
        Result := (W > 0) and (H > 0);
      end
      else if (Sig[0] = Ord('B')) and (Sig[1] = Ord('M')) then
      begin
        FS.Position := 18;
        W := Integer(ReadU32LE(FS));
        H := Integer(ReadU32LE(FS));
        Result := (W > 0) and (H > 0);
      end
      else if (Sig[0] = Ord('R')) and (Sig[8] = Ord('W')) then
      begin
        FS.Position := 12;
        FS.ReadBuffer(Sig, 4);
        if (Sig[0] = Ord('V')) and (Sig[1] = Ord('P')) and (Sig[2] = Ord('8')) and
           (Sig[3] = Ord('X')) then
        begin
          FS.Position := 24;
          W := Integer(ReadU32LE(FS) and $FFFFFF) + 1;
          H := Integer(ReadU32LE(FS) and $FFFFFF) + 1;
          Result := (W > 0) and (H > 0);
        end;
      end;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

{$IFDEF MSWINDOWS}
type
  IPropertyStore = interface(IUnknown)
    ['{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}']
    function GetCount(out cProps: DWORD): HResult; stdcall;
    function GetAt(iProp: DWORD; out pkey: TPropertyKey): HResult; stdcall;
    function GetValue(const key: TPropertyKey; out pv: TPropVariant): HResult; stdcall;
    function SetValue(const key: TPropertyKey; const propvar: TPropVariant): HResult; stdcall;
    function Commit: HResult; stdcall;
  end;

function SHGetPropertyStoreFromParsingName(pszPath: PWideChar; pbc: Pointer;
  flags: DWORD; const riid: TGUID; out ppv: IPropertyStore): HResult; stdcall;
  external 'shell32.dll' name 'SHGetPropertyStoreFromParsingName';

function PropUInt(Store: IPropertyStore; const Key: TPropertyKey; out V: UInt64): Boolean;
var
  Pv: TPropVariant;
begin
  Result := False;
  V := 0;
  FillChar(Pv, SizeOf(Pv), 0);
  if Failed(Store.GetValue(Key, Pv)) then
    Exit;
  try
    case Pv.vt of
      VT_UI4, VT_UINT:
        V := Pv.ulVal;
      VT_I4, VT_INT:
        if Pv.lVal > 0 then
          V := Pv.lVal;
      VT_UI8:
        V := Pv.uhVal.QuadPart;
      VT_I8:
        if Pv.hVal.QuadPart > 0 then
          V := UInt64(Pv.hVal.QuadPart);
      VT_R8:
        if Pv.dblVal > 0 then
          V := Round(Pv.dblVal);
    else
      Exit;
    end;
    Result := True;
  finally
    PropVariantClear(Pv);
  end;
end;

function ProbeMediaDuration(const APath: string): Double;
{$IFDEF MSWINDOWS}
var
  Store: IPropertyStore;
  Dur: UInt64;
  FS: TFileStream;
  Id: array[0..3] of AnsiChar;
  Sz, Rate, Avg, BlockAlign, Bits, Ch, DataSz: Integer;
  Fmt: Word;
{$ENDIF}
begin
  Result := 0;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
{$IFDEF MSWINDOWS}
  Store := nil;
  if Succeeded(SHGetPropertyStoreFromParsingName(PChar(APath), nil, GPS_BESTEFFORT,
    IPropertyStore, Store)) and (Store <> nil) then
  begin
    if PropUInt(Store, PKEY_Duration, Dur) and (Dur > 0) then
      Exit(Dur / 1.0e7);
  end;
  if not SameText(ExtractFileExt(APath), '.wav') then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < 44 then
        Exit;
      FS.ReadBuffer(Id, 4);
      if not ((Id[0] = 'R') and (Id[1] = 'I') and (Id[2] = 'F') and (Id[3] = 'F')) then
        Exit;
      FS.ReadBuffer(Sz, 4);
      FS.ReadBuffer(Id, 4);
      if not ((Id[0] = 'W') and (Id[1] = 'A') and (Id[2] = 'V') and (Id[3] = 'E')) then
        Exit;
      Rate := 0;
      Ch := 0;
      Bits := 0;
      DataSz := 0;
      while FS.Position + 8 <= FS.Size do
      begin
        FS.ReadBuffer(Id, 4);
        FS.ReadBuffer(Sz, 4);
        if Sz < 0 then
          Break;
        if (Id[0] = 'f') and (Id[1] = 'm') and (Id[2] = 't') then
        begin
          FS.ReadBuffer(Fmt, 2);
          FS.ReadBuffer(Ch, 2);
          FS.ReadBuffer(Rate, 4);
          FS.ReadBuffer(Avg, 4);
          FS.ReadBuffer(BlockAlign, 2);
          FS.ReadBuffer(Bits, 2);
          if Sz > 16 then
            FS.Position := FS.Position + Sz - 16;
        end
        else if (Id[0] = 'd') and (Id[1] = 'a') and (Id[2] = 't') and (Id[3] = 'a') then
        begin
          DataSz := Sz;
          Break;
        end
        else
          FS.Position := Min(FS.Size, FS.Position + Sz);
      end;
      if (Rate > 0) and (Ch > 0) and (Bits > 0) and (DataSz > 0) then
        Result := DataSz / (Rate * Ch * (Bits / 8.0));
    finally
      FS.Free;
    end;
  except
  end;
{$ENDIF}
end;

function ShellMetaText(const APath: string): string;
var
  Store: IPropertyStore;
  W, H, Dur: UInt64;
  Ext: string;
begin
  Result := '';
  Store := nil;
  if Failed(SHGetPropertyStoreFromParsingName(PChar(APath), nil, GPS_BESTEFFORT,
    IPropertyStore, Store)) or (Store = nil) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if IsImageMetaExt(Ext) then
  begin
    if PropUInt(Store, PKEY_ImageW, W) and PropUInt(Store, PKEY_ImageH, H) and
       (W > 0) and (H > 0) then
      Result := Format('%dх%d', [W, H]);
  end
  else if IsMediaMetaExt(Ext) then
  begin
    if PropUInt(Store, PKEY_Duration, Dur) and (Dur > 0) then
      Result := FormatMediaClock(Dur / 1.0e7);
    if (Result = '') and IsVideoMetaExt(Ext) then
      if PropUInt(Store, PKEY_VideoW, W) and PropUInt(Store, PKEY_VideoH, H) and
         (W > 0) and (H > 0) then
        Result := Format('%dх%d', [W, H]);
  end;
end;
{$ENDIF}

function ReadMetaText(const APath: string): string;
var
  Ext: string;
  W, H: Integer;
begin
  Result := '';
  Ext := LowerCase(ExtractFileExt(APath));
  if IsImageMetaExt(Ext) then
  begin
    if TryReadImageSize(APath, W, H) then
      Exit(Format('%dх%d', [W, H]));
{$IFDEF MSWINDOWS}
    Result := ShellMetaText(APath);
{$ENDIF}
  end
  else if IsMediaMetaExt(Ext) then
  begin
{$IFDEF MSWINDOWS}
    Result := ShellMetaText(APath);
{$ENDIF}
  end;
end;

{$IFDEF MSWINDOWS}
const
  MF_VERSION = $20070;
  MFSTARTUP_LITE = 1;
  MF_SOURCE_READER_FIRST_AUDIO = $FFFFFFFD;
  MF_SOURCE_READER_MEDIASOURCE = $FFFFFFFF;
  MF_SOURCE_READERF_ENDOFSTREAM = $2;
  MFMediaType_Audio: TGUID = '{73647561-0000-0010-8000-00AA00389B71}';
  MFAudioFormat_PCM: TGUID = '{00000001-0000-0010-8000-00AA00389B71}';
  MF_MT_MAJOR_TYPE: TGUID = '{48EBA18E-F8C9-4687-BF11-0A74C9F96A8F}';
  MF_MT_SUBTYPE: TGUID = '{F7E34C9A-42E8-4714-B74B-CB29D72C35E5}';
  MF_MT_AUDIO_NUM_CHANNELS: TGUID = '{37E48BF0-EF61-4EE3-B485-7D85FDCD2C4E}';
  MF_MT_AUDIO_SAMPLES_PER_SECOND: TGUID = '{5FAEEAE7-0290-4C31-9E8A-C534F68D9DBA}';
  MF_MT_AUDIO_BITS_PER_SAMPLE: TGUID = '{F2DEB57F-40FA-4764-AA33-ED4F2D1FF669}';
  MF_MT_AUDIO_BLOCK_ALIGNMENT: TGUID = '{322DE230-9EEB-43BD-AB7A-FF412251541D}';
  MF_MT_AUDIO_AVG_BYTES_PER_SECOND: TGUID = '{1AAB75C7-168E-4E75-ACEE-3956E84BE915}';
  MF_PD_DURATION: TGUID = '{6C990D33-BB8E-477A-8598-0D5D96FCD88A}';
  GUID_TIME_NONE: TGUID = '{00000000-0000-0000-0000-000000000000}';

type
  IMFAttributes = interface(IUnknown)
    ['{2CD2D921-C447-44A7-A13C-4ADABFC247E3}']
    function GetItem(const guidKey: TGUID; pValue: Pointer): HResult; stdcall;
    function GetItemType(const guidKey: TGUID; out pType: DWORD): HResult; stdcall;
    function CompareItem(const guidKey: TGUID; const Value: TPropVariant;
      out pbResult: BOOL): HResult; stdcall;
    function Compare(pTheirs: IMFAttributes; MatchType: DWORD;
      out pbResult: BOOL): HResult; stdcall;
    function GetUINT32(const guidKey: TGUID; out punValue: UINT32): HResult; stdcall;
    function GetUINT64(const guidKey: TGUID; out punValue: UInt64): HResult; stdcall;
    function GetDouble(const guidKey: TGUID; out pfValue: Double): HResult; stdcall;
    function GetGUID(const guidKey: TGUID; out pguidValue: TGUID): HResult; stdcall;
    function GetStringLength(const guidKey: TGUID; out pcchLength: UINT32): HResult; stdcall;
    function GetString(const guidKey: TGUID; pwszValue: PWideChar; cchBufSize: UINT32;
      pcchLength: PUINT32): HResult; stdcall;
    function GetAllocatedString(const guidKey: TGUID; out ppwszValue: PWideChar;
      out pcchLength: UINT32): HResult; stdcall;
    function GetBlobSize(const guidKey: TGUID; out pcbBlobSize: UINT32): HResult; stdcall;
    function GetBlob(const guidKey: TGUID; pBuf: Pointer; cbBufSize: UINT32;
      pcbBlobSize: PUINT32): HResult; stdcall;
    function GetAllocatedBlob(const guidKey: TGUID; out ppBuf: Pointer;
      out pcbSize: UINT32): HResult; stdcall;
    function GetUnknown(const guidKey: TGUID; const riid: TGUID; out ppv): HResult; stdcall;
    function SetItem(const guidKey: TGUID; const Value: TPropVariant): HResult; stdcall;
    function DeleteItem(const guidKey: TGUID): HResult; stdcall;
    function DeleteAllItems: HResult; stdcall;
    function SetUINT32(const guidKey: TGUID; unValue: UINT32): HResult; stdcall;
    function SetUINT64(const guidKey: TGUID; unValue: UInt64): HResult; stdcall;
    function SetDouble(const guidKey: TGUID; fValue: Double): HResult; stdcall;
    function SetGUID(const guidKey: TGUID; const guidValue: TGUID): HResult; stdcall;
    function SetString(const guidKey: TGUID; wszValue: PWideChar): HResult; stdcall;
    function SetBlob(const guidKey: TGUID; pBuf: Pointer; cbBufSize: UINT32): HResult; stdcall;
    function SetUnknown(const guidKey: TGUID; pUnknown: IUnknown): HResult; stdcall;
    function LockStore: HResult; stdcall;
    function UnlockStore: HResult; stdcall;
    function GetCount(out pcItems: UINT32): HResult; stdcall;
    function GetItemByIndex(unIndex: UINT32; out pguidKey: TGUID;
      pValue: Pointer): HResult; stdcall;
    function CopyAllItems(pDest: IMFAttributes): HResult; stdcall;
  end;

  IMFMediaType = interface(IMFAttributes)
    ['{44AE0FA8-EA31-4109-8D2E-4CAE4997C555}']
    function GetMajorType(out pguidMajorType: TGUID): HResult; stdcall;
    function IsCompressedFormat(out pfCompressed: BOOL): HResult; stdcall;
    function IsEqual(pIMediaType: IMFMediaType; out pdwFlags: DWORD): HResult; stdcall;
    function GetRepresentation(const guidRepresentation: TGUID;
      out ppvRepresentation: Pointer): HResult; stdcall;
    function FreeRepresentation(const guidRepresentation: TGUID;
      pvRepresentation: Pointer): HResult; stdcall;
  end;

  IMFMediaBuffer = interface(IUnknown)
    ['{045FA593-8799-42B8-BC8D-8968C6453507}']
    function Lock(out ppbBuffer: Pointer; pcbMaxLength: PDWORD;
      out pcbCurrentLength: DWORD): HResult; stdcall;
    function Unlock: HResult; stdcall;
    function GetCurrentLength(out pcbCurrentLength: DWORD): HResult; stdcall;
    function SetCurrentLength(cbCurrentLength: DWORD): HResult; stdcall;
    function GetMaxLength(out pcbMaxLength: DWORD): HResult; stdcall;
  end;

  IMFSample = interface(IMFAttributes)
    ['{C40A00F2-B93A-4D80-AE16-5A52D5DA7B6A}']
    function GetSampleFlags(out pdwSampleFlags: DWORD): HResult; stdcall;
    function SetSampleFlags(dwSampleFlags: DWORD): HResult; stdcall;
    function GetSampleTime(out phnsSampleTime: Int64): HResult; stdcall;
    function SetSampleTime(hnsSampleTime: Int64): HResult; stdcall;
    function GetSampleDuration(out phnsSampleDuration: Int64): HResult; stdcall;
    function SetSampleDuration(hnsSampleDuration: Int64): HResult; stdcall;
    function GetBufferCount(out pdwBufferCount: DWORD): HResult; stdcall;
    function GetBufferByIndex(dwIndex: DWORD; out ppBuffer: IMFMediaBuffer): HResult; stdcall;
    function ConvertToContiguousBuffer(out ppBuffer: IMFMediaBuffer): HResult; stdcall;
    function AddBuffer(pBuffer: IMFMediaBuffer): HResult; stdcall;
    function RemoveBufferByIndex(dwIndex: DWORD): HResult; stdcall;
    function RemoveAllBuffers: HResult; stdcall;
    function GetTotalLength(out pcbTotalLength: DWORD): HResult; stdcall;
    function CopyToBuffer(pBuffer: IMFMediaBuffer): HResult; stdcall;
  end;

  IMFSourceReader = interface(IUnknown)
    ['{70AE66F2-C809-4E4F-8586-DAC6547EBF43}']
    function GetStreamSelection(dwStreamIndex: DWORD; out pfSelected: BOOL): HResult; stdcall;
    function SetStreamSelection(dwStreamIndex: DWORD; fSelected: BOOL): HResult; stdcall;
    function GetNativeMediaType(dwStreamIndex, dwMediaTypeIndex: DWORD;
      out ppMediaType: IMFMediaType): HResult; stdcall;
    function GetCurrentMediaType(dwStreamIndex: DWORD;
      out ppMediaType: IMFMediaType): HResult; stdcall;
    function SetCurrentMediaType(dwStreamIndex: DWORD; pdwReserved: PDWORD;
      pMediaType: IMFMediaType): HResult; stdcall;
    function SetCurrentPosition(const guidTimeFormat: TGUID;
      const varPosition: TPropVariant): HResult; stdcall;
    function ReadSample(dwStreamIndex, dwControlFlags: DWORD;
      out pdwActualStreamIndex, pdwStreamFlags: DWORD; out pllTimestamp: Int64;
      out ppSample: IMFSample): HResult; stdcall;
    function Flush(dwStreamIndex: DWORD): HResult; stdcall;
    function GetServiceForStream(dwStreamIndex: DWORD; const guidService, riid: TGUID;
      out ppvObject): HResult; stdcall;
    function GetPresentationAttribute(dwStreamIndex: DWORD; const guidAttribute: TGUID;
      out pvarAttribute: TPropVariant): HResult; stdcall;
  end;

  TMFStartup = function(Version: ULONG; dwFlags: DWORD): HResult; stdcall;
  TMFCreateMediaType = function(out ppMFType: IMFMediaType): HResult; stdcall;
  TMFCreateSourceReaderFromURL = function(pwszURL: PWideChar; pAttributes: Pointer;
    out ppSourceReader: IMFSourceReader): HResult; stdcall;

var
  GMfRead: HMODULE = 0;
  GMfPlat2: HMODULE = 0;
  GMfReadOk: Boolean = False;
  MFStartup2: TMFStartup = nil;
  MFCreateMediaType: TMFCreateMediaType = nil;
  MFCreateSourceReaderFromURL: TMFCreateSourceReaderFromURL = nil;

function EnsureMfRead: Boolean;
begin
  Result := GMfReadOk;
  if Result then
    Exit;
  GMfPlat2 := LoadLibrary('mfplat.dll');
  GMfRead := LoadLibrary('mfreadwrite.dll');
  if (GMfPlat2 = 0) or (GMfRead = 0) then
    Exit;
  @MFStartup2 := GetProcAddress(GMfPlat2, 'MFStartup');
  @MFCreateMediaType := GetProcAddress(GMfPlat2, 'MFCreateMediaType');
  @MFCreateSourceReaderFromURL := GetProcAddress(GMfRead, 'MFCreateSourceReaderFromURL');
  if not Assigned(MFStartup2) or not Assigned(MFCreateMediaType) or
     not Assigned(MFCreateSourceReaderFromURL) then
    Exit;
  if Failed(MFStartup2(MF_VERSION, MFSTARTUP_LITE)) then
    if Failed(MFStartup2(MF_VERSION, 0)) then
      Exit;
  GMfReadOk := True;
  Result := True;
end;

function OpenPcmReader(const APath: string; out Reader: IMFSourceReader;
  out ARate, ACh, ABits: Integer; AHighQuality: Boolean = False): Boolean;
var
  Url: string;
  Mt: IMFMediaType;
  Block: UINT32;
begin
  Result := False;
  Reader := nil;
  ARate := 22050;
  ACh := 1;
  ABits := 16;
  if not EnsureMfRead then
    Exit;
  Url := APath;
  if (Pos('#', Url) > 0) or (Pos('?', Url) > 0) then
    Url := 'file:///' + StringReplace(Url, '\', '/', [rfReplaceAll]);
  if Failed(MFCreateSourceReaderFromURL(PChar(Url), nil, Reader)) or (Reader = nil) then
    Exit;
  Reader.SetStreamSelection($FFFFFFFE, False);
  Reader.SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO, True);
  if AHighQuality then
  begin
    ARate := 44100;
    ACh := 2;
    if Succeeded(Reader.GetNativeMediaType(MF_SOURCE_READER_FIRST_AUDIO, 0, Mt)) and Assigned(Mt) then
    begin
      if Succeeded(Mt.GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, Block)) and (Block >= 8000) then
        ARate := Integer(Block);
      if Succeeded(Mt.GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, Block)) and (Block > 0) and (Block <= 8) then
        ACh := Integer(Block);
      Mt := nil;
    end;
  end;
  if Failed(MFCreateMediaType(Mt)) then
    Exit;
  Mt.SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  Mt.SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  Mt.SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  if AHighQuality then
  begin
    ABits := 16;
    Mt.SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, ACh);
    Mt.SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, ARate);
    Mt.SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, ACh * 2);
    Mt.SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, ARate * ACh * 2);
  end
  else
  begin
    Mt.SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
    Mt.SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 22050);
    Mt.SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 2);
    Mt.SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 44100);
  end;
  if Failed(Reader.SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO, nil, Mt)) then
  begin
    Reader := nil;
    Exit;
  end;
  Mt := nil;
  if Succeeded(Reader.GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO, Mt)) and
     Assigned(Mt) then
  begin
    if Succeeded(Mt.GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, Block)) and (Block > 0) then
      ARate := Integer(Block);
    if Succeeded(Mt.GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, Block)) and (Block > 0) then
      ACh := Integer(Block);
    if Succeeded(Mt.GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, Block)) and (Block > 0) then
      ABits := Integer(Block);
  end;
  Result := True;
end;

function ReaderDurationSec(Reader: IMFSourceReader): Double;
var
  Pv: TPropVariant;
begin
  Result := 0;
  FillChar(Pv, SizeOf(Pv), 0);
  if Failed(Reader.GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE,
    MF_PD_DURATION, Pv)) then
    Exit;
  try
    if Pv.vt = VT_UI8 then
      Result := Pv.uhVal.QuadPart / 1.0e7
    else if Pv.vt = VT_I8 then
      Result := Pv.hVal.QuadPart / 1.0e7;
  finally
    PropVariantClear(Pv);
  end;
end;

function SeekReader(Reader: IMFSourceReader; ASec: Double): Boolean;
var
  Pv: TPropVariant;
begin
  FillChar(Pv, SizeOf(Pv), 0);
  Pv.vt := VT_I8;
  Pv.hVal.QuadPart := Round(Max(0, ASec) * 1.0e7);
  Result := Succeeded(Reader.SetCurrentPosition(GUID_TIME_NONE, Pv));
end;
{$ENDIF}

procedure NormalizePeaks(var A: TArray<Single>);
var
  I: Integer;
  M: Single;
begin
  M := 0;
  for I := 0 to High(A) do
    if A[I] > M then
      M := A[I];
  if M < 0.0001 then
    Exit;
  for I := 0 to High(A) do
    A[I] := 0.08 + 0.92 * Power(A[I] / M, 0.55);
end;

function BuildWavePeaks(const APath: string; ACount: Integer): TArray<Single>;
var
  I: Integer;
{$IFDEF MSWINDOWS}
  NeedCo: Boolean;
  Reader: IMFSourceReader;
  Sample: IMFSample;
  Buf: IMFMediaBuffer;
  Data: Pointer;
  Bytes, Flags, StreamIdx: DWORD;
  Ts: Int64;
  Dur, T: Double;
  N, Rate, Ch, Bits, V: Integer;
  P: PSmallInt;
  Peak: Single;
{$ENDIF}
begin
  if ACount < 8 then
    ACount := 8;
  if ACount > 240 then
    ACount := 240;
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    Result[I] := 0.1;
{$IFDEF MSWINDOWS}
  NeedCo := Succeeded(CoInitializeEx(nil, COINIT_MULTITHREADED));
  try
    if not OpenPcmReader(APath, Reader, Rate, Ch, Bits) then
      Exit;
    Dur := ReaderDurationSec(Reader);
    if Dur <= 0 then
      Dur := 1;
    while True do
    begin
      Sample := nil;
      if Failed(Reader.ReadSample(MF_SOURCE_READER_FIRST_AUDIO, 0, StreamIdx,
        Flags, Ts, Sample)) then
        Break;
      if (Flags and MF_SOURCE_READERF_ENDOFSTREAM) <> 0 then
        Break;
      if Sample = nil then
        Continue;
      T := Ts / 1.0e7;
      I := EnsureRange(Trunc(T / Dur * ACount), 0, ACount - 1);
      if Failed(Sample.ConvertToContiguousBuffer(Buf)) then
        Continue;
      if Failed(Buf.Lock(Data, nil, Bytes)) then
        Continue;
      try
        Peak := Result[I];
        N := Integer(Bytes) div 2;
        P := Data;
        while N > 0 do
        begin
          V := Abs(P^);
          if V / 32768.0 > Peak then
            Peak := V / 32768.0;
          Inc(P);
          Dec(N);
        end;
        Result[I] := Peak;
      finally
        Buf.Unlock;
      end;
      Buf := nil;
      Sample := nil;
    end;
    Reader := nil;
    NormalizePeaks(Result);
  finally
    if NeedCo then
      CoUninitialize;
  end;
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
function FindFfmpeg: string;
var
  Dir, P, Part: string;
  I: Integer;
  Cands: TArray<string>;
  C: string;
begin
  Result := '';
  Dir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Cands := [
    Dir + 'ffmpeg.exe',
    Dir + 'ffmpeg\ffmpeg.exe',
    Dir + 'ffmpeg\bin\ffmpeg.exe',
    Dir + 'bin\ffmpeg.exe',
    IncludeTrailingPathDelimiter(GetCurrentDir) + 'ffmpeg.exe',
    IncludeTrailingPathDelimiter(GetCurrentDir) + 'ffmpeg\bin\ffmpeg.exe',
    'C:\ffmpeg\bin\ffmpeg.exe',
    'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
    IncludeTrailingPathDelimiter(GetEnvironmentVariable('ProgramData')) + 'chocolatey\bin\ffmpeg.exe'
  ];
  for C in Cands do
    if (C <> '') and FileExists(C) then
      Exit(C);
  P := GetEnvironmentVariable('PATH');
  while P <> '' do
  begin
    I := Pos(';', P);
    if I = 0 then
    begin
      Part := P;
      P := '';
    end
    else
    begin
      Part := Copy(P, 1, I - 1);
      Delete(P, 1, I);
    end;
    Part := IncludeTrailingPathDelimiter(Trim(Part));
    if (Part <> '\') and (Part <> '') and FileExists(Part + 'ffmpeg.exe') then
      Exit(Part + 'ffmpeg.exe');
  end;
end;

function RunHidden(const AExe, AParams: string): Boolean;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
  Code: DWORD;
begin
  Result := False;
  FillChar(SI, SizeOf(SI), 0);
  FillChar(PI, SizeOf(PI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  Cmd := '"' + AExe + '" ' + AParams;
  UniqueString(Cmd);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
    Exit;
  WaitForSingleObject(PI.hProcess, 300000);
  Code := 1;
  GetExitCodeProcess(PI.hProcess, Code);
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  Result := Code = 0;
end;

function WriteWavHeader(S: TStream; DataBytes, Rate, Ch, Bits: Integer): Integer;
var
  Block, Bps: Integer;
  procedure WStr(const A: AnsiString);
  begin
    S.WriteBuffer(A[1], Length(A));
  end;
  procedure W32(V: Cardinal);
  begin
    S.WriteBuffer(V, 4);
  end;
  procedure W16(V: Word);
  begin
    S.WriteBuffer(V, 2);
  end;
begin
  Block := Max(1, Ch * (Bits div 8));
  Bps := Rate * Block;
  WStr('RIFF');
  W32(36 + Cardinal(DataBytes));
  WStr('WAVE');
  WStr('fmt ');
  W32(16);
  W16(1);
  W16(Ch);
  W32(Rate);
  W32(Bps);
  W16(Block);
  W16(Bits);
  WStr('data');
  W32(Cardinal(DataBytes));
  Result := DataBytes;
end;

function WavLosslessClip(const ASrc, ADst: string; AStart, AEnd: Double;
  out AError: string): Boolean;
var
  InF, OutF: TFileStream;
  Id: array[0..3] of AnsiChar;
  ChunkSz, Rate, Avg, Align, DataSz, Bits, Ch, Extra: Integer;
  Fmt: Word;
  Header: TMemoryStream;
  Bps: Double;
  Off0, Off1, Keep, Left: Int64;
  Buf: array[0..8191] of Byte;
  N: Integer;
  RiffSize: Integer;
  B: Byte;
begin
  Result := False;
  AError := '';
  if not SameText(ExtractFileExt(ASrc), '.wav') then
    Exit;
  InF := nil;
  OutF := nil;
  Header := TMemoryStream.Create;
  try
    InF := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyNone);
    if InF.Size < 44 then
    begin
      AError := 'короткий wav';
      Exit;
    end;
    InF.ReadBuffer(Id, 4);
    if (Id[0] <> 'R') or (Id[1] <> 'I') or (Id[2] <> 'F') or (Id[3] <> 'F') then
      Exit;
    InF.ReadBuffer(ChunkSz, 4);
    InF.ReadBuffer(Id, 4);
    if (Id[0] <> 'W') or (Id[1] <> 'A') or (Id[2] <> 'V') or (Id[3] <> 'E') then
      Exit;
    Rate := 0;
    Ch := 0;
    Bits := 0;
    DataSz := 0;
    Align := 1;
    B := Ord('R'); Header.WriteBuffer(B, 1);
    B := Ord('I'); Header.WriteBuffer(B, 1);
    B := Ord('F'); Header.WriteBuffer(B, 1);
    B := Ord('F'); Header.WriteBuffer(B, 1);
    RiffSize := 0;
    Header.WriteBuffer(RiffSize, 4);
    B := Ord('W'); Header.WriteBuffer(B, 1);
    B := Ord('A'); Header.WriteBuffer(B, 1);
    B := Ord('V'); Header.WriteBuffer(B, 1);
    B := Ord('E'); Header.WriteBuffer(B, 1);
    while InF.Position + 8 <= InF.Size do
    begin
      InF.ReadBuffer(Id, 4);
      InF.ReadBuffer(ChunkSz, 4);
      if (Id[0] = 'f') and (Id[1] = 'm') and (Id[2] = 't') then
      begin
        Header.WriteBuffer(Id, 4);
        Header.WriteBuffer(ChunkSz, 4);
        if ChunkSz < 16 then
          Exit;
        InF.ReadBuffer(Fmt, 2);
        InF.ReadBuffer(Ch, 2);
        InF.ReadBuffer(Rate, 4);
        InF.ReadBuffer(Avg, 4);
        InF.ReadBuffer(Align, 2);
        InF.ReadBuffer(Bits, 2);
        Header.WriteBuffer(Fmt, 2);
        Header.WriteBuffer(Ch, 2);
        Header.WriteBuffer(Rate, 4);
        Header.WriteBuffer(Avg, 4);
        Header.WriteBuffer(Align, 2);
        Header.WriteBuffer(Bits, 2);
        Extra := ChunkSz - 16;
        while Extra > 0 do
        begin
          N := Extra;
          if N > SizeOf(Buf) then
            N := SizeOf(Buf);
          InF.ReadBuffer(Buf[0], N);
          Header.WriteBuffer(Buf[0], N);
          Dec(Extra, N);
        end;
      end
      else if (Id[0] = 'd') and (Id[1] = 'a') and (Id[2] = 't') and (Id[3] = 'a') then
      begin
        DataSz := ChunkSz;
        Break;
      end
      else
      begin
        Header.WriteBuffer(Id, 4);
        Header.WriteBuffer(ChunkSz, 4);
        Extra := ChunkSz;
        while Extra > 0 do
        begin
          N := Extra;
          if N > SizeOf(Buf) then
            N := SizeOf(Buf);
          if InF.Position + N > InF.Size then
            Break;
          InF.ReadBuffer(Buf[0], N);
          Header.WriteBuffer(Buf[0], N);
          Dec(Extra, N);
        end;
      end;
    end;
    if (Rate <= 0) or (Ch <= 0) or (Bits <= 0) or (DataSz <= 0) then
    begin
      AError := 'битый wav';
      Exit;
    end;
    if Align < 1 then
      Align := Max(1, Ch * Max(1, Bits div 8));
    Bps := Rate * 1.0 * Align;
    Off0 := Round(Max(0, AStart) * Bps);
    Off1 := Round(Max(AStart + 0.02, AEnd) * Bps);
    Off0 := Off0 - (Off0 mod Align);
    Off1 := Off1 - (Off1 mod Align);
    if Off0 < 0 then
      Off0 := 0;
    if Off1 > DataSz then
      Off1 := DataSz;
    if Off1 <= Off0 then
      Off1 := Min(Int64(DataSz), Off0 + Align);
    Keep := Off1 - Off0;
    OutF := TFileStream.Create(ADst, fmCreate);
    Header.Position := 0;
    OutF.CopyFrom(Header, Header.Size);
    B := Ord('d'); OutF.WriteBuffer(B, 1);
    B := Ord('a'); OutF.WriteBuffer(B, 1);
    B := Ord('t'); OutF.WriteBuffer(B, 1);
    B := Ord('a'); OutF.WriteBuffer(B, 1);
    N := Integer(Keep);
    OutF.WriteBuffer(N, 4);
    InF.Position := InF.Position + Off0;
    Left := Keep;
    while Left > 0 do
    begin
      N := Integer(Min(Left, SizeOf(Buf)));
      InF.ReadBuffer(Buf[0], N);
      OutF.WriteBuffer(Buf[0], N);
      Dec(Left, N);
    end;
    OutF.Position := 4;
    N := Integer(OutF.Size - 8);
    OutF.WriteBuffer(N, 4);
    Result := Keep > 0;
  finally
    Header.Free;
    InF.Free;
    OutF.Free;
  end;
end;

function MfWavClip(const ASrc, ADst: string; AStart, AEnd: Double;
  out AError: string): Boolean;
var
  NeedCo: Boolean;
  Reader: IMFSourceReader;
  Sample: IMFSample;
  Buf: IMFMediaBuffer;
  Data: Pointer;
  Bytes, Flags, StreamIdx: DWORD;
  Ts: Int64;
  Rate, Ch, Bits, Block: Integer;
  FS: TFileStream;
  DataSize, SkipLeft, KeepLeft, Take: Int64;
begin
  Result := False;
  AError := '';
  NeedCo := CoInitializeEx(nil, COINIT_MULTITHREADED) = S_OK;
  FS := nil;
  try
    if not OpenPcmReader(ASrc, Reader, Rate, Ch, Bits, True) then
    begin
      AError := 'нет декодера аудио';
      Exit;
    end;
    if AEnd <= AStart then
      AEnd := AStart + 0.2;
    if Rate < 1000 then
      Rate := 44100;
    if Ch < 1 then
      Ch := 2;
    if Bits < 8 then
      Bits := 16;
    Block := Ch * (Bits div 8);
    if Block < 1 then
      Block := 2;
    SeekReader(Reader, AStart);
    SkipLeft := 0;
    KeepLeft := Round((AEnd - AStart) * Rate) * Int64(Block);
    if KeepLeft < Block then
      KeepLeft := Block;
    FS := TFileStream.Create(ADst, fmCreate);
    WriteWavHeader(FS, 0, Rate, Ch, Bits);
    DataSize := 0;
    while KeepLeft > 0 do
    begin
      Sample := nil;
      if Failed(Reader.ReadSample(MF_SOURCE_READER_FIRST_AUDIO, 0, StreamIdx,
        Flags, Ts, Sample)) then
        Break;
      if (Flags and MF_SOURCE_READERF_ENDOFSTREAM) <> 0 then
        Break;
      if Sample = nil then
        Continue;
      if Failed(Sample.ConvertToContiguousBuffer(Buf)) then
        Continue;
      if Failed(Buf.Lock(Data, nil, Bytes)) or (Bytes = 0) then
        Continue;
      try
        if SkipLeft > 0 then
        begin
          if SkipLeft >= Bytes then
          begin
            Dec(SkipLeft, Bytes);
            Continue;
          end;
          Inc(PByte(Data), SkipLeft);
          Dec(Bytes, DWORD(SkipLeft));
          SkipLeft := 0;
        end;
        Take := Bytes;
        if Take > KeepLeft then
          Take := KeepLeft;
        FS.WriteBuffer(Data^, Take);
        Inc(DataSize, Take);
        Dec(KeepLeft, Take);
      finally
        Buf.Unlock;
      end;
      Buf := nil;
      Sample := nil;
    end;
    FS.Position := 0;
    WriteWavHeader(FS, DataSize, Rate, Ch, Bits);
    Result := DataSize > 0;
    if not Result then
      AError := 'пустой фрагмент';
  finally
    FS.Free;
    Reader := nil;
    if NeedCo then
      CoUninitialize;
  end;
end;

function FfNum(V: Double): string;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  Result := FormatFloat('0.000', V, FS);
end;

function FfmpegClip(const ASrc, ADst: string; AStart, AEnd: Double): Boolean;
var
  Exe, Ss, Td, Params, ExtD, ExtS: string;
  Dur: Double;
  IsVid: Boolean;
begin
  Result := False;
  Exe := FindFfmpeg;
  if Exe = '' then
    Exit;
  Dur := Max(0.05, AEnd - AStart);
  Ss := FfNum(Max(0, AStart));
  Td := FfNum(Dur);
  ExtD := LowerCase(ExtractFileExt(ADst));
  ExtS := LowerCase(ExtractFileExt(ASrc));
  IsVid := MatchText(ExtS, ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.webm', '.m4v',
    '.mpg', '.mpeg', '.3gp', '.mts']) or MatchText(ExtD, ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v']);

  { 1) stream copy — тот же кодек/контейнер }
  Params := Format(
    '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -c copy -map 0 -avoid_negative_ts make_zero "%s"',
    [Ss, ASrc, Td, ADst]);
  Result := RunHidden(Exe, Params) and FileExists(ADst) and (TFile.GetSize(ADst) > 0);
  if Result then
    Exit;
  if FileExists(ADst) then
  try
    TFile.Delete(ADst);
  except
  end;

  if not IsVid then
  begin
    { Аудио: перекодировать в целевой формат }
    if ExtD = '.wav' then
      Params := Format(
        '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -vn -acodec pcm_s16le -ar 44100 -ac 2 "%s"',
        [Ss, ASrc, Td, ADst])
    else if ExtD = '.mp3' then
      Params := Format(
        '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -vn -acodec libmp3lame -q:a 2 "%s"',
        [Ss, ASrc, Td, ADst])
    else if (ExtD = '.m4a') or (ExtD = '.aac') then
      Params := Format(
        '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -vn -acodec aac -b:a 192k "%s"',
        [Ss, ASrc, Td, ADst])
    else if ExtD = '.ogg' then
      Params := Format(
        '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -vn -acodec libvorbis -q:a 5 "%s"',
        [Ss, ASrc, Td, ADst])
    else if ExtD = '.flac' then
      Params := Format(
        '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -vn -acodec flac "%s"',
        [Ss, ASrc, Td, ADst])
    else
      Params := Format(
        '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -vn -acodec aac -b:a 192k "%s"',
        [Ss, ASrc, Td, ADst]);
    Result := RunHidden(Exe, Params) and FileExists(ADst) and (TFile.GetSize(ADst) > 0);
    Exit;
  end;

  { Видео: re-encode }
  Params := Format(
    '-nostdin -hide_banner -loglevel error -y -ss %s -i "%s" -t %s -c:v libx264 -preset veryfast -crf 20 -c:a aac -b:a 192k -movflags +faststart "%s"',
    [Ss, ASrc, Td, ADst]);
  if FileExists(ADst) then
  try
    TFile.Delete(ADst);
  except
  end;
  Result := RunHidden(Exe, Params) and FileExists(ADst) and (TFile.GetSize(ADst) > 0);
end;

function ExportMediaClip(const ASrc, ADst: string; AStart, AEnd: Double;
  AVideo: Boolean; out AError: string): Boolean;
var
  ExtS, ExtD, Dst: string;
begin
  Result := False;
  AError := '';
  Dst := ADst;
  if (ASrc = '') or (Dst = '') or not FileExists(ASrc) then
  begin
    AError := 'нет файла';
    Exit;
  end;
  if SameText(ExpandFileName(ASrc), ExpandFileName(Dst)) then
  begin
    AError := 'нельзя перезаписать исходный файл';
    Exit;
  end;
  if AEnd <= AStart then
    AEnd := AStart + 0.2;

  ExtS := LowerCase(ExtractFileExt(ASrc));
  ExtD := LowerCase(ExtractFileExt(Dst));

  if (not AVideo) and (ExtS = '.wav') and (ExtD = '.wav') then
  begin
    Result := WavLosslessClip(ASrc, Dst, AStart, AEnd, AError);
    if Result then
      Exit;
  end;

  if FindFfmpeg <> '' then
  begin
    Result := FfmpegClip(ASrc, Dst, AStart, AEnd);
    if Result then
      Exit;
  end;

  if not AVideo then
  begin
    if ExtD <> '.wav' then
      Dst := ChangeFileExt(Dst, '.wav');
    Result := MfWavClip(ASrc, Dst, AStart, AEnd, AError);
    if Result then
    begin
      if not SameText(Dst, ADst) then
        AError := 'Сохранено WAV: ' + Dst;
      Exit;
    end;
    if ExtS = '.wav' then
    begin
      Result := WavLosslessClip(ASrc, Dst, AStart, AEnd, AError);
      if Result then
        Exit;
    end;
  end;

  if FindFfmpeg = '' then
    AError := 'Нет ffmpeg.exe — клип в исходном формате недоступен.' + sLineBreak +
      'Положите ffmpeg.exe рядом с программой (essentials с gyan.dev).'
  else
    AError := 'Не удалось вырезать фрагмент. Попробуйте WAV или положите другой ffmpeg.';
end;
{$ENDIF}

constructor TMetaCache.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TDictionary<string, string>.Create;
  FPending := TDictionary<string, Boolean>.Create;
  FQueue := TQueue<string>.Create;
end;

destructor TMetaCache.Destroy;
begin
  Shutdown;
  FQueue.Free;
  FPending.Free;
  FItems.Free;
  FLock.Free;
  inherited;
end;

procedure TMetaCache.Shutdown;
var
  Guard: Integer;
begin
  FShuttingDown := True;
  FLock.Enter;
  try
    FQueue.Clear;
    FPending.Clear;
  finally
    FLock.Leave;
  end;
  Guard := 0;
  while (FBusy > 0) and (Guard < 12) do
  begin
    Sleep(15);
    Inc(Guard);
  end;
end;

function TMetaCache.TryGet(const APath: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if (APath = '') or FShuttingDown then
    Exit;
  FLock.Enter;
  try
    Result := FItems.TryGetValue(LowerCase(APath), AText);
  finally
    FLock.Leave;
  end;
end;

procedure TMetaCache.RequestAsync(const APath: string);
var
  Key, Dummy: string;
  Ext: string;
begin
  if FShuttingDown or (APath = '') then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if not (IsImageMetaExt(Ext) or IsMediaMetaExt(Ext)) then
    Exit;
  Key := LowerCase(APath);
  FLock.Enter;
  try
    if FItems.TryGetValue(Key, Dummy) then
      Exit;
    if FPending.ContainsKey(Key) then
      Exit;
    FPending.Add(Key, True);
    FQueue.Enqueue(APath);
  finally
    FLock.Leave;
  end;
  Pump;
end;

function TMetaCache.HasWork: Boolean;
begin
  FLock.Enter;
  try
    Result := (FQueue.Count > 0) or (FBusy > 0);
  finally
    FLock.Leave;
  end;
end;

function TMetaCache.Generation: Integer;
begin
  Result := FGeneration;
end;

procedure TMetaCache.Invalidate(const APath: string);
begin
  if APath = '' then
    Exit;
  FLock.Enter;
  try
    FItems.Remove(LowerCase(APath));
  finally
    FLock.Leave;
  end;
  TInterlocked.Increment(FGeneration);
end;

procedure TMetaCache.StartJob(const APath: string);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Text, Key: string;
    begin
      try
{$IFDEF MSWINDOWS}
        CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
{$ENDIF}
        try
          if not FShuttingDown then
            Text := ReadMetaText(APath);
        finally
{$IFDEF MSWINDOWS}
          CoUninitialize;
{$ENDIF}
        end;
        if not FShuttingDown then
        begin
          Key := LowerCase(APath);
          FLock.Enter;
          try
            FItems.AddOrSetValue(Key, Text);
            FPending.Remove(Key);
          finally
            FLock.Leave;
          end;
          TInterlocked.Increment(FGeneration);
        end;
      except
        FLock.Enter;
        try
          FPending.Remove(LowerCase(APath));
        finally
          FLock.Leave;
        end;
      end;
      TInterlocked.Decrement(FBusy);
      if not FShuttingDown then
        Pump;
    end).Start;
end;

procedure TMetaCache.Pump;
var
  Path: string;
begin
  while True do
  begin
    Path := '';
    FLock.Enter;
    try
      if FShuttingDown or (FQueue.Count = 0) or (FBusy >= MaxWorkers) then
        Exit;
      Path := FQueue.Dequeue;
      TInterlocked.Increment(FBusy);
    finally
      FLock.Leave;
    end;
    if Path <> '' then
      StartJob(Path);
  end;
end;

initialization
  GlobalMetaCache := TMetaCache.Create;

finalization
  if Assigned(GlobalMetaCache) then
    GlobalMetaCache.Shutdown;
  FreeAndNil(GlobalMetaCache);

end.

