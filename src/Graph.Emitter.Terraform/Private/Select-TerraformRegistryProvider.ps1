function Select-TerraformRegistryProvider {
    # Not exported. Providers matching any -Name pattern (all when none): a pattern with
    # two slashes matches ProviderAddress, one slash namespace/name, none the bare name in
    # any namespace. -like, so wildcards work and case is ignored. -ByTier sorts official
    # first, then by namespace/name; otherwise cache order (by address).
    param($Cache, [string[]]$Name, [string[]]$Tier, [switch]$ByTier)

    $selected = foreach ($provider in $Cache.Providers) {
        if ($Tier -and $Tier -notcontains $provider.Tier) { continue }
        if (-not $Name) { $provider; continue }
        foreach ($pattern in $Name) {
            $value = switch ($pattern.Split('/').Count) {
                1       { $provider.Name }
                2       { $provider.Source }
                default { $provider.ProviderAddress }
            }
            if ($value -like $pattern) { $provider; break }
        }
    }
    if (-not $ByTier) { return $selected }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($provider in $selected) { $list.Add($provider) }
    $rank = $script:TerraformRegistryTierRank
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            $byTier = ($rank[$a.Tier] ?? 9).CompareTo(($rank[$b.Tier] ?? 9))
            if ($byTier) { return $byTier }
            [string]::CompareOrdinal($a.Source.ToLowerInvariant(), $b.Source.ToLowerInvariant())
        })
    $list.ToArray()
}
