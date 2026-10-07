function Get-TerraformSchemaCache {
    <#
    .SYNOPSIS
        Lists the provider schemas in the local schema cache.

    .DESCRIPTION
        Get-TerraformSchemaCache lists the files in the local schema cache,
        $env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz, one
        TerraformGraph.CachedSchema per provider version. It only reads, and never
        decompresses more than the start of each file.

        The cache is filled by Get-TerraformSchemaPack (downloaded packs) and
        Get-TerraformProviderSchema -SaveToCache (harvested locally), and read by
        ConvertTo-TerraformSchemaGraph -Provider and ConvertTo-TerraformResourceGraph
        -Provider or -AutoSchema.

    .PARAMETER Provider
        Only these providers. Patterns match by shape and may use wildcards: 'azurerm' or
        'azure*' match the bare name in any namespace, 'hashicorp/azure*' namespace/name,
        and a full address the address. Case is ignored. Default: every cached schema.

    .EXAMPLE
        Get-TerraformSchemaCache

        Every cached provider version, newest version first within each provider.

    .EXAMPLE
        Get-TerraformSchemaCache 'azure*' | Measure-Object Bytes -Sum

        Disk used by the cached azurerm and azuredevops schemas.

    .OUTPUTS
        TerraformGraph.CachedSchema: ProviderAddress, Version, Path, Bytes, CachedOn (UTC).
        Default view is ProviderAddress, Version, Bytes, CachedOn.

    .LINK
        Get-TerraformSchemaPack
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider
    )

    Select-TerraformSchemaCacheEntry -Entry @(Get-TerraformSchemaCacheEntry) -Name $Provider
}
