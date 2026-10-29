unit uMeshPreview;

{
  Кадр сітки для плитки і швидкого перегляду.
  Без форм, теми і панелі. Рендер викликають з фонового потоку.
}

interface

uses
  System.SysUtils, FMX.Graphics;

type
  TMeshKind = (mkNone, mkStl, mkObj, mkPly, mkGltf, mkGlb, mkBlend);

  TMeshError = (meNone, meEmpty, meBad, meNoView, meBlend, meNotMesh);

  TMeshCancel = reference to function: Boolean;

  TMeshCamera = record
    Azimuth: Single;
    Elevation: Single;
    Scale: Single;
  end;

  TMeshInfo = record
    Kind: TMeshKind;
    Vertices: Int64;
    Triangles: Int64;
    Points: Int64;
    Error: TMeshError;
    Simplified: Boolean;
    Picture: Boolean;
    Bytes: Int64;
    PicW: Integer;
    PicH: Integer;
  end;

function IsMeshExt(const AExt: string): Boolean;
function MeshKindName(AKind: TMeshKind): string;
function MeshHomeCamera: TMeshCamera;
function MeshInfo(const APath: string): TMeshInfo;
function RenderMeshThumb(const APath: string; ASize: Integer): TBitmap;
function RenderMeshView(const APath: string; AW, AH: Integer;
  const ACamera: TMeshCamera): TBitmap; overload;
function RenderMeshView(const APath: string; AW, AH: Integer;
  const ACamera: TMeshCamera; out AInfo: TMeshInfo): TBitmap; overload;
function RenderMeshView(const APath: string; AW, AH: Integer;
  const ACamera: TMeshCamera; out AInfo: TMeshInfo;
  const ACancel: TMeshCancel): TBitmap; overload;

implementation

uses
  System.Classes, System.Math, System.Diagnostics, System.IOUtils, System.SyncObjs,
  System.StrUtils, System.UITypes, System.JSON, System.NetEncoding, System.ZLib,
  FMX.Types;

const
  TILE_BYTES = 64 * 1024 * 1024;
  VIEW_BYTES = 256 * 1024 * 1024;
  TILE_TRIS = 400000;
  VIEW_TRIS = 1500000;
  TILE_VERTS = 800000;
  VIEW_VERTS = 3000000;
  TILE_MS = 1500;
  VIEW_MS = 4000;
  MAX_FRAME = 2560;
  GRAY_R = 176;
  GRAY_G = 178;
  GRAY_B = 184;
  { Відстань камери в одиницях нормалізованої сітки (ребро куба = 1). }
  CAM_DIST = 3.0;

type
  TMeshLimits = record
    MaxBytes: Int64;
    MaxTris: Integer;
    MaxVerts: Integer;
    MaxMs: Cardinal;
  end;

  TMeshVert = record
    X, Y, Z: Single;
    Nx, Ny, Nz: Single;
    Col: Cardinal;
  end;

  TMeshTri = record
    A, B, C: Integer;
    Nx, Ny, Nz: Single;
    Col: Cardinal;
  end;

  TMeshData = record
    Info: TMeshInfo;
    Verts: TArray<TMeshVert>;
    Tris: TArray<TMeshTri>;
    HasVertColor: Boolean;
    Cancelled: Boolean;
    Pic: TBytes;
    PicW, PicH: Integer;
  end;

  TPlyTy = (pyI8, pyU8, pyI16, pyU16, pyI32, pyU32, pyF32, pyF64);

  TMat4 = array[0..15] of Single;

  TVec3 = record
    X, Y, Z: Single;
  end;

  TScr = record
    X, Y, Z: Single;
  end;

  THold = record
    Valid: Boolean;
    Path: string;
    Age: TDateTime;
    Bytes: Int64;
    MaxTris: Integer;
    MaxVerts: Integer;
    Data: TMeshData;
  end;

var
  GLock: TCriticalSection;
  GHold: THold;

function V3(X, Y, Z: Single): TVec3;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

function VSub(const A, B: TVec3): TVec3;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
  Result.Z := A.Z - B.Z;
end;

function VCross(const A, B: TVec3): TVec3;
begin
  Result.X := A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.Z * B.X - A.X * B.Z;
  Result.Z := A.X * B.Y - A.Y * B.X;
end;

function VDot(const A, B: TVec3): Single;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function VLen(const A: TVec3): Single;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
end;

function VNorm(const A: TVec3): TVec3;
var
  L: Single;
begin
  L := VLen(A);
  if L < 1E-12 then
    Exit(V3(0, 0, 0));
  Result.X := A.X / L;
  Result.Y := A.Y / L;
  Result.Z := A.Z / L;
end;

function CeilDiv(A, B: Int64): Int64;
begin
  if (B <= 0) or (A <= 0) then
    Exit(1);
  Result := (A + B - 1) div B;
end;

function IsMeshExt(const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  if (E <> '') and (E[1] <> '.') then
    E := '.' + E;
  Result := (E = '.stl') or (E = '.obj') or (E = '.ply') or (E = '.gltf') or
    (E = '.glb') or (E = '.blend');
end;

function MeshKindName(AKind: TMeshKind): string;
begin
  case AKind of
    mkStl: Result := 'STL';
    mkObj: Result := 'OBJ';
    mkPly: Result := 'PLY';
    mkGltf: Result := 'glTF';
    mkGlb: Result := 'GLB';
    mkBlend: Result := 'BLEND';
  else
    Result := '';
  end;
end;

function MeshHomeCamera: TMeshCamera;
begin
  Result.Azimuth := 35;
  Result.Elevation := 25;
  Result.Scale := 1;
end;

procedure ClearInfo(out AInfo: TMeshInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

function LimitsOf(ATile: Boolean): TMeshLimits;
begin
  if ATile then
  begin
    Result.MaxBytes := TILE_BYTES;
    Result.MaxTris := TILE_TRIS;
    Result.MaxVerts := TILE_VERTS;
    Result.MaxMs := TILE_MS;
  end
  else
  begin
    Result.MaxBytes := VIEW_BYTES;
    Result.MaxTris := VIEW_TRIS;
    Result.MaxVerts := VIEW_VERTS;
    Result.MaxMs := VIEW_MS;
  end;
end;

function KindOfExt(const AExt: string): TMeshKind;
var
  E: string;
begin
  E := LowerCase(AExt);
  if E = '.stl' then
    Result := mkStl
  else if E = '.obj' then
    Result := mkObj
  else if E = '.ply' then
    Result := mkPly
  else if E = '.gltf' then
    Result := mkGltf
  else if E = '.glb' then
    Result := mkGlb
  else if E = '.blend' then
    Result := mkBlend
  else
    Result := mkNone;
end;

function ReadU32(const B: TBytes; O: Integer): Cardinal;
begin
  Result := Cardinal(B[O]) or (Cardinal(B[O + 1]) shl 8) or
    (Cardinal(B[O + 2]) shl 16) or (Cardinal(B[O + 3]) shl 24);
end;

procedure ReadF3(const B: TBytes; O: Integer; out X, Y, Z: Single);
begin
  Move(B[O], X, 4);
  Move(B[O + 4], Y, 4);
  Move(B[O + 8], Z, 4);
end;

function ReadLine(const B: TBytes; ASize: Integer; var APos: Integer;
  out ALine: string): Boolean;
var
  Start, K: Integer;
begin
  if APos >= ASize then
    Exit(False);
  Start := APos;
  while (APos < ASize) and (B[APos] <> 10) and (B[APos] <> 13) do
    Inc(APos);
  K := APos - Start;
  if K > 0 then
    ALine := TEncoding.UTF8.GetString(B, Start, K)
  else
    ALine := '';
  if (APos < ASize) and (B[APos] = 13) then
    Inc(APos);
  if (APos < ASize) and (B[APos] = 10) then
    Inc(APos);
  Result := True;
end;

function NextTok(const S: string; var I: Integer; out Tok: string): Boolean;
var
  N, Start: Integer;
begin
  N := Length(S);
  while (I <= N) and (S[I] <= ' ') do
    Inc(I);
  if I > N then
    Exit(False);
  Start := I;
  while (I <= N) and (S[I] > ' ') do
    Inc(I);
  Tok := Copy(S, Start, I - Start);
  Result := Tok <> '';
end;

function TokEq(const A, B: string): Boolean;
begin
  Result := SameText(A, B);
end;

function ParseF(const S: string; out V: Single): Boolean;
var
  E: Extended;
begin
  Result := TryStrToFloat(Trim(S), E, TFormatSettings.Invariant);
  if Result then
  begin
    if E > 1E20 then
      E := 1E20
    else if E < -1E20 then
      E := -1E20;
    V := E;
  end;
end;

function Halted(const ACancel: TMeshCancel; const AClock: TStopwatch;
  AMaxMs: Cardinal): Boolean;
begin
  Result := AClock.ElapsedMilliseconds >= AMaxMs;
  if Result then
    Exit;
  if Assigned(ACancel) then
    Result := ACancel();
end;

function LoadBytes(const APath: string; AMax: Int64; out ABytes: TBytes;
  out ASize: Int64; out AAge: TDateTime; out AErr: TMeshError): Boolean;
var
  FS: TFileStream;
  Got: Integer;
begin
  Result := False;
  ASize := 0;
  AAge := 0;
  SetLength(ABytes, 0);
  AErr := meBad;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    ASize := TFile.GetSize(APath);
    AAge := TFile.GetLastWriteTime(APath);
  except
    AErr := meBad;
    Exit;
  end;
  if ASize <= 0 then
  begin
    AErr := meEmpty;
    Exit;
  end;
  if ASize > AMax then
  begin
    AErr := meEmpty;
    Exit;
  end;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < ASize then
        ASize := FS.Size;
      if ASize <= 0 then
      begin
        AErr := meEmpty;
        Exit;
      end;
      if ASize > AMax then
      begin
        AErr := meEmpty;
        Exit;
      end;
      SetLength(ABytes, ASize);
      Got := FS.Read(ABytes[0], ASize);
      if Got < ASize then
      begin
        ASize := Got;
        SetLength(ABytes, ASize);
      end;
    finally
      FS.Free;
    end;
  except
    SetLength(ABytes, 0);
    AErr := meBad;
    Exit;
  end;
  if ASize <= 0 then
  begin
    AErr := meEmpty;
    Exit;
  end;
  AErr := meNone;
  Result := True;
end;

function TextStl(const B: TBytes; ASize: Integer): Boolean;
var
  I, N, Start: Integer;
  Head: string;
begin
  Result := False;
  I := 0;
  if (ASize >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    I := 3;
  while (I < ASize) and (B[I] <= 32) do
    Inc(I);
  if I + 5 > ASize then
    Exit;
  SetString(Head, PChar(@B[I]), 0);
  Head := UpperCase(TEncoding.ASCII.GetString(B, I, 5));
  if Head <> 'SOLID' then
    Exit;
  N := ASize;
  Start := I;
  while I < N do
  begin
    if B[I] = 0 then
      Exit;
    Inc(I);
  end;
  I := Start;
  while I + 5 <= ASize do
  begin
    if ((I = Start) or (B[I - 1] <= 32)) and
       (UpCase(Char(B[I])) = 'F') and (UpCase(Char(B[I + 1])) = 'A') and
       (UpCase(Char(B[I + 2])) = 'C') and (UpCase(Char(B[I + 3])) = 'E') and
       (UpCase(Char(B[I + 4])) = 'T') and
       ((I + 5 = ASize) or (B[I + 5] <= 32)) then
    begin
      if (I + 8 <= ASize) and (UpCase(Char(B[I])) = 'F') then
      begin
        { endfacet містить facet лише як частину слова, токен уже відсіяний пробілом. }
      end;
      Exit(True);
    end;
    Inc(I);
  end;
end;

function KeepCap(const ALim: TMeshLimits): Integer;
var
  ByVert: Integer;
begin
  Result := ALim.MaxTris;
  if Result < 1 then
    Result := 1;
  if ALim.MaxVerts < 3 then
    ByVert := 1
  else
    ByVert := ALim.MaxVerts div 3;
  if ByVert < Result then
    Result := ByVert;
  if Result < 1 then
    Result := 1;
end;

procedure PushVert(var AVerts: TArray<TMeshVert>; var ACount: Integer;
  const AV: TMeshVert);
begin
  if ACount >= Length(AVerts) then
  begin
    if Length(AVerts) = 0 then
      SetLength(AVerts, 1024)
    else
      SetLength(AVerts, Length(AVerts) * 2);
  end;
  AVerts[ACount] := AV;
  Inc(ACount);
end;

procedure PushTri(var ATris: TArray<TMeshTri>; var ACount: Integer;
  const AT: TMeshTri);
begin
  if ACount >= Length(ATris) then
  begin
    if Length(ATris) = 0 then
      SetLength(ATris, 1024)
    else
      SetLength(ATris, Length(ATris) * 2);
  end;
  ATris[ACount] := AT;
  Inc(ACount);
end;

function MakeVert(X, Y, Z, NX, NY, NZ: Single; ACol: Cardinal): TMeshVert;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
  Result.Nx := NX;
  Result.Ny := NY;
  Result.Nz := NZ;
  Result.Col := ACol;
end;

function MakeTri(A, B, C: Integer; NX, NY, NZ: Single; ACol: Cardinal): TMeshTri;
begin
  Result.A := A;
  Result.B := B;
  Result.C := C;
  Result.Nx := NX;
  Result.Ny := NY;
  Result.Nz := NZ;
  Result.Col := ACol;
end;

procedure ParseBinaryStl(const B: TBytes; ASize: Integer; const ALim: TMeshLimits;
  const ACancel: TMeshCancel; const AClock: TStopwatch; var AMesh: TMeshData);
var
  Count, Step, Keep, Stored, K, O, VC, TC: Integer;
  Complete: Int64;
  NX, NY, NZ, X0, Y0, Z0, X1, Y1, Z1, X2, Y2, Z2: Single;
  Base: Integer;
begin
  if ASize < 84 then
  begin
    AMesh.Info.Error := meBad;
    Exit;
  end;
  Count := Integer(ReadU32(B, 80));
  if Count < 0 then
  begin
    AMesh.Info.Error := meBad;
    Exit;
  end;
  Complete := (Int64(ASize) - 84) div 50;
  if Int64(Count) <> Complete then
  begin
    AMesh.Info.Error := meBad;
    Exit;
  end;
  AMesh.Info.Kind := mkStl;
  AMesh.Info.Triangles := Count;
  AMesh.Info.Vertices := Int64(Count) * 3;
  if Count = 0 then
  begin
    AMesh.Info.Error := meEmpty;
    Exit;
  end;
  Keep := KeepCap(ALim);
  Step := 1;
  if Count > Keep then
  begin
    Step := Integer(CeilDiv(Count, Keep));
    AMesh.Info.Simplified := True;
  end;
  Stored := (Count + Step - 1) div Step;
  SetLength(AMesh.Verts, Stored * 3);
  SetLength(AMesh.Tris, Stored);
  VC := 0;
  TC := 0;
  for K := 0 to Stored - 1 do
  begin
    if (K and 4095) = 0 then
    begin
      if Assigned(ACancel) and ACancel() then
      begin
        AMesh.Cancelled := True;
        Exit;
      end;
      if AClock.ElapsedMilliseconds >= ALim.MaxMs then
      begin
        AMesh.Info.Simplified := True;
        Break;
      end;
    end;
    O := 84 + K * Step * 50;
    if O + 50 > ASize then
      Break;
    ReadF3(B, O, NX, NY, NZ);
    ReadF3(B, O + 12, X0, Y0, Z0);
    ReadF3(B, O + 24, X1, Y1, Z1);
    ReadF3(B, O + 36, X2, Y2, Z2);
    Base := VC;
    AMesh.Verts[VC] := MakeVert(X0, Y0, Z0, 0, 0, 0, 0);
    Inc(VC);
    AMesh.Verts[VC] := MakeVert(X1, Y1, Z1, 0, 0, 0, 0);
    Inc(VC);
    AMesh.Verts[VC] := MakeVert(X2, Y2, Z2, 0, 0, 0, 0);
    Inc(VC);
    AMesh.Tris[TC] := MakeTri(Base, Base + 1, Base + 2, NX, NY, NZ, 0);
    Inc(TC);
  end;
  SetLength(AMesh.Verts, VC);
  SetLength(AMesh.Tris, TC);
  if TC = 0 then
    AMesh.Info.Error := meEmpty
  else
    AMesh.Info.Error := meNone;
end;

procedure ParseTextStl(const B: TBytes; ASize: Integer; const ALim: TMeshLimits;
  const ACancel: TMeshCancel; const AClock: TStopwatch; var AMesh: TMeshData);
var
  Pos: Integer;
  Line, Tok: string;
  TI, SeenTri, Step, Keep: Integer;
  NX, NY, NZ, X, Y, Z: Single;
  HaveN, InFacet: Boolean;
  VX, VY, VZ: array[0..15] of Single;
  VN: Integer;
  VC, TC: Integer;
  Verts: TArray<TMeshVert>;
  Tris: TArray<TMeshTri>;

  procedure FlushFacet;
  var
    I, Base: Integer;
  begin
    if not InFacet then
      Exit;
    InFacet := False;
    if (VN < 3) or (VN > 16) then
    begin
      VN := 0;
      Exit;
    end;
    for I := 1 to VN - 2 do
    begin
      if (Step > 1) and (SeenTri mod Step <> 0) then
      begin
        Inc(SeenTri);
        Continue;
      end;
      Base := VC;
      PushVert(Verts, VC, MakeVert(VX[0], VY[0], VZ[0], 0, 0, 0, 0));
      PushVert(Verts, VC, MakeVert(VX[I], VY[I], VZ[I], 0, 0, 0, 0));
      PushVert(Verts, VC, MakeVert(VX[I + 1], VY[I + 1], VZ[I + 1], 0, 0, 0, 0));
      PushTri(Tris, TC, MakeTri(Base, Base + 1, Base + 2, NX, NY, NZ, 0));
      Inc(SeenTri);
    end;
    VN := 0;
    HaveN := False;
  end;

  function CountTextTris: Integer;
  var
    P, LocalVN: Integer;
    L, T: string;
    J: Integer;
    Facet: Boolean;
  begin
    Result := 0;
    P := 0;
    LocalVN := 0;
    Facet := False;
    while ReadLine(B, ASize, P, L) do
    begin
      J := 1;
      if not NextTok(L, J, T) then
        Continue;
      if TokEq(T, 'endsolid') then
        Break;
      if TokEq(T, 'facet') then
      begin
        if Facet and (LocalVN >= 3) and (LocalVN <= 16) then
          Inc(Result, LocalVN - 2);
        Facet := True;
        LocalVN := 0;
      end
      else if TokEq(T, 'endfacet') then
      begin
        if Facet and (LocalVN >= 3) and (LocalVN <= 16) then
          Inc(Result, LocalVN - 2);
        Facet := False;
        LocalVN := 0;
      end
      else if TokEq(T, 'vertex') and Facet and (LocalVN < 16) then
        Inc(LocalVN);
    end;
    if Facet and (LocalVN >= 3) and (LocalVN <= 16) then
      Inc(Result, LocalVN - 2);
  end;

begin
  SeenTri := 0;
  AMesh.Info.Triangles := CountTextTris;
  if Assigned(ACancel) and ACancel() then
  begin
    AMesh.Cancelled := True;
    Exit;
  end;
  Keep := KeepCap(ALim);
  Step := 1;
  if AMesh.Info.Triangles > Keep then
  begin
    Step := Integer(CeilDiv(AMesh.Info.Triangles, Keep));
    AMesh.Info.Simplified := True;
  end;
  Pos := 0;
  InFacet := False;
  HaveN := False;
  VN := 0;
  NX := 0;
  NY := 0;
  NZ := 0;
  VC := 0;
  TC := 0;
  SeenTri := 0;
  while ReadLine(B, ASize, Pos, Line) do
  begin
    if (TC and 8191) = 0 then
    begin
      if Assigned(ACancel) and ACancel() then
      begin
        AMesh.Cancelled := True;
        Exit;
      end;
      if AClock.ElapsedMilliseconds >= ALim.MaxMs then
      begin
        AMesh.Info.Simplified := True;
        Break;
      end;
    end;
    TI := 1;
    if not NextTok(Line, TI, Tok) then
      Continue;
    if TokEq(Tok, 'endsolid') then
      Break;
    if TokEq(Tok, 'facet') then
    begin
      FlushFacet;
      InFacet := True;
      HaveN := False;
      VN := 0;
      if NextTok(Line, TI, Tok) and TokEq(Tok, 'normal') then
      begin
        if NextTok(Line, TI, Tok) and ParseF(Tok, NX) and
           NextTok(Line, TI, Tok) and ParseF(Tok, NY) and
           NextTok(Line, TI, Tok) and ParseF(Tok, NZ) then
          HaveN := True
        else
        begin
          NX := 0;
          NY := 0;
          NZ := 0;
        end;
      end;
    end
    else if TokEq(Tok, 'vertex') and InFacet then
    begin
      if VN >= 16 then
        Continue;
      if NextTok(Line, TI, Tok) and ParseF(Tok, X) and
         NextTok(Line, TI, Tok) and ParseF(Tok, Y) and
         NextTok(Line, TI, Tok) and ParseF(Tok, Z) then
      begin
        VX[VN] := X;
        VY[VN] := Y;
        VZ[VN] := Z;
        Inc(VN);
      end;
    end
    else if TokEq(Tok, 'endfacet') then
      FlushFacet;
  end;
  FlushFacet;
  if not HaveN then
  begin
    { нормаль грані вже записана в трикутник; нуль замінить растеризатор. }
  end;
  AMesh.Info.Vertices := AMesh.Info.Triangles * 3;
  AMesh.Info.Kind := mkStl;
  SetLength(Verts, VC);
  SetLength(Tris, TC);
  AMesh.Verts := Verts;
  AMesh.Tris := Tris;
  if TC = 0 then
    AMesh.Info.Error := meEmpty
  else
    AMesh.Info.Error := meNone;
end;

function FaceIndex(const Tok: string; ACount: Integer; out AZero: Integer): Boolean;
var
  Part: string;
  Slash: Integer;
  V: Int64;
begin
  Result := False;
  Part := Tok;
  Slash := Pos('/', Part);
  if Slash > 0 then
    Part := Copy(Part, 1, Slash - 1);
  if Part = '' then
    Exit;
  if not TryStrToInt64(Part, V) then
    Exit;
  if V = 0 then
    Exit;
  if V < 0 then
    V := Int64(ACount) + V
  else
    Dec(V);
  if (V < 0) or (V >= ACount) or (V > High(Integer)) then
    Exit;
  AZero := Integer(V);
  Result := True;
end;

procedure ParseObj(const B: TBytes; ASize: Integer; const ALim: TMeshLimits;
  const ACancel: TMeshCancel; const AClock: TStopwatch; var AMesh: TMeshData);
var
  FullTris, FullVerts: Int64;
  Step: Integer;
  Verts: TArray<TMeshVert>;
  Tris: TArray<TMeshTri>;
  VC, TC, Serial, P, TI, Seen, N, I, Idx, Lines: Integer;
  Line, Tok: string;
  Ids: array[0..15] of Integer;
  HaveV, HaveF: Boolean;
  X, Y, Z: Single;
begin
  FullTris := 0;
  FullVerts := 0;
  HaveV := False;
  HaveF := False;
  P := 0;
  Seen := 0;
  Lines := 0;
  if (ASize >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    P := 3;
  while ReadLine(B, ASize, P, Line) do
  begin
    TI := 1;
    if not NextTok(Line, TI, Tok) then
      Continue;
    if (Tok <> '') and (Tok[1] = '#') then
      Continue;
    if TokEq(Tok, 'v') then
    begin
      HaveV := True;
      if NextTok(Line, TI, Tok) and ParseF(Tok, X) and
         NextTok(Line, TI, Tok) and ParseF(Tok, Y) and
         NextTok(Line, TI, Tok) and ParseF(Tok, Z) then
        Inc(Seen);
    end
    else if TokEq(Tok, 'f') then
    begin
      HaveF := True;
      N := 0;
      while (N < 16) and NextTok(Line, TI, Tok) do
      begin
        if not FaceIndex(Tok, Seen, Idx) then
        begin
          N := -1;
          Break;
        end;
        Inc(N);
      end;
      if NextTok(Line, TI, Tok) then
        N := -1;
      if N >= 3 then
        Inc(FullTris, N - 2);
    end;
    Inc(Lines);
    if (Lines and 8191) = 0 then
    begin
      if Assigned(ACancel) and ACancel() then
      begin
        AMesh.Cancelled := True;
        Exit;
      end;
      if AClock.ElapsedMilliseconds >= ALim.MaxMs then
      begin
        AMesh.Info.Simplified := True;
        Break;
      end;
    end;
  end;
  FullVerts := Seen;
  if AMesh.Cancelled then
    Exit;
  if FullTris <= 0 then
  begin
    AMesh.Info.Error := meNotMesh;
    AMesh.Info.Kind := mkObj;
    AMesh.Info.Vertices := FullVerts;
    Exit;
  end;
  Step := 1;
  if FullTris > KeepCap(ALim) then
  begin
    Step := Integer(CeilDiv(FullTris, KeepCap(ALim)));
    AMesh.Info.Simplified := True;
  end;
  if FullVerts > ALim.MaxVerts then
    AMesh.Info.Simplified := True;
  VC := 0;
  TC := 0;
  Serial := 0;
  Seen := 0;
  Lines := 0;
  P := 0;
  if (ASize >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    P := 3;
  while ReadLine(B, ASize, P, Line) do
  begin
    Inc(Lines);
    if (Lines and 8191) = 0 then
    begin
      if Assigned(ACancel) and ACancel() then
      begin
        AMesh.Cancelled := True;
        Exit;
      end;
      if AClock.ElapsedMilliseconds >= ALim.MaxMs then
      begin
        AMesh.Info.Simplified := True;
        Break;
      end;
    end;
    TI := 1;
    if not NextTok(Line, TI, Tok) then
      Continue;
    if (Tok <> '') and (Tok[1] = '#') then
      Continue;
    if TokEq(Tok, 'v') then
    begin
      if NextTok(Line, TI, Tok) and ParseF(Tok, X) and
         NextTok(Line, TI, Tok) and ParseF(Tok, Y) and
         NextTok(Line, TI, Tok) and ParseF(Tok, Z) then
      begin
        if Seen < ALim.MaxVerts then
          PushVert(Verts, VC, MakeVert(X, Y, Z, 0, 0, 0, 0));
        Inc(Seen);
      end;
    end
    else if TokEq(Tok, 'f') then
    begin
      N := 0;
      while (N < 16) and NextTok(Line, TI, Tok) do
      begin
        if not FaceIndex(Tok, Seen, Idx) or (Idx >= VC) then
        begin
          N := -1;
          Break;
        end;
        Ids[N] := Idx;
        Inc(N);
      end;
      if NextTok(Line, TI, Tok) then
        N := -1;
      if N >= 3 then
        for I := 1 to N - 2 do
        begin
          if (Step <= 1) or (Serial mod Step = 0) then
            PushTri(Tris, TC, MakeTri(Ids[0], Ids[I], Ids[I + 1], 0, 0, 0, 0));
          Inc(Serial);
        end;
    end;
  end;
  if not HaveV and not HaveF and (TC = 0) then
  begin
    AMesh.Info.Error := meNotMesh;
    Exit;
  end;
  SetLength(Verts, VC);
  SetLength(Tris, TC);
  AMesh.Verts := Verts;
  AMesh.Tris := Tris;
  AMesh.Info.Kind := mkObj;
  AMesh.Info.Vertices := FullVerts;
  AMesh.Info.Triangles := FullTris;
  if TC = 0 then
    AMesh.Info.Error := meNotMesh
  else
    AMesh.Info.Error := meNone;
end;

function PlyTyOf(const S: string; out ATy: TPlyTy): Boolean;
begin
  Result := True;
  if SameText(S, 'char') or SameText(S, 'int8') then
    ATy := pyI8
  else if SameText(S, 'uchar') or SameText(S, 'uint8') then
    ATy := pyU8
  else if SameText(S, 'short') or SameText(S, 'int16') then
    ATy := pyI16
  else if SameText(S, 'ushort') or SameText(S, 'uint16') then
    ATy := pyU16
  else if SameText(S, 'int') or SameText(S, 'int32') then
    ATy := pyI32
  else if SameText(S, 'uint') or SameText(S, 'uint32') then
    ATy := pyU32
  else if SameText(S, 'float') or SameText(S, 'float32') then
    ATy := pyF32
  else if SameText(S, 'double') or SameText(S, 'float64') then
    ATy := pyF64
  else
    Result := False;
end;

function PlyTyBytes(ATy: TPlyTy): Integer;
begin
  case ATy of
    pyI8, pyU8: Result := 1;
    pyI16, pyU16: Result := 2;
    pyI32, pyU32, pyF32: Result := 4;
  else
    Result := 8;
  end;
end;

function ReadPlyNum(const B: TBytes; var APos: Integer; ASize: Integer;
  ATy: TPlyTy; ABE: Boolean; out V: Double): Boolean;
var
  N, I: Integer;
  Raw: array[0..7] of Byte;
  U: Cardinal;
  W: UInt64;
  S: Single;
  D: Double;
begin
  Result := False;
  N := PlyTyBytes(ATy);
  if (APos < 0) or (APos + N > ASize) then
    Exit;
  if ABE then
  begin
    for I := 0 to N - 1 do
      Raw[N - 1 - I] := B[APos + I];
  end
  else
    Move(B[APos], Raw[0], N);
  Inc(APos, N);
  case ATy of
    pyI8:
      V := ShortInt(Raw[0]);
    pyU8:
      V := Raw[0];
    pyI16:
      V := SmallInt(Word(Raw[0]) or (Word(Raw[1]) shl 8));
    pyU16:
      V := Word(Raw[0]) or (Word(Raw[1]) shl 8);
    pyI32, pyU32, pyF32:
      begin
        U := Cardinal(Raw[0]) or (Cardinal(Raw[1]) shl 8) or
          (Cardinal(Raw[2]) shl 16) or (Cardinal(Raw[3]) shl 24);
        if ATy = pyF32 then
        begin
          Move(U, S, 4);
          V := S;
        end
        else if ATy = pyI32 then
          V := Integer(U)
        else
          V := U;
      end;
  else
    begin
      W := 0;
      for I := 7 downto 0 do
        W := (W shl 8) or Raw[I];
      Move(W, D, 8);
      V := D;
    end;
  end;
  Result := True;
end;

function ColByteOf(V: Double; AFloat: Boolean): Byte;
begin
  if AFloat and (V <= 1) then
    V := V * 255;
  if V < 0 then
    V := 0
  else if V > 255 then
    V := 255;
  Result := Byte(Round(V));
end;

procedure ParsePly(const B: TBytes; ASize: Integer; const ALim: TMeshLimits;
  const ACancel: TMeshCancel; const AClock: TStopwatch; var AMesh: TMeshData);
type
  TSlot = (slSkip, slX, slY, slZ, slNx, slNy, slNz, slR, slG, slB, slList);
  TProp = record
    Slot: TSlot;
    List: Boolean;
    CountTy, ValTy: TPlyTy;
    FloatVal: Boolean;
  end;
  TElem = record
    Name: string;
    Count: Int64;
    Props: TArray<TProp>;
  end;
var
  Pos, I, P, NProps, Stored, Keep, Step, VC, TC, Fan, Base: Integer;
  Line, Tok, Name: string;
  Prop: TProp;
  IX, IY, IZ, INX, INY, INZ, IR, IG, IB, E, StoredV: Integer;
  VI, N64, KeepV, VStep, FStep: Int64;
  Timed, Ascii, Take: Boolean;
  Fmt: Integer;
  Big, SawPly, SawEnd, HasFace, HasColor, HasNorm: Boolean;
  Elems: TArray<TElem>;
  EC, VertEl, FaceEl: Integer;
  Vals: array[0..31] of Double;
  Idx: array[0..15] of Integer;
  X, Y, Z, NX, NY, NZ: Single;
  CR, CG, CB: Byte;
  Col: Cardinal;
  FullV, FullT, Serial: Int64;
  ListN, K, UseN: Integer;
  Num: Double;

  function AddElem(const AName: string; ACount: Int64): Integer;
  begin
    if EC >= Length(Elems) then
      SetLength(Elems, EC + 8);
    Elems[EC].Name := AName;
    Elems[EC].Count := ACount;
    SetLength(Elems[EC].Props, 0);
    Result := EC;
    Inc(EC);
  end;

  function AddProp(AElem: Integer; const AP: TProp): Boolean;
  begin
    Result := AElem >= 0;
    if not Result then
      Exit;
    NProps := Length(Elems[AElem].Props);
    if NProps >= 32 then
      Exit;
    SetLength(Elems[AElem].Props, NProps + 1);
    Elems[AElem].Props[NProps] := AP;
    Result := True;
  end;

  function ReadAsciiNum(const ATyName: string; AFloat: Boolean; out V: Double): Boolean;
  begin
    Result := NextTok(Line, P, Tok) and ParseF(Tok, X);
    V := X;
    if not Result then
      Exit;
    if not AFloat then
      V := Round(X);
  end;

  function ReadPropValue(const AP: TProp; AAscii: Boolean; out V: Double): Boolean;
  begin
    if AAscii then
      Result := ReadAsciiNum('', AP.FloatVal, V)
    else
      Result := ReadPlyNum(B, Pos, ASize, AP.ValTy, Big, V);
  end;

  function ReadElemValues(const AE: TElem; AAscii: Boolean; out AListN: Integer;
    var AIdx: array of Integer): Boolean;
  var
    PI, LI, LN: Integer;
    Skip: Double;
  begin
    Result := False;
    AListN := 0;
    if AAscii then
    begin
      if not ReadLine(B, ASize, Pos, Line) then
        Exit;
      P := 1;
    end;
    for PI := 0 to High(AE.Props) do
    begin
      if AE.Props[PI].List then
      begin
        if AAscii then
        begin
          if not NextTok(Line, P, Tok) or not TryStrToInt(Tok, LN) then
            Exit;
        end
        else if not ReadPlyNum(B, Pos, ASize, AE.Props[PI].CountTy, Big, Skip) then
          Exit
        else
          LN := Round(Skip);
        if LN < 0 then
          Exit;
        if AE.Props[PI].Slot = slList then
        begin
          AListN := LN;
          if AListN > 16 then
            UseN := 16
          else
            UseN := AListN;
        end
        else
          UseN := 0;
        for LI := 0 to LN - 1 do
        begin
          if AAscii then
          begin
            if not NextTok(Line, P, Tok) or not ParseF(Tok, X) then
              Exit;
            Num := X;
          end
          else if not ReadPlyNum(B, Pos, ASize, AE.Props[PI].ValTy, Big, Num) then
            Exit;
          if (AE.Props[PI].Slot = slList) and (LI < UseN) then
          begin
            if (Num < 0) or (Num > MaxInt) then
              AIdx[LI] := -1
            else
              AIdx[LI] := Round(Num);
          end;
        end;
      end
      else if not ReadPropValue(AE.Props[PI], AAscii, Vals[PI]) then
        Exit;
    end;
    Result := True;
  end;

  function SlotOf(const AName: string; AList: Boolean): TSlot;
  begin
    if AList then
    begin
      if SameText(AName, 'vertex_indices') or SameText(AName, 'vertex_index') then
        Exit(slList);
      Exit(slSkip);
    end;
    if SameText(AName, 'x') then
      Exit(slX);
    if SameText(AName, 'y') then
      Exit(slY);
    if SameText(AName, 'z') then
      Exit(slZ);
    if SameText(AName, 'nx') then
      Exit(slNx);
    if SameText(AName, 'ny') then
      Exit(slNy);
    if SameText(AName, 'nz') then
      Exit(slNz);
    if SameText(AName, 'red') then
      Exit(slR);
    if SameText(AName, 'green') then
      Exit(slG);
    if SameText(AName, 'blue') then
      Exit(slB);
    Result := slSkip;
  end;

begin
  AMesh.Info.Kind := mkPly;
  AMesh.Info.Error := meBad;
  Pos := 0;
  if (ASize >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    Pos := 3;
  Fmt := 0;
  Big := False;
  SawPly := False;
  SawEnd := False;
  EC := 0;
  VertEl := -1;
  FaceEl := -1;
  SetLength(Elems, 0);
  while ReadLine(B, ASize, Pos, Line) do
  begin
    P := 1;
    if not NextTok(Line, P, Tok) then
      Continue;
    if TokEq(Tok, 'comment') or TokEq(Tok, 'obj_info') then
      Continue;
    if TokEq(Tok, 'ply') then
      SawPly := True
    else if TokEq(Tok, 'format') then
    begin
      if not NextTok(Line, P, Tok) then
        Exit;
      if TokEq(Tok, 'ascii') then
        Fmt := 1
      else if TokEq(Tok, 'binary_little_endian') then
        Fmt := 2
      else if TokEq(Tok, 'binary_big_endian') then
      begin
        Fmt := 2;
        Big := True;
      end
      else
        Exit;
    end
    else if TokEq(Tok, 'element') then
    begin
      if not NextTok(Line, P, Name) then
        Exit;
      if not NextTok(Line, P, Tok) then
        Exit;
      if not TryStrToInt64(Tok, FullV) or (FullV < 0) then
        Exit;
      I := AddElem(Name, FullV);
      if SameText(Name, 'vertex') and (VertEl < 0) then
        VertEl := I
      else if SameText(Name, 'face') and (FaceEl < 0) then
        FaceEl := I;
    end
    else if TokEq(Tok, 'property') then
    begin
      if EC = 0 then
        Exit;
      Prop.Slot := slSkip;
      Prop.List := False;
      Prop.FloatVal := False;
      Prop.CountTy := pyU8;
      Prop.ValTy := pyF32;
      if not NextTok(Line, P, Tok) then
        Exit;
      if TokEq(Tok, 'list') then
      begin
        Prop.List := True;
        if not NextTok(Line, P, Tok) or not PlyTyOf(Tok, Prop.CountTy) then
          Exit;
        if not NextTok(Line, P, Tok) or not PlyTyOf(Tok, Prop.ValTy) then
          Exit;
        if not NextTok(Line, P, Name) then
          Exit;
        Prop.Slot := SlotOf(Name, True);
        if not AddProp(EC - 1, Prop) then
          Exit;
      end
      else
      begin
        if not PlyTyOf(Tok, Prop.ValTy) then
          Exit;
        Prop.FloatVal := (Prop.ValTy = pyF32) or (Prop.ValTy = pyF64);
        if not NextTok(Line, P, Name) then
          Exit;
        Prop.Slot := SlotOf(Name, False);
        if not AddProp(EC - 1, Prop) then
          Exit;
      end;
    end
    else if TokEq(Tok, 'end_header') then
    begin
      SawEnd := True;
      Break;
    end;
  end;
  if not SawPly or not SawEnd or (Fmt = 0) or (VertEl < 0) then
    Exit;
  IX := -1;
  IY := -1;
  IZ := -1;
  INX := -1;
  INY := -1;
  INZ := -1;
  IR := -1;
  IG := -1;
  IB := -1;
  for I := 0 to High(Elems[VertEl].Props) do
    case Elems[VertEl].Props[I].Slot of
      slX: IX := I;
      slY: IY := I;
      slZ: IZ := I;
      slNx: INX := I;
      slNy: INY := I;
      slNz: INZ := I;
      slR: IR := I;
      slG: IG := I;
      slB: IB := I;
    end;
  if (IX < 0) or (IY < 0) or (IZ < 0) then
    Exit;
  if not (Elems[VertEl].Props[IX].ValTy in [pyF32, pyF64]) or
     not (Elems[VertEl].Props[IY].ValTy in [pyF32, pyF64]) or
     not (Elems[VertEl].Props[IZ].ValTy in [pyF32, pyF64]) then
    Exit;
  HasNorm := (INX >= 0) and (INY >= 0) and (INZ >= 0);
  HasColor := (IR >= 0) and (IG >= 0) and (IB >= 0);
  HasFace := False;
  if FaceEl >= 0 then
    for I := 0 to High(Elems[FaceEl].Props) do
      if Elems[FaceEl].Props[I].Slot = slList then
        HasFace := True;
  if Elems[VertEl].Count <= 0 then
  begin
    AMesh.Info.Error := meEmpty;
    Exit;
  end;
  FullV := Elems[VertEl].Count;
  AMesh.Info.Vertices := FullV;
  AMesh.HasVertColor := HasColor;
  Ascii := Fmt = 1;
  Keep := KeepCap(ALim);
  Timed := False;
  if HasFace and (FullV > ALim.MaxVerts) then
  begin
    KeepV := ALim.MaxVerts;
    AMesh.Info.Simplified := True;
  end
  else
    KeepV := FullV;
  if (not HasFace) and (FullV > ALim.MaxVerts) then
  begin
    VStep := CeilDiv(FullV, ALim.MaxVerts);
    AMesh.Info.Simplified := True;
  end
  else
    VStep := 1;
  VC := 0;
  TC := 0;
  FullT := 0;
  StoredV := 0;
  for E := 0 to EC - 1 do
  begin
    if Length(Elems[E].Props) = 0 then
      Continue;
    N64 := Elems[E].Count;
    if N64 > ASize then
      N64 := ASize;
    if (E = FaceEl) and HasFace and (N64 > Keep) then
    begin
      FStep := CeilDiv(N64, Keep);
      AMesh.Info.Simplified := True;
    end
    else
      FStep := 1;
    Serial := 0;
    for VI := 0 to N64 - 1 do
    begin
      if (VI and 4095) = 0 then
      begin
        if Assigned(ACancel) and ACancel() then
        begin
          AMesh.Cancelled := True;
          Exit;
        end;
        if AClock.ElapsedMilliseconds >= ALim.MaxMs then
        begin
          AMesh.Info.Simplified := True;
          Timed := True;
          Break;
        end;
      end;
      if not ReadElemValues(Elems[E], Ascii, ListN, Idx) then
      begin
        AMesh.Info.Error := meBad;
        Exit;
      end;
      if E = VertEl then
      begin
        if HasFace then
          Take := VI < KeepV
        else
          Take := (VStep <= 1) or ((VI mod VStep) = 0);
        if Take then
        begin
          X := Vals[IX];
          Y := Vals[IY];
          Z := Vals[IZ];
          if HasNorm then
          begin
            NX := Vals[INX];
            NY := Vals[INY];
            NZ := Vals[INZ];
          end
          else
          begin
            NX := 0;
            NY := 0;
            NZ := 0;
          end;
          if HasColor then
          begin
            CR := ColByteOf(Vals[IR], Elems[VertEl].Props[IR].FloatVal);
            CG := ColByteOf(Vals[IG], Elems[VertEl].Props[IG].FloatVal);
            CB := ColByteOf(Vals[IB], Elems[VertEl].Props[IB].FloatVal);
            Col := $01000000 or (Cardinal(CR) shl 16) or (Cardinal(CG) shl 8) or CB;
          end
          else
            Col := 0;
          PushVert(AMesh.Verts, VC, MakeVert(X, Y, Z, NX, NY, NZ, Col));
        end;
      end
      else if (E = FaceEl) and HasFace then
      begin
        UseN := ListN;
        if UseN > 16 then
          UseN := 16;
        if (UseN >= 3) and ((FStep <= 1) or ((Serial mod FStep) = 0)) then
        begin
          for Fan := 1 to UseN - 2 do
          begin
            if (Idx[0] < 0) or (Idx[Fan] < 0) or (Idx[Fan + 1] < 0) or
               (Idx[0] >= StoredV) or (Idx[Fan] >= StoredV) or
               (Idx[Fan + 1] >= StoredV) then
              Continue;
            Inc(FullT);
            if TC >= Keep then
            begin
              AMesh.Info.Simplified := True;
              Continue;
            end;
            NX := 0;
            NY := 0;
            NZ := 0;
            if HasNorm then
            begin
              NX := (AMesh.Verts[Idx[0]].Nx + AMesh.Verts[Idx[Fan]].Nx +
                AMesh.Verts[Idx[Fan + 1]].Nx) / 3;
              NY := (AMesh.Verts[Idx[0]].Ny + AMesh.Verts[Idx[Fan]].Ny +
                AMesh.Verts[Idx[Fan + 1]].Ny) / 3;
              NZ := (AMesh.Verts[Idx[0]].Nz + AMesh.Verts[Idx[Fan]].Nz +
                AMesh.Verts[Idx[Fan + 1]].Nz) / 3;
              if (NX * NX + NY * NY + NZ * NZ) < 1E-12 then
              begin
                NX := 0;
                NY := 0;
                NZ := 0;
              end;
            end;
            PushTri(AMesh.Tris, TC, MakeTri(Idx[0], Idx[Fan], Idx[Fan + 1],
              NX, NY, NZ, 0));
          end;
        end
        else if UseN >= 3 then
          Inc(FullT, UseN - 2);
        Inc(Serial);
      end;
    end;
    if E = VertEl then
      StoredV := VC;
    if Timed then
      Break;
  end;
  SetLength(AMesh.Verts, VC);
  SetLength(AMesh.Tris, TC);
  AMesh.Info.Triangles := FullT;
  if TC > 0 then
  begin
    AMesh.Info.Points := 0;
    AMesh.Info.Error := meNone;
  end
  else if (VC > 0) and (FullT = 0) then
  begin
    AMesh.Info.Points := FullV;
    AMesh.Info.Triangles := 0;
    AMesh.Info.Error := meNone;
  end
  else
    AMesh.Info.Error := meEmpty;
end;

function MatIdent: TMat4;
var
  I: Integer;
begin
  for I := 0 to 15 do
    Result[I] := 0;
  Result[0] := 1;
  Result[5] := 1;
  Result[10] := 1;
  Result[15] := 1;
end;

function MatMul(const A, B: TMat4): TMat4;
var
  C, R, K: Integer;
  S: Single;
begin
  for C := 0 to 3 do
    for R := 0 to 3 do
    begin
      S := 0;
      for K := 0 to 3 do
        S := S + A[K * 4 + R] * B[C * 4 + K];
      Result[C * 4 + R] := S;
    end;
end;

function MatApply(const M: TMat4; X, Y, Z: Single): TVec3;
begin
  Result.X := M[0] * X + M[4] * Y + M[8] * Z + M[12];
  Result.Y := M[1] * X + M[5] * Y + M[9] * Z + M[13];
  Result.Z := M[2] * X + M[6] * Y + M[10] * Z + M[14];
end;

function MatTRS(TX, TY, TZ, SX, SY, SZ, QX, QY, QZ, QW: Single): TMat4;
var
  L, XX, YY, ZZ, XY, XZ, YZ, WX, WY, WZ: Single;
begin
  Result := MatIdent;
  L := Sqrt(QX * QX + QY * QY + QZ * QZ + QW * QW);
  if L < 1E-8 then
  begin
    QX := 0;
    QY := 0;
    QZ := 0;
    QW := 1;
  end
  else
  begin
    QX := QX / L;
    QY := QY / L;
    QZ := QZ / L;
    QW := QW / L;
  end;
  XX := QX * QX;
  YY := QY * QY;
  ZZ := QZ * QZ;
  XY := QX * QY;
  XZ := QX * QZ;
  YZ := QY * QZ;
  WX := QW * QX;
  WY := QW * QY;
  WZ := QW * QZ;
  Result[0] := (1 - 2 * (YY + ZZ)) * SX;
  Result[1] := (2 * (XY + WZ)) * SX;
  Result[2] := (2 * (XZ - WY)) * SX;
  Result[4] := (2 * (XY - WZ)) * SY;
  Result[5] := (1 - 2 * (XX + ZZ)) * SY;
  Result[6] := (2 * (YZ + WX)) * SY;
  Result[8] := (2 * (XZ + WY)) * SZ;
  Result[9] := (2 * (YZ - WX)) * SZ;
  Result[10] := (1 - 2 * (XX + YY)) * SZ;
  Result[12] := TX;
  Result[13] := TY;
  Result[14] := TZ;
end;

function PctDecode(const S: string): string;
var
  I, N, V: Integer;
begin
  Result := '';
  I := 1;
  N := Length(S);
  while I <= N do
  begin
    if (S[I] = '%') and (I + 2 <= N) and
       TryStrToInt('$' + Copy(S, I + 1, 2), V) then
    begin
      Result := Result + Char(Byte(V));
      Inc(I, 3);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

function UriForeign(const S: string): Boolean;
var
  U: string;
begin
  U := PctDecode(Trim(S));
  if StartsText('data:', U) then
    Exit(False);
  Result := True;
  if U = '' then
    Exit;
  if (Pos('://', U) > 0) or StartsText('http:', U) or StartsText('https:', U) then
    Exit;
  if (U[1] = '/') or (U[1] = '\') then
    Exit;
  if (Length(U) >= 2) and (U[2] = ':') then
    Exit;
  if Pos(':', U) > 0 then
    Exit;
  if StartsText('./', U) then
    Delete(U, 1, 2);
  if (Pos('..', U) > 0) or (Pos('/', U) > 0) or (Pos('\', U) > 0) then
    Exit;
  Result := False;
end;

function JObj(V: TJSONValue): TJSONObject;
begin
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    Result := nil;
end;

function JArr(V: TJSONValue): TJSONArray;
begin
  if V is TJSONArray then
    Result := TJSONArray(V)
  else
    Result := nil;
end;

function JNum(V: TJSONValue; out D: Double): Boolean;
begin
  Result := V is TJSONNumber;
  if Result then
    D := TJSONNumber(V).AsDouble;
end;

function JInt(V: TJSONValue; out N: Integer): Boolean;
var
  D: Double;
begin
  Result := JNum(V, D) and (D >= Low(Integer)) and (D <= High(Integer));
  if Result then
    N := Round(D);
end;

function JsonText(V: TJSONValue): string;
begin
  if V is TJSONString then
    Result := TJSONString(V).Value
  else
    Result := '';
end;

procedure ParseGltf(const APath: string; const B: TBytes; ASize: Integer;
  AKind: TMeshKind; const ALim: TMeshLimits; const ACancel: TMeshCancel;
  const AClock: TStopwatch; var AMesh: TMeshData);
type
  TBuf = record
    Data: TBytes;
    N: Integer;
    Ok: Boolean;
  end;
var
  Root: TJSONObject;
  Parsed: TJSONValue;
  Scenes, Nodes, Meshes, Accessors, Views, Buffers, Materials, Roots: TJSONArray;
  Foreign, BadAcc, Found, Stop: Boolean;
  Bin: TBytes;
  BinN, JsonAt, JsonN, I, K, MeshIx, Keep, Step, VC, TC: Integer;
  SceneIx, CLen, CType, Cursor: Integer;
  Xform: TMat4;
  FullV, FullT, Serial: Int64;
  Dir: string;
  Bufs: TArray<TBuf>;
  Seen: TArray<Boolean>;

  function TakeObject(V: TJSONValue): TJSONObject;
  begin
    if V is TJSONObject then
      Result := TJSONObject(V)
    else
    begin
      V.Free;
      Result := nil;
    end;
  end;

  function DecodeData(const S: string; out Bytes: TBytes): Boolean;
  var
    Mark: Integer;
    Payload: string;
  begin
    Result := False;
    SetLength(Bytes, 0);
    Mark := Pos('base64,', LowerCase(S));
    if Mark <= 0 then
      Exit;
    Payload := Copy(S, Mark + 7, MaxInt);
    try
      Bytes := TNetEncoding.Base64.DecodeStringToBytes(Payload);
    except
      SetLength(Bytes, 0);
      Exit;
    end;
    if (Length(Bytes) = 0) or (Int64(Length(Bytes)) > ALim.MaxBytes) then
    begin
      SetLength(Bytes, 0);
      Exit;
    end;
    Result := True;
  end;

  function ReadSibling(const AName: string; out Bytes: TBytes): Boolean;
  var
    Full: string;
    Sz: Int64;
    FS: TFileStream;
    Got: Integer;
  begin
    Result := False;
    SetLength(Bytes, 0);
    try
      Full := TPath.Combine(Dir, AName);
      if not TFile.Exists(Full) then
        Exit;
      Sz := TFile.GetSize(Full);
      if (Sz <= 0) or (Sz > ALim.MaxBytes) then
        Exit;
      FS := TFileStream.Create(Full, fmOpenRead or fmShareDenyNone);
      try
        SetLength(Bytes, Sz);
        Got := FS.Read(Bytes[0], Sz);
        if Got <> Sz then
        begin
          SetLength(Bytes, 0);
          Exit;
        end;
      finally
        FS.Free;
      end;
      Result := True;
    except
      SetLength(Bytes, 0);
    end;
  end;

  procedure LoadBuffers;
  var
    BI, Decl, N: Integer;
    Obj: TJSONObject;
    Uri, Name: string;
    Raw: TBytes;
  begin
    SetLength(Bufs, 0);
    if Buffers = nil then
      Exit;
    SetLength(Bufs, Buffers.Count);
    for BI := 0 to Buffers.Count - 1 do
    begin
      Bufs[BI].Ok := False;
      Bufs[BI].N := 0;
      Obj := JObj(Buffers.Items[BI]);
      if Obj = nil then
        Continue;
      Decl := 0;
      JInt(Obj.GetValue('byteLength'), Decl);
      Uri := JsonText(Obj.GetValue('uri'));
      Raw := nil;
      N := 0;
      if Uri = '' then
      begin
        if BinN > 0 then
        begin
          N := BinN;
          Raw := Bin;
        end;
      end
      else if StartsText('data:', Uri) then
      begin
        if not DecodeData(Uri, Raw) then
          N := 0
        else
          N := Length(Raw);
      end
      else if UriForeign(Uri) then
        Foreign := True
      else
      begin
        Name := PctDecode(Trim(Uri));
        if StartsText('./', Name) then
          Delete(Name, 1, 2);
        if ReadSibling(Name, Raw) then
          N := Length(Raw);
      end;
      if N > 0 then
      begin
        if (Decl > 0) and (Decl < N) then
          N := Decl;
        SetLength(Bufs[BI].Data, N);
        Move(Raw[0], Bufs[BI].Data[0], N);
        Bufs[BI].N := N;
        Bufs[BI].Ok := True;
      end;
    end;
  end;

  function OpenAcc(AccIx: Integer; out Data: TBytes; out Off, Count, Stride, Comp,
    CSize: Integer): Boolean;
  var
    Acc, View: TJSONObject;
    TypeName: string;
    BvIx, BufIx, AccOff, ViewOff, ViewStride, NComp: Integer;
    Need: Int64;
  begin
    Result := False;
    SetLength(Data, 0);
    Off := 0;
    Count := 0;
    Stride := 0;
    Comp := 0;
    CSize := 0;
    if (Accessors = nil) or (AccIx < 0) or (AccIx >= Accessors.Count) then
      Exit;
    Acc := JObj(Accessors.Items[AccIx]);
    if Acc = nil then
      Exit;
    TypeName := JsonText(Acc.GetValue('type'));
    if TypeName = 'SCALAR' then
      NComp := 1
    else if TypeName = 'VEC2' then
      NComp := 2
    else if TypeName = 'VEC3' then
      NComp := 3
    else if TypeName = 'VEC4' then
      NComp := 4
    else
      Exit;
    if not JInt(Acc.GetValue('componentType'), Comp) then
      Exit;
    if not JInt(Acc.GetValue('count'), Count) or (Count < 1) then
      Exit;
    case Comp of
      5120, 5121: CSize := 1;
      5122, 5123: CSize := 2;
      5125, 5126: CSize := 4;
    else
      Exit;
    end;
    if not JInt(Acc.GetValue('bufferView'), BvIx) then
      Exit;
    if (Views = nil) or (BvIx < 0) or (BvIx >= Views.Count) then
      Exit;
    View := JObj(Views.Items[BvIx]);
    if View = nil then
      Exit;
    if not JInt(View.GetValue('buffer'), BufIx) then
      Exit;
    if (BufIx < 0) or (BufIx > High(Bufs)) or not Bufs[BufIx].Ok then
      Exit;
    ViewOff := 0;
    AccOff := 0;
    ViewStride := 0;
    JInt(View.GetValue('byteOffset'), ViewOff);
    JInt(Acc.GetValue('byteOffset'), AccOff);
    JInt(View.GetValue('byteStride'), ViewStride);
    if ViewStride <= 0 then
      Stride := NComp * CSize
    else
      Stride := ViewStride;
    if (Stride < NComp * CSize) or (ViewOff < 0) or (AccOff < 0) then
      Exit;
    Off := ViewOff + AccOff;
    Need := Int64(Off) + Int64(Count - 1) * Stride + Int64(NComp) * CSize;
    if (Need < 0) or (Need > Bufs[BufIx].N) then
      Exit;
    Data := Bufs[BufIx].Data;
    Result := True;
  end;

  function BufferReady(AccIx: Integer): Boolean;
  var
    Acc, View: TJSONObject;
    BvIx, BufIx: Integer;
  begin
    Result := False;
    if (Accessors = nil) or (AccIx < 0) or (AccIx >= Accessors.Count) then
      Exit;
    Acc := JObj(Accessors.Items[AccIx]);
    if (Acc = nil) or not JInt(Acc.GetValue('bufferView'), BvIx) then
      Exit;
    if (Views = nil) or (BvIx < 0) or (BvIx >= Views.Count) then
      Exit;
    View := JObj(Views.Items[BvIx]);
    if (View = nil) or not JInt(View.GetValue('buffer'), BufIx) then
      Exit;
    Result := (BufIx >= 0) and (BufIx <= High(Bufs)) and Bufs[BufIx].Ok;
  end;

  function ReadF32(const Data: TBytes; O: Integer; out V: Single): Boolean;
  begin
    Result := (O >= 0) and (O + 4 <= Length(Data));
    if Result then
      Move(Data[O], V, 4);
  end;

  function ReadIndex(const Data: TBytes; O, AComp: Integer; out V: Integer): Boolean;
  var
    U: Cardinal;
  begin
    Result := False;
    V := -1;
    case AComp of
      5121:
        if (O >= 0) and (O < Length(Data)) then
        begin
          V := Data[O];
          Result := True;
        end;
      5123:
        if (O >= 0) and (O + 2 <= Length(Data)) then
        begin
          V := Word(Data[O]) or (Word(Data[O + 1]) shl 8);
          Result := True;
        end;
      5125:
        if (O >= 0) and (O + 4 <= Length(Data)) then
        begin
          U := Cardinal(Data[O]) or (Cardinal(Data[O + 1]) shl 8) or
            (Cardinal(Data[O + 2]) shl 16) or (Cardinal(Data[O + 3]) shl 24);
          if U <= Cardinal(MaxInt) then
          begin
            V := Integer(U);
            Result := True;
          end;
        end;
    end;
  end;

  function NodeMat(Node: TJSONObject): TMat4;
  var
    Arr: TJSONArray;
    KI: Integer;
    D: Double;
    TX, TY, TZ, SX, SY, SZ, QX, QY, QZ, QW: Single;
  begin
    Arr := JArr(Node.GetValue('matrix'));
    if (Arr <> nil) and (Arr.Count >= 16) then
    begin
      Result := MatIdent;
      for KI := 0 to 15 do
        if JNum(Arr.Items[KI], D) then
          Result[KI] := D;
      Exit;
    end;
    TX := 0;
    TY := 0;
    TZ := 0;
    SX := 1;
    SY := 1;
    SZ := 1;
    QX := 0;
    QY := 0;
    QZ := 0;
    QW := 1;
    Arr := JArr(Node.GetValue('translation'));
    if (Arr <> nil) and (Arr.Count >= 3) then
    begin
      if JNum(Arr.Items[0], D) then TX := D;
      if JNum(Arr.Items[1], D) then TY := D;
      if JNum(Arr.Items[2], D) then TZ := D;
    end;
    Arr := JArr(Node.GetValue('scale'));
    if (Arr <> nil) and (Arr.Count >= 3) then
    begin
      if JNum(Arr.Items[0], D) then SX := D;
      if JNum(Arr.Items[1], D) then SY := D;
      if JNum(Arr.Items[2], D) then SZ := D;
    end;
    Arr := JArr(Node.GetValue('rotation'));
    if (Arr <> nil) and (Arr.Count >= 4) then
    begin
      if JNum(Arr.Items[0], D) then QX := D;
      if JNum(Arr.Items[1], D) then QY := D;
      if JNum(Arr.Items[2], D) then QZ := D;
      if JNum(Arr.Items[3], D) then QW := D;
    end;
    Result := MatTRS(TX, TY, TZ, SX, SY, SZ, QX, QY, QZ, QW);
  end;

  function FlatColor(Prim: TJSONObject): Cardinal;
  var
    MI: Integer;
    Mat, Pbr: TJSONObject;
    Arr: TJSONArray;
    R, G, Bc, D: Double;
    RB, GB, BB: Byte;
  begin
    Result := 0;
    if not JInt(Prim.GetValue('material'), MI) then
      Exit;
    if (Materials = nil) or (MI < 0) or (MI >= Materials.Count) then
      Exit;
    Mat := JObj(Materials.Items[MI]);
    if Mat = nil then
      Exit;
    Pbr := JObj(Mat.GetValue('pbrMetallicRoughness'));
    if (Pbr = nil) or (Pbr.GetValue('baseColorTexture') <> nil) then
      Exit;
    Arr := JArr(Pbr.GetValue('baseColorFactor'));
    if (Arr = nil) or (Arr.Count < 3) then
      Exit;
    R := 1;
    G := 1;
    Bc := 1;
    if JNum(Arr.Items[0], D) then R := D;
    if JNum(Arr.Items[1], D) then G := D;
    if JNum(Arr.Items[2], D) then Bc := D;
    if R < 0 then R := 0 else if R > 1 then R := 1;
    if G < 0 then G := 0 else if G > 1 then G := 1;
    if Bc < 0 then Bc := 0 else if Bc > 1 then Bc := 1;
    RB := Byte(Round(R * 255));
    GB := Byte(Round(G * 255));
    BB := Byte(Round(Bc * 255));
    Result := $01000000 or (Cardinal(RB) shl 16) or (Cardinal(GB) shl 8) or BB;
  end;

  function MeshDrawable(AIx: Integer): Boolean;
  var
    Mesh, Prim, Attr: TJSONObject;
    Prims: TJSONArray;
    P: Integer;
  begin
    Result := False;
    if (Meshes = nil) or (AIx < 0) or (AIx >= Meshes.Count) then
      Exit;
    Mesh := JObj(Meshes.Items[AIx]);
    if Mesh = nil then
      Exit;
    Prims := JArr(Mesh.GetValue('primitives'));
    if Prims = nil then
      Exit;
    for P := 0 to Prims.Count - 1 do
    begin
      Prim := JObj(Prims.Items[P]);
      if Prim = nil then
        Continue;
      Attr := JObj(Prim.GetValue('attributes'));
      if (Attr = nil) or (Attr.GetValue('JOINTS_0') <> nil) then
        Continue;
      if Attr.GetValue('POSITION') <> nil then
        Exit(True);
    end;
  end;

  function TriCount(AMode, N: Integer): Integer;
  begin
    if N < 3 then
      Exit(0);
    case AMode of
      4: Result := N div 3;
      5, 6: Result := N - 2;
    else
      Result := 0;
    end;
  end;

  procedure Walk(NodeIx: Integer; const Parent: TMat4);
  var
    Node: TJSONObject;
    Local, World: TMat4;
    Kids: TJSONArray;
    CI, MeshN, Child: Integer;
  begin
    if Found or Stop or (NodeIx < 0) or (Nodes = nil) or (NodeIx >= Nodes.Count) then
      Exit;
    if (NodeIx <= High(Seen)) and Seen[NodeIx] then
      Exit;
    if NodeIx <= High(Seen) then
      Seen[NodeIx] := True;
    Node := JObj(Nodes.Items[NodeIx]);
    if Node = nil then
      Exit;
    Local := NodeMat(Node);
    World := MatMul(Parent, Local);
    if (Node.GetValue('skin') = nil) and JInt(Node.GetValue('mesh'), MeshN) and
       MeshDrawable(MeshN) then
    begin
      Found := True;
      MeshIx := MeshN;
      Xform := World;
      Exit;
    end;
    Kids := JArr(Node.GetValue('children'));
    if Kids = nil then
      Exit;
    for CI := 0 to Kids.Count - 1 do
      if JInt(Kids.Items[CI], Child) then
        Walk(Child, World);
  end;

  procedure ConsumePrim(Prim: TJSONObject; AStore: Boolean);
  var
    Attr, Acc: TJSONObject;
    Mode, PosAcc, IndAcc, N, T, IA, IB, IC: Integer;
    PosD, IndD: TBytes;
    PosOff, PosCount, PosStride, PosComp, PosSize: Integer;
    IndOff, IndCount, IndStride, IndComp, IndSize: Integer;
    HasInd: Boolean;
    Col: Cardinal;
    P0, P1, P2: TVec3;
    X0, Y0, Z0: Single;
    Base: Integer;

    function AtIndex(AIndex: Integer; out V: Integer): Boolean;
    begin
      if HasInd then
        Result := ReadIndex(IndD, IndOff + AIndex * IndStride, IndComp, V)
      else
      begin
        V := AIndex;
        Result := (AIndex >= 0) and (AIndex < PosCount);
      end;
    end;

    procedure Note(A, Bp, C: Integer);
    begin
      if not AStore then
      begin
        Inc(FullT);
        Exit;
      end;
      if (Step > 1) and ((Serial mod Step) <> 0) then
      begin
        Inc(Serial);
        Exit;
      end;
      Inc(Serial);
      if (A < 0) or (Bp < 0) or (C < 0) or (A >= PosCount) or (Bp >= PosCount) or
         (C >= PosCount) then
        Exit;
      if TC >= Keep then
      begin
        AMesh.Info.Simplified := True;
        Exit;
      end;
      if not ReadF32(PosD, PosOff + A * PosStride, X0) or
         not ReadF32(PosD, PosOff + A * PosStride + 4, Y0) or
         not ReadF32(PosD, PosOff + A * PosStride + 8, Z0) then
        Exit;
      P0 := MatApply(Xform, X0, Y0, Z0);
      if not ReadF32(PosD, PosOff + Bp * PosStride, X0) or
         not ReadF32(PosD, PosOff + Bp * PosStride + 4, Y0) or
         not ReadF32(PosD, PosOff + Bp * PosStride + 8, Z0) then
        Exit;
      P1 := MatApply(Xform, X0, Y0, Z0);
      if not ReadF32(PosD, PosOff + C * PosStride, X0) or
         not ReadF32(PosD, PosOff + C * PosStride + 4, Y0) or
         not ReadF32(PosD, PosOff + C * PosStride + 8, Z0) then
        Exit;
      P2 := MatApply(Xform, X0, Y0, Z0);
      Base := VC;
      PushVert(AMesh.Verts, VC, MakeVert(P0.X, P0.Y, P0.Z, 0, 0, 0, 0));
      PushVert(AMesh.Verts, VC, MakeVert(P1.X, P1.Y, P1.Z, 0, 0, 0, 0));
      PushVert(AMesh.Verts, VC, MakeVert(P2.X, P2.Y, P2.Z, 0, 0, 0, 0));
      PushTri(AMesh.Tris, TC, MakeTri(Base, Base + 1, Base + 2, 0, 0, 0, Col));
    end;

  begin
    if Stop or (Prim = nil) then
      Exit;
    Attr := JObj(Prim.GetValue('attributes'));
    if Attr = nil then
      Exit;
    if Attr.GetValue('JOINTS_0') <> nil then
      Exit;
    Mode := 4;
    JInt(Prim.GetValue('mode'), Mode);
    if (Mode <> 4) and (Mode <> 5) and (Mode <> 6) then
      Exit;
    if not JInt(Attr.GetValue('POSITION'), PosAcc) then
      Exit;
    if not OpenAcc(PosAcc, PosD, PosOff, PosCount, PosStride, PosComp, PosSize) then
    begin
      if BufferReady(PosAcc) then
        BadAcc := True;
      Exit;
    end;
    Acc := JObj(Accessors.Items[PosAcc]);
    if (Acc = nil) or (JsonText(Acc.GetValue('type')) <> 'VEC3') or (PosComp <> 5126) or
       (PosStride < 12) then
    begin
      BadAcc := True;
      Exit;
    end;
    HasInd := JInt(Prim.GetValue('indices'), IndAcc);
    if HasInd then
    begin
      if not OpenAcc(IndAcc, IndD, IndOff, IndCount, IndStride, IndComp, IndSize) then
      begin
        if BufferReady(IndAcc) then
          BadAcc := True;
        Exit;
      end;
      Acc := JObj(Accessors.Items[IndAcc]);
      if (Acc = nil) or (JsonText(Acc.GetValue('type')) <> 'SCALAR') or
         ((IndComp <> 5121) and (IndComp <> 5123) and (IndComp <> 5125)) then
      begin
        BadAcc := True;
        Exit;
      end;
      N := IndCount;
    end
    else
      N := PosCount;
    if not AStore then
    begin
      Inc(FullV, PosCount);
      Inc(FullT, TriCount(Mode, N));
      Exit;
    end;
    Col := FlatColor(Prim);
    if Mode = 4 then
    begin
      T := 0;
      while (not Stop) and (T + 2 < N) do
      begin
        if (T and 4095) = 0 then
        begin
          if Assigned(ACancel) and ACancel() then
          begin
            AMesh.Cancelled := True;
            Stop := True;
            Exit;
          end;
          if AClock.ElapsedMilliseconds >= ALim.MaxMs then
          begin
            AMesh.Info.Simplified := True;
            Stop := True;
            Exit;
          end;
        end;
        if AtIndex(T, IA) and AtIndex(T + 1, IB) and AtIndex(T + 2, IC) then
          Note(IA, IB, IC)
        else
          Note(-1, -1, -1);
        Inc(T, 3);
      end;
    end
    else if Mode = 5 then
    begin
      T := 0;
      while (not Stop) and (T + 2 < N) do
      begin
        if (T and 4095) = 0 then
        begin
          if Assigned(ACancel) and ACancel() then
          begin
            AMesh.Cancelled := True;
            Stop := True;
            Exit;
          end;
          if AClock.ElapsedMilliseconds >= ALim.MaxMs then
          begin
            AMesh.Info.Simplified := True;
            Stop := True;
            Exit;
          end;
        end;
        if (T and 1) = 0 then
        begin
          if AtIndex(T, IA) and AtIndex(T + 1, IB) and AtIndex(T + 2, IC) then
            Note(IA, IB, IC)
          else
            Note(-1, -1, -1);
        end
        else if AtIndex(T + 1, IA) and AtIndex(T, IB) and AtIndex(T + 2, IC) then
          Note(IA, IB, IC)
        else
          Note(-1, -1, -1);
        Inc(T);
      end;
    end
    else
    begin
      T := 1;
      while (not Stop) and (T + 1 < N) do
      begin
        if AtIndex(0, IA) and AtIndex(T, IB) and AtIndex(T + 1, IC) then
          Note(IA, IB, IC)
        else
          Note(-1, -1, -1);
        Inc(T);
      end;
    end;
  end;

  procedure ReadMesh(AStore: Boolean);
  var
    Mesh, Prim: TJSONObject;
    Prims: TJSONArray;
    P: Integer;
  begin
    if (Meshes = nil) or (MeshIx < 0) or (MeshIx >= Meshes.Count) then
      Exit;
    Mesh := JObj(Meshes.Items[MeshIx]);
    if Mesh = nil then
      Exit;
    Prims := JArr(Mesh.GetValue('primitives'));
    if Prims = nil then
      Exit;
    for P := 0 to Prims.Count - 1 do
    begin
      if Stop then
        Exit;
      Prim := JObj(Prims.Items[P]);
      ConsumePrim(Prim, AStore);
    end;
  end;

begin
  AMesh.Info.Kind := AKind;
  AMesh.Info.Error := meBad;
  Root := nil;
  Foreign := False;
  BadAcc := False;
  Found := False;
  Stop := False;
  MeshIx := -1;
  Xform := MatIdent;
  FullV := 0;
  FullT := 0;
  Serial := 0;
  VC := 0;
  TC := 0;
  BinN := 0;
  JsonAt := 0;
  JsonN := 0;
  SetLength(Bin, 0);
  Dir := ExtractFileDir(APath);
  if AKind = mkGlb then
  begin
    if (ASize < 20) or (B[0] <> Ord('g')) or (B[1] <> Ord('l')) or
       (B[2] <> Ord('T')) or (B[3] <> Ord('F')) then
      Exit;
    Cursor := 12;
    while Cursor + 8 <= ASize do
    begin
      CLen := Integer(ReadU32(B, Cursor));
      CType := Integer(ReadU32(B, Cursor + 4));
      if (CLen < 0) or (Int64(Cursor) + 8 + CLen > ASize) then
        Break;
      if (CType = Integer($4E4F534A)) and (JsonN = 0) then
      begin
        JsonAt := Cursor + 8;
        JsonN := CLen;
      end
      else if (CType = Integer($004E4942)) and (BinN = 0) then
      begin
        SetLength(Bin, CLen);
        if CLen > 0 then
          Move(B[Cursor + 8], Bin[0], CLen);
        BinN := CLen;
      end;
      Inc(Cursor, 8 + CLen);
    end;
    if JsonN <= 0 then
      Exit;
    while (JsonN > 0) and (B[JsonAt + JsonN - 1] <= 32) do
      Dec(JsonN);
  end
  else
  begin
    if (ASize >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
      JsonAt := 3;
    JsonN := ASize - JsonAt;
    while (JsonN > 0) and (B[JsonAt + JsonN - 1] <= 32) do
      Dec(JsonN);
    if JsonN <= 0 then
      Exit;
  end;
  { ALength у System.JSON — це кінець зрізу, не довжина. Для GLB зсув не нульовий. }
  Parsed := TJSONObject.ParseJSONValue(B, JsonAt, JsonAt + JsonN, True);
  Root := TakeObject(Parsed);
  if Root = nil then
    Exit;
  try
    Accessors := JArr(Root.GetValue('accessors'));
    Views := JArr(Root.GetValue('bufferViews'));
    Buffers := JArr(Root.GetValue('buffers'));
    Meshes := JArr(Root.GetValue('meshes'));
    Nodes := JArr(Root.GetValue('nodes'));
    Scenes := JArr(Root.GetValue('scenes'));
    Materials := JArr(Root.GetValue('materials'));
    LoadBuffers;
    if (Scenes <> nil) and (Scenes.Count > 0) and (Nodes <> nil) and (Nodes.Count > 0) then
    begin
      SceneIx := 0;
      if JInt(Root.GetValue('scene'), SceneIx) and
         ((SceneIx < 0) or (SceneIx >= Scenes.Count)) then
        SceneIx := 0;
      if (SceneIx >= 0) and (SceneIx < Scenes.Count) and
         (JObj(Scenes.Items[SceneIx]) <> nil) then
      begin
        SetLength(Seen, Nodes.Count);
        Roots := JArr(JObj(Scenes.Items[SceneIx]).GetValue('nodes'));
        if Roots <> nil then
          for I := 0 to Roots.Count - 1 do
            if JInt(Roots.Items[I], K) then
            begin
              Walk(K, MatIdent);
              if Found then
                Break;
            end;
      end;
    end
    else if (Meshes <> nil) and (Meshes.Count > 0) and MeshDrawable(0) then
    begin
      Found := True;
      MeshIx := 0;
      Xform := MatIdent;
    end;
    if not Found then
    begin
      if Foreign then
        AMesh.Info.Error := meNoView
      else
        AMesh.Info.Error := meEmpty;
      Exit;
    end;
    ReadMesh(False);
    if AMesh.Cancelled then
      Exit;
    Keep := KeepCap(ALim);
    Step := 1;
    if FullT > Keep then
    begin
      Step := Integer(CeilDiv(FullT, Keep));
      if Step < 1 then
        Step := 1;
      AMesh.Info.Simplified := True;
    end;
    Serial := 0;
    VC := 0;
    TC := 0;
    ReadMesh(True);
    if AMesh.Cancelled then
      Exit;
    SetLength(AMesh.Verts, VC);
    SetLength(AMesh.Tris, TC);
    AMesh.Info.Vertices := FullV;
    AMesh.Info.Triangles := FullT;
    AMesh.Info.Points := 0;
    if TC > 0 then
      AMesh.Info.Error := meNone
    else if Foreign then
      AMesh.Info.Error := meNoView
    else if BadAcc then
      AMesh.Info.Error := meBad
    else
      AMesh.Info.Error := meEmpty;
  finally
    Root.Free;
  end;
end;

procedure ParseBlend(const B: TBytes; ASize: Integer; var AMesh: TMeshData);
const
  SCAN = 2 * 1024 * 1024;
var
  InS: TBytesStream;
  Z: TZDecompressionStream;
  UseZ, Big: Boolean;
  At: Int64;
  Ptr: Integer;

  function Pull(var Dest; N: Integer): Boolean;
  var
    Got, Need: Integer;
    P: PByte;
  begin
    Result := False;
    if N <= 0 then
      Exit(True);
    if not UseZ then
    begin
      if (At < 0) or (At + N > ASize) then
        Exit;
      Move(B[Integer(At)], Dest, N);
      Inc(At, N);
      Exit(True);
    end;
    P := @Dest;
    Need := N;
    while Need > 0 do
    begin
      Got := Z.Read(P^, Need);
      if Got <= 0 then
        Exit;
      Inc(P, Got);
      Dec(Need, Got);
    end;
    Inc(At, N);
    Result := True;
  end;

  function SkipRaw(N: Int64): Boolean;
  var
    Buf: array[0..4095] of Byte;
    Left: Int64;
    M: Integer;
  begin
    Result := False;
    if N < 0 then
      Exit;
    if N = 0 then
      Exit(True);
    if not UseZ then
    begin
      if At + N > ASize then
        Exit;
      Inc(At, N);
      Exit(True);
    end;
    Left := N;
    while Left > 0 do
    begin
      if Left > SizeOf(Buf) then
        M := SizeOf(Buf)
      else
        M := Integer(Left);
      if not Pull(Buf, M) then
        Exit;
      Dec(Left, M);
    end;
    Result := True;
  end;

  function ReadI32(out V: Integer): Boolean;
  var
    D: array[0..3] of Byte;
    U: Cardinal;
  begin
    Result := Pull(D, 4);
    if not Result then
      Exit;
    if Big then
      U := (Cardinal(D[0]) shl 24) or (Cardinal(D[1]) shl 16) or
        (Cardinal(D[2]) shl 8) or D[3]
    else
      U := Cardinal(D[0]) or (Cardinal(D[1]) shl 8) or
        (Cardinal(D[2]) shl 16) or (Cardinal(D[3]) shl 24);
    V := Integer(U);
  end;

  procedure Run;
  var
    Head: array[0..11] of Byte;
    Code: array[0..3] of Byte;
    Len, W, H: Integer;
    Pixels: TBytes;
  begin
    if not Pull(Head, 12) then
      Exit;
    if (Head[0] <> Ord('B')) or (Head[1] <> Ord('L')) or (Head[2] <> Ord('E')) or
       (Head[3] <> Ord('N')) or (Head[4] <> Ord('D')) or (Head[5] <> Ord('E')) or
       (Head[6] <> Ord('R')) then
      Exit;
    if Head[7] = Ord('_') then
      Ptr := 4
    else if Head[7] = Ord('-') then
      Ptr := 8
    else
      Exit;
    if Head[8] = Ord('v') then
      Big := False
    else if Head[8] = Ord('V') then
      Big := True
    else
      Exit;
    while At < SCAN do
    begin
      if not Pull(Code, 4) then
        Exit;
      if not ReadI32(Len) or (Len < 0) then
        Exit;
      if not SkipRaw(Ptr + 8) then
        Exit;
      if (Code[0] = Ord('E')) and (Code[1] = Ord('N')) and (Code[2] = Ord('D')) and
         (Code[3] = Ord('B')) then
        Exit;
      if (Code[0] = Ord('T')) and (Code[1] = Ord('E')) and (Code[2] = Ord('S')) and
         (Code[3] = Ord('T')) then
      begin
        if Len < 8 then
          Exit;
        if not ReadI32(W) or not ReadI32(H) then
          Exit;
        if (W < 1) or (H < 1) or (W > 1024) or (H > 1024) then
          Exit;
        if Int64(Len) <> 8 + Int64(W) * Int64(H) * 4 then
          Exit;
        SetLength(Pixels, W * H * 4);
        if (Length(Pixels) > 0) and not Pull(Pixels[0], Length(Pixels)) then
          Exit;
        AMesh.Pic := Pixels;
        AMesh.PicW := W;
        AMesh.PicH := H;
        AMesh.Info.PicW := W;
        AMesh.Info.PicH := H;
        AMesh.Info.Picture := True;
        AMesh.Info.Error := meNone;
        Exit;
      end;
      if At + Int64(Len) >= SCAN then
        Exit;
      if not SkipRaw(Len) then
        Exit;
    end;
  end;

begin
  AMesh.Info.Kind := mkBlend;
  AMesh.Info.Error := meBlend;
  AMesh.Info.Picture := False;
  AMesh.PicW := 0;
  AMesh.PicH := 0;
  SetLength(AMesh.Pic, 0);
  if ASize < 4 then
    Exit;
  if (ASize >= 4) and (B[0] = $28) and (B[1] = $B5) and (B[2] = $2F) and (B[3] = $FD) then
    Exit;
  UseZ := (ASize >= 2) and (B[0] = $1F) and (B[1] = $8B);
  At := 0;
  Big := False;
  Ptr := 4;
  InS := nil;
  Z := nil;
  try
    if UseZ then
    begin
      InS := TBytesStream.Create(B);
      try
        Z := TZDecompressionStream.Create(InS, 31, False);
        try
          Run;
        finally
          Z.Free;
          Z := nil;
        end;
      finally
        InS.Free;
        InS := nil;
      end;
    end
    else
      Run;
  except
    AMesh.Info.Error := meBlend;
    AMesh.Info.Picture := False;
    AMesh.PicW := 0;
    AMesh.PicH := 0;
    SetLength(AMesh.Pic, 0);
  end;
end;

procedure StlToYUp(var AMesh: TMeshData);
var
  I: Integer;
  Y, NY: Single;
begin
  { Blender і CAD пишуть STL із Z вгору. OBJ і glTF тут із Y вгору.
    (x, y, z) -> (x, z, -y): це поворот, обхід граней не змінюється. }
  for I := 0 to High(AMesh.Verts) do
  begin
    Y := AMesh.Verts[I].Y;
    AMesh.Verts[I].Y := AMesh.Verts[I].Z;
    AMesh.Verts[I].Z := -Y;
  end;
  for I := 0 to High(AMesh.Tris) do
  begin
    NY := AMesh.Tris[I].Ny;
    AMesh.Tris[I].Ny := AMesh.Tris[I].Nz;
    AMesh.Tris[I].Nz := -NY;
  end;
end;

procedure ParseMesh(const APath: string; const ABytes: TBytes; ASize: Integer;
  AKind: TMeshKind; const ALim: TMeshLimits; const ACancel: TMeshCancel;
  const AClock: TStopwatch; var AMesh: TMeshData);
begin
  AMesh.Info.Kind := AKind;
  case AKind of
    mkStl:
      if TextStl(ABytes, ASize) then
        ParseTextStl(ABytes, ASize, ALim, ACancel, AClock, AMesh)
      else
        ParseBinaryStl(ABytes, ASize, ALim, ACancel, AClock, AMesh);
    mkObj:
      ParseObj(ABytes, ASize, ALim, ACancel, AClock, AMesh);
    mkPly:
      ParsePly(ABytes, ASize, ALim, ACancel, AClock, AMesh);
    mkGltf, mkGlb:
      ParseGltf(APath, ABytes, ASize, AKind, ALim, ACancel, AClock, AMesh);
    mkBlend:
      ParseBlend(ABytes, ASize, AMesh);
  else
    AMesh.Info.Error := meBad;
  end;
  if (AKind = mkStl) and (AMesh.Info.Error = meNone) and not AMesh.Cancelled then
    StlToYUp(AMesh);
end;

procedure BuildCamera(const ACam: TMeshCamera; out ARight, AUp, AEye: TVec3);
var
  Az, El, Cx, Cy, Cz: Single;
  Forward, WorldUp: TVec3;
begin
  Az := ACam.Azimuth * Pi / 180;
  El := ACam.Elevation * Pi / 180;
  Cx := Cos(El) * Sin(Az);
  Cy := Sin(El);
  Cz := Cos(El) * Cos(Az);
  AEye := VNorm(V3(Cx, Cy, Cz));
  Forward := V3(-AEye.X, -AEye.Y, -AEye.Z);
  WorldUp := V3(0, 1, 0);
  if Abs(VDot(Forward, WorldUp)) > 0.98 then
    WorldUp := V3(0, 0, 1);
  ARight := VNorm(VCross(Forward, WorldUp));
  AUp := VNorm(VCross(AEye, ARight));
end;

function ShadeOf(const ANorm: TVec3; const ALight: TVec3): Single;
var
  N: TVec3;
  D, Back: Single;
  Facing: Boolean;
begin
  N := VNorm(ANorm);
  if VLen(N) < 1E-8 then
    Exit(0.72);
  D := VDot(N, ALight);
  Facing := N.Z >= 0;
  if D < 0 then
    D := 0;
  Result := 0.40 + 0.60 * D;
  if not Facing then
  begin
    Back := VDot(N, V3(-ALight.X, -ALight.Y, -ALight.Z));
    if Back < 0 then
      Back := 0;
    Result := 0.28 + 0.34 * Back;
  end;
  if Result < 0.22 then
    Result := 0.22
  else if Result > 1 then
    Result := 1;
end;

function Channel(AShade: Single; AByte: Byte): Byte;
var
  V: Integer;
begin
  V := Round(AByte * AShade);
  if V < 0 then
    V := 0
  else if V > 255 then
    V := 255;
  Result := Byte(V);
end;

procedure RasterMesh(const AMesh: TMeshData; AW, AH: Integer;
  const ACam: TMeshCamera; const ACancel: TMeshCancel; const AClock: TStopwatch;
  AMaxMs: Cardinal; out ABmp: TBitmap);
var
  W, H, I, X, Y, MinX, MinY, MaxX, MaxY: Integer;
  Right, Up, Eye, Light, Nrm, E1, E2: TVec3;
  Scr: TArray<TScr>;
  Depth: TArray<Single>;
  Pix: TArray<Cardinal>;
  MinVX, MinVY, MaxVX, MaxVY, Span, Usable, Scl, MidX, MidY: Single;
  ViewZ, DepthZ: Single;
  P: TVec3;
  V0, V1, V2: TMeshVert;
  S0, S1, S2: TScr;
  Area, W0, W1, W2, Z, Px, Py, Shade: Single;
  Col: Cardinal;
  CR, CG, CB: Byte;
  Data: TBitmapData;
  Row: PCardinal;
  Edges: Boolean;
  TriN: Integer;

  procedure Plot(AX, AY: Integer; AZ: Single; ACol: Cardinal);
  var
    Ip: Integer;
  begin
    if (AX < 0) or (AY < 0) or (AX >= W) or (AY >= H) then
      Exit;
    Ip := AY * W + AX;
    if AZ >= Depth[Ip] then
    begin
      Depth[Ip] := AZ;
      Pix[Ip] := ACol;
    end;
  end;

  procedure DrawEdge(const P0, P1: TScr; ACol: Cardinal);
  var
    X0, Y0, X1, Y1, Dx, Dy, Err, E2s, SX, SY: Integer;
    T, Zv: Single;
    Steps, S: Integer;
  begin
    X0 := Round(P0.X);
    Y0 := Round(P0.Y);
    X1 := Round(P1.X);
    Y1 := Round(P1.Y);
    Dx := Abs(X1 - X0);
    Dy := Abs(Y1 - Y0);
    if X0 < X1 then
      SX := 1
    else
      SX := -1;
    if Y0 < Y1 then
      SY := 1
    else
      SY := -1;
    Err := Dx - Dy;
    Steps := Dx + Dy;
    if Steps < 1 then
      Steps := 1;
    S := 0;
    while True do
    begin
      T := S / Steps;
      Zv := P0.Z + (P1.Z - P0.Z) * T + 1E-3;
      Plot(X0, Y0, Zv, ACol);
      if (X0 = X1) and (Y0 = Y1) then
        Break;
      E2s := 2 * Err;
      if E2s > -Dy then
      begin
        Err := Err - Dy;
        Inc(X0, SX);
      end;
      if E2s < Dx then
      begin
        Err := Err + Dx;
        Inc(Y0, SY);
      end;
      Inc(S);
      if S > W + H + 8 then
        Break;
    end;
  end;

begin
  ABmp := nil;
  W := AW;
  H := AH;
  if (W < 2) or (H < 2) then
    Exit;
  if (Length(AMesh.Tris) = 0) and (Length(AMesh.Verts) = 0) then
    Exit;
  if Assigned(ACancel) and ACancel() then
    Exit;
  BuildCamera(ACam, Right, Up, Eye);
  Light := VNorm(V3(0.42, 0.78, 0.46));
  SetLength(Scr, Length(AMesh.Verts));
  MinVX := 1E30;
  MinVY := 1E30;
  MaxVX := -1E30;
  MaxVY := -1E30;
  for I := 0 to High(AMesh.Verts) do
  begin
    P := V3(AMesh.Verts[I].X, AMesh.Verts[I].Y, AMesh.Verts[I].Z);
    { Eye росте до камери. Ділимо на відстань від камери, тож ближній край більший. }
    ViewZ := VDot(P, Eye);
    DepthZ := CAM_DIST - ViewZ;
    if DepthZ < 0.2 then
      DepthZ := 0.2;
    Scr[I].X := VDot(P, Right) / DepthZ;
    Scr[I].Y := VDot(P, Up) / DepthZ;
    Scr[I].Z := ViewZ;
    if Scr[I].X < MinVX then
      MinVX := Scr[I].X;
    if Scr[I].Y < MinVY then
      MinVY := Scr[I].Y;
    if Scr[I].X > MaxVX then
      MaxVX := Scr[I].X;
    if Scr[I].Y > MaxVY then
      MaxVY := Scr[I].Y;
  end;
  Span := MaxVX - MinVX;
  if MaxVY - MinVY > Span then
    Span := MaxVY - MinVY;
  if Span < 1E-8 then
    Span := 1;
  Usable := Min(W, H) * 0.84;
  Scl := (Usable / Span) * ACam.Scale;
  if Scl < 1E-6 then
    Scl := 1;
  MidX := (MinVX + MaxVX) * 0.5;
  MidY := (MinVY + MaxVY) * 0.5;
  for I := 0 to High(Scr) do
  begin
    Scr[I].X := W * 0.5 + (Scr[I].X - MidX) * Scl;
    Scr[I].Y := H * 0.5 - (Scr[I].Y - MidY) * Scl;
  end;
  SetLength(Depth, W * H);
  SetLength(Pix, W * H);
  for I := 0 to W * H - 1 do
  begin
    Depth[I] := -1E30;
    Pix[I] := 0;
  end;
  TriN := Length(AMesh.Tris);
  Edges := (TriN > 0) and (TriN < 400);
  for I := 0 to TriN - 1 do
  begin
    if (I and 2047) = 0 then
    begin
      if Assigned(ACancel) and ACancel() then
        Exit;
      if AClock.ElapsedMilliseconds >= AMaxMs then
        Break;
    end;
    if (AMesh.Tris[I].A < 0) or (AMesh.Tris[I].B < 0) or (AMesh.Tris[I].C < 0) or
       (AMesh.Tris[I].A > High(AMesh.Verts)) or
       (AMesh.Tris[I].B > High(AMesh.Verts)) or
       (AMesh.Tris[I].C > High(AMesh.Verts)) then
      Continue;
    V0 := AMesh.Verts[AMesh.Tris[I].A];
    V1 := AMesh.Verts[AMesh.Tris[I].B];
    V2 := AMesh.Verts[AMesh.Tris[I].C];
    S0 := Scr[AMesh.Tris[I].A];
    S1 := Scr[AMesh.Tris[I].B];
    S2 := Scr[AMesh.Tris[I].C];
    E1 := VSub(V3(V1.X, V1.Y, V1.Z), V3(V0.X, V0.Y, V0.Z));
    E2 := VSub(V3(V2.X, V2.Y, V2.Z), V3(V0.X, V0.Y, V0.Z));
    Nrm := VCross(E1, E2);
    if VLen(V3(AMesh.Tris[I].Nx, AMesh.Tris[I].Ny, AMesh.Tris[I].Nz)) > 1E-8 then
    begin
      P := V3(AMesh.Tris[I].Nx, AMesh.Tris[I].Ny, AMesh.Tris[I].Nz);
      Nrm := V3(VDot(P, Right), VDot(P, Up), VDot(P, Eye));
      if VLen(Nrm) < 1E-8 then
        Nrm := VCross(E1, E2);
    end
    else
    begin
      { Геометрична нормаль уже у просторі моделі. У вид — тим самим базисом. }
      P := Nrm;
      Nrm := V3(VDot(P, Right), VDot(P, Up), VDot(P, Eye));
    end;
    Shade := ShadeOf(Nrm, Light);
    if AMesh.Tris[I].Col <> 0 then
    begin
      CR := Channel(Shade, Byte((AMesh.Tris[I].Col shr 16) and $FF));
      CG := Channel(Shade, Byte((AMesh.Tris[I].Col shr 8) and $FF));
      CB := Channel(Shade, Byte(AMesh.Tris[I].Col and $FF));
    end
    else if AMesh.HasVertColor and ((V0.Col or V1.Col or V2.Col) <> 0) then
    begin
      CR := Channel(Shade, Byte((((V0.Col shr 16) and $FF) + ((V1.Col shr 16) and $FF) +
        ((V2.Col shr 16) and $FF)) div 3));
      CG := Channel(Shade, Byte((((V0.Col shr 8) and $FF) + ((V1.Col shr 8) and $FF) +
        ((V2.Col shr 8) and $FF)) div 3));
      CB := Channel(Shade, Byte(((V0.Col and $FF) + (V1.Col and $FF) + (V2.Col and $FF)) div 3));
    end
    else
    begin
      CR := Channel(Shade, GRAY_R);
      CG := Channel(Shade, GRAY_G);
      CB := Channel(Shade, GRAY_B);
    end;
    Col := $FF000000 or (Cardinal(CR) shl 16) or (Cardinal(CG) shl 8) or CB;
    MinX := Floor(Min(S0.X, Min(S1.X, S2.X)));
    MaxX := Ceil(Max(S0.X, Max(S1.X, S2.X)));
    MinY := Floor(Min(S0.Y, Min(S1.Y, S2.Y)));
    MaxY := Ceil(Max(S0.Y, Max(S1.Y, S2.Y)));
    if (MaxX < 0) or (MaxY < 0) or (MinX >= W) or (MinY >= H) then
      Continue;
    if (MaxX - MinX <= 1) and (MaxY - MinY <= 1) then
    begin
      Plot(Round((S0.X + S1.X + S2.X) / 3), Round((S0.Y + S1.Y + S2.Y) / 3),
        (S0.Z + S1.Z + S2.Z) / 3, Col);
      Continue;
    end;
    if MinX < 0 then
      MinX := 0;
    if MinY < 0 then
      MinY := 0;
    if MaxX >= W then
      MaxX := W - 1;
    if MaxY >= H then
      MaxY := H - 1;
    Area := (S1.X - S0.X) * (S2.Y - S0.Y) - (S1.Y - S0.Y) * (S2.X - S0.X);
    if Abs(Area) < 1E-6 then
      Continue;
    for Y := MinY to MaxY do
    begin
      Py := Y + 0.5;
      for X := MinX to MaxX do
      begin
        Px := X + 0.5;
        W0 := (S1.X - Px) * (S2.Y - Py) - (S1.Y - Py) * (S2.X - Px);
        W1 := (S2.X - Px) * (S0.Y - Py) - (S2.Y - Py) * (S0.X - Px);
        W2 := (S0.X - Px) * (S1.Y - Py) - (S0.Y - Py) * (S1.X - Px);
        if Area > 0 then
        begin
          if (W0 < 0) or (W1 < 0) or (W2 < 0) then
            Continue;
        end
        else if (W0 > 0) or (W1 > 0) or (W2 > 0) then
          Continue;
        Z := (W0 * S0.Z + W1 * S1.Z + W2 * S2.Z) / Area;
        Plot(X, Y, Z, Col);
      end;
    end;
  end;
  if (TriN = 0) and (Length(AMesh.Verts) > 0) and
     not (Assigned(ACancel) and ACancel()) then
  begin
    for I := 0 to High(AMesh.Verts) do
    begin
      if (I and 4095) = 0 then
      begin
        if Assigned(ACancel) and ACancel() then
          Exit;
        if AClock.ElapsedMilliseconds >= AMaxMs then
          Break;
      end;
      if AMesh.HasVertColor then
      begin
        CR := Byte((AMesh.Verts[I].Col shr 16) and $FF);
        CG := Byte((AMesh.Verts[I].Col shr 8) and $FF);
        CB := Byte(AMesh.Verts[I].Col and $FF);
      end
      else
      begin
        CR := GRAY_R;
        CG := GRAY_G;
        CB := GRAY_B;
      end;
      Col := $FF000000 or (Cardinal(CR) shl 16) or (Cardinal(CG) shl 8) or CB;
      MinX := Round(Scr[I].X);
      MinY := Round(Scr[I].Y);
      for Y := -1 to 1 do
        for X := -1 to 1 do
          Plot(MinX + X, MinY + Y, Scr[I].Z, Col);
    end;
  end;
  if Edges and not (Assigned(ACancel) and ACancel()) then
  begin
    Col := $FF000000 or (Cardinal(48) shl 16) or (Cardinal(50) shl 8) or 56;
    for I := 0 to High(AMesh.Tris) do
    begin
      if (AMesh.Tris[I].A < 0) or (AMesh.Tris[I].A > High(Scr)) or
         (AMesh.Tris[I].B > High(Scr)) or (AMesh.Tris[I].C > High(Scr)) then
        Continue;
      DrawEdge(Scr[AMesh.Tris[I].A], Scr[AMesh.Tris[I].B], Col);
      DrawEdge(Scr[AMesh.Tris[I].B], Scr[AMesh.Tris[I].C], Col);
      DrawEdge(Scr[AMesh.Tris[I].C], Scr[AMesh.Tris[I].A], Col);
    end;
  end;
  if Assigned(ACancel) and ACancel() then
    Exit;
  ABmp := TBitmap.Create;
  try
    ABmp.SetSize(W, H);
    if not ABmp.Map(TMapAccess.Write, Data) then
    begin
      FreeAndNil(ABmp);
      Exit;
    end;
    try
      if Data.PixelFormat = TPixelFormat.BGRA then
      begin
        for Y := 0 to H - 1 do
        begin
          Row := Data.GetScanline(Y);
          Move(Pix[Y * W], Row^, W * 4);
        end;
      end
      else
        for Y := 0 to H - 1 do
          for X := 0 to W - 1 do
            Data.SetPixel(X, Y, Pix[Y * W + X]);
    finally
      ABmp.Unmap(Data);
    end;
  except
    FreeAndNil(ABmp);
  end;
end;

procedure NormalizeMesh(var AMesh: TMeshData);
var
  I: Integer;
  MinX, MinY, MinZ, MaxX, MaxY, MaxZ, CX, CY, CZ, Span, Inv: Single;
begin
  if Length(AMesh.Verts) = 0 then
    Exit;
  MinX := AMesh.Verts[0].X;
  MinY := AMesh.Verts[0].Y;
  MinZ := AMesh.Verts[0].Z;
  MaxX := MinX;
  MaxY := MinY;
  MaxZ := MinZ;
  for I := 1 to High(AMesh.Verts) do
  begin
    if AMesh.Verts[I].X < MinX then
      MinX := AMesh.Verts[I].X;
    if AMesh.Verts[I].Y < MinY then
      MinY := AMesh.Verts[I].Y;
    if AMesh.Verts[I].Z < MinZ then
      MinZ := AMesh.Verts[I].Z;
    if AMesh.Verts[I].X > MaxX then
      MaxX := AMesh.Verts[I].X;
    if AMesh.Verts[I].Y > MaxY then
      MaxY := AMesh.Verts[I].Y;
    if AMesh.Verts[I].Z > MaxZ then
      MaxZ := AMesh.Verts[I].Z;
  end;
  CX := (MinX + MaxX) * 0.5;
  CY := (MinY + MaxY) * 0.5;
  CZ := (MinZ + MaxZ) * 0.5;
  Span := MaxX - MinX;
  if MaxY - MinY > Span then
    Span := MaxY - MinY;
  if MaxZ - MinZ > Span then
    Span := MaxZ - MinZ;
  if Span < 1E-12 then
    Inv := 1
  else
    Inv := 1 / Span;
  for I := 0 to High(AMesh.Verts) do
  begin
    AMesh.Verts[I].X := (AMesh.Verts[I].X - CX) * Inv;
    AMesh.Verts[I].Y := (AMesh.Verts[I].Y - CY) * Inv;
    AMesh.Verts[I].Z := (AMesh.Verts[I].Z - CZ) * Inv;
  end;
end;

function CacheHit(const APath: string; AAge: TDateTime; ABytes: Int64;
  const ALim: TMeshLimits; out AMesh: TMeshData): Boolean;
begin
  Result := False;
  GLock.Enter;
  try
    if GHold.Valid and SameText(GHold.Path, APath) and (GHold.Age = AAge) and
       (GHold.Bytes = ABytes) and (GHold.MaxTris = ALim.MaxTris) and
       (GHold.MaxVerts = ALim.MaxVerts) then
    begin
      AMesh := GHold.Data;
      Result := True;
    end;
  finally
    GLock.Leave;
  end;
end;

procedure CachePut(const APath: string; AAge: TDateTime; ABytes: Int64;
  const ALim: TMeshLimits; const AMesh: TMeshData);
begin
  GLock.Enter;
  try
    GHold.Valid := True;
    GHold.Path := APath;
    GHold.Age := AAge;
    GHold.Bytes := ABytes;
    GHold.MaxTris := ALim.MaxTris;
    GHold.MaxVerts := ALim.MaxVerts;
    GHold.Data := AMesh;
  finally
    GLock.Leave;
  end;
end;

function BuildMesh(const APath: string; ATile: Boolean; const ACancel: TMeshCancel;
  out AInfo: TMeshInfo): TMeshData;
var
  Lim: TMeshLimits;
  Bytes: TBytes;
  Size: Int64;
  Age: TDateTime;
  Err: TMeshError;
  Clock: TStopwatch;
  Kind: TMeshKind;
begin
  ClearInfo(AInfo);
  Result.Info := AInfo;
  Result.Cancelled := False;
  Result.HasVertColor := False;
  Result.PicW := 0;
  Result.PicH := 0;
  SetLength(Result.Pic, 0);
  Lim := LimitsOf(ATile);
  Kind := KindOfExt(ExtractFileExt(APath));
  if Kind = mkNone then
  begin
    AInfo.Error := meBad;
    Result.Info := AInfo;
    Exit;
  end;
  if not LoadBytes(APath, Lim.MaxBytes, Bytes, Size, Age, Err) then
  begin
    AInfo.Error := Err;
    AInfo.Kind := Kind;
    AInfo.Bytes := Size;
    Result.Info := AInfo;
    Exit;
  end;
  AInfo.Bytes := Size;
  AInfo.Kind := Kind;
  if CacheHit(APath, Age, Size, Lim, Result) then
  begin
    AInfo := Result.Info;
    AInfo.Bytes := Size;
    Exit;
  end;
  Clock := TStopwatch.StartNew;
  if Assigned(ACancel) and ACancel() then
  begin
    Result.Cancelled := True;
    AInfo.Error := meNone;
    Result.Info := AInfo;
    Exit;
  end;
  try
    ParseMesh(APath, Bytes, Size, Kind, Lim, ACancel, Clock, Result);
  except
    Result.Info.Error := meBad;
    Result.Cancelled := False;
  end;
  Result.Info.Bytes := Size;
  if Result.Info.Kind = mkNone then
    Result.Info.Kind := Kind;
  if Result.Cancelled then
  begin
    AInfo := Result.Info;
    Exit;
  end;
  if Result.Info.Error = meNone then
    NormalizeMesh(Result);
  CachePut(APath, Age, Size, Lim, Result);
  AInfo := Result.Info;
end;

procedure RasterPicture(const APic: TBytes; AW, AH, DW, DH: Integer; out ABmp: TBitmap);
var
  Fit: Single;
  DrawW, DrawH, Ox, Oy, X, Y, SX, SY, Src: Integer;
  Pix: TArray<Cardinal>;
  R, G, B, A: Byte;
  Data: TBitmapData;
  Row: PCardinal;
begin
  ABmp := nil;
  if (AW < 1) or (AH < 1) or (DW < 2) or (DH < 2) then
    Exit;
  if Int64(Length(APic)) < Int64(AW) * AH * 4 then
    Exit;
  Fit := DW / AW;
  if (DH / AH) < Fit then
    Fit := DH / AH;
  DrawW := Round(AW * Fit);
  DrawH := Round(AH * Fit);
  if DrawW < 1 then
    DrawW := 1;
  if DrawH < 1 then
    DrawH := 1;
  if DrawW > DW then
    DrawW := DW;
  if DrawH > DH then
    DrawH := DH;
  Ox := (DW - DrawW) div 2;
  Oy := (DH - DrawH) div 2;
  SetLength(Pix, DW * DH);
  for Y := 0 to DW * DH - 1 do
    Pix[Y] := 0;
  for Y := 0 to DrawH - 1 do
  begin
    SY := (Y * AH) div DrawH;
    if SY >= AH then
      SY := AH - 1;
    SY := (AH - 1) - SY;
    for X := 0 to DrawW - 1 do
    begin
      SX := (X * AW) div DrawW;
      if SX >= AW then
        SX := AW - 1;
      Src := (SY * AW + SX) * 4;
      R := APic[Src];
      G := APic[Src + 1];
      B := APic[Src + 2];
      A := APic[Src + 3];
      if A < 16 then
        Continue;
      Pix[(Oy + Y) * DW + (Ox + X)] := $FF000000 or (Cardinal(R) shl 16) or
        (Cardinal(G) shl 8) or B;
    end;
  end;
  ABmp := TBitmap.Create;
  try
    ABmp.SetSize(DW, DH);
    if not ABmp.Map(TMapAccess.Write, Data) then
    begin
      FreeAndNil(ABmp);
      Exit;
    end;
    try
      if Data.PixelFormat = TPixelFormat.BGRA then
      begin
        for Y := 0 to DH - 1 do
        begin
          Row := Data.GetScanline(Y);
          Move(Pix[Y * DW], Row^, DW * 4);
        end;
      end
      else
        for Y := 0 to DH - 1 do
          for X := 0 to DW - 1 do
            Data.SetPixel(X, Y, Pix[Y * DW + X]);
    finally
      ABmp.Unmap(Data);
    end;
  except
    FreeAndNil(ABmp);
  end;
end;

function RenderFrame(const APath: string; AW, AH: Integer; const ACamera: TMeshCamera;
  ATile: Boolean; out AInfo: TMeshInfo; const ACancel: TMeshCancel): TBitmap;
var
  Mesh: TMeshData;
  Cam: TMeshCamera;
  Lim: TMeshLimits;
  Clock: TStopwatch;
begin
  Result := nil;
  ClearInfo(AInfo);
  if AW < 1 then
    AW := 1;
  if AH < 1 then
    AH := 1;
  if AW > MAX_FRAME then
    AW := MAX_FRAME;
  if AH > MAX_FRAME then
    AH := MAX_FRAME;
  Cam := ACamera;
  if Cam.Scale < 0.4 then
    Cam.Scale := 0.4
  else if Cam.Scale > 6 then
    Cam.Scale := 6;
  Lim := LimitsOf(ATile);
  Clock := TStopwatch.StartNew;
  Mesh := BuildMesh(APath, ATile, ACancel, AInfo);
  if Mesh.Cancelled then
    Exit;
  if AInfo.Error <> meNone then
    Exit;
  if AInfo.Picture then
  begin
    RasterPicture(Mesh.Pic, Mesh.PicW, Mesh.PicH, AW, AH, Result);
    if (Result = nil) and not (Assigned(ACancel) and ACancel()) and (AInfo.Error = meNone) then
      AInfo.Error := meBlend;
    Exit;
  end;
  if (Length(Mesh.Tris) = 0) and (Length(Mesh.Verts) = 0) then
  begin
    if AInfo.Error = meNone then
      AInfo.Error := meEmpty;
    Exit;
  end;
  if Assigned(ACancel) and ACancel() then
    Exit;
  RasterMesh(Mesh, AW, AH, Cam, ACancel, Clock, Lim.MaxMs, Result);
  if Result = nil then
  begin
    if Assigned(ACancel) and ACancel() then
      Exit;
    if AInfo.Error = meNone then
      AInfo.Error := meEmpty;
  end;
end;

function MeshInfo(const APath: string): TMeshInfo;
var
  Mesh: TMeshData;
begin
  Mesh := BuildMesh(APath, False, nil, Result);
end;

function RenderMeshThumb(const APath: string; ASize: Integer): TBitmap;
var
  Info: TMeshInfo;
begin
  if ASize < 16 then
    ASize := 16;
  if ASize > 512 then
    ASize := 512;
  Result := RenderFrame(APath, ASize, ASize, MeshHomeCamera, True, Info, nil);
end;

function RenderMeshView(const APath: string; AW, AH: Integer;
  const ACamera: TMeshCamera): TBitmap;
var
  Info: TMeshInfo;
begin
  Result := RenderFrame(APath, AW, AH, ACamera, False, Info, nil);
end;

function RenderMeshView(const APath: string; AW, AH: Integer;
  const ACamera: TMeshCamera; out AInfo: TMeshInfo): TBitmap;
begin
  Result := RenderFrame(APath, AW, AH, ACamera, False, AInfo, nil);
end;

function RenderMeshView(const APath: string; AW, AH: Integer;
  const ACamera: TMeshCamera; out AInfo: TMeshInfo;
  const ACancel: TMeshCancel): TBitmap;
begin
  Result := RenderFrame(APath, AW, AH, ACamera, False, AInfo, ACancel);
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  FreeAndNil(GLock);

end.
