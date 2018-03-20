unit TradeDraw32;
 { ����������� ���������, ��������� � ���������� �������� ������ }
 { $Rev: 2266 $   $Date:: 2015-11-05 18:20:57#$ }

interface
uses
  GR32, Graphics, SeriesIntf, Math, Types, Classes, SysUtils, Windows, Axis;

type
   // ����������� ��������� �������� �������
  TFullSnapRec = record
    RID: Int64;                            // ID ������ (����� ��� NetInvestor/Plaza, ����� ��������� ���������)
    Price: Single;                         // ����
    Volume: Integer;                       // ����� (������������� �������� ��� �����)
    ChVol: Integer;                        // ��������� ������
    ChDate: TDateTime;                     // ����� ��������� ������
  end;
  TFullSnapshot = array of TFullSnapRec;   // ���������� ������ �������

const
   // ������� 0 ������������� �������, 255 - ������, ����� ������ ��������� �� 96 �� 224
   // ���� ���������� �� 0 (�������) �� 40 (������) � �� 80 (�������)
  BrightRange  = 130;
  FMT_PRICE  = '%.0n';              // ������ ����������� ���� ��������� ������
  FMT_VOLUME = '%d';                // � ������

  COLORS32: array[0..12] of TColor32 = (
    clBlack32, clGray32, clMaroon32, clGreen32, clOlive32, clNavy32,
    clPurple32, clTeal32, clRed32, clLime32, clBlue32, clFuchsia32, clAqua32);

  COLORS: array[0..12] of TColor = (
    clBlack, clGray, clMaroon, clGreen, clOlive, clNavy,
    clPurple, clTeal, clRed, clLime, clBlue, clFuchsia, clAqua);

{$R circles.res}                    // ������ ������ �������� � ����� ��������
var
  bRedCircle: TBitmap32;
  bGreenCircle: TBitmap32;
  bRedArrow: TBitmap32;
  bRedDeal: TBitmap32;
  bGreenDeal: TBitmap32;
  bGreenArrow: TBitmap32;
  bSell: TBitmap32;
  bBuy: TBitmap32;
  bSellGray: TBitmap32;
  bBuyGray: TBitmap32;
  bStop: TBitmap32;

type
  TCorrFunc = function (X, Y: TSeries): Double;

procedure DrawGrid(ABitmap: TBitmap32; AAxis: TAxis; AStepPrice: Double);
 { ���������� ������������ ����� }

procedure DrawTickDeals (ABitmap: TBitmap32; const ATradeT: TTradeSeries; AHorzAxis, AVertAxis: TAxis);
 { ������ �� ������� ������� ������ }

procedure Desaturate32(Dest: TBitmap32);
 { ����������� ������ � �������� ������ }

function RandomColor32: TColor32;
 { ���������� ��������� ���� �� ������ ���������� }

{$WARN UNSAFE_TYPE OFF}
function LoadBitmapFromResource (AResourceID: PChar): TBitmap32;
 { ��������� Bitmap32 �� ����� �������� }
{$WARN UNSAFE_TYPE ON}

implementation

function FormatPrice (APrice: Double): string;
 { ��������� ������� ��������� ������ ��� ����� }
var
  P: Integer;
  sFmt: string;
begin
  if (APrice <> 0) and not IsInfinite(APrice)
    then P := 1 + Abs(Trunc(Log10(Abs(APrice))))
    else P := 1;
  sFmt := '%' + IntToStr(P) + '.' + IntToStr(Max(0, 5-P)) + 'n';
  Result := Format(sFmt, [APrice]);
end;

procedure DrawGrid (ABitmap: TBitmap32; AAxis: TAxis; AStepPrice: Double);
var
  fPrice: Double;
  nY1, nY2, nY: Integer;
  sPrice: string;
begin
  if not Assigned(ABitmap) or not Assigned(AAxis)
    then Exit;

  with ABitmap do begin
    BeginUpdate;
    fPrice := Trunc (AAxis.Maximum / AStepPrice) * AStepPrice + AStepPrice;     // �������� � ���������� �������� �������� ���� ��������
    while fPrice > AAxis.Minimum do begin
      nY1 := AAxis.ValueToPixel (fPrice + AStepPrice/2);

{      SetStipple([clWhite32, clWhite32, $FFDDDDDD]);             // ������ �������, �� ����������� �� ����� ���������, ����� ������������ �������� �����, HorzLineS
      HorzLineTSP(0, nY1, ABitmap.Width);                         // �������� ��������� ���������
}
      HorzLineS(0, nY1, ABitmap.Width, $FFF0F0F0);                // ������� ������

       // �������� ������� �������
      Inc (nY1);
      sPrice := FormatPrice (fPrice);
      if (Trunc(fPrice) mod 100 = 0) and (Width > 400) then begin
        nY2 := AAxis.ValueToPixel (fPrice - AStepPrice/2);
        FillRectS(0, nY1, ABitmap.Width, nY2, $FFEEEEEE);
        Font.Color := clGray;
        Font.Style := Font.Style - [fsBold];
        nY := AAxis.ValueToPixel (fPrice);
        TextOut (ABitmap.Width div 3, nY - (TextHeight(sPrice)) div 2, sPrice);
      end;

      fPrice := fPrice - AStepPrice;
    end;
    EndUpdate;
    Changed;
  end;
end;

{$WARN UNSAFE_TYPE OFF}
function LoadBitmapFromResource (AResourceID: PChar): TBitmap32;
 { ��������� Bitmap32 �� ����� �������� }
const
  BM = $4D42; // ������������� ���� �����������
var
  BMF: TBitmapFileHeader;
  HResInfo: THandle;
  MemHandle: THandle;
  Stream: TMemoryStream;
  ResPtr: PByte;
  ResSize: Longint;
begin
  Result := nil;
  BMF.bfType := BM;

   // ����, ��������� � ��������� BITMAP-������ � ��������� ��������� ID
  HResInfo := FindResource(HInstance, AResourceID, RT_Bitmap);
  if HResInfo = 0 then Exit;

  MemHandle := LoadResource(HInstance, HResInfo);
  ResPtr := LockResource(MemHandle);

   // ������� Memory-�����, ������������� ��� ������, ���������� ���� ��������� � ���� �����������
  Stream := TMemoryStream.Create;
  ResSize := SizeofResource(HInstance, HResInfo);
  Stream.SetSize(ResSize + SizeOf(BMF));
  Stream.Write(BMF, SizeOf(BMF));
  Stream.Write(ResPtr^, ResSize);

   // ����������� ����� � ���������� ��� ������� � 0
  FreeResource(MemHandle);
  Stream.Seek(0, 0);

   // ������� TBitmap � ��������� ����������� �� MemoryStream
  Result := TBitmap32.Create;
  Result.LoadFromStream(Stream);
  Stream.Free;
end;
{$WARN UNSAFE_TYPE ON}

function SumPrev (N: Integer): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to N do
    Inc (Result, I-1);
end;

procedure DrawCircle (var ABitmap: TBitmap32; X, Y, Diameter: Integer; const ASrcBitmap: TBitmap32);
 { ������ ������ �� ������� ������ (�� 20 �������) �� �������� ������� ������� ����� }
var
  sR: TRect;
begin
  sR.Top := 0;
  if Diameter > 20 then Diameter := 20;
  if Diameter < 1 then Diameter := 1;
  sR.Left := SumPrev(Diameter)-1;        // 0-based pixels
  sR.Bottom := Diameter;
  sR.Right := sR.Left + Diameter;
  ABitmap.Draw (X - Diameter div 2, Y - Diameter div 2, sR, ASrcBitmap);
end;

procedure DrawTickDeals (ABitmap: TBitmap32; const ATradeT: TTradeSeries; AHorzAxis, AVertAxis: TAxis);
 { ������ �� ������� ������� ������ }
var
  D, D1, D2, nX, nY, nDiameter: Integer;
  fVol, fAvgVol: Double;
  //sVol: string;
begin
  if not Assigned(ABitmap) or (Len(ATradeT) = 0) then Exit;

  D1 := Max (0, IndexOf(AHorzAxis.Minimum, ATradeT.DateTimeA));
  D2 := Min (Hi(ATradeT), IndexOf (AHorzAxis.Maximum, ATradeT.DateTimeA));

   // ���������� ������� ������ ������, ��� ��������������� �������
  fAvgVol := 1;
  if D2 > D1 then begin
    for D := D1 to D2 do
      fAvgVol := fAvgVol + Abs(ATradeT.VolumeA[D]);
    fAvgVol := fAvgVol/(D2-D1);
  end;

   // ������
  with ABitmap do begin
    BeginUpdate;
    Clear(clWhite32);
    PenColor := clBlack;
    Font.Size := 6;
    Font.Style := Font.Style + [fsBold];
    for D := D1 to D2 do begin
      AVertAxis.Value := ATradeT.PriceA[D];
      nX := AHorzAxis.ValueToPixel(ATradeT.DateTimeA[D]);
      nY := AVertAxis.ValueToPixel(ATradeT.PriceA[D]);
      fVol := ATradeT.VolumeA[D];
      if fVol = 0 then fVol := 1;
      nDiameter := 1 + Round (6*LogN(6, Abs(fVol/fAvgVol)));   // Log(N, 1) = 0, ������� ���������� 1

      if fVol > 0
        then DrawCircle(ABitmap, nX, nY, nDiameter, bGreenCircle)
        else DrawCircle(ABitmap, nX, nY, nDiameter, bRedCircle);

       // � ������� ������� ������ ��� ������� ������ (��������� ������������ ������ ��������, �������
       // ��������� �� ���� �������, ��� ����� ����������� ��������������� ���������� ��������)
{      if nDiameter > 14 then begin
        sVol := IntToStr(Abs(Trunc(ATradeT.VolumeA[D])));
        RenderText(nX - TextWidth(sVol) div 2 - 1, nY - TextHeight(sVol) div 2, sVol, 16, clWhite32);
      end; }
    end;
    EndUpdate;
    Changed;
  end;
end;

function CLAMP(const n, AMin, AMax: Integer): Integer;
begin
  if n < AMin then Result := AMin
  else if n > AMax then Result := AMax
  else Result := n;
end; { CLAMP }

{$WARN UNSAFE_CODE OFF}
procedure Desaturate32(Dest: TBitmap32);
var
  i        : Integer;
  a, Intens: Cardinal;
  r, g, b  : Byte;
  Bits     : PColor32;
begin
  Bits := @Dest.Bits[0];

  for i := 0 to Dest.Width * Dest.Height - 1 do begin
    a := Bits^ and $FF000000;

    if a > 0 then begin
      r := Bits^ shr 16 and $FF;
      g := Bits^ shr  8 and $FF;
      b := Bits^        and $FF;

      if (r <> g) or (r <> b) or (g <> b) then begin
        Intens := Round(0.299 * r + 0.587 * g + 0.114 * b);
        Intens := Clamp(Intens, 0, 255);
        Bits^  := a or (Intens shl 16) or (Intens shl 8) or Intens;
      end;
    end;

    Inc(Bits);
  end;
end; { Desaturate32 }


function RandomColor32: TColor32;
 { ���������� ��������� ���� �� ������ ���������� }
begin
  Result := COLORS32[Random(Length(COLORS32))];
end;

initialization
  if not Assigned(bRedCircle) then begin
    bRedCircle := LoadBitmapFromResource('IDB_REDCIRCLES');
    bRedCircle.MasterAlpha := 240;   // MasterAlpha ������������ ��������� � �����-�������, ������� �����������
    bRedCircle.DrawMode := dmBlend;  // ������ ���� � bmp-����� (�� ��� ��������� ��������� ��� ���������!)
  end;

  if not Assigned(bGreenCircle) then begin
    bGreenCircle := LoadBitmapFromResource('IDB_GREENCIRCLES');
    bGreenCircle.MasterAlpha := 240;
    bGreenCircle.DrawMode := dmBlend;
  end;

  if not Assigned(bRedArrow) then begin
    bRedArrow := LoadBitmapFromResource('IDB_REDARROW');
    bRedArrow.MasterAlpha := 240;
    bRedArrow.DrawMode := dmBlend;
  end;

  if not Assigned(bGreenArrow) then begin
    bGreenArrow := LoadBitmapFromResource('IDB_GREENARROW');
    bGreenArrow.MasterAlpha := 240;
    bGreenArrow.DrawMode := dmBlend;
  end;

  if not Assigned(bSell) then begin
    bSell := LoadBitmapFromResource('IDB_REDORDER');
    bSell.MasterAlpha := 240;
    bSell.DrawMode := dmBlend;

     // ������� ����� ������ �������
    bSellGray := TBitmap32.Create;
    bSellGray.Assign(bSell);
    Desaturate32(bSellGray);
  end;

  if not Assigned(bBuy) then begin
    bBuy := LoadBitmapFromResource('IDB_GREENORDER');
    bBuy.MasterAlpha := 240;
    bBuy.DrawMode := dmBlend;

    bBuyGray := TBitmap32.Create;
    bBuyGray.Assign(bBuy);
    Desaturate32(bBuyGray);
  end;

  if not Assigned(bStop) then begin
    bStop := LoadBitmapFromResource('IDB_STOP');
    bStop.MasterAlpha := 140;
    bStop.DrawMode := dmBlend;
  end;

  if not Assigned(bRedDeal) then begin
    bRedDeal := LoadBitmapFromResource('IDB_REDDEAL');
    bRedDeal.MasterAlpha := 240;
    bRedDeal.DrawMode := dmBlend;
  end;

  if not Assigned(bGreenDeal) then begin
    bGreenDeal := LoadBitmapFromResource('IDB_GREENDEAL');
    bGreenDeal.MasterAlpha := 240;
    bGreenDeal.DrawMode := dmBlend;
  end;

finalization
  FreeAndNil(bRedCircle);
  FreeAndNil(bGreenCircle);
  FreeAndNil(bRedArrow);
  FreeAndNil(bGreenArrow);
  FreeAndNil(bSell);
  FreeAndNil(bBuy);
  FreeAndNil(bSellGray);
  FreeAndNil(bBuyGray);
  FreeAndNil(bStop);
  FreeAndNil(bRedDeal);
  FreeAndNil(bGreenDeal);
end.
