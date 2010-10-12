{
  ����·�ɱ�
}
unit Route_u;

interface

uses
  Windows, Winsock;

type
  PIP_MASK_STRING = ^IP_MASK_STRING;
{$EXTERNALSYM PIP_MASK_STRING}
  IP_ADDRESS_STRING = record
    S: array[0..15] of Char;
  end;
{$EXTERNALSYM IP_ADDRESS_STRING}
  PIP_ADDRESS_STRING = ^IP_ADDRESS_STRING;
{$EXTERNALSYM PIP_ADDRESS_STRING}
  IP_MASK_STRING = IP_ADDRESS_STRING;
{$EXTERNALSYM IP_MASK_STRING}
  TIpAddressString = IP_ADDRESS_STRING;
  PIpAddressString = PIP_MASK_STRING;

  //
  // IP_ADDR_STRING - store an IP address with its corresponding subnet mask,
  // both as dotted decimal strings
  //

  PIP_ADDR_STRING = ^IP_ADDR_STRING;
{$EXTERNALSYM PIP_ADDR_STRING}
  _IP_ADDR_STRING = record
    Next: PIP_ADDR_STRING;
    IpAddress: IP_ADDRESS_STRING;
    IpMask: IP_MASK_STRING;
    Context: DWORD;
  end;
{$EXTERNALSYM _IP_ADDR_STRING}
  IP_ADDR_STRING = _IP_ADDR_STRING;
{$EXTERNALSYM IP_ADDR_STRING}
  TIpAddrString = IP_ADDR_STRING;
  PIpAddrString = PIP_ADDR_STRING;

  //
  // ADAPTER_INFO - per-adapter information. All IP addresses are stored as
  // strings
  //

  PIP_ADAPTER_INFO = ^IP_ADAPTER_INFO;
{$EXTERNALSYM PIP_ADAPTER_INFO}
  _IP_ADAPTER_INFO = record
    Next: PIP_ADAPTER_INFO;             //����ָ��������ͨ�������������̬����
    ComboIndex: DWORD;                  //����δ��
    AdapterName: array[0..131] of Char; //������
    Description: array[0..131] of Char; //��������������ʵ���Ϻ�����//�������������
    AddressLength: UINT;                //�����ַ�ĳ��ȣ�ͨ��������ǲ�����ȷ����ʾ���������е������
    Address: array[0..7] of Byte;       //�����ַ��ÿ���ֽڴ��һ��ʮ�����Ƶ���ֵ
    Index: DWORD;                       //����������
    Type_: UINT;                        //��������
    DhcpEnabled: UINT;                  //�Ƿ�������DHCP��̬IP����
    CurrentIpAddress: PIP_ADDR_STRING;  //��ǰʹ�õ�IP��ַ
    IpAddressList: IP_ADDR_STRING;      //�󶨵���������IP��ַ������Ҫ��Ŀ
    GatewayList: IP_ADDR_STRING;        //���ص�ַ������Ҫ��Ŀ
    DhcpServer: IP_ADDR_STRING;         //DHCP��������ַ��ֻ����DhcpEnabled==TRUE������²���
    HaveWins: BOOL;                     //�Ƿ�������WINS
    PrimaryWinsServer: IP_ADDR_STRING;  //��WINS��ַ
    SecondaryWinsServer: IP_ADDR_STRING; //��WINS��ַ
    LeaseObtained: Longint;             //��ǰDHCP����ȡ��ʱ��
    LeaseExpires: Longint;              //��ǰDHCP���ʧЧʱ�䡣���������ݽṹֻ����������DHCPʱ�����á�
  end;
{$EXTERNALSYM _IP_ADAPTER_INFO}
  IP_ADAPTER_INFO = _IP_ADAPTER_INFO;
{$EXTERNALSYM IP_ADAPTER_INFO}
  TIpAdapterInfo = IP_ADAPTER_INFO;
  PIpAdapterInfo = PIP_ADAPTER_INFO;

  {IP ·���б�ṹ}
  PMIB_IPFORWARDROW = ^MIB_IPFORWARDROW;
  _MIB_IPFORWARDROW = record
    dwForwardDest: DWORD;               //·�ɵ���Ŀ�������ַ
    dwForwardMask: DWORD;               //·�ɵ���Ŀ��������������
    dwForwardPolicy: DWORD;             //����û��
    dwForwardNextHop: DWORD;            //��һ���ĵ�ַ�������ص�ַ
    dwForwardIfIndex: DWORD;            //ʹ�õ������豸�ӿ�����ֵ
    dwForwardType: DWORD;               //·������ 3������Ŀ�꣬4�Ƿ�����Ŀ��
    dwForwardProto: DWORD;              //·��Э�飬��������������Ҫ���3
    dwForwardAge: DWORD;                //·���������ڣ�·�ɴ��ڵ�����
    dwForwardNextHopAS: DWORD;          //û�ã����0
    dwForwardMetric1: DWORD;            //·�����ȼ�����������С���ȼ�Խ��
    dwForwardMetric2: DWORD;            //�����⼸����ʱ���ã����0xFFFFFFFF
    dwForwardMetric3: DWORD;
    dwForwardMetric4: DWORD;
    dwForwardMetric5: DWORD;
  end;
  MIB_IPFORWARDROW = _MIB_IPFORWARDROW;
  TMibIpForwardRow = MIB_IPFORWARDROW;
  PMibIpForwardRow = PMIB_IPFORWARDROW;

  {IP ·��ȫ��ṹ}
  PMIB_IPFORWARDTABLE = ^MIB_IPFORWARDTABLE;
  _MIB_IPFORWARDTABLE = record
    dwNumEntries: DWORD;                //·������
    table: array[0..0] of MIB_IPFORWARDROW;
  end;
  MIB_IPFORWARDTABLE = _MIB_IPFORWARDTABLE;

const
  iphlpapilib       = 'iphlpapi.dll';

function AddIpRoute(const dwDest, dwMask, dwGawy: DWORD): boolean;
function DeleteIpRoute(dwDest: DWORD): boolean;
function SetLocalRoute(dwDest, dwMask, dwGawy: DWORD): Integer;
implementation

//����API����ERROR_SUCCESS���ǳɹ�

function GetBestInterface(dwDestAddr: ULONG; var pdwBestIfIndex: DWORD): DWORD; stdcall; external iphlpapilib name 'GetBestInterface';
//function GetAdaptersInfo(pAdapterInfo: PIP_ADAPTER_INFO; var pOutBufLen: ULONG): DWORD; stdcall; external iphlpapilib name 'GetAdaptersInfo';

function GetIpForwardTable(pIpForwardTable: PMIB_IPFORWARDTABLE; var pdwSize: ULONG; bOrder: BOOL): DWORD; stdcall; external iphlpapilib name 'GetIpForwardTable';

function CreateIpForwardEntry(const pRoute: MIB_IPFORWARDROW): DWORD; stdcall; external iphlpapilib name 'CreateIpForwardEntry';

function SetIpForwardEntry(const pRoute: MIB_IPFORWARDROW): DWORD; stdcall; external iphlpapilib name 'SetIpForwardEntry';

function DeleteIpForwardEntry(const pRoute: MIB_IPFORWARDROW): DWORD; stdcall; external iphlpapilib name 'DeleteIpForwardEntry';

function SetRTable(const dwDest, dwMask, dwGawy, IfIndex: DWORD): MIB_IPFORWARDROW;
begin
  with Result do
  begin
    dwForwardDest := dwDest;
    dwForwardMask := dwMask;
    dwForwardNextHop := dwGawy;
    dwForwardIfIndex := IfIndex;        //ʹ�õ������豸�ӿ�����ֵ
    dwForwardType := 4;                 //·������ 3������Ŀ�꣬4�Ƿ�����Ŀ��
    dwForwardProto := 3;                //·��Э�飬��������������Ҫ���3
    dwForwardAge := 0;                  //·���������ڣ�·�ɴ��ڵ�����
    dwForwardNextHopAS := 0;            //û�ã����0
    dwForwardMetric1 := 1;              //·�����ȼ���������ԽС���ȼ�Խ��
    dwForwardMetric2 := 0;              //�����⼸����ʱ���ã����0xFFFFFFFF
    dwForwardMetric3 := 0;
    dwForwardMetric4 := 0;
    dwForwardMetric5 := 0;
  end;
end;

function AddIpRoute(const dwDest, dwMask, dwGawy: DWORD): boolean;
var
  IfIndex           : DWORD;
begin
  GetBestInterface(dwGawy, IfIndex);    //��õ���ָ��IP����ӿ�
  Result := CreateIpForwardEntry(SetRTable(dwDest, dwMask, dwGawy, IfIndex)) = NO_ERROR;
end;

function DeleteIpRoute;
var
  i, dwSize         : ULONG;
  lpRouteTable      : PMIB_IPFORWARDTABLE; //·�ɱ�
  lpRouteRow        : PMIB_IPFORWARDROW;
begin
  Result := false;
  dwSize := 0;
  if GetIpForwardTable(nil, dwSize, True) = ERROR_INSUFFICIENT_BUFFER then
  begin
    lpRouteTable := nil;
    GetMem(lpRouteTable, dwSize);
    try
      if GetIpForwardTable(lpRouteTable, dwSize, True) = NO_ERROR then
        for i := 0 to lpRouteTable.dwNumEntries - 1 do
        begin
          lpRouteRow := @lpRouteTable.table[i];
          if dwDest = lpRouteRow^.dwForwardDest then
            Result := DeleteIpForwardEntry(lpRouteRow^) = NO_ERROR;
        end;
    finally
      if lpRouteTable <> nil then
        FreeMem(lpRouteTable);
    end;
  end;
end;

function SetLocalRoute;
var
  pRTable           : PMIB_IPFORWARDTABLE;
  i, dwSize         : ULONG;
  ipRow             : TMibIpForwardRow;
begin
  Result := 0;
  dwSize := 0;
  pRTable := nil;
  try
    if GetIpForwardTable(nil, dwSize, TRUE) = ERROR_INSUFFICIENT_BUFFER then
    begin
      pRTable := GetMemory(dwSize);
      if GetIpForwardTable(pRTable, dwSize, TRUE) <> NO_ERROR then
        Exit;

      for i := 0 to pRTable^.dwNumEntries - 1 do
        if dwGawy = pRTable^.table[i].dwForwardNextHop then
        begin
          with ipRow do
          begin
            dwForwardDest := dwDest;    //����
            dwForwardMask := dwMask;    //����
            dwForwardNextHop := dwGawy; //����
            dwForwardIfIndex := pRTable^.table[i].dwForwardIfIndex; //ʹ�õ������豸�ӿ�����ֵ
            dwForwardType := 3;         //·������ 3������Ŀ�꣬4�Ƿ�����Ŀ��
            dwForwardProto := 3;        //·��Э�飬��������������Ҫ���3
            dwForwardAge := 0;          //·���������ڣ�·�ɴ��ڵ�����
            dwForwardNextHopAS := 0;    //û�ã����0
            dwForwardMetric1 := 1;      //·�����ȼ���������ԽС���ȼ�Խ��
            dwForwardMetric2 := 0;      //�����⼸����ʱ���ã����0xFFFFFFFF
            dwForwardMetric3 := 0;
            dwForwardMetric4 := 0;
            dwForwardMetric5 := 0;
          end;
          Result := CreateIpForwardEntry(ipRow);
          Break;
        end;
    end;
  finally
    FreeMemory(pRTable);
  end;
end;

end.

