# Runtime verification.
#
# Compiling proves the code is well formed; it does not prove the object graph
# can be built, ticked and torn down. This deploys the sources into the MT5
# data folder, then runs the integration harness as a Strategy Tester pass and
# greps the resulting log for the machine-readable verdict line.
#
# The Strategy Tester is used because it is the only MT5 entry point that can
# be launched non-interactively from a command line.
param(
    [string]$Symbol = 'EURUSD',
    [string]$From   = '2025.01.02',
    [string]$To     = '2025.01.03'
)

$ErrorActionPreference = 'Continue'
$mt5   = 'C:\Program Files\MetaTrader 5'
$src   = 'c:\scalp robot\MQL5'
$term  = Join-Path $mt5 'terminal64.exe'
$ed    = Join-Path $mt5 'MetaEditor64.exe'
$mqlRt = Join-Path $mt5 'MQL5'

if (-not (Test-Path $term)) { Write-Output 'TERMINAL NOT FOUND'; exit 1 }

# --- 1. deploy ------------------------------------------------------------
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
Write-Output 'deployed sources into the terminal data folder'

# --- 2. compile the harness in place -------------------------------------
$harness = Join-Path $mqlRt 'Experts\ScalpRobotPro\P6ProductionCheck.mq5'
$hlog    = [System.IO.Path]::ChangeExtension($harness, '.buildlog')
$hex5    = [System.IO.Path]::ChangeExtension($harness, '.ex5')
if (Test-Path $hex5) { Remove-Item $hex5 -Force }
cmd /c "`"$ed`" /compile:`"$harness`" /inc:`"$mqlRt`" /log:`"$hlog`"" 2>&1 | Out-Null
if (-not (Test-Path $hex5)) {
    Write-Output 'HARNESS DID NOT COMPILE'
    if (Test-Path $hlog) {
        Get-Content $hlog -Encoding Unicode |
            Where-Object { $_ -match 'error|Result:' } |
            ForEach-Object { Write-Output ('  ' + $_.Trim()) }
    }
    exit 1
}
Write-Output 'harness compiled'

# --- 3. run it through the tester ----------------------------------------
# A fresh report path per run, so a stale log can never be mistaken for a
# current pass.
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$iniPath = Join-Path $env:TEMP "srp_test_$stamp.ini"
# Model=2 is "open prices only": the cheapest model the tester offers. The
# harness does all of its work in OnInit and then fails initialisation, so it
# never needs a tick - and asking for real ticks would trigger a multi-gigabyte
# download before the first assertion ever ran.
$ini = @"
[Tester]
Expert=ScalpRobotPro\P6ProductionCheck.ex5
Symbol=$Symbol
Period=M1
Model=2
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
Set-Content -LiteralPath $iniPath -Value $ini -Encoding ASCII

# Clear old tester logs so the grep below reads only this run.
$logDirs = @((Join-Path $mt5 'Tester\logs'), (Join-Path $mt5 'logs'))
foreach ($ld in $logDirs) {
    if (Test-Path $ld) { Get-ChildItem $ld -Filter '*.log' | Remove-Item -Force -ErrorAction SilentlyContinue }
}

Write-Output "running the tester on $Symbol ($From..$To)"
# Wait out any terminal still running from an earlier pass: it would refuse
# this launch and hold the logs, producing "no verdict" for a suite that never
# ran. Reported rather than silently absorbed.
$stale = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
if ($stale.Count -gt 0) {
    Write-Output "waiting for $($stale.Count) running terminal(s) to exit"
    foreach ($p in $stale) { $p.WaitForExit(600000) | Out-Null }
}
$proc = Start-Process -FilePath $term -ArgumentList "/config:`"$iniPath`"" -PassThru
if (-not $proc.WaitForExit(180000)) {
    Write-Output 'TESTER TIMED OUT'
    try { $proc.Kill() } catch { }
}

# --- 4. read the verdict -------------------------------------------------
# A terminal left running from an earlier pass refuses a fresh /config launch
# AND holds the logs open, so the suite reported no verdict while nothing had
# actually run. Waiting it out first makes the result trustworthy.
# MT5 writes these logs as UTF-16LE without a BOM, which Get-Content
# misreads. Detecting via interleaved NUL bytes is reliable and cheap.
function Read-MtLog([string]$path) {
    # Read via a COPY. A terminal still holding its log makes a direct
    # ReadAllBytes throw, and the whole verdict was then reported as
    # "NO VERDICT LINE FOUND" - a passing regression suite indistinguishable
    # from a failing one. Same defect was already fixed in backtest.ps1.
    $tmp = Join-Path $env:TEMP ('srp_t_' + [System.Guid]::NewGuid().ToString('N') + '.log')
    try { Copy-Item -LiteralPath $path -Destination $tmp -Force -ErrorAction Stop }
    catch { return @() }
    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $nulls = 0
    $limit = [Math]::Min(400, $bytes.Length)
    for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
    $text = if ($nulls -gt ($limit / 8)) {
        [System.Text.Encoding]::Unicode.GetString($bytes)
    } else {
        [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    return ($text -split "`r?`n")
}

Start-Sleep -Seconds 2
$lines = @()
foreach ($ld in $logDirs) {
    if (-not (Test-Path $ld)) { continue }
    Get-ChildItem $ld -Filter '*.log' | Sort-Object LastWriteTime | ForEach-Object {
        $lines += Read-MtLog $_.FullName
    }
}

# Strip the tester's log prefix (tag, level, timestamp, source) so the
# harness output reads like the assertions it is.
$interesting = $lines | Where-Object {
    $_ -match 'SRP_RESULT|FAIL|\bok\b|INTEGRATION|CHECKS|=== |CProductionEngine'
}
foreach ($l in $interesting) {
    Write-Output ('  ' + ($l -replace '^\S+\s+\d+\s+\d\d:\d\d:\d\d\.\d+\s+\S+\s+', ''))
}

$verdict = $lines | Where-Object { $_ -match 'SRP_RESULT' } | Select-Object -Last 1
Write-Output ''
if ($verdict) {
    Write-Output ('VERDICT: ' + ($verdict -replace '^.*SRP_RESULT', 'SRP_RESULT'))
    if ($verdict -match 'VERDICT=PASS') { exit 0 } else { exit 1 }
}
Write-Output 'NO VERDICT LINE FOUND IN TESTER LOGS'
exit 1
