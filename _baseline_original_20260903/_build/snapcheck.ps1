# Finds SInputSnapshot fields that CollectInputs never assigns.
#
# WHY THIS EXISTS
# MQL5 zero-initialises the struct, so a field the EA forgets to populate is
# not "left at its default" - it arrives as 0. When the market profile is
# authoritative that is invisible, because the profile overwrites it. With
# InpProfileOverridesInputs=false the zero survives into the sealed config.
#
# Two such fields were already found this way, and both failed in ways that
# looked like strategy behaviour rather than defects:
#   * context/setup timeframe -> iADX refused the handle, EA would not start
#   * session windows          -> every window 00:00-00:00, 100% of ticks blocked
#
# So the check is mechanical rather than a matter of remembering.
param(
    [string]$Builder = 'c:\scalp robot\MQL5\Include\ScalpRobotPro\Configuration\CConfigurationBuilder.mqh',
    [string]$Expert  = 'c:\scalp robot\MQL5\Experts\ScalpRobotPro\ScalpRobotPro.mq5'
)

# --- 1. field names declared in SInputSnapshot ---------------------------
$blines = Get-Content -LiteralPath $Builder
$inStruct = $false
$depth = 0
$fields = @()
foreach ($l in $blines) {
    if (-not $inStruct) {
        if ($l -match '^\s*struct\s+SInputSnapshot') { $inStruct = $true }
        continue
    }
    if ($l -match '\{') { $depth++ }
    if ($l -match '\}') { $depth--; if ($depth -le 0) { break } }
    # <type> <name>;  possibly with a trailing comment. Skip methods.
    if ($l -match '\(') { continue }
    $m = [regex]::Match($l, '^\s*[A-Za-z_][A-Za-z0-9_]*\s+([a-z_][a-z0-9_]*)\s*;')
    if ($m.Success) { $fields += $m.Groups[1].Value }
}

# --- 2. fields assigned in CollectInputs --------------------------------
$elines = Get-Content -LiteralPath $Expert
$assigned = @{}
foreach ($l in $elines) {
    $m = [regex]::Match($l, 'snapshot\.([a-z_][a-z0-9_]*)\s*=')
    if ($m.Success) { $assigned[$m.Groups[1].Value] = $true }
}

$missing = $fields | Where-Object { -not $assigned.ContainsKey($_) } | Sort-Object -Unique

"SInputSnapshot fields declared : $($fields.Count)"
"fields assigned by CollectInputs: $($assigned.Count)"
if ($missing.Count -eq 0) {
    'OK  every snapshot field is populated from an input'
} else {
    "UNPOPULATED ($($missing.Count)) - each arrives as 0 when the profile is advisory:"
    $missing | ForEach-Object { '  ' + $_ }
}
