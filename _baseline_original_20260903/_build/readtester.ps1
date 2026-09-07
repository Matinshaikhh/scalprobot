# Reads the newest TESTER agent log, copying it first so a live terminal
# handle cannot make the read fail. The tester writes EA Print output to
# the agent log, which is where every funnel and metric line lands.
param([int]$Tail = 250, [string]$Match = '')

# The AGENT log is where EA Print output lands, so it is searched
# recursively under Tester (the agent directory name contains a port and
# therefore is not a fixed path).
$files = @()
if (Test-Path 'C:\Program Files\MetaTrader 5\Tester') {
    $files += Get-ChildItem 'C:\Program Files\MetaTrader 5\Tester' -Recurse `
              -Filter *.log -ErrorAction SilentlyContinue
}
if (Test-Path 'C:\Program Files\MetaTrader 5\logs') {
    $files += Get-ChildItem 'C:\Program Files\MetaTrader 5\logs' `
              -Filter *.log -ErrorAction SilentlyContinue
}
if ($files.Count -eq 0) { 'NO LOG FILES FOUND'; exit }

$p = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$tmp = Join-Path $env:TEMP ('srp_read_' + [System.Guid]::NewGuid().ToString('N') + '.log')
Copy-Item -LiteralPath $p.FullName -Destination $tmp -Force

$bytes = [System.IO.File]::ReadAllBytes($tmp)
$nulls = 0
$limit = [Math]::Min(400, $bytes.Length)
for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
$text = if ($nulls -gt ($limit / 8)) { [System.Text.Encoding]::Unicode.GetString($bytes) }
        else { [System.Text.Encoding]::UTF8.GetString($bytes) }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

$all = $text -split "`r?`n"
"file: $($p.FullName)   lines: $($all.Count)"
$sel = $all | Select-Object -Last $Tail
if ($Match -ne '') { $sel = $sel | Select-String -Pattern $Match | ForEach-Object { $_.Line } }
$sel | ForEach-Object { ($_ -replace '^\S+\s+\d+\s+', '').TrimEnd() }
