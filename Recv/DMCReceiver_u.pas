unit DMCReceiver_u;

interface
uses
  Windows, Messages, SysUtils, Classes,
  FuncLib, Config_u, Protoc_u, IStats_u,
  Negotiate_u, Fifo_u, RecvData_u, HouLog_u;

type
  TReceiverThread = class(TThread)
  private
    FConfig: PRecvConfig;
    FStats: IReceiverStats;

    FIo: TFifo;
    FNego: TNegotiate;
    FDp: TDataPool;
    FReceiver: TReceiver;
  protected
    procedure Execute; override;
  public
    constructor Create(config: PRecvConfig; TransStats: IReceiverStats);
    destructor Destroy; override;
    procedure Terminate; overload;
  public
    property Io: TFifo read FIo;
    property Nego: TNegotiate read FNego;
  end;

  //API�ӿ�

  //���Ĭ������
function DMCConfigFill(var config: TRecvConfig): Boolean; stdcall;
//��ʼ�Ự
function DMCNegoCreate(config: PRecvConfig; TransStats: IReceiverStats;
  var lpFifo: Pointer): Pointer; stdcall;
//�ȴ����ݻ������ɶ�
function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
//����������(�Դӻ�����ȡ��)
function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
//�ȴ��Ự����(ȷ����ȫ�Ͽ��Ự)
function DMCNegoWaitEnded(lpNego: Pointer): Boolean; stdcall;
//�����Ự
function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;

implementation

function DMCConfigFill(var config: TRecvConfig): Boolean;
begin
  //FillChar(config, SizeOf(config), 0);
  with config do
  begin
    with net do
    begin
      ifName := 'eth0';                 //eth0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
      localPort := 8090;                //9001
      remotePort := 9080;               //9000

      mcastRdv := nil;
      ttl := 1;

      //SOCKET OPTION
      sockSendBufSize := 0;             //default
      sockRecvBufSize := 0;             //default
    end;

    flags := [];
    blockSize := 1456;
  end;
end;

function DMCNegoCreate(config: PRecvConfig; TransStats: IReceiverStats;
  var lpFifo: Pointer): Pointer;
var
  Receiver          : TReceiverThread;
begin
  Receiver := TReceiverThread.Create(config, TransStats);
  lpFifo := Receiver.Io;
  Result := Receiver;
  Receiver.Resume;
end;

function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer;
var
  pos, bytes        : Integer;
begin
  pos := TFifo(lpFifo).DataPC.GetConsumerPosition;
  bytes := TFifo(lpFifo).DataPC.ConsumeContiguousMinAmount(dwBytes);
  if (bytes > (pos + bytes) mod DISK_BLOCK_SIZE) then
    Dec(bytes, (pos + bytes) mod DISK_BLOCK_SIZE);

  dwBytes := bytes;
  if bytes > 0 then
    Result := TFifo(lpFifo).GetDataBuffer(pos)
  else
    Result := nil;
end;

function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean;
begin
  if (dwBytes > 0) then
  begin
    TFifo(lpFifo).DataPC.Consumed(dwBytes);
    TFifo(lpFifo).FreeMemPC.Produce(dwBytes);
  end
  else                                  //no data
  begin
    TFifo(lpFifo).FreeMemPC.MarkEnd;
    TFifo(lpFifo).DataPC.MarkEnd;
  end;
end;

function DMCNegoWaitEnded(lpNego: Pointer): Boolean;
begin
  try
    Result := True;
    TReceiverThread(lpNego).WaitFor;
  except on e: Exception do
    begin
      Result := False;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

function DMCNegoDestroy(lpNego: Pointer): Boolean;
begin
  try
    Result := True;
    TReceiverThread(lpNego).Terminate;
    TReceiverThread(lpNego).Free;
  except on e: Exception do
    begin
      Result := False;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

{ TReceiverThread }

constructor TReceiverThread.Create(config: PRecvConfig; TransStats: IReceiverStats);
begin
  FConfig := config;
  FIo := TFifo.Create(config^.blockSize);
  FStats := TransStats;
  FNego := TNegotiate.Create(config, TransStats);

  FDp := TDataPool.Create;
  FReceiver := TReceiver.Create;
  inherited Create(True);
end;

destructor TReceiverThread.Destroy;
begin
  if Assigned(FIo) then
    FIo.Free;
  if Assigned(FDp) then
    FreeAndNil(FDp);
  if Assigned(FReceiver) then
    FreeAndNil(FReceiver);
  if Assigned(FNego) then
    FNego.Free;
  inherited;
end;

procedure TReceiverThread.Execute;
begin
  try
    if FNego.StartNegotiate then
    begin                               //�Ự�ɹ�����ʼ����
      FDp.Init(FNego, FIo);
      FReceiver.Init(FNego, FDp);

      FReceiver.Execute;                //ִ�з���
    end;
  finally
    FNego.TransState := tsStop;
  end;
end;

procedure TReceiverThread.Terminate;
begin
  inherited Terminate;

  try
    if FNego.TransState <> tsNego then
    begin
      FDp.Close;
      FNego.USocket.Close;
      FIo.Terminate;
    end
    else                                //�Ự��?
      FNego.StopNegotiate;
  except
  end;
end;

end.
 
