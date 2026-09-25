unit uQuickViewForm;

{
  Отдельное окно просмотра (F3). Не зависит от панелей и курсора.
}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Types,
  FMX.Forms, FMX.Types, FMX.Layouts, FMX.Graphics, FMX.Objects,
  uThemeManager, uFilePreview;

type
  TQuickViewForm = class(TForm)
  private
    FPreview: TFilePreview;
    FDark: Boolean;
    procedure ApplyNativeChrome;
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowFile(const APath: string);
    procedure ApplyTheme(const AColors: TThemeColors) ;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}Winapi.Windows, FMX.Platform.Win{$ENDIF};

constructor TQuickViewForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Width := 960;
  Height := 720;
  BorderStyle := TFmxFormBorderStyle.Sizeable;
  BorderIcons := [TBorderIcon.biSystemMenu, TBorderIcon.biMaximize, TBorderIcon.biMinimize];
  Caption := 'Просмотр';
  Position := TFormPosition.ScreenCenter;
  FPreview := TFilePreview.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := TAlignLayout.Client;
  FPreview.ShowCloseButton := False;
  FPreview.CaptureKeys := True;
  FPreview.Margins.Rect := TRectF.Create(8, 8, 8, 8);
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

procedure TQuickViewForm.ShowFile(const APath: string);
begin
  Caption := ExtractFileName(APath);
  if Caption = '' then
    Caption := 'Просмотр';
  FPreview.LoadFile(APath);
  Show;
  BringToFront;
  Activate;
  if Assigned(FPreview) then
    FPreview.FocusViewer;
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
