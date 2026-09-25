unit uConflictDialog;

{
  Одно Fluent-окно на пачку конфликтов имени.
  Используется в режиме «Тихий» (copy/move): без progress и без диалогов Shell.
  V!be-режим конфликты показывает в uFileOpProgressForm, не здесь.
  Листает пункты; «для всех оставшихся» применяет действие ко всем.
  Закрытие окна = Пропустить оставшиеся.
}

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.Graphics,
  {$IFDEF MSWINDOWS}Winapi.Windows, Winapi.DwmApi, FMX.Platform.Win,{$ENDIF}
  uAppSettings, uThemeManager, uFluentChrome, uFileOps, uFileModel, uThumbCache,
  UCoreEngine;

function ShowConflictDialog(AOwner: TCommonCustomForm;
  const AItems: TArray<TConflictItem>;
  out AActions: TArray<TConflictAction>): Boolean;

type
  TConflictDialog = class(TForm)
  private
    FColors: TThemeColors;
    FItems: TArray<TConflictItem>;
    FActions: TArray<TConflictAction>;
    FIndex: Integer;
    FFinished: Boolean;
    FGen: Integer;
    FDead: Boolean;

    FRoot: TRectangle;
    FTitle: TText;
    FCounter: TText;
    FCards: TLayout;
    FSrcCard, FDstCard: TRectangle;
    FSrcCap, FDstCap: TText;
    FSrcNewer, FDstNewer: TText;
    FSrcImg, FDstImg: TImage;
    FSrcName, FDstName: TText;
    FSrcSize, FDstSize: TText;
    FSrcDate, FDstDate: TText;
    FDestPath: TText;
    FForAll: TFluentCheckRow;
    FBtnSkip, FBtnAuto, FBtnOver: TFluentButton;
    FPoll: TTimer;

    procedure BuildUI;
    function MakeCard(AParent: TFmxObject; const ACaption: string;
      out ACard: TRectangle; out ACap, ANewer: TText; out AImg: TImage;
      out AName, ASize, ADate: TText): TRectangle;
    procedure ApplyNativeChrome;
    procedure ShowItem;
    procedure LoadThumb(const APath: string; AIsDir: Boolean; AImg: TImage);
    procedure SetFallbackIcon(const APath: string; AIsDir: Boolean; AImg: TImage);
    procedure ApplyAction(AAct: TConflictAction);
    procedure SkipClick(Sender: TObject);
    procedure AutoClick(Sender: TObject);
    procedure OverClick(Sender: TObject);
    procedure PollTick(Sender: TObject);
    procedure Finish;
  protected
    procedure CreateHandle; override;
    procedure DoShow; override;
    procedure DoClose(var CloseAction: TCloseAction); override;

  public
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
    constructor Create(AOwner: TComponent; const AItems: TArray<TConflictItem>); reintroduce;
    destructor Destroy; override;
    property Actions: TArray<TConflictAction> read FActions;
    procedure ApplyTheme(const AColors: TThemeColors);
  end;

implementation

const
  DLG_W = 700;
  DLG_H = 470;
  CARD_H = 268;
  THUMB = 112;

function ShowConflictDialog(AOwner: TCommonCustomForm;
  const AItems: TArray<TConflictItem>;
  out AActions: TArray<TConflictAction>): Boolean;
var
  Dlg: TConflictDialog;
  I: Integer;
begin
  SetLength(AActions, Length(AItems));
  for I := 0 to High(AActions) do
    AActions[I] := caSkip;
  if Length(AItems) = 0 then
    Exit(True);
  if (AOwner <> nil) and (csDestroying in AOwner.ComponentState) then
    Exit(True);

  Dlg := TConflictDialog.Create(AOwner, AItems);
  try
    Dlg.ShowModal;
    AActions := Copy(Dlg.Actions);
    Result := True;
  finally
    Dlg.Free;
  end;
end;

constructor TConflictDialog.Create(AOwner: TComponent;
  const AItems: TArray<TConflictItem>);
var
  I: Integer;
begin
  inherited CreateNew(AOwner);
  FItems := Copy(AItems);
  SetLength(FActions, Length(FItems));
  for I := 0 to High(FActions) do
    FActions[I] := caSkip;
  FIndex := 0;
  FFinished := False;
  FColors := GetThemeColors(ActiveAppTheme);
  Width := DLG_W;
  Height := DLG_H;
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Caption := 'Конфликт имени';
  Position := TFormPosition.OwnerFormCenter;
  ShowHint := True;
  BuildUI;
  ShowItem;
  ApplyNativeChrome;
end;

destructor TConflictDialog.Destroy;
begin
  FDead := True;
  if Assigned(FPoll) then
    FPoll.Enabled := False;
  inherited;
end;

procedure TConflictDialog.ApplyNativeChrome;
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

procedure TConflictDialog.CreateHandle;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TConflictDialog.DoShow;
begin
  inherited;
  ApplyNativeChrome;
end;

procedure TConflictDialog.DoClose(var CloseAction: TCloseAction);
var
  I: Integer;
begin
  FDead := True;
  if Assigned(FPoll) then
    FPoll.Enabled := False;
  { Крестик / Alt+F4: только если не завершили кнопками — оставшиеся = Пропустить.
    Иначе DoClose затирал бы ответы «Для всех оставшихся» обратно в caSkip. }
  if not FFinished then
  begin
    if FIndex < 0 then
      FIndex := 0;
    for I := FIndex to High(FActions) do
      FActions[I] := caSkip;
  end;
  inherited;
end;


procedure TConflictDialog.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkEscape then
  begin
    Key := 0;
    ApplyAction(caSkip);
    Exit;
  end;
  if Key = vkReturn then
  begin
    Key := 0;
    ApplyAction(caOverwrite);
    if not FFinished then
      Finish;
    Exit;
  end;
  inherited;
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

function TConflictDialog.MakeCard(AParent: TFmxObject; const ACaption: string;
  out ACard: TRectangle; out ACap, ANewer: TText; out AImg: TImage;
  out AName, ASize, ADate: TText): TRectangle;
var
  Head: TLayout;
begin
  ACard := TRectangle.Create(Self);
  ACard.Parent := AParent;
  ACard.Align := TAlignLayout.None;
  ACard.XRadius := 10;
  ACard.YRadius := 10;
  ACard.Stroke.Kind := TBrushKind.Solid;
  ACard.Stroke.Thickness := 1;
  ACard.Stroke.Color := FColors.CardStroke;
  ACard.Fill.Kind := TBrushKind.Solid;
  ACard.Fill.Color := FColors.CardBackground;


  Head := TLayout.Create(Self);
  Head.Parent := ACard;
  Head.Align := TAlignLayout.Top;
  Head.Height := 22;

  ACap := MkText(Self, Head, 12, True, FColors.SubTextColor, TAlignLayout.Client);
  ACap.Text := ACaption;

  ANewer := MkText(Self, Head, 11, True, FColors.SelectionColor, TAlignLayout.Right);
  ANewer.Width := 64;
  ANewer.Text := 'новее';
  ANewer.TextSettings.HorzAlign := TTextAlign.Trailing;
  ANewer.Visible := False;

  ADate := MkText(Self, ACard, 12, False, FColors.SubTextColor, TAlignLayout.Top);
  ADate.Height := 18;



  ASize := MkText(Self, ACard, 12, False, FColors.SubTextColor, TAlignLayout.Top);
  ASize.Height := 18;
  ASize.Margins.Top := 10;

  AImg := TImage.Create(Self);
  AImg.Parent := ACard;
  AImg.Align := TAlignLayout.Top;

  AImg.Height := THUMB + 8;

  AImg.WrapMode := TImageWrapMode.Fit;
  AImg.HitTest := False;


 

  AName := MkText(Self, ACard, 14, True, FColors.TextColor, TAlignLayout.Top);
  AName.Height := 22;
  AName.TextSettings.Trimming := TTextTrimming.Character;
  AName.TextSettings.WordWrap := False;




  ACard.Padding.Rect := TRectF.Create(12, 10, 12, 10);
   AImg.Margins.Rect := TRectF.Create(0, 20, 0, 4);
  Result := ACard;
end;

procedure TConflictDialog.BuildUI;
var
  Head, Foot, Btns: TLayout;
begin
  FRoot := TRectangle.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Stroke.Kind := TBrushKind.None;
  FRoot.Fill.Color := FColors.Background;
 // FRoot.Padding.Rect := TRectF.Create(18, 14, 18, 14);

  Head := TLayout.Create(Self);
  Head.Parent := FRoot;
  Head.Align := TAlignLayout.Top;
  Head.Height := 32;

  FTitle := MkText(Self, Head, 18, True, FColors.TextColor, TAlignLayout.Client);
  FTitle.Text := 'Конфликт имени';

  FForAll := TFluentCheckRow.Create(Self);
  FForAll.Setup(FRoot, 'Для всех оставшихся', False);
  FForAll.Align := TAlignLayout.Top;
  FForAll.Height := 32;
  FForAll.Margins.Top := 4;
  FForAll.ApplyTheme(FColors);

  FCounter := MkText(Self, Head, 13, False, FColors.SubTextColor, TAlignLayout.Right);
  FCounter.Width := 90;
  FCounter.TextSettings.HorzAlign := TTextAlign.Trailing;

  FCards := TLayout.Create(Self);
  FCards.Parent := FRoot;
  FCards.Align := TAlignLayout.Top;
  FCards.Height := CARD_H;


  MakeCard(FCards, 'Источник (копируем)', FSrcCard, FSrcCap, FSrcNewer, FSrcImg,
    FSrcName, FSrcSize, FSrcDate);
  MakeCard(FCards, 'Назначение (уже есть)', FDstCard, FDstCap, FDstNewer, FDstImg,
    FDstName, FDstSize, FDstDate);
  FSrcCard.Align := TAlignLayout.Left;
  FSrcCard.Width := 322;
  FSrcCard.Margins.Right := 8;
  FDstCard.Align := TAlignLayout.Client;
  FDstCard.Margins.Left := 8;
    FCards.Margins.Top := 8;
  FDestPath := MkText(Self, FRoot, 11, False, FColors.SubTextColor, TAlignLayout.Top);
  FDestPath.Height := 22;
  FDestPath.Margins.Top := 8;
  FDestPath.TextSettings.Trimming := TTextTrimming.Character;
  FDestPath.TextSettings.WordWrap := False;

 

  Foot := TLayout.Create(Self);
  Foot.Parent := FRoot;
  Foot.Align := TAlignLayout.Bottom;
  Foot.Height := 40;
  Foot.Margins.Top := 8;

  Btns := TLayout.Create(Self);
  Btns.Parent := Foot;
  Btns.Align := TAlignLayout.Right;
  Btns.Width := 430;


    FRoot.Padding.Rect := TRectF.Create(18, 14, 18, 14);




    FBtnOver := CreateFluentButton(Self, Btns, '', 'Перезаписать', fbkAccent, 150, OverClick);
  FBtnSkip := CreateFluentButton(Self, Btns, '', 'Пропустить', fbkStandard, 130, SkipClick);
  FBtnAuto := CreateFluentButton(Self, Btns, '', 'Автоимя', fbkStandard, 130, AutoClick);

  FBtnSkip.Align := TAlignLayout.Left;
  FBtnAuto.Align := TAlignLayout.Left;
  FBtnOver.Align := TAlignLayout.Left;

  FPoll := TTimer.Create(Self);
  FPoll.Interval := 200;
  FPoll.OnTimer := PollTick;
  FPoll.Enabled := False;
   ApplyTheme(FColors);
end;

procedure TConflictDialog.SetFallbackIcon(const APath: string; AIsDir: Boolean;
  AImg: TImage);
var
  Bmp: FMX.Graphics.TBitmap;
  Key: string;
begin
  Bmp := nil;
  if AIsDir then
    Key := '#dir'
  else
    Key := ExtractFileExt(APath);
  GetTypeIconBitmap(Key, AIsDir, Bmp);
  try
    if Assigned(Bmp) then
      AImg.Bitmap.Assign(Bmp)
    else
      AImg.Bitmap.Assign(nil);
  finally
    Bmp.Free;
  end;
end;

procedure TConflictDialog.LoadThumb(const APath: string; AIsDir: Boolean; AImg: TImage);
var
  Cached: FMX.Graphics.TBitmap;
  Path: string;
  Img: TImage;
  Gen: Integer;
begin
  SetFallbackIcon(APath, AIsDir, AImg);
  if (APath = '') or AIsDir or (GlobalThumbCache = nil) then
    Exit;
  if GlobalThumbCache.TryGet(APath, Cached) and Assigned(Cached) then
  begin
    AImg.Bitmap.Assign(Cached);
    Exit;
  end;
  Path := APath;
  Img := AImg;
  Gen := FGen;
  GlobalThumbCache.RequestAsync(APath, 128,
    procedure(const AReadyPath: string; ABitmap: FMX.Graphics.TBitmap)
    begin
      if FDead or (Gen <> FGen) then
        Exit;
      if Assigned(ABitmap) and SameText(AReadyPath, Path) then
        Img.Bitmap.Assign(ABitmap);
    end);
  FPoll.Enabled := True;
  FPoll.Tag := 0;
end;

procedure TConflictDialog.PollTick(Sender: TObject);
var
  Bmp: FMX.Graphics.TBitmap;
begin
  if FDead or (FIndex < 0) or (FIndex > High(FItems)) then
  begin
    FPoll.Enabled := False;
    Exit;
  end;
  FPoll.Tag := FPoll.Tag + 1;
  if (GlobalThumbCache <> nil) then
  begin
    if (not FItems[FIndex].SourceIsDir) and
       GlobalThumbCache.TryGet(FItems[FIndex].SourcePath, Bmp) and Assigned(Bmp) then
      FSrcImg.Bitmap.Assign(Bmp);
    if (not FItems[FIndex].DestIsDir) and
       GlobalThumbCache.TryGet(FItems[FIndex].DestPath, Bmp) and Assigned(Bmp) then
      FDstImg.Bitmap.Assign(Bmp);
  end;
  if FPoll.Tag >= 12 then
    FPoll.Enabled := False;
end;

procedure TConflictDialog.ShowItem;
var
  It: TConflictItem;
  SrcNewer, DstNewer: Boolean;
begin
  if (FIndex < 0) or (FIndex > High(FItems)) then
  begin
    Finish;
    Exit;
  end;
  Inc(FGen);
  It := FItems[FIndex];
  FCounter.Text := Format('%d из %d', [FIndex + 1, Length(FItems)]);
  FSrcName.Text := ExtractFileName(ExcludeTrailingPathDelimiter(It.SourcePath));
  FDstName.Text := ExtractFileName(ExcludeTrailingPathDelimiter(It.DestPath));
  if It.SourceSize > 0 then
    FSrcSize.Text := FormatFileSize(It.SourceSize)
  else
    FSrcSize.Text := '—';
  if It.DestSize > 0 then
    FDstSize.Text := FormatFileSize(It.DestSize)
  else
    FDstSize.Text := '—';
  if It.SourceTime > 0 then
    FSrcDate.Text := FormatDateTime('dd.mm.yyyy HH:nn', It.SourceTime)
  else
    FSrcDate.Text := '—';
  if It.DestTime > 0 then
    FDstDate.Text := FormatDateTime('dd.mm.yyyy HH:nn', It.DestTime)
  else
    FDstDate.Text := '—';
  FDestPath.Text := It.DestPath;

  SrcNewer := (It.SourceTime > 0) and (It.DestTime > 0) and (It.SourceTime > It.DestTime);
  DstNewer := (It.SourceTime > 0) and (It.DestTime > 0) and (It.DestTime > It.SourceTime);
  FSrcNewer.Visible := SrcNewer;
  FDstNewer.Visible := DstNewer;
  if SrcNewer then
  begin
    FSrcCard.Stroke.Color := FColors.SelectionColor;
    FSrcCard.Stroke.Thickness := 2;
  end
  else
  begin
    FSrcCard.Stroke.Color := FColors.CardStroke;
    FSrcCard.Stroke.Thickness := 1;
  end;
  if DstNewer then
  begin
    FDstCard.Stroke.Color := FColors.SelectionColor;
    FDstCard.Stroke.Thickness := 2;
  end
  else
  begin
    FDstCard.Stroke.Color := FColors.CardStroke;
    FDstCard.Stroke.Thickness := 1;
  end;

  LoadThumb(It.SourcePath, It.SourceIsDir, FSrcImg);
  LoadThumb(It.DestPath, It.DestIsDir, FDstImg);
end;

procedure TConflictDialog.Finish;
begin
  FDead := True;
  FFinished := True;
  if Assigned(FPoll) then
    FPoll.Enabled := False;
  ModalResult := mrOk;
  Close;
end;

procedure TConflictDialog.ApplyAction(AAct: TConflictAction);
var
  I: Integer;
  All: Boolean;
begin
  if (FIndex < 0) or (FIndex > High(FActions)) then
  begin
    Finish;
    Exit;
  end;
  All := Assigned(FForAll) and FForAll.Checked;
  FActions[FIndex] := AAct;
  if All then
  begin
    for I := FIndex + 1 to High(FActions) do
      FActions[I] := AAct;
    FIndex := Length(FActions); { все ответы записаны }
    Finish;
    Exit;
  end;
  Inc(FIndex);
  if FIndex > High(FItems) then
    Finish
  else
    ShowItem;
end;

procedure TConflictDialog.SkipClick(Sender: TObject);
begin
  ApplyAction(caSkip);
end;

procedure TConflictDialog.AutoClick(Sender: TObject);
begin
  ApplyAction(caAutoName);
end;

procedure TConflictDialog.OverClick(Sender: TObject);
begin
  ApplyAction(caOverwrite);
end;


procedure TConflictDialog.ApplyTheme(const AColors: TThemeColors);
begin
  FColors := AColors;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := AColors.Background;
  FRoot.Fill.Color := AColors.Background;
  FTitle.TextSettings.FontColor := AColors.TextColor;
  FCounter.TextSettings.FontColor := AColors.SubTextColor;
  FDestPath.TextSettings.FontColor := AColors.SubTextColor;
  FSrcCap.TextSettings.FontColor := AColors.SubTextColor;
  FDstCap.TextSettings.FontColor := AColors.SubTextColor;
  FSrcName.TextSettings.FontColor := AColors.TextColor;
  FDstName.TextSettings.FontColor := AColors.TextColor;
  FSrcSize.TextSettings.FontColor := AColors.SubTextColor;
  FDstSize.TextSettings.FontColor := AColors.SubTextColor;
  FSrcDate.TextSettings.FontColor := AColors.SubTextColor;
  FDstDate.TextSettings.FontColor := AColors.SubTextColor;
  FSrcCard.Fill.Color := AColors.CardBackground;
  FDstCard.Fill.Color := AColors.CardBackground;
  FSrcCard.Stroke.Color := AColors.CardStroke;
  FDstCard.Stroke.Color := AColors.CardStroke;
  FForAll.ApplyTheme(AColors);
  FBtnSkip.ApplyTheme(AColors);
  FBtnAuto.ApplyTheme(AColors);
  FBtnOver.ApplyTheme(AColors);
  ApplyNativeChrome;
end;

end.
