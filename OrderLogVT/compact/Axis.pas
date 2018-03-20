unit Axis;
 { Простой компонент для поддержки осей координат на графиках }

interface
uses
  Windows, Classes, GR32, Math, SeriesIntf;

type
   // Ось может рисоваться справа, слева, сверху и снизу
  TAxisKind = (axLeft, axRight, axBottom, axTop);

  TAxis = class(TComponent)
  private
    FMinimum: Double;                   // Границы оси координат
    FMaximum: Double;
    FValue: Double;                     // Текущее значение (выделяется)
    FBitmap: TBitmap32;                 // Битмап, на котором считаем и рисуем
    FKind: TAxisKind;                   // Тип оси
    FTitle: string;                     // Название
    FColor: Cardinal;
    FReversed: Boolean;                 // Флажок перевёрнутости оси

    procedure SetMinimum (AMinimum: Double);
    procedure SetMaximum (AMaximum: Double);
    procedure SetKind (AKind: TAxisKind);
    procedure SetBitmap (ABitmap: TBitmap32);
    function GetRange: Double;
  published
    property Minimum: Double read FMinimum write SetMinimum;
    property Maximum: Double read FMaximum write SetMaximum;
    property Value: Double read FValue write FValue;
    property Kind: TAxisKind read FKind write SetKind;
    property Bitmap: TBitmap32 read FBitmap write SetBitmap;
    property Range: Double read GetRange;
    property Color: Cardinal read FColor write FColor;
    property Title: string read FTitle write FTitle;
    property Reversed: Boolean read FReversed write FReversed;
  public
    constructor Create (AOwner: TComponent); override;
    procedure ReflectChanges;
     { Пересчитывает внутренние коэффициенты - более не нужна, оставлена для совместимости }
    function GetRatio: Double;
     { Возвращает величину коэффициента масштабирования }
    function PixelToValue (APixel: Integer): Double;
    function ValueToPixel (AValue: Double): Integer;
    function WidthToRange (AWidth: Integer): Double;
    function RangeToWidth (ARange: Double): Integer;
    procedure SetRange (AMinimum, AMaximum: Double); overload;
    procedure SetRange(const SrcA: TSeries); overload;
    procedure ShiftByPixels (APixelRange: Integer);
    procedure ShiftByRange (ARange: Double);
    procedure Zoom (APercent: Double = 1.5);
  end;

function CreateAxis(ABitmap: TBitmap32; AKind: TAxisKind = axRight): TAxis;

implementation

function CreateAxis(ABitmap: TBitmap32; AKind: TAxisKind = axRight): TAxis;
begin
  Result := TAxis.Create(nil);
  Result.Bitmap := ABitmap;
  Result.Kind := AKind;
end;

constructor TAxis.Create (AOwner: TComponent);
begin
  inherited;
  Bitmap := nil;
  Minimum := 0;
  Maximum := 0;
  Kind := axRight;
  FReversed := False;
end;

procedure TAxis.ReflectChanges;
begin
end;

function TAxis.GetRatio: Double;
 { Возвращает величину коэффициента масштабирования }
begin
  if Assigned(Bitmap) and (Maximum <> Minimum) then
    if Kind in [axLeft, axRight]
      then Result := Bitmap.Height / (Maximum - Minimum)
      else Result := Bitmap.Width / (Maximum - Minimum)
  else
    Result := 1;
end;

procedure TAxis.SetMinimum(AMinimum: Double);
begin
  FMinimum := AMinimum;
  ReflectChanges;
end;

procedure TAxis.SetMaximum(AMaximum: Double);
begin
  FMaximum := AMaximum;
  ReflectChanges;
end;

procedure TAxis.SetRange (AMinimum, AMaximum: Double);
begin
  FMinimum := AMinimum;
  FMaximum := AMaximum;
  ReflectChanges;
end;

procedure TAxis.SetRange(const SrcA: TSeries);
begin
  FMinimum := LowValue(SrcA);
  FMaximum := HighValue(SrcA);
  ReflectChanges;
end;

procedure TAxis.ShiftByPixels (APixelRange: Integer);
var
  fDelta: Double;
begin
  fDelta := WidthToRange (APixelRange);
  SetRange(Minimum + fDelta, Maximum + fDelta);
end;

procedure TAxis.ShiftByRange (ARange: Double);
begin
  SetRange(Minimum + ARange, Maximum + ARange);
end;

function TAxis.GetRange: Double;
begin
  Result := Maximum - Minimum;
end;

procedure TAxis.SetKind (AKind: TAxisKind);
begin
  FKind := AKind;
  ReflectChanges;
end;

procedure TAxis.SetBitmap (ABitmap: TBitmap32);
begin
  FBitmap := ABitmap;
  ReflectChanges;
end;

function TAxis.PixelToValue (APixel: Integer): Double;
var
  fK: Double;
begin
  fK := GetRatio;
  if (fK <> 0) and not IsInfinite(fK) then
    if Kind in [axLeft, axRight]
      then Result := Maximum - APixel / fK
      else Result := Minimum + APixel / fK
  else
    Result := 0;
end;

function TAxis.ValueToPixel (AValue: Double): Integer;
var
  R: Int64;
  fK: Double;
begin
  fK := GetRatio;
  R := 0;
  if (fK <> 0) and not IsInfinite(fK) then
    try
    if Kind in [axLeft, axRight]
      then R := Round((Maximum - AValue) * fK)     // Для вертикальных осей инвертируем координаты, поскольку 0 - вверху
      else R := Round((AValue - Minimum) * fK)
    finally
      Result := Max(Min(R, MaxInt), -MaxInt);
    end
  else
    Result := 0;

  if FReversed then
    if Kind in [axLeft, axRight]
      then Result := FBitmap.Height - Result
      else Result := FBitmap.Width - Result;
end;

function TAxis.WidthToRange (AWidth: Integer): Double;
var
  fK: Double;
begin
  fK := GetRatio;
  if (fK <> 0) and not IsInfinite(fK)
    then Result := AWidth / fK
    else Result := 0;
end;

function TAxis.RangeToWidth (ARange: Double): Integer;
var
  fK: Double;
begin
  fK := GetRatio;
  if (fK <> 0) and not IsInfinite(fK)
    then Result := Max(Min(Round (ARange * fK), MaxInt), -MaxInt)
    else Result := 0;
end;

procedure TAxis.Zoom(APercent: Double = 1.5);
var
  fStep, fShiftKoeff: Double;
begin
  fStep := Range * APercent / 100;
   // Коэффициент используется для того, чтобы центр оси (определяемый текущим значением), оставался на месте
  if Value = 0
    then fShiftKoeff := 1
    else fShiftKoeff := Abs ((Maximum - Value) / (Value - Minimum));
  Minimum := Minimum + fStep;
  Maximum := Maximum - fStep * fShiftKoeff;
  ReflectChanges;
end;

end.
