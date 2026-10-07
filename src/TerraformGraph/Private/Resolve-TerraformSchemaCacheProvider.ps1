function Resolve-TerraformSchemaCacheProvider {
    # Not exported. One cached schema per provider the -Name patterns select, at -Version or
    # the newest cached version. A name without a wildcard that matches several namespaces
    # resolves to the hashicorp one, else is an error. Throws when anything is not cached,
    # naming both ways to fill the -Kind cache; callers turn that into their own terminating
    # error.
    param([string[]]$Name, [string]$Version, [ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    $entries = @(Get-TerraformSchemaCacheEntry -Kind $Kind)
    $addresses = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $Name) {
        $found = @(Select-TerraformSchemaCacheEntry -Entry $entries -Name $pattern | ForEach-Object ProviderAddress | Select-Object -Unique)
        if ($found.Count -gt 1 -and -not [WildcardPattern]::ContainsWildcardCharacters($pattern)) {
            $normalized = (ConvertTo-TerraformProviderAddress -Provider $pattern).Address
            $preferred = @($found | Where-Object { $_ -eq $normalized })
            if (-not $preferred.Count) {
                if ($Kind -eq 'Docs') {
                    Stop-TerraformGraphCommand -Throw -Id 'ProviderDocNotCached' -Category InvalidArgument -Target $pattern -ExceptionType ([System.ArgumentException]) -Message "'$pattern' matches $($found.Count) cached providers: $($found -join ', '). Specify one; Get-TerraformDocCache -Provider '$pattern' lists them."
                }
                Stop-TerraformGraphCommand -Throw -Id 'SchemaNotCached' -Category InvalidArgument -Target $pattern -ExceptionType ([System.ArgumentException]) -Message "'$pattern' matches $($found.Count) cached providers: $($found -join ', '). Specify one; Get-TerraformSchemaCache -Provider '$pattern' lists them."
            }
            $found = $preferred
        }
        if (-not $found.Count) {
            if ($Kind -eq 'Docs') {
                Stop-TerraformGraphCommand -Throw -Id 'ProviderDocNotCached' -Category ObjectNotFound -Target $pattern -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No cached provider docs match '$pattern'. Download a docs pack with Get-TerraformDocPack -Provider $pattern, or harvest them from the registry with Update-TerraformProviderDocCache -Provider $pattern."
            }
            Stop-TerraformGraphCommand -Throw -Id 'SchemaNotCached' -Category ObjectNotFound -Target $pattern -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No cached schema matches '$pattern'. Download a schema pack with Get-TerraformSchemaPack -Provider $pattern, or harvest it locally with Get-TerraformProviderSchema -Provider $pattern -SaveToCache."
        }
        foreach ($address in $found) {
            if (-not ($addresses | Where-Object { $_ -eq $address })) { $addresses.Add($address) }
        }
    }

    foreach ($address in $addresses) {
        $versions = @($entries | Where-Object ProviderAddress -eq $address)
        if (-not $Version) { $versions[0]; continue }
        $entry = $versions | Where-Object Version -eq $Version | Select-Object -First 1
        if (-not $entry) {
            if ($Kind -eq 'Docs') {
                Stop-TerraformGraphCommand -Throw -Id 'ProviderDocNotCached' -Category ObjectNotFound -Target $address -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "Docs for $address $Version are not cached (cached: $(@($versions.Version) -join ', ')). Download them with Get-TerraformDocPack -Provider $address -Version $Version, or harvest them with Update-TerraformProviderDocCache -Provider $address -Version $Version."
            }
            Stop-TerraformGraphCommand -Throw -Id 'SchemaNotCached' -Category ObjectNotFound -Target $address -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "$address $Version is not cached (cached: $(@($versions.Version) -join ', ')). Download it with Get-TerraformSchemaPack -Provider $address -Version $Version, or harvest it locally with Get-TerraformProviderSchema -Provider $address -Version '= $Version' -SaveToCache."
        }
        $entry
    }
}
