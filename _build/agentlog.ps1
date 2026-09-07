param([int]$Tail = 80)
# The tester writes the EA's own output into the AGENT log, which is a
# different folder from Tester\logs. When an EA fails at OnInit the agent
# log is the only place the reason appears.
$root = 'C:\Program Files\MetaTrader 5\Tester'
$files = Get-ChildItem $root -Recurse -Filter '*.log' -ErrorAction SilentlyContinue
if ($files.Count -eq 0) { 'NO AGENT LOGS'; exit }
$p = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$bytes = [System.IO.File]::ReadAllBytes($p.FullName)
$nulls = 0
$limit = [Math]::Min(400, $bytes.Length)
for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
$text = if ($nulls -gt ($limit / 8)) { [System.Text.Encoding]::Unicode.GetString($bytes) }
        else { [System.Text.Encoding]::UTF8.GetString($bytes) }
$all = $text -split "`r?`n"
"file: $($p.FullName)   lines: $($all.Count)"
$all | Select-Object -Last $Tail |
    ForEach-Object { ($_ -replace '^\S+\s+\d+\s+', '').TrimEnd() }
