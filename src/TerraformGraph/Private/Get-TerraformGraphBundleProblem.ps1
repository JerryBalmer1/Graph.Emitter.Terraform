function Get-TerraformGraphBundleProblem {
    # Not exported. Lint for a parsed bundle: one message per problem, nothing when clean.
    param($Bundle)

    if ($Bundle -isnot [System.Collections.IDictionary]) {
        'the bundle is not a JSON object.'
        return
    }
    if ([string]$Bundle['formatVersion'] -ne [string]$script:TerraformGraphBundleFormatVersion) {
        "formatVersion '$($Bundle['formatVersion'])' is not $($script:TerraformGraphBundleFormatVersion)."
    }
    foreach ($tier in @($Bundle['tiers'])) {
        if ($null -ne $tier -and $script:TerraformGraphBundleTiers -cnotcontains [string]$tier) { "tier '$tier' is not official, partner or community." }
    }
    foreach ($key in 'providers', 'exclude') {
        foreach ($value in @($Bundle[$key])) {
            if ($null -ne $value -and [string]::IsNullOrWhiteSpace([string]$value)) { "$key has an empty value." }
        }
    }
    foreach ($entry in @($Bundle['entries'])) {
        if ($null -ne $entry -and ($entry -isnot [System.Collections.IDictionary] -or [string]::IsNullOrWhiteSpace([string]$entry['provider']))) { 'an entry has no provider.' }
    }
}
