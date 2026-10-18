unit uLang;

{
  Словарь интерфейса. Ключ в коде — имя в ini (cmd.tiles).
  Секция только группирует строки и в ключ не входит.
  Язык — это lang\<код>.ini рядом с exe, UTF-8.
  Имя языка в файле: lang.name. Список строится по файлам в папке.
}

interface

type
  TLangChoice = record
    Code: string;
    Name: string;
  end;
  TLangNotify = procedure;

function L(const AKey: string): string;
function Lf(const AKey: string; const Args: array of const): string;
{ Славянское склонение: 1 / 2–4 / остальные. В en few и many одинаковые. }
function LCount(N: Integer; const AOne, AFew, AMany: string): string;
procedure SetLanguage(const ACode: string);
procedure SetLanguageChanged(AProc: TLangNotify);
function CurrentLanguage: string;
function LanguageFile(const ACode: string): string;
function AvailableLanguages: TArray<TLangChoice>;
{ system или код файла из двух-восьми латинских букв. Чужое значение становится system. }
function NormalizeLanguage(const ACode: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles, System.IOUtils,
  System.Generics.Collections, System.Generics.Defaults
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

var
  FDict: TDictionary<string, string>;
  FCurrent: string;
  FOnChanged: TLangNotify;

function IsLangCode(const S: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(S) >= 2) and (Length(S) <= 8);
  if not Result then
    Exit;
  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['a'..'z']) then
      Exit(False);
end;

function NormalizeLanguage(const ACode: string): string;
begin
  Result := LowerCase(Trim(ACode));
  if Result = 'system' then
    Exit;
  if not IsLangCode(Result) then
    Result := 'system';
end;

function LangDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'lang');
end;

function HasLangFile(const ACode: string): Boolean;
begin
  Result := IsLangCode(ACode) and
    TFile.Exists(TPath.Combine(LangDir, ACode + '.ini'));
end;

function SystemLanguageCode: string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..15] of Char;
{$ENDIF}
  Langs: TArray<TLangChoice>;
begin
  Result := 'en';
  {$IFDEF MSWINDOWS}
  if GetLocaleInfo(GetUserDefaultUILanguage, LOCALE_SISO639LANGNAME,
       Buf, Length(Buf)) > 0 then
    Result := LowerCase(string(PChar(@Buf[0])));
  {$ENDIF}
  if HasLangFile(Result) then
    Exit;
  if HasLangFile('en') then
    Exit('en');
  if HasLangFile('ru') then
    Exit('ru');
  Langs := AvailableLanguages;
  if Length(Langs) > 0 then
    Result := Langs[0].Code;
end;

function LanguageFile(const ACode: string): string;
var
  Code: string;
begin
  Code := NormalizeLanguage(ACode);
  if Code = 'system' then
    Code := SystemLanguageCode;
  Result := TPath.Combine(LangDir, Code + '.ini');
end;

function ReadLangName(const APath, ACode: string): string;
var
  Ini: TMemIniFile;
begin
  Result := '';
  Ini := TMemIniFile.Create(APath, TEncoding.UTF8);
  try
    Result := Trim(Ini.ReadString('Main', 'lang.name', ''));
    if Result = '' then
      Result := Trim(Ini.ReadString('Settings', 'lang.name', ''));
  finally
    Ini.Free;
  end;
  if Result = '' then
    Result := ACode;
end;

function AvailableLanguages: TArray<TLangChoice>;
var
  Files: TArray<string>;
  I, N: Integer;
  Code: string;
begin
  Result := nil;
  if not TDirectory.Exists(LangDir) then
    Exit;
  Files := TDirectory.GetFiles(LangDir, '*.ini', TSearchOption.soTopDirectoryOnly);
  SetLength(Result, Length(Files));
  N := 0;
  for I := 0 to High(Files) do
  begin
    Code := LowerCase(TPath.GetFileNameWithoutExtension(Files[I]));
    if not IsLangCode(Code) then
      Continue;
    Result[N].Code := Code;
    Result[N].Name := ReadLangName(Files[I], Code);
    Inc(N);
  end;
  SetLength(Result, N);
  if N > 1 then
    TArray.Sort<TLangChoice>(Result, TComparer<TLangChoice>.Construct(
      function(const L, R: TLangChoice): Integer
      begin
        Result := CompareText(L.Name, R.Name);
      end));
end;

function TryLoad(const ACode: string): Boolean;
var
  Ini: TMemIniFile;
  Sections, Keys: TStringList;
  S, K: string;
  I, J: Integer;
  Path: string;
begin
  Path := LanguageFile(ACode);
  Result := TFile.Exists(Path);
  if not Result then
    Exit;
  FDict.Clear;
  Ini := TMemIniFile.Create(Path, TEncoding.UTF8);
  Sections := TStringList.Create;
  Keys := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    for I := 0 to Sections.Count - 1 do
    begin
      S := Sections[I];
      Keys.Clear;
      Ini.ReadSection(S, Keys);
      for J := 0 to Keys.Count - 1 do
      begin
        K := Keys[J];
        FDict.AddOrSetValue(K, Ini.ReadString(S, K, ''));
      end;
    end;
    FCurrent := ACode;
  finally
    Keys.Free;
    Sections.Free;
    Ini.Free;
  end;
end;

procedure NotifyLanguage;
begin
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure SetLanguageChanged(AProc: TLangNotify);
begin
  FOnChanged := AProc;
end;

procedure SetLanguage(const ACode: string);
var
  Want: string;
  Langs: TArray<TLangChoice>;
begin
  Want := NormalizeLanguage(ACode);
  if Want = 'system' then
    Want := SystemLanguageCode;
  if TryLoad(Want) then
  begin
    NotifyLanguage;
    Exit;
  end;
  if (Want <> 'en') and TryLoad('en') then
  begin
    NotifyLanguage;
    Exit;
  end;
  if (Want <> 'ru') and TryLoad('ru') then
  begin
    NotifyLanguage;
    Exit;
  end;
  Langs := AvailableLanguages;
  if (Length(Langs) > 0) and (Langs[0].Code <> Want) and TryLoad(Langs[0].Code) then
  begin
    NotifyLanguage;
    Exit;
  end;
  FDict.Clear;
  FCurrent := Want;
  NotifyLanguage;
end;

function CurrentLanguage: string;
begin
  Result := FCurrent;
end;

function L(const AKey: string): string;
begin
  if (FDict = nil) or not FDict.TryGetValue(AKey, Result) then
    Result := AKey;
end;

function Lf(const AKey: string; const Args: array of const): string;
begin
  Result := L(AKey);
  try
    Result := Format(Result, Args);
  except
  end;
end;

function LCount(N: Integer; const AOne, AFew, AMany: string): string;
var
  N10, N100, AbsN: Integer;
  Key: string;
begin
  AbsN := Abs(N);
  N10 := AbsN mod 10;
  N100 := AbsN mod 100;
  if (N10 = 1) and (N100 <> 11) then
    Key := AOne
  else if (N10 >= 2) and (N10 <= 4) and ((N100 < 12) or (N100 > 14)) then
    Key := AFew
  else
    Key := AMany;
  Result := Lf(Key, [N]);
end;

initialization
  FDict := TDictionary<string, string>.Create;
  FCurrent := 'ru';

finalization
  FreeAndNil(FDict);

end.
