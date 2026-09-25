unit uThemeManager;

{
  Fluent Design / WinUI 3 tokens for CORE Commander.

  Surfaces follow Windows 11 layering:
    Background  -> window base (mica stand-in)
    Card        -> elevated pane
    Panel       -> file list
    Control     -> buttons, address bar, tabs
  Accent is taken from the system DWM color.
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uAppSettings
  {$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.Messages, Winapi.DwmApi, Winapi.UxTheme, System.Win.Registry
  {$ENDIF};

const
  FluentFontFamily = 'Segoe UI';
  FluentFontDisplay = 'Segoe UI Semibold';
  FluentIconFamily = 'Segoe Fluent Icons';

type
  TThemeColors = record
    // Surfaces
    Background: TAlphaColor;
    LayerBackground: TAlphaColor;
    CardBackground: TAlphaColor;
    PanelBackground: TAlphaColor;
    ItemBackground: TAlphaColor;
    ItemAltBackground: TAlphaColor;
    ItemHover: TAlphaColor;

    // Chrome
    TitleBarBackground: TAlphaColor;
    ToolbarBackground: TAlphaColor;
    DockBackground: TAlphaColor;
    HeaderBackground: TAlphaColor;
    FooterBackground: TAlphaColor;
    TabBarBackground: TAlphaColor;
    AddressBackground: TAlphaColor;

    // Text
    TextColor: TAlphaColor;
    SubTextColor: TAlphaColor;
    DisabledTextColor: TAlphaColor;

    // Strokes
    BorderColor: TAlphaColor;
    CardStroke: TAlphaColor;
    DividerColor: TAlphaColor;
    ControlStroke: TAlphaColor;

    // Controls
    ControlFill: TAlphaColor;
    ControlFillHover: TAlphaColor;
    ControlFillPressed: TAlphaColor;

    // Accent / selection
    SelectionColor: TAlphaColor;
    AccentHover: TAlphaColor;
    AccentSubtle: TAlphaColor;
    AccentSubtleStrong: TAlphaColor;
    SelectionTextColor: TAlphaColor;
    CodeKeyword: TAlphaColor;
    CodeString: TAlphaColor;
    CodeComment: TAlphaColor;
    CodeNumber: TAlphaColor;
    CodeTag: TAlphaColor;
    OnAccentTextColor: TAlphaColor;
    FocusStroke: TAlphaColor;
    DangerColor: TAlphaColor;

    IsDark: Boolean;
  end;

  TSystemChromeWatcher = class
  private
    {$IFDEF MSWINDOWS}
    FWnd: HWND;
    {$ENDIF}
    FOnChange: TProc;
    FLastDark: Boolean;
    FLastAccent: TAlphaColor;
    {$IFDEF MSWINDOWS}
    procedure WndProc(var Message: TMessage);
    {$ENDIF}
    procedure Snapshot;
    procedure CheckChanged;
  public
    constructor Create(AOnChange: TProc);
    destructor Destroy; override;
  end;

function IsSystemDarkTheme: Boolean;
function GetSystemAccentColor: TAlphaColor;
function GetThemeColors(Theme: TAppTheme): TThemeColors;
procedure SetActiveAppTheme(ATheme: TAppTheme);
function ActiveAppTheme: TAppTheme;

function MakeColor(R, G, B: Byte): TAlphaColor;
function MakeColorA(R, G, B, A: Byte): TAlphaColor;
function LightenColor(AColor: TAlphaColor; Amount: Single): TAlphaColor;
function DarkenColor(AColor: TAlphaColor; Amount: Single): TAlphaColor;
function ThemeAdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;

{$IFDEF MSWINDOWS}
procedure ApplyNativeWindowChrome(AWnd: HWND; ADark: Boolean);
procedure ApplyWindowMaterial(AWnd: HWND; AMaterial: TWindowMaterial; ADark: Boolean);
{$ENDIF}
procedure TintChromeForMaterial(var AColors: TThemeColors; AMaterial: TWindowMaterial);

implementation

function MakeColor(R, G, B: Byte): TAlphaColor;
var
  LColor: TAlphaColorRec;
begin
  LColor.A := 255;
  LColor.R := R;
  LColor.G := G;
  LColor.B := B;
  Result := LColor.Color;
end;

function MakeColorA(R, G, B, A: Byte): TAlphaColor;
var
  LColor: TAlphaColorRec;
begin
  LColor.A := A;
  LColor.R := R;
  LColor.G := G;
  LColor.B := B;
  Result := LColor.Color;
end;

function ThemeAdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.Color := AColor;
  Rec.A := AAlpha;
  Result := Rec.Color;
end;

function LightenColor(AColor: TAlphaColor; Amount: Single): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Amount := EnsureRange(Amount, 0, 1);
  Rec.Color := AColor;
  Rec.R := Min(255, Round(Rec.R + (255 - Rec.R) * Amount));
  Rec.G := Min(255, Round(Rec.G + (255 - Rec.G) * Amount));
  Rec.B := Min(255, Round(Rec.B + (255 - Rec.B) * Amount));
  Result := Rec.Color;
end;

function DarkenColor(AColor: TAlphaColor; Amount: Single): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Amount := EnsureRange(Amount, 0, 1);
  Rec.Color := AColor;
  Rec.R := Max(0, Round(Rec.R * (1 - Amount)));
  Rec.G := Max(0, Round(Rec.G * (1 - Amount)));
  Rec.B := Max(0, Round(Rec.B * (1 - Amount)));
  Result := Rec.Color;
end;

function IsSystemDarkTheme: Boolean;
{$IFDEF MSWINDOWS}
var
  Reg: TRegistry;
{$ENDIF}
begin
  Result := False;
  {$IFDEF MSWINDOWS}
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') then
    begin
      if Reg.ValueExists('AppsUseLightTheme') then
        Result := Reg.ReadInteger('AppsUseLightTheme') = 0;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  {$ENDIF}
end;

function GetSystemAccentColor: TAlphaColor;
{$IFDEF MSWINDOWS}
var
  Reg: TRegistry;
  ColorValue: Cardinal;
  R, G, B, A: Byte;
{$ENDIF}
begin
  Result := $FF0078D4;

  {$IFDEF MSWINDOWS}
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Microsoft\Windows\DWM') then
    begin
      if Reg.ValueExists('AccentColor') then
      begin
        ColorValue := Cardinal(Reg.ReadInteger('AccentColor'));
        A := Byte(ColorValue shr 24);
        B := Byte(ColorValue shr 16);
        G := Byte(ColorValue shr 8);
        R := Byte(ColorValue);
        if A = 0 then
          A := 255;
        Result := (TAlphaColor(A) shl 24) or
                  (TAlphaColor(R) shl 16) or
                  (TAlphaColor(G) shl 8) or
                  TAlphaColor(B);
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  {$ENDIF}
end;

var
  GActiveTheme: TAppTheme = atSystem;

procedure SetActiveAppTheme(ATheme: TAppTheme);
begin
  GActiveTheme := ATheme;
end;

function ActiveAppTheme: TAppTheme;
begin
  Result := GActiveTheme;
end;

function GetThemeColors(Theme: TAppTheme): TThemeColors;
var
  Dark: Boolean;
  Accent: TAlphaColor;
begin
  case Theme of
    atLight: Dark := False;
    atDark:  Dark := True;
  else
    Dark := IsSystemDarkTheme;
  end;

  Accent := GetSystemAccentColor ;
  FillChar(Result, SizeOf(Result), 0);
  Result.IsDark := Dark;
  Result.SelectionColor := Accent;
  Result.AccentHover := LightenColor(Accent, 0.14);
  Result.AccentSubtle := ThemeAdjustAlpha(Accent, $36);
  Result.AccentSubtleStrong := ThemeAdjustAlpha(Accent, $52);
  Result.FocusStroke := Accent;
  Result.OnAccentTextColor := $FFFFFFFF;
  Result.DangerColor := $FFC42B1C;

  if Dark then
  begin
    Result.Background         := $FF202020;
    Result.LayerBackground    := $FF1C1C1C;
    Result.CardBackground     := $FF2C2C2C;
    Result.PanelBackground    := $FF2C2C2C;
    Result.ItemBackground     := $FF2C2C2C;
    Result.ItemAltBackground  := $FF2F2F2F;
    Result.ItemHover          := $22FFFFFF;
    Result.TitleBarBackground := $FF202020;
    Result.ToolbarBackground  := $FF2C2C2C;
    Result.DockBackground     := $FF282828;
    Result.HeaderBackground   := $FF323232;
    Result.FooterBackground   := $FF282828;
    Result.TabBarBackground   := $FF282828;
    Result.AddressBackground  := $FF2C2C2C;
    Result.TextColor          := $FFF3F3F3;
    Result.SubTextColor       := $BBC5C5C5;
    Result.DisabledTextColor  := $FF737373;
    Result.BorderColor        := $26FFFFFF;
    Result.CardStroke         := $22FFFFFF;
    Result.DividerColor       := $1AFFFFFF;
    Result.ControlStroke      := $18FFFFFF;
    Result.ControlFill        := $12FFFFFF;
    Result.ControlFillHover   := $1AFFFFFF;
    Result.ControlFillPressed := $0CFFFFFF;
    Result.SelectionTextColor := $FFF3F3F3;
    Result.CodeKeyword := $FF6CB6FF;
    Result.CodeString := $FFCE9178;
    Result.CodeComment := $FF6A9955;
    Result.CodeNumber := $FFB5CEA8;
    Result.CodeTag := $FF4EC9B0;
  end
  else
  begin
    Result.Background         := $FFE6E6E6;
    Result.LayerBackground    := $FFE6E6E6;
    Result.CardBackground     := $FFFFFFFF;
    Result.PanelBackground    := $FFFFFFFF;
    Result.ItemBackground     := $FFFFFFFF;
    Result.ItemAltBackground  := $FFF7F7F7;
    Result.ItemHover          := $14000000;
    Result.TitleBarBackground := $FFE6E6E6;
    Result.ToolbarBackground  := $FFF0F0F0;
    Result.DockBackground     := $FFF3F3F3;
    Result.HeaderBackground   := $FFF9F9F9;
    Result.FooterBackground   := $FFE6E6E6;
    Result.TabBarBackground   := $FFE6E6E6;
    Result.AddressBackground  := $FFEDEDED;
    Result.TextColor          := $FF1A1A1A;
    Result.SubTextColor       := $BB404040;
    Result.DisabledTextColor  := $FF9A9A9A;
    Result.BorderColor        := $1A000000;
    Result.CardStroke         := $17000000;
    Result.DividerColor       := $14000000;
    Result.ControlStroke      := $16000000;
    Result.ControlFill        := $0A000000;
    Result.ControlFillHover   := $12000000;
    Result.ControlFillPressed := $08000000;
    Result.SelectionTextColor := $FF1A1A1A;
    Result.CodeKeyword := $FF0000CC;
    Result.CodeString := $FFA31515;
    Result.CodeComment := $FF008000;
    Result.CodeNumber := $FF098658;
    Result.CodeTag := $FF267F99;
  end;
end;

{$IFDEF MSWINDOWS}
const
  WM_DWMCOLORIZATIONCOLORCHANGED = $0320;
  DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;
  DWMWA_USE_IMMERSIVE_DARK_MODE_NEW = 20;
  UXTHEME_AllowDarkModeForWindow = 133;
  UXTHEME_SetPreferredAppMode    = 135;
  UXTHEME_FlushMenuThemes        = 136;
  PAM_FORCE_DARK  = 2;
  PAM_FORCE_LIGHT = 3;

procedure ApplyNativeWindowChrome(AWnd: HWND; ADark: Boolean);
var
  Dark: BOOL;
  Lib: HMODULE;
  SetMode: function(Mode: Integer): Integer; stdcall;
  AllowDark: function(Wnd: HWND; Allow: BOOL): BOOL; stdcall;
  Flush: procedure; stdcall;
begin
  if AWnd = 0 then
    Exit;

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
    if Assigned(AllowDark) then
      AllowDark(AWnd, ADark);
    if Assigned(Flush) then
      Flush;
  end;

  Dark := ADark;
  DwmSetWindowAttribute(AWnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, @Dark, SizeOf(Dark));
  DwmSetWindowAttribute(AWnd, DWMWA_USE_IMMERSIVE_DARK_MODE_NEW, @Dark, SizeOf(Dark));
  SetWindowPos(AWnd, 0, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
end;

const
  DWMWA_SYSTEMBACKDROP_TYPE = 38;
  DWMWA_MICA_EFFECT = 1029;
  DWMWA_CAPTION_COLOR = 35;
  DWMWA_BORDER_COLOR = 34;
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWA_COLOR_NONE = $FFFFFFFE;
  DWMSBT_AUTO = 0;
  DWMSBT_NONE = 1;
  DWMSBT_MAINWINDOW = 2;
  DWMSBT_TRANSIENTWINDOW = 3;
  DWMSBT_TABBEDWINDOW = 4;
  WCA_ACCENT_POLICY = 19;
  ACCENT_DISABLED = 0;
  ACCENT_ENABLE_BLURBEHIND = 3;
  ACCENT_ENABLE_ACRYLICBLURBEHIND = 4;

type
  TAccentPolicy = packed record
    AccentState: Integer;
    AccentFlags: Integer;
    GradientColor: Cardinal;
    AnimationId: Integer;
  end;
  TWinCompAttrData = packed record
    Attribute: Integer;
    Data: Pointer;
    SizeOfData: ULONG;
  end;

function NtBuildNumber: DWORD;
begin
  Result := TOSVersion.Build;
end;

procedure SetAccentPolicy(AWnd: HWND; AState: Integer; AGradient: Cardinal);
var
  SetAttr: function(Wnd: HWND; var Data: TWinCompAttrData): BOOL; stdcall;
  Policy: TAccentPolicy;
  Data: TWinCompAttrData;
begin
  @SetAttr := GetProcAddress(GetModuleHandle('user32.dll'), 'SetWindowCompositionAttribute');
  if not Assigned(SetAttr) then
    Exit;
  FillChar(Policy, SizeOf(Policy), 0);
  Policy.AccentState := AState;
  Policy.AccentFlags := 2;
  Policy.GradientColor := AGradient;
  Data.Attribute := WCA_ACCENT_POLICY;
  Data.Data := @Policy;
  Data.SizeOfData := SizeOf(Policy);
  SetAttr(AWnd, Data);
end;

procedure ApplyWindowMaterial(AWnd: HWND; AMaterial: TWindowMaterial; ADark: Boolean);
var
  Backdrop: Integer;
  MicaOn: BOOL;
  Margins: TMargins;
  Tint: Cardinal;
  ColorNone: COLORREF;
begin
  if AWnd = 0 then
    Exit;

  ApplyNativeWindowChrome(AWnd, ADark);

  FillChar(Margins, SizeOf(Margins), 0);
  ColorNone := DWMWA_COLOR_NONE;

  case AMaterial of
    wmMica:
      begin
        Margins.cxLeftWidth := -1;
        Margins.cxRightWidth := -1;
        Margins.cyTopHeight := -1;
        Margins.cyBottomHeight := -1;
        DwmExtendFrameIntoClientArea(AWnd, Margins);
        DwmSetWindowAttribute(AWnd, DWMWA_CAPTION_COLOR, @ColorNone, SizeOf(ColorNone));
        DwmSetWindowAttribute(AWnd, DWMWA_BORDER_COLOR, @ColorNone, SizeOf(ColorNone));
        if NtBuildNumber >= 22621 then
        begin
          Backdrop := DWMSBT_MAINWINDOW;
          DwmSetWindowAttribute(AWnd, DWMWA_SYSTEMBACKDROP_TYPE, @Backdrop, SizeOf(Backdrop));
        end
        else if NtBuildNumber >= 22000 then
        begin
          MicaOn := True;
          DwmSetWindowAttribute(AWnd, DWMWA_MICA_EFFECT, @MicaOn, SizeOf(MicaOn));
        end
        else
        begin
          if ADark then
            Tint := $66202020
          else
            Tint := $66F3F3F3;
          SetAccentPolicy(AWnd, ACCENT_ENABLE_ACRYLICBLURBEHIND, Tint);
        end;
      end;
    wmAcrylic:
      begin
        Margins.cxLeftWidth := -1;
        Margins.cxRightWidth := -1;
        Margins.cyTopHeight := -1;
        Margins.cyBottomHeight := -1;
        DwmExtendFrameIntoClientArea(AWnd, Margins);
        DwmSetWindowAttribute(AWnd, DWMWA_CAPTION_COLOR, @ColorNone, SizeOf(ColorNone));
        DwmSetWindowAttribute(AWnd, DWMWA_BORDER_COLOR, @ColorNone, SizeOf(ColorNone));
        if NtBuildNumber >= 22621 then
        begin
          Backdrop := DWMSBT_TRANSIENTWINDOW;
          DwmSetWindowAttribute(AWnd, DWMWA_SYSTEMBACKDROP_TYPE, @Backdrop, SizeOf(Backdrop));
        end
        else
        begin
          if ADark then
            Tint := $99202020
          else
            Tint := $99E6E6E6;
          SetAccentPolicy(AWnd, ACCENT_ENABLE_ACRYLICBLURBEHIND, Tint);
        end;
      end;
  else
    Backdrop := DWMSBT_NONE;
    DwmSetWindowAttribute(AWnd, DWMWA_SYSTEMBACKDROP_TYPE, @Backdrop, SizeOf(Backdrop));
    MicaOn := False;
    DwmSetWindowAttribute(AWnd, DWMWA_MICA_EFFECT, @MicaOn, SizeOf(MicaOn));
    SetAccentPolicy(AWnd, ACCENT_DISABLED, 0);
    DwmExtendFrameIntoClientArea(AWnd, Margins);
  end;

  SetWindowPos(AWnd, 0, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
end;
{$ENDIF}

procedure TintChromeForMaterial(var AColors: TThemeColors; AMaterial: TWindowMaterial);
begin
  case AMaterial of
    wmMica:
      begin
        AColors.Background := ThemeAdjustAlpha(AColors.Background, $01);
        AColors.TitleBarBackground := ThemeAdjustAlpha(AColors.TitleBarBackground, $18);
        AColors.DockBackground := ThemeAdjustAlpha(AColors.DockBackground, $70);
        AColors.ToolbarBackground := ThemeAdjustAlpha(AColors.ToolbarBackground, $99);
        AColors.FooterBackground := ThemeAdjustAlpha(AColors.FooterBackground, $40);
        AColors.TabBarBackground := ThemeAdjustAlpha(AColors.TabBarBackground, $A0);
      end;
    wmAcrylic:
      begin
        AColors.Background := ThemeAdjustAlpha(AColors.Background, $90);
        AColors.TitleBarBackground := ThemeAdjustAlpha(AColors.TitleBarBackground, $70);
        AColors.DockBackground := ThemeAdjustAlpha(AColors.DockBackground, $A8);
        AColors.ToolbarBackground := ThemeAdjustAlpha(AColors.ToolbarBackground, $B8);
        AColors.FooterBackground := ThemeAdjustAlpha(AColors.FooterBackground, $80);
        AColors.TabBarBackground := ThemeAdjustAlpha(AColors.TabBarBackground, $B0);
      end;
  end;
end;

{ TSystemChromeWatcher }

constructor TSystemChromeWatcher.Create(AOnChange: TProc);
begin
  inherited Create;
  FOnChange := AOnChange;
  Snapshot;
  {$IFDEF MSWINDOWS}
  FWnd := AllocateHWnd(WndProc);
  {$ENDIF}
end;

destructor TSystemChromeWatcher.Destroy;
begin
  {$IFDEF MSWINDOWS}
  if FWnd <> 0 then
  begin
    KillTimer(FWnd, 1);
    DeallocateHWnd(FWnd);
    FWnd := 0;
  end;
  {$ENDIF}
  inherited;
end;

procedure TSystemChromeWatcher.Snapshot;
begin
  FLastDark := IsSystemDarkTheme;
  FLastAccent := GetSystemAccentColor;
end;

procedure TSystemChromeWatcher.CheckChanged;
var
  Dark: Boolean;
  Accent: TAlphaColor;
begin
  Dark := IsSystemDarkTheme;
  Accent := GetSystemAccentColor;
  if (Dark = FLastDark) and (Accent = FLastAccent) then
    Exit;
  FLastDark := Dark;
  FLastAccent := Accent;
  if Assigned(FOnChange) then
    FOnChange();
end;

{$IFDEF MSWINDOWS}
procedure TSystemChromeWatcher.WndProc(var Message: TMessage);
begin
  case Message.Msg of
    WM_SETTINGCHANGE, WM_THEMECHANGED, WM_DWMCOLORIZATIONCOLORCHANGED:
      SetTimer(FWnd, 1, 180, nil);
    WM_TIMER:
      begin
        KillTimer(FWnd, 1);
        CheckChanged;
      end;
  else
    Message.Result := DefWindowProc(FWnd, Message.Msg, Message.WParam, Message.LParam);
  end;
end;
{$ENDIF}

end.
