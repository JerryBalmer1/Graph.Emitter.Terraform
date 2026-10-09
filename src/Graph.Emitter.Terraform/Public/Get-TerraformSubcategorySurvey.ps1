function Get-TerraformSubcategorySurvey {
    <#
    .SYNOPSIS
        Counts the doc subcategory labels each provider publishes: one row per provider and label.

    .DESCRIPTION
        Get-TerraformSubcategorySurvey reads the docs cache, never the network, and counts
        resource and data source pages by the subcategory label the registry publishes for
        them (the provider's own grouping, such as "Key Vault" or "Host and Cluster
        Management"). It returns one TerraformGraph.SubcategorySurveyRow per provider and
        label, sorted by provider address then label, and one NoSubcategory row per
        provider whose pages have an empty label. It is the evidence for the drawer list in
        classifiers\drawers.json: a label many providers share is a candidate drawer.

        -BundlePath surveys the bundle's provider set at each provider's latest version in
        its registry cache (else the newest cached docs); providers with no cached docs
        are left out with one warning and listed under missing in the output file.
        -Provider surveys cached providers by pattern instead.

        -OutputPath writes the survey as JSON with its provenance: the bundle's provider
        set and registry cache, each provider's docs version, harvest time and schema
        version, every label with the number of providers using it, and the rows. The file
        has no timestamp of its own and is sorted, so the same caches give the same bytes.

    .PARAMETER BundlePath
        Bundle file. Default: as for Get-TerraformGraphBundle.

    .PARAMETER Provider
        Cached providers to survey instead of a bundle; patterns as for
        Get-TerraformDocCache.

    .PARAMETER Version
        Docs version with -Provider. Default: the newest cached.

    .PARAMETER OutputPath
        JSON file to write (a folder gets subcategories.json). Rows are then returned only
        with -PassThru.

    .PARAMETER PassThru
        With -OutputPath, also return the rows.

    .EXAMPLE
        Get-TerraformSubcategorySurvey -Provider vsphere

        vsphere's labels with their resource and data source page counts.

    .EXAMPLE
        Get-TerraformSubcategorySurvey -OutputPath .\dist\survey\subcategories.json

        Survey the bundle's providers and write the file Invoke-Build HarvestBundleDocs
        writes.

    .EXAMPLE
        Get-TerraformSubcategorySurvey | Group-Object Subcategory | Sort-Object Count -Descending | Select-Object -First 20 Name, Count

        The labels the most bundle providers share.

    .OUTPUTS
        TerraformGraph.SubcategorySurveyRow: ProviderAddress, Version, Subcategory (empty on
        the NoSubcategory row), ResourceCount, DataSourceCount, Status (Labeled or
        NoSubcategory). Default view is ProviderAddress, Subcategory, ResourceCount,
        DataSourceCount, Status.

    .LINK
        Update-TerraformProviderDocCache

    .LINK
        New-TerraformClassifier
    #>
    [CmdletBinding(DefaultParameterSetName = 'Bundle')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Bundle')]
        [string]
        $BundlePath,

        [Parameter(Mandatory, ParameterSetName = 'Provider')]
        [string[]]
        $Provider,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $Version,

        [string]
        $OutputPath,

        [switch]
        $PassThru
    )

    $targets = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[object]]::new()
    $bundleInfo = $null
    if ($PSCmdlet.ParameterSetName -eq 'Bundle') {
        try {
            $full = Resolve-TerraformGraphBundlePath -Path $BundlePath
            $bundle = Read-TerraformGraphBundle -Path $full
            $registry = Get-TerraformGraphBundleRegistry -BundlePath $full
            $selected = @(Resolve-TerraformGraphBundleProvider -Tier $bundle['tiers'] -Provider $bundle['providers'] -Exclude $bundle['exclude'] -Cache $registry)
        }
        catch {
            # A missing bundle or registry cache keeps its own id (DECISIONS 50).
            if ((Get-TerraformGraphErrorId $_) -in 'BundleNotFound', 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
            Stop-TerraformGraphCommand -Id 'BundleInvalid' -Category InvalidData -Target $BundlePath -ExceptionType ([System.IO.InvalidDataException]) -Message ($_.Exception.Message)
        }
        $cached = @(Get-TerraformSchemaCacheEntry -Kind Docs)
        foreach ($item in $selected) {
            $mine = @($cached | Where-Object ProviderAddress -eq $item.ProviderAddress)
            $entry = $mine | Where-Object Version -eq ([string]$item.Latest) | Select-Object -First 1
            if (-not $entry -and $mine.Count) {
                $entry = $mine[0]
                Write-Verbose "No cached docs for $($item.ProviderAddress) $($item.Latest); surveying the cached $($entry.Version)"
            }
            if ($entry) { $targets.Add($entry) }
            else { $missing.Add([ordered]@{ provider = $item.ProviderAddress; version = [string]$item.Latest; reason = 'no cached docs' }) }
        }
        if ($missing.Count) {
            Write-Warning "No cached docs for $($missing.Count) of $($selected.Count) providers in the bundle, so the survey leaves them out: $(@($missing | ForEach-Object { $_.provider }) -join ', '). Run Update-TerraformProviderDocCache -BundlePath $full -Resume."
        }
        $bundleInfo = [ordered]@{
            formatVersion = $bundle['formatVersion']
            tiers         = [object[]]$bundle['tiers']
            providers     = [object[]]$bundle['providers']
            exclude       = [object[]]$bundle['exclude']
            registry      = [ordered]@{ harvestedOn = $registry.HarvestedOn; providerCount = @($registry.Providers).Count }
        }
    }
    else {
        try {
            foreach ($entry in @(Resolve-TerraformSchemaCacheProvider -Name $Provider -Version $Version -Kind Docs)) { $targets.Add($entry) }
        }
        catch {
            Stop-TerraformGraphCommand -Id 'ProviderDocNotCached' -Category ObjectNotFound -Target $Provider -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $providers = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($targets | Sort-Object { $_.ProviderAddress } -Culture '')) {
        Write-Verbose "Surveying $($entry.ProviderAddress) $($entry.Version) from $($entry.Path)"
        $document = Read-TerraformSchemaCache -Path $entry.Path
        $counts = [System.Collections.Generic.Dictionary[string, int[]]]::new([System.StringComparer]::Ordinal)
        $none = [int[]]@(0, 0)
        foreach ($doc in @($document['docs'])) {
            $slot = switch ([string]$doc['category']) { 'resources' { 0 } 'data-sources' { 1 } default { -1 } }
            if ($slot -lt 0) { continue }
            $label = [string]$doc['subcategory']
            if ([string]::IsNullOrWhiteSpace($label)) { $none[$slot]++; continue }
            if (-not $counts.ContainsKey($label)) { $counts[$label] = [int[]]@(0, 0) }
            $counts[$label][$slot]++
        }
        $labels = [System.Collections.Generic.List[string]]::new()
        foreach ($label in $counts.Keys) { $labels.Add($label) }
        $labels.Sort([System.Comparison[string]] {
                param($a, $b)
                $byText = [string]::Compare($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
                if ($byText) { return $byText }
                [string]::CompareOrdinal($a, $b)
            })
        $resourceTotal = $none[0]
        $dataTotal = $none[1]
        foreach ($label in $labels) {
            $resourceTotal += $counts[$label][0]
            $dataTotal += $counts[$label][1]
            $rows.Add([pscustomobject]@{
                PSTypeName      = 'TerraformGraph.SubcategorySurveyRow'
                ProviderAddress = $entry.ProviderAddress
                Version         = $entry.Version
                Subcategory     = $label
                ResourceCount   = $counts[$label][0]
                DataSourceCount = $counts[$label][1]
                Status          = 'Labeled'
            })
        }
        if ($none[0] + $none[1]) {
            $rows.Add([pscustomobject]@{
                PSTypeName      = 'TerraformGraph.SubcategorySurveyRow'
                ProviderAddress = $entry.ProviderAddress
                Version         = $entry.Version
                Subcategory     = $null
                ResourceCount   = $none[0]
                DataSourceCount = $none[1]
                Status          = 'NoSubcategory'
            })
        }
        $providers.Add([ordered]@{
            provider        = $entry.ProviderAddress
            version         = $entry.Version
            harvestedOn     = $document['harvestedOn']
            schemaVersion   = $document['schemaVersion']
            pageCount       = $document['docCount']
            resourceCount   = $resourceTotal
            dataSourceCount = $dataTotal
            labelCount      = $labels.Count
        })
    }

    if ($OutputPath) {
        # Labels across providers, matched ignoring case as map rows are; each is shown in the
        # spelling most providers use (ties: ordinal order).
        $byLabel = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $noLabel = @{ Providers = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal); Resource = 0; Data = 0 }
        foreach ($row in $rows) {
            if ($row.Status -eq 'NoSubcategory') {
                $null = $noLabel.Providers.Add($row.ProviderAddress)
                $noLabel.Resource += $row.ResourceCount
                $noLabel.Data += $row.DataSourceCount
                continue
            }
            $group = $null
            if (-not $byLabel.TryGetValue($row.Subcategory, [ref]$group)) {
                $group = @{
                    Spellings = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
                    Providers = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
                    Resource  = 0
                    Data      = 0
                }
                $byLabel[$row.Subcategory] = $group
            }
            $group.Spellings[$row.Subcategory] = 1 + $(if ($group.Spellings.ContainsKey($row.Subcategory)) { $group.Spellings[$row.Subcategory] } else { 0 })
            $null = $group.Providers.Add($row.ProviderAddress)
            $group.Resource += $row.ResourceCount
            $group.Data += $row.DataSourceCount
        }
        $labelList = [System.Collections.Generic.List[object]]::new()
        foreach ($group in $byLabel.Values) {
            $spelling = @($group.Spellings.Keys | Sort-Object -Property @{ Expression = { $group.Spellings[$_] }; Descending = $true }, @{ Expression = { $_ }; Descending = $false } -Culture '')[0]
            $labelList.Add([pscustomobject]@{ Label = $spelling; Group = $group })
        }
        $labelList.Sort([System.Comparison[object]] {
                param($a, $b)
                $byProviders = $b.Group.Providers.Count.CompareTo($a.Group.Providers.Count)
                if ($byProviders) { return $byProviders }
                $byText = [string]::Compare($a.Label, $b.Label, [System.StringComparison]::OrdinalIgnoreCase)
                if ($byText) { return $byText }
                [string]::CompareOrdinal($a.Label, $b.Label)
            })

        $document = [ordered]@{
            formatVersion = 1
            source        = 'docs cache: resources and data-sources pages counted by the subcategory label the registry publishes'
            bundle        = $bundleInfo
            summary       = [ordered]@{
                providerCount              = $providers.Count
                missingCount               = $missing.Count
                labelCount                 = $labelList.Count
                rowCount                   = $rows.Count
                noSubcategoryProviderCount = $noLabel.Providers.Count
            }
            providers     = [object[]]$providers.ToArray()
            missing       = [object[]]$missing.ToArray()
            labels        = [object[]]@(foreach ($item in $labelList) {
                    [ordered]@{
                        subcategory     = $item.Label
                        providerCount   = $item.Group.Providers.Count
                        resourceCount   = $item.Group.Resource
                        dataSourceCount = $item.Group.Data
                        providers       = [object[]]@($item.Group.Providers)
                    }
                })
            noSubcategory = [ordered]@{
                providerCount   = $noLabel.Providers.Count
                resourceCount   = $noLabel.Resource
                dataSourceCount = $noLabel.Data
                providers       = [object[]]@($noLabel.Providers)
            }
            rows          = [object[]]@(foreach ($row in $rows) {
                    [ordered]@{
                        provider        = $row.ProviderAddress
                        version         = $row.Version
                        subcategory     = $row.Subcategory
                        resourceCount   = $row.ResourceCount
                        dataSourceCount = $row.DataSourceCount
                        status          = $row.Status
                    }
                })
        }
        $fullPath = [System.IO.Path]::GetFullPath($OutputPath, (Get-Location -PSProvider FileSystem).ProviderPath)
        if ((Test-Path -LiteralPath $fullPath -PathType Container) -or -not [System.IO.Path]::GetExtension($fullPath)) { $fullPath = Join-Path $fullPath 'subcategories.json' }
        Write-TerraformGraphTextFile -Path $fullPath -Text (Format-TerraformClassifierJson -Document $document)
        Write-Verbose "Wrote $($rows.Count) rows, $($labelList.Count) labels across $($providers.Count) providers to $fullPath"
        if (-not $PassThru) { return }
    }
    foreach ($row in $rows) { $row }
}
