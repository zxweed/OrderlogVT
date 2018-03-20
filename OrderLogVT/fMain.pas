unit fMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms, Math, Axis, GR32, Config,
  Dialogs, VirtualTrees, ImgList, ComCtrls, ToolWin, GR32_Image, ExtCtrls, uIntList, SeriesIntf, TradeDraw32,
  ActnList;

const
  F_DT_MARGIN = 1/24/60/60;
  S_REG_KEY   = '\Software\nTick\OrderLogVT';

type
  TFileHeader = packed record
    Count: Integer;     // Количество записей в файле тип integer (4 байта)
    Rev: Int64;         // Ревизия последней вставленной записи тип Int64 (8 байт)
  end;

  TFullLogDataRow = packed record
    LocalTime: TDateTime;       // локальная метка времени
    ServerTime: TDateTime;      // серверная метка времени
    OrderID: Int64;             // номер заявки
    ISIN_ID: Integer;           // идентификатор инструмента
    Price: Double;              // цена заявки
    Action: Byte;               // действие  0-Заявка удалена 1-Заявка добавлена 2-Заявка сведена в сделку
    Status: Integer;            // статус заявки  0x01 Котировочная  0x02 Встречная  0x04 Внесистемная (другие статусы описаны ниже)
    Dir: Byte;                  // направление заявки (покупка или продажа)
    Amount: Integer;            // количество в операции
    AmountRest:Integer;         // оставшееся количество
    DealPrice: Double;          // цена сделки
    DealID: Int64;              // идентификатор сделки
  end;

  TForm1 = class(TForm)
    VST: TVirtualStringTree;
    gSnap: TVirtualStringTree;
    Splitter1: TSplitter;
    bSnapChart: TImage32;
    Splitter2: TSplitter;
    ToolBar: TToolBar;
    bOpen: TToolButton;
    Icons: TImageList;
    dlgOpen: TOpenDialog;
    Splitter3: TSplitter;
    bTickChart: TImage32;
    bProcess: TToolButton;
    Splitter4: TSplitter;
    bSnapOrders: TImage32;
    ActionList: TActionList;
    actOpen: TAction;
    actProcess: TAction;
    procedure actOpenExecute(Sender: TObject);
    procedure actProcessExecute(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure bTickChartResize(Sender: TObject);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta:
        Integer; MousePos: TPoint; var Handled: Boolean);
    procedure gSnapDrawText(Sender: TBaseVirtualTree; TargetCanvas: TCanvas; Node:
        PVirtualNode; Column: TColumnIndex; const Text: string; const CellRect:
        TRect; var DefaultDraw: Boolean);
    procedure gSnapGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column:
        TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure VSTDrawText(Sender: TBaseVirtualTree; TargetCanvas: TCanvas; Node:
        PVirtualNode; Column: TColumnIndex; const Text: string; const CellRect:
        TRect; var DefaultDraw: Boolean);
    procedure VSTGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
  private
    F: TFileStream;
    FCount: Int64;
    FSnapList: TIntList;
    FLastOrderID: Int64;
    FTradeT: TTradeSeries;
    FFutDateAxis: TAxis;                    // Оси координат
    FLastDateAxis: TAxis;
    FVolKoeff: Double;
    FPriceAxis: TAxis;
    FSnapDT: TDateTime;                     // Текущее время

    function GetMedianPrice: Integer;
  public
    function LoadRow (AIndex: Int64): TFullLogDataRow;
    procedure Process_ToCursor;
    procedure ProcessRow (ARow: TFullLogDataRow);
    procedure AddToSnap (AOrderID: Int64; APrice: Integer; AVolume: Integer);
    procedure DrawOrders(const ABitmap: TBitmap32; AIndex: Int64; AVertAxis, AHorzAxis: TAxis; AVolKoeff: Double);
    procedure Redraw(AIndex: Int64);
  end;

var
  Form1: TForm1;

implementation

uses fChart;

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  FFutDateAxis := CreateAxis (bSnapOrders.Bitmap, axBottom);
  FLastDateAxis := CreateAxis (bTickChart.Bitmap, axBottom);
  FPriceAxis := CreateAxis (bSnapOrders.Bitmap);
  FVolKoeff := 4;

  FSnapList := TIntList.Create;
  FSnapList.Sorted := True;
  FSnapList.OwnObjects := True;
  LoadFromRegistry(S_REG_KEY, Self);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FreeAndNil(F);
  FreeAndNil(FSnapList);
  SaveToRegistry(S_REG_KEY, Self);
end;

function TForm1.LoadRow (AIndex: Int64): TFullLogDataRow;
var
  I: Int64;
begin
  I := SizeOf(TFileHeader) + AIndex * SizeOf(TFullLogDataRow);
  F.Seek (I, soFromBeginning);
  F.Read(Result, SizeOf(TFullLogDataRow));
end;

function DecodeStatus (AStatus: Integer): string;
 { Декодирует статус заявки: }
begin
  Result := '';
  if AStatus and $01 <> 0 then Result := 'Q' + Result;          // 0x01 Котировочная
  if AStatus and $02 <> 0 then Result := 'C' + Result;          // 0x02 Встречная
  if AStatus and $04 <> 0 then Result := 'O' + Result;          // 0x04 Внесистемная
  if AStatus and $08 <> 0 then Result := 'R' + Result;          // 0x08 RFQ. Запрос на котировку
  if AStatus and $10 <> 0 then Result := 'T' + Result;          // 0x10 RFQ. Время истекло

  if AStatus and $400 <> 0 then Result := '?' + Result;          // неописанный бит

  if AStatus and $001000 <> 0 then Result := 'L' + Result;      // 0x1000 Запись является последней в транзакции
  if AStatus and $080000 <> 0 then Result := 'F' + Result;      // 0x00080000 Заявка Fill-or-kill
  if AStatus and $100000 <> 0 then Result := 'M' + Result;      // 0x100000 Запись является результатом операции перемещения заявки
  if AStatus and $200000 <> 0 then Result := 'D' + Result;      // 0x200000 Запись является результатом операции удаления заявки
  if AStatus and $400000 <> 0 then Result := 'G' + Result;      // 0x400000 Запись является результатом группового удаления
  if AStatus and $20000000 <> 0 then Result := 'X' + Result;    // 0x2000000 Признак удаления остатка заявки по причине кросс-сделки
end;

function DecodeDir (ADir: Byte): string;
begin
  case ADir of
    1: Result := 'Buy';
    2: Result := 'Sell';
  end;
end;

procedure TForm1.VSTGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  R: TFullLogDataRow;
begin
  R := LoadRow(Node.Index);
  case Column of
    0: CellText := FormatDateTime('DD.MM.YY hh:nn:ss.zzz', R.ServerTime);
    1: CellText := IntToStr(Trunc(R.Price));
    2: CellText := IntToStr(R.Action);
    3: CellText := Format('$%s %6s', [IntToHex(R.Status, 4), DecodeStatus(R.Status), 6]);
    4: CellText := Format ('%d - %s', [R.Dir, DecodeDir(R.Dir)]);
    5: CellText := IntToStr(R.Amount);
    6: CellText := IntToStr(R.AmountRest);
    7: CellText := IntToStr(Trunc(R.DealPrice));
    8: CellText := IntToStr(R.DealID);
  end;
end;

procedure TForm1.VSTDrawText(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
    Node: PVirtualNode; Column: TColumnIndex; const Text: string; const
    CellRect: TRect; var DefaultDraw: Boolean);
begin
  if Column = 4 then
    if Pos('Sell', Text) <> 0 then
      TargetCanvas.Font.Color := clRed
    else if Pos('Buy', Text) <> 0 then
      TargetCanvas.Font.Color := clGreen;
end;

procedure TForm1.AddToSnap (AOrderID: Int64; APrice: Integer; AVolume: Integer);
var
  K: Integer;
  S: TIntList;
begin
  if FSnapList.Find(APrice, K) then
    S := TIntList(FSnapList.Objects[K])
  else begin
    S := TIntList.Create;
    S.Sorted := False;                // Объемы ордеров хранятся строго в порядке поступления
    FSnapList.AddObject(APrice, S);
  end;
  S.AddObject(AOrderID, Pointer(AVolume));
end;

procedure TForm1.ProcessRow (ARow: TFullLogDataRow);
var
  K, nVol: Integer;
  T: TTrade;
  S: TIntList;
begin
  if ARow.Status and $04 <> 0 then Exit;         // Внесистемные тоже пропускаем

  FSnapDT := ARow.ServerTime;
  if ARow.Dir = 2 then nVol := -ARow.Amount else nVol := ARow.Amount;

   // Обрабатываем стакан
  K := -1;
  case ARow.Action of
    1: begin     // Добавление заявки по цене
      AddToSnap(ARow.OrderID, Trunc(ARow.Price), nVol);
      FLastOrderID := ARow.OrderID;
    end;

    0, 2: begin     // Удаление заявки (возможно, со сделкой)
      K := FSnapList.IndexOf(Trunc(ARow.Price));
      if K >= 0 then begin
        S := TIntList(FSnapList.Objects[K]);
        if S.Find(ARow.OrderID, K) then case ARow.Action of
          0: S.Delete(K);     // Удаление снятого ордера

          {2: begin     // Выключено для поддержки кривых логов от цериха
               if S.Values[K] - nVol = ARow.AmountRest * Sign(nVol)
                 then S.Values[K] := S.Values[K] - nVol
                 else Exception.Create(Format('OrderID=%d at Price=%d not match amount', [ARow.OrderID, Trunc(ARow.Price)]));

               if ARow.AmountRest = 0 then S.Delete(K);
             end; }

           2: begin
                S.Values[K] := S.Values[K] - nVol;
                if S.Values[K] = 0 then S.Delete(K);
              end;

        end else
          raise Exception.Create(Format('OrderID=%d at Price=%d not found', [ARow.OrderID, Trunc(ARow.Price)]));
      end else
        raise Exception.Create('Price not found');

       // Выгружаем сделку в поток
      if (ARow.Action = 2) and (ARow.OrderID = FLastOrderID) then begin
        T.DateTime := ARow.ServerTime;
        T.Price := ARow.DealPrice;
        if ARow.Dir = 2 then T.Volume := -ARow.Amount else T.Volume := ARow.Amount;
        AppendValue(FTradeT, T);
      end;
    end;
  end;

   // Удаляем нулевые строки из стакана
  K := 0;
  while K < FSnapList.Count do begin
    S := TIntList(FSnapList.Objects[K]);
    if S.Count = 0 then begin
      FreeAndNil(S);
      FSnapList.Delete(K);
    end else
      Inc (K);
  end;
end;

procedure DrawPrepare(const ABitmap: TBitmap32; const ASnap: TIntList; const AVertAxis: TAxis);
var
  fPrice, fStepPrice: Double;
  nY: Integer;
  K: Integer;
  nMedian: Integer;
  nPriceStepHeight: Integer;
  S: TIntList;
begin
  with ABitmap do begin
    BeginUpdate;
    Clear(Color32(clCream));

    fStepPrice := 10; //GetPriceStep (AsSnap(ASnap));
    nPriceStepHeight := AVertAxis.RangeToWidth (fStepPrice);

     // Фоны
    nMedian := 0;
    for K := 0 to ASnap.Count-1 do begin
      S := ASnap.Objects[K] as TIntList;
      if Assigned(S) and (S.Values[0] < 0) then begin
        nMedian := K;
        Break;
      end;
    end;

    fPrice := ASnap[nMedian];
    nY := AVertAxis.ValueToPixel (fPrice) + nPriceStepHeight div 2 - 1;
    FillRectS (0, 0, Width, nY, $FFFFE5E5);

    if (nMedian > 0) and (nMedian < ASnap.Count) then begin
      fPrice := ASnap[nMedian-1];
      nY := AVertAxis.ValueToPixel (fPrice) - nPriceStepHeight div 2 - 1;
      FillRectS (0, nY, Width, Height, $FFE5FFE5);
    end;
    EndUpdate;
    Changed;
  end;
end;

procedure TForm1.DrawOrders(const ABitmap: TBitmap32; AIndex: Int64; AVertAxis, AHorzAxis: TAxis; AVolKoeff: Double);
var
  R: TFullLogDataRow;
  nY, nY1, nY2, nX1, nX2: Integer;
  nColor: DWORD;
  fStepPrice: Double;
  I, nPriceStepHeight: Integer;
  DT: TDateTime;
begin
  fStepPrice := 10; //GetPriceStep (AsSnap(ASnap));
  if fStepPrice = 0 then fStepPrice := 1;
  nPriceStepHeight := AVertAxis.RangeToWidth (fStepPrice);

  with ABitmap do begin
    BeginUpdate;
    R := LoadRow(AIndex);

     // Сетка времени
    DT := FrameStart(AHorzAxis.Minimum, 0.1);
    while DT < AHorzAxis.Maximum do begin
      nX1 := AHorzAxis.ValueToPixel(DT);
      if nX1 > 0 then VertLine(nX1, 0, Height-1, $FFCCCCCC);
      DT := DT + 0.1/24/60/60;
      Textout(nX1 + 5, Height - 20, FormatDateTime('hh:nn:ss.zzz', DT));
    end;

     // Ордера
    for I := AIndex to AIndex + 10000 do begin
      R := LoadRow(I);
      nY := AVertAxis.ValueToPixel (R.Price);
      nY1 := nY - nPriceStepHeight div 2;
      nY2 := nY + nPriceStepHeight div 2;
      nX1 := AHorzAxis.ValueToPixel(R.LocalTime);
      nX2 := nX1 + Round(R.Amount * AVolKoeff);
      case R.Action of
        0: begin
          if R.Dir = 2 then nColor := $FFFF8888 else nColor := $FF88FF88;

          FillRectS (nX1, nY1, nX2, nY2, nColor);
          RaiseRectTS (nX1, nY1, nX2, nY2, 20);
        end;
        1: begin     // Добавление заявки по цене
          if R.Dir = 2 then nColor := clRed32 else nColor := clGreen32;

          FillRectS (nX1, nY1, nX2, nY2, nColor);
          RaiseRectTS (nX1, nY1, nX2, nY2, 20);
        end;
      end;
    end;

    EndUpdate;
    Changed;
  end;
end;

procedure DrawSnap1 (const ABitmap: TBitmap32; const ASnap: TIntList; AVertAxis: TAxis; AVolKoeff: Double; AMaxVol: Integer);
 { Рисует на битмапе стакан }
const
  fVolMargin = 0.3;            // Относительная ширина полей с объемом
var
  fPrice, fStepPrice: Double;
  nY, nY1, nW, nY2, nX1, nX2, K: Integer;
  nColor: DWORD;
  I, nPriceStepHeight: Integer;
  S: TIntList;
begin
  if not Assigned(ABitmap) or (ASnap.Count = 0) then Exit;

  fStepPrice := 10; //GetPriceStep (AsSnap(ASnap));
  if fStepPrice = 0 then fStepPrice := 1;
  nPriceStepHeight := AVertAxis.RangeToWidth (fStepPrice);

  with ABitmap do begin
    DrawGrid (ABitmap, AVertAxis, fStepPrice);

    BeginUpdate;
    for I := 0 to ASnap.Count - 1 do begin
      S := ASnap.Objects[I] as TIntList;
      if not Assigned(S) then Continue;

      fPrice := ASnap[I];
      nY := AVertAxis.ValueToPixel (fPrice);
      nY1 := nY - nPriceStepHeight div 2;
      nY2 := nY + nPriceStepHeight div 2;
      nX2 := Width;

      for K := 0 to S.Count - 1 do begin
//        nW := Round(LogN(1.1, Abs(S.Values[K]))+1);
        nW := Round(Abs(S.Values[K]) * AVolKoeff);
        nX1 := nX2 - nW;

        if S.Values[K] > 0 then nColor := clGreen32 else nColor := clRed32;
        FillRectS (nX1, nY1, nX2, nY2, nColor);
        RaiseRectTS (nX1, nY1, nX2, nY2, 20);

        Dec (nX2, nW+1);
      end;
    end;
    EndUpdate;
    Changed;
  end;
end;

procedure TForm1.bTickChartResize(Sender: TObject);
var
  Img: TImage32;
begin
  Img := Sender as TImage32;
  Img.Bitmap.Width := Img.Width;
  Img.Bitmap.Height := Img.Height;

  Img.Bitmap.Clear(clCream);
end;

function ListToStr (const S: TIntList): string;
var
  I: Integer;
begin
  Result := '';
  if Assigned(S) then
    for I := 0 to S.Count - 1 do
      if S.Values[I] >= 0
        then Result := Result + '+' + IntToStr(S.Values[I])
        else Result := Result + IntToStr(S.Values[I]);
end;

procedure TForm1.actOpenExecute(Sender: TObject);
var
  H: TFileHeader;
begin
  if dlgOpen.Execute then begin
    FreeAndNil(F);
    F := TFileStream.Create (dlgOpen.FileName, fmOpenRead);

     // Читаем заголовок
    F.ReadBuffer(H, SizeOf(H));
    FCount := H.Count;
    VST.RootNodeCount := FCount;
  end;
end;

procedure TForm1.actProcessExecute(Sender: TObject);
begin
  Process_ToCursor;
end;

procedure TForm1.FormMouseWheel(Sender: TObject; Shift: TShiftState;
    WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  fK, fStep: Double;
begin
  with FPriceAxis do begin
    fK := Abs ((Maximum - Value) / (Value - Minimum));
    fStep := Range * 0.015;
    Minimum := Minimum + Sign(WheelDelta) * fStep;
    Maximum := Maximum - Sign(WheelDelta) * fStep * fK;
  end;
  if Assigned(VST.FocusedNode) then Redraw(VST.FocusedNode.Index);
end;

function TForm1.GetMedianPrice: Integer;
var
  I: Integer;
begin
  I := 0;
   // ищем первую цену BID
  while (I < FSnapList.Count) and (Pos ('-', ListToStr(TIntList(FSnapList.Objects[I]))) = 0) do Inc(I);

  Result := FSnapList[I];
end;

procedure TForm1.gSnapDrawText(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
    Node: PVirtualNode; Column: TColumnIndex; const Text: string; const
    CellRect: TRect; var DefaultDraw: Boolean);
begin
  if Column = 1 then
    if Pos('-', Text) <> 0 then
      TargetCanvas.Font.Color := clRed
    else if Pos('+', Text) <> 0 then
      TargetCanvas.Font.Color := clGreen;
end;

procedure TForm1.gSnapGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
    Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  S: TIntList;
  Str: string;
  I: Integer;
begin
  if FSnapList.Count = 0 then Exit;

  I := (FSnapList.Count-1) - Node.Index;         // Переворачиваем стакан
  S := TIntList(FSnapList.Objects[I]);
  Str := ListToStr(S);

  case Column of
    0: CellText := IntToStr(FSnapList[I]);

    1: if Pos('+', Str) <> 0 then
          CellText := Str
       else if Pos('-', Str) <> 0 then
         CellText := Str
       else
         CellText := '';
  end;
end;

procedure TForm1.Redraw(AIndex: Int64);
var
  fMedian: Double;
begin
  fMedian := GetMedianPrice;
  FPriceAxis.SetRange (fMedian - 800, fMedian + 800);

  FFutDateAxis.SetRange (FSnapDT, FSnapDT + F_DT_MARGIN);
  FLastDateAxis.SetRange (FSnapDT - F_DT_MARGIN*60, FSnapDT + F_DT_MARGIN);

  DrawPrepare(bSnapChart.Bitmap, FSnapList, FPriceAxis);
  DrawPrepare(bSnapOrders.Bitmap, FSnapList, FPriceAxis);

  DrawSnap1(bSnapChart.Bitmap, FSnapList, FPriceAxis, FVolKoeff, 300);
  DrawOrders(bSnapOrders.Bitmap, AIndex, FPriceAxis, FFutDateAxis, FVolKoeff);

  DrawTickDeals(bTickChart.Bitmap, FTradeT, FLastDateAxis, FPriceAxis);
end;

procedure TForm1.Process_ToCursor;
 { Обработка от начала до курсора }
var
  I: Int64;
begin
  FSnapList.Clear;
  SetLen(FTradeT, 0);
  FLastOrderID := 0;

  I := 0;
  while Assigned(VST.FocusedNode) and (I < VST.FocusedNode.Index) do begin
    ProcessRow (LoadRow(I));
    Inc(I);
  end;

  if Assigned(VST.FocusedNode) then Redraw(VST.FocusedNode.Index);

  gSnap.RootNodeCount := FSnapList.Count;
  Application.ProcessMessages;
end;

end.

