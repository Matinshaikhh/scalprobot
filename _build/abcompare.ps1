# A/B: does harness v2 change any TRADING DECISION?
#
# WHAT THIS TEST IS FOR
# Audit section 11 step 2 asserts that fixes 2 and 4 are observation-only, and
# the handoff names the test that would actually establish it: "no entry or
# exit differs from baseline on a period with no daily breach". This script
# runs that pair and nothing else. It does not tune anything, and neither side
# is allowed to be the "improved" one - both are measured identically.
#
# HOW THE THREE BEHAVIOURAL FIXES ARE NEUTRALISED
# Fixes 1 and 3 provably DO change decisions, so a naive 1.00-vs-1.10 diff
# measures them and says nothing about fix 4. They are switched off by
# configuration rather than by choosing a flattering period:
#
#   fix 3  InpScalpCommissionPoints=0.0   restores the 1.00 cost model. With
#          the 6.0 default the funnel blocked 24 of 57 signals on COST where
#          1.00 blocked 9 of 25, which swamps everything else.
#   fix 1  InpDailyLimitTerminal=true     restores the 1.00 latch, so a daily
#          breach ends the run on BOTH sides instead of standing down on one.
#
# What remains between the two binaries is then fix 2 (measuring server-side
# fills) and fix 4 (the provenance header) - both claimed to be inert. Any
# difference in the deal stream is therefore either a refutation of that claim
# or a regression, and both are worth knowing about.
#
# WHY THE BINARIES ARE STAGED UNDER A SEPARATE FOLDER WITH NO SOURCE
# The baseline is a preserved 1.00 EX5; there is no 1.00 source in the tree to
# rebuild it from. Staging both sides in Experts\SRP_AB\ with NO .mq5 beside
# them means nothing can recompile either binary mid-experiment, and the EA the
# terminal already has loaded is left alone.
param(
    [string]$Symbol    = 'XAUUSD',
    [string]$From      = '2026.09.01',
    # 2026.09.01 .. 2026.09.02 is chosen because the BASELINE's behaviour over
    # it is already on record: the 1.00 passes of 2026-09-03 took 15 entries
    # from 25 signals and ended at 4897.76 USD, twice, from a 5000 deposit.
    # The baseline side of this experiment is therefore expected to reproduce
    # 4897.76 exactly, which makes it a control on the harness itself rather
    # than just one half of a comparison.
    [string]$To        = '2026.09.02',
    # The chart period is PINNED, and not because it was proven irrelevant.
    # This EA reads InpContextTimeframe and InpSetupTimeframe explicitly, so the
    # chart period should not be a decision input - but the two 1.00 passes that
    # reproduce 4897.76 over this period were BOTH on M1, and the one recorded
    # M5 pass over the same span produced a different funnel entirely
    # (3 signals -> 3 entries, 5001.80 USD). Whether that came from the chart
    # period or from different inputs has not been established, so nothing here
    # relies on it: both sides run M1, which is what the control was recorded on.
    [string]$Period    = 'M1',
    # 4 = every tick based on REAL TICKS. Deliberately not 1: on this feed
    # 1-minute OHLC generation models the spread three times too tight, which
    # is the finding that started the audit.
    [int]$Model        = 4,
    [int]$Deposit      = 5000,
    [int]$Leverage     = 100,
    [int]$TimeoutMs    = 1800000,
    # Stage and reconcile the .set files, then stop without launching. Use this
    # to inspect the experiment before spending an hour of tester time on it.
    [switch]$SetsOnly
)
$ErrorActionPreference = 'Continue'
$mt5      = 'C:\Program Files\MetaTrader 5'
$src      = 'c:\scalp robot\MQL5'
$baseSrc  = 'c:\scalp robot\_baseline_original_20260903\MQL5'
$term     = Join-Path $mt5 'terminal64.exe'
$mqlRt    = Join-Path $mt5 'MQL5'
$stage    = Join-Path $mqlRt 'Experts\SRP_AB'
$outDir   = 'c:\scalp robot\_build\_ab'
$baseEx5  = 'c:\scalp robot\_build\_deploy_backup\ScalpRobotPro.ex5.1.00.20260903-1651.bak'
$currEx5  = Join-Path $mqlRt 'Experts\ScalpRobotPro\ScalpRobotPro.ex5'

foreach ($p in @($baseEx5, $currEx5, $term)) {
    if (-not (Test-Path $p)) { Write-Output "MISSING: $p"; exit 1 }
}
New-Item -ItemType Directory -Path $stage  -Force | Out-Null
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# --- stage both binaries --------------------------------------------------
# Copy-Item, never Move-Item: the baseline .bak is the ONLY surviving copy of
# the pre-audit binary and the current .ex5 is what the terminal has loaded.
Get-ChildItem $stage -File -ErrorAction SilentlyContinue | Remove-Item -Force
Copy-Item $baseEx5 (Join-Path $stage 'srp_baseline_100.ex5') -Force
Copy-Item $currEx5 (Join-Path $stage 'srp_current_110.ex5')  -Force

$stray = Get-ChildItem $stage -File | Where-Object { $_.Extension -ne '.ex5' }
if ($stray) {
    # A .mq5 in the staging folder would let MetaEditor rebuild a side of the
    # experiment from whatever source happens to be current, silently turning
    # the baseline into another copy of the current build.
    Write-Output 'ABORT: non-.ex5 files in the staging folder:'
    $stray | ForEach-Object { '  ' + $_.Name }
    exit 1
}
Write-Output "staged in $stage"
Get-ChildItem $stage -Filter '*.ex5' | ForEach-Object {
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 16)
    Write-Output ("  {0,-24} {1,8} bytes  sha256 {2}  {3:yyyy-MM-dd HH:mm:ss}" -f
                  $_.Name, $_.Length, $h, $_.LastWriteTime)
}
# --- generate one COMPLETE .set per side ----------------------------------
# Each side's inputs are generated from ITS OWN source, because the two
# binaries do not declare the same input list: 1.10 adds InpDailyLimitTerminal
# and InpRunDataSegment. A set file generated from the wrong source would name
# inputs one binary does not have and omit ones it does, and an omitted input
# arrives as 0 rather than at its default.
$setDir   = Join-Path $mqlRt 'Profiles\Tester'
$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$mk       = 'c:\scalp robot\_build\makeset.ps1'
$baseSet  = "srp_ab_base_$stamp.set"
$currSet  = "srp_ab_curr_$stamp.set"

# The two overrides ARE the experiment: they configure 1.10 to price and latch
# exactly as 1.00 does, leaving only the observation-only fixes between them.
$currOverride = @('InpScalpCommissionPoints=0.0', 'InpDailyLimitTerminal=true')

# APPLIED TO BOTH SIDES, and not a preference.
#
# Both source versions declare InpCapitalBase = SRP_CAPITAL_EQUITY (0), but
# every recorded pass in this project's logs - 1.00 and 1.10 alike - ran with
# InpCapitalBase=1 (BALANCE), because the terminal had a saved input set that
# deviated from the source default. Risk sizing reads it, so it moves lot sizes
# and therefore decisions.
#
# Setting it here on BOTH sides costs nothing for the comparison, which only
# needs the two sides to agree, and buys the control below: with 1 the baseline
# side is expected to reproduce a figure already on record.
$commonOverride = @('InpCapitalBase=1')

# The falsifiable prediction. Two 1.00 passes on 2026-09-03 over this period
# with these inputs both ended here. If the baseline side lands anywhere else,
# the staging or the set file is wrong and the comparison means nothing.
$controlBalance = '4897.76'

& $mk -Expert (Join-Path $baseSrc 'Experts\ScalpRobotPro\ScalpRobotPro.mq5') `
      -OutPath (Join-Path $setDir $baseSet) -Override $commonOverride |
    Where-Object { $_ -match 'WARNING|wrote' } | ForEach-Object { "  base: $_" }
& $mk -Expert (Join-Path $src 'Experts\ScalpRobotPro\ScalpRobotPro.mq5') `
      -OutPath (Join-Path $setDir $currSet) `
      -Override ($commonOverride + $currOverride) |
    Where-Object { $_ -match 'WARNING|wrote' } | ForEach-Object { "  curr: $_" }

foreach ($s in @($baseSet, $currSet)) {
    if (-not (Test-Path (Join-Path $setDir $s))) {
        Write-Output "SET FILE NOT WRITTEN: $s"; exit 1
    }
}
Write-Output ("overrides on the 1.10 side: " + ($currOverride -join '; '))
# --- reconcile the two input sets -----------------------------------------
# THE CHECK THAT MAKES THE EXPERIMENT MEAN ANYTHING.
#
# An A/B where a shared input silently differs is not an A/B, and the two
# defaults that changed between 1.00 and 1.10 are exactly the kind of thing
# that goes unnoticed - one of them is a number in a comment. Every input
# declared by BOTH binaries is compared here, and anything that differs and is
# not a declared part of the experiment aborts the run rather than producing a
# result that would have to be withdrawn later.
function Read-Set([string]$path) {
    $h = @{}
    foreach ($l in (Get-Content -LiteralPath $path)) {
        if ($l -match '^\s*[;#]') { continue }
        if ($l -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() }
    }
    return $h
}
$bh = Read-Set (Join-Path $setDir $baseSet)
$ch = Read-Set (Join-Path $setDir $currSet)

# Differences that are the point of the test, not a flaw in it.
$expected = @('InpScalpCommissionPoints')
$shared = @($bh.Keys | Where-Object { $ch.ContainsKey($_) })
$mismatch = @()
foreach ($k in $shared) {
    if ($bh[$k] -ne $ch[$k]) { $mismatch += $k }
}
$onlyBase = @($bh.Keys | Where-Object { -not $ch.ContainsKey($_) })
$onlyCurr = @($ch.Keys | Where-Object { -not $bh.ContainsKey($_) })

Write-Output ''
Write-Output '--- input reconciliation ---'
Write-Output ("  inputs: base $($bh.Count), current $($ch.Count), shared $($shared.Count)")
if ($onlyBase.Count) { Write-Output ("  1.00 only: " + ($onlyBase -join ', ')) }
if ($onlyCurr.Count) { Write-Output ("  1.10 only: " + ($onlyCurr -join ', ')) }
foreach ($k in $mismatch) {
    $tag = if ($expected -contains $k) { 'BY DESIGN' } else { 'UNEXPECTED' }
    Write-Output ("  {0,-10} {1,-32} base={2}  curr={3}" -f $tag, $k, $bh[$k], $ch[$k])
}
$bad = @($mismatch | Where-Object { $expected -notcontains $_ })
if ($bad.Count) {
    Write-Output ''
    Write-Output 'ABORT: shared inputs differ that are not part of the experiment.'
    Write-Output '       Fix these before running, or the diff measures them instead'
    Write-Output '       of measuring fix 4.'
    exit 1
}
if ($mismatch.Count -eq 0) {
    # InpScalpCommissionPoints must appear here: 1.00 declares 0.0 and 1.10
    # declares 6.0, so the override having landed is what makes them equal.
    Write-Output '  note: no shared input differs, including the commission -'
    Write-Output '        confirm the override was applied, not silently dropped.'
}
if ($SetsOnly) { Write-Output ''; Write-Output 'SetsOnly: nothing launched.'; exit 0 }
# --- log reading (same approach as backtest.ps1) ---------------------------
# Read via a COPY: a terminal still holding the log makes a direct read throw,
# which would discard the report of a pass that actually completed. The
# encoding is sniffed rather than assumed - agent logs are UTF-16LE, some
# others are not.
function Read-MtLog([string]$path) {
    $tmp = Join-Path $env:TEMP ('srp_ab_' + [System.Guid]::NewGuid().ToString('N') + '.log')
    try { Copy-Item -LiteralPath $path -Destination $tmp -Force -ErrorAction Stop }
    catch { return @() }
    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $nulls = 0
    $limit = [Math]::Min(400, $bytes.Length)
    for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
    $text = if ($nulls -gt ($limit / 8)) { [System.Text.Encoding]::Unicode.GetString($bytes) }
            else { [System.Text.Encoding]::UTF8.GetString($bytes) }
    return ($text -split "`r?`n")
}

function Invoke-Pass([string]$side, [string]$expert, [string]$setName) {
    Write-Output ''
    Write-Output "=== $side : $expert ==="
    $ini = Join-Path $env:TEMP ("srp_ab_${side}_$stamp.ini")
    # Deposit and leverage are stated rather than left to the terminal's last
    # GUI setting, because a run whose account size came from a dialog is not
    # reproducible and cannot be compared with anything.
    $body = @"
[Tester]
Expert=$expert
ExpertParameters=$setName
Symbol=$Symbol
Period=$Period
Model=$Model
FromDate=$From
ToDate=$To
Optimization=0
ShutdownTerminal=1
Deposit=$Deposit
Currency=USD
Leverage=$Leverage
ExecutionMode=0
Visual=0
"@
    Set-Content -LiteralPath $ini -Value $body -Encoding ASCII

    # A terminal left open from an earlier pass holds the logs and refuses a
    # fresh /config launch, so it is waited out - never killed. Killing it
    # would destroy whatever the operator had running.
    Get-Process terminal64 -ErrorAction SilentlyContinue |
        ForEach-Object { $_.WaitForExit(600000) | Out-Null }

    $runStart = (Get-Date).AddSeconds(-5)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $term -ArgumentList "/config:`"$ini`"" -PassThru
    if (-not $proc.WaitForExit($TimeoutMs)) {
        Write-Output '  TESTER TIMED OUT'
        try { $proc.Kill() } catch { }
    }
    $sw.Stop()
    Start-Sleep -Seconds 3
    Write-Output ("  elapsed: {0:n1} min" -f $sw.Elapsed.TotalMinutes)
    # The agent log is the ONLY place EA Print output lands, and its directory
    # name embeds a port, so the agent tree is discovered rather than assumed.
    $logDirs = @((Join-Path $mt5 'Tester\logs'), (Join-Path $mt5 'logs'))
    Get-ChildItem (Join-Path $mt5 'Tester') -Directory -Filter 'Agent-*' `
                  -ErrorAction SilentlyContinue |
        ForEach-Object { $logDirs += (Join-Path $_.FullName 'logs') }

    # ISOLATE THIS PASS, PER FILE.
    #
    # MT5 appends to one log per day, so a fresh read still returns every
    # earlier pass - including the other side of this very experiment. The
    # cutoff must be applied to EACH file separately: the Tester log and the
    # agent log each span the whole day, so finding one cutoff index in the
    # concatenation of the two keeps the tail of the first file AND the
    # entirety of the second. That produced a diff in which the "baseline"
    # side contained six earlier passes, and it read as a real divergence.
    $cut = $runStart.ToString('HH:mm:ss')
    $lines = @()
    foreach ($ld in ($logDirs | Select-Object -Unique)) {
        if (-not (Test-Path $ld)) { continue }
        Get-ChildItem $ld -Filter '*.log' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $runStart.AddMinutes(-1) } |
            Sort-Object LastWriteTime | ForEach-Object {
                $fl = Read-MtLog $_.FullName
                $idx = -1
                for ($i = 0; $i -lt $fl.Count; $i++) {
                    if ($fl[$i] -match '(\d\d:\d\d:\d\d)\.\d+') {
                        if ($Matches[1] -ge $cut) { $idx = $i; break }
                    }
                }
                if ($idx -ge 0) { $lines += $fl[$idx..($fl.Count - 1)] }
            }
    }

    $dst = Join-Path $outDir "$side.log"
    # UTF-8 so the differ does not have to sniff an encoding a second time.
    Set-Content -LiteralPath $dst -Value $lines -Encoding UTF8
    Write-Output ("  isolated from ${cut}: $($lines.Count) lines -> $dst")
    $deals = @($lines | Where-Object { $_ -match '\bdeal #\d+' })
    $bal   = @($lines | Where-Object { $_ -match 'final balance' }) | Select-Object -Last 1
    Write-Output ("  deal lines: $($deals.Count)")
    $script:passBalance = ''
    if ($bal) {
        $clean = ($bal -replace '^\S+\s+\d+\s+', '').Trim()
        Write-Output ('  ' + $clean)
        if ($clean -match 'final balance ([\d.]+)') { $script:passBalance = $Matches[1] }
    }
    if ($lines.Count -eq 0) {
        Write-Output '  NO LOG CAPTURED - this pass produced no evidence and must not be'
        Write-Output '  reported as a result. Check that the terminal actually launched.'
    }
}
Write-Output ''
Write-Output ("experiment: $Symbol $Period  $From .. $To  model=$Model " +
              "deposit=$Deposit leverage=1:$Leverage")

# Baseline first, so that if the second pass is interrupted the surviving
# artefact is the one that cannot be regenerated from source.
Invoke-Pass 'baseline_100' 'SRP_AB\srp_baseline_100.ex5' $baseSet
$baseBalance = $script:passBalance
Write-Output ''
Write-Output '--- reproduction control ---'
if ($baseBalance -eq '') {
    Write-Output "  NO BALANCE CAPTURED. The baseline pass produced no summary, so"
    Write-Output "  nothing here is a measurement."
} elseif ($baseBalance -eq $controlBalance) {
    Write-Output ("  PASS: baseline reproduced $controlBalance USD, the figure two 1.00")
    Write-Output '        passes reached over this period on 2026-09-03. The staged'
    Write-Output '        binary and the generated input set are faithful.'
} else {
    Write-Output ("  FAIL: baseline ended at $baseBalance USD, expected $controlBalance.")
    Write-Output '        Something differs from the recorded conditions - inputs, tick'
    Write-Output '        data, or the binary. Fix that before reading the diff below,'
    Write-Output '        because a baseline that cannot reproduce itself cannot serve'
    Write-Output '        as a baseline.'
}

Invoke-Pass 'current_110'  'SRP_AB\srp_current_110.ex5'  $currSet

Write-Output ''
Write-Output '--- next step ---'
Write-Output "  python `"c:\scalp robot\_build\abdiff.py`" `"$outDir\baseline_100.log`" `"$outDir\current_110.log`""
Write-Output ''
Write-Output '  A clean diff means fixes 2 and 4 moved no order. It does NOT mean'
Write-Output '  1.10 as shipped trades like 1.00: the shipping defaults enable'
Write-Output '  fixes 1 and 3, which this run switched off on purpose.'
