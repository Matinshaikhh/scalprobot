# Greps MT5 logs for a pattern.
#
# EA Print output lands in the tester AGENT log, but the terminal log is
# where startup and tester lifecycle lines appear, so BOTH trees are
# searched and the newest match wins. Every file is read via a copy: a live
# terminal keeps its log open and a direct read throws.
param([string]$Match = 'ENTRY GATES', [int]$Last = 40, [switch]$AllFiles)

$roots = @('C:\Program Files\MetaTrader 5\Tester',
           'C:\Program Files\MetaTrader 5\logs',
           'C:\Program Files\MetaTrader 5\MQL5\logs')

$files = @()
foreach ($r in $roots) {
    if (Test-Path $r) {
        $files += Get-ChildItem $r -Recurse -Filter *.log -ErrorAction SilentlyContinue
    }
}
if ($files.Count -eq 0) { 'NO LOG FILES FOUND'; exit }

function Read-Copy([string]$path) {
    $tmp = Join-Path $env:TEMP ('srp_ag_' + [System.Guid]::NewGuid().ToString('N') + '.log')
    try { Copy-Item -LiteralPath $path -Destination $tmp -Force -ErrorAction Stop }
    catch { return @() }
    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    $nulls = 0
    $limit = [Math]::Min(400, $bytes.Length)
    for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $nulls++ } }
    $text = if ($nulls -gt ($limit / 8)) { [System.Text.Encoding]::Unicode.GetString($bytes) }
            else { [System.Text.Encoding]::UTF8.GetString($bytes) }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return ($text -split "`r?`n")
}

# Newest first, and stop at the first file that actually contains the
# pattern unless every file was requested.
$ordered = $files | Sort-Object LastWriteTime -Descending
foreach ($f in $ordered) {
    $lines = Read-Copy $f.FullName
    $hits = $lines | Select-String -Pattern $Match
    if ($hits.Count -eq 0 -and -not $AllFiles) { continue }
    "file: $($f.FullName)  written: $($f.LastWriteTime)  lines: $($lines.Count)"
    $hits | Select-Object -Last $Last |
        ForEach-Object { ($_.Line -replace '^\S+\s+\d+\s+', '').TrimEnd() }
    if (-not $AllFiles) { break }
}
