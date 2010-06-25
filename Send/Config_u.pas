{    ע��ṹ��СҪ��udpcast.h�е�һ��!!!
}
unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  //���ܲ���
  DOUBLING_SETP     = 4;                //sliceSize ���� sliceSize div DOUBLING_SETP
  REDOUBLING_SETP   = 2;                //���lastGoodBlocksС��sliceSize div REDOUBLING_SETP����ôsliceSize�Ժ���Ϊ׼
  MIN_CONT_SLICE    = 5;                //��С����Ƭ�����ﵽ��תΪ����״̬

  //һ�㳣��
  MAX_CLIENTS       = 512;              //�������ͻ��ˣ�����Խ��Խ�ã�
  RC_MSG_QUEUE_SIZE = MAX_CLIENTS;      //������Ϣ���д�С
  DEFLT_STAT_PERIOD = 1000;             //״̬������� 1s

const
  MAX_GOVERNORS     = 10;

type
  TDmcFlag = (
    { "switched network" ��������(ȫ˫��): ������������Ƭ����ʼ������һƬǰ����һƬ�Ѿ�ȷ�ϣ�
    ��Ҫ���ھɵ�ͬ��������� }
    dmcFullDuplex,

    { "not switched network" mode: ��������֪�Ĳ��ɽ���(�޷��߷���ȷ��)! }
    dmcNotFullDuplex,

    { �첽ģʽ������Ҫ�ͻ���ȷ�ϡ�����û�лش��ŵ����õ������! }
    dmcAsyncMode,

    { �����㴫��ģʽ��ʹ�õ�����ʱ�������������������ֻ��һ����������}
    dmcPointToPoint,

    { Do automatic rate limitation by monitoring socket's send buffer
      size. Not very useful, as this still doesn't protect against the
      switch dropping packets because its queue (which might be slightly slower)
      overruns }
    //{$ifndef WINDOWS}
    // FLAG_AUTORATE =$0008;
    //{$ENDIF}

{$IFDEF BB_FEATURE_UDPCAST_FEC}
    { Forward Error Correction }
    dmcUseFec,                          // FLAG_FEC          = $0010;
{$ENDIF}

    { ʹ�ù㲥�����Ƕಥ����������֧�ֶಥʱ }
    dmcBCastMode,

    { ��ʹ�õ�Ե㣬����ֻ��һ�������� }
    dmcNoPointToPoint,

    { �ڷ��Ͷ˲�Ҫѯ�ʰ�����ʼ���� }
    dmcNoKeyBoard,

    { ��ģʽ���������������һ�����ڽ��еĴ��� }
    dmcStreamMode
    );
  TDmcFlags = set of TDmcFlag;

  TDiscovery = (
    DSC_DOUBLING,                       //���ӿ�
    DSC_REDUCING                        //���ٿ�
    );

  TNetConfig = packed record
    fileName: PAnsiChar;
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    blockSize: Integer;
    sliceSize: Integer;

    mcastRdv: PAnsiChar;
    ttl: Integer;
    nrGovernors: Integer;
    rateGovernor: array[0..MAX_GOVERNORS - 1] of Pointer; //struct rateGovernor_t *rateGovernor[MAX_GOVERNORS];
    rateGovernorData: array[0..MAX_GOVERNORS - 1] of Pointer;
    {int async;}
    {int pointopoint;}
    ref_tv: timeval;
    discovery: TDiscovery;              //enum sizeof=4
    { int autoRate; do queue watching using TIOCOUTQ, to avoid overruns }
    flags: TDmcFlags;                     { non-capability command line flags }
    capabilities: Integer;
    min_slice_size: Integer;
    default_slice_size: Integer;
    max_slice_size: Integer;
    rcvbuf: DWORD;                      //���ݲ�ͬ�ͻ��˻�������С��ȡ��С��
    rexmit_hello_interval: Integer; { retransmission interval between hello's.
    * If 0, hello message won't be retransmitted
    }
    autostart: Integer;                 { autostart after that many retransmits }
    requestedBufSize: Integer;          { requested receiver buffer }
    { sender-specific parameters }
    min_receivers: Integer;
    min_receivers_wait: Integer;        //���ն���������min_receivers�󣬵ȴ�ʱ��
    max_receivers_wait: Integer;        //���ȴ�ʱ��
    retriesUntilDrop: Integer;
    { receiver-specif parameters }
    exitWait: Integer;                  { How many milliseconds to wait on program exit }
    startTimeout: Integer;              { Timeout at start }
    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
    rehelloOffset: Integer;             { �����ٸ��飬����һ��hello }
  end;
  PNetConfig = ^TNetConfig;

implementation

end.

