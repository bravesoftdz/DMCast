{    ע��ṹ��СҪ��udpcast.h�е�һ��!!!
}
unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  //�˿�Offset
  S_PORT_OFFSET     = 1;                //Sender
  R_PORT_OFFSET     = 0;                //Receiver

  //���ܲ���
  DOUBLING_SETP     = 4;                //sliceSize ���� sliceSize div DOUBLING_SETP
  REDOUBLING_SETP   = 2;                //���lastGoodBlocksС��sliceSize div REDOUBLING_SETP����ôsliceSize�Ժ���Ϊ׼
  MIN_CONT_SLICE    = 5;                //��С����Ƭ�����ﵽ��תΪ����״̬

  MIN_SLICE_SIZE    = 32;               //�Զ�����Ƭ��Сʱ����С�޶�
  MAX_SLICE_SIZE    = 1024;             //���Ƭ��С,���10K���ң���MAX_SLICE_SIZE div BITS_PER_CHAR +Header(8)<1472
  MAX_BLOCK_SIZE    = 1456;             //����ʱ1472������16�ֽ�ͷ

  DISK_BLOCK_SIZE   = 4096;             //����������С��λ�����Ϊ blockSize * DISK_BLOCK_SIZE
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  MAX_FEC_INTERLEAVE = 256;
{$ENDIF}

  //һ�㳣��
  MAX_CLIENTS       = 512;              //�������ͻ��ˣ�����Խ��Խ�ã�
  RC_MSG_QUEUE_SIZE = MAX_CLIENTS;      //������Ϣ���д�С
  DEFLT_STAT_PERIOD = 1000;             //״̬������� 1s

  //�̶�����
  BITS_PER_CHAR     = 8;
  BITS_PER_INT      = SizeOf(Integer) * 8;
const
  { "switched network" ��������(ȫ˫��): ������׼����ʼ������һ����Ƭ֮ǰ����ȷ����һƬ��
    ��Ҫ���ھɵ�ͬ��������� }
  FLAG_SN           = $0001;

  { "not switched network" mode: ��������֪�Ĳ��ɽ���(�޷�ȷ��)! }
  FLAG_NOTSN        = $0002;

  { �첽ģʽ������Ҫ�ͻ���ȷ�ϡ�����û�лش��ŵ����õ������! }
  FLAG_ASYNC        = $0004;

  { �����㴫��ģʽ��ʹ�õ�����ʱ�������������������ֻ��һ����������}
  FLAG_POINTOPOINT  = $0008;

  { Do automatic rate limitation by monitoring socket's send buffer
    size. Not very useful, as this still doesn't protect against the
    switch dropping packets because its queue (which might be slightly slower)
    overruns }
  //{$ifndef WINDOWS}
  // FLAG_AUTORATE =$0008;
  //{$ENDIF}

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  { Forward Error Correction }
  FLAG_FEC          = $0010;
{$ENDIF}

  { ʹ�ù㲥�����Ƕಥ����������֧�ֶಥʱ }
  FLAG_BCAST        = $0020;

  { ��ʹ�õ�Ե㣬����ֻ��һ�������� }
  FLAG_NOPOINTOPOINT = $0040;

  { �ڷ��Ͷ˲�Ҫѯ�ʰ�����ʼ���� }
  FLAG_NOKBD        = $0080;

  { ��ģʽ���������������һ�����ڽ��еĴ��� }
  FLAG_STREAMING    = $0100;

const
  MAX_GOVERNORS     = 10;

type
  TDiscovery = (
    DSC_DOUBLING,                       //���ӿ�
    DSC_REDUCING                        //���ٿ�
    );

  TNetConfig = packed record            //sizeof=216
    ifName: PChar;                      //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    fileName: PChar;
    portBase: Integer;                  //Port base

    blockSize: Integer;
    sliceSize: Integer;

    mcastRdv: PChar;
    ttl: Integer;
    nrGovernors: Integer;
    rateGovernor: array[0..MAX_GOVERNORS - 1] of Pointer; //struct rateGovernor_t *rateGovernor[MAX_GOVERNORS];
    rateGovernorData: array[0..MAX_GOVERNORS - 1] of Pointer;
    {int async;}
    {int pointopoint;}
    ref_tv: timeval;
    discovery: TDiscovery;              //enum sizeof=4
    { int autoRate; do queue watching using TIOCOUTQ, to avoid overruns }
    flags: Integer;                     { non-capability command line flags }
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
    max_receivers_wait: Integer;
    min_receivers_wait: Integer;
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

