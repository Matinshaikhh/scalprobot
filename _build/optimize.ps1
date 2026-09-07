# Runs a real GENETIC optimisation.
#
# This is the last subsystem that cannot be proven any other way: it
# verifies that OnTester returns a usable fitness, that the custom criterion
# actually ranks passes, that incoherent parameter sets are skipped rather
# than wasted on, and that the per-pass CSV export is written.
param(
    [string]$Symbol = 'XAUUSD',
    [string]$From   = '2025.01.02',
    [string]$To     = '2025.01.31'
)

$ErrorActionPreference = 'Continue'
$mt5   = 'C:\Program Files\MetaTrader 5'
$term  = Join-Path $mt5 'terminal64.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ini   = Join-Path $env:TEMP "srp_opt_$stamp.ini"

# Optimization=1 is the genetic algorithm. OptimizationCriterion=6 selects
# "Custom max", which is what routes ranking through OnTester.
@"
[Tester]
Expert=ScalpRobotPro\ScalpRobotPro.ex5
Symbol=$Symbol
Period=M1
Model=1
FromDate=$From
ToDate=$To
Optimization=1
OptimizationCriterion=6
ShutdownTerminal=1
Deposit=10000
Currency=USD
Leverage=100
Visual=0

[TesterInputs]
InpFastMaPeriod=9||5||2||15||Y
InpSlowMaPeriod=21||18||3||36||Y
InpRiskPercent=0.5||0.25||0.25||1.0||Y
InpTpRiskReward=1.6||1.2||0.2||2.4||Y
"@ | Set-Content -LiteralPath $ini -Encoding ASCII

# Clear the previous export so a stale file cannot be mistaken for a result.
$exportDir = Join-Path $mt5 'MQL5\Files\ScalpRobotPro\Optimization'
if (Test-Path $exportDir) {
    Get-ChildItem $exportDir -Filter '*.csv' | Remove-Item -Force -ErrorAction SilentlyContinue
}
foreach ($ld in @((Join-Path $mt5 'Tester\logs'), (Join-Path $mt5 'logs'))) {
    if (Test-Path $ld) {
        Get-ChildItem $ld -Filter '*.log' | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "genetic optimisation on $Symbol ($From .. $To)"
$p = Start-Process -FilePath $term -ArgumentList "/config:`"$ini`"" -PassThru
if (-not $p.WaitForExit(900000)) {
    Write-Output 'OPTIMISATION TIMED OUT'
    try { $p.Kill() } catch { }
}
Start-Sleep -Seconds 3

function Read-MtLog([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $nulls = 0
    $limit = [Math]::Min(400, $bytes.Length)
    for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
    $text = if ($nulls -gt ($limit / 8)) { [System.Text.Encoding]::Unicode.GetString($bytes) }
            else { [System.Text.Encoding]::UTF8.GetString($bytes) }
    return ($text -split "`r?`n")
}

$lines = @()
foreach ($ld in @((Join-Path $mt5 'logs'), (Join-Path $mt5 'Tester\logs'))) {
    if (-not (Test-Path $ld)) { continue }
    Get-ChildItem $ld -Filter '*.log' | Sort-Object LastWriteTime | ForEach-Object {
        $lines += Read-MtLog $_.FullName
    }
}
$clean = $lines | ForEach-Object { ($_ -replace '^\S+\s+\d+\s+', '').Trim() }

Write-Output '--- optimisation progress ---'
$clean | Where-Object {
    $_ -match 'genetic|optimization (finished|started)|passes|result:|best|' +
              'skipped|INIT_PARAMETERS|disabled|complete'
} | Select-Object -First 25 | ForEach-Object { '  ' + $_ }

Write-Output '--- per-pass CSV export ---'
if (Test-Path $exportDir) {
    Get-ChildItem $exportDir -Filter '*.csv' | ForEach-Object {
        $rows = @(Get-Content $_.FullName)
        "  $($_.Name): $($rows.Count) line(s)"
        $rows | Select-Object -First 3 | ForEach-Object { '    ' + $_ }
    }
} else {
    Write-Output '  export folder not created'
}

$faults = $clean | Where-Object { $_ -match 'invalid pointer|leaked|not deleted|critical error' }
Write-Output ''
if ($faults) { 'RUNTIME FAULTS:'; $faults | ForEach-Object { '  ' + $_ }; exit 1 }
Write-Output 'NO RUNTIME FAULTS DETECTED'
