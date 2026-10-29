unit uHdrPreview;

{
  Тонмап Radiance RGBE і OpenEXR у 8-бітний кадр.
  Без форм, теми і панелі. Файл закривається до повернення.
  У кеш плитки float не кладеться: назовні йде лише бітмап.
}

interface

uses
  System.SysUtils, FMX.Graphics;

type
  THdrError = (heNone, heBad, heNoRgb);

  THdrImage = record
    Width: Integer;
    Height: Integer;
    Rgb: TArray<Single>;
    procedure Clear;
  end;

function IsHdrExt(const AExt: string): Boolean;
function HdrKindName(const AExt: string): string;
function LoadHdrImage(const APath: string; out AImg: THdrImage): THdrError;
function ToneMapHdr(const ARgb: TArray<Single>; AW, AH: Integer;
  AExposure: Single; ABmp: TBitmap): Boolean;
function RenderHdrThumb(const APath: string; ASize: Integer): TBitmap;

implementation

uses
  System.Classes, System.Math, System.StrUtils, System.UITypes, System.ZLib,
  FMX.Types;

const
  HDR_MAX_FILE = 256 * 1024 * 1024;
  HDR_MAX_SIDE = 16384;
  HDR_MAX_PIXELS = 16 * 1024 * 1024;

procedure THdrImage.Clear;
begin
  Width := 0;
  Height := 0;
  SetLength(Rgb, 0);
end;

function IsHdrExt(const AExt: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(AExt);
  Result := (Ext = '.hdr') or (Ext = '.pic') or (Ext = '.exr');
end;

function HdrKindName(const AExt: string): string;
begin
  if LowerCase(AExt) = '.exr' then
    Result := 'EXR'
  else
    Result := 'HDR';
end;

function Need(const B: TBytes; AAt, ACount: Integer): Boolean;
begin
  Result := (AAt >= 0) and (ACount >= 0) and
    (Int64(AAt) + ACount <= Length(B));
end;

function ReadU16(const B: TBytes; AAt: Integer): Word;
begin
  Result := Word(B[AAt]) or (Word(B[AAt + 1]) shl 8);
end;

function ReadI32(const B: TBytes; AAt: Integer): Integer;
begin
  Result := Integer(Cardinal(B[AAt]) or (Cardinal(B[AAt + 1]) shl 8) or
    (Cardinal(B[AAt + 2]) shl 16) or (Cardinal(B[AAt + 3]) shl 24));
end;

function ReadU32(const B: TBytes; AAt: Integer): Cardinal;
begin
  Result := Cardinal(ReadI32(B, AAt));
end;

function ReadI64(const B: TBytes; AAt: Integer): Int64;
begin
  Result := Int64(ReadU32(B, AAt)) or (Int64(ReadU32(B, AAt + 4)) shl 32);
end;

function ReadF32(const B: TBytes; AAt: Integer): Single;
var
  U: Cardinal;
begin
  U := ReadU32(B, AAt);
  Move(U, Result, 4);
end;

function BitsToSingle(ABits: Cardinal): Single;
begin
  Move(ABits, Result, 4);
end;

function HalfToFloat(H: Word): Single;
var
  Sign, Exp, Mant: Integer;
  Bits: Cardinal;
begin
  Sign := H shr 15;
  Exp := (H shr 10) and $1F;
  Mant := H and $3FF;
  if Exp = 31 then
  begin
    if Mant = 0 then
      Bits := (Cardinal(Sign) shl 31) or $7F800000
    else
      Bits := (Cardinal(Sign) shl 31) or $7F800000 or (Cardinal(Mant) shl 13);
    Exit(BitsToSingle(Bits));
  end;
  if Exp = 0 then
  begin
    if Mant = 0 then
    begin
      Bits := Cardinal(Sign) shl 31;
      Exit(BitsToSingle(Bits));
    end;
    Result := (Mant / 1024.0) * Power(2, -14);
    if Sign <> 0 then
      Result := -Result;
    Exit;
  end;
  Bits := (Cardinal(Sign) shl 31) or (Cardinal(Exp + 112) shl 23) or
    (Cardinal(Mant) shl 13);
  Result := BitsToSingle(Bits);
end;

function ReadFileShare(const APath: string; out B: TBytes): Boolean;
var
  FS: TFileStream;
  N: Int64;
begin
  Result := False;
  SetLength(B, 0);
  if APath = '' then
    Exit;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    N := FS.Size;
    if (N <= 0) or (N > HDR_MAX_FILE) then
      Exit;
    SetLength(B, N);
    FS.ReadBuffer(B[0], N);
    Result := True;
  finally
    FS.Free;
  end;
end;

function PrepLinear(C, AScale: Single): Single;
begin
  if IsNan(C) or IsInfinite(C) then
    Exit(0);
  C := C * AScale;
  if IsNan(C) or IsInfinite(C) or (C <= 0) then
    Exit(0);
  Result := C;
end;

function ReinhardByte(C: Single): Byte;
var
  N: Integer;
begin
  if IsNan(C) or IsInfinite(C) or (C <= 0) then
    Exit(0);
  C := C / (1.0 + C);
  N := Round(C * 255.0);
  if N < 0 then
    N := 0
  else if N > 255 then
    N := 255;
  Result := Byte(N);
end;

function ExposureScale(AExposure: Single): Single;
begin
  Result := Power(2.0, EnsureRange(AExposure, -3, 3));
end;

procedure WritePixel(const Data: TBitmapData; X, Y: Integer; AR, AG, AB: Byte);
var
  Row: PByte;
  Pix: TAlphaColor;
begin
  if Data.PixelFormat = TPixelFormat.BGRA then
  begin
    Row := Data.GetScanline(Y);
    Row[X * 4] := AB;
    Row[X * 4 + 1] := AG;
    Row[X * 4 + 2] := AR;
    Row[X * 4 + 3] := 255;
  end
  else
  begin
    Pix := $FF000000 or (TAlphaColor(AR) shl 16) or (TAlphaColor(AG) shl 8) or AB;
    Data.SetPixel(X, Y, Pix);
  end;
end;

function ToneMapHdr(const ARgb: TArray<Single>; AW, AH: Integer;
  AExposure: Single; ABmp: TBitmap): Boolean;
var
  Data: TBitmapData;
  Scale: Single;
  X, Y, I: Integer;
  R, G, B: Single;
begin
  Result := False;
  if (ABmp = nil) or (AW < 1) or (AH < 1) then
    Exit;
  if Length(ARgb) < AW * AH * 3 then
    Exit;
  Scale := ExposureScale(AExposure);
  ABmp.SetSize(AW, AH);
  if not ABmp.Map(TMapAccess.Write, Data) then
    Exit;
  try
    for Y := 0 to AH - 1 do
      for X := 0 to AW - 1 do
      begin
        I := (Y * AW + X) * 3;
        R := PrepLinear(ARgb[I], Scale);
        G := PrepLinear(ARgb[I + 1], Scale);
        B := PrepLinear(ARgb[I + 2], Scale);
        WritePixel(Data, X, Y, ReinhardByte(R), ReinhardByte(G), ReinhardByte(B));
      end;
    Result := True;
  finally
    ABmp.Unmap(Data);
  end;
end;

function ToneMapBox(const ARgb: TArray<Single>; AW, AH, ADW, ADH: Integer;
  AExposure: Single; ABmp: TBitmap): Boolean;
var
  Data: TBitmapData;
  Scale, R, G, B, C: Single;
  X, Y, SX0, SX1, SY0, SY1, IX, IY, N, I: Integer;
begin
  Result := False;
  if (ABmp = nil) or (ADW < 1) or (ADH < 1) then
    Exit;
  if Length(ARgb) < AW * AH * 3 then
    Exit;
  Scale := ExposureScale(AExposure);
  ABmp.SetSize(ADW, ADH);
  if not ABmp.Map(TMapAccess.Write, Data) then
    Exit;
  try
    for Y := 0 to ADH - 1 do
    begin
      SY0 := Integer((Int64(Y) * AH) div ADH);
      SY1 := Integer((Int64(Y + 1) * AH) div ADH);
      if SY1 <= SY0 then
        SY1 := SY0 + 1;
      if SY1 > AH then
        SY1 := AH;
      for X := 0 to ADW - 1 do
      begin
        SX0 := Integer((Int64(X) * AW) div ADW);
        SX1 := Integer((Int64(X + 1) * AW) div ADW);
        if SX1 <= SX0 then
          SX1 := SX0 + 1;
        if SX1 > AW then
          SX1 := AW;
        R := 0;
        G := 0;
        B := 0;
        N := 0;
        for IY := SY0 to SY1 - 1 do
          for IX := SX0 to SX1 - 1 do
          begin
            I := (IY * AW + IX) * 3;
            C := ARgb[I];
            if not IsNan(C) and not IsInfinite(C) and (C > 0) then
              R := R + C;
            C := ARgb[I + 1];
            if not IsNan(C) and not IsInfinite(C) and (C > 0) then
              G := G + C;
            C := ARgb[I + 2];
            if not IsNan(C) and not IsInfinite(C) and (C > 0) then
              B := B + C;
            Inc(N);
          end;
        if N > 0 then
        begin
          R := PrepLinear(R / N, Scale);
          G := PrepLinear(G / N, Scale);
          B := PrepLinear(B / N, Scale);
        end;
        WritePixel(Data, X, Y, ReinhardByte(R), ReinhardByte(G), ReinhardByte(B));
      end;
    end;
    Result := True;
  finally
    ABmp.Unmap(Data);
  end;
end;

function ReadLine(const B: TBytes; var P: Integer; out S: string): Boolean;
var
  Start: Integer;
begin
  Result := False;
  S := '';
  if (P < 0) or (P >= Length(B)) then
    Exit;
  Start := P;
  while (P < Length(B)) and (B[P] <> 10) and (B[P] <> 13) do
    Inc(P);
  S := TEncoding.ASCII.GetString(B, Start, P - Start);
  if (P < Length(B)) and (B[P] = 13) then
    Inc(P);
  if (P < Length(B)) and (B[P] = 10) then
    Inc(P);
  Result := True;
end;

function NextAxis(const S: string; var I: Integer; out AAxis: Char;
  out ASign, ANum: Integer): Boolean;
var
  Start: Integer;
begin
  Result := False;
  while (I <= Length(S)) and (S[I] <= ' ') do
    Inc(I);
  if I > Length(S) then
    Exit;
  if S[I] = '-' then
    ASign := -1
  else if S[I] = '+' then
    ASign := 1
  else
    Exit;
  Inc(I);
  if I > Length(S) then
    Exit;
  AAxis := UpCase(S[I]);
  if (AAxis <> 'X') and (AAxis <> 'Y') then
    Exit;
  Inc(I);
  while (I <= Length(S)) and (S[I] <= ' ') do
    Inc(I);
  Start := I;
  while (I <= Length(S)) and (S[I] >= '0') and (S[I] <= '9') do
    Inc(I);
  if I = Start then
    Exit;
  ANum := StrToIntDef(Copy(S, Start, I - Start), -1);
  Result := ANum > 0;
end;

function ParseResLine(const S: string; out AW, AH, AXSign, AYSign: Integer): Boolean;
var
  T: string;
  I, N1, N2, S1, S2: Integer;
  A1, A2: Char;
begin
  Result := False;
  T := Trim(S);
  I := 1;
  if not NextAxis(T, I, A1, S1, N1) then
    Exit;
  if not NextAxis(T, I, A2, S2, N2) then
    Exit;
  if Trim(Copy(T, I, MaxInt)) <> '' then
    Exit;
  if A1 = A2 then
    Exit;
  if A1 = 'X' then
  begin
    AW := N1;
    AXSign := S1;
    AH := N2;
    AYSign := S2;
  end
  else
  begin
    AH := N1;
    AYSign := S1;
    AW := N2;
    AXSign := S2;
  end;
  Result := (AW > 0) and (AH > 0);
end;

procedure RgbeToRgb(AR, AG, AB, AE: Byte; AScale: Single;
  out FR, FG, FB: Single);
var
  F: Single;
begin
  if AE = 0 then
  begin
    FR := 0;
    FG := 0;
    FB := 0;
    Exit;
  end;
  F := Ldexp(1.0, Integer(AE) - 128 - 8) * AScale;
  FR := AR * F;
  FG := AG * F;
  FB := AB * F;
end;

function ReadRleChan(const B: TBytes; var P: Integer; AW: Integer;
  var Dest: TBytes; ADestAt: Integer): Boolean;
var
  Written, Count, I: Integer;
  Code: Byte;
begin
  Result := False;
  Written := 0;
  while Written < AW do
  begin
    if not Need(B, P, 1) then
      Exit;
    Code := B[P];
    Inc(P);
    if Code > 128 then
    begin
      Count := Code - 128;
      if (Count < 1) or (Written + Count > AW) or not Need(B, P, 1) then
        Exit;
      for I := 0 to Count - 1 do
        Dest[ADestAt + Written + I] := B[P];
      Inc(P);
      Inc(Written, Count);
    end
    else
    begin
      Count := Code;
      if (Count < 1) or (Written + Count > AW) or not Need(B, P, Count) then
        Exit;
      Move(B[P], Dest[ADestAt + Written], Count);
      Inc(P, Count);
      Inc(Written, Count);
    end;
  end;
  Result := True;
end;

function DecodeRgbePixels(const B: TBytes; P, AW, AH, AXSign, AYSign: Integer;
  AScale: Single; var ARgb: TArray<Single>): Boolean;
var
  Row, Col, C: Integer;
  Flat: Boolean;
  Scan: TBytes;
  RR, GG, BB, EE: Byte;
  FR, FG, FB: Single;

  procedure Store(ARow, ACol: Integer; AFr, AFg, AFb: Single);
  var
    X, Y, I: Integer;
  begin
    if AXSign < 0 then
      X := AW - 1 - ACol
    else
      X := ACol;
    if AYSign > 0 then
      Y := AH - 1 - ARow
    else
      Y := ARow;
    I := (Y * AW + X) * 3;
    ARgb[I] := AFr;
    ARgb[I + 1] := AFg;
    ARgb[I + 2] := AFb;
  end;

begin
  Result := False;
  Flat := (AW < 8) or (AW > 32767);
  SetLength(Scan, AW * 4);
  for Row := 0 to AH - 1 do
  begin
    if not Flat and Need(B, P, 4) and (B[P] = 2) and (B[P + 1] = 2) and
       ((B[P + 2] and $80) = 0) and
       (((Integer(B[P + 2]) shl 8) or B[P + 3]) = AW) then
    begin
      Inc(P, 4);
      for C := 0 to 3 do
        if not ReadRleChan(B, P, AW, Scan, C * AW) then
          Exit;
      for Col := 0 to AW - 1 do
      begin
        RgbeToRgb(Scan[Col], Scan[AW + Col], Scan[2 * AW + Col],
          Scan[3 * AW + Col], AScale, FR, FG, FB);
        Store(Row, Col, FR, FG, FB);
      end;
    end
    else
    begin
      Flat := True;
      for Col := 0 to AW - 1 do
      begin
        if not Need(B, P, 4) then
          Exit;
        RR := B[P];
        GG := B[P + 1];
        BB := B[P + 2];
        EE := B[P + 3];
        Inc(P, 4);
        RgbeToRgb(RR, GG, BB, EE, AScale, FR, FG, FB);
        Store(Row, Col, FR, FG, FB);
      end;
    end;
  end;
  Result := True;
end;

function DecodeHdr(const B: TBytes; out AImg: THdrImage): THdrError;
var
  P, Lines, W, H, XSign, YSign: Integer;
  Line: string;
  Scale: Single;
  SawRes, FormatOk: Boolean;
  V: Single;
begin
  Result := heBad;
  AImg.Clear;
  if Length(B) < 16 then
    Exit;
  P := 0;
  Lines := 0;
  Scale := 1;
  SawRes := False;
  FormatOk := True;
  W := 0;
  H := 0;
  XSign := 1;
  YSign := -1;
  while (Lines < 256) and ReadLine(B, P, Line) do
  begin
    Inc(Lines);
    if ParseResLine(Line, W, H, XSign, YSign) then
    begin
      SawRes := True;
      Break;
    end;
    if StartsText('FORMAT=', Trim(Line)) then
      FormatOk := Pos('rgbe', LowerCase(Line)) > 0;
    if StartsText('EXPOSURE=', Trim(Line)) then
    begin
      V := StrToFloatDef(Trim(Copy(Trim(Line), 10, MaxInt)), 1,
        TFormatSettings.Invariant);
      if (V > 0) and not IsNan(V) and not IsInfinite(V) then
        Scale := Scale * V;
    end;
  end;
  if not SawRes or not FormatOk then
    Exit;
  if (W > HDR_MAX_SIDE) or (H > HDR_MAX_SIDE) or
     (Int64(W) * H > HDR_MAX_PIXELS) then
    Exit;
  AImg.Width := W;
  AImg.Height := H;
  SetLength(AImg.Rgb, W * H * 3);
  if not DecodeRgbePixels(B, P, W, H, XSign, YSign, Scale, AImg.Rgb) then
  begin
    AImg.Clear;
    Exit;
  end;
  Result := heNone;
end;

type
  TExrChan = record
    Name: string;
    Layer: string;
    Key: string;
    Pix: Integer;
    XS: Integer;
    YS: Integer;
  end;

  TExrPart = record
    Name: string;
    Kind: string;
    Comp: Integer;
    LineOrder: Integer;
    MinX, MinY, MaxX, MaxY: Integer;
    Chans: TArray<TExrChan>;
    ChunkN: Integer;
    HasChunk: Boolean;
    Tiled: Boolean;
    Deep: Boolean;
    HasWindow: Boolean;
    HasComp: Boolean;
    IR, IG, IB: Integer;
    HasRgb: Boolean;
    Decodable: Boolean;
  end;

function ReadCStr(const B: TBytes; var P: Integer; AMax: Integer): string;
var
  Start, N: Integer;
begin
  Result := '';
  if not Need(B, P, 1) then
    Exit;
  Start := P;
  N := 0;
  while Need(B, P, 1) and (B[P] <> 0) and (N < AMax) do
  begin
    Inc(P);
    Inc(N);
  end;
  if not Need(B, P, 1) or (B[P] <> 0) then
  begin
    P := -1;
    Exit;
  end;
  if N > 0 then
    Result := TEncoding.ASCII.GetString(B, Start, N);
  Inc(P);
end;

function SkipLayerName(const AName: string): Boolean;
var
  S: string;
begin
  S := LowerCase(AName);
  Result := (Pos('cryptomatte', S) > 0) or (Pos('depth', S) > 0) or
    (Pos('motion', S) > 0);
end;

function LayerOf(const AName: string): string;
var
  D: Integer;
begin
  D := LastDelimiter('.', AName);
  if D <= 1 then
    Result := ''
  else
    Result := Copy(AName, 1, D - 1);
end;

function KeyOf(const AName: string): string;
var
  D: Integer;
begin
  D := LastDelimiter('.', AName);
  if D = 0 then
    Result := AName
  else
    Result := Copy(AName, D + 1, MaxInt);
end;

function DivP(A, S: Integer): Integer;
begin
  if S <= 0 then
    Exit(0);
  if A >= 0 then
    Result := A div S
  else
    Result := -(((-A) + S - 1) div S);
end;

function ModP(A, S: Integer): Integer;
begin
  if S <= 0 then
    Exit(0);
  Result := A - S * DivP(A, S);
end;

function PixBytes(APix: Integer): Integer;
begin
  if APix = 1 then
    Result := 2
  else if (APix = 0) or (APix = 2) then
    Result := 4
  else
    Result := 0;
end;

function LinesPerBlock(AComp: Integer): Integer;
begin
  if AComp = 3 then
    Result := 16
  else if AComp = 4 then
    Result := 32
  else
    Result := 1;
end;

function CompKnown(AComp: Integer): Boolean;
begin
  Result := (AComp >= 0) and (AComp <= 4);
end;

function OnScan(Y, YS, AMinY: Integer): Boolean;
begin
  if YS = 1 then
    Result := True
  else
    Result := ModP(Y, YS) = ModP(AMinY, YS);
end;

function SampleCount(AXS, AMinX, AMaxX: Integer): Integer;
begin
  if AXS <= 0 then
    Exit(0);
  Result := DivP(AMaxX, AXS) - DivP(AMinX, AXS) + 1;
  if Result < 0 then
    Result := 0;
end;

function PickRgb(const AChans: TArray<TExrChan>; out AIR, AIG, AIB: Integer): Boolean;
var
  I, J: Integer;
  Layers: TArray<string>;
  Seen: Boolean;
  Layer, Key: string;
begin
  Result := False;
  AIR := -1;
  AIG := -1;
  AIB := -1;
  SetLength(Layers, 0);
  for I := 0 to High(AChans) do
  begin
    Layer := AChans[I].Layer;
    if SkipLayerName(Layer) then
      Continue;
    Seen := False;
    for J := 0 to High(Layers) do
      if Layers[J] = Layer then
        Seen := True;
    if not Seen then
    begin
      SetLength(Layers, Length(Layers) + 1);
      Layers[High(Layers)] := Layer;
    end;
  end;
  for J := 0 to High(Layers) do
  begin
    AIR := -1;
    AIG := -1;
    AIB := -1;
    for I := 0 to High(AChans) do
    begin
      if AChans[I].Layer <> Layers[J] then
        Continue;
      if SkipLayerName(AChans[I].Layer) then
        Continue;
      Key := AChans[I].Key;
      if (Key = 'R') or (Key = 'r') then
        AIR := I
      else if (Key = 'G') or (Key = 'g') then
        AIG := I
      else if (Key = 'B') or (Key = 'b') then
        AIB := I;
    end;
    if (AIR >= 0) and (AIG >= 0) and (AIB >= 0) and
       (AChans[AIR].XS = 1) and (AChans[AIR].YS = 1) and
       (AChans[AIG].XS = 1) and (AChans[AIG].YS = 1) and
       (AChans[AIB].XS = 1) and (AChans[AIB].YS = 1) and
       (PixBytes(AChans[AIR].Pix) > 0) and
       (PixBytes(AChans[AIG].Pix) > 0) and
       (PixBytes(AChans[AIB].Pix) > 0) then
      Exit(True);
  end;
end;

function ParseChlist(const V: TBytes; out AChans: TArray<TExrChan>): Boolean;
var
  P, N: Integer;
  Ch: TExrChan;
begin
  Result := False;
  SetLength(AChans, 0);
  P := 0;
  N := 0;
  while P < Length(V) do
  begin
    if V[P] = 0 then
    begin
      Result := True;
      Exit;
    end;
    Ch.Name := ReadCStr(V, P, 255);
    if P < 0 then
      Exit;
    if not Need(V, P, 16) then
      Exit;
    Ch.Pix := ReadI32(V, P);
    Inc(P, 4);
    Inc(P, 4);
    Ch.XS := ReadI32(V, P);
    Inc(P, 4);
    Ch.YS := ReadI32(V, P);
    Inc(P, 4);
    Ch.Layer := LayerOf(Ch.Name);
    Ch.Key := KeyOf(Ch.Name);
    if N > 256 then
      Exit;
    SetLength(AChans, N + 1);
    AChans[N] := Ch;
    Inc(N);
  end;
end;

function BytesOfAttr(const V: TBytes): string;
begin
  if Length(V) = 0 then
    Result := ''
  else
    Result := TEncoding.ASCII.GetString(V, 0, Length(V));
end;

function ParseHeader(const B: TBytes; var P: Integer; ALong: Boolean;
  out APart: TExrPart): Boolean;
var
  Name, Typ: string;
  Size, MaxName: Integer;
  Value: TBytes;
begin
  Result := False;
  APart := Default(TExrPart);
  APart.Comp := -1;
  APart.ChunkN := -1;
  APart.IR := -1;
  APart.IG := -1;
  APart.IB := -1;
  if ALong then
    MaxName := 255
  else
    MaxName := 31;
  if (P < 0) or (P >= Length(B)) then
    Exit;
  while True do
  begin
    Name := ReadCStr(B, P, MaxName);
    if P < 0 then
      Exit;
    if Name = '' then
    begin
      Result := True;
      Exit;
    end;
    Typ := ReadCStr(B, P, MaxName);
    if (P < 0) or (Typ = '') or not Need(B, P, 4) then
      Exit;
    Size := ReadI32(B, P);
    Inc(P, 4);
    if (Size < 0) or not Need(B, P, Size) then
      Exit;
    SetLength(Value, Size);
    if Size > 0 then
      Move(B[P], Value[0], Size);
    Inc(P, Size);
    if Name = 'channels' then
    begin
      if not ParseChlist(Value, APart.Chans) then
        Exit;
    end
    else if Name = 'compression' then
    begin
      if Size < 1 then
        Exit;
      APart.Comp := Value[0];
      APart.HasComp := True;
    end
    else if Name = 'dataWindow' then
    begin
      if Size < 16 then
        Exit;
      APart.MinX := ReadI32(Value, 0);
      APart.MinY := ReadI32(Value, 4);
      APart.MaxX := ReadI32(Value, 8);
      APart.MaxY := ReadI32(Value, 12);
      APart.HasWindow := True;
    end
    else if Name = 'lineOrder' then
    begin
      if Size < 1 then
        Exit;
      APart.LineOrder := Value[0];
    end
    else if Name = 'chunkCount' then
    begin
      if Size < 4 then
        Exit;
      APart.ChunkN := ReadI32(Value, 0);
      APart.HasChunk := True;
    end
    else if Name = 'name' then
      APart.Name := BytesOfAttr(Value)
    else if Name = 'type' then
      APart.Kind := BytesOfAttr(Value)
    else if Name = 'tiles' then
      APart.Tiled := True;
  end;
end;

procedure FinishPart(var APart: TExrPart; ASingleTiled: Boolean);
var
  W, H: Int64;
begin
  if ASingleTiled then
    APart.Tiled := True;
  if StartsText('deep', LowerCase(APart.Kind)) then
    APart.Deep := True;
  if SameText(APart.Kind, 'tiledimage') then
    APart.Tiled := True;
  APart.HasRgb := PickRgb(APart.Chans, APart.IR, APart.IG, APart.IB);
  APart.Decodable := False;
  if not APart.HasRgb or APart.Tiled or APart.Deep or not APart.HasWindow or
     not APart.HasComp or not CompKnown(APart.Comp) then
    Exit;
  if SkipLayerName(APart.Name) then
  begin
    APart.HasRgb := False;
    Exit;
  end;
  if (APart.MaxX < APart.MinX) or (APart.MaxY < APart.MinY) then
    Exit;
  W := Int64(APart.MaxX) - APart.MinX + 1;
  H := Int64(APart.MaxY) - APart.MinY + 1;
  if (W < 1) or (H < 1) or (W > HDR_MAX_SIDE) or (H > HDR_MAX_SIDE) or
     (W * H > HDR_MAX_PIXELS) then
    Exit;
  APart.Decodable := True;
end;

function PartChunkCount(const APart: TExrPart): Integer;
var
  H, Lines: Integer;
begin
  if APart.HasChunk then
  begin
    Result := APart.ChunkN;
    Exit;
  end;
  if APart.Tiled or APart.Deep or not APart.HasWindow or not CompKnown(APart.Comp) then
    Exit(-1);
  if (APart.MaxY < APart.MinY) then
    Exit(-1);
  H := APart.MaxY - APart.MinY + 1;
  Lines := LinesPerBlock(APart.Comp);
  Result := (H + Lines - 1) div Lines;
end;

function ScanBytes(const APart: TExrPart; Y: Integer): Integer;
var
  I, N, Bp, Add: Integer;
begin
  Result := 0;
  for I := 0 to High(APart.Chans) do
  begin
    if not OnScan(Y, APart.Chans[I].YS, APart.MinY) then
      Continue;
    N := SampleCount(APart.Chans[I].XS, APart.MinX, APart.MaxX);
    Bp := PixBytes(APart.Chans[I].Pix);
    if (N < 0) or (Bp <= 0) then
      Exit(-1);
    Add := N * Bp;
    if (Add < 0) or (Result > MaxInt - Add) then
      Exit(-1);
    Inc(Result, Add);
  end;
end;

function SampleFloat(const B: TBytes; AAt, APix: Integer): Single;
begin
  if APix = 1 then
    Result := HalfToFloat(ReadU16(B, AAt))
  else if APix = 2 then
    Result := ReadF32(B, AAt)
  else
    Result := ReadU32(B, AAt);
end;

procedure ExrPredict(var Buf: TBytes);
var
  I, D: Integer;
begin
  for I := 1 to High(Buf) do
  begin
    D := Integer(Buf[I - 1]) + Integer(Buf[I]) - 128;
    Buf[I] := Byte(D and $FF);
  end;
end;

procedure ExrInterleave(const Src: TBytes; out Dst: TBytes);
var
  N, Half, I, A, C: Integer;
begin
  N := Length(Src);
  SetLength(Dst, N);
  Half := (N + 1) div 2;
  A := 0;
  C := Half;
  I := 0;
  while I < N do
  begin
    if A < Half then
    begin
      Dst[I] := Src[A];
      Inc(A);
      Inc(I);
    end;
    if (I < N) and (C < N) then
    begin
      Dst[I] := Src[C];
      Inc(C);
      Inc(I);
    end;
  end;
end;

function InflateExact(const B: TBytes; AAt, APacked, AExpect: Integer;
  out ARaw: TBytes): Boolean;
var
  Src: TBytes;
begin
  Result := False;
  SetLength(ARaw, 0);
  if (APacked < 0) or (AExpect < 1) or not Need(B, AAt, APacked) then
    Exit;
  SetLength(Src, APacked);
  if APacked > 0 then
    Move(B[AAt], Src[0], APacked);
  try
    ZDecompress(Src, ARaw);
  except
    SetLength(ARaw, 0);
    Exit;
  end;
  Result := Length(ARaw) = AExpect;
  if not Result then
    SetLength(ARaw, 0);
end;

function Unpredict(AComp: Integer; const B: TBytes; AAt, APacked, AExpect: Integer;
  out ARaw: TBytes): Boolean;
var
  Tmp, Got: TBytes;
  O, Count, I, Code: Integer;
begin
  Result := False;
  SetLength(ARaw, 0);
  if (APacked = AExpect) and Need(B, AAt, APacked) then
  begin
    SetLength(ARaw, AExpect);
    if AExpect > 0 then
      Move(B[AAt], ARaw[0], AExpect);
    Exit(True);
  end;
  if AComp = 1 then
  begin
    if not Need(B, AAt, APacked) then
      Exit;
    SetLength(Tmp, AExpect);
    I := AAt;
    O := 0;
    while (I < AAt + APacked) and (O < AExpect) do
    begin
      Code := B[I];
      Inc(I);
      if Code >= 128 then
      begin
        Count := 256 - Code;
        if (Count < 1) or (I + Count > AAt + APacked) or (O + Count > AExpect) then
          Exit;
        Move(B[I], Tmp[O], Count);
        Inc(I, Count);
        Inc(O, Count);
      end
      else
      begin
        Count := Code + 1;
        if (I >= AAt + APacked) or (O + Count > AExpect) then
          Exit;
        FillChar(Tmp[O], Count, B[I]);
        Inc(I);
        Inc(O, Count);
      end;
    end;
    if O <> AExpect then
      Exit;
    Got := Tmp;
  end
  else if not InflateExact(B, AAt, APacked, AExpect, Got) then
    Exit;
  ExrPredict(Got);
  ExrInterleave(Got, ARaw);
  Result := Length(ARaw) = AExpect;
end;

function S16(V: Word): Integer;
begin
  if V >= 32768 then
    Result := Integer(V) - 65536
  else
    Result := Integer(V);
end;

function Sar1(V: Integer): Integer;
begin
  Result := Integer((Cardinal(V) shr 1) or (Cardinal(V) and $80000000));
end;

procedure Wdec14(L, H: Word; out A, B: Word);
var
  HI, AI, ASV, BSV: Integer;
begin
  HI := S16(H);
  AI := S16(L) + (HI and 1) + Sar1(HI);
  ASV := AI and $FFFF;
  if ASV >= 32768 then
    ASV := ASV - 65536;
  BSV := ASV - HI;
  A := Word(ASV and $FFFF);
  B := Word(BSV and $FFFF);
end;

procedure Wdec16(L, H: Word; out A, B: Word);
var
  M, D, BB, AA: Integer;
begin
  M := L;
  D := H;
  BB := (M - (D shr 1)) and 65535;
  AA := (D + BB - 32768) and 65535;
  B := Word(BB);
  A := Word(AA);
end;

function Wav2Decode(var Buf: TArray<Word>; Base, NX, OX, NY, OY: Integer;
  MX: Word): Boolean;
var
  W14: Boolean;
  N, P, P2, OY1, OY2, OX1, OX2: Integer;
  PY, EY, PX, EX, P01, P10, P11, Last: Integer;
  I00, I01, I10, I11: Word;

  function Ok(A: Integer): Boolean;
  begin
    Result := (A >= 0) and (A <= Last);
  end;

begin
  Result := False;
  Last := High(Buf);
  if (NX < 1) or (NY < 1) or (OX < 1) or (OY < 1) or (Base < 0) then
    Exit;
  W14 := MX < (1 shl 14);
  if NX < NY then
    N := NX
  else
    N := NY;
  P := 1;
  while P <= N do
    P := P shl 1;
  P := P shr 1;
  P2 := P;
  P := P shr 1;
  while P >= 1 do
  begin
    PY := Base;
    EY := Base + OY * (NY - P2);
    OY1 := OY * P;
    OY2 := OY * P2;
    OX1 := OX * P;
    OX2 := OX * P2;
    while PY <= EY do
    begin
      PX := PY;
      EX := PY + OX * (NX - P2);
      while PX <= EX do
      begin
        P01 := PX + OX1;
        P10 := PX + OY1;
        P11 := P10 + OX1;
        if not (Ok(PX) and Ok(P01) and Ok(P10) and Ok(P11)) then
          Exit;
        if W14 then
        begin
          Wdec14(Buf[PX], Buf[P10], I00, I10);
          Wdec14(Buf[P01], Buf[P11], I01, I11);
          Wdec14(I00, I01, Buf[PX], Buf[P01]);
          Wdec14(I10, I11, Buf[P10], Buf[P11]);
        end
        else
        begin
          Wdec16(Buf[PX], Buf[P10], I00, I10);
          Wdec16(Buf[P01], Buf[P11], I01, I11);
          Wdec16(I00, I01, Buf[PX], Buf[P01]);
          Wdec16(I10, I11, Buf[P10], Buf[P11]);
        end;
        PX := PX + OX2;
      end;
      if (NX and P) <> 0 then
      begin
        P10 := PX + OY1;
        if not (Ok(PX) and Ok(P10)) then
          Exit;
        if W14 then
          Wdec14(Buf[PX], Buf[P10], I00, Buf[P10])
        else
          Wdec16(Buf[PX], Buf[P10], I00, Buf[P10]);
        Buf[PX] := I00;
      end;
      PY := PY + OY2;
    end;
    if (NY and P) <> 0 then
    begin
      PX := PY;
      EX := PY + OX * (NX - P2);
      while PX <= EX do
      begin
        P01 := PX + OX1;
        if not (Ok(PX) and Ok(P01)) then
          Exit;
        if W14 then
          Wdec14(Buf[PX], Buf[P01], I00, Buf[P01])
        else
          Wdec16(Buf[PX], Buf[P01], I00, Buf[P01]);
        Buf[PX] := I00;
        PX := PX + OX2;
      end;
    end;
    P2 := P;
    P := P shr 1;
  end;
  Result := True;
end;

function HufUncompress(const B: TBytes; AAt, ACount, ARawN: Integer;
  var Raw: TArray<Word>): Boolean;
const
  HUF_ENCSIZE = (1 shl 16) + 1;
  HUF_DECBITS = 14;
  HUF_DECSIZE = 1 shl HUF_DECBITS;
  HUF_DECMASK = HUF_DECSIZE - 1;
  SHORT_ZERO = 59;
  LONG_ZERO = 63;
  SHORTEST_LONG = 6;
var
  SymLo, SymHi, NBits, P, EndP, LC, O, I, J, L, Slot, N, Sym, Cs, Prev: Integer;
  C, Code, Mask: UInt64;
  HCode: TArray<UInt64>;
  Len: TBytes;
  Lit: TArray<Integer>;
  Longs: TArray<TArray<Integer>>;
  Ie: Integer;

  function Bits(AN: Integer): Integer;
  begin
    Result := -1;
    while LC < AN do
    begin
      if P >= EndP then
        Exit;
      C := (C shl 8) or B[P];
      Inc(P);
      Inc(LC, 8);
    end;
    Dec(LC, AN);
    Result := Integer((C shr LC) and ((UInt64(1) shl AN) - 1));
  end;

  function LengthOf(ACode: UInt64): Integer;
  begin
    Result := Integer(ACode and 63);
  end;

  function CodeOf(ACode: UInt64): UInt64;
  begin
    Result := ACode shr 6;
  end;

  function Emit(ASym: Integer): Boolean;
  begin
    Result := False;
    if ASym = SymHi then
    begin
      if LC < 8 then
      begin
        if P >= Ie then
          Exit;
        C := (C shl 8) or B[P];
        Inc(P);
        Inc(LC, 8);
      end;
      Dec(LC, 8);
      if LC < 0 then
        Exit;
      Cs := Integer((C shr LC) and $FF);
      if (O < 1) or (O > ARawN - Cs) then
        Exit;
      Prev := Raw[O - 1];
      while Cs > 0 do
      begin
        Raw[O] := Word(Prev);
        Inc(O);
        Dec(Cs);
      end;
    end
    else
    begin
      if (O >= ARawN) or (ASym < 0) or (ASym > 65535) then
        Exit;
      Raw[O] := Word(ASym);
      Inc(O);
    end;
    Result := True;
  end;

  function Take(ALen, ASym: Integer): Boolean;
  begin
    Result := False;
    Dec(LC, ALen);
    if LC < 0 then
      Exit;
    Result := Emit(ASym);
  end;

begin
  Result := False;
  if ARawN < 0 then
    Exit;
  SetLength(Raw, ARawN);
  if ARawN = 0 then
    Exit(ACount = 0);
  if ACount < 20 then
    Exit;
  if not Need(B, AAt, ACount) then
    Exit;
  SymLo := ReadI32(B, AAt);
  SymHi := ReadI32(B, AAt + 4);
  NBits := ReadI32(B, AAt + 12);
  if (SymLo < 0) or (SymLo >= HUF_ENCSIZE) or (SymHi < 0) or (SymHi >= HUF_ENCSIZE) or
     (NBits < 0) then
    Exit;
  P := AAt + 20;
  EndP := AAt + ACount;
  if (Int64(NBits) + 7) div 8 > EndP - (AAt + 20) then
    Exit;
  SetLength(HCode, HUF_ENCSIZE);
  C := 0;
  LC := 0;
  I := SymLo;
  while I <= SymHi do
  begin
    L := Bits(6);
    if L < 0 then
      Exit;
    if L = LONG_ZERO then
    begin
      N := Bits(8);
      if N < 0 then
        Exit;
      N := N + SHORTEST_LONG;
      if I + N > SymHi + 1 then
        Exit;
      while N > 0 do
      begin
        HCode[I] := 0;
        Inc(I);
        Dec(N);
      end;
      Dec(I);
    end
    else if L >= SHORT_ZERO then
    begin
      N := L - SHORT_ZERO + 2;
      if I + N > SymHi + 1 then
        Exit;
      while N > 0 do
      begin
        HCode[I] := 0;
        Inc(I);
        Dec(N);
      end;
      Dec(I);
    end
    else
      HCode[I] := UInt64(L);
    Inc(I);
  end;
  begin
    var NLen: array[0..58] of UInt64;
    var CC, NC: UInt64;
    var LL: Integer;
    for LL := 0 to 58 do
      NLen[LL] := 0;
    for I := 0 to HUF_ENCSIZE - 1 do
    begin
      LL := Integer(HCode[I]);
      if (LL < 0) or (LL > 58) then
        Exit;
      Inc(NLen[LL]);
    end;
    CC := 0;
    for LL := 58 downto 1 do
    begin
      NC := (CC + NLen[LL]) shr 1;
      NLen[LL] := CC;
      CC := NC;
    end;
    for I := 0 to HUF_ENCSIZE - 1 do
    begin
      LL := Integer(HCode[I]);
      if LL > 0 then
      begin
        HCode[I] := UInt64(LL) or (NLen[LL] shl 6);
        Inc(NLen[LL]);
      end;
    end;
  end;
  if NBits > (EndP - P) * 8 then
    Exit;
  SetLength(Len, HUF_DECSIZE);
  SetLength(Lit, HUF_DECSIZE);
  SetLength(Longs, HUF_DECSIZE);
  for I := SymLo to SymHi do
  begin
    Code := CodeOf(HCode[I]);
    L := LengthOf(HCode[I]);
    if L = 0 then
      Continue;
    if (L > 58) or ((Code shr L) <> 0) then
      Exit;
    if L > HUF_DECBITS then
    begin
      Slot := Integer(Code shr (L - HUF_DECBITS));
      if (Slot < 0) or (Slot >= HUF_DECSIZE) or (Len[Slot] <> 0) then
        Exit;
      N := Length(Longs[Slot]);
      SetLength(Longs[Slot], N + 1);
      Longs[Slot][N] := I;
    end
    else
    begin
      Slot := Integer(Code shl (HUF_DECBITS - L));
      N := 1 shl (HUF_DECBITS - L);
      if (Slot < 0) or (Slot + N > HUF_DECSIZE) then
        Exit;
      for J := 0 to N - 1 do
      begin
        if (Len[Slot + J] <> 0) or (Length(Longs[Slot + J]) > 0) then
          Exit;
        Len[Slot + J] := Byte(L);
        Lit[Slot + J] := I;
      end;
    end;
  end;
  Ie := P + (NBits + 7) div 8;
  if Ie > EndP then
    Ie := EndP;
  C := 0;
  LC := 0;
  O := 0;
  while P < Ie do
  begin
    C := (C shl 8) or B[P];
    Inc(P);
    Inc(LC, 8);
    while LC >= HUF_DECBITS do
    begin
      Slot := Integer((C shr (LC - HUF_DECBITS)) and HUF_DECMASK);
      if Len[Slot] <> 0 then
      begin
        if not Take(Len[Slot], Lit[Slot]) then
          Exit;
      end
      else
      begin
        N := Length(Longs[Slot]);
        if N = 0 then
          Exit;
        J := 0;
        while J < N do
        begin
          Sym := Longs[Slot][J];
          L := LengthOf(HCode[Sym]);
          while (LC < L) and (P < Ie) do
          begin
            C := (C shl 8) or B[P];
            Inc(P);
            Inc(LC, 8);
          end;
          if LC >= L then
          begin
            Mask := (UInt64(1) shl L) - 1;
            if CodeOf(HCode[Sym]) = ((C shr (LC - L)) and Mask) then
            begin
              if not Take(L, Sym) then
                Exit;
              Break;
            end;
          end;
          Inc(J);
        end;
        if J = N then
          Exit;
      end;
    end;
  end;
  I := (8 - NBits) and 7;
  C := C shr I;
  Dec(LC, I);
  while LC > 0 do
  begin
    Slot := Integer((C shl (HUF_DECBITS - LC)) and HUF_DECMASK);
    if Len[Slot] = 0 then
      Exit;
    if not Take(Len[Slot], Lit[Slot]) then
      Exit;
  end;
  Result := O = ARawN;
end;

function PizUncompress(const B: TBytes; AAt, APacked: Integer;
  const APart: TExrPart; AY0, ALines: Integer; out ARaw: TBytes): Boolean;
const
  BITMAP_N = 8192;
var
  MinNZ, MaxNZ, P, Expect, O, I, J, Y, NX, NY, Sz, Add, Total, NWrite: Integer;
  MaxV: Word;
  Bitmap: TBytes;
  Lut: TArray<Word>;
  Samples: TArray<Word>;
  Start, XS, YS, CSize, Cur: TArray<Integer>;
  K: Integer;
begin
  Result := False;
  SetLength(ARaw, 0);
  if (APacked < 4) or (ALines < 1) or not Need(B, AAt, APacked) then
    Exit;
  if (AY0 < APart.MinY) or (AY0 > APart.MaxY) then
    Exit;
  SetLength(Start, Length(APart.Chans));
  SetLength(XS, Length(APart.Chans));
  SetLength(YS, Length(APart.Chans));
  SetLength(CSize, Length(APart.Chans));
  SetLength(Cur, Length(APart.Chans));
  Total := 0;
  for I := 0 to High(APart.Chans) do
  begin
    NX := SampleCount(APart.Chans[I].XS, APart.MinX, APart.MaxX);
    NY := SampleCount(APart.Chans[I].YS, AY0, AY0 + ALines - 1);
    Sz := PixBytes(APart.Chans[I].Pix) div 2;
    if (NX < 1) or (NY < 1) or (Sz < 1) then
      Exit;
    Add := NX * NY * Sz;
    if (Add <= 0) or (Total > MaxInt - Add) then
      Exit;
    Start[I] := Total;
    XS[I] := NX;
    YS[I] := APart.Chans[I].YS;
    CSize[I] := Sz;
    Inc(Total, Add);
  end;
  if Total < 1 then
    Exit;
  P := AAt;
  MinNZ := ReadU16(B, P);
  MaxNZ := ReadU16(B, P + 2);
  Inc(P, 4);
  if MaxNZ >= BITMAP_N then
    Exit;
  SetLength(Bitmap, BITMAP_N);
  if MinNZ <= MaxNZ then
  begin
    NWrite := MaxNZ - MinNZ + 1;
    if not Need(B, P, NWrite) then
      Exit;
    Move(B[P], Bitmap[MinNZ], NWrite);
    Inc(P, NWrite);
  end;
  SetLength(Lut, 65536);
  K := 0;
  for I := 0 to 65535 do
    if (I = 0) or ((Bitmap[I shr 3] and (1 shl (I and 7))) <> 0) then
    begin
      Lut[K] := Word(I);
      Inc(K);
    end;
  if K < 1 then
    Exit;
  MaxV := Word(K - 1);
  if not Need(B, P, 4) then
    Exit;
  NWrite := ReadI32(B, P);
  Inc(P, 4);
  if (NWrite < 0) or not Need(B, P, NWrite) then
    Exit;
  if not HufUncompress(B, P, NWrite, Total, Samples) then
    Exit;
  for I := 0 to High(APart.Chans) do
    for J := 0 to CSize[I] - 1 do
      if not Wav2Decode(Samples, Start[I] + J, XS[I], CSize[I],
        SampleCount(APart.Chans[I].YS, AY0, AY0 + ALines - 1),
        XS[I] * CSize[I], MaxV) then
        Exit;
  for I := 0 to Total - 1 do
    Samples[I] := Lut[Samples[I]];
  Expect := 0;
  for Y := AY0 to AY0 + ALines - 1 do
  begin
    Add := ScanBytes(APart, Y);
    if (Add < 0) or (Expect > MaxInt - Add) then
      Exit;
    Inc(Expect, Add);
  end;
  if Expect <> Total * 2 then
    Exit;
  SetLength(ARaw, Expect);
  for I := 0 to High(Cur) do
    Cur[I] := Start[I];
  O := 0;
  for Y := AY0 to AY0 + ALines - 1 do
    for I := 0 to High(APart.Chans) do
    begin
      if ModP(Y, YS[I]) <> 0 then
        Continue;
      NWrite := XS[I] * CSize[I];
      if Cur[I] + NWrite > Total then
        Exit;
      for J := 0 to NWrite - 1 do
      begin
        ARaw[O] := Byte(Samples[Cur[I]] and $FF);
        ARaw[O + 1] := Byte(Samples[Cur[I]] shr 8);
        Inc(Cur[I]);
        Inc(O, 2);
      end;
    end;
  Result := O = Expect;
end;

function DecompressBlock(AComp: Integer; const B: TBytes; AAt, APacked,
  AExpect: Integer; out ARaw: TBytes): Boolean;
begin
  if AComp = 0 then
  begin
    Result := False;
    if (APacked <> AExpect) or not Need(B, AAt, APacked) then
      Exit;
    SetLength(ARaw, AExpect);
    if AExpect > 0 then
      Move(B[AAt], ARaw[0], AExpect);
    Exit(True);
  end;
  if (AComp = 1) or (AComp = 2) or (AComp = 3) then
    Result := Unpredict(AComp, B, AAt, APacked, AExpect, ARaw)
  else
    Result := False;
end;

function TakeScan(const Raw: TBytes; var O: Integer; const APart: TExrPart;
  Y: Integer; AW: Integer; var ARgb: TArray<Single>): Boolean;
var
  I, N, Bp, X, PixY, Idx: Integer;
  Value: Single;
begin
  Result := False;
  PixY := Y - APart.MinY;
  if (PixY < 0) or (PixY >= (APart.MaxY - APart.MinY + 1)) then
    Exit;
  for I := 0 to High(APart.Chans) do
  begin
    if not OnScan(Y, APart.Chans[I].YS, APart.MinY) then
      Continue;
    N := SampleCount(APart.Chans[I].XS, APart.MinX, APart.MaxX);
    Bp := PixBytes(APart.Chans[I].Pix);
    if (Bp <= 0) or (N < 0) or not Need(Raw, O, N * Bp) then
      Exit;
    if (I = APart.IR) or (I = APart.IG) or (I = APart.IB) then
    begin
      if N <> AW then
        Exit;
      for X := 0 to N - 1 do
      begin
        Value := SampleFloat(Raw, O + X * Bp, APart.Chans[I].Pix);
        Idx := (PixY * AW + X) * 3;
        if I = APart.IR then
          ARgb[Idx] := Value
        else if I = APart.IG then
          ARgb[Idx + 1] := Value
        else
          ARgb[Idx + 2] := Value;
      end;
    end;
    Inc(O, N * Bp);
  end;
  Result := True;
end;

function DecodeScanPart(const B: TBytes; const APart: TExrPart; ATable: Integer;
  AMultipart: Boolean; out AImg: THdrImage): THdrError;
var
  W, H, Lines, Chunks, I, At, Y0, PackN, NLines, Line, YLine: Integer;
  Expect, O, Dir, Add: Integer;
  Off: Int64;
  Raw: TBytes;
begin
  Result := heBad;
  AImg.Clear;
  W := APart.MaxX - APart.MinX + 1;
  H := APart.MaxY - APart.MinY + 1;
  Lines := LinesPerBlock(APart.Comp);
  Chunks := (H + Lines - 1) div Lines;
  if APart.HasChunk and (APart.ChunkN <> Chunks) then
    Exit;
  if (Chunks < 1) or not Need(B, ATable, Chunks * 8) then
    Exit;
  AImg.Width := W;
  AImg.Height := H;
  SetLength(AImg.Rgb, W * H * 3);
  if APart.LineOrder = 1 then
    Dir := -1
  else
    Dir := 1;
  for I := 0 to Chunks - 1 do
  begin
    Off := ReadI64(B, ATable + I * 8);
    if (Off <= 0) or (Off > Length(B)) then
    begin
      AImg.Clear;
      Exit;
    end;
    At := Integer(Off);
    if AMultipart then
    begin
      if not Need(B, At, 4) then
      begin
        AImg.Clear;
        Exit;
      end;
      Inc(At, 4);
    end;
    if not Need(B, At, 8) then
    begin
      AImg.Clear;
      Exit;
    end;
    Y0 := ReadI32(B, At);
    PackN := ReadI32(B, At + 4);
    Inc(At, 8);
    if APart.Comp = 4 then
    begin
      NLines := Min(Lines, APart.MaxY - Y0 + 1);
      if (Y0 < APart.MinY) or (NLines < 1) or
         not PizUncompress(B, At, PackN, APart, Y0, NLines, Raw) then
      begin
        AImg.Clear;
        Exit;
      end;
      O := 0;
      for Line := 0 to NLines - 1 do
        if not TakeScan(Raw, O, APart, Y0 + Line, W, AImg.Rgb) then
        begin
          AImg.Clear;
          Exit;
        end;
      if O <> Length(Raw) then
      begin
        AImg.Clear;
        Exit;
      end;
      Continue;
    end;
    if Dir > 0 then
      NLines := Min(Lines, APart.MaxY - Y0 + 1)
    else
      NLines := Min(Lines, Y0 - APart.MinY + 1);
    if NLines < 1 then
    begin
      AImg.Clear;
      Exit;
    end;
    Expect := 0;
    for Line := 0 to NLines - 1 do
    begin
      if Dir > 0 then
        YLine := Y0 + Line
      else
        YLine := Y0 - Line;
      Add := ScanBytes(APart, YLine);
      if (Add < 0) or (Expect > MaxInt - Add) then
      begin
        AImg.Clear;
        Exit;
      end;
      Inc(Expect, Add);
    end;
    if not DecompressBlock(APart.Comp, B, At, PackN, Expect, Raw) then
    begin
      AImg.Clear;
      Exit;
    end;
    O := 0;
    for Line := 0 to NLines - 1 do
    begin
      if Dir > 0 then
        YLine := Y0 + Line
      else
        YLine := Y0 - Line;
      if not TakeScan(Raw, O, APart, YLine, W, AImg.Rgb) then
      begin
        AImg.Clear;
        Exit;
      end;
    end;
    if O <> Length(Raw) then
    begin
      AImg.Clear;
      Exit;
    end;
  end;
  Result := heNone;
end;

function DecodeExr(const B: TBytes; out AImg: THdrImage): THdrError;
var
  P, I, Chosen, Table, SkipN, Flags: Integer;
  Multipart, LongName, TiledFlag, DeepFlag, SawHeader, FoundRgb: Boolean;
  Parts: TArray<TExrPart>;
  Part: TExrPart;
begin
  Result := heBad;
  AImg.Clear;
  if Length(B) < 8 then
    Exit;
  if (B[0] <> $76) or (B[1] <> $2F) or (B[2] <> $31) or (B[3] <> $01) then
    Exit;
  if B[4] <> 2 then
    Exit;
  Flags := B[5];
  TiledFlag := (Flags and $02) <> 0;
  LongName := (Flags and $04) <> 0;
  DeepFlag := (Flags and $08) <> 0;
  Multipart := (Flags and $10) <> 0;
  if DeepFlag and not Multipart then
    Exit;
  P := 8;
  SetLength(Parts, 0);
  SawHeader := False;
  while P >= 0 do
  begin
    if Multipart and (Length(Parts) > 0) and Need(B, P, 1) and (B[P] = 0) then
    begin
      Inc(P);
      Break;
    end;
    if not ParseHeader(B, P, LongName, Part) then
      Exit;
    SawHeader := True;
    if not Multipart and TiledFlag then
      Part.Tiled := True;
    FinishPart(Part, False);
    SetLength(Parts, Length(Parts) + 1);
    Parts[High(Parts)] := Part;
    if not Multipart then
      Break;
    if Length(Parts) > 64 then
      Exit;
  end;
  if not SawHeader or (Length(Parts) = 0) or (P < 0) then
    Exit;
  Chosen := -1;
  FoundRgb := False;
  for I := 0 to High(Parts) do
  begin
    if Parts[I].HasRgb then
      FoundRgb := True;
    if (Chosen < 0) and Parts[I].Decodable then
      Chosen := I;
  end;
  if Chosen < 0 then
  begin
    if FoundRgb then
      Result := heBad
    else
      Result := heNoRgb;
    Exit;
  end;
  Table := P;
  for I := 0 to Chosen - 1 do
  begin
    SkipN := PartChunkCount(Parts[I]);
    if SkipN < 0 then
      Exit;
    if not Need(B, Table, SkipN * 8) then
      Exit;
    Inc(Table, SkipN * 8);
  end;
  Result := DecodeScanPart(B, Parts[Chosen], Table, Multipart, AImg);
end;

function LoadHdrImage(const APath: string; out AImg: THdrImage): THdrError;
var
  B: TBytes;
  Ext: string;
begin
  AImg.Clear;
  try
    if not ReadFileShare(APath, B) then
      Exit(heBad);
    Ext := LowerCase(ExtractFileExt(APath));
    if Ext = '.exr' then
      Result := DecodeExr(B, AImg)
    else
      Result := DecodeHdr(B, AImg);
    SetLength(B, 0);
  except
    AImg.Clear;
    Result := heBad;
  end;
end;

function RenderHdrThumb(const APath: string; ASize: Integer): TBitmap;
var
  Img: THdrImage;
  Err: THdrError;
  DW, DH: Integer;
  Scale: Single;
begin
  Result := nil;
  if ASize < 16 then
    ASize := 16
  else if ASize > 512 then
    ASize := 512;
  Err := LoadHdrImage(APath, Img);
  if Err <> heNone then
  begin
    Img.Clear;
    Exit;
  end;
  try
    Result := TBitmap.Create;
    try
      if (Img.Width <= ASize) and (Img.Height <= ASize) then
      begin
        if not ToneMapHdr(Img.Rgb, Img.Width, Img.Height, 0, Result) then
          FreeAndNil(Result);
      end
      else
      begin
        Scale := ASize / Img.Width;
        if Img.Height * Scale > ASize then
          Scale := ASize / Img.Height;
        DW := Max(1, Round(Img.Width * Scale));
        DH := Max(1, Round(Img.Height * Scale));
        if not ToneMapBox(Img.Rgb, Img.Width, Img.Height, DW, DH, 0, Result) then
          FreeAndNil(Result);
      end;
    except
      FreeAndNil(Result);
    end;
  finally
    Img.Clear;
  end;
end;

end.
