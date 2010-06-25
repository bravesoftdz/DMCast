unit IStats_u;

interface
uses
  Windows, Sysutils, Messages, WinSock,
  Config_u;

type
  TUMsgType = (umtMsg, umtDebug, umtWarn, umtError, umtFatal);
const
  DMC_MSG_TYPE      : array[TUMsgType] of string[8] = ('��Ϣ', '����', '����',
    '����', '����');
type
  ITransStats = interface
    ['{20100608-0027-0000-0000-000000000001}']
    procedure BeginTrans();
    procedure EndTrans();
    procedure AddBytes(bytes: Integer);
    procedure AddRetrans(nrRetrans: Integer);
    procedure Msg(msgType: TUMsgType; msg: string);
    function Transmitting(): Boolean;
  end;

implementation

end.

