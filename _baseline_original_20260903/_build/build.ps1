param([string]$Target = 'all')

# MetaEditor CLI notes (learned the hard way in Phase 1/2):
#   * Start-Process swallows all output -> use cmd /c
#   * the build root must contain NO spaces
#   * /inc: must point at the MQL5 root for <ScalpRobotPro/...> to resolve
$ErrorActionPreference = 'Continue'
$editor  = 'C:\Program Files\MetaTrader 5\MetaEditor64.exe'
$srcRoot = 'c:\scalp robot\MQL5'
$bldRoot = 'C:\srp_build\MQL5'

if (Test-Path $bldRoot) { Remove-Item $bldRoot -Recurse -Force }
New-Item -ItemType Directory -Path $bldRoot -Force | Out-Null
Copy-Item (Join-Path $srcRoot 'Include') -Destination $bldRoot -Recurse -Force
foreach ($d in @('Scripts','Experts')) {
    if (Test-Path (Join-Path $srcRoot $d)) {
        Copy-Item (Join-Path $srcRoot $d) -Destination $bldRoot -Recurse -Force
    }
}

$targets = @()
if ($Target -eq 'all') {
    $targets = Get-ChildItem -Path $bldRoot -Recurse -Filter '*.mq5' | ForEach-Object { $_.FullName }
} else {
    $targets = @(Join-Path $bldRoot $Target)
}

$totalErr = 0; $totalWarn = 0
foreach ($t in $targets) {
    if (-not (Test-Path $t)) { Write-Output ("MISSING: " + $t); continue }
    $log = [System.IO.Path]::ChangeExtension($t, '.buildlog')
    $ex5 = [System.IO.Path]::ChangeExtension($t, '.ex5')
    if (Test-Path $ex5) { Remove-Item $ex5 -Force }

    cmd /c "`"$editor`" /compile:`"$t`" /inc:`"$bldRoot`" /log:`"$log`"" 2>&1 | Out-Null

    Write-Output ("=== " + (Split-Path $t -Leaf) + " ===")
    if (Test-Path $log) {
        $lines = Get-Content $log -Encoding Unicode -ErrorAction SilentlyContinue
        $keep = $lines | Where-Object {
            $_ -match 'error|warning|Result:' -and
            $_ -notmatch 'information: (compiling|generating|code generated|including)'
        }
        foreach ($k in $keep) { Write-Output ("  " + $k.Trim()) }
        $res = $lines | Where-Object { $_ -match 'Result:' } | Select-Object -Last 1
        if ($res -match '(\d+) errors?, (\d+) warnings?') {
            $totalErr += [int]$Matches[1]; $totalWarn += [int]$Matches[2]
        }
    } else { Write-Output "  NO LOG" }
    Write-Output ("  ex5: " + (Test-Path $ex5))
}

Write-Output ""
Write-Output ("TOTAL ERRORS:   " + $totalErr)
Write-Output ("TOTAL WARNINGS: " + $totalWarn)
