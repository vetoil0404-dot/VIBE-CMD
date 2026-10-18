unit uPeInfo;

{
  Разбор PE с диска для QV. Файл не запускается.
  LoadLibrary без флагов, CreateProcess и ShellExecute здесь не используются.
  Иконку в TBitmap кладёт только UI-поток.
}

interface

uses
  System.SysUtils, FMX.Graphics;

type
  TPeDllRef = record
    Name: string;
    Missing: Boolean;
  end;

  TPeInfo = record
    Ok: Boolean;
    Fail: string;
    Kind: string;
    Arch: string;
    Machine: string;
    Subsystem: string;
    IsDotNet: Boolean;
    Elevation: string;
    Signed: Integer;
    Publisher: string;
    Description: string;
    Product: string;
    FileVer: string;
    ProdVer: string;
    Company: string;
    Copyright: string;
    Original: string;
    Built: string;
    NameMismatch: Boolean;
    Imports: TArray<TPeDllRef>;
    ImportMore: Integer;
    ExportNames: TArray<string>;
    ExportMore: Integer;
    IconCount: Integer;
    ManifestCount: Integer;
    VersionCount: Integer;
    StringCount: Integer;
    Strings: TArray<string>;
    IsDll: Boolean;
  end;

function ReadPeInfo(const APath: string): TPeInfo;
procedure LoadPeIcon(const APath: string; ABmp: FMX.Graphics.TBitmap);

implementation

uses
  System.Classes, System.IOUtils, System.DateUtils, System.StrUtils, System.Math,
  Winapi.Windows;

const
  IMG_DOS = $5A4D;
  IMG_NT = $00004550;
  IMG_NT32 = $10B;
  IMG_NT64 = $20B;
  IMG_DLL = $2000;
  DIR_EXPORT = 0;
  DIR_IMPORT = 1;
  DIR_RESOURCE = 2;
  DIR_CLR = 14;
  RT_ICON_ID = 3;
  RT_STRING_ID = 6;
  RT_GROUP_ICON_ID = 14;
  RT_VERSION_ID = 16;
  RT_MANIFEST_ID = 24;
  TRUST_E_NOSIGNATURE = $800B0100;
  TRUST_E_SUBJECT_FORM_UNKNOWN = $800B0003;
  WTD_UI_NONE = 2;
  WTD_REVOKE_NONE = 0;
  WTD_CHOICE_FILE = 1;
  WTD_STATEACTION_VERIFY = 1;
  WTD_STATEACTION_CLOSE = 2;
  WTD_CACHE_ONLY_URL_RETRIEVAL = $00001000;

type
  TPeSec = record
    VA: DWORD;
    Virt: DWORD;
    Raw: DWORD;
    RawSize: DWORD;
  end;

  TWinTrustFileInfo = record
    cbStruct: DWORD;
    pcwszFilePath: PWideChar;
    hFile: THandle;
    pgKnownSubject: PGUID;
  end;

  TWinTrustData = record
    cbStruct: DWORD;
    pPolicyCallbackData: Pointer;
    pSIPClientData: Pointer;
    dwUIChoice: DWORD;
    fdwRevocationChecks: DWORD;
    dwUnionChoice: DWORD;
    pFile: Pointer;
    dwStateAction: DWORD;
    hWVTStateData: THandle;
    pwszURLReference: PWideChar;
    dwProvFlags: DWORD;
    dwUIContext: DWORD;
  end;

function WinVerifyTrust(hwnd: HWND; pgActionID: PGUID; pWVTData: Pointer): LONG; stdcall;
  external 'wintrust.dll' name 'WinVerifyTrust';
function CryptQueryObject(dwObjectType: DWORD; pvObject: Pointer;
  dwExpectedContentTypeFlags, dwExpectedFormatTypeFlags, dwFlags: DWORD;
  pdwMsgAndCertEncodingType, pdwContentType, pdwFormatType: PDWORD;
  phCertStore: PPointer; phMsg: PPointer; ppvContext: PPointer): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptQueryObject';
function CertEnumCertificatesInStore(hCertStore, pPrevCertContext: Pointer): Pointer; stdcall;
  external 'crypt32.dll' name 'CertEnumCertificatesInStore';
function CertCloseStore(hCertStore: Pointer; dwFlags: DWORD): BOOL; stdcall;
  external 'crypt32.dll' name 'CertCloseStore';
function CertGetNameStringW(pCertContext: Pointer; dwType, dwFlags: DWORD;
  pvTypePara: Pointer; pszNameString: PWideChar; cchNameString: DWORD): DWORD; stdcall;
  external 'crypt32.dll' name 'CertGetNameStringW';
function PrivateExtractIconsW(szFileName: PWideChar; nIconIndex, cxIcon, cyIcon: Integer;
  phicon: Pointer; piconid: Pointer; nIcons, flags: UINT): UINT; stdcall;
  external 'user32.dll' name 'PrivateExtractIconsW';
function GetSystemWow64DirectoryW(lpBuffer: PWideChar; uSize: UINT): UINT; stdcall;
  external 'kernel32.dll' name 'GetSystemWow64DirectoryW';

function RvaToOff(const Secs: TArray<TPeSec>; Rva: DWORD): Int64;
var
  I: Integer;
  Span: DWORD;
begin
  Result := -1;
  if Rva = 0 then
    Exit;
  for I := 0 to High(Secs) do
  begin
    Span := Secs[I].Virt;
    if Secs[I].RawSize > Span then
      Span := Secs[I].RawSize;
    if (Rva >= Secs[I].VA) and (Rva < Secs[I].VA + Span) then
    begin
      Result := Int64(Secs[I].Raw) + (Rva - Secs[I].VA);
      Exit;
    end;
  end;
end;

function ReadCString(FS: TStream; Off: Int64; MaxLen: Integer): string;
var
  B: Byte;
  Bytes: TBytes;
  N: Integer;
begin
  Result := '';
  if (Off < 0) or (Off >= FS.Size) or (MaxLen < 1) then
    Exit;
  SetLength(Bytes, MaxLen);
  N := 0;
  FS.Position := Off;
  while (N < MaxLen) and (FS.Position < FS.Size) do
  begin
    if FS.Read(B, 1) <> 1 then
      Break;
    if B = 0 then
      Break;
    Bytes[N] := B;
    Inc(N);
  end;
  if N = 0 then
    Exit;
  SetLength(Bytes, N);
  Result := TEncoding.ANSI.GetString(Bytes);
end;

function ReadU16(FS: TStream): Word;
begin
  FS.ReadBuffer(Result, 2);
end;

function ReadU32(FS: TStream): DWORD;
begin
  FS.ReadBuffer(Result, 4);
end;

procedure AddImport(var Info: TPeInfo; const AName: string);
var
  I, N: Integer;
begin
  if AName = '' then
    Exit;
  for I := 0 to High(Info.Imports) do
    if SameText(Info.Imports[I].Name, AName) then
      Exit;
  if Length(Info.Imports) >= 24 then
  begin
    Inc(Info.ImportMore);
    Exit;
  end;
  N := Length(Info.Imports);
  SetLength(Info.Imports, N + 1);
  Info.Imports[N].Name := AName;
  Info.Imports[N].Missing := False;
end;

function DllOnDisk(const AExe, ADll: string): Boolean;
var
  Dir, Sys32, Wow, PathEnv, Part: string;
  Parts: TArray<string>;
begin
  Result := True;
  if (ADll = '') or StartsText('api-ms-', ADll) or StartsText('ext-ms-', ADll) then
    Exit;
  Dir := IncludeTrailingPathDelimiter(ExtractFilePath(AExe));
  if TFile.Exists(Dir + ADll) then
    Exit;
  SetLength(Sys32, MAX_PATH);
  SetLength(Sys32, GetSystemDirectory(PChar(Sys32), MAX_PATH));
  if (Sys32 <> '') and TFile.Exists(IncludeTrailingPathDelimiter(Sys32) + ADll) then
    Exit;
  SetLength(Wow, MAX_PATH);
  SetLength(Wow, GetSystemWow64DirectoryW(PChar(Wow), MAX_PATH));
  if (Wow <> '') and TFile.Exists(IncludeTrailingPathDelimiter(Wow) + ADll) then
    Exit;
  PathEnv := GetEnvironmentVariable('PATH');
  Parts := PathEnv.Split([';']);
  for Part in Parts do
    if (Part <> '') and TFile.Exists(IncludeTrailingPathDelimiter(Part) + ADll) then
      Exit;
  Result := False;
end;

procedure MarkMissing(const APath: string; var Info: TPeInfo);
var
  I: Integer;
begin
  for I := 0 to High(Info.Imports) do
    Info.Imports[I].Missing := not DllOnDisk(APath, Info.Imports[I].Name);
end;

procedure ReadVersion(const APath: string; var Info: TPeInfo);
var
  Size, Handle, Len: DWORD;
  Buf: TBytes;
  Trans, P: Pointer;
  Lang: string;
  I: Integer;
  Keys: array[0..6] of string;
  Vals: array[0..6] of string;
begin
  Size := GetFileVersionInfoSize(PChar(APath), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(APath), 0, Size, @Buf[0]) then
    Exit;
  Trans := nil;
  Len := 0;
  if not VerQueryValue(@Buf[0], '\VarFileInfo\Translation', Trans, Len) or (Len < 4) then
    Exit;
  Lang := Format('%.4x%.4x', [PWord(Trans)^, PWord(PByte(Trans) + 2)^]);
  Keys[0] := 'FileDescription';
  Keys[1] := 'ProductName';
  Keys[2] := 'FileVersion';
  Keys[3] := 'ProductVersion';
  Keys[4] := 'CompanyName';
  Keys[5] := 'LegalCopyright';
  Keys[6] := 'OriginalFilename';
  for I := 0 to 6 do
  begin
    P := nil;
    Len := 0;
    Vals[I] := '';
    if VerQueryValue(@Buf[0], PChar('\StringFileInfo\' + Lang + '\' + Keys[I]), P, Len) and
       (P <> nil) and (Len > 1) then
      Vals[I] := Trim(string(PChar(P)));
  end;
  Info.Description := Vals[0];
  Info.Product := Vals[1];
  Info.FileVer := Vals[2];
  Info.ProdVer := Vals[3];
  Info.Company := Vals[4];
  Info.Copyright := Vals[5];
  Info.Original := Vals[6];
  if Info.Original <> '' then
    Info.NameMismatch := not SameText(ExtractFileName(Info.Original), ExtractFileName(APath));
end;

procedure ReadSignature(const APath: string; var Info: TPeInfo);
const
  Action: TGUID = '{00AAC56B-CD44-11D0-8CC2-00C04FC295EE}';
var
  FileInfo: TWinTrustFileInfo;
  Data: TWinTrustData;
  Status: LONG;
  Store, Cert: Pointer;
  Name: array[0..255] of Char;
begin
  Info.Signed := 0;
  Info.Publisher := '';
  FillChar(FileInfo, SizeOf(FileInfo), 0);
  FileInfo.cbStruct := SizeOf(FileInfo);
  FileInfo.pcwszFilePath := PChar(APath);
  FillChar(Data, SizeOf(Data), 0);
  Data.cbStruct := SizeOf(Data);
  Data.dwUIChoice := WTD_UI_NONE;
  Data.fdwRevocationChecks := WTD_REVOKE_NONE;
  Data.dwUnionChoice := WTD_CHOICE_FILE;
  Data.pFile := @FileInfo;
  Data.dwStateAction := WTD_STATEACTION_VERIFY;
  Data.dwProvFlags := WTD_CACHE_ONLY_URL_RETRIEVAL;
  Status := WinVerifyTrust(0, @Action, @Data);
  Data.dwStateAction := WTD_STATEACTION_CLOSE;
  WinVerifyTrust(0, @Action, @Data);
  if Status = 0 then
    Info.Signed := 1
  else if (DWORD(Status) = TRUST_E_NOSIGNATURE) or
          (DWORD(Status) = TRUST_E_SUBJECT_FORM_UNKNOWN) then
    Info.Signed := 0
  else
    Info.Signed := 2;
  if Info.Signed <> 1 then
    Exit;
  Store := nil;
  if not CryptQueryObject(1, PChar(APath), $400, 2, 0, nil, nil, nil, @Store, nil, nil) then
    Exit;
  try
    Cert := CertEnumCertificatesInStore(Store, nil);
    if Cert = nil then
      Exit;
    if CertGetNameStringW(Cert, 4, 0, nil, Name, Length(Name)) > 1 then
      Info.Publisher := Trim(string(Name));
  finally
    CertCloseStore(Store, 0);
  end;
end;

procedure ReadResources(FS: TStream; const Secs: TArray<TPeSec>; ResRva: DWORD;
  var Info: TPeInfo);
var
  Root: Int64;

  function Off(Rel: DWORD): Int64;
  begin
    Result := Root + Rel;
  end;

  procedure Walk(Rel: DWORD; Depth, TypeId: Integer; Want: Integer; var Count: Integer;
    TakeManifest, TakeStrings: Boolean);
  var
    Pos0: Int64;
    Named, Ids, I: Integer;
    NameOrId, EntryOff, Child, DataRva, DataSize: DWORD;
    IsName, IsDir: Boolean;
    Id: Integer;
    Blob: TBytes;
    Text, Level: string;
    P, NStr: Integer;
    SLen: Word;
    S: string;
  begin
    if (Depth > 4) or (Count > 64) then
      Exit;
    Pos0 := Off(Rel);
    if (Pos0 < 0) or (Pos0 + 16 > FS.Size) then
      Exit;
    FS.Position := Pos0 + 12;
    Named := ReadU16(FS);
    Ids := ReadU16(FS);
    for I := 0 to Named + Ids - 1 do
    begin
      FS.Position := Pos0 + 16 + I * 8;
      if FS.Position + 8 > FS.Size then
        Exit;
      NameOrId := ReadU32(FS);
      EntryOff := ReadU32(FS);
      IsName := (NameOrId and $80000000) <> 0;
      IsDir := (EntryOff and $80000000) <> 0;
      Id := Integer(NameOrId and $FFFF);
      Child := EntryOff and $7FFFFFFF;
      if Depth = 0 then
      begin
        if IsName then
          Continue;
        if (Id = RT_GROUP_ICON_ID) or ((Id = RT_ICON_ID) and (Want = RT_ICON_ID)) then
          Walk(Child, Depth + 1, Id, Id, Info.IconCount, False, False)
        else if Id = RT_MANIFEST_ID then
          Walk(Child, Depth + 1, Id, Id, Info.ManifestCount, True, False)
        else if Id = RT_VERSION_ID then
          Walk(Child, Depth + 1, Id, Id, Info.VersionCount, False, False)
        else if Id = RT_STRING_ID then
          Walk(Child, Depth + 1, Id, Id, Info.StringCount, False, True);
      end
      else if IsDir then
        Walk(Child, Depth + 1, TypeId, Want, Count, TakeManifest, TakeStrings)
      else
      begin
        Inc(Count);
        FS.Position := Off(Child);
        if FS.Position + 16 > FS.Size then
          Exit;
        DataRva := ReadU32(FS);
        DataSize := ReadU32(FS);
        if (DataSize = 0) or (DataSize > 256 * 1024) then
          Continue;
        Pos0 := RvaToOff(Secs, DataRva);
        if (Pos0 < 0) or (Pos0 + DataSize > FS.Size) then
          Continue;
        if TakeManifest and (Info.Elevation = '') then
        begin
          SetLength(Blob, DataSize);
          FS.Position := Pos0;
          FS.ReadBuffer(Blob[0], DataSize);
          Text := LowerCase(TEncoding.ANSI.GetString(Blob));
          P := Pos('requestedexecutionlevel', Text);
          if P > 0 then
          begin
            Level := Copy(Text, P, 180);
            if Pos('requireadministrator', Level) > 0 then
              Info.Elevation := 'требует администратора'
            else if Pos('highestavailable', Level) > 0 then
              Info.Elevation := 'просит повышение';
          end;
        end;
        if TakeStrings and (Length(Info.Strings) < 12) then
        begin
          SetLength(Blob, DataSize);
          FS.Position := Pos0;
          FS.ReadBuffer(Blob[0], DataSize);
          P := 0;
          for NStr := 0 to 15 do
          begin
            if P + 2 > Length(Blob) then
              Break;
            SLen := PWord(@Blob[P])^;
            Inc(P, 2);
            if (SLen = 0) or (P + SLen * 2 > Length(Blob)) then
            begin
              Inc(P, SLen * 2);
              Continue;
            end;
            S := Trim(TEncoding.Unicode.GetString(Blob, P, SLen * 2));
            Inc(P, SLen * 2);
            if Length(S) < 2 then
              Continue;
            if Length(S) > 80 then
              S := Copy(S, 1, 80);
            if Length(Info.Strings) >= 12 then
              Break;
            SetLength(Info.Strings, Length(Info.Strings) + 1);
            Info.Strings[High(Info.Strings)] := S;
          end;
        end;
        FS.Position := Pos0;
      end;
    end;
  end;

begin
  Root := RvaToOff(Secs, ResRva);
  if Root < 0 then
    Exit;
  Walk(0, 0, 0, 0, Info.IconCount, False, False);
  if Info.IconCount = 0 then
  begin
    { повтор для отдельных иконок, если группы нет }
  end;
end;

procedure ReadImports(FS: TStream; const Secs: TArray<TPeSec>; Rva: DWORD; var Info: TPeInfo);
var
  Off: Int64;
  NameRva: DWORD;
  Guard: Integer;
  S: string;
begin
  Off := RvaToOff(Secs, Rva);
  if Off < 0 then
    Exit;
  Guard := 0;
  while (Off + 20 <= FS.Size) and (Guard < 256) do
  begin
    FS.Position := Off + 12;
    NameRva := ReadU32(FS);
    if NameRva = 0 then
      Break;
    S := ReadCString(FS, RvaToOff(Secs, NameRva), 128);
    if SameText(S, 'mscoree.dll') then
      Info.IsDotNet := True;
    AddImport(Info, S);
    Inc(Off, 20);
    Inc(Guard);
  end;
end;

procedure ReadExports(FS: TStream; const Secs: TArray<TPeSec>; Rva: DWORD; var Info: TPeInfo);
var
  Off, NamesOff: Int64;
  Count, I, Got: Integer;
  NameRva: DWORD;
  S: string;
begin
  Off := RvaToOff(Secs, Rva);
  if (Off < 0) or (Off + 40 > FS.Size) then
    Exit;
  FS.Position := Off + 24;
  Count := Integer(ReadU32(FS));
  FS.Position := Off + 32;
  NameRva := ReadU32(FS);
  if (Count <= 0) or (Count > 100000) then
    Exit;
  NamesOff := RvaToOff(Secs, NameRva);
  if NamesOff < 0 then
    Exit;
  Got := 0;
  for I := 0 to Count - 1 do
  begin
    if NamesOff + I * 4 + 4 > FS.Size then
      Break;
    FS.Position := NamesOff + I * 4;
    NameRva := ReadU32(FS);
    S := ReadCString(FS, RvaToOff(Secs, NameRva), 160);
    if S = '' then
      Continue;
    if Got >= 40 then
    begin
      Inc(Info.ExportMore);
      Continue;
    end;
    SetLength(Info.ExportNames, Got + 1);
    Info.ExportNames[Got] := S;
    Inc(Got);
  end;
end;

function ReadPeInfo(const APath: string): TPeInfo;
var
  FS: TFileStream;
  ELfa, Magic: Word;
  Lfa: DWORD;
  Machine, Sections, OptSize, Chars, Subsys, Dirs: Word;
  Stamp: DWORD;
  SecOfs, DirOfs: Int64;
  I: Integer;
  Secs: TArray<TPeSec>;
  DirRva: array[0..15] of DWORD;
  Built: TDateTime;
  Ext: string;
begin
  Result := Default(TPeInfo);
  Result.Arch := 'неизвестно';
  Result.Machine := '';
  Result.Subsystem := '';
  Result.Kind := 'EXE';
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    Result.Fail := 'файл занят';
    Exit;
  end;
  try
    try
      if FS.Size < 64 then
        Exit;
      if ReadU16(FS) <> IMG_DOS then
        Exit;
      FS.Position := 60;
      Lfa := ReadU32(FS);
      if (Lfa < 64) or (Int64(Lfa) + 24 + 96 > FS.Size) then
        Exit;
      FS.Position := Lfa;
      if ReadU32(FS) <> IMG_NT then
        Exit;
      Machine := ReadU16(FS);
      Sections := ReadU16(FS);
      Stamp := ReadU32(FS);
      FS.Position := Lfa + 20;
      OptSize := ReadU16(FS);
      Chars := ReadU16(FS);
      if (Sections = 0) or (Sections > 96) or (OptSize < 96) then
        Exit;
      FS.Position := Lfa + 24;
      ELfa := ReadU16(FS);
      Magic := ELfa;
      if Magic = IMG_NT64 then
        Result.Arch := '64-bit'
      else if Magic = IMG_NT32 then
        Result.Arch := '32-bit'
      else
        Exit;
      case Machine of
        $014C: Result.Machine := 'x86';
        $8664: Result.Machine := 'x64';
        $AA64: Result.Machine := 'ARM64';
      else
        Result.Machine := Format('%.4x', [Machine]);
      end;
      FS.Position := Lfa + 24 + 68;
      Subsys := ReadU16(FS);
      case Subsys of
        2: Result.Subsystem := 'GUI';
        3: Result.Subsystem := 'консоль';
        1: Result.Subsystem := 'драйвер';
        10, 11, 12, 13: Result.Subsystem := 'EFI';
      else
        if Subsys <> 0 then
          Result.Subsystem := IntToStr(Subsys);
      end;
      if Magic = IMG_NT64 then
        DirOfs := Lfa + 24 + 112
      else
        DirOfs := Lfa + 24 + 96;
      FS.Position := DirOfs - 4;
      Dirs := Word(ReadU32(FS));
      if Dirs > 16 then
        Dirs := 16;
      FillChar(DirRva, SizeOf(DirRva), 0);
      for I := 0 to Dirs - 1 do
      begin
        DirRva[I] := ReadU32(FS);
        ReadU32(FS);
      end;
      if (DIR_CLR < Dirs) and (DirRva[DIR_CLR] <> 0) then
        Result.IsDotNet := True;
      SecOfs := Lfa + 24 + OptSize;
      SetLength(Secs, Sections);
      for I := 0 to Sections - 1 do
      begin
        FS.Position := SecOfs + I * 40 + 8;
        Secs[I].Virt := ReadU32(FS);
        Secs[I].VA := ReadU32(FS);
        Secs[I].RawSize := ReadU32(FS);
        Secs[I].Raw := ReadU32(FS);
      end;
      if DirRva[DIR_IMPORT] <> 0 then
        ReadImports(FS, Secs, DirRva[DIR_IMPORT], Result);
      if DirRva[DIR_EXPORT] <> 0 then
        ReadExports(FS, Secs, DirRva[DIR_EXPORT], Result);
      if DirRva[DIR_RESOURCE] <> 0 then
        ReadResources(FS, Secs, DirRva[DIR_RESOURCE], Result);
      Result.IsDll := (Chars and IMG_DLL) <> 0;
      Ext := LowerCase(ExtractFileExt(APath));
      if Ext = '.sys' then
        Result.Kind := 'SYS'
      else if Result.IsDll or (Ext = '.dll') or (Ext = '.ocx') then
        Result.Kind := 'DLL'
      else if Ext = '.cpl' then
        Result.Kind := 'CPL'
      else if Ext = '.scr' then
        Result.Kind := 'SCR'
      else
        Result.Kind := 'EXE';
      if (not Result.IsDll) and (Ext <> '.dll') and (Ext <> '.ocx') and
         (Length(Result.ExportNames) = 0) then
        Result.ExportMore := 0;
      if (Stamp > 100000) and (Stamp < $F0000000) then
      begin
        Built := TTimeZone.Local.ToLocalTime(UnixToDateTime(Stamp, True));
        if (Built > EncodeDate(1990, 1, 1)) and (Built < IncYear(Now, 2)) then
          Result.Built := FormatDateTime('dd.mm.yyyy hh:nn', Built);
      end;
      Result.Ok := True;
    except
      Result.Ok := False;
      if Result.Fail = '' then
        Result.Fail := 'файл занят';
    end;
  finally
    FS.Free;
  end;
  if not Result.Ok then
    Exit;
  try
    ReadVersion(APath, Result);
  except
  end;
  try
    MarkMissing(APath, Result);
  except
  end;
  try
    ReadSignature(APath, Result);
  except
    Result.Signed := 0;
  end;
end;

procedure LoadPeIcon(const APath: string; ABmp: FMX.Graphics.TBitmap);
var
  Ico: HICON;
  Info: TIconInfo;
  DC, Mem: HDC;
  Dib: HBITMAP;
  Old: HGDIOBJ;
  BI: TBitmapInfo;
  Bits: Pointer;
  W, H, Y, Row: Integer;
  Data: TBitmapData;
  Got: UINT;

  function Grab(ASize: Integer): Boolean;
  begin
    Ico := 0;
    Got := PrivateExtractIconsW(PChar(APath), 0, ASize, ASize, @Ico, nil, 1, 0);
    Result := (Got > 0) and (Ico <> 0);
  end;

begin
  if ABmp = nil then
    Exit;
  ABmp.SetSize(0, 0);
  Ico := 0;
  if not Grab(256) then
    if not Grab(48) then
      Exit;
  try
    FillChar(Info, SizeOf(Info), 0);
    if not GetIconInfo(Ico, Info) then
      Exit;
    W := 256;
    H := 256;
    DC := GetDC(0);
    Mem := CreateCompatibleDC(DC);
    try
      FillChar(BI, SizeOf(BI), 0);
      BI.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
      BI.bmiHeader.biWidth := W;
      BI.bmiHeader.biHeight := -H;
      BI.bmiHeader.biPlanes := 1;
      BI.bmiHeader.biBitCount := 32;
      BI.bmiHeader.biCompression := BI_RGB;
      Bits := nil;
      Dib := CreateDIBSection(DC, BI, DIB_RGB_COLORS, Bits, 0, 0);
      if (Dib = 0) or (Bits = nil) then
        Exit;
      Old := SelectObject(Mem, Dib);
      DrawIconEx(Mem, 0, 0, Ico, W, H, 0, 0, DI_NORMAL);
      SelectObject(Mem, Old);
      ABmp.SetSize(W, H);
      if ABmp.Map(TMapAccess.Write, Data) then
      try
        Row := W * 4;
        for Y := 0 to H - 1 do
          System.Move((PByte(Bits) + Y * Row)^, PByte(Data.Data)[Y * Data.Pitch], Row);
      finally
        ABmp.Unmap(Data);
      end;
      DeleteObject(Dib);
    finally
      DeleteDC(Mem);
      ReleaseDC(0, DC);
    end;
    if Info.hbmColor <> 0 then
      DeleteObject(Info.hbmColor);
    if Info.hbmMask <> 0 then
      DeleteObject(Info.hbmMask);
  finally
    DestroyIcon(Ico);
  end;
end;

end.
