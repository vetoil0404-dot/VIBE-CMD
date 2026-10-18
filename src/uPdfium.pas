unit uPdfium;

{
  Тонкая обёртка pdfium.dll: загрузка PDF / PDF-based AI и рендер страницы в TBitmap.
}

interface

uses
  System.SysUtils, System.Classes, System.Math, FMX.Graphics, FMX.Types,
  System.UITypes, System.Types;

type
  TPdfiumDoc = class
  private
    FDoc: Pointer;
    FCount: Integer;
    FPath: string;
    function ReadPagePoints(AIndex: Integer; out AWf, AHf: Double): Boolean;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;
    { AScaleCap > 0 — потолок масштаба (плитка, 2.5). 0 — ровно в заданные пиксели. }
    function RenderPageRaw(AIndex, AMaxW, AMaxH: Integer; out APixels: TBytes;
      out AWidth, AHeight: Integer; AScaleCap: Double = 2.5): Boolean;
    function RenderPage(AIndex, AMaxW, AMaxH: Integer;
      AScaleCap: Double = 2.5): TBitmap;
    function PagePointSize(AIndex: Integer; out W, H: Integer): Boolean;
    { Пиксели Round(pt / 72 × dpi). Не размер битмапа. }
    function PagePixelSize(AIndex, ADpi: Integer; out W, H: Integer): Boolean;
    { QV: рендер в печатных пикселях 300 dpi, длинная сторона не больше 4096.
      Наружу — полный расчёт, даже если битмап ужат. }
    function RenderPagePrint(AIndex: Integer;
      out APrintW, APrintH, APointW, APointH: Integer): TBitmap;
    property PageCount: Integer read FCount;
    property FilePath: string read FPath;
    class function Available: Boolean; static;
    class function LooksLikePdfFamily(const APath: string): Boolean; static;
  end;

function IsPdfThumbExt(const APath: string): Boolean;
procedure FillBitmapFromBgra(ABitmap: FMX.Graphics.TBitmap; const APixels: TBytes;
  AWidth, AHeight: Integer);
function RenderPdfThumbRaw(const APath: string; AMaxW, AMaxH: Integer;
  out APixels: TBytes; out AWidth, AHeight: Integer): Boolean;
function RenderPdfThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap): Boolean;
{ Первая страница в пунктах PDF, округлённых до целых. }
function TryPdfPageSize(const APath: string; out W, H: Integer): Boolean;
{ Первая страница в печатных пикселях: Round(pt / 72 × 300). Для подписи плитки. }
function TryPdfPrintSize(const APath: string; out W, H: Integer): Boolean;

implementation

uses
  System.SyncObjs, uLang
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

var
  GPdfLock: TCriticalSection;

procedure PdfEnter;
begin
  if GPdfLock = nil then
    GPdfLock := TCriticalSection.Create;
  GPdfLock.Enter;
end;

procedure PdfLeave;
begin
  if GPdfLock <> nil then
    GPdfLock.Leave;
end;

{$IFDEF MSWINDOWS}
const
  FPDF_REVERSE_BYTE_ORDER = $10;
  FPDF_ANNOT = $01;
  FPDF_LCD_TEXT = $02;

type
  FPDF_DOCUMENT = Pointer;
  FPDF_PAGE = Pointer;
  FPDF_BITMAP = Pointer;

  TFPDF_InitLibrary = procedure; cdecl;
  TFPDF_DestroyLibrary = procedure; cdecl;
  TFPDF_LoadDocument = function(file_path, password: PAnsiChar): FPDF_DOCUMENT; cdecl;
  TFPDF_LoadMemDocument = function(data: Pointer; size: Integer; password: PAnsiChar): FPDF_DOCUMENT; cdecl;
  TFPDF_GetPageCount = function(doc: FPDF_DOCUMENT): Integer; cdecl;
  TFPDF_LoadPage = function(doc: FPDF_DOCUMENT; page_index: Integer): FPDF_PAGE; cdecl;
  TFPDF_ClosePage = procedure(page: FPDF_PAGE); cdecl;
  TFPDF_CloseDocument = procedure(doc: FPDF_DOCUMENT); cdecl;
  TFPDF_GetPageWidth = function(page: FPDF_PAGE): Double; cdecl;
  TFPDF_GetPageHeight = function(page: FPDF_PAGE): Double; cdecl;
  TFPDFBitmap_Create = function(width, height, alpha: Integer): FPDF_BITMAP; cdecl;
  TFPDFBitmap_FillRect = procedure(bitmap: FPDF_BITMAP; left, top, width, height: Integer;
    color: Cardinal); cdecl;
  TFPDFBitmap_GetBuffer = function(bitmap: FPDF_BITMAP): Pointer; cdecl;
  TFPDFBitmap_GetStride = function(bitmap: FPDF_BITMAP): Integer; cdecl;
  TFPDFBitmap_Destroy = procedure(bitmap: FPDF_BITMAP); cdecl;
  TFPDF_RenderPageBitmap = procedure(bitmap: FPDF_BITMAP; page: FPDF_PAGE;
    start_x, start_y, size_x, size_y, rotate, flags: Integer); cdecl;

var
  GLib: HMODULE = 0;
  GReady: Integer = 0;
  FPDF_InitLibrary: TFPDF_InitLibrary = nil;
  FPDF_DestroyLibrary: TFPDF_DestroyLibrary = nil;
  FPDF_LoadDocument: TFPDF_LoadDocument = nil;
  FPDF_LoadMemDocument: TFPDF_LoadMemDocument = nil;
  FPDF_GetPageCount: TFPDF_GetPageCount = nil;
  FPDF_LoadPage: TFPDF_LoadPage = nil;
  FPDF_ClosePage: TFPDF_ClosePage = nil;
  FPDF_CloseDocument: TFPDF_CloseDocument = nil;
  FPDF_GetPageWidth: TFPDF_GetPageWidth = nil;
  FPDF_GetPageHeight: TFPDF_GetPageHeight = nil;
  FPDFBitmap_Create: TFPDFBitmap_Create = nil;
  FPDFBitmap_FillRect: TFPDFBitmap_FillRect = nil;
  FPDFBitmap_GetBuffer: TFPDFBitmap_GetBuffer = nil;
  FPDFBitmap_GetStride: TFPDFBitmap_GetStride = nil;
  FPDFBitmap_Destroy: TFPDFBitmap_Destroy = nil;
  FPDF_RenderPageBitmap: TFPDF_RenderPageBitmap = nil;

function Bind(const AName: AnsiString): Pointer;
begin
  Result := GetProcAddress(GLib, PAnsiChar(AName));
end;

function FindSidecarDll(const AName: string): string;
var
  Dir, Cand, Parent: string;
  I: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  for I := 0 to 4 do
  begin
    Cand := Dir + PathDelim + AName;
    if FileExists(Cand) then
      Exit(Cand);
    Parent := ExcludeTrailingPathDelimiter(ExpandFileName(Dir + PathDelim + '..'));
    if (Parent = '') or SameText(Parent, Dir) then
      Break;
    Dir := Parent;
  end;
  Result := AName;
end;

procedure FillBitmapFromBgra(ABitmap: FMX.Graphics.TBitmap; const APixels: TBytes;
  AWidth, AHeight: Integer);
var
  Data: FMX.Graphics.TBitmapData;
  X, Y: Integer;
  S: PByte;
  Stride: Integer;
  Col: TAlphaColor;
begin
  { PDFium: байты B,G,R,A. В FMX пишем TAlphaColor через SetPixel —
    AlphaColorToPixel сам кладёт каналы в формат битмапа (BGRA или RGBA). }
  if (ABitmap = nil) or (AWidth < 1) or (AHeight < 1) then
    Exit;
  if Length(APixels) < AWidth * AHeight * 4 then
    Exit;
  try
    ABitmap.SetSize(AWidth, AHeight);
  except
    ABitmap.SetSize(0, 0);
    Exit;
  end;
  if not ABitmap.Map(TMapAccess.Write, Data) then
    Exit;
  try
    Stride := AWidth * 4;
    for Y := 0 to AHeight - 1 do
    begin
      S := @APixels[Y * Stride];
      for X := 0 to AWidth - 1 do
      begin
        Col := TAlphaColor((Cardinal(S[3]) shl 24) or (Cardinal(S[2]) shl 16) or
          (Cardinal(S[1]) shl 8) or Cardinal(S[0]));
        Data.SetPixel(X, Y, Col);
        Inc(S, 4);
      end;
    end;
  finally
    ABitmap.Unmap(Data);
  end;
end;

procedure CopyPdfBufferToBgraBytes(Src: Pointer; SrcStride, W, H: Integer; out Dest: TBytes);
var
  Y: Integer;
  RowBytes: Integer;
begin
  RowBytes := W * 4;
  SetLength(Dest, RowBytes * H);
  for Y := 0 to H - 1 do
    Move(Pointer(NativeUInt(Src) + NativeUInt(Y) * NativeUInt(SrcStride))^,
      Dest[Y * RowBytes], RowBytes);
end;

function EnsurePdfium: Boolean;
var
  Dll: string;
begin
  if GReady > 0 then
    Exit(True);
  if GReady < 0 then
    Exit(False);
  Dll := FindSidecarDll('pdfium.dll');
  GLib := LoadLibrary(PChar(Dll));
  if GLib = 0 then
  begin
    GReady := -1;
    Exit(False);
  end;
  FPDF_InitLibrary := Bind('FPDF_InitLibrary');
  FPDF_DestroyLibrary := Bind('FPDF_DestroyLibrary');
  FPDF_LoadDocument := Bind('FPDF_LoadDocument');
  FPDF_LoadMemDocument := Bind('FPDF_LoadMemDocument');
  FPDF_GetPageCount := Bind('FPDF_GetPageCount');
  FPDF_LoadPage := Bind('FPDF_LoadPage');
  FPDF_ClosePage := Bind('FPDF_ClosePage');
  FPDF_CloseDocument := Bind('FPDF_CloseDocument');
  FPDF_GetPageWidth := Bind('FPDF_GetPageWidth');
  FPDF_GetPageHeight := Bind('FPDF_GetPageHeight');
  FPDFBitmap_Create := Bind('FPDFBitmap_Create');
  FPDFBitmap_FillRect := Bind('FPDFBitmap_FillRect');
  FPDFBitmap_GetBuffer := Bind('FPDFBitmap_GetBuffer');
  FPDFBitmap_GetStride := Bind('FPDFBitmap_GetStride');
  FPDFBitmap_Destroy := Bind('FPDFBitmap_Destroy');
  FPDF_RenderPageBitmap := Bind('FPDF_RenderPageBitmap');
  if not Assigned(FPDF_InitLibrary) or not Assigned(FPDF_LoadDocument) or
     not Assigned(FPDF_RenderPageBitmap) then
  begin
    FreeLibrary(GLib);
    GLib := 0;
    GReady := -1;
    Exit(False);
  end;
  FPDF_InitLibrary();
  GReady := 1;
  Result := True;
end;
{$ENDIF}

class function TPdfiumDoc.Available: Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := EnsurePdfium;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

class function TPdfiumDoc.LooksLikePdfFamily(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: array[0..1023] of AnsiChar;
  N, I: Integer;
  S: AnsiString;
  Ext: string;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.pdf') and (Ext <> '.ai') then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := FS.Read(Buf[0], SizeOf(Buf));
    finally
      FS.Free;
    end;
  except
    Exit(False);
  end;
  if N <= 0 then
    Exit;
  SetString(S, PAnsiChar(@Buf[0]), N);
  if Copy(S, 1, 5) = '%PDF-' then
    Exit(True);
  Result := Pos(AnsiString('%PDF-'), S) > 0;
  if not Result and (Ext = '.ai') then
  begin
    for I := 1 to N do
      if (Buf[I - 1] < #9) and (Buf[I - 1] <> #0) then
        { binary AI — всё равно пробуем PDFium }
        Exit(True);
    Result := Pos(AnsiString('Illustrator'), S) > 0;
  end;
end;

constructor TPdfiumDoc.Create(const APath: string);
{$IFDEF MSWINDOWS}
var
  Utf8: UTF8String;
  Bytes: TBytes;
  FS: TFileStream;
{$ENDIF}
begin
  inherited Create;
  FDoc := nil;
  FCount := 0;
  FPath := APath;
  {$IFDEF MSWINDOWS}
  PdfEnter;
  try
    if not EnsurePdfium then
      raise Exception.Create(L('pdf.nodll'));
    Utf8 := UTF8String(APath);
    FDoc := FPDF_LoadDocument(PAnsiChar(Utf8), nil);
    if (FDoc = nil) and Assigned(FPDF_LoadMemDocument) then
    begin
      FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
      try
        SetLength(Bytes, FS.Size);
        if Length(Bytes) > 0 then
          FS.ReadBuffer(Bytes[0], Length(Bytes));
      finally
        FS.Free;
      end;
      if Length(Bytes) > 0 then
        FDoc := FPDF_LoadMemDocument(@Bytes[0], Length(Bytes), nil);
    end;
    if FDoc = nil then
      raise Exception.Create(L('pdf.openfail'));
    FCount := FPDF_GetPageCount(FDoc);
    if FCount < 1 then
      FCount := 0;
  finally
    PdfLeave;
  end;
  {$ELSE}
  raise Exception.Create(L('pdf.windows'));
  {$ENDIF}
end;

destructor TPdfiumDoc.Destroy;
begin
  {$IFDEF MSWINDOWS}
  PdfEnter;
  try
    if (FDoc <> nil) and Assigned(FPDF_CloseDocument) then
      FPDF_CloseDocument(FDoc);
    FDoc := nil;
  finally
    PdfLeave;
  end;
  {$ENDIF}
  inherited;
end;

function TPdfiumDoc.RenderPageRaw(AIndex, AMaxW, AMaxH: Integer; out APixels: TBytes;
  out AWidth, AHeight: Integer; AScaleCap: Double): Boolean;
{$IFDEF MSWINDOWS}
var
  Page: FPDF_PAGE;
  Bmp: FPDF_BITMAP;
  Wf, Hf, Scale: Double;
  W, H, Stride: Integer;
  Buf: Pointer;
  Bg: Cardinal;
{$ENDIF}
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  {$IFDEF MSWINDOWS}
  PdfEnter;
  try
    if (FDoc = nil) or (AIndex < 0) or (AIndex >= FCount) then
      Exit;
    Page := FPDF_LoadPage(FDoc, AIndex);
    if Page = nil then
      Exit;
    try
      Wf := FPDF_GetPageWidth(Page);
      Hf := FPDF_GetPageHeight(Page);
      if (Wf < 1) or (Hf < 1) then
        Exit;
      if AScaleCap > 0 then
      begin
        if AMaxW < 32 then
          AMaxW := 256;
        if AMaxH < 32 then
          AMaxH := 256;
      end
      else
      begin
        if AMaxW < 1 then
          AMaxW := 1;
        if AMaxH < 1 then
          AMaxH := 1;
      end;
      Scale := Min(AMaxW / Wf, AMaxH / Hf);
      if Scale <= 0 then
        Exit;
      { Плитка: не раздувать мелкую страницу сильнее 2.5 и не схлопывать огромную. }
      if AScaleCap > 0 then
      begin
        if Scale > AScaleCap then
          Scale := AScaleCap;
        if Scale < 0.15 then
          Scale := 0.15;
      end;
      W := Round(Wf * Scale);
      H := Round(Hf * Scale);
      if AScaleCap > 0 then
      begin
        if W < 8 then
          W := 8;
        if H < 8 then
          H := 8;
      end
      else
      begin
        if W > AMaxW then
          W := AMaxW;
        if H > AMaxH then
          H := AMaxH;
        if W < 1 then
          W := 1;
        if H < 1 then
          H := 1;
      end;
      Bmp := FPDFBitmap_Create(W, H, 1);
      if Bmp = nil then
        Exit;
      try
        { FillRect: ARGB. Рендер без FPDF_REVERSE_BYTE_ORDER — буфер BGRA. }
        Bg := $FFFFFFFF;
        FPDFBitmap_FillRect(Bmp, 0, 0, W, H, Bg);
        FPDF_RenderPageBitmap(Bmp, Page, 0, 0, W, H, 0, FPDF_ANNOT or FPDF_LCD_TEXT);
        Buf := FPDFBitmap_GetBuffer(Bmp);
        Stride := FPDFBitmap_GetStride(Bmp);
        if (Buf = nil) or (Stride <= 0) then
          Exit;
        CopyPdfBufferToBgraBytes(Buf, Stride, W, H, APixels);
        AWidth := W;
        AHeight := H;
        Result := Length(APixels) > 0;
      finally
        FPDFBitmap_Destroy(Bmp);
      end;
    finally
      FPDF_ClosePage(Page);
    end;
  finally
    PdfLeave;
  end;
  {$ENDIF}
end;

function TPdfiumDoc.RenderPage(AIndex, AMaxW, AMaxH: Integer;
  AScaleCap: Double): FMX.Graphics.TBitmap;
var
  Pix: TBytes;
  W, H: Integer;
begin
  Result := nil;
  if not RenderPageRaw(AIndex, AMaxW, AMaxH, Pix, W, H, AScaleCap) then
    Exit;
  Result := FMX.Graphics.TBitmap.Create;
  try
    FillBitmapFromBgra(Result, Pix, W, H);
    if (Result.Width < 1) or (Result.Height < 1) then
      FreeAndNil(Result);
  except
    FreeAndNil(Result);
  end;
end;

function TPdfiumDoc.ReadPagePoints(AIndex: Integer; out AWf, AHf: Double): Boolean;
{$IFDEF MSWINDOWS}
var
  Page: FPDF_PAGE;
{$ENDIF}
begin
  Result := False;
  AWf := 0;
  AHf := 0;
  {$IFDEF MSWINDOWS}
  PdfEnter;
  try
    if (FDoc = nil) or (AIndex < 0) or (AIndex >= FCount) then
      Exit;
    if not Assigned(FPDF_LoadPage) or not Assigned(FPDF_GetPageWidth) or
       not Assigned(FPDF_GetPageHeight) or not Assigned(FPDF_ClosePage) then
      Exit;
    Page := FPDF_LoadPage(FDoc, AIndex);
    if Page = nil then
      Exit;
    try
      AWf := FPDF_GetPageWidth(Page);
      AHf := FPDF_GetPageHeight(Page);
      Result := (AWf >= 1) and (AHf >= 1) and (AWf <= 1000000) and (AHf <= 1000000);
      if not Result then
      begin
        AWf := 0;
        AHf := 0;
      end;
    finally
      FPDF_ClosePage(Page);
    end;
  finally
    PdfLeave;
  end;
  {$ENDIF}
end;

function TPdfiumDoc.PagePointSize(AIndex: Integer; out W, H: Integer): Boolean;
var
  Wf, Hf: Double;
begin
  Result := False;
  W := 0;
  H := 0;
  if not ReadPagePoints(AIndex, Wf, Hf) then
    Exit;
  W := Max(1, Round(Wf));
  H := Max(1, Round(Hf));
  Result := True;
end;

function TPdfiumDoc.PagePixelSize(AIndex, ADpi: Integer; out W, H: Integer): Boolean;
var
  Wf, Hf: Double;
begin
  Result := False;
  W := 0;
  H := 0;
  if ADpi < 1 then
    Exit;
  if not ReadPagePoints(AIndex, Wf, Hf) then
    Exit;
  W := Max(1, Round(Wf / 72 * ADpi));
  H := Max(1, Round(Hf / 72 * ADpi));
  Result := True;
end;

function TPdfiumDoc.RenderPagePrint(AIndex: Integer;
  out APrintW, APrintH, APointW, APointH: Integer): FMX.Graphics.TBitmap;
const
  PrintDpi = 300;
  MaxSide = 4096;
var
  Wf, Hf, Fit: Double;
  Rw, Rh: Integer;
begin
  Result := nil;
  APrintW := 0;
  APrintH := 0;
  APointW := 0;
  APointH := 0;
  if not ReadPagePoints(AIndex, Wf, Hf) then
    Exit;
  APointW := Max(1, Round(Wf));
  APointH := Max(1, Round(Hf));
  APrintW := Max(1, Round(Wf / 72 * PrintDpi));
  APrintH := Max(1, Round(Hf / 72 * PrintDpi));
  Rw := APrintW;
  Rh := APrintH;
  Fit := Max(Rw, Rh);
  if Fit > MaxSide then
  begin
    Fit := MaxSide / Fit;
    Rw := Max(1, Round(Rw * Fit));
    Rh := Max(1, Round(Rh * Fit));
  end;
  { 0 — без потолка 2.5: 240 pt дают 1000 px, а не 600. }
  Result := RenderPage(AIndex, Rw, Rh, 0);
end;

function AiPdfCandidate(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: array[0..1023] of Byte;
  N, I: Integer;
  S: AnsiString;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := FS.Read(Buf[0], SizeOf(Buf));
    finally
      FS.Free;
    end;
  except
    Exit(False);
  end;
  if N <= 0 then
    Exit;
  SetString(S, PAnsiChar(@Buf[0]), N);
  if Pos(AnsiString('%PDF-'), S) > 0 then
    Exit(True);
  { Двоичный AI без текстового заголовка. Чистый PostScript не трогаем:
    у него размер берётся из BoundingBox, без чтения всего файла в PDFium. }
  for I := 0 to N - 1 do
    if (Buf[I] < 9) and (Buf[I] <> 0) then
      Exit(True);
end;

function TryPdfPageSize(const APath: string; out W, H: Integer): Boolean;
var
  Doc: TPdfiumDoc;
  Ext: string;
begin
  Result := False;
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.pdf') and (Ext <> '.ai') then
    Exit;
  if not TPdfiumDoc.Available then
    Exit;
  if (Ext = '.ai') and not AiPdfCandidate(APath) then
    Exit;
  Doc := nil;
  try
    try
      Doc := TPdfiumDoc.Create(APath);
      if Doc.PageCount < 1 then
        Exit;
      Result := Doc.PagePointSize(0, W, H);
    except
      Result := False;
    end;
  finally
    Doc.Free;
  end;
end;

function TryPdfPrintSize(const APath: string; out W, H: Integer): Boolean;
var
  Doc: TPdfiumDoc;
  Ext: string;
begin
  Result := False;
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.pdf') and (Ext <> '.ai') then
    Exit;
  if not TPdfiumDoc.Available then
    Exit;
  if (Ext = '.ai') and not AiPdfCandidate(APath) then
    Exit;
  Doc := nil;
  try
    try
      Doc := TPdfiumDoc.Create(APath);
      if Doc.PageCount < 1 then
        Exit;
      Result := Doc.PagePixelSize(0, 300, W, H);
    except
      Result := False;
    end;
  finally
    Doc.Free;
  end;
end;

function IsPdfThumbExt(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.pdf') or (Ext = '.ai');
end;

function RenderPdfThumbRaw(const APath: string; AMaxW, AMaxH: Integer;
  out APixels: TBytes; out AWidth, AHeight: Integer): Boolean;
var
  Doc: TPdfiumDoc;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  if not IsPdfThumbExt(APath) then
    Exit;
  if not TPdfiumDoc.Available then
    Exit;
  Doc := nil;
  try
    Doc := TPdfiumDoc.Create(APath);
    if Doc.PageCount < 1 then
      Exit;
    Result := Doc.RenderPageRaw(0, AMaxW, AMaxH, APixels, AWidth, AHeight);
  except
    Result := False;
    SetLength(APixels, 0);
  end;
  Doc.Free;
end;

function RenderPdfThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap): Boolean;
var
  Pix: TBytes;
  W, H: Integer;
begin
  Result := False;
  if (ABitmap = nil) or (AWidth < 8) or (AHeight < 8) then
    Exit;
  if not RenderPdfThumbRaw(APath, AWidth, AHeight, Pix, W, H) then
    Exit;
  FillBitmapFromBgra(ABitmap, Pix, W, H);
  Result := (ABitmap.Width > 0) and (ABitmap.Height > 0);
end;

initialization
  GPdfLock := TCriticalSection.Create;

finalization
{$IFDEF MSWINDOWS}
  if (GReady > 0) and Assigned(FPDF_DestroyLibrary) then
    FPDF_DestroyLibrary();
  if GLib <> 0 then
    FreeLibrary(GLib);
{$ENDIF}
  FreeAndNil(GPdfLock);

end.
