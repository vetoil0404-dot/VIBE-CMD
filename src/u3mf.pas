unit u3mf;

{
  3MF: zip. Корінь моделі і мініатюра беруться зі зв'язків пакета (_rels),
  інакше з імен частин. Сітка з component path підвантажується з того ж zip.
  Плоский displaycolor. Без текстур і без запису файлу.
}

interface

uses
  System.SysUtils;

const
  C3mfXmlMax = 200 * 1024 * 1024;

type
  T3mfStatus = (st3Ok, st3NotZip, st3NoModel, st3Bad, st3TooBig, st3Empty);

  T3mfVert = record
    X, Y, Z: Single;
  end;

  T3mfTri = record
    A, B, C: Integer;
    Col: Cardinal;
  end;

  T3mfCancel = reference to function: Boolean;

  T3mfModel = record
    Status: T3mfStatus;
    Cancelled: Boolean;
    Incomplete: Boolean;
    Simplified: Boolean;
    UnitName: string;
    Objects: Integer;
    HasThumb: Boolean;
    Thumb: TBytes;
    Verts: TArray<T3mfVert>;
    Tris: TArray<T3mfTri>;
  end;

function Read3mf(const APath: string; ALoadMesh: Boolean; AMaxTris, AMaxVerts: Integer;
  AMaxMs: Cardinal; const ACancel: T3mfCancel): T3mfModel;

implementation

uses
  System.Classes, System.Zip, System.Math, System.Diagnostics,
  System.Generics.Collections;

const
  C3mfDepth = 16;
  C3mfThumbMax = 12 * 1024 * 1024;
  C3mfStack = 48;

type
  TKind = (ekSkip, ekModel, ekResources, ekBases, ekObject, ekMesh, ekVerts,
    ekTris, ekComps, ekBuild);

  TVal = record
    B: array[0..511] of Byte;
    N: Integer;
  end;

  TAff = record
    M: array[0..11] of Double;
  end;

  TRawTri = record
    A, B, C: Integer;
    Pid: Integer;
    PIndex: Integer;
    HasPid: Boolean;
    Keep: Boolean;
    Col: Cardinal;
  end;

  TComp = record
    Id: Integer;
    Xf: TAff;
    Path: string;
  end;

  TPartLink = record
    Name: string;
    Ids: TDictionary<Integer, Integer>;
  end;

  TObj = record
    Id: Integer;
    HasPid: Boolean;
    Pid: Integer;
    PIndex: Integer;
    StepV: Integer;
    StepT: Integer;
    VN: Integer;
    TN: Integer;
    Verts: TArray<T3mfVert>;
    Bad: TArray<Byte>;
    Tris: TArray<TRawTri>;
    Comps: TArray<TComp>;
    CN: Integer;
  end;

  TPlan = record
    VCount: Integer;
    TCount: Integer;
    StepV: Integer;
    StepT: Integer;
  end;

  TItem = record
    Id: Integer;
    Xf: TAff;
  end;

  TMat = record
    Id: Integer;
    Cols: TArray<Cardinal>;
    N: Integer;
  end;

  TFrame = record
    Kind: TKind;
    DefCore: Boolean;
    NsMark: Integer;
  end;

  TNs = record
    Pref: string;
    Core: Boolean;
  end;

  T3mfParser = class
  private
    FBuf: TBytes;
    FLen: Integer;
    FPass: Integer;
    FMaxTris: Integer;
    FMaxVerts: Integer;
    FMaxMs: Cardinal;
    FCancel: T3mfCancel;
    FClock: TStopwatch;
    FStack: TArray<TFrame>;
    FNs: TArray<TNs>;
    FPlan: TArray<TPlan>;
    FObjs: TArray<TObj>;
    FItems: TArray<TItem>;
    FMats: TArray<TMat>;
    FCur: Integer;
    FFill: Integer;
    FLocalV: Integer;
    FLocalT: Integer;
    FMatCur: Integer;
    FSawModel: Boolean;
    FUnit: string;
    FFirstCol: Cardinal;
    FHaveFirst: Boolean;
    FCancelled: Boolean;
    FIncomplete: Boolean;
    FSimplified: Boolean;
    FOutV: TArray<T3mfVert>;
    FOutT: TArray<T3mfTri>;
    FOutVN: Integer;
    FOutTN: Integer;
    FSeen: TArray<Integer>;
    FSeenN: Integer;
    FMap: TDictionary<Integer, Integer>;
    FParts: TArray<TPartLink>;
    FPartTooBig: Boolean;
    function Halted: Boolean;
    function ParentKind: TKind;
    function ParentDef: Boolean;
    function EqI(APos, ALen: Integer; const S: string): Boolean;
    function HasAscii(const V: TVal; const S: string): Boolean;
    function UrlCore(const V: TVal): Boolean;
    function ReadQuoted(var I: Integer; ATo: Integer; out V: TVal): Boolean;
    function FindAttr(AFrom, ATo: Integer; const AName: string; out V: TVal): Boolean;
    procedure ApplyXmlns(AFrom, ATo: Integer; var ADef: Boolean);
    function ParseNum(const V: TVal; out N: Double): Boolean;
    function ParseInt(const V: TVal; out N: Integer): Boolean;
    function ParseColor(const V: TVal): Cardinal;
    function ParseXform(const V: TVal; out Xf: TAff): Boolean;
    function ValText(const V: TVal): string;
    function PathText(const V: TVal): string;
    procedure Push(AKind: TKind; ADef: Boolean; ANsMark: Integer);
    procedure Pop;
    procedure BeginObject(AFrom, ATo: Integer; out AModel: Boolean);
    procedure ReadVertex(AFrom, ATo: Integer);
    procedure ReadTriangle(AFrom, ATo: Integer);
    procedure ReadComponent(AFrom, ATo: Integer);
    procedure ReadItem(AFrom, ATo: Integer);
    procedure BeginMats(AFrom, ATo: Integer);
    procedure ReadBase(AFrom, ATo: Integer);
    procedure FinishObject;
    procedure Scan;
    procedure ResolveColors;
    function TryCol(APid, APIndex: Integer; out ACol: Cardinal): Boolean;
    function IndexOfId(AId: Integer): Integer;
    function Busy(AIndex: Integer): Boolean;
    function CountEmit(AIndex: Integer; ADepth: Integer): Int64;
    procedure EmitOne(AIndex: Integer; const AXf: TAff; ADepth: Integer; AStep: Integer);
    procedure Emit(var AModel: T3mfModel);
    function PartSlot(const APath: string): Integer;
    function PartPaths: TArray<string>;
    procedure Relink(const APath: string; const AIds: TDictionary<Integer, Integer>);
    procedure IngestPart(const APath: string; var AXml: TBytes);
  public
    destructor Destroy; override;
    procedure Parse(const AXml: TBytes; AMaxTris, AMaxVerts: Integer; AMaxMs: Cardinal;
      const ACancel: T3mfCancel);
    procedure Build(var AModel: T3mfModel);
  end;

function IsWs(C: Byte): Boolean;
begin
  Result := (C = 32) or (C = 9) or (C = 10) or (C = 13);
end;

function AffId: TAff;
var
  I: Integer;
begin
  for I := 0 to 11 do
    Result.M[I] := 0;
  Result.M[0] := 1;
  Result.M[4] := 1;
  Result.M[8] := 1;
end;

function MulAff(const P, C: TAff): TAff;
begin
  Result.M[0] := P.M[0] * C.M[0] + P.M[1] * C.M[3] + P.M[2] * C.M[6];
  Result.M[1] := P.M[0] * C.M[1] + P.M[1] * C.M[4] + P.M[2] * C.M[7];
  Result.M[2] := P.M[0] * C.M[2] + P.M[1] * C.M[5] + P.M[2] * C.M[8];
  Result.M[3] := P.M[3] * C.M[0] + P.M[4] * C.M[3] + P.M[5] * C.M[6];
  Result.M[4] := P.M[3] * C.M[1] + P.M[4] * C.M[4] + P.M[5] * C.M[7];
  Result.M[5] := P.M[3] * C.M[2] + P.M[4] * C.M[5] + P.M[5] * C.M[8];
  Result.M[6] := P.M[6] * C.M[0] + P.M[7] * C.M[3] + P.M[8] * C.M[6];
  Result.M[7] := P.M[6] * C.M[1] + P.M[7] * C.M[4] + P.M[8] * C.M[7];
  Result.M[8] := P.M[6] * C.M[2] + P.M[7] * C.M[5] + P.M[8] * C.M[8];
  Result.M[9] := P.M[0] * C.M[9] + P.M[1] * C.M[10] + P.M[2] * C.M[11] + P.M[9];
  Result.M[10] := P.M[3] * C.M[9] + P.M[4] * C.M[10] + P.M[5] * C.M[11] + P.M[10];
  Result.M[11] := P.M[6] * C.M[9] + P.M[7] * C.M[10] + P.M[8] * C.M[11] + P.M[11];
end;

function GrowTo(AHave, ANeed: Integer): Integer;
begin
  Result := AHave;
  if Result < 64 then
    Result := 64;
  while Result < ANeed do
  begin
    if Result > MaxInt div 2 then
    begin
      Result := ANeed;
      Exit;
    end;
    Result := Result * 2;
  end;
end;

function ZipNorm(const S: string): string;
var
  I, L: Integer;
begin
  Result := LowerCase(StringReplace(S, '\', '/', [rfReplaceAll]));
  I := 1;
  L := Length(Result);
  while (I <= L) and (Result[I] = '/') do
    Inc(I);
  if I > 1 then
    Result := Copy(Result, I, MaxInt);
  if (Result <> '') and (Result[Length(Result)] = '/') then
    SetLength(Result, Length(Result) - 1);
end;

function PctDecode(const S: string): string;
var
  I, V: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) and
       TryStrToInt('$' + Copy(S, I + 1, 2), V) and (V >= 32) and (V < 127) then
    begin
      Result := Result + Char(V);
      Inc(I, 3);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

function SafeZip(const S: string): string;
begin
  Result := ZipNorm(PctDecode(S));
  if (Result = '') or (Pos('..', Result) > 0) or (Pos(':', Result) > 0) then
    Exit('');
end;

function NameExt(const S: string): string;
var
  P: Integer;
begin
  P := Length(S);
  while (P > 0) and (S[P] <> '.') and (S[P] <> '/') do
    Dec(P);
  if (P < 1) or (S[P] <> '.') then
    Exit('');
  Result := Copy(S, P, MaxInt);
end;

function ModelPartName(const S: string): string;
begin
  Result := SafeZip(S);
  if NameExt(Result) <> '.model' then
    Exit('');
end;

function ImageName(const S: string): string;
var
  E: string;
begin
  Result := SafeZip(S);
  E := NameExt(Result);
  if (E <> '.png') and (E <> '.jpg') and (E <> '.jpeg') then
    Exit('');
end;

function IsPng(const B: TBytes): Boolean;
begin
  Result := (Length(B) >= 8) and (B[0] = $89) and (B[1] = $50) and (B[2] = $4E) and
    (B[3] = $47) and (B[4] = $0D) and (B[5] = $0A) and (B[6] = $1A) and (B[7] = $0A);
end;

function IsImage(const B: TBytes): Boolean;
begin
  Result := IsPng(B) or ((Length(B) >= 3) and (B[0] = $FF) and (B[1] = $D8) and
    (B[2] = $FF));
end;

function FindRelTarget(const AXml: TBytes; const AMark: string): string;
var
  S, Low, Tag: string;
  P, A, B, I, Q: Integer;
  Quote: Char;
begin
  Result := '';
  if (Length(AXml) = 0) or (Length(AXml) > 1024 * 1024) or (AMark = '') then
    Exit;
  S := TEncoding.UTF8.GetString(AXml);
  Low := LowerCase(S);
  P := Pos(LowerCase(AMark), Low);
  if P < 1 then
    Exit;
  A := P;
  while (A > 1) and (S[A] <> '<') do
    Dec(A);
  B := P;
  while (B <= Length(S)) and (S[B] <> '>') do
    Inc(B);
  if B > Length(S) then
    Exit;
  Tag := LowerCase(Copy(S, A, B - A + 1));
  I := Pos('target=', Tag);
  if I < 1 then
    Exit;
  Inc(I, 7);
  while (I <= Length(Tag)) and (Tag[I] = ' ') do
    Inc(I);
  if I > Length(Tag) then
    Exit;
  Quote := Tag[I];
  if (Quote <> '"') and (Quote <> '''') then
    Exit;
  Inc(I);
  Q := I;
  while (Q <= Length(Tag)) and (Tag[Q] <> Quote) do
    Inc(Q);
  Result := SafeZip(Copy(Tag, I, Q - I));
end;

destructor T3mfParser.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FParts) do
    FParts[I].Ids.Free;
  FMap.Free;
  inherited;
end;

function T3mfParser.Halted: Boolean;
begin
  if FCancelled or FIncomplete then
    Exit(True);
  if Assigned(FCancel) and FCancel() then
  begin
    FCancelled := True;
    Exit(True);
  end;
  if (FPass = 2) and (FMaxMs > 0) and (FClock.ElapsedMilliseconds >= FMaxMs) then
  begin
    FIncomplete := True;
    FSimplified := True;
    Exit(True);
  end;
  Result := False;
end;

function T3mfParser.ParentKind: TKind;
begin
  if Length(FStack) = 0 then
    Result := ekSkip
  else
    Result := FStack[High(FStack)].Kind;
end;

function T3mfParser.ParentDef: Boolean;
begin
  if Length(FStack) = 0 then
    Result := True
  else
    Result := FStack[High(FStack)].DefCore;
end;

function T3mfParser.EqI(APos, ALen: Integer; const S: string): Boolean;
var
  I: Integer;
  C: Byte;
begin
  if ALen <> Length(S) then
    Exit(False);
  for I := 1 to ALen do
  begin
    C := FBuf[APos + I - 1];
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      Inc(C, 32);
    if C <> Ord(S[I]) then
      Exit(False);
  end;
  Result := True;
end;

function T3mfParser.HasAscii(const V: TVal; const S: string): Boolean;
var
  I, J: Integer;
  C: Byte;
begin
  Result := False;
  if (S = '') or (V.N < Length(S)) then
    Exit;
  for I := 0 to V.N - Length(S) do
  begin
    Result := True;
    for J := 1 to Length(S) do
    begin
      C := V.B[I + J - 1];
      if (C >= Ord('A')) and (C <= Ord('Z')) then
        Inc(C, 32);
      if C <> Ord(S[J]) then
      begin
        Result := False;
        Break;
      end;
    end;
    if Result then
      Exit;
  end;
end;

function T3mfParser.UrlCore(const V: TVal): Boolean;
begin
  Result := HasAscii(V, '3dmanufacturing/core') or
    HasAscii(V, '3dmanufacturing/2013/01');
end;

function T3mfParser.ReadQuoted(var I: Integer; ATo: Integer; out V: TVal): Boolean;
var
  Q, C: Byte;
  J, K, Hex, Code: Integer;

  procedure Put(B: Byte);
  begin
    if V.N >= Length(V.B) then
    begin
      V.N := -1;
      Exit;
    end;
    V.B[V.N] := B;
    Inc(V.N);
  end;

begin
  Result := False;
  V.N := 0;
  if (I >= ATo) or ((FBuf[I] <> Ord('"')) and (FBuf[I] <> Ord(''''))) then
    Exit;
  Q := FBuf[I];
  Inc(I);
  while (I < ATo) and (FBuf[I] <> Q) and (V.N >= 0) do
  begin
    C := FBuf[I];
    if C <> Ord('&') then
    begin
      Put(C);
      Inc(I);
      Continue;
    end;
    J := I + 1;
    Code := -1;
    if (J < ATo) and (FBuf[J] = Ord('#')) then
    begin
      Inc(J);
      Hex := 0;
      if (J < ATo) and ((FBuf[J] = Ord('x')) or (FBuf[J] = Ord('X'))) then
      begin
        Inc(J);
        Hex := 1;
      end;
      Code := 0;
      K := 0;
      while J < ATo do
      begin
        C := FBuf[J];
        if Hex = 1 then
        begin
          if (C >= Ord('0')) and (C <= Ord('9')) then
            Code := Code * 16 + (C - Ord('0'))
          else if (C >= Ord('a')) and (C <= Ord('f')) then
            Code := Code * 16 + (C - Ord('a') + 10)
          else if (C >= Ord('A')) and (C <= Ord('F')) then
            Code := Code * 16 + (C - Ord('A') + 10)
          else
            Break;
        end
        else if (C >= Ord('0')) and (C <= Ord('9')) then
          Code := Code * 10 + (C - Ord('0'))
        else
          Break;
        Inc(K);
        Inc(J);
        if K > 6 then
          Break;
      end;
      if (K = 0) or (J >= ATo) or (FBuf[J] <> Ord(';')) or (Code < 0) or (Code > 255) then
        Code := -1
      else
        I := J;
    end
    else
    begin
      if EqI(J, 3, 'amp') and (J + 3 < ATo) and (FBuf[J + 3] = Ord(';')) then
      begin
        Code := Ord('&');
        I := J + 3;
      end
      else if EqI(J, 2, 'lt') and (J + 2 < ATo) and (FBuf[J + 2] = Ord(';')) then
      begin
        Code := Ord('<');
        I := J + 2;
      end
      else if EqI(J, 2, 'gt') and (J + 2 < ATo) and (FBuf[J + 2] = Ord(';')) then
      begin
        Code := Ord('>');
        I := J + 2;
      end
      else if EqI(J, 4, 'quot') and (J + 4 < ATo) and (FBuf[J + 4] = Ord(';')) then
      begin
        Code := Ord('"');
        I := J + 4;
      end
      else if EqI(J, 4, 'apos') and (J + 4 < ATo) and (FBuf[J + 4] = Ord(';')) then
      begin
        Code := Ord('''');
        I := J + 4;
      end;
    end;
    if Code < 0 then
      Put(Ord('&'))
    else
      Put(Byte(Code));
    Inc(I);
  end;
  if V.N < 0 then
    Exit;
  if (I >= ATo) or (FBuf[I] <> Q) then
    Exit;
  Inc(I);
  Result := True;
end;

function T3mfParser.FindAttr(AFrom, ATo: Integer; const AName: string; out V: TVal): Boolean;
var
  I, Ns, Nl, Colon: Integer;
begin
  Result := False;
  V.N := 0;
  I := AFrom;
  while I < ATo do
  begin
    while (I < ATo) and IsWs(FBuf[I]) do
      Inc(I);
    if I >= ATo then
      Exit;
    Ns := I;
    while (I < ATo) and not IsWs(FBuf[I]) and (FBuf[I] <> Ord('=')) do
      Inc(I);
    Nl := I - Ns;
    Colon := 0;
    while (Colon < Nl) and (FBuf[Ns + Colon] <> Ord(':')) do
      Inc(Colon);
    if Colon < Nl then
    begin
      Ns := Ns + Colon + 1;
      Nl := Nl - Colon - 1;
    end;
    while (I < ATo) and IsWs(FBuf[I]) do
      Inc(I);
    if (I >= ATo) or (FBuf[I] <> Ord('=')) then
      Continue;
    Inc(I);
    while (I < ATo) and IsWs(FBuf[I]) do
      Inc(I);
    if not ReadQuoted(I, ATo, V) then
      Exit;
    if EqI(Ns, Nl, AName) then
      Exit(True);
  end;
end;

procedure T3mfParser.ApplyXmlns(AFrom, ATo: Integer; var ADef: Boolean);
var
  I, Ns, Nl, Colon: Integer;
  V: TVal;
  Pref: string;
  P: Integer;
begin
  I := AFrom;
  while I < ATo do
  begin
    while (I < ATo) and IsWs(FBuf[I]) do
      Inc(I);
    if I >= ATo then
      Exit;
    Ns := I;
    while (I < ATo) and not IsWs(FBuf[I]) and (FBuf[I] <> Ord('=')) do
      Inc(I);
    Nl := I - Ns;
    while (I < ATo) and IsWs(FBuf[I]) do
      Inc(I);
    if (I >= ATo) or (FBuf[I] <> Ord('=')) then
      Continue;
    Inc(I);
    while (I < ATo) and IsWs(FBuf[I]) do
      Inc(I);
    if not ReadQuoted(I, ATo, V) then
      Exit;
    if EqI(Ns, Nl, 'xmlns') then
      ADef := UrlCore(V)
    else if (Nl > 6) and EqI(Ns, 6, 'xmlns:') then
    begin
      Colon := Ns + 6;
      Pref := '';
      for P := Colon to Ns + Nl - 1 do
      begin
        if FBuf[P] > 127 then
        begin
          Pref := '';
          Break;
        end;
        Pref := Pref + Char(FBuf[P]);
      end;
      if Pref <> '' then
      begin
        SetLength(FNs, Length(FNs) + 1);
        FNs[High(FNs)].Pref := Pref;
        FNs[High(FNs)].Core := UrlCore(V);
      end;
    end;
  end;
end;

function T3mfParser.ParseNum(const V: TVal; out N: Double): Boolean;
var
  I, Sign, ExpSign, Exp, Frac, Got: Integer;
  X: Double;
begin
  Result := False;
  N := 0;
  if (V.N < 1) or (V.N > 64) then
    Exit;
  I := 0;
  Sign := 1;
  if (V.B[I] = Ord('+')) or (V.B[I] = Ord('-')) then
  begin
    if V.B[I] = Ord('-') then
      Sign := -1;
    Inc(I);
  end;
  if I >= V.N then
    Exit;
  X := 0;
  Frac := 0;
  Got := 0;
  while (I < V.N) and (V.B[I] >= Ord('0')) and (V.B[I] <= Ord('9')) do
  begin
    X := X * 10 + (V.B[I] - Ord('0'));
    Inc(I);
    Got := 1;
  end;
  if (I < V.N) and (V.B[I] = Ord('.')) then
  begin
    Inc(I);
    while (I < V.N) and (V.B[I] >= Ord('0')) and (V.B[I] <= Ord('9')) do
    begin
      X := X * 10 + (V.B[I] - Ord('0'));
      Inc(Frac);
      Inc(I);
      Got := 1;
    end;
  end;
  if Got = 0 then
    Exit;
  while Frac > 0 do
  begin
    X := X / 10;
    Dec(Frac);
  end;
  if (I < V.N) and ((V.B[I] = Ord('e')) or (V.B[I] = Ord('E'))) then
  begin
    Inc(I);
    ExpSign := 1;
    if (I < V.N) and ((V.B[I] = Ord('+')) or (V.B[I] = Ord('-'))) then
    begin
      if V.B[I] = Ord('-') then
        ExpSign := -1;
      Inc(I);
    end;
    if (I >= V.N) or (V.B[I] < Ord('0')) or (V.B[I] > Ord('9')) then
      Exit;
    Exp := 0;
    while (I < V.N) and (V.B[I] >= Ord('0')) and (V.B[I] <= Ord('9')) do
    begin
      Exp := Exp * 10 + (V.B[I] - Ord('0'));
      if Exp > 99 then
        Exit;
      Inc(I);
    end;
    if ExpSign < 0 then
      while Exp > 0 do
      begin
        X := X / 10;
        Dec(Exp);
      end
    else
      while Exp > 0 do
      begin
        X := X * 10;
        Dec(Exp);
      end;
  end;
  if I <> V.N then
    Exit;
  if IsNan(X) or IsInfinite(X) then
    Exit;
  N := X * Sign;
  Result := True;
end;

function T3mfParser.ParseInt(const V: TVal; out N: Integer): Boolean;
var
  I, Sign: Integer;
  U: Int64;
begin
  Result := False;
  N := 0;
  if (V.N < 1) or (V.N > 12) then
    Exit;
  I := 0;
  Sign := 1;
  if (V.B[0] = Ord('+')) or (V.B[0] = Ord('-')) then
  begin
    if V.B[0] = Ord('-') then
      Sign := -1;
    I := 1;
  end;
  if I >= V.N then
    Exit;
  U := 0;
  while I < V.N do
  begin
    if (V.B[I] < Ord('0')) or (V.B[I] > Ord('9')) then
      Exit;
    U := U * 10 + (V.B[I] - Ord('0'));
    if U > High(Integer) then
      Exit;
    Inc(I);
  end;
  N := Integer(U) * Sign;
  Result := True;
end;

function T3mfParser.ParseColor(const V: TVal): Cardinal;
var
  Hex: string;
  I, Nib, R, G, B: Integer;
  C: Byte;

  function Nibble(Ch: Char; out D: Integer): Boolean;
  begin
    Result := True;
    if (Ch >= '0') and (Ch <= '9') then
      D := Ord(Ch) - Ord('0')
    else if (Ch >= 'a') and (Ch <= 'f') then
      D := Ord(Ch) - Ord('a') + 10
    else if (Ch >= 'A') and (Ch <= 'F') then
      D := Ord(Ch) - Ord('A') + 10
    else
      Result := False;
  end;

begin
  Result := 0;
  if (V.N < 7) or (V.B[0] <> Ord('#')) then
    Exit;
  if (V.N <> 7) and (V.N <> 9) then
    Exit;
  Hex := '';
  for I := 1 to V.N - 1 do
  begin
    C := V.B[I];
    if C > 127 then
      Exit;
    Hex := Hex + Char(C);
  end;
  if Length(Hex) = 8 then
    Hex := Copy(Hex, 3, 6);
  if Length(Hex) <> 6 then
    Exit;
  if not Nibble(Hex[1], Nib) then
    Exit;
  R := Nib shl 4;
  if not Nibble(Hex[2], Nib) then
    Exit;
  R := R or Nib;
  if not Nibble(Hex[3], Nib) then
    Exit;
  G := Nib shl 4;
  if not Nibble(Hex[4], Nib) then
    Exit;
  G := G or Nib;
  if not Nibble(Hex[5], Nib) then
    Exit;
  B := Nib shl 4;
  if not Nibble(Hex[6], Nib) then
    Exit;
  B := B or Nib;
  Result := $01000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

function T3mfParser.ParseXform(const V: TVal; out Xf: TAff): Boolean;
var
  I, N, Start: Integer;
  Part: TVal;
  Num: Double;
  Raw: array[0..11] of Double;
begin
  Result := False;
  Xf := AffId;
  N := 0;
  I := 0;
  while I < V.N do
  begin
    while (I < V.N) and IsWs(V.B[I]) do
      Inc(I);
    if I >= V.N then
      Break;
    Start := I;
    while (I < V.N) and not IsWs(V.B[I]) do
      Inc(I);
    if N > 11 then
      Exit;
    Part.N := I - Start;
    if (Part.N < 1) or (Part.N > 64) then
      Exit;
    Move(V.B[Start], Part.B[0], Part.N);
    if not ParseNum(Part, Num) then
      Exit;
    Raw[N] := Num;
    Inc(N);
  end;
  Result := N = 12;
  if not Result then
  begin
    Xf := AffId;
    Exit;
  end;
  { Спека 3MF: «m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32».
    Точка — рядок, x' = m00*x + m10*y + m20*z + m30.
    Emit множить стовпчик зліва, тож 3×3 зберігаємо транспонованою.
    Діагональний зсув на стіл від цього не змінюється. Поворот, яким
    Bambu кладе Y-up сітку на стіл, без транспонування ставив модель
    верх ногами. }
  Xf.M[0] := Raw[0];
  Xf.M[1] := Raw[3];
  Xf.M[2] := Raw[6];
  Xf.M[3] := Raw[1];
  Xf.M[4] := Raw[4];
  Xf.M[5] := Raw[7];
  Xf.M[6] := Raw[2];
  Xf.M[7] := Raw[5];
  Xf.M[8] := Raw[8];
  Xf.M[9] := Raw[9];
  Xf.M[10] := Raw[10];
  Xf.M[11] := Raw[11];
end;

function T3mfParser.ValText(const V: TVal): string;
var
  I: Integer;
  C: Byte;
begin
  Result := '';
  if V.N < 1 then
    Exit;
  for I := 0 to V.N - 1 do
  begin
    C := V.B[I];
    if C > 127 then
      Exit('');
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      Inc(C, 32);
    if C <= 32 then
      Continue;
    Result := Result + Char(C);
    if Length(Result) >= 32 then
      Break;
  end;
end;

function T3mfParser.PathText(const V: TVal): string;
var
  I: Integer;
  C: Byte;
begin
  Result := '';
  if V.N < 1 then
    Exit;
  for I := 0 to V.N - 1 do
  begin
    C := V.B[I];
    if C < 32 then
      Continue;
    if C > 127 then
      Exit('');
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      Inc(C, 32);
    Result := Result + Char(C);
  end;
end;

procedure T3mfParser.Push(AKind: TKind; ADef: Boolean; ANsMark: Integer);
var
  N: Integer;
begin
  N := Length(FStack);
  if N >= C3mfStack then
    AKind := ekSkip;
  SetLength(FStack, N + 1);
  FStack[N].Kind := AKind;
  FStack[N].DefCore := ADef;
  FStack[N].NsMark := ANsMark;
end;

procedure T3mfParser.Pop;
var
  K: TKind;
begin
  if Length(FStack) = 0 then
    Exit;
  K := FStack[High(FStack)].Kind;
  SetLength(FNs, FStack[High(FStack)].NsMark);
  SetLength(FStack, Length(FStack) - 1);
  if K = ekObject then
    FinishObject
  else if K = ekBases then
    FMatCur := -1;
end;

procedure T3mfParser.BeginObject(AFrom, ATo: Integer; out AModel: Boolean);
var
  V: TVal;
  Id, Pid, PIndex, N: Integer;
  Kind: string;
begin
  AModel := True;
  if FindAttr(AFrom, ATo, 'type', V) then
  begin
    Kind := ValText(V);
    AModel := (Kind = '') or (Kind = 'model');
  end;
  if not AModel then
    Exit;
  if FPass = 1 then
  begin
    N := Length(FPlan);
    SetLength(FPlan, N + 1);
    FPlan[N].VCount := 0;
    FPlan[N].TCount := 0;
    FPlan[N].StepV := 1;
    FPlan[N].StepT := 1;
    FCur := N;
    FLocalV := 0;
    FLocalT := 0;
    Exit;
  end;
  if FFill >= Length(FPlan) then
  begin
    AModel := False;
    Exit;
  end;
  N := Length(FObjs);
  SetLength(FObjs, N + 1);
  FObjs[N].Id := 0;
  FObjs[N].HasPid := False;
  FObjs[N].Pid := 0;
  FObjs[N].PIndex := 0;
  FObjs[N].StepV := FPlan[FFill].StepV;
  FObjs[N].StepT := FPlan[FFill].StepT;
  FObjs[N].VN := 0;
  FObjs[N].TN := 0;
  FObjs[N].CN := 0;
  if FindAttr(AFrom, ATo, 'id', V) and ParseInt(V, Id) then
    FObjs[N].Id := Id;
  if FindAttr(AFrom, ATo, 'pid', V) and ParseInt(V, Pid) then
  begin
    FObjs[N].HasPid := True;
    FObjs[N].Pid := Pid;
    FObjs[N].PIndex := 0;
    if FindAttr(AFrom, ATo, 'pindex', V) and ParseInt(V, PIndex) then
      FObjs[N].PIndex := PIndex;
  end;
  FCur := N;
  FLocalV := 0;
  FLocalT := 0;
  Inc(FFill);
end;

procedure T3mfParser.ReadVertex(AFrom, ATo: Integer);
var
  Vx, Vy, Vz: TVal;
  X, Y, Z: Double;
  Bad: Boolean;
  N, Slot: Integer;
begin
  if FCur < 0 then
    Exit;
  if FPass = 1 then
  begin
    if FPlan[FCur].VCount < MaxInt then
      Inc(FPlan[FCur].VCount);
    Exit;
  end;
  Slot := FLocalV;
  Inc(FLocalV);
  if (FObjs[FCur].StepV > 1) and ((Slot mod FObjs[FCur].StepV) <> 0) then
    Exit;
  Bad := not FindAttr(AFrom, ATo, 'x', Vx) or not ParseNum(Vx, X) or
    not FindAttr(AFrom, ATo, 'y', Vy) or not ParseNum(Vy, Y) or
    not FindAttr(AFrom, ATo, 'z', Vz) or not ParseNum(Vz, Z);
  if not Bad then
    Bad := IsNan(X) or IsNan(Y) or IsNan(Z) or IsInfinite(X) or IsInfinite(Y) or
      IsInfinite(Z) or (Abs(X) > 1E9) or (Abs(Y) > 1E9) or (Abs(Z) > 1E9);
  N := FObjs[FCur].VN;
  if N >= Length(FObjs[FCur].Verts) then
  begin
    SetLength(FObjs[FCur].Verts, GrowTo(Length(FObjs[FCur].Verts), N + 1));
    SetLength(FObjs[FCur].Bad, Length(FObjs[FCur].Verts));
  end;
  if Bad then
  begin
    FObjs[FCur].Verts[N].X := 0;
    FObjs[FCur].Verts[N].Y := 0;
    FObjs[FCur].Verts[N].Z := 0;
    FObjs[FCur].Bad[N] := 1;
  end
  else
  begin
    FObjs[FCur].Verts[N].X := X;
    FObjs[FCur].Verts[N].Y := Y;
    FObjs[FCur].Verts[N].Z := Z;
    FObjs[FCur].Bad[N] := 0;
  end;
  Inc(FObjs[FCur].VN);
end;

procedure T3mfParser.ReadTriangle(AFrom, ATo: Integer);
var
  Va, Vb, Vc, Vp, Vi: TVal;
  A, B, C, Pid, PIndex, N, Slot: Integer;
  Has: Boolean;
begin
  if FCur < 0 then
    Exit;
  if FPass = 1 then
  begin
    if FPlan[FCur].TCount < MaxInt then
      Inc(FPlan[FCur].TCount);
    Exit;
  end;
  Slot := FLocalT;
  Inc(FLocalT);
  if (FObjs[FCur].StepT > 1) and ((Slot mod FObjs[FCur].StepT) <> 0) then
    Exit;
  if not FindAttr(AFrom, ATo, 'v1', Va) or not ParseInt(Va, A) or
     not FindAttr(AFrom, ATo, 'v2', Vb) or not ParseInt(Vb, B) or
     not FindAttr(AFrom, ATo, 'v3', Vc) or not ParseInt(Vc, C) then
    Exit;
  if FObjs[FCur].StepV > 1 then
  begin
    if (A < 0) or (B < 0) or (C < 0) or
       ((A mod FObjs[FCur].StepV) <> 0) or ((B mod FObjs[FCur].StepV) <> 0) or
       ((C mod FObjs[FCur].StepV) <> 0) then
      Exit;
    A := A div FObjs[FCur].StepV;
    B := B div FObjs[FCur].StepV;
    C := C div FObjs[FCur].StepV;
  end;
  Has := FindAttr(AFrom, ATo, 'pid', Vp) and ParseInt(Vp, Pid);
  PIndex := 0;
  if Has and FindAttr(AFrom, ATo, 'pindex', Vi) then
    ParseInt(Vi, PIndex);
  N := FObjs[FCur].TN;
  if N >= Length(FObjs[FCur].Tris) then
    SetLength(FObjs[FCur].Tris, GrowTo(Length(FObjs[FCur].Tris), N + 1));
  FObjs[FCur].Tris[N].A := A;
  FObjs[FCur].Tris[N].B := B;
  FObjs[FCur].Tris[N].C := C;
  FObjs[FCur].Tris[N].HasPid := Has;
  if Has then
    FObjs[FCur].Tris[N].Pid := Pid
  else
    FObjs[FCur].Tris[N].Pid := 0;
  FObjs[FCur].Tris[N].PIndex := PIndex;
  FObjs[FCur].Tris[N].Col := 0;
  Inc(FObjs[FCur].TN);
end;

procedure T3mfParser.ReadComponent(AFrom, ATo: Integer);
var
  V: TVal;
  Id, N: Integer;
  Xf: TAff;
  Part: string;
begin
  if (FPass <> 2) or (FCur < 0) then
    Exit;
  if not FindAttr(AFrom, ATo, 'objectid', V) or not ParseInt(V, Id) then
    Exit;
  Part := '';
  if FindAttr(AFrom, ATo, 'path', V) then
    Part := ModelPartName(PathText(V));
  Xf := AffId;
  if FindAttr(AFrom, ATo, 'transform', V) then
    if not ParseXform(V, Xf) then
      Xf := AffId;
  N := FObjs[FCur].CN;
  if N >= Length(FObjs[FCur].Comps) then
    SetLength(FObjs[FCur].Comps, GrowTo(Length(FObjs[FCur].Comps), N + 1));
  FObjs[FCur].Comps[N].Id := Id;
  FObjs[FCur].Comps[N].Xf := Xf;
  FObjs[FCur].Comps[N].Path := Part;
  Inc(FObjs[FCur].CN);
end;

procedure T3mfParser.ReadItem(AFrom, ATo: Integer);
var
  V: TVal;
  Id, N: Integer;
  Xf: TAff;
begin
  if FPass <> 2 then
    Exit;
  if not FindAttr(AFrom, ATo, 'objectid', V) or not ParseInt(V, Id) then
    Exit;
  Xf := AffId;
  if FindAttr(AFrom, ATo, 'transform', V) then
    if not ParseXform(V, Xf) then
      Xf := AffId;
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N].Id := Id;
  FItems[N].Xf := Xf;
end;

procedure T3mfParser.BeginMats(AFrom, ATo: Integer);
var
  V: TVal;
  Id, N: Integer;
begin
  if FPass <> 2 then
    Exit;
  N := Length(FMats);
  SetLength(FMats, N + 1);
  FMats[N].Id := 0;
  FMats[N].N := 0;
  if FindAttr(AFrom, ATo, 'id', V) and ParseInt(V, Id) then
    FMats[N].Id := Id;
  FMatCur := N;
end;

procedure T3mfParser.ReadBase(AFrom, ATo: Integer);
var
  V: TVal;
  Col: Cardinal;
  N: Integer;
begin
  if (FPass <> 2) or (FMatCur < 0) then
    Exit;
  Col := 0;
  if FindAttr(AFrom, ATo, 'displaycolor', V) then
    Col := ParseColor(V);
  if not FHaveFirst then
  begin
    FFirstCol := Col;
    FHaveFirst := True;
  end;
  N := FMats[FMatCur].N;
  if N >= Length(FMats[FMatCur].Cols) then
    SetLength(FMats[FMatCur].Cols, GrowTo(Length(FMats[FMatCur].Cols), N + 1));
  FMats[FMatCur].Cols[N] := Col;
  Inc(FMats[FMatCur].N);
end;

procedure T3mfParser.FinishObject;
var
  I, W, NA, NB, NC: Integer;
  Map: TArray<Integer>;
  Any: Boolean;
begin
  if (FPass <> 2) or (FCur < 0) or (FCur > High(FObjs)) then
  begin
    FCur := -1;
    Exit;
  end;
  Any := False;
  for I := 0 to FObjs[FCur].VN - 1 do
    if (I < Length(FObjs[FCur].Bad)) and (FObjs[FCur].Bad[I] <> 0) then
      Any := True;
  if Any then
  begin
    SetLength(Map, FObjs[FCur].VN);
    W := 0;
    for I := 0 to FObjs[FCur].VN - 1 do
      if (I < Length(FObjs[FCur].Bad)) and (FObjs[FCur].Bad[I] <> 0) then
        Map[I] := -1
      else
      begin
        Map[I] := W;
        FObjs[FCur].Verts[W] := FObjs[FCur].Verts[I];
        Inc(W);
      end;
    FObjs[FCur].VN := W;
    W := 0;
    for I := 0 to FObjs[FCur].TN - 1 do
    begin
      NA := FObjs[FCur].Tris[I].A;
      NB := FObjs[FCur].Tris[I].B;
      NC := FObjs[FCur].Tris[I].C;
      if (NA < 0) or (NB < 0) or (NC < 0) or (NA > High(Map)) or
         (NB > High(Map)) or (NC > High(Map)) then
        Continue;
      if (Map[NA] < 0) or (Map[NB] < 0) or (Map[NC] < 0) then
        Continue;
      FObjs[FCur].Tris[W] := FObjs[FCur].Tris[I];
      FObjs[FCur].Tris[W].A := Map[NA];
      FObjs[FCur].Tris[W].B := Map[NB];
      FObjs[FCur].Tris[W].C := Map[NC];
      Inc(W);
    end;
    FObjs[FCur].TN := W;
  end;
  SetLength(FObjs[FCur].Verts, FObjs[FCur].VN);
  SetLength(FObjs[FCur].Tris, FObjs[FCur].TN);
  SetLength(FObjs[FCur].Bad, 0);
  SetLength(FObjs[FCur].Comps, FObjs[FCur].CN);
  FCur := -1;
end;

procedure T3mfParser.Scan;
var
  I, NamePos, NameLen, Colon, LocalPos, LocalLen, AttrPos, AttrEnd, NsMark: Integer;
  Empty, Core: Boolean;
  DefCore: Boolean;
  Pref: string;
  P, K: Integer;
  ModelObj: Boolean;
  V: TVal;
begin
  I := 0;
  if (FLen >= 3) and (FBuf[0] = $EF) and (FBuf[1] = $BB) and (FBuf[2] = $BF) then
    I := 3;
  while I < FLen do
  begin
    if (I and $3FFFF) = 0 then
      if Halted then
        Exit;
    if FBuf[I] <> Ord('<') then
    begin
      Inc(I);
      Continue;
    end;
    Inc(I);
    if I >= FLen then
      Exit;
    if FBuf[I] = Ord('?') then
    begin
      Inc(I);
      while I + 1 < FLen do
      begin
        if (FBuf[I] = Ord('?')) and (FBuf[I + 1] = Ord('>')) then
        begin
          Inc(I, 2);
          Break;
        end;
        Inc(I);
      end;
      Continue;
    end;
    if FBuf[I] = Ord('!') then
    begin
      if (I + 2 < FLen) and (FBuf[I + 1] = Ord('-')) and (FBuf[I + 2] = Ord('-')) then
      begin
        Inc(I, 3);
        while I + 2 < FLen do
        begin
          if (FBuf[I] = Ord('-')) and (FBuf[I + 1] = Ord('-')) and (FBuf[I + 2] = Ord('>')) then
          begin
            Inc(I, 3);
            Break;
          end;
          Inc(I);
        end;
      end
      else if (I + 7 < FLen) and EqI(I + 1, 7, '[CDATA[') then
      begin
        Inc(I, 8);
        while I + 2 < FLen do
        begin
          if (FBuf[I] = Ord(']')) and (FBuf[I + 1] = Ord(']')) and (FBuf[I + 2] = Ord('>')) then
          begin
            Inc(I, 3);
            Break;
          end;
          Inc(I);
        end;
      end
      else
      begin
        while (I < FLen) and (FBuf[I] <> Ord('>')) do
          Inc(I);
        if I < FLen then
          Inc(I);
      end;
      Continue;
    end;
    if FBuf[I] = Ord('/') then
    begin
      while (I < FLen) and (FBuf[I] <> Ord('>')) do
        Inc(I);
      if I < FLen then
        Inc(I);
      Pop;
      Continue;
    end;
    NamePos := I;
    while (I < FLen) and not IsWs(FBuf[I]) and (FBuf[I] <> Ord('/')) and
          (FBuf[I] <> Ord('>')) do
      Inc(I);
    NameLen := I - NamePos;
    AttrPos := I;
    Empty := False;
    AttrEnd := I;
    while I < FLen do
    begin
      if FBuf[I] = Ord('"') then
      begin
        Inc(I);
        while (I < FLen) and (FBuf[I] <> Ord('"')) do
          Inc(I);
        if I < FLen then
          Inc(I);
      end
      else if FBuf[I] = Ord('''') then
      begin
        Inc(I);
        while (I < FLen) and (FBuf[I] <> Ord('''')) do
          Inc(I);
        if I < FLen then
          Inc(I);
      end
      else if FBuf[I] = Ord('>') then
      begin
        K := I - 1;
        while (K >= AttrPos) and IsWs(FBuf[K]) do
          Dec(K);
        if (K >= AttrPos) and (FBuf[K] = Ord('/')) then
        begin
          Empty := True;
          AttrEnd := K;
        end
        else
          AttrEnd := I;
        Inc(I);
        Break;
      end
      else
        Inc(I);
    end;
    Colon := 0;
    while (Colon < NameLen) and (FBuf[NamePos + Colon] <> Ord(':')) do
      Inc(Colon);
    if Colon < NameLen then
    begin
      LocalPos := NamePos + Colon + 1;
      LocalLen := NameLen - Colon - 1;
      Pref := '';
      for P := NamePos to NamePos + Colon - 1 do
      begin
        if FBuf[P] > 127 then
        begin
          Pref := #1;
          Break;
        end;
        Pref := Pref + Char(FBuf[P]);
      end;
    end
    else
    begin
      LocalPos := NamePos;
      LocalLen := NameLen;
      Pref := '';
    end;
    NsMark := Length(FNs);
    DefCore := ParentDef;
    ApplyXmlns(AttrPos, AttrEnd, DefCore);
    if Pref = '' then
      Core := DefCore
    else if Pref = #1 then
      Core := False
    else
    begin
      Core := False;
      for P := High(FNs) downto 0 do
        if FNs[P].Pref = Pref then
        begin
          Core := FNs[P].Core;
          Break;
        end;
    end;
    if not Core then
    begin
      if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if EqI(LocalPos, LocalLen, 'model') and
       ((Length(FStack) = 0) or (ParentKind = ekSkip)) and (Length(FStack) < 2) then
    begin
      FSawModel := True;
      if FUnit = '' then
      begin
        if FindAttr(AttrPos, AttrEnd, 'unit', V) then
          FUnit := ValText(V);
        if FUnit = '' then
          FUnit := 'millimeter';
      end;
      if not Empty then
        Push(ekModel, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekModel) and EqI(LocalPos, LocalLen, 'resources') then
    begin
      if not Empty then
        Push(ekResources, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekModel) and EqI(LocalPos, LocalLen, 'build') then
    begin
      if not Empty then
        Push(ekBuild, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekResources) and EqI(LocalPos, LocalLen, 'basematerials') then
    begin
      BeginMats(AttrPos, AttrEnd);
      if not Empty then
        Push(ekBases, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekResources) and EqI(LocalPos, LocalLen, 'object') then
    begin
      BeginObject(AttrPos, AttrEnd, ModelObj);
      if ModelObj then
      begin
        if not Empty then
          Push(ekObject, DefCore, NsMark)
        else
          FinishObject;
      end
      else if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekObject) and EqI(LocalPos, LocalLen, 'mesh') then
    begin
      if not Empty then
        Push(ekMesh, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekObject) and EqI(LocalPos, LocalLen, 'components') then
    begin
      if not Empty then
        Push(ekComps, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekMesh) and EqI(LocalPos, LocalLen, 'vertices') then
    begin
      if not Empty then
        Push(ekVerts, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekMesh) and EqI(LocalPos, LocalLen, 'triangles') then
    begin
      if not Empty then
        Push(ekTris, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekVerts) and EqI(LocalPos, LocalLen, 'vertex') then
    begin
      ReadVertex(AttrPos, AttrEnd);
      if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekTris) and EqI(LocalPos, LocalLen, 'triangle') then
    begin
      ReadTriangle(AttrPos, AttrEnd);
      if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekComps) and EqI(LocalPos, LocalLen, 'component') then
    begin
      ReadComponent(AttrPos, AttrEnd);
      if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekBuild) and EqI(LocalPos, LocalLen, 'item') then
    begin
      ReadItem(AttrPos, AttrEnd);
      if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if (ParentKind = ekBases) and EqI(LocalPos, LocalLen, 'base') then
    begin
      ReadBase(AttrPos, AttrEnd);
      if not Empty then
        Push(ekSkip, DefCore, NsMark);
      Continue;
    end;
    if not Empty then
      Push(ekSkip, DefCore, NsMark);
  end;
end;

function T3mfParser.TryCol(APid, APIndex: Integer; out ACol: Cardinal): Boolean;
var
  I: Integer;
begin
  Result := False;
  ACol := 0;
  for I := 0 to High(FMats) do
    if FMats[I].Id = APid then
    begin
      if (APIndex >= 0) and (APIndex < FMats[I].N) then
      begin
        ACol := FMats[I].Cols[APIndex];
        Result := True;
      end;
      Exit;
    end;
end;

procedure T3mfParser.ResolveColors;
var
  O, T: Integer;
  Col: Cardinal;
  Got: Boolean;
begin
  for O := 0 to High(FObjs) do
    for T := 0 to FObjs[O].TN - 1 do
    begin
      if FObjs[O].Tris[T].Keep then
        Continue;
      Got := False;
      Col := 0;
      if FObjs[O].Tris[T].HasPid then
        Got := TryCol(FObjs[O].Tris[T].Pid, FObjs[O].Tris[T].PIndex, Col);
      if not Got and FObjs[O].HasPid then
        Got := TryCol(FObjs[O].Pid, FObjs[O].PIndex, Col);
      if not Got and FHaveFirst then
      begin
        Col := FFirstCol;
        Got := True;
      end;
      if not Got then
        Col := 0;
      FObjs[O].Tris[T].Col := Col;
    end;
end;

function T3mfParser.IndexOfId(AId: Integer): Integer;
begin
  if (FMap <> nil) and FMap.TryGetValue(AId, Result) then
    Exit;
  Result := -1;
end;

function T3mfParser.Busy(AIndex: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to FSeenN - 1 do
    if FSeen[I] = AIndex then
      Exit(True);
  Result := False;
end;

function T3mfParser.CountEmit(AIndex: Integer; ADepth: Integer): Int64;
var
  K, Child: Integer;
begin
  Result := 0;
  if FCancelled or (AIndex < 0) or (AIndex > High(FObjs)) or (ADepth > C3mfDepth) then
    Exit;
  if Busy(AIndex) then
    Exit;
  if FSeenN >= Length(FSeen) then
    SetLength(FSeen, GrowTo(Length(FSeen), FSeenN + 1));
  FSeen[FSeenN] := AIndex;
  Inc(FSeenN);
  Result := FObjs[AIndex].TN;
  for K := 0 to FObjs[AIndex].CN - 1 do
  begin
    if FObjs[AIndex].Comps[K].Path <> '' then
      Continue;
    Child := IndexOfId(FObjs[AIndex].Comps[K].Id);
    Result := Result + CountEmit(Child, ADepth + 1);
  end;
  Dec(FSeenN);
end;

procedure T3mfParser.EmitOne(AIndex: Integer; const AXf: TAff; ADepth: Integer;
  AStep: Integer);
var
  I, K, Base, Child: Integer;
  X, Y, Z: Double;
begin
  if FCancelled or FIncomplete or (AIndex < 0) or (AIndex > High(FObjs)) or
     (ADepth > C3mfDepth) then
    Exit;
  if Busy(AIndex) then
    Exit;
  if Halted then
    Exit;
  if FSeenN >= Length(FSeen) then
    SetLength(FSeen, GrowTo(Length(FSeen), FSeenN + 1));
  FSeen[FSeenN] := AIndex;
  Inc(FSeenN);
  Base := FOutVN;
  for I := 0 to FObjs[AIndex].VN - 1 do
  begin
    if (I and 4095) = 0 then
      if Halted then
      begin
        Dec(FSeenN);
        Exit;
      end;
    X := AXf.M[0] * FObjs[AIndex].Verts[I].X + AXf.M[1] * FObjs[AIndex].Verts[I].Y +
      AXf.M[2] * FObjs[AIndex].Verts[I].Z + AXf.M[9];
    Y := AXf.M[3] * FObjs[AIndex].Verts[I].X + AXf.M[4] * FObjs[AIndex].Verts[I].Y +
      AXf.M[5] * FObjs[AIndex].Verts[I].Z + AXf.M[10];
    Z := AXf.M[6] * FObjs[AIndex].Verts[I].X + AXf.M[7] * FObjs[AIndex].Verts[I].Y +
      AXf.M[8] * FObjs[AIndex].Verts[I].Z + AXf.M[11];
    if IsNan(X) or IsNan(Y) or IsNan(Z) or IsInfinite(X) or IsInfinite(Y) or
       IsInfinite(Z) then
    begin
      X := 0;
      Y := 0;
      Z := 0;
    end;
    if FOutVN >= Length(FOutV) then
      SetLength(FOutV, GrowTo(Length(FOutV), FOutVN + 1));
    FOutV[FOutVN].X := X;
    FOutV[FOutVN].Y := Y;
    FOutV[FOutVN].Z := Z;
    Inc(FOutVN);
  end;
  if AStep < 1 then
    AStep := 1;
  for I := 0 to FObjs[AIndex].TN - 1 do
  begin
    if (I and 4095) = 0 then
      if Halted then
      begin
        Dec(FSeenN);
        Exit;
      end;
    { Крок усередині об'єкта: I = 0 лишається, тож пізній об'єкт не зникає. }
    if (AStep > 1) and ((I mod AStep) <> 0) then
      Continue;
    if (FObjs[AIndex].Tris[I].A < 0) or (FObjs[AIndex].Tris[I].B < 0) or
       (FObjs[AIndex].Tris[I].C < 0) or
       (FObjs[AIndex].Tris[I].A >= FObjs[AIndex].VN) or
       (FObjs[AIndex].Tris[I].B >= FObjs[AIndex].VN) or
       (FObjs[AIndex].Tris[I].C >= FObjs[AIndex].VN) then
      Continue;
    if FOutTN >= FMaxTris then
    begin
      FSimplified := True;
      Break;
    end;
    if FOutTN >= Length(FOutT) then
      SetLength(FOutT, GrowTo(Length(FOutT), FOutTN + 1));
    FOutT[FOutTN].A := Base + FObjs[AIndex].Tris[I].A;
    FOutT[FOutTN].B := Base + FObjs[AIndex].Tris[I].B;
    FOutT[FOutTN].C := Base + FObjs[AIndex].Tris[I].C;
    FOutT[FOutTN].Col := FObjs[AIndex].Tris[I].Col;
    Inc(FOutTN);
  end;
  for K := 0 to FObjs[AIndex].CN - 1 do
  begin
    if FObjs[AIndex].Comps[K].Path <> '' then
      Continue;
    Child := IndexOfId(FObjs[AIndex].Comps[K].Id);
    EmitOne(Child, MulAff(AXf, FObjs[AIndex].Comps[K].Xf), ADepth + 1, AStep);
  end;
  Dec(FSeenN);
end;

procedure T3mfParser.Emit(var AModel: T3mfModel);
var
  I, Child, Roots, Resolved: Integer;
  Used: TDictionary<Integer, Byte>;
  Total: Int64;
  Step: Integer;
  Idn: TAff;
  Partial: Boolean;
begin
  { Годинник розбору вже міг вичерпатись на великій частині. Сітку, яку встигли
    прочитати, все одно віддаємо. Новий відлік — тільки на збірку сцени. }
  Partial := FIncomplete;
  FIncomplete := False;
  FClock := TStopwatch.StartNew;
  ResolveColors;
  FreeAndNil(FMap);
  FMap := TDictionary<Integer, Integer>.Create;
  for I := 0 to High(FObjs) do
    if not FMap.ContainsKey(FObjs[I].Id) then
      FMap.Add(FObjs[I].Id, I);
  Idn := AffId;
  FSeenN := 0;
  Total := 0;
  Resolved := 0;
  if Length(FItems) > 0 then
  begin
    for I := 0 to High(FItems) do
      if IndexOfId(FItems[I].Id) >= 0 then
      begin
        Inc(Resolved);
        FSeenN := 0;
        Total := Total + CountEmit(IndexOfId(FItems[I].Id), 0);
      end;
  end;
  if Resolved = 0 then
  begin
    Used := TDictionary<Integer, Byte>.Create;
    try
      for I := 0 to High(FObjs) do
        for Child := 0 to FObjs[I].CN - 1 do
          if FObjs[I].Comps[Child].Path = '' then
            Used.AddOrSetValue(FObjs[I].Comps[Child].Id, 1);
      Roots := 0;
      for I := 0 to High(FObjs) do
        if not Used.ContainsKey(FObjs[I].Id) then
          Inc(Roots);
      if Roots = 0 then
      begin
        for I := 0 to High(FObjs) do
        begin
          FSeenN := 0;
          Total := Total + CountEmit(I, 0);
        end;
      end
      else
        for I := 0 to High(FObjs) do
          if not Used.ContainsKey(FObjs[I].Id) then
          begin
            FSeenN := 0;
            Total := Total + CountEmit(I, 0);
          end;
    finally
      Used.Free;
    end;
    AModel.Objects := Length(FObjs);
  end
  else
    AModel.Objects := Resolved;
  if Total < 1 then
    Step := 1
  else if Total > FMaxTris then
  begin
    Step := Integer((Total + FMaxTris - 1) div FMaxTris);
    FSimplified := True;
  end
  else
    Step := 1;
  if Step < 1 then
    Step := 1;
  FOutVN := 0;
  FOutTN := 0;
  FSeenN := 0;
  if Resolved > 0 then
  begin
    for I := 0 to High(FItems) do
      if IndexOfId(FItems[I].Id) >= 0 then
        EmitOne(IndexOfId(FItems[I].Id), FItems[I].Xf, 0, Step);
  end
  else
  begin
    Used := TDictionary<Integer, Byte>.Create;
    try
      for I := 0 to High(FObjs) do
        for Child := 0 to FObjs[I].CN - 1 do
          if FObjs[I].Comps[Child].Path = '' then
            Used.AddOrSetValue(FObjs[I].Comps[Child].Id, 1);
      Roots := 0;
      for I := 0 to High(FObjs) do
        if not Used.ContainsKey(FObjs[I].Id) then
          Inc(Roots);
      if Roots = 0 then
      begin
        for I := 0 to High(FObjs) do
          EmitOne(I, Idn, 0, Step);
      end
      else
        for I := 0 to High(FObjs) do
          if not Used.ContainsKey(FObjs[I].Id) then
            EmitOne(I, Idn, 0, Step);
    finally
      Used.Free;
    end;
  end;
  SetLength(FOutV, FOutVN);
  SetLength(FOutT, FOutTN);
  AModel.Verts := FOutV;
  AModel.Tris := FOutT;
  AModel.Simplified := FSimplified;
  AModel.Incomplete := FIncomplete or Partial;
  AModel.Cancelled := FCancelled;
  if FUnit = '' then
    AModel.UnitName := 'millimeter'
  else
    AModel.UnitName := FUnit;
end;

function T3mfParser.PartSlot(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FParts) do
    if FParts[I].Name = APath then
      Exit(I);
  Result := -1;
end;

function T3mfParser.PartPaths: TArray<string>;
var
  I, K, N: Integer;
  Seen: TDictionary<string, Byte>;
  P: string;
begin
  Seen := TDictionary<string, Byte>.Create;
  try
    N := 0;
    SetLength(Result, 0);
    for I := 0 to High(FObjs) do
      for K := 0 to FObjs[I].CN - 1 do
      begin
        P := FObjs[I].Comps[K].Path;
        if (P = '') or Seen.ContainsKey(P) then
          Continue;
        Seen.Add(P, 1);
        if N >= Length(Result) then
          SetLength(Result, GrowTo(Length(Result), N + 1));
        Result[N] := P;
        Inc(N);
      end;
    SetLength(Result, N);
  finally
    Seen.Free;
  end;
end;

procedure T3mfParser.Relink(const APath: string;
  const AIds: TDictionary<Integer, Integer>);
var
  I, K, NewId: Integer;
begin
  for I := 0 to High(FObjs) do
    for K := 0 to FObjs[I].CN - 1 do
      if FObjs[I].Comps[K].Path = APath then
      begin
        if (AIds <> nil) and AIds.TryGetValue(FObjs[I].Comps[K].Id, NewId) then
          FObjs[I].Comps[K].Id := NewId
        else
          FObjs[I].Comps[K].Id := -1;
        FObjs[I].Comps[K].Path := '';
      end;
end;

procedure T3mfParser.IngestPart(const APath: string; var AXml: TBytes);
var
  Child: T3mfParser;
  IdMap: TDictionary<Integer, Integer>;
  I, K, N, T, MaxId, NewId, Base, Mapped, Slot: Integer;

  procedure AddComp(AObj: Integer; AId: Integer; const AXf: TAff; const APart: string);
  var
    C: Integer;
  begin
    C := FObjs[AObj].CN;
    if C >= Length(FObjs[AObj].Comps) then
      SetLength(FObjs[AObj].Comps, GrowTo(Length(FObjs[AObj].Comps), C + 1));
    FObjs[AObj].Comps[C].Id := AId;
    FObjs[AObj].Comps[C].Xf := AXf;
    FObjs[AObj].Comps[C].Path := APart;
    Inc(FObjs[AObj].CN);
  end;

begin
  if APath = '' then
    Exit;
  Slot := PartSlot(APath);
  if Slot >= 0 then
  begin
    Relink(APath, FParts[Slot].Ids);
    Exit;
  end;
  if Length(AXml) = 0 then
  begin
    Relink(APath, nil);
    Exit;
  end;
  Child := T3mfParser.Create;
  IdMap := nil;
  try
    try
      Child.Parse(AXml, FMaxTris, FMaxVerts, FMaxMs, FCancel);
      Child.FBuf := nil;
      SetLength(AXml, 0);
      if Child.FCancelled then
      begin
        FCancelled := True;
        Relink(APath, nil);
        Exit;
      end;
      if not Child.FSawModel then
      begin
        Relink(APath, nil);
        Exit;
      end;
      if Child.FIncomplete then
        FIncomplete := True;
      if Child.FSimplified then
        FSimplified := True;
      Child.ResolveColors;
      MaxId := 0;
      for I := 0 to High(FObjs) do
        if FObjs[I].Id > MaxId then
          MaxId := FObjs[I].Id;
      NewId := MaxId;
      Base := Length(FObjs);
      IdMap := TDictionary<Integer, Integer>.Create;
      for I := 0 to High(Child.FObjs) do
      begin
        Inc(NewId);
        N := Length(FObjs);
        SetLength(FObjs, N + 1);
        FObjs[N].Id := NewId;
        FObjs[N].HasPid := False;
        FObjs[N].Pid := 0;
        FObjs[N].PIndex := 0;
        FObjs[N].StepV := 1;
        FObjs[N].StepT := 1;
        FObjs[N].VN := Child.FObjs[I].VN;
        FObjs[N].TN := Child.FObjs[I].TN;
        FObjs[N].CN := 0;
        SetLength(FObjs[N].Verts, FObjs[N].VN);
        if FObjs[N].VN > 0 then
          Move(Child.FObjs[I].Verts[0], FObjs[N].Verts[0],
            FObjs[N].VN * SizeOf(T3mfVert));
        SetLength(FObjs[N].Tris, FObjs[N].TN);
        for T := 0 to FObjs[N].TN - 1 do
        begin
          FObjs[N].Tris[T] := Child.FObjs[I].Tris[T];
          FObjs[N].Tris[T].Keep := True;
          FObjs[N].Tris[T].HasPid := False;
        end;
        if not IdMap.ContainsKey(Child.FObjs[I].Id) then
          IdMap.Add(Child.FObjs[I].Id, NewId);
      end;
      for I := 0 to High(Child.FObjs) do
        for K := 0 to Child.FObjs[I].CN - 1 do
          if Child.FObjs[I].Comps[K].Path = '' then
          begin
            if IdMap.TryGetValue(Child.FObjs[I].Comps[K].Id, Mapped) then
              AddComp(Base + I, Mapped, Child.FObjs[I].Comps[K].Xf, '');
          end
          else
            AddComp(Base + I, Child.FObjs[I].Comps[K].Id,
              Child.FObjs[I].Comps[K].Xf, Child.FObjs[I].Comps[K].Path);
      N := Length(FParts);
      SetLength(FParts, N + 1);
      FParts[N].Name := APath;
      FParts[N].Ids := IdMap;
      IdMap := nil;
      Relink(APath, FParts[N].Ids);
    except
      Relink(APath, nil);
      raise;
    end;
  finally
    IdMap.Free;
    Child.Free;
  end;
end;

procedure T3mfParser.Parse(const AXml: TBytes; AMaxTris, AMaxVerts: Integer;
  AMaxMs: Cardinal; const ACancel: T3mfCancel);
var
  N, ShareV, ShareT: Integer;
begin
  FBuf := AXml;
  FLen := Length(AXml);
  FMaxTris := AMaxTris;
  FMaxVerts := AMaxVerts;
  if FMaxTris < 1 then
    FMaxTris := 1;
  if FMaxVerts < 3 then
    FMaxVerts := 3;
  FMaxMs := AMaxMs;
  FCancel := ACancel;
  FCur := -1;
  FFill := 0;
  FMatCur := -1;
  FSawModel := False;
  FUnit := '';
  FHaveFirst := False;
  FFirstCol := 0;
  FCancelled := False;
  FIncomplete := False;
  FSimplified := False;
  FPass := 1;
  SetLength(FStack, 0);
  SetLength(FNs, 0);
  SetLength(FPlan, 0);
  Scan;
  if FCancelled then
  begin
    FBuf := nil;
    Exit;
  end;
  while Length(FStack) > 0 do
    Pop;
  N := Length(FPlan);
  if N < 1 then
    N := 1;
  ShareV := FMaxVerts div N;
  if ShareV < 3 then
    ShareV := 3;
  ShareT := FMaxTris div N;
  if ShareT < 1 then
    ShareT := 1;
  for N := 0 to High(FPlan) do
  begin
    if FPlan[N].VCount > ShareV then
    begin
      FPlan[N].StepV := (FPlan[N].VCount + ShareV - 1) div ShareV;
      FSimplified := True;
    end
    else
      FPlan[N].StepV := 1;
    if FPlan[N].TCount > ShareT then
    begin
      FPlan[N].StepT := (FPlan[N].TCount + ShareT - 1) div ShareT;
      FSimplified := True;
    end
    else
      FPlan[N].StepT := 1;
    if FPlan[N].StepV < 1 then
      FPlan[N].StepV := 1;
    if FPlan[N].StepT < 1 then
      FPlan[N].StepT := 1;
  end;
  FPass := 2;
  FClock := TStopwatch.StartNew;
  SetLength(FStack, 0);
  SetLength(FNs, 0);
  FCur := -1;
  FFill := 0;
  FMatCur := -1;
  Scan;
  if FCur >= 0 then
    FinishObject;
  while Length(FStack) > 0 do
    Pop;
  FBuf := nil;
end;

procedure T3mfParser.Build(var AModel: T3mfModel);
begin
  AModel.Cancelled := FCancelled;
  AModel.Incomplete := FIncomplete;
  AModel.Simplified := FSimplified;
  if FCancelled then
    Exit;
  if not FSawModel then
  begin
    AModel.Status := st3Bad;
    Exit;
  end;
  if FPartTooBig then
  begin
    AModel.Status := st3TooBig;
    if FUnit = '' then
      AModel.UnitName := 'millimeter'
    else
      AModel.UnitName := FUnit;
    Exit;
  end;
  if FUnit = '' then
    AModel.UnitName := 'millimeter'
  else
    AModel.UnitName := FUnit;
  if Length(FObjs) = 0 then
  begin
    AModel.Status := st3Empty;
    AModel.Objects := 0;
    Exit;
  end;
  Emit(AModel);
  if FCancelled then
  begin
    AModel.Cancelled := True;
    Exit;
  end;
  if (FOutTN = 0) and (FOutVN = 0) then
    AModel.Status := st3Empty
  else
    AModel.Status := st3Ok;
end;

function Read3mf(const APath: string; ALoadMesh: Boolean; AMaxTris, AMaxVerts: Integer;
  AMaxMs: Cardinal; const ACancel: T3mfCancel): T3mfModel;
var
  Zip: TZipFile;
  Names: TDictionary<string, Integer>;
  Parser: T3mfParser;
  I, ModelI, PartI, Guard, P: Integer;
  Name, RootName, ThumbName, Key: string;
  Sz, BestSize: UInt64;
  Xml, PartXml, Rels, Empty: TBytes;
  Paths: TArray<string>;
  BestScore, Score, BestI, LooseN: Integer;
  LooseName: string;

  function IndexOfName(const N: string): Integer;
  begin
    if (N <> '') and Names.TryGetValue(N, Result) then
      Exit;
    Result := -1;
  end;

  function ResolveEntry(const Want: string): Integer;
  var
    Fn, N: string;
    Hit, C, Cut: Integer;
  begin
    Result := IndexOfName(Want);
    if Result >= 0 then
      Exit;
    if (Want <> '') and (Pos('/', Want) = 0) then
    begin
      Result := IndexOfName('3d/' + Want);
      if Result >= 0 then
        Exit;
      Result := IndexOfName('3d/objects/' + Want);
      if Result >= 0 then
        Exit;
    end;
    Fn := Want;
    Cut := LastDelimiter('/', Fn);
    if Cut > 0 then
      Fn := Copy(Fn, Cut + 1, MaxInt);
    if (Fn = '') or (Pos('.', Fn) = 0) then
      Exit(-1);
    Hit := -1;
    C := 0;
    for N in Names.Keys do
      if (N = Fn) or ((Length(N) > Length(Fn)) and
         (Copy(N, Length(N) - Length(Fn), Length(Fn) + 1) = '/' + Fn)) then
      begin
        Inc(C);
        Hit := Names[N];
      end;
    if C = 1 then
      Result := Hit
    else
      Result := -1;
  end;

  procedure KeepImage(AIndex: Integer);
  var
    Bytes: TBytes;
    Size: UInt64;
  begin
    if Result.HasThumb or (AIndex < 0) then
      Exit;
    Size := Zip.FileInfo[AIndex].UncompressedSize64;
    if (Size = 0) or (Size > C3mfThumbMax) then
      Exit;
    try
      Zip.Read(AIndex, Bytes);
    except
      Exit;
    end;
    if IsImage(Bytes) then
    begin
      Result.Thumb := Bytes;
      Result.HasThumb := True;
    end;
  end;

  procedure LoadSmall(const AName: string; var AOut: TBytes);
  var
    Ix: Integer;
    Size: UInt64;
  begin
    SetLength(AOut, 0);
    Ix := IndexOfName(AName);
    if Ix < 0 then
      Exit;
    Size := Zip.FileInfo[Ix].UncompressedSize64;
    if (Size = 0) or (Size > 1024 * 1024) then
      Exit;
    try
      Zip.Read(Ix, AOut);
    except
      SetLength(AOut, 0);
    end;
  end;

  function ImageScore(const N: string): Integer;
  var
    E: string;
  begin
    Result := 0;
    E := NameExt(N);
    if (E <> '.png') and (E <> '.jpg') and (E <> '.jpeg') then
      Exit;
    if (Pos('pick_', N) > 0) or (Pos('no_light', N) > 0) or (Pos('/top_', N) > 0) then
      Exit;
    if Pos('thumbnail', N) > 0 then
    begin
      if (Pos('small', N) > 0) or (Pos('middle', N) > 0) then
        Result := 80
      else
        Result := 100;
      Exit;
    end;
    if Pos('plate_', N) > 0 then
    begin
      if Pos('small', N) > 0 then
        Result := 40
      else if Pos('plate_1.', N) > 0 then
        Result := 70
      else
        Result := 60;
      Exit;
    end;
    Result := 10;
  end;

begin
  Result := Default(T3mfModel);
  Result.Status := st3NotZip;
  if (APath = '') or not FileExists(APath) then
    Exit;
  Names := TDictionary<string, Integer>.Create;
  Zip := TZipFile.Create;
  Parser := nil;
  try
    try
      Zip.Open(APath, zmRead);
    except
      Exit;
    end;
    for I := 0 to Zip.FileCount - 1 do
    begin
      Name := ZipNorm(Zip.FileName[I]);
      if Name <> '' then
        Names.AddOrSetValue(Name, I);
    end;
    RootName := '';
    ThumbName := '';
    LoadSmall('_rels/.rels', Rels);
    if Length(Rels) > 0 then
    begin
      ThumbName := ImageName(FindRelTarget(Rels, 'metadata/thumbnail'));
      RootName := ModelPartName(FindRelTarget(Rels, '/3dmodel'));
    end;
    KeepImage(ResolveEntry(ThumbName));
    if not Result.HasThumb then
      for Key in Names.Keys do
        if (Key <> '_rels/.rels') and (NameExt(Key) = '.rels') then
        begin
          LoadSmall(Key, Rels);
          KeepImage(ResolveEntry(ImageName(FindRelTarget(Rels, 'metadata/thumbnail'))));
          if Result.HasThumb then
            Break;
        end;
    if not Result.HasThumb then
    begin
      BestScore := 0;
      BestI := -1;
      BestSize := 0;
      for Key in Names.Keys do
      begin
        Score := ImageScore(Key);
        if Score < 1 then
          Continue;
        I := Names[Key];
        Sz := Zip.FileInfo[I].UncompressedSize64;
        if (Sz = 0) or (Sz > C3mfThumbMax) then
          Continue;
        if (Score > BestScore) or ((Score = BestScore) and (Sz > BestSize)) then
        begin
          BestScore := Score;
          BestSize := Sz;
          BestI := I;
        end;
      end;
      KeepImage(BestI);
    end;
    ModelI := ResolveEntry(RootName);
    if ModelI < 0 then
      ModelI := IndexOfName('3d/3dmodel.model');
    if ModelI < 0 then
    begin
      LooseN := 0;
      LooseName := '';
      BestI := -1;
      for Key in Names.Keys do
        if (NameExt(Key) = '.model') and (Pos('/objects/', Key) = 0) then
        begin
          Inc(LooseN);
          if (LooseName = '') or ((Pos('3dmodel.model', Key) > 0) and
             (Pos('3dmodel.model', LooseName) = 0)) then
          begin
            LooseName := Key;
            BestI := Names[Key];
          end;
        end;
      if LooseN >= 1 then
        ModelI := BestI
      else
      begin
        LooseN := 0;
        for Key in Names.Keys do
          if NameExt(Key) = '.model' then
          begin
            Inc(LooseN);
            BestI := Names[Key];
          end;
        if LooseN = 1 then
          ModelI := BestI;
      end;
    end;
    if ModelI < 0 then
    begin
      Result.Status := st3NoModel;
      Exit;
    end;
    Sz := Zip.FileInfo[ModelI].UncompressedSize64;
    if Sz > C3mfXmlMax then
    begin
      Result.Status := st3TooBig;
      Exit;
    end;
    if not ALoadMesh then
    begin
      Result.Status := st3Ok;
      Exit;
    end;
    try
      Zip.Read(ModelI, Xml);
    except
      on EOutOfMemory do
      begin
        Result.Status := st3TooBig;
        Exit;
      end;
    else
      begin
        Result.Status := st3Bad;
        Exit;
      end;
    end;
    if (Length(Xml) = 0) or (Length(Xml) > C3mfXmlMax) then
    begin
      if Length(Xml) > C3mfXmlMax then
        Result.Status := st3TooBig
      else
        Result.Status := st3Bad;
      Exit;
    end;
    Parser := T3mfParser.Create;
    try
      Parser.Parse(Xml, AMaxTris, AMaxVerts, AMaxMs, ACancel);
      SetLength(Xml, 0);
      if Parser.FCancelled then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      Guard := 0;
      while (Guard < C3mfDepth) and not Parser.FCancelled and
        not Parser.FPartTooBig do
      begin
        Paths := Parser.PartPaths;
        if Length(Paths) = 0 then
          Break;
        for P := 0 to High(Paths) do
        begin
          if Assigned(ACancel) and ACancel() then
          begin
            Parser.FCancelled := True;
            Break;
          end;
          PartI := ResolveEntry(Paths[P]);
          if PartI < 0 then
          begin
            Parser.IngestPart(Paths[P], Empty);
            Continue;
          end;
          Sz := Zip.FileInfo[PartI].UncompressedSize64;
          if (Sz = 0) or (Sz > C3mfXmlMax) then
          begin
            Parser.FPartTooBig := True;
            Break;
          end;
          try
            Zip.Read(PartI, PartXml);
          except
            on EOutOfMemory do
            begin
              Parser.FPartTooBig := True;
              Break;
            end;
          else
            begin
              SetLength(PartXml, 0);
              Parser.IngestPart(Paths[P], Empty);
              Continue;
            end;
          end;
          if Length(PartXml) > C3mfXmlMax then
          begin
            SetLength(PartXml, 0);
            Parser.FPartTooBig := True;
            Break;
          end;
          try
            Parser.IngestPart(Paths[P], PartXml);
          finally
            SetLength(PartXml, 0);
          end;
        end;
        Inc(Guard);
      end;
      if Parser.FCancelled then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      Parser.Build(Result);
    except
      on EOutOfMemory do
        Result.Status := st3TooBig;
    else
      if Result.Status = st3NotZip then
        Result.Status := st3Bad;
    end;
  finally
    Parser.Free;
    Names.Free;
    Zip.Free;
    SetLength(Xml, 0);
    SetLength(PartXml, 0);
    SetLength(Rels, 0);
  end;
end;

end.
