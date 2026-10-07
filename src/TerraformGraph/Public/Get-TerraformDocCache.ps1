function Get-TerraformDocCache {
    <#
    .SYNOPSIS
        Lists the provider docs in the local docs cache.

    .DESCRIPTION
        Get-TerraformDocCache lists the files in
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz, one
        TerraformGraph.CachedDoc per provider version, newest version first within each
        provider. It only reads, and never decompresses more than the start of each file.

    .PARAMETER Provider
        Only these providers. Patterns match by shape and may use wildcards, as for
        Get-TerraformSchemaCache. Default: every cached provider.

    .EXAMPLE
        Get-TerraformDocCache

        Every cached docs version with its page and unmatched counts.

    .OUTPUTS
        TerraformGraph.CachedDoc: ProviderAddress, Version, Path, Bytes, CachedOn (UTC),
        DocCount, UnmatchedCount (empty when the docs were not matched to a schema),
        HarvestedOn (as the file records it). Default view is ProviderAddress, Version,
        DocCount, UnmatchedCount, Bytes.

    .LINK
        Get-TerraformProviderDoc

    .LINK
        Get-TerraformSchemaCache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider
    )

    Select-TerraformSchemaCacheEntry -Entry @(Get-TerraformSchemaCacheEntry -Kind Docs) -Name $Provider
}
