unit SendData_u;

interface
uses
  Windows, Sysutils, Classes, WinSock, Func_u,
  Config_u, Protoc_u, IStats_u, INegotiate_u, Participants_u,
  Produconsum_u, Log_u, SockLib_u;

const
  NR_SLICES         = 2;

type
  TSlice = class;
  TDataPool = class;
  TRChannel = class;
  TSender = class;

  TSliceState = (SLICE_FREE,            { free slice, and in the queue of free slices }
    SLICE_NEW,                          { newly allocated. FEC calculation and first transmission }
    SLICE_XMITTED,                      { transmitted }
    SLICE_PRE_FREE                      { no longer used, but not returned to queue }
    );

  TClientsMap = array[0..MAX_CLIENTS div BITS_PER_CHAR - 1] of Byte;
  TBlocksMap = array[0..MAX_SLICE_SIZE div BITS_PER_CHAR - 1] of Byte;

  TReqackBm = packed record             //����ȷ��,�Ѿ�׼��Map
    ra: TReqack;
    readySet: TClientsMap;              { who is already ok? }
  end;

  TSlice = class
  private
    FBase: DWORD_PTR;                   { base address of slice in buffer }
    FSliceNo: Integer;
    FBytes: Integer;                    { bytes in slice }
    FNextBlock: Integer;                { index of next buffer to be transmitted }
    FState: TSliceState;                {volatile}
    FRxmitMap: TBlocksMap;
    { blocks to be retransmitted }

    FXmittedMap: TBlocksMap;
    FAnsweredMap: TClientsMap;          { who answered at all? }
    { blocks which have already been retransmitted during this round}

    FRxmitId: Integer;                  //�������ּ����ط�����ʹ�����ܹ����׷����ġ��ɡ�������Ĵ�

    { ����ṹ���������ٿͻ�answered ,������reqack��Ϣ }
    FReqackBm: TReqackBm;

    FNrReady: Integer;                  { number of participants who are ready }
    FNrAnswered: Integer;               { number of participants who answered; }
    FNeedRxmit: Boolean;                { does this need retransmission? }
    FLastGoodBlocks: Integer; { last good block of slice (i.e. last block having not
    * needed retransmission }

    FLastReqack: Integer;               { last req ack sent (debug) }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFecData: PChar;
{$ENDIF}
    FDp: TDataPool;
    FRc: TRChannel;
    FConfig: PNetConfig;
    FUSocket: TUDPSocket;
    FNegotiate: INegotiate;
    FStats: ISenderStats;
  private
    function SendRawData(header: PChar; headerSize: Integer;
      data: PChar; dataSize: Integer): Integer;
    function TransmitDataBlock(i: Integer): Integer;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    function TransmitFecBlock(i: Integer): Integer;
{$ENDIF}
  public
    constructor Create(Config: PNetConfig;
      Dp: TDataPool;
      Rc: TRChannel;
      USocket: TUDPSocket;
      Negotiate: INegotiate;
      Stats: ISenderStats);
    destructor Destroy; override;
    procedure Init(sliceNo: Integer; base: DWORD_PTR;
{$IFDEF BB_FEATURE_UDPCAST_FEC}fecData: PChar; {$ENDIF}bytes: Integer);
    function GetBlocks(): Integer;
    function SendSlice(isRetrans: Boolean): Integer;
    function SendReqack(): Integer;
    procedure MarkOk(clNo: Integer);
    procedure MarkDisconnect(clNo: Integer);
    procedure MarkParticipantAnswered(clNo: Integer);
    procedure MarkRetransmit(clNo: Integer; map: PByteArray; rxmit: Integer);
    function IsReady(clNo: Integer): Boolean;
  published
    property State: TSliceState read FState write FState;
    property SliceNo: Integer read FSliceNo;
    property Bytes: Integer read FBytes;
    property NextBlock: Integer read FNextBlock; { index of next buffer to be transmitted }
    property NrReady: Integer read FNrReady;
    property NeedRxmit: Boolean read FNeedRxmit;
    property NrAnswered: Integer read FNrAnswered;
    property RxmitId: Integer read FRxmitId write FRxmitId;
  end;

  TDataPool = class(TThread)            //���ݷ�Ƭ�����
  private
    FFile: Integer;
    FOrigFDataBuffer: DWORD_PTR;        //ԭʼ������ָ��
    FDataBuffer: DWORD_PTR;
    FDataBufSize: DWORD;
    FDataPC: TProduceConsum;            //��������
    FFreeMemPC: TProduceConsum;         //���ÿռ�

    FNrContSlice: Integer;              //�����ɹ�Ƭ���������ж��Ƿ�Ҫ����Ƭ��С
    FSliceNo: Integer;
    FSlices: array[0..NR_SLICES - 1] of TSlice;
    FFreeSlicesPC: TProduceConsum;      //����Ƭ
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFecData: PChar;
    FFecThread: THandle;
    FFecDataPC: TProduceConsum;
{$ENDIF}

    FConfig: PNetConfig;
    FStats: ISenderStats;
  public
    constructor Create(Config: PNetConfig; Stats: ISenderStats);
    destructor Destroy; override;
    procedure Terminate; overload;
    procedure InitData(Rc: TRChannel;
      USocket: TUDPSocket; Negotiate: INegotiate); //������ǰ��һ��Ҫִ�У�

    function MakeSlice(): TSlice;       //׼������Ƭ
    function AckSlice(Slice: TSlice): Integer; //ȷ��Ƭ���ɹ�����>=0
    function FreeSlice(Slice: TSlice): Integer;
    function FindSlice(Slice1, Slice2: TSlice; sliceNo: Integer): TSlice;
  protected
    procedure Execute; override;        //ѭ���ȴ���ȡ���ݵ����Ͷ���
  published
    property DataPC: TProduceConsum read FDataPC;
    property FreeMemPC: TProduceConsum read FFreeMemPC;
    property DataBuffer: DWORD_PTR read FDataBuffer;
    property DataBufSize: DWORD read FDataBufSize;
    property NrContSlice: Integer read FNrContSlice write FNrContSlice;
  end;

  TCtrlMsgQueue = packed record
    clNo: Integer;                      //�ͻ���ţ�������
    msg: TCtrlMsg;                      //������Ϣ
  end;

  TRChannel = class(TThread)            //�ͻ�����Ϣ�������Thread
  private
    FUSocket: TUDPSocket;               { socket on which we receive the messages }

    FIncomingPC: TProduceConsum;        { where to enqueue incoming messages }
    FFreeSpacePC: TProduceConsum;       { free space }
    FMsgQueue: array[0..RC_MSG_QUEUE_SIZE - 1] of TCtrlMsgQueue; //��Ϣ����

    FDp: TDataPool;
    FConfig: PNetConfig;
    FParts: TParticipants;
  public
    constructor Create(config: PNetConfig; USocket: TUDPSocket;
      Dp: TDataPool; Parts: TParticipants);
    destructor Destroy; override;
    procedure Terminate; overload;
    procedure HandleNextMessage(xmitSlice, rexmitSlice: TSlice); //��������Ϣ�����е���Ϣ
  protected
    procedure Execute; override;        //ѭ�����տͻ��˷�����Ϣ����������
  published
    property IncomingPC: TProduceConsum read FIncomingPC;
  end;

  TSender = class                       //(TThread)   //���ݷ��͡�����Э��
  private
    FDp: TDataPool;
    FRc: TRChannel;
    FConfig: PNetConfig;
    FParts: TParticipants;
    FStats: ISenderStats;
    FTerminated: Boolean;               //��ֹ����
  public
    constructor Create(Config: PNetConfig;
      Dp: TDataPool;
      Rc: TRChannel;
      Parts: TParticipants;
      Stats: ISenderStats);
    destructor Destroy; override;

    procedure Execute;                  //override;    //ѭ�����ͺʹ���ͻ��˷�����Ϣ
  published
    property Terminated: Boolean read FTerminated write FTerminated;
  end;

implementation

{ TSlice }

constructor TSlice.Create(Config: PNetConfig;
  Dp: TDataPool;
  Rc: TRChannel;
  USocket: TUDPSocket;
  Negotiate: INegotiate;
  Stats: ISenderStats);
begin
  FState := SLICE_FREE;
  FConfig := Config;
  FDp := Dp;
  FRc := Rc;
  FUSocket := USocket;
  FNegotiate := Negotiate;
  FStats := Stats;
end;

destructor TSlice.Destroy;
begin
  inherited;
end;

function TDataPool.AckSlice(Slice: TSlice): Integer;
begin
  if not Boolean(FConfig^.flags and FLAG_SN) then //ȫ�ֹ�������Ҫ����(�ɲ�ͣ�ķ�)
    if (FConfig^.sliceSize < FConfig^.max_slice_size) then //������
      if (FConfig^.discovery = DSC_DOUBLING) then begin //����Ƭ��С
        Inc(FConfig^.sliceSize, FConfig^.sliceSize div DOUBLING_SETP);
        if (FConfig^.sliceSize >= FConfig^.max_slice_size) then begin
          FConfig^.sliceSize := FConfig^.max_slice_size;
          FConfig^.discovery := DSC_REDUCING;
        end;
        logprintf(g_udpc_log, 'Doubling slice size to %d'#10,
          [FConfig^.sliceSize]);
      end else begin                    //�ɹ�Ƭ����
        if FNrContSlice >= MIN_CONT_SLICE then begin
          FConfig^.discovery := DSC_DOUBLING;
          FNrContSlice := 0;
        end else
          Inc(FNrContSlice);
      end;

  Result := Slice.Bytes;
  FreeMemPC.Produce(Result);
  FreeSlice(Slice);                     //�ͷ�Ƭ

  FStats.AddBytes(Result);              //����״̬
end;

function TSlice.GetBlocks: Integer;
begin
  Result := (FBytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
end;

procedure TSlice.Init(sliceNo: Integer; base: DWORD_PTR;
{$IFDEF BB_FEATURE_UDPCAST_FEC}fecData: PChar; {$ENDIF}bytes: Integer);
begin
  FState := SLICE_NEW;

  FBase := base;
  FBytes := bytes;
  FSliceNo := sliceNo;

  FNextBlock := 0;
  FRxmitId := 0;

  FillChar(FReqackBm, SizeOf(FReqackBm), 0);
  FillChar(FRxmitMap, SizeOf(FRxmitMap), 0);
  FillChar(FXmittedMap, SizeOf(FXmittedMap), 0);
  FillChar(FAnsweredMap, SizeOf(FAnsweredMap), 0);

  FNrReady := 0;
  FNrAnswered := 0;
  FNeedRxmit := False;
  FLastGoodBlocks := 0;

  FLastReqack := 0;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FFecData := fecData;
{$ENDIF}
end;

function TSlice.SendReqack(): Integer;
var
  nrBlocks          : Integer;
begin
  Inc(FRxmitId);

  //�����첽�Ҳ��ǵ�һ���ش�����ȷ��
  if not Boolean(FConfig^.flags and FLAG_SN) and (FRxmitId <> 0) then
  begin
    nrBlocks := GetBlocks();
{$IFDEF DEBUG}
    flprintf('nrBlocks=%d lastGoodBlocks=%d\n',
      nrBlocks, FLastGoodBlocks);
{$ENDIF}
    //�����ǰ���������ϴγɹ��Ŀ�������СƬ��С
    if (FLastGoodBlocks <> 0) and (FLastGoodBlocks < nrBlocks) then begin
      FConfig^.discovery := DSC_REDUCING;
      if (FLastGoodBlocks < FConfig^.sliceSize div REDOUBLING_SETP) then
        FConfig^.sliceSize := FConfig^.sliceSize div REDOUBLING_SETP
      else
        FConfig^.sliceSize := FLastGoodBlocks;

      if (FConfig^.sliceSize < MIN_SLICE_SIZE) then
        FConfig^.sliceSize := MIN_SLICE_SIZE;

      logprintf(g_udpc_log, 'Slice size^.%d'#10, [FConfig^.sliceSize]);
    end;
  end;

  FLastGoodBlocks := 0;
{$IFDEF DEBUG}
  flprintf('Send reqack %d.%d\n', FSliceNo, slice^.rxmitId);
{$ENDIF}
  FReqackBm.ra.opCode := htons(Word(CMD_REQACK));
  FReqackBm.ra.sliceNo := htonl(FSliceNo);
  FReqackBm.ra.bytes := htonl(FBytes);

  FReqackBm.ra.reserved := 0;
  move(FReqackBm.readySet, FAnsweredMap, SizeOf(FAnsweredMap));
  FNrAnswered := FNrReady;

  { not everybody is ready yet }
  FNeedRxmit := False;
  FillChar(FRxmitMap, SizeOf(FRxmitMap), 0);
  FillChar(FXmittedMap, SizeOf(FXmittedMap), 0);
  FReqackBm.ra.rxmit := htonl(FRxmitId);

  //  rgWaitAll(net_config, sock,
  //    FUSocket.CastAddr.sin_addr.s_addr,
  //    SizeOf(FReqackBm));
{$IFDEF DEBUG}
  flprintf('sending reqack for slice %d\n', FSliceNo);
{$ENDIF}
  //BCAST_DATA(sock, FReqackBm);
  {��������}
  Result := FUSocket.SendCtrlMsgCast(FReqackBm, SizeOf(FReqackBm));
end;

function TSlice.SendSlice(isRetrans: Boolean): Integer;
var
  nrBlocks, i, rehello: integer;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  fecBlocks         : Integer;
{$ENDIF}
  nrRetrans         : Integer;
begin
  Result := 0;
  nrRetrans := 0;

  if isRetrans then begin
    FNextBlock := 0;
    if (FState <> SLICE_XMITTED) then
      Exit;
  end else
    if (FState <> SLICE_NEW) then
      Exit;

  nrBlocks := GetBlocks();
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if Boolean(FConfig^.flags and FLAG_FEC) and not isRetrans then
    fecBlocks := FConfig^.fec_redundancy * FConfig^.fec_stripes
  else
    fecBlocks := 0;
{$ENDIF}

{$IFDEF DEBUG}
  if isRetrans then
  begin
    flprintf('%s slice %d from %d to %d (%d bytes) %d\n',
      'Retransmitting:' + BoolToStr(isRetrans),
      FSliceNo, slice^.nextBlock, nrBlocks, FBytes,
      FConfig^.blockSize);
  end;
{$ENDIF}

  if Boolean(FConfig^.flags and FLAG_STREAMING) then
  begin
    rehello := nrBlocks - FConfig^.rehelloOffset;
    if rehello < 0 then
      rehello := 0
  end else
    rehello := -1;

  { transmit the data }

  for i := FNextBlock to nrBlocks
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  + fecBlocks
{$ENDIF} - 1 do
  begin
    if isRetrans then begin
      if not BIT_ISSET(i, @FRxmitMap) or
        BIT_ISSET(i, @FXmittedMap) then
      begin                             //��������ش��б���Ѿ������ô����
        if (i > FLastGoodBlocks) then
          FLastGoodBlocks := i;
        Continue;
      end;

      SET_BIT(i, @FXmittedMap);
      Inc(nrRetrans);
{$IFDEF DEBUG}
      flprintf('Retransmitting %d.%d\n', FSliceNo, i);
{$ENDIF}
    end;

    if (i = rehello) then
      FNegotiate.SendHello(True);       //��ģʽ

    if i < nrBlocks then
      TransmitDataBlock(i)
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    else
      TransmitFecBlock(i - nrBlocks)
{$ENDIF};
    if not Boolean(isRetrans) and (FRc.FIncomingPC.GetProducedAmount > 0) then
      Break;                            //�����ʱ���з�����Ϣ(һ��Ϊ��Ҫ�ش�)������ֹ���䣬����
  end;                                  //end while

  if nrRetrans > 0 then
    FStats.AddRetrans(nrRetrans);       //����״̬


  if i <> nrBlocks
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  + fecBlocks
{$ENDIF} then begin
    FNextBlock := i                     //����Ƭû�д����꣬��ס�´�Ҫ�����λ��
  end else
  begin
    FNeedRxmit := False;
    if not Boolean(isRetrans) then FState := SLICE_XMITTED;

{$IFDEF DEBUG}
    flprintf('Done: at block %d %d %d\n', i, isRetrans,
      FState);
{$ENDIF}
    Result := 2;
    Exit;
  end;
{$IFDEF DEBUG}
  flprintf('Done: at block %d %d %d\n', i, isRetrans,
    FState);
{$ENDIF}
  Result := 1;
end;

function TSlice.SendRawData(header: PChar; headerSize: Integer;
  data: PChar; dataSize: Integer): Integer;
var
  iov               : array[0..1] of TIovec;
  hdr               : TMsghdr;
begin
  iov[0].iov_base := header;
  iov[0].iov_len := headerSize;

  iov[1].iov_base := data;
  iov[1].iov_len := dataSize;

  hdr.msg_iov := @iov;
  hdr.msg_iovlen := 2;

  ////rgWaitAll(config, sock, FUSocket.CastAddr.sin_addr.s_addr, dataSize + headerSize);
  Result := FUSocket.SendDataMsg(hdr);
  if (Result < 0) then
  begin
    raise Exception.CreateFmt('(%d) Could not broadcast data packet to %s:%d',
      [GetLastError, inet_ntoa(FUSocket.DataAddr.sin_addr),
      ntohs(FUSocket.DataAddr.sin_port)]);
  end;
end;

function TSlice.TransmitDataBlock(i: Integer): Integer;
var
  msg               : TDataBlock;
  size              : Integer;
begin
  assert(i < MAX_SLICE_SIZE);

  msg.opCode := htons(Word(CMD_DATA));
  msg.sliceNo := htonl(FSliceNo);
  msg.blockNo := htons(i);

  msg.reserved := 0;
  msg.reserved2 := 0;
  msg.bytes := htonl(FBytes);

  size := FBytes - i * FConfig^.blockSize;
  if size < 0 then
    size := 0;
  if size > FConfig^.blockSize then
    size := FConfig^.blockSize;

  Result := SendRawData(@msg, SizeOf(msg),
    Pointer(FDp.DataBuffer +
    (FBase + i * FConfig^.blockSize) mod FDp.DataBufSize),
    size);
end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}

function TSlice.TransmitFecBlock(int i): Integer;
var
  config            : PNetConfig;
  msg               : fecBlock;
begin
  Result := 0;
  config := sendst^.config;

  { Do not transmit zero byte FEC blocks if we are not in async mode }
  if (FBytes = 0 and not Boolean(FConfig^.flags and FLAG_ASYNC)) then
    Exit;

  assert(i < FConfig^.fec_redundancy * FConfig^.fec_stripes);

  msg.opCode := htons(CMD_FEC);
  msg.stripes := htons(FConfig^.fec_stripes);
  msg.sliceNo := htonl(slice^.sliceNo);
  msg.blockNo := htons(i);
  msg.reserved2 := 0;
  msg.bytes := htonl(FBytes);
  SendRawData(sendst^.socket, sendst^.config,
    @msg, SizeOf(msg),
    (slice^.fec_data + i * FConfig^.blockSize), FConfig^.blockSize);
end;
{$ENDIF}

procedure TSlice.MarkOk(clNo: Integer);
begin
  if (BIT_ISSET(clNo, @FReqackBm.readySet)) then begin
    { client is already marked ready }
{$IFDEF DEBUG}
    flprintf('client %d is already ready\n', clNo);
{$ENDIF}
  end else begin
    SET_BIT(clNo, @FReqackBm.readySet);
    Inc(FNrReady);
{$IFDEF DEBUG}
    flprintf('client %d replied ok for %p %d ready = %d\n', clNo,
      self, FSliceNo, FNrReady);
{$ENDIF}
    MarkParticipantAnswered(clNo);
  end;
end;

procedure TSlice.MarkDisconnect(clNo: Integer);
begin
  if (BIT_ISSET(clNo, @FReqackBm.readySet)) then begin
    //avoid counting client both as left and ready
    CLR_BIT(clNo, @FReqackBm.readySet);
    Dec(FNrReady);
  end;
  if (BIT_ISSET(clNo, @FAnsweredMap)) then begin
    Dec(FNrAnswered);
    CLR_BIT(clNo, @FAnsweredMap);
  end;
end;

procedure TSlice.MarkParticipantAnswered(clNo: Integer);
begin
  if BIT_ISSET(clNo, @FAnsweredMap) then //client already has answered
    Exit;

  Inc(FNrAnswered);
  SET_BIT(clNo, @FAnsweredMap);
end;

procedure TSlice.MarkRetransmit(clNo: Integer; map: PByteArray; rxmit: Integer);
var
  i                 : Integer;
begin
{$IFDEF DEBUG}
  flprintf('Mark retransmit Map %d@%d\n', FSliceNo, clNo);
{$ENDIF}
  if (rxmit < FRxmitId) then
  begin                                 //����� Reqack �ش�
{$IF False}
    flprintf('Late answer\n');
{$IFEND}
    Exit;
  end;

{$IFDEF DEBUG}
  logprintf(udpc_log,
    'Received retransmit request for slice %d from client %d\n',
    slice^.sliceNo, clNo);
{$ENDIF}
  for i := 0 to SizeOf(FRxmitMap) - 1 do
    FRxmitMap[i] := FRxmitMap[i] or not map[i];

  FNeedRxmit := True;
  MarkParticipantAnswered(clNo);
end;

function TSlice.IsReady(clNo: Integer): Boolean;
begin
  Result := BIT_ISSET(clNo, @FReqackBm.readySet)
end;

//------------------------------------------------------------------------------
//   { TDataPool }
//------------------------------------------------------------------------------


//ADR(x, bs)(fifo^.dataBuffer + (slice^.base + (x) * bs) mod fifo^.dataBufSize)

{$IFDEF BB_FEATURE_UDPCAST_FEC}

procedure fec_encode_all_stripes(sendst: PSenderState;
  slice: PSlice);
var
  i, j              : Integer;
  stripe            : Integer;
  config            : PNetConfig;
  fifo              : PFifo;
  bytes, stripes, redundancy, nrBlocks, leftOver: Integer;
  fec_data          : PAnsiChar;
  fec_blocks        : array of PAnsiChar;
  data_blocks       : array[0..127] of PAnsiChar;
  lastBlock         : PAnsiChar;
begin
  config := sendst^.config;
  fifo := sendst^.fifo;
  bytes := FBytes;
  stripes := FConfig^.fec_stripes;
  redundancy := FConfig^.fec_redundancy;
  nrBlocks := (bytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
  leftOver := bytes mod FConfig^.blockSize;
  fec_data := slice^.fec_data;

  SetLength(fec_blocks, redundancy);
  if (leftOver) then begin
    lastBlock := fifo^.dataBuffer + (slice^.base + (nrBlocks - 1)
      * FConfig^.blockSize) mod fifo^.dataBufSize;
    FillChar(lastBlock + leftOver, FConfig^.blockSize - leftOver, 0);
  end;

  for stripe := 0 to stripes - 1 do begin
    for i = : 0 to redundancy - 1 do
      fec_blocks[i] := fec_data + FConfig^.blockSize * (stripe + i * stripes);
    j := 0;
    i := stripe;
    while i < nrBlocks do begin
      data_blocks[j] = ADR(i, FConfig^.blockSize);
      Inc(i, stripes);
      Inc(j);
    end;
    fec_encode(FConfig^.blockSize, data_blocks, j, fec_blocks, redundancy);
  end;
end;

function fecMainThread(sendst: PSenderState): Integer;
var
  slice             : PSlice;
  sliceNo           : Integer;
begin
  sliceNo := 0;

  while True do begin
    { consume free slice }
    slice := makeSlice(sendst, sliceNo);
    Inc(sliceNo);
    { do the fec calculation here }
    fec_encode_all_stripes(sendst, slice);
    pc_produce(sendst^.fec_data_pc, 1);
  end;
  Result := 0;
end;
{$ENDIF}

constructor TDataPool.Create(Config: PNetConfig; Stats: ISenderStats);
begin
  FConfig := Config;
  FStats := Stats;
  inherited Create(True);
end;

destructor TDataPool.Destroy;
var
  i                 : Integer;
begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FFecThread.Destroy;
{$ENDIF}
  if Assigned(FDataPC) then
    FreeAndNil(FDataPC);
  if Assigned(FFreeMemPC) then
    FreeAndNil(FFreeMemPC);
  if Assigned(FFreeSlicesPC) then
    FreeAndNil(FFreeSlicesPC);
  FreeMemory(Pointer(FOrigFDataBuffer));
  FileClose(FFile);
  for i := 0 to NR_SLICES - 1 do
    FreeAndNil(FSlices[i]);
  inherited;
end;

procedure TDataPool.Terminate;
begin
  inherited;
  if Assigned(FFreeSlicesPC) then FFreeSlicesPC.MarkEnd;
  if Assigned(FreeMemPC) then FreeMemPC.MarkEnd;
  if Assigned(FDataPC) then FDataPC.MarkEnd;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if Boolean(FConfig^.flags and FLAG_FEC) then begin
    pthread_cancel(FFec_thread);
    pthread_join(FFec_thread, nil);
    pc_destoryProduconsum(FFec_data_pc);
    FreeMemory(FFec_data);
  end;
{$ENDIF}
  WaitFor;
end;

procedure TDataPool.InitData(Rc: TRChannel; USocket: TUDPSocket;
  Negotiate: INegotiate);
var
  i                 : Integer;
begin
  FFile := FileOpen(FConfig^.fileName, fmOpenRead or fmShareDenyNone);
  if FFile <= 0 then
    raise Exception.Create(FConfig^.fileName + ' �ļ��޷���');

  FDataBufSize := FConfig^.blockSize * DISK_BLOCK_SIZE; //��֤����/���Ķ�������
  FOrigFDataBuffer := DWORD_PTR(GetMemory(FDataBufSize + DISK_BLOCK_SIZE));
  FDataBuffer := FOrigFDataBuffer + DISK_BLOCK_SIZE -
    DWORD_PTR(FOrigFDataBuffer) mod DISK_BLOCK_SIZE;

  {* Free memory queue is initially full *}
  FFreeMemPC := TProduceConsum.Create(FDataBufSize, 'free mem');
  FFreeMemPC.Produce(FDataBufSize);

  FDataPC := TProduceConsum.Create(FDataBufSize, 'data');

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if Boolean(FConfig^.flags and FLAG_FEC) then
    FFecData := GetMemory(NR_SLICES *
      FConfig^.fec_stripes *
      FConfig^.fec_redundancy *
      FConfig^.blockSize);
{$ENDIF}

  FFreeSlicesPC := TProduceConsum.Create(NR_SLICES, 'free slices');
  FFreeSlicesPC.Produce(NR_SLICES);
  for i := 0 to NR_SLICES - 1 do
    FSlices[i] := TSlice.Create(FConfig, Self, Rc, USocket, Negotiate, FStats);

  if (FConfig^.default_slice_size = 0) then begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if Boolean(FConfig^.flags and FLAG_FEC) then
      FConfig^.sliceSize := FConfig^.fec_stripesize * FConfig^.fec_stripes
    else
{$ENDIF}
      if Boolean(FConfig^.flags and FLAG_ASYNC) then
        FConfig^.sliceSize := MAX_SLICE_SIZE
      else if Boolean(FConfig^.flags and FLAG_SN) then
        FConfig^.sliceSize := 112
      else
        FConfig^.sliceSize := 130;

    FConfig^.discovery := DSC_DOUBLING;
  end else begin
    FConfig^.sliceSize := FConfig^.default_slice_size;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if Boolean(FConfig^.flags and FLAG_FEC) and
      (FConfig^.sliceSize > 128 * FConfig^.fec_stripes) then
      FConfig^.sliceSize := 128 * FConfig^.fec_stripes;
{$ENDIF}
  end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if ((FConfig^.flags & FLAG_FEC) and
    FConfig^.max_slice_size > FConfig^.fec_stripes * 128)
    FConfig^.max_slice_size = FConfig^.fec_stripes * 128;
{$ENDIF}

  if (FConfig^.sliceSize > FConfig^.max_slice_size) then
    FConfig^.sliceSize := FConfig^.max_slice_size;

  assert(FConfig^.sliceSize <= MAX_SLICE_SIZE);

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if Boolean(FConfig^.flags and FLAG_FEC) then begin
    { Free memory queue is initially full }
    fec_init();
    FFecDataPC := TProduceConsum.Create(NR_SLICES, 'fec data');

    FFecThread := BeginThread(nil, 0, @fecMainThread, FConfig, 0, dwThID);
  end;
{$ENDIF}
end;

function TDataPool.MakeSlice(): TSlice;
var
  I, bytes          : Integer;
begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if Boolean(FConfig^.flags and FLAG_FEC) then begin
    FFecDataPC.Consume(1);
    i := FFecDataPC.GetConsumerPosition();
    Result := FSlices[i];
    FFecDataPC.Consumed(1);
  end else
{$ENDIF}
  begin
    FFreeSlicesPC.Consume(1);
    i := FFreeSlicesPC.GetConsumerPosition();
    Result := FSlices[i];
    FFreeSlicesPC.Consumed(1);
  end;

  assert(Result.State = SLICE_FREE);

  bytes := FDataPC.Consume(MIN_SLICE_SIZE * FConfig^.blockSize);
  { fixme: use current slice size here }
  if bytes > FConfig^.blockSize * FConfig^.sliceSize then
    bytes := FConfig^.blockSize * FConfig^.sliceSize;

  if bytes > FConfig^.blockSize then
    Dec(bytes, bytes mod FConfig^.blockSize);

  Result.Init(FSliceNo, FDataPC.GetConsumerPosition(),
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    sendst^.fec_data + (i * FConfig^.fec_stripes *
    FConfig^.fec_redundancy *
    FConfig^.blockSize),
{$ENDIF}bytes);

  FDataPC.Consumed(bytes);
  Inc(FSliceNo);

{$IFDEF 0}
  flprintf('Made slice %p %d\n', Result, sliceNo);
{$ENDIF}
end;

function TDataPool.FindSlice(Slice1, Slice2: TSlice; sliceNo: Integer): TSlice;
begin
  if (Slice1 <> nil) and (Slice1.SliceNo = sliceNo) then
    Result := Slice1
  else if (Slice2 <> nil) and (Slice2.SliceNo = sliceNo) then
    Result := Slice2
  else Result := nil;
end;

function TDataPool.FreeSlice(Slice: TSlice): Integer;
var
  pos               : Integer;
begin
  Result := 0;
{$IFDEF DEBUG}
  flprintf('Freeing slice %p %d %d\n', slice, Slice.SliceNo,
    slice - PChar(@FSlices));
{$ENDIF}
  Slice.State := SLICE_PRE_FREE;
  while True do
  begin
    pos := FFreeSlicesPC.GetProducerPosition();
    if FSlices[pos].State = SLICE_PRE_FREE then //��ֹFree����ʹ�õ�Slice
      FSlices[pos].State := SLICE_FREE
    else Break;
    FFreeSlicesPC.Produce(1);
  end;
end;

procedure TDataPool.Execute;
var
  Pos, bytes        : Integer;
begin
  bytes := 0;
  while True do
  begin
    pos := FFreeMemPC.GetConsumerPosition;
    bytes := FFreeMemPC.ConsumeContiguousMinAmount(DISK_BLOCK_SIZE);

    if Terminated then Break;

    if (bytes > (pos + bytes) mod DISK_BLOCK_SIZE) then
      Dec(bytes, (pos + bytes) mod DISK_BLOCK_SIZE);

    if (bytes = 0) then
      Break;                            //net writer exited?

    bytes := FileRead(FFile, PChar(FDataBuffer + pos)^, bytes);

    if (bytes < 0) then
      raise Exception.CreateFmt('read error!', [GetLastError])
    else if (bytes = 0) then
    begin
      FDataPC.MarkEnd;
      Break;
    end else
    begin
      FFreeMemPC.Consumed(bytes);
      FDataPC.Produce(bytes);
    end;
  end;
  ReturnValue := bytes;
end;

//------------------------------------------------------------------------------
//    { TRChannel }
//------------------------------------------------------------------------------

constructor TRChannel.Create(config: PNetConfig; USocket: TUDPSocket;
  Dp: TDataPool; Parts: TParticipants);
begin
  FDp := Dp;
  FConfig := config;
  FUSocket := USocket;
  FParts := Parts;

  FFreeSpacePC := TProduceConsum.Create(RC_MSG_QUEUE_SIZE, 'msg:free-queue');
  FFreeSpacePC.Produce(RC_MSG_QUEUE_SIZE);
  FIncomingPC := TProduceConsum.Create(RC_MSG_QUEUE_SIZE, 'msg:incoming');

  inherited Create(True);
end;

destructor TRChannel.Destroy;
begin
  FreeAndNil(FFreeSpacePC);
  FreeAndNil(FIncomingPC);
  inherited;
end;

procedure TRChannel.Terminate;
begin
  inherited;
  if Assigned(FFreeSpacePC) then FFreeSpacePC.MarkEnd;
  if Assigned(FIncomingPC) then FIncomingPC.MarkEnd;
  WaitFor;
end;

procedure TRChannel.HandleNextMessage(xmitSlice, rexmitSlice: TSlice);
var
  pos, clNo         : Integer;
  msg               : PCtrlMsg;
  Slice             : TSlice;
begin
  pos := FIncomingPC.GetConsumerPosition();
  msg := @FMsgQueue[pos].msg;
  clNo := FMsgQueue[pos].clNo;

{$IFDEF DEBUG}
  flprintf('handle next message\n');
{$ENDIF}

  FIncomingPC.ConsumeAny();
  case TOpCode(ntohs(msg^.opCode)) of
    CMD_OK:
      begin
        Slice := FDp.FindSlice(xmitSlice, rexmitSlice, ntohl(msg^.ok.sliceNo));
        if Slice <> nil then Slice.MarkOk(clNo);
      end;

    CMD_DISCONNECT:
      begin
        if Assigned(xmitSlice) then xmitSlice.MarkDisconnect(clNo);
        if Assigned(rexmitSlice) then rexmitSlice.MarkDisconnect(clNo);
        FParts.Remove(clNo);
      end;

    CMD_RETRANSMIT:
      begin
{$IFDEF DEBUG}
        flprintf('Received retransmittal request for %d from %d: \n',
          (long)xtohl(msg^.retransmit.sliceNo), clNo);
{$ENDIF}
        Slice := FDp.FindSlice(xmitSlice, rexmitSlice, ntohl(msg^.ok.sliceNo));
        if Slice <> nil then Slice.MarkRetransmit(clNo,
            @msg^.retransmit.map,
            msg^.retransmit.rxmit);
      end;
  else begin
{$IFDEF CONSOLE}
      WriteLn(Format('Bad command %-.4x', [msg^.opCode]));
{$ENDIF}
    end;
  end;
  FIncomingPC.Consumed(1);
  FFreeSpacePC.Produce(1);
end;

procedure TRChannel.Execute;
var
  pos, clNo         : Integer;
  addrFrom          : TSockAddrIn;
begin
  while True do
  begin
    pos := FFreeSpacePC.GetConsumerPosition();
    FFreeSpacePC.ConsumeAny();

    if Terminated then Break;

    ReturnValue := FUSocket.RecvCtrlMsg(FMsgQueue[pos].msg, addrFrom);
    if ReturnValue > 0 then begin
      clNo := FParts.Lookup(@addrFrom);
      if (clNo < 0) then                { packet from unknown provenance }
        Continue;

      FMsgQueue[pos].clNo := clNo;
      FFreeSpacePC.Consumed(1);
      FIncomingPC.Produce(1);
    end;
  end;
end;

//------------------------------------------------------------------------------
//    { TSender }
//------------------------------------------------------------------------------

constructor TSender.Create(Config: PNetConfig;
  Dp: TDataPool;
  Rc: TRChannel;
  Parts: TParticipants;
  Stats: ISenderStats);
begin
  FConfig := config;
  FDp := dp;
  FRc := rc;
  FParts := Parts;
  FStats := Stats;
  //inherited Create(True);
end;

destructor TSender.Destroy;
begin
  inherited;
end;

procedure TSender.Execute;
var
  i                 : Integer;
  atEnd             : Boolean;
  nrWaited          : Integer;
  tickStart, tickDiff: DWORD;           //�ȴ�������ʱ
  waitAvg, waitTime : DWORD;

  xmitSlice, rexmitSlice: TSlice;
label
  exit_main_loop;
begin
  atEnd := False;
  nrWaited := 0;
  waitAvg := 10 * 1000;                 // �ϴεȴ���ƽ����(��ʼ0.01s��֮�����)

  xmitSlice := nil;                     // Slice��һ�α�����
  rexmitSlice := nil;                   // Slice�ȴ�ȷ�ϻ��ش�

  { transmit the data }
  FStats.BeginTrans;
  while not FTerminated do
  begin
    if Boolean(FConfig^.flags and FLAG_ASYNC) then //ASYNC
    begin
      if (xmitSlice <> nil) then begin  // ֱ��ȷ�ϣ��ͷ�
        FDp.AckSlice(xmitSlice);
        xmitSlice := nil;
      end;
    end else begin
      if FParts.Count < 1 then          // û�г�Ա
        Break;

      if (rexmitSlice <> nil)
        and (rexmitSlice.NrReady >= FParts.Count) then
      begin                             // rexmitSliceƬȷ����ϣ��ͷ�
        FDp.AckSlice(rexmitSlice);
        rexmitSlice := nil;
      end;

      if (xmitSlice <> nil) and (rexmitSlice = nil)
        and (xmitSlice.State = SLICE_XMITTED) then
      begin                             // xmitSlice�Ѵ��䣬�ƶ���rexmitSlice��(�״�)����ȷ��
        rexmitSlice := xmitSlice;
        xmitSlice := nil;
        rexmitSlice.SendReqack();
      end;

      if FRc.FIncomingPC.GetProducedAmount > 0 then
      begin                             // ����ͻ�������Ϣ
        FRc.HandleNextMessage(xmitSlice, rexmitSlice);
        Continue;
      end;

      if (rexmitSlice <> nil) then begin
        if (rexmitSlice.NeedRxmit) then
        begin                           // �ش�
          FDp.NrContSlice := 0;         // ����Ƭ����0
          rexmitSlice.SendSlice(True);
        end
        else if (rexmitSlice.NrAnswered >= FParts.Count) then
          rexmitSlice.SendReqack();     // ��Ա���ش���,�����ش�Ƭ�Ƿ񵽴�
      end;
    end;                                // end NO_ASYNC

    if (xmitSlice = nil) and (not atEnd) then
    begin                               // ׼��xmitSlice
{$IFDEF DEBUG}
      flprintf('SN = %d\n', FConfig^.flags and FLAG_SN);
{$ENDIF}
      if Boolean(FConfig^.flags and FLAG_SN) or (rexmitSlice = nil) then
      begin
        xmitSlice := FDp.MakeSlice();
        if (xmitSlice.Bytes = 0) then
          atEnd := True;                // ����
      end;
    end;

    if (xmitSlice <> nil) and (xmitSlice.State = SLICE_NEW) then
    begin                               // ����xmitSlice (�п����Ǵ��������û������)
      xmitSlice.SendSlice(False);
{$IFDEF DEBUG}
      flprintf('%d Interrupted at %d / %d\n', xmitSlice^.sliceNo,
        xmitSlice^.nextBlock,
        getSliceBlocks(xmitSlice, config));
{$ENDIF}
      Continue;
    end;

    if atEnd and (rexmitSlice = nil) and (xmitSlice = nil) then
      Break;                            // ������Slice���Ѵ���

    // �ȴ�������Ϣ,ֱ����ʱ
{$IFDEF DEBUG}
    WiteLn('Waiting for timeout...');
{$ENDIF}
    tickStart := GetTickCountUSec();
    if (rexmitSlice.RxmitId > 10) then
      waitTime := waitAvg div 1000 + 1000 // ����1��
    else
      waitTime := waitAvg div 1000;

    //Writeln(#13, waitTime);
    if FRc.incomingPC.ConsumeAnyWithTimeout(waitTime) > 0 then
    begin                               // �з�����Ϣ
{$IFDEF DEBUG}
      flprintf('Have data\n');
{$ENDIF}
      // �������ܸ��µȴ�ʱ��
      tickDiff := DiffTickCount(tickStart, GetTickCountUSec());
      if (nrWaited > 0) then Inc(tickDiff, waitAvg);

      Inc(waitAvg, 9);
      waitAvg := Trunc(0.9 * waitAvg + 0.1 * tickDiff);

      nrWaited := 0;
      Continue;
    end
    else begin                          // ����Ƿ�ʱ������������ȷ��
      if (rexmitSlice <> nil) then begin
{$IFDEF DEBUG}
        if (nrWaited > 5) then begin
          Write('Timeout notAnswered map = ');
          printNotSet(rc^.participantsDb,
            @rexmitSlice^.answeredSet);
          Write(' notReady = ');
          printNotSet(rc^.participantsDb, @rexmitSlice^.sl_reqack.readySet);
          WriteLn(format(' nrAns = %d nrRead = %d nrPart = %d avg = %d',
            [rexmitSlice^.nrAnswered,
            rexmitSlice^.nrReady,
              nrParticipants(rc^.participantsDb),
              waitAvg]));
          nrWaited := 0;
        end;
{$ENDIF}
        Inc(nrWaited);
        if (rexmitSlice.RxmitId >= FConfig^.retriesUntilDrop) then
        begin                           //����Ƭ��ʱ
          for i := 0 to MAX_CLIENTS - 1 do
          begin
            if (not rexmitSlice.IsReady(i)) then
              if FParts.Remove(i) then begin //�Ƴ�������
{$IFDEF CONSOLE}
                WriteLn('Dropping client #', i, ' because of timeout');
{$ENDIF}
              end;
          end;
        end else
          rexmitSlice.SendReqack();     // �ط� Reqack
      end else
      begin                             //rexmitSlice = nil
{$IFDEF CONSOLE}
        Write('Weird. Timeout and no rxmit slice');
{$ENDIF}
        Break;
      end;
    end;                                // end wait

  end;                                  // end while

  exit_main_loop:                       // ��������
  FStats.EndTrans;
end;

end.

