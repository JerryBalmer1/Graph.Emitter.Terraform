function Invoke-TerraformProviderDocUpdate {
    # Not exported. The harvest of one provider for Update-TerraformProviderDocCache: returns
    # its TerraformGraph.DocCache row, or throws an ErrorRecord carrying the command's error
    # id (RegistryProviderNotResolved, ProviderDocNotOnRegistry, ProviderDocHarvestFailed),
    # which the Provider set rethrows as terminating and the Bundle set turns into a warning
    # and a Failed row. -RegistryProvider (a registry cache record) skips resolving -Name.
    # -Version empty means the registry cache's latest, else the newest non-prerelease on the
    # registry. -Resume returns a version that is already cached before any network call
    # when the version is known locally, and otherwise continues from the version's partial
    # file (<version>.partial.json beside the cache file) when there is one; -Force harvests a
    # cached version again and deletes any partial file first. A finished harvest deletes the
    # partial file. -Quiet makes the no-cached-schema warning verbose, for bundle runs where
    # most providers have none.
    param([string]$Name, $RegistryProvider, [string]$Version, [int]$ThrottleLimit, [switch]$Force, [switch]$Resume, [switch]$Quiet)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $cachedRow = {
        param([string]$Address, [string]$DocVersion, [string]$Path)
        $entry = Get-TerraformSchemaCacheEntry -Kind Docs | Where-Object Path -eq ([System.IO.Path]::GetFullPath($Path)) | Select-Object -First 1
        $stopwatch.Stop()
        [pscustomobject]@{
            PSTypeName      = 'TerraformGraph.DocCache'
            ProviderAddress = $Address
            Version         = $DocVersion
            Path            = $Path
            Status          = 'Cached'
            DocCount        = $entry.DocCount
            UnmatchedCount  = $entry.UnmatchedCount
            SchemaVersion   = $null
            ResumedPages    = 0
            Elapsed         = $stopwatch.Elapsed
            Error           = $null
        }
    }

    if ($RegistryProvider) {
        $parsed = ConvertTo-TerraformProviderAddress -Provider $RegistryProvider.ProviderAddress
        $registryProvider = $RegistryProvider
        $Name = $RegistryProvider.ProviderAddress
    }
    else {
        try {
            if ([WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $registryProvider = Resolve-TerraformRegistryProvider -Name $Name
                $parsed = ConvertTo-TerraformProviderAddress -Provider $registryProvider.ProviderAddress
            }
            else {
                $parsed = ConvertTo-TerraformProviderAddress -Provider $Name
                $registryCache = Get-TerraformRegistryCache
                $registryProvider = if ($registryCache) {
                    $registryCache.Providers | Where-Object ProviderAddress -eq $parsed.Address.ToLowerInvariant() | Select-Object -First 1
                }
            }
        }
        catch {
            if ((Get-TerraformGraphErrorId $_) -eq 'RegistryCacheNotFound') { throw }
            Stop-TerraformGraphCommand -Throw -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $Name -ExceptionType ([System.ArgumentException]) -Message $_.Exception.Message
        }
    }
    if ($parsed.Host -ne $script:TerraformRegistrySource) {
        Stop-TerraformGraphCommand -Throw -Id 'ProviderDocNotOnRegistry' -Category InvalidArgument -Target $Name -ExceptionType ([System.ArgumentException]) -Message "$($parsed.Address) is not on $($script:TerraformRegistrySource); only registry providers have docs to harvest. Pass a registry address, such as Update-TerraformProviderDocCache -Provider hashicorp/null."
    }
    $address = $parsed.Address.ToLowerInvariant()
    # The registry record keeps the namespace's own case (IBM-Cloud), which the API is given.
    $namespace = if ($registryProvider) { $registryProvider.Namespace } else { $parsed.Namespace }
    $providerName = if ($registryProvider) { $registryProvider.Name } else { $parsed.Name }
    $wanted = if ($Version) { $Version } elseif ($registryProvider -and $registryProvider.Latest) { [string]$registryProvider.Latest } else { $null }

    if ($Resume -and $wanted) {
        $path = Get-TerraformSchemaCachePath -Provider $address -Version $wanted -Kind Docs
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Write-Verbose "Docs for $address $wanted are already cached at $path; -Resume skips them."
            return (& $cachedRow $address $wanted $path)
        }
    }

    try {
        $found = Find-TerraformProviderDocVersion -Namespace $namespace -Name $providerName -Version $wanted
    }
    catch {
        Stop-TerraformGraphCommand -Throw -Id 'ProviderDocHarvestFailed' -Category ConnectionError -Target $address -InnerException $_.Exception -Message "$($_.Exception.Message) List the versions with Get-TerraformRegistryProvider -Name $address | Select-Object -ExpandProperty Versions, or refresh them with Update-TerraformRegistryCache."
    }
    $docVersion = $found.Version
    $path = Get-TerraformSchemaCachePath -Provider $address -Version $docVersion -Kind Docs
    $existed = Test-Path -LiteralPath $path -PathType Leaf

    if ($existed -and -not $Force) {
        Write-Verbose "Docs for $address $docVersion are already cached at $path. Use -Force to harvest them again."
        return (& $cachedRow $address $docVersion $path)
    }

    $partialPath = Join-Path (Split-Path -Path $path -Parent) "$docVersion.partial.json"
    if ($Force -and (Test-Path -LiteralPath $partialPath -PathType Leaf)) {
        Write-Verbose "-Force: deleting $partialPath"
        Remove-Item -LiteralPath $partialPath -Force
    }
    Write-Verbose "Harvesting docs for $address $docVersion (registry version id $($found.VersionId))"
    $harvestState = @{}
    try {
        $docs = @(Get-TerraformProviderDocHarvest -VersionId $found.VersionId -ThrottleLimit $ThrottleLimit -PartialPath $partialPath -Resume:$Resume -Address $address -Version $docVersion -State $harvestState)
    }
    catch {
        Stop-TerraformGraphCommand -Throw -Id 'ProviderDocHarvestFailed' -Category ConnectionError -Target $address -InnerException $_.Exception -Message "$($_.Exception.Message) Run Update-TerraformProviderDocCache -Provider $address -Version $docVersion -Resume to continue."
    }

    $index = Get-TerraformProviderDocSchemaIndex -Address $address -Version $docVersion
    if (-not $index) {
        $message = "No cached schema for $address, so resource and data source doc Ids are built from the '$($parsed.Name)_' prefix without checking. Run Get-TerraformSchemaPack -Provider $($parsed.Source) (or Get-TerraformProviderSchema -Provider $($parsed.Source) -SaveToCache), then Update-TerraformProviderDocCache -Force, to match them to schema nodes."
        if ($Quiet) { Write-Verbose $message } else { Write-Warning $message }
    }
    $prefix = if ($index) { $index.Prefix } else { $parsed.Name }
    $document = ConvertTo-TerraformProviderDocDocument -Address $address -Version $docVersion -Docs $docs -Index $index -Prefix $prefix
    foreach ($doc in $document.docs) {
        if ($doc.id.StartsWith("$address/unmatched/", [System.StringComparison]::Ordinal)) { Write-Verbose "Unmatched: $($doc.category)/$($doc.slug)" }
    }
    $path = Write-TerraformSchemaCache -Provider $address -Version $docVersion -Document $document -Kind Docs
    if (Test-Path -LiteralPath $partialPath -PathType Leaf) { Remove-Item -LiteralPath $partialPath -Force }
    $stopwatch.Stop()
    Write-Verbose "Wrote $($document.docCount) docs for $address $docVersion ($(if ($index) { "$($document.unmatchedCount) unmatched against schema $($index.SchemaVersion)" } else { 'not matched: no cached schema' })) to $path in $($stopwatch.Elapsed)"

    [pscustomobject]@{
        PSTypeName      = 'TerraformGraph.DocCache'
        ProviderAddress = $address
        Version         = $docVersion
        Path            = $path
        Status          = if ($existed) { 'Updated' } else { 'Harvested' }
        DocCount        = $document.docCount
        UnmatchedCount  = $document.unmatchedCount
        SchemaVersion   = $document.schemaVersion
        ResumedPages    = [int]$harvestState.ResumedPages
        Elapsed         = $stopwatch.Elapsed
        Error           = $null
    }
}
