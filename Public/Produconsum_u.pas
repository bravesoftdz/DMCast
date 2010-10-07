{
 20100427 %Fix û�в����������Ļ�ֱ�ӷ���0(Ӧ�õȴ�)
}

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
    FDoubSize: UINT;                    //˫����С
    FProduced: UINT;
    FConsumed: UINT;
    FAtEnd: Boolean;
    FLock: TRTLCriticalSection;
    FConsumerIsWaiting: Boolean;
    FEvent: THandle;
    FName: PAnsiChar;
  protected
    procedure WakeConsumer();
    function _ConsumeAny(minAmount, waitTime: UINT): Integer; //����
  public
    constructor Create(size: UINT; const name: PAnsiChar);
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
    function GetProducedAmount(): Integer; //��ȡĿǰ�ɱ����ĵ�����������������
  end;

implementation

{ TProduceConsum }

constructor TProduceConsum.Create(size: UINT; const name: PAnsiChar);
begin
  Assert(size <= UINT(-1) div 2, '"size" Too Big!');
  FSize := size;
  FDoubSize := 2 * size;
  FProduced := 0;
  FConsumed := 0;
  FAtEnd := False;
  InitializeCriticalSection(FLock);
  FConsumerIsWaiting := True;           //True��ֹû�в�������������
  FEvent := CreateEvent(nil, True, False, nil); //[�ֶ���λ][���ź�]
  FName := name;
end;

destructor TProduceConsum.Destroy;
begin
  DeleteCriticalSection(FLock);
  CloseHandle(FEvent);
  inherited;
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
  if (amount > FSize) then
  begin
    raise Exception.CreateFmt('Buffer overflow in produce %s: %d > %d '#10,
      [FName, amount, FSize]);
    Exit;
  end;

  Inc(produced, amount);
  if (produced >= FDoubSize) then
    Dec(produced, FDoubSize);

  if (produced > consumed + FSize) or
    ((produced < consumed) and (produced > consumed - FSize)) then
  begin
    raise Exception.CreateFmt('Buffer overflow in produce %s: %d > %d[%d]'#10,
      [FName, produced, consumed, FSize]);
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
  WriteLn(Format('%s: Waiting for %d bytes(%d: %d)',
    [FName, minAmount, FConsumed, FProduced]);
{$ENDIF}
    FConsumerIsWaiting := True;
    amount := GetProducedAmount();
    if (amount >= minAmount) or FAtEnd then
    begin
      FConsumerIsWaiting := False;
{$IFDEF DEBUG}
      WriteLn(Format('%s: got %d bytes', [FName, amount]));
{$ENDIF}
      Result := amount;
    end
    else
    begin
      EnterCriticalSection(FLock);
      while (not FAtEnd) do
      begin
        amount := GetProducedAmount();
        if (amount < minAmount) then    //�ȴ��ﵽ�����
        begin
{$IFDEF DEBUG}
          WriteLn(Format('%s: ..Waiting for %d bytes(%d: %d)',
            [FName, minAmount, FConsumed, FProduced]);
{$ENDIF}
            ResetEvent(FEvent);
            LeaveCriticalSection(FLock);

            r := WaitForSingleObject(FEvent, waitTime);
            EnterCriticalSection(FLock);

            if (r = WAIT_TIMEOUT) then
            begin
              amount := GetProducedAmount();
              Break;
            end;
        end
        else
          Break;
      end;                              //end while
      LeaveCriticalSection(FLock);
{$IFDEF DEBUG}
      WriteLn(Format('%s: Got them %d(for %d) %s',
        [FName, amount, minAmount, BoolToStr(FAtEnd)]));
{$ENDIF}
      FConsumerIsWaiting := False;
      Result := amount;
    end;
end;

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
  if (consumed >= FDoubSize - amount) then
    Inc(consumed, amount - FDoubSize)
  else
    Inc(consumed, amount);

  FConsumed := consumed;
  Result := amount;
end;

function TProduceConsum.GetConsumerPosition: UINT;
begin
  Result := FConsumed mod FSize;
end;

function TProduceConsum.GetProducedAmount: Integer;
begin
  if (FProduced < FConsumed) then
    Result := FProduced + FDoubSize - FConsumed
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

end.

