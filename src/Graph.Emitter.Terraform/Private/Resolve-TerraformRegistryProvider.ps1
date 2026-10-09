function Resolve-TerraformRegistryProvider {
    # Not exported. Exactly one cached provider for -Name, or a throw whose message lists
    # every match. Callers turn the throw into their own terminating error.
    param([string]$Name, [switch]$NoBundledData)

    $cache = Get-TerraformRegistryCache -NoBundledData:$NoBundledData
    if (-not $cache) {
        Stop-TerraformGraphCommand -Throw -Id 'RegistryCacheNotFound' -Category ObjectNotFound -Target $Name -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "'$Name' matches no provider: there is no registry cache. Run Update-TerraformRegistryCache or pass a full address."
    }
    $found = @(Select-TerraformRegistryProvider -Cache $cache -Name $Name -ByTier)
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -eq 0) {
        $date = if ($cache.HarvestedOn.Length -ge 10) { $cache.HarvestedOn.Substring(0, 10) } else { $cache.HarvestedOn }
        Stop-TerraformGraphCommand -Throw -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $Name -ExceptionType ([System.ArgumentException]) -Message "'$Name' matches no provider in the registry cache (harvested $date). Run Update-TerraformRegistryCache or pass a full address."
    }
    Stop-TerraformGraphCommand -Throw -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $Name -ExceptionType ([System.ArgumentException]) -Message "'$Name' matches $($found.Count) providers: $(@($found.Source) -join ', '). Specify one; Get-TerraformRegistryProvider -Name '$Name' lists them."
}
