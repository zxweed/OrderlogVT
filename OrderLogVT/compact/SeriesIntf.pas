unit SeriesIntf;

interface
uses
   SysUtils, Types, Windows, StrUtils, Math, Classes;

const
  N_REF_MAX     = 10000;                // ������������ �������� RefCount, ���� �������� ����� ��������� MMF (� ���� ������ ��������� ����� �� �������� � ����������� ������)

type
  TSeries = array of Double;            // ����� ������

  TTradeSeries = record                   // ��������� ����� �������� ������
    DateTimeA: TSeries;
    PriceA: TSeries;
    VolumeA: TSeries;
  end;
  TSeriesOfTradeSeries = array of TTradeSeries;

  TTimeSeries = record                    // ����� ������ �� ��������
    DateTimeA: TSeries;
    PriceA: TSeries;
  end;

  TTrade = record
    DateTime: Double;
    Price: Double;
    Volume: Double;
  end;

  TOHLC = record
    DateTime: Double;
    Open: Double;
    High: Double;
    Low: Double;
    Close: Double;
    Volume: Double;
  end;

  PBoundedSeries = ^TBoundedSeries;
  TBoundedSeries = array [Word] of Double;
  TBoundedIntSeries = array [Word] of Integer;

  PArrayHeader = ^TArrayHeader;
  TArrayHeader = packed record            // ��������� ������������� �������
    RefCount: DWORD;                      // ������� ������
    Length: Integer;                      // ����� �������
  end;

procedure SetLen (var SrcA: TSeries; ALen: Integer); overload;

procedure SetLen (var SrcT: TTradeSeries; ALen: Integer); overload;

function HPtr(var SrcA: TSeries): PArrayHeader;
 { ���������� ������ �� ��������� ����� }
function IncLen (var SrcA: TSeries): Integer; overload;

function IncLen (var SrcT: TTimeSeries): Integer; overload;
function IncLen (var SrcT: TTradeSeries): Integer; overload;

function Hi (const SrcT: TTradeSeries): Integer;
function Len (const SrcT: TTradeSeries): Integer;
function AppendValue(var TradeT: TTradeSeries; const ATrade: TTrade): Integer;
function FrameStart (ADateTime: TDateTime; AFrameSec: Double = 1): TDateTime;
 { ���������� ������ ��������� ��� ���������� �������. }
function HighValue (const SrcA: TSeries): Double;
 { ���������� ������������ �������� � �����. }
function LowValue (const SrcA: TSeries): Double;
 { ���������� ����������� �������� � �����. }
function IndexOf (AValue: Double; const SrcA: TSeries): Integer; overload;
 { ���� ������ ����� � _�������������_ �����, ���������� ��� ������. }
 { ���� �� ����� ������� ����������, ���������� ������ ��������. }


implementation

procedure SetLen (var SrcA: TSeries; ALen: Integer); overload;
var
  H: PArrayHeader;
  nSize: Integer;
begin
  H := PArrayHeader(Integer(SrcA)-8);
  if Assigned(Pointer(SrcA)) and (H^.RefCount > N_REF_MAX) then begin
     // �������� ����������� ������� ������ ��� ����������
    nSize := (ALen - H^.Length) * SizeOf(Double);
    if nSize > 0
      then FillChar (TBoundedSeries(Pointer(SrcA)^)[H^.Length], nSize, 0);
    H^.Length := ALen;
  end else
    SetLength (SrcA, ALen);
end;

procedure SetLen (var SrcT: TTradeSeries; ALen: Integer); overload;
begin
  SetLen (SrcT.PriceA, ALen);
  SetLen (SrcT.VolumeA, ALen);
  SetLen (SrcT.DateTimeA, ALen);
end;

function HPtr(var SrcA: TSeries): PArrayHeader;
 { ���������� ������ �� ��������� ����� }
begin
  if Assigned(Pointer(SrcA))
    then Result := PArrayHeader(Integer(SrcA)-8)
    else Result := nil;
end;

function IncLen (var SrcA: TSeries): Integer; overload;
begin
  if Assigned(Pointer(SrcA)) and (HPtr(SrcA)^.RefCount > N_REF_MAX) then begin
    Assert (HPtr(SrcA)^.Length >= 0, 'Length of series cannot be negative');
    Result := InterlockedIncrement(HPtr(SrcA)^.Length)
  end else begin
     // ��� ������� ����� ���������� ����������� ��������
    Result := Length(SrcA) + 1;
    SetLength (SrcA, Result);
  end;
end;

function IncLen (var SrcT: TTimeSeries): Integer; overload;
begin
  IncLen(SrcT.PriceA);
  Result := IncLen(SrcT.DateTimeA);
end;

function IncLen (var SrcT: TTradeSeries): Integer; overload;
begin
  IncLen(SrcT.VolumeA);
  IncLen(SrcT.PriceA);
  Result := IncLen(SrcT.DateTimeA);
end;

function Hi (const SrcT: TTradeSeries): Integer;
var
  H1, H2, H3: Integer;
begin
  H1 := High(SrcT.DateTimeA);
  H2 := High(SrcT.VolumeA);
  H3 := High(SrcT.PriceA);
  Result := Min (Min (H1, H2), H3);
end;

function Len (const SrcT: TTradeSeries): Integer;
var
  L1, L2, L3: Integer;
begin
  L1 := Length(SrcT.DateTimeA);
  L2 := Length(SrcT.VolumeA);
  L3 := Length(SrcT.PriceA);
  Result := Min (Min (L1, L2), L3);
end;

function AppendValue(var TradeT: TTradeSeries; const ATrade: TTrade): Integer;
begin
  Result := IncLen(TradeT)-1;
  TradeT.DateTimeA[Result] := ATrade.DateTime;
  TradeT.PriceA[Result] := ATrade.Price;
  TradeT.VolumeA[Result] := ATrade.Volume;
end;

function FrameStart (ADateTime: TDateTime; AFrameSec: Double = 1): TDateTime;
 { ���������� ������ ��������� ��� ���������� �������. }
var
  K: Double;
begin
  K := 24 * 60 * 60 / AFrameSec;
  Result := Trunc((ADateTime + 1/24/60/60/1000) * K) / K;       // + ������������, ����� 10:00:00 �������� � �������� �� 10, � �� � 9:59:59
end;

function HighValue (const SrcA: TSeries): Double;
 { ���������� ������������ �������� � �����. }
var
  J: Integer;
begin
  Result := -MaxInt;
  for J := 0 to High(SrcA) do
    if (SrcA[J] > Result) and not IsInfinite(SrcA[J]) then Result := SrcA[J];
  if Result = -MaxInt then Result := 0;
end;

function LowValue (const SrcA: TSeries): Double;
 { ���������� ����������� �������� � �����. }
var
  J: Integer;
begin
  Result := MaxInt;
  for J := 0 to High(SrcA) do
    if (SrcA[J] < Result) and not IsInfinite(SrcA[J]) then Result := SrcA[J];
  if Result = MaxInt then Result := 0;
end;

function IndexOf (AValue: Double; const SrcA: TSeries): Integer; overload;
 { ���� ������ ����� � _�������������_ �����, ���������� ��� ������. }
 { ���� �� ����� ������� ����������, ���������� ������ ��������. }
var
  J, Lb, Ub: Integer;
begin
  Result := -1;
  Lb := Low (SrcA);
  Ub := High (SrcA);
  if Ub < Lb then Exit;

   // �������� �����
  while (Result = -1) and (Lb <= Ub) do begin
    J := (Lb + Ub) div 2;
    if AValue < SrcA[J] then
      Ub := J - 1
    else if AValue > SrcA[J] then
      Lb := J + 1
    else
      Result := J;

      // �� ����� ������� ���������� - ���������� �������
    if Lb > Ub then Result := Ub;
  end;
end;

end.
