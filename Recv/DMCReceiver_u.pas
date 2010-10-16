unit DMCReceiver_u;

interface
uses
  Windows, Messages, SysUtils, MyClasses,
  FuncLib, Config_u, Protoc_u, Fifo_u,
  Negotiate_u, RecvData_u, HouLog_u;

type
  TReceiverThread = class(TThread)
  private
    FIo: TFifo;
    FNego: TNegotiate;
    FDp: TDataPool;
    FReceiver: TReceiver;
  protected
    procedure Execute; override;
  public
    constructor Create(config: PRecvConfig; OnTransStateChange: TOnTransStateChange);
    destructor Destroy; override;
    procedure Terminate; overload;
  public
    property Io: TFifo read FIo;
    property Nego: TNegotiate read FNego;
  end;

  //API�ӿ�

  //���Ĭ������
procedure DMCConfigFill(var config: TRecvConfig); stdcall;

//��ʼ�Ự  OnTransStateChange ��ѡ
function DMCNegoCreate(config: PRecvConfig; OnTransStateChange: TOnTransStateChange;
  var lpFifo: Pointer): Pointer; stdcall;
//�����Ự
function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;

//�ȴ����ݻ������ɶ�
function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
//����������(�Դӻ�����ȡ��)
function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;

//�ȴ��Ự����(ȷ����ȫ�Ͽ��Ự)
function DMCNegoWaitEnded(lpNego: Pointer): Boolean; stdcall;

//ͳ���Ѿ�����Bytes
function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;

implementation

procedure DMCConfigFill(var config: TRecvConfig);
begin
  FillChar(config, SizeOf(config), 0);
  with config do
  begin
    with net do
    begin
      ifName := nil;                    //eth0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
      localPort := 8090;                //9001
      remotePort := 9080;               //9000

      mcastRdv := nil;
      ttl := 1;

      //SOCKET OPTION
      sockSendBufSize := 0;             //default
      sockRecvBufSize := 512 * 1024;    //�������Recv�����ܽϲ���������㹻�Ļ����������ٶ���
    end;

    dmcMode := dmcFixedMode;
    blockSize := 1456;
  end;
end;

function DMCNegoCreate(config: PRecvConfig; OnTransStateChange: TOnTransStateChange;
  var lpFifo: Pointer): Pointer;
var
  Receiver          : TReceiverThread;
begin
  Receiver := TReceiverThread.Create(config, OnTransStateChange);
  lpFifo := Receiver.Io;
  Result := Receiver;
  Receiver.Resume;
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

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
begin
  try
    Result := TReceiverThread(lpNego).FNego.StatsTotalBytes;
  except on e: Exception do
    begin
      Result := -1;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

{ TReceiverThread }

constructor TReceiverThread.Create;
begin
  FIo := TFifo.Create(config^.blockSize);
  FNego := TNegotiate.Create(config, OnTransStateChange);

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

      if FNego.TransState <> tsComplete then
        FIo.DataPC.MarkEnd;             //������������ȡ��[�ź�]
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
      FIo.Close;
    end
    else                                //�Ự��?
      FNego.StopNegotiate;
  except
  end;
end;

end.
 
