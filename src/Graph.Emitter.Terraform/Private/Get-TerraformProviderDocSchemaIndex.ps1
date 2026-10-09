function Get-TerraformProviderDocSchemaIndex {
    # Not exported. The resource and data source types of one provider from the schema
    # cache, for joining docs to schema node Ids: the schema cached at -Version, else the
    # newest cached version, else $null. Prefix is the most common text before the first
    # underscore across those types (azurerm, azuredevops, vsphere, null).
    param([string]$Address, [string]$Version)

    $entries = @(Get-TerraformSchemaCacheEntry | Where-Object ProviderAddress -eq $Address)
    if (-not $entries.Count) { return $null }
    $entry = $entries | Where-Object Version -eq $Version | Select-Object -First 1
    if (-not $entry) {
        $entry = $entries[0]
        Write-Verbose "No cached schema for $Address $Version; matching docs against the cached $($entry.Version) schema"
    }

    $document = Read-TerraformSchemaCache -Path $entry.Path
    $schemas = $document['provider_schemas']
    $key = @($schemas.Keys) | Where-Object { $_ -eq $Address } | Select-Object -First 1
    $schema = $schemas[$key]
    $resource = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $data = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($schema['resource_schemas']) { foreach ($type in $schema['resource_schemas'].Keys) { $null = $resource.Add([string]$type) } }
    if ($schema['data_source_schemas']) { foreach ($type in $schema['data_source_schemas'].Keys) { $null = $data.Add([string]$type) } }

    $prefix = @(@($resource) + @($data) | ForEach-Object { $_.Split('_')[0] } | Group-Object -NoElement |
            Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
            Select-Object -First 1).Name
    [pscustomobject]@{
        SchemaVersion = $entry.Version
        Prefix        = if ($prefix) { $prefix } else { $Address.Split('/')[-1] }
        Resource      = $resource
        Data          = $data
    }
}
