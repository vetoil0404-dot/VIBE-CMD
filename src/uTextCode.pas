unit uTextCode;

{
  Текст Quick View: детектор, кодировка, строки, подсветка, мини-лист плитки.
  Не браузер и не LSP.
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, FMX.Graphics, uThemeManager;

const
  TextQVMaxBytes = 8 * 1024 * 1024;
  TextThumbReadBytes = 4 * 1024;
  TextThumbFileMax = 16 * 1024 * 1024;

type
  TTextEncMode = (temAuto, temUtf8, temAcp, temUtf16);
  TTextLang = (tlNone, tlJson, tlXml, tlMd, tlPas, tlJs);
  TTextRole = (trNormal, trKeyword, trString, trComment, trNumber, trTag);
  TLineState = (lsNormal, lsBlock, lsFence);

  TTextToken = record
    Start: Integer;
    Len: Integer;
    Role: TTextRole;
  end;

function IsListedTextExt(const AExt: string): Boolean;
function TextDefaultIsCode(const AExt: string): Boolean;
function TextFileLooksLike(const APath: string): Boolean;
function TextLangOfExt(const AExt: string): TTextLang;
function LoadTextViewIsCode(const AExt: string): Boolean;
procedure SaveTextViewIsCode(const AExt: string; ACode: Boolean);

function DecodeTextBytes(const ABytes: TBytes; AMode: TTextEncMode;
  out ALabel: string): string;
procedure SplitTextLines(const AText: string; out ALines: TArray<string>;
  out AMaxCols: Integer);

function ScanLineStates(const ALines: TArray<string>; ALang: TTextLang): TArray<TLineState>;
function TokenizeLine(const ALine: string; ALang: TTextLang;
  AEnter: TLineState): TArray<TTextToken>;
function TextRoleColor(ARole: TTextRole; const AColors: TThemeColors): TAlphaColor;

function RenderTextA4Thumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;

implementation

uses
  System.IOUtils, System.Math, System.IniFiles, System.StrUtils, System.Character,
  uDocumentData;

const
  ListedExt: array[0..50] of string = (
    '.txt', '.log', '.ini', '.md', '.markdown', '.json', '.xml', '.yml', '.yaml',
    '.html', '.htm', '.css', '.js', '.mjs', '.ts', '.tsx', '.jsx', '.pas', '.dpr',
    '.dpw', '.cpp', '.c', '.h', '.hpp', '.cs', '.java', '.py', '.go', '.rs',
    '.php', '.sh', '.bash', '.bat', '.cmd', '.ps1', '.conf', '.cfg', '.toml',
    '.sql', '.lua', '.rb', '.swift', '.kt', '.dart', '.vue', '.scss', '.less',
    '.xhtml', '.shtml', '.asp', '.aspx');

function NormExt(const AExt: string): string;
begin
  Result := LowerCase(AExt);
  if (Result <> '') and (Result[1] <> '.') then
    Result := '.' + Result;
end;

function IsListedTextExt(const AExt: string): Boolean;
var
  E: string;
  I: Integer;
begin
  E := NormExt(AExt);
  Result := False;
  for I := Low(ListedExt) to High(ListedExt) do
    if E = ListedExt[I] then
      Exit(True);
end;

function TextDefaultIsCode(const AExt: string): Boolean;
var
  E: string;
begin
  E := NormExt(AExt);
  if MatchText(E, ['.txt', '.log', '.md', '.markdown']) then
    Exit(False);
  Result := IsListedTextExt(E);
end;

function TextLangOfExt(const AExt: string): TTextLang;
var
  E: string;
begin
  E := NormExt(AExt);
  if E = '.json' then
    Exit(tlJson);
  if MatchText(E, ['.xml', '.html', '.htm', '.xhtml', '.shtml', '.vue',
    '.asp', '.aspx']) then
    Exit(tlXml);
  if MatchText(E, ['.md', '.markdown']) then
    Exit(tlMd);
  if MatchText(E, ['.pas', '.dpr', '.dpw']) then
    Exit(tlPas);
  if MatchText(E, ['.js', '.mjs', '.ts', '.tsx', '.jsx']) then
    Exit(tlJs);
  Result := tlNone;
end;

function SettingsIni: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'VibeSetting.ini';
end;

function LoadTextViewIsCode(const AExt: string): Boolean;
var
  E, Key: string;
  Ini: TIniFile;
begin
  E := NormExt(AExt);
  Result := TextDefaultIsCode(E);
  Key := Copy(E, 2, MaxInt);
  if Key = '' then
    Exit;
  Ini := TIniFile.Create(SettingsIni);
  try
    if Ini.ValueExists('TextQV', Key) then
      Result := Ini.ReadInteger('TextQV', Key, Ord(Result)) <> 0;
  finally
    Ini.Free;
  end;
end;

procedure SaveTextViewIsCode(const AExt: string; ACode: Boolean);
var
  Key: string;
  Ini: TIniFile;
begin
  Key := Copy(NormExt(AExt), 2, MaxInt);
  if Key = '' then
    Exit;
  Ini := TIniFile.Create(SettingsIni);
  try
    Ini.WriteInteger('TextQV', Key, Ord(ACode));
  finally
    Ini.Free;
  end;
end;

function TextFileLooksLike(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  I, N, Good: Integer;
  B: Byte;
begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(8192), FS.Size));
      if N = 0 then
        Exit(True);
      SetLength(Buf, N);
      FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
  except
    Exit(False);
  end;
  Good := 0;
  for I := 0 to N - 1 do
  begin
    B := Buf[I];
    if B = 0 then
      Exit(False);
    if (B = 9) or (B = 10) or (B = 13) or (B >= 32) then
      Inc(Good);
  end;
  Result := Good / N >= 0.85;
end;

function MbTake(const ABytes: TBytes; AFrom: Integer; ACodePage, AFlags: Cardinal;
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

function Utf16Le(const ABytes: TBytes; AFrom: Integer): string;
var
  N: Integer;
begin
  N := Length(ABytes) - AFrom;
  if Odd(N) then
    Dec(N);
  if N <= 0 then
    Exit('');
  Result := TEncoding.Unicode.GetString(ABytes, AFrom, N);
end;

function Utf16Be(const ABytes: TBytes; AFrom: Integer): string;
var
  N: Integer;
begin
  N := Length(ABytes) - AFrom;
  if Odd(N) then
    Dec(N);
  if N <= 0 then
    Exit('');
  Result := TEncoding.BigEndianUnicode.GetString(ABytes, AFrom, N);
end;

function AcpText(const ABytes: TBytes; AFrom: Integer): string;
begin
  if not MbTake(ABytes, AFrom, TEncoding.ANSI.CodePage, 0, Result) then
    Result := '';
end;

function DecodeTextBytes(const ABytes: TBytes; AMode: TTextEncMode;
  out ALabel: string): string;
var
  N, Bom: Integer;
begin
  ALabel := 'UTF-8';
  N := Length(ABytes);
  if N = 0 then
  begin
    ALabel := 'пусто';
    Exit('');
  end;
  Bom := 0;
  if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Bom := 3
  else if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    Bom := 2
  else if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    Bom := 2;

  case AMode of
    temUtf8:
      begin
        if (Bom = 3) or MbTake(ABytes, Bom, 65001, 8, Result) then
        begin
          if Bom = 3 then
            MbTake(ABytes, 3, 65001, 0, Result);
          ALabel := 'UTF-8';
        end
        else
        begin
          MbTake(ABytes, 0, 65001, 0, Result);
          ALabel := 'UTF-8';
        end;
      end;
    temAcp:
      begin
        Result := AcpText(ABytes, 0);
        ALabel := 'ACP';
      end;
    temUtf16:
      begin
        if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
          Result := Utf16Be(ABytes, 2)
        else if Bom = 2 then
          Result := Utf16Le(ABytes, 2)
        else
          Result := Utf16Le(ABytes, 0);
        ALabel := 'UTF-16';
      end;
  else
    if Bom = 3 then
    begin
      MbTake(ABytes, 3, 65001, 0, Result);
      ALabel := 'UTF-8';
    end
    else if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    begin
      Result := Utf16Le(ABytes, 2);
      ALabel := 'UTF-16';
    end
    else if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    begin
      Result := Utf16Be(ABytes, 2);
      ALabel := 'UTF-16';
    end
    else if MbTake(ABytes, 0, 65001, 8, Result) then
      ALabel := 'UTF-8'
    else
    begin
      Result := AcpText(ABytes, 0);
      ALabel := 'ACP';
    end;
  end;
end;

procedure SplitTextLines(const AText: string; out ALines: TArray<string>;
  out AMaxCols: Integer);
var
  SL: TStringList;
  I, C, Cols: Integer;
  Ch: Char;
begin
  AMaxCols := 0;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SetLength(ALines, SL.Count);
    for I := 0 to SL.Count - 1 do
    begin
      ALines[I] := SL[I];
      Cols := 0;
      for C := 1 to Length(ALines[I]) do
      begin
        Ch := ALines[I][C];
        if Ch = #9 then
          Inc(Cols, 4)
        else
          Inc(Cols);
      end;
      if Cols > AMaxCols then
        AMaxCols := Cols;
    end;
  finally
    SL.Free;
  end;
end;

function TextRoleColor(ARole: TTextRole; const AColors: TThemeColors): TAlphaColor;
begin
  case ARole of
    trKeyword: Result := AColors.CodeKeyword;
    trString: Result := AColors.CodeString;
    trComment: Result := AColors.CodeComment;
    trNumber: Result := AColors.CodeNumber;
    trTag: Result := AColors.CodeTag;
  else
    Result := AColors.TextColor;
  end;
  if Result = 0 then
    Result := AColors.TextColor;
end;

function InList(const AWord: string; const AList: array of string): Boolean;
var
  I: Integer;
begin
  for I := Low(AList) to High(AList) do
    if SameText(AWord, AList[I]) then
      Exit(True);
  Result := False;
end;

procedure PushTok(var AToks: TArray<TTextToken>; AStart, ALen: Integer; ARole: TTextRole);
var
  T: TTextToken;
begin
  if (ALen <= 0) or (ARole = trNormal) then
    Exit;
  T.Start := AStart;
  T.Len := ALen;
  T.Role := ARole;
  SetLength(AToks, Length(AToks) + 1);
  AToks[High(AToks)] := T;
end;

function ScanLineStates(const ALines: TArray<string>; ALang: TTextLang): TArray<TLineState>;
var
  I, J: Integer;
  S, T: string;
  St: TLineState;
  Ch: Char;
begin
  SetLength(Result, Length(ALines));
  St := lsNormal;
  for I := 0 to High(ALines) do
  begin
    Result[I] := St;
    S := ALines[I];
    if ALang = tlMd then
    begin
      T := Trim(S);
      if (Length(T) >= 3) and
         (((T[1] = '`') and (T[2] = '`') and (T[3] = '`')) or
          ((T[1] = '~') and (T[2] = '~') and (T[3] = '~'))) then
      begin
        if St = lsFence then
          St := lsNormal
        else if St = lsNormal then
          St := lsFence;
      end;
      Continue;
    end;
    if not (ALang in [tlJs, tlPas, tlXml]) then
      Continue;
    J := 1;
    while J <= Length(S) do
    begin
      if St = lsBlock then
      begin
        if (ALang = tlXml) and (J + 2 <= Length(S)) and (Copy(S, J, 3) = '-->') then
        begin
          St := lsNormal;
          Inc(J, 3);
        end
        else if (ALang = tlJs) and (J < Length(S)) and (S[J] = '*') and (S[J + 1] = '/') then
        begin
          St := lsNormal;
          Inc(J, 2);
        end
        else if (ALang = tlPas) and (S[J] = '}') then
        begin
          St := lsNormal;
          Inc(J);
        end
        else if (ALang = tlPas) and (J < Length(S)) and (S[J] = '*') and (S[J + 1] = ')') then
        begin
          St := lsNormal;
          Inc(J, 2);
        end
        else
          Inc(J);
        Continue;
      end;
      Ch := S[J];
      if (ALang = tlXml) and (J + 3 <= Length(S)) and (Copy(S, J, 4) = '<!--') then
      begin
        St := lsBlock;
        Inc(J, 4);
      end
      else if (ALang = tlJs) and (J < Length(S)) and (Ch = '/') and (S[J + 1] = '*') then
      begin
        St := lsBlock;
        Inc(J, 2);
      end
      else if (ALang = tlJs) and (J < Length(S)) and (Ch = '/') and (S[J + 1] = '/') then
        Break
      else if (ALang = tlPas) and (J < Length(S)) and (Ch = '/') and (S[J + 1] = '/') then
        Break
      else if (ALang = tlPas) and (Ch = '{') then
      begin
        St := lsBlock;
        Inc(J);
      end
      else if (ALang = tlPas) and (J < Length(S)) and (Ch = '(') and (S[J + 1] = '*') then
      begin
        St := lsBlock;
        Inc(J, 2);
      end
      else if (Ch = '''') or (Ch = '"') or ((ALang = tlJs) and (Ch = '`')) then
      begin
        Inc(J);
        while J <= Length(S) do
        begin
          if (ALang = tlPas) and (S[J] = '''') then
          begin
            if (J < Length(S)) and (S[J + 1] = '''') then
              Inc(J, 2)
            else
            begin
              Inc(J);
              Break;
            end;
          end
          else if S[J] = Ch then
          begin
            Inc(J);
            Break;
          end
          else if (S[J] = '\') and (ALang = tlJs) and (J < Length(S)) then
            Inc(J, 2)
          else
            Inc(J);
        end;
      end
      else
        Inc(J);
    end;
  end;
end;

function TokenizeLine(const ALine: string; ALang: TTextLang;
  AEnter: TLineState): TArray<TTextToken>;

  procedure TokJson;
  const
    Lits: array[0..2] of string = ('true', 'false', 'null');
  var
    I, S, P: Integer;
    Prev: Char;
  begin
    I := 1;
    while I <= Length(ALine) do
    begin
      if CharInSet(ALine[I], [' ', #9]) then
      begin
        Inc(I);
        Continue;
      end;
      if ALine[I] = '"' then
      begin
        S := I;
        Inc(I);
        while I <= Length(ALine) do
        begin
          if (ALine[I] = '\') and (I < Length(ALine)) then
            Inc(I, 2)
          else if ALine[I] = '"' then
          begin
            Inc(I);
            Break;
          end
          else
            Inc(I);
        end;
        P := S - 1;
        while (P >= 1) and CharInSet(ALine[P], [' ', #9]) do
          Dec(P);
        if P >= 1 then
          Prev := ALine[P]
        else
          Prev := #0;
        if (Prev = '{') or (Prev = ',') or (Prev = #0) then
          PushTok(Result, S - 1, I - S, trTag)
        else
          PushTok(Result, S - 1, I - S, trString);
        Continue;
      end;
      if CharInSet(ALine[I], ['{', '}', '[', ']', ',']) then
      begin
        PushTok(Result, I - 1, 1, trTag);
        Inc(I);
        Continue;
      end;
      if CharInSet(ALine[I], ['-', '0'..'9']) then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and CharInSet(ALine[I], ['0'..'9', '.', 'e', 'E', '+', '-']) do
          Inc(I);
        PushTok(Result, S - 1, I - S, trNumber);
        Continue;
      end;
      if CharInSet(ALine[I], ['A'..'Z', 'a'..'z']) then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and CharInSet(ALine[I], ['A'..'Z', 'a'..'z']) do
          Inc(I);
        if InList(Copy(ALine, S, I - S), Lits) then
          PushTok(Result, S - 1, I - S, trKeyword);
        Continue;
      end;
      Inc(I);
    end;
  end;

  procedure TokXml;
  var
    I, S, N: Integer;
    InTag: Boolean;
  begin
    I := 1;
    InTag := AEnter = lsBlock;
    if AEnter = lsBlock then
    begin
      S := 1;
      while I + 2 <= Length(ALine) do
      begin
        if Copy(ALine, I, 3) = '-->' then
        begin
          Inc(I, 3);
          Break;
        end;
        Inc(I);
      end;
      if I > Length(ALine) then
        I := Length(ALine) + 1;
      PushTok(Result, S - 1, I - S, trComment);
    end;
    while I <= Length(ALine) do
    begin
      if (I + 3 <= Length(ALine)) and (Copy(ALine, I, 4) = '<!--') then
      begin
        S := I;
        Inc(I, 4);
        while (I + 2 <= Length(ALine)) and (Copy(ALine, I, 3) <> '-->') do
          Inc(I);
        if I + 2 <= Length(ALine) then
          Inc(I, 3)
        else
          I := Length(ALine) + 1;
        PushTok(Result, S - 1, I - S, trComment);
        Continue;
      end;
      if ALine[I] = '<' then
      begin
        InTag := True;
        S := I;
        Inc(I);
        if (I <= Length(ALine)) and (ALine[I] = '/') then
          Inc(I);
        N := I;
        while (I <= Length(ALine)) and not CharInSet(ALine[I], [' ', #9, '>', '/']) do
          Inc(I);
        PushTok(Result, N - 1, I - N, trTag);
        Continue;
      end;
      if InTag and (ALine[I] = '>') then
      begin
        InTag := False;
        Inc(I);
        Continue;
      end;
      if InTag and (ALine[I] = '=') then
      begin
        Inc(I);
        Continue;
      end;
      if InTag and CharInSet(ALine[I], ['A'..'Z', 'a'..'z', ':']) then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and not CharInSet(ALine[I], [' ', #9, '=', '>', '/']) do
          Inc(I);
        PushTok(Result, S - 1, I - S, trKeyword);
        Continue;
      end;
      if CharInSet(ALine[I], ['"', '''']) then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and (ALine[I] <> ALine[S]) do
          Inc(I);
        if I <= Length(ALine) then
          Inc(I);
        PushTok(Result, S - 1, I - S, trString);
        Continue;
      end;
      Inc(I);
    end;
  end;

  procedure TokMd;
  var
    I, S: Integer;
    T: string;
  begin
    if AEnter = lsFence then
    begin
      PushTok(Result, 0, Length(ALine), trComment);
      Exit;
    end;
    T := TrimLeft(ALine);
    if (T <> '') and (T[1] = '#') then
    begin
      PushTok(Result, 0, Length(ALine), trKeyword);
      Exit;
    end;
    I := 1;
    while I <= Length(ALine) do
    begin
      if (I + 2 <= Length(ALine)) and (ALine[I] = '`') and (ALine[I + 1] = '`') and
         (ALine[I + 2] = '`') then
      begin
        PushTok(Result, I - 1, Length(ALine) - I + 1, trComment);
        Exit;
      end;
      if ALine[I] = '`' then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and (ALine[I] <> '`') do
          Inc(I);
        if I <= Length(ALine) then
          Inc(I);
        PushTok(Result, S - 1, I - S, trString);
        Continue;
      end;
      if (I < Length(ALine)) and (ALine[I] = '*') and (ALine[I + 1] = '*') then
      begin
        S := I;
        Inc(I, 2);
        while (I < Length(ALine)) and not ((ALine[I] = '*') and (ALine[I + 1] = '*')) do
          Inc(I);
        if I < Length(ALine) then
          Inc(I, 2);
        PushTok(Result, S - 1, I - S, trKeyword);
        Continue;
      end;
      if ALine[I] = '[' then
      begin
        S := I;
        while (I <= Length(ALine)) and (ALine[I] <> ')') do
          Inc(I);
        if I <= Length(ALine) then
          Inc(I);
        PushTok(Result, S - 1, I - S, trTag);
        Continue;
      end;
      Inc(I);
    end;
  end;

  procedure TokCode(APas: Boolean);
  const
    PasKw: array[0..36] of string = (
      'and', 'array', 'begin', 'case', 'class', 'const', 'div', 'do', 'downto',
      'else', 'end', 'for', 'function', 'if', 'in', 'mod', 'nil', 'not', 'of',
      'or', 'procedure', 'program', 'record', 'repeat', 'set', 'shl', 'shr',
      'string', 'then', 'to', 'type', 'unit', 'until', 'uses', 'var', 'while',
      'with');
    JsKw: array[0..32] of string = (
      'break', 'case', 'catch', 'class', 'const', 'continue', 'default',
      'delete', 'do', 'else', 'export', 'extends', 'false', 'finally', 'for',
      'function', 'if', 'import', 'in', 'let', 'new', 'null', 'return', 'super',
      'switch', 'this', 'throw', 'true', 'try', 'typeof', 'var', 'while', 'yield');
  var
    I, S: Integer;
    W: string;
    Quote: Char;
  begin
    I := 1;
    if AEnter = lsBlock then
    begin
      S := 1;
      while I <= Length(ALine) do
      begin
        if APas and (ALine[I] = '}') then
        begin
          Inc(I);
          Break;
        end;
        if APas and (I < Length(ALine)) and (ALine[I] = '*') and (ALine[I + 1] = ')') then
        begin
          Inc(I, 2);
          Break;
        end;
        if (not APas) and (I < Length(ALine)) and (ALine[I] = '*') and (ALine[I + 1] = '/') then
        begin
          Inc(I, 2);
          Break;
        end;
        Inc(I);
      end;
      PushTok(Result, S - 1, I - S, trComment);
    end;
    while I <= Length(ALine) do
    begin
      if (I < Length(ALine)) and (ALine[I] = '/') and (ALine[I + 1] = '/') then
      begin
        PushTok(Result, I - 1, Length(ALine) - I + 1, trComment);
        Exit;
      end;
      if (not APas) and (I < Length(ALine)) and (ALine[I] = '/') and (ALine[I + 1] = '*') then
      begin
        S := I;
        Inc(I, 2);
        while (I < Length(ALine)) and not ((ALine[I] = '*') and (ALine[I + 1] = '/')) do
          Inc(I);
        if I < Length(ALine) then
          Inc(I, 2);
        PushTok(Result, S - 1, I - S, trComment);
        Continue;
      end;
      if APas and (ALine[I] = '{') then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and (ALine[I] <> '}') do
          Inc(I);
        if I <= Length(ALine) then
          Inc(I);
        PushTok(Result, S - 1, I - S, trComment);
        Continue;
      end;
      if APas and (I < Length(ALine)) and (ALine[I] = '(') and (ALine[I + 1] = '*') then
      begin
        S := I;
        Inc(I, 2);
        while (I < Length(ALine)) and not ((ALine[I] = '*') and (ALine[I + 1] = ')')) do
          Inc(I);
        if I < Length(ALine) then
          Inc(I, 2);
        PushTok(Result, S - 1, I - S, trComment);
        Continue;
      end;
      if (ALine[I] = '''') or (ALine[I] = '"') or ((not APas) and (ALine[I] = '`')) then
      begin
        Quote := ALine[I];
        S := I;
        Inc(I);
        while I <= Length(ALine) do
        begin
          if APas and (ALine[I] = '''') and (I < Length(ALine)) and (ALine[I + 1] = '''') then
            Inc(I, 2)
          else if ALine[I] = Quote then
          begin
            Inc(I);
            Break;
          end
          else if (not APas) and (ALine[I] = '\') and (I < Length(ALine)) then
            Inc(I, 2)
          else
            Inc(I);
        end;
        PushTok(Result, S - 1, I - S, trString);
        Continue;
      end;
      if CharInSet(ALine[I], ['0'..'9']) then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and CharInSet(ALine[I], ['0'..'9', '.', 'x', 'X', 'a'..'f', 'A'..'F']) do
          Inc(I);
        PushTok(Result, S - 1, I - S, trNumber);
        Continue;
      end;
      if CharInSet(ALine[I], ['A'..'Z', 'a'..'z', '_']) or ALine[I].IsLetter then
      begin
        S := I;
        Inc(I);
        while (I <= Length(ALine)) and
          (CharInSet(ALine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or
           ALine[I].IsLetter) do
          Inc(I);
        W := Copy(ALine, S, I - S);
        if APas and InList(W, PasKw) then
          PushTok(Result, S - 1, I - S, trKeyword)
        else if (not APas) and InList(W, JsKw) then
          PushTok(Result, S - 1, I - S, trKeyword);
        Continue;
      end;
      Inc(I);
    end;
  end;

begin
  SetLength(Result, 0);
  if (ALine = '') or (ALang = tlNone) then
    Exit;
  try
    case ALang of
      tlJson: TokJson;
      tlXml: TokXml;
      tlMd: TokMd;
      tlPas: TokCode(True);
      tlJs: TokCode(False);
    end;
  except
    SetLength(Result, 0);
  end;
end;

function RenderTextA4Thumb(const APath: string; AWidth, AHeight: Integer;
  ABitmap: TBitmap): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  N: Integer;
  Ext, Text, Enc, Err: string;
  Sz: Int64;
  Doc: TDocDocument;
begin
  Result := False;
  if (ABitmap = nil) or (APath = '') or not TFile.Exists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if not IsListedTextExt(Ext) then
    Exit;
  try
    Sz := TFile.GetSize(APath);
  except
    Exit;
  end;
  if Sz > TextThumbFileMax then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(TextThumbReadBytes), FS.Size));
      SetLength(Buf, N);
      if N > 0 then
        FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
    Text := DecodeTextBytes(Buf, temAuto, Enc);
    Doc := LoadTextDocumentFromString(Text, APath, Err);
    if Doc = nil then
      Exit;
    try
      Result := RenderLaidDocThumb(Doc, AWidth, AHeight, ABitmap);
    finally
      Doc.Free;
    end;
  except
    Result := False;
  end;
end;

end.
