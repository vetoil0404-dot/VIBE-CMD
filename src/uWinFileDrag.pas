unit uWinFileDrag;

{
  Отдача файлов в Проводник и другие приложения.
  IShellItemArray + SHDoDragDrop — CFSTR_SHELLIDLIST, иконка, панель задач.
  CF_HDROP остаётся запасным путём.
}

interface

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;

function DragFilesToOle(const AFiles: TArray<string>; out AEffect: Integer;
  AWnd: HWND = 0): Boolean;
function CopyFilesToClipboard(const AFiles: TArray<string>; ACut: Boolean): Boolean;
function TryGetClipboardFiles(out AFiles: TArray<string>; out ACut: Boolean): Boolean;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  Winapi.ActiveX, Winapi.ShlObj, Winapi.ShellAPI, System.SysUtils;

type
  TDropFilesRec = packed record
    pFiles: UINT;
    pt: TPoint;
    fNC: BOOL;
    fWide: BOOL;
  end;
  PDropFilesRec = ^TDropFilesRec;

type
  TDropSource = class(TInterfacedObject, IDropSource)
    function QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: Longint): HResult; stdcall;
    function GiveFeedback(dwEffect: Longint): HResult; stdcall;
  end;

  TEnumFormatEtc = class(TInterfacedObject, IEnumFORMATETC)
  private
    FIndex: Integer;
  public
    function Next(celt: Longint; out elt; pceltFetched: PLongint): HResult; stdcall;
    function Skip(celt: Longint): HResult; stdcall;
    function Reset: HResult; stdcall;
    function Clone(out Enum: IEnumFORMATETC): HResult; stdcall;
  end;

  { Не TInterfacedObject: Explorer часто держит IDataObject после DoDragDrop,
    из-за чего счётчик ссылок не падает до 0 и FastMM видит утечку на выходе.
    Счётчик ведём сами, но объект освобождаем явно после CoDisconnectObject. }
  TFileDataObject = class(TObject, IDataObject, IDataObjectAsyncCapability)
  private
    FRefCount: Integer;
    FHandle: HGLOBAL;
    function DupHandle: HGLOBAL;
  public
    constructor Create(AHandle: HGLOBAL);
    destructor Destroy; override;
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    function GetData(const formatetcIn: TFormatEtc; out medium: TStgMedium): HResult; stdcall;
    function GetDataHere(const formatetc: TFormatEtc; out medium: TStgMedium): HResult; stdcall;
    function QueryGetData(const formatetc: TFormatEtc): HResult; stdcall;
    function GetCanonicalFormatEtc(const formatetc: TFormatEtc; out formatetcOut: TFormatEtc): HResult; stdcall;
    function SetData(const formatetc: TFormatEtc; var medium: TStgMedium; fRelease: BOOL): HResult; stdcall;
    function EnumFormatEtc(dwDirection: Longint; out enumFormatEtc: IEnumFORMATETC): HResult; stdcall;
    function DAdvise(const formatetc: TFormatEtc; advf: Longint; const advSink: IAdviseSink; out dwConnection: Longint): HResult; stdcall;
    function DUnadvise(dwConnection: Longint): HResult; stdcall;
    function EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
    function SetAsyncMode(fDoOpAsync: BOOL): HRESULT; stdcall;
    function GetAsyncMode(var pfIsOpAsync: Bool): HRESULT; stdcall;
    function StartOperation(pbcReserved: IBindCtx): HRESULT; stdcall;
    function InOperation(var pfInAsyncOp: Bool): HRESULT; stdcall;
    function EndOperation(hResult: HRESULT; pbcReserved: IBindCtx; dwEffects: DWORD): HRESULT; stdcall;
  end;

function TDropSource.QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: Longint): HResult;
begin
  if fEscapePressed then
    Result := DRAGDROP_S_CANCEL
  else if (grfKeyState and (MK_LBUTTON or MK_RBUTTON)) = 0 then
    Result := DRAGDROP_S_DROP
  else
    Result := S_OK;
end;

function TDropSource.GiveFeedback(dwEffect: Longint): HResult;
begin
  Result := DRAGDROP_S_USEDEFAULTCURSORS;
end;

function TEnumFormatEtc.Next(celt: Longint; out elt; pceltFetched: PLongint): HResult;
var
  Fmt: PFormatEtc;
begin
  if (celt <= 0) or (FIndex > 0) then
  begin
    if Assigned(pceltFetched) then
      pceltFetched^ := 0;
    Exit(S_FALSE);
  end;
  Fmt := @elt;
  Fmt.cfFormat := CF_HDROP;
  Fmt.ptd := nil;
  Fmt.dwAspect := DVASPECT_CONTENT;
  Fmt.lindex := -1;
  Fmt.tymed := TYMED_HGLOBAL;
  Inc(FIndex);
  if Assigned(pceltFetched) then
    pceltFetched^ := 1;
  if celt = 1 then
    Result := S_OK
  else
    Result := S_FALSE;
end;

function TEnumFormatEtc.Skip(celt: Longint): HResult;
begin
  Inc(FIndex, celt);
  if FIndex > 1 then
    Result := S_FALSE
  else
    Result := S_OK;
end;

function TEnumFormatEtc.Reset: HResult;
begin
  FIndex := 0;
  Result := S_OK;
end;

function TEnumFormatEtc.Clone(out Enum: IEnumFORMATETC): HResult;
var
  Cloned: TEnumFormatEtc;
begin
  Cloned := TEnumFormatEtc.Create;
  Cloned.FIndex := FIndex;
  Enum := Cloned;
  Result := S_OK;
end;

constructor TFileDataObject.Create(AHandle: HGLOBAL);
begin
  inherited Create;
  FHandle := AHandle;
end;

destructor TFileDataObject.Destroy;
begin
  if FHandle <> 0 then
  begin
    GlobalFree(FHandle);
    FHandle := 0;
  end;
  inherited;
end;

function TFileDataObject.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TFileDataObject._AddRef: Integer;
begin
  Result := AtomicIncrement(FRefCount);
end;

function TFileDataObject._Release: Integer;
begin
  Result := AtomicDecrement(FRefCount);
end;

function TFileDataObject.SetAsyncMode(fDoOpAsync: BOOL): HRESULT;
begin
  { Синхронная передача: Explorer отпускает IDataObject до возврата из DoDragDrop. }
  if fDoOpAsync then
    Result := E_FAIL
  else
    Result := S_OK;
end;

function TFileDataObject.GetAsyncMode(var pfIsOpAsync: Bool): HRESULT;
begin
  pfIsOpAsync := False;
  Result := S_OK;
end;

function TFileDataObject.StartOperation(pbcReserved: IBindCtx): HRESULT;
begin
  Result := E_FAIL;
end;

function TFileDataObject.InOperation(var pfInAsyncOp: Bool): HRESULT;
begin
  pfInAsyncOp := False;
  Result := S_OK;
end;

function TFileDataObject.EndOperation(hResult: HRESULT; pbcReserved: IBindCtx;
  dwEffects: DWORD): HRESULT;
begin
  Result := S_OK;
end;

function TFileDataObject.DupHandle: HGLOBAL;
var
  Size: SIZE_T;
  Src, Dst: Pointer;
begin
  Result := 0;
  Size := GlobalSize(FHandle);
  if Size = 0 then
    Exit;
  Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_DDESHARE, Size);
  if Result = 0 then
    Exit;
  Src := GlobalLock(FHandle);
  Dst := GlobalLock(Result);
  try
    Move(Src^, Dst^, Size);
  finally
    GlobalUnlock(Result);
    GlobalUnlock(FHandle);
  end;
end;

function TFileDataObject.GetData(const formatetcIn: TFormatEtc; out medium: TStgMedium): HResult;
begin
  FillChar(medium, SizeOf(medium), 0);
  if QueryGetData(formatetcIn) <> S_OK then
    Exit(DV_E_FORMATETC);
  medium.tymed := TYMED_HGLOBAL;
  medium.hGlobal := DupHandle;
  medium.unkForRelease := nil;
  if medium.hGlobal = 0 then
    Result := E_OUTOFMEMORY
  else
    Result := S_OK;
end;

function TFileDataObject.GetDataHere(const formatetc: TFormatEtc; out medium: TStgMedium): HResult;
begin
  Result := E_NOTIMPL;
end;

function TFileDataObject.QueryGetData(const formatetc: TFormatEtc): HResult;
begin
  if formatetc.cfFormat <> CF_HDROP then
    Exit(DV_E_FORMATETC);
  if (formatetc.tymed and TYMED_HGLOBAL) = 0 then
    Exit(DV_E_TYMED);
  Result := S_OK;
end;

function TFileDataObject.GetCanonicalFormatEtc(const formatetc: TFormatEtc;
  out formatetcOut: TFormatEtc): HResult;
begin
  formatetcOut := formatetc;
  formatetcOut.ptd := nil;
  Result := DATA_S_SAMEFORMATETC;
end;

function TFileDataObject.SetData(const formatetc: TFormatEtc; var medium: TStgMedium;
  fRelease: BOOL): HResult;
begin
  { Explorer пишет CFSTR_PERFORMEDDROPEFFECT и др. Принимаем владение, чтобы
    источник не держал IDataObject в ожидании SetData. }
  if fRelease then
  begin
    ReleaseStgMedium(medium);
    FillChar(medium, SizeOf(medium), 0);
    Result := S_OK;
  end
  else
    Result := E_NOTIMPL;
end;

function TFileDataObject.EnumFormatEtc(dwDirection: Longint;
  out enumFormatEtc: IEnumFORMATETC): HResult;
begin
  if dwDirection = DATADIR_GET then
  begin
    enumFormatEtc := TEnumFormatEtc.Create;
    Result := S_OK;
  end
  else
    Result := E_NOTIMPL;
end;

function TFileDataObject.DAdvise(const formatetc: TFormatEtc; advf: Longint;
  const advSink: IAdviseSink; out dwConnection: Longint): HResult;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TFileDataObject.DUnadvise(dwConnection: Longint): HResult;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TFileDataObject.EnumDAdvise(out enumAdvise: IEnumStatData): HResult;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function CreateShellFilesDataObject(const AFiles: TArray<string>): IDataObject;
var
  I, N: Integer;
  Pidls: TArray<PItemIDList>;
  Attr: ULONG;
  Path: string;
  Arr: IShellItemArray;
begin
  Result := nil;
  SetLength(Pidls, Length(AFiles));
  N := 0;
  for I := 0 to High(AFiles) do
  begin
    Path := AFiles[I];
    if Path = '' then
      Continue;
    if not ((Length(Path) = 3) and (Path[2] = ':') and
      ((Path[3] = '\') or (Path[3] = '/'))) then
      Path := ExcludeTrailingPathDelimiter(Path);
    Pidls[N] := nil;
    Attr := 0;
    if Failed(SHParseDisplayName(PChar(Path), nil, Pidls[N], 0, Attr)) or
      not Assigned(Pidls[N]) then
      Pidls[N] := ILCreateFromPath(PChar(Path));
    if Assigned(Pidls[N]) then
      Inc(N);
  end;
  SetLength(Pidls, N);
  if N = 0 then
    Exit;
  try
    if Failed(SHCreateShellItemArrayFromIDLists(N,
      PCUIDLIST_ABSOLUTE_ARRAY(@Pidls[0]), Arr)) or not Assigned(Arr) then
      Exit;
    if Failed(Arr.BindToHandler(nil, BHID_DataObject, IDataObject, Result)) then
      Result := nil;
  finally
    for I := 0 to High(Pidls) do
      if Assigned(Pidls[I]) then
        CoTaskMemFree(Pidls[I]);
  end;
end;

function MakeHDrop(const AFiles: TArray<string>): HGLOBAL;
var
  I, CharCount: Integer;
  P: PDropFilesRec;
  W: PWideChar;
  S: string;
begin
  Result := 0;
  if Length(AFiles) = 0 then
    Exit;

  CharCount := 1;
  for I := 0 to High(AFiles) do
    Inc(CharCount, Length(AFiles[I]) + 1);

  Result := GlobalAlloc(GHND or GMEM_DDESHARE,
    SizeOf(TDropFilesRec) + NativeUInt(CharCount) * SizeOf(WideChar));
  if Result = 0 then
    Exit;

  P := GlobalLock(Result);
  try
    FillChar(P^, SizeOf(TDropFilesRec), 0);
    P.pFiles := SizeOf(TDropFilesRec);
    P.fWide := True;
    W := PWideChar(PByte(P) + SizeOf(TDropFilesRec));
    for I := 0 to High(AFiles) do
    begin
      S := AFiles[I];
      if S <> '' then
      begin
        Move(PWideChar(S)^, W^, (Length(S) + 1) * SizeOf(WideChar));
        Inc(W, Length(S) + 1);
      end;
    end;
    W^ := #0;
  finally
    GlobalUnlock(Result);
  end;
end;

function DragFilesToOle(const AFiles: TArray<string>; out AEffect: Integer;
  AWnd: HWND): Boolean;
var
  HDrop: HGLOBAL;
  Fallback: TFileDataObject;
  Data: IDataObject;
  Src: IDropSource;
  HR: HResult;
  Effect: DWORD;
  EffectI: Longint;
  OkEffects: DWORD;
begin
  Result := False;
  AEffect := DROPEFFECT_NONE;
  Fallback := nil;
  Src := nil;
  Data := CreateShellFilesDataObject(AFiles);
  if Data = nil then
  begin
    HDrop := MakeHDrop(AFiles);
    if HDrop = 0 then
      Exit;
    Fallback := TFileDataObject.Create(HDrop);
    Data := Fallback;
  end;
  OkEffects := DROPEFFECT_COPY or DROPEFFECT_MOVE or DROPEFFECT_LINK;
  Effect := 0;
  try
    { nil IDropSource — оболочка даёт IDropSourceNotify: панель задач
      переключает окна, курсор и описание дропа без задержки. }
    HR := SHDoDragDrop(AWnd, Data, nil, OkEffects, Effect);
    if Failed(HR) then
    begin
      Src := TDropSource.Create;
      EffectI := Longint(Effect);
      HR := DoDragDrop(Data, Src, Longint(OkEffects), EffectI);
      Effect := DWORD(EffectI);
      Src := nil;
    end;
    AEffect := Integer(Effect);
    Result := (HR = DRAGDROP_S_DROP) and (Effect <> DROPEFFECT_NONE);
  finally
    if Assigned(Data) then
      CoDisconnectObject(Data, 0);
    Data := nil;
    Src := nil;
    Fallback.Free;
  end;
end;

function CopyFilesToClipboard(const AFiles: TArray<string>; ACut: Boolean): Boolean;
var
  HDrop, HEff: HGLOBAL;
  PEff: PLongInt;
  Fmt: UINT;
begin
  Result := False;
  if Length(AFiles) = 0 then
    Exit;
  HDrop := MakeHDrop(AFiles);
  if HDrop = 0 then
    Exit;
  if not OpenClipboard(0) then
  begin
    GlobalFree(HDrop);
    Exit;
  end;
  try
    EmptyClipboard;
    SetClipboardData(CF_HDROP, HDrop);
    Fmt := RegisterClipboardFormat('Preferred DropEffect');
    HEff := GlobalAlloc(GMEM_MOVEABLE or GMEM_DDESHARE, SizeOf(Integer));
    if HEff <> 0 then
    begin
      PEff := GlobalLock(HEff);
      if ACut then
        PEff^ := DROPEFFECT_MOVE
      else
        PEff^ := DROPEFFECT_COPY;
      GlobalUnlock(HEff);
      SetClipboardData(Fmt, HEff);
    end;
    Result := True;
  finally
    CloseClipboard;
  end;
end;

function TryGetClipboardFiles(out AFiles: TArray<string>; out ACut: Boolean): Boolean;
var
  Drop: HDROP;
  Count, I, Len: Integer;
  Buf: array[0..MAX_PATH] of Char;
  Fmt: UINT;
  HEff: HGLOBAL;
  PEff: PLongInt;
begin
  Result := False;
  ACut := False;
  SetLength(AFiles, 0);
  if not OpenClipboard(0) then
    Exit;
  try
    Drop := HDROP(GetClipboardData(CF_HDROP));
    if Drop = 0 then
      Exit;
    Count := DragQueryFile(Drop, $FFFFFFFF, nil, 0);
    if Count <= 0 then
      Exit;
    SetLength(AFiles, Count);
    for I := 0 to Count - 1 do
    begin
      Len := DragQueryFile(Drop, I, Buf, MAX_PATH);
      SetString(AFiles[I], Buf, Len);
    end;
    Fmt := RegisterClipboardFormat('Preferred DropEffect');
    HEff := GetClipboardData(Fmt);
    if HEff <> 0 then
    begin
      PEff := GlobalLock(HEff);
      if Assigned(PEff) then
        ACut := (PEff^ and DROPEFFECT_MOVE) <> 0;
      GlobalUnlock(HEff);
    end;
    Result := True;
  finally
    CloseClipboard;
  end;
end;

{$ENDIF}

end.
