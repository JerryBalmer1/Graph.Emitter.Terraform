function Get-TerraformClassifierPrefixRow {
    # Not exported. The prefix row that places -Type of -Address, or $null: the type without
    # its provider token (the text before the first underscore) must equal the row's prefix
    # or start with the prefix and an underscore, so git matches azuredevops_git and
    # azuredevops_git_repository but not azuredevops_github. The longest matching prefix
    # wins; Read-TerraformClassifierMap keeps each provider's rows longest first.
    param($Map, [string]$Address, [string]$Type)

    $rows = $null
    if (-not $Map.Prefix.TryGetValue($Address, [ref]$rows)) { return $null }
    $cut = $Type.IndexOf('_')
    if ($cut -lt 0) { return $null }
    $rest = $Type.Substring($cut + 1)
    foreach ($row in $rows) {
        $prefix = [string]$row['subcategory']
        if ($rest -ceq $prefix -or $rest.StartsWith("$($prefix)_", [System.StringComparison]::Ordinal)) { return $row }
    }
    $null
}
