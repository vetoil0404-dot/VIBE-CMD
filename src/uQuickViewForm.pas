unit uQuickViewForm;

{
  Отдельное окно просмотра (F3).
  FollowFile меняет файл, не открывая окно и не забирая фокус.
  Курсор панели отсюда не двигается.
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Types,
  FMX.Forms, FMX.Types, FMX.Layouts, FMX.Graphics, FMX.Objects,
  uThemeManager, uFilePreview, uLang;

type
  TQuickViewForm = class(TForm)
  private
    FPreview: TFilePreview;
    FDark: Boolean;
    procedure ApplyNativeChrome;
    procedure PreviewDiskChanged(Sender: TObject);
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
    procedure ShowFile(const APath: string);
    { Тот же Load, без Show, Activate и фокуса. Тот же путь не грузится снова. }
    procedure FollowFile(const APath: string);
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ApplyLanguage;
  end;

implementation

uses
  uFilePanel
  {$IFDEF MSWINDOWS}, Winapi.Windows, FMX.Platform.Win{$ENDIF};

constructor TQuickViewForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Width := 960;
  Height := 720;
  BorderStyle := TFmxFormBorderStyle.Sizeable;
  BorderIcons := [TBorderIcon.biSystemMenu, TBorderIcon.biMaximize, TBorderIcon.biMinimize];
  Caption := L('qv.title');
  Position := TFormPosition.ScreenCenter;
  FPreview := TFilePreview.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := TAlignLayout.Client;
  FPreview.ShowCloseButton := False;
  FPreview.CaptureKeys := True;
  FPreview.OnDiskChanged := PreviewDiskChanged;
  FPreview.Margins.Rect := TRectF.Create(8, 8, 8, 8);
end;

procedure TQuickViewForm.PreviewDiskChanged(Sender: TObject);
begin
  NotifyPreviewSaved(Sender);
end;

procedure TQuickViewForm.ApplyNativeChrome;
begin
  {$IFDEF MSWINDOWS}
  ApplyNativeWindowChrome(FormToHWND(Self), FDark);
  {$ENDIF}
end;

procedure TQuickViewForm.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TQuickViewForm.DoShow;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TQuickViewForm.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  inherited;
  if Key = 0 then
    Exit;
  if Assigned(FPreview) and FPreview.HandleFontKey(Key, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
  end;
end;

procedure TQuickViewForm.ShowFile(const APath: string);
begin
  Caption := ExtractFileName(APath);
  if Caption = '' then
    Caption := L('qv.title');
  FPreview.LoadFile(APath);
  Show;
  BringToFront;
  Activate;
  if Assigned(FPreview) then
    FPreview.FocusViewer;
end;

procedure TQuickViewForm.FollowFile(const APath: string);
var
  Name: string;
begin
  if (APath = '') or not Visible or not Assigned(FPreview) then
    Exit;
  if SameText(ExcludeTrailingPathDelimiter(APath),
              ExcludeTrailingPathDelimiter(FPreview.FilePath)) then
    Exit;
  Name := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if Name = '' then
    Name := L('qv.title');
  Caption := Name;
  FPreview.LoadFile(APath);
end;

procedure TQuickViewForm.ApplyLanguage;
var
  Name: string;
begin
  Name := '';
  if Assigned(FPreview) then
    Name := ExtractFileName(ExcludeTrailingPathDelimiter(FPreview.FilePath));
  if Name = '' then
    Caption := L('qv.title')
  else
    Caption := Name;
  if Assigned(FPreview) then
    FPreview.ApplyLanguage;
end;

procedure TQuickViewForm.ApplyTheme(const AColors: TThemeColors);
begin
  FDark := AColors.IsDark;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  if Assigned(FPreview) then
    FPreview.ApplyTheme(AColors);
  ApplyNativeChrome;
end;

end.
