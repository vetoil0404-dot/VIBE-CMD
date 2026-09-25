unit uThumbCache;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.SyncObjs, System.Diagnostics, System.DateUtils, System.StrUtils,
  System.Math, System.UITypes, System.Types,
  FMX.Graphics, FMX.Types, FMX.Skia, System.Skia,
  UCoreEngine, uFileModel, uSpreadsheetData, uDocumentData, uPdfium,
  uPsdPreview, uTextCode;

function TryLoadSvgDom(const APath: string; out ADom: ISkSVGDOM): Boolean;
function ReadSvgText(const APath: string): string;
function RenderSvgThumbRaw(const APath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
function IsThumbCandidate(const APath: string; AIsDir: Boolean = False;
  const ANameHint: string = ''): Boolean;

type
  TThumbReadyProc = reference to procedure(const APath: string; ABitmap: TBitmap);

  TThumbStamp = record
    Age: TDateTime;
    Bytes: Int64;
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

  TThumbCache = class
  private
    FCache: TDictionary<string, TCachedThumb>;
    FNoThumb: TDictionary<string, TThumbStamp>;
    FPending: TDictionary<string, Boolean>;
    FWait: TQueue<TThumbJob>;
    FLock: TCriticalSection;
    FShuttingDown: Boolean;
    FBusy: Integer;
    FQueued: Integer;
    FEnabled: Boolean;
    FWorkersEnabled: Boolean;
    FMaxItems: Integer;
    FGeneration: Integer;
    FOrder: TStringList;
    procedure WaitIdle;
    procedure TouchLocked(const APath: string);
    procedure EvictLocked;
    function CanCacheFile(const APath: string; const ANameHint: string = ''): Boolean;
    function ReadStamp(const APath: string; out AStamp: TThumbStamp): Boolean;
    function SameStamp(const A, B: TThumbStamp): Boolean;
    procedure RemoveCachedLocked(const APath: string);
    procedure PumpJobs;
    procedure StartJob(const AJob: TThumbJob);
  public
    constructor Create;
    destructor Destroy; override;

    function TryGet(const APath: string; out ABitmap: TBitmap): Boolean;
    procedure RequestAsync(const APath: string; ASize: Integer; AOnReady: TThumbReadyProc;
      const ANameHint: string = '');
    function HasWork: Boolean;
    function PendingCount: Integer;
    function Generation: Integer;
    procedure Invalidate(const APath: string);
    procedure InvalidateFolder(const AFolder: string);
    procedure Shutdown;
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
  System.ZLib
  {$IFDEF MSWINDOWS}, Winapi.ShlObj, Winapi.ActiveX{$ENDIF};

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

function IsRasterThumbExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.jpg') or (AExt = '.jpeg') or (AExt = '.jpe') or
    (AExt = '.jfif') or (AExt = '.png') or (AExt = '.gif') or (AExt = '.bmp') or
    (AExt = '.dib') or (AExt = '.webp') or (AExt = '.tif') or (AExt = '.tiff') or
    (AExt = '.heic') or (AExt = '.heif') or (AExt = '.avif') or
    (AExt = '.jxl') or (AExt = '.tga');
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
    Exit;
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
    Exit;
  if IsArchiveExt(Ext) then
    Exit(True);
  { exe/lnk/ico — jumbo из IconCache, не полный decode и не shell-thumb. }
  Result :=
    (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') or (Ext = '.jfif') or
    (Ext = '.png') or (Ext = '.gif') or (Ext = '.bmp') or (Ext = '.dib') or
    (Ext = '.webp') or (Ext = '.tif') or (Ext = '.tiff') or (Ext = '.tga') or
    (Ext = '.heic') or (Ext = '.heif') or (Ext = '.avif') or
    (Ext = '.jxl') or (Ext = '.dds') or (Ext = '.wmf') or (Ext = '.emf') or
    (Ext = '.pdf') or (Ext = '.svg') or (Ext = '.svgz') or (Ext = '.ai') or
    (Ext = '.psd') or (Ext = '.psb') or
    (Ext = '.xlsx') or (Ext = '.xls') or (Ext = '.xlsm') or
    (Ext = '.csv') or (Ext = '.tsv') or
    (Ext = '.tgs') or
    (Ext = '.docx') or (Ext = '.doc') or (Ext = '.pptx') or (Ext = '.ppt') or
    (Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or (Ext = '.mov') or
    (Ext = '.wmv') or (Ext = '.webm') or
    (IsListedTextExt(Ext) and not IsRemotePath(APath));
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
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
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
  if not IsSvgThumbExt(APath) then
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

function RenderRasterThumbRaw(const APath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
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
  if not IsRasterThumbExt(ThumbExtOf(APath, '')) then
    Exit;
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

{ TThumbCache }

constructor TThumbCache.Create;
begin
  inherited Create;
  FCache := TDictionary<string, TCachedThumb>.Create;
  FNoThumb := TDictionary<string, TThumbStamp>.Create;
  FPending := TDictionary<string, Boolean>.Create;
  FWait := TQueue<TThumbJob>.Create;
  FOrder := TStringList.Create;
  FLock := TCriticalSection.Create;
  FShuttingDown := False;
  FBusy := 0;
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
begin
  Result := False;
  AStamp.Age := 0;
  AStamp.Bytes := 0;
  if not CanCacheFile(APath) then
    Exit;
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

procedure TThumbCache.WaitIdle;
var
  Sw: TStopwatch;
begin
  Sw := TStopwatch.StartNew;
  { При выходе не ждём до 3с — процесс и так убьёт воркеры. }
  while ((FBusy > 0) or (FQueued > 0)) and (Sw.ElapsedMilliseconds < 250) do
  begin
    if TThread.CurrentThread.ThreadID = MainThreadID then
      CheckSynchronize(15)
    else
      Sleep(15);
  end;
end;

procedure TThumbCache.Shutdown;
begin
  FShuttingDown := True;
  FLock.Enter;
  try
    FWait.Clear;
    FPending.Clear;
  finally
    FLock.Leave;
  end;
  WaitIdle;
end;

destructor TThumbCache.Destroy;
begin
  Shutdown;
  Clear;
  FCache.Free;
  FNoThumb.Free;
  FPending.Free;
  FWait.Free;
  FOrder.Free;
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
    FPending.Clear;
    FWait.Clear;
    FOrder.Clear;
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
  finally
    FLock.Leave;
  end;
end;

procedure TThumbCache.InvalidateFolder(const AFolder: string);
var
  Prefix: string;
  Keys: TArray<string>;
  K: string;
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
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.HasWork: Boolean;
begin
  FLock.Enter;
  try
    Result := (FPending.Count > 0) or (FWait.Count > 0) or (FBusy > 0) or (FQueued > 0);
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.PendingCount: Integer;
begin
  FLock.Enter;
  try
    Result := FWait.Count + FBusy;
  finally
    FLock.Leave;
  end;
end;

function TThumbCache.TryGet(const APath: string; out ABitmap: TBitmap): Boolean;
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
        Exit;
      Job := FWait.Dequeue;
      Inc(FBusy);
    finally
      FLock.Leave;
    end;
    StartJob(Job);
  end;
end;

function RenderTgsThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;
var
  FS: TFileStream;
  Z: TDecompressionStream;
  Anim: ISkottieAnimation;
  Sz: TSizeF;
  S: Single;
  R: TRectF;
begin
  Result := False;
  if (ABitmap = nil) or (AWidth < 8) or (AHeight < 8) or (APath = '') then
    Exit;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Z := TDecompressionStream.Create(FS, 31);
    try
      Anim := TSkottieAnimation.MakeFromStream(Z);
    finally
      Z.Free;
    end;
  finally
    FS.Free;
  end;
  if Anim = nil then
    Exit;
  Anim.SeekFrameTime(0);
  Sz := Anim.Size;
  if (Sz.Width < 1) or (Sz.Height < 1) then
    Exit;
  ABitmap.SetSize(AWidth, AHeight);
  S := Min((AWidth - 8) / Sz.Width, (AHeight - 8) / Sz.Height);
  R := RectF((AWidth - Sz.Width * S) / 2, (AHeight - Sz.Height * S) / 2, 0, 0);
  R.Right := R.Left + Sz.Width * S;
  R.Bottom := R.Top + Sz.Height * S;
  ABitmap.SkiaDraw(
    procedure(const ACanvas: ISkCanvas)
    begin
      ACanvas.Clear($FFFFFFFF);
      Anim.Render(ACanvas, R, []);
    end, True);
  Result := True;
end;

procedure TThumbCache.StartJob(const AJob: TThumbJob);
var
  Path, NameHint: string;
  Size: Integer;
  Age: TThumbStamp;
  Ready: TThumbReadyProc;
begin
  Path := AJob.Path;
  Size := AJob.Size;
  Age := AJob.Stamp;
  NameHint := AJob.NameHint;
  Ready := AJob.OnReady;
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
      Local, Ext: string;
    begin
      Bmp := nil;
      Success := False;
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
            if IsRasterThumbExt(Ext) then
              Success := RenderRasterThumbRaw(Path, RenderSize, RenderSize, Raw, RawW, RawH);
            if not Success and IsPdfThumbExt(Path) then
              Success := RenderPdfThumbRaw(Path, RenderSize, RenderSize, Raw, RawW, RawH);
            if not Success and IsSvgThumbExt(Path) then
              Success := RenderSvgThumbRaw(Path, RenderSize, RenderSize, Raw, RawW, RawH);
            if not Success and IsPsdThumbExt(Path) then
              Success := RenderPsdThumbRaw(Path, RenderSize, RenderSize, Raw, RawW, RawH);

            if not Success and (Length(Raw) = 0) then
            begin
              if IsSpreadsheetThumbExt(Path) or IsDocumentThumbExt(Path) then
              begin
                Bmp := TBitmap.Create;
                try
                  if IsSpreadsheetThumbExt(Path) then
                    Success := RenderSpreadsheetThumb(Path, RenderSize, RenderSize, Bmp);
                  if not Success and IsDocumentThumbExt(Path) then
                    Success := RenderDocumentThumb(Path, RenderSize, RenderSize, Bmp);
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

            if not Success and (Bmp = nil) and (Ext = '.tgs') then
            begin
              Bmp := TBitmap.Create;
              try
                Success := RenderTgsThumb(Path, RenderSize, RenderSize, Bmp);
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

            if not Success and (Bmp = nil) and IsListedTextExt(Ext) and
               not IsRemotePath(Path) then
            begin
              Bmp := TBitmap.Create;
              try
                Success := RenderTextA4Thumb(Path, RenderSize, RenderSize, Bmp);
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

{$IFDEF MSWINDOWS}
            if not Success then
            begin
              Unk := nil;
              if TryBindShellItem(Path, Unk) then
                Success := GetShellItemThumbnailRaw(Unk, RenderSize, RenderSize, Raw, RawW, RawH);
            end;
{$ENDIF}
            if not Success then
              Success := GetFileThumbnailRaw(Path, RenderSize, RenderSize, Raw, RawW, RawH);
{$IFDEF MSWINDOWS}
            if not Success and IsRasterThumbExt(Ext) and
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
{$ENDIF}
          end;
        except
          Success := False;
          FreeAndNil(Bmp);
          SetLength(Raw, 0);
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
          begin
            UiBmp := nil;
            NotifyBmp := nil;
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
                FPending.Remove(Path);
                if Success and Assigned(UiBmp) then
                begin
                  if FCache.TryGetValue(Path, Old) and (Old.Bitmap <> UiBmp) then
                    Old.Bitmap.Free;
                  Stored.Bitmap := UiBmp;
                  Stored.Stamp := Stamp;
                  FCache.AddOrSetValue(Path, Stored);
                  FNoThumb.Remove(Path);
                  TouchLocked(Path);
                  EvictLocked;
                  Inc(FGeneration);
                  NotifyBmp := Stored.Bitmap;
                  UiBmp := nil;
                end
                else
                begin
                  FNoThumb.AddOrSetValue(Path, Stamp);
                  FreeAndNil(UiBmp);
                end;
              finally
                FLock.Leave;
              end;
              if Assigned(Ready) and Assigned(NotifyBmp) then
                Ready(Path, NotifyBmp);
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
          if FBusy > 0 then
            Dec(FBusy);
        finally
          FLock.Leave;
        end;
        PumpJobs;
      end;
    end).Start;
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
          not IsPsdThumbExt(APath)) then
        Exit;
      FNoThumb.Remove(APath);
    end;

    FPending.Add(APath, True);
    Job.Path := APath;
    Job.Size := ASize;
    Job.Stamp := Current;
    Job.NameHint := ANameHint;
    Job.OnReady := AOnReady;
    FWait.Enqueue(Job);
  finally
    FLock.Leave;
  end;

  PumpJobs;
end;

initialization
  GlobalThumbCache := TThumbCache.Create;

finalization
  if Assigned(GlobalThumbCache) then
    GlobalThumbCache.Shutdown;
  FreeAndNil(GlobalThumbCache);

end.

