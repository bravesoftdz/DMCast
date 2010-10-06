unit Func_u;

interface

uses
  Windows, SysUtils;

//* bitmap manipulation */
//#define BITS_PER_ITEM(map) (SizeOf(map[0])*8)
//#define MASK(pos,map) (1 << ((pos) % (BITS_PER_ITEM(map))))
//#define POS(pos,map)  ((pos) / BITS_PER_ITEM(map))
//#define SET_BIT(x, map) (map[POS(x,map)] |= MASK(x,map))
//#define CLR_BIT(x, map) (map[POS(x,map)] &= ~MASK(x,map))
//#define BIT_ISSET(x, map) (map[POS(x,map)] & MASK(x,map))

{ BitsMap ʹ��delphi 2005������֧������ }
function bit_isset(x: Dword; m: PByteArray): Boolean;
procedure set_bit(x: Dword; m: PByteArray);
procedure clr_bit(x: Dword; m: PByteArray);

function GetTickCountUSec(): DWORD;     //΢���ʱ����1/1000 000��
function DiffTickCount(tOld, tNew: DWORD): DWORD; //����ʱ���
function GetSizeKMG(byteSize: Int64): string; //�Զ�����KB MB GB
implementation

function bit_isset(x: Dword; m: PByteArray): Boolean; {$IF COMPILERVERSION >17.0}inline; {$IFEND}
begin
  Result := Boolean(m[x div 8] and (1 shl (x mod 8)));
end;

procedure set_bit(x: Dword; m: PByteArray); {$IF COMPILERVERSION >17.0}inline; {$IFEND}
begin
  m[x div 8] := m[x div 8] or (1 shl (x mod 8));
end;

procedure clr_bit(x: Dword; m: PByteArray); {$IF COMPILERVERSION >17.0}inline; {$IFEND}
begin
  m[x div 8] := m[x div 8] and not (1 shl (x mod 8));
end;

var
  Frequency         : Int64;

function GetTickCountUSec;              //�� GetTickCount���ȸ�25~30����
var
  lpPerformanceCount: Int64;
begin
  if Frequency = 0 then begin
    QueryPerformanceFrequency(Frequency); //WINDOWS API ���ؼ���Ƶ��(Intel86:1193180)(���ϵͳ�ĸ�����Ƶ�ʼ�������һ���ڵ��𶯴���)
    Frequency := Frequency div 1000000; //һ΢�����񶯴���
  end;
  QueryPerformanceCounter(lpPerformanceCount);
  Result := lpPerformanceCount div Frequency;
end;

function DiffTickCount;                 //����ʱ���
begin
  if tNew >= tOld then Result := tNew - tOld
  else Result := INFINITE - tOld + tNew;
end;

function GetSizeKMG(byteSize: Int64): string; //�Զ�����KB MB GB
  function FloatToStr2(const f: Double; const n: Integer): string; //<== 20100313 hou
  var
    i, j, k         : Integer;
  begin
    j := 1;
    for i := 1 to n do
      j := j * 10;

    k := Trunc(f);
    Result := IntToStr(k) + '.' + IntToStr(Trunc((f - k) * j));
  end;
begin
  if byteSize < 1024 then
    Result := IntToStr(byteSize) + ' B'
  else if byteSize < 1024 * 1024 then
    Result := FloatToStr2(byteSize / 1024, 2) + ' KB' //format2('%.2f KB', [byteSize / 1024])
  else if byteSize < 1024 * 1024 * 1024 then
    Result := FloatToStr2(byteSize / (1024 * 1024), 2) + ' MB' //format('%.2f MB', [byteSize / (1024 * 1024)])
  else Result := FloatToStr2(byteSize / (1024 * 1024 * 1024), 2) + ' GB'; //format('%.2f GB', [byteSize / (1024 * 1024 * 1024)]);
end;

end.
