# Shows selected lines from the newest generated tester .set file.
param([string]$Match = '.')

$f = Get-ChildItem 'C:\Program Files\MetaTrader 5\MQL5\Profiles\Tester\srp_bt_*.set' `
     -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
     Select-Object -First 1
if ($null -eq $f) { 'NO GENERATED SET FILE'; exit }
"file: $($f.FullName)"
Get-Content -LiteralPath $f.FullName | Select-String -Pattern $Match |
    ForEach-Object { $_.Line }
