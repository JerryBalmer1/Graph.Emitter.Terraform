function Read-TerraformSchemaCache {
    # Not exported. A cache file (either kind) as ordered dictionaries, the shape
    # Get-TerraformProviderSchema returns.
    param([string]$Path)

    [TerraformGraph.Json]::Deserialize((Read-TerraformSchemaCacheText -Path $Path), 1024, $true)
}
