unit Stats_u;

interface
uses
  Windows, Sysutils, Messages, WinSock,
  Config_u, Func_u, IStats_u;

type
  TReceiverStats = class(TInterfacedObject, ITransStats)
  private
    FTransmitting: Boolean;
    FConfig: PNetConfig;
    FStartTime: DWORD; //���俪ʼʱ��
    FStatPeriod: DWORD; //״̬��ʾ����
    FPeriodStart: DWORD; //���ڿ�ʼ����
    FLastPosBytes: Int64; //���ͳ�ƽ���
    FTotalBytes: Int64; //��������
  protected
    procedure DoDisplay();
  public
    constructor Create(config: PNetConfig; statPeriod: Integer);
    destructor Destroy; override;

    procedure BeginTrans();
    procedure EndTrans();
    procedure AddBytes(bytes: Integer);
    procedure AddRetrans(nrRetrans: Integer); virtual; abstract;
    procedure Msg(msgType: TUMsgType; msg: string);
    function Transmitting(): Boolean;
  end;

implementation

{ TReceiverStats }

constructor TReceiverStats.Create(config: PNetConfig; statPeriod: Integer);
begin
  FConfig := config;
  FStatPeriod := statPeriod;
end;

destructor TReceiverStats.Destroy;
begin
  inherited;
end;

procedure TReceiverStats.BeginTrans;
begin
  FTransmitting := True;
  FStartTime := GetTickCount;
  FPeriodStart := FStartTime;
end;

procedure TReceiverStats.EndTrans;
begin
  FTransmitting := False;
  DoDisplay;
end;

procedure TReceiverStats.AddBytes(bytes: Integer);
begin
  Inc(FTotalBytes, bytes);
  DoDisplay;
end;

procedure TReceiverStats.DoDisplay();
var
  tickNow, tdiff: DWORD;
  blocks: dword;
  bw: double;
  hOut: THandle;
  conBuf: TConsoleScreenBufferInfo;
begin
  tickNow := GetTickCount;

  if FTransmitting then
  begin
    tdiff := DiffTickCount(FPeriodStart, tickNow);
    if (tdiff < FStatPeriod) then Exit;
    //����ͳ��
    bw := (FTotalBytes - FLastPosBytes) / tdiff * 1000; // Byte/s
  end else
  begin
    tdiff := DiffTickCount(FStartTime, tickNow);
    if tdiff = 0 then tdiff := 1;
   //ƽ������ͳ��
    bw := FTotalBytes / tdiff * 1000; // Byte/s
  end;

  //��ʾ״̬
{$IFDEF CONSOLE}
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hOut, conBuf);
  conBuf.dwCursorPosition.X := 0;
  SetConsoleCursorPosition(hOut, conBuf.dwCursorPosition);

  Write(Format('bytes=%d speed=%s', [FTotalBytes, GetSizeKMG(Trunc(bw))]));
{$ENDIF}
  FPeriodStart := GetTickCount;
  FLastPosBytes := FTotalBytes;
end;

function TReceiverStats.Transmitting: Boolean;
begin
  Result := FTransmitting;
end;

procedure TReceiverStats.Msg(msgType: TUMsgType; msg: string);
begin
{$IFDEF CONSOLE}
  writeln(msg);
{$ENDIF}
end;

end.

