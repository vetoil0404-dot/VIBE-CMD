unit uImageSniff;

{
  Сигнатура картинки, кадры ICO/CUR и запись multi-size ICO.
}

interface

uses
  System.SysUtils,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  FMX.Graphics;

type
  TImageSig = (isNone, isJpeg, isPng, isGif, isWebp, isBmp, isIco, isCur,
    isPdf, isSvg, isHeic, isAvif, isJxl, isPe, isZip);

function SniffImageFile(const APath: string): TImageSig;
function ImageSigName(ASig: TImageSig): string;
function ImageSigExt(ASig: TImageSig): string;
function ImageExtMatches(ASig: TImageSig; const AExt: string): Boolean;

function LoadIcoFrames(const APath: string; out AFrames: TArray<TBitmap>;
  out ALabels: TArray<string>): Boolean;
function SaveMultiIco(const ASource: TBitmap; const APath: string): Boolean;

implementation

uses
  System.Classes, System.Math, System.UITypes, System.IOUtils,
  FMX.Types, FMX.Surfaces, FMX.Skia, System.Skia;

function SniffImageFile(const APath: string): TImageSig;
var
  FS: TFileStream;
  B: TBytes;
  N: Integer;
  S: string;
begin
  Result := isNone;
  if (APath = '') or not System.IOUtils.TFile.Exists(APath) then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      N := Integer(Min(Int64(64), FS.Size));
      if N < 4 then
        Exit;
      SetLength(B, N);
      FS.ReadBuffer(B[0], N);
    finally
      FS.Free;
    end;
  except
    Exit;
  end;
  if (B[0] = $FF) and (B[1] = $D8) and (B[2] = $FF) then
    Exit(isJpeg);
  if (B[0] = $89) and (B[1] = $50) and (B[2] = $4E) and (B[3] = $47) then
    Exit(isPng);
  if (N >= 6) and (B[0] = Ord('G')) and (B[1] = Ord('I')) and (B[2] = Ord('F')) then
    Exit(isGif);
  if (N >= 12) and (B[0] = Ord('R')) and (B[1] = Ord('I')) and (B[2] = Ord('F')) and
     (B[3] = Ord('F')) and (B[8] = Ord('W')) and (B[9] = Ord('E')) and
     (B[10] = Ord('B')) and (B[11] = Ord('P')) then
    Exit(isWebp);
  if (B[0] = Ord('B')) and (B[1] = Ord('M')) then
    Exit(isBmp);
  if (B[0] = 0) and (B[1] = 0) and (B[2] = 1) and (B[3] = 0) then
    Exit(isIco);
  if (B[0] = 0) and (B[1] = 0) and (B[2] = 2) and (B[3] = 0) then
    Exit(isCur);
  if (B[0] = Ord('%')) and (B[1] = Ord('P')) and (B[2] = Ord('D')) and (B[3] = Ord('F')) then
    Exit(isPdf);
  if (B[0] = Ord('M')) and (B[1] = Ord('Z')) then
    Exit(isPe);
  { docx/xlsx/pptx/3mf и прочие OOXML — это тоже PK. Не картинка и не подмена типа. }
  if (B[0] = $50) and (B[1] = $4B) then
    Exit(isNone);
  if (N >= 12) and (B[4] = Ord('f')) and (B[5] = Ord('t')) and (B[6] = Ord('y')) and
     (B[7] = Ord('p')) then
  begin
    SetLength(S, 4);
    S[1] := Char(B[8]);
    S[2] := Char(B[9]);
    S[3] := Char(B[10]);
    S[4] := Char(B[11]);
    S := LowerCase(S);
    if (S = 'avif') or (S = 'avis') then
      Exit(isAvif);
    if (S = 'heic') or (S = 'heix') or (S = 'hevc') or (S = 'mif1') or (S = 'msf1') then
      Exit(isHeic);
  end;
  if (N >= 12) and (B[0] = 0) and (B[1] = 0) and (B[2] = 0) and (B[3] = $0C) and
     (B[4] = $4A) and (B[5] = $58) and (B[6] = $4C) and (B[7] = $20) then
    Exit(isJxl);
  SetLength(S, N);
  for N := 0 to High(B) do
    if B[N] < 128 then
      S[N + 1] := Char(B[N])
    else
      S[N + 1] := ' ';
  S := LowerCase(S);
  if (Pos('<svg', S) > 0) or ((Pos('<?xml', S) > 0) and (Pos('svg', S) > 0)) then
    Exit(isSvg);
end;

function ImageSigName(ASig: TImageSig): string;
begin
  case ASig of
    isJpeg: Result := 'JPEG';
    isPng: Result := 'PNG';
    isGif: Result := 'GIF';
    isWebp: Result := 'WEBP';
    isBmp: Result := 'BMP';
    isIco: Result := 'ICO';
    isCur: Result := 'CUR';
    isPdf: Result := 'PDF';
    isSvg: Result := 'SVG';
    isHeic: Result := 'HEIC';
    isAvif: Result := 'AVIF';
    isJxl: Result := 'JXL';
    isPe: Result := 'EXE';
    isZip: Result := 'ZIP';
  else
    Result := '';
  end;
end;

function ImageSigExt(ASig: TImageSig): string;
begin
  case ASig of
    isJpeg: Result := '.jpg';
    isPng: Result := '.png';
    isGif: Result := '.gif';
    isWebp: Result := '.webp';
    isBmp: Result := '.bmp';
    isIco: Result := '.ico';
    isCur: Result := '.cur';
    isPdf: Result := '.pdf';
    isSvg: Result := '.svg';
    isHeic: Result := '.heic';
    isAvif: Result := '.avif';
    isJxl: Result := '.jxl';
    isPe: Result := '.exe';
    isZip: Result := '.zip';
  else
    Result := '';
  end;
end;

function ImageExtMatches(ASig: TImageSig; const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  case ASig of
    isJpeg: Result := (E = '.jpg') or (E = '.jpeg') or (E = '.jpe') or (E = '.jfif');
    isPng: Result := E = '.png';
    isGif: Result := E = '.gif';
    isWebp: Result := E = '.webp';
    isBmp: Result := E = '.bmp';
    isIco: Result := E = '.ico';
    isCur: Result := E = '.cur';
    isPdf: Result := (E = '.pdf') or (E = '.ai');
    isSvg: Result := (E = '.svg') or (E = '.svgz');
    isHeic: Result := (E = '.heic') or (E = '.heif');
    isAvif: Result := E = '.avif';
    isJxl: Result := E = '.jxl';
    isPe: Result := (E = '.exe') or (E = '.dll') or (E = '.scr');
    isZip: Result := (E = '.zip') or (E = '.jar');
  else
    Result := True;
  end;
end;

{$IFDEF MSWINDOWS}
function IconToBitmap(AIcon: HICON; AWidth, AHeight: Integer): TBitmap;
var
  DC, Mem: HDC;
  Info: TBitmapInfo;
  Bits: Pointer;
  Dib: HBITMAP;
  Old: HGDIOBJ;
  Surf: TBitmapSurface;
  Y: Integer;
  Src, Dst: PByte;
begin
  Result := nil;
  if (AIcon = 0) or (AWidth < 1) or (AHeight < 1) then
    Exit;
  DC := GetDC(0);
  Mem := 0;
  Dib := 0;
  Old := 0;
  Surf := TBitmapSurface.Create;
  try
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    Info.bmiHeader.biWidth := AWidth;
    Info.bmiHeader.biHeight := -AHeight;
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    Dib := CreateDIBSection(DC, Info, DIB_RGB_COLORS, Bits, 0, 0);
    if (Dib = 0) or (Bits = nil) then
      Exit;
    Mem := CreateCompatibleDC(DC);
    Old := SelectObject(Mem, Dib);
    DrawIconEx(Mem, 0, 0, AIcon, AWidth, AHeight, 0, 0, DI_NORMAL);
    Surf.SetSize(AWidth, AHeight, TPixelFormat.BGRA);
    for Y := 0 to AHeight - 1 do
    begin
      Src := PByte(Bits);
      Inc(Src, Y * AWidth * 4);
      Dst := Surf.Scanline[Y];
      Move(Src^, Dst^, AWidth * 4);
    end;
    Result := TBitmap.Create;
    Result.Assign(Surf);
  finally
    if Old <> 0 then
      SelectObject(Mem, Old);
    if Mem <> 0 then
      DeleteDC(Mem);
    if Dib <> 0 then
      DeleteObject(Dib);
    ReleaseDC(0, DC);
    Surf.Free;
  end;
end;
{$ENDIF}

function LoadIcoFrames(const APath: string; out AFrames: TArray<TBitmap>;
  out ALabels: TArray<string>): Boolean;
{$IFDEF MSWINDOWS}
var
  Bytes: TBytes;
  Count, I, W, H: Integer;
  Off, Size: Cardinal;
  Icon: HICON;
  Bmp: TBitmap;
  Png: TBytesStream;
{$ENDIF}
begin
  Result := False;
  SetLength(AFrames, 0);
  SetLength(ALabels, 0);
  {$IFDEF MSWINDOWS}
  try
    Bytes := System.IOUtils.TFile.ReadAllBytes(APath);
  except
    Exit;
  end;
  if Length(Bytes) < 6 then
    Exit;
  Count := Bytes[4] or (Bytes[5] shl 8);
  if (Count < 1) or (Count > 64) or (Length(Bytes) < 6 + Count * 16) then
    Exit;
  for I := 0 to Count - 1 do
  begin
    W := Bytes[6 + I * 16];
    H := Bytes[6 + I * 16 + 1];
    if W = 0 then
      W := 256;
    if H = 0 then
      H := 256;
    Size := PCardinal(@Bytes[6 + I * 16 + 8])^;
    Off := PCardinal(@Bytes[6 + I * 16 + 12])^;
    if (Off = 0) or (Size = 0) or (Int64(Off) + Size > Length(Bytes)) then
      Continue;
    Bmp := nil;
    if (Size >= 8) and (Bytes[Off] = $89) and (Bytes[Off + 1] = $50) then
    begin
      Png := TBytesStream.Create;
      try
        Png.WriteBuffer(Bytes[Off], Size);
        Png.Position := 0;
        Bmp := TBitmap.Create;
        try
          Bmp.LoadFromStream(Png);
        except
          FreeAndNil(Bmp);
        end;
      finally
        Png.Free;
      end;
    end
    else
    begin
      Icon := CreateIconFromResourceEx(@Bytes[Off], Size, True, $00030000, W, H, 0);
      if Icon <> 0 then
      try
        Bmp := IconToBitmap(Icon, W, H);
      finally
        DestroyIcon(Icon);
      end;
    end;
    if (Bmp <> nil) and (Bmp.Width > 0) then
    begin
      SetLength(AFrames, Length(AFrames) + 1);
      SetLength(ALabels, Length(ALabels) + 1);
      AFrames[High(AFrames)] := Bmp;
      ALabels[High(ALabels)] := Format('%d×%d', [Bmp.Width, Bmp.Height]);
    end
    else
      Bmp.Free;
  end;
  Result := Length(AFrames) > 0;
  {$ENDIF}
end;

function ScaledFrame(const ASource: TBitmap; ASize: Integer): TBitmap;
var
  S: Single;
begin
  Result := TBitmap.Create(ASize, ASize);
  S := ASize / Max(ASource.Width, ASource.Height);
  Result.SkiaDraw(
    procedure(const C: ISkCanvas)
    begin
      C.Clear(TAlphaColors.Null);
      C.Translate((ASize - ASource.Width * S) / 2, (ASize - ASource.Height * S) / 2);
      C.Scale(S, S);
      C.DrawImage(ASource.ToSkImage, 0, 0);
    end);
end;

procedure WriteWord(AStream: TStream; AValue: Word);
begin
  AStream.WriteBuffer(AValue, SizeOf(AValue));
end;

procedure WriteByte(AStream: TStream; AValue: Byte);
begin
  AStream.WriteBuffer(AValue, 1);
end;

procedure WriteCard(AStream: TStream; AValue: Cardinal);
begin
  AStream.WriteBuffer(AValue, SizeOf(AValue));
end;

function SaveMultiIco(const ASource: TBitmap; const APath: string): Boolean;
const
  Sizes: array[0..4] of Integer = (16, 32, 48, 64, 256);
var
  Frames: array[0..4] of TBytes;
  Used: array[0..4] of Integer;
  I, Count, Off: Integer;
  FS: TFileStream;
  Bmp: TBitmap;
  MS: TMemoryStream;
  Img: ISkImage;
  Data: TBytes;
  Side: Byte;
begin
  Result := False;
  if (ASource = nil) or (ASource.Width < 1) then
    Exit;
  Count := 0;
  for I := 0 to High(Sizes) do
  begin
    Bmp := ScaledFrame(ASource, Sizes[I]);
    try
      Img := Bmp.ToSkImage;
      if Img = nil then
        Continue;
      Data := Img.Encode(TSkEncodedImageFormat.PNG, 100);
      if Length(Data) = 0 then
        Continue;
      Frames[Count] := Data;
      Used[Count] := Sizes[I];
      Inc(Count);
    finally
      Bmp.Free;
    end;
  end;
  if Count = 0 then
    Exit;
  FS := TFileStream.Create(APath, fmCreate);
  try
    MS := TMemoryStream.Create;
    try
      WriteWord(MS, 0);
      WriteWord(MS, 1);
      WriteWord(MS, Count);
      Off := 6 + Count * 16;
      for I := 0 to Count - 1 do
      begin
        if Used[I] >= 256 then
          Side := 0
        else
          Side := Byte(Used[I]);
        WriteByte(MS, Side);
        WriteByte(MS, Side);
        WriteByte(MS, 0);
        WriteByte(MS, 0);
        WriteWord(MS, 1);
        WriteWord(MS, 32);
        WriteCard(MS, Length(Frames[I]));
        WriteCard(MS, Off);
        Inc(Off, Length(Frames[I]));
      end;
      for I := 0 to Count - 1 do
        if Length(Frames[I]) > 0 then
          MS.WriteBuffer(Frames[I][0], Length(Frames[I]));
      MS.Position := 0;
      FS.CopyFrom(MS, MS.Size);
      Result := True;
    finally
      MS.Free;
    end;
  finally
    FS.Free;
  end;
end;

end.
