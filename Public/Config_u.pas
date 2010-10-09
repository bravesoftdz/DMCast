unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  DEFLT_STAT_PERIOD = 1000;             //״̬������� 1s

type
  TDmcFlag = (
    { "switched network" ��������(ȫ˫��): ������������Ƭ����ʼ������һƬǰ����һƬ�Ѿ�ȷ�ϣ�
    ��Ҫ���ھɵ�ͬ��������� }
    dmcFullDuplex,

    { "not switched network" mode: ��������֪�Ĳ��ɽ���(�޷��߷���ȷ��)! }
    dmcNotFullDuplex,

    { �����㴫��ģʽ��ʹ�õ�����ʱ�������������������ֻ��һ����������}
    dmcPointToPoint,

    { ǿ��ʹ�ù㲥�����Ƕಥ����������֧�ֶಥʱ�Ž���ʹ�� }
    dmcBoardcast,

    { ��ʹ�õ�Ե㣬����ֻ��һ�������� }
    dmcNoPointToPoint
    );
  TDmcFlags = set of TDmcFlag;

  { ���ݶಥģʽ }
  TDmcMode = (
    { �̶�ģʽ: ���������ݹ̶� }
    dmcFixedMode,
    { ��ģʽ���������������һ�����ڽ��еĴ��� }
    dmcStreamMode,

    // Ignore lost data
    { �첽ģʽ������Ҫ�ͻ���ȷ�ϡ�����û�лش��ŵ����õ������! }
    dmcAsyncMode,

    { FECģʽ: ǰ������ṩ�������౸�� }
    dmcFecMode);

  TNetConfig = packed record
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    //�����鲥�Ự/����
    mcastRdv: PAnsiChar;                //239.1.2.3  default nil
    ttl: Integer;

    //SOCKET OPTION
    sockSendBufSize: Integer;
    sockRecvBufSize: Integer;
  end;
  PNetConfig = ^TNetConfig;

  TSendConfig = packed record
    net: TNetConfig;
    flags: TDmcFlags;
    dmcMode: TDmcMode;

    {
      ���ݿ�(��)��С(����16�ֽ�ͷ)�� Ĭ�ϣ�Ҳ�������1456��
      MTU(1500) - 28(UDP_HEAD + IP_HEAD) - 16(DMC_HEAD) = 1456
    }
    blockSize: Integer;

    {
      ��СƬ�ߴ磨�Կ�Ϊ��λ���� Ĭ��Ϊ32��
      ����̬����Ƭ�Ĵ�С���������ڷ�˫��ģʽ����
      ˫��ģʽ���Դ����ã�Ĭ�ϣ���
    }
    min_slice_size: Integer;

    {
      Ĭ��Ƭ�ߴ磨�Կ�Ϊ��λ����
      ��˫��ģʽ:130
      ȫ˫��ģʽ:112
    }
    default_slice_size: Integer;

    {
      ���Ƭ�ߴ磨�Կ�Ϊ��λ���� Ĭ��ֵ��1024��
      ����̬����Ƭ�Ĵ�С���������ڷ�˫��ģʽ�����Ӳ�ʹ�ñ���������Ƭ��
      ˫��ģʽ���Դ����ã�Ĭ�ϣ���
    }
    max_slice_size: Integer;

    {
      �Ự�ڼ�,����೤ʱ�䷢��һ��Hello���ݰ���
      ���ѡ����[�첽ģʽ]�º����ã���Ϊ�첽ģʽ���������ᷢ��һ����������(��˲���õ����Ӵ�)
      ���Ҫ�����˰��õ�������Ϣ���������ݽ���״̬��
      (�Ժ���Ϊ��λ,Ĭ��1000)
    }
    rexmit_hello_interval: Integer;

    {
     [�Զ�����]���ӵĽ����������ﵽ������(Ĭ��0,����)
    }
    min_receivers: Integer;
    {
     [�Զ�����]����һ�����������Ӻ�,���ȴ��೤ʱ�䣨����Ϊ��λ����(Ĭ��0,����)
    }
    max_receivers_wait: Integer;

    {
      [��ʱ����]��һЩʱ�䷢��REQACK�����նˣ��ظ����ٴκ���ֹ����Ӧ�Ľ��ն�.
      ͷ10�μ��ʱ��Լ10ms(waitAvg)����,֮����500ms����
      ע��:�ȴ����ն�ȷ�Ϲ����ж϶������յ�Щ������Ϣ���ȴ�ʱ�������(0.9 * waitAvg + 0.1 * tickDiff(ǰһ�εȴ���ʱ))
    }
    retriesUntilDrop: Integer;          //sendReqackƬ���Դ���(Ĭ��30)

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
    {
      ����[��ģʽ]�£���Ƭ�������ǰ�����ٰ�����һ��Hello���ݰ���Ĭ��50����
      ʹ�¿����Ľ������յ�������Ϣ���������ݽ���״̬��
    }
    rehelloOffset: Integer;             { �����ٸ��飬����һ��hello }
  end;
  PSendConfig = ^TSendConfig;

  { Receiver }
type
  TRecvConfig = packed record
    net: TNetConfig;
    dmcMode: TDmcMode;                  { non-capability command line flags }
    blockSize: Integer;

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
  end;
  PRecvConfig = ^TRecvConfig;

implementation

end.

