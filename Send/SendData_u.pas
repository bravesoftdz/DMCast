{$INCLUDE def.inc}

unit SendData_u;

interface
uses
  Windows, Sysutils, Classes, WinSock, Func_u,
  Config_u, Protoc_u, IStats_u, Negotiate_u,
  Participants_u, Produconsum_u, Fifo_u, SockLib_u,
  HouLog_u;

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
  TReqackBm = packed record             //����ȷ��,�Ѿ�׼��Map
    ra: TReqack;
    readySet: TClientsMap;              { who is already ok? }
  end;

  TSlice = class
  private
    FIndex: Integer;                    //In Dp.Slices Index
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
    FFecData: PAnsiChar;
{$ENDIF}

    { ���� }
    FFifo: TFifo;
    FRc: TRChannel;
    FDp: TDataPool;
    FConfig: PSendConfig;
    FUSocket: TUDPSenderSocket;
    FNego: TNegotiate;
    FStats: ISenderStats;
  private
    function SendRawData(header: PAnsiChar; headerSize: Integer;
      data: PAnsiChar; dataSize: Integer): Integer;
    function TransmitDataBlock(i: Integer): Integer;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    function TransmitFecBlock(i: Integer): Integer;
{$ENDIF}
  public
    constructor Create(Index: Integer;
      Fifo: TFifo;
      Rc: TRChannel;
      Dp: TDataPool;
      Nego: TNegotiate);
    destructor Destroy; override;
    procedure Init(sliceNo: Integer; base: DWORD_PTR;
{$IFDEF BB_FEATURE_UDPCAST_FEC}fecData: PAnsiChar; {$ENDIF}bytes: Integer);
    function GetBlocks(): Integer;

    function Send(isRetrans: Boolean): Integer;
    function Reqack(): Integer;

    procedure MarkOk(clNo: Integer);
    procedure MarkDisconnect(clNo: Integer);
    procedure MarkParticipantAnswered(clNo: Integer);
    procedure MarkRetransmit(clNo: Integer; map: PByteArray; rxmit: Integer);
    function IsReady(clNo: Integer): Boolean;
  public
    property Index: Integer read FIndex;
    property State: TSliceState read FState write FState;
    property SliceNo: Integer read FSliceNo;
    property Bytes: Integer read FBytes;
    property NextBlock: Integer read FNextBlock; { index of next buffer to be transmitted }
    property NrReady: Integer read FNrReady;
    property NeedRxmit: Boolean read FNeedRxmit;
    property NrAnswered: Integer read FNrAnswered;
    property RxmitId: Integer read FRxmitId write FRxmitId;
  end;

  TDataPool = class(TObject)            //���ݷ�Ƭ�����
  private
    { ���ڰ�˫��ģʽ��̬����SliceSize }
    FNrContSlice: Integer;              //�����ɹ�Ƭ���������ж��Ƿ�Ҫ����Ƭ��С
    FDiscovery: TDiscovery;

    FSliceSize: Integer;
    FSliceIndex: Integer;
    FSlices: array[0..NR_SLICES - 1] of TSlice;
    FFreeSlicesPC: TProduceConsum;      //����Ƭ
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFecData: PAnsiChar;
    FFecThread: THandle;
    FFecDataPC: TProduceConsum;
{$ENDIF}

    { ���� }
    FFifo: TFifo;
    FConfig: PSendConfig;
    FStats: ISenderStats;
    FNego: TNegotiate;
  public
    constructor Create(Nego: TNegotiate);
    destructor Destroy; override;
    procedure InitSlice(Fifo: TFifo; Rc: TRChannel); //��ʼ����
    procedure Close;

    function MakeSlice(): TSlice;       //׼������Ƭ
    function AckSlice(Slice: TSlice): Integer; //ȷ��Ƭ���ɹ�����>=0
    function FreeSlice(Slice: TSlice): Integer;
    function FindSlice(Slice1, Slice2: TSlice; sliceNo: Integer): TSlice;
  public
    property NrContSlice: Integer read FNrContSlice write FNrContSlice;
    property Discovery: TDiscovery read FDiscovery write FDiscovery;
    property SliceSize: Integer read FSliceSize write FSliceSize;
  end;

  TCtrlMsgQueue = packed record
    clNo: Integer;                      //�ͻ���ţ�������
    msg: TCtrlMsg;                      //������Ϣ
  end;

  TRChannel = class(TThread)            //�ͻ�����Ϣ�������Thread
  private
    FUSocket: TUDPSenderSocket;         { socket on which we receive the messages }

    FIncomingPC: TProduceConsum;        { where to enqueue incoming messages }
    FFreeSpacePC: TProduceConsum;       { free space }
    FMsgQueue: array[0..RC_MSG_QUEUE_SIZE - 1] of TCtrlMsgQueue; //��Ϣ����

    { ���� }
    FDp: TDataPool;
    FNego: TNegotiate;
    FConfig: PSendConfig;
    FParts: TParticipants;
  public
    constructor Create(Nego: TNegotiate; Dp: TDataPool);
    destructor Destroy; override;
    procedure Terminate; overload;
    procedure HandleNextMessage(xmitSlice, rexmitSlice: TSlice); //��������Ϣ�����е���Ϣ
  protected
    procedure Execute; override;        //ѭ�����տͻ��˷�����Ϣ����������
  public
    property IncomingPC: TProduceConsum read FIncomingPC;
  end;

  TSender = class                       //(TThread)   //���ݷ��͡�����Э��
  private
    FTerminated: Boolean;               //��ֹ����

    { ���� }
    FDp: TDataPool;
    FRc: TRChannel;
    FNego: TNegotiate;
    FConfig: PSendConfig;
    FParts: TParticipants;
  public
    constructor Create(Nego: TNegotiate;
      Dp: TDataPool;
      Rc: TRChannel);
    destructor Destroy; override;

    procedure Execute;                  //override;    //ѭ�����ͺʹ���ͻ��˷�����Ϣ
  public
    property Terminated: Boolean read FTerminated write FTerminated;
  end;

implementation

{ TSlice }

constructor TSlice.Create;
begin
  FIndex := Index;
  FState := SLICE_FREE;

  FFifo := Fifo;
  FRc := Rc;
  FDp := Dp;
  FNego := Nego;
  FUSocket := Nego.USocket;
  FConfig := Nego.Config;
  FStats := Nego.Stats;
end;

destructor TSlice.Destroy;
begin
  inherited;
end;

function TSlice.GetBlocks: Integer;
begin
  Result := (FBytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
end;

procedure TSlice.Init(sliceNo: Integer; base: DWORD_PTR;
{$IFDEF BB_FEATURE_UDPCAST_FEC}fecData: PAnsiChar; {$ENDIF}bytes: Integer);
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

function TSlice.Reqack(): Integer;
var
  nrBlocks          : Integer;
begin
  Inc(FRxmitId);

  //����ȫ˫��ģʽ�Ҳ��ǵ�һ���ش�����ȷ��
  if not (dmcFullDuplex in FConfig^.flags) and (FRxmitId <> 0) then
  begin
    nrBlocks := GetBlocks();
{$IFDEF DEBUG}
    Writeln(Format('nrBlocks=%d lastGoodBlocks=%d', [nrBlocks, FLastGoodBlocks]));
{$ENDIF}
    //�����ǰ���������ϴγɹ��Ŀ�������СƬ��С
    if (FLastGoodBlocks <> 0) and (FLastGoodBlocks < nrBlocks) then
    begin
      FDp.Discovery := DSC_REDUCING;
      if (FLastGoodBlocks < FDp.SliceSize div REDOUBLING_SETP) then
        FDp.SliceSize := FDp.SliceSize div REDOUBLING_SETP
      else
        FDp.SliceSize := FLastGoodBlocks;

      if (FDp.SliceSize < MIN_SLICE_SIZE) then
        FDp.SliceSize := MIN_SLICE_SIZE;
{$IFDEF DMC_DEBUG_ON}
      OutLog2(llDebug, Format('Slice size^.%d', [FDp.SliceSize]));
{$ENDIF}
    end;
  end;

  FLastGoodBlocks := 0;
{$IFDEF DEBUG}
  writeln(Format('Send reqack %d.%d', [FSliceNo, slice^.rxmitId]));
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
  writeln('sending reqack for slice ', FSliceNo);
{$ENDIF}
  //BCAST_DATA(sock, FReqackBm);
  {��������}
  Result := FUSocket.SendCtrlMsg(FReqackBm, SizeOf(FReqackBm));
end;

function TSlice.Send(isRetrans: Boolean): Integer;
var
  nrBlocks, i, rehello: integer;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  fecBlocks         : Integer;
{$ENDIF}
  nrRetrans         : Integer;
begin
  Result := 0;
  nrRetrans := 0;

  if isRetrans then
  begin
    FNextBlock := 0;
    if (FState <> SLICE_XMITTED) then
      Exit;
  end
  else if (FState <> SLICE_NEW) then
    Exit;

  nrBlocks := GetBlocks();
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) and not isRetrans then
    fecBlocks := FConfig^.fec_redundancy * FConfig^.fec_stripes
  else
    fecBlocks := 0;
{$ENDIF}

{$IFDEF DEBUG}
  if isRetrans then
  begin
    writeln(Format('Retransmitting:%s slice %d from %d to %d (%d bytes) %d',
      [BoolToStr(isRetrans), FSliceNo, slice^.nextBlock, nrBlocks, FBytes,
      FConfig^.blockSize]));
  end;
{$ENDIF}

  if dmcStreamMode in FConfig^.flags then
  begin
    rehello := nrBlocks - FConfig^.rehelloOffset;
    if rehello < 0 then
      rehello := 0
  end
  else
    rehello := -1;

  { transmit the data }

  for i := FNextBlock to nrBlocks
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  + fecBlocks
{$ENDIF} - 1 do
  begin
    if isRetrans then
    begin
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
      writeln(Format('Retransmitting %d.%d', [FSliceNo, i]));
{$ENDIF}
    end;

    if (i = rehello) then
      FNego.SendHello(True);            //��ģʽ

    if i < nrBlocks then
      TransmitDataBlock(i)
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    else
      TransmitFecBlock(i - nrBlocks)
{$ENDIF};
    if not isRetrans and (FRc.FIncomingPC.GetProducedAmount > 0) then
      Break;                            //�����ʱ���з�����Ϣ(һ��Ϊ��Ҫ�ش�)������ֹ���䣬����
  end;                                  //end while

  if nrRetrans > 0 then
    FStats.AddRetrans(nrRetrans);       //����״̬

  if i <> nrBlocks
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  + fecBlocks
{$ENDIF} then
  begin
    FNextBlock := i                     //����Ƭû�д����꣬��ס�´�Ҫ�����λ��
  end
  else
  begin
    FNeedRxmit := False;
    if not LongBool(isRetrans) then
      FState := SLICE_XMITTED;

{$IFDEF DEBUG}
    writeln(Format('Done: at block %d %d %d',
      [i, isRetrans, FState]));
{$ENDIF}
    Result := 2;
    Exit;
  end;
{$IFDEF DEBUG}
  writeln(Format('Done: at block %d %d %d',
    [i, isRetrans, FState]));
{$ENDIF}
  Result := 1;
end;

function TSlice.SendRawData(header: PAnsiChar; headerSize: Integer;
  data: PAnsiChar; dataSize: Integer): Integer;
var
  msg               : TNetMsg;
begin
  msg.head.base := header;
  msg.head.len := headerSize;
  msg.data.base := data;
  msg.data.len := dataSize;

  ////rgWaitAll(config, sock, FUSocket.CastAddr.sin_addr.s_addr, dataSize + headerSize);
  Result := FUSocket.SendDataMsg(msg);
{$IFDEF DMC_ERROR_ON}
  if Result < 0 then
  begin
    OutLog2(llError, Format('(%d) Could not broadcast data packet to %s:%d',
      [GetLastError, inet_ntoa(FUSocket.DataAddr.sin_addr),
      ntohs(FUSocket.DataAddr.sin_port)]));
  end;
{$ENDIF}
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
    FFifo.GetDataBuffer(FBase + i * FConfig^.blockSize), size);
end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}

function TSlice.TransmitFecBlock(int i): Integer;
var
  config            : PSendConfig;
  msg               : fecBlock;
begin
  Result := 0;
  config := sendst^.config;

  { Do not transmit zero byte FEC blocks if we are not in async mode }
  if (FBytes = 0) and not (dmcAsyncMode in FConfig^.flags)) then
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
  if (BIT_ISSET(clNo, @FReqackBm.readySet)) then
  begin
    { client is already marked ready }
{$IFDEF DEBUG}
    writeln(Format('client %d is already ready', [clNo]));
{$ENDIF}
  end
  else
  begin
    SET_BIT(clNo, @FReqackBm.readySet);
    Inc(FNrReady);
{$IFDEF DEBUG}
    writeln(Format('client %d replied ok for %p %d ready = %d',
      [clNo, @Self, FSliceNo, FNrReady]));
{$ENDIF}
    MarkParticipantAnswered(clNo);
  end;
end;

procedure TSlice.MarkDisconnect(clNo: Integer);
begin
  if (BIT_ISSET(clNo, @FReqackBm.readySet)) then
  begin
    //avoid counting client both as left and ready
    CLR_BIT(clNo, @FReqackBm.readySet);
    Dec(FNrReady);
  end;
  if (BIT_ISSET(clNo, @FAnsweredMap)) then
  begin
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
  writeln(Format('Mark retransmit Map %d@%d', [FSliceNo, clNo]));
{$ENDIF}
  if (rxmit < FRxmitId) then
  begin                                 //����� Reqack �ش�
{$IF False}
    writeln('Late answer');
{$IFEND}
    Exit;
  end;

{$IFDEF DEBUG}
  writeln(Format('Received retransmit request for slice %d from client %d',
    [Slice^.sliceNo, clNo]);
{$ENDIF}
    //or ������������ش�BlocksMap
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

{$IFDEF BB_FEATURE_UDPCAST_FEC}

procedure fec_encode_all_stripes(sendst: PSenderState;
  slice: PSlice);
var
  i, j              : Integer;
  stripe            : Integer;
  config            : PSendConfig;
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
  if (leftOver) then
  begin
    lastBlock := fifo^.dataBuffer + (slice^.base + (nrBlocks - 1)
      * FConfig^.blockSize) mod fifo^.dataBufSize;
    FillChar(lastBlock + leftOver, FConfig^.blockSize - leftOver, 0);
  end;

  for stripe := 0 to stripes - 1 do
  begin
    for i = : 0 to redundancy - 1 do
      fec_blocks[i] := fec_data + FConfig^.blockSize * (stripe + i * stripes);
    j := 0;
    i := stripe;
    while i < nrBlocks do
    begin
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

  while True do
  begin
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

constructor TDataPool.Create;
begin
  FNego := Nego;
  FConfig := Nego.Config;
  FStats := Nego.Stats;
end;

destructor TDataPool.Destroy;
var
  i                 : Integer;
begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FFecThread.Destroy;
{$ENDIF}
  if Assigned(FFreeSlicesPC) then
    FreeAndNil(FFreeSlicesPC);
  for i := 0 to NR_SLICES - 1 do
    FreeAndNil(FSlices[i]);
  inherited;
end;

procedure TDataPool.InitSlice;
var
  i                 : Integer;
begin
  FFifo := Fifo;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
    FFecData := GetMemory(NR_SLICES *
      FConfig^.fec_stripes *
      FConfig^.fec_redundancy *
      FConfig^.blockSize);
{$ENDIF}

  FFreeSlicesPC := TProduceConsum.Create(NR_SLICES, 'free slices');
  FFreeSlicesPC.Produce(NR_SLICES);
  for i := 0 to NR_SLICES - 1 do        //׼��Ƭ
    FSlices[i] := TSlice.Create(i, Fifo, Rc, Self, FNego);

  if (FConfig^.default_slice_size = 0) then
  begin                                 //����������ú��ʵ�Ƭ��С
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if LongBool(FConfig^.flags and FLAG_FEC) then
      FSliceSize := FConfig^.fec_stripesize * FConfig^.fec_stripes
    else
{$ENDIF}if dmcAsyncMode in FConfig^.flags then
        FSliceSize := MAX_SLICE_SIZE
      else if dmcFullDuplex in FConfig^.flags then
        FSliceSize := 112
      else
        FSliceSize := 130;

    FDiscovery := DSC_DOUBLING;
  end
  else
  begin
    FSliceSize := FConfig^.default_slice_size;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if LongBool(FConfig^.flags and FLAG_FEC) and
      (FDp.SliceSize > 128 * FConfig^.fec_stripes) then
      FDp.SliceSize := 128 * FConfig^.fec_stripes;
{$ENDIF}
  end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if ((FConfig^.flags & FLAG_FEC) and
    FConfig^.max_slice_size > FConfig^.fec_stripes * 128)
    FConfig^.max_slice_size = FConfig^.fec_stripes * 128;
{$ENDIF}

  if (FSliceSize > FConfig^.max_slice_size) then
    FSliceSize := FConfig^.max_slice_size;

  assert(FSliceSize <= MAX_SLICE_SIZE);

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    { Free memory queue is initially full }
    fec_init();
    FFecDataPC := TProduceConsum.Create(NR_SLICES, 'fec data');

    FFecThread := BeginThread(nil, 0, @fecMainThread, FConfig, 0, dwThID);
  end;
{$ENDIF}
end;

procedure TDataPool.Close;
begin
  if Assigned(FFreeSlicesPC) then
    FFreeSlicesPC.MarkEnd;

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    pthread_cancel(FFec_thread);
    pthread_join(FFec_thread, nil);
    pc_destoryProduconsum(FFec_data_pc);
    FreeMemory(FFec_data);
  end;
{$ENDIF}
end;

function TDataPool.MakeSlice(): TSlice;
var
  I, bytes          : Integer;
begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    FFecDataPC.Consume(1);
    i := FFecDataPC.GetConsumerPosition();
    Result := FSlices[i];
    FFecDataPC.Consumed(1);
  end
  else
{$ENDIF}
  begin
    FFreeSlicesPC.Consume(1);
    i := FFreeSlicesPC.GetConsumerPosition();
    Result := FSlices[i];
    FFreeSlicesPC.Consumed(1);
  end;

  assert(Result.State = SLICE_FREE);

  bytes := FFifo.DataPC.Consume(MIN_SLICE_SIZE * FConfig^.blockSize);
  { fixme: use current slice size here }
  if bytes > FConfig^.blockSize * FSliceSize then
    bytes := FConfig^.blockSize * FSliceSize;

  if bytes > FConfig^.blockSize then
    Dec(bytes, bytes mod FConfig^.blockSize);

  Result.Init(FSliceIndex, FFifo.DataPC.GetConsumerPosition(),
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    sendst^.fec_data + (i * FConfig^.fec_stripes *
    FConfig^.fec_redundancy *
    FConfig^.blockSize),
{$ENDIF}bytes);

  FFifo.DataPC.Consumed(bytes);
  Inc(FSliceIndex);

{$IFDEF 0}
  writeln(Format('Made slice %p %d', [@Result, sliceNo]));
{$ENDIF}
end;

function TDataPool.AckSlice(Slice: TSlice): Integer;
begin
  if not (dmcFullDuplex in FConfig^.flags) //��ȫ˫��ģʽ���б�Ҫ��̬����Ƭ��С
  and (FSliceSize < FConfig^.max_slice_size) then //������
    if (FDiscovery = DSC_DOUBLING) then
    begin                               //����Ƭ��С
      Inc(FSliceSize, FSliceSize div DOUBLING_SETP);

      if (FSliceSize >= FConfig^.max_slice_size) then
      begin
        FSliceSize := FConfig^.max_slice_size;
        FDiscovery := DSC_REDUCING;
      end;

{$IFDEF DMC_DEBUG_ON}
      OutLog2(llDebug, Format('Doubling slice size to %d', [FSliceSize]));
{$ENDIF}
    end
    else
    begin                               //�ɹ�Ƭ����
      if FNrContSlice >= MIN_CONT_SLICE then
      begin
        FDiscovery := DSC_DOUBLING;
        FNrContSlice := 0;
      end
      else
        Inc(FNrContSlice);
    end;

  Result := Slice.Bytes;
  FFifo.FreeMemPC.Produce(Result);
  FreeSlice(Slice);                     //�ͷ�Ƭ

  FStats.AddBytes(Result);              //����״̬
end;

function TDataPool.FindSlice(Slice1, Slice2: TSlice; sliceNo: Integer): TSlice;
begin
  if (Slice1 <> nil) and (Slice1.SliceNo = sliceNo) then
    Result := Slice1
  else if (Slice2 <> nil) and (Slice2.SliceNo = sliceNo) then
    Result := Slice2
  else
    Result := nil;
end;

function TDataPool.FreeSlice(Slice: TSlice): Integer;
var
  pos               : Integer;
begin
  Result := 0;
{$IFDEF DEBUG}
  Writeln(format('Freeing slice %p %d %d',
    [@Slice, Slice.SliceNo, Slice.Index]));
{$ENDIF}
  Slice.State := SLICE_PRE_FREE;
  while True do
  begin
    pos := FFreeSlicesPC.GetProducerPosition();
    if FSlices[pos].State = SLICE_PRE_FREE then //��ֹFree����ʹ�õ�Slice
      FSlices[pos].State := SLICE_FREE
    else
      Break;
    FFreeSlicesPC.Produce(1);
  end;
end;

//------------------------------------------------------------------------------
//    { TRChannel }
//------------------------------------------------------------------------------

constructor TRChannel.Create;
begin
  FDp := Dp;
  FNego := Nego;
  FConfig := Nego.Config;
  FUSocket := Nego.USocket;
  FParts := Nego.Parts;

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
  if Assigned(FFreeSpacePC) then
    FFreeSpacePC.MarkEnd;
  if Assigned(FIncomingPC) then
    FIncomingPC.MarkEnd;
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
  Writeln('handle next message');
{$ENDIF}

  FIncomingPC.ConsumeAny();
  case TOpCode(ntohs(msg^.opCode)) of
    CMD_OK:
      begin
        Slice := FDp.FindSlice(xmitSlice, rexmitSlice, ntohl(msg^.ok.sliceNo));
        if Slice <> nil then
          Slice.MarkOk(clNo);
      end;

    CMD_DISCONNECT:
      begin
        if Assigned(xmitSlice) then
          xmitSlice.MarkDisconnect(clNo);
        if Assigned(rexmitSlice) then
          rexmitSlice.MarkDisconnect(clNo);
        FParts.Remove(clNo);
      end;

    CMD_RETRANSMIT:
      begin
{$IFDEF DEBUG}
        WriteLn(Format('Received retransmittal request for %d from %d: ',
          [ntohl(msg^.retransmit.sliceNo), clNo]));
{$ENDIF}
        Slice := FDp.FindSlice(xmitSlice, rexmitSlice, ntohl(msg^.retransmit.sliceNo));
        if Slice <> nil then
          Slice.MarkRetransmit(clNo,
            @msg^.retransmit.map,
            msg^.retransmit.rxmit);
      end;
  else
    begin
{$IFDEF DMC_WARN_ON}
      OutLog2(llWarn, Format('Bad command %-.4x', [ntohs(msg^.opCode)]));
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

    if Terminated then
      Break;

    ReturnValue := FUSocket.RecvCtrlMsg(FMsgQueue[pos].msg,
      SizeOf(FMsgQueue[pos].msg), addrFrom);

    if ReturnValue > 0 then
    begin
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

constructor TSender.Create;
begin
  FNego := Nego;
  FConfig := Nego.Config;
  FDp := Dp;
  FRc := Rc;
  FParts := Nego.Parts;
  //inherited Create(True);
end;

destructor TSender.Destroy;
begin
  FTerminated := True;
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
begin
  atEnd := False;
  nrWaited := 0;
  waitAvg := 10 * 1000;                 // �ϴεȴ���ƽ����(��ʼ0.01s��֮�����)

  xmitSlice := nil;                     // Slice��һ�α�����
  rexmitSlice := nil;                   // Slice�ȴ�ȷ�ϻ��ش�

  { transmit the data }
  FNego.TransState := tsTransing;
  while not FTerminated do
  begin
    if dmcAsyncMode in FConfig^.flags then //ASYNC
    begin
      if (xmitSlice <> nil) then
      begin                             // ֱ��ȷ�ϣ��ͷ�
        FDp.AckSlice(xmitSlice);
        xmitSlice := nil;
      end;
    end
    else
    begin
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
        rexmitSlice.Reqack();
      end;

      if FRc.FIncomingPC.GetProducedAmount > 0 then
      begin                             // ����ͻ�������Ϣ
        FRc.HandleNextMessage(xmitSlice, rexmitSlice);
        Continue;
      end;

      if (rexmitSlice <> nil) then
      begin
        if (rexmitSlice.NeedRxmit) then
        begin                           // �ش�
          FDp.NrContSlice := 0;         // ����Ƭ����0
          rexmitSlice.Send(True);
        end
        else if (rexmitSlice.NrAnswered >= FParts.Count) then
          rexmitSlice.Reqack();         // ��Ա���ش���,�����ش�Ƭ�Ƿ񵽴�
      end;
    end;                                // end NO_ASYNC

    if (xmitSlice = nil) and (not atEnd) then
    begin                               // ׼��xmitSlice
{$IFDEF DEBUG}
      Writeln(Format('SN = %d', [dmcFullDuplex in FConfig^.flags]));
{$ENDIF}
      if (dmcFullDuplex in FConfig^.flags) or (rexmitSlice = nil) then
      begin                             //ȫ˫�� �� ��һƬ�Ѿ�ȷ��
        xmitSlice := FDp.MakeSlice();
        if (xmitSlice.Bytes = 0) then
          atEnd := True;                // ����
      end;
    end;

    if (xmitSlice <> nil) and (xmitSlice.State = SLICE_NEW) then
    begin                               // ����xmitSlice (�п����Ǵ��������û������)
      xmitSlice.Send(False);
{$IFDEF DEBUG}
      Writeln(Format('%d Interrupted at %d / %d', xmitSlice^.sliceNo,
        [xmitSlice^.nextBlock, getSliceBlocks(xmitSlice, config)]));
{$ENDIF}
      Continue;
    end;

    if atEnd and (rexmitSlice = nil) and (xmitSlice = nil) then
      Break;                            // ������Slice���ѳɹ�����

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
    if FRc.IncomingPC.ConsumeAnyWithTimeout(waitTime) > 0 then
    begin                               // �з�����Ϣ
{$IFDEF DEBUG}
      Writeln('Have data');
{$ENDIF}
      // �������ܸ��µȴ�ʱ��
      tickDiff := DiffTickCount(tickStart, GetTickCountUSec());
      if (nrWaited > 0) then
        Inc(tickDiff, waitAvg);

      Inc(waitAvg, 9);
      waitAvg := Trunc(0.9 * waitAvg + 0.1 * tickDiff);

      nrWaited := 0;
      Continue;
    end
    else
    begin                               // ����Ƿ�ʱ������������ȷ��
      if (rexmitSlice <> nil) then
      begin
{$IFDEF DEBUG}
        if (nrWaited > 5) then
        begin
          Write('Timeout notAnswered map = ');
          printNotSet(rc^.participantsDb,
            @rexmitSlice^.answeredSet);
          Write(' notReady = ');
          printNotSet(rc^.participantsDb, @rexmitSlice^.sl_reqack.readySet);
          WriteLn(format(' nrAns = %d nrRead = %d nrPart = %d avg = %d',
            [rexmitSlice^.nrAnswered, rexmitSlice^.nrReady,
            nrParticipants(rc^.participantsDb), waitAvg]));
          nrWaited := 0;
        end;
{$ENDIF}
        Inc(nrWaited);
        if (rexmitSlice.RxmitId >= FConfig^.retriesUntilDrop) then
        begin                           //����Ƭ��ʱ
          for i := 0 to MAX_CLIENTS - 1 do
          begin
            if (not rexmitSlice.IsReady(i)) then
              if FParts.Remove(i) then
              begin                     //�Ƴ�������
{$IFDEF DMC_MSG_ON}
                OutLog2(llMsg, 'Dropping client #' + IntToStr(i) + ' because of timeout');
{$ENDIF}
              end;
          end;
        end
        else
          rexmitSlice.Reqack();         // �ط� Reqack
      end
      else
      begin                             //rexmitSlice = nil ����֣�^_^!
{$IFDEF DMC_FATAL_ON}
        OutLog2(llFatal, 'Weird. Timeout and no rxmit slice');
{$ENDIF}
        Break;
      end;
    end;                                // end wait
  end;                                  // end while

{$IFDEF DMC_MSG_ON}
  OutLog2(llMsg, 'Transfer complete.');
{$ENDIF}
  FNego.TransState := tsComplete;       // ��������
end;

end.

