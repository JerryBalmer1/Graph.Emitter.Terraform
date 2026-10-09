function Get-TerraformSchemaPack {
    <#
    .SYNOPSIS
        Downloads provider schema packs into the local schema cache.

    .DESCRIPTION
        Get-TerraformSchemaPack fills the local schema cache from a pack source instead of
        running terraform. A pack source holds manifest.json and one gzipped schema file per
        provider version; packs built for each module release are attached to its GitHub
        release, which is the default -Source.

        It reads manifest.json, picks the entry for each provider (at -Version, or the
        newest version in the manifest), downloads the file, checks its sha256 against the
        manifest and only then moves it into the cache at
        $env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz. A file
        whose hash does not match is a terminating error and nothing is written.

        A version that is already cached is skipped unless -Force is given. Every provider
        is checked against the manifest before anything is downloaded; one that has no
        entry is a terminating error that names Get-TerraformProviderSchema -SaveToCache,
        which harvests any provider locally.

        Once cached, ConvertTo-TerraformSchemaGraph -Provider and
        ConvertTo-TerraformResourceGraph -Provider or -AutoSchema read the schema with no
        terraform and no network.

        Only manifest entries with kind schema (or no kind, as manifests before 0.11.0
        wrote them) are considered; docs entries are for Get-TerraformDocPack.

        For a GitHub release -Source, set $env:GH_TOKEN (or $env:GITHUB_TOKEN) when the
        repository is private: the files are then fetched through the GitHub releases API
        with that token, since the plain releases/.../download URL is 404 for a private
        repository. Without a token the anonymous URL is used.

    .PARAMETER Provider
        Providers to download: 'azurerm', 'hashicorp/azurerm', or
        'registry.terraform.io/hashicorp/azurerm'. A name that is not in the manifest as
        written is also matched against the manifest by bare name, so 'azuredevops' finds
        microsoft/azuredevops. A value with a wildcard is resolved against the provider
        registry cache first and must match exactly one provider (see
        Get-TerraformRegistryProvider). Default: every provider in the manifest.

    .PARAMETER Version
        Version to download, such as 4.40.0. Default: the newest version in the manifest
        for each provider.

    .PARAMETER Source
        Where manifest.json and the pack files are: an http(s) URL, or a local directory
        such as the dist\schema-packs folder Invoke-Build BuildSchemaPack writes. Default:
        https://github.com/JerryBalmer1/Graph.Emitter.Terraform/releases/latest/download. A
        https://github.com/<owner>/<repo>/releases/download/<tag> URL names one release.

    .PARAMETER Force
        Download and replace a version that is already cached.

    .PARAMETER PassThru
        Return one TerraformGraph.SchemaPack per provider.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere -PassThru

        Download three packs from the latest release and show where they were cached.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider vsphere -Source .\dist\schema-packs -PassThru

        Install a pack built locally with Invoke-Build BuildSchemaPack.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider 'hashicorp/azure*' -Force

        Resolve the wildcard through the registry cache, then download that provider's
        pack again even though it is cached.

    .OUTPUTS
        None, or TerraformGraph.SchemaPack with -PassThru: ProviderAddress, Version, Path,
        Bytes, Status (Downloaded, Cached, or Updated). Default view is ProviderAddress,
        Version, Status, Bytes.

    .NOTES
        Status: Downloaded when the version was not cached before; Cached when it was and
        nothing was downloaded; Updated when -Force replaced a cached file.

    .LINK
        Get-TerraformSchemaCache

    .LINK
        Get-TerraformProviderSchema
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

    Install-TerraformPack -Cmdlet $PSCmdlet -Kind Schema -Provider $Provider -Version $Version -Source $Source -Force:$Force -PassThru:$PassThru
}
