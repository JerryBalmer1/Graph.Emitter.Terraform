function Get-TerraformClassifierPrefixProblem {
    # Not exported. Lint for -Address's prefix rows against its schema types: one message per
    # row whose prefix matches no type, so a typo or a renamed type cannot sit in the map
    # unnoticed.
    param($Map, [string]$Address, [string[]]$Type)

    $rows = $null
    if (-not $Map.Prefix.TryGetValue($Address, [ref]$rows)) { return }
    foreach ($row in $rows) {
        $prefix = [string]$row['subcategory']
        $hit = $false
        foreach ($name in $Type) {
            $cut = $name.IndexOf('_')
            if ($cut -lt 0) { continue }
            $rest = $name.Substring($cut + 1)
            if ($rest -ceq $prefix -or $rest.StartsWith("$($prefix)_", [System.StringComparison]::Ordinal)) { $hit = $true; break }
        }
        if (-not $hit) { "prefix row '$prefix' for $Address matches no resource or data source type in its schema." }
    }
}
