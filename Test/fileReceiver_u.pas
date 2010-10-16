unit fileReceiver_u;

interface

uses
  Windows, Messages, SysUtils, MyClasses, WinSock,
  FuncLib, Config_u, HouLog_u;

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
  end;

const
  MY_CRLF_LINE      = '��������������������������������������������������������������������'#13#10;

var
  g_Nego            : Pointer;
  g_Fifo            : Pointer;
  g_TransState      : TTransState;

  { �ٶ�ͳ�� }
  g_StatsTimer      : THandle;
  g_TransStartTime  : DWORD;
  g_TransPeriodStart: DWORD;
  g_LastPosBytes    : Int64;

  g_WaitTimer       : THandle;

procedure Writeln(s: string);
function RunReceiver(const FileName: string): Boolean;

procedure OnTransStateChange(TransState: TTransState);
procedure DoDisplayStats;
implementation
//{$DEFINE IS_IMPORT_MODULE}
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

//��ʼ�Ự  OnTransStateChange ��ѡ

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
        SetEvent(g_WaitTimer);
      end;
    tsExcept:
      begin
{$IFDEF CONSOLE}
        Writeln('Transfer Except!');
{$ENDIF}
        SetEvent(g_WaitTimer);
      end;

    tsStop:
      begin
{$IFDEF CONSOLE}
        Writeln('Stop.');
{$ENDIF}
        SetEvent(g_WaitTimer);
      end;
  end;
end;

procedure DoDisplayStats;
var
  hOut              : THandle;
  conBuf            : TConsoleScreenBufferInfo;

  totalBytes, bwBytes: Int64;
  tickNow, tdiff    : DWORD;

  bw                : Double;
begin
  tickNow := GetTickCount;
  totalBytes := DMCStatsTotalBytes(g_Nego);

  if g_TransState = tsTransing then
  begin
    tdiff := DiffTickCount(g_TransPeriodStart, tickNow);
    bwBytes := totalBytes - g_LastPosBytes;
  end
  else
  begin
    tdiff := DiffTickCount(g_TransStartTime, tickNow);
    bwBytes := totalBytes;
  end;
  if tdiff = 0 then
    tdiff := 1;
  //ƽ������ͳ��
  bw := bwBytes * 1000 / tdiff;         // Byte/s

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
  while True do                         //ȷ��������������ȫд��
  begin
    dwBytes := 4096;
    lpBuf := DMCDataReadWait(FFifo, dwBytes); //�ȴ�����
    if (lpBuf = nil) then               //data end?
      Break;

    dwBytes := FFile.Write(lpBuf^, dwBytes);
    if Integer(dwBytes) <= 0 then
    begin
      Writeln(#13#10'File Write Error: ' + SysErrorMessage(GetLastError));
      Halt(0);
      Exit;
    end;

    DMCDataReaded(FFifo, dwBytes);
  end;
end;

{ End }

function RunReceiver(const FileName: string): Boolean;
var
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

  if g_Nego = nil then
  begin
{$IFDEF EN_LOG}
    OutLog('DMCNegoCreate Fail!');
{$ENDIF}
    Exit;
  end;

  FileWriter := TFileWriter.Create(fileName, g_Fifo);

  while WaitForSingleObject(g_WaitTimer, 1000) = WAIT_TIMEOUT do
  begin
    if g_TransState = tsTransing then
      DoDisplayStats;
  end;

  FileWriter.WaitFor;                   //�ȴ�����д�����

  DMCNegoWaitEnded(g_Nego);
  DMCNegoDestroy(g_Nego);
  FileWriter.Free;
end;

procedure Writeln(s: string);
begin
  System.Write(s + #13#10 + MY_CRLF_LINE);
end;

{$IFDEF CONSOLE}

procedure MyOutLog2(level: TLogLevel; s: string);
begin
  System.Writeln(LOG_MSG_TYPE[level], ': ', s);
end;
{$ENDIF}

initialization
{$IFDEF EN_LOG}
{$IFDEF CONSOLE}
  OutLog2 := MyOutLog2;
{$ENDIF}
{$ENDIF}
  g_WaitTimer := CreateEvent(nil, True, False, nil);

finalization
  CloseHandle(g_WaitTimer);

end.

