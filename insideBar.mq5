//+------------------------------------------------------------------+
//|                                     TheStrat_InsideBar_Only.mq5  |
//|                                 Copyright 2026, Bunyamin Demir   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "6.10" // Inside Bar + Market Kapanış Koruması + Zaman Dilimi + Point SL
#property strict

#include <Trade\Trade.mqh>
#include <MovingAverages.mqh>

//--- 1. TEMEL AYARLAR (Lot, Risk ve Zaman Dilimi)
input group "=== 1. TEMEL AYARLAR ==="
input ENUM_TIMEFRAMES Trade_Timeframe = PERIOD_CURRENT; // İşlem Zaman Dilimi (Optimizasyon için)
input double RiskPerTrade = 0.0;          // İşlem Başına Risk % (0 ise Sabit Lot kullanır)
input double FixedLotSize = 0.1;          // Sabit Lot Miktarı
input double MaxRiskPercent = 5.0;        // Toplam Maksimum Risk Limiti (%)
input int MagicNumber = 777777;           // EA Kimlik No
input int MaxPositions = 3;               // Maksimum Pozisyon Sayısı

//--- 2. FİLTRE KONTROLLERİ (Aç/Kapat)
input group "=== 2. FİLTRE KONTROLLERİ ==="
input bool Use_EMA_Filter = true;         // EMA Trend Filtresi Aktif mi?
input bool Use_ATR_Filter = false;        // ATR Hacim/Volatilite Filtresi Aktif mi?

//--- 3. İNDİKATÖR VE STOP AYARLARI
input group "=== 3. İNDİKATÖR VE STOP AYARLARI ==="
input int SL_Points = 150;                // Stop Loss Mesafesi (Point)
input int EMA_Fast_Period = 20;           // Hızlı EMA Periyodu
input int EMA_Slow_Period = 50;           // Yavaş EMA Periyodu
input int ATR_Period = 14;                // ATR Periyodu
input double Min_ATR_Level = 0.0005;      // ATR Filtresi açıksa gereken minimum değer

//--- 4. ZAMAN VE KAPANIŞ AYARLARI
input group "=== 4. ZAMAN AYARLARI ==="
input bool Use_Time_Filter = true;        // Zaman Filtresi Aktif mi?
input int Trade_Start_Hour = 8;           // İşlem Başlama Saati
input int Trade_Start_Minute = 0;         // İşlem Başlama Dakikası
input int Trade_End_Hour = 22;            // İşlem Bitiş Saati
input int Trade_End_Minute = 0;           // İşlem Bitiş Dakikası
input bool Use_Auto_Close = true;         // Gün Sonu Otomatik Kapatma Aktif mi?
input int Auto_Close_Hour = 23;           // Piyasa Kapanış Saati (Broker Saati)
input int Auto_Close_Minute = 55;         // Kapanıştan 5 dk öncesi için dakika

//--- 5. ÇIKIŞ VE TAKİP AYARLARI
input group "=== 5. ÇIKIŞ VE TAKİP AYARLARI ==="
input int TP_Trigger_Points = 200;        // Hedef Bölgesi (Point) - TP OLMAZ, STOP ÇEKER
input int Tight_Trailing_Points = 15;     // Hedefe Ulaşınca Devreye Girecek Sıkı Stop (Point)

//--- Global Değişkenler
CTrade trade;
int handleATR, handleEMA_Fast, handleEMA_Slow;
datetime lastTradeBarTime = 0;            

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   
   // İndikatörleri seçilen zaman dilimine (Trade_Timeframe) göre ayarla
   handleATR = iATR(_Symbol, Trade_Timeframe, ATR_Period);
   handleEMA_Fast = iMA(_Symbol, Trade_Timeframe, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, Trade_Timeframe, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   Print("TheStrat Inside Bar Özel Sürüm Başlatıldı. Zaman Dilimi: ", EnumToString(Trade_Timeframe));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 0. Gün sonu kapanış kontrolü (5 dk kala her şeyi kapat)
   if(Use_Auto_Close) CheckMarketClose();

   // 1. Açık Pozisyonları Yönet (Hedefe ulaşınca 15 puanlık stoploss devreye girer)
   ManageAllPositions();
   
   // 2. Zaman Filtresi Kontrolü
   if(!IsTradingTime()) return;

   // 3. Maksimum pozisyon, Risk ve Makineli Tüfek kontrolü
   if(CountPositions() >= MaxPositions) return;
   if(MaxRiskPercent > 0 && GetTotalRiskPercent() >= MaxRiskPercent) return;
   
   // Mum kapanış kontrolünü seçili zaman dilimine göre yap
   datetime currentBarTime = iTime(_Symbol, Trade_Timeframe, 0);
   if(lastTradeBarTime == currentBarTime) return;

   // 4. Veri ve İndikatör Okuma (Seçili Zaman Diliminden)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, Trade_Timeframe, 0, 10, rates) < 10) return;

   double atr[], emaFast[], emaSlow[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   
   CopyBuffer(handleATR, 0, 0, 2, atr);
   CopyBuffer(handleEMA_Fast, 0, 0, 3, emaFast);
   CopyBuffer(handleEMA_Slow, 0, 0, 3, emaSlow);

   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   
   // Point bazlı risk mesafesi hesaplama
   double riskDistance = SL_Points * _Point;

   // --- FİLTRE MANTIKLARI ---
   bool trendUp = (emaFast[0] > emaSlow[0] && emaFast[1] > emaSlow[1]);
   bool trendDown = (emaFast[0] < emaSlow[0] && emaFast[1] < emaSlow[1]);
   
   bool emaBuyOk = !Use_EMA_Filter || trendUp;
   bool emaSellOk = !Use_EMA_Filter || trendDown;
   bool atrOk = !Use_ATR_Filter || atr[0] >= Min_ATR_Level;

   if(!atrOk) return;

   // --- THE STRAT FORMASYON 1: INSIDE BAR SADECE ---
   // Şart: 1. mumun yükseği 2. mumdan küçük VE 1. mumun düşüğü 2. mumdan büyük
   if(rates[1].high < rates[2].high && rates[1].low > rates[2].low)
   {
      // Yukarı Kırılım (Buy)
      if(Ask > rates[1].high && emaBuyOk) 
      {
         ExecuteTrade(ORDER_TYPE_BUY, Ask, riskDistance, "InsideBar Breakout UP");
      }
      // Aşağı Kırılım (Sell)
      else if(Bid < rates[1].low && emaSellOk) 
      {
         ExecuteTrade(ORDER_TYPE_SELL, Bid, riskDistance, "InsideBar Breakout DOWN");
      }
   }
}

//+------------------------------------------------------------------+
//| Market Kapanışına 5 Dk Kala Tüm İşlemleri Kapatma                |
//+------------------------------------------------------------------+
void CheckMarketClose()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.hour == Auto_Close_Hour && dt.min >= Auto_Close_Minute)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Zaman Filtresi Fonksiyonu                                        |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!Use_Time_Filter) return true; 
   MqlDateTime dt;
   TimeCurrent(dt);
   int currentMins = dt.hour * 60 + dt.min;
   int startMins = Trade_Start_Hour * 60 + Trade_Start_Minute;
   int endMins = Trade_End_Hour * 60 + Trade_End_Minute;
   
   if(startMins < endMins) return (currentMins >= startMins && currentMins <= endMins);
   else return (currentMins >= startMins || currentMins <= endMins);
}

//+------------------------------------------------------------------+
//| Dinamik Lot Hesaplama Fonksiyonu                                 |
//+------------------------------------------------------------------+
double GetDynamicLotSize(double slDistancePoints)
{
   if(RiskPerTrade <= 0) return FixedLotSize; 
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (RiskPerTrade / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slDistancePoints <= 0 || tickValue <= 0) return FixedLotSize;
   
   double lot = riskAmount / (slDistancePoints * tickValue);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathRound(lot / stepLot) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//+------------------------------------------------------------------+
//| İşlem Açma Fonksiyonu                                            |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, double price, double riskDistance, string comment)
{
   double sl = 0;
   double tp = 0; // Gerçek TP yok, sanal TP (Trailing Stop) var.
   double slPoints = riskDistance / _Point;
   double calculatedLot = GetDynamicLotSize(slPoints);
   
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(price - riskDistance, _Digits);
      if(trade.Buy(calculatedLot, _Symbol, price, sl, tp, comment))
      {
         lastTradeBarTime = iTime(_Symbol, Trade_Timeframe, 0); 
         Print("BUY açıldı: Lot=", calculatedLot, " Price=", price);
      }
   }
   else
   {
      sl = NormalizeDouble(price + riskDistance, _Digits);
      if(trade.Sell(calculatedLot, _Symbol, price, sl, tp, comment))
      {
         lastTradeBarTime = iTime(_Symbol, Trade_Timeframe, 0); 
         Print("SELL açıldı: Lot=", calculatedLot, " Price=", price);
      }
   }
}

//+------------------------------------------------------------------+
//| Pozisyon Yönetimi (TP Bölgesinde 15 Point İzleyen Stop)          |
//+------------------------------------------------------------------+
void ManageAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double curPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profitPoints = (posType == POSITION_TYPE_BUY) ? (curPrice - entry) / _Point : (entry - curPrice) / _Point;

      // 200 puana (TP_Trigger_Points) vurduğu zaman TP olmayacak, 15 puanlık takip eden stoploss olacak.
      if(profitPoints >= TP_Trigger_Points)
      {
         double newSL = 0;
         if(posType == POSITION_TYPE_BUY)
         {
            newSL = NormalizeDouble(curPrice - (Tight_Trailing_Points * _Point), _Digits);
            if(newSL > sl + (2 * _Point)) trade.PositionModify(ticket, newSL, 0);
         }
         else 
         {
            newSL = NormalizeDouble(curPrice + (Tight_Trailing_Points * _Point), _Digits);
            if((newSL < sl - (2 * _Point)) || sl == 0) trade.PositionModify(ticket, newSL, 0);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Güvenlik ve Kontrol Fonksiyonları                                |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
   }
   return count;
}

double GetTotalRiskPercent()
{
   double totalRisk = 0;
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double riskPoints = MathAbs(entry - sl) / _Point;
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         totalRisk += (riskPoints * tickValue * tickSize * volume);
      }
   }
   if(accountEquity > 0) return (totalRisk / accountEquity) * 100.0;
   return 0;
}