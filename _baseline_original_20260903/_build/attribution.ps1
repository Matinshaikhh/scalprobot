# Aggregates the exported per-trade CSV by strategy, exit reason and hour.
#
# Reads the rows the EA writes at shutdown. Nothing is modelled or inferred
# here: every figure is a sum over realised closed trades, so a strategy that
# looks profitable in this table actually was over the measured period.
param([string]$Csv = '')

if ($Csv -eq '') {
    $f = Get-ChildItem 'C:\Program Files\MetaTrader 5' -Recurse -Filter 'trades_*.csv' `
         -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -like '*Reports*' } |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $f) { 'NO TRADE CSV FOUND'; exit }
    $Csv = $f.FullName
}
"source: $Csv"

$rows = Import-Csv -LiteralPath $Csv
"rows: $($rows.Count)"
if ($rows.Count -eq 0) { exit }

# Column names are discovered rather than assumed, so a header change shows
# up as a clear failure instead of silently zeroed output.
$cols = $rows[0].PSObject.Properties.Name
"columns: $($cols -join ', ')"

function Summarise($group, $label) {
    # The net P/L column is named "net" in the EA's export.
    $out = @()
    foreach ($g in $group) {
        $net = ($g.Group | Measure-Object -Property net -Sum).Sum
        $wins = @($g.Group | Where-Object { [double]$_.net -gt 0 })
        $loss = @($g.Group | Where-Object { [double]$_.net -le 0 })
        $gp = ($wins | Measure-Object -Property net -Sum).Sum
        $gl = ($loss | Measure-Object -Property net -Sum).Sum
        $pf = if ($gl -ne 0) { [math]::Round($gp / [math]::Abs($gl), 3) } else { 'inf' }
        $out += [pscustomobject][ordered]@{
            $label   = $g.Name
            trades   = $g.Count
            winRate  = [math]::Round(100.0 * $wins.Count / $g.Count, 2)
            net      = [math]::Round($net, 2)
            pf       = $pf
            expectancy = [math]::Round($net / $g.Count, 2)
        }
    }
    $out | Sort-Object -Property trades -Descending
}

if ($cols -contains 'strategy') {
    ''; '=== BY STRATEGY ==='
    Summarise (($rows | Group-Object strategy)) 'strategy' | Format-Table -AutoSize
}
if ($cols -contains 'exit_reason') {
    ''; '=== BY EXIT REASON ==='
    # NORMALISE the reason before grouping. The EA embeds the stop price in
    # the text ("sl 2318.18"), so grouping raw strings produced one row per
    # price level - 600+ single-trade rows that hid the actual distribution.
    $withExit = $rows | ForEach-Object {
        $r = $_.exit_reason
        $k = switch -Regex ($r) {
            '^SRP-scalp early profit' { 'EARLY_PROFIT' }
            '^SRP-scalp timeout'      { 'SCALP_TIMEOUT' }
            '^sl\b'                   { 'STOP_LOSS' }
            '^tp\b'                   { 'TAKE_PROFIT' }
            default                   { if ($r) { $r } else { 'unknown' } }
        }
        $_ | Add-Member -NotePropertyName exit_kind -NotePropertyValue $k -Force -PassThru
    }
    Summarise (($withExit | Group-Object exit_kind)) 'exit' | Format-Table -AutoSize
}

if ($cols -contains 'strategy') {
    ''; '=== BY STRATEGY FAMILY ==='
    # Same problem: the strategy label carries a confidence figure, so the
    # raw values split one strategy across many rows.
    $withFam = $rows | ForEach-Object {
        $s = $_.strategy
        $f = 'other'
        if ($s -match 'from\s+([A-Za-z]+)') { $f = $Matches[1] }
        $d = if ($s -match '^SRP-(BUY|SELL)') { $Matches[1] } else { '?' }
        $_ | Add-Member -NotePropertyName family -NotePropertyValue $f -Force -PassThru |
             Add-Member -NotePropertyName dir -NotePropertyValue $d -Force -PassThru
    }
    Summarise (($withFam | Group-Object family)) 'family' | Format-Table -AutoSize
}
if ($cols -contains 'side') {
    ''; '=== BY DIRECTION ==='
    Summarise (($rows | Group-Object side)) 'side' | Format-Table -AutoSize
}
if ($cols -contains 'open_time') {
    ''; '=== BY HOUR OF OPEN ==='
    $withHour = $rows | ForEach-Object {
        $h = 'n/a'
        if ($_.open_time -match '(\d\d):\d\d') { $h = $Matches[1] }
        $_ | Add-Member -NotePropertyName hour -NotePropertyValue $h -Force -PassThru
    }
    Summarise (($withHour | Group-Object hour)) 'hour' |
        Sort-Object -Property hour | Format-Table -AutoSize
}
