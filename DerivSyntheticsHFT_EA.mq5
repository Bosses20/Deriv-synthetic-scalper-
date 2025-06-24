//+------------------------------------------------------------------+
//|                                 DerivSyntheticsHFT_EA.mq5 |
//|                                  Copyright 2023, Jules |
//|                                             AI Trader |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Jules"
#property link      "AI Trader"
#property version   "0.30" // Version for end of Module 3
#property strict

//--- Include potential future libraries (placeholder)
#include <Trade\Trade.mqh> // Standard Trading library
//#include <Trade\AccountInfo.mqh> // Account information

//--- Input parameters (extern variables)
// General Settings
extern int MagicNumber = 12345; // EA's unique identifier for trades
extern string EA_Comment = "DerivHFT_V0.4"; // Comment for trades (Version updated for Module 4)

// Risk Management Settings
sgroup "Risk Management"
extern double MaxRiskPerTradePercent = 1.0; // Maximum risk per trade as a percentage of account balance
extern ENUM_LOT_SIZE_BEHAVIOR SmallAccountMinLotBehavior = LOT_SIZE_BEHAVIOR_SKIP_TRADE; // Behavior when min lot exceeds risk
extern double FixedLotSize = 0.0; // Fixed lot size (if > 0, overrides risk % based calculation)
sgroup ""

// Stop-Loss Settings
sgroup "Stop-Loss Configuration"
extern ENUM_SL_METHOD SL_Method = SL_METHOD_ATR; // Stop-Loss calculation method
extern int SL_FixedPips = 500;                 // Stop-Loss in points (if SL_Method is FixedPips) (Note: V50 1s points, not pips)
extern int SL_ATR_Period = 14;                 // ATR Period (if SL_Method is ATR)
extern double SL_ATR_Multiplier = 1.5;         // ATR Multiplier (if SL_Method is ATR)
extern ENUM_TIMEFRAMES SL_ATR_Timeframe = PERIOD_M5; // Timeframe for ATR calculation
sgroup ""

// Take-Profit Settings
sgroup "Take-Profit Configuration"
extern ENUM_TP_METHOD TP_Method = TP_METHOD_RR;   // Take-Profit calculation method
extern int TP_FixedPips = 1000;                // Take-Profit in points (if TP_Method is FixedPips)
extern double TP_RR_Ratio = 1.5;               // Risk/Reward Ratio (if TP_Method is RR)
sgroup ""

// Trend Filter Settings
sgroup "Trend Filter Configuration"
extern bool EnableTrendFilter = true;                 // Enable/Disable the trend filter
extern ENUM_TIMEFRAMES TrendFilter_Timeframe = PERIOD_M15; // Timeframe for trend filter MA
extern int TrendFilter_MA_Period = 50;                // MA Period for trend filter
extern ENUM_MA_METHOD TrendFilter_MA_Method = MODE_EMA;   // MA Method for trend filter
extern ENUM_APPLIED_PRICE TrendFilter_MA_AppliedPrice = PRICE_CLOSE; // Applied price for trend filter MA
sgroup ""

// Trading Direction Settings
sgroup "Trading Direction"
extern ENUM_TRADE_DIRECTION TradeDirection = TRADE_DIRECTION_BOTH; // Allowable trade directions
sgroup ""

// M1 Entry Logic Settings - Structure Break & Retest
sgroup "M1 Entry: Structure Break & Retest"
extern bool EnableEntry_StructureBreakRetest = true; // Enable/Disable this entry signal
extern int SBR_SwingDetectionPeriod = 5;         // Period for detecting micro swing points (e.g., highest high of last 5 M1 bars)
extern int SBR_RetestWindowBars = 10;            // How many bars after break to wait for retest
extern double SBR_RetestProximityPoints = 50;    // How close price must come to broken level for retest (in points)
extern int SBR_ConfirmationCandlePattern = 0;    // 0: Simple touch/rejection, 1: Pinbar, 2: Engulfing (Future)
extern int SBR_MinBreakoutPoints = 20;           // Minimum points the break must exceed the swing level
sgroup ""

// Trade Execution Settings
sgroup "Trade Execution"
extern int MaxOpenTrades_Initial = 1;     // Maximum initial open trades allowed by this EA instance
extern int SlippagePoints = 10;           // Allowed slippage in points for order execution
sgroup ""


//--- Enumerations for settings
enum ENUM_LOT_SIZE_BEHAVIOR
  {
   LOT_SIZE_BEHAVIOR_USE_MIN_LOT, // Use Minimum Lot (High Risk)
   LOT_SIZE_BEHAVIOR_SKIP_TRADE   // Skip Trade if Risk Exceeded by Min Lot
   // LOT_SIZE_BEHAVIOR_SCALE_DOWN (Future implementation)
  };

enum ENUM_SL_METHOD
  {
   SL_METHOD_FIXED_PIPS, // Fixed Pips/Points
   SL_METHOD_ATR         // ATR Based
  };

enum ENUM_TP_METHOD
  {
   TP_METHOD_FIXED_PIPS, // Fixed Pips/Points
   TP_METHOD_RR          // Risk/Reward Ratio
  };

enum ENUM_TRADE_DIRECTION
  {
   TRADE_DIRECTION_LONG_ONLY, // Only Long trades
   TRADE_DIRECTION_SHORT_ONLY, // Only Short trades
   TRADE_DIRECTION_BOTH         // Both Long and Short trades
  };

//--- Global variables
CTrade trade; // Instance of the CTrade class for trading operations
//CAccountInfo account; // Instance of CAccountInfo for account details

long chart_ID; // To store chart ID
string expert_name; // To store EA name
double current_symbol_point_value; // To store the value of 1 point for the current symbol
double current_symbol_min_lot; // To store minimum lot size for the current symbol
double current_symbol_lot_step; // To store lot step for the current symbol
int    current_symbol_digits; // To store number of digits for price

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Store chart ID and expert name
   chart_ID = ChartID();
   expert_name = MQLInfoString(MQL_PROGRAM_NAME);

//--- Initialize trading object (if using CTrade)
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Symbol());
   trade.LogLevel(LOG_LEVEL_ERROR); // Set log level to errors only for CTrade, LOG_LEVEL_INFO for more details

//--- Initialize account info object
   //account.Refresh();

//--- Get symbol specific information
   current_symbol_point_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   current_symbol_min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   current_symbol_lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   current_symbol_digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);


//--- General OnInit messages
   PrintFormat("%s: Initializing EA...", expert_name);
   PrintFormat("%s: MagicNumber = %d", expert_name, MagicNumber);
   PrintFormat("%s: EA_Comment = %s", expert_name, EA_Comment);
   PrintFormat("%s: Symbol = %s", expert_name, Symbol());
   PrintFormat("%s: Timeframe = %s", expert_name, EnumToString(Period()));
   PrintFormat("%s: Account Balance = %.2f", expert_name, AccountInfoDouble(ACCOUNT_BALANCE));
   PrintFormat("%s: Symbol Point Value = %f", expert_name, current_symbol_point_value);
   PrintFormat("%s: Symbol Min Lot = %.2f", expert_name, current_symbol_min_lot);
   PrintFormat("%s: Symbol Lot Step = %.2f", expert_name, current_symbol_lot_step);
   PrintFormat("%s: Max Risk Per Trade = %.2f%%", expert_name, MaxRiskPerTradePercent);
   PrintFormat("%s: SL Method = %s", expert_name, EnumToString(SL_Method));
   PrintFormat("%s: TP Method = %s", expert_name, EnumToString(TP_Method));
   PrintFormat("%s: Trend Filter Enabled = %s", expert_name, BoolToString(EnableTrendFilter));
   if(EnableTrendFilter)
     {
      PrintFormat("%s: Trend Filter TF = %s, MA Period = %d, MA Method = %s",
                  expert_name,
                  EnumToString(TrendFilter_Timeframe),
                  TrendFilter_MA_Period,
                  EnumToString(TrendFilter_MA_Method));
     }
   PrintFormat("%s: Trading Direction = %s", expert_name, EnumToString(TradeDirection));


//--- Check for minimum terminal version or other critical settings (optional)
   if(TerminalInfoInteger(TERMINAL_BUILD) < 2000) // Example check
     {
      Print("This EA requires MetaTrader 5 build 2000 or higher.");
      Alert("This EA requires MetaTrader 5 build 2000 or higher."); // Alert for more visibility
      return(INIT_FAILED);
     }

   if(current_symbol_point_value == 0 || current_symbol_min_lot == 0)
     {
      PrintFormat("%s: Critical error: Could not retrieve symbol point value or min lot for %s.", expert_name, Symbol());
      Alert("EA Initialization Failed: Symbol properties error. Check logs.");
      return(INIT_FAILED);
     }

   PrintFormat("%s: Initialization successful.", expert_name);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   PrintFormat("%s: Deinitializing EA. Reason code: %d", expert_name, reason);

//--- Perform cleanup if necessary (e.g., remove chart objects created by EA)
   //ObjectsDeleteAll(chart_ID, expert_name); // Example: if EA creates objects with its name

   PrintFormat("%s: Deinitialization complete.", expert_name);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check if trading is allowed for the account / EA
   if(!IsTradingAllowed())
     {
      // PrintFormat("%s: Trading is not allowed.", expert_name); // Can be spammy
      return;
     }

//--- Check for new bar (optional, for strategies that trade once per bar)
   //static datetime prevTime = 0;
   //datetime barTime = (datetime)SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);
   //if(barTime == prevTime)
   //  {
   //   return; // Not a new bar yet
   //  }
   //prevTime = barTime;

//--- Main EA logic will go here in future steps
   // 1. Check current market conditions / signals
   // 2. Check existing trades management (SL, TP, trailing)
   // 3. Check for new trade entry opportunities
   // 4. Check for trade exit conditions

   // --- Main trading logic call
   CheckForNewTradeSignals();


   // --- Example usage of Trend Filter (for testing)
   /*
   ENUM_CURRENT_TREND current_trend_status = GetCurrentTrend();
   PrintFormat("%s: Current Trend Status: %s", expert_name, EnumToString(current_trend_status));
   */

   // --- Example usage of risk management functions (for testing, will be integrated into trade logic later)
   /*
   double sl_points_calc = CalculateStopLossPips(SL_ATR_Timeframe); // Example for ATR based SL
   if(sl_points_calc > 0)
     {
      double lot_size = CalculateLotSize(sl_points_calc);
      PrintFormat("%s: Calculated SL Points: %.2f, Calculated Lot Size: %.2f", expert_name, sl_points_calc, lot_size);

      if(lot_size > 0)
        {
         double tp_points_calc = CalculateTakeProfitPips(sl_points_calc);
         PrintFormat("%s: Calculated TP Points: %.2f", expert_name, tp_points_calc);
        }
     }
   */

  }

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      PrintFormat("%s: AutoTrading is disabled in terminal settings.", expert_name);
      return false;
     }
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DISABLED)
     {
      PrintFormat("%s: Trading is disabled for the account.", expert_name);
      return false;
     }
   // Could add more checks like: if EA is paused by user input, etc.
   return true;
  }

//+------------------------------------------------------------------+
//| Calculate Stop Loss in Pips/Points                               |
//+------------------------------------------------------------------+
double CalculateStopLossPips(ENUM_TIMEFRAMES atr_timeframe_param) // Parameter for ATR timeframe
  {
   double sl_pips = 0;
   switch(SL_Method)
     {
      case SL_METHOD_FIXED_PIPS:
         sl_pips = SL_FixedPips;
         break;
      case SL_METHOD_ATR:
         double atr_value = iATR(Symbol(), atr_timeframe_param, SL_ATR_Period, 1); // Get ATR from the last closed bar
         if(atr_value > 0)
           {
            sl_pips = NormalizeDouble(atr_value * SL_ATR_Multiplier, current_symbol_digits);
            // For VIX indices, ATR value is already in points. For others, might need /_Point
            // Assuming VIX indices where ATR is direct points.
           }
         else
           {
            PrintFormat("%s: Could not calculate ATR for SL. ATR Period: %d, TF: %s. Using fixed SL of %d points as fallback.",
                        expert_name, SL_ATR_Period, EnumToString(atr_timeframe_param), SL_FixedPips);
            sl_pips = SL_FixedPips; // Fallback
           }
         break;
     }
   return sl_pips / SymbolInfoDouble(Symbol(), SYMBOL_POINT); // Return SL in points (not pips for VIX)
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
// sl_points is the stop loss distance in points (e.g. for V50, 1 point = $0.05 for 0.05 lot)
double CalculateLotSize(double sl_points)
  {
   if(sl_points <= 0)
     {
      PrintFormat("%s: SL points must be greater than 0 for lot calculation. SL points: %.2f", expert_name, sl_points);
      return 0.0;
     }

   double lot_size = 0.0;
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (MaxRiskPerTradePercent / 100.0);

   // If FixedLotSize is specified and > 0, use it directly
   if(FixedLotSize > 0)
     {
      lot_size = FixedLotSize;
     }
   else // Calculate based on risk percentage
     {
      // Value per point for 1 lot = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
      // For Deriv Synthetics, SYMBOL_TRADE_TICK_VALUE is often the value of 1 point movement for 1 lot.
      // Example: V50 (1s), SYMBOL_TRADE_TICK_VALUE might be 1.0 (meaning $1 per point for 1 lot).
      // If SL is 100 points, risk per lot is 100 * $1 = $100.
      // Lot size = Risk Amount / (SL_Points * Value_Per_Point_Per_Lot)
      double value_per_point_per_lot = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
      if(value_per_point_per_lot <= 0) {
         PrintFormat("%s: Error! Symbol Tick Value is zero for %s. Cannot calculate lot size.", expert_name, Symbol());
         return 0.0;
      }

      lot_size = risk_amount / (sl_points * value_per_point_per_lot);
     }

   // Normalize lot size according to symbol's lot step
   lot_size = NormalizeDouble(lot_size, 2); // Normalize to 2 decimal places first for general case
   lot_size = MathFloor(lot_size / current_symbol_lot_step) * current_symbol_lot_step;


   // Check against minimum lot size
   if(lot_size < current_symbol_min_lot)
     {
      PrintFormat("%s: Calculated lot size %.2f is less than min lot %.2f.", expert_name, lot_size, current_symbol_min_lot);
      switch(SmallAccountMinLotBehavior)
        {
         case LOT_SIZE_BEHAVIOR_USE_MIN_LOT:
            PrintFormat("%s: Using minimum lot size %.2f due to SmallAccountMinLotBehavior setting (High Risk).", expert_name, current_symbol_min_lot);
            lot_size = current_symbol_min_lot;
            // Optional: Add a check here if using min lot still exceeds a hard max risk % (e.g. 10% of account)
            double risk_with_min_lot = (current_symbol_min_lot * sl_points * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE) / account_balance) * 100.0;
            PrintFormat("%s: Risk with min lot %.2f is %.2f%%", expert_name, current_symbol_min_lot, risk_with_min_lot);
            if (risk_with_min_lot > MaxRiskPerTradePercent * 2 && MaxRiskPerTradePercent > 0) { // Example: if it's more than double the desired risk
                PrintFormat("%s: WARNING! Using min lot results in risk %.2f%%, which significantly exceeds desired %.2f%%. Consider skipping trade or adjusting risk.", expert_name, risk_with_min_lot, MaxRiskPerTradePercent);
            }
            break;
         case LOT_SIZE_BEHAVIOR_SKIP_TRADE:
            PrintFormat("%s: Skipping trade due to SmallAccountMinLotBehavior setting.", expert_name);
            return 0.0; // Return 0 to indicate skip trade
        }
     }

   // Check against maximum lot size (if defined, e.g. SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX))
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   if(lot_size > max_lot && max_lot > 0)
     {
        PrintFormat("%s: Calculated lot size %.2f exceeds max lot %.2f. Using max lot.", expert_name, lot_size, max_lot);
        lot_size = max_lot;
     }

   return lot_size;
  }

//+------------------------------------------------------------------+
//| Calculate Take Profit in Pips/Points                             |
//+------------------------------------------------------------------+
// sl_pips_for_rr is the stop loss distance in pips/points used for RR calculation
double CalculateTakeProfitPips(double sl_pips_for_rr)
  {
   double tp_pips = 0;
   switch(TP_Method)
     {
      case TP_METHOD_FIXED_PIPS:
         tp_pips = TP_FixedPips;
         break;
      case TP_METHOD_RR:
         if(sl_pips_for_rr > 0 && TP_RR_Ratio > 0)
           {
            tp_pips = sl_pips_for_rr * TP_RR_Ratio;
           }
         else
           {
            PrintFormat("%s: Could not calculate TP based on R:R. SL pips: %.2f, R:R Ratio: %.2f. Using fixed TP of %d points as fallback.",
                        expert_name, sl_pips_for_rr, TP_RR_Ratio, TP_FixedPips);
            tp_pips = TP_FixedPips; // Fallback
           }
         break;
     }
   return tp_pips; // Return TP in points (not pips for VIX)
  }

//--- Trend Determination Enums & Functions ---
enum ENUM_CURRENT_TREND
  {
   TREND_NONE,    // Trend cannot be determined or is neutral
   TREND_UP,      // Uptrend detected
   TREND_DOWN    // Downtrend detected
  };

//+------------------------------------------------------------------+
//| Get Current Trend based on MA Filter                             |
//+------------------------------------------------------------------+
ENUM_CURRENT_TREND GetCurrentTrend()
  {
   if(!EnableTrendFilter)
     {
      return TREND_NONE; // Filter disabled, so no specific trend bias from MA
     }

   // Get the MA value on the TrendFilter_Timeframe for the last fully closed bar (shift=1)
   double ma_value_array[];
   if(CopyBuffer(iMA(Symbol(), TrendFilter_Timeframe, TrendFilter_MA_Period, 0, TrendFilter_MA_Method, TrendFilter_MA_AppliedPrice), 0, 1, 1, ma_value_array) < 1)
     {
      PrintFormat("%s: Error copying MA buffer for trend filter. Symbol: %s, TF: %s, Period: %d",
                  expert_name, Symbol(), EnumToString(TrendFilter_Timeframe), TrendFilter_MA_Period);
      return TREND_NONE; // Cannot determine trend
     }
   double ma_value = ma_value_array[0];

   // Get the close price of the current M1 bar (or the last closed M1 bar if preferred)
   // Using last closed M1 bar's close for stability against current tick fluctuation
   MqlRates rates_m1[];
   if(CopyRates(Symbol(), PERIOD_M1, 1, 1, rates_m1) < 1)
     {
      PrintFormat("%s: Error copying M1 rates for trend filter.", expert_name);
      return TREND_NONE;
     }
   double current_m1_close = rates_m1[0].close;

   if(current_m1_close > ma_value)
     {
      return TREND_UP;
     }
   else if(current_m1_close < ma_value)
     {
      return TREND_DOWN;
     }

   return TREND_NONE; // Price is exactly on the MA or error
  }

//--- Price Action Entry Logic ---

// Structure to hold signal details (can be expanded)
struct TradeSignalInfo
  {
   ENUM_ORDER_TYPE signal_type;       // BUY or SELL
   double          entry_price;
   double          stop_loss_price;
   double          take_profit_price;
   string          comment;
  };

//+------------------------------------------------------------------+
//| Check for new trade signals                                      |
//+------------------------------------------------------------------+
void CheckForNewTradeSignals()
  {
   if(!EnableEntry_StructureBreakRetest) return; // Signal disabled

   // Ensure we are on M1 timeframe for this specific logic, or adapt if necessary
   if(Period() != PERIOD_M1)
     {
      // This specific SBR logic is designed for M1.
      // Could add a check in OnInit or make timeframe an input for SBR.
      // For now, just return if not on M1.
      // static bool m1_warning_shown = false;
      // if(!m1_warning_shown){ PrintFormat("%s: SBR Entry logic is optimized for M1. Current TF: %s", expert_name, EnumToString(Period())); m1_warning_shown = true;}
      return;
     }

   ENUM_CURRENT_TREND current_trend = GetCurrentTrend();
   TradeSignalInfo signal; // To store any found signal

   // Check for Long (Buy) Signal
   if(TradeDirection == TRADE_DIRECTION_BOTH || TradeDirection == TRADE_DIRECTION_LONG_ONLY)
     {
      if(!EnableTrendFilter || (EnableTrendFilter && current_trend == TREND_UP) || (EnableTrendFilter && current_trend == TREND_NONE && !strict_trend_mode)) // Allow TREND_NONE if not strict
        {
         if(CheckSBR_Long(signal))
           {
            // TODO: Execute Buy Trade using signal details
            PrintFormat("%s: BUY Signal SBR - Entry:%.5f SL:%.5f TP:%.5f", expert_name, signal.entry_price, signal.stop_loss_price, signal.take_profit_price);
            ExecuteTrade(signal);
            return; // Process one signal per tick for now
           }
        }
     }

   // Check for Short (Sell) Signal
   if(TradeDirection == TRADE_DIRECTION_BOTH || TradeDirection == TRADE_DIRECTION_SHORT_ONLY)
     {
      if(!EnableTrendFilter || (EnableTrendFilter && current_trend == TREND_DOWN) || (EnableTrendFilter && current_trend == TREND_NONE && !strict_trend_mode)) // Allow TREND_NONE if not strict
        {
         if(CheckSBR_Short(signal))
           {
            // TODO: Execute Sell Trade using signal details
            PrintFormat("%s: SELL Signal SBR - Entry:%.5f SL:%.5f TP:%.5f", expert_name, signal.entry_price, signal.stop_loss_price, signal.take_profit_price);
            ExecuteTrade(signal);
            return; // Process one signal per tick for now
           }
        }
     }
  }

// Placeholder for strict trend mode - if true, TREND_NONE would not allow trades
static bool strict_trend_mode = false; // Can be made an input parameter

//+------------------------------------------------------------------+
//| Check for Structure Break & Retest - LONG SIGNAL                 |
//+------------------------------------------------------------------+
bool CheckSBR_Long(TradeSignalInfo &signal_out)
  {
   MqlRates m1_rates[];
   // Need SBR_SwingDetectionPeriod + SBR_RetestWindowBars + few extra for safety, e.g., 20-30 bars for typical settings
   int bars_needed = SBR_SwingDetectionPeriod + SBR_RetestWindowBars + 5;
   if(CopyRates(Symbol(), PERIOD_M1, 0, bars_needed, m1_rates) < bars_needed)
     {
      PrintFormat("%s: SBR_Long - Not enough M1 bars. Need %d, Got %d", expert_name, bars_needed, CopyRates(Symbol(), PERIOD_M1, 0, bars_needed, m1_rates));
      return false;
     }
   ArraySetAsSeries(m1_rates, true); // Index 0 is current bar, 1 is previous, etc.

   // 1. Detect Micro Swing High (within SBR_SwingDetectionPeriod, look back from SBR_RetestWindowBars ago)
   // We search for a swing high that occurred *before* a potential retest window.
   // The break must happen, then a retest.
   // Let's simplify: look for a swing high in the recent past, then a break, then a retest.
   // Start looking for swing from bar index `start_idx_swing_search`

   // Iterate backwards from (SBR_RetestWindowBars + 1) up to (SBR_RetestWindowBars + SBR_SwingDetectionPeriod)
   // to find the highest high that could have been broken and then retested.
   // Bar 0 is current (incomplete), Bar 1 is last completed.
   // Break must happen on a completed bar. Retest can be on current or completed.

   for(int retest_bar_idx = 1; retest_bar_idx <= SBR_RetestWindowBars; retest_bar_idx++) // Potential retest bar
   {
       for(int break_bar_idx = retest_bar_idx + 1; break_bar_idx < retest_bar_idx + SBR_SwingDetectionPeriod + 1 && break_bar_idx < bars_needed; break_bar_idx++) // Potential break bar
       {
           // Find swing high prior to break_bar_idx
           double swing_high_price = 0;
           int swing_high_idx = -1;

           for(int k=break_bar_idx + 1; k < break_bar_idx + SBR_SwingDetectionPeriod + 1 && k < bars_needed; k++)
           {
               if(m1_rates[k].high > swing_high_price)
               {
                   swing_high_price = m1_rates[k].high;
                   swing_high_idx = k;
               }
           }
           if(swing_high_idx == -1) continue; // No valid swing high found

           // 2. Detect Break of Swing High
           // Check if m1_rates[break_bar_idx].close broke above swing_high_price
           bool broken = m1_rates[break_bar_idx].close > swing_high_price &&
                         (m1_rates[break_bar_idx].close - swing_high_price) >= SBR_MinBreakoutPoints * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
           if(!broken) continue;

           // 3. Detect Retest of Broken Level (swing_high_price)
           // Check if m1_rates[retest_bar_idx].low came close to swing_high_price
           // and if the close of retest_bar_idx is above the swing_high_price (confirmation)
           bool retested_level = (m1_rates[retest_bar_idx].low <= swing_high_price + SBR_RetestProximityPoints * SymbolInfoDouble(Symbol(), SYMBOL_POINT)) &&
                                 (m1_rates[retest_bar_idx].low >= swing_high_price - SBR_RetestProximityPoints * SymbolInfoDouble(Symbol(), SYMBOL_POINT)); // Price touched the zone

           bool confirmation_candle = m1_rates[retest_bar_idx].close > swing_high_price; // Simple confirmation: closed above

           // Add SBR_ConfirmationCandlePattern logic here later (pinbar, engulfing)
           // For now, simple close above is enough for SBR_ConfirmationCandlePattern == 0

           if(retested_level && confirmation_candle)
           {
               // Potential Buy Signal Found
               // SL below the low of the retest candle or below the swing_high_price
               double sl_price = m1_rates[retest_bar_idx].low - SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * SymbolInfoDouble(Symbol(), SYMBOL_POINT) - (SL_FixedPips * SymbolInfoDouble(Symbol(), SYMBOL_POINT)); // Example initial SL

               // Use risk management module for actual SL points calculation
               double sl_points_calc = CalculateStopLossPips(SL_ATR_Timeframe); // Use the configured SL method
               if (sl_points_calc <=0) sl_points_calc = SL_FixedPips; // Fallback if ATR fails for some reason

               // Place SL below retest bar's low or below the broken structure, whichever is lower and safer
               double sl_candidate1 = m1_rates[retest_bar_idx].low - sl_points_calc * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               double sl_candidate2 = swing_high_price - sl_points_calc * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               sl_price = MathMin(sl_candidate1, sl_candidate2);


               double entry_price_calc = SymbolInfoDouble(Symbol(), SYMBOL_ASK); // Current Ask for Buy
               double tp_points_calc = CalculateTakeProfitPips(MathAbs(entry_price_calc - sl_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));
               double tp_price = entry_price_calc + tp_points_calc * SymbolInfoDouble(Symbol(), SYMBOL_POINT);

               // Fill signal_out structure (TODO_REPLACE_WITH_REFERENCE_TradeSignalInfo needs to be changed to TradeSignalInfo&)
               signal_out.signal_type = ORDER_TYPE_BUY;
               signal_out.entry_price = entry_price_calc;
               signal_out.stop_loss_price = sl_price;
               signal_out.take_profit_price = tp_price;
               signal_out.comment = expert_name + " SBR Long";

               // Check if this bar was already used for a signal to prevent multiple signals from same bar
               // static datetime last_signal_bar_time_long = 0;
               // if(m1_rates[retest_bar_idx].time == last_signal_bar_time_long) return false;
               // last_signal_bar_time_long = m1_rates[retest_bar_idx].time;

               return true;
           }
       }
   }
   return false;
  }

//+------------------------------------------------------------------+
//| Check for Structure Break & Retest - SHORT SIGNAL                |
//+------------------------------------------------------------------+
bool CheckSBR_Short(TradeSignalInfo &signal_out)
  {
   MqlRates m1_rates[];
   int bars_needed = SBR_SwingDetectionPeriod + SBR_RetestWindowBars + 5;
   if(CopyRates(Symbol(), PERIOD_M1, 0, bars_needed, m1_rates) < bars_needed)
     {
      PrintFormat("%s: SBR_Short - Not enough M1 bars. Need %d, Got %d", expert_name, bars_needed, CopyRates(Symbol(), PERIOD_M1, 0, bars_needed, m1_rates));
      return false;
     }
   ArraySetAsSeries(m1_rates, true);

   for(int retest_bar_idx = 1; retest_bar_idx <= SBR_RetestWindowBars; retest_bar_idx++)
   {
       for(int break_bar_idx = retest_bar_idx + 1; break_bar_idx < retest_bar_idx + SBR_SwingDetectionPeriod + 1 && break_bar_idx < bars_needed; break_bar_idx++)
       {
           double swing_low_price = DBL_MAX; // Initialize with max double for finding minimum
           int swing_low_idx = -1;

           for(int k=break_bar_idx + 1; k < break_bar_idx + SBR_SwingDetectionPeriod + 1 && k < bars_needed; k++)
           {
               if(m1_rates[k].low < swing_low_price) // Check DBL_MAX on first iteration implicitly
               {
                   swing_low_price = m1_rates[k].low;
                   swing_low_idx = k;
               }
           }
           if(swing_low_idx == -1 || swing_low_price == DBL_MAX) continue; // No valid swing low found

           bool broken = m1_rates[break_bar_idx].close < swing_low_price &&
                         (swing_low_price - m1_rates[break_bar_idx].close) >= SBR_MinBreakoutPoints * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
           if(!broken) continue;

           bool retested_level = (m1_rates[retest_bar_idx].high >= swing_low_price - SBR_RetestProximityPoints * SymbolInfoDouble(Symbol(), SYMBOL_POINT)) &&
                                 (m1_rates[retest_bar_idx].high <= swing_low_price + SBR_RetestProximityPoints * SymbolInfoDouble(Symbol(), SYMBOL_POINT));

           bool confirmation_candle = m1_rates[retest_bar_idx].close < swing_low_price;

           if(retested_level && confirmation_candle)
           {
               // Potential Sell Signal Found
               // SL above the high of the retest candle or above the swing_low_price
               // Use risk management module for actual SL points calculation
               double sl_points_calc = CalculateStopLossPips(SL_ATR_Timeframe); // Use the configured SL method
               if (sl_points_calc <=0) sl_points_calc = SL_FixedPips; // Fallback if ATR fails

               // Place SL above retest bar's high or above the broken structure, whichever is higher and safer
               double sl_candidate1 = m1_rates[retest_bar_idx].high + sl_points_calc * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               double sl_candidate2 = swing_low_price + sl_points_calc * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               double sl_price = MathMax(sl_candidate1, sl_candidate2);

               double entry_price_calc = SymbolInfoDouble(Symbol(), SYMBOL_BID); // Current Bid for Sell
               double tp_points_calc = CalculateTakeProfitPips(MathAbs(entry_price_calc - sl_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));
               double tp_price = entry_price_calc - tp_points_calc * SymbolInfoDouble(Symbol(), SYMBOL_POINT);

               signal_out.signal_type = ORDER_TYPE_SELL;
               signal_out.entry_price = entry_price_calc;
               signal_out.stop_loss_price = sl_price;
               signal_out.take_profit_price = tp_price;
               signal_out.comment = expert_name + " SBR Short";

               // Prevent multiple signals from the same retest bar (optional, can be handled by trade execution logic)
               // static datetime last_signal_bar_time_short = 0;
               // if(m1_rates[retest_bar_idx].time == last_signal_bar_time_short) return false;
               // last_signal_bar_time_short = m1_rates[retest_bar_idx].time;

               return true;
           }
       }
   }
   return false;
  }

//+------------------------------------------------------------------+
//| Execute Trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(TradeSignalInfo &signal)
  {
//--- Check if max open trades limit reached
   if(CountOpenTrades() >= MaxOpenTrades_Initial)
     {
      PrintFormat("%s: Max open trades limit (%d) reached. No new trade.", expert_name, MaxOpenTrades_Initial);
      return;
     }

//--- Calculate Lot Size
   // SL distance in points for lot calculation:
   double sl_distance_points = MathAbs(signal.entry_price - signal.stop_loss_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   if(signal.signal_type == ORDER_TYPE_SELL) // For sells, entry is Bid, SL is above
     {
      sl_distance_points = MathAbs(signal.stop_loss_price - SymbolInfoDouble(Symbol(), SYMBOL_BID)) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
      // Ensure SL is calculated from current market, not theoretical entry if signal is old
     }
   else // For buys, entry is Ask, SL is below
     {
      sl_distance_points = MathAbs(SymbolInfoDouble(Symbol(), SYMBOL_ASK) - signal.stop_loss_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
     }

   if(sl_distance_points < SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT) && SL_Method != SL_METHOD_FIXED_PIPS) // If ATR SL is too small
     {
       sl_distance_points = SL_FixedPips; // Fallback to fixed pips SL if ATR is smaller than stops level
       PrintFormat("%s: Calculated SL distance (%.2f points) is too small. Using fixed SL of %.0f points for lot calculation.", expert_name, sl_distance_points, (double)SL_FixedPips);
     }


   double lot_size = CalculateLotSize(sl_distance_points);
   if(lot_size <= 0.0)
     {
      PrintFormat("%s: Lot size calculation failed or returned 0. Cannot execute trade.", expert_name);
      return;
     }

//--- Normalize SL and TP prices to symbol digits and ensure they are valid
   double actual_sl_price = NormalizeDouble(signal.stop_loss_price, current_symbol_digits);
   double actual_tp_price = NormalizeDouble(signal.take_profit_price, current_symbol_digits);
   double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double min_stop_distance_price = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(signal.signal_type == ORDER_TYPE_BUY)
     {
      if(actual_sl_price >= current_ask - min_stop_distance_price) // SL too close
        {
         actual_sl_price = current_ask - min_stop_distance_price * 1.1; // Move it further
         actual_sl_price = NormalizeDouble(actual_sl_price, current_symbol_digits);
         PrintFormat("%s: Adjusted SL for BUY to %.5f due to stops level.", expert_name, actual_sl_price);
        }
      if(actual_tp_price <= current_ask + min_stop_distance_price && actual_tp_price != 0) // TP too close
        {
         actual_tp_price = current_ask + min_stop_distance_price * 1.1;
         actual_tp_price = NormalizeDouble(actual_tp_price, current_symbol_digits);
         PrintFormat("%s: Adjusted TP for BUY to %.5f due to stops level.", expert_name, actual_tp_price);
        }
     }
   else // ORDER_TYPE_SELL
     {
      if(actual_sl_price <= current_bid + min_stop_distance_price) // SL too close
        {
         actual_sl_price = current_bid + min_stop_distance_price * 1.1;
         actual_sl_price = NormalizeDouble(actual_sl_price, current_symbol_digits);
         PrintFormat("%s: Adjusted SL for SELL to %.5f due to stops level.", expert_name, actual_sl_price);
        }
      if(actual_tp_price >= current_bid - min_stop_distance_price && actual_tp_price != 0) // TP too close
        {
         actual_tp_price = current_bid - min_stop_distance_price * 1.1;
         actual_tp_price = NormalizeDouble(actual_tp_price, current_symbol_digits);
         PrintFormat("%s: Adjusted TP for SELL to %.5f due to stops level.", expert_name, actual_tp_price);
        }
     }

   // Ensure TP is 0 if it was calculated as 0 (e.g. R:R is 0)
   if (signal.take_profit_price == 0) actual_tp_price = 0;


//--- Execute Trade using CTrade
   bool result = false;
   string trade_type_str = "";

   PrintFormat("%s: Attempting to %s %.2f lots of %s at market. SL: %.5f, TP: %.5f. Comment: %s",
               expert_name,
               (signal.signal_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               lot_size,
               Symbol(),
               actual_sl_price,
               actual_tp_price,
               signal.comment);

   if(signal.signal_type == ORDER_TYPE_BUY)
     {
      result = trade.Buy(lot_size, Symbol(), 0, actual_sl_price, actual_tp_price, signal.comment);
      trade_type_str = "BUY";
     }
   else if(signal.signal_type == ORDER_TYPE_SELL)
     {
      result = trade.Sell(lot_size, Symbol(), 0, actual_sl_price, actual_tp_price, signal.comment);
      trade_type_str = "SELL";
     }

   if(result)
     {
      PrintFormat("%s: %s order placed successfully. Ticket: %d. SL: %.5f, TP: %.5f, Lots: %.2f",
                  expert_name, trade_type_str, (int)trade.ResultOrder(), actual_sl_price, actual_tp_price, lot_size);
     }
   else
     {
      PrintFormat("%s: %s order placement failed. Error code: %d. Message: %s",
                  expert_name, trade_type_str, (int)trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Count Open Trades by this EA's Magic Number                      |
//+------------------------------------------------------------------+
int CountOpenTrades()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == Symbol())
        {
         count++;
        }
     }
   return count;
  }


//+------------------------------------------------------------------+
//| OnTimer function (Example, if needed)                            |
//+------------------------------------------------------------------+
//void OnTimer()
//  {
//   //--- Timer-based actions (e.g., less frequent checks, UI updates)
//   if(!IsTradingAllowed()) return;
//
//   // Comment("EA Timer Event: ", TimeCurrent());
//  }
//+------------------------------------------------------------------+
//| OnTrade function (Example, for reacting to trade events)         |
//+------------------------------------------------------------------+
//void OnTrade()
//  {
//    //--- React to trade events (e.g., order filled, modified, closed)
//    // CTradeResult result;
//    // CTradeOrderInfo order_info;
//    // ... logic to get trade details ...
//    // PrintFormat("%s: Trade event occurred.", expert_name);
//  }
//+------------------------------------------------------------------+
//| OnChartEvent function (Example, for UI interactions)             |
//+------------------------------------------------------------------+
//void OnChartEvent(const int id,
//                  const long &lparam,
//                  const double &dparam,
//                  const string &sparam)
//  {
//   //--- Handle chart events (e.g., button clicks)
//   // if(id == CHARTEVENT_OBJECT_CLICK)
//   //   {
//   //    PrintFormat("%s: Chart object clicked: %s", expert_name, sparam);
//   //    // --- Logic for button clicks will go here
//   //   }
//  }
//+------------------------------------------------------------------+
//| Helper functions (future development)                            |
//+------------------------------------------------------------------+
// Example: Get current spread
//double GetCurrentSpreadInPoints() // Renamed for clarity
//  {
//   MqlTick latest_tick;
//   SymbolInfoTick(Symbol(), latest_tick);
//   // For symbols like Forex, spread is (ask-bid). For single-price synthetics, this might be different or always 0.
//   // Assuming standard ask-bid spread for now.
//   double spread = (latest_tick.ask - latest_tick.bid);
//   return NormalizeDouble(spread / SymbolInfoDouble(Symbol(), SYMBOL_POINT), current_symbol_digits); // Spread in points
//  }

// Example: Calculate ATR (already used iATR directly, but a wrapper could be useful)
//double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift)
//  {
//   double atr_buffer[];
//   // Ensure we request enough data for the shift. For shift 1 (last closed bar), 2 bars of data.
//   int bars_to_copy = shift + 2;
//   if(CopyBuffer(iATR(symbol, timeframe, period), 0, 0, bars_to_copy, atr_buffer) < bars_to_copy)
//     {
//      PrintFormat("%s: Error copying ATR buffer. Symbol: %s, TF: %s, Period: %d, Shift: %d",
//                  expert_name, symbol, EnumToString(timeframe), period, shift);
//      return 0.0;
//     }
//   // Array is indexed from current (0) to past. atr_buffer[shift] is the desired bar.
//   return NormalizeDouble(atr_buffer[shift], current_symbol_digits + 1); // ATR value typically has more precision
//  }
//+------------------------------------------------------------------+
