unit uMapDriveDialog;

{
  Підключити шару літерою диска.
  Каркас як у TConflictDialog: без системних кнопки, комбо і чекбокса.
}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics,
  {$IFDEF MSWINDOWS}Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,{$ENDIF}
  uThemeManager, uFluentChrome, uFluentComboBox;

function ShowMapDriveDialog(AOwner: TCommonCustomForm; const AUnc: string;
  const ALetters: TArray<string>; out ALetter: string; out ARestore: Boolean): Boolean;

implementation

uses
  uLang, uLangBind;

const
  DLG_W = 460;
  PAD_X = 18;
  PAD_TOP = 16;
  PAD_BOT = 16;
  TITLE_H = 28;
  PATH_H = 22;
  LBL_H = 20;
  COMBO_H = 36;
  CHECK_H = 36;
  BTN_H = 36;
  BTN_W = 140;
  BTN_GAP = 8;

type
  TMapDriveDialog = class(TForm)
  private
    FColors: TThemeColors;
    FUnc: string;
    FLetters: TArray<string>;
    FLetter: string;
    FRestore: Boolean;
    FRoot: TRectangle;
    FTitle, FPath, FLetterLbl: TText;
    FCombo: TFluentComboBox;
    FRestoreRow: TFluentCheckRow;
    FBtnOk, FBtnCancel: TFluentButton;
    FKeyBtn: TFluentButton;
    procedure BuildUI;
    procedure PlaceControls;
    procedure RootResize(Sender: TObject);
    function ContentHeight: Single;
    procedure ApplyNativeChrome;
    procedure ApplyTheme(const AColors: TThemeColors);
    procedure ArmClick(Sender: TObject);
    procedure SetKeyBtn(AButton: TFluentButton);
    procedure CollectKeyRow(out ARow: TArray<TFluentButton>);
    procedure SyncKeyFocus;
    procedure MoveKeyFocus(ADelta: Integer);
    procedure PressKeyBtn;
    function DropOwnsKey: Boolean;
    function ChosenLetter: string;
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure ComboSubmit(Sender: TObject);
    procedure ComboEscape(Sender: TObject);
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
  public
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
    constructor Create(AOwner: TComponent; const AUnc: string;
      const ALetters: TArray<string>); reintroduce;
    property Letter: string read FLetter;
    property Restore: Boolean read FRestore;
  end;

function MkText(AOwner: TComponent; AParent: TFmxObject; ASize: Single;
  ABold: Boolean; AColor: TAlphaColor): TText;
begin
  Result := TText.Create(AOwner);
  Result.Parent := AParent;
  Result.HitTest := False;
  Result.Align := TAlignLayout.None;
  ApplyFluentText(Result, ASize, ABold);
  Result.TextSettings.FontColor := AColor;
  Result.TextSettings.HorzAlign := TTextAlign.Leading;
  Result.TextSettings.VertAlign := TTextAlign.Center;
end;

function ShowMapDriveDialog(AOwner: TCommonCustomForm; const AUnc: string;
  const ALetters: TArray<string>; out ALetter: string; out ARestore: Boolean): Boolean;
var
  Dlg: TMapDriveDialog;
begin
  ALetter := '';
  ARestore := True;
  Result := False;
  if Length(ALetters) = 0 then
    Exit;
  if (AOwner <> nil) and (csDestroying in AOwner.ComponentState) then
    Exit;
  Dlg := TMapDriveDialog.Create(AOwner, AUnc, ALetters);
  try
    if Dlg.ShowModal <> mrOk then
      Exit;
    ALetter := Dlg.Letter;
    ARestore := Dlg.Restore;
    Result := ALetter <> '';
  finally
    Dlg.Free;
  end;
end;

constructor TMapDriveDialog.Create(AOwner: TComponent; const AUnc: string;
  const ALetters: TArray<string>);
begin
  inherited CreateNew(AOwner);
  FUnc := AUnc;
  FLetters := Copy(ALetters);
  FRestore := True;
  FColors := GetThemeColors(ActiveAppTheme);
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  TrForm(Self, 'panel.net.map');
  BuildUI;
  if AOwner <> nil then
    Position := TFormPosition.OwnerFormCenter
  else
    Position := TFormPosition.MainFormCenter;
  ApplyNativeChrome;
end;

procedure TMapDriveDialog.ApplyNativeChrome;
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

procedure TMapDriveDialog.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TMapDriveDialog.DoShow;
begin
  inherited;
  ApplyNativeChrome;
  PlaceControls;
  SyncKeyFocus;
end;

procedure TMapDriveDialog.ArmClick(Sender: TObject);
begin
  if (Sender is TFluentButton) and FluentButtonLive(TFluentButton(Sender)) then
    SetKeyBtn(TFluentButton(Sender));
end;

procedure TMapDriveDialog.SetKeyBtn(AButton: TFluentButton);
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

procedure TMapDriveDialog.CollectKeyRow(out ARow: TArray<TFluentButton>);
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

procedure TMapDriveDialog.SyncKeyFocus;
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
  if FluentButtonLive(FBtnOk) then
    SetKeyBtn(FBtnOk)
  else if Length(Row) > 0 then
    SetKeyBtn(Row[0])
  else
    SetKeyBtn(nil);
end;

procedure TMapDriveDialog.MoveKeyFocus(ADelta: Integer);
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

procedure TMapDriveDialog.PressKeyBtn;
begin
  SyncKeyFocus;
  if Assigned(FKeyBtn) and FluentButtonLive(FKeyBtn) then
    FKeyBtn.Invoke;
end;

function TMapDriveDialog.DropOwnsKey: Boolean;
begin
  Result := Assigned(FCombo) and FCombo.IsDropOpen;
end;

function TMapDriveDialog.ChosenLetter: string;
var
  I: Integer;
  Txt: string;
begin
  Result := '';
  if (FCombo = nil) or (FCombo.Items = nil) then
    Exit;
  if (FCombo.ItemIndex >= 0) and (FCombo.ItemIndex < FCombo.Items.Count) then
    Exit(FCombo.Items[FCombo.ItemIndex]);
  Txt := Trim(FCombo.Text);
  if Txt = '' then
    Exit;
  for I := 0 to FCombo.Items.Count - 1 do
    if SameText(Trim(FCombo.Items[I]), Txt) then
      Exit(FCombo.Items[I]);
end;

procedure TMapDriveDialog.OkClick(Sender: TObject);
var
  Letter: string;
begin
  Letter := ChosenLetter;
  if Letter = '' then
    Exit;
  FLetter := Letter;
  FRestore := Assigned(FRestoreRow) and FRestoreRow.Checked;
  ModalResult := mrOk;
end;

procedure TMapDriveDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TMapDriveDialog.ComboSubmit(Sender: TObject);
begin
  PressKeyBtn;
end;

procedure TMapDriveDialog.ComboEscape(Sender: TObject);
begin
  CancelClick(Sender);
end;

procedure TMapDriveDialog.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
var
  Plain: Boolean;
begin
  if Key in [vkF2..vkF8] then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  { Відкритий список літер сам їсть стрілки, Enter і Esc. }
  if DropOwnsKey then
  begin
    inherited;
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

procedure TMapDriveDialog.RootResize(Sender: TObject);
begin
  PlaceControls;
end;

procedure TMapDriveDialog.PlaceControls;
var
  W, H, Inner, Y, BtnY: Single;
begin
  if not Assigned(FRoot) or not Assigned(FTitle) then
    Exit;
  W := FRoot.Width;
  H := FRoot.Height;
  if W < 80 then
  begin
    W := ClientWidth;
    if W < 80 then
      W := DLG_W;
  end;
  if H < 40 then
    H := ClientHeight;
  Inner := W - PAD_X * 2;
  if Inner < 160 then
    Inner := 160;

  FTitle.Align := TAlignLayout.None;
  FLetterLbl.Align := TAlignLayout.None;
  FCombo.Align := TAlignLayout.None;
  FRestoreRow.Align := TAlignLayout.None;
  FBtnOk.Align := TAlignLayout.None;
  FBtnCancel.Align := TAlignLayout.None;
  if Assigned(FPath) then
    FPath.Align := TAlignLayout.None;

  Y := PAD_TOP;
  FTitle.SetBounds(PAD_X, Y, Inner, TITLE_H);
  Y := Y + TITLE_H;
  if Assigned(FPath) and FPath.Visible then
  begin
    Y := Y + 4;
    FPath.SetBounds(PAD_X, Y, Inner, PATH_H);
    Y := Y + PATH_H;
  end;
  Y := Y + 14;
  FLetterLbl.SetBounds(PAD_X, Y, Inner, LBL_H);
  Y := Y + LBL_H + 6;
  FCombo.SetBounds(PAD_X, Y, Inner, COMBO_H);
  Y := Y + COMBO_H + 12;
  FRestoreRow.SetBounds(PAD_X, Y, Inner, CHECK_H);
  Y := Y + CHECK_H + 18;

  BtnY := Y;
  if H >= Y + BTN_H + PAD_BOT then
    BtnY := H - PAD_BOT - BTN_H;
  FBtnCancel.SetBounds(PAD_X + Inner - BTN_W, BtnY, BTN_W, BTN_H);
  FBtnOk.SetBounds(PAD_X + Inner - BTN_W * 2 - BTN_GAP, BtnY, BTN_W, BTN_H);
end;

function TMapDriveDialog.ContentHeight: Single;
begin
  Result := PAD_TOP + TITLE_H;
  if FUnc <> '' then
    Result := Result + 4 + PATH_H;
  Result := Result + 14 + LBL_H + 6 + COMBO_H + 12 + CHECK_H + 18 + BTN_H + PAD_BOT;
end;

procedure TMapDriveDialog.BuildUI;
var
  I: Integer;
begin
  FRoot := TRectangle.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Stroke.Kind := TBrushKind.None;
  FRoot.Fill.Color := FColors.Background;
  FRoot.OnResize := RootResize;

  FBtnCancel := CreateFluentButton(Self, FRoot, '', L('panel.net.map.cancel'),
    fbkStandard, BTN_W, CancelClick);
  TrButton(FBtnCancel, 'panel.net.map.cancel');
  FBtnOk := CreateFluentButton(Self, FRoot, '', L('panel.net.map.ok'),
    fbkStandard, BTN_W, OkClick);
  TrButton(FBtnOk, 'panel.net.map.ok');
  FBtnOk.Align := TAlignLayout.None;
  FBtnCancel.Align := TAlignLayout.None;
  FBtnOk.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FBtnCancel.Margins.Rect := TRectF.Create(0, 0, 0, 0);
  FBtnOk.CanFocus := False;
  FBtnCancel.CanFocus := False;
  FBtnOk.TabStop := False;
  FBtnCancel.TabStop := False;
  FBtnOk.OnArm := ArmClick;
  FBtnCancel.OnArm := ArmClick;

  FTitle := MkText(Self, FRoot, 18, True, FColors.TextColor);
  TrText(FTitle, 'panel.net.map');

  FPath := MkText(Self, FRoot, 13, False, FColors.SubTextColor);
  FPath.Text := FUnc;
  FPath.TextSettings.Trimming := TTextTrimming.Character;
  FPath.TextSettings.WordWrap := False;
  FPath.Visible := FUnc <> '';

  FLetterLbl := MkText(Self, FRoot, 13, False, FColors.TextColor);
  TrText(FLetterLbl, 'panel.net.map.letter');

  FCombo := TFluentComboBox.Create(Self);
  FCombo.Parent := FRoot;
  FCombo.Align := TAlignLayout.None;
  FCombo.DropListOnly := True;
  for I := 0 to High(FLetters) do
    FCombo.Items.Add(FLetters[I]);
  if FCombo.Items.Count > 0 then
    FCombo.ItemIndex := 0;
  FCombo.OnSubmit := ComboSubmit;
  FCombo.OnEscape := ComboEscape;

  FRestoreRow := TFluentCheckRow.Create(Self);
  FRestoreRow.Setup(FRoot, L('panel.net.map.restore'), True);
  TrCheck(FRestoreRow, 'panel.net.map.restore');
  FRestoreRow.Align := TAlignLayout.None;

  ClientWidth := DLG_W;
  ClientHeight := Round(ContentHeight);
  ApplyTheme(FColors);
  PlaceControls;
  SyncKeyFocus;
end;

procedure TMapDriveDialog.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  if Assigned(FRoot) then
    FRoot.Fill.Color := AColors.Background;
  if Assigned(FTitle) then
    FTitle.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FPath) then
    FPath.TextSettings.FontColor := AColors.SubTextColor;
  if Assigned(FLetterLbl) then
    FLetterLbl.TextSettings.FontColor := AColors.TextColor;
  if Assigned(FCombo) then
    FCombo.ApplyTheme(AColors);
  if Assigned(FRestoreRow) then
    FRestoreRow.ApplyTheme(AColors);
  if Assigned(FBtnOk) then
    FBtnOk.ApplyTheme(AColors);
  if Assigned(FBtnCancel) then
    FBtnCancel.ApplyTheme(AColors);
  ApplyNativeChrome;
end;

end.
