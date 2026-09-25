unit uClipboardImage;

{
  Картинка из буфера Windows в байты PNG.
  Буфер открыт только на время копирования байт.
}

interface

uses
  System.SysUtils;

function TryClipboardImagePng(out APng: TBytes): Boolean;

implementation

uses
  System.Classes, System.Math,
  Winapi.Windows,
  FMX.Graphics, FMX.Surfaces, FMX.Types;

function CopyGlobal(H: HGLOBAL): TBytes;
var
  P: Pointer;
  N: NativeUInt;
begin
  SetLength(Result, 0);
  if H = 0 then
    Exit;
  N := GlobalSize(H);
  if N = 0 then
    Exit;
  P := GlobalLock(H);
  if P = nil then
    Exit;
  try
    SetLength(Result, N);
    Move(P^, Result[0], N);
  finally
    GlobalUnlock(H);
  end;
end;

function IsPng(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 8) and (ABytes[0] = $89) and (ABytes[1] = $50) and
    (ABytes[2] = $4E) and (ABytes[3] = $47);
end;

function SurfaceToPng(ASurf: TBitmapSurface): TBytes;
var
  Bmp: TBitmap;
  MS: TBytesStream;
begin
  SetLength(Result, 0);
  if (ASurf = nil) or (ASurf.Width < 1) or (ASurf.Height < 1) then
    Exit;
  Bmp := TBitmap.Create;
  MS := TBytesStream.Create;
  try
    Bmp.Assign(ASurf);
    Bmp.SaveToStream(MS);
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
      Move(MS.Bytes[0], Result[0], MS.Size);
  finally
    MS.Free;
    Bmp.Free;
  end;
end;

function BgraToPng(const APixels: TBytes; AWidth, AHeight: Integer;
  AForceOpaque: Boolean): TBytes;
var
  Surf: TBitmapSurface;
  Y, X: Integer;
  Src, Dst: PByte;
begin
  SetLength(Result, 0);
  if (AWidth < 1) or (AHeight < 1) or
     (Length(APixels) < AWidth * AHeight * 4) then
    Exit;
  Surf := TBitmapSurface.Create;
  try
    Surf.SetSize(AWidth, AHeight, TPixelFormat.BGRA);
    for Y := 0 to AHeight - 1 do
    begin
      Src := @APixels[Y * AWidth * 4];
      Dst := Surf.Scanline[Y];
      Move(Src^, Dst^, AWidth * 4);
      if AForceOpaque then
        for X := 0 to AWidth - 1 do
          PByte(NativeUInt(Dst) + X * 4 + 3)^ := 255;
    end;
    Result := SurfaceToPng(Surf);
  finally
    Surf.Free;
  end;
end;

function DibToPng(const AData: TBytes): TBytes;
var
  Hdr: PBitmapInfoHeader;
  W, H, BitCount, Stride, Off, Y, X, SrcY: Integer;
  TopDown, AnyAlpha: Boolean;
  Bits, Src, Dst: PByte;
  Surf: TBitmapSurface;
  Pix: PByte;
begin
  SetLength(Result, 0);
  if Length(AData) < SizeOf(TBitmapInfoHeader) then
    Exit;
  Hdr := @AData[0];
  if (Hdr.biWidth <= 0) or (Hdr.biWidth > 16000) then
    Exit;
  W := Hdr.biWidth;
  H := Abs(Hdr.biHeight);
  if (H <= 0) or (H > 16000) then
    Exit;
  TopDown := Hdr.biHeight < 0;
  BitCount := Hdr.biBitCount;
  if not (BitCount in [24, 32]) then
    Exit;
  if not (Hdr.biCompression in [BI_RGB, BI_BITFIELDS]) then
    Exit;
  Off := Hdr.biSize;
  if (Hdr.biSize <= SizeOf(TBitmapInfoHeader)) and (Hdr.biCompression = BI_BITFIELDS) then
    Inc(Off, 12);
  if Off < 0 then
    Exit;
  Stride := ((W * BitCount + 31) div 32) * 4;
  if (Off > Length(AData)) or (Int64(Stride) * H > Length(AData) - Off) then
    Exit;
  Bits := @AData[Off];
  AnyAlpha := False;
  if BitCount = 32 then
    for Y := 0 to H - 1 do
    begin
      Src := Bits + Y * Stride;
      for X := 0 to W - 1 do
        if PByte(NativeUInt(Src) + X * 4 + 3)^ <> 0 then
        begin
          AnyAlpha := True;
          Break;
        end;
      if AnyAlpha then
        Break;
    end;
  Surf := TBitmapSurface.Create;
  try
    Surf.SetSize(W, H, TPixelFormat.BGRA);
    for Y := 0 to H - 1 do
    begin
      if TopDown then
        SrcY := Y
      else
        SrcY := H - 1 - Y;
      Src := Bits + SrcY * Stride;
      Dst := Surf.Scanline[Y];
      if BitCount = 32 then
      begin
        Move(Src^, Dst^, W * 4);
        if not AnyAlpha then
          for X := 0 to W - 1 do
            PByte(NativeUInt(Dst) + X * 4 + 3)^ := 255;
      end
      else
        for X := 0 to W - 1 do
        begin
          Pix := PByte(NativeUInt(Dst) + X * 4);
          Pix^ := PByte(NativeUInt(Src) + X * 3)^;
          PByte(NativeUInt(Pix) + 1)^ := PByte(NativeUInt(Src) + X * 3 + 1)^;
          PByte(NativeUInt(Pix) + 2)^ := PByte(NativeUInt(Src) + X * 3 + 2)^;
          PByte(NativeUInt(Pix) + 3)^ := 255;
        end;
    end;
    Result := SurfaceToPng(Surf);
  finally
    Surf.Free;
  end;
end;

function BitmapHandleToBgra(ABmp: HBITMAP; out AWidth, AHeight: Integer): TBytes;
var
  Info: TBitmapInfo;
  Bm: BITMAP;
  DC: HDC;
  N: Integer;
begin
  SetLength(Result, 0);
  AWidth := 0;
  AHeight := 0;
  if GetObject(ABmp, SizeOf(Bm), @Bm) = 0 then
    Exit;
  AWidth := Bm.bmWidth;
  AHeight := Abs(Bm.bmHeight);
  if (AWidth < 1) or (AHeight < 1) or (AWidth > 16000) or (AHeight > 16000) then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  Info.bmiHeader.biWidth := AWidth;
  Info.bmiHeader.biHeight := -AHeight;
  Info.bmiHeader.biPlanes := 1;
  Info.bmiHeader.biBitCount := 32;
  Info.bmiHeader.biCompression := BI_RGB;
  N := AWidth * AHeight * 4;
  SetLength(Result, N);
  DC := GetDC(0);
  try
    if GetDIBits(DC, ABmp, 0, AHeight, @Result[0], Info, DIB_RGB_COLORS) = 0 then
      SetLength(Result, 0);
  finally
    ReleaseDC(0, DC);
  end;
end;

function TryClipboardImagePng(out APng: TBytes): Boolean;
var
  PngFmt, PngMime, DibV5: UINT;
  H: HGLOBAL;
  Raw, Bgra: TBytes;
  Kind, W, Hgt: Integer;
  Bmp: HBITMAP;
begin
  Result := False;
  SetLength(APng, 0);
  Kind := 0;
  W := 0;
  Hgt := 0;
  SetLength(Raw, 0);
  SetLength(Bgra, 0);
  if not OpenClipboard(0) then
    Exit;
  try
    PngFmt := RegisterClipboardFormat('PNG');
    PngMime := RegisterClipboardFormat('image/png');
    DibV5 := CF_DIBV5;
    if (PngFmt <> 0) and IsClipboardFormatAvailable(PngFmt) then
    begin
      Raw := CopyGlobal(GetClipboardData(PngFmt));
      Kind := 1;
    end
    else if (PngMime <> 0) and IsClipboardFormatAvailable(PngMime) then
    begin
      Raw := CopyGlobal(GetClipboardData(PngMime));
      Kind := 1;
    end
    else if IsClipboardFormatAvailable(DibV5) then
    begin
      Raw := CopyGlobal(GetClipboardData(DibV5));
      Kind := 2;
    end
    else if IsClipboardFormatAvailable(CF_DIB) then
    begin
      Raw := CopyGlobal(GetClipboardData(CF_DIB));
      Kind := 2;
    end
    else if IsClipboardFormatAvailable(CF_BITMAP) then
    begin
      H := GetClipboardData(CF_BITMAP);
      Bmp := HBITMAP(H);
      Bgra := BitmapHandleToBgra(Bmp, W, Hgt);
      Kind := 3;
    end;
  finally
    CloseClipboard;
  end;
  case Kind of
    1:
      if IsPng(Raw) then
        APng := Raw;
    2:
      APng := DibToPng(Raw);
    3:
      APng := BgraToPng(Bgra, W, Hgt, True);
  end;
  Result := Length(APng) > 0;
end;

end.
