program DMCSender;

uses
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmCastFile};

{$R *.res}
begin
  Application.Initialize;
  Application.Title := 'HOU�ļ��ಥ';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

