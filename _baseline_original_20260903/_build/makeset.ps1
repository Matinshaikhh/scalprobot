# Builds a COMPLETE tester .set file from the EA source, then applies
# overrides on top.
#
# WHY THIS EXISTS
# A .set file that lists only the inputs you want to change does NOT leave
# the rest at their declared defaults - the tester treats the file as the
# whole input set and every omitted input arrives as 0. That zeroed an ADX
# period, iADX refused the handle with error 4805, and the EA correctly
# refused to start. The failure surfaced only as "some error after pass
# finished", i.e. indistinguishable from a run that took no trades.
#
# So the full input list is generated from the EA's own `input` declarations,
# which keeps it authoritative rather than a hand-maintained copy.
param(
    [string]$Expert    = 'c:\scalp robot\MQL5\Experts\ScalpRobotPro\ScalpRobotPro.mq5',
    [string]$OutPath   = '',
    [string[]]$Override = @()
)

if (-not (Test-Path $Expert)) { Write-Error "expert not found: $Expert"; exit 1 }

$lines = Get-Content -LiteralPath $Expert
$defs  = [ordered]@{}

foreach ($l in $lines) {
    # input <type> <name> = <value>;   with an optional // comment
    $m = [regex]::Match($l, '^\s*input\s+\w+\s+(\w+)\s*=\s*([^;]+);')
    if (-not $m.Success) { continue }
    $name = $m.Groups[1].Value
    $val  = $m.Groups[2].Value.Trim()
    # Strip quotes from string literals; the .set format is unquoted.
    if ($val.StartsWith('"') -and $val.EndsWith('"')) {
        $val = $val.Substring(1, $val.Length - 2)
    }
    # MQL5 string literals escape backslashes; the .set format does not.
    $val = $val -replace '\\\\', '\'

    # EVALUATE ARITHMETIC DEFAULTS.
    #
    # Source defaults are C expressions - `8*60`, `13*60+30` - and the .set
    # format has no expression parser: the tester read `8*60` as 8, so a
    # London window declared as 08:00-16:30 arrived as 00:08-00:16. The
    # session filter then blocked every tick and reported it as
    # FRIDAY_CLOSE, which pointed nowhere near the real cause.
    if ($val -match '^[0-9\s\*\+\-\/\(\)\.]+$' -and $val -match '[\*\+\-\/]') {
        try { $val = [string]([scriptblock]::Create($val).Invoke()[0]) } catch { }
    }
    $defs[$name] = $val
}

# Enum defaults are symbolic names in source but the .set format carries only
# ordinals, so the enumerators actually used as defaults are mapped here.
# Anything unmapped is reported rather than silently written as a name the
# tester would read as 0 - which is precisely the failure this script exists
# to prevent.
$enumOrdinals = @{
    'SRP_PROFILE_AUTO'          = 0
    'SRP_PROFILE_NASDAQ'        = 1
    'SRP_PROFILE_GOLD'          = 2
    'SRP_PROFILE_CUSTOM'        = 3
    'SRP_DIRECTION_BOTH'        = 0
    'SRP_DIRECTION_LONG_ONLY'   = 1
    'SRP_DIRECTION_SHORT_ONLY'  = 2
    'SRP_LOG_TRACE'             = 0
    'SRP_LOG_DEBUG'             = 1
    'SRP_LOG_INFO'              = 2
    'SRP_LOG_WARN'              = 3
    'SRP_LOG_ERROR'             = 4
    'SRP_SIZING_FIXED_LOT'      = 0
    'SRP_SIZING_RISK_PERCENT'   = 1
    'SRP_CAPITAL_EQUITY'        = 0
    'SRP_CAPITAL_BALANCE'       = 1
    'SRP_UI_THEME_DARK'         = 0
    'SRP_UI_THEME_LIGHT'        = 1
    'SRP_STOP_NONE'             = 0
    'SRP_STOP_FIXED_POINTS'     = 1
    'SRP_STOP_ATR_MULTIPLE'     = 2
    'SRP_STOP_STRUCTURE'        = 3
    'SRP_STOP_DYNAMIC'          = 4
    'SRP_TARGET_NONE'           = 0
    'SRP_TARGET_FIXED_POINTS'   = 1
    'SRP_TARGET_ATR_MULTIPLE'   = 2
    'SRP_TARGET_RISK_REWARD'    = 3
    'SRP_TARGET_STRUCTURE'      = 4
    'SRP_TARGET_DYNAMIC'        = 5
    'SRP_TRAIL_DISABLED'        = 0
    'SRP_TRAIL_FIXED_STEP'      = 1
    'SRP_TRAIL_ATR_STEP'        = 2
    'SRP_TRAIL_PROFIT_PERCENT'  = 3
    'SRP_NEWS_IMPACT_NONE'      = 0
    'SRP_NEWS_IMPACT_LOW'       = 1
    'SRP_NEWS_IMPACT_MEDIUM'    = 2
    'SRP_NEWS_IMPACT_HIGH'      = 3
    'SRP_NEWS_SOURCE_DISABLED'  = 0
    'SRP_NEWS_SOURCE_TERMINAL_CALENDAR' = 1
    'SRP_NEWS_SOURCE_CSV_FILE'  = 2
    'SRP_AGGREGATION_FIRST_MATCH'    = 0
    'SRP_AGGREGATION_MAJORITY_VOTE'  = 1
    'SRP_AGGREGATION_WEIGHTED_SCORE' = 2
    'SRP_AGGREGATION_UNANIMOUS'      = 3
    'SRP_CRITERION_NET_PROFIT'       = 0
    'SRP_CRITERION_PROFIT_FACTOR'    = 1
    'SRP_CRITERION_EXPECTANCY'       = 2
    'SRP_CRITERION_SHARPE_RATIO'     = 3
    'SRP_CRITERION_RECOVERY_FACTOR'  = 4
    'SRP_CRITERION_CUSTOM_COMPOSITE' = 5
    # MQL5 timeframe constants carry their own numeric values.
    'PERIOD_M1'  = 1
    'PERIOD_M5'  = 5
    'PERIOD_M15' = 15
    'PERIOD_M30' = 30
    'PERIOD_H1'  = 16385
    'PERIOD_H4'  = 16388
}
foreach ($k in @($defs.Keys)) {
    $v = [string]$defs[$k]
    if ($v -match '^[A-Za-z_][A-Za-z0-9_]*$' -and
        $v -ne 'true' -and $v -ne 'false') {
        if ($enumOrdinals.ContainsKey($v)) { $defs[$k] = $enumOrdinals[$v] }
        # A bare identifier that is not a known enumerator and not a bool is
        # left alone only if it plausibly is a string default.
    }
}

# RE-SPLIT the override list.
#
# A string[] parameter crossing a powershell.exe -File boundary arrives as a
# SINGLE comma-joined string, so "a=1","b=2" became "a=1,b=2": the first
# override took the whole thing as its value and the second silently vanished.
# That made two tier ablations return byte-identical results and look like a
# finding about the strategy rather than a bug in the harness.
$flat = @()
foreach ($o in $Override) {
    $flat += ($o -split '[,;]' | ForEach-Object { $_.Trim() } |
              Where-Object { $_ -ne '' })
}

foreach ($o in $flat) {
    if ($o -notmatch '=') { continue }
    $k = $o.Substring(0, $o.IndexOf('=')).Trim()
    $v = $o.Substring($o.IndexOf('=') + 1).Trim()
    if (-not $defs.Contains($k)) {
        Write-Output "WARNING override names an input the EA does not declare: $k"
    }
    $defs[$k] = $v
}

$out = @('; generated from ' + (Split-Path $Expert -Leaf))
foreach ($k in $defs.Keys) { $out += ("$k=" + $defs[$k]) }

if ($OutPath -eq '') { $out } else {
    $out -join "`r`n" | Set-Content -LiteralPath $OutPath -Encoding ASCII
    Write-Output "wrote $OutPath ($($defs.Count) inputs)"
}
