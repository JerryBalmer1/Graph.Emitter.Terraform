function Read-TerraformRegistryCacheFile {
    # Not exported. One registry.json as the object Get-TerraformRegistryCache returns, not
    # memoized: Path, HarvestedOn, Scope, Source, Providers (TerraformGraph.RegistryProvider).
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    $document = [TerraformGraph.Json]::Deserialize([System.IO.File]::ReadAllText($item.FullName), 1024, $false)
    $providers = foreach ($entry in @($document.providers)) {
        $versions = @($entry.versions)
        [pscustomobject]@{
            PSTypeName      = 'TerraformGraph.RegistryProvider'
            ProviderAddress = [string]$entry.address
            Source          = "$($entry.namespace)/$($entry.name)"
            Namespace       = [string]$entry.namespace
            Name            = [string]$entry.name
            Tier            = [string]$entry.tier
            Description     = [string]$entry.description
            Latest          = $entry.latest
            VersionCount    = $versions.Count
            Versions        = $versions
        }
    }
    [pscustomobject]@{
        Path        = $item.FullName
        HarvestedOn = [string]$document.harvestedOn
        Scope       = [string]$document.scope
        Source      = [string]$document.source
        Providers   = @($providers)
    }
}
