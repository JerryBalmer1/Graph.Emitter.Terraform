function Resolve-TerraformClassifier {
    # Not exported. One classifier entry per provider the -Name patterns select (every
    # provider with a classifier when there are none), matched by shape as in
    # Get-TerraformSchemaCache, sorted by address. Throws when a pattern matches nothing or
    # -Version is not there; callers turn that into their own terminating error.
    param([string[]]$Name, [string]$Version, [string]$ClassifierPath)

    $entries = @(Get-TerraformClassifierEntry -ClassifierPath $ClassifierPath)
    $addresses = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Name) {
        foreach ($pattern in $Name) {
            $found = @(Select-TerraformSchemaCacheEntry -Entry $entries -Name $pattern)
            if (-not $found.Count) {
                Stop-TerraformGraphCommand -Throw -Id 'ClassifierNotFound' -Category ObjectNotFound -Target $pattern -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No classifier matches '$pattern'. Generate one with New-TerraformClassifier -Provider $pattern, or pass -ClassifierPath."
            }
            foreach ($item in $found) { $null = $addresses.Add($item.ProviderAddress) }
        }
    }
    else {
        foreach ($item in $entries) { $null = $addresses.Add($item.ProviderAddress) }
    }

    foreach ($address in $addresses) {
        $entry = Find-TerraformClassifierEntry -Entry $entries -Address $address -Version $Version
        if (-not $entry) {
            $available = @($entries | Where-Object ProviderAddress -eq $address | ForEach-Object Version | Select-Object -Unique)
            Stop-TerraformGraphCommand -Throw -Id 'ClassifierNotFound' -Category ObjectNotFound -Target $address -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No classifier for $address $Version (available: $($available -join ', ')). Generate it with New-TerraformClassifier -Provider $address -Version $Version."
        }
        $entry
    }
}
