unit uAppSettings;

{
  Хранение и загрузка пользовательских настроек в VibeSetting.ini рядом с exe.
  Поддерживаются вкладки обеих панелей, вид/зум/сортировка каждой вкладки
  и геометрия окна. Старый формат (один Path на панель) читается как одна вкладка.
}

interface

uses
  System.SysUtils, System.IniFiles, System.Classes, System.Math,
  System.SyncObjs, System.Threading;

type
  TAppTheme = (atSystem, atLight, atDark);
  TWindowMaterial = (wmNormal, wmAcrylic, wmMica);
  TPanelViewMode = (vmDetails, vmTiles);
  TDockAlign = (daLeft, daCenter, daFree);
  TFileOpMode = (fomQuiet, fomExplorer, fomVibe);

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
    function BoolToStr(B: Boolean): string;
    function StrToBoolDef(const S: string; Def: Boolean): Boolean;
    function DefaultTab(const APath: string): TTabState;
    procedure LoadSide(Ini: TIniFile; const ASection: string; var ASide: TSideState);
    procedure SaveSide(Ini: TIniFile; const ASection: string; const ASide: TSideState);
  public
    Theme: TAppTheme;
    WindowMaterial: TWindowMaterial;
    QuickViewEnabled: Boolean;
    WindowAnimate: Boolean;
    ShowNetworkButton: Boolean;
    ShowHiddenFiles: Boolean;
    ActivePanel: Integer; // 0 = left, 1 = right

    ShowDock: Boolean;
    ShowMidBar: Boolean;
    ShowDriveBar: Boolean;
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

    ThumbCacheEnabled: Boolean;
    ThumbCacheMaxItems: Integer;
    FileOpMode: TFileOpMode;

    WindowLeft, WindowTop, WindowWidth, WindowHeight: Integer;
    WindowMaximized: Boolean;
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
    procedure Load;
    procedure Save;
    procedure SaveSearchHistory;
    { Только секция Dock — в фоне, без блокировки UI. }
    procedure SaveDockAsync;
    { Полный Save в фоне (после Collect на UI). }
    procedure SaveAsync;
  end;

implementation

var
  GSettingsSaveLock: TCriticalSection;

const
  DEFAULT_ZOOM = 100;

constructor TAppSettings.Create;
var
  Root: string;
begin
  inherited Create;
  if GSettingsSaveLock = nil then
    GSettingsSaveLock := TCriticalSection.Create;
  FFileName := ExtractFilePath(ParamStr(0)) + 'VibeSetting.ini';

  Theme := atSystem;
  WindowMaterial := wmNormal;
  QuickViewEnabled := True;
  WindowAnimate := True;
  ShowNetworkButton := False;
  ShowHiddenFiles := False;
  ActivePanel := 0;

  ShowDock := True;
  ShowMidBar := True;
  ShowDriveBar := True;
  ShowBreadcrumbs := True;
  ShowStatusBar := True;
  ShowFnBar := True;
  ShowQuickAccess := True;
  ShowCommandLine := False;

  ListFontFamily := 'Segoe UI';
  ListFontSize := 13;
  ShowTabIcons := True;
  EqualTabWidth := True;
  DockAlign := daLeft;
  DockShowSeparators := True;

  ThumbCacheEnabled := True;
  ThumbCacheMaxItems := 400;
  FileOpMode := fomVibe;

  WindowLeft := 100;
  WindowTop := 100;
  WindowWidth := 1200;
  WindowHeight := 625;
  WindowMaximized := False;
  SplitterPos := 0.5;

  Root := ExtractFileDrive(ParamStr(0)) + '\';
  Left.ActiveTab := 0;
  SetLength(Left.Tabs, 1);
  Left.Tabs[0] := DefaultTab(Root);
  Right := Left;
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

function TAppSettings.BoolToStr(B: Boolean): string;
begin
  if B then Result := '1' else Result := '0';
end;

function TAppSettings.StrToBoolDef(const S: string; Def: Boolean): Boolean;
begin
  if S = '1' then Result := True
  else if S = '0' then Result := False
  else Result := Def;
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
      ASide.Tabs[I] := DefaultTab(ExtractFileDrive(ParamStr(0)) + '\');
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
    ASide.Tabs[0] := DefaultTab(ExtractFileDrive(ParamStr(0)) + '\');
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

procedure TAppSettings.SaveSide(Ini: TIniFile; const ASection: string; const ASide: TSideState);
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
    Ini.WriteString(ASection, 'SortAsc', BoolToStr(ASide.Tabs[ASide.ActiveTab].SortAsc));
  end;

  for I := 0 to High(ASide.Tabs) do
  begin
    TabSec := ASection + 'Tab' + IntToStr(I);
    Ini.WriteString(TabSec, 'Path', ASide.Tabs[I].Path);
    Ini.WriteInteger(TabSec, 'ViewMode', Ord(ASide.Tabs[I].ViewMode));
    Ini.WriteInteger(TabSec, 'ZoomDetails', ASide.Tabs[I].ZoomDetails);
    Ini.WriteInteger(TabSec, 'ZoomTiles', ASide.Tabs[I].ZoomTiles);
    Ini.WriteInteger(TabSec, 'SortField', ASide.Tabs[I].SortField);
    Ini.WriteString(TabSec, 'SortAsc', BoolToStr(ASide.Tabs[I].SortAsc));
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
  Source := FFileName;
  if not FileExists(Source) then
  begin
    Source := ExtractFilePath(ParamStr(0)) + 'TCClone.ini';
    if not FileExists(Source) then
      Exit;
  end;

  Ini := TIniFile.Create(Source);
  try
    Theme := TAppTheme(Ini.ReadInteger('Main', 'Theme', Ord(atSystem)));
    WindowMaterial := TWindowMaterial(EnsureRange(
      Ini.ReadInteger('Appearance', 'Material', Ord(wmNormal)), 0, 2));
    QuickViewEnabled := True;
    WindowAnimate := True;
    ShowNetworkButton := StrToBoolDef(Ini.ReadString('Main', 'ShowNetwork', '0'), False);
    ShowHiddenFiles := StrToBoolDef(Ini.ReadString('Main', 'ShowHidden', '0'), False);
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
    ShowBreadcrumbs := True;
    ShowStatusBar := StrToBoolDef(Ini.ReadString('Layout', 'StatusBar', '1'), True);
    ShowFnBar := StrToBoolDef(Ini.ReadString('Layout', 'FnBar', '1'), True);
    ShowQuickAccess := StrToBoolDef(Ini.ReadString('Layout', 'QuickAccess', '1'), True);
    ShowCommandLine := StrToBoolDef(Ini.ReadString('Layout', 'CommandLine', '0'), False);

    ListFontFamily := Ini.ReadString('Appearance', 'FontFamily', ListFontFamily);
    ListFontSize := Ini.ReadInteger('Appearance', 'FontSize', ListFontSize);
    if ListFontSize < 10 then ListFontSize := 10;
    if ListFontSize > 22 then ListFontSize := 22;
    ShowTabIcons := StrToBoolDef(Ini.ReadString('Appearance', 'TabIcons', '1'), True);
    EqualTabWidth := StrToBoolDef(Ini.ReadString('Appearance', 'EqualTabWidth', '1'), True);
    DockAlign := TDockAlign(EnsureRange(Ini.ReadInteger('Dock', 'Align', 0), 0, 2));
    DockShowSeparators := StrToBoolDef(Ini.ReadString('Dock', 'ShowSeps', '1'), True);

    ThumbCacheEnabled := StrToBoolDef(Ini.ReadString('Performance', 'Thumbs', '1'), True);
    ThumbCacheMaxItems := Ini.ReadInteger('Performance', 'ThumbMaxItems', ThumbCacheMaxItems);
    FileOpMode := TFileOpMode(EnsureRange(Ini.ReadInteger('FileOps', 'Mode', Ord(fomVibe)), 0, 2));
    if ThumbCacheMaxItems < 50 then ThumbCacheMaxItems := 50;
    if ThumbCacheMaxItems > 4000 then ThumbCacheMaxItems := 4000;

    WindowLeft := Ini.ReadInteger('Window', 'Left', WindowLeft);
    WindowTop := Ini.ReadInteger('Window', 'Top', WindowTop);
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

procedure TAppSettings.Save;
var
  Ini: TIniFile;
begin
  if GSettingsSaveLock <> nil then
    GSettingsSaveLock.Enter;
  try
  Ini := TIniFile.Create(FFileName);
  try
    Ini.WriteInteger('Main', 'Theme', Ord(Theme));
    Ini.WriteInteger('Appearance', 'Material', Ord(WindowMaterial));
    Ini.WriteString('Main', 'QuickView', '1');
    Ini.WriteString('Main', 'WindowAnim', '1');
    Ini.WriteString('Main', 'ShowNetwork', BoolToStr(ShowNetworkButton));
    Ini.WriteString('Main', 'ShowHidden', BoolToStr(ShowHiddenFiles));
    Ini.WriteInteger('Main', 'ActivePanel', ActivePanel);
    Ini.WriteString('Main', 'SearchHistory', string.Join(#9, SearchHistory));

    Ini.WriteString('Layout', 'Dock', BoolToStr(ShowDock));
    Ini.WriteString('Layout', 'MidBar', BoolToStr(ShowMidBar));
    Ini.WriteString('Layout', 'DriveBar', BoolToStr(ShowDriveBar));
    Ini.WriteString('Layout', 'Breadcrumbs', BoolToStr(ShowBreadcrumbs));
    Ini.WriteString('Layout', 'StatusBar', BoolToStr(ShowStatusBar));
    Ini.WriteString('Layout', 'FnBar', BoolToStr(ShowFnBar));
    Ini.WriteString('Layout', 'QuickAccess', BoolToStr(ShowQuickAccess));
    Ini.WriteString('Layout', 'CommandLine', BoolToStr(ShowCommandLine));

    Ini.WriteString('Appearance', 'FontFamily', ListFontFamily);
    Ini.WriteInteger('Appearance', 'FontSize', ListFontSize);
    Ini.WriteString('Appearance', 'TabIcons', BoolToStr(ShowTabIcons));
    Ini.WriteString('Appearance', 'EqualTabWidth', BoolToStr(EqualTabWidth));
    Ini.WriteInteger('Dock', 'Align', Ord(DockAlign));
    Ini.WriteString('Dock', 'ShowSeps', BoolToStr(DockShowSeparators));

    Ini.WriteString('Performance', 'Thumbs', BoolToStr(ThumbCacheEnabled));
    Ini.WriteInteger('Performance', 'ThumbMaxItems', ThumbCacheMaxItems);
    Ini.WriteInteger('FileOps', 'Mode', Ord(FileOpMode));

    Ini.WriteInteger('Window', 'Left', WindowLeft);
    Ini.WriteInteger('Window', 'Top', WindowTop);
    Ini.WriteInteger('Window', 'Width', WindowWidth);
    Ini.WriteInteger('Window', 'Height', WindowHeight);
    Ini.WriteString('Window', 'Maximized', BoolToStr(WindowMaximized));
    Ini.WriteFloat('Window', 'SplitterPos', SplitterPos);

    SaveSide(Ini, 'LeftPanel', Left);
    SaveSide(Ini, 'RightPanel', Right);

    Ini.WriteInteger('Dock', 'Count', Length(DockItems));
    for var I := 0 to High(DockItems) do
    begin
      Ini.WriteString('Dock', 'Item' + IntToStr(I), DockItems[I]);
      if I <= High(DockItemX) then
        Ini.WriteFloat('Dock', 'X' + IntToStr(I), DockItemX[I])
      else
        Ini.WriteFloat('Dock', 'X' + IntToStr(I), 0);
      if I <= High(DockKinds) then
        Ini.WriteInteger('Dock', 'Kind' + IntToStr(I), DockKinds[I])
      else
        Ini.WriteInteger('Dock', 'Kind' + IntToStr(I), -1);
      if I <= High(DockCaptions) then
        Ini.WriteString('Dock', 'Caption' + IntToStr(I), DockCaptions[I])
      else
        Ini.WriteString('Dock', 'Caption' + IntToStr(I), '');
      if I <= High(DockIcons) then
        Ini.WriteString('Dock', 'Icon' + IntToStr(I), DockIcons[I])
      else
        Ini.WriteString('Dock', 'Icon' + IntToStr(I), '');
      if (I <= High(DockIconLocked)) and DockIconLocked[I] then
        Ini.WriteString('Dock', 'IconLock' + IntToStr(I), '1')
      else
        Ini.WriteString('Dock', 'IconLock' + IntToStr(I), '0');
    end;
  finally
    Ini.Free;
  end;
  finally
    if GSettingsSaveLock <> nil then
      GSettingsSaveLock.Leave;
  end;
end;


function SettingsBoolStr(B: Boolean): string;
begin
  if B then
    Result := '1'
  else
    Result := '0';
end;

procedure TAppSettings.SaveSearchHistory;
var
  Ini: TIniFile;
begin
  if GSettingsSaveLock <> nil then
    GSettingsSaveLock.Enter;
  try
    Ini := TIniFile.Create(FFileName);
    try
      Ini.WriteString('Main', 'SearchHistory', string.Join(#9, SearchHistory));
    finally
      Ini.Free;
    end;
  finally
    if GSettingsSaveLock <> nil then
      GSettingsSaveLock.Leave;
  end;
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
    var
      Ini: TIniFile;
      I: Integer;
    begin
      if GSettingsSaveLock = nil then
        Exit;
      GSettingsSaveLock.Enter;
      try
        Ini := TIniFile.Create(Fn);
        try
          Ini.WriteInteger('Dock', 'Align', AlignOrd);
          Ini.WriteString('Dock', 'ShowSeps', SettingsBoolStr(Seps));
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
        finally
          Ini.Free;
        end;
      finally
        GSettingsSaveLock.Leave;
      end;
    end).Start;
end;


procedure TAppSettings.SaveAsync;
begin
  { Данные уже в полях Self; пишем под тем же lock, что и Save. }
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        Save;
      except
        { диск/права — не роняем UI }
      end;
    end).Start;
end;


end.

