unit UCoreEngine;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IOUtils,
  System.Math, System.SyncObjs,
  Winapi.Windows, Winapi.ShellAPI, Winapi.ActiveX, Winapi.ShlObj,
  Vcl.Imaging.pngimage, System.Generics.Collections,
  FMX.Graphics, Vcl.Graphics;

type
  TFileInfo = record
    Name: string;
    Extension: string;
    Size: Int64;
    ModifiedDate: TDateTime;
    IsFolder: Boolean;
    IsSelected: Boolean;
  end;

// Shell interface for high-quality thumbnails
[ComImport]
[InterfaceType(ComInterfaceType.IUnknownForInterface)]
[Guid('bcc18b79-ba16-442f-80c4-8a59c30c463b')]
IShellItemImageFactory = interface(IUnknown)
  ['{bcc18b79-ba16-442f-80c4-8a59c30c463b}']
  function GetImage(size: TSize; flags: Integer; out phbm: HBITMAP): HResult; stdcall;
end;

function FormatFileDate(const DateTime: TDateTime): string;
function FormatFileSize(const Bytes: Int64): string;
procedure GetFileIconBitmap(const AFilePath: string; IsFolder: Boolean; var ABitmap: FMX.Graphics.TBitmap);
procedure GetTypeIconBitmap(const AIconKey: string; AIsDir: Boolean; var ABitmap: FMX.Graphics.TBitmap);
procedure GetAppIconBitmap(var ABitmap: FMX.Graphics.TBitmap; ASize: Integer = 32);
function GetFileThumbnail(const AFilePath: string; AWidth, AHeight: Integer; ABitmap: FMX.Graphics.TBitmap): Boolean;
function GetFileThumbnailRaw(const AFilePath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
function GetShellItemThumbnailRaw(const AItem: IUnknown; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
function GetTypeIconRaw(const AIconKey: string; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  APixelSize: Integer = 32): Boolean;
function GetFileIconRaw(const AFilePath: string; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  APixelSize: Integer = 256): Boolean;
function ExtractDockJumboRaw(const AFilePath: string; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
function GetShellItemIconRaw(const AItem: IUnknown; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  APixelSize: Integer = 256): Boolean;
procedure BgraToFmxBitmap(const APixels: TBytes; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap);
procedure RawToFmxBitmap(const APixels: TBytes; AWidth, AHeight: Integer;
  var ABitmap: FMX.Graphics.TBitmap);
function IsBlockedReparsePath(const APath: string): Boolean;
function IsCloudPlaceholderPath(const APath: string): Boolean;
function SafeGetFileAge(const APath: string; out AAge: TDateTime): Boolean;

// Цветовые утилиты
function AdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;
function BlendColors(C1, C2: TAlphaColor; T: Single): TAlphaColor;

implementation

const Neighbors: array[0..3] of TPoint = ((X: 1; Y: 0), (X: -1; Y: 0), (X: 0; Y: 1), (X: 0; Y: -1));

function AdjustAlpha(AColor: TAlphaColor; AAlpha: Byte): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.Color := AColor;
  Rec.A := AAlpha;
  Result := Rec.Color;
end;

function BlendColors(C1, C2: TAlphaColor; T: Single): TAlphaColor;
var
  R1, G1, B1, A1: Byte;
  R2, G2, B2, A2: Byte;
begin
  R1 := TAlphaColorRec(C1).R;
  G1 := TAlphaColorRec(C1).G;
  B1 := TAlphaColorRec(C1).B;
  A1 := TAlphaColorRec(C1).A;

  R2 := TAlphaColorRec(C2).R;
  G2 := TAlphaColorRec(C2).G;
  B2 := TAlphaColorRec(C2).B;
  A2 := TAlphaColorRec(C2).A;

  TAlphaColorRec(Result).R := Round(R1 + (R2 - R1) * T);
  TAlphaColorRec(Result).G := Round(G1 + (G2 - G1) * T);
  TAlphaColorRec(Result).B := Round(B1 + (B2 - B1) * T);
  TAlphaColorRec(Result).A := Round(A1 + (A2 - A1) * T);
end;

procedure Icon2Png(AIcon: TIcon; APng: TPngImage);
var
  Stream: TMemoryStream;
  Wic: TWicImage;
begin
  Stream := TMemoryStream.Create;
  try
    AIcon.SaveToStream(Stream);
    Stream.Position := 0;

    Wic := TWicImage.Create;
    try
      Wic.LoadFromStream(Stream);
      APng.Assign(Wic);
    finally
      Wic.Free;
    end;
  finally
    Stream.Free;
  end;
end;


function MakeBackgroundTransparent(ABitmap: FMX.Graphics.TBitmap): Boolean;
var
  Data: TBitmapData;
  IsBackground: array of Boolean;
  Queue: TList<TPoint>;
  W, H, X, Y, I, CurrX, CurrY: Integer;
  R, G, B, A: Byte;
  C: TAlphaColor;
  BgR, BgG, BgB: Integer;
  Tolerance: Double;

  function GetColorDist(const AColor: TAlphaColor; TR, TG, TB: Integer): Double;
  begin
    Result := Sqrt(Sqr(TAlphaColorRec(AColor).R - TR) +
                   Sqr(TAlphaColorRec(AColor).G - TG) +
                   Sqr(TAlphaColorRec(AColor).B - TB));
  end;

const
  DX: array[0..3] of Integer = (1, -1, 0, 0);
  DY: array[0..3] of Integer = (0, 0, 1, -1);
begin
  Result := False;
  if (ABitmap = nil) or (ABitmap.Width < 8) or (ABitmap.Height < 8) then
    Exit;

  W := ABitmap.Width;
  H := ABitmap.Height;

  if not ABitmap.Map(TMapAccess.ReadWrite, Data) then
    Exit;

  try
    var C1 := Data.GetPixel(0, 0);
    var C2 := Data.GetPixel(W - 1, 0);
    var C3 := Data.GetPixel(0, H - 1);
    var C4 := Data.GetPixel(W - 1, H - 1);

    BgR := (TAlphaColorRec(C1).R + TAlphaColorRec(C2).R + TAlphaColorRec(C3).R + TAlphaColorRec(C4).R) div 4;
    BgG := (TAlphaColorRec(C1).G + TAlphaColorRec(C2).G + TAlphaColorRec(C3).G + TAlphaColorRec(C4).G) div 4;
    BgB := (TAlphaColorRec(C1).B + TAlphaColorRec(C2).B + TAlphaColorRec(C3).B + TAlphaColorRec(C4).B) div 4;

    Tolerance := 35.0;

    SetLength(IsBackground, W * H);
    FillChar(IsBackground[0], Length(IsBackground) * SizeOf(Boolean), False);

    Queue := TList<TPoint>.Create;
    try
      for X := 0 to W - 1 do
      begin
        if GetColorDist(Data.GetPixel(X, 0), BgR, BgG, BgB) <= Tolerance then
        begin
          IsBackground[X] := True;
          Queue.Add(TPoint.Create(X, 0));
        end;
        if GetColorDist(Data.GetPixel(X, H - 1), BgR, BgG, BgB) <= Tolerance then
        begin
          IsBackground[(H - 1) * W + X] := True;
          Queue.Add(TPoint.Create(X, H - 1));
        end;
      end;

      for Y := 0 to H - 1 do
      begin
        if GetColorDist(Data.GetPixel(0, Y), BgR, BgG, BgB) <= Tolerance then
        begin
          IsBackground[Y * W] := True;
          Queue.Add(TPoint.Create(0, Y));
        end;
        if GetColorDist(Data.GetPixel(W - 1, Y), BgR, BgG, BgB) <= Tolerance then
        begin
          IsBackground[Y * W + (W - 1)] := True;
          Queue.Add(TPoint.Create(W - 1, Y));
        end;
      end;

      I := 0;
      while I < Queue.Count do
      begin
        var Pt := Queue[I];
        Inc(I);

        for var D := 0 to 3 do
        begin
          CurrX := Pt.X + DX[D];
          CurrY := Pt.Y + DY[D];

          if (CurrX >= 0) and (CurrX < W) and (CurrY >= 0) and (CurrY < H) then
          begin
            var Idx := CurrY * W + CurrX;
            if not IsBackground[Idx] then
            begin
              C := Data.GetPixel(CurrX, CurrY);
              if GetColorDist(C, BgR, BgG, BgB) <= Tolerance then
              begin
                IsBackground[Idx] := True;
                Queue.Add(TPoint.Create(CurrX, CurrY));
              end;
            end;
          end;
        end;
      end;

      for Y := 0 to H - 1 do
      begin
        for X := 0 to W - 1 do
        begin
          var Idx := Y * W + X;
          if IsBackground[Idx] then
          begin
            Data.SetPixel(X, Y, 0);
          end
          else
          begin
            C := Data.GetPixel(X, Y);
            R := TAlphaColorRec(C).R;
            G := TAlphaColorRec(C).G;
            B := TAlphaColorRec(C).B;
            A := TAlphaColorRec(C).A;

            var NearBg := False;
            for var D := 0 to 3 do
            begin
              CurrX := X + DX[D];
              CurrY := Y + DY[D];
              if (CurrX >= 0) and (CurrX < W) and (CurrY >= 0) and (CurrY < H) then
              begin
                if IsBackground[CurrY * W + CurrX] then
                begin
                  NearBg := True;
                  Break;
                end;
              end;
            end;

            if NearBg then
            begin
              var Dist := GetColorDist(C, BgR, BgG, BgB);
              if Dist < (Tolerance + 20.0) then
              begin
                var Factor := (Dist - Tolerance) / 20.0;
                if Factor < 0.0 then Factor := 0.0;
                if Factor > 1.0 then Factor := 1.0;

                var NewAlpha := Round(A * Factor);
                C := (Cardinal(NewAlpha) shl 24) or
                     (Cardinal(R) shl 16) or
                     (Cardinal(G) shl 8)  or
                     Cardinal(B);
                Data.SetPixel(X, Y, C);
              end;
            end;
          end;
        end;
      end;

      Result := True;
    finally
      Queue.Free;
    end;
  finally
    ABitmap.Unmap(Data);
  end;
end;


function FormatFileSize(const Bytes: Int64): string;
const
  Tera = Int64(1024) * 1024 * 1024 * 1024; // 1 TB
  Giga = Int64(1024) * 1024 * 1024;        // 1 GB
  Mega = Int64(1024) * 1024;               // 1 MB
  Kilo = 1024;                             // 1 KB
begin
  if Bytes >= Tera then
    Result := Format('%.1f TB', [Bytes / Tera])
  else if Bytes >= Giga then
    Result := Format('%.1f GB', [Bytes / Giga])
  else if Bytes >= Mega then
    Result := Format('%.1f MB', [Bytes / Mega])
  else if Bytes >= Kilo then
    Result := Format('%.1f KB', [Bytes / Kilo])
  else
    Result := IntToStr(Bytes) + ' B';

  // Коррекция разделителя дробной части (замена запятой на точку, если в системе запятая)
  Result := StringReplace(Result, ',', '.', [rfReplaceAll]);
end;

function FormatFileDate(const DateTime: TDateTime): string;
begin
  if DateTime <= 0 then
    Result := ''
  else
    Result := FormatDateTime('dd.mm.yyyy HH:mm', DateTime);
end;

function IsBlockedReparsePath(const APath: string): Boolean;
var
  Attr: DWORD;
begin
  Result := False;
  if APath = '' then
    Exit;
  try
    Attr := GetFileAttributes(PChar(APath));
    { Нет Win32-атрибутов — не reparse, а shell/MTP (телефон, камера). }
    if Attr = INVALID_FILE_ATTRIBUTES then
      Exit(False);
    if (Attr and FILE_ATTRIBUTE_REPARSE_POINT) = 0 then
      Exit(False);
    Result := ((Attr and FILE_ATTRIBUTE_HIDDEN) <> 0) and
      ((Attr and FILE_ATTRIBUTE_SYSTEM) <> 0);
  except
    Result := False;
  end;
end;

function IsCloudPlaceholderPath(const APath: string): Boolean;
const
  FILE_ATTRIBUTE_RECALL_ON_OPEN = $00040000;
  FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = $00400000;
var
  Attr: DWORD;
begin
  Result := False;
  if APath = '' then
    Exit;
  try
    Attr := GetFileAttributes(PChar(APath));
    if Attr = INVALID_FILE_ATTRIBUTES then
      Exit;
    Result := ((Attr and FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS) <> 0) or
      ((Attr and FILE_ATTRIBUTE_RECALL_ON_OPEN) <> 0);
  except
    Result := False;
  end;
end;

function SafeGetFileAge(const APath: string; out AAge: TDateTime): Boolean;
var
  Attr: DWORD;
begin
  Result := False;
  AAge := 0;
  if APath = '' then
    Exit;
  try
    Attr := GetFileAttributes(PChar(APath));
    if Attr = INVALID_FILE_ATTRIBUTES then
      Exit;
    if ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) and
       ((Attr and FILE_ATTRIBUTE_HIDDEN) <> 0) and
       ((Attr and FILE_ATTRIBUTE_SYSTEM) <> 0) then
      Exit;
    Result := FileAge(APath, AAge);
  except
    Result := False;
    AAge := 0;
  end;
end;

const
  SHIL_LARGE_FALLBACK = 0;
  SHIL_EXTRALARGE_FALLBACK = 2;
  SHIL_JUMBO_FALLBACK = 4;
  ILD_TRANSPARENT_FALLBACK = 1;
  SIIGBF_RESIZETOFIT = $00000000;
  SIIGBF_ICONONLY = $00000004;
  SIIGBF_THUMBNAILONLY = $00000008;
  SIIGBF_SCALEUP = $00000100;
  IID_IImageList: TGUID = '{46EB5926-582E-4017-9FDF-E8998DAA0950}';
  BHID_ThumbnailHandler: TGUID = '{e357fccd-a995-4576-b01f-234630154e96}';
  E_PENDING_HR = HRESULT($8000000A);
  HRESULT_BUSY = HRESULT($800700AA);
  IconPixelMax = 256;
  ThumbPixelMax = 256;

type
  IShellImageList = interface(IUnknown)
    ['{46EB5926-582E-4017-9FDF-E8998DAA0950}']
    function Add(Image, Mask: Pointer; var Index: Integer): HRESULT; stdcall;
    function ReplaceIcon(Index: Integer; Icon: HICON; var IndexRes: Integer): HRESULT; stdcall;
    function SetOverlayImage(iImage, iOverlay: Integer): HRESULT; stdcall;
    function Replace(Index: Integer; Image, Mask: Pointer): HRESULT; stdcall;
    function AddMasked(Image: Pointer; MaskColor: COLORREF; var Index: Integer): HRESULT; stdcall;
    function Draw(p: Pointer): HRESULT; stdcall;
    function Remove(Index: Integer): HRESULT; stdcall;
    function GetIcon(Index: Integer; Flags: UINT; out Icon: HICON): HRESULT; stdcall;
  end;

  IThumbnailProvider = interface(IUnknown)
    ['{E357FCCD-A995-4576-B01F-234630154E96}']
    function GetThumbnail(cx: UINT; out phbmp: HBITMAP; out pdwAlpha: DWORD): HRESULT; stdcall;
  end;

function SHGetImageList(iImageList: Integer; const riid: TGUID; out ppvOut): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetImageList';

function ExtractIconsEx(lpszFile: LPCWSTR; nIconIndex, cxIcon, cyIcon: Integer;
  phicon: Pointer; piconid: Pointer; nIcons, flags: UINT): UINT; stdcall;
  external 'user32.dll' name 'PrivateExtractIconsW';

function DefExtractIconEx(pszIconFile: LPCWSTR; iIndex: Integer; uFlags: UINT;
  phiconLarge: Pointer; phiconSmall: Pointer; nIconSize: UINT): HRESULT; stdcall;
  external 'shell32.dll' name 'SHDefExtractIconW';

function BgraHasAlpha(const APixels: TBytes): Boolean;
var
  I: Integer;
begin
  Result := False;
  I := 3;
  while I < Length(APixels) do
  begin
    if APixels[I] <> 0 then
      Exit(True);
    Inc(I, 4);
  end;
end;

procedure ForceOpaqueAlpha(var APixels: TBytes);
var
  I: Integer;
begin
  I := 3;
  while I < Length(APixels) do
  begin
    APixels[I] := 255;
    Inc(I, 4);
  end;
end;

function PixelDist2(const APixels: TBytes; AIndex, AR, AG, AB: Integer): Integer;
var
  DR, DG, DB: Integer;
begin
  DB := Integer(APixels[AIndex]) - AB;
  DG := Integer(APixels[AIndex + 1]) - AG;
  DR := Integer(APixels[AIndex + 2]) - AR;
  Result := DR * DR + DG * DG + DB * DB;
end;

function BgraUsefulAlpha(const APixels: TBytes; AWidth, AHeight: Integer): Boolean;
var
  I, N, ClearN, SolidN: Integer;
begin
  Result := False;
  N := AWidth * AHeight;
  if N < 16 then
    Exit;
  ClearN := 0;
  SolidN := 0;
  I := 3;
  while I < Length(APixels) do
  begin
    if APixels[I] <= 12 then
      Inc(ClearN)
    else if APixels[I] >= 240 then
      Inc(SolidN);
    Inc(I, 4);
  end;
  Result := (ClearN > N div 20) and (SolidN > 0);
end;

procedure CropBgraRect(var APixels: TBytes; var AWidth, AHeight: Integer;
  MinX, MinY, MaxX, MaxY: Integer);
var
  NewW, NewH, Y: Integer;
  Dst: TBytes;
begin
  NewW := MaxX - MinX + 1;
  NewH := MaxY - MinY + 1;
  if (NewW <= 0) or (NewH <= 0) then
    Exit;
  if (NewW >= AWidth) and (NewH >= AHeight) then
    Exit;
  if (NewW >= Trunc(AWidth * 0.94)) and (NewH >= Trunc(AHeight * 0.94)) then
    Exit;
  SetLength(Dst, NewW * NewH * 4);
  for Y := 0 to NewH - 1 do
    Move(APixels[((Y + MinY) * AWidth + MinX) * 4], Dst[Y * NewW * 4], NewW * 4);
  APixels := Dst;
  AWidth := NewW;
  AHeight := NewH;
end;

procedure CropBgraToContent(var APixels: TBytes; var AWidth, AHeight: Integer);
var
  MinX, MinY, MaxX, MaxY, X, Y, I: Integer;
  A, BgR, BgG, BgB: Byte;
  UseAlpha: Boolean;
  DistTol2: Integer;
begin
  if (AWidth < 8) or (AHeight < 8) or (Length(APixels) < AWidth * AHeight * 4) then
    Exit;
  MinX := AWidth;
  MinY := AHeight;
  MaxX := -1;
  MaxY := -1;
  UseAlpha := BgraUsefulAlpha(APixels, AWidth, AHeight);
  if UseAlpha then
  begin
    for Y := 0 to AHeight - 1 do
      for X := 0 to AWidth - 1 do
      begin
        A := APixels[(Y * AWidth + X) * 4 + 3];
        if A > 12 then
        begin
          if X < MinX then MinX := X;
          if Y < MinY then MinY := Y;
          if X > MaxX then MaxX := X;
          if Y > MaxY then MaxY := Y;
        end;
      end;
  end
  else
  begin
    { Jumbo 256: глиф часто в левом верхнем углу, фон — непрозрачный квадрат.
      Фон берём с правого нижнего края, не со среднего по углам. }
    I := ((AHeight - 1) * AWidth + (AWidth - 1)) * 4;
    BgB := APixels[I];
    BgG := APixels[I + 1];
    BgR := APixels[I + 2];
    DistTol2 := 40 * 40;
    for Y := 0 to AHeight - 1 do
      for X := 0 to AWidth - 1 do
      begin
        I := (Y * AWidth + X) * 4;
        if APixels[I + 3] <= 12 then
          Continue;
        if PixelDist2(APixels, I, BgR, BgG, BgB) > DistTol2 then
        begin
          if X < MinX then MinX := X;
          if Y < MinY then MinY := Y;
          if X > MaxX then MaxX := X;
          if Y > MaxY then MaxY := Y;
        end;
      end;
  end;
  if MaxX < MinX then
    Exit;
  CropBgraRect(APixels, AWidth, AHeight, MinX, MinY, MaxX, MaxY);
end;

procedure NormalizeIconPixels(var APixels: TBytes; var AWidth, AHeight: Integer);
begin
  CropBgraToContent(APixels, AWidth, AHeight);
end;

procedure KnockOutWhiteFolderBg(var APixels: TBytes; AWidth, AHeight: Integer);
var
  X, Y, I: Integer;
  R, G, B, A: Byte;
  HasAlpha: Boolean;
begin
  if Length(APixels) < AWidth * AHeight * 4 then
    Exit;
  HasAlpha := BgraHasAlpha(APixels);
  if HasAlpha then
    Exit;
  for Y := 0 to AHeight - 1 do
    for X := 0 to AWidth - 1 do
    begin
      I := (Y * AWidth + X) * 4;
      B := APixels[I];
      G := APixels[I + 1];
      R := APixels[I + 2];
      A := APixels[I + 3];
      if (A > 0) and (R > 245) and (G > 245) and (B > 245) then
        APixels[I + 3] := 0;
    end;
end;

function HBitmapToBgra(hbm: HBITMAP; AMaxEdge: Integer; AOpaqueIfNoAlpha: Boolean;
  out APixels: TBytes; out AWidth, AHeight: Integer): Boolean;
var
  BM: BITMAP;
  SrcW, SrcH, DstW, DstH: Integer;
  BI: BITMAPINFO;
  SrcDC, DstDC: HDC;
  DstBmp, OldBmp, OldSrc: HBITMAP;
  Bits: Pointer;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  OldSrc := 0;
  if hbm = 0 then
    Exit;
  if GetObject(hbm, SizeOf(BM), @BM) = 0 then
    Exit;
  SrcW := BM.bmWidth;
  SrcH := Abs(BM.bmHeight);
  if (SrcW < 1) or (SrcH < 1) then
    Exit;
  if AMaxEdge < 16 then
    AMaxEdge := 16;
  if AMaxEdge > 1024 then
    AMaxEdge := 1024;
  if (SrcW <= AMaxEdge) and (SrcH <= AMaxEdge) then
  begin
    DstW := SrcW;
    DstH := SrcH;
  end
  else if SrcW >= SrcH then
  begin
    DstW := AMaxEdge;
    DstH := Max(1, Round(SrcH * AMaxEdge / SrcW));
  end
  else
  begin
    DstH := AMaxEdge;
    DstW := Max(1, Round(SrcW * AMaxEdge / SrcH));
  end;

  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  BI.bmiHeader.biWidth := DstW;
  BI.bmiHeader.biHeight := -DstH;
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;

  try
    SetLength(APixels, DstW * DstH * 4);
  except
    SetLength(APixels, 0);
    Exit;
  end;

  if (DstW = SrcW) and (DstH = SrcH) then
  begin
    SrcDC := CreateCompatibleDC(0);
    if SrcDC = 0 then
    begin
      SetLength(APixels, 0);
      Exit;
    end;
    try
      Result := GetDIBits(SrcDC, hbm, 0, DstH, @APixels[0], BI, DIB_RGB_COLORS) > 0;
    finally
      DeleteDC(SrcDC);
    end;
  end
  else
  begin
    Bits := nil;
    DstDC := CreateCompatibleDC(0);
    if DstDC = 0 then
    begin
      SetLength(APixels, 0);
      Exit;
    end;
    DstBmp := CreateDIBSection(DstDC, BI, DIB_RGB_COLORS, Bits, 0, 0);
    if (DstBmp = 0) or (Bits = nil) then
    begin
      if DstBmp <> 0 then
        DeleteObject(DstBmp);
      DeleteDC(DstDC);
      SetLength(APixels, 0);
      Exit;
    end;
    OldBmp := SelectObject(DstDC, DstBmp);
    SrcDC := CreateCompatibleDC(0);
    OldSrc := 0;
    try
      if SrcDC <> 0 then
        OldSrc := SelectObject(SrcDC, hbm);
      SetStretchBltMode(DstDC, HALFTONE);
      SetBrushOrgEx(DstDC, 0, 0, nil);
      Result := (SrcDC <> 0) and
        StretchBlt(DstDC, 0, 0, DstW, DstH, SrcDC, 0, 0, SrcW, SrcH, SRCCOPY);
      if Result then
        Move(Bits^, APixels[0], Length(APixels));
    finally
      if (SrcDC <> 0) and (OldSrc <> 0) then
        SelectObject(SrcDC, OldSrc);
      SelectObject(DstDC, OldBmp);
      DeleteObject(DstBmp);
      if SrcDC <> 0 then
        DeleteDC(SrcDC);
      DeleteDC(DstDC);
    end;
  end;

  if not Result then
  begin
    SetLength(APixels, 0);
    Exit;
  end;
  if AOpaqueIfNoAlpha and not BgraHasAlpha(APixels) then
    ForceOpaqueAlpha(APixels);
  AWidth := DstW;
  AHeight := DstH;
end;

procedure ApplyIconMaskAlpha(hbmMask: HBITMAP; var APixels: TBytes; AWidth, AHeight: Integer);
var
  Mask: TBytes;
  MW, MH, X, Y, I, J: Integer;
begin
  if (hbmMask = 0) or (AWidth < 1) or (AHeight < 1) then
    Exit;
  if not HBitmapToBgra(hbmMask, Max(AWidth, AHeight), True, Mask, MW, MH) then
    Exit;
  if (MW < 1) or (MH < 1) then
    Exit;
  for Y := 0 to Min(AHeight, MH) - 1 do
    for X := 0 to Min(AWidth, MW) - 1 do
    begin
      I := (Y * AWidth + X) * 4;
      J := (Y * MW + X) * 4;
      { Маска AND: белое = прозрачное. }
      if (Mask[J] > 200) and (Mask[J + 1] > 200) and (Mask[J + 2] > 200) then
        APixels[I + 3] := 0
      else if APixels[I + 3] = 0 then
        APixels[I + 3] := 255;
    end;
end;

function IconHandleToBgra(AIcon: HICON; out APixels: TBytes; out AWidth, AHeight: Integer): Boolean;
var
  Info: TIconInfo;
  BM: BITMAP;
  BI: BITMAPINFO;
  DC: HDC;
  Dib, Old: HBITMAP;
  Bits: Pointer;
  W, H: Integer;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  if AIcon = 0 then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  if not GetIconInfo(AIcon, Info) then
    Exit;
  try
    if Info.hbmColor <> 0 then
    begin
      if HBitmapToBgra(Info.hbmColor, IconPixelMax, False, APixels, AWidth, AHeight) then
      begin
        if (not BgraHasAlpha(APixels)) and (Info.hbmMask <> 0) then
          ApplyIconMaskAlpha(Info.hbmMask, APixels, AWidth, AHeight);
        if BgraHasAlpha(APixels) then
          Exit(True);
      end;
    end;
    if Info.hbmColor <> 0 then
      GetObject(Info.hbmColor, SizeOf(BM), @BM)
    else if Info.hbmMask <> 0 then
      GetObject(Info.hbmMask, SizeOf(BM), @BM)
    else
      Exit;
    W := BM.bmWidth;
    H := Abs(BM.bmHeight);
    if Info.hbmColor = 0 then
      H := H div 2;
  finally
    if Info.hbmColor <> 0 then
      DeleteObject(Info.hbmColor);
    if Info.hbmMask <> 0 then
      DeleteObject(Info.hbmMask);
  end;
  if (W < 1) or (H < 1) or (W > 512) or (H > 512) then
    Exit;

  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  BI.bmiHeader.biWidth := W;
  BI.bmiHeader.biHeight := -H;
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  Bits := nil;
  DC := CreateCompatibleDC(0);
  if DC = 0 then
    Exit;
  Dib := CreateDIBSection(DC, BI, DIB_RGB_COLORS, Bits, 0, 0);
  if (Dib = 0) or (Bits = nil) then
  begin
    if Dib <> 0 then
      DeleteObject(Dib);
    DeleteDC(DC);
    Exit;
  end;
  Old := SelectObject(DC, Dib);
  try
    FillChar(Bits^, W * H * 4, 0);
    DrawIconEx(DC, 0, 0, AIcon, W, H, 0, 0, DI_NORMAL);
    SetLength(APixels, W * H * 4);
    Move(Bits^, APixels[0], Length(APixels));
    AWidth := W;
    AHeight := H;
    Result := True;
  finally
    SelectObject(DC, Old);
    DeleteObject(Dib);
    DeleteDC(DC);
  end;
end;

procedure BgraToFmxBitmap(const APixels: TBytes; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap);
var
  Data: TBitmapData;
  X, Y: Integer;
  S: PByte;
  Stride: Integer;
  Col: TAlphaColor;
begin
  if (ABitmap = nil) or (AWidth < 1) or (AHeight < 1) then
    Exit;
  if Length(APixels) < AWidth * AHeight * 4 then
    Exit;
  try
    ABitmap.SetSize(AWidth, AHeight);
  except
    ABitmap.SetSize(0, 0);
    Exit;
  end;
  if not ABitmap.Map(TMapAccess.Write, Data) then
    Exit;
  try
    Stride := AWidth * 4;
    for Y := 0 to AHeight - 1 do
    begin
      S := @APixels[Y * Stride];
      for X := 0 to AWidth - 1 do
      begin
        Col := TAlphaColor((Cardinal(S[3]) shl 24) or (Cardinal(S[2]) shl 16) or
          (Cardinal(S[1]) shl 8) or Cardinal(S[0]));
        Data.SetPixel(X, Y, Col);
        Inc(S, 4);
      end;
    end;
  finally
    ABitmap.Unmap(Data);
  end;
end;

procedure RawToFmxBitmap(const APixels: TBytes; AWidth, AHeight: Integer;
  var ABitmap: FMX.Graphics.TBitmap);
begin
  ABitmap := nil;
  if (AWidth < 1) or (AHeight < 1) or (Length(APixels) < AWidth * AHeight * 4) then
    Exit;
  ABitmap := FMX.Graphics.TBitmap.Create;
  try
    BgraToFmxBitmap(APixels, AWidth, AHeight, ABitmap);
    if (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
      FreeAndNil(ABitmap);
  except
    FreeAndNil(ABitmap);
  end;
end;

procedure IconHandleToFmxBitmap(AIcon: HICON; var ABitmap: FMX.Graphics.TBitmap);
var
  Pixels: TBytes;
  W, H: Integer;
begin
  ABitmap := nil;
  if not IconHandleToBgra(AIcon, Pixels, W, H) then
    Exit;
  NormalizeIconPixels(Pixels, W, H);
  RawToFmxBitmap(Pixels, W, H, ABitmap);
end;

var
  GSysImageLock: TCriticalSection;

function LooksLikePaperSheet(const APixels: TBytes; AWidth, AHeight: Integer): Boolean;
var
  X, Y, Off, Corner, Light, Total: Integer;
  R, G, B, A: Byte;
begin
  Result := False;
  if (AWidth < 24) or (AHeight < 24) or
     (Length(APixels) < AWidth * AHeight * 4) then
    Exit;
  Light := 0;
  Total := 0;
  for Y := 0 to AHeight - 1 do
    for X := 0 to AWidth - 1 do
    begin
      if (X > 1) and (X < AWidth - 2) and (Y > 1) and (Y < AHeight - 2) then
        Continue;
      Off := (Y * AWidth + X) * 4;
      B := APixels[Off];
      G := APixels[Off + 1];
      R := APixels[Off + 2];
      A := APixels[Off + 3];
      Inc(Total);
      if (A >= 200) and (R >= 210) and (G >= 210) and (B >= 210) then
        Inc(Light);
    end;
  if (Total = 0) or (Light * 100 < Total * 72) then
    Exit;
  Corner := 0;
  for X := 0 to 1 do
    for Y := 0 to 1 do
    begin
      Off := ((Y * (AHeight - 1)) * AWidth + (X * (AWidth - 1))) * 4;
      B := APixels[Off];
      G := APixels[Off + 1];
      R := APixels[Off + 2];
      A := APixels[Off + 3];
      if (A >= 200) and (R >= 210) and (G >= 210) and (B >= 210) then
        Inc(Corner);
    end;
  Result := Corner >= 3;
end;

function SysImageListIconRaw(AList, AIndex: Integer; out APixels: TBytes;
  out AWidth, AHeight: Integer): Boolean;
var
  Images: IShellImageList;
  Pv: Pointer;
  hIco: HICON;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  if AIndex < 0 then
    Exit;
  GSysImageLock.Enter;
  try
    Pv := nil;
    if Failed(SHGetImageList(AList, IID_IImageList, Pv)) or (Pv = nil) then
      Exit;
    Images := IShellImageList(Pv);
    hIco := 0;
    if Failed(Images.GetIcon(AIndex, ILD_TRANSPARENT_FALLBACK, hIco)) or (hIco = 0) then
      Exit;
    try
      Result := IconHandleToBgra(hIco, APixels, AWidth, AHeight);
      if Result then
        NormalizeIconPixels(APixels, AWidth, AHeight);
    finally
      DestroyIcon(hIco);
    end;
  finally
    GSysImageLock.Leave;
  end;
end;

function BestSysIconRaw(AIndex: Integer; out APixels: TBytes;
  out AWidth, AHeight: Integer; AMinPx: Integer = 32): Boolean;
var
  Lists: array[0..2] of Integer;
  I, BestW, BestH: Integer;
  Best: TBytes;
  W, H: Integer;
  Pix: TBytes;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  if AMinPx < 16 then
    AMinPx := 16;
  if AMinPx <= 32 then
  begin
    Lists[0] := SHIL_LARGE_FALLBACK;
    Lists[1] := SHIL_EXTRALARGE_FALLBACK;
    Lists[2] := SHIL_JUMBO_FALLBACK;
  end
  else if AMinPx <= 48 then
  begin
    Lists[0] := SHIL_EXTRALARGE_FALLBACK;
    Lists[1] := SHIL_JUMBO_FALLBACK;
    Lists[2] := SHIL_LARGE_FALLBACK;
  end
  else
  begin
    Lists[0] := SHIL_JUMBO_FALLBACK;
    Lists[1] := SHIL_EXTRALARGE_FALLBACK;
    Lists[2] := SHIL_LARGE_FALLBACK;
  end;
  BestW := 0;
  BestH := 0;
  SetLength(Best, 0);
  for I := 0 to 2 do
  begin
    if not SysImageListIconRaw(Lists[I], AIndex, Pix, W, H) then
      Continue;
    if (W >= AMinPx) and (H >= AMinPx) then
    begin
      APixels := Pix;
      AWidth := W;
      AHeight := H;
      Exit(True);
    end;
    if W * H > BestW * BestH then
    begin
      Best := Pix;
      BestW := W;
      BestH := H;
    end;
  end;
  if BestW > 0 then
  begin
    APixels := Best;
    AWidth := BestW;
    AHeight := BestH;
    Result := True;
  end;
end;

function TypeDummyPath(const AIconKey: string; AIsDir: Boolean; out AAttr: DWORD): string;
var
  Key: string;
begin
  Key := LowerCase(AIconKey);
  if AIsDir or (Key = '#dir') or (Key = '#drive') then
  begin
    Result := 'folder';
    AAttr := FILE_ATTRIBUTE_DIRECTORY;
  end
  else
  begin
    AAttr := FILE_ATTRIBUTE_NORMAL;
    if (Key = '') or (Key = '#file') then
      Result := 'file'
    else if (Length(Key) > 0) and (Key[1] = '.') then
      Result := 'file' + Key
    else
      Result := 'file.' + Key;
  end;
end;

function IsShellNamespacePath(const APath: string): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(APath));
  Result := (Copy(L, 1, 2) = '::') or (Pos('::{', L) > 0) or
    (Copy(L, 1, 6) = 'shell:') or (Pos('usb#vid_', L) > 0) or
    (Pos('{6ac27878-a6fa-4155-ba85-f98f491d4f33}', L) > 0) or
    (Pos('portabledevice', L) > 0);
end;

function TryMakeShellItem(const APath: string; out AItem: IShellItem): Boolean;
var
  Pidl: PItemIDList;
  Attr: DWORD;
begin
  AItem := nil;
  Result := False;
  if Trim(APath) = '' then
    Exit;
  if Succeeded(SHCreateItemFromParsingName(PChar(APath), nil, IShellItem, AItem)) and
     Assigned(AItem) then
    Exit(True);
  AItem := nil;
  Pidl := nil;
  Attr := 0;
  if Succeeded(SHParseDisplayName(PChar(APath), nil, Pidl, 0, Attr)) and (Pidl <> nil) then
  try
    Result := Succeeded(SHCreateItemFromIDList(Pidl, IShellItem, AItem)) and Assigned(AItem);
    if not Result then
      AItem := nil;
  finally
    CoTaskMemFree(Pidl);
  end;
end;

function AsShellItem(const AItem: IUnknown; out AShell: IShellItem): Boolean;
begin
  AShell := nil;
  Result := Assigned(AItem) and Supports(AItem, IShellItem, AShell) and Assigned(AShell);
end;

function IsComputerSysIcon(AIndex: Integer): Boolean;
var
  SFI: TSHFileInfo;
  Pidl: PItemIDList;
begin
  Result := False;
  if AIndex <= 0 then
    Exit;
  Pidl := nil;
  if Failed(SHGetSpecialFolderLocation(0, CSIDL_DRIVES, Pidl)) or (Pidl = nil) then
    Exit;
  try
    FillChar(SFI, SizeOf(SFI), 0);
    if SHGetFileInfo(PChar(Pidl), 0, SFI, SizeOf(SFI),
         SHGFI_PIDL or SHGFI_SYSICONINDEX) <> 0 then
      Result := SFI.iIcon = AIndex;
  finally
    CoTaskMemFree(Pidl);
  end;
end;

function ShellItemSysIconIndex(const AItem: IShellItem; out AIndex: Integer): Boolean;
var
  Pidl: PItemIDList;
  SFI: TSHFileInfo;
begin
  Result := False;
  AIndex := 0;
  if AItem = nil then
    Exit;
  Pidl := nil;
  if Failed(SHGetIDListFromObject(AItem, Pidl)) or (Pidl = nil) then
    Exit;
  try
    FillChar(SFI, SizeOf(SFI), 0);
    Result := SHGetFileInfo(PChar(Pidl), 0, SFI, SizeOf(SFI),
      SHGFI_PIDL or SHGFI_SYSICONINDEX) <> 0;
    if Result then
      AIndex := SFI.iIcon;
  finally
    CoTaskMemFree(Pidl);
  end;
end;

function ShellItemImageFromItem(const AItem: IShellItem; AWidth, AHeight, AFlags,
  AMaxEdge: Integer; AOpaqueIfNoAlpha: Boolean; out APixels: TBytes;
  out AOutW, AOutH: Integer): Boolean;
var
  ImageFactory: IShellItemImageFactory;
  Size: TSize;
  hBmp: HBITMAP;
  Hr: HRESULT;
  Tries: Integer;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if AItem = nil then
    Exit;
  Size.cx := Max(16, AWidth);
  Size.cy := Max(16, AHeight);
  hBmp := 0;
  try
    if Failed(AItem.QueryInterface(IShellItemImageFactory, ImageFactory)) then
      Exit;
    Tries := 0;
    repeat
      if hBmp <> 0 then
      begin
        DeleteObject(hBmp);
        hBmp := 0;
      end;
      Hr := ImageFactory.GetImage(Size, AFlags, hBmp);
      if Succeeded(Hr) and (hBmp <> 0) then
        Break;
      Inc(Tries);
      if (Hr <> E_PENDING_HR) and (Hr <> HRESULT_BUSY) then
        Break;
      Sleep(40);
    until Tries >= 6;
    if (hBmp = 0) or Failed(Hr) then
      Exit;
    Result := HBitmapToBgra(hBmp, AMaxEdge, AOpaqueIfNoAlpha, APixels, AOutW, AOutH);
  except
    Result := False;
    SetLength(APixels, 0);
  end;
  if hBmp <> 0 then
    DeleteObject(hBmp);
end;

function ShellItemImageRaw(const APath: string; AWidth, AHeight, AFlags, AMaxEdge: Integer;
  AOpaqueIfNoAlpha: Boolean; out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
var
  ShellItem: IShellItem;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if (APath = '') or IsCloudPlaceholderPath(APath) then
    Exit;
  if IsBlockedReparsePath(APath) then
    Exit;
  if not TryMakeShellItem(APath, ShellItem) then
    Exit;
  Result := ShellItemImageFromItem(ShellItem, AWidth, AHeight, AFlags, AMaxEdge,
    AOpaqueIfNoAlpha, APixels, AOutW, AOutH);
end;

function GetShellItemIconRaw(const AItem: IUnknown; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  APixelSize: Integer): Boolean;
var
  SI: IShellItem;
  Idx, Want: Integer;
  GotImg, GotIdx: Boolean;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if not AsShellItem(AItem, SI) then
    Exit;
  Want := APixelSize;
  if Want < 16 then
    Want := 16;
  if Want > IconPixelMax then
    Want := IconPixelMax;
  GotImg := ShellItemImageFromItem(SI, Want, Want, SIIGBF_ICONONLY,
    Want, False, APixels, AOutW, AOutH);
  if GotImg then
  begin
    NormalizeIconPixels(APixels, AOutW, AOutH);
    if LooksLikePaperSheet(APixels, AOutW, AOutH) then
    begin
      SetLength(APixels, 0);
      AOutW := 0;
      AOutH := 0;
      GotImg := False;
    end;
  end;
  GotIdx := ShellItemSysIconIndex(SI, Idx);
  { Папка, которую shell свёл к «Этот компьютер» — не монитор, а обычная папка. }
  if AIsDir and GotIdx and IsComputerSysIcon(Idx) then
  begin
    SetLength(APixels, 0);
    Result := GetTypeIconRaw('#dir', True, APixels, AOutW, AOutH, Want);
    Exit;
  end;
  if GotImg and (AOutW >= 8) and (AOutH >= 8) then
    Exit(True);
  if GotIdx then
    Result := BestSysIconRaw(Idx, APixels, AOutW, AOutH, Want);
  if Result then
    Exit;
  if AIsDir then
    Result := GetTypeIconRaw('#dir', True, APixels, AOutW, AOutH, Want);
end;

function GetShellItemThumbnailRaw(const AItem: IUnknown; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
var
  SI: IShellItem;
  Prov: IThumbnailProvider;
  W, H, MaxEdge: Integer;
  hBmp: HBITMAP;
  Alpha: DWORD;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if not AsShellItem(AItem, SI) then
    Exit;
  W := Max(16, AWidth);
  H := Max(16, AHeight);
  MaxEdge := Max(W, H);
  if MaxEdge > 1024 then
    MaxEdge := 1024;
  Result := ShellItemImageFromItem(SI, W, H, SIIGBF_THUMBNAILONLY, MaxEdge, True,
    APixels, AOutW, AOutH);
  if not Result then
    Result := ShellItemImageFromItem(SI, W, H, SIIGBF_RESIZETOFIT, MaxEdge, True,
      APixels, AOutW, AOutH);
  if Result then
    Exit;
  Prov := nil;
  hBmp := 0;
  Alpha := 0;
  if Failed(SI.BindToHandler(nil, BHID_ThumbnailHandler, IThumbnailProvider, Prov)) or
     (Prov = nil) then
    Exit;
  if Failed(Prov.GetThumbnail(MaxEdge, hBmp, Alpha)) or (hBmp = 0) then
    Exit;
  try
    Result := HBitmapToBgra(hBmp, MaxEdge, True, APixels, AOutW, AOutH);
  finally
    DeleteObject(hBmp);
  end;
end;

function GetTypeIconRaw(const AIconKey: string; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  APixelSize: Integer): Boolean;
var
  SFI: TSHFileInfo;
  Dummy: string;
  Attr: DWORD;
  Flags: Cardinal;
  Want: Integer;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  Want := APixelSize;
  if Want < 16 then
    Want := 16;
  Dummy := TypeDummyPath(AIconKey, AIsDir, Attr);
  FillChar(SFI, SizeOf(SFI), 0);
  Flags := SHGFI_SYSICONINDEX or SHGFI_USEFILEATTRIBUTES;
  try
    if SHGetFileInfo(PChar(Dummy), Attr, SFI, SizeOf(SFI), Flags) = 0 then
      Exit;
  except
    Exit;
  end;
  Result := BestSysIconRaw(SFI.iIcon, APixels, AOutW, AOutH, Want);
  if Result then
    Exit;
  FillChar(SFI, SizeOf(SFI), 0);
  Flags := SHGFI_ICON or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES;
  try
    SHGetFileInfo(PChar(Dummy), Attr, SFI, SizeOf(SFI), Flags);
  except
    Exit;
  end;
  if SFI.hIcon = 0 then
    Exit;
  try
    Result := IconHandleToBgra(SFI.hIcon, APixels, AOutW, AOutH);
    if Result then
      NormalizeIconPixels(APixels, AOutW, AOutH);
  finally
    DestroyIcon(SFI.hIcon);
  end;
end;

function IsIconResourcePath(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.exe') or (Ext = '.dll') or (Ext = '.ico') or (Ext = '.icl') or
    (Ext = '.scr') or (Ext = '.cpl') or (Ext = '.ocx') or (Ext = '.sys') or
    (Ext = '.lnk') or (Ext = '.pif') or (Ext = '.com') or (Ext = '.msc');
end;

function TryIconHandleRaw(AIcon: HICON; out APixels: TBytes;
  out AWidth, AHeight: Integer): Boolean;
begin
  Result := (AIcon <> 0) and IconHandleToBgra(AIcon, APixels, AWidth, AHeight);
  if Result then
    NormalizeIconPixels(APixels, AWidth, AHeight);
  Result := Result and (AWidth > 0) and (AHeight > 0);
end;

function ExtractResourceIconRaw(const APath: string; out APixels: TBytes;
  out AWidth, AHeight: Integer; APixelSize: Integer = 256): Boolean;
var
  Sizes: array[0..3] of Integer;
  I, NTry: Integer;
  Large, Small: HICON;
  N: UINT;
begin
  Result := False;
  SetLength(APixels, 0);
  AWidth := 0;
  AHeight := 0;
  if APath = '' then
    Exit;
  if APixelSize <= 24 then
  begin
    Sizes[0] := 32;
    Sizes[1] := 48;
    Sizes[2] := 16;
    NTry := 3;
  end
  else if APixelSize <= 48 then
  begin
    Sizes[0] := 48;
    Sizes[1] := 32;
    Sizes[2] := 64;
    Sizes[3] := 256;
    NTry := 4;
  end
  else if APixelSize <= 64 then
  begin
    Sizes[0] := 64;
    Sizes[1] := 48;
    Sizes[2] := 256;
    Sizes[3] := 32;
    NTry := 4;
  end
  else
  begin
    Sizes[0] := 256;
    Sizes[1] := 64;
    Sizes[2] := 48;
    NTry := 3;
  end;
  for I := 0 to NTry - 1 do
  begin
    Large := 0;
    Small := 0;
    if Succeeded(DefExtractIconEx(PWideChar(APath), 0, 0, @Large, @Small, Sizes[I])) then
    begin
      if Small <> 0 then
        DestroyIcon(Small);
      if Large <> 0 then
      try
        Result := TryIconHandleRaw(Large, APixels, AWidth, AHeight);
      finally
        DestroyIcon(Large);
      end;
      if Result then
        Exit;
    end;
    Large := 0;
    N := ExtractIconsEx(PWideChar(APath), 0, Sizes[I], Sizes[I], @Large, nil, 1,
      LR_DEFAULTCOLOR);
    if (N > 0) and (Large <> 0) then
    try
      Result := TryIconHandleRaw(Large, APixels, AWidth, AHeight);
    finally
      DestroyIcon(Large);
    end;
    if Result then
      Exit;
  end;
end;

function GetFileIconRaw(const AFilePath: string; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer;
  APixelSize: Integer): Boolean;
var
  SFI: TSHFileInfo;
  Flags: Cardinal;
  Pidl: PItemIDList;
  Attr: ULONG;
  SI: IShellItem;
  Want: Integer;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if AFilePath = '' then
    Exit;
  Want := APixelSize;
  if Want < 16 then
    Want := 16;
  if Want > IconPixelMax then
    Want := IconPixelMax;

  if (not AIsDir) and IsIconResourcePath(AFilePath) and
     not IsBlockedReparsePath(AFilePath) and not IsCloudPlaceholderPath(AFilePath) then
  begin
    Result := ExtractResourceIconRaw(AFilePath, APixels, AOutW, AOutH, Want);
    if Result then
      Exit;
  end;

  { MTP/shell: не вызывать SHGetFileInfo по parsing-имени.
    Строка с CLSID "Этот компьютер" даёт иконку монитора. Нужен IShellItem/PIDL. }
  if IsShellNamespacePath(AFilePath) then
  begin
    if TryMakeShellItem(AFilePath, SI) then
      Result := GetShellItemIconRaw(SI, AIsDir, APixels, AOutW, AOutH, Want);
    if Result then
      Exit;
    if AIsDir then
      Result := GetTypeIconRaw('#dir', True, APixels, AOutW, AOutH, Want)
    else
      Result := GetTypeIconRaw(ExtractFileExt(AFilePath), False, APixels, AOutW, AOutH, Want);
    Exit;
  end;

  if not IsBlockedReparsePath(AFilePath) and not IsCloudPlaceholderPath(AFilePath) then
  begin
    Result := ShellItemImageRaw(AFilePath, Want, Want,
      SIIGBF_ICONONLY, Want, False, APixels, AOutW, AOutH);
    if Result then
    begin
      NormalizeIconPixels(APixels, AOutW, AOutH);
      if LooksLikePaperSheet(APixels, AOutW, AOutH) then
      begin
        SetLength(APixels, 0);
        AOutW := 0;
        AOutH := 0;
        Result := False;
      end
      else if (AOutW >= 8) and (AOutH >= 8) then
        Exit;
    end;
  end;

  FillChar(SFI, SizeOf(SFI), 0);
  Flags := SHGFI_SYSICONINDEX;
  try
    if IsBlockedReparsePath(AFilePath) then
    begin
      if AIsDir then
        Result := SHGetFileInfo(PChar(AFilePath), FILE_ATTRIBUTE_DIRECTORY, SFI, SizeOf(SFI),
          Flags or SHGFI_USEFILEATTRIBUTES) <> 0;
    end
    else
    begin
      Result := SHGetFileInfo(PChar(AFilePath), 0, SFI, SizeOf(SFI), Flags) <> 0;
      if not Result then
      begin
        Pidl := nil;
        if Succeeded(SHParseDisplayName(PChar(AFilePath), nil, Pidl, 0, Attr)) then
        try
          FillChar(SFI, SizeOf(SFI), 0);
          Result := SHGetFileInfo(PChar(Pidl), 0, SFI, SizeOf(SFI), Flags or SHGFI_PIDL) <> 0;
        finally
          CoTaskMemFree(Pidl);
        end;
      end;
    end;
  except
    Result := False;
    FillChar(SFI, SizeOf(SFI), 0);
  end;

  if Result then
    Result := BestSysIconRaw(SFI.iIcon, APixels, AOutW, AOutH, Want);
  if Result then
    Exit;

  Result := GetTypeIconRaw(ExtractFileExt(AFilePath), AIsDir, APixels, AOutW, AOutH, Want);
end;

function ExpandEnvPath(const APath: string): string;
var
  N: DWORD;
begin
  Result := APath;
  if APath = '' then
    Exit;
  N := ExpandEnvironmentStrings(PChar(APath), nil, 0);
  if N = 0 then
    Exit;
  SetLength(Result, N);
  N := ExpandEnvironmentStrings(PChar(APath), PChar(Result), N);
  if N > 0 then
    SetLength(Result, N - 1);
end;

function SplitIconSpec(const ASpec: string; out AFile: string; out AIndex: Integer): Boolean;
var
  S: string;
  P: Integer;
begin
  Result := False;
  AFile := '';
  AIndex := 0;
  S := Trim(ASpec);
  if S = '' then
    Exit;
  if (Length(S) >= 2) and (S[1] = '"') then
  begin
    Delete(S, 1, 1);
    P := Pos('"', S);
    if P > 0 then
    begin
      AFile := Copy(S, 1, P - 1);
      S := Trim(Copy(S, P + 1, MaxInt));
      if (S <> '') and (S[1] = ',') then
        Delete(S, 1, 1);
      AIndex := StrToIntDef(Trim(S), 0);
      Exit(AFile <> '');
    end;
  end;
  P := LastDelimiter(',', S);
  if P > 0 then
  begin
    AFile := Trim(Copy(S, 1, P - 1));
    AIndex := StrToIntDef(Trim(Copy(S, P + 1, MaxInt)), 0);
  end
  else
    AFile := S;
  Result := AFile <> '';
end;

function ReadFolderIconSpec(const AFolder: string; out ARes: string; out AIndex: Integer): Boolean;
var
  IniPath, Line, Sec, IconFile: string;
  SL: TStringList;
  I, Idx: Integer;
  InShell: Boolean;
begin
  Result := False;
  ARes := '';
  AIndex := 0;
  IconFile := '';
  Idx := 0;
  IniPath := TPath.Combine(AFolder, 'desktop.ini');
  if not TFile.Exists(IniPath) then
    Exit;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(IniPath, TEncoding.UTF8);
    except
      try
        SL.LoadFromFile(IniPath);
      except
        Exit;
      end;
    end;
    InShell := False;
    for I := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[I]);
      if Line = '' then
        Continue;
      if (Line[1] = '[') and (Line[Length(Line)] = ']') then
      begin
        Sec := LowerCase(Copy(Line, 2, Length(Line) - 2));
        InShell := (Sec = '.shellclassinfo');
        Continue;
      end;
      if not InShell then
        Continue;
      if (Length(Line) >= 13) and SameText(Copy(Line, 1, 13), 'IconResource=') then
      begin
        if SplitIconSpec(Copy(Line, 14, MaxInt), ARes, AIndex) then
          Exit(True);
      end
      else if (Length(Line) >= 9) and SameText(Copy(Line, 1, 9), 'IconFile=') then
        IconFile := Copy(Line, 10, MaxInt)
      else if (Length(Line) >= 10) and SameText(Copy(Line, 1, 10), 'IconIndex=') then
        Idx := StrToIntDef(Trim(Copy(Line, 11, MaxInt)), 0);
    end;
    if IconFile <> '' then
    begin
      ARes := IconFile;
      AIndex := Idx;
      Result := True;
    end;
  finally
    SL.Free;
  end;
end;

function ResolveShortcutTarget(const ALnk: string; out ATarget: string; out AIsDir: Boolean): Boolean;
var
  Link: IShellLink;
  Pf: IPersistFile;
  Buf: array[0..MAX_PATH] of WideChar;
  Fd: TWin32FindData;
begin
  Result := False;
  ATarget := '';
  AIsDir := False;
  if Failed(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER,
      IShellLink, Link)) then
    Exit;
  if Failed(Link.QueryInterface(IPersistFile, Pf)) then
    Exit;
  if Failed(Pf.Load(PWideChar(ALnk), STGM_READ)) then
    Exit;
  FillChar(Fd, SizeOf(Fd), 0);
  FillChar(Buf, SizeOf(Buf), 0);
  if Failed(Link.GetPath(@Buf[0], MAX_PATH, Fd, 0)) then
    Exit;
  ATarget := ExcludeTrailingPathDelimiter(string(Buf));
  AIsDir := (Fd.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0;
  Result := ATarget <> '';
end;

function ExtractBySpec(const ARes: string; AIndex: Integer; out APixels: TBytes;
  out AOutW, AOutH: Integer): Boolean;
var
  Large, Small: HICON;
begin
  Result := False;
  Large := 0;
  Small := 0;
  if Succeeded(DefExtractIconEx(PWideChar(ARes), AIndex, 0, @Large, @Small, 256)) then
  begin
    if Small <> 0 then
      DestroyIcon(Small);
    if Large <> 0 then
    try
      Result := TryIconHandleRaw(Large, APixels, AOutW, AOutH);
    finally
      DestroyIcon(Large);
    end;
  end;
  if not Result then
    Result := ExtractResourceIconRaw(ARes, APixels, AOutW, AOutH, 256);
end;

function ExtractDockJumboRaw(const AFilePath: string; AIsDir: Boolean;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
var
  Ext, Res, Target, Folder: string;
  Idx: Integer;
  TargetDir: Boolean;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if AFilePath = '' then
    Exit;
  Ext := LowerCase(ExtractFileExt(AFilePath));
  if AIsDir then
  begin
    Folder := ExcludeTrailingPathDelimiter(AFilePath);
    if ReadFolderIconSpec(Folder, Res, Idx) then
    begin
      Res := ExpandEnvPath(Res);
      if (Res <> '') and (ExtractFileDrive(Res) = '') then
        Res := TPath.Combine(Folder, Res);
      Result := ExtractBySpec(Res, Idx, APixels, AOutW, AOutH);
      if Result and (AOutW >= 48) and (AOutH >= 48) then
        Exit;
    end;
    Result := GetFileIconRaw(AFilePath, True, APixels, AOutW, AOutH, 256);
    Exit;
  end;
  if (Ext = '.exe') or (Ext = '.dll') or (Ext = '.scr') or (Ext = '.cpl') or
     (Ext = '.ico') or (Ext = '.icl') then
  begin
    Result := ExtractResourceIconRaw(AFilePath, APixels, AOutW, AOutH, 256);
    if Result and (AOutW >= 48) then
      Exit;
  end;
  if Ext = '.lnk' then
  begin
    if ResolveShortcutTarget(AFilePath, Target, TargetDir) then
    begin
      Result := ExtractDockJumboRaw(Target, TargetDir, APixels, AOutW, AOutH);
      if Result then
        Exit;
    end;
  end;
  Result := GetFileIconRaw(AFilePath, False, APixels, AOutW, AOutH, 256);
end;

procedure GetTypeIconBitmap(const AIconKey: string; AIsDir: Boolean; var ABitmap: FMX.Graphics.TBitmap);
var
  Pixels: TBytes;
  W, H: Integer;
begin
  ABitmap := nil;
  if GetTypeIconRaw(AIconKey, AIsDir, Pixels, W, H) then
    RawToFmxBitmap(Pixels, W, H, ABitmap);
end;

procedure GetFileIconBitmap(const AFilePath: string; IsFolder: Boolean; var ABitmap: FMX.Graphics.TBitmap);
var
  Pixels: TBytes;
  W, H: Integer;
begin
  ABitmap := nil;
  if GetFileIconRaw(AFilePath, IsFolder, Pixels, W, H) then
    RawToFmxBitmap(Pixels, W, H, ABitmap);
end;

procedure GetAppIconBitmap(var ABitmap: FMX.Graphics.TBitmap; ASize: Integer);
var
  H, Shared: HICON;
  WinIcon: TIcon;
  Png: TPngImage;
  Stream: TMemoryStream;
begin
  ABitmap := nil;
  if ASize <= 0 then
    ASize := GetSystemMetrics(SM_CXICON);

  { MAINICON = Icon_MainIcon из .dproj (VibeCmd.ico), уже в ресурсе exe.
    LoadImage с явным размером берёт нормальный слой, а не гигантский кадр ico. }
  H := LoadImage(HInstance, PChar('MAINICON'), IMAGE_ICON, ASize, ASize, LR_DEFAULTCOLOR);
  if H = 0 then
    H := LoadImage(HInstance, MAKEINTRESOURCE(1), IMAGE_ICON, ASize, ASize, LR_DEFAULTCOLOR);
  if H = 0 then
  begin
    Shared := LoadIcon(HInstance, 'MAINICON');
    if Shared <> 0 then
      H := CopyIcon(Shared);
  end;
  if H = 0 then
    Exit;

  WinIcon := TIcon.Create;
  try
    WinIcon.Handle := H;
    H := 0;
    Png := TPngImage.Create;
    try
      Icon2Png(WinIcon, Png);
      Stream := TMemoryStream.Create;
      try
        Png.SaveToStream(Stream);
        Stream.Position := 0;
        ABitmap := FMX.Graphics.TBitmap.Create(0, 0);
        ABitmap.LoadFromStream(Stream);
      finally
        Stream.Free;
      end;
    finally
      Png.Free;
    end;
  finally
    WinIcon.Free;
    if H <> 0 then
      DestroyIcon(H);
  end;
end;


function GetFileThumbnailRaw(const AFilePath: string; AWidth, AHeight: Integer;
  out APixels: TBytes; out AOutW, AOutH: Integer): Boolean;
var
  Attr: DWORD;
  IsFolder: Boolean;
  MaxEdge, W, H: Integer;
  SI: IShellItem;
begin
  Result := False;
  SetLength(APixels, 0);
  AOutW := 0;
  AOutH := 0;
  if AFilePath = '' then
    Exit;
  Attr := INVALID_FILE_ATTRIBUTES;
  try
    Attr := GetFileAttributes(PChar(AFilePath));
  except
    Attr := INVALID_FILE_ATTRIBUTES;
  end;
  if (Attr <> INVALID_FILE_ATTRIBUTES) then
  begin
    if IsBlockedReparsePath(AFilePath) or IsCloudPlaceholderPath(AFilePath) then
      Exit;
    IsFolder := (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0;
  end
  else
    IsFolder := False;
  W := Max(16, AWidth);
  H := Max(16, AHeight);
  MaxEdge := Max(W, H);
  if MaxEdge > 1024 then
    MaxEdge := 1024;

  if TryMakeShellItem(AFilePath, SI) then
  begin
    Result := GetShellItemThumbnailRaw(SI, W, H, APixels, AOutW, AOutH);
    if Result and IsFolder then
      KnockOutWhiteFolderBg(APixels, AOutW, AOutH);
    if Result then
      Exit;
  end;

  { Без BIGGERSIZEOK — иначе shell отдаёт 4K кадр и съедает память. }
  Result := ShellItemImageRaw(AFilePath, W, H, SIIGBF_THUMBNAILONLY, MaxEdge,
    not IsFolder, APixels, AOutW, AOutH);
  if not Result then
    Result := ShellItemImageRaw(AFilePath, W, H, SIIGBF_RESIZETOFIT, MaxEdge,
      not IsFolder, APixels, AOutW, AOutH);
  if Result and IsFolder then
    KnockOutWhiteFolderBg(APixels, AOutW, AOutH);
end;

function GetFileThumbnail(const AFilePath: string; AWidth, AHeight: Integer;
  ABitmap: FMX.Graphics.TBitmap): Boolean;
var
  Pixels: TBytes;
  W, H: Integer;
begin
  Result := False;
  if (ABitmap = nil) or (AFilePath = '') then
    Exit;
  ABitmap.SetSize(0, 0);
  if not GetFileThumbnailRaw(AFilePath, AWidth, AHeight, Pixels, W, H) then
    Exit;
  try
    BgraToFmxBitmap(Pixels, W, H, ABitmap);
    Result := (ABitmap.Width > 0) and (ABitmap.Height > 0);
    if Result and TDirectory.Exists(AFilePath) then
      MakeBackgroundTransparent(ABitmap);
  except
    Result := False;
    try
      ABitmap.SetSize(0, 0);
    except
    end;
  end;
end;

initialization
  GSysImageLock := TCriticalSection.Create;

finalization
  FreeAndNil(GSysImageLock);

end.
