function Get-TerraformDocPack {
    <#
    .SYNOPSIS
        Downloads provider docs packs into the local docs cache.

    .DESCRIPTION
        Get-TerraformDocPack is Get-TerraformSchemaPack for docs: it reads manifest.json
        from -Source, keeps the entries whose kind is docs, picks the entry for each
        provider (at -Version, or the newest version in the manifest), downloads the file,
        checks its sha256 and only then moves it into
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz. Pack files
        are named docs.<address-slug>.<version>.json.gz.

        A version that is already cached is skipped unless -Force is given. A provider with
        no docs entry is a terminating error that names Update-TerraformProviderDocCache,
        which harvests any registry provider's docs. For a private GitHub release source,
        set $env:GH_TOKEN (or $env:GITHUB_TOKEN), as for Get-TerraformSchemaPack.

    .PARAMETER Provider
        Providers to download, as for Get-TerraformSchemaPack: a name, namespace/name or
        full address; a bare name not in the manifest as written is matched by bare name; a
        wildcard resolves through the registry cache. Default: every docs entry.

    .PARAMETER Version
        Version to download. Default: the newest docs version in the manifest per provider.

    .PARAMETER Source
        Where manifest.json and the pack files are: an http(s) URL or a local directory.
        Default: https://github.com/JerryBalmer1/Graph.Emitter.Terraform/releases/latest/download.

    .PARAMETER Force
        Download and replace a version that is already cached.

    .PARAMETER PassThru
        Return one TerraformGraph.DocPack per provider.

    .EXAMPLE
        Get-TerraformDocPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere -PassThru

        Download three docs packs from the latest release.

    .EXAMPLE
        Get-TerraformDocPack -Provider vsphere -Source .\dist\schema-packs -PassThru

        Install a docs pack built locally with Invoke-Build BuildSchemaPack.

    .OUTPUTS
        None, or TerraformGraph.DocPack with -PassThru: ProviderAddress, Version, Path,
        Bytes, Status (Downloaded, Cached, or Updated). Default view is ProviderAddress,
        Version, Status, Bytes.

    .LINK
        Get-TerraformProviderDoc

    .LINK
        Update-TerraformProviderDocCache

    .LINK
        Get-TerraformSchemaPack
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string]
        $Source = $script:TerraformSchemaPackSource,

        [switch]
        $Force,

        [switch]
        $PassThru
    )

    Install-TerraformPack -Cmdlet $PSCmdlet -Kind Docs -Provider $Provider -Version $Version -Source $Source -Force:$Force -PassThru:$PassThru
}
