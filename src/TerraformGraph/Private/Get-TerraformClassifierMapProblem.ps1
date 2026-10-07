function Get-TerraformClassifierMapProblem {
    # Not exported. Lint for a parsed map.json: one message per problem, nothing when the map
    # is clean. Every row needs a provider ('*' or a full lowercase address), a subcategory, a
    # reason, a drawer from -Drawer other than unclassified (unclassified is the fallback, not
    # a target: leave the row out and record why in DECISIONS.md), addedOn as yyyy-MM-dd and
    # addedBy agent or jerry. source is optional: subcategory (the default) or prefix. A prefix
    # row names one provider (not '*') and its subcategory field holds a type prefix after the
    # provider token: lowercase words joined by single underscores, such as git or
    # branch_policy. The same provider, source and subcategory may appear once.
    param($Map, [string[]]$Drawer)

    if ($Map -isnot [System.Collections.IDictionary] -or -not $Map.Contains('rows')) {
        'map has no top-level rows array.'
        return
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rows = @($Map['rows'])
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $provider = [string]$row['provider']
        $subcategory = [string]$row['subcategory']
        $source = if ($row.Contains('source')) { [string]$row['source'] } else { 'subcategory' }
        $label = if ($source -ceq 'prefix') { "row $($i + 1) ($provider / prefix $subcategory)" } else { "row $($i + 1) ($provider / $subcategory)" }
        if ($provider -cne '*' -and ($provider -notmatch '^[^/\s]+/[^/\s]+/[^/\s]+$' -or $provider -cne $provider.ToLowerInvariant())) {
            "$label`: provider must be '*' or a full lowercase address such as registry.terraform.io/hashicorp/azurerm."
        }
        if ($source -cnotin 'subcategory', 'prefix') {
            "$label`: source '$source' must be subcategory or prefix."
        }
        elseif ($source -ceq 'prefix') {
            if ($provider -ceq '*') { "$label`: a prefix row needs a provider address; a type prefix means something only within one provider." }
            if ($subcategory -and $subcategory -cnotmatch '^[a-z0-9]+(_[a-z0-9]+)*$') {
                "$label`: prefix '$subcategory' must be lowercase words joined by single underscores, without the provider token (git, not azuredevops_git_)."
            }
        }
        if ([string]::IsNullOrWhiteSpace($subcategory)) { "$label has no subcategory." }
        if ([string]::IsNullOrWhiteSpace([string]$row['reason'])) { "$label has no reason." }
        $drawerName = [string]$row['drawer']
        if ($drawerName -ceq 'unclassified') {
            "$label`: unclassified is the fallback drawer, not a map target. Leave the row out and record why in DECISIONS.md."
        }
        elseif ($Drawer -cnotcontains $drawerName) {
            "$label`: drawer '$drawerName' is not in drawers.json."
        }
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$row['addedOn'], 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
            "$label`: addedOn '$($row['addedOn'])' is not a yyyy-MM-dd date."
        }
        if ([string]$row['addedBy'] -cnotin 'agent', 'jerry') {
            "$label`: addedBy '$($row['addedBy'])' must be agent or jerry."
        }
        if (-not $seen.Add("$provider`n$source`n$subcategory")) {
            "$label repeats an earlier row for the same provider and subcategory."
        }
    }
}
