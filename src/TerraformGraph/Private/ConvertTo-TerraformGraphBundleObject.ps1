function ConvertTo-TerraformGraphBundleObject {
    # Not exported. A parsed bundle as TerraformGraph.Bundle with TerraformGraph.BundleEntry
    # Entries and TerraformGraph.BundleSource Sources.
    param([System.Collections.IDictionary]$Document, [string]$Path)

    $registry = $Document['registry']
    $sources = [object[]]@(ConvertTo-TerraformGraphBundleSourceObject -Source @($Document['sources']))
    $entries = [object[]]@(foreach ($entry in @($Document['entries'])) {
            [pscustomobject]@{
                PSTypeName        = 'TerraformGraph.BundleEntry'
                ProviderAddress   = [string]$entry['provider']
                Version           = $entry['version']
                DocsVersion       = $entry['docsVersion']
                SchemaVersion     = $entry['schemaVersion']
                ClassifierVersion = $entry['classifierVersion']
                HarvestedOn       = $entry['harvestedOn']
            }
        })
    [pscustomobject]@{
        PSTypeName            = 'TerraformGraph.Bundle'
        Path                  = $Path
        FormatVersion         = $Document['formatVersion']
        Tiers                 = [string[]]@($Document['tiers'])
        Providers             = [string[]]@($Document['providers'])
        Exclude               = [string[]]@($Document['exclude'])
        RegistryHarvestedOn   = if ($registry -is [System.Collections.IDictionary]) { $registry['harvestedOn'] } else { $null }
        RegistryProviderCount = if ($registry -is [System.Collections.IDictionary]) { $registry['providerCount'] } else { $null }
        Sources               = $sources
        Entries               = $entries
        EntryCount            = $entries.Length
        # Packs are built per provider by Invoke-Build BuildSchemaPack, a schema pack and a docs
        # pack for each entry with a schemaVersion; the rest are indexed from the registry only
        # (their docs, if any, were harvested on the machine that wrote the bundle).
        PackedEntryCount       = @($entries | Where-Object SchemaVersion).Count
        ClassifiedEntryCount   = @($entries | Where-Object ClassifierVersion).Count
        RegistryOnlyEntryCount = @($entries | Where-Object { -not $_.SchemaVersion }).Count
    }
}
