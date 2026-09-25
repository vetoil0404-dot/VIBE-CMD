unit uIconCache;

{
  Кэш иконок панели: две растровые корзины 24 и 64.
  Paint читает готовый TBitmap и ничего не запрашивает с диска.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  FMX.Graphics, uFileModel;

type
  TIconBucket = (ib24, ib64);

  TCustomIconJob = record
    Key: string;
    Path: string;
    IsDir: Boolean;
    PixelSize: Integer;
  end;

  TTypeIconJob = record
    Key: string;
    IconKey: string;
    IsDir: Boolean;
    PixelSize: Integer;
  end;

function SelectIconBucket(ATargetSize: Integer): TIconBucket;
function IconBucketLogical(ABucket: TIconBucket): Integer;
function IconBucketPixels(ABucket: TIconBucket; AScale: Single): Integer;

type
  TIconCache = class
  private
    FTypes: TObjectDictionary<string, TBitmap>;
    FCustom: TObjectDictionary<string, TBitmap>;
    FPending: TDictionary<string, Boolean>;
    FNoCustom: TDictionary<string, Integer>;
    FQueue: TQueue<TCustomIconJob>;
    FTypeQueue: TQueue<TTypeIconJob>;
    FTypePending: TDictionary<string, Boolean>;
    FTypeFails: TDictionary<string, Integer>;
    FLock: TCriticalSection;
    FShuttingDown: Boolean;
    FBusy: Integer;
    FTypeBusy: Integer;
    FQueued: Integer;
    FGeneration: Integer;
    FMaxCustom: Integer;
    FCustomOrder: TStringList;
    FAllowTypes: Boolean;
    FAllowCustom: Boolean;
    function TypeKey(const AIconKey: string; AIsDir: Boolean;
      ABucket: TIconBucket): string;
    function CustomKey(const APath: string; ABucket: TIconBucket): string;
    function CustomPathOfKey(const AKey: string): string;
    procedure EvictCustomLocked;
    function CanFetchCustom(const APath: string): Boolean;
    procedure StartCustomJob(const AJob: TCustomIconJob);
    procedure PumpQueue;
    procedure EnqueueType(const AIconKey: string; AIsDir: Boolean;
      ABucket: TIconBucket; APixelSize: Integer);
    procedure StartTypeJob(const AJob: TTypeIconJob);
    procedure PumpTypeQueue;
    function TryGetTypeLocked(const AKey: string; out ABmp: TBitmap): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function GetForPaint(const AEntry: TFileEntry; ABucket: TIconBucket;
      AScale: Single = 1): TBitmap;
    procedure RequestCustom(const AEntry: TFileEntry; ABucket: TIconBucket;
      AScale: Single = 1);
    procedure PrefetchTypes(AList: TFileEntryList; ABucket: TIconBucket;
      AScale: Single = 1);
    procedure EnableTypeFetch;
    procedure EnableCustomFetch;
    function HasWork: Boolean;
    function Generation: Integer;
    procedure InvalidatePath(const APath: string);
    procedure InvalidateFolder(const AFolder: string);
    procedure Shutdown;
    procedure Clear;
  end;

var
  GlobalIconCache: TIconCache;

implementation

uses
  System.StrUtils, System.Math, System.UITypes, System.Types,
  System.Skia, FMX.Skia, UCoreEngine
  {$IFDEF MSWINDOWS}, Winapi.ActiveX{$ENDIF};

const
  MaxTypeRetries = 3;

function SelectIconBucket(ATargetSize: Integer): TIconBucket;
begin
  if ATargetSize <= 24 then
    Result := ib24
  else
    Result := ib64;
end;

function IconBucketLogical(ABucket: TIconBucket): Integer;
begin
  if ABucket = ib24 then
    Result := 24
  else
    Result := 64;
end;

function IconBucketId(ABucket: TIconBucket): string;
begin
  if ABucket = ib24 then
    Result := '24'
  else
    Result := '64';
end;

function IconBucketPixels(ABucket: TIconBucket; AScale: Single): Integer;
begin
  if AScale < 1 then
    AScale := 1;
  Result := Max(IconBucketLogical(ABucket), Round(IconBucketLogical(ABucket) * AScale));
end;

function FitIconPixels(var Pix: TBytes; var W, H: Integer; AMax: Integer): Boolean;
var
  Img: ISkImage;
  SrcInfo, DstInfo: TSkImageInfo;
  DstW, DstH: Integer;
  Scale: Double;
  Dst: TBytes;
begin
  Result := True;
  if (AMax < 8) or (W < 1) or (H < 1) then
    Exit;
  if (W <= AMax) and (H <= AMax) then
    Exit;
  Scale := Min(AMax / W, AMax / H);
  DstW := Max(1, Round(W * Scale));
  DstH := Max(1, Round(H * Scale));
  try
    SrcInfo := TSkImageInfo.Create(W, H, TSkColorType.BGRA8888, TSkAlphaType.Unpremul);
    Img := TSkImage.MakeRasterCopy(SrcInfo, @Pix[0], NativeUInt(W) * 4);
    if Img = nil then
      Exit(False);
    DstInfo := TSkImageInfo.Create(DstW, DstH, TSkColorType.BGRA8888,
      TSkAlphaType.Unpremul);
    SetLength(Dst, Int64(DstW) * DstH * 4);
    if not Img.ScalePixels(DstInfo, @Dst[0], NativeUInt(DstW) * 4,
      TSkSamplingOptions.Medium) then
      Exit(False);
    Pix := Dst;
    W := DstW;
    H := DstH;
  except
    Result := False;
  end;
end;

constructor TIconCache.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FTypes := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
  FCustom := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
  FPending := TDictionary<string, Boolean>.Create;
  FNoCustom := TDictionary<string, Integer>.Create;
  FQueue := TQueue<TCustomIconJob>.Create;
  FTypeQueue := TQueue<TTypeIconJob>.Create;
  FTypePending := TDictionary<string, Boolean>.Create;
  FTypeFails := TDictionary<string, Integer>.Create;
  FCustomOrder := TStringList.Create;
  FCustomOrder.CaseSensitive := False;
  FMaxCustom := 512;
  FBusy := 0;
  FTypeBusy := 0;
  FQueued := 0;
  FAllowTypes := False;
  FAllowCustom := False;
end;

destructor TIconCache.Destroy;
begin
  Shutdown;
  FreeAndNil(FCustomOrder);
  FreeAndNil(FQueue);
  FreeAndNil(FTypeQueue);
  FreeAndNil(FTypePending);
  FreeAndNil(FTypeFails);
  FreeAndNil(FNoCustom);
  FreeAndNil(FPending);
  FreeAndNil(FCustom);
  FreeAndNil(FTypes);
  FreeAndNil(FLock);
  inherited;
end;

procedure TIconCache.Shutdown;
var
  Guard: Integer;
begin
  FShuttingDown := True;
  FLock.Enter;
  try
    FQueue.Clear;
    FTypeQueue.Clear;
    FPending.Clear;
    FTypePending.Clear;
  finally
    FLock.Leave;
  end;
  Guard := 0;
  while ((FBusy > 0) or (FTypeBusy > 0) or (FQueued > 0)) and (Guard < 12) do
  begin
    if TThread.CurrentThread.ThreadID = MainThreadID then
      CheckSynchronize(15)
    else
      Sleep(15);
    Inc(Guard);
  end;
end;

procedure TIconCache.Clear;
begin
  FLock.Enter;
  try
    FTypes.Clear;
    FCustom.Clear;
    FPending.Clear;
    FNoCustom.Clear;
    FQueue.Clear;
    FTypeQueue.Clear;
    FTypePending.Clear;
    FTypeFails.Clear;
    FCustomOrder.Clear;
  finally
    FLock.Leave;
  end;
end;

function TIconCache.TypeKey(const AIconKey: string; AIsDir: Boolean;
  ABucket: TIconBucket): string;
begin
  if AIsDir then
    Result := '#dir'
  else if (AIconKey = '') or SameText(AIconKey, '#file') then
    Result := '#file'
  else
    Result := LowerCase(AIconKey);
  Result := Result + '|' + IconBucketId(ABucket);
end;

function TIconCache.CustomKey(const APath: string; ABucket: TIconBucket): string;
begin
  Result := APath + '|' + IconBucketId(ABucket);
end;

function TIconCache.CustomPathOfKey(const AKey: string): string;
var
  P: Integer;
begin
  P := LastDelimiter('|', AKey);
  if P > 1 then
    Result := Copy(AKey, 1, P - 1)
  else
    Result := AKey;
end;

function TIconCache.TryGetTypeLocked(const AKey: string; out ABmp: TBitmap): Boolean;
begin
  Result := FTypes.TryGetValue(AKey, ABmp) and Assigned(ABmp);
  if not Result then
    ABmp := nil;
end;

function TIconCache.GetForPaint(const AEntry: TFileEntry; ABucket: TIconBucket;
  AScale: Single): TBitmap;
var
  PathKey, ExtKey, FbKey: string;
  NeedType, NeedCustom, NeedFallback: Boolean;
  Fails: Integer;
  Px: Integer;
begin
  Result := nil;
  if FShuttingDown then
    Exit;
  Px := IconBucketPixels(ABucket, AScale);
  PathKey := '';
  if AEntry.FullPath <> '' then
    PathKey := CustomKey(AEntry.FullPath, ABucket);
  ExtKey := TypeKey(AEntry.IconKey, AEntry.IsDirectory, ABucket);
  if AEntry.IsDirectory then
    FbKey := TypeKey('#dir', True, ABucket)
  else
    FbKey := TypeKey('#file', False, ABucket);
  NeedType := False;
  NeedFallback := False;
  NeedCustom := FAllowCustom and AEntry.NeedsCustomIcon;
  FLock.Enter;
  try
    if (PathKey <> '') and FCustom.TryGetValue(PathKey, Result) and Assigned(Result) then
      Exit;
    if TryGetTypeLocked(ExtKey, Result) then
    begin
      { тип готов; custom всё равно можно догрузить }
    end
    else
    begin
      Result := nil;
      Fails := 0;
      FTypeFails.TryGetValue(ExtKey, Fails);
      NeedType := FAllowTypes and (Fails < MaxTypeRetries);
      if (ExtKey <> FbKey) and TryGetTypeLocked(FbKey, Result) then
      begin
        { fallback на экране, настоящий тип всё равно ставим в очередь }
      end
      else if ExtKey <> FbKey then
      begin
        Fails := 0;
        FTypeFails.TryGetValue(FbKey, Fails);
        NeedFallback := FAllowTypes and (Fails < MaxTypeRetries);
      end;
    end;
  finally
    FLock.Leave;
  end;
  if NeedType then
    EnqueueType(AEntry.IconKey, AEntry.IsDirectory, ABucket, Px);
  if NeedFallback then
  begin
    if AEntry.IsDirectory then
      EnqueueType('#dir', True, ABucket, Px)
    else
      EnqueueType('#file', False, ABucket, Px);
  end;
  if NeedCustom then
    RequestCustom(AEntry, ABucket, AScale);
end;

function TIconCache.CanFetchCustom(const APath: string): Boolean;
var
  Arc, Inner: string;
begin
  Result := False;
  if (APath = '') or FShuttingDown then
    Exit;
  if SplitArchivePath(APath, Arc, Inner) and (Inner <> '') then
    Exit;
  if IsThisPCPath(APath) then
    Exit;
  if IsVirtualShellPath(APath) and not IsPortableDevicePath(APath) and
     not IsDeviceNamespacePath(APath) then
    Exit;
  if IsCloudPlaceholderPath(APath) or IsBlockedReparsePath(APath) then
    Exit;
  Result := True;
end;

procedure TIconCache.StartCustomJob(const AJob: TCustomIconJob);
var
  Job: TCustomIconJob;
begin
  Job := AJob;
  AtomicIncrement(FBusy);
  TThread.CreateAnonymousThread(
    procedure
    var
      Pixels: TBytes;
      W, H: Integer;
      Keep: Boolean;
      Path, Key: string;
      IsDir: Boolean;
      NeedCom: Boolean;
      Attempt, Px: Integer;
    begin
      Path := Job.Path;
      Key := Job.Key;
      IsDir := Job.IsDir;
      Px := Job.PixelSize;
      if Px < 16 then
        Px := 16;
      Keep := False;
      W := 0;
      H := 0;
{$IFDEF MSWINDOWS}
      NeedCom := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
{$ELSE}
      NeedCom := False;
{$ENDIF}
      try
        if not FShuttingDown then
        for Attempt := 1 to MaxTypeRetries do
        begin
          try
{$IFDEF MSWINDOWS}
            var Unk: IUnknown := nil;
            if TryBindShellItem(Path, Unk) then
              Keep := GetShellItemIconRaw(Unk, IsDir, Pixels, W, H, Px) and
                (W > 0) and (H > 0);
            if not Keep then
{$ENDIF}
              Keep := GetFileIconRaw(Path, IsDir, Pixels, W, H, Px) and
                (W > 0) and (H > 0);
            if Keep then
            begin
              FitIconPixels(Pixels, W, H, Px);
              Break;
            end;
          except
            Keep := False;
            SetLength(Pixels, 0);
          end;
          if (Attempt < MaxTypeRetries) and not FShuttingDown then
            Sleep(50 + 75 * (Attempt - 1));
        end;
      finally
{$IFDEF MSWINDOWS}
        if NeedCom then
          CoUninitialize;
{$ENDIF}
      end;

      if FShuttingDown then
      begin
        AtomicDecrement(FBusy);
        Exit;
      end;

      AtomicIncrement(FQueued);
      TThread.Queue(nil,
        procedure
        var
          Bmp: TBitmap;
          N: Integer;
        begin
          Bmp := nil;
          try
            if FShuttingDown or (GlobalIconCache = nil) then
              Exit;
            if Keep then
            try
              Bmp := TBitmap.Create;
              BgraToFmxBitmap(Pixels, W, H, Bmp);
              if (Bmp.Width <= 0) or (Bmp.Height <= 0) then
                FreeAndNil(Bmp);
            except
              FreeAndNil(Bmp);
            end;
            FLock.Enter;
            try
              FPending.Remove(Key);
              if Assigned(Bmp) then
              begin
                if FCustom.ContainsKey(Key) then
                  FreeAndNil(Bmp)
                else
                begin
                  FCustom.Add(Key, Bmp);
                  FCustomOrder.Add(Key);
                  EvictCustomLocked;
                  FNoCustom.Remove(Key);
                  Inc(FGeneration);
                  Bmp := nil;
                end;
              end
              else
              begin
                N := 0;
                FNoCustom.TryGetValue(Key, N);
                FNoCustom.AddOrSetValue(Key, N + MaxTypeRetries);
              end;
            finally
              FLock.Leave;
              Bmp.Free;
            end;
          finally
            AtomicDecrement(FQueued);
          end;
        end);

      AtomicDecrement(FBusy);
      FLock.Enter;
      try
        PumpQueue;
      finally
        FLock.Leave;
      end;
    end).Start;
end;

procedure TIconCache.PumpQueue;
const
  MaxCustomWorkers = 4;
var
  Job: TCustomIconJob;
begin
  while (FBusy < MaxCustomWorkers) and (FQueue.Count > 0) and not FShuttingDown do
  begin
    Job := FQueue.Dequeue;
    StartCustomJob(Job);
  end;
end;

procedure TIconCache.PumpTypeQueue;
const
  MaxTypeWorkers = 1;
var
  Job: TTypeIconJob;
begin
  while (FTypeBusy < MaxTypeWorkers) and (FTypeQueue.Count > 0) and not FShuttingDown do
  begin
    Job := FTypeQueue.Dequeue;
    StartTypeJob(Job);
  end;
end;

procedure TIconCache.EnqueueType(const AIconKey: string; AIsDir: Boolean;
  ABucket: TIconBucket; APixelSize: Integer);
var
  Key: string;
  Job: TTypeIconJob;
  Fails: Integer;
begin
  if FShuttingDown or not FAllowTypes then
    Exit;
  Key := TypeKey(AIconKey, AIsDir, ABucket);
  FLock.Enter;
  try
    if FTypes.ContainsKey(Key) or FTypePending.ContainsKey(Key) then
      Exit;
    Fails := 0;
    if FTypeFails.TryGetValue(Key, Fails) and (Fails >= MaxTypeRetries) then
      Exit;
    FTypePending.Add(Key, True);
    Job.Key := Key;
    Job.IconKey := AIconKey;
    Job.IsDir := AIsDir or SameText(AIconKey, '#dir') or SameText(AIconKey, '#drive');
    Job.PixelSize := APixelSize;
    FTypeQueue.Enqueue(Job);
    PumpTypeQueue;
  finally
    FLock.Leave;
  end;
end;

procedure TIconCache.StartTypeJob(const AJob: TTypeIconJob);
var
  Job: TTypeIconJob;
begin
  Job := AJob;
  AtomicIncrement(FTypeBusy);
  TThread.CreateAnonymousThread(
    procedure
    var
      Pixels: TBytes;
      W, H: Integer;
      Key, IconKey: string;
      IsDir: Boolean;
      Keep: Boolean;
      NeedCom: Boolean;
      Attempt, Px: Integer;
    begin
      Key := Job.Key;
      IconKey := Job.IconKey;
      IsDir := Job.IsDir;
      Px := Job.PixelSize;
      if Px < 16 then
        Px := 16;
      Keep := False;
      W := 0;
      H := 0;
{$IFDEF MSWINDOWS}
      NeedCom := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
{$ELSE}
      NeedCom := False;
{$ENDIF}
      try
        if not FShuttingDown then
        for Attempt := 1 to MaxTypeRetries do
        begin
          try
            Keep := GetTypeIconRaw(IconKey, IsDir, Pixels, W, H, Px) and
              (W > 0) and (H > 0);
            if Keep then
            begin
              FitIconPixels(Pixels, W, H, Px);
              Break;
            end;
          except
            Keep := False;
            SetLength(Pixels, 0);
          end;
          if (Attempt < MaxTypeRetries) and not FShuttingDown then
            Sleep(50 + 75 * (Attempt - 1));
        end;
      finally
{$IFDEF MSWINDOWS}
        if NeedCom then
          CoUninitialize;
{$ENDIF}
      end;

      if FShuttingDown then
      begin
        AtomicDecrement(FTypeBusy);
        Exit;
      end;

      AtomicIncrement(FQueued);
      TThread.Queue(nil,
        procedure
        var
          Bmp: TBitmap;
        begin
          Bmp := nil;
          try
            if FShuttingDown or (GlobalIconCache = nil) then
              Exit;
            if Keep then
            try
              Bmp := TBitmap.Create;
              BgraToFmxBitmap(Pixels, W, H, Bmp);
              if (Bmp.Width <= 0) or (Bmp.Height <= 0) then
                FreeAndNil(Bmp);
            except
              FreeAndNil(Bmp);
            end;
            FLock.Enter;
            try
              FTypePending.Remove(Key);
              if Assigned(Bmp) then
              begin
                FTypeFails.Remove(Key);
                if FTypes.ContainsKey(Key) then
                  FreeAndNil(Bmp)
                else
                begin
                  FTypes.Add(Key, Bmp);
                  Inc(FGeneration);
                  Bmp := nil;
                end;
              end
              else
                FTypeFails.AddOrSetValue(Key, MaxTypeRetries);
            finally
              FLock.Leave;
              Bmp.Free;
            end;
          finally
            AtomicDecrement(FQueued);
          end;
        end);

      AtomicDecrement(FTypeBusy);
      FLock.Enter;
      try
        PumpTypeQueue;
      finally
        FLock.Leave;
      end;
    end).Start;
end;

procedure TIconCache.RequestCustom(const AEntry: TFileEntry; ABucket: TIconBucket;
  AScale: Single);
var
  Path, Key: string;
  Job: TCustomIconJob;
  Fails: Integer;
begin
  if FShuttingDown or not FAllowCustom or not AEntry.NeedsCustomIcon then
    Exit;
  Path := AEntry.FullPath;
  if not CanFetchCustom(Path) then
    Exit;
  Key := CustomKey(Path, ABucket);

  FLock.Enter;
  try
    if FCustom.ContainsKey(Key) or FPending.ContainsKey(Key) then
      Exit;
    Fails := 0;
    if FNoCustom.TryGetValue(Key, Fails) and (Fails >= MaxTypeRetries) then
      Exit;
    FPending.Add(Key, True);
    Job.Key := Key;
    Job.Path := Path;
    Job.IsDir := AEntry.IsDirectory;
    Job.PixelSize := IconBucketPixels(ABucket, AScale);
    FQueue.Enqueue(Job);
    PumpQueue;
  finally
    FLock.Leave;
  end;
end;

procedure TIconCache.EvictCustomLocked;
var
  Victim: string;
begin
  while (FCustomOrder.Count > FMaxCustom) and (FCustomOrder.Count > 0) do
  begin
    Victim := FCustomOrder[0];
    FCustomOrder.Delete(0);
    FCustom.Remove(Victim);
  end;
end;

procedure TIconCache.EnableTypeFetch;
begin
  FAllowTypes := True;
end;

procedure TIconCache.EnableCustomFetch;
begin
  FAllowCustom := True;
end;

procedure TIconCache.PrefetchTypes(AList: TFileEntryList; ABucket: TIconBucket;
  AScale: Single);
var
  Seen: TDictionary<string, Boolean>;
  E: TFileEntry;
  Key: string;
  Px: Integer;
begin
  if FShuttingDown or not FAllowTypes or (AList = nil) then
    Exit;
  Px := IconBucketPixels(ABucket, AScale);
  FLock.Enter;
  try
    FTypeFails.Clear;
  finally
    FLock.Leave;
  end;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for E in AList do
    begin
      Key := TypeKey(E.IconKey, E.IsDirectory, ABucket);
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      EnqueueType(E.IconKey, E.IsDirectory, ABucket, Px);
    end;
    EnqueueType('#file', False, ABucket, Px);
    EnqueueType('#dir', True, ABucket, Px);
  finally
    Seen.Free;
  end;
end;

function TIconCache.HasWork: Boolean;
begin
  FLock.Enter;
  try
    Result := (FPending.Count > 0) or (FQueue.Count > 0) or (FBusy > 0) or
      (FTypePending.Count > 0) or (FTypeQueue.Count > 0) or (FTypeBusy > 0) or
      (FQueued > 0);
  finally
    FLock.Leave;
  end;
end;

function TIconCache.Generation: Integer;
begin
  Result := FGeneration;
end;

procedure TIconCache.InvalidatePath(const APath: string);
var
  I: Integer;
  K: string;
  Keys: TArray<string>;
begin
  if APath = '' then
    Exit;
  FLock.Enter;
  try
    Keys := FCustom.Keys.ToArray;
    for K in Keys do
      if SameText(CustomPathOfKey(K), APath) then
      begin
        FCustom.Remove(K);
        FNoCustom.Remove(K);
        FPending.Remove(K);
        I := FCustomOrder.IndexOf(K);
        if I >= 0 then
          FCustomOrder.Delete(I);
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TIconCache.InvalidateFolder(const AFolder: string);
var
  Prefix: string;
  Keys: TArray<string>;
  K, Path: string;
  I: Integer;
begin
  if AFolder = '' then
    Exit;
  Prefix := IncludeTrailingPathDelimiter(AFolder);
  FLock.Enter;
  try
    FTypeFails.Clear;
    Keys := FCustom.Keys.ToArray;
    for K in Keys do
    begin
      Path := CustomPathOfKey(K);
      if StartsText(Prefix, IncludeTrailingPathDelimiter(ExtractFilePath(Path))) or
         SameText(Path, ExcludeTrailingPathDelimiter(AFolder)) then
      begin
        FCustom.Remove(K);
        FNoCustom.Remove(K);
        I := FCustomOrder.IndexOf(K);
        if I >= 0 then
          FCustomOrder.Delete(I);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

initialization
  GlobalIconCache := TIconCache.Create;

finalization
  if Assigned(GlobalIconCache) then
    GlobalIconCache.Shutdown;
  FreeAndNil(GlobalIconCache);

end.

