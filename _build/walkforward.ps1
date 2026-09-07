# Rolling walk-forward over the available XAUUSD real-tick history.
#
# "Available" is now enforced rather than asserted: the default windows sit
# inside the real-tick archive and a window starting before it is refused.
#
# NO OPTIMISATION HAPPENS HERE, and the report says so rather than implying
# otherwise. Every window runs the SHIPPING configuration unchanged, so what
# this measures is stability of the existing edge across time, not the
# performance of a fitted parameter set. Calling that "walk-forward
# optimisation" would overstate it.
#
# Windows are consecutive and non-overlapping, so no trade is counted twice.
param(
    [string]$Symbol = 'XAUUSD',
    [int]$Model = 4,
    # HARNESS v2, FIX 4. What these windows are allowed to be quoted as.
    #
    # DEV by default, and that is now the ACCURATE label rather than a
    # flattering one: the default windows below sit entirely inside the audit
    # 9.1 DEV span, and DEV is the weak claim - in-sample, unlimited looks,
    # never quotable as validation. UNDECLARED remains available and OOS/VAL
    # must be asked for by name, because only the operator knows whether a
    # given span was genuinely held out.
    #
    # It used to default to UNDECLARED on the reasoning that the shipping
    # defaults were themselves chosen with some of this history in view and a
    # script cannot know how much. That is still true of ARBITRARY windows,
    # which is why -Windows leaves the label alone; it is not true of a window
    # set defined by the declared split.
    [ValidateSet('UNDECLARED', 'DEV', 'VAL', 'OOS')]
    [string]$Segment = 'DEV',
    # HARNESS v2, FIX 5. Pins the spread sample every window derives its trade
    # geometry from.
    #
    # 0 keeps the shipping behaviour, in which each window samples SYMBOL_SPREAD
    # at its own initialisation and derives twelve distances from it. That makes
    # the windows incomparable with each other as well as unrepeatable: window 1
    # may trade a 95-point stop and window 4 a 200-point stop for no reason
    # connected to the market, and the table below would read as a change in the
    # edge over time. Setting it makes every window run the same geometry, which
    # is what "the shipping configuration unchanged" was always supposed to mean.
    #
    # Left at 0 by default because changing it changes results, and this script
    # must keep producing what it produced yesterday unless asked otherwise.
    [double]$PinSpread = 0.0,
    # Four consecutive non-overlapping ~69-day windows covering the audit 9.1
    # DEV span EXACTLY: 2025.05.27 -> 2026.03.01, no ragged tail, no overlap.
    #
    # The old defaults were 2023.01.02 -> 2025.08.01 in five windows. The
    # XAUUSD real-tick archive begins 2025-05-27, so FOUR of those five
    # windows contained no real ticks at all and the fifth was ~35% covered.
    # MT5 does not refuse an uncovered window - it silently generates ticks
    # from M1 bars, and audit 6.2 measured generated spread at 4.0-4.4 pts
    # against 9.5-33.5 real. Those defaults therefore understated cost about
    # threefold and FLATTERED every result, while this file's own first line
    # claimed to run "over the available XAUUSD real-tick history".
    #
    # VAL (2026.03.01 -> 2026.09.01) is deliberately NOT here. It is one look
    # per frozen candidate; a rolling script must not spend it by default.
    [string[]]$Windows = @(
        '2025.05.27:2025.08.04',
        '2025.08.04:2025.10.13',
        '2025.10.13:2025.12.22',
        '2025.12.22:2026.03.01'
    ),
    # The first month of the real-tick archive. A window starting before this
    # is refused rather than run, because the run that results is not the
    # measurement it reports itself as.
    [string]$TickArchiveStart = '2025.05.27',
    [switch]$AllowPreTickHistory
)

# --- refuse windows the tick archive cannot cover -----------------------
# Checked before anything is compiled or deployed: the cost of being wrong
# here is a whole run's worth of numbers that read as real and are not.
$archiveStart = [datetime]::ParseExact($TickArchiveStart, 'yyyy.MM.dd',
                                       [System.Globalization.CultureInfo]::InvariantCulture)
$preTick = @()
foreach ($w in $Windows) {
    $p = $w -split ':'
    if ($p.Count -ne 2) { Write-Output "MALFORMED WINDOW: '$w' (want from:to)"; exit 1 }
    $d = [datetime]::ParseExact($p[0], 'yyyy.MM.dd',
                                [System.Globalization.CultureInfo]::InvariantCulture)
    if ($d -lt $archiveStart) { $preTick += $w }
}
if ($preTick.Count -gt 0) {
    if (-not $AllowPreTickHistory -and $Model -ge 4) {
        Write-Output "REFUSED: $($preTick.Count) window(s) start before the real-tick archive ($TickArchiveStart):"
        $preTick | ForEach-Object { Write-Output "  $_" }
        Write-Output '  MT5 would generate ticks from M1 bars for these without saying so, at about'
        Write-Output '  a third of the real spread - the result would read as a real-tick run and flatter itself.'
        Write-Output '  Pass -AllowPreTickHistory to run them anyway; they cannot be quoted as real-tick.'
        exit 1
    }
    Write-Output "WARNING: $($preTick.Count) window(s) predate the tick archive - BAR-GENERATED, cost understated ~3x."
}

# Ordinals per ENUM_SRP_DATA_SEGMENT. Mapped here rather than passed as a
# number so the command line reads as the thing it declares. VAL and OOS are
# the same ordinal: audit 9.1 names the held-out half VAL, the enum calls it
# SRP_SEGMENT_OOS, and having two spellings of one ordinal is better than
# having the script and the audit disagree about what to call it.
$segmentOrdinal = @{ 'UNDECLARED' = 0; 'DEV' = 1; 'VAL' = 2; 'OOS' = 2 }[$Segment]
$segmentIni = "InpRunDataSegment=$segmentOrdinal"
Write-Output "declared data segment: $Segment ($segmentIni)"

# HARNESS v2, FIX 5. The pin is passed only when it is set, so a default run
# writes exactly the override list it wrote before this parameter existed.
# InvariantCulture, not the current culture: a machine with a comma decimal
# separator would otherwise write InpPinSpreadSample=13,00 and the terminal
# would read 13 - or the comma would split the override list.
$windowIni = $segmentIni
if ($PinSpread -gt 0.0) {
    $pinText = $PinSpread.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $windowIni = "$segmentIni;InpPinSpreadSample=$pinText"
    Write-Output "spread sample PINNED at $pinText pts on every window - the windows share one geometry"
} else {
    Write-Output 'spread sample NOT pinned: each window derives its own geometry from its own first tick,'
    Write-Output '  so the windows below are not strictly comparable with each other. Pass -PinSpread to fix that.'
}

$results = @()
foreach ($w in $Windows) {
    $parts = $w -split ':'
    $from = $parts[0]; $to = $parts[1]
    Write-Output "=== window $from .. $to ==="

    $out = & powershell -NoProfile -ExecutionPolicy Bypass `
           -File 'c:\scalp robot\_build\backtest.ps1' `
           -Symbol $Symbol -Model $Model -From $from -To $to `
           -Ini $windowIni -TimeoutMs 1800000 2>&1

    $trades = ($out | Select-String -Pattern 'trades=(\d+) wins=(\d+) losses=(\d+).*winRate=([\d\.]+)' |
               Select-Object -Last 1)
    $pf     = ($out | Select-String -Pattern 'profitFactor=([\d\.]+)' | Select-Object -Last 1)
    $dd     = ($out | Select-String -Pattern 'maxDD=[\d\.]+ \(([\d\.]+)%\)' | Select-Object -Last 1)
    $exp    = ($out | Select-String -Pattern 'expectancy=(-?[\d\.]+)' | Select-Object -Last 1)
    $bal    = ($out | Select-String -Pattern 'final balance ([\d\.]+)' | Select-Object -Last 1)
    # HARNESS v2, FIX 4. The two verdicts from the EA's own provenance block,
    # lifted into this table. A summary row of pf and win rate with no tick
    # model beside it is the exact artefact the audit found being quoted: the
    # numbers are real, what produced them was not stated anywhere near them.
    $tick   = ($out | Select-String -Pattern 'TICK MODEL : (.+)$'  | Select-Object -Last 1)
    $quot   = ($out | Select-String -Pattern 'QUOTABLE   : (\w+)'  | Select-Object -Last 1)
    # HARNESS v2, FIX 5. The geometry root, lifted the same way. Two columns
    # rather than one: the sample says whether the windows traded the same
    # distances, and pinned says whether that was guaranteed or coincidence.
    $geom   = ($out | Select-String -Pattern 'GEOMETRY   : spread sample ([\d\.]+) pts, (PINNED|read)' |
               Select-Object -Last 1)
    # Resolved before the row literal rather than inside it: a multi-line
    # if/elseif as a hashtable value parses differently from one at statement
    # level, and a table column is not worth that risk.
    $geomSample = 'NOT REPORTED'
    $geomPinned = 'NOT REPORTED'
    if ($geom) {
        $geomSample = $geom.Matches[0].Groups[1].Value
        if ($geom.Matches[0].Groups[2].Value -eq 'PINNED') {
            $geomPinned = 'yes'
        } else {
            $geomPinned = 'no'
        }
    }

    $row = [ordered]@{
        window   = "$from..$to"
        trades   = if ($trades) { $trades.Matches[0].Groups[1].Value } else { 'n/a' }
        winRate  = if ($trades) { $trades.Matches[0].Groups[4].Value } else { 'n/a' }
        pf       = if ($pf)     { $pf.Matches[0].Groups[1].Value }     else { 'n/a' }
        expectancy = if ($exp)  { $exp.Matches[0].Groups[1].Value }    else { 'n/a' }
        maxDDpct = if ($dd)     { $dd.Matches[0].Groups[1].Value }     else { 'n/a' }
        balance  = if ($bal)    { $bal.Matches[0].Groups[1].Value }    else { 'n/a' }
        tape     = if ($tick)   { $tick.Matches[0].Groups[1].Value.Trim() } else { 'NOT REPORTED' }
        spreadPts = $geomSample
        pinned   = $geomPinned
        quotable = if ($quot)   { $quot.Matches[0].Groups[1].Value }    else { 'NOT REPORTED' }
    }
    $results += [pscustomobject]$row
    $results | Format-Table -AutoSize | Out-String | Write-Output
}

Write-Output '=== WALK-FORWARD SUMMARY (shipping config, no per-window fitting) ==='
Write-Output "declared data segment: $Segment"
$results | Format-Table -AutoSize
# A row whose provenance never reached this table is reported as such rather
# than left to be read as passing.
$silent = @($results | Where-Object { $_.quotable -eq 'NOT REPORTED' })
if ($silent.Count -gt 0) {
    Write-Output ("WARNING: $($silent.Count) of $($results.Count) windows " +
                  'produced no provenance block. Those rows state no tick ' +
                  'model and may not be quoted.')
}

# HARNESS v2, FIX 5. The same treatment for the geometry. A table of windows
# that each derived their own trade distances is not a picture of one strategy
# over time, and that is said here rather than left to be inferred from a
# column the reader may not know how to weigh.
$unpinned = @($results | Where-Object { $_.pinned -eq 'no' })
if ($unpinned.Count -gt 0) {
    Write-Output ("WARNING: $($unpinned.Count) of $($results.Count) windows ran " +
                  'an unpinned spread sample. Each of those rows derived its own ' +
                  'trade geometry from its own first tick, so differences between ' +
                  'them are not necessarily differences in the edge. Rerun with ' +
                  '-PinSpread <points> to give every window one geometry.')
}
# Distinct sample values across pinned rows would mean the pin did not reach
# some window - a plumbing failure that would otherwise read as a clean run.
$pinnedRows = @($results | Where-Object { $_.pinned -eq 'yes' })
if ($pinnedRows.Count -gt 1) {
    $distinct = @($pinnedRows | Select-Object -ExpandProperty spreadPts -Unique)
    if ($distinct.Count -gt 1) {
        Write-Output ("WARNING: pinned windows report $($distinct.Count) different " +
                      "spread samples ($($distinct -join ', ')). The pin did not " +
                      'reach every window; these rows are not comparable.')
    }
}
