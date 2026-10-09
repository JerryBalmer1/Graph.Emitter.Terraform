function New-TerraformGraphBundleEntry {
    # Not exported. One entry per -RegistryProvider record: version is the registry cache's
    # latest; docsVersion the docs cached at that version, else the newest cached docs, and
    # harvestedOn when they were harvested; schemaVersion the version when the schema cache
    # holds exactly that version, else null; classifierVersion the newest bundled classifier.
    param([object[]]$RegistryProvider)

    $docs = @(Get-TerraformSchemaCacheEntry -Kind Docs)
    $schemas = @(Get-TerraformSchemaCacheEntry)
    $classifiers = @(Get-TerraformGraphBundleClassifierEntry)
    foreach ($provider in $RegistryProvider) {
        $address = $provider.ProviderAddress
        $version = if ($provider.Latest) { [string]$provider.Latest } else { $null }
        $mineDocs = @($docs | Where-Object ProviderAddress -eq $address)
        $doc = $mineDocs | Where-Object Version -eq $version | Select-Object -First 1
        if (-not $doc) { $doc = $mineDocs | Select-Object -First 1 }
        $schema = $schemas | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $version } | Select-Object -First 1
        $mineClassifiers = @($classifiers | Where-Object ProviderAddress -eq $address)
        $classifier = if ($mineClassifiers.Count) { @(Sort-TerraformRegistryVersion -Versions $mineClassifiers)[0].Record } else { $null }
        [ordered]@{
            provider          = $address
            version           = $version
            docsVersion       = if ($doc) { $doc.Version } else { $null }
            schemaVersion     = if ($schema) { $schema.Version } else { $null }
            classifierVersion = if ($classifier) { $classifier.Version } else { $null }
            harvestedOn       = if ($doc) { $doc.HarvestedOn } else { $null }
        }
    }
}
