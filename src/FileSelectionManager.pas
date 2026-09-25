unit FileSelectionManager;

interface

uses
  System.Classes, System.Types, System.UITypes, System.SysUtils, System.Math,
  System.Masks, System.StrUtils;

type
  ISelectionAdapter = interface
    ['{B48C21A5-3F7E-4219-98A1-1E4C765E4231}']
    function GetItemCount: Integer;
    function IsItemSelected(AIndex: Integer): Boolean;
    procedure SetItemSelected(AIndex: Integer; ASelected: Boolean);
    function GetItemExtension(AIndex: Integer): string;
    function GetItemName(AIndex: Integer): string;
    function IsItemDirectory(AIndex: Integer): Boolean;
    procedure InvalidateView;
  end;

  TFileSelectionManager = class
  private
    FAdapter: ISelectionAdapter;
    FAnchorIndex: Integer;
    FCurrentIndex: Integer;
    FIsDragging: Boolean;
    FInitialState: Boolean;
  public
    constructor Create(AAdapter: ISelectionAdapter);

    procedure ResetState(AIndex: Integer);

    procedure SelectRange(AStart, AEnd: Integer; AAddMode: Boolean);

    procedure MouseDown(AIndex: Integer; AButton: TMouseButton; AShift: TShiftState);
    procedure BeginRightPaint(AIndex: Integer);
    procedure MouseMove(AIndex: Integer; AShift: TShiftState);
    procedure MouseUp(AButton: TMouseButton);
    procedure CancelDrag;

    function KeyDown(var AKey: Word; AShift: TShiftState): Boolean;

    procedure SelectAll;
    procedure DeselectAll;
    procedure InvertSelection;
    procedure SelectByMask(const AExtension: string; ASelect: Boolean);
    procedure SelectByWildcard(const AMask: string; ASelect: Boolean);
    procedure SelectFilesOnly;
    procedure SelectFoldersOnly;

    property CurrentIndex: Integer read FCurrentIndex write FCurrentIndex;
    property AnchorIndex: Integer read FAnchorIndex write FAnchorIndex;
    property IsDragging: Boolean read FIsDragging;
  end;

implementation

constructor TFileSelectionManager.Create(AAdapter: ISelectionAdapter);
begin
  inherited Create();
  FAdapter := AAdapter;
  FAnchorIndex := -1;
  FCurrentIndex := 0;
  FIsDragging := False;
  FInitialState := False;
end;

procedure TFileSelectionManager.ResetState(AIndex: Integer);
begin
  FIsDragging := False;
  FAnchorIndex := AIndex;
  FCurrentIndex := AIndex;
  DeselectAll;
end;






procedure TFileSelectionManager.SelectRange(AStart, AEnd: Integer; AAddMode: Boolean);
var
  LMin, LMax, I: Integer;
begin
  LMin := Min(AStart, AEnd);
  LMax := Max(AStart, AEnd);




  for I := LMin to LMax do
    if (I >= 0) and (I < FAdapter.GetItemCount) then
      FAdapter.SetItemSelected(I, True);

  FAdapter.InvalidateView;
end;

procedure TFileSelectionManager.MouseDown(AIndex: Integer; AButton: TMouseButton; AShift: TShiftState);
begin
  if (AIndex < 0) or (AIndex >= FAdapter.GetItemCount) then Exit;

  if AButton = TMouseButton.mbLeft then
  begin
    FCurrentIndex := AIndex;
    FIsDragging := False;

    if ssShift in AShift then
    begin
      if FAnchorIndex < 0 then
        FAnchorIndex := FCurrentIndex;
      SelectRange(FAnchorIndex, FCurrentIndex, ssCtrl in AShift);
    end
    else if ssCtrl in AShift then
    begin
      FAnchorIndex := FCurrentIndex;
      FAdapter.SetItemSelected(FCurrentIndex, not FAdapter.IsItemSelected(FCurrentIndex));
      FAdapter.InvalidateView;
    end
    else
    begin


      FCurrentIndex := AIndex;
      FAnchorIndex := AIndex;
      FAdapter.InvalidateView;
    end;
  end
  else if AButton = TMouseButton.mbRight then
  begin
    { Короткий клик ПКМ — переключить пункт. Протяжка идёт через BeginRightPaint. }
    FCurrentIndex := AIndex;
    FAnchorIndex := AIndex;
    FIsDragging := False;
    FAdapter.SetItemSelected(AIndex, not FAdapter.IsItemSelected(AIndex));
    FAdapter.InvalidateView;
  end;
end;

procedure TFileSelectionManager.BeginRightPaint(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FAdapter.GetItemCount) then
    Exit;
  FCurrentIndex := AIndex;
  FAnchorIndex := AIndex;
  FIsDragging := True;
  FInitialState := not FAdapter.IsItemSelected(AIndex);
  FAdapter.SetItemSelected(AIndex, FInitialState);
  FAdapter.InvalidateView;
end;



procedure TFileSelectionManager.CancelDrag;
begin
  FIsDragging := False;
end;

procedure TFileSelectionManager.MouseMove(AIndex: Integer; AShift: TShiftState);
var
  LMin, LMax, I: Integer;
begin
  if FIsDragging and
     (AIndex >= 0) and (AIndex < FAdapter.GetItemCount) then
  begin
    if AIndex <> FCurrentIndex then
    begin
      FCurrentIndex := AIndex;
      LMin := Min(FAnchorIndex, FCurrentIndex);
      LMax := Max(FAnchorIndex, FCurrentIndex);

      for I := 0 to FAdapter.GetItemCount - 1 do
      begin
        if (I >= LMin) and (I <= LMax) then
          FAdapter.SetItemSelected(I, FInitialState);
      end;
      FAdapter.InvalidateView;
    end;
  end;
end;

procedure TFileSelectionManager.MouseUp(AButton: TMouseButton);
begin
  FIsDragging := False;
end;



function TFileSelectionManager.KeyDown(var AKey: Word; AShift: TShiftState): Boolean;
var
  LExt: string;
begin
  Result := True;

  // 1. Ctrl + A / Ctrl + "+" -> Выделить все
  if (ssCtrl in AShift) and (
       (AKey = Ord('A')) or (AKey = Ord('а')) or (AKey = Ord('Ф')) or
       (AKey = 107) or (AKey = 187)
     ) then
  begin
    SelectAll;
    AKey := 0;
    Exit;
  end;

  // 2. Ctrl + "-" -> Снять все выделения
  if (ssCtrl in AShift) and ((AKey = 109) or (AKey = 189)) then
  begin
    DeselectAll;
    AKey := 0;
    Exit;
  end;

  // 3. Alt + "+" -> Выделение группы по типу
  if ((ssAlt in AShift) and ((AKey = 107) or (AKey = 187)))  or (AKey = 443) then
  begin
    if (FCurrentIndex >= 0) and (FCurrentIndex < FAdapter.GetItemCount) then
    begin
      LExt := FAdapter.GetItemExtension(FCurrentIndex);
      SelectByMask(LExt, True);
    end;
    AKey := 0;
    Exit;
  end;

  // 4. Alt + "-" -> Снять выделение группы по типу
  if (ssAlt in AShift) and ((AKey = 109) or (AKey = 189)) then
  begin
    if (FCurrentIndex >= 0) and (FCurrentIndex < FAdapter.GetItemCount) then
    begin
      LExt := FAdapter.GetItemExtension(FCurrentIndex);
      SelectByMask(LExt, False);
    end;
    AKey := 0;
    Exit;
  end;

  // 5. "*" -> Инвертировать выделение
  if (AKey = vkMultiply) or ((ssShift in AShift) and (AKey = 56)) then
  begin
    InvertSelection;
    AKey := 0;
    Exit;
  end;



  Result := False;
end;







procedure TFileSelectionManager.SelectAll;
var
  I: Integer;
begin
  for I := 0 to FAdapter.GetItemCount - 1 do
    FAdapter.SetItemSelected(I, True);
   FAdapter.InvalidateView;

end;

procedure TFileSelectionManager.DeselectAll;
var
  I: Integer;
begin
  for I := 0 to FAdapter.GetItemCount - 1 do
    FAdapter.SetItemSelected(I, False);
    FAdapter.InvalidateView;
end;

procedure TFileSelectionManager.InvertSelection;
var
  I: Integer;
begin
  for I := 0 to FAdapter.GetItemCount - 1 do
    FAdapter.SetItemSelected(I, not FAdapter.IsItemSelected(I));
  FAdapter.InvalidateView;
end;

procedure TFileSelectionManager.SelectByMask(const AExtension: string; ASelect: Boolean);
var
  I: Integer;
begin
  for I := 0 to FAdapter.GetItemCount - 1 do
  begin
    if SameText(FAdapter.GetItemExtension(I), AExtension) then
      FAdapter.SetItemSelected(I, ASelect);
  end;
  FAdapter.InvalidateView;
end;

function NameMatchesWild(const AName, AMask: string): Boolean;
var
  Parts: TArray<string>;
  P: string;
begin
  Result := False;
  if (AMask = '') or (AMask = '*') or (AMask = '*.*') then
    Exit(True);
  Parts := AMask.Split([';', '|']);
  for P in Parts do
  begin
    if Trim(P) = '' then
      Continue;
    try
      if MatchesMask(AName, Trim(P)) then
        Exit(True);
    except
    end;
  end;
end;

procedure TFileSelectionManager.SelectByWildcard(const AMask: string; ASelect: Boolean);
var
  I: Integer;
  M: string;
begin
  M := Trim(AMask);
  if M = '' then
    M := '*.*';
  for I := 0 to FAdapter.GetItemCount - 1 do
    if NameMatchesWild(FAdapter.GetItemName(I), M) then
      FAdapter.SetItemSelected(I, ASelect);
  FAdapter.InvalidateView;
end;

procedure TFileSelectionManager.SelectFilesOnly;
var
  I: Integer;
begin
  for I := 0 to FAdapter.GetItemCount - 1 do
    if not FAdapter.IsItemDirectory(I) then
      FAdapter.SetItemSelected(I, True);
  FAdapter.InvalidateView;
end;

procedure TFileSelectionManager.SelectFoldersOnly;
var
  I: Integer;
begin
  for I := 0 to FAdapter.GetItemCount - 1 do
    if FAdapter.IsItemDirectory(I) then
      FAdapter.SetItemSelected(I, True);
  FAdapter.InvalidateView;
end;

end.
