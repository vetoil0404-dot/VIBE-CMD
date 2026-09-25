unit uMultiRename;

{
  Движок группового переименования в стиле Total Commander (Ctrl+M):
  маски [N]/[E]/[C]/даты, поиск-замена, регистр, предпросмотр коллизий.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  uFileModel;

type
  TRenameCaseMode = (rcKeep, rcLower, rcUpper, rcFirstUpper);

  TRenameItem = record
    OldName: string;
    OldPath: string;
    NewName: string;
    IsDirectory: Boolean;
    Modified: TDateTime;
    Collision: Boolean;
    Skipped: Boolean;
  end;

  TMultiRenameEngine = class
  private
    FItems: TArray<TRenameItem>;
    function SliceText(const S, Spec: string): string;
    function ApplyCaseWord(const S, Mode: string): string;
    function ExpandMask(const AMask, AName, AExt, APath: string; AIndex: Integer;
      const ATime: TDateTime): string;
    function ExpandToken(const ATok, AName, AExt, APath: string; AIndex: Integer;
      const ATime: TDateTime): string;
    function ApplyFindReplace(const S: string): string;
    function ApplyCaseMode(const S: string): string;
    function SanitizeName(const S: string): string;
  public
    NameMask: string;
    ExtMask: string;
    FindText: string;
    ReplaceText: string;
    CaseSensitive: Boolean;
    UseRegex: Boolean;
    CounterStart: Integer;
    CounterStep: Integer;
    CounterDigits: Integer;
    CaseMode: TRenameCaseMode;
    constructor Create;
    procedure LoadEntries(const AEntries: TArray<TFileEntry>);
    procedure RebuildPreview;
    function CollisionCount: Integer;
    function ApplyRenames: Integer;
    property Items: TArray<TRenameItem> read FItems;
  end;

implementation

uses
  System.IOUtils, System.StrUtils, System.DateUtils, uFileOps;

function IsBadNameChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['<', '>', ':', '"', '/', '\', '|', '?', '*']);
end;

constructor TMultiRenameEngine.Create;
begin
  inherited Create;
  NameMask := '[N]';
  ExtMask := '[E]';
  CounterStart := 1;
  CounterStep := 1;
  CounterDigits := 3;
  CaseMode := rcKeep;
end;

procedure TMultiRenameEngine.LoadEntries(const AEntries: TArray<TFileEntry>);
var
  I, N: Integer;
begin
  SetLength(FItems, Length(AEntries));
  N := 0;
  for I := 0 to High(AEntries) do
  begin
    if (AEntries[I].FullPath = '') or (AEntries[I].Name = '') or
       (AEntries[I].Name = '..') then
      Continue;
    FItems[N].OldName := AEntries[I].Name;
    FItems[N].OldPath := AEntries[I].FullPath;
    FItems[N].NewName := AEntries[I].Name;
    FItems[N].IsDirectory := AEntries[I].IsDirectory;
    FItems[N].Modified := AEntries[I].Modified;
    FItems[N].Collision := False;
    FItems[N].Skipped := False;
    Inc(N);
  end;
  SetLength(FItems, N);
  RebuildPreview;
end;

function TMultiRenameEngine.ApplyCaseWord(const S, Mode: string): string;
var
  M: string;
begin
  M := LowerCase(Mode);
  if M = 'lower' then
    Result := AnsiLowerCase(S)
  else if M = 'upper' then
    Result := AnsiUpperCase(S)
  else if (M = 'firstupper') or (M = 'first') then
  begin
    Result := AnsiLowerCase(S);
    if Result <> '' then
      Result[1] := UpCase(Result[1]);
  end
  else
    Result := S;
end;

function TMultiRenameEngine.SliceText(const S, Spec: string): string;
var
  Body, Mode: string;
  P, FromIdx, ToIdx, LenN, Comma: Integer;
begin
  Body := Trim(Spec);
  Mode := '';
  if EndsText('lower', LowerCase(Body)) and (Length(Body) >= 5) then
  begin
    Mode := 'lower';
    if LowerCase(Body) = 'lower' then
      Exit(ApplyCaseWord(S, Mode));
    SetLength(Body, Length(Body) - 5);
  end
  else if EndsText('upper', LowerCase(Body)) and (Length(Body) >= 5) and
    not EndsText('firstupper', LowerCase(Body)) then
  begin
    Mode := 'upper';
    if LowerCase(Body) = 'upper' then
      Exit(ApplyCaseWord(S, Mode));
    SetLength(Body, Length(Body) - 5);
  end
  else if EndsText('firstupper', LowerCase(Body)) then
  begin
    Mode := 'firstupper';
    if LowerCase(Body) = 'firstupper' then
      Exit(ApplyCaseWord(S, Mode));
    SetLength(Body, Length(Body) - 10);
  end;
  Body := Trim(Body);
  if Body = '' then
    Result := S
  else
  begin
    Comma := Pos(',', Body);
    P := Pos('-', Body);
    if Comma > 0 then
    begin
      FromIdx := StrToIntDef(Copy(Body, 1, Comma - 1), 1);
      LenN := StrToIntDef(Copy(Body, Comma + 1, MaxInt), Length(S));
      if FromIdx < 1 then FromIdx := 1;
      Result := Copy(S, FromIdx, LenN);
    end
    else if P > 0 then
    begin
      FromIdx := StrToIntDef(Copy(Body, 1, P - 1), 1);
      if P = Length(Body) then
        ToIdx := Length(S)
      else
        ToIdx := StrToIntDef(Copy(Body, P + 1, MaxInt), Length(S));
      if FromIdx < 1 then FromIdx := 1;
      if ToIdx < FromIdx then ToIdx := FromIdx;
      Result := Copy(S, FromIdx, ToIdx - FromIdx + 1);
    end
    else
    begin
      FromIdx := StrToIntDef(Body, 1);
      if FromIdx < 1 then FromIdx := 1;
      Result := Copy(S, FromIdx, MaxInt);
    end;
  end;
  if Mode <> '' then
    Result := ApplyCaseWord(Result, Mode);
end;

function ParentFolderName(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(ExtractFilePath(APath)));
end;

function TMultiRenameEngine.ExpandToken(const ATok, AName, AExt, APath: string;
  AIndex: Integer; const ATime: TDateTime): string;
var
  Spec: string;
  C: Char;
  Start, Step, Digits, Value: Integer;
  Parts: TArray<string>;
begin
  Result := '';
  if ATok = '' then
    Exit;
  if ATok = 'm' then
    Exit(FormatDateTime('nn', ATime));
  if ATok = 's' then
    Exit(FormatDateTime('ss', ATime));
  if ATok = 'h' then
    Exit(FormatDateTime('hh', ATime));
  if ATok = 'y' then
    Exit(FormatDateTime('yy', ATime));
  C := UpCase(ATok[1]);
  Spec := Copy(ATok, 2, MaxInt);
  case C of
    'N':
      Result := SliceText(AName, Spec);
    'E':
      Result := SliceText(AExt, Spec);
    'P':
      Result := SliceText(ParentFolderName(APath), Spec);
    'C':
      begin
        Start := CounterStart;
        Step := CounterStep;
        Digits := CounterDigits;
        if (Spec <> '') and (Spec[1] = ':') then
        begin
          Parts := Spec.Substring(1).Split([':']);
          if Length(Parts) > 0 then Start := StrToIntDef(Parts[0], Start);
          if Length(Parts) > 1 then Step := StrToIntDef(Parts[1], Step);
          if Length(Parts) > 2 then Digits := StrToIntDef(Parts[2], Digits);
        end;
        Value := Start + AIndex * Step;
        if Digits < 1 then
          Result := IntToStr(Value)
        else
          Result := Format('%.*d', [Digits, Value]);
      end;
    'Y':
      Result := FormatDateTime('yyyy', ATime);
    'M':
      Result := FormatDateTime('mm', ATime);
    'D':
      Result := FormatDateTime('dd', ATime);
    'H':
      Result := FormatDateTime('hh', ATime);
    'S':
      Result := FormatDateTime('ss', ATime);
  else
    Result := '[' + ATok + ']';
  end;
end;

function TMultiRenameEngine.ExpandMask(const AMask, AName, AExt, APath: string;
  AIndex: Integer; const ATime: TDateTime): string;
var
  I, Close: Integer;
  Tok: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AMask) do
  begin
    if AMask[I] = '[' then
    begin
      Close := Pos(']', AMask, I + 1);
      if Close > I then
      begin
        Tok := Copy(AMask, I + 1, Close - I - 1);
        Result := Result + ExpandToken(Tok, AName, AExt, APath, AIndex, ATime);
        I := Close + 1;
        Continue;
      end;
    end;
    Result := Result + AMask[I];
    Inc(I);
  end;
end;

function TMultiRenameEngine.ApplyFindReplace(const S: string): string;
var
  Flags: TReplaceFlags;
begin
  Result := S;
  if FindText = '' then
    Exit;
  if UseRegex then
  try
    if CaseSensitive then
      Result := TRegEx.Replace(S, FindText, ReplaceText)
    else
      Result := TRegEx.Replace(S, FindText, ReplaceText, [roIgnoreCase]);
  except
    Result := S;
  end
  else
  begin
    Flags := [rfReplaceAll];
    if not CaseSensitive then
      Include(Flags, rfIgnoreCase);
    Result := StringReplace(S, FindText, ReplaceText, Flags);
  end;
end;

function TMultiRenameEngine.ApplyCaseMode(const S: string): string;
var
  Base, Ext: string;
begin
  Result := S;
  case CaseMode of
    rcLower: Result := AnsiLowerCase(S);
    rcUpper: Result := AnsiUpperCase(S);
    rcFirstUpper:
      begin
        Ext := ExtractFileExt(S);
        Base := ChangeFileExt(S, '');
        Base := AnsiLowerCase(Base);
        if Base <> '' then
          Base[1] := UpCase(Base[1]);
        Result := Base + Ext;
      end;
  end;
end;

function TMultiRenameEngine.SanitizeName(const S: string): string;
var
  I: Integer;
begin
  Result := Trim(S);
  for I := 1 to Length(Result) do
    if IsBadNameChar(Result[I]) then
      Result[I] := '_';
  while StartsText('.', Result) and (Length(Result) > 1) and (Result <> '.') do
    Break;
end;

procedure TMultiRenameEngine.RebuildPreview;
var
  I, J: Integer;
  NameOnly, ExtOnly, Built: string;
  Seen: TDictionary<string, Integer>;
  Key, Folder, Dest: string;
begin
  Seen := TDictionary<string, Integer>.Create;
  try
    for I := 0 to High(FItems) do
    begin
      NameOnly := ChangeFileExt(FItems[I].OldName, '');
      ExtOnly := ExtractFileExt(FItems[I].OldName);
      if (ExtOnly <> '') and (ExtOnly[1] = '.') then
        Delete(ExtOnly, 1, 1);
      { 1–2. Найти и заменить по исходному имени, затем подставить как [N]. }
      NameOnly := ApplyFindReplace(NameOnly);
      { 3–4. Маска имени: [N], [C], даты и остальные теги. }
      Built := ExpandMask(NameMask, NameOnly, ExtOnly, FItems[I].OldPath, I,
        FItems[I].Modified);
      if Trim(ExtMask) <> '' then
      begin
        ExtOnly := ExpandMask(ExtMask, NameOnly, ExtOnly, FItems[I].OldPath, I,
          FItems[I].Modified);
        if ExtOnly <> '' then
          Built := Built + '.' + ExtOnly;
      end;
      Built := ApplyCaseMode(Built);
      Built := SanitizeName(Built);
      FItems[I].NewName := Built;
      FItems[I].Collision := (Built = '') or (Built = '.') or (Built = '..');
      FItems[I].Skipped := False;
    end;

    for I := 0 to High(FItems) do
    begin
      if FItems[I].Collision then
        Continue;
      Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(FItems[I].OldPath));
      Key := LowerCase(Folder + '\' + FItems[I].NewName);
      if Seen.ContainsKey(Key) then
      begin
        J := Seen[Key];
        FItems[I].Collision := True;
        FItems[J].Collision := True;
      end
      else
        Seen.Add(Key, I);
    end;

    for I := 0 to High(FItems) do
    begin
      if FItems[I].Collision then
        Continue;
      if SameText(FItems[I].NewName, FItems[I].OldName) then
        Continue;
      Dest := TPath.Combine(ExtractFilePath(FItems[I].OldPath), FItems[I].NewName);
      if (not SameText(Dest, FItems[I].OldPath)) and
         (TFile.Exists(Dest) or TDirectory.Exists(Dest)) then
      begin
        if not Seen.ContainsKey(LowerCase(ExcludeTrailingPathDelimiter(
             ExtractFilePath(FItems[I].OldPath)) + '\' + FItems[I].OldName)) then
          FItems[I].Collision := True;
        { dest exists: collision unless dest is another item being renamed away }
        var Taken := False;
        for J := 0 to High(FItems) do
          if (J <> I) and SameText(FItems[J].OldPath, Dest) then
          begin
            Taken := True;
            Break;
          end;
        if not Taken then
          FItems[I].Collision := True
        else if SameText(FItems[J].NewName, FItems[I].NewName) then
          FItems[I].Collision := True;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

function TMultiRenameEngine.CollisionCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FItems) do
    if FItems[I].Collision then
      Inc(Result);
end;

function TMultiRenameEngine.ApplyRenames: Integer;
var
  I: Integer;
  Folder, TempName, Dummy, FinalPath: string;
  Temped: TArray<Boolean>;
begin
  Result := 0;
  RebuildPreview;
  SetLength(Temped, Length(FItems));
  for I := 0 to High(FItems) do
  begin
    Temped[I] := False;
    if FItems[I].Collision or SameText(FItems[I].NewName, FItems[I].OldName) then
      Continue;
    Folder := ExtractFilePath(FItems[I].OldPath);
    TempName := Format('.__vibe_%d_%d.tmp', [I, Random(MaxInt)]);
    if not RenamePath(FItems[I].OldPath, TempName, Dummy) then
    begin
      FItems[I].Skipped := True;
      Continue;
    end;
    FItems[I].OldPath := Dummy;
    Temped[I] := True;
  end;
  for I := 0 to High(FItems) do
  begin
    if FItems[I].Collision or FItems[I].Skipped or not Temped[I] then
      Continue;
    if not RenamePath(FItems[I].OldPath, FItems[I].NewName, FinalPath) then
    begin
      FItems[I].Skipped := True;
      Continue;
    end;
    FItems[I].OldPath := FinalPath;
    FItems[I].OldName := FItems[I].NewName;
    Inc(Result);
  end;
end;

end.
