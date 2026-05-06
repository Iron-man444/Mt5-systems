//+------------------------------------------------------------------+
//|                                     TheStrat_Form1_InsideBar.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <MovingAverages.mqh>

input group "=== 1. TEMEL AYARLAR ==="
input double RiskPerTrade = 0.0;          
input double FixedLotSize = 0.1;          
input double MaxRiskPercent = 5.0;        
input int MagicNumber = 111111;           // F1 için özel Kimlik No
input int MaxPositions = 3;               

input group "=== 2. FİLTRE KONTROLLERİ ==="
input bool Use_EMA_Filter = true;         
input bool Use_RSI_Filter = true;         
input bool Use_ATR_Filter = false;        

input group "=== 3. İNDİKATÖR AYARLARI ==="
input int EMA_Fast_Period = 20;           
input int EMA_Slow_Period = 50;           
input int RSI_Period = 14;                
input int RSI_Level_Bullish = 50;         
input int RSI_Level_Bearish = 50;         
input int ATR_Period = 14;                
input double ATR_Multiplier_SL = 1.5;     
input double Min_ATR_Level = 0.0005;      

input group "=== 4. ZAMAN AYARLARI ==="
input bool Use_Time_Filter = true;        
input int Trade_Start_Hour = 8;           
input int Trade_Start_Minute = 0;         
input int Trade_End_Hour = 22;            
input int Trade_End_Minute = 0;           

input group "=== 5. ÇIKIŞ VE TAKİP AYARLARI ==="
input int TP_Trigger_Points = 200;        
input int Tight_Trailing_Points = 15;     

input group "=== 6. FORMASYON KONTROLÜ ==="
input bool Use_Formation_1 = true;        // Formasyon 1: Inside Bar Aktif mi?
input int Entry_Buffer_Points = 20;       // Kırılım teyidi için mesafe (Point)


CTrade trade;
int handleATR, handleEMA_Fast, handleEMA_Slow, handleRSI;
datetime lastTradeBarTime = 0;         

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   handleATR = iATR(_Symbol, _Period, ATR_Period);
   handleEMA_Fast = iMA(_Symbol, _Period, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, _Period, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   
   Print("TheStrat Formasyon 1 (Inside Bar) Başlatıldı.");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   ManageAllPositions();
   
   if(!IsTradingTime() || CountPositions() >= MaxPositions || (MaxRiskPercent > 0 && GetTotalRiskPercent() >= MaxRiskPercent)) return;
   
   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, 10, rates) < 10) return;

   double atr[], emaFast[], emaSlow[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   
   CopyBuffer(handleATR, 0, 0, 2, atr);
   CopyBuffer(handleEMA_Fast, 0, 0, 3, emaFast);
   CopyBuffer(handleEMA_Slow, 0, 0, 3, emaSlow);

   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double riskDistance = atr[1] * ATR_Multiplier_SL;

   bool trendUp = (emaFast[0] > emaSlow[0] && emaFast[1] > emaSlow[1]);
   bool trendDown = (emaFast[0] < emaSlow[0] && emaFast[1] < emaSlow[1]);
   bool emaBuyOk = !Use_EMA_Filter || trendUp;
   bool emaSellOk = !Use_EMA_Filter || trendDown;
   bool atrOk = !Use_ATR_Filter || atr[0] >= Min_ATR_Level;

   if(!atrOk) return;

   // ================= FORMASYON 1 (INSIDE BAR) =================
   if(Use_Formation_1 && lastTradeBarTime != currentBarTime)
   {
      // 1. Bar, 2. Bar'ın içinde mi? (Inside Bar Kontrolü)
      if(rates[1].high < rates[2].high && rates[1].low > rates[2].low) 
      {
         // Hedef giriş seviyelerini Buffer ekleyerek belirle
         double buyTriggerPrice = rates[1].high + (Entry_Buffer_Points * _Point);
         double sellTriggerPrice = rates[1].low - (Entry_Buffer_Points * _Point);

         // Alış (Buy) Şartı
         if(Ask > buyTriggerPrice && emaBuyOk) 
         {
            if(ExecuteTrade(ORDER_TYPE_BUY, Ask, riskDistance, "Form 1: InsideBar UP (Buffered)"))
               lastTradeBarTime = currentBarTime;
         }
         // Satış (Sell) Şartı
         else if(Bid < sellTriggerPrice && emaSellOk) 
         {
            if(ExecuteTrade(ORDER_TYPE_SELL, Bid, riskDistance, "Form 1: InsideBar DOWN (Buffered)"))
               lastTradeBarTime = currentBarTime;
         }
      }
   }
   
   }

bool ExecuteTrade(ENUM_ORDER_TYPE orderType, double price, double riskDistance, string comment)
{
   double sl = 0, tp = 0; 
   double slPoints = riskDistance / _Point;
   double calculatedLot = GetDynamicLotSize(slPoints);
   
   if(orderType == ORDER_TYPE_BUY) {
      sl = NormalizeDouble(price - riskDistance, _Digits);
      return trade.Buy(calculatedLot, _Symbol, price, sl, tp, comment);
   } else {
      sl = NormalizeDouble(price + riskDistance, _Digits);
      return trade.Sell(calculatedLot, _Symbol, price, sl, tp, comment);
   }
}

bool IsTradingTime()
{
   if(!Use_Time_Filter) return true; 
   MqlDateTime dt; TimeCurrent(dt);
   int currentMins = dt.hour * 60 + dt.min;
   int startMins = Trade_Start_Hour * 60 + Trade_Start_Minute;
   int endMins = Trade_End_Hour * 60 + Trade_End_Minute;
   if(startMins < endMins) return (currentMins >= startMins && currentMins <= endMins);
   else return (currentMins >= startMins || currentMins <= endMins);
}

double GetDynamicLotSize(double slDistancePoints)
{
   if(RiskPerTrade <= 0) return FixedLotSize; 
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (RiskPerTrade / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slDistancePoints <= 0 || tickValue <= 0) return FixedLotSize;
   double lot = riskAmount / (slDistancePoints * tickValue);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathRound(lot / stepLot) * stepLot;
   if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)) lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return lot;
}

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

      if(profitPoints >= TP_Trigger_Points) {
         double newSL = 0;
         if(posType == POSITION_TYPE_BUY) {
            newSL = NormalizeDouble(curPrice - (Tight_Trailing_Points * _Point), _Digits);
            if(newSL > sl + (2 * _Point)) trade.PositionModify(ticket, newSL, 0);
         } else {
            newSL = NormalizeDouble(curPrice + (Tight_Trailing_Points * _Point), _Digits);
            if((newSL < sl - (2 * _Point)) || sl == 0) trade.PositionModify(ticket, newSL, 0);
         }
      }
   }
}

int CountPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
   return count;
}

double GetTotalRiskPercent()
{
   double totalRisk = 0;
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         double riskPoints = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - PositionGetDouble(POSITION_SL)) / _Point;
         totalRisk += (riskPoints * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * PositionGetDouble(POSITION_VOLUME));
      }
   }
   if(accountEquity > 0) return (totalRisk / accountEquity) * 100.0;
   return 0;
}