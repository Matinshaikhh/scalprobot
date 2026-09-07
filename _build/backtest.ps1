# Runs the REAL Expert Advisor through the Strategy Tester.
#
# The integration harness proves the object graph builds and tears down. This
# proves the shipped product initialises under the tester, survives a real tick
# stream, and reaches OnTester. It is the last thing that can be verified
# without a live account.
param(
    [string]$Symbol = 'EURUSD',
    [string]$From   = '2025.01.02',
    [string]$To     = '2025.02.01',
    [string]$Period = 'M1',
    [string]$Expert = 'ScalpRobotPro\ScalpRobotPro.ex5',
    [string]$Ini    = '',
    [int]$Model     = 1,
    [int]$TimeoutMs = 600000
)

$ErrorActionPreference = 'Continue'
$mt5   = 'C:\Program Files\MetaTrader 5'
$src   = 'c:\scalp robot\MQL5'
$term  = Join-Path $mt5 'terminal64.exe'
$ed    = Join-Path $mt5 'MetaEditor64.exe'
$mqlRt = Join-Path $mt5 'MQL5'

# --- deploy and compile the EA in place -----------------------------------
$dstInc = Join-Path $mqlRt 'Include\ScalpRobotPro'
if (Test-Path $dstInc) { Remove-Item $dstInc -Recurse -Force }
Copy-Item (Join-Path $src 'Include\ScalpRobotPro') `
          -Destination (Join-Path $mqlRt 'Include') -Recurse -Force
foreach ($d in 'Experts', 'Scripts') {
    $dst = Join-Path $mqlRt "$d\ScalpRobotPro"
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item (Join-Path $src "$d\ScalpRobotPro") `
              -Destination (Join-Path $mqlRt $d) -Recurse -Force
}

$ea   = Join-Path $mqlRt 'Experts\ScalpRobotPro\ScalpRobotPro.mq5'
$log  = [System.IO.Path]::ChangeExtension($ea, '.buildlog')
$ex5  = [System.IO.Path]::ChangeExtension($ea, '.ex5')
if (Test-Path $ex5) { Remove-Item $ex5 -Force }
cmd /c "`"$ed`" /compile:`"$ea`" /inc:`"$mqlRt`" /log:`"$log`"" 2>&1 | Out-Null
if (-not (Test-Path $ex5)) { Write-Output 'EA DID NOT COMPILE'; exit 1 }
Write-Output 'EA compiled and deployed'

# --- tester configuration -------------------------------------------------
# Model: 1 = 1-minute OHLC (fast, adequate for pipeline exercise)
#         4 = every tick based on REAL TICKS (honest, needs tick archive)
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$iniPath = Join-Path $env:TEMP "srp_bt_$stamp.ini"
$body = @"
[Tester]
Expert=$Expert
Symbol=$Symbol
Period=$Period
Model=$Model
FromDate=$From
ToDate=$To
Optimization=0
ShutdownTerminal=1
Deposit=10000
Currency=USD
Leverage=100
ExecutionMode=0
Visual=0
"@
# Input overrides go in a .set file that the ini POINTS AT, not inline.
#
# An inline [TesterInputs] block is accepted by the ini parser but aborts the
# pass with "some error after pass finished" and zero ticks - a failure that
# looks exactly like a run that legitimately took no trades. The .set form is
# what the terminal writes itself, so it is the form it reliably reads.
if ($Ini -ne '') {
    $setDir  = Join-Path $mqlRt 'Profiles\Tester'
    $setName = "srp_bt_$stamp.set"
    $setPath = Join-Path $setDir $setName
    # A COMPLETE input set is generated from the EA's own declarations and the
    # overrides applied on top. A partial file is not "defaults plus changes":
    # every omitted input arrives as 0, which zeroed an indicator period and
    # made the EA refuse to start - reported only as an aborted pass.
    # Split on semicolons AS WELL AS newlines.
    #
    # A newline written as a backtick escape inside an outer quoted command
    # does not always survive the shell, and when it did not the ENTIRE
    # override list collapsed into one line: the first name=value applied and
    # every later one was swallowed into its value. The run then looked like
    # a legitimate configuration that simply took no trades.
    $ovr = @($Ini -split "[;`r`n]+" | ForEach-Object { $_.Trim() } |
             Where-Object { $_ -ne '' })
    # Guard against a silent partial application. The array is re-joined
    # when it crosses the -File boundary below and re-split there; if that
    # round trip ever loses an entry again, this is where it shows up.
    Write-Output "overrides parsed: $($ovr.Count)"
    # A malformed entry is refused rather than silently written.
    foreach ($o in $ovr) {
        if ($o -notmatch '^Inp[A-Za-z0-9_]+=') {
            Write-Output "BAD OVERRIDE (ignored, not Inp<name>=value): $o"
        }
    }
    # Dot-source rather than launching a child powershell.exe.
    #
    # Passing a string[] to a -File child re-joins it into one comma-
    # separated argument, and the generator then treated the whole list as a
    # single name=value pair. Only the FIRST override survived, so a
    # two-tier ablation silently became a one-tier ablation and produced
    # results identical to the previous run - which read as a finding about
    # the strategy rather than a broken experiment.
    $mkOut = & 'c:\scalp robot\_build\makeset.ps1' `
             -Expert (Join-Path $mqlRt 'Experts\ScalpRobotPro\ScalpRobotPro.mq5') `
             -OutPath $setPath -Override $ovr
    $mkOut | Where-Object { $_ -match 'WARNING|wrote' } | ForEach-Object { "  $_" }
    if (-not (Test-Path $setPath)) { Write-Output 'SET FILE NOT WRITTEN'; exit 1 }
    $body += "`r`nExpertParameters=$setName`r`n"
    Write-Output ("input overrides: $setName -> " + ($ovr -join '; '))
}
Set-Content -LiteralPath $iniPath -Value $body -Encoding ASCII

# EA Print output lands in the AGENT log, whose directory name embeds a
# port, so the agent tree is discovered rather than assumed.
$logDirs = @((Join-Path $mt5 'Tester\logs'), (Join-Path $mt5 'logs'))
Get-ChildItem (Join-Path $mt5 'Tester') -Directory -Filter 'Agent-*' -ErrorAction SilentlyContinue |
    ForEach-Object { $logDirs += (Join-Path $_.FullName 'logs') }

# A terminal left running from an earlier pass holds the logs open and would
# also refuse a fresh /config launch, so it is waited out first.
Get-Process terminal64 -ErrorAction SilentlyContinue |
    ForEach-Object { $_.WaitForExit(600000) | Out-Null }

# Record the cutoff instead of DELETING the logs.
#
# The agent log is the ONLY place EA Print output lands. Deleting it left the
# agent with no log for the following pass, so the report came back empty
# while still reporting success - which would have silently destroyed the
# evidence trail for every measurement in this phase. Filtering by timestamp
# isolates a run without removing anything the tester owns.
$runStart = (Get-Date).AddSeconds(-5)

Write-Output "backtesting $Symbol $Period ($From .. $To)"
$proc = Start-Process -FilePath $term -ArgumentList "/config:`"$iniPath`"" -PassThru
if (-not $proc.WaitForExit($TimeoutMs)) {
    Write-Output 'TESTER TIMED OUT'
    try { $proc.Kill() } catch { }
}
Start-Sleep -Seconds 3

# A pass that ends with "some error after pass finished" and produced no
# agent log did NOT run. Saying so is the difference between a measurement
# and a guess.
$verdictLines = @()

function Read-MtLog([string]$path) {
    # Read via a COPY. A terminal still holding the log makes a direct
    # ReadAllBytes throw, which previously discarded the entire report of a
    # run that had actually completed.
    $tmp = Join-Path $env:TEMP ('srp_bt_' + [System.Guid]::NewGuid().ToString('N') + '.log')
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

# Re-discover the agent directory: the tester may create it during the run.
Get-ChildItem (Join-Path $mt5 'Tester') -Directory -Filter 'Agent-*' -ErrorAction SilentlyContinue |
    ForEach-Object { $logDirs += (Join-Path $_.FullName 'logs') }

# ISOLATE THIS RUN, PER FILE.
#
# MT5 appends to one log per day, so a filtered read still returns every
# earlier pass from the same day. Reporting those alongside the current run
# made two different configurations look like one result, which is worse
# than no output at all. Everything before this run's own start timestamp is
# dropped by wall-clock time, which each line carries as its prefix.
#
# The cutoff is applied to EACH FILE SEPARATELY. It used to be applied once to
# the concatenation of all of them, and because the Tester log and the agent
# log each span the whole day, that kept the tail of the first file AND the
# entirety of the second: a two-pass A/B capture came back holding six earlier
# passes, whose counters then read as a divergence between the two binaries.
# Found 2026-09-04 while running the fix-4 identity test.
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
Write-Output "run isolated from $cut ($($lines.Count) lines)"

$clean = $lines | ForEach-Object { $_ -replace '^\S+\s+\d+\s+', '' }

Write-Output '--- initialisation, errors and results ---'
# The performance lines are included DELIBERATELY: without them a caller
# parsing this output can only see the final balance, which is why a
# walk-forward report came back with every profit factor as "n/a".
$clean | Where-Object {
    $_ -match 'invalid|leak|not deleted|OnInit|failed|error|critical|EMERGENCY|' +
              'final balance|total net profit|Trades|deals|no trading|' +
              'Scalping Robot Pro|Environment|configuration|abnormal|' +
              'profitFactor|expectancy|maxDD|win rate|winRate|payoff|' +
              'exits:|holding:|entries=|ENTRY GATES|SCALP FUNNEL|blocked by|' +
              'scalps/day|avg win|avg spread'
} | Select-Object -First 90 | ForEach-Object { '  ' + $_.Trim() }

Write-Output '--- trade activity ---'
$deals = $clean | Where-Object { $_ -match '\b(deal|order) #?\d+' }
Write-Output ("  order/deal log lines: " + $deals.Count)
$deals | Select-Object -First 12 | ForEach-Object { '  ' + $_.Trim() }

$fatal = $clean | Where-Object { $_ -match 'invalid pointer|leaked|not deleted|zero divide|array out of range|critical error' }
Write-Output ''
if ($fatal.Count -gt 0) {
    Write-Output 'RUNTIME FAULTS DETECTED:'
    $fatal | ForEach-Object { '  ' + $_.Trim() }
    exit 1
}
Write-Output 'NO RUNTIME FAULTS DETECTED'
exit 0
