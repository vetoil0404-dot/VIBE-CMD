program VibeCmd;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  uMain in 'uMain.pas',
  uFilePanel in 'uFilePanel.pas',
  uFileModel in 'uFileModel.pas',
  uArchiveEngine in 'uArchiveEngine.pas',
  uThumbCache in 'uThumbCache.pas',
  uIconCache in 'uIconCache.pas',
  uWinFileDrag in 'uWinFileDrag.pas',
  uClipboardImage in 'uClipboardImage.pas',
  uWinBrowserDrop in 'uWinBrowserDrop.pas',
  uWinShellMenu in 'uWinShellMenu.pas',
  uDirWatcher in 'uDirWatcher.pas',
  uThemeManager in 'uThemeManager.pas',
  uFluentChrome in 'uFluentChrome.pas',
  uFluentEdit in 'uFluentEdit.pas',
  uFluentComboBox in 'uFluentComboBox.pas',
  uFluentDatePicker in 'uFluentDatePicker.pas',
  uDriveBar in 'uDriveBar.pas',
  uLaunchDock in 'uLaunchDock.pas',
  uAppSettings in 'uAppSettings.pas',
  uFileOps in 'uFileOps.pas',
  uFileOpEngine in 'uFileOpEngine.pas',
  uFileOpProgressForm in 'uFileOpProgressForm.pas',
  uConflictDialog in 'uConflictDialog.pas',
  uFilePreview in 'uFilePreview.pas',
  uQuickViewForm in 'uQuickViewForm.pas',
  uSettingsForm in 'uSettingsForm.pas',
  uMultiRename in 'uMultiRename.pas',
  uMultiRenameForm in 'uMultiRenameForm.pas',
  uFileSearch in 'uFileSearch.pas',
  uSearchForm in 'uSearchForm.pas',
  uSpreadsheetData in 'uSpreadsheetData.pas',
  uSpreadsheetGrid in 'uSpreadsheetGrid.pas',
  uDocumentData in 'uDocumentData.pas',
  uDocumentView in 'uDocumentView.pas',
  uTextCode in 'uTextCode.pas',
  uCodeView in 'uCodeView.pas',
  uImageSniff in 'uImageSniff.pas',
  uPdfium in 'uPdfium.pas',
  uPsdPreview in 'uPsdPreview.pas',
  uMpvPlayer in 'uMpvPlayer.pas',
  uMetaCache in 'uMetaCache.pas';

{$R *.res}

begin
  NoteAppStart;
  if TryActivateRunningInstance then
    Halt(0);
  GlobalUseSkia := True;
{$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
