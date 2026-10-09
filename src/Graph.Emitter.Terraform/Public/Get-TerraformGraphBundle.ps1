function Get-TerraformGraphBundle {
    <#
    .SYNOPSIS
        Gets the bundle manifest: the provider set the bundled data covers and what was harvested for each provider.

    .DESCRIPTION
        Get-TerraformGraphBundle reads a bundle manifest and returns one
        TerraformGraph.BundleEntry per provider, shown as a table. It never touches the
        network.

        A bundle manifest is JSON:
            { formatVersion, tiers, providers, exclude,
              registry: { harvestedOn, providerCount },
              sources: [ { kind, urls, relatedUrls, harvestedBy, lastPulled } ],
              entries: [ { provider, version, docsVersion, schemaVersion, classifierVersion,
                           harvestedOn } ] }
        sources names, for each kind of bundled data (registry, schemas, docs, classifiers,
        skills, and cmdb, reserved), the upstream endpoints it is pulled from, the pages
        that explain them, the command that pulls it and when it last was.
        tiers, providers (extra full addresses) and exclude define the provider set,
        resolved against the registry cache recorded in registry. Each entry records the
        provider's latest version in that registry cache, the docs and schema versions in
        the local caches, the newest bundled classifier, and when the docs were harvested.
        Test-TerraformGraphBundle checks the entries against those sources.

        The bundled manifest (data\bundle.json in the module) covers the official tier plus
        microsoft/azuredevops and vmware/vsphere. New-TerraformGraphBundle writes your own
        copy, which this command reads first.

    .PARAMETER Path
        Bundle file. Default: $env:LOCALAPPDATA\TerraformGraph\bundle.json when it exists,
        else the bundled data\bundle.json.

    .PARAMETER Document
        Return the whole manifest as one TerraformGraph.Bundle instead of its entries.

    .PARAMETER Sources
        Return the manifest's sources block as TerraformGraph.BundleSource rows instead of
        its entries.

    .EXAMPLE
        Get-TerraformGraphBundle

        The bundle entries as a table of ProviderAddress, Version, DocsVersion,
        SchemaVersion, ClassifierVersion, HarvestedOn.

    .EXAMPLE
        Get-TerraformGraphBundle -Sources | Format-List Kind, Urls, RelatedUrls, HarvestedBy, LastPulled

        Where each kind of bundled data comes from, which command pulls it and when it
        last did.

    .EXAMPLE
        Get-TerraformGraphBundle -Document | Select-Object Tiers, Providers, RegistryHarvestedOn, EntryCount

        The provider set and the registry cache it was resolved against.

    .OUTPUTS
        TerraformGraph.BundleEntry: ProviderAddress, Version, DocsVersion, SchemaVersion,
        ClassifierVersion, HarvestedOn. With -Document, TerraformGraph.Bundle: Path,
        FormatVersion, Tiers, Providers, Exclude, RegistryHarvestedOn,
        RegistryProviderCount, Sources, Entries, EntryCount, PackedEntryCount (entries with a
        schemaVersion: Invoke-Build BuildSchemaPack attaches a schema and a docs pack for exactly
        those), ClassifiedEntryCount, RegistryOnlyEntryCount (indexed from the registry only).
        With -Sources,
        TerraformGraph.BundleSource: Kind, Urls, RelatedUrls, HarvestedBy, LastPulled
        (default view Kind, HarvestedBy, LastPulled, Urls).

    .LINK
        New-TerraformGraphBundle

    .LINK
        Test-TerraformGraphBundle
    #>
    [CmdletBinding(DefaultParameterSetName = 'Entries')]
    param(
        [Parameter(Position = 0)]
        [Alias('BundlePath')]
        [string]
        $Path,

        [Parameter(Mandatory, ParameterSetName = 'Document')]
        [switch]
        $Document,

        [Parameter(Mandatory, ParameterSetName = 'Sources')]
        [switch]
        $Sources
    )

    try {
        $full = Resolve-TerraformGraphBundlePath -Path $Path
    }
    catch {
        Stop-TerraformGraphCommand -Id 'BundleNotFound' -Category ObjectNotFound -Target $Path -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
    }
    try {
        $bundle = Read-TerraformGraphBundle -Path $full
    }
    catch {
        Stop-TerraformGraphCommand -Id 'BundleInvalid' -Category InvalidData -Target $full -ExceptionType ([System.IO.InvalidDataException]) -Message ($_.Exception.Message)
    }
    $view = ConvertTo-TerraformGraphBundleObject -Document $bundle -Path $full
    if ($Document) { $view } elseif ($Sources) { $view.Sources } else { $view.Entries }
}
