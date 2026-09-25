unit uFileOpEngine;

{
  Движок файловых операций V!be CMD.
  Пауза между блоками, отмена, пропуск файла, конфликт имён.
  Прогресс — снимок под замком, UI не дёргается на каждый байт.
}

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  uFileOps;

type
  TFileOpKind = (okCopy, okMove, okDelete, okArchive);

  TFileOpPhase = (opIdle, opScan, opReady, opRun, opPaused, opDone, opCancel, opFail);

  TConflictChoice = (ccOverwrite, ccSkip, ccAutoRename, ccOverwriteAll,
    ccSkipAll, ccOverwriteOlder, ccCancel);

  TFileOpProgress = record
    Phase: TFileOpPhase;
    Kind: TFileOpKind;
    FileName: string;
    SourcePath: string;
    DestPath: string;
    FilesDone: Integer;
    FilesTotal: Integer;
    FileBytesDone: Int64;
    FileBytesTotal: Int64;
    TotalBytesDone: Int64;
    TotalBytesTotal: Int64;
    SpeedBps: Double;
    RemainingSec: Double;
    Errors: Integer;
    Skipped: Integer;
    Unchanged: Integer;
    Status: string;
  end;

  TFileOpConflictInfo = record
    Source: string;
    Dest: string;
    SrcSize: Int64;
    DstSize: Int64;
    SrcTime: TDateTime;
    DstTime: TDateTime;
    TypeClash: Boolean;
  end;

  TFileOpConflictProc = reference to procedure(const AInfo: TFileOpConflictInfo;
    AAnswer: TProc<TConflictChoice>);

  TFileOpEngine = class
  private
    FKind: TFileOpKind;
    FSources: TArray<string>;
    FDest: string;
    FPermanent: Boolean;
    FThread: TThread;
    FLock: TCriticalSection;
    FPauseEvent: TEvent;
    FCancel: Boolean;
    FSkip: Boolean;
    FPaused: Boolean;
    FStarted: Boolean;
    FSnap: TFileOpProgress;
    FOverwriteAll: Boolean;
    FSkipAll: Boolean;
    FAutoRename: Boolean;
    FOverwriteOlder: Boolean;
    FErrorList: TStringList;
    FFatal: Boolean;
    FConflict: TFileOpConflictInfo;
    FConflictChoice: TConflictChoice;
    FConflictEvent: TEvent;
    FWaitingConflict: Boolean;
    FTickStart: TDateTime;
    FRunStart: TDateTime;
    FBytesAtTick: Int64;
    FSpecialCopy: TProc<string, string>;
    FBatchWork: TProc;
    procedure NotifyItem(const APath: string; AStatus: TOpItemStatus);
    procedure SetPhase(APhase: TFileOpPhase; const AStatus: string);
    procedure Publish(const AFile: string; AFileDone, AFileTotal: Int64);
    procedure AddBytes(ADelta: Int64);
    procedure CheckWait;
    procedure ScanPath(const APath: string; var AFiles: Integer; var ABytes: Int64);
    procedure ProcessPath(const ASrc, ADestDir: string);
    function CopyOneFile(const ASrc, ADst: string): Boolean;
    procedure CopyOneDir(const ASrc, ADst: string; AMove: Boolean);
    procedure DeleteTree(const APath: string);
    procedure NoteError(const APath, AMsg: string);
    procedure IncDone;
    procedure IncSkipped;
    function CountFilesQuick(const APath: string): Integer;
    function TryRemoveEmptyDir(const APath: string): Boolean;
    function IsFatalWinError(ACode: Cardinal): Boolean;
    procedure ArchiveAll;
    function DecideConflict(const ASrc, ADst: string): TConflictChoice;
    function DecideConflictKnown(const ASrc, ADst: string; ASrcSize, ADstSize: Int64;
      ASrcTime, ADstTime: TDateTime): TConflictChoice;
    function UniqueName(const APath: string): string;
    function IsIntoSelf(const ASrc, ADstDir: string): Boolean;
    function SameVolume(const A, B: string): Boolean;
    procedure Run;
  public
    OnConflict: TFileOpConflictProc;
    OnDone: TFileOpDoneProc;
    OnItemDone: TFileOpItemDoneProc;
    constructor Create(AKind: TFileOpKind; const ASources: TArray<string>;
      const ADest: string; APermanent: Boolean = False);
    destructor Destroy; override;
    procedure ScanAsync;
    procedure Start;
    procedure Pause;
    procedure Resume;
    procedure Cancel;
    procedure SkipCurrent;
    procedure AnswerConflict(AChoice: TConflictChoice);
    function GetProgress: TFileOpProgress;
    property Kind: TFileOpKind read FKind;
    property Dest: string read FDest;
    property SpecialCopy: TProc<string, string> read FSpecialCopy write FSpecialCopy;
    property BatchWork: TProc read FBatchWork write FBatchWork;
    property WaitingConflict: Boolean read FWaitingConflict;
    property Conflict: TFileOpConflictInfo read FConflict;
    property Permanent: Boolean read FPermanent;
  end;

function FileOpKindCaption(AKind: TFileOpKind): string;
function FormatOpBytes(ABytes: Int64): string;
function FormatOpSpeed(ABps: Double): string;
function FormatOpEta(ASec: Double): string;

implementation

uses
  System.IOUtils, System.Math, System.StrUtils, System.DateUtils, uFileModel,
  uArchiveEngine
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const
  CHUNK = 1024 * 1024;

function FileOpKindCaption(AKind: TFileOpKind): string;
begin
  case AKind of
    okCopy:    Result := 'Копирование';
    okMove:    Result := 'Перемещение';
    okDelete:  Result := 'Удаление';
    okArchive: Result := 'Архивация';
  else
    Result := 'Операция';
  end;
end;

function FormatOpBytes(ABytes: Int64): string;
begin
  if ABytes >= 1024 * 1024 * 1024 then
    Result := FormatFloat('0.00', ABytes / (1024 * 1024 * 1024)) + ' ГБ'
  else if ABytes >= 1024 * 1024 then
    Result := FormatFloat('0.0', ABytes / (1024 * 1024)) + ' МБ'
  else if ABytes >= 1024 then
    Result := FormatFloat('0.0', ABytes / 1024) + ' КБ'
  else
    Result := IntToStr(ABytes) + ' Б';
end;

function FormatOpSpeed(ABps: Double): string;
begin
  if ABps <= 0 then
    Result := '—'
  else
    Result := FormatOpBytes(Round(ABps)) + '/с';
end;

function FormatOpEta(ASec: Double): string;
var
  S: Integer;
begin
  if ASec <= 0 then
    Exit('—');
  S := Round(ASec);
  if S < 60 then
    Result := IntToStr(S) + ' с'
  else if S < 3600 then
    Result := Format('%d мин %d с', [S div 60, S mod 60])
  else
    Result := Format('%d ч %d мин', [S div 3600, (S mod 3600) div 60]);
end;

constructor TFileOpEngine.Create(AKind: TFileOpKind; const ASources: TArray<string>;
  const ADest: string; APermanent: Boolean);
begin
  inherited Create;
  FKind := AKind;
  FSources := Copy(ASources);
  FDest := ADest;
  FPermanent := APermanent;
  FLock := TCriticalSection.Create;
  FPauseEvent := TEvent.Create(nil, True, True, '');
  FConflictEvent := TEvent.Create(nil, False, False, '');
  FErrorList := TStringList.Create;
  FSnap.Kind := AKind;
  FSnap.Phase := opIdle;
  FSnap.DestPath := ADest;
  FTickStart := Now;
end;

destructor TFileOpEngine.Destroy;
begin
  Cancel;
  if Assigned(FThread) then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FreeAndNil(FConflictEvent);
  FreeAndNil(FPauseEvent);
  FreeAndNil(FErrorList);
  FreeAndNil(FLock);
  inherited;
end;

procedure TFileOpEngine.SetPhase(APhase: TFileOpPhase; const AStatus: string);
begin
  FLock.Enter;
  try
    FSnap.Phase := APhase;
    if AStatus <> '' then
      FSnap.Status := AStatus;
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.Publish(const AFile: string; AFileDone, AFileTotal: Int64);
begin
  FLock.Enter;
  try
    if AFile <> '' then
      FSnap.FileName := ExtractFileName(AFile);
    FSnap.SourcePath := AFile;
    FSnap.FileBytesDone := AFileDone;
    FSnap.FileBytesTotal := AFileTotal;
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.AddBytes(ADelta: Int64);
var
  El: Double;
begin
  if ADelta <= 0 then
    Exit;
  FLock.Enter;
  try
    Inc(FSnap.FileBytesDone, ADelta);
    Inc(FSnap.TotalBytesDone, ADelta);
    El := MilliSecondsBetween(Now, FTickStart) / 1000;
    if El >= 0.25 then
    begin
      FSnap.SpeedBps := FSnap.SpeedBps * 0.65 +
        ((FSnap.TotalBytesDone - FBytesAtTick) / El) * 0.35;
      if FSnap.SpeedBps < 0 then
        FSnap.SpeedBps := 0;
      if (FSnap.SpeedBps > 1) and (FSnap.TotalBytesDone >= 1024 * 1024) and
         (MilliSecondsBetween(Now, FRunStart) >= 1000) then
        FSnap.RemainingSec :=
          (FSnap.TotalBytesTotal - FSnap.TotalBytesDone) / FSnap.SpeedBps
      else
        FSnap.RemainingSec := 0;
      FTickStart := Now;
      FBytesAtTick := FSnap.TotalBytesDone;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.CheckWait;
begin
  if FCancel then
    Abort;
  if FPaused then
    FPauseEvent.WaitFor(INFINITE);
  if FCancel then
    Abort;
end;

function TFileOpEngine.GetProgress: TFileOpProgress;
begin
  FLock.Enter;
  try
    Result := FSnap;
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.ScanAsync;
begin
  if Assigned(FThread) then
    Exit;
  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      Run;
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TFileOpEngine.Start;
begin
  FStarted := True;
  FPaused := False;
  FPauseEvent.SetEvent;
end;

procedure TFileOpEngine.Pause;
begin
  FPaused := True;
  FPauseEvent.ResetEvent;
  SetPhase(opPaused, 'Пауза');
end;

procedure TFileOpEngine.Resume;
begin
  if FCancel then
    Exit;
  FPaused := False;
  FPauseEvent.SetEvent;
  SetPhase(opRun, FileOpKindCaption(FKind));
end;

procedure TFileOpEngine.Cancel;
begin
  FCancel := True;
  FPaused := False;
  FPauseEvent.SetEvent;
  if FWaitingConflict then
  begin
    FConflictChoice := ccCancel;
    FConflictEvent.SetEvent;
  end;
end;

procedure TFileOpEngine.SkipCurrent;
begin
  FSkip := True;
end;

procedure TFileOpEngine.AnswerConflict(AChoice: TConflictChoice);
begin
  FConflictChoice := AChoice;
  FConflictEvent.SetEvent;
end;

procedure TFileOpEngine.ScanPath(const APath: string; var AFiles: Integer; var ABytes: Int64);
var
  Af: Integer;
  Ab: Int64;
  SR: TSearchRec;
  Full: string;
  RC: Integer;
begin
  CheckWait;
  RC := System.SysUtils.FindFirst(TPath.Combine(APath, '*.*'), faAnyFile, SR);
  if RC = 0 then
  try
    repeat
      CheckWait;
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Full := TPath.Combine(APath, SR.Name);
      if (SR.Attr and faDirectory) <> 0 then
        ScanPath(Full, AFiles, ABytes)
      else
      begin
        Inc(AFiles);
        Inc(ABytes, SR.Size);
      end;
    until System.SysUtils.FindNext(SR) <> 0;
  finally
    System.SysUtils.FindClose(SR);
  end
  else if (not IsRemotePath(APath)) and TFile.Exists(APath) then
  begin
    Inc(AFiles);
    try
      Inc(ABytes, TFile.GetSize(APath));
    except
    end;
  end
  else if ScanArchivePath(APath, Af, Ab) then
  begin
    Inc(AFiles, Af);
    Inc(ABytes, Ab);
  end
  else if not IsRemotePath(APath) then
    Inc(AFiles);
end;

function TFileOpEngine.IsIntoSelf(const ASrc, ADstDir: string): Boolean;
var
  S, D: string;
begin
  { C:\Foo vs C:\FooBar = false; C:\Foo vs C:\Foo\Bar = true; C:\Foo vs C:\Foo = true }
  S := ExcludeTrailingPathDelimiter(ASrc);
  D := ExcludeTrailingPathDelimiter(ADstDir);
  if SameText(S, D) then
    Exit(True);
  Result := StartsText(IncludeTrailingPathDelimiter(S),
    IncludeTrailingPathDelimiter(D));
end;

function VolumeRoot(const APath: string): string;
var
  S: string;
  I, N: Integer;
begin
  S := ExcludeTrailingPathDelimiter(APath);
  if StartsText('\\', S) then
  begin
    N := 0;
    Result := '\\';
    for I := 3 to Length(S) do
    begin
      if S[I] = '\' then
      begin
        Inc(N);
        if N = 2 then
          Exit(Copy(S, 1, I - 1));
      end;
    end;
    Result := S;
  end
  else
    Result := ExtractFileDrive(S);
end;

function TFileOpEngine.SameVolume(const A, B: string): Boolean;
var
  RA, RB: string;
begin
  RA := VolumeRoot(A);
  RB := VolumeRoot(B);
  Result := (RA <> '') and SameText(RA, RB);
end;

function TFileOpEngine.UniqueName(const APath: string): string;
var
  Dir, Name, Ext: string;
  I: Integer;
begin
  Dir := ExtractFilePath(APath);
  Name := ChangeFileExt(ExtractFileName(APath), '');
  Ext := ExtractFileExt(APath);
  I := 1;
  repeat
    Result := TPath.Combine(Dir, Format('%s (%d)%s', [Name, I, Ext]));
    Inc(I);
  until not TFile.Exists(Result) and not TDirectory.Exists(Result);
end;

procedure TFileOpEngine.NoteError(const APath, AMsg: string);
begin
  FLock.Enter;
  try
    Inc(FSnap.Errors);
    if FErrorList.Count < 40 then
      FErrorList.Add(ExtractFileName(APath) + ': ' + AMsg);
    FSnap.Status := AMsg;
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.IncDone;
begin
  FLock.Enter;
  try
    Inc(FSnap.FilesDone);
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.IncSkipped;
begin
  FLock.Enter;
  try
    Inc(FSnap.Skipped);
  finally
    FLock.Leave;
  end;
end;

procedure TFileOpEngine.NotifyItem(const APath: string; AStatus: TOpItemStatus);
var
  P: string;
  S: TOpItemStatus;
  Cb: TFileOpItemDoneProc;
begin
  if not Assigned(OnItemDone) or (APath = '') then
    Exit;
  P := APath;
  S := AStatus;
  Cb := OnItemDone;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Cb) then
        Cb(P, S);
    end);
end;

function TFileOpEngine.IsFatalWinError(ACode: Cardinal): Boolean;
begin
  Result := (ACode = 112) or (ACode = 39) or (ACode = 21) or (ACode = 15);
end;

function TFileOpEngine.CountFilesQuick(const APath: string): Integer;
var
  F, D: string;
begin
  Result := 0;
  if TDirectory.Exists(APath) then
  begin
    try
      for F in TDirectory.GetFiles(APath) do
        Inc(Result);
      for D in TDirectory.GetDirectories(APath) do
        Inc(Result, CountFilesQuick(D));
    except
    end;
  end
  else if TFile.Exists(APath) then
    Result := 1;
end;

function TFileOpEngine.TryRemoveEmptyDir(const APath: string): Boolean;
begin
  Result := False;
  if not TDirectory.Exists(APath) then
    Exit(True);
  try
    if (Length(TDirectory.GetFiles(APath)) = 0) and
       (Length(TDirectory.GetDirectories(APath)) = 0) then
    begin
      TDirectory.Delete(APath, False);
      Result := True;
    end;
  except
    Result := False;
  end;
end;

function TFileOpEngine.DecideConflictKnown(const ASrc, ADst: string;
  ASrcSize, ADstSize: Int64; ASrcTime, ADstTime: TDateTime): TConflictChoice;
begin
  Result := ccOverwrite;
  if FSkipAll then
    Exit(ccSkip);
  if FAutoRename then
    Exit(ccAutoRename);
  if FOverwriteAll then
    Exit(ccOverwrite);
  if FOverwriteOlder then
  begin
    if ASrcTime > ADstTime then
      Exit(ccOverwrite)
    else
      Exit(ccSkip);
  end;
  { Всегда спрашиваем при конфликте имени — даже если размер/время совпадают. }
  if not Assigned(OnConflict) then
    Exit(ccOverwrite);

  FConflict.Source := ASrc;
  FConflict.Dest := ADst;
  FConflict.SrcSize := ASrcSize;
  FConflict.DstSize := ADstSize;
  FConflict.SrcTime := ASrcTime;
  FConflict.DstTime := ADstTime;
  FConflict.TypeClash := False;
  FConflictChoice := ccSkip;
  FWaitingConflict := True;
  FConflictEvent.ResetEvent;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(OnConflict) then
        OnConflict(FConflict,
          procedure(AAns: TConflictChoice)
          begin
            AnswerConflict(AAns);
          end);
    end);
  FConflictEvent.WaitFor(INFINITE);
  FWaitingConflict := False;
  Result := FConflictChoice;
  case Result of
    ccOverwriteAll:
      begin
        FOverwriteAll := True;
        Result := ccOverwrite;
      end;
    ccSkipAll:
      begin
        FSkipAll := True;
        Result := ccSkip;
      end;
    ccAutoRename:
      FAutoRename := True;
    ccOverwriteOlder:
      begin
        FOverwriteOlder := True;
        Result := DecideConflictKnown(ASrc, ADst, ASrcSize, ADstSize, ASrcTime, ADstTime);
      end;
    ccCancel:
      begin
        FCancel := True;
        Abort;
      end;
  end;
end;

function SafeFileSize(const APath: string): Int64;
begin
  Result := 0;
  if TFile.Exists(APath) and not TDirectory.Exists(APath) then
  try
    Result := TFile.GetSize(APath);
  except
    Result := 0;
  end;
end;

function SafeFileTime(const APath: string): TDateTime;
begin
  Result := 0;
  try
    if TFile.Exists(APath) then
      Result := TFile.GetLastWriteTime(APath)
    else if TDirectory.Exists(APath) then
      Result := TDirectory.GetLastWriteTime(APath);
  except
    Result := 0;
  end;
end;

function TFileOpEngine.DecideConflict(const ASrc, ADst: string): TConflictChoice;
var
  SrcDir, DstDir, SrcFile, DstFile: Boolean;
begin
  Result := ccOverwrite;
  SrcDir := TDirectory.Exists(ASrc);
  DstDir := TDirectory.Exists(ADst);
  SrcFile := TFile.Exists(ASrc) and not SrcDir;
  DstFile := TFile.Exists(ADst) and not DstDir;
  if not DstFile and not DstDir then
    Exit;
  if SrcDir and DstDir then
    Exit(ccOverwrite);
  if (SrcFile and DstDir) or (SrcDir and DstFile) then
  begin
    FConflict.TypeClash := True;
    FConflict.Source := ASrc;
    FConflict.Dest := ADst;
    FConflict.SrcSize := SafeFileSize(ASrc);
    FConflict.DstSize := SafeFileSize(ADst);
    FConflict.SrcTime := SafeFileTime(ASrc);
    FConflict.DstTime := SafeFileTime(ADst);
    if FSkipAll then
      Exit(ccSkip);
    if FAutoRename then
      Exit(ccAutoRename);
    if not Assigned(OnConflict) then
      Exit(ccSkip);
    FConflictChoice := ccSkip;
    FWaitingConflict := True;
    FConflictEvent.ResetEvent;
    TThread.Queue(nil,
      procedure
      begin
        if Assigned(OnConflict) then
          OnConflict(FConflict,
            procedure(AAns: TConflictChoice)
            begin
              AnswerConflict(AAns);
            end);
      end);
    FConflictEvent.WaitFor(INFINITE);
    FWaitingConflict := False;
    Result := FConflictChoice;
    case Result of
      ccSkipAll:
        begin
          FSkipAll := True;
          Result := ccSkip;
        end;
      ccAutoRename:
        FAutoRename := True;
      ccOverwrite, ccOverwriteAll, ccOverwriteOlder:
        Result := ccSkip;
      ccCancel:
        begin
          FCancel := True;
          Abort;
        end;
    end;
    if Result = ccSkip then
      NotifyItem(ASrc, oisSkipped)
    else
      NotifyItem(ASrc, oisOk);
    Exit;
  end;
  Result := DecideConflictKnown(ASrc, ADst, SafeFileSize(ASrc), SafeFileSize(ADst),
    SafeFileTime(ASrc), SafeFileTime(ADst));
end;

procedure ClearReadonly(const APath: string);
{$IFDEF MSWINDOWS}
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(APath));
  if (Attr <> INVALID_FILE_ATTRIBUTES) and
     ((Attr and FILE_ATTRIBUTE_READONLY) <> 0) then
    SetFileAttributes(PChar(APath), Attr and not FILE_ATTRIBUTE_READONLY);
{$ELSE}
begin
{$ENDIF}
end;

procedure CopyAttrs(const ASrc, ADst: string);
{$IFDEF MSWINDOWS}
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(ASrc));
  if Attr <> INVALID_FILE_ATTRIBUTES then
    SetFileAttributes(PChar(ADst), Attr and not FILE_ATTRIBUTE_DIRECTORY);
{$ELSE}
begin
{$ENDIF}
end;

function TFileOpEngine.CopyOneFile(const ASrc, ADst: string): Boolean;
var
  InS, OutS: TStream;
  Buf: TBytes;
  N: Integer;
  Total, Done: Int64;
  Choice: TConflictChoice;
  Dest: string;
  Err: Cardinal;
{$IFDEF MSWINDOWS}
  HIn, HOut: THandle;
{$ENDIF}
begin
  Result := False;
  CheckWait;
  Dest := ADst;
  if TFile.Exists(Dest) or TDirectory.Exists(Dest) then
  begin
    Choice := DecideConflict(ASrc, Dest);
    case Choice of
      ccSkip:
        begin
          IncSkipped;
          NotifyItem(ASrc, oisSkipped);
          Exit(False);
        end;
      ccAutoRename:
        Dest := UniqueName(Dest);
    end;
  end;

  ForceDirectories(ExtractFilePath(Dest));
  if TFile.Exists(Dest) then
    ClearReadonly(Dest);
  Total := 0;
  try
    Total := TFile.GetSize(ASrc);
  except
  end;
  Publish(ASrc, 0, Total);
  Done := 0;
  FSkip := False;

  try
{$IFDEF MSWINDOWS}
    HIn := CreateFile(PChar(ASrc), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
      nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
    if HIn = INVALID_HANDLE_VALUE then
    begin
      Err := GetLastError;
      if IsFatalWinError(Err) then
        FFatal := True;
      raise Exception.Create('Нет доступа: ' + ExtractFileName(ASrc));
    end;
    InS := THandleStream.Create(HIn);
    try
      HOut := CreateFile(PChar(Dest), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
      if HOut = INVALID_HANDLE_VALUE then
      begin
        Err := GetLastError;
        ClearReadonly(Dest);
        HOut := CreateFile(PChar(Dest), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
          FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
      end;
      if HOut = INVALID_HANDLE_VALUE then
      begin
        Err := GetLastError;
        if IsFatalWinError(Err) then
          FFatal := True;
        raise Exception.Create('Не удалось создать: ' + ExtractFileName(Dest));
      end;
      OutS := THandleStream.Create(HOut);
      try
        SetLength(Buf, CHUNK);
        repeat
          CheckWait;
          if FSkip then
            Break;
          N := InS.Read(Buf[0], Length(Buf));
          if N <= 0 then
            Break;
          OutS.WriteBuffer(Buf[0], N);
          Inc(Done, N);
          AddBytes(N);
          Publish(ASrc, Done, Total);
        until False;
      finally
        OutS.Free;
        CloseHandle(HOut);
      end;
    finally
      InS.Free;
      CloseHandle(HIn);
    end;
{$ELSE}
    InS := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyNone);
    try
      OutS := TFileStream.Create(Dest, fmCreate);
      try
        SetLength(Buf, CHUNK);
        repeat
          CheckWait;
          if FSkip then
            Break;
          N := InS.Read(Buf[0], Length(Buf));
          if N <= 0 then
            Break;
          OutS.WriteBuffer(Buf[0], N);
          Inc(Done, N);
          AddBytes(N);
          Publish(ASrc, Done, Total);
        until False;
      finally
        OutS.Free;
      end;
    finally
      InS.Free;
    end;
{$ENDIF}

    if FSkip then
    begin
      IncSkipped;
      if Done > 0 then
      begin
        FLock.Enter;
        try
          Dec(FSnap.TotalBytesDone, Done);
          if FSnap.TotalBytesDone < 0 then
            FSnap.TotalBytesDone := 0;
        finally
          FLock.Leave;
        end;
      end;
      if TFile.Exists(Dest) then
      try
        TFile.Delete(Dest);
      except
      end;
      NotifyItem(ASrc, oisSkipped);
      Exit(False);
    end;
    try
      TFile.SetLastWriteTime(Dest, TFile.GetLastWriteTime(ASrc));
    except
    end;
    try
      CopyAttrs(ASrc, Dest);
    except
    end;
    Result := True;
    NotifyItem(ASrc, oisOk);
  except
    on E: EAbort do
      raise;
    on E: Exception do
    begin
      if Done > 0 then
      begin
        FLock.Enter;
        try
          Dec(FSnap.TotalBytesDone, Done);
          if FSnap.TotalBytesDone < 0 then
            FSnap.TotalBytesDone := 0;
        finally
          FLock.Leave;
        end;
      end;
      if TFile.Exists(Dest) then
      try
        if Done = 0 then
          TFile.Delete(Dest);
      except
      end;
      NoteError(ASrc, E.Message);
      Result := False;
    end;
  end;
end;

procedure TFileOpEngine.CopyOneDir(const ASrc, ADst: string; AMove: Boolean);
var
  F, D, Name, Child, Dest: string;
  Choice: TConflictChoice;
begin
  CheckWait;
  Dest := ADst;
  if TFile.Exists(Dest) and not TDirectory.Exists(Dest) then
  begin
    Choice := DecideConflict(ASrc, Dest);
    case Choice of
      ccSkip:
        begin
          IncSkipped;
          NotifyItem(ASrc, oisSkipped);
          Exit;
        end;
      ccAutoRename:
        Dest := UniqueName(Dest);
    else
      Exit;
    end;
  end;
  ForceDirectories(Dest);
  try
    for F in TDirectory.GetFiles(ASrc) do
    begin
      CheckWait;
      if FFatal then
        Abort;
      Name := TPath.GetFileName(F);
      if CopyOneFile(F, TPath.Combine(Dest, Name)) then
      begin
        IncDone;
        if AMove then
        try
          ClearReadonly(F);
          TFile.Delete(F);
        except
          on E: Exception do
            NoteError(F, E.Message);
        end;
      end;
    end;
    for D in TDirectory.GetDirectories(ASrc) do
    begin
      Child := TPath.Combine(Dest, TPath.GetFileName(D));
      CopyOneDir(D, Child, AMove);
    end;
    if AMove then
      TryRemoveEmptyDir(ASrc);
  except
    on E: EAbort do
      raise;
    on E: Exception do
    begin
      NoteError(ASrc, E.Message);
      if FFatal then
        raise;
    end;
  end;
end;

procedure TFileOpEngine.DeleteTree(const APath: string);
var
  F, D: string;
  Sz: Int64;
begin
  CheckWait;
  Publish(APath, 0, 0);
  if TDirectory.Exists(APath) then
  begin
    try
      for F in TDirectory.GetFiles(APath) do
        DeleteTree(F);
      for D in TDirectory.GetDirectories(APath) do
        DeleteTree(D);
      TryRemoveEmptyDir(APath);
    except
      on E: EAbort do
        raise;
      on E: Exception do
        NoteError(APath, E.Message);
    end;
  end
  else if TFile.Exists(APath) then
  begin
    Sz := 0;
    try
      Sz := TFile.GetSize(APath);
    except
    end;
    try
      ClearReadonly(APath);
      TFile.Delete(APath);
      IncDone;
      if Sz > 0 then
        AddBytes(Sz);
    except
      on E: Exception do
        NoteError(APath, E.Message);
    end;
  end;
end;

procedure TFileOpEngine.ArchiveAll;
var
  ZipPath: string;
  Choice: TConflictChoice;
  ReplaceDest: Boolean;
begin
  ZipPath := FDest;
  FLock.Enter;
  try
    FSnap.DestPath := ZipPath;
    FSnap.FileName := ExtractFileName(ZipPath);
  finally
    FLock.Leave;
  end;

  ReplaceDest := True;
  if TFile.Exists(ZipPath) or TDirectory.Exists(ZipPath) then
  begin
    if Length(FSources) > 0 then
      Choice := DecideConflict(FSources[0], ZipPath)
    else
      Choice := DecideConflict(ZipPath, ZipPath);
    case Choice of
      ccSkip:
        begin
          FLock.Enter;
          try
            Inc(FSnap.Skipped);
            FSnap.FilesDone := FSnap.FilesTotal;
          finally
            FLock.Leave;
          end;
          Exit;
        end;
      ccAutoRename:
        begin
          ZipPath := UniqueName(ZipPath);
          FDest := ZipPath;
          FLock.Enter;
          try
            FSnap.DestPath := ZipPath;
          finally
            FLock.Leave;
          end;
        end;
    else
      ReplaceDest := True;
    end;
  end;

  ForceDirectories(ExtractFilePath(ZipPath));
  PackToArchive(FSources, ZipPath, ReplaceDest);
end;

procedure TFileOpEngine.ProcessPath(const ASrc, ADestDir: string);
var
  Name, Dst: string;
  Moved: Boolean;
  N: Integer;
  Sz: Int64;
begin
  CheckWait;
  if FFatal then
    Abort;
  Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(ASrc));
  Dst := TPath.Combine(ADestDir, Name);
  FLock.Enter;
  try
    FSnap.SourcePath := ASrc;
    FSnap.DestPath := Dst;
    FSnap.FileName := Name;
  finally
    FLock.Leave;
  end;

  if (FKind in [okCopy, okMove]) and TDirectory.Exists(ASrc) and
     IsIntoSelf(ASrc, ADestDir) then
    raise Exception.Create('Нельзя копировать папку саму в себя: ' + Name);

  if (FKind in [okCopy, okMove]) and ArchiveInvolved(ASrc, ADestDir) then
  begin
    try
      CopyPathSync(ASrc, ADestDir);
      if (FKind = okMove) and not FCancel then
        DeletePathSync(ASrc, True);
      N := CountFilesQuick(ASrc);
      if N <= 0 then
        N := 1;
      FLock.Enter;
      try
        Inc(FSnap.FilesDone, N);
      finally
        FLock.Leave;
      end;
    except
      on E: EAbort do
        raise;
      on E: Exception do
        NoteError(ASrc, E.Message);
    end;
    Exit;
  end;
  if (FKind = okDelete) and ArchiveInvolved(ASrc, '') then
  begin
    try
      DeletePathSync(ASrc, True);
      IncDone;
    except
      on E: EAbort do
        raise;
      on E: Exception do
        NoteError(ASrc, E.Message);
    end;
    Exit;
  end;

  if not TFile.Exists(ASrc) and not TDirectory.Exists(ASrc) then
  begin
    try
      if Assigned(FSpecialCopy) and (FKind in [okCopy, okMove, okArchive]) then
      begin
        FSpecialCopy(ASrc, ADestDir);
        if (FKind = okMove) and not FCancel then
          DeletePathSync(ASrc, True);
      end
      else if Assigned(FSpecialCopy) and (FKind = okDelete) then
        FSpecialCopy(ASrc, '');
      IncDone;
    except
      on E: EAbort do
        raise;
      on E: Exception do
        NoteError(ASrc, E.Message);
    end;
    Exit;
  end;

  case FKind of
    okCopy:
      if TDirectory.Exists(ASrc) then
        CopyOneDir(ASrc, Dst, False)
      else if CopyOneFile(ASrc, Dst) then
        IncDone;
    okMove:
      begin
        Moved := False;
        if SameVolume(ASrc, ADestDir) and not TFile.Exists(Dst) and
           not TDirectory.Exists(Dst) then
        begin
          ForceDirectories(ADestDir);
          N := CountFilesQuick(ASrc);
          Sz := 0;
          if TFile.Exists(ASrc) then
          try
            Sz := TFile.GetSize(ASrc);
          except
          end;
          Moved := RenameFile(ASrc, Dst);
          if Moved then
          begin
            if N <= 0 then
              N := 1;
            FLock.Enter;
            try
              Inc(FSnap.FilesDone, N);
            finally
              FLock.Leave;
            end;
            if Sz > 0 then
              AddBytes(Sz);
          end;
        end;
        if not Moved then
        begin
          if TDirectory.Exists(ASrc) then
            CopyOneDir(ASrc, Dst, True)
          else if CopyOneFile(ASrc, Dst) then
          begin
            IncDone;
            try
              ClearReadonly(ASrc);
              TFile.Delete(ASrc);
            except
              on E: Exception do
                NoteError(ASrc, E.Message);
            end;
          end;
        end;
      end;
    okDelete:
      begin
        Publish(ASrc, 0, 0);
        if not FPermanent then
        begin
          N := CountFilesQuick(ASrc);
          Sz := 0;
          if TFile.Exists(ASrc) then
          try
            Sz := TFile.GetSize(ASrc);
          except
          end;
          try
            DeletePathSync(ASrc, False);
            if N <= 0 then
              N := 1;
            FLock.Enter;
            try
              Inc(FSnap.FilesDone, N);
            finally
              FLock.Leave;
            end;
            if Sz > 0 then
              AddBytes(Sz);
          except
            on E: Exception do
              NoteError(ASrc, E.Message);
          end;
        end
        else
          DeleteTree(ASrc);
      end;
    okArchive:
      begin
        Publish(ASrc, 0, 0);
        try
          if Assigned(FSpecialCopy) then
            FSpecialCopy(ASrc, FDest);
          IncDone;
        except
          on E: EAbort do
            raise;
          on E: Exception do
            NoteError(ASrc, E.Message);
        end;
      end;
  end;
end;

procedure TFileOpEngine.Run;
var
  I, Files: Integer;
  Bytes: Int64;
  Src, DestDir: string;
  Ok: Boolean;
  Err: string;
begin
  Ok := True;
  Err := '';
  SetArchiveHooks(
    procedure(const AName: string; ADelta, AFileSize: Int64)
    begin
      if AName <> '' then
        Publish(AName, 0, AFileSize);
      AddBytes(ADelta);
    end,
    function(const ASrc, ADst: string; ASrcSize, ADstSize: Int64;
      ASrcTime, ADstTime: TDateTime): TArcConflict
    var
      C: TConflictChoice;
    begin
      C := DecideConflictKnown(ASrc, ADst, ASrcSize, ADstSize, ASrcTime, ADstTime);
      case C of
        ccSkip:
          Result := acSkip;
        ccAutoRename:
          Result := acRename;
        ccCancel:
          Result := acCancel;
      else
        Result := acOverwrite;
      end;
    end,
    procedure
    begin
      CheckWait;
    end);
  try
    SetPhase(opScan, 'Подсчёт файлов…');
    Files := 0;
    Bytes := 0;
    for Src in FSources do
      ScanPath(Src, Files, Bytes);
    FLock.Enter;
    try
      FSnap.FilesTotal := Files;
      FSnap.TotalBytesTotal := Bytes;
      if Bytes = 0 then
        FSnap.TotalBytesTotal := Files;
    finally
      FLock.Leave;
    end;
    SetPhase(opReady, Format('К выполнению: %d, %s',
      [Files, FormatOpBytes(Bytes)]));

    while not FStarted and not FCancel do
      Sleep(30);
    if FCancel then
      Abort;

    SetPhase(opRun, FileOpKindCaption(FKind));
    FTickStart := Now;
    FRunStart := Now;
    FBytesAtTick := 0;
    DestDir := FDest;
    if FKind = okArchive then
      ArchiveAll
    else if Assigned(FBatchWork) then
    begin
      FBatchWork();
      FLock.Enter;
      try
        FSnap.FilesDone := FSnap.FilesTotal;
        FSnap.TotalBytesDone := FSnap.TotalBytesTotal;
      finally
        FLock.Leave;
      end;
    end
    else
    begin
      for I := 0 to High(FSources) do
      begin
        CheckWait;
        if FFatal then
          Break;
        try
          ProcessPath(FSources[I], DestDir);
          { Корень обработан (скопирован / пропущен после конфликта) — снять выделение. }
          if FKind in [okCopy, okMove] then
            NotifyItem(FSources[I], oisOk);
        except
          on E: EAbort do
          begin
            if FKind in [okCopy, okMove] then
              NotifyItem(FSources[I], oisSkipped);
            raise;
          end;
          on E: Exception do
          begin
            NoteError(FSources[I], E.Message);
            if FKind in [okCopy, okMove] then
              NotifyItem(FSources[I], oisError);
            if FFatal then
              Break;
          end;
        end;
      end;
    end;
    FLock.Enter;
    try
      if FSnap.Errors > 0 then
      begin
        Ok := False;
        Err := Format('Ошибок: %d', [FSnap.Errors]);
        if FErrorList.Count > 0 then
          Err := Err + ' — ' + FErrorList[0];
        if FErrorList.Count > 1 then
          Err := Err + Format(' (+%d)', [FErrorList.Count - 1]);
        SetPhase(opDone, Err);
      end
      else
        SetPhase(opDone, 'Готово');
    finally
      FLock.Leave;
    end;
  except
    on E: EAbort do
    begin
      Ok := False;
      Err := 'Отменено';
      SetPhase(opCancel, 'Отменено');
    end;
    on E: Exception do
    begin
      Ok := False;
      Err := E.Message;
      SetPhase(opFail, E.Message);
    end;
  end;
  ClearArchiveHooks;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(OnDone) then
        OnDone(Ok, Err);
    end);
end;

end.
