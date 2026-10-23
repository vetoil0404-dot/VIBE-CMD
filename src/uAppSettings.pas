unit uAppSettings;

{
  Хранение и загрузка пользовательских настроек в VibeSetting.ini рядом с exe.
  /ini= подменяет этот файл до создания настроек. Чужой запуск ini не меняет.
  Поддерживаются вкладки обеих панелей, вид/зум/сортировка каждой вкладки
  и геометрия окна. Старый формат (один Path на панель) читается как одна вкладка.
}

interface

uses
  System.SysUtils, System.IniFiles, System.Classes, System.Math,
  System.SyncObjs, System.Threading, uLang;

type
  TAppTheme = (atSystem, atLight, atDark);
  TWindowMaterial = (wmNormal, wmAcrylic, wmMica);
  TPanelViewMode = (vmDetails, vmTiles);
  TDockAlign = (daLeft, daCenter, daFree);
  TFileOpMode = (fomQuiet, fomExplorer, fomVibe);
  TMouseSelectMode = (msmVibe, msmExplorer);

  TTabState = record
    Path: string;
    ViewMode: TPanelViewMode;
    ZoomDetails: Integer;
    ZoomTiles: Integer;
    SortField: Integer;
    SortAsc: Boolean;
    CursorPath: string;
  end;

  TDriveLastEntry = record
    Root: string;
    Path: string;
  end;

  TSideState = record
    ActiveTab: Integer;
    Tabs: TArray<TTabState>;
    DriveLast: TArray<TDriveLastEntry>;
  end;

  TAppSettings = class
  private
    FFileName: string;
    FIniSource: string;
    FPrefsDirty: Boolean;
    FPrefsWorker: Boolean;
    FPrefsLock: TCriticalSection;
    FPrefsEvent: TEvent;
    FPending: TObject;
    function StrToBoolDef(const S: string; Def: Boolean): Boolean;
    function DefaultTab(const APath: string): TTabState;
    procedure LoadSide(Ini: TIniFile; const ASection: string; var ASide: TSideState);
    procedure PrefsWorker;
  public
    Theme: TAppTheme;
    WindowMaterial: TWindowMaterial;
    { -1 выкл, 0..359 градус Hue. Красит только wmNormal. }
    ColorTint: Integer;
    { 0 непрозрачно, 1..100 процент. Normal — только фон окна и
      заголовок (то, что красит оттенок); на 100 это четверть
      прежней альфы. Acrylic умножает свою альфу на тот же предел.
      Mica ослабляет вкладки, диски, крошки, заголовок и статус. }
    Transparency: Integer;
    { Код файла lang\*.ini или 'system'. Ini: Main/Language. }
    Language: string;
    QuickViewEnabled: Boolean;
    { Окно F3. Колонку Ctrl+Q не включает и не выключает. }
    FollowCursor: Boolean;
    WindowAnimate: Boolean;
    ShowNetworkButton: Boolean;
    { Секция Network: последний диапазон и до 20 путей через «|». }
    NetworkLastSubnet: string;
    NetworkHistory: string;
    ShowHiddenFiles: Boolean;
    ShowFolderSizes: Boolean;
    ActivePanel: Integer; // 0 = left, 1 = right

    ShowDock: Boolean;
    ShowMidBar: Boolean;
    ShowDriveBar: Boolean;
    ShowDriveHome: Boolean;
    ShowBreadcrumbs: Boolean;
    ShowStatusBar: Boolean;
    ShowFnBar: Boolean;
    ShowQuickAccess: Boolean;
    ShowCommandLine: Boolean;

    ListFontFamily: string;
    ListFontSize: Integer;
    ShowTabIcons: Boolean;
    EqualTabWidth: Boolean;
    DockAlign: TDockAlign;
    DockShowSeparators: Boolean;
    { True, пока секцию Dock ещё ни разу не сохраняли. Пустой список пинов — не этот признак. }
    DockSeedPending: Boolean;

    ThumbCacheEnabled: Boolean;
    ThumbCacheMaxItems: Integer;
    FileOpMode: TFileOpMode;
    { Select/MouseMode: vibe — ПКМ, explorer — ЛКМ. Жест в ini не пишется. }
    MouseSelectMode: TMouseSelectMode;
    AutoStart: Boolean;
    SingleInstance: Boolean;

    WindowLeft, WindowTop, WindowWidth, WindowHeight: Integer;
    WindowMaximized: Boolean;
    { False, пока в ini нет Window/Left и Window/Top. -1 само по себе — монитор слева или сверху. }
    WindowPosSaved: Boolean;
    SplitterPos: Single;

    Left: TSideState;
    Right: TSideState;
    DockItems: TArray<string>;
    DockItemX: TArray<Single>;
    DockKinds: TArray<Integer>;
    DockCaptions: TArray<string>;
    DockIcons: TArray<string>;
    DockIconLocked: TArray<Boolean>;
    SearchHistory: TArray<string>;

    constructor Create;
    destructor Destroy; override;
    procedure Load;
    { Первый запуск: пины и daCenter в ту же секцию Dock. Пустой набор не пишет ini. }
    procedure CommitDockSeed(const APaths, ACaptions: TArray<string>);
    procedure SaveSettings;
    procedure SaveSession;
    procedure SaveSessionAsync;
    procedure SaveBehavior;
    procedure SaveNetwork;
    procedure SaveSearchHistory;
    { Только секция Dock — в фоне, без блокировки UI. }
    procedure SaveDockAsync;
    { Снимок настроек и одна запись в фоне. UI этот файл не ждёт. }
    procedure SaveAsync;
    { Дождаться фоновой записи. Выход и закрытие диалога терять правку не должны. }
    procedure FlushPrefs;
    function PrefsDirty: Boolean;
    procedure MarkPrefsDirty;
  end;

function SingleInstanceWanted: Boolean;
{ Пусто — VibeSetting.ini рядом с exe. /ini= задаёт путь до загрузки сессии. }
procedure SetSettingsIniOverride(const APath: string);
function ActiveSettingsIni: string;
function ReadFontPhrase: string;
procedure WriteFontPhrase(const AText: string);
{ Первый фиксированный том, A→Z. Без ini панели открываются на нём, не на диске exe. }
function DefaultStartupDrive: string;
{ Настоящая сборка NT. Граница Windows 11 — 22000. }
function WindowsBuild: Cardinal;
{ 10 или 11. У обеих Major = 10, граница — сборка 22000. }
function WindowsVersion: Integer;
{ На Windows 10 нет ни мики, ни акрила: любое значение сводится к обычному окну. }
function MaterialForWindows(AMaterial: TWindowMaterial): TWindowMaterial;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

procedure UpdateIni(const AFile: string; const AEdit: TProc<TCustomIniFile>); forward;

var
  GSettingsSaveLock: TCriticalSection;
  GSettingsIniOverride: string;

const
  DEFAULT_ZOOM = 100;

constructor TAppSettings.Create;
var
  Root: string;
begin
  inherited Create;
  if GSettingsSaveLock = nil then
    GSettingsSaveLock := TCriticalSection.Create;
  FPrefsLock := TCriticalSection.Create;
  FPrefsEvent := TEvent.Create(nil, True, True, '');
  if GSettingsIniOverride <> '' then
    FFileName := GSettingsIniOverride
  else
    FFileName := ExtractFilePath(ParamStr(0)) + 'VibeSetting.ini';

  Theme := atSystem;
  WindowMaterial := wmNormal;
  ColorTint := -1;
  Transparency := 0;
  Language := 'system';
  QuickViewEnabled := True;
  FollowCursor := True;
  WindowAnimate := True;
  ShowNetworkButton := True;
  ShowHiddenFiles := False;
  ShowFolderSizes := True;
  ActivePanel := 0;

  ShowDock := True;
  ShowMidBar := True;
  ShowDriveBar := True;
  ShowDriveHome := True;
  ShowBreadcrumbs := True;
  ShowStatusBar := True;
  ShowFnBar := True;
  ShowQuickAccess := True;
  ShowCommandLine := True;

  ListFontFamily := 'Segoe UI';
  ListFontSize := 13;
  ShowTabIcons := True;
  EqualTabWidth := True;
  DockAlign := daLeft;
  DockShowSeparators := True;
  DockSeedPending := False;
  FIniSource := '';

  ThumbCacheEnabled := True;
  ThumbCacheMaxItems := 400;
  FileOpMode := fomExplorer;
  MouseSelectMode := msmExplorer;
  AutoStart := False;
  SingleInstance := True;

  WindowLeft := -1;
  WindowTop := -1;
  WindowWidth := 1200;
  WindowHeight := 625;
  WindowMaximized := False;
  WindowPosSaved := False;
  SplitterPos := 0.5;

  Root := DefaultStartupDrive;
  Left.ActiveTab := 0;
  SetLength(Left.Tabs, 1);
  Left.Tabs[0] := DefaultTab(Root);
  Right := Left;
end;

destructor TAppSettings.Destroy;
begin
  try
    if FPrefsLock <> nil then
      FlushPrefs;
  except
  end;
  FPending.Free;
  FPrefsEvent.Free;
  FPrefsLock.Free;
  inherited;
end;

function DefaultStartupDrive: string;
{$IFDEF MSWINDOWS}
var
  Mask: DWORD;
  I: Integer;
  Root, Other: string;
  Kind: UINT;
{$ENDIF}
begin
  Result := 'C:\';
{$IFDEF MSWINDOWS}
  Other := '';
  Mask := GetLogicalDrives;
  for I := 0 to 25 do
  begin
    if (Mask and (1 shl I)) = 0 then
      Continue;
    Root := Char(Ord('A') + I) + ':\';
    Kind := GetDriveType(PChar(Root));
    if Kind = DRIVE_FIXED then
      Exit(Root);
    if (Other = '') and (Kind <> DRIVE_NO_ROOT_DIR) and (Kind <> DRIVE_UNKNOWN) then
      Other := Root;
  end;
  if Other <> '' then
    Result := Other;
{$ENDIF}
end;

function WindowsBuild: Cardinal;
var
  RtlGetVersion: function(var Info: TOSVersionInfoExW): LongInt; stdcall;
  Info: TOSVersionInfoExW;
begin
  { TOSVersion на части процессов остаётся ниже 22000, и Windows 11
    принимается за Windows 10. RtlGetVersion отдаёт настоящую сборку. }
  Result := TOSVersion.Build;
  @RtlGetVersion := GetProcAddress(GetModuleHandle('ntdll.dll'), 'RtlGetVersion');
  if not Assigned(RtlGetVersion) then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  Info.dwOSVersionInfoSize := SizeOf(Info);
  if RtlGetVersion(Info) = 0 then
    Result := Info.dwBuildNumber;
end;

function WindowsVersion: Integer;
begin
  Result := 10;
  if WindowsBuild >= 22000 then
    Result := 11
  else if TOSVersion.Major > 10 then
    Result := TOSVersion.Major;
end;

function MaterialForWindows(AMaterial: TWindowMaterial): TWindowMaterial;
begin
  Result := AMaterial;
  if WindowsVersion < 11 then
    Result := wmNormal;
end;

function EncodeTabCursor(const APath: string): string;
begin
  if APath = #1 then
    Result := '..'
  else
    Result := APath;
end;

function DecodeTabCursor(const APath: string): string;
begin
  if (APath = '..') or (APath = #1) then
    Result := #1
  else
    Result := APath;
end;

function TAppSettings.DefaultTab(const APath: string): TTabState;
begin
  Result.Path := APath;
  Result.ViewMode := vmDetails;
  Result.ZoomDetails := DEFAULT_ZOOM;
  Result.ZoomTiles := DEFAULT_ZOOM;
  Result.SortField := 0;
  Result.SortAsc := True;
  Result.CursorPath := '';
end;

function IniBoolStr(B: Boolean): string;
begin
  if B then
    Result := '1'
  else
    Result := '0';
end;

function TAppSettings.StrToBoolDef(const S: string; Def: Boolean): Boolean;
begin
  { «-1» пишет SysUtils.BoolToStr(True). Так уже лежит SortAsc сессии. }
  if (S = '1') or (S = '-1') or SameText(S, 'true') then
    Result := True
  else if (S = '0') or SameText(S, 'false') then
    Result := False
  else
    Result := Def;
end;

procedure TAppSettings.LoadSide(Ini: TIniFile; const ASection: string; var ASide: TSideState);
var
  TabCount, I, LegacyZoom: Integer;
  TabSec, LegacyPath: string;
begin
  TabCount := Ini.ReadInteger(ASection, 'TabCount', -1);
  ASide.ActiveTab := Ini.ReadInteger(ASection, 'ActiveTab', 0);

  if TabCount > 0 then
  begin
    SetLength(ASide.Tabs, TabCount);
    for I := 0 to TabCount - 1 do
    begin
      TabSec := ASection + 'Tab' + IntToStr(I);
      ASide.Tabs[I] := DefaultTab(DefaultStartupDrive);
      ASide.Tabs[I].Path := Ini.ReadString(TabSec, 'Path', ASide.Tabs[I].Path);
      ASide.Tabs[I].ViewMode := TPanelViewMode(Ini.ReadInteger(TabSec, 'ViewMode', 0));
      LegacyZoom := Ini.ReadInteger(TabSec, 'Zoom', DEFAULT_ZOOM);
      ASide.Tabs[I].ZoomDetails := Ini.ReadInteger(TabSec, 'ZoomDetails', LegacyZoom);
      ASide.Tabs[I].ZoomTiles := Ini.ReadInteger(TabSec, 'ZoomTiles', LegacyZoom);
      ASide.Tabs[I].SortField := Ini.ReadInteger(TabSec, 'SortField',
        Ini.ReadInteger(TabSec, 'SortColumn', 0));
      ASide.Tabs[I].SortAsc := StrToBoolDef(Ini.ReadString(TabSec, 'SortAsc', '1'), True);
      ASide.Tabs[I].CursorPath := DecodeTabCursor(Ini.ReadString(TabSec, 'CursorPath', ''));
    end;
  end
  else
  begin
    LegacyPath := Ini.ReadString(ASection, 'Path', '');
    if LegacyPath <> '' then
    begin
      SetLength(ASide.Tabs, 1);
      ASide.Tabs[0] := DefaultTab(LegacyPath);
      ASide.Tabs[0].ViewMode := TPanelViewMode(Ini.ReadInteger(ASection, 'ViewMode', 0));
      LegacyZoom := Ini.ReadInteger(ASection, 'Zoom', DEFAULT_ZOOM);
      ASide.Tabs[0].ZoomDetails := LegacyZoom;
      ASide.Tabs[0].ZoomTiles := LegacyZoom;
      ASide.Tabs[0].SortField := Ini.ReadInteger(ASection, 'SortColumn', 0);
      ASide.Tabs[0].SortAsc := StrToBoolDef(Ini.ReadString(ASection, 'SortAsc', '1'), True);
    end;
  end;

  if Length(ASide.Tabs) = 0 then
  begin
    SetLength(ASide.Tabs, 1);
    ASide.Tabs[0] := DefaultTab(DefaultStartupDrive);
  end;
  if (ASide.ActiveTab < 0) or (ASide.ActiveTab >= Length(ASide.Tabs)) then
    ASide.ActiveTab := 0;

  var LastCount := Ini.ReadInteger(ASection, 'DriveLastCount', 0);
  SetLength(ASide.DriveLast, 0);
  if LastCount > 0 then
  begin
    SetLength(ASide.DriveLast, LastCount);
    var N := 0;
    for I := 0 to LastCount - 1 do
    begin
      var Root := Trim(Ini.ReadString(ASection, 'DriveLastRoot' + IntToStr(I), ''));
      var Path := Trim(Ini.ReadString(ASection, 'DriveLastPath' + IntToStr(I), ''));
      if Root = '' then
        Continue;
      ASide.DriveLast[N].Root := Root;
      ASide.DriveLast[N].Path := Path;
      Inc(N);
    end;
    SetLength(ASide.DriveLast, N);
  end;
end;

procedure WriteSide(Ini: TCustomIniFile; const ASection: string; const ASide: TSideState);
var
  I: Integer;
  TabSec: string;
begin
  Ini.WriteInteger(ASection, 'TabCount', Length(ASide.Tabs));
  Ini.WriteInteger(ASection, 'ActiveTab', ASide.ActiveTab);
  if Length(ASide.Tabs) > 0 then
  begin
    Ini.WriteString(ASection, 'Path', ASide.Tabs[ASide.ActiveTab].Path);
    Ini.WriteInteger(ASection, 'ViewMode', Ord(ASide.Tabs[ASide.ActiveTab].ViewMode));
    Ini.WriteInteger(ASection, 'Zoom', ASide.Tabs[ASide.ActiveTab].ZoomDetails);
    Ini.WriteInteger(ASection, 'SortColumn', ASide.Tabs[ASide.ActiveTab].SortField);
    Ini.WriteString(ASection, 'SortAsc', IniBoolStr(ASide.Tabs[ASide.ActiveTab].SortAsc));
  end;

  for I := 0 to High(ASide.Tabs) do
  begin
    TabSec := ASection + 'Tab' + IntToStr(I);
    Ini.WriteString(TabSec, 'Path', ASide.Tabs[I].Path);
    Ini.WriteInteger(TabSec, 'ViewMode', Ord(ASide.Tabs[I].ViewMode));
    Ini.WriteInteger(TabSec, 'ZoomDetails', ASide.Tabs[I].ZoomDetails);
    Ini.WriteInteger(TabSec, 'ZoomTiles', ASide.Tabs[I].ZoomTiles);
    Ini.WriteInteger(TabSec, 'SortField', ASide.Tabs[I].SortField);
    Ini.WriteString(TabSec, 'SortAsc', IniBoolStr(ASide.Tabs[I].SortAsc));
    Ini.WriteString(TabSec, 'CursorPath', EncodeTabCursor(ASide.Tabs[I].CursorPath));
  end;

  Ini.WriteInteger(ASection, 'DriveLastCount', Length(ASide.DriveLast));
  for I := 0 to High(ASide.DriveLast) do
  begin
    Ini.WriteString(ASection, 'DriveLastRoot' + IntToStr(I), ASide.DriveLast[I].Root);
    Ini.WriteString(ASection, 'DriveLastPath' + IntToStr(I), ASide.DriveLast[I].Path);
  end;
end;

procedure TAppSettings.Load;
var
  Ini: TIniFile;
  Source: string;
begin
  DockSeedPending := True;
  DockAlign := daCenter;
  FIniSource := '';
  Source := FFileName;
  if not FileExists(Source) then
  begin
    { /ini= не подменяет соседний VibeSetting.ini и TCClone.ini. }
    if GSettingsIniOverride <> '' then
      Exit;
    Source := ExtractFilePath(ParamStr(0)) + 'TCClone.ini';
    if not FileExists(Source) then
      Exit;
  end;

  FIniSource := Source;
  Ini := TIniFile.Create(Source);
  try
    Theme := TAppTheme(Ini.ReadInteger('Main', 'Theme', Ord(atSystem)));
    WindowMaterial := MaterialForWindows(TWindowMaterial(EnsureRange(
      Ini.ReadInteger('Appearance', 'Material', Ord(wmNormal)), 0, 2)));
    ColorTint := Ini.ReadInteger('Appearance', 'ColorHue', -1);
    Language := NormalizeLanguage(Ini.ReadString('Main', 'Language', 'system'));
    if (ColorTint < 0) or (ColorTint > 359) then
      ColorTint := -1;
    Transparency := Ini.ReadInteger('Appearance', 'Transparency', 0);
    if (Transparency < 0) or (Transparency > 100) then
      Transparency := 0;
    QuickViewEnabled := True;
    FollowCursor := StrToBoolDef(Ini.ReadString('View', 'FollowCursor', '1'), True);
    { Нет ключа — как в конструкторе. SaveSession эти поля не пишет. }
    if SameText(Ini.ReadString('Select', 'MouseMode', 'explorer'), 'explorer') then
      MouseSelectMode := msmExplorer
    else
      MouseSelectMode := msmVibe;
    WindowAnimate := True;
    ShowNetworkButton := StrToBoolDef(Ini.ReadString('Main', 'ShowNetwork', '1'), True);
    NetworkLastSubnet := Ini.ReadString('Network', 'LastSubnet', '');
    NetworkHistory := Ini.ReadString('Network', 'History', '');
    ShowHiddenFiles := StrToBoolDef(Ini.ReadString('Main', 'ShowHidden', '0'), False);
    ShowFolderSizes := StrToBoolDef(Ini.ReadString('Main', 'ShowFolderSize', '1'), True);
    ActivePanel := Ini.ReadInteger('Main', 'ActivePanel', 0);
    var Hist := Ini.ReadString('Main', 'SearchHistory', '');
    SetLength(SearchHistory, 0);
    if Hist <> '' then
    begin
      var Parts := Hist.Split([#9]);
      var N := 0;
      SetLength(SearchHistory, Min(12, Length(Parts)));
      for var I := 0 to High(Parts) do
      begin
        var S := Trim(Parts[I]);
        if (S <> '') and (N < 12) then
        begin
          SearchHistory[N] := S;
          Inc(N);
        end;
      end;
      SetLength(SearchHistory, N);
    end;

    ShowDock := StrToBoolDef(Ini.ReadString('Layout', 'Dock', '1'), True);
    ShowMidBar := StrToBoolDef(Ini.ReadString('Layout', 'MidBar', '1'), True);
    ShowDriveBar := StrToBoolDef(Ini.ReadString('Layout', 'DriveBar', '1'), True);
    ShowDriveHome := StrToBoolDef(Ini.ReadString('Layout', 'DriveHome', '1'), True);
    ShowBreadcrumbs := True;
    ShowStatusBar := StrToBoolDef(Ini.ReadString('Layout', 'StatusBar', '1'), True);
    ShowFnBar := StrToBoolDef(Ini.ReadString('Layout', 'FnBar', '1'), True);
    ShowQuickAccess := StrToBoolDef(Ini.ReadString('Layout', 'QuickAccess', '1'), True);
    ShowCommandLine := StrToBoolDef(Ini.ReadString('Layout', 'CommandLine', '1'), True);

    ListFontFamily := Ini.ReadString('Appearance', 'FontFamily', ListFontFamily);
    ListFontSize := Ini.ReadInteger('Appearance', 'FontSize', ListFontSize);
    if ListFontSize < 10 then ListFontSize := 10;
    if ListFontSize > 22 then ListFontSize := 22;
    ShowTabIcons := StrToBoolDef(Ini.ReadString('Appearance', 'TabIcons', '1'), True);
    EqualTabWidth := StrToBoolDef(Ini.ReadString('Appearance', 'EqualTabWidth', '1'), True);
    if Ini.SectionExists('Dock') then
    begin
      DockSeedPending := False;
      DockAlign := TDockAlign(EnsureRange(Ini.ReadInteger('Dock', 'Align', 0), 0, 2));
    end
    else
    begin
      DockSeedPending := True;
      DockAlign := daCenter;
    end;
    DockShowSeparators := StrToBoolDef(Ini.ReadString('Dock', 'ShowSeps', '1'), True);

    AutoStart := StrToBoolDef(Ini.ReadString('Behavior', 'AutoStart', '0'), False);
    SingleInstance := StrToBoolDef(Ini.ReadString('Behavior', 'SingleInstance', '1'), True);

    ThumbCacheEnabled := StrToBoolDef(Ini.ReadString('Performance', 'Thumbs', '1'), True);
    ThumbCacheMaxItems := Ini.ReadInteger('Performance', 'ThumbMaxItems', ThumbCacheMaxItems);
    FileOpMode := TFileOpMode(EnsureRange(Ini.ReadInteger('FileOps', 'Mode', Ord(fomExplorer)), 0, 2));
    if ThumbCacheMaxItems < 50 then ThumbCacheMaxItems := 50;
    if ThumbCacheMaxItems > 4000 then ThumbCacheMaxItems := 4000;

    { Отрицательные Left/Top не отсекать: это левый или верхний монитор. }
    WindowLeft := Ini.ReadInteger('Window', 'Left', WindowLeft);
    WindowTop := Ini.ReadInteger('Window', 'Top', WindowTop);
    WindowPosSaved := Ini.ValueExists('Window', 'Left') or
      Ini.ValueExists('Window', 'Top');
    WindowWidth := Ini.ReadInteger('Window', 'Width', WindowWidth);
    WindowHeight := Ini.ReadInteger('Window', 'Height', WindowHeight);
    if WindowHeight < 625 then
      WindowHeight := 625;
    WindowMaximized := StrToBoolDef(Ini.ReadString('Window', 'Maximized', '0'), False);
    SplitterPos := Ini.ReadFloat('Window', 'SplitterPos', SplitterPos);

    LoadSide(Ini, 'LeftPanel', Left);
    LoadSide(Ini, 'RightPanel', Right);

    var DockCount := Ini.ReadInteger('Dock', 'Count', 0);
    SetLength(DockItems, 0);
    SetLength(DockItemX, 0);
    SetLength(DockKinds, 0);
    SetLength(DockCaptions, 0);
    SetLength(DockIcons, 0);
    SetLength(DockIconLocked, 0);
    if DockCount > 0 then
    begin
      SetLength(DockItems, DockCount);
      SetLength(DockItemX, DockCount);
      SetLength(DockKinds, DockCount);
      SetLength(DockCaptions, DockCount);
      SetLength(DockIcons, DockCount);
      SetLength(DockIconLocked, DockCount);
      var N := 0;
      for var I := 0 to DockCount - 1 do
      begin
        var P := Trim(Ini.ReadString('Dock', 'Item' + IntToStr(I), ''));
        if P <> '' then
        begin
          DockItems[N] := P;
          DockItemX[N] := Ini.ReadFloat('Dock', 'X' + IntToStr(I), 0);
          DockKinds[N] := Ini.ReadInteger('Dock', 'Kind' + IntToStr(I), -1);
          DockCaptions[N] := Ini.ReadString('Dock', 'Caption' + IntToStr(I), '');
          DockIcons[N] := Ini.ReadString('Dock', 'Icon' + IntToStr(I), '');
          DockIconLocked[N] := StrToBoolDef(Ini.ReadString('Dock',
            'IconLock' + IntToStr(I), '0'), False);
          Inc(N);
        end;
      end;
      SetLength(DockItems, N);
      SetLength(DockItemX, N);
      SetLength(DockKinds, N);
      SetLength(DockCaptions, N);
      SetLength(DockIcons, N);
      SetLength(DockIconLocked, N);
    end;
  finally
    Ini.Free;
  end;
end;

procedure UpdateIni(const AFile: string; const AEdit: TProc<TCustomIniFile>);
var
  Ini: TMemIniFile;
begin
  { Один раз прочитали файл, поправили в памяти, один раз записали.
    TIniFile на каждый ключ зовёт WritePrivateProfileString и переписывает файл. }
  if GSettingsSaveLock <> nil then
    GSettingsSaveLock.Enter;
  try
    Ini := TMemIniFile.Create(AFile);
    try
      AEdit(Ini);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  finally
    if GSettingsSaveLock <> nil then
      GSettingsSaveLock.Leave;
  end;
end;

procedure TAppSettings.CommitDockSeed(const APaths, ACaptions: TArray<string>);
const
  KindFolder = 1;
var
  Fn: string;
  I, N: Integer;
begin
  if not DockSeedPending then
    Exit;
  N := 0;
  for I := 0 to High(APaths) do
    if Trim(APaths[I]) <> '' then
      Inc(N);
  if N = 0 then
    Exit;
  SetLength(DockItems, N);
  SetLength(DockItemX, N);
  SetLength(DockKinds, N);
  SetLength(DockCaptions, N);
  SetLength(DockIcons, N);
  SetLength(DockIconLocked, N);
  N := 0;
  for I := 0 to High(APaths) do
  begin
    if Trim(APaths[I]) = '' then
      Continue;
    DockItems[N] := ExcludeTrailingPathDelimiter(Trim(APaths[I]));
    DockItemX[N] := 0;
    DockKinds[N] := KindFolder;
    if (I <= High(ACaptions)) and (Trim(ACaptions[I]) <> '') then
      DockCaptions[N] := ACaptions[I]
    else
      DockCaptions[N] := '';
    DockIcons[N] := '';
    DockIconLocked[N] := False;
    Inc(N);
  end;
  DockAlign := daCenter;
  if FIniSource <> '' then
    Fn := FIniSource
  else
    Fn := FFileName;
  UpdateIni(Fn,
    procedure(Ini: TCustomIniFile)
    var
      J: Integer;
    begin
      Ini.WriteInteger('Dock', 'Align', Ord(daCenter));
      Ini.WriteString('Dock', 'ShowSeps', IniBoolStr(DockShowSeparators));
      Ini.WriteInteger('Dock', 'Count', N);
      for J := 0 to N - 1 do
      begin
        Ini.WriteString('Dock', 'Item' + IntToStr(J), DockItems[J]);
        Ini.WriteFloat('Dock', 'X' + IntToStr(J), 0);
        Ini.WriteInteger('Dock', 'Kind' + IntToStr(J), DockKinds[J]);
        Ini.WriteString('Dock', 'Caption' + IntToStr(J), DockCaptions[J]);
        Ini.WriteString('Dock', 'Icon' + IntToStr(J), '');
        Ini.WriteString('Dock', 'IconLock' + IntToStr(J), '0');
      end;
    end);
  DockSeedPending := False;
end;

procedure SetSettingsIniOverride(const APath: string);
begin
  GSettingsIniOverride := APath;
end;

function ActiveSettingsIni: string;
begin
  if GSettingsIniOverride <> '' then
    Exit(GSettingsIniOverride);
  Result := ExtractFilePath(ParamStr(0)) + 'VibeSetting.ini';
end;

function BehaviorIniPath: string;
begin
  if GSettingsIniOverride <> '' then
    Exit(GSettingsIniOverride);
  Result := ExtractFilePath(ParamStr(0)) + 'VibeSetting.ini';
  if not FileExists(Result) and
     FileExists(ExtractFilePath(ParamStr(0)) + 'TCClone.ini') then
    Result := ExtractFilePath(ParamStr(0)) + 'TCClone.ini';
end;

function FontIniPath: string;
begin
  Result := ActiveSettingsIni;
end;

function ReadFontPhrase: string;
var
  Ini: TIniFile;
begin
  Result := '';
  if not FileExists(FontIniPath) then
    Exit;
  if GSettingsSaveLock <> nil then
    GSettingsSaveLock.Enter;
  try
    Ini := TIniFile.Create(FontIniPath);
    try
      Result := Ini.ReadString('Font', 'Phrase', '');
    finally
      Ini.Free;
    end;
  finally
    if GSettingsSaveLock <> nil then
      GSettingsSaveLock.Leave;
  end;
end;

procedure WriteFontPhrase(const AText: string);
begin
  UpdateIni(FontIniPath,
    procedure(Ini: TCustomIniFile)
    begin
      Ini.WriteString('Font', 'Phrase', AText);
    end);
end;

function SingleInstanceWanted: Boolean;
var
  Ini: TIniFile;
  Path: string;
begin
  Result := True;
  Path := BehaviorIniPath;
  if not FileExists(Path) then
    Exit;
  Ini := TIniFile.Create(Path);
  try
    Result := Ini.ReadString('Behavior', 'SingleInstance', '1') <> '0';
  finally
    Ini.Free;
  end;
end;

procedure TAppSettings.SaveBehavior;
var
  Fn: string;
  Auto, Single: Boolean;
begin
  Fn := FFileName;
  Auto := AutoStart;
  Single := SingleInstance;
  UpdateIni(Fn,
    procedure(Ini: TCustomIniFile)
    begin
      Ini.WriteString('Behavior', 'AutoStart', IniBoolStr(Auto));
      Ini.WriteString('Behavior', 'SingleInstance', IniBoolStr(Single));
    end);
end;

procedure TAppSettings.SaveNetwork;
var
  Fn, Subnet, Hist: string;
begin
  Fn := FFileName;
  Subnet := NetworkLastSubnet;
  Hist := NetworkHistory;
  UpdateIni(Fn,
    procedure(Ini: TCustomIniFile)
    begin
      Ini.WriteString('Network', 'LastSubnet', Subnet);
      Ini.WriteString('Network', 'History', Hist);
    end);
end;

type
  TPrefsSnap = class
  public
    FileName: string;
    Theme: TAppTheme;
    WindowMaterial: TWindowMaterial;
    ColorTint: Integer;
    Transparency: Integer;
    Language: string;
    ShowNetworkButton: Boolean;
    NetworkLastSubnet: string;
    NetworkHistory: string;
    ShowHiddenFiles: Boolean;
    ShowFolderSizes: Boolean;
    ShowDock: Boolean;
    ShowMidBar: Boolean;
    ShowDriveBar: Boolean;
    ShowDriveHome: Boolean;
    ShowStatusBar: Boolean;
    ShowFnBar: Boolean;
    ShowQuickAccess: Boolean;
    ShowCommandLine: Boolean;
    FollowCursor: Boolean;
    MouseSelectMode: TMouseSelectMode;
    ListFontFamily: string;
    ListFontSize: Integer;
    ShowTabIcons: Boolean;
    EqualTabWidth: Boolean;
    DockSeedPending: Boolean;
    DockAlign: TDockAlign;
    DockShowSeparators: Boolean;
    DockItems: TArray<string>;
    DockItemX: TArray<Single>;
    DockKinds: TArray<Integer>;
    DockCaptions: TArray<string>;
    DockIcons: TArray<string>;
    DockIconLocked: TArray<Boolean>;
    AutoStart: Boolean;
    SingleInstance: Boolean;
    FileOpMode: TFileOpMode;
  end;

procedure WriteDockKeys(Ini: TCustomIniFile; AWithAlign: Boolean; AAlign: Integer;
  ASeps: Boolean; const Items: TArray<string>; const Xs: TArray<Single>;
  const Kinds: TArray<Integer>; const Caps, Icons: TArray<string>;
  const Locks: TArray<Boolean>);
var
  I: Integer;
begin
  if AWithAlign then
  begin
    Ini.WriteInteger('Dock', 'Align', AAlign);
    Ini.WriteString('Dock', 'ShowSeps', IniBoolStr(ASeps));
  end;
  Ini.WriteInteger('Dock', 'Count', Length(Items));
  for I := 0 to High(Items) do
  begin
    Ini.WriteString('Dock', 'Item' + IntToStr(I), Items[I]);
    if I <= High(Xs) then
      Ini.WriteFloat('Dock', 'X' + IntToStr(I), Xs[I])
    else
      Ini.WriteFloat('Dock', 'X' + IntToStr(I), 0);
    if I <= High(Kinds) then
      Ini.WriteInteger('Dock', 'Kind' + IntToStr(I), Kinds[I])
    else
      Ini.WriteInteger('Dock', 'Kind' + IntToStr(I), -1);
    if I <= High(Caps) then
      Ini.WriteString('Dock', 'Caption' + IntToStr(I), Caps[I])
    else
      Ini.WriteString('Dock', 'Caption' + IntToStr(I), '');
    if I <= High(Icons) then
      Ini.WriteString('Dock', 'Icon' + IntToStr(I), Icons[I])
    else
      Ini.WriteString('Dock', 'Icon' + IntToStr(I), '');
    if (I <= High(Locks)) and Locks[I] then
      Ini.WriteString('Dock', 'IconLock' + IntToStr(I), '1')
    else
      Ini.WriteString('Dock', 'IconLock' + IntToStr(I), '0');
  end;
end;

function CapturePrefs(S: TAppSettings): TPrefsSnap;
begin
  Result := TPrefsSnap.Create;
  Result.FileName := S.FFileName;
  Result.Theme := S.Theme;
  Result.WindowMaterial := S.WindowMaterial;
  Result.ColorTint := S.ColorTint;
  Result.Transparency := S.Transparency;
  Result.Language := NormalizeLanguage(S.Language);
  Result.ShowNetworkButton := S.ShowNetworkButton;
  Result.NetworkLastSubnet := S.NetworkLastSubnet;
  Result.NetworkHistory := S.NetworkHistory;
  Result.ShowHiddenFiles := S.ShowHiddenFiles;
  Result.ShowFolderSizes := S.ShowFolderSizes;
  Result.ShowDock := S.ShowDock;
  Result.ShowMidBar := S.ShowMidBar;
  Result.ShowDriveBar := S.ShowDriveBar;
  Result.ShowDriveHome := S.ShowDriveHome;
  Result.ShowStatusBar := S.ShowStatusBar;
  Result.ShowFnBar := S.ShowFnBar;
  Result.ShowQuickAccess := S.ShowQuickAccess;
  Result.ShowCommandLine := S.ShowCommandLine;
  Result.FollowCursor := S.FollowCursor;
  Result.MouseSelectMode := S.MouseSelectMode;
  Result.ListFontFamily := S.ListFontFamily;
  Result.ListFontSize := S.ListFontSize;
  Result.ShowTabIcons := S.ShowTabIcons;
  Result.EqualTabWidth := S.EqualTabWidth;
  Result.DockSeedPending := S.DockSeedPending;
  Result.DockAlign := S.DockAlign;
  Result.DockShowSeparators := S.DockShowSeparators;
  Result.DockItems := Copy(S.DockItems);
  Result.DockItemX := Copy(S.DockItemX);
  Result.DockKinds := Copy(S.DockKinds);
  Result.DockCaptions := Copy(S.DockCaptions);
  Result.DockIcons := Copy(S.DockIcons);
  Result.DockIconLocked := Copy(S.DockIconLocked);
  Result.AutoStart := S.AutoStart;
  Result.SingleInstance := S.SingleInstance;
  Result.FileOpMode := S.FileOpMode;
end;

procedure WritePrefs(Snap: TPrefsSnap);
begin
  UpdateIni(Snap.FileName,
    procedure(Ini: TCustomIniFile)
    begin
      Ini.WriteInteger('Main', 'Theme', Ord(Snap.Theme));
      Ini.WriteString('Main', 'Language', Snap.Language);
      Ini.WriteInteger('Appearance', 'Material', Ord(Snap.WindowMaterial));
      if (Snap.ColorTint < 0) or (Snap.ColorTint > 359) then
        Ini.WriteInteger('Appearance', 'ColorHue', -1)
      else
        Ini.WriteInteger('Appearance', 'ColorHue', Snap.ColorTint);
      if (Snap.Transparency < 0) or (Snap.Transparency > 100) then
        Ini.WriteInteger('Appearance', 'Transparency', 0)
      else
        Ini.WriteInteger('Appearance', 'Transparency', Snap.Transparency);
      Ini.WriteString('Main', 'ShowNetwork', IniBoolStr(Snap.ShowNetworkButton));
      Ini.WriteString('Network', 'LastSubnet', Snap.NetworkLastSubnet);
      Ini.WriteString('Network', 'History', Snap.NetworkHistory);
      Ini.WriteString('Main', 'ShowHidden', IniBoolStr(Snap.ShowHiddenFiles));
      Ini.WriteString('Main', 'ShowFolderSize', IniBoolStr(Snap.ShowFolderSizes));
      Ini.WriteString('Layout', 'Dock', IniBoolStr(Snap.ShowDock));
      Ini.WriteString('Layout', 'MidBar', IniBoolStr(Snap.ShowMidBar));
      Ini.WriteString('Layout', 'DriveBar', IniBoolStr(Snap.ShowDriveBar));
      Ini.WriteString('Layout', 'DriveHome', IniBoolStr(Snap.ShowDriveHome));
      Ini.WriteString('Layout', 'StatusBar', IniBoolStr(Snap.ShowStatusBar));
      Ini.WriteString('Layout', 'FnBar', IniBoolStr(Snap.ShowFnBar));
      Ini.WriteString('Layout', 'QuickAccess', IniBoolStr(Snap.ShowQuickAccess));
      Ini.WriteString('Layout', 'CommandLine', IniBoolStr(Snap.ShowCommandLine));
      Ini.WriteString('View', 'FollowCursor', IniBoolStr(Snap.FollowCursor));
      if Snap.MouseSelectMode = msmExplorer then
        Ini.WriteString('Select', 'MouseMode', 'explorer')
      else
        Ini.WriteString('Select', 'MouseMode', 'vibe');
      Ini.WriteString('Appearance', 'FontFamily', Snap.ListFontFamily);
      Ini.WriteInteger('Appearance', 'FontSize', Snap.ListFontSize);
      Ini.WriteString('Appearance', 'TabIcons', IniBoolStr(Snap.ShowTabIcons));
      Ini.WriteString('Appearance', 'EqualTabWidth', IniBoolStr(Snap.EqualTabWidth));
      if not Snap.DockSeedPending then
        WriteDockKeys(Ini, True, Ord(Snap.DockAlign), Snap.DockShowSeparators,
          Snap.DockItems, Snap.DockItemX, Snap.DockKinds, Snap.DockCaptions,
          Snap.DockIcons, Snap.DockIconLocked);
      Ini.WriteString('Behavior', 'AutoStart', IniBoolStr(Snap.AutoStart));
      Ini.WriteString('Behavior', 'SingleInstance', IniBoolStr(Snap.SingleInstance));
      Ini.WriteInteger('FileOps', 'Mode', Ord(Snap.FileOpMode));
    end);
end;

procedure TAppSettings.SaveSettings;
var
  Snap: TPrefsSnap;
begin
  Snap := CapturePrefs(Self);
  try
    WritePrefs(Snap);
  finally
    Snap.Free;
  end;
  if FPrefsLock = nil then
  begin
    FPrefsDirty := False;
    Exit;
  end;
  FPrefsLock.Enter;
  try
    if not FPrefsWorker then
      FPrefsDirty := False;
  finally
    FPrefsLock.Leave;
  end;
end;

procedure TAppSettings.SaveSession;
var
  Fn, Hist: string;
  Active, Wl, Wt, Ww, Wh: Integer;
  Maxed, Seed: Boolean;
  Split: Single;
  LeftS, RightS: TSideState;
  Items, Caps, Icons: TArray<string>;
  Xs: TArray<Single>;
  Kinds: TArray<Integer>;
  Locks: TArray<Boolean>;
begin
  Fn := FFileName;
  Active := ActivePanel;
  Hist := string.Join(#9, SearchHistory);
  Wl := WindowLeft;
  Wt := WindowTop;
  Ww := WindowWidth;
  Wh := WindowHeight;
  Maxed := WindowMaximized;
  Split := SplitterPos;
  LeftS := Left;
  RightS := Right;
  Seed := DockSeedPending;
  Items := Copy(DockItems);
  Xs := Copy(DockItemX);
  Kinds := Copy(DockKinds);
  Caps := Copy(DockCaptions);
  Icons := Copy(DockIcons);
  Locks := Copy(DockIconLocked);
  UpdateIni(Fn,
    procedure(Ini: TCustomIniFile)
    begin
      Ini.WriteInteger('Main', 'ActivePanel', Active);
      Ini.WriteString('Main', 'SearchHistory', Hist);
      { Отрицательные Left/Top пишем как есть. }
      Ini.WriteInteger('Window', 'Left', Wl);
      Ini.WriteInteger('Window', 'Top', Wt);
      Ini.WriteInteger('Window', 'Width', Ww);
      Ini.WriteInteger('Window', 'Height', Wh);
      Ini.WriteString('Window', 'Maximized', IniBoolStr(Maxed));
      Ini.WriteFloat('Window', 'SplitterPos', Split);
      WriteSide(Ini, 'LeftPanel', LeftS);
      WriteSide(Ini, 'RightPanel', RightS);
      if not Seed then
        WriteDockKeys(Ini, False, 0, False, Items, Xs, Kinds, Caps, Icons, Locks);
    end);
end;

procedure TAppSettings.SaveSessionAsync;
var
  Fn, Hist: string;
  Active, Wl, Wt, Ww, Wh: Integer;
  Maxed, Seed: Boolean;
  Split: Single;
  LeftS, RightS: TSideState;
  Items, Caps, Icons: TArray<string>;
  Xs: TArray<Single>;
  Kinds: TArray<Integer>;
  Locks: TArray<Boolean>;
begin
  Fn := FFileName;
  Active := ActivePanel;
  Hist := string.Join(#9, SearchHistory);
  Wl := WindowLeft;
  Wt := WindowTop;
  Ww := WindowWidth;
  Wh := WindowHeight;
  Maxed := WindowMaximized;
  Split := SplitterPos;
  LeftS := Left;
  RightS := Right;
  Seed := DockSeedPending;
  Items := Copy(DockItems);
  Xs := Copy(DockItemX);
  Kinds := Copy(DockKinds);
  Caps := Copy(DockCaptions);
  Icons := Copy(DockIcons);
  Locks := Copy(DockIconLocked);
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        UpdateIni(Fn,
          procedure(Ini: TCustomIniFile)
          begin
            Ini.WriteInteger('Main', 'ActivePanel', Active);
            Ini.WriteString('Main', 'SearchHistory', Hist);
            Ini.WriteInteger('Window', 'Left', Wl);
            Ini.WriteInteger('Window', 'Top', Wt);
            Ini.WriteInteger('Window', 'Width', Ww);
            Ini.WriteInteger('Window', 'Height', Wh);
            Ini.WriteString('Window', 'Maximized', IniBoolStr(Maxed));
            Ini.WriteFloat('Window', 'SplitterPos', Split);
            WriteSide(Ini, 'LeftPanel', LeftS);
            WriteSide(Ini, 'RightPanel', RightS);
            if not Seed then
              WriteDockKeys(Ini, False, 0, False, Items, Xs, Kinds, Caps, Icons, Locks);
          end);
      except
      end;
    end).Start;
end;

procedure TAppSettings.SaveSearchHistory;
var
  Fn, Hist: string;
begin
  Fn := FFileName;
  Hist := string.Join(#9, SearchHistory);
  UpdateIni(Fn,
    procedure(Ini: TCustomIniFile)
    begin
      Ini.WriteString('Main', 'SearchHistory', Hist);
    end);
end;

procedure TAppSettings.SaveDockAsync;
var
  Fn: string;
  Items: TArray<string>;
  Xs: TArray<Single>;
  Kinds: TArray<Integer>;
  Caps, Icons: TArray<string>;
  Locks: TArray<Boolean>;
  AlignOrd: Integer;
  Seps: Boolean;
begin
  if DockSeedPending then
    Exit;
  Fn := FFileName;
  Items := Copy(DockItems);
  Xs := Copy(DockItemX);
  Kinds := Copy(DockKinds);
  Caps := Copy(DockCaptions);
  Icons := Copy(DockIcons);
  Locks := Copy(DockIconLocked);
  AlignOrd := Ord(DockAlign);
  Seps := DockShowSeparators;

  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        UpdateIni(Fn,
          procedure(Ini: TCustomIniFile)
          begin
            WriteDockKeys(Ini, True, AlignOrd, Seps, Items, Xs, Kinds, Caps,
              Icons, Locks);
          end);
      except
      end;
    end).Start;
end;


function TAppSettings.PrefsDirty: Boolean;
begin
  if FPrefsLock = nil then
    Exit(FPrefsDirty);
  FPrefsLock.Enter;
  try
    Result := FPrefsDirty or FPrefsWorker or (FPending <> nil);
  finally
    FPrefsLock.Leave;
  end;
end;

procedure TAppSettings.MarkPrefsDirty;
begin
  if FPrefsLock = nil then
  begin
    FPrefsDirty := True;
    Exit;
  end;
  FPrefsLock.Enter;
  try
    FPrefsDirty := True;
  finally
    FPrefsLock.Leave;
  end;
end;

procedure TAppSettings.PrefsWorker;
var
  Snap: TPrefsSnap;
  OK, Again: Boolean;
begin
  try
    repeat
      FPrefsLock.Enter;
      try
        Snap := TPrefsSnap(FPending);
        FPending := nil;
      finally
        FPrefsLock.Leave;
      end;
      OK := Snap = nil;
      if Snap <> nil then
      begin
        try
          try
            WritePrefs(Snap);
            OK := True;
          except
            OK := False;
          end;
        finally
          Snap.Free;
        end;
      end;
      FPrefsLock.Enter;
      try
        Again := FPending <> nil;
        if not Again then
        begin
          FPrefsWorker := False;
          if OK then
            FPrefsDirty := False;
          if FPrefsEvent <> nil then
            FPrefsEvent.SetEvent;
        end;
      finally
        FPrefsLock.Leave;
      end;
    until not Again;
  except
    if FPrefsLock <> nil then
    begin
      FPrefsLock.Enter;
      try
        FPrefsWorker := False;
        if FPrefsEvent <> nil then
          FPrefsEvent.SetEvent;
      finally
        FPrefsLock.Leave;
      end;
    end;
  end;
end;

procedure TAppSettings.SaveAsync;
var
  Snap: TPrefsSnap;
  Start: Boolean;
begin
  Snap := CapturePrefs(Self);
  if FPrefsLock = nil then
  begin
    try
      WritePrefs(Snap);
    finally
      Snap.Free;
    end;
    FPrefsDirty := False;
    Exit;
  end;
  FPrefsLock.Enter;
  try
    FPending.Free;
    FPending := Snap;
    FPrefsDirty := True;
    Start := not FPrefsWorker;
    FPrefsWorker := True;
    if FPrefsEvent <> nil then
      FPrefsEvent.ResetEvent;
  finally
    FPrefsLock.Leave;
  end;
  if Start then
    TThread.CreateAnonymousThread(
      procedure
      begin
        PrefsWorker;
      end).Start;
end;

procedure TAppSettings.FlushPrefs;
begin
  if not PrefsDirty then
    Exit;
  SaveAsync;
  if FPrefsEvent <> nil then
    FPrefsEvent.WaitFor(4000);
  if PrefsDirty then
  try
    SaveSettings;
  except
  end;
end;


end.

