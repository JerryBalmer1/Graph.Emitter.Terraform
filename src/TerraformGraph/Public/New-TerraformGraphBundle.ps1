function New-TerraformGraphBundle {
    <#
    .SYNOPSIS
        Writes a bundle manifest for a provider set, resolved against the registry cache.

    .DESCRIPTION
        New-TerraformGraphBundle resolves a provider set against the registry cache: every
        provider in -Tier, plus every provider each -Provider pattern matches, less any an
        -Exclude pattern matches. Patterns match by shape and may use wildcards, as for
        Get-TerraformRegistryProvider -Name. It writes the manifest with the -Provider
        patterns expanded to full addresses, the -Exclude patterns as given (so a provider
        that appears in the registry later is still excluded), and one entry per provider: its latest version in the
        registry cache, the docs and schema versions in the local caches, the newest
        bundled classifier and when the docs were harvested. It never touches the network.

        Each of -Tier, -Provider and -Exclude that is not given is taken from the bundled
        manifest, so New-TerraformGraphBundle alone refreshes your copy of the bundled set.
        The registry cache used is registry.json in the output folder when there is one,
        else the usual registry cache (your own, else the bundled one). The output is
        sorted and has no timestamp of its own, so the same inputs give the same bytes.

    .PARAMETER Tier
        Registry tiers whose every provider is included: official, partner, community.
        Pass @() for none.

    .PARAMETER Provider
        Extra providers: 'vsphere', 'vmware/vsphere', a full address, or a wildcard. A
        pattern that matches nothing is a terminating error.

    .PARAMETER Exclude
        Providers to leave out, as patterns.

    .PARAMETER OutputPath
        File to write (a folder gets bundle.json). Default:
        $env:LOCALAPPDATA\TerraformGraph\bundle.json, which Get-TerraformGraphBundle reads
        before the bundled copy.

    .PARAMETER PassThru
        Return the written manifest as a TerraformGraph.Bundle.

    .EXAMPLE
        New-TerraformGraphBundle -PassThru

        Refresh your copy of the bundled set (official tier, azuredevops, vsphere) against
        the current registry cache and caches.

    .EXAMPLE
        New-TerraformGraphBundle -Tier @() -Provider hashicorp/azurerm, 'vmware/*' -Exclude vmware/wavefront -OutputPath .\bundle.json

        A bundle of azurerm and every vmware provider except wavefront.

    .OUTPUTS
        None, or TerraformGraph.Bundle with -PassThru.

    .LINK
        Get-TerraformGraphBundle

    .LINK
        Update-TerraformProviderDocCache
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('official', 'partner', 'community')]
        [AllowEmptyCollection()]
        [string[]]
        $Tier,

        [AllowEmptyCollection()]
        [string[]]
        $Provider,

        [AllowEmptyCollection()]
        [string[]]
        $Exclude,

        [string]
        $OutputPath = $script:TerraformGraphBundleUserPath,

        [switch]
        $PassThru
    )

    $defaults = $null
    $unbound = @('Tier', 'Provider', 'Exclude' | Where-Object { -not $PSBoundParameters.ContainsKey($_) })
    if ($unbound.Count -and (Test-Path -LiteralPath $script:TerraformGraphBundleBundledPath -PathType Leaf)) {
        $defaults = Read-TerraformGraphBundle -Path $script:TerraformGraphBundleBundledPath
    }
    $tiers = if ($PSBoundParameters.ContainsKey('Tier')) { [string[]]@($Tier) } elseif ($defaults) { $defaults['tiers'] } else { [string[]]@() }
    $patterns = if ($PSBoundParameters.ContainsKey('Provider')) { [string[]]@($Provider) } elseif ($defaults) { $defaults['providers'] } else { [string[]]@() }
    $excludes = if ($PSBoundParameters.ContainsKey('Exclude')) { [string[]]@($Exclude) } elseif ($defaults) { $defaults['exclude'] } else { [string[]]@() }

    $fullPath = [System.IO.Path]::GetFullPath($OutputPath, (Get-Location -PSProvider FileSystem).ProviderPath)
    if (Test-Path -LiteralPath $fullPath -PathType Container) { $fullPath = Join-Path $fullPath 'bundle.json' }

    try {
        $registry = Get-TerraformGraphBundleRegistry -BundlePath $fullPath
    }
    catch {
        Stop-TerraformGraphCommand -Id 'RegistryCacheNotFound' -Category ObjectNotFound -Target $fullPath -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
    }
    try {
        $selected = @(Resolve-TerraformGraphBundleProvider -Tier $tiers -Provider $patterns -Exclude $excludes -Cache $registry)
    }
    catch {
        # A missing bundle or registry cache keeps its own id (DECISIONS 50).
        if ((Get-TerraformGraphErrorId $_) -in 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
        Stop-TerraformGraphCommand -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $Provider -ExceptionType ([System.ArgumentException]) -Message ($_.Exception.Message)
    }

    $expanded = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pattern in $patterns) {
        foreach ($item in @(Select-TerraformRegistryProvider -Cache $registry -Name $pattern)) { $null = $expanded.Add($item.ProviderAddress) }
    }
    $entries = [object[]]@(New-TerraformGraphBundleEntry -RegistryProvider $selected)
    $document = [ordered]@{
        formatVersion = $script:TerraformGraphBundleFormatVersion
        tiers         = [object[]]@($script:TerraformGraphBundleTiers | Where-Object { $tiers -contains $_ })
        providers     = [object[]]@($expanded)
        exclude       = [object[]]@($excludes)
        registry      = [ordered]@{ harvestedOn = $registry.HarvestedOn; providerCount = @($registry.Providers).Count }
        sources       = [object[]]@(New-TerraformGraphBundleSource -Registry $registry -Entries $entries)
        entries       = $entries
    }
    Write-TerraformGraphTextFile -Path $fullPath -Text (Format-TerraformClassifierJson -Document $document)
    Write-Verbose "Wrote $($selected.Count) entries to $fullPath (registry cache $($registry.Path), harvested $($registry.HarvestedOn))"

    if ($PassThru) { ConvertTo-TerraformGraphBundleObject -Document (Read-TerraformGraphBundle -Path $fullPath) -Path $fullPath }
}
