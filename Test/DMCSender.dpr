program DMCSender;

uses
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmUdpcast};

{$R *.res}
begin
  Application.Initialize;
  Application.Title := '�ļ�/���ݶಥ';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

