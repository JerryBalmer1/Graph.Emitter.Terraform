function Get-TerraformSchemaCacheDocument {
    # Not exported. One schema document holding every -Entry's provider, in the shape
    # terraform providers schema -json prints, for ConvertTo-TerraformSchemaGraph.
    param([object[]]$Entry)

    $providerSchemas = [ordered]@{}
    $formatVersion = '1.0'
    foreach ($item in $Entry) {
        Write-Verbose "Reading $($item.ProviderAddress) $($item.Version) from $($item.Path)"
        $document = Read-TerraformSchemaCache -Path $item.Path
        if ($document['format_version']) { $formatVersion = $document['format_version'] }
        foreach ($key in @($document['provider_schemas'].Keys)) {
            $providerSchemas[$key] = $document['provider_schemas'][$key]
        }
    }
    [ordered]@{ format_version = $formatVersion; provider_schemas = $providerSchemas }
}
