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

    { ��ģʽ���������������һ�����ڽ��еĴ��� }
    dmcStreamMode
    );
  TDmcFlags = set of TDmcFlag;

  TDiscovery = (
    DSC_DOUBLING,                       //���ӿ�
    DSC_REDUCING                        //���ٿ�
    );

  TNetConfig = packed record            //sizeof=216
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    //�����鲥�Ự/����
    mcastRdv: PAnsiChar;                //234.1.2.3  default nil
    ttl: Integer;

    //SOCKET OPTION
    sockSendBufSize: Integer;
    sockRecvBufSize: Integer;
  end;
  PNetConfig = ^TNetConfig;

  TSendConfig = packed record
    net: TNetConfig;
    flags: TDmcFlags;                   { non-capability command line flags }
    blockSize: Integer;

    //�����ٶȹ���(��δʵ��)
//    nrGovernors: Integer;
//    rateGovernor: array[0..MAX_GOVERNORS - 1] of Pointer; //struct rateGovernor_t *rateGovernor[MAX_GOVERNORS];
//    rateGovernorData: array[0..MAX_GOVERNORS - 1] of Pointer;

    min_slice_size: Integer;
    default_slice_size: Integer;
    max_slice_size: Integer;

    //rcvbuf: DWORD;                      //���ݲ�ͬ�ͻ��˻�������С��ȡ��С��
    rexmit_hello_interval: Integer;     { sendHello ���  }

    { sender-specific parameters }
    min_receivers: Integer;             //���ն���������min_receivers��,�Զ���ʼ
    max_receivers_wait: Integer;        //���ȴ�ʱ��

    retriesUntilDrop: Integer;          //sendReqackƬ���Դ��� ��ԭ 200��

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
    rehelloOffset: Integer;             { �����ٸ��飬����һ��hello }
  end;
  PSendConfig = ^TSendConfig;

  //const
  //  DEFAULT_CONFIG    : TNetConfig = (
  //    ifName: 'eth0';                     //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
  //    localPort: 9080;
  //    remotePort: 8090;
  //
  //    blockSize: 1456;                    //���ֵ��һЩ����£���������ߣ������ô��Ч�����Щ��10K
  //    sliceSize: 32;
  //
  //    mcastRdv: nil;                      //�����ַ
  //    ttl: 1;
  //
  //    nrGovernors: 0;
  //
  //    flags: [dmcNoKeyBoard];             //û�п���̨!
  //    capabilities: 0;
  //    min_slice_size: 32;
  //    max_slice_size: 1456;
  //    default_slice_size: 0;              //=0 ���������Զ�ѡ��
  //
  //    rexmit_hello_interval: 0;           //retransmit hello message
  //    autostart: 0;
  //    requestedBufSize: 0;
  //
  //    min_receivers: seWaitReceivers.Value;
  //    max_receivers_wait: 0;
  //    min_receivers_wait: 0;
  //    startTimeout: 0;
  //
  //    retriesUntilDrop: 30;
  //    rehelloOffset: 50;
  //    );

implementation

end.

