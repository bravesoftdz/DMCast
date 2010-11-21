
{$IFDEF NO_DLL}
uses
  DMCReceiver_u;
{$ELSE}
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
