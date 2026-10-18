unit uFontConvert;

{
  Честная смена коробки шрифта: sfnt ↔ WOFF (zlib) и, если рядом brotli.dll,
  sfnt ↔ WOFF2 без преобразования glyf/loca. Контуры glyf в CFF не переводятся.
  Сети нет, исходный файл эта единица не перезаписывает.
}

interface

uses
  System.SysUtils;

type
  TFontContainer = (fcUnknown, fcTtf, fcOtf, fcWoff, fcWoff2, fcTtc, fcFon, fcEot);

  TFontTarget = (ftTtf, ftOtf, ftWoff, ftWoff2);

  TFontFaceInfo = record
    Name: string;
    Family: string;
    Bold: Boolean;
    Italic: Boolean;
    GlyphCount: Integer;
  end;

  TFontProbe = record
    Ok: Boolean;
    Container: TFontContainer;
    Flavor: Cardinal;
    GlyphCount: Integer;
    Faces: TArray<TFontFaceInfo>;
    Problem: string;
    Convertible: Boolean;
  end;

  TFontOffer = record
    Target: TFontTarget;
    Caption: string;
    Ext: string;
  end;

{ Потолок списка для карты глифов. Сначала BMP, остальное не разворачивается. }
const
  FontCodeCap = 16384;

function ProbeFont(const APath: string): TFontProbe;
function ContainerTitle(AContainer: TFontContainer): string;
function BrotliBesideExe: Boolean;
function FontOffers(const AProbe: TFontProbe; ABrotli: Boolean): TArray<TFontOffer>;
{ Байты одного лица (sfnt) и коды cmap без .notdef и без U+0000..U+001F.
  AStrict: ошибка контрольной суммы — отказ. Иначе байты всё равно возвращаются,
  а текст ошибки остаётся в AError. }
function LoadFace(const APath: string; AFace: Integer; AStrict: Boolean;
  out ABytes: TBytes; out ACodes: TArray<Integer>; out AGlyphs: Integer;
  out AError: string): Boolean;
{ Один проход по файлу: проба всех лиц и sfnt выбранного. Файл не читается дважды. }
function OpenFont(const APath: string; AFace: Integer; out AProbe: TFontProbe;
  out ABytes: TBytes; out ACodes: TArray<Integer>; out AGlyphs: Integer;
  out AError: string): Boolean;
function ConvertFont(const ASrc, ADst: string; ATarget: TFontTarget;
  out AError: string): Boolean;

implementation

uses
  System.Classes, System.Math, System.IOUtils, System.ZLib,
  System.Generics.Collections, System.Generics.Defaults,
  Winapi.Windows, uLang;

const
  SIG_TTF  = $00010000;
  SIG_OTTO = $4F54544F;
  SIG_TRUE = $74727565;
  SIG_WOFF = $774F4646;
  SIG_WOF2 = $774F4632;
  SIG_TTC  = $74746366;
  SIG_TYP1 = $74797031;
  TAG_HEAD = $68656164;
  TAG_MAXP = $6D617870;
  TAG_CMAP = $636D6170;
  TAG_NAME = $6E616D65;
  TAG_GLYF = $676C7966;
  TAG_LOCA = $6C6F6361;

  WOFF2_TAGS: array[0..62] of Cardinal = (
    $636D6170, $68656164, $68686561, $686D7478, $6D617870, $6E616D65, $4F532F32, $706F7374,
    $63767420, $6670676D, $676C7966, $6C6F6361, $70726570, $43464620, $564F5247, $45424454,
    $45424C43, $67617370, $68646D78, $6B65726E, $4C545348, $50434C54, $56444D58, $76686561,
    $766D7478, $42415345, $47444546, $47504F53, $47535542, $45425343, $4A535446, $4D415448,
    $43424454, $43424C43, $434F4C52, $4350414C, $53564720, $73626978, $61636E74, $61766172,
    $62646174, $626C6F63, $62736C6E, $63766172, $66647363, $66656174, $666D7478, $66766172,
    $67766172, $68737479, $6A757374, $6C636172, $6D6F7274, $6D6F7278, $6F706264, $70726F70,
    $7472616B, $5A617066, $53696C66, $476C6174, $476C6F63, $46656174, $53696C6C);

type
  TSfntTable = record
    Tag: Cardinal;
    Checksum: Cardinal;
    Data: TBytes;
  end;

  TBrotliEncode = function(quality, lgwin, mode: Integer; input_size: NativeUInt;
    input_buffer: Pointer; var encoded_size: NativeUInt; encoded_buffer: Pointer): Integer; cdecl;
  TBrotliDecode = function(encoded_size: NativeUInt; encoded_buffer: Pointer;
    var decoded_size: NativeUInt; decoded_buffer: Pointer): Integer; cdecl;

var
  GBrotliLooked: Boolean;
  GBrotliOk: Boolean;
  GBrotliLib: HMODULE;
  GBrotliEnc: TBrotliEncode;
  GBrotliDec: TBrotliDecode;

function ReadU16(const B: TBytes; O: Integer): Word;
begin
  Result := (Word(B[O]) shl 8) or Word(B[O + 1]);
end;

function ReadU32(const B: TBytes; O: Integer): Cardinal;
begin
  Result := (Cardinal(B[O]) shl 24) or (Cardinal(B[O + 1]) shl 16) or
    (Cardinal(B[O + 2]) shl 8) or Cardinal(B[O + 3]);
end;

function ReadI16(const B: TBytes; O: Integer): Smallint;
begin
  Result := Smallint(ReadU16(B, O));
end;

procedure WriteU16(var B: TBytes; O: Integer; V: Word);
begin
  B[O] := Byte(V shr 8);
  B[O + 1] := Byte(V);
end;

procedure WriteU32(var B: TBytes; O: Integer; V: Cardinal);
begin
  B[O] := Byte(V shr 24);
  B[O + 1] := Byte(V shr 16);
  B[O + 2] := Byte(V shr 8);
  B[O + 3] := Byte(V);
end;

function Align4(V: Integer): Integer;
begin
  Result := (V + 3) and not 3;
end;

function Slice(const B: TBytes; O, N: Integer): TBytes;
begin
  SetLength(Result, 0);
  if (N <= 0) or (O < 0) or (O + N > Length(B)) then
    Exit;
  SetLength(Result, N);
  if N > 0 then
    Move(B[O], Result[0], N);
end;

function InRange(const B: TBytes; O, N: Integer): Boolean;
begin
  Result := (O >= 0) and (N >= 0) and (O <= Length(B)) and (N <= Length(B) - O);
end;

function TableChecksum(const Data: TBytes; AZeroHeadAdj: Boolean): Cardinal;
var
  Padded: TBytes;
  I, N: Integer;
  V: Cardinal;
begin
  N := Length(Data);
  SetLength(Padded, Align4(N));
  if N > 0 then
    Move(Data[0], Padded[0], N);
  if AZeroHeadAdj and (Length(Padded) >= 12) then
  begin
    Padded[8] := 0;
    Padded[9] := 0;
    Padded[10] := 0;
    Padded[11] := 0;
  end;
  Result := 0;
  I := 0;
  while I + 3 < Length(Padded) do
  begin
    V := (Cardinal(Padded[I]) shl 24) or (Cardinal(Padded[I + 1]) shl 16) or
      (Cardinal(Padded[I + 2]) shl 8) or Cardinal(Padded[I + 3]);
    Result := Cardinal(Result + V);
    Inc(I, 4);
  end;
end;

function FindTable(const ATables: TArray<TSfntTable>; ATag: Cardinal): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ATables) do
    if ATables[I].Tag = ATag then
      Exit(I);
  Result := -1;
end;

procedure SearchHeader(N: Integer; out ASearch, AEntry, ARange: Word);
var
  Max2, Log: Integer;
begin
  Max2 := 1;
  Log := 0;
  while (Max2 * 2 <= N) and (Log < 15) do
  begin
    Max2 := Max2 * 2;
    Inc(Log);
  end;
  AEntry := Word(Log);
  ASearch := Word(Max2 * 16);
  ARange := Word(N * 16 - ASearch);
end;

function ReadSfnt(const B: TBytes; AOrigin: Integer; out AFlavor: Cardinal;
  out ATables: TArray<TSfntTable>; out AError: string): Boolean;
var
  N, I, Off, Len, Dir: Integer;
  Tag, Sum: Cardinal;
begin
  Result := False;
  AError := '';
  SetLength(ATables, 0);
  AFlavor := 0;
  if not InRange(B, AOrigin, 12) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  AFlavor := ReadU32(B, AOrigin);
  if (AFlavor <> SIG_TTF) and (AFlavor <> SIG_OTTO) and (AFlavor <> SIG_TRUE) and
     (AFlavor <> SIG_TYP1) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  N := ReadU16(B, AOrigin + 4);
  if (N < 1) or (N > 128) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  Dir := AOrigin + 12;
  if not InRange(B, Dir, N * 16) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  SetLength(ATables, N);
  for I := 0 to N - 1 do
  begin
    Tag := ReadU32(B, Dir + I * 16);
    Sum := ReadU32(B, Dir + I * 16 + 4);
    Off := Integer(ReadU32(B, Dir + I * 16 + 8));
    Len := Integer(ReadU32(B, Dir + I * 16 + 12));
    if (Len < 0) or (Off < 0) or not InRange(B, Off, Len) then
    begin
      AError := L('font.unreadable');
      SetLength(ATables, 0);
      Exit;
    end;
    ATables[I].Tag := Tag;
    ATables[I].Checksum := Sum;
    ATables[I].Data := Slice(B, Off, Len);
  end;
  Result := True;
end;

function KnownTag(AFlags: Integer): Cardinal;
begin
  if (AFlags >= 0) and (AFlags <= High(WOFF2_TAGS)) then
    Result := WOFF2_TAGS[AFlags]
  else
    Result := 0;
end;

function KnownIndex(ATag: Cardinal): Integer;
var
  I: Integer;
begin
  for I := 0 to High(WOFF2_TAGS) do
    if WOFF2_TAGS[I] = ATag then
      Exit(I);
  Result := -1;
end;

function ReadU16LE(const B: TBytes; O: Integer): Word;
begin
  Result := Word(B[O]) or (Word(B[O + 1]) shl 8);
end;

function ReadBase128(const B: TBytes; var P: Integer; out V: Cardinal): Boolean;
var
  I: Integer;
  By: Byte;
begin
  Result := False;
  V := 0;
  if P >= Length(B) then
    Exit;
  for I := 0 to 4 do
  begin
    if P >= Length(B) then
      Exit;
    By := B[P];
    Inc(P);
    if (I = 0) and (By = $80) then
      Exit;
    if V > (Cardinal($FFFFFFFF) shr 7) then
      Exit;
    V := (V shl 7) or (By and $7F);
    if (By and $80) = 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure AppendBase128(var B: TBytes; V: Cardinal);
var
  Tmp: array[0..4] of Byte;
  N, I, At: Integer;
begin
  N := 0;
  repeat
    Tmp[N] := Byte(V and $7F);
    V := V shr 7;
    Inc(N);
  until V = 0;
  At := Length(B);
  SetLength(B, At + N);
  for I := 0 to N - 1 do
  begin
    B[At + I] := Tmp[N - 1 - I];
    if I < N - 1 then
      B[At + I] := B[At + I] or $80;
  end;
end;

function BrotliCompress(const Input: TBytes; out Output: TBytes): Boolean;
var
  Need: NativeUInt;
  Buf: TBytes;
begin
  Result := False;
  SetLength(Output, 0);
  if not GBrotliOk or not Assigned(GBrotliEnc) then
    Exit;
  if Length(Input) = 0 then
  begin
    SetLength(Output, 0);
    Exit(True);
  end;
  Need := NativeUInt(Length(Input) + (Length(Input) div 4) + 128);
  SetLength(Buf, Need);
  if GBrotliEnc(11, 22, 2, NativeUInt(Length(Input)), @Input[0], Need, @Buf[0]) = 0 then
    Exit;
  if Need > NativeUInt(Length(Buf)) then
    Exit;
  SetLength(Buf, Need);
  Output := Buf;
  Result := True;
end;

function BrotliDecompress(const Input: TBytes; ANeed: Integer; out Output: TBytes): Boolean;
var
  Got: NativeUInt;
begin
  Result := False;
  SetLength(Output, 0);
  if (ANeed < 0) or not GBrotliOk or not Assigned(GBrotliDec) then
    Exit;
  if ANeed = 0 then
    Exit(True);
  if Length(Input) = 0 then
    Exit;
  SetLength(Output, ANeed);
  Got := NativeUInt(ANeed);
  if GBrotliDec(NativeUInt(Length(Input)), @Input[0], Got, @Output[0]) <> 1 then
  begin
    SetLength(Output, 0);
    Exit;
  end;
  if Integer(Got) <> ANeed then
  begin
    SetLength(Output, 0);
    Exit;
  end;
  Result := True;
end;

function ReadWoff(const B: TBytes; out AFlavor: Cardinal; out ATables: TArray<TSfntTable>;
  AStrict: Boolean; out AError: string): Boolean;
var
  N, I, Off, CompLen, OrigLen, Pos: Integer;
  Sum: Cardinal;
  Raw, Plain: TBytes;
  BadSum: Boolean;
begin
  Result := False;
  AError := '';
  SetLength(ATables, 0);
  AFlavor := 0;
  BadSum := False;
  if (Length(B) < 44) or (ReadU32(B, 0) <> SIG_WOFF) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  AFlavor := ReadU32(B, 4);
  N := ReadU16(B, 12);
  if (N < 1) or (N > 128) or not InRange(B, 44, N * 20) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  SetLength(ATables, N);
  for I := 0 to N - 1 do
  begin
    Pos := 44 + I * 20;
    Off := Integer(ReadU32(B, Pos + 4));
    CompLen := Integer(ReadU32(B, Pos + 8));
    OrigLen := Integer(ReadU32(B, Pos + 12));
    Sum := ReadU32(B, Pos + 16);
    if (CompLen < 0) or (OrigLen < 0) or (CompLen > OrigLen) or
       not InRange(B, Off, CompLen) then
    begin
      AError := L('font.unreadable');
      SetLength(ATables, 0);
      Exit;
    end;
    Raw := Slice(B, Off, CompLen);
    if CompLen = OrigLen then
      Plain := Raw
    else
    begin
      try
        ZDecompress(Raw, Plain);
      except
        Plain := nil;
      end;
      if Length(Plain) <> OrigLen then
      begin
        AError := L('font.unreadable');
        SetLength(ATables, 0);
        Exit;
      end;
    end;
    ATables[I].Tag := ReadU32(B, Pos);
    ATables[I].Data := Plain;
    ATables[I].Checksum := TableChecksum(Plain, ATables[I].Tag = TAG_HEAD);
    if ATables[I].Checksum <> Sum then
      BadSum := True;
  end;
  if BadSum then
  begin
    AError := L('font.checksum');
    if AStrict then
    begin
      SetLength(ATables, 0);
      Exit;
    end;
  end;
  Result := True;
end;

function ReadWoff2(const B: TBytes; out AFlavor: Cardinal; out ATables: TArray<TSfntTable>;
  AStrict: Boolean; out AError: string): Boolean;
var
  N, I, P, CompSize, Flags, Idx, Ver: Integer;
  Tag, Orig, TransLen, Total: Cardinal;
  Lens: TArray<Integer>;
  CompBytes, Plain: TBytes;
  At: Integer;
  Transformed: Boolean;
begin
  Result := False;
  AError := '';
  SetLength(ATables, 0);
  AFlavor := 0;
  if not BrotliBesideExe then
  begin
    AError := L('font.woff2');
    Exit;
  end;
  if (Length(B) < 48) or (ReadU32(B, 0) <> SIG_WOF2) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  AFlavor := ReadU32(B, 4);
  N := ReadU16(B, 12);
  CompSize := Integer(ReadU32(B, 20));
  if (N < 1) or (N > 128) or (CompSize < 0) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  P := 48;
  SetLength(ATables, N);
  SetLength(Lens, N);
  Total := 0;
  Transformed := False;
  for I := 0 to N - 1 do
  begin
    if P >= Length(B) then
    begin
      AError := L('font.unreadable');
      Exit;
    end;
    Flags := B[P];
    Inc(P);
    Idx := Flags and $3F;
    Ver := Flags shr 6;
    if Idx = 63 then
    begin
      if not InRange(B, P, 4) then
      begin
        AError := L('font.unreadable');
        Exit;
      end;
      Tag := ReadU32(B, P);
      Inc(P, 4);
    end
    else
      Tag := KnownTag(Idx);
    if not ReadBase128(B, P, Orig) then
    begin
      AError := L('font.unreadable');
      Exit;
    end;
    if (Tag = TAG_GLYF) or (Tag = TAG_LOCA) then
    begin
      if Ver <> 3 then
      begin
        Transformed := True;
        if not ReadBase128(B, P, TransLen) then
        begin
          AError := L('font.unreadable');
          Exit;
        end;
      end;
    end
    else if Ver <> 0 then
    begin
      Transformed := True;
      if not ReadBase128(B, P, TransLen) then
      begin
        AError := L('font.unreadable');
        Exit;
      end;
    end;
    if Orig > Cardinal(64 * 1024 * 1024) then
    begin
      AError := L('font.unreadable');
      Exit;
    end;
    ATables[I].Tag := Tag;
    ATables[I].Checksum := 0;
    Lens[I] := Integer(Orig);
    Total := Total + Orig;
  end;
  if Transformed then
  begin
    AError := L('font.woff2xform');
    SetLength(ATables, 0);
    Exit;
  end;
  if (Total > Cardinal(64 * 1024 * 1024)) or not InRange(B, P, CompSize) then
  begin
    AError := L('font.unreadable');
    SetLength(ATables, 0);
    Exit;
  end;
  CompBytes := Slice(B, P, CompSize);
  if not BrotliDecompress(CompBytes, Integer(Total), Plain) then
  begin
    AError := L('font.unreadable');
    SetLength(ATables, 0);
    Exit;
  end;
  At := 0;
  for I := 0 to N - 1 do
  begin
    if At + Lens[I] > Length(Plain) then
    begin
      AError := L('font.unreadable');
      SetLength(ATables, 0);
      Exit;
    end;
    ATables[I].Data := Slice(Plain, At, Lens[I]);
    ATables[I].Checksum := TableChecksum(ATables[I].Data, ATables[I].Tag = TAG_HEAD);
    Inc(At, Lens[I]);
  end;
  if At <> Length(Plain) then
  begin
    AError := L('font.unreadable');
    SetLength(ATables, 0);
    Exit;
  end;
  Result := True;
  if AStrict and (AError <> '') then
    Result := False;
end;

function ReadFileBytes(const APath: string; out B: TBytes; out AError: string): Boolean;
begin
  Result := False;
  AError := '';
  SetLength(B, 0);
  try
    B := TFile.ReadAllBytes(APath);
  except
    AError := L('font.unreadable');
    Exit;
  end;
  if Length(B) < 12 then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  Result := True;
end;

function EotPayload(const B: TBytes): TBytes;
var
  DataSize, Total, Start: Integer;
begin
  SetLength(Result, 0);
  if (Length(B) < 36) or (ReadU16LE(B, 34) <> $504C) then
    Exit;
  Total := Integer(Cardinal(B[0]) or (Cardinal(B[1]) shl 8) or
    (Cardinal(B[2]) shl 16) or (Cardinal(B[3]) shl 24));
  DataSize := Integer(Cardinal(B[4]) or (Cardinal(B[5]) shl 8) or
    (Cardinal(B[6]) shl 16) or (Cardinal(B[7]) shl 24));
  if (DataSize < 12) or (DataSize > Length(B)) then
    Exit;
  Start := Length(B) - DataSize;
  if (Total > DataSize) and (Total <= Length(B)) then
    Start := Total - DataSize;
  if not InRange(B, Start, DataSize) then
    Exit;
  Result := Slice(B, Start, DataSize);
end;

function ContainerOf(const B: TBytes): TFontContainer;
var
  Sig: Cardinal;
begin
  Result := fcUnknown;
  if Length(B) < 4 then
    Exit;
  Sig := ReadU32(B, 0);
  if (Sig = SIG_TTF) or (Sig = SIG_TRUE) then
    Exit(fcTtf);
  if Sig = SIG_OTTO then
    Exit(fcOtf);
  if Sig = SIG_WOFF then
    Exit(fcWoff);
  if Sig = SIG_WOF2 then
    Exit(fcWoff2);
  if Sig = SIG_TTC then
    Exit(fcTtc);
  if (Length(B) >= 36) and (ReadU16LE(B, 34) = $504C) then
    Exit(fcEot);
  if (B[0] = $4D) and (B[1] = $5A) then
    Result := fcFon;
end;

function FaceOffsets(const B: TBytes): TArray<Integer>;
var
  N, I: Integer;
begin
  SetLength(Result, 0);
  if (Length(B) < 12) or (ReadU32(B, 0) <> SIG_TTC) then
    Exit;
  N := Integer(ReadU32(B, 8));
  if (N < 1) or (N > 64) or not InRange(B, 12, N * 4) then
    Exit;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := Integer(ReadU32(B, 12 + I * 4));
end;

function ReadTables(const B: TBytes; AFace: Integer; AStrict: Boolean;
  out AFlavor: Cardinal; out ATables: TArray<TSfntTable>; out AError: string): Boolean;
var
  Kind: TFontContainer;
  Offs: TArray<Integer>;
  Payload: TBytes;
  Origin: Integer;
begin
  Result := False;
  AError := '';
  AFlavor := 0;
  SetLength(ATables, 0);
  Kind := ContainerOf(B);
  if Kind = fcTtc then
  begin
    Offs := FaceOffsets(B);
    if (AFace < 0) or (AFace > High(Offs)) then
    begin
      AError := L('font.unreadable');
      Exit;
    end;
    Result := ReadSfnt(B, Offs[AFace], AFlavor, ATables, AError);
    Exit;
  end;
  if Kind = fcEot then
  begin
    Payload := EotPayload(B);
    if Length(Payload) < 12 then
    begin
      AError := L('font.unreadable');
      Exit;
    end;
    Result := ReadSfnt(Payload, 0, AFlavor, ATables, AError);
    Exit;
  end;
  if Kind = fcWoff then
    Exit(ReadWoff(B, AFlavor, ATables, AStrict, AError));
  if Kind = fcWoff2 then
    Exit(ReadWoff2(B, AFlavor, ATables, AStrict, AError));
  if (Kind = fcTtf) or (Kind = fcOtf) or
     ((Length(B) >= 4) and (ReadU32(B, 0) = SIG_TYP1)) then
  begin
    Origin := 0;
    Result := ReadSfnt(B, Origin, AFlavor, ATables, AError);
    Exit;
  end;
  AError := L('font.unreadable');
end;

function Utf16Be(const B: TBytes; O, N: Integer): string;
var
  I, C: Integer;
begin
  Result := '';
  if not InRange(B, O, N) or (N < 2) then
    Exit;
  C := N div 2;
  SetLength(Result, C);
  for I := 0 to C - 1 do
    Result[I + 1] := WideChar(ReadU16(B, O + I * 2));
end;

function NameString(const NameTbl: TBytes; ANameId: Integer): string;
var
  Count, Store, I, Rec, Pid, Eid, Nid, Len, Off: Integer;
  Best: Integer;
begin
  Result := '';
  Best := -1;
  if Length(NameTbl) < 6 then
    Exit;
  Count := ReadU16(NameTbl, 2);
  Store := ReadU16(NameTbl, 4);
  if (Count < 0) or (Count > 256) then
    Exit;
  for I := 0 to Count - 1 do
  begin
    Rec := 6 + I * 12;
    if not InRange(NameTbl, Rec, 12) then
      Break;
    Pid := ReadU16(NameTbl, Rec);
    Eid := ReadU16(NameTbl, Rec + 2);
    Nid := ReadU16(NameTbl, Rec + 6);
    Len := ReadU16(NameTbl, Rec + 8);
    Off := ReadU16(NameTbl, Rec + 10);
    if Nid <> ANameId then
      Continue;
    if (Pid = 3) and (Eid = 1) then
    begin
      Result := Utf16Be(NameTbl, Store + Off, Len);
      if Result <> '' then
        Exit;
    end
    else if (Pid = 0) and (Best < 0) then
    begin
      Result := Utf16Be(NameTbl, Store + Off, Len);
      Best := 0;
    end;
  end;
end;

function FaceLabel(const ATables: TArray<TSfntTable>; AIndex: Integer): string;
var
  Ix: Integer;
  Sub, Fam: string;
begin
  Sub := '';
  Fam := '';
  Ix := FindTable(ATables, TAG_NAME);
  if Ix >= 0 then
  begin
    Sub := Trim(NameString(ATables[Ix].Data, 2));
    Fam := Trim(NameString(ATables[Ix].Data, 1));
  end;
  if Sub <> '' then
    Result := Sub
  else if Fam <> '' then
    Result := Fam
  else
    Result := Lf('font.face', [AIndex + 1]);
end;

procedure FaceFlags(const ATables: TArray<TSfntTable>; out ABold, AItalic: Boolean);
var
  Ix: Integer;
  Style: Word;
begin
  ABold := False;
  AItalic := False;
  Ix := FindTable(ATables, TAG_HEAD);
  if (Ix < 0) or (Length(ATables[Ix].Data) < 46) then
    Exit;
  Style := ReadU16(ATables[Ix].Data, 44);
  ABold := (Style and 1) <> 0;
  AItalic := (Style and 2) <> 0;
end;

function GlyphCount(const ATables: TArray<TSfntTable>): Integer;
var
  Ix: Integer;
begin
  Result := 0;
  Ix := FindTable(ATables, TAG_MAXP);
  if (Ix >= 0) and (Length(ATables[Ix].Data) >= 6) then
    Result := ReadU16(ATables[Ix].Data, 4);
end;

procedure AddCode(AList: TList<Integer>; ASeen: TDictionary<Integer, Boolean>; ACode, AGlyph: Integer);
begin
  if (AGlyph = 0) or (ACode <= $1F) or (ACode > $10FFFF) then
    Exit;
  if ASeen.ContainsKey(ACode) then
    Exit;
  ASeen.Add(ACode, True);
  AList.Add(ACode);
end;

procedure ReadCmapSub(const Tbl: TBytes; AStart, ALen: Integer;
  AList: TList<Integer>; ASeen: TDictionary<Integer, Boolean>);
var
  Fmt, N, I, Seg, SegCount, Code, Glyph, StartC, EndC, Delta, RangeOff, Pos: Integer;
  Groups, G, Span: Integer;
begin
  if (ALen < 4) or not InRange(Tbl, AStart, ALen) then
    Exit;
  Fmt := ReadU16(Tbl, AStart);
  if Fmt = 4 then
  begin
    if ALen < 16 then
      Exit;
    N := ReadU16(Tbl, AStart + 2);
    if (N < 16) or (N > ALen) then
      N := ALen;
    SegCount := ReadU16(Tbl, AStart + 6) div 2;
    if (SegCount < 1) or (SegCount > 512) then
      Exit;
    if AStart + 14 + SegCount * 8 + 2 > AStart + N then
      Exit;
    for Seg := 0 to SegCount - 1 do
    begin
      EndC := ReadU16(Tbl, AStart + 14 + Seg * 2);
      StartC := ReadU16(Tbl, AStart + 16 + SegCount * 2 + Seg * 2);
      Delta := ReadI16(Tbl, AStart + 16 + SegCount * 4 + Seg * 2);
      RangeOff := ReadU16(Tbl, AStart + 16 + SegCount * 6 + Seg * 2);
      if StartC > EndC then
        Continue;
      Span := EndC - StartC;
      if Span > 8192 then
        Span := 8192;
      for I := 0 to Span do
      begin
        Code := StartC + I;
        if RangeOff = 0 then
          Glyph := Word(Code + Delta)
        else
        begin
          Pos := AStart + 16 + SegCount * 6 + Seg * 2 + RangeOff + (Code - StartC) * 2;
          if not InRange(Tbl, Pos, 2) or (Pos >= AStart + N) then
            Continue;
          Glyph := ReadU16(Tbl, Pos);
          if Glyph <> 0 then
            Glyph := Word(Glyph + Delta);
        end;
        AddCode(AList, ASeen, Code, Glyph);
      end;
    end;
  end
  else if Fmt = 12 then
  begin
    if ALen < 16 then
      Exit;
    Groups := Integer(ReadU32(Tbl, AStart + 12));
    if (Groups < 0) or (Groups > 200000) then
      Exit;
    for G := 0 to Groups - 1 do
    begin
      Pos := AStart + 16 + G * 12;
      if not InRange(Tbl, Pos, 12) then
        Break;
      StartC := Integer(ReadU32(Tbl, Pos));
      EndC := Integer(ReadU32(Tbl, Pos + 4));
      Glyph := Integer(ReadU32(Tbl, Pos + 8));
      if (StartC < 0) or (EndC < StartC) then
        Continue;
      Span := EndC - StartC;
      if Span > 8192 then
        Span := 8192;
      for I := 0 to Span do
        AddCode(AList, ASeen, StartC + I, Glyph + I);
    end;
  end
  else if Fmt = 0 then
  begin
    if ALen < 262 then
      Exit;
    for I := 0 to 255 do
      AddCode(AList, ASeen, I, Tbl[AStart + 6 + I]);
  end
  else if Fmt = 6 then
  begin
    if ALen < 10 then
      Exit;
    StartC := ReadU16(Tbl, AStart + 6);
    N := ReadU16(Tbl, AStart + 8);
    if N > 8192 then
      N := 8192;
    for I := 0 to N - 1 do
    begin
      Pos := AStart + 10 + I * 2;
      if not InRange(Tbl, Pos, 2) then
        Break;
      AddCode(AList, ASeen, StartC + I, ReadU16(Tbl, Pos));
    end;
  end
  else if Fmt = 13 then
  begin
    if ALen < 16 then
      Exit;
    Groups := Integer(ReadU32(Tbl, AStart + 12));
    if (Groups < 0) or (Groups > 4096) then
      Exit;
    for G := 0 to Groups - 1 do
    begin
      Pos := AStart + 16 + G * 12;
      if not InRange(Tbl, Pos, 12) then
        Break;
      StartC := Integer(ReadU32(Tbl, Pos));
      EndC := Integer(ReadU32(Tbl, Pos + 4));
      Glyph := Integer(ReadU32(Tbl, Pos + 8));
      if (EndC < StartC) or (EndC - StartC > 8192) then
        Continue;
      for I := StartC to EndC do
        AddCode(AList, ASeen, I, Glyph);
    end;
  end;
end;

function CmapCodes(const ATables: TArray<TSfntTable>): TArray<Integer>;
var
  Ix, Count, I, Rec, Off, Len, Pid: Integer;
  Tbl: TBytes;
  List: TList<Integer>;
  Seen: TDictionary<Integer, Boolean>;
begin
  SetLength(Result, 0);
  Ix := FindTable(ATables, TAG_CMAP);
  if Ix < 0 then
    Exit;
  Tbl := ATables[Ix].Data;
  if Length(Tbl) < 4 then
    Exit;
  Count := ReadU16(Tbl, 2);
  if (Count < 1) or (Count > 64) then
    Exit;
  List := TList<Integer>.Create;
  Seen := TDictionary<Integer, Boolean>.Create;
  try
    for I := 0 to Count - 1 do
    begin
      Rec := 4 + I * 8;
      if not InRange(Tbl, Rec, 8) then
        Break;
      Pid := ReadU16(Tbl, Rec);
      if (Pid <> 0) and (Pid <> 3) and (Pid <> 1) then
        Continue;
      Off := Integer(ReadU32(Tbl, Rec + 4));
      if (Off < 0) or (Off >= Length(Tbl)) then
        Continue;
      Len := Length(Tbl) - Off;
      ReadCmapSub(Tbl, Off, Len, List, Seen);
    end;
    List.Sort(TComparer<Integer>.Construct(
      function(const L, R: Integer): Integer
      begin
        if (L <= $FFFF) <> (R <= $FFFF) then
        begin
          if L <= $FFFF then
            Result := -1
          else
            Result := 1;
        end
        else if L < R then
          Result := -1
        else if L > R then
          Result := 1
        else
          Result := 0;
      end));
    Result := List.ToArray;
    if Length(Result) > FontCodeCap then
      SetLength(Result, FontCodeCap);
  finally
    Seen.Free;
    List.Free;
  end;
end;

function BuildSfnt(AFlavor: Cardinal; const ATables: TArray<TSfntTable>): TBytes;
var
  N, I, At, Total, Pad: Integer;
  SR, ES, RS: Word;
  Sum: Cardinal;
begin
  SetLength(Result, 0);
  N := Length(ATables);
  if (N < 1) or (N > 128) then
    Exit;
  Total := 12 + N * 16;
  for I := 0 to N - 1 do
    Total := Align4(Total + Length(ATables[I].Data));
  SetLength(Result, Total);
  WriteU32(Result, 0, AFlavor);
  WriteU16(Result, 4, Word(N));
  SearchHeader(N, SR, ES, RS);
  WriteU16(Result, 6, SR);
  WriteU16(Result, 8, ES);
  WriteU16(Result, 10, RS);
  At := 12 + N * 16;
  for I := 0 to N - 1 do
  begin
    Sum := TableChecksum(ATables[I].Data, ATables[I].Tag = TAG_HEAD);
    WriteU32(Result, 12 + I * 16, ATables[I].Tag);
    WriteU32(Result, 12 + I * 16 + 4, Sum);
    WriteU32(Result, 12 + I * 16 + 8, Cardinal(At));
    WriteU32(Result, 12 + I * 16 + 12, Cardinal(Length(ATables[I].Data)));
    if Length(ATables[I].Data) > 0 then
      Move(ATables[I].Data[0], Result[At], Length(ATables[I].Data));
    At := At + Length(ATables[I].Data);
    Pad := Align4(At) - At;
    At := At + Pad;
  end;
end;

function BuildWoff(AFlavor: Cardinal; const ATables: TArray<TSfntTable>;
  out AError: string): TBytes;
var
  N, I, DirAt, DataAt, TotalSfnt, CompLen: Integer;
  Raw, Comp: TBytes;
  Sum: Cardinal;
  StoreRaw: Boolean;
begin
  SetLength(Result, 0);
  AError := '';
  N := Length(ATables);
  if N < 1 then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  DirAt := 44 + N * 20;
  SetLength(Result, DirAt);
  DataAt := DirAt;
  TotalSfnt := 12 + N * 16;
  for I := 0 to N - 1 do
  begin
    Raw := ATables[I].Data;
    Sum := TableChecksum(Raw, ATables[I].Tag = TAG_HEAD);
    StoreRaw := True;
    Comp := nil;
    if Length(Raw) > 0 then
    begin
      try
        ZCompress(Raw, Comp, zcDefault);
      except
        Comp := nil;
      end;
      if (Length(Comp) > 0) and (Length(Comp) < Length(Raw)) then
        StoreRaw := False;
    end;
    if StoreRaw then
    begin
      Comp := Raw;
      CompLen := Length(Raw);
    end
    else
      CompLen := Length(Comp);
    if Length(Result) < DataAt + CompLen + 4 then
      SetLength(Result, DataAt + CompLen + 4);
    if CompLen > 0 then
      Move(Comp[0], Result[DataAt], CompLen);
    WriteU32(Result, 44 + I * 20, ATables[I].Tag);
    WriteU32(Result, 44 + I * 20 + 4, Cardinal(DataAt));
    WriteU32(Result, 44 + I * 20 + 8, Cardinal(CompLen));
    WriteU32(Result, 44 + I * 20 + 12, Cardinal(Length(Raw)));
    WriteU32(Result, 44 + I * 20 + 16, Sum);
    DataAt := Align4(DataAt + CompLen);
    TotalSfnt := TotalSfnt + Align4(Length(Raw));
  end;
  SetLength(Result, DataAt);
  WriteU32(Result, 0, SIG_WOFF);
  WriteU32(Result, 4, AFlavor);
  WriteU32(Result, 8, Cardinal(DataAt));
  WriteU16(Result, 12, Word(N));
  WriteU16(Result, 14, 0);
  WriteU32(Result, 16, Cardinal(TotalSfnt));
  WriteU16(Result, 20, 1);
  WriteU16(Result, 22, 0);
  WriteU32(Result, 24, 0);
  WriteU32(Result, 28, 0);
  WriteU32(Result, 32, 0);
  WriteU32(Result, 36, 0);
  WriteU32(Result, 40, 0);
end;

function BuildWoff2(AFlavor: Cardinal; const ATables: TArray<TSfntTable>;
  out AError: string): TBytes;
var
  N, I, TotalSfnt, Idx: Integer;
  Plain, CompBytes, Dir: TBytes;
  Flags: Byte;
  SumLen: Integer;
begin
  SetLength(Result, 0);
  AError := '';
  if not BrotliBesideExe then
  begin
    AError := L('font.woff2');
    Exit;
  end;
  N := Length(ATables);
  if N < 1 then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  SumLen := 0;
  SetLength(Dir, 0);
  for I := 0 to N - 1 do
  begin
    Idx := KnownIndex(ATables[I].Tag);
    if Idx < 0 then
      Flags := 63
    else
      Flags := Byte(Idx);
    if (ATables[I].Tag = TAG_GLYF) or (ATables[I].Tag = TAG_LOCA) then
      Flags := Flags or $C0;
    SetLength(Dir, Length(Dir) + 1);
    Dir[High(Dir)] := Flags;
    if Idx < 0 then
    begin
      SetLength(Dir, Length(Dir) + 4);
      WriteU32(Dir, Length(Dir) - 4, ATables[I].Tag);
    end;
    AppendBase128(Dir, Cardinal(Length(ATables[I].Data)));
    SumLen := SumLen + Length(ATables[I].Data);
  end;
  SetLength(Plain, SumLen);
  SumLen := 0;
  for I := 0 to N - 1 do
  begin
    if Length(ATables[I].Data) > 0 then
      Move(ATables[I].Data[0], Plain[SumLen], Length(ATables[I].Data));
    Inc(SumLen, Length(ATables[I].Data));
  end;
  if not BrotliCompress(Plain, CompBytes) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  TotalSfnt := 12 + N * 16;
  for I := 0 to N - 1 do
    TotalSfnt := TotalSfnt + Align4(Length(ATables[I].Data));
  SetLength(Result, 48 + Length(Dir) + Length(CompBytes));
  WriteU32(Result, 0, SIG_WOF2);
  WriteU32(Result, 4, AFlavor);
  WriteU32(Result, 8, Cardinal(Length(Result)));
  WriteU16(Result, 12, Word(N));
  WriteU16(Result, 14, 0);
  WriteU32(Result, 16, Cardinal(TotalSfnt));
  WriteU32(Result, 20, Cardinal(Length(CompBytes)));
  WriteU16(Result, 24, 1);
  WriteU16(Result, 26, 0);
  WriteU32(Result, 28, 0);
  WriteU32(Result, 32, 0);
  WriteU32(Result, 36, 0);
  WriteU32(Result, 40, 0);
  WriteU32(Result, 44, 0);
  if Length(Dir) > 0 then
    Move(Dir[0], Result[48], Length(Dir));
  if Length(CompBytes) > 0 then
    Move(CompBytes[0], Result[48 + Length(Dir)], Length(CompBytes));
end;

function FlavorOfContainer(AContainer: TFontContainer; AFlavor: Cardinal): Cardinal;
begin
  if AFlavor <> 0 then
    Result := AFlavor
  else if AContainer = fcOtf then
    Result := SIG_OTTO
  else
    Result := SIG_TTF;
end;

function ContainerTitle(AContainer: TFontContainer): string;
begin
  case AContainer of
    fcTtf: Result := 'TTF';
    fcOtf: Result := 'OTF';
    fcWoff: Result := 'WOFF';
    fcWoff2: Result := 'WOFF2';
    fcTtc: Result := 'TTC';
    fcFon: Result := 'FON';
    fcEot: Result := 'EOT';
  else
    Result := '';
  end;
end;

function BrotliBesideExe: Boolean;
var
  Path: string;
  Enc, Dec: Pointer;
begin
  if not GBrotliLooked then
  begin
    GBrotliLooked := True;
    GBrotliOk := False;
    Path := ExtractFilePath(ParamStr(0)) + 'brotli.dll';
    if TFile.Exists(Path) then
    begin
      GBrotliLib := LoadLibrary(PChar(Path));
      if GBrotliLib <> 0 then
      begin
        Enc := GetProcAddress(GBrotliLib, 'BrotliEncoderCompress');
        Dec := GetProcAddress(GBrotliLib, 'BrotliDecoderDecompress');
        if (Enc <> nil) and (Dec <> nil) then
        begin
          GBrotliEnc := TBrotliEncode(Enc);
          GBrotliDec := TBrotliDecode(Dec);
          GBrotliOk := True;
        end
        else
        begin
          FreeLibrary(GBrotliLib);
          GBrotliLib := 0;
        end;
      end;
    end;
  end;
  Result := GBrotliOk;
end;

function FontOffers(const AProbe: TFontProbe; ABrotli: Boolean): TArray<TFontOffer>;
var
  N: Integer;
  Flavor: Cardinal;

  procedure Add(ATarget: TFontTarget; const ACaption, AExt: string);
  begin
    SetLength(Result, N + 1);
    Result[N].Target := ATarget;
    Result[N].Caption := ACaption;
    Result[N].Ext := AExt;
    Inc(N);
  end;

begin
  SetLength(Result, 0);
  N := 0;
  if not AProbe.Ok then
    Exit;
  if not (AProbe.Container in [fcTtf, fcOtf, fcWoff, fcWoff2]) then
    Exit;
  Flavor := FlavorOfContainer(AProbe.Container, AProbe.Flavor);
  if (AProbe.Container = fcWoff) or (AProbe.Container = fcWoff2) then
  begin
    if Flavor = SIG_OTTO then
      Add(ftOtf, 'OTF (CFF)', '.otf')
    else if Flavor <> SIG_TYP1 then
      Add(ftTtf, 'TTF (glyf)', '.ttf');
    Exit;
  end;
  if (AProbe.Container = fcTtf) or (AProbe.Container = fcOtf) then
  begin
    Add(ftWoff, 'WOFF', '.woff');
    if ABrotli then
      Add(ftWoff2, 'WOFF2', '.woff2');
  end;
end;

procedure FillFaceInfo(const ATables: TArray<TSfntTable>; AIndex: Integer;
  out AInfo: TFontFaceInfo);
var
  Ix: Integer;
begin
  AInfo.Name := FaceLabel(ATables, AIndex);
  AInfo.Family := '';
  Ix := FindTable(ATables, TAG_NAME);
  if Ix >= 0 then
    AInfo.Family := Trim(NameString(ATables[Ix].Data, 1));
  if AInfo.Family = '' then
    AInfo.Family := AInfo.Name;
  FaceFlags(ATables, AInfo.Bold, AInfo.Italic);
  AInfo.GlyphCount := GlyphCount(ATables);
end;

function DescribeFace(const B: TBytes; AOrigin: Integer; AIndex: Integer;
  out AInfo: TFontFaceInfo; out AFlavor: Cardinal): Boolean;
var
  Tables: TArray<TSfntTable>;
  Err: string;
begin
  Result := ReadSfnt(B, AOrigin, AFlavor, Tables, Err);
  if not Result then
    Exit;
  FillFaceInfo(Tables, AIndex, AInfo);
end;

function ProbeFont(const APath: string): TFontProbe;
var
  B, Payload: TBytes;
  Err: string;
  Offs: TArray<Integer>;
  I: Integer;
  Flavor: Cardinal;
  Info: TFontFaceInfo;
  Tables: TArray<TSfntTable>;
begin
  Result.Ok := False;
  Result.Container := fcUnknown;
  Result.Flavor := 0;
  Result.GlyphCount := 0;
  SetLength(Result.Faces, 0);
  Result.Problem := '';
  Result.Convertible := False;
  if not ReadFileBytes(APath, B, Err) then
    Exit;
  Result.Container := ContainerOf(B);
  if Result.Container = fcFon then
  begin
    Result.Ok := True;
    Exit;
  end;
  if Result.Container = fcTtc then
  begin
    Offs := FaceOffsets(B);
    if Length(Offs) = 0 then
      Exit;
    SetLength(Result.Faces, Length(Offs));
    for I := 0 to High(Offs) do
    begin
      if not DescribeFace(B, Offs[I], I, Info, Flavor) then
        Exit;
      Result.Faces[I] := Info;
      if I = 0 then
      begin
        Result.Flavor := Flavor;
        Result.GlyphCount := Info.GlyphCount;
      end;
    end;
    Result.Ok := True;
    Exit;
  end;
  if Result.Container = fcEot then
  begin
    Payload := EotPayload(B);
    if not ReadSfnt(Payload, 0, Flavor, Tables, Err) then
      Exit;
    Result.Flavor := Flavor;
    Result.GlyphCount := GlyphCount(Tables);
    SetLength(Result.Faces, 1);
    FillFaceInfo(Tables, 0, Result.Faces[0]);
    Result.GlyphCount := Result.Faces[0].GlyphCount;
    Result.Ok := True;
    Exit;
  end;
  if not ReadTables(B, 0, False, Flavor, Tables, Err) then
    Exit;
  Result.Flavor := Flavor;
  Result.GlyphCount := GlyphCount(Tables);
  Result.Problem := Err;
  SetLength(Result.Faces, 1);
  FillFaceInfo(Tables, 0, Result.Faces[0]);
  if Result.Faces[0].GlyphCount > 0 then
    Result.GlyphCount := Result.Faces[0].GlyphCount;
  Result.Ok := True;
  Result.Convertible := (Result.Problem = '') and
    (Result.Container in [fcTtf, fcOtf, fcWoff, fcWoff2]);
end;

function LoadFace(const APath: string; AFace: Integer; AStrict: Boolean;
  out ABytes: TBytes; out ACodes: TArray<Integer>; out AGlyphs: Integer;
  out AError: string): Boolean;
var
  B: TBytes;
  Flavor: Cardinal;
  Tables: TArray<TSfntTable>;
begin
  Result := False;
  SetLength(ABytes, 0);
  SetLength(ACodes, 0);
  AGlyphs := 0;
  AError := '';
  if not ReadFileBytes(APath, B, AError) then
    Exit;
  if not ReadTables(B, AFace, AStrict, Flavor, Tables, AError) then
    Exit;
  ABytes := BuildSfnt(Flavor, Tables);
  ACodes := CmapCodes(Tables);
  AGlyphs := GlyphCount(Tables);
  Result := Length(ABytes) > 0;
  if not Result then
    AError := L('font.unreadable');
end;

function OpenFont(const APath: string; AFace: Integer; out AProbe: TFontProbe;
  out ABytes: TBytes; out ACodes: TArray<Integer>; out AGlyphs: Integer;
  out AError: string): Boolean;
var
  B: TBytes;
  Err: string;
  Offs: TArray<Integer>;
  I: Integer;
  Flavor, FaceFlavor: Cardinal;
  Tables, Kept: TArray<TSfntTable>;
  Info: TFontFaceInfo;
  Kind: TFontContainer;
begin
  Result := False;
  AProbe.Ok := False;
  AProbe.Container := fcUnknown;
  AProbe.Flavor := 0;
  AProbe.GlyphCount := 0;
  SetLength(AProbe.Faces, 0);
  AProbe.Problem := '';
  AProbe.Convertible := False;
  SetLength(ABytes, 0);
  SetLength(ACodes, 0);
  AGlyphs := 0;
  AError := '';
  FaceFlavor := 0;
  SetLength(Kept, 0);
  if not ReadFileBytes(APath, B, AError) then
  begin
    AProbe.Problem := AError;
    Exit;
  end;
  Kind := ContainerOf(B);
  AProbe.Container := Kind;
  if Kind = fcFon then
  begin
    AProbe.Ok := True;
    AError := L('font.unreadable');
    AProbe.Problem := AError;
    Exit;
  end;
  if Kind = fcTtc then
  begin
    Offs := FaceOffsets(B);
    if (Length(Offs) = 0) or (AFace < 0) or (AFace > High(Offs)) then
    begin
      AError := L('font.unreadable');
      AProbe.Problem := AError;
      Exit;
    end;
    SetLength(AProbe.Faces, Length(Offs));
    for I := 0 to High(Offs) do
    begin
      if not ReadSfnt(B, Offs[I], Flavor, Tables, Err) then
      begin
        AError := Err;
        if AError = '' then
          AError := L('font.unreadable');
        AProbe.Problem := AError;
        Exit;
      end;
      FillFaceInfo(Tables, I, Info);
      AProbe.Faces[I] := Info;
      if I = AFace then
      begin
        Kept := Tables;
        FaceFlavor := Flavor;
      end;
    end;
    ABytes := BuildSfnt(FaceFlavor, Kept);
    ACodes := CmapCodes(Kept);
    AGlyphs := GlyphCount(Kept);
    AProbe.Flavor := FaceFlavor;
    if AGlyphs > 0 then
      AProbe.GlyphCount := AGlyphs
    else if AFace <= High(AProbe.Faces) then
      AProbe.GlyphCount := AProbe.Faces[AFace].GlyphCount;
    Result := Length(ABytes) > 0;
    if not Result then
    begin
      AError := L('font.unreadable');
      AProbe.Problem := AError;
    end
    else
      AProbe.Ok := True;
    Exit;
  end;
  if not ReadTables(B, AFace, False, Flavor, Tables, AError) then
  begin
    if AError = '' then
      AError := L('font.unreadable');
    AProbe.Problem := AError;
    Exit;
  end;
  AProbe.Flavor := Flavor;
  AProbe.Problem := AError;
  SetLength(AProbe.Faces, 1);
  FillFaceInfo(Tables, 0, AProbe.Faces[0]);
  AProbe.GlyphCount := AProbe.Faces[0].GlyphCount;
  ABytes := BuildSfnt(Flavor, Tables);
  ACodes := CmapCodes(Tables);
  AGlyphs := GlyphCount(Tables);
  if AProbe.GlyphCount = 0 then
    AProbe.GlyphCount := AGlyphs;
  Result := Length(ABytes) > 0;
  if not Result then
  begin
    AError := L('font.unreadable');
    AProbe.Problem := AError;
    AProbe.Ok := False;
  end
  else
  begin
    AProbe.Ok := True;
    AProbe.Convertible := (AProbe.Problem = '') and
      (Kind in [fcTtf, fcOtf, fcWoff, fcWoff2]);
  end;
end;

function ConvertFont(const ASrc, ADst: string; ATarget: TFontTarget;
  out AError: string): Boolean;
var
  B, OutBytes: TBytes;
  Flavor: Cardinal;
  Tables: TArray<TSfntTable>;
  Kind: TFontContainer;
begin
  Result := False;
  AError := '';
  if SameText(ExpandFileName(ASrc), ExpandFileName(ADst)) then
  begin
    AError := L('qv.replaceopen');
    Exit;
  end;
  if not ReadFileBytes(ASrc, B, AError) then
    Exit;
  Kind := ContainerOf(B);
  if not (Kind in [fcTtf, fcOtf, fcWoff, fcWoff2]) then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  if not ReadTables(B, 0, True, Flavor, Tables, AError) then
  begin
    if AError = '' then
      AError := L('font.unreadable');
    Exit;
  end;
  if (ATarget = ftOtf) and (Flavor <> SIG_OTTO) then
  begin
    AError := L('font.nototf');
    Exit;
  end;
  if (ATarget = ftTtf) and (Flavor = SIG_OTTO) then
  begin
    AError := L('font.notttf');
    Exit;
  end;
  case ATarget of
    ftWoff:
      OutBytes := BuildWoff(Flavor, Tables, AError);
    ftWoff2:
      OutBytes := BuildWoff2(Flavor, Tables, AError);
    ftOtf, ftTtf:
      OutBytes := BuildSfnt(Flavor, Tables);
  else
    OutBytes := nil;
  end;
  if AError <> '' then
    Exit;
  if Length(OutBytes) = 0 then
  begin
    AError := L('font.unreadable');
    Exit;
  end;
  try
    TFile.WriteAllBytes(ADst, OutBytes);
  except
    AError := L('qv.writefail');
    Exit;
  end;
  Result := True;
end;

initialization

finalization
  if GBrotliLib <> 0 then
  begin
    FreeLibrary(GBrotliLib);
    GBrotliLib := 0;
  end;

end.
