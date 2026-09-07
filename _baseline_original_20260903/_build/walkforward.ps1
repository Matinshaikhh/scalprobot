# Rolling walk-forward over the available XAUUSD real-tick history.
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
    [string[]]$Windows = @(
        '2023.01.02:2023.07.01',
        '2023.07.01:2024.01.01',
        '2024.01.01:2024.07.01',
        '2024.07.01:2025.01.01',
        '2025.01.01:2025.08.01'
    )
)

$results = @()
foreach ($w in $Windows) {
    $parts = $w -split ':'
    $from = $parts[0]; $to = $parts[1]
    Write-Output "=== window $from .. $to ==="

    $out = & powershell -NoProfile -ExecutionPolicy Bypass `
           -File 'c:\scalp robot\_build\backtest.ps1' `
           -Symbol $Symbol -Model $Model -From $from -To $to -TimeoutMs 1800000 2>&1

    $trades = ($out | Select-String -Pattern 'trades=(\d+) wins=(\d+) losses=(\d+).*winRate=([\d\.]+)' |
               Select-Object -Last 1)
    $pf     = ($out | Select-String -Pattern 'profitFactor=([\d\.]+)' | Select-Object -Last 1)
    $dd     = ($out | Select-String -Pattern 'maxDD=[\d\.]+ \(([\d\.]+)%\)' | Select-Object -Last 1)
    $exp    = ($out | Select-String -Pattern 'expectancy=(-?[\d\.]+)' | Select-Object -Last 1)
    $bal    = ($out | Select-String -Pattern 'final balance ([\d\.]+)' | Select-Object -Last 1)

    $row = [ordered]@{
        window   = "$from..$to"
        trades   = if ($trades) { $trades.Matches[0].Groups[1].Value } else { 'n/a' }
        winRate  = if ($trades) { $trades.Matches[0].Groups[4].Value } else { 'n/a' }
        pf       = if ($pf)     { $pf.Matches[0].Groups[1].Value }     else { 'n/a' }
        expectancy = if ($exp)  { $exp.Matches[0].Groups[1].Value }    else { 'n/a' }
        maxDDpct = if ($dd)     { $dd.Matches[0].Groups[1].Value }     else { 'n/a' }
        balance  = if ($bal)    { $bal.Matches[0].Groups[1].Value }    else { 'n/a' }
    }
    $results += [pscustomobject]$row
    $results | Format-Table -AutoSize | Out-String | Write-Output
}

Write-Output '=== WALK-FORWARD SUMMARY (shipping config, no per-window fitting) ==='
$results | Format-Table -AutoSize
