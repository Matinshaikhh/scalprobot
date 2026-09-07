#!/bin/bash
# fetch_panel.sh - the XTM cross-instrument replication panel.
#
# The panel is named on LIQUIDITY and ASSET-CLASS-COVERAGE grounds before
# a single return is looked at. It is not chosen from anything measured.
# Its job in gate G5 is to answer one question: does the IDENTICAL,
# unmodified, gold-fitted rule work on instruments it was never fitted
# to? That is the only defence against data-mining that cannot itself be
# gamed, because the parameters are frozen before the panel is touched.
#
# Deliberately spans six asset classes. A trend premium that is real is a
# statement about how markets absorb information, so it should not care
# whether the underlying is metal, currency, equity or energy. One that
# only shows up in gold is a gold story, not a trend story, and gate G5
# is written to catch exactly that.

cd "$(dirname "$0")/data" || exit 1
P1=0
P2=1790000000
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

fetch () {
  sym="$1"; out="$2"
  url="https://query1.finance.yahoo.com/v8/finance/chart/${sym}?period1=${P1}&period2=${P2}&interval=1d"
  curl -s -A "$UA" "$url" -o "$out"
  n=$(python -c "
import json,sys
try:
    d=json.load(open('$out'))
    r=d['chart']['result'][0]
    ts=r['timestamp']; c=r['indicators']['quote'][0]['close']
    ok=[x for x in c if x is not None]
    import datetime
    a=datetime.datetime.fromtimestamp(ts[0],datetime.UTC).date()
    b=datetime.datetime.fromtimestamp(ts[-1],datetime.UTC).date()
    print('n=%d ok=%d %s .. %s'%(len(ts),len(ok),a,b))
except Exception as e:
    print('FAILED %s'%e)
")
  printf '  %-12s %-22s %s\n' "$sym" "$out" "$n"
}

echo "XTM replication panel - six asset classes, named before measurement"
echo
echo "FX majors (currency):"
fetch "EURUSD=X"   "y_eurusd.json"
fetch "GBPUSD=X"   "y_gbpusd.json"
fetch "JPY=X"      "y_usdjpy.json"
fetch "AUDUSD=X"   "y_audusd.json"
fetch "CAD=X"      "y_usdcad.json"
fetch "CHF=X"      "y_usdchf.json"
echo
echo "Equity indices:"
fetch "%5EGSPC"    "y_spx.json"
fetch "%5ENDX"     "y_ndx.json"
echo
echo "Energy:"
fetch "CL=F"       "y_crude.json"
fetch "NG=F"       "y_natgas.json"
echo
echo "Metals (non-gold):"
fetch "SI=F"       "y_silver.json"
fetch "HG=F"       "y_copper.json"
echo
echo "Rates:"
fetch "ZN=F"       "y_note10y.json"
echo
echo "Dollar index (long history):"
fetch "DX-Y.NYB"   "y_dxy.json"
echo
echo "PANEL FETCH COMPLETE"
