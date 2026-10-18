unit uVecPreview;

{
  Свой разбор CDR, EPS, EMF и WMF для Quick View.
  EMF/WMF: рамка в 0.01 мм. Quick View рисует печатный размер (300 dpi, потолок 4096).
  Плитка метафайла остаётся под слот. Подпись плитки — те же печатные пиксели.
  EPS: разбор PostScript (графика) и встроенный TIFF/WMF/EPSI.
  CDR: ZIP или RIFF, превью DISP и встроенные картинки.
  Плитка CDR/CDT берёт именованное превью из ZIP, иначе тот же разбор, что Quick View.
}

interface

uses
  System.SysUtils, FMX.Graphics;

{ EMF/WMF: APrint — 300 dpi, AScreen — 96 dpi, ALabel пустой.
  Нет рамки — нули, подпись тогда берёт сторону битмапа. EPS и CDR пишут ALabel. }
function LoadVectorPreview(const APath: string; ABitmap: TBitmap;
  out ALabel: string; out APrintW, APrintH, AScreenW, AScreenH: Integer): Boolean;
function RenderMetaTile(const APath: string; AMaxSide: Integer;
  ABitmap: TBitmap): Boolean;
function RenderCdrTile(const APath: string; AMaxSide: Integer;
  ABitmap: TBitmap; AFullParse: Boolean = True): Boolean;
{ Подпись плитки. EMF/WMF — печатные пиксели 300 dpi, не сторона превью.
  Пустой rclFrame — bounds как есть, без выдуманного dpi. }
function TryMetaImageSize(const APath: string; out W, H: Integer): Boolean;
{ %%HiResBoundingBox / %%BoundingBox старого AI, в пунктах. }
function TryPsPointSize(const APath: string; out W, H: Integer): Boolean;

implementation

uses
  System.Classes, System.Math, System.Types, System.UITypes,
  System.Generics.Collections, System.Zip, System.Diagnostics,
  System.Skia, FMX.Skia;

const
  VecMaxBytes = 96 * 1024 * 1024;
  VecMaxSide = 2400;
  VecPrintCap = 4096;
  VecMinSide = 720;
  EpsMaxScript = 24 * 1024 * 1024;
  EpsMaxSteps = 4000000;
  EpsMaxDepth = 64;
  EmfSig = $464D4520;
  EpsMagic = $C6D3D0C5;
  WmfKey = $9AC6CDD7;
  MetaSetWindowExt = $020C;

type
  HDC = NativeUInt;
  HBITMAP = NativeUInt;
  HGDIOBJ = NativeUInt;
  HENHMETAFILE = NativeUInt;
  HBRUSH = NativeUInt;

  TRectL = record
    Left, Top, Right, Bottom: Integer;
  end;

  TSizeL = record
    cx, cy: Integer;
  end;

  TEnhHdr = record
    iType: Cardinal;
    nSize: Cardinal;
    rclBounds: TRectL;
    rclFrame: TRectL;
    dSignature: Cardinal;
    nVersion: Cardinal;
    nBytes: Cardinal;
    nRecords: Cardinal;
    nHandles: Word;
    sReserved: Word;
    nDescription: Cardinal;
    offDescription: Cardinal;
    nPalEntries: Cardinal;
    szlDevice: TSizeL;
    szlMillimeters: TSizeL;
    cbPixelFormat: Cardinal;
    offPixelFormat: Cardinal;
    bOpenGL: Cardinal;
    szlMicrometers: TSizeL;
  end;

  TMetaPict = record
    mm: Integer;
    xExt: Integer;
    yExt: Integer;
    hMF: NativeUInt;
  end;

  TBitmapInfoHeader = record
    biSize: Cardinal;
    biWidth: Integer;
    biHeight: Integer;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: Cardinal;
    biSizeImage: Cardinal;
    biXPelsPerMeter: Integer;
    biYPelsPerMeter: Integer;
    biClrUsed: Cardinal;
    biClrImportant: Cardinal;
  end;

  TBitmapInfo = record
    bmiHeader: TBitmapInfoHeader;
    bmiColors: array[0..0] of Cardinal;
  end;

  TWmfPlace = packed record
    Key: Cardinal;
    Handle: Word;
    Left, Top, Right, Bottom: SmallInt;
    Inch: Word;
    Reserved: Cardinal;
    Checksum: Word;
  end;

  TWmfHeader = packed record
    mtType: Word;
    mtHeaderSize: Word;
    mtVersion: Word;
    mtSize: Cardinal;
    mtNoObjects: Word;
    mtMaxRecord: Cardinal;
    mtNoParameters: Word;
  end;

  TMetaPx = record
    PrintW, PrintH: Integer;
    ScreenW, ScreenH: Integer;
  end;

function SetEnhMetaFileBits(cb: Cardinal; pb: PByte): HENHMETAFILE; stdcall;
  external 'gdi32.dll';
function GetEnhMetaFileHeader(hmf: HENHMETAFILE; cb: Cardinal; p: Pointer): Cardinal; stdcall;
  external 'gdi32.dll';
function PlayEnhMetaFile(DC: HDC; hmf: HENHMETAFILE; const R: TRectL): LongBool; stdcall;
  external 'gdi32.dll';
function DeleteEnhMetaFile(hmf: HENHMETAFILE): LongBool; stdcall;
  external 'gdi32.dll';
function SetWinMetaFileBits(cb: Cardinal; pb: PByte; DC: HDC;
  const MFP: TMetaPict): HENHMETAFILE; stdcall; external 'gdi32.dll';
function CreateCompatibleDC(DC: HDC): HDC; stdcall; external 'gdi32.dll';
function DeleteDC(DC: HDC): LongBool; stdcall; external 'gdi32.dll';
function CreateDIBSection(DC: HDC; var BI: TBitmapInfo; Usage: Cardinal;
  var Bits: Pointer; Section: NativeUInt; Offset: Cardinal): HBITMAP; stdcall;
  external 'gdi32.dll';
function SelectObject(DC: HDC; Obj: HGDIOBJ): HGDIOBJ; stdcall; external 'gdi32.dll';
function DeleteObject(Obj: HGDIOBJ): LongBool; stdcall; external 'gdi32.dll';
function GetStockObject(Index: Integer): HGDIOBJ; stdcall; external 'gdi32.dll';
function SetStretchBltMode(DC: HDC; Mode: Integer): Integer; stdcall;
  external 'gdi32.dll';
function FillRect(DC: HDC; const R: TRectL; Brush: HBRUSH): Integer; stdcall;
  external 'user32.dll';

function ReadFileBytes(const APath: string; AMax: Integer): TBytes;
var
  FS: TFileStream;
  N: Integer;
begin
  SetLength(Result, 0);
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    N := FS.Size;
    if N > AMax then
      N := AMax;
    if N < 1 then
      Exit;
    SetLength(Result, N);
    FS.ReadBuffer(Result[0], N);
  finally
    FS.Free;
  end;
end;

function U16(const B: TBytes; O: Integer): Word;
begin
  Result := Word(B[O]) or (Word(B[O + 1]) shl 8);
end;

function U32(const B: TBytes; O: Integer): Cardinal;
begin
  Result := Cardinal(B[O]) or (Cardinal(B[O + 1]) shl 8) or
    (Cardinal(B[O + 2]) shl 16) or (Cardinal(B[O + 3]) shl 24);
end;

function I32(const B: TBytes; O: Integer): Integer;
begin
  Result := Integer(U32(B, O));
end;

function FourCC(const B: TBytes; O: Integer): string;
begin
  Result := Char(B[O]) + Char(B[O + 1]) + Char(B[O + 2]) + Char(B[O + 3]);
end;

procedure ClampSide(var W, H: Integer);
var
  M, S: Double;
begin
  if W < 1 then
    W := 1;
  if H < 1 then
    H := 1;
  M := Max(W, H);
  if M < VecMinSide then
  begin
    S := VecMinSide / M;
    W := Max(1, Round(W * S));
    H := Max(1, Round(H * S));
  end;
  M := Max(W, H);
  if M > VecMaxSide then
  begin
    S := VecMaxSide / M;
    W := Max(1, Round(W * S));
    H := Max(1, Round(H * S));
  end;
end;

function LooksEmf(const B: TBytes): Boolean;
begin
  Result := (Length(B) >= 48) and (U32(B, 0) = 1) and (U32(B, 40) = EmfSig);
end;

function DibToFmx(Bits: PByte; W, H, Stride: Integer; ABmp: TBitmap): Boolean;
var
  Data: TBitmapData;
  Y, X: Integer;
  Src, Dst: PByte;
  C: TAlphaColorRec;
begin
  Result := False;
  if (Bits = nil) or (W < 1) or (H < 1) then
    Exit;
  ABmp.SetSize(W, H);
  if not ABmp.Map(TMapAccess.Write, Data) then
    Exit;
  try
    for Y := 0 to H - 1 do
    begin
      Src := Bits + Y * Stride;
      Dst := PByte(Data.GetScanline(Y));
      for X := 0 to W - 1 do
      begin
        C.B := Src[X * 4];
        C.G := Src[X * 4 + 1];
        C.R := Src[X * 4 + 2];
        C.A := 255;
        PAlphaColor(Dst + X * 4)^ := C.Color;
      end;
    end;
    Result := True;
  finally
    ABmp.Unmap(Data);
  end;
end;

function PlayEmf(Hemf: HENHMETAFILE; ABmp: TBitmap; AMaxSide: Integer;
  ATargetW: Integer = 0; ATargetH: Integer = 0): Boolean;
var
  Hdr: TEnhHdr;
  FW, FH, BW, BH, W, H, M: Integer;
  S: Double;
  DC: HDC;
  BI: TBitmapInfo;
  Bits: Pointer;
  DIB, Old: HBITMAP;
  R: TRectL;
begin
  Result := False;
  if Hemf = 0 then
    Exit;
  if (ATargetW > 0) and (ATargetH > 0) then
  begin
    { Quick View: готовые пиксели (печать или bounds). Потолок 4096, вверх не тянуть. }
    W := ATargetW;
    H := ATargetH;
    M := Max(W, H);
    if M > VecPrintCap then
    begin
      S := VecPrintCap / M;
      W := Max(1, Round(W * S));
      H := Max(1, Round(H * S));
    end;
  end
  else if AMaxSide = 0 then
  begin
    { Рамки в файле нет. DPI не выдумывать: bounds как пиксели, иначе квадрат. }
    W := 1200;
    H := 1200;
    FillChar(Hdr, SizeOf(Hdr), 0);
    if GetEnhMetaFileHeader(Hemf, SizeOf(Hdr), @Hdr) >= 88 then
    begin
      BW := Abs(Hdr.rclBounds.Right - Hdr.rclBounds.Left);
      BH := Abs(Hdr.rclBounds.Bottom - Hdr.rclBounds.Top);
      if (BW >= 2) and (BH >= 2) then
      begin
        W := BW;
        H := BH;
      end;
    end;
    M := Max(W, H);
    if M > VecPrintCap then
    begin
      S := VecPrintCap / M;
      W := Max(1, Round(W * S));
      H := Max(1, Round(H * S));
    end;
  end
  else
  begin
    { Плитка и встроенное превью EPS. 192 dpi — только промежуточный кадр:
      плитка сразу садится в слот, EPS сравнивается с порогом 300 px.
      Quick View сюда не заходит. }
    FillChar(Hdr, SizeOf(Hdr), 0);
    if GetEnhMetaFileHeader(Hemf, SizeOf(Hdr), @Hdr) >= 88 then
    begin
      FW := Abs(Hdr.rclFrame.Right - Hdr.rclFrame.Left);
      FH := Abs(Hdr.rclFrame.Bottom - Hdr.rclFrame.Top);
      W := Max(1, Round(FW * 192 / 2540));
      H := Max(1, Round(FH * 192 / 2540));
      if (FW < 2) or (FH < 2) then
      begin
        W := Max(1, Abs(Hdr.rclBounds.Right - Hdr.rclBounds.Left));
        H := Max(1, Abs(Hdr.rclBounds.Bottom - Hdr.rclBounds.Top));
      end;
    end
    else
    begin
      W := 1200;
      H := 1200;
    end;
    if AMaxSide > 0 then
    begin
      M := Max(W, H);
      if M < 1 then
        M := 1;
      S := AMaxSide / M;
      W := Max(1, Round(W * S));
      H := Max(1, Round(H * S));
    end
    else if AMaxSide < 0 then
    begin
      M := Max(W, H);
      if M > VecMaxSide then
      begin
        S := VecMaxSide / M;
        W := Max(1, Round(W * S));
        H := Max(1, Round(H * S));
      end;
    end;
  end;
  DC := CreateCompatibleDC(0);
  if DC = 0 then
    Exit;
  DIB := 0;
  Old := 0;
  Bits := nil;
  try
    FillChar(BI, SizeOf(BI), 0);
    BI.bmiHeader.biSize := 40;
    BI.bmiHeader.biWidth := W;
    BI.bmiHeader.biHeight := -H;
    BI.bmiHeader.biPlanes := 1;
    BI.bmiHeader.biBitCount := 32;
    BI.bmiHeader.biCompression := 0;
    DIB := CreateDIBSection(DC, BI, 0, Bits, 0, 0);
    if (DIB = 0) or (Bits = nil) then
      Exit;
    Old := SelectObject(DC, DIB);
    R.Left := 0;
    R.Top := 0;
    R.Right := W;
    R.Bottom := H;
    FillRect(DC, R, GetStockObject(0));
    SetStretchBltMode(DC, 4);
    if not PlayEnhMetaFile(DC, Hemf, R) then
      Exit;
    Result := DibToFmx(PByte(Bits), W, H, W * 4, ABmp);
  finally
    if Old <> 0 then
      SelectObject(DC, Old);
    if DIB <> 0 then
      DeleteObject(DIB);
    DeleteDC(DC);
  end;
end;

function WindowExtOf(const B: TBytes; AOff: Integer): TPoint;
var
  Off, Words: Integer;
  Fn: Word;
begin
  Result := TPoint.Create(0, 0);
  Off := AOff;
  while Off + 6 <= Length(B) do
  begin
    Words := Integer(U32(B, Off));
    if (Words < 3) or (Off + Words * 2 > Length(B)) then
      Break;
    Fn := U16(B, Off + 4);
    if Fn = 0 then
      Break;
    if (Fn = MetaSetWindowExt) and (Words >= 4) then
    begin
      Result.Y := Abs(SmallInt(U16(B, Off + 6)));
      Result.X := Abs(SmallInt(U16(B, Off + 8)));
      Exit;
    end;
    Inc(Off, Words * 2);
  end;
end;

function WmfToEmf(const B: TBytes; AOff, ALen: Integer): HENHMETAFILE;
var
  Place: TWmfPlace;
  Head: Integer;
  Pict: TMetaPict;
  Win: TPoint;
  Inch: Integer;
begin
  Result := 0;
  if (AOff < 0) or (ALen < 18) or (AOff + ALen > Length(B)) then
    Exit;
  Head := AOff;
  FillChar(Pict, SizeOf(Pict), 0);
  Pict.mm := 8;
  if (ALen >= 22) and (U32(B, AOff) = WmfKey) then
  begin
    Move(B[AOff], Place, 22);
    Head := AOff + 22;
    Inch := Place.Inch;
    if Inch < 1 then
      Inch := 1440;
    Pict.xExt := Max(1, Round(Abs(Place.Right - Place.Left) / Inch * 2540));
    Pict.yExt := Max(1, Round(Abs(Place.Bottom - Place.Top) / Inch * 2540));
  end
  else
  begin
    Win := WindowExtOf(B, Head);
    if (Win.X > 0) and (Win.Y > 0) then
    begin
      Pict.xExt := Max(1, Round(Win.X / 1440 * 2540));
      Pict.yExt := Max(1, Round(Win.Y / 1440 * 2540));
    end;
  end;
  if Head + 18 > AOff + ALen then
    Exit;
  Result := SetWinMetaFileBits(AOff + ALen - Head, @B[Head], 0, Pict);
end;

function RenderMetaBytes(const B: TBytes; ABmp: TBitmap; AMaxSide: Integer): Boolean;
var
  Hemf: HENHMETAFILE;
begin
  Result := False;
  if LooksEmf(B) then
    Hemf := SetEnhMetaFileBits(Length(B), @B[0])
  else
    Hemf := WmfToEmf(B, 0, Length(B));
  if Hemf = 0 then
    Exit;
  try
    Result := PlayEmf(Hemf, ABmp, AMaxSide);
  finally
    DeleteEnhMetaFile(Hemf);
  end;
end;

function RenderMetaTarget(const B: TBytes; ABmp: TBitmap;
  ATargetW, ATargetH: Integer): Boolean;
var
  Hemf: HENHMETAFILE;
begin
  Result := False;
  if (ABmp = nil) or (ATargetW < 1) or (ATargetH < 1) or (Length(B) < 18) then
    Exit;
  if LooksEmf(B) then
    Hemf := SetEnhMetaFileBits(Length(B), @B[0])
  else
    Hemf := WmfToEmf(B, 0, Length(B));
  if Hemf = 0 then
    Exit;
  try
    Result := PlayEmf(Hemf, ABmp, 0, ATargetW, ATargetH);
  finally
    DeleteEnhMetaFile(Hemf);
  end;
end;

function MetaSideOk(W, H: Integer): Boolean;
begin
  Result := (W >= 1) and (H >= 1) and (W <= 1000000) and (H <= 1000000);
end;

procedure ClearMetaPx(out APx: TMetaPx);
begin
  APx.PrintW := 0;
  APx.PrintH := 0;
  APx.ScreenW := 0;
  APx.ScreenH := 0;
end;

function DpiPx(AUnits: Int64; APerInch, ADpi: Integer): Integer;
var
  V: Double;
begin
  Result := 0;
  if (AUnits < 1) or (APerInch < 1) or (ADpi < 1) then
    Exit;
  V := (AUnits * 1.0) / APerInch * ADpi;
  if (V < 0.5) or (V > 1000000) then
    Exit;
  Result := Max(1, Round(V));
end;

function FillDpiPair(AUw, AUh: Int64; APerInch: Integer; out APx: TMetaPx): Boolean;
begin
  ClearMetaPx(APx);
  APx.ScreenW := DpiPx(AUw, APerInch, 96);
  APx.ScreenH := DpiPx(AUh, APerInch, 96);
  APx.PrintW := DpiPx(AUw, APerInch, 300);
  APx.PrintH := DpiPx(AUh, APerInch, 300);
  if MetaSideOk(APx.PrintW, APx.PrintH) and MetaSideOk(APx.ScreenW, APx.ScreenH) then
    Exit(True);
  APx.PrintW := 0;
  APx.PrintH := 0;
  Result := MetaSideOk(APx.ScreenW, APx.ScreenH);
  if not Result then
    ClearMetaPx(APx);
end;

function EmfMetaPx(const B: TBytes; out APx: TMetaPx): Boolean;
var
  FW, FH, BW, BH: Int64;
begin
  Result := False;
  ClearMetaPx(APx);
  if not LooksEmf(B) then
    Exit;
  FW := Abs(Int64(I32(B, 32)) - Int64(I32(B, 24)));
  FH := Abs(Int64(I32(B, 36)) - Int64(I32(B, 28)));
  if (FW >= 2) and (FH >= 2) then
  begin
    { rclFrame в 0.01 мм. 2540 единиц = 1 дюйм. rclBounds и DPI устройства не берём. }
    Result := FillDpiPair(FW, FH, 2540, APx);
    Exit;
  end;
  BW := Abs(Int64(I32(B, 16)) - Int64(I32(B, 8)));
  BH := Abs(Int64(I32(B, 20)) - Int64(I32(B, 12)));
  if (BW < 1) or (BH < 1) or (BW > 1000000) or (BH > 1000000) then
    Exit;
  APx.ScreenW := Integer(BW);
  APx.ScreenH := Integer(BH);
  Result := MetaSideOk(APx.ScreenW, APx.ScreenH);
  if not Result then
    ClearMetaPx(APx);
end;

function WmfMetaPx(const B: TBytes; out APx: TMetaPx): Boolean;
var
  Place: TWmfPlace;
  Inch, Dw, Dh: Integer;
  Win: TPoint;
begin
  Result := False;
  ClearMetaPx(APx);
  if Length(B) < 18 then
    Exit;
  if (Length(B) >= 22) and (U32(B, 0) = WmfKey) then
  begin
    Move(B[0], Place, 22);
    Inch := Place.Inch;
    if Inch < 1 then
      Inch := 1440;
    Dw := Abs(Integer(Place.Right) - Integer(Place.Left));
    Dh := Abs(Integer(Place.Bottom) - Integer(Place.Top));
    if (Dw < 1) or (Dh < 1) then
      Exit;
    Result := FillDpiPair(Dw, Dh, Inch, APx);
    Exit;
  end;
  Win := WindowExtOf(B, 0);
  if (Win.X < 1) or (Win.Y < 1) then
    Exit;
  Result := FillDpiPair(Win.X, Win.Y, 1440, APx);
end;

function TakeTilePx(const APx: TMetaPx; out W, H: Integer): Boolean;
begin
  if (APx.PrintW > 0) and (APx.PrintH > 0) then
  begin
    W := APx.PrintW;
    H := APx.PrintH;
    Exit(True);
  end;
  if (APx.ScreenW > 0) and (APx.ScreenH > 0) then
  begin
    W := APx.ScreenW;
    H := APx.ScreenH;
    Exit(True);
  end;
  W := 0;
  H := 0;
  Result := False;
end;

function TryMetaImageSize(const APath: string; out W, H: Integer): Boolean;
var
  Ext: string;
  B: TBytes;
  Px: TMetaPx;
begin
  Result := False;
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.emf') and (Ext <> '.wmf') then
    Exit;
  try
    B := ReadFileBytes(APath, 256 * 1024);
    if Ext = '.emf' then
      EmfMetaPx(B, Px)
    else
      WmfMetaPx(B, Px);
    Result := TakeTilePx(Px, W, H);
  except
    Result := False;
    W := 0;
    H := 0;
  end;
end;

function RenderMetaTile(const APath: string; AMaxSide: Integer;
  ABitmap: TBitmap): Boolean;
var
  Ext: string;
begin
  Result := False;
  if (ABitmap = nil) or (APath = '') or not FileExists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.emf') and (Ext <> '.wmf') then
    Exit;
  if AMaxSide < 32 then
    AMaxSide := 32;
  if AMaxSide > 512 then
    AMaxSide := 512;
  try
    { Слот, не 300 dpi. Печатный размер для подписи считается отдельно, из заголовка. }
    Result := RenderMetaBytes(ReadFileBytes(APath, VecMaxBytes), ABitmap, AMaxSide)
      and (ABitmap.Width > 0);
  except
    Result := False;
  end;
end;

function AssignEncoded(const B: TBytes; ABmp: TBitmap): Boolean;
var
  Img: ISkImage;
  Tmp: TBitmap;
begin
  Result := False;
  if Length(B) < 8 then
    Exit;
  Img := TSkImage.MakeFromEncoded(B);
  if Img = nil then
    Exit;
  Tmp := TBitmap.CreateFromSkImage(Img);
  try
    if (Tmp.Width < 1) or (Tmp.Height < 1) then
      Exit;
    ABmp.SetSize(Tmp.Width, Tmp.Height);
    ABmp.Assign(Tmp);
    Result := ABmp.Width > 0;
  finally
    Tmp.Free;
  end;
end;

function WrapDib(const Dib: TBytes): TBytes;
var
  N, Off, Colors, Bit: Integer;
  Hdr: Cardinal;
begin
  SetLength(Result, 0);
  if Length(Dib) < 40 then
    Exit;
  Hdr := U32(Dib, 0);
  if (Hdr <> 40) and (Hdr <> 108) and (Hdr <> 124) then
    Exit;
  Bit := U16(Dib, 14);
  Colors := Integer(U32(Dib, 32));
  if (Bit <= 8) and (Colors = 0) then
    Colors := 1 shl Bit;
  if Bit > 8 then
    Colors := 0;
  Off := Integer(Hdr) + Colors * 4;
  if Off < 40 then
    Exit;
  N := 14 + Length(Dib);
  SetLength(Result, N);
  Result[0] := Ord('B');
  Result[1] := Ord('M');
  PCardinal(@Result[2])^ := Cardinal(N);
  PCardinal(@Result[10])^ := Cardinal(14 + Off);
  Move(Dib[0], Result[14], Length(Dib));
end;

function TryIndexedDisp(const D: TBytes; ABmp: TBitmap): Boolean;
var
  W, H, X, Y, Idx, Row: Integer;
  Data: TBitmapData;
  Pix: PByte;
  Pal: TAlphaColorRec;
  Src: Integer;
begin
  Result := False;
  if Length(D) < 1068 + 4 then
    Exit;
  W := I32(D, 8);
  H := I32(D, 12);
  if (W < 2) or (H < 2) or (W > 8000) or (H > 8000) then
    Exit;
  if Length(D) < 1068 + W * H then
    Exit;
  ABmp.SetSize(W, H);
  if not ABmp.Map(TMapAccess.Write, Data) then
    Exit;
  try
    for Y := 0 to H - 1 do
    begin
      Row := H - 1 - Y;
      Pix := PByte(Data.GetScanline(Y));
      for X := 0 to W - 1 do
      begin
        Idx := D[1068 + Row * W + X];
        Src := 44 + Idx * 4;
        if Src + 3 >= Length(D) then
          Exit;
        Pal.B := D[Src];
        Pal.G := D[Src + 1];
        Pal.R := D[Src + 2];
        Pal.A := 255;
        PAlphaColor(Pix + X * 4)^ := Pal.Color;
      end;
    end;
    Result := True;
  finally
    ABmp.Unmap(Data);
  end;
end;

function TryRasterBytes(const B: TBytes; ABmp: TBitmap): Boolean;
var
  Wrapped: TBytes;
begin
  Result := AssignEncoded(B, ABmp);
  if Result then
    Exit;
  Wrapped := WrapDib(B);
  if Length(Wrapped) > 0 then
    Result := AssignEncoded(Wrapped, ABmp);
  if Result then
    Exit;
  Result := TryIndexedDisp(B, ABmp);
end;

procedure Consider(ANew: TBitmap; var ABest: TBitmap; var AArea: Int64);
var
  Area: Int64;
begin
  if (ANew = nil) or (ANew.Width < 2) or (ANew.Height < 2) then
  begin
    ANew.Free;
    Exit;
  end;
  Area := Int64(ANew.Width) * ANew.Height;
  if Area > AArea then
  begin
    ABest.Free;
    ABest := ANew;
    AArea := Area;
  end
  else
    ANew.Free;
end;

function ParseCdrRiff(const B: TBytes; ABmp: TBitmap): Boolean;
var
  Best: TBitmap;
  Area: Int64;

  procedure Walk(AFrom, ATo: Integer);
  var
    P, Size, Inner: Integer;
    Id: string;
    Chunk: TBytes;
    Tmp: TBitmap;
  begin
    P := AFrom;
    while P + 8 <= ATo do
    begin
      Id := FourCC(B, P);
      Size := Integer(U32(B, P + 4));
      if (Size < 0) or (P + 8 + Size > ATo) then
        Break;
      Inner := P + 8;
      if (Id = 'RIFF') or (Id = 'LIST') then
      begin
        if (Size >= 4) and (FourCC(B, Inner) <> 'cmpr') then
          Walk(Inner + 4, Inner + Size);
      end
      else
      begin
        SetLength(Chunk, Size);
        if Size > 0 then
          Move(B[Inner], Chunk[0], Size);
        Tmp := TBitmap.Create;
        if TryRasterBytes(Chunk, Tmp) then
          Consider(Tmp, Best, Area)
        else
          Tmp.Free;
      end;
      Inc(P, 8 + Size + (Size and 1));
    end;
  end;

begin
  Result := False;
  Best := nil;
  Area := 0;
  try
    if (Length(B) < 12) or (FourCC(B, 0) <> 'RIFF') then
      Exit;
    if (Copy(FourCC(B, 8), 1, 3) <> 'CDR') and
       (Copy(FourCC(B, 8), 1, 3) <> 'CDT') then
      Exit;
    Walk(12, Min(Length(B), 8 + Integer(U32(B, 4))));
    if Best = nil then
      Exit;
    ABmp.Assign(Best);
    Result := ABmp.Width > 0;
  finally
    Best.Free;
  end;
end;

function ZipNorm(const S: string): string;
begin
  Result := StringReplace(LowerCase(S), '\', '/', [rfReplaceAll]);
end;

function ParseCdrZip(const APath: string; ABmp: TBitmap): Boolean;
var
  FS: TFileStream;
  Zip: TZipFile;
  I: Integer;
  Name: string;
  Bytes: TBytes;
  InfoSize: Int64;
  Best: TBitmap;
  Area: Int64;
  Tmp: TBitmap;
begin
  Result := False;
  Best := nil;
  Area := 0;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  Zip := TZipFile.Create;
  try
    Zip.Open(FS, zmRead);
    for I := 0 to Zip.FileCount - 1 do
    begin
      Name := ZipNorm(Zip.FileName[I]);
      InfoSize := Zip.FileInfo[I].UncompressedSize;
      if (InfoSize < 16) or (InfoSize > 40 * 1024 * 1024) then
        Continue;
      if (Pos('riffdata.cdr', Name) > 0) or (Copy(Name, Length(Name) - 3, 4) = '.cdr') then
      begin
        Zip.Read(I, Bytes);
        Tmp := TBitmap.Create;
        if ParseCdrRiff(Bytes, Tmp) then
          Consider(Tmp, Best, Area)
        else
          Tmp.Free;
        Continue;
      end;
      if (Pos('thumb', Name) = 0) and (Pos('preview', Name) = 0) and
         (Pos('bitmap', Name) = 0) and
         (Pos('.bmp', Name) = 0) and (Pos('.png', Name) = 0) and
         (Pos('.jpg', Name) = 0) and (Pos('.jpeg', Name) = 0) and
         (Pos('.tif', Name) = 0) and (Pos('.webp', Name) = 0) then
        Continue;
      if InfoSize > 20 * 1024 * 1024 then
        Continue;
      Zip.Read(I, Bytes);
      Tmp := TBitmap.Create;
      if TryRasterBytes(Bytes, Tmp) then
        Consider(Tmp, Best, Area)
      else
        Tmp.Free;
    end;
    if Best = nil then
      Exit;
    ABmp.Assign(Best);
    Result := ABmp.Width > 0;
  finally
    Best.Free;
    Zip.Free;
    FS.Free;
  end;
end;

function LoadCdr(const APath: string; ABmp: TBitmap): Boolean;
var
  B: TBytes;
begin
  Result := False;
  B := ReadFileBytes(APath, VecMaxBytes);
  if Length(B) < 12 then
    Exit;
  if (B[0] = $50) and (B[1] = $4B) then
    Result := ParseCdrZip(APath, ABmp)
  else if (B[0] = Ord('R')) and (B[1] = Ord('I')) then
    Result := ParseCdrRiff(B, ABmp)
  else
    Result := TryRasterBytes(B, ABmp);
end;

function TryCdrNamedPreview(const APath: string; ABmp: TBitmap;
  AMaxSide: Integer): Boolean;
var
  FS: TFileStream;
  Zip: TZipFile;
  I: Integer;
  Name: string;
  Bytes: TBytes;
  Sig: array[0..1] of Byte;
  InfoSize, Area: Int64;
  Best, Tmp: TBitmap;
begin
  Result := False;
  Best := nil;
  Area := 0;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Zip := TZipFile.Create;
    try
      try
        if (FS.Size < 4) or (FS.Read(Sig, 2) <> 2) then
          Exit;
        if (Sig[0] <> $50) or (Sig[1] <> $4B) then
          Exit;
        FS.Position := 0;
        Zip.Open(FS, zmRead);
        for I := 0 to Zip.FileCount - 1 do
        begin
          Name := ZipNorm(Zip.FileName[I]);
          if (Pos('thumb', Name) = 0) and (Pos('preview', Name) = 0) then
            Continue;
          InfoSize := Zip.FileInfo[I].UncompressedSize;
          if (InfoSize < 32) or (InfoSize > 20 * 1024 * 1024) then
            Continue;
          try
            Zip.Read(I, Bytes);
            Tmp := TBitmap.Create;
            try
              if TryRasterBytes(Bytes, Tmp) or
                 RenderMetaBytes(Bytes, Tmp, AMaxSide) then
                Consider(Tmp, Best, Area)
              else
                Tmp.Free;
            except
              Tmp.Free;
            end;
          except
          end;
        end;
        if Best = nil then
          Exit;
        ABmp.Assign(Best);
        Result := ABmp.Width > 1;
      except
        Result := False;
      end;
    finally
      Best.Free;
      Zip.Free;
    end;
  finally
    FS.Free;
  end;
end;

procedure PaintCdrTile(const ASrc, ADst: TBitmap; AMaxSide: Integer);
var
  Img: ISkImage;
  W, H: Integer;
  Scale: Single;
begin
  W := ASrc.Width;
  H := ASrc.Height;
  if (W > AMaxSide) or (H > AMaxSide) then
  begin
    Scale := Min(AMaxSide / W, AMaxSide / H);
    W := Max(1, Round(W * Scale));
    H := Max(1, Round(H * Scale));
  end;
  Img := ASrc.ToSkImage;
  if Img = nil then
  begin
    ADst.Assign(ASrc);
    Exit;
  end;
  ADst.SetSize(W, H);
  ADst.SkiaDraw(
    procedure(const C: ISkCanvas)
    begin
      C.Clear($FFFFFFFF);
      C.DrawImageRect(Img, TRectF.Create(0, 0, W, H), TSkSamplingOptions.Medium);
    end, True);
end;

function RenderCdrTile(const APath: string; AMaxSide: Integer;
  ABitmap: TBitmap; AFullParse: Boolean): Boolean;
var
  Ext: string;
  Full: TBitmap;
  Named: Boolean;
  Side: Integer;
begin
  Result := False;
  if (ABitmap = nil) or (APath = '') or not FileExists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.cdr') and (Ext <> '.cdt') then
    Exit;
  if AMaxSide < 32 then
    AMaxSide := 32;
  if AMaxSide > 512 then
    AMaxSide := 512;
  Full := TBitmap.Create;
  try
    try
      Named := TryCdrNamedPreview(APath, Full, AMaxSide) and (Full.Width > 1) and
        (Full.Height > 1);
      Side := 0;
      if Named then
        Side := Max(Full.Width, Full.Height);
      { Крупное именованное превью — страница. Иначе тот же разбор, что в Quick View. }
      if not (Named and (Side >= 64)) and AFullParse then
      begin
        try
          if LoadCdr(APath, Full) and (Full.Width > 1) and (Full.Height > 1) then
            Named := True;
        except
        end;
      end;
      if not Named or (Max(Full.Width, Full.Height) < 16) then
        Exit;
      PaintCdrTile(Full, ABitmap, AMaxSide);
      Result := ABitmap.Width > 1;
    except
      Result := False;
    end;
  finally
    Full.Free;
  end;
end;

type
  TTokKind = (tkNum, tkName, tkLit, tkStr, tkLBrace, tkRBrace);

  TTok = record
    Kind: TTokKind;
    Num: Double;
    Text: string;
  end;

  TPsKind = (pkNum, pkName, pkStr, pkProc, pkArr, pkDict, pkMark, pkBool);

  TPsVal = record
    Kind: TPsKind;
    Num: Double;
    Text: string;
    ProcFrom, ProcTo: Integer;
    Nums: TArray<Double>;
    Keys: TArray<string>;
    Vals: TArray<TPsVal>;
  end;

  TMat = record
    A, B, C, D, E, F: Double;
  end;

  TVerbKind = (vkMove, vkLine, vkCubic, vkClose);

  TVerb = record
    Kind: TVerbKind;
    X1, Y1, X2, Y2, X3, Y3: Single;
  end;

  TGs = record
    User: TMat;
    FillC, StrokeC: TAlphaColor;
    LineW: Double;
    Cap, Join: Integer;
    HasPt: Boolean;
    Ux, Uy: Double;
    Painted: Boolean;
    SaveId: Integer;
    Verbs: TArray<TVerb>;
    VerbN: Integer;
  end;

  TEpsDraw = class
  private
    FCanvas: ISkCanvas;
    FToks: TArray<TTok>;
    FTokN: Integer;
    FStack: TArray<TPsVal>;
    FSP: Integer;
    FUser: TDictionary<string, TPsVal>;
    FPage, FUserM: TMat;
    FFillC, FStrokeC: TAlphaColor;
    FLineW: Double;
    FCap, FJoin: Integer;
    FVerbs: TArray<TVerb>;
    FVerbN: Integer;
    FHasPt: Boolean;
    FUx, FUy: Double;
    FSubX, FSubY: Double;
    FPainted: Boolean;
    FGs: TArray<TGs>;
    FGsN: Integer;
    FBaseSave: Integer;
    FSteps: Integer;
    FDepth: Integer;
    FDraws: Integer;
    FFontSize: Double;
    FAbort: Boolean;
    FClock: TStopwatch;
    function Pop(out V: TPsVal): Boolean;
    function Peek(AFromTop: Integer; out V: TPsVal): Boolean;
    procedure Push(const V: TPsVal);
    procedure PushNum(const N: Double);
    procedure PushBool(AOn: Boolean);
    function PopNum(out N: Double): Boolean;
    function PopTwo(out A, B: Double): Boolean;
    procedure UserToDev(X, Y: Double; out DX, DY: Single);
    procedure AddMove(X, Y: Double);
    procedure AddLine(X, Y: Double);
    procedure AddCubic(X1, Y1, X2, Y2, X3, Y3: Double);
    procedure DoClose;
    function SnapshotPath(AEvenOdd: Boolean): ISkPath;
    procedure Paint(AFill, AStroke: Boolean; AEvenOdd: Boolean);
    procedure NewPath;
    procedure GSave;
    procedure GRestore;
    procedure ConcatM(const M: TMat);
    procedure DrawSamples(const Data: string; AW, AH, AComp: Integer;
      const Matrix: TArray<Double>);
    procedure DoImageDict(const D: TPsVal);
    procedure ExecRange(AFrom, ATo: Integer);
    procedure ExecName(const AName: string);
    procedure DoOp(AOp: Integer);
  public
    constructor Create(const ACanvas: ISkCanvas; const APage: TMat);
    destructor Destroy; override;
    function Run(const AScript: string): Integer;
  end;

var
  GOps: TDictionary<string, Integer>;

function Ident(const A, B, C, D, E, F: Double): TMat;
begin
  Result.A := A;
  Result.B := B;
  Result.C := C;
  Result.D := D;
  Result.E := E;
  Result.F := F;
end;

function MulMat(const L, R: TMat): TMat;
begin
  Result.A := L.A * R.A + L.C * R.B;
  Result.B := L.B * R.A + L.D * R.B;
  Result.C := L.A * R.C + L.C * R.D;
  Result.D := L.B * R.C + L.D * R.D;
  Result.E := L.A * R.E + L.C * R.F + L.E;
  Result.F := L.B * R.E + L.D * R.F + L.F;
end;

function Chan(const V: Double): Byte;
var
  X: Double;
begin
  X := V;
  if X > 1 then
    X := X / 255;
  X := EnsureRange(X, 0, 1);
  Result := Round(X * 255);
end;

function PackRGB(R, G, B: Byte): TAlphaColor;
var
  C: TAlphaColorRec;
begin
  C.R := R;
  C.G := G;
  C.B := B;
  C.A := 255;
  Result := C.Color;
end;

function ModP(A, B: Integer): Integer;
begin
  if B <= 0 then
    Exit(0);
  Result := A mod B;
  if Result < 0 then
    Inc(Result, B);
end;

function IsSpace(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = #12) or (C = #0);
end;

function DecodeHex(const S: string): string;
var
  I, N, V, D, OutN: Integer;
  C: Char;
begin
  SetLength(Result, Length(S) div 2 + 1);
  OutN := 0;
  N := 0;
  V := 0;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if IsSpace(C) then
      Continue;
    if (C >= '0') and (C <= '9') then
      D := Ord(C) - Ord('0')
    else if (C >= 'a') and (C <= 'f') then
      D := Ord(C) - Ord('a') + 10
    else if (C >= 'A') and (C <= 'F') then
      D := Ord(C) - Ord('A') + 10
    else
      Continue;
    V := (V shl 4) or D;
    Inc(N);
    if N = 2 then
    begin
      Inc(OutN);
      Result[OutN] := Char(V and $FF);
      N := 0;
      V := 0;
    end;
  end;
  if N = 1 then
  begin
    Inc(OutN);
    Result[OutN] := Char((V shl 4) and $FF);
  end;
  SetLength(Result, OutN);
end;

function DecodeA85(const S: string): string;
var
  I, N, K, Take, OutN: Integer;
  C: Char;
  V: Cardinal;
  Group: array[0..4] of Integer;
  Bytes: array[0..3] of Byte;
begin
  SetLength(Result, Length(S) * 4 + 4);
  OutN := 0;
  I := 1;
  while I <= Length(S) do
  begin
    C := S[I];
    if IsSpace(C) then
    begin
      Inc(I);
      Continue;
    end;
    if C = 'z' then
    begin
      Result[OutN + 1] := #0;
      Result[OutN + 2] := #0;
      Result[OutN + 3] := #0;
      Result[OutN + 4] := #0;
      Inc(OutN, 4);
      Inc(I);
      Continue;
    end;
    N := 0;
    while (I <= Length(S)) and (N < 5) do
    begin
      C := S[I];
      Inc(I);
      if IsSpace(C) then
        Continue;
      if (C = '~') or (C = '>') then
        Break;
      Group[N] := Ord(C) - 33;
      Inc(N);
    end;
    if N = 0 then
      Break;
    Take := N;
    while N < 5 do
    begin
      Group[N] := 84;
      Inc(N);
    end;
    V := 0;
    for K := 0 to 4 do
      V := V * 85 + Cardinal(Group[K]);
    Bytes[0] := Byte(V shr 24);
    Bytes[1] := Byte(V shr 16);
    Bytes[2] := Byte(V shr 8);
    Bytes[3] := Byte(V);
    for K := 0 to Take - 2 do
    begin
      Inc(OutN);
      Result[OutN] := Char(Bytes[K]);
    end;
  end;
  SetLength(Result, OutN);
end;

procedure AddTok(var AToks: TArray<TTok>; var AN: Integer; const ATok: TTok);
begin
  if AN >= Length(AToks) then
    SetLength(AToks, AN + 4096);
  AToks[AN] := ATok;
  Inc(AN);
end;

procedure Tokenize(const S: string; var AToks: TArray<TTok>; var AN: Integer);
var
  I, J, Depth, Start: Integer;
  C: Char;
  Tok: TTok;
  Chunk, NumS: string;
  FS: TFormatSettings;

  function At(K: Integer): Char;
  begin
    if (K >= 1) and (K <= Length(S)) then
      Result := S[K]
    else
      Result := #0;
  end;

begin
  FS := TFormatSettings.Invariant;
  I := 1;
  AN := 0;
  while I <= Length(S) do
  begin
    C := S[I];
    if IsSpace(C) then
    begin
      Inc(I);
      Continue;
    end;
    if C = '%' then
    begin
      if Copy(S, I, 12) = '%%BeginData:' then
      begin
        J := Pos('%%EndData', S, I + 12);
        if J > 0 then
          I := J + 9
        else
          Exit;
        Continue;
      end;
      while (I <= Length(S)) and (S[I] <> #10) and (S[I] <> #13) do
        Inc(I);
      Continue;
    end;
    if C = '(' then
    begin
      Chunk := '';
      Inc(I);
      Depth := 1;
      while (I <= Length(S)) and (Depth > 0) do
      begin
        C := S[I];
        Inc(I);
        if C = '\' then
        begin
          if I > Length(S) then
            Break;
          C := S[I];
          Inc(I);
          case C of
            'n': Chunk := Chunk + #10;
            'r': Chunk := Chunk + #13;
            't': Chunk := Chunk + #9;
            'b': Chunk := Chunk + #8;
            'f': Chunk := Chunk + #12;
            '\', '(', ')': Chunk := Chunk + C;
            #10, #13:
              if (C = #13) and (At(I) = #10) then
                Inc(I);
          else
            if (C >= '0') and (C <= '7') then
            begin
              J := Ord(C) - Ord('0');
              if (At(I) >= '0') and (At(I) <= '7') then
              begin
                J := J * 8 + Ord(At(I)) - Ord('0');
                Inc(I);
                if (At(I) >= '0') and (At(I) <= '7') then
                begin
                  J := J * 8 + Ord(At(I)) - Ord('0');
                  Inc(I);
                end;
              end;
              Chunk := Chunk + Char(J and $FF);
            end
            else
              Chunk := Chunk + C;
          end;
        end
        else if C = '(' then
        begin
          Inc(Depth);
          Chunk := Chunk + C;
        end
        else if C = ')' then
        begin
          Dec(Depth);
          if Depth > 0 then
            Chunk := Chunk + C;
        end
        else
          Chunk := Chunk + C;
      end;
      Tok.Kind := tkStr;
      Tok.Text := Chunk;
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
      Continue;
    end;
    if C = '<' then
    begin
      if At(I + 1) = '<' then
      begin
        Tok.Kind := tkName;
        Tok.Text := '<<';
        Tok.Num := 0;
        AddTok(AToks, AN, Tok);
        Inc(I, 2);
        Continue;
      end;
      if At(I + 1) = '~' then
      begin
        J := Pos('~>', S, I + 2);
        if J < 1 then
          Exit;
        Tok.Kind := tkStr;
        Tok.Text := DecodeA85(Copy(S, I + 2, J - (I + 2)));
        Tok.Num := 0;
        AddTok(AToks, AN, Tok);
        I := J + 2;
        Continue;
      end;
      J := Pos('>', S, I + 1);
      if J < 1 then
        Exit;
      Tok.Kind := tkStr;
      Tok.Text := DecodeHex(Copy(S, I + 1, J - (I + 1)));
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
      I := J + 1;
      Continue;
    end;
    if (C = '>') and (At(I + 1) = '>') then
    begin
      Tok.Kind := tkName;
      Tok.Text := '>>';
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
      Inc(I, 2);
      Continue;
    end;
    if C = '{' then
    begin
      Tok.Kind := tkLBrace;
      Tok.Text := '';
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
      Inc(I);
      Continue;
    end;
    if C = '}' then
    begin
      Tok.Kind := tkRBrace;
      Tok.Text := '';
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
      Inc(I);
      Continue;
    end;
    if (C = '[') or (C = ']') or (C = '>') then
    begin
      Tok.Kind := tkName;
      Tok.Text := C;
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
      Inc(I);
      Continue;
    end;
    if C = '/' then
    begin
      Start := I + 1;
      if At(Start) = '/' then
        Inc(Start);
      J := Start;
      while (J <= Length(S)) and not IsSpace(S[J]) and
            not CharInSet(S[J], ['/', '%', '(', ')', '<', '>', '[', ']', '{', '}']) do
        Inc(J);
      Tok.Kind := tkLit;
      Tok.Text := Copy(S, Start, J - Start);
      Tok.Num := 0;
      if At(I + 1) = '/' then
        Tok.Text := '//' + Tok.Text;
      AddTok(AToks, AN, Tok);
      I := J;
      Continue;
    end;
    Start := I;
    while (I <= Length(S)) and not IsSpace(S[I]) and
          not CharInSet(S[I], ['/', '%', '(', ')', '<', '>', '[', ']', '{', '}']) do
      Inc(I);
    NumS := Copy(S, Start, I - Start);
    if (NumS <> '') and TryStrToFloat(NumS, Tok.Num, FS) then
    begin
      Tok.Kind := tkNum;
      Tok.Text := '';
      AddTok(AToks, AN, Tok);
    end
    else if NumS <> '' then
    begin
      Tok.Kind := tkName;
      Tok.Text := NumS;
      Tok.Num := 0;
      AddTok(AToks, AN, Tok);
    end;
    if I = Start then
      Inc(I);
    if AN > 1500000 then
      Exit;
  end;
end;

constructor TEpsDraw.Create(const ACanvas: ISkCanvas; const APage: TMat);
begin
  inherited Create;
  FCanvas := ACanvas;
  FPage := APage;
  FUserM := Ident(1, 0, 0, 1, 0, 0);
  FFillC := PackRGB(0, 0, 0);
  FStrokeC := FFillC;
  FLineW := 1;
  FUser := TDictionary<string, TPsVal>.Create;
  FFontSize := 12;
  FBaseSave := FCanvas.Save;
end;

destructor TEpsDraw.Destroy;
begin
  FUser.Free;
  inherited;
end;

function TEpsDraw.Pop(out V: TPsVal): Boolean;
begin
  Result := FSP > 0;
  if not Result then
    Exit;
  Dec(FSP);
  V := FStack[FSP];
end;

function TEpsDraw.Peek(AFromTop: Integer; out V: TPsVal): Boolean;
var
  I: Integer;
begin
  I := FSP - 1 - AFromTop;
  Result := I >= 0;
  if Result then
    V := FStack[I];
end;

procedure TEpsDraw.Push(const V: TPsVal);
begin
  if FSP >= Length(FStack) then
    SetLength(FStack, FSP + 256);
  FStack[FSP] := V;
  Inc(FSP);
end;

procedure TEpsDraw.PushNum(const N: Double);
var
  V: TPsVal;
begin
  V := Default(TPsVal);
  V.Kind := pkNum;
  V.Num := N;
  Push(V);
end;

procedure TEpsDraw.PushBool(AOn: Boolean);
var
  V: TPsVal;
begin
  V := Default(TPsVal);
  V.Kind := pkBool;
  if AOn then
    V.Num := 1
  else
    V.Num := 0;
  Push(V);
end;

function TEpsDraw.PopNum(out N: Double): Boolean;
var
  V: TPsVal;
begin
  Result := Pop(V) and ((V.Kind = pkNum) or (V.Kind = pkBool));
  if Result then
    N := V.Num;
end;

function TEpsDraw.PopTwo(out A, B: Double): Boolean;
begin
  Result := PopNum(B) and PopNum(A);
end;

procedure TEpsDraw.UserToDev(X, Y: Double; out DX, DY: Single);
var
  X1, Y1: Double;
begin
  X1 := FUserM.A * X + FUserM.C * Y + FUserM.E;
  Y1 := FUserM.B * X + FUserM.D * Y + FUserM.F;
  DX := FPage.A * X1 + FPage.C * Y1 + FPage.E;
  DY := FPage.B * X1 + FPage.D * Y1 + FPage.F;
end;

procedure TEpsDraw.AddMove(X, Y: Double);
var
  V: TVerb;
begin
  if FPainted then
  begin
    FVerbN := 0;
    FPainted := False;
  end;
  FUx := X;
  FUy := Y;
  FSubX := X;
  FSubY := Y;
  FHasPt := True;
  UserToDev(X, Y, V.X1, V.Y1);
  V.Kind := vkMove;
  if FVerbN >= Length(FVerbs) then
    SetLength(FVerbs, FVerbN + 256);
  FVerbs[FVerbN] := V;
  Inc(FVerbN);
end;

procedure TEpsDraw.AddLine(X, Y: Double);
var
  V: TVerb;
begin
  if not FHasPt then
  begin
    AddMove(X, Y);
    Exit;
  end;
  FUx := X;
  FUy := Y;
  UserToDev(X, Y, V.X1, V.Y1);
  V.Kind := vkLine;
  if FVerbN >= Length(FVerbs) then
    SetLength(FVerbs, FVerbN + 256);
  FVerbs[FVerbN] := V;
  Inc(FVerbN);
end;

procedure TEpsDraw.AddCubic(X1, Y1, X2, Y2, X3, Y3: Double);
var
  V: TVerb;
begin
  if not FHasPt then
    AddMove(X1, Y1);
  UserToDev(X1, Y1, V.X1, V.Y1);
  UserToDev(X2, Y2, V.X2, V.Y2);
  UserToDev(X3, Y3, V.X3, V.Y3);
  V.Kind := vkCubic;
  if FVerbN >= Length(FVerbs) then
    SetLength(FVerbs, FVerbN + 256);
  FVerbs[FVerbN] := V;
  Inc(FVerbN);
  FUx := X3;
  FUy := Y3;
  FHasPt := True;
end;

procedure TEpsDraw.DoClose;
var
  V: TVerb;
begin
  if FVerbN < 1 then
    Exit;
  V.Kind := vkClose;
  if FVerbN >= Length(FVerbs) then
    SetLength(FVerbs, FVerbN + 16);
  FVerbs[FVerbN] := V;
  Inc(FVerbN);
  FUx := FSubX;
  FUy := FSubY;
  FHasPt := True;
end;

function TEpsDraw.SnapshotPath(AEvenOdd: Boolean): ISkPath;
var
  Path: ISkPathBuilder;
  I: Integer;
begin
  Result := nil;
  if FVerbN < 1 then
    Exit;
  Path := TSkPathBuilder.Create;
  if AEvenOdd then
    Path.FillType := TSkPathFillType.EvenOdd
  else
    Path.FillType := TSkPathFillType.Winding;
  for I := 0 to FVerbN - 1 do
    case FVerbs[I].Kind of
      vkMove:
        Path.MoveTo(FVerbs[I].X1, FVerbs[I].Y1);
      vkLine:
        Path.LineTo(FVerbs[I].X1, FVerbs[I].Y1);
      vkCubic:
        Path.CubicTo(FVerbs[I].X1, FVerbs[I].Y1, FVerbs[I].X2, FVerbs[I].Y2,
          FVerbs[I].X3, FVerbs[I].Y3);
      vkClose:
        Path.Close;
    end;
  Result := Path.Snapshot;
end;

procedure TEpsDraw.Paint(AFill, AStroke, AEvenOdd: Boolean);
var
  Snap: ISkPath;
  P: ISkPaint;
  Sc, Wpx: Double;
  M: TMat;
begin
  Snap := SnapshotPath(AEvenOdd);
  if Snap = nil then
    Exit;
  M := MulMat(FPage, FUserM);
  Sc := Sqrt(Abs(M.A * M.D - M.B * M.C));
  if Sc < 1e-6 then
    Sc := 1;
  if AFill then
  begin
    P := TSkPaint.Create(TSkPaintStyle.Fill);
    P.AntiAlias := True;
    P.Color := FFillC;
    FCanvas.DrawPath(Snap, P);
  end;
  if AStroke then
  begin
    Wpx := FLineW * Sc;
    if Wpx < 0.75 then
      Wpx := 0.75;
    P := TSkPaint.Create(TSkPaintStyle.Stroke);
    P.AntiAlias := True;
    P.Color := FStrokeC;
    P.StrokeWidth := Wpx;
    case FCap of
      1: P.StrokeCap := TSkStrokeCap.Round;
      2: P.StrokeCap := TSkStrokeCap.Square;
    else
      P.StrokeCap := TSkStrokeCap.Butt;
    end;
    case FJoin of
      1: P.StrokeJoin := TSkStrokeJoin.Round;
      2: P.StrokeJoin := TSkStrokeJoin.Bevel;
    else
      P.StrokeJoin := TSkStrokeJoin.Miter;
    end;
    FCanvas.DrawPath(Snap, P);
  end;
  FPainted := True;
  Inc(FDraws);
end;

procedure TEpsDraw.NewPath;
begin
  FVerbN := 0;
  FPainted := False;
  FHasPt := False;
end;

procedure TEpsDraw.GSave;
begin
  if FGsN >= 64 then
    Exit;
  if FGsN >= Length(FGs) then
    SetLength(FGs, FGsN + 16);
  FGs[FGsN].User := FUserM;
  FGs[FGsN].FillC := FFillC;
  FGs[FGsN].StrokeC := FStrokeC;
  FGs[FGsN].LineW := FLineW;
  FGs[FGsN].Cap := FCap;
  FGs[FGsN].Join := FJoin;
  FGs[FGsN].HasPt := FHasPt;
  FGs[FGsN].Ux := FUx;
  FGs[FGsN].Uy := FUy;
  FGs[FGsN].Painted := FPainted;
  FGs[FGsN].Verbs := Copy(FVerbs, 0, FVerbN);
  FGs[FGsN].VerbN := FVerbN;
  FGs[FGsN].SaveId := FCanvas.Save;
  Inc(FGsN);
end;

procedure TEpsDraw.GRestore;
begin
  if FGsN < 1 then
    Exit;
  Dec(FGsN);
  FUserM := FGs[FGsN].User;
  FFillC := FGs[FGsN].FillC;
  FStrokeC := FGs[FGsN].StrokeC;
  FLineW := FGs[FGsN].LineW;
  FCap := FGs[FGsN].Cap;
  FJoin := FGs[FGsN].Join;
  FHasPt := FGs[FGsN].HasPt;
  FUx := FGs[FGsN].Ux;
  FUy := FGs[FGsN].Uy;
  FPainted := FGs[FGsN].Painted;
  FVerbs := Copy(FGs[FGsN].Verbs, 0, FGs[FGsN].VerbN);
  FVerbN := FGs[FGsN].VerbN;
  FCanvas.RestoreToCount(FGs[FGsN].SaveId);
end;

procedure TEpsDraw.ConcatM(const M: TMat);
begin
  FUserM := MulMat(FUserM, M);
end;

procedure TEpsDraw.DrawSamples(const Data: string; AW, AH, AComp: Integer;
  const Matrix: TArray<Double>);
var
  Bmp: TBitmap;
  DataMap: TBitmapData;
  Img: ISkImage;
  X, Y, Src, Need: Integer;
  Pix: PByte;
  R, G, B, KK: Double;
  P00, P10, P01: TPointF;
  Dest: TRectF;
  IM, UM: TMat;

  function MapPoint(UX, UY: Double): TPointF;
  var
    X1, Y1: Double;
  begin
    X1 := UM.A * UX + UM.C * UY + UM.E;
    Y1 := UM.B * UX + UM.D * UY + UM.F;
    Result.X := FPage.A * X1 + FPage.C * Y1 + FPage.E;
    Result.Y := FPage.B * X1 + FPage.D * Y1 + FPage.F;
  end;

begin
  if (AW < 1) or (AH < 1) or (AW > 8000) or (AH > 8000) or (AComp < 1) then
    Exit;
  Need := AW * AH * AComp;
  if Length(Data) < Need then
    Exit;
  if Length(Matrix) < 6 then
    Exit;
  Bmp := TBitmap.Create(AW, AH);
  try
    if not Bmp.Map(TMapAccess.Write, DataMap) then
      Exit;
    try
      for Y := 0 to AH - 1 do
      begin
        Pix := PByte(DataMap.GetScanline(Y));
        for X := 0 to AW - 1 do
        begin
          Src := (Y * AW + X) * AComp + 1;
          if AComp = 1 then
          begin
            R := Ord(Data[Src]);
            G := R;
            B := R;
          end
          else if AComp >= 4 then
          begin
            KK := Ord(Data[Src + 3]) / 255;
            R := 255 * (1 - Ord(Data[Src]) / 255) * (1 - KK);
            G := 255 * (1 - Ord(Data[Src + 1]) / 255) * (1 - KK);
            B := 255 * (1 - Ord(Data[Src + 2]) / 255) * (1 - KK);
          end
          else
          begin
            R := Ord(Data[Src]);
            G := Ord(Data[Src + 1]);
            B := Ord(Data[Src + 2]);
          end;
          PAlphaColor(Pix + X * 4)^ := PackRGB(Chan(R / 255), Chan(G / 255), Chan(B / 255));
        end;
      end;
    finally
      Bmp.Unmap(DataMap);
    end;
    IM := Ident(Matrix[0], Matrix[1], Matrix[2], Matrix[3], Matrix[4], Matrix[5]);
    UM := MulMat(FUserM, IM);
    P00 := MapPoint(0, 0);
    P10 := MapPoint(1, 0);
    P01 := MapPoint(0, 1);
    Dest := TRectF.Create(
      Min(P00.X, Min(P10.X, P01.X)),
      Min(P00.Y, Min(P10.Y, P01.Y)),
      Max(P00.X, Max(P10.X, P01.X)),
      Max(P00.Y, Max(P10.Y, P01.Y)));
    if (Dest.Width < 1) or (Dest.Height < 1) then
      Exit;
    Img := Bmp.ToSkImage;
    if Img = nil then
      Exit;
    FCanvas.DrawImageRect(Img, Dest, TSkSamplingOptions.High);
    Inc(FDraws);
  finally
    Bmp.Free;
  end;
end;

function DictNum(const D: TPsVal; const AKey: string; out N: Double): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(D.Keys) do
    if D.Keys[I] = AKey then
    begin
      if (D.Vals[I].Kind = pkNum) or (D.Vals[I].Kind = pkBool) then
      begin
        N := D.Vals[I].Num;
        Exit(True);
      end;
    end;
end;

procedure TEpsDraw.DoImageDict(const D: TPsVal);
var
  W, H, Bits, Comp, I: Integer;
  N: Double;
  Matrix: TArray<Double>;
  Data: string;
begin
  if not DictNum(D, 'Width', N) then
    Exit;
  W := Round(N);
  if not DictNum(D, 'Height', N) then
    Exit;
  H := Round(N);
  Bits := 8;
  if DictNum(D, 'BitsPerComponent', N) then
    Bits := Round(N);
  if Bits <> 8 then
    Exit;
  Comp := 1;
  Data := '';
  SetLength(Matrix, 0);
  for I := 0 to High(D.Keys) do
  begin
    if (D.Keys[I] = 'DataSource') and (D.Vals[I].Kind = pkStr) then
      Data := D.Vals[I].Text
    else if (D.Keys[I] = 'ImageMatrix') and (D.Vals[I].Kind = pkArr) then
      Matrix := D.Vals[I].Nums
    else if D.Keys[I] = 'Decode' then
      Comp := Max(1, Length(D.Vals[I].Nums) div 2);
  end;
  if (Data = '') or (Length(Matrix) < 6) then
    Exit;
  if Length(Data) >= W * H * 3 then
    Comp := Max(Comp, 3);
  if Length(Data) >= W * H * 4 then
    Comp := Max(Comp, 4);
  DrawSamples(Data, W, H, Comp, Matrix);
end;

procedure TEpsDraw.ExecRange(AFrom, ATo: Integer);
var
  IP, Start, Depth, FromI, Count: Integer;
  Tok: TTok;
  V: TPsVal;
begin
  if FAbort or (FDepth > EpsMaxDepth) then
    Exit;
  Inc(FDepth);
  try
    IP := AFrom;
    while (IP < ATo) and not FAbort do
    begin
      Inc(FSteps);
      if FSteps > EpsMaxSteps then
      begin
        FAbort := True;
        Exit;
      end;
      if ((FSteps and 127) = 0) and (FClock.ElapsedMilliseconds > 2000) then
      begin
        FAbort := True;
        Exit;
      end;
      Tok := FToks[IP];
      case Tok.Kind of
        tkNum:
          begin
            PushNum(Tok.Num);
            Inc(IP);
          end;
        tkLit:
          begin
            if Copy(Tok.Text, 1, 2) = '//' then
              ExecName(Copy(Tok.Text, 3, MaxInt))
            else
            begin
              V := Default(TPsVal);
              V.Kind := pkName;
              V.Text := Tok.Text;
              Push(V);
            end;
            Inc(IP);
          end;
        tkStr:
          begin
            V := Default(TPsVal);
            V.Kind := pkStr;
            V.Text := Tok.Text;
            Push(V);
            Inc(IP);
          end;
        tkLBrace:
          begin
            Inc(IP);
            Start := IP;
            Depth := 1;
            while (IP < FTokN) and (Depth > 0) do
            begin
              if FToks[IP].Kind = tkLBrace then
                Inc(Depth)
              else if FToks[IP].Kind = tkRBrace then
                Dec(Depth);
              if Depth = 0 then
                Break;
              Inc(IP);
            end;
            V := Default(TPsVal);
            V.Kind := pkProc;
            V.ProcFrom := Start;
            V.ProcTo := IP;
            Push(V);
            Inc(IP);
          end;
        tkRBrace:
          Inc(IP);
        tkName:
          begin
            ExecName(Tok.Text);
            Inc(IP);
          end;
      else
        Inc(IP);
      end;
    end;
  finally
    Dec(FDepth);
  end;
  FromI := 0;
  Count := 0;
  if (FromI = Count) and (AFrom < 0) then
    Exit;
end;

procedure TEpsDraw.ExecName(const AName: string);
var
  V: TPsVal;
  Op: Integer;
begin
  if FUser.TryGetValue(AName, V) then
  begin
    if V.Kind = pkProc then
      ExecRange(V.ProcFrom, V.ProcTo)
    else
      Push(V);
    Exit;
  end;
  if (GOps <> nil) and GOps.TryGetValue(AName, Op) then
    DoOp(Op);
end;

procedure TEpsDraw.DoOp(AOp: Integer);
var
  A, B, C, D, E, Ff, G, H: Double;
  V, V2, Name: TPsVal;
  N, J, K, I: Integer;
  M: TMat;
  Items: TArray<TPsVal>;
  Nums: TArray<Double>;
  Keys: TArray<string>;
  Vals: TArray<TPsVal>;
  Ang1, Ang2, Rad, Step, Limit, Cur: Double;
  Font: ISkFont;
  Ink: ISkPaint;
  Snap: ISkPath;
  DX, DY: Single;
  Comp: Integer;
begin
  case AOp of
    1:
      if PopTwo(A, B) then
        AddMove(A, B);
    2:
      if PopTwo(A, B) then
        AddLine(A, B);
    3:
      if PopTwo(A, B) and FHasPt then
        AddMove(FUx + A, FUy + B);
    4:
      if PopTwo(A, B) and FHasPt then
        AddLine(FUx + A, FUy + B);
    5:
      if PopTwo(E, Ff) and PopTwo(C, D) and PopTwo(A, B) then
        AddCubic(A, B, C, D, E, Ff);
    6:
      if PopTwo(E, Ff) and PopTwo(C, D) and PopTwo(A, B) and FHasPt then
        AddCubic(FUx + A, FUy + B, FUx + C, FUy + D, FUx + E, FUy + Ff);
    7:
      DoClose;
    8:
      NewPath;
    9:
      Paint(False, True, False);
    10:
      Paint(True, False, False);
    11:
      Paint(True, False, True);
    12:
      if PopNum(C) and PopNum(B) and PopNum(A) then
      begin
        FFillC := PackRGB(Chan(A), Chan(B), Chan(C));
        FStrokeC := FFillC;
      end;
    13:
      if PopNum(A) then
      begin
        FFillC := PackRGB(Chan(A), Chan(A), Chan(A));
        FStrokeC := FFillC;
      end;
    14:
      if PopNum(D) and PopNum(C) and PopNum(B) and PopNum(A) then
      begin
        FFillC := PackRGB(
          Chan((1 - A) * (1 - D)),
          Chan((1 - B) * (1 - D)),
          Chan((1 - C) * (1 - D)));
        FStrokeC := FFillC;
      end;
    15:
      if PopNum(A) then
        FLineW := Abs(A);
    16:
      GSave;
    17:
      GRestore;
    18:
      if PopTwo(A, B) then
        ConcatM(Ident(1, 0, 0, 1, A, B));
    19:
      if PopTwo(A, B) then
        ConcatM(Ident(A, 0, 0, B, 0, 0));
    20:
      if PopNum(A) then
      begin
        A := DegToRad(A);
        ConcatM(Ident(Cos(A), Sin(A), -Sin(A), Cos(A), 0, 0));
      end;
    21:
      if Pop(V) and (V.Kind = pkArr) and (Length(V.Nums) >= 6) then
        ConcatM(Ident(V.Nums[0], V.Nums[1], V.Nums[2], V.Nums[3], V.Nums[4], V.Nums[5]));
    22, 23:
      if PopNum(Ang2) and PopNum(Ang1) and PopNum(Rad) and PopTwo(A, B) then
      begin
        if AOp = 23 then
          Step := -8
        else
          Step := 8;
        if FHasPt then
          AddLine(A + Rad * Cos(DegToRad(Ang1)), B + Rad * Sin(DegToRad(Ang1)))
        else
          AddMove(A + Rad * Cos(DegToRad(Ang1)), B + Rad * Sin(DegToRad(Ang1)));
        Cur := Ang1;
        K := 0;
        while (K < 90) and (((Step > 0) and (Cur < Ang2)) or ((Step < 0) and (Cur > Ang2))) do
        begin
          Cur := Cur + Step;
          if (Step > 0) and (Cur > Ang2) then
            Cur := Ang2;
          if (Step < 0) and (Cur < Ang2) then
            Cur := Ang2;
          AddLine(A + Rad * Cos(DegToRad(Cur)), B + Rad * Sin(DegToRad(Cur)));
          Inc(K);
        end;
      end;
    24:
      begin
        Snap := SnapshotPath(False);
        if Snap <> nil then
          FCanvas.ClipPath(Snap, TSkClipOp.Intersect, True);
      end;
    26:
      if PopNum(A) then
        FCap := EnsureRange(Round(A), 0, 2);
    27:
      if PopNum(A) then
        FJoin := EnsureRange(Round(A), 0, 2);
    28, 29:
      if PopNum(H) and PopNum(G) and PopTwo(A, B) then
      begin
        AddMove(A, B);
        AddLine(A + G, B);
        AddLine(A + G, B + H);
        AddLine(A, B + H);
        DoClose;
        if AOp = 28 then
          Paint(True, False, False)
        else
          Paint(False, True, False);
        NewPath;
      end;
    30:
      if Pop(V) and (V.Kind = pkStr) and (V.Text <> '') then
      begin
        UserToDev(FUx, FUy, DX, DY);
        Font := TSkFont.Create(TSkTypeface.MakeDefault,
          Max(1, FFontSize * Sqrt(Abs(FPage.A * FPage.D))), 1, 0);
        Ink := TSkPaint.Create(TSkPaintStyle.Fill);
        Ink.Color := FFillC;
        Ink.AntiAlias := True;
        FCanvas.DrawSimpleText(V.Text, DX, DY, Font, Ink);
        if FHasPt then
          FUx := FUx + Length(V.Text) * FFontSize * 0.5;
        Inc(FDraws);
      end;
    31:
      if Pop(V) then
      begin
        V2 := Default(TPsVal);
        V2.Kind := pkName;
        V2.Text := V.Text;
        V2.Num := FFontSize;
        Push(V2);
      end;
    32:
      if PopNum(A) and Pop(V) then
      begin
        V.Num := A;
        FFontSize := Abs(A);
        Push(V);
      end;
    33:
      if Pop(V) and (V.Num > 0) then
        FFontSize := Abs(V.Num);
    34:
      if Pop(Name) and Pop(V) and (Name.Kind = pkName) then
        FUser.AddOrSetValue(Name.Text, V);
    35:
      ;
    36:
      if Peek(0, V) then
        Push(V);
    37:
      if Pop(V) and Pop(V2) then
      begin
        Push(V);
        Push(V2);
      end;
    38:
      Pop(V);
    39:
      if PopNum(A) then
      begin
        N := Round(A);
        if Peek(N, V) then
          Push(V);
      end;
    40:
      if PopNum(B) and PopNum(A) then
      begin
        J := Round(A);
        N := Round(B);
        if (J > 0) and (J <= FSP) then
        begin
          SetLength(Items, J);
          for I := J - 1 downto 0 do
            Pop(Items[I]);
          for I := 0 to J - 1 do
            Push(Items[ModP(I - N, J)]);
        end;
      end;
    41:
      if PopNum(A) then
      begin
        N := Round(A);
        if (N > 0) and (N <= FSP) then
          for I := N - 1 downto 0 do
            if Peek(I, V) then
              Push(FStack[FSP - N + (N - 1 - I)]);
      end;
    42:
      if PopTwo(A, B) then
        PushNum(A + B);
    43:
      if PopTwo(A, B) then
        PushNum(A - B);
    44:
      if PopTwo(A, B) then
        PushNum(A * B);
    45:
      if PopTwo(A, B) and (Abs(B) > 1e-12) then
        PushNum(A / B);
    46:
      if PopNum(A) then
        PushNum(-A);
    47, 48:
      if PopNum(B) and PopNum(A) then
        PushBool((Abs(A - B) < 1e-6) xor (AOp = 48));
    49:
      if PopNum(B) and PopNum(A) then
        PushBool(A > B);
    50:
      if PopNum(B) and PopNum(A) then
        PushBool(A < B);
    51:
      if PopNum(B) and PopNum(A) then
        PushBool(A >= B);
    52:
      if PopNum(B) and PopNum(A) then
        PushBool(A <= B);
    53:
      if PopNum(B) and PopNum(A) then
        PushBool((Abs(A) > 1e-8) and (Abs(B) > 1e-8));
    54:
      if PopNum(B) and PopNum(A) then
        PushBool((Abs(A) > 1e-8) or (Abs(B) > 1e-8));
    55:
      if PopNum(A) then
        PushBool(Abs(A) <= 1e-8);
    56:
      if Pop(V) and PopNum(A) and (V.Kind = pkProc) and (Abs(A) > 1e-8) then
        ExecRange(V.ProcFrom, V.ProcTo);
    57:
      if Pop(V2) and Pop(V) and PopNum(A) then
      begin
        if Abs(A) > 1e-8 then
        begin
          if V.Kind = pkProc then
            ExecRange(V.ProcFrom, V.ProcTo);
        end
        else if V2.Kind = pkProc then
          ExecRange(V2.ProcFrom, V2.ProcTo);
      end;
    58:
      if Pop(V) and PopNum(A) and (V.Kind = pkProc) then
      begin
        N := EnsureRange(Round(A), 0, 100000);
        for I := 1 to N do
        begin
          if FAbort then
            Break;
          ExecRange(V.ProcFrom, V.ProcTo);
        end;
      end;
    59:
      if Pop(V) and PopNum(Limit) and PopNum(Step) and PopNum(Cur) and
         (V.Kind = pkProc) and (Abs(Step) > 1e-12) then
      begin
        K := 0;
        while (K < 100000) and not FAbort and
              (((Step > 0) and (Cur <= Limit + 1e-8)) or
               ((Step < 0) and (Cur >= Limit - 1e-8))) do
        begin
          PushNum(Cur);
          ExecRange(V.ProcFrom, V.ProcTo);
          Cur := Cur + Step;
          Inc(K);
        end;
      end;
    60:
      if Pop(V) then
      begin
        if V.Kind = pkProc then
          ExecRange(V.ProcFrom, V.ProcTo)
        else if V.Kind = pkName then
          ExecName(V.Text)
        else
          Push(V);
      end;
    61:
      if Peek(0, V) and (V.Kind = pkDict) then
      begin
        Pop(V);
        DoImageDict(V);
      end
      else if Peek(0, V) and Peek(1, V2) and (V2.Kind = pkArr) then
      begin
        Pop(V);
        Pop(V2);
        if PopNum(C) and PopNum(H) and PopNum(G) and (V.Kind = pkStr) then
        begin
          Comp := 1;
          if Length(V.Text) >= Round(G) * Round(H) * 3 then
            Comp := 3;
          DrawSamples(V.Text, Round(G), Round(H), Comp, V2.Nums);
        end;
      end;
    62:
      if Peek(0, V) and (V.Kind = pkNum) and Peek(1, V2) and (V2.Kind = pkStr) then
      begin
        PopNum(A);
        Pop(V2);
        if Pop(V) and (V.Kind = pkArr) and PopNum(C) and PopNum(H) and PopNum(G) then
          DrawSamples(V2.Text, Round(G), Round(H), Max(1, Round(A)), V.Nums);
      end;
    63:
      begin
        V := Default(TPsVal);
        V.Kind := pkMark;
        Push(V);
      end;
    64:
      begin
        SetLength(Items, 0);
        while Pop(V) and (V.Kind <> pkMark) do
        begin
          SetLength(Items, Length(Items) + 1);
          Items[High(Items)] := V;
        end;
        SetLength(Nums, 0);
        for I := High(Items) downto 0 do
          if (Items[I].Kind = pkNum) or (Items[I].Kind = pkBool) then
          begin
            SetLength(Nums, Length(Nums) + 1);
            Nums[High(Nums)] := Items[I].Num;
          end;
        V := Default(TPsVal);
        V.Kind := pkArr;
        V.Nums := Nums;
        Push(V);
      end;
    65:
      begin
        V := Default(TPsVal);
        V.Kind := pkMark;
        Push(V);
      end;
    66:
      begin
        SetLength(Keys, 0);
        SetLength(Vals, 0);
        while Pop(V) and (V.Kind <> pkMark) do
        begin
          if not Pop(Name) then
            Break;
          if Name.Kind = pkMark then
            Break;
          if Name.Kind = pkName then
          begin
            SetLength(Keys, Length(Keys) + 1);
            SetLength(Vals, Length(Vals) + 1);
            Keys[High(Keys)] := Name.Text;
            Vals[High(Vals)] := V;
          end;
        end;
        V := Default(TPsVal);
        V.Kind := pkDict;
        V.Keys := Keys;
        V.Vals := Vals;
        Push(V);
      end;
    67:
      PushBool(False);
    68:
      if Pop(Name) then
      begin
        if FUser.TryGetValue(Name.Text, V) then
          Push(V)
        else
          PushNum(0);
      end;
    69:
      ;
    70:
      begin
        Pop(V);
        Pop(V2);
      end;
    71:
      if PopNum(A) then
        PushNum(Abs(A));
    72:
      if PopNum(A) and (A >= 0) then
        PushNum(Sqrt(A));
    73:
      if PopTwo(A, B) and (Abs(B) > 1e-8) then
        PushNum(Int(A / B));
    74:
      if PopTwo(A, B) and (Abs(B) > 1e-8) then
        PushNum(A - B * Int(A / B));
    84:
      PushBool(True);
    85:
      PushBool(False);
    90:
      if PopTwo(E, Ff) and PopTwo(A, B) and FHasPt then
        AddCubic(FUx, FUy, A, B, E, Ff);
    91:
      if PopTwo(E, Ff) and PopTwo(A, B) then
        AddCubic(A, B, E, Ff, E, Ff);
    92:
      begin
        DoClose;
        Paint(False, True, False);
      end;
    93:
      Paint(True, True, False);
    94:
      begin
        DoClose;
        Paint(True, True, False);
      end;
    95:
      NewPath;
    96:
      begin
        DoClose;
        NewPath;
      end;
    97:
      if PopNum(D) and PopNum(C) and PopNum(B) and PopNum(A) then
        FFillC := PackRGB(Chan((1 - A) * (1 - D)), Chan((1 - B) * (1 - D)),
          Chan((1 - C) * (1 - D)));
    98:
      if PopNum(D) and PopNum(C) and PopNum(B) and PopNum(A) then
        FStrokeC := PackRGB(Chan((1 - A) * (1 - D)), Chan((1 - B) * (1 - D)),
          Chan((1 - C) * (1 - D)));
    99:
      if PopNum(A) then
        FFillC := PackRGB(Chan(A), Chan(A), Chan(A));
    100:
      if PopNum(A) then
        FStrokeC := PackRGB(Chan(A), Chan(A), Chan(A));
    101:
      if PopNum(C) and PopNum(B) and PopNum(A) then
        FFillC := PackRGB(Chan(A), Chan(B), Chan(C));
    102:
      if PopNum(C) and PopNum(B) and PopNum(A) then
        FStrokeC := PackRGB(Chan(A), Chan(B), Chan(C));
    103:
      if PopNum(A) then
        ;
  end;
end;

function TEpsDraw.Run(const AScript: string): Integer;
begin
  Tokenize(AScript, FToks, FTokN);
  FClock := TStopwatch.StartNew;
  FCanvas.Clear(TAlphaColors.White);
  ExecRange(0, FTokN);
  if FVerbN > 0 then
    Paint(True, False, False);
  Result := FDraws;
end;

function FindPreviewBox(const S: string; const AKey: string; out L, T, R, B: Double): Boolean;
var
  P, I: Integer;
  Line, Num: string;
  V: array[0..3] of Double;
  FS: TFormatSettings;
  N: Integer;
begin
  Result := False;
  FS := TFormatSettings.Invariant;
  P := 1;
  while P > 0 do
  begin
    P := Pos(AKey, S, P);
    if P < 1 then
      Exit;
    I := P + Length(AKey);
    while (I <= Length(S)) and (S[I] <> #10) and (S[I] <> #13) do
      Inc(I);
    Line := Trim(Copy(S, P + Length(AKey), I - (P + Length(AKey))));
    if Pos('atend', LowerCase(Line)) = 0 then
    begin
      N := 0;
      Num := '';
      Line := Line + ' ';
      for I := 1 to Length(Line) do
      begin
        if Line[I] = ' ' then
        begin
          if (Num <> '') and (N < 4) and TryStrToFloat(Num, V[N], FS) then
            Inc(N);
          Num := '';
        end
        else
          Num := Num + Line[I];
      end;
      if N = 4 then
      begin
        L := V[0];
        T := V[1];
        R := V[2];
        B := V[3];
        Exit(True);
      end;
    end;
    Inc(P, Length(AKey));
  end;
end;

function BytesToLatin(const B: TBytes; AFrom, ALen: Integer): string;
var
  I, N: Integer;
begin
  if AFrom < 0 then
    AFrom := 0;
  N := ALen;
  if AFrom + N > Length(B) then
    N := Length(B) - AFrom;
  if N < 0 then
    N := 0;
  if N > EpsMaxScript then
    N := EpsMaxScript;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I + 1] := Char(B[AFrom + I]);
end;

function TryPsPointSize(const APath: string; out W, H: Integer): Boolean;
var
  B: TBytes;
  S: string;
  L, T, R, Bm: Double;
begin
  Result := False;
  W := 0;
  H := 0;
  if not SameText(ExtractFileExt(APath), '.ai') then
    Exit;
  try
    B := ReadFileBytes(APath, 64 * 1024);
    S := BytesToLatin(B, 0, Length(B));
    if not FindPreviewBox(S, '%%HiResBoundingBox:', L, T, R, Bm) then
      if not FindPreviewBox(S, '%%BoundingBox:', L, T, R, Bm) then
        Exit;
    if (Abs(R - L) < 1) or (Abs(Bm - T) < 1) then
      Exit;
    W := Max(1, Round(Abs(R - L)));
    H := Max(1, Round(Abs(Bm - T)));
    Result := MetaSideOk(W, H);
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

procedure NScan(const S: string; AFrom: Integer; out W, H, Depth: Integer);
var
  I, N: Integer;
  Num: string;
  V: array[0..3] of Integer;
begin
  W := 0;
  H := 0;
  Depth := 1;
  N := 0;
  Num := '';
  I := AFrom;
  while (I <= Length(S)) and (N < 4) and (S[I] <> #10) and (S[I] <> #13) do
  begin
    if S[I] = ' ' then
    begin
      if Num <> '' then
      begin
        V[N] := StrToIntDef(Num, 0);
        Inc(N);
        Num := '';
      end;
    end
    else
      Num := Num + S[I];
    Inc(I);
  end;
  if Num <> '' then
  begin
    V[N] := StrToIntDef(Num, 0);
    Inc(N);
  end;
  if N >= 1 then
    W := V[0];
  if N >= 2 then
    H := V[1];
  if N >= 3 then
    Depth := V[2];
end;

function TryEpsi(const S: string; ABmp: TBitmap): Boolean;
var
  P, I, W, H, Depth, X, Y, Bit, Need: Integer;
  Hex: string;
  C: Char;
  Data: TBitmapData;
  Pix: PByte;
  White: Boolean;
begin
  Result := False;
  P := Pos('%%BeginPreview:', S);
  if P < 1 then
    Exit;
  NScan(S, P + Length('%%BeginPreview:'), W, H, Depth);
  if (Depth <> 1) or (W < 2) or (H < 2) or (W > 4000) or (H > 4000) then
    Exit;
  Hex := '';
  I := P;
  while (I <= Length(S)) and (S[I] <> #10) and (S[I] <> #13) do
    Inc(I);
  if I <= Length(S) then
    Inc(I);
  if (I <= Length(S)) and (S[I] = #10) then
    Inc(I);
  while I <= Length(S) do
  begin
    if Copy(S, I, 13) = '%%EndPreview' then
      Break;
    if S[I] = '%' then
    begin
      Inc(I);
      while (I <= Length(S)) and (S[I] <> #10) and (S[I] <> #13) do
      begin
        C := S[I];
        if CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F']) then
          Hex := Hex + C;
        Inc(I);
      end;
    end
    else
      Inc(I);
  end;
  Hex := DecodeHex(Hex);
  Need := (W * H + 7) div 8;
  if Length(Hex) < Need then
    Exit;
  ABmp.SetSize(W, H);
  if not ABmp.Map(TMapAccess.Write, Data) then
    Exit;
  try
    Bit := 0;
    for Y := 0 to H - 1 do
    begin
      Pix := PByte(Data.GetScanline(Y));
      for X := 0 to W - 1 do
      begin
        White := (Ord(Hex[(Bit div 8) + 1]) and (128 shr (Bit mod 8))) <> 0;
        Inc(Bit);
        if White then
          PAlphaColor(Pix + X * 4)^ := TAlphaColors.White
        else
          PAlphaColor(Pix + X * 4)^ := TAlphaColors.Black;
      end;
    end;
    Result := True;
  finally
    ABmp.Unmap(Data);
  end;
end;

function SliceBytes(const B: TBytes; AOff, ALen: Integer): TBytes;
begin
  SetLength(Result, 0);
  if (AOff < 0) or (ALen < 8) or (AOff + ALen > Length(B)) then
    Exit;
  SetLength(Result, ALen);
  Move(B[AOff], Result[0], ALen);
end;

function LoadEps(const APath: string; ABmp: TBitmap): Boolean;
var
  B: TBytes;
  Script: string;
  PsOff, PsLen, MfOff, MfLen, TfOff, TfLen: Integer;
  Preview, Vec: TBitmap;
  L, T, R, Bm, PW, PH, Scale: Double;
  Page: TMat;
  W, H, Draws: Integer;
  Slice: TBytes;
begin
  Result := False;
  B := ReadFileBytes(APath, VecMaxBytes);
  if Length(B) < 8 then
    Exit;
  PsOff := 0;
  PsLen := Length(B);
  MfOff := 0;
  MfLen := 0;
  TfOff := 0;
  TfLen := 0;
  if U32(B, 0) = EpsMagic then
  begin
    PsOff := Integer(U32(B, 4));
    PsLen := Integer(U32(B, 8));
    MfOff := Integer(U32(B, 12));
    MfLen := Integer(U32(B, 16));
    TfOff := Integer(U32(B, 20));
    TfLen := Integer(U32(B, 24));
  end;
  Preview := TBitmap.Create;
  Vec := TBitmap.Create;
  try
    Slice := SliceBytes(B, TfOff, TfLen);
    if not TryRasterBytes(Slice, Preview) then
    begin
      Slice := SliceBytes(B, MfOff, MfLen);
      if not RenderMetaBytes(Slice, Preview, -1) then
        Preview.SetSize(0, 0);
    end;
    if Preview.Width >= 300 then
    begin
      ABmp.Assign(Preview);
      Result := True;
      Exit;
    end;
    Script := BytesToLatin(B, PsOff, PsLen);
    if Preview.Width < 2 then
      TryEpsi(Script, Preview);
    if Preview.Width >= 300 then
    begin
      ABmp.Assign(Preview);
      Result := True;
      Exit;
    end;
    if not FindPreviewBox(Script, '%%HiResBoundingBox:', L, T, R, Bm) then
      if not FindPreviewBox(Script, '%%BoundingBox:', L, T, R, Bm) then
      begin
        L := 0;
        T := 0;
        R := 612;
        Bm := 792;
      end;
    PW := R - L;
    PH := Bm - T;
    if PW < 1 then
      PW := 612;
    if PH < 1 then
      PH := 792;
    Scale := 2000 / Max(PW, PH);
    W := Max(1, Round(PW * Scale));
    H := Max(1, Round(PH * Scale));
    ClampSide(W, H);
    Scale := W / PW;
    Page := Ident(Scale, 0, 0, -Scale, -L * Scale, Bm * Scale);
    Vec.SetSize(W, H);
    Draws := 0;
    Vec.SkiaDraw(
      procedure(const C: ISkCanvas)
      var
        Draw: TEpsDraw;
      begin
        Draw := TEpsDraw.Create(C, Page);
        try
          Draws := Draw.Run(Script);
        finally
          Draw.Free;
        end;
      end);
    if (Draws >= 3) or ((Draws > 0) and (Preview.Width < 300)) then
    begin
      ABmp.Assign(Vec);
      Result := ABmp.Width > 0;
    end
    else if Preview.Width > 1 then
    begin
      ABmp.Assign(Preview);
      Result := True;
    end
    else if Draws > 0 then
    begin
      ABmp.Assign(Vec);
      Result := ABmp.Width > 0;
    end;
  finally
    Preview.Free;
    Vec.Free;
  end;
end;

procedure RegisterOps;
begin
  GOps := TDictionary<string, Integer>.Create;
  GOps.Add('moveto', 1);
  GOps.Add('m', 1);
  GOps.Add('lineto', 2);
  GOps.Add('l', 2);
  GOps.Add('L', 2);
  GOps.Add('rmoveto', 3);
  GOps.Add('rlineto', 4);
  GOps.Add('curveto', 5);
  GOps.Add('c', 5);
  GOps.Add('rcurveto', 6);
  GOps.Add('C', 6);
  GOps.Add('closepath', 7);
  GOps.Add('h', 7);
  GOps.Add('H', 7);
  GOps.Add('newpath', 8);
  GOps.Add('stroke', 9);
  GOps.Add('s', 9);
  GOps.Add('fill', 10);
  GOps.Add('f', 10);
  GOps.Add('F', 10);
  GOps.Add('eofill', 11);
  GOps.Add('setrgbcolor', 12);
  GOps.Add('setgray', 13);
  GOps.Add('setcmykcolor', 14);
  GOps.Add('setlinewidth', 15);
  GOps.Add('w', 15);
  GOps.Add('gsave', 16);
  GOps.Add('q', 16);
  GOps.Add('grestore', 17);
  GOps.Add('Q', 17);
  GOps.Add('translate', 18);
  GOps.Add('scale', 19);
  GOps.Add('rotate', 20);
  GOps.Add('concat', 21);
  GOps.Add('arc', 22);
  GOps.Add('arcn', 23);
  GOps.Add('clip', 24);
  GOps.Add('setlinecap', 26);
  GOps.Add('J', 26);
  GOps.Add('setlinejoin', 27);
  GOps.Add('j', 27);
  GOps.Add('rectfill', 28);
  GOps.Add('rectstroke', 29);
  GOps.Add('show', 30);
  GOps.Add('findfont', 31);
  GOps.Add('scalefont', 32);
  GOps.Add('setfont', 33);
  GOps.Add('def', 34);
  GOps.Add('bdef', 34);
  GOps.Add('bind', 35);
  GOps.Add('dup', 36);
  GOps.Add('exch', 37);
  GOps.Add('pop', 38);
  GOps.Add('index', 39);
  GOps.Add('roll', 40);
  GOps.Add('copy', 41);
  GOps.Add('add', 42);
  GOps.Add('sub', 43);
  GOps.Add('mul', 44);
  GOps.Add('div', 45);
  GOps.Add('neg', 46);
  GOps.Add('eq', 47);
  GOps.Add('ne', 48);
  GOps.Add('gt', 49);
  GOps.Add('lt', 50);
  GOps.Add('ge', 51);
  GOps.Add('le', 52);
  GOps.Add('and', 53);
  GOps.Add('or', 54);
  GOps.Add('not', 55);
  GOps.Add('if', 56);
  GOps.Add('ifelse', 57);
  GOps.Add('repeat', 58);
  GOps.Add('for', 59);
  GOps.Add('exec', 60);
  GOps.Add('image', 61);
  GOps.Add('colorimage', 62);
  GOps.Add('[', 63);
  GOps.Add(']', 64);
  GOps.Add('<<', 65);
  GOps.Add('>>', 66);
  GOps.Add('where', 67);
  GOps.Add('load', 68);
  GOps.Add('showpage', 69);
  GOps.Add('setdash', 70);
  GOps.Add('d', 70);
  GOps.Add('abs', 71);
  GOps.Add('sqrt', 72);
  GOps.Add('idiv', 73);
  GOps.Add('mod', 74);
  GOps.Add('true', 84);
  GOps.Add('false', 85);
  GOps.Add('v', 90);
  GOps.Add('y', 91);
  GOps.Add('S', 92);
  GOps.Add('B', 93);
  GOps.Add('b', 94);
  GOps.Add('n', 95);
  GOps.Add('N', 96);
  GOps.Add('k', 97);
  GOps.Add('K', 98);
  GOps.Add('g', 99);
  GOps.Add('G', 100);
  GOps.Add('rg', 101);
  GOps.Add('RG', 102);
  GOps.Add('setmiterlimit', 103);
  GOps.Add('M', 103);
end;

function LoadVectorPreview(const APath: string; ABitmap: TBitmap;
  out ALabel: string; out APrintW, APrintH, AScreenW, AScreenH: Integer): Boolean;
var
  Ext: string;
  B: TBytes;
  Px: TMetaPx;

  procedure PlaySized;
  begin
    APrintW := Px.PrintW;
    APrintH := Px.PrintH;
    AScreenW := Px.ScreenW;
    AScreenH := Px.ScreenH;
    if (APrintW > 0) and (APrintH > 0) then
      Result := RenderMetaTarget(B, ABitmap, APrintW, APrintH)
    else if (AScreenW > 0) and (AScreenH > 0) then
      Result := RenderMetaTarget(B, ABitmap, AScreenW, AScreenH)
    else
      Result := RenderMetaBytes(B, ABitmap, 0);
  end;

begin
  Result := False;
  ALabel := '';
  APrintW := 0;
  APrintH := 0;
  AScreenW := 0;
  AScreenH := 0;
  if (APath = '') or (ABitmap = nil) or not FileExists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    if (Ext = '.emf') or (Ext = '.wmf') then
    begin
      B := ReadFileBytes(APath, VecMaxBytes);
      if Ext = '.emf' then
        EmfMetaPx(B, Px)
      else
        WmfMetaPx(B, Px);
      PlaySized;
    end
    else if Ext = '.eps' then
    begin
      ALabel := 'EPS';
      Result := LoadEps(APath, ABitmap);
    end
    else if (Ext = '.cdr') or (Ext = '.cdt') then
    begin
      ALabel := 'CDR';
      Result := LoadCdr(APath, ABitmap);
    end;
  except
    Result := False;
  end;
  if not Result then
  begin
    ALabel := '';
    APrintW := 0;
    APrintH := 0;
    AScreenW := 0;
    AScreenH := 0;
  end;
end;

initialization
  RegisterOps;

finalization
  GOps.Free;

end.
