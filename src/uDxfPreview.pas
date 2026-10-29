unit uDxfPreview;

{
  Кадр DXF для плитки и быстрого просмотра.
  Модельное пространство: линии, дуги, полилинии с bulge, блоки и INSERT,
  сплайн по точкам, простой текст. Штриховка, лист и тела ACIS не рисуются.
  Вид сверху (XY). Если чертёж плоский в другой плоскости, берётся она.
}

interface

uses
  System.SysUtils, FMX.Graphics;

function LoadDxfPreview(const APath: string; ABitmap: TBitmap;
  AMaxSide: Integer): Boolean;
function RenderDxfTile(const APath: string; AMaxSide: Integer;
  ABitmap: TBitmap): Boolean;

implementation

uses
  System.Classes, System.Math, System.Generics.Collections, System.Types,
  System.UITypes, System.Skia, FMX.Skia;

const
  DxfMaxBytes = 64 * 1024 * 1024;
  DxfMaxEnt = 300000;
  DxfMaxPts = 1500000;
  DxfMaxDepth = 8;
  DxfViewSide = 2400;

type
  TDxfKind = (dkLine, dkCircle, dkArc, dkEllipse, dkLw, dkPoly, dkSpline,
    dkInsert, dkPoint, dkSolid, dkFace, dkText, dkMText, dkDim, dkLeader);

  TProj = (pjXY, pjXZ, pjYZ);

  TDxfPt = record
    X, Y, Z, B: Double;
  end;

  TDxfFace = record
    A, B, C, D: Integer;
  end;

  TDxfEnt = record
    Kind: TDxfKind;
    Layer: string;
    Color: Integer;
    Rgb: Integer;
    Mirror: Boolean;
    Closed: Boolean;
    X, Y, Z: Double;
    X2, Y2, Z2: Double;
    R, A0, A1, Ratio, Rot, Sx, Sy, Th: Double;
    SySet: Boolean;
    Align: Boolean;
    HAlign, VAlign: Integer;
    Name: string;
    Text: string;
    Flags: Integer;
    MeshM, MeshN: Integer;
    Degree: Integer;
    Pts: TArray<TDxfPt>;
    NPts: Integer;
    Fit: TArray<TDxfPt>;
    NFit: Integer;
    Knots: TArray<Double>;
    NKnots: Integer;
    Faces: TArray<TDxfFace>;
    NFaces: Integer;
    Corn: array[0..3] of TDxfPt;
    NCorn: Integer;
  end;

  TDxfBlock = record
    Name: string;
    Bx, By: Double;
    Ents: TArray<TDxfEnt>;
    NEnt: Integer;
  end;

  TDxfLayer = record
    Name: string;
    Color: Integer;
    Off: Boolean;
    Frozen: Boolean;
  end;

  TAff = record
    A, B, C, D, E, F: Double;
  end;

  TRunKind = (rkStroke, rkFill, rkPoint, rkText);

  TRun = record
    Kind: TRunKind;
    Col: Cardinal;
    At, N: Integer;
    Closed: Boolean;
    Th, Rot: Single;
    Text: string;
  end;

  TDxfDoc = class
  private
    FLayers: TArray<TDxfLayer>;
    FNLayers: Integer;
    FLayerOf: TDictionary<string, Integer>;
    FBlocks: TArray<TDxfBlock>;
    FNBlocks: Integer;
    FBlockOf: TDictionary<string, Integer>;
    FRoot: TArray<TDxfEnt>;
    FNRoot: Integer;
    FProj: TProj;
    FMinX, FMaxX, FMinY, FMaxY, FMinZ, FMaxZ: Double;
    FHaveBox: Boolean;
    FPts: TArray<TDxfPt>;
    FNPts: Integer;
    FRuns: TArray<TRun>;
    FNRuns: Integer;
    FStack: array[0..DxfMaxDepth] of string;
    procedure Note(X, Y, Z: Double);
    function Shown(const ALayer: string): Boolean;
    function LayerColor(const ALayer: string): Integer;
    function Ink(AAci, ARgb: Integer; const ALayer: string;
      AInherit: TAlphaColor): TAlphaColor;
    procedure AddRun(AKind: TRunKind; ACol: TAlphaColor; AAt, AN: Integer;
      AClosed: Boolean; ATh, ARot: Single; const AText: string);
    procedure AddXY(X, Y: Double);
    function AffOf(const E: TDxfEnt; Bx, By: Double): TAff;
    procedure World(const M: TAff; X, Y, Z: Double; AMirror: Boolean;
      out U, V: Double);
    procedure EmitPts(const M: TAff; AMirror: Boolean; const Src: array of TDxfPt;
      ACount: Integer; AClosed: Boolean; ACol: TAlphaColor; AFill: Boolean);
    procedure EmitLine(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitArc(const M: TAff; CX, CY, Z, R, A0, A1: Double;
      AFull, AMirror: Boolean; ACol: TAlphaColor);
    procedure EmitBulgePoly(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitEllipse(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitSpline(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitSolid(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitFace(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitPolyMesh(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitFaceMesh(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitText(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
    procedure EmitEnt(const E: TDxfEnt; const M: TAff; AInherit: TAlphaColor;
      ADepth: Integer);
    procedure EmitBlock(AIndex: Integer; const M: TAff; AInherit: TAlphaColor;
      ADepth: Integer);
    procedure EmitList(const Ents: TArray<TDxfEnt>; AN: Integer; const M: TAff;
      AInherit: TAlphaColor; ADepth: Integer);
    function BlockIndex(const AName: string): Integer;
    procedure ChooseProj;
    function PaintRuns(ABitmap: TBitmap; AMaxSide: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Load(const APath: string): Boolean;
    function Paint(ABitmap: TBitmap; AMaxSide: Integer): Boolean;
  end;

  TBinKind = (bkStop, bkStr, bkDbl, bkI16, bkI32, bkI64, bkByte, bkChunk);

function AffIdent: TAff;
begin
  Result.A := 1;
  Result.B := 0;
  Result.C := 0;
  Result.D := 1;
  Result.E := 0;
  Result.F := 0;
end;

function AffMul(const P, L: TAff): TAff;
begin
  Result.A := P.A * L.A + P.B * L.C;
  Result.B := P.A * L.B + P.B * L.D;
  Result.E := P.A * L.E + P.B * L.F + P.E;
  Result.C := P.C * L.A + P.D * L.C;
  Result.D := P.C * L.B + P.D * L.D;
  Result.F := P.C * L.E + P.D * L.F + P.F;
end;

function PackRgb(R, G, B: Byte): TAlphaColor;
var
  C: TAlphaColorRec;
begin
  C.R := R;
  C.G := G;
  C.B := B;
  C.A := 255;
  Result := C.Color;
end;

function PackInt(ARgb: Integer): TAlphaColor;
begin
  Result := PackRgb(Byte((ARgb shr 16) and $FF), Byte((ARgb shr 8) and $FF),
    Byte(ARgb and $FF));
end;

function DarkenPaper(C: TAlphaColor): TAlphaColor;
var
  Q: TAlphaColorRec;
begin
  Q.Color := C;
  if (Q.R >= 250) and (Q.G >= 250) and (Q.B >= 250) then
    Result := PackRgb($33, $33, $33)
  else
    Result := C;
end;

function AciColor(AIndex: Integer): TAlphaColor;
const
  Levels: array[0..4] of Integer = (255, 165, 127, 76, 38);
var
  I, Hue, Band, Sec, Step, Rise, Fall, Lv, Mx: Integer;
  BR, BG, BB, R, G, B: Integer;
begin
  if (AIndex < 1) or (AIndex > 255) then
    AIndex := 7;
  case AIndex of
    1: Exit(PackRgb(255, 0, 0));
    2: Exit(PackRgb(255, 255, 0));
    3: Exit(PackRgb(0, 255, 0));
    4: Exit(PackRgb(0, 255, 255));
    5: Exit(PackRgb(0, 0, 255));
    6: Exit(PackRgb(255, 0, 255));
    7: Exit(PackRgb(0, 0, 0));
    8: Exit(PackRgb(128, 128, 128));
    9: Exit(PackRgb(192, 192, 192));
    250: Exit(PackRgb(0, 0, 0));
    251: Exit(PackRgb($2D, $2D, $2D));
    252: Exit(PackRgb($5B, $5B, $5B));
    253: Exit(PackRgb($89, $89, $89));
    254: Exit(PackRgb($B7, $B7, $B7));
    255: Exit(PackRgb($B3, $B3, $B3));
  end;
  I := AIndex - 10;
  if (I < 0) or (I > 239) then
    Exit(PackRgb(0, 0, 0));
  Hue := I div 10;
  Band := I mod 10;
  Sec := Hue div 4;
  Step := Hue mod 4;
  case Step of
    0: Rise := 0;
    1: Rise := $3F;
    2: Rise := $7F;
  else
    Rise := $BF;
  end;
  case 4 - Step of
    0: Fall := 0;
    1: Fall := $3F;
    2: Fall := $7F;
    3: Fall := $BF;
  else
    Fall := $FF;
  end;
  case Sec of
    0: begin BR := 255; BG := Rise; BB := 0; end;
    1: begin BR := Fall; BG := 255; BB := 0; end;
    2: begin BR := 0; BG := 255; BB := Rise; end;
    3: begin BR := 0; BG := Fall; BB := 255; end;
    4: begin BR := Rise; BG := 0; BB := 255; end;
  else
    begin BR := 255; BG := 0; BB := Fall; end;
  end;
  Lv := Levels[Band div 2];
  R := Round(BR * Lv / 255);
  G := Round(BG * Lv / 255);
  B := Round(BB * Lv / 255);
  if Odd(Band) then
  begin
    Mx := R;
    if G > Mx then
      Mx := G;
    if B > Mx then
      Mx := B;
    R := (R + Mx) div 2;
    G := (G + Mx) div 2;
    B := (B + Mx) div 2;
  end;
  Result := PackRgb(R, G, B);
end;

function HexVal(C: Char): Integer;
begin
  if (C >= '0') and (C <= '9') then
    Exit(Ord(C) - Ord('0'));
  if (C >= 'a') and (C <= 'f') then
    Exit(Ord(C) - Ord('a') + 10);
  if (C >= 'A') and (C <= 'F') then
    Exit(Ord(C) - Ord('A') + 10);
  Result := -1;
end;

function CleanDxfText(const S: string; AMText: Boolean): string;
var
  I, N, H, K: Integer;
  C: Char;
begin
  SetLength(Result, Length(S));
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    C := S[I];
    if (C = '%') and (I + 2 <= Length(S)) and (S[I + 1] = '%') then
    begin
      case UpCase(S[I + 2]) of
        'D': C := #$00B0;
        'P': C := #$00B1;
        'C': C := #$00D8;
        '%': C := '%';
        'U', 'O':
          begin
            Inc(I, 3);
            Continue;
          end;
      else
        Inc(I);
        Continue;
      end;
      Inc(N);
      Result[N] := C;
      Inc(I, 3);
      Continue;
    end;
    if C = '\' then
    begin
      if I >= Length(S) then
        Break;
      C := S[I + 1];
      if (UpCase(C) = 'U') and (I + 2 <= Length(S)) and (S[I + 2] = '+') then
      begin
        H := 0;
        K := 0;
        Inc(I, 3);
        while (I <= Length(S)) and (K < 6) and (HexVal(S[I]) >= 0) do
        begin
          H := (H shl 4) or HexVal(S[I]);
          Inc(I);
          Inc(K);
        end;
        if (H > 0) and (H <= $FFFF) then
        begin
          Inc(N);
          Result[N] := Char(H);
        end;
        Continue;
      end;
      if AMText and (UpCase(C) = 'P') then
      begin
        Inc(N);
        Result[N] := #10;
        Inc(I, 2);
        Continue;
      end;
      if AMText and (C = '~') then
      begin
        Inc(N);
        Result[N] := ' ';
        Inc(I, 2);
        Continue;
      end;
      if C = '\' then
      begin
        Inc(N);
        Result[N] := '\';
        Inc(I, 2);
        Continue;
      end;
      if (C = '{') or (C = '}') then
      begin
        Inc(I, 2);
        Continue;
      end;
      Inc(I, 2);
      if AMText then
        while (I <= Length(S)) and (S[I] <> ';') and (S[I] <> '\') do
          Inc(I);
      if (I <= Length(S)) and (S[I] = ';') then
        Inc(I);
      Continue;
    end;
    if AMText and ((C = '{') or (C = '}')) then
    begin
      Inc(I);
      Continue;
    end;
    Inc(N);
    Result[N] := C;
    Inc(I);
  end;
  SetLength(Result, N);
end;

function KindOfName(const AName: string; out AKind: TDxfKind): Boolean;
begin
  Result := True;
  if AName = 'LINE' then
    AKind := dkLine
  else if AName = 'CIRCLE' then
    AKind := dkCircle
  else if AName = 'ARC' then
    AKind := dkArc
  else if AName = 'ELLIPSE' then
    AKind := dkEllipse
  else if AName = 'LWPOLYLINE' then
    AKind := dkLw
  else if AName = 'POLYLINE' then
    AKind := dkPoly
  else if AName = 'SPLINE' then
    AKind := dkSpline
  else if AName = 'INSERT' then
    AKind := dkInsert
  else if AName = 'POINT' then
    AKind := dkPoint
  else if (AName = 'SOLID') or (AName = 'TRACE') then
    AKind := dkSolid
  else if AName = '3DFACE' then
    AKind := dkFace
  else if AName = 'TEXT' then
    AKind := dkText
  else if AName = 'MTEXT' then
    AKind := dkMText
  else if AName = 'DIMENSION' then
    AKind := dkDim
  else if (AName = 'LEADER') or (AName = 'MLEADER') then
    AKind := dkLeader
  else
    Result := False;
end;

function IsModelName(const AName: string): Boolean;
begin
  Result := SameText(AName, '*MODEL_SPACE') or SameText(AName, '*MODEL_SPACE0');
end;

procedure ClearEnt(out E: TDxfEnt);
begin
  E := Default(TDxfEnt);
  E.Color := 256;
  E.Rgb := -1;
  E.Sx := 1;
  E.Sy := 1;
  E.Ratio := 1;
  E.A1 := 360;
  E.Degree := 3;
end;

procedure GrowPt(var A: TArray<TDxfPt>; var N: Integer; const P: TDxfPt);
begin
  if N >= 900000 then
    Exit;
  if N >= Length(A) then
    SetLength(A, N + 64 + N div 2);
  A[N] := P;
  Inc(N);
end;

function BinKind(ACode: Integer): TBinKind;
begin
  case ACode of
    0..9, 100..102, 105, 300..309, 320..369, 390..399, 410..419,
    430..439, 470..481, 999, 1000..1009:
      Result := bkStr;
    10..59, 110..149, 210..239, 460..469, 1010..1059:
      Result := bkDbl;
    60..79, 170..179, 270..289, 370..389, 400..409, 1060..1070:
      Result := bkI16;
    90..99, 420..429, 440..449, 1071:
      Result := bkI32;
    160..169:
      Result := bkI64;
    290..299:
      Result := bkByte;
    310..319:
      Result := bkChunk;
  else
    Result := bkStop;
  end;
end;

function NextTextLine(const S: string; var I: Integer; out Line: string): Boolean;
var
  A: Integer;
begin
  if I > Length(S) then
    Exit(False);
  A := I;
  while (I <= Length(S)) and (S[I] <> #10) and (S[I] <> #13) do
    Inc(I);
  Line := Copy(S, A, I - A);
  if (I <= Length(S)) and (S[I] = #13) then
    Inc(I);
  if (I <= Length(S)) and (S[I] = #10) then
    Inc(I);
  Result := True;
end;

constructor TDxfDoc.Create;
begin
  inherited Create;
  FLayerOf := TDictionary<string, Integer>.Create;
  FBlockOf := TDictionary<string, Integer>.Create;
end;

destructor TDxfDoc.Destroy;
begin
  FLayerOf.Free;
  FBlockOf.Free;
  inherited;
end;

procedure TDxfDoc.Note(X, Y, Z: Double);
begin
  if not FHaveBox then
  begin
    FMinX := X;
    FMaxX := X;
    FMinY := Y;
    FMaxY := Y;
    FMinZ := Z;
    FMaxZ := Z;
    FHaveBox := True;
    Exit;
  end;
  if X < FMinX then
    FMinX := X;
  if X > FMaxX then
    FMaxX := X;
  if Y < FMinY then
    FMinY := Y;
  if Y > FMaxY then
    FMaxY := Y;
  if Z < FMinZ then
    FMinZ := Z;
  if Z > FMaxZ then
    FMaxZ := Z;
end;

function TDxfDoc.Load(const APath: string): Boolean;
var
  B: TBytes;
  Text: string;
  FS: TFileStream;
  Sz: Int64;
  Enc: TEncoding;
  Head: string;
  Bin: Boolean;
  Pos: Integer;
  At: Integer;
  Code: Integer;
  Num: Double;
  StrV: string;
  IsNum: Boolean;
  Mode: Integer;
  Sec: Integer;
  Wait: Integer;
  Table: string;
  InBlock: Boolean;
  BlockIx: Integer;
  OpenWhere, OpenIx: Integer;
  VtxLive, VtxSaw: Boolean;
  Vtx: TDxfPt;
  VtxFlag: Integer;
  VtxFace: TDxfFace;
  Cur: TDxfEnt;
  Lay: TDxfLayer;
  Blk: TDxfBlock;
  Stop: Boolean;
  PairN: Integer;
  Fmt: TFormatSettings;

  procedure SkipBlank(const S: string; var I: Integer);
  var
    Line: string;
    J: Integer;
  begin
    while True do
    begin
      J := I;
      if not NextTextLine(S, J, Line) then
        Exit;
      if Trim(Line) <> '' then
        Exit;
      I := J;
    end;
  end;

  procedure ApplyNum(var E: TDxfEnt; ACode: Integer; V: Double;
    var Vtx: TDxfPt; var VtxFlag: Integer; var VtxFace: TDxfFace;
    var VtxSaw: Boolean; AVtx: Boolean);
  var
    Slot: Integer;
    P: TDxfPt;
  begin
    if AVtx then
    begin
      case ACode of
        10: Vtx.X := V;
        20: Vtx.Y := V;
        30: Vtx.Z := V;
        42: Vtx.B := V;
        70: VtxFlag := Round(V);
        71:
          begin
            VtxFace.A := Round(V);
            VtxSaw := True;
          end;
        72:
          begin
            VtxFace.B := Round(V);
            VtxSaw := True;
          end;
        73:
          begin
            VtxFace.C := Round(V);
            VtxSaw := True;
          end;
        74:
          begin
            VtxFace.D := Round(V);
            VtxSaw := True;
          end;
      end;
      Exit;
    end;
    case E.Kind of
      dkLw, dkLeader:
        if ACode = 10 then
        begin
          P := Default(TDxfPt);
          P.X := V;
          P.Z := E.Z;
          GrowPt(E.Pts, E.NPts, P);
          Note(V, 0, E.Z);
        end
        else if (ACode = 20) and (E.NPts > 0) then
        begin
          E.Pts[E.NPts - 1].Y := V;
          Note(E.Pts[E.NPts - 1].X, V, E.Pts[E.NPts - 1].Z);
        end
        else if (ACode = 42) and (E.NPts > 0) then
          E.Pts[E.NPts - 1].B := V
        else if ACode = 38 then
          E.Z := V
        else if ACode = 70 then
          E.Flags := Round(V);
      dkSpline:
        if ACode = 10 then
        begin
          P := Default(TDxfPt);
          P.X := V;
          GrowPt(E.Pts, E.NPts, P);
          Note(V, 0, 0);
        end
        else if (ACode = 20) and (E.NPts > 0) then
        begin
          E.Pts[E.NPts - 1].Y := V;
          Note(E.Pts[E.NPts - 1].X, V, 0);
        end
        else if (ACode = 30) and (E.NPts > 0) then
          E.Pts[E.NPts - 1].Z := V
        else if ACode = 11 then
        begin
          P := Default(TDxfPt);
          P.X := V;
          GrowPt(E.Fit, E.NFit, P);
          Note(V, 0, 0);
        end
        else if (ACode = 21) and (E.NFit > 0) then
        begin
          E.Fit[E.NFit - 1].Y := V;
          Note(E.Fit[E.NFit - 1].X, V, 0);
        end
        else if (ACode = 31) and (E.NFit > 0) then
          E.Fit[E.NFit - 1].Z := V
        else if ACode = 40 then
        begin
          if E.NKnots >= Length(E.Knots) then
            SetLength(E.Knots, E.NKnots + 32);
          E.Knots[E.NKnots] := V;
          Inc(E.NKnots);
        end
        else if ACode = 70 then
          E.Flags := Round(V)
        else if ACode = 71 then
          E.Degree := Max(1, Round(V));
      dkLine, dkSolid, dkFace:
        begin
          if (ACode >= 10) and (ACode <= 13) then
            Slot := ACode - 10
          else if (ACode >= 20) and (ACode <= 23) then
            Slot := ACode - 20
          else if (ACode >= 30) and (ACode <= 33) then
            Slot := ACode - 30
          else
            Slot := -1;
          if Slot >= 0 then
          begin
            if Slot + 1 > E.NCorn then
              E.NCorn := Slot + 1;
            if (ACode >= 10) and (ACode <= 13) then
              E.Corn[Slot].X := V
            else if (ACode >= 20) and (ACode <= 23) then
              E.Corn[Slot].Y := V
            else
              E.Corn[Slot].Z := V;
            Note(E.Corn[Slot].X, E.Corn[Slot].Y, E.Corn[Slot].Z);
          end
          else if ACode = 70 then
            E.Flags := Round(V);
        end;
    else
      case ACode of
        10:
          begin
            E.X := V;
            Note(V, E.Y, E.Z);
          end;
        20:
          begin
            E.Y := V;
            Note(E.X, V, E.Z);
          end;
        30:
          begin
            E.Z := V;
            Note(E.X, E.Y, V);
          end;
        11: E.X2 := V;
        21: E.Y2 := V;
        31: E.Z2 := V;
        40:
          begin
            E.R := V;
            E.Th := V;
            E.Ratio := V;
            if E.Kind in [dkCircle, dkArc] then
            begin
              Note(E.X - V, E.Y - V, E.Z);
              Note(E.X + V, E.Y + V, E.Z);
            end;
          end;
        41:
          if E.Kind = dkInsert then
            E.Sx := V
          else if E.Kind = dkEllipse then
            E.A0 := V;
        42:
          if E.Kind = dkInsert then
          begin
            E.Sy := V;
            E.SySet := True;
          end
          else if E.Kind = dkEllipse then
            E.A1 := V;
        50:
          begin
            E.A0 := V;
            E.Rot := V;
          end;
        51: E.A1 := V;
        62: E.Color := Round(V);
        67: ;
        70:
          E.Flags := Round(V);
        71:
          if E.Kind = dkMText then
            E.VAlign := Round(V)
          else if E.Kind = dkPoly then
            E.MeshM := Round(V);
        72:
          if E.Kind = dkText then
            E.HAlign := Round(V)
          else if E.Kind = dkPoly then
            E.MeshN := Round(V);
        73:
          if E.Kind = dkText then
            E.VAlign := Round(V);
        210: E.X2 := E.X2;
        220: ;
        230:
          if V < -0.5 then
            E.Mirror := True;
        420:
          E.Rgb := Integer(Cardinal(Round(V)) and $FFFFFF);
      end;
    end;
    if (E.Kind in [dkLw, dkLeader, dkSpline, dkLine, dkSolid, dkFace]) and
       (ACode = 62) then
      E.Color := Round(V);
    if (E.Kind in [dkLw, dkLeader, dkSpline, dkLine, dkSolid, dkFace]) and
       (ACode = 420) then
      E.Rgb := Integer(Cardinal(Round(V)) and $FFFFFF);
    if (E.Kind in [dkLw, dkLeader, dkSpline]) and (ACode = 230) and (V < -0.5) then
      E.Mirror := True;
    if (ACode = 67) and (Round(V) = 1) then
      E.Flags := E.Flags or $10000;
  end;

  function ReadAsciiPair: Boolean;
  var
    Line, Tok: string;
  begin
    Result := False;
    SkipBlank(Text, Pos);
    if not NextTextLine(Text, Pos, Line) then
      Exit;
    Tok := Trim(Line);
    if Tok = '' then
      Exit;
    if not TryStrToFloat(Tok, Num, Fmt) then
      Exit;
    Code := Round(Num);
    if not NextTextLine(Text, Pos, StrV) then
      Exit;
    IsNum := False;
    Num := 0;
    case BinKind(Code) of
      bkDbl, bkI16, bkI32, bkI64, bkByte:
        begin
          IsNum := TryStrToFloat(Trim(StrV), Num, Fmt);
          if not IsNum then
            Num := 0;
        end;
    else
      IsNum := False;
    end;
    Result := True;
  end;

  function ReadBinPair: Boolean;
  var
    Kind: TBinKind;
    K: Integer;
    Ch: Byte;

    function Need(N: Integer): Boolean;
    begin
      Result := At + N <= Length(B);
    end;

  begin
    Result := False;
    if not Need(2) then
      Exit;
    Code := SmallInt(Word(B[At]) or (Word(B[At + 1]) shl 8));
    Inc(At, 2);
    Kind := BinKind(Code);
    if Kind = bkStop then
    begin
      Stop := True;
      Exit;
    end;
    IsNum := False;
    Num := 0;
    StrV := '';
    case Kind of
      bkStr:
        begin
          K := 0;
          while (At < Length(B)) and (B[At] <> 0) and (K < 8192) do
          begin
            Inc(K);
            Inc(At);
          end;
          if K > 0 then
            StrV := TEncoding.ANSI.GetString(B, At - K, K);
          if (At < Length(B)) and (B[At] = 0) then
            Inc(At);
        end;
      bkDbl:
        begin
          if not Need(8) then
            Exit;
          Move(B[At], Num, 8);
          Inc(At, 8);
          IsNum := True;
        end;
      bkI16:
        begin
          if not Need(2) then
            Exit;
          Num := SmallInt(Word(B[At]) or (Word(B[At + 1]) shl 8));
          Inc(At, 2);
          IsNum := True;
        end;
      bkI32:
        begin
          if not Need(4) then
            Exit;
          Num := Integer(Cardinal(B[At]) or (Cardinal(B[At + 1]) shl 8) or
            (Cardinal(B[At + 2]) shl 16) or (Cardinal(B[At + 3]) shl 24));
          Inc(At, 4);
          IsNum := True;
        end;
      bkI64:
        begin
          if not Need(8) then
            Exit;
          Inc(At, 8);
          IsNum := True;
        end;
      bkByte:
        begin
          if not Need(1) then
            Exit;
          Num := B[At];
          Inc(At);
          IsNum := True;
        end;
      bkChunk:
        begin
          if not Need(1) then
            Exit;
          Ch := B[At];
          Inc(At);
          if not Need(Ch) then
            Exit;
          Inc(At, Ch);
        end;
    end;
    Result := True;
  end;

  procedure CommitLayer;
  var
    Key: string;
  begin
    if Lay.Name = '' then
      Exit;
    Key := UpperCase(Lay.Name);
    if Lay.Color = 0 then
      Lay.Color := 7;
    if FNLayers >= Length(FLayers) then
      SetLength(FLayers, FNLayers + 32);
    FLayers[FNLayers] := Lay;
    FLayerOf.AddOrSetValue(Key, FNLayers);
    Inc(FNLayers);
    Lay := Default(TDxfLayer);
  end;

  procedure CommitBlock;
  var
    Key: string;
  begin
    if Blk.Name = '' then
      Blk.Name := 'BLK';
    Key := UpperCase(Blk.Name);
    if FNBlocks >= Length(FBlocks) then
      SetLength(FBlocks, FNBlocks + 16);
    FBlocks[FNBlocks] := Blk;
    FBlockOf.AddOrSetValue(Key, FNBlocks);
    BlockIx := FNBlocks;
    Inc(FNBlocks);
    InBlock := True;
    Blk := Default(TDxfBlock);
  end;

  procedure CommitEnt;
  var
    DestN: Integer;
  begin
    if (Cur.Flags and $10000) <> 0 then
    begin
      ClearEnt(Cur);
      Exit;
    end;
    if (FNRoot + FNBlocks) > DxfMaxEnt then
    begin
      Stop := True;
      ClearEnt(Cur);
      Exit;
    end;
    if InBlock and (BlockIx >= 0) and (BlockIx < FNBlocks) then
    begin
      DestN := FBlocks[BlockIx].NEnt;
      if DestN >= Length(FBlocks[BlockIx].Ents) then
        SetLength(FBlocks[BlockIx].Ents, DestN + 32 + DestN div 2);
      FBlocks[BlockIx].Ents[DestN] := Cur;
      Inc(FBlocks[BlockIx].NEnt);
      if Cur.Kind = dkPoly then
      begin
        OpenWhere := 1;
        OpenIx := DestN;
      end;
    end
    else if Sec = 4 then
    begin
      if FNRoot >= Length(FRoot) then
        SetLength(FRoot, FNRoot + 64 + FNRoot div 2);
      FRoot[FNRoot] := Cur;
      if Cur.Kind = dkPoly then
      begin
        OpenWhere := 0;
        OpenIx := FNRoot;
      end;
      Inc(FNRoot);
    end;
    ClearEnt(Cur);
  end;

  procedure CommitVtx;

    procedure Take(var Ent: TDxfEnt);
    begin
      Note(Vtx.X, Vtx.Y, Vtx.Z);
      if VtxSaw or (((VtxFlag and 128) <> 0) and
         ((VtxFace.A <> 0) or (VtxFace.B <> 0))) then
      begin
        if Ent.NFaces >= Length(Ent.Faces) then
          SetLength(Ent.Faces, Ent.NFaces + 16);
        Ent.Faces[Ent.NFaces] := VtxFace;
        Inc(Ent.NFaces);
      end
      else
        GrowPt(Ent.Pts, Ent.NPts, Vtx);
      if Ent.NPts > DxfMaxPts then
        Stop := True;
    end;

  begin
    if OpenIx < 0 then
      Exit;
    if OpenWhere = 1 then
    begin
      if (BlockIx < 0) or (BlockIx >= FNBlocks) or
         (OpenIx >= FBlocks[BlockIx].NEnt) then
        Exit;
      Take(FBlocks[BlockIx].Ents[OpenIx]);
    end
    else
    begin
      if OpenIx >= FNRoot then
        Exit;
      Take(FRoot[OpenIx]);
    end;
  end;

  procedure BeginType(const AName: string);
  var
    Up: string;
    K: TDxfKind;
  begin
    Up := UpperCase(Trim(AName));
    if VtxLive then
    begin
      CommitVtx;
      VtxLive := False;
    end;
    if Mode = 1 then
      CommitEnt
    else if Mode = 2 then
      CommitLayer
    else if Mode = 3 then
      CommitBlock;
    if Up <> 'VERTEX' then
    begin
      OpenIx := -1;
      OpenWhere := 0;
    end;
    Mode := 0;
    if Up = 'EOF' then
      Stop := True
    else if Up = 'SECTION' then
      Wait := 1
    else if Up = 'ENDSEC' then
    begin
      Sec := 0;
      InBlock := False;
      OpenIx := -1;
    end
    else if Up = 'TABLE' then
      Wait := 2
    else if Up = 'ENDTAB' then
      Table := ''
    else if Up = 'BLOCK' then
    begin
      if Sec = 3 then
      begin
        Mode := 3;
        Blk := Default(TDxfBlock);
      end;
    end
    else if Up = 'ENDBLK' then
    begin
      InBlock := False;
      OpenIx := -1;
    end
    else if Up = 'SEQEND' then
      OpenIx := -1
    else if Up = 'VERTEX' then
    begin
      if OpenIx >= 0 then
      begin
        VtxLive := True;
        Vtx := Default(TDxfPt);
        VtxFlag := 0;
        VtxFace := Default(TDxfFace);
        VtxSaw := False;
      end;
    end
    else if Up = 'LAYER' then
    begin
      if Table = 'LAYER' then
      begin
        Mode := 2;
        Lay := Default(TDxfLayer);
        Lay.Color := 7;
      end;
    end
    else if KindOfName(Up, K) and ((Sec = 4) or (InBlock and (Sec = 3))) then
    begin
      Mode := 1;
      ClearEnt(Cur);
      Cur.Kind := K;
      if K = dkEllipse then
      begin
        Cur.A0 := 0;
        Cur.A1 := 2 * Pi;
      end;
    end;
  end;

  procedure ApplyStr(ACode: Integer; const S: string);
  begin
    if (ACode = 2) and (Wait = 1) then
    begin
      Wait := 0;
      if SameText(S, 'HEADER') then
        Sec := 1
      else if SameText(S, 'TABLES') then
        Sec := 2
      else if SameText(S, 'BLOCKS') then
        Sec := 3
      else if SameText(S, 'ENTITIES') then
        Sec := 4
      else
        Sec := 0;
      Exit;
    end;
    if (ACode = 2) and (Wait = 2) then
    begin
      Wait := 0;
      Table := UpperCase(Trim(S));
      Exit;
    end;
    if Mode = 3 then
    begin
      if ACode = 2 then
        Blk.Name := Trim(S);
      Exit;
    end;
    if Mode = 2 then
    begin
      if ACode = 2 then
        Lay.Name := Trim(S);
      Exit;
    end;
    if Mode <> 1 then
      Exit;
    if (ACode = 8) and not VtxLive then
      Cur.Layer := Trim(S)
    else if (ACode = 2) and (Cur.Kind in [dkInsert, dkDim]) then
      Cur.Name := Trim(S)
    else if (ACode = 1) and (Cur.Kind in [dkText, dkMText]) then
      Cur.Text := Cur.Text + S
    else if (ACode = 3) and (Cur.Kind = dkMText) then
      Cur.Text := Cur.Text + S;
  end;

begin
  Result := False;
  if (APath = '') or not FileExists(APath) then
    Exit;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Sz := FS.Size;
    if (Sz < 12) or (Sz > DxfMaxBytes) then
      Exit;
    SetLength(B, Sz);
    if FS.Read(B[0], Sz) <> Sz then
      Exit;
  finally
    FS.Free;
  end;
  Bin := (Length(B) >= 22) and
    (TEncoding.ASCII.GetString(B, 0, 18) = 'AutoCAD Binary DXF');
  Fmt := TFormatSettings.Invariant;
  Pos := 1;
  At := 0;
  Mode := 0;
  Sec := 0;
  Wait := 0;
  Table := '';
  InBlock := False;
  BlockIx := -1;
  OpenWhere := 0;
  OpenIx := -1;
  VtxLive := False;
  Stop := False;
  PairN := 0;
  ClearEnt(Cur);
  if not Bin then
  begin
    Enc := TEncoding.ANSI;
    if (Length(B) >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
      Enc := TEncoding.UTF8
    else
    begin
      Head := TEncoding.ASCII.GetString(B, 0, Min(4000, Length(B)));
      if System.Pos('UTF-8', UpperCase(Head)) > 0 then
        Enc := TEncoding.UTF8;
    end;
    Text := Enc.GetString(B);
    SetLength(B, 0);
  end
  else
    At := 22;
  while not Stop do
  begin
    if Bin then
    begin
      if not ReadBinPair then
        Break;
    end
    else if not ReadAsciiPair then
      Break;
    Inc(PairN);
    if PairN > 8000000 then
      Break;
    if Code = 0 then
      BeginType(StrV)
    else if Mode = 2 then
    begin
      if (Code = 62) and IsNum then
      begin
        Lay.Color := Abs(Round(Num));
        Lay.Off := Num < 0;
      end
      else if (Code = 70) and IsNum then
        Lay.Frozen := (Round(Num) and 1) <> 0
      else if not IsNum then
        ApplyStr(Code, StrV);
    end
    else if Mode = 3 then
    begin
      if IsNum and (Code = 10) then
        Blk.Bx := Num
      else if IsNum and (Code = 20) then
        Blk.By := Num
      else if not IsNum then
        ApplyStr(Code, StrV);
    end
    else if IsNum then
      ApplyNum(Cur, Code, Num, Vtx, VtxFlag, VtxFace, VtxSaw, VtxLive)
    else
      ApplyStr(Code, StrV);
    if FNRoot > DxfMaxEnt then
      Break;
  end;
  if VtxLive then
    CommitVtx;
  if Mode = 1 then
    CommitEnt
  else if Mode = 2 then
    CommitLayer
  else if Mode = 3 then
    CommitBlock;
  Result := (FNRoot > 0) or (FNBlocks > 0);
end;

function TDxfDoc.Shown(const ALayer: string): Boolean;
var
  Ix: Integer;
begin
  if (ALayer = '') or not FLayerOf.TryGetValue(UpperCase(ALayer), Ix) then
    Exit(True);
  Result := (not FLayers[Ix].Off) and (not FLayers[Ix].Frozen);
end;

function TDxfDoc.LayerColor(const ALayer: string): Integer;
var
  Ix: Integer;
begin
  if FLayerOf.TryGetValue(UpperCase(ALayer), Ix) then
    Result := FLayers[Ix].Color
  else
    Result := 7;
  if Result <= 0 then
    Result := 7;
end;

function TDxfDoc.Ink(AAci, ARgb: Integer; const ALayer: string;
  AInherit: TAlphaColor): TAlphaColor;
begin
  if (AAci <> 0) and (AAci <> 256) and (ARgb >= 0) then
    Exit(PackInt(ARgb));
  if AAci = 0 then
    Exit(AInherit);
  if (AAci = 256) or (AAci < 0) then
    Exit(AciColor(LayerColor(ALayer)));
  Result := AciColor(AAci);
end;

procedure TDxfDoc.AddRun(AKind: TRunKind; ACol: TAlphaColor; AAt, AN: Integer;
  AClosed: Boolean; ATh, ARot: Single; const AText: string);
begin
  if FNRuns >= 500000 then
    Exit;
  if FNRuns >= Length(FRuns) then
    SetLength(FRuns, FNRuns + 128 + FNRuns div 2);
  FRuns[FNRuns].Kind := AKind;
  FRuns[FNRuns].Col := Cardinal(ACol);
  FRuns[FNRuns].At := AAt;
  FRuns[FNRuns].N := AN;
  FRuns[FNRuns].Closed := AClosed;
  FRuns[FNRuns].Th := ATh;
  FRuns[FNRuns].Rot := ARot;
  FRuns[FNRuns].Text := AText;
  Inc(FNRuns);
end;

procedure TDxfDoc.AddXY(X, Y: Double);
begin
  if FNPts >= DxfMaxPts then
    Exit;
  if FNPts >= Length(FPts) then
    SetLength(FPts, FNPts + 256 + FNPts div 2);
  FPts[FNPts].X := X;
  FPts[FNPts].Y := Y;
  Inc(FNPts);
end;

function TDxfDoc.AffOf(const E: TDxfEnt; Bx, By: Double): TAff;
var
  Co, Si, Sx, Sy: Double;
begin
  Sx := E.Sx;
  if Abs(Sx) < 1E-12 then
    Sx := 1;
  if E.SySet then
    Sy := E.Sy
  else
    Sy := Sx;
  if Abs(Sy) < 1E-12 then
    Sy := Sx;
  Co := Cos(DegToRad(E.Rot));
  Si := Sin(DegToRad(E.Rot));
  Result.A := Sx * Co;
  Result.B := -Sy * Si;
  Result.C := Sx * Si;
  Result.D := Sy * Co;
  Result.E := E.X - Result.A * Bx - Result.B * By;
  Result.F := E.Y - Result.C * Bx - Result.D * By;
end;

procedure TDxfDoc.World(const M: TAff; X, Y, Z: Double; AMirror: Boolean;
  out U, V: Double);
var
  WX, WY, WZ: Double;
begin
  if AMirror then
    X := -X;
  WX := M.A * X + M.B * Y + M.E;
  WY := M.C * X + M.D * Y + M.F;
  WZ := Z;
  case FProj of
    pjXZ:
      begin
        U := WX;
        V := WZ;
      end;
    pjYZ:
      begin
        U := WY;
        V := WZ;
      end;
  else
    begin
      U := WX;
      V := WY;
    end;
  end;
end;

procedure TDxfDoc.EmitPts(const M: TAff; AMirror: Boolean;
  const Src: array of TDxfPt; ACount: Integer; AClosed: Boolean;
  ACol: TAlphaColor; AFill: Boolean);
var
  I, A, N: Integer;
  U, V: Double;
begin
  if ACount < 2 then
    Exit;
  A := FNPts;
  N := 0;
  for I := 0 to ACount - 1 do
  begin
    if FNPts >= DxfMaxPts then
      Break;
    World(M, Src[I].X, Src[I].Y, Src[I].Z, AMirror, U, V);
    if (N > 0) and (Abs(U - FPts[FNPts - 1].X) < 1E-9) and
       (Abs(V - FPts[FNPts - 1].Y) < 1E-9) then
      Continue;
    AddXY(U, V);
    Inc(N);
  end;
  if N < 2 then
    Exit;
  if AFill then
    AddRun(rkFill, ACol, A, N, True, 0, 0, '')
  else
    AddRun(rkStroke, DarkenPaper(ACol), A, N, AClosed, 0, 0, '');
end;

procedure TDxfDoc.EmitLine(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  P: array[0..1] of TDxfPt;
begin
  if E.NCorn < 2 then
    Exit;
  P[0] := E.Corn[0];
  P[1] := E.Corn[1];
  EmitPts(M, E.Mirror, P, 2, False, ACol, False);
end;

procedure TDxfDoc.EmitArc(const M: TAff; CX, CY, Z, R, A0, A1: Double;
  AFull, AMirror: Boolean; ACol: TAlphaColor);
var
  Sweep, A, S, C: Double;
  I, N, At, Count: Integer;
  U, V: Double;
begin
  if R <= 1E-12 then
    Exit;
  if AFull then
    Sweep := 2 * Pi
  else
  begin
    Sweep := DegToRad(A1 - A0);
    while Sweep <= 1E-6 do
      Sweep := Sweep + 2 * Pi;
    if Sweep > 2 * Pi - 1E-4 then
      Sweep := 2 * Pi;
    A0 := DegToRad(A0);
  end;
  N := EnsureRange(Round(Sweep / DegToRad(8)), 8, 96);
  if AFull then
    N := Max(N, 24);
  At := FNPts;
  Count := 0;
  for I := 0 to N do
  begin
    if (not AFull) or (I < N) then
    begin
      A := A0 + Sweep * I / N;
      S := Sin(A);
      C := Cos(A);
      World(M, CX + R * C, CY + R * S, Z, AMirror, U, V);
      AddXY(U, V);
      Inc(Count);
    end;
  end;
  if Count >= 2 then
    AddRun(rkStroke, DarkenPaper(ACol), At, Count, AFull or (Sweep > 2 * Pi - 0.01),
      0, 0, '');
end;

procedure BulgePoints(X1, Y1, X2, Y2, B: Double; var Dst: TArray<TDxfPt>;
  var N: Integer);
var
  Dx, Dy, C, H, Cx, Cy, R, A0, A1, Sweep, StepA, A: Double;
  I, Segs: Integer;
  P: TDxfPt;
  CCW: Boolean;
begin
  Dx := X2 - X1;
  Dy := Y2 - Y1;
  C := Hypot(Dx, Dy);
  if (C < 1E-9) or (Abs(B) < 1E-8) then
    Exit;
  H := C * (1 - B * B) / (4 * B);
  Cx := (X1 + X2) * 0.5 + (-Dy / C) * H;
  Cy := (Y1 + Y2) * 0.5 + (Dx / C) * H;
  R := Abs(C * (1 + B * B) / (4 * B));
  if R < 1E-9 then
    Exit;
  A0 := ArcTan2(Y1 - Cy, X1 - Cx);
  A1 := ArcTan2(Y2 - Cy, X2 - Cx);
  CCW := B > 0;
  if CCW then
  begin
    Sweep := A1 - A0;
    while Sweep <= 1E-6 do
      Sweep := Sweep + 2 * Pi;
  end
  else
  begin
    Sweep := A0 - A1;
    while Sweep <= 1E-6 do
      Sweep := Sweep + 2 * Pi;
    Sweep := -Sweep;
  end;
  Segs := EnsureRange(Round(Abs(Sweep) / DegToRad(8)), 2, 80);
  StepA := Sweep / Segs;
  for I := 1 to Segs - 1 do
  begin
    A := A0 + StepA * I;
    P.X := Cx + R * Cos(A);
    P.Y := Cy + R * Sin(A);
    P.Z := 0;
    P.B := 0;
    GrowPt(Dst, N, P);
  end;
end;

procedure TDxfDoc.EmitBulgePoly(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  Tmp: TArray<TDxfPt>;
  NT, I, J: Integer;
  P: TDxfPt;
  Closed: Boolean;
begin
  if E.NPts < 2 then
    Exit;
  Closed := E.Closed or ((E.Flags and 1) <> 0);
  NT := 0;
  J := E.NPts - 1;
  if Closed then
    J := E.NPts;
  for I := 0 to J - 1 do
  begin
    P := E.Pts[I mod E.NPts];
    P.B := 0;
    GrowPt(Tmp, NT, P);
    if Abs(E.Pts[I mod E.NPts].B) > 1E-8 then
      BulgePoints(E.Pts[I mod E.NPts].X, E.Pts[I mod E.NPts].Y,
        E.Pts[(I + 1) mod E.NPts].X, E.Pts[(I + 1) mod E.NPts].Y,
        E.Pts[I mod E.NPts].B, Tmp, NT);
  end;
  if not Closed then
  begin
    P := E.Pts[E.NPts - 1];
    P.B := 0;
    GrowPt(Tmp, NT, P);
  end;
  EmitPts(M, E.Mirror, Tmp, NT, Closed, ACol, False);
end;

procedure TDxfDoc.EmitEllipse(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  Mx, My, Len, Sweep, T, Ct, St: Double;
  Nx, Ny, A0: Double;
  I, N, At, Count: Integer;
  U, V: Double;
begin
  Mx := E.X2;
  My := E.Y2;
  Len := Hypot(Mx, My);
  if Len < 1E-9 then
    Exit;
  Nx := -My * E.Ratio;
  Ny := Mx * E.Ratio;
  A0 := E.A0;
  Sweep := E.A1 - E.A0;
  while Sweep < -1E-6 do
    Sweep := Sweep + 2 * Pi;
  if Sweep < 1E-4 then
    Sweep := 2 * Pi;
  N := EnsureRange(Round(Sweep / DegToRad(8)), 8, 96);
  At := FNPts;
  Count := 0;
  for I := 0 to N do
  begin
    if (Sweep < 2 * Pi - 1E-3) or (I < N) then
    begin
      T := A0 + Sweep * I / N;
      Ct := Cos(T);
      St := Sin(T);
      World(M, E.X + Mx * Ct + Nx * St, E.Y + My * Ct + Ny * St, E.Z,
        E.Mirror, U, V);
      AddXY(U, V);
      Inc(Count);
    end;
  end;
  if Count >= 2 then
    AddRun(rkStroke, DarkenPaper(ACol), At, Count, Sweep > 2 * Pi - 0.05,
      0, 0, '');
end;

function DeBoor(const Ctrl: TArray<TDxfPt>; NC: Integer; const Knots: TArray<Double>;
  NK, Deg: Integer; U: Double; out X, Y, Z: Double): Boolean;
var
  K, R, J, S: Integer;
  Dx, Dy, Dz: array of Double;
  A, Den: Double;
begin
  Result := False;
  if (NC < 2) or (Deg < 1) or (NK < NC + Deg + 1) then
    Exit;
  if U >= Knots[NC] then
    K := NC - 1
  else if U <= Knots[Deg] then
    K := Deg
  else
  begin
    K := Deg;
    for S := Deg to NC - 1 do
      if (U >= Knots[S]) and (U < Knots[S + 1]) then
      begin
        K := S;
        Break;
      end;
  end;
  SetLength(Dx, Deg + 1);
  SetLength(Dy, Deg + 1);
  SetLength(Dz, Deg + 1);
  for J := 0 to Deg do
  begin
    S := K - Deg + J;
    if (S < 0) or (S >= NC) then
      Exit;
    Dx[J] := Ctrl[S].X;
    Dy[J] := Ctrl[S].Y;
    Dz[J] := Ctrl[S].Z;
  end;
  for R := 1 to Deg do
    for J := Deg downto R do
    begin
      Den := Knots[J + K - R + 1] - Knots[J + K - Deg];
      if Abs(Den) < 1E-12 then
        A := 0
      else
        A := (U - Knots[J + K - Deg]) / Den;
      Dx[J] := (1 - A) * Dx[J - 1] + A * Dx[J];
      Dy[J] := (1 - A) * Dy[J - 1] + A * Dy[J];
      Dz[J] := (1 - A) * Dz[J - 1] + A * Dz[J];
    end;
  X := Dx[Deg];
  Y := Dy[Deg];
  Z := Dz[Deg];
  Result := True;
end;

procedure TDxfDoc.EmitSpline(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  Tmp: TArray<TDxfPt>;
  NT, I, Segs: Integer;
  U0, U1, U, X, Y, Z: Double;
  P: TDxfPt;
  Closed: Boolean;
begin
  Closed := (E.Flags and 1) <> 0;
  if E.NFit >= 2 then
  begin
    EmitPts(M, E.Mirror, E.Fit, E.NFit, Closed, ACol, False);
    Exit;
  end;
  if (E.NPts >= 2) and (E.NKnots >= E.NPts + E.Degree + 1) then
  begin
    U0 := E.Knots[E.Degree];
    U1 := E.Knots[E.NPts];
    Segs := EnsureRange((E.NPts - E.Degree) * 6, 8, 720);
    NT := 0;
    for I := 0 to Segs do
    begin
      if Segs = 0 then
        U := U0
      else
        U := U0 + (U1 - U0) * I / Segs;
      if not DeBoor(E.Pts, E.NPts, E.Knots, E.NKnots, E.Degree, U, X, Y, Z) then
      begin
        NT := 0;
        Break;
      end;
      P.X := X;
      P.Y := Y;
      P.Z := Z;
      P.B := 0;
      GrowPt(Tmp, NT, P);
    end;
    if NT >= 2 then
    begin
      EmitPts(M, E.Mirror, Tmp, NT, Closed, ACol, False);
      Exit;
    end;
  end;
  if E.NPts >= 2 then
    EmitPts(M, E.Mirror, E.Pts, E.NPts, Closed, ACol, False);
end;

procedure TDxfDoc.EmitSolid(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  P: array[0..3] of TDxfPt;
  N: Integer;
begin
  if E.NCorn < 3 then
    Exit;
  P[0] := E.Corn[0];
  P[1] := E.Corn[1];
  if E.NCorn >= 4 then
  begin
    P[2] := E.Corn[3];
    P[3] := E.Corn[2];
    N := 4;
  end
  else
  begin
    P[2] := E.Corn[2];
    N := 3;
  end;
  EmitPts(M, E.Mirror, P, N, True, ACol, True);
  EmitPts(M, E.Mirror, P, N, True, ACol, False);
end;

procedure TDxfDoc.EmitFace(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  Idx: array[0..3] of Integer;
  Hide: array[0..3] of Boolean;
  I, N, A, Count: Integer;
  U, V: Double;
  P, Q: TDxfPt;
begin
  N := E.NCorn;
  if N < 3 then
    Exit;
  if N > 4 then
    N := 4;
  Idx[0] := 0;
  Idx[1] := 1;
  Idx[2] := 2;
  Idx[3] := 3;
  Hide[0] := (E.Flags and 1) <> 0;
  Hide[1] := (E.Flags and 2) <> 0;
  Hide[2] := (E.Flags and 4) <> 0;
  Hide[3] := (E.Flags and 8) <> 0;
  for I := 0 to N - 1 do
  begin
    if (N = 3) and (I = 2) then
    begin
      if Hide[2] and Hide[3] then
        Continue;
    end
    else if Hide[I] then
      Continue;
    P := E.Corn[Idx[I]];
    Q := E.Corn[Idx[(I + 1) mod N]];
    A := FNPts;
    World(M, P.X, P.Y, P.Z, E.Mirror, U, V);
    AddXY(U, V);
    World(M, Q.X, Q.Y, Q.Z, E.Mirror, U, V);
    AddXY(U, V);
    Count := 2;
    AddRun(rkStroke, DarkenPaper(ACol), A, Count, False, 0, 0, '');
  end;
end;

procedure TDxfDoc.EmitPolyMesh(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  Rows, Cols, R, C, I0, I1: Integer;
  P: array[0..1] of TDxfPt;
begin
  Rows := E.MeshM;
  Cols := E.MeshN;
  if (Rows < 2) or (Cols < 2) or (E.NPts < Rows * Cols) then
  begin
    EmitBulgePoly(M, E, ACol);
    Exit;
  end;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
    begin
      I0 := R * Cols + C;
      if C + 1 < Cols then
      begin
        I1 := I0 + 1;
        P[0] := E.Pts[I0];
        P[1] := E.Pts[I1];
        EmitPts(M, E.Mirror, P, 2, False, ACol, False);
      end;
      if R + 1 < Rows then
      begin
        I1 := I0 + Cols;
        P[0] := E.Pts[I0];
        P[1] := E.Pts[I1];
        EmitPts(M, E.Mirror, P, 2, False, ACol, False);
      end;
    end;
end;

procedure TDxfDoc.EmitText(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  Raw, Line: string;
  X, Y, Z, U, V: Double;
  I, Cut, At: Integer;
  Step: Double;
begin
  Raw := Trim(CleanDxfText(E.Text, E.Kind = dkMText));
  if (Raw = '') or (E.Th <= 1E-9) then
    Exit;
  X := E.X;
  Y := E.Y;
  Z := E.Z;
  if (E.Kind = dkText) and ((E.HAlign <> 0) or (E.VAlign <> 0)) then
  begin
    X := E.X2;
    Y := E.Y2;
  end;
  Step := E.Th * 1.25;
  I := 1;
  while I <= Length(Raw) do
  begin
    Cut := I;
    while (Cut <= Length(Raw)) and (Raw[Cut] <> #10) do
      Inc(Cut);
    Line := Copy(Raw, I, Cut - I);
    if Line <> '' then
    begin
      World(M, X, Y, Z, False, U, V);
      V := V - (0) ;
      At := FNPts;
      AddXY(U, V);
      AddRun(rkText, DarkenPaper(ACol), At, 1, False, E.Th, E.Rot, Line);
    end;
    Y := Y - Step;
    I := Cut + 1;
  end;
end;

function TDxfDoc.BlockIndex(const AName: string): Integer;
begin
  if not FBlockOf.TryGetValue(UpperCase(Trim(AName)), Result) then
    Result := -1;
end;

procedure TDxfDoc.EmitList(const Ents: TArray<TDxfEnt>; AN: Integer;
  const M: TAff; AInherit: TAlphaColor; ADepth: Integer);
var
  I: Integer;
begin
  for I := 0 to AN - 1 do
    EmitEnt(Ents[I], M, AInherit, ADepth);
end;

procedure TDxfDoc.EmitBlock(AIndex: Integer; const M: TAff;
  AInherit: TAlphaColor; ADepth: Integer);
var
  I: Integer;
  Name: string;
begin
  if (AIndex < 0) or (AIndex >= FNBlocks) or (ADepth > DxfMaxDepth) then
    Exit;
  Name := UpperCase(FBlocks[AIndex].Name);
  for I := 0 to ADepth - 1 do
    if FStack[I] = Name then
      Exit;
  FStack[ADepth] := Name;
  EmitList(FBlocks[AIndex].Ents, FBlocks[AIndex].NEnt, M, AInherit, ADepth);
end;

procedure TDxfDoc.EmitEnt(const E: TDxfEnt; const M: TAff; AInherit: TAlphaColor;
  ADepth: Integer);
var
  Col: TAlphaColor;
  Ix: Integer;
  Local, WorldM: TAff;
  Ins: TDxfEnt;
  U, V: Double;
begin
  if not Shown(E.Layer) then
    Exit;
  if FNRuns >= 500000 then
    Exit;
  Col := Ink(E.Color, E.Rgb, E.Layer, AInherit);
  case E.Kind of
    dkLine:
      EmitLine(M, E, Col);
    dkCircle:
      EmitArc(M, E.X, E.Y, E.Z, E.R, 0, 0, True, E.Mirror, Col);
    dkArc:
      EmitArc(M, E.X, E.Y, E.Z, E.R, E.A0, E.A1, False, E.Mirror, Col);
    dkEllipse:
      EmitEllipse(M, E, Col);
    dkLw, dkLeader:
      EmitBulgePoly(M, E, Col);
    dkPoly:
      if ((E.Flags and 64) <> 0) and (E.NFaces > 0) then
        EmitFaceMesh(M, E, Col)
      else if (E.Flags and 16) <> 0 then
        EmitPolyMesh(M, E, Col)
      else
        EmitBulgePoly(M, E, Col);
    dkSpline:
      EmitSpline(M, E, Col);
    dkPoint:
      begin
        World(M, E.X, E.Y, E.Z, E.Mirror, U, V);
        AddXY(U, V);
        AddRun(rkPoint, DarkenPaper(Col), FNPts - 1, 1, False, 0, 0, '');
      end;
    dkSolid:
      EmitSolid(M, E, Col);
    dkFace:
      EmitFace(M, E, Col);
    dkText, dkMText:
      EmitText(M, E, Col);
    dkInsert, dkDim:
      begin
        Ix := BlockIndex(E.Name);
        if Ix < 0 then
          Exit;
        if (E.Kind = dkInsert) and IsModelName(FBlocks[Ix].Name) then
          Exit;
        Ins := E;
        if E.Kind = dkDim then
        begin
          Ins.X := 0;
          Ins.Y := 0;
          Ins.Rot := 0;
          Ins.Sx := 1;
          Ins.Sy := 1;
          Ins.SySet := True;
        end;
        Local := AffOf(Ins, FBlocks[Ix].Bx, FBlocks[Ix].By);
        WorldM := AffMul(M, Local);
        EmitBlock(Ix, WorldM, Col, ADepth + 1);
      end;
  end;
end;

procedure TDxfDoc.EmitFaceMesh(const M: TAff; const E: TDxfEnt; ACol: TAlphaColor);
var
  I, A, B, C, D: Integer;
  P: array[0..1] of TDxfPt;

  procedure Edge(I0, I1: Integer);
  var
    Hide: Boolean;
  begin
    Hide := I0 < 0;
    I0 := Abs(I0);
    I1 := Abs(I1);
    if (I0 < 1) or (I1 < 1) or (I0 > E.NPts) or (I1 > E.NPts) then
      Exit;
    if Hide then
      Exit;
    P[0] := E.Pts[I0 - 1];
    P[1] := E.Pts[I1 - 1];
    EmitPts(M, E.Mirror, P, 2, False, ACol, False);
  end;

begin
  for I := 0 to E.NFaces - 1 do
  begin
    A := E.Faces[I].A;
    B := E.Faces[I].B;
    C := E.Faces[I].C;
    D := E.Faces[I].D;
    Edge(A, B);
    if C <> 0 then
      Edge(B, C);
    if D <> 0 then
    begin
      Edge(C, D);
      Edge(D, A);
    end
    else if C <> 0 then
      Edge(C, A);
  end;
end;

procedure TDxfDoc.ChooseProj;
var
  SX, SY, SZ, Big: Double;
begin
  FProj := pjXY;
  if not FHaveBox then
    Exit;
  SX := FMaxX - FMinX;
  SY := FMaxY - FMinY;
  SZ := FMaxZ - FMinZ;
  Big := SX;
  if SY > Big then
    Big := SY;
  if SZ > Big then
    Big := SZ;
  if Big < 1E-9 then
    Exit;
  if (SY <= Big * 0.02) and (SZ > SY * 8) and (SZ > Big * 0.2) then
  begin
    if SX >= SY then
      FProj := pjXZ
    else
      FProj := pjYZ;
  end
  else if (SX <= Big * 0.02) and (SZ > SX * 8) and (SY > Big * 0.2) then
    FProj := pjYZ;
end;

function TDxfDoc.PaintRuns(ABitmap: TBitmap; AMaxSide: Integer): Boolean;
var
  I, J, W, H, Pad: Integer;
  MinU, MaxU, MinV, MaxV, SpanU, SpanV, Scale: Double;
  Have: Boolean;
  Stroke, Fill: ISkPaint;
  Font: ISkFont;

begin
  Result := False;
  if FNRuns < 1 then
    Exit;
  Have := False;
  MinU := 0;
  MaxU := 0;
  MinV := 0;
  MaxV := 0;
  for I := 0 to FNRuns - 1 do
  begin
    if FRuns[I].Kind = rkText then
    begin
      if (FRuns[I].At < 0) or (FRuns[I].At >= FNPts) then
        Continue;
      SpanU := Max(FRuns[I].Th, Length(FRuns[I].Text) * FRuns[I].Th * 0.55);
      SpanV := Max(FRuns[I].Th, 1E-6);
      if not Have then
      begin
        MinU := FPts[FRuns[I].At].X - SpanU;
        MaxU := FPts[FRuns[I].At].X + SpanU;
        MinV := FPts[FRuns[I].At].Y - SpanV;
        MaxV := FPts[FRuns[I].At].Y + SpanV;
        Have := True;
      end
      else
      begin
        MinU := Min(MinU, FPts[FRuns[I].At].X - SpanU);
        MaxU := Max(MaxU, FPts[FRuns[I].At].X + SpanU);
        MinV := Min(MinV, FPts[FRuns[I].At].Y - SpanV);
        MaxV := Max(MaxV, FPts[FRuns[I].At].Y + SpanV);
      end;
      Continue;
    end;
    for J := 0 to FRuns[I].N - 1 do
    begin
      if FRuns[I].At + J >= FNPts then
        Break;
      if not Have then
      begin
        MinU := FPts[FRuns[I].At + J].X;
        MaxU := MinU;
        MinV := FPts[FRuns[I].At + J].Y;
        MaxV := MinV;
        Have := True;
      end
      else
      begin
        MinU := Min(MinU, FPts[FRuns[I].At + J].X);
        MaxU := Max(MaxU, FPts[FRuns[I].At + J].X);
        MinV := Min(MinV, FPts[FRuns[I].At + J].Y);
        MaxV := Max(MaxV, FPts[FRuns[I].At + J].Y);
      end;
    end;
  end;
  if not Have then
    Exit;
  if MaxU - MinU < 1E-6 then
  begin
    MinU := MinU - 1;
    MaxU := MaxU + 1;
  end;
  if MaxV - MinV < 1E-6 then
  begin
    MinV := MinV - 1;
    MaxV := MaxV + 1;
  end;
  if AMaxSide <= 0 then
    AMaxSide := DxfViewSide;
  AMaxSide := EnsureRange(AMaxSide, 32, 4096);
  Pad := Max(4, Round(AMaxSide * 0.04));
  SpanU := MaxU - MinU;
  SpanV := MaxV - MinV;
  Scale := (AMaxSide - 2.0 * Pad) / Max(SpanU, SpanV);
  if Scale <= 0 then
    Exit;
  W := Max(1, Round(SpanU * Scale + 2 * Pad));
  H := Max(1, Round(SpanV * Scale + 2 * Pad));
  if W > AMaxSide then
    W := AMaxSide;
  if H > AMaxSide then
    H := AMaxSide;
  ABitmap.SetSize(W, H);
  Stroke := TSkPaint.Create(TSkPaintStyle.Stroke);
  Stroke.AntiAlias := True;
  Stroke.StrokeWidth := 1.35;
  Stroke.StrokeCap := TSkStrokeCap.Round;
  Stroke.StrokeJoin := TSkStrokeJoin.Round;
  Fill := TSkPaint.Create(TSkPaintStyle.Fill);
  Fill.AntiAlias := True;
  ABitmap.SkiaDraw(
    procedure(const C: ISkCanvas)
    var
      R, K: Integer;
      Path: ISkPathBuilder;
      Snap: ISkPath;
      Ink: TAlphaColor;
      Face: ISkTypeface;

      function Px(X: Double): Single;
      begin
        Result := Pad + (X - MinU) * Scale;
      end;

      function Py(Y: Double): Single;
      begin
        Result := (H - Pad) - (Y - MinV) * Scale;
      end;

    begin
      C.Clear(TAlphaColors.White);
      Face := TSkTypeface.MakeDefault;
      for R := 0 to FNRuns - 1 do
      begin
        Ink := TAlphaColor(FRuns[R].Col);
        if FRuns[R].Kind = rkPoint then
        begin
          if (FRuns[R].At < 0) or (FRuns[R].At >= FNPts) then
            Continue;
          Stroke.Color := Ink;
          C.DrawLine(Px(FPts[FRuns[R].At].X) - 3, Py(FPts[FRuns[R].At].Y),
            Px(FPts[FRuns[R].At].X) + 3, Py(FPts[FRuns[R].At].Y), Stroke);
          C.DrawLine(Px(FPts[FRuns[R].At].X), Py(FPts[FRuns[R].At].Y) - 3,
            Px(FPts[FRuns[R].At].X), Py(FPts[FRuns[R].At].Y) + 3, Stroke);
        end
        else if FRuns[R].Kind = rkText then
        begin
          if FRuns[R].Th * Scale < 3 then
            Continue;
          if (FRuns[R].At < 0) or (FRuns[R].At >= FNPts) then
            Continue;
          Font := TSkFont.Create(Face, Max(1, FRuns[R].Th * Scale), 1, 0);
          Fill.Color := Ink;
          C.Save;
          C.Translate(Px(FPts[FRuns[R].At].X), Py(FPts[FRuns[R].At].Y));
          C.Rotate(-FRuns[R].Rot);
          C.DrawSimpleText(FRuns[R].Text, 0, 0, Font, Fill);
          C.Restore;
        end
        else if FRuns[R].N >= 2 then
        begin
          Path := TSkPathBuilder.Create;
          Path.MoveTo(Px(FPts[FRuns[R].At].X), Py(FPts[FRuns[R].At].Y));
          for K := 1 to FRuns[R].N - 1 do
          begin
            if FRuns[R].At + K >= FNPts then
              Break;
            Path.LineTo(Px(FPts[FRuns[R].At + K].X), Py(FPts[FRuns[R].At + K].Y));
          end;
          if FRuns[R].Closed then
            Path.Close;
          Snap := Path.Snapshot;
          if FRuns[R].Kind = rkFill then
          begin
            Fill.Color := Ink;
            C.DrawPath(Snap, Fill);
          end
          else
          begin
            Stroke.Color := Ink;
            C.DrawPath(Snap, Stroke);
          end;
        end;
      end;
    end, True);
  Result := (ABitmap.Width > 1) and (ABitmap.Height > 1);
end;

function TDxfDoc.Paint(ABitmap: TBitmap; AMaxSide: Integer): Boolean;
var
  M: TAff;
  Ix: Integer;
begin
  Result := False;
  if ABitmap = nil then
    Exit;
  ChooseProj;
  M := AffIdent;
  if FNRoot > 0 then
    EmitList(FRoot, FNRoot, M, AciColor(7), 0)
  else
  begin
    Ix := BlockIndex('*MODEL_SPACE');
    if Ix < 0 then
      Ix := BlockIndex('*MODEL_SPACE0');
    if Ix >= 0 then
      EmitBlock(Ix, M, AciColor(7), 0);
  end;
  Result := PaintRuns(ABitmap, AMaxSide);
end;

function LoadDxfPreview(const APath: string; ABitmap: TBitmap;
  AMaxSide: Integer): Boolean;
var
  Doc: TDxfDoc;
begin
  Result := False;
  if (APath = '') or (ABitmap = nil) then
    Exit;
  Doc := TDxfDoc.Create;
  try
    try
      if not Doc.Load(APath) then
        Exit;
      Result := Doc.Paint(ABitmap, AMaxSide);
    except
      Result := False;
    end;
  finally
    Doc.Free;
  end;
end;

function RenderDxfTile(const APath: string; AMaxSide: Integer;
  ABitmap: TBitmap): Boolean;
begin
  if AMaxSide <= 0 then
    AMaxSide := 256;
  Result := LoadDxfPreview(APath, ABitmap, AMaxSide);
end;

end.
