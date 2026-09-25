unit uWinBrowserDrop;

{
  Приём картинок из браузера через IDropTarget на HWND формы.
  CF_HDROP и прочий FMX-drop проксируются во внутренний TWinDropTarget.
  Исходящий SHDoDragDrop не трогаем.
}

interface

{$IFDEF MSWINDOWS}

uses
  FMX.Forms;

procedure InstallFormDropTarget(AForm: TCommonCustomForm);
procedure UninstallFormDropTarget(AForm: TCommonCustomForm);

{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Math, System.Types,
  System.IOUtils, System.Rtti, System.NetEncoding, System.Net.HttpClient,
  Winapi.Windows, Winapi.ActiveX, Winapi.ShellAPI, Winapi.ShlObj,
  Vcl.Graphics, Vcl.Imaging.pngimage,
  FMX.Types, FMX.Platform.Win,
  uFilePanel, uCustomTabs;

const
  CF_FMOBJECT = CF_PRIVATEFIRST + 1;
  MaxDropBytes = Int64(100) * 1024 * 1024;
  DropTimeoutMs = 30000;
  BrowserUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

type
  TDropKind = (dkNone, dkHDrop, dkBytes, dkUrl);

  TDropItem = record
    Kind: TDropKind;
    Name: string;
    Bytes: TBytes;
    Url: string;
  end;

  TBrowserDropJob = class
  private
    FPanel: TFilePanel;
    FDest: string;
    FGen: Integer;
    FItems: TArray<TDropItem>;
  public
    constructor Create(APanel: TFilePanel; const ADest: string; AGen: Integer;
      const AItems: TArray<TDropItem>);
    procedure Run;
  end;

  TFormDropTarget = class(TInterfacedObject, IDropTarget)
  private
    FForm: TCommonCustomForm;
    FInner: IDropTarget;
    FHover: TFilePanel;
    FBrowser: Boolean;
    function ScreenOf(const pt: TPoint): TPointF;
    function TrackAt(const pt: TPoint; ABrowser: Boolean; out ADest: string;
      out APanel: TFilePanel): Boolean;
    procedure ClearHover;
    function PanelOk(APanel: TFilePanel): Boolean;
  public
    constructor Create(AForm: TCommonCustomForm);
    function DragEnter(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function DragOver(grfKeyState: Longint; pt: TPoint;
      var dwEffect: Longint): HResult; stdcall;
    function DragLeave: HResult; stdcall;
    function Drop(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;
  end;

var
  GDrop: IDropTarget;
  GDropWnd: HWND;
  GDropGen: Integer;
  CF_FILEDESCRIPTORW: TClipFormat;
  CF_FILEDESCRIPTORA: TClipFormat;
  CF_FILECONTENTS: TClipFormat;
  CF_INETURLW: TClipFormat;
  CF_INETURLA: TClipFormat;
  CF_URILIST: TClipFormat;
  CF_MOZURL: TClipFormat;
  CF_HTML: TClipFormat;
  CF_PNG: TClipFormat;
  CF_IMAGEPNG: TClipFormat;

function PanelClosing(APanel: TFilePanel): Boolean;
begin
  Result := (APanel = nil) or (csDestroying in APanel.ComponentState);
end;

function HasFormat(const Data: IDataObject; AFmt: TClipFormat;
  AIndex: Integer; ATymed: Longint): Boolean;
var
  Fe: TFormatEtc;
begin
  Result := False;
  if Data = nil then
    Exit;
  Fe.cfFormat := AFmt;
  Fe.ptd := nil;
  Fe.dwAspect := DVASPECT_CONTENT;
  Fe.lindex := AIndex;
  Fe.tymed := ATymed;
  Result := Data.QueryGetData(Fe) = S_OK;
end;

function IsFmxInternalDrag(const Data: IDataObject): Boolean;
begin
  Result := IsTabDragActive or
    HasFormat(Data, CF_FMOBJECT, -1, TYMED_HGLOBAL);
end;

function BrowserFormatsPresent(const Data: IDataObject): Boolean;
begin
  if IsFmxInternalDrag(Data) then
    Exit(False);
  Result := HasFormat(Data, CF_FILEDESCRIPTORW, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_FILEDESCRIPTORA, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_INETURLW, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_INETURLA, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_URILIST, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_MOZURL, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_HTML, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_PNG, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_IMAGEPNG, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_DIB, -1, TYMED_HGLOBAL) or
    HasFormat(Data, CF_BITMAP, -1, TYMED_GDI);
end;

function GetMedium(const Data: IDataObject; AFmt: TClipFormat; AIndex: Integer;
  ATymed: Longint; out Med: TStgMedium): Boolean;
var
  Fe: TFormatEtc;
begin
  FillChar(Med, SizeOf(Med), 0);
  Fe.cfFormat := AFmt;
  Fe.ptd := nil;
  Fe.dwAspect := DVASPECT_CONTENT;
  Fe.lindex := AIndex;
  Fe.tymed := ATymed;
  Result := Succeeded(Data.GetData(Fe, Med));
end;

function GlobalToRaw(H: HGLOBAL; out N: NativeUInt): Pointer;
begin
  Result := nil;
  N := 0;
  if H = 0 then
    Exit;
  N := GlobalSize(H);
  Result := GlobalLock(H);
end;

function BytesFromGlobal(H: HGLOBAL): TBytes;
var
  P: Pointer;
  N: NativeUInt;
begin
  SetLength(Result, 0);
  P := GlobalToRaw(H, N);
  if P = nil then
    Exit;
  try
    SetLength(Result, N);
    if N > 0 then
      Move(P^, Result[0], N);
  finally
    GlobalUnlock(H);
  end;
end;

function WideFromGlobal(H: HGLOBAL): string;
var
  P: PWideChar;
  N: NativeUInt;
begin
  Result := '';
  P := GlobalToRaw(H, N);
  if P = nil then
    Exit;
  try
    Result := PWideChar(P);
  finally
    GlobalUnlock(H);
  end;
end;

function AnsiFromGlobal(H: HGLOBAL): string;
var
  P: PAnsiChar;
  N: NativeUInt;
begin
  Result := '';
  P := GlobalToRaw(H, N);
  if P = nil then
    Exit;
  try
    Result := string(PAnsiChar(P));
  finally
    GlobalUnlock(H);
  end;
end;

function Utf8FromGlobal(H: HGLOBAL): string;
var
  Raw: TBytes;
  N: Integer;
begin
  Raw := BytesFromGlobal(H);
  N := Length(Raw);
  while (N > 0) and (Raw[N - 1] = 0) do
    Dec(N);
  SetLength(Raw, N);
  Result := TEncoding.UTF8.GetString(Raw);
end;

function StreamToBytes(Stm: IStream): TBytes;
var
  Stat: TStatStg;
  Total, Got: Int64;
  Chunk: Longint;
  Buf: array[0..65535] of Byte;
  ReadN: FixedUInt;
begin
  SetLength(Result, 0);
  if Stm = nil then
    Exit;
  FillChar(Stat, SizeOf(Stat), 0);
  Total := 0;
  if Succeeded(Stm.Stat(Stat, STATFLAG_NONAME)) then
    Total := Stat.cbSize;
  if Total > MaxDropBytes then
    raise Exception.Create('Файл слишком большой (лимит 100 МБ)');
  if Total > 0 then
    SetLength(Result, Total);
  Got := 0;
  repeat
    ReadN := 0;
    if Failed(Stm.Read(@Buf[0], SizeOf(Buf), @ReadN)) or (ReadN = 0) then
      Break;
    Chunk := Longint(ReadN);
    if Got + Chunk > MaxDropBytes then
      raise Exception.Create('Файл слишком большой (лимит 100 МБ)');
    if Length(Result) < Got + Chunk then
      SetLength(Result, Got + Chunk);
    Move(Buf[0], Result[Got], Chunk);
    Inc(Got, Chunk);
  until False;
  SetLength(Result, Got);
end;

function ExtFromSignature(const ABytes: TBytes): string;
begin
  Result := '';
  if Length(ABytes) >= 3 then
    if (ABytes[0] = $FF) and (ABytes[1] = $D8) and (ABytes[2] = $FF) then
      Exit('.jpg');
  if Length(ABytes) >= 8 then
    if (ABytes[0] = $89) and (ABytes[1] = $50) and (ABytes[2] = $4E) and (ABytes[3] = $47) then
      Exit('.png');
  if Length(ABytes) >= 6 then
    if (ABytes[0] = $47) and (ABytes[1] = $49) and (ABytes[2] = $46) then
      Exit('.gif');
  if Length(ABytes) >= 2 then
    if (ABytes[0] = $42) and (ABytes[1] = $4D) then
      Exit('.bmp');
  if Length(ABytes) >= 12 then
    if (ABytes[0] = $52) and (ABytes[1] = $49) and (ABytes[2] = $46) and (ABytes[3] = $46) and
       (ABytes[8] = $57) and (ABytes[9] = $45) and (ABytes[10] = $42) and (ABytes[11] = $50) then
      Exit('.webp');
end;

function ExtFromMime(const AMime: string): string;
var
  M: string;
  P: Integer;
begin
  M := LowerCase(Trim(AMime));
  P := Pos(';', M);
  if P > 0 then
    M := Trim(Copy(M, 1, P - 1));
  if (M = 'image/jpeg') or (M = 'image/jpg') then
    Exit('.jpg');
  if M = 'image/png' then
    Exit('.png');
  if M = 'image/gif' then
    Exit('.gif');
  if M = 'image/webp' then
    Exit('.webp');
  if (M = 'image/bmp') or (M = 'image/x-bmp') or (M = 'image/x-ms-bmp') then
    Exit('.bmp');
  Result := '';
end;

function MimeLooksLikeHtml(const AMime: string): Boolean;
var
  M: string;
  P: Integer;
begin
  M := LowerCase(Trim(AMime));
  P := Pos(';', M);
  if P > 0 then
    M := Trim(Copy(M, 1, P - 1));
  Result := (M = 'text/html') or (M = 'application/xhtml+xml');
end;

function SafeFileName(const AName: string): string;
var
  I: Integer;
  C: Char;
  Leaf: string;
begin
  Leaf := AName;
  I := LastDelimiter('/\', Leaf);
  if I > 0 then
    Leaf := Copy(Leaf, I + 1, MaxInt);
  I := Pos('?', Leaf);
  if I > 0 then
    Leaf := Copy(Leaf, 1, I - 1);
  I := Pos('#', Leaf);
  if I > 0 then
    Leaf := Copy(Leaf, 1, I - 1);
  Result := '';
  for I := 1 to Length(Leaf) do
  begin
    C := Leaf[I];
    if CharInSet(C, ['<', '>', ':', '"', '/', '\', '|', '?', '*', #0..#31]) then
      Result := Result + '_'
    else
      Result := Result + C;
  end;
  Result := Trim(Result);
  if (Result = '') or (Result = '.') or (Result = '..') then
    Result := 'image';
end;

function UniqueDestPath(const ADir, AName: string): string;
var
  Base, Ext: string;
  N: Integer;
begin
  Base := ChangeFileExt(SafeFileName(AName), '');
  Ext := ExtractFileExt(SafeFileName(AName));
  if Base = '' then
    Base := 'image';
  Result := TPath.Combine(ADir, Base + Ext);
  N := 2;
  while TFile.Exists(Result) or TDirectory.Exists(Result) do
  begin
    Result := TPath.Combine(ADir, Format('%s (%d)%s', [Base, N, Ext]));
    Inc(N);
  end;
end;

function StampName(const AExt: string): string;
begin
  Result := 'image_' + FormatDateTime('yyyymmdd_hhnnss', Now) + AExt;
end;

function NameFromUrl(const AUrl, AExt: string): string;
var
  Leaf, Ext: string;
begin
  Leaf := SafeFileName(AUrl);
  Ext := ExtractFileExt(Leaf);
  if Ext = '' then
  begin
    if AExt <> '' then
      Leaf := ChangeFileExt(Leaf, AExt)
    else
      Leaf := StampName('.img');
  end;
  if SameText(Leaf, 'image') or (Length(Leaf) > 80) then
    Leaf := StampName(ExtractFileExt(Leaf));
  Result := Leaf;
end;

procedure EnsureExt(var AName: string; const ABytes: TBytes; const AMime: string);
var
  Ext, Sig: string;
begin
  Sig := ExtFromSignature(ABytes);
  Ext := ExtractFileExt(AName);
  if Sig <> '' then
  begin
    if (Ext = '') or SameText(Ext, '.img') or SameText(Ext, '.bin') then
      AName := ChangeFileExt(AName, Sig);
    Exit;
  end;
  if Ext <> '' then
    Exit;
  Ext := ExtFromMime(AMime);
  if Ext = '' then
    Ext := '.png';
  AName := ChangeFileExt(AName, Ext);
end;

function HDropToFiles(H: HDROP): TArray<string>;
var
  N, I, Len: Integer;
  Buf: array[0..MAX_PATH] of Char;
begin
  SetLength(Result, 0);
  if H = 0 then
    Exit;
  N := DragQueryFile(H, $FFFFFFFF, nil, 0);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    FillChar(Buf, SizeOf(Buf), 0);
    Len := DragQueryFile(H, I, Buf, MAX_PATH);
    if Len > 0 then
      Result[I] := string(Buf)
    else
      Result[I] := '';
  end;
end;

function FileUrlToPath(const AUrl: string): string;
var
  U: string;
begin
  Result := '';
  U := Trim(AUrl);
  if not StartsText('file:', U) then
    Exit;
  if StartsText('file:///', U) then
    Delete(U, 1, 8)
  else if StartsText('file://', U) then
    Delete(U, 1, 7)
  else
    Delete(U, 1, 5);
  U := StringReplace(U, '/', '\', [rfReplaceAll]);
  try
    U := TNetEncoding.URL.Decode(U);
  except
  end;
  Result := U;
end;

function ExtractFirstHttpImg(const AHtml: string): string;
var
  Low, Tag, Src: string;
  P, TagEnd, SrcPos, Q: Integer;
  Quote: Char;
begin
  Result := '';
  Low := LowerCase(AHtml);
  P := 1;
  while True do
  begin
    P := PosEx('<img', Low, P);
    if P <= 0 then
      Exit;
    TagEnd := PosEx('>', AHtml, P);
    if TagEnd <= 0 then
      TagEnd := Length(AHtml);
    Tag := Copy(AHtml, P, TagEnd - P + 1);
    SrcPos := Pos('src=', LowerCase(Tag));
    if SrcPos > 0 then
    begin
      SrcPos := SrcPos + 4;
      while (SrcPos <= Length(Tag)) and (Tag[SrcPos] <= ' ') do
        Inc(SrcPos);
      if SrcPos <= Length(Tag) then
      begin
        Quote := Tag[SrcPos];
        if (Quote = '"') or (Quote = '''') then
        begin
          Inc(SrcPos);
          Q := SrcPos;
          while (Q <= Length(Tag)) and (Tag[Q] <> Quote) do
            Inc(Q);
          Src := Copy(Tag, SrcPos, Q - SrcPos);
        end
        else
        begin
          Q := SrcPos;
          while (Q <= Length(Tag)) and not CharInSet(Tag[Q], [' ', '>', #9, #10, #13]) do
            Inc(Q);
          Src := Copy(Tag, SrcPos, Q - SrcPos);
        end;
        Src := Trim(Src);
        if StartsText('http://', Src) or StartsText('https://', Src) or StartsText('file:', Src) then
          Exit(Src);
      end;
    end;
    P := TagEnd + 1;
  end;
end;

function DibToPngBytes(H: HGLOBAL): TBytes;
var
  Bmp: Vcl.Graphics.TBitmap;
  Png: TPngImage;
  MS: TMemoryStream;
begin
  SetLength(Result, 0);
  if H = 0 then
    Exit;
  Bmp := Vcl.Graphics.TBitmap.Create;
  Png := TPngImage.Create;
  MS := TMemoryStream.Create;
  try
    try
      Bmp.LoadFromClipboardFormat(CF_DIB, H, 0);
      if (Bmp.Width < 1) or (Bmp.Height < 1) then
        Exit;
      Png.Assign(Bmp);
      Png.SaveToStream(MS);
      SetLength(Result, MS.Size);
      if MS.Size > 0 then
      begin
        MS.Position := 0;
        MS.ReadBuffer(Result[0], MS.Size);
      end;
    except
      SetLength(Result, 0);
    end;
  finally
    MS.Free;
    Png.Free;
    Bmp.Free;
  end;
end;

function BitmapHandleToPng(ABmp: HBITMAP): TBytes;
var
  Bmp: Vcl.Graphics.TBitmap;
  Png: TPngImage;
  MS: TMemoryStream;
begin
  SetLength(Result, 0);
  if ABmp = 0 then
    Exit;
  Bmp := Vcl.Graphics.TBitmap.Create;
  Png := TPngImage.Create;
  MS := TMemoryStream.Create;
  try
    try
      Bmp.Handle := ABmp;
      if (Bmp.Width < 1) or (Bmp.Height < 1) then
      begin
        Bmp.ReleaseHandle;
        Exit;
      end;
      Png.Assign(Bmp);
      Png.SaveToStream(MS);
      SetLength(Result, MS.Size);
      if MS.Size > 0 then
      begin
        MS.Position := 0;
        MS.ReadBuffer(Result[0], MS.Size);
      end;
      Bmp.ReleaseHandle;
    except
      try
        Bmp.ReleaseHandle;
      except
      end;
      SetLength(Result, 0);
    end;
  finally
    MS.Free;
    Png.Free;
    Bmp.Free;
  end;
end;

procedure AddBytesItem(var AItems: TArray<TDropItem>; const AName: string; const ABytes: TBytes);
var
  N: Integer;
  It: TDropItem;
begin
  if Length(ABytes) = 0 then
    Exit;
  It := Default(TDropItem);
  It.Kind := dkBytes;
  It.Name := AName;
  It.Bytes := ABytes;
  N := Length(AItems);
  SetLength(AItems, N + 1);
  AItems[N] := It;
end;

procedure AddUrlItem(var AItems: TArray<TDropItem>; const AUrl, AName: string);
var
  N: Integer;
  It: TDropItem;
  Path, U: string;
begin
  U := Trim(AUrl);
  if U = '' then
    Exit;
  Path := FileUrlToPath(U);
  if (Path <> '') and TFile.Exists(Path) then
  begin
    It := Default(TDropItem);
    It.Kind := dkHDrop;
    It.Name := ExtractFileName(Path);
    It.Url := Path;
    N := Length(AItems);
    SetLength(AItems, N + 1);
    AItems[N] := It;
    Exit;
  end;
  if not (StartsText('http://', U) or StartsText('https://', U)) then
    Exit;
  It := Default(TDropItem);
  It.Kind := dkUrl;
  It.Url := U;
  It.Name := AName;
  N := Length(AItems);
  SetLength(AItems, N + 1);
  AItems[N] := It;
end;

function ReadFileContents(const Data: IDataObject; AIndex: Integer): TBytes;
var
  Med: TStgMedium;
  Stm: IStream;
begin
  SetLength(Result, 0);
  if GetMedium(Data, CF_FILECONTENTS, AIndex, TYMED_ISTREAM or TYMED_HGLOBAL, Med) then
  try
    if (Med.tymed and TYMED_ISTREAM) <> 0 then
    begin
      Stm := IStream(Med.stm);
      Result := StreamToBytes(Stm);
    end
    else if (Med.tymed and TYMED_HGLOBAL) <> 0 then
      Result := BytesFromGlobal(Med.hGlobal);
  finally
    ReleaseStgMedium(Med);
  end;
end;

function CollectFromDescriptorW(const Data: IDataObject): TArray<TDropItem>;
var
  Med: TStgMedium;
  Base: PByte;
  N: NativeUInt;
  Count, MaxCount, I: Integer;
  Desc: PFileDescriptorW;
  Name: string;
  Bytes: TBytes;
begin
  SetLength(Result, 0);
  if not GetMedium(Data, CF_FILEDESCRIPTORW, -1, TYMED_HGLOBAL, Med) then
    Exit;
  try
    Base := GlobalToRaw(Med.hGlobal, N);
    if (Base = nil) or (N < SizeOf(UINT)) then
      Exit;
    try
      Count := Integer(PUINT(Base)^);
      MaxCount := Integer((N - SizeOf(UINT)) div NativeUInt(SizeOf(TFileDescriptorW)));
      if Count > MaxCount then
        Count := MaxCount;
      for I := 0 to Count - 1 do
      begin
        Desc := PFileDescriptorW(Base + SizeOf(UINT) + NativeInt(I) * SizeOf(TFileDescriptorW));
        if ((Desc.dwFlags and FD_ATTRIBUTES) <> 0) and
           ((Desc.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) then
          Continue;
        Name := SafeFileName(string(Desc.cFileName));
        Bytes := ReadFileContents(Data, I);
        AddBytesItem(Result, Name, Bytes);
      end;
    finally
      GlobalUnlock(Med.hGlobal);
    end;
  finally
    ReleaseStgMedium(Med);
  end;
end;

function CollectFromDescriptorA(const Data: IDataObject): TArray<TDropItem>;
var
  Med: TStgMedium;
  Base: PByte;
  N: NativeUInt;
  Count, MaxCount, I: Integer;
  Desc: PFileDescriptorA;
  Name: string;
  Bytes: TBytes;
begin
  SetLength(Result, 0);
  if not GetMedium(Data, CF_FILEDESCRIPTORA, -1, TYMED_HGLOBAL, Med) then
    Exit;
  try
    Base := GlobalToRaw(Med.hGlobal, N);
    if (Base = nil) or (N < SizeOf(UINT)) then
      Exit;
    try
      Count := Integer(PUINT(Base)^);
      MaxCount := Integer((N - SizeOf(UINT)) div NativeUInt(SizeOf(TFileDescriptorA)));
      if Count > MaxCount then
        Count := MaxCount;
      for I := 0 to Count - 1 do
      begin
        Desc := PFileDescriptorA(Base + SizeOf(UINT) + NativeInt(I) * SizeOf(TFileDescriptorA));
        if ((Desc.dwFlags and FD_ATTRIBUTES) <> 0) and
           ((Desc.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) then
          Continue;
        Name := SafeFileName(string(Desc.cFileName));
        Bytes := ReadFileContents(Data, I);
        AddBytesItem(Result, Name, Bytes);
      end;
    finally
      GlobalUnlock(Med.hGlobal);
    end;
  finally
    ReleaseStgMedium(Med);
  end;
end;

function CollectUrls(const Data: IDataObject): TArray<TDropItem>;
var
  Med: TStgMedium;
  S, Line: string;
  SL: TStringList;
  I: Integer;
begin
  SetLength(Result, 0);
  if GetMedium(Data, CF_INETURLW, -1, TYMED_HGLOBAL, Med) then
  try
    AddUrlItem(Result, Trim(WideFromGlobal(Med.hGlobal)), '');
  finally
    ReleaseStgMedium(Med);
  end;
  if Length(Result) > 0 then
    Exit;
  if GetMedium(Data, CF_INETURLA, -1, TYMED_HGLOBAL, Med) then
  try
    AddUrlItem(Result, Trim(AnsiFromGlobal(Med.hGlobal)), '');
  finally
    ReleaseStgMedium(Med);
  end;
  if Length(Result) > 0 then
    Exit;
  if GetMedium(Data, CF_MOZURL, -1, TYMED_HGLOBAL, Med) then
  try
    S := WideFromGlobal(Med.hGlobal);
    if S = '' then
      S := Utf8FromGlobal(Med.hGlobal);
    SL := TStringList.Create;
    try
      SL.Text := S;
      if SL.Count > 0 then
        AddUrlItem(Result, Trim(SL[0]), '');
    finally
      SL.Free;
    end;
  finally
    ReleaseStgMedium(Med);
  end;
  if Length(Result) > 0 then
    Exit;
  if GetMedium(Data, CF_URILIST, -1, TYMED_HGLOBAL, Med) then
  try
    S := Utf8FromGlobal(Med.hGlobal);
    if S = '' then
      S := AnsiFromGlobal(Med.hGlobal);
    SL := TStringList.Create;
    try
      SL.Text := S;
      for I := 0 to SL.Count - 1 do
      begin
        Line := Trim(SL[I]);
        if (Line = '') or StartsText('#', Line) then
          Continue;
        AddUrlItem(Result, Line, '');
        if Length(Result) > 0 then
          Break;
      end;
    finally
      SL.Free;
    end;
  finally
    ReleaseStgMedium(Med);
  end;
end;

function CollectHtmlImg(const Data: IDataObject): TArray<TDropItem>;
var
  Med: TStgMedium;
  Html, Src: string;
begin
  SetLength(Result, 0);
  if not GetMedium(Data, CF_HTML, -1, TYMED_HGLOBAL, Med) then
    Exit;
  try
    Html := Utf8FromGlobal(Med.hGlobal);
    Src := ExtractFirstHttpImg(Html);
    AddUrlItem(Result, Src, '');
  finally
    ReleaseStgMedium(Med);
  end;
end;

function CollectRaster(const Data: IDataObject): TArray<TDropItem>;
var
  Med: TStgMedium;
  Bytes: TBytes;
begin
  SetLength(Result, 0);
  if GetMedium(Data, CF_PNG, -1, TYMED_HGLOBAL, Med) or
     GetMedium(Data, CF_IMAGEPNG, -1, TYMED_HGLOBAL, Med) then
  try
    Bytes := BytesFromGlobal(Med.hGlobal);
    AddBytesItem(Result, StampName('.png'), Bytes);
  finally
    ReleaseStgMedium(Med);
  end;
  if Length(Result) > 0 then
    Exit;
  if GetMedium(Data, CF_DIB, -1, TYMED_HGLOBAL, Med) then
  try
    Bytes := DibToPngBytes(Med.hGlobal);
    AddBytesItem(Result, StampName('.png'), Bytes);
  finally
    ReleaseStgMedium(Med);
  end;
  if Length(Result) > 0 then
    Exit;
  if GetMedium(Data, CF_BITMAP, -1, TYMED_GDI, Med) then
  try
    Bytes := BitmapHandleToPng(Med.hBitmap);
    AddBytesItem(Result, StampName('.png'), Bytes);
  finally
    ReleaseStgMedium(Med);
  end;
end;

function CollectHDrop(const Data: IDataObject): TArray<string>;
var
  Med: TStgMedium;
begin
  SetLength(Result, 0);
  if not GetMedium(Data, CF_HDROP, -1, TYMED_HGLOBAL, Med) then
    Exit;
  try
    Result := HDropToFiles(HDROP(Med.hGlobal));
  finally
    ReleaseStgMedium(Med);
  end;
end;

function ParseBrowserDrop(const Data: IDataObject; out AItems: TArray<TDropItem>): Boolean;
begin
  AItems := CollectFromDescriptorW(Data);
  if Length(AItems) = 0 then
    AItems := CollectFromDescriptorA(Data);
  if Length(AItems) = 0 then
    AItems := CollectUrls(Data);
  if Length(AItems) = 0 then
    AItems := CollectHtmlImg(Data);
  if Length(AItems) = 0 then
    AItems := CollectRaster(Data);
  Result := Length(AItems) > 0;
end;

procedure DownloadUrl(const AUrl: string; out ABytes: TBytes; out AMime: string);
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
  MS: TMemoryStream;
  Aborted: Boolean;
begin
  SetLength(ABytes, 0);
  AMime := '';
  Aborted := False;
  Http := THTTPClient.Create;
  MS := TMemoryStream.Create;
  try
    Http.UserAgent := BrowserUA;
    Http.ConnectionTimeout := 15000;
    Http.ResponseTimeout := DropTimeoutMs;
    Http.HandleRedirects := True;
    Http.ReceiveDataCallBack :=
      procedure(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean)
      begin
        if (AContentLength > MaxDropBytes) or (AReadCount > MaxDropBytes) then
        begin
          Aborted := True;
          AAbort := True;
        end;
      end;
    Resp := Http.Get(AUrl, MS);
    if Aborted then
      raise Exception.Create('Файл слишком большой (лимит 100 МБ)');
    if (Resp = nil) or (Resp.StatusCode < 200) or (Resp.StatusCode >= 300) then
    begin
      if Resp <> nil then
        raise Exception.Create('HTTP ' + IntToStr(Resp.StatusCode))
      else
        raise Exception.Create('Нет ответа сервера');
    end;
    if MS.Size > MaxDropBytes then
      raise Exception.Create('Файл слишком большой (лимит 100 МБ)');
    AMime := Resp.MimeType;
    SetLength(ABytes, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.ReadBuffer(ABytes[0], MS.Size);
    end;
    if MimeLooksLikeHtml(AMime) and (ExtFromSignature(ABytes) = '') then
    begin
      SetLength(ABytes, 0);
      raise Exception.Create('Браузер не отдал файл');
    end;
  finally
    MS.Free;
    Http.Free;
  end;
end;

procedure SaveItems(const ADest: string; const AItems: TArray<TDropItem>;
  out AFiles: TArray<string>);
var
  I: Integer;
  Name, Path: string;
  Bytes: TBytes;
  Mime: string;
  FS: TFileStream;
begin
  SetLength(AFiles, 0);
  for I := 0 to High(AItems) do
  begin
    Bytes := nil;
    Mime := '';
    Name := AItems[I].Name;
    if AItems[I].Kind = dkHDrop then
    begin
      if TFile.Exists(AItems[I].Url) then
      begin
        Name := ExtractFileName(AItems[I].Url);
        Path := UniqueDestPath(ADest, Name);
        TFile.Copy(AItems[I].Url, Path, False);
        SetLength(AFiles, Length(AFiles) + 1);
        AFiles[High(AFiles)] := Path;
      end;
      Continue;
    end;
    if AItems[I].Kind = dkUrl then
    begin
      DownloadUrl(AItems[I].Url, Bytes, Mime);
      if Name = '' then
        Name := NameFromUrl(AItems[I].Url, ExtFromMime(Mime));
    end
    else
      Bytes := AItems[I].Bytes;
    if Length(Bytes) = 0 then
      Continue;
    EnsureExt(Name, Bytes, Mime);
    Path := UniqueDestPath(ADest, Name);
    FS := TFileStream.Create(Path, fmCreate);
    try
      FS.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
    SetLength(AFiles, Length(AFiles) + 1);
    AFiles[High(AFiles)] := Path;
  end;
end;

constructor TBrowserDropJob.Create(APanel: TFilePanel; const ADest: string;
  AGen: Integer; const AItems: TArray<TDropItem>);
begin
  inherited Create;
  FPanel := APanel;
  FDest := ADest;
  FGen := AGen;
  FItems := AItems;
end;

procedure TBrowserDropJob.Run;
var
  Saved: TArray<string>;
  Err: string;
begin
  Err := '';
  try
    try
      SaveItems(FDest, FItems, Saved);
    except
      on E: Exception do
        Err := E.Message;
    end;
    TThread.Queue(nil,
      procedure
      var
        F: string;
      begin
        try
          if Err <> '' then
          begin
            for F in Saved do
            try
              if TFile.Exists(F) then
                TFile.Delete(F);
            except
            end;
            if (FGen = GDropGen) and not PanelClosing(FPanel) then
              FPanel.ShowNotice(Err);
            Exit;
          end;
          if FGen <> GDropGen then
            Exit;
          if Length(Saved) = 0 then
          begin
            if not PanelClosing(FPanel) then
              FPanel.ShowNotice('Браузер не отдал файл');
            Exit;
          end;
          if not PanelClosing(FPanel) then
            FPanel.FinishBrowserFiles(FDest, Saved);
        finally
          Self.Free;
        end;
      end);
  except
    Free;
  end;
end;

function CaptureFmxDropTarget(AForm: TCommonCustomForm): IDropTarget;
var
  Ctx: TRttiContext;
  H: TWinWindowHandle;
  Fld: TRttiField;
  Obj: TObject;
begin
  Result := nil;
  if (AForm = nil) or (AForm.Handle = nil) then
    Exit;
  H := WindowHandleToPlatform(AForm.Handle);
  if H = nil then
    Exit;
  Fld := Ctx.GetType(TWinWindowHandle).GetField('FWinDropTarget');
  if Fld = nil then
    Exit;
  Obj := Fld.GetValue(H).AsObject;
  if Obj <> nil then
    Obj.GetInterface(IDropTarget, Result);
end;

constructor TFormDropTarget.Create(AForm: TCommonCustomForm);
begin
  inherited Create;
  FForm := AForm;
  FHover := nil;
end;

function TFormDropTarget.ScreenOf(const pt: TPoint): TPointF;
begin
  Result := PxToDp(pt);
end;

function TFormDropTarget.PanelOk(APanel: TFilePanel): Boolean;
begin
  Result := Assigned(APanel) and not PanelClosing(APanel);
end;

function TFormDropTarget.TrackAt(const pt: TPoint; ABrowser: Boolean;
  out ADest: string; out APanel: TFilePanel): Boolean;
var
  ScreenPt: TPointF;
begin
  Result := False;
  ADest := '';
  APanel := nil;
  ScreenPt := ScreenOf(pt);
  APanel := TFilePanel.HitAtScreen(FForm, ScreenPt);
  if APanel = nil then
  begin
    ClearHover;
    Exit;
  end;
  if (FHover <> nil) and (FHover <> APanel) then
    FHover.SetDropHot(False);
  FHover := APanel;
  Result := APanel.TrackExternalDrop(ScreenPt, ABrowser, ADest);
  if not Result then
    APanel := nil;
end;

procedure TFormDropTarget.ClearHover;
begin
  if PanelOk(FHover) then
    FHover.SetDropHot(False);
  FHover := nil;
end;

function TFormDropTarget.DragEnter(const dataObj: IDataObject; grfKeyState: Longint;
  pt: TPoint; var dwEffect: Longint): HResult;
var
  Dest: string;
  Panel: TFilePanel;
begin
  dwEffect := DROPEFFECT_NONE;
  Result := S_OK;
  FBrowser := False;
  if FileDragIsActive then
    Exit;
  { BeginAutoDrag вкладки отдаёт CF_BITMAP (скриншот) — это FMX, не браузер. }
  if IsFmxInternalDrag(dataObj) then
  begin
    if FInner <> nil then
      Result := FInner.DragEnter(dataObj, grfKeyState, pt, dwEffect);
    Exit;
  end;
  if HasFormat(dataObj, CF_HDROP, -1, TYMED_HGLOBAL) then
  begin
    if FInner <> nil then
      Result := FInner.DragEnter(dataObj, grfKeyState, pt, dwEffect)
    else if TrackAt(pt, False, Dest, Panel) then
      dwEffect := DROPEFFECT_COPY;
    Exit;
  end;
  if not BrowserFormatsPresent(dataObj) then
  begin
    if FInner <> nil then
      Result := FInner.DragEnter(dataObj, grfKeyState, pt, dwEffect);
    Exit;
  end;
  FBrowser := True;
  if TrackAt(pt, True, Dest, Panel) then
    dwEffect := DROPEFFECT_COPY;
end;

function TFormDropTarget.DragOver(grfKeyState: Longint; pt: TPoint;
  var dwEffect: Longint): HResult;
var
  Dest: string;
  Panel: TFilePanel;
begin
  dwEffect := DROPEFFECT_NONE;
  Result := S_OK;
  if FileDragIsActive then
    Exit;
  if IsTabDragActive then
  begin
    if FInner <> nil then
      Result := FInner.DragOver(grfKeyState, pt, dwEffect);
    Exit;
  end;
  if not FBrowser then
  begin
    if FInner <> nil then
      Result := FInner.DragOver(grfKeyState, pt, dwEffect)
    else if TrackAt(pt, False, Dest, Panel) then
      dwEffect := DROPEFFECT_COPY;
    Exit;
  end;
  if TrackAt(pt, True, Dest, Panel) then
    dwEffect := DROPEFFECT_COPY;
end;

function TFormDropTarget.DragLeave: HResult;
begin
  ClearHover;
  Result := S_OK;
  if ((not FBrowser) or IsTabDragActive) and (FInner <> nil) then
    Result := FInner.DragLeave;
  FBrowser := False;
end;

function TFormDropTarget.Drop(const dataObj: IDataObject; grfKeyState: Longint;
  pt: TPoint; var dwEffect: Longint): HResult;
var
  Dest: string;
  Panel: TFilePanel;
  Items: TArray<TDropItem>;
  HFiles: TArray<string>;
begin
  dwEffect := DROPEFFECT_NONE;
  Result := S_OK;
  try
    if FileDragIsActive then
      Exit;
    if IsTabDragActive then
    begin
      ClearHover;
      if FInner <> nil then
        Result := FInner.Drop(dataObj, grfKeyState, pt, dwEffect);
      FBrowser := False;
      Exit;
    end;
    if not FBrowser then
    begin
      ClearHover;
      if FInner <> nil then
        Result := FInner.Drop(dataObj, grfKeyState, pt, dwEffect)
      else
      begin
        TrackAt(pt, False, Dest, Panel);
        ClearHover;
        if PanelOk(Panel) and (Dest <> '') then
        begin
          HFiles := CollectHDrop(dataObj);
          if (Length(HFiles) > 0) and Panel.CanDropTo(Dest, HFiles) then
          begin
            dwEffect := DROPEFFECT_COPY;
            if Assigned(Panel.OnActivate) then
              Panel.OnActivate(Panel);
            Panel.ApplyDrop(Dest, HFiles, (grfKeyState and MK_SHIFT) <> 0, nil);
          end;
        end;
      end;
      Exit;
    end;

    TrackAt(pt, True, Dest, Panel);
    ClearHover;
    FBrowser := False;
    if (not PanelOk(Panel)) or (Dest = '') then
      Exit;
    if not Panel.CanDropBrowserDest(Dest) then
      Exit;

    if not ParseBrowserDrop(dataObj, Items) then
    begin
      Panel.ShowNotice('Браузер не отдал файл');
      Exit;
    end;

    dwEffect := DROPEFFECT_COPY;
    if Assigned(Panel.OnActivate) then
      Panel.OnActivate(Panel);
    TThread.CreateAnonymousThread(TBrowserDropJob.Create(Panel, Dest, GDropGen, Items).Run).Start;
  except
    on E: Exception do
      if PanelOk(Panel) then
        Panel.ShowNotice(E.Message);
  end;
end;

procedure InstallFormDropTarget(AForm: TCommonCustomForm);
var
  Wnd: HWND;
  Target: TFormDropTarget;
begin
  if AForm = nil then
    Exit;
  Wnd := FormToHWND(AForm);
  if Wnd = 0 then
    Exit;
  UninstallFormDropTarget(AForm);
  Target := TFormDropTarget.Create(AForm);
  Target.FInner := CaptureFmxDropTarget(AForm);
  GDrop := Target;
  GDropWnd := Wnd;
  RevokeDragDrop(Wnd);
  if Failed(RegisterDragDrop(Wnd, GDrop)) then
  begin
    GDrop := nil;
    GDropWnd := 0;
  end;
end;

procedure UninstallFormDropTarget(AForm: TCommonCustomForm);
var
  Wnd: HWND;
begin
  Inc(GDropGen);
  Wnd := GDropWnd;
  if (AForm <> nil) and (FormToHWND(AForm) <> 0) then
    Wnd := FormToHWND(AForm);
  if Wnd <> 0 then
    RevokeDragDrop(Wnd);
  GDrop := nil;
  GDropWnd := 0;
end;

initialization
  CF_FILEDESCRIPTORW := TClipFormat(RegisterClipboardFormat(CFSTR_FILEDESCRIPTORW));
  CF_FILEDESCRIPTORA := TClipFormat(RegisterClipboardFormat(CFSTR_FILEDESCRIPTORA));
  CF_FILECONTENTS := TClipFormat(RegisterClipboardFormat(CFSTR_FILECONTENTS));
  CF_INETURLW := TClipFormat(RegisterClipboardFormat(CFSTR_INETURLW));
  CF_INETURLA := TClipFormat(RegisterClipboardFormat(CFSTR_INETURLA));
  CF_URILIST := TClipFormat(RegisterClipboardFormat('text/uri-list'));
  CF_MOZURL := TClipFormat(RegisterClipboardFormat('text/x-moz-url'));
  CF_HTML := TClipFormat(RegisterClipboardFormat('HTML Format'));
  CF_PNG := TClipFormat(RegisterClipboardFormat('PNG'));
  CF_IMAGEPNG := TClipFormat(RegisterClipboardFormat('image/png'));

{$ENDIF}

end.
