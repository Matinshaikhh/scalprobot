param([int]$Tail = 400)
$dirs = @('C:\Program Files\MetaTrader 5\Tester\logs',
          'C:\Program Files\MetaTrader 5\logs')
$files = @()
foreach ($d in $dirs) {
    if (Test-Path $d) {
        $files += Get-ChildItem $d -Filter *.log -ErrorAction SilentlyContinue
    }
}
if ($files.Count -eq 0) { 'NO LOG FILES FOUND'; exit }
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
