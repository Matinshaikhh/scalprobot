# Runs a verification harness for real, headlessly, via the Strategy Tester.
#
# Compiling proves the code is well formed; it does not prove behaviour. The
# Strategy Tester is used because it is the only MT5 entry point that can be
# launched non-interactively.
param(
    [string]$Harness = 'P6ProductionCheck',
    [string]$Symbol  = 'EURUSD',
    [string]$Pattern = 'SRP_RESULT|SRP_PROFILE|SRP_REGIME',
    # Default start sits well inside available history so higher-timeframe
    # indicators are warmed up quickly.
    [string]$From    = '2025.01.20',
    [string]$To      = '2025.01.24',
    # Model 2 = open prices only, the cheapest. Harnesses that assert in
    # OnInit need no ticks. A harness that must wait for BarsCalculated to
    # reach READY does need them, so it passes -Model 1 (1-minute OHLC).
    [int]$Model      = 2,
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
$mt5   = 'C:\Program Files\MetaTrader 5'
$src   = 'c:\scalp robot\MQL5'
$term  = Join-Path $mt5 'terminal64.exe'
$ed    = Join-Path $mt5 'MetaEditor64.exe'
$mqlRt = Join-Path $mt5 'MQL5'

# --- deploy -------------------------------------------------------------
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

# --- compile the harness in place ---------------------------------------
$ea  = Join-Path $mqlRt "Experts\ScalpRobotPro\$Harness.mq5"
if (-not (Test-Path $ea)) { Write-Output "NO SUCH HARNESS: $Harness"; exit 1 }
$log = [System.IO.Path]::ChangeExtension($ea, '.buildlog')
$ex5 = [System.IO.Path]::ChangeExtension($ea, '.ex5')
if (Test-Path $ex5) { Remove-Item $ex5 -Force }
cmd /c "`"$ed`" /compile:`"$ea`" /inc:`"$mqlRt`" /log:`"$log`"" 2>&1 | Out-Null
if (-not (Test-Path $ex5)) {
    Write-Output "$Harness DID NOT COMPILE"
    if (Test-Path $log) {
        Get-Content $log -Encoding Unicode | Where-Object { $_ -match 'error|Result:' } |
            ForEach-Object { '  ' + $_.Trim() }
    }
    exit 1
}

# --- run ----------------------------------------------------------------
# Model=2 (open prices only) is the cheapest model. A harness does its work
# in OnInit and then fails init, so it never needs a tick - and asking for
# real ticks would trigger a multi-gigabyte download first.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ini   = Join-Path $env:TEMP "srp_h_$stamp.ini"
@"
[Tester]
Expert=ScalpRobotPro\$Harness.ex5
Symbol=$Symbol
Period=M1
Model=$Model
FromDate=$From
ToDate=$To
Optimization=0
ShutdownTerminal=1
Deposit=10000
Currency=USD
Leverage=100
Visual=0
"@ | Set-Content -LiteralPath $ini -Encoding ASCII

$logDirs = @((Join-Path $mt5 'Tester\logs'), (Join-Path $mt5 'logs'))
foreach ($ld in $logDirs) {
    if (Test-Path $ld) {
        Get-ChildItem $ld -Filter '*.log' | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# Wait out a terminal left running from an earlier pass: it refuses this
# launch and holds the logs, so the harness would report no verdict for a
# suite that never ran.
$stale = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
if ($stale.Count -gt 0) {
    Write-Output "waiting for $($stale.Count) running terminal(s) to exit"
    foreach ($p in $stale) { $p.WaitForExit(600000) | Out-Null }
}
$proc = Start-Process -FilePath $term -ArgumentList "/config:`"$ini`"" -PassThru
if (-not $proc.WaitForExit(300000)) {
    Write-Output 'TESTER TIMED OUT'
    try { $proc.Kill() } catch { }
}
Start-Sleep -Seconds 2

function Read-MtLog([string]$path) {
    # Read via a COPY: a terminal still holding its log makes a direct
    # ReadAllBytes throw, which discarded the verdict of a suite that had
    # actually run. Same fix already applied to backtest.ps1 and test.ps1.
    $tmp = Join-Path $env:TEMP ('srp_h_' + [System.Guid]::NewGuid().ToString('N') + '.log')
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

$lines = @()
foreach ($ld in $logDirs) {
    if (-not (Test-Path $ld)) { continue }
    Get-ChildItem $ld -Filter '*.log' | Sort-Object LastWriteTime | ForEach-Object {
        $lines += Read-MtLog $_.FullName
    }
}
$clean = $lines | ForEach-Object {
    ($_ -replace '^\S+\s+\d+\s+\d\d:\d\d:\d\d\.\d+\s+\S+\s+', '') -replace '^\s+', ''
}

if ($Verbose) {
    $clean | Where-Object { $_ -match 'ok |FAIL|=== |CHECKS|Profile |Symbol ' } |
        ForEach-Object { '  ' + $_ }
} else {
    $clean | Where-Object { $_ -match 'FAIL' } | ForEach-Object { '  ' + $_ }
}

$verdict = $clean | Where-Object { $_ -match $Pattern } | Select-Object -Last 1
Write-Output ''
if ($verdict) {
    Write-Output "VERDICT [$Symbol/$Harness]: $verdict"
    if ($verdict -match 'VERDICT=PASS') { exit 0 } else { exit 1 }
}
Write-Output "NO VERDICT LINE FOUND [$Symbol/$Harness]"
$clean | Where-Object { $_ -match 'error|failed|invalid' } | Select-Object -First 10 |
    ForEach-Object { '  ' + $_ }
exit 1
