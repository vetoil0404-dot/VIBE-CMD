unit uDocumentData;

{
  Модель документа + парсеры docx/docm/dotx/dotm/odt/rtf без Word COM.
  BuildLayout раскладывает блоки на страницы-листы (поля, переносы, таблицы).
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Types,
  System.UITypes, System.Math, FMX.Graphics, FMX.Types, FMX.TextLayout;

type
  TDocAlign = (daLeft, daCenter, daRight, daJustify);

  TDocRunStyle = record
    FontName: string;
    SizePt: Single;
    Bold: Boolean;
    Italic: Boolean;
    Underline: Boolean;
    Strike: Boolean;
    Color: TAlphaColor;
    Highlight: TAlphaColor;
    HasColor: Boolean;
    HasHighlight: Boolean;
    procedure InitDefault;
  end;

  TDocInlineKind = (dikText, dikImage, dikBreak, dikPageBreak, dikTab);

  TDocInline = class
  public
    Kind: TDocInlineKind;
    Style: TDocRunStyle;
    Text: string;
    Image: TBitmap;
    ImgW: Single;
    ImgH: Single;
    destructor Destroy; override;
  end;

  TDocPara = class
  public
    Align: TDocAlign;
    SpaceBefore: Single;
    SpaceAfter: Single;
    LeftInd: Single;
    RightInd: Single;
    FirstInd: Single;
    LineMult: Single;
    Fill: TAlphaColor;
    HasFill: Boolean;
    OutlineLvl: Integer;
    NumText: string;
    PageBreakBefore: Boolean;
    Inlines: TObjectList<TDocInline>;
    constructor Create;
    destructor Destroy; override;
  end;

  TDocCell = class
  public
    Paras: TObjectList<TDocPara>;
    Width: Single;
    Fill: TAlphaColor;
    HasFill: Boolean;
    Span: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TDocRow = class
  public
    Cells: TObjectList<TDocCell>;
    constructor Create;
    destructor Destroy; override;
  end;

  TDocTable = class
  public
    Rows: TObjectList<TDocRow>;
    ColW: TArray<Single>;
    constructor Create;
    destructor Destroy; override;
  end;

  TDocBlockKind = (dbkPara, dbkTable);

  TDocBlock = class
  public
    Kind: TDocBlockKind;
    Para: TDocPara;
    Table: TDocTable;
    destructor Destroy; override;
  end;

  TDocPaintKind = (dpkText, dpkImage, dpkFill, dpkLine);

  TDocPaintItem = class
  public
    Kind: TDocPaintKind;
    X, Y, W, H: Single;
    Text: string;
    Style: TDocRunStyle;
    Bitmap: TBitmap;
    Fill: TAlphaColor;
    Stroke: TAlphaColor;
  end;

  TDocLaidPage = class
  public
    PaperW: Single;
    PaperH: Single;
    MarginL: Single;
    MarginT: Single;
    MarginR: Single;
    MarginB: Single;
    Items: TObjectList<TDocPaintItem>;
    constructor Create;
    destructor Destroy; override;
  end;

  TDocDocument = class
  public
    FilePath: string;
    PaperW: Single;
    PaperH: Single;
    MarginL: Single;
    MarginT: Single;
    MarginR: Single;
    MarginB: Single;
    Blocks: TObjectList<TDocBlock>;
    Header: TObjectList<TDocPara>;
    Footer: TObjectList<TDocPara>;
    Images: TObjectList<TBitmap>;
    Pages: TObjectList<TDocLaidPage>;
    Truncated: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure BuildLayout;
    function PlainText: string;
  end;

function IsDocumentFile(const APath: string): Boolean;
function IsDocumentThumbExt(const APath: string): Boolean;
function IsMarkdownFile(const APath: string): Boolean;
function LoadTextDocumentFromString(const AText, APath: string;
  out AError: string): TDocDocument;
function LoadDocumentLimited(const APath: string; out AError: string): TDocDocument;
function RenderDocumentThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;

const
  { один множитель для замера и рисования; иначе глифы не лезут в бокс }
  DocViewFontMul = 1.35;
  DocQVMaxBytes = 30 * 1024 * 1024;
  DocQVMaxBlocks = 2500;
  DocQVMaxPages = 80;
  DocQVMaxImages = 60;

implementation

uses
  System.Zip, System.IOUtils, System.StrUtils, System.Character;

type
  TStylePack = record
    Id: string;
    BasedOn: string;
    Para: TDocPara;
    Run: TDocRunStyle;
    HasPara: Boolean;
    HasRun: Boolean;
    Resolved: Boolean;
  end;

procedure TDocRunStyle.InitDefault;
begin
  FontName := 'Calibri';
  SizePt := 15;
  Bold := False;
  Italic := False;
  Underline := False;
  Strike := False;
  Color := $FF000000;
  Highlight := 0;
  HasColor := False;
  HasHighlight := False;
end;

destructor TDocInline.Destroy;
begin
  Image := nil;
  inherited;
end;

constructor TDocPara.Create;
begin
  inherited Create;
  Inlines := TObjectList<TDocInline>.Create(True);
  Align := daLeft;
  LineMult := 1.15;
  OutlineLvl := -1;
end;

destructor TDocPara.Destroy;
begin
  Inlines.Free;
  inherited;
end;

constructor TDocCell.Create;
begin
  inherited Create;
  Paras := TObjectList<TDocPara>.Create(True);
  Span := 1;
end;

destructor TDocCell.Destroy;
begin
  Paras.Free;
  inherited;
end;

constructor TDocRow.Create;
begin
  inherited Create;
  Cells := TObjectList<TDocCell>.Create(True);
end;

destructor TDocRow.Destroy;
begin
  Cells.Free;
  inherited;
end;

constructor TDocTable.Create;
begin
  inherited Create;
  Rows := TObjectList<TDocRow>.Create(True);
end;

destructor TDocTable.Destroy;
begin
  Rows.Free;
  inherited;
end;

destructor TDocBlock.Destroy;
begin
  Para.Free;
  Table.Free;
  inherited;
end;

constructor TDocLaidPage.Create;
begin
  inherited Create;
  Items := TObjectList<TDocPaintItem>.Create(True);
end;

destructor TDocLaidPage.Destroy;
begin
  Items.Free;
  inherited;
end;

constructor TDocDocument.Create;
begin
  inherited Create;
  Blocks := TObjectList<TDocBlock>.Create(True);
  Header := TObjectList<TDocPara>.Create(True);
  Footer := TObjectList<TDocPara>.Create(True);
  Images := TObjectList<TBitmap>.Create(True);
  Pages := TObjectList<TDocLaidPage>.Create(True);
  PaperW := 794;
  PaperH := 1123;
  MarginL := 96;
  MarginT := 96;
  MarginR := 96;
  MarginB := 96;
end;

destructor TDocDocument.Destroy;
begin
  Pages.Free;
  Blocks.Free;
  Header.Free;
  Footer.Free;
  Images.Free;
  inherited;
end;

function TwipPx(V: Double): Single;
begin
  Result := V / 15.0;
end;

function EmuPx(V: Double): Single;
begin
  Result := V / 9525.0;
end;

function PtPx(Pt: Single): Single;
begin
  Result := Pt * 96.0 / 72.0;
end;

function HexColor(const S: string): TAlphaColor;
var
  H: string;
  R, G, B: Integer;
begin
  Result := $FF000000;
  H := UpperCase(Trim(S));
  if (Length(H) = 8) and (H[1] = 'F') then
    Delete(H, 1, 2);
  if Length(H) < 6 then
    Exit;
  R := StrToIntDef('$' + Copy(H, 1, 2), 0);
  G := StrToIntDef('$' + Copy(H, 3, 2), 0);
  B := StrToIntDef('$' + Copy(H, 5, 2), 0);
  Result := $FF000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

function HighlightName(const S: string): TAlphaColor;
var
  N: string;
begin
  N := LowerCase(Trim(S));
  if N = 'yellow' then Exit($FFFFFF00);
  if N = 'green' then Exit($FF00FF00);
  if N = 'cyan' then Exit($FF00FFFF);
  if N = 'magenta' then Exit($FFFF00FF);
  if N = 'blue' then Exit($FF0000FF);
  if N = 'red' then Exit($FFFF0000);
  if N = 'darkblue' then Exit($FF000080);
  if N = 'darkcyan' then Exit($FF008080);
  if N = 'darkgreen' then Exit($FF008000);
  if N = 'darkmagenta' then Exit($FF800080);
  if N = 'darkred' then Exit($FF800000);
  if N = 'darkyellow' then Exit($FF808000);
  if N = 'darkgray' then Exit($FF808080);
  if N = 'lightgray' then Exit($FFC0C0C0);
  if N = 'black' then Exit($FF000000);
  Result := 0;
end;

function XmlUnescape(const S: string): string;
begin
  Result := S;
  if Pos('&', Result) = 0 then
    Exit;
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', #39, [rfReplaceAll]);
  Result := StringReplace(Result, '&#39;', #39, [rfReplaceAll]);
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

function IsNameChar(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
    ((C >= '0') and (C <= '9')) or (C = ':') or (C = '_') or (C = '-') or (C = '.');
end;

function ParseXmlName(const S: string; P: Integer): string;
var
  Q: Integer;
begin
  Q := P;
  while (Q <= Length(S)) and IsNameChar(S[Q]) do
    Inc(Q);
  Result := Copy(S, P, Q - P);
end;

function LocalName(const N: string): string;
var
  P: Integer;
begin
  P := Pos(':', N);
  if P > 0 then
    Result := Copy(N, P + 1, MaxInt)
  else
    Result := N;
end;

function XmlNextChild(const Xml: string; var P: Integer; out Name, OpenTag, Inner: string): Boolean;
var
  Lt, Gt, Q, Depth, CloseLt: Integer;
  N2: string;
  InnerStart: Integer;
begin
  Result := False;
  Name := '';
  OpenTag := '';
  Inner := '';
  while P <= Length(Xml) do
  begin
    Lt := Pos('<', Xml, P);
    if Lt = 0 then
    begin
      P := Length(Xml) + 1;
      Exit;
    end;
    if (Lt < Length(Xml)) and ((Xml[Lt + 1] = '/') or (Xml[Lt + 1] = '!') or (Xml[Lt + 1] = '?')) then
    begin
      Gt := Pos('>', Xml, Lt);
      if Gt = 0 then
      begin
        P := Length(Xml) + 1;
        Exit;
      end;
      P := Gt + 1;
      Continue;
    end;
    Name := ParseXmlName(Xml, Lt + 1);
    if Name = '' then
    begin
      P := Lt + 1;
      Continue;
    end;
    Gt := Pos('>', Xml, Lt);
    if Gt = 0 then
    begin
      P := Length(Xml) + 1;
      Exit;
    end;
    OpenTag := Copy(Xml, Lt, Gt - Lt + 1);
    if (Gt > Lt) and (Xml[Gt - 1] = '/') then
    begin
      Inner := '';
      P := Gt + 1;
      Exit(True);
    end;
    InnerStart := Gt + 1;
    Depth := 1;
    Q := InnerStart;
    while Q <= Length(Xml) do
    begin
      CloseLt := Pos('<', Xml, Q);
      if CloseLt = 0 then
        Break;
      if (CloseLt < Length(Xml)) and (Xml[CloseLt + 1] = '/') then
      begin
        N2 := ParseXmlName(Xml, CloseLt + 2);
        Gt := Pos('>', Xml, CloseLt);
        if Gt = 0 then
          Break;
        if N2 = Name then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Inner := Copy(Xml, InnerStart, CloseLt - InnerStart);
            P := Gt + 1;
            Exit(True);
          end;
        end;
        Q := Gt + 1;
      end
      else if (CloseLt < Length(Xml)) and ((Xml[CloseLt + 1] = '!') or (Xml[CloseLt + 1] = '?')) then
      begin
        Gt := Pos('>', Xml, CloseLt);
        if Gt = 0 then
          Break;
        Q := Gt + 1;
      end
      else
      begin
        N2 := ParseXmlName(Xml, CloseLt + 1);
        Gt := Pos('>', Xml, CloseLt);
        if Gt = 0 then
          Break;
        if (N2 = Name) and not ((Gt > CloseLt) and (Xml[Gt - 1] = '/')) then
          Inc(Depth);
        Q := Gt + 1;
      end;
    end;
    P := Length(Xml) + 1;
    Exit;
  end;
end;

function XmlFindLocalInner(const Xml, Want: string): string;
var
  P: Integer;
  Name, OT, Inn, Sub: string;
begin
  Result := '';
  if (Xml = '') or (Want = '') then
    Exit;
  P := 1;
  while XmlNextChild(Xml, P, Name, OT, Inn) do
  begin
    if SameText(LocalName(Name), Want) then
      Exit(Inn);
    Sub := XmlFindLocalInner(Inn, Want);
    if Sub <> '' then
      Exit(Sub);
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
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
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

function LoadBmp(const Bytes: TBytes): TBitmap;
var
  MS: TMemoryStream;
begin
  Result := nil;
  if Length(Bytes) < 16 then
    Exit;
  MS := TMemoryStream.Create;
  try
    MS.WriteBuffer(Bytes[0], Length(Bytes));
    MS.Position := 0;
    Result := TBitmap.Create;
    try
      Result.LoadFromStream(MS);
      if Result.Width <= 0 then
        FreeAndNil(Result);
    except
      FreeAndNil(Result);
    end;
  finally
    MS.Free;
  end;
end;

function MeasureRun(const S: string; const St: TDocRunStyle): TSizeF;
var
  L: TTextLayout;
  Fam: string;
  Approx: TSizeF;
begin
  if S = '' then
    Exit(TSizeF.Create(0, Max(PtPx(St.SizePt) * 1.2, 8)));
  if (Trim(S) = '') then
    Approx := TSizeF.Create(Max(2, Length(S) * PtPx(St.SizePt) * 0.28),
      Max(PtPx(St.SizePt) * 1.2, 8))
  else
    Approx := TSizeF.Create(
      Max(4, Length(S) * PtPx(St.SizePt) * 0.50),
      Max(PtPx(St.SizePt) * 1.2, 8));
  { TTextLayout с фонового потока даёт AV / stack overflow в FMX. }
  if TThread.CurrentThread.ThreadID <> MainThreadID then
    Exit(Approx);
  Fam := St.FontName;
  if Fam = '' then
    Fam := 'Calibri';
  L := nil;
  try
    L := TTextLayoutManager.DefaultTextLayout.Create;
    L.BeginUpdate;
    L.MaxSize := TPointF.Create(8000, 8000);
    L.Font.Family := Fam;
    L.Font.Size := Max(6, St.SizePt * DocViewFontMul);
    L.Font.Style := [];
    if St.Bold then
      L.Font.Style := L.Font.Style + [TFontStyle.fsBold];
    if St.Italic then
      L.Font.Style := L.Font.Style + [TFontStyle.fsItalic];
    L.WordWrap := False;
    L.HorizontalAlign := TTextAlign.Leading;
    L.VerticalAlign := TTextAlign.Leading;
    L.Text := S;
    L.EndUpdate;
    { не раздувать ширину — иначе пробелы становятся «дырами» между словами }
    Result := TSizeF.Create(
      Max(0.5, L.TextWidth),
      Max(L.TextHeight, PtPx(St.SizePt) * 1.2));
  except
    Result := Approx;
  end;
  L.Free;
end;

procedure MergeRun(var Dst: TDocRunStyle; const Src: TDocRunStyle; const HasFont: Boolean);
begin
  if HasFont and (Src.FontName <> '') then
    Dst.FontName := Src.FontName;
  if Src.SizePt > 0 then
    Dst.SizePt := Src.SizePt;
  Dst.Bold := Dst.Bold or Src.Bold;
  Dst.Italic := Dst.Italic or Src.Italic;
  Dst.Underline := Dst.Underline or Src.Underline;
  Dst.Strike := Dst.Strike or Src.Strike;
  if Src.HasColor then
  begin
    Dst.Color := Src.Color;
    Dst.HasColor := True;
  end;
  if Src.HasHighlight then
  begin
    Dst.Highlight := Src.Highlight;
    Dst.HasHighlight := True;
  end;
end;

procedure ApplyRPr(const Frag: string; var St: TDocRunStyle);
var
  P: Integer;
  Name, OpenTag, Inner: string;
  V, Sz: string;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    Name := LocalName(Name);
    if (Name = 'b') or (Name = 'bCs') then
      St.Bold := not SameText(XmlAttr(OpenTag, 'w:val'), '0') and
        not SameText(XmlAttr(OpenTag, 'val'), 'false')
    else if (Name = 'i') or (Name = 'iCs') then
      St.Italic := not SameText(XmlAttr(OpenTag, 'w:val'), '0')
    else if Name = 'u' then
      St.Underline := not SameText(XmlAttr(OpenTag, 'w:val'), 'none')
    else if (Name = 'strike') or (Name = 'dstrike') then
      St.Strike := True
    else if (Name = 'sz') or (Name = 'szCs') then
    begin
      Sz := XmlAttr(OpenTag, 'w:val');
      if Sz = '' then
        Sz := XmlAttr(OpenTag, 'val');
      if Sz <> '' then
        St.SizePt := StrToFloatDef(Sz, St.SizePt * 2) / 2.0;
    end
    else if Name = 'rFonts' then
    begin
      V := XmlAttr(OpenTag, 'w:ascii');
      if V = '' then
        V := XmlAttr(OpenTag, 'ascii');
      if V = '' then
        V := XmlAttr(OpenTag, 'w:hAnsi');
      if V = '' then
        V := XmlAttr(OpenTag, 'w:cs');
      if V = '' then
      begin
        V := XmlAttr(OpenTag, 'w:asciiTheme');
        if V = '' then
          V := XmlAttr(OpenTag, 'asciiTheme');
        if SameText(V, 'majorHAnsi') or SameText(V, 'majorAscii') or
           SameText(V, 'majorBidi') then
          V := 'Cambria'
        else if (V <> '') and StartsText('minor', LowerCase(V)) then
          V := 'Calibri'
        else
          V := '';
      end;
      if V <> '' then
        St.FontName := V;
    end
    else if Name = 'color' then
    begin
      V := XmlAttr(OpenTag, 'w:val');
      if V = '' then
        V := XmlAttr(OpenTag, 'val');
      if (V <> '') and not SameText(V, 'auto') then
      begin
        St.Color := HexColor(V);
        St.HasColor := True;
      end;
    end
    else if Name = 'highlight' then
    begin
      V := XmlAttr(OpenTag, 'w:val');
      if V = '' then
        V := XmlAttr(OpenTag, 'val');
      St.Highlight := HighlightName(V);
      St.HasHighlight := St.Highlight <> 0;
    end
    else if Name = 'shd' then
    begin
      V := XmlAttr(OpenTag, 'w:fill');
      if V = '' then
        V := XmlAttr(OpenTag, 'fill');
      if (V <> '') and not SameText(V, 'auto') then
      begin
        St.Highlight := HexColor(V);
        St.HasHighlight := True;
      end;
    end;
  end;
end;

procedure ApplyPPr(const Frag: string; Para: TDocPara; var St: TDocRunStyle); overload; forward;

procedure ApplyPPr(const Frag: string; Para: TDocPara); overload;
var
  Dummy: TDocRunStyle;
begin
  Dummy.InitDefault;
  Dummy.SizePt := 0;
  Dummy.FontName := '';
  ApplyPPr(Frag, Para, Dummy);
end;

procedure ApplyPPr(const Frag: string; Para: TDocPara; var St: TDocRunStyle); overload;
var
  P: Integer;
  Name, OpenTag, Inner, V: string;
  Line, LineRule: string;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    Name := LocalName(Name);
    if Name = 'jc' then
    begin
      V := LowerCase(XmlAttr(OpenTag, 'w:val'));
      if V = '' then
        V := LowerCase(XmlAttr(OpenTag, 'val'));
      if (V = 'center') or (V = 'centre') then
        Para.Align := daCenter
      else if (V = 'right') or (V = 'end') then
        Para.Align := daRight
      else if V = 'both' then
        Para.Align := daJustify
      else
        Para.Align := daLeft;
    end
    else if Name = 'spacing' then
    begin
      V := XmlAttr(OpenTag, 'w:before');
      if V = '' then
        V := XmlAttr(OpenTag, 'before');
      if V <> '' then
        Para.SpaceBefore := TwipPx(StrToFloatDef(V, 0));
      V := XmlAttr(OpenTag, 'w:after');
      if V = '' then
        V := XmlAttr(OpenTag, 'after');
      if V <> '' then
        Para.SpaceAfter := TwipPx(StrToFloatDef(V, 0));
      Line := XmlAttr(OpenTag, 'w:line');
      if Line = '' then
        Line := XmlAttr(OpenTag, 'line');
      LineRule := LowerCase(XmlAttr(OpenTag, 'w:lineRule'));
      if LineRule = '' then
        LineRule := LowerCase(XmlAttr(OpenTag, 'lineRule'));
      if Line <> '' then
      begin
        if (LineRule = '') or (LineRule = 'auto') then
          Para.LineMult := StrToFloatDef(Line, 240) / 240.0
        else
          Para.LineMult := Max(1, TwipPx(StrToFloatDef(Line, 240)) / 16);
      end;
    end
    else if Name = 'ind' then
    begin
      V := XmlAttr(OpenTag, 'w:left');
      if V = '' then
        V := XmlAttr(OpenTag, 'left');
      if V <> '' then
        Para.LeftInd := TwipPx(StrToFloatDef(V, 0));
      V := XmlAttr(OpenTag, 'w:right');
      if V = '' then
        V := XmlAttr(OpenTag, 'right');
      if V <> '' then
        Para.RightInd := TwipPx(StrToFloatDef(V, 0));
      V := XmlAttr(OpenTag, 'w:firstLine');
      if V = '' then
        V := XmlAttr(OpenTag, 'firstLine');
      if V <> '' then
        Para.FirstInd := TwipPx(StrToFloatDef(V, 0));
      V := XmlAttr(OpenTag, 'w:hanging');
      if V = '' then
        V := XmlAttr(OpenTag, 'hanging');
      if V <> '' then
        Para.FirstInd := -TwipPx(StrToFloatDef(V, 0));
    end
    else if Name = 'shd' then
    begin
      V := XmlAttr(OpenTag, 'w:fill');
      if V = '' then
        V := XmlAttr(OpenTag, 'fill');
      if (V <> '') and not SameText(V, 'auto') then
      begin
        Para.Fill := HexColor(V);
        Para.HasFill := True;
      end;
    end
    else if Name = 'outlineLvl' then
    begin
      V := XmlAttr(OpenTag, 'w:val');
      if V = '' then
        V := XmlAttr(OpenTag, 'val');
      Para.OutlineLvl := StrToIntDef(V, -1);
    end
    else if Name = 'rPr' then
      ApplyRPr(Inner, St)
    else if Name = 'pageBreakBefore' then
      Para.PageBreakBefore := True
    else if Name = 'numPr' then
    begin
      { filled later via ilvl/numId stored in NumText temporarily as id|lvl }
      V := '';
      var Q := 1;
      var N2, O2, I2: string;
      while XmlNextChild(Inner, Q, N2, O2, I2) do
      begin
        N2 := LocalName(N2);
        if N2 = 'numId' then
          V := XmlAttr(O2, 'w:val');
        if V = '' then
          V := XmlAttr(O2, 'val');
        if N2 = 'ilvl' then
        begin
          if XmlAttr(O2, 'w:val') <> '' then
            Para.NumText := XmlAttr(O2, 'w:val')
          else
            Para.NumText := XmlAttr(O2, 'val');
        end;
      end;
      if V <> '' then
        Para.NumText := V + '|' + Para.NumText;
    end;
  end;
end;

function ClonePara(Src: TDocPara): TDocPara;
begin
  Result := TDocPara.Create;
  if Src = nil then
    Exit;
  Result.Align := Src.Align;
  Result.SpaceBefore := Src.SpaceBefore;
  Result.SpaceAfter := Src.SpaceAfter;
  Result.LeftInd := Src.LeftInd;
  Result.RightInd := Src.RightInd;
  Result.FirstInd := Src.FirstInd;
  Result.LineMult := Src.LineMult;
  Result.Fill := Src.Fill;
  Result.HasFill := Src.HasFill;
  Result.OutlineLvl := Src.OutlineLvl;
  Result.PageBreakBefore := Src.PageBreakBefore;
end;

procedure AddTextInline(Para: TDocPara; const St: TDocRunStyle; const Txt: string);
var
  It: TDocInline;
begin
  if Txt = '' then
    Exit;
  It := TDocInline.Create;
  It.Kind := dikText;
  It.Style := St;
  It.Text := Txt;
  Para.Inlines.Add(It);
end;

procedure AddKindInline(Para: TDocPara; Kind: TDocInlineKind; const St: TDocRunStyle);
var
  It: TDocInline;
begin
  It := TDocInline.Create;
  It.Kind := Kind;
  It.Style := St;
  Para.Inlines.Add(It);
end;

{ ---------- layout ---------- }

type
  TAtom = record
    Kind: TDocInlineKind;
    Text: string;
    Style: TDocRunStyle;
    Image: TBitmap;
    W, H: Single;
  end;

procedure AddPaintText(Page: TDocLaidPage; X, Y, W, H: Single; const Txt: string;
  const St: TDocRunStyle);
var
  It: TDocPaintItem;
begin
  if (Txt = '') and not St.HasHighlight then
    Exit;
  It := TDocPaintItem.Create;
  It.Kind := dpkText;
  It.X := X;
  It.Y := Y;
  It.W := W;
  It.H := H;
  It.Text := Txt;
  It.Style := St;
  Page.Items.Add(It);
end;

procedure AddPaintImage(Page: TDocLaidPage; X, Y, W, H: Single; Bmp: TBitmap);
var
  It: TDocPaintItem;
begin
  if Bmp = nil then
    Exit;
  It := TDocPaintItem.Create;
  It.Kind := dpkImage;
  It.X := X;
  It.Y := Y;
  It.W := W;
  It.H := H;
  It.Bitmap := Bmp;
  Page.Items.Add(It);
end;

procedure AddPaintFill(Page: TDocLaidPage; X, Y, W, H: Single; C: TAlphaColor);
var
  It: TDocPaintItem;
begin
  It := TDocPaintItem.Create;
  It.Kind := dpkFill;
  It.X := X;
  It.Y := Y;
  It.W := W;
  It.H := H;
  It.Fill := C;
  Page.Items.Add(It);
end;

procedure AddPaintLine(Page: TDocLaidPage; X, Y, W, H: Single; C: TAlphaColor);
var
  It: TDocPaintItem;
begin
  It := TDocPaintItem.Create;
  It.Kind := dpkLine;
  It.X := X;
  It.Y := Y;
  It.W := W;
  It.H := H;
  It.Stroke := C;
  Page.Items.Add(It);
end;

function NewPage(Doc: TDocDocument): TDocLaidPage;
begin
  Result := TDocLaidPage.Create;
  Result.PaperW := Doc.PaperW;
  Result.PaperH := Doc.PaperH;
  Result.MarginL := Doc.MarginL;
  Result.MarginT := Doc.MarginT;
  Result.MarginR := Doc.MarginR;
  Result.MarginB := Doc.MarginB;
  Doc.Pages.Add(Result);
end;

procedure SplitTextAtoms(const Txt: string; const St: TDocRunStyle; var Atoms: TArray<TAtom>);
var
  I, Start: Integer;
  Piece: string;
  Sz: TSizeF;
  A: TAtom;
  Ch: Char;
begin
  I := 1;
  while I <= Length(Txt) do
  begin
    Start := I;
    Ch := Txt[I];
    if (Ch = ' ') or (Ch = #9) then
    begin
      while (I <= Length(Txt)) and ((Txt[I] = ' ') or (Txt[I] = #9)) do
        Inc(I);
    end
    else
    begin
      while (I <= Length(Txt)) and (Txt[I] <> ' ') and (Txt[I] <> #9) do
        Inc(I);
    end;
    Piece := Copy(Txt, Start, I - Start);
    Sz := MeasureRun(Piece, St);
    A := Default(TAtom);
    A.Kind := dikText;
    A.Text := Piece;
    A.Style := St;
    A.W := Sz.Width;
    A.H := Sz.Height;
    SetLength(Atoms, Length(Atoms) + 1);
    Atoms[High(Atoms)] := A;
  end;
end;

procedure LayoutParaOnPage(Doc: TDocDocument; var Page: TDocLaidPage; var CurY: Single;
  Para: TDocPara; Left, Width, Bottom: Single; Paginate: Boolean = True;
  AEmit: Boolean = True);
var
  Atoms: TArray<TAtom>;
  Line: TArray<TAtom>;
  LineW, LineH, Used, FirstW: Single;
  I, J, ExtraN: Integer;
  A: TAtom;
  Sz: TSizeF;
  First: Boolean;
  ContentL, ContentW, LineLeft: Single;

  procedure EnsurePage;
  begin
    if not Paginate then
      Exit;
    if (Page = nil) or (CurY > Bottom - 8) then
    begin
      if Doc.Pages.Count >= DocQVMaxPages then
      begin
        Doc.Truncated := True;
        Exit;
      end;
      Page := NewPage(Doc);
      CurY := Page.MarginT;
      Bottom := Page.PaperH - Page.MarginB;
    end;
  end;

  procedure FlushLine;
  var
    K: Integer;
    LX, Shift, SpCount, Add: Single;
  begin
    if Length(Line) = 0 then
      Exit;
    EnsurePage;
    if Page = nil then
      Exit;
    if Paginate and (CurY + LineH * Para.LineMult > Bottom) then
    begin
      Page := NewPage(Doc);
      CurY := Page.MarginT;
      Bottom := Page.PaperH - Page.MarginB;
    end;
    LineLeft := ContentL;
    if First then
      LineLeft := ContentL + Para.FirstInd;
    Shift := 0;
    if Para.Align = daCenter then
      Shift := Max(0, (ContentW - LineW) / 2)
    else if Para.Align = daRight then
      Shift := Max(0, ContentW - LineW);
    if AEmit and Para.HasFill then
      AddPaintFill(Page, ContentL, CurY, ContentW, LineH * Para.LineMult, Para.Fill);
    LX := LineLeft + Shift;
    SpCount := 0;
    if (Para.Align = daJustify) and (Length(Line) > 1) then
      for K := 0 to High(Line) do
        if (Line[K].Kind = dikText) and (Line[K].Text <> '') and (Line[K].Text[1] = ' ') then
          SpCount := SpCount + 1;
    Add := 0;
    if (SpCount > 0) and (ContentW > LineW) then
      Add := (ContentW - LineW) / SpCount;
    for K := 0 to High(Line) do
    begin
      if AEmit then
      begin
        if Line[K].Kind = dikImage then
          AddPaintImage(Page, LX, CurY, Line[K].W, Line[K].H, Line[K].Image)
        else if Line[K].Kind = dikText then
        begin
          if Line[K].Style.HasHighlight then
            AddPaintFill(Page, LX, CurY, Line[K].W, Line[K].H, Line[K].Style.Highlight);
          AddPaintText(Page, LX, CurY, Line[K].W, Line[K].H, Line[K].Text, Line[K].Style);
          if Line[K].Style.Underline or Line[K].Style.Strike then
            AddPaintLine(Page, LX, CurY + Line[K].H * IfThen(Line[K].Style.Strike, 0.55, 0.88),
              Line[K].W, 1, Line[K].Style.Color);
        end;
      end;
      LX := LX + Line[K].W;
      if (Para.Align = daJustify) and (Line[K].Kind = dikText) and (Line[K].Text <> '') and
         (Line[K].Text[1] = ' ') then
        LX := LX + Add;
    end;
    CurY := CurY + LineH * Para.LineMult;
    SetLength(Line, 0);
    LineW := 0;
    LineH := 0;
    First := False;
  end;

begin
  if Para = nil then
    Exit;
  if Paginate and Para.PageBreakBefore and (Page <> nil) and (CurY > Page.MarginT + 1) then
  begin
    Page := NewPage(Doc);
    CurY := Page.MarginT;
    Bottom := Page.PaperH - Page.MarginB;
  end;
  EnsurePage;
  if Page = nil then
    Exit;

  SetLength(Atoms, 0);
  if Para.NumText <> '' then
  begin
    A := Default(TAtom);
    A.Kind := dikText;
    A.Text := Para.NumText;
    if Para.Inlines.Count > 0 then
      A.Style := Para.Inlines[0].Style
    else
      A.Style.InitDefault;
    Sz := MeasureRun(A.Text, A.Style);
    A.W := Sz.Width;
    A.H := Sz.Height;
    SetLength(Atoms, 1);
    Atoms[0] := A;
  end;
  for I := 0 to Para.Inlines.Count - 1 do
  begin
    case Para.Inlines[I].Kind of
      dikText:
        SplitTextAtoms(Para.Inlines[I].Text, Para.Inlines[I].Style, Atoms);
      dikTab:
        begin
          A := Default(TAtom);
          A.Kind := dikTab;
          A.Style := Para.Inlines[I].Style;
          A.W := 48;
          A.H := PtPx(Para.Inlines[I].Style.SizePt) * 1.2;
          SetLength(Atoms, Length(Atoms) + 1);
          Atoms[High(Atoms)] := A;
        end;
      dikBreak, dikPageBreak:
        begin
          A := Default(TAtom);
          A.Kind := Para.Inlines[I].Kind;
          A.Style := Para.Inlines[I].Style;
          A.H := PtPx(Para.Inlines[I].Style.SizePt) * 1.2;
          SetLength(Atoms, Length(Atoms) + 1);
          Atoms[High(Atoms)] := A;
        end;
      dikImage:
        begin
          A := Default(TAtom);
          A.Kind := dikImage;
          A.Style := Para.Inlines[I].Style;
          A.Image := Para.Inlines[I].Image;
          A.W := Max(8, Para.Inlines[I].ImgW);
          A.H := Max(8, Para.Inlines[I].ImgH);
          if A.W > Width then
          begin
            A.H := A.H * (Width / A.W);
            A.W := Width;
          end;
          SetLength(Atoms, Length(Atoms) + 1);
          Atoms[High(Atoms)] := A;
        end;
    end;
  end;

  if Length(Atoms) = 0 then
  begin
    CurY := CurY + Para.SpaceBefore + PtPx(11) * Para.LineMult + Para.SpaceAfter;
    Exit;
  end;

  ContentL := Left + Para.LeftInd;
  ContentW := Max(40, Width - Para.LeftInd - Para.RightInd);
  CurY := CurY + Para.SpaceBefore;
  First := True;
  SetLength(Line, 0);
  LineW := 0;
  LineH := 0;

  I := 0;
  while I <= High(Atoms) do
  begin
    A := Atoms[I];
    if A.Kind = dikPageBreak then
    begin
      FlushLine;
      if Paginate then
      begin
        Page := NewPage(Doc);
        CurY := Page.MarginT;
        Bottom := Page.PaperH - Page.MarginB;
      end;
      Inc(I);
      Continue;
    end;
    if A.Kind = dikBreak then
    begin
      if Length(Line) = 0 then
      begin
        LineH := Max(LineH, A.H);
        SetLength(Line, 1);
        Line[0] := A;
        Line[0].Text := '';
        Line[0].W := 0;
      end;
      FlushLine;
      Inc(I);
      Continue;
    end;
    FirstW := 0;
    if First then
      FirstW := Para.FirstInd;
    Used := ContentW - FirstW;
    if A.Kind = dikTab then
    begin
      A.W := 48 - Frac((LineW) / 48) * 48;
      if A.W < 8 then
        A.W := 48;
    end;
    if (LineW + A.W > Used) and (Length(Line) > 0) and (A.Kind <> dikTab) then
      FlushLine;
    if (A.Kind = dikText) and (A.W > Used) and (Length(A.Text) > 1) then
    begin
      { split overlong token by chars }
      J := 1;
      while J <= Length(A.Text) do
      begin
        ExtraN := 1;
        Sz := MeasureRun(Copy(A.Text, J, ExtraN), A.Style);
        while (J + ExtraN - 1 < Length(A.Text)) and (LineW + Sz.Width <= Used) do
        begin
          Inc(ExtraN);
          Sz := MeasureRun(Copy(A.Text, J, ExtraN), A.Style);
        end;
        if ExtraN > 1 then
          Dec(ExtraN);
        A.Text := Copy(Atoms[I].Text, J, ExtraN);
        A.W := MeasureRun(A.Text, A.Style).Width;
        A.H := MeasureRun(A.Text, A.Style).Height;
        SetLength(Line, Length(Line) + 1);
        Line[High(Line)] := A;
        LineW := LineW + A.W;
        LineH := Max(LineH, A.H);
        Inc(J, ExtraN);
        if J <= Length(Atoms[I].Text) then
          FlushLine;
      end;
      Inc(I);
      Continue;
    end;
    SetLength(Line, Length(Line) + 1);
    Line[High(Line)] := A;
    LineW := LineW + A.W;
    LineH := Max(LineH, A.H);
    Inc(I);
  end;
  FlushLine;
  CurY := CurY + Para.SpaceAfter;
end;

procedure LayoutParas(Doc: TDocDocument; var Page: TDocLaidPage; var CurY: Single;
  Paras: TObjectList<TDocPara>; Left, Width, Bottom: Single; Paginate: Boolean = True;
  AEmit: Boolean = True);
var
  I: Integer;
begin
  for I := 0 to Paras.Count - 1 do
  begin
    if Paginate and (Doc.Pages.Count >= DocQVMaxPages) then
    begin
      Doc.Truncated := True;
      Exit;
    end;
    LayoutParaOnPage(Doc, Page, CurY, Paras[I], Left, Width, Bottom, Paginate, AEmit);
  end;
end;

procedure LayoutTable(Doc: TDocDocument; var Page: TDocLaidPage; var CurY: Single;
  Tbl: TDocTable; Left, Width, Bottom: Single);

  function CellSpan(Cell: TDocCell): Integer;
  begin
    if (Cell = nil) or (Cell.Span < 1) then
      Result := 1
    else
      Result := Cell.Span;
  end;

  function SpanWidth(AFrom, ASpan: Integer; const Cols: TArray<Single>): Single;
  var
    K: Integer;
  begin
    Result := 0;
    for K := 0 to ASpan - 1 do
      if AFrom + K <= High(Cols) then
        Result := Result + Cols[AFrom + K];
    if Result <= 0 then
      Result := 40;
  end;

  procedure StrokeCell(Page: TDocLaidPage; X, Y, W, H: Single; C: TAlphaColor);
  begin
    if (Page = nil) or (W <= 0) or (H <= 0) then
      Exit;
    AddPaintLine(Page, X, Y, W, 1, C);
    AddPaintLine(Page, X, Y + H - 1, W, 1, C);
    AddPaintLine(Page, X, Y, 1, H, C);
    AddPaintLine(Page, X + W - 1, Y, 1, H, C);
  end;

var
  R, C, N, ColIdx, Span: Integer;
  Row: TDocRow;
  Cell: TDocCell;
  Cols: TArray<Single>;
  Sum, Scale, X, CellH, SaveY, MaxH, CW, InnerH: Single;
  DummyPage: TDocLaidPage;
  I: Integer;
  Tmp: TDocLaidPage;
begin
  if (Tbl = nil) or (Tbl.Rows.Count = 0) then
    Exit;
  N := Length(Tbl.ColW);
  if N = 0 then
  begin
    N := 0;
    for R := 0 to Tbl.Rows.Count - 1 do
    begin
      ColIdx := 0;
      for C := 0 to Tbl.Rows[R].Cells.Count - 1 do
        ColIdx := ColIdx + CellSpan(Tbl.Rows[R].Cells[C]);
      N := Max(N, ColIdx);
    end;
    SetLength(Cols, Max(1, N));
    for C := 0 to High(Cols) do
      Cols[C] := Width / Length(Cols);
  end
  else
  begin
    SetLength(Cols, N);
    Sum := 0;
    for C := 0 to N - 1 do
    begin
      Cols[C] := Max(16, Tbl.ColW[C]);
      Sum := Sum + Cols[C];
    end;
    if Sum <= 0 then
      for C := 0 to N - 1 do
        Cols[C] := Width / N
    else
    begin
      Scale := Width / Sum;
      for C := 0 to N - 1 do
        Cols[C] := Cols[C] * Scale;
    end;
  end;

  for R := 0 to Tbl.Rows.Count - 1 do
  begin
    Row := Tbl.Rows[R];
    MaxH := 22;
    DummyPage := TDocLaidPage.Create;
    try
      DummyPage.PaperW := Doc.PaperW;
      DummyPage.PaperH := 20000;
      DummyPage.MarginL := 0;
      DummyPage.MarginT := 0;
      DummyPage.MarginR := 0;
      DummyPage.MarginB := 0;
      ColIdx := 0;
      for C := 0 to Row.Cells.Count - 1 do
      begin
        Cell := Row.Cells[C];
        Span := CellSpan(Cell);
        CW := SpanWidth(ColIdx, Span, Cols);
        SaveY := 4;
        Tmp := DummyPage;
        LayoutParas(Doc, Tmp, SaveY, Cell.Paras, 4, Max(16, CW - 8), 19900, False, False);
        MaxH := Max(MaxH, SaveY + 4);
        Inc(ColIdx, Span);
      end;
    finally
      for I := Doc.Pages.Count - 1 downto 0 do
        if Doc.Pages[I] = DummyPage then
          Doc.Pages.Extract(DummyPage);
      DummyPage.Free;
    end;

    InnerH := 0;
    if Page <> nil then
      InnerH := Page.PaperH - Page.MarginT - Page.MarginB;
    if (InnerH > 40) and (MaxH > InnerH) then
      MaxH := InnerH;

    if (Page <> nil) and (CurY + MaxH > Bottom) and (CurY > Page.MarginT + 1) then
    begin
      Page := NewPage(Doc);
      CurY := Page.MarginT;
      Bottom := Page.PaperH - Page.MarginB;
    end;
    if Page = nil then
    begin
      Page := NewPage(Doc);
      CurY := Page.MarginT;
      Bottom := Page.PaperH - Page.MarginB;
    end;

    X := Left;
    ColIdx := 0;
    for C := 0 to Row.Cells.Count - 1 do
    begin
      Cell := Row.Cells[C];
      Span := CellSpan(Cell);
      CW := SpanWidth(ColIdx, Span, Cols);
      if Cell.HasFill then
        AddPaintFill(Page, X, CurY, CW, MaxH, Cell.Fill)
      else
        AddPaintFill(Page, X, CurY, CW, MaxH, $FFFFFFFF);
      StrokeCell(Page, X, CurY, CW, MaxH, $FFB0B0B0);
      SaveY := CurY + 4;
      LayoutParas(Doc, Page, SaveY, Cell.Paras, X + 5, Max(16, CW - 10),
        CurY + MaxH - 2, False);
      X := X + CW;
      Inc(ColIdx, Span);
    end;
    CurY := CurY + MaxH;
  end;
end;

procedure LayoutHeaderFooter(Doc: TDocDocument; Page: TDocLaidPage; Paras: TObjectList<TDocPara>;
  Top: Boolean);
var
  Y, Bottom, Left, W: Single;
  Tmp: TDocLaidPage;
begin
  if (Paras = nil) or (Paras.Count = 0) or (Page = nil) then
    Exit;
  Left := Page.MarginL;
  W := Page.PaperW - Page.MarginL - Page.MarginR;
  if Top then
  begin
    Y := 16;
    Bottom := Page.MarginT - 8;
  end
  else
  begin
    Y := Page.PaperH - Page.MarginB + 8;
    Bottom := Page.PaperH - 12;
  end;
  if Bottom <= Y then
    Exit;
  Tmp := Page;
  LayoutParas(Doc, Tmp, Y, Paras, Left, W, Bottom, False);
end;

procedure TDocDocument.BuildLayout;
var
  Page: TDocLaidPage;
  CurY, Bottom, Left, W: Single;
  I, J: Integer;
begin
  Pages.Clear;
  if Blocks.Count = 0 then
  begin
    Page := NewPage(Self);
    Exit;
  end;
  Page := NewPage(Self);
  CurY := Page.MarginT;
  Bottom := Page.PaperH - Page.MarginB;
  Left := Page.MarginL;
  W := Page.PaperW - Page.MarginL - Page.MarginR;
  for I := 0 to Blocks.Count - 1 do
  begin
    if Pages.Count >= DocQVMaxPages then
    begin
      Truncated := True;
      Break;
    end;
    if Blocks[I].Kind = dbkPara then
      LayoutParaOnPage(Self, Page, CurY, Blocks[I].Para, Left, W, Bottom)
    else
      LayoutTable(Self, Page, CurY, Blocks[I].Table, Left, W, Bottom);
  end;
  for J := 0 to Pages.Count - 1 do
  begin
    LayoutHeaderFooter(Self, Pages[J], Header, True);
    LayoutHeaderFooter(Self, Pages[J], Footer, False);
  end;
end;

function TDocDocument.PlainText: string;
var
  B: TDocBlock;
  I, J, K, R, C: Integer;
  SL: TStringList;
  Para: TDocPara;
begin
  SL := TStringList.Create;
  try
    for I := 0 to Blocks.Count - 1 do
    begin
      B := Blocks[I];
      if B.Kind = dbkPara then
      begin
        Result := B.Para.NumText;
        for J := 0 to B.Para.Inlines.Count - 1 do
          if B.Para.Inlines[J].Kind = dikText then
            Result := Result + B.Para.Inlines[J].Text
          else if B.Para.Inlines[J].Kind in [dikBreak, dikPageBreak] then
            Result := Result + sLineBreak;
        SL.Add(Result);
      end
      else if Assigned(B.Table) then
        for R := 0 to B.Table.Rows.Count - 1 do
        begin
          Result := '';
          for C := 0 to B.Table.Rows[R].Cells.Count - 1 do
          begin
            if C > 0 then
              Result := Result + #9;
            for K := 0 to B.Table.Rows[R].Cells[C].Paras.Count - 1 do
            begin
              Para := B.Table.Rows[R].Cells[C].Paras[K];
              for J := 0 to Para.Inlines.Count - 1 do
                if Para.Inlines[J].Kind = dikText then
                  Result := Result + Para.Inlines[J].Text;
            end;
          end;
          SL.Add(Result);
        end;
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

function IsDocumentFile(const APath: string): Boolean;
var
  Ext, Name: string;
begin
  Name := ExtractFileName(APath);
  if (Length(Name) >= 2) and (Name[1] = '~') and (Name[2] = '$') then
    Exit(False);
  Ext := LowerCase(ExtractFileExt(APath));
  Result := MatchText(Ext, ['.docx', '.docm', '.dotx', '.dotm', '.odt', '.rtf']);
end;

function IsDocumentThumbExt(const APath: string): Boolean;
begin
  Result := IsDocumentFile(APath);
end;

{ ---------- DOCX ---------- }

procedure ParseRels(const Xml: string; Map: TDictionary<string, string>);
var
  P: Integer;
  Name, OpenTag, Inner, Id, Target: string;
begin
  P := 1;
  while XmlNextChild(Xml, P, Name, OpenTag, Inner) do
  begin
    if SameText(LocalName(Name), 'Relationship') then
    begin
      Id := XmlAttr(OpenTag, 'Id');
      if Id = '' then
        Id := XmlAttr(OpenTag, 'r:id');
      Target := XmlAttr(OpenTag, 'Target');
      if (Id <> '') and (Target <> '') then
        Map.AddOrSetValue(Id, Target);
    end
    else if Inner <> '' then
      ParseRels(Inner, Map);
  end;
end;

function RelToWordPath(const Target: string): string;
var
  T: string;
begin
  T := StringReplace(Target, '\', '/', [rfReplaceAll]);
  while (T <> '') and (T[1] = '/') do
    Delete(T, 1, 1);
  if StartsText('../', T) then
    Result := 'word/' + Copy(T, 4, MaxInt)
  else if StartsText('word/', T) then
    Result := T
  else
    Result := 'word/' + T;
end;

procedure ApplySectPr(const Frag: string; Doc: TDocDocument);
var
  P: Integer;
  Name, OpenTag, Inner, V: string;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    Name := LocalName(Name);
    if Name = 'pgSz' then
    begin
      V := XmlAttr(OpenTag, 'w:w');
      if V = '' then
        V := XmlAttr(OpenTag, 'w');
      if V <> '' then
        Doc.PaperW := Max(200, TwipPx(StrToFloatDef(V, 11906)));
      V := XmlAttr(OpenTag, 'w:h');
      if V = '' then
        V := XmlAttr(OpenTag, 'h');
      if V <> '' then
        Doc.PaperH := Max(200, TwipPx(StrToFloatDef(V, 16838)));
    end
    else if Name = 'pgMar' then
    begin
      V := XmlAttr(OpenTag, 'w:left');
      if V = '' then
        V := XmlAttr(OpenTag, 'left');
      if V <> '' then
        Doc.MarginL := Max(24, TwipPx(StrToFloatDef(V, 1440)));
      V := XmlAttr(OpenTag, 'w:right');
      if V = '' then
        V := XmlAttr(OpenTag, 'right');
      if V <> '' then
        Doc.MarginR := Max(24, TwipPx(StrToFloatDef(V, 1440)));
      V := XmlAttr(OpenTag, 'w:top');
      if V = '' then
        V := XmlAttr(OpenTag, 'top');
      if V <> '' then
        Doc.MarginT := Max(24, TwipPx(StrToFloatDef(V, 1440)));
      V := XmlAttr(OpenTag, 'w:bottom');
      if V = '' then
        V := XmlAttr(OpenTag, 'bottom');
      if V <> '' then
        Doc.MarginB := Max(24, TwipPx(StrToFloatDef(V, 1440)));
    end;
  end;
end;

procedure ParseRuns(const Frag: string; Para: TDocPara; Base: TDocRunStyle;
  Doc: TDocDocument; Imgs: TDictionary<string, TBitmap>; Zip: TZipFile;
  Rels: TDictionary<string, string>; Styles: TDictionary<string, TStylePack> = nil);
var
  P: Integer;
  Name, OpenTag, Inner, LN, Rid, Target: string;
  St: TDocRunStyle;
  Cx, Cy: Single;
  It: TDocInline;
  Bmp: TBitmap;
  Q: Integer;
  N2, O2, I2, Val: string;
  BrType: string;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    LN := LocalName(Name);
    if (LN = 'r') or (LN = 'ins') or (LN = 'hyperlink') or (LN = 'smartTag') or
       (LN = 'fldSimple') or (LN = 'sdt') then
    begin
      if LN = 'sdt' then
      begin
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'sdtContent' then
            ParseRuns(I2, Para, Base, Doc, Imgs, Zip, Rels, Styles);
      end
      else if LN = 'r' then
      begin
        St := Base;
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
        begin
          N2 := LocalName(N2);
          if N2 = 'rPr' then
          begin
            ApplyRPr(I2, St);
            if Assigned(Styles) then
            begin
              var RP := 1;
              var RN, RO, RI, RidS: string;
              var PackR: TStylePack;
              while XmlNextChild(I2, RP, RN, RO, RI) do
                if LocalName(RN) = 'rStyle' then
                begin
                  RidS := XmlAttr(RO, 'w:val');
                  if RidS = '' then
                    RidS := XmlAttr(RO, 'val');
                  if (RidS <> '') and Styles.TryGetValue(RidS, PackR) and PackR.HasRun then
                    MergeRun(St, PackR.Run, PackR.Run.FontName <> '');
                end;
            end;
          end
          else if N2 = 't' then
            AddTextInline(Para, St, XmlUnescape(I2))
          else if N2 = 'tab' then
            AddKindInline(Para, dikTab, St)
          else if (N2 = 'br') or (N2 = 'cr') then
          begin
            BrType := LowerCase(XmlAttr(O2, 'w:type'));
            if BrType = '' then
              BrType := LowerCase(XmlAttr(O2, 'type'));
            if BrType = 'page' then
              AddKindInline(Para, dikPageBreak, St)
            else
              AddKindInline(Para, dikBreak, St);
          end
          else if N2 = 'lastRenderedPageBreak' then
            AddKindInline(Para, dikPageBreak, St)
          else if (N2 = 'drawing') or (N2 = 'pict') then
          begin
            Rid := '';
            Cx := 0;
            Cy := 0;
            Val := I2 + O2;
            if Pos('r:embed="', Val) > 0 then
            begin
              Rid := XmlAttr(Copy(Val, Pos('r:embed="', Val), 80), 'r:embed');
              if Rid = '' then
                Rid := XmlAttr(Copy(Val, Pos('r:embed="', Val), 80), 'embed');
            end;
            if Rid = '' then
            begin
              if Pos('r:id="', Val) > 0 then
                Rid := XmlAttr(Copy(Val, Pos('r:id="', Val), 80), 'r:id');
            end;
            if Pos('cx="', Val) > 0 then
              Cx := EmuPx(StrToFloatDef(XmlAttr(Copy(Val, Pos('cx="', Val), 60), 'cx'), 0));
            if Pos('cy="', Val) > 0 then
              Cy := EmuPx(StrToFloatDef(XmlAttr(Copy(Val, Pos('cy="', Val), 60), 'cy'), 0));
            Bmp := nil;
            if (Rid <> '') and Assigned(Imgs) then
              Imgs.TryGetValue(Rid, Bmp);
            if (Bmp = nil) and (Rid <> '') and Assigned(Rels) and Assigned(Zip) then
            begin
              if Rels.TryGetValue(Rid, Target) then
              begin
                Bmp := LoadBmp(ZipReadBytes(Zip, RelToWordPath(Target)));
                if Assigned(Bmp) then
                begin
                  Doc.Images.Add(Bmp);
                  if Assigned(Imgs) then
                    Imgs.AddOrSetValue(Rid, Bmp);
                end;
              end;
            end;
            if Assigned(Bmp) then
            begin
              if Cx < 8 then
                Cx := Bmp.Width;
              if Cy < 8 then
                Cy := Bmp.Height;
              It := TDocInline.Create;
              It.Kind := dikImage;
              It.Style := St;
              It.Image := Bmp;
              It.ImgW := Cx;
              It.ImgH := Cy;
              Para.Inlines.Add(It);
            end;
          end
          else if N2 = 'instrText' then
            { skip field codes }
          else if N2 = 'delText' then
            { skip deleted }
          ;
        end;
      end
      else
        ParseRuns(Inner, Para, Base, Doc, Imgs, Zip, Rels, Styles);
    end
    else if LN = 'del' then
      { skip }
    else if LN = 'bookmarkStart' then
    else if LN = 'bookmarkEnd' then
    else if LN = 'proofErr' then
    else
      ParseRuns(Inner, Para, Base, Doc, Imgs, Zip, Rels, Styles);
  end;
end;

procedure ParsePInto(const Inner: string; Dest: TObjectList<TDocPara>;
  Doc: TDocDocument; DefaultRun: TDocRunStyle; Styles: TDictionary<string, TStylePack>;
  Imgs: TDictionary<string, TBitmap>; Zip: TZipFile; Rels: TDictionary<string, string>;
  NumMap: TDictionary<string, string>); forward;
procedure ApplyResolvedStyle(const StyleId: string; Styles: TDictionary<string, TStylePack>;
  Para: TDocPara; var St: TDocRunStyle); forward;

procedure ParseTable(const Frag: string; Tbl: TDocTable; Doc: TDocDocument;
  DefaultRun: TDocRunStyle; Styles: TDictionary<string, TStylePack>;
  Imgs: TDictionary<string, TBitmap>; Zip: TZipFile; Rels: TDictionary<string, string>;
  NumMap: TDictionary<string, string>);
var
  P, Q, K: Integer;
  Name, OpenTag, Inner, N2, O2, I2, N3, O3, I3, V: string;
  Row: TDocRow;
  Cell: TDocCell;
  Cols: TList<Single>;
begin
  Cols := TList<Single>.Create;
  try
    P := 1;
    while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
    begin
      Name := LocalName(Name);
      if Name = 'tblGrid' then
      begin
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'gridCol' then
          begin
            V := XmlAttr(O2, 'w:w');
            if V = '' then
              V := XmlAttr(O2, 'w');
            Cols.Add(TwipPx(StrToFloatDef(V, 1440)));
          end;
      end
      else if Name = 'tr' then
      begin
        Row := TDocRow.Create;
        Tbl.Rows.Add(Row);
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
        begin
          if LocalName(N2) <> 'tc' then
            Continue;
          Cell := TDocCell.Create;
          Row.Cells.Add(Cell);
          K := 1;
          while XmlNextChild(I2, K, N3, O3, I3) do
          begin
            N3 := LocalName(N3);
            if N3 = 'tcPr' then
            begin
              var T := 1;
              var A, B, C: string;
              while XmlNextChild(I3, T, A, B, C) do
              begin
                A := LocalName(A);
                if A = 'gridSpan' then
                  Cell.Span := Max(1, StrToIntDef(XmlAttr(B, 'w:val'), 1))
                else if A = 'shd' then
                begin
                  V := XmlAttr(B, 'w:fill');
                  if V = '' then
                    V := XmlAttr(B, 'fill');
                  if (V <> '') and not SameText(V, 'auto') then
                  begin
                    Cell.Fill := HexColor(V);
                    Cell.HasFill := True;
                  end;
                end
                else if A = 'tcW' then
                begin
                  V := XmlAttr(B, 'w:w');
                  if V = '' then
                    V := XmlAttr(B, 'w');
                  if V <> '' then
                    Cell.Width := TwipPx(StrToFloatDef(V, 0));
                end;
              end;
            end
            else if N3 = 'p' then
              ParsePInto(I3, Cell.Paras, Doc, DefaultRun, Styles, Imgs, Zip, Rels, NumMap)
            else if N3 = 'tbl' then
              ParsePInto(I3, Cell.Paras, Doc, DefaultRun, Styles, Imgs, Zip, Rels, NumMap);
          end;
        end;
      end;
    end;
    SetLength(Tbl.ColW, Cols.Count);
    for K := 0 to Cols.Count - 1 do
      Tbl.ColW[K] := Cols[K];
  finally
    Cols.Free;
  end;
end;

procedure ResolveNum(Para: TDocPara; NumMap: TDictionary<string, string>;
  Counters: TDictionary<Integer, TArray<Integer>>);
var
  IdS, LvlS, Fmt, LvlPack, Font: string;
  P, Id, Lvl, I: Integer;
  Arr: TArray<Integer>;
  S: string;
  Parts: TArray<string>;
  Sz, LeftInd, Hang: Single;
  Bold, Italic: Boolean;
  J: Integer;
  LvlRun: TDocRunStyle;
begin
  if (Para.NumText = '') or (Pos('|', Para.NumText) = 0) then
    Exit;
  P := Pos('|', Para.NumText);
  IdS := Copy(Para.NumText, 1, P - 1);
  LvlS := Copy(Para.NumText, P + 1, MaxInt);
  Id := StrToIntDef(IdS, 0);
  Lvl := StrToIntDef(LvlS, 0);
  Para.NumText := '';
  LvlPack := '';
  if Assigned(NumMap) then
  begin
    NumMap.TryGetValue(IdS + ':' + IntToStr(Lvl), LvlPack);
    if LvlPack = '' then
      NumMap.TryGetValue(IdS, LvlPack);
  end;
  Fmt := LvlPack;
  Sz := 0;
  Bold := False;
  Italic := False;
  Font := '';
  LeftInd := 0;
  Hang := 0;
  if Pos('#', LvlPack) > 0 then
  begin
    Parts := LvlPack.Split(['#']);
    if Length(Parts) > 0 then
      Fmt := Parts[0];
    if Length(Parts) > 1 then
      Sz := StrToFloatDef(Parts[1], 0);
    if Length(Parts) > 2 then
      Bold := Parts[2] = '1';
    if Length(Parts) > 3 then
      Italic := Parts[3] = '1';
    if Length(Parts) > 4 then
      Font := Parts[4];
    if Length(Parts) > 5 then
      LeftInd := StrToFloatDef(Parts[5], 0);
    if Length(Parts) > 6 then
      Hang := StrToFloatDef(Parts[6], 0);
  end;
  if not Counters.TryGetValue(Id, Arr) then
  begin
    SetLength(Arr, 9);
    for I := 0 to High(Arr) do
      Arr[I] := 0;
  end;
  if Lvl > High(Arr) then
    Lvl := High(Arr);
  Inc(Arr[Lvl]);
  for I := Lvl + 1 to High(Arr) do
    Arr[I] := 0;
  Counters.AddOrSetValue(Id, Arr);
  if (Fmt = 'bullet') or (Fmt = 'none') then
    Para.NumText := '○ '
  else
  begin
    S := '';
    for I := 0 to Lvl do
    begin
      if I > 0 then
        S := S + '.';
      S := S + IntToStr(Max(1, Arr[I]));
    end;
    Para.NumText := S + '. ';
  end;
  if (LeftInd > 0) and (Para.LeftInd < 1) then
    Para.LeftInd := Min(LeftInd, 96);
  if (Hang > 0) and (Abs(Para.FirstInd) < 1) then
    Para.FirstInd := -Min(Hang, 48);
end;

procedure ParsePInto(const Inner: string; Dest: TObjectList<TDocPara>;
  Doc: TDocDocument; DefaultRun: TDocRunStyle; Styles: TDictionary<string, TStylePack>;
  Imgs: TDictionary<string, TBitmap>; Zip: TZipFile; Rels: TDictionary<string, string>;
  NumMap: TDictionary<string, string>);
var
  Q: Integer;
  N2, O2, I2, StyleId: string;
  Para: TDocPara;
  St: TDocRunStyle;
  Pack: TStylePack;
  Counters: TDictionary<Integer, TArray<Integer>>;
begin
  if Dest = nil then
    Exit;
  St := DefaultRun;
  Para := TDocPara.Create;
  StyleId := '';
  Q := 1;
  while XmlNextChild(Inner, Q, N2, O2, I2) do
    if LocalName(N2) = 'pPr' then
    begin
      var T := 1;
      var A, B, C: string;
      while XmlNextChild(I2, T, A, B, C) do
        if LocalName(A) = 'pStyle' then
        begin
          StyleId := XmlAttr(B, 'w:val');
          if StyleId = '' then
            StyleId := XmlAttr(B, 'val');
        end;
      ApplyResolvedStyle(StyleId, Styles, Para, St);
      ApplyPPr(I2, Para, St);
    end;
  ParseRuns(Inner, Para, St, Doc, Imgs, Zip, Rels, Styles);
  Counters := TDictionary<Integer, TArray<Integer>>.Create;
  try
    ResolveNum(Para, NumMap, Counters);
  finally
    Counters.Free;
  end;
  Dest.Add(Para);
end;

procedure ParseBodyAsBlocks(const Frag: string; Doc: TDocDocument; DefaultRun: TDocRunStyle;
  Styles: TDictionary<string, TStylePack>; Imgs: TDictionary<string, TBitmap>;
  Zip: TZipFile; Rels: TDictionary<string, string>; NumMap: TDictionary<string, string>);
var
  P, Q: Integer;
  Name, OpenTag, Inner, LN, N2, O2, I2, StyleId: string;
  Para: TDocPara;
  St: TDocRunStyle;
  Pack: TStylePack;
  Blk: TDocBlock;
  Counters: TDictionary<Integer, TArray<Integer>>;
begin
  Counters := TDictionary<Integer, TArray<Integer>>.Create;
  try
    P := 1;
    while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
    begin
      if Doc.Blocks.Count >= DocQVMaxBlocks then
      begin
        Doc.Truncated := True;
        Exit;
      end;
      LN := LocalName(Name);
      if (LN = 'document') or (LN = 'body') then
      begin
        ParseBodyAsBlocks(Inner, Doc, DefaultRun, Styles, Imgs, Zip, Rels, NumMap);
        Continue;
      end;
      if LN = 'p' then
      begin
        St := DefaultRun;
        Para := TDocPara.Create;
        StyleId := '';
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'pPr' then
          begin
            var T := 1;
            var A, B, C: string;
            while XmlNextChild(I2, T, A, B, C) do
              if LocalName(A) = 'pStyle' then
              begin
                StyleId := XmlAttr(B, 'w:val');
                if StyleId = '' then
                  StyleId := XmlAttr(B, 'val');
              end;
            ApplyResolvedStyle(StyleId, Styles, Para, St);
            ApplyPPr(I2, Para, St);
          end;
        ParseRuns(Inner, Para, St, Doc, Imgs, Zip, Rels, Styles);
        ResolveNum(Para, NumMap, Counters);
        Blk := TDocBlock.Create;
        Blk.Kind := dbkPara;
        Blk.Para := Para;
        Doc.Blocks.Add(Blk);
      end
      else if LN = 'tbl' then
      begin
        Blk := TDocBlock.Create;
        Blk.Kind := dbkTable;
        Blk.Table := TDocTable.Create;
        ParseTable(Inner, Blk.Table, Doc, DefaultRun, Styles, Imgs, Zip, Rels, NumMap);
        Doc.Blocks.Add(Blk);
      end
      else if LN = 'sectPr' then
        ApplySectPr(Inner + OpenTag, Doc)
      else if LN = 'sdt' then
      begin
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'sdtContent' then
            ParseBodyAsBlocks(I2, Doc, DefaultRun, Styles, Imgs, Zip, Rels, NumMap);
      end;
    end;
  finally
    Counters.Free;
  end;
end;

procedure ParseHeaderParas(const Frag: string; Dest: TObjectList<TDocPara>;
  Doc: TDocDocument; DefaultRun: TDocRunStyle; Styles: TDictionary<string, TStylePack>;
  Imgs: TDictionary<string, TBitmap>; Zip: TZipFile; Rels: TDictionary<string, string>);
var
  P, Q: Integer;
  Name, OpenTag, Inner, LN, N2, O2, I2, StyleId: string;
  Para: TDocPara;
  St: TDocRunStyle;
  Pack: TStylePack;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    LN := LocalName(Name);
    if (LN = 'hdr') or (LN = 'ftr') then
    begin
      ParseHeaderParas(Inner, Dest, Doc, DefaultRun, Styles, Imgs, Zip, Rels);
      Continue;
    end;
    if LN <> 'p' then
      Continue;
    St := DefaultRun;
    Para := TDocPara.Create;
    StyleId := '';
    Q := 1;
    while XmlNextChild(Inner, Q, N2, O2, I2) do
      if LocalName(N2) = 'pPr' then
      begin
        var T := 1;
        var A, B, C: string;
        while XmlNextChild(I2, T, A, B, C) do
          if LocalName(A) = 'pStyle' then
          begin
            StyleId := XmlAttr(B, 'w:val');
            if StyleId = '' then
              StyleId := XmlAttr(B, 'val');
          end;
        ApplyResolvedStyle(StyleId, Styles, Para, St);
        ApplyPPr(I2, Para, St);
      end;
    ParseRuns(Inner, Para, St, Doc, Imgs, Zip, Rels, Styles);
    Dest.Add(Para);
  end;
end;

procedure ParseStylesXml(const Xml: string; Styles: TDictionary<string, TStylePack>;
  var DefaultRun: TDocRunStyle);
var
  P, Q: Integer;
  Name, OpenTag, Inner, LN, N2, O2, I2, Id: string;
  Pack: TStylePack;
begin
  P := 1;
  while XmlNextChild(Xml, P, Name, OpenTag, Inner) do
  begin
    LN := LocalName(Name);
    if LN = 'styles' then
    begin
      ParseStylesXml(Inner, Styles, DefaultRun);
      Continue;
    end;
    if LN = 'docDefaults' then
    begin
      Q := 1;
      while XmlNextChild(Inner, Q, N2, O2, I2) do
        if LocalName(N2) = 'rPrDefault' then
        begin
          var T := 1;
          var A, B, C: string;
          while XmlNextChild(I2, T, A, B, C) do
            if LocalName(A) = 'rPr' then
              ApplyRPr(C, DefaultRun);
        end;
    end
    else if LN = 'style' then
    begin
      Id := XmlAttr(OpenTag, 'w:styleId');
      if Id = '' then
        Id := XmlAttr(OpenTag, 'styleId');
      if Id = '' then
        Continue;
      Pack := Default(TStylePack);
      Pack.Id := Id;
      Pack.Run.InitDefault;
      Pack.Para := TDocPara.Create;
      Q := 1;
      while XmlNextChild(Inner, Q, N2, O2, I2) do
      begin
        N2 := LocalName(N2);
        if N2 = 'basedOn' then
        begin
          Pack.BasedOn := XmlAttr(O2, 'w:val');
          if Pack.BasedOn = '' then
            Pack.BasedOn := XmlAttr(O2, 'val');
        end
        else if N2 = 'pPr' then
        begin
          ApplyPPr(I2, Pack.Para, Pack.Run);
          Pack.HasPara := True;
        end
        else if N2 = 'rPr' then
        begin
          Pack.Run.InitDefault;
          Pack.Run.SizePt := 0;
          Pack.Run.FontName := '';
          ApplyRPr(I2, Pack.Run);
          Pack.HasRun := True;
        end;
      end;
      Styles.AddOrSetValue(Id, Pack);
    end;
  end;
end;

procedure ResolveStyles(Styles: TDictionary<string, TStylePack>);
var
  Guard: TDictionary<string, Boolean>;

  procedure ResolveOne(const Id: string);
  var
    Pack, Base: TStylePack;
    Run: TDocRunStyle;
  begin
    if (Styles = nil) or (Id = '') or Guard.ContainsKey(Id) then
      Exit;
    if not Styles.TryGetValue(Id, Pack) then
      Exit;
    if Pack.Resolved then
      Exit;
    Guard.Add(Id, True);
    if Pack.BasedOn <> '' then
    begin
      ResolveOne(Pack.BasedOn);
      if Styles.TryGetValue(Pack.BasedOn, Base) then
      begin
        if Base.HasRun then
        begin
          Run := Base.Run;
          MergeRun(Run, Pack.Run, Pack.Run.FontName <> '');
          if Pack.Run.SizePt > 0 then
            Run.SizePt := Pack.Run.SizePt;
          if Pack.Run.FontName <> '' then
            Run.FontName := Pack.Run.FontName;
          Pack.Run := Run;
          Pack.HasRun := True;
        end;
        if Base.HasPara and not Pack.HasPara then
        begin
          Pack.Para.Align := Base.Para.Align;
          Pack.Para.SpaceBefore := Base.Para.SpaceBefore;
          Pack.Para.SpaceAfter := Base.Para.SpaceAfter;
          Pack.Para.LeftInd := Base.Para.LeftInd;
          Pack.Para.RightInd := Base.Para.RightInd;
          Pack.Para.FirstInd := Base.Para.FirstInd;
          Pack.Para.LineMult := Base.Para.LineMult;
          Pack.Para.OutlineLvl := Base.Para.OutlineLvl;
          Pack.HasPara := True;
        end;
      end;
    end;
    Pack.Resolved := True;
    Styles.AddOrSetValue(Id, Pack);
  end;

var
  Id: string;
begin
  if Styles = nil then
    Exit;
  Guard := TDictionary<string, Boolean>.Create;
  try
    for Id in Styles.Keys do
      ResolveOne(Id);
  finally
    Guard.Free;
  end;
end;

procedure ApplyResolvedStyle(const StyleId: string; Styles: TDictionary<string, TStylePack>;
  Para: TDocPara; var St: TDocRunStyle);
var
  Pack: TStylePack;
begin
  if (StyleId = '') or (Styles = nil) or not Styles.TryGetValue(StyleId, Pack) then
    Exit;
  if Pack.HasPara then
  begin
    Para.Align := Pack.Para.Align;
    Para.SpaceBefore := Pack.Para.SpaceBefore;
    Para.SpaceAfter := Pack.Para.SpaceAfter;
    Para.LeftInd := Pack.Para.LeftInd;
    Para.RightInd := Pack.Para.RightInd;
    Para.FirstInd := Pack.Para.FirstInd;
    Para.LineMult := Pack.Para.LineMult;
    Para.OutlineLvl := Pack.Para.OutlineLvl;
    Para.Fill := Pack.Para.Fill;
    Para.HasFill := Pack.Para.HasFill;
  end;
  if Pack.HasRun then
    MergeRun(St, Pack.Run, Pack.Run.FontName <> '');
end;

procedure ParseNumbering(const Xml: string; NumMap: TDictionary<string, string>);
var
  P, Q, K: Integer;
  Name, OpenTag, Inner, N2, O2, I2, N3, O3, I3: string;
  AbsId, NumId, Fmt, Lvl, LvlPack, V: string;
  AbsFmt: TDictionary<string, string>;
  LvlRun: TDocRunStyle;
  LeftInd, Hang: Single;
begin
  AbsFmt := TDictionary<string, string>.Create;
  try
    P := 1;
    while XmlNextChild(Xml, P, Name, OpenTag, Inner) do
    begin
      if LocalName(Name) = 'numbering' then
      begin
        ParseNumbering(Inner, NumMap);
        Continue;
      end;
      if LocalName(Name) = 'abstractNum' then
      begin
        AbsId := XmlAttr(OpenTag, 'w:abstractNumId');
        if AbsId = '' then
          AbsId := XmlAttr(OpenTag, 'abstractNumId');
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'lvl' then
          begin
            Lvl := XmlAttr(O2, 'w:ilvl');
            if Lvl = '' then
              Lvl := XmlAttr(O2, 'ilvl');
            Fmt := 'decimal';
            LvlRun.InitDefault;
            LvlRun.SizePt := 0;
            LvlRun.FontName := '';
            LeftInd := 0;
            Hang := 0;
            K := 1;
            while XmlNextChild(I2, K, N3, O3, I3) do
            begin
              if LocalName(N3) = 'numFmt' then
              begin
                Fmt := LowerCase(XmlAttr(O3, 'w:val'));
                if Fmt = '' then
                  Fmt := LowerCase(XmlAttr(O3, 'val'));
              end
              else if LocalName(N3) = 'rPr' then
                ApplyRPr(I3, LvlRun)
              else if LocalName(N3) = 'pPr' then
              begin
                var T := 1;
                var A, B, C: string;
                while XmlNextChild(I3, T, A, B, C) do
                  if LocalName(A) = 'ind' then
                  begin
                    V := XmlAttr(B, 'w:left');
                    if V = '' then
                      V := XmlAttr(B, 'left');
                    if V <> '' then
                      LeftInd := TwipPx(StrToFloatDef(V, 0));
                    V := XmlAttr(B, 'w:hanging');
                    if V = '' then
                      V := XmlAttr(B, 'hanging');
                    if V <> '' then
                      Hang := TwipPx(StrToFloatDef(V, 0));
                  end;
              end;
            end;
            LvlPack := Fmt + '#' + FloatToStr(LvlRun.SizePt) + '#' +
              IntToStr(Ord(LvlRun.Bold)) + '#' + IntToStr(Ord(LvlRun.Italic)) + '#' +
              LvlRun.FontName + '#' + FloatToStr(LeftInd) + '#' + FloatToStr(Hang);
            AbsFmt.AddOrSetValue(AbsId + ':' + Lvl, LvlPack);
          end;
      end
      else if LocalName(Name) = 'num' then
      begin
        NumId := XmlAttr(OpenTag, 'w:numId');
        if NumId = '' then
          NumId := XmlAttr(OpenTag, 'numId');
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'abstractNumId' then
          begin
            AbsId := XmlAttr(O2, 'w:val');
            if AbsId = '' then
              AbsId := XmlAttr(O2, 'val');
            for Lvl in AbsFmt.Keys do
              if StartsText(AbsId + ':', Lvl) then
                NumMap.AddOrSetValue(NumId + ':' + Copy(Lvl, Length(AbsId) + 2, MaxInt),
                  AbsFmt[Lvl]);
          end;
      end;
    end;
  finally
    AbsFmt.Free;
  end;
end;

procedure FallbackWordTexts(const Xml: string; Doc: TDocDocument; const Base: TDocRunStyle);
var
  P, Gt, CloseP: Integer;
  Chunk: string;
  Para: TDocPara;
  Blk: TDocBlock;
begin
  if (Doc = nil) or (Xml = '') then
    Exit;
  P := 1;
  Para := TDocPara.Create;
  Para.LineMult := 1.2;
  while P <= Length(Xml) do
  begin
    P := Pos('<w:t', Xml, P);
    if P = 0 then
      Break;
    if (P + 4 <= Length(Xml)) and
       (Xml[P + 4] <> '>') and (Xml[P + 4] <> ' ') and (Xml[P + 4] <> '/') then
    begin
      Inc(P, 4);
      Continue;
    end;
    Gt := Pos('>', Xml, P);
    if Gt = 0 then
      Break;
    if Xml[Gt - 1] = '/' then
    begin
      P := Gt + 1;
      Continue;
    end;
    CloseP := Pos('</w:t>', Xml, Gt + 1);
    if CloseP = 0 then
      Break;
    Chunk := XmlUnescape(Copy(Xml, Gt + 1, CloseP - Gt - 1));
    if Chunk <> '' then
    begin
      if Para.Inlines.Count > 40 then
      begin
        Blk := TDocBlock.Create;
        Blk.Kind := dbkPara;
        Blk.Para := Para;
        Doc.Blocks.Add(Blk);
        Para := TDocPara.Create;
        Para.LineMult := 1.2;
      end;
      AddTextInline(Para, Base, Chunk);
    end;
    P := CloseP + 6;
  end;
  if Para.Inlines.Count > 0 then
  begin
    Blk := TDocBlock.Create;
    Blk.Kind := dbkPara;
    Blk.Para := Para;
    Doc.Blocks.Add(Blk);
  end
  else
    Para.Free;
end;

function LoadDocx(const APath: string; out AError: string): TDocDocument;
var
  Zip: TZipFile;
  Stream: TFileStream;
  DocXml, StylesXml, RelXml, NumXml, Body: string;
  Styles: TDictionary<string, TStylePack>;
  Rels, NumMap, ImgRel: TDictionary<string, string>;
  Imgs: TDictionary<string, TBitmap>;
  DefaultRun: TDocRunStyle;
  P: Integer;
  Name, OpenTag, Inner, Id, Target, Typ: string;
  Bmp: TBitmap;
  Pair: TPair<string, TStylePack>;
  HTarget: string;
begin
  Result := nil;
  AError := '';
  Stream := nil;
  Zip := nil;
  Styles := TDictionary<string, TStylePack>.Create;
  Rels := TDictionary<string, string>.Create;
  NumMap := TDictionary<string, string>.Create;
  Imgs := TDictionary<string, TBitmap>.Create;
  try
    try
      Zip := ZipOpenShared(APath, Stream);
    except
      on E: Exception do
      begin
        AError := E.Message;
        Exit;
      end;
    end;
    DocXml := ZipReadUtf8(Zip, 'word/document.xml');
    if DocXml = '' then
    begin
      AError := 'Нет word/document.xml';
      Exit;
    end;
    StylesXml := ZipReadUtf8(Zip, 'word/styles.xml');
    RelXml := ZipReadUtf8(Zip, 'word/_rels/document.xml.rels');
    NumXml := ZipReadUtf8(Zip, 'word/numbering.xml');
    DefaultRun.InitDefault;
    ParseStylesXml(StylesXml, Styles, DefaultRun);
    ResolveStyles(Styles);
    ParseRels(RelXml, Rels);
    ParseNumbering(NumXml, NumMap);
    for Id in Rels.Keys do
    begin
      Target := Rels[Id];
      if not ContainsText(LowerCase(Target), 'media/') then
        Continue;
      Bmp := LoadBmp(ZipReadBytes(Zip, RelToWordPath(Target)));
      if Assigned(Bmp) then
        Imgs.AddOrSetValue(Id, Bmp);
    end;

    Result := TDocDocument.Create;
    Result.FilePath := APath;
    for Bmp in Imgs.Values do
      if Result.Images.IndexOf(Bmp) < 0 then
        Result.Images.Add(Bmp);

    Body := XmlFindLocalInner(DocXml, 'body');
    if Body = '' then
      Body := DocXml;
    ParseBodyAsBlocks(Body, Result, DefaultRun, Styles, Imgs, Zip, Rels, NumMap);
    if Result.Blocks.Count = 0 then
      ParseBodyAsBlocks(DocXml, Result, DefaultRun, Styles, Imgs, Zip, Rels, NumMap);
    if Result.Blocks.Count = 0 then
      FallbackWordTexts(DocXml, Result, DefaultRun);

    HTarget := '';
    for Pair in Styles do
      ;
    for Target in Rels.Values do
      ;
    for Id in Rels.Keys do
    begin
      Typ := '';
      { header/footer by target name }
      Rels.TryGetValue(Id, Target);
      if ContainsText(LowerCase(Target), 'header') and (Result.Header.Count = 0) then
        HTarget := Target;
      if ContainsText(LowerCase(Target), 'footer') and (Result.Footer.Count = 0) then
        if HTarget <> Target then
          ParseHeaderParas(ZipReadUtf8(Zip, RelToWordPath(Target)), Result.Footer, Result,
            DefaultRun, Styles, Imgs, Zip, Rels);
    end;
    if HTarget <> '' then
      ParseHeaderParas(ZipReadUtf8(Zip, RelToWordPath(HTarget)), Result.Header, Result,
        DefaultRun, Styles, Imgs, Zip, Rels);
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      AError := E.Message;
    end;
  end;
  { Styles packs own TDocPara }
  for Pair in Styles do
    Pair.Value.Para.Free;
  Styles.Free;
  Rels.Free;
  NumMap.Free;
  Imgs.Free; { bitmaps owned by Result.Images }
  if Assigned(Zip) then
  begin
    Zip.Close;
    Zip.Free;
  end;
  Stream.Free;
end;

{ ---------- ODT ---------- }

procedure ApplyOdtStyle(const Frag: string; Para: TDocPara; var St: TDocRunStyle);
var
  P: Integer;
  Name, OpenTag, Inner, V: string;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    if (LocalName(Name) = 'paragraph-properties') or (LocalName(Name) = 'text-properties') then
    begin
      V := LowerCase(XmlAttr(OpenTag, 'fo:text-align'));
      if V = 'center' then
        Para.Align := daCenter
      else if V = 'end' then
        Para.Align := daRight
      else if V = 'justify' then
        Para.Align := daJustify;
      V := XmlAttr(OpenTag, 'fo:font-size');
      if V = '' then
        V := XmlAttr(OpenTag, 'fo:font-size-complex');
      if EndsText('pt', V) then
        St.SizePt := StrToFloatDef(Copy(V, 1, Length(V) - 2), St.SizePt);
      V := XmlAttr(OpenTag, 'fo:font-weight');
      if (V = 'bold') or (V = '700') then
        St.Bold := True;
      V := XmlAttr(OpenTag, 'fo:font-style');
      if V = 'italic' then
        St.Italic := True;
      V := XmlAttr(OpenTag, 'style:text-underline-style');
      if (V <> '') and (V <> 'none') then
        St.Underline := True;
      V := XmlAttr(OpenTag, 'fo:color');
      if (V <> '') and (V[1] = '#') then
      begin
        St.Color := HexColor(Copy(V, 2, 6));
        St.HasColor := True;
      end;
      V := XmlAttr(OpenTag, 'fo:background-color');
      if (V <> '') and (V[1] = '#') then
      begin
        Para.Fill := HexColor(Copy(V, 2, 6));
        Para.HasFill := True;
      end;
      V := XmlAttr(OpenTag, 'fo:margin-left');
      if EndsText('cm', V) then
        Para.LeftInd := StrToFloatDef(Copy(V, 1, Length(V) - 2), 0) * 37.8;
      V := XmlAttr(OpenTag, 'fo:margin-top');
      if EndsText('cm', V) then
        Para.SpaceBefore := StrToFloatDef(Copy(V, 1, Length(V) - 2), 0) * 37.8;
      V := XmlAttr(OpenTag, 'fo:margin-bottom');
      if EndsText('cm', V) then
        Para.SpaceAfter := StrToFloatDef(Copy(V, 1, Length(V) - 2), 0) * 37.8;
      V := XmlAttr(OpenTag, 'style:font-name');
      if V <> '' then
        St.FontName := V;
      ApplyOdtStyle(Inner, Para, St);
    end
    else
      ApplyOdtStyle(Inner, Para, St);
  end;
end;

procedure ParseOdtText(const Frag: string; Para: TDocPara; St: TDocRunStyle;
  Styles: TDictionary<string, TStylePack>; Doc: TDocDocument; Zip: TZipFile);
var
  P, Q: Integer;
  Name, OpenTag, Inner, LN, Href, W, H: string;
  Pack: TStylePack;
  Bmp: TBitmap;
  It: TDocInline;
  Cnt: Integer;
  Ns: TDocRunStyle;
begin
  P := 1;
  while XmlNextChild(Frag, P, Name, OpenTag, Inner) do
  begin
    LN := LocalName(Name);
    Ns := St;
    if (LN = 'span') or (LN = 'a') then
    begin
      if Styles.TryGetValue(XmlAttr(OpenTag, 'text:style-name'), Pack) and Pack.HasRun then
        Ns := Pack.Run;
      if Inner = '' then
        AddTextInline(Para, Ns, XmlUnescape(Inner))
      else if Pos('<', Inner) = 0 then
        AddTextInline(Para, Ns, XmlUnescape(Inner))
      else
        ParseOdtText(Inner, Para, Ns, Styles, Doc, Zip);
    end
    else if LN = 's' then
    begin
      Cnt := StrToIntDef(XmlAttr(OpenTag, 'text:c'), 1);
      AddTextInline(Para, St, StringOfChar(' ', Max(1, Cnt)));
    end
    else if LN = 'tab' then
      AddKindInline(Para, dikTab, St)
    else if LN = 'line-break' then
      AddKindInline(Para, dikBreak, St)
    else if (LN = 'frame') or (LN = 'image') then
    begin
      Href := XmlAttr(OpenTag, 'xlink:href');
      if Href = '' then
      begin
        Q := 1;
        var N2, O2, I2: string;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if LocalName(N2) = 'image' then
            Href := XmlAttr(O2, 'xlink:href');
      end;
      W := XmlAttr(OpenTag, 'svg:width');
      H := XmlAttr(OpenTag, 'svg:height');
      if Href <> '' then
      begin
        Bmp := LoadBmp(ZipReadBytes(Zip, Href));
        if Assigned(Bmp) then
        begin
          Doc.Images.Add(Bmp);
          It := TDocInline.Create;
          It.Kind := dikImage;
          It.Style := St;
          It.Image := Bmp;
          if EndsText('cm', W) then
            It.ImgW := StrToFloatDef(Copy(W, 1, Length(W) - 2), 0) * 37.8
          else
            It.ImgW := Bmp.Width;
          if EndsText('cm', H) then
            It.ImgH := StrToFloatDef(Copy(H, 1, Length(H) - 2), 0) * 37.8
          else
            It.ImgH := Bmp.Height;
          Para.Inlines.Add(It);
        end;
      end;
    end
    else
      ParseOdtText(Inner, Para, St, Styles, Doc, Zip);
  end;
  if (Para.Inlines.Count = 0) and (Pos('<', Frag) = 0) then
    AddTextInline(Para, St, XmlUnescape(Frag));
end;

function LoadOdt(const APath: string; out AError: string): TDocDocument;
var
  Zip: TZipFile;
  Stream: TFileStream;
  Content, StylesXml, Body: string;
  Styles: TDictionary<string, TStylePack>;
  P, Q: Integer;
  Name, OpenTag, Inner, LN, N2, O2, I2, StyleName: string;
  Pack: TStylePack;
  DefaultRun: TDocRunStyle;
  Para: TDocPara;
  Blk: TDocBlock;
  St: TDocRunStyle;
  Pair: TPair<string, TStylePack>;
begin
  Result := nil;
  AError := '';
  Stream := nil;
  Zip := nil;
  Styles := TDictionary<string, TStylePack>.Create;
  try
    try
      Zip := ZipOpenShared(APath, Stream);
    except
      on E: Exception do
      begin
        AError := E.Message;
        Exit;
      end;
    end;
    Content := ZipReadUtf8(Zip, 'content.xml');
    StylesXml := ZipReadUtf8(Zip, 'styles.xml');
    if Content = '' then
    begin
      AError := 'Нет content.xml';
      Exit;
    end;
    DefaultRun.InitDefault;
    P := 1;
    while XmlNextChild(StylesXml + Content, P, Name, OpenTag, Inner) do
    begin
      LN := LocalName(Name);
      if (LN = 'style') or (LN = 'default-style') then
      begin
        StyleName := XmlAttr(OpenTag, 'style:name');
        if StyleName = '' then
          Continue;
        Pack := Default(TStylePack);
        Pack.Id := StyleName;
        Pack.Run.InitDefault;
        Pack.Para := TDocPara.Create;
        ApplyOdtStyle(Inner + OpenTag, Pack.Para, Pack.Run);
        Pack.HasPara := True;
        Pack.HasRun := True;
        Styles.AddOrSetValue(StyleName, Pack);
      end
      else if Inner <> '' then
      begin
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if (LocalName(N2) = 'style') or (LocalName(N2) = 'default-style') then
          begin
            StyleName := XmlAttr(O2, 'style:name');
            if StyleName = '' then
              Continue;
            Pack := Default(TStylePack);
            Pack.Id := StyleName;
            Pack.Run.InitDefault;
            Pack.Para := TDocPara.Create;
            ApplyOdtStyle(I2 + O2, Pack.Para, Pack.Run);
            Pack.HasPara := True;
            Pack.HasRun := True;
            Styles.AddOrSetValue(StyleName, Pack);
          end;
      end;
    end;
    Result := TDocDocument.Create;
    Result.FilePath := APath;
    Body := XmlFindLocalInner(Content, 'text');
    if Body = '' then
      Body := XmlFindLocalInner(Content, 'body');
    if Body = '' then
      Body := Content;
    P := 1;
    while XmlNextChild(Body, P, Name, OpenTag, Inner) do
    begin
      if Result.Blocks.Count >= DocQVMaxBlocks then
      begin
        Result.Truncated := True;
        Break;
      end;
      LN := LocalName(Name);
      if (LN = 'p') or (LN = 'h') then
      begin
        St := DefaultRun;
        Para := TDocPara.Create;
        StyleName := XmlAttr(OpenTag, 'text:style-name');
        if Styles.TryGetValue(StyleName, Pack) then
        begin
          St := Pack.Run;
          Para.Align := Pack.Para.Align;
          Para.SpaceBefore := Pack.Para.SpaceBefore;
          Para.SpaceAfter := Pack.Para.SpaceAfter;
          Para.LeftInd := Pack.Para.LeftInd;
          Para.HasFill := Pack.Para.HasFill;
          Para.Fill := Pack.Para.Fill;
        end;
        if LN = 'h' then
        begin
          St.Bold := True;
          St.SizePt := Max(St.SizePt, 14);
        end;
        if Pos('<', Inner) = 0 then
          AddTextInline(Para, St, XmlUnescape(Inner))
        else
          ParseOdtText(Inner, Para, St, Styles, Result, Zip);
        Blk := TDocBlock.Create;
        Blk.Kind := dbkPara;
        Blk.Para := Para;
        Result.Blocks.Add(Blk);
      end
      else if Inner <> '' then
      begin
        Q := 1;
        while XmlNextChild(Inner, Q, N2, O2, I2) do
          if (LocalName(N2) = 'p') or (LocalName(N2) = 'h') then
          begin
            St := DefaultRun;
            Para := TDocPara.Create;
            StyleName := XmlAttr(O2, 'text:style-name');
            if Styles.TryGetValue(StyleName, Pack) then
            begin
              St := Pack.Run;
              Para.Align := Pack.Para.Align;
            end;
            if Pos('<', I2) = 0 then
              AddTextInline(Para, St, XmlUnescape(I2))
            else
              ParseOdtText(I2, Para, St, Styles, Result, Zip);
            Blk := TDocBlock.Create;
            Blk.Kind := dbkPara;
            Blk.Para := Para;
            Result.Blocks.Add(Blk);
          end;
      end;
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      AError := E.Message;
    end;
  end;
  for Pair in Styles do
    Pair.Value.Para.Free;
  Styles.Free;
  if Assigned(Zip) then
  begin
    Zip.Close;
    Zip.Free;
  end;
  Stream.Free;
end;

{ ---------- RTF ---------- }

function RtfReadKeyword(const S: string; var P: Integer; out Dest: Integer): string;
var
  Start: Integer;
  Neg: Boolean;
  Digs: string;
begin
  Result := '';
  Dest := 0;
  if (P > Length(S)) or (S[P] <> '\') then
    Exit;
  Inc(P);
  if P > Length(S) then
    Exit;
  if not S[P].IsLetter then
  begin
    Result := S[P];
    Inc(P);
    Exit;
  end;
  Start := P;
  while (P <= Length(S)) and S[P].IsLetter do
    Inc(P);
  Result := Copy(S, Start, P - Start);
  Neg := False;
  if (P <= Length(S)) and (S[P] = '-') then
  begin
    Neg := True;
    Inc(P);
  end;
  Digs := '';
  while (P <= Length(S)) and S[P].IsDigit do
  begin
    Digs := Digs + S[P];
    Inc(P);
  end;
  if Digs <> '' then
  begin
    Dest := StrToIntDef(Digs, 0);
    if Neg then
      Dest := -Dest;
  end;
  if (P <= Length(S)) and (S[P] = ' ') then
    Inc(P);
end;

procedure RtfSkipGroup(const S: string; var P: Integer);
var
  Depth: Integer;
  Dummy: Integer;
  Kw: string;
begin
  Depth := 1;
  while (P <= Length(S)) and (Depth > 0) do
  begin
    if S[P] = '{' then
    begin
      Inc(Depth);
      Inc(P);
    end
    else if S[P] = '}' then
    begin
      Dec(Depth);
      Inc(P);
    end
    else if S[P] = '\' then
    begin
      Kw := RtfReadKeyword(S, P, Dummy);
      if Kw = '''' then
        Inc(P, 2);
    end
    else
      Inc(P);
  end;
end;

function LoadRtf(const APath: string; out AError: string): TDocDocument;
var
  Raw: TBytes;
  S: string;
  P, N, Cpg, FIdx, USkip, I: Integer;
  Kw: string;
  Ch: Char;
  St: TDocRunStyle;
  Para: TDocPara;
  Blk: TDocBlock;
  Fonts: TDictionary<Integer, string>;
  Colors: TDictionary<Integer, TAlphaColor>;
  CR, CG, CB, CIdx: Integer;
  Enc: TEncoding;
  B: TBytes;
  Hex: string;
  FlushPara: Boolean;

  procedure EnsurePara;
  begin
    if Para = nil then
    begin
      Para := TDocPara.Create;
      Para.LineMult := 1.15;
    end;
  end;

  procedure EndPara;
  begin
    if Para = nil then
      Exit;
    Blk := TDocBlock.Create;
    Blk.Kind := dbkPara;
    Blk.Para := Para;
    Result.Blocks.Add(Blk);
    Para := nil;
  end;

begin
  Result := nil;
  AError := '';
  try
    Raw := TFile.ReadAllBytes(APath);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Exit;
    end;
  end;
  if Length(Raw) < 5 then
  begin
    AError := 'Пустой RTF';
    Exit;
  end;
  S := TEncoding.ANSI.GetString(Raw);
  if not StartsText('{\rtf', S) then
  begin
    AError := 'Не RTF';
    Exit;
  end;
  Result := TDocDocument.Create;
  Result.FilePath := APath;
  Fonts := TDictionary<Integer, string>.Create;
  Colors := TDictionary<Integer, TAlphaColor>.Create;
  Para := nil;
  St.InitDefault;
  Cpg := 1252;
  FIdx := 0;
  USkip := 1;
  CR := 0;
  CG := 0;
  CB := 0;
  CIdx := 0;
  P := 1;
  try
    while P <= Length(S) do
    begin
      if Result.Blocks.Count >= DocQVMaxBlocks then
      begin
        Result.Truncated := True;
        Break;
      end;
      Ch := S[P];
      if Ch = '{' then
      begin
        Inc(P);
        if (P < Length(S)) and (S[P] = '\') and (P + 1 <= Length(S)) and (S[P + 1] = '*') then
          RtfSkipGroup(S, P)
        else if (P < Length(S) - 4) and (Copy(S, P, 5) = '\pict') then
          RtfSkipGroup(S, P)
        else if (P < Length(S) - 7) and (Copy(S, P, 8) = '\fonttbl') then
        begin
          { parse fonttbl simply inside this group via normal loop; depth handled by braces }
        end
        else
          Continue;
      end
      else if Ch = '}' then
      begin
        Inc(P);
      end
      else if Ch = '\' then
      begin
        Kw := RtfReadKeyword(S, P, N);
        if Kw = '''' then
        begin
          Hex := Copy(S, P, 2);
          Inc(P, 2);
          SetLength(B, 1);
          B[0] := Byte(StrToIntDef('$' + Hex, 32));
          Enc := TEncoding.GetEncoding(Cpg);
          try
            EnsurePara;
            AddTextInline(Para, St, Enc.GetString(B));
          finally
            Enc.Free;
          end;
        end
        else if Kw = 'u' then
        begin
          EnsurePara;
          if N < 0 then
            N := N + 65536;
          AddTextInline(Para, St, Char(N));
          I := 0;
          while (I < USkip) and (P <= Length(S)) do
          begin
            if S[P] = '\' then
              RtfReadKeyword(S, P, N)
            else
              Inc(P);
            Inc(I);
          end;
        end
        else if Kw = 'uc' then
          USkip := N
        else if Kw = 'ansicpg' then
          Cpg := N
        else if Kw = 'pard' then
        begin
          if Para <> nil then
            EndPara;
          EnsurePara;
        end
        else if Kw = 'par' then
        begin
          EnsurePara;
          EndPara;
        end
        else if Kw = 'page' then
        begin
          EnsurePara;
          AddKindInline(Para, dikPageBreak, St);
          EndPara;
        end
        else if Kw = 'line' then
        begin
          EnsurePara;
          AddKindInline(Para, dikBreak, St);
        end
        else if Kw = 'tab' then
        begin
          EnsurePara;
          AddKindInline(Para, dikTab, St);
        end
        else if Kw = 'b' then
          St.Bold := N <> 0
        else if Kw = 'i' then
          St.Italic := N <> 0
        else if Kw = 'ul' then
          St.Underline := True
        else if (Kw = 'ulnone') or (Kw = 'ul0') then
          St.Underline := False
        else if Kw = 'strike' then
          St.Strike := N <> 0
        else if Kw = 'fs' then
          St.SizePt := Max(6, N / 2.0)
        else if Kw = 'f' then
        begin
          FIdx := N;
          if Fonts.ContainsKey(FIdx) then
            St.FontName := Fonts[FIdx];
        end
        else if Kw = 'cf' then
        begin
          if Colors.ContainsKey(N) then
          begin
            St.Color := Colors[N];
            St.HasColor := True;
          end;
        end
        else if Kw = 'qc' then
        begin
          EnsurePara;
          Para.Align := daCenter;
        end
        else if Kw = 'qr' then
        begin
          EnsurePara;
          Para.Align := daRight;
        end
        else if Kw = 'qj' then
        begin
          EnsurePara;
          Para.Align := daJustify;
        end
        else if Kw = 'ql' then
        begin
          EnsurePara;
          Para.Align := daLeft;
        end
        else if Kw = 'plain' then
          St.InitDefault
        else if Kw = 'fnil' then
        else if Kw = 'froman' then
        else if Kw = 'fswiss' then
        else if Kw = 'fcharset' then
        else if Kw = 'red' then
          CR := N
        else if Kw = 'green' then
          CG := N
        else if Kw = 'blue' then
        begin
          CB := N;
          Colors.AddOrSetValue(CIdx, $FF000000 or (Cardinal(CR) shl 16) or
            (Cardinal(CG) shl 8) or Cardinal(CB));
          Inc(CIdx);
        end
        else if Kw = 'deff' then
        else if Kw = 'rtf' then
        else if Kw = 'fonttbl' then
        else if Kw = 'colortbl' then
        begin
          Colors.AddOrSetValue(0, $FF000000);
          CIdx := 1;
        end;
      end
      else if Ch = #13 then
        Inc(P)
      else if Ch = #10 then
        Inc(P)
      else
      begin
        EnsurePara;
        AddTextInline(Para, St, Ch);
        Inc(P);
      end;
    end;
    if Para <> nil then
      EndPara;
  finally
    Fonts.Free;
    Colors.Free;
  end;
end;

const
  TextPageMargin = 40;
  TextBodyPt = 15;

function IsMarkdownFile(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := MatchText(Ext, ['.md', '.markdown', '.mdown', '.mkd']);
end;

function NewTextPageDoc(const APath: string): TDocDocument;
begin
  Result := TDocDocument.Create;
  Result.FilePath := APath;
  Result.PaperW := 794;
  Result.PaperH := 1123;
  Result.MarginL := TextPageMargin;
  Result.MarginT := TextPageMargin;
  Result.MarginR := TextPageMargin;
  Result.MarginB := TextPageMargin;
end;

procedure AddParaBlock(Doc: TDocDocument; Para: TDocPara);
var
  Blk: TDocBlock;
begin
  if (Doc = nil) or (Para = nil) then
  begin
    Para.Free;
    Exit;
  end;
  Blk := TDocBlock.Create;
  Blk.Kind := dbkPara;
  Blk.Para := Para;
  Doc.Blocks.Add(Blk);
  if Doc.Blocks.Count >= DocQVMaxBlocks then
    Doc.Truncated := True;
end;

procedure AddTableBlock(Doc: TDocDocument; Tbl: TDocTable);
var
  Blk: TDocBlock;
begin
  if (Doc = nil) or (Tbl = nil) then
  begin
    Tbl.Free;
    Exit;
  end;
  Blk := TDocBlock.Create;
  Blk.Kind := dbkTable;
  Blk.Table := Tbl;
  Doc.Blocks.Add(Blk);
  if Doc.Blocks.Count >= DocQVMaxBlocks then
    Doc.Truncated := True;
end;

function TextBodyStyle: TDocRunStyle;
begin
  Result.InitDefault;
  Result.FontName := 'Calibri';
  Result.SizePt := TextBodyPt;
end;

function TextCodeStyle: TDocRunStyle;
begin
  Result.InitDefault;
  Result.FontName := 'Consolas';
  Result.SizePt := 13;
  Result.Color := $FF1A1A1A;
  Result.HasColor := True;
end;

function HeadingRunStyle(ALevel: Integer): TDocRunStyle;
begin
  Result := TextBodyStyle;
  Result.Bold := True;
  case ALevel of
    1: Result.SizePt := 26;
    2: Result.SizePt := 22;
    3: Result.SizePt := 18;
    4: Result.SizePt := 16;
    5: Result.SizePt := 15;
  else
    Result.SizePt := 14;
  end;
end;

function IsCodeLikeTextExt(const AExt: string): Boolean;
begin
  Result := MatchText(AExt, ['.json', '.ini', '.inf', '.log', '.reg', '.conf',
    '.cfg', '.toml', '.editorconfig', '.gitignore', '.gitattributes', '.yml',
    '.yaml', '.xml', '.csv', '.tsv', '.bat', '.cmd', '.ps1', '.sh']);
end;

function LoadPlainTextFromString(const AText, APath: string): TDocDocument;
var
  SL: TStringList;
  I: Integer;
  Para: TDocPara;
  St: TDocRunStyle;
  Ext: string;
begin
  Result := NewTextPageDoc(APath);
  Ext := LowerCase(ExtractFileExt(APath));
  if IsCodeLikeTextExt(Ext) then
    St := TextCodeStyle
  else
    St := TextBodyStyle;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    if SL.Count = 0 then
    begin
      Para := TDocPara.Create;
      Para.LineMult := 1.25;
      AddTextInline(Para, St, '');
      AddParaBlock(Result, Para);
      Exit;
    end;
    for I := 0 to SL.Count - 1 do
    begin
      Para := TDocPara.Create;
      Para.LineMult := 1.28;
      Para.SpaceAfter := 1;
      if SL[I] = '' then
        Para.SpaceAfter := 10
      else
        AddTextInline(Para, St, SL[I]);
      AddParaBlock(Result, Para);
      if Result.Truncated then
        Break;
    end;
  finally
    SL.Free;
  end;
end;

function CountLeadIndent(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = ' ' then
      Inc(Result)
    else if S[I] = #9 then
      Inc(Result, 4)
    else
      Break;
    Inc(I);
  end;
end;

function TrimLeftIndent(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  Result := Copy(S, I, MaxInt);
end;

function IsMdHr(const S: string): Boolean;
var
  T: string;
  I, Dash, Star, Und: Integer;
begin
  T := Trim(S);
  if Length(T) < 3 then
    Exit(False);
  Dash := 0;
  Star := 0;
  Und := 0;
  for I := 1 to Length(T) do
  begin
    case T[I] of
      '-': Inc(Dash);
      '*': Inc(Star);
      '_': Inc(Und);
      ' ', #9: ;
    else
      Exit(False);
    end;
  end;
  Result := (Dash >= 3) and (Star = 0) and (Und = 0) or
            (Star >= 3) and (Dash = 0) and (Und = 0) or
            (Und >= 3) and (Dash = 0) and (Star = 0);
end;

function MdHeadingLevel(const S: string; out ATitle: string): Integer;
var
  I, N: Integer;
  T: string;
begin
  Result := 0;
  ATitle := '';
  T := TrimLeftIndent(S);
  N := 0;
  I := 1;
  while (I <= Length(T)) and (T[I] = '#') and (N < 6) do
  begin
    Inc(N);
    Inc(I);
  end;
  if (N = 0) or (I > Length(T)) or ((T[I] <> ' ') and (T[I] <> #9)) then
    Exit;
  Result := N;
  ATitle := Trim(Copy(T, I + 1, MaxInt));
  while (ATitle <> '') and (ATitle[Length(ATitle)] = '#') do
    SetLength(ATitle, Length(ATitle) - 1);
  ATitle := Trim(ATitle);
end;

function MdFenceOpen(const S: string; out AMark: Char; out ALang: string): Boolean;
var
  T: string;
  N: Integer;
begin
  Result := False;
  AMark := #0;
  ALang := '';
  T := TrimRight(S);
  T := TrimLeftIndent(T);
  if Length(T) < 3 then
    Exit;
  if (T[1] = '`') and (Length(T) >= 3) and (T[2] = '`') and (T[3] = '`') then
    AMark := '`'
  else if (T[1] = '~') and (Length(T) >= 3) and (T[2] = '~') and (T[3] = '~') then
    AMark := '~'
  else
    Exit;
  N := 3;
  while (N <= Length(T)) and (T[N] = AMark) do
    Inc(N);
  ALang := Trim(Copy(T, N, MaxInt));
  Result := True;
end;

function MdFenceClose(const S: string; AMark: Char): Boolean;
var
  T: string;
  N: Integer;
begin
  T := Trim(S);
  if (Length(T) < 3) or (T[1] <> AMark) then
    Exit(False);
  N := 1;
  while (N <= Length(T)) and (T[N] = AMark) do
    Inc(N);
  Result := (N > 3) and (Trim(Copy(T, N, MaxInt)) = '');
end;

function MdListMarker(const S: string; out ARest: string; out AOrdered: Boolean;
  out ANum: string): Boolean;
var
  T: string;
  I: Integer;
begin
  Result := False;
  ARest := S;
  AOrdered := False;
  ANum := '• ';
  T := TrimLeftIndent(S);
  if T = '' then
    Exit;
  if ((T[1] = '-') or (T[1] = '*') or (T[1] = '+')) and
     (Length(T) > 1) and ((T[2] = ' ') or (T[2] = #9)) then
  begin
    ARest := Trim(Copy(T, 3, MaxInt));
    if StartsText('[ ]', ARest) then
    begin
      ANum := '☐ ';
      ARest := Trim(Copy(ARest, 4, MaxInt));
    end
    else if StartsText('[x]', ARest) or StartsText('[X]', ARest) then
    begin
      ANum := '☑ ';
      ARest := Trim(Copy(ARest, 4, MaxInt));
    end;
    Result := True;
    Exit;
  end;
  I := 1;
  if not CharInSet(T[1], ['0'..'9']) then
    Exit;
  while (I <= Length(T)) and CharInSet(T[I], ['0'..'9']) do
    Inc(I);
  if (I > Length(T)) or (T[I] <> '.') then
    Exit;
  if (I + 1 <= Length(T)) and (T[I + 1] <> ' ') and (T[I + 1] <> #9) then
    Exit;
  AOrdered := True;
  ANum := Copy(T, 1, I) + ' ';
  ARest := Trim(Copy(T, I + 2, MaxInt));
  Result := True;
end;

function IsMdTableSep(const S: string): Boolean;
var
  T: string;
  I, Dash: Integer;
  HasPipe: Boolean;
begin
  T := Trim(S);
  if T = '' then
    Exit(False);
  HasPipe := False;
  Dash := 0;
  for I := 1 to Length(T) do
    case T[I] of
      '|': HasPipe := True;
      '-': Inc(Dash);
      ':', ' ', #9: ;
    else
      Exit(False);
    end;
  Result := (Dash >= 3) and HasPipe;
end;

function SplitMdTableRow(const S: string): TArray<string>;
var
  T: string;
  I, Start: Integer;
begin
  T := Trim(S);
  if (T <> '') and (T[1] = '|') then
    Delete(T, 1, 1);
  if (T <> '') and (T[Length(T)] = '|') then
    SetLength(T, Length(T) - 1);
  SetLength(Result, 0);
  Start := 1;
  for I := 1 to Length(T) + 1 do
    if (I > Length(T)) or (T[I] = '|') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(Copy(T, Start, I - Start));
      Start := I + 1;
    end;
end;

procedure ParseMdInlines(Para: TDocPara; const S: string; const Base: TDocRunStyle);

  procedure AddRun(const Txt: string; const St: TDocRunStyle);
  begin
    if Txt <> '' then
      AddTextInline(Para, St, Txt);
  end;

  function FindClose(const Open: string; AFrom: Integer): Integer;
  var
    P: Integer;
  begin
    Result := 0;
    P := AFrom;
    while P <= Length(S) do
    begin
      if S[P] = '\' then
      begin
        Inc(P, 2);
        Continue;
      end;
      if Copy(S, P, Length(Open)) = Open then
        Exit(P);
      Inc(P);
    end;
  end;

var
  I, J, K, N: Integer;
  Acc: string;
  St, Inner: TDocRunStyle;
  LabelTxt, Url: string;
begin
  St := Base;
  I := 1;
  N := Length(S);
  Acc := '';
  while I <= N do
  begin
    if S[I] = '\' then
    begin
      if I < N then
      begin
        Acc := Acc + S[I + 1];
        Inc(I, 2);
      end
      else
      begin
        Acc := Acc + '\';
        Inc(I);
      end;
      Continue;
    end;
    if S[I] = '`' then
    begin
      AddRun(Acc, St);
      Acc := '';
      J := I + 1;
      while (J <= N) and (S[J] <> '`') do
        Inc(J);
      if J <= N then
      begin
        Inner := TextCodeStyle;
        Inner.SizePt := Max(10, Base.SizePt - 1);
        Inner.Highlight := $FFECECEC;
        Inner.HasHighlight := True;
        AddRun(Copy(S, I + 1, J - I - 1), Inner);
        I := J + 1;
      end
      else
      begin
        Acc := Acc + '`';
        Inc(I);
      end;
      Continue;
    end;
    if Copy(S, I, 2) = '~~' then
    begin
      J := FindClose('~~', I + 2);
      if J > 0 then
      begin
        AddRun(Acc, St);
        Acc := '';
        Inner := St;
        Inner.Strike := True;
        ParseMdInlines(Para, Copy(S, I + 2, J - I - 2), Inner);
        I := J + 2;
        Continue;
      end;
    end;
    if Copy(S, I, 3) = '***' then
    begin
      J := FindClose('***', I + 3);
      if J > 0 then
      begin
        AddRun(Acc, St);
        Acc := '';
        Inner := St;
        Inner.Bold := True;
        Inner.Italic := True;
        ParseMdInlines(Para, Copy(S, I + 3, J - I - 3), Inner);
        I := J + 3;
        Continue;
      end;
    end;
    if Copy(S, I, 2) = '**' then
    begin
      J := FindClose('**', I + 2);
      if J > 0 then
      begin
        AddRun(Acc, St);
        Acc := '';
        Inner := St;
        Inner.Bold := True;
        ParseMdInlines(Para, Copy(S, I + 2, J - I - 2), Inner);
        I := J + 2;
        Continue;
      end;
    end;
    if Copy(S, I, 2) = '__' then
    begin
      J := FindClose('__', I + 2);
      if J > 0 then
      begin
        AddRun(Acc, St);
        Acc := '';
        Inner := St;
        Inner.Bold := True;
        ParseMdInlines(Para, Copy(S, I + 2, J - I - 2), Inner);
        I := J + 2;
        Continue;
      end;
    end;
    if (S[I] = '*') and ((I = 1) or (S[I - 1] <> '*')) then
    begin
      J := FindClose('*', I + 1);
      if (J > I + 1) and ((J = N) or (Copy(S, J, 2) <> '**')) then
      begin
        AddRun(Acc, St);
        Acc := '';
        Inner := St;
        Inner.Italic := True;
        ParseMdInlines(Para, Copy(S, I + 1, J - I - 1), Inner);
        I := J + 1;
        Continue;
      end;
    end;
    if (S[I] = '_') and ((I = 1) or not CharInSet(S[I - 1], ['A'..'Z', 'a'..'z', '0'..'9'])) then
    begin
      J := FindClose('_', I + 1);
      if (J > I + 1) and ((J = N) or not CharInSet(S[J + 1], ['A'..'Z', 'a'..'z', '0'..'9'])) then
      begin
        AddRun(Acc, St);
        Acc := '';
        Inner := St;
        Inner.Italic := True;
        ParseMdInlines(Para, Copy(S, I + 1, J - I - 1), Inner);
        I := J + 1;
        Continue;
      end;
    end;
    if (S[I] = '!') and (I < N) and (S[I + 1] = '[') then
    begin
      J := PosEx('](', S, I + 2);
      if J > 0 then
      begin
        K := PosEx(')', S, J + 2);
        if K > 0 then
        begin
          AddRun(Acc, St);
          Acc := '';
          LabelTxt := Copy(S, I + 2, J - I - 2);
          Inner := St;
          Inner.Italic := True;
          Inner.Color := $FF555555;
          Inner.HasColor := True;
          if LabelTxt = '' then
            LabelTxt := 'изображение';
          AddRun(LabelTxt, Inner);
          I := K + 1;
          Continue;
        end;
      end;
    end;
    if S[I] = '[' then
    begin
      J := PosEx('](', S, I + 1);
      if J > 0 then
      begin
        K := PosEx(')', S, J + 2);
        if K > 0 then
        begin
          AddRun(Acc, St);
          Acc := '';
          LabelTxt := Copy(S, I + 1, J - I - 1);
          Url := Copy(S, J + 2, K - J - 2);
          Inner := St;
          Inner.Color := $FF0563C1;
          Inner.HasColor := True;
          Inner.Underline := True;
          if LabelTxt = '' then
            LabelTxt := Url;
          AddRun(LabelTxt, Inner);
          I := K + 1;
          Continue;
        end;
      end;
    end;
    Acc := Acc + S[I];
    Inc(I);
  end;
  AddRun(Acc, St);
end;

function LoadMarkdownFromString(const AText, APath: string): TDocDocument;
var
  SL: TStringList;
  I, Lvl, QuoteLvl: Integer;
  Line, Rest, Title, Lang, Num: string;
  Fence: Char;
  InFence, Ordered: Boolean;
  Para: TDocPara;
  St: TDocRunStyle;
  Tbl: TDocTable;
  Row: TDocRow;
  Cell: TDocCell;
  Cells: TArray<string>;
  C: Integer;

  function Peek(ADelta: Integer): string;
  begin
    if (I + ADelta >= 0) and (I + ADelta < SL.Count) then
      Result := SL[I + ADelta]
    else
      Result := '';
  end;

  procedure FlushQuote;
  begin
    QuoteLvl := 0;
  end;

begin
  Result := NewTextPageDoc(APath);
  SL := TStringList.Create;
  try
    SL.Text := AText;
    I := 0;
    InFence := False;
    Fence := #0;
    QuoteLvl := 0;
    while (I < SL.Count) and not Result.Truncated do
    begin
      Line := SL[I];
      if InFence then
      begin
        if MdFenceClose(Line, Fence) then
          InFence := False
        else
        begin
          Para := TDocPara.Create;
          Para.LineMult := 1.15;
          Para.SpaceAfter := 0;
          Para.LeftInd := 8;
          Para.HasFill := True;
          Para.Fill := $FFF4F4F4;
          St := TextCodeStyle;
          if Line = '' then
            AddTextInline(Para, St, ' ')
          else
            AddTextInline(Para, St, Line);
          AddParaBlock(Result, Para);
        end;
        Inc(I);
        Continue;
      end;

      if MdFenceOpen(Line, Fence, Lang) then
      begin
        InFence := True;
        Inc(I);
        Continue;
      end;

      if Trim(Line) = '' then
      begin
        Para := TDocPara.Create;
        Para.SpaceAfter := 8;
        AddParaBlock(Result, Para);
        FlushQuote;
        Inc(I);
        Continue;
      end;

      Lvl := MdHeadingLevel(Line, Title);
      if Lvl > 0 then
      begin
        Para := TDocPara.Create;
        Para.LineMult := 1.15;
        Para.OutlineLvl := Lvl - 1;
        case Lvl of
          1:
            begin
              Para.SpaceBefore := 16;
              Para.SpaceAfter := 10;
            end;
          2:
            begin
              Para.SpaceBefore := 14;
              Para.SpaceAfter := 8;
            end;
        else
          Para.SpaceBefore := 10;
          Para.SpaceAfter := 6;
        end;
        ParseMdInlines(Para, Title, HeadingRunStyle(Lvl));
        AddParaBlock(Result, Para);
        FlushQuote;
        Inc(I);
        Continue;
      end;

      if (I + 1 < SL.Count) then
      begin
        Rest := Trim(Peek(1));
        if (Rest <> '') and ((Rest[1] = '=') or (Rest[1] = '-')) and
           (Trim(StringReplace(StringReplace(Rest, '=', '', [rfReplaceAll]),
             '-', '', [rfReplaceAll])) = '') and (Length(Rest) >= 3) then
        begin
          if Rest[1] = '=' then
            Lvl := 1
          else
            Lvl := 2;
          Para := TDocPara.Create;
          Para.LineMult := 1.15;
          Para.OutlineLvl := Lvl - 1;
          Para.SpaceBefore := 14;
          Para.SpaceAfter := 8;
          ParseMdInlines(Para, Trim(Line), HeadingRunStyle(Lvl));
          AddParaBlock(Result, Para);
          Inc(I, 2);
          FlushQuote;
          Continue;
        end;
      end;

      if IsMdHr(Line) then
      begin
        Para := TDocPara.Create;
        Para.SpaceBefore := 8;
        Para.SpaceAfter := 8;
        Para.LineMult := 0.35;
        Para.HasFill := True;
        Para.Fill := $FFD8D8D8;
        St := TextBodyStyle;
        AddTextInline(Para, St, ' ');
        AddParaBlock(Result, Para);
        FlushQuote;
        Inc(I);
        Continue;
      end;

      if (Pos('|', Line) > 0) and IsMdTableSep(Peek(1)) then
      begin
        Tbl := TDocTable.Create;
        Cells := SplitMdTableRow(Line);
        Row := TDocRow.Create;
        for C := 0 to High(Cells) do
        begin
          Cell := TDocCell.Create;
          Cell.HasFill := True;
          Cell.Fill := $FFF0F0F0;
          Para := TDocPara.Create;
          Para.LineMult := 1.15;
          St := TextBodyStyle;
          St.Bold := True;
          ParseMdInlines(Para, Cells[C], St);
          Cell.Paras.Add(Para);
          Row.Cells.Add(Cell);
        end;
        Tbl.Rows.Add(Row);
        Inc(I, 2);
        while I < SL.Count do
        begin
          if (Trim(SL[I]) = '') or (Pos('|', SL[I]) = 0) then
            Break;
          Cells := SplitMdTableRow(SL[I]);
          Row := TDocRow.Create;
          for C := 0 to High(Cells) do
          begin
            Cell := TDocCell.Create;
            Para := TDocPara.Create;
            Para.LineMult := 1.15;
            ParseMdInlines(Para, Cells[C], TextBodyStyle);
            Cell.Paras.Add(Para);
            Row.Cells.Add(Cell);
          end;
          Tbl.Rows.Add(Row);
          Inc(I);
        end;
        AddTableBlock(Result, Tbl);
        FlushQuote;
        Continue;
      end;

      Rest := TrimLeftIndent(Line);
      QuoteLvl := 0;
      while (Rest <> '') and (Rest[1] = '>') do
      begin
        Inc(QuoteLvl);
        Delete(Rest, 1, 1);
        if (Rest <> '') and ((Rest[1] = ' ') or (Rest[1] = #9)) then
          Delete(Rest, 1, 1);
      end;
      if QuoteLvl > 0 then
      begin
        Para := TDocPara.Create;
        Para.LineMult := 1.3;
        Para.SpaceAfter := 4;
        Para.LeftInd := 16 + (QuoteLvl - 1) * 12;
        St := TextBodyStyle;
        St.Italic := True;
        St.Color := $FF444444;
        St.HasColor := True;
        if Rest = '' then
          AddTextInline(Para, St, ' ')
        else
          ParseMdInlines(Para, Rest, St);
        AddParaBlock(Result, Para);
        Inc(I);
        Continue;
      end;

      if MdListMarker(Line, Rest, Ordered, Num) then
      begin
        Para := TDocPara.Create;
        Para.LineMult := 1.28;
        Para.SpaceAfter := 3;
        Para.LeftInd := 12 + (CountLeadIndent(Line) div 2) * 10;
        Para.NumText := Num;
        ParseMdInlines(Para, Rest, TextBodyStyle);
        AddParaBlock(Result, Para);
        Inc(I);
        Continue;
      end;

      Para := TDocPara.Create;
      Para.LineMult := 1.32;
      Para.SpaceAfter := 8;
      ParseMdInlines(Para, Trim(Line), TextBodyStyle);
      while (I + 1 < SL.Count) and (Trim(Peek(1)) <> '') and
            (MdHeadingLevel(Peek(1), Title) = 0) and not IsMdHr(Peek(1)) and
            not MdFenceOpen(Peek(1), Fence, Lang) and
            not MdListMarker(Peek(1), Rest, Ordered, Num) and
            (not StartsText('>', TrimLeftIndent(Peek(1)))) do
      begin
        //AddTextInline(Para, TextBodyStyle, ' ');
        AddKindInline(Para, dikBreak, TextBodyStyle);
        ParseMdInlines(Para, Trim(Peek(1)), TextBodyStyle);
        Inc(I);
      end;
      AddParaBlock(Result, Para);
      Inc(I);
    end;
  finally
    SL.Free;
  end;
end;

function LoadTextDocumentFromString(const AText, APath: string;
  out AError: string): TDocDocument;
begin
  AError := '';
  Result := nil;
  try
    if IsMarkdownFile(APath) then
      Result := LoadMarkdownFromString(AText, APath)
    else
      Result := LoadPlainTextFromString(AText, APath);
    if Result = nil then
      AError := 'Не удалось разобрать текст'
    else
    try
      Result.BuildLayout;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        AError := E.Message;
      end;
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      AError := E.Message;
    end;
  end;
end;

function LoadDocumentLimited(const APath: string; out AError: string): TDocDocument;
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
  if not IsDocumentFile(APath) then
  begin
    AError := 'Формат не поддерживается';
    Exit;
  end;
  try
    Sz := TFile.GetSize(APath);
  except
    Sz := 0;
  end;
  if Sz > DocQVMaxBytes then
  begin
    AError := 'Файл слишком большой для просмотра';
    Exit;
  end;
  Ext := LowerCase(ExtractFileExt(APath));
  if MatchText(Ext, ['.docx', '.docm', '.dotx', '.dotm']) then
    Result := LoadDocx(APath, AError)
  else if Ext = '.odt' then
    Result := LoadOdt(APath, AError)
  else if Ext = '.rtf' then
    Result := LoadRtf(APath, AError)
  else
    AError := 'Формат не поддерживается';
end;

function RenderDocumentThumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;
var
  Doc: TDocDocument;
  Err, Fam: string;
  Page: TDocLaidPage;
  Scale, W, H: Single;
  I: Integer;
  It: TDocPaintItem;
  R, IR: TRectF;
  State: TCanvasSaveState;
  C: TCanvas;
begin
  Result := False;
  if (ABitmap = nil) or (AWidth < 8) or (AHeight < 8) then
    Exit;
  Doc := LoadDocumentLimited(APath, Err);
  if Doc = nil then
    Exit;
  try
    if Doc.Pages.Count = 0 then
    try
      Doc.BuildLayout;
    except
    end;
    if (Doc.Pages = nil) or (Doc.Pages.Count = 0) then
      Exit;
    Page := Doc.Pages[0];
    if (Page = nil) or (Page.Items = nil) then
      Exit;
    ABitmap.SetSize(AWidth, AHeight);
    if not ABitmap.Canvas.BeginScene then
      Exit;
    try
      C := ABitmap.Canvas;
      C.Fill.Kind := TBrushKind.Solid;
      C.Fill.Color := $FF3C3C3C;
      C.FillRect(RectF(0, 0, AWidth, AHeight), 0, 0, [], 1);
      Scale := Min((AWidth - 8) / Max(1, Page.PaperW), (AHeight - 8) / Max(1, Page.PaperH));
      W := Page.PaperW * Scale;
      H := Page.PaperH * Scale;
      R := RectF((AWidth - W) / 2, (AHeight - H) / 2, 0, 0);
      R.Right := R.Left + W;
      R.Bottom := R.Top + H;
      C.Fill.Color := $FFFFFFFF;
      C.FillRect(R, 0, 0, [], 1);
      C.Stroke.Kind := TBrushKind.Solid;
      C.Stroke.Color := $FFD0D0D0;
      C.Stroke.Thickness := 1;
      C.DrawRect(R, 0, 0, [], 1);
      State := C.SaveState;
      try
        C.IntersectClipRect(R);
        for I := 0 to Page.Items.Count - 1 do
        begin
          It := Page.Items[I];
          if It = nil then
            Continue;
          IR := RectF(R.Left + It.X * Scale, R.Top + It.Y * Scale,
            R.Left + (It.X + Max(It.W, 0.5)) * Scale,
            R.Top + (It.Y + Max(It.H, 0.5)) * Scale);
          if (IR.Bottom < R.Top) or (IR.Top > R.Bottom) then
            Continue;
          case It.Kind of
            dpkFill:
              begin
                C.Fill.Color := It.Fill;
                C.FillRect(IR, 0, 0, [], 1);
              end;
            dpkLine:
              begin
                C.Stroke.Color := It.Stroke;
                if It.Stroke = 0 then
                  C.Stroke.Color := $FF333333;
                if It.W + 0.01 < It.H then
                begin
                  C.Stroke.Thickness := Max(1, It.W * Scale);
                  C.DrawLine(TPointF.Create(IR.Left, IR.Top),
                    TPointF.Create(IR.Left, IR.Bottom), 1);
                end
                else
                begin
                  C.Stroke.Thickness := Max(1, Min(It.H, 2) * Scale);
                  C.DrawLine(TPointF.Create(IR.Left, IR.Top),
                    TPointF.Create(IR.Right, IR.Top), 1);
                end;
              end;
            dpkImage:
              if Assigned(It.Bitmap) and (It.Bitmap.Width > 0) then
              try
                C.DrawBitmap(It.Bitmap, It.Bitmap.Bounds, IR, 1, True);
              except
              end;
            dpkText:
              if It.Text <> '' then
              begin
                Fam := It.Style.FontName;
                if Fam = '' then
                  Fam := 'Calibri';
                C.Fill.Kind := TBrushKind.Solid;
                C.Font.Family := Fam;
                C.Font.Size := Max(4, It.Style.SizePt * DocViewFontMul * Scale);
                C.Font.Style := [];
                if It.Style.Bold then
                  C.Font.Style := C.Font.Style + [TFontStyle.fsBold];
                if It.Style.Italic then
                  C.Font.Style := C.Font.Style + [TFontStyle.fsItalic];
                if It.Style.HasColor then
                  C.Fill.Color := It.Style.Color
                else
                  C.Fill.Color := $FF222222;
                if IR.Width < C.Font.Size then
                  IR.Right := IR.Left + Max(C.Font.Size,
                    Length(It.Text) * C.Font.Size * 0.55);
                if IR.Height < C.Font.Size then
                  IR.Bottom := IR.Top + C.Font.Size * 1.3;
                C.FillText(IR, It.Text, False, 1, [],
                  TTextAlign.Leading, TTextAlign.Leading);
              end;
          end;
        end;
      finally
        C.RestoreState(State);
      end;
    finally
      ABitmap.Canvas.EndScene;
    end;
    Result := True;
  finally
    Doc.Free;
  end;
end;

end.
