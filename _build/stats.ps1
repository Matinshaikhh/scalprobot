$root = 'c:\scalp robot\MQL5'
$rows = @()
Get-ChildItem -Path $root -Recurse -Include *.mq5,*.mqh | ForEach-Object {
    $n = (Get-Content -LiteralPath $_.FullName).Count
    $rows += [pscustomobject]@{ Lines = $n; Path = $_.FullName.Substring($root.Length + 1) }
}
$rows | Sort-Object Path | ForEach-Object { "{0,6}  {1}" -f $_.Lines, $_.Path }
""
"FILES: " + $rows.Count
"LINES: " + ($rows | Measure-Object -Property Lines -Sum).Sum
