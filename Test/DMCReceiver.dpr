program DMCReceiver;

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  fileReceiver_u in 'fileReceiver_u.pas';

{$R *.res}
var
  s                 : string;
begin
  Write(MY_CRLF_LINE);
  Writeln('HOU�ļ��ಥ(���ն�) v1.0b');

  if ParamCount < 1 then
  begin
    write('�����ļ�����Ŀ¼(��d:\):');
    readln(s);
    if s = '' then
      Exit;
    Write(MY_CRLF_LINE);
  end
  else
    s := ParamStr(1);

  //Start
  RunReceiver(s);
end.

