function Get-TerraformRegistryProvider {
    <#
    .SYNOPSIS
        Lists Terraform providers and their versions from the registry cache.

    .DESCRIPTION
        Get-TerraformRegistryProvider reads the provider registry cache, never the network.
        The cache is the user file ($env:LOCALAPPDATA\TerraformGraph\registry.json, written
        by Update-TerraformRegistryCache) when present, else the copy bundled with the
        module. With no cache it writes one warning naming Update-TerraformRegistryCache
        and returns nothing.

        -Name patterns allow wildcards and match by shape: 'aws' or 'aws*' matches the bare
        name in any namespace, 'hashicorp/aws*' matches namespace/name, and
        'registry.terraform.io/hashicorp/aws' matches the full address. Case is ignored.

    .PARAMETER Name
        One or more name patterns. Default: every provider.

    .PARAMETER Tier
        Only these tiers: official, partner, community.

    .PARAMETER NoBundledData
        Ignore the bundled cache; read only the user cache.

    .EXAMPLE
        Get-TerraformRegistryProvider aws*

        Every cached provider whose name starts with aws, in any namespace.

    .EXAMPLE
        Get-TerraformRegistryProvider -Tier partner -Name 'datadog/*'

        Partner providers in the datadog namespace.

    .EXAMPLE
        (Get-TerraformRegistryProvider hashicorp/aws).Versions | Select-Object -First 5

        The five newest hashicorp/aws versions with protocols and publish dates.

    .OUTPUTS
        TerraformGraph.RegistryProvider: ProviderAddress, Source (namespace/name), Namespace,
        Name, Tier, Description, Latest, VersionCount, Versions (newest first: Version,
        Protocols, Published). Default view is ProviderAddress, Tier, Latest, VersionCount.

    .LINK
        Update-TerraformRegistryCache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Name,

        [ValidateSet('official', 'partner', 'community')]
        [string[]]
        $Tier,

        [switch]
        $NoBundledData
    )

    $cache = Get-TerraformRegistryCache -NoBundledData:$NoBundledData
    if (-not $cache) {
        Write-Warning 'No provider registry cache found. Run Update-TerraformRegistryCache to create one.'
        return
    }
    Select-TerraformRegistryProvider -Cache $cache -Name $Name -Tier $Tier
}
