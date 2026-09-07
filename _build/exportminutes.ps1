# exportminutes.ps1
#   XauStructurePro - Research : deploy, compile and verify XSPExportMinutes.
#
# WHAT THIS DOES NOT DO: run the export. XSPExportMinutes is a Script, and a
# Script runs on a chart inside the terminal - the /config tester harness can
# only launch an Expert. That is not a limitation to work around, it is the
# whole point: inside the tester CopyTicksRange returns the TESTER's stream,
# which under any model but 4 is synthesised from M1 bars, and audit 6.2
# measured that stream's spread at 4.0-4.4 pts against 9.5-33.5 real. So the
# export must read the terminal's own archive, which means one manual step.
# This script makes that step safe: it proves the constants in the source are
# the pre-registered ones, proves the file compiles clean, puts the binary
# where the Navigator will find it, and moves any stale output aside.
#
# Run order:
#   powershell -File _build\exportminutes.ps1            # assert + compile + deploy
#   ... attach the script to a chart, wait for it to finish ...
#   powershell -File _build\exportminutes.ps1 -Verify    # check what it produced
param(
    [switch]$Verify,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Continue'
$mt5    = 'C:\Program Files\MetaTrader 5'
$ed     = Join-Path $mt5 'MetaEditor64.exe'
$mqlRt  = Join-Path $mt5 'MQL5'
$src    = 'c:\scalp robot\MQL5'
# MetaEditor's CLI refuses a build root containing spaces (Phase 1 lesson).
# A root of its own, not build.ps1's C:\srp_build, so the two do not wipe
# each other's artifacts when run back to back.
$scr    = 'C:\xsp_build\MQL5'
# FILE_COMMON's target is not assumed here: Phase A's CXspCsv wrote
# xsp_instances.csv, with FILE_COMMON, to exactly this path.
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\XauStructurePro'
$srcMq5 = Join-Path $src 'Scripts\XauStructurePro\XSPExportMinutes.mq5'
$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'

$fail = 0
function Say([string]$t) { Write-Output $t }
function Chk([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Output ("  OK   " + $name + "  " + $detail) }
    else     { Write-Output ("  FAIL " + $name + "  " + $detail); $script:fail++ }
}

# --------------------------------------------------------------------------
# 1. The constants in the source ARE the pre-registered constants.
#
# CHANGELOG 'XSP 0.2' lists, under "what would make this study unquotable",
# "any constant differing from the code". That sentence is worth nothing if
# nobody checks it, so it is checked here: the values below are transcribed
# from the pre-registration and compared against the .mq5 literally. A
# mismatch stops the run before anything is compiled or deployed.
# --------------------------------------------------------------------------
$want = [ordered]@{
    'InpSymbols'          = '"XAUUSD,EURUSD"'
    'InpFrom'             = "D'2025.05.27 00:00'"
    'InpTo'               = "D'2026.03.01 00:00'"
    'InpPrefix'           = '"xsp_minutes_"'
    'InpMaxSpreadSamples' = '65536'
}

Say ("XSP_EXPORTMINUTES " + $stamp)
Say ''
Say 'CONSTANTS (source vs CHANGELOG XSP 0.2)'
if (-not (Test-Path $srcMq5)) {
    Chk 'source present' $false $srcMq5
} else {
    $text = Get-Content $srcMq5 -Raw
    foreach ($k in $want.Keys) {
        $m = [regex]::Match($text, ('(?m)^\s*input\s+\w+\s+' + $k + '\s*=\s*(.+?)\s*;'))
        if (-not $m.Success) { Chk $k $false 'not declared as an input'; continue }
        $got = $m.Groups[1].Value.Trim()
        Chk $k ($got -eq $want[$k]) ("got " + $got + "  want " + $want[$k])
    }
    # Two properties of the file that matter more than any single constant.
    # Comment lines are stripped first: the header block SAYS "there is no
    # OrderSend", so scanning the raw text would fail the file for describing
    # itself accurately.
    $code = (($text -split "`n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    $ordr = [regex]::Matches($code, 'OrderSend|CTrade|PositionOpen|trade\.Buy|trade\.Sell').Count
    Chk 'no trading code' ($ordr -eq 0) ("order-function matches=" + $ordr)

    Chk 'VAL guard present' ($text -match "InpTo>D'2026\.03\.01 00:00'") 'refuses InpTo past 2026.03.01'
}
if ($fail -gt 0) {
    Say ''
    Say ("XSP_EXPORTMINUTES checks_failed=" + $fail + " VERDICT=FAIL")
    Say 'Nothing was compiled or deployed. Fix the source or the transcription above.'
    exit 1
}

function CompileOne([string]$mq5, [string]$incRoot) {
    # Returns "errors warnings ex5present". MetaEditor writes a UTF-16 log and
    # returns a useless exit code, so the log is the only source of truth.
    $log = [System.IO.Path]::ChangeExtension($mq5, '.buildlog')
    $ex5 = [System.IO.Path]::ChangeExtension($mq5, '.ex5')
    if (Test-Path $ex5) { Remove-Item $ex5 -Force }
    if (Test-Path $log) { Remove-Item $log -Force }
    cmd /c "`"$ed`" /compile:`"$mq5`" /inc:`"$incRoot`" /log:`"$log`"" 2>&1 | Out-Null
    $e = -1; $w = -1
    if (Test-Path $log) {
        $lines = Get-Content $log -Encoding Unicode -ErrorAction SilentlyContinue
        foreach ($l in $lines) {
            if ($l -match 'error|warning') {
                if ($l -notmatch 'information:' -and $l -notmatch '(\d+) errors?, (\d+) warnings?') {
                    Write-Output ("       | " + $l.Trim())
                }
            }
        }
        $res = $lines | Where-Object { $_ -match 'Result:' } | Select-Object -Last 1
        if ($res -match '(\d+) errors?, (\d+) warnings?') { $e = [int]$Matches[1]; $w = [int]$Matches[2] }
    }
    return @($e, $w, (Test-Path $ex5))
}

if (-not $Verify) {
    # ----------------------------------------------------------------------
    # 2. Compile gate in a scratch tree. Separate from the deploy so a broken
    #    source can never reach the terminal's Navigator.
    # ----------------------------------------------------------------------
    Say ''
    Say 'COMPILE GATE (scratch tree)'
    if (Test-Path $scr) { Remove-Item $scr -Recurse -Force }
    New-Item -ItemType Directory -Path $scr -Force | Out-Null
    Copy-Item (Join-Path $src 'Include')  -Destination $scr -Recurse -Force
    Copy-Item (Join-Path $src 'Scripts')  -Destination $scr -Recurse -Force
    $t = Join-Path $scr 'Scripts\XauStructurePro\XSPExportMinutes.mq5'
    $r = CompileOne $t $scr
    Chk 'compiles'   ($r[2] -eq $true) ('ex5=' + $r[2] + '  ' + $t)
    Chk '0 errors'   ($r[0] -eq 0)     ('errors=' + $r[0])
    Chk '0 warnings' ($r[1] -eq 0)     ('warnings=' + $r[1])
    if ($fail -gt 0) {
        Say ''
        Say ("XSP_EXPORTMINUTES checks_failed=" + $fail + " VERDICT=FAIL")
        Say 'NOT deployed - the terminal still holds whatever it held before.'
        exit 1
    }

    # ----------------------------------------------------------------------
    # 3. Deploy into the terminal and compile there.
    #
    # Include\XauStructurePro and Scripts\XauStructurePro only. ScalpRobotPro
    # is not touched: AUDIT 9.5 uses the source copy of that tree as the
    # byte-identical comparison baseline, and backtest.ps1 owns its deploy.
    # ----------------------------------------------------------------------
    if ($SkipDeploy) {
        Say ''
        Say 'DEPLOY skipped (-SkipDeploy). The compile gate above is green; the'
        Say 'terminal has NOT been given this binary.'
        Say ("XSP_EXPORTMINUTES checks_failed=0 VERDICT=PASS")
        exit 0
    }
    Say ''
    Say 'DEPLOY (into the terminal tree)'
    foreach ($d in @('Include', 'Scripts')) {
        $dst = Join-Path $mqlRt "$d\XauStructurePro"
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item (Join-Path $src "$d\XauStructurePro") -Destination (Join-Path $mqlRt $d) -Recurse -Force
        Chk ("copied " + $d) (Test-Path $dst) $dst
    }
    $t2 = Join-Path $mqlRt 'Scripts\XauStructurePro\XSPExportMinutes.mq5'
    $r2 = CompileOne $t2 $mqlRt
    Chk 'compiles in terminal tree' ($r2[2] -eq $true) ('ex5=' + $r2[2])
    Chk '0 errors (terminal tree)'   ($r2[0] -eq 0) ('errors=' + $r2[0])
    Chk '0 warnings (terminal tree)' ($r2[1] -eq 0) ('warnings=' + $r2[1])

    # ----------------------------------------------------------------------
    # 4. Move any previous output aside.
    #
    # The script opens for overwrite, so a fresh run replaces its own files -
    # but a run that fails halfway leaves a short file behind, and a short
    # file with a valid preamble is the one artifact that could be quoted as
    # a complete dataset. Archived rather than deleted.
    # ----------------------------------------------------------------------
    Say ''
    Say 'PREVIOUS OUTPUT'
    if (Test-Path $common) {
        $old = Get-ChildItem $common -Filter 'xsp_minutes_*.csv' -ErrorAction SilentlyContinue
        if ($old.Count -eq 0) { Say '  none' }
        foreach ($o in $old) {
            $bak = Join-Path $common ($o.BaseName + '.' + $stamp + '.bak')
            Move-Item $o.FullName $bak -Force
            Say ('  moved aside: ' + $o.Name + ' -> ' + (Split-Path $bak -Leaf) + '  (' + $o.Length + ' B)')
        }
    } else { Say ('  common folder does not exist yet: ' + $common) }

    Say ''
    if ($fail -gt 0) {
        Say ("XSP_EXPORTMINUTES checks_failed=" + $fail + " VERDICT=FAIL")
        exit 1
    }
    Say ("XSP_EXPORTMINUTES checks_failed=0 VERDICT=PASS")
    Say ''
    Say '=== THE ONE MANUAL STEP ==================================='
    Say ''
    Say ' 1. Open MetaTrader 5.'
    Say ' 2. Navigator (Ctrl+N) -> Scripts -> XauStructurePro -> XSPExportMinutes.'
    Say '    Not there? right-click Scripts -> Refresh.'
    Say ' 3. Open ANY chart. The script exports the symbols named in its input,'
    Say '    not the chart symbol, so which chart it is does not matter.'
    Say ' 4. Double-click the script. The inputs dialog opens. Check that it reads'
    Say '       InpSymbols = XAUUSD,EURUSD'
    Say '       InpFrom    = 2025.05.27 00:00'
    Say '       InpTo      = 2026.03.01 00:00'
    Say '    then OK. If MT5 remembered different values from a previous run,'
    Say '    correct them here - the dialog wins over the source defaults.'
    Say ' 5. Watch Toolbox -> Experts for lines starting XSP_EXPORT. Expect'
    Say '    minutes, not seconds: XAUUSD alone is ~60.5M ticks over 279 days.'
    Say '    Leave the chart and the terminal open until it prints'
    Say '       XSP_EXPORT symbols=2 of 2 VERDICT=PASS'
    Say ' 6. A "FAIL CopyTicksRange" line means the archive was still paging in.'
    Say '    It retries 5 times per day internally; if it still fails, run the'
    Say '    script again - the files are rewritten from scratch each time.'
    Say ''
    Say ' Then:  powershell -File _build\exportminutes.ps1 -Verify'
    Say ''
    Say ' Output lands in:'
    Say ("   " + $common)
    Say '     xsp_minutes_XAUUSD.csv'
    Say '     xsp_minutes_EURUSD.csv'
    Say '==========================================================='
    exit 0
}

# --------------------------------------------------------------------------
# 5. -Verify : structural check of what the terminal actually wrote.
#
# Structure and provenance only. Every statistic that decides anything lives
# in _build\xspresidual.py and is pre-registered; this is here to catch a
# truncated file, a wrong span, a stale file, or a schema drift BEFORE the
# analysis runs and quietly reports a number computed on the wrong data.
# --------------------------------------------------------------------------
$HDR  = 'epoch,o,h,l,c,ticks,spread_med_pts,spread_p90_pts,spread_n'
$FROM = [int64]([datetime]::new(2025,5,27,0,0,0) - [datetime]::new(1970,1,1)).TotalSeconds
$TO   = [int64]([datetime]::new(2026,3,1,0,0,0) - [datetime]::new(1970,1,1)).TotalSeconds

$agg = @{}
foreach ($sym in @('XAUUSD', 'EURUSD')) {
    $p = Join-Path $common ('xsp_minutes_' + $sym + '.csv')
    Say ''
    Say ('FILE ' + $sym)
    if (-not (Test-Path $p)) { Chk 'present' $false $p; continue }
    $fi = Get-Item $p
    $rows = 0; $bad = 0; $nonmono = 0; $oob = 0; $noSpr = 0
    $ticks = [int64]0; $sn = [int64]0
    $minE = [int64]::MaxValue; $maxE = [int64]::MinValue; $prev = [int64]-1
    $hdrOk = $false; $hasProv = $false; $hasCav = $false; $totRows = [int64]-1
    $set = New-Object 'System.Collections.Generic.HashSet[int64]'
    $sr = New-Object System.IO.StreamReader($p)
    while ($null -ne ($line = $sr.ReadLine())) {
        if ($line.Length -eq 0) { continue }
        if ($line[0] -eq '#') {
            if ($line -match 'xsp_export:.*schema=xsp-minute-v1') { $hasProv = $true }
            if ($line -match 'xsp_export_caveats:')               { $hasCav  = $true }
            if ($line -match 'xsp_export_totals:.*rows=(\d+)')    { $totRows = [int64]$Matches[1] }
            continue
        }
        if ($line -eq $HDR) { $hdrOk = $true; continue }
        $f = $line.Split(',')
        if ($f.Count -ne 9) { $bad++; continue }
        # TryParse rather than a cast in try/catch: a cast failure is a
        # terminating error, and one stray byte should cost one row, not the run.
        $e = [int64]0; $tk = [int64]0; $ns = [int64]0
        if (-not ([int64]::TryParse($f[0], [ref]$e) -and
                  [int64]::TryParse($f[5], [ref]$tk) -and
                  [int64]::TryParse($f[8], [ref]$ns))) { $bad++; continue }

        if ($e -le $prev) { $nonmono++ }
        $prev = $e
        if ($e -lt $FROM -or $e -ge $TO) { $oob++ }
        if ($e -lt $minE) { $minE = $e }
        if ($e -gt $maxE) { $maxE = $e }
        if ($ns -le 0) { $noSpr++ }
        $ticks += $tk; $sn += $ns
        [void]$set.Add($e)
        $rows++
    }
    $sr.Close()

    $d0 = if ($rows -gt 0) { [datetime]::new(1970,1,1).AddSeconds($minE).ToString('yyyy.MM.dd HH:mm') } else { '-' }
    $d1 = if ($rows -gt 0) { [datetime]::new(1970,1,1).AddSeconds($maxE).ToString('yyyy.MM.dd HH:mm') } else { '-' }
    Chk 'provenance line' $hasProv 'schema=xsp-minute-v1'
    Chk 'caveats line'    $hasCav  ''
    Chk 'header exact'    $hdrOk   $HDR
    Chk 'totals trailer'  ($totRows -ge 0) ("declared rows=" + $totRows)
    Chk 'rows match trailer' ($totRows -eq $rows) ("counted=" + $rows + " declared=" + $totRows)
    Chk 'rows > 0'        ($rows -gt 0) ("rows=" + $rows)
    Chk 'no malformed rows' ($bad -eq 0) ("bad=" + $bad)
    Chk 'epoch strictly increasing' ($nonmono -eq 0) ("violations=" + $nonmono)
    Chk 'inside declared span' ($oob -eq 0) ("outside=" + $oob + "  span " + $d0 + " .. " + $d1)
    Chk 'epoch is minute-aligned' (($minE % 60) -eq 0 -and ($maxE % 60) -eq 0) ''
    Say ('  ..   bytes=' + $fi.Length + '  ticks=' + $ticks + '  spread_samples=' + $sn +
         '  minutes_without_spread=' + $noSpr)
    if ($rows -gt 0) {
        Say ('  ..   ticks/minute mean=' + [math]::Round($ticks / $rows, 1) +
             '  coverage=' + [math]::Round(100.0 * $rows / (($TO - $FROM) / 60), 2) + '% of all clock minutes')
    }
    $agg[$sym] = $set
}

# --- cross-checks against Phase A, and the alignment the study depends on ---
#
# Phase A's provenance trailer, from _build\_xsp\dev_20260905_170205\run.log,
# recorded ticks=60541601 and minutes=268353 for XAUUSD over this exact span.
# Printed as a ratio, not asserted: the tester counted the ticks it was fed,
# this counts what the archive holds, and the two can differ at the day
# boundaries without either being wrong. A ratio far from 1.0 is the signal.
Say ''
Say 'CROSS-CHECK'
if ($agg.ContainsKey('XAUUSD')) {
    $nx = $agg['XAUUSD'].Count
    Say ('  XAUUSD minutes exported=' + $nx + '  Phase A saw 268353  ratio=' +
         [math]::Round($nx / 268353.0, 4))
} else { Say '  XAUUSD not read' }

Say ''
Say 'ALIGNMENT (upper bound on the study sample)'
if ($agg.ContainsKey('XAUUSD') -and $agg.ContainsKey('EURUSD')) {
    $sx = $agg['XAUUSD']; $se = $agg['EURUSD']
    $both = [System.Collections.Generic.HashSet[int64]]::new([int64[]]$sx)
    $both.IntersectWith($se)
    $nb = $both.Count
    Say ('  minutes in XAUUSD only : ' + ($sx.Count - $nb))
    Say ('  minutes in EURUSD only : ' + ($se.Count - $nb))
    Say ('  minutes in BOTH        : ' + $nb)

    Say ''
    Say '  This is an UPPER BOUND, not the sample size. The pre-registered VALID'
    Say '  rule also requires a tick in t-1 for both symbols and a gap of no more'
    Say '  than 5 clock minutes from the previous valid minute, and triggers are'
    Say '  then thinned to non-overlapping windows. xspresidual.py reports the'
    Say '  real n and the pre-registered gates judge it.'
} else { Say '  both files needed; skipped' }

Say ''
if ($fail -gt 0) {
    Say ("XSP_EXPORTMINUTES_VERIFY checks_failed=" + $fail + " VERDICT=FAIL")
    Say 'Do not run the analysis on these files.'
    exit 1
}
Say ("XSP_EXPORTMINUTES_VERIFY checks_failed=0 VERDICT=PASS")
Say 'Next:  python _build\xspresidual.py'
exit 0






