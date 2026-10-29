unit uImageSniff;

{
  Сигнатура картинки, кадры ICO/CUR и запись multi-size ICO.
}

interface

uses
  System.SysUtils,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  FMX.Graphics;

type
  TImageSig = (isNone, isJpeg, isPng, isGif, isWebp, isBmp, isIco, isCur,
    isPdf, isSvg, isHeic, isAvif, isJxl, isPe, isZip);

function SniffImageFile(const APath: string): TImageSig;
function ImageSigName(ASig: TImageSig): string;
function ImageSigExt(ASig: TImageSig): string;
function ImageExtMatches(ASig: TImageSig; const AExt: string): Boolean;

function LoadIcoFrames(const APath: string; out AFrames: TArray<TBitmap>;
  out ALabels: TArray<string>): Boolean;
function SaveMultiIco(const ASource: TBitmap; const APath: string): Boolean;

type
  TImageSaveFormat = (isfPng, isfJpeg, isfWebp, isfBmp, isfIco);

{ Запись кадра без окна. Пакетный конвертер зовёт эту же функцию. }
function SaveImage(const ABitmap: TBitmap; const APath: string;
  AFormat: TImageSaveFormat; AQuality: Integer): Boolean;

implementation

uses
  System.Classes, System.Math, System.UITypes, System.IOUtils,
  FMX.Types, FMX.Surfaces, FMX.Skia, System.Skia;

function SniffImageFile(const APath: string): TImageSig;
var
  FS: TFileStream;
  B: TBytes;
  N: Integer;
  S: string;
begin
  Result := isNone;
  if (APath = '') or not System.IOUtils.TFile.Exists(APath) then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(64), FS.Size));
      if N < 4 then
        Exit;
      SetLength(B, N);
      FS.ReadBuffer(B[0], N);
    finally
      FS.Free;
    end;
  except
    Exit;
  end;
  if (B[0] = $FF) and (B[1] = $D8) and (B[2] = $FF) then
    Exit(isJpeg);
  if (B[0] = $89) and (B[1] = $50) and (B[2] = $4E) and (B[3] = $47) then
    Exit(isPng);
  if (N >= 6) and (B[0] = Ord('G')) and (B[1] = Ord('I')) and (B[2] = Ord('F')) then
    Exit(isGif);
  if (N >= 12) and (B[0] = Ord('R')) and (B[1] = Ord('I')) and (B[2] = Ord('F')) and
     (B[3] = Ord('F')) and (B[8] = Ord('W')) and (B[9] = Ord('E')) and
     (B[10] = Ord('B')) and (B[11] = Ord('P')) then
    Exit(isWebp);
  if (B[0] = Ord('B')) and (B[1] = Ord('M')) then
    Exit(isBmp);
  if (B[0] = 0) and (B[1] = 0) and (B[2] = 1) and (B[3] = 0) then
    Exit(isIco);
  if (B[0] = 0) and (B[1] = 0) and (B[2] = 2) and (B[3] = 0) then
    Exit(isCur);
  if (B[0] = Ord('%')) and (B[1] = Ord('P')) and (B[2] = Ord('D')) and (B[3] = Ord('F')) then
    Exit(isPdf);
  if (B[0] = Ord('M')) and (B[1] = Ord('Z')) then
    Exit(isPe);
  { docx/xlsx/pptx/3mf и прочие OOXML — это тоже PK. Не картинка и не подмена типа. }
  if (B[0] = $50) and (B[1] = $4B) then
    Exit(isNone);
  if (N >= 12) and (B[4] = Ord('f')) and (B[5] = Ord('t')) and (B[6] = Ord('y')) and
     (B[7] = Ord('p')) then
  begin
    SetLength(S, 4);
    S[1] := Char(B[8]);
    S[2] := Char(B[9]);
    S[3] := Char(B[10]);
    S[4] := Char(B[11]);
    S := LowerCase(S);
    if (S = 'avif') or (S = 'avis') then
      Exit(isAvif);
    if (S = 'heic') or (S = 'heix') or (S = 'hevc') or (S = 'mif1') or (S = 'msf1') then
      Exit(isHeic);
  end;
  if (N >= 12) and (B[0] = 0) and (B[1] = 0) and (B[2] = 0) and (B[3] = $0C) and
     (B[4] = $4A) and (B[5] = $58) and (B[6] = $4C) and (B[7] = $20) then
    Exit(isJxl);
  SetLength(S, N);
  for N := 0 to High(B) do
    if B[N] < 128 then
      S[N + 1] := Char(B[N])
    else
      S[N + 1] := ' ';
  S := LowerCase(S);
  if (Pos('<svg', S) > 0) or ((Pos('<?xml', S) > 0) and (Pos('svg', S) > 0)) then
    Exit(isSvg);
end;

function ImageSigName(ASig: TImageSig): string;
begin
  case ASig of
    isJpeg: Result := 'JPEG';
    isPng: Result := 'PNG';
    isGif: Result := 'GIF';
    isWebp: Result := 'WEBP';
    isBmp: Result := 'BMP';
    isIco: Result := 'ICO';
    isCur: Result := 'CUR';
    isPdf: Result := 'PDF';
    isSvg: Result := 'SVG';
    isHeic: Result := 'HEIC';
    isAvif: Result := 'AVIF';
    isJxl: Result := 'JXL';
    isPe: Result := 'EXE';
    isZip: Result := 'ZIP';
  else
    Result := '';
  end;
end;

function ImageSigExt(ASig: TImageSig): string;
begin
  case ASig of
    isJpeg: Result := '.jpg';
    isPng: Result := '.png';
    isGif: Result := '.gif';
    isWebp: Result := '.webp';
    isBmp: Result := '.bmp';
    isIco: Result := '.ico';
    isCur: Result := '.cur';
    isPdf: Result := '.pdf';
    isSvg: Result := '.svg';
    isHeic: Result := '.heic';
    isAvif: Result := '.avif';
    isJxl: Result := '.jxl';
    isPe: Result := '.exe';
    isZip: Result := '.zip';
  else
    Result := '';
  end;
end;

function ImageExtMatches(ASig: TImageSig; const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  case ASig of
    isJpeg: Result := (E = '.jpg') or (E = '.jpeg') or (E = '.jpe') or (E = '.jfif');
    isPng: Result := E = '.png';
    isGif: Result := E = '.gif';
    isWebp: Result := E = '.webp';
    isBmp: Result := E = '.bmp';
    isIco: Result := E = '.ico';
    isCur: Result := E = '.cur';
    isPdf: Result := (E = '.pdf') or (E = '.ai');
    isSvg: Result := (E = '.svg') or (E = '.svgz');
    isHeic: Result := (E = '.heic') or (E = '.heif');
    isAvif: Result := E = '.avif';
    isJxl: Result := E = '.jxl';
    isPe: Result := (E = '.exe') or (E = '.dll') or (E = '.scr');
    isZip: Result := (E = '.zip') or (E = '.jar');
  else
    Result := True;
  end;
end;

{$IFDEF MSWINDOWS}
function IconToBitmap(AIcon: HICON; AWidth, AHeight: Integer): TBitmap;
var
  DC, Mem: HDC;
  Info: TBitmapInfo;
  Bits: Pointer;
  Dib: HBITMAP;
  Old: HGDIOBJ;
  Surf: TBitmapSurface;
  Y: Integer;
  Src, Dst: PByte;
begin
  Result := nil;
  if (AIcon = 0) or (AWidth < 1) or (AHeight < 1) then
    Exit;
  DC := GetDC(0);
  Mem := 0;
  Dib := 0;
  Old := 0;
  Surf := TBitmapSurface.Create;
  try
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    Info.bmiHeader.biWidth := AWidth;
    Info.bmiHeader.biHeight := -AHeight;
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    Dib := CreateDIBSection(DC, Info, DIB_RGB_COLORS, Bits, 0, 0);
    if (Dib = 0) or (Bits = nil) then
      Exit;
    Mem := CreateCompatibleDC(DC);
    Old := SelectObject(Mem, Dib);
    DrawIconEx(Mem, 0, 0, AIcon, AWidth, AHeight, 0, 0, DI_NORMAL);
    Surf.SetSize(AWidth, AHeight, TPixelFormat.BGRA);
    for Y := 0 to AHeight - 1 do
    begin
      Src := PByte(Bits);
      Inc(Src, Y * AWidth * 4);
      Dst := Surf.Scanline[Y];
      Move(Src^, Dst^, AWidth * 4);
    end;
    Result := TBitmap.Create;
    Result.Assign(Surf);
  finally
    if Old <> 0 then
      SelectObject(Mem, Old);
    if Mem <> 0 then
      DeleteDC(Mem);
    if Dib <> 0 then
      DeleteObject(Dib);
    ReleaseDC(0, DC);
    Surf.Free;
  end;
end;
{$ENDIF}

{ CUR хранит сам DIB, не ресурс RT_CURSOR. У классического кадра biHeight
  удвоен: сначала XOR, потом AND (бит 1 — дырка). DrawIconEx в 32-битный
  DIB часто пишет цвет с альфой 0, и плитка такой кадр выбрасывает. }
function CursorDibBitmap(const ABytes: TBytes; AOff, ASize: Cardinal;
  ADirH: Integer): TBitmap;

  function U32(O: Integer): Cardinal;
  begin
    Result := Cardinal(ABytes[O]) or (Cardinal(ABytes[O + 1]) shl 8) or
      (Cardinal(ABytes[O + 2]) shl 16) or (Cardinal(ABytes[O + 3]) shl 24);
  end;

  function MaskBit(ARow, AX: Integer): Boolean;
  begin
    Result := (ABytes[ARow + (AX shr 3)] and (1 shl (7 - (AX and 7)))) <> 0;
  end;

var
  Base, Hdr, Bpp, Colors, ImgW, ImgH, AbsH, XorH: Integer;
  XorStride, AndStride, PixAt, X, Y, SrcY, Idx, Opaque: Integer;
  Need: Int64;
  TopDown, HasMask, UseAlpha: Boolean;
  Pal: array of array[0..2] of Byte;
  Surf: TBitmapSurface;
  RowXor, RowAnd: Integer;
  Dst: PByte;
  BB, GG, RR, AA, MaxA: Byte;
begin
  Result := nil;
  if (ASize < 40) or (Int64(AOff) + ASize > Length(ABytes)) then
    Exit;
  Base := Integer(AOff);
  Hdr := Integer(U32(Base));
  if (Hdr < 40) or (Hdr > Integer(ASize)) then
    Exit;
  ImgW := Integer(U32(Base + 4));
  ImgH := Integer(U32(Base + 8));
  Bpp := ABytes[Base + 14] or (ABytes[Base + 15] shl 8);
  if (U32(Base + 16) <> 0) or (ImgW < 1) or (ImgH = 0) then
    Exit;
  if not (Bpp in [1, 4, 8, 24, 32]) then
    Exit;
  if ImgH = Low(Integer) then
    Exit;
  TopDown := ImgH < 0;
  AbsH := Abs(ImgH);
  if (ADirH > 0) and (AbsH = ADirH * 2) then
  begin
    XorH := ADirH;
    HasMask := True;
  end
  else if (ADirH > 0) and (AbsH = ADirH) then
  begin
    XorH := ADirH;
    HasMask := False;
  end
  else if (AbsH mod 2) = 0 then
  begin
    XorH := AbsH div 2;
    HasMask := True;
  end
  else
  begin
    XorH := AbsH;
    HasMask := False;
  end;
  if (ImgW > 2048) or (XorH < 1) or (XorH > 2048) then
    Exit;
  Colors := 0;
  if Bpp <= 8 then
  begin
    Colors := Integer(U32(Base + 32));
    if Colors = 0 then
      Colors := 1 shl Bpp
    else if (Colors < 1) or (Colors > (1 shl Bpp)) then
      Exit;
  end;
  if Int64(Hdr) + Int64(Colors) * 4 > ASize then
    Exit;
  PixAt := Base + Hdr + Colors * 4;
  XorStride := ((ImgW * Bpp + 31) div 32) * 4;
  AndStride := ((ImgW + 31) div 32) * 4;
  Need := Int64(XorStride) * XorH;
  if HasMask then
    Inc(Need, Int64(AndStride) * XorH);
  if Int64(PixAt) + Need > Int64(Base) + ASize then
    Exit;
  SetLength(Pal, Colors);
  for Idx := 0 to Colors - 1 do
  begin
    Pal[Idx][0] := ABytes[Base + Hdr + Idx * 4];
    Pal[Idx][1] := ABytes[Base + Hdr + Idx * 4 + 1];
    Pal[Idx][2] := ABytes[Base + Hdr + Idx * 4 + 2];
  end;
  UseAlpha := False;
  if Bpp = 32 then
  begin
    MaxA := 0;
    for Y := 0 to XorH - 1 do
    begin
      RowXor := PixAt + Y * XorStride;
      for X := 0 to ImgW - 1 do
        if ABytes[RowXor + X * 4 + 3] > MaxA then
          MaxA := ABytes[RowXor + X * 4 + 3];
    end;
    UseAlpha := MaxA > 0;
  end;
  Surf := TBitmapSurface.Create;
  try
    Surf.SetSize(ImgW, XorH, TPixelFormat.BGRA);
    Opaque := 0;
    for Y := 0 to XorH - 1 do
    begin
      if TopDown then
        SrcY := Y
      else
        SrcY := XorH - 1 - Y;
      RowXor := PixAt + SrcY * XorStride;
      RowAnd := PixAt + XorH * XorStride + SrcY * AndStride;
      Dst := Surf.Scanline[Y];
      for X := 0 to ImgW - 1 do
      begin
        BB := 0;
        GG := 0;
        RR := 0;
        AA := 255;
        Idx := 0;
        case Bpp of
          1:
            begin
              Idx := (ABytes[RowXor + (X shr 3)] shr (7 - (X and 7))) and 1;
              if Idx < Colors then
              begin
                BB := Pal[Idx][0];
                GG := Pal[Idx][1];
                RR := Pal[Idx][2];
              end;
            end;
          4:
            begin
              if (X and 1) = 0 then
                Idx := ABytes[RowXor + (X shr 1)] shr 4
              else
                Idx := ABytes[RowXor + (X shr 1)] and $0F;
              if Idx < Colors then
              begin
                BB := Pal[Idx][0];
                GG := Pal[Idx][1];
                RR := Pal[Idx][2];
              end;
            end;
          8:
            begin
              Idx := ABytes[RowXor + X];
              if Idx < Colors then
              begin
                BB := Pal[Idx][0];
                GG := Pal[Idx][1];
                RR := Pal[Idx][2];
              end;
            end;
          24:
            begin
              BB := ABytes[RowXor + X * 3];
              GG := ABytes[RowXor + X * 3 + 1];
              RR := ABytes[RowXor + X * 3 + 2];
            end;
          32:
            begin
              BB := ABytes[RowXor + X * 4];
              GG := ABytes[RowXor + X * 4 + 1];
              RR := ABytes[RowXor + X * 4 + 2];
              if UseAlpha then
                AA := ABytes[RowXor + X * 4 + 3]
              else
                AA := 255;
            end;
        end;
        if HasMask and not UseAlpha and MaskBit(RowAnd, X) then
        begin
          { AND=1 и белый XOR — это инверсия экрана. На плитке рисуем чёрным. }
          if (Bpp = 1) and (Idx = 1) then
          begin
            BB := 0;
            GG := 0;
            RR := 0;
            AA := 255;
          end
          else
          begin
            BB := 0;
            GG := 0;
            RR := 0;
            AA := 0;
          end;
        end;
        Dst[0] := BB;
        Dst[1] := GG;
        Dst[2] := RR;
        Dst[3] := AA;
        Inc(Dst, 4);
        if AA > 12 then
          Inc(Opaque);
      end;
    end;
    if Opaque = 0 then
      Exit;
    Result := TBitmap.Create;
    try
      Result.Assign(Surf);
    except
      FreeAndNil(Result);
    end;
  finally
    Surf.Free;
  end;
end;

function LoadIcoFrames(const APath: string; out AFrames: TArray<TBitmap>;
  out ALabels: TArray<string>): Boolean;
{$IFDEF MSWINDOWS}
var
  Bytes: TBytes;
  Count, I, W, H: Integer;
  Off, Size: Cardinal;
  Icon: HICON;
  Bmp: TBitmap;
  Png: TBytesStream;
  IsCur: Boolean;
{$ENDIF}
begin
  Result := False;
  SetLength(AFrames, 0);
  SetLength(ALabels, 0);
  {$IFDEF MSWINDOWS}
  try
    Bytes := System.IOUtils.TFile.ReadAllBytes(APath);
  except
    Exit;
  end;
  if Length(Bytes) < 6 then
    Exit;
  IsCur := (Bytes[2] = 2) and (Bytes[3] = 0);
  Count := Bytes[4] or (Bytes[5] shl 8);
  if (Count < 1) or (Count > 64) or (Length(Bytes) < 6 + Count * 16) then
    Exit;
  for I := 0 to Count - 1 do
  begin
    W := Bytes[6 + I * 16];
    H := Bytes[6 + I * 16 + 1];
    if W = 0 then
      W := 256;
    if H = 0 then
      H := 256;
    Size := PCardinal(@Bytes[6 + I * 16 + 8])^;
    Off := PCardinal(@Bytes[6 + I * 16 + 12])^;
    if (Off = 0) or (Size = 0) or (Int64(Off) + Size > Length(Bytes)) then
      Continue;
    Bmp := nil;
    if (Size >= 8) and (Bytes[Off] = $89) and (Bytes[Off + 1] = $50) then
    begin
      Png := TBytesStream.Create;
      try
        Png.WriteBuffer(Bytes[Off], Size);
        Png.Position := 0;
        Bmp := TBitmap.Create;
        try
          Bmp.LoadFromStream(Png);
        except
          FreeAndNil(Bmp);
        end;
      finally
        Png.Free;
      end;
    end
    else
    begin
      if IsCur then
      try
        Bmp := CursorDibBitmap(Bytes, Off, Size, H);
      except
        FreeAndNil(Bmp);
      end;
      if Bmp = nil then
      begin
        Icon := CreateIconFromResourceEx(@Bytes[Off], Size, True, $00030000, W, H, 0);
        if Icon <> 0 then
        try
          Bmp := IconToBitmap(Icon, W, H);
        finally
          DestroyIcon(Icon);
        end;
      end;
    end;
    if (Bmp <> nil) and (Bmp.Width > 0) then
    begin
      SetLength(AFrames, Length(AFrames) + 1);
      SetLength(ALabels, Length(ALabels) + 1);
      AFrames[High(AFrames)] := Bmp;
      ALabels[High(ALabels)] := Format('%d×%d', [Bmp.Width, Bmp.Height]);
    end
    else
      Bmp.Free;
  end;
  Result := Length(AFrames) > 0;
  {$ENDIF}
end;

function ScaledFrame(const ASource: TBitmap; ASize: Integer): TBitmap;
var
  S: Single;
begin
  Result := TBitmap.Create(ASize, ASize);
  S := ASize / Max(ASource.Width, ASource.Height);
  Result.SkiaDraw(
    procedure(const C: ISkCanvas)
    begin
      C.Clear(TAlphaColors.Null);
      C.Translate((ASize - ASource.Width * S) / 2, (ASize - ASource.Height * S) / 2);
      C.Scale(S, S);
      C.DrawImage(ASource.ToSkImage, 0, 0);
    end);
end;

procedure WriteWord(AStream: TStream; AValue: Word);
begin
  AStream.WriteBuffer(AValue, SizeOf(AValue));
end;

procedure WriteByte(AStream: TStream; AValue: Byte);
begin
  AStream.WriteBuffer(AValue, 1);
end;

procedure WriteCard(AStream: TStream; AValue: Cardinal);
begin
  AStream.WriteBuffer(AValue, SizeOf(AValue));
end;

function SaveMultiIco(const ASource: TBitmap; const APath: string): Boolean;
const
  Sizes: array[0..4] of Integer = (16, 32, 48, 64, 256);
var
  Frames: array[0..4] of TBytes;
  Used: array[0..4] of Integer;
  I, Count, Off: Integer;
  FS: TFileStream;
  Bmp: TBitmap;
  MS: TMemoryStream;
  Img: ISkImage;
  Data: TBytes;
  Side: Byte;
begin
  Result := False;
  if (ASource = nil) or (ASource.Width < 1) then
    Exit;
  Count := 0;
  for I := 0 to High(Sizes) do
  begin
    Bmp := ScaledFrame(ASource, Sizes[I]);
    try
      Img := Bmp.ToSkImage;
      if Img = nil then
        Continue;
      Data := Img.Encode(TSkEncodedImageFormat.PNG, 100);
      if Length(Data) = 0 then
        Continue;
      Frames[Count] := Data;
      Used[Count] := Sizes[I];
      Inc(Count);
    finally
      Bmp.Free;
    end;
  end;
  if Count = 0 then
    Exit;
  FS := TFileStream.Create(APath, fmCreate);
  try
    MS := TMemoryStream.Create;
    try
      WriteWord(MS, 0);
      WriteWord(MS, 1);
      WriteWord(MS, Count);
      Off := 6 + Count * 16;
      for I := 0 to Count - 1 do
      begin
        if Used[I] >= 256 then
          Side := 0
        else
          Side := Byte(Used[I]);
        WriteByte(MS, Side);
        WriteByte(MS, Side);
        WriteByte(MS, 0);
        WriteByte(MS, 0);
        WriteWord(MS, 1);
        WriteWord(MS, 32);
        WriteCard(MS, Length(Frames[I]));
        WriteCard(MS, Off);
        Inc(Off, Length(Frames[I]));
      end;
      for I := 0 to Count - 1 do
        if Length(Frames[I]) > 0 then
          MS.WriteBuffer(Frames[I][0], Length(Frames[I]));
      MS.Position := 0;
      FS.CopyFrom(MS, MS.Size);
      Result := True;
    finally
      MS.Free;
    end;
  finally
    FS.Free;
  end;
end;

function FlattenOnWhite(const ASource: TBitmap): TBitmap;
var
  Src: ISkImage;
begin
  Result := TBitmap.Create(ASource.Width, ASource.Height);
  Src := ASource.ToSkImage;
  Result.SkiaDraw(
    procedure(const C: ISkCanvas)
    begin
      C.Clear(TAlphaColors.White);
      if Src <> nil then
        C.DrawImage(Src, 0, 0);
    end);
end;

function SaveBmpFile(const ABitmap: TBitmap; const APath: string): Boolean;
var
  Data: TBitmapData;
  FS: TFileStream;
  W, H, X, Y, RowBytes, Stride, FileSize: Integer;
  Hdr: array[0..53] of Byte;
  Row: TBytes;
  C: TAlphaColorRec;
begin
  Result := False;
  if (ABitmap = nil) or (ABitmap.Width < 1) or (ABitmap.Height < 1) or
     (APath = '') then
    Exit;
  if not ABitmap.Map(TMapAccess.Read, Data) then
    Exit;
  FS := nil;
  try
    try
      W := ABitmap.Width;
      H := ABitmap.Height;
      RowBytes := W * 3;
      Stride := ((RowBytes + 3) div 4) * 4;
      FileSize := 54 + Stride * H;
      FillChar(Hdr, SizeOf(Hdr), 0);
      Hdr[0] := Ord('B');
      Hdr[1] := Ord('M');
      PCardinal(@Hdr[2])^ := Cardinal(FileSize);
      PCardinal(@Hdr[10])^ := 54;
      PCardinal(@Hdr[14])^ := 40;
      PInteger(@Hdr[18])^ := W;
      PInteger(@Hdr[22])^ := H;
      PWord(@Hdr[26])^ := 1;
      PWord(@Hdr[28])^ := 24;
      PCardinal(@Hdr[34])^ := Cardinal(Stride * H);
      SetLength(Row, Stride);
      FS := TFileStream.Create(APath, fmCreate);
      FS.WriteBuffer(Hdr, 54);
      for Y := H - 1 downto 0 do
      begin
        FillChar(Row[0], Stride, 0);
        for X := 0 to W - 1 do
        begin
          C := TAlphaColorRec(Data.GetPixel(X, Y));
          Row[X * 3] := C.B;
          Row[X * 3 + 1] := C.G;
          Row[X * 3 + 2] := C.R;
        end;
        FS.WriteBuffer(Row[0], Stride);
      end;
      Result := FS.Size = FileSize;
    except
      Result := False;
    end;
  finally
    ABitmap.Unmap(Data);
    FS.Free;
  end;
  if not Result and TFile.Exists(APath) then
    try
      TFile.Delete(APath);
    except
    end;
end;

function SaveImage(const ABitmap: TBitmap; const APath: string;
  AFormat: TImageSaveFormat; AQuality: Integer): Boolean;
var
  Img: ISkImage;
  Fmt: TSkEncodedImageFormat;
  Q: Integer;
  Flat, SrcBmp: TBitmap;
begin
  Result := False;
  if (ABitmap = nil) or (ABitmap.Width < 1) or (ABitmap.Height < 1) or
     (APath = '') then
    Exit;
  if AFormat = isfIco then
    Exit(SaveMultiIco(ABitmap, APath));
  Flat := nil;
  SrcBmp := ABitmap;
  if AFormat in [isfJpeg, isfBmp] then
  begin
    Flat := FlattenOnWhite(ABitmap);
    SrcBmp := Flat;
  end;
  try
    if AFormat = isfBmp then
      Exit(SaveBmpFile(SrcBmp, APath));
    case AFormat of
      isfJpeg: Fmt := TSkEncodedImageFormat.JPEG;
      isfWebp: Fmt := TSkEncodedImageFormat.WEBP;
    else
      Fmt := TSkEncodedImageFormat.PNG;
    end;
    Q := 100;
    if AFormat in [isfJpeg, isfWebp] then
      Q := EnsureRange(AQuality, 1, 100);
    Img := SrcBmp.ToSkImage;
    if Img = nil then
      Exit;
    try
      Result := Img.EncodeToFile(APath, Fmt, Q);
    except
      Result := False;
    end;
  finally
    Flat.Free;
  end;
end;

end.
