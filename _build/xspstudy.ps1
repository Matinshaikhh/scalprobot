# Deploys, compiles and runs the XauStructurePro PHASE A STUDY, then hands the
# resulting per-instance CSV to xspstudy.py.
#
# WHAT MAKES THIS DIFFERENT FROM backtest.ps1
#
# backtest.ps1 runs a product to see whether it survives a tick stream. This
# runs a MEASUREMENT INSTRUMENT, and the instrument's output is a file that will
# be quoted. So three things are enforced here that a product run does not need:
#
#   1. THE SEGMENT AND THE DATES ARE ONE SWITCH. -Segment sets the window AND
#      the EA's own declaration together. In the old harness they were
#      independent, and the audit's malformed OOS window is what that produces:
#      a run whose dates and whose self-description need not agree, with nothing
#      anywhere to reveal the disagreement.
#
#   2. REAL TICKS OR NOTHING QUOTABLE. Audit 6.2 measured OHLC-generated spread
#      at 4.0-4.4pt against 9.5-33.5pt on real ticks. A generated pass does not
#      merely lose precision, it FLATTERS the strategy about threefold on the
#      one quantity the study is testing against. So Model<4 is allowed but
#      forces the declaration to UNDECLARED.
#
#   3. THE CSV IS COPIED OUT BEFORE ANYTHING ELSE CAN TOUCH IT. CXspCsv opens
#      with FILE_WRITE, i.e. it TRUNCATES: the next study run destroys this
#      one's evidence. Each pass therefore lands in its own stamped directory
#      alongside the .set that produced it and the isolated log.
param(
    # DEV and VAL are the audit's section 9.1 slices and carry their own dates.
    # SMOKE is for exercising the pipeline over arbitrary dates and declares
    # itself UNDECLARED, so its output cannot be quoted by accident.
    [ValidateSet('DEV', 'VAL', 'SMOKE')]
    [string]$Segment = 'DEV',
    [string]$Symbol  = 'XAUUSD',
    [string]$Period  = 'M15',
    # Only meaningful with -Segment SMOKE. Supplying them for DEV or VAL is
    # refused rather than honoured - see the guard below.
    [string]$From    = '',
    [string]$To      = '',
    [int]$Model      = 4,
    [double]$CommissionPts = 7.0,
    # A nine-month real-tick pass over XAUUSD is hours, not minutes.
    [int]$TimeoutMs  = 10800000,
    # VAL is ONE LOOK per frozen candidate. The switch exists so that spending
    # it is a deliberate act and appears in the shell history.
    [switch]$ConfirmOneLookAtVal,
    [switch]$AllowGeneratedTicks,
    [switch]$SkipSelfTest,
    [switch]$SkipAnalysis,
    # Compile and run XSPCheck only. Verification step 3 before step 4.
    [switch]$SelfTestOnly
)

$ErrorActionPreference = 'Continue'
$mt5    = 'C:\Program Files\MetaTrader 5'
$src    = 'c:\scalp robot\MQL5'
$build  = 'c:\scalp robot\_build'
$term   = Join-Path $mt5 'terminal64.exe'
$ed     = Join-Path $mt5 'MetaEditor64.exe'
$mqlRt  = Join-Path $mt5 'MQL5'
# InpUseCommonFolder defaults true, and that is not a preference. This install
# has ten tester agents, each with its OWN MQL5\Files; a non-common write lands
# in whichever agent took the pass and the runner would have to guess which.
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$csvName = 'xsp_instances.csv'
$csvLive = Join-Path $common ('XauStructurePro\' + $csvName)

# --- segment resolution: window and declaration together -------------------
# Ordinals are ENUM_SRP_DATA_SEGMENT: 0 UNDECLARED, 1 DEV, 2 OOS. The plan's
# VAL is the audit's OOS under a newer name; one enum, so both products mean
# the same thing by it.
$segDates = @{
    'DEV'   = @{ From = '2025.05.27'; To = '2026.02.28'; Ord = 1 }
    'VAL'   = @{ From = '2026.03.01'; To = '2026.09.01'; Ord = 2 }
    'SMOKE' = @{ From = '2026.01.05'; To = '2026.01.19'; Ord = 0 }
}
$seg = $segDates[$Segment]

if ($Segment -ne 'SMOKE' -and ($From -ne '' -or $To -ne '')) {
    Write-Output "REFUSED: -From/-To with -Segment $Segment."
    Write-Output "  $Segment means a FIXED window ($($seg.From) .. $($seg.To)). A run that"
    Write-Output "  declares one segment and covers different dates is unquotable, and"
    Write-Output "  nothing downstream could detect it. Use -Segment SMOKE for free dates."
    exit 1
}
if ($From -ne '') { $seg.From = $From }
if ($To   -ne '') { $seg.To   = $To }

if ($Segment -eq 'VAL' -and -not $ConfirmOneLookAtVal) {
    Write-Output 'REFUSED: VAL is ONE LOOK per frozen candidate.'
    Write-Output '  Re-run with -ConfirmOneLookAtVal once the hypothesis rows are already'
    Write-Output '  in CHANGELOG.md and Phase B has produced a survivor on DEV. Spending'
    Write-Output '  the look before then does not buy a second one.'
    exit 1
}

$declaredOrd = $seg.Ord
if ($Model -lt 4) {
    if (-not $AllowGeneratedTicks) {
        Write-Output "REFUSED: -Model $Model generates ticks from bars."
        Write-Output '  Audit 6.2: generated spread 4.0-4.4pt vs 9.5-33.5pt on real ticks,'
        Write-Output '  so a generated pass understates the cost this study measures against'
        Write-Output '  by about threefold - it flatters every result in the file.'
        Write-Output '  Add -AllowGeneratedTicks to run anyway; the output will declare'
        Write-Output '  itself UNDECLARED and the analysis will refuse to quote it.'
        exit 1
    }
    Write-Output "WARNING generated ticks (-Model $Model): declaration forced to UNDECLARED"
    $declaredOrd = 0
}

# --- does the real-tick archive actually cover the window? -----------------
#
# The plan asked for this to be confirmed by hand once. It is done on EVERY run
# instead, because the failure is silent: MT5 falls back to bar generation for
# any month it has no .tkc for, keeps running, and reports nothing. A window
# half-covered by real ticks produces one file whose first half is honest and
# whose second half understates spread threefold - and the provenance line
# infers ONE tick model for the whole pass, so it cannot show the seam.
function Test-TickCoverage([string]$sym, [string]$from, [string]$to) {
    $dirs = @(Get-ChildItem (Join-Path $mt5 'bases') -Directory -ErrorAction SilentlyContinue |
              ForEach-Object { Join-Path $_.FullName "ticks\$sym" } |
              Where-Object { Test-Path $_ })
    if ($dirs.Count -eq 0) {
        Write-Output "  TICKS: no archive directory for $sym under bases\*\ticks"
        return $false
    }
    $have = @{}
    foreach ($d in $dirs) {
        Get-ChildItem $d -Filter '*.tkc' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.BaseName -match '^\d{6}$') { $have[$_.BaseName] = $_.Length }
        }
    }
    if ($have.Count -eq 0) { Write-Output "  TICKS: archive for $sym holds no .tkc months"; return $false }
    $f = [datetime]::ParseExact($from, 'yyyy.MM.dd', $null)
    $t = [datetime]::ParseExact($to,   'yyyy.MM.dd', $null)
    $want = @()
    $cur = Get-Date -Year $f.Year -Month $f.Month -Day 1
    while ($cur -le $t) { $want += $cur.ToString('yyyyMM'); $cur = $cur.AddMonths(1) }
    $missing = @($want | Where-Object { -not $have.ContainsKey($_) })
    $months  = ($have.Keys | Sort-Object)
    Write-Output ("  TICKS: $sym archive $($months[0])..$($months[-1]) ($($have.Count) months)")
    if ($missing.Count -gt 0) {
        Write-Output ("  TICKS: MISSING for this window: " + ($missing -join ' '))
        return $false
    }
    # A month present but tiny is a PARTIAL month, which is the archive's first
    # or last month. Reported because the window's own edge may sit inside it.
    foreach ($m in @($want[0], $want[-1])) {
        if ($have.ContainsKey($m) -and $have[$m] -lt 3000000) {
            Write-Output ("  TICKS: $m is only " + [int]($have[$m] / 1024) +
                          ' KB - a PARTIAL month; the window edge may predate the ticks')
        }
    }
    Write-Output '  TICKS: every month in the window is present'
    return $true
}

Write-Output "=== XSP PHASE A STUDY ==="
Write-Output ("  segment  : $Segment (declared ordinal $declaredOrd) $($seg.From) .. $($seg.To)")
Write-Output ("  symbol   : $Symbol $Period   model=$Model   commission=$CommissionPts pts")
$covered = Test-TickCoverage $Symbol $seg.From $seg.To
if ($Model -ge 4 -and -not $covered -and -not $AllowGeneratedTicks) {
    Write-Output 'REFUSED: -Model 4 was asked for but the archive does not cover the window.'
    Write-Output '  MT5 would silently generate the uncovered months from bars. Download the'
    Write-Output '  missing months, or pass -AllowGeneratedTicks to accept an UNDECLARED run.'
    exit 1
}

# --- deploy both trees -----------------------------------------------------
#
# ScalpRobotPro is COPIED, never touched at source: XSPSetupStudy includes
# CRunProvenance from it, and that file is the section 9.5 comparison baseline.
# Copying the frozen tree into the runtime is what backtest.ps1 already does;
# it is a deployment, not a modification.
foreach ($tree in 'XauStructurePro', 'ScalpRobotPro') {
    $dst = Join-Path $mqlRt "Include\$tree"
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item (Join-Path $src "Include\$tree") -Destination (Join-Path $mqlRt 'Include') `
              -Recurse -Force
}
$dstEx = Join-Path $mqlRt 'Experts\XauStructurePro'
if (Test-Path $dstEx) { Remove-Item $dstEx -Recurse -Force }
Copy-Item (Join-Path $src 'Experts\XauStructurePro') -Destination (Join-Path $mqlRt 'Experts') `
          -Recurse -Force
Write-Output '  deployed : Include\XauStructurePro, Include\ScalpRobotPro, Experts\XauStructurePro'

# --- compile ---------------------------------------------------------------
# WARNINGS ARE REPORTED, not swallowed. The build contract for both trees is
# 0 errors and 0 warnings, and a warning count is the only cheap signal that an
# implicit conversion is quietly changing a measured number.
function Build-Ea([string]$name) {
    $mq5 = Join-Path $mqlRt "Experts\XauStructurePro\$name.mq5"
    $log = [System.IO.Path]::ChangeExtension($mq5, '.buildlog')
    $ex5 = [System.IO.Path]::ChangeExtension($mq5, '.ex5')
    if (Test-Path $ex5) { Remove-Item $ex5 -Force }
    cmd /c "`"$ed`" /compile:`"$mq5`" /inc:`"$mqlRt`" /log:`"$log`"" 2>&1 | Out-Null
    $txt = if (Test-Path $log) { Get-Content -LiteralPath $log -Encoding Unicode } else { @() }
    if ($txt.Count -eq 0 -and (Test-Path $log)) { $txt = Get-Content -LiteralPath $log }
    $errs = @($txt | Where-Object { $_ -match ': error' })
    $warn = @($txt | Where-Object { $_ -match ': warning' })
    Write-Output ("  compile  : $name errors=$($errs.Count) warnings=$($warn.Count)")
    ($errs + $warn) | Select-Object -First 20 | ForEach-Object { '      ' + $_.Trim() }
    if (-not (Test-Path $ex5)) { Write-Output "  COMPILE FAILED: $name"; return $false }
    return $true
}
if (-not (Build-Ea 'XSPCheck'))      { exit 1 }
if (-not (Build-Ea 'XSPSetupStudy')) { exit 1 }

# --- shared tester plumbing ------------------------------------------------
# Log isolation is backtest.ps1's, including the reason it is applied PER FILE:
# MT5 appends one log per day per directory, and applying one cutoff to the
# concatenation of the Tester log and the agent log keeps the whole of the
# second file - which made two configurations read as one result.
function Read-MtLog([string]$path) {
    $tmp = Join-Path $env:TEMP ('xsp_' + [System.Guid]::NewGuid().ToString('N') + '.log')
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

function Invoke-Tester([string]$expert, [string]$setName, [string]$from, [string]$to,
                       [int]$model, [int]$timeout) {
    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $iniPath = Join-Path $env:TEMP "xsp_$stamp.ini"
    # ForwardMode=0 is explicit. A forward split left on from an earlier session
    # would silently hand half the window to a forward segment; the run would
    # still finish, and only the provenance line's forward=yes would show it.
    $body = @"
[Tester]
Expert=$expert
Symbol=$Symbol
Period=$Period
Model=$model
FromDate=$from
ToDate=$to
Optimization=0
ForwardMode=0
ShutdownTerminal=1
Deposit=10000
Currency=USD
Leverage=100
ExecutionMode=0
Visual=0
"@
    if ($setName -ne '') { $body += "`r`nExpertParameters=$setName`r`n" }
    Set-Content -LiteralPath $iniPath -Value $body -Encoding ASCII

    $logDirs = @((Join-Path $mt5 'Tester\logs'), (Join-Path $mt5 'logs'))
    Get-ChildItem (Join-Path $mt5 'Tester') -Directory -Filter 'Agent-*' -ErrorAction SilentlyContinue |
        ForEach-Object { $logDirs += (Join-Path $_.FullName 'logs') }

    Get-Process terminal64 -ErrorAction SilentlyContinue |
        ForEach-Object { $_.WaitForExit(600000) | Out-Null }

    # Cutoff recorded, logs NOT deleted: the agent log is the only place EA
    # Print output lands, and deleting it leaves the next pass with none.
    $runStart = (Get-Date).AddSeconds(-5)
    $proc = Start-Process -FilePath $term -ArgumentList "/config:`"$iniPath`"" -PassThru
    if (-not $proc.WaitForExit($timeout)) {
        Write-Output '  TESTER TIMED OUT'
        try { $proc.Kill() } catch { }
    }
    Start-Sleep -Seconds 3

    Get-ChildItem (Join-Path $mt5 'Tester') -Directory -Filter 'Agent-*' -ErrorAction SilentlyContinue |
        ForEach-Object { $logDirs += (Join-Path $_.FullName 'logs') }
    $cut = $runStart.ToString('HH:mm:ss')
    $lines = @()
    foreach ($ld in ($logDirs | Select-Object -Unique)) {
        if (-not (Test-Path $ld)) { continue }
        Get-ChildItem $ld -Filter '*.log' |
            Where-Object { $_.LastWriteTime -ge $runStart.AddMinutes(-1) } |
            Sort-Object LastWriteTime | ForEach-Object {
                $fl  = Read-MtLog $_.FullName
                $idx = -1
                for ($i = 0; $i -lt $fl.Count; $i++) {
                    if ($fl[$i] -match '(\d\d:\d\d:\d\d)\.\d+') {
                        if ($Matches[1] -ge $cut) { $idx = $i; break }
                    }
                }
                if ($idx -ge 0) { $lines += $fl[$idx..($fl.Count - 1)] }
            }
    }
    return ,@($lines | ForEach-Object { $_ -replace '^\S+\s+\d+\s+', '' })
}

# --- verification step 3: the self-test, BEFORE the study ------------------
#
# The study's whole output is one CSV. If the barrier tracker mismeasures an
# excursion or the row builder is off by one column, every number the analysis
# prints afterwards is wrong in a way no amount of re-cutting can reveal. So a
# failing self-test stops the run rather than annotating it.
$checkVerdict = 'SKIPPED'
if (-not $SkipSelfTest) {
    Write-Output ''
    Write-Output '--- XSPCheck (self-test) ---'
    # Short window, generated ticks: the suite asserts on synthetic tick
    # sequences it builds itself, plus a handful of live-history reads that only
    # need a warmed-up probe. It is not measuring cost, so it does not need the
    # tick archive - and running it on real ticks would cost hours for nothing.
    $cl = Invoke-Tester 'XauStructurePro\XSPCheck.ex5' '' '2026.01.05' '2026.01.09' 1 900000
    $cl | Where-Object { $_ -match 'XSP_CHECK|FAIL|OnInit|error|critical|array out of range|zero divide' } |
        Select-Object -First 60 | ForEach-Object { '  ' + $_.Trim() }
    $v = @($cl | Where-Object { $_ -match 'XSP_CHECK CHECKS=' })
    if ($v.Count -eq 0) {
        Write-Output '  NO VERDICT LINE FOUND - the suite did not reach its summary.'
        Write-Output '  Treated as a failure: a study run after an unreported self-test is'
        Write-Output '  a study whose instrument was never checked.'
        exit 1
    }
    Write-Output ('  ' + $v[-1].Trim())
    $checkVerdict = if ($v[-1] -match 'VERDICT=PASS') { 'PASS' } else { 'FAIL' }
    if ($checkVerdict -ne 'PASS') {
        Write-Output '  SELF-TEST FAILED - the study is not run. Fix the instrument first.'
        exit 1
    }
}
if ($SelfTestOnly) { Write-Output ''; Write-Output "SELF-TEST $checkVerdict (study not run: -SelfTestOnly)"; exit 0 }

# --- the study pass --------------------------------------------------------
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir  = Join-Path $build ("_xsp\{0}_{1}" -f $Segment.ToLower(), $stamp)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# A COMPLETE input set, generated from the EA's own declarations. A partial
# .set is not "defaults plus changes": every omitted input arrives as 0, which
# here would zero InpCommissionPts and blank InpStudyFile.
$setName = "xsp_study_$stamp.set"
$setPath = Join-Path $mqlRt "Profiles\Tester\$setName"
$ovr = @(
    "InpDataSegment=$declaredOrd"
    "InpStudyFile=$csvName"
    'InpUseCommonFolder=true'
    "InpCommissionPts=$CommissionPts"
    'InpPrintCensus=true'
)
$mkOut = & (Join-Path $build 'makeset.ps1') `
         -Expert (Join-Path $mqlRt 'Experts\XauStructurePro\XSPSetupStudy.mq5') `
         -OutPath $setPath -Override $ovr
$mkOut | Where-Object { $_ -match 'WARNING|wrote' } | ForEach-Object { '  ' + $_ }
if (-not (Test-Path $setPath)) { Write-Output 'SET FILE NOT WRITTEN'; exit 1 }
Write-Output ('  inputs   : ' + ($ovr -join '; '))

# DELETE THE STALE CSV FIRST.
#
# CXspCsv opens with FILE_WRITE, so a completed run truncates it anyway. The
# case this covers is the run that DIES in OnInit: the previous pass's file
# would survive untouched and the analysis would read it as this pass's output -
# a stale measurement presented as a fresh one. An absent file is a loud
# failure; a stale one is a silent wrong answer.
if (Test-Path $csvLive) { Remove-Item $csvLive -Force -ErrorAction SilentlyContinue }

Write-Output ''
Write-Output "--- study pass: $Symbol $Period $($seg.From) .. $($seg.To) model=$Model ---"
$clean = Invoke-Tester 'XauStructurePro\XSPSetupStudy.ex5' $setName $seg.From $seg.To $Model $TimeoutMs
Write-Output "  log lines isolated: $($clean.Count)"

Write-Output ''
Write-Output '--- XSP output ---'
# XSP_ tokens plus the fault vocabulary. Progress lines are included on purpose:
# without them a stalled pass and a pass that found nothing look identical.
$clean | Where-Object {
    $_ -match 'XSP_STUDY|XSP_CHECK|XSP_TRACK|XSP_REC|XSP BUILD|provenance|' +
              'RECONCILED|recorder |pools |events |swings |regime |' +
              'OnInit|failed|error|critical|abnormal|not deleted|leak'
} | Select-Object -First 120 | ForEach-Object { '  ' + $_.Trim() }

$fatal = @($clean | Where-Object {
    $_ -match 'invalid pointer|leaked|not deleted|zero divide|array out of range|critical error'
})
if ($fatal.Count -gt 0) {
    Write-Output ''
    Write-Output 'RUNTIME FAULTS DETECTED:'
    $fatal | ForEach-Object { '  ' + $_.Trim() }
}

# --- preserve the evidence bundle ------------------------------------------
$clean | Set-Content -LiteralPath (Join-Path $outDir 'run.log') -Encoding UTF8
Copy-Item $setPath (Join-Path $outDir $setName) -Force -ErrorAction SilentlyContinue
$csvOut = Join-Path $outDir $csvName
if (Test-Path $csvLive) {
    Copy-Item $csvLive $csvOut -Force
    $rows = @(Get-Content -LiteralPath $csvOut | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
    # -1 for the schema header line, which is not an instance.
    $dataRows = [Math]::Max(0, $rows.Count - 1)
    Write-Output ''
    Write-Output "  csv      : $csvOut"
    Write-Output "  data rows: $dataRows"
    # THE ROW-COUNT RECONCILIATION the plan's verification step 4 asks for, done
    # here rather than left to the reader: the EA counts what it wrote and the
    # shell counts what arrived, and the two are compared. A mismatch means rows
    # were lost between WriteRow and the filesystem - a flush or a full disk -
    # which no other check in the chain would notice.
    $censusRows = 0
    $m = [regex]::Match(($clean -join "`n"), 'xsp_census:[^\n]*?\brows=(\d+)')
    if ($m.Success) { $censusRows = [int]$m.Groups[1].Value }
    if ($censusRows -ne $dataRows) {
        Write-Output "  ROW COUNT MISMATCH: census says rows=$censusRows, file holds $dataRows"
    } else {
        Write-Output "  row counts agree (census rows=$censusRows)"
    }
} else {
    Write-Output ''
    Write-Output "  CSV NOT PRODUCED at $csvLive"
    Write-Output '  The pass did not reach OnInit, or wrote elsewhere. Nothing to analyse.'
    exit 1
}

# --- analysis ---------------------------------------------------------------
# Run against the COPY in the stamped directory, never the live file: pointing
# the analysis at the Common folder would make the numbers depend on whichever
# pass happened to run last.
if (-not $SkipAnalysis) {
    Write-Output ''
    Write-Output '--- analysis ---'
    $py = Join-Path $build 'xspstudy.py'
    if (-not (Test-Path $py)) {
        Write-Output "  $py not found - CSV is preserved, analyse it separately"
    } else {
        & python $py --csv $csvOut --commission $CommissionPts
        if ($LASTEXITCODE -ne 0) { Write-Output "  analysis exited $LASTEXITCODE" }
    }
}

Write-Output ''
Write-Output "SELF-TEST $checkVerdict | SEGMENT $Segment | MODEL $Model | BUNDLE $outDir"
if ($fatal.Count -gt 0) { exit 1 }
exit 0
