unit uLangBind;

{
  Живые подписи. Tr* ставит текст и запоминает ключ.
  SetLanguage проходит по списку и обновляет открытые окна.
  Хук принадлежит контролу и исчезает вместе с ним.
}

interface

uses
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Forms,
  uFluentChrome, uFluentEdit;

procedure TrText(AText: TText; const AKey: string);
procedure TrButton(ABtn: TFluentButton; const AKey: string);
procedure TrCheck(ARow: TFluentCheckRow; const AKey: string);
procedure TrHint(ACtrl: TControl; const AKey: string);
procedure TrForm(AForm: TCustomForm; const AKey: string);
procedure TrPrompt(AEdit: TFluentEdit; const AKey: string);

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uLang;

type
  TLangKind = (lkText, lkButton, lkCheck, lkHint, lkForm, lkPrompt);

  TLangHook = class(TComponent)
  public
    Kind: TLangKind;
    Key: string;
    Target: TComponent;
    procedure Apply;
    destructor Destroy; override;
  end;

var
  FHooks: TList<TLangHook>;

procedure TLangHook.Apply;
begin
  if (Target = nil) or (Key = '') then
    Exit;
  case Kind of
    lkText:
      if Target is TText then
        TText(Target).Text := L(Key);
    lkButton:
      if Target is TFluentButton then
        TFluentButton(Target).SetCaption(L(Key));
    lkCheck:
      if Target is TFluentCheckRow then
        TFluentCheckRow(Target).SetCaption(L(Key));
    lkHint:
      if Target is TControl then
        TControl(Target).Hint := L(Key);
    lkForm:
      if Target is TCustomForm then
        TCustomForm(Target).Caption := L(Key);
    lkPrompt:
      if Target is TFluentEdit then
        TFluentEdit(Target).Placeholder := L(Key);
  end;
end;

destructor TLangHook.Destroy;
begin
  if FHooks <> nil then
    FHooks.Remove(Self);
  inherited;
end;

procedure AddHook(ATarget: TComponent; AKind: TLangKind; const AKey: string);
var
  H: TLangHook;
begin
  if (ATarget = nil) or (AKey = '') or (FHooks = nil) then
    Exit;
  H := TLangHook.Create(ATarget);
  H.Kind := AKind;
  H.Key := AKey;
  H.Target := ATarget;
  FHooks.Add(H);
end;

procedure ApplyAll;
var
  I: Integer;
begin
  if FHooks = nil then
    Exit;
  for I := FHooks.Count - 1 downto 0 do
    if I < FHooks.Count then
      FHooks[I].Apply;
end;

procedure TrText(AText: TText; const AKey: string);
begin
  if AText = nil then
    Exit;
  AText.Text := L(AKey);
  AddHook(AText, lkText, AKey);
end;

procedure TrButton(ABtn: TFluentButton; const AKey: string);
begin
  if ABtn = nil then
    Exit;
  ABtn.SetCaption(L(AKey));
  AddHook(ABtn, lkButton, AKey);
end;

procedure TrCheck(ARow: TFluentCheckRow; const AKey: string);
begin
  if ARow = nil then
    Exit;
  ARow.SetCaption(L(AKey));
  AddHook(ARow, lkCheck, AKey);
end;

procedure TrHint(ACtrl: TControl; const AKey: string);
begin
  if ACtrl = nil then
    Exit;
  ACtrl.Hint := L(AKey);
  ACtrl.ShowHint := True;
  AddHook(ACtrl, lkHint, AKey);
end;

procedure TrForm(AForm: TCustomForm; const AKey: string);
begin
  if AForm = nil then
    Exit;
  AForm.Caption := L(AKey);
  AddHook(AForm, lkForm, AKey);
end;

procedure TrPrompt(AEdit: TFluentEdit; const AKey: string);
begin
  if AEdit = nil then
    Exit;
  AEdit.Placeholder := L(AKey);
  AddHook(AEdit, lkPrompt, AKey);
end;

initialization
  FHooks := TList<TLangHook>.Create;
  SetLanguageChanged(ApplyAll);

finalization
  FreeAndNil(FHooks);

end.
