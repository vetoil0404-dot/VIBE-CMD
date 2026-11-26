unit uBinConfirmDialog;

{
  Підтвердження очищення кошика.
  Каркас як у TConflictDialog. Типово активна скасувати.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics,
  {$IFDEF MSWINDOWS}Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,{$ENDIF}
  uThemeManager, uFluentChrome;

function ShowBinConfirm(AOwner: TCommonCustomForm; const AText: string): Boolean;

implementation

uses
  uLang, uLangBind;

const
  DLG_W = 460;
  DLG_H = 210;

type
  TBinConfirmDialog = class(TForm)
  private
    FColors: TThemeColors;
    FText: string;
    FRoot: TRectangle;
    FTitle, FBody: TText;
    FBtnOk, FBtnCancel: TFluentButton;
    FKeyBtn: TFluentButton;
    procedure BuildUI;
    procedure ApplyNativeChrome;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ArmClick(Sender: TObject);
    procedure SetKeyBtn(AButton: TFluentButton);
    procedure CollectKeyRow(out ARow: TArray<TFluentButton>);
    procedure SyncKeyFocus;
    procedure MoveKeyFocus(ADelta: Integer);
    procedure PressKeyBtn;
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
  public
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
    constructor Create(AOwner: TComponent; const AText: string); reintroduce;
  end;

function MkText(AOwner: TComponent; AParent: TFmxObject; ASize: Single;
  ABold: Boolean; AColor: TAlphaColor; AAlign: TAlignLayout): TText;
begin
  Result := TText.Create(AOwner);
  Result.Parent := AParent;
  Result.HitTest := False;
  Result.Align := AAlign;
  ApplyFluentText(Result, ASize, ABold);
  Result.TextSettings.FontColor := AColor;
  Result.TextSettings.HorzAlign := TTextAlign.Leading;
  Result.TextSettings.VertAlign := TTextAlign.Center;
end;

function ShowBinConfirm(AOwner: TCommonCustomForm; const AText: string): Boolean;
var
  Dlg: TBinConfirmDialog;
begin
  Result := False;
  if (AOwner <> nil) and (csDestroying in AOwner.ComponentState) then
    Exit;
  Dlg := TBinConfirmDialog.Create(AOwner, AText);
  try
    Result := Dlg.ShowModal = mrOk;
  finally
    Dlg.Free;
  end;
end;

constructor TBinConfirmDialog.Create(AOwner: TComponent; const AText: string);
begin
  inherited CreateNew(AOwner);
  FText := AText;
  FColors := GetThemeColors(ActiveAppTheme);
  Width := DLG_W;
  Height := DLG_H;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  TrForm(Self, 'bin.title');
  if AOwner <> nil then
    Position := TFormPosition.OwnerFormCenter
  else
    Position := TFormPosition.MainFormCenter;
  BuildUI;
  ApplyNativeChrome;
end;

procedure TBinConfirmDialog.ApplyNativeChrome;
{$IFDEF MSWINDOWS}
var
  Wnd: HWND;
  Corner: Integer;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  ApplyNativeWindowChrome(FormToHWND(Self), FColors.IsDark);
  Wnd := FormToHWND(Self);
  if Wnd <> 0 then
  begin
    Corner := 2;
    DwmSetWindowAttribute(Wnd, 33, @Corner, SizeOf(Corner));
  end;
{$ENDIF}
end;

procedure TBinConfirmDialog.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TBinConfirmDialog.DoShow;
begin
  inherited;
  ApplyNativeChrome;
  SyncKeyFocus;
end;

procedure TBinConfirmDialog.ArmClick(Sender: TObject);
begin
  if (Sender is TFluentButton) and FluentButtonLive(TFluentButton(Sender)) then
    SetKeyBtn(TFluentButton(Sender));
end;

procedure TBinConfirmDialog.SetKeyBtn(AButton: TFluentButton);
begin
  if FKeyBtn = AButton then
  begin
    if Assigned(FKeyBtn) then
      FKeyBtn.SetKeyFocus(True);
    Exit;
  end;
  if Assigned(FKeyBtn) then
    FKeyBtn.SetKeyFocus(False);
  FKeyBtn := AButton;
  if Assigned(FKeyBtn) then
    FKeyBtn.SetKeyFocus(True);
end;

procedure TBinConfirmDialog.CollectKeyRow(out ARow: TArray<TFluentButton>);
  procedure AddLive(AButton: TFluentButton);
  var
    N: Integer;
  begin
    if not FluentButtonLive(AButton) then
      Exit;
    N := Length(ARow);
    SetLength(ARow, N + 1);
    ARow[N] := AButton;
  end;
begin
  SetLength(ARow, 0);
  AddLive(FBtnOk);
  AddLive(FBtnCancel);
end;

procedure TBinConfirmDialog.SyncKeyFocus;
var
  Row: TArray<TFluentButton>;
  I: Integer;
begin
  CollectKeyRow(Row);
  if Assigned(FKeyBtn) then
    for I := 0 to High(Row) do
      if Row[I] = FKeyBtn then
      begin
        FKeyBtn.SetKeyFocus(True);
        Exit;
      end;
  if FluentButtonLive(FBtnCancel) then
    SetKeyBtn(FBtnCancel)
  else if Length(Row) > 0 then
    SetKeyBtn(Row[0])
  else
    SetKeyBtn(nil);
end;

procedure TBinConfirmDialog.MoveKeyFocus(ADelta: Integer);
var
  Row: TArray<TFluentButton>;
  I, At, N: Integer;
  Found: Boolean;
begin
  CollectKeyRow(Row);
  N := Length(Row);
  if N = 0 then
    Exit;
  Found := False;
  At := 0;
  if Assigned(FKeyBtn) then
    for I := 0 to High(Row) do
      if Row[I] = FKeyBtn then
      begin
        At := I;
        Found := True;
        Break;
      end;
  if not Found then
  begin
    SyncKeyFocus;
    Exit;
  end;
  At := (At + ADelta) mod N;
  if At < 0 then
    Inc(At, N);
  SetKeyBtn(Row[At]);
end;

procedure TBinConfirmDialog.PressKeyBtn;
begin
  SyncKeyFocus;
  if Assigned(FKeyBtn) and FluentButtonLive(FKeyBtn) then
    FKeyBtn.Invoke;
end;

procedure TBinConfirmDialog.OkClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TBinConfirmDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TBinConfirmDialog.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
var
  Plain: Boolean;
begin
  if Key in [vkF2..vkF8] then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  Plain := not (ssAlt in Shift) and not (ssCtrl in Shift);
  if Plain and ((Key = vkLeft) or (Key = vkRight) or (Key = vkTab)) then
  begin
    if (Key = vkLeft) or ((Key = vkTab) and (ssShift in Shift)) then
      MoveKeyFocus(-1)
    else
      MoveKeyFocus(1);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if Plain and ((Key = vkUp) or (Key = vkDown)) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if Key = vkEscape then
  begin
    Key := 0;
    KeyChar := #0;
    CancelClick(nil);
    Exit;
  end;
  if (Key = vkReturn) or (Key = vkSpace) then
  begin
    Key := 0;
    KeyChar := #0;
    PressKeyBtn;
    Exit;
  end;
  inherited;
end;

procedure TBinConfirmDialog.BuildUI;
var
  Foot: TLayout;
begin
  FRoot := TRectangle.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Stroke.Kind := TBrushKind.None;
  FRoot.Fill.Color := FColors.Background;
  FRoot.Padding.Rect := TRectF.Create(18, 14, 18, 14);

  Foot := TLayout.Create(Self);
  Foot.Parent := FRoot;
  Foot.Align := TAlignLayout.Bottom;
  Foot.Height := 40;
  Foot.Margins.Top := 14;

  FBtnCancel := CreateFluentButton(Self, Foot, '', L('ask.cancel'),
    fbkStandard, 140, CancelClick);
  TrButton(FBtnCancel, 'ask.cancel');
  FBtnCancel.Align := TAlignLayout.Right;
  FBtnOk := CreateFluentButton(Self, Foot, '', L('ask.ok'),
    fbkStandard, 140, OkClick);
  TrButton(FBtnOk, 'ask.ok');
  FBtnOk.Align := TAlignLayout.Right;
  FBtnOk.Margins.Right := 8;
  FBtnOk.CanFocus := False;
  FBtnCancel.CanFocus := False;
  FBtnOk.TabStop := False;
  FBtnCancel.TabStop := False;
  FBtnOk.OnArm := ArmClick;
  FBtnCancel.OnArm := ArmClick;

  FTitle := MkText(Self, FRoot, 18, True, FColors.TextColor, TAlignLayout.Top);
  FTitle.Height := 28;
  TrText(FTitle, 'bin.title');

  FBody := MkText(Self, FRoot, 14, False, FColors.TextColor, TAlignLayout.Client);
  FBody.Margins.Top := 8;
  FBody.Text := FText;
  FBody.TextSettings.VertAlign := TTextAlign.Leading;
  FBody.TextSettings.WordWrap := True;
  FBody.TextSettings.Trimming := TTextTrimming.None;

  ApplyTheme(FColors);
  SyncKeyFocus;
end;

procedure TBinConfirmDialog.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  if Assigned(FRoot) then
    FRoot.Fill.Color := AColors.Background;
  if Assigned(FTitle) then
    FTitle.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBody) then
    FBody.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FBtnOk) then
    FBtnOk.ApplyTheme(AColors);
  if Assigned(FBtnCancel) then
    FBtnCancel.ApplyTheme(AColors);
  ApplyNativeChrome;
end;

end.
