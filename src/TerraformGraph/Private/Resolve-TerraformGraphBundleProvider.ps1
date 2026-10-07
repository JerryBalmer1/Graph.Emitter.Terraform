function Resolve-TerraformGraphBundleProvider {
    # Not exported. The registry providers a bundle covers, sorted by address: every provider
    # in -Tier, plus every match of each -Provider pattern (matched by shape, as
    # Get-TerraformRegistryProvider -Name; a pattern with no match throws), less any provider
    # an -Exclude pattern matches.
    param([string[]]$Tier, [string[]]$Provider, [string[]]$Exclude, $Cache)

    $selected = [System.Collections.Generic.SortedDictionary[string, object]]::new([System.StringComparer]::Ordinal)
    if ($Tier) {
        foreach ($item in @(Select-TerraformRegistryProvider -Cache $Cache -Tier $Tier)) { $selected[$item.ProviderAddress] = $item }
    }
    foreach ($pattern in $Provider) {
        $found = @(Select-TerraformRegistryProvider -Cache $Cache -Name $pattern)
        if (-not $found.Count) {
            Stop-TerraformGraphCommand -Throw -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $pattern -ExceptionType ([System.ArgumentException]) -Message "'$pattern' matches no provider in the registry cache $($Cache.Path) (harvested $($Cache.HarvestedOn)). Run Update-TerraformRegistryCache, or fix the pattern."
        }
        foreach ($item in $found) { $selected[$item.ProviderAddress] = $item }
    }
    if ($Exclude) {
        foreach ($item in @($selected.Values)) {
            if (@(Select-TerraformRegistryProvider -Cache ([pscustomobject]@{ Providers = @($item) }) -Name $Exclude).Count) {
                $null = $selected.Remove($item.ProviderAddress)
            }
        }
    }
    @($selected.Values)
}
