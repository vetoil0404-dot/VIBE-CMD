unit uFilePreview;

{
  Универсальный просмотр файла: картинки, PSD/PSB, вектор (превью), медиа,
  текст, шрифты, архивы, Office/PDF через IPreviewHandler.
  Один контрол — и для соседней панели (Ctrl+Q), и для окна F3.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IOUtils,
  System.StrUtils, System.Math, System.Generics.Collections, System.Rtti,
  {$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, Winapi.ShellAPI,
  Winapi.WebView2, FMX.Platform.Win,
  {$ENDIF}
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  FMX.Memo, FMX.Memo.Types, FMX.Forms, FMX.Dialogs, FMX.Edit,
  FMX.WebBrowser, FMX.Skia, System.Skia,
  uAppSettings, uThemeManager, uFluentChrome, uFileModel, UCoreEngine,
  uArchiveEngine,
  uSpreadsheetData, uSpreadsheetGrid, uCustomScrollbar,
  uDocumentData, uDocumentView, uPdfium, uPsdPreview, uMetaCache,
  uFluentComboBox, uTextCode, uCodeView, uImageSniff
  {$IFDEF MSWINDOWS}, uMpvPlayer{$ENDIF};

type
  TFilePreview = class(TRectangle)
  private
    FColors: TThemeColors;
    FPath: string;
    FPendingPath: string;
    FStampAge: TDateTime;
    FStampSize: Int64;
    FShowClose: Boolean;
    FOnClose: TNotifyEvent;
    FHeader: TRectangle;
    FTitle: TText;
    FKindText: TText;
    FBtnClose: TFluentButton;
    FMeta: TText;
    FBody: TLayout;
    FImgHost: TLayout;
    FImage: TImage;
    FImgUserZoom: Single;
    FImgPan: TPointF;
    FImgPanning: Boolean;
    FImgPanLast: TPointF;
    FMemo: TMemo;
    FInfo: TText;
    FFontSample: TText;
    FGrid: TSpreadsheetGrid;
    FBook: TSpreadWorkbook;
    FDocView: TDocumentView;
    FDoc: TDocDocument;
    FMemoVScroll: TCustomFileScrollbar;
    FMemoHScroll: TCustomFileScrollbar;
    FSheetBar: TLayout;
    FSheetCombo: TFluentComboBox;
    FDebounce: TTimer;
    FSyncTimer: TTimer;
    FCaptureKeys: Boolean;
    FDestroying: Boolean;
    FLoadGen: Integer;
    FPdf: TPdfiumDoc;
    FPdfPage: Integer;
    FSvgBox: TSkPaintBox;
    FSvgDom: ISkSVGDOM;
    FWeb: TWebBrowser;
    FHtmlModeBar: TLayout;
    FBtnHtmlPage: TFluentButton;
    FBtnHtmlSrc: TFluentButton;
    FHtmlShowSource: Boolean;
    FTextBar: TLayout;
    FBtnEnc: TFluentButton;
    FBtnSheets: TFluentButton;
    FBtnCode: TFluentButton;
    FBtnHi: TFluentButton;
    FBtnWrap: TFluentButton;
    FEncMenu: TFluentPopupMenu;
    FCodeView: TCodeView;
    FTextLines: TArray<string>;
    FTextEnc: TTextEncMode;
    FTextEncLabel: string;
    FTextTotal: Int64;
    FTextShown: Int64;
    FTextMaxCols: Integer;
    FTextCode: Boolean;
    FTextHi: Boolean;
    FTextWrap: Boolean;
    FTextExt: string;
    FTextJob: TObject;
    FSvgTemp: string;
    FAnim: TSkAnimatedImage;
    FFontMap: TPaintBox;
    FFontFace: string;
    FImgBar: TLayout;
    FImgWork: TBitmap;
    FBtnRotL: TFluentButton;
    FBtnRotR: TFluentButton;
    FBtnResize: TFluentButton;
    FBtnSaveAs: TFluentButton;
    FBtnFit: TFluentButton;
    FBtn100: TFluentButton;
    FBtnFlipH: TFluentButton;
    FBtnFlipV: TFluentButton;
    FBtnCrop: TFluentButton;
    FBtnIco: TFluentButton;
    FImgDirty: Boolean;
    FSvgZoom: Single;
    FSvgPan: TPointF;
    FPdfZoom: Single;
    FSig: TImageSig;
    FSigBar: TLayout;
    FSigText: TText;
    FBtnSigRename: TFluentButton;
    FIcoBar: TLayout;
    FIcoFrames: TObjectList<TBitmap>;
    FIcoIndex: Integer;
    FCropping: Boolean;
    FCropA, FCropB: TPointF;
    FCropDrag: Boolean;
    FCropPaint: TPaintBox;
    FToast: TText;
    FToastTimer: TTimer;
    FSizeBox: TLayout;
    FSizeW: TEdit;
    FSizeH: TEdit;
    FSizeLock: TCheckBox;
    FSizeRatio: Single;
    FOnDiskChanged: TNotifyEvent;
    FMediaBar: TLayout;
    FBtnPlay: TFluentButton;
    FTimeText: TText;
    FSeekBox: TPaintBox;
    FBtnSaveClip: TFluentButton;
    FWaveBox: TPaintBox;
    FIsAudio: Boolean;
    FIsVideo: Boolean;
    FMediaDur: Double;
    FMediaPos: Double;
    FTrimA: Double;
    FTrimB: Double;
    FWave: TArray<Single>;
    FSeekDrag: Integer;
    FExporting: Boolean;
    FMediaPaused: Boolean;
    FMediaClockMs: Cardinal;
    FPosHoldUntil: Cardinal;
    {$IFDEF MSWINDOWS}
    FHostWnd: HWND;
    FHandler: IPreviewHandler;
    FUsingNative: Boolean;
    FMpv: TMpvSession;
    FUsingMpv: Boolean;
    {$ENDIF}
    procedure BuildUI;
    procedure CloseClick(Sender: TObject);
    procedure DebounceTick(Sender: TObject);
    procedure SyncTick(Sender: TObject);
    procedure DoLoad(const APath: string);
    procedure HideViewers;
    procedure ShowInfo(const AText: string);
    procedure ShowMeta(const APath: string);
    function ClassifyExt(const AExt: string): Integer;
    function LooksLikeText(const APath: string): Boolean;
    function LoadAsImage(const APath: string): Boolean;
    function LoadAsText(const APath: string): Boolean;
    function LoadAsMedia(const APath: string): Boolean;
    function LoadAsFont(const APath: string): Boolean;
    function LoadAsArchive(const APath: string): Boolean;
    function LoadAsThumb(const APath: string): Boolean;
    function LoadAsHex(const APath: string): Boolean;
    function LoadAsSpreadsheet(const APath: string): Boolean;
    function LoadAsDocument(const APath: string): Boolean;
    function LoadAsPdf(const APath: string): Boolean;
    function LoadAsSkiaImage(const APath: string): Boolean;
    function LoadAsAnimated(const APath: string): Boolean;
    function AnimIsPlaying: Boolean;
    procedure StopAnim;
    procedure EnsureAnim;
    function LoadAsHtmlBrowser(const APath: string): Boolean;
    function IsHtmlExt(const AExt: string): Boolean;
    procedure ShowHtmlMode(AShow: Boolean);
    procedure ShowTextChrome(AShow: Boolean);
    procedure LayoutTextBar;
    procedure StartTextLoad(const APath: string);
    procedure AcceptTextLoad(AJob: TObject);
    procedure ShowTextModel;
    procedure UpdateTextStatus;
    procedure TextSheetsClick(Sender: TObject);
    procedure TextCodeClick(Sender: TObject);
    procedure TextHiClick(Sender: TObject);
    procedure TextWrapClick(Sender: TObject);
    procedure TextEncClick(Sender: TObject);
    procedure EncUtf8Click(Sender: TObject);
    procedure EncAcpClick(Sender: TObject);
    procedure Enc16Click(Sender: TObject);
    procedure TextStatus(Sender: TObject);
    procedure UpdateHtmlModeButtons;
    procedure HtmlPageClick(Sender: TObject);
    procedure HtmlSourceClick(Sender: TObject);
    procedure WebShouldLoad(Sender: TObject; const AURL: string; var ACancel: Boolean);
    procedure WebFinished(Sender: TObject);
    function FileUriForBrowser(const APath: string): string;
    function HtmlPreviewUrl(const APath: string): string;
    function HtmlNavAllowed(const AURL: string): Boolean;
    function MapHtmlFolder(const AFolder: string): Boolean;
    procedure CleanupSvgTemp;
    procedure EnsureWebBrowser;
    procedure HideSvgWeb;
    function WaitWebEngine(ATimeoutMs: Cardinal): TWindowsActiveEngine;
    function WbLoadHtml(const AHtml: string): Boolean;
    {$IFDEF MSWINDOWS}
    function WbLoadHtmlIE(const AHtml: string): Boolean;
    {$ENDIF}
    procedure PaintSvg(Sender: TObject; const ACanvas: ISkCanvas;
      const ADest: TRectF; const AOpacity: Single);
    procedure ApplySpreadsheet(ABook: TSpreadWorkbook);
    procedure ApplyDocument(ADoc: TDocDocument);
    procedure StartHeavyLoad(const APath: string; AKind: Integer);
    procedure ShowPdfPage(AIndex: Integer; AResetView: Boolean = True);
    procedure PaintFontMap(Sender: TObject; Canvas: TCanvas);
    procedure ImgRotate(AClockwise: Boolean);
    procedure ImgRotLClick(Sender: TObject);
    procedure ImgRotRClick(Sender: TObject);
    procedure ImgResizeClick(Sender: TObject);
    procedure ImgSaveAsClick(Sender: TObject);
    function SaveSvgPdf(const APath: string): Boolean;
    procedure ImgFitClick(Sender: TObject);
    procedure Img100Click(Sender: TObject);
    procedure ImgFlipClick(Sender: TObject);
    procedure ImgCropClick(Sender: TObject);
    procedure ImgIcoClick(Sender: TObject);
    procedure IcoFrameClick(Sender: TObject);
    procedure SigRenameClick(Sender: TObject);
    procedure SizeLockChange(Sender: TObject);
    procedure SizeOkClick(Sender: TObject);
    procedure SizeCancelClick(Sender: TObject);
    procedure CropPaint(Sender: TObject; Canvas: TCanvas);
    procedure CropMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure CropMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure CropMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ToastTick(Sender: TObject);
    procedure ShowToast(const AText: string);
    procedure MarkImgDirty;
    procedure DropDirtyWork;
    procedure ShowSigBanner(ASig: TImageSig);
    procedure HideSigBanner;
    procedure ClearIcoFrames;
    procedure ShowIcoStrip(const APath: string);
    procedure ApplyIcoFrame(AIndex: Integer);
    procedure CancelCrop;
    procedure ApplyCrop;
    procedure SvgWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure ShowImageTools(AShow: Boolean);
    procedure ShowRasterImage(AResetView: Boolean = True);
    function ImgViewActive: Boolean;
    procedure ResetImgView;
    procedure ClampImgPan(AHostW, AHostH, ADw, ADh: Single);
    procedure ApplyImgView;
    procedure ImgMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure ImgMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ImgMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure ImgMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure EnsureWorkBitmap;
    procedure ShowMediaChrome(AAudio: Boolean);
    procedure HideMediaChrome;
    procedure MediaPlayClick(Sender: TObject);
    procedure MediaSaveClick(Sender: TObject);
    procedure PaintWave(Sender: TObject; Canvas: TCanvas);
    procedure PaintSeek(Sender: TObject; Canvas: TCanvas);
    procedure SeekMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure SeekMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure SeekMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure UpdateMediaHud;
    function XToMediaTime(X, AWidth: Single): Double;
    {$IFDEF MSWINDOWS}
    function LoadNativePreview(const APath: string): Boolean;
    procedure UnloadNative;
    procedure EnsureHostWnd;
    procedure SyncHostWnd;
    procedure HideHostWnd;
    procedure StopMpv;
    function StartMpv(const APath: string; AVideo: Boolean): Boolean;
    {$ENDIF}
    procedure SheetComboChange(Sender: TObject);
    procedure SetShowClose(AValue: Boolean);
    procedure MemoViewportChange(Sender: TObject; const OldViewportPosition,
      NewViewportPosition: TPointF; const ContentSizeChanged: Boolean);
    procedure PreviewBodyResize(Sender: TObject);
    procedure SyncMemoScroll;
    procedure HeaderMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFile(const APath: string);
    procedure ClearPreview;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure FocusViewer;
    function HasKeyboardFocus: Boolean;
    property FilePath: string read FPath;
    property ShowCloseButton: Boolean read FShowClose write SetShowClose;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property CaptureKeys: Boolean read FCaptureKeys write FCaptureKeys;
    property OnDiskChanged: TNotifyEvent read FOnDiskChanged write FOnDiskChanged;
    function HandleImageKey(var Key: Word; Shift: TShiftState): Boolean;
  end;

implementation

uses
  System.Zip, uThumbCache, System.Variants
  {$IFDEF MSWINDOWS}, Winapi.ShLwApi, SHDocVw, Winapi.EdgeUtils{$ENDIF};

type
  TTextLoadJob = class
  public
    Preview: TFilePreview;
    Path: string;
    Gen: Integer;
    Mode: TTextEncMode;
    Lines: TArray<string>;
    EncLabel: string;
    Total: Int64;
    Shown: Int64;
    MaxCols: Integer;
    Ok: Boolean;
    procedure Execute;
    procedure Apply;
  end;

const
  PK_OTHER   = 0;
  PK_IMAGE   = 1;
  PK_TEXT    = 2;
  PK_MEDIA   = 3;
  PK_FONT    = 4;
  PK_ARCHIVE = 5;
  PK_DOC     = 6;
  PK_TABLE   = 7;
  PK_PDF     = 8;

  MAX_TEXT_BYTES = 512 * 1024;
  MAX_HEX_BYTES  = 64 * 1024;

{$IFDEF MSWINDOWS}
const
  PreviewHandlerIID = '{8895B1C6-B41F-4C1C-A562-0D564250836F}';
  FR_PRIVATE = $10;

type
  IPreviewHandler = interface(IUnknown)
    ['{8895B1C6-B41F-4C1C-A562-0D564250836F}']
    function SetWindow(hwnd: HWND; var prc: TRect): HResult; stdcall;
    function SetRect(var prc: TRect): HResult; stdcall;
    function DoPreview: HResult; stdcall;
    function Unload: HResult; stdcall;
    function SetFocus: HResult; stdcall;
    function QueryFocus(out phwnd: HWND): HResult; stdcall;
    function TranslateAccelerator(var pmsg: TMsg): HResult; stdcall;
  end;

  IInitializeWithFile = interface(IUnknown)
    ['{B7D14566-0509-4CCE-A71F-0A554233BD9B}']
    function Initialize(pszFilePath: PWideChar; grfMode: DWORD): HResult; stdcall;
  end;

  IInitializeWithStream = interface(IUnknown)
    ['{B824B49D-22AC-4161-AC8A-9916E8FA3FFC}']
    function Initialize(const pstream: IStream; grfMode: DWORD): HResult; stdcall;
  end;

  IInitializeWithItem = interface(IUnknown)
    ['{7F73BE3F-FB79-493C-A6C7-7EE14E245841}']
    function Initialize(const psi: IShellItem; grfMode: DWORD): HResult; stdcall;
  end;

function GetFontResourceInfoW(lpszFilename: PWideChar; var cbBuffer: DWORD;
  lpBuffer: Pointer; dwQueryType: DWORD): BOOL; stdcall;
  external 'gdi32.dll' name 'GetFontResourceInfoW';
{$ENDIF}

function ExtIn(const AExt: string; const AList: array of string): Boolean;
var
  S: string;
begin
  for S in AList do
    if AExt = S then
      Exit(True);
  Result := False;
end;

function IsExcelExt(const AExt: string): Boolean;
begin
  Result := ExtIn(LowerCase(AExt), ['.xls', '.xlsx', '.xlsm', '.xlsb',
    '.xlt', '.xltx', '.xltm', '.xlam']);
end;

function DetectEncoding(const Buf: TBytes; out BomLen: Integer): TEncoding;
begin
  BomLen := 0;
  Result := TEncoding.UTF8;
  if (Length(Buf) >= 3) and (Buf[0] = $EF) and (Buf[1] = $BB) and (Buf[2] = $BF) then
  begin
    Result := TEncoding.UTF8;
    BomLen := 3;
  end
  else if (Length(Buf) >= 2) and (Buf[0] = $FF) and (Buf[1] = $FE) then
  begin
    Result := TEncoding.Unicode;
    BomLen := 2;
  end
  else if (Length(Buf) >= 2) and (Buf[0] = $FE) and (Buf[1] = $FF) then
  begin
    Result := TEncoding.BigEndianUnicode;
    BomLen := 2;
  end
  else
    Result := TEncoding.UTF8;
end;

constructor TFilePreview.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := GetThemeColors(atSystem);
  Align := TAlignLayout.Client;
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;
  ClipChildren := True;
  HitTest := True;
  CanFocus := True;
  TabStop := True;
  FShowClose := False;
  FCaptureKeys := False;
  FTextHi := True;
  FTextWrap := False;
  FTextEnc := temAuto;
  FTextEncLabel := 'UTF-8';
  FImgUserZoom := 1;
  FSvgZoom := 1;
  FPdfZoom := 1;
  FIcoFrames := TObjectList<TBitmap>.Create(True);
  FImgPan := TPointF.Zero;
  FImgPanning := False;
  BuildUI;
  FDestroying := False;
  FLoadGen := 0;
  FPdfPage := 0;
  FDebounce := TTimer.Create(Self);
  FDebounce.Interval := 140;
  FDebounce.Enabled := False;
  FDebounce.OnTimer := DebounceTick;
  FSyncTimer := TTimer.Create(Self);
  FSyncTimer.Interval := 40;
  FSyncTimer.Enabled := False;
  FSyncTimer.OnTimer := SyncTick;
  ApplyTheme(FColors);
end;

destructor TFilePreview.Destroy;
begin
  FDestroying := True;
  Inc(FLoadGen);
  FreeAndNil(FIcoFrames);
  if FTextJob <> nil then
  begin
    TTextLoadJob(FTextJob).Preview := nil;
    FTextJob := nil;
  end;
  FSvgDom := nil;
  CleanupSvgTemp;
  HideSvgWeb;
  FreeAndNil(FMemoVScroll);
  FreeAndNil(FMemoHScroll);
  FreeAndNil(FImgWork);
  FreeAndNil(FPdf);
  ClearPreview;
  {$IFDEF MSWINDOWS}
  StopMpv;
  FreeAndNil(FMpv);
  if FHostWnd <> 0 then
  begin
    DestroyWindow(FHostWnd);
    FHostWnd := 0;
  end;
  {$ENDIF}
  inherited;
end;

procedure TFilePreview.BuildUI;
begin
  FHeader := TRectangle.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := TAlignLayout.Top;
  FHeader.Height := 36;
  FHeader.Stroke.Kind := TBrushKind.None;
  FHeader.Fill.Kind := TBrushKind.Solid;
  FHeader.OnMouseDown := HeaderMouseDown;

  FBtnClose := CreateFluentButton(Self, FHeader, '', '✕', fbkSubtle, 36, CloseClick);
  FBtnClose.Align := TAlignLayout.Right;
  FBtnClose.Visible := False;

  FKindText := TText.Create(Self);
  FKindText.Parent := FHeader;
  FKindText.Align := TAlignLayout.Right;
  FKindText.Width := 110;
  FKindText.HitTest := False;
  ApplyFluentText(FKindText, 11, False);
  FKindText.TextSettings.HorzAlign := TTextAlign.Trailing;
  FKindText.TextSettings.VertAlign := TTextAlign.Center;
  FKindText.Margins.Right := 8;

  FHtmlModeBar := TLayout.Create(Self);
  FHtmlModeBar.Parent := FHeader;
  FHtmlModeBar.Align := TAlignLayout.Right;
  FHtmlModeBar.Width := 176;
  FHtmlModeBar.Visible := False;
  FHtmlModeBar.HitTest := True;
  FBtnHtmlPage := CreateFluentButton(Self, FHtmlModeBar, '', 'Страница', fbkSubtle,
    88, HtmlPageClick);
  FBtnHtmlPage.Align := TAlignLayout.Left;
  FBtnHtmlPage.Width := 88;
  FBtnHtmlSrc := CreateFluentButton(Self, FHtmlModeBar, '', 'Исходник', fbkSubtle,
    88, HtmlSourceClick);
  FBtnHtmlSrc.Align := TAlignLayout.Client;

  FTextBar := TLayout.Create(Self);
  FTextBar.Parent := FHeader;
  FTextBar.Align := TAlignLayout.Right;
  FTextBar.Width := 360;
  FTextBar.Visible := False;
  FTextBar.HitTest := True;
  FBtnEnc := CreateFluentButton(Self, FTextBar, '', 'UTF-8', fbkSubtle, 72, TextEncClick);
  FBtnEnc.Align := TAlignLayout.Left;
  FBtnSheets := CreateFluentButton(Self, FTextBar, '', 'Листы', fbkSubtle, 64, TextSheetsClick);
  FBtnSheets.Align := TAlignLayout.Left;
  FBtnCode := CreateFluentButton(Self, FTextBar, '', 'Код', fbkSubtle, 52, TextCodeClick);
  FBtnCode.Align := TAlignLayout.Left;
  FBtnHi := CreateFluentButton(Self, FTextBar, '', 'Подсветка', fbkSubtle, 88, TextHiClick);
  FBtnHi.Align := TAlignLayout.Left;
  FBtnWrap := CreateFluentButton(Self, FTextBar, '', 'Перенос', fbkSubtle, 78, TextWrapClick);
  FBtnWrap.Align := TAlignLayout.Left;
  FEncMenu := TFluentPopupMenu.Create(Self);
  FEncMenu.Parent := Self;

  FTitle := TText.Create(Self);
  FTitle.Parent := FHeader;
  FTitle.Align := TAlignLayout.Client;
  FTitle.HitTest := False;
  FTitle.Margins.Rect := TRectF.Create(12, 0, 8, 0);
  ApplyFluentText(FTitle, 13, True);
  FTitle.TextSettings.HorzAlign := TTextAlign.Leading;
  FTitle.TextSettings.VertAlign := TTextAlign.Center;
  FTitle.TextSettings.Trimming := TTextTrimming.Character;
  FTitle.WordWrap := False;
  FTitle.Text := 'Просмотр';

  FMeta := TText.Create(Self);
  FMeta.Parent := Self;
  FMeta.Align := TAlignLayout.Bottom;
  FMeta.Height := 22;
  FMeta.HitTest := False;
  FMeta.Margins.Rect := TRectF.Create(12, 0, 12, 4);
  ApplyFluentText(FMeta, 11, False);
  FMeta.TextSettings.HorzAlign := TTextAlign.Leading;
  FMeta.TextSettings.VertAlign := TTextAlign.Center;
  FMeta.TextSettings.Trimming := TTextTrimming.Character;
  FMeta.WordWrap := False;

  FBody := TLayout.Create(Self);
  FBody.Parent := Self;
  FBody.Align := TAlignLayout.Client;
  FBody.Margins.Rect := TRectF.Create(8, 4, 8, 4);

  FImgHost := TLayout.Create(Self);
  FImgHost.Parent := FBody;
  FImgHost.Align := TAlignLayout.Client;
  FImgHost.ClipChildren := True;
  FImgHost.HitTest := True;
  FImgHost.Visible := False;
  FImgHost.OnMouseWheel := ImgMouseWheel;
  FImgHost.OnMouseDown := ImgMouseDown;
  FImgHost.OnMouseMove := ImgMouseMove;
  FImgHost.OnMouseUp := ImgMouseUp;
  FImage := TImage.Create(Self);
  FImage.Parent := FImgHost;
  FImage.Align := TAlignLayout.None;
  FImage.WrapMode := TImageWrapMode.Stretch;
  FImage.Visible := False;
  FImage.HitTest := False;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := FBody;
  FMemo.Align := TAlignLayout.Client;
  FMemo.ReadOnly := True;
  FMemo.WordWrap := False;
  FMemo.ShowScrollBars := False;
  FMemo.ControlType := TControlType.Styled;
  FMemo.Visible := False;
  FMemo.OnViewportPositionChange := MemoViewportChange;
  FBody.OnResize := PreviewBodyResize;
  FMemoVScroll := TCustomFileScrollbar.Create(FBody, FMemo);
  FMemoHScroll := TCustomFileScrollbar.Create(FBody, FMemo);
  FMemoHScroll.Orientation := TOrientation.Horizontal;

  FFontSample := TText.Create(Self);
  FFontSample.Parent := FBody;
  FFontSample.Align := TAlignLayout.Client;
  FFontSample.HitTest := False;
  FFontSample.Visible := False;
  FFontSample.TextSettings.HorzAlign := TTextAlign.Center;
  FFontSample.TextSettings.VertAlign := TTextAlign.Center;
  FFontSample.WordWrap := True;

  FInfo := TText.Create(Self);
  FInfo.Parent := FBody;
  FInfo.Align := TAlignLayout.Client;
  FInfo.HitTest := False;
  ApplyFluentText(FInfo, 13, False);
  FInfo.TextSettings.HorzAlign := TTextAlign.Center;
  FInfo.TextSettings.VertAlign := TTextAlign.Center;
  FInfo.WordWrap := True;
  FInfo.Visible := False;

  FSheetBar := TLayout.Create(Self);
  FSheetBar.Parent := FBody;
  FSheetBar.Align := TAlignLayout.Top;
  FSheetBar.Height := 28;
  FSheetBar.Visible := False;
  FSheetCombo := TFluentComboBox.Create(Self);
  FSheetCombo.Parent := FSheetBar;
  FSheetCombo.Align := TAlignLayout.Left;
  FSheetCombo.Width := 220;
  FSheetCombo.DropListOnly := True;
  FSheetCombo.Suggest := False;
  FSheetCombo.OnSelChange := SheetComboChange;
  FGrid := TSpreadsheetGrid.Create(Self);
  FGrid.Parent := FBody;
  FGrid.Visible := False;
  FDocView := TDocumentView.Create(Self);
  FDocView.Parent := FBody;
  FDocView.Visible := False;
  FDocView.OnStatus := TextStatus;
  FCodeView := TCodeView.Create(Self);
  FCodeView.Parent := FBody;
  FCodeView.Visible := False;
  FCodeView.OnStatus := TextStatus;

  FSvgBox := TSkPaintBox.Create(Self);
  FSvgBox.Parent := FBody;
  FSvgBox.Align := TAlignLayout.Client;
  FSvgBox.Visible := False;
  FSvgBox.HitTest := False;
  FSvgBox.OnDraw := PaintSvg;
  FSvgBox.OnMouseWheel := SvgWheel;

  FSigBar := TLayout.Create(Self);
  FSigBar.Parent := FBody;
  FSigBar.Align := TAlignLayout.Top;
  FSigBar.Height := 32;
  FSigBar.Visible := False;
  FSigText := TText.Create(Self);
  FSigText.Parent := FSigBar;
  FSigText.Align := TAlignLayout.Client;
  FSigText.HitTest := False;
  ApplyFluentText(FSigText, 12, False);
  FSigText.TextSettings.VertAlign := TTextAlign.Center;
  FSigText.Margins.Left := 8;
  FBtnSigRename := CreateFluentButton(Self, FSigBar, '', 'Переименовать', fbkSubtle,
    120, SigRenameClick);
  FBtnSigRename.Align := TAlignLayout.Right;

  FIcoBar := TLayout.Create(Self);
  FIcoBar.Parent := FBody;
  FIcoBar.Align := TAlignLayout.Bottom;
  FIcoBar.Height := 62;
  FIcoBar.Visible := False;

  FCropPaint := TPaintBox.Create(Self);
  FCropPaint.Parent := FImgHost;
  FCropPaint.Align := TAlignLayout.Client;
  FCropPaint.Visible := False;
  FCropPaint.OnPaint := CropPaint;
  FCropPaint.OnMouseDown := CropMouseDown;
  FCropPaint.OnMouseMove := CropMouseMove;
  FCropPaint.OnMouseUp := CropMouseUp;

  FToast := TText.Create(Self);
  FToast.Parent := Self;
  FToast.Align := TAlignLayout.Bottom;
  FToast.Height := 26;
  FToast.Visible := False;
  FToast.HitTest := False;
  ApplyFluentText(FToast, 13, False);
  FToast.TextSettings.HorzAlign := TTextAlign.Center;
  FToast.TextSettings.VertAlign := TTextAlign.Center;
  FToastTimer := TTimer.Create(Self);
  FToastTimer.Enabled := False;
  FToastTimer.Interval := 2000;
  FToastTimer.OnTimer := ToastTick;

  FAnim := nil;

  FFontMap := TPaintBox.Create(Self);
  FFontMap.Parent := FBody;
  FFontMap.Align := TAlignLayout.Client;
  FFontMap.Visible := False;
  FFontMap.OnPaint := PaintFontMap;

  FImgBar := TLayout.Create(Self);
  FImgBar.Parent := FBody;
  FImgBar.Align := TAlignLayout.Bottom;
  FImgBar.Height := 34;
  FImgBar.Visible := False;
  FBtnRotL := CreateFluentButton(Self, FImgBar, '↺', '90°', fbkSubtle, 72, ImgRotLClick);
  FBtnRotL.Align := TAlignLayout.Left;
  FBtnRotR := CreateFluentButton(Self, FImgBar, '↻', '90°', fbkSubtle, 72, ImgRotRClick);
  FBtnRotR.Align := TAlignLayout.Left;
  FBtnResize := CreateFluentButton(Self, FImgBar, '', 'Размер', fbkSubtle, 88, ImgResizeClick);
  FBtnResize.Align := TAlignLayout.Left;
  FBtnSaveAs := CreateFluentButton(Self, FImgBar, '', 'Сохранить как', fbkSubtle, 130, ImgSaveAsClick);
  FBtnSaveAs.Align := TAlignLayout.Left;
  FBtnFit := CreateFluentButton(Self, FImgBar, '', 'Fit', fbkSubtle, 52, ImgFitClick);
  FBtnFit.Align := TAlignLayout.Left;
  FBtn100 := CreateFluentButton(Self, FImgBar, '', '100%', fbkSubtle, 58, Img100Click);
  FBtn100.Align := TAlignLayout.Left;
  FBtnFlipH := CreateFluentButton(Self, FImgBar, '', '↔', fbkSubtle, 44, ImgFlipClick);
  FBtnFlipH.Align := TAlignLayout.Left;
  FBtnFlipH.Tag := 0;
  FBtnFlipV := CreateFluentButton(Self, FImgBar, '', '↕', fbkSubtle, 44, ImgFlipClick);
  FBtnFlipV.Align := TAlignLayout.Left;
  FBtnFlipV.Tag := 1;
  FBtnCrop := CreateFluentButton(Self, FImgBar, '', 'Кроп', fbkSubtle, 64, ImgCropClick);
  FBtnCrop.Align := TAlignLayout.Left;
  FBtnIco := CreateFluentButton(Self, FImgBar, '', 'ICO', fbkSubtle, 52, ImgIcoClick);
  FBtnIco.Align := TAlignLayout.Left;

  FSizeBox := TLayout.Create(Self);
  FSizeBox.Parent := FBody;
  FSizeBox.Align := TAlignLayout.Bottom;
  FSizeBox.Height := 36;
  FSizeBox.Visible := False;
  FSizeW := TEdit.Create(Self);
  FSizeW.Parent := FSizeBox;
  FSizeW.Align := TAlignLayout.Left;
  FSizeW.Width := 72;
  FSizeW.OnChange := SizeLockChange;
  FSizeH := TEdit.Create(Self);
  FSizeH.Parent := FSizeBox;
  FSizeH.Align := TAlignLayout.Left;
  FSizeH.Width := 72;
  FSizeH.OnChange := SizeLockChange;
  FSizeLock := TCheckBox.Create(Self);
  FSizeLock.Parent := FSizeBox;
  FSizeLock.Align := TAlignLayout.Left;
  FSizeLock.Width := 110;
  FSizeLock.Text := 'Пропорции';
  FSizeLock.IsChecked := True;
  FSizeLock.OnChange := SizeLockChange;
  with CreateFluentButton(Self, FSizeBox, '', 'OK', fbkSubtle, 48, SizeOkClick) do
    Align := TAlignLayout.Left;
  with CreateFluentButton(Self, FSizeBox, '', 'Отмена', fbkSubtle, 72, SizeCancelClick) do
    Align := TAlignLayout.Left;

  FWaveBox := TPaintBox.Create(Self);
  FWaveBox.Parent := FBody;
  FWaveBox.Align := TAlignLayout.Client;
  FWaveBox.Visible := False;
  FWaveBox.HitTest := True;
  FWaveBox.AutoCapture := True;
  FWaveBox.OnPaint := PaintWave;
  FWaveBox.OnMouseDown := SeekMouseDown;
  FWaveBox.OnMouseMove := SeekMouseMove;
  FWaveBox.OnMouseUp := SeekMouseUp;

  FMediaBar := TLayout.Create(Self);
  FMediaBar.Parent := FBody;
  FMediaBar.Align := TAlignLayout.Bottom;
  FMediaBar.Height := 48;
  FMediaBar.Visible := False;
  FBtnPlay := CreateFluentButton(Self, FMediaBar, #$E768, 'Старт', fbkStandard, 96, MediaPlayClick);
  FBtnPlay.Align := TAlignLayout.Left;
  FTimeText := TText.Create(Self);
  FTimeText.Parent := FMediaBar;
  FTimeText.Align := TAlignLayout.Left;
  FTimeText.Width := 108;
  FTimeText.HitTest := False;
  ApplyFluentText(FTimeText, 12, False);
  FTimeText.TextSettings.HorzAlign := TTextAlign.Center;
  FTimeText.TextSettings.VertAlign := TTextAlign.Center;
  FTimeText.Text := '00:00 / 00:00';
  FBtnSaveClip := CreateFluentButton(Self, FMediaBar, '', 'Сохранить', fbkStandard, 118, MediaSaveClick);
  FBtnSaveClip.Align := TAlignLayout.Right;
  FSeekBox := TPaintBox.Create(Self);
  FSeekBox.Parent := FMediaBar;
  FSeekBox.Align := TAlignLayout.Client;
  FSeekBox.HitTest := True;
  FSeekBox.AutoCapture := True;
  FSeekBox.OnPaint := PaintSeek;
  FSeekBox.OnMouseDown := SeekMouseDown;
  FSeekBox.OnMouseMove := SeekMouseMove;
  FSeekBox.OnMouseUp := SeekMouseUp;
end;

procedure TFilePreview.SetShowClose(AValue: Boolean);
begin
  FShowClose := AValue and False;
  if Assigned(FBtnClose) then
    FBtnClose.Visible := False;
end;

procedure TFilePreview.SyncMemoScroll;
begin
  if Assigned(FMemoVScroll) then
    FMemoVScroll.UpdateThumb;
  if Assigned(FMemoHScroll) then
    FMemoHScroll.UpdateThumb;
end;

procedure TFilePreview.MemoViewportChange(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF;
  const ContentSizeChanged: Boolean);
begin
  SyncMemoScroll;
end;

procedure TFilePreview.PreviewBodyResize(Sender: TObject);
begin
  if FDestroying or (csDestroying in ComponentState) then
    Exit;
  SyncMemoScroll;
  ApplyImgView;
  {$IFDEF MSWINDOWS}
  if FUsingNative or FUsingMpv then
  begin
    FSyncTimer.Enabled := False;
    FSyncTimer.Enabled := True;
  end;
  {$ENDIF}
end;

function TFilePreview.ImgViewActive: Boolean;
begin
  Result := Assigned(FImgHost) and Assigned(FImage) and FImgHost.Visible and
    FImage.Visible and Assigned(FImage.Bitmap) and
    (FImage.Bitmap.Width > 0) and (FImage.Bitmap.Height > 0);
end;

procedure TFilePreview.ResetImgView;
begin
  FImgUserZoom := 1;
  FImgPan := TPointF.Zero;
  if FImgPanning and Assigned(FImgHost) and Assigned(FImgHost.Root) and
      Assigned(FImgHost.Root.Captured) and (FImgHost.Root.Captured.GetObject = FImgHost) then
    FImgHost.Root.Captured := nil;
  FImgPanning := False;
end;

procedure TFilePreview.ShowRasterImage(AResetView: Boolean);
begin
  if Assigned(FImgHost) then
    FImgHost.Visible := True;
  if Assigned(FImage) then
    FImage.Visible := True;
  if AResetView then
    ResetImgView;
  ApplyImgView;
end;

procedure TFilePreview.ClampImgPan(AHostW, AHostH, ADw, ADh: Single);
var
  MaxX, MaxY: Single;
begin
  if ADw <= AHostW + 0.5 then
    FImgPan.X := 0
  else
  begin
    MaxX := (ADw - AHostW) / 2;
    FImgPan.X := EnsureRange(FImgPan.X, -MaxX, MaxX);
  end;
  if ADh <= AHostH + 0.5 then
    FImgPan.Y := 0
  else
  begin
    MaxY := (ADh - AHostH) / 2;
    FImgPan.Y := EnsureRange(FImgPan.Y, -MaxY, MaxY);
  end;
end;

procedure TFilePreview.ApplyImgView;
var
  HostW, HostH, ImgW, ImgH, Fit, Scale, Dw, Dh: Single;
begin
  if not ImgViewActive then
    Exit;
  HostW := FImgHost.Width;
  HostH := FImgHost.Height;
  if (HostW < 8) or (HostH < 8) then
    Exit;
  ImgW := FImage.Bitmap.Width;
  ImgH := FImage.Bitmap.Height;
  if (ImgW < 1) or (ImgH < 1) then
    Exit;
  Fit := Min(HostW / ImgW, HostH / ImgH);
  if Fit <= 0 then
    Exit;
  if FImgUserZoom < 0.2 then
    FImgUserZoom := 0.2;
  if FImgUserZoom > 32 then
    FImgUserZoom := 32;
  Scale := Fit * FImgUserZoom;
  Dw := ImgW * Scale;
  Dh := ImgH * Scale;
  ClampImgPan(HostW, HostH, Dw, Dh);
  FImage.Position.Point := TPointF.Create(
    (HostW - Dw) / 2 + FImgPan.X,
    (HostH - Dh) / 2 + FImgPan.Y);
  FImage.Width := Dw;
  FImage.Height := Dh;
  if (Dw > HostW + 0.5) or (Dh > HostH + 0.5) then
    FImgHost.Cursor := crSizeAll
  else
    FImgHost.Cursor := crDefault;
end;

procedure TFilePreview.ImgMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  HostW, HostH, ImgW, ImgH, Fit, OldZ, NewZ, OldDw, OldDh, NewDw, NewDh: Single;
  L, T, FracX, FracY: Single;
  Mouse: TPointF;
begin
  if not ImgViewActive or (WheelDelta = 0) then
    Exit;
  Handled := True;
  HostW := FImgHost.Width;
  HostH := FImgHost.Height;
  ImgW := FImage.Bitmap.Width;
  ImgH := FImage.Bitmap.Height;
  if (HostW < 8) or (HostH < 8) or (ImgW < 1) or (ImgH < 1) then
    Exit;
  Fit := Min(HostW / ImgW, HostH / ImgH);
  if Fit <= 0 then
    Exit;
  OldZ := FImgUserZoom;
  if OldZ < 0.2 then
    OldZ := 0.2;
  NewZ := OldZ * Power(1.2, WheelDelta / 120.0);
  if NewZ < 0.2 then
    NewZ := 0.2;
  if NewZ > 32 then
    NewZ := 32;
  if Abs(NewZ - 1) < 0.03 then
    NewZ := 1;
  OldDw := ImgW * Fit * OldZ;
  OldDh := ImgH * Fit * OldZ;
  L := (HostW - OldDw) / 2 + FImgPan.X;
  T := (HostH - OldDh) / 2 + FImgPan.Y;
  Mouse := FImgHost.ScreenToLocal(Screen.MousePos);
  if OldDw > 1 then
    FracX := (Mouse.X - L) / OldDw
  else
    FracX := 0.5;
  if OldDh > 1 then
    FracY := (Mouse.Y - T) / OldDh
  else
    FracY := 0.5;
  NewDw := ImgW * Fit * NewZ;
  NewDh := ImgH * Fit * NewZ;
  FImgUserZoom := NewZ;
  if Assigned(FPdf) then
  begin
    FPdfZoom := NewZ;
    ShowPdfPage(FPdfPage, False);
    Exit;
  end;
  FImgPan.X := Mouse.X - (HostW - NewDw) / 2 - FracX * NewDw;
  FImgPan.Y := Mouse.Y - (HostH - NewDh) / 2 - FracY * NewDh;
  if Abs(NewZ - 1) < 0.001 then
    FImgPan := TPointF.Zero;
  ApplyImgView;
end;

procedure TFilePreview.ImgMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FocusViewer;
  if not ImgViewActive or (Button <> TMouseButton.mbLeft) then
    Exit;
  if (FImage.Width <= FImgHost.Width + 0.5) and
     (FImage.Height <= FImgHost.Height + 0.5) then
    Exit;
  FImgPanning := True;
  FImgPanLast := TPointF.Create(X, Y);
  if Assigned(FImgHost.Root) then
    FImgHost.Root.Captured := FImgHost;
  FImgHost.Cursor := crSizeAll;
end;

procedure TFilePreview.ImgMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if not FImgPanning then
    Exit;
  FImgPan.X := FImgPan.X + (X - FImgPanLast.X);
  FImgPan.Y := FImgPan.Y + (Y - FImgPanLast.Y);
  FImgPanLast := TPointF.Create(X, Y);
  ApplyImgView;
end;

procedure TFilePreview.ImgMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if not FImgPanning then
    Exit;
  FImgPanning := False;
  if Assigned(FImgHost) and Assigned(FImgHost.Root) and
      Assigned(FImgHost.Root.Captured) and (FImgHost.Root.Captured.GetObject = FImgHost) then
    FImgHost.Root.Captured := nil;
  ApplyImgView;
end;

procedure TFilePreview.FocusViewer;
begin
  if Assigned(FDocView) and FDocView.Visible and FDocView.CanFocus then
    FDocView.SetFocus
  else if Assigned(FGrid) and FGrid.Visible and FGrid.CanFocus then
    FGrid.SetFocus
  else if Assigned(FCodeView) and FCodeView.Visible and FCodeView.CanFocus then
    FCodeView.SetFocus
  else if Assigned(FMemo) and FMemo.Visible and FMemo.CanFocus then
    FMemo.SetFocus
  else if FCaptureKeys and CanFocus then
    SetFocus;
end;

function TFilePreview.HasKeyboardFocus: Boolean;
var
  Form: TCommonCustomForm;
  Obj: TFmxObject;
begin
  Result := False;
  if not Visible or not ParentedVisible then
    Exit;
  if Assigned(Root) and (Root.GetObject is TCommonCustomForm) then
    Form := TCommonCustomForm(Root.GetObject)
  else
    Exit;
  if Form.Focused = nil then
    Exit;
  Obj := Form.Focused.GetObject;
  while Assigned(Obj) do
  begin
    if Obj = Self then
      Exit(True);
    Obj := Obj.Parent;
  end;
end;

procedure TFilePreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FocusViewer;
end;

procedure TFilePreview.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  if ImgViewActive then
  begin
    ImgMouseWheel(Self, Shift, WheelDelta, Handled);
    if Handled then
      Exit;
  end;
  inherited;
end;

procedure TFilePreview.HeaderMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FocusViewer;
end;

procedure TFilePreview.CloseClick(Sender: TObject);
begin
  if Assigned(FOnClose) then
    FOnClose(Self)
  else
    ClearPreview;
end;

procedure TFilePreview.LoadFile(const APath: string);
begin
  FPendingPath := APath;
  FDebounce.Enabled := False;
  { Пока крутится gif/webp, тикер Skia может глушить TTimer — грузим сразу. }
  if AnimIsPlaying then
    DoLoad(APath)
  else
    FDebounce.Enabled := True;
end;

procedure TFilePreview.DebounceTick(Sender: TObject);
begin
  FDebounce.Enabled := False;
  try
    DoLoad(FPendingPath);
  except
  end;
end;

procedure TFilePreview.SyncTick(Sender: TObject);
var
  NowMs: Cardinal;
  Dt: Double;
  EngPos: Double;
begin
  {$IFDEF MSWINDOWS}
  if FUsingNative or FUsingMpv then
    SyncHostWnd;
  if FUsingMpv and Assigned(FMpv) then
    FMpv.Pump;
  {$ENDIF}
  if FIsAudio or FIsVideo then
  begin
    NowMs := TThread.GetTickCount;
    if FMediaClockMs = 0 then
      FMediaClockMs := NowMs;
    Dt := (NowMs - FMediaClockMs) / 1000.0;
    FMediaClockMs := NowMs;
    if Dt < 0 then
      Dt := 0;
    if Dt > 0.25 then
      Dt := 0.25;
    if FMediaDur <= 0.05 then
    begin
{$IFDEF MSWINDOWS}
      if Assigned(FMpv) and FMpv.HasEngine then
        if FMpv.Duration > 0.05 then
          FMediaDur := FMpv.Duration;
{$ENDIF}
      if (FMediaDur <= 0.05) and (FPath <> '') then
        FMediaDur := ProbeMediaDuration(FPath);
      if (FMediaDur > 0.05) and (FTrimB <= 0.05) then
        FTrimB := FMediaDur;
    end;
    if FSeekDrag = 0 then
    begin
{$IFDEF MSWINDOWS}
      if Assigned(FMpv) and FMpv.HasEngine then
      begin
        EngPos := FMpv.Duration;
        if EngPos > 0.05 then
          FMediaDur := EngPos;
        if (FPosHoldUntil = 0) or (NowMs >= FPosHoldUntil) then
          FMediaPos := FMpv.Position;
        if (FMediaDur > 0.2) and (FMediaPos >= FMediaDur - 0.08) and
           ((FPosHoldUntil = 0) or (NowMs >= FPosHoldUntil)) then
          FMediaPaused := True;
      end
      else
{$ENDIF}
      if not FMediaPaused then
        FMediaPos := FMediaPos + Dt;
      if FTrimB > FTrimA + 0.05 then
      begin
        if FMediaPos < FTrimA then
          FMediaPos := FTrimA;
        if FMediaPos >= FTrimB then
        begin
          FMediaPos := FTrimB;
          FMediaPaused := True;
{$IFDEF MSWINDOWS}
          if Assigned(FMpv) then
            FMpv.SetPaused(True);
{$ENDIF}
        end;
      end
      else if (FMediaDur > 0) and (FMediaPos > FMediaDur) then
      begin
        FMediaPos := FMediaDur;
        FMediaPaused := True;
      end;
    end;
    UpdateMediaHud;
  end;
end;

procedure TFilePreview.ClearPreview;
begin
  if FImgDirty then
    ShowToast('не сохранено');
  FImgDirty := False;
  FDebounce.Enabled := False;
  FPath := '';
  FPendingPath := '';
  FStampAge := 0;
  FStampSize := 0;
  HideViewers;
  if Assigned(FTitle) then
    FTitle.Text := 'Просмотр';
  if Assigned(FKindText) then
    FKindText.Text := '';
  if Assigned(FMeta) then
    FMeta.Text := '';
end;

procedure TFilePreview.HideViewers;
begin
  {$IFDEF MSWINDOWS}
  StopMpv;
  UnloadNative;
  {$ENDIF}
  if Assigned(FImage) then
  begin
    try
      FImage.Bitmap.Assign(nil);
    except
    end;
    FImage.Visible := False;
  end;
  if Assigned(FImgHost) then
    FImgHost.Visible := False;
  ResetImgView;
  FSvgDom := nil;
  if Assigned(FSvgBox) then
    FSvgBox.Visible := False;
  HideSvgWeb;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := False;
  if FTextJob <> nil then
  begin
    TTextLoadJob(FTextJob).Preview := nil;
    FTextJob := nil;
  end;
  SetLength(FTextLines, 0);
  if Assigned(FTextBar) then
    FTextBar.Visible := False;
  if Assigned(FCodeView) then
  begin
    FCodeView.Visible := False;
    FCodeView.Clear;
  end;
  StopAnim;
  if Assigned(FFontMap) then
    FFontMap.Visible := False;
  ShowImageTools(False);
  CancelCrop;
  HideSigBanner;
  ClearIcoFrames;
  if Assigned(FSizeBox) then
    FSizeBox.Visible := False;
  FSvgZoom := 1;
  FSvgPan := TPointF.Zero;
  FPdfZoom := 1;
  HideMediaChrome;
  FreeAndNil(FImgWork);
  FreeAndNil(FPdf);
  if Assigned(FMemo) then
  begin
    FMemo.Lines.Clear;
    FMemo.Visible := False;
  end;
  if Assigned(FFontSample) then
    FFontSample.Visible := False;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  if Assigned(FGrid) then
  begin
    FGrid.Visible := False;
    FGrid.Clear;
  end;
  if Assigned(FDocView) then
  begin
    FDocView.Visible := False;
    FDocView.Clear;
  end;
  if Assigned(FSheetBar) then
    FSheetBar.Visible := False;
  if Assigned(FSheetCombo) then
    FSheetCombo.Items.Clear;
  FreeAndNil(FBook);
  FreeAndNil(FDoc);
  SyncMemoScroll;
end;

procedure TFilePreview.ShowInfo(const AText: string);
begin
  FInfo.Text := AText;
  FInfo.Visible := True;
end;

procedure TFilePreview.ShowMeta(const APath: string);
var
  Sz: Int64;
  When: TDateTime;
begin
  if (APath = '') or not (TFile.Exists(APath) or TDirectory.Exists(APath)) then
  begin
    FMeta.Text := '';
    Exit;
  end;
  try
    if TDirectory.Exists(APath) then
      FMeta.Text := APath
    else
    begin
      Sz := TFile.GetSize(APath);
      When := TFile.GetLastWriteTime(APath);
      FMeta.Text := Format('%s    %s    %s',
        [APath, FormatFileSize(Sz), DateTimeToStr(When)]);
    end;
  except
    FMeta.Text := APath;
  end;
end;

function TFilePreview.ClassifyExt(const AExt: string): Integer;
begin
  if ExtIn(AExt, ['.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff',
    '.webp', '.ico', '.cur', '.jfif', '.heic', '.heif', '.jxl', '.svg', '.svgz',
    '.emf', '.wmf', '.psd', '.psb', '.tga', '.avif', '.lottie', '.tgs']) then
    Exit(PK_IMAGE);
  if ExtIn(AExt, ['.txt', '.log', '.ini', '.inf', '.md', '.markdown',
 '.json', '.htm', '.html', '.xhtml', '.shtml',   '.m3u8', '.m3u',
    '.xml', '.yml', '.yaml', '.pas', '.dpr', '.dpk', '.inc',
     '.pp', '.lfm', '.dfm', '.sql',
    '.mht', '.mhtml', '.css', '.js', '.ts',
    '.c', '.h', '.cpp', '.hpp', '.cs', '.java', '.py', '.rb', '.go', '.rs',
    '.php', '.sh', '.bash', '.bat', '.cmd', '.ps1', '.vbs',   '.asc', '.bas', '.asm', '.lua',
    '.mjs', '.tsx', '.jsx', '.dpw', '.dart', '.vue', '.scss', '.less',
    '.asp', '.aspx',
     '.reg', '.conf', '.cfg',
    '.toml', '.editorconfig', '.gitignore', '.gitattributes', '.nfo',
     '.kt', '.swift', '.m', '.mm', '.plist']) then
    Exit(PK_TEXT);
  if ExtIn(AExt, ['.mp3', '.wav', '.flac', '.wma', '.aac', '.ogg', '.m4a',
    '.opus', '.mid', '.midi', '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.weba',
    '.m4v', '.mpg', '.mpeg', '.3gp', '.mts']) then
    Exit(PK_MEDIA);
  if ExtIn(AExt, ['.ttf', '.otf', '.ttc', '.woff', '.woff2', '.fon', '.eot']) then
    Exit(PK_FONT);
  if ExtIn(AExt, ['.zip', '.jar', '.apk', '.whl', '.nupkg',
    '.pptx', '.ppt', '.pptm','.ppsx','.ods', '.odp']) or IsArchiveExt(AExt) then
    Exit(PK_ARCHIVE);
  if ExtIn(AExt, ['.xlsx', '.xlsm', '.csv', '.tsv', '.xls', '.xlsb',  '.xlt', '.xltx', '.xltm']) then
    Exit(PK_TABLE);
  if ExtIn(AExt, ['.pdf', '.ai']) then
    Exit(PK_PDF);
  if ExtIn(AExt, ['.docx', '.docm', '.dotx', '.dotm', '.odt', '.rtf', '.doc',
    '.ppt', '.vsd', '.vsdx']) then
    Exit(PK_DOC);

  Result := PK_OTHER;
end;

function TFilePreview.LooksLikeText(const APath: string): Boolean;
begin
  Result := TextFileLooksLike(APath);
end;

function TFilePreview.LoadAsImage(const APath: string): Boolean;
var
  Ext: string;
begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext = '.ico') or (Ext = '.cur') or (FSig in [isIco, isCur]) then
  begin
    ShowIcoStrip(APath);
    Result := Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0);
    if Result then
    begin
      ShowImageTools(True);
      Exit;
    end;
  end;
  Result := LoadAsSkiaImage(APath);
  if Result and Assigned(FSvgBox) and FSvgBox.Visible then
  begin
    FSvgBox.HitTest := True;
    FSvgZoom := 1;
    ShowImageTools(True);
  end;
  if not Result and ExtIn(Ext, ['.jpg', '.jpeg', '.png', '.bmp', '.gif']) then
  try
    FImage.Bitmap.LoadFromFile(APath);
    Result := (FImage.Bitmap.Width > 0) and (FImage.Bitmap.Height > 0);
    if Result then
      ShowRasterImage;
  except
    Result := False;
  end;
  if not Result then
    Result := LoadAsThumb(APath);
  if Result then
  begin
    if FImage.Visible then
      FKindText.Text := Format('%d × %d', [FImage.Bitmap.Width, FImage.Bitmap.Height]);
    ShowImageTools(FImage.Visible);
  end;
end;

function TFilePreview.LoadAsThumb(const APath: string): Boolean;
var
  W, H: Integer;
begin
  Result := False;
  W := Max(200, Round(FBody.Width));
  H := Max(200, Round(FBody.Height));
  if W < 400 then W := 800;
  if H < 300 then H := 600;
  try
    Result := GetFileThumbnail(APath, W, H, FImage.Bitmap) and
      (FImage.Bitmap.Width > 0);
  except
    Result := False;
  end;
  if Result then
    ShowRasterImage;
end;

function TFilePreview.LoadAsText(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  N: Integer;
  Total: Int64;
  S, Err, EncName: string;
  Doc: TDocDocument;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      Total := FS.Size;
      N := Integer(Min(Int64(MAX_TEXT_BYTES), Total));
      SetLength(Buf, N);
      if N > 0 then
        FS.ReadBuffer(Buf[0], N);
      S := DecodeLooseText(Buf, EncName);
    finally
      FS.Free;
    end;
    if (EncName <> '') and Assigned(FMeta) then
    begin
      if FMeta.Text = '' then
        FMeta.Text := EncName
      else
        FMeta.Text := FMeta.Text + '    ' + EncName;
    end;
    if Total > MAX_TEXT_BYTES then
      S := S + sLineBreak + sLineBreak + Format('… показаны первые %d КБ',
        [MAX_TEXT_BYTES div 1024]);
    Doc := LoadTextDocumentFromString(S, APath, Err);
    if Doc <> nil then
    begin
      ApplyDocument(Doc);
      if Assigned(FDoc) and Assigned(FDocView) and FDocView.Visible then
      begin
        if IsMarkdownFile(APath) then
          FKindText.Text := 'Markdown'
        else
          FKindText.Text := 'Текст';
        Result := True;
        Exit;
      end;
    end;
    FMemo.WordWrap := True;
    FMemo.TextSettings.Font.Family := 'Calibri';
    FMemo.TextSettings.Font.Size := 13;
    FMemo.Lines.Text := S;
    FMemo.Visible := True;
    FKindText.Text := 'Текст';
    SyncMemoScroll;
    Result := True;
  except
    Result := False;
  end;
end;

function TFilePreview.LoadAsHex(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  I, N, Row, Col: Integer;
  Line: string;
  SL: TStringList;
  C: Byte;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(MAX_HEX_BYTES), FS.Size));
      SetLength(Buf, N);
      if N > 0 then
        FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
    SL := TStringList.Create;
    try
      I := 0;
      while I < N do
      begin
        Line := Format('%.8X  ', [I]);
        for Col := 0 to 15 do
        begin
          if I + Col < N then
            Line := Line + Format('%.2X ', [Buf[I + Col]])
          else
            Line := Line + '   ';
          if Col = 7 then
            Line := Line + ' ';
        end;
        Line := Line + ' |';
        for Col := 0 to 15 do
        begin
          if I + Col >= N then
            Break;
          C := Buf[I + Col];
          if C in [32..126] then
            Line := Line + Chr(C)
          else
            Line := Line + '.';
        end;
        Line := Line + '|';
        SL.Add(Line);
        Inc(I, 16);
        Row := SL.Count;
        if Row > 4096 then
          Break;
      end;
      if N = MAX_HEX_BYTES then
        SL.Add(Format('… показаны первые %d КБ', [MAX_HEX_BYTES div 1024]));
      FMemo.WordWrap := False;
      FMemo.TextSettings.Font.Family := 'Consolas';
      FMemo.TextSettings.Font.Size := 12;
      FMemo.Lines.Assign(SL);
    finally
      SL.Free;
    end;
    FMemo.Visible := True;
    FKindText.Text := 'Двоичный';
    SyncMemoScroll;
    Result := True;
  except
    Result := False;
  end;
end;

function TFilePreview.LoadAsMedia(const APath: string): Boolean;
var
  Ext: string;
  Audio: Boolean;
  OkPlay: Boolean;
begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  Audio := IsAudioMetaExt(Ext);
  OkPlay := False;
{$IFDEF MSWINDOWS}
  OkPlay := StartMpv(APath, not Audio); { видео — с HWND, аудио — без }
{$ENDIF}
  if not Audio and not OkPlay then
  begin
    if LoadAsThumb(APath) then
      Result := True
    else if LoadAsImage(APath) then
      Result := True;
  end;
  if OkPlay or Result or IsMediaMetaExt(Ext) then
  begin
    ShowMediaChrome(Audio);
    if Audio then
      FKindText.Text := 'Аудио'
    else
      FKindText.Text := 'Видео';
    Result := True;
    Exit;
  end;
end;

function TFilePreview.LoadAsFont(const APath: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Face: array[0..255] of Char;
  Sz: DWORD;
  Name: string;
{$ENDIF}
  Tf: ISkTypeface;
begin
  Result := False;
  FFontFace := ChangeFileExt(ExtractFileName(APath), '');
{$IFDEF MSWINDOWS}
  try
    if AddFontResourceEx(PChar(APath), FR_PRIVATE, nil) > 0 then
    begin
      FillChar(Face, SizeOf(Face), 0);
      Sz := SizeOf(Face);
      if GetFontResourceInfoW(PChar(APath), Sz, @Face, 1) then
        Name := string(Face)
      else
        Name := FFontFace;
      if Name <> '' then
        FFontFace := Name;
      Result := True;
    end;
  except
  end;
{$ENDIF}
  try
    Tf := TSkTypeface.MakeFromFile(APath);
    if Tf <> nil then
    begin
      if (FFontFace = '') or SameText(FFontFace, ChangeFileExt(ExtractFileName(APath), '')) then
        FFontFace := Tf.FamilyName;
      Result := True;
    end;
  except
  end;
  if not Result then
    Result := LoadAsThumb(APath);
  if Result then
  begin
    FFontSample.Align := TAlignLayout.Top;
    FFontSample.Height := 86;
    FFontSample.Text := FFontFace + sLineBreak +
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ  abcdefghijklmnopqrstuvwxyz' + sLineBreak +
      '0123456789  АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ';
    FFontSample.TextSettings.Font.Family := FFontFace;
    FFontSample.TextSettings.Font.Size := 18;
    FFontSample.Visible := True;
    FFontMap.Visible := True;
    FFontMap.Repaint;
    FKindText.Text := 'Шрифт';
  end;
end;

function TFilePreview.LoadAsArchive(const APath: string): Boolean;
var
  I, N: Integer;
  SL: TStringList;
  Items: TArray<TArcItem>;
begin
  Result := False;
  if not IsArchiveFileName(APath) then
  begin
    if LoadAsThumb(APath) then
    begin
      FKindText.Text := 'Архив';
      Exit(True);
    end;
    Exit(False);
  end;
  SL := TStringList.Create;
  try
    try
      Items := ListArchiveBranch(APath);
      N := Length(Items);
      SL.Add(Format('Файлов в архиве: %d', [N]));
      SL.Add('');
      for I := 0 to Min(N, 400) - 1 do
        if Items[I].IsDir then
          SL.Add(Items[I].Path + '/')
        else
          SL.Add(Items[I].Path);
      if N > 400 then
        SL.Add(Format('… и ещё %d', [N - 400]));
      SetLength(FTextLines, SL.Count);
      for I := 0 to SL.Count - 1 do
        FTextLines[I] := SL[I];
      FTextCode := False;
      FTextEncLabel := 'Архив';
      FTextExt := '.txt';
      FTextMaxCols := 80;
      try
        FTextTotal := TFile.GetSize(APath);
      except
        FTextTotal := 0;
      end;
      FTextShown := FTextTotal;
      if Assigned(FMemo) then
        FMemo.Visible := False;
      ShowTextModel;
      Result := True;
    except
      Result := LoadAsThumb(APath);
      if Result then
        FKindText.Text := 'Архив';
    end;
  finally
    SL.Free;
  end;
end;

const
  XLSX_MAX_ROWS = 200;
  XLSX_MAX_COLS = 40;
  XLSX_MAX_XML  = 8 * 1024 * 1024;

function XmlUnescape(const S: string): string;
begin
  Result := S;
  if Pos('&', Result) = 0 then
    Exit;
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', #39, [rfReplaceAll]);
  Result := StringReplace(Result, '&#39;', #39, [rfReplaceAll]);
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

function XmlAttr(const Tag, Name: string): string;
var
  Pat: string;
  P, Q: Integer;
  Quote: Char;
begin
  Result := '';
  Pat := Name + '="';
  P := Pos(Pat, Tag);
  Quote := '"';
  if P = 0 then
  begin
    Pat := Name + '=''';
    P := Pos(Pat, Tag);
    Quote := #39;
  end;
  if P = 0 then
    Exit;
  P := P + Length(Pat);
  Q := P;
  while (Q <= Length(Tag)) and (Tag[Q] <> Quote) do
    Inc(Q);
  Result := XmlUnescape(Copy(Tag, P, Q - P));
end;

function ZipReadUtf8(Zip: TZipFile; const Inner: string): string;
var
  Want, Have: string;
  I: Integer;
  Bytes: TBytes;
begin
  Result := '';
  Want := StringReplace(Inner, '\', '/', [rfReplaceAll]);
  for I := 0 to Zip.FileCount - 1 do
  begin
    Have := StringReplace(Zip.FileName[I], '\', '/', [rfReplaceAll]);
    if not SameText(Have, Want) then
      Continue;
    Zip.Read(I, Bytes);
    if Length(Bytes) > XLSX_MAX_XML then
      SetLength(Bytes, XLSX_MAX_XML);
    Result := DecodeUtf8OrReplace(Bytes);
    Exit;
  end;
end;

function CellRefToRC(const Ref: string; out Row, Col: Integer): Boolean;
var
  I, C: Integer;
  Ch: Char;
begin
  Result := False;
  Row := 0;
  Col := 0;
  I := 1;
  C := 0;
  while I <= Length(Ref) do
  begin
    Ch := UpCase(Ref[I]);
    if (Ch < 'A') or (Ch > 'Z') then
      Break;
    C := C * 26 + (Ord(Ch) - Ord('A') + 1);
    Inc(I);
  end;
  if (C <= 0) or (I > Length(Ref)) then
    Exit;
  Row := StrToIntDef(Copy(Ref, I, 8), 0);
  Col := C;
  Result := (Row > 0) and (Col > 0);
end;

function ExtractTRuns(const Fragment: string): string;
var
  P, Gt, CloseP: Integer;
  Chunk: string;
begin
  Result := '';
  P := 1;
  while P <= Length(Fragment) do
  begin
    P := Pos('<t', Fragment, P);
    if P = 0 then
      Break;
    if (P + 2 <= Length(Fragment)) and
       (Fragment[P + 2] <> '>') and (Fragment[P + 2] <> ' ') and
       (Fragment[P + 2] <> '/') then
    begin
      Inc(P, 2);
      Continue;
    end;
    Gt := Pos('>', Fragment, P);
    if Gt = 0 then
      Break;
    if (Gt > P) and (Fragment[Gt - 1] = '/') then
    begin
      P := Gt + 1;
      Continue;
    end;
    CloseP := Pos('</t>', Fragment, Gt + 1);
    if CloseP = 0 then
      Break;
    Chunk := Copy(Fragment, Gt + 1, CloseP - Gt - 1);
    Result := Result + XmlUnescape(Chunk);
    P := CloseP + 4;
  end;
end;

function CollectSharedStrings(const Xml: string): TArray<string>;
var
  P, Gt, CloseP: Integer;
  Inner: string;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    P := 1;
    while P <= Length(Xml) do
    begin
      P := Pos('<si', Xml, P);
      if P = 0 then
        Break;
      if (P + 3 <= Length(Xml)) and
         (Xml[P + 3] <> '>') and (Xml[P + 3] <> ' ') and (Xml[P + 3] <> '/') then
      begin
        Inc(P, 3);
        Continue;
      end;
      Gt := Pos('>', Xml, P);
      if Gt = 0 then
        Break;
      if (Gt > P) and (Xml[Gt - 1] = '/') then
      begin
        List.Add('');
        P := Gt + 1;
        Continue;
      end;
      CloseP := Pos('</si>', Xml, Gt + 1);
      if CloseP = 0 then
        Break;
      Inner := Copy(Xml, Gt + 1, CloseP - Gt - 1);
      List.Add(ExtractTRuns(Inner));
      P := CloseP + 5;
      if List.Count > 50000 then
        Break;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FirstSheetName(const WorkbookXml: string): string;
var
  P, Gt: Integer;
  Tag: string;
begin
  Result := '';
  P := 1;
  while P <= Length(WorkbookXml) do
  begin
    P := Pos('<sheet', WorkbookXml, P);
    if P = 0 then
      Exit;
    if (P + 6 <= Length(WorkbookXml)) and
       (WorkbookXml[P + 6] <> '>') and (WorkbookXml[P + 6] <> ' ') then
    begin
      Inc(P, 6);
      Continue;
    end;
    Gt := Pos('>', WorkbookXml, P);
    if Gt = 0 then
      Exit;
    Tag := Copy(WorkbookXml, P, Gt - P + 1);
    Result := XmlAttr(Tag, 'name');
    if Result <> '' then
      Exit;
    P := Gt + 1;
  end;
end;

function XmlInnerV(const Fragment: string): string;
var
  A, B: Integer;
begin
  Result := '';
  A := Pos('<v', Fragment);
  if A = 0 then
    Exit;
  A := Pos('>', Fragment, A);
  if A = 0 then
    Exit;
  B := Pos('</v>', Fragment, A);
  if B = 0 then
    Exit;
  Result := XmlUnescape(Copy(Fragment, A + 1, B - A - 1));
end;

function ParseXlsxSheet(const SheetXml: string; const Shared: TArray<string>): string;
var
  P, Gt, CloseP, Row, Col, MaxRow, MaxCol, R, C, Idx: Integer;
  Tag, Inner, Ref, Typ, Val: string;
  SelfClose: Boolean;
  Grid: array of TArray<string>;
  Line: string;
  SL: TStringList;

  procedure PutCell(ARow, ACol: Integer; const AVal: string);
  begin
    if (ARow < 1) or (ACol < 1) or (ARow > XLSX_MAX_ROWS) or (ACol > XLSX_MAX_COLS) then
      Exit;
    if Length(Grid) < ARow then
      SetLength(Grid, ARow);
    if Length(Grid[ARow - 1]) < ACol then
      SetLength(Grid[ARow - 1], ACol);
    Grid[ARow - 1][ACol - 1] := AVal;
    if ARow > MaxRow then
      MaxRow := ARow;
    if ACol > MaxCol then
      MaxCol := ACol;
  end;

begin
  Result := '';
  MaxRow := 0;
  MaxCol := 0;
  P := 1;
  while P <= Length(SheetXml) do
  begin
    P := Pos('<c', SheetXml, P);
    if P = 0 then
      Break;
    if (P + 2 <= Length(SheetXml)) and
       (SheetXml[P + 2] <> '>') and (SheetXml[P + 2] <> ' ') and
       (SheetXml[P + 2] <> '/') then
    begin
      Inc(P, 2);
      Continue;
    end;
    Gt := Pos('>', SheetXml, P);
    if Gt = 0 then
      Break;
    SelfClose := (Gt > P) and (SheetXml[Gt - 1] = '/');
    Tag := Copy(SheetXml, P, Gt - P + 1);
    Ref := XmlAttr(Tag, 'r');
    if not CellRefToRC(Ref, Row, Col) then
    begin
      P := Gt + 1;
      Continue;
    end;
    Inner := '';
    CloseP := Gt;
    if not SelfClose then
    begin
      CloseP := Pos('</c>', SheetXml, Gt + 1);
      if CloseP = 0 then
        Break;
      Inner := Copy(SheetXml, Gt + 1, CloseP - Gt - 1);
    end;
    Typ := LowerCase(XmlAttr(Tag, 't'));
    if Typ = 's' then
    begin
      Idx := StrToIntDef(XmlInnerV(Inner), -1);
      if (Idx >= 0) and (Idx < Length(Shared)) then
        Val := Shared[Idx]
      else
        Val := '';
    end
    else if Typ = 'inlinestr' then
      Val := ExtractTRuns(Inner)
    else if Typ = 'b' then
    begin
      if Trim(XmlInnerV(Inner)) = '1' then
        Val := 'TRUE'
      else
        Val := 'FALSE';
    end
    else
    begin
      Val := XmlInnerV(Inner);
      if Val = '' then
        Val := ExtractTRuns(Inner);
    end;
    PutCell(Row, Col, Val);
    if SelfClose then
      P := Gt + 1
    else
      P := CloseP + 4;
    if MaxRow >= XLSX_MAX_ROWS then
      Break;
  end;
  if MaxRow = 0 then
    Exit;
  SL := TStringList.Create;
  try
    for R := 0 to MaxRow - 1 do
    begin
      Line := '';
      for C := 0 to MaxCol - 1 do
      begin
        if C > 0 then
          Line := Line + #9;
        if (R < Length(Grid)) and (C < Length(Grid[R])) then
          Line := Line + Grid[R][C];
      end;
      SL.Add(Line);
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

function XlsxWorkbookText(const APath: string): string;
var
  Zip: TZipFile;
  SharedXml, SheetXml, BookXml, SheetName: string;
  Shared: TArray<string>;
  I: Integer;
  Have: string;
begin
  Result := '';
  Zip := nil;
  try
    Zip := OpenZipRead(APath);
    BookXml := ZipReadUtf8(Zip, 'xl/workbook.xml');
    SharedXml := ZipReadUtf8(Zip, 'xl/sharedStrings.xml');
    SheetXml := ZipReadUtf8(Zip, 'xl/worksheets/sheet1.xml');
    if SheetXml = '' then
      for I := 0 to Zip.FileCount - 1 do
      begin
        Have := StringReplace(LowerCase(Zip.FileName[I]), '\', '/', [rfReplaceAll]);
        if Pos('xl/worksheets/sheet', Have) = 1 then
        begin
          SheetXml := ZipReadUtf8(Zip, Zip.FileName[I]);
          Break;
        end;
      end;
  finally
    if Assigned(Zip) then
      Zip.Free;
  end;
  if SheetXml = '' then
    Exit;
  if SharedXml <> '' then
    Shared := CollectSharedStrings(SharedXml)
  else
    SetLength(Shared, 0);
  SheetName := FirstSheetName(BookXml);
  Result := ParseXlsxSheet(SheetXml, Shared);
  if Result = '' then
    Exit;
  if SheetName <> '' then
    Result := 'Лист: ' + SheetName + sLineBreak + sLineBreak + Result;
end;

function FileHasZipMagic(const APath: string): Boolean;
var
  FS: TFileStream;
  B: array[0..3] of Byte;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Read(B, 4) = 4 then
        Result := (B[0] = $50) and (B[1] = $4B);
    finally
      FS.Free;
    end;
  except
  end;
end;

procedure TFilePreview.SheetComboChange(Sender: TObject);
begin
  if Assigned(FPdf) and Assigned(FSheetCombo) and (FSheetCombo.ItemIndex >= 0) then
  begin
    ShowPdfPage(FSheetCombo.ItemIndex);
    Exit;
  end;
  if Assigned(FDoc) and Assigned(FDocView) and Assigned(FSheetCombo) and
     (FSheetCombo.ItemIndex >= 0) then
  begin
    FDocView.GoToPage(FSheetCombo.ItemIndex);
    Exit;
  end;
  if not Assigned(FBook) or not Assigned(FGrid) or not Assigned(FSheetCombo) then
    Exit;
  if (FSheetCombo.ItemIndex < 0) or (FSheetCombo.ItemIndex >= FBook.Sheets.Count) then
    Exit;
  FBook.ActiveIndex := FSheetCombo.ItemIndex;
  FGrid.SetSheet(FBook.ActiveSheet);
end;

function TFilePreview.LoadAsSpreadsheet(const APath: string): Boolean;
var
  Ext, Err, Meta: string;
  I: Integer;
  Sheet: TSpreadSheet;
begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  if IsOfficeLockFile(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if ExtIn(Ext, ['.xls', '.xlsb', '.xlt']) then
    Exit;
  if Assigned(FGrid) then
    FGrid.Clear;
  FreeAndNil(FBook);
  FBook := LoadWorkbookLimited(APath, SpreadQVMaxRows, SpreadQVMaxCols, Err);
  if FBook = nil then
    Exit;
  FSheetCombo.Items.BeginUpdate;
  try
    FSheetCombo.Items.Clear;
    for I := 0 to FBook.Sheets.Count - 1 do
      FSheetCombo.Items.Add(FBook.Sheets[I].Name);
  finally
    FSheetCombo.Items.EndUpdate;
  end;
  FSheetCombo.ItemIndex := 0;
  FSheetBar.Visible := FBook.Sheets.Count > 1;
  FGrid.ApplyTheme(FColors);
  FGrid.Visible := True;
  FGrid.SetSheet(FBook.ActiveSheet);
  FGrid.SyncNow;
  FKindText.Text := 'Таблица';
  Sheet := FBook.ActiveSheet;
  Meta := '';
  if Assigned(Sheet) then
  begin
    Meta := Format('%d × %d', [Sheet.RowCount, Sheet.ColCount]);
    if Sheet.Truncated then
      Meta := Meta + Format('  (показано до %d×%d)', [SpreadQVMaxRows, SpreadQVMaxCols]);
  end;
  if (FBook <> nil) and (FBook.EncodingLabel <> '') then
    Meta := Meta + '    ' + FBook.EncodingLabel;
  if Meta <> '' then
    FMeta.Text := FMeta.Text + '    ' + Meta;
  Result := True;
end;

function TFilePreview.LoadAsDocument(const APath: string): Boolean;
var
  Ext, Err, Meta: string;
  I: Integer;
begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  if IsOfficeLockFile(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  if Ext = '.doc' then
    Exit;
  if Assigned(FDocView) then
    FDocView.Clear;
  FreeAndNil(FDoc);
  FDoc := LoadDocumentLimited(APath, Err);
  if FDoc = nil then
    Exit;
  FSheetCombo.Items.BeginUpdate;
  try
    FSheetCombo.Items.Clear;
    for I := 0 to FDoc.Pages.Count - 1 do
      FSheetCombo.Items.Add(Format('Страница %d', [I + 1]));
  finally
    FSheetCombo.Items.EndUpdate;
  end;
  if FSheetCombo.Items.Count > 0 then
    FSheetCombo.ItemIndex := 0;
  FSheetBar.Visible := FDoc.Pages.Count > 1;
  FDocView.ApplyTheme(FColors);
  FDocView.Visible := True;
  FDocView.SetDocument(FDoc);
  FDocView.SyncNow;
  FKindText.Text := 'Документ';
  Meta := Format('%d стр.', [FDoc.Pages.Count]);
  if FDoc.Truncated then
    Meta := Meta + '  (показано частично)';
  if Meta <> '' then
    FMeta.Text := FMeta.Text + '    ' + Meta;
  Result := True;
end;

procedure TFilePreview.ApplySpreadsheet(ABook: TSpreadWorkbook);
var
  I: Integer;
  Sheet: TSpreadSheet;
  Meta: string;
begin
  if (ABook = nil) or FDestroying or (csDestroying in ComponentState) then
  begin
    ABook.Free;
    Exit;
  end;
  if Assigned(FGrid) then
    FGrid.Clear;
  FreeAndNil(FBook);
  FBook := ABook;
  try
    FSheetCombo.Items.BeginUpdate;
    try
      FSheetCombo.Items.Clear;
      for I := 0 to FBook.Sheets.Count - 1 do
        FSheetCombo.Items.Add(FBook.Sheets[I].Name);
    finally
      FSheetCombo.Items.EndUpdate;
    end;
    FSheetCombo.ItemIndex := 0;
    FSheetBar.Visible := FBook.Sheets.Count > 1;
    FGrid.ApplyTheme(FColors);
    FGrid.Visible := True;
    FGrid.SetSheet(FBook.ActiveSheet);
    FKindText.Text := 'Таблица';
    Sheet := FBook.ActiveSheet;
    Meta := '';
    if Assigned(Sheet) then
    begin
      Meta := Format('%d × %d', [Sheet.RowCount, Sheet.ColCount]);
      if Sheet.Truncated then
        Meta := Meta + Format('  (показано до %d×%d)', [SpreadQVMaxRows, SpreadQVMaxCols]);
    end;
    if (FBook <> nil) and (FBook.EncodingLabel <> '') then
      Meta := Meta + '    ' + FBook.EncodingLabel;
    if Meta <> '' then
      FMeta.Text := FMeta.Text + '    ' + Meta;
    if FCaptureKeys then
      FocusViewer;
  except
    if Assigned(FGrid) then
      FGrid.Clear;
    FreeAndNil(FBook);
    ShowInfo('Не удалось показать таблицу');
  end;
end;

procedure TFilePreview.ApplyDocument(ADoc: TDocDocument);
var
  I: Integer;
  Meta: string;
begin
  if (ADoc = nil) or FDestroying or (csDestroying in ComponentState) then
  begin
    ADoc.Free;
    Exit;
  end;
  if Assigned(FDocView) then
    FDocView.Clear;
  FreeAndNil(FDoc);
  FDoc := ADoc;
  try
    FSheetCombo.Items.BeginUpdate;
    try
      FSheetCombo.Items.Clear;
      if FDoc.Pages.Count = 0 then
        FDoc.BuildLayout;
      for I := 0 to FDoc.Pages.Count - 1 do
        FSheetCombo.Items.Add(Format('Страница %d', [I + 1]));
    finally
      FSheetCombo.Items.EndUpdate;
    end;
    if FSheetCombo.Items.Count > 0 then
      FSheetCombo.ItemIndex := 0;
    FSheetBar.Visible := FDoc.Pages.Count > 1;
    FDocView.ApplyTheme(FColors);
    FDocView.Visible := True;
    FDocView.SetDocument(FDoc);
    FKindText.Text := 'Документ';
    Meta := Format('%d стр.', [FDoc.Pages.Count]);
    if FDoc.Truncated then
      Meta := Meta + '  (показано частично)';
    if Meta <> '' then
      FMeta.Text := FMeta.Text + '    ' + Meta;
    if FCaptureKeys then
      FocusViewer;
  except
    if Assigned(FDocView) then
      FDocView.Clear;
    FreeAndNil(FDoc);
    ShowInfo('Не удалось показать документ');
  end;
end;

procedure TFilePreview.StartHeavyLoad(const APath: string; AKind: Integer);
var
  Gen: Integer;
  Path: string;
begin
  Inc(FLoadGen);
  Gen := FLoadGen;
  Path := APath;
  ShowInfo('Загрузка…');
  TThread.CreateAnonymousThread(
    procedure
    var
      Book: TSpreadWorkbook;
      Doc: TDocDocument;
      Err: string;
    begin
      Book := nil;
      Doc := nil;
      try
        if AKind = PK_TABLE then
          Book := LoadWorkbookLimited(Path, SpreadQVMaxRows, SpreadQVMaxCols, Err)
        else
          Doc := LoadDocumentLimited(Path, Err);
      except
        on E: Exception do
          Err := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if FDestroying or (csDestroying in ComponentState) or (FLoadGen <> Gen) then
          begin
            Book.Free;
            Doc.Free;
            Exit;
          end;
          try
            if Assigned(FInfo) then
              FInfo.Visible := False;
            if AKind = PK_TABLE then
            begin
              if Book <> nil then
              begin
                ApplySpreadsheet(Book);
                Book := nil;
              end
              else
              begin
                ShowInfo('Не удалось разобрать таблицу');
                FKindText.Text := 'Таблица';
              end;
            end
            else if Doc <> nil then
            begin
              ApplyDocument(Doc);
              Doc := nil;
            end
            else
            begin
              ShowInfo('Не удалось разобрать документ');
              FKindText.Text := 'Документ';
            end;
          except
            Book.Free;
            Doc.Free;
            ShowInfo('Ошибка просмотра');
          end;
        end);
    end).Start;
end;

function LooksLikeLottie(const APath: string): Boolean;
var
  FS: TFileStream;
  Buf: TBytes;
  I, N: Integer;
  Head: string;
  C: Byte;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(4096), FS.Size));
      if N < 8 then
        Exit;
      SetLength(Buf, N);
      FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
  except
    Exit(False);
  end;
  I := 0;
  if (N >= 3) and (Buf[0] = $EF) and (Buf[1] = $BB) and (Buf[2] = $BF) then
    I := 3;
  while (I < N) and (Buf[I] in [9, 10, 13, 32]) do
    Inc(I);
  if (I >= N) or (Buf[I] <> Ord('{')) then
    Exit;
  SetLength(Head, N);
  for I := 0 to N - 1 do
  begin
    C := Buf[I];
    if C < 128 then
      Head[I + 1] := Char(C)
    else
      Head[I + 1] := ' ';
  end;
  Head := LowerCase(Head);
  Result := (Pos('"layers"', Head) > 0) or (Pos('"assets"', Head) > 0);
end;

procedure TFilePreview.PaintSvg(Sender: TObject; const ACanvas: ISkCanvas;
  const ADest: TRectF; const AOpacity: Single);
var
  Intr: TSizeF;
  VB: TRectF;
  Scale, Ox, Oy: Single;
begin
  if not Assigned(FSvgDom) or not Assigned(FSvgDom.Root) then
    Exit;
  if ADest.IsEmpty then
    Exit;
  try
    Intr := FSvgDom.Root.GetIntrinsicSize(TSizeF.Create(ADest.Width, ADest.Height));
    if (Intr.Width < 1) or (Intr.Height < 1) then
    begin
      if FSvgDom.Root.TryGetViewBox(VB) and (VB.Width > 0) and (VB.Height > 0) then
        Intr := TSizeF.Create(VB.Width, VB.Height)
      else
        Intr := TSizeF.Create(ADest.Width, ADest.Height);
    end;
    if (Intr.Width < 1) or (Intr.Height < 1) then
      Exit;
    Scale := Min(ADest.Width / Intr.Width, ADest.Height / Intr.Height) * FSvgZoom;
    if Scale <= 0 then
      Exit;
    Ox := ADest.Left + (ADest.Width - Intr.Width * Scale) / 2 + FSvgPan.X;
    Oy := ADest.Top + (ADest.Height - Intr.Height * Scale) / 2 + FSvgPan.Y;
    FSvgDom.SetContainerSize(Intr);
    ACanvas.Save;
    try
      ACanvas.ClipRect(ADest);
      if AOpacity < 0.999 then
        ACanvas.SaveLayerAlpha(Byte(Round(AOpacity * 255)))
      else
        ACanvas.Save;
      try
        ACanvas.Translate(Ox, Oy);
        ACanvas.Scale(Scale, Scale);
        FSvgDom.Render(ACanvas);
      finally
        ACanvas.Restore;
      end;
    finally
      ACanvas.Restore;
    end;
  except
  end;
end;

function TFilePreview.AnimIsPlaying: Boolean;
begin
  Result := Assigned(FAnim) and FAnim.Visible;
end;

procedure TFilePreview.StopAnim;
begin
  if FAnim = nil then
    Exit;
  try
    if Assigned(FAnim.Animation) then
    begin
      FAnim.Animation.Loop := False;
      FAnim.Animation.Stop;
      FAnim.Animation.Enabled := False;
    end;
  except
  end;
  try
    FAnim.Visible := False;
    FAnim.HitTest := False;
    FAnim.Parent := nil;
  except
  end;
  FreeAndNil(FAnim);
end;

procedure TFilePreview.EnsureAnim;
begin
  if Assigned(FAnim) then
    Exit;
  FAnim := TSkAnimatedImage.Create(Self);
  FAnim.Parent := FBody;
  FAnim.Align := TAlignLayout.Client;
  FAnim.Visible := False;
  FAnim.HitTest := False;
  FAnim.WrapMode := TSkAnimatedImageWrapMode.Fit;
  if Assigned(FAnim.Animation) then
  begin
    FAnim.Animation.Loop := True;
    FAnim.Animation.Enabled := False;
  end;
end;

function TFilePreview.LoadAsAnimated(const APath: string): Boolean;
var
  Ext: string;
  Zip: TZipFile;
  I: Integer;
  Bytes: TBytes;
  Name: string;
begin
  Result := False;
  if APath = '' then
    Exit;
  StopAnim;
  EnsureAnim;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    FAnim.LoadFromFile(APath);
    if (FAnim.OriginalSize.Width < 1) and (Ext = '.lottie') then
    begin
      Zip := TZipFile.Create;
      try
        Zip.Open(APath, zmRead);
        for I := 0 to Zip.FileCount - 1 do
        begin
          Name := LowerCase(Zip.FileName[I]);
          if ExtractFileExt(Name) <> '.json' then
            Continue;
          Zip.Read(I, Bytes);
          if Length(Bytes) = 0 then
            Continue;
          FAnim.Source.Data := Bytes;
          if FAnim.OriginalSize.Width > 0 then
            Break;
        end;
      finally
        Zip.Free;
      end;
    end;
    if FAnim.OriginalSize.Width < 1 then
    begin
      StopAnim;
      Exit(False);
    end;
    FAnim.WrapMode := TSkAnimatedImageWrapMode.Fit;
    FAnim.Animation.Loop := True;
    FAnim.Animation.Enabled := True;
    FAnim.Visible := True;
    FAnim.BringToFront;
    FAnim.Animation.Progress := 0;
    FAnim.Animation.Start;
    Result := True;
  except
    StopAnim;
    Result := False;
  end;
end;

procedure TFilePreview.CleanupSvgTemp;
begin
  if FSvgTemp = '' then
    Exit;
  try
    if TFile.Exists(FSvgTemp) then
      TFile.Delete(FSvgTemp);
  except
  end;
  FSvgTemp := '';
end;

procedure TFilePreview.HideSvgWeb;
begin
  if Assigned(FWeb) then
  begin
    FWeb.Visible := False;
    try
      FWeb.Stop;
    except
    end;
  end;
end;

{$IFDEF MSWINDOWS}
function WebView2LoaderFile: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'WebView2Loader.dll';
end;

function DllImageMachine(const APath: string): Word;
var
  FS: TFileStream;
  PeOff: Integer;
begin
  Result := 0;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size < $40 then
      Exit;
    FS.Position := $3C;
    FS.ReadBuffer(PeOff, SizeOf(PeOff));
    if (PeOff < 0) or (PeOff > FS.Size - 6) then
      Exit;
    FS.Position := PeOff + 4;
    FS.ReadBuffer(Result, SizeOf(Result));
  finally
    FS.Free;
  end;
end;

procedure PrepareWebView2Loader;
var
  P: string;
begin
  P := WebView2LoaderFile;
  if TFile.Exists(P) then
    SetWebView2Path(P);
end;

function WebView2BlockReason: string;
var
  M: Word;
begin
  Result := '';
  if IsEdgeAvailable then
    Exit;
  if not TFile.Exists(WebView2LoaderFile) then
    Exit('WebView2Loader.dll не найден рядом с программой. Страница в IE: тёмный фон и анимация недоступны.')
  else
  begin
    try
      M := DllImageMachine(WebView2LoaderFile);
    except
      M := 0;
    end;
    if M = $8664 then
      Exit('WebView2Loader.dll 64-битный, программа 32-битная. Страница в IE: тёмный фон и анимация недоступны.')
    else
      Exit('WebView2 не запустился. Страница в IE: тёмный фон и анимация недоступны.');
  end;
end;
{$ENDIF}

procedure TFilePreview.EnsureWebBrowser;
begin
  {$IFDEF MSWINDOWS}
  PrepareWebView2Loader;
  {$ENDIF}
  if Assigned(FWeb) then
    Exit;
  FWeb := FMX.WebBrowser.TWebBrowser.Create(Self);
  FWeb.Visible := False;
  FWeb.EnableCaching := False;
  FWeb.HitTest := True;
  { URL до Parent, иначе RecreateWebBrowser делает Navigate('') и
    падает с EFileNotFoundException. }
  FWeb.WindowsEngine := TWindowsEngine.EdgeIfAvailable;
  FWeb.OnShouldLoadURL := WebShouldLoad;
  FWeb.OnDidFinishLoad := WebFinished;
  FWeb.URL := 'about:blank';
  FWeb.Parent := FBody;
  FWeb.Align := TAlignLayout.Client;
end;

const
  HTML_PREVIEW_HOST = 'vibe.example';

function EncodePathSegment(const S: string): string;
var
  B: TBytes;
  I: Integer;
begin
  B := TEncoding.UTF8.GetBytes(S);
  Result := '';
  for I := 0 to High(B) do
    if ((B[I] >= Ord('A')) and (B[I] <= Ord('Z'))) or
       ((B[I] >= Ord('a')) and (B[I] <= Ord('z'))) or
       ((B[I] >= Ord('0')) and (B[I] <= Ord('9'))) or
       (B[I] in [Ord('-'), Ord('.'), Ord('_'), Ord('~')]) then
      Result := Result + Char(B[I])
    else
      Result := Result + '%' + IntToHex(B[I], 2);
end;

function FindCoreWebView(ARoot: TFmxObject): ICoreWebView2;
var
  Ctx: TRttiContext;
  Inst: TObject;
  Prop: TRttiProperty;
  Field: TRttiField;
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if Supports(ARoot, ICoreWebView2, Result) then
    Exit;
  Ctx := TRttiContext.Create;
  try
    Prop := Ctx.GetType(ARoot.ClassType).GetProperty('NativePresentation');
    if Prop <> nil then
    begin
      Inst := Prop.GetValue(ARoot).AsObject;
      if (Inst <> nil) and Supports(Inst, ICoreWebView2, Result) then
        Exit;
    end;
    Field := Ctx.GetType(ARoot.ClassType).GetField('FNativePresentation');
    if Field <> nil then
    begin
      Inst := Field.GetValue(ARoot).AsObject;
      if (Inst <> nil) and Supports(Inst, ICoreWebView2, Result) then
        Exit;
    end;
  finally
    Ctx.Free;
  end;
  for I := 0 to ARoot.ChildrenCount - 1 do
  begin
    Result := FindCoreWebView(ARoot.Children[I]);
    if Result <> nil then
      Exit;
  end;
end;

function TFilePreview.MapHtmlFolder(const AFolder: string): Boolean;
var
  WV: ICoreWebView2;
  WV3: ICoreWebView2_3;
begin
  Result := False;
  {$IFDEF MSWINDOWS}
  if (AFolder = '') or not TDirectory.Exists(AFolder) then
    Exit;
  WV := FindCoreWebView(FWeb);
  if (WV = nil) or (WV.QueryInterface(ICoreWebView2_3, WV3) <> S_OK) or
     (WV3 = nil) then
    Exit;
  WV3.ClearVirtualHostNameToFolderMapping(PChar(HTML_PREVIEW_HOST));
  Result := Succeeded(WV3.SetVirtualHostNameToFolderMapping(
    PChar(HTML_PREVIEW_HOST), PChar(AFolder),
    COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW));
  {$ELSE}
  if AFolder = '' then
    Exit;
  {$ENDIF}
end;

function TFilePreview.HtmlPreviewUrl(const APath: string): string;
begin
  Result := 'https://' + HTML_PREVIEW_HOST + '/' +
    EncodePathSegment(ExtractFileName(APath));
end;

function TFilePreview.FileUriForBrowser(const APath: string): string;
var
  P: string;
begin
  { «File:///», не «file://»: FMX срезает префикс file:// и затем FileExists
    на остатке падает, а WebView2 так и не получает URI для css/js. }
  P := StringReplace(APath, '\', '/', [rfReplaceAll]);
  P := StringReplace(P, '%', '%25', [rfReplaceAll]);
  P := StringReplace(P, ' ', '%20', [rfReplaceAll]);
  P := StringReplace(P, '#', '%23', [rfReplaceAll]);
  P := StringReplace(P, '?', '%3F', [rfReplaceAll]);
  if (Length(P) >= 2) and (P[1] = '/') and (P[2] = '/') then
    Result := 'File:' + P
  else
    Result := 'File:///' + P;
end;

function TFilePreview.HtmlNavAllowed(const AURL: string): Boolean;
var
  U, Ext: string;
begin
  U := Trim(AURL);
  if U = '' then
    Exit(True);
  if StartsText('about:', U) or StartsText('data:', U) then
    Exit(True);
  { Папка страницы отдаётся как https://vibe.example/… — относительные css/js/img. }
  if StartsText('https://' + HTML_PREVIEW_HOST, U) or
     StartsText('http://' + HTML_PREVIEW_HOST, U) then
    Exit(True);
  { Переход документа наружу. Картинки, css и js с CDN сюда не попадают. }
  if StartsText('http:', U) or StartsText('https:', U) or StartsText('ftp:', U) or
     StartsText('javascript:', U) or StartsText('blob:', U) then
    Exit(False);
  if StartsText('file:', U) or StartsText('\\', U) or StartsText('//', U) or
     ((Length(U) >= 2) and (U[2] = ':')) then
  begin
    Ext := LowerCase(ExtractFileExt(U));
    if Pos('?', Ext) > 0 then
      Ext := Copy(Ext, 1, Pos('?', Ext) - 1);
    if Pos('#', Ext) > 0 then
      Ext := Copy(Ext, 1, Pos('#', Ext) - 1);
    Result := not ExtIn(Ext, ['.exe', '.msi', '.bat', '.cmd', '.ps1', '.com',
      '.scr', '.zip', '.rar', '.7z', '.iso', '.dmg', '.cab', '.msix']);
    Exit;
  end;
  Result := False;
end;

procedure TFilePreview.WebShouldLoad(Sender: TObject; const AURL: string;
  var ACancel: Boolean);
begin
  ACancel := not HtmlNavAllowed(AURL);
end;

procedure TFilePreview.WebFinished(Sender: TObject);
const
  Sandbox =
    'try{window.close=function(){};window.open=function(){return null;};' +
    'document.addEventListener("click",function(ev){var n=ev.target;' +
    'while(n&&n.tagName!=="A")n=n.parentElement;if(!n)return;' +
    'if(n.hasAttribute("download")){ev.preventDefault();ev.stopPropagation();}' +
    '},true);}catch(e){}';
begin
  if not Assigned(FWeb) or not FWeb.Visible then
    Exit;
  try
    FWeb.EvaluateJavaScript(Sandbox);
  except
  end;
end;

procedure TFilePreview.UpdateHtmlModeButtons;
begin
  if Assigned(FBtnHtmlPage) then
    FBtnHtmlPage.SetSelected(not FHtmlShowSource);
  if Assigned(FBtnHtmlSrc) then
    FBtnHtmlSrc.SetSelected(FHtmlShowSource);
end;

procedure TFilePreview.ShowHtmlMode(AShow: Boolean);
begin
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := AShow;
  UpdateHtmlModeButtons;
end;

procedure TFilePreview.HtmlPageClick(Sender: TObject);
begin
  if FPath = '' then
    Exit;
  FHtmlShowSource := False;
  UpdateHtmlModeButtons;
  if Assigned(FMemo) then
    FMemo.Visible := False;
  if Assigned(FDocView) then
    FDocView.Visible := False;
  if Assigned(FCodeView) then
    FCodeView.Visible := False;
  ShowTextChrome(False);
  LoadAsHtmlBrowser(FPath);
end;

procedure TFilePreview.HtmlSourceClick(Sender: TObject);
begin
  if FPath = '' then
    Exit;
  FHtmlShowSource := True;
  UpdateHtmlModeButtons;
  HideSvgWeb;
  if Assigned(FCodeView) then
    FCodeView.Visible := False;
  if Assigned(FDocView) then
    FDocView.Visible := False;
  ShowHtmlMode(True);
  FTextEnc := temAuto;
  StartTextLoad(FPath);
end;

procedure TTextLoadJob.Execute;
var
  FS: TFileStream;
  Buf: TBytes;
  N: Integer;
  Text: string;
begin
  Ok := False;
  try
    FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      Total := FS.Size;
      N := Integer(Min(Int64(TextQVMaxBytes), Total));
      Shown := N;
      SetLength(Buf, N);
      if N > 0 then
        FS.ReadBuffer(Buf[0], N);
    finally
      FS.Free;
    end;
    Text := DecodeTextBytes(Buf, Mode, EncLabel);
    SplitTextLines(Text, Lines, MaxCols);
    Ok := True;
  except
    Ok := False;
  end;
  TThread.Queue(nil, Apply);
end;

procedure TTextLoadJob.Apply;
var
  P: TFilePreview;
begin
  P := Preview;
  if (P <> nil) and (P.FTextJob = Self) then
    P.FTextJob := nil;
  try
    if (P <> nil) and (not P.FDestroying) and (P.FLoadGen = Gen) then
      P.AcceptTextLoad(Self);
  finally
    Free;
  end;
end;

procedure TFilePreview.ShowTextChrome(AShow: Boolean);
begin
  if Assigned(FTextBar) then
    FTextBar.Visible := AShow;
  if Assigned(FKindText) then
    FKindText.Visible := not AShow;
  if AShow then
    LayoutTextBar;
end;

procedure TFilePreview.LayoutTextBar;
var
  W: Single;
begin
  if not Assigned(FTextBar) then
    Exit;
  if Assigned(FBtnSheets) then
    FBtnSheets.SetSelected(not FTextCode);
  if Assigned(FBtnCode) then
    FBtnCode.SetSelected(FTextCode);
  if Assigned(FBtnHi) then
  begin
    FBtnHi.Visible := FTextCode;
    FBtnHi.SetSelected(FTextHi);
  end;
  if Assigned(FBtnWrap) then
  begin
    FBtnWrap.Visible := FTextCode;
    FBtnWrap.SetSelected(FTextWrap);
  end;
  if Assigned(FBtnEnc) then
  begin
    if FTextEncLabel = '' then
      FBtnEnc.SetCaption('UTF-8')
    else
      FBtnEnc.SetCaption(FTextEncLabel);
  end;
  W := 72 + 64 + 52;
  if FTextCode then
    W := W + 88 + 78;
  FTextBar.Width := W;
end;

procedure TFilePreview.UpdateTextStatus;
var
  S: string;
  Line, Col, N: Integer;
begin
  if not Assigned(FMeta) then
    Exit;
  S := FormatFileSize(FTextTotal);
  if FTextEncLabel <> '' then
    S := S + '    ' + FTextEncLabel;
  if FTextShown < FTextTotal then
    S := S + Format('    показано %s из %s',
      [FormatFileSize(FTextShown), FormatFileSize(FTextTotal)]);
  Line := 0;
  Col := 0;
  N := 0;
  if FTextCode and Assigned(FCodeView) and FCodeView.Visible then
  begin
    Line := FCodeView.CaretLine;
    Col := FCodeView.CaretCol;
    if FCodeView.HasSelection then
      N := FCodeView.SelCount;
  end
  else if Assigned(FDocView) and FDocView.Visible then
  begin
    Line := FDocView.CaretLine;
    Col := FDocView.CaretCol;
    if FDocView.HasTextSelection then
      N := FDocView.SelCount;
  end;
  if Line > 0 then
    S := S + Format('    %d:%d', [Line, Col]);
  if N > 0 then
    S := S + Format('    выделено %d', [N]);
  FMeta.Text := S;
end;

procedure TFilePreview.TextStatus(Sender: TObject);
begin
  UpdateTextStatus;
end;

procedure TFilePreview.ShowTextModel;
var
  SL: TStringList;
  I: Integer;
  Doc: TDocDocument;
  Err: string;
begin
  if Assigned(FInfo) then
    FInfo.Visible := False;
  if Assigned(FMemo) then
    FMemo.Visible := False;
  LayoutTextBar;
  if FTextCode then
  begin
    if Assigned(FDocView) then
      FDocView.Visible := False;
    if Assigned(FSheetBar) then
      FSheetBar.Visible := False;
    if Assigned(FCodeView) then
    begin
      FCodeView.Visible := True;
      FCodeView.BringToFront;
      FCodeView.SetLines(FTextLines, TextLangOfExt(FTextExt), FTextHi, FTextWrap,
        FTextMaxCols);
      FCodeView.ApplyTheme(FColors);
      if FCaptureKeys and FCodeView.CanFocus then
        FCodeView.SetFocus;
    end;
  end
  else
  begin
    if Assigned(FCodeView) then
      FCodeView.Visible := False;
    SL := TStringList.Create;
    try
      SL.Capacity := Length(FTextLines);
      for I := 0 to High(FTextLines) do
        SL.Add(FTextLines[I]);
      Doc := LoadTextDocumentFromString(SL.Text, FPath, Err);
    finally
      SL.Free;
    end;
    if Doc <> nil then
    begin
      ApplyDocument(Doc);
      if Assigned(FDoc) and Assigned(FDocView) then
      begin
        FDocView.SetSourceLines(FTextLines);
        FDocView.OnStatus := TextStatus;
      end;
    end
    else if Err <> '' then
      ShowInfo(Err);
  end;
  ShowTextChrome(True);
  UpdateTextStatus;
end;

procedure TFilePreview.AcceptTextLoad(AJob: TObject);
var
  Job: TTextLoadJob;
begin
  Job := TTextLoadJob(AJob);
  if not Job.Ok then
  begin
    ShowInfo('Не удалось прочитать текст');
    Exit;
  end;
  FTextLines := Job.Lines;
  FTextEncLabel := Job.EncLabel;
  FTextTotal := Job.Total;
  FTextShown := Job.Shown;
  FTextMaxCols := Job.MaxCols;
  FTextCode := LoadTextViewIsCode(FTextExt);
  ShowTextModel;
end;

procedure TFilePreview.StartTextLoad(const APath: string);
var
  Job: TTextLoadJob;
begin
  if APath = '' then
    Exit;
  Inc(FLoadGen);
  if FTextJob <> nil then
  begin
    TTextLoadJob(FTextJob).Preview := nil;
    FTextJob := nil;
  end;
  FTextExt := LowerCase(ExtractFileExt(APath));
  Job := TTextLoadJob.Create;
  Job.Preview := Self;
  Job.Path := APath;
  Job.Gen := FLoadGen;
  Job.Mode := FTextEnc;
  FTextJob := Job;
  ShowTextChrome(True);
  if Assigned(FInfo) then
  begin
    FInfo.Text := 'Чтение…';
    FInfo.Visible := True;
    FInfo.BringToFront;
  end;
  TThread.CreateAnonymousThread(
    procedure
    begin
      Job.Execute;
    end).Start;
end;

procedure TFilePreview.TextSheetsClick(Sender: TObject);
begin
  if not FTextCode then
    Exit;
  FTextCode := False;
  SaveTextViewIsCode(FTextExt, False);
  ShowTextModel;
end;

procedure TFilePreview.TextCodeClick(Sender: TObject);
begin
  if FTextCode then
    Exit;
  FTextCode := True;
  SaveTextViewIsCode(FTextExt, True);
  ShowTextModel;
end;

procedure TFilePreview.TextHiClick(Sender: TObject);
begin
  FTextHi := not FTextHi;
  if Assigned(FCodeView) then
    FCodeView.SetHighlight(FTextHi);
  LayoutTextBar;
end;

procedure TFilePreview.TextWrapClick(Sender: TObject);
begin
  FTextWrap := not FTextWrap;
  if Assigned(FCodeView) then
    FCodeView.SetWrap(FTextWrap);
  LayoutTextBar;
end;

procedure TFilePreview.EncUtf8Click(Sender: TObject);
begin
  FTextEnc := temUtf8;
  if FPath <> '' then
    StartTextLoad(FPath);
end;

procedure TFilePreview.EncAcpClick(Sender: TObject);
begin
  FTextEnc := temAcp;
  if FPath <> '' then
    StartTextLoad(FPath);
end;

procedure TFilePreview.Enc16Click(Sender: TObject);
begin
  FTextEnc := temUtf16;
  if FPath <> '' then
    StartTextLoad(FPath);
end;

procedure TFilePreview.TextEncClick(Sender: TObject);
begin
  if not Assigned(FEncMenu) or not Assigned(FBtnEnc) then
    Exit;
  FEncMenu.ClearItems;
  FEncMenu.AddItem('UTF-8', '', EncUtf8Click);
  FEncMenu.AddItem('ACP', '', EncAcpClick);
  FEncMenu.AddItem('UTF-16', '', Enc16Click);
  FEncMenu.ApplyTheme(FColors);
  FEncMenu.PopupNear(FBtnEnc, False);
end;

function TFilePreview.WaitWebEngine(ATimeoutMs: Cardinal): TWindowsActiveEngine;
var
  Tick: UInt64;
  Gen: Integer;
begin
  Result := TWindowsActiveEngine.None;
  if not Assigned(FWeb) then
    Exit;
  Gen := FLoadGen;
  Tick := TThread.GetTickCount64;
  repeat
    Result := FWeb.WindowsActiveEngine;
    if (Result = TWindowsActiveEngine.IE) or (Result = TWindowsActiveEngine.Edge) then
      Exit;
    Application.ProcessMessages;
    if FDestroying or (FLoadGen <> Gen) then
      Exit(TWindowsActiveEngine.None);
  until TThread.GetTickCount64 - Tick > ATimeoutMs;
  Result := FWeb.WindowsActiveEngine;
end;

{$IFDEF MSWINDOWS}
function TFilePreview.WbLoadHtmlIE(const AHtml: string): Boolean;
var
  WB: IWebBrowser2;
  SL: TStringList;
  MS: TMemoryStream;
  Tick: UInt64;
  Psi: IPersistStreamInit;
  Empty: OleVariant;
  Gen: Integer;
begin
  Result := False;
  if not Assigned(FWeb) then
    Exit;
  if not Supports(FWeb, IWebBrowser2, WB) then
    Exit;
  Empty := EmptyParam;
  WB.Navigate('about:blank', Empty, Empty, Empty, Empty);
  Gen := FLoadGen;
  Tick := TThread.GetTickCount64;
  while (WB.ReadyState < READYSTATE_INTERACTIVE) and
    (TThread.GetTickCount64 - Tick < 4000) do
  begin
    Application.ProcessMessages;
    if FDestroying or (FLoadGen <> Gen) then
      Exit;
  end;
  if not Assigned(WB.Document) then
    Exit;
  SL := TStringList.Create;
  try
    MS := TMemoryStream.Create;
    try
      SL.Text := AHtml;
      SL.SaveToStream(MS, TEncoding.UTF8);
      MS.Position := 0;
      if Supports(WB.Document, IPersistStreamInit, Psi) then
        Result := Succeeded(Psi.Load(TStreamAdapter.Create(MS)));
    finally
      MS.Free;
    end;
  finally
    SL.Free;
  end;
end;
{$ENDIF}

function TFilePreview.WbLoadHtml(const AHtml: string): Boolean;
var
  Eng: TWindowsActiveEngine;
begin
  Result := False;
  if AHtml = '' then
    Exit;
  EnsureWebBrowser;
  if not Assigned(FWeb) then
    Exit;
  FWeb.Visible := True;
  FWeb.BringToFront;
  Application.ProcessMessages;
  Eng := WaitWebEngine(5000);
  case Eng of
    TWindowsActiveEngine.Edge:
      begin
        FWeb.LoadFromStrings(AHtml, TEncoding.UTF8, 'about:blank');
        Result := True;
      end;
    TWindowsActiveEngine.IE:
      begin
        {$IFDEF MSWINDOWS}
        Result := WbLoadHtmlIE(AHtml);
        {$ENDIF}
        if not Result then
        try
          FWeb.LoadFromStrings(AHtml, TEncoding.UTF8, 'about:blank');
          Result := True;
        except
          Result := False;
        end;
      end;
  else
    try
      FWeb.LoadFromStrings(AHtml, TEncoding.UTF8, 'about:blank');
      Result := True;
    except
      Result := False;
    end;
  end;
end;

function TFilePreview.IsHtmlExt(const AExt: string): Boolean;
begin
  Result := ExtIn(LowerCase(AExt), ['.htm', '.html', '.xhtml', '.shtml',
    '.shtm', '.mht', '.mhtml']);
end;

function TFilePreview.LoadAsHtmlBrowser(const APath: string): Boolean;
var
  Eng: TWindowsActiveEngine;
  Ext, Html: string;
  FS: TFileStream;
  Buf: TBytes;
  N: Integer;
  EncName: string;

  procedure NoteEngine(AEdge: Boolean);
  var
    Why: string;
  begin
    if AEdge then
    begin
      if ExtIn(Ext, ['.mht', '.mhtml']) then
        FKindText.Text := 'MHTML'
      else
        FKindText.Text := 'HTML';
      Exit;
    end;
    FKindText.Text := 'HTML · IE';
    {$IFDEF MSWINDOWS}
    Why := WebView2BlockReason;
    if (Why <> '') and Assigned(FMeta) then
    begin
      if FMeta.Text <> '' then
        FMeta.Text := FMeta.Text + '    ' + Why
      else
        FMeta.Text := Why;
    end;
    {$ELSE}
    Why := '';
    {$ENDIF}
  end;

begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    EnsureWebBrowser;
    if not Assigned(FWeb) then
      Exit;
    FWeb.Visible := True;
    FWeb.BringToFront;
    Eng := WaitWebEngine(5000);
    if Eng = TWindowsActiveEngine.None then
      Exit;
    if (Eng = TWindowsActiveEngine.Edge) and MapHtmlFolder(ExtractFileDir(APath)) then
      FWeb.Navigate(HtmlPreviewUrl(APath))
    else
      FWeb.Navigate(FileUriForBrowser(APath));
    NoteEngine(Eng = TWindowsActiveEngine.Edge);
    Result := True;
  except
    Result := False;
  end;
  { Edge нет — старый IE, страница из строки. Относительные css/js могут не найтись. }
  {$IFDEF MSWINDOWS}
  if (not Result) and Assigned(FWeb) and
     (FWeb.WindowsActiveEngine = TWindowsActiveEngine.IE) then
  begin
    try
      FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
      try
        N := Integer(Min(Int64(2 * 1024 * 1024), FS.Size));
        SetLength(Buf, N);
        if N > 0 then
          FS.ReadBuffer(Buf[0], N);
      finally
        FS.Free;
      end;
      Html := DecodeLooseText(Buf, EncName);
      if WbLoadHtmlIE(Html) then
      begin
        FWeb.Visible := True;
        FWeb.BringToFront;
        NoteEngine(False);
        Result := True;
      end;
    except
      Result := False;
    end;
  end;
  {$ENDIF}
  if not Result then
    HideSvgWeb;
end;

function TFilePreview.LoadAsSkiaImage(const APath: string): Boolean;
var
  Ext: string;
  Img: ISkImage;
  Tmp: TBitmap;
  Bytes: TBytes;
  W, H, SrcW, SrcH: Integer;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    if ExtIn(Ext, ['.svg', '.svgz']) then
    begin
      if TryLoadSvgDom(APath, FSvgDom) then
      begin
        FSvgBox.Visible := True;
        FSvgBox.BringToFront;
        FSvgBox.Redraw;
        FKindText.Text := 'SVG';
        Exit(True);
      end;
      FSvgDom := nil;
      Exit;
    end;
    if ExtIn(Ext, ['.psd', '.psb']) then
    begin
      W := Max(400, Round(FBody.Width * 1.4));
      H := Max(400, Round(FBody.Height * 1.4));
      if W < 800 then
        W := 1600;
      if H < 600 then
        H := 1200;
      if LoadPsdPreview(APath, W, H, FImage.Bitmap, SrcW, SrcH) then
      begin
        ShowRasterImage;
        if SrcW > 0 then
          FKindText.Text := Format('%s  %d × %d',
            [UpperCase(Copy(Ext, 2, 8)), SrcW, SrcH])
        else
          FKindText.Text := Format('%d × %d',
            [FImage.Bitmap.Width, FImage.Bitmap.Height]);
        Exit(True);
      end;
      Exit(False);
    end;
    if ExtIn(Ext, ['.gif', '.webp', '.tgs', '.lottie']) or
      ((Ext = '.json') and LooksLikeLottie(APath)) then
    begin
      if LoadAsAnimated(APath) then
      begin
        if Ext = '.json' then
          FKindText.Text := 'Lottie'
        else
          FKindText.Text := UpperCase(Copy(Ext, 2, 8));
        Exit(True);
      end;
      if ExtIn(Ext, ['.tgs', '.lottie', '.json']) then
        Exit(False);
    end;
    Img := TSkImage.MakeFromEncodedFile(APath);
    if Img = nil then
    begin
      Bytes := TFile.ReadAllBytes(APath);
      if Length(Bytes) > 0 then
        Img := TSkImage.MakeFromEncoded(Bytes);
    end;
    if Img = nil then
      Exit;
    Tmp := TBitmap.CreateFromSkImage(Img);
    try
      FImage.Bitmap.Assign(Tmp);
    finally
      Tmp.Free;
    end;
    Result := (FImage.Bitmap.Width > 0) and (FImage.Bitmap.Height > 0);
    if Result then
    begin
      ShowRasterImage;
      FKindText.Text := Format('%d × %d', [FImage.Bitmap.Width, FImage.Bitmap.Height]);
    end;
  except
    Result := False;
  end;
end;

procedure TFilePreview.ShowPdfPage(AIndex: Integer; AResetView: Boolean);
var
  Bmp: TBitmap;
  W, H: Integer;
begin
  if (FPdf = nil) or (AIndex < 0) or (AIndex >= FPdf.PageCount) then
    Exit;
  if (not AResetView) and Assigned(FImage) and (FImage.Width > 32) then
  begin
    W := Max(200, Round(FImage.Width));
    H := Max(200, Round(FImage.Height));
  end
  else
  begin
    W := Max(400, Round(FBody.Width * Max(1, FPdfZoom)));
    H := Max(400, Round(FBody.Height * Max(1, FPdfZoom)));
  end;
  if W > 3200 then
    W := 3200;
  if H > 3200 then
    H := 3200;
  Bmp := FPdf.RenderPage(AIndex, W, H);
  if Bmp = nil then
    Exit;
  try
    FImage.Bitmap.Assign(Bmp);
  finally
    Bmp.Free;
  end;
  FPdfPage := AIndex;
  ShowRasterImage(AResetView);
  FKindText.Text := Format('PDF  %d / %d', [AIndex + 1, FPdf.PageCount]);
end;

function TFilePreview.LoadAsPdf(const APath: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not TPdfiumDoc.Available then
    Exit;
  if not TPdfiumDoc.LooksLikePdfFamily(APath) and
     (LowerCase(ExtractFileExt(APath)) <> '.pdf') then
    Exit;
  try
    FreeAndNil(FPdf);
    FPdf := TPdfiumDoc.Create(APath);
    if FPdf.PageCount < 1 then
    begin
      FreeAndNil(FPdf);
      Exit;
    end;
    FSheetCombo.Items.BeginUpdate;
    try
      FSheetCombo.Items.Clear;
      for I := 0 to FPdf.PageCount - 1 do
        FSheetCombo.Items.Add(Format('Страница %d', [I + 1]));
    finally
      FSheetCombo.Items.EndUpdate;
    end;
    FSheetCombo.ItemIndex := 0;
    FSheetBar.Visible := FPdf.PageCount > 1;
    ShowPdfPage(0);
    Result := FImage.Visible;
    if Result then
      ShowImageTools(True);
  except
    FreeAndNil(FPdf);
    Result := False;
  end;
end;

procedure TFilePreview.PaintFontMap(Sender: TObject; Canvas: TCanvas);
var
  Cols, Rows, I, C, R, Code: Integer;
  CellW, CellH: Single;
  Rect: TRectF;
  Ch: string;
  Codes: TArray<Integer>;
  N: Integer;
begin
  if not Assigned(FFontMap) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FFontMap.LocalRect, 0, 0, [], 1);
  N := 0;
  SetLength(Codes, 96 + 64);
  for I := 32 to 126 do
  begin
    Codes[N] := I;
    Inc(N);
  end;
  for I := $410 to $44F do
  begin
    Codes[N] := I;
    Inc(N);
  end;
  SetLength(Codes, N);
  Cols := Max(8, Trunc(FFontMap.Width / 36));
  if Cols < 1 then
    Cols := 8;
  Rows := (N + Cols - 1) div Cols;
  CellW := FFontMap.Width / Cols;
  CellH := Max(22, FFontMap.Height / Max(1, Rows));
  Canvas.Font.Family := FFontFace;
  Canvas.Font.Size := Min(22, CellH * 0.55);
  for I := 0 to N - 1 do
  begin
    C := I mod Cols;
    R := I div Cols;
    Rect := TRectF.Create(C * CellW + 1, R * CellH + 1, (C + 1) * CellW - 1, (R + 1) * CellH - 1);
    Code := Codes[I];
    Ch := Char(Code);
    Canvas.Fill.Color := FColors.ItemBackground;
    Canvas.FillRect(Rect, 3, 3, AllCorners, 1);
    Canvas.Fill.Color := FColors.TextColor;
    Canvas.FillText(Rect, Ch, False, 1, [], TTextAlign.Center, TTextAlign.Center);
  end;
end;

procedure TFilePreview.ShowMediaChrome(AAudio: Boolean);
var
  Path: string;
  Gen: Integer;
begin
  FIsAudio := AAudio;
  FIsVideo := not AAudio;
  FMediaDur := 0;
  FMediaPos := 0;
  FTrimA := 0;
  FTrimB := 0;
  FSeekDrag := 0;
  FMediaPaused := False;
  FMediaClockMs := TThread.GetTickCount;
  SetLength(FWave, 0);
  if Assigned(FMediaBar) then
    FMediaBar.Visible := True;
  if Assigned(FWaveBox) then
  begin
    FWaveBox.Visible := AAudio;
    FWaveBox.BringToFront;
  end;
{$IFDEF MSWINDOWS}
  HideHostWnd;
  if AAudio and Assigned(FMpv) then
    FMpv.SetBoundsScreen(TRect.Create(0, 0, 0, 0));
{$ENDIF}
  if Assigned(FTimeText) then
    FTimeText.Text := '00:00 / 00:00';
  if Assigned(FBtnPlay) then
  begin
    FBtnPlay.SetIcon(#$E769);
    FBtnPlay.SetCaption('Стоп');
  end;
  if Assigned(FSyncTimer) then
  begin
    FSyncTimer.Interval := 50;
    FSyncTimer.Enabled := True;
  end;
  Path := FPath;
  Gen := FLoadGen;
  if Path <> '' then
  begin
    FMediaDur := ProbeMediaDuration(Path);
{$IFDEF MSWINDOWS}
    if Assigned(FMpv) and FMpv.HasEngine then
    begin
      if FMpv.Duration > FMediaDur then
        FMediaDur := FMpv.Duration;
    end;
{$ENDIF}
    FTrimA := 0;
    if FMediaDur > 0 then
      FTrimB := FMediaDur
    else
      FTrimB := 0;
    FMediaPos := 0;
  end;
  if AAudio and (Path <> '') then
    TThread.CreateAnonymousThread(
      procedure
      var
        Peaks: TArray<Single>;
      begin
        Peaks := BuildWavePeaks(Path, 180);
        TThread.Queue(nil,
          procedure
          begin
            if (not FDestroying) and (FLoadGen = Gen) then
            begin
              FWave := Peaks;
              if Assigned(FWaveBox) then
                FWaveBox.Repaint;
            end;
          end);
      end).Start;
  UpdateMediaHud;
end;

procedure TFilePreview.HideMediaChrome;
begin
  FIsAudio := False;
  FIsVideo := False;
  FSeekDrag := 0;
  FMediaDur := 0;
  FMediaPos := 0;
  FTrimA := 0;
  FTrimB := 0;
  SetLength(FWave, 0);
  if Assigned(FMediaBar) then
    FMediaBar.Visible := False;
  if Assigned(FWaveBox) then
    FWaveBox.Visible := False;
end;

procedure TFilePreview.MediaPlayClick(Sender: TObject);
begin
  {$IFDEF MSWINDOWS}
  if not (FIsAudio or FIsVideo) then
    Exit;
  FMediaPaused := not FMediaPaused;
  if (not FMediaPaused) and (FMediaDur > 0.2) and (FMediaPos >= FMediaDur - 0.08) then
  begin
    FMediaPos := FTrimA;
    if Assigned(FMpv) then
      FMpv.Seek(FMediaPos);
  end;
  if Assigned(FMpv) then
    FMpv.SetPaused(FMediaPaused);
  if Assigned(FBtnPlay) then
    if FMediaPaused then
    begin
      FBtnPlay.SetIcon(#$E768);
      FBtnPlay.SetCaption('Старт');
    end
    else
    begin

      FBtnPlay.SetIcon(#$E769);
      FBtnPlay.SetCaption('Стоп');
      FMediaClockMs := TThread.GetTickCount;
    end;
  UpdateMediaHud;
  {$ENDIF}
end;

procedure TFilePreview.MediaSaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Src, Dst, Ext: string;
  A0, B0, Dur0: Double;
  Video: Boolean;
  Gen: Integer;
begin
  if FExporting or (FPath = '') then
    Exit;
  Src := FPath;
  if not TFile.Exists(Src) then
    Exit;
  Ext := ExtractFileExt(Src);
  Dlg := TSaveDialog.Create(Self);
  try
    if IsAudioMetaExt(LowerCase(Ext)) or FIsAudio then
    begin
      if Ext = '' then
        Ext := '.mp3';
      Dlg.Filter := 'Как исходник|*' + Ext + '|MP3|*.mp3|M4A|*.m4a|WAV|*.wav';
      Dlg.DefaultExt := Copy(Ext, 2, 8);
      Dlg.FileName := ChangeFileExt(ExtractFileName(Src), '') + '_clip' + Ext;
    end
    else
    begin
      if Ext = '' then
        Ext := '.mp4';
      Dlg.Filter := 'Как исходник|*' + Ext + '|MP4|*.mp4|MKV|*.mkv';
      Dlg.DefaultExt := Copy(Ext, 2, 8);
      Dlg.FileName := ChangeFileExt(ExtractFileName(Src), '') + '_clip' + Ext;
    end;
    if not Dlg.Execute then
      Exit;
    Dst := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  if SameText(ExpandFileName(Src), ExpandFileName(Dst)) then
    Dst := ChangeFileExt(Dst, '') + '_clip' + ExtractFileExt(Dst);
  A0 := FTrimA;
  B0 := FTrimB;
  Dur0 := FMediaDur;
  if B0 <= A0 + 0.05 then
  begin
    A0 := 0;
    B0 := Dur0;
  end;
  if B0 <= A0 then
    B0 := A0 + 0.2;
  Video := IsVideoMetaExt(LowerCase(ExtractFileExt(Src))) or FIsVideo;
  FExporting := True;
  if Assigned(FBtnSaveClip) then
    FBtnSaveClip.StartBusy;
  Gen := FLoadGen;
  TThread.CreateAnonymousThread(
    procedure
    var
      Ok: Boolean;
      Msg: string;
    begin
      Ok := False;
      Msg := '';
      try
        if (A0 <= 0.05) and (Dur0 > 0) and (B0 >= Dur0 - 0.2) then
        try
          TFile.Copy(Src, Dst, True);
          Ok := TFile.Exists(Dst);
        except
          Ok := False;
        end;
{$IFDEF MSWINDOWS}
        if not Ok then
          Ok := MpvExportClip(Src, Dst, A0, B0, Video, Msg);
{$ENDIF}
        if not Ok and (Msg = '') then
          Msg := 'Не удалось сохранить фрагмент. Нужен ffmpeg.exe в папке программы.';
      except
        on E: Exception do
        begin
          Ok := False;
          Msg := E.Message;
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          FExporting := False;
          if Assigned(FBtnSaveClip) then
            FBtnSaveClip.EndBusy;
          if (not FDestroying) and (FLoadGen = Gen) then
            if Ok then
            begin
              if Msg <> '' then
                FKindText.Text := Msg
              else
                FKindText.Text := 'Сохранено';
            end
            else if Msg <> '' then
              ShowInfo(Msg);
        end);
    end).Start;
end;

function TFilePreview.XToMediaTime(X, AWidth: Single): Double;
begin
  if (AWidth < 1) or (FMediaDur <= 0) then
    Exit(0);
  Result := EnsureRange(X / AWidth, 0, 1) * FMediaDur;
end;

procedure TFilePreview.PaintWave(Sender: TObject; Canvas: TCanvas);
var
  R, Bar: TRectF;
  I, N: Integer;
  Slot, BarW, H, Cy, Px, T: Single;
  Peak, Op: Single;
  Played: Boolean;
  Col: TAlphaColor;
begin
  R := FWaveBox.LocalRect;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(R, 0, 0, [], 1);
  N := Length(FWave);
  if N < 2 then
    Exit;
  Slot := R.Width / N;
  BarW := Max(3, Min(5, Slot * 0.72));
  Cy := R.Top + R.Height * 0.5;
  for I := 0 to N - 1 do
  begin
    Peak := FWave[I];
    H := Max(4, Peak * Min(R.Height * 0.42, 120));
    Px := R.Left + I * Slot + (Slot - BarW) * 0.5;
    Bar := TRectF.Create(Px, Cy - H * 0.5, Px + BarW, Cy + H * 0.5);
    T := 0;
    if FMediaDur > 0 then
      T := (I + 0.5) / N * FMediaDur;
    Played := (FMediaDur > 0) and (T <= FMediaPos);
    Op := 1;
    if (FMediaDur > 0) and ((T < FTrimA) or (T > FTrimB)) then
      Op := 0.28;
    if Played then
      Col := FColors.SelectionColor
    else
      Col := FColors.ControlStroke;
    Canvas.Fill.Color := Col;
    Canvas.FillRect(Bar, 1.5, 1.5, AllCorners, Op);
  end;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  if (FMediaDur > 0) and (FTrimB > FTrimA + 0.01) then
  begin
    Canvas.Stroke.Thickness := 2;
    Canvas.Stroke.Color := FColors.SelectionColor;
    Px := R.Left + (FTrimA / FMediaDur) * R.Width;
    Canvas.DrawLine(TPointF.Create(Px, R.Top), TPointF.Create(Px, R.Bottom), 1);
    Px := R.Left + (FTrimB / FMediaDur) * R.Width;
    Canvas.DrawLine(TPointF.Create(Px, R.Top), TPointF.Create(Px, R.Bottom), 1);
  end;
  if (FMediaDur > 0) and (FMediaPos > 0) then
  begin
    Canvas.Stroke.Thickness := 1.5;
    Canvas.Stroke.Color := FColors.SelectionColor;
    Px := R.Left + (FMediaPos / FMediaDur) * R.Width;
    Canvas.DrawLine(TPointF.Create(Px, R.Top), TPointF.Create(Px, R.Bottom), 1);
  end;
end;

procedure TFilePreview.PaintSeek(Sender: TObject; Canvas: TCanvas);
var
  R, Track, FillR, Hand: TRectF;
  Dur, Pos, A, B, X: Single;
  Cy: Single;
begin
  R := FSeekBox.LocalRect;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := TAlphaColors.Null;
  Canvas.FillRect(R, 0, 0, [], 1);
  Dur := FMediaDur;
  if Dur <= 0 then
    Dur := 1;
  Pos := EnsureRange(FMediaPos, 0, Dur);
  A := EnsureRange(FTrimA, 0, Dur);
  B := FTrimB;
  if B <= A then
    B := Dur;
  B := EnsureRange(B, 0, Dur);
  Cy := R.Top + R.Height * 0.5;
  Track := TRectF.Create(R.Left + 8, Cy - 3, R.Right - 8, Cy + 3);
  Canvas.Fill.Color := FColors.ControlFill;
  Canvas.FillRect(Track, 3, 3, AllCorners, 1);
  FillR := TRectF.Create(Track.Left + (A / Dur) * Track.Width, Track.Top,
    Track.Left + (B / Dur) * Track.Width, Track.Bottom);
  Canvas.Fill.Color := FColors.AccentSubtle;
  Canvas.FillRect(FillR, 3, 3, AllCorners, 1);
  FillR := TRectF.Create(Track.Left, Track.Top,
    Track.Left + (Pos / Dur) * Track.Width, Track.Bottom);
  Canvas.Fill.Color := FColors.SelectionColor;
  Canvas.FillRect(FillR, 3, 3, AllCorners, 1);
  X := Track.Left + (A / Dur) * Track.Width;
  Hand := TRectF.Create(X - 4, Cy - 10, X + 4, Cy + 10);
  Canvas.Fill.Color := FColors.TextColor;
  Canvas.FillRect(Hand, 2, 2, AllCorners, 1);
  X := Track.Left + (B / Dur) * Track.Width;
  Hand := TRectF.Create(X - 4, Cy - 10, X + 4, Cy + 10);
  Canvas.FillRect(Hand, 2, 2, AllCorners, 1);
  X := Track.Left + (Pos / Dur) * Track.Width;
  Canvas.Fill.Color := FColors.OnAccentTextColor;
  Canvas.Fill.Color := FColors.SelectionColor;
  Canvas.FillEllipse(TRectF.Create(X - 6, Cy - 6, X + 6, Cy + 6), 1);
end;

procedure TFilePreview.SeekMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  W, Dur, XA, XB, T: Double;
  Box: TPaintBox;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  Box := Sender as TPaintBox;
  W := Box.Width;
  Dur := FMediaDur;
  if Dur <= 0 then
    Dur := 1;
  XA := (FTrimA / Dur) * W;
  XB := (FTrimB / Dur) * W;
  if FTrimB <= FTrimA then
    XB := W;
  if Abs(X - XA) <= 10 then
    FSeekDrag := 2
  else if Abs(X - XB) <= 10 then
    FSeekDrag := 3
  else
    FSeekDrag := 1;
  T := XToMediaTime(X, W);
  case FSeekDrag of
    1:
      begin
        if FTrimB > FTrimA + 0.05 then
          T := EnsureRange(T, FTrimA, FTrimB);
        FMediaPos := T;
      end;
    2:
      begin
        FTrimA := EnsureRange(T, 0, Max(0, FTrimB - 0.05));
        if FMediaPos < FTrimA then
          FMediaPos := FTrimA;
      end;
    3:
      begin
        FTrimB := EnsureRange(T, FTrimA + 0.05, Dur);
        if FMediaPos > FTrimB then
          FMediaPos := FTrimB;
      end;
  end;
  Box.Repaint;
  if Assigned(FWaveBox) and FWaveBox.Visible then
    FWaveBox.Repaint;
end;

procedure TFilePreview.SeekMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  W, Dur, T: Double;
  Box: TPaintBox;
begin
  { Отпустили кнопку за окном — FMX не шлёт MouseUp контролу. }
  if FSeekDrag <> 0 then
    if not (ssLeft in Shift) then
    begin
      SeekMouseUp(Sender, TMouseButton.mbLeft, Shift, X, Y);
      Exit;
    end;
  if FSeekDrag = 0 then
    Exit;
  Box := Sender as TPaintBox;
  W := Box.Width;
  Dur := FMediaDur;
  if Dur <= 0 then
    Dur := 1;
  T := XToMediaTime(X, W);
  case FSeekDrag of
    1:
      begin
        if FTrimB > FTrimA + 0.05 then
          T := EnsureRange(T, FTrimA, FTrimB);
        FMediaPos := T;
      end;
    2:
      begin
        FTrimA := EnsureRange(T, 0, Max(0, FTrimB - 0.05));
        if FMediaPos < FTrimA then
          FMediaPos := FTrimA;
      end;
    3:
      begin
        FTrimB := EnsureRange(T, FTrimA + 0.05, Dur);
        if FMediaPos > FTrimB then
          FMediaPos := FTrimB;
      end;
  end;
  Box.Repaint;
  if Assigned(FSeekBox) then
    FSeekBox.Repaint;
  if Assigned(FWaveBox) and FWaveBox.Visible then
    FWaveBox.Repaint;
end;

procedure TFilePreview.SeekMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  W, T: Double;
  Box: TPaintBox;
begin
  if FSeekDrag = 0 then
    Exit;
  if FSeekDrag = 1 then
  begin
    if Sender is TPaintBox then
    begin
      Box := TPaintBox(Sender);
      W := Box.Width;
      T := XToMediaTime(X, W);
      if FTrimB > FTrimA + 0.05 then
        T := EnsureRange(T, FTrimA, FTrimB);
      FMediaPos := T;
    end;
{$IFDEF MSWINDOWS}
    if Assigned(FMpv) then
      FMpv.Seek(FMediaPos);
{$ENDIF}
  end
  else if FSeekDrag in [2, 3] then
  begin
    if FMediaPos < FTrimA then
      FMediaPos := FTrimA;
    if (FTrimB > 0) and (FMediaPos > FTrimB) then
      FMediaPos := FTrimB;
{$IFDEF MSWINDOWS}
    if Assigned(FMpv) then
      FMpv.Seek(FMediaPos);
{$ENDIF}
  end;
  FSeekDrag := 0;
  FPosHoldUntil := TThread.GetTickCount + 600;
  UpdateMediaHud;
end;

procedure TFilePreview.UpdateMediaHud;
var
  D, Eng: Double;
begin
  if FDestroying or not (FIsAudio or FIsVideo) then
    Exit;
  {$IFDEF MSWINDOWS}
  if Assigned(FMpv) and FMpv.HasEngine then
  begin
    D := FMpv.Duration;
    Eng := FMpv.Position;
    if (FSeekDrag = 0) and ((FPosHoldUntil = 0) or (TThread.GetTickCount >= FPosHoldUntil)) then
      FMediaPos := Eng;
    if D <= 0 then
      D := FMediaDur;
    if D <= 0 then
      D := ProbeMediaDuration(FPath);
    if D > 0 then
    begin
      FMediaDur := D;
      if FTrimB <= 0 then
        FTrimB := D;
      if FTrimB > D then
        FTrimB := D;
      if FTrimA > FTrimB then
        FTrimA := 0;
    end;
  end;
  {$ENDIF}
  if Assigned(FBtnPlay) then
    if FMediaPaused then
    begin
      FBtnPlay.SetIcon(#$E768);
      FBtnPlay.SetCaption('Старт');
    end
    else
    begin
      FBtnPlay.SetIcon(#$E769);
      FBtnPlay.SetCaption('Стоп');
    end;
  if Assigned(FTimeText) then
    FTimeText.Text := FormatMediaClock(FMediaPos) + ' / ' + FormatMediaClock(FMediaDur);
  if Assigned(FSeekBox) then
    FSeekBox.Repaint;
  if Assigned(FWaveBox) and FWaveBox.Visible then
    FWaveBox.Repaint;
end;

procedure TFilePreview.ShowImageTools(AShow: Boolean);
begin
  if Assigned(FImgBar) then
    FImgBar.Visible := AShow;
  ApplyImgView;
end;

procedure TFilePreview.EnsureWorkBitmap;
begin
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) then
    Exit;
  if FImgWork = nil then
    FImgWork := TBitmap.Create;
  if (FImgWork.Width <> FImage.Bitmap.Width) or (FImgWork.Height <> FImage.Bitmap.Height) then
    FImgWork.Assign(FImage.Bitmap);
end;

procedure TFilePreview.ShowToast(const AText: string);
begin
  if not Assigned(FToast) then
    Exit;
  FToast.Text := AText;
  FToast.Visible := True;
  FToast.BringToFront;
  if Assigned(FToastTimer) then
  begin
    FToastTimer.Enabled := False;
    FToastTimer.Enabled := True;
  end;
end;

procedure TFilePreview.ToastTick(Sender: TObject);
begin
  if Assigned(FToastTimer) then
    FToastTimer.Enabled := False;
  if Assigned(FToast) then
    FToast.Visible := False;
end;

procedure TFilePreview.MarkImgDirty;
begin
  FImgDirty := True;
end;

procedure TFilePreview.DropDirtyWork;
begin
  if FImgDirty then
    ShowToast('не сохранено');
  FImgDirty := False;
  CancelCrop;
end;

procedure TFilePreview.HideSigBanner;
begin
  FSig := isNone;
  if Assigned(FSigBar) then
    FSigBar.Visible := False;
end;

procedure TFilePreview.ShowSigBanner(ASig: TImageSig);
begin
  FSig := ASig;
  if not Assigned(FSigBar) or not Assigned(FSigText) then
    Exit;
  if ImageExtMatches(ASig, ExtractFileExt(FPath)) or (ImageSigName(ASig) = '') then
  begin
    HideSigBanner;
    Exit;
  end;
  FSigText.Text := Format('Файл похож на %s, расширение %s',
    [ImageSigName(ASig), ExtractFileExt(FPath)]);
  FSigBar.Visible := True;
end;

procedure TFilePreview.SigRenameClick(Sender: TObject);
var
  Ext, Dir, Base, Name, Dest: string;
  N: Integer;
begin
  Ext := ImageSigExt(FSig);
  if (Ext = '') or (FPath = '') then
    Exit;
  Dir := ExtractFilePath(FPath);
  Base := ChangeFileExt(ExtractFileName(FPath), '');
  Name := Base + Ext;
  N := 2;
  Dest := System.IOUtils.TPath.Combine(Dir, Name);
  while TFile.Exists(Dest) do
  begin
    Name := Format('%s (%d)%s', [Base, N, Ext]);
    Dest := System.IOUtils.TPath.Combine(Dir, Name);
    Inc(N);
  end;
  try
    TFile.Move(FPath, Dest);
  except
    ShowToast('нет прав');
    Exit;
  end;
  FImgDirty := False;
  FPath := Dest;
  HideSigBanner;
  if Assigned(FTitle) then
    FTitle.Text := ExtractFileName(Dest);
  if Assigned(FOnDiskChanged) then
    FOnDiskChanged(Self);
  ShowToast('сохранено');
end;

procedure TFilePreview.ClearIcoFrames;
begin
  if Assigned(FIcoFrames) then
    FIcoFrames.Clear;
  if Assigned(FIcoBar) then
  begin
    while FIcoBar.ControlsCount > 0 do
      FIcoBar.Controls[0].Free;
    FIcoBar.Visible := False;
  end;
  FIcoIndex := -1;
end;

procedure TFilePreview.ApplyIcoFrame(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FIcoFrames.Count) then
    Exit;
  if FImgDirty then
    ShowToast('не сохранено');
  FImgDirty := False;
  CancelCrop;
  FImage.Bitmap.Assign(FIcoFrames[AIndex]);
  if Assigned(FImgWork) then
    FImgWork.Assign(FImage.Bitmap);
  FIcoIndex := AIndex;
  FKindText.Text := Format('%d × %d', [FImage.Bitmap.Width, FImage.Bitmap.Height]);
  ResetImgView;
  ApplyImgView;
  if Assigned(FIcoBar) then
    FIcoBar.Repaint;
end;

procedure TFilePreview.IcoFrameClick(Sender: TObject);
begin
  if Sender is TControl then
    ApplyIcoFrame(TControl(Sender).Tag);
end;

procedure TFilePreview.ShowIcoStrip(const APath: string);
var
  Frames: TArray<TBitmap>;
  Labels: TArray<string>;
  I: Integer;
  Cell: TLayout;
  Img: TImage;
  Cap: TText;
begin
  ClearIcoFrames;
  if not LoadIcoFrames(APath, Frames, Labels) then
    Exit;
  for I := 0 to High(Frames) do
    FIcoFrames.Add(Frames[I]);
  if FIcoFrames.Count <= 1 then
  begin
    if FIcoFrames.Count = 1 then
    begin
      FImage.Bitmap.Assign(FIcoFrames[0]);
      ShowRasterImage;
    end;
    Exit;
  end;
  for I := 0 to FIcoFrames.Count - 1 do
  begin
    Cell := TLayout.Create(FIcoBar);
    Cell.Parent := FIcoBar;
    Cell.Align := TAlignLayout.Left;
    Cell.Width := 56;
    Cell.HitTest := True;
    Cell.Tag := I;
    Cell.OnClick := IcoFrameClick;
    Img := TImage.Create(Cell);
    Img.Parent := Cell;
    Img.Align := TAlignLayout.Top;
    Img.Height := 40;
    Img.HitTest := False;
    Img.WrapMode := TImageWrapMode.Fit;
    Img.Bitmap.Assign(FIcoFrames[I]);
    Cap := TText.Create(Cell);
    Cap.Parent := Cell;
    Cap.Align := TAlignLayout.Client;
    Cap.HitTest := False;
    Cap.Text := Labels[I];
    ApplyFluentText(Cap, 10, False);
    Cap.TextSettings.HorzAlign := TTextAlign.Center;
  end;
  FIcoBar.Visible := True;
  ApplyIcoFrame(FIcoFrames.Count - 1);
end;

procedure TFilePreview.ImgFitClick(Sender: TObject);
begin
  FImgUserZoom := 1;
  FImgPan := TPointF.Zero;
  FSvgZoom := 1;
  FSvgPan := TPointF.Zero;
  FPdfZoom := 1;
  if Assigned(FPdf) then
    ShowPdfPage(FPdfPage);
  ApplyImgView;
  if Assigned(FSvgBox) and FSvgBox.Visible then
    FSvgBox.Redraw;
end;

procedure TFilePreview.Img100Click(Sender: TObject);
var
  Fit: Single;
begin
  if ImgViewActive then
  begin
    Fit := Min(FImgHost.Width / FImage.Bitmap.Width, FImgHost.Height / FImage.Bitmap.Height);
    if Fit > 0 then
      FImgUserZoom := 1 / Fit;
    ApplyImgView;
  end;
  if Assigned(FSvgBox) and FSvgBox.Visible then
  begin
    FSvgZoom := 4;
    FSvgBox.Redraw;
  end;
end;

procedure TFilePreview.ImgFlipClick(Sender: TObject);
var
  Src, Dst: TBitmap;
  Vertical: Boolean;
begin
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) then
    Exit;
  Vertical := (Sender is TControl) and (TControl(Sender).Tag = 1);
  Src := FImage.Bitmap;
  Dst := TBitmap.Create(Src.Width, Src.Height);
  try
    Dst.SkiaDraw(
      procedure(const C: ISkCanvas)
      begin
        if Vertical then
        begin
          C.Translate(0, Dst.Height);
          C.Scale(1, -1);
        end
        else
        begin
          C.Translate(Dst.Width, 0);
          C.Scale(-1, 1);
        end;
        C.DrawImage(Src.ToSkImage, 0, 0);
      end);
    FImage.Bitmap.Assign(Dst);
    if Assigned(FImgWork) then
      FImgWork.Assign(FImage.Bitmap);
    MarkImgDirty;
    ApplyImgView;
  finally
    Dst.Free;
  end;
end;

procedure TFilePreview.CancelCrop;
begin
  FCropping := False;
  FCropDrag := False;
  if Assigned(FCropPaint) then
  begin
    FCropPaint.Visible := False;
    FCropPaint.Repaint;
  end;
end;

procedure TFilePreview.ApplyCrop;
var
  R, ImgR, SrcR: TRectF;
  Dst: TBitmap;
  W, H: Integer;
begin
  if not FCropping or not ImgViewActive then
  begin
    CancelCrop;
    Exit;
  end;
  R.Left := Min(FCropA.X, FCropB.X);
  R.Top := Min(FCropA.Y, FCropB.Y);
  R.Right := Max(FCropA.X, FCropB.X);
  R.Bottom := Max(FCropA.Y, FCropB.Y);
  ImgR := FImage.BoundsRect;
  R.Left := Max(R.Left, ImgR.Left);
  R.Top := Max(R.Top, ImgR.Top);
  R.Right := Min(R.Right, ImgR.Right);
  R.Bottom := Min(R.Bottom, ImgR.Bottom);
  if (R.Width < 4) or (R.Height < 4) then
  begin
    CancelCrop;
    Exit;
  end;
  SrcR := TRectF.Create(
    (R.Left - ImgR.Left) / ImgR.Width * FImage.Bitmap.Width,
    (R.Top - ImgR.Top) / ImgR.Height * FImage.Bitmap.Height,
    (R.Right - ImgR.Left) / ImgR.Width * FImage.Bitmap.Width,
    (R.Bottom - ImgR.Top) / ImgR.Height * FImage.Bitmap.Height);
  W := Max(1, Round(SrcR.Width));
  H := Max(1, Round(SrcR.Height));
  Dst := TBitmap.Create(W, H);
  try
    Dst.SkiaDraw(
      procedure(const C: ISkCanvas)
      begin
        C.Translate(-SrcR.Left, -SrcR.Top);
        C.DrawImage(FImage.Bitmap.ToSkImage, 0, 0);
      end);
    FImage.Bitmap.Assign(Dst);
    if Assigned(FImgWork) then
      FImgWork.Assign(FImage.Bitmap);
  finally
    Dst.Free;
  end;
  MarkImgDirty;
  FKindText.Text := Format('%d × %d', [FImage.Bitmap.Width, FImage.Bitmap.Height]);
  CancelCrop;
  ResetImgView;
  ApplyImgView;
end;

procedure TFilePreview.CropPaint(Sender: TObject; Canvas: TCanvas);
var
  R: TRectF;
begin
  if not FCropping then
    Exit;
  R.Left := Min(FCropA.X, FCropB.X);
  R.Top := Min(FCropA.Y, FCropB.Y);
  R.Right := Max(FCropA.X, FCropB.X);
  R.Bottom := Max(FCropA.Y, FCropB.Y);
  Canvas.Stroke.Color := FColors.SelectionColor;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(R, 0, 0, [], 1);
end;

procedure TFilePreview.CropMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if not FCropping or (Button <> TMouseButton.mbLeft) then
    Exit;
  FCropDrag := True;
  FCropA := TPointF.Create(X, Y);
  FCropB := FCropA;
  if Assigned(FCropPaint.Root) then
    FCropPaint.Root.Captured := FCropPaint;
  FCropPaint.Repaint;
end;

procedure TFilePreview.CropMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if not FCropDrag then
    Exit;
  FCropB := TPointF.Create(X, Y);
  FCropPaint.Repaint;
end;

procedure TFilePreview.CropMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FCropDrag := False;
  if Assigned(FCropPaint) and Assigned(FCropPaint.Root) and
     Assigned(FCropPaint.Root.Captured) and
     (FCropPaint.Root.Captured.GetObject = FCropPaint) then
    FCropPaint.Root.Captured := nil;
end;

procedure TFilePreview.ImgCropClick(Sender: TObject);
begin
  if not ImgViewActive then
    Exit;
  FCropping := True;
  FCropA := TPointF.Create(FImage.Position.X + 8, FImage.Position.Y + 8);
  FCropB := TPointF.Create(FImage.Position.X + FImage.Width - 8,
    FImage.Position.Y + FImage.Height - 8);
  FCropPaint.Visible := True;
  FCropPaint.BringToFront;
  FCropPaint.Repaint;
  if CanFocus then
    SetFocus;
end;

procedure TFilePreview.SizeLockChange(Sender: TObject);
var
  N: Integer;
begin
  if (FSizeLock = nil) or (FSizeLock.Tag = 1) or not FSizeLock.IsChecked then
    Exit;
  if FSizeRatio <= 0 then
    Exit;
  FSizeLock.Tag := 1;
  try
    if Sender = FSizeW then
    begin
      N := StrToIntDef(FSizeW.Text, 0);
      if N > 0 then
        FSizeH.Text := IntToStr(Max(1, Round(N / FSizeRatio)));
    end
    else if Sender = FSizeH then
    begin
      N := StrToIntDef(FSizeH.Text, 0);
      if N > 0 then
        FSizeW.Text := IntToStr(Max(1, Round(N * FSizeRatio)));
    end;
  finally
    FSizeLock.Tag := 0;
  end;
end;

procedure TFilePreview.SizeCancelClick(Sender: TObject);
begin
  if Assigned(FSizeBox) then
    FSizeBox.Visible := False;
end;

procedure TFilePreview.SizeOkClick(Sender: TObject);
var
  Nw, Nh: Integer;
  Dst: TBitmap;
  Sx, Sy: Single;
begin
  Nw := StrToIntDef(FSizeW.Text, 0);
  Nh := StrToIntDef(FSizeH.Text, 0);
  if (Nw < 1) or (Nh < 1) or (Nw > 16000) or (Nh > 16000) then
    Exit;
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) then
    Exit;
  Dst := TBitmap.Create(Nw, Nh);
  try
    Sx := Nw / FImage.Bitmap.Width;
    Sy := Nh / FImage.Bitmap.Height;
    Dst.SkiaDraw(
      procedure(const C: ISkCanvas)
      begin
        C.Scale(Sx, Sy);
        C.DrawImage(FImage.Bitmap.ToSkImage, 0, 0);
      end);
    FImage.Bitmap.Assign(Dst);
    if Assigned(FImgWork) then
      FImgWork.Assign(FImage.Bitmap);
  finally
    Dst.Free;
  end;
  MarkImgDirty;
  FKindText.Text := Format('%d × %d', [Nw, Nh]);
  FSizeBox.Visible := False;
  ResetImgView;
  ApplyImgView;
end;

procedure TFilePreview.ImgIcoClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) then
    Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'ICO|*.ico';
    Dlg.DefaultExt := 'ico';
    Dlg.FileName := ChangeFileExt(ExtractFileName(FPath), '.ico');
    Dlg.InitialDir := ExtractFilePath(FPath);
    if not Dlg.Execute then
      Exit;
    if SaveMultiIco(FImage.Bitmap, Dlg.FileName) then
    begin
      FImgDirty := False;
      ShowToast('сохранено');
      if Assigned(FOnDiskChanged) then
        FOnDiskChanged(Self);
    end
    else
      ShowToast('не удалось записать');
  finally
    Dlg.Free;
  end;
end;

function TFilePreview.HandleImageKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
  if not FCropping then
    Exit;
  if Key = vkReturn then
  begin
    ApplyCrop;
    Key := 0;
    Result := True;
  end
  else if Key = vkEscape then
  begin
    CancelCrop;
    Key := 0;
    Result := True;
  end;
end;

procedure TFilePreview.SvgWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  if not Assigned(FSvgBox) or not FSvgBox.Visible or (WheelDelta = 0) then
    Exit;
  Handled := True;
  FSvgZoom := FSvgZoom * Power(1.2, WheelDelta / 120);
  if FSvgZoom < 0.2 then
    FSvgZoom := 0.2;
  if FSvgZoom > 16 then
    FSvgZoom := 16;
  FSvgBox.Redraw;
end;

procedure TFilePreview.ImgRotate(AClockwise: Boolean);
var
  Src, Dst: TBitmap;
  Deg: Single;
begin
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) then
    Exit;
  Src := FImage.Bitmap;
  Dst := TBitmap.Create(Src.Height, Src.Width);
  try
    if AClockwise then
      Deg := 90
    else
      Deg := -90;
    Dst.SkiaDraw(
      procedure(const C: ISkCanvas)
      begin
        if AClockwise then
        begin
          C.Translate(Dst.Width, 0);
          C.Rotate(Deg);
        end
        else
        begin
          C.Translate(0, Dst.Height);
          C.Rotate(Deg);
        end;
        C.DrawImage(Src.ToSkImage, 0, 0);
      end);
    FImage.Bitmap.Assign(Dst);
    if Assigned(FImgWork) then
      FImgWork.Assign(FImage.Bitmap);
    MarkImgDirty;
    FKindText.Text := Format('%d × %d', [FImage.Bitmap.Width, FImage.Bitmap.Height]);
    ResetImgView;
    ApplyImgView;
  finally
    Dst.Free;
  end;
end;

procedure TFilePreview.ImgRotLClick(Sender: TObject);
begin
  ImgRotate(False);
end;

procedure TFilePreview.ImgRotRClick(Sender: TObject);
begin
  ImgRotate(True);
end;

procedure TFilePreview.ImgResizeClick(Sender: TObject);
begin
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) or not Assigned(FSizeBox) then
    Exit;
  if FImage.Bitmap.Height > 0 then
    FSizeRatio := FImage.Bitmap.Width / FImage.Bitmap.Height
  else
    FSizeRatio := 1;
  FSizeLock.Tag := 1;
  FSizeW.Text := IntToStr(FImage.Bitmap.Width);
  FSizeH.Text := IntToStr(FImage.Bitmap.Height);
  FSizeLock.Tag := 0;
  FSizeBox.Visible := True;
end;

function TFilePreview.SaveSvgPdf(const APath: string): Boolean;
var
  Stream: TFileStream;
  Doc: ISkDocument;
  Canvas: ISkCanvas;
  Intr: TSizeF;
  VB: TRectF;
begin
  Result := False;
  if not Assigned(FSvgDom) then
    Exit;
  Intr := FSvgDom.Root.GetIntrinsicSize(TSizeF.Create(800, 1100));
  if (Intr.Width < 1) or (Intr.Height < 1) then
  begin
    if FSvgDom.Root.TryGetViewBox(VB) and (VB.Width > 1) then
      Intr := TSizeF.Create(VB.Width, VB.Height)
    else
      Intr := TSizeF.Create(800, 1100);
  end;
  try
    Stream := TFileStream.Create(APath, fmCreate);
    try
      Doc := TSkDocument.MakePDF(Stream);
      if Doc = nil then
        Exit;
      Canvas := Doc.BeginPage(Intr.Width, Intr.Height);
      FSvgDom.SetContainerSize(Intr);
      FSvgDom.Render(Canvas);
      Doc.EndPage;
      Doc.Close;
      Result := True;
    finally
      Stream.Free;
    end;
  except
    Result := False;
    if TFile.Exists(APath) then
      try
        TFile.Delete(APath);
      except
      end;
  end;
end;

procedure TFilePreview.ImgSaveAsClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Ext: string;
  Fmt: TSkEncodedImageFormat;
  Img: ISkImage;
begin
  if Assigned(FSvgBox) and FSvgBox.Visible and Assigned(FSvgDom) and
     ((not Assigned(FImage)) or (FImage.Bitmap.Width < 1)) then
  begin
    Dlg := TSaveDialog.Create(Self);
    try
      Dlg.Filter := 'PDF|*.pdf';
      Dlg.DefaultExt := 'pdf';
      Dlg.FileName := ChangeFileExt(ExtractFileName(FPath), '.pdf');
      Dlg.InitialDir := ExtractFilePath(FPath);
      if not Dlg.Execute then
        Exit;
      if SaveSvgPdf(Dlg.FileName) then
      begin
        ShowToast('сохранено');
        if Assigned(FOnDiskChanged) then
          FOnDiskChanged(Self);
      end
      else
        ShowToast('PDF (растр) не записан');
    finally
      Dlg.Free;
    end;
    Exit;
  end;
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) then
    Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'PNG|*.png|JPEG|*.jpg|WEBP|*.webp|BMP|*.bmp';
    Dlg.DefaultExt := 'png';
    Dlg.FileName := ChangeFileExt(ExtractFileName(FPath), '.png');
    if not Dlg.Execute then
      Exit;
    Ext := LowerCase(ExtractFileExt(Dlg.FileName));
    if Ext = '.jpg' then
      Fmt := TSkEncodedImageFormat.JPEG
    else if Ext = '.webp' then
      Fmt := TSkEncodedImageFormat.WEBP
    else if Ext = '.bmp' then
      Fmt := TSkEncodedImageFormat.BMP
    else
      Fmt := TSkEncodedImageFormat.PNG;
    Img := FImage.Bitmap.ToSkImage;
    if (Img <> nil) and Img.EncodeToFile(Dlg.FileName, Fmt, 90) then
    begin
      FImgDirty := False;
      ShowToast('сохранено');
      if Assigned(FOnDiskChanged) then
        FOnDiskChanged(Self);
    end
    else
      ShowToast('не удалось записать');
  finally
    Dlg.Free;
  end;
end;

{$IFDEF MSWINDOWS}
procedure TFilePreview.EnsureHostWnd;
var
  Form: TCommonCustomForm;
  ParentWnd: HWND;
begin
  if (FHostWnd <> 0) and IsWindow(FHostWnd) then
    Exit;
  FHostWnd := 0;
  Form := nil;
  if Assigned(Root) and (Root.GetObject is TCommonCustomForm) then
    Form := TCommonCustomForm(Root.GetObject);
  if Form = nil then
    Exit;
  ParentWnd := FormToHWND(Form);
  if ParentWnd = 0 then
    Exit;
  { Дочернее окно формы — в него MFPlay рисует кадры (внутри QV). }
  FHostWnd := CreateWindowEx(
    0,
    'STATIC',
    nil,
    WS_CHILD or WS_CLIPSIBLINGS or WS_CLIPCHILDREN or WS_VISIBLE,
    0, 0, 16, 16,
    ParentWnd,
    0,
    HInstance,
    nil);
  if FHostWnd <> 0 then
  begin
    ShowWindow(FHostWnd, SW_HIDE);
    EnableWindow(FHostWnd, False); { клики идут в FMX }
  end;
end;

procedure TFilePreview.HideHostWnd;
begin
  if FHostWnd <> 0 then
    ShowWindow(FHostWnd, SW_HIDE);
  FSyncTimer.Enabled := False;
  FUsingNative := False;
end;

procedure TFilePreview.UnloadNative;
begin
  if Assigned(FHandler) then
  try
    FHandler.Unload;
  except
  end;
  FHandler := nil;
  if not FUsingMpv then
    HideHostWnd;
end;

procedure TFilePreview.StopMpv;
begin
  FUsingMpv := False;
  if Assigned(FMpv) then
  try
    FMpv.Stop;
  except
  end;
end;

function TFilePreview.StartMpv(const APath: string; AVideo: Boolean): Boolean;
var
  Form: TCommonCustomForm;
  OwnerWnd: HWND;
begin
  Result := False;
{$IFDEF MSWINDOWS}
  Form := nil;
  if Assigned(Root) and (Root.GetObject is TCommonCustomForm) then
    Form := TCommonCustomForm(Root.GetObject);
  if Form = nil then
    Exit;
  OwnerWnd := FormToHWND(Form);
  if OwnerWnd = 0 then
    Exit;
  if FMpv = nil then
    FMpv := TMpvSession.Create;
  FMpv.Attach(OwnerWnd);
  FUsingMpv := True;
  FIsVideo := AVideo;
  FIsAudio := not AVideo;
  if AVideo then
    { POPUP поверх QV — движущееся видео }
  else
    HideHostWnd;
  if not FMpv.LoadFile(APath, AVideo) then
  begin
    FUsingMpv := False;
    FIsVideo := False;
    FIsAudio := False;
    FMpv.Stop;
    Exit;
  end;
  FSyncTimer.Enabled := True;
  if AVideo then
    SyncHostWnd;
  Result := True;
{$ENDIF}
end;

procedure TFilePreview.SyncHostWnd;
var
  Form: TCommonCustomForm;
  R: TRectF;
  P1, P2, S1, S2: TPointF;
  WR: TRect;
  ParentWnd: HWND;
  Pt: TPoint;
  ScreenR: TRect;
begin
  if not Assigned(FBody) then
    Exit;
  if Assigned(Root) and (Root.GetObject is TCommonCustomForm) then
    Form := TCommonCustomForm(Root.GetObject)
  else
    Exit;
  ParentWnd := FormToHWND(Form);
  if ParentWnd = 0 then
    Exit;
  R := FBody.AbsoluteRect;
  if Assigned(FMediaBar) and FMediaBar.Visible then
    R.Bottom := R.Bottom - FMediaBar.Height;
  P1 := TPointF.Create(R.Left, R.Top);
  P2 := TPointF.Create(R.Right, R.Bottom);
  S1 := Form.ClientToScreen(P1);
  S2 := Form.ClientToScreen(P2);
  ScreenR := TRect.Create(Round(S1.X), Round(S1.Y), Round(S2.X), Round(S2.Y));

{$IFDEF MSWINDOWS}
  { Видео — дочернее окно формы, прямоугольник в экранных координатах области превью }
  if FUsingMpv and FIsVideo and Assigned(FMpv) and (not FDestroying) then
  begin
    if Visible and ParentedVisible and (ScreenR.Width > 8) and (ScreenR.Height > 8) then
      FMpv.SetBoundsScreen(ScreenR)
    else
      FMpv.SetBoundsScreen(TRect.Create(0, 0, 0, 0));
  end;
{$ENDIF}

  if FHostWnd = 0 then
    Exit;
  if not FUsingNative then
  begin
    ShowWindow(FHostWnd, SW_HIDE);
    Exit;
  end;
  Pt := TPoint.Create(Round(S1.X), Round(S1.Y));
  Winapi.Windows.ScreenToClient(ParentWnd, Pt);
  WR := TRect.Create(Pt.X, Pt.Y, Pt.X + Max(8, Round(S2.X - S1.X)),
    Pt.Y + Max(8, Round(S2.Y - S1.Y)));
  if FDestroying or (WR.Width < 8) or (WR.Height < 8) then
    Exit;
  try
    SetWindowPos(FHostWnd, HWND_TOP, WR.Left, WR.Top, WR.Width, WR.Height,
      SWP_NOACTIVATE or SWP_SHOWWINDOW);
    if Assigned(FHandler) then
    begin
      WR := TRect.Create(0, 0, WR.Width, WR.Height);
      FHandler.SetRect(WR);
    end;
  except
  end;
end;

function TFilePreview.LoadNativePreview(const APath: string): Boolean;
var
  Ext: string;
  Buf: array[0..511] of Char;
  Len: DWORD;
  Cls: TCLSID;
  InitF: IInitializeWithFile;
  InitI: IInitializeWithItem;
  InitS: IInitializeWithStream;
  Item: IShellItem;
  FS: TFileStream;
  Stm: IStream;
  R: TRect;
  Hr: HResult;
begin
  Result := False;
  UnloadNative;
  Ext := ExtractFileExt(APath);
  if Ext = '' then
    Exit;
  Len := Length(Buf);
  if Failed(AssocQueryString(ASSOCF_NOTRUNCATE, ASSOCSTR(16),
    PChar(Ext), PChar(PreviewHandlerIID), Buf, @Len)) then
    Exit;
  if Failed(CLSIDFromString(Buf, Cls)) then
    Exit;
  EnsureHostWnd;
  if FHostWnd = 0 then
    Exit;
  Hr := CoCreateInstance(Cls, nil, CLSCTX_INPROC_SERVER or CLSCTX_LOCAL_SERVER,
    IPreviewHandler, FHandler);
  if Failed(Hr) or (FHandler = nil) then
    Exit;
  if Supports(FHandler, IInitializeWithFile, InitF) then
  begin
    if Failed(InitF.Initialize(PWideChar(APath), STGM_READ)) then
    begin
      UnloadNative;
      Exit;
    end;
  end
  else if Supports(FHandler, IInitializeWithItem, InitI) then
  begin
    if Failed(SHCreateItemFromParsingName(PChar(APath), nil, IShellItem, Item)) or
       Failed(InitI.Initialize(Item, STGM_READ)) then
    begin
      UnloadNative;
      Exit;
    end;
  end
  else if Supports(FHandler, IInitializeWithStream, InitS) then
  begin
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    Stm := TStreamAdapter.Create(FS, soOwned);
    if Failed(InitS.Initialize(Stm, STGM_READ)) then
    begin
      UnloadNative;
      Exit;
    end;
  end
  else
  begin
    UnloadNative;
    Exit;
  end;
  FUsingNative := True;
  ShowWindow(FHostWnd, SW_SHOW);
  SyncHostWnd;
  R := TRect.Create(0, 0, 100, 100);
  FHandler.SetWindow(FHostWnd, R);
  SyncHostWnd;
  if Failed(FHandler.DoPreview) then
  begin
    UnloadNative;
    Exit;
  end;
  FSyncTimer.Enabled := True;
  Result := True;
end;
{$ENDIF}

function ReadPreviewStamp(const APath: string; out AAge: TDateTime; out ASize: Int64): Boolean;
begin
  Result := False;
  AAge := 0;
  ASize := 0;
  if APath = '' then
    Exit;
  try
    if TDirectory.Exists(APath) then
    begin
      AAge := TDirectory.GetLastWriteTime(APath);
      Result := True;
    end
    else if TFile.Exists(APath) then
    begin
      AAge := TFile.GetLastWriteTime(APath);
      ASize := TFile.GetSize(APath);
      Result := True;
    end;
  except
  end;
end;

function SamePreviewStamp(const AAge, BAge: TDateTime; ASize, BSize: Int64): Boolean;
begin
  Result := (ASize = BSize) and (Abs(AAge - BAge) < (0.2 / 86400.0));
end;

procedure TFilePreview.DoLoad(const APath: string);
var
  Local, Ext: string;
  Kind: Integer;
  IsDir: Boolean;
  Age: TDateTime;
  Sz: Int64;
  HaveStamp: Boolean;
begin
  try
  Inc(FLoadGen);
  HaveStamp := ReadPreviewStamp(APath, Age, Sz);
  if SameText(APath, FPath) and (APath <> '') and not AnimIsPlaying and
     HaveStamp and SamePreviewStamp(Age, FStampAge, Sz, FStampSize) then
    Exit;
  if FImgDirty and not SameText(APath, FPath) then
    ShowToast('не сохранено');
  FImgDirty := False;
  try
    HideViewers;
  except
    StopAnim;
  end;
  Local := APath;
  FPath := APath;
  FStampAge := Age;
  FStampSize := Sz;
  if APath = '' then
  begin
    FTitle.Text := 'Просмотр';
    ShowInfo('Нет файла для просмотра');
    Exit;
  end;

  if (not TFile.Exists(Local)) and (not TDirectory.Exists(Local)) then
    MaterializeFile(APath, Local);

  FTitle.Text := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  ShowMeta(Local);
  IsDir := TDirectory.Exists(Local);

  if IsDir then
  begin
    FKindText.Text := 'Папка';
    if not LoadAsThumb(Local) then
      ShowInfo('Папка' + sLineBreak + Local);
    Exit;
  end;

  if not TFile.Exists(Local) then
  begin
    ShowInfo('Файл недоступен для просмотра');
    Exit;
  end;

  if IsOfficeLockFile(Local) then
  begin
    ShowInfo('Служебный файл Office (~$).' + sLineBreak +
      'Его создаёт Excel/Word, пока документ открыт.' + sLineBreak +
      'Это не таблица и не документ.');
    FKindText.Text := 'Lock';
    Exit;
  end;

  Ext := LowerCase(ExtractFileExt(Local));
  FSig := SniffImageFile(Local);
  if FSig = isPe then
  begin
    ShowInfo('Это не изображение.' + sLineBreak + 'Похоже на ' + ImageSigName(FSig));
    ShowSigBanner(FSig);
    Exit;
  end;
  if FSig = isPdf then
  begin
    if LoadAsPdf(Local) then
    begin
      ShowSigBanner(FSig);
      Exit;
    end;
  end
  else if FSig in [isJpeg, isPng, isGif, isWebp, isBmp, isIco, isCur, isSvg,
    isHeic, isAvif, isJxl] then
  begin
    if LoadAsImage(Local) then
    begin
      ShowSigBanner(FSig);
      Exit;
    end;
    if FSig in [isHeic, isAvif, isJxl] then
    begin
      if not LoadAsThumb(Local) then
        ShowInfo('Нет кодека ' + ImageSigName(FSig));
      FKindText.Text := 'Нет кодека ' + ImageSigName(FSig);
      Exit;
    end;
  end;
  Kind := ClassifyExt(Ext);

  if Kind = PK_IMAGE then
  begin
    if LoadAsImage(Local) then
      Exit;
    if (Ext = '.svg') or (Ext = '.svgz') then
      if LoadAsText(Local) then
        Exit;
  end
  else if Kind = PK_TEXT then
  begin
    if IsHtmlExt(Ext) then
    begin
      ShowHtmlMode(True);
      if FHtmlShowSource then
      begin
        FTextEnc := temAuto;
        StartTextLoad(Local);
        Exit;
      end
      else if LoadAsHtmlBrowser(Local) then
        Exit
      else if LoadAsText(Local) then
      begin
        if ExtIn(Ext, ['.mht', '.mhtml']) then
          FKindText.Text := 'MHTML'
        else
          FKindText.Text := 'HTML';
        if Assigned(FMeta) and (FMeta.Text <> '') then
          FMeta.Text := FMeta.Text + '    страница не открылась, исходник'
        else if Assigned(FMeta) then
          FMeta.Text := 'страница не открылась, исходник';
        Exit;
      end;
    end;
    if (Ext = '.json') and LoadAsSkiaImage(Local) then
      Exit;
    FTextEnc := temAuto;
    StartTextLoad(Local);
    Exit;
  end
  else if Kind = PK_MEDIA then
  begin
    if LoadAsMedia(Local) then
      Exit;
    if LoadAsThumb(Local) then
    begin
      FKindText.Text := 'Медиа';
      Exit;
    end;
  end
  else if Kind = PK_FONT then
  begin
    if LoadAsFont(Local) then
      Exit;
  end
  else if Kind = PK_ARCHIVE then
  begin
    {$IFDEF MSWINDOWS}
     if (Ext = '.pptx') or (Ext = '.ppt') or (Ext = '.pptm') or (Ext = '.ppsx') then
      if LoadNativePreview(Local) then
      begin
         FKindText.Text := 'Презентация';
        Exit;
      end;
    {$ENDIF}
    if LoadAsArchive(Local) then
      Exit;
  end
  else if Kind = PK_PDF then
  begin
    if LoadAsPdf(Local) then
      Exit;
    {$IFDEF MSWINDOWS}
    if LoadNativePreview(Local) then
    begin
      FKindText.Text := 'PDF';
      Exit;
    end;
    {$ENDIF}
    if LoadAsThumb(Local) then
    begin
      FKindText.Text := 'PDF';
      Exit;
    end;
    ShowInfo('Не удалось открыть PDF. Положите pdfium.dll рядом с программой.');
    FKindText.Text := 'PDF';
    Exit;
  end

  else if Kind = PK_TABLE then
  {
  begin
    StartHeavyLoad(Local, PK_TABLE);
    Exit;
  end
   }
   //___________________________________________________________________________
  begin
    // Если это современный формат или текст - используем наш быстрый метод
    if MatchText(Ext, ['.xlsx', '.xlsm', '.csv', '.tsv']) then
    begin
      StartHeavyLoad(Local, PK_TABLE);
      Exit;
    end
    else
    begin
      // Для старых .XLS и .XLSB используем только Проводник (Native)
      {$IFDEF MSWINDOWS}
      if LoadNativePreview(Local) then
      begin
        FKindText.Text := 'Таблица (Legacy)';
        Exit;
      end;
      {$ENDIF}
    end;
  end

  //___________________________________________________________________________

  else if Kind = PK_DOC then
  begin
    if IsDocumentFile(Local) then
    begin
      StartHeavyLoad(Local, PK_DOC);
      Exit;
    end;
    if IsExcelExt(Ext) then
    begin
      StartHeavyLoad(Local, PK_TABLE);
      Exit;
    end;
    {$IFDEF MSWINDOWS}
    if LoadNativePreview(Local) then
    begin
      FKindText.Text := 'Документ';
      Exit;
    end;
    {$ENDIF}
    if LoadAsThumb(Local) then
    begin
      FKindText.Text := 'Документ';
      Exit;
    end;
  end;

  {$IFDEF MSWINDOWS}
  if not IsExcelExt(Ext) then
    if LoadNativePreview(Local) then
    begin
      FKindText.Text := UpperCase(Copy(Ext, 2, 8));
      Exit;
    end;
  {$ENDIF}

  if LoadAsThumb(Local) then
  begin
    FKindText.Text := UpperCase(Copy(Ext, 2, 8));
    Exit;
  end;
  if IsListedTextExt(Ext) or LooksLikeText(Local) then
  begin
    FTextEnc := temAuto;
    StartTextLoad(Local);
    Exit;
  end;
  if LoadAsHex(Local) then
    Exit;
  ShowInfo('Нет обработчика для ' + Ext);
  finally
    if FCaptureKeys then
      FocusViewer;
  end;
end;

procedure TFilePreview.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Color := AColors.PanelBackground;
  if Assigned(FHeader) then
    FHeader.Fill.Color := AColors.HeaderBackground;
  if Assigned(FTitle) then
    FTitle.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FKindText) then
    FKindText.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FMeta) then
    FMeta.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FInfo) then
    FInfo.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FFontSample) then
    FFontSample.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnClose) then
    FBtnClose.ApplyTheme(AColors);
  if Assigned(FBtnHtmlPage) then
    FBtnHtmlPage.ApplyTheme(AColors);
  if Assigned(FBtnHtmlSrc) then
    FBtnHtmlSrc.ApplyTheme(AColors);
  UpdateHtmlModeButtons;
  if Assigned(FBtnEnc) then
    FBtnEnc.ApplyTheme(AColors);
  if Assigned(FBtnSheets) then
    FBtnSheets.ApplyTheme(AColors);
  if Assigned(FBtnCode) then
    FBtnCode.ApplyTheme(AColors);
  if Assigned(FBtnHi) then
    FBtnHi.ApplyTheme(AColors);
  if Assigned(FBtnWrap) then
    FBtnWrap.ApplyTheme(AColors);
  if Assigned(FEncMenu) then
    FEncMenu.ApplyTheme(AColors);
  if Assigned(FCodeView) then
    FCodeView.ApplyTheme(AColors);
  LayoutTextBar;
  if Assigned(FMemo) then
  begin
    FMemo.TextSettings.FontColor := AColors.TextColor;
    FMemo.TextSettings.Font.Family := 'Consolas';
  end;
  if Assigned(FMemoVScroll) then
    FMemoVScroll.ApplyTheme(AColors);
  if Assigned(FMemoHScroll) then
    FMemoHScroll.ApplyTheme(AColors);
  if Assigned(FGrid) then
    FGrid.ApplyTheme(AColors);
  if Assigned(FDocView) then
    FDocView.ApplyTheme(AColors);
  if Assigned(FSheetCombo) then
    FSheetCombo.ApplyTheme(AColors);
  if Assigned(FBtnRotL) then
    FBtnRotL.ApplyTheme(AColors);
  if Assigned(FBtnRotR) then
    FBtnRotR.ApplyTheme(AColors);
  if Assigned(FBtnResize) then
    FBtnResize.ApplyTheme(AColors);
  if Assigned(FBtnSaveAs) then
    FBtnSaveAs.ApplyTheme(AColors);
  if Assigned(FBtnFit) then
    FBtnFit.ApplyTheme(AColors);
  if Assigned(FBtn100) then
    FBtn100.ApplyTheme(AColors);
  if Assigned(FBtnFlipH) then
    FBtnFlipH.ApplyTheme(AColors);
  if Assigned(FBtnFlipV) then
    FBtnFlipV.ApplyTheme(AColors);
  if Assigned(FBtnCrop) then
    FBtnCrop.ApplyTheme(AColors);
  if Assigned(FBtnIco) then
    FBtnIco.ApplyTheme(AColors);
  if Assigned(FBtnSigRename) then
    FBtnSigRename.ApplyTheme(AColors);
  if Assigned(FSigText) then
    FSigText.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FToast) then
    FToast.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnPlay) then
    FBtnPlay.ApplyTheme(AColors);
  if Assigned(FBtnSaveClip) then
    FBtnSaveClip.ApplyTheme(AColors);
  if Assigned(FTimeText) then
    FTimeText.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FWaveBox) then
    FWaveBox.Repaint;
  if Assigned(FSeekBox) then
    FSeekBox.Repaint;
  SyncMemoScroll;
end;

end.
