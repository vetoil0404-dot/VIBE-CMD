unit uSpreadsheetData;

{
  Модель книги + парсеры xlsx/xlsm/csv/tsv без Excel COM.
  RenderSpreadsheetThumb — растр для плиток (CPU, без FMX-грида).
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Types,
  System.UITypes, System.Math, FMX.Graphics, FMX.Types;

type
  TSpreadCellKind = (sckEmpty, sckText, sckNumber, sckBool, sckDate, sckError, sckImage);

  TSpreadCell = record
    Value: string;
    Kind: TSpreadCellKind;
    FillColor: TAlphaColor;
    TextColor: TAlphaColor;
    HasFill: Boolean;
    HasTextColor: Boolean;
  end;

  TSpreadImage = class
  public
    Col: Integer;
    Row: Integer;
    Bitmap: TBitmap;
    WidthPx: Integer;
    HeightPx: Integer;
    destructor Destroy; override;
  end;

  TSpreadSheet = class
  private
    FCells: TArray<TArray<TSpreadCell>>;
    FRowH: TArray<Single>;
    FColW: TArray<Single>;
    procedure GrowTo(ARow, ACol: Integer);
  public
    Name: string;
    ColCount: Integer;
    RowCount: Integer;
    Truncated: Boolean;
    DefaultColW: Single;
    DefaultRowH: Single;
    Images: TObjectList<TSpreadImage>;
    constructor Create;
    destructor Destroy; override;
    procedure Put(ARow, ACol: Integer; const AValue: string; AKind: TSpreadCellKind;
      AFill: TAlphaColor = 0; AText: TAlphaColor = 0; AHasFill: Boolean = False;
      AHasText: Boolean = False);
    function Cell(ARow, ACol: Integer): TSpreadCell;
    function RowHeight(ARow: Integer): Single;
    function RowTop(ARow: Integer): Single;
    function TotalHeight: Single;
    function ColWidth(ACol: Integer): Single;
    function ColLeft(ACol: Integer): Single;
    function TotalWidth: Single;
    procedure SetColWidth(AFrom, ATo: Integer; AWidth: Single);
    procedure SetRowHeight(ARow: Integer; AHeight: Single);
    procedure RecalcRowHeights(AColW, AMinH, AMaxH: Single);
    function ImageAt(ARow, ACol: Integer): TSpreadImage;
  end;

  TSpreadWorkbook = class
  public
    FilePath: string;
    EncodingLabel: string;
    Sheets: TObjectList<TSpreadSheet>;
    ActiveIndex: Integer;
    constructor Create;
    destructor Destroy; override;
    function ActiveSheet: TSpreadSheet;
  end;

function IsSpreadsheetFile(const APath: string): Boolean;
function IsSpreadsheetThumbExt(const APath: string): Boolean;
function DecodeLooseText(const ABytes: TBytes; out AEncodingLabel: string): string;
function DecodeUtf8OrReplace(const ABytes: TBytes): string;
function LoadWorkbookLimited(const APath: string; MaxRows, MaxCols: Integer;
  out AError: string): TSpreadWorkbook;
function RenderSpreadsheetThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;
function ColIndexToName(ACol: Integer): string;
function FitAspectRect(const ABounds: TRectF; AImgW, AImgH: Single): TRectF;

const
  SpreadQVMaxRows = 300;
  SpreadQVMaxCols = 60;
  SpreadQVMaxBytes = 40 * 1024 * 1024;
  SpreadThumbMaxBytes = 8 * 1024 * 1024;
  SpreadThumbMaxRows = 56;
  SpreadThumbMaxCols = 18;
  SpreadThumbPageW = 794;
  SpreadThumbPageH = 1123;

implementation

uses
  System.Zip, System.IOUtils, System.StrUtils, System.DateUtils,
  uAppSettings, uThemeManager;

function LenientCodePage(const ABytes: TBytes; AFrom: Integer;
  ACodePage: Cardinal): string;
var
  Count, Written, I: Integer;
begin
  Count := Length(ABytes) - AFrom;
  if Count <= 0 then
    Exit('');
  Written := UnicodeFromLocaleChars(ACodePage, 0, PAnsiChar(@ABytes[AFrom]), Count, nil, 0);
  if Written > 0 then
  begin
    SetLength(Result, Written);
    UnicodeFromLocaleChars(ACodePage, 0, PAnsiChar(@ABytes[AFrom]), Count,
      PChar(Result), Written);
    Exit;
  end;
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
    if ABytes[AFrom + I] < 32 then
      Result[I + 1] := #$FFFD
    else
      Result[I + 1] := Char(ABytes[AFrom + I]);
end;

function MbToString(const ABytes: TBytes; AFrom: Integer; ACodePage, AFlags: Cardinal;
  out AText: string): Boolean;
var
  Count, Written: Integer;
begin
  AText := '';
  Count := Length(ABytes) - AFrom;
  if Count <= 0 then
    Exit(True);
  Written := UnicodeFromLocaleChars(ACodePage, AFlags, PAnsiChar(@ABytes[AFrom]),
    Count, nil, 0);
  Result := Written > 0;
  if not Result then
    Exit;
  SetLength(AText, Written);
  UnicodeFromLocaleChars(ACodePage, AFlags, PAnsiChar(@ABytes[AFrom]), Count,
    PChar(AText), Written);
end;

function DecodeUtf8OrReplace(const ABytes: TBytes): string;
var
  N, Bom: Integer;
begin
  N := Length(ABytes);
  Bom := 0;
  if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Bom := 3
  else if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    N := N - 2;
    if Odd(N) then
      Dec(N);
    if N <= 0 then
      Exit('');
    Exit(TEncoding.Unicode.GetString(ABytes, 2, N));
  end
  else if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    N := N - 2;
    if Odd(N) then
      Dec(N);
    if N <= 0 then
      Exit('');
    Exit(TEncoding.BigEndianUnicode.GetString(ABytes, 2, N));
  end;
  if MbToString(ABytes, Bom, 65001, 8, Result) then
    Exit;
  Result := LenientCodePage(ABytes, Bom, 65001);
end;

function DecodeLooseText(const ABytes: TBytes; out AEncodingLabel: string): string;
var
  N, Bom, Count: Integer;
begin
  AEncodingLabel := '';
  N := Length(ABytes);
  if N = 0 then
  begin
    AEncodingLabel := 'пусто';
    Exit('');
  end;

  if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    Count := N - 2;
    if Odd(Count) then
      Dec(Count);
    AEncodingLabel := 'UTF-16 LE';
    if Count <= 0 then
      Exit('');
    Exit(TEncoding.Unicode.GetString(ABytes, 2, Count));
  end;
  if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    Count := N - 2;
    if Odd(Count) then
      Dec(Count);
    AEncodingLabel := 'UTF-16 BE';
    if Count <= 0 then
      Exit('');
    Exit(TEncoding.BigEndianUnicode.GetString(ABytes, 2, Count));
  end;

  Bom := 0;
  if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Bom := 3;
  if MbToString(ABytes, Bom, 65001, 8, Result) then
  begin
    if Bom > 0 then
      AEncodingLabel := 'UTF-8 BOM'
    else
      AEncodingLabel := 'UTF-8';
    Exit;
  end;

  if MbToString(ABytes, 0, 1251, 8, Result) then
  begin
    AEncodingLabel := 'Windows-1251';
    Exit;
  end;

  if (TEncoding.ANSI.CodePage <> 1251) and
     MbToString(ABytes, 0, TEncoding.ANSI.CodePage, 8, Result) then
  begin
    AEncodingLabel := 'ANSI';
    Exit;
  end;

  AEncodingLabel := 'с заменой';
  Result := LenientCodePage(ABytes, Bom, 65001);
end;

destructor TSpreadImage.Destroy;
begin
  FreeAndNil(Bitmap);
  inherited;
end;

constructor TSpreadSheet.Create;
begin
  inherited Create;
  Images := TObjectList<TSpreadImage>.Create(True);
  Name := 'Sheet';
  DefaultColW := 64;
  DefaultRowH := 20;
end;

destructor TSpreadSheet.Destroy;
begin
  Images.Free;
  inherited;
end;

procedure TSpreadSheet.GrowTo(ARow, ACol: Integer);
var
  R, OldR: Integer;
begin
  if ARow < 1 then
    ARow := 1;
  if ACol < 1 then
    ACol := 1;
  if ARow > RowCount then
  begin
    OldR := Length(FCells);
    SetLength(FCells, ARow);
    for R := OldR to ARow - 1 do
      SetLength(FCells[R], Max(ACol, ColCount));
    RowCount := ARow;
    SetLength(FRowH, ARow);
    for R := OldR to ARow - 1 do
      FRowH[R] := -1;
  end;
  if ACol > ColCount then
  begin
    OldR := ColCount;
    for R := 0 to High(FCells) do
      SetLength(FCells[R], ACol);
    ColCount := ACol;
    SetLength(FColW, ACol);
    for R := OldR to ACol - 1 do
      FColW[R] := -1;
  end;
end;

procedure TSpreadSheet.Put(ARow, ACol: Integer; const AValue: string; AKind: TSpreadCellKind;
  AFill: TAlphaColor; AText: TAlphaColor; AHasFill, AHasText: Boolean);
begin
  if (ARow < 1) or (ACol < 1) then
    Exit;
  GrowTo(ARow, ACol);
  FCells[ARow - 1][ACol - 1].Value := AValue;
  FCells[ARow - 1][ACol - 1].Kind := AKind;
  if AHasFill then
  begin
    FCells[ARow - 1][ACol - 1].FillColor := AFill;
    FCells[ARow - 1][ACol - 1].HasFill := True;
  end;
  if AHasText then
  begin
    FCells[ARow - 1][ACol - 1].TextColor := AText;
    FCells[ARow - 1][ACol - 1].HasTextColor := True;
  end;
end;

function TSpreadSheet.Cell(ARow, ACol: Integer): TSpreadCell;
begin
  Result.Value := '';
  Result.Kind := sckEmpty;
  Result.FillColor := 0;
  Result.TextColor := 0;
  Result.HasFill := False;
  Result.HasTextColor := False;
  if (ARow < 1) or (ACol < 1) or (ARow > RowCount) or (ACol > ColCount) then
    Exit;
  if (ARow - 1 > High(FCells)) or (ACol - 1 > High(FCells[ARow - 1])) then
    Exit;
  Result := FCells[ARow - 1][ACol - 1];
end;

function TSpreadSheet.RowHeight(ARow: Integer): Single;
begin
  Result := DefaultRowH;
  if DefaultRowH < 8 then
    Result := 20;
  if (ARow < 1) or (ARow > Length(FRowH)) then
    Exit;
  if FRowH[ARow - 1] >= 0 then
    Result := FRowH[ARow - 1];
end;

function TSpreadSheet.ColWidth(ACol: Integer): Single;
begin
  Result := DefaultColW;
  if DefaultColW < 8 then
    Result := 64;
  if (ACol < 1) or (ACol > Length(FColW)) then
    Exit;
  if FColW[ACol - 1] >= 0 then
    Result := FColW[ACol - 1];
end;

function TSpreadSheet.ColLeft(ACol: Integer): Single;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to ACol - 1 do
    Result := Result + ColWidth(I);
end;

function TSpreadSheet.TotalWidth: Single;
begin
  Result := ColLeft(ColCount + 1);
end;

procedure TSpreadSheet.SetColWidth(AFrom, ATo: Integer; AWidth: Single);
var
  C: Integer;
begin
  if ATo < AFrom then
    Exit;
  GrowTo(Max(1, RowCount), ATo);
  for C := AFrom to ATo do
    if (C >= 1) and (C <= Length(FColW)) then
      FColW[C - 1] := Max(0, AWidth);
end;

procedure TSpreadSheet.SetRowHeight(ARow: Integer; AHeight: Single);
begin
  if ARow < 1 then
    Exit;
  GrowTo(ARow, Max(1, ColCount));
  if ARow <= Length(FRowH) then
    FRowH[ARow - 1] := Max(0, AHeight);
end;

function TSpreadSheet.RowTop(ARow: Integer): Single;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to ARow - 1 do
    Result := Result + RowHeight(I);
end;

function TSpreadSheet.TotalHeight: Single;
begin
  Result := RowTop(RowCount + 1);
end;

function TSpreadSheet.ImageAt(ARow, ACol: Integer): TSpreadImage;
var
  I: Integer;
begin
  Result := nil;
  if Images = nil then
    Exit;
  for I := 0 to Images.Count - 1 do
    if (Images[I].Row = ARow) and (Images[I].Col = ACol) then
      Exit(Images[I]);
end;

procedure TSpreadSheet.RecalcRowHeights(AColW, AMinH, AMaxH: Single);
var
  R: Integer;
begin
  { Высоты из файла не трогаем. }
  if RowCount <= 0 then
    Exit;
  SetLength(FRowH, RowCount);
  for R := 0 to High(FRowH) do
    if FRowH[R] < 0 then
      FRowH[R] := DefaultRowH;
end;

function FitAspectRect(const ABounds: TRectF; AImgW, AImgH: Single): TRectF;
var
  Scale, W, H: Single;
begin
  if (AImgW <= 0) or (AImgH <= 0) or (ABounds.Width <= 0) or (ABounds.Height <= 0) then
    Exit(ABounds);
  Scale := Min(ABounds.Width / AImgW, ABounds.Height / AImgH);
  W := AImgW * Scale;
  H := AImgH * Scale;
  Result := TRectF.Create(
    ABounds.Left + (ABounds.Width - W) / 2,
    ABounds.Top + (ABounds.Height - H) / 2,
    ABounds.Left + (ABounds.Width - W) / 2 + W,
    ABounds.Top + (ABounds.Height - H) / 2 + H);
end;

constructor TSpreadWorkbook.Create;
begin
  inherited Create;
  Sheets := TObjectList<TSpreadSheet>.Create(True);
  ActiveIndex := 0;
end;

destructor TSpreadWorkbook.Destroy;
begin
  Sheets.Free;
  inherited;
end;

function TSpreadWorkbook.ActiveSheet: TSpreadSheet;
begin
  Result := nil;
  if (ActiveIndex >= 0) and (ActiveIndex < Sheets.Count) then
    Result := Sheets[ActiveIndex];
end;

function IsSpreadsheetFile(const APath: string): Boolean;
var
  Ext, Name: string;
begin
  Name := ExtractFileName(APath);
  if (Length(Name) >= 2) and (Name[1] = '~') and (Name[2] = '$') then
    Exit(False);
  Ext := LowerCase(ExtractFileExt(APath));
  Result := MatchText(Ext, ['.xlsx', '.xlsm', '.csv', '.tsv']);
end;

function IsSpreadsheetThumbExt(const APath: string): Boolean;
begin
  Result := IsSpreadsheetFile(APath);
end;

function ColIndexToName(ACol: Integer): string;
var
  N: Integer;
begin
  Result := '';
  N := ACol;
  if N < 1 then
    N := 1;
  while N > 0 do
  begin
    Dec(N);
    Result := Chr(Ord('A') + (N mod 26)) + Result;
    N := N div 26;
  end;
end;

function CellRefToRC(const Ref: string; out Row, Col: Integer): Boolean;
var
  I, C: Integer;
  Ch: Char;
begin
  Result := False;
  Row := 0;
  Col := 0;
  C := 0;
  I := 1;
  while I <= Length(Ref) do
  begin
    Ch := UpCase(Ref[I]);
    if (Ch >= 'A') and (Ch <= 'Z') then
      C := C * 26 + (Ord(Ch) - Ord('A') + 1)
    else
      Break;
    Inc(I);
  end;
  if (C <= 0) or (I > Length(Ref)) then
    Exit;
  Row := StrToIntDef(Copy(Ref, I, MaxInt), 0);
  Col := C;
  Result := (Row > 0) and (Col > 0);
end;

function XmlUnescape(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', '''', [rfReplaceAll]);
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

function XmlAttr(const Tag, Name: string): string;
var
  P, Q: Integer;
  Key: string;
  Quote: Char;
begin
  Result := '';
  Key := Name + '=';
  P := Pos(Key, Tag);
  if P = 0 then
    Exit;
  P := P + Length(Key);
  if P > Length(Tag) then
    Exit;
  Quote := Tag[P];
  if (Quote <> '"') and (Quote <> '''') then
    Exit;
  Inc(P);
  Q := P;
  while (Q <= Length(Tag)) and (Tag[Q] <> Quote) do
    Inc(Q);
  Result := XmlUnescape(Copy(Tag, P, Q - P));
end;

function ZipOpenShared(const APath: string; out AStream: TFileStream): TZipFile;
begin
  AStream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  Result := TZipFile.Create;
  try
    Result.Open(AStream, zmRead);
  except
    Result.Free;
    FreeAndNil(AStream);
    raise;
  end;
end;

function ZipFind(Zip: TZipFile; const AName: string): Integer;
var
  I: Integer;
  Want, Have: string;
begin
  Result := -1;
  Want := StringReplace(LowerCase(AName), '\', '/', [rfReplaceAll]);
  while (Want <> '') and (Want[1] = '/') do
    Delete(Want, 1, 1);
  for I := 0 to Zip.FileCount - 1 do
  begin
    Have := StringReplace(LowerCase(Zip.FileName[I]), '\', '/', [rfReplaceAll]);
    while (Have <> '') and (Have[1] = '/') do
      Delete(Have, 1, 1);
    if Have = Want then
      Exit(I);
  end;
end;

function ZipReadUtf8(Zip: TZipFile; const AName: string): string;
var
  Idx: Integer;
  Bytes: TBytes;
begin
  Result := '';
  Idx := ZipFind(Zip, AName);
  if Idx < 0 then
    Exit;
  Zip.Read(Idx, Bytes);
  if Length(Bytes) = 0 then
    Exit;
  Result := DecodeUtf8OrReplace(Bytes);
end;

function ZipReadBytes(Zip: TZipFile; const AName: string): TBytes;
var
  Idx: Integer;
begin
  SetLength(Result, 0);
  Idx := ZipFind(Zip, AName);
  if Idx < 0 then
    Exit;
  Zip.Read(Idx, Result);
end;

function ExtractTRuns(const Fragment: string): string;
var
  P, Gt, CloseP: Integer;
  Chunk: string;
begin
  Result := '';
  P := 1;
  while P <= Length(Fragment) do
  begin
    P := Pos('<t', Fragment, P);
    if P = 0 then
      Break;
    if (P + 2 <= Length(Fragment)) and
       (Fragment[P + 2] <> '>') and (Fragment[P + 2] <> ' ') and
       (Fragment[P + 2] <> '/') then
    begin
      Inc(P, 2);
      Continue;
    end;
    Gt := Pos('>', Fragment, P);
    if Gt = 0 then
      Break;
    if (Gt > P) and (Fragment[Gt - 1] = '/') then
    begin
      P := Gt + 1;
      Continue;
    end;
    CloseP := Pos('</t>', Fragment, Gt + 1);
    if CloseP = 0 then
      Break;
    Chunk := Copy(Fragment, Gt + 1, CloseP - Gt - 1);
    Result := Result + XmlUnescape(Chunk);
    P := CloseP + 4;
  end;
end;

function XmlInnerTag(const Fragment, TagName: string): string;
var
  Open, Gt, CloseP: Integer;
  OpenTok: string;
begin
  Result := '';
  OpenTok := '<' + TagName;
  Open := Pos(OpenTok, Fragment);
  if Open = 0 then
    Exit;
  Gt := Pos('>', Fragment, Open);
  if Gt = 0 then
    Exit;
  if (Gt > Open) and (Fragment[Gt - 1] = '/') then
    Exit;
  CloseP := Pos('</' + TagName + '>', Fragment, Gt + 1);
  if CloseP = 0 then
    Exit;
  Result := XmlUnescape(Copy(Fragment, Gt + 1, CloseP - Gt - 1));
end;

function CollectSharedStrings(const Xml: string): TArray<string>;
var
  P, Gt, CloseP: Integer;
  Inner: string;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    P := 1;
    while P <= Length(Xml) do
    begin
      P := Pos('<si', Xml, P);
      if P = 0 then
        Break;
      if (P + 3 <= Length(Xml)) and
         (Xml[P + 3] <> '>') and (Xml[P + 3] <> ' ') and (Xml[P + 3] <> '/') then
      begin
        Inc(P, 3);
        Continue;
      end;
      Gt := Pos('>', Xml, P);
      if Gt = 0 then
        Break;
      if (Gt > P) and (Xml[Gt - 1] = '/') then
      begin
        List.Add('');
        P := Gt + 1;
        Continue;
      end;
      CloseP := Pos('</si>', Xml, Gt + 1);
      if CloseP = 0 then
        Break;
      Inner := Copy(Xml, Gt + 1, CloseP - Gt - 1);
      List.Add(ExtractTRuns(Inner));
      P := CloseP + 5;
      if List.Count > 80000 then
        Break;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure CollectWorkbookSheets(const BookXml, RelsXml: string;
  Names, Targets: TStringList);
var
  P, Gt, I: Integer;
  Tag, SName, Rid, Id, Target: string;
  Map: TDictionary<string, string>;
begin
  Names.Clear;
  Targets.Clear;
  Map := TDictionary<string, string>.Create;
  try
    P := 1;
    while P <= Length(RelsXml) do
    begin
      P := Pos('<Relationship', RelsXml, P);
      if P = 0 then
        Break;
      Gt := Pos('/>', RelsXml, P);
      if Gt = 0 then
        Gt := Pos('>', RelsXml, P);
      if Gt = 0 then
        Break;
      Tag := Copy(RelsXml, P, Gt - P + 2);
      Id := XmlAttr(Tag, 'Id');
      Target := XmlAttr(Tag, 'Target');
      Target := StringReplace(Target, '\', '/', [rfReplaceAll]);
      if (Id <> '') and (Target <> '') then
        Map.AddOrSetValue(Id, Target);
      P := Gt + 1;
    end;
    P := 1;
    while P <= Length(BookXml) do
    begin
      P := Pos('<sheet', BookXml, P);
      if P = 0 then
        Break;
      if (P + 6 <= Length(BookXml)) and
         (BookXml[P + 6] <> '>') and (BookXml[P + 6] <> ' ') then
      begin
        Inc(P, 6);
        Continue;
      end;
      Gt := Pos('>', BookXml, P);
      if Gt = 0 then
        Break;
      Tag := Copy(BookXml, P, Gt - P + 1);
      SName := XmlAttr(Tag, 'name');
      Rid := XmlAttr(Tag, 'r:id');
      if Rid = '' then
        Rid := XmlAttr(Tag, 'id');
      if SName = '' then
        SName := 'Sheet' + IntToStr(Names.Count + 1);
      Target := '';
      if (Rid <> '') and Map.TryGetValue(Rid, Target) then
      begin
        if not StartsText('xl/', LowerCase(Target)) then
        begin
          if StartsText('/', Target) then
            Delete(Target, 1, 1)
          else if StartsText('../', Target) then
            Delete(Target, 1, 3)
          else
            Target := 'xl/' + Target;
        end;
      end;
      Names.Add(SName);
      Targets.Add(Target);
      P := Gt + 1;
      if Names.Count >= 20 then
        Break;
    end;
    if Names.Count = 0 then
    begin
      Names.Add('Sheet1');
      Targets.Add('xl/worksheets/sheet1.xml');
    end;
    for I := 0 to Targets.Count - 1 do
      if Targets[I] = '' then
        Targets[I] := 'xl/worksheets/sheet' + IntToStr(I + 1) + '.xml';
  finally
    Map.Free;
  end;
end;

type
  TXfStyle = record
    Fill: TAlphaColor;
    Text: TAlphaColor;
    HasFill: Boolean;
    HasText: Boolean;
  end;

function HexToColor(const S: string): TAlphaColor;
var
  H: string;
  V: Cardinal;
begin
  Result := 0;
  H := UpperCase(Trim(S));
  if StartsText('FF', H) and (Length(H) = 8) then
    Delete(H, 1, 2)
  else if Length(H) = 8 then
    H := Copy(H, 3, 6);
  if Length(H) <> 6 then
    Exit;
  V := StrToIntDef('$' + H, 0);
  Result := $FF000000 or V;
end;

function ApplyTint(C: TAlphaColor; Tint: Double): TAlphaColor;
var
  R, G, B: Double;
  Rec: TAlphaColorRec;
begin
  Rec.Color := C;
  R := Rec.R;
  G := Rec.G;
  B := Rec.B;
  if Tint < 0 then
  begin
    R := R * (1 + Tint);
    G := G * (1 + Tint);
    B := B * (1 + Tint);
  end
  else if Tint > 0 then
  begin
    R := R * (1 - Tint) + 255 * Tint;
    G := G * (1 - Tint) + 255 * Tint;
    B := B * (1 - Tint) + 255 * Tint;
  end;
  Rec.R := Byte(EnsureRange(Round(R), 0, 255));
  Rec.G := Byte(EnsureRange(Round(G), 0, 255));
  Rec.B := Byte(EnsureRange(Round(B), 0, 255));
  Rec.A := 255;
  Result := Rec.Color;
end;

function ParseOOXMLColor(const Frag: string; const Theme: TArray<TAlphaColor>): TAlphaColor;
var
  Rgb, ThemeS, TintS: string;
  ThemeI, PCol: Integer;
  Tint: Double;
  FS: TFormatSettings;
begin
  Result := 0;
  Rgb := XmlAttr(Frag, 'rgb');
  if Rgb = '' then
  begin
    PCol := Pos('<color', Frag);
    if PCol > 1 then
      Exit(ParseOOXMLColor(Copy(Frag, PCol, 90), Theme));
  end;
  if Rgb <> '' then
    Exit(HexToColor(Rgb));
  ThemeS := XmlAttr(Frag, 'theme');
  if ThemeS <> '' then
  begin
    ThemeI := StrToIntDef(ThemeS, -1);
    if (ThemeI >= 0) and (ThemeI < Length(Theme)) then
      Result := Theme[ThemeI]
    else
      Result := $FF000000;
    TintS := XmlAttr(Frag, 'tint');
    if TintS <> '' then
    begin
      FS := TFormatSettings.Invariant;
      Tint := StrToFloatDef(StringReplace(TintS, ',', '.', []), 0, FS);
      Result := ApplyTint(Result, Tint);
    end;
    Exit;
  end;
  Rgb := XmlAttr(Frag, 'lastClr');
  if Rgb <> '' then
    Result := HexToColor(Rgb);
end;

function ColorTagOf(const Frag: string): string;
var
  P, Gt: Integer;
begin
  P := Pos('<color', Frag);
  if P = 0 then
    Exit(Frag);
  Gt := Pos('>', Frag, P);
  if Gt = 0 then
    Exit(Copy(Frag, P, 120));
  Result := Copy(Frag, P, Gt - P + 1);
end;

function IsExcelAutoFontColor(const FontFrag: string): Boolean;
var
  Tag, ThemeS, TintS, AutoS, IndexedS, Rgb: string;
begin
  { Excel Automatic: <color theme="1"/> — в схеме это lt1/белый,
    на листе рисуется чёрный текст (windowText), не белый. }
  Tag := ColorTagOf(FontFrag);
  AutoS := XmlAttr(Tag, 'auto');
  if AutoS = '1' then
    Exit(True);
  IndexedS := XmlAttr(Tag, 'indexed');
  if IndexedS = '64' then
    Exit(True);
  Rgb := XmlAttr(Tag, 'rgb');
  if Rgb <> '' then
    Exit(False);
  ThemeS := XmlAttr(Tag, 'theme');
  TintS := XmlAttr(Tag, 'tint');
  Result := (ThemeS = '1') and
    ((TintS = '') or (StrToFloatDef(StringReplace(TintS, ',', '.', []), 0,
      TFormatSettings.Invariant) = 0));
end;

function DefaultThemeColors: TArray<TAlphaColor>;
begin
  SetLength(Result, 12);
  Result[0] := $FF000000;
  Result[1] := $FFFFFFFF;
  Result[2] := $FF44546A;
  Result[3] := $FFE7E6E6;
  Result[4] := $FF5B9BD5;
  Result[5] := $FFED7D31;
  Result[6] := $FFA5A5A5;
  Result[7] := $FFFFC000;
  Result[8] := $FF4472C4;
  Result[9] := $FF70AD47;
  Result[10] := $FF0563C1;
  Result[11] := $FF954F72;
end;

procedure ParseThemeColors(const ThemeXml: string; var Theme: TArray<TAlphaColor>);
var
  Names: array[0..11] of string;
  I, P, Gt: Integer;
  Frag: string;
  C: TAlphaColor;
begin
  Theme := DefaultThemeColors;
  Names[0] := 'dk1'; Names[1] := 'lt1'; Names[2] := 'dk2'; Names[3] := 'lt2';
  Names[4] := 'accent1'; Names[5] := 'accent2'; Names[6] := 'accent3';
  Names[7] := 'accent4'; Names[8] := 'accent5'; Names[9] := 'accent6';
  Names[10] := 'hlink'; Names[11] := 'folHlink';
  for I := 0 to 11 do
  begin
    P := Pos('<a:' + Names[I], ThemeXml);
    if P = 0 then
      P := Pos('<' + Names[I], ThemeXml);
    if P = 0 then
      Continue;
    Gt := Pos('</a:' + Names[I] + '>', ThemeXml, P);
    if Gt = 0 then
      Gt := Min(Length(ThemeXml), P + 280);
    Frag := Copy(ThemeXml, P, Gt - P + 1);
    C := ParseOOXMLColor(Frag, Theme);
    if C = 0 then
    begin
      if Pos('srgbClr', Frag) > 0 then
        C := HexToColor(XmlAttr(Copy(Frag, Pos('srgbClr', Frag), 60), 'val'));
      if C = 0 then
        C := HexToColor(XmlAttr(Frag, 'lastClr'));
    end;
    if C <> 0 then
      Theme[I] := C or $FF000000;
  end;
end;

function ExtractBlocks(const Xml, OpenTag, CloseTag: string): TArray<string>;
var
  P, Gt, CloseP: Integer;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    P := 1;
    while P <= Length(Xml) do
    begin
      P := Pos(OpenTag, Xml, P);
      if P = 0 then
        Break;
      Gt := Pos('>', Xml, P);
      if Gt = 0 then
        Break;
      if (Gt > P) and (Xml[Gt - 1] = '/') then
      begin
        List.Add(Copy(Xml, P, Gt - P + 1));
        P := Gt + 1;
        Continue;
      end;
      CloseP := Pos(CloseTag, Xml, Gt + 1);
      if CloseP = 0 then
        Break;
      List.Add(Copy(Xml, P, CloseP + Length(CloseTag) - P));
      P := CloseP + Length(CloseTag);
      if List.Count > 4000 then
        Break;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure ParseCellStyles(const StyleXml: string; const Theme: TArray<TAlphaColor>;
  out Styles: TArray<TXfStyle>);
var
  Fonts, Fills, Xfs: TArray<string>;
  FontCols, FillCols: TArray<TAlphaColor>;
  FontHas, FillHas: TArray<Boolean>;
  I, Fid, FillId: Integer;
  Frag, Pat: string;
  C: TAlphaColor;
begin
  SetLength(Styles, 0);
  Fonts := ExtractBlocks(StyleXml, '<font', '</font>');
  Fills := ExtractBlocks(StyleXml, '<fill', '</fill>');
  Xfs := ExtractBlocks(StyleXml, '<xf', '</xf>');
  if Length(Xfs) = 0 then
    Xfs := ExtractBlocks(StyleXml, '<xf ', '/>');
  SetLength(FontCols, Length(Fonts));
  SetLength(FontHas, Length(Fonts));
  for I := 0 to High(Fonts) do
  begin
    if IsExcelAutoFontColor(Fonts[I]) then
    begin
      FontCols[I] := 0;
      FontHas[I] := False;
    end
    else
    begin
      C := ParseOOXMLColor(Fonts[I], Theme);
      FontCols[I] := C;
      FontHas[I] := C <> 0;
    end;
  end;
  SetLength(FillCols, Length(Fills));
  SetLength(FillHas, Length(Fills));
  for I := 0 to High(Fills) do
  begin
    Pat := LowerCase(XmlAttr(Fills[I], 'patternType'));
    if (Pat = 'none') or (Pat = 'gray125') then
      Continue;
    Frag := Fills[I];
    if Pos('<fgColor', Frag) > 0 then
      Frag := Copy(Frag, Pos('<fgColor', Frag), 120);
    C := ParseOOXMLColor(Frag, Theme);
    if (C = 0) and (Pat = 'solid') then
      C := ParseOOXMLColor(Fills[I], Theme);
    FillCols[I] := C;
    FillHas[I] := (C <> 0) and (Pat <> 'none');
    if (Pat = 'solid') and (C = 0) then
    begin
      { solid без rgb — часто theme }
      FillHas[I] := False;
    end;
  end;
  { cellXfs идут после cellStyleXfs: берём xf внутри cellXfs }
  Frag := StyleXml;
  if Pos('<cellXfs', Frag) > 0 then
    Xfs := ExtractBlocks(Copy(Frag, Pos('<cellXfs', Frag), MaxInt), '<xf', '</xf>');
  if Length(Xfs) = 0 then
    if Pos('<cellXfs', StyleXml) > 0 then
      Xfs := ExtractBlocks(Copy(StyleXml, Pos('<cellXfs', StyleXml), MaxInt), '<xf ', '/>');
  SetLength(Styles, Length(Xfs));
  for I := 0 to High(Xfs) do
  begin
    Fid := StrToIntDef(XmlAttr(Xfs[I], 'fontId'), 0);
    FillId := StrToIntDef(XmlAttr(Xfs[I], 'fillId'), 0);
    if (Fid >= 0) and (Fid < Length(FontCols)) then
    begin
      Styles[I].Text := FontCols[Fid];
      Styles[I].HasText := FontHas[Fid];
    end;
    if (FillId >= 0) and (FillId < Length(FillCols)) then
    begin
      Styles[I].Fill := FillCols[FillId];
      Styles[I].HasFill := FillHas[FillId];
    end;
  end;
end;

function GuessKind(const Typ, Val: string): TSpreadCellKind;
var
  N: Double;
begin
  if Typ = 's' then
    Exit(sckText);
  if Typ = 'inlinestr' then
    Exit(sckText);
  if Typ = 'str' then
    Exit(sckText);
  if Typ = 'b' then
    Exit(sckBool);
  if Typ = 'e' then
    Exit(sckError);
  if TryStrToFloat(Val, N, TFormatSettings.Invariant) then
    Exit(sckNumber);
  if Trim(Val) = '' then
    Exit(sckEmpty);
  Result := sckText;
end;

function AttrFloat(const Tag, Name: string; Def: Double): Double;
var
  S: string;
  FS: TFormatSettings;
begin
  S := XmlAttr(Tag, Name);
  if S = '' then
    Exit(Def);
  FS := TFormatSettings.Invariant;
  Result := StrToFloatDef(StringReplace(S, ',', '.', []), Def, FS);
end;

function ExcelColWidthToPx(W: Double): Single;
begin
  if W <= 0 then
    Exit(0);
  { MDW=7 для Calibri 11 @ 96dpi — как в Excel. }
  Result := Max(4, ((256 * W + Trunc(128 / 7)) / 256) * 7);
end;

function ExcelRowHeightToPx(Ht: Double): Single;
begin
  if Ht <= 0 then
    Exit(0);
  Result := Max(4, Ht * 96 / 72);
end;

procedure ParseSheetLayout(const SheetXml: string; ASheet: TSpreadSheet;
  MaxRows, MaxCols: Integer);
var
  P, Gt, CloseP, R, C1, C2: Integer;
  Tag, Ref, Hidden: string;
  W: Double;
begin
  ASheet.DefaultColW := ExcelColWidthToPx(8.43);
  ASheet.DefaultRowH := ExcelRowHeightToPx(15);
  P := Pos('<sheetFormatPr', SheetXml);
  if P > 0 then
  begin
    Gt := Pos('>', SheetXml, P);
    if Gt > 0 then
    begin
      Tag := Copy(SheetXml, P, Gt - P + 1);
      if XmlAttr(Tag, 'defaultColWidth') <> '' then
        ASheet.DefaultColW := ExcelColWidthToPx(AttrFloat(Tag, 'defaultColWidth', 8.43));
      if XmlAttr(Tag, 'defaultRowHeight') <> '' then
        ASheet.DefaultRowH := ExcelRowHeightToPx(AttrFloat(Tag, 'defaultRowHeight', 15));
    end;
  end;
  P := Pos('<dimension', SheetXml);
  if P > 0 then
  begin
    Gt := Pos('>', SheetXml, P);
    if Gt > 0 then
    begin
      Tag := Copy(SheetXml, P, Gt - P + 1);
      Ref := XmlAttr(Tag, 'ref');
      if Pos(':', Ref) > 0 then
        Ref := Copy(Ref, Pos(':', Ref) + 1, MaxInt);
      if CellRefToRC(Ref, R, C1) then
        ASheet.GrowTo(Min(R, MaxRows), Min(C1, MaxCols));
    end;
  end;
  P := Pos('<cols', SheetXml);
  if P > 0 then
  begin
    CloseP := Pos('</cols>', SheetXml, P);
    if CloseP = 0 then
      CloseP := Length(SheetXml);
    while P < CloseP do
    begin
      P := Pos('<col', SheetXml, P);
      if (P = 0) or (P > CloseP) then
        Break;
      Gt := Pos('>', SheetXml, P);
      if Gt = 0 then
        Break;
      Tag := Copy(SheetXml, P, Gt - P + 1);
      C1 := StrToIntDef(XmlAttr(Tag, 'min'), 0);
      C2 := StrToIntDef(XmlAttr(Tag, 'max'), C1);
      Hidden := XmlAttr(Tag, 'hidden');
      if Hidden = '1' then
        W := 0
      else
        W := AttrFloat(Tag, 'width', 8.43);
      if (C1 >= 1) then
        ASheet.SetColWidth(C1, Min(C2, MaxCols), ExcelColWidthToPx(W));
      P := Gt + 1;
    end;
  end;
  P := 1;
  while P <= Length(SheetXml) do
  begin
    P := Pos('<row', SheetXml, P);
    if P = 0 then
      Break;
    if (P + 4 <= Length(SheetXml)) and
       (SheetXml[P + 4] <> ' ') and (SheetXml[P + 4] <> '>') then
    begin
      Inc(P, 4);
      Continue;
    end;
    Gt := Pos('>', SheetXml, P);
    if Gt = 0 then
      Break;
    Tag := Copy(SheetXml, P, Gt - P + 1);
    R := StrToIntDef(XmlAttr(Tag, 'r'), 0);
    if (R >= 1) and (R <= MaxRows) then
    begin
      Hidden := XmlAttr(Tag, 'hidden');
      if Hidden = '1' then
        ASheet.SetRowHeight(R, 0)
      else if XmlAttr(Tag, 'ht') <> '' then
        ASheet.SetRowHeight(R, ExcelRowHeightToPx(AttrFloat(Tag, 'ht', 15)));
    end;
    P := Gt + 1;
  end;
end;

procedure ParseSheetXml(const SheetXml: string; const Shared: TArray<string>;
  const Styles: TArray<TXfStyle>; ASheet: TSpreadSheet; MaxRows, MaxCols: Integer);
var
  P, Gt, CloseP, Row, Col, Idx, StyleI: Integer;
  Tag, Inner, Ref, Typ, Val: string;
  SelfClose: Boolean;
  Kind: TSpreadCellKind;
  Fill, Txt: TAlphaColor;
  HasFill, HasTxt: Boolean;
begin
  ParseSheetLayout(SheetXml, ASheet, MaxRows, MaxCols);
  P := 1;
  while P <= Length(SheetXml) do
  begin
    P := Pos('<c', SheetXml, P);
    if P = 0 then
      Break;
    if (P + 2 <= Length(SheetXml)) and
       (SheetXml[P + 2] <> '>') and (SheetXml[P + 2] <> ' ') and
       (SheetXml[P + 2] <> '/') then
    begin
      Inc(P, 2);
      Continue;
    end;
    Gt := Pos('>', SheetXml, P);
    if Gt = 0 then
      Break;
    SelfClose := (Gt > P) and (SheetXml[Gt - 1] = '/');
    Tag := Copy(SheetXml, P, Gt - P + 1);
    Ref := XmlAttr(Tag, 'r');
    if not CellRefToRC(Ref, Row, Col) then
    begin
      P := Gt + 1;
      Continue;
    end;
    if (Row > MaxRows) or (Col > MaxCols) then
    begin
      ASheet.Truncated := True;
      if SelfClose then
        P := Gt + 1
      else
      begin
        CloseP := Pos('</c>', SheetXml, Gt + 1);
        if CloseP = 0 then
          Break;
        P := CloseP + 4;
      end;
      Continue;
    end;
    Inner := '';
    CloseP := Gt;
    if not SelfClose then
    begin
      CloseP := Pos('</c>', SheetXml, Gt + 1);
      if CloseP = 0 then
        Break;
      Inner := Copy(SheetXml, Gt + 1, CloseP - Gt - 1);
    end;
    StyleI := StrToIntDef(XmlAttr(Tag, 's'), -1);
    HasFill := False;
    HasTxt := False;
    Fill := 0;
    Txt := 0;
    if (StyleI >= 0) and (StyleI < Length(Styles)) then
    begin
      HasFill := Styles[StyleI].HasFill;
      HasTxt := Styles[StyleI].HasText;
      Fill := Styles[StyleI].Fill;
      Txt := Styles[StyleI].Text;
    end;
    Typ := LowerCase(XmlAttr(Tag, 't'));
    if Typ = 's' then
    begin
      Idx := StrToIntDef(XmlInnerTag(Inner, 'v'), -1);
      if (Idx >= 0) and (Idx < Length(Shared)) then
        Val := Shared[Idx]
      else
        Val := '';
      Kind := sckText;
    end
    else if Typ = 'inlinestr' then
    begin
      Val := ExtractTRuns(Inner);
      Kind := sckText;
    end
    else if Typ = 'b' then
    begin
      if Trim(XmlInnerTag(Inner, 'v')) = '1' then
        Val := 'TRUE'
      else
        Val := 'FALSE';
      Kind := sckBool;
    end
    else if Typ = 'e' then
    begin
      Val := XmlInnerTag(Inner, 'v');
      Kind := sckError;
    end
    else
    begin
      Val := XmlInnerTag(Inner, 'v');
      if Val = '' then
        Val := ExtractTRuns(Inner);
      Kind := GuessKind(Typ, Val);
    end;
    if (Val <> '') or HasFill then
      ASheet.Put(Row, Col, Val, Kind, Fill, Txt, HasFill, HasTxt);
    if SelfClose then
      P := Gt + 1
    else
      P := CloseP + 4;
  end;
end;

procedure TryLoadSheetImages(Zip: TZipFile; const SheetPath: string; ASheet: TSpreadSheet);
var
  SheetRels, DrawXml, DrawRels, Media, RelPath, DrawPath, Target, Id: string;
  Dir, Base: string;
  P, Gt, CloseP, Col, Row, Slash, NextFrom, BlipP, D: Integer;
  Tag: string;
  Map: TDictionary<string, string>;
  Bytes: TBytes;
  MS: TMemoryStream;
  Img: TSpreadImage;
  Bmp: TBitmap;
  Drawings: TStringList;
begin
  Dir := StringReplace(SheetPath, '\', '/', [rfReplaceAll]);
  Slash := LastDelimiter('/', Dir);
  if Slash > 0 then
    Base := Copy(Dir, 1, Slash)
  else
    Base := 'xl/worksheets/';
  SheetRels := ZipReadUtf8(Zip, Copy(Base, 1, Length(Base) - 1) + '/_rels/' +
    ExtractFileName(StringReplace(SheetPath, '/', '\', [rfReplaceAll])) + '.rels');
  if SheetRels = '' then
    SheetRels := ZipReadUtf8(Zip, 'xl/worksheets/_rels/sheet1.xml.rels');
  Drawings := TStringList.Create;
  Drawings.Sorted := True;
  Drawings.Duplicates := dupIgnore;
  try
  P := 1;
  while P <= Length(SheetRels) do
  begin
    P := Pos('<Relationship', SheetRels, P);
    if P = 0 then
      Break;
    Gt := Pos('/>', SheetRels, P);
    if Gt = 0 then
      Gt := Pos('>', SheetRels, P);
    if Gt = 0 then
      Break;
    Tag := Copy(SheetRels, P, Gt - P + 2);
    Target := XmlAttr(Tag, 'Target');
    if Pos('drawing', LowerCase(Target)) > 0 then
    begin
      Target := StringReplace(Target, '\', '/', [rfReplaceAll]);
      if StartsText('../', Target) then
        DrawPath := 'xl/' + Copy(Target, 4, MaxInt)
      else if StartsText('xl/', Target) then
        DrawPath := Target
      else
        DrawPath := 'xl/drawings/' + ExtractFileName(Target);
      if DrawPath <> '' then
        Drawings.Add(DrawPath);
    end;
    P := Gt + 1;
  end;
  for D := 0 to Drawings.Count - 1 do
  begin
  DrawPath := Drawings[D];
  DrawXml := ZipReadUtf8(Zip, DrawPath);
  DrawRels := ZipReadUtf8(Zip, 'xl/drawings/_rels/' + ExtractFileName(StringReplace(DrawPath, '/', '\', [rfReplaceAll])) + '.rels');
  Map := TDictionary<string, string>.Create;
  try
    P := 1;
    while P <= Length(DrawRels) do
    begin
      P := Pos('<Relationship', DrawRels, P);
      if P = 0 then
        Break;
      Gt := Pos('/>', DrawRels, P);
      if Gt = 0 then
        Gt := Pos('>', DrawRels, P);
      if Gt = 0 then
        Break;
      Tag := Copy(DrawRels, P, Gt - P + 2);
      Id := XmlAttr(Tag, 'Id');
      Target := XmlAttr(Tag, 'Target');
      if (Id <> '') and (Target <> '') then
        Map.AddOrSetValue(Id, Target);
      P := Gt + 1;
    end;
    P := 1;
    while P <= Length(DrawXml) do
    begin
      P := Pos('<xdr:from>', DrawXml, P);
      if P = 0 then
        Break;
      Gt := Pos('</xdr:from>', DrawXml, P);
      if Gt = 0 then
        Break;
      Tag := Copy(DrawXml, P, Gt - P);
      Col := StrToIntDef(XmlInnerTag(Tag, 'xdr:col'), 0) + 1;
      Row := StrToIntDef(XmlInnerTag(Tag, 'xdr:row'), 0) + 1;
      RelPath := '';
      NextFrom := Pos('<xdr:from>', DrawXml, Gt + 1);
      if NextFrom = 0 then
        NextFrom := Length(DrawXml) + 1;
      BlipP := Pos('<a:blip', DrawXml, P);
      if (BlipP > 0) and (BlipP < NextFrom) then
      begin
        CloseP := Pos('/>', DrawXml, BlipP);
        if (CloseP = 0) or (CloseP > NextFrom) then
          CloseP := Pos('>', DrawXml, BlipP);
        if (CloseP > 0) and (CloseP < NextFrom) then
        begin
          Tag := Copy(DrawXml, BlipP, CloseP - BlipP + 2);
          Id := XmlAttr(Tag, 'r:embed');
          if Id = '' then
            Id := XmlAttr(Tag, 'embed');
          Map.TryGetValue(Id, RelPath);
        end;
      end;
      P := NextFrom;
      if RelPath = '' then
        Continue;
      RelPath := StringReplace(RelPath, '\', '/', [rfReplaceAll]);
      if StartsText('../media/', RelPath) then
        Media := 'xl/media/' + Copy(RelPath, 10, MaxInt)
      else if StartsText('xl/media/', RelPath) then
        Media := RelPath
      else
        Media := 'xl/media/' + ExtractFileName(RelPath);
      Bytes := ZipReadBytes(Zip, Media);
      if Length(Bytes) < 16 then
        Continue;
      MS := TMemoryStream.Create;
      Bmp := TBitmap.Create;
      try
        MS.WriteBuffer(Bytes[0], Length(Bytes));
        MS.Position := 0;
        try
          Bmp.LoadFromStream(MS);
        except
          FreeAndNil(Bmp);
        end;
        if Assigned(Bmp) and (Bmp.Width > 0) then
        begin
          Img := TSpreadImage.Create;
          Img.Col := Col;
          Img.Row := Row;
          Img.Bitmap := Bmp;
          Img.WidthPx := Bmp.Width;
          Img.HeightPx := Bmp.Height;
          Bmp := nil;
          ASheet.Images.Add(Img);
          ASheet.Put(Row, Col, '[img]', sckImage);
        end;
      finally
        Bmp.Free;
        MS.Free;
      end;
    end;
  finally
    Map.Free;
  end;
  end;
  finally
    Drawings.Free;
  end;
end;

function DetectCsvDelim(const Sample: string; AForceTab: Boolean): Char;
var
  Commas, Semis, Tabs, I, LineEnd: Integer;
  Line: string;
begin
  if AForceTab then
    Exit(#9);
  LineEnd := Pos(#10, Sample);
  if LineEnd = 0 then
    Line := Sample
  else
    Line := Copy(Sample, 1, LineEnd);
  Commas := 0;
  Semis := 0;
  Tabs := 0;
  for I := 1 to Length(Line) do
    case Line[I] of
      ',': Inc(Commas);
      ';': Inc(Semis);
      #9: Inc(Tabs);
    end;
  if (Tabs >= Commas) and (Tabs >= Semis) and (Tabs > 0) then
    Result := #9
  else if Semis > Commas then
    Result := ';'
  else
    Result := ',';
end;

procedure ParseCsvText(const Text: string; ASheet: TSpreadSheet;
  ADelim: Char; MaxRows, MaxCols: Integer);
var
  I, Row, Col, L: Integer;
  Cell: string;
  InQ: Boolean;
  Ch: Char;
  procedure Flush;
  var
    Kind: TSpreadCellKind;
    N: Double;
  begin
    if (Row <= MaxRows) and (Col <= MaxCols) then
    begin
      if TryStrToFloat(Trim(Cell), N, TFormatSettings.Invariant) and (Cell <> '') then
        Kind := sckNumber
      else if Cell = '' then
        Kind := sckEmpty
      else
        Kind := sckText;
      if Cell <> '' then
        ASheet.Put(Row, Col, Cell, Kind);
    end
    else if (Row > MaxRows) or (Col > MaxCols) then
      ASheet.Truncated := True;
    Cell := '';
  end;
begin
  Row := 1;
  Col := 1;
  Cell := '';
  InQ := False;
  L := Length(Text);
  I := 1;
  while I <= L do
  begin
    Ch := Text[I];
    if InQ then
    begin
      if Ch = '"' then
      begin
        if (I < L) and (Text[I + 1] = '"') then
        begin
          Cell := Cell + '"';
          Inc(I);
        end
        else
          InQ := False;
      end
      else
        Cell := Cell + Ch;
    end
    else if Ch = '"' then
      InQ := True
    else if Ch = ADelim then
    begin
      Flush;
      Inc(Col);
    end
    else if (Ch = #10) or (Ch = #13) then
    begin
      Flush;
      if (Ch = #13) and (I < L) and (Text[I + 1] = #10) then
        Inc(I);
      Inc(Row);
      Col := 1;
      if Row > MaxRows + 2 then
      begin
        ASheet.Truncated := True;
        Break;
      end;
    end
    else
      Cell := Cell + Ch;
    Inc(I);
  end;
  if Cell <> '' then
    Flush;
end;

function LoadCsv(const APath: string; MaxRows, MaxCols: Integer;
  out AError: string): TSpreadWorkbook;
var
  Bytes: TBytes;
  Text, EncLabel: string;
  Sheet: TSpreadSheet;
  Ext: string;
  FS: TFileStream;
begin
  Result := nil;
  AError := '';
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, FS.Size);
      if Length(Bytes) > 0 then
        FS.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
    Text := DecodeLooseText(Bytes, EncLabel);
    Result := TSpreadWorkbook.Create;
    Result.FilePath := APath;
    Result.EncodingLabel := EncLabel;
    Sheet := TSpreadSheet.Create;
    Ext := LowerCase(ExtractFileExt(APath));
    if Ext = '.tsv' then
      Sheet.Name := 'TSV'
    else
      Sheet.Name := 'CSV';
    ParseCsvText(Text, Sheet, DetectCsvDelim(Copy(Text, 1, 2000), Ext = '.tsv'),
      MaxRows, MaxCols);
    Result.Sheets.Add(Sheet);
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      AError := E.Message;
    end;
  end;
end;

function LoadXlsx(const APath: string; MaxRows, MaxCols: Integer;
  out AError: string): TSpreadWorkbook;
var
  Zip: TZipFile;
  Stream: TFileStream;
  BookXml, RelsXml, SharedXml, SheetXml, StyleXml, ThemeXml: string;
  Shared: TArray<string>;
  Names, Targets: TStringList;
  I: Integer;
  Sheet: TSpreadSheet;
  Theme: TArray<TAlphaColor>;
  Styles: TArray<TXfStyle>;
begin
  Result := nil;
  AError := '';
  Zip := nil;
  Stream := nil;
  Names := TStringList.Create;
  Targets := TStringList.Create;
  try
    try
      Zip := ZipOpenShared(APath, Stream);
      BookXml := ZipReadUtf8(Zip, 'xl/workbook.xml');
      RelsXml := ZipReadUtf8(Zip, 'xl/_rels/workbook.xml.rels');
      SharedXml := ZipReadUtf8(Zip, 'xl/sharedStrings.xml');
      StyleXml := ZipReadUtf8(Zip, 'xl/styles.xml');
      ThemeXml := ZipReadUtf8(Zip, 'xl/theme/theme1.xml');
      if SharedXml <> '' then
        Shared := CollectSharedStrings(SharedXml)
      else
        SetLength(Shared, 0);
      ParseThemeColors(ThemeXml, Theme);
      ParseCellStyles(StyleXml, Theme, Styles);
      CollectWorkbookSheets(BookXml, RelsXml, Names, Targets);
      Result := TSpreadWorkbook.Create;
      Result.FilePath := APath;
      for I := 0 to Names.Count - 1 do
      begin
        SheetXml := ZipReadUtf8(Zip, Targets[I]);
        if SheetXml = '' then
          Continue;
        Sheet := TSpreadSheet.Create;
        Sheet.Name := Names[I];
        ParseSheetXml(SheetXml, Shared, Styles, Sheet, MaxRows, MaxCols);
        try
          TryLoadSheetImages(Zip, Targets[I], Sheet);
        except
        end;
        Result.Sheets.Add(Sheet);
      end;
      if Result.Sheets.Count = 0 then
      begin
        FreeAndNil(Result);
        AError := 'В книге нет листов';
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        AError := E.Message;
      end;
    end;
  finally
    Names.Free;
    Targets.Free;
    if Assigned(Zip) then
    begin
      Zip.Close;
      Zip.Free;
    end;
    Stream.Free;
  end;
end;

function LoadWorkbookLimited(const APath: string; MaxRows, MaxCols: Integer;
  out AError: string): TSpreadWorkbook;
var
  Ext: string;
  Sz: Int64;
begin
  Result := nil;
  AError := '';
  if (APath = '') or not TFile.Exists(APath) then
  begin
    AError := 'Файл не найден';
    Exit;
  end;
  if not IsSpreadsheetFile(APath) then
  begin
    AError := 'Формат не поддерживается';
    Exit;
  end;
  try
    Sz := TFile.GetSize(APath);
  except
    Sz := 0;
  end;
  if Sz > SpreadQVMaxBytes then
  begin
    AError := 'Файл слишком большой для просмотра';
    Exit;
  end;
  if MaxRows < 1 then
    MaxRows := SpreadQVMaxRows;
  if MaxCols < 1 then
    MaxCols := SpreadQVMaxCols;
  Ext := LowerCase(ExtractFileExt(APath));
  if MatchText(Ext, ['.csv', '.tsv']) then
    Result := LoadCsv(APath, MaxRows, MaxCols, AError)
  else if MatchText(Ext, ['.xlsx', '.xlsm']) then
    Result := LoadXlsx(APath, MaxRows, MaxCols, AError)
  else
    AError := 'Формат не поддерживается';
end;

procedure DrawEllipsis(ACanvas: TCanvas; const ARect: TRectF; const AText: string;
  AColor: TAlphaColor; ASize: Single; ARight: Boolean);
var
  Flags: TFillTextFlags;
begin
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AColor;
  ACanvas.Font.Family := 'Segoe UI';
  ACanvas.Font.Size := ASize;
  Flags := [];
  if ARight then
    ACanvas.FillText(ARect, AText, False, 1, Flags, TTextAlign.Trailing, TTextAlign.Center)
  else
    ACanvas.FillText(ARect, AText, False, 1, Flags, TTextAlign.Leading, TTextAlign.Center);
end;

function RenderSpreadsheetThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;
var
  Wb: TSpreadWorkbook;
  Sheet: TSpreadSheet;
  Err, Title, Ext, CellText: string;
  Sz: Int64;
  Rows, Cols, R, C, MaxR, MaxC: Integer;
  HeaderH, Acc, ContentW, ContentH, Scale, X, Y, CW, CH, FontSz: Single;
  CellR, HeadR, ImgR, PageR: TRectF;
  Kind: TSpreadCellKind;
  Cell: TSpreadCell;
  FillC, TextC: TAlphaColor;
  Img: TSpreadImage;
  Cnv: TCanvas;
  State: TCanvasSaveState;
begin
  Result := False;
  if (ABitmap = nil) or (AWidth < 16) or (AHeight < 16) then
    Exit;
  if not IsSpreadsheetThumbExt(APath) then
    Exit;
  try
    Sz := TFile.GetSize(APath);
  except
    Exit;
  end;
  if Sz > SpreadThumbMaxBytes then
    Exit;
  Wb := LoadWorkbookLimited(APath, SpreadThumbMaxRows, SpreadThumbMaxCols, Err);
  try
    if (Wb = nil) or (Wb.Sheets.Count = 0) then
      Exit;
    Sheet := Wb.Sheets[0];
    Ext := UpperCase(Copy(ExtractFileExt(APath), 2, 8));
    if Ext = '' then
      Ext := 'XLS';
    Title := Sheet.Name;
    if Title = '' then
      Title := Ext;
    ABitmap.SetSize(AWidth, AHeight);
    if not ABitmap.Canvas.BeginScene then
    begin
      ABitmap.Clear($FFFFFFFF);
      Exit(ABitmap.Width > 0);
    end;
    try
      Cnv := ABitmap.Canvas;
      Cnv.Clear($FFFFFFFF);
      HeaderH := Max(14, AHeight * 0.12);
      HeadR := TRectF.Create(0, 0, AWidth, HeaderH);
      Cnv.Fill.Kind := TBrushKind.Solid;
      Cnv.Fill.Color := $FFF3F3F3;
      Cnv.FillRect(HeadR, 0, 0, [], 1);
      DrawEllipsis(Cnv, TRectF.Create(6, 0, AWidth - 6, HeaderH),
        Title, $FF222222, Max(8, HeaderH * 0.5), False);
      Rows := Max(1, Sheet.RowCount);
      Cols := Max(1, Sheet.ColCount);
      if (Sheet.RowCount = 0) or (Sheet.ColCount = 0) then
      begin
        DrawEllipsis(Cnv, TRectF.Create(8, HeaderH + 8, AWidth - 8, AHeight - 8),
          Ext, $FF666666, 18, False);
        Result := True;
        Exit;
      end;
      Acc := 0;
      MaxC := 0;
      for C := 1 to Cols do
      begin
        Acc := Acc + Sheet.ColWidth(C);
        MaxC := C;
        if Acc >= SpreadThumbPageW then
          Break;
      end;
      Acc := 0;
      MaxR := 0;
      for R := 1 to Rows do
      begin
        Acc := Acc + Sheet.RowHeight(R);
        MaxR := R;
        if Acc >= SpreadThumbPageH then
          Break;
      end;
      if MaxC < 1 then
        MaxC := 1;
      if MaxR < 1 then
        MaxR := 1;
      ContentW := 0;
      for C := 1 to MaxC do
        ContentW := ContentW + Sheet.ColWidth(C);
      ContentH := 0;
      for R := 1 to MaxR do
        ContentH := ContentH + Sheet.RowHeight(R);
      if ContentW < 1 then
        ContentW := 1;
      if ContentH < 1 then
        ContentH := 1;
      Scale := Min((AWidth - 2) / ContentW, (AHeight - HeaderH - 2) / ContentH);
      PageR := TRectF.Create(1, HeaderH + 1, 1 + ContentW * Scale,
        HeaderH + 1 + ContentH * Scale);
      Cnv.Fill.Color := $FFFFFFFF;
      Cnv.FillRect(PageR, 0, 0, [], 1);
      Cnv.Stroke.Kind := TBrushKind.Solid;
      Cnv.Stroke.Thickness := 1;
      Cnv.Stroke.Color := $FFD0D0D0;
      State := Cnv.SaveState;
      try
        Cnv.IntersectClipRect(PageR);
        Y := PageR.Top;
        for R := 1 to MaxR do
        begin
          CH := Sheet.RowHeight(R) * Scale;
          X := PageR.Left;
          for C := 1 to MaxC do
          begin
            CW := Sheet.ColWidth(C) * Scale;
            CellR := TRectF.Create(X, Y, X + CW, Y + CH);
            Cell := Sheet.Cell(R, C);
            if Cell.HasFill then
              FillC := Cell.FillColor
            else if Odd(R) then
              FillC := $FFF7F7F7
            else
              FillC := $FFFFFFFF;
            Cnv.Fill.Color := FillC;
            Cnv.FillRect(CellR, 0, 0, [], 1);
            Cnv.Stroke.Color := $FFE0E0E0;
            Cnv.DrawRect(CellR, 0, 0, [], 1);
            Kind := Cell.Kind;
            CellText := Cell.Value;
            Img := Sheet.ImageAt(R, C);
            if Assigned(Img) and Assigned(Img.Bitmap) and (Img.Bitmap.Width > 0) then
            begin
              ImgR := CellR;
              ImgR.Inflate(-1, -1);
              ImgR := FitAspectRect(ImgR, Img.Bitmap.Width, Img.Bitmap.Height);
              try
                Cnv.DrawBitmap(Img.Bitmap, Img.Bitmap.Bounds, ImgR, 1, True);
              except
              end;
            end
            else if CellText <> '' then
            begin
              if Cell.HasTextColor then
                TextC := Cell.TextColor
              else
                TextC := $FF222222;
              FontSz := Max(5, Min(11, CH * 0.62));
              DrawEllipsis(Cnv,
                TRectF.Create(CellR.Left + 1, CellR.Top, CellR.Right - 1, CellR.Bottom),
                CellText, TextC, FontSz, Kind = sckNumber);
            end;
            X := X + CW;
          end;
          Y := Y + CH;
        end;
      finally
        Cnv.RestoreState(State);
      end;
      Result := True;
    finally
      ABitmap.Canvas.EndScene;
    end;
  finally
    Wb.Free;
  end;
end;

end.
