unit uFilePanel;

interface

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.ShellAPI, Vcl.Graphics,
  {$ENDIF}
  System.IOUtils, System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Generics.Collections, System.Math, System.Masks, System.StrUtils,
  System.Rtti, System.SyncObjs,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Objects, FMX.Layouts,
  FMX.StdCtrls, FMX.Graphics, FMX.Ani, FMX.Surfaces, FMX.Platform,
  FMX.TextLayout,
  uFileModel, uThemeManager, uThumbCache, uIconCache, uMetaCache, uAppSettings, UCoreEngine,
  uCustomScrollbar, uCustomTabs, uFluentChrome, uFluentEdit, uFilePreview,
  FileSelectionManager, uFileOps,
  uDirWatcher, uDriveBar
  {$IFDEF MSWINDOWS}, uWinFileDrag, uWinShellMenu, uClipboardImage, FMX.Platform.Win{$ENDIF};

procedure OpenFileWithDefaultApp(const APath: string);

type
  TFileDragDropHook = reference to function(const AScreen: TPointF;
    const APaths: TArray<string>): Boolean;

procedure RegisterFileDragDropHook(const AHook: TFileDragDropHook);
function FileDragIsActive: Boolean;
function PeekFileDragPaths: TArray<string>;

type
  TFilePanel = class;

  TQuickViewEvent = procedure(Sender: TObject; const APath: string) of object;
  TPathChangedEvent = procedure(Sender: TObject; const APath: string) of object;
  TPanelCopyMoveEvent = procedure(Sender: TObject; const ADest: string;
    const ASources: TArray<string>; AMove: Boolean; ASourcePanel: TFilePanel) of object;

  TDateColMode = (dcmHidden, dcmShort, dcmMed, dcmFull);

  TFileTab = record
    Path: string;
    ContainerLayout: TLayout;
    ScrollBox: TVertScrollBox;
    BgRect: TRectangle;
    PaintBox: TPaintBox;
    LastVisitedPath: string;
    History: TArray<string>;
    HistoryIndex: Integer;
    Scrollbar: TCustomFileScrollbar;
    Entries: uFileModel.TFileEntryList;
    SelectedIndices: TList<Integer>;
    AnchorIndex: Integer;
    ViewMode: TPanelViewMode;
    ZoomDetails: Integer;
    ZoomTiles: Integer;
    SortField: TSortField;
    SortAsc: Boolean;
    CursorIndex: Integer;
    CursorPath: string;
    Loaded: Boolean;
    Stale: Boolean;
    BranchView: Boolean;
    SearchView: Boolean;
    Watcher: TDirWatcher;
    Loading: Boolean;
    LoadQueued: Boolean;
    LoadGen: Integer;
    LoadTick: Cardinal;
    LoadSeen: Integer;
    LoadSeenWatch: Integer;
    Partial: Boolean;
    AutoRetryUsed: Boolean;
    LoadError: string;
    LoadThread: TThread;
    LoadPath: string;
    RefreshPending: Boolean;
    PendingSelect: string;
    PendingKeepSel: Boolean;
    Offline: Boolean;
  end;

  TFilePanel = class(TLayout, ISelectionAdapter)
  private
    FCard: TRectangle;
    FChromeStack: TLayout;
    FPathAndHeader: TRectangle;
    FTabsBar: TCustomTabsBar;
    FDriveBar: TDriveBar;
    FTopBar: TRectangle;
    FBtnBack: TFluentButton;
    FBtnForward: TFluentButton;
    FHistorySilent: Boolean;
    FCrumbsBox: THorzScrollBox;
    FCrumbsHost: TLayout;
    FPathEdit: TFluentEdit;
    FCrumbPaths: TStringList;
    FCrumbHoverIdx: Integer;
    FEndingPathEdit: Boolean;
    FLongClickTimer: TTimer;
    FDragPollTimer: TTimer;
    FSelectScrollTimer: TTimer;
    FLongClickArmed: Boolean;
    FLongClickBtn: TMouseButton;
    FLongClickIdx: Integer;
    FLongClickPt: TPointF;
    FPendingRightSelect: Boolean;
    FSuppressSelectUntilUp: Boolean;
    FRenameEdit: TFluentEdit;
    FRenamePath: string;
    FRenameApplying: Boolean;
    FHeaderBar: TRectangle;
    FHeaderPaint: TPaintBox;
    FHoverIndex: Integer;
    FDragReady: Boolean;
    FDragStart: TPointF;
    FDragPaths: TArray<string>;
    FDropHighlightIndex: Integer;
    FDropTargetHot: Boolean;
    FThumbTimer: TTimer;
    FThumbGen: Integer;
    FIconGen: Integer;
    FMetaGen: Integer;
    FDirChangeTimer: TTimer;
    FDirChangePath: string;
    FTabs: TList<TFileTab>;
    FActiveTabIndex: Integer;
    FColors: TThemeColors;
    FActive: Boolean;
    FLoadWatchTimer: TTimer;
    FNetPulseTimer: TTimer;
    FNetPulseBusy: Boolean;
    FScrollTick: Cardinal;
    FRetryBtn: TFluentButton;
    FParentRetryRect: TRectF;
    FRefreshPending: Boolean;
    FPendingCursorIndex: Integer;
    FPendingRenamePath: string;
    FHistoryClearSel: Boolean;
    FKeepSelPaths: TStringList;
    FKeepSelFocus: string;
    FOnQuickView: TQuickViewEvent;
    FOnPathChanged: TPathChangedEvent;
    FOnActivate: TNotifyEvent;
    FOnCursorChange: TNotifyEvent;
    FOnListReady: TNotifyEvent;
    FOnDropCopyMove: TPanelCopyMoveEvent;
    FPreview: TFilePreview;
    FDestroying: Boolean;
    FShotJob: TObject;
    FPendingShot: string;
    FDeferDirLoad: Boolean;
    FWatchEnabled: Boolean;
    FListReadyFired: Boolean;
    FShowHiddenFiles: Boolean;
    FShowDriveBar: Boolean;
    FNameFilter: string;
    FFilterReady: Boolean;
    FFilterMap: TList<Integer>;
    FListFontSize: Integer;
    FColFs: Single;
    FColPad: Single;
    FColGap: Single;
    FColMinName: Single;
    FColTypeW: Single;
    FColSizeW: Single;
    FColThisPCSizeW: Single;
    FColDateFullW: Single;
    FColDateMedW: Single;
    FColDateShortW: Single;
    FColLayoutW: Single;
    FLongestType: string;
    FColShowType: Boolean;
    FColShowSize: Boolean;
    FColTwoLine: Boolean;
    FColThisPC: Boolean;
    FColDateMode: TDateColMode;
    FColMeasure: TTextLayout;
    FNameLayout: TTextLayout;
    FDriveLast: TDictionary<string, string>;

    // Менеджер выделений
    FSelectionManager: TFileSelectionManager;

    // Статус-бар и элементы управления
    FFooterPanel: TRectangle;
    FStatusText: TText;
    FBtnDetails: TRectangle;
    FBtnTiles: TRectangle;
    FBtnQuickView: TRectangle;

    // Реализация интерфейса ISelectionAdapter
    function GetItemCount: Integer;
    function IsItemSelected(AIndex: Integer): Boolean;
    procedure SetItemSelected(AIndex: Integer; ASelected: Boolean);
    function GetItemExtension(AIndex: Integer): string;
    function GetItemName(AIndex: Integer): string;
    function IsItemDirectory(AIndex: Integer): Boolean;
    function VisualToActual(AIndex: Integer; out AActual: Integer): Boolean;
    function VisualCount: Integer;
    function VisualFromActual(AActual: Integer): Integer;
    function EntryMatchesFilter(const AEntry: TFileEntry): Boolean;
    procedure CaptureFilterIdentity(APaths: TStringList; out AFocus: string);
    procedure RebuildFilterMap;
    procedure RestoreFilterIdentity(APaths: TStringList; const AFocus: string;
      AJump, ARebuild: Boolean);
    procedure SuspendNameFilter;
    procedure CommitNameFilter(AJump: Boolean);

    // Активные ссылки на данные текущей активной вкладки
    function GetCurrentEntries: uFileModel.TFileEntryList;
    function GetCurrentSelectedIndices: TList<Integer>;
    function GetCurrentViewMode: TPanelViewMode;
    procedure SetCurrentViewMode(Value: TPanelViewMode);
    function GetCurrentZoomPercent: Integer;
    procedure SetCurrentZoomPercent(Value: Integer);
    function GetCurrentSortField: TSortField;
    function GetCurrentSortAsc: Boolean;

    function GetIndexAt(X, Y: Single): Integer;

    procedure BuildChrome;
    procedure RebuildContent;
    function CurrentScrollBox: TVertScrollBox;
    function CurrentPaintBox: TPaintBox;
    function TileSize: Integer;
    function RowHeight: Integer;
    procedure GetTileLayout(AWidth: Single; out ACols, ATS: Integer;
      out ATileH, ASlotW, APadX: Single);
    procedure KeepFocusVisible;
    function GetCurrentPathImpl: string;
    function ShowsParentRow(const APath: string): Boolean;
    function HasParentDirectory: Boolean;
    procedure SetShowDriveBar(AShow: Boolean);

    procedure NavigateToParent;


    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    function RightButtonHeld(const AShift: TShiftState): Boolean;
    function GetSelectIndexAt(X, Y: Single): Integer;
    procedure CapturePaintBoxMouse;
    procedure ReleasePaintBoxCapture;
    procedure EndRightPaint;
    procedure ApplyRightPaintMouse(X, Y: Single);
    procedure SelectScrollTimerTick(Sender: TObject);
    procedure PaintBoxDblClick(Sender: TObject);
    procedure PanelMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);

    procedure DoAddTab(const APath: string; Activate: Boolean);
    procedure UpdatePathLabel;
    procedure RebuildBreadcrumbs;
    function HitCrumbIndex(AContentX: Single): Integer;
    procedure CrumbsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure CrumbsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure CrumbsMouseLeave(Sender: TObject);
    procedure SetCrumbHover(AIndex: Integer);
    procedure BeginPathEdit;
    procedure EndPathEdit(AApply: Boolean);
    procedure PathEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure PathEditSubmit(Sender: TObject);
    procedure PathEditExit(Sender: TObject);
    function NormalizePastedPath(const AText: string): string;
    procedure ApplyPathEditTheme;
    procedure EmptyAreaMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure LongClickTimerTick(Sender: TObject);
    procedure CancelLongClick;
    function VisualToEntry(AVisualIdx: Integer; out AEntry: TFileEntry): Boolean;
    function GetInlineRenameRect(AVisualIdx: Integer; out ARect: TRectF): Boolean;
    procedure BeginInlineRename(AVisualIdx: Integer);
    procedure EndInlineRename(AApply: Boolean);
    procedure RenameEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure RenameEditSubmit(Sender: TObject);
    procedure RenameEditExit(Sender: TObject);
    procedure ShowShellMenuForIndex(AVisualIdx: Integer);
    procedure GetColumnBounds(AContentWidth: Single;
      out NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR: Single);
    procedure GetHeaderColumnBounds(AContentWidth: Single;
      out NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR: Single);
    function DetailsFontSize: Single;
    function MeasureColText(const AText: string; ASize: Single): Single;
    procedure InvalidateColLayout;
    procedure EnsureColTemplates;
    procedure UpdateLongestType(AList: uFileModel.TFileEntryList);
    procedure RecalcColLayout(AContentWidth: Single);
    function FormatRowDate(const AEntry: TFileEntry): string;
    procedure DrawTrimmedText(Canvas: TCanvas; const ARect: TRectF;
      const AText: string; AColor: TAlphaColor; AOpacity: Single;
      AAlign: TTextAlign; ASize: Single);
    procedure ScrollBoxResize(Sender: TObject);
    procedure ScrollBoxViewportPositionChange(Sender: TObject; const OldViewportPosition, NewViewportPosition: TPointF; const ContentSizeChanged: Boolean);
    procedure EnsureIndexVisible(AIndex: Integer);

    procedure BtnDetailsClick(Sender: TObject);
    procedure BtnTilesClick(Sender: TObject);
    procedure BtnQuickViewClick(Sender: TObject);
    procedure PreviewCloseClick(Sender: TObject);
    procedure PreviewDiskChanged(Sender: TObject);
    procedure NotifyCursorChange;
    procedure BtnBackClick(Sender: TObject);
    procedure BtnForwardClick(Sender: TObject);
    procedure RecordHistory(const APath: string);
    procedure HistoryGo(ADelta: Integer);
    procedure UpdateHistoryButtons;
    procedure StyleHistBtn(ABtn: TFluentButton; AEnabled: Boolean);
    procedure HeaderPaint(Sender: TObject; Canvas: TCanvas);
    procedure HeaderMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseLeave(Sender: TObject);
    procedure IconBtnEnter(Sender: TObject);
    procedure IconBtnLeave(Sender: TObject);
    procedure UpdateViewButtons;
    procedure ApplyCardChrome;
    procedure UpdateChromeStackHeight;
    procedure LockChromeOrder;
    procedure DriveBarClick(Sender: TObject; const ARoot: string);
    procedure DriveBarContext(Sender: TObject; const ARoot: string);
    function DriveClickKey(const ARoot: string): string;
    procedure RememberDrivePath(const APath: string);
    function ResolveDriveTarget(const ARoot: string): string;
    procedure HandlePlacesChanged(Sender: TObject);
    function TabPathStillAvailable(const APath: string;
      const APlaces: TArray<TDriveInfo>): Boolean;
    procedure SyncDriveBar;
    procedure SetSort(AField: TSortField);
    procedure PaintItemChrome(Canvas: TCanvas; const R: TRectF;
      ARadius: Single; IsSelected, IsCursor: Boolean; AIndex: Integer;
      out ATextColor: TAlphaColor);
    function EntryRowOpacity(const AEntry: TFileEntry): Single;
    procedure DrawEntryIcon(Canvas: TCanvas; const AEntry: TFileEntry;
      const ARect: TRectF; AOpacity: Single);
    function IconSceneScale: Single;
    function CurrentIconTarget: Integer;

    procedure HandleTabChange(Sender: TObject; AIndex: Integer);
    procedure HandleTabClose(Sender: TObject; AIndex: Integer; var ACanClose: Boolean);
    procedure HandleTabAdd;
    procedure HandleTabReorder(Sender: TObject; AFromIndex, AToIndex: Integer);
    procedure HandleTabDragQuery(Sender: TObject; AIndex: Integer; var APath: string);
    procedure HandleTabDragOver(Sender: TObject; const Point: TPointF;
      var Operation: TDragOperation);
    procedure HandleTabDragDrop(Sender: TObject; const Point: TPointF);
    function PointOverTabBar(const AAbsPt: TPointF): Boolean;
    procedure AcceptForeignTab(const APath: string; AInsertBefore: Integer);

    procedure PanelKeyDownHandler(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure ThumbTimerTick(Sender: TObject);
    procedure RefreshThumbs;
    procedure DirChangeTimerTick(Sender: TObject);
    function FileListsEquivalent(A, B: uFileModel.TFileEntryList): Boolean;

    procedure BindDragEvents(AControl: TControl);
    procedure StartInternalDrag;
    procedure FileDragTrack;
    procedure FileDragEnd(AButton: TMouseButton; AShift: TShiftState);
    procedure StartOleExport;
    { SetDropHot / ApplyDrop — public для внешнего IDropTarget }
    procedure DragPollTimerTick(Sender: TObject);
    function IsDragGiving: Boolean;
    function PointInOwnForm(const AScreen: TPointF): Boolean;
    function PanelAtScreen(const AScreen: TPointF): TFilePanel;
    function CollectDragFiles(const Data: TDragObject): TArray<string>;
    function ResolveDropPath(const ALocal: TPointF; out AHighlight: Integer): string;
    procedure PanelDragOver(Sender: TObject; const Data: TDragObject;
      const Point: TPointF; var Operation: TDragOperation);
    procedure PanelDragDrop(Sender: TObject; const Data: TDragObject; const Point: TPointF);
    procedure PanelDragLeave(Sender: TObject);
    function LocalPointOnPaintBox(Sender: TObject; const Point: TPointF): TPointF;
    procedure ApplyTabState(AIndex: Integer; const AState: TTabState);
    procedure SaveTabCursor(AIndex: Integer);
    procedure RestoreTabCursor(AIndex: Integer);
    function PathFromVisualIndex(const Tab: TFileTab; AVisual: Integer): string;
    function IndexFromCursorPath(const Tab: TFileTab): Integer;
    procedure WatchTab(AIndex: Integer);
    function TabMatchesWatch(const ATabPath, AWatchPath: string): Boolean;
    procedure WatchCurrentPath;
    procedure HandleDirChange(const APath: string);
    procedure CaptureSelection(APaths: TStringList; out AFocus: string);
    procedure CaptureTabSelection(AIndex: Integer; APaths: TStringList; out AFocus: string);
    procedure RestoreTabSelection(AIndex: Integer; AEntries: uFileModel.TFileEntryList;
      APaths: TStringList; const AFocus: string; AApplyToManager: Boolean);
    procedure ApplyLoadedList(const APath: string; List: uFileModel.TFileEntryList;
      const ASelectPath: string; AKeepSel: Boolean;
      ASelPaths: TStringList; const AFocus: string; APartial: Boolean = False);
    procedure SetTabOffline(AIndex: Integer; const AMsg: string);
    procedure StopRemoteLoad(AIndex: Integer);
    procedure NoteRemoteProgress(AIndex: Integer; ACount: Integer);
    procedure AppendRemoteChunk(AIndex: Integer; ASlice: uFileModel.TFileEntryList;
      ADone: Boolean);
    procedure ResumeRemoteRead;
    function IndexOfLoadGen(AGen: Integer; const APath: string): Integer;
    function HitParentRetry(const ALocal: TPointF): Boolean;
    procedure ParentRemoteBits(out AStatus, ARetry: string; out AShowRetry: Boolean);
    procedure NetPulseTick(Sender: TObject);
    procedure ApplyNetPulse(ATabIndex: Integer; const APath: string;
      AWasOff, AOk: Boolean);
    function WantRemoteThumbs: Boolean;
    procedure StartDirLoad(const APath, ASelectPath: string; AKeepSelection: Boolean);
    procedure StartDirLoadAt(ATabIndex: Integer; const APath, ASelectPath: string;
      AKeepSelection: Boolean);
    procedure AbandonTabLoad(ATabIndex: Integer);
    function ActiveLoadCount: Integer;
    function IndexOfLoadThread(AThr: TThread): Integer;
    procedure ContinueAfterLoad(ATabIndex: Integer);
    procedure PumpLoadQueue;
    procedure UpdateLoadChrome;
    procedure LoadWatchTick(Sender: TObject);
    procedure RetryLoadClick(Sender: TObject);
    procedure ApplyCursorAfterLoad(AList: uFileModel.TFileEntryList;
      const ASelectPath: string; AKeepSel: Boolean);

  protected
    function FindTarget(P: TPointF; const Data: TDragObject): IControl; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure UpdateStatusText;
    procedure ApplyNameFilter(const AMask: string);
    procedure ClearFilter;
    function HasFilter: Boolean;
    procedure ShowNotice(const AText: string);
    class function HitAtScreen(ARoot: TFmxObject; const AScreen: TPointF): TFilePanel; static;
    function TrackExternalDrop(const AScreen: TPointF; ABrowser: Boolean;
      out ADest: string): Boolean;
    procedure FinishBrowserFiles(const ADest: string; const AFiles: TArray<string>);
    procedure SetDropHot(AHot: Boolean);
    procedure ApplyDrop(const ADest: string; const ASources: TArray<string>;
      AMove: Boolean; ASourcePanel: TFilePanel);
    function CanDropBrowserDest(const ADest: string): Boolean;
    function CanDropTo(const ADest: string; const ASources: TArray<string>): Boolean;
    procedure Navigate(const APath: string; const ASelectPath: string = '');
    procedure Refresh(const ASelectPath: string = ''; AKeepSelection: Boolean = False);
    function PreviewEditKey(var Key: Word; Shift: TShiftState): Boolean;
    procedure InvalidateView;
    procedure AddTab(const APath: string = '');
    procedure CloseCurrentTab;
    procedure SetViewMode(AMode: TPanelViewMode);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure SetShowNetwork(AShow: Boolean);
    procedure SetShowHiddenFiles(AShow: Boolean);
    procedure ApplyUiSettings(const ASettings: TAppSettings);
    procedure SetActive(AIsActive: Boolean);
    procedure MoveSelection(Delta: Integer; Shift: TShiftState = []);
    procedure MoveSelectionGrid(DeltaX, DeltaY: Integer; Shift: TShiftState = []);
    procedure OpenSelected;
    procedure GoBack;
    procedure ToggleBranchView;
    function IsBranchView: Boolean;
    function IsSearchView: Boolean;
    procedure ShowSearchHits(const ARoot: string; AList: uFileModel.TFileEntryList);
    procedure HistoryBack;
    procedure HistoryForward;
    function CanHistoryBack: Boolean;
    function CanHistoryForward: Boolean;
    procedure PanelonResize(Sender: TObject);
    procedure DeselectByPath(const APath: string);

    function SelectedEntry: TFileEntry;
    function HasSelection: Boolean;
    function HasMultiSelection: Boolean;
    procedure StartInlineRename;
    procedure CreateNewFolderInPlace;
    function IsInlineRenaming: Boolean;
    function SelectedEntries: TArray<TFileEntry>;
    function GetFocusedEntry(out AEntry: TFileEntry): Boolean;
    function HandleSelectionKey(var AKey: Word; AShift: TShiftState): Boolean;
    function FocusByMask(const AMask: string): Boolean;
    procedure ClearSelection;
    procedure SelectAllItems;
    procedure InvertSelection;
    procedure SelectByWildcard(const AMask: string; ASelect: Boolean);
    procedure SelectSameExtension(ASelect: Boolean);
    procedure SelectFilesOnly;
    procedure SelectFoldersOnly;
    procedure CompareDirectories(AOther: TFilePanel);
    procedure CopySelectionToClipboard(ACut: Boolean = False);
    procedure HandlePaste;
    function IsPathEditing: Boolean;
    procedure CancelPathEdit;
    function CollectDragPaths: TArray<string>;
    function FocusPathAfterRemove(const ARemoved: TArray<string>): string;
    procedure CaptureTabs(out AState: TSideState);
    procedure RestoreTabs(const AState: TSideState);
    procedure LoadActiveTab;
    function LoadNextStaleTab: Boolean;
    procedure EnableDirWatch;
    procedure StartDeferredDrives;
    procedure AddSlowPlaces;
    procedure AllowTabShellIcons;

    property ViewMode: TPanelViewMode read GetCurrentViewMode write SetCurrentViewMode;
    property CurrentPath: string read GetCurrentPathImpl;
    property ZoomPercent: Integer read GetCurrentZoomPercent write SetCurrentZoomPercent;
    property SortField: TSortField read GetCurrentSortField;
    property SortAscending: Boolean read GetCurrentSortAsc;
    property OnActivate: TNotifyEvent read FOnActivate write FOnActivate;
    property OnQuickView: TQuickViewEvent read FOnQuickView write FOnQuickView;
    property OnPathChanged: TPathChangedEvent read FOnPathChanged write FOnPathChanged;
    property OnCursorChange: TNotifyEvent read FOnCursorChange write FOnCursorChange;
    property OnListReady: TNotifyEvent read FOnListReady write FOnListReady;
    property OnDropCopyMove: TPanelCopyMoveEvent read FOnDropCopyMove write FOnDropCopyMove;
    function IsOffline: Boolean;
    function IsPreviewActive: Boolean;
    function PreviewHasFocus: Boolean;
    procedure ShowPreview(const APath: string);
    procedure HidePreview;
    procedure PreviewFile(const APath: string);

    procedure MoveHome(const AShift: TShiftState);
    procedure MoveEnd(const AShift: TShiftState);
    procedure MovePage(ADirection: Integer; const AShift: TShiftState);
    procedure ToggleCurrentAndMove;
  end;

implementation

type
  TInAppFileDrag = record
    Active: Boolean;
    OleExport: Boolean;
    Consumed: Boolean;
    Source: TFilePanel;
    Hover: TFilePanel;
    Paths: TArray<string>;
    OleFiles: TArray<string>;
  end;

var
  GFileDrag: TInAppFileDrag;
  GFileDragDropHook: TFileDragDropHook;

type
  TNetPulseJob = class
    Panel: TFilePanel;
    Path: string;
    TabIdx: Integer;
    WasOff: Boolean;
    Ok: Boolean;
    procedure Apply;
  end;

  TShotSaveJob = class
    Panel: TFilePanel;
    Dest: string;
    Bytes: TBytes;
    Ok: Boolean;
    procedure Execute;
    procedure Apply;
  end;

const
  MIN_ZOOM = 50;
  MAX_ZOOM = 250;
  MIN_TILE_ZOOM = 100;
  MAX_TILE_ZOOM = 250;
  ZOOM_STEP = 10;
  BASE_ROW_HEIGHT = 32;
  BASE_TILE_SIZE = 144;
  MIN_TILE_SIZE = 144;
  MAX_TILE_SIZE = 360;
  TILE_GAP = 10;
  TILE_TEXT_ZONE = 45;
  SCROLLBAR_RESERVE = 18;
  MAX_DIR_HISTORY = 80;

function NormDirHistoryPath(const APath: string): string;
begin
  Result := Trim(APath);
  if Result = '' then
    Exit;
  if not IsVirtualShellPath(Result) then
  begin
    Result := ExcludeTrailingPathDelimiter(Result);
    if (Length(Result) = 2) and (Result[2] = ':') then
      Result := Result + PathDelim;
  end;
end;

function SameDirHistoryPath(const A, B: string): Boolean;
begin
  Result := SameText(NormDirHistoryPath(A), NormDirHistoryPath(B));
end;

function AdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.Color := AColor;
  Rec.A := AAlpha;
  Result := Rec.Color;
end;

procedure OpenFileWithDefaultApp(const APath: string);
begin
  if IsOfficeLockFile(APath) then
    Exit;
  {$IFDEF MSWINDOWS}
  ShellExecute(0, 'open', PChar(APath), nil, nil, SW_SHOWNORMAL);
  {$ENDIF}
end;

procedure RegisterFileDragDropHook(const AHook: TFileDragDropHook);
begin
  GFileDragDropHook := AHook;
end;

function FileDragIsActive: Boolean;
begin
  Result := GFileDrag.Active and not GFileDrag.OleExport;
end;

function PeekFileDragPaths: TArray<string>;
begin
  Result := Copy(GFileDrag.Paths);
end;

{ TFilePanel }

constructor TFilePanel.Create(AOwner: TComponent);
begin
  FDestroying := False;
  FDeferDirLoad := False;
  FWatchEnabled := False;
  FListReadyFired := False;
  inherited Create(AOwner);
  FTabs := TList<TFileTab>.Create;
  FActiveTabIndex := -1;
  FColors := GetThemeColors(atSystem);

  FSelectionManager := TFileSelectionManager.Create(Self);
  FPendingCursorIndex := 0;
  FHoverIndex := -1;
  FDropHighlightIndex := -2;
  FDropTargetHot := False;
  FShowHiddenFiles := False;
  FShowDriveBar := True;
  FNameFilter := '';
  FFilterReady := False;
  FFilterMap := TList<Integer>.Create;
  FListFontSize := 13;
  FLongestType := 'Папка';
  FColLayoutW := -1;
  FColFs := 0;
  FDriveLast := TDictionary<string, string>.Create;
  FDragReady := False;
  FCrumbPaths := TStringList.Create;
  FThumbTimer := TTimer.Create(Self);
  FThumbTimer.Interval := 40;
  FThumbTimer.Enabled := False;
  FThumbTimer.OnTimer := ThumbTimerTick;
  FDirChangeTimer := TTimer.Create(Self);
  FDirChangeTimer.Interval := 800;
  FDirChangeTimer.Enabled := False;
  FDirChangeTimer.OnTimer := DirChangeTimerTick;
  FLoadWatchTimer := TTimer.Create(Self);
  FLoadWatchTimer.Interval := 400;
  FLoadWatchTimer.Enabled := False;
  FLoadWatchTimer.OnTimer := LoadWatchTick;
  FNetPulseTimer := TTimer.Create(Self);
  FNetPulseTimer.Interval := 10000;
  FNetPulseTimer.Enabled := False;
  FNetPulseTimer.OnTimer := NetPulseTick;
  FNetPulseBusy := False;
  FKeepSelPaths := TStringList.Create;
  FKeepSelPaths.CaseSensitive := False;
  FLongClickTimer := TTimer.Create(Self);
  FLongClickTimer.Interval := 1000;
  FLongClickTimer.Enabled := False;
  FLongClickTimer.OnTimer := LongClickTimerTick;
  FDragPollTimer := TTimer.Create(Self);
  FDragPollTimer.Interval := 16;
  FDragPollTimer.Enabled := False;
  FDragPollTimer.OnTimer := DragPollTimerTick;
  FSelectScrollTimer := TTimer.Create(Self);
  FSelectScrollTimer.Interval := 30;
  FSelectScrollTimer.Enabled := False;
  FSelectScrollTimer.OnTimer := SelectScrollTimerTick;
  BuildChrome;
  FRetryBtn := TFluentButton.Create(Self);
  FRetryBtn.Setup(FCard, '', 'Повторить', fbkStandard, RetryLoadClick);
  FRetryBtn.Visible := False;
  FRetryBtn.HitTest := True;
  FRetryBtn.Width := 128;
  FRetryBtn.Height := 32;
  CanFocus := True;
  TabStop := True;
  Self.OnKeyDown := PanelKeyDownHandler;
end;

destructor TFilePanel.Destroy;
begin
  FDestroying := True;
  FRefreshPending := False;
  if FShotJob <> nil then
  begin
    TShotSaveJob(FShotJob).Panel := nil;
    FShotJob := nil;
  end;
  if Assigned(FPreview) then
  begin
    FPreview.OnClose := nil;
    FPreview.ClearPreview;
  end;
  FreeAndNil(FKeepSelPaths);
  FreeAndNil(FFilterMap);
  FreeAndNil(FColMeasure);
  FreeAndNil(FNameLayout);
  if Assigned(FThumbTimer) then
    FThumbTimer.Enabled := False;
  if Assigned(FDirChangeTimer) then
    FDirChangeTimer.Enabled := False;
  if Assigned(FLoadWatchTimer) then
    FLoadWatchTimer.Enabled := False;
  if Assigned(FNetPulseTimer) then
    FNetPulseTimer.Enabled := False;
  if Assigned(FDragPollTimer) then
    FDragPollTimer.Enabled := False;
  if Assigned(FSelectScrollTimer) then
    FSelectScrollTimer.Enabled := False;
  if GFileDrag.Source = Self then
  begin
    GFileDrag.Active := False;
    GFileDrag.OleExport := False;
    GFileDrag.Source := nil;
    GFileDrag.Hover := nil;
    SetLength(GFileDrag.Paths, 0);
    SetLength(GFileDrag.OleFiles, 0);
  end;

  for var J := 0 to FTabs.Count - 1 do
    AbandonTabLoad(J);
  CheckSynchronize;

  FreeAndNil(FSelectionManager);

  for var I := FTabs.Count - 1 downto 0 do
  begin
    var Tab := FTabs[I];
    if Assigned(Tab.Watcher) then
    begin
      Tab.Watcher.OnChange := nil;
      FreeAndNil(Tab.Watcher);
    end;
    if Assigned(Tab.Scrollbar) then FreeAndNil(Tab.Scrollbar);
    if Assigned(Tab.Entries) then FreeAndNil(Tab.Entries);
    if Assigned(Tab.SelectedIndices) then FreeAndNil(Tab.SelectedIndices);
  end;

  FTabs.Clear;
  FreeAndNil(FTabs);
  FreeAndNil(FTabsBar);
  FreeAndNil(FCrumbPaths);
  FreeAndNil(FDriveLast);

  inherited;
end;

{ Реализация ISelectionAdapter }

function TFilePanel.GetItemCount: Integer;
begin
  Result := VisualCount;
end;

function TFilePanel.IsItemSelected(AIndex: Integer): Boolean;
var
  SelIndices: TList<Integer>;
begin
  SelIndices := GetCurrentSelectedIndices;
  Result := Assigned(SelIndices) and SelIndices.Contains(AIndex);
end;

procedure TFilePanel.PanelKeyDownHandler(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  if Assigned(FSelectionManager) then
  begin
    if FSelectionManager.KeyDown(Key, Shift) then
    begin
      Key := 0;
    end;
  end;
end;

procedure TFilePanel.SetItemSelected(AIndex: Integer; ASelected: Boolean);
var
  SelIndices: TList<Integer>;
begin
if HasParentDirectory and (AIndex = 0) then Exit;
  SelIndices := GetCurrentSelectedIndices;
  if not Assigned(SelIndices) then Exit;

  if ASelected then
  begin
    if not SelIndices.Contains(AIndex) then
      SelIndices.Add(AIndex);
  end
  else
  begin
    SelIndices.Remove(AIndex);
  end;
end;

function TFilePanel.GetItemExtension(AIndex: Integer): string;
var
  Entries: uFileModel.TFileEntryList;
  ActualIndex: Integer;
begin
  Result := '';
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;
  if not VisualToActual(AIndex, ActualIndex) then Exit;
  Result := Entries[ActualIndex].Extension;
end;

function TFilePanel.VisualToActual(AIndex: Integer; out AActual: Integer): Boolean;
var
  Entries: uFileModel.TFileEntryList;
  Slot: Integer;
begin
  Result := False;
  AActual := -1;
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then
    Exit;
  if FFilterReady then
  begin
    if HasParentDirectory then
    begin
      if AIndex <= 0 then
        Exit;
      Slot := AIndex - 1;
    end
    else
      Slot := AIndex;
    if (Slot < 0) or (Slot >= FFilterMap.Count) then
      Exit;
    AActual := FFilterMap[Slot];
  end
  else if HasParentDirectory then
  begin
    if AIndex <= 0 then
      Exit;
    AActual := AIndex - 1;
  end
  else
    AActual := AIndex;
  Result := (AActual >= 0) and (AActual < Entries.Count);
end;

function TFilePanel.VisualCount: Integer;
var
  Entries: uFileModel.TFileEntryList;
begin
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then
    Exit(0);
  if FFilterReady then
    Result := FFilterMap.Count
  else
    Result := Entries.Count;
  if HasParentDirectory then
    Inc(Result);
end;

function TFilePanel.VisualFromActual(AActual: Integer): Integer;
var
  Slot: Integer;
begin
  Result := -1;
  if AActual < 0 then
    Exit;
  if FFilterReady then
  begin
    Slot := FFilterMap.IndexOf(AActual);
    if Slot < 0 then
      Exit;
    Result := Slot;
  end
  else
    Result := AActual;
  if HasParentDirectory then
    Inc(Result);
end;

function TFilePanel.EntryMatchesFilter(const AEntry: TFileEntry): Boolean;
var
  Needle: string;
begin
  if FNameFilter = '' then
    Exit(True);
  if (Pos('*', FNameFilter) > 0) or (Pos('?', FNameFilter) > 0) then
    Result := MatchesMask(AEntry.Name, FNameFilter) or
      ((AEntry.DisplayName <> '') and (AEntry.DisplayName <> AEntry.Name) and
       MatchesMask(AEntry.DisplayName, FNameFilter))
  else
  begin
    Needle := AnsiLowerCase(FNameFilter);
    Result := Pos(Needle, AnsiLowerCase(AEntry.Name)) > 0;
    if not Result and (AEntry.DisplayName <> '') then
      Result := Pos(Needle, AnsiLowerCase(AEntry.DisplayName)) > 0;
  end;
end;

procedure TFilePanel.CaptureFilterIdentity(APaths: TStringList; out AFocus: string);
var
  Sel: TList<Integer>;
  Entries: uFileModel.TFileEntryList;
  I, Actual, Vis: Integer;
begin
  AFocus := '';
  if APaths = nil then
    Exit;
  APaths.Clear;
  Entries := GetCurrentEntries;
  if Assigned(FSelectionManager) then
  begin
    Vis := FSelectionManager.CurrentIndex;
    if HasParentDirectory and (Vis = 0) then
      AFocus := #1
    else if VisualToActual(Vis, Actual) and Assigned(Entries) then
      AFocus := Entries[Actual].FullPath;
  end;
  Sel := GetCurrentSelectedIndices;
  if not Assigned(Sel) or not Assigned(Entries) then
    Exit;
  for I := 0 to Sel.Count - 1 do
    if VisualToActual(Sel[I], Actual) and (Entries[Actual].FullPath <> '') then
      APaths.Add(Entries[Actual].FullPath);
end;

procedure TFilePanel.RebuildFilterMap;
var
  Entries: uFileModel.TFileEntryList;
  I: Integer;
begin
  if FFilterMap = nil then
    FFilterMap := TList<Integer>.Create;
  FFilterMap.Clear;
  if FNameFilter = '' then
  begin
    FFilterReady := False;
    Exit;
  end;
  Entries := GetCurrentEntries;
  if Assigned(Entries) then
    for I := 0 to Entries.Count - 1 do
      if EntryMatchesFilter(Entries[I]) then
        FFilterMap.Add(I);
  FFilterReady := True;
end;

procedure TFilePanel.RestoreFilterIdentity(APaths: TStringList; const AFocus: string;
  AJump, ARebuild: Boolean);
var
  Entries: uFileModel.TFileEntryList;
  Sel: TList<Integer>;
  I, Vis, Idx: Integer;
begin
  Entries := GetCurrentEntries;
  Sel := GetCurrentSelectedIndices;
  if Assigned(Sel) then
    Sel.Clear;
  if Assigned(Sel) and Assigned(Entries) and Assigned(APaths) then
    for I := 0 to Entries.Count - 1 do
      if (Entries[I].FullPath <> '') and (APaths.IndexOf(Entries[I].FullPath) >= 0) then
      begin
        Vis := VisualFromActual(I);
        if Vis >= 0 then
          Sel.Add(Vis);
      end;

  Idx := 0;
  if AJump and FFilterReady then
  begin
    if HasParentDirectory and (FFilterMap.Count > 0) then
      Idx := 1
    else
      Idx := 0;
  end
  else if AFocus = #1 then
    Idx := 0
  else if (AFocus <> '') and Assigned(Entries) then
  begin
    Idx := -1;
    for I := 0 to Entries.Count - 1 do
      if SameText(Entries[I].FullPath, AFocus) then
      begin
        Idx := VisualFromActual(I);
        Break;
      end;
    if Idx < 0 then
    begin
      if HasParentDirectory and FFilterReady and (FFilterMap.Count > 0) then
        Idx := 1
      else
        Idx := 0;
    end;
  end
  else if Assigned(FSelectionManager) then
    Idx := FSelectionManager.CurrentIndex;

  if VisualCount <= 0 then
    Idx := 0
  else
    Idx := EnsureRange(Idx, 0, VisualCount - 1);

  if Assigned(FSelectionManager) then
  begin
    FSelectionManager.CurrentIndex := Idx;
    if AJump or (FSelectionManager.AnchorIndex < 0) or
       (FSelectionManager.AnchorIndex >= VisualCount) then
      FSelectionManager.AnchorIndex := Idx;
  end;

  if ARebuild then
  begin
    UpdateStatusText;
    RebuildContent;
    if Assigned(FSelectionManager) then
      EnsureIndexVisible(FSelectionManager.CurrentIndex);
    InvalidateView;
  end;
end;

procedure TFilePanel.SuspendNameFilter;
var
  Paths: TStringList;
  Focus, Keep: string;
begin
  if not FFilterReady then
    Exit;
  Paths := TStringList.Create;
  Paths.CaseSensitive := False;
  try
    CaptureFilterIdentity(Paths, Focus);
    Keep := FNameFilter;
    FNameFilter := '';
    RebuildFilterMap;
    FNameFilter := Keep;
    RestoreFilterIdentity(Paths, Focus, False, False);
  finally
    Paths.Free;
  end;
end;

procedure TFilePanel.CommitNameFilter(AJump: Boolean);
var
  Paths: TStringList;
  Focus: string;
begin
  Paths := TStringList.Create;
  Paths.CaseSensitive := False;
  try
    CaptureFilterIdentity(Paths, Focus);
    RebuildFilterMap;
    RestoreFilterIdentity(Paths, Focus, AJump, True);
  finally
    Paths.Free;
  end;
end;

procedure TFilePanel.ApplyNameFilter(const AMask: string);
var
  Jump: Boolean;
begin
  if AMask = '' then
  begin
    ClearFilter;
    Exit;
  end;
  Jump := FNameFilter <> AMask;
  FNameFilter := AMask;
  CommitNameFilter(Jump);
end;

procedure TFilePanel.ClearFilter;
begin
  if (FNameFilter = '') and not FFilterReady then
    Exit;
  FNameFilter := '';
  CommitNameFilter(False);
end;

function TFilePanel.HasFilter: Boolean;
begin
  Result := FNameFilter <> '';
end;

function TFilePanel.GetItemName(AIndex: Integer): string;
var
  Entries: uFileModel.TFileEntryList;
  Actual: Integer;
begin
  Result := '';
  if not VisualToActual(AIndex, Actual) then
    Exit;
  Entries := GetCurrentEntries;
  Result := Entries[Actual].Name;
end;

function TFilePanel.IsItemDirectory(AIndex: Integer): Boolean;
var
  Entries: uFileModel.TFileEntryList;
  Actual: Integer;
begin
  Result := False;
  if HasParentDirectory and (AIndex = 0) then
    Exit(True);
  if not VisualToActual(AIndex, Actual) then
    Exit;
  Entries := GetCurrentEntries;
  Result := Entries[Actual].IsDirectory;
end;

procedure TFilePanel.InvalidateView;
var
  PB: TPaintBox;
begin
  PB := CurrentPaintBox;
  if Assigned(PB) then
    PB.Repaint;
end;

{ Вспомогательные геттеры текущей вкладки }

function TFilePanel.GetCurrentEntries: uFileModel.TFileEntryList;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].Entries
  else
    Result := nil;
end;

function TFilePanel.GetCurrentSelectedIndices: TList<Integer>;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].SelectedIndices
  else
    Result := nil;
end;

function TFilePanel.GetCurrentViewMode: TPanelViewMode;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].ViewMode
  else
    Result := vmDetails;
end;

procedure TFilePanel.SetCurrentViewMode(Value: TPanelViewMode);
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
  begin
    var Tab := FTabs[FActiveTabIndex];
    Tab.ViewMode := Value;
    FTabs[FActiveTabIndex] := Tab;
    InvalidateColLayout;
    RebuildContent;
  end;
end;

function TFilePanel.GetCurrentZoomPercent: Integer;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
  begin
    if FTabs[FActiveTabIndex].ViewMode = vmDetails then
      Result := FTabs[FActiveTabIndex].ZoomDetails
    else
      Result := FTabs[FActiveTabIndex].ZoomTiles;
  end
  else
    Result := 100;
end;

procedure TFilePanel.SetCurrentZoomPercent(Value: Integer);
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
  begin
    var Tab := FTabs[FActiveTabIndex];
    if Tab.ViewMode = vmDetails then
      Tab.ZoomDetails := EnsureRange(Value, MIN_ZOOM, MAX_ZOOM)
    else
      Tab.ZoomTiles := EnsureRange(Value, MIN_TILE_ZOOM, MAX_TILE_ZOOM);
    FTabs[FActiveTabIndex] := Tab;
    InvalidateColLayout;
    RebuildContent;
  end;
end;

function TFilePanel.GetCurrentSortField: TSortField;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].SortField
  else
    Result := sfName;
end;

function TFilePanel.GetCurrentSortAsc: Boolean;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].SortAsc
  else
    Result := True;
end;

function TFilePanel.GetIndexAt(X, Y: Single): Integer;
var
  RH, TS, Cols: Integer;
  TileH, SlotW, PadX: Single;
  SB: TVertScrollBox;
  Entries: uFileModel.TFileEntryList;
  TotalCount: Integer;
begin
  Result := -1;
  SB := CurrentScrollBox;
  if SB = nil then Exit;

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  TotalCount := VisualCount;
  if TotalCount <= 0 then Exit;

  if ViewMode = vmDetails then
  begin
    RH := RowHeight;
    if RH > 0 then
      Result := Floor(Y / RH);
  end
  else
  begin
    GetTileLayout(Max(1, SB.Width - SCROLLBAR_RESERVE), Cols, TS, TileH, SlotW, PadX);
    if (SlotW <= 0) or (TileH <= 0) then
      Exit;
    var Col := Floor(X / SlotW);
    var RowIdx := Floor(Y / TileH);
    if (Col >= 0) and (Col < Cols) then
      Result := RowIdx * Cols + Col;
  end;

  if (Result < 0) or (Result >= TotalCount) then
    Result := -1;
end;

procedure TFilePanel.BuildChrome;
var
  ButtonsLayout: TLayout;
  FooterLine: TRectangle;

  function CreateIconButton(const AText: string; AOnClick: TNotifyEvent): TRectangle;
  begin
    Result := TRectangle.Create(Self);
    Result.Parent := ButtonsLayout;
    Result.Align := TAlignLayout.Left;
    Result.Width := 28;
    Result.Margins.Rect := TRectF.Create(2, 2, 0, 2);
    Result.XRadius := 5;
    Result.YRadius := 5;
    Result.Fill.Kind := TBrushKind.Solid;
    Result.Fill.Color := TAlphaColors.Null;
    Result.Stroke.Kind := TBrushKind.None;
    Result.Cursor := crHandPoint;
    Result.OnClick := AOnClick;
    Result.OnMouseEnter := IconBtnEnter;
    Result.OnMouseLeave := IconBtnLeave;

    var LText := TText.Create(Result);
    LText.Parent := Result;
    LText.Align := TAlignLayout.Client;
    LText.TextSettings.HorzAlign := TTextAlign.Center;
    LText.TextSettings.VertAlign := TTextAlign.Center;
    LText.Font.Family := FluentIconFamily;
    LText.Font.Size := 14;
    LText.TextSettings.FontColor := FColors.TextColor;
    LText.Text := AText;
    LText.HitTest := False;
  end;

begin
  Self.Align := TAlignLayout.Client;
  Self.Padding.Rect := TRectF.Create(4, 4, 4, 4);

  FCard := TRectangle.Create(Self);
  FCard.Parent := Self;
  FCard.Align := TAlignLayout.Client;
  FCard.XRadius := 10;
  FCard.YRadius := 10;
  FCard.Corners := AllCorners;
  FCard.Fill.Kind := TBrushKind.Solid;
  FCard.Fill.Color := TAlphaColors.Null;
  FCard.Stroke.Kind := TBrushKind.Solid;
  FCard.Stroke.Color := FColors.CardStroke;
  FCard.Stroke.Thickness := 1;
  FCard.ClipChildren := True;

  FFooterPanel := TRectangle.Create(Self);
  FFooterPanel.Parent := FCard;
  FFooterPanel.Align := TAlignLayout.Bottom;
  FFooterPanel.Height := 32;
  FFooterPanel.Fill.Kind := TBrushKind.Solid;
  FFooterPanel.Fill.Color := FColors.HeaderBackground;
  FFooterPanel.Stroke.Kind := TBrushKind.None;
  FFooterPanel.HitTest := True;

  FooterLine := TRectangle.Create(Self);
  FooterLine.Parent := FFooterPanel;
  FooterLine.Align := TAlignLayout.Top;
  FooterLine.Height := 1;
  FooterLine.Stroke.Kind := TBrushKind.None;
  FooterLine.Fill.Kind := TBrushKind.Solid;
  FooterLine.Fill.Color := FColors.DividerColor;
  FooterLine.HitTest := False;
  FooterLine.Tag := 1;

  FStatusText := TText.Create(Self);
  FStatusText.Parent := FFooterPanel;
  FStatusText.Align := TAlignLayout.Client;
  FStatusText.TextSettings.HorzAlign := TTextAlign.Leading;
  FStatusText.TextSettings.VertAlign := TTextAlign.Center;
  FStatusText.TextSettings.Font.Family := FluentFontFamily;
  FStatusText.TextSettings.Font.Size := 11;
  FStatusText.TextSettings.FontColor := FColors.SubTextColor;
  FStatusText.Margins.Rect :=  TRectF.Create(12, 0, 4, 0);
  FStatusText.HitTest := False;
  ApplyFluentText(FStatusText, 11, False);

  ButtonsLayout := TLayout.Create(Self);
  ButtonsLayout.Parent := FFooterPanel;
  ButtonsLayout.Align := TAlignLayout.Right;
  ButtonsLayout.Width := 96;
  ButtonsLayout.Margins.Rect := TRectF.Create(0, 2, 6, 2);

  FBtnTiles := CreateIconButton('', BtnTilesClick);
  FBtnDetails := CreateIconButton('', BtnDetailsClick);
  FBtnQuickView := CreateIconButton('', BtnQuickViewClick);


  FChromeStack := TLayout.Create(Self);
  FChromeStack.Parent := FCard;
  FChromeStack.Align := TAlignLayout.Top;

  FTabsBar := TCustomTabsBar.Create(FChromeStack);
  FTabsBar.OnTabChange := HandleTabChange;
  FTabsBar.OnTabClose := HandleTabClose;
  FTabsBar.OnTabAdd := HandleTabAdd;
  FTabsBar.OnTabReorder := HandleTabReorder;
  FTabsBar.OnTabDragQuery := HandleTabDragQuery;

  { Адрес + заголовок колонок — один блок. Заголовок всегда виден (и в плитках). }
  FPathAndHeader := TRectangle.Create(Self);
  FPathAndHeader.Parent := FChromeStack;
  FPathAndHeader.Align := TAlignLayout.Top;
  FPathAndHeader.Height := 50;
  FPathAndHeader.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FPathAndHeader.Padding.Rect := TRectF.Create(8, 2, 8, 2);
  FPathAndHeader.XRadius := 0;
  FPathAndHeader.YRadius := 0;
  FPathAndHeader.Fill.Kind := TBrushKind.Solid;
  FPathAndHeader.Fill.Color := FColors.HeaderBackground;
  FPathAndHeader.Stroke.Kind := TBrushKind.None;
  FPathAndHeader.ClipChildren := True;

  FTopBar := TRectangle.Create(Self);
  FTopBar.Parent := FPathAndHeader;
  FTopBar.Align := TAlignLayout.Top;
  FTopBar.Height := 22;
  FTopBar.Stroke.Kind := TBrushKind.None;
  FTopBar.Fill.Kind := TBrushKind.Solid;
  FTopBar.Fill.Color := TAlphaColors.Null;

  FBtnBack := TFluentButton.Create(Self);
  FBtnBack.Setup(FTopBar, '', '', fbkSubtle, BtnBackClick);
  FBtnBack.Align := TAlignLayout.Left;
  FBtnBack.Width := 28;
  FBtnBack.Margins.Rect := TRectF.Create(0, 1, 0, 1);
  FBtnBack.Hint := 'Назад (Alt+←)';
  FBtnBack.ShowHint := True;
  FBtnBack.ApplyTheme(FColors);

  FBtnForward := TFluentButton.Create(Self);
  FBtnForward.Setup(FTopBar, '', '', fbkSubtle, BtnForwardClick);
  FBtnForward.Align := TAlignLayout.Left;
  FBtnForward.Width := 28;
  FBtnForward.Margins.Rect := TRectF.Create(0, 1, 2, 1);
  FBtnForward.Hint := 'Вперёд (Alt+→)';
  FBtnForward.ShowHint := True;
  FBtnForward.ApplyTheme(FColors);

  FCrumbsBox := THorzScrollBox.Create(Self);
  FCrumbsBox.Parent := FTopBar;
  FCrumbsBox.Align := TAlignLayout.Client;
  FCrumbsBox.ShowScrollBars := False;
  FCrumbsBox.Margins.Rect := TRectF.Create(4, 0, 6, 0);
  FCrumbsBox.HitTest := True;
  FCrumbsBox.OnMouseDown := CrumbsMouseDown;
  FCrumbsBox.OnMouseMove := CrumbsMouseMove;
  FCrumbsBox.OnMouseLeave := CrumbsMouseLeave;
  FCrumbHoverIdx := -1;

  FCrumbsHost := TLayout.Create(Self);
  FCrumbsHost.Parent := FCrumbsBox;
  FCrumbsHost.Align := TAlignLayout.None;
  FCrumbsHost.HitTest := False;
  FCrumbsHost.Height := 22;

  FPathEdit := TFluentEdit.Create(Self);
  FPathEdit.Parent := FTopBar;
  FPathEdit.Align := TAlignLayout.Client;
  FPathEdit.Margins.Rect := TRectF.Create(2, 2, 4, 2);
  FPathEdit.Visible := False;
  FPathEdit.OnKeyDown := PathEditKeyDown;
  FPathEdit.OnSubmit := PathEditSubmit;
  FPathEdit.OnExit := PathEditExit;
  ApplyPathEditTheme;

  FHeaderBar := TRectangle.Create(Self);
  FHeaderBar.Parent := FPathAndHeader;
  FHeaderBar.Align := TAlignLayout.Client;
  FHeaderBar.Fill.Kind := TBrushKind.Solid;
  FHeaderBar.Fill.Color := FColors.HeaderBackground;
  FHeaderBar.Stroke.Kind := TBrushKind.None;

  FHeaderPaint := TPaintBox.Create(Self);
  FHeaderPaint.Parent := FHeaderBar;
  FHeaderPaint.Align := TAlignLayout.Client;
  FHeaderPaint.OnPaint := HeaderPaint;
  FHeaderPaint.OnMouseDown := HeaderMouseDown;
  FHeaderPaint.Cursor := crHandPoint;

  FDriveBar := TDriveBar.Create(Self);
  FDriveBar.Parent := FChromeStack;
  FDriveBar.Align := TAlignLayout.Top;
  FDriveBar.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FDriveBar.OnDriveClick := DriveBarClick;
  FDriveBar.OnDriveContext := DriveBarContext;
  FDriveBar.OnPlacesChanged := HandlePlacesChanged;
  FDriveBar.ApplyTheme(FColors);

  UpdateChromeStackHeight;
  LockChromeOrder;
  Self.OnMouseWheel := PanelMouseWheel;
  Self.OnResize := PanelonResize;
  BindDragEvents(Self);
  if Assigned(FCard) then
    BindDragEvents(FCard);

  FPreview := TFilePreview.Create(Self);
  FPreview.Parent := FCard;
  FPreview.Align := TAlignLayout.Client;
  FPreview.Visible := False;
  FPreview.ShowCloseButton := True;
  FPreview.OnClose := PreviewCloseClick;
  FPreview.OnDiskChanged := PreviewDiskChanged;
  FPreview.ApplyTheme(FColors);
  UpdateHistoryButtons;
end;

procedure TFilePanel.BtnDetailsClick(Sender: TObject);
begin
  SetViewMode(vmDetails);
end;

procedure TFilePanel.BtnTilesClick(Sender: TObject);
begin
  SetViewMode(vmTiles);
end;

procedure TFilePanel.BtnQuickViewClick(Sender: TObject);
var
  FocusedEntry: TFileEntry;
begin
  if Assigned(FOnQuickView) then
  begin
    if GetFocusedEntry(FocusedEntry) then
      FOnQuickView(Self, FocusedEntry.FullPath)
    else
      FOnQuickView(Self, GetCurrentPathImpl);
  end;
end;

procedure TFilePanel.PreviewDiskChanged(Sender: TObject);
begin
  if Sender is TFilePreview then
    Refresh(TFilePreview(Sender).FilePath);
end;

function TFilePanel.PreviewEditKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := Assigned(FPreview) and FPreview.Visible and
    FPreview.HandleImageKey(Key, Shift);
end;

procedure TFilePanel.PreviewCloseClick(Sender: TObject);
begin
  HidePreview;
end;

procedure TFilePanel.NotifyCursorChange;
begin
  if Assigned(FOnCursorChange) then
    FOnCursorChange(Self);
end;

function TFilePanel.IsPreviewActive: Boolean;
begin
  Result := Assigned(FPreview) and FPreview.Visible;
end;

function TFilePanel.PreviewHasFocus: Boolean;
begin
  Result := Assigned(FPreview) and FPreview.Visible and FPreview.HasKeyboardFocus;
end;

procedure TFilePanel.ShowPreview(const APath: string);
begin
  if FPreview = nil then
    Exit;
  FPreview.Visible := True;
  FPreview.BringToFront;
  FPreview.LoadFile(APath);
end;

procedure TFilePanel.HidePreview;
begin
  if FPreview = nil then
    Exit;
  FPreview.ClearPreview;
  FPreview.Visible := False;
end;

procedure TFilePanel.PreviewFile(const APath: string);
begin
  if (FPreview = nil) or not FPreview.Visible then
    Exit;
  FPreview.LoadFile(APath);
end;

procedure TFilePanel.BtnBackClick(Sender: TObject);
begin
  HistoryBack;
end;

procedure TFilePanel.BtnForwardClick(Sender: TObject);
begin
  HistoryForward;
end;

procedure TFilePanel.IconBtnEnter(Sender: TObject);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Fill.Color := FColors.ControlFillHover;
end;

procedure TFilePanel.IconBtnLeave(Sender: TObject);
begin
  UpdateViewButtons;
end;

procedure TFilePanel.UpdateViewButtons;
begin
  if Assigned(FBtnDetails) then
  begin
    if ViewMode = vmDetails then
      FBtnDetails.Fill.Color := FColors.AccentSubtle
    else
      FBtnDetails.Fill.Color := TAlphaColors.Null;
  end;
  if Assigned(FBtnTiles) then
  begin
    if ViewMode = vmTiles then
      FBtnTiles.Fill.Color := FColors.AccentSubtle
    else
      FBtnTiles.Fill.Color := TAlphaColors.Null;
  end;
  if Assigned(FBtnQuickView) then
    FBtnQuickView.Fill.Color := TAlphaColors.Null;
end;

procedure TFilePanel.LockChromeOrder;
begin
  { Align.Top: первый в списке — сверху. SendToBack в обратном порядке. }
  if Assigned(FPathAndHeader) then
    FPathAndHeader.SendToBack;
  if Assigned(FTabsBar) and Assigned(FTabsBar.Container) then
    FTabsBar.Container.SendToBack;
  if Assigned(FDriveBar) then
    FDriveBar.SendToBack;
end;

procedure TFilePanel.UpdateChromeStackHeight;
var
  H: Single;
begin
  if not Assigned(FChromeStack) then
    Exit;
  H := 0;
  if Assigned(FDriveBar) then
    H := H + FDriveBar.Height + FDriveBar.Margins.Top + FDriveBar.Margins.Bottom;
  if Assigned(FTabsBar) and Assigned(FTabsBar.Container) then
    H := H + FTabsBar.Container.Height;
  if Assigned(FPathAndHeader) then
    H := H + FPathAndHeader.Height + FPathAndHeader.Margins.Top +
      FPathAndHeader.Margins.Bottom;
  FChromeStack.Height := H;
  LockChromeOrder;
end;

function TFilePanel.DriveClickKey(const ARoot: string): string;
begin
  Result := DriveMemoryKey(ARoot);
  if Result = '' then
    Result := LowerCase(ExcludeTrailingPathDelimiter(ARoot));
end;

procedure TFilePanel.RememberDrivePath(const APath: string);
var
  Key, Best: string;
  Pair: TPair<string, string>;
begin
  if not Assigned(FDriveLast) then
    Exit;
  if (APath = '') or IsThisPCPath(APath) then
    Exit;
  Key := DriveMemoryKey(APath);
  if Key <> '' then
  begin
    FDriveLast.AddOrSetValue(Key, APath);
    Exit;
  end;
  Best := '';
  for Pair in FDriveLast do
    if (Pair.Key <> '') and
       (StartsText(IncludeTrailingPathDelimiter(Pair.Key), APath) or
        StartsText(IncludeTrailingPathDelimiter(APath), Pair.Key) or
        SameText(ExcludeTrailingPathDelimiter(Pair.Key),
          ExcludeTrailingPathDelimiter(APath))) then
      if Length(Pair.Key) > Length(Best) then
        Best := Pair.Key;
  if Best <> '' then
    FDriveLast.AddOrSetValue(Best, APath);
end;

function TFilePanel.ResolveDriveTarget(const ARoot: string): string;
var
  Key, Last, Walk: string;
begin
  Result := ARoot;
  if (ARoot = '') or not Assigned(FDriveLast) then
    Exit;
  Key := DriveClickKey(ARoot);
  if (Key = '') or not FDriveLast.TryGetValue(Key, Last) then
    Exit;
  Last := Trim(Last);
  if Last = '' then
    Exit;
  Walk := Last;
  while (Walk <> '') and not IsListablePath(Walk) do
  begin
    if SameText(ExcludeTrailingPathDelimiter(Walk),
         ExcludeTrailingPathDelimiter(ARoot)) then
      Break;
    Walk := ParentOfBrowsablePath(Walk);
  end;
  if (Walk <> '') and IsListablePath(Walk) then
    Result := Walk
  else if IsListablePath(ARoot) then
    Result := ARoot;
end;

procedure TFilePanel.DriveBarClick(Sender: TObject; const ARoot: string);
var
  Target, Key: string;
begin
  CancelPathEdit;
  if Assigned(FOnActivate) then
    FOnActivate(Self);
  if ARoot = '' then
    Exit;
  Target := ResolveDriveTarget(ARoot);
  if not IsListablePath(Target) then
    Target := ARoot;
  if not IsListablePath(Target) then
    Exit;
  Navigate(Target);
  Key := DriveClickKey(ARoot);
  if (Key <> '') and Assigned(FDriveLast) then
    FDriveLast.AddOrSetValue(Key, Target);
end;

procedure TFilePanel.DriveBarContext(Sender: TObject; const ARoot: string);
{$IFDEF MSWINDOWS}
var
  Pt: TPoint;
  Wnd: HWND;
  Verb: string;
  Files: TArray<string>;
begin
  if ARoot = '' then
    Exit;
  GetCursorPos(Pt);
  Wnd := 0;
  if Root is TCommonCustomForm then
    Wnd := FormToHWND(TCommonCustomForm(Root));
  SetLength(Files, 1);
  Files[0] := ARoot;
  ShowExplorerContextMenu(Wnd, Files, Pt.X, Pt.Y, FColors.IsDark, Verb);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure TFilePanel.SyncDriveBar;
begin
  if Assigned(FDriveBar) then
    FDriveBar.SetActivePath(GetCurrentPathImpl);
end;

function TFilePanel.TabPathStillAvailable(const APath: string;
  const APlaces: TArray<TDriveInfo>): Boolean;
var
  Drive: string;
  C: Char;
  Mask: DWORD;
  I: Integer;
  Root: string;
begin
  if (APath = '') or IsThisPCPath(APath) then
    Exit(True);
  { Для shell-путей ExtractFileDrive ошибочно видит букву S. }
  if IsVirtualShellPath(APath) or IsPortableDevicePath(APath) then
  begin
    for I := 0 to High(APlaces) do
    begin
      Root := APlaces[I].Root;
      if Root = '' then
        Continue;
      if SameText(ExcludeTrailingPathDelimiter(Root), ExcludeTrailingPathDelimiter(APath)) then
        Exit(True);
      if StartsText(IncludeTrailingPathDelimiter(Root),
        IncludeTrailingPathDelimiter(APath)) then
        Exit(True);
    end;
    Exit(True);
  end;

  Drive := ExtractFileDrive(APath);
  if (Length(Drive) >= 2) and (Drive[2] = ':') and
     CharInSet(Drive[1], ['A'..'Z', 'a'..'z']) and
     (Length(APath) >= 2) and (APath[2] = ':') and
     CharInSet(APath[1], ['A'..'Z', 'a'..'z']) then
  begin
    C := UpCase(Drive[1]);
    if CharInSet(C, ['A'..'Z']) then
    begin
      {$IFDEF MSWINDOWS}
      Mask := GetLogicalDrives;
      Exit((Mask and (1 shl (Ord(C) - Ord('A')))) <> 0);
      {$ELSE}
      Exit(True);
      {$ENDIF}
    end;
  end;

  for I := 0 to High(APlaces) do
  begin
    Root := APlaces[I].Root;
    if Root = '' then
      Continue;
    if SameText(ExcludeTrailingPathDelimiter(Root), ExcludeTrailingPathDelimiter(APath)) then
      Exit(True);
    if StartsText(IncludeTrailingPathDelimiter(Root), IncludeTrailingPathDelimiter(APath)) then
      Exit(True);
  end;
  Result := False;
end;

procedure TFilePanel.HandlePlacesChanged(Sender: TObject);
var
  I: Integer;
  Tab: TFileTab;
  Places: TArray<TDriveInfo>;
  LeaveToComputer: Boolean;
  Caption: string;
begin
  if FDestroying then
    Exit;

  Places := CollectAllPlaces(True);
  LeaveToComputer := False;

  for I := 0 to FTabs.Count - 1 do
  begin
    if IsThisPCPath(FTabs[I].Path) then
    begin
      Tab := FTabs[I];
      Tab.Stale := True;
      FTabs[I] := Tab;
    end
    else if not TabPathStillAvailable(FTabs[I].Path, Places) then
    begin
      if I = FActiveTabIndex then
        LeaveToComputer := True
      else
      begin
        Tab := FTabs[I];
        Tab.Path := ComputerFolderPath;
        Tab.Loaded := False;
        Tab.Stale := True;
        Tab.CursorIndex := 0;
        Tab.CursorPath := '';
        FTabs[I] := Tab;
        Caption := DisplayNameForPath(Tab.Path);
        if Assigned(FTabsBar) then
          FTabsBar.SetTabInfo(I, Caption, Tab.Path);
      end;
    end;
  end;

  if LeaveToComputer then
    Navigate(ComputerFolderPath)
  else if IsThisPCPath(GetCurrentPathImpl) then
    Refresh('', True);

  SyncDriveBar;
end;

function ItemPathAtVisual(APanel: TFilePanel; AIndex: Integer): string;
var
  Entry: TFileEntry;
begin
  Result := '';
  if APanel.VisualToEntry(AIndex, Entry) then
    Result := Entry.FullPath;
end;

function PrepareOleDragFiles(const APaths: TArray<string>): TArray<string>; forward;

function PathInList(const APath: string; const AList: TArray<string>): Boolean;
var
  S: string;
begin
  Result := False;
  if APath = '' then
    Exit;
  for S in AList do
    if SameText(S, APath) then
      Exit(True);
end;

procedure TFilePanel.PaintItemChrome(Canvas: TCanvas; const R: TRectF;
  ARadius: Single; IsSelected, IsCursor: Boolean; AIndex: Integer;
  out ATextColor: TAlphaColor);
var
  FocusRect: TRectF;
  Giving: Boolean;
begin
  ATextColor := FColors.TextColor;
  Giving := IsDragGiving and
    PathInList(ItemPathAtVisual(Self, AIndex), GFileDrag.Paths);

  if IsCursor and not IsSelected then
  begin
    Canvas.Fill.Color := FColors.SelectionColor;
    Canvas.FillRect(R, ARadius, ARadius, AllCorners, AbsoluteOpacity);
    ATextColor := FColors.OnAccentTextColor;
  end
  else if IsCursor and IsSelected then
  begin
    Canvas.Fill.Color := FColors.AccentSubtle;
    Canvas.FillRect(R, ARadius, ARadius, AllCorners, AbsoluteOpacity);
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := FColors.SelectionColor;
    Canvas.Stroke.Thickness := 2;
    FocusRect := R;
    FocusRect.Inflate(-1, -1);
    Canvas.DrawRect(FocusRect, ARadius, ARadius, AllCorners, AbsoluteOpacity);
    ATextColor := FColors.TextColor;
  end
  else if IsSelected then
  begin
    Canvas.Fill.Color := FColors.AccentSubtle;
    Canvas.FillRect(R, ARadius, ARadius, AllCorners, AbsoluteOpacity);
  end
  else if AIndex = FHoverIndex then
  begin
    Canvas.Fill.Color := FColors.ItemHover;
    Canvas.FillRect(R, ARadius, ARadius, AllCorners, AbsoluteOpacity);
  end;

  if Giving then
  begin
    Canvas.Fill.Color := ThemeAdjustAlpha(FColors.SelectionColor, $38);
    Canvas.FillRect(R, ARadius, ARadius, AllCorners, AbsoluteOpacity);
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := FColors.SelectionColor;
    Canvas.Stroke.Thickness := 2;
    Canvas.Stroke.Dash := TStrokeDash.Dash;
    FocusRect := R;
    FocusRect.Inflate(-1, -1);
    Canvas.DrawRect(FocusRect, ARadius, ARadius, AllCorners, AbsoluteOpacity);
    Canvas.Stroke.Dash := TStrokeDash.Solid;
  end;

  if FDropHighlightIndex = AIndex then
  begin
    Canvas.Fill.Color := ThemeAdjustAlpha(FColors.SelectionColor, $30);
    Canvas.FillRect(R, ARadius, ARadius, AllCorners, AbsoluteOpacity);
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := FColors.SelectionColor;
    Canvas.Stroke.Thickness := 2.5;
    Canvas.Stroke.Dash := TStrokeDash.Solid;
    FocusRect := R;
    FocusRect.Inflate(-1, -1);
    Canvas.DrawRect(FocusRect, ARadius, ARadius, AllCorners, AbsoluteOpacity);
  end;
end;

function TFilePanel.EntryRowOpacity(const AEntry: TFileEntry): Single;
begin
  Result := AbsoluteOpacity;
  if AEntry.IsDimmed then
    Result := Result * 0.45;
end;

function TFilePanel.IsOffline: Boolean;
begin
  Result := (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) and
    FTabs[FActiveTabIndex].Offline;
end;

function TFilePanel.IconSceneScale: Single;
begin
  Result := 1;
  if Assigned(Scene) then
    Result := Scene.GetSceneScale;
  if Result < 1 then
    Result := 1;
end;

function TFilePanel.CurrentIconTarget: Integer;
var
  RH, Side: Integer;
begin
  if ViewMode = vmDetails then
  begin
    Result := Round(22 * ZoomPercent / 100);
    RH := RowHeight;
    if Result > RH - 8 then
      Result := Max(14, RH - 4);
  end
  else
  begin
    Side := Round((TileSize - 12) * 0.72);
    if Side < 32 then
      Side := 32;
    Result := Side;
  end;
  if Result < 14 then
    Result := 14;
end;

procedure TFilePanel.DrawEntryIcon(Canvas: TCanvas; const AEntry: TFileEntry;
  const ARect: TRectF; AOpacity: Single);
var
  Bmp: FMX.Graphics.TBitmap;
  SrcW, SrcH, Dw, Dh, Fit: Single;
  Dest: TRectF;
  Target: Integer;
  Bucket: TIconBucket;
begin
  Bmp := nil;
  Target := Max(1, Round(Min(ARect.Width, ARect.Height)));
  Bucket := SelectIconBucket(Target);
  if Assigned(GlobalIconCache) then
    Bmp := GlobalIconCache.GetForPaint(AEntry, Bucket, IconSceneScale);
  if Assigned(Bmp) and (Bmp.Width > 0) and (Bmp.Height > 0) then
  begin
    SrcW := Bmp.Width;
    SrcH := Bmp.Height;
    Fit := Min(ARect.Width / SrcW, ARect.Height / SrcH);
    if Fit > 1 then
      Fit := 1;
    Dw := SrcW * Fit;
    Dh := SrcH * Fit;
    Dest := TRectF.Create(
      ARect.Left + (ARect.Width - Dw) / 2,
      ARect.Top + (ARect.Height - Dh) / 2,
      ARect.Left + (ARect.Width - Dw) / 2 + Dw,
      ARect.Top + (ARect.Height - Dh) / 2 + Dh);
    Canvas.DrawBitmap(Bmp, Bmp.Bounds, Dest, AOpacity, False);
  end;
end;

function TFilePanel.IsDragGiving: Boolean;
begin
  Result := GFileDrag.Active and (GFileDrag.Source = Self);
end;

procedure TFilePanel.ApplyCardChrome;
begin
  if not Assigned(FCard) then
    Exit;
  FCard.Fill.Color := TAlphaColors.Null;
  FCard.Stroke.Kind := TBrushKind.Solid;
  FCard.Stroke.Dash := TStrokeDash.Solid;
  if FActive then
  begin
    FCard.Stroke.Color := ThemeAdjustAlpha(FColors.SelectionColor, $A0);
    FCard.Stroke.Thickness := 1.5;
  end
  else
  begin
    FCard.Stroke.Color := FColors.CardStroke;
    FCard.Stroke.Thickness := 1;
  end;
end;

procedure TFilePanel.SetSort(AField: TSortField);
var
  Tab: TFileTab;
  SelectedPaths: TStringList;
  FocusedPath: string;
  Entries: uFileModel.TFileEntryList;
begin
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
    Exit;

  Tab := FTabs[FActiveTabIndex];
  if Tab.SortField = AField then
    Tab.SortAsc := not Tab.SortAsc
  else
  begin
    Tab.SortField := AField;
    Tab.SortAsc := True;
  end;
  FTabs[FActiveTabIndex] := Tab;

  Entries := Tab.Entries;
  if not Assigned(Entries) then
    Exit;

  SelectedPaths := TStringList.Create;
  SelectedPaths.CaseSensitive := False;
  try
    CaptureFilterIdentity(SelectedPaths, FocusedPath);
    SortEntries(Entries, Tab.SortField, Tab.SortAsc);
    RebuildFilterMap;
    RestoreFilterIdentity(SelectedPaths, FocusedPath, False, True);
  finally
    SelectedPaths.Free;
  end;

  if Assigned(FHeaderPaint) then
    FHeaderPaint.Repaint;
end;

procedure TFilePanel.HeaderPaint(Sender: TObject; Canvas: TCanvas);
var
  W: Single;
  Arrow: string;

  procedure DrawCol(const ARect: TRectF; const ACaption: string; AField: TSortField);
  var
    LAlign: TTextAlign;
  begin
    // Если ПЛИТКИ — текст всегда по центру. Если ПОДРОБНО — размер/дата справа, имя слева.
    if (ViewMode = vmTiles) or ((ViewMode = vmDetails) and FColTwoLine) then
      LAlign := TTextAlign.Center
    else if (AField = sfSize) or (AField = sfDate) then
      LAlign := TTextAlign.Trailing
    else
      LAlign := TTextAlign.Leading;

    // Подсветка активной сортировки в режиме плиток (делаем как кнопку)   (ViewMode = vmTiles) and
   { if  (SortField = AField) then
    begin
      Canvas.Fill.Color := FColors.AccentSubtle;
      Canvas.FillRect(ARect, 4, 4, AllCorners, 1);
      Canvas.Fill.Color := FColors.TextColor;
    end
    else }
      Canvas.Fill.Color := FColors.SubTextColor;

    var Caption := ACaption;
    if SortField = AField then
      Caption := Caption + IfThen(SortAscending, ' ↑', ' ↓');

    Canvas.FillText(ARect, Caption, False, 1, [], LAlign, TTextAlign.Center);
  end;


begin
  W := FHeaderBar.Width;
  Canvas.BeginScene;
  try
    Canvas.Fill.Color := FColors.HeaderBackground;
    Canvas.FillRect(TRectF.Create(0, 0, W, FHeaderBar.Height), 0, 0, [], 1);

    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := FColors.DividerColor;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(TPointF.Create(0, FHeaderBar.Height - 0.5),
      TPointF.Create(W, FHeaderBar.Height - 0.5), 1);

    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := 11;
    Canvas.Font.Style := [];
    Canvas.Fill.Color := FColors.SubTextColor;

    var NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR, Off, ListW: Single;
    ListW := W;
    Off := 0;
    if CurrentScrollBox <> nil then
    begin
      ListW := CurrentScrollBox.Width;
      Off := FHeaderBar.AbsoluteRect.Left - CurrentScrollBox.AbsoluteRect.Left;
    end;
    GetHeaderColumnBounds(ListW, NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR);
    DrawCol(TRectF.Create(NameL - Off, 0, NameR - Off, FHeaderBar.Height), 'Имя', sfName);
    if (ViewMode = vmDetails) and FColTwoLine then
    begin
      if TypeR - TypeL > 4 then
        DrawCol(TRectF.Create(TypeL - Off, 0, TypeR - Off, FHeaderBar.Height), 'Тип', sfExt);
      if SizeR - SizeL > 4 then
      begin
        if IsThisPCPath(GetCurrentPathImpl) then
          DrawCol(TRectF.Create(SizeL - Off, 0, SizeR - Off, FHeaderBar.Height),
            'Свободно / занято', sfSize)
        else
          DrawCol(TRectF.Create(SizeL - Off, 0, SizeR - Off, FHeaderBar.Height), 'Размер', sfSize);
      end;
      if (not IsThisPCPath(GetCurrentPathImpl)) and (DateR - DateL > 4) then
        DrawCol(TRectF.Create(DateL - Off, 0, DateR - Off, FHeaderBar.Height), 'Дата', sfDate);
    end
    else
    begin
      if FColShowType and (TypeR - TypeL > 4) then
        DrawCol(TRectF.Create(TypeL - Off, 0, TypeR - Off, FHeaderBar.Height), 'Тип', sfExt);
      if FColShowSize and (SizeR - SizeL > 4) then
      begin
        if IsThisPCPath(GetCurrentPathImpl) then
          DrawCol(TRectF.Create(SizeL - Off, 0, SizeR - Off, FHeaderBar.Height),
            'Свободно / занято', sfSize)
        else
          DrawCol(TRectF.Create(SizeL - Off, 0, SizeR - Off, FHeaderBar.Height), 'Размер', sfSize);
      end;
      if (FColDateMode <> dcmHidden) and (DateR - DateL > 4) and
         (not IsThisPCPath(GetCurrentPathImpl)) then
        DrawCol(TRectF.Create(DateL - Off, 0, DateR - Off, FHeaderBar.Height), 'Дата', sfDate);
    end;
  finally
    Canvas.EndScene;
  end;
end;

procedure TFilePanel.HeaderMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  CancelPathEdit;
  if Assigned(FOnActivate) then
    FOnActivate(Self);
  if Button <> TMouseButton.mbLeft then
    Exit;
  var NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR, Off, ListW, LX: Single;
  ListW := FHeaderBar.Width;
  Off := 0;
  if CurrentScrollBox <> nil then
  begin
    ListW := CurrentScrollBox.Width;
    Off := FHeaderBar.AbsoluteRect.Left - CurrentScrollBox.AbsoluteRect.Left;
  end;
  GetHeaderColumnBounds(ListW, NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR);
  LX := X + Off;
  if (ViewMode = vmDetails) and FColTwoLine then
  begin
    if (not IsThisPCPath(GetCurrentPathImpl)) and (DateR - DateL > 4) and
       (LX >= DateL) then
      SetSort(sfDate)
    else if (SizeR - SizeL > 4) and (LX >= SizeL) then
      SetSort(sfSize)
    else if (TypeR - TypeL > 4) and (LX >= TypeL) then
      SetSort(sfExt)
    else
      SetSort(sfName);
    Exit;
  end;
  if (not IsThisPCPath(GetCurrentPathImpl)) and
     (FColDateMode <> dcmHidden) and (DateR - DateL > 4) and
     (LX >= DateL) then
    SetSort(sfDate)
  else if FColShowSize and (SizeR - SizeL > 4) and (LX >= SizeL) then
    SetSort(sfSize)
  else if FColShowType and (TypeR - TypeL > 4) and (LX >= TypeL) then
    SetSort(sfExt)
  else
    SetSort(sfName);
end;





procedure TFilePanel.ShowNotice(const AText: string);
begin
  if Assigned(FStatusText) then
    FStatusText.Text := AText;
end;

procedure TFilePanel.UpdateStatusText;
var
  FileCount, FolderCount: Integer;
  TotalSize: Int64;
  SelFileCount, SelFolderCount: Integer;
  SelTotalSize: Int64;
  Entries: uFileModel.TFileEntryList;
  SelectedIndicesRef: TList<Integer>;
  RealIdx: Integer;
begin
  if FFilterReady and Assigned(FStatusText) then
  begin
    Entries := GetCurrentEntries;
    if Assigned(Entries) then
      FStatusText.Text := Format('%d из %d', [FFilterMap.Count, Entries.Count])
    else
      FStatusText.Text := Format('%d из %d', [FFilterMap.Count, 0]);
    Exit;
  end;
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
  begin
    if FTabs[FActiveTabIndex].Loading and
       IsRemotePath(FTabs[FActiveTabIndex].Path) then
    begin
      if Assigned(FStatusText) then
      begin
        var N := FTabs[FActiveTabIndex].LoadSeen;
        if (N <= 0) and Assigned(FTabs[FActiveTabIndex].Entries) then
          N := FTabs[FActiveTabIndex].Entries.Count;
        FStatusText.Text := Format('Чтение сети · %d', [N]);
      end;
      Exit;
    end;
  end;
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  // 1. Считаем общие показатели для всей папки
  FileCount := 0;
  FolderCount := 0;
  TotalSize := 0;

  for var Entry in Entries do
  begin
    if Entry.IsDirectory then
      Inc(FolderCount)
    else
    begin
      Inc(FileCount);
      TotalSize := TotalSize + Entry.Size;
    end;
  end;

  // 2. Считаем выделенные элементы
  SelFileCount := 0;
  SelFolderCount := 0;
  SelTotalSize := 0;

  SelectedIndicesRef := GetCurrentSelectedIndices;

  if Assigned(SelectedIndicesRef) and (SelectedIndicesRef.Count > 0) then
  begin
    for var VisualIdx in SelectedIndicesRef do
    begin
      // Корректируем визуальный индекс под индекс модели (если на первом месте "..");
      RealIdx := VisualIdx;
      if HasParentDirectory then
      begin
        if VisualIdx = 0 then Continue; // Элемент ".." не учитываем
        RealIdx := VisualIdx - 1;
      end;

      if (RealIdx >= 0) and (RealIdx < Entries.Count) then
      begin
        var Entry := Entries[RealIdx];
        if Entry.IsDirectory then
          Inc(SelFolderCount)
        else
        begin
          Inc(SelFileCount);
          SelTotalSize := SelTotalSize + Entry.Size;
        end;
      end;
    end;
  end;

  // 3. Выводим результат
  if Assigned(FStatusText) then
  begin
    // Если реально выделен хотя бы 1 файл или 1 папка
    if (SelFileCount + SelFolderCount) > 0 then
    begin
      if IsSearchView then
        FStatusText.Text := Format('Поиск  |  %s / %s  |  %d / %d',
          [FormatFileSize(SelTotalSize), FormatFileSize(TotalSize),
           SelFileCount + SelFolderCount, FileCount + FolderCount])
      else if IsBranchView then
        FStatusText.Text := Format('Ветвь  |  %s / %s  |  Файлов: %d / %d',
          [FormatFileSize(SelTotalSize), FormatFileSize(TotalSize),
           SelFileCount, FileCount])
      else
        FStatusText.Text := Format('%s / %s  |  Файлов: %d / %d  |  Папок: %d / %d',
          [FormatFileSize(SelTotalSize), FormatFileSize(TotalSize),
           SelFileCount, FileCount,
           SelFolderCount, FolderCount]);
    end
    else if IsSearchView then
      FStatusText.Text := Format('Поиск  |  %s  |  %d',
        [FormatFileSize(TotalSize), FileCount + FolderCount])
    else if IsBranchView then
      FStatusText.Text := Format('Ветвь  |  %s  |  Файлов: %d',
        [FormatFileSize(TotalSize), FileCount])
    else
      FStatusText.Text := Format('%s  |  Файлов: %d  |  Папок: %d',
        [FormatFileSize(TotalSize), FileCount, FolderCount]);
  end;
end;




procedure TFilePanel.ScrollBoxResize(Sender: TObject);
begin
  FColLayoutW := -1;
  RebuildContent;
  KeepFocusVisible;
  for var Tab in FTabs do
  begin
    if Tab.ScrollBox = Sender then
    begin
      Tab.Scrollbar.UpdateThumb;
      Break;
    end;
  end;
end;

procedure TFilePanel.ScrollBoxViewportPositionChange(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF; const ContentSizeChanged: Boolean);
begin
  FScrollTick := GetTickCount;
  if Assigned(FRenameEdit) and FRenameEdit.Visible then
    EndInlineRename(False);
  var PB := CurrentPaintBox;
  if Assigned(PB) then PB.Repaint;

  for var Tab in FTabs do
  begin
    if Tab.ScrollBox = Sender then
    begin
      Tab.Scrollbar.UpdateThumb;
      Break;
    end;
  end;
end;

function TFilePanel.GetCurrentPathImpl: string;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].Path
  else
    Result := '';
end;

function TFilePanel.ShowsParentRow(const APath: string): Boolean;
begin
  Result := ParentOfBrowsablePath(APath) <> '';
  if Result and IsDriveRoot(APath) and FShowDriveBar then
    Result := False;
end;

function TFilePanel.HasParentDirectory: Boolean;
begin
  Result := IsSearchView or ShowsParentRow(GetCurrentPathImpl);
end;

procedure TFilePanel.SetShowDriveBar(AShow: Boolean);
var
  I, J, Delta: Integer;
  Tab: TFileTab;
begin
  if Assigned(FDriveBar) then
  begin
    FDriveBar.Visible := AShow;
    if AShow then
      FDriveBar.Height := 56
    else
      FDriveBar.Height := 0;
  end;

  if FShowDriveBar = AShow then
    Exit;

  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    SaveTabCursor(FActiveTabIndex);

  if AShow then
    Delta := -1
  else
    Delta := 1;
  FShowDriveBar := AShow;

  for I := 0 to FTabs.Count - 1 do
  begin
    if not IsDriveRoot(FTabs[I].Path) then
      Continue;
    Tab := FTabs[I];
    if Assigned(Tab.SelectedIndices) then
      for J := 0 to Tab.SelectedIndices.Count - 1 do
        if Delta < 0 then
          Tab.SelectedIndices[J] := Max(0, Tab.SelectedIndices[J] - 1)
        else
          Tab.SelectedIndices[J] := Tab.SelectedIndices[J] + 1;
    if Delta < 0 then
      Tab.CursorIndex := Max(0, Tab.CursorIndex - 1)
    else
      Inc(Tab.CursorIndex);
    if (Delta < 0) and (Tab.CursorPath = #1) then
      Tab.CursorPath := PathFromVisualIndex(Tab, Tab.CursorIndex);
    FTabs[I] := Tab;
  end;

  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    RestoreTabCursor(FActiveTabIndex);
  RebuildContent;
  KeepFocusVisible;
end;

procedure TFilePanel.NavigateToParent;
var
  ParentPath, CurrentPath: string;
begin
  if FTabs.Count = 0 then Exit;
  CurrentPath := FTabs[FActiveTabIndex].Path;
  ParentPath := ParentOfBrowsablePath(CurrentPath);
  if IsBrowsablePath(ParentPath) and (ParentPath <> CurrentPath) then
    Navigate(ParentPath, CurrentPath);
end;

procedure TFilePanel.UpdatePathLabel;
begin
  if Assigned(FPathEdit) and FPathEdit.Visible then
    Exit;
  RebuildBreadcrumbs;
end;

function TFilePanel.DetailsFontSize: Single;
begin
  Result := Max(11, Round(FListFontSize * ZoomPercent / 100));
end;

function TFilePanel.MeasureColText(const AText: string; ASize: Single): Single;
begin
  if FColMeasure = nil then
  begin
    FColMeasure := TTextLayoutManager.DefaultTextLayout.Create;
    FColMeasure.WordWrap := False;
  end;
  FColMeasure.BeginUpdate;
  try
    FColMeasure.Text := AText;
    FColMeasure.Font.Family := FluentFontFamily;
    FColMeasure.Font.Size := ASize;
    FColMeasure.Font.Style := [];
  finally
    FColMeasure.EndUpdate;
  end;
  Result := Ceil(FColMeasure.TextWidth);
end;

procedure TFilePanel.InvalidateColLayout;
begin
  FColFs := 0;
  FColLayoutW := -1;
end;

procedure TFilePanel.EnsureColTemplates;
var
  Fs, Cap: Single;
  TypeSample: string;
begin
  Fs := DetailsFontSize;
  if (Abs(Fs - FColFs) < 0.05) and (FColSizeW > 0) then
    Exit;
  FColFs := Fs;
  FColPad := Max(8, Round(0.6 * Fs));
  FColGap := Max(8, Round(0.7 * Fs));
  FColMinName := Max(140, Round(18 * Fs));
  TypeSample := FLongestType;
  if TypeSample = '' then
    TypeSample := 'Папка';
  FColTypeW := MeasureColText(TypeSample, Fs) + FColPad;
  Cap := MeasureColText('Файл конфигурации', Fs) + FColPad;
  if FColTypeW < MeasureColText('Папка', Fs) + FColPad then
    FColTypeW := MeasureColText('Папка', Fs) + FColPad;
  if FColTypeW > Cap then
    FColTypeW := Cap;
  FColSizeW := MeasureColText('999.9 ГБ', Fs) + FColPad;
  FColThisPCSizeW := Max(MeasureColText('Свободно / занято', Fs),
    MeasureColText('999.9 ГБ / 999.9 ГБ', Fs)) + FColPad;
  FColDateFullW := MeasureColText('31.12.2026 23:59', Fs) + FColPad;
  FColDateMedW := MeasureColText('31.12.26 23:59', Fs) + FColPad;
  FColDateShortW := MeasureColText('31.12.26', Fs) + FColPad;
  FColLayoutW := -1;
end;

procedure TFilePanel.UpdateLongestType(AList: uFileModel.TFileEntryList);
var
  E: TFileEntry;
  Best: string;
  BestW, Tw: Single;
  Fs: Single;
begin
  Best := 'Папка';
  Fs := DetailsFontSize;
  BestW := MeasureColText(Best, Fs);
  if Assigned(AList) then
    for E in AList do
    begin
      if E.DisplayType = '' then
        Continue;
      Tw := MeasureColText(E.DisplayType, Fs);
      if Tw > BestW then
      begin
        BestW := Tw;
        Best := E.DisplayType;
      end;
    end;
  if Best <> FLongestType then
  begin
    FLongestType := Best;
    InvalidateColLayout;
  end;
end;

procedure TFilePanel.RecalcColLayout(AContentWidth: Single);
const
  TwoLineHyst = 10;
var
  W, SizeW, NameLeft, Need: Single;
  ThisPC, WasTwo: Boolean;

  function TypeLeft(ADateW: Single; AHasDate: Boolean): Single;
  var
    Right, SizeR, SizeL: Single;
  begin
    Right := W - 6;
    if not AHasDate then
      SizeR := Right
    else
      SizeR := Right - ADateW - FColGap;
    SizeL := SizeR - SizeW;
    Result := SizeL - FColGap - FColTypeW;
  end;

  function NameRoom(ADateW: Single; AHasDate: Boolean): Single;
  begin
    Result := TypeLeft(ADateW, AHasDate) - FColGap - NameLeft;
  end;

begin
  EnsureColTemplates;
  ThisPC := IsThisPCPath(GetCurrentPathImpl);
  WasTwo := FColTwoLine;
  if (Abs(AContentWidth - FColLayoutW) < 0.5) and (ThisPC = FColThisPC) then
    Exit;
  FColLayoutW := AContentWidth;
  FColThisPC := ThisPC;
  W := AContentWidth - SCROLLBAR_RESERVE;
  if ThisPC then
    SizeW := FColThisPCSizeW
  else
    SizeW := FColSizeW;
  NameLeft := 6 + 14 + Round(22 * ZoomPercent / 100) + 16;
  FColShowType := True;
  FColShowSize := True;
  { Вторая строка только когда имя уже заметно уже минимума одной строки. }
  Need := Max(80, Round(FColMinName * 0.42));
  if WasTwo then
    Need := Need + TwoLineHyst;

  if ThisPC then
  begin
    FColDateMode := dcmHidden;
    FColTwoLine := NameRoom(0, False) < Need;
    Exit;
  end;

  if NameRoom(FColDateShortW, True) >= Need then
  begin
    FColTwoLine := False;
    if NameRoom(FColDateFullW, True) >= FColMinName then
      FColDateMode := dcmFull
    else if NameRoom(FColDateMedW, True) >= FColMinName then
      FColDateMode := dcmMed
    else
      FColDateMode := dcmShort;
  end
  else
  begin
    FColTwoLine := True;
    FColDateMode := dcmShort;
  end;
end;

function TFilePanel.FormatRowDate(const AEntry: TFileEntry): string;
begin
  Result := '';
  if AEntry.Modified <= 0 then
    Exit;
  case FColDateMode of
    dcmFull: Result := FormatDateTime('dd.mm.yyyy HH:nn', AEntry.Modified);
    dcmMed: Result := FormatDateTime('dd.mm.yy HH:nn', AEntry.Modified);
    dcmShort: Result := FormatDateTime('dd.mm.yy', AEntry.Modified);
  else
    Result := FormatDateTime('dd.mm.yyyy', AEntry.Modified);
  end;
end;

procedure TFilePanel.DrawTrimmedText(Canvas: TCanvas; const ARect: TRectF;
  const AText: string; AColor: TAlphaColor; AOpacity: Single;
  AAlign: TTextAlign; ASize: Single);
begin
  if (AText = '') or (ARect.Width < 4) or (ARect.Height < 4) then
    Exit;
  if AOpacity < 0.99 then
  begin
    var Rec: TAlphaColorRec;
    Rec.Color := AColor;
    Rec.A := Max(0, Min(255, Round(Rec.A * AOpacity)));
    AColor := Rec.Color;
  end;
  if FNameLayout = nil then
    FNameLayout := TTextLayoutManager.DefaultTextLayout.Create;
  FNameLayout.BeginUpdate;
  try
    FNameLayout.Text := AText;
    FNameLayout.Font.Family := FluentFontFamily;
    FNameLayout.Font.Size := ASize;
    FNameLayout.Font.Style := [];
    FNameLayout.Color := AColor;
    FNameLayout.WordWrap := False;
    FNameLayout.Trimming := TTextTrimming.Character;
    FNameLayout.HorizontalAlign := AAlign;
    FNameLayout.VerticalAlign := TTextAlign.Center;
    FNameLayout.TopLeft := ARect.TopLeft;
    FNameLayout.MaxSize := TPointF.Create(ARect.Width, ARect.Height);
  finally
    FNameLayout.EndUpdate;
  end;
  FNameLayout.RenderLayout(Canvas);
end;

procedure TFilePanel.GetColumnBounds(AContentWidth: Single;
  out NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR: Single);
var
  ER, StartX, NameW, TypeW, SizeW, DateW, Gap: Single;
  ThisPC: Boolean;
  FirstMeta: Single;
begin
  if ViewMode <> vmDetails then
  begin
    ThisPC := IsThisPCPath(GetCurrentPathImpl);
    if ThisPC then
    begin
      NameW := 80;
      TypeW := 80;
      SizeW := 180;
      DateW := 0;
    end
    else
    begin
      NameW := 80;
      TypeW := 80;
      SizeW := 80;
      DateW := 80;
    end;
    StartX := (AContentWidth - (NameW + TypeW + SizeW + DateW)) / 2;
    NameL := StartX;         NameR := NameL + NameW;
    TypeL := NameR;          TypeR := TypeL + TypeW;
    SizeL := TypeR;          SizeR := SizeL + SizeW;
    DateL := SizeR;          DateR := DateL + DateW;
    Exit;
  end;

  RecalcColLayout(AContentWidth);
  ER := AContentWidth - SCROLLBAR_RESERVE;
  Gap := FColGap;
  DateR := ER - 6;

  if FColDateMode = dcmHidden then
    DateL := DateR
  else
  begin
    case FColDateMode of
      dcmMed: DateW := FColDateMedW;
      dcmShort: DateW := FColDateShortW;
    else
      DateW := FColDateFullW;
    end;
    DateL := DateR - DateW;
  end;

  if FColShowSize then
  begin
    if IsThisPCPath(GetCurrentPathImpl) then
      SizeW := FColThisPCSizeW
    else
      SizeW := FColSizeW;
    if FColDateMode = dcmHidden then
      SizeR := DateR
    else
      SizeR := DateL - Gap;
    SizeL := SizeR - SizeW;
  end
  else
  begin
    SizeR := DateL;
    SizeL := DateL;
  end;

  if FColShowType then
  begin
    TypeR := SizeL - Gap;
    TypeL := TypeR - FColTypeW;
  end
  else
  begin
    TypeR := SizeL;
    TypeL := SizeL;
  end;

  FirstMeta := ER - 6;
  if FColShowType then
    FirstMeta := TypeL
  else if FColShowSize then
    FirstMeta := SizeL
  else if FColDateMode <> dcmHidden then
    FirstMeta := DateL;
  NameL := 20;
  NameR := FirstMeta - Gap;
  if NameR < NameL + 40 then
    NameR := ER - 6;
end;

procedure TFilePanel.GetHeaderColumnBounds(AContentWidth: Single;
  out NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR: Single);
var
  ER, Inner, UnitW, Pad: Single;
  Parts: Single;
begin
  RecalcColLayout(AContentWidth);
  if (ViewMode <> vmDetails) or not FColTwoLine then
  begin
    GetColumnBounds(AContentWidth, NameL, NameR, TypeL, TypeR, SizeL, SizeR,
      DateL, DateR);
    Exit;
  end;

  ER := AContentWidth - SCROLLBAR_RESERVE;
  Pad := 8;
  Inner := ER - Pad * 2;
  if Inner < 40 then
    Inner := 40;
  if IsThisPCPath(GetCurrentPathImpl) then
    Parts := 3.4
  else
    Parts := 4.4;
  UnitW := Inner / Parts;
  NameL := Pad;
  NameR := NameL + UnitW * 1.4;
  TypeL := NameR;
  TypeR := TypeL + UnitW;
  SizeL := TypeR;
  SizeR := SizeL + UnitW;
  if IsThisPCPath(GetCurrentPathImpl) then
  begin
    DateL := SizeR;
    DateR := SizeR;
  end
  else
  begin
    DateL := SizeR;
    DateR := DateL + UnitW;
  end;
end;





procedure TFilePanel.ApplyPathEditTheme;
begin
  if not Assigned(FPathEdit) then
    Exit;
  FPathEdit.FillMode := fefTransparent;
  FPathEdit.ApplyTheme(FColors);
end;

procedure TFilePanel.RebuildBreadcrumbs;
var
  Full, Drive, Rest, Name, Acc: string;
  Slash, I: Integer;
  Names: TStringList;
  X: Single;
  Layout: TTextLayout;

  function Measure(const S: string): Single;
  begin
    Layout.BeginUpdate;
    try
      Layout.MaxSize := TPointF.Create(4000, 40);
      Layout.WordWrap := False;
      Layout.Text := S;
    finally
      Layout.EndUpdate;
    end;
    Result := Ceil(Layout.TextWidth) + 4;
  end;

  function AddChip(const AText, APath: string; AIndex: Integer): TRectangle;
  var
    Lbl: TText;
    W, H: Single;
  begin
    if AIndex < 0 then
      W := Measure(AText) + 2
    else
      W := Measure(AText) + 8;
    H := Max(FCrumbsHost.Height, 22);
    Result := TRectangle.Create(FCrumbsHost);
    Result.Parent := FCrumbsHost;
    Result.Align := TAlignLayout.None;
    Result.SetBounds(X, 0, W, H);
    Result.Stroke.Kind := TBrushKind.None;
    Result.Fill.Kind := TBrushKind.Solid;
    Result.Fill.Color := TAlphaColors.Null;
    Result.XRadius := 4;
    Result.YRadius := 4;
    Result.Tag := AIndex;
    Result.TagString := APath;
    { HitTest выключен: FMX бьёт детей в обратном порядке. Клик и hover — по X. }
    Result.HitTest := False;

    Lbl := TText.Create(Result);
    Lbl.Parent := Result;
    Lbl.Align := TAlignLayout.Client;
    Lbl.Text := AText;
    Lbl.HitTest := False;
    ApplyFluentText(Lbl, 14, True);
    Lbl.TextSettings.HorzAlign := TTextAlign.Center;
    Lbl.TextSettings.VertAlign := TTextAlign.Center;
    if AIndex >= 0 then
    begin
      if FActive then
        Lbl.TextSettings.FontColor := FColors.TextColor
      else
        Lbl.TextSettings.FontColor := FColors.SubTextColor;
    end
    else
      Lbl.TextSettings.FontColor := FColors.SubTextColor;
    if AIndex < 0 then
      X := X + W
    else
      X := X + W + 2;
  end;

begin
  if not Assigned(FCrumbsHost) or not Assigned(FCrumbPaths) then
    Exit;

  while FCrumbsHost.ControlsCount > 0 do
    FCrumbsHost.Controls[0].Free;
  FCrumbPaths.Clear;
  FCrumbHoverIdx := -1;
  if Assigned(FCrumbsBox) then
    FCrumbsBox.Cursor := crDefault;

  Full := ExcludeTrailingPathDelimiter(GetCurrentPathImpl);
  if Full = '' then
    Exit;

  Names := TStringList.Create;
  Layout := TTextLayoutManager.DefaultTextLayout.Create;
  Layout.Font.Family := FluentFontFamily;
  Layout.Font.Size := 14;
  Layout.Font.Style := [TFontStyle.fsBold];
  try
    Drive := ExtractFileDrive(Full);
    if IsVirtualShellPath(Full) then
    begin
      Acc := Full;
      while Acc <> '' do
      begin
        FCrumbPaths.Insert(0, Acc);
        Name := DisplayNameForPath(Acc);
        if Name = '' then
          Name := 'Устройство';
        Names.Insert(0, Name);
        if IsThisPCPath(Acc) then
          Break;
        Rest := ParentOfBrowsablePath(Acc);
        if (Rest = '') or SameText(Rest, Acc) then
          Break;
        Acc := Rest;
      end;
    end
    else if Drive = '' then
    begin
      FCrumbPaths.Add(Full);
      Names.Add(Full);
    end
    else
    begin
      Acc := IncludeTrailingPathDelimiter(Drive);
      FCrumbPaths.Add(Acc);
      Names.Add(Drive);

      Rest := Full;
      if StartsText(Acc, Rest) then
        Delete(Rest, 1, Length(Acc))
      else if StartsText(Drive, Rest) then
        Delete(Rest, 1, Length(Drive));
      if (Rest <> '') and (Rest[1] = '\') then
        Delete(Rest, 1, 1);

      while Rest <> '' do
      begin
        Slash := Pos('\', Rest);
        if Slash > 0 then
        begin
          Name := Copy(Rest, 1, Slash - 1);
          Delete(Rest, 1, Slash);
        end
        else
        begin
          Name := Rest;
          Rest := '';
        end;
        if Name = '' then
          Continue;
        Acc := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Acc)) + Name;
        FCrumbPaths.Add(Acc);
        Names.Add(Name);
      end;
    end;

    X := 4;
    for I := 0 to Names.Count - 1 do
    begin
      if I > 0 then
        AddChip('>', '', -1);
      AddChip(Names[I], FCrumbPaths[I], I);
    end;
    FCrumbsHost.Align := TAlignLayout.None;
    FCrumbsHost.Position.Point := TPointF.Create(0, 0);
    FCrumbsHost.Height := Max(FCrumbsBox.Height, 22);
    FCrumbsHost.Width := Max(X + 8, 20);
  finally
    Layout.Free;
    Names.Free;
  end;
end;

function TFilePanel.HitCrumbIndex(AContentX: Single): Integer;
var
  I, Idx: Integer;
  C: TControl;
begin
  Result := -1;
  if not Assigned(FCrumbsHost) then
    Exit;
  AContentX := AContentX - FCrumbsHost.Position.X;
  for I := 0 to FCrumbsHost.ControlsCount - 1 do
  begin
    C := FCrumbsHost.Controls[I];
    Idx := C.Tag;
    if (Idx < 0) or (Idx >= FCrumbPaths.Count) then
      Continue;
    if (AContentX >= C.Position.X) and (AContentX < C.Position.X + C.Width) then
      Exit(Idx);
  end;
end;

procedure TFilePanel.CrumbsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
  Target: string;
  ContentX: Single;
begin
  if Assigned(FOnActivate) then
    FOnActivate(Self);
  if Button <> TMouseButton.mbLeft then
    Exit;

  ContentX := X;
  if Assigned(FCrumbsBox) then
    ContentX := X + FCrumbsBox.ViewportPosition.X;
  Idx := HitCrumbIndex(ContentX);
  if (Idx >= 0) and (Idx < FCrumbPaths.Count) then
  begin
    Target := FCrumbPaths[Idx];
    if (Target <> '') and IsBrowsablePath(Target) then
      Navigate(Target);
    Exit;
  end;
  BeginPathEdit;
end;

procedure TFilePanel.CrumbsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  ContentX: Single;
begin
  ContentX := X;
  if Assigned(FCrumbsBox) then
    ContentX := X + FCrumbsBox.ViewportPosition.X;
  SetCrumbHover(HitCrumbIndex(ContentX));
end;

procedure TFilePanel.CrumbsMouseLeave(Sender: TObject);
begin
  SetCrumbHover(-1);
end;

procedure TFilePanel.SetCrumbHover(AIndex: Integer);
var
  I: Integer;
  C: TControl;
  Chip: TRectangle;
begin
  if AIndex = FCrumbHoverIdx then
    Exit;
  if Assigned(FCrumbsHost) then
    for I := 0 to FCrumbsHost.ControlsCount - 1 do
    begin
      C := FCrumbsHost.Controls[I];
      if not (C is TRectangle) then
        Continue;
      Chip := TRectangle(C);
      if Chip.Tag = FCrumbHoverIdx then
        Chip.Fill.Color := TAlphaColors.Null;
      if (AIndex >= 0) and (Chip.Tag = AIndex) then
        Chip.Fill.Color := FColors.ItemHover;
    end;
  FCrumbHoverIdx := AIndex;
  if Assigned(FCrumbsBox) then
  begin
    if AIndex >= 0 then
      FCrumbsBox.Cursor := crHandPoint
    else
      FCrumbsBox.Cursor := crDefault;
  end;
end;

procedure TFilePanel.BeginPathEdit;
begin
  if not Assigned(FPathEdit) or not Assigned(FCrumbsBox) then
    Exit;
  FCrumbsBox.Visible := False;
  FPathEdit.Text := GetCurrentPathImpl;
  FPathEdit.Visible := True;
  FPathEdit.SetFocus;
  FPathEdit.SelectAll;
end;

procedure TFilePanel.EndPathEdit(AApply: Boolean);
var
  Target, SelectPath: string;
begin
  if FEndingPathEdit or not Assigned(FPathEdit) or not FPathEdit.Visible then
    Exit;
  FEndingPathEdit := True;
  try
  Target := NormalizePastedPath(FPathEdit.Text);
  FPathEdit.Visible := False;
  if Assigned(FCrumbsBox) then
    FCrumbsBox.Visible := True;
  if AApply and (Target <> '') then
  begin
    SelectPath := '';
    if TFile.Exists(Target) then
    begin
      SelectPath := Target;
      Target := ExtractFilePath(Target);
    end;
    if IsBrowsablePath(Target) then
      Navigate(Target, SelectPath);
  end;
  RebuildBreadcrumbs;
  finally
    FEndingPathEdit := False;
  end;
end;

procedure TFilePanel.PathEditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    EndPathEdit(True);
    Key := 0;
  end
  else if Key = vkEscape then
  begin
    EndPathEdit(False);
    Key := 0;
  end;
end;

procedure TFilePanel.PathEditSubmit(Sender: TObject);
begin
  EndPathEdit(True);
end;

procedure TFilePanel.PathEditExit(Sender: TObject);
begin
  EndPathEdit(False);
end;

function TFilePanel.NormalizePastedPath(const AText: string): string;
begin
  Result := Trim(AText);
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  Result := ExcludeTrailingPathDelimiter(Result);
end;

function TFilePanel.IsPathEditing: Boolean;
begin
  Result := Assigned(FPathEdit) and FPathEdit.Visible and FPathEdit.IsFocused;
end;

procedure TFilePanel.CancelPathEdit;
begin
  EndPathEdit(False);
  EndInlineRename(False);
end;

procedure TFilePanel.EmptyAreaMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  CancelPathEdit;
  if Assigned(FOnActivate) then
    FOnActivate(Self);
  if CanFocus then
    SetFocus;
end;

procedure TFilePanel.CopySelectionToClipboard(ACut: Boolean);
var
  Paths: TArray<string>;
  I: Integer;
  Arc, Inner, LocalDir: string;
begin
  Paths := CollectDragPaths;
  if Length(Paths) = 0 then
    Exit;
  {$IFDEF MSWINDOWS}
  for I := 0 to High(Paths) do
    if SplitArchivePath(Paths[I], Arc, Inner) and (Inner <> '') then
    begin
      LocalDir := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath, 'TCClone');
      ForceDirectories(LocalDir);
      CopyPathSync(Paths[I], LocalDir);
      Paths[I] := System.IOUtils.TPath.Combine(LocalDir,
        ExtractFileName(ExcludeTrailingPathDelimiter(Paths[I])));
    end;
  CopyFilesToClipboard(Paths, ACut);
  {$ENDIF}
end;

procedure TShotSaveJob.Execute;
var
  FS: TFileStream;
begin
  Ok := False;
  try
    FS := TFileStream.Create(Dest, fmCreate);
    try
      if Length(Bytes) > 0 then
        FS.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
    Ok := True;
  except
    Ok := False;
    if (Dest <> '') and TFile.Exists(Dest) then
      try
        if TFile.GetSize(Dest) = 0 then
          TFile.Delete(Dest);
      except
      end;
  end;
  TThread.Queue(nil, Apply);
end;

procedure TShotSaveJob.Apply;
var
  P: TFilePanel;
  Folder: string;
begin
  P := Panel;
  try
    if (P <> nil) and (P.FShotJob = Self) then
      P.FShotJob := nil;
    if (P <> nil) and (not P.FDestroying) and SameText(P.FPendingShot, Dest) then
      P.FPendingShot := '';
    if (P = nil) or P.FDestroying then
      Exit;
    if not Ok then
    begin
      P.ShowNotice('Не удалось записать снимок');
      Exit;
    end;
    Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(Dest));
    if SameText(ExcludeTrailingPathDelimiter(P.GetCurrentPathImpl), Folder) then
      P.Refresh(Dest);
  finally
    Free;
  end;
end;

function NextShotFile(const ADir, APending: string): string;
var
  Stamp, Base, Name, Full: string;
  N: Integer;
begin
  Stamp := FormatDateTime('yyyy-mm-dd hh-nn-ss', Now);
  Base := 'ScreenShot ' + Stamp;
  N := 1;
  repeat
    if N = 1 then
      Name := Base + '.png'
    else
      Name := Format('%s (%d).png', [Base, N]);
    Full := System.IOUtils.TPath.Combine(ADir, Name);
    Inc(N);
  until (not TFile.Exists(Full)) and (not SameText(Full, APending));
  Result := Full;
end;

procedure TFilePanel.HandlePaste;
var
  Files: TArray<string>;
  Cut: Boolean;
  TextPath, Target, SelectPath, Dir, Dest: string;
  Svc: IFMXClipboardService;
  Clip: TValue;
  Png: TBytes;
  Arc, Inner: string;
  Job: TShotSaveJob;
  FS: TFileStream;

  function FolderOk: Boolean;
  begin
    Result := False;
    Dir := GetCurrentPathImpl;
    if IsSearchView or IsOffline or IsThisPCPath(Dir) or IsVirtualShellPath(Dir) or
       IsPortableDevicePath(Dir) or IsDeviceNamespacePath(Dir) or
       SplitArchivePath(Dir, Arc, Inner) or (not TDirectory.Exists(Dir)) then
    begin
      ShowNotice('Некуда вставить');
      Exit;
    end;
    Result := True;
  end;

begin
  {$IFDEF MSWINDOWS}
  if TryGetClipboardFiles(Files, Cut) and (Length(Files) > 0) then
  begin
    ApplyDrop(GetCurrentPathImpl, Files, Cut, nil);
    Exit;
  end;
  if TryClipboardImagePng(Png) then
  begin
    if not FolderOk then
      Exit;
    Dest := NextShotFile(Dir, FPendingShot);
    FPendingShot := Dest;
    if IsRemotePath(Dir) then
    begin
      if FShotJob <> nil then
        TShotSaveJob(FShotJob).Panel := nil;
      Job := TShotSaveJob.Create;
      Job.Panel := Self;
      Job.Dest := Dest;
      Job.Bytes := Png;
      FShotJob := Job;
      TThread.CreateAnonymousThread(
        procedure
        begin
          Job.Execute;
        end).Start;
      Exit;
    end;
    try
      FS := TFileStream.Create(Dest, fmCreate);
      try
        FS.WriteBuffer(Png[0], Length(Png));
      finally
        FS.Free;
      end;
      FPendingShot := '';
      Refresh(Dest);
    except
      FPendingShot := '';
      if TFile.Exists(Dest) then
        try
          if TFile.GetSize(Dest) = 0 then
            TFile.Delete(Dest);
        except
        end;
      ShowNotice('Не удалось записать снимок');
    end;
    Exit;
  end;
  {$ENDIF}

  TextPath := '';
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
  begin
    Clip := Svc.GetClipboard;
    if not Clip.IsEmpty then
      TextPath := NormalizePastedPath(Clip.ToString);
  end;
  if TextPath = '' then
    Exit;

  if IsBrowsablePath(TextPath) then
    Navigate(TextPath)
  else if TFile.Exists(TextPath) then
  begin
    SelectPath := TextPath;
    Target := ExtractFilePath(TextPath);
    Navigate(Target, SelectPath);
  end
  else
  begin
    BeginPathEdit;
    if Assigned(FPathEdit) then
      FPathEdit.Text := TextPath;
  end;
end;

function TFilePanel.CurrentScrollBox: TVertScrollBox;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].ScrollBox
  else
    Result := nil;
end;

function TFilePanel.CurrentPaintBox: TPaintBox;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    Result := FTabs[FActiveTabIndex].PaintBox
  else
    Result := nil;
end;

function TFilePanel.TileSize: Integer;
begin
  Result := Round(BASE_TILE_SIZE * ZoomPercent / 100);
  if Result < MIN_TILE_SIZE then
    Result := MIN_TILE_SIZE;
  if Result > MAX_TILE_SIZE then
    Result := MAX_TILE_SIZE;
end;

function TFilePanel.RowHeight: Integer;
var
  SB: TVertScrollBox;
  W: Single;
begin
  Result := Round(BASE_ROW_HEIGHT * ZoomPercent / 100);
  if ViewMode <> vmDetails then
    Exit;
  SB := CurrentScrollBox;
  if Assigned(SB) then
    W := SB.Width
  else
    W := Width;
  RecalcColLayout(W);
  if FColTwoLine then
    Result := Round(Result * 1.9);
end;

procedure TFilePanel.GetTileLayout(AWidth: Single; out ACols, ATS: Integer;
  out ATileH, ASlotW, APadX: Single);
var
  Avail, MinSlot: Single;
begin
  ATS := TileSize;
  ATileH := ATS + TILE_TEXT_ZONE + TILE_GAP;
  MinSlot := ATS + TILE_GAP;
  Avail := AWidth;
  if Avail < MinSlot then
    Avail := MinSlot;
  ACols := Max(1, Trunc(Avail / MinSlot));
  ASlotW := Avail / ACols;
  APadX := (ASlotW - ATS) * 0.5;
end;

procedure TFilePanel.KeepFocusVisible;
begin
  if FDestroying or not Assigned(FSelectionManager) then
    Exit;
  if FSelectionManager.CurrentIndex >= 0 then
    EnsureIndexVisible(FSelectionManager.CurrentIndex);
end;

procedure TFilePanel.DoAddTab(const APath: string; Activate: Boolean);
var
  ContainerLayout: TLayout;
  SB: TVertScrollBox;
  PB: TPaintBox;
  BgRect: TRectangle;
  Tab: TFileTab;
  Target: string;
  CustomScrollbar: TCustomFileScrollbar;
  TabName: string;
  NewIdx: Integer;
begin
  Target := APath;
  if Trim(Target) = '' then
    Target := ExtractFileDrive(ParamStr(0)) + '\';
  if (Target = '') or (Target = '\') then
    Target := 'C:\';

  TabName := DisplayNameForPath(Target);

  ContainerLayout := TLayout.Create(Self);
  if Assigned(FCard) then
    ContainerLayout.Parent := FCard
  else
    ContainerLayout.Parent := Self;
  ContainerLayout.Align := TAlignLayout.Client;
  ContainerLayout.Visible := False;

  SB := TVertScrollBox.Create(Self);
  SB.Parent := ContainerLayout;
  SB.Align := TAlignLayout.Client;
  SB.ShowScrollBars := False;
  SB.AniCalculations.AutoShowing := False;
  SB.OnMouseWheel := PanelMouseWheel;
  SB.OnResize := ScrollBoxResize;
  SB.OnViewportPositionChange := ScrollBoxViewportPositionChange;
  SB.OnMouseDown := EmptyAreaMouseDown;
  ContainerLayout.OnMouseDown := EmptyAreaMouseDown;

  BgRect := TRectangle.Create(Self);
  BgRect.Parent := SB.Content;
  BgRect.Align := TAlignLayout.Client;
  BgRect.Fill.Kind := TBrushKind.Solid;
  BgRect.Fill.Color := FColors.PanelBackground;
  BgRect.Stroke.Kind := TBrushKind.None;
  BgRect.HitTest := True;
  BgRect.OnMouseDown := EmptyAreaMouseDown;
  BindDragEvents(BgRect);

  PB := TPaintBox.Create(Self);
  PB.Parent := SB.Content;
  PB.Align := TAlignLayout.Top;
  PB.OnPaint := PaintBoxPaint;
  PB.OnMouseDown := PaintBoxMouseDown;
  PB.OnMouseMove := PaintBoxMouseMove;
  PB.OnMouseUp := PaintBoxMouseUp;
  PB.OnDblClick := PaintBoxDblClick;
  PB.OnMouseLeave := PaintBoxMouseLeave;
  PB.OnMouseWheel := PanelMouseWheel;
  BindDragEvents(PB);
  BindDragEvents(SB);
  BindDragEvents(ContainerLayout);

  CustomScrollbar := TCustomFileScrollbar.Create(ContainerLayout, SB);

  Tab.Path := Target;
  Tab.ContainerLayout := ContainerLayout;
  Tab.ScrollBox := SB;
  Tab.BgRect := BgRect;
  Tab.PaintBox := PB;
  Tab.LastVisitedPath := '';
  Tab.History := [NormDirHistoryPath(Target)];
  Tab.HistoryIndex := 0;
  Tab.Scrollbar := CustomScrollbar;

  Tab.Entries := uFileModel.TFileEntryList.Create;
  Tab.SelectedIndices := TList<Integer>.Create;
  Tab.AnchorIndex := 0;
  Tab.ViewMode := vmDetails;
  Tab.ZoomDetails := 100;
  Tab.ZoomTiles := 100;
  Tab.SortField := sfName;
  Tab.SortAsc := True;
  Tab.CursorIndex := 0;
  Tab.CursorPath := '';
  Tab.Loaded := False;
  Tab.Stale := False;
  Tab.BranchView := False;
  Tab.SearchView := False;
  Tab.Watcher := nil;
  Tab.Loading := False;
  Tab.LoadQueued := False;
  Tab.LoadGen := 0;
  Tab.LoadTick := 0;
  Tab.LoadError := '';
  Tab.LoadThread := nil;
  Tab.LoadPath := '';
  Tab.RefreshPending := False;
  Tab.PendingSelect := '';
  Tab.PendingKeepSel := False;
  Tab.Offline := False;
  Tab.Partial := False;
  Tab.AutoRetryUsed := False;
  Tab.LoadSeen := 0;
  Tab.LoadSeenWatch := 0;

  FTabs.Add(Tab);

  NewIdx := FTabsBar.AddTab(TabName, ContainerLayout, Target, Activate);

  if Activate then
  begin
    FActiveTabIndex := NewIdx;
    FTabsBar.ActiveIndex := NewIdx;
  end;

  CustomScrollbar.UpdateThumb;
end;

procedure TFilePanel.AddTab(const APath: string);
var
  P: string;
begin
  P := APath;
  if P = '' then
  begin
    if FTabs.Count > 0 then
      P := FTabs[FActiveTabIndex].Path
    else
      P := GetCurrentPathImpl;
  end;

  if (P = '') or not IsListablePath(P) then
    P := 'C:\';

  DoAddTab(P, True);
  Navigate(P);
end;

procedure TFilePanel.CloseCurrentTab;
begin
  if FTabs.Count <= 1 then Exit;
  FTabsBar.RemoveTab(FActiveTabIndex);
end;

procedure TFilePanel.HandleTabChange(Sender: TObject; AIndex: Integer);
var
  Prev: Integer;
  NeedLoad: Boolean;
  Tab: TFileTab;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then Exit;

  Prev := FActiveTabIndex;
  if (Prev >= 0) and (Prev < FTabs.Count) and (Prev <> AIndex) then
  begin
    SuspendNameFilter;
    SaveTabCursor(Prev);
  end;

  FActiveTabIndex := AIndex;

  for var I := 0 to FTabs.Count - 1 do
    if Assigned(FTabs[I].ContainerLayout) then
      FTabs[I].ContainerLayout.Visible := (I = FActiveTabIndex);

  RestoreTabCursor(AIndex);

  UpdatePathLabel;
  SyncDriveBar;

  Tab := FTabs[AIndex];
  if FDeferDirLoad then
  begin
    Tab.Stale := True;
    Tab.Loaded := False;
    FTabs[AIndex] := Tab;
    UpdateHistoryButtons;
    NotifyCursorChange;
    Exit;
  end;
  NeedLoad := (not Tab.Loaded) or Tab.Stale or not Assigned(Tab.Entries);
  if NeedLoad then
  begin
    Tab.Stale := False;
    FTabs[AIndex] := Tab;
    Refresh('', True);
  end
  else
  begin
    if FNameFilter <> '' then
      CommitNameFilter(False)
    else
    begin
      RebuildContent;
      UpdateStatusText;
      KeepFocusVisible;
    end;
  end;
  if FWatchEnabled and (not Tab.Loading) and Tab.Loaded then
    WatchTab(AIndex);
  UpdateLoadChrome;
  UpdateHistoryButtons;
  NotifyCursorChange;
end;

procedure TFilePanel.HandleTabClose(Sender: TObject; AIndex: Integer; var ACanClose: Boolean);
var
  Tab: TFileTab;
begin
  if FTabs.Count <= 1 then
  begin
    ACanClose := False;
    Exit;
  end;

  if (AIndex < 0) or (AIndex >= FTabs.Count) then
  begin
    ACanClose := False;
    Exit;
  end;

  Tab := FTabs[AIndex];
  AbandonTabLoad(AIndex);
  Tab := FTabs[AIndex];
  if Assigned(Tab.Watcher) then
  begin
    Tab.Watcher.OnChange := nil;
    FreeAndNil(Tab.Watcher);
  end;
  if Assigned(Tab.Scrollbar) then FreeAndNil(Tab.Scrollbar);
  if Assigned(Tab.ContainerLayout) then FreeAndNil(Tab.ContainerLayout);
  if Assigned(Tab.Entries) then FreeAndNil(Tab.Entries);
  if Assigned(Tab.SelectedIndices) then FreeAndNil(Tab.SelectedIndices);

  FTabs.Delete(AIndex);

  if AIndex = FActiveTabIndex then
    FActiveTabIndex := -1
  else if AIndex < FActiveTabIndex then
    Dec(FActiveTabIndex);

  ACanClose := True;
end;

procedure TFilePanel.HandleTabAdd;
begin
  AddTab(GetCurrentPathImpl);
end;

procedure TFilePanel.HandleTabReorder(Sender: TObject; AFromIndex, AToIndex: Integer);
var
  Tab: TFileTab;
  I: Integer;
begin
  if (AFromIndex < 0) or (AFromIndex >= FTabs.Count) then
    Exit;
  if (AToIndex < 0) or (AToIndex >= FTabs.Count) then
    Exit;
  if AFromIndex = AToIndex then
    Exit;

  Tab := FTabs[AFromIndex];
  FTabs.Delete(AFromIndex);
  FTabs.Insert(AToIndex, Tab);
  if Assigned(FTabsBar) then
    FActiveTabIndex := FTabsBar.ActiveIndex
  else
    FActiveTabIndex := AToIndex;

  for I := 0 to FTabs.Count - 1 do
    if Assigned(FTabs[I].ContainerLayout) then
      FTabs[I].ContainerLayout.Visible := (I = FActiveTabIndex);
end;

procedure TFilePanel.HandleTabDragQuery(Sender: TObject; AIndex: Integer; var APath: string);
begin
  if (AIndex >= 0) and (AIndex < FTabs.Count) then
    APath := FTabs[AIndex].Path;
end;

function TFilePanel.PointOverTabBar(const AAbsPt: TPointF): Boolean;
begin
  Result := Assigned(FTabsBar) and Assigned(FTabsBar.Container) and
    FTabsBar.Container.AbsoluteRect.Contains(AAbsPt);
end;

procedure TFilePanel.AcceptForeignTab(const APath: string; AInsertBefore: Integer);
var
  NewIdx: Integer;
begin
  AddTab(APath);
  NewIdx := FTabs.Count - 1;
  if (AInsertBefore >= 0) and (AInsertBefore < NewIdx) then
    FTabsBar.MoveTab(NewIdx, AInsertBefore);
  if Assigned(FOnActivate) then
    FOnActivate(Self);
end;

function TFilePanel.FindTarget(P: TPointF; const Data: TDragObject): IControl;
var
  LP: TPointF;
begin
  if IsTabDragActive and Visible then
  begin
    LP := P;
    if Scene <> nil then
      LP := Scene.ScreenToLocal(LP);
    if PointInObject(LP.X, LP.Y) then
      Exit(Self);
    Result := nil;
    Exit;
  end;
  Result := inherited FindTarget(P, Data);
end;

procedure TFilePanel.HandleTabDragOver(Sender: TObject; const Point: TPointF;
  var Operation: TDragOperation);
var
  AbsPt: TPointF;
  OverBar: Boolean;
begin
  Operation := TDragOperation.None;
  if not Assigned(FTabsBar) then
    Exit;

  if Sender is TControl then
    AbsPt := TControl(Sender).LocalToAbsolute(Point)
  else
    AbsPt := Point;

  OverBar := PointOverTabBar(AbsPt);
  if TabDragSourceIs(FTabsBar) then
  begin
    if OverBar then
    begin
      Operation := TDragOperation.Move;
      FTabsBar.ShowDropHint(FTabsBar.HitInsertIndex(AbsPt));
    end
    else
      FTabsBar.HideDropHint;
  end
  else
  begin
    Operation := TDragOperation.Move;
    if OverBar then
      FTabsBar.ShowDropHint(FTabsBar.HitInsertIndex(AbsPt))
    else
      FTabsBar.ShowDropHint(FTabsBar.TabCount);
  end;
end;

procedure TFilePanel.HandleTabDragDrop(Sender: TObject; const Point: TPointF);
var
  AbsPt: TPointF;
  Ins: Integer;
  OverBar, SameBar: Boolean;
  Path: string;
  SrcIdx: Integer;
  DestBar: TCustomTabsBar;
begin
  if not Assigned(FTabsBar) then
  begin
    ClearTabDrag;
    Exit;
  end;

  if Sender is TControl then
    AbsPt := TControl(Sender).LocalToAbsolute(Point)
  else
    AbsPt := Point;
  OverBar := PointOverTabBar(AbsPt);
  SameBar := TabDragSourceIs(FTabsBar);
  Path := TabDragPath;
  SrcIdx := TabDragSourceIndex;
  DestBar := FTabsBar;
  if OverBar then
    Ins := FTabsBar.HitInsertIndex(AbsPt)
  else
    Ins := -1;

  FTabsBar.HideDropHint;
  ClearTabDrag;

  { RebuildTabs освобождает TTabChrome, который ещё в стеке DoDragDrop — откладываем. }
  TThread.ForceQueue(nil,
    procedure
    begin
      if SameBar then
      begin
        if OverBar and Assigned(DestBar) then
          DestBar.MoveTab(SrcIdx, Ins);
      end
      else if Path <> '' then
        AcceptForeignTab(Path, Ins);
    end);
end;

procedure TFilePanel.Navigate(const APath: string; const ASelectPath: string = '');
var
  TargetPath: string;
  SameDir: Boolean;
  CurEntries: uFileModel.TFileEntryList;
begin
  EndInlineRename(False);
  TargetPath := APath;
  if not IsListablePath(TargetPath) then
    TargetPath := 'C:\';

  if not IsListablePath(TargetPath) then
    Exit;

  SameDir := SameDirHistoryPath(GetCurrentPathImpl, TargetPath);
  CurEntries := GetCurrentEntries;

  if FTabs.Count = 0 then
    DoAddTab(TargetPath, True)
  else if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
  begin
    var Tab := FTabs[FActiveTabIndex];
    Tab.Path := TargetPath;
    Tab.Loaded := SameDir;
    Tab.Stale := False;
    Tab.BranchView := False;
    Tab.SearchView := False;
    Tab.LoadError := '';
    Tab.Offline := False;
    Tab.Partial := False;
    Tab.AutoRetryUsed := False;
    Tab.LoadSeen := 0;
    Tab.LoadSeenWatch := 0;
    Tab.CursorIndex := 0;
    if ASelectPath <> '' then
      Tab.CursorPath := ASelectPath
    else
      Tab.CursorPath := '';
    if (not SameDir) and IsRemotePath(TargetPath) and Assigned(Tab.Entries) then
      Tab.Entries.Clear;
    FTabs[FActiveTabIndex] := Tab;
    var TabCaption := DisplayNameForPath(TargetPath);
    FTabsBar.SetTabInfo(FActiveTabIndex, TabCaption, TargetPath);
  end;

  if Assigned(FSelectionManager) then
  begin
    var SelIndices := GetCurrentSelectedIndices;
    if Assigned(SelIndices) then SelIndices.Clear;
    FSelectionManager.ResetState(0);
  end;

  InvalidateView;

  UpdatePathLabel;
  SyncDriveBar;
  RememberDrivePath(TargetPath);

  if Assigned(FOnPathChanged) then
    FOnPathChanged(Self, TargetPath);

  if not FHistorySilent then
    RecordHistory(TargetPath)
  else
    UpdateHistoryButtons;

  Refresh(ASelectPath);
  { Та же папка: список уже на экране, не ждать перечитывания —
    иначе курсор остаётся на «..», пока поток не отбросит тот же listing. }
  if SameDir and (ASelectPath <> '') and Assigned(CurEntries) then
  begin
    ApplyCursorAfterLoad(CurEntries, ASelectPath, False);
    KeepFocusVisible;
    InvalidateView;
  end;
  if IsRemotePath(TargetPath) then
    UpdateLoadChrome;
end;



procedure TFilePanel.Refresh(const ASelectPath: string; AKeepSelection: Boolean);
var
  Path: string;
begin
  if FDestroying then Exit;
  if IsSearchView then
    Exit;

  Path := GetCurrentPathImpl;
  if (Path = '') or (not IsListablePath(Path)) then Exit;

  if AKeepSelection then
  begin
    CaptureSelection(FKeepSelPaths, FKeepSelFocus);
    if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    begin
      var TabCursor := FTabs[FActiveTabIndex].CursorPath;
      if TabCursor <> '' then
      begin
        if (FKeepSelFocus = '') or ((FKeepSelFocus = #1) and (TabCursor <> #1)) then
          FKeepSelFocus := TabCursor;
      end;
    end;
  end
  else if Assigned(FKeepSelPaths) then
  begin
    FKeepSelPaths.Clear;
    FKeepSelFocus := '';
  end;

  if Assigned(FSelectionManager) then
    FPendingCursorIndex := FSelectionManager.CurrentIndex
  else
    FPendingCursorIndex := 0;

  StartDirLoad(Path, ASelectPath, AKeepSelection);
end;

procedure TFilePanel.ApplyCursorAfterLoad(AList: uFileModel.TFileEntryList;
  const ASelectPath: string; AKeepSel: Boolean);
var
  I, Found, ScreenIndex, Total, Idx: Integer;
begin
  if not Assigned(FSelectionManager) then
    Exit;

  Total := 0;
  if Assigned(AList) then
    Total := AList.Count;
  if HasParentDirectory then
    Inc(Total);

  if ASelectPath <> '' then
  begin
    Found := -1;
    if Assigned(AList) then
      for I := 0 to AList.Count - 1 do
        if SameText(AList[I].FullPath, ASelectPath) or
           SameText(ExcludeTrailingPathDelimiter(AList[I].FullPath),
                    ExcludeTrailingPathDelimiter(ASelectPath)) or
           SameText(AList[I].Name,
             ExtractFileName(ExcludeTrailingPathDelimiter(ASelectPath))) then
        begin
          Found := I;
          Break;
        end;
    if Found >= 0 then
    begin
      ScreenIndex := Found;
      if HasParentDirectory then
        Inc(ScreenIndex);
      FSelectionManager.ResetState(ScreenIndex);
      if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
        SaveTabCursor(FActiveTabIndex);
      Exit;
    end;
  end;

  if AKeepSel then
    Idx := FSelectionManager.CurrentIndex
  else
    Idx := FPendingCursorIndex;
  if Idx < 0 then
    Idx := 0;
  if Total <= 0 then
    Idx := 0
  else if Idx >= Total then
    Idx := Total - 1;

  if AKeepSel then
    FSelectionManager.CurrentIndex := Idx
  else
    FSelectionManager.ResetState(Idx);

  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    SaveTabCursor(FActiveTabIndex);
end;

function TFilePanel.ActiveLoadCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FTabs.Count - 1 do
    if Assigned(FTabs[I].LoadThread) then
      Inc(Result);
end;

procedure TFilePanel.AbandonTabLoad(ATabIndex: Integer);
var
  Tab: TFileTab;
  T: TThread;
begin
  if (ATabIndex < 0) or (ATabIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[ATabIndex];
  Inc(Tab.LoadGen);
  Tab.Loading := False;
  Tab.LoadQueued := False;
  Tab.RefreshPending := False;
  Tab.PendingSelect := '';
  Tab.PendingKeepSel := False;
  Tab.LoadPath := '';
  T := Tab.LoadThread;
  Tab.LoadThread := nil;
  FTabs[ATabIndex] := Tab;
  if T = nil then
    Exit;
  T.OnTerminate := nil;
  T.Terminate;
  T.FreeOnTerminate := True;
end;

function TFilePanel.IndexOfLoadThread(AThr: TThread): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AThr = nil then
    Exit;
  for I := 0 to FTabs.Count - 1 do
    if FTabs[I].LoadThread = AThr then
      Exit(I);
end;

procedure TFilePanel.ContinueAfterLoad(ATabIndex: Integer);
var
  Tab: TFileTab;
  Sel: string;
  Keep: Boolean;
begin
  if FDestroying then
    Exit;
  if (ATabIndex < 0) or (ATabIndex >= FTabs.Count) then
  begin
    PumpLoadQueue;
    Exit;
  end;
  Tab := FTabs[ATabIndex];
  if Tab.RefreshPending or
     (FRefreshPending and (ATabIndex = FActiveTabIndex)) then
  begin
    Tab.RefreshPending := False;
    Sel := Tab.PendingSelect;
    Keep := Tab.PendingKeepSel;
    Tab.PendingSelect := '';
    Tab.PendingKeepSel := False;
    FTabs[ATabIndex] := Tab;
    if ATabIndex = FActiveTabIndex then
      FRefreshPending := False;
    StartDirLoadAt(ATabIndex, Tab.Path, Sel, Keep);
  end
  else
    PumpLoadQueue;
end;

procedure TFilePanel.PumpLoadQueue;
var
  I: Integer;
  Tab: TFileTab;
begin
  if FDestroying then
    Exit;
  if ActiveLoadCount >= 3 then
    Exit;
  for I := 0 to FTabs.Count - 1 do
  begin
    Tab := FTabs[I];
    if Tab.LoadQueued then
    begin
      Tab.LoadQueued := False;
      FTabs[I] := Tab;
      StartDirLoadAt(I, Tab.Path, '', True);
      if ActiveLoadCount >= 3 then
        Exit;
    end;
  end;
end;

procedure TFilePanel.UpdateLoadChrome;
var
  Tab: TFileTab;
  I: Integer;
  AnyRemote: Boolean;
  Busy: Boolean;
begin
  if FDestroying then
    Exit;
  AnyRemote := False;
  for I := 0 to FTabs.Count - 1 do
  begin
    Busy := FTabs[I].Loading and IsRemotePath(FTabs[I].Path);
    if Assigned(FTabsBar) then
      FTabsBar.SetTabBusy(I, Busy);
    if Busy then
      AnyRemote := True;
  end;
  if Assigned(FLoadWatchTimer) then
    FLoadWatchTimer.Enabled := AnyRemote;
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[FActiveTabIndex];
  if Tab.Loading and IsRemotePath(Tab.Path) then
    UpdateStatusText;
  if Assigned(FNetPulseTimer) then
    FNetPulseTimer.Enabled := IsRemotePath(Tab.Path) and (not Tab.Loading);
  if Assigned(FRetryBtn) then
    FRetryBtn.Visible := False;
  InvalidateView;
end;

procedure TFilePanel.LoadWatchTick(Sender: TObject);
var
  I, N: Integer;
  Tab: TFileTab;
  NowTick: Cardinal;
  Changed: Boolean;
begin
  if FDestroying then
    Exit;
  Changed := False;
  NowTick := GetTickCount;
  for I := 0 to FTabs.Count - 1 do
  begin
    Tab := FTabs[I];
    if not Tab.Loading then
      Continue;
    if not IsRemotePath(Tab.Path) then
      Continue;
    if (NowTick - Tab.LoadTick) < 8000 then
      Continue;
    if Tab.LoadSeen > Tab.LoadSeenWatch then
    begin
      Tab.LoadSeenWatch := Tab.LoadSeen;
      FTabs[I] := Tab;
      Continue;
    end;
    N := 0;
    if Assigned(Tab.Entries) then
      N := Tab.Entries.Count;
    StopRemoteLoad(I);
    Tab := FTabs[I];
    if N = 0 then
    begin
      Tab.Partial := True;
      Tab.Offline := True;
      Tab.LoadError := '';
      FTabs[I] := Tab;
      if not Tab.AutoRetryUsed then
      begin
        Tab.AutoRetryUsed := True;
        Tab.Partial := False;
        Tab.Offline := False;
        FTabs[I] := Tab;
        StartDirLoadAt(I, Tab.Path, '', True);
      end;
    end
    else
    begin
      Tab.Partial := True;
      Tab.Offline := False;
      Tab.LoadError := '';
      FTabs[I] := Tab;
    end;
    Changed := True;
  end;
  if Changed then
    UpdateLoadChrome;
  PumpLoadQueue;
end;

procedure TFilePanel.RetryLoadClick(Sender: TObject);
begin
  ResumeRemoteRead;
end;

procedure TFilePanel.StopRemoteLoad(AIndex: Integer);
var
  Tab: TFileTab;
  T: TThread;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  Tab.Loading := False;
  Tab.LoadQueued := False;
  Tab.RefreshPending := False;
  T := Tab.LoadThread;
  Tab.LoadThread := nil;
  FTabs[AIndex] := Tab;
  if T = nil then
    Exit;
  T.OnTerminate := nil;
  T.Terminate;
  T.FreeOnTerminate := True;
end;

function TFilePanel.IndexOfLoadGen(AGen: Integer; const APath: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FTabs.Count - 1 do
    if (FTabs[I].LoadGen = AGen) and SameDirHistoryPath(FTabs[I].Path, APath) then
      Exit(I);
end;

procedure TFilePanel.NoteRemoteProgress(AIndex: Integer; ACount: Integer);
var
  Tab: TFileTab;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  Tab.LoadTick := GetTickCount;
  if ACount > Tab.LoadSeen then
    Tab.LoadSeen := ACount;
  FTabs[AIndex] := Tab;
  if AIndex = FActiveTabIndex then
    UpdateLoadChrome;
end;

procedure TFilePanel.AppendRemoteChunk(AIndex: Integer; ASlice: uFileModel.TFileEntryList;
  ADone: Boolean);
var
  Tab: TFileTab;
  Seen: TDictionary<string, Boolean>;
  E: TFileEntry;
  I: Integer;
begin
  try
    if (AIndex < 0) or (AIndex >= FTabs.Count) or FDestroying then
      Exit;
    Tab := FTabs[AIndex];
    if Tab.Entries = nil then
    begin
      Tab.Entries := uFileModel.TFileEntryList.Create;
      FTabs[AIndex] := Tab;
    end;
    if Assigned(ASlice) and (ASlice.Count > 0) then
    begin
      Seen := TDictionary<string, Boolean>.Create;
      try
        for I := 0 to Tab.Entries.Count - 1 do
          Seen.AddOrSetValue(AnsiLowerCase(Tab.Entries[I].FullPath), True);
        for E in ASlice do
        begin
          if (E.FullPath <> '') and Seen.ContainsKey(AnsiLowerCase(E.FullPath)) then
            Continue;
          Tab.Entries.Add(E);
          if E.FullPath <> '' then
            Seen.AddOrSetValue(AnsiLowerCase(E.FullPath), True);
        end;
      finally
        Seen.Free;
      end;
    end;
    Tab.Loaded := True;
    Tab.Stale := False;
    Tab.LoadTick := GetTickCount;
    if Tab.Entries.Count > Tab.LoadSeen then
      Tab.LoadSeen := Tab.Entries.Count;
    if ADone then
    begin
      Tab.Loading := False;
      Tab.Partial := False;
      Tab.Offline := False;
      Tab.LoadError := '';
      Tab.LoadPath := '';
      if (AIndex = FActiveTabIndex) and (FNameFilter <> '') then
      begin
        var KeepPaths := TStringList.Create;
        var KeepFocus := '';
        try
          KeepPaths.CaseSensitive := False;
          CaptureFilterIdentity(KeepPaths, KeepFocus);
          SortEntries(Tab.Entries, Tab.SortField, Tab.SortAsc);
          FTabs[AIndex] := Tab;
          RebuildFilterMap;
          RestoreFilterIdentity(KeepPaths, KeepFocus, False, False);
        finally
          KeepPaths.Free;
        end;
      end
      else
        SortEntries(Tab.Entries, Tab.SortField, Tab.SortAsc);
    end;
    FTabs[AIndex] := Tab;
    if AIndex = FActiveTabIndex then
    begin
      UpdateLongestType(Tab.Entries);
      if FNameFilter <> '' then
        CommitNameFilter(False)
      else
      begin
        UpdateStatusText;
        RebuildContent;
      end;
      InvalidateView;
      if ADone then
      begin
        if FWatchEnabled then
          WatchTab(AIndex);
        UpdateLoadChrome;
      end;
    end;
  finally
    if Assigned(ASlice) then
      ASlice.Free;
  end;
end;

procedure TFilePanel.ResumeRemoteRead;
var
  Tab: TFileTab;
begin
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[FActiveTabIndex];
  Tab.Partial := False;
  Tab.Offline := False;
  Tab.LoadError := '';
  FTabs[FActiveTabIndex] := Tab;
  CaptureSelection(FKeepSelPaths, FKeepSelFocus);
  StartDirLoadAt(FActiveTabIndex, Tab.Path, '', True);
end;

function TFilePanel.HitParentRetry(const ALocal: TPointF): Boolean;
begin
  Result := (FParentRetryRect.Width > 4) and FParentRetryRect.Contains(ALocal);
end;

procedure TFilePanel.ParentRemoteBits(out AStatus, ARetry: string; out AShowRetry: Boolean);
var
  Tab: TFileTab;
  N: Integer;
begin
  AStatus := '';
  ARetry := 'Дочитать';
  AShowRetry := False;
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[FActiveTabIndex];
  if not IsRemotePath(Tab.Path) then
    Exit;
  N := Tab.LoadSeen;
  if (N <= 0) and Assigned(Tab.Entries) then
    N := Tab.Entries.Count;
  if Tab.Loading then
    AStatus := Format('%d…', [N])
  else if Tab.Partial then
  begin
    AShowRetry := True;
    if (not Assigned(Tab.Entries) or (Tab.Entries.Count = 0)) then
      AStatus := 'нет связи · '
    else
      AStatus := 'оборвалось · ';
  end;
end;

procedure TFilePanel.SetTabOffline(AIndex: Integer; const AMsg: string);
var
  Tab: TFileTab;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  Tab.Offline := True;
  Tab.Loading := False;
  if AMsg <> '' then
    Tab.LoadError := AMsg
  else
    Tab.LoadError := 'Нет связи';
  FTabs[AIndex] := Tab;
  Inc(FThumbGen);
  Inc(FIconGen);
  if AIndex = FActiveTabIndex then
    UpdateLoadChrome;
end;

function TFilePanel.WantRemoteThumbs: Boolean;
begin
  Result := False;
  if FDestroying or IsOffline then
    Exit;
  if (GetTickCount - FScrollTick) < 250 then
    Exit;
  if Assigned(GlobalThumbCache) and (GlobalThumbCache.PendingCount >= 24) then
    Exit;
  Result := True;
end;

procedure TFilePanel.NetPulseTick(Sender: TObject);
var
  Path: string;
  TabIdx: Integer;
  WasOff: Boolean;
begin
  if FDestroying or FNetPulseBusy then
    Exit;
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
    Exit;
  if FTabs[FActiveTabIndex].Loading then
    Exit;
  if not IsRemotePath(FTabs[FActiveTabIndex].Path) then
  begin
    if Assigned(FNetPulseTimer) then
      FNetPulseTimer.Enabled := False;
    Exit;
  end;
  Path := FTabs[FActiveTabIndex].Path;
  TabIdx := FActiveTabIndex;
  WasOff := FTabs[TabIdx].Offline;
  FNetPulseBusy := True;
  var Job := TNetPulseJob.Create;
  Job.Panel := Self;
  Job.Path := Path;
  Job.TabIdx := TabIdx;
  Job.WasOff := WasOff;
  TThread.CreateAnonymousThread(
    procedure
    var
      SR: TSearchRec;
      RC: Integer;
    begin
      RC := System.SysUtils.FindFirst(
        System.IOUtils.TPath.Combine(Job.Path, '*.*'), faAnyFile, SR);
      Job.Ok := RC = 0;
      if Job.Ok then
        System.SysUtils.FindClose(SR);
      TThread.Queue(nil, Job.Apply);
    end).Start;
end;

procedure TNetPulseJob.Apply;
begin
  try
    if Assigned(Panel) then
      Panel.ApplyNetPulse(TabIdx, Path, WasOff, Ok);
  finally
    Free;
  end;
end;

procedure TFilePanel.ApplyNetPulse(ATabIndex: Integer; const APath: string;
  AWasOff, AOk: Boolean);
var
  T: TFileTab;
begin
  FNetPulseBusy := False;
  if FDestroying or (ATabIndex < 0) or (ATabIndex >= FTabs.Count) then
    Exit;
  if not SameDirHistoryPath(FTabs[ATabIndex].Path, APath) then
    Exit;
  if AOk then
  begin
    if AWasOff or FTabs[ATabIndex].Offline then
    begin
      T := FTabs[ATabIndex];
      T.Offline := False;
      T.LoadError := '';
      FTabs[ATabIndex] := T;
      StartDirLoadAt(ATabIndex, APath, '', True);
    end;
  end
  else if not FTabs[ATabIndex].Offline then
    SetTabOffline(ATabIndex, 'Нет связи');
end;

procedure TFilePanel.StartDirLoad(const APath, ASelectPath: string; AKeepSelection: Boolean);
begin
  StartDirLoadAt(FActiveTabIndex, APath, ASelectPath, AKeepSelection);
end;

procedure TFilePanel.StartDirLoadAt(ATabIndex: Integer; const APath, ASelectPath: string;
  AKeepSelection: Boolean);
var
  Path: string;
  KeepSel, HistClear, Branch, Remote: Boolean;
  CapturedPaths: TStringList;
  CapturedFocus: string;
  Tab: TFileTab;
  Gen, TabIdx: Integer;
  Thr: TThread;
begin
  if FDestroying then
    Exit;
  if (ATabIndex < 0) or (ATabIndex >= FTabs.Count) then
    Exit;
  Path := APath;
  Remote := IsRemotePath(Path);
  Tab := FTabs[ATabIndex];
  if Tab.LoadThread <> nil then
  begin
    { Сверять с путём ПОТОКА, не Tab.Path: Navigate уже подменяет Path. }
    if SameDirHistoryPath(Tab.LoadPath, Path) then
    begin
      Tab.RefreshPending := True;
      if ASelectPath <> '' then
        Tab.PendingSelect := ASelectPath;
      Tab.PendingKeepSel := Tab.PendingKeepSel or AKeepSelection;
      FTabs[ATabIndex] := Tab;
      Exit;
    end;
    AbandonTabLoad(ATabIndex);
    Tab := FTabs[ATabIndex];
  end;
  if (ActiveLoadCount >= 3) and (Tab.LoadThread = nil) then
  begin
    Tab.Loading := Remote;
    Tab.LoadQueued := True;
    Tab.LoadError := '';
    FTabs[ATabIndex] := Tab;
    if Remote then
      UpdateLoadChrome;
    Exit;
  end;

  KeepSel := AKeepSelection;
  HistClear := FHistoryClearSel;
  FHistoryClearSel := False;

  Inc(Tab.LoadGen);
  Tab.Loading := Remote;
  Tab.LoadQueued := False;
  Tab.LoadError := '';
  Tab.Partial := False;
  Tab.LoadTick := GetTickCount;
  if Assigned(Tab.Entries) then
    Tab.LoadSeen := Tab.Entries.Count
  else
    Tab.LoadSeen := 0;
  Tab.LoadSeenWatch := Tab.LoadSeen;
  Tab.LoadPath := Path;
  Tab.RefreshPending := False;
  Gen := Tab.LoadGen;
  TabIdx := ATabIndex;
  FTabs[ATabIndex] := Tab;
  if Remote then
    UpdateLoadChrome;

  CapturedPaths := TStringList.Create;
  CapturedPaths.CaseSensitive := False;
  if KeepSel and Assigned(FKeepSelPaths) then
    CapturedPaths.Assign(FKeepSelPaths);
  CapturedFocus := FKeepSelFocus;
  Branch := Tab.BranchView and SameDirHistoryPath(Tab.Path, Path);

  Thr := nil;
  Thr := TDirLoadThread.Create(Path,
    procedure(List: uFileModel.TFileEntryList)
    var
      Applied: Boolean;
      Cur: TFileTab;
      Idx: Integer;
    begin
      Applied := False;
      try
      try
        if FDestroying or (csDestroying in ComponentState) then
        begin
          if Assigned(List) then
            List.Free;
          Exit;
        end;
        Idx := IndexOfLoadThread(Thr);
        if Idx < 0 then
          Idx := IndexOfLoadGen(Gen, Path);
        if Idx < 0 then
        begin
          if Assigned(List) then
            List.Free;
          PumpLoadQueue;
          Exit;
        end;
        TabIdx := Idx;
        Cur := FTabs[TabIdx];
        if (Cur.LoadGen <> Gen) or not SameDirHistoryPath(Cur.Path, Path) then
        begin
          Cur.LoadThread := nil;
          Cur.Loading := False;
          FTabs[TabIdx] := Cur;
          if Assigned(List) then
            List.Free;
          ContinueAfterLoad(TabIdx);
          Exit;
        end;
        if List = nil then
        begin
          Cur.LoadThread := nil;
          Cur.Loading := False;
          if Remote then
          begin
            Cur.Partial := False;
            Cur.Offline := False;
            Cur.LoadError := '';
            if Assigned(Cur.Entries) and (Cur.Entries.Count > 0) then
              SortEntries(Cur.Entries, Cur.SortField, Cur.SortAsc);
          end;
          FTabs[TabIdx] := Cur;
          if Remote and (TabIdx = FActiveTabIndex) then
          begin
            UpdateStatusText;
            RebuildContent;
            UpdateLoadChrome;
          end;
          ContinueAfterLoad(TabIdx);
          Exit;
        end;

        Cur.LoadThread := nil;
        Cur.Loading := False;
        Cur.LoadError := '';
        Cur.LoadPath := '';
        Cur.Offline := False;
        Cur.Partial := False;
        FTabs[TabIdx] := Cur;
        if Remote and Assigned(Cur.Entries) and (Cur.Entries.Count > 0) then
        begin
          AppendRemoteChunk(TabIdx, List, True);
          Applied := True;
        end
        else
          ApplyLoadedList(Path, List, ASelectPath, KeepSel, CapturedPaths, CapturedFocus, False);
        Applied := True;
        if FWatchEnabled then
          WatchTab(TabIdx);

        if HistClear and (FActiveTabIndex = TabIdx) then
        begin
          ClearSelection;
          Cur := FTabs[TabIdx];
          Cur.RefreshPending := False;
          Cur.PendingKeepSel := False;
          FTabs[TabIdx] := Cur;
        end;

        if (FPendingRenamePath <> '') and (ASelectPath <> '') and
           SameText(ExcludeTrailingPathDelimiter(FPendingRenamePath),
                    ExcludeTrailingPathDelimiter(ASelectPath)) and
           (FActiveTabIndex = TabIdx) then
        begin
          FPendingRenamePath := '';
          TThread.ForceQueue(nil,
            procedure
            begin
              if FDestroying or not Assigned(FSelectionManager) then
                Exit;
              EnsureIndexVisible(FSelectionManager.CurrentIndex);
              BeginInlineRename(FSelectionManager.CurrentIndex);
            end);
        end;
        if Remote then
          UpdateLoadChrome;
        ContinueAfterLoad(TabIdx);
      except
        if not Applied and Assigned(List) then
          List.Free;
      end;
      finally
        CapturedPaths.Free;
      end;
    end,
    procedure(AError: string)
    var
      Cur: TFileTab;
      Idx, N: Integer;
    begin
      CapturedPaths.Free;
      if FDestroying then
        Exit;
      Idx := IndexOfLoadThread(Thr);
      if Idx < 0 then
        Idx := IndexOfLoadGen(Gen, Path);
      if Idx < 0 then
      begin
        PumpLoadQueue;
        Exit;
      end;
      TabIdx := Idx;
      Cur := FTabs[TabIdx];
      Cur.LoadThread := nil;
      Cur.Loading := False;
      Cur.LoadPath := '';
      if (Cur.LoadGen = Gen) and SameDirHistoryPath(Cur.Path, Path) and Remote then
      begin
        N := 0;
        if Assigned(Cur.Entries) then
          N := Cur.Entries.Count;
        Cur.Loading := False;
        Cur.LoadError := '';
        if AError = 'Нет доступа' then
        begin
          Cur.LoadError := AError;
          Cur.Partial := True;
          Cur.Offline := False;
        end
        else if N > 0 then
        begin
          Cur.Partial := True;
          Cur.Offline := False;
        end
        else
        begin
          Cur.Partial := True;
          Cur.Offline := True;
          if not Cur.AutoRetryUsed then
          begin
            Cur.AutoRetryUsed := True;
            Cur.Partial := False;
            Cur.Offline := False;
            FTabs[TabIdx] := Cur;
            StartDirLoadAt(TabIdx, Path, '', True);
            if Remote then
              UpdateLoadChrome;
            ContinueAfterLoad(TabIdx);
            Exit;
          end;
        end;
        FTabs[TabIdx] := Cur;
      end
      else if not Remote then
      begin
        Cur.LoadError := '';
        FTabs[TabIdx] := Cur;
      end
      else
        FTabs[TabIdx] := Cur;
      if Assigned(FOnListReady) and not FListReadyFired then
      begin
        FListReadyFired := True;
        FOnListReady(Self);
      end;
      if Remote then
        UpdateLoadChrome;
      ContinueAfterLoad(TabIdx);
    end,
    FShowHiddenFiles, Branch,
    procedure(List: uFileModel.TFileEntryList; ADone: Boolean)
    var
      Idx: Integer;
    begin
      if FDestroying or (csDestroying in ComponentState) then
      begin
        if Assigned(List) then
          List.Free;
        Exit;
      end;
      Idx := IndexOfLoadGen(Gen, Path);
      if Idx < 0 then
      begin
        if Assigned(List) then
          List.Free;
        Exit;
      end;
      AppendRemoteChunk(Idx, List, ADone);
      if Remote and (Idx = FActiveTabIndex) then
        UpdateLoadChrome;
    end,
    procedure(ACount: Integer)
    var
      Idx: Integer;
    begin
      if FDestroying then
        Exit;
      Idx := IndexOfLoadGen(Gen, Path);
      if Idx < 0 then
        Exit;
      NoteRemoteProgress(Idx, ACount);
    end
  );
  Tab := FTabs[ATabIndex];
  Tab.LoadThread := Thr;
  Tab.LoadPath := Path;
  FTabs[ATabIndex] := Tab;
  Thr.Start;
end;

procedure TFilePanel.RebuildContent;
var
  SB: TVertScrollBox;
  PB: TPaintBox;
  Cols: Integer;
  TileH, AvailW: Single;
  TotalCount: Integer;
  Entries: uFileModel.TFileEntryList;
begin
  SB := CurrentScrollBox;
  PB := CurrentPaintBox;
  if (SB = nil) or (PB = nil) then Exit;

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  TotalCount := VisualCount;

  if ViewMode = vmDetails then
  begin
    PB.Height := Max(TotalCount * RowHeight, SB.Height);
  end
  else
  begin
    var SlotW, PadX: Single;
    var TS: Integer;
    AvailW := Max(1, SB.Width - SCROLLBAR_RESERVE);
    GetTileLayout(AvailW, Cols, TS, TileH, SlotW, PadX);
    if TotalCount > 0 then
      PB.Height := Max(Ceil(TotalCount / Cols) * TileH, SB.Height)
    else
      PB.Height := SB.Height;
  end;
  PB.Repaint;

  UpdateChromeStackHeight;
  if Assigned(FHeaderPaint) then
    FHeaderPaint.Repaint;
  UpdateViewButtons;

  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    FTabs[FActiveTabIndex].Scrollbar.UpdateThumb;
end;

procedure TFilePanel.PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
var
  I, StartIdx, EndIdx: Integer;
  RH, TS, Cols: Integer;
  VPos, ViewH, W: Single;
  SB: TVertScrollBox;
  Entry: TFileEntry;
  IsSelected, IsCursor: Boolean;
  R: TRectF;
  HasParent: Boolean;
  ActualIndex: Integer;
  TotalCount: Integer;
  EffectiveRight: Single;
  Entries: uFileModel.TFileEntryList;
  SelectedIndicesRef: TList<Integer>;
begin
  SB := CurrentScrollBox;
  if SB = nil then Exit;

  Entries := GetCurrentEntries;
  SelectedIndicesRef := GetCurrentSelectedIndices;
  if not Assigned(Entries) or not Assigned(SelectedIndicesRef) then Exit;

  VPos := SB.ViewportPosition.Y;
  ViewH := SB.Height;
  W := SB.Width;
  HasParent := HasParentDirectory;
  TotalCount := VisualCount;

  EffectiveRight := W - SCROLLBAR_RESERVE;

  FParentRetryRect := TRectF.Empty;
  Canvas.BeginScene;
  try
    Canvas.Fill.Color := FColors.PanelBackground;
    Canvas.FillRect(TRectF.Create(0, VPos, W, VPos + ViewH), 0, 0, [], AbsoluteOpacity);
    Canvas.Font.Family := FluentFontFamily;
    Canvas.Font.Size := Max(11, Round(FListFontSize * ZoomPercent / 100));
    Canvas.Font.Style := [];

    if ViewMode = vmDetails then
    begin
      RH := RowHeight;
      if RH <= 0 then Exit;
      StartIdx := Max(0, Floor(VPos / RH));
      EndIdx := Min(TotalCount - 1, Ceil((VPos + ViewH) / RH));

      var DetailsIconSize := Round(22 * ZoomPercent / 100);
      if DetailsIconSize > RH - 8 then
        DetailsIconSize := Max(14, RH - 4);
      var NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR: Single;
      GetColumnBounds(W, NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR);
      var LineH := RH * 0.5;
      if FColTwoLine then
        DetailsIconSize := Min(DetailsIconSize, Max(14, Round(LineH - 4)));
      var TextLeft := 14 + DetailsIconSize + 16;
      NameL := Max(NameL, 6 + TextLeft);
      var Fs := DetailsFontSize;
      var MetaFs := Max(10, Round(Fs * 0.9));

      for I := StartIdx to EndIdx do
      begin
        IsSelected := SelectedIndicesRef.Contains(I);
        IsCursor := FActive and (I = FSelectionManager.CurrentIndex);
        R := TRectF.Create(6, I * RH + 1, EffectiveRight + 4, (I + 1) * RH - 2);

        var ItemTextColor: TAlphaColor;
        PaintItemChrome(Canvas, R, 5, IsSelected, IsCursor, I, ItemTextColor);
        Canvas.Fill.Color := ItemTextColor;
        Canvas.Font.Size := Fs;

        var IconTop := R.Top + (RH - DetailsIconSize) / 2;
        if FColTwoLine then
          IconTop := R.Top + (LineH - DetailsIconSize) / 2;

        if HasParent and (I = 0) then
        begin
          var IconRect := TRectF.Create(R.Left + 6, IconTop, R.Left + 6 + DetailsIconSize, IconTop + DetailsIconSize);
          Canvas.Font.Family := 'Segoe Fluent Icons';
          Canvas.FillText(IconRect, '', False, 1, [], TTextAlign.Center, TTextAlign.Center);
          Canvas.Font.Family := FluentFontFamily;
          var NameRight := NameR;
          if FColTwoLine then
            NameRight := EffectiveRight - 10;
          var StL, StR: Single;
          var St, Retry: string;
          var ShowRetry: Boolean;
          ParentRemoteBits(St, Retry, ShowRetry);
          StR := EffectiveRight - 8;
          if (St <> '') or ShowRetry then
          begin
            var StatusTop := R.Top;
            var StatusBot := R.Bottom;
            if FColTwoLine then
            begin
              StatusTop := R.Top + LineH;
              StatusBot := R.Bottom;
            end;
            StL := StR - 140;
            if StL < NameL + 24 then
              StL := NameL + 24;
            NameRight := StL - 6;
            Canvas.Font.Size := MetaFs;
            DrawTrimmedText(Canvas, TRectF.Create(StL, StatusTop, StR, StatusBot),
              St, FColors.SubTextColor, 1, TTextAlign.Leading, MetaFs);
            if ShowRetry then
            begin
              var Tw := Canvas.TextWidth(St);
              var Rx := StL + Tw;
              if Rx < StL then
                Rx := StL;
              DrawTrimmedText(Canvas, TRectF.Create(Rx, StatusTop, StR, StatusBot),
                Retry, FColors.SelectionColor, 1, TTextAlign.Leading, MetaFs);
              FParentRetryRect := TRectF.Create(Rx, StatusTop, StR, StatusBot);
            end;
          end;
          if FColTwoLine then
            DrawTrimmedText(Canvas, TRectF.Create(NameL, R.Top, NameRight, R.Top + LineH),
              '..', ItemTextColor, 1, TTextAlign.Leading, Fs)
          else
            DrawTrimmedText(Canvas, TRectF.Create(NameL, R.Top, NameRight, R.Bottom),
              '..', ItemTextColor, 1, TTextAlign.Leading, Fs);
          Continue;
        end;

        if not VisualToActual(I, ActualIndex) then
          Continue;

        Entry := Entries[ActualIndex];
        var RowOp := EntryRowOpacity(Entry);

        var IconRect := TRectF.Create(R.Left + 14, IconTop, R.Left + 14 + DetailsIconSize, IconTop + DetailsIconSize);
        DrawEntryIcon(Canvas, Entry, IconRect, RowOp);

        if FColTwoLine then
        begin
          DrawTrimmedText(Canvas, TRectF.Create(NameL, R.Top, EffectiveRight - 8, R.Top + LineH),
            Entry.DisplayName, ItemTextColor, RowOp, TTextAlign.Leading, Fs);
          var MetaTop := R.Top + LineH;
          Canvas.Fill.Color := FColors.SubTextColor;
          if TypeR - TypeL > 4 then
            DrawTrimmedText(Canvas, TRectF.Create(TypeL, MetaTop, TypeR, R.Bottom),
              Entry.DisplayType, FColors.SubTextColor, RowOp, TTextAlign.Leading, MetaFs);
          if SizeR - SizeL > 4 then
            DrawTrimmedText(Canvas, TRectF.Create(SizeL, MetaTop, SizeR, R.Bottom),
              Entry.DisplaySize, FColors.SubTextColor, RowOp, TTextAlign.Trailing, MetaFs);
          if (FColDateMode <> dcmHidden) and (DateR - DateL > 4) then
            DrawTrimmedText(Canvas, TRectF.Create(DateL, MetaTop, DateR, R.Bottom),
              FormatRowDate(Entry), FColors.SubTextColor, RowOp, TTextAlign.Trailing, MetaFs);
        end
        else
        begin
          DrawTrimmedText(Canvas, TRectF.Create(NameL, R.Top, NameR, R.Bottom),
            Entry.DisplayName, ItemTextColor, RowOp, TTextAlign.Leading, Fs);
          if IsCursor and not IsSelected then
            Canvas.Fill.Color := FColors.OnAccentTextColor
          else
            Canvas.Fill.Color := FColors.SubTextColor;
          if FColShowType then
            DrawTrimmedText(Canvas, TRectF.Create(TypeL, R.Top, TypeR, R.Bottom),
              Entry.DisplayType, Canvas.Fill.Color, RowOp, TTextAlign.Leading, MetaFs);
          if FColShowSize then
            DrawTrimmedText(Canvas, TRectF.Create(SizeL, R.Top, SizeR, R.Bottom),
              Entry.DisplaySize, Canvas.Fill.Color, RowOp, TTextAlign.Trailing, MetaFs);
          if FColDateMode <> dcmHidden then
            DrawTrimmedText(Canvas, TRectF.Create(DateL, R.Top, DateR, R.Bottom),
              FormatRowDate(Entry), Canvas.Fill.Color, RowOp, TTextAlign.Trailing, MetaFs);
        end;
        Canvas.Font.Size := Fs;
      end;
    end
    else
    begin
      var TileH, SlotW, PadX: Single;
      GetTileLayout(Max(1, EffectiveRight), Cols, TS, TileH, SlotW, PadX);
      if Cols <= 0 then Cols := 1;
      Canvas.Font.Size := 12;

      StartIdx := Max(0, Floor(VPos / TileH) * Cols);
      EndIdx := Min(TotalCount - 1, Ceil((VPos + ViewH) / TileH) * Cols + Cols);

      for I := StartIdx to EndIdx do
      begin
        IsSelected := SelectedIndicesRef.Contains(I);
        IsCursor := FActive and (I = FSelectionManager.CurrentIndex);
        var Col := I mod Cols;
        var RowIdx := I div Cols;
        var X := Col * SlotW + PadX;
        var Y := RowIdx * TileH;

        R := TRectF.Create(X, Y, X + TS, Y + TS + TILE_TEXT_ZONE);

        var ItemTextColor: TAlphaColor;
        PaintItemChrome(Canvas, R, 8, IsSelected, IsCursor, I, ItemTextColor);
        Canvas.Fill.Color := ItemTextColor;

        if HasParent and (I = 0) then
        begin
          var ThumbRect := TRectF.Create(R.Left + 6, R.Top + 6, R.Right - 6, R.Top + TS - 6);
          Canvas.Font.Family := 'Segoe Fluent Icons';
          Canvas.FillText(ThumbRect, '', False, 1, [], TTextAlign.Center, TTextAlign.Center);
          Canvas.Font.Family := 'Segoe UI';
          var Line1Rect := TRectF.Create(R.Left + 6, R.Top + TS, R.Right - 6, R.Bottom - 4);
          var St, Retry: string;
          var ShowRetry: Boolean;
          ParentRemoteBits(St, Retry, ShowRetry);
          if ShowRetry then
          begin
            Canvas.FillText(Line1Rect, '..  ' + St + Retry, False, 1, [],
              TTextAlign.Center, TTextAlign.Center);
            FParentRetryRect := Line1Rect;
          end
          else if St <> '' then
            Canvas.FillText(Line1Rect, '..  ' + St, False, 1, [],
              TTextAlign.Center, TTextAlign.Center)
          else
            Canvas.FillText(Line1Rect, '..', False, 1, [], TTextAlign.Center, TTextAlign.Center);
          Continue;
        end;

        if not VisualToActual(I, ActualIndex) then
          Continue;

        Entry := Entries[ActualIndex];
        var RowOp := EntryRowOpacity(Entry);

        var ThumbRect := TRectF.Create(R.Left + 6, R.Top + 6, R.Right - 6, R.Top + TS - 6);
        var HasDrawn := False;
        var Thumb: FMX.Graphics.TBitmap;

        if Assigned(GlobalThumbCache) and
           GlobalThumbCache.TryGet(Entry.FullPath, Thumb) and Assigned(Thumb) then
        begin
          var TargetW := ThumbRect.Width;
          var TargetH := ThumbRect.Height;
          var ImgW := Thumb.Width;
          var ImgH := Thumb.Height;

          if (ImgW > 0) and (ImgH > 0) then
          begin
            var Scale := Min(TargetW / ImgW, TargetH / ImgH);
            var DrawW := ImgW * Scale;
            var DrawH := ImgH * Scale;
            var DrawX := ThumbRect.Left + (TargetW - DrawW) / 2;
            var DrawY := ThumbRect.Top + (TargetH - DrawH) / 2;
            var FittedRect := TRectF.Create(DrawX, DrawY, DrawX + DrawW, DrawY + DrawH);

            Canvas.DrawBitmap(Thumb, Thumb.Bounds, FittedRect, RowOp, False);
          end
          else
            Canvas.DrawBitmap(Thumb, Thumb.Bounds, ThumbRect, RowOp, False);

          HasDrawn := True;
        end;
        if (TS >= 64) and Assigned(GlobalThumbCache) and
           GlobalThumbCache.WorkersEnabled and
           IsThumbCandidate(Entry.FullPath, Entry.IsDirectory, Entry.Name) and
           (not IsRemotePath(Entry.FullPath) or WantRemoteThumbs) then
        begin
          GlobalThumbCache.RequestAsync(Entry.FullPath, Round(TS), nil, Entry.Name);
          if Assigned(FThumbTimer) and not FDestroying then
            FThumbTimer.Enabled := True;
        end;

        if not HasDrawn then
        begin
          var IconSide := Min(ThumbRect.Width, ThumbRect.Height) * 0.72;
          if IconSide < 32 then
            IconSide := 32;
          var IconDrawRect := TRectF.Create(
            ThumbRect.Left + (ThumbRect.Width - IconSide) / 2,
            ThumbRect.Top + (ThumbRect.Height - IconSide) / 2,
            ThumbRect.Left + (ThumbRect.Width - IconSide) / 2 + IconSide,
            ThumbRect.Top + (ThumbRect.Height - IconSide) / 2 + IconSide
          );
          DrawEntryIcon(Canvas, Entry, IconDrawRect, RowOp);
        end;

        var ExtStr: string;
        if Entry.IsDirectory then
          ExtStr := ''
        else
          ExtStr := Entry.DisplayType;

        var ExtWidth := Canvas.TextWidth(ExtStr);
        var NameRect := TRectF.Create(R.Left + 6, R.Top + TS, R.Right - 6 - ExtWidth - 10, R.Top + TS + 20);
        Canvas.FillText(NameRect, Entry.DisplayName, False, RowOp, [], TTextAlign.Leading, TTextAlign.Center);

        var ExtRect := TRectF.Create(R.Right - 6 - ExtWidth, R.Top + TS, R.Right - 6, R.Top + TS + 20);
        Canvas.FillText(ExtRect, ExtStr, False, RowOp, [], TTextAlign.Trailing, TTextAlign.Center);

        if IsCursor and not IsSelected then
          Canvas.Fill.Color := FColors.OnAccentTextColor
        else
          Canvas.Fill.Color := FColors.SubTextColor;
        var SizeStr: string;
        if Entry.DisplaySize <> '' then
          SizeStr := Entry.DisplaySize
        else if Entry.IsDirectory then
          SizeStr := 'Папка'
        else
          SizeStr := '';

        var ExtraStr := '';
        if (not Entry.IsDirectory) and Assigned(GlobalMetaCache) and
           not IsRemotePath(Entry.FullPath) then
        begin
          if not GlobalMetaCache.TryGet(Entry.FullPath, ExtraStr) then
          begin
            GlobalMetaCache.RequestAsync(Entry.FullPath);
            if Assigned(FThumbTimer) and not FDestroying then
              FThumbTimer.Enabled := True;
          end;
        end;
        var ExtraW: Single := 0;
        if ExtraStr <> '' then
          ExtraW := Canvas.TextWidth(ExtraStr) + 8;
        var Line2Rect := TRectF.Create(R.Left + 6, R.Top + TS + 20, R.Right - 6 - ExtraW, R.Bottom - 4);
        Canvas.FillText(Line2Rect, SizeStr, False, RowOp, [], TTextAlign.Leading, TTextAlign.Center);
        if ExtraStr <> '' then
        begin
          var ExtraRect := TRectF.Create(R.Right - 6 - ExtraW + 4, R.Top + TS + 20, R.Right - 6, R.Bottom - 4);
          Canvas.FillText(ExtraRect, ExtraStr, False, RowOp, [], TTextAlign.Trailing, TTextAlign.Center);
        end;
      end;
    end;
    if Assigned(FThumbTimer) and not FDestroying and Assigned(GlobalIconCache) and
       GlobalIconCache.HasWork then
      FThumbTimer.Enabled := True;
  finally
    Canvas.EndScene;
  end;
end;


procedure TFilePanel.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  ClickedIdx: Integer;
  Entries: uFileModel.TFileEntryList;
  TotalCount: Integer;
begin
  var SB := CurrentScrollBox;
  if SB = nil then Exit;

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  CancelPathEdit;
  if Assigned(FOnActivate) then
    FOnActivate(Self);
  if CanFocus then
    SetFocus;

  ClickedIdx := GetIndexAt(X, Y);
  TotalCount := VisualCount;

  if (Button = TMouseButton.mbLeft) and HasParentDirectory and (ClickedIdx = 0) and
     HitParentRetry(TPointF.Create(X, Y)) then
  begin
    ResumeRemoteRead;
    Exit;
  end;

  if (ClickedIdx >= 0) and (ClickedIdx < TotalCount) then
  begin
    FSuppressSelectUntilUp := False;
    FPendingRightSelect := False;
    FSelectionManager.CurrentIndex := ClickedIdx;
    NotifyCursorChange;

    if Button = TMouseButton.mbLeft then
    begin
      FSelectionManager.MouseDown(ClickedIdx, Button, Shift);
      if not (ssCtrl in Shift) and not (ssShift in Shift) then
      begin
        FDragReady := True;
        FDragStart := TPointF.Create(X, Y);
        FDragPaths := CollectDragPaths;
      end
      else
        FDragReady := False;
    end
    else if Button = TMouseButton.mbRight then
    begin
      { Длинный ПКМ не трогает выделение. Короткий клик — в MouseUp,
        протяжка кистью — после сдвига > 8 px. }
      FDragReady := False;
      FPendingRightSelect := True;
      FSelectionManager.CancelDrag;
      CapturePaintBoxMouse;
      InvalidateView;
    end
    else
      FDragReady := False;

    FLongClickArmed := True;
    FLongClickBtn := Button;
    FLongClickIdx := ClickedIdx;
    FLongClickPt := TPointF.Create(X, Y);
    FLongClickTimer.Enabled := False;
    FLongClickTimer.Enabled := True;
  end
  else
    CancelLongClick;
end;

procedure TFilePanel.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  ClickedIdx: Integer;
  Entries: uFileModel.TFileEntryList;
begin
  if GFileDrag.Active then
  begin
    FileDragTrack;
    Exit;
  end;
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  if FPendingRightSelect or FSelectionManager.IsDragging then
  begin
    if not RightButtonHeld(Shift) then
    begin
      EndRightPaint;
    end
    else
    begin
      if FLongClickArmed and
         ((Abs(X - FLongClickPt.X) > 8) or (Abs(Y - FLongClickPt.Y) > 8)) then
      begin
        FPendingRightSelect := False;
        FSelectionManager.BeginRightPaint(FLongClickIdx);
        CancelLongClick;
        if Assigned(FSelectScrollTimer) then
          FSelectScrollTimer.Enabled := True;
      end;
      if FSelectionManager.IsDragging then
        ApplyRightPaintMouse(X, Y);
    end;
  end
  else if FLongClickArmed and
     ((Abs(X - FLongClickPt.X) > 8) or (Abs(Y - FLongClickPt.Y) > 8)) then
    CancelLongClick;

  if FDragReady and (ssLeft in Shift) then
  begin
    if (Abs(X - FDragStart.X) > 8) or (Abs(Y - FDragStart.Y) > 8) then
    begin
      FDragReady := False;
      CancelLongClick;
      StartInternalDrag;
      Exit;
    end;
  end;
  if FSuppressSelectUntilUp then
  begin
    if not (ssLeft in Shift) and not (ssRight in Shift) then
      FSuppressSelectUntilUp := False;
  end;
  ClickedIdx := GetIndexAt(X, Y);
  if FHoverIndex <> ClickedIdx then
  begin
    FHoverIndex := ClickedIdx;
    InvalidateView;
    UpdateStatusText;
  end
  else if (ssLeft in Shift) or (ssRight in Shift) then
    UpdateStatusText;
end;

procedure TFilePanel.PaintBoxMouseLeave(Sender: TObject);
begin
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    InvalidateView;
  end;
end;


procedure TFilePanel.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if GFileDrag.Active then
  begin
    FileDragEnd(Button, Shift);
    Exit;
  end;
  if FPendingRightSelect and (Button = TMouseButton.mbRight) and FLongClickArmed then
    FSelectionManager.MouseDown(FLongClickIdx, TMouseButton.mbRight, Shift);
  FSuppressSelectUntilUp := False;
  CancelLongClick;
  FDragReady := False;
  FSelectionManager.MouseUp(Button);
  EndRightPaint;
  UpdateStatusText;
end;

procedure TFilePanel.CancelLongClick;
begin
  FLongClickArmed := False;
  if Assigned(FLongClickTimer) then
    FLongClickTimer.Enabled := False;
end;

function TFilePanel.RightButtonHeld(const AShift: TShiftState): Boolean;
begin
  Result := ssRight in AShift;
{$IFDEF MSWINDOWS}
  if not Result then
    Result := (GetKeyState(VK_RBUTTON) and $8000) <> 0;
{$ENDIF}
end;

procedure TFilePanel.CapturePaintBoxMouse;
var
  PB: TPaintBox;
begin
  PB := CurrentPaintBox;
  if (PB <> nil) and Assigned(Root) then
    Root.Captured := PB;
end;

procedure TFilePanel.ReleasePaintBoxCapture;
var
  PB: TPaintBox;
begin
  PB := CurrentPaintBox;
  if not Assigned(Root) or (PB = nil) then
    Exit;
  if Assigned(Root.Captured) and (Root.Captured.GetObject = PB) then
    Root.Captured := nil;
end;

procedure TFilePanel.EndRightPaint;
begin
  FPendingRightSelect := False;
  FSelectionManager.CancelDrag;
  if Assigned(FSelectScrollTimer) then
    FSelectScrollTimer.Enabled := False;
  ReleasePaintBoxCapture;
end;

function TFilePanel.GetSelectIndexAt(X, Y: Single): Integer;
var
  RH, TS, Cols, TotalCount: Integer;
  TileH, SlotW, PadX: Single;
  SB: TVertScrollBox;
  Entries: uFileModel.TFileEntryList;
  Col, RowIdx: Integer;
begin
  Result := GetIndexAt(X, Y);
  if Result >= 0 then
    Exit;
  SB := CurrentScrollBox;
  Entries := GetCurrentEntries;
  if (SB = nil) or not Assigned(Entries) then
    Exit;
  TotalCount := VisualCount;
  if TotalCount <= 0 then
    Exit;

  if ViewMode = vmDetails then
  begin
    RH := RowHeight;
    if RH <= 0 then
      Exit;
    if Y < 0 then
      Result := 0
    else
      Result := TotalCount - 1;
  end
  else
  begin
    GetTileLayout(Max(1, SB.Width - SCROLLBAR_RESERVE), Cols, TS, TileH, SlotW, PadX);
    if (Cols <= 0) or (TileH <= 0) then
      Exit;
    Col := Floor(X / SlotW);
    if Col < 0 then
      Col := 0
    else if Col >= Cols then
      Col := Cols - 1;
    RowIdx := Floor(Y / TileH);
    if RowIdx < 0 then
      Result := 0
    else
    begin
      Result := RowIdx * Cols + Col;
      if Result >= TotalCount then
        Result := TotalCount - 1;
    end;
  end;
end;

procedure TFilePanel.ApplyRightPaintMouse(X, Y: Single);
var
  SB: TVertScrollBox;
  ViewY, ViewH, Zone, Dist, Delta, ItemH, VPos, MaxVPos: Single;
  TS, Cols: Integer;
  TileH, SlotW, PadX: Single;
  Idx, PrevIdx: Integer;
begin
  SB := CurrentScrollBox;
  if SB = nil then
    Exit;

  if ViewMode = vmDetails then
    ItemH := RowHeight
  else
  begin
    GetTileLayout(Max(1, SB.Width - SCROLLBAR_RESERVE), Cols, TS, TileH, SlotW, PadX);
    ItemH := TileH;
  end;
  if ItemH <= 0 then
    ItemH := 22;

  ViewH := SB.Height;
  ViewY := Y - SB.ViewportPosition.Y;
  Zone := Max(22.0, ItemH);
  Delta := 0;
  if ViewY < Zone then
  begin
    Dist := Zone - ViewY;
    Delta := -Min(ItemH * 3, ItemH * Max(0.35, Dist / Zone));
  end
  else if ViewY > ViewH - Zone then
  begin
    Dist := ViewY - (ViewH - Zone);
    Delta := Min(ItemH * 3, ItemH * Max(0.35, Dist / Zone));
  end;

  if Delta <> 0 then
  begin
    VPos := SB.ViewportPosition.Y + Delta;
    MaxVPos := Max(0.0, SB.ContentBounds.Height - ViewH);
    VPos := Max(0.0, Min(VPos, MaxVPos));
    if not SameValue(VPos, SB.ViewportPosition.Y) then
    begin
      Y := Y + (VPos - SB.ViewportPosition.Y);
      SB.ViewportPosition := TPointF.Create(SB.ViewportPosition.X, VPos);
    end;
  end;

  Idx := GetSelectIndexAt(X, Y);
  if Idx < 0 then
    Exit;
  PrevIdx := FSelectionManager.CurrentIndex;
  FSelectionManager.MouseMove(Idx, [ssRight]);
  if FSelectionManager.CurrentIndex <> PrevIdx then
    NotifyCursorChange;
end;

procedure TFilePanel.SelectScrollTimerTick(Sender: TObject);
var
  PB: TPaintBox;
  Local: TPointF;
  ScreenPt: TPointF;
begin
  if FDestroying then
  begin
    if Assigned(FSelectScrollTimer) then
      FSelectScrollTimer.Enabled := False;
    Exit;
  end;
  if not FSelectionManager.IsDragging then
  begin
    if Assigned(FSelectScrollTimer) then
      FSelectScrollTimer.Enabled := False;
    Exit;
  end;
  if not RightButtonHeld([]) then
  begin
    EndRightPaint;
    UpdateStatusText;
    Exit;
  end;
  PB := CurrentPaintBox;
  if PB = nil then
    Exit;
  ScreenPt := Screen.MousePos;
  Local := PB.ScreenToLocal(ScreenPt);
  ApplyRightPaintMouse(Local.X, Local.Y);
end;

procedure TFilePanel.LongClickTimerTick(Sender: TObject);
begin
  FLongClickTimer.Enabled := False;
  if not FLongClickArmed then
    Exit;
  FLongClickArmed := False;
  FDragReady := False;

  {$IFDEF MSWINDOWS}
  if FLongClickBtn = TMouseButton.mbLeft then
  begin
    if (GetKeyState(VK_LBUTTON) and $8000) = 0 then
      Exit;
    BeginInlineRename(FLongClickIdx);
  end
  else if FLongClickBtn = TMouseButton.mbRight then
  begin
    if (GetKeyState(VK_RBUTTON) and $8000) = 0 then
      Exit;
    FSuppressSelectUntilUp := True;
    EndRightPaint;
    ShowShellMenuForIndex(FLongClickIdx);
    FSelectionManager.CancelDrag;
    if Assigned(Root) then
      Root.Captured := nil;
    ReleaseCapture;
  end;
  {$ELSE}
  if FLongClickBtn = TMouseButton.mbLeft then
    BeginInlineRename(FLongClickIdx);
  {$ENDIF}
end;

function TFilePanel.VisualToEntry(AVisualIdx: Integer; out AEntry: TFileEntry): Boolean;
var
  Entries: uFileModel.TFileEntryList;
  Actual: Integer;
begin
  Result := False;
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then
    Exit;
  if not VisualToActual(AVisualIdx, Actual) then
    Exit;
  AEntry := Entries[Actual];
  Result := AEntry.FullPath <> '';
end;

function TFilePanel.GetInlineRenameRect(AVisualIdx: Integer; out ARect: TRectF): Boolean;
var
  PB: TPaintBox;
  SB: TVertScrollBox;
  NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR: Single;
  RH, TS, Cols, Col, Row: Integer;
  TileH, SlotW, PadX: Single;
  TL, BR: TPointF;
begin
  Result := False;
  PB := CurrentPaintBox;
  SB := CurrentScrollBox;
  if (PB = nil) or (SB = nil) then
    Exit;

  if ViewMode = vmDetails then
  begin
    RH := RowHeight;
    GetColumnBounds(SB.Width, NameL, NameR, TypeL, TypeR, SizeL, SizeR, DateL, DateR);
    if FColTwoLine then
      ARect := TRectF.Create(NameL, AVisualIdx * RH + 2, SB.Width - SCROLLBAR_RESERVE - 8,
        AVisualIdx * RH + RH * 0.5)
    else if RH > 20 then
      ARect := TRectF.Create(NameL, AVisualIdx * RH + 3, NameR, (AVisualIdx + 1) * RH - 4)
    else
      ARect := TRectF.Create(NameL, AVisualIdx * RH + 1, NameR, (AVisualIdx + 1) * RH - 1);
  end
  else
  begin
    GetTileLayout(Max(1, SB.Width - SCROLLBAR_RESERVE), Cols, TS, TileH, SlotW, PadX);
    Col := AVisualIdx mod Cols;
    Row := AVisualIdx div Cols;
    ARect := TRectF.Create(Col * SlotW + PadX + 4, Row * TileH + TS + 6,
      Col * SlotW + PadX + TS - 4, Row * TileH + TS + TILE_TEXT_ZONE - 4);
  end;

  TL := AbsoluteToLocal(PB.LocalToAbsolute(ARect.TopLeft));
  BR := AbsoluteToLocal(PB.LocalToAbsolute(ARect.BottomRight));
  ARect := TRectF.Create(TL, BR);
  Result := (ARect.Width > 20) and (ARect.Height > 8);
end;

procedure TFilePanel.BeginInlineRename(AVisualIdx: Integer);
var
  Entry: TFileEntry;
  R: TRectF;
  BaseLen: Integer;
begin
  CancelLongClick;
  if not VisualToEntry(AVisualIdx, Entry) then
    Exit;
  if not GetInlineRenameRect(AVisualIdx, R) then
    Exit;
  EndPathEdit(False);

  if FRenameEdit = nil then
  begin
    FRenameEdit := TFluentEdit.Create(Self);
    FRenameEdit.Parent := Self;
    FRenameEdit.Align := TAlignLayout.None;
    FRenameEdit.OnKeyDown := RenameEditKeyDown;
    FRenameEdit.OnSubmit := RenameEditSubmit;
    FRenameEdit.OnExit := RenameEditExit;
  end;
  FRenameEdit.FillMode := fefSolid;
  FRenameEdit.ApplyTheme(FColors);
  if ViewMode = vmDetails then
    FRenameEdit.FontSize := Max(11, Round(FListFontSize * ZoomPercent / 100))
  else
    FRenameEdit.FontSize := 12;
  FRenameEdit.SetBounds(R.Left, R.Top, R.Width, R.Height);
  FRenameEdit.Text := Entry.Name;
  FRenamePath := Entry.FullPath;
  FRenameEdit.Visible := True;
  FRenameEdit.BringToFront;
  FRenameEdit.SetFocus;
  if (not Entry.IsDirectory) and (Entry.Extension <> '') then
  begin
    BaseLen := Length(Entry.Name) - Length(Entry.Extension);
    if BaseLen < 0 then
      BaseLen := Length(Entry.Name);
    FRenameEdit.SelectRange(0, BaseLen);
  end
  else
    FRenameEdit.SelectAll;
end;

procedure TFilePanel.EndInlineRename(AApply: Boolean);
var
  NewName, NewPath: string;
begin
  if FRenameApplying or not Assigned(FRenameEdit) or not FRenameEdit.Visible then
    Exit;
  FRenameApplying := True;
  try
    NewName := Trim(FRenameEdit.Text);
    FRenameEdit.Visible := False;
    if AApply and (FRenamePath <> '') and (NewName <> '') and
       not SameText(NewName, ExtractFileName(FRenamePath)) then
    begin
      if RenamePath(FRenamePath, NewName, NewPath) then
        Refresh(NewPath);
    end
    else if AApply and Assigned(FSelectionManager) then
      FSelectionManager.DeselectAll;
    FRenamePath := '';
  finally
    FRenameApplying := False;
  end;
end;

procedure TFilePanel.RenameEditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    EndInlineRename(True);
    Key := 0;
  end
  else if Key = vkEscape then
  begin
    EndInlineRename(False);
    Key := 0;
  end;
end;

procedure TFilePanel.RenameEditSubmit(Sender: TObject);
begin
  EndInlineRename(True);
end;

procedure TFilePanel.RenameEditExit(Sender: TObject);
begin
  EndInlineRename(False);
end;

procedure TFilePanel.ShowShellMenuForIndex(AVisualIdx: Integer);
{$IFDEF MSWINDOWS}
var
  Entry: TFileEntry;
  Files: TArray<string>;
  Pt: TPoint;
  Wnd: HWND;
  Sel: TArray<TFileEntry>;
  I: Integer;
  ClickedSel: Boolean;
  Verb: string;
begin
  if not VisualToEntry(AVisualIdx, Entry) then
    Exit;
  ClickedSel := False;
  Sel := SelectedEntries;
  for I := 0 to High(Sel) do
    if SameText(Sel[I].FullPath, Entry.FullPath) then
    begin
      ClickedSel := True;
      Break;
    end;
  if ClickedSel and (Length(Sel) > 0) then
  begin
    SetLength(Files, Length(Sel));
    for I := 0 to High(Sel) do
      Files[I] := Sel[I].FullPath;
  end
  else
  begin
    SetLength(Files, 1);
    Files[0] := Entry.FullPath;
  end;
  GetCursorPos(Pt);
  Wnd := 0;
  if Root is TCommonCustomForm then
    Wnd := FormToHWND(TCommonCustomForm(Root));
  if ShowExplorerContextMenu(Wnd, Files, Pt.X, Pt.Y, FColors.IsDark, Verb, True) then
  begin
    if SameText(Verb, 'rename') then
      BeginInlineRename(AVisualIdx)
    else if SameText(Verb, 'paste') then
      HandlePaste;
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure TFilePanel.PaintBoxDblClick(Sender: TObject);
var
  ActualIndex: Integer;
  Sel: TFileEntry;
  Entries: uFileModel.TFileEntryList;
  FocusIdx: Integer;
begin
  if IsOffline then
  begin
    ShowNotice('Нет связи');
    Exit;
  end;
  Entries := GetCurrentEntries;
  if not Assigned(Entries) or not Assigned(FSelectionManager) then Exit;

  // Берем индекс текущего элемента под фокусом (курсором) из менеджера выделения/фокуса
  // (замените .CurrentIndex на название вашего свойства, если оно называется иначе, например .FocusedIndex)
  FocusIdx := FSelectionManager.CurrentIndex;

  if HasParentDirectory and (FocusIdx = 0) then
  begin
    if IsSearchView then
      GoBack
    else if IsBranchView then
      ToggleBranchView
    else
      NavigateToParent;
    Exit;
  end;
  if not VisualToActual(FocusIdx, ActualIndex) then
    Exit;

  if (ActualIndex >= 0) and (ActualIndex < Entries.Count) then
  begin
    Sel := Entries[ActualIndex];
    if Sel.IsDirectory or IsArchiveFileName(Sel.Name) or IsArchiveFileName(Sel.FullPath) then
      Navigate(Sel.FullPath)
    else
    begin
      var LocalFile: string;
      if IsRemotePath(Sel.FullPath) then
        OpenFileWithDefaultApp(Sel.FullPath)
      else if MaterializeFile(Sel.FullPath, LocalFile) then
        OpenFileWithDefaultApp(LocalFile)
      else
        OpenFileWithDefaultApp(Sel.FullPath);
    end;
  end;
end;


procedure TFilePanel.PanelMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  SB: TVertScrollBox;
begin
  SB := CurrentScrollBox;
  if SB = nil then Exit;

  if ssCtrl in Shift then
  begin
    var CurZoom := ZoomPercent;
    var ZMin := MIN_ZOOM;
    var ZMax := MAX_ZOOM;
    if ViewMode = vmTiles then
    begin
      ZMin := MIN_TILE_ZOOM;
      ZMax := MAX_TILE_ZOOM;
    end;
    if WheelDelta > 0 then
      CurZoom := Min(ZMax, CurZoom + ZOOM_STEP)
    else
      CurZoom := Max(ZMin, CurZoom - ZOOM_STEP);
    ZoomPercent := CurZoom;
    KeepFocusVisible;
    Handled := True;
  end
  else
  begin
    SB.ViewportPosition := TPointF.Create(
      SB.ViewportPosition.X,
      Max(0.0, Min(SB.ViewportPosition.Y - WheelDelta, SB.ContentBounds.Height - SB.Height))
    );
    Handled := True;
  end;
end;

procedure TFilePanel.SetViewMode(AMode: TPanelViewMode);
begin
  ViewMode := AMode;
end;

procedure TFilePanel.SetShowNetwork(AShow: Boolean);
begin
  if Assigned(FDriveBar) then
    FDriveBar.ShowNetwork := AShow;
end;

procedure TFilePanel.SetShowHiddenFiles(AShow: Boolean);
begin
  if FShowHiddenFiles = AShow then
    Exit;
  FShowHiddenFiles := AShow;
  if not FDestroying then
    Refresh('', True);
end;

procedure TFilePanel.ApplyUiSettings(const ASettings: TAppSettings);
begin
  FListFontSize := ASettings.ListFontSize;
  if FListFontSize < 10 then
    FListFontSize := 13;
  InvalidateColLayout;
  if Assigned(FDriveBar) then
    FDriveBar.ShowNetwork := ASettings.ShowNetworkButton;
  SetShowDriveBar(ASettings.ShowDriveBar);
  if Assigned(FCrumbsBox) then
    FCrumbsBox.Visible := not (Assigned(FPathEdit) and FPathEdit.Visible);
  if Assigned(FFooterPanel) then
  begin
    FFooterPanel.Visible := ASettings.ShowStatusBar;
    if ASettings.ShowStatusBar then
      FFooterPanel.Height := 32
    else
      FFooterPanel.Height := 0;
  end;
  if Assigned(FBtnDetails) then
    FBtnDetails.Visible := ASettings.ShowQuickAccess;
  if Assigned(FBtnTiles) then
    FBtnTiles.Visible := ASettings.ShowQuickAccess;
  if Assigned(FBtnQuickView) then
    FBtnQuickView.Visible := ASettings.ShowQuickAccess;
  if Assigned(FTabsBar) then
    FTabsBar.SetTabChrome(ASettings.ShowTabIcons, ASettings.EqualTabWidth);
  UpdateChromeStackHeight;
  LockChromeOrder;
  InvalidateView;
  if FShowHiddenFiles <> ASettings.ShowHiddenFiles then
    SetShowHiddenFiles(ASettings.ShowHiddenFiles);
end;

procedure TFilePanel.ApplyTheme(const AColors: TThemeColors);
var
  PB: TPaintBox;
  I: Integer;
begin
  FColors := AColors;
  InvalidateColLayout;

  ApplyCardChrome;

  if Assigned(FFooterPanel) then
    FFooterPanel.Fill.Color := AColors.HeaderBackground;
  if Assigned(FStatusText) then
    FStatusText.TextSettings.FontColor := AColors.SubTextColor;

  if Assigned(FFooterPanel) then
    for I := 0 to FFooterPanel.ControlsCount - 1 do
      if (FFooterPanel.Controls[I] is TRectangle) and
         (TRectangle(FFooterPanel.Controls[I]).Tag = 1) then
        TRectangle(FFooterPanel.Controls[I]).Fill.Color := AColors.DividerColor;

  if Assigned(FPathAndHeader) then
  begin
    FPathAndHeader.Fill.Color := AColors.HeaderBackground;
    FPathAndHeader.Stroke.Kind := TBrushKind.None;
  end;
  if Assigned(FTopBar) then
  begin
    FTopBar.Fill.Color := TAlphaColors.Null;
    FTopBar.Stroke.Kind := TBrushKind.None;
  end;

  if Assigned(FBtnBack) then
    FBtnBack.ApplyTheme(AColors);
  if Assigned(FBtnForward) then
    FBtnForward.ApplyTheme(AColors);
  if Assigned(FRetryBtn) then
    FRetryBtn.ApplyTheme(AColors);
  UpdateHistoryButtons;

  if Assigned(FHeaderBar) then
    FHeaderBar.Fill.Color := AColors.HeaderBackground;
  if Assigned(FHeaderPaint) then
    FHeaderPaint.Repaint;

  ApplyPathEditTheme;
  RebuildBreadcrumbs;

  if Assigned(FTabsBar) then
    FTabsBar.ApplyTheme(AColors);
  if Assigned(FDriveBar) then
  begin
    FDriveBar.ApplyTheme(AColors);
    FDriveBar.SetActivePath(GetCurrentPathImpl);
  end;

  if Assigned(FBtnDetails) and (FBtnDetails.ChildrenCount > 0) then
    TText(FBtnDetails.Children[0]).TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnTiles) and (FBtnTiles.ChildrenCount > 0) then
    TText(FBtnTiles.Children[0]).TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnQuickView) and (FBtnQuickView.ChildrenCount > 0) then
    TText(FBtnQuickView.Children[0]).TextSettings.FontColor := AColors.TextColor;
  if Assigned(FPreview) then
    FPreview.ApplyTheme(AColors);

  UpdateViewButtons;

  for var Tab in FTabs do
  begin
    if Assigned(Tab.BgRect) then
      Tab.BgRect.Fill.Color := AColors.PanelBackground;
    if Assigned(Tab.Scrollbar) then
      Tab.Scrollbar.ApplyTheme(AColors);
  end;

  PB := CurrentPaintBox;
  if Assigned(PB) then
    PB.Repaint;
end;

procedure TFilePanel.SetActive(AIsActive: Boolean);
var
  PB: TPaintBox;
begin
  FActive := AIsActive;
  ApplyCardChrome;
  RebuildBreadcrumbs;

  PB := CurrentPaintBox;
  if Assigned(PB) then
    PB.Repaint;
end;

function TFilePanel.HasSelection: Boolean;
begin
  Result := GetItemCount > 0;
end;

function TFilePanel.HasMultiSelection: Boolean;
var
  Sel: TList<Integer>;
begin
  Sel := GetCurrentSelectedIndices;
  Result := Assigned(Sel) and (Sel.Count > 0);
end;

procedure TFilePanel.StartInlineRename;
begin
  if Assigned(FSelectionManager) then
    BeginInlineRename(FSelectionManager.CurrentIndex);
end;

function TFilePanel.IsInlineRenaming: Boolean;
begin
  Result := Assigned(FRenameEdit) and FRenameEdit.Visible;
end;

function TFilePanel.FocusPathAfterRemove(const ARemoved: TArray<string>): string;
var
  Entries: uFileModel.TFileEntryList;
  I, Start: Integer;

  function IsRemoved(const APath: string): Boolean;
  var
    S: string;
  begin
    Result := False;
    for S in ARemoved do
      if SameText(ExcludeTrailingPathDelimiter(S),
                  ExcludeTrailingPathDelimiter(APath)) then
        Exit(True);
  end;

begin
  Result := '';
  Entries := GetCurrentEntries;
  if not Assigned(Entries) or (Entries.Count = 0) then
    Exit;

  Start := 0;
  if Assigned(FSelectionManager) then
    if not VisualToActual(FSelectionManager.CurrentIndex, Start) then
      Start := 0;
  if Start < 0 then
    Start := 0;
  if Start >= Entries.Count then
    Start := Entries.Count - 1;

  for I := Start to Entries.Count - 1 do
    if not IsRemoved(Entries[I].FullPath) then
      Exit(Entries[I].FullPath);

  for I := Start - 1 downto 0 do
    if not IsRemoved(Entries[I].FullPath) then
      Exit(Entries[I].FullPath);
end;

procedure TFilePanel.CreateNewFolderInPlace;
var
  Created: string;
begin
  Created := CreateNewFolder(GetCurrentPathImpl, 'Новая папка');
  if Created = '' then
    Exit;
  FPendingRenamePath := Created;
  Refresh(Created);
end;



function TFilePanel.SelectedEntry: TFileEntry;
var
  Entries: TFileEntryList;
  CurrentIdx: Integer;
begin
  Entries := GetCurrentEntries;
  if Assigned(Entries) and Assigned(FSelectionManager) and
     VisualToActual(FSelectionManager.CurrentIndex, CurrentIdx) then
    Exit(Entries[CurrentIdx]);

  // Так как TFileEntry — это record, возвращаем пустой дефолтный экземпляр вместо nil
  Result := Default(TFileEntry);
end;


function TFilePanel.SelectedEntries: TArray<TFileEntry>;
var
  SelectedIndices: TList<Integer>;
  Entries: TFileEntryList;
  I: Integer;
  LList: TList<TFileEntry>;
  Idx, ActualIndex: Integer;
begin
  LList := TList<TFileEntry>.Create;
  try
    SelectedIndices := GetCurrentSelectedIndices; // Индексы мультивыделения
    Entries := GetCurrentEntries;                 // Список всех записей в панели

    if Assigned(SelectedIndices) and (SelectedIndices.Count > 0) then
    begin
      // 1. Если есть мультивыделение — берем все отмеченные файлы
      for I := 0 to SelectedIndices.Count - 1 do
      begin
        Idx := SelectedIndices[I];
        if not VisualToActual(Idx, ActualIndex) then
          Continue;
        if Assigned(Entries) then
          LList.Add(Entries[ActualIndex]);
      end;
    end
    else
    begin
      if Assigned(FSelectionManager) then
      begin
        Idx := FSelectionManager.CurrentIndex;
        if VisualToActual(Idx, ActualIndex) and Assigned(Entries) then
          LList.Add(Entries[ActualIndex]);
      end;
    end;

    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

procedure TFilePanel.MoveSelection(Delta: Integer; Shift: TShiftState);
var
  TotalCount, NewIdx: Integer;
  SB: TVertScrollBox;
  PB: TPaintBox;
  Entries: uFileModel.TFileEntryList;
  SelectedIndicesRef: TList<Integer>;
begin
  SB := CurrentScrollBox;
  if SB = nil then Exit;

  Entries := GetCurrentEntries;
  SelectedIndicesRef := GetCurrentSelectedIndices;
  if not Assigned(Entries) or not Assigned(SelectedIndicesRef) then Exit;

  TotalCount := VisualCount;
  if TotalCount = 0 then Exit;

  if FSelectionManager.AnchorIndex < 0 then
    FSelectionManager.AnchorIndex := FSelectionManager.CurrentIndex;

  NewIdx := Max(0, Min(TotalCount - 1, FSelectionManager.CurrentIndex + Delta));
  FSelectionManager.CurrentIndex := NewIdx;

  if ssShift in Shift then
  begin
    FSelectionManager.SelectRange(FSelectionManager.AnchorIndex, FSelectionManager.CurrentIndex, False);
  end
  else
  begin
    FSelectionManager.AnchorIndex := NewIdx;
   // FSelectionManager.DeselectAll;
   // SetItemSelected(NewIdx, True);
  end;

  EnsureIndexVisible(NewIdx);

  PB := CurrentPaintBox;
  if Assigned(PB) then
    PB.Repaint;

  UpdateStatusText;
  NotifyCursorChange;
end;

procedure TFilePanel.MoveSelectionGrid(DeltaX, DeltaY: Integer; Shift: TShiftState);
var
  TotalCount, NewIdx, Cols, TS: Integer;
  TileH, SlotW, PadX: Single;
  SB: TVertScrollBox;
  PB: TPaintBox;
  Entries: uFileModel.TFileEntryList;
  SelectedIndicesRef: TList<Integer>;
begin
  SB := CurrentScrollBox;
  if SB = nil then Exit;

  Entries := GetCurrentEntries;
  SelectedIndicesRef := GetCurrentSelectedIndices;
  if not Assigned(Entries) or not Assigned(SelectedIndicesRef) then Exit;

  TotalCount := VisualCount;
  if TotalCount = 0 then Exit;

  GetTileLayout(Max(1, SB.Width - SCROLLBAR_RESERVE), Cols, TS, TileH, SlotW, PadX);

  if FSelectionManager.AnchorIndex < 0 then
    FSelectionManager.AnchorIndex := FSelectionManager.CurrentIndex;

  if DeltaY <> 0 then
    NewIdx := FSelectionManager.CurrentIndex + (DeltaY * Cols)
  else
    NewIdx := FSelectionManager.CurrentIndex + DeltaX;

  NewIdx := Max(0, Min(TotalCount - 1, NewIdx));
  FSelectionManager.CurrentIndex := NewIdx;

  if ssShift in Shift then
  begin
    FSelectionManager.SelectRange(FSelectionManager.AnchorIndex, FSelectionManager.CurrentIndex, False);
  end
  else
  begin
    FSelectionManager.AnchorIndex := NewIdx;
   // FSelectionManager.DeselectAll;
    //SetItemSelected(NewIdx, True);
  end;

  EnsureIndexVisible(NewIdx);

  PB := CurrentPaintBox;
  if Assigned(PB) then
    PB.Repaint;
  NotifyCursorChange;
end;

procedure TFilePanel.OpenSelected;
begin
  PaintBoxDblClick(nil);
end;

procedure TFilePanel.GoBack;
begin
  if IsSearchView then
  begin
    var Tab := FTabs[FActiveTabIndex];
    Tab.SearchView := False;
    Tab.Loaded := False;
    FTabs[FActiveTabIndex] := Tab;
    Refresh('', False);
    Exit;
  end;
  if IsBranchView then
  begin
    ToggleBranchView;
    Exit;
  end;
  if HasParentDirectory then
    NavigateToParent;
end;

function TFilePanel.IsBranchView: Boolean;
begin
  Result := (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) and
    FTabs[FActiveTabIndex].BranchView;
end;

function TFilePanel.IsSearchView: Boolean;
begin
  Result := (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) and
    FTabs[FActiveTabIndex].SearchView;
end;

procedure TFilePanel.ShowSearchHits(const ARoot: string; AList: uFileModel.TFileEntryList);
var
  Tab: TFileTab;
  Root: string;
begin
  if AList = nil then
    Exit;
  Root := ARoot;
  if (Root = '') or not IsBrowsablePath(Root) then
    Root := GetCurrentPathImpl;
  if FTabs.Count = 0 then
    DoAddTab(Root, True);
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
  begin
    AList.Free;
    Exit;
  end;
  EndInlineRename(False);
  Tab := FTabs[FActiveTabIndex];
  Tab.Path := Root;
  Tab.SearchView := True;
  Tab.BranchView := False;
  Tab.Loaded := True;
  Tab.Stale := False;
  Tab.CursorIndex := 0;
  Tab.CursorPath := '';
  FTabs[FActiveTabIndex] := Tab;
  FTabsBar.SetTabInfo(FActiveTabIndex, DisplayNameForPath(Root), Root);
  if Assigned(FSelectionManager) then
  begin
    var SelIndices := GetCurrentSelectedIndices;
    if Assigned(SelIndices) then
      SelIndices.Clear;
    FSelectionManager.ResetState(0);
  end;
  ApplyLoadedList(Root, AList, '', False, nil, '');
  UpdatePathLabel;
  SyncDriveBar;
  if Assigned(FOnPathChanged) then
    FOnPathChanged(Self, Root);
  WatchCurrentPath;
end;

procedure TFilePanel.ToggleBranchView;
var
  Tab: TFileTab;
  Path, Arc, Inner: string;
begin
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
    Exit;
  if IsPathEditing or IsInlineRenaming then
    Exit;
  Path := GetCurrentPathImpl;
  if Path = '' then
    Exit;
  if not FTabs[FActiveTabIndex].BranchView then
  begin
    if IsThisPCPath(Path) then
    begin
      ShowNotice('Ветвь каталога недоступна в «Этот компьютер»');
      Exit;
    end;
    if IsVirtualShellPath(Path) and not TDirectory.Exists(Path) and
       not (SplitArchivePath(Path, Arc, Inner) and IsArchiveFileName(Arc)) then
    begin
      ShowNotice('Ветвь каталога недоступна здесь');
      Exit;
    end;
  end;
  Tab := FTabs[FActiveTabIndex];
  Tab.BranchView := not Tab.BranchView;
  Tab.Loaded := False;
  FTabs[FActiveTabIndex] := Tab;
  Refresh('', False);
end;

procedure TFilePanel.StyleHistBtn(ABtn: TFluentButton; AEnabled: Boolean);
begin
  if ABtn = nil then
    Exit;
  ABtn.Enabled := AEnabled;
  ABtn.HitTest := AEnabled;
  if AEnabled then
    ABtn.Opacity := 1
  else
    ABtn.Opacity := 0.32;
end;

function TFilePanel.CanHistoryBack: Boolean;
begin
  Result := (FTabs.Count > 0) and (FActiveTabIndex >= 0) and
    (FActiveTabIndex < FTabs.Count) and (FTabs[FActiveTabIndex].HistoryIndex > 0);
end;

function TFilePanel.CanHistoryForward: Boolean;
begin
  Result := (FTabs.Count > 0) and (FActiveTabIndex >= 0) and
    (FActiveTabIndex < FTabs.Count) and
    (FTabs[FActiveTabIndex].HistoryIndex < High(FTabs[FActiveTabIndex].History));
end;

procedure TFilePanel.UpdateHistoryButtons;
begin
  StyleHistBtn(FBtnBack, CanHistoryBack);
  StyleHistBtn(FBtnForward, CanHistoryForward);
end;

procedure TFilePanel.RecordHistory(const APath: string);
var
  Tab: TFileTab;
  P: string;
  Idx: Integer;
begin
  if FHistorySilent or (FTabs.Count = 0) then
    Exit;
  P := NormDirHistoryPath(APath);
  if P = '' then
    Exit;
  Tab := FTabs[FActiveTabIndex];
  Idx := Tab.HistoryIndex;
  if (Length(Tab.History) > 0) and (Idx >= 0) and (Idx <= High(Tab.History)) and
     SameDirHistoryPath(Tab.History[Idx], P) then
  begin
    UpdateHistoryButtons;
    Exit;
  end;
  if Idx < High(Tab.History) then
    SetLength(Tab.History, Idx + 1);
  Tab.History := Tab.History + [P];
  if Length(Tab.History) > MAX_DIR_HISTORY then
  begin
    Delete(Tab.History, 0, Length(Tab.History) - MAX_DIR_HISTORY);
  end;
  Tab.HistoryIndex := High(Tab.History);
  FTabs[FActiveTabIndex] := Tab;
  UpdateHistoryButtons;
end;

procedure TFilePanel.HistoryGo(ADelta: Integer);
var
  Tab: TFileTab;
  NewIdx: Integer;
  FromPath, Target: string;
begin
  if FTabs.Count = 0 then
    Exit;
  CancelPathEdit;
  EndInlineRename(False);
  Tab := FTabs[FActiveTabIndex];
  NewIdx := Tab.HistoryIndex + ADelta;
  if (NewIdx < 0) or (NewIdx > High(Tab.History)) then
    Exit;
  FromPath := GetCurrentPathImpl;
  Target := Tab.History[NewIdx];
  Tab.HistoryIndex := NewIdx;
  FTabs[FActiveTabIndex] := Tab;
  FHistoryClearSel := True;
  FHistorySilent := True;
  try
    Navigate(Target, FromPath);
  finally
    FHistorySilent := False;
  end;
  UpdateHistoryButtons;
end;

procedure TFilePanel.HistoryBack;
begin
  HistoryGo(-1);
end;

procedure TFilePanel.HistoryForward;
begin
  HistoryGo(1);
end;

procedure TFilePanel.EnsureIndexVisible(AIndex: Integer);
var
  SB: TVertScrollBox;
  TotalCount, EffectiveCols, Row, TS: Integer;
  VPos, ViewH, ItemTop, ItemBot, ItemSize, MaxVPos: Single;
  TileH, SlotW, PadX: Single;
  Entries: uFileModel.TFileEntryList;
begin
  SB := CurrentScrollBox;
  if SB = nil then Exit;
  if AIndex < 0 then Exit;

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  TotalCount := VisualCount;
  if TotalCount <= 0 then Exit;
  if AIndex >= TotalCount then
    AIndex := TotalCount - 1;

  if ViewMode = vmDetails then
  begin
    EffectiveCols := 1;
    ItemSize := RowHeight;
  end
  else
  begin
    GetTileLayout(Max(1, SB.Width - SCROLLBAR_RESERVE), EffectiveCols, TS, TileH, SlotW, PadX);
    ItemSize := TileH;
  end;

  if ItemSize <= 0 then Exit;

  Row := AIndex div EffectiveCols;
  ItemTop := Row * ItemSize;
  ItemBot := ItemTop + ItemSize;

  VPos := SB.ViewportPosition.Y;
  ViewH := SB.Height;

  if ItemSize >= ViewH then
    VPos := ItemTop
  else if ItemTop < VPos then
    VPos := ItemTop
  else if ItemBot > VPos + ViewH then
    VPos := ItemBot - ViewH
  else
    Exit;

  MaxVPos := Max(0.0, SB.ContentBounds.Height - ViewH);
  VPos := Max(0.0, Min(VPos, MaxVPos));

  SB.ViewportPosition := TPointF.Create(0, VPos);
end;

procedure TFilePanel.PanelonResize(Sender: TObject);
begin
  KeepFocusVisible;
end;

function TFilePanel.GetFocusedEntry(out AEntry: TFileEntry): Boolean;
var
  Entries: TFileEntryList;
  Idx, ActualIndex: Integer;
begin
  Result := False;
  if not Assigned(FSelectionManager) then Exit;

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  Idx := FSelectionManager.CurrentIndex;
  if not VisualToActual(Idx, ActualIndex) then
    Exit;

  if (ActualIndex >= 0) and (ActualIndex < Entries.Count) then
  begin
    AEntry := Entries[ActualIndex];
    Result := True; // Успешно нашли файл под фокусом
  end;
end;

function TFilePanel.HandleSelectionKey(var AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := False;
  if Assigned(FSelectionManager) then
    Result := FSelectionManager.KeyDown(AKey, AShift);
end;

procedure TFilePanel.MoveHome(const AShift: TShiftState);
var
  TotalCount: Integer;
  Entries: uFileModel.TFileEntryList;
begin
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  TotalCount := VisualCount;

  if TotalCount > 0 then
    MoveSelection(0 - FSelectionManager.CurrentIndex, AShift);
end;

procedure TFilePanel.MoveEnd(const AShift: TShiftState);
var
  TotalCount: Integer;
  Entries: uFileModel.TFileEntryList;
begin
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  TotalCount := VisualCount;

  if TotalCount > 0 then
    MoveSelection((TotalCount - 1) - FSelectionManager.CurrentIndex, AShift);
end;

procedure TFilePanel.MovePage(ADirection: Integer; const AShift: TShiftState);
var
  VisibleRows: Integer;
  RH: Single;
  SB: TVertScrollBox;
begin
  SB := CurrentScrollBox;
  if SB = nil then Exit;

  if ViewMode = vmDetails then
  begin
    RH := RowHeight;
    if RH > 0 then
      VisibleRows := Max(1, Trunc(SB.Height / RH) - 1)
    else
      VisibleRows := 10;
  end
  else
  begin
    // Для режима плиток берем примерное число видимых элементов на странице
    VisibleRows := 12;
  end;

  MoveSelection(ADirection * VisibleRows, AShift);
end;

procedure TFilePanel.ToggleCurrentAndMove;
var
  Idx: Integer;
  SelectedIndicesRef: TList<Integer>;
  TotalCount: Integer;
  Entries: uFileModel.TFileEntryList;
begin
  if not Assigned(FSelectionManager) then Exit;

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then Exit;

  TotalCount := VisualCount;

  Idx := FSelectionManager.CurrentIndex;

  // Защита от выхода за границы и от попытки выделить папку ".." (индекс 0)
  if HasParentDirectory and (Idx = 0) then Exit;
  if (Idx < 0) or (Idx >= TotalCount) then Exit;

  SelectedIndicesRef := GetCurrentSelectedIndices;
  if not Assigned(SelectedIndicesRef) then Exit;

  // Инвертируем выбор текущего элемента (добавляем или удаляем из списка мультивыделения)
  if SelectedIndicesRef.Contains(Idx) then
    SelectedIndicesRef.Remove(Idx)
  else
    SelectedIndicesRef.Add(Idx);

  // Перемещаем фокус/курсор на один элемент вниз
  if ViewMode = vmDetails then
    MoveSelection(1, [])
  else
    MoveSelectionGrid(0, 1, []);

  // Перерисовываем панель, чтобы сразу увидеть изменения
  Repaint;
end;

procedure TFilePanel.ClearSelection;
var
  SelIndices: TList<Integer>;
begin
  SelIndices := GetCurrentSelectedIndices;
  if Assigned(SelIndices) then
    SelIndices.Clear;
  if Assigned(FSelectionManager) then
    FSelectionManager.DeselectAll;
  UpdateStatusText;
  InvalidateView;
end;

procedure TFilePanel.SelectAllItems;
begin
  if Assigned(FSelectionManager) then
    FSelectionManager.SelectAll;
  UpdateStatusText;
end;

procedure TFilePanel.InvertSelection;
begin
  if Assigned(FSelectionManager) then
    FSelectionManager.InvertSelection;
  UpdateStatusText;
end;

procedure TFilePanel.SelectByWildcard(const AMask: string; ASelect: Boolean);
begin
  if Assigned(FSelectionManager) then
    FSelectionManager.SelectByWildcard(AMask, ASelect);
  UpdateStatusText;
end;

procedure TFilePanel.SelectSameExtension(ASelect: Boolean);
var
  Ext: string;
  Idx: Integer;
begin
  if not Assigned(FSelectionManager) then
    Exit;
  Idx := FSelectionManager.CurrentIndex;
  Ext := GetItemExtension(Idx);
  FSelectionManager.SelectByMask(Ext, ASelect);
  UpdateStatusText;
end;

procedure TFilePanel.SelectFilesOnly;
begin
  if Assigned(FSelectionManager) then
    FSelectionManager.SelectFilesOnly;
  UpdateStatusText;
end;

procedure TFilePanel.SelectFoldersOnly;
begin
  if Assigned(FSelectionManager) then
    FSelectionManager.SelectFoldersOnly;
  UpdateStatusText;
end;

procedure TFilePanel.CompareDirectories(AOther: TFilePanel);
var
  Mine, Theirs: uFileModel.TFileEntryList;
  Map: TDictionary<string, TFileEntry>;
  I, Visual, Marked: Integer;
  E, O: TFileEntry;
  Unique, Differ: Boolean;
begin
  if not Assigned(AOther) or not Assigned(FSelectionManager) then
    Exit;
  Mine := GetCurrentEntries;
  Theirs := AOther.GetCurrentEntries;
  if not Assigned(Mine) or not Assigned(Theirs) then
    Exit;
  FSelectionManager.DeselectAll;
  Map := TDictionary<string, TFileEntry>.Create;
  try
    for I := 0 to Theirs.Count - 1 do
      Map.AddOrSetValue(LowerCase(Theirs[I].Name), Theirs[I]);
    Marked := 0;
    for I := 0 to Mine.Count - 1 do
    begin
      E := Mine[I];
      Visual := VisualFromActual(I);
      if Visual < 0 then
        Continue;
      Unique := not Map.TryGetValue(LowerCase(E.Name), O);
      Differ := False;
      if not Unique and not E.IsDirectory and not O.IsDirectory then
        Differ := (E.Size <> O.Size) or (Abs(E.Modified - O.Modified) > (2 / 86400));
      if Unique or Differ then
      begin
        SetItemSelected(Visual, True);
        Inc(Marked);
      end;
    end;
  finally
    Map.Free;
  end;
  InvalidateView;
  UpdateStatusText;
  if Marked = 0 then
    ShowNotice('Каталоги совпадают')
  else
    ShowNotice(Format('Отмечено отличий: %d', [Marked]));
end;

function TFilePanel.FocusByMask(const AMask: string): Boolean;
var
  I, VisualIdx: Integer;
  Entries: uFileModel.TFileEntryList;
  Pattern: string;
begin
  Result := False;
  Pattern := Trim(AMask);
  if Pattern = '' then
    Exit;
  if (Pos('*', Pattern) = 0) and (Pos('?', Pattern) = 0) then
    Pattern := '*' + Pattern + '*';

  Entries := GetCurrentEntries;
  if not Assigned(Entries) then
    Exit;

  for I := 0 to Entries.Count - 1 do
    if MatchesMask(Entries[I].Name, Pattern) then
    begin
      VisualIdx := VisualFromActual(I);
      if VisualIdx < 0 then
        Continue;
      if Assigned(FSelectionManager) then
        FSelectionManager.CurrentIndex := VisualIdx;
      EnsureIndexVisible(VisualIdx);
      InvalidateView;
      NotifyCursorChange;
      Result := True;
      Exit;
    end;
end;

procedure TFilePanel.DeselectByPath(const APath: string);
var
  Entries: uFileModel.TFileEntryList;
  SelectedIndicesRef: TList<Integer>;
  I, VisualIdx: Integer;
  Want, Have: string;
begin
  if not Assigned(FSelectionManager) then Exit;
  Entries := GetCurrentEntries;
  SelectedIndicesRef := GetCurrentSelectedIndices;
  if not Assigned(Entries) or not Assigned(SelectedIndicesRef) then Exit;
  if APath = '' then Exit;

  Want := ExcludeTrailingPathDelimiter(APath);
  VisualIdx := -1;
  for I := 0 to Entries.Count - 1 do
  begin
    Have := ExcludeTrailingPathDelimiter(Entries[I].FullPath);
    if SameText(Have, Want) then
    begin
      VisualIdx := VisualFromActual(I);
      Break;
    end;
  end;

  if VisualIdx <> -1 then
  begin
    SelectedIndicesRef.Remove(VisualIdx);
    InvalidateView;
  end;
end;

procedure TFilePanel.BindDragEvents(AControl: TControl);
begin
  if AControl = nil then
    Exit;
  AControl.OnDragOver := PanelDragOver;
  AControl.OnDragDrop := PanelDragDrop;
  AControl.OnDragLeave := PanelDragLeave;
end;

function TFilePanel.CollectDragPaths: TArray<string>;
var
  Entries: TArray<TFileEntry>;
  I, N: Integer;
  Focused: TFileEntry;
begin
  Entries := SelectedEntries;
  SetLength(Result, Length(Entries));
  N := 0;
  for I := 0 to High(Entries) do
    if Entries[I].FullPath <> '' then
    begin
      Result[N] := Entries[I].FullPath;
      Inc(N);
    end;
  SetLength(Result, N);
  if (Length(Result) = 0) and GetFocusedEntry(Focused) and (Focused.FullPath <> '') then
  begin
    SetLength(Result, 1);
    Result[0] := Focused.FullPath;
  end;
end;

function TFilePanel.FileListsEquivalent(A, B: uFileModel.TFileEntryList): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (A = nil) or (B = nil) then
    Exit;
  if A.Count <> B.Count then
    Exit;
  for I := 0 to A.Count - 1 do
  begin
    if not SameText(A[I].FullPath, B[I].FullPath) then
      Exit;
    if A[I].IsDirectory <> B[I].IsDirectory then
      Exit;
    if A[I].Size <> B[I].Size then
      Exit;
    if Abs(A[I].Modified - B[I].Modified) >= (2.1 / 86400.0) then
      Exit;
    if A[I].IsHidden <> B[I].IsHidden then
      Exit;
  end;
  Result := True;
end;

procedure TFilePanel.RefreshThumbs;
var
  Entries: uFileModel.TFileEntryList;
  E: TFileEntry;
  Sz: Integer;
begin
  if FDestroying then
    Exit;
  if Assigned(GlobalIconCache) and not IsRemotePath(GetCurrentPathImpl) then
  begin
    GlobalIconCache.PrefetchTypes(GetCurrentEntries,
      SelectIconBucket(CurrentIconTarget), IconSceneScale);
    if Assigned(FThumbTimer) then
      FThumbTimer.Enabled := True;
  end;
  if ViewMode <> vmTiles then
    Exit;
  if TileSize < 64 then
    Exit;
  if IsRemotePath(GetCurrentPathImpl) then
    Exit;
  if not Assigned(GlobalThumbCache) or not GlobalThumbCache.WorkersEnabled then
    Exit;
  Entries := GetCurrentEntries;
  if not Assigned(Entries) then
    Exit;
  Sz := TileSize;
  for E in Entries do
  begin
    if IsThumbCandidate(E.FullPath, E.IsDirectory, E.Name) then
      GlobalThumbCache.RequestAsync(E.FullPath, Sz, nil, E.Name);
    if Assigned(GlobalMetaCache) and not E.IsDirectory then
      GlobalMetaCache.RequestAsync(E.FullPath);
  end;
  if Assigned(FThumbTimer) then
    FThumbTimer.Enabled := True;
end;

procedure TFilePanel.ThumbTimerTick(Sender: TObject);
begin
  if FDestroying then
  begin
    if Assigned(FThumbTimer) then
      FThumbTimer.Enabled := False;
    Exit;
  end;
  if Assigned(GlobalThumbCache) and (FThumbGen <> GlobalThumbCache.Generation) then
  begin
    FThumbGen := GlobalThumbCache.Generation;
    InvalidateView;
  end;
  if Assigned(GlobalIconCache) and (FIconGen <> GlobalIconCache.Generation) then
  begin
    FIconGen := GlobalIconCache.Generation;
    InvalidateView;
  end;
  if Assigned(GlobalMetaCache) and (FMetaGen <> GlobalMetaCache.Generation) then
  begin
    FMetaGen := GlobalMetaCache.Generation;
    InvalidateView;
  end;
  if (not Assigned(GlobalThumbCache) or not GlobalThumbCache.HasWork) and
     (not Assigned(GlobalIconCache) or not GlobalIconCache.HasWork) and
     (not Assigned(GlobalMetaCache) or not GlobalMetaCache.HasWork) then
    if Assigned(FThumbTimer) then
      FThumbTimer.Enabled := False;
end;

procedure TFilePanel.StartInternalDrag;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
{$ENDIF}
begin
  if GFileDrag.Active then
    Exit;
  if Length(FDragPaths) = 0 then
    FDragPaths := CollectDragPaths;
  if Length(FDragPaths) = 0 then
    Exit;
  GFileDrag.Active := True;
  GFileDrag.OleExport := False;
  GFileDrag.Consumed := False;
  GFileDrag.Source := Self;
  GFileDrag.Hover := nil;
  GFileDrag.Paths := FDragPaths;
  GFileDrag.OleFiles := PrepareOleDragFiles(FDragPaths);
  Capture;
  Cursor := crDrag;
  {$IFDEF MSWINDOWS}
  if Root is TCommonCustomForm then
  begin
    Wnd := FormToHWND(TCommonCustomForm(Root));
    if Wnd <> 0 then
      SetCapture(Wnd);
  end;
  {$ENDIF}
  if Assigned(FDragPollTimer) then
    FDragPollTimer.Enabled := True;
  ApplyCardChrome;
  InvalidateView;
end;

procedure TFilePanel.SetDropHot(AHot: Boolean);
begin
  if FDropTargetHot = AHot then
    Exit;
  FDropTargetHot := AHot;
  if not AHot then
    FDropHighlightIndex := -2;
  ApplyCardChrome;
  InvalidateView;
end;

function TFilePanel.PointInOwnForm(const AScreen: TPointF): Boolean;
var
  Form: TCommonCustomForm;
  Client: TPointF;
  {$IFDEF MSWINDOWS}
  Wnd, Hit, FormRoot: HWND;
  R: TRect;
  Pt: TPoint;
  {$ENDIF}
begin
  Result := False;
  if not (Root is TCommonCustomForm) then
    Exit;
  Form := TCommonCustomForm(Root);
  {$IFDEF MSWINDOWS}
  Wnd := FormToHWND(Form);
  if Wnd <> 0 then
  begin
    Pt.X := Round(AScreen.X);
    Pt.Y := Round(AScreen.Y);
    Hit := WindowFromPoint(Pt);
    if Hit <> 0 then
    begin
      FormRoot := GetAncestor(Wnd, GA_ROOT);
      if FormRoot = 0 then
        FormRoot := Wnd;
      { Чужое окно / панель задач — сразу OLE, не ждать выхода из GetWindowRect. }
      if GetAncestor(Hit, GA_ROOT) <> FormRoot then
        Exit(False);
    end;
    GetWindowRect(Wnd, R);
    InflateRect(R, -2, -2);
    Result := (Pt.X >= R.Left) and (Pt.X < R.Right) and
      (Pt.Y >= R.Top) and (Pt.Y < R.Bottom);
    Exit;
  end;
  {$ENDIF}
  Client := Form.ScreenToClient(AScreen);
  Result := (Client.X >= 0) and (Client.Y >= 0) and
    (Client.X < Form.ClientWidth) and (Client.Y < Form.ClientHeight);
end;

function PrepareOleDragFiles(const APaths: TArray<string>): TArray<string>;
var
  I: Integer;
  Arc, Inner, LocalDir, Local: string;
begin
  SetLength(Result, 0);
  for I := 0 to High(APaths) do
  begin
    if TFile.Exists(APaths[I]) or TDirectory.Exists(APaths[I]) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := APaths[I];
    end
    else if SplitArchivePath(APaths[I], Arc, Inner) and (Inner <> '') then
    begin
      LocalDir := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath, 'TCClone\drag');
      ForceDirectories(LocalDir);
      try
        CopyPathSync(APaths[I], LocalDir);
        Local := System.IOUtils.TPath.Combine(LocalDir,
          ExtractFileName(ExcludeTrailingPathDelimiter(APaths[I])));
        if TFile.Exists(Local) or TDirectory.Exists(Local) then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Local;
        end;
      except
      end;
    end;
  end;
end;

procedure TFilePanel.StartOleExport;
{$IFDEF MSWINDOWS}
var
  Paths: TArray<string>;
  Effect: Integer;
  Src, Hover: TFilePanel;
  Wnd: HWND;
begin
  if not GFileDrag.Active or GFileDrag.OleExport then
    Exit;
  GFileDrag.OleExport := True;
  if Assigned(FDragPollTimer) then
    FDragPollTimer.Enabled := False;
  ReleaseCapture;
  if GetCapture <> 0 then
    Winapi.Windows.ReleaseCapture;
  Cursor := crDefault;
  Hover := GFileDrag.Hover;
  if Assigned(Hover) then
  begin
    Hover.SetDropHot(False);
    GFileDrag.Hover := nil;
  end;
  Src := GFileDrag.Source;
  Paths := GFileDrag.OleFiles;
  if Length(Paths) = 0 then
    Paths := PrepareOleDragFiles(GFileDrag.Paths);
  if Assigned(Src) then
  begin
    Src.ApplyCardChrome;
    Src.InvalidateView;
  end;
  if Length(Paths) = 0 then
  begin
    GFileDrag.Active := False;
    GFileDrag.OleExport := False;
    GFileDrag.Source := nil;
    SetLength(GFileDrag.Paths, 0);
    SetLength(GFileDrag.OleFiles, 0);
    Exit;
  end;
  Wnd := 0;
  if Root is TCommonCustomForm then
    Wnd := FormToHWND(TCommonCustomForm(Root));
  try
    if DragFilesToOle(Paths, Effect, Wnd) then
      if (not GFileDrag.Consumed) and Assigned(Src) and not Src.FDestroying then
      begin
        Src.ClearSelection;
        if (Effect and 2) <> 0 then
          Src.Refresh;
      end;
  finally
    if Assigned(GFileDrag.Hover) then
      GFileDrag.Hover.SetDropHot(False);
    GFileDrag.Active := False;
    GFileDrag.OleExport := False;
    GFileDrag.Consumed := False;
    GFileDrag.Source := nil;
    GFileDrag.Hover := nil;
    SetLength(GFileDrag.Paths, 0);
    SetLength(GFileDrag.OleFiles, 0);
    if Assigned(Src) and not Src.FDestroying then
    begin
      Src.Cursor := crDefault;
      Src.ApplyCardChrome;
      Src.InvalidateView;
    end;
  end;
end;
{$ELSE}
begin
  FileDragEnd(TMouseButton.mbLeft, []);
end;
{$ENDIF}

function HitPanelIn(AObj: TFmxObject; const AFormPt: TPointF): TFilePanel; forward;

class function TFilePanel.HitAtScreen(ARoot: TFmxObject; const AScreen: TPointF): TFilePanel;
var
  Form: TCommonCustomForm;
begin
  Result := nil;
  if ARoot is TCommonCustomForm then
    Form := TCommonCustomForm(ARoot)
  else if Assigned(ARoot) and (ARoot.Root is TCommonCustomForm) then
    Form := TCommonCustomForm(ARoot.Root)
  else
    Exit;
  Result := HitPanelIn(Form, Form.ScreenToClient(AScreen));
end;

function TFilePanel.CanDropBrowserDest(const ADest: string): Boolean;
var
  Dest, Z, Inner: string;
begin
  Dest := ExcludeTrailingPathDelimiter(ADest);
  Result := False;
  if (Dest = '') or FDestroying then
    Exit;
  if IsThisPCPath(Dest) or IsVirtualShellPath(Dest) then
    Exit;
  if SplitArchivePath(Dest, Z, Inner) then
    Exit;
  if IsRemotePath(Dest) or IsUncPath(Dest) then
    Exit(True);
  if TFile.Exists(Dest) then
    Exit;
  Result := TDirectory.Exists(Dest);
end;

function TFilePanel.TrackExternalDrop(const AScreen: TPointF; ABrowser: Boolean;
  out ADest: string): Boolean;
var
  PB: TPaintBox;
  Local: TPointF;
  Highlight: Integer;
begin
  Result := False;
  ADest := '';
  if FDestroying then
    Exit;
  PB := CurrentPaintBox;
  if PB = nil then
    Exit;
  Local := PB.ScreenToLocal(AScreen);
  ADest := ResolveDropPath(Local, Highlight);
  if ABrowser then
    Result := CanDropBrowserDest(ADest)
  else
    Result := CanDropTo(ADest, nil);
  if not Result then
  begin
    SetDropHot(False);
    Exit;
  end;
  FDropTargetHot := True;
  if FDropHighlightIndex <> Highlight then
  begin
    FDropHighlightIndex := Highlight;
    ApplyCardChrome;
    InvalidateView;
  end
  else
    ApplyCardChrome;
end;

procedure TFilePanel.FinishBrowserFiles(const ADest: string; const AFiles: TArray<string>);
var
  F: string;
begin
  if FDestroying then
    Exit;
  for F in AFiles do
  begin
    if Assigned(GlobalThumbCache) then
      GlobalThumbCache.Invalidate(F);
    if Assigned(GlobalIconCache) then
      GlobalIconCache.InvalidatePath(F);
    if Assigned(GlobalMetaCache) then
      GlobalMetaCache.Invalidate(F);
  end;
  if Length(AFiles) = 1 then
    Refresh(AFiles[0])
  else
    Refresh;
end;

function HitPanelIn(AObj: TFmxObject; const AFormPt: TPointF): TFilePanel;
var
  I: Integer;
begin
  Result := nil;
  if AObj = nil then
    Exit;
  if (AObj is TFilePanel) and TFilePanel(AObj).Visible and
     TFilePanel(AObj).AbsoluteRect.Contains(AFormPt) then
    Exit(TFilePanel(AObj));
  for I := 0 to AObj.ChildrenCount - 1 do
  begin
    Result := HitPanelIn(AObj.Children[I], AFormPt);
    if Result <> nil then
      Exit;
  end;
end;

function TFilePanel.PanelAtScreen(const AScreen: TPointF): TFilePanel;
var
  Form: TCommonCustomForm;
begin
  Result := nil;
  if not (Root is TCommonCustomForm) then
    Exit;
  Form := TCommonCustomForm(Root);
  Result := HitPanelIn(Form, Form.ScreenToClient(AScreen));
end;

procedure TFilePanel.FileDragTrack;
var
  ScreenPt: TPointF;
  Target: TFilePanel;
  Local: TPointF;
  Dest: string;
  Highlight: Integer;
  PB: TPaintBox;
  Pt: TPoint;
begin
  if not GFileDrag.Active or GFileDrag.OleExport then
    Exit;
  GetCursorPos(Pt);
  ScreenPt := TPointF.Create(Pt.X, Pt.Y);
  if not PointInOwnForm(ScreenPt) then
  begin
    StartOleExport;
    Exit;
  end;
  Target := PanelAtScreen(ScreenPt);
  if (GFileDrag.Hover <> nil) and (GFileDrag.Hover <> Target) then
    GFileDrag.Hover.SetDropHot(False);
  GFileDrag.Hover := Target;
  if Target = nil then
    Exit;
  PB := Target.CurrentPaintBox;
  if PB = nil then
    Exit;
  Local := PB.ScreenToLocal(ScreenPt);
  Dest := Target.ResolveDropPath(Local, Highlight);
  if not Target.CanDropTo(Dest, GFileDrag.Paths) then
  begin
    Target.SetDropHot(False);
    Exit;
  end;
  if (not Target.FDropTargetHot) or (Target.FDropHighlightIndex <> Highlight) then
  begin
    Target.FDropTargetHot := True;
    Target.FDropHighlightIndex := Highlight;
    Target.ApplyCardChrome;
    Target.InvalidateView;
  end
  else
    Target.ApplyCardChrome;
end;

procedure TFilePanel.DragPollTimerTick(Sender: TObject);
begin
  if FDestroying or not GFileDrag.Active or GFileDrag.OleExport then
  begin
    if Assigned(FDragPollTimer) then
      FDragPollTimer.Enabled := False;
    Exit;
  end;
  FileDragTrack;
end;

procedure TFilePanel.FileDragEnd(AButton: TMouseButton; AShift: TShiftState);
var
  Target: TFilePanel;
  ScreenPt, Local: TPointF;
  Dest: string;
  Highlight: Integer;
  PB: TPaintBox;
  MoveOp: Boolean;
  Src: TFilePanel;
  Paths: TArray<string>;
  Pt: TPoint;
begin
  if not GFileDrag.Active or GFileDrag.OleExport then
    Exit;
  if Assigned(FDragPollTimer) then
    FDragPollTimer.Enabled := False;
  Target := GFileDrag.Hover;
  GetCursorPos(Pt);
  ScreenPt := TPointF.Create(Pt.X, Pt.Y);
  if Target = nil then
    Target := PanelAtScreen(ScreenPt);
  ReleaseCapture;
  {$IFDEF MSWINDOWS}
  if GetCapture <> 0 then
    Winapi.Windows.ReleaseCapture;
  {$ENDIF}
  Cursor := crDefault;
  Src := GFileDrag.Source;
  Paths := Copy(GFileDrag.Paths);
  if Assigned(GFileDrag.Hover) then
    GFileDrag.Hover.SetDropHot(False);
  GFileDrag.Active := False;
  GFileDrag.Source := nil;
  GFileDrag.Hover := nil;
  SetLength(GFileDrag.Paths, 0);
  SetLength(GFileDrag.OleFiles, 0);
  if Assigned(Src) then
  begin
    Src.ApplyCardChrome;
    Src.InvalidateView;
  end;
  if (AButton <> TMouseButton.mbLeft) or (Length(Paths) = 0) then
    Exit;
  if Assigned(GFileDragDropHook) and GFileDragDropHook(ScreenPt, Paths) then
  begin
    if Assigned(Src) and not Src.FDestroying then
      Src.ClearSelection;
    Exit;
  end;
  if Target = nil then
    Exit;
  PB := Target.CurrentPaintBox;
  if PB <> nil then
    Local := PB.ScreenToLocal(ScreenPt)
  else
    Local := TPointF.Zero;
  Dest := Target.ResolveDropPath(Local, Highlight);
  MoveOp := ssShift in AShift;
  if Target.CanDropTo(Dest, Paths) then
    Target.ApplyDrop(Dest, Paths, MoveOp, Src);
end;

procedure TFilePanel.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if GFileDrag.Active then
    FileDragTrack;
end;

procedure TFilePanel.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if GFileDrag.Active then
  begin
    FileDragEnd(Button, Shift);
    Exit;
  end;
  if FPendingRightSelect or FSelectionManager.IsDragging then
  begin
    if FPendingRightSelect and (Button = TMouseButton.mbRight) and FLongClickArmed then
      FSelectionManager.MouseDown(FLongClickIdx, TMouseButton.mbRight, Shift);
    FSelectionManager.MouseUp(Button);
    EndRightPaint;
    UpdateStatusText;
  end;
  inherited;
end;

function TFilePanel.CollectDragFiles(const Data: TDragObject): TArray<string>;
var
  I: Integer;
begin
  if GFileDrag.Active and (Length(GFileDrag.Paths) > 0) then
    Exit(Copy(GFileDrag.Paths));
  if Data.Source is TFilePanel then
    Result := TFilePanel(Data.Source).FDragPaths
  else
  begin
    SetLength(Result, Length(Data.Files));
    for I := 0 to High(Data.Files) do
      Result[I] := Data.Files[I];
  end;
  if (Length(Result) = 0) and (Data.Source is TFilePanel) then
    Result := TFilePanel(Data.Source).CollectDragPaths;
end;

function TFilePanel.LocalPointOnPaintBox(Sender: TObject; const Point: TPointF): TPointF;
var
  PB: TPaintBox;
  C: TControl;
begin
  PB := CurrentPaintBox;
  if PB = nil then
    Exit(Point);
  if Sender = PB then
    Exit(Point);
  if Sender is TControl then
  begin
    C := TControl(Sender);
    Result := PB.AbsoluteToLocal(C.LocalToAbsolute(Point));
  end
  else
    Result := Point;
end;

function TFilePanel.ResolveDropPath(const ALocal: TPointF; out AHighlight: Integer): string;
var
  Idx, Actual: Integer;
  Entries: uFileModel.TFileEntryList;
  Arc, Inner: string;
begin
  Result := GetCurrentPathImpl;
  AHighlight := -1;
  Idx := GetIndexAt(ALocal.X, ALocal.Y);
  Entries := GetCurrentEntries;
  if not Assigned(Entries) or (Idx < 0) then
    Exit;

  if HasParentDirectory and (Idx = 0) then
  begin
    AHighlight := 0;
    Result := ExtractFileDir(ExcludeTrailingPathDelimiter(GetCurrentPathImpl));
    if Result = '' then
      Result := GetCurrentPathImpl;
    Exit;
  end;

  if not VisualToActual(Idx, Actual) then
    Exit;
  if (Actual >= 0) and (Actual < Entries.Count) then
  begin
    if Entries[Actual].IsDirectory or
       (TFile.Exists(Entries[Actual].FullPath) and
        IsArchiveFileName(Entries[Actual].FullPath)) or
       (IsArchiveFileName(Entries[Actual].Name) and
        SplitArchivePath(Entries[Actual].FullPath, Arc, Inner)) then
    begin
      AHighlight := Idx;
      Result := Entries[Actual].FullPath;
    end;
  end;
end;

function TFilePanel.CanDropTo(const ADest: string; const ASources: TArray<string>): Boolean;
var
  Dest, Src, DestSlash, SrcSlash, ZipFile, ZipInner: string;
begin
  Dest := ExcludeTrailingPathDelimiter(ADest);
  Result := Dest <> '';
  if not Result then
    Exit;
  if SplitArchivePath(Dest, ZipFile, ZipInner) and IsArchiveFileName(ZipFile) then
    Result := True
  else if IsRemotePath(Dest) or IsUncPath(Dest) then
    Result := True
  else
    Result := TDirectory.Exists(Dest);
  if not Result then
    Exit;
  DestSlash := IncludeTrailingPathDelimiter(Dest);
  for Src in ASources do
  begin
    if SameText(ExcludeTrailingPathDelimiter(Src), Dest) then
      Exit(False);
    SrcSlash := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Src));
    if StartsText(SrcSlash, DestSlash) and
       (IsRemotePath(Src) or TDirectory.Exists(Src)) then
      Exit(False);
  end;
end;

procedure TFilePanel.ApplyDrop(const ADest: string; const ASources: TArray<string>;
  AMove: Boolean; ASourcePanel: TFilePanel);
var
  Src, ParentDir, FocusPath: string;
  DestPanel, SrcPanel: TFilePanel;
  Paths: TArray<string>;
begin
  DestPanel := Self;
  SrcPanel := ASourcePanel;
  SetLength(Paths, 0);
  for Src in ASources do
  begin
    ParentDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(Src)));
    if SameText(ParentDir, ExcludeTrailingPathDelimiter(ADest)) then
      Continue;
    SetLength(Paths, Length(Paths) + 1);
    Paths[High(Paths)] := Src;
  end;
  if Length(Paths) = 0 then
    Exit;

  FocusPath := '';
  if AMove and Assigned(SrcPanel) then
    FocusPath := SrcPanel.FocusPathAfterRemove(Paths);

  if Assigned(FOnDropCopyMove) then
  begin
    FOnDropCopyMove(Self, ADest, Paths, AMove, SrcPanel);
    Exit;
  end;

  if AMove then
    MovePathsAsync(Paths, ADest,
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if not DestPanel.FDestroying then
          DestPanel.Refresh;
        if Assigned(SrcPanel) and not SrcPanel.FDestroying then
        begin
          SrcPanel.ClearSelection;
          SrcPanel.Refresh(FocusPath);
        end;
        if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') then
          DestPanel.ShowNotice(ErrorMsg);
      end)
  else
    CopyPathsAsync(Paths, ADest,
      procedure(Success: Boolean; const ErrorMsg: string)
      begin
        if not DestPanel.FDestroying then
          DestPanel.Refresh;
        if Assigned(SrcPanel) and not SrcPanel.FDestroying then
          SrcPanel.ClearSelection;
        if (not Success) and (ErrorMsg <> '') and (ErrorMsg <> 'Отменено') then
          DestPanel.ShowNotice(ErrorMsg);
      end);
end;

procedure TFilePanel.PanelDragOver(Sender: TObject; const Data: TDragObject;
  const Point: TPointF; var Operation: TDragOperation);
var
  Files: TArray<string>;
  Dest: string;
  Highlight: Integer;
  ShiftMove: Boolean;
begin
  if IsTabDragActive then
  begin
    HandleTabDragOver(Sender, Point, Operation);
    Exit;
  end;

  Operation := TDragOperation.None;
  Files := CollectDragFiles(Data);
  if Length(Files) = 0 then
    Exit;

  Dest := ResolveDropPath(LocalPointOnPaintBox(Sender, Point), Highlight);
  if not CanDropTo(Dest, Files) then
  begin
    SetDropHot(False);
    Exit;
  end;

  {$IFDEF MSWINDOWS}
  ShiftMove := (GetKeyState(VK_SHIFT) and $8000) <> 0;
  {$ELSE}
  ShiftMove := False;
  {$ENDIF}

  if ShiftMove then
    Operation := TDragOperation.Move
  else
    Operation := TDragOperation.Copy;

  FDropTargetHot := True;
  if FDropHighlightIndex <> Highlight then
  begin
    FDropHighlightIndex := Highlight;
    ApplyCardChrome;
    InvalidateView;
  end
  else
    ApplyCardChrome;
end;

procedure TFilePanel.PanelDragDrop(Sender: TObject; const Data: TDragObject; const Point: TPointF);
var
  Files: TArray<string>;
  Dest: string;
  Highlight: Integer;
  ShiftMove: Boolean;
  SrcPanel: TFilePanel;
begin
  if IsTabDragActive then
  begin
    HandleTabDragDrop(Sender, Point);
    Exit;
  end;

  Files := CollectDragFiles(Data);
  Dest := ResolveDropPath(LocalPointOnPaintBox(Sender, Point), Highlight);
  SetDropHot(False);
  if GFileDrag.Active then
    GFileDrag.Consumed := True;
  if (Length(Files) = 0) or not CanDropTo(Dest, Files) then
    Exit;

  {$IFDEF MSWINDOWS}
  ShiftMove := (GetKeyState(VK_SHIFT) and $8000) <> 0;
  {$ELSE}
  ShiftMove := False;
  {$ENDIF}

  if Data.Source is TFilePanel then
    SrcPanel := TFilePanel(Data.Source)
  else
    SrcPanel := nil;

  if Assigned(FOnActivate) then
    FOnActivate(Self);

  ApplyDrop(Dest, Files, ShiftMove, SrcPanel);
end;

procedure TFilePanel.PanelDragLeave(Sender: TObject);
begin
  if Assigned(FTabsBar) then
    FTabsBar.HideDropHint;
  SetDropHot(False);
end;

procedure TFilePanel.ApplyTabState(AIndex: Integer; const AState: TTabState);
var
  Tab: TFileTab;
  Caption: string;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  Tab.Path := AState.Path;
  Tab.ViewMode := AState.ViewMode;
  Tab.ZoomDetails := EnsureRange(AState.ZoomDetails, MIN_ZOOM, MAX_ZOOM);
  Tab.ZoomTiles := EnsureRange(AState.ZoomTiles, MIN_TILE_ZOOM, MAX_TILE_ZOOM);
  if (AState.SortField >= Ord(Low(TSortField))) and (AState.SortField <= Ord(High(TSortField))) then
    Tab.SortField := TSortField(AState.SortField)
  else
    Tab.SortField := sfName;
  Tab.SortAsc := AState.SortAsc;
  Tab.CursorPath := AState.CursorPath;
  Tab.CursorIndex := 0;
  Tab.Loaded := False;
  Tab.Stale := True;
  FTabs[AIndex] := Tab;

  Caption := ExtractFileName(ExcludeTrailingPathDelimiter(AState.Path));
  if Caption = '' then
    Caption := AState.Path;
  if Assigned(FTabsBar) then
    FTabsBar.SetTabInfo(AIndex, Caption, AState.Path);
end;

procedure TFilePanel.CaptureTabs(out AState: TSideState);
var
  I: Integer;
  Tab: TFileTab;
  Pair: TPair<string, string>;
begin
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) then
    SaveTabCursor(FActiveTabIndex);
  AState.ActiveTab := FActiveTabIndex;
  SetLength(AState.Tabs, FTabs.Count);
  for I := 0 to FTabs.Count - 1 do
  begin
    Tab := FTabs[I];
    AState.Tabs[I].Path := Tab.Path;
    AState.Tabs[I].ViewMode := Tab.ViewMode;
    AState.Tabs[I].ZoomDetails := Tab.ZoomDetails;
    AState.Tabs[I].ZoomTiles := Tab.ZoomTiles;
    AState.Tabs[I].SortField := Ord(Tab.SortField);
    AState.Tabs[I].SortAsc := Tab.SortAsc;
    AState.Tabs[I].CursorPath := Tab.CursorPath;
    RememberDrivePath(Tab.Path);
  end;
  SetLength(AState.DriveLast, 0);
  if Assigned(FDriveLast) then
  begin
    SetLength(AState.DriveLast, FDriveLast.Count);
    I := 0;
    for Pair in FDriveLast do
    begin
      AState.DriveLast[I].Root := Pair.Key;
      AState.DriveLast[I].Path := Pair.Value;
      Inc(I);
    end;
  end;
  if AState.ActiveTab < 0 then
    AState.ActiveTab := 0;
end;

procedure TFilePanel.RestoreTabs(const AState: TSideState);
var
  I, Active: Integer;
  Tab: TFileTab;
begin
  FDeferDirLoad := True;
  FListReadyFired := False;
  if Length(AState.Tabs) = 0 then
  begin
    DoAddTab(ExtractFileDrive(ParamStr(0)) + '\', True);
    if FTabs.Count > 0 then
    begin
      Tab := FTabs[0];
      Tab.Stale := True;
      Tab.Loaded := False;
      FTabs[0] := Tab;
    end;
    Exit;
  end;

  for I := 0 to High(AState.Tabs) do
    DoAddTab(AState.Tabs[I].Path, False);

  for I := 0 to High(AState.Tabs) do
    if I < FTabs.Count then
      ApplyTabState(I, AState.Tabs[I]);

  Active := AState.ActiveTab;
  if (Active < 0) or (Active >= FTabs.Count) then
    Active := 0;
  FActiveTabIndex := Active;
  if Assigned(FTabsBar) then
    FTabsBar.SelectTab(Active);
  if Assigned(FDriveLast) then
  begin
    FDriveLast.Clear;
    for I := 0 to High(AState.DriveLast) do
      if AState.DriveLast[I].Root <> '' then
        FDriveLast.AddOrSetValue(DriveClickKey(AState.DriveLast[I].Root),
          AState.DriveLast[I].Path);
    for I := 0 to FTabs.Count - 1 do
      RememberDrivePath(FTabs[I].Path);
  end;
  SyncDriveBar;
end;

procedure TFilePanel.LoadActiveTab;
var
  Tab: TFileTab;
begin
  FDeferDirLoad := False;
  if (FActiveTabIndex < 0) or (FActiveTabIndex >= FTabs.Count) then
  begin
    if Assigned(FOnListReady) and not FListReadyFired then
    begin
      FListReadyFired := True;
      FOnListReady(Self);
    end;
    Exit;
  end;
  Tab := FTabs[FActiveTabIndex];
  Tab.Stale := False;
  FTabs[FActiveTabIndex] := Tab;
  UpdatePathLabel;
  SyncDriveBar;
  Refresh('', True);
end;

function TFilePanel.LoadNextStaleTab: Boolean;
var
  I: Integer;
  Tab: TFileTab;
begin
  Result := False;
  if FDestroying then
    Exit;
  if ActiveLoadCount >= 3 then
    Exit(True);
  for I := 0 to FTabs.Count - 1 do
  begin
    if I = FActiveTabIndex then
      Continue;
    Tab := FTabs[I];
    if Tab.Stale or not Tab.Loaded then
    begin
      Tab.Stale := False;
      FTabs[I] := Tab;
      StartDirLoadAt(I, Tab.Path, '', True);
      Exit(True);
    end;
  end;
end;

procedure TFilePanel.EnableDirWatch;
begin
  FWatchEnabled := True;
  if (FActiveTabIndex >= 0) and (FActiveTabIndex < FTabs.Count) and
     FTabs[FActiveTabIndex].Loaded and not FTabs[FActiveTabIndex].Loading then
    WatchTab(FActiveTabIndex);
end;

procedure TFilePanel.StartDeferredDrives;
begin
  if not Assigned(FDriveBar) then
    Exit;
  FDriveBar.PopulateLetters;
  FDriveBar.StartUsageFill;
end;

procedure TFilePanel.AddSlowPlaces;
begin
  if Assigned(FDriveBar) then
    FDriveBar.AddPortablePlaces;
end;

procedure TFilePanel.AllowTabShellIcons;
begin
  if Assigned(FTabsBar) then
    FTabsBar.AllowShellIcons;
end;

procedure TFilePanel.SaveTabCursor(AIndex: Integer);
var
  Tab: TFileTab;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  if AIndex = FActiveTabIndex then
  begin
    if Assigned(FSelectionManager) then
    begin
      Tab.CursorIndex := FSelectionManager.CurrentIndex;
      Tab.AnchorIndex := FSelectionManager.AnchorIndex;
    end;
    Tab.CursorPath := PathFromVisualIndex(Tab, Tab.CursorIndex);
  end;
  FTabs[AIndex] := Tab;
end;

procedure TFilePanel.RestoreTabCursor(AIndex: Integer);
var
  Tab: TFileTab;
  Idx: Integer;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  if not Assigned(FSelectionManager) then
    Exit;
  Tab := FTabs[AIndex];
  Idx := IndexFromCursorPath(Tab);
  FSelectionManager.CurrentIndex := Idx;
  if Tab.AnchorIndex >= 0 then
    FSelectionManager.AnchorIndex := Tab.AnchorIndex
  else
    FSelectionManager.AnchorIndex := Idx;
end;

function TFilePanel.PathFromVisualIndex(const Tab: TFileTab; AVisual: Integer): string;
var
  Actual: Integer;
  ParentRow: Boolean;
begin
  Result := '';
  if FFilterReady and Assigned(Tab.Entries) and (Tab.Entries = GetCurrentEntries) then
  begin
    if HasParentDirectory and (AVisual = 0) then
      Exit(#1);
    if VisualToActual(AVisual, Actual) then
      Result := Tab.Entries[Actual].FullPath;
    Exit;
  end;
  ParentRow := ShowsParentRow(Tab.Path);
  if ParentRow and (AVisual = 0) then
  begin
    Result := #1;
    Exit;
  end;
  Actual := AVisual;
  if ParentRow then
    Dec(Actual);
  if Assigned(Tab.Entries) and (Actual >= 0) and (Actual < Tab.Entries.Count) then
    Result := Tab.Entries[Actual].FullPath;
end;

function TFilePanel.IndexFromCursorPath(const Tab: TFileTab): Integer;
var
  I, Total: Integer;
  ParentRow: Boolean;
  Name: string;
begin
  ParentRow := ShowsParentRow(Tab.Path);
  Total := 0;
  if Assigned(Tab.Entries) then
    Total := Tab.Entries.Count;
  if ParentRow then
    Inc(Total);

  if Tab.CursorPath = #1 then
  begin
    Result := 0;
    Exit;
  end;

  if (Tab.CursorPath <> '') and Assigned(Tab.Entries) then
  begin
    for I := 0 to Tab.Entries.Count - 1 do
      if SameText(Tab.Entries[I].FullPath, Tab.CursorPath) or
         SameText(ExcludeTrailingPathDelimiter(Tab.Entries[I].FullPath),
                  ExcludeTrailingPathDelimiter(Tab.CursorPath)) then
      begin
        Result := I;
        if ParentRow then
          Inc(Result);
        if FFilterReady and (Tab.Entries = GetCurrentEntries) then
        begin
          Result := VisualFromActual(I);
          if Result < 0 then
            Result := 0;
        end;
        Exit;
      end;
    Name := ExtractFileName(ExcludeTrailingPathDelimiter(Tab.CursorPath));
    if Name <> '' then
      for I := 0 to Tab.Entries.Count - 1 do
        if SameText(Tab.Entries[I].Name, Name) then
        begin
          Result := I;
          if ParentRow then
            Inc(Result);
          if FFilterReady and (Tab.Entries = GetCurrentEntries) then
          begin
            Result := VisualFromActual(I);
            if Result < 0 then
              Result := 0;
          end;
          Exit;
        end;
  end;

  Result := Tab.CursorIndex;
  if Result < 0 then
    Result := 0;
  if Total <= 0 then
    Result := 0
  else if Result >= Total then
    Result := Total - 1;
end;

procedure TFilePanel.WatchTab(AIndex: Integer);
var
  Tab: TFileTab;
  Watch, Arc, Inner: string;
begin
  if FDestroying or not FWatchEnabled then
    Exit;
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  if IsRemotePath(Tab.Path) then
  begin
    if Assigned(Tab.Watcher) then
      Tab.Watcher.Stop;
    Exit;
  end;
  if Tab.Loading or (Tab.LoadError <> '') then
    Exit;
  if not Assigned(Tab.Watcher) then
  begin
    Tab.Watcher := TDirWatcher.Create;
    Tab.Watcher.OnChange := HandleDirChange;
    FTabs[AIndex] := Tab;
  end;
  Watch := Tab.Path;
  if SplitArchivePath(Tab.Path, Arc, Inner) then
    Watch := ExcludeTrailingPathDelimiter(ExtractFilePath(Arc));
  Tab.Watcher.Watch(Watch);
end;

function TFilePanel.TabMatchesWatch(const ATabPath, AWatchPath: string): Boolean;
var
  Watch, Arc, Inner: string;
begin
  Watch := ExcludeTrailingPathDelimiter(AWatchPath);
  if SplitArchivePath(ATabPath, Arc, Inner) then
  begin
    Result := SameText(Watch, ExcludeTrailingPathDelimiter(Arc)) or
              SameText(Watch, ExcludeTrailingPathDelimiter(ExtractFilePath(Arc))) or
              SameText(Watch, ExcludeTrailingPathDelimiter(ATabPath));
    Exit;
  end;
  Result := SameText(Watch, ExcludeTrailingPathDelimiter(ATabPath));
end;

procedure TFilePanel.WatchCurrentPath;
begin
  WatchTab(FActiveTabIndex);
end;

procedure TFilePanel.HandleDirChange(const APath: string);
begin
  if FDestroying then
    Exit;
  if IsArchiveBusy then
  begin
    FRefreshPending := True;
    Exit;
  end;
  FDirChangePath := APath;
  if Assigned(FDirChangeTimer) then
  begin
    FDirChangeTimer.Enabled := False;
    FDirChangeTimer.Enabled := True;
  end
  else
    DirChangeTimerTick(nil);
end;

procedure TFilePanel.DirChangeTimerTick(Sender: TObject);
var
  I, InactiveLoadIdx: Integer;
  Tab: TFileTab;
  RefreshActive: Boolean;
  APath, Cur, Arc, Inner: string;
begin
  if Assigned(FDirChangeTimer) then
    FDirChangeTimer.Enabled := False;
  if FDestroying then
    Exit;
  APath := FDirChangePath;
  if IsArchiveBusy then
  begin
    FRefreshPending := True;
    Exit;
  end;

  RefreshActive := False;
  InactiveLoadIdx := -1;
  for I := 0 to FTabs.Count - 1 do
  begin
    if not TabMatchesWatch(FTabs[I].Path, APath) then
      Continue;
    if FTabs[I].SearchView then
      Continue;
    if I = FActiveTabIndex then
      RefreshActive := True
    else
    begin
      Tab := FTabs[I];
      Tab.Stale := True;
      FTabs[I] := Tab;
      if InactiveLoadIdx < 0 then
        InactiveLoadIdx := I;
    end;
  end;

  if RefreshActive then
  begin
    Cur := GetCurrentPathImpl;
    if not SplitArchivePath(Cur, Arc, Inner) then
    begin
      if IsRemotePath(Cur) then
      begin
        Refresh('', True);
        Exit;
      end;
      if (Cur <> '') and not TDirectory.Exists(Cur) and not IsVirtualShellPath(Cur) then
      begin
        if IsBrowsablePath(Cur) then
          Refresh('', True)
        else
          NavigateToParent;
        Exit;
      end;
    end;
    Refresh('', True);
    Exit;
  end;

  if (InactiveLoadIdx >= 0) and (ActiveLoadCount < 3) then
  begin
    CaptureTabSelection(InactiveLoadIdx, FKeepSelPaths, FKeepSelFocus);
    if (FKeepSelFocus = '') then
      FKeepSelFocus := FTabs[InactiveLoadIdx].CursorPath;
    StartDirLoadAt(InactiveLoadIdx, FTabs[InactiveLoadIdx].Path, '', True);
  end;
end;

procedure TFilePanel.CaptureTabSelection(AIndex: Integer; APaths: TStringList; out AFocus: string);
var
  Tab: TFileTab;
  I, VisualIdx, Actual: Integer;
  ParentRow: Boolean;
begin
  AFocus := '';
  if not Assigned(APaths) then
    Exit;
  APaths.Clear;
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  if not Assigned(Tab.Entries) then
    Exit;
  ParentRow := ShowsParentRow(Tab.Path);

  if AIndex = FActiveTabIndex then
  begin
    if Assigned(FSelectionManager) then
      AFocus := PathFromVisualIndex(Tab, FSelectionManager.CurrentIndex);
  end
  else if Tab.CursorPath <> '' then
    AFocus := Tab.CursorPath
  else
    AFocus := PathFromVisualIndex(Tab, Tab.CursorIndex);

  if Assigned(Tab.SelectedIndices) then
    for I := 0 to Tab.SelectedIndices.Count - 1 do
    begin
      VisualIdx := Tab.SelectedIndices[I];
      if ParentRow and (VisualIdx = 0) then
        Continue;
      Actual := VisualIdx;
      if ParentRow then
        Dec(Actual);
      if (Actual >= 0) and (Actual < Tab.Entries.Count) then
        APaths.Add(Tab.Entries[Actual].FullPath);
    end;
end;

procedure TFilePanel.RestoreTabSelection(AIndex: Integer; AEntries: uFileModel.TFileEntryList;
  APaths: TStringList; const AFocus: string; AApplyToManager: Boolean);
var
  Tab: TFileTab;
  I, VisualIdx: Integer;
  ParentRow: Boolean;
begin
  if not Assigned(AEntries) then
    Exit;
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  Tab := FTabs[AIndex];
  ParentRow := ShowsParentRow(Tab.Path);
  if Assigned(Tab.SelectedIndices) then
  begin
    Tab.SelectedIndices.Clear;
    if Assigned(APaths) then
      for I := 0 to AEntries.Count - 1 do
        if APaths.IndexOf(AEntries[I].FullPath) >= 0 then
        begin
          VisualIdx := I;
          if ParentRow then
            Inc(VisualIdx);
          Tab.SelectedIndices.Add(VisualIdx);
        end;
  end;

  if AFocus <> '' then
  begin
    Tab.CursorPath := AFocus;
    Tab.CursorIndex := IndexFromCursorPath(Tab);
  end;
  FTabs[AIndex] := Tab;

  if AApplyToManager and Assigned(FSelectionManager) then
  begin
    if AFocus = #1 then
      FSelectionManager.CurrentIndex := 0
    else if AFocus <> '' then
      FSelectionManager.CurrentIndex := Tab.CursorIndex;
  end;
end;

procedure TFilePanel.ApplyLoadedList(const APath: string; List: uFileModel.TFileEntryList;
  const ASelectPath: string; AKeepSel: Boolean;
  ASelPaths: TStringList; const AFocus: string; APartial: Boolean);
var
  I, TargetIdx: Integer;
  Tab: TFileTab;
  Active: Boolean;
  Focus: string;
begin
  if List = nil then
    Exit;
  if FDestroying then
  begin
    List.Free;
    Exit;
  end;

  TargetIdx := -1;
  for I := 0 to FTabs.Count - 1 do
    if SameDirHistoryPath(FTabs[I].Path, APath) then
    begin
      if I = FActiveTabIndex then
      begin
        TargetIdx := I;
        Break;
      end;
      if TargetIdx < 0 then
        TargetIdx := I;
    end;

  if TargetIdx < 0 then
  begin
    List.Free;
    Exit;
  end;

  Tab := FTabs[TargetIdx];
  UpdateLongestType(List);
  if APartial then
    SortEntries(List, sfName, True)
  else
    SortEntries(List, Tab.SortField, Tab.SortAsc);

  if Assigned(Tab.Entries) and (Tab.Entries <> List) and
     (Tab.Entries.Count > 0) and FileListsEquivalent(Tab.Entries, List) then
  begin
    List.Free;
    Tab.Loaded := True;
    Tab.Stale := False;
    FTabs[TargetIdx] := Tab;
    if (TargetIdx = FActiveTabIndex) and Assigned(FOnListReady) and not FListReadyFired then
    begin
      FListReadyFired := True;
      FOnListReady(Self);
    end;
    if TargetIdx = FActiveTabIndex then
    begin
      if ASelectPath <> '' then
      begin
        FFilterReady := False;
        if Assigned(FFilterMap) then
          FFilterMap.Clear;
        ApplyCursorAfterLoad(Tab.Entries, ASelectPath, False);
        if FNameFilter <> '' then
          CommitNameFilter(False)
        else
        begin
          KeepFocusVisible;
          InvalidateView;
        end;
      end;
      NotifyCursorChange;
      RefreshThumbs;
    end;
    Exit;
  end;

  if Assigned(Tab.Entries) and (Tab.Entries <> List) then
    Tab.Entries.Free;
  Tab.Entries := List;
  Tab.Loaded := True;
  Tab.Stale := False;
  FTabs[TargetIdx] := Tab;
  if TargetIdx = FActiveTabIndex then
  begin
    FFilterReady := False;
    if Assigned(FFilterMap) then
      FFilterMap.Clear;
  end;

  Active := TargetIdx = FActiveTabIndex;
  Focus := AFocus;
  if (Focus = '') and (ASelectPath <> '') then
    Focus := ASelectPath;

  if AKeepSel then
    RestoreTabSelection(TargetIdx, List, ASelPaths, Focus, Active)
  else if Assigned(Tab.SelectedIndices) then
    Tab.SelectedIndices.Clear;

  if Active then
  begin
    ApplyCursorAfterLoad(List, ASelectPath, AKeepSel);
    if FNameFilter <> '' then
      CommitNameFilter(False)
    else
    begin
      UpdateStatusText;
      RebuildContent;
      KeepFocusVisible;
    end;
    NotifyCursorChange;
    if not APartial then
      RefreshThumbs;
    if Assigned(FOnListReady) and not FListReadyFired then
    begin
      FListReadyFired := True;
      FOnListReady(Self);
    end;
    if (not APartial) and Assigned(GlobalIconCache) and
       not IsRemotePath(APath) then
      GlobalIconCache.PrefetchTypes(List,
        SelectIconBucket(CurrentIconTarget), IconSceneScale);
    if Assigned(FThumbTimer) then
      FThumbTimer.Enabled := True;
    TThread.ForceQueue(nil,
      procedure
      begin
        if FDestroying then
          Exit;
        InvalidateView;
      end);
  end
  else
  begin
    Tab := FTabs[TargetIdx];
    if Focus <> '' then
      Tab.CursorPath := Focus;
    Tab.CursorIndex := IndexFromCursorPath(Tab);
    FTabs[TargetIdx] := Tab;
  end;
end;

procedure TFilePanel.CaptureSelection(APaths: TStringList; out AFocus: string);
begin
  CaptureTabSelection(FActiveTabIndex, APaths, AFocus);
end;

end.
