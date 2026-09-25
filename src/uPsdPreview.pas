unit uPsdPreview;

{
  Просмотр PSD/PSB без Photoshop: встроенный JPEG-thumbnail и
  композитное изображение (RAW / PackBits / ZIP).
}

interface

uses
  System.SysUtils, System.Classes, FMX.Graphics;

function IsPsdThumbExt(const APath: string): Boolean;
function LooksLikePsd(const APath: string): Boolean;
function RenderPsdThumbRaw(const APath: string; AMaxW, AMaxH: Integer;
  out APixels: TBytes; out AWidth, AHeight: Integer): Boolean;
function LoadPsdPreview(const APath: string; AMaxW, AMaxH: Integer;
  ABitmap: FMX.Graphics.TBitmap; out ASrcW, ASrcH: Integer): Boolean;

implementation

uses
  System.Math, System.ZLib, System.Types, System.UITypes,
  System.Skia, FMX.Skia, FMX.Types;

const
  PsdMaxPixels: Int64 = 40000000;
  PsdMaxPlanar: Int64 = 220000000;
  PsdMaxResourceScan: Int64 = 24 * 1024 * 1024;
  PsdSig: array[0..3] of Byte = ($38, $42, $50, $53); { '8BPS' }
  ResSig: array[0..3] of Byte = ($38, $42, $49, $4D); { '8BIM' }

  CM_BITMAP = 0;
  CM_GRAY = 1;
  CM_INDEXED = 2;
  CM_RGB = 3;
  CM_CMYK = 4;
  CM_MULTI = 7;
  CM_DUOTONE = 8;
  CM_LAB = 9;

  COMP_RAW = 0;
  COMP_RLE = 1;
  COMP_ZIP = 2;
  COMP_ZIPPRED = 3;

type
  TPsdHeader = record
    IsPsb: Boolean;
    Channels: Integer;
    Width: Integer;
    Height: Integer;
    Depth: Integer;
    ColorMode: Integer;
  end;

  TPsdThumb = record
    Present: Boolean;
    Jpeg: Boolean;
    Bgr: Boolean;
    Width: Integer;
    Height: Integer;
    WidthBytes: Integer;
    Data: TBytes;
  end;

function Remain(S: TStream): Int64;
begin
  Result := S.Size - S.Position;
  if Result < 0 then
    Result := 0;
end;

function ReadExact(S: TStream; var Buf; Count: Integer): Boolean;
begin
  Result := (Count >= 0) and (Remain(S) >= Count) and
    (S.Read(Buf, Count) = Count);
end;

function ReadU8(S: TStream; out V: Byte): Boolean;
begin
  Result := ReadExact(S, V, 1);
end;

function ReadU16BE(S: TStream; out V: Word): Boolean;
var
  B: array[0..1] of Byte;
begin
  Result := ReadExact(S, B, 2);
  if Result then
    V := (Word(B[0]) shl 8) or B[1];
end;

function ReadU32BE(S: TStream; out V: Cardinal): Boolean;
var
  B: array[0..3] of Byte;
begin
  Result := ReadExact(S, B, 4);
  if Result then
    V := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or
      (Cardinal(B[2]) shl 8) or B[3];
end;

function ReadU64BE(S: TStream; out V: UInt64): Boolean;
var
  Hi, Lo: Cardinal;
begin
  Result := ReadU32BE(S, Hi) and ReadU32BE(S, Lo);
  if Result then
    V := (UInt64(Hi) shl 32) or Lo;
end;

function SkipBytes(S: TStream; Count: Int64): Boolean;
begin
  Result := False;
  if Count < 0 then
    Exit;
  if Count = 0 then
    Exit(True);
  if Remain(S) < Count then
    Exit;
  S.Position := S.Position + Count;
  Result := True;
end;

function ReadBuf(S: TStream; Count: Integer; out Data: TBytes): Boolean;
begin
  Result := False;
  SetLength(Data, 0);
  if Count < 0 then
    Exit;
  if Count = 0 then
    Exit(True);
  if Remain(S) < Count then
    Exit;
  SetLength(Data, Count);
  Result := S.Read(Data[0], Count) = Count;
  if not Result then
    SetLength(Data, 0);
end;

function IsPsdThumbExt(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.psd') or (Ext = '.psb');
end;

function LooksLikePsd(const APath: string): Boolean;
var
  S: TFileStream;
  Sig: array[0..3] of Byte;
  Ver: Word;
begin
  Result := False;
  if (APath = '') or not FileExists(APath) then
    Exit;
  try
    S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if not ReadExact(S, Sig, 4) then
        Exit;
      if not CompareMem(@Sig[0], @PsdSig[0], 4) then
        Exit;
      if not ReadU16BE(S, Ver) then
        Exit;
      Result := (Ver = 1) or (Ver = 2);
    finally
      S.Free;
    end;
  except
    Result := False;
  end;
end;

function ColorChannelCount(const H: TPsdHeader): Integer;
begin
  case H.ColorMode of
    CM_BITMAP, CM_GRAY, CM_INDEXED, CM_DUOTONE:
      Result := 1;
    CM_RGB, CM_LAB:
      Result := 3;
    CM_CMYK:
      Result := 4;
  else
    Result := Max(1, Min(H.Channels, 4));
  end;
end;

function BytesPerSample(Depth: Integer): Integer;
begin
  case Depth of
    1: Result := 0;
    8: Result := 1;
    16: Result := 2;
    32: Result := 4;
  else
    Result := 0;
  end;
end;

function PlaneRowBytes(Width, Depth: Integer): Int64;
begin
  if Depth = 1 then
    Result := (Int64(Width) + 7) shr 3
  else
    Result := Int64(Width) * BytesPerSample(Depth);
end;

function BeFloatToByte(P: PByte): Byte;
var
  U: Cardinal;
  F: Single;
begin
  U := (Cardinal(P[0]) shl 24) or (Cardinal(P[1]) shl 16) or
    (Cardinal(P[2]) shl 8) or P[3];
  Move(U, F, SizeOf(F));
  if IsNan(F) or (F <= 0) then
    Result := 0
  else if F >= 1 then
    Result := 255
  else
    Result := Byte(Round(F * 255));
end;

function SampleAt(const Plane: TBytes; Index, Depth: Integer): Byte;
var
  Off: Int64;
begin
  Result := 0;
  if Depth = 1 then
    Exit;
  Off := Int64(Index) * BytesPerSample(Depth);
  if (Off < 0) or (Off >= Length(Plane)) then
    Exit;
  case Depth of
    8:
      Result := Plane[Off];
    16:
      if Off + 1 < Length(Plane) then
        Result := Plane[Off];
    32:
      if Off + 3 < Length(Plane) then
        Result := BeFloatToByte(@Plane[Off]);
  end;
end;

function BitSample(const Plane: TBytes; X, Y, Width: Integer): Byte;
var
  RowBytes, Off: Int64;
  B: Byte;
begin
  Result := 255;
  RowBytes := (Int64(Width) + 7) shr 3;
  Off := Int64(Y) * RowBytes + (X shr 3);
  if (Off < 0) or (Off >= Length(Plane)) then
    Exit;
  B := Plane[Off];
  if ((B shr (7 - (X and 7))) and 1) <> 0 then
    Result := 0
  else
    Result := 255;
end;

procedure LabToRgb(L8, A8, B8: Byte; out R, G, B: Byte);
var
  Ls, As_, Bs, FY, FX, FZ, X, Y, Z, Rf, Gf, Bf: Double;

  function Pivot(T: Double): Double;
  begin
    if T > 0.20689655 then
      Result := T * T * T
    else
      Result := (T - 16 / 116) / 7.787;
  end;

  function Gamma(T: Double): Double;
  begin
    if T <= 0.0031308 then
      Result := 12.92 * T
    else
      Result := 1.055 * Power(T, 1 / 2.4) - 0.055;
  end;

  function Clamp01(T: Double): Byte;
  begin
    if T <= 0 then
      Result := 0
    else if T >= 1 then
      Result := 255
    else
      Result := Byte(Round(T * 255));
  end;

begin
  Ls := L8 * 100.0 / 255.0;
  As_ := Integer(A8) - 128;
  Bs := Integer(B8) - 128;
  FY := (Ls + 16.0) / 116.0;
  FX := As_ / 500.0 + FY;
  FZ := FY - Bs / 200.0;
  X := 0.95047 * Pivot(FX);
  Y := Pivot(FY);
  Z := 1.08883 * Pivot(FZ);
  Rf := 3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z;
  Gf := -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z;
  Bf := 0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z;
  R := Clamp01(Gamma(Rf));
  G := Clamp01(Gamma(Gf));
  B := Clamp01(Gamma(Bf));
end;

function BgraInfo(AWidth, AHeight: Integer): TSkImageInfo;
begin
  Result := TSkImageInfo.Create(AWidth, AHeight, TSkColorType.BGRA8888,
    TSkAlphaType.Unpremul);
end;

function EncodedToBgra(const Enc: TBytes; out Pix: TBytes;
  out W, H: Integer): Boolean;
var
  Img: ISkImage;
  Info: TSkImageInfo;
begin
  Result := False;
  SetLength(Pix, 0);
  W := 0;
  H := 0;
  if Length(Enc) < 8 then
    Exit;
  Img := TSkImage.MakeFromEncoded(Enc);
  if Img = nil then
    Exit;
  W := Img.Width;
  H := Img.Height;
  if (W < 1) or (H < 1) then
    Exit;
  Info := BgraInfo(W, H);
  SetLength(Pix, Int64(W) * H * 4);
  Result := Img.ReadPixels(Info, @Pix[0], NativeUInt(W) * 4);
  if not Result then
  begin
    SetLength(Pix, 0);
    W := 0;
    H := 0;
  end;
end;

function RawThumbToBgra(const Thumb: TPsdThumb; out Pix: TBytes): Boolean;
var
  X, Y, Stride: Integer;
  Src: Integer;
  R, G, B: Byte;
  Dst: Integer;
begin
  Result := False;
  SetLength(Pix, 0);
  if (Thumb.Width < 1) or (Thumb.Height < 1) or (Length(Thumb.Data) = 0) then
    Exit;
  Stride := Thumb.WidthBytes;
  if Stride <= 0 then
    Stride := Thumb.Width * 3;
  if Int64(Stride) * Thumb.Height > Length(Thumb.Data) then
    Exit;
  SetLength(Pix, Int64(Thumb.Width) * Thumb.Height * 4);
  for Y := 0 to Thumb.Height - 1 do
    for X := 0 to Thumb.Width - 1 do
    begin
      Src := Y * Stride + X * 3;
      if Thumb.Bgr then
      begin
        B := Thumb.Data[Src];
        G := Thumb.Data[Src + 1];
        R := Thumb.Data[Src + 2];
      end
      else
      begin
        R := Thumb.Data[Src];
        G := Thumb.Data[Src + 1];
        B := Thumb.Data[Src + 2];
      end;
      Dst := (Y * Thumb.Width + X) * 4;
      Pix[Dst] := B;
      Pix[Dst + 1] := G;
      Pix[Dst + 2] := R;
      Pix[Dst + 3] := 255;
    end;
  Result := True;
end;

function ScaleBgra(const Src: TBytes; SrcW, SrcH, DstW, DstH: Integer;
  out Dst: TBytes): Boolean;
var
  Img: ISkImage;
  SrcInfo, DstInfo: TSkImageInfo;
begin
  Result := False;
  SetLength(Dst, 0);
  if (SrcW < 1) or (SrcH < 1) or (DstW < 1) or (DstH < 1) then
    Exit;
  if Length(Src) < Int64(SrcW) * SrcH * 4 then
    Exit;
  if (SrcW = DstW) and (SrcH = DstH) then
  begin
    Dst := Copy(Src);
    Exit(True);
  end;
  SrcInfo := BgraInfo(SrcW, SrcH);
  Img := TSkImage.MakeRasterCopy(SrcInfo, @Src[0], NativeUInt(SrcW) * 4);
  if Img = nil then
    Exit;
  DstInfo := BgraInfo(DstW, DstH);
  SetLength(Dst, Int64(DstW) * DstH * 4);
  Result := Img.ScalePixels(DstInfo, @Dst[0], NativeUInt(DstW) * 4,
    TSkSamplingOptions.Medium);
  if not Result then
    SetLength(Dst, 0);
end;

procedure FitSize(SrcW, SrcH, MaxW, MaxH: Integer; out DstW, DstH: Integer);
var
  Scale: Double;
begin
  if MaxW < 8 then
    MaxW := 8;
  if MaxH < 8 then
    MaxH := 8;
  if (SrcW <= MaxW) and (SrcH <= MaxH) then
  begin
    DstW := SrcW;
    DstH := SrcH;
    Exit;
  end;
  Scale := Min(MaxW / SrcW, MaxH / SrcH);
  DstW := Max(1, Round(SrcW * Scale));
  DstH := Max(1, Round(SrcH * Scale));
end;

function IsEmptyBgra(const Pix: TBytes): Boolean;
var
  I: Integer;
begin
  Result := True;
  I := 0;
  while I <= Length(Pix) - 4 do
  begin
    if (Pix[I] <> 0) or (Pix[I + 1] <> 0) or (Pix[I + 2] <> 0) or
      (Pix[I + 3] <> 0) then
      Exit(False);
    Inc(I, 4);
  end;
end;

function UnpackBits(const Src: TBytes; DstLen: Integer; out Dst: TBytes): Boolean;
var
  I, O, N, C, Lim: Integer;
begin
  Result := False;
  SetLength(Dst, DstLen);
  if DstLen > 0 then
    FillChar(Dst[0], DstLen, 0);
  I := 0;
  O := 0;
  Lim := Length(Src);
  while (I < Lim) and (O < DstLen) do
  begin
    N := Src[I];
    Inc(I);
    if N < 128 then
    begin
      C := N + 1;
      if (I + C > Lim) or (O + C > DstLen) then
        Exit(False);
      Move(Src[I], Dst[O], C);
      Inc(I, C);
      Inc(O, C);
    end
    else if N > 128 then
    begin
      C := 257 - N;
      if (I >= Lim) or (O + C > DstLen) then
        Exit(False);
      FillChar(Dst[O], C, Src[I]);
      Inc(I);
      Inc(O, C);
    end;
  end;
  Result := O = DstLen;
end;

procedure UndoDelta8(var Row: TBytes; Width: Integer);
var
  X: Integer;
begin
  if (Width < 2) or (Length(Row) < Width) then
    Exit;
  for X := 1 to Width - 1 do
    Row[X] := Byte(Row[X] + Row[X - 1]);
end;

procedure UndoDelta16(var Row: TBytes; Width: Integer);
var
  X: Integer;
  Prev, Cur: Word;
begin
  if (Width < 2) or (Length(Row) < Width * 2) then
    Exit;
  Prev := (Word(Row[0]) shl 8) or Row[1];
  for X := 1 to Width - 1 do
  begin
    Cur := (Word(Row[X * 2]) shl 8) or Row[X * 2 + 1];
    Cur := Word(Cur + Prev);
    Row[X * 2] := Byte(Cur shr 8);
    Row[X * 2 + 1] := Byte(Cur);
    Prev := Cur;
  end;
end;

procedure UndoDelta32(var Row: TBytes; Width: Integer);
var
  X, B: Integer;
begin
  if (Width < 2) or (Length(Row) < Width * 4) then
    Exit;
  for X := 1 to Width - 1 do
    for B := 0 to 3 do
      Row[X * 4 + B] := Byte(Row[X * 4 + B] + Row[(X - 1) * 4 + B]);
end;

function InflateZlib(S: TStream; Expected: Int64; out Data: TBytes): Boolean;
var
  Z: TDecompressionStream;
  Total, N, Chunk: Integer;
  Buf: array[0..65535] of Byte;
begin
  Result := False;
  SetLength(Data, 0);
  if Expected <= 0 then
    Exit;
  if Expected > PsdMaxPlanar then
    Exit;
  try
    Z := TDecompressionStream.Create(S, 15);
    try
      SetLength(Data, Expected);
      Total := 0;
      while Total < Expected do
      begin
        Chunk := Integer(Min(Int64(SizeOf(Buf)), Expected - Total));
        N := Z.Read(Buf[0], Chunk);
        if N <= 0 then
          Break;
        Move(Buf[0], Data[Total], N);
        Inc(Total, N);
      end;
      if Total < Expected then
      begin
        if Total <= 0 then
        begin
          SetLength(Data, 0);
          Exit;
        end;
        FillChar(Data[Total], Integer(Expected - Total), 0);
      end;
      Result := True;
    finally
      Z.Free;
    end;
  except
    SetLength(Data, 0);
    Result := False;
  end;
end;

function ParseHeader(S: TStream; out H: TPsdHeader): Boolean;
var
  Sig: array[0..3] of Byte;
  Ver: Word;
  Reserved: array[0..5] of Byte;
  Ch, Depth, Mode: Word;
  W, Ht: Cardinal;
begin
  Result := False;
  FillChar(H, SizeOf(H), 0);
  if not ReadExact(S, Sig, 4) then
    Exit;
  if not CompareMem(@Sig[0], @PsdSig[0], 4) then
    Exit;
  if not ReadU16BE(S, Ver) then
    Exit;
  if (Ver <> 1) and (Ver <> 2) then
    Exit;
  if not ReadExact(S, Reserved, 6) then
    Exit;
  if not ReadU16BE(S, Ch) then
    Exit;
  if not ReadU32BE(S, Ht) then
    Exit;
  if not ReadU32BE(S, W) then
    Exit;
  if not ReadU16BE(S, Depth) then
    Exit;
  if not ReadU16BE(S, Mode) then
    Exit;
  if (Ch < 1) or (Ch > 56) then
    Exit;
  if (W < 1) or (Ht < 1) then
    Exit;
  if not (Depth in [1, 8, 16, 32]) then
    Exit;
  H.IsPsb := Ver = 2;
  H.Channels := Ch;
  H.Width := Integer(W);
  H.Height := Integer(Ht);
  H.Depth := Depth;
  H.ColorMode := Mode;
  Result := True;
end;

function SkipSection(S: TStream; LenBytes: Integer): Boolean;
var
  L32: Cardinal;
  L64: UInt64;
begin
  Result := False;
  if LenBytes = 8 then
  begin
    if not ReadU64BE(S, L64) then
      Exit;
    Result := SkipBytes(S, Int64(L64));
  end
  else
  begin
    if not ReadU32BE(S, L32) then
      Exit;
    Result := SkipBytes(S, L32);
  end;
end;

procedure ParseThumbResource(ID: Word; const Data: TBytes; var Thumb: TPsdThumb);
var
  Fmt, Tw, Th, Wb, Comp: Cardinal;
  Bits, Planes: Word;
  P: Integer;
  Jpeg: Boolean;
  Body: TBytes;
begin
  if Length(Data) < 28 then
    Exit;
  Fmt := (Cardinal(Data[0]) shl 24) or (Cardinal(Data[1]) shl 16) or
    (Cardinal(Data[2]) shl 8) or Data[3];
  Tw := (Cardinal(Data[4]) shl 24) or (Cardinal(Data[5]) shl 16) or
    (Cardinal(Data[6]) shl 8) or Data[7];
  Th := (Cardinal(Data[8]) shl 24) or (Cardinal(Data[9]) shl 16) or
    (Cardinal(Data[10]) shl 8) or Data[11];
  Wb := (Cardinal(Data[12]) shl 24) or (Cardinal(Data[13]) shl 16) or
    (Cardinal(Data[14]) shl 8) or Data[15];
  Comp := (Cardinal(Data[20]) shl 24) or (Cardinal(Data[21]) shl 16) or
    (Cardinal(Data[22]) shl 8) or Data[23];
  Bits := (Word(Data[24]) shl 8) or Data[25];
  Planes := (Word(Data[26]) shl 8) or Data[27];
  if (Tw < 1) or (Th < 1) or (Tw > 16384) or (Th > 16384) then
    Exit;
  if (Bits <> 0) and (Bits <> 24) then
    Exit;
  if (Planes <> 0) and (Planes <> 1) then
    Exit;
  P := 28;
  Jpeg := Fmt = 1;
  if Jpeg then
  begin
    if Comp > 0 then
    begin
      if Int64(P) + Comp > Length(Data) then
        Exit;
      SetLength(Body, Comp);
      Move(Data[P], Body[0], Comp);
    end
    else
    begin
      SetLength(Body, Length(Data) - P);
      if Length(Body) > 0 then
        Move(Data[P], Body[0], Length(Body));
    end;
  end
  else
  begin
    if Wb = 0 then
      Wb := Tw * 3;
    if Int64(Wb) * Th > Length(Data) - P then
      Exit;
    SetLength(Body, Int64(Wb) * Th);
    Move(Data[P], Body[0], Length(Body));
  end;
  { 1036 предпочтительнее 1033. }
  if Thumb.Present and (ID = $0409) then
    Exit;
  Thumb.Present := True;
  Thumb.Jpeg := Jpeg;
  Thumb.Bgr := ID = $0409;
  Thumb.Width := Integer(Tw);
  Thumb.Height := Integer(Th);
  Thumb.WidthBytes := Integer(Wb);
  Thumb.Data := Body;
end;

function ParseResources(S: TStream; out Thumb: TPsdThumb): Boolean;
var
  Len: Cardinal;
  ResEnd, Start, Taken: Int64;
  Sig: array[0..3] of Byte;
  ID: Word;
  NameLen: Byte;
  NamePad, Size: Cardinal;
  Data: TBytes;
  SizeI: Integer;
begin
  Result := False;
  Thumb.Present := False;
  Thumb.Jpeg := False;
  Thumb.Bgr := False;
  Thumb.Width := 0;
  Thumb.Height := 0;
  Thumb.WidthBytes := 0;
  SetLength(Thumb.Data, 0);
  if not ReadU32BE(S, Len) then
    Exit;
  Start := S.Position;
  ResEnd := Start + Len;
  if ResEnd > S.Size then
    Exit;
  Taken := 0;
  while S.Position + 10 <= ResEnd do
  begin
    if Taken > PsdMaxResourceScan then
      Break;
    if not ReadExact(S, Sig, 4) then
      Break;
    if not CompareMem(@Sig[0], @ResSig[0], 4) then
      Break;
    if not ReadU16BE(S, ID) then
      Break;
    if not ReadU8(S, NameLen) then
      Break;
    NamePad := NameLen;
    if ((NameLen + 1) and 1) <> 0 then
      Inc(NamePad);
    if not SkipBytes(S, NamePad) then
      Break;
    if not ReadU32BE(S, Size) then
      Break;
    if Size > $40000000 then
      Break;
    SizeI := Integer(Size);
    if S.Position + SizeI > ResEnd then
      Break;
    if ((ID = $040C) or (ID = $0409)) and (SizeI > 0) and
      (SizeI <= 16 * 1024 * 1024) then
    begin
      if not ReadBuf(S, SizeI, Data) then
        Break;
      ParseThumbResource(ID, Data, Thumb);
    end
    else if not SkipBytes(S, SizeI) then
      Break;
    if (Size and 1) <> 0 then
      if S.Position < ResEnd then
        if not SkipBytes(S, 1) then
          Break;
    Taken := S.Position - Start;
  end;
  S.Position := ResEnd;
  Result := True;
end;

function ReadColorModeData(S: TStream; ColorMode: Integer;
  out Palette: TBytes): Boolean;
var
  Len: Cardinal;
  Data: TBytes;
begin
  Result := False;
  SetLength(Palette, 0);
  if not ReadU32BE(S, Len) then
    Exit;
  if Len = 0 then
    Exit(True);
  if Len > 1024 * 1024 then
    Exit(SkipBytes(S, Len));
  if not ReadBuf(S, Integer(Len), Data) then
    Exit;
  if (ColorMode = CM_INDEXED) and (Length(Data) >= 768) then
  begin
    SetLength(Palette, 768);
    Move(Data[0], Palette[0], 768);
  end;
  Result := True;
end;

function DecodeRle(S: TStream; const H: TPsdHeader; PlaneSize, RowBytes: Int64;
  out Planar: TBytes): Boolean;
var
  CountSize, CountsBytes, Ch, Y, PackedLen, Need: Integer;
  Counts: TBytes;
  PackedRow, Unpacked: TBytes;
  Off: Int64;
  V32: Cardinal;
  V16: Word;
begin
  Result := False;
  SetLength(Planar, 0);
  if H.IsPsb then
    CountSize := 4
  else
    CountSize := 2;
  CountsBytes := H.Channels * H.Height * CountSize;
  if not ReadBuf(S, CountsBytes, Counts) then
    Exit;
  SetLength(Planar, PlaneSize * H.Channels);
  if Length(Planar) > 0 then
    FillChar(Planar[0], Length(Planar), 0);
  for Ch := 0 to H.Channels - 1 do
    for Y := 0 to H.Height - 1 do
    begin
      Off := (Int64(Ch) * H.Height + Y) * CountSize;
      if CountSize = 4 then
        V32 := (Cardinal(Counts[Off]) shl 24) or (Cardinal(Counts[Off + 1]) shl 16) or
          (Cardinal(Counts[Off + 2]) shl 8) or Counts[Off + 3]
      else
      begin
        V16 := (Word(Counts[Off]) shl 8) or Counts[Off + 1];
        V32 := V16;
      end;
      PackedLen := Integer(V32);
      if PackedLen < 0 then
        Exit;
      if PackedLen = 0 then
        Continue;
      if not ReadBuf(S, PackedLen, PackedRow) then
        Exit;
      Need := Integer(RowBytes);
      if not UnpackBits(PackedRow, Need, Unpacked) then
        Exit;
      Off := Int64(Ch) * PlaneSize + Int64(Y) * RowBytes;
      if Off + RowBytes <= Length(Planar) then
        Move(Unpacked[0], Planar[Off], Need);
    end;
  Result := True;
end;

function DecodeRaw(S: TStream; const H: TPsdHeader; PlaneSize: Int64;
  out Planar: TBytes): Boolean;
var
  Total: Int64;
begin
  Result := False;
  Total := PlaneSize * H.Channels;
  if (Total <= 0) or (Total > PsdMaxPlanar) then
    Exit;
  if Remain(S) < Total then
    Exit;
  SetLength(Planar, Total);
  Result := S.Read(Planar[0], Total) = Total;
  if not Result then
    SetLength(Planar, 0);
end;

function DecodeZip(S: TStream; const H: TPsdHeader; PlaneSize, RowBytes: Int64;
  Predict: Boolean; out Planar: TBytes): Boolean;
var
  Ch, Y: Integer;
  Row: TBytes;
  Off: Int64;
  Width: Integer;
begin
  Result := False;
  if not InflateZlib(S, PlaneSize * H.Channels, Planar) then
    Exit;
  if not Predict then
    Exit(True);
  Width := H.Width;
  SetLength(Row, Integer(RowBytes));
  for Ch := 0 to H.Channels - 1 do
    for Y := 0 to H.Height - 1 do
    begin
      Off := Int64(Ch) * PlaneSize + Int64(Y) * RowBytes;
      if Off + RowBytes > Length(Planar) then
        Exit(False);
      Move(Planar[Off], Row[0], Integer(RowBytes));
      case H.Depth of
        8: UndoDelta8(Row, Width);
        16: UndoDelta16(Row, Width);
        32: UndoDelta32(Row, Width);
      end;
      Move(Row[0], Planar[Off], Integer(RowBytes));
    end;
  Result := True;
end;

function PlaneSlice(const Planar: TBytes; Index: Integer; PlaneSize: Int64): TBytes;
var
  Off: Int64;
begin
  SetLength(Result, 0);
  if Index < 0 then
    Exit;
  Off := Int64(Index) * PlaneSize;
  if Off >= Length(Planar) then
    Exit;
  SetLength(Result, Integer(Min(PlaneSize, Length(Planar) - Off)));
  if Length(Result) > 0 then
    Move(Planar[Off], Result[0], Length(Result));
end;

function PlanarToBgra(const H: TPsdHeader; const Planar, Palette: TBytes;
  out Pix: TBytes): Boolean;
var
  X, Y, I, NColor, HasAlpha: Integer;
  PlaneSize: Int64;
  Ch: array[0..4] of TBytes;
  R, G, B, A, C, M, Yc, K, Idx: Byte;
  Dst: Integer;
  Gray: Byte;
begin
  Result := False;
  SetLength(Pix, 0);
  PlaneSize := Int64(H.Height) * PlaneRowBytes(H.Width, H.Depth);
  if PlaneSize <= 0 then
    Exit;
  NColor := ColorChannelCount(H);
  if NColor > H.Channels then
    NColor := H.Channels;
  for I := 0 to Min(4, H.Channels) - 1 do
    Ch[I] := PlaneSlice(Planar, I, PlaneSize);
  HasAlpha := Ord(H.Channels > NColor);
  if HasAlpha <> 0 then
    Ch[4] := PlaneSlice(Planar, NColor, PlaneSize);
  SetLength(Pix, Int64(H.Width) * H.Height * 4);
  for Y := 0 to H.Height - 1 do
    for X := 0 to H.Width - 1 do
    begin
      I := Y * H.Width + X;
      A := 255;
      R := 0;
      G := 0;
      B := 0;
      if H.Depth = 1 then
      begin
        Gray := BitSample(Ch[0], X, Y, H.Width);
        R := Gray;
        G := Gray;
        B := Gray;
      end
      else
      begin
        case H.ColorMode of
          CM_BITMAP, CM_GRAY, CM_DUOTONE, CM_MULTI:
            begin
              Gray := SampleAt(Ch[0], I, H.Depth);
              R := Gray;
              G := Gray;
              B := Gray;
              if (H.ColorMode = CM_MULTI) and (NColor >= 3) then
              begin
                R := SampleAt(Ch[0], I, H.Depth);
                G := SampleAt(Ch[1], I, H.Depth);
                B := SampleAt(Ch[2], I, H.Depth);
              end;
            end;
          CM_INDEXED:
            begin
              Idx := SampleAt(Ch[0], I, H.Depth);
              if Length(Palette) >= 768 then
              begin
                R := Palette[Idx];
                G := Palette[256 + Idx];
                B := Palette[512 + Idx];
              end
              else
              begin
                R := Idx;
                G := Idx;
                B := Idx;
              end;
            end;
          CM_RGB:
            begin
              R := SampleAt(Ch[0], I, H.Depth);
              if NColor > 1 then
                G := SampleAt(Ch[1], I, H.Depth)
              else
                G := R;
              if NColor > 2 then
                B := SampleAt(Ch[2], I, H.Depth)
              else
                B := R;
            end;
          CM_CMYK:
            begin
              C := SampleAt(Ch[0], I, H.Depth);
              M := SampleAt(Ch[1], I, H.Depth);
              Yc := SampleAt(Ch[2], I, H.Depth);
              K := SampleAt(Ch[3], I, H.Depth);
              { Composite CMYK хранится инвертированным. }
              R := Byte((Integer(C) * Integer(K)) div 255);
              G := Byte((Integer(M) * Integer(K)) div 255);
              B := Byte((Integer(Yc) * Integer(K)) div 255);
            end;
          CM_LAB:
            begin
              LabToRgb(SampleAt(Ch[0], I, H.Depth),
                SampleAt(Ch[1], I, H.Depth),
                SampleAt(Ch[2], I, H.Depth), R, G, B);
            end;
        else
          Gray := SampleAt(Ch[0], I, H.Depth);
          R := Gray;
          G := Gray;
          B := Gray;
        end;
        if HasAlpha <> 0 then
          A := SampleAt(Ch[4], I, H.Depth);
      end;
      Dst := I * 4;
      Pix[Dst] := B;
      Pix[Dst + 1] := G;
      Pix[Dst + 2] := R;
      Pix[Dst + 3] := A;
    end;
  Result := Length(Pix) > 0;
end;

function ThumbToBgra(const Thumb: TPsdThumb; out Pix: TBytes;
  out W, H: Integer): Boolean;
begin
  Result := False;
  W := 0;
  H := 0;
  if not Thumb.Present then
    Exit;
  if Thumb.Jpeg then
    Result := EncodedToBgra(Thumb.Data, Pix, W, H)
  else
  begin
    Result := RawThumbToBgra(Thumb, Pix);
    if Result then
    begin
      W := Thumb.Width;
      H := Thumb.Height;
    end;
  end;
end;

function DecodeComposite(S: TStream; const H: TPsdHeader; const Palette: TBytes;
  out Pix: TBytes): Boolean;
var
  Comp: Word;
  RowBytes, PlaneSize, Pixels: Int64;
  Planar: TBytes;
begin
  Result := False;
  SetLength(Pix, 0);
  Pixels := Int64(H.Width) * H.Height;
  if Pixels > PsdMaxPixels then
    Exit;
  RowBytes := PlaneRowBytes(H.Width, H.Depth);
  PlaneSize := RowBytes * H.Height;
  if (RowBytes <= 0) or (PlaneSize <= 0) or
    (PlaneSize * H.Channels > PsdMaxPlanar) then
    Exit;
  if not ReadU16BE(S, Comp) then
    Exit;
  case Comp of
    COMP_RAW:
      if not DecodeRaw(S, H, PlaneSize, Planar) then
        Exit;
    COMP_RLE:
      if not DecodeRle(S, H, PlaneSize, RowBytes, Planar) then
        Exit;
    COMP_ZIP:
      if not DecodeZip(S, H, PlaneSize, RowBytes, False, Planar) then
        Exit;
    COMP_ZIPPRED:
      if not DecodeZip(S, H, PlaneSize, RowBytes, True, Planar) then
        Exit;
  else
    Exit;
  end;
  if not PlanarToBgra(H, Planar, Palette, Pix) then
    Exit;
  if IsEmptyBgra(Pix) then
  begin
    SetLength(Pix, 0);
    Exit;
  end;
  Result := True;
end;

function FinishScaled(const Src: TBytes; SrcW, SrcH, MaxW, MaxH: Integer;
  out Dst: TBytes; out DstW, DstH: Integer): Boolean;
begin
  Result := False;
  SetLength(Dst, 0);
  DstW := 0;
  DstH := 0;
  if Length(Src) = 0 then
    Exit;
  FitSize(SrcW, SrcH, MaxW, MaxH, DstW, DstH);
  Result := ScaleBgra(Src, SrcW, SrcH, DstW, DstH, Dst);
  if not Result then
  begin
    DstW := 0;
    DstH := 0;
  end;
end;

function RenderPsdRaw(const APath: string; AMaxW, AMaxH: Integer;
  APreferFull: Boolean; out APixels: TBytes; out AWidth, AHeight, ASrcW,
  ASrcH: Integer): Boolean;
var
  S: TFileStream;
  H: TPsdHeader;
  Thumb: TPsdThumb;
  Palette, CompPix, ThumbPix, OutPix: TBytes;
  LayerLenBytes: Integer;
  Tw, Th, Dw, Dh: Integer;
  HaveComp, HaveThumb: Boolean;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  ASrcW := 0;
  ASrcH := 0;
  if not IsPsdThumbExt(APath) then
    Exit;
  if (APath = '') or not FileExists(APath) then
    Exit;
  if AMaxW < 8 then
    AMaxW := 256;
  if AMaxH < 8 then
    AMaxH := 256;
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    try
      if not ParseHeader(S, H) then
        Exit;
      ASrcW := H.Width;
      ASrcH := H.Height;
      if not ReadColorModeData(S, H.ColorMode, Palette) then
        Exit;
      if not ParseResources(S, Thumb) then
        Exit;
      if H.IsPsb then
        LayerLenBytes := 8
      else
        LayerLenBytes := 4;
      if not SkipSection(S, LayerLenBytes) then
        Exit;

      HaveThumb := ThumbToBgra(Thumb, ThumbPix, Tw, Th);
      HaveComp := False;
      if APreferFull or not HaveThumb then
        HaveComp := DecodeComposite(S, H, Palette, CompPix);

      if HaveComp then
      begin
        if FinishScaled(CompPix, H.Width, H.Height, AMaxW, AMaxH, OutPix, Dw, Dh) then
        begin
          APixels := OutPix;
          AWidth := Dw;
          AHeight := Dh;
          Exit(True);
        end;
      end;
      if HaveThumb then
      begin
        if FinishScaled(ThumbPix, Tw, Th, AMaxW, AMaxH, OutPix, Dw, Dh) then
        begin
          APixels := OutPix;
          AWidth := Dw;
          AHeight := Dh;
          Result := True;
        end;
      end;
    except
      Result := False;
      SetLength(APixels, 0);
      AWidth := 0;
      AHeight := 0;
    end;
  finally
    S.Free;
  end;
end;

function RenderPsdThumbRaw(const APath: string; AMaxW, AMaxH: Integer;
  out APixels: TBytes; out AWidth, AHeight: Integer): Boolean;
var
  SrcW, SrcH: Integer;
begin
  Result := RenderPsdRaw(APath, AMaxW, AMaxH, False, APixels, AWidth, AHeight,
    SrcW, SrcH);
end;

function LoadPsdPreview(const APath: string; AMaxW, AMaxH: Integer;
  ABitmap: FMX.Graphics.TBitmap; out ASrcW, ASrcH: Integer): Boolean;
var
  Pix: TBytes;
  W, H: Integer;
  Img: ISkImage;
  Tmp: TBitmap;
  Info: TSkImageInfo;
begin
  Result := False;
  ASrcW := 0;
  ASrcH := 0;
  if ABitmap = nil then
    Exit;
  if not RenderPsdRaw(APath, AMaxW, AMaxH, True, Pix, W, H, ASrcW, ASrcH) then
    Exit;
  if (W < 1) or (H < 1) or (Length(Pix) < Int64(W) * H * 4) then
    Exit;
  Info := BgraInfo(W, H);
  Img := TSkImage.MakeRasterCopy(Info, @Pix[0], NativeUInt(W) * 4);
  if Img = nil then
    Exit;
  Tmp := TBitmap.CreateFromSkImage(Img);
  try
    ABitmap.Assign(Tmp);
  finally
    Tmp.Free;
  end;
  Result := (ABitmap.Width > 0) and (ABitmap.Height > 0);
end;

end.
