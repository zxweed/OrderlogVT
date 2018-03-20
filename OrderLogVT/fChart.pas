unit fChart;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, TeeGDIPlus, TeEngine, ExtCtrls, TeeProcs, Chart, ShareCode;

type
  TFormChart = class(TForm)
    Chart: TChart;
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  FormChart: TFormChart;

implementation

{$R *.dfm}

end.
