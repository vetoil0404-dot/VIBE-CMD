unit uWinShellMenu;

{
  Контекстное меню Проводника через IShellItem / IShellItemArray.
  IContextMenu2/3 — вложенные пункты и иконки.
  Тёмная/светлая тема попапа через uxtheme (как у приложения).
}

interface

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;

function ShowExplorerContextMenu(AOwnerWnd: HWND; const AFiles: TArray<string>;
  AX, AY: Integer; ADark: Boolean; out AVerb: string;
  AInterceptPaste: Boolean = False): Boolean;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  Winapi.Messages, Winapi.ShlObj, Winapi.ActiveX, Winapi.DwmApi,
  System.SysUtils;

const
  CShellMenuClass = 'TCClone.ShellMenuHost';

  { uxtheme undocumented, стабильны с Windows 10 1903 }
  UXTHEME_AllowDarkModeForWindow = 133;
  UXTHEME_SetPreferredAppMode    = 135;
  UXTHEME_FlushMenuThemes        = 136;

  PAM_DEFAULT     = 0;
  PAM_ALLOW_DARK  = 1;
  PAM_FORCE_DARK  = 2;
  PAM_FORCE_LIGHT = 3;

type
  TAllowDarkModeForWindow = function(Wnd: HWND; Allow: BOOL): BOOL; stdcall;
  TSetPreferredAppMode = function(Mode: Integer): Integer; stdcall;
  TFlushMenuThemes = procedure; stdcall;

  TMenuHostState = record
    CM2: IContextMenu2;
    CM3: IContextMenu3;
  end;

var
  GClassAtom: ATOM = 0;
  GHost: TMenuHostState;

function SetWindowThemeDirect(Wnd: HWND; const AApp, AId: UnicodeString): HRESULT;
var
  Fn: function(hwnd: HWND; pszSubAppName, pszSubIdList: LPCWSTR): HRESULT; stdcall;
  Lib: HMODULE;
  AppP, IdP: PWideChar;
begin
  Result := E_FAIL;
  Lib := GetModuleHandle('uxtheme.dll');
  if Lib = 0 then
    Lib := LoadLibrary('uxtheme.dll');
  if Lib = 0 then
    Exit;
  @Fn := GetProcAddress(Lib, 'SetWindowTheme');
  if not Assigned(Fn) then
    Exit;
  if AApp <> '' then
    AppP := PWideChar(AApp)
  else
    AppP := nil;
  if AId <> '' then
    IdP := PWideChar(AId)
  else
    IdP := nil;
  Result := Fn(Wnd, AppP, IdP);
end;

procedure ApplyPopupMenuTheme(AWnd: HWND; ADark: Boolean);
var
  Lib: HMODULE;
  AllowDark: TAllowDarkModeForWindow;
  SetMode: TSetPreferredAppMode;
  Flush: TFlushMenuThemes;
  Dark: BOOL;
begin
  Lib := GetModuleHandle('uxtheme.dll');
  if Lib = 0 then
    Lib := LoadLibrary('uxtheme.dll');
  if Lib <> 0 then
  begin
    @SetMode := GetProcAddress(Lib, MakeIntResourceA(UXTHEME_SetPreferredAppMode));
    @AllowDark := GetProcAddress(Lib, MakeIntResourceA(UXTHEME_AllowDarkModeForWindow));
    @Flush := GetProcAddress(Lib, MakeIntResourceA(UXTHEME_FlushMenuThemes));
    if Assigned(SetMode) then
    begin
      if ADark then
        SetMode(PAM_FORCE_DARK)
      else
        SetMode(PAM_FORCE_LIGHT);
    end;
    if Assigned(AllowDark) and (AWnd <> 0) then
      AllowDark(AWnd, ADark);
    if Assigned(Flush) then
      Flush;
  end;

  if AWnd <> 0 then
  begin
    if ADark then
      SetWindowThemeDirect(AWnd, 'DarkMode_Explorer', '')
    else
      SetWindowThemeDirect(AWnd, 'Explorer', '');
    Dark := ADark;
    DwmSetWindowAttribute(AWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @Dark, SizeOf(Dark));
  end;
end;

function ShellMenuWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  LRes: LRESULT;
begin
  case Msg of
    WM_INITMENUPOPUP, WM_UNINITMENUPOPUP, WM_DRAWITEM, WM_MEASUREITEM, WM_MENUCHAR:
      begin
        LRes := 0;
        if Assigned(GHost.CM3) then
        begin
          if GHost.CM3.HandleMenuMsg2(Msg, WParam, LParam, LRes) = S_OK then
            Exit(LRes);
        end
        else if Assigned(GHost.CM2) then
        begin
          if GHost.CM2.HandleMenuMsg(Msg, WParam, LParam) = S_OK then
            Exit(0);
        end;
      end;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure EnsureShellMenuClass;
var
  WC: WNDCLASSEX;
begin
  if GClassAtom <> 0 then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.style := CS_DBLCLKS;
  WC.lpfnWndProc := @ShellMenuWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.lpszClassName := CShellMenuClass;
  GClassAtom := RegisterClassEx(WC);
  if GClassAtom = 0 then
    if GetLastError = ERROR_CLASS_ALREADY_EXISTS then
      GClassAtom := 1;
end;

function CreatePidlArray(const AFiles: TArray<string>; out APidls: TArray<PItemIDList>): Boolean;
var
  I: Integer;
  Attr: ULONG;
  Path: string;
begin
  Result := False;
  SetLength(APidls, Length(AFiles));
  for I := 0 to High(AFiles) do
  begin
    APidls[I] := nil;
    Path := ExcludeTrailingPathDelimiter(AFiles[I]);
    if Path = '' then
      Exit;
    if Failed(SHParseDisplayName(PChar(Path), nil, APidls[I], 0, Attr)) then
      Exit;
  end;
  Result := Length(APidls) > 0;
end;

procedure FreePidlArray(var APidls: TArray<PItemIDList>);
var
  I: Integer;
begin
  for I := 0 to High(APidls) do
    if Assigned(APidls[I]) then
      CoTaskMemFree(APidls[I]);
  SetLength(APidls, 0);
end;

function TryGetMenuFromItems(AOwnerWnd: HWND; const AFiles: TArray<string>;
  out AMenu: IContextMenu): Boolean;
var
  Arr: IShellItemArray;
  Item: IShellItem;
  Pidls: TArray<PItemIDList>;
  Path: string;
begin
  Result := False;
  AMenu := nil;

  if CreatePidlArray(AFiles, Pidls) then
  try
    if Succeeded(SHCreateShellItemArrayFromIDLists(Length(Pidls),
      PCUIDLIST_ABSOLUTE_ARRAY(@Pidls[0]), Arr)) and Assigned(Arr) then
      Result := Succeeded(Arr.BindToHandler(nil, BHID_SFUIObject,
        IID_IContextMenu, AMenu)) and Assigned(AMenu);
  finally
    FreePidlArray(Pidls);
  end;
  if Result then
    Exit;

  Path := ExcludeTrailingPathDelimiter(AFiles[0]);
  if Path = '' then
    Exit;
  if Failed(SHCreateItemFromParsingName(PChar(Path), nil, IID_IShellItem, Item)) then
    Exit;
  Result := Succeeded(Item.BindToHandler(nil, BHID_SFUIObject,
    IID_IContextMenu, AMenu)) and Assigned(AMenu);
end;

function TryGetMenuClassic(AOwnerWnd: HWND; const APath: string;
  out AMenu: IContextMenu): Boolean;
var
  Desktop, Folder: IShellFolder;
  Pidl, Child: PItemIDList;
  Attr: ULONG;
begin
  Result := False;
  AMenu := nil;
  if Failed(SHGetDesktopFolder(Desktop)) then
    Exit;
  if Failed(SHParseDisplayName(PChar(APath), nil, Pidl, 0, Attr)) then
    Exit;
  try
    Child := nil;
    if Failed(SHBindToParent(Pidl, IID_IShellFolder, Pointer(Folder), Child)) then
      Exit;
    if not Assigned(Folder) or not Assigned(Child) then
      Exit;
    Result := Succeeded(Folder.GetUIObjectOf(AOwnerWnd, 1, Child,
      IID_IContextMenu, nil, Pointer(AMenu))) and Assigned(AMenu);
  finally
    CoTaskMemFree(Pidl);
  end;
end;

function ReadMenuVerb(const AMenu: IContextMenu; ACmd: UINT): string;
var
  Buf: array[0..127] of WideChar;
begin
  Result := '';
  FillChar(Buf, SizeOf(Buf), 0);
  if Succeeded(AMenu.GetCommandString(ACmd - 1, GCS_VERBW, nil,
    PAnsiChar(@Buf[0]), Length(Buf))) then
    Result := Buf;
end;

function ShowExplorerContextMenu(AOwnerWnd: HWND; const AFiles: TArray<string>;
  AX, AY: Integer; ADark: Boolean; out AVerb: string;
  AInterceptPaste: Boolean): Boolean;
var
  Menu: IContextMenu;
  Pop: HMENU;
  Cmd: UINT;
  ICI: TCMInvokeCommandInfoEx;
  Flags: UINT;
  Host: HWND;
  Path: string;
begin
  Result := False;
  AVerb := '';
  GHost.CM2 := nil;
  GHost.CM3 := nil;
  if Length(AFiles) = 0 then
    Exit;
  Path := ExcludeTrailingPathDelimiter(AFiles[0]);
  if Path = '' then
    Exit;

  if not TryGetMenuFromItems(AOwnerWnd, AFiles, Menu) then
    if not TryGetMenuClassic(AOwnerWnd, Path, Menu) then
      Exit;

  Supports(Menu, IContextMenu3, GHost.CM3);
  if GHost.CM3 = nil then
    Supports(Menu, IContextMenu2, GHost.CM2);

  EnsureShellMenuClass;
  Host := 0;
  if GClassAtom <> 0 then
    Host := CreateWindowEx(WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW,
      CShellMenuClass, nil, WS_POPUP, 0, 0, 0, 0, AOwnerWnd, 0, HInstance, nil);
  if Host = 0 then
    Host := AOwnerWnd;

  ApplyPopupMenuTheme(Host, ADark);
  if (AOwnerWnd <> 0) and (AOwnerWnd <> Host) then
    ApplyPopupMenuTheme(AOwnerWnd, ADark);

  Pop := CreatePopupMenu;
  if Pop = 0 then
  begin
    if (Host <> 0) and (Host <> AOwnerWnd) then
      DestroyWindow(Host);
    GHost.CM2 := nil;
    GHost.CM3 := nil;
    Exit;
  end;

  try
    Flags := CMF_NORMAL or CMF_EXPLORE or CMF_ITEMMENU or CMF_CANRENAME;
    if GetKeyState(VK_SHIFT) < 0 then
      Flags := Flags or CMF_EXTENDEDVERBS;
    if Failed(Menu.QueryContextMenu(Pop, 0, 1, $7FFF, Flags)) then
      Exit;

    Cmd := UINT(TrackPopupMenuEx(Pop,
      TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_HORIZONTAL or TPM_VERTICAL,
      AX, AY, Host, nil));
    ReleaseCapture;
    if Cmd = 0 then
      Exit;

    AVerb := ReadMenuVerb(Menu, Cmd);
    if SameText(AVerb, 'rename') or
       (AInterceptPaste and SameText(AVerb, 'paste')) then
    begin
      Result := True;
      Exit;
    end;

    FillChar(ICI, SizeOf(ICI), 0);
    ICI.cbSize := SizeOf(ICI);
    ICI.fMask := CMIC_MASK_UNICODE or CMIC_MASK_PTINVOKE;
    if GetKeyState(VK_SHIFT) < 0 then
      ICI.fMask := ICI.fMask or CMIC_MASK_SHIFT_DOWN;
    if GetKeyState(VK_CONTROL) < 0 then
      ICI.fMask := ICI.fMask or CMIC_MASK_CONTROL_DOWN;
    ICI.hwnd := AOwnerWnd;
    ICI.lpVerb := MakeIntResourceA(Cmd - 1);
    ICI.lpVerbW := MakeIntResource(Cmd - 1);
    ICI.nShow := SW_SHOWNORMAL;
    ICI.ptInvoke.X := AX;
    ICI.ptInvoke.Y := AY;
    Result := Succeeded(Menu.InvokeCommand(PCMInvokeCommandInfo(@ICI)^));
  finally
    DestroyMenu(Pop);
    if (Host <> 0) and (Host <> AOwnerWnd) then
      DestroyWindow(Host);
    GHost.CM2 := nil;
    GHost.CM3 := nil;
  end;
end;

{$ENDIF}

end.
