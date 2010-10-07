unit IStats_u;

interface
uses
  Windows, Sysutils, Messages, WinSock;

type
  { Sender/Receiver ����״̬ͳ�� }

  TTransState = (tsStop, tsNego, tsTransing, tsComplete, tsExcept);

  ITransStats = interface
    //tCreate   tChange        nID
    ['{20100608-2010-1005-2212-001E68AD5693}']
    //����״̬����
    procedure TransStateChange(TransState: TTransState);
    //��ǰ����״̬
    function TransState: TTransState;
    //�ɹ�����Ƭ��С
    procedure AddBytes(bytes: Integer);
  end;

  { Sender }
  ISenderStats = interface(ITransStats)
    //�ش�����
    procedure AddRetrans(nrRetrans: Integer);
  end;

  { Reciever }
  IReceiverStats = interface(ITransStats)
  end;

  { Sender ��Ա��� }
  IPartsStats = interface
    ['{20100930-1049-0000-0000-000000000001}']
    function Add(index: Integer; addr: PSockAddrIn; sockBuf: Integer): Boolean;
    function Remove(index: Integer; addr: PSockAddrIn): Boolean;
    function GetNrOnline(): Integer;
  end;

implementation

end.

