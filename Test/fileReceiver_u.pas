unit fileReceiver_u;

interface

uses
  Windows, Messages, SysUtils, MyClasses, WinSock,
  FuncLib, Config_u, Window_u, HouLog_u;

type
  TFileWriter = class(TThread)
  private
    FFile: TFileStream;
    FFifo: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(fileName: string; lpFifo: Pointer);
    destructor Destroy; override;
    procedure Terminate; overload;
  end;

var
  g_Nego            : Pointer;
  g_Fifo            : Pointer;
  g_TransState      : TTransState;

  { �ٶ�ͳ�� }
  g_StatsTimer      : THandle;
  g_TransStartTime  : DWORD;
  g_TransPeriodStart: DWORD;
  g_LastPosBytes    : Int64;

function RunReceiver(const FileName: string): Boolean;

procedure OnTransStateChange(TransState: TTransState);
procedure DoDisplayStats;
implementation
{$DEFINE IS_IMPORT_MODULE}
{$IFNDEF IS_IMPORT_MODULE}
uses
  DMCReceiver_u;
{$ELSE}
//API�ӿ�
const
  DMC_RECEIVER_DLL  = 'DMCReceiver.dll';

  //���Ĭ������

procedure DMCConfigFill(var config: TRecvConfig); stdcall;
  external DMC_RECEIVER_DLL;

//��ʼ�Ự  TransStats ����Ϊnil

function DMCNegoCreate(config: PRecvConfig; OnTransStateChange: TOnTransStateChange;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

//�����Ự

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//�ȴ����ݻ������ɶ�

function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

//����������(�Դӻ�����ȡ��)

function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//�ȴ��Ự����(ȷ����ȫ�Ͽ��Ự)

function DMCNegoWaitEnded(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//ͳ���Ѿ�����Bytes

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
  external DMC_RECEIVER_DLL;
{$ENDIF}

{ TReceiverStats }

procedure OnTransStateChange(TransState: TTransState);
begin
  g_TransState := TransState;
  case TransState of
    tsNego:
      begin
{$IFDEF CONSOLE}
        Writeln('Start Negotiations...');
{$ENDIF}
      end;
    tsTransing:
      begin
        g_TransStartTime := GetTickCount;
        g_TransPeriodStart := g_TransStartTime;
        g_StatsTimer := SetTimer(WinHandle, 0, 1000, nil);
{$IFDEF CONSOLE}
        Writeln('Start Trans..');
{$ENDIF}
      end;
    tsComplete:
      begin
        DoDisplayStats;
{$IFDEF CONSOLE}
        Writeln('Transfer Complete.');
{$ENDIF}
        PostMessage(WinHandle, WM_QUIT, 0, 0);
      end;
    tsExcept:
      begin
{$IFDEF CONSOLE}
        Writeln('Transfer Except!');
{$ENDIF}
        PostMessage(WinHandle, WM_QUIT, 0, 0);
      end;

    tsStop:
      begin
{$IFDEF CONSOLE}
        Writeln('Stop.');
{$ENDIF}
        PostMessage(WinHandle, WM_QUIT, 0, 0);
      end;
  end;
end;

procedure DoDisplayStats;
var
  hOut              : THandle;
  conBuf            : TConsoleScreenBufferInfo;

  totalBytes        : Int64;
  tickNow, tdiff    : DWORD;

  bw                : Double;
begin
  if g_Nego = nil then
  begin
    KillTimer(WinHandle, g_StatsTimer);
    Exit;
  end;

  tickNow := GetTickCount;
  totalBytes := DMCStatsTotalBytes(g_Nego);

  tdiff := DiffTickCount(g_TransStartTime, tickNow);
  if tdiff = 0 then
    tdiff := 1;
  //ƽ������ͳ��
  bw := totalBytes * 1000 / tdiff;      // Byte/s

  //��ʾ״̬
{$IFDEF CONSOLE}
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hOut, conBuf);
  conBuf.dwCursorPosition.X := 0;
  SetConsoleCursorPosition(hOut, conBuf.dwCursorPosition);

  Write(Format('bytes=%d(%s)'#9'speed=%s/s'#9#9,
    [totalBytes, GetSizeKMG(totalBytes), GetSizeKMG(Trunc(bw))]));
  if g_TransState <> tsTransing then
    WriteLn('');
{$ENDIF}

  g_LastPosBytes := totalBytes;
  g_TransPeriodStart := GetTickCount;
end;

{ TFileWriter }

constructor TFileWriter.Create(fileName: string; lpFifo: Pointer);
begin
  FFifo := lpFifo;
  FFile := TFileStream.Create(fileName, fmShareDenyNone or fmCreate);
  inherited Create(False);
end;

destructor TFileWriter.Destroy;
begin
  if Assigned(FFile) then
    FFile.Free;
  inherited;
end;

procedure TFileWriter.Execute;
var
  lpBuf             : PByte;
  dwBytes           : DWORD;
begin
  while not Terminated do
  begin
    dwBytes := 4096;
    lpBuf := DMCDataReadWait(FFifo, dwBytes); //�ȴ�����
    if (lpBuf = nil) or Terminated then
      Break;

    dwBytes := FFile.Write(lpBuf^, dwBytes);
    DMCDataReaded(FFifo, dwBytes);
  end;
end;

procedure TFileWriter.Terminate;
begin
  inherited Terminate;
  DMCDataReaded(FFifo, 0);
  WaitFor;
end;

{ End }

function RunReceiver(const FileName: string): Boolean;
var
  msg               : TMsg;
  config            : TRecvConfig;
  FileWriter        : TFileWriter;
begin
  //Ĭ������
  DMCConfigFill(config);

{$IFDEF EN_LOG}
  OutLog('File Save to ' + fileName);
{$ELSE}
{$IFDEF CONSOLE}
  WriteLn('File Save to ' + fileName);
{$ENDIF}
{$ENDIF}

  g_Nego := DMCNegoCreate(@config, OnTransStateChange, g_Fifo);

  if Assigned(g_Fifo) then
    FileWriter := TFileWriter.Create(fileName, g_Fifo);

  while GetMessage(msg, 0, 0, 0) do
  begin
    case msg.message of
      WM_TIMER: DoDisplayStats;
      WM_QUIT: Break;
    else
      TranslateMessage(msg);
      DispatchMessage(msg);
    end;
  end;

  DMCNegoWaitEnded(g_Nego);
  DMCNegoDestroy(g_Nego);

  FileWriter.WaitFor;
  FileWriter.Free;
end;

{$IFDEF EN_LOG}
{$IFDEF CONSOLE}

procedure MyOutLog2(level: TLogLevel; s: string);
begin
  Writeln(DMC_MSG_TYPE[level], ': ', s);
end;

initialization
  OutLog2 := MyOutLog2;
{$ENDIF}
{$ENDIF}

end.

