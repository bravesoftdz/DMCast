program DMCSender;

uses
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmCastFile};

{$R *.res}
begin
  Application.Initialize;
  Application.Title := '�ļ�/���ݶಥ';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

