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
  FMX.Memo, FMX.Memo.Types, FMX.Forms, FMX.Dialogs, FMX.Edit, FMX.Effects,
  FMX.WebBrowser, FMX.Skia, System.Skia,
  uAppSettings, uThemeManager, uFluentChrome, uFileModel, UCoreEngine,
  uArchiveEngine,
  uSpreadsheetData, uSpreadsheetGrid, uCustomScrollbar,
  uDocumentData, uDocumentView, uPdfium, uPsdPreview, uMetaCache,
  uFluentComboBox, uFluentEdit, uTextCode, uCodeView, uImageSniff, uPeInfo,
  uMeshPreview,
  uFontConvert, uLang, uLangBind
  {$IFDEF MSWINDOWS}, uMpvPlayer{$ENDIF};

type
  TImgViewKind = (ivNone, ivRaster, ivSvg, ivAnim, ivPsd);

  TImgOpKind = (iopRot, iopFlipH, iopFlipV, iopSize, iopCrop);

  TImgOp = record
    Kind: TImgOpKind;
    Deg: Integer;
    W, H: Integer;
    Crop: TRectF;
  end;

  TFilePreview = class(TRectangle)
  private
    FColors: TThemeColors;
    FPath: string;
    FLastSaved: string;
    FPendingPath: string;
    FStampAge: TDateTime;
    FStampSize: Int64;
    FShowClose: Boolean;
    FOnClose: TNotifyEvent;
    FHeader: TRectangle;
    FTitle: TText;
    FKindText: TText;
    FKindKey: string;
    FInfoKey: string;
    FMetaKey: string;
    FBtnClose: TFluentButton;
    FMeta: TText;
    FBody: TLayout;
    FImgHost: TLayout;
    FImage: TImage;
    FViewFit: Boolean;
    FViewScale: Single;
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
    FBtnSheetBack: TFluentButton;
    FBtnSheetFwd: TFluentButton;
    FDebounce: TTimer;
    FSyncTimer: TTimer;
    FCaptureKeys: Boolean;
    FDestroying: Boolean;
    FLoadGen: Integer;
    FPdf: TPdfiumDoc;
    FPdfPage: Integer;
    FPdfPages: Integer;
    FPdfFile: string;
    FPdfPrintW: Integer;
    FPdfPrintH: Integer;
    FPdfPointW: Integer;
    FPdfPointH: Integer;
    FMetaPrintW: Integer;
    FMetaPrintH: Integer;
    FMetaScreenW: Integer;
    FMetaScreenH: Integer;
    FSvgBox: TSkPaintBox;
    FSvgDom: ISkSVGDOM;
    FWeb: TWebBrowser;
    FHtmlModeBar: TLayout;
    FBtnHtmlPage: TFluentButton;
    FBtnHtmlSrc: TFluentButton;
    FHtmlShowSource: Boolean;
    FLottieHead: Boolean;
    FLottieShowSource: Boolean;
    FSvgHead: Boolean;
    FSvgShowSource: Boolean;
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
    FFontOn: Boolean;
    FFontSilence: Boolean;
    FFontSliderDrag: Boolean;
    FFontBold: Boolean;
    FFontItalic: Boolean;
    FFontAll: Boolean;
    FFontLatin: Boolean;
    FFontCyr: Boolean;
    FFontDigit: Boolean;
    FFontCanSave: Boolean;
    FFontWriting: Boolean;
    FSaveFont: Boolean;
    FFontSize: Single;
    FFontScrollY: Single;
    FFontSel: Integer;
    FFontFaceIndex: Integer;
    FFontGlyphs: Integer;
    FFontProblem: string;
    FFontPhraseText: string;
    FFontProbe: TFontProbe;
    FFontOffers: TArray<TFontOffer>;
    FFontAllCodes: TArray<Integer>;
    FFontCodes: TArray<Integer>;
    FFontBytes: TArray<TBytes>;
    FFontCodeCache: TArray<TArray<Integer>>;
    FFontCodeKnown: TArray<Boolean>;
    FFontJob: TObject;
    FFontCodeJob: TObject;
    FFontSerial: Integer;
    FFontTypeface: ISkTypeface;
    FFontResPath: string;
    FFontResTemp: Boolean;
    FFontSampleBox: TPaintBox;
    FFontPhrase: TFluentEdit;
    FFontSlider: TPaintBox;
    FFontBtnLatin: TFluentButton;
    FFontBtnCyr: TFluentButton;
    FFontBtnDigit: TFluentButton;
    FFontBtnAll: TFluentButton;
    FFontFaces: TFluentComboBox;
    FBtnFontSave: TFluentButton;
    FFontTrack: TRectangle;
    FFontVScroll: TCustomFileScrollbar;
    FFontPlate: TLayout;
    FFontPlatePaint: TPaintBox;
    FBtnCopyChar: TFluentButton;
    FBtnCopyCode: TFluentButton;
    FBtnCopyHtml: TFluentButton;
    FSaveNote: TText;
    FImgChrome: Boolean;
    FImgKind: TImgViewKind;
    FViewW: Integer;
    FViewH: Integer;
    FFrameW: Integer;
    FFrameH: Integer;
    FDocW: Integer;
    FDocH: Integer;
    FPxText: TText;
    FFrameNote: TText;
    FHeaderRule: TRectangle;
    FFooterHost: TLayout;
    FFooterBg: TRectangle;
    FViewBar: TLayout;
    FEditBar: TLayout;
    FViewRule: TRectangle;
    FEditRule: TRectangle;
    FZoomCombo: TFluentComboBox;
    FBtnFit: TFluentButton;
    FBtnEdit: TFluentButton;
    FEditScroll: THorzScrollBox;
    FEditScrollBar: TCustomFileScrollbar;
    FEditTools: TLayout;
    FBtnCrop: TFluentButton;
    FBtnFlipH: TFluentButton;
    FBtnFlipV: TFluentButton;
    FBtnRotR: TFluentButton;
    FBtnSize: TFluentButton;
    FBtnReset: TFluentButton;
    FBtnSave: TFluentButton;
    FEditWarn: TText;
    FEditWarnOn: Boolean;
    FSizeStrip: TLayout;
    FSizeWLbl: TText;
    FSizeHLbl: TText;
    FSizeW: TFluentEdit;
    FSizeH: TFluentEdit;
    FSizeLock: TFluentButton;
    FSizeLocked: Boolean;
    FSizeGuard: Boolean;
    FSizeBaseW: Integer;
    FSizeBaseH: Integer;
    FBtnSizeOk: TFluentButton;
    FSizeCombo: TFluentComboBox;
    FRatioStrip: TLayout;
    FRatioBtns: array[0..8] of TFluentButton;
    FBtnCropOk: TFluentButton;
    FCropRatio: Integer;
    FImgOriginal: TBitmap;
    FImgOps: TArray<TImgOp>;
    FImgDirty: Boolean;
    FEditing: Boolean;
    FImgBuilding: Boolean;
    FBuildGen: Integer;
    FBuildJob: TObject;
    FInFooterLayout: Boolean;
    FPdfZoom: Single;
    FSig: TImageSig;
    FSigBar: TLayout;
    FSigText: TText;
    FBtnSigRename: TFluentButton;
    FIcoBar: TLayout;
    FIcoScroll: TCustomFileScrollbar;
    FIcoFrames: TObjectList<TBitmap>;
    FIcoIndex: Integer;
    FCropping: Boolean;
    FCropNorm: TRectF;
    FCropDragId: Integer;
    FCropLast: TPointF;
    FCropGrid: Boolean;
    FCropPaint: TPaintBox;
    FToast: TText;
    FToastTimer: TTimer;
    FSaveShade: TLayout;
    FSaveCard: TRectangle;
    FSaveShadow: TShadowEffect;
    FSaveTitle: TText;
    FSaveFmtLbl: TText;
    FSaveFmt: TFluentComboBox;
    FSaveQualLbl: TText;
    FSaveQual: TFluentEdit;
    FSaveNameLbl: TText;
    FSaveName: TFluentEdit;
    FSaveFolder: TText;
    FSaveBrowse: TFluentButton;
    FSaveExists: TText;
    FSaveCancel: TFluentButton;
    FSaveOk: TFluentButton;
    FSaveDir: string;
    FSaveArmed: Boolean;
    FSaveBlocked: Boolean;
    FSaveSilence: Boolean;
    FSaveNameOwn: Boolean;
    FSaveMedia: Boolean;
    FSaveKind: Integer;
    FSaveKindRow: TLayout;
    FBtnKindClip: TFluentButton;
    FBtnKindFrame: TFluentButton;
    FBtnKindAudio: TFluentButton;
    FSaveRange: TText;
    FSaveStill: TImage;
    FVidW: Integer;
    FVidH: Integer;
    FPanoBox: TPaintBox;
    FPanoTimer: TTimer;
    FPanoToken: Integer;
    FPanoArchive: Boolean;
    FPanoPhoto, FPanoVideo, FPanoDocs, FPanoOther: Int64;
    FPanoFiles, FPanoFolders: Integer;
    FPanoPartial, FPanoReady, FPanoFailed: Boolean;
    FPanoAnim: Boolean;
    FPanoAnimAt: Cardinal;
    FPanoIconTicks: Integer;
    FPeBox: TPaintBox;
    FPeHexBtn: TFluentButton;
    FPeToken: Integer;
    FPe: TPeInfo;
    FPeIcon: TBitmap;
    FPeScroll: Single;
    FPeContentH: Single;
    FPeReady: Boolean;
    FPeHex: Boolean;
    FPeKey: string;
    FFileBox: TPaintBox;
    FFileHex: TFluentButton;
    FFileThumb: TBitmap;
    FFileScroll: Single;
    FFileContentH: Single;
    FFileHexOn: Boolean;
    FFileToken: Integer;
    FFileType: string;
    FFileOpens: string;
    FFileCreated: string;
    FFileModified: string;
    FFileSize: string;
    FFileAttrs: string;
    FFileTarget: string;
    FFileArgs: string;
    FFileWork: string;
    FFileUrl: string;
    FOnDiskChanged: TNotifyEvent;
    FMediaBar: TLayout;
    FBtnPlay: TFluentButton;
    FTimeText: TText;
    FSeekBox: TPaintBox;
    FBtnSaveClip: TFluentButton;
    FBtnSaveFrame: TFluentButton;
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
    FMeshOn: Boolean;
    FMeshPicture: Boolean;
    FMeshDrag: Boolean;
    FMeshHintGone: Boolean;
    FMeshPending: Boolean;
    FMeshBusy: Boolean;
    FMeshSimple: Boolean;
    FMeshDragX: Single;
    FMeshDragY: Single;
    FMeshAz: Single;
    FMeshEl: Single;
    FMeshScale: Single;
    FMeshGen: Integer;
    FMeshRendW: Integer;
    FMeshRendH: Integer;
    FMeshVerts: Int64;
    FMeshTris: Int64;
    FMeshPoints: Int64;
    FMeshBytes: Int64;
    FMeshPicW: Integer;
    FMeshPicH: Integer;
    FMeshKind: Integer;
    FMeshPath: string;
    FMeshExt: string;
    FMeshHint: TText;
    FHdrOn: Boolean;
    FHdrLock: Boolean;
    FHdrW: Integer;
    FHdrH: Integer;
    FHdrRgb: TArray<Single>;
    FHdrFailKey: string;
    FHdrKind: string;
    FHdrTrack: TPaintBox;
    FHdrEv: TText;
    FHdrEvVal: Single;
    FHdrShown: Single;
    FHdrDrag: Boolean;
    procedure BuildUI;
    procedure CloseClick(Sender: TObject);
    procedure DebounceTick(Sender: TObject);
    procedure SyncTick(Sender: TObject);
    procedure DoLoad(const APath: string);
    procedure StartMeshLoad(const ALocal: string);
    procedure ScheduleMeshFrame;
    procedure ApplyMeshFrame(ABmp: TBitmap; AErr: Integer; APicture, ASimple: Boolean;
      AKind: Integer; AVerts, ATris, APoints, ABytes: Int64; APicW, APicH: Integer;
      AGen, ALoadGen: Integer);
    procedure ApplyMeshChrome;
    procedure FinishOrdinary(const ALocal, AExt: string);
    procedure ShowMeshFail(AErr: Integer);
    procedure MeshRenderSize(out AW, AH: Integer);
    procedure ClearHdr;
    procedure LoadHdrView(const ALocal: string);
    procedure ShowHdrFail(const AExt: string; ANoRgb: Boolean);
    procedure ApplyHdrExposure;
    procedure PaintHdrSeek(Sender: TObject; Canvas: TCanvas);
    procedure HdrSeekDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HdrSeekMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure HdrSeekUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    function HdrXToEv(X: Single): Single;
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
    procedure ShowPanorama(const APath: string; AArchive: Boolean);
    procedure AcceptPanorama(AToken: Integer; const AKey: string;
      APhoto, AVideo, ADocs, AOther: Int64; AFiles, AFolders: Integer;
      APartial, AFailed, AFinal: Boolean);
    procedure HidePanorama;
    procedure PaintPanorama(Sender: TObject; Canvas: TCanvas);
    procedure PanoTick(Sender: TObject);
    procedure ShowPe(const APath: string);
    procedure HidePe;
    procedure PaintPe(Sender: TObject; Canvas: TCanvas);
    procedure PeHexClick(Sender: TObject);
    procedure PlacePeHex;
    procedure AcceptPe(AToken: Integer; const AKey, APath: string; const AInfo: TPeInfo);
    procedure ShowFileCard(const APath: string);
    procedure HideFileCard;
    procedure PaintFileCard(Sender: TObject; Canvas: TCanvas);
    procedure FileHexClick(Sender: TObject);
    procedure PlaceFileHex;
    procedure AcceptFileThumb(AToken: Integer; const APixels: TBytes; AW, AH: Integer);
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
    procedure StartTextLoad(const APath: string; const AExtOverride: string = '';
      ALottieJson: Boolean = False);
    function OpenLottieView(const APath: string): Boolean;
    procedure ShowLottieScene;
    procedure ShowLottieSource;
    function OpenSvgView(const APath: string): Boolean;
    procedure ShowSvgScene;
    procedure ShowSvgSource;
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
    function OpenPdfDoc: Boolean;
    procedure ApplyPdfSizeText;
    procedure ApplyMetaSizeText;
    procedure PaintFontMap(Sender: TObject; Canvas: TCanvas);
    procedure HideFontView;
    procedure ReleaseFontResource;
    function TypefaceFromFile(const APath: string; AIndex: Integer): ISkTypeface;
    function TypefaceFromBytes(const ABytes: TBytes): ISkTypeface;
    procedure StartFontJob(const APath: string; AFace: Integer; AFaceOnly: Boolean);
    procedure CancelFontCodeJob;
    procedure StartFontCodeJob;
    procedure InstallFontProbe(AJob: TObject);
    procedure BindParsedFace(AJob: TObject);
    procedure RememberFontFace(AFace: Integer; const ABytes: TBytes;
      const ACodes: TArray<Integer>; AKnown: Boolean);
    function FontFaceReady(AFace: Integer): Boolean;
    procedure AcceptFontLoad(AJob: TObject);
    procedure MountFontFace(AFace: Integer);
    procedure RebuildFontCodes;
    procedure ApplyFontBlocks;
    procedure ShowFontChrome;
    procedure LayoutFont;
    function FontCols: Integer;
    function FontContentH: Single;
    function FontOwnedText(const AText: string): string;
    function FontPreviewLines: TArray<string>;
    procedure DrawOwnedLine(ACanvas: TCanvas; const ARect: TRectF;
      const AText: string; ASize: Single; AColor: TAlphaColor);
    procedure DrawOwnedGlyph(ACanvas: TCanvas; const ARect: TRectF;
      ACode: Integer; ASize: Single; AColor: TAlphaColor);
    procedure SyncFontScroll;
    procedure FontBarScroll(APos: Single);
    procedure MoveFontSel(ADelta: Integer);
    procedure PaintFontSample(Sender: TObject; Canvas: TCanvas);
    procedure PaintFontPlate(Sender: TObject; Canvas: TCanvas);
    procedure PaintFontSlider(Sender: TObject; Canvas: TCanvas);
    procedure FontPhraseChange(Sender: TObject);
    procedure FontBlockClick(Sender: TObject);
    procedure FontFaceChange(Sender: TObject);
    procedure FontSaveClick(Sender: TObject);
    procedure FontMapDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure FontMapDbl(Sender: TObject);
    procedure FontMapWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure FontSliderDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure FontSliderMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure FontSliderUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure FontSliderApply(X: Single);
    procedure CopyFontText(const AText: string);
    procedure CopyFontChar(Sender: TObject);
    procedure CopyFontCode(Sender: TObject);
    procedure CopyFontHtml(Sender: TObject);
    function SelectedFontCode: Integer;
    function CodeHas(ACode: Integer): Boolean;
    function FontFreeName(const AExt: string): string;
    procedure FillFontFormats;
    procedure OpenFontSave;
    procedure CommitFontSave;
    procedure BuildImageChrome;
    procedure LayoutImageHeader(Sender: TObject);
    procedure LayoutImageFooter(Sender: TObject);
    procedure LayoutSaveCard(Sender: TObject);
    procedure ApplyImageTheme;
    procedure ShowImageTools(AShow: Boolean);
    procedure AdoptRasterView;
    procedure ResetEditState;
    procedure SetHeaderPixels(AW, AH: Integer);
    procedure MeasureSvgFrame;
    function ViewMetrics(out AScale, ADw, ADh, AL, AT: Single): Boolean;
    procedure SyncZoomCaption;
    procedure SetFitMode;
    procedure SetViewScale(AScale: Single; AKeepPan: Boolean);
    procedure ImgFitClick(Sender: TObject);
    procedure ImgEditClick(Sender: TObject);
    procedure ImgZoomSelect(Sender: TObject);
    procedure ImgZoomSubmit(Sender: TObject);
    procedure ImgDblClick(Sender: TObject);
    function EnsureOriginal: Boolean;
    procedure PushRot(AClockwise: Boolean);
    procedure PushFlip(AVertical: Boolean);
    procedure PushSize(AW, AH: Integer);
    procedure PushCrop(const ANorm: TRectF);
    procedure KickRebuild;
    procedure AcceptBuilt(ABmp: TBitmap; AGen: Integer);
    procedure ShowLiveSource;
    procedure ImgRotate(AClockwise: Boolean);
    procedure ImgRotRClick(Sender: TObject);
    procedure ImgResizeClick(Sender: TObject);
    procedure ImgSaveClick(Sender: TObject);
    procedure ImgFlipClick(Sender: TObject);
    procedure ImgCropClick(Sender: TObject);
    procedure ImgResetClick(Sender: TObject);
    procedure LeaveEdit(ADiscard: Boolean);
    procedure SyncEditButtons;
    procedure SizeFieldChange(Sender: TObject);
    procedure SizePctApply(Sender: TObject);
    procedure SizeComboSubmit(Sender: TObject);
    function TryApplySizePercent: Boolean;
    procedure SyncSizePct;
    procedure SizeLockClick(Sender: TObject);
    procedure SizeSubmit(Sender: TObject);
    procedure SizeCancel(Sender: TObject);
    procedure KeepDigits(AEdit: TFluentEdit; AMaxLen: Integer);
    procedure RatioClick(Sender: TObject);
    procedure CropApplyClick(Sender: TObject);
    function CropAspect: Single;
    procedure ApplyCropRatio;
    function ImageBounds: TRectF;
    function HitCropHandle(X, Y: Single): Integer;
    procedure IcoFrameClick(Sender: TObject);
    procedure SigRenameClick(Sender: TObject);
    procedure CropPaint(Sender: TObject; Canvas: TCanvas);
    procedure CropMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure CropMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure CropMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure ToastTick(Sender: TObject);
    procedure ShowToast(const AText: string);
    procedure MarkImgDirty;
    procedure ShowSigBanner(ASig: TImageSig);
    procedure HideSigBanner;
    procedure ClearIcoFrames;
    procedure ShowIcoStrip(const APath: string);
    procedure IcoHostResize(Sender: TObject);
    procedure IcoViewportChange(Sender: TObject; const OldViewportPosition,
      NewViewportPosition: TPointF; const ContentSizeChanged: Boolean);
    procedure EditToolsResize(Sender: TObject);
    procedure EditToolsViewport(Sender: TObject; const OldViewportPosition,
      NewViewportPosition: TPointF; const ContentSizeChanged: Boolean);
    procedure StyleIcoCaptions;
    procedure ApplyIcoFrame(AIndex: Integer);
    procedure CancelCrop;
    procedure ApplyCrop;
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
    procedure OpenSaveCard;
    procedure CloseSaveCard;
    procedure SaveFormatChange(Sender: TObject);
    procedure SaveNameChange(Sender: TObject);
    procedure SaveBrowseClick(Sender: TObject);
    procedure SaveCancelClick(Sender: TObject);
    procedure CommitSave;
    procedure RefreshSaveExists;
    function SaveTargetPath: string;
    procedure ShowMediaChrome(AAudio: Boolean);
    procedure HideMediaChrome;
    procedure MediaPlayClick(Sender: TObject);
    procedure MediaSaveClick(Sender: TObject);
    procedure MediaSaveFrameClick(Sender: TObject);
    procedure OpenMediaSaveCard(AKind: Integer);
    procedure SaveKindClick(Sender: TObject);
    procedure FillImageFormats;
    procedure FillMediaFormats;
    procedure ApplyMediaKind;
    function MediaExt: string;
    function MediaDefaultName: string;
    function MediaQualMode: Integer;
    function MediaRangeText: string;
    procedure CommitMediaSave;
    procedure SaveQuickFrame;
    procedure RefreshVideoLabel;
    procedure ShowVideoStill;
    procedure HideVideoStill;
    procedure SetMediaShelfLocked(ALock: Boolean);
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
    procedure DocPageChanged(Sender: TObject);
    procedure SheetComboChange(Sender: TObject);
    procedure ShowSheetBar(AOn: Boolean);
    procedure SyncSheetButtons;
    procedure SheetStep(ADelta: Integer);
    procedure SheetPrevClick(Sender: TObject);
    procedure SheetNextClick(Sender: TObject);
    procedure SheetBarWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure SheetComboKey(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    function SheetHotkey(var Key: Word; Shift: TShiftState; AArrows: Boolean): Boolean;
    procedure SetShowClose(AValue: Boolean);
    procedure MemoViewportChange(Sender: TObject; const OldViewportPosition,
      NewViewportPosition: TPointF; const ContentSizeChanged: Boolean);
    procedure PreviewBodyResize(Sender: TObject);
    procedure SyncMemoScroll;
    procedure HeaderMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure SetKindKey(const AKey: string);
    procedure SetKindRaw(const AText: string);
    procedure ShowInfoKey(const AKey: string);
    procedure RefreshFontKind;
  protected
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFile(const APath: string);
    procedure ClearPreview;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ApplyLanguage;
    procedure FocusViewer;
    function HasKeyboardFocus: Boolean;
    property FilePath: string read FPath;
    property LastSavedPath: string read FLastSaved;
    property ShowCloseButton: Boolean read FShowClose write SetShowClose;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property CaptureKeys: Boolean read FCaptureKeys write FCaptureKeys;
    property OnDiskChanged: TNotifyEvent read FOnDiskChanged write FOnDiskChanged;
    function HandleImageKey(var Key: Word; Shift: TShiftState): Boolean;
    function HandleFontKey(var Key: Word; Shift: TShiftState): Boolean;
  end;

implementation

uses
  System.Zip, uThumbCache, uIconCache, System.Variants, uVecPreview, uDxfPreview,
  uHdrPreview,
  FMX.Platform,
  FMX.Skia.Canvas, uQuickViewForm
  {$IFDEF MSWINDOWS}, Winapi.ShLwApi, SHDocVw, Winapi.EdgeUtils{$ENDIF};

function LBreak(const AKey: string): string;
begin
  Result := StringReplace(L(AKey), '\n', sLineBreak, [rfReplaceAll]);
end;

function PePhrase(const S: string): string;
begin
  if S = 'файл занят' then
    Exit(L('qv.pe.busy'))
  else if S = 'требует администратора' then
    Exit(L('qv.pe.admin'))
  else if S = 'просит повышение' then
    Exit(L('qv.pe.elevate'))
  else if S = 'неизвестно' then
    Exit(L('qv.pe.unknown'))
  else if S = 'консоль' then
    Exit(L('qv.pe.console'))
  else if S = 'драйвер' then
    Exit(L('qv.pe.driver'));
  Result := S;
end;

type
  TTextLoadJob = class
  public
    Preview: TFilePreview;
    Path: string;
    Gen: Integer;
    Mode: TTextEncMode;
    UseLottieJson: Boolean;
    UseSvgText: Boolean;
    Lines: TArray<string>;
    EncLabel: string;
    Total: Int64;
    Shown: Int64;
    MaxCols: Integer;
    Ok: Boolean;
    procedure Execute;
    procedure Apply;
  end;

  TImgBuildJob = class
  public
    Preview: TFilePreview;
    Src: TBitmap;
    Ops: TArray<TImgOp>;
    Bmp: TBitmap;
    Gen: Integer;
    procedure Execute;
    procedure Finish;
    procedure Apply;
  end;

  TFontLoadJob = class
  public
    Preview: TFilePreview;
    Path: string;
    Gen: Integer;
    Serial: Integer;
    Face: Integer;
    FaceOnly: Boolean;
    Probe: TFontProbe;
    Bytes: TBytes;
    Codes: TArray<Integer>;
    Glyphs: Integer;
    Error: string;
    Ok: Boolean;
    Cancel: Boolean;
    procedure Execute;
    procedure ApplyFinal;
  end;

  TFontCodeJob = class
  public
    Preview: TFilePreview;
    Path: string;
    Gen: Integer;
    Serial: Integer;
    Face: Integer;
    FaceRef: ISkTypeface;
    Codes: TArray<Integer>;
    Cancel: Boolean;
    procedure Execute;
    procedure Apply;
  end;

  TSheetDocView = class(TDocumentView)
  protected
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  end;

  TSheetGrid = class(TSpreadsheetGrid)
  protected
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
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
  PK_MESH    = 9;
  IMG_SHELF_H = 39;

  MAX_TEXT_BYTES = 512 * 1024;
  MAX_HEX_BYTES  = 64 * 1024;

{$IFDEF MSWINDOWS}
const
  PreviewHandlerIID = '{8895B1C6-B41F-4C1C-A562-0D564250836F}';

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
  FViewFit := True;
  FViewScale := 1;
  FPdfZoom := 1;
  FCropGrid := True;
  FSizeLocked := True;
  FCropDragId := -1;
  FIcoFrames := TObjectList<TBitmap>.Create(True);
  FImgPan := TPointF.Zero;
  FImgPanning := False;
  BuildUI;
  FDestroying := False;
  FLoadGen := 0;
  FMeshGen := 0;
  FMeshScale := 1;
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
  Inc(FMeshGen);
  FreeAndNil(FIcoFrames);
  if FTextJob <> nil then
  begin
    TTextLoadJob(FTextJob).Preview := nil;
    FTextJob := nil;
  end;
  if FFontJob <> nil then
  begin
    TFontLoadJob(FFontJob).Cancel := True;
    TFontLoadJob(FFontJob).Preview := nil;
    FFontJob := nil;
  end;
  if FFontCodeJob <> nil then
  begin
    TFontCodeJob(FFontCodeJob).Cancel := True;
    TFontCodeJob(FFontCodeJob).Preview := nil;
    FFontCodeJob := nil;
  end;
  FSvgDom := nil;
  CleanupSvgTemp;
  HideSvgWeb;
  FreeAndNil(FMemoVScroll);
  FreeAndNil(FMemoHScroll);
  FreeAndNil(FIcoScroll);
  FreeAndNil(FEditScrollBar);
  if FBuildJob <> nil then
  begin
    TImgBuildJob(FBuildJob).Preview := nil;
    FBuildJob := nil;
  end;
  FreeAndNil(FImgOriginal);
  FreeAndNil(FPdf);
  ClearPreview;
  if Assigned(FFontVScroll) then
    FFontVScroll.OnExternalScroll := nil;
  FreeAndNil(FFontVScroll);
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
  FHeader.OnResize := LayoutImageHeader;

  FBtnClose := CreateFluentButton(Self, FHeader, '', '✕', fbkSubtle, 36, CloseClick);
  FBtnClose.Align := TAlignLayout.Right;
  FBtnClose.Visible := False;

  FKindText := TText.Create(Self);
  FKindText.Parent := FHeader;
  FKindText.Align := TAlignLayout.Right;
  FKindText.Width := 110;
  FKindText.HitTest := False;
  FKindText.WordWrap := False;
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
  FBtnHtmlPage := CreateFluentButton(Self, FHtmlModeBar, '', '', fbkSubtle,
    88, HtmlPageClick);
  FBtnHtmlPage.Align := TAlignLayout.Left;
  FBtnHtmlPage.Width := 88;
  FBtnHtmlPage.SetCaption(L('qv.page'));
  FBtnHtmlSrc := CreateFluentButton(Self, FHtmlModeBar, '', '', fbkSubtle,
    88, HtmlSourceClick);
  FBtnHtmlSrc.Align := TAlignLayout.Client;
  TrButton(FBtnHtmlSrc, 'qv.source');

  FTextBar := TLayout.Create(Self);
  FTextBar.Parent := FHeader;
  FTextBar.Align := TAlignLayout.Right;
  FTextBar.Width := 400;
  FTextBar.Margins.Right := 8;
  FTextBar.Visible := False;
  FTextBar.HitTest := True;
  FBtnEnc := CreateFluentButton(Self, FTextBar, '', 'UTF-8', fbkSubtle, 76, TextEncClick);
  FBtnEnc.Align := TAlignLayout.Left;
  FBtnSheets := CreateFluentButton(Self, FTextBar, '', '', fbkSubtle, 68, TextSheetsClick);
  TrButton(FBtnSheets, 'qv.sheets');
  FBtnSheets.Align := TAlignLayout.Left;
  FBtnCode := CreateFluentButton(Self, FTextBar, '', '', fbkSubtle, 56, TextCodeClick);
  TrButton(FBtnCode, 'qv.code');
  FBtnCode.Align := TAlignLayout.Left;
  FBtnHi := CreateFluentButton(Self, FTextBar, '', '', fbkSubtle, 104, TextHiClick);
  TrButton(FBtnHi, 'qv.highlight');
  FBtnHi.Align := TAlignLayout.Left;
  FBtnWrap := CreateFluentButton(Self, FTextBar, '', '', fbkSubtle, 86, TextWrapClick);
  TrButton(FBtnWrap, 'qv.wrap');
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
  FTitle.Text := L('qv.title');

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
  FImgHost.OnDblClick := ImgDblClick;
  FImage := TImage.Create(Self);
  FImage.Parent := FImgHost;
  FImage.Align := TAlignLayout.None;
  FImage.WrapMode := TImageWrapMode.Stretch;
  FImage.Visible := False;
  FImage.HitTest := False;

  FMeshHint := TText.Create(Self);
  FMeshHint.Parent := FImgHost;
  FMeshHint.Align := TAlignLayout.Bottom;
  FMeshHint.Height := 18;
  FMeshHint.HitTest := False;
  FMeshHint.Visible := False;
  ApplyFluentText(FMeshHint, 11, False);
  FMeshHint.TextSettings.HorzAlign := TTextAlign.Center;
  FMeshHint.TextSettings.VertAlign := TTextAlign.Center;
  FMeshHint.TextSettings.Trimming := TTextTrimming.Character;
  FMeshHint.WordWrap := False;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := FBody;
  FMemo.Align := TAlignLayout.Client;
  FMemo.ReadOnly := True;
  FMemo.WordWrap := False;
  FMemo.ShowScrollBars := False;
  FMemo.ControlType := TControlType.Styled;
  FMemo.Visible := False;
  FMemo.OnViewportPositionChange := MemoViewportChange;
  { OnResize приходит до раскладки детей: FImgHost ещё старого размера,
    и картинка остаётся не по центру после разворота окна. }
  FBody.OnResized := PreviewBodyResize;
  FMemoVScroll := TCustomFileScrollbar.Create(FBody, FMemo);
  FMemoHScroll := TCustomFileScrollbar.Create(FBody, FMemo);
  FMemoHScroll.Orientation := TOrientation.Horizontal;

  FFontSample := TText.Create(Self);
  FFontSample.Parent := FBody;
  FFontSample.Align := TAlignLayout.None;
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
  FSheetBar.HitTest := True;
  FSheetBar.OnMouseWheel := SheetBarWheel;
  { Сначала «назад»: Align=Left кладёт контролы слева направо по порядку создания. }
  FBtnSheetBack := CreateFluentButton(Self, FSheetBar, #$E76B, '', fbkSubtle, 28,
    SheetPrevClick);
  FBtnSheetBack.Align := TAlignLayout.Left;
  FBtnSheetBack.Width := 28;
  FBtnSheetBack.Margins.Rect := TRectF.Create(0, 0, 2, 0);
  FSheetCombo := TFluentComboBox.Create(Self);
  FSheetCombo.Parent := FSheetBar;
  FSheetCombo.Align := TAlignLayout.Left;
  FSheetCombo.Width := 220;
  FSheetCombo.DropListOnly := True;
  FSheetCombo.Suggest := False;
  FSheetCombo.OnSelChange := SheetComboChange;
  FSheetCombo.OnClosedWheel := SheetBarWheel;
  FSheetCombo.OnEditorKey := SheetComboKey;
  FBtnSheetFwd := CreateFluentButton(Self, FSheetBar, #$E76C, '', fbkSubtle, 28,
    SheetNextClick);
  FBtnSheetFwd.Align := TAlignLayout.Left;
  FBtnSheetFwd.Width := 28;
  FBtnSheetFwd.Margins.Rect := TRectF.Create(2, 0, 0, 0);
  SyncSheetButtons;
  FGrid := TSheetGrid.Create(Self);
  FGrid.Parent := FBody;
  FGrid.Visible := False;
  FDocView := TSheetDocView.Create(Self);
  FDocView.Parent := FBody;
  FDocView.Visible := False;
  FDocView.OnStatus := TextStatus;
  FDocView.OnPageChange := DocPageChanged;
  FCodeView := TCodeView.Create(Self);
  FCodeView.Parent := FBody;
  FCodeView.Visible := False;
  FCodeView.OnStatus := TextStatus;

  FSvgBox := TSkPaintBox.Create(Self);
  FSvgBox.Parent := FImgHost;
  FSvgBox.Align := TAlignLayout.Client;
  FSvgBox.Visible := False;
  FSvgBox.HitTest := False;
  FSvgBox.OnDraw := PaintSvg;

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
  FBtnSigRename := CreateFluentButton(Self, FSigBar, '', '', fbkSubtle,
    120, SigRenameClick);
  TrButton(FBtnSigRename, 'qv.rename');
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
  FCropPaint.OnDblClick := ImgDblClick;
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
  FToast.TextSettings.Trimming := TTextTrimming.Character;
  FToast.WordWrap := False;
  FToastTimer := TTimer.Create(Self);
  FToastTimer.Enabled := False;
  FToastTimer.Interval := 2000;
  FToastTimer.OnTimer := ToastTick;

  FAnim := nil;

  FFontSize := 28;
  FFontLatin := True;
  FFontCyr := True;
  FFontDigit := True;
  FFontSel := -1;

  FFontSampleBox := TPaintBox.Create(Self);
  FFontSampleBox.Parent := FBody;
  FFontSampleBox.Align := TAlignLayout.None;
  FFontSampleBox.Visible := False;
  FFontSampleBox.HitTest := False;
  FFontSampleBox.OnPaint := PaintFontSample;

  FFontPhrase := CreateFluentEdit(Self, FBody);
  FFontPhrase.Align := TAlignLayout.None;
  FFontPhrase.Visible := False;
  FFontPhrase.FillMode := fefSubtle;
  TrPrompt(FFontPhrase, 'font.phrase');
  FFontPhrase.OnChange := FontPhraseChange;

  FFontSlider := TPaintBox.Create(Self);
  FFontSlider.Parent := FBody;
  FFontSlider.Align := TAlignLayout.None;
  FFontSlider.Visible := False;
  FFontSlider.OnPaint := PaintFontSlider;
  FFontSlider.OnMouseDown := FontSliderDown;
  FFontSlider.OnMouseMove := FontSliderMove;
  FFontSlider.OnMouseUp := FontSliderUp;

  FFontBtnLatin := CreateFluentButton(Self, FBody, '', '', fbkSubtle, 92, FontBlockClick);
  TrButton(FFontBtnLatin, 'font.latin');
  FFontBtnLatin.Align := TAlignLayout.None;
  FFontBtnLatin.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FFontBtnLatin.Tag := 0;
  FFontBtnLatin.Visible := False;
  FFontBtnCyr := CreateFluentButton(Self, FBody, '', '', fbkSubtle, 100, FontBlockClick);
  TrButton(FFontBtnCyr, 'font.cyr');
  FFontBtnCyr.Align := TAlignLayout.None;
  FFontBtnCyr.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FFontBtnCyr.Tag := 1;
  FFontBtnCyr.Visible := False;
  FFontBtnDigit := CreateFluentButton(Self, FBody, '', '', fbkSubtle, 72, FontBlockClick);
  TrButton(FFontBtnDigit, 'font.digit');
  FFontBtnDigit.Align := TAlignLayout.None;
  FFontBtnDigit.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FFontBtnDigit.Tag := 2;
  FFontBtnDigit.Visible := False;
  FFontBtnAll := CreateFluentButton(Self, FBody, '', '', fbkSubtle, 52, FontBlockClick);
  TrButton(FFontBtnAll, 'font.all');
  FFontBtnAll.Align := TAlignLayout.None;
  FFontBtnAll.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FFontBtnAll.Tag := 3;
  FFontBtnAll.Visible := False;

  FFontFaces := TFluentComboBox.Create(Self);
  FFontFaces.Parent := FBody;
  FFontFaces.Align := TAlignLayout.None;
  FFontFaces.Visible := False;
  FFontFaces.DropListOnly := True;
  FFontFaces.Suggest := False;
  FFontFaces.OnSelChange := FontFaceChange;

  FBtnFontSave := CreateFluentButton(Self, FBody, #$E74E, '', fbkAccent, 118, FontSaveClick);
  TrButton(FBtnFontSave, 'qv.save');
  FBtnFontSave.Align := TAlignLayout.None;
  FBtnFontSave.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FBtnFontSave.Visible := False;
  TrHint(FBtnFontSave, 'qv.save');
  FBtnFontSave.ShowHint := True;

  FFontMap := TPaintBox.Create(Self);
  FFontMap.Parent := FBody;
  FFontMap.Align := TAlignLayout.None;
  FFontMap.Visible := False;
  FFontMap.OnPaint := PaintFontMap;
  FFontMap.OnMouseDown := FontMapDown;
  FFontMap.OnDblClick := FontMapDbl;
  FFontMap.OnMouseWheel := FontMapWheel;

  FFontTrack := TRectangle.Create(Self);
  FFontTrack.Parent := FBody;
  FFontTrack.Align := TAlignLayout.None;
  FFontTrack.Visible := False;
  FFontTrack.HitTest := True;
  FFontTrack.Fill.Kind := TBrushKind.None;
  FFontTrack.Stroke.Kind := TBrushKind.None;
  FFontVScroll := TCustomFileScrollbar.CreateForTrack(FFontTrack, FFontTrack,
    TOrientation.Vertical);
  FFontVScroll.OnExternalScroll := FontBarScroll;

  FFontPlate := TLayout.Create(Self);
  FFontPlate.Parent := FBody;
  FFontPlate.Align := TAlignLayout.None;
  FFontPlate.Visible := False;
  FFontPlatePaint := TPaintBox.Create(Self);
  FFontPlatePaint.Parent := FFontPlate;
  FFontPlatePaint.Align := TAlignLayout.None;
  FFontPlatePaint.HitTest := False;
  FFontPlatePaint.OnPaint := PaintFontPlate;
  FBtnCopyChar := CreateFluentButton(Self, FFontPlate, '', '', fbkSubtle, 84, CopyFontChar);
  TrButton(FBtnCopyChar, 'font.char');
  FBtnCopyChar.Align := TAlignLayout.None;
  FBtnCopyChar.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FBtnCopyChar.Visible := False;
  FBtnCopyCode := CreateFluentButton(Self, FFontPlate, '', '', fbkSubtle, 72, CopyFontCode);
  TrButton(FBtnCopyCode, 'font.code');
  FBtnCopyCode.Align := TAlignLayout.None;
  FBtnCopyCode.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FBtnCopyHtml := CreateFluentButton(Self, FFontPlate, '', 'HTML', fbkSubtle, 72, CopyFontHtml);
  FBtnCopyHtml.Align := TAlignLayout.None;
  FBtnCopyHtml.Margins.Rect := TRectF.Create(0, 0, 0, 0);

  BuildImageChrome;

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
  FBtnPlay := CreateFluentButton(Self, FMediaBar, #$E768, '', fbkStandard, 96, MediaPlayClick);
  FBtnPlay.SetCaption(L('qv.start'));
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
  FBtnSaveFrame := CreateFluentButton(Self, FMediaBar, #$E722, '', fbkSubtle, 36, MediaSaveFrameClick);
  FBtnSaveFrame.Align := TAlignLayout.Right;
  FBtnSaveFrame.Margins.Left := 4;
  TrHint(FBtnSaveFrame, 'qv.framehint');
  FBtnSaveFrame.ShowHint := True;
  FBtnSaveFrame.Visible := False;
  FBtnSaveClip := CreateFluentButton(Self, FMediaBar, #$E74E, '', fbkAccent, 128, MediaSaveClick);
  TrButton(FBtnSaveClip, 'qv.save');
  FBtnSaveClip.Align := TAlignLayout.Right;
  FBtnSaveClip.Margins.Left := 8;
  TrHint(FBtnSaveClip, 'qv.save');
  FBtnSaveClip.ShowHint := True;
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
  if Assigned(FPanoBox) and FPanoBox.Visible then
    FPanoBox.Repaint;
  PlacePeHex;
  PlaceFileHex;
  {$IFDEF MSWINDOWS}
  if FUsingNative or FUsingMpv then
  begin
    FSyncTimer.Enabled := False;
    FSyncTimer.Enabled := True;
  end;
  {$ENDIF}
  if FFontOn then
    LayoutFont;
  if FMeshOn and Assigned(FImgHost) and FImgHost.Visible and Assigned(FImage) and
     FImage.Visible and (FImage.Bitmap.Width > 0) then
  begin
    if not FMeshPicture then
      FImgHost.Cursor := crHandPoint;
    if (Abs(Round(FImgHost.Width) - FMeshRendW) > 48) or
       (Abs(Round(FImgHost.Height) - FMeshRendH) > 48) then
      ScheduleMeshFrame;
  end;
end;

function TFilePreview.ImgViewActive: Boolean;
begin
  Result := False;
  if not Assigned(FImgHost) or not FImgHost.Visible then
    Exit;
  if FPdfPages > 0 then
    Exit(Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0));
  if Assigned(FSvgBox) and FSvgBox.Visible and (FViewW > 0) and (FViewH > 0) then
    Exit(True);
  if Assigned(FAnim) and FAnim.Visible and (FViewW > 0) and (FViewH > 0) then
    Exit(True);
  Result := Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0) and
    (FImage.Bitmap.Height > 0);
end;

procedure TFilePreview.ResetImgView;
begin
  FViewFit := True;
  FViewScale := 1;
  FImgPan := TPointF.Zero;
  if FImgPanning and Assigned(FImgHost) and Assigned(FImgHost.Root) and
      Assigned(FImgHost.Root.Captured) and (FImgHost.Root.Captured.GetObject = FImgHost) then
    FImgHost.Root.Captured := nil;
  FImgPanning := False;
end;

function TFilePreview.ViewMetrics(out AScale, ADw, ADh, AL, AT: Single): Boolean;
var
  HostW, HostH, FW, FH, Fit: Single;
begin
  Result := False;
  AScale := 1;
  ADw := 0;
  ADh := 0;
  AL := 0;
  AT := 0;
  if not Assigned(FImgHost) then
    Exit;
  HostW := FImgHost.Width;
  HostH := FImgHost.Height;
  if (HostW < 8) or (HostH < 8) then
    Exit;
  if Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0) then
  begin
    FW := FImage.Bitmap.Width;
    FH := FImage.Bitmap.Height;
  end
  else if (FViewW > 0) and (FViewH > 0) then
  begin
    FW := FViewW;
    FH := FViewH;
  end
  else
    Exit;
  Fit := Min(HostW / FW, HostH / FH);
  if Fit <= 0 then
    Exit;
  if FViewFit then
    AScale := Fit
  else
    AScale := EnsureRange(FViewScale, 0.10, 8.0);
  ADw := FW * AScale;
  ADh := FH * AScale;
  ClampImgPan(HostW, HostH, ADw, ADh);
  AL := (HostW - ADw) / 2 + FImgPan.X;
  AT := (HostH - ADh) / 2 + FImgPan.Y;
  Result := True;
end;

procedure TFilePreview.ShowRasterImage(AResetView: Boolean);
begin
  if Assigned(FImgHost) then
    FImgHost.Visible := True;
  if Assigned(FSvgBox) then
    FSvgBox.Visible := False;
  if Assigned(FAnim) and (FImgKind <> ivAnim) then
    FAnim.Visible := False;
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
  Scale, Dw, Dh, L, T: Single;
begin
  if not ViewMetrics(Scale, Dw, Dh, L, T) then
    Exit;
  if Assigned(FImage) and FImage.Visible then
  begin
    FImage.Position.Point := TPointF.Create(L, T);
    FImage.Width := Dw;
    FImage.Height := Dh;
  end;
  if Assigned(FAnim) and FAnim.Visible then
  begin
    FAnim.Align := TAlignLayout.None;
    FAnim.WrapMode := TSkAnimatedImageWrapMode.Stretch;
    FAnim.SetBounds(L, T, Dw, Dh);
  end;
  if Assigned(FSvgBox) and FSvgBox.Visible then
    FSvgBox.Redraw;
  if FCropping and Assigned(FCropPaint) then
    FCropPaint.Repaint;
  if (Dw > FImgHost.Width + 0.5) or (Dh > FImgHost.Height + 0.5) then
    FImgHost.Cursor := crSizeAll
  else
    FImgHost.Cursor := crDefault;
  SyncZoomCaption;
end;

procedure TFilePreview.SyncZoomCaption;
var
  Scale, Dw, Dh, L, T: Single;
  Cap: string;
begin
  if not Assigned(FZoomCombo) or not FImgChrome then
    Exit;
  if FZoomCombo.EditorFocused then
    Exit;
  if ViewMetrics(Scale, Dw, Dh, L, T) then
    Cap := IntToStr(Max(1, Round(Scale * 100))) + '%'
  else
    Cap := IntToStr(Max(1, Round(FViewScale * 100))) + '%';
  if not FZoomCombo.EditorFocused and (FZoomCombo.Text <> Cap) then
    FZoomCombo.Text := Cap;
  if Assigned(FBtnFit) then
  begin
    if FViewFit then
    begin
      FBtnFit.SetIcon(#$E740);
      FBtnFit.Hint := uLang.L('qv.actual');
    end
    else
    begin
      FBtnFit.SetIcon(#$E9A6);
      FBtnFit.Hint := uLang.L('qv.fit');
    end;
  end;
end;

procedure TFilePreview.ImgMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  Scale, Dw, Dh, L, T, OldScale, NewScale, NewDw, NewDh, FracX, FracY: Single;
  Mouse: TPointF;
begin
  if FMeshOn and not FMeshPicture then
  begin
    if WheelDelta = 0 then
      Exit;
    Handled := True;
    if WheelDelta > 0 then
      FMeshScale := FMeshScale * 1.12
    else
      FMeshScale := FMeshScale / 1.12;
    if FMeshScale < 0.4 then
      FMeshScale := 0.4
    else if FMeshScale > 6 then
      FMeshScale := 6;
    ScheduleMeshFrame;
    Exit;
  end;
  if WheelDelta = 0 then
    Exit;
  if not ImgViewActive then
    Exit;
  if not ViewMetrics(Scale, Dw, Dh, L, T) then
    Exit;
  Handled := True;
  OldScale := Scale;
  NewScale := OldScale * Power(1.12, WheelDelta / 120.0);
  NewScale := EnsureRange(NewScale, 0.10, 8.0);
  if Abs(NewScale - 1) < 0.02 then
    NewScale := 1;
  Mouse := FImgHost.ScreenToLocal(Screen.MousePos);
  if Dw > 1 then
    FracX := (Mouse.X - L) / Dw
  else
    FracX := 0.5;
  if Dh > 1 then
    FracY := (Mouse.Y - T) / Dh
  else
    FracY := 0.5;
  NewDw := Dw * (NewScale / OldScale);
  NewDh := Dh * (NewScale / OldScale);
  FViewFit := False;
  FViewScale := NewScale;
  FImgPan.X := Mouse.X - (FImgHost.Width - NewDw) / 2 - FracX * NewDw;
  FImgPan.Y := Mouse.Y - (FImgHost.Height - NewDh) / 2 - FracY * NewDh;
  ApplyImgView;
end;

procedure TFilePreview.ImgMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Scale, Dw, Dh, L, T: Single;
  PanBtn: Boolean;
begin
  if FMeshOn and not FMeshPicture then
  begin
    FocusViewer;
    if Button <> TMouseButton.mbLeft then
      Exit;
    FMeshDrag := True;
    FMeshDragX := X;
    FMeshDragY := Y;
    FMeshHintGone := True;
    if Assigned(FMeshHint) then
      FMeshHint.Visible := False;
    if Assigned(FImgHost.Root) then
      FImgHost.Root.Captured := FImgHost;
    FImgHost.Cursor := crHandPoint;
    Exit;
  end;
  FocusViewer;
  if FCropping or not ImgViewActive then
    Exit;
  PanBtn := (Button = TMouseButton.mbLeft) or (Button = TMouseButton.mbMiddle);
  if not PanBtn then
    Exit;
  if not ViewMetrics(Scale, Dw, Dh, L, T) then
    Exit;
  if (Dw <= FImgHost.Width + 0.5) and (Dh <= FImgHost.Height + 0.5) then
    Exit;
  FImgPanning := True;
  FImgPanLast := TPointF.Create(X, Y);
  if Assigned(FImgHost.Root) then
    FImgHost.Root.Captured := FImgHost;
  FImgHost.Cursor := crSizeAll;
end;

procedure TFilePreview.ImgMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if FMeshOn and not FMeshPicture then
  begin
    if not FMeshDrag then
      Exit;
    FMeshAz := FMeshAz - (X - FMeshDragX) * 0.4;
    FMeshEl := FMeshEl + (Y - FMeshDragY) * 0.4;
    if FMeshEl > 89 then
      FMeshEl := 89
    else if FMeshEl < -89 then
      FMeshEl := -89;
    FMeshDragX := X;
    FMeshDragY := Y;
    ScheduleMeshFrame;
    Exit;
  end;
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
  if FMeshDrag then
  begin
    FMeshDrag := False;
    if Assigned(FImgHost) and Assigned(FImgHost.Root) and
       Assigned(FImgHost.Root.Captured) and (FImgHost.Root.Captured.GetObject = FImgHost) then
      FImgHost.Root.Captured := nil;
    Exit;
  end;
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
  if Assigned(FPeBox) and FPeBox.Visible then
  begin
    FPeScroll := EnsureRange(FPeScroll - WheelDelta * 0.4, 0,
      Max(0, FPeContentH - FPeBox.Height));
    FPeBox.Repaint;
    Handled := True;
    Exit;
  end;
  if Assigned(FFileBox) and FFileBox.Visible then
  begin
    FFileScroll := EnsureRange(FFileScroll - WheelDelta * 0.4, 0,
      Max(0, FFileContentH - FFileBox.Height));
    FFileBox.Repaint;
    Handled := True;
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
    ShowToast(L('qv.toast.failed'));
  FImgDirty := False;
  FDebounce.Enabled := False;
  FPath := '';
  FPendingPath := '';
  FStampAge := 0;
  FStampSize := 0;
  HideViewers;
  if Assigned(FTitle) then
    FTitle.Text := L('qv.title');
  if Assigned(FKindText) then
    SetKindKey('');
  if Assigned(FMeta) then
    FMeta.Text := '';
end;

procedure TFilePreview.HideViewers;
begin
  FKindKey := '';
  FInfoKey := '';
  ClearHdr;
  if FMeshDrag and Assigned(FImgHost) and Assigned(FImgHost.Root) and
     Assigned(FImgHost.Root.Captured) and (FImgHost.Root.Captured.GetObject = FImgHost) then
    FImgHost.Root.Captured := nil;
  FMeshOn := False;
  FMeshDrag := False;
  FMeshPending := False;
  FMeshPicture := False;
  Inc(FMeshGen);
  if Assigned(FMeshHint) then
    FMeshHint.Visible := False;
  FPdfPrintW := 0;
  FPdfPrintH := 0;
  FPdfPointW := 0;
  FPdfPointH := 0;
  FMetaPrintW := 0;
  FMetaPrintH := 0;
  FMetaScreenW := 0;
  FMetaScreenH := 0;
  FPdfPages := 0;
  FPdfFile := '';
  FMetaKey := '';
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
  FLottieHead := False;
  FSvgHead := False;
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
  HideFontView;
  ShowImageTools(False);
  CancelCrop;
  HideSigBanner;
  ClearIcoFrames;
  FPdfZoom := 1;
  HideMediaChrome;
  ResetEditState;
  FreeAndNil(FPdf);
  if Assigned(FMemo) then
  begin
    FMemo.Lines.Clear;
    FMemo.Visible := False;
  end;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  HidePanorama;
  HidePe;
  HideFileCard;
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
  if Assigned(FSheetCombo) then
    FSheetCombo.Items.Clear;
  ShowSheetBar(False);
  FreeAndNil(FBook);
  FreeAndNil(FDoc);
  SyncMemoScroll;
end;

procedure TFilePreview.ShowInfo(const AText: string);
begin
  FInfoKey := '';
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
  if ExtIn(AExt, ['.jpg', '.jpeg', '.jpe', '.png', '.bmp', '.dib', '.gif', '.tif', '.tiff',
    '.webp', '.ico', '.cur', '.jfif', '.heic', '.heif', '.jxl', '.dds', '.svg', '.svgz',
    '.emf', '.wmf', '.eps', '.cdr', '.cdt', '.dxf', '.psd', '.psb', '.tga', '.avif', '.lottie', '.tgs']) then
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
  if ExtIn(LowerCase(AExt), ['.stl', '.obj', '.ply', '.gltf', '.glb', '.blend']) then
    Exit(PK_MESH);

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
      FImgKind := ivRaster;
      FViewW := FImage.Bitmap.Width;
      FViewH := FImage.Bitmap.Height;
      FFrameW := FViewW;
      FFrameH := FViewH;
      ShowImageTools(True);
      Exit;
    end;
  end;
  Result := LoadAsSkiaImage(APath);
  if not Result and ExtIn(Ext, ['.jpg', '.jpeg', '.png', '.bmp', '.gif']) then
  try
    FImage.Bitmap.LoadFromFile(APath);
    Result := (FImage.Bitmap.Width > 0) and (FImage.Bitmap.Height > 0);
    if Result then
    begin
      FImgKind := ivRaster;
      FViewW := FImage.Bitmap.Width;
      FViewH := FImage.Bitmap.Height;
      FFrameW := FViewW;
      FFrameH := FViewH;
      ShowRasterImage;
    end;
  except
    Result := False;
  end;
  if not Result then
    Result := LoadAsThumb(APath);
  if Result and (FImgKind = ivNone) and Assigned(FImage) and FImage.Visible then
  begin
    FImgKind := ivRaster;
    FViewW := FImage.Bitmap.Width;
    FViewH := FImage.Bitmap.Height;
    FFrameW := FViewW;
    FFrameH := FViewH;
  end;
  if Result then
    ShowImageTools(True);
  if Result and ((FMetaPrintW > 0) or (FMetaScreenW > 0)) then
    ApplyMetaSizeText;
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
      S := S + sLineBreak + sLineBreak + Lf('qv.shownkb',
        [MAX_TEXT_BYTES div 1024]);
    Doc := LoadTextDocumentFromString(S, APath, Err);
    if Doc <> nil then
    begin
      ApplyDocument(Doc);
      if Assigned(FDoc) and Assigned(FDocView) and FDocView.Visible then
      begin
        if IsMarkdownFile(APath) then
          SetKindKey('qv.kind.markdown')
        else
          SetKindKey('qv.kind.text');
        Result := True;
        Exit;
      end;
    end;
    FMemo.WordWrap := True;
    FMemo.TextSettings.Font.Family := 'Calibri';
    FMemo.TextSettings.Font.Size := 13;
    FMemo.Lines.Text := S;
    FMemo.Visible := True;
    SetKindKey('qv.kind.text');
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
        SL.Add(Lf('qv.shownkb', [MAX_HEX_BYTES div 1024]));
      FMemo.WordWrap := False;
      FMemo.TextSettings.Font.Family := 'Consolas';
      FMemo.TextSettings.Font.Size := 12;
      FMemo.Lines.Assign(SL);
    finally
      SL.Free;
    end;
    FMemo.Visible := True;
    SetKindKey('qv.kind.binary');
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
      SetKindKey('qv.kind.audio')
    else
      SetKindKey('');
    Result := True;
    Exit;
  end;
end;

const
  FONT_LATIN = 'The quick brown fox jumps over the lazy dog';
  FONT_CYR = 'Съешь же ещё этих мягких французских булок, да выпей чаю';
  FONT_DIGITS = '0123456789  + − × ÷  №';

function FontCodeText(ACode: Integer): string;
var
  U: Cardinal;
begin
  if ACode < 0 then
    Exit('');
  if ACode <= $FFFF then
    Result := WideChar(ACode)
  else
  begin
    U := Cardinal(ACode) - $10000;
    Result := WideChar($D800 + (U shr 10)) + WideChar($DC00 + (U and $3FF));
  end;
end;

function FontHex(ACode: Integer): string;
var
  Digs: Integer;
begin
  Digs := 4;
  if ACode > $FFFF then
    Digs := 6;
  Result := IntToHex(ACode, Digs);
end;

function FontUtf8(ACode: Integer): string;
var
  Bytes: TBytes;
  I: Integer;
begin
  Bytes := TEncoding.UTF8.GetBytes(FontCodeText(ACode));
  Result := '';
  for I := 0 to High(Bytes) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + IntToHex(Bytes[I], 2);
  end;
end;

function FontHtml(ACode: Integer): string;
begin
  Result := '&#' + IntToStr(ACode) + ';';
end;

function Font1251(ACode: Integer): string;
var
  W, Back: WideChar;
  Buf: array[0..3] of AnsiChar;
  Used: BOOL;
  N: Integer;
begin
  Result := L('font.none');
  if (ACode < 0) or (ACode > $FFFF) then
    Exit;
  W := WideChar(ACode);
  Used := False;
  N := WideCharToMultiByte(1251, $400, @W, 1, @Buf[0], SizeOf(Buf), nil, @Used);
  if (N <> 1) or Used then
    Exit;
  Back := #0;
  N := MultiByteToWideChar(1251, 0, @Buf[0], 1, @Back, 1);
  if (N <> 1) or (Back <> W) then
    Exit;
  Result := '0x' + LowerCase(IntToHex(Byte(Buf[0]), 2));
end;

procedure TFilePreview.HideFontView;
begin
  FFontOn := False;
  FFontSliderDrag := False;
  if FFontJob <> nil then
  begin
    TFontLoadJob(FFontJob).Cancel := True;
    TFontLoadJob(FFontJob).Preview := nil;
    FFontJob := nil;
  end;
  CancelFontCodeJob;
  ReleaseFontResource;
  FFontTypeface := nil;
  SetLength(FFontCodes, 0);
  SetLength(FFontAllCodes, 0);
  SetLength(FFontBytes, 0);
  SetLength(FFontCodeCache, 0);
  SetLength(FFontCodeKnown, 0);
  FFontSel := -1;
  if Assigned(FFontSample) then
  begin
    FFontSample.Visible := False;
    FFontSample.Align := TAlignLayout.None;
  end;
  if Assigned(FFontSampleBox) then
    FFontSampleBox.Visible := False;
  if Assigned(FFontPhrase) then
    FFontPhrase.Visible := False;
  if Assigned(FFontSlider) then
    FFontSlider.Visible := False;
  if Assigned(FFontBtnLatin) then
    FFontBtnLatin.Visible := False;
  if Assigned(FFontBtnCyr) then
    FFontBtnCyr.Visible := False;
  if Assigned(FFontBtnDigit) then
    FFontBtnDigit.Visible := False;
  if Assigned(FFontBtnAll) then
    FFontBtnAll.Visible := False;
  if Assigned(FFontFaces) then
    FFontFaces.Visible := False;
  if Assigned(FBtnFontSave) then
    FBtnFontSave.Visible := False;
  if Assigned(FFontMap) then
  begin
    FFontMap.Visible := False;
    FFontMap.Align := TAlignLayout.None;
  end;
  if Assigned(FFontTrack) then
    FFontTrack.Visible := False;
  if Assigned(FFontPlate) then
    FFontPlate.Visible := False;
  if Assigned(FMeta) then
    FMeta.Visible := True;
end;

function TFilePreview.TypefaceFromFile(const APath: string;
  AIndex: Integer): ISkTypeface;
begin
  Result := nil;
  if APath = '' then
    Exit;
  try
    Result := TSkTypeface.MakeFromFile(APath, AIndex);
  except
    Result := nil;
  end;
end;

function TFilePreview.TypefaceFromBytes(const ABytes: TBytes): ISkTypeface;
var
  Temp, Ext: string;
begin
  { Как в рабочей копии: файл, а не поток Delphi. Skia дочитывает поток
    со своего потока глифов и окно замирает. Файл живёт, пока живо лицо. }
  Result := nil;
  if Length(ABytes) = 0 then
    Exit;
  if FFontProbe.Flavor = $4F54544F then
    Ext := '.otf'
  else
    Ext := '.ttf';
  Temp := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath,
    'vibe-font-' + IntToStr(TThread.GetTickCount) + Ext);
  try
    TFile.WriteAllBytes(Temp, ABytes);
  except
    Exit;
  end;
  FFontResPath := Temp;
  FFontResTemp := True;
  Result := TypefaceFromFile(Temp, 0);
  if Result = nil then
  begin
    FFontResPath := '';
    FFontResTemp := False;
    try
      if TFile.Exists(Temp) then
        TFile.Delete(Temp);
    except
    end;
  end;
end;

procedure TFilePreview.ReleaseFontResource;
var
  Path: string;
  Temp: Boolean;
begin
  FFontTypeface := nil;
  Path := FFontResPath;
  Temp := FFontResTemp;
  FFontResPath := '';
  FFontResTemp := False;
  if (not Temp) or (Path = '') then
    Exit;
  try
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  except
  end;
end;

procedure TFontLoadJob.Execute;
begin
  { Только байты и cmap. Skia и AddFontResourceEx отсюда нельзя:
    они держат тот же замок, что и отрисовка, и окно замирает. }
  Ok := False;
  Error := '';
  Glyphs := 0;
  SetLength(Bytes, 0);
  SetLength(Codes, 0);
  try
    if not Cancel then
    begin
      if FaceOnly then
        Ok := LoadFace(Path, Face, False, Bytes, Codes, Glyphs, Error)
      else
        Ok := OpenFont(Path, Face, Probe, Bytes, Codes, Glyphs, Error);
    end;
  except
    Ok := False;
  end;
  TThread.Queue(nil, ApplyFinal);
end;

procedure TFontLoadJob.ApplyFinal;
var
  P: TFilePreview;
begin
  P := Preview;
  try
    if (P <> nil) and (not P.FDestroying) and (not Cancel) and
       (P.FLoadGen = Gen) and (P.FFontSerial = Serial) and
       SameText(P.FPath, Path) then
      P.AcceptFontLoad(Self);
  finally
    if (P <> nil) and (P.FFontJob = Self) then
      P.FFontJob := nil;
    Free;
  end;
end;

procedure TFontCodeJob.Execute;
var
  Font: ISkFont;
  Code, N: Integer;
  List: TList<Integer>;
begin
  SetLength(Codes, 0);
  try
    if (not Cancel) and (FaceRef <> nil) then
    begin
      Font := TSkFont.Create(FaceRef, 16);
      List := TList<Integer>.Create;
      try
        N := 0;
        Code := $20;
        while (Code <= $FFFF) and (N < FontCodeCap) and (not Cancel) do
        begin
          if Font.UnicharToGlyph(Code) <> 0 then
          begin
            List.Add(Code);
            Inc(N);
          end;
          Inc(Code);
        end;
        if not Cancel then
          Codes := List.ToArray;
      finally
        List.Free;
      end;
    end;
  except
    SetLength(Codes, 0);
  end;
  Font := nil;
  FaceRef := nil;
  TThread.Queue(nil, Apply);
end;

procedure TFontCodeJob.Apply;
var
  P: TFilePreview;
  Live: Boolean;
begin
  P := Preview;
  Live := (P <> nil) and (not P.FDestroying) and (not Cancel) and
    (P.FLoadGen = Gen) and (P.FFontSerial = Serial) and
    SameText(P.FPath, Path) and (P.FFontFaceIndex = Face);
  try
    if Live then
    begin
      P.FFontAllCodes := Codes;
      P.RememberFontFace(Face, nil, Codes, True);
      if Length(Codes) > 0 then
      begin
        P.RebuildFontCodes;
        P.LayoutFont;
        P.RefreshFontKind;
      end;
    end;
  finally
    if (P <> nil) and (P.FFontCodeJob = Self) then
      P.FFontCodeJob := nil;
    Free;
  end;
end;

procedure TFilePreview.CancelFontCodeJob;
begin
  if FFontCodeJob = nil then
    Exit;
  TFontCodeJob(FFontCodeJob).Cancel := True;
  TFontCodeJob(FFontCodeJob).Preview := nil;
  FFontCodeJob := nil;
end;

procedure TFilePreview.StartFontCodeJob;
var
  Job: TFontCodeJob;
begin
  CancelFontCodeJob;
  if (FFontTypeface = nil) or (Length(FFontAllCodes) > 0) or
     (FFontProbe.Container = fcFon) then
    Exit;
  Job := TFontCodeJob.Create;
  Job.Preview := Self;
  Job.Path := FPath;
  Job.Gen := FLoadGen;
  Job.Serial := FFontSerial;
  Job.Face := FFontFaceIndex;
  Job.FaceRef := FFontTypeface;
  FFontCodeJob := Job;
  TThread.CreateAnonymousThread(
    procedure
    begin
      Job.Execute;
    end).Start;
end;

procedure TFilePreview.StartFontJob(const APath: string; AFace: Integer;
  AFaceOnly: Boolean);
var
  Job: TFontLoadJob;
begin
  Inc(FFontSerial);
  CancelFontCodeJob;
  if FFontJob <> nil then
  begin
    TFontLoadJob(FFontJob).Cancel := True;
    TFontLoadJob(FFontJob).Preview := nil;
    FFontJob := nil;
  end;
  Job := TFontLoadJob.Create;
  Job.Preview := Self;
  Job.Path := APath;
  Job.Gen := FLoadGen;
  Job.Serial := FFontSerial;
  Job.Face := AFace;
  Job.FaceOnly := AFaceOnly;
  FFontJob := Job;
  TThread.CreateAnonymousThread(
    procedure
    begin
      Job.Execute;
    end).Start;
end;

procedure TFilePreview.InstallFontProbe(AJob: TObject);
var
  Job: TFontLoadJob;
  S: string;
  I: Integer;
begin
  Job := TFontLoadJob(AJob);
  FFontProbe := Job.Probe;
  FFontProblem := Job.Probe.Problem;
  if Job.Error <> '' then
    FFontProblem := Job.Error;
  FFontGlyphs := Job.Probe.GlyphCount;
  FFontCanSave := Job.Probe.Ok and
    (Job.Probe.Container in [fcTtf, fcOtf, fcWoff, fcWoff2]);
  FFontSilence := True;
  try
    if Assigned(FFontFaces) then
    begin
      FFontFaces.Items.Clear;
      for I := 0 to High(FFontProbe.Faces) do
      begin
        S := FFontProbe.Faces[I].Name;
        if S = '' then
          S := Lf('font.face', [I + 1]);
        if FFontFaces.Items.IndexOf(S) >= 0 then
          S := S + ' ' + IntToStr(I + 1);
        FFontFaces.Items.Add(S);
      end;
      if (Job.Face >= 0) and (Job.Face < FFontFaces.Items.Count) then
        FFontFaces.ItemIndex := Job.Face;
    end;
  finally
    FFontSilence := False;
  end;
end;

procedure TFilePreview.RememberFontFace(AFace: Integer; const ABytes: TBytes;
  const ACodes: TArray<Integer>; AKnown: Boolean);
var
  N: Integer;
begin
  if AFace < 0 then
    Exit;
  N := AFace + 1;
  if Length(FFontProbe.Faces) > N then
    N := Length(FFontProbe.Faces);
  if Length(FFontBytes) < N then
  begin
    SetLength(FFontBytes, N);
    SetLength(FFontCodeCache, N);
    SetLength(FFontCodeKnown, N);
  end;
  if Length(ABytes) > 0 then
    FFontBytes[AFace] := ABytes;
  if AKnown then
  begin
    FFontCodeCache[AFace] := ACodes;
    FFontCodeKnown[AFace] := True;
  end;
end;

function TFilePreview.FontFaceReady(AFace: Integer): Boolean;
begin
  Result := (AFace >= 0) and (AFace <= High(FFontCodeKnown)) and
    FFontCodeKnown[AFace] and (Length(FFontBytes[AFace]) > 0);
end;

procedure TFilePreview.BindParsedFace(AJob: TObject);
var
  Job: TFontLoadJob;
  Tf: ISkTypeface;
begin
  Job := TFontLoadJob(AJob);
  ReleaseFontResource;
  FFontFaceIndex := Job.Face;
  FFontBold := False;
  FFontItalic := False;
  FFontFace := '';
  if (Job.Face >= 0) and (Job.Face <= High(FFontProbe.Faces)) then
  begin
    FFontBold := FFontProbe.Faces[Job.Face].Bold;
    FFontItalic := FFontProbe.Faces[Job.Face].Italic;
    FFontFace := FFontProbe.Faces[Job.Face].Family;
    if FFontProbe.Faces[Job.Face].GlyphCount > 0 then
      FFontGlyphs := FFontProbe.Faces[Job.Face].GlyphCount;
  end;
  if Job.Glyphs > 0 then
    FFontGlyphs := Job.Glyphs;
  Tf := nil;
  if FFontProbe.Container in [fcTtf, fcOtf, fcTtc] then
    Tf := TypefaceFromFile(Job.Path, Job.Face);
  if Tf = nil then
    Tf := TypefaceFromBytes(Job.Bytes);
  FFontTypeface := Tf;
  if (FFontFace = '') and (Tf <> nil) then
    FFontFace := Tf.FamilyName;
  if FFontFace = '' then
    FFontFace := ChangeFileExt(ExtractFileName(FPath), '');
  if Job.Error <> '' then
    FFontProblem := Job.Error;
  FFontAllCodes := Job.Codes;
  RememberFontFace(Job.Face, Job.Bytes, Job.Codes, Length(Job.Codes) > 0);
  Job.Bytes := nil;
  Job.Codes := nil;
end;

procedure TFilePreview.AcceptFontLoad(AJob: TObject);
var
  Job: TFontLoadJob;
begin
  Job := TFontLoadJob(AJob);
  if not Job.FaceOnly then
    InstallFontProbe(Job);
  if not Job.Ok then
  begin
    if Job.FaceOnly then
    begin
      FFontSilence := True;
      try
        if Assigned(FFontFaces) and (FFontFaceIndex >= 0) and
           (FFontFaceIndex < FFontFaces.Items.Count) then
          FFontFaces.ItemIndex := FFontFaceIndex;
      finally
        FFontSilence := False;
      end;
    end
    else
    begin
      ShowInfoKey('font.unreadable');
      SetKindRaw(ContainerTitle(FFontProbe.Container));
      if Assigned(FKindText) then
        FKindText.Width := 168;
    end;
    Exit;
  end;
  BindParsedFace(Job);
  if FFontTypeface = nil then
  begin
    ShowInfoKey('font.unreadable');
    SetKindRaw(ContainerTitle(FFontProbe.Container));
    if Assigned(FKindText) then
      FKindText.Width := 168;
    Exit;
  end;
  ApplyFontBlocks;
  RebuildFontCodes;
  ShowFontChrome;
  LayoutFont;
  RefreshFontKind;
  if Length(FFontAllCodes) = 0 then
    StartFontCodeJob;
end;

procedure TFilePreview.MountFontFace(AFace: Integer);
begin
  if not FontFaceReady(AFace) then
    Exit;
  FFontFaceIndex := AFace;
  FFontBold := False;
  FFontItalic := False;
  FFontFace := '';
  if (AFace >= 0) and (AFace <= High(FFontProbe.Faces)) then
  begin
    FFontBold := FFontProbe.Faces[AFace].Bold;
    FFontItalic := FFontProbe.Faces[AFace].Italic;
    FFontFace := FFontProbe.Faces[AFace].Family;
    if FFontProbe.Faces[AFace].GlyphCount > 0 then
      FFontGlyphs := FFontProbe.Faces[AFace].GlyphCount;
  end;
  ReleaseFontResource;
  if FFontProbe.Container in [fcTtf, fcOtf, fcTtc] then
    FFontTypeface := TypefaceFromFile(FPath, AFace);
  if FFontTypeface = nil then
    FFontTypeface := TypefaceFromBytes(FFontBytes[AFace]);
  if (FFontFace = '') and (FFontTypeface <> nil) then
    FFontFace := FFontTypeface.FamilyName;
  if FFontFace = '' then
    FFontFace := ChangeFileExt(ExtractFileName(FPath), '');
  FFontAllCodes := FFontCodeCache[AFace];
end;

function TFilePreview.CodeHas(ACode: Integer): Boolean;
var
  L, R, M: Integer;
begin
  Result := False;
  L := 0;
  R := High(FFontAllCodes);
  while L <= R do
  begin
    M := (L + R) div 2;
    if FFontAllCodes[M] = ACode then
      Exit(True);
    if FFontAllCodes[M] < ACode then
      L := M + 1
    else
      R := M - 1;
  end;
end;

procedure TFilePreview.RebuildFontCodes;
var
  N, I, C, Keep: Integer;

  procedure Take(ACode: Integer);
  begin
    if not CodeHas(ACode) then
      Exit;
    FFontCodes[N] := ACode;
    Inc(N);
  end;

  procedure TakeRange(AFrom, ATo: Integer);
  var
    K: Integer;
  begin
    for K := AFrom to ATo do
      Take(K);
  end;

begin
  Keep := SelectedFontCode;
  SetLength(FFontCodes, Length(FFontAllCodes));
  N := 0;
  if FFontAll then
  begin
    for I := 0 to High(FFontAllCodes) do
    begin
      FFontCodes[N] := FFontAllCodes[I];
      Inc(N);
    end;
  end
  else
  begin
    if FFontLatin then
    begin
      TakeRange($41, $5A);
      TakeRange($61, $7A);
    end;
    if FFontCyr then
    begin
      TakeRange($410, $42F);
      TakeRange($430, $44F);
      Take($401);
      Take($451);
      Take($407);
      Take($457);
      Take($404);
      Take($454);
    end;
    if FFontDigit then
      TakeRange($30, $39);
  end;
  SetLength(FFontCodes, N);
  FFontSel := -1;
  if N > 0 then
  begin
    FFontSel := 0;
    if Keep >= 0 then
      for C := 0 to N - 1 do
        if FFontCodes[C] = Keep then
          FFontSel := C;
  end;
  FFontScrollY := 0;
  if Assigned(FFontMap) then
    FFontMap.Repaint;
  if Assigned(FFontPlatePaint) then
    FFontPlatePaint.Repaint;
  SyncFontScroll;
end;

procedure TFilePreview.ApplyFontBlocks;
begin
  if Assigned(FFontBtnLatin) then
    FFontBtnLatin.SetSelected(FFontLatin and not FFontAll);
  if Assigned(FFontBtnCyr) then
    FFontBtnCyr.SetSelected(FFontCyr and not FFontAll);
  if Assigned(FFontBtnDigit) then
    FFontBtnDigit.SetSelected(FFontDigit and not FFontAll);
  if Assigned(FFontBtnAll) then
    FFontBtnAll.SetSelected(FFontAll);
end;

procedure TFilePreview.ShowFontChrome;
begin
  FFontOn := True;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  if Assigned(FFontSampleBox) then
  begin
    FFontSampleBox.Visible := True;
    FFontSampleBox.BringToFront;
  end;
  if Assigned(FFontPhrase) then
  begin
    FFontPhrase.Visible := True;
    FFontPhrase.BringToFront;
  end;
  if Assigned(FFontSlider) then
  begin
    FFontSlider.Visible := True;
    FFontSlider.BringToFront;
  end;
  if Assigned(FFontBtnLatin) then
    FFontBtnLatin.Visible := True;
  if Assigned(FFontBtnCyr) then
    FFontBtnCyr.Visible := True;
  if Assigned(FFontBtnDigit) then
    FFontBtnDigit.Visible := True;
  if Assigned(FFontBtnAll) then
    FFontBtnAll.Visible := True;
  if Assigned(FFontBtnLatin) then
    FFontBtnLatin.BringToFront;
  if Assigned(FFontBtnCyr) then
    FFontBtnCyr.BringToFront;
  if Assigned(FFontBtnDigit) then
    FFontBtnDigit.BringToFront;
  if Assigned(FFontBtnAll) then
    FFontBtnAll.BringToFront;
  if Assigned(FFontFaces) then
  begin
    FFontFaces.Visible := Length(FFontProbe.Faces) > 1;
    if FFontFaces.Visible then
      FFontFaces.BringToFront;
  end;
  if Assigned(FBtnFontSave) then
  begin
    FBtnFontSave.Visible := FFontCanSave;
    if FFontProblem <> '' then
      FBtnFontSave.Opacity := 0.45
    else
      FBtnFontSave.Opacity := 1;
    if FBtnFontSave.Visible then
      FBtnFontSave.BringToFront;
  end;
  if Assigned(FFontMap) then
  begin
    FFontMap.Visible := True;
    FFontMap.BringToFront;
  end;
  if Assigned(FFontTrack) then
  begin
    FFontTrack.Visible := True;
    FFontTrack.BringToFront;
  end;
  if Assigned(FFontPlate) then
  begin
    FFontPlate.Visible := True;
    FFontPlate.BringToFront;
  end;
  if Assigned(FBtnCopyChar) then
    FBtnCopyChar.Visible := True;
  if Assigned(FMeta) then
    FMeta.Visible := False;
end;

function TFilePreview.FontCols: Integer;
begin
  Result := 1;
  if not Assigned(FFontMap) or (FFontMap.Width < 56) then
    Exit;
  Result := Trunc(FFontMap.Width / 56);
  if Result < 1 then
    Result := 1;
end;

function TFilePreview.FontContentH: Single;
var
  Rows, Cols, N: Integer;
begin
  Cols := FontCols;
  N := Length(FFontCodes);
  if N < 1 then
    Rows := 1
  else
    Rows := (N + Cols - 1) div Cols;
  Result := Rows * 36;
end;

function TFilePreview.FontOwnedText(const AText: string): string;
var
  I, Code, Lo: Integer;
begin
  // Только коды, которые есть в cmap этого файла. Чужой шрифт их не дорисовывает.
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    Code := Ord(AText[I]);
    if (Code >= $D800) and (Code <= $DBFF) and (I < Length(AText)) then
    begin
      Lo := Ord(AText[I + 1]);
      if (Lo >= $DC00) and (Lo <= $DFFF) then
      begin
        Code := $10000 + ((Code - $D800) shl 10) + (Lo - $DC00);
        if CodeHas(Code) then
          Result := Result + AText[I] + AText[I + 1];
        Inc(I, 2);
        Continue;
      end;
    end;
    if CodeHas(Code) then
      Result := Result + AText[I];
    Inc(I);
  end;
end;

function TFilePreview.FontPreviewLines: TArray<string>;
var
  Phrase, S: string;
  List: TList<string>;
begin
  if Assigned(FFontPhrase) then
    Phrase := FFontPhrase.Text
  else
    Phrase := FFontPhraseText;
  List := TList<string>.Create;
  try
    if Length(FFontAllCodes) = 0 then
    begin
      if Phrase <> '' then
        List.Add(Phrase)
      else
      begin
        List.Add(FONT_LATIN);
        List.Add(FONT_CYR);
        List.Add(FONT_DIGITS);
      end;
    end
    else if Phrase <> '' then
    begin
      S := FontOwnedText(Phrase);
      if Trim(S) <> '' then
        List.Add(S);
    end
    else
    begin
      S := FontOwnedText(FONT_LATIN);
      if Trim(S) <> '' then
        List.Add(S);
      S := FontOwnedText(FONT_CYR);
      if Trim(S) <> '' then
        List.Add(S);
      S := FontOwnedText(FONT_DIGITS);
      if Trim(S) <> '' then
        List.Add(S);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TFilePreview.DrawOwnedLine(ACanvas: TCanvas; const ARect: TRectF;
  const AText: string; ASize: Single; AColor: TAlphaColor);
var
  Sk: ISkCanvas;
  Font: ISkFont;
  Paint: ISkPaint;
  Metrics: TSkFontMetrics;
  State: TCanvasSaveState;
  Shown, Ellipsis: string;
  X, Y, Limit: Single;
  Lo, Hi, Mid: Integer;
begin
  if (AText = '') or (ARect.Width < 2) or (ARect.Height < 2) then
    Exit;
  if (FFontTypeface = nil) or not (ACanvas is TSkCanvasCustom) then
    Exit;
  Sk := TSkCanvasCustom(ACanvas).Canvas;
  if Sk = nil then
    Exit;
  Font := TSkFont.Create(FFontTypeface, ASize);
  Font.Edging := TSkFontEdging.SubpixelAntiAlias;
  Font.Subpixel := True;
  Font.EmbeddedBitmaps := True;
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := AColor;
  if CodeHas($2026) then
    Ellipsis := WideChar($2026)
  else if CodeHas(Ord('.')) then
    Ellipsis := '...'
  else
    Ellipsis := '';
  Shown := AText;
  Limit := ARect.Width;
  if Font.MeasureText(Shown) > Limit then
  begin
    Lo := 0;
    Hi := Length(AText);
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      Shown := Copy(AText, 1, Mid) + Ellipsis;
      if Font.MeasureText(Shown) <= Limit then
        Lo := Mid + 1
      else
        Hi := Mid - 1;
    end;
    if Hi < 0 then
      Hi := 0;
    if (Hi >= 1) and (Hi <= Length(AText)) and
       (Ord(AText[Hi]) >= $D800) and (Ord(AText[Hi]) <= $DFFF) then
      Dec(Hi);
    Shown := Copy(AText, 1, Hi) + Ellipsis;
  end;
  Font.GetMetrics(Metrics);
  X := ARect.Left;
  Y := ARect.CenterPoint.Y - (Metrics.Ascent + Metrics.Descent) / 2;
  State := ACanvas.SaveState;
  try
    ACanvas.IntersectClipRect(ARect);
    Sk.DrawSimpleText(Shown, X, Y, Font, Paint);
  finally
    ACanvas.RestoreState(State);
  end;
end;

procedure TFilePreview.DrawOwnedGlyph(ACanvas: TCanvas; const ARect: TRectF;
  ACode: Integer; ASize: Single; AColor: TAlphaColor);
var
  Sk: ISkCanvas;
  Font: ISkFont;
  Paint: ISkPaint;
  Metrics: TSkFontMetrics;
  Bounds: TRectF;
  State: TCanvasSaveState;
  Text: string;
  X, Y: Single;
begin
  Text := FontCodeText(ACode);
  if Text = '' then
    Exit;
  if (FFontTypeface = nil) or not (ACanvas is TSkCanvasCustom) then
    Exit;
  Sk := TSkCanvasCustom(ACanvas).Canvas;
  if Sk = nil then
    Exit;
  Font := TSkFont.Create(FFontTypeface, ASize);
  Font.Edging := TSkFontEdging.SubpixelAntiAlias;
  Font.Subpixel := True;
  Font.EmbeddedBitmaps := True;
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := AColor;
  Font.MeasureText(Text, Bounds);
  if Bounds.IsEmpty then
  begin
    Font.GetMetrics(Metrics);
    X := ARect.CenterPoint.X;
    Y := ARect.CenterPoint.Y - (Metrics.Ascent + Metrics.Descent) / 2;
  end
  else
  begin
    X := ARect.CenterPoint.X - (Bounds.Left + Bounds.Right) / 2;
    Y := ARect.CenterPoint.Y - (Bounds.Top + Bounds.Bottom) / 2;
  end;
  State := ACanvas.SaveState;
  try
    ACanvas.IntersectClipRect(ARect);
    Sk.DrawSimpleText(Text, X, Y, Font, Paint);
  finally
    ACanvas.RestoreState(State);
  end;
end;

procedure TFilePreview.SyncFontScroll;
var
  MaxS: Single;
begin
  if not Assigned(FFontMap) then
    Exit;
  MaxS := FontContentH - FFontMap.Height;
  if MaxS < 0 then
    MaxS := 0;
  FFontScrollY := EnsureRange(FFontScrollY, 0, MaxS);
  if Assigned(FFontVScroll) and FFontOn then
    FFontVScroll.SetExternalMetrics(FontContentH, FFontMap.Height, FFontScrollY);
end;

procedure TFilePreview.FontBarScroll(APos: Single);
begin
  FFontScrollY := APos;
  if Assigned(FFontMap) then
    FFontMap.Repaint;
end;

procedure TFilePreview.MoveFontSel(ADelta: Integer);
var
  N, Cols, Row: Integer;
  Top, ViewH, MaxS: Single;
begin
  N := Length(FFontCodes);
  if N = 0 then
    Exit;
  if FFontSel < 0 then
    FFontSel := 0;
  FFontSel := EnsureRange(FFontSel + ADelta, 0, N - 1);
  Cols := FontCols;
  if Cols < 1 then
    Cols := 1;
  Row := FFontSel div Cols;
  Top := Row * 36;
  ViewH := 0;
  if Assigned(FFontMap) then
    ViewH := FFontMap.Height;
  if Top < FFontScrollY then
    FFontScrollY := Top
  else if Top + 36 > FFontScrollY + ViewH then
    FFontScrollY := Top + 36 - ViewH;
  MaxS := FontContentH - ViewH;
  if MaxS < 0 then
    MaxS := 0;
  FFontScrollY := EnsureRange(FFontScrollY, 0, MaxS);
  SyncFontScroll;
  if Assigned(FFontMap) then
    FFontMap.Repaint;
  if Assigned(FFontPlatePaint) then
    FFontPlatePaint.Repaint;
end;

procedure TFilePreview.LayoutFont;
var
  W, H, Y, LineH, SampleH, PlateH, TableH, PhraseW, X, BW, Gap, SaveW, FaceW: Single;
  Phrase: string;
begin
  if FDestroying or not FFontOn or not Assigned(FBody) then
    Exit;
  W := FBody.Width;
  H := FBody.Height;
  if W < 80 then
    W := 80;
  if H < 80 then
    H := 80;
  LineH := FFontSize * 1.25;
  if LineH < 18 then
    LineH := 18;
  if Assigned(FFontPhrase) then
    Phrase := FFontPhrase.Text
  else
    Phrase := FFontPhraseText;
  if Phrase <> '' then
    SampleH := LineH + 12
  else
  begin
    SampleH := Length(FontPreviewLines);
    if SampleH < 1 then
      SampleH := 1;
    SampleH := LineH * SampleH + 12;
  end;
  PlateH := 124;
  if SampleH + PlateH + 90 > H then
  begin
    SampleH := LineH + 12;
    if SampleH + 120 > H then
      PlateH := 116;
  end;
  Y := 0;
  if Assigned(FFontSampleBox) then
    FFontSampleBox.SetBounds(0, Y, W, SampleH);
  Y := Y + SampleH + 6;
  SaveW := 0;
  PhraseW := W - 132;
  if PhraseW < 72 then
    PhraseW := 72;
  if PhraseW > W - 132 then
    PhraseW := W - 132;
  if Assigned(FFontPhrase) then
    FFontPhrase.SetBounds(0, Y, PhraseW, 32);
  if Assigned(FFontSlider) then
    FFontSlider.SetBounds(PhraseW + 8, Y, W - PhraseW - 8, 32);
  Y := Y + 38;
  Gap := 4;
  FaceW := 0;
  if Assigned(FFontFaces) and FFontFaces.Visible then
    FaceW := 128;
  if Assigned(FBtnFontSave) and FBtnFontSave.Visible then
    SaveW := 118;
  BW := W - FaceW - SaveW - Gap * 3;
  if FaceW > 0 then
    BW := BW - Gap;
  if SaveW > 0 then
    BW := BW - Gap;
  BW := BW / 4;
  if BW < 28 then
    BW := 28;
  X := 0;
  if Assigned(FFontBtnLatin) then
    FFontBtnLatin.SetBounds(X, Y, BW, 32);
  X := X + BW + Gap;
  if Assigned(FFontBtnCyr) then
    FFontBtnCyr.SetBounds(X, Y, BW, 32);
  X := X + BW + Gap;
  if Assigned(FFontBtnDigit) then
    FFontBtnDigit.SetBounds(X, Y, BW, 32);
  X := X + BW + Gap;
  if Assigned(FFontBtnAll) then
    FFontBtnAll.SetBounds(X, Y, BW, 32);
  X := X + BW + Gap;
  if FaceW > 0 then
    FFontFaces.SetBounds(X, Y, FaceW, 32);
  if SaveW > 0 then
    FBtnFontSave.SetBounds(W - SaveW, Y, SaveW, 32);
  Y := Y + 38;
  TableH := H - PlateH - Y - 4;
  if TableH < 36 then
    TableH := 36;
  if Assigned(FFontMap) then
    FFontMap.SetBounds(0, Y, W - 10, TableH);
  if Assigned(FFontTrack) then
    FFontTrack.SetBounds(W - 8, Y, 8, TableH);
  if Assigned(FFontPlate) then
  begin
    FFontPlate.SetBounds(0, H - PlateH, W, PlateH);
    if Assigned(FFontPlatePaint) then
      FFontPlatePaint.SetBounds(0, 0, W, PlateH - 36);
    X := (W - 248) / 2;
    if X < 0 then
      X := 0;
    if Assigned(FBtnCopyChar) then
    begin
      FBtnCopyChar.Visible := True;
      FBtnCopyChar.SetBounds(X, PlateH - 34, 84, 32);
    end;
    if Assigned(FBtnCopyCode) then
      FBtnCopyCode.SetBounds(X + 92, PlateH - 34, 72, 32);
    if Assigned(FBtnCopyHtml) then
      FBtnCopyHtml.SetBounds(X + 172, PlateH - 34, 76, 32);
  end;
  SyncFontScroll;
  if Assigned(FFontSampleBox) then
    FFontSampleBox.Repaint;
  if Assigned(FFontMap) then
    FFontMap.Repaint;
  if Assigned(FFontPlatePaint) then
    FFontPlatePaint.Repaint;
  if Assigned(FFontSlider) then
    FFontSlider.Repaint;
end;

procedure TFilePreview.PaintFontSample(Sender: TObject; Canvas: TCanvas);
var
  R: TRectF;
  LineH, Y: Single;
  I: Integer;
  Lines: TArray<string>;
begin
  if not Assigned(FFontSampleBox) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FFontSampleBox.LocalRect, 0, 0, [], 1);
  LineH := FFontSize * 1.25;
  if LineH < 18 then
    LineH := 18;
  Lines := FontPreviewLines;
  if Length(Lines) = 0 then
  begin
    Canvas.Font.Family := 'Segoe UI';
    Canvas.Font.Size := 13;
    Canvas.Font.Style := [];
    Canvas.Fill.Color := FColors.SubTextColor;
    R := TRectF.Create(4, 2, FFontSampleBox.Width - 4, FFontSampleBox.Height - 2);
    Canvas.FillText(R, L('font.missing'), False, 1, [],
      TTextAlign.Leading, TTextAlign.Center);
    Exit;
  end;
  Y := 4;
  for I := 0 to High(Lines) do
  begin
    R := TRectF.Create(4, Y, FFontSampleBox.Width - 4, Y + LineH);
    DrawOwnedLine(Canvas, R, Lines[I], FFontSize, FColors.TextColor);
    Y := Y + LineH;
  end;
end;

procedure TFilePreview.PaintFontSlider(Sender: TObject; Canvas: TCanvas);
var
  Track, T, ThumbX: Single;
  R: TRectF;
begin
  if not Assigned(FFontSlider) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FFontSlider.LocalRect, 0, 0, [], 1);
  Track := FFontSlider.Width - 40;
  if Track < 24 then
    Track := 24;
  T := (FFontSize - 12) / (96 - 12);
  T := EnsureRange(T, 0, 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := FColors.DividerColor;
  Canvas.Stroke.Thickness := 3;
  Canvas.DrawLine(TPointF.Create(6, 16), TPointF.Create(6 + Track, 16), 1);
  Canvas.Stroke.Color := FColors.FocusStroke;
  Canvas.DrawLine(TPointF.Create(6, 16), TPointF.Create(6 + Track * T, 16), 1);
  ThumbX := 6 + Track * T;
  Canvas.Fill.Color := FColors.FocusStroke;
  Canvas.FillEllipse(TRectF.Create(ThumbX - 6, 10, ThumbX + 6, 22), 1);
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := FColors.SubTextColor;
  R := TRectF.Create(FFontSlider.Width - 32, 0, FFontSlider.Width, 32);
  Canvas.FillText(R, IntToStr(Round(FFontSize)), False, 1, [], TTextAlign.Trailing,
    TTextAlign.Center);
end;

procedure TFilePreview.PaintFontPlate(Sender: TObject; Canvas: TCanvas);
const
  RowH = 16;
  LabelW = 118;
  GlyphW = 72;
  Gap = 12;
var
  Code, I: Integer;
  Labels: array[0..4] of string;
  Values: array[0..4] of string;
  R, GR: TRectF;
  BlockW, BlockH, X0, Y0, ValueW, Avail, GroupW, Xg: Single;
begin
  if not Assigned(FFontPlatePaint) then
    Exit;
  Labels[0] := 'Unicode';
  Labels[1] := L('font.decimal');
  Labels[2] := 'UTF-8';
  Labels[3] := 'HTML';
  Labels[4] := 'Windows-1251';
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FFontPlatePaint.LocalRect, 0, 0, [], 1);
  Code := SelectedFontCode;
  if Code < 0 then
  begin
    for I := 0 to 4 do
      Values[I] := '';
  end
  else
  begin
    Values[0] := 'U+' + FontHex(Code);
    Values[1] := IntToStr(Code);
    Values[2] := FontUtf8(Code);
    Values[3] := FontHtml(Code);
    Values[4] := Font1251(Code);
  end;
  BlockH := Length(Labels) * RowH;
  Avail := FFontPlatePaint.Width - 8;
  if Avail < 80 then
    Avail := 80;
  ValueW := 168;
  if GlyphW + Gap + LabelW + 16 + ValueW > Avail then
    ValueW := Avail - GlyphW - Gap - LabelW - 16;
  if ValueW < 48 then
    ValueW := 48;
  BlockW := LabelW + 16 + ValueW;
  GroupW := GlyphW + Gap + BlockW;
  if GroupW > Avail then
    GroupW := Avail;
  Xg := (FFontPlatePaint.Width - GroupW) / 2;
  if Xg < 4 then
    Xg := 4;
  Y0 := (FFontPlatePaint.Height - BlockH) / 2;
  if Y0 < 0 then
    Y0 := 0;
  GR := TRectF.Create(Xg, Y0, Xg + GlyphW, Y0 + BlockH);
  if Code >= 0 then
    DrawOwnedGlyph(Canvas, GR, Code, 42, FColors.TextColor);
  X0 := GR.Right + Gap;
  for I := 0 to High(Labels) do
  begin
    Canvas.Font.Family := 'Segoe UI';
    Canvas.Font.Size := 12;
    Canvas.Font.Style := [];
    Canvas.Fill.Color := FColors.SubTextColor;
    R := TRectF.Create(X0, Y0, X0 + LabelW, Y0 + RowH);
    Canvas.FillText(R, Labels[I], False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
    Canvas.Fill.Color := FColors.TextColor;
    R := TRectF.Create(X0 + LabelW + 16, Y0, X0 + BlockW, Y0 + RowH);
    Canvas.FillText(R, Values[I], False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Y0 := Y0 + RowH;
  end;
end;

procedure TFilePreview.FontPhraseChange(Sender: TObject);
begin
  if FFontSilence or not Assigned(FFontPhrase) then
    Exit;
  FFontPhraseText := FFontPhrase.Text;
  WriteFontPhrase(FFontPhraseText);
  LayoutFont;
end;

procedure TFilePreview.FontBlockClick(Sender: TObject);
var
  Tag: Integer;
begin
  if not (Sender is TFluentButton) then
    Exit;
  Tag := TFluentButton(Sender).Tag;
  if Tag = 3 then
  begin
    FFontAll := True;
    FFontLatin := False;
    FFontCyr := False;
    FFontDigit := False;
  end
  else
  begin
    if FFontAll then
    begin
      FFontAll := False;
      FFontLatin := Tag = 0;
      FFontCyr := Tag = 1;
      FFontDigit := Tag = 2;
    end
    else
    begin
      case Tag of
        0: FFontLatin := not FFontLatin;
        1: FFontCyr := not FFontCyr;
        2: FFontDigit := not FFontDigit;
      end;
      if not FFontLatin and not FFontCyr and not FFontDigit then
      begin
        if Tag = 0 then
          FFontLatin := True
        else if Tag = 1 then
          FFontCyr := True
        else
          FFontDigit := True;
      end;
    end;
  end;
  ApplyFontBlocks;
  RebuildFontCodes;
  LayoutFont;
end;

procedure TFilePreview.FontFaceChange(Sender: TObject);
begin
  if FFontSilence or not Assigned(FFontFaces) then
    Exit;
  if FFontFaces.ItemIndex < 0 then
    Exit;
  if FFontFaces.ItemIndex = FFontFaceIndex then
  begin
    if (FFontJob <> nil) and (TFontLoadJob(FFontJob).Face <> FFontFaceIndex) then
    begin
      TFontLoadJob(FFontJob).Cancel := True;
      TFontLoadJob(FFontJob).Preview := nil;
      FFontJob := nil;
    end;
    Exit;
  end;
  if FontFaceReady(FFontFaces.ItemIndex) then
  begin
    if FFontJob <> nil then
    begin
      TFontLoadJob(FFontJob).Cancel := True;
      TFontLoadJob(FFontJob).Preview := nil;
      FFontJob := nil;
    end;
    MountFontFace(FFontFaces.ItemIndex);
    ApplyFontBlocks;
    RebuildFontCodes;
    LayoutFont;
    RefreshFontKind;
  end
  else
    StartFontJob(FPath, FFontFaces.ItemIndex, True);
end;

procedure TFilePreview.FontSliderApply(X: Single);
var
  Track, T: Single;
begin
  if not Assigned(FFontSlider) then
    Exit;
  Track := FFontSlider.Width - 40;
  if Track < 24 then
    Track := 24;
  T := EnsureRange((X - 6) / Track, 0, 1);
  FFontSize := Round(12 + T * (96 - 12));
  FFontSize := EnsureRange(FFontSize, 12, 96);
  LayoutFont;
end;

procedure TFilePreview.FontSliderDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  FFontSliderDrag := True;
  if Assigned(FFontSlider) and Assigned(FFontSlider.Root) then
    FFontSlider.Root.Captured := FFontSlider;
  FontSliderApply(X);
end;

procedure TFilePreview.FontSliderMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if FFontSliderDrag then
    FontSliderApply(X);
end;

procedure TFilePreview.FontSliderUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FFontSliderDrag := False;
  if Assigned(FFontSlider) and Assigned(FFontSlider.Root) and
     Assigned(FFontSlider.Root.Captured) and
     (FFontSlider.Root.Captured.GetObject = FFontSlider) then
    FFontSlider.Root.Captured := nil;
end;

function TFilePreview.SelectedFontCode: Integer;
begin
  Result := -1;
  if (FFontSel >= 0) and (FFontSel < Length(FFontCodes)) then
    Result := FFontCodes[FFontSel];
end;

procedure TFilePreview.CopyFontText(const AText: string);
var
  Svc: IFMXClipboardService;
begin
  if AText = '' then
    Exit;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
  begin
    Svc.SetClipboard(AText);
    ShowToast(L('qv.toast.copied'));
  end;
end;

procedure TFilePreview.CopyFontChar(Sender: TObject);
var
  Code: Integer;
begin
  Code := SelectedFontCode;
  if Code >= 0 then
    CopyFontText(FontCodeText(Code));
end;

procedure TFilePreview.CopyFontCode(Sender: TObject);
var
  Code: Integer;
begin
  Code := SelectedFontCode;
  if Code >= 0 then
    CopyFontText('U+' + FontHex(Code));
end;

procedure TFilePreview.CopyFontHtml(Sender: TObject);
var
  Code: Integer;
begin
  Code := SelectedFontCode;
  if Code >= 0 then
    CopyFontText(FontHtml(Code));
end;

procedure TFilePreview.FontMapDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Cols, Col, Row, Index: Integer;
  CellW: Single;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  if CanFocus then
    SetFocus;
  if not Assigned(FFontMap) or (Length(FFontCodes) = 0) then
    Exit;
  Cols := FontCols;
  CellW := FFontMap.Width / Cols;
  if CellW <= 1 then
    Exit;
  Col := Trunc(X / CellW);
  Row := Trunc((Y + FFontScrollY) / 36);
  if (Col < 0) or (Col >= Cols) or (Row < 0) then
    Exit;
  Index := Row * Cols + Col;
  if (Index < 0) or (Index > High(FFontCodes)) then
    Exit;
  FFontSel := Index;
  FFontMap.Repaint;
  if Assigned(FFontPlatePaint) then
    FFontPlatePaint.Repaint;
end;

procedure TFilePreview.FontMapDbl(Sender: TObject);
begin
  CopyFontChar(nil);
end;

procedure TFilePreview.FontMapWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  Step, MaxS: Single;
begin
  if not FFontOn or not Assigned(FFontMap) then
    Exit;
  MaxS := FontContentH - FFontMap.Height;
  if MaxS < 0 then
    MaxS := 0;
  Step := 36 * 3;
  if WheelDelta > 0 then
    FFontScrollY := FFontScrollY - Step
  else
    FFontScrollY := FFontScrollY + Step;
  FFontScrollY := EnsureRange(FFontScrollY, 0, MaxS);
  SyncFontScroll;
  FFontMap.Repaint;
  Handled := True;
end;

function TFilePreview.FontFreeName(const AExt: string): string;
var
  Dir, Base, Path, Candidate: string;
  N: Integer;
begin
  Dir := FSaveDir;
  if Dir = '' then
    Dir := ExtractFilePath(FPath);
  Base := ChangeFileExt(ExtractFileName(FPath), '');
  N := 1;
  Candidate := Base + AExt;
  repeat
    if N = 1 then
      Candidate := Base + AExt
    else
      Candidate := Base + ' (' + IntToStr(N) + ')' + AExt;
    Path := System.IOUtils.TPath.Combine(Dir, Candidate);
    Inc(N);
  until (N > 100) or
    ((not TFile.Exists(Path)) and
     not SameText(ExpandFileName(Path), ExpandFileName(FPath)));
  Result := Candidate;
end;

procedure TFilePreview.FillFontFormats;
var
  I: Integer;
begin
  if not Assigned(FSaveFmt) then
    Exit;
  FFontOffers := FontOffers(FFontProbe, BrotliBesideExe);
  FSaveSilence := True;
  try
    FSaveFmt.Items.Clear;
    for I := 0 to High(FFontOffers) do
      FSaveFmt.Items.Add(FFontOffers[I].Caption);
    if FSaveFmt.Items.Count > 0 then
      FSaveFmt.ItemIndex := 0;
  finally
    FSaveSilence := False;
  end;
end;

procedure TFilePreview.OpenFontSave;
begin
  if not FFontOn or not FFontCanSave or FFontWriting then
    Exit;
  FSaveMedia := False;
  FSaveFont := True;
  FSaveNameOwn := False;
  FSaveArmed := False;
  FSaveBlocked := FFontProblem <> '';
  if Assigned(FSaveKindRow) then
    FSaveKindRow.Visible := False;
  if Assigned(FSaveRange) then
    FSaveRange.Visible := False;
  if Assigned(FSaveTitle) then
    FSaveTitle.Text := L('qv.save');
  FSaveDir := ExtractFilePath(FPath);
  if Assigned(FSaveFolder) then
    FSaveFolder.Text := FSaveDir;
  FillFontFormats;
  FSaveSilence := True;
  try
    if Length(FFontOffers) > 0 then
      FSaveName.Text := FontFreeName(FFontOffers[0].Ext)
    else
      FSaveName.Text := ChangeFileExt(ExtractFileName(FPath), '');
  finally
    FSaveSilence := False;
  end;
  if Assigned(FSaveNote) then
  begin
    FSaveNote.Text := L('font.woff2');
    FSaveNote.Visible := not BrotliBesideExe;
  end;
  if Assigned(FSaveOk) then
  begin
    FSaveOk.Enabled := (FFontProblem = '') and (Length(FFontOffers) > 0);
    if FSaveOk.Enabled then
      FSaveOk.Opacity := 1
    else
      FSaveOk.Opacity := 0.4;
  end;
  RefreshSaveExists;
  if Assigned(FSaveShade) then
  begin
    FSaveShade.Visible := True;
    FSaveShade.BringToFront;
  end;
  LayoutSaveCard(nil);
  if Assigned(FSaveName) and FSaveName.CanFocus then
    FSaveName.SetFocus;
end;

procedure TFilePreview.FontSaveClick(Sender: TObject);
begin
  if Assigned(FSaveShade) and FSaveShade.Visible and FSaveFont then
    CommitSave
  else
    OpenFontSave;
end;

procedure TFilePreview.CommitFontSave;
var
  Path, Err, Dir, Base, Ext, Candidate: string;
  Offer: TFontOffer;
  N: Integer;
begin
  if FFontWriting or not FSaveFont then
    Exit;
  if (FSaveFmt = nil) or (FSaveFmt.ItemIndex < 0) or
     (FSaveFmt.ItemIndex > High(FFontOffers)) then
    Exit;
  if FFontProblem <> '' then
    Exit;
  Offer := FFontOffers[FSaveFmt.ItemIndex];
  Path := SaveTargetPath;
  if Path = '' then
    Exit;
  if SameText(ExpandFileName(Path), ExpandFileName(FPath)) or TFile.Exists(Path) then
  begin
    Dir := ExtractFilePath(Path);
    Base := ChangeFileExt(ExtractFileName(FPath), '');
    Ext := Offer.Ext;
    N := 2;
    repeat
      Candidate := Base + ' (' + IntToStr(N) + ')' + Ext;
      Path := System.IOUtils.TPath.Combine(Dir, Candidate);
      Inc(N);
    until (N > 100) or
      ((not TFile.Exists(Path)) and
       not SameText(ExpandFileName(Path), ExpandFileName(FPath)));
  end;
  FFontWriting := True;
  if Assigned(FSaveOk) then
  begin
    FSaveOk.Enabled := False;
    FSaveOk.Opacity := 0.4;
  end;
  if Assigned(FBtnFontSave) then
    FBtnFontSave.Enabled := False;
  try
    Err := '';
    if ConvertFont(FPath, Path, Offer.Target, Err) then
    begin
      FLastSaved := Path;
      CloseSaveCard;
      ShowToast(Lf('qv.toast.savedas', [Path]));
      if Assigned(FOnDiskChanged) then
        FOnDiskChanged(Self);
      FLastSaved := '';
    end
    else
    begin
      if Err = '' then
        Err := L('qv.writefail');
      if Assigned(FSaveExists) then
      begin
        FSaveExists.Text := Err;
        FSaveExists.Visible := True;
      end;
      LayoutSaveCard(nil);
    end;
  finally
    FFontWriting := False;
    if Assigned(FBtnFontSave) then
      FBtnFontSave.Enabled := True;
    if Assigned(FSaveOk) and Assigned(FSaveShade) and FSaveShade.Visible then
    begin
      FSaveOk.Enabled := FFontProblem = '';
      if FSaveOk.Enabled then
        FSaveOk.Opacity := 1
      else
        FSaveOk.Opacity := 0.4;
    end;
  end;
end;

function TFilePreview.LoadAsFont(const APath: string): Boolean;
begin
  Result := True;
  FFontProblem := '';
  FFontGlyphs := 0;
  FFontSize := 28;
  FFontScrollY := 0;
  FFontSel := 0;
  FFontAll := False;
  FFontLatin := True;
  FFontCyr := True;
  FFontDigit := True;
  FFontCanSave := False;
  FFontPhraseText := ReadFontPhrase;
  FFontSilence := True;
  try
    if Assigned(FFontPhrase) then
      FFontPhrase.Text := FFontPhraseText;
    if Assigned(FFontFaces) then
      FFontFaces.Items.Clear;
  finally
    FFontSilence := False;
  end;
  ShowInfoKey('qv.loading');
  if Assigned(FInfo) then
  begin
    FInfo.Visible := True;
    FInfo.BringToFront;
  end;
  StartFontJob(APath, 0, False);
end;

function TFilePreview.HandleFontKey(var Key: Word; Shift: TShiftState): Boolean;
var
  Code, Cols, Delta: Integer;

  function ArrowTarget: Boolean;
  var
    Form: TCommonCustomForm;
  begin
    { Окно F3 само получает клавиши. Колонка — только с фокусом в просмотре. }
    Result := HasKeyboardFocus;
    if Result or not Assigned(Root) then
      Exit;
    if not (Root.GetObject is TCommonCustomForm) then
      Exit;
    Form := TCommonCustomForm(Root.GetObject);
    Result := Form is TQuickViewForm;
  end;

begin
  Result := False;
  if not FFontOn then
    Exit;
  if Assigned(FSaveShade) and FSaveShade.Visible and FSaveFont and (Key = vkEscape) and
     not (ssAlt in Shift) then
  begin
    CloseSaveCard;
    Exit(True);
  end;
  if Assigned(FFontPhrase) and FFontPhrase.IsFocused then
    Exit;
  if Assigned(FSaveName) and FSaveName.IsFocused then
    Exit;
  if Assigned(FFontFaces) and FFontFaces.EditorFocused then
    Exit;
  if not (ssAlt in Shift) and not (ssCtrl in Shift) and
     not (Assigned(FSaveShade) and FSaveShade.Visible and FSaveFont) and
     (Length(FFontCodes) > 0) and ArrowTarget then
  begin
    Cols := FontCols;
    if Cols < 1 then
      Cols := 1;
    Delta := 0;
    case Key of
      vkLeft: Delta := -1;
      vkRight: Delta := 1;
      vkUp: Delta := -Cols;
      vkDown: Delta := Cols;
    end;
    if Delta <> 0 then
    begin
      MoveFontSel(Delta);
      Exit(True);
    end;
  end;
  if (Key <> vkC) or not (ssCtrl in Shift) or (ssAlt in Shift) then
    Exit;
  Code := SelectedFontCode;
  if Code < 0 then
    Exit;
  CopyFontText(FontCodeText(Code));
  Result := True;
end;

function OwningPreview(AFrom: TFmxObject): TFilePreview;
var
  O: TFmxObject;
begin
  Result := nil;
  O := AFrom;
  while O <> nil do
  begin
    if O is TFilePreview then
      Exit(TFilePreview(O));
    O := O.Parent;
  end;
end;

procedure TSheetDocView.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  Preview: TFilePreview;
begin
  Preview := OwningPreview(Self);
  if Assigned(Preview) and Preview.SheetHotkey(Key, Shift, False) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  inherited;
end;

procedure TSheetGrid.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  Preview: TFilePreview;
begin
  Preview := OwningPreview(Self);
  if Assigned(Preview) and Preview.SheetHotkey(Key, Shift, False) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  inherited;
end;

procedure TFilePreview.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if HandleFontKey(Key, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if SheetHotkey(Key, Shift, ImgViewActive) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  inherited;
end;

function PanoEase(T: Single): Single;
begin
  T := EnsureRange(T, 0, 1);
  Result := 1 - Power(1 - T, 3);
end;

procedure PanoSplit(ABytes: Int64; out ANum, AUnit: string);
var
  V: Double;
begin
  if ABytes < 0 then
    ABytes := 0;
  if ABytes >= Int64(1024) * 1024 * 1024 then
  begin
    V := ABytes / (Int64(1024) * 1024 * 1024);
    ANum := StringReplace(FormatFloat('0.0', V), ',', '.', []);
    AUnit := L('qv.unit.gb');
  end
  else if ABytes >= 1024 * 1024 then
  begin
    V := ABytes / (1024 * 1024);
    if Abs(V - Round(V)) < 0.05 then
      ANum := IntToStr(Round(V))
    else
      ANum := StringReplace(FormatFloat('0.0', V), ',', '.', []);
    AUnit := L('qv.unit.mb');
  end
  else if ABytes >= 1024 then
  begin
    ANum := IntToStr(ABytes div 1024);
    AUnit := L('qv.unit.kb');
  end
  else
  begin
    ANum := IntToStr(ABytes);
    AUnit := L('qv.unit.b');
  end;
end;

function PanoCat(const AExt: string): Integer;
begin
  if MatchText(AExt, ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tif',
    '.tiff', '.heic', '.psd', '.psb', '.svg', '.cr2', '.nef', '.arw', '.dng']) then
    Exit(0);
  if IsVideoMetaExt(AExt) then
    Exit(1);
  if MatchText(AExt, ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.txt', '.md', '.rtf', '.odt', '.ods', '.csv']) then
    Exit(2);
  Result := 3;
end;

type
  TPanoCacheRec = record
    Photo, Video, Docs, Other: Int64;
    Files, Folders: Integer;
    Partial, Failed: Boolean;
  end;

var
  GPanoCache: TDictionary<string, TPanoCacheRec>;
  GPeCache: TDictionary<string, TPeInfo>;

function PanoCacheKey(const APath: string; AArchive: Boolean): string;
var
  Age: TDateTime;
  Sz: Int64;
begin
  Sz := 0;
  Age := 0;
  try
    if AArchive then
    begin
      Age := TFile.GetLastWriteTime(APath);
      Sz := TFile.GetSize(APath);
    end
    else
      Age := TDirectory.GetLastWriteTime(ExcludeTrailingPathDelimiter(APath));
  except
  end;
  Result := LowerCase(ExcludeTrailingPathDelimiter(APath)) + '|' +
    IntToStr(Ord(AArchive)) + '|' + IntToStr(Sz) + '|' + FloatToStr(Age);
end;

procedure TFilePreview.HidePanorama;
begin
  Inc(FPanoToken);
  FPanoAnim := False;
  FPanoIconTicks := 0;
  if Assigned(FPanoTimer) then
    FPanoTimer.Enabled := False;
  if Assigned(FPanoBox) then
    FPanoBox.Visible := False;
end;

procedure TFilePreview.PanoTick(Sender: TObject);
begin
  if FPanoAnim and (TThread.GetTickCount - FPanoAnimAt >= 800) then
    FPanoAnim := False;
  if not FPanoAnim and (FPanoIconTicks > 0) then
    Dec(FPanoIconTicks);
  if Assigned(FPanoBox) then
    FPanoBox.Repaint;
  if (not FPanoAnim) and (FPanoIconTicks <= 0) and Assigned(FPanoTimer) then
    FPanoTimer.Enabled := False;
end;

procedure TFilePreview.PaintPanorama(Sender: TObject; Canvas: TCanvas);
const
  CPhoto = $FF00D4FF;
  CVideo = $FFA277FF;
  CDocs = $FFFF77A9;
  COther = $FF505050;
var
  W, H, Side, Gap, ColW, RowH: Single;
  CX, CY, R, Thick, LegendTop, FootY: Single;
  Total: Int64;
  Parts: array[0..3] of Int64;
  Colors: array[0..3] of TAlphaColor;
  Names: array[0..3] of string;
  I, Shown, Cols: Integer;
  StartA, Sweep, Rot, Ease, Op: Single;
  Num, UnitName, Cap: string;
  RText, Dest: TRectF;
  Seg: Integer;
  Entry: TFileEntry;
  Bmp: FMX.Graphics.TBitmap;
  Scale, Fit, Dw, Dh, BlockW, Origin, CellW: Single;
  Vals: array[0..3] of string;
  ItemW: array[0..3] of Single;
  LeftW, RightW, GapX, X0: Single;
  Arc, Inner: string;
begin
  if Canvas = nil then
    Exit;
  W := FPanoBox.Width;
  H := FPanoBox.Height;
  if (W < 40) or (H < 40) then
    Exit;
  Parts[0] := FPanoPhoto;
  Parts[1] := FPanoVideo;
  Parts[2] := FPanoDocs;
  Parts[3] := FPanoOther;
  Colors[0] := CPhoto;
  Colors[1] := CVideo;
  Colors[2] := CDocs;
  Colors[3] := COther;
  Names[0] := L('qv.pano.photo');
  Names[1] := L('qv.pano.video');
  Names[2] := L('qv.pano.docs');
  Names[3] := L('qv.pano.other');
  Total := Parts[0] + Parts[1] + Parts[2] + Parts[3];
  if W < 280 then
  begin
    Cols := 1;
    RowH := 38;
  end
  else
  begin
    Cols := 2;
    RowH := 44;
  end;
  LegendTop := H - 28 - RowH * (4 div Cols) - 12;
  if LegendTop < 140 then
    LegendTop := 140;
  Side := Min(220, Min(W - 32, LegendTop - 96));
  if Side < 96 then
    Side := 96;
  CX := W / 2;
  CY := 78 + (LegendTop - 78) / 2;
  if CY + Side / 2 > LegendTop - 4 then
    CY := LegendTop - 4 - Side / 2;
  Thick := 18;
  R := Side / 2 - Thick / 2;

  Entry := TFileEntry.FromPath(FPath);
  if SplitArchivePath(FPath, Arc, Inner) and (Inner <> '') then
  begin
    if ArchivePathIsFolder(FPath) then
    begin
      Entry.IsDirectory := True;
      Entry.IconKey := '#dir';
      Entry.NeedsCustomIcon := False;
    end
    else if IsArchiveFileName(FPath) or IsArchiveFileName(Inner) then
    begin
      Entry.IsDirectory := False;
      Entry.Extension := ExtractFileExt(Inner);
      if Entry.Extension = '' then
        Entry.Extension := ExtractFileExt(FPath);
      Entry.IconKey := LowerCase(Entry.Extension);
      Entry.NeedsCustomIcon := False;
    end;
  end;
  Scale := 1;
  if Assigned(Scene) then
    Scale := Scene.GetSceneScale;
  if Scale < 1 then
    Scale := 1;
  Bmp := nil;
  if Assigned(GlobalIconCache) then
    Bmp := GlobalIconCache.GetForPaint(Entry, ib64, Scale);
  if (Bmp = nil) and (FPanoIconTicks <= 0) then
    FPanoIconTicks := 20;
  if Assigned(Bmp) and (Bmp.Width > 0) and (Bmp.Height > 0) then
  begin
    Fit := Min(48 / Bmp.Width, 48 / Bmp.Height);
    if Fit > 1 then
      Fit := 1;
    Dw := Bmp.Width * Fit;
    Dh := Bmp.Height * Fit;
    Dest := TRectF.Create(18 + (48 - Dw) / 2, 10 + (48 - Dh) / 2,
      18 + (48 - Dw) / 2 + Dw, 10 + (48 - Dh) / 2 + Dh);
    Canvas.DrawBitmap(Bmp, Bmp.Bounds, Dest, 1, False);
  end;
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 18;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.Fill.Color := FColors.TextColor;
  Cap := FTitle.Text;
  Canvas.FillText(TRectF.Create(76, 14, W - 16, 38), Cap, False, 1, [],
    TTextAlign.Leading, TTextAlign.Center);
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := FColors.SubTextColor;
  Canvas.FillText(TRectF.Create(76, 38, W - 16, 56), FPath, True, 1, [],
    TTextAlign.Leading, TTextAlign.Center);

  Ease := 1;
  Rot := 0;
  Op := 1;
  if FPanoAnim then
  begin
    Ease := PanoEase((TThread.GetTickCount - FPanoAnimAt) / 800);
    Rot := -90 * (1 - Ease);
    Op := Ease;
  end;

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := Thick;
  Canvas.Stroke.Cap := TStrokeCap.Flat;
  Canvas.Stroke.Join := TStrokeJoin.Miter;
  if (not FPanoReady) or FPanoFailed or (Total <= 0) then
  begin
    Canvas.Stroke.Color := COther;
    Canvas.DrawArc(TPointF.Create(CX, CY), TPointF.Create(R, R), -90, 359.5, 1);
  end
  else
  begin
    Shown := 0;
    for I := 0 to 3 do
      if Parts[I] > 0 then
        Inc(Shown);
    if Shown < 2 then
      Gap := 0
    else
      Gap := 3;
    StartA := -90 + Rot;
    for I := 0 to 3 do
    begin
      if Parts[I] <= 0 then
        Continue;
      Sweep := 360 * Parts[I] / Total;
      if Shown > 1 then
      begin
        if Sweep <= Gap + 0.4 then
        begin
          StartA := StartA + Sweep;
          Continue;
        end;
        Canvas.Stroke.Color := Colors[I];
        Canvas.DrawArc(TPointF.Create(CX, CY), TPointF.Create(R, R),
          StartA + Gap / 2, Sweep - Gap, Op);
      end
      else
      begin
        Canvas.Stroke.Color := Colors[I];
        Canvas.DrawArc(TPointF.Create(CX, CY), TPointF.Create(R, R), StartA, Sweep, Op);
      end;
      StartA := StartA + Sweep;
    end;
  end;

  PanoSplit(Total, Num, UnitName);
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 28;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.Fill.Color := FColors.TextColor;
  Canvas.FillText(TRectF.Create(CX - R + 8, CY - 22, CX + R - 8, CY + 8), Num,
    False, 1, [], TTextAlign.Center, TTextAlign.Center);
  Canvas.Font.Size := 13;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := FColors.SubTextColor;
  Cap := UnitName;
  if FPanoFailed then
    Cap := L('qv.pano.empty')
  else if not FPanoReady then
    Cap := Lf('qv.pano.counting', [UnitName])
  else if FPanoPartial then
    Cap := Lf('qv.pano.partial', [UnitName]);
  Canvas.FillText(TRectF.Create(CX - R + 4, CY + 8, CX + R - 4, CY + 28), Cap,
    False, 1, [], TTextAlign.Center, TTextAlign.Center);

  Canvas.Font.Family := 'Segoe UI';
  for I := 0 to 3 do
  begin
    PanoSplit(Parts[I], Num, UnitName);
    Vals[I] := Num + ' ' + UnitName;
    Canvas.Font.Size := 12;
    Canvas.Font.Style := [];
    ItemW[I] := Canvas.TextWidth(Names[I]);
    Canvas.Font.Size := 14;
    Canvas.Font.Style := [TFontStyle.fsBold];
    ItemW[I] := Max(ItemW[I], Canvas.TextWidth(Vals[I])) + 20;
  end;
  GapX := 40;
  if Cols = 1 then
  begin
    BlockW := ItemW[0];
    for I := 1 to 3 do
      if ItemW[I] > BlockW then
        BlockW := ItemW[I];
  end
  else
  begin
    LeftW := Max(ItemW[0], ItemW[2]);
    RightW := Max(ItemW[1], ItemW[3]);
    BlockW := LeftW + GapX + RightW;
  end;
  Origin := (W - BlockW) / 2;
  for I := 0 to 3 do
  begin
    if Cols = 1 then
      X0 := (W - ItemW[I]) / 2
    else if (I mod 2) = 0 then
      X0 := Origin
    else
      X0 := Origin + LeftW + GapX;
    RText := TRectF.Create(X0, LegendTop + (I div Cols) * RowH,
      X0 + ItemW[I], LegendTop + (I div Cols) * RowH + RowH);
    Canvas.Fill.Color := Colors[I];
    Canvas.FillEllipse(TRectF.Create(RText.Left, RText.Top + 2, RText.Left + 12, RText.Top + 14), 1);
    Canvas.Font.Size := 12;
    Canvas.Font.Style := [];
    Canvas.Fill.Color := FColors.SubTextColor;
    Canvas.FillText(TRectF.Create(RText.Left + 18, RText.Top, RText.Right + 8, RText.Top + 16),
      Names[I], False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
    Canvas.Font.Size := 14;
    Canvas.Font.Style := [TFontStyle.fsBold];
    Canvas.Fill.Color := FColors.TextColor;
    Canvas.FillText(TRectF.Create(RText.Left + 18, RText.Top + 16, RText.Right + 8, RText.Top + 36),
      Vals[I], False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
  end;

  FootY := H - 26;
  Canvas.Stroke.Thickness := 1;
  Canvas.Stroke.Color := FColors.DividerColor;
  Canvas.DrawLine(TPointF.Create(16, FootY - 8), TPointF.Create(W - 16, FootY - 8), 1);
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := FColors.SubTextColor;
  Canvas.FillText(TRectF.Create(16, FootY - 4, W / 2, H),
    LCount(FPanoFiles, 'qv.count.file.one', 'qv.count.file.few', 'qv.count.file.many'),
    False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
  Canvas.FillText(TRectF.Create(W / 2, FootY - 4, W - 16, H),
    LCount(FPanoFolders, 'qv.count.folder.one', 'qv.count.folder.few', 'qv.count.folder.many'),
    False, 1, [], TTextAlign.Trailing, TTextAlign.Leading);
end;

procedure TFilePreview.HidePe;
begin
  Inc(FPeToken);
  FPeReady := False;
  FPeHex := False;
  FPeScroll := 0;
  if Assigned(FPeBox) then
    FPeBox.Visible := False;
  if Assigned(FPeHexBtn) then
    FPeHexBtn.Visible := False;
  if Assigned(FPeIcon) then
    FPeIcon.SetSize(0, 0);
end;

procedure TFilePreview.PlacePeHex;
begin
  if not Assigned(FPeHexBtn) or not Assigned(FHeader) then
    Exit;
  if FPeHexBtn.Parent <> FHeader then
    FPeHexBtn.Parent := FHeader;
  FPeHexBtn.Align := TAlignLayout.Right;
  FPeHexBtn.Width := 96;
  FPeHexBtn.Margins.Rect := TRectF.Create(2, 4, 8, 4);
end;

procedure TFilePreview.PeHexClick(Sender: TObject);
begin
  if FPath = '' then
    Exit;
  FPeHex := not FPeHex;
  if FPeHex then
  begin
    if Assigned(FPeBox) then
      FPeBox.Visible := False;
    LoadAsHex(FPath);
    if Assigned(FPeHexBtn) then
    begin
      FPeHexBtn.SetCaption(L('qv.card'));
      FPeHexBtn.Visible := True;
    end;
  end
  else
  begin
    if Assigned(FMemo) then
      FMemo.Visible := False;
    if Assigned(FPeBox) then
    begin
      FPeBox.Visible := True;
      FPeBox.Repaint;
    end;
    if Assigned(FPeHexBtn) then
      FPeHexBtn.SetCaption(L('qv.hex'));
    if FPe.Ok then
    begin
      if FPe.Arch = '64-bit' then
        SetKindRaw(FPe.Kind + ' · 64')
      else if FPe.Arch = '32-bit' then
        SetKindRaw(FPe.Kind + ' · 32')
      else
        SetKindRaw(FPe.Kind);
    end;
  end;
  PlacePeHex;
end;

procedure TFilePreview.PaintPe(Sender: TObject; Canvas: TCanvas);
var
  Y, X, ColW: Single;
  Facts, Line, Sign: string;
  I, Col: Integer;
  Bmp: FMX.Graphics.TBitmap;
  Entry: TFileEntry;
  Scale, Fit, Dw, Dh: Single;
  Dest: TRectF;
  RowsK, RowsV: array of string;
  RowsW: array of Boolean;

  procedure AddRow(const K, V: string; Warn: Boolean);
  var
    N: Integer;
  begin
    if V = '' then
      Exit;
    N := Length(RowsK);
    SetLength(RowsK, N + 1);
    SetLength(RowsV, N + 1);
    SetLength(RowsW, N + 1);
    RowsK[N] := K;
    RowsV[N] := V;
    RowsW[N] := Warn;
  end;

  procedure Heading(const S: string);
  begin
    Y := Y + 14;
    Canvas.Font.Size := 13;
    Canvas.Font.Style := [TFontStyle.fsBold];
    Canvas.Fill.Color := FColors.TextColor;
    Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 18), S, False, 1,
      [], TTextAlign.Leading, TTextAlign.Leading);
    Y := Y + 22;
  end;

begin
  if Canvas = nil then
    Exit;
  Canvas.IntersectClipRect(TRectF.Create(0, 0, FPeBox.Width, FPeBox.Height));
  Y := 16 - FPeScroll;
  X := 18;
  if Assigned(FPeIcon) and (FPeIcon.Width > 8) then
    Canvas.DrawBitmap(FPeIcon, FPeIcon.Bounds,
      TRectF.Create(X, Y, X + 96, Y + 96), 1, False)
  else
  begin
    Entry := TFileEntry.FromPath(FPath);
    Scale := 1;
    if Assigned(Scene) then
      Scale := Scene.GetSceneScale;
    if Scale < 1 then
      Scale := 1;
    Bmp := nil;
    if Assigned(GlobalIconCache) then
      Bmp := GlobalIconCache.GetForPaint(Entry, ib64, Scale);
    if Assigned(Bmp) and (Bmp.Width > 0) then
    begin
      Fit := Min(96 / Bmp.Width, 96 / Bmp.Height);
      if Fit > 1 then
        Fit := 1;
      Dw := Bmp.Width * Fit;
      Dh := Bmp.Height * Fit;
      Dest := TRectF.Create(X + (96 - Dw) / 2, Y + (96 - Dh) / 2,
        X + (96 - Dw) / 2 + Dw, Y + (96 - Dh) / 2 + Dh);
      Canvas.DrawBitmap(Bmp, Bmp.Bounds, Dest, 1, False);
    end;
  end;
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 18;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.Fill.Color := FColors.TextColor;
  Canvas.FillText(TRectF.Create(128, Y, FPeBox.Width - 12, Y + 26), FTitle.Text,
    True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
  Line := FPe.Product;
  if FPe.Description <> '' then
  begin
    if Line <> '' then
      Line := Line + ' — ';
    Line := Line + FPe.Description;
  end;
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := FColors.SubTextColor;
  Canvas.FillText(TRectF.Create(128, Y + 28, FPeBox.Width - 12, Y + 62), Line,
    True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
  if not FPeReady then
    Facts := L('qv.pe.reading')
  else if FPe.Fail <> '' then
    Facts := PePhrase(FPe.Fail)
  else if not FPe.Ok then
    Facts := L('qv.pe.notpe')
  else
  begin
    Facts := PePhrase(FPe.Arch);
    if FPe.Machine <> '' then
      Facts := Facts + ' ' + FPe.Machine;
    if FPe.Subsystem <> '' then
      Facts := Facts + ' · ' + PePhrase(FPe.Subsystem);
    if FPe.IsDotNet then
      Facts := Facts + ' · .NET'
    else
      Facts := Facts + ' · ' + L('qv.pe.native');
    if FPe.Elevation <> '' then
      Facts := Facts + ' · ' + PePhrase(FPe.Elevation);
    if FPe.Signed = 1 then
    begin
      Sign := L('qv.pe.signed');
      if FPe.Publisher <> '' then
        Sign := Sign + ' · ' + FPe.Publisher;
    end
    else if FPe.Signed = 2 then
      Sign := L('qv.pe.badsig')
    else
      Sign := L('qv.pe.unsigned');
    Facts := Facts + ' · ' + Sign;
  end;
  Canvas.Font.Size := 12;
  Canvas.Fill.Color := FColors.TextColor;
  Canvas.FillText(TRectF.Create(128, Y + 66, FPeBox.Width - 12, Y + 96), Facts,
    True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
  Y := Y + 108;
  if FPeReady and FPe.Ok then
  begin
    AddRow(L('qv.pe.desc'), FPe.Description, False);
    AddRow(L('qv.pe.product'), FPe.Product, False);
    AddRow(L('qv.pe.filever'), FPe.FileVer, False);
    AddRow(L('qv.pe.prodver'), FPe.ProdVer, False);
    AddRow(L('qv.pe.company'), FPe.Company, False);
    AddRow(L('qv.pe.rights'), FPe.Copyright, False);
    AddRow(L('qv.pe.original'), FPe.Original, FPe.NameMismatch);
    AddRow(L('qv.pe.built'), FPe.Built, False);
    if Length(RowsK) > 0 then
    begin
      Heading(L('qv.pe.about'));
      ColW := (FPeBox.Width - 40) / 2;
      if FPeBox.Width < 460 then
        ColW := FPeBox.Width - 36;
      for I := 0 to High(RowsK) do
      begin
        if FPeBox.Width < 460 then
        begin
          Col := 0;
          X := 18;
        end
        else
        begin
          Col := I mod 2;
          X := 18 + Col * ColW;
        end;
        Canvas.Font.Size := 11;
        Canvas.Font.Style := [];
        Canvas.Fill.Color := FColors.SubTextColor;
        Canvas.FillText(TRectF.Create(X, Y, X + ColW - 8, Y + 14), RowsK[I],
          False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
        Canvas.Font.Size := 13;
        if RowsW[I] then
          Canvas.Fill.Color := FColors.DangerColor
        else
          Canvas.Fill.Color := FColors.TextColor;
        Canvas.FillText(TRectF.Create(X, Y + 14, X + ColW - 8, Y + 32), RowsV[I],
          True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
        if (FPeBox.Width < 460) or (Col = 1) or (I = High(RowsK)) then
          Y := Y + 36;
      end;
    end;
    if Length(FPe.Imports) > 0 then
    begin
      Heading(L('qv.pe.imports'));
      Canvas.Font.Size := 12;
      Canvas.Font.Style := [];
      for I := 0 to High(FPe.Imports) do
      begin
        if FPe.Imports[I].Missing then
        begin
          Canvas.Fill.Color := FColors.DangerColor;
          Line := Lf('qv.pe.missing', [FPe.Imports[I].Name]);
        end
        else
        begin
          Canvas.Fill.Color := FColors.TextColor;
          Line := FPe.Imports[I].Name;
        end;
        Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 16), Line,
          False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
        Y := Y + 16;
      end;
      if FPe.ImportMore > 0 then
      begin
        Canvas.Fill.Color := FColors.SubTextColor;
        Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 16),
          Lf('qv.pe.more', [FPe.ImportMore]), False, 1, [],
          TTextAlign.Leading, TTextAlign.Leading);
        Y := Y + 16;
      end;
    end;
    if (FPe.IsDll or (FPe.Kind = 'DLL') or (FPe.Kind = 'CPL')) and
       ((Length(FPe.ExportNames) > 0) or (FPe.ExportMore > 0)) then
    begin
      Heading(L('qv.pe.exports'));
      Canvas.Font.Size := 12;
      Canvas.Font.Style := [];
      Canvas.Fill.Color := FColors.TextColor;
      for I := 0 to High(FPe.ExportNames) do
      begin
        Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 16), FPe.ExportNames[I],
          True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
        Y := Y + 16;
      end;
      if FPe.ExportMore > 0 then
      begin
        Canvas.Fill.Color := FColors.SubTextColor;
        Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 16),
          Lf('qv.pe.more', [FPe.ExportMore]), False, 1, [],
          TTextAlign.Leading, TTextAlign.Leading);
        Y := Y + 16;
      end;
    end;
    if (FPe.IconCount > 0) or (FPe.ManifestCount > 0) or (FPe.VersionCount > 0) or
       (FPe.StringCount > 0) then
    begin
      Heading(L('qv.pe.inside'));
      Canvas.Font.Size := 12;
      Canvas.Font.Style := [];
      Canvas.Fill.Color := FColors.TextColor;
      Line := '';
      if FPe.IconCount > 0 then
        Line := Line + Lf('qv.pe.icons', [FPe.IconCount]) + '   ';
      if FPe.ManifestCount > 0 then
        Line := Line + Lf('qv.pe.manifest', [FPe.ManifestCount]) + '   ';
      if FPe.VersionCount > 0 then
        Line := Line + Lf('qv.pe.version', [FPe.VersionCount]) + '   ';
      if FPe.StringCount > 0 then
        Line := Line + Lf('qv.pe.strings', [FPe.StringCount]);
      Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 18), Trim(Line),
        False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
      Y := Y + 20;
      Canvas.Fill.Color := FColors.SubTextColor;
      for I := 0 to High(FPe.Strings) do
      begin
        Canvas.FillText(TRectF.Create(18, Y, FPeBox.Width - 16, Y + 16), FPe.Strings[I],
          True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
        Y := Y + 16;
      end;
    end;
  end;
  FPeContentH := Y + FPeScroll + 48;
end;

procedure TFilePreview.AcceptPe(AToken: Integer; const AKey, APath: string;
  const AInfo: TPeInfo);
begin
  if FDestroying or (FPeToken <> AToken) then
    Exit;
  FPe := AInfo;
  FPeReady := True;
  if not AInfo.Ok then
  begin
    if Assigned(FPeBox) then
      FPeBox.Repaint;
    Exit;
  end;
  if FPeIcon = nil then
    FPeIcon := TBitmap.Create;
  try
    LoadPeIcon(APath, FPeIcon);
  except
    FPeIcon.SetSize(0, 0);
  end;
  if AInfo.Arch = '64-bit' then
    SetKindRaw(AInfo.Kind + ' · 64')
  else if AInfo.Arch = '32-bit' then
    SetKindRaw(AInfo.Kind + ' · 32')
  else
    SetKindRaw(AInfo.Kind);
  if GPeCache = nil then
    GPeCache := TDictionary<string, TPeInfo>.Create;
  GPeCache.AddOrSetValue(AKey, AInfo);
  if Assigned(FPeBox) then
    FPeBox.Repaint;
end;

procedure TFilePreview.ShowPe(const APath: string);
var
  Token: Integer;
  Key: string;
  Age: TDateTime;
  Sz: Int64;
  Hit: TPeInfo;
begin
  Inc(FPeToken);
  Token := FPeToken;
  FPe := Default(TPeInfo);
  FPeReady := False;
  FPeHex := False;
  FPeScroll := 0;
  FPeContentH := 0;
  Sz := 0;
  Age := 0;
  try
    Age := TFile.GetLastWriteTime(APath);
    Sz := TFile.GetSize(APath);
  except
  end;
  Key := LowerCase(APath) + '|' + IntToStr(Sz) + '|' + FloatToStr(Age);
  FPeKey := Key;
  if FPeBox = nil then
  begin
    FPeBox := TPaintBox.Create(Self);
    FPeBox.Parent := FBody;
    FPeBox.Align := TAlignLayout.Client;
    FPeBox.HitTest := False;
    FPeBox.OnPaint := PaintPe;
  end;
  if FPeHexBtn = nil then
  begin
    FPeHexBtn := CreateFluentButton(Self, FHeader, '', 'HEX', fbkSubtle, 96, PeHexClick);
    FPeHexBtn.Align := TAlignLayout.Right;
    FPeHexBtn.Margins.Right := 8;
    FPeHexBtn.ApplyTheme(FColors);
  end;
  FPeHexBtn.SetCaption(L('qv.hex'));
  FPeHexBtn.Visible := True;
  FPeBox.Visible := True;
  FPeBox.BringToFront;
  PlacePeHex;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  SetKindKey('qv.kind.exe');
  if (GPeCache <> nil) and GPeCache.TryGetValue(Key, Hit) then
  begin
    AcceptPe(Token, Key, APath, Hit);
    Exit;
  end;
  FPeBox.Repaint;
  TThread.CreateAnonymousThread(
    procedure
    var
      Info: TPeInfo;
    begin
      Info := ReadPeInfo(APath);
      TThread.Queue(nil,
        procedure
        begin
          AcceptPe(Token, Key, APath, Info);
        end);
    end).Start;
end;

procedure TFilePreview.HideFileCard;
begin
  Inc(FFileToken);
  FFileHexOn := False;
  FFileScroll := 0;
  if Assigned(FFileBox) then
    FFileBox.Visible := False;
  if Assigned(FFileHex) then
    FFileHex.Visible := False;
  FreeAndNil(FFileThumb);
end;

procedure TFilePreview.PlaceFileHex;
begin
  if not Assigned(FFileHex) or not Assigned(FHeader) then
    Exit;
  if FFileHex.Parent <> FHeader then
    FFileHex.Parent := FHeader;
  FFileHex.Align := TAlignLayout.Right;
  FFileHex.Width := 96;
  FFileHex.Margins.Rect := TRectF.Create(2, 4, 8, 4);
end;

procedure TFilePreview.FileHexClick(Sender: TObject);
begin
  if FPath = '' then
    Exit;
  FFileHexOn := not FFileHexOn;
  if FFileHexOn then
  begin
    if Assigned(FFileBox) then
      FFileBox.Visible := False;
    LoadAsHex(FPath);
    if Assigned(FFileHex) then
    begin
      FFileHex.SetCaption(L('qv.card'));
      FFileHex.Visible := True;
    end;
  end
  else
  begin
    if Assigned(FMemo) then
      FMemo.Visible := False;
    if Assigned(FFileBox) then
    begin
      FFileBox.Visible := True;
      FFileBox.Repaint;
    end;
    if Assigned(FFileHex) then
      FFileHex.SetCaption(L('qv.hex'));
    if FFileType <> '' then
      SetKindRaw(FFileType);
  end;
  PlaceFileHex;
end;

procedure TFilePreview.AcceptFileThumb(AToken: Integer; const APixels: TBytes;
  AW, AH: Integer);
begin
  if FDestroying or (FFileToken <> AToken) then
    Exit;
  if (AW < 96) or (AH < 96) or (Length(APixels) < AW * AH * 4) then
    Exit;
  if FFileThumb = nil then
    FFileThumb := TBitmap.Create;
  BgraToFmxBitmap(APixels, AW, AH, FFileThumb);
  if Assigned(FFileBox) and FFileBox.Visible then
    FFileBox.Repaint;
end;

procedure TFilePreview.PaintFileCard(Sender: TObject; Canvas: TCanvas);
var
  Y, X, W: Single;
  Entry: TFileEntry;
  Bmp: FMX.Graphics.TBitmap;
  Scale, Fit, Dw, Dh: Single;
  Dest: TRectF;

  procedure Row(const K, V: string);
  begin
    if V = '' then
      Exit;
    Canvas.Font.Size := 11;
    Canvas.Font.Style := [];
    Canvas.Fill.Color := FColors.SubTextColor;
    Canvas.FillText(TRectF.Create(18, Y, W - 16, Y + 14), K, False, 1, [],
      TTextAlign.Leading, TTextAlign.Leading);
    Canvas.Font.Size := 13;
    Canvas.Fill.Color := FColors.TextColor;
    Canvas.FillText(TRectF.Create(18, Y + 14, W - 16, Y + 32), V, True, 1, [],
      TTextAlign.Leading, TTextAlign.Leading);
    Y := Y + 36;
  end;

begin
  if Canvas = nil then
    Exit;
  W := FFileBox.Width;
  Canvas.IntersectClipRect(TRectF.Create(0, 0, W, FFileBox.Height));
  Y := 16 - FFileScroll;
  Entry := TFileEntry.FromPath(FPath);
  Scale := 1;
  if Assigned(Scene) then
    Scale := Scene.GetSceneScale;
  if Scale < 1 then
    Scale := 1;
  Bmp := nil;
  if Assigned(GlobalIconCache) then
    Bmp := GlobalIconCache.GetForPaint(Entry, ib64, Scale);
  if Assigned(Bmp) and (Bmp.Width > 0) then
  begin
    Fit := Min(96 / Bmp.Width, 96 / Bmp.Height);
    if Fit > 1 then
      Fit := 1;
    Dw := Bmp.Width * Fit;
    Dh := Bmp.Height * Fit;
    Dest := TRectF.Create(18 + (96 - Dw) / 2, Y + (96 - Dh) / 2,
      18 + (96 - Dw) / 2 + Dw, Y + (96 - Dh) / 2 + Dh);
    Canvas.DrawBitmap(Bmp, Bmp.Bounds, Dest, 1, False);
  end;
  Canvas.Font.Family := 'Segoe UI';
  Canvas.Font.Size := 18;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.Fill.Color := FColors.TextColor;
  Canvas.FillText(TRectF.Create(128, Y, W - 12, Y + 28), FTitle.Text, True, 1, [],
    TTextAlign.Leading, TTextAlign.Leading);
  Canvas.Font.Size := 13;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := FColors.SubTextColor;
  Canvas.FillText(TRectF.Create(128, Y + 32, W - 12, Y + 88), FFileType, True, 1, [],
    TTextAlign.Leading, TTextAlign.Leading);
  Y := Y + 112;
  Row(L('qv.file.size'), FFileSize);
  Row(L('qv.file.modified'), FFileModified);
  Row(L('qv.file.created'), FFileCreated);
  Row(L('qv.file.opens'), FFileOpens);
  Row(L('qv.file.attrs'), FFileAttrs);
  Row(L('qv.file.target'), FFileTarget);
  Row(L('qv.file.args'), FFileArgs);
  Row(L('qv.file.folder'), FFileWork);
  Row(L('qv.file.url'), FFileUrl);
  if Assigned(FFileThumb) and (FFileThumb.Width >= 96) then
  begin
    Y := Y + 8;
    Fit := Min((W - 36) / FFileThumb.Width, 280 / FFileThumb.Height);
    if Fit > 1 then
      Fit := 1;
    Dw := FFileThumb.Width * Fit;
    Dh := FFileThumb.Height * Fit;
    X := (W - Dw) / 2;
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Thickness := 1;
    Canvas.Stroke.Color := FColors.DividerColor;
    Canvas.DrawRect(TRectF.Create(X - 1, Y - 1, X + Dw + 1, Y + Dh + 1), 0, 0, [], 1);
    Canvas.DrawBitmap(FFileThumb, FFileThumb.Bounds,
      TRectF.Create(X, Y, X + Dw, Y + Dh), 1, False);
    Y := Y + Dh + 8;
  end;
  FFileContentH := Y + FFileScroll + 48;
end;

procedure TFilePreview.ShowFileCard(const APath: string);
var
  Token: Integer;
  Ext, Opens: string;
  SFI: TSHFileInfo;
  Buf: array[0..511] of Char;
  Len: DWORD;
  Attr: DWORD;
  Parts: TArray<string>;
  Link: IShellLink;
  Pf: IPersistFile;
  LinkBuf: array[0..1023] of Char;
  Fd: TWin32FindData;
  SL: TStringList;
  Line: string;

  function When(const D: TDateTime): string;
  begin
    if D <= 1 then
      Result := ''
    else
      Result := FormatDateTime('dd.mm.yyyy hh:nn', D);
  end;

begin
  Inc(FFileToken);
  Token := FFileToken;
  FFileHexOn := False;
  FFileScroll := 0;
  FFileContentH := 0;
  FFileType := '';
  FFileOpens := '';
  FFileCreated := '';
  FFileModified := '';
  FFileSize := '';
  FFileAttrs := '';
  FFileTarget := '';
  FFileArgs := '';
  FFileWork := '';
  FFileUrl := '';
  FreeAndNil(FFileThumb);
  Ext := LowerCase(ExtractFileExt(APath));
  FillChar(SFI, SizeOf(SFI), 0);
  if SHGetFileInfo(PChar(APath), 0, SFI, SizeOf(SFI), SHGFI_TYPENAME) <> 0 then
    FFileType := Trim(string(SFI.szTypeName));
  if FFileType = '' then
  begin
    if Ext = '' then
      FFileType := L('qv.file.kind')
    else
      FFileType := UpperCase(Copy(Ext, 2, 12));
  end;
  try
    FFileSize := FormatFileSize(TFile.GetSize(APath));
  except
  end;
  try
    FFileModified := When(TFile.GetLastWriteTime(APath));
  except
  end;
  try
    FFileCreated := When(TFile.GetCreationTime(APath));
  except
  end;
  Opens := '';
  if Ext <> '' then
  begin
    Len := Length(Buf);
    if Succeeded(AssocQueryString(ASSOCF_NOTRUNCATE, ASSOCSTR(4), PChar(Ext), nil, Buf, @Len)) then
      Opens := Trim(string(Buf));
    if Opens = '' then
    begin
      Len := Length(Buf);
      if Succeeded(AssocQueryString(ASSOCF_NOTRUNCATE, ASSOCSTR(2), PChar(Ext), nil, Buf, @Len)) then
        Opens := ExtractFileName(Trim(string(Buf)));
    end;
  end;
  if Opens = '' then
    Opens := L('qv.file.unassigned');
  FFileOpens := Opens;
  Attr := GetFileAttributes(PChar(APath));
  if Attr <> INVALID_FILE_ATTRIBUTES then
  begin
    if (Attr and FILE_ATTRIBUTE_READONLY) <> 0 then
      Parts := Parts + [L('qv.file.readonly')];
    if (Attr and FILE_ATTRIBUTE_HIDDEN) <> 0 then
      Parts := Parts + [L('qv.file.hidden')];
    if (Attr and FILE_ATTRIBUTE_SYSTEM) <> 0 then
      Parts := Parts + [L('qv.file.system')];
    FFileAttrs := string.Join(', ', Parts);
  end;
  if Ext = '.lnk' then
  begin
    Link := nil;
    Pf := nil;
    if Succeeded(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER,
      IShellLink, Link)) and Succeeded(Link.QueryInterface(IPersistFile, Pf)) and
      Succeeded(Pf.Load(PChar(APath), STGM_READ)) then
    begin
      FillChar(Fd, SizeOf(Fd), 0);
      FillChar(LinkBuf, SizeOf(LinkBuf), 0);
      if Succeeded(Link.GetPath(@LinkBuf[0], 1024, Fd, 0)) then
        FFileTarget := string(LinkBuf);
      FillChar(LinkBuf, SizeOf(LinkBuf), 0);
      if Succeeded(Link.GetArguments(@LinkBuf[0], 1024)) then
        FFileArgs := Trim(string(LinkBuf));
      FillChar(LinkBuf, SizeOf(LinkBuf), 0);
      if Succeeded(Link.GetWorkingDirectory(@LinkBuf[0], 1024)) then
        FFileWork := Trim(string(LinkBuf));
    end;
  end
  else if Ext = '.url' then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(APath);
      for Line in SL do
        if StartsText('URL=', Trim(Line)) then
        begin
          FFileUrl := Trim(Copy(Trim(Line), 5, MaxInt));
          Break;
        end;
    except
    end;
    SL.Free;
  end;
  if FFileBox = nil then
  begin
    FFileBox := TPaintBox.Create(Self);
    FFileBox.Parent := FBody;
    FFileBox.Align := TAlignLayout.Client;
    FFileBox.HitTest := False;
    FFileBox.OnPaint := PaintFileCard;
  end;
  if FFileHex = nil then
  begin
    FFileHex := CreateFluentButton(Self, FHeader, '', 'HEX', fbkSubtle, 96, FileHexClick);
    FFileHex.Align := TAlignLayout.Right;
    FFileHex.Margins.Right := 8;
    FFileHex.ApplyTheme(FColors);
  end;
  FFileHex.SetCaption(L('qv.hex'));
  FFileHex.Visible := True;
  FFileBox.Visible := True;
  FFileBox.BringToFront;
  PlaceFileHex;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  SetKindRaw(FFileType);
  FFileBox.Repaint;
  TThread.CreateAnonymousThread(
    procedure
    var
      Pix: TBytes;
      TW, TH: Integer;
      Ok: Boolean;
    begin
      CoInitialize(nil);
      try
        Ok := GetFileThumbnailOnly(APath, 480, Pix, TW, TH);
      finally
        CoUninitialize;
      end;
      if not Ok then
        Exit;
      TThread.Queue(nil,
        procedure
        begin
          AcceptFileThumb(Token, Pix, TW, TH);
        end);
    end).Start;
end;

procedure RunPanoScan(APreview: TFilePreview; AToken: Integer;
  const APath, AKey: string; AArchive: Boolean);
var
  Photo, Video, Docs, Other: Int64;
  Files, Folders: Integer;
  Partial, Failed: Boolean;
  LastPost: Cardinal;
  P, V, D, O: Int64;
  NFiles, NFolders: Integer;
  Part, Fail: Boolean;

  procedure Touch;
  var
    NowTick: Cardinal;
    P, V, D, O: Int64;
    NFiles, NFolders: Integer;
    Part, Fail: Boolean;
  begin
    NowTick := TThread.GetTickCount;
    if NowTick - LastPost < 250 then
      Exit;
    LastPost := NowTick;
    P := Photo;
    V := Video;
    D := Docs;
    O := Other;
    NFiles := Files;
    NFolders := Folders;
    Part := Partial;
    Fail := Failed;
    TThread.Queue(nil,
      procedure
      begin
        if APreview <> nil then
          APreview.AcceptPanorama(AToken, AKey, P, V, D, O, NFiles, NFolders,
            Part, Fail, False);
      end);
  end;

  procedure AddFile(const AName: string; ASize: Int64);
  begin
    Inc(Files);
    if ASize < 0 then
      ASize := 0;
    case PanoCat(LowerCase(ExtractFileExt(AName))) of
      0: Inc(Photo, ASize);
      1: Inc(Video, ASize);
      2: Inc(Docs, ASize);
    else
      Inc(Other, ASize);
    end;
  end;

  procedure Walk(const ADir: string; ADepth: Integer);
  var
    SR: TSearchRec;
    Full: string;
    Attr: DWORD;
  begin
    if (APreview.FPanoToken <> AToken) or (ADepth > 64) then
    begin
      if ADepth > 64 then
        Partial := True;
      Exit;
    end;
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR) <> 0 then
    begin
      Partial := True;
      Exit;
    end;
    try
      repeat
        if APreview.FPanoToken <> AToken then
          Exit;
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        Full := IncludeTrailingPathDelimiter(ADir) + SR.Name;
        if (SR.Attr and faDirectory) <> 0 then
        begin
          Inc(Folders);
          Attr := GetFileAttributes(PChar(Full));
          if (Attr <> INVALID_FILE_ATTRIBUTES) and
             ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
            Continue;
          Walk(Full, ADepth + 1);
        end
        else
          AddFile(SR.Name, SR.Size);
        Touch;
      until FindNext(SR) <> 0;
    finally
      System.SysUtils.FindClose(SR);
    end;
  end;

  procedure FromArchive;
  var
    Items: TArray<TArcItem>;
    I: Integer;
    Arc, Inner, Prefix, Rel: string;
  begin
    if not ListArchiveAll(APath, Items) then
    begin
      Failed := True;
      Exit;
    end;
    Prefix := '';
    if SplitArchivePath(APath, Arc, Inner) then
      Prefix := ArcNorm(Inner);
    for I := 0 to High(Items) do
    begin
      if APreview.FPanoToken <> AToken then
        Exit;
      Rel := ArcNorm(Items[I].Path);
      if Prefix <> '' then
      begin
        if SameText(Rel, Prefix) then
          Continue;
        if not StartsText(Prefix + '/', Rel) then
          Continue;
      end;
      if Items[I].IsDir then
        Inc(Folders)
      else if Rel <> '' then
        AddFile(Items[I].Path, Items[I].Size);
    end;
  end;

begin
  Photo := 0;
  Video := 0;
  Docs := 0;
  Other := 0;
  Files := 0;
  Folders := 0;
  Partial := False;
  Failed := False;
  LastPost := TThread.GetTickCount;
  try
    if AArchive then
      FromArchive
    else
      Walk(ExcludeTrailingPathDelimiter(APath), 0);
  except
    Failed := True;
  end;
  if APreview.FPanoToken <> AToken then
    Exit;
  P := Photo;
  V := Video;
  D := Docs;
  O := Other;
  NFiles := Files;
  NFolders := Folders;
  Part := Partial;
  Fail := Failed;
  TThread.Queue(nil,
    procedure
    begin
      if APreview <> nil then
        APreview.AcceptPanorama(AToken, AKey, P, V, D, O, NFiles, NFolders,
          Part, Fail, True);
    end);
end;

procedure TFilePreview.AcceptPanorama(AToken: Integer; const AKey: string;
  APhoto, AVideo, ADocs, AOther: Int64; AFiles, AFolders: Integer;
  APartial, AFailed, AFinal: Boolean);
var
  Hit: TPanoCacheRec;
begin
  if FDestroying or (FPanoToken <> AToken) then
    Exit;
  if FPanoReady and not AFinal then
    Exit;
  FPanoPhoto := APhoto;
  FPanoVideo := AVideo;
  FPanoDocs := ADocs;
  FPanoOther := AOther;
  FPanoFiles := AFiles;
  FPanoFolders := AFolders;
  FPanoPartial := APartial;
  FPanoFailed := AFailed;
  FPanoReady := AFinal;
  if AFinal and not AFailed then
  begin
    FPanoAnim := True;
    FPanoAnimAt := TThread.GetTickCount;
    if FPanoTimer = nil then
    begin
      FPanoTimer := TTimer.Create(Self);
      FPanoTimer.Interval := 16;
      FPanoTimer.OnTimer := PanoTick;
    end;
    FPanoTimer.Enabled := True;
    if GPanoCache = nil then
      GPanoCache := TDictionary<string, TPanoCacheRec>.Create;
    Hit.Photo := APhoto;
    Hit.Video := AVideo;
    Hit.Docs := ADocs;
    Hit.Other := AOther;
    Hit.Files := AFiles;
    Hit.Folders := AFolders;
    Hit.Partial := APartial;
    Hit.Failed := False;
    GPanoCache.AddOrSetValue(AKey, Hit);
  end
  else
    FPanoAnim := False;
  if Assigned(FPanoBox) then
    FPanoBox.Repaint;
end;

procedure TFilePreview.ShowPanorama(const APath: string; AArchive: Boolean);
var
  Token: Integer;
  Key: string;
  Hit: TPanoCacheRec;
begin
  Inc(FPanoToken);
  Token := FPanoToken;
  FPanoArchive := AArchive;
  FPanoPhoto := 0;
  FPanoVideo := 0;
  FPanoDocs := 0;
  FPanoOther := 0;
  FPanoFiles := 0;
  FPanoFolders := 0;
  FPanoPartial := False;
  FPanoReady := False;
  FPanoFailed := False;
  FPanoAnim := False;
  FPanoIconTicks := 40;
  Key := PanoCacheKey(APath, AArchive);
  if FPanoBox = nil then
  begin
    FPanoBox := TPaintBox.Create(Self);
    FPanoBox.Parent := FBody;
    FPanoBox.Align := TAlignLayout.Client;
    FPanoBox.HitTest := False;
    FPanoBox.OnPaint := PaintPanorama;
  end;
  FPanoBox.Visible := True;
  FPanoBox.BringToFront;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  if Assigned(FMeta) then
    FMeta.Visible := False;
  if FPanoTimer = nil then
  begin
    FPanoTimer := TTimer.Create(Self);
    FPanoTimer.Interval := 16;
    FPanoTimer.OnTimer := PanoTick;
  end;
  FPanoTimer.Enabled := True;
  if (GPanoCache <> nil) and GPanoCache.TryGetValue(Key, Hit) and not Hit.Failed then
  begin
    AcceptPanorama(Token, Key, Hit.Photo, Hit.Video, Hit.Docs, Hit.Other,
      Hit.Files, Hit.Folders, Hit.Partial, False, True);
    Exit;
  end;
  FPanoBox.Repaint;
  TThread.CreateAnonymousThread(
    procedure
    begin
      RunPanoScan(Self, Token, APath, Key, AArchive);
    end).Start;
end;

function TFilePreview.LoadAsArchive(const APath: string): Boolean;
var
  KindName: string;
  Kind: TArchiveKind;
begin
  Result := False;
  if not IsArchiveFileName(APath) then
  begin
    if LoadAsThumb(APath) then
    begin
      SetKindKey('qv.kind.archive');
      Exit(True);
    end;
    Exit(False);
  end;
  Kind := DetectArchiveKind(APath);
  KindName := ArchiveKindCaption(Kind);
  if (KindName = '') or (Kind = akOther) then
    SetKindKey('qv.kind.archive')
  else
    SetKindRaw(KindName);
  ShowPanorama(APath, True);
  Result := True;
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
    Result := Lf('sheet.name', [SheetName]) + sLineBreak + sLineBreak + Result;
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

procedure TFilePreview.DocPageChanged(Sender: TObject);
var
  Idx: Integer;
begin
  if not Assigned(FDoc) or not Assigned(FDocView) or not Assigned(FSheetCombo) then
    Exit;
  if not FDocView.Visible or (FPdfPages > 0) or Assigned(FPdf) or Assigned(FBook) then
    Exit;
  Idx := FDocView.ActivePage;
  if (Idx >= 0) and (Idx < FSheetCombo.Items.Count) and (FSheetCombo.ItemIndex <> Idx) then
  begin
    { Иначе OnSelChange вызовет GoToPage и прижмёт лист к верху страницы. }
    FSheetCombo.OnSelChange := nil;
    try
      FSheetCombo.ItemIndex := Idx;
    finally
      FSheetCombo.OnSelChange := SheetComboChange;
    end;
  end;
  SyncSheetButtons;
end;

procedure TFilePreview.SheetComboChange(Sender: TObject);
var
  Want: Integer;
begin
  try
    if (FPdfPages > 0) and Assigned(FSheetCombo) and (FSheetCombo.ItemIndex >= 0) then
    begin
      Want := FSheetCombo.ItemIndex;
      if (FPdf <> nil) or OpenPdfDoc then
        ShowPdfPage(Want);
      if (FPdfPage <> Want) and (FPdfPage >= 0) and
         (FPdfPage < FSheetCombo.Items.Count) then
      begin
        FSheetCombo.OnSelChange := nil;
        try
          FSheetCombo.ItemIndex := FPdfPage;
        finally
          FSheetCombo.OnSelChange := SheetComboChange;
        end;
      end;
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
  finally
    SyncSheetButtons;
  end;
end;

procedure TFilePreview.ShowSheetBar(AOn: Boolean);
begin
  if Assigned(FSheetBar) then
    FSheetBar.Visible := AOn;
  SyncSheetButtons;
end;

procedure TFilePreview.SyncSheetButtons;
var
  N, Ix: Integer;
  OnBar, BackOn, FwdOn: Boolean;
begin
  if FBtnSheetBack = nil then
    Exit;
  OnBar := Assigned(FSheetBar) and FSheetBar.Visible and Assigned(FSheetCombo) and
    (FSheetCombo.Items.Count > 1);
  N := 0;
  Ix := 0;
  if OnBar then
  begin
    N := FSheetCombo.Items.Count;
    Ix := FSheetCombo.ItemIndex;
    if Ix < 0 then
      Ix := 0;
  end;
  BackOn := OnBar and (Ix > 0);
  FwdOn := OnBar and (Ix < N - 1);
  FBtnSheetBack.Enabled := BackOn;
  FBtnSheetFwd.Enabled := FwdOn;
  if BackOn then
    FBtnSheetBack.Opacity := 1
  else
    FBtnSheetBack.Opacity := 0.35;
  if FwdOn then
    FBtnSheetFwd.Opacity := 1
  else
    FBtnSheetFwd.Opacity := 0.35;
  if BackOn then
    FBtnSheetBack.Cursor := crHandPoint
  else
    FBtnSheetBack.Cursor := crDefault;
  if FwdOn then
    FBtnSheetFwd.Cursor := crHandPoint
  else
    FBtnSheetFwd.Cursor := crDefault;
end;

procedure TFilePreview.SheetStep(ADelta: Integer);
var
  N, Ix: Integer;
begin
  if ADelta = 0 then
    Exit;
  if not Assigned(FSheetBar) or not FSheetBar.Visible or not Assigned(FSheetCombo) then
    Exit;
  if FSheetCombo.IsDropOpen then
    FSheetCombo.CloseList;
  N := FSheetCombo.Items.Count;
  if N < 2 then
    Exit;
  Ix := FSheetCombo.ItemIndex;
  if Ix < 0 then
    Ix := 0;
  Ix := EnsureRange(Ix + ADelta, 0, N - 1);
  if Ix = FSheetCombo.ItemIndex then
    Exit;
  FSheetCombo.ItemIndex := Ix;
end;

procedure TFilePreview.SheetPrevClick(Sender: TObject);
begin
  SheetStep(-1);
end;

procedure TFilePreview.SheetNextClick(Sender: TObject);
begin
  SheetStep(1);
end;

procedure TFilePreview.SheetBarWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  if WheelDelta = 0 then
    Exit;
  if not Assigned(FSheetBar) or not FSheetBar.Visible then
    Exit;
  { Открытый список крутит сам себя. Здесь только закрытый комбо и полоса. }
  if Assigned(FSheetCombo) and FSheetCombo.IsDropOpen then
  begin
    Handled := True;
    Exit;
  end;
  if WheelDelta > 0 then
    SheetStep(-1)
  else
    SheetStep(1);
  Handled := True;
end;

procedure TFilePreview.SheetComboKey(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if SheetHotkey(Key, Shift, False) then
  begin
    Key := 0;
    KeyChar := #0;
  end;
end;

function TFilePreview.SheetHotkey(var Key: Word; Shift: TShiftState;
  AArrows: Boolean): Boolean;
var
  Delta, N, Ix: Integer;
begin
  Result := False;
  if not Assigned(FSheetBar) or not FSheetBar.Visible then
    Exit;
  if not Assigned(FSheetCombo) or (FSheetCombo.Items.Count < 2) then
    Exit;
  if FSheetCombo.EditorFocused and
     ((Key = vkLeft) or (Key = vkRight) or (Key = vkUp) or (Key = vkDown)) then
    Exit;
  if FSheetCombo.IsDropOpen and ((Key = vkUp) or (Key = vkDown)) then
    Exit;
  N := FSheetCombo.Items.Count;
  Ix := FSheetCombo.ItemIndex;
  if Ix < 0 then
    Ix := 0;
  if (Key = vkPrior) or (Key = vkNext) then
  begin
    if ssCtrl in Shift then
    begin
      if Key = vkPrior then
        Delta := -Ix
      else
        Delta := (N - 1) - Ix;
    end
    else if Key = vkPrior then
      Delta := -1
    else
      Delta := 1;
  end
  else if AArrows and ((Key = vkLeft) or (Key = vkUp) or (Key = vkRight) or
          (Key = vkDown)) then
  begin
    if ssAlt in Shift then
      Exit;
    if (Key = vkLeft) or (Key = vkUp) then
      Delta := -1
    else
      Delta := 1;
  end
  else
    Exit;
  Result := True;
  if Delta <> 0 then
    SheetStep(Delta);
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
  ShowSheetBar(FBook.Sheets.Count > 1);
  FGrid.ApplyTheme(FColors);
  FGrid.Visible := True;
  FGrid.SetSheet(FBook.ActiveSheet);
  FGrid.SyncNow;
  SetKindKey('qv.kind.sheet');
  Sheet := FBook.ActiveSheet;
  Meta := '';
  if Assigned(Sheet) then
  begin
    Meta := Format('%d × %d', [Sheet.RowCount, Sheet.ColCount]);
    if Sheet.Truncated then
      Meta := Meta + Lf('qv.sheet.limit', [SpreadQVMaxRows, SpreadQVMaxCols]);
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
      FSheetCombo.Items.Add(Lf('qv.page.n', [I + 1]));
  finally
    FSheetCombo.Items.EndUpdate;
  end;
  if FSheetCombo.Items.Count > 0 then
    FSheetCombo.ItemIndex := 0;
  ShowSheetBar(FDoc.Pages.Count > 1);
  FDocView.ApplyTheme(FColors);
  FDocView.Visible := True;
  FDocView.SetDocument(FDoc);
  FDocView.SyncNow;
  SetKindKey('qv.kind.doc');
  Meta := Lf('qv.pages', [FDoc.Pages.Count]);
  if FDoc.Truncated then
    Meta := Meta + L('qv.partial');
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
    ShowSheetBar(FBook.Sheets.Count > 1);
    FGrid.ApplyTheme(FColors);
    FGrid.Visible := True;
    FGrid.SetSheet(FBook.ActiveSheet);
    SetKindKey('qv.kind.sheet');
    Sheet := FBook.ActiveSheet;
    Meta := '';
    if Assigned(Sheet) then
    begin
      Meta := Format('%d × %d', [Sheet.RowCount, Sheet.ColCount]);
      if Sheet.Truncated then
        Meta := Meta + Lf('qv.sheet.limit', [SpreadQVMaxRows, SpreadQVMaxCols]);
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
    ShowInfoKey('qv.sheet.showfail');
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
        FSheetCombo.Items.Add(Lf('qv.page.n', [I + 1]));
    finally
      FSheetCombo.Items.EndUpdate;
    end;
    if FSheetCombo.Items.Count > 0 then
      FSheetCombo.ItemIndex := 0;
    ShowSheetBar(FDoc.Pages.Count > 1);
    FDocView.ApplyTheme(FColors);
    FDocView.Visible := True;
    FDocView.SetDocument(FDoc);
    SetKindKey('qv.kind.doc');
    Meta := Lf('qv.pages', [FDoc.Pages.Count]);
    if FDoc.Truncated then
      Meta := Meta + L('qv.partial');
    if Meta <> '' then
      FMeta.Text := FMeta.Text + '    ' + Meta;
    if FCaptureKeys then
      FocusViewer;
  except
    if Assigned(FDocView) then
      FDocView.Clear;
    FreeAndNil(FDoc);
    ShowInfoKey('qv.doc.showfail');
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
  ShowInfoKey('qv.loading');
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
                ShowInfoKey('qv.sheet.parsefail');
                SetKindKey('qv.kind.sheet');
              end;
            end
            else if Doc <> nil then
            begin
              ApplyDocument(Doc);
              Doc := nil;
            end
            else
            begin
              ShowInfoKey('qv.doc.parsefail');
              SetKindKey('qv.kind.doc');
            end;
          except
            Book.Free;
            Doc.Free;
            ShowInfoKey('qv.error');
          end;
        end);
    end).Start;
end;

procedure TFilePreview.PaintSvg(Sender: TObject; const ACanvas: ISkCanvas;
  const ADest: TRectF; const AOpacity: Single);
var
  Scale, Dw, Dh, L, T, DrawScale: Single;
begin
  if not Assigned(FSvgDom) or not Assigned(FSvgDom.Root) then
    Exit;
  if ADest.IsEmpty or (FViewW < 1) or (FViewH < 1) then
    Exit;
  if not ViewMetrics(Scale, Dw, Dh, L, T) then
    Exit;
  DrawScale := Dw / FViewW;
  if DrawScale <= 0 then
    Exit;
  try
    FSvgDom.SetContainerSize(TSizeF.Create(FViewW, FViewH));
    ACanvas.Save;
    try
      ACanvas.ClipRect(ADest);
      if AOpacity < 0.999 then
        ACanvas.SaveLayerAlpha(Byte(Round(AOpacity * 255)))
      else
        ACanvas.Save;
      try
        ACanvas.Translate(ADest.Left + L, ADest.Top + T);
        ACanvas.Scale(DrawScale, DrawScale);
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
  FAnim.Parent := FImgHost;
  FAnim.Align := TAlignLayout.None;
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
  Bytes: TBytes;
begin
  Result := False;
  if APath = '' then
    Exit;
  StopAnim;
  EnsureAnim;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    FAnim.LoadFromFile(APath);
    if FAnim.OriginalSize.Width < 1 then
    begin
      Bytes := ReadLottieJsonBytes(APath, 32 * 1024 * 1024, False);
      if Length(Bytes) > 0 then
        FAnim.Source.Data := Bytes;
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
    Exit('qv.wv.missing')
  else
  begin
    try
      M := DllImageMachine(WebView2LoaderFile);
    except
      M := 0;
    end;
    if M = $8664 then
      Exit('qv.wv.bits')
    else
      Exit('qv.wv.fail');
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
var
  SceneOn: Boolean;
begin
  if FLottieHead or FSvgHead then
  begin
    if FSvgHead then
      SceneOn := not FSvgShowSource
    else
      SceneOn := not FLottieShowSource;
    if Assigned(FBtnHtmlPage) then
    begin
      FBtnHtmlPage.SetCaption(L('qv.scene'));
      FBtnHtmlPage.SetSelected(SceneOn);
    end;
    if Assigned(FBtnHtmlSrc) then
    begin
      FBtnHtmlSrc.SetCaption(L('qv.source'));
      FBtnHtmlSrc.SetSelected(not SceneOn);
    end;
  end
  else
  begin
    if Assigned(FBtnHtmlPage) then
    begin
      FBtnHtmlPage.SetCaption(L('qv.page'));
      FBtnHtmlPage.SetSelected(not FHtmlShowSource);
    end;
    if Assigned(FBtnHtmlSrc) then
    begin
      FBtnHtmlSrc.SetCaption(L('qv.source'));
      FBtnHtmlSrc.SetSelected(FHtmlShowSource);
    end;
  end;
end;

procedure TFilePreview.ShowHtmlMode(AShow: Boolean);
begin
  FLottieHead := False;
  FSvgHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := AShow;
  UpdateHtmlModeButtons;
end;

procedure TFilePreview.ShowLottieScene;
var
  Ok: Boolean;
begin
  if FPath = '' then
    Exit;
  if FImgDirty then
  begin
    ShowToast(L('qv.toast.failed'));
    Exit;
  end;
  FLottieShowSource := False;
  FLottieHead := True;
  FSvgHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  if FTextJob <> nil then
  begin
    TTextLoadJob(FTextJob).Preview := nil;
    FTextJob := nil;
  end;
  if Assigned(FMemo) then
    FMemo.Visible := False;
  if Assigned(FDocView) then
    FDocView.Visible := False;
  if Assigned(FCodeView) then
    FCodeView.Visible := False;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  ShowTextChrome(False);
  Ok := LoadAsSkiaImage(FPath);
  if not Ok then
  begin
    ShowInfoKey('qv.lottie.fail');
    Exit;
  end;
  if not FImgChrome then
    ShowImageTools(True);
  if Assigned(FKindText) then
    SetKindKey('qv.kind.lottie');
  ShowMeta(FPath);
  LayoutImageHeader(nil);
end;

procedure TFilePreview.ShowLottieSource;
begin
  if FPath = '' then
    Exit;
  if FImgDirty then
  begin
    ShowToast(L('qv.toast.failed'));
    Exit;
  end;
  FLottieShowSource := True;
  FLottieHead := True;
  FSvgHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  ShowImageTools(False);
  HideSvgWeb;
  StopAnim;
  if Assigned(FImgHost) then
    FImgHost.Visible := False;
  if Assigned(FImage) then
    FImage.Visible := False;
  if Assigned(FDocView) then
    FDocView.Visible := False;
  if Assigned(FCodeView) then
    FCodeView.Visible := False;
  FTextEnc := temAuto;
  StartTextLoad(FPath, '.json', True);
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  FLottieHead := True;
  UpdateHtmlModeButtons;
end;

function TFilePreview.OpenLottieView(const APath: string): Boolean;
var
  Ext: string;
  Ok: Boolean;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.lottie') and (Ext <> '.tgs') and
     not ((Ext = '.json') and LooksLikeLottieFile(APath)) then
    Exit;
  Result := True;
  FLottieHead := True;
  FSvgHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  if FLottieShowSource then
  begin
    ShowLottieSource;
    Exit;
  end;
  Ok := LoadAsSkiaImage(APath);
  if Ok then
  begin
    if not FImgChrome then
      ShowImageTools(True);
    if Assigned(FKindText) then
      SetKindKey('qv.kind.lottie');
    FLottieHead := True;
    if Assigned(FHtmlModeBar) then
      FHtmlModeBar.Visible := True;
    UpdateHtmlModeButtons;
    LayoutImageHeader(nil);
    Exit;
  end;
  FLottieHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := False;
  if Ext = '.json' then
  begin
    FTextEnc := temAuto;
    StartTextLoad(APath);
    Exit;
  end;
  ShowInfoKey('qv.lottie.fail');
  if Assigned(FKindText) then
    SetKindKey('qv.kind.lottie');
end;

procedure TFilePreview.ShowSvgScene;
var
  Ok: Boolean;
begin
  if FPath = '' then
    Exit;
  if FImgDirty then
  begin
    ShowToast(L('qv.toast.failed'));
    Exit;
  end;
  FSvgShowSource := False;
  FSvgHead := True;
  FLottieHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  if FTextJob <> nil then
  begin
    TTextLoadJob(FTextJob).Preview := nil;
    FTextJob := nil;
  end;
  if Assigned(FMemo) then
    FMemo.Visible := False;
  if Assigned(FDocView) then
    FDocView.Visible := False;
  if Assigned(FCodeView) then
    FCodeView.Visible := False;
  if Assigned(FInfo) then
    FInfo.Visible := False;
  ShowTextChrome(False);
  Ok := LoadAsSkiaImage(FPath);
  if not Ok then
  begin
    ShowInfoKey('qv.svg.fail');
    Exit;
  end;
  if not FImgChrome then
    ShowImageTools(True);
  FSvgHead := True;
  FLottieHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  LayoutImageHeader(nil);
end;

procedure TFilePreview.ShowSvgSource;
begin
  if FPath = '' then
    Exit;
  if FImgDirty then
  begin
    ShowToast(L('qv.toast.failed'));
    Exit;
  end;
  FSvgShowSource := True;
  FSvgHead := True;
  FLottieHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  ShowImageTools(False);
  HideSvgWeb;
  StopAnim;
  FSvgDom := nil;
  if Assigned(FSvgBox) then
    FSvgBox.Visible := False;
  if Assigned(FImgHost) then
    FImgHost.Visible := False;
  if Assigned(FImage) then
    FImage.Visible := False;
  if Assigned(FDocView) then
    FDocView.Visible := False;
  if Assigned(FCodeView) then
    FCodeView.Visible := False;
  FTextEnc := temAuto;
  StartTextLoad(FPath, '.svg', False);
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  FSvgHead := True;
  FLottieHead := False;
  UpdateHtmlModeButtons;
end;

function TFilePreview.OpenSvgView(const APath: string): Boolean;
var
  Ext: string;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext <> '.svg') and (Ext <> '.svgz') then
    Exit;
  Result := True;
  FSvgHead := True;
  FLottieHead := False;
  if Assigned(FHtmlModeBar) then
    FHtmlModeBar.Visible := True;
  UpdateHtmlModeButtons;
  if FSvgShowSource then
  begin
    ShowSvgSource;
    Exit;
  end;
  if LoadAsSkiaImage(APath) then
  begin
    if not FImgChrome then
      ShowImageTools(True);
    FSvgHead := True;
    FLottieHead := False;
    if Assigned(FHtmlModeBar) then
      FHtmlModeBar.Visible := True;
    UpdateHtmlModeButtons;
    LayoutImageHeader(nil);
    Exit;
  end;
  ShowSvgSource;
end;

procedure TFilePreview.HtmlPageClick(Sender: TObject);
begin
  if FPath = '' then
    Exit;
  if FSvgHead then
  begin
    ShowSvgScene;
    Exit;
  end;
  if FLottieHead then
  begin
    ShowLottieScene;
    Exit;
  end;
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
  if FSvgHead then
  begin
    ShowSvgSource;
    Exit;
  end;
  if FLottieHead then
  begin
    ShowLottieSource;
    Exit;
  end;
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
    if UseLottieJson then
    begin
      Buf := ReadLottieJsonBytes(Path, TextQVMaxBytes, True);
      Total := Length(Buf);
      Shown := Total;
    end
    else if UseSvgText then
    begin
      Buf := ReadSvgSourceBytes(Path, TextQVMaxBytes);
      Shown := Length(Buf);
      Total := Shown;
      if Shown >= TextQVMaxBytes then
      begin
        Total := TFile.GetSize(Path);
        if Total < Shown then
          Total := Shown;
      end;
    end
    else
    begin
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
    end;
    if (UseLottieJson or UseSvgText) and (Length(Buf) = 0) then
      Ok := False
    else
    begin
      Text := DecodeTextBytes(Buf, Mode, EncLabel);
      SplitTextLines(Text, Lines, MaxCols);
      Ok := True;
    end;
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
  W := 0;
  if Assigned(FBtnEnc) then
    W := W + FBtnEnc.Width + FBtnEnc.Margins.Left + FBtnEnc.Margins.Right;
  if Assigned(FBtnSheets) then
    W := W + FBtnSheets.Width + FBtnSheets.Margins.Left + FBtnSheets.Margins.Right;
  if Assigned(FBtnCode) then
    W := W + FBtnCode.Width + FBtnCode.Margins.Left + FBtnCode.Margins.Right;
  if FTextCode then
  begin
    if Assigned(FBtnHi) then
      W := W + FBtnHi.Width + FBtnHi.Margins.Left + FBtnHi.Margins.Right;
    if Assigned(FBtnWrap) then
      W := W + FBtnWrap.Width + FBtnWrap.Margins.Left + FBtnWrap.Margins.Right;
  end;
  FTextBar.Margins.Right := 8;
  FTextBar.Width := W + 4;
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
    S := S + Lf('qv.text.shown',
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
    S := S + Lf('qv.text.sel', [N]);
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
    ShowSheetBar(False);
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
    ShowInfoKey('qv.text.fail');
    Exit;
  end;
  FTextLines := Job.Lines;
  FTextEncLabel := Job.EncLabel;
  FTextTotal := Job.Total;
  FTextShown := Job.Shown;
  FTextMaxCols := Job.MaxCols;
  FTextCode := LoadTextViewIsCode(FTextExt);
  if FSvgHead and FSvgShowSource then
    FTextCode := True;
  ShowTextModel;
end;

procedure TFilePreview.StartTextLoad(const APath: string;
  const AExtOverride: string; ALottieJson: Boolean);
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
  if FSvgHead and FSvgShowSource then
    FTextExt := '.svg'
  else if AExtOverride <> '' then
    FTextExt := LowerCase(AExtOverride)
  else
    FTextExt := LowerCase(ExtractFileExt(APath));
  Job := TTextLoadJob.Create;
  Job.Preview := Self;
  Job.Path := APath;
  Job.Gen := FLoadGen;
  Job.Mode := FTextEnc;
  Job.UseLottieJson := ALottieJson;
  Job.UseSvgText := FSvgHead and FSvgShowSource;
  FTextJob := Job;
  ShowTextChrome(True);
  if Assigned(FInfo) then
  begin
    ShowInfoKey('qv.reading');
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
        SetKindKey('qv.kind.mhtml')
      else
        SetKindKey('qv.kind.html');
      Exit;
    end;
    SetKindKey('qv.kind.htmlie');
    {$IFDEF MSWINDOWS}
    Why := WebView2BlockReason;
    if (Why <> '') and Assigned(FMeta) then
    begin
      FMetaKey := Why;
      Why := L(Why);
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
  VecLabel: string;
  PrintW, PrintH, ScreenW, ScreenH: Integer;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(APath));
  try
    if Ext = '.dxf' then
    begin
      if LoadDxfPreview(APath, FImage.Bitmap, 2400) then
      begin
        FImgKind := ivRaster;
        FViewW := FImage.Bitmap.Width;
        FViewH := FImage.Bitmap.Height;
        FMetaPrintW := 0;
        FMetaPrintH := 0;
        FMetaScreenW := 0;
        FMetaScreenH := 0;
        FFrameW := FViewW;
        FFrameH := FViewH;
        if Assigned(FKindText) then
          SetKindRaw('DXF');
        ShowRasterImage;
        Exit(True);
      end;
      Exit(False);
    end;
    if ExtIn(Ext, ['.emf', '.wmf', '.eps', '.cdr', '.cdt']) then
    begin
      if LoadVectorPreview(APath, FImage.Bitmap, VecLabel,
        PrintW, PrintH, ScreenW, ScreenH) then
      begin
        FImgKind := ivRaster;
        FViewW := FImage.Bitmap.Width;
        FViewH := FImage.Bitmap.Height;
        FMetaPrintW := 0;
        FMetaPrintH := 0;
        FMetaScreenW := 0;
        FMetaScreenH := 0;
        if (PrintW > 0) and (PrintH > 0) and (ScreenW > 0) and (ScreenH > 0) then
        begin
          { Подпись — полный печатный размер, даже если битмап ужат капом 4096. }
          FMetaPrintW := PrintW;
          FMetaPrintH := PrintH;
          FMetaScreenW := ScreenW;
          FMetaScreenH := ScreenH;
          FFrameW := PrintW;
          FFrameH := PrintH;
        end
        else if (ScreenW > 0) and (ScreenH > 0) then
        begin
          FMetaScreenW := ScreenW;
          FMetaScreenH := ScreenH;
          FFrameW := ScreenW;
          FFrameH := ScreenH;
        end
        else
        begin
          FFrameW := FViewW;
          FFrameH := FViewH;
        end;
        if Assigned(FKindText) and (VecLabel <> '') then
          SetKindRaw(VecLabel);
        ShowRasterImage;
        Exit(True);
      end;
      Exit(False);
    end;
    if ExtIn(Ext, ['.svg', '.svgz', '.ai']) then
    begin
      if TryLoadSvgDom(APath, FSvgDom) then
      begin
        MeasureSvgFrame;
        FSvgBox.Visible := True;
        FSvgBox.HitTest := False;
        FSvgBox.BringToFront;
        if Assigned(FImgHost) then
          FImgHost.Visible := True;
        if Assigned(FImage) then
          FImage.Visible := False;
        Exit(True);
      end;
      FSvgDom := nil;
      if Ext <> '.ai' then
        Exit;
    end;
    if ExtIn(Ext, ['.psd', '.psb']) then
    begin
      { 0,0 — пиксели как в заголовке PSD, не размер панели и не DPI экрана. }
      if LoadPsdPreview(APath, 0, 0, FImage.Bitmap, SrcW, SrcH) then
      begin
        FImgKind := ivPsd;
        FDocW := SrcW;
        FDocH := SrcH;
        FViewW := FImage.Bitmap.Width;
        FViewH := FImage.Bitmap.Height;
        if SrcW > 0 then
        begin
          FFrameW := SrcW;
          FFrameH := SrcH;
        end
        else
        begin
          FFrameW := FViewW;
          FFrameH := FViewH;
        end;
        ShowRasterImage;
        Exit(True);
      end;
      Exit(False);
    end;
    if ExtIn(Ext, ['.gif', '.webp', '.tgs', '.lottie']) or
      ((Ext = '.json') and LooksLikeLottieFile(APath)) then
    begin
      if LoadAsAnimated(APath) then
      begin
        FImgKind := ivAnim;
        FViewW := Max(1, Round(FAnim.OriginalSize.Width));
        FViewH := Max(1, Round(FAnim.OriginalSize.Height));
        FFrameW := FViewW;
        FFrameH := FViewH;
        if Assigned(FImgHost) then
          FImgHost.Visible := True;
        if Assigned(FImage) then
          FImage.Visible := False;
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
      FImgKind := ivRaster;
      FViewW := FImage.Bitmap.Width;
      FViewH := FImage.Bitmap.Height;
      FFrameW := FViewW;
      FFrameH := FViewH;
      ShowRasterImage;
    end;
  except
    Result := False;
  end;
end;

procedure TFilePreview.ApplyPdfSizeText;
var
  S: string;
begin
  if not Assigned(FKindText) then
    Exit;
  if (FPdfPages < 1) or (FPdfPrintW < 1) or (FPdfPrintH < 1) or
     (FPdfPointW < 1) or (FPdfPointH < 1) then
  begin
    FKindText.Width := 110;
    if FPdfPages > 1 then
      FKindText.Text := Lf('qv.kind.pdfn', [FPdfPage + 1, FPdfPages])
    else
      FKindText.Text := L('qv.kind.pdf');
    Exit;
  end;
  if FPdfPages > 1 then
    S := Lf('qv.pdf.sizen', [FPdfPrintW, FPdfPrintH, FPdfPointW, FPdfPointH,
      FPdfPage + 1, FPdfPages])
  else
    S := Lf('qv.pdf.size', [FPdfPrintW, FPdfPrintH, FPdfPointW, FPdfPointH]);
  FKindText.Text := S;
  FKindText.Width := Max(320, Length(S) * 7.4 + 16);
  if Assigned(FPxText) and FImgChrome and not FEditing then
  begin
    FPxText.Text := S;
    LayoutImageHeader(nil);
  end;
end;

procedure TFilePreview.ApplyMetaSizeText;
var
  S: string;
begin
  if not Assigned(FKindText) then
    Exit;
  if (FMetaPrintW > 0) and (FMetaPrintH > 0) and
     (FMetaScreenW > 0) and (FMetaScreenH > 0) then
  begin
    FFrameW := FMetaPrintW;
    FFrameH := FMetaPrintH;
    S := Lf('qv.vec.size', [FMetaPrintW, FMetaPrintH, FMetaScreenW, FMetaScreenH]);
    FKindText.Width := Max(320, Length(S) * 7.4 + 16);
  end
  else if (FMetaScreenW > 0) and (FMetaScreenH > 0) then
  begin
    FFrameW := FMetaScreenW;
    FFrameH := FMetaScreenH;
    S := Format('%d × %d', [FMetaScreenW, FMetaScreenH]);
    if Length(S) > 18 then
      FKindText.Width := Max(110, Length(S) * 7.4 + 16)
    else
      FKindText.Width := 110;
  end
  else
    Exit;
  FKindKey := 'qv.vec.size';
  FKindText.Text := S;
  if Assigned(FPxText) and FImgChrome and not FEditing then
  begin
    FPxText.Text := S;
    LayoutImageHeader(nil);
  end;
end;

function TFilePreview.OpenPdfDoc: Boolean;
begin
  Result := FPdf <> nil;
  if Result then
    Exit;
  if (FPdfFile = '') or (FPdfPages < 1) or not TFile.Exists(FPdfFile) then
    Exit;
  if not TPdfiumDoc.Available then
    Exit;
  try
    FPdf := TPdfiumDoc.Create(FPdfFile);
    Result := (FPdf <> nil) and (FPdf.PageCount >= 1);
  except
    Result := False;
  end;
  if not Result then
    FreeAndNil(FPdf);
end;

procedure TFilePreview.ShowPdfPage(AIndex: Integer; AResetView: Boolean);
var
  Bmp: TBitmap;
  KeepW, KeepH, KeepPw, KeepPh: Integer;
begin
  if FPdf = nil then
    Exit;
  if (AIndex < 0) or (AIndex >= FPdf.PageCount) then
  begin
    FreeAndNil(FPdf);
    Exit;
  end;
  FPdfPages := FPdf.PageCount;
  try
    if FImgDirty then
      ShowToast(L('qv.toast.failed'));
    if FBuildJob <> nil then
    begin
      TImgBuildJob(FBuildJob).Preview := nil;
      FBuildJob := nil;
    end;
    CancelCrop;
    FImgBuilding := False;
    SetLength(FImgOps, 0);
    FreeAndNil(FImgOriginal);
    FImgDirty := False;
    FEditing := False;
    if Assigned(FSizeStrip) then
      FSizeStrip.Visible := False;
    if Assigned(FEditBar) then
      FEditBar.Visible := False;
    KeepW := FPdfPrintW;
    KeepH := FPdfPrintH;
    KeepPw := FPdfPointW;
    KeepPh := FPdfPointH;
    Bmp := FPdf.RenderPagePrint(AIndex, FPdfPrintW, FPdfPrintH, FPdfPointW, FPdfPointH);
    if Bmp = nil then
    begin
      FPdfPrintW := KeepW;
      FPdfPrintH := KeepH;
      FPdfPointW := KeepPw;
      FPdfPointH := KeepPh;
      Exit;
    end;
    try
      FImage.Bitmap.Assign(Bmp);
    finally
      Bmp.Free;
    end;
    FPdfPage := AIndex;
    FPdfZoom := 1;
    if AResetView then
      ShowRasterImage(True)
    else
      ShowRasterImage(False);
    AdoptRasterView;
    { После AdoptRasterView: он пишет в хедер размер битмапа. Нужны пункты и 300 dpi. }
    SetKindKey('qv.pdf.size');
  finally
    { Страница уже в битмапе. Хэндл PDFium не держим — файл можно удалить. }
    FreeAndNil(FPdf);
  end;
end;

function TFilePreview.LoadAsPdf(const APath: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not TPdfiumDoc.Available then
    Exit;
  if not TPdfiumDoc.LooksLikePdfFamily(APath) and
     not ExtIn(LowerCase(ExtractFileExt(APath)), ['.pdf', '.ai']) then
    Exit;
  try
    FreeAndNil(FPdf);
    FPdf := TPdfiumDoc.Create(APath);
    if FPdf.PageCount < 1 then
    begin
      FreeAndNil(FPdf);
      Exit;
    end;
    FPdfFile := APath;
    FPdfPages := FPdf.PageCount;
    FSheetCombo.Items.BeginUpdate;
    try
      FSheetCombo.Items.Clear;
      for I := 0 to FPdf.PageCount - 1 do
        FSheetCombo.Items.Add(Lf('qv.page.n', [I + 1]));
    finally
      FSheetCombo.Items.EndUpdate;
    end;
    FSheetCombo.ItemIndex := 0;
    ShowSheetBar(FPdfPages > 1);
    ShowPdfPage(0);
    Result := Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0);
    if not Result then
    begin
      FPdfPages := 0;
      FPdfFile := '';
      FreeAndNil(FPdf);
    end;
  except
    FreeAndNil(FPdf);
    FPdfPages := 0;
    FPdfFile := '';
    Result := False;
  end;
end;

procedure TFilePreview.PaintFontMap(Sender: TObject; Canvas: TCanvas);
var
  Cols, I, C, R, Code, N: Integer;
  CellW, GlyphSize: Single;
  Cell, GlyphR, CodeR, Frame: TRectF;
  State: TCanvasSaveState;
begin
  if not Assigned(FFontMap) then
    Exit;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColors.PanelBackground;
  Canvas.FillRect(FFontMap.LocalRect, 0, 0, [], 1);
  N := Length(FFontCodes);
  if N = 0 then
    Exit;
  Cols := FontCols;
  CellW := FFontMap.Width / Cols;
  if CellW < 1 then
    Exit;
  GlyphSize := FFontSize;
  if GlyphSize > 22 then
    GlyphSize := 22;
  if GlyphSize < 10 then
    GlyphSize := 10;
  State := Canvas.SaveState;
  try
    Canvas.IntersectClipRect(FFontMap.LocalRect);
    for I := 0 to N - 1 do
    begin
      C := I mod Cols;
      R := I div Cols;
      Cell := TRectF.Create(C * CellW, R * 36 - FFontScrollY,
        (C + 1) * CellW, R * 36 + 36 - FFontScrollY);
      if Cell.Bottom < 0 then
        Continue;
      if Cell.Top > FFontMap.Height then
        Break;
      Frame := TRectF.Create(Cell.Left + 1, Cell.Top + 1, Cell.Right - 1, Cell.Bottom - 1);
      Canvas.Fill.Color := FColors.ItemBackground;
      Canvas.FillRect(Frame, 2, 2, AllCorners, 1);
      Code := FFontCodes[I];
      GlyphR := TRectF.Create(Cell.Left, Cell.Top, Cell.Right, Cell.Bottom - 12);
      DrawOwnedGlyph(Canvas, GlyphR, Code, GlyphSize, FColors.TextColor);
      Canvas.Font.Family := 'Segoe UI';
      Canvas.Font.Size := 9;
      Canvas.Font.Style := [];
      Canvas.Fill.Color := FColors.SubTextColor;
      CodeR := TRectF.Create(Cell.Left, Cell.Bottom - 12, Cell.Right, Cell.Bottom - 1);
      Canvas.FillText(CodeR, FontHex(Code), False, 1, [],
        TTextAlign.Center, TTextAlign.Center);
      if I = FFontSel then
      begin
        Canvas.Stroke.Kind := TBrushKind.Solid;
        Canvas.Stroke.Dash := TStrokeDash.Solid;
        Canvas.Stroke.Color := FColors.FocusStroke;
        Canvas.Stroke.Thickness := 1.5;
        Canvas.DrawRect(Frame, 1);
      end;
    end;
  finally
    Canvas.RestoreState(State);
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
    FBtnPlay.SetCaption(L('qv.stop'));
  end;
  if Assigned(FBtnSaveFrame) then
  begin
    FBtnSaveFrame.Visible := not AAudio;
    FBtnSaveFrame.BringToFront;
  end;
  if Assigned(FBtnSaveClip) then
    FBtnSaveClip.BringToFront;
  if Assigned(FMeta) then
    FMeta.Visible := False;
  FVidW := 0;
  FVidH := 0;
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
  if Assigned(FMeta) then
    FMeta.Visible := True;
  if Assigned(FKindText) then
    FKindText.Width := 110;
  FVidW := 0;
  FVidH := 0;
  SetMediaShelfLocked(False);
  HideVideoStill;
  if FSaveMedia then
    CloseSaveCard;
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
      FBtnPlay.SetCaption(L('qv.start'));
    end
    else
    begin

      FBtnPlay.SetIcon(#$E769);
      FBtnPlay.SetCaption(L('qv.stop'));
      FMediaClockMs := TThread.GetTickCount;
    end;
  UpdateMediaHud;
  {$ENDIF}
end;

procedure TFilePreview.MediaSaveClick(Sender: TObject);
begin
  OpenMediaSaveCard(0);
end;

procedure TFilePreview.MediaSaveFrameClick(Sender: TObject);
begin
  SaveQuickFrame;
end;

procedure TFilePreview.RefreshVideoLabel;
var
  W, H: Integer;
begin
  if FDestroying or not FIsVideo or not Assigned(FKindText) then
    Exit;
  W := 0;
  H := 0;
{$IFDEF MSWINDOWS}
  if Assigned(FMpv) and FMpv.VideoPixelSize(W, H) then
  begin
    if (W = FVidW) and (H = FVidH) and (FKindText.Text <> '') then
      Exit;
    FVidW := W;
    FVidH := H;
    FKindText.Width := 168;
    SetKindRaw(Format('%d × %d', [W, H]));
  end;
{$ENDIF}
end;

function TFilePreview.MediaExt: string;
var
  Ix: Integer;
  Ext: string;
begin
  Ix := 0;
  if Assigned(FSaveFmt) then
    Ix := FSaveFmt.ItemIndex;
  if Ix < 0 then
    Ix := 0;
  case FSaveKind of
    1:
      case Ix of
        1: Result := '.jpg';
        2: Result := '.webp';
        3: Result := '.bmp';
      else
        Result := '.png';
      end;
    2:
      case Ix of
        1: Result := '.mp3';
        2: Result := '.wav';
        3: Result := '.flac';
      else
        Result := '.m4a';
      end;
  else
    if Ix = 0 then
    begin
      Ext := ExtractFileExt(FPath);
      if Ext = '' then
        Ext := '.mp4';
      Result := Ext;
    end
    else if Assigned(FSaveFmt) and (Ix >= 0) and (Ix < FSaveFmt.Items.Count) and
      SameText(FSaveFmt.Items[Ix], 'MKV') then
      Result := '.mkv'
    else if Assigned(FSaveFmt) and (Ix >= 0) and (Ix < FSaveFmt.Items.Count) and
      SameText(FSaveFmt.Items[Ix], 'WebM') then
      Result := '.webm'
    else
      Result := '.mp4';
  end;
end;

function TFilePreview.MediaDefaultName: string;
var
  Stem, Mark: string;
begin
  Stem := ChangeFileExt(ExtractFileName(FPath), '');
  case FSaveKind of
    1: Mark := '_frame';
    2: Mark := '_audio';
  else
    Mark := '_clip';
  end;
  Result := Stem + Mark + MediaExt;
end;

function TFilePreview.MediaQualMode: Integer;
var
  Ix: Integer;
begin
  Result := 0;
  Ix := 0;
  if Assigned(FSaveFmt) then
    Ix := FSaveFmt.ItemIndex;
  if Ix < 0 then
    Ix := 0;
  case FSaveKind of
    0:
      if Ix > 0 then
        Result := 1;
    1:
      if (Ix = 1) or (Ix = 2) then
        Result := 1;
    2:
      if (Ix = 0) or (Ix = 1) then
        Result := 2;
  end;
end;

function TFilePreview.MediaRangeText: string;
var
  Full: Boolean;
begin
  if FSaveKind = 1 then
    Exit(Lf('qv.frametime', [FormatMediaClock(Max(0, FMediaPos))]));
  Full := (FTrimA <= 0.05) and ((FMediaDur <= 0.05) or (FTrimB >= FMediaDur - 0.25));
  if Full then
    Result := L('qv.wholefile')
  else
    Result := FormatMediaClock(FTrimA) + ' – ' + FormatMediaClock(FTrimB);
end;

procedure TFilePreview.FillImageFormats;
begin
  if not Assigned(FSaveFmt) then
    Exit;
  FSaveSilence := True;
  try
    FSaveFmt.Items.Clear;
    FSaveFmt.Items.Add('PNG');
    FSaveFmt.Items.Add('JPEG');
    FSaveFmt.Items.Add('WebP');
    FSaveFmt.Items.Add('BMP');
    FSaveFmt.Items.Add('ICO');
    FSaveFmt.ItemIndex := 0;
  finally
    FSaveSilence := False;
  end;
end;

procedure TFilePreview.FillMediaFormats;
var
  Ext, Name: string;
begin
  if not Assigned(FSaveFmt) then
    Exit;
  FSaveSilence := True;
  try
    FSaveFmt.Items.Clear;
    case FSaveKind of
      1:
        begin
          FSaveFmt.Items.Add('PNG');
          FSaveFmt.Items.Add('JPEG');
          FSaveFmt.Items.Add('WebP');
          FSaveFmt.Items.Add('BMP');
        end;
      2:
        begin
          FSaveFmt.Items.Add('M4A');
          FSaveFmt.Items.Add('MP3');
          FSaveFmt.Items.Add('WAV');
          FSaveFmt.Items.Add('FLAC');
        end;
    else
      begin
        Ext := ExtractFileExt(FPath);
        if Length(Ext) > 1 then
          Name := UpperCase(Copy(Ext, 2, 8))
        else
          Name := L('qv.sourcename');
        FSaveFmt.Items.Add(Name);
        if not SameText(Name, 'MP4') then
          FSaveFmt.Items.Add('MP4');
        if not SameText(Name, 'MKV') then
          FSaveFmt.Items.Add('MKV');
        if not SameText(Name, 'WEBM') then
          FSaveFmt.Items.Add('WebM');
      end;
    end;
    FSaveFmt.ItemIndex := 0;
  finally
    FSaveSilence := False;
  end;
end;

procedure TFilePreview.ApplyMediaKind;
var
  Mode: Integer;
begin
  if Assigned(FBtnKindClip) then
    FBtnKindClip.SetSelected((not FIsAudio) and (FSaveKind = 0));
  if Assigned(FBtnKindFrame) then
    FBtnKindFrame.SetSelected((not FIsAudio) and (FSaveKind = 1));
  if Assigned(FBtnKindAudio) then
    FBtnKindAudio.SetSelected((not FIsAudio) and (FSaveKind = 2));
  if Assigned(FSaveKindRow) then
    FSaveKindRow.Visible := FSaveMedia and not FIsAudio;
  if Assigned(FSaveRange) then
  begin
    FSaveRange.Visible := FSaveMedia;
    FSaveRange.Text := MediaRangeText;
  end;
  FillMediaFormats;
  Mode := MediaQualMode;
  FSaveSilence := True;
  try
    if Mode = 2 then
      FSaveQual.Text := '192'
    else
      FSaveQual.Text := '90';
    if not FSaveNameOwn then
      FSaveName.Text := MediaDefaultName;
  finally
    FSaveSilence := False;
  end;
  RefreshSaveExists;
  LayoutSaveCard(nil);
end;

procedure TFilePreview.SaveKindClick(Sender: TObject);
begin
  if not (Sender is TFluentButton) then
    Exit;
  FSaveKind := TFluentButton(Sender).Tag;
  if FIsAudio then
    FSaveKind := 2;
  FSaveNameOwn := False;
  ApplyMediaKind;
end;

procedure TFilePreview.OpenMediaSaveCard(AKind: Integer);
begin
  if FExporting or (FPath = '') or not TFile.Exists(FPath) then
    Exit;
  if not (FIsAudio or FIsVideo) then
    Exit;
  FSaveMedia := True;
  FSaveFont := False;
  FSaveArmed := False;
  FSaveBlocked := False;
  if Assigned(FSaveNote) then
    FSaveNote.Visible := False;
  if Assigned(FSaveOk) then
  begin
    FSaveOk.Enabled := True;
    FSaveOk.Opacity := 1;
  end;
  if FIsAudio then
    FSaveKind := 2
  else
    FSaveKind := EnsureRange(AKind, 0, 2);
  FSaveNameOwn := False;
  FSaveDir := ExtractFilePath(FPath);
  if Assigned(FSaveFolder) then
    FSaveFolder.Text := FSaveDir;
  if Assigned(FSaveTitle) then
    FSaveTitle.Text := L('qv.save');
  if FIsVideo and not FMediaPaused then
  begin
    FMediaPaused := True;
{$IFDEF MSWINDOWS}
    if Assigned(FMpv) then
      FMpv.SetPaused(True);
{$ENDIF}
    if Assigned(FBtnPlay) then
    begin
      FBtnPlay.SetIcon(#$E768);
      FBtnPlay.SetCaption(L('qv.start'));
    end;
  end;
  ShowVideoStill;
  SetMediaShelfLocked(True);
  if Assigned(FSaveShade) then
  begin
    FSaveShade.Visible := True;
    FSaveShade.BringToFront;
  end;
  ApplyMediaKind;
  LayoutSaveCard(nil);
  {$IFDEF MSWINDOWS}
  SyncHostWnd;
  {$ENDIF}
  if Assigned(FSaveName) and FSaveName.CanFocus then
    FSaveName.SetFocus;
end;

procedure TFilePreview.SaveQuickFrame;
var
  Src, Dst: string;
  At: Double;
  Gen, N: Integer;
begin
  if FExporting or not FIsVideo or (FPath = '') or not TFile.Exists(FPath) then
    Exit;
  Src := FPath;
  Dst := ExtractFilePath(Src) + ChangeFileExt(ExtractFileName(Src), '') + '_frame.png';
  N := 2;
  while TFile.Exists(Dst) and (N < 1000) do
  begin
    Dst := ExtractFilePath(Src) + ChangeFileExt(ExtractFileName(Src), '') +
      '_frame ' + IntToStr(N) + '.png';
    Inc(N);
  end;
  At := FMediaPos;
  if At < 0 then
    At := 0;
  FExporting := True;
  if Assigned(FBtnSaveFrame) then
    FBtnSaveFrame.StartBusy;
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
{$IFDEF MSWINDOWS}
        Ok := ExportVideoFrame(Src, Dst, At, 90, Msg);
{$ELSE}
        Msg := 'qv.framewin';
{$ENDIF}
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
          if Assigned(FBtnSaveFrame) then
            FBtnSaveFrame.EndBusy;
          if FDestroying or (FLoadGen <> Gen) then
            Exit;
          if Ok then
            ShowToast(ExtractFileName(Dst))
          else if StartsText('qv.', Msg) then
            ShowInfoKey(Msg)
          else if Msg <> '' then
            ShowInfo(Msg);
        end);
    end).Start;
end;

procedure TFilePreview.CommitMediaSave;
var
  Path, Src: string;
  Kind, Ix, Q, Crf, Bitrate, Gen: Integer;
  A0, B0, Dur0, At: Double;
  CopyOnly, Full: Boolean;
begin
  if FExporting or FImgBuilding then
    Exit;
  Path := SaveTargetPath;
  if Path = '' then
    Exit;
  if FSaveBlocked or SameText(ExpandFileName(Path), ExpandFileName(FPath)) then
  begin
    FSaveBlocked := True;
    FSaveArmed := False;
    if Assigned(FSaveExists) then
    begin
      FSaveExists.Text := L('qv.replaceopen');
      FSaveExists.Visible := True;
    end;
    LayoutSaveCard(nil);
    Exit;
  end;
  if TFile.Exists(Path) and not FSaveArmed then
  begin
    if Assigned(FSaveExists) then
    begin
      FSaveExists.Text := L('qv.exists');
      FSaveExists.Visible := True;
    end;
    FSaveArmed := True;
    LayoutSaveCard(nil);
    Exit;
  end;
  Src := FPath;
  Kind := FSaveKind;
  Ix := 0;
  if Assigned(FSaveFmt) then
    Ix := FSaveFmt.ItemIndex;
  Q := StrToIntDef(Trim(FSaveQual.Text), 90);
  if MediaQualMode = 2 then
  begin
    Bitrate := EnsureRange(StrToIntDef(Trim(FSaveQual.Text), 192), 64, 320);
    Q := 90;
  end
  else
  begin
    Q := EnsureRange(Q, 1, 100);
    Bitrate := 192;
  end;
  Crf := 32 - Round((Q - 1) * 14 / 99);
  A0 := FTrimA;
  B0 := FTrimB;
  Dur0 := FMediaDur;
  At := Max(0, FMediaPos);
  Full := (A0 <= 0.05) and ((Dur0 <= 0.05) or (B0 >= Dur0 - 0.25));
  if Full then
  begin
    A0 := 0;
    B0 := Dur0;
  end;
  if B0 <= A0 then
    B0 := A0 + 0.2;
  CopyOnly := (Kind = 0) and (Ix <= 0);
  CloseSaveCard;
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
{$IFDEF MSWINDOWS}
        case Kind of
          1:
            Ok := ExportVideoFrame(Src, Path, At, Q, Msg);
          2:
            Ok := ExportAudioOnly(Src, Path, A0, B0, Bitrate, Msg);
        else
          if CopyOnly and Full and SameText(ExtractFileExt(Src), ExtractFileExt(Path)) then
          try
            TFile.Copy(Src, Path, True);
            Ok := TFile.Exists(Path);
          except
            Ok := False;
          end
          else if CopyOnly then
            Ok := ExportClipCopy(Src, Path, A0, B0, Msg)
          else
            Ok := ExportClipEncode(Src, Path, A0, B0, Crf, Msg);
        end;
{$ELSE}
        Msg := 'qv.mediawin';
{$ENDIF}
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
          if FDestroying or (FLoadGen <> Gen) then
            Exit;
          if Ok then
            ShowToast(ExtractFileName(Path))
          else if StartsText('qv.', Msg) then
            ShowInfoKey(Msg)
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
      FBtnPlay.SetCaption(L('qv.start'));
    end
    else
    begin
      FBtnPlay.SetIcon(#$E769);
      FBtnPlay.SetCaption(L('qv.stop'));
    end;
  if Assigned(FTimeText) then
    FTimeText.Text := FormatMediaClock(FMediaPos) + ' / ' + FormatMediaClock(FMediaDur);
  if Assigned(FSeekBox) then
    FSeekBox.Repaint;
  if Assigned(FWaveBox) and FWaveBox.Visible then
    FWaveBox.Repaint;
  RefreshVideoLabel;
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
  FSigText.Text := Lf('qv.sig',
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
    ShowToast(L('qv.toast.norights'));
    Exit;
  end;
  FImgDirty := False;
  FPath := Dest;
  HideSigBanner;
  if Assigned(FTitle) then
    FTitle.Text := ExtractFileName(Dest);
  if Assigned(FOnDiskChanged) then
    FOnDiskChanged(Self);
  ShowToast(L('qv.toast.saved'));
end;

procedure TFilePreview.ClearIcoFrames;
begin
  if Assigned(FIcoFrames) then
    FIcoFrames.Clear;
  FreeAndNil(FIcoScroll);
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
    ShowToast(L('qv.toast.failed'));
  FImgDirty := False;
  ResetEditState;
  CancelCrop;
  FImage.Bitmap.Assign(FIcoFrames[AIndex]);
  FImgKind := ivRaster;
  FViewW := FImage.Bitmap.Width;
  FViewH := FImage.Bitmap.Height;
  FFrameW := FViewW;
  FFrameH := FViewH;
  FIcoIndex := AIndex;
  SetHeaderPixels(FFrameW, FFrameH);
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

procedure TFilePreview.StyleIcoCaptions;

  procedure Walk(AParent: TFmxObject);
  var
    I: Integer;
    C: TFmxObject;
  begin
    if AParent = nil then
      Exit;
    for I := 0 to AParent.ChildrenCount - 1 do
    begin
      C := AParent.Children[I];
      if C is TText then
      begin
        TText(C).Color := FColors.TextColor;
        TText(C).TextSettings.FontColor := FColors.TextColor;
      end;
      Walk(C);
    end;
  end;

begin
  Walk(FIcoBar);
end;

procedure TFilePreview.ShowIcoStrip(const APath: string);
var
  Frames: TArray<TBitmap>;
  Labels: TArray<string>;
  I, MaxH, BW, BH, CellW: Integer;
  X: Single;
  Host: THorzScrollBox;
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
  MaxH := 1;
  for I := 0 to FIcoFrames.Count - 1 do
    if FIcoFrames[I].Height > MaxH then
      MaxH := FIcoFrames[I].Height;
  FIcoBar.Height := MaxH + 36;
  Host := THorzScrollBox.Create(FIcoBar);
  Host.Parent := FIcoBar;
  Host.Align := TAlignLayout.Client;
  Host.ShowScrollBars := False;
  Host.AniCalculations.AutoShowing := False;
  Host.OnResize := IcoHostResize;
  Host.OnViewportPositionChange := IcoViewportChange;
  X := 4;
  for I := 0 to FIcoFrames.Count - 1 do
  begin
    BW := Max(1, FIcoFrames[I].Width);
    BH := Max(1, FIcoFrames[I].Height);
    CellW := Max(BW + 12, 52);
    Cell := TLayout.Create(Host);
    Cell.Parent := Host;
    Cell.Align := TAlignLayout.None;
    Cell.SetBounds(X, 0, CellW, MaxH + 22);
    Cell.HitTest := True;
    Cell.Tag := I;
    Cell.OnClick := IcoFrameClick;
    Img := TImage.Create(Cell);
    Img.Parent := Cell;
    Img.Align := TAlignLayout.None;
    Img.HitTest := False;
    Img.WrapMode := TImageWrapMode.Original;
    Img.Bitmap.Assign(FIcoFrames[I]);
    Img.SetBounds((CellW - BW) / 2, 20 + (MaxH - BH) / 2, BW, BH);
    Cap := TText.Create(Cell);
    Cap.Parent := Cell;
    Cap.Align := TAlignLayout.None;
    Cap.HitTest := False;
    Cap.SetBounds(0, 2, CellW, 16);
    Cap.Text := Labels[I];
    ApplyFluentText(Cap, 10, False);
    Cap.TextSettings.HorzAlign := TTextAlign.Center;
    Cap.TextSettings.VertAlign := TTextAlign.Center;
    X := X + CellW;
  end;
  StyleIcoCaptions;
  FIcoScroll := TCustomFileScrollbar.Create(FIcoBar, Host);
  FIcoScroll.Orientation := TOrientation.Horizontal;
  FIcoScroll.ApplyTheme(FColors);
  Host.InvalidateContentSize;
  Host.RealignContent;
  FIcoBar.Visible := True;
  FIcoScroll.UpdateThumb;
  ApplyIcoFrame(FIcoFrames.Count - 1);
end;

procedure TFilePreview.IcoHostResize(Sender: TObject);
begin
  if Assigned(FIcoScroll) then
    FIcoScroll.UpdateThumb;
end;

procedure TFilePreview.IcoViewportChange(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF;
  const ContentSizeChanged: Boolean);
begin
  if Assigned(FIcoScroll) then
    FIcoScroll.UpdateThumb;
end;

procedure TFilePreview.EditToolsResize(Sender: TObject);
begin
  if Assigned(FEditScrollBar) then
    FEditScrollBar.UpdateThumb;
end;

procedure TFilePreview.EditToolsViewport(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF;
  const ContentSizeChanged: Boolean);
begin
  if Assigned(FEditScrollBar) then
    FEditScrollBar.UpdateThumb;
end;

function NormDeg(ADeg: Integer): Integer;
begin
  Result := ADeg mod 360;
  if Result < 0 then
    Inc(Result, 360);
end;

function ClampChannel(const AValue: Double): Byte;
begin
  if AValue <= 0 then
    Result := 0
  else if AValue >= 255 then
    Result := 255
  else
    Result := Round(AValue);
end;

function ReadPx(ARow: PByte; X: Integer): TAlphaColorRec;
begin
  Result := TAlphaColorRec(PAlphaColor(ARow + X * 4)^);
end;

procedure WritePx(ARow: PByte; X: Integer; const AColor: TAlphaColorRec);
begin
  PAlphaColor(ARow + X * 4)^ := AColor.Color;
end;

procedure BoxAverageRow(ASrc: PByte; ASrcW: Integer; ADst: PByte; ADstW: Integer);
var
  X, I, I0, I1: Integer;
  X0, X1, Span, PixW, Wgt, AccB, AccG, AccR, AccA: Double;
  C, OutC: TAlphaColorRec;
begin
  if ADstW < 1 then
    Exit;
  Span := ASrcW / ADstW;
  for X := 0 to ADstW - 1 do
  begin
    X0 := X * Span;
    X1 := X0 + Span;
    if X1 > ASrcW then
      X1 := ASrcW;
    I0 := Floor(X0);
    I1 := Ceil(X1) - 1;
    if I0 < 0 then
      I0 := 0;
    if I1 >= ASrcW then
      I1 := ASrcW - 1;
    AccB := 0;
    AccG := 0;
    AccR := 0;
    AccA := 0;
    Wgt := 0;
    for I := I0 to I1 do
    begin
      PixW := Min(I + 1.0, X1) - Max(Double(I), X0);
      if PixW <= 0 then
        Continue;
      C := ReadPx(ASrc, I);
      AccB := AccB + C.B * PixW;
      AccG := AccG + C.G * PixW;
      AccR := AccR + C.R * PixW;
      AccA := AccA + C.A * PixW;
      Wgt := Wgt + PixW;
    end;
    if Wgt <= 0 then
      OutC := ReadPx(ASrc, EnsureRange(I0, 0, ASrcW - 1))
    else
    begin
      OutC.B := ClampChannel(AccB / Wgt);
      OutC.G := ClampChannel(AccG / Wgt);
      OutC.R := ClampChannel(AccR / Wgt);
      OutC.A := ClampChannel(AccA / Wgt);
    end;
    WritePx(ADst, X, OutC);
  end;
end;

procedure BoxAverageCol(const ASrc: TBitmapData; ASrcH, ADstW: Integer;
  const ADst: TBitmapData; ADstH: Integer);
var
  X, Y, I, I0, I1: Integer;
  Y0, Y1, Span, PixW, Wgt, AccB, AccG, AccR, AccA: Double;
  C, OutC: TAlphaColorRec;
  Rows: array of PByte;
  DstRow: PByte;
begin
  if (ADstH < 1) or (ADstW < 1) or (ASrcH < 1) then
    Exit;
  SetLength(Rows, ASrcH);
  for I := 0 to ASrcH - 1 do
    Rows[I] := PByte(ASrc.GetScanline(I));
  Span := ASrcH / ADstH;
  for Y := 0 to ADstH - 1 do
  begin
    Y0 := Y * Span;
    Y1 := Y0 + Span;
    if Y1 > ASrcH then
      Y1 := ASrcH;
    I0 := Floor(Y0);
    I1 := Ceil(Y1) - 1;
    if I0 < 0 then
      I0 := 0;
    if I1 >= ASrcH then
      I1 := ASrcH - 1;
    DstRow := PByte(ADst.GetScanline(Y));
    for X := 0 to ADstW - 1 do
    begin
      AccB := 0;
      AccG := 0;
      AccR := 0;
      AccA := 0;
      Wgt := 0;
      for I := I0 to I1 do
      begin
        PixW := Min(I + 1.0, Y1) - Max(Double(I), Y0);
        if PixW <= 0 then
          Continue;
        C := ReadPx(Rows[I], X);
        AccB := AccB + C.B * PixW;
        AccG := AccG + C.G * PixW;
        AccR := AccR + C.R * PixW;
        AccA := AccA + C.A * PixW;
        Wgt := Wgt + PixW;
      end;
      if Wgt <= 0 then
        OutC := ReadPx(Rows[EnsureRange(I0, 0, ASrcH - 1)], X)
      else
      begin
        OutC.B := ClampChannel(AccB / Wgt);
        OutC.G := ClampChannel(AccG / Wgt);
        OutC.R := ClampChannel(AccR / Wgt);
        OutC.A := ClampChannel(AccA / Wgt);
      end;
      WritePx(DstRow, X, OutC);
    end;
  end;
end;

function BoxScale(ASrc: TBitmap; ANw, ANh: Integer): TBitmap;
var
  SW, SH, X, Y, SX: Integer;
  SrcData, DstData, TmpData: TBitmapData;
  Temp: TBitmap;
  S0, S1, Dst: PByte;
  C00, C01, C10, C11, OutC: TAlphaColorRec;
  MappedSrc, MappedDst, MappedTmp: Boolean;
begin
  Result := nil;
  if (ASrc = nil) or (ANw < 1) or (ANh < 1) or
     (ANw > ASrc.Width) or (ANh > ASrc.Height) then
    Exit;
  SW := ASrc.Width;
  SH := ASrc.Height;
  Result := TBitmap.Create(ANw, ANh);
  Temp := nil;
  MappedDst := False;
  MappedTmp := False;
  if not ASrc.Map(TMapAccess.Read, SrcData) then
  begin
    Result.Free;
    Exit(nil);
  end;
  MappedSrc := True;
  try
    if not Result.Map(TMapAccess.Write, DstData) then
    begin
      Result.Free;
      Exit(nil);
    end;
    MappedDst := True;
    if (ANw * 2 = SW) and (ANh * 2 = SH) then
    begin
      for Y := 0 to ANh - 1 do
      begin
        S0 := PByte(SrcData.GetScanline(Y * 2));
        S1 := PByte(SrcData.GetScanline(Y * 2 + 1));
        Dst := PByte(DstData.GetScanline(Y));
        for X := 0 to ANw - 1 do
        begin
          SX := X * 2;
          C00 := ReadPx(S0, SX);
          C01 := ReadPx(S0, SX + 1);
          C10 := ReadPx(S1, SX);
          C11 := ReadPx(S1, SX + 1);
          OutC.B := (C00.B + C01.B + C10.B + C11.B + 2) div 4;
          OutC.G := (C00.G + C01.G + C10.G + C11.G + 2) div 4;
          OutC.R := (C00.R + C01.R + C10.R + C11.R + 2) div 4;
          OutC.A := (C00.A + C01.A + C10.A + C11.A + 2) div 4;
          WritePx(Dst, X, OutC);
        end;
      end;
    end
    else if ANh = SH then
    begin
      for Y := 0 to SH - 1 do
        BoxAverageRow(PByte(SrcData.GetScanline(Y)), SW,
          PByte(DstData.GetScanline(Y)), ANw);
    end
    else
    begin
      Temp := TBitmap.Create(ANw, SH);
      if not Temp.Map(TMapAccess.Write, TmpData) then
      begin
        Result.Unmap(DstData);
        MappedDst := False;
        Result.Free;
        Exit(nil);
      end;
      MappedTmp := True;
      for Y := 0 to SH - 1 do
        BoxAverageRow(PByte(SrcData.GetScanline(Y)), SW,
          PByte(TmpData.GetScanline(Y)), ANw);
      Temp.Unmap(TmpData);
      MappedTmp := False;
      ASrc.Unmap(SrcData);
      MappedSrc := False;
      if not Temp.Map(TMapAccess.Read, TmpData) then
      begin
        Result.Unmap(DstData);
        MappedDst := False;
        Result.Free;
        Exit(nil);
      end;
      MappedTmp := True;
      BoxAverageCol(TmpData, SH, ANw, DstData, ANh);
    end;
  finally
    if MappedTmp and (Temp <> nil) then
      Temp.Unmap(TmpData);
    Temp.Free;
    if MappedDst and (Result <> nil) then
      Result.Unmap(DstData);
    if MappedSrc then
      ASrc.Unmap(SrcData);
  end;
end;

function DrawResample(const ASrc: ISkImage; ANw, ANh: Integer;
  const ASampling: TSkSamplingOptions): TBitmap;
var
  Dest: TBitmap;
  Src: ISkImage;
  Nw, Nh: Integer;
  Sampling: TSkSamplingOptions;
begin
  Nw := ANw;
  Nh := ANh;
  Sampling := ASampling;
  Src := ASrc;
  Dest := TBitmap.Create(Nw, Nh);
  Dest.SkiaDraw(
    procedure(const C: ISkCanvas)
    begin
      C.DrawImageRect(Src, TRectF.Create(0, 0, Nw, Nh), Sampling);
    end);
  Result := Dest;
end;

function ResampleBitmap(ASrc: TBitmap; ANw, ANh: Integer): TBitmap;
var
  Cur, Next: TBitmap;
  SW, SH: Integer;
  Img: ISkImage;
  Sampling: TSkSamplingOptions;
  Owned: Boolean;
begin
  Result := nil;
  if (ASrc = nil) or (ASrc.Width < 1) or (ASrc.Height < 1) then
    Exit;
  ANw := EnsureRange(ANw, 1, 16000);
  ANh := EnsureRange(ANh, 1, 16000);
  if (ANw = ASrc.Width) and (ANh = ASrc.Height) then
  begin
    Result := TBitmap.Create;
    Result.Assign(ASrc);
    Exit;
  end;
  Cur := ASrc;
  Owned := False;
  try
    while (Cur.Width > ANw * 2) or (Cur.Height > ANh * 2) do
    begin
      SW := Cur.Width;
      SH := Cur.Height;
      if SW > ANw * 2 then
        SW := Max(ANw, SW div 2);
      if SH > ANh * 2 then
        SH := Max(ANh, SH div 2);
      if (SW = Cur.Width) and (SH = Cur.Height) then
        Break;
      Next := BoxScale(Cur, SW, SH);
      if Next = nil then
        Break;
      if Owned then
        Cur.Free;
      Cur := Next;
      Owned := True;
      if (Cur.Width = ANw) and (Cur.Height = ANh) then
      begin
        Result := Cur;
        Owned := False;
        Exit;
      end;
    end;
    Img := Cur.ToSkImage;
    if Img = nil then
    begin
      Result := TBitmap.Create;
      Result.Assign(Cur);
      Exit;
    end;
    if (Cur.Width <= ANw) and (Cur.Height <= ANh) then
      Sampling := TSkSamplingOptions.Create(TSkCubicResampler.CatmullRom)
    else
      Sampling := TSkSamplingOptions.High;
    Result := DrawResample(Img, ANw, ANh, Sampling);
    Img := nil;
  finally
    if Owned then
      Cur.Free;
  end;
end;

function ApplyImgOp(ASrc: TBitmap; const AOp: TImgOp): TBitmap;
var
  Deg, Nw, Nh: Integer;
  Sx, Sy, L, T, R, B: Single;
  SrcImg: ISkImage;
  Dest: TBitmap;
begin
  Result := nil;
  if (ASrc = nil) or (ASrc.Width < 1) or (ASrc.Height < 1) then
    Exit;
  SrcImg := ASrc.ToSkImage;
  if SrcImg = nil then
    Exit;
  case AOp.Kind of
    iopRot:
      begin
        Deg := NormDeg(AOp.Deg);
        if Deg = 0 then
          Exit;
        if Deg = 180 then
          Dest := TBitmap.Create(ASrc.Width, ASrc.Height)
        else
          Dest := TBitmap.Create(ASrc.Height, ASrc.Width);
        Result := Dest;
        Dest.SkiaDraw(
          procedure(const C: ISkCanvas)
          begin
            case Deg of
              90:
                begin
                  C.Translate(Dest.Width, 0);
                  C.Rotate(90);
                end;
              180:
                begin
                  C.Translate(Dest.Width, Dest.Height);
                  C.Rotate(180);
                end;
            else
              begin
                C.Translate(0, Dest.Height);
                C.Rotate(-90);
              end;
            end;
            C.DrawImage(SrcImg, 0, 0);
          end);
      end;
    iopFlipH, iopFlipV:
      begin
        Dest := TBitmap.Create(ASrc.Width, ASrc.Height);
        Result := Dest;
        Dest.SkiaDraw(
          procedure(const C: ISkCanvas)
          begin
            if AOp.Kind = iopFlipV then
            begin
              C.Translate(0, Dest.Height);
              C.Scale(1, -1);
            end
            else
            begin
              C.Translate(Dest.Width, 0);
              C.Scale(-1, 1);
            end;
            C.DrawImage(SrcImg, 0, 0);
          end);
      end;
    iopSize:
      Result := ResampleBitmap(ASrc, AOp.W, AOp.H);
    iopCrop:
      begin
        L := EnsureRange(AOp.Crop.Left, 0, 1) * ASrc.Width;
        T := EnsureRange(AOp.Crop.Top, 0, 1) * ASrc.Height;
        R := EnsureRange(AOp.Crop.Right, 0, 1) * ASrc.Width;
        B := EnsureRange(AOp.Crop.Bottom, 0, 1) * ASrc.Height;
        if R < L then
        begin
          Sx := L;
          L := R;
          R := Sx;
        end;
        if B < T then
        begin
          Sy := T;
          T := B;
          B := Sy;
        end;
        Nw := Max(1, Round(R - L));
        Nh := Max(1, Round(B - T));
        Result := TBitmap.Create(Nw, Nh);
        Result.SkiaDraw(
          procedure(const C: ISkCanvas)
          begin
            C.Translate(-L, -T);
            C.DrawImage(SrcImg, 0, 0);
          end);
      end;
  end;
end;

function RenderOps(ASrc: TBitmap; const AOps: TArray<TImgOp>): TBitmap;
var
  I: Integer;
  Next: TBitmap;
begin
  Result := TBitmap.Create;
  if (ASrc = nil) or (ASrc.Width < 1) then
    Exit;
  Result.Assign(ASrc);
  for I := 0 to High(AOps) do
  begin
    Next := ApplyImgOp(Result, AOps[I]);
    if Next = nil then
      Continue;
    Result.Free;
    Result := Next;
  end;
end;

procedure TImgBuildJob.Execute;
begin
  try
    Bmp := RenderOps(Src, Ops);
  except
    Bmp := nil;
  end;
  FreeAndNil(Src);
  Finish;
end;

procedure TImgBuildJob.Finish;
begin
  TThread.Queue(nil, Apply);
end;

procedure TImgBuildJob.Apply;
var
  P: TFilePreview;
  Built: TBitmap;
begin
  P := Preview;
  Built := Bmp;
  Bmp := nil;
  if P = nil then
  begin
    FreeAndNil(Built);
    Free;
    Exit;
  end;
  if P.FBuildJob = Self then
    P.FBuildJob := nil;
  P.AcceptBuilt(Built, Gen);
  Free;
end;

procedure TFilePreview.AcceptBuilt(ABmp: TBitmap; AGen: Integer);
begin
  if FDestroying or (AGen <> FBuildGen) then
  begin
    FreeAndNil(ABmp);
    Exit;
  end;
  FImgBuilding := False;
  if (ABmp <> nil) and (ABmp.Width > 0) then
  begin
    FImage.Bitmap.Assign(ABmp);
    FImage.Visible := True;
    if Assigned(FSvgBox) then
      FSvgBox.Visible := False;
    if Assigned(FAnim) then
    begin
      try
        if Assigned(FAnim.Animation) then
          FAnim.Animation.Enabled := False;
      except
      end;
      FAnim.Visible := False;
    end;
    FViewW := FImage.Bitmap.Width;
    FViewH := FImage.Bitmap.Height;
    SetHeaderPixels(FViewW, FViewH);
    if Assigned(FImgHost) then
      FImgHost.Visible := True;
  end;
  FreeAndNil(ABmp);
  SyncEditButtons;
  ApplyImgView;
  LayoutImageFooter(nil);
end;

procedure TFilePreview.MeasureSvgFrame;
var
  Intr: TSizeF;
  VB: TRectF;
begin
  FImgKind := ivSvg;
  Intr := TSizeF.Create(512, 512);
  if Assigned(FSvgDom) and Assigned(FSvgDom.Root) then
  begin
    Intr := FSvgDom.Root.GetIntrinsicSize(TSizeF.Create(512, 512));
    if (Intr.Width < 1) or (Intr.Height < 1) then
    begin
      if FSvgDom.Root.TryGetViewBox(VB) and (VB.Width > 1) and (VB.Height > 1) then
        Intr := TSizeF.Create(VB.Width, VB.Height)
      else
        Intr := TSizeF.Create(512, 512);
    end;
  end;
  FViewW := Max(1, Round(Intr.Width));
  FViewH := Max(1, Round(Intr.Height));
  FFrameW := FViewW;
  FFrameH := FViewH;
  FDocW := 0;
  FDocH := 0;
end;

procedure TFilePreview.SetHeaderPixels(AW, AH: Integer);
begin
  FFrameW := Max(0, AW);
  FFrameH := Max(0, AH);
  if Assigned(FPxText) then
    FPxText.Text := Format('%d × %d', [FFrameW, FFrameH]);
  if Assigned(FFrameNote) then
    FFrameNote.Visible := FImgChrome and FEditing and (FImgKind = ivAnim);
  LayoutImageHeader(nil);
end;

procedure TFilePreview.LayoutImageHeader(Sender: TObject);
var
  SizeW, NameRight, NameW: Single;
begin
  if not Assigned(FTitle) or not Assigned(FHeader) then
    Exit;
  if not FImgChrome then
  begin
    FTitle.Align := TAlignLayout.Client;
    FTitle.Margins.Rect := TRectF.Create(12, 0, 8, 0);
    if Assigned(FPxText) then
      FPxText.Visible := False;
    if Assigned(FFrameNote) then
      FFrameNote.Visible := False;
    if Assigned(FHeaderRule) then
      FHeaderRule.Visible := False;
    if Assigned(FKindText) then
      FKindText.Visible := True;
    Exit;
  end;
  FTitle.Align := TAlignLayout.None;
  FTitle.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  if Assigned(FKindText) then
    FKindText.Visible := False;
  if Assigned(FHeaderRule) then
  begin
    FHeaderRule.Visible := True;
    FHeaderRule.Align := TAlignLayout.None;
    FHeaderRule.SetBounds(0, FHeader.Height - 1, FHeader.Width, 1);
  end;
  if not Assigned(FPxText) then
    Exit;
  FPxText.Visible := True;
  if FPxText.Text = '' then
    FPxText.Text := Format('%d × %d', [FFrameW, FFrameH]);
  if Length(FPxText.Text) > 24 then
    SizeW := Max(84, Length(FPxText.Text) * 7.8 + 12)
  else
    SizeW := Max(84, Length(FPxText.Text) * 7.6);
  NameRight := 16;
  if Assigned(FBtnClose) and FBtnClose.Visible then
    NameRight := NameRight + FBtnClose.Width;
  if Assigned(FHtmlModeBar) and FHtmlModeBar.Visible then
    NameRight := NameRight + FHtmlModeBar.Width + 8;
  FPxText.SetBounds(FHeader.Width - NameRight - SizeW, 0, SizeW,
    Max(1, FHeader.Height - 1));
  NameRight := FPxText.Position.X - 12;
  if Assigned(FFrameNote) then
  begin
    FFrameNote.Visible := FEditing and (FImgKind = ivAnim);
    if FFrameNote.Visible then
    begin
      FFrameNote.SetBounds(FPxText.Position.X - 46, 0, 42, Max(1, FHeader.Height - 1));
      NameRight := FFrameNote.Position.X - 8;
    end;
  end;
  NameW := NameRight - 16;
  if NameW < 24 then
    NameW := 24;
  FTitle.SetBounds(16, 0, NameW, Max(1, FHeader.Height - 1));
end;

function TFilePreview.ImageBounds: TRectF;
var
  Scale, Dw, Dh, L, T: Single;
begin
  if ViewMetrics(Scale, Dw, Dh, L, T) then
    Result := TRectF.Create(L, T, L + Dw, T + Dh)
  else
    Result := TRectF.Create(0, 0, 0, 0);
end;

procedure TFilePreview.SyncEditButtons;
begin
  if Assigned(FBtnCrop) then
  begin
    FBtnCrop.Enabled := not FImgBuilding;
    FBtnCrop.SetSelected(FCropping);
  end;
  if Assigned(FBtnFlipH) then
    FBtnFlipH.Enabled := not FImgBuilding;
  if Assigned(FBtnFlipV) then
    FBtnFlipV.Enabled := not FImgBuilding;
  if Assigned(FBtnRotR) then
    FBtnRotR.Enabled := not FImgBuilding;
  if Assigned(FBtnSize) then
  begin
    FBtnSize.Enabled := not FImgBuilding;
    FBtnSize.SetSelected(Assigned(FSizeStrip) and FSizeStrip.Visible);
  end;
  if Assigned(FBtnReset) then
    FBtnReset.Enabled := not FImgBuilding;
  if Assigned(FBtnSave) then
    FBtnSave.Enabled := not FImgBuilding;
end;

procedure TFilePreview.LayoutImageFooter(Sender: TObject);
var
  Y, W, X, Total, SaveW, RightW: Single;
  I: Integer;
  Btns: array[0..5] of TFluentButton;
begin
  if FInFooterLayout or not Assigned(FFooterHost) or FDestroying then
    Exit;
  FInFooterLayout := True;
  try
    W := FFooterHost.Width;
    if W < 8 then
      W := 8;
    Y := 0;
    if Assigned(FSizeStrip) and FSizeStrip.Visible then
    begin
      FSizeStrip.SetBounds(0, Y, W, 44);
      X := 8;
      if Assigned(FSizeWLbl) then
      begin
        FSizeWLbl.SetBounds(X, 6, 62, 32);
        X := X + 68;
      end;
      if Assigned(FSizeW) then
      begin
        FSizeW.SetBounds(X, 6, 72, 32);
        X := X + 76;
      end;
      if Assigned(FSizeLock) then
      begin
        FSizeLock.SetBounds(X, 6, 32, 32);
        X := X + 42;
      end;
      if Assigned(FSizeHLbl) then
      begin
        FSizeHLbl.SetBounds(X, 6, 58, 32);
        X := X + 64;
      end;
      if Assigned(FSizeH) then
      begin
        FSizeH.SetBounds(X, 6, 72, 32);
        X := X + 82;
      end;
      if Assigned(FSizeCombo) then
        FSizeCombo.SetBounds(X, 6, 108, 32);
      if Assigned(FBtnSizeOk) then
        FBtnSizeOk.SetBounds(W - 8 - 36, 6, 36, 32);
      Y := Y + 44;
    end;
    if Assigned(FRatioStrip) and FRatioStrip.Visible then
    begin
      FRatioStrip.SetBounds(0, Y, W, 36);
      if Assigned(FBtnCropOk) then
        FBtnCropOk.SetBounds(W - 8 - 36, 2, 36, 32);
      X := 8;
      for I := 0 to High(FRatioBtns) do
        if Assigned(FRatioBtns[I]) then
        begin
          FRatioBtns[I].SetBounds(X, 2, FRatioBtns[I].Width, 32);
          X := X + FRatioBtns[I].Width + 6;
        end;
      Y := Y + 36;
    end;
    if Assigned(FEditWarn) and FEditWarn.Visible then
    begin
      FEditWarn.SetBounds(12, Y, W - 24, 20);
      Y := Y + 20;
    end;
    if Assigned(FViewBar) then
      FViewBar.SetBounds(0, Y, W, IMG_SHELF_H);
    if Assigned(FEditBar) then
      FEditBar.SetBounds(0, Y, W, IMG_SHELF_H);
    if Assigned(FViewRule) then
      FViewRule.SetBounds(0, 0, W, 1);
    if Assigned(FEditRule) then
      FEditRule.SetBounds(0, 0, W, 1);
    Total := 108 + 8 + 36 + 8 + 36;
    RightW := 0;
    if FHdrOn and Assigned(FHdrTrack) then
      RightW := 168 + 4 + 48 + 8;
    X := (W - RightW - Total) / 2;
    if X < 8 then
      X := 8;
    if RightW > 0 then
    begin
      if X + Total > W - RightW - 8 then
        X := Max(8, W - RightW - 8 - Total);
    end;
    if Assigned(FZoomCombo) then
      FZoomCombo.SetBounds(X, 4, 108, 32);
    if Assigned(FBtnFit) then
      FBtnFit.SetBounds(X + 116, 4, 36, 32);
    if Assigned(FBtnEdit) then
      FBtnEdit.SetBounds(X + 160, 4, 36, 32);
    if Assigned(FHdrTrack) then
    begin
      FHdrTrack.Visible := FHdrOn and Assigned(FViewBar) and FViewBar.Visible;
      if FHdrTrack.Visible then
        FHdrTrack.SetBounds(W - 12 - 48 - 168, 4, 168, 32);
    end;
    if Assigned(FHdrEv) then
    begin
      FHdrEv.Visible := FHdrOn and Assigned(FViewBar) and FViewBar.Visible;
      if FHdrEv.Visible then
        FHdrEv.SetBounds(W - 12 - 44, 4, 44, 32);
    end;
    SaveW := 128;
    if Assigned(FBtnSave) then
      FBtnSave.SetBounds(W - 12 - SaveW, 4, SaveW, 32);
    if Assigned(FEditScroll) then
      FEditScroll.SetBounds(8, 2, Max(40, W - 12 - SaveW - 8 - 8), IMG_SHELF_H - 4);
    Btns[0] := FBtnCrop;
    Btns[1] := FBtnFlipH;
    Btns[2] := FBtnFlipV;
    Btns[3] := FBtnRotR;
    Btns[4] := FBtnSize;
    Btns[5] := FBtnReset;
    X := 0;
    for I := 0 to 5 do
      if Assigned(Btns[I]) then
      begin
        Btns[I].SetBounds(X, 3, 36, 32);
        X := X + 44;
      end;
    if Assigned(FEditTools) then
      FEditTools.SetBounds(0, 0, Max(44, X), 48);
    if Assigned(FEditScrollBar) then
      FEditScrollBar.UpdateThumb;
    if Abs(FFooterHost.Height - (Y + IMG_SHELF_H)) > 0.5 then
      FFooterHost.Height := Y + IMG_SHELF_H;
  finally
    FInFooterLayout := False;
  end;
end;

procedure TFilePreview.ShowLiveSource;
begin
  if FImgKind = ivSvg then
  begin
    if Assigned(FImage) then
      FImage.Visible := False;
    if Assigned(FAnim) then
      FAnim.Visible := False;
    MeasureSvgFrame;
    if Assigned(FSvgBox) then
    begin
      FSvgBox.Visible := True;
      FSvgBox.BringToFront;
    end;
    if Assigned(FImgHost) then
      FImgHost.Visible := True;
    SetHeaderPixels(FFrameW, FFrameH);
  end
  else if (FImgKind = ivAnim) and Assigned(FAnim) then
  begin
    if Assigned(FImage) then
      FImage.Visible := False;
    if Assigned(FSvgBox) then
      FSvgBox.Visible := False;
    FAnim.Visible := True;
    FViewW := Max(1, Round(FAnim.OriginalSize.Width));
    FViewH := Max(1, Round(FAnim.OriginalSize.Height));
    try
      if Assigned(FAnim.Animation) then
      begin
        FAnim.Animation.Enabled := True;
        FAnim.Animation.Start;
      end;
    except
    end;
    SetHeaderPixels(FViewW, FViewH);
    if Assigned(FImgHost) then
      FImgHost.Visible := True;
  end
  else if Assigned(FImgOriginal) and (FImgOriginal.Width > 0) and Assigned(FImage) then
  begin
    FImage.Bitmap.Assign(FImgOriginal);
    FImage.Visible := True;
    if Assigned(FSvgBox) then
      FSvgBox.Visible := False;
    if Assigned(FAnim) then
      FAnim.Visible := False;
    FViewW := FImage.Bitmap.Width;
    FViewH := FImage.Bitmap.Height;
    if (FImgKind = ivPsd) and (FDocW > 0) and (FDocH > 0) then
      SetHeaderPixels(FDocW, FDocH)
    else
      SetHeaderPixels(FViewW, FViewH);
    ShowRasterImage(False);
  end;
  ApplyImgView;
end;

procedure TFilePreview.ResetEditState;
begin
  if FBuildJob <> nil then
  begin
    TImgBuildJob(FBuildJob).Preview := nil;
    FBuildJob := nil;
  end;
  Inc(FBuildGen);
  FImgBuilding := False;
  SetLength(FImgOps, 0);
  FreeAndNil(FImgOriginal);
  FImgDirty := False;
  FEditing := False;
  FEditWarnOn := False;
  FCropping := False;
  FCropDragId := -1;
  if Assigned(FCropPaint) then
    FCropPaint.Visible := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  if Assigned(FRatioStrip) then
    FRatioStrip.Visible := False;
  CloseSaveCard;
  if FImgChrome and Assigned(FViewBar) then
  begin
    FViewBar.Visible := True;
    if Assigned(FEditBar) then
      FEditBar.Visible := False;
    LayoutImageFooter(nil);
  end;
end;

procedure TFilePreview.AdoptRasterView;
begin
  if not Assigned(FImage) or (FImage.Bitmap.Width < 1) or (FImage.Bitmap.Height < 1) then
    Exit;
  FImgKind := ivRaster;
  FViewW := FImage.Bitmap.Width;
  FViewH := FImage.Bitmap.Height;
  FFrameW := FViewW;
  FFrameH := FViewH;
  ShowImageTools(True);
end;

procedure TFilePreview.ShowImageTools(AShow: Boolean);
begin
  if not AShow then
  begin
    FImgChrome := False;
    FEditing := False;
    if Assigned(FFooterHost) then
      FFooterHost.Visible := False;
    if Assigned(FMeta) then
      FMeta.Visible := True;
    ResetEditState;
    LayoutImageHeader(nil);
    Exit;
  end;
  FImgChrome := True;
  if Assigned(FMeta) then
    FMeta.Visible := False;
  if Assigned(FFooterHost) then
  begin
    FFooterHost.Visible := True;
    FFooterHost.BringToFront;
  end;
  if Assigned(FViewBar) then
    FViewBar.Visible := True;
  if Assigned(FEditBar) then
    FEditBar.Visible := False;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  if Assigned(FRatioStrip) then
    FRatioStrip.Visible := False;
  SetHeaderPixels(FFrameW, FFrameH);
  LayoutImageFooter(nil);
  ApplyImgView;
end;

procedure TFilePreview.KickRebuild;
var
  Job: TImgBuildJob;
begin
  if Length(FImgOps) = 0 then
  begin
    FImgBuilding := False;
    ShowLiveSource;
    SyncEditButtons;
    Exit;
  end;
  if not Assigned(FImgOriginal) or (FImgOriginal.Width < 1) then
    Exit;
  if FBuildJob <> nil then
    TImgBuildJob(FBuildJob).Preview := nil;
  Inc(FBuildGen);
  Job := TImgBuildJob.Create;
  Job.Preview := Self;
  Job.Gen := FBuildGen;
  Job.Src := TBitmap.Create;
  Job.Src.Assign(FImgOriginal);
  Job.Ops := Copy(FImgOps);
  FBuildJob := Job;
  FImgBuilding := True;
  SyncEditButtons;
  TThread.CreateAnonymousThread(
    procedure
    begin
      Job.Execute;
    end).Start;
end;

function GrabStill(const APath: string; AAnim: TSkAnimatedImage): TBitmap;
var
  Player: ISkAnimationCodecPlayer;
  Img: ISkImage;
  Tmp: TBitmap;
  Ms: Cardinal;
  Ext: string;
  Progress: Double;
begin
  Result := nil;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext = '.tgs') or (Ext = '.lottie') or (Ext = '.json') then
  begin
    Progress := 0;
    if Assigned(AAnim) and Assigned(AAnim.Animation) and
       (AAnim.Animation.Duration > 0) then
      Progress := AAnim.Animation.Progress;
    Result := RenderLottieStill(APath, Progress);
    if Result <> nil then
      Exit;
  end;
  Player := TSkAnimationCodecPlayer.MakeFromFile(APath);
  if Player <> nil then
  begin
    Ms := 0;
    if Assigned(AAnim) and Assigned(AAnim.Animation) and (AAnim.Animation.Duration > 0) then
      Ms := Round(AAnim.Animation.Progress * AAnim.Animation.Duration * 1000);
    Player.Seek(Ms);
    Img := Player.Frame;
    if Img <> nil then
    begin
      Tmp := TBitmap.CreateFromSkImage(Img);
      try
        Result := TBitmap.Create;
        Result.Assign(Tmp);
      finally
        Tmp.Free;
      end;
      if Result.Width > 0 then
        Exit;
      FreeAndNil(Result);
    end;
  end;
  Img := TSkImage.MakeFromEncodedFile(APath);
  if Img = nil then
    Exit;
  Tmp := TBitmap.CreateFromSkImage(Img);
  try
    Result := TBitmap.Create;
    Result.Assign(Tmp);
  finally
    Tmp.Free;
  end;
end;

function TFilePreview.EnsureOriginal: Boolean;
var
  W, H, SW, SH: Integer;
  Full: TBitmap;
begin
  Result := Assigned(FImgOriginal) and (FImgOriginal.Width > 0);
  if Result then
    Exit;
  if FImgOriginal = nil then
    FImgOriginal := TBitmap.Create;
  if FImgKind = ivSvg then
  begin
    if not Assigned(FSvgDom) then
      Exit(False);
    if (FViewW < 1) or (FViewH < 1) then
      MeasureSvgFrame;
    W := FViewW;
    H := FViewH;
    if (W < 512) or (H < 512) then
    begin
      W := W * 2;
      H := H * 2;
    end;
    Full := TBitmap.Create(Max(1, W), Max(1, H));
    try
      Full.SkiaDraw(
        procedure(const C: ISkCanvas)
        begin
          FSvgDom.SetContainerSize(TSizeF.Create(FViewW, FViewH));
          C.Scale(Full.Width / FViewW, Full.Height / FViewH);
          FSvgDom.Render(C);
        end);
      FImgOriginal.Assign(Full);
    finally
      Full.Free;
    end;
  end
  else if FImgKind = ivAnim then
  begin
    Full := GrabStill(FPath, FAnim);
    if Full = nil then
      Exit(False);
    try
      FImgOriginal.Assign(Full);
    finally
      Full.Free;
    end;
  end
  else if (FImgKind = ivPsd) and Assigned(FImage) and
     (((FDocW > FImage.Bitmap.Width) or (FDocH > FImage.Bitmap.Height))) then
  begin
    Full := TBitmap.Create;
    try
      if LoadPsdPreview(FPath, 0, 0, Full, SW, SH) and (Full.Width > 0) then
        FImgOriginal.Assign(Full)
      else if FImage.Bitmap.Width > 0 then
        FImgOriginal.Assign(FImage.Bitmap)
      else
        Exit(False);
    finally
      Full.Free;
    end;
  end
  else if Assigned(FImage) and (FImage.Bitmap.Width > 0) then
    FImgOriginal.Assign(FImage.Bitmap)
  else
    Exit(False);
  Result := FImgOriginal.Width > 0;
end;

procedure TFilePreview.PushRot(AClockwise: Boolean);
var
  N, D: Integer;
begin
  if FImgBuilding or not FEditing then
    Exit;
  if not EnsureOriginal then
    Exit;
  if AClockwise then
    D := 90
  else
    D := -90;
  N := Length(FImgOps);
  if (N > 0) and (FImgOps[N - 1].Kind = iopRot) then
  begin
    FImgOps[N - 1].Deg := NormDeg(FImgOps[N - 1].Deg + D);
    if FImgOps[N - 1].Deg = 0 then
      SetLength(FImgOps, N - 1);
  end
  else
  begin
    SetLength(FImgOps, N + 1);
    FImgOps[N].Kind := iopRot;
    FImgOps[N].Deg := NormDeg(D);
  end;
  MarkImgDirty;
  FEditWarnOn := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  KickRebuild;
end;

procedure TFilePreview.PushFlip(AVertical: Boolean);
var
  N: Integer;
  Kind: TImgOpKind;
begin
  if FImgBuilding or not FEditing then
    Exit;
  if not EnsureOriginal then
    Exit;
  if AVertical then
    Kind := iopFlipV
  else
    Kind := iopFlipH;
  N := Length(FImgOps);
  if (N > 0) and (FImgOps[N - 1].Kind = Kind) then
    SetLength(FImgOps, N - 1)
  else
  begin
    SetLength(FImgOps, N + 1);
    FImgOps[N].Kind := Kind;
  end;
  MarkImgDirty;
  FEditWarnOn := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  KickRebuild;
end;

procedure TFilePreview.PushSize(AW, AH: Integer);
var
  Idx: Integer;
begin
  if FImgBuilding or not FEditing then
    Exit;
  if not EnsureOriginal then
    Exit;
  if (AW < 1) or (AH < 1) or (AW > 16000) or (AH > 16000) then
    Exit;
  Idx := Length(FImgOps);
  if (Idx > 0) and (FImgOps[Idx - 1].Kind = iopSize) then
    Idx := Idx - 1
  else
  begin
    if Assigned(FImgOriginal) and (Length(FImgOps) = 0) then
    begin
      FSizeBaseW := FImgOriginal.Width;
      FSizeBaseH := FImgOriginal.Height;
    end
    else if Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0) then
    begin
      FSizeBaseW := FImage.Bitmap.Width;
      FSizeBaseH := FImage.Bitmap.Height;
    end
    else
    begin
      FSizeBaseW := Max(1, FViewW);
      FSizeBaseH := Max(1, FViewH);
    end;
    SetLength(FImgOps, Idx + 1);
  end;
  FImgOps[Idx].Kind := iopSize;
  FImgOps[Idx].W := AW;
  FImgOps[Idx].H := AH;
  MarkImgDirty;
  FEditWarnOn := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  LayoutImageFooter(nil);
  KickRebuild;
end;

procedure TFilePreview.PushCrop(const ANorm: TRectF);
var
  N: Integer;
begin
  if FImgBuilding or not FEditing then
    Exit;
  if not EnsureOriginal then
    Exit;
  if (ANorm.Width < 0.002) or (ANorm.Height < 0.002) then
    Exit;
  N := Length(FImgOps);
  SetLength(FImgOps, N + 1);
  FImgOps[N].Kind := iopCrop;
  FImgOps[N].Crop := ANorm;
  MarkImgDirty;
  FEditWarnOn := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  KickRebuild;
end;

procedure TFilePreview.ImgRotate(AClockwise: Boolean);
begin
  PushRot(AClockwise);
end;

procedure TFilePreview.ImgRotRClick(Sender: TObject);
begin
  PushRot(True);
end;

procedure TFilePreview.ImgFlipClick(Sender: TObject);
begin
  PushFlip((Sender is TControl) and (TControl(Sender).Tag = 1));
end;

procedure TFilePreview.SetFitMode;
begin
  FViewFit := True;
  FImgPan := TPointF.Zero;
  ApplyImgView;
end;

procedure TFilePreview.SetViewScale(AScale: Single; AKeepPan: Boolean);
begin
  FViewFit := False;
  FViewScale := EnsureRange(AScale, 0.10, 8);
  if not AKeepPan then
    FImgPan := TPointF.Zero;
  ApplyImgView;
end;

procedure TFilePreview.ImgFitClick(Sender: TObject);
begin
  if FViewFit then
    SetViewScale(1, False)
  else
    SetFitMode;
end;

procedure TFilePreview.ImgDblClick(Sender: TObject);
var
  Cam: TMeshCamera;
begin
  if FMeshOn and not FMeshPicture then
  begin
    Cam := MeshHomeCamera;
    FMeshAz := Cam.Azimuth;
    FMeshEl := Cam.Elevation;
    FMeshScale := Cam.Scale;
    ScheduleMeshFrame;
    Exit;
  end;
  if FCropping then
  begin
    ApplyCrop;
    Exit;
  end;
  if Assigned(FSizeStrip) and FSizeStrip.Visible then
  begin
    SizeSubmit(nil);
    Exit;
  end;
  if FViewFit then
    SetViewScale(1, False)
  else
    SetFitMode;
end;

procedure TFilePreview.ImgZoomSelect(Sender: TObject);
var
  S: string;
  N: Integer;
begin
  if not Assigned(FZoomCombo) then
    Exit;
  S := Trim(FZoomCombo.Text);
  if S = '' then
    Exit;
  S := StringReplace(S, '%', '', [rfReplaceAll]);
  N := StrToIntDef(Trim(S), 0);
  if (N < 10) or (N > 800) then
    Exit;
  SetViewScale(N / 100, False);
end;

procedure TFilePreview.ImgZoomSubmit(Sender: TObject);
begin
  ImgZoomSelect(Sender);
end;

procedure TFilePreview.ImgEditClick(Sender: TObject);
begin
  if FEditing or not FImgChrome then
    Exit;
  if not EnsureOriginal then
  begin
    ShowToast(L('qv.toast.noframe'));
    Exit;
  end;
  FEditing := True;
  FEditWarnOn := False;
  if Assigned(FViewBar) then
    FViewBar.Visible := False;
  if Assigned(FEditBar) then
    FEditBar.Visible := True;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  CancelCrop;
  SetHeaderPixels(FFrameW, FFrameH);
  SyncEditButtons;
  LayoutImageFooter(nil);
  if CanFocus then
    SetFocus;
end;

procedure TFilePreview.LeaveEdit(ADiscard: Boolean);
begin
  CancelCrop;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  CloseSaveCard;
  if ADiscard or (Length(FImgOps) = 0) then
  begin
    SetLength(FImgOps, 0);
    FImgDirty := False;
    ShowLiveSource;
  end;
  FEditing := False;
  FEditWarnOn := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  if Assigned(FEditBar) then
    FEditBar.Visible := False;
  if Assigned(FViewBar) then
    FViewBar.Visible := True;
  SetHeaderPixels(FFrameW, FFrameH);
  if (FPdfPages > 0) and (FPdfPrintW > 0) and (Length(FImgOps) = 0) and not FImgDirty then
    ApplyPdfSizeText;
  if ((FMetaPrintW > 0) or (FMetaScreenW > 0)) and (Length(FImgOps) = 0) and
     not FImgDirty then
    ApplyMetaSizeText;
  LayoutImageFooter(nil);
end;

procedure TFilePreview.ImgResetClick(Sender: TObject);
begin
  if not FEditing or FImgBuilding then
    Exit;
  SetLength(FImgOps, 0);
  FImgDirty := False;
  FEditWarnOn := False;
  if Assigned(FEditWarn) then
    FEditWarn.Visible := False;
  CancelCrop;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  ShowLiveSource;
  SyncEditButtons;
  LayoutImageFooter(nil);
end;

procedure TFilePreview.KeepDigits(AEdit: TFluentEdit; AMaxLen: Integer);
var
  S, D: string;
  I: Integer;
begin
  if (AEdit = nil) or FSizeGuard or FSaveSilence then
    Exit;
  S := AEdit.Text;
  D := '';
  for I := 1 to Length(S) do
    if CharInSet(S[I], ['0'..'9']) then
      D := D + S[I];
  if Length(D) > AMaxLen then
    SetLength(D, AMaxLen);
  if D <> S then
  begin
    FSizeGuard := True;
    AEdit.Text := D;
    FSizeGuard := False;
  end;
end;

procedure TFilePreview.SizeLockClick(Sender: TObject);
begin
  FSizeLocked := not FSizeLocked;
  if Assigned(FSizeLock) then
  begin
    FSizeLock.SetSelected(FSizeLocked);
    if FSizeLocked then
      FSizeLock.SetIcon(#$E71B)
    else
      FSizeLock.SetIcon(#$E785);
  end;
end;

procedure TFilePreview.SizeFieldChange(Sender: TObject);
var
  N, Other: Integer;
begin
  if Sender = FSizeW then
    KeepDigits(FSizeW, 5)
  else if Sender = FSizeH then
    KeepDigits(FSizeH, 5);
  if FSizeGuard or not FSizeLocked then
    Exit;
  if (FSizeBaseW < 1) or (FSizeBaseH < 1) then
    Exit;
  FSizeGuard := True;
  try
    if Sender = FSizeW then
    begin
      N := StrToIntDef(FSizeW.Text, 0);
      if N > 0 then
      begin
        Other := Max(1, Round(N * FSizeBaseH / FSizeBaseW));
        FSizeH.Text := IntToStr(Other);
      end;
    end
    else if Sender = FSizeH then
    begin
      N := StrToIntDef(FSizeH.Text, 0);
      if N > 0 then
      begin
        Other := Max(1, Round(N * FSizeBaseW / FSizeBaseH));
        FSizeW.Text := IntToStr(Other);
      end;
    end;
  finally
    FSizeGuard := False;
  end;
  SyncSizePct;
end;

procedure TFilePreview.SyncSizePct;
var
  N: Integer;
  Cap: string;
begin
  if FSizeGuard or not Assigned(FSizeCombo) or FSizeCombo.EditorFocused then
    Exit;
  if FSizeBaseW < 1 then
    Exit;
  N := StrToIntDef(Trim(FSizeW.Text), 0);
  if N < 1 then
    Exit;
  Cap := IntToStr(Max(1, Round(N * 100 / FSizeBaseW))) + '%';
  if FSizeCombo.Text = Cap then
    Exit;
  FSizeGuard := True;
  try
    FSizeCombo.Text := Cap;
  finally
    FSizeGuard := False;
  end;
end;

function TFilePreview.TryApplySizePercent: Boolean;
var
  S: string;
  N, W, H: Integer;
begin
  Result := False;
  if FSizeGuard or not Assigned(FSizeCombo) then
    Exit;
  if (FSizeBaseW < 1) or (FSizeBaseH < 1) then
    Exit;
  S := Trim(FSizeCombo.Text);
  if S = '' then
    Exit;
  S := StringReplace(S, '%', '', [rfReplaceAll]);
  N := StrToIntDef(Trim(S), 0);
  if (N < 10) or (N > 800) then
    Exit;
  W := Max(1, Round(FSizeBaseW * N / 100));
  H := Max(1, Round(FSizeBaseH * N / 100));
  FSizeGuard := True;
  try
    FSizeW.Text := IntToStr(W);
    FSizeH.Text := IntToStr(H);
    FSizeCombo.Text := IntToStr(N) + '%';
  finally
    FSizeGuard := False;
  end;
  Result := True;
end;

procedure TFilePreview.SizePctApply(Sender: TObject);
begin
  TryApplySizePercent;
end;

procedure TFilePreview.SizeComboSubmit(Sender: TObject);
begin
  if TryApplySizePercent then
    SizeSubmit(Sender);
end;

procedure TFilePreview.SizeSubmit(Sender: TObject);
var
  W, H: Integer;
begin
  W := StrToIntDef(Trim(FSizeW.Text), 0);
  H := StrToIntDef(Trim(FSizeH.Text), 0);
  if (W < 1) or (H < 1) then
    Exit;
  PushSize(W, H);
end;

procedure TFilePreview.SizeCancel(Sender: TObject);
begin
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  SyncEditButtons;
  LayoutImageFooter(nil);
end;

procedure TFilePreview.ImgResizeClick(Sender: TObject);
var
  CurW, CurH: Integer;
  Base: TPoint;

  function FrameAfter(ALast: Integer): TPoint;
  var
    I, W, H, TW, TH, Deg: Integer;
    C: TRectF;
  begin
    W := Max(1, FImgOriginal.Width);
    H := Max(1, FImgOriginal.Height);
    for I := 0 to ALast do
    begin
      case FImgOps[I].Kind of
        iopRot:
          begin
            Deg := NormDeg(FImgOps[I].Deg);
            if (Deg = 90) or (Deg = 270) then
            begin
              TW := W;
              W := H;
              H := TW;
            end;
          end;
        iopSize:
          begin
            W := Max(1, FImgOps[I].W);
            H := Max(1, FImgOps[I].H);
          end;
        iopCrop:
          begin
            C := FImgOps[I].Crop;
            TW := Max(1, Round(Abs(C.Width) * W));
            TH := Max(1, Round(Abs(C.Height) * H));
            W := TW;
            H := TH;
          end;
      end;
    end;
    Result := TPoint.Create(W, H);
  end;

begin
  if not FEditing or FImgBuilding then
    Exit;
  if Assigned(FSizeStrip) and FSizeStrip.Visible then
  begin
    SizeCancel(nil);
    Exit;
  end;
  CancelCrop;
  if not EnsureOriginal then
    Exit;
  if (Length(FImgOps) > 0) and (FImgOps[High(FImgOps)].Kind = iopSize) then
  begin
    Base := FrameAfter(High(FImgOps) - 1);
    CurW := Max(1, FImgOps[High(FImgOps)].W);
    CurH := Max(1, FImgOps[High(FImgOps)].H);
  end
  else
  begin
    Base := FrameAfter(High(FImgOps));
    CurW := Base.X;
    CurH := Base.Y;
  end;
  FSizeBaseW := Max(1, Base.X);
  FSizeBaseH := Max(1, Base.Y);
  if FSizeBaseW < 1 then
    FSizeBaseW := CurW;
  if FSizeBaseH < 1 then
    FSizeBaseH := CurH;
  FSizeLocked := True;
  if Assigned(FSizeLock) then
  begin
    FSizeLock.SetSelected(True);
    FSizeLock.SetIcon(#$E71B);
  end;
  FSizeGuard := True;
  try
    FSizeW.Text := IntToStr(CurW);
    FSizeH.Text := IntToStr(CurH);
    if Assigned(FSizeCombo) and (FSizeBaseW > 0) then
      FSizeCombo.Text := IntToStr(Max(1, Round(CurW * 100 / FSizeBaseW))) + '%';
  finally
    FSizeGuard := False;
  end;
  FSizeStrip.Visible := True;
  SyncEditButtons;
  LayoutImageFooter(nil);
end;

function TFilePreview.CropAspect: Single;
begin
  case FCropRatio of
    1: Result := 9 / 16;
    2: Result := 2 / 3;
    3: Result := 3 / 4;
    4: Result := 1;
    5: Result := 4 / 3;
    6: Result := 3 / 2;
    7: Result := 16 / 9;
    8:
      if (FViewW > 0) and (FViewH > 0) then
        Result := FViewW / FViewH
      else if (FFrameW > 0) and (FFrameH > 0) then
        Result := FFrameW / FFrameH
      else
        Result := 0;
  else
    Result := 0;
  end;
end;

procedure TFilePreview.ApplyCropRatio;
var
  Aspect, FrameAspect, Target, W, H: Single;
begin
  Aspect := CropAspect;
  if Aspect <= 0 then
    Exit;
  FrameAspect := FViewW / Max(1, FViewH);
  if FrameAspect <= 0 then
    FrameAspect := 1;
  Target := Aspect / FrameAspect;
  if Target >= 1 then
  begin
    W := 1;
    H := 1 / Target;
    if H > 1 then
    begin
      W := W * (1 / H);
      H := 1;
    end;
  end
  else
  begin
    H := 1;
    W := Target;
  end;
  W := EnsureRange(W, 0.02, 1);
  H := EnsureRange(H, 0.02, 1);
  FCropNorm := TRectF.Create((1 - W) / 2, (1 - H) / 2, (1 + W) / 2, (1 + H) / 2);
end;

procedure TFilePreview.CropApplyClick(Sender: TObject);
begin
  ApplyCrop;
end;

procedure TFilePreview.RatioClick(Sender: TObject);
var
  I: Integer;
begin
  if not (Sender is TControl) then
    Exit;
  if TControl(Sender).Tag = FCropRatio then
    FCropRatio := 0
  else
    FCropRatio := TControl(Sender).Tag;
  for I := 0 to High(FRatioBtns) do
    if Assigned(FRatioBtns[I]) then
      FRatioBtns[I].SetSelected(FRatioBtns[I].Tag = FCropRatio);
  ApplyCropRatio;
  if Assigned(FCropPaint) then
    FCropPaint.Repaint;
end;

procedure TFilePreview.CancelCrop;
begin
  FCropping := False;
  FCropDragId := -1;
  if Assigned(FRatioStrip) then
    FRatioStrip.Visible := False;
  if Assigned(FCropPaint) then
  begin
    FCropPaint.Visible := False;
    FCropPaint.Repaint;
  end;
  SyncEditButtons;
  LayoutImageFooter(nil);
end;

procedure TFilePreview.ApplyCrop;
begin
  if not FCropping then
    Exit;
  FCropNorm.Left := EnsureRange(Min(FCropNorm.Left, FCropNorm.Right), 0, 1);
  FCropNorm.Top := EnsureRange(Min(FCropNorm.Top, FCropNorm.Bottom), 0, 1);
  FCropNorm.Right := EnsureRange(Max(FCropNorm.Left, FCropNorm.Right), 0, 1);
  FCropNorm.Bottom := EnsureRange(Max(FCropNorm.Top, FCropNorm.Bottom), 0, 1);
  if (FCropNorm.Width < 0.01) or (FCropNorm.Height < 0.01) then
  begin
    CancelCrop;
    Exit;
  end;
  if (FCropNorm.Width > 0.995) and (FCropNorm.Height > 0.995) then
  begin
    CancelCrop;
    Exit;
  end;
  PushCrop(FCropNorm);
  CancelCrop;
end;

function TFilePreview.HitCropHandle(X, Y: Single): Integer;
var
  R: TRectF;
  Pts: array[1..8] of TPointF;
  I: Integer;
const
  Slop = 8;
begin
  Result := -1;
  R := ImageBounds;
  if R.Width < 2 then
    Exit;
  R := TRectF.Create(
    R.Left + FCropNorm.Left * R.Width,
    R.Top + FCropNorm.Top * R.Height,
    R.Left + FCropNorm.Right * R.Width,
    R.Top + FCropNorm.Bottom * R.Height);
  Pts[1] := TPointF.Create(R.Left, R.Top);
  Pts[2] := TPointF.Create((R.Left + R.Right) / 2, R.Top);
  Pts[3] := TPointF.Create(R.Right, R.Top);
  Pts[4] := TPointF.Create(R.Right, (R.Top + R.Bottom) / 2);
  Pts[5] := TPointF.Create(R.Right, R.Bottom);
  Pts[6] := TPointF.Create((R.Left + R.Right) / 2, R.Bottom);
  Pts[7] := TPointF.Create(R.Left, R.Bottom);
  Pts[8] := TPointF.Create(R.Left, (R.Top + R.Bottom) / 2);
  for I := 1 to 8 do
    if (Abs(X - Pts[I].X) <= Slop) and (Abs(Y - Pts[I].Y) <= Slop) then
      Exit(I);
  if R.Contains(TPointF.Create(X, Y)) then
    Result := 0;
end;

procedure TFilePreview.CropPaint(Sender: TObject; Canvas: TCanvas);
var
  Host, Img, Crop: TRectF;
  I: Integer;
  Pts: array[1..8] of TPointF;
  G: Single;
begin
  if not FCropping then
    Exit;
  Host := FCropPaint.LocalRect;
  Img := ImageBounds;
  if Img.Width < 2 then
    Exit;
  Crop := TRectF.Create(
    Img.Left + FCropNorm.Left * Img.Width,
    Img.Top + FCropNorm.Top * Img.Height,
    Img.Left + FCropNorm.Right * Img.Width,
    Img.Top + FCropNorm.Bottom * Img.Height);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $8C000000;
  Canvas.FillRect(TRectF.Create(Host.Left, Host.Top, Host.Right, Crop.Top), 0, 0, [], 1);
  Canvas.FillRect(TRectF.Create(Host.Left, Crop.Bottom, Host.Right, Host.Bottom), 0, 0, [], 1);
  Canvas.FillRect(TRectF.Create(Host.Left, Crop.Top, Crop.Left, Crop.Bottom), 0, 0, [], 1);
  Canvas.FillRect(TRectF.Create(Crop.Right, Crop.Top, Host.Right, Crop.Bottom), 0, 0, [], 1);
  if FCropGrid and (Crop.Width > 8) and (Crop.Height > 8) then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := $66FFFFFF;
    Canvas.Stroke.Thickness := 1;
    for I := 1 to 2 do
    begin
      G := Crop.Left + Crop.Width * I / 3;
      Canvas.DrawLine(TPointF.Create(G, Crop.Top), TPointF.Create(G, Crop.Bottom), 1);
      G := Crop.Top + Crop.Height * I / 3;
      Canvas.DrawLine(TPointF.Create(Crop.Left, G), TPointF.Create(Crop.Right, G), 1);
    end;
  end;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := FColors.SelectionColor;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(Crop, 0, 0, [], 1);
  Pts[1] := TPointF.Create(Crop.Left, Crop.Top);
  Pts[2] := TPointF.Create((Crop.Left + Crop.Right) / 2, Crop.Top);
  Pts[3] := TPointF.Create(Crop.Right, Crop.Top);
  Pts[4] := TPointF.Create(Crop.Right, (Crop.Top + Crop.Bottom) / 2);
  Pts[5] := TPointF.Create(Crop.Right, Crop.Bottom);
  Pts[6] := TPointF.Create((Crop.Left + Crop.Right) / 2, Crop.Bottom);
  Pts[7] := TPointF.Create(Crop.Left, Crop.Bottom);
  Pts[8] := TPointF.Create(Crop.Left, (Crop.Top + Crop.Bottom) / 2);
  Canvas.Fill.Color := FColors.SelectionColor;
  for I := 1 to 8 do
  begin
    G := 4;
    Canvas.FillRect(TRectF.Create(
      EnsureRange(Pts[I].X - G, Img.Left, Img.Right - G * 2),
      EnsureRange(Pts[I].Y - G, Img.Top, Img.Bottom - G * 2),
      EnsureRange(Pts[I].X - G, Img.Left, Img.Right - G * 2) + G * 2,
      EnsureRange(Pts[I].Y - G, Img.Top, Img.Bottom - G * 2) + G * 2),
      1, 1, AllCorners, 1);
  end;
end;

procedure TFilePreview.CropMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if not FCropping or (Button <> TMouseButton.mbLeft) then
    Exit;
  FCropDragId := HitCropHandle(X, Y);
  if FCropDragId < 0 then
    Exit;
  FCropLast := TPointF.Create(X, Y);
  if Assigned(FCropPaint.Root) then
    FCropPaint.Root.Captured := FCropPaint;
end;

procedure TFilePreview.CropMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  Img: TRectF;
  NX, NY, DW, DH, PixAspect, NormAspect: Single;

  procedure PlaceLocked;
  var
    L0, T0, R0, B0, W, H, CX, CY: Single;
  begin
    L0 := FCropNorm.Left;
    T0 := FCropNorm.Top;
    R0 := FCropNorm.Right;
    B0 := FCropNorm.Bottom;
    case FCropDragId of
      1:
        begin
          W := EnsureRange(R0 - NX, 0.02, R0);
          H := W / NormAspect;
          if B0 - H < 0 then
          begin
            H := EnsureRange(B0, 0.02, 1);
            W := Min(H * NormAspect, R0);
            H := W / NormAspect;
          end;
          FCropNorm := TRectF.Create(R0 - W, B0 - H, R0, B0);
        end;
      3:
        begin
          W := EnsureRange(NX - L0, 0.02, 1 - L0);
          H := W / NormAspect;
          if B0 - H < 0 then
          begin
            H := EnsureRange(B0, 0.02, 1);
            W := Min(H * NormAspect, 1 - L0);
            H := W / NormAspect;
          end;
          FCropNorm := TRectF.Create(L0, B0 - H, L0 + W, B0);
        end;
      5:
        begin
          W := EnsureRange(NX - L0, 0.02, 1 - L0);
          H := W / NormAspect;
          if T0 + H > 1 then
          begin
            H := EnsureRange(1 - T0, 0.02, 1);
            W := Min(H * NormAspect, 1 - L0);
            H := W / NormAspect;
          end;
          FCropNorm := TRectF.Create(L0, T0, L0 + W, T0 + H);
        end;
      7:
        begin
          W := EnsureRange(R0 - NX, 0.02, R0);
          H := W / NormAspect;
          if T0 + H > 1 then
          begin
            H := EnsureRange(1 - T0, 0.02, 1);
            W := Min(H * NormAspect, R0);
            H := W / NormAspect;
          end;
          FCropNorm := TRectF.Create(R0 - W, T0, R0, T0 + H);
        end;
      2:
        begin
          H := EnsureRange(B0 - NY, 0.02, B0);
          W := H * NormAspect;
          if W > 1 then
          begin
            W := 1;
            H := Min(W / NormAspect, B0);
            W := H * NormAspect;
          end;
          CX := (L0 + R0) / 2;
          CX := EnsureRange(CX, W / 2, 1 - W / 2);
          FCropNorm := TRectF.Create(CX - W / 2, B0 - H, CX + W / 2, B0);
        end;
      6:
        begin
          H := EnsureRange(NY - T0, 0.02, 1 - T0);
          W := H * NormAspect;
          if W > 1 then
          begin
            W := 1;
            H := Min(W / NormAspect, 1 - T0);
            W := H * NormAspect;
          end;
          CX := (L0 + R0) / 2;
          CX := EnsureRange(CX, W / 2, 1 - W / 2);
          FCropNorm := TRectF.Create(CX - W / 2, T0, CX + W / 2, T0 + H);
        end;
      8:
        begin
          W := EnsureRange(R0 - NX, 0.02, R0);
          H := W / NormAspect;
          if H > 1 then
          begin
            H := 1;
            W := Min(H * NormAspect, R0);
            H := W / NormAspect;
          end;
          CY := (T0 + B0) / 2;
          CY := EnsureRange(CY, H / 2, 1 - H / 2);
          FCropNorm := TRectF.Create(R0 - W, CY - H / 2, R0, CY + H / 2);
        end;
      4:
        begin
          W := EnsureRange(NX - L0, 0.02, 1 - L0);
          H := W / NormAspect;
          if H > 1 then
          begin
            H := 1;
            W := Min(H * NormAspect, 1 - L0);
            H := W / NormAspect;
          end;
          CY := (T0 + B0) / 2;
          CY := EnsureRange(CY, H / 2, 1 - H / 2);
          FCropNorm := TRectF.Create(L0, CY - H / 2, L0 + W, CY + H / 2);
        end;
    end;
  end;

begin
  if (FCropDragId < 0) or not FCropping then
    Exit;
  Img := ImageBounds;
  if Img.Width < 2 then
    Exit;
  NX := EnsureRange((X - Img.Left) / Img.Width, 0, 1);
  NY := EnsureRange((Y - Img.Top) / Img.Height, 0, 1);
  if FCropDragId = 0 then
  begin
    DW := FCropNorm.Width;
    DH := FCropNorm.Height;
    FCropNorm.Left := EnsureRange(FCropNorm.Left + (X - FCropLast.X) / Img.Width, 0, 1 - DW);
    FCropNorm.Top := EnsureRange(FCropNorm.Top + (Y - FCropLast.Y) / Img.Height, 0, 1 - DH);
    FCropNorm.Right := FCropNorm.Left + DW;
    FCropNorm.Bottom := FCropNorm.Top + DH;
  end
  else if FCropRatio <> 0 then
  begin
    PixAspect := CropAspect;
    if PixAspect < 0.001 then
      PixAspect := 1;
    NormAspect := PixAspect * Max(1, FViewH) / Max(1, FViewW);
    if NormAspect < 0.001 then
      NormAspect := 1;
    PlaceLocked;
  end
  else
  begin
    if FCropDragId in [1, 7, 8] then
      FCropNorm.Left := Min(NX, FCropNorm.Right - 0.02);
    if FCropDragId in [1, 2, 3] then
      FCropNorm.Top := Min(NY, FCropNorm.Bottom - 0.02);
    if FCropDragId in [3, 4, 5] then
      FCropNorm.Right := Max(NX, FCropNorm.Left + 0.02);
    if FCropDragId in [5, 6, 7] then
      FCropNorm.Bottom := Max(NY, FCropNorm.Top + 0.02);
    FCropNorm.Left := EnsureRange(FCropNorm.Left, 0, 1);
    FCropNorm.Top := EnsureRange(FCropNorm.Top, 0, 1);
    FCropNorm.Right := EnsureRange(FCropNorm.Right, 0, 1);
    FCropNorm.Bottom := EnsureRange(FCropNorm.Bottom, 0, 1);
  end;
  FCropLast := TPointF.Create(X, Y);
  FCropPaint.Repaint;
end;

procedure TFilePreview.CropMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FCropDragId := -1;
  if Assigned(FCropPaint) and Assigned(FCropPaint.Root) and
     Assigned(FCropPaint.Root.Captured) and
     (FCropPaint.Root.Captured.GetObject = FCropPaint) then
    FCropPaint.Root.Captured := nil;
end;

procedure TFilePreview.ImgCropClick(Sender: TObject);
var
  I: Integer;
begin
  if not FEditing or FImgBuilding then
    Exit;
  if FCropping then
  begin
    CancelCrop;
    Exit;
  end;
  if Assigned(FSizeStrip) then
    FSizeStrip.Visible := False;
  if not EnsureOriginal then
    Exit;
  FCropping := True;
  FCropRatio := 0;
  FCropGrid := True;
  FCropNorm := TRectF.Create(0, 0, 1, 1);
  for I := 0 to High(FRatioBtns) do
    if Assigned(FRatioBtns[I]) then
      FRatioBtns[I].SetSelected(FRatioBtns[I].Tag = FCropRatio);
  if Assigned(FRatioStrip) then
    FRatioStrip.Visible := True;
  if Assigned(FCropPaint) then
  begin
    FCropPaint.Visible := True;
    FCropPaint.BringToFront;
    FCropPaint.Repaint;
  end;
  SyncEditButtons;
  LayoutImageFooter(nil);
  if CanFocus then
    SetFocus;
end;

function SaveExt(AFmt: TImageSaveFormat): string;
begin
  case AFmt of
    isfJpeg: Result := '.jpg';
    isfWebp: Result := '.webp';
    isfBmp: Result := '.bmp';
    isfIco: Result := '.ico';
  else
    Result := '.png';
  end;
end;

function TFilePreview.SaveTargetPath: string;
var
  Name, Ext: string;
  Fmt: TImageSaveFormat;
begin
  Result := '';
  if not Assigned(FSaveName) or not Assigned(FSaveFmt) then
    Exit;
  Name := Trim(FSaveName.Text);
  if Name = '' then
    Exit;
  if FSaveFont then
  begin
    Ext := '';
    if (FSaveFmt.ItemIndex >= 0) and (FSaveFmt.ItemIndex <= High(FFontOffers)) then
      Ext := FFontOffers[FSaveFmt.ItemIndex].Ext;
  end
  else if FSaveMedia then
    Ext := MediaExt
  else
  begin
    Fmt := TImageSaveFormat(EnsureRange(FSaveFmt.ItemIndex, 0, Ord(High(TImageSaveFormat))));
    Ext := SaveExt(Fmt);
  end;
  if not SameText(ExtractFileExt(Name), Ext) then
    Name := ChangeFileExt(Name, Ext);
  if FSaveDir = '' then
    FSaveDir := ExtractFilePath(FPath);
  Result := System.IOUtils.TPath.Combine(FSaveDir, Name);
end;

procedure TFilePreview.RefreshSaveExists;
var
  Path: string;
begin
  Path := SaveTargetPath;
  if not Assigned(FSaveExists) then
    Exit;
  if FSaveFont then
  begin
    FSaveArmed := False;
    if FFontProblem <> '' then
    begin
      FSaveBlocked := True;
      FSaveExists.Text := FFontProblem;
      FSaveExists.Visible := True;
    end
    else
    begin
      FSaveBlocked := False;
      FSaveExists.Visible := False;
    end;
    Exit;
  end;
  if FSaveMedia and (Path <> '') and SameText(ExpandFileName(Path), ExpandFileName(FPath)) then
  begin
    FSaveBlocked := True;
    FSaveArmed := False;
    FSaveExists.Text := L('qv.replaceopen');
    FSaveExists.Visible := True;
    Exit;
  end;
  FSaveBlocked := False;
  FSaveExists.Text := L('qv.exists');
  FSaveExists.Visible := (Path <> '') and TFile.Exists(Path);
  if not FSaveExists.Visible then
    FSaveArmed := False;
end;

procedure TFilePreview.LayoutSaveCard(Sender: TObject);
var
  W, H, Y, CW: Single;
  ShowKind, ShowRange, ShowQ: Boolean;
  Mode, BW: Integer;
  Gap: Single;
begin
  if not Assigned(FSaveShade) or not FSaveShade.Visible or not Assigned(FSaveCard) then
    Exit;
  ShowKind := FSaveMedia and (not FIsAudio) and Assigned(FSaveKindRow);
  ShowRange := FSaveMedia and Assigned(FSaveRange);
  if Assigned(FSaveNote) and not FSaveFont then
    FSaveNote.Visible := False;
  if FSaveFont then
    Mode := 0
  else if FSaveMedia then
    Mode := MediaQualMode
  else if Assigned(FSaveFmt) and (FSaveFmt.ItemIndex in [Ord(isfJpeg), Ord(isfWebp)]) then
    Mode := 1
  else
    Mode := 0;
  ShowQ := Mode > 0;
  if Assigned(FSaveKindRow) then
    FSaveKindRow.Visible := ShowKind;
  if Assigned(FSaveRange) then
  begin
    FSaveRange.Visible := ShowRange;
    if ShowRange then
      FSaveRange.Text := MediaRangeText;
  end;
  if Assigned(FSaveQualLbl) then
  begin
    FSaveQualLbl.Visible := ShowQ;
    if Mode = 2 then
      FSaveQualLbl.Text := L('qv.kbps')
    else
      FSaveQualLbl.Text := L('qv.quality');
  end;
  if Assigned(FSaveQual) then
    FSaveQual.Visible := ShowQ;
  CW := FSaveShade.Width;
  if CW > 460 then
    W := 420
  else
    W := Max(280, CW - 24);
  H := 16 + 26 + 10 + 16 + 32 + 10 + 16 + 32 + 10 + 28 + 12 + 32 + 16;
  if ShowKind then
    H := H + 32 + 8;
  if ShowRange then
    H := H + 18 + 8;
  if ShowQ then
    H := H + 16 + 32 + 8;
  if Assigned(FSaveExists) and FSaveExists.Visible then
    H := H + 22;
  if Assigned(FSaveNote) and FSaveNote.Visible then
    H := H + 20;
  FSaveCard.SetBounds((FSaveShade.Width - W) / 2,
    EnsureRange((FSaveShade.Height - H) / 2, 8, 4000), W, H);
  Y := 16;
  if Assigned(FSaveTitle) then
    FSaveTitle.SetBounds(20, Y, W - 40, 26);
  Y := Y + 26 + 10;
  if ShowKind then
  begin
    FSaveKindRow.SetBounds(20, Y, W - 40, 32);
    Gap := 8;
    BW := Round((W - 40 - Gap * 2) / 3);
    if Assigned(FBtnKindClip) then
      FBtnKindClip.SetBounds(0, 0, BW, 32);
    if Assigned(FBtnKindFrame) then
      FBtnKindFrame.SetBounds(BW + Gap, 0, BW, 32);
    if Assigned(FBtnKindAudio) then
      FBtnKindAudio.SetBounds((BW + Gap) * 2, 0, W - 40 - (BW + Gap) * 2, 32);
    Y := Y + 32 + 8;
  end;
  if ShowRange then
  begin
    FSaveRange.SetBounds(20, Y, W - 40, 18);
    Y := Y + 18 + 8;
  end;
  if Assigned(FSaveFmtLbl) then
    FSaveFmtLbl.SetBounds(20, Y, W - 40, 16);
  Y := Y + 16;
  if Assigned(FSaveFmt) then
    FSaveFmt.SetBounds(20, Y, W - 40, 32);
  Y := Y + 32 + 10;
  if ShowQ then
  begin
    if Assigned(FSaveQualLbl) then
      FSaveQualLbl.SetBounds(20, Y + 6, 90, 20);
    if Assigned(FSaveQual) then
      FSaveQual.SetBounds(116, Y, 72, 32);
    Y := Y + 32 + 8;
  end;
  if Assigned(FSaveNameLbl) then
    FSaveNameLbl.SetBounds(20, Y, W - 40, 16);
  Y := Y + 16;
  if Assigned(FSaveName) then
    FSaveName.SetBounds(20, Y, W - 40, 32);
  Y := Y + 32 + 10;
  if Assigned(FSaveBrowse) then
    FSaveBrowse.SetBounds(W - 20 - 96, Y, 96, 28);
  if Assigned(FSaveFolder) then
    FSaveFolder.SetBounds(20, Y, W - 20 - 96 - 12 - 20, 28);
  Y := Y + 28 + 6;
  if Assigned(FSaveExists) and FSaveExists.Visible then
  begin
    FSaveExists.SetBounds(20, Y, W - 40, 18);
    Y := Y + 22;
  end;
  if Assigned(FSaveNote) and FSaveNote.Visible then
  begin
    FSaveNote.SetBounds(20, Y, W - 40, 16);
    Y := Y + 20;
  end;
  Y := Y + 6;
  if Assigned(FSaveOk) then
    FSaveOk.SetBounds(W - 20 - 118, Y, 118, 32);
  if Assigned(FSaveCancel) then
    FSaveCancel.SetBounds(W - 20 - 118 - 8 - 96, Y, 96, 32);
end;

procedure TFilePreview.CloseSaveCard;
begin
  FSaveArmed := False;
  FSaveFont := False;
  if Assigned(FSaveNote) then
    FSaveNote.Visible := False;
  if Assigned(FSaveOk) then
  begin
    FSaveOk.Enabled := True;
    FSaveOk.Opacity := 1;
  end;
  SetMediaShelfLocked(False);
  HideVideoStill;
  if Assigned(FSaveShade) then
    FSaveShade.Visible := False;
  {$IFDEF MSWINDOWS}
  if FUsingMpv and FIsVideo then
    SyncHostWnd;
  {$ENDIF}
end;

procedure TFilePreview.SetMediaShelfLocked(ALock: Boolean);
  procedure Gate(AControl: TControl);
  begin
    if AControl = nil then
      Exit;
    AControl.HitTest := not ALock;
    AControl.Enabled := not ALock;
    if ALock then
      AControl.Opacity := 0.4
    else
      AControl.Opacity := 1;
  end;
begin
  Gate(FBtnPlay);
  Gate(FBtnSaveClip);
  Gate(FBtnSaveFrame);
  Gate(FSeekBox);
  Gate(FWaveBox);
end;

procedure TFilePreview.HideVideoStill;
begin
  if not Assigned(FSaveStill) then
    Exit;
  FSaveStill.Visible := False;
  FSaveStill.Bitmap.SetSize(0, 0);
end;

function PrintWindow(hwnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';

procedure TFilePreview.ShowVideoStill;
{$IFDEF MSWINDOWS}
const
  PW_RENDERFULLCONTENT = 2;
var
  Wnd: HWND;
  WR: TRect;
  DC, Mem: HDC;
  Dib: HBITMAP;
  OldBmp: HGDIOBJ;
  Info: TBitmapInfo;
  Bits: Pointer;
  W, H, Y, Row: Integer;
  Shot: TBitmap;
  Data: FMX.Graphics.TBitmapData;
  Src, Dst: PByte;
  P: TPointF;
{$ENDIF}
begin
  HideVideoStill;
  if not FIsVideo then
    Exit;
{$IFDEF MSWINDOWS}
  if not Assigned(FMpv) or not FMpv.HostWindow(Wnd) then
    Exit;
  if not GetClientRect(Wnd, WR) then
    Exit;
  W := WR.Right - WR.Left;
  H := WR.Bottom - WR.Top;
  if (W < 8) or (H < 8) then
    Exit;
  DC := GetDC(Wnd);
  if DC = 0 then
    Exit;
  Shot := nil;
  Dib := 0;
  Mem := 0;
  try
    Mem := CreateCompatibleDC(DC);
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    Info.bmiHeader.biWidth := W;
    Info.bmiHeader.biHeight := -H;
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    Bits := nil;
    Dib := CreateDIBSection(DC, Info, DIB_RGB_COLORS, Bits, 0, 0);
    if (Dib = 0) or (Bits = nil) then
      Exit;
    OldBmp := SelectObject(Mem, Dib);
    if not PrintWindow(Wnd, Mem, PW_RENDERFULLCONTENT) then
      BitBlt(Mem, 0, 0, W, H, DC, 0, 0, SRCCOPY);
    SelectObject(Mem, OldBmp);
    Shot := TBitmap.Create(W, H);
    if Shot.Map(TMapAccess.Write, Data) then
    try
      Row := W * 4;
      Src := PByte(Bits);
      Dst := PByte(Data.Data);
      if Dst <> nil then
        for Y := 0 to H - 1 do
        begin
          System.Move(Src^, Dst^, Row);
          Inc(Src, Row);
          Inc(Dst, Data.Pitch);
        end;
    finally
      Shot.Unmap(Data);
    end;
    if FSaveStill = nil then
    begin
      FSaveStill := TImage.Create(Self);
      FSaveStill.Parent := FBody;
      FSaveStill.Stored := False;
      FSaveStill.HitTest := False;
      FSaveStill.Align := TAlignLayout.None;
      FSaveStill.WrapMode := TImageWrapMode.Stretch;
    end;
    FSaveStill.Bitmap.Assign(Shot);
    if GetWindowRect(Wnd, WR) then
    begin
      P := FBody.ScreenToLocal(TPointF.Create(WR.Left, WR.Top));
      FSaveStill.SetBounds(P.X, P.Y, WR.Right - WR.Left, WR.Bottom - WR.Top);
    end;
    FSaveStill.Visible := True;
  finally
    Shot.Free;
    if Dib <> 0 then
      DeleteObject(Dib);
    if Mem <> 0 then
      DeleteDC(Mem);
    ReleaseDC(Wnd, DC);
  end;
{$ENDIF}
end;

procedure TFilePreview.SaveFormatChange(Sender: TObject);
var
  Fmt: TImageSaveFormat;
  Name: string;
begin
  if FSaveSilence or not Assigned(FSaveFmt) or not Assigned(FSaveName) then
    Exit;
  if FSaveFont then
  begin
    Name := Trim(FSaveName.Text);
    if (FSaveFmt.ItemIndex >= 0) and (FSaveFmt.ItemIndex <= High(FFontOffers)) then
    begin
      if (Name = '') or not FSaveNameOwn then
        Name := FontFreeName(FFontOffers[FSaveFmt.ItemIndex].Ext)
      else
        Name := ChangeFileExt(Name, FFontOffers[FSaveFmt.ItemIndex].Ext);
    end;
    FSaveSilence := True;
    try
      FSaveName.Text := Name;
    finally
      FSaveSilence := False;
    end;
    RefreshSaveExists;
    LayoutSaveCard(nil);
    Exit;
  end;
  if FSaveMedia then
  begin
    Name := Trim(FSaveName.Text);
    if (Name = '') or not FSaveNameOwn then
      Name := MediaDefaultName
    else
      Name := ChangeFileExt(Name, MediaExt);
    FSaveSilence := True;
    try
      FSaveName.Text := Name;
      if MediaQualMode = 2 then
      begin
        if (StrToIntDef(Trim(FSaveQual.Text), 0) < 64) or
           (StrToIntDef(Trim(FSaveQual.Text), 0) > 320) then
          FSaveQual.Text := '192';
      end
      else if MediaQualMode = 1 then
      begin
        if (StrToIntDef(Trim(FSaveQual.Text), 0) < 1) or
           (StrToIntDef(Trim(FSaveQual.Text), 0) > 100) then
          FSaveQual.Text := '90';
      end;
    finally
      FSaveSilence := False;
    end;
    RefreshSaveExists;
    LayoutSaveCard(nil);
    Exit;
  end;
  Fmt := TImageSaveFormat(EnsureRange(FSaveFmt.ItemIndex, 0, Ord(High(TImageSaveFormat))));
  Name := Trim(FSaveName.Text);
  if Name = '' then
    Name := ChangeFileExt(ExtractFileName(FPath), SaveExt(Fmt))
  else
    Name := ChangeFileExt(Name, SaveExt(Fmt));
  FSaveSilence := True;
  try
    FSaveName.Text := Name;
  finally
    FSaveSilence := False;
  end;
  RefreshSaveExists;
  LayoutSaveCard(nil);
end;

procedure TFilePreview.SaveNameChange(Sender: TObject);
begin
  if FSaveSilence then
    Exit;
  KeepDigits(FSaveQual, 3);
  if Sender = FSaveName then
  begin
    FSaveNameOwn := Trim(FSaveName.Text) <> '';
    FSaveArmed := False;
    RefreshSaveExists;
    LayoutSaveCard(nil);
  end;
end;

procedure TFilePreview.SaveBrowseClick(Sender: TObject);
var
  Dlg: IFileOpenDialog;
  Item: IShellItem;
  Path: PWideChar;
  Opts: DWORD;
  Start: string;
begin
  if Failed(CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER,
      IFileOpenDialog, Dlg)) then
    Exit;
  Dlg.SetTitle(PChar(L('qv.folder')));
  Dlg.GetOptions(Opts);
  Dlg.SetOptions(Opts or FOS_PICKFOLDERS or FOS_FORCEFILESYSTEM);
  Start := ExcludeTrailingPathDelimiter(FSaveDir);
  if (Start <> '') and TDirectory.Exists(Start) and
     Succeeded(SHCreateItemFromParsingName(PWideChar(Start), nil, IID_IShellItem, Item)) then
    Dlg.SetFolder(Item);
  if Failed(Dlg.Show(0)) then
    Exit;
  if Failed(Dlg.GetResult(Item)) then
    Exit;
  if Succeeded(Item.GetDisplayName(SIGDN_FILESYSPATH, Path)) then
  try
    FSaveDir := Path;
    if Assigned(FSaveFolder) then
      FSaveFolder.Text := FSaveDir;
  finally
    CoTaskMemFree(Path);
  end;
  RefreshSaveExists;
  LayoutSaveCard(nil);
end;

procedure TFilePreview.SaveCancelClick(Sender: TObject);
begin
  CloseSaveCard;
end;

procedure TFilePreview.CommitSave;
var
  Path, Ext: string;
  Fmt: TImageSaveFormat;
  Q: Integer;
  Src: TBitmap;
begin
  if FSaveFont then
  begin
    CommitFontSave;
    Exit;
  end;
  if FImgBuilding then
    Exit;
  if FSaveMedia then
  begin
    CommitMediaSave;
    Exit;
  end;
  Path := SaveTargetPath;
  if Path = '' then
    Exit;
  if TFile.Exists(Path) and not (Assigned(FSaveExists) and FSaveExists.Visible) then
  begin
    if Assigned(FSaveExists) then
      FSaveExists.Visible := True;
    FSaveArmed := True;
    LayoutSaveCard(nil);
    Exit;
  end;
  if not EnsureOriginal then
    Exit;
  Fmt := TImageSaveFormat(EnsureRange(FSaveFmt.ItemIndex, 0, Ord(High(TImageSaveFormat))));
  Q := StrToIntDef(Trim(FSaveQual.Text), 90);
  Q := EnsureRange(Q, 1, 100);
  Src := TBitmap.Create;
  try
    if (Length(FImgOps) > 0) and Assigned(FImage) and (FImage.Bitmap.Width > 0) then
      Src.Assign(FImage.Bitmap)
    else
      Src.Assign(FImgOriginal);
    Ext := ExtractFilePath(Path);
    if (Ext <> '') and not TDirectory.Exists(Ext) then
    begin
      ShowToast(L('qv.toast.nofolder'));
      Exit;
    end;
    if SaveImage(Src, Path, Fmt, Q) then
    begin
      FImgDirty := False;
      FLastSaved := Path;
      if Assigned(GlobalMetaCache) then
      begin
        GlobalMetaCache.Invalidate(Path);
        GlobalMetaCache.RequestAsync(Path);
      end;
      if Assigned(GlobalThumbCache) then
        GlobalThumbCache.Invalidate(Path);
      if Assigned(GlobalIconCache) then
        GlobalIconCache.InvalidatePath(Path);
      CloseSaveCard;
      ShowToast(L('qv.toast.saved'));
      if Assigned(FOnDiskChanged) then
        FOnDiskChanged(Self);
      FLastSaved := '';
    end
    else
      ShowToast(L('qv.writefail'));
  finally
    Src.Free;
  end;
end;

procedure TFilePreview.OpenSaveCard;
var
  Ext: string;
  Fmt: TImageSaveFormat;
begin
  if not FEditing or FImgBuilding then
    Exit;
  if not EnsureOriginal then
  begin
    ShowToast(L('qv.toast.noframe'));
    Exit;
  end;
  FSaveMedia := False;
  FSaveFont := False;
  FSaveNameOwn := False;
  if Assigned(FSaveNote) then
    FSaveNote.Visible := False;
  if Assigned(FSaveOk) then
  begin
    FSaveOk.Enabled := True;
    FSaveOk.Opacity := 1;
  end;
  if Assigned(FSaveKindRow) then
    FSaveKindRow.Visible := False;
  if Assigned(FSaveRange) then
    FSaveRange.Visible := False;
  Ext := LowerCase(ExtractFileExt(FPath));
  if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jfif') then
    Fmt := isfJpeg
  else if Ext = '.webp' then
    Fmt := isfWebp
  else if Ext = '.bmp' then
    Fmt := isfBmp
  else if (Ext = '.ico') or (Ext = '.cur') then
    Fmt := isfIco
  else
    Fmt := isfPng;
  FSaveDir := ExtractFilePath(FPath);
  FillImageFormats;
  FSaveSilence := True;
  try
    FSaveFmt.ItemIndex := Ord(Fmt);
    FSaveName.Text := ChangeFileExt(ExtractFileName(FPath), SaveExt(Fmt));
    FSaveQual.Text := '90';
  finally
    FSaveSilence := False;
  end;
  if Assigned(FSaveFolder) then
    FSaveFolder.Text := FSaveDir;
  RefreshSaveExists;
  FSaveShade.Visible := True;
  FSaveShade.BringToFront;
  LayoutSaveCard(nil);
  if FSaveName.CanFocus then
    FSaveName.SetFocus;
end;

procedure TFilePreview.ImgSaveClick(Sender: TObject);
begin
  if Assigned(FSaveShade) and FSaveShade.Visible then
    CommitSave
  else
    OpenSaveCard;
end;

function TFilePreview.HandleImageKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
  if not FImgChrome then
    Exit;
  if ssAlt in Shift then
    Exit;
  if Assigned(FSaveShade) and FSaveShade.Visible then
  begin
    if Key = vkEscape then
    begin
      CloseSaveCard;
      Key := 0;
      Exit(True);
    end;
    if (Key = vkS) and (ssCtrl in Shift) then
    begin
      CommitSave;
      Key := 0;
      Exit(True);
    end;
    Exit;
  end;
  if FCropping then
  begin
    if Key = vkReturn then
    begin
      ApplyCrop;
      Key := 0;
      Exit(True);
    end;
    if Key = vkEscape then
    begin
      CancelCrop;
      Key := 0;
      Exit(True);
    end;
    if (Key = vkG) and not (ssCtrl in Shift) then
    begin
      FCropGrid := not FCropGrid;
      if Assigned(FCropPaint) then
        FCropPaint.Repaint;
      Key := 0;
      Exit(True);
    end;
    Exit;
  end;
  if Assigned(FSizeStrip) and FSizeStrip.Visible and
     ((Key = vkReturn) or (Key = vkEscape)) then
  begin
    if Key = vkReturn then
      SizeSubmit(nil)
    else
      SizeCancel(nil);
    Key := 0;
    Exit(True);
  end;
  if not FEditing then
    Exit;
  if (Key = vkS) and (ssCtrl in Shift) then
  begin
    ImgSaveClick(nil);
    Key := 0;
    Exit(True);
  end;
  if (Key = vkZ) and (ssCtrl in Shift) then
  begin
    ImgResetClick(nil);
    Key := 0;
    Exit(True);
  end;
  if ssCtrl in Shift then
    Exit;
  if Key = vkC then
  begin
    ImgCropClick(nil);
    Key := 0;
    Exit(True);
  end;
  if Key = vkH then
  begin
    PushFlip(False);
    Key := 0;
    Exit(True);
  end;
  if Key = vkV then
  begin
    PushFlip(True);
    Key := 0;
    Exit(True);
  end;
  if Key = 219 then
  begin
    PushRot(False);
    Key := 0;
    Exit(True);
  end;
  if Key = 221 then
  begin
    PushRot(True);
    Key := 0;
    Exit(True);
  end;
  if Key = vkR then
  begin
    ImgResizeClick(nil);
    Key := 0;
    Exit(True);
  end;
  if Key = vkEscape then
  begin
    if Length(FImgOps) = 0 then
      LeaveEdit(False)
    else if not FEditWarnOn then
    begin
      FEditWarnOn := True;
      if Assigned(FEditWarn) then
      begin
        FEditWarn.Visible := True;
        FEditWarn.Text := L('qv.dirty');
      end;
      LayoutImageFooter(nil);
    end
    else
      LeaveEdit(True);
    Key := 0;
    Exit(True);
  end;
end;

procedure TFilePreview.ApplyImageTheme;
var
  I: Integer;
  Btns: array[0..10] of TFluentButton;
begin
  if Assigned(FPxText) then
    FPxText.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FFrameNote) then
    FFrameNote.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FHeaderRule) then
  begin
    FHeaderRule.Fill.Color := FColors.DividerColor;
    FHeaderRule.Stroke.Kind := TBrushKind.None;
  end;
  if Assigned(FFooterBg) then
  begin
    FFooterBg.Fill.Color := FColors.PanelBackground;
    FFooterBg.Stroke.Kind := TBrushKind.None;
  end;
  if Assigned(FViewRule) then
    FViewRule.Fill.Color := FColors.DividerColor;
  if Assigned(FEditRule) then
    FEditRule.Fill.Color := FColors.DividerColor;
  if Assigned(FEditWarn) then
    FEditWarn.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FHdrEv) then
    FHdrEv.TextSettings.FontColor := FColors.TextColor;
  if Assigned(FHdrTrack) and FHdrTrack.Visible then
    FHdrTrack.Repaint;
  if Assigned(FSizeWLbl) then
    FSizeWLbl.TextSettings.FontColor := FColors.TextColor;
  if Assigned(FSizeHLbl) then
    FSizeHLbl.TextSettings.FontColor := FColors.TextColor;
  if Assigned(FSizeW) then
    FSizeW.ApplyTheme(FColors);
  if Assigned(FSizeH) then
    FSizeH.ApplyTheme(FColors);
  if Assigned(FSizeCombo) then
    FSizeCombo.ApplyTheme(FColors);
  if Assigned(FZoomCombo) then
    FZoomCombo.ApplyTheme(FColors);
  Btns[0] := FBtnFit;
  Btns[1] := FBtnEdit;
  Btns[2] := FBtnCrop;
  Btns[3] := FBtnFlipH;
  Btns[4] := FBtnFlipV;
  Btns[5] := FBtnRotR;
  Btns[6] := FBtnSize;
  Btns[7] := FBtnReset;
  Btns[8] := FBtnSave;
  Btns[9] := FSizeLock;
  Btns[10] := FSaveBrowse;
  for I := 0 to High(Btns) do
    if Assigned(Btns[I]) then
      Btns[I].ApplyTheme(FColors);
  for I := 0 to High(FRatioBtns) do
    if Assigned(FRatioBtns[I]) then
      FRatioBtns[I].ApplyTheme(FColors);
  if Assigned(FBtnCropOk) then
    FBtnCropOk.ApplyTheme(FColors);
  if Assigned(FBtnSizeOk) then
    FBtnSizeOk.ApplyTheme(FColors);
  StyleIcoCaptions;
  if Assigned(FSaveCard) then
  begin
    FSaveCard.Fill.Color := FColors.CardBackground;
    FSaveCard.Stroke.Color := FColors.CardStroke;
  end;
  if Assigned(FSaveShadow) then
    ApplyFluentShadow(FSaveShadow, FColors.IsDark);
  if Assigned(FSaveTitle) then
    FSaveTitle.TextSettings.FontColor := FColors.TextColor;
  if Assigned(FSaveFmtLbl) then
    FSaveFmtLbl.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FSaveNameLbl) then
    FSaveNameLbl.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FSaveQualLbl) then
    FSaveQualLbl.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FSaveFolder) then
    FSaveFolder.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FSaveExists) then
    FSaveExists.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FSaveNote) then
    FSaveNote.TextSettings.FontColor := FColors.SubTextColor;
  if Assigned(FSaveFmt) then
    FSaveFmt.ApplyTheme(FColors);
  if Assigned(FSaveQual) then
    FSaveQual.ApplyTheme(FColors);
  if Assigned(FSaveName) then
    FSaveName.ApplyTheme(FColors);
  if Assigned(FSaveCancel) then
    FSaveCancel.ApplyTheme(FColors);
  if Assigned(FSaveOk) then
    FSaveOk.ApplyTheme(FColors);
end;

function MakeIconButton(AOwner: TComponent; AParent: TFmxObject;
  const AIcon, AHint: string; AKind: TFluentButtonKind; AWidth: Single;
  AClick: TNotifyEvent): TFluentButton;
begin
  Result := CreateFluentButton(AOwner, AParent, AIcon, '', AKind, AWidth, AClick);
  Result.Align := TAlignLayout.None;
  Result.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  Result.Hint := AHint;
  Result.ShowHint := True;
end;

procedure TwistGlyph(ABtn: TFluentButton; AAngle: Single; AMirror: Boolean);

  procedure Walk(AParent: TFmxObject);
  var
    I: Integer;
    C: TFmxObject;
  begin
    if AParent = nil then
      Exit;
    for I := 0 to AParent.ChildrenCount - 1 do
    begin
      C := AParent.Children[I];
      if C is TText then
      begin
        TText(C).RotationCenter.Point := PointF(0.5, 0.5);
        TText(C).RotationAngle := AAngle;
        if AMirror then
          TText(C).Scale.X := -1
        else
          TText(C).Scale.X := 1;
      end;
      Walk(C);
    end;
  end;

begin
  if ABtn = nil then
    Exit;
  ABtn.RotationAngle := 0;
  ABtn.Scale.X := 1;
  ABtn.RotationCenter.Point := PointF(0.5, 0.5);
  Walk(ABtn);
end;

procedure AddPercentItems(ACombo: TFluentComboBox);
begin
  if ACombo = nil then
    Exit;
  ACombo.Items.Add('10%');
  ACombo.Items.Add('25%');
  ACombo.Items.Add('50%');
  ACombo.Items.Add('75%');
  ACombo.Items.Add('100%');
  ACombo.Items.Add('150%');
  ACombo.Items.Add('200%');
  ACombo.Items.Add('400%');
end;

procedure TFilePreview.BuildImageChrome;
var
  I: Integer;
  Names: array[0..8] of string;
  Widths: array[0..8] of Single;
  Tags: array[0..8] of Integer;
begin
  FPxText := TText.Create(Self);
  FPxText.Parent := FHeader;
  FPxText.Align := TAlignLayout.None;
  FPxText.HitTest := False;
  FPxText.Visible := False;
  ApplyFluentText(FPxText, 11, False);
  FPxText.TextSettings.HorzAlign := TTextAlign.Trailing;
  FPxText.TextSettings.VertAlign := TTextAlign.Center;
  FPxText.WordWrap := False;

  FFrameNote := TText.Create(Self);
  FFrameNote.Parent := FHeader;
  FFrameNote.Align := TAlignLayout.None;
  FFrameNote.HitTest := False;
  FFrameNote.Visible := False;
  TrText(FFrameNote, 'qv.frameword');
  ApplyFluentText(FFrameNote, 11, False);
  FFrameNote.TextSettings.HorzAlign := TTextAlign.Trailing;
  FFrameNote.TextSettings.VertAlign := TTextAlign.Center;

  FHeaderRule := TRectangle.Create(Self);
  FHeaderRule.Parent := FHeader;
  FHeaderRule.Align := TAlignLayout.None;
  FHeaderRule.Height := 1;
  FHeaderRule.HitTest := False;
  FHeaderRule.Visible := False;
  FHeaderRule.Stroke.Kind := TBrushKind.None;

  FFooterHost := TLayout.Create(Self);
  FFooterHost.Parent := Self;
  FFooterHost.Align := TAlignLayout.Bottom;
  FFooterHost.Height := IMG_SHELF_H;
  FFooterHost.Visible := False;
  FFooterHost.ClipChildren := True;
  FFooterHost.OnResize := LayoutImageFooter;

  FFooterBg := TRectangle.Create(Self);
  FFooterBg.Parent := FFooterHost;
  FFooterBg.Align := TAlignLayout.Client;
  FFooterBg.HitTest := False;
  FFooterBg.Stroke.Kind := TBrushKind.None;

  FSizeStrip := TLayout.Create(Self);
  FSizeStrip.Parent := FFooterHost;
  FSizeStrip.Align := TAlignLayout.None;
  FSizeStrip.Visible := False;
  FSizeStrip.Height := 44;
  FSizeWLbl := TText.Create(Self);
  FSizeWLbl.Parent := FSizeStrip;
  FSizeWLbl.Align := TAlignLayout.None;
  FSizeWLbl.HitTest := False;
  TrText(FSizeWLbl, 'qv.width');
  ApplyFluentText(FSizeWLbl, 12, False);
  FSizeWLbl.TextSettings.VertAlign := TTextAlign.Center;
  FSizeW := TFluentEdit.Create(Self);
  FSizeW.Parent := FSizeStrip;
  FSizeW.Align := TAlignLayout.None;
  FSizeW.FillMode := fefSolid;
  FSizeW.OnChange := SizeFieldChange;
  FSizeW.OnSubmit := SizeSubmit;
  FSizeW.OnCancel := SizeCancel;
  FSizeLock := MakeIconButton(Self, FSizeStrip, #$E71B, '',
    fbkSubtle, 32, SizeLockClick);
  TrHint(FSizeLock, 'qv.lockratio');
  FSizeLock.SetSelected(True);
  FSizeHLbl := TText.Create(Self);
  FSizeHLbl.Parent := FSizeStrip;
  FSizeHLbl.Align := TAlignLayout.None;
  FSizeHLbl.HitTest := False;
  TrText(FSizeHLbl, 'qv.height');
  ApplyFluentText(FSizeHLbl, 12, False);
  FSizeHLbl.TextSettings.VertAlign := TTextAlign.Center;
  FSizeH := TFluentEdit.Create(Self);
  FSizeH.Parent := FSizeStrip;
  FSizeH.Align := TAlignLayout.None;
  FSizeH.FillMode := fefSolid;
  FSizeH.OnChange := SizeFieldChange;
  FSizeH.OnSubmit := SizeSubmit;
  FSizeH.OnCancel := SizeCancel;
  FSizeCombo := TFluentComboBox.Create(Self);
  FSizeCombo.Parent := FSizeStrip;
  FSizeCombo.Align := TAlignLayout.None;
  FSizeCombo.Width := 108;
  FSizeCombo.DropListOnly := False;
  FSizeCombo.Suggest := False;
  FSizeCombo.MaxVisible := 12;
  AddPercentItems(FSizeCombo);
  FSizeCombo.Text := '100%';
  FSizeCombo.OnSelChange := SizePctApply;
  FSizeCombo.OnSubmit := SizeComboSubmit;
  FBtnSizeOk := MakeIconButton(Self, FSizeStrip, #$E73E, '',
    fbkAccent, 36, SizeSubmit);
  TrHint(FBtnSizeOk, 'qv.apply');

  FRatioStrip := TLayout.Create(Self);
  FRatioStrip.Parent := FFooterHost;
  FRatioStrip.Align := TAlignLayout.None;
  FRatioStrip.Visible := False;
  FRatioStrip.Height := 36;
  Names[0] := L('qv.ratio.original');
  Names[1] := L('qv.ratio.free');
  Names[2] := '9:16';
  Names[3] := '2:3';
  Names[4] := '3:4';
  Names[5] := '1:1';
  Names[6] := '4:3';
  Names[7] := '3:2';
  Names[8] := '16:9';
  Widths[0] := 84;
  Widths[1] := 84;
  Widths[2] := 48;
  Widths[3] := 40;
  Widths[4] := 40;
  Widths[5] := 40;
  Widths[6] := 40;
  Widths[7] := 40;
  Widths[8] := 48;
  Tags[0] := 8;
  Tags[1] := 0;
  Tags[2] := 1;
  Tags[3] := 2;
  Tags[4] := 3;
  Tags[5] := 4;
  Tags[6] := 5;
  Tags[7] := 6;
  Tags[8] := 7;
  for I := 0 to High(FRatioBtns) do
  begin
    FRatioBtns[I] := CreateFluentButton(Self, FRatioStrip, '', Names[I], fbkSubtle,
      Widths[I], RatioClick);
    FRatioBtns[I].Align := TAlignLayout.None;
    FRatioBtns[I].Margins.Rect := TRectF.Create(0, 0, 0, 0);
    FRatioBtns[I].Width := Widths[I];
    FRatioBtns[I].Tag := Tags[I];
  end;
  TrButton(FRatioBtns[0], 'qv.ratio.original');
  TrButton(FRatioBtns[1], 'qv.ratio.free');
  FBtnCropOk := MakeIconButton(Self, FRatioStrip, #$E73E, '',
    fbkAccent, 36, CropApplyClick);
  TrHint(FBtnCropOk, 'qv.apply');

  FEditWarn := TText.Create(Self);
  FEditWarn.Parent := FFooterHost;
  FEditWarn.Align := TAlignLayout.None;
  FEditWarn.HitTest := False;
  FEditWarn.Visible := False;
  TrText(FEditWarn, 'qv.dirty');
  ApplyFluentText(FEditWarn, 11, False);
  FEditWarn.TextSettings.HorzAlign := TTextAlign.Leading;
  FEditWarn.TextSettings.VertAlign := TTextAlign.Center;

  FViewBar := TLayout.Create(Self);
  FViewBar.Parent := FFooterHost;
  FViewBar.Align := TAlignLayout.None;
  FViewBar.Height := IMG_SHELF_H;
  FViewRule := TRectangle.Create(Self);
  FViewRule.Parent := FViewBar;
  FViewRule.Align := TAlignLayout.None;
  FViewRule.Height := 1;
  FViewRule.HitTest := False;
  FViewRule.Stroke.Kind := TBrushKind.None;
  FZoomCombo := TFluentComboBox.Create(Self);
  FZoomCombo.Parent := FViewBar;
  FZoomCombo.Align := TAlignLayout.None;
  FZoomCombo.Width := 108;
  FZoomCombo.DropListOnly := False;
  FZoomCombo.Suggest := False;
  FZoomCombo.MaxVisible := 12;
  AddPercentItems(FZoomCombo);
  FZoomCombo.Text := '100%';
  FZoomCombo.OnSelChange := ImgZoomSelect;
  FZoomCombo.OnSubmit := ImgZoomSubmit;
  FBtnFit := MakeIconButton(Self, FViewBar, #$E9A6, '', fbkSubtle, 36, ImgFitClick);
  TrHint(FBtnFit, 'qv.fit');
  FBtnEdit := MakeIconButton(Self, FViewBar, #$E70F, '', fbkSubtle, 36, ImgEditClick);
  TrHint(FBtnEdit, 'qv.edit');
  FHdrTrack := TPaintBox.Create(Self);
  FHdrTrack.Parent := FViewBar;
  FHdrTrack.Align := TAlignLayout.None;
  FHdrTrack.Visible := False;
  FHdrTrack.HitTest := True;
  FHdrTrack.AutoCapture := True;
  FHdrTrack.OnPaint := PaintHdrSeek;
  FHdrTrack.OnMouseDown := HdrSeekDown;
  FHdrTrack.OnMouseMove := HdrSeekMove;
  FHdrTrack.OnMouseUp := HdrSeekUp;
  TrHint(FHdrTrack, 'qv.hdr.exposure');
  FHdrEv := TText.Create(Self);
  FHdrEv.Parent := FViewBar;
  FHdrEv.Align := TAlignLayout.None;
  FHdrEv.HitTest := False;
  FHdrEv.Visible := False;
  ApplyFluentText(FHdrEv, 12, False);
  FHdrEv.TextSettings.HorzAlign := TTextAlign.Leading;
  FHdrEv.TextSettings.VertAlign := TTextAlign.Center;
  FHdrEv.Text := '0.0';

  FEditBar := TLayout.Create(Self);
  FEditBar.Parent := FFooterHost;
  FEditBar.Align := TAlignLayout.None;
  FEditBar.Height := IMG_SHELF_H;
  FEditBar.Visible := False;
  FEditRule := TRectangle.Create(Self);
  FEditRule.Parent := FEditBar;
  FEditRule.Align := TAlignLayout.None;
  FEditRule.Height := 1;
  FEditRule.HitTest := False;
  FEditRule.Stroke.Kind := TBrushKind.None;
  FEditScroll := THorzScrollBox.Create(Self);
  FEditScroll.Parent := FEditBar;
  FEditScroll.Align := TAlignLayout.None;
  FEditScroll.ShowScrollBars := False;
  FEditScroll.AniCalculations.AutoShowing := False;
  FEditScroll.OnResize := EditToolsResize;
  FEditScroll.OnViewportPositionChange := EditToolsViewport;
  FEditTools := TLayout.Create(Self);
  FEditTools.Parent := FEditScroll;
  FEditTools.Align := TAlignLayout.None;
  FEditTools.HitTest := False;
  FBtnCrop := MakeIconButton(Self, FEditTools, #$E7A8, '', fbkSubtle, 36, ImgCropClick);
  TrHint(FBtnCrop, 'qv.crop');
  FBtnFlipH := MakeIconButton(Self, FEditTools, #$E8AB, '', fbkSubtle, 36, ImgFlipClick);
  TrHint(FBtnFlipH, 'qv.flipH');
  FBtnFlipH.Tag := 0;
  FBtnFlipV := MakeIconButton(Self, FEditTools, #$E8AB, '', fbkSubtle, 36, ImgFlipClick);
  TrHint(FBtnFlipV, 'qv.flipV');
  FBtnFlipV.Tag := 1;
  TwistGlyph(FBtnFlipV, 90, False);
  FBtnRotR := MakeIconButton(Self, FEditTools, #$E7AD, '', fbkSubtle, 36, ImgRotRClick);
  TrHint(FBtnRotR, 'qv.rotate');
  FBtnSize := MakeIconButton(Self, FEditTools, #$E799, '', fbkSubtle, 36, ImgResizeClick);
  TrHint(FBtnSize, 'qv.size');
  FBtnReset := MakeIconButton(Self, FEditTools, #$E7A7, '', fbkSubtle, 36, ImgResetClick);
  TrHint(FBtnReset, 'qv.reset');
  FBtnSave := CreateFluentButton(Self, FEditBar, #$E74E, '', fbkAccent, 128, ImgSaveClick);
  TrButton(FBtnSave, 'qv.save');
  FBtnSave.Align := TAlignLayout.None;
  FBtnSave.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  TrHint(FBtnSave, 'qv.save');
  FBtnSave.ShowHint := True;
  FEditScrollBar := TCustomFileScrollbar.Create(FEditBar, FEditScroll);
  FEditScrollBar.Orientation := TOrientation.Horizontal;
  FEditScrollBar.ApplyTheme(FColors);

  FSaveShade := TLayout.Create(Self);
  FSaveShade.Parent := FBody;
  FSaveShade.Align := TAlignLayout.Client;
  FSaveShade.Visible := False;
  FSaveShade.HitTest := True;
  FSaveShade.OnResize := LayoutSaveCard;
  FSaveCard := TRectangle.Create(Self);
  FSaveCard.Parent := FSaveShade;
  FSaveCard.Align := TAlignLayout.None;
  FSaveCard.XRadius := 8;
  FSaveCard.YRadius := 8;
  FSaveCard.Stroke.Kind := TBrushKind.Solid;
  FSaveCard.Stroke.Thickness := 1;
  FSaveShadow := TShadowEffect.Create(FSaveCard);
  FSaveShadow.Parent := FSaveCard;
  ApplyFluentShadow(FSaveShadow, FColors.IsDark);
  FSaveTitle := TText.Create(Self);
  FSaveTitle.Parent := FSaveCard;
  FSaveTitle.Align := TAlignLayout.None;
  FSaveTitle.HitTest := False;
  TrText(FSaveTitle, 'qv.save');
  ApplyFluentText(FSaveTitle, 16, True);
  FSaveFmtLbl := TText.Create(Self);
  FSaveFmtLbl.Parent := FSaveCard;
  FSaveFmtLbl.Align := TAlignLayout.None;
  FSaveFmtLbl.HitTest := False;
  TrText(FSaveFmtLbl, 'qv.format');
  ApplyFluentText(FSaveFmtLbl, 11, False);
  FSaveFmt := TFluentComboBox.Create(Self);
  FSaveFmt.Parent := FSaveCard;
  FSaveFmt.Align := TAlignLayout.None;
  FSaveFmt.DropListOnly := True;
  FSaveFmt.Suggest := False;
  FSaveFmt.Items.Add('PNG');
  FSaveFmt.Items.Add('JPEG');
  FSaveFmt.Items.Add('WebP');
  FSaveFmt.Items.Add('BMP');
  FSaveFmt.Items.Add('ICO');
  FSaveFmt.ItemIndex := 0;
  FSaveFmt.OnSelChange := SaveFormatChange;
  FSaveQualLbl := TText.Create(Self);
  FSaveQualLbl.Parent := FSaveCard;
  FSaveQualLbl.Align := TAlignLayout.None;
  FSaveQualLbl.HitTest := False;
  TrText(FSaveQualLbl, 'qv.quality');
  ApplyFluentText(FSaveQualLbl, 12, False);
  FSaveQual := TFluentEdit.Create(Self);
  FSaveQual.Parent := FSaveCard;
  FSaveQual.Align := TAlignLayout.None;
  FSaveQual.FillMode := fefSolid;
  FSaveQual.Text := '90';
  FSaveQual.OnChange := SaveNameChange;
  FSaveQual.OnCancel := SaveCancelClick;
  FSaveNameLbl := TText.Create(Self);
  FSaveNameLbl.Parent := FSaveCard;
  FSaveNameLbl.Align := TAlignLayout.None;
  FSaveNameLbl.HitTest := False;
  TrText(FSaveNameLbl, 'qv.name');
  ApplyFluentText(FSaveNameLbl, 11, False);
  FSaveName := TFluentEdit.Create(Self);
  FSaveName.Parent := FSaveCard;
  FSaveName.Align := TAlignLayout.None;
  FSaveName.FillMode := fefSolid;
  FSaveName.OnChange := SaveNameChange;
  FSaveName.OnSubmit := ImgSaveClick;
  FSaveName.OnCancel := SaveCancelClick;
  FSaveFolder := TText.Create(Self);
  FSaveFolder.Parent := FSaveCard;
  FSaveFolder.Align := TAlignLayout.None;
  FSaveFolder.HitTest := False;
  ApplyFluentText(FSaveFolder, 12, False);
  FSaveFolder.TextSettings.VertAlign := TTextAlign.Center;
  FSaveFolder.TextSettings.Trimming := TTextTrimming.Character;
  FSaveFolder.WordWrap := False;
  FSaveBrowse := CreateFluentButton(Self, FSaveCard, '', '', fbkSubtle, 96, SaveBrowseClick);
  TrButton(FSaveBrowse, 'qv.browse');
  FSaveBrowse.Align := TAlignLayout.None;
  FSaveBrowse.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FSaveExists := TText.Create(Self);
  FSaveExists.Parent := FSaveCard;
  FSaveExists.Align := TAlignLayout.None;
  FSaveExists.HitTest := False;
  FSaveExists.Visible := False;
  FSaveExists.Text := L('qv.exists');
  ApplyFluentText(FSaveExists, 12, False);
  FSaveNote := TText.Create(Self);
  FSaveNote.Parent := FSaveCard;
  FSaveNote.Align := TAlignLayout.None;
  FSaveNote.HitTest := False;
  FSaveNote.Visible := False;
  TrText(FSaveNote, 'font.woff2');
  ApplyFluentText(FSaveNote, 12, False);
  FSaveNote.TextSettings.Trimming := TTextTrimming.Character;
  FSaveNote.WordWrap := False;
  FSaveCancel := CreateFluentButton(Self, FSaveCard, '', '', fbkStandard, 96, SaveCancelClick);
  TrButton(FSaveCancel, 'qv.cancel');
  FSaveCancel.Align := TAlignLayout.None;
  FSaveCancel.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FSaveOk := CreateFluentButton(Self, FSaveCard, '', '', fbkAccent, 118, ImgSaveClick);
  TrButton(FSaveOk, 'qv.save');
  FSaveOk.Align := TAlignLayout.None;
  FSaveOk.Margins.Rect := TRectF.Create(0, 0, 0, 0);

  FSaveKindRow := TLayout.Create(Self);
  FSaveKindRow.Parent := FSaveCard;
  FSaveKindRow.Align := TAlignLayout.None;
  FSaveKindRow.Visible := False;
  FSaveKindRow.HitTest := True;
  FBtnKindClip := CreateFluentButton(Self, FSaveKindRow, #$E714, '', fbkSubtle, 120, SaveKindClick);
  TrButton(FBtnKindClip, 'qv.clip');
  FBtnKindClip.Align := TAlignLayout.None;
  FBtnKindClip.Tag := 0;
  FBtnKindFrame := CreateFluentButton(Self, FSaveKindRow, #$E722, '', fbkSubtle, 120, SaveKindClick);
  TrButton(FBtnKindFrame, 'qv.frame');
  FBtnKindFrame.Align := TAlignLayout.None;
  FBtnKindFrame.Tag := 1;
  FBtnKindAudio := CreateFluentButton(Self, FSaveKindRow, #$E8D6, '', fbkSubtle, 120, SaveKindClick);
  TrButton(FBtnKindAudio, 'qv.sound');
  FBtnKindAudio.Align := TAlignLayout.None;
  FBtnKindAudio.Tag := 2;
  FSaveRange := TText.Create(Self);
  FSaveRange.Parent := FSaveCard;
  FSaveRange.Align := TAlignLayout.None;
  FSaveRange.Visible := False;
  FSaveRange.HitTest := False;
  ApplyFluentText(FSaveRange, 12, False);
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
  begin
    if FMediaBar.AbsoluteRect.Top > R.Top + 8 then
      R.Bottom := FMediaBar.AbsoluteRect.Top
    else
      R.Bottom := R.Bottom - FMediaBar.Height;
  end;
  P1 := TPointF.Create(R.Left, R.Top);
  P2 := TPointF.Create(R.Right, R.Bottom);
  S1 := Form.ClientToScreen(P1);
  S2 := Form.ClientToScreen(P2);
  ScreenR := TRect.Create(Round(S1.X), Round(S1.Y), Round(S2.X), Round(S2.Y));

{$IFDEF MSWINDOWS}
  { Видео — дочернее окно формы, прямоугольник в экранных координатах области превью }
  if FUsingMpv and FIsVideo and Assigned(FMpv) and (not FDestroying) then
  begin
    if Visible and ParentedVisible and (ScreenR.Width > 8) and (ScreenR.Height > 8) and
       not (Assigned(FSaveShade) and FSaveShade.Visible) then
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

procedure TFilePreview.MeshRenderSize(out AW, AH: Integer);
begin
  AW := 640;
  AH := 480;
  if Assigned(FImgHost) and (FImgHost.Width >= 32) and (FImgHost.Height >= 32) then
  begin
    AW := Round(FImgHost.Width);
    AH := Round(FImgHost.Height);
  end;
  if AW < 32 then
    AW := 32;
  if AH < 32 then
    AH := 32;
  if AW > 2560 then
    AW := 2560;
  if AH > 2560 then
    AH := 2560;
end;

procedure TFilePreview.ShowMeshFail(AErr: Integer);
var
  Key: string;
begin
  if Assigned(FImage) and FImage.Visible and (FImage.Bitmap.Width > 0) then
    Exit;
  if AErr = Ord(meBad) then
    Key := 'qv.mesh.bad'
  else if AErr = Ord(meBlend) then
    Key := 'qv.mesh.blend'
  else
    Key := 'qv.mesh.empty';
  if Assigned(FImgHost) then
    FImgHost.Visible := False;
  ShowInfoKey(Key);
  SetKindRaw(MeshKindName(TMeshKind(FMeshKind)));
end;

procedure TFilePreview.ApplyMeshChrome;
var
  Count, Line, Name: string;
begin
  Name := MeshKindName(TMeshKind(FMeshKind));
  if Name = '' then
    Name := UpperCase(Copy(FMeshExt, 2, 8));
  FKindKey := '';
  SetKindRaw(Name);
  if FMeshPicture then
    Line := Name + ' · ' + IntToStr(FMeshPicW) + '×' + IntToStr(FMeshPicH) +
      ' · ' + FormatFileSize(FMeshBytes)
  else
  begin
    if FMeshPoints > 0 then
      Count := Lf('qv.mesh.pts', [IntToStr(FMeshPoints)])
    else
      Count := Lf('qv.mesh.tris', [IntToStr(FMeshTris)]);
    if FMeshSimple then
      Count := Count + ' ~';
    Line := Lf('qv.mesh.stats', [Name, IntToStr(FMeshVerts), Count, FormatFileSize(FMeshBytes)]);
  end;
  if Assigned(FMeta) then
  begin
    FMeta.Visible := True;
    FMeta.Text := Line;
  end;
  if Assigned(FMeshHint) then
  begin
    FMeshHint.Text := L('qv.mesh.turn');
    FMeshHint.Visible := FMeshOn and not FMeshPicture and not FMeshHintGone;
    if FMeshHint.Visible then
      FMeshHint.BringToFront;
  end;
end;

procedure TFilePreview.FinishOrdinary(const ALocal, AExt: string);
begin
  if Assigned(FInfo) then
    FInfo.Visible := False;
  FInfoKey := '';
  {$IFDEF MSWINDOWS}
  if not IsExcelExt(AExt) then
    if LoadNativePreview(ALocal) then
    begin
      SetKindRaw(UpperCase(Copy(AExt, 2, 8)));
      Exit;
    end;
  {$ENDIF}
  if IsListedTextExt(AExt) or LooksLikeText(ALocal) then
  begin
    FTextEnc := temAuto;
    StartTextLoad(ALocal);
    Exit;
  end;
  ShowFileCard(ALocal);
end;

procedure TFilePreview.ApplyMeshFrame(ABmp: TBitmap; AErr: Integer;
  APicture, ASimple: Boolean; AKind: Integer; AVerts, ATris, APoints, ABytes: Int64;
  APicW, APicH: Integer; AGen, ALoadGen: Integer);
begin
  FMeshBusy := False;
  try
    if FDestroying or (AGen <> FMeshGen) or (ALoadGen <> FLoadGen) or not FMeshOn then
      Exit;
    if AErr = Ord(meNotMesh) then
    begin
      FMeshOn := False;
      if Assigned(FMeshHint) then
        FMeshHint.Visible := False;
      FinishOrdinary(FMeshPath, FMeshExt);
      Exit;
    end;
    FMeshKind := AKind;
    FMeshPicture := APicture;
    FMeshSimple := ASimple;
    FMeshVerts := AVerts;
    FMeshTris := ATris;
    FMeshPoints := APoints;
    FMeshBytes := ABytes;
    FMeshPicW := APicW;
    FMeshPicH := APicH;
    if (ABmp = nil) or (AErr <> Ord(meNone)) then
    begin
      if AErr <> Ord(meNone) then
        ShowMeshFail(AErr);
      Exit;
    end;
    FImage.Bitmap.Assign(ABmp);
    if Assigned(FInfo) then
      FInfo.Visible := False;
    FInfoKey := '';
    ShowRasterImage(True);
    ShowImageTools(False);
    ApplyMeshChrome;
    if not FMeshPicture and Assigned(FImgHost) then
      FImgHost.Cursor := crHandPoint;
  finally
    FreeAndNil(ABmp);
    if FMeshPending and FMeshOn and not FDestroying and not FMeshBusy then
      ScheduleMeshFrame;
  end;
end;

procedure TFilePreview.ScheduleMeshFrame;
var
  Path: string;
  W, H, Gen, LoadGen: Integer;
  Cam: TMeshCamera;
begin
  if not FMeshOn or FDestroying then
    Exit;
  if FMeshBusy then
  begin
    FMeshPending := True;
    Exit;
  end;
  FMeshBusy := True;
  FMeshPending := False;
  Inc(FMeshGen);
  Gen := FMeshGen;
  LoadGen := FLoadGen;
  Path := FMeshPath;
  Cam.Azimuth := FMeshAz;
  Cam.Elevation := FMeshEl;
  Cam.Scale := FMeshScale;
  MeshRenderSize(W, H);
  FMeshRendW := W;
  FMeshRendH := H;
  TThread.CreateAnonymousThread(
    procedure
    var
      Info: TMeshInfo;
      Bmp: TBitmap;
      Err, Kind, PicW, PicH: Integer;
      Picture, Simple: Boolean;
      Verts, Tris, Points, Bytes: Int64;
    begin
      Bmp := nil;
      Err := Ord(meBad);
      Kind := 0;
      Picture := False;
      Simple := False;
      Verts := 0;
      Tris := 0;
      Points := 0;
      Bytes := 0;
      PicW := 0;
      PicH := 0;
      try
        Bmp := RenderMeshView(Path, W, H, Cam, Info,
          function: Boolean
          begin
            Result := FDestroying or (Gen <> FMeshGen) or (LoadGen <> FLoadGen);
          end);
        Err := Ord(Info.Error);
        Kind := Ord(Info.Kind);
        Picture := Info.Picture;
        Simple := Info.Simplified;
        Verts := Info.Vertices;
        Tris := Info.Triangles;
        Points := Info.Points;
        Bytes := Info.Bytes;
        PicW := Info.PicW;
        PicH := Info.PicH;
      except
        FreeAndNil(Bmp);
        Err := Ord(meBad);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if FDestroying then
          begin
            Bmp.Free;
            FMeshBusy := False;
            Exit;
          end;
          ApplyMeshFrame(Bmp, Err, Picture, Simple, Kind, Verts, Tris, Points, Bytes,
            PicW, PicH, Gen, LoadGen);
        end);
    end).Start;
end;

procedure TFilePreview.StartMeshLoad(const ALocal: string);
var
  Cam: TMeshCamera;
begin
  Cam := MeshHomeCamera;
  FMeshOn := True;
  FMeshPicture := False;
  FMeshDrag := False;
  FMeshHintGone := False;
  FMeshPending := False;
  FMeshSimple := False;
  FMeshPath := ALocal;
  FMeshExt := LowerCase(ExtractFileExt(ALocal));
  FMeshKind := 0;
  FMeshAz := Cam.Azimuth;
  FMeshEl := Cam.Elevation;
  FMeshScale := Cam.Scale;
  FMeshVerts := 0;
  FMeshTris := 0;
  FMeshPoints := 0;
  FMeshBytes := 0;
  FMeshPicW := 0;
  FMeshPicH := 0;
  FMeshRendW := 0;
  FMeshRendH := 0;
  if FMeshExt = '.gltf' then
    SetKindRaw('glTF')
  else
    SetKindRaw(UpperCase(Copy(FMeshExt, 2, 8)));
  if Assigned(FMeshHint) then
    FMeshHint.Visible := False;
  ShowInfoKey('qv.loading');
  ScheduleMeshFrame;
end;

function HdrEvText(V: Single): string;
begin
  Result := FormatFloat('0.0', V);
  if V > 0.049 then
    Result := '+' + Result;
end;

procedure TFilePreview.ClearHdr;
begin
  FHdrOn := False;
  FHdrW := 0;
  FHdrH := 0;
  FHdrKind := '';
  FHdrFailKey := '';
  FHdrEvVal := 0;
  FHdrShown := 0;
  FHdrDrag := False;
  SetLength(FHdrRgb, 0);
  FHdrLock := True;
  try
    if Assigned(FHdrTrack) then
      FHdrTrack.Visible := False;
  finally
    FHdrLock := False;
  end;
  if Assigned(FHdrEv) then
  begin
    FHdrEv.Text := '0.0';
    FHdrEv.Visible := False;
  end;
end;

function TFilePreview.HdrXToEv(X: Single): Single;
var
  W, T, V: Single;
  N: Integer;
begin
  Result := 0;
  if not Assigned(FHdrTrack) then
    Exit;
  W := FHdrTrack.Width;
  if W < 17 then
    W := 17;
  T := EnsureRange((X - 8) / (W - 16), 0, 1);
  V := -3 + T * 6;
  if V >= 0 then
    N := Trunc(V * 10 + 0.5)
  else
    N := -Trunc(-V * 10 + 0.5);
  Result := EnsureRange(N / 10, -3, 3);
end;

procedure TFilePreview.PaintHdrSeek(Sender: TObject; Canvas: TCanvas);
var
  R, Track, FillR: TRectF;
  Cy, X, T: Single;
begin
  if not (Sender is TPaintBox) then
    Exit;
  R := TPaintBox(Sender).LocalRect;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := TAlphaColors.Null;
  Canvas.FillRect(R, 0, 0, [], 1);
  Cy := R.Top + R.Height * 0.5;
  Track := TRectF.Create(R.Left + 8, Cy - 3, R.Right - 8, Cy + 3);
  if Track.Width < 1 then
    Exit;
  Canvas.Fill.Color := FColors.ControlFill;
  Canvas.FillRect(Track, 3, 3, AllCorners, 1);
  T := (EnsureRange(FHdrEvVal, -3, 3) + 3) / 6;
  X := Track.Left + T * Track.Width;
  FillR := TRectF.Create(Track.Left, Track.Top, X, Track.Bottom);
  Canvas.Fill.Color := FColors.SelectionColor;
  Canvas.FillRect(FillR, 3, 3, AllCorners, 1);
  Canvas.FillEllipse(TRectF.Create(X - 6, Cy - 6, X + 6, Cy + 6), 1);
end;

procedure TFilePreview.HdrSeekDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if (Button <> TMouseButton.mbLeft) or FDestroying or not FHdrOn then
    Exit;
  FHdrDrag := True;
  FHdrEvVal := HdrXToEv(X);
  if Assigned(FHdrEv) then
    FHdrEv.Text := HdrEvText(FHdrEvVal);
  if Assigned(FHdrTrack) then
    FHdrTrack.Repaint;
end;

procedure TFilePreview.HdrSeekMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
begin
  if FHdrDrag and not (ssLeft in Shift) then
  begin
    HdrSeekUp(Sender, TMouseButton.mbLeft, Shift, X, Y);
    Exit;
  end;
  if not FHdrDrag or FDestroying or not FHdrOn then
    Exit;
  FHdrEvVal := HdrXToEv(X);
  if Assigned(FHdrEv) then
    FHdrEv.Text := HdrEvText(FHdrEvVal);
  if Assigned(FHdrTrack) then
    FHdrTrack.Repaint;
end;

procedure TFilePreview.HdrSeekUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if not FHdrDrag then
    Exit;
  FHdrDrag := False;
  if FDestroying or not FHdrOn then
    Exit;
  FHdrEvVal := HdrXToEv(X);
  if Assigned(FHdrEv) then
    FHdrEv.Text := HdrEvText(FHdrEvVal);
  if Assigned(FHdrTrack) then
    FHdrTrack.Repaint;
  ApplyHdrExposure;
end;

procedure TFilePreview.ApplyHdrExposure;
var
  Bmp: TBitmap;
  Ev: Single;
begin
  if FHdrLock or FDestroying or not FHdrOn or (FHdrW < 1) or (FHdrH < 1) then
    Exit;
  if Length(FHdrRgb) < FHdrW * FHdrH * 3 then
    Exit;
  Ev := EnsureRange(FHdrEvVal, -3, 3);
  if Abs(Ev - FHdrShown) < 0.001 then
    Exit;
  if Assigned(FHdrEv) then
    FHdrEv.Text := HdrEvText(Ev);
  Bmp := TBitmap.Create;
  try
    if not ToneMapHdr(FHdrRgb, FHdrW, FHdrH, Ev, Bmp) then
      Exit;
    FHdrShown := Ev;
    if FImgOriginal = nil then
      FImgOriginal := TBitmap.Create;
    FImgOriginal.Assign(Bmp);
    if Length(FImgOps) = 0 then
    begin
      if Assigned(FImage) then
      begin
        FImage.Bitmap.Assign(Bmp);
        FImage.Visible := True;
      end;
      FViewW := Bmp.Width;
      FViewH := Bmp.Height;
      ShowRasterImage(False);
    end
    else
      KickRebuild;
  finally
    Bmp.Free;
  end;
end;

procedure TFilePreview.ShowHdrFail(const AExt: string; ANoRgb: Boolean);
var
  Kind, Key: string;
begin
  Kind := HdrKindName(AExt);
  FHdrKind := Kind;
  try
    ShowFileCard(FPath);
  except
  end;
  SetKindRaw(Kind);
  if ANoRgb then
  begin
    FHdrFailKey := '';
    FFileType := Kind;
  end
  else
  begin
    if Kind = 'EXR' then
      Key := 'qv.exr.fail'
    else
      Key := 'qv.hdr.fail';
    FHdrFailKey := Key;
    FInfoKey := Key;
    FFileType := L(Key);
    if Assigned(FMeta) then
    begin
      FMeta.Visible := True;
      FMeta.Text := L(Key);
    end;
  end;
  if Assigned(FFileBox) then
    FFileBox.Repaint;
end;

procedure TFilePreview.LoadHdrView(const ALocal: string);
var
  Img: THdrImage;
  Err: THdrError;
  Bmp: TBitmap;
  Ext, Name: string;
begin
  Ext := LowerCase(ExtractFileExt(ALocal));
  FHdrKind := HdrKindName(Ext);
  Img.Clear;
  try
    Err := LoadHdrImage(ALocal, Img);
  except
    Err := heBad;
    Img.Clear;
  end;
  if Err <> heNone then
  begin
    Img.Clear;
    ShowHdrFail(Ext, Err = heNoRgb);
    Exit;
  end;
  FHdrW := Img.Width;
  FHdrH := Img.Height;
  FHdrRgb := Img.Rgb;
  SetLength(Img.Rgb, 0);
  Bmp := TBitmap.Create;
  try
    if not ToneMapHdr(FHdrRgb, FHdrW, FHdrH, 0, Bmp) then
    begin
      ClearHdr;
      ShowHdrFail(Ext, False);
      Exit;
    end;
    FHdrOn := True;
    FHdrFailKey := '';
    if FImgOriginal = nil then
      FImgOriginal := TBitmap.Create;
    FImgOriginal.Assign(Bmp);
    if Assigned(FImage) then
      FImage.Bitmap.Assign(Bmp);
  finally
    Bmp.Free;
  end;
  FImgKind := ivRaster;
  FViewW := FHdrW;
  FViewH := FHdrH;
  FFrameW := FHdrW;
  FFrameH := FHdrH;
  FHdrEvVal := 0;
  FHdrShown := 0;
  FHdrDrag := False;
  if Assigned(FHdrEv) then
    FHdrEv.Text := '0.0';
  ShowRasterImage(True);
  ShowImageTools(True);
  Name := ExtractFileName(ExcludeTrailingPathDelimiter(FPath));
  if Name = '' then
    Name := ExtractFileName(ALocal);
  FTitle.Text := Name + ' · ' + FHdrKind;
  SetHeaderPixels(FHdrW, FHdrH);
  if Assigned(FInfo) then
    FInfo.Visible := False;
  FInfoKey := '';
  LayoutImageFooter(nil);
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
  FLastSaved := '';
  HaveStamp := ReadPreviewStamp(APath, Age, Sz);
  if SameText(APath, FPath) and (APath <> '') and not AnimIsPlaying and
     HaveStamp and SamePreviewStamp(Age, FStampAge, Sz, FStampSize) then
    Exit;
  if not SameText(APath, FPath) then
  begin
    FLottieShowSource := False;
    FSvgShowSource := False;
  end;
  if FImgDirty and not SameText(APath, FPath) then
    ShowToast(L('qv.toast.failed'));
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
    FTitle.Text := L('qv.title');
    ShowInfoKey('qv.nofile');
    Exit;
  end;

  if (not TFile.Exists(Local)) and (not TDirectory.Exists(Local)) then
    MaterializeFile(APath, Local);
  if Local = '' then
    Local := APath;

  FTitle.Text := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  ShowMeta(Local);
  IsDir := TDirectory.Exists(APath);

  if IsDir or (ArchivePathIsFolder(APath) and
     not (TFile.Exists(APath) and IsArchiveFileName(APath))) then
  begin
    SetKindKey('qv.kind.folder');
    ShowPanorama(APath, not IsDir);
    Exit;
  end;

  if not TFile.Exists(Local) then
  begin
    ShowInfoKey('qv.unavailable');
    Exit;
  end;

  if IsOfficeLockFile(Local) then
  begin
    ShowInfoKey('qv.officelock');
    SetKindKey('qv.kind.lock');
    Exit;
  end;

  Ext := LowerCase(ExtractFileExt(Local));
  if IsHdrExt(Ext) then
  begin
    LoadHdrView(Local);
    Exit;
  end;
  if OpenLottieView(Local) then
    Exit;
  if OpenSvgView(Local) then
    Exit;
  if ExtIn(Ext, ['.exe', '.dll', '.sys', '.ocx', '.scr', '.cpl']) then
  begin
    ShowPe(Local);
    Exit;
  end;
  FSig := SniffImageFile(Local);
  if FSig = isPe then
  begin
    ShowPe(Local);
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
      if LoadAsThumb(Local) then
        AdoptRasterView
      else
      begin
        ShowInfoKey('qv.kind.nocodec');
        SetKindKey('qv.kind.nocodec');
      end;
      Exit;
    end;
  end;
  Kind := ClassifyExt(Ext);

  if Kind = PK_IMAGE then
  begin
    if LoadAsImage(Local) then
      Exit;
    if Ext = '.dxf' then
    begin
      ShowFileCard(Local);
      SetKindRaw('DXF');
      Exit;
    end;
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
          SetKindKey('qv.kind.mhtml')
        else
          SetKindKey('qv.kind.html');
        FMetaKey := 'qv.html.fail';
        if Assigned(FMeta) and (FMeta.Text <> '') then
          FMeta.Text := FMeta.Text + '    ' + L('qv.html.fail')
        else if Assigned(FMeta) then
          FMeta.Text := L('qv.html.fail');
        Exit;
      end;
    end;
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
      SetKindKey('qv.kind.media');
      AdoptRasterView;
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
         SetKindKey('qv.kind.slides');
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
    if (Ext = '.ai') and LoadAsImage(Local) then
      Exit;
    {$IFDEF MSWINDOWS}
    if LoadNativePreview(Local) then
    begin
      SetKindKey('qv.kind.pdf');
      Exit;
    end;
    {$ENDIF}
    if LoadAsThumb(Local) then
    begin
      SetKindKey('qv.kind.pdf');
      AdoptRasterView;
      Exit;
    end;
    ShowInfoKey('qv.pdf.fail');
    SetKindKey('qv.kind.pdf');
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
        SetKindKey('qv.kind.sheetlegacy');
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
      SetKindKey('qv.kind.doc');
      Exit;
    end;
    {$ENDIF}
    if LoadAsThumb(Local) then
    begin
      SetKindKey('qv.kind.doc');
      AdoptRasterView;
      Exit;
    end;
  end
  else if Kind = PK_MESH then
  begin
    StartMeshLoad(Local);
    Exit;
  end;

  FinishOrdinary(Local, Ext);
  finally
    if FCaptureKeys then
      FocusViewer;
  end;
end;

procedure TFilePreview.SetKindKey(const AKey: string);
begin
  FKindKey := AKey;
  if not Assigned(FKindText) then
    Exit;
  if AKey = 'qv.pdf.size' then
  begin
    ApplyPdfSizeText;
    Exit;
  end;
  if AKey = 'qv.vec.size' then
  begin
    ApplyMetaSizeText;
    Exit;
  end;
  FKindText.Width := 110;
  if AKey = '' then
    FKindText.Text := ''
  else if AKey = 'qv.kind.pdfn' then
  begin
    if FPdfPages > 1 then
      FKindText.Text := Lf('qv.kind.pdfn', [FPdfPage + 1, FPdfPages])
    else if FPdf <> nil then
      FKindText.Text := Lf('qv.kind.pdfn', [FPdfPage + 1, FPdf.PageCount])
    else
      FKindText.Text := L('qv.kind.pdf');
  end
  else if AKey = 'qv.kind.nocodec' then
    FKindText.Text := Lf('qv.kind.nocodec', [ImageSigName(FSig)])
  else
    FKindText.Text := L(AKey);
end;

procedure TFilePreview.SetKindRaw(const AText: string);
begin
  FKindKey := '';
  if not Assigned(FKindText) then
    Exit;
  FKindText.Text := AText;
  if Length(AText) > 18 then
    FKindText.Width := Max(110, Length(AText) * 7.4 + 12)
  else
    FKindText.Width := 110;
end;

procedure TFilePreview.ShowInfoKey(const AKey: string);
var
  Text: string;
begin
  if AKey = 'qv.officelock' then
    Text := LBreak(AKey)
  else if AKey = 'qv.kind.nocodec' then
    Text := Lf('qv.kind.nocodec', [ImageSigName(FSig)])
  else
    Text := L(AKey);
  ShowInfo(Text);
  FInfoKey := AKey;
end;

procedure TFilePreview.RefreshFontKind;
var
  Title: string;
begin
  Title := ContainerTitle(FFontProbe.Container);
  if Title = '' then
    Title := L('font.title');
  FKindKey := '';
  if not Assigned(FKindText) then
    Exit;
  FKindText.Width := 168;
  if FFontGlyphs > 0 then
    FKindText.Text := Title + ' · ' + IntToStr(FFontGlyphs)
  else
    FKindText.Text := Title;
end;

procedure TFilePreview.ApplyLanguage;
var
  Meta, S, Ext, Opens: string;
  Sheet: TSpreadSheet;
  Ix, I, N: Integer;
  SFI: TSHFileInfo;
  Buf: array[0..511] of Char;
  Len, Attr: DWORD;
  Parts: TArray<string>;

  procedure AddMeta(const Extra: string);
  begin
    if (Extra = '') or not Assigned(FMeta) then
      Exit;
    if FMeta.Text <> '' then
      FMeta.Text := FMeta.Text + '    ' + Extra
    else
      FMeta.Text := Extra;
  end;

begin
  if (FPath = '') and Assigned(FTitle) then
    FTitle.Text := L('qv.title');
  UpdateHtmlModeButtons;
  SyncZoomCaption;
  if (FIsAudio or FIsVideo) and Assigned(FBtnPlay) then
  begin
    if FMediaPaused then
    begin
      FBtnPlay.SetIcon(#$E768);
      FBtnPlay.SetCaption(L('qv.start'));
    end
    else
    begin
      FBtnPlay.SetIcon(#$E769);
      FBtnPlay.SetCaption(L('qv.stop'));
    end;
  end;
  if Assigned(FPeHexBtn) and FPeHexBtn.Visible then
  begin
    if FPeHex then
      FPeHexBtn.SetCaption(L('qv.card'))
    else
      FPeHexBtn.SetCaption(L('qv.hex'));
  end;
  if Assigned(FFileHex) and FFileHex.Visible then
  begin
    if FFileHexOn then
      FFileHex.SetCaption(L('qv.card'))
    else
      FFileHex.SetCaption(L('qv.hex'));
  end;
  if Assigned(FEditWarn) and (FEditWarn.Visible or FEditWarnOn) then
    FEditWarn.Text := L('qv.dirty');
  if Assigned(FFrameNote) then
    FFrameNote.Text := L('qv.frameword');
  if Assigned(FSigBar) and FSigBar.Visible then
    ShowSigBanner(FSig);
  if FFontOn then
    RefreshFontKind
  else if FMeshOn then
    ApplyMeshChrome
  else if FKindKey <> '' then
    SetKindKey(FKindKey);
  if (FHdrFailKey <> '') and not FHdrOn then
  begin
    if Assigned(FMeta) then
      FMeta.Text := L(FHdrFailKey);
    FFileType := L(FHdrFailKey);
    if Assigned(FFileBox) and FFileBox.Visible then
      FFileBox.Repaint;
  end;
  if (FKindKey = 'qv.kind.sheet') and (FBook <> nil) and Assigned(FMeta) then
  begin
    ShowMeta(FPath);
    Meta := '';
    Sheet := FBook.ActiveSheet;
    if Assigned(Sheet) then
    begin
      Meta := Format('%d × %d', [Sheet.RowCount, Sheet.ColCount]);
      if Sheet.Truncated then
        Meta := Meta + Lf('qv.sheet.limit', [SpreadQVMaxRows, SpreadQVMaxCols]);
    end;
    if FBook.EncodingLabel <> '' then
      Meta := Meta + '    ' + FBook.EncodingLabel;
    AddMeta(Meta);
  end
  else if (FKindKey = 'qv.kind.doc') and (FDoc <> nil) and Assigned(FMeta) then
  begin
    ShowMeta(FPath);
    Meta := Lf('qv.pages', [FDoc.Pages.Count]);
    if FDoc.Truncated then
      Meta := Meta + L('qv.partial');
    AddMeta(Meta);
  end
  else if Assigned(FTextBar) and FTextBar.Visible then
  begin
    UpdateTextStatus;
    if FMetaKey = 'qv.html.fail' then
      AddMeta(L('qv.html.fail'));
  end
  else if (FMetaKey = 'qv.html.fail') and Assigned(FMeta) then
  begin
    ShowMeta(FPath);
    AddMeta(L('qv.html.fail'));
  end
  else if (FKindKey = 'qv.kind.htmlie') and StartsText('qv.wv.', FMetaKey) and
     Assigned(FMeta) then
  begin
    ShowMeta(FPath);
    AddMeta(L(FMetaKey));
  end;
  if Assigned(FInfo) and FInfo.Visible and (FInfoKey <> '') then
    ShowInfoKey(FInfoKey);
  if Assigned(FSheetCombo) and (FBook = nil) and (FSheetCombo.Items.Count > 0) then
  begin
    N := 0;
    if FPdfPages > 0 then
      N := FPdfPages
    else if FPdf <> nil then
      N := FPdf.PageCount
    else if FDoc <> nil then
      N := FDoc.Pages.Count;
    if (N > 0) and (N = FSheetCombo.Items.Count) then
    begin
      Ix := FSheetCombo.ItemIndex;
      FSheetCombo.OnSelChange := nil;
      try
        FSheetCombo.Items.BeginUpdate;
        try
          FSheetCombo.Items.Clear;
          for I := 0 to N - 1 do
            FSheetCombo.Items.Add(Lf('qv.page.n', [I + 1]));
        finally
          FSheetCombo.Items.EndUpdate;
        end;
        if (Ix >= 0) and (Ix < FSheetCombo.Items.Count) then
          FSheetCombo.ItemIndex := Ix;
      finally
        FSheetCombo.OnSelChange := SheetComboChange;
      end;
      SyncSheetButtons;
    end;
  end;
  if FFontOn and Assigned(FFontFaces) and (Length(FFontProbe.Faces) > 0) then
  begin
    Ix := FFontFaces.ItemIndex;
    FFontSilence := True;
    try
      FFontFaces.Items.BeginUpdate;
      try
        FFontFaces.Items.Clear;
        for I := 0 to High(FFontProbe.Faces) do
        begin
          S := FFontProbe.Faces[I].Name;
          if S = '' then
            S := Lf('font.face', [I + 1]);
          if FFontFaces.Items.IndexOf(S) >= 0 then
            S := S + ' ' + IntToStr(I + 1);
          FFontFaces.Items.Add(S);
        end;
      finally
        FFontFaces.Items.EndUpdate;
      end;
      if (Ix >= 0) and (Ix < FFontFaces.Items.Count) then
        FFontFaces.ItemIndex := Ix;
    finally
      FFontSilence := False;
    end;
  end;
  if Assigned(FSaveShade) and FSaveShade.Visible and Assigned(FSaveFmt) then
  begin
    Ix := FSaveFmt.ItemIndex;
    if FSaveFont then
      FillFontFormats
    else if FSaveMedia then
      FillMediaFormats
    else
      FillImageFormats;
    FSaveSilence := True;
    try
      if (Ix >= 0) and (Ix < FSaveFmt.Items.Count) then
        FSaveFmt.ItemIndex := Ix;
    finally
      FSaveSilence := False;
    end;
    RefreshSaveExists;
    LayoutSaveCard(nil);
    if FSaveFont and Assigned(FSaveNote) then
    begin
      FSaveNote.Text := L('font.woff2');
      FSaveNote.Visible := not BrotliBesideExe;
    end;
  end;
  if (FPath <> '') and TFile.Exists(FPath) and
     ((Assigned(FFileBox) and FFileBox.Visible) or FFileHexOn) then
  begin
    Ext := LowerCase(ExtractFileExt(FPath));
    FillChar(SFI, SizeOf(SFI), 0);
    FFileType := '';
    if SHGetFileInfo(PChar(FPath), 0, SFI, SizeOf(SFI), SHGFI_TYPENAME) <> 0 then
      FFileType := Trim(string(SFI.szTypeName));
    if FFileType = '' then
    begin
      if Ext = '' then
        FFileType := L('qv.file.kind')
      else
        FFileType := UpperCase(Copy(Ext, 2, 12));
    end;
    Opens := '';
    if Ext <> '' then
    begin
      Len := Length(Buf);
      if Succeeded(AssocQueryString(ASSOCF_NOTRUNCATE, ASSOCSTR(4),
        PChar(Ext), nil, Buf, @Len)) then
        Opens := Trim(string(Buf));
      if Opens = '' then
      begin
        Len := Length(Buf);
        if Succeeded(AssocQueryString(ASSOCF_NOTRUNCATE, ASSOCSTR(2),
          PChar(Ext), nil, Buf, @Len)) then
          Opens := ExtractFileName(Trim(string(Buf)));
      end;
    end;
    if Opens = '' then
      Opens := L('qv.file.unassigned');
    FFileOpens := Opens;
    SetLength(Parts, 0);
    Attr := GetFileAttributes(PChar(FPath));
    if Attr <> INVALID_FILE_ATTRIBUTES then
    begin
      if (Attr and FILE_ATTRIBUTE_READONLY) <> 0 then
        Parts := Parts + [L('qv.file.readonly')];
      if (Attr and FILE_ATTRIBUTE_HIDDEN) <> 0 then
        Parts := Parts + [L('qv.file.hidden')];
      if (Attr and FILE_ATTRIBUTE_SYSTEM) <> 0 then
        Parts := Parts + [L('qv.file.system')];
      FFileAttrs := string.Join(', ', Parts);
    end;
    if (FKindKey = '') and (not FFileHexOn) then
      SetKindRaw(FFileType);
  end;
  if Assigned(FPeBox) then
    FPeBox.Repaint;
  if Assigned(FFileBox) then
    FFileBox.Repaint;
  if Assigned(FPanoBox) then
    FPanoBox.Repaint;
  if Assigned(FFontMap) then
    FFontMap.Repaint;
  if Assigned(FFontSampleBox) then
    FFontSampleBox.Repaint;
  if Assigned(FFontPlatePaint) then
    FFontPlatePaint.Repaint;
  if Assigned(FDocView) then
    FDocView.Repaint;
  if Assigned(FCodeView) then
    FCodeView.Repaint;
  Repaint;
end;

procedure TFilePreview.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  { Mica/Acrylic: фон просмотра без собственной плашки, чтобы не смешивать
    её со списком. Список на это время прячет панель. }
  if TAlphaColorRec(AColors.PanelBackground).A < 255 then
    Fill.Color := TAlphaColors.Null
  else
    Fill.Color := AColors.PanelBackground;
  if Assigned(FHeader) then
    FHeader.Fill.Color := AColors.HeaderBackground;
  if Assigned(FTitle) then
    FTitle.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FKindText) then
    FKindText.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FMeta) then
    FMeta.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FMeshHint) then
    FMeshHint.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FInfo) then
    FInfo.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FPanoBox) and FPanoBox.Visible then
    FPanoBox.Repaint;
  if Assigned(FFontSample) then
    FFontSample.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FFontPhrase) then
    FFontPhrase.ApplyTheme(AColors);
  if Assigned(FFontFaces) then
    FFontFaces.ApplyTheme(AColors);
  if Assigned(FFontBtnLatin) then
    FFontBtnLatin.ApplyTheme(AColors);
  if Assigned(FFontBtnCyr) then
    FFontBtnCyr.ApplyTheme(AColors);
  if Assigned(FFontBtnDigit) then
    FFontBtnDigit.ApplyTheme(AColors);
  if Assigned(FFontBtnAll) then
    FFontBtnAll.ApplyTheme(AColors);
  if Assigned(FBtnFontSave) then
    FBtnFontSave.ApplyTheme(AColors);
  if Assigned(FBtnCopyChar) then
    FBtnCopyChar.ApplyTheme(AColors);
  if Assigned(FBtnCopyCode) then
    FBtnCopyCode.ApplyTheme(AColors);
  if Assigned(FBtnCopyHtml) then
    FBtnCopyHtml.ApplyTheme(AColors);
  if Assigned(FFontVScroll) then
    FFontVScroll.ApplyTheme(AColors);
  if Assigned(FFontSampleBox) and FFontSampleBox.Visible then
    FFontSampleBox.Repaint;
  if Assigned(FFontSlider) and FFontSlider.Visible then
    FFontSlider.Repaint;
  if Assigned(FFontMap) and FFontMap.Visible then
    FFontMap.Repaint;
  if Assigned(FFontPlatePaint) and FFontPlatePaint.Visible then
    FFontPlatePaint.Repaint;
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
  if Assigned(FIcoScroll) then
    FIcoScroll.ApplyTheme(AColors);
  if Assigned(FEditScrollBar) then
    FEditScrollBar.ApplyTheme(AColors);
  if Assigned(FGrid) then
    FGrid.ApplyTheme(AColors);
  if Assigned(FDocView) then
    FDocView.ApplyTheme(AColors);
  if Assigned(FSheetCombo) then
    FSheetCombo.ApplyTheme(AColors);
  if Assigned(FBtnSheetBack) then
    FBtnSheetBack.ApplyTheme(AColors);
  if Assigned(FBtnSheetFwd) then
    FBtnSheetFwd.ApplyTheme(AColors);
  ApplyImageTheme;
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
  if Assigned(FBtnSaveFrame) then
    FBtnSaveFrame.ApplyTheme(AColors);
  if Assigned(FBtnKindClip) then
    FBtnKindClip.ApplyTheme(AColors);
  if Assigned(FBtnKindFrame) then
    FBtnKindFrame.ApplyTheme(AColors);
  if Assigned(FBtnKindAudio) then
    FBtnKindAudio.ApplyTheme(AColors);
  if Assigned(FSaveRange) then
    FSaveRange.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FTimeText) then
    FTimeText.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FWaveBox) then
    FWaveBox.Repaint;
  if Assigned(FSeekBox) then
    FSeekBox.Repaint;
  SyncMemoScroll;
end;

end.
