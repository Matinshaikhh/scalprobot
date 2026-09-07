//+------------------------------------------------------------------+
//|                                        CSymbolClassifier.mqh |
//|                Scalping Robot Pro - Multi-Asset Profiles (P6) |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide which asset class the CURRENT      |
//|   broker symbol belongs to, and read that symbol's real contract       |
//|   specification from the terminal.                                    |
//|                                                                  |
//|   WHY THIS EXISTS                                                    |
//|   Brokers name the same instrument a dozen different ways. NASDAQ is   |
//|   NAS100, US100, USTEC, NAS100.cash, US100.cash, USTECH, NDX, and      |
//|   more with suffixes like .r .pro .m .ecn appended. Gold is XAUUSD,    |
//|   XAUUSDm, GOLD, XAUUSD.cash. An EA that hardcodes one spelling works  |
//|   on one broker and silently mis-parameterises on every other.        |
//|                                                                  |
//|   SO NOTHING HERE IS HARDCODED TO A SINGLE NAME. Classification is     |
//|   by token matching against the symbol the trader actually selected,   |
//|   and EVERY numeric fact comes from SymbolInfo* at runtime. The class  |
//|   never assumes a contract size, a digit count or a tick value.        |
//|                                                                  |
//|   NAME MATCHING IS A HINT, NOT A CONTRACT. A symbol that matches no    |
//|   token is classified CUSTOM and runs on explicit user parameters      |
//|   rather than being forced into a preset that might be wrong. Guessing |
//|   would be worse than admitting ignorance: applying index parameters   |
//|   to an unrecognised FX pair would size every position wrongly.       |
//+------------------------------------------------------------------+
#ifndef SRP_PROFILES_CSYMBOLCLASSIFIER_MQH
#define SRP_PROFILES_CSYMBOLCLASSIFIER_MQH

#include "../Core/Types/Structs.mqh"
#include "../Utilities/CStringUtils.mqh"

//+------------------------------------------------------------------+
//| How the profile is chosen. Exposed as an input so a trader on a      |
//| broker with an unusual symbol name can force the right preset rather  |
//| than being silently dropped into CUSTOM.                             |
//+------------------------------------------------------------------+
enum ENUM_SRP_PROFILE_MODE
  {
   SRP_PROFILE_AUTO,      // detect from the broker symbol name
   SRP_PROFILE_NASDAQ,    // force the NASDAQ preset
   SRP_PROFILE_GOLD,      // force the gold preset
   SRP_PROFILE_CUSTOM     // conservative baseline, inputs rule
  };

//+------------------------------------------------------------------+
//| Which market profile a symbol should run under.                    |
//+------------------------------------------------------------------+
enum ENUM_SRP_ASSET_CLASS
  {
   SRP_ASSET_UNKNOWN,          // not recognised; user parameters only
   SRP_ASSET_INDEX_NASDAQ,     // NAS100 / US100 / USTEC family
   SRP_ASSET_INDEX_OTHER,      // any other equity index
   SRP_ASSET_METAL_GOLD,       // XAUUSD family
   SRP_ASSET_METAL_OTHER,      // silver, platinum, palladium
   SRP_ASSET_FOREX,            // currency pair
   SRP_ASSET_CRYPTO            // BTC, ETH, ...
  };

//+------------------------------------------------------------------+
//| Everything the engine needs to know about the traded instrument,   |
//| read from the broker rather than assumed.                          |
//|                                                                  |
//| This extends SSymbolSpec (Phase 1) with the execution-side facts   |
//| Phase 6 needs: filling mode, execution mode, and the derived       |
//| money-per-point that every risk calculation depends on.            |
//+------------------------------------------------------------------+
struct SSymbolProfile
  {
   //--- Identity.
   string                symbol;
   ENUM_SRP_ASSET_CLASS  asset_class;
   string                class_name;
   bool                  resolved;
   string                resolve_error;

   //--- Quote geometry.
   int                   digits;
   double                point;
   double                tick_size;
   double                tick_value;
   double                contract_size;

   //--- Volume rules.
   double                volume_min;
   double                volume_max;
   double                volume_step;
   double                volume_limit;      // total across positions, 0 = none

   //--- Distance rules, in points.
   int                   stops_level;
   int                   freeze_level;

   //--- Cost and margin.
   double                spread_current;    // points, at resolve time
   //--- HARNESS v2, FIX 5. 1 when spread_current was supplied by an input
   //--- instead of read from the tick. The whole trade geometry descends
   //--- from this one number (audit 5.5), so whether it is reproducible is
   //--- a fact about the RUN and has to travel with the sample itself.
   int                   spread_pinned;     // 1 = came from InpPinSpreadSample
   int                   spread_float;      // 1 = floating
   double                margin_initial;
   double                margin_hedged;
   double                swap_long;
   double                swap_short;

   //--- Execution.
   ENUM_SYMBOL_TRADE_MODE          trade_mode;
   ENUM_SYMBOL_TRADE_EXECUTION     execution_mode;
   ENUM_SYMBOL_CALC_MODE           calc_mode;
   int                             filling_flags;
   ENUM_ORDER_TYPE_FILLING         preferred_filling;

   //--- Session facts, from the broker's own quote schedule.
   bool                  quotes_today;
   bool                  trades_today;

   //--- Derived. Money lost per POINT of adverse move on one lot,
   //--- obtained from the terminal so it is right on metals too.
   double                money_per_point_per_lot;

                     SSymbolProfile(void) { Reset(); }
   void              Reset(void)
     {
      symbol=""; asset_class=SRP_ASSET_UNKNOWN; class_name="unknown";
      resolved=false; resolve_error="";
      digits=0; point=0.0; tick_size=0.0; tick_value=0.0; contract_size=0.0;
      volume_min=0.0; volume_max=0.0; volume_step=0.0; volume_limit=0.0;
      stops_level=0; freeze_level=0;
      spread_current=0.0; spread_float=0; spread_pinned=0;
      margin_initial=0.0; margin_hedged=0.0;
      swap_long=0.0; swap_short=0.0;
      trade_mode=SYMBOL_TRADE_MODE_DISABLED;
      execution_mode=SYMBOL_TRADE_EXECUTION_REQUEST;
      calc_mode=SYMBOL_CALC_MODE_FOREX;
      filling_flags=0;
      preferred_filling=ORDER_FILLING_RETURN;
      quotes_today=false; trades_today=false;
      money_per_point_per_lot=0.0;
     }

   //--- True when the instrument can actually be traded right now.
   bool              IsTradable(void) const
     {
      return(resolved && trade_mode==SYMBOL_TRADE_MODE_FULL);
     }
   //--- True when the broker allows only closing trades.
   bool              IsCloseOnly(void) const
     {
      return(trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY);
     }
  };

//+------------------------------------------------------------------+
//| Static classifier. Holds no state: it answers questions about a     |
//| symbol name and fills a profile struct from the terminal.           |
//+------------------------------------------------------------------+
class CSymbolClassifier
  {
private:
   //--- Case-insensitive "does the symbol contain this token".
   static bool       Contains(const string haystack_upper,const string token);
   //--- Strips the decorations brokers append: .cash .r .pro _m -ECN etc.
   static string     CoreName(const string symbol);
   static ENUM_ORDER_TYPE_FILLING ResolveFilling(const int flags,
                                                 const ENUM_SYMBOL_TRADE_EXECUTION mode);

public:
   //--- Classification from the symbol name. A HINT, never a fact:
   //--- numeric behaviour always comes from the resolved profile.
   static ENUM_SRP_ASSET_CLASS Classify(const string symbol);
   static string     ClassName(const ENUM_SRP_ASSET_CLASS asset_class);

   //--- Reads every contract specification the engine relies on.
   //--- Returns false with profile.resolve_error set when the symbol
   //--- cannot be used, rather than returning silent zeroes.
   static bool       Resolve(const string symbol,SSymbolProfile &profile);

   //--- HARNESS v2, FIX 5. Replaces the resolved spread sample with a
   //--- declared one, and records that it was declared.
   //---
   //--- Resolve() reads SYMBOL_SPREAD at the instant it is called, and
   //--- twelve trading distances descend from that one number (audit 5.5).
   //--- Two runs over the same period therefore trade different geometry
   //--- unless the root is fixed. This is the only place the substitution
   //--- happens, so "what pinning means" has one definition: pass 0 or
   //--- less and nothing changes at all.
   //---
   //--- Returns true when the pin was applied.
   static bool       PinSpreadSample(SSymbolProfile &profile,
                                     const double pinned_points);

   //--- Human-readable dump for the startup log and support tickets.
   static string     Describe(const SSymbolProfile &profile);
  };

//+------------------------------------------------------------------+
bool CSymbolClassifier::PinSpreadSample(SSymbolProfile &profile,
                                        const double pinned_points)
  {
   //--- A pin of 0 is the shipping default and means "use the tick", so it
   //--- must be a no-op rather than a zero sample - the chain's fallback
   //--- would silently become 10.0 points on every run.
   if(pinned_points<=0.0)
      return(false);
   profile.spread_current=pinned_points;
   profile.spread_pinned=1;
   return(true);
  }

//+------------------------------------------------------------------+
bool CSymbolClassifier::Contains(const string haystack_upper,const string token)
  {
   return(StringFind(haystack_upper,token)>=0);
  }
//+------------------------------------------------------------------+
//| Reduces a broker symbol to its recognisable core.                  |
//|                                                                  |
//| "NAS100.cash" -> "NAS100",  "XAUUSDm" -> "XAUUSD",                 |
//| "US100_SB"    -> "US100",   "USTEC.r" -> "USTEC"                   |
//|                                                                  |
//| Only decoration is removed. The result is still only used for      |
//| matching, never for arithmetic.                                    |
//+------------------------------------------------------------------+
string CSymbolClassifier::CoreName(const string symbol)
  {
   string upper=symbol;
   StringToUpper(upper);

   //--- Cut at the first separator brokers use for suffixes.
   const string cuts[]={".","_","-","#"};
   for(int i=0;i<ArraySize(cuts);i++)
     {
      const int at=StringFind(upper,cuts[i]);
      if(at>0)
         upper=StringSubstr(upper,0,at);
     }
   return(upper);
  }
//+------------------------------------------------------------------+
//| ASSET CLASSIFICATION.                                              |
//|                                                                  |
//| Order matters: the most specific family is tested first, so a       |
//| symbol containing both "US" and "USD" is not misread. Every branch  |
//| below is a NAME HINT used to pick default parameters; nothing here  |
//| feeds a price or size calculation.                                 |
//+------------------------------------------------------------------+
ENUM_SRP_ASSET_CLASS CSymbolClassifier::Classify(const string symbol)
  {
   if(symbol=="")
      return(SRP_ASSET_UNKNOWN);

   const string core=CoreName(symbol);
   string upper=symbol;
   StringToUpper(upper);

   //=== NASDAQ. The widest set of broker spellings of any instrument.
   if(Contains(core,"NAS100")  || Contains(core,"NAS")    ||
      Contains(core,"US100")   || Contains(core,"USTEC")  ||
      Contains(core,"USTECH")  || Contains(core,"NDX")    ||
      Contains(core,"NQ100")   || Contains(core,"TECH100")||
      Contains(core,"USATECH") || Contains(core,"US_100"))
      return(SRP_ASSET_INDEX_NASDAQ);

   //=== GOLD. XAU is unambiguous; "GOLD" needs care because it also
   //=== appears in exotic names, so it is matched on the core only.
   if(Contains(core,"XAU") || core=="GOLD" || Contains(core,"GOLDUSD"))
      return(SRP_ASSET_METAL_GOLD);

   //=== OTHER METALS.
   if(Contains(core,"XAG") || Contains(core,"SILVER") ||
      Contains(core,"XPT") || Contains(core,"XPD")    ||
      Contains(core,"PLATINUM") || Contains(core,"PALLADIUM"))
      return(SRP_ASSET_METAL_OTHER);

   //=== CRYPTO.
   if(Contains(core,"BTC") || Contains(core,"ETH")  ||
      Contains(core,"XRP") || Contains(core,"LTC")  ||
      Contains(core,"BITCOIN") || Contains(core,"DOGE")||
      Contains(core,"SOL") || Contains(core,"ADA"))
      return(SRP_ASSET_CRYPTO);

   //=== OTHER INDICES.
   if(Contains(core,"US30")   || Contains(core,"DJ30")   ||
      Contains(core,"DOW")    || Contains(core,"US500")  ||
      Contains(core,"SPX")    || Contains(core,"SP500")  ||
      Contains(core,"GER")    || Contains(core,"DAX")    ||
      Contains(core,"UK100")  || Contains(core,"FTSE")   ||
      Contains(core,"JP225")  || Contains(core,"NIKKEI") ||
      Contains(core,"HK50")   || Contains(core,"AUS200") ||
      Contains(core,"EU50")   || Contains(core,"STOXX"))
      return(SRP_ASSET_INDEX_OTHER);

   //=== FOREX. Decided from the broker's own currency fields rather
   //=== than from the name, which is far more reliable than guessing.
   const string base  = SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
   const string profit= SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT);
   const ENUM_SYMBOL_CALC_MODE calc=
      (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE);
   if(calc==SYMBOL_CALC_MODE_FOREX ||
      calc==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)
      if(base!="" && profit!="" && StringLen(base)==3 && StringLen(profit)==3)
         return(SRP_ASSET_FOREX);

   //--- Unrecognised. Say so rather than guessing: a wrong preset is
   //--- worse than no preset, because it would size every trade wrongly.
   return(SRP_ASSET_UNKNOWN);
  }
//+------------------------------------------------------------------+
string CSymbolClassifier::ClassName(const ENUM_SRP_ASSET_CLASS asset_class)
  {
   switch(asset_class)
     {
      case SRP_ASSET_INDEX_NASDAQ: return("NASDAQ index");
      case SRP_ASSET_INDEX_OTHER:  return("equity index");
      case SRP_ASSET_METAL_GOLD:   return("gold");
      case SRP_ASSET_METAL_OTHER:  return("metal");
      case SRP_ASSET_FOREX:        return("forex");
      case SRP_ASSET_CRYPTO:       return("crypto");
     }
   return("unrecognised");
  }
//+------------------------------------------------------------------+
//| FILLING MODE RESOLUTION.                                           |
//|                                                                  |
//| Sending an unsupported filling mode is rejected outright by the     |
//| server, so it is resolved from the broker's own flags rather than   |
//| assumed. Market execution brokers generally want IOC or FOK;        |
//| exchange execution wants whatever the venue supports.               |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CSymbolClassifier::ResolveFilling(
                                    const int flags,
                                    const ENUM_SYMBOL_TRADE_EXECUTION mode)
  {
   //--- SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2 (bit flags).
   const bool fok=((flags & SYMBOL_FILLING_FOK)!=0);
   const bool ioc=((flags & SYMBOL_FILLING_IOC)!=0);

   //--- IOC first for market/instant execution: a partial fill is better
   //--- than a rejection on a fast-moving index.
   if(mode==SYMBOL_TRADE_EXECUTION_MARKET ||
      mode==SYMBOL_TRADE_EXECUTION_INSTANT)
     {
      if(ioc) return(ORDER_FILLING_IOC);
      if(fok) return(ORDER_FILLING_FOK);
     }
   if(fok) return(ORDER_FILLING_FOK);
   if(ioc) return(ORDER_FILLING_IOC);
   //--- Neither flag set means the symbol accepts RETURN only, which is
   //--- the correct answer for exchange-executed instruments.
   return(ORDER_FILLING_RETURN);
  }
//+------------------------------------------------------------------+
//| RESOLVE. Reads every contract fact from the terminal.              |
//|                                                                  |
//| Nothing is defaulted or inferred. A field the broker cannot supply  |
//| makes the profile unresolved, because a downstream division by a    |
//| zero point or volume step is how accounts get damaged.              |
//+------------------------------------------------------------------+
bool CSymbolClassifier::Resolve(const string symbol,SSymbolProfile &profile)
  {
   profile.Reset();
   profile.symbol=symbol;

   if(symbol=="")
     {
      profile.resolve_error="empty symbol name";
      return(false);
     }

   //--- A symbol absent from Market Watch returns zeroes rather than
   //--- failing, so selection is verified before anything is trusted.
   if(!SymbolSelect(symbol,true))
     {
      profile.resolve_error="symbol could not be selected in Market Watch";
      return(false);
     }

   profile.asset_class = Classify(symbol);
   profile.class_name  = ClassName(profile.asset_class);

   //--- Quote geometry.
   profile.digits        = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   profile.point         = SymbolInfoDouble(symbol,SYMBOL_POINT);
   profile.tick_size     = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   profile.tick_value    = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   profile.contract_size = SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);

   //--- Volume rules.
   profile.volume_min    = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   profile.volume_max    = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   profile.volume_step   = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   profile.volume_limit  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT);

   //--- Distance rules.
   profile.stops_level   = (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   profile.freeze_level  = (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   //--- Cost and margin.
   profile.spread_current= (double)SymbolInfoInteger(symbol,SYMBOL_SPREAD);
   profile.spread_float  = (int)SymbolInfoInteger(symbol,SYMBOL_SPREAD_FLOAT);
   profile.margin_initial= SymbolInfoDouble(symbol,SYMBOL_MARGIN_INITIAL);
   profile.margin_hedged = SymbolInfoDouble(symbol,SYMBOL_MARGIN_MAINTENANCE);
   profile.swap_long     = SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG);
   profile.swap_short    = SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT);

   //--- Execution.
   profile.trade_mode     = (ENUM_SYMBOL_TRADE_MODE)
                            SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   profile.execution_mode = (ENUM_SYMBOL_TRADE_EXECUTION)
                            SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
   profile.calc_mode      = (ENUM_SYMBOL_CALC_MODE)
                            SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE);
   profile.filling_flags  = (int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   profile.preferred_filling=ResolveFilling(profile.filling_flags,
                                            profile.execution_mode);

   //--- Broker quote schedule, so a session filter can be cross-checked
   //--- against what the venue is actually doing today.
   const datetime now=TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now,dt);
   datetime from=0,to=0;
   profile.quotes_today=SymbolInfoSessionQuote(symbol,
                              (ENUM_DAY_OF_WEEK)dt.day_of_week,0,from,to);
   profile.trades_today=SymbolInfoSessionTrade(symbol,
                              (ENUM_DAY_OF_WEEK)dt.day_of_week,0,from,to);

   //--- THE DERIVED FIGURE EVERY RISK CALCULATION DEPENDS ON.
   //--- Priced through the terminal, not from tick_value: this broker
   //--- reports gold with tick_size 0.01 and tick_value 0.10 against a
   //--- 100 oz contract, which understates real loss tenfold. Asking
   //--- OrderCalcProfit uses the broker's own contract specification and
   //--- is therefore right on metals, indices and FX without special
   //--- cases. See docs/BACKTESTING.md for the measured consequence.
   const double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   if(ask>0.0 && profile.point>0.0)
     {
      //--- 1000 points is a large enough distance to avoid rounding
      //--- noise in the broker's own arithmetic, then scaled back down.
      const double probe_points=1000.0;
      double loss=0.0;
      if(OrderCalcProfit(ORDER_TYPE_BUY,symbol,1.0,ask,
                         ask-probe_points*profile.point,loss))
         profile.money_per_point_per_lot=MathAbs(loss)/probe_points;
     }

   //--- VALIDATION. Every one of these is divided by downstream.
   if(profile.point<=0.0)
      profile.resolve_error="broker reports point size 0";
   else if(profile.digits<=0)
      profile.resolve_error="broker reports 0 digits";
   else if(profile.volume_step<=0.0)
      profile.resolve_error="broker reports volume step 0";
   else if(profile.volume_min<=0.0)
      profile.resolve_error="broker reports minimum volume 0";
   else if(profile.tick_size<=0.0)
      profile.resolve_error="broker reports tick size 0";

   profile.resolved=(profile.resolve_error=="");
   return(profile.resolved);
  }
//+------------------------------------------------------------------+
string CSymbolClassifier::Describe(const SSymbolProfile &profile)
  {
   if(!profile.resolved)
      return(StringFormat("Symbol %s UNRESOLVED: %s",
                          profile.symbol,profile.resolve_error));

   string filling="RETURN";
   if(profile.preferred_filling==ORDER_FILLING_IOC) filling="IOC";
   if(profile.preferred_filling==ORDER_FILLING_FOK) filling="FOK";

   string mode="DISABLED";
   switch(profile.trade_mode)
     {
      case SYMBOL_TRADE_MODE_FULL:      mode="FULL";       break;
      case SYMBOL_TRADE_MODE_LONGONLY:  mode="LONG ONLY";  break;
      case SYMBOL_TRADE_MODE_SHORTONLY: mode="SHORT ONLY"; break;
      case SYMBOL_TRADE_MODE_CLOSEONLY: mode="CLOSE ONLY"; break;
     }

   string text=StringFormat("Symbol %s [%s]",profile.symbol,profile.class_name);
   text+=StringFormat("\n  quote: digits=%d point=%.*f tickSize=%.*f "
                      "contract=%.2f",
                      profile.digits,profile.digits+2,profile.point,
                      profile.digits+2,profile.tick_size,
                      profile.contract_size);
   text+=StringFormat("\n  volume: min=%.4f max=%.2f step=%.4f limit=%.2f",
                      profile.volume_min,profile.volume_max,
                      profile.volume_step,profile.volume_limit);
   text+=StringFormat("\n  distance: stopsLevel=%d freezeLevel=%d spread=%.0f%s%s",
                      profile.stops_level,profile.freeze_level,
                      profile.spread_current,
                      (profile.spread_float!=0 ? " (floating)" : " (fixed)"),
                      //--- FIX 5. The spread printed here is the root of the
                      //--- whole trade geometry, so whether it is reproducible
                      //--- belongs on the same line as the number.
                      (profile.spread_pinned!=0 ? " [PINNED by input]"
                                                : " [live sample]"));
   text+=StringFormat("\n  execution: mode=%s filling=%s tradesToday=%s",
                      mode,filling,(profile.trades_today ? "yes" : "no"));
   text+=StringFormat("\n  risk: money per point per lot=%.5f",
                      profile.money_per_point_per_lot);
   if(profile.money_per_point_per_lot<=0.0)
      text+="  [UNAVAILABLE - sizing will fall back to tick arithmetic]";
   return(text);
  }

#endif // SRP_PROFILES_CSYMBOLCLASSIFIER_MQH
//+------------------------------------------------------------------+
