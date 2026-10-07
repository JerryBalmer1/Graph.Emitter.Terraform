function New-TerraformGraphBundleSource {
    # Not exported. The sources block for a bundle resolved against -Registry with -Entries
    # (bundle entry dictionaries): the static table above plus lastPulled per kind, from data
    # only (never the clock), so the same caches give the same bytes. registry: the registry
    # cache's harvestedOn. schemas: the newest CachedOn of the schema files the entries record.
    # docs: the newest entry harvestedOn. classifiers: the newest generatedOn of the bundled
    # classifiers the entries record. skills and cmdb: null (shipped with the module, or not
    # harvested yet). -NoSchemaCache leaves schemas null without reading the schema cache
    # (Test-TerraformGraphBundle -Scope Repo).
    param($Registry, [object[]]$Entries, [switch]$NoSchemaCache)

    $pulled = @{ registry = $Registry.HarvestedOn; schemas = $null; docs = $null; classifiers = $null }
    $stamp = { param($Value) if ($Value -is [datetime]) { $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) } else { [string]$Value } }
    $schemas = if ($NoSchemaCache) { @() } else { @(Get-TerraformSchemaCacheEntry) }
    $classifiers = @(Get-TerraformGraphBundleClassifierEntry)
    foreach ($entry in $Entries) {
        $address = [string]$entry['provider']
        if ($entry['harvestedOn'] -and [string]$entry['harvestedOn'] -gt [string]$pulled.docs) { $pulled.docs = [string]$entry['harvestedOn'] }
        if ($entry['schemaVersion']) {
            $schema = $schemas | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq [string]$entry['schemaVersion'] } | Select-Object -First 1
            if ($schema) {
                $value = & $stamp $schema.CachedOn
                if ($value -gt [string]$pulled.schemas) { $pulled.schemas = $value }
            }
        }
        if ($entry['classifierVersion']) {
            $classifier = $classifiers | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq [string]$entry['classifierVersion'] } | Select-Object -First 1
            if ($classifier) {
                $value = [string](Read-TerraformClassifierJson -Path $classifier.Path)['generatedOn']
                if ($value -gt [string]$pulled.classifiers) { $pulled.classifiers = $value }
            }
        }
    }
    foreach ($source in $script:TerraformGraphBundleSources) {
        [ordered]@{
            kind        = $source.kind
            urls        = [object[]]@($source.urls)
            relatedUrls = [object[]]@($source.relatedUrls)
            harvestedBy = $source.harvestedBy
            lastPulled  = if ($pulled.ContainsKey($source.kind)) { $pulled[$source.kind] } else { $null }
        }
    }
}
