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

# WHERE THE ARTIFACTS ARE, AND THAT THEY ARE NOT DEPLOYED.
#
# This script is a compile gate, not a deployment. It builds in a scratch
# tree because the MetaEditor CLI needs a build root with no spaces, and it
# deliberately does not touch the terminal - overwriting the EA the terminal
# has loaded, on every "does it still compile" check, is not something a
# compile gate should do quietly.
#
# `backtest.ps1` is what deploys: it wipes and re-copies the ScalpRobotPro
# source into `C:\Program Files\MetaTrader 5\MQL5` and compiles it there
# before every run. So a green build here does NOT mean the terminal's
# Navigator is showing the binary you just built, and on 2026-09-04 it did
# not - the terminal was still holding a 1.00 EX5 from the previous day.
# Saying so here costs one line and closes that gap.
Write-Output ""
Write-Output ("ARTIFACTS: " + $bldRoot + "  (scratch tree, NOT deployed)")
Write-Output "DEPLOY:    backtest.ps1 deploys+compiles into the MT5 tree before each run."
Write-Output "           To hand the terminal this exact binary without running a test:"
Write-Output ("           copy `"" + (Join-Path $bldRoot 'Experts\ScalpRobotPro\ScalpRobotPro.ex5') + "`" -> " +
              "`"C:\Program Files\MetaTrader 5\MQL5\Experts\ScalpRobotPro\`"")
