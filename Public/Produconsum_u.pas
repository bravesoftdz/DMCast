unit Produconsum_u;

interface
uses
  Windows, Sysutils;

type
  //����(��������������/�ռ�) ,��������������������
  //���ڲ������ݻ�����, ֻ���ƶ�ָ�롢������ͬ��,�������ɾ������
  TProduceConsum = class
  private
    FSize: UINT;
    FProduced: UINT;
    FConsumed: UINT;
    FAtEnd: Boolean;
    FLock: TRTLCriticalSection;
    FConsumerIsWaiting: Boolean;
    FEvent: THandle;
    FName: PChar;
  protected
    procedure WakeConsumer();
    function _ConsumeAny(minAmount, waitTime: UINT): Integer; //����
  public
    constructor Create(size: Integer; const name: PChar);
    destructor Destroy; override;

    procedure Produce(amount: UINT);    //����
    procedure MarkEnd();                //��ǽ���
    function ConsumeAny(): Integer;     //�������1,����
    function ConsumeAnyWithTimeout(waitTime: UINT): Integer; //�������1��ֱ����ʱ
    function ConsumeAnyContiguous(): Integer; //������������ݿ�,����
    function ConsumeContiguousMinAmount(amount: UINT): Integer; //��������Ļ�����������x,����
    function Consume(amount: UINT): Integer; //��������x,����
    function Consumed(amount: UINT): Integer; //������
    function GetProducerPosition(): UINT; //��ȡ�����ߵ�ǰλ��(��Produced�ƶ�)
    function GetConsumerPosition(): UINT; //��ȡ�����ߵ�ǰλ��(��Consumed�ƶ�)
    function GetSize(): UINT;
    function GetProducedAmount(): Integer; //��ȡĿǰ�ȴ������ĵ�����������������
  end;

implementation

{ TProduceConsum }

function TProduceConsum.Consume(amount: UINT): Integer;
begin
  Result := _ConsumeAny(amount, INFINITE);
end;

function TProduceConsum.ConsumeAny: Integer;
begin
  Result := _ConsumeAny(1, INFINITE);
end;

function TProduceConsum.ConsumeAnyContiguous: Integer;
begin
  Result := ConsumeContiguousMinAmount(1);
end;

function TProduceConsum.ConsumeAnyWithTimeout(waitTime: UINT): Integer;
begin
  Result := _ConsumeAny(1, waitTime);
end;

function TProduceConsum.ConsumeContiguousMinAmount(amount: UINT): Integer;
var
  l                 : Integer;
begin
  Result := _ConsumeAny(amount, INFINITE);
  l := FSize - (FConsumed mod FSize);
  if (Result > l) then
    Result := l;
end;

function TProduceConsum.Consumed(amount: UINT): Integer;
var
  consumed          : UINT;
begin
  consumed := FConsumed;
  if (consumed >= 2 * FSize - amount) then
    Inc(consumed, amount - 2 * FSize)
  else
    Inc(consumed, amount);

  FConsumed := consumed;
  Result := amount;
end;

constructor TProduceConsum.Create(size: Integer; const name: PChar);
begin
  FSize := size;
  FProduced := 0;
  FConsumed := 0;
  FAtEnd := False;
  InitializeCriticalSection(FLock);
  FConsumerIsWaiting := False;
  FEvent := CreateEvent(nil, True, True, nil); //[�ֶ���λ][���ź�]
  FName := name;
end;

destructor TProduceConsum.Destroy;
begin
  DeleteCriticalSection(FLock);
  CloseHandle(FEvent);
  inherited;
end;

function TProduceConsum.GetConsumerPosition: UINT;
begin
  Result := FConsumed mod FSize;
end;

function TProduceConsum.GetProducedAmount: Integer;
begin
  if (FProduced < FConsumed) then
    Result := FProduced + 2 * FSize - FConsumed
  else
    Result := FProduced - FConsumed;
end;

function TProduceConsum.GetProducerPosition: UINT;
begin
  Result := FProduced mod FSize;
end;

function TProduceConsum.GetSize: UINT;
begin
  Result := FSize;
end;

procedure TProduceConsum.MarkEnd;
begin
  FAtEnd := True;
  WakeConsumer();
end;

procedure TProduceConsum.Produce(amount: UINT);
var
  produced, consumed: UINT;
begin
  produced := FProduced;
  consumed := FConsumed;

  { * sanity checks:
    * 1. should not produce more than size
    * 2. do not pass consumed + size
    * }
  if (amount > FSize) then begin
    raise Exception.Create(Format('Buffer overflow in produce %s: %d > %d '#10,
      [FName, amount, FSize]));
    Exit;
  end;

  Inc(produced, amount);
  if (produced >= 2 * FSize) then
    Dec(produced, 2 * FSize);

  if (produced > consumed + FSize) or
    ((produced < consumed) and (produced > consumed - FSize)) then begin
    raise Exception.Create(Format('Buffer overflow in produce %s: %d > %d[%d]'#10,
      [FName, produced, consumed, FSize]));
    Exit;
  end;

  FProduced := produced;
  WakeConsumer();
end;

procedure TProduceConsum.WakeConsumer;
begin
  if FConsumerIsWaiting then
  begin
    EnterCriticalSection(FLock);
    SetEvent(FEvent);
    LeaveCriticalSection(FLock);
  end;
end;

function TProduceConsum._ConsumeAny(minAmount, waitTime: UINT): Integer;
var
  r                 : Integer;
  amount            : UINT;
begin
{$IFDEF DEBUG}
  flprintf('%s: Waiting for %d bytes(%d: %d)\n',
    FName, minAmount, FConsumed, FProduced);
{$ENDIF}
  FConsumerIsWaiting := True;
  amount := GetProducedAmount();
  if (amount >= minAmount) or FAtEnd then
  begin
    FConsumerIsWaiting := False;
{$IFDEF DEBUG}
    flprintf('%s: got %d bytes\n', pc^.name, amount);
{$ENDIF}
    Result := amount;
  end else
  begin
    EnterCriticalSection(FLock);
    while (not FAtEnd) do
    begin
      amount := GetProducedAmount();
      if amount < minAmount then        //�ȴ��ﵽ�����
      begin
        //{$IFDEF DEBUG}
        //      flprintf('%s: ..Waiting for %d bytes(%d: %d)\n',
        //        pc^.name, minAmount, pc^.consumed, pc^.produced);
        //{$ENFIF}
        ResetEvent(FEvent);
        LeaveCriticalSection(FLock);
        r := WaitForSingleObject(FEvent, waitTime);
        EnterCriticalSection(FLock);

        if (r = WAIT_TIMEOUT) then begin
          amount := GetProducedAmount();
          Break;
        end;
      end else
        Break;
    end;                                //end while
    LeaveCriticalSection(FLock);
{$IFDEF DEBUG}
    flprintf('%s: Got them %d(for %d)%d\n', FName,
      amount, minAmount, FAtEnd);
{$ENDIF}
    FConsumerIsWaiting := False;
    Result := amount;
  end;
end;

end.

