function Get-TerraformProviderDoc {
    <#
    .SYNOPSIS
        Gets provider documentation pages from the docs cache, by provider, Id, type or pipeline node.

    .DESCRIPTION
        Get-TerraformProviderDoc reads the local docs cache, never the network. Each page
        is a TerraformGraph.ProviderDoc whose Id is the schema node Id it documents:
        <address>/resource/<type>, <address>/data/<type>, <address> for the overview,
        <address>/guide/<slug> for guides, <address>/unmatched/<category>/<slug> for pages
        whose type is not in the schema.

        By provider: -Provider patterns (wildcards, matched by shape as in
        Get-TerraformSchemaCache) select cached providers at -Version or their newest cached
        version; with no -Provider every cached provider is read. A pattern with no cached
        docs is a terminating error that names Get-TerraformDocPack and
        Update-TerraformProviderDocCache.

        By pipeline: pipe SchemaNode objects (looked up by Id) or ResourceNode objects
        (looked up by SchemaId). A nested Block or Attribute node returns the page of its
        resource or data source; a Provider or provider config node returns the overview.
        Each page is returned once per call however many nodes point to it, so a resource
        graph's nodes give exactly the pages a configuration uses. A provider with no cached
        docs gets one warning; terraform.io/builtin providers have no registry docs and are
        skipped.

        -Id, -Type and -Category filter either way.

    .PARAMETER Provider
        Cached providers to read: 'azurerm', 'azure*', 'hashicorp/azurerm' or a full
        address. Default: every provider in the docs cache.

    .PARAMETER Version
        Cached version to read. Default: the newest cached version of each provider.

    .PARAMETER Id
        Only pages whose Id matches one of these patterns (wildcards allowed), such as
        'registry.terraform.io/hashicorp/azurerm/resource/azurerm_virtual_network'.

    .PARAMETER Type
        Only resource and data source pages whose type matches one of these patterns, such
        as 'azurerm_virtual_*'.

    .PARAMETER Category
        Only these categories: resources, data-sources, guides, overview.

    .PARAMETER Examples
        Return only the ```hcl and ```terraform code blocks of each page: Content holds
        them joined by a blank line and ExampleCount says how many there were (0 leaves
        Content empty).

    .PARAMETER InputObject
        A TerraformGraph.SchemaNode or TerraformGraph.ResourceNode (or anything with a
        SchemaId or Id property, or an Id string). Accepts pipeline input.

    .EXAMPLE
        Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema |
            Select-Object -ExpandProperty Nodes | Get-TerraformProviderDoc

        The pages for every resource and data source type the configuration uses, once
        each, from the cache only.

    .EXAMPLE
        Get-TerraformProviderDoc -Provider azurerm -Type 'azurerm_virtual_*' -Examples

        The HCL examples of every azurerm resource and data source whose type starts with
        azurerm_virtual_.

    .EXAMPLE
        Get-TerraformProviderDoc -Provider vsphere -Category guides, overview

        The vsphere overview and guides.

    .EXAMPLE
        Get-TerraformProviderDoc -Provider vsphere -Id '*/unmatched/*'

        Pages the registry has for vsphere whose type is not in the cached schema.

    .OUTPUTS
        TerraformGraph.ProviderDoc: Id, ProviderAddress, Version, Category, Title,
        Subcategory, Slug, Type (resources and data sources only), Content (raw markdown, or
        the joined examples with -Examples), ExampleCount (with -Examples). Default view is
        Id, Category, Title, Subcategory.

    .LINK
        Update-TerraformProviderDocCache

    .LINK
        Get-TerraformDocPack

    .LINK
        ConvertTo-TerraformResourceGraph
    #>
    [CmdletBinding(DefaultParameterSetName = 'Provider')]
    param(
        [Parameter(ParameterSetName = 'Provider', Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string[]]
        $Id,

        [string[]]
        $Type,

        [ValidateSet('resources', 'data-sources', 'guides', 'overview')]
        [string[]]
        $Category,

        [switch]
        $Examples,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [object]
        $InputObject
    )

    begin {
        $emitted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $emit = {
            param($Doc)
            if ($Category -and $Category -notcontains $Doc.Category) { return }
            if ($Id) {
                $hit = $false
                foreach ($pattern in $Id) { if ($Doc.Id -like $pattern) { $hit = $true; break } }
                if (-not $hit) { return }
            }
            if ($Type) {
                if (-not $Doc.Type) { return }
                $hit = $false
                foreach ($pattern in $Type) { if ($Doc.Type -like $pattern) { $hit = $true; break } }
                if (-not $hit) { return }
            }
            if (-not $emitted.Add($Doc.Id)) { return }
            $out = $Doc.PSObject.Copy()
            if ($Examples) {
                $blocks = @(Get-TerraformDocExample -Content $Doc.Content)
                $out.Content = $blocks -join "`n`n"
                $out.ExampleCount = $blocks.Count
            }
            $out
        }

        # Piped input with no -Provider is pipeline mode even if begin still sees the default
        # parameter set, which happens before the first object is bound.
        $pipelineMode = $PSCmdlet.ParameterSetName -eq 'InputObject' -or ($MyInvocation.ExpectingInput -and -not $PSBoundParameters.ContainsKey('Provider'))
        if (-not $pipelineMode) {
            if ($Provider) {
                try {
                    $entries = @(Resolve-TerraformSchemaCacheProvider -Name $Provider -Version $Version -Kind Docs)
                }
                catch {
                    Stop-TerraformGraphCommand -Id 'ProviderDocNotCached' -Category ObjectNotFound -Target $Provider -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
                }
            }
            else {
                $all = @(Get-TerraformSchemaCacheEntry -Kind Docs)
                $entries = @(foreach ($group in @($all | Group-Object { $_.ProviderAddress.ToLowerInvariant() })) {
                        if ($Version) { $group.Group | Where-Object Version -eq $Version | Select-Object -First 1 }
                        else { $group.Group[0] }
                    })
                if (-not $entries.Count) {
                    $versionText = if ($Version) { " at version $Version" } else { '' }
                    Stop-TerraformGraphCommand -Id 'ProviderDocNotCached' -Category ObjectNotFound -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No provider docs are cached$versionText. Download a docs pack with Get-TerraformDocPack -Provider <name>, or harvest them from the registry with Update-TerraformProviderDocCache -Provider <name>."
                }
            }
            foreach ($entry in $entries) {
                Write-Verbose "Reading docs for $($entry.ProviderAddress) $($entry.Version) from $($entry.Path)"
                foreach ($doc in (Read-TerraformProviderDocFile -Path $entry.Path).Docs) { & $emit $doc }
            }
        }
        else {
            $cachedEntries = $null
            $loaded = @{}
        }
    }

    process {
        if (-not $pipelineMode -or $null -eq $InputObject) { return }

        $key = if ($InputObject -is [string]) { $InputObject }
        elseif ($InputObject.PSObject.Properties['SchemaId'] -and $InputObject.SchemaId) { [string]$InputObject.SchemaId }
        elseif ($InputObject.PSObject.Properties['Id']) { [string]$InputObject.Id }
        if (-not $key) {
            Write-Verbose 'Skipping an input object with no SchemaId or Id'
            return
        }
        $segments = $key.Split('/')
        if ($segments.Count -lt 3) {
            Write-Verbose "Skipping '$key': not a schema node Id"
            return
        }
        # Doc Ids carry the lowercase address, as provider_schemas keys do.
        $address = ($segments[0..2] -join '/').ToLowerInvariant()
        $key = $address + $key.Substring($address.Length)
        if ($segments[0] -eq 'terraform.io' -and $segments[1] -eq 'builtin') {
            Write-Verbose "Skipping '$key': built-in providers have no registry docs"
            return
        }

        if (-not $loaded.ContainsKey($address)) {
            if ($null -eq $cachedEntries) { $cachedEntries = @(Get-TerraformSchemaCacheEntry -Kind Docs) }
            $versions = @($cachedEntries | Where-Object { $_.ProviderAddress.ToLowerInvariant() -eq $address })
            $entry = if ($Version) { $versions | Where-Object Version -eq $Version | Select-Object -First 1 } else { $versions | Select-Object -First 1 }
            if ($entry) {
                Write-Verbose "Reading docs for $($entry.ProviderAddress) $($entry.Version) from $($entry.Path)"
                $loaded[$address] = Read-TerraformProviderDocFile -Path $entry.Path
            }
            else {
                $versionText = if ($Version) { " $Version" } else { '' }
                $providerSource = (ConvertTo-TerraformProviderAddress -Provider $address).Source
                Write-Warning "No cached docs for $address$versionText. Download a docs pack with Get-TerraformDocPack -Provider $providerSource, or harvest them with Update-TerraformProviderDocCache -Provider $providerSource."
                $loaded[$address] = $null
            }
        }
        $file = $loaded[$address]
        if (-not $file) { return }

        # Exact Id, else the resource or data source a nested node belongs to, else the
        # overview for the provider and its config nodes.
        $doc = $null
        $candidates = @($key)
        if ($segments.Count -ge 5 -and $segments[3] -in 'resource', 'data') { $candidates += "$address/$($segments[3])/$($segments[4])" }
        if ($segments.Count -gt 3 -and $segments[3] -eq 'config') { $candidates += $address }
        foreach ($candidate in $candidates) {
            if ($file.ById.TryGetValue($candidate, [ref]$doc)) { break }
        }
        if ($doc) { & $emit $doc } else { Write-Verbose "No doc for '$key'" }
    }
}
