function Test-TerraformGraphBundle {
    <#
    .SYNOPSIS
        Checks the bundle manifest and the bundled data against their sources: Fresh, Stale or Missing per item.

    .DESCRIPTION
        Test-TerraformGraphBundle returns one TerraformGraph.BundleCheck (Item, Status,
        Detail, RecommendedAction, InspectAction) per thing it checks. Status is Fresh,
        Stale (the source moved on) or Missing (something the bundle records is not there).
        Every row that is not Fresh carries two pasteable commands: RecommendedAction
        promotes the data (an Invoke-Build task such as BuildRegistry, BuildSchemaPack
        -Provider, BuildClassifier -Provider or HarvestBundleDocs -Resume for the bundled
        manifest; Update-TerraformProviderDocCache, New-TerraformGraphBundle and the other
        commands for your own copy), and InspectAction shows what that would change first,
        writing only to $env:TEMP\TerraformGraph-inspect or the user caches, never to the
        module's src folder. Fresh rows have neither. Offline unless -Online.

        -Scope says what is certified (DECISIONS 51). Machine (the default) checks the
        bundle against this machine's caches too: the user registry cache when no
        registry.json sits beside the bundle, and the docs and schema caches. Repo reads
        only the bundle's own folder, the module's bundled classifiers and map.json, and
        -DistPath: no user cache, so the rows are the same on every machine with the same
        checkout and dist folder. Invoke-Build CheckBundle (the release gate) uses -Scope
        Repo -Strict. Rows:
            registry               bundle registry.harvestedOn and providerCount against the
                                   registry cache it resolves against (registry.json beside
                                   the bundle, else, with -Scope Machine, the usual cache)
            sources                the bundle has a sources block, and it is what a refresh
                                   would write now
            entry <address>        the entry is in the bundle's provider set, and its version
                                   is the registry cache's latest; every provider in the set
                                   has an entry
            docs <address>         -Scope Machine only: docsVersion is in the docs cache,
                                   equals the entry version, and harvestedOn matches the
                                   cached file
            schema <address>       -Scope Machine only, when the entry has a schemaVersion:
                                   it is in the schema cache and equals the entry version
            classifier <address>   when the entry has a classifierVersion: that bundled
                                   classifier exists and equals the entry version
            mapVersion <address> <version>
                                   each bundled classifier's mapVersion against map.json
            pack <kind> <address> <version>
                                   when -DistPath holds manifest.json: each pack file's
                                   sha256, and its version against the entry's schemaVersion
                                   or docsVersion; an entry with a schemaVersion and no
                                   schema pack is Missing
        -Online adds the live registry's provider count and each entry's latest version on
        registry.terraform.io (one request per entry).

        -Strict writes every row, then throws a terminating error (BundleNotFresh) when any
        row is Stale or Missing. Invoke-Build CheckBundle runs it with -Strict before a
        release.

    .PARAMETER BundlePath
        Bundle file. Default: as for Get-TerraformGraphBundle.

    .PARAMETER DistPath
        Folder of built packs to check when it holds manifest.json. Default:
        dist\schema-packs under the current folder.

    .PARAMETER Scope
        Machine (default): the bundle against this machine's caches as well. Repo: only the
        bundle's folder, the bundled classifiers and -DistPath, never a user cache.

    .PARAMETER Online
        Also compare against the live registry.

    .PARAMETER Strict
        Throw when any row is Stale or Missing.

    .EXAMPLE
        Test-TerraformGraphBundle | Where-Object Status -ne Fresh

        What is out of date, offline.

    .EXAMPLE
        Test-TerraformGraphBundle -BundlePath .\src\Graph.Emitter.Terraform\data\bundle.json -Online -Strict

        The release gate, including the live registry.

    .EXAMPLE
        Test-TerraformGraphBundle | Where-Object Status -ne Fresh | Format-List Item, Detail, InspectAction, RecommendedAction

        Each stale item with the command that shows the change and the one that makes it.

    .OUTPUTS
        TerraformGraph.BundleCheck: Item, Status (Fresh, Stale, Missing), Detail,
        RecommendedAction, InspectAction. Default view is Item, Status, RecommendedAction.

    .LINK
        Get-TerraformGraphBundle

    .LINK
        New-TerraformGraphBundle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]
        $BundlePath,

        [string]
        $DistPath = (Join-Path (Get-Location -PSProvider FileSystem).ProviderPath 'dist' 'schema-packs'),

        [ValidateSet('Machine', 'Repo')]
        [string]
        $Scope = 'Machine',

        [switch]
        $Online,

        [switch]
        $Strict
    )

    try {
        $full = Resolve-TerraformGraphBundlePath -Path $BundlePath
        $bundle = Read-TerraformGraphBundle -Path $full
    }
    catch {
        # A missing bundle or registry cache keeps its own id (DECISIONS 50).
        if ((Get-TerraformGraphErrorId $_) -in 'BundleNotFound', 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
        Stop-TerraformGraphCommand -Id 'BundleInvalid' -Category InvalidData -Target $BundlePath -ExceptionType ([System.IO.InvalidDataException]) -Message ($_.Exception.Message)
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    # Every row that is not Fresh carries two pasteable commands: RecommendedAction promotes
    # the data (through an Invoke-Build task for the bundled manifest, else into the user's own
    # files) and InspectAction shows what that would change first, writing only under
    # $env:TEMP\TerraformGraph-inspect or the user caches, never src\.
    $add = {
        param([string]$Item, [string]$Status, [string]$Detail, [string]$Recommended, [string]$Inspect)
        $fresh = $Status -eq 'Fresh'
        $rows.Add([pscustomobject]@{
                PSTypeName        = 'TerraformGraph.BundleCheck'
                Item              = $Item
                Status            = $Status
                Detail            = $Detail
                RecommendedAction = if ($fresh) { $null } else { $Recommended }
                InspectAction     = if ($fresh) { $null } else { $Inspect }
            })
    }
    $refresh = "Rerun New-TerraformGraphBundle -OutputPath $full (Invoke-Build HarvestBundleDocs refreshes the bundled one)."
    $quote = { param([string]$Value) "'$($Value.Replace("'", "''"))'" }
    $list = { param([string[]]$Value) if ($Value.Count) { @($Value | ForEach-Object { & $quote $_ }) -join ',' } else { '@()' } }
    $bundled = [string]::Equals($full, [System.IO.Path]::GetFullPath($script:TerraformGraphBundleBundledPath), [System.StringComparison]::OrdinalIgnoreCase)
    $inspectDir = '$env:TEMP\TerraformGraph-inspect'
    $freshInspectDir = "Remove-Item -LiteralPath `"$inspectDir`" -Recurse -Force -ErrorAction Ignore; `$null = New-Item -ItemType Directory -Path `"$inspectDir`""
    $newBundle = "New-TerraformGraphBundle -Tier $(& $list $bundle['tiers']) -Provider $(& $list $bundle['providers']) -Exclude $(& $list $bundle['exclude'])"
    $besideRegistry = Join-Path (Split-Path -Path $full -Parent) 'registry.json'
    $refreshAction = if ($bundled) { 'Invoke-Build HarvestBundleDocs -Resume' } else { "$newBundle -OutputPath $(& $quote $full)" }
    $copyRegistry = if (Test-Path -LiteralPath $besideRegistry -PathType Leaf) { 'Copy-Item -LiteralPath ' + (& $quote $besideRegistry) + ' -Destination "' + $inspectDir + '"; ' } else { '' }
    $refreshInspect = "$freshInspectDir; $copyRegistry$newBundle -OutputPath `"$inspectDir\bundle.json`"; git diff --no-index -- $(& $quote $full) `"$inspectDir\bundle.json`""
    $registryAction = if ($bundled) { 'Invoke-Build BuildRegistry' } else { 'Update-TerraformRegistryCache' }
    $registryInspect = "$freshInspectDir; Update-TerraformRegistryCache -Path `"$inspectDir\registry.json`" -PassThru"
    $entries = [ordered]@{}
    foreach ($entry in $bundle['entries']) { $entries[[string]$entry['provider']] = $entry }
    $schemaProviders = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($address in $entries.Keys) { if ($entries[$address]['schemaVersion']) { $null = $schemaProviders.Add($address) } }
    $buildSchemaPack = { param([string]$Address) $set = [System.Collections.Generic.SortedSet[string]]::new($schemaProviders, [System.StringComparer]::Ordinal); $null = $set.Add($Address); "Invoke-Build BuildSchemaPack -Provider $(@($set) -join ',')" }
    $classifierInspect = {
        param([string]$Address, [string]$ClassifierVersion, [string]$BundledFile)
        $file = "$($Address.ToLowerInvariant().Replace('/', '-')).$ClassifierVersion.json"
        $text = "$freshInspectDir; New-TerraformClassifier -Provider $(& $quote $Address) -Version $(& $quote $ClassifierVersion) -OutputPath `"$inspectDir`" -PassThru"
        if ($BundledFile) { $text += "; git diff --no-index -- $(& $quote $BundledFile) `"$inspectDir\$file`"" }
        $text
    }

    $repoScope = $Scope -eq 'Repo'

    # Built packs, read up front: the docs rows recommend Get-TerraformDocPack only for a
    # provider that has a docs pack.
    $manifestPath = if ($DistPath) { Join-Path $DistPath 'manifest.json' } else { $null }
    $manifest = if ($manifestPath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Read-TerraformClassifierJson -Path $manifestPath } else { $null }
    $docsPacks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($manifest) {
        foreach ($pack in @($manifest['packs'])) { if ([string]$pack['kind'] -eq 'docs') { $null = $docsPacks.Add("$($pack['address'])|$($pack['version'])") } }
    }

    # Registry cache.
    $registry = $null
    if ($repoScope) {
        if (Test-Path -LiteralPath $besideRegistry -PathType Leaf) {
            $registry = Read-TerraformRegistryCacheFile -Path $besideRegistry
        }
        else {
            & $add 'registry' 'Missing' "-Scope Repo reads only the registry.json beside the bundle, and $besideRegistry does not exist. Write it with Update-TerraformRegistryCache -Path $(& $quote $besideRegistry) (Invoke-Build BuildRegistry for the bundled one)." $registryAction $registryInspect
        }
    }
    else {
        try {
            $registry = Get-TerraformGraphBundleRegistry -BundlePath $full
        }
        catch {
            & $add 'registry' 'Missing' $_.Exception.Message $registryAction $registryInspect
        }
    }
    if ($registry) {
        $recorded = $bundle['registry']
        $count = @($registry.Providers).Count
        if ($recorded -isnot [System.Collections.IDictionary]) {
            & $add 'registry' 'Missing' "The bundle has no registry block. $refresh" $refreshAction $refreshInspect
        }
        elseif ([string]$recorded['harvestedOn'] -ne $registry.HarvestedOn -or [int]$recorded['providerCount'] -ne $count) {
            & $add 'registry' 'Stale' "The bundle was resolved against a registry cache harvested $($recorded['harvestedOn']) ($($recorded['providerCount']) providers); $($registry.Path) was harvested $($registry.HarvestedOn) ($count providers). $refresh" $refreshAction $refreshInspect
        }
        else {
            & $add 'registry' 'Fresh' "Harvested $($registry.HarvestedOn), $count providers ($($registry.Path))."
        }
        if ($Online) {
            $filter = if ($registry.Scope -eq 'all') { '' } else { "&filter[tier]=$($registry.Scope)" }
            $probe = "https://$($script:TerraformRegistrySource)/v2/providers?page[size]=1&page[number]=1$filter"
            try {
                $live = Invoke-TerraformRegistryRequest -Uri $probe
                $liveCount = [int]$live.meta.pagination.'total-count'
                if ($liveCount -ne $count) {
                    & $add 'registry (online)' 'Stale' "$($script:TerraformRegistrySource) lists $liveCount $($registry.Scope) providers; the registry cache has $count. Run Invoke-Build BuildRegistry (or Update-TerraformRegistryCache)." $registryAction "$registryInspect; git diff --no-index --stat -- $(& $quote $registry.Path) `"$inspectDir\registry.json`""
                }
                else {
                    & $add 'registry (online)' 'Fresh' "$($script:TerraformRegistrySource) lists $liveCount $($registry.Scope) providers, as cached."
                }
            }
            catch {
                & $add 'registry (online)' 'Missing' "Could not reach $($script:TerraformRegistrySource): $($_.Exception.Message)" "Test-TerraformGraphBundle -BundlePath $(& $quote $full) -Online" "Invoke-RestMethod -Uri $(& $quote $probe) | Select-Object -ExpandProperty meta"
            }
        }
    }

    # Sources: what a refresh would write, against what the bundle records.
    $recordedSources = $bundle['sources']
    if ($recordedSources -isnot [System.Collections.IList] -or -not $recordedSources.Count) {
        & $add 'sources' 'Missing' "The bundle names no sources. $refresh" $refreshAction $refreshInspect
    }
    elseif ($registry) {
        $expectedSources = [object[]]@(New-TerraformGraphBundleSource -Registry $registry -Entries @($bundle['entries']) -NoSchemaCache:$repoScope)
        if ($repoScope) {
            # The schemas lastPulled is a schema cache file time: machine data, so not checked.
            $recordedSchemas = @($recordedSources | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['kind'] -eq 'schemas' }) | Select-Object -First 1
            foreach ($source in $expectedSources) { if ($source['kind'] -eq 'schemas') { $source['lastPulled'] = if ($recordedSchemas) { $recordedSchemas['lastPulled'] } else { $null } } }
        }
        $expected = [TerraformGraph.Json]::Serialize($expectedSources, 64, $true)
        if ([TerraformGraph.Json]::Serialize($recordedSources, 64, $true) -cne $expected) {
            & $add 'sources' 'Stale' "The bundle's sources (urls or lastPulled) differ from what the caches give now. $refresh" $refreshAction $refreshInspect
        }
        else {
            & $add 'sources' 'Fresh' "$($recordedSources.Count) sources: $(@($recordedSources | ForEach-Object { $_['kind'] }) -join ', ')."
        }
    }

    # Entries against the provider set and the caches.
    $selected = @{}
    if ($registry) {
        try {
            foreach ($item in @(Resolve-TerraformGraphBundleProvider -Tier $bundle['tiers'] -Provider $bundle['providers'] -Exclude $bundle['exclude'] -Cache $registry)) {
                $selected[$item.ProviderAddress] = $item
            }
        }
        catch {
            & $add 'provider set' 'Stale' $_.Exception.Message "$registryAction; $refreshAction" "Get-TerraformGraphBundle -Path $(& $quote $full) -Document | Format-List Tiers, Providers, Exclude, RegistryHarvestedOn"
        }
    }
    foreach ($address in @($selected.Keys | Sort-Object -Culture '')) {
        if (-not $entries.Contains($address)) { & $add "entry $address" 'Missing' "In the bundle's provider set but has no entry. $refresh" $refreshAction $refreshInspect }
    }

    $docs = if ($repoScope) { @() } else { @(Get-TerraformSchemaCacheEntry -Kind Docs) }
    $schemas = if ($repoScope) { @() } else { @(Get-TerraformSchemaCacheEntry) }
    $classifiers = @(Get-TerraformGraphBundleClassifierEntry)
    $harvest = "Update-TerraformProviderDocCache -BundlePath $full -Resume"
    foreach ($address in $entries.Keys) {
        $entry = $entries[$address]
        $version = [string]$entry['version']
        $registryProvider = $selected[$address]
        $docsInspect = "Get-TerraformDocCache -Provider $(& $quote $address) | Format-Table ProviderAddress, Version, DocCount, HarvestedOn"
        if ($registry -and -not $registryProvider) {
            & $add "entry $address" 'Stale' "Not in the bundle's provider set (tiers, providers, exclude). $refresh" $refreshAction $refreshInspect
        }
        elseif ($registryProvider -and $version -ne [string]$registryProvider.Latest) {
            & $add "entry $address" 'Stale' "Version $version; the registry cache's latest is $($registryProvider.Latest). $refresh" "Update-TerraformProviderDocCache -Provider $address -Version $($registryProvider.Latest); $refreshAction" $refreshInspect
        }
        else {
            & $add "entry $address" 'Fresh' "Version $version."
        }

        $docsVersion = [string]$entry['docsVersion']
        $cachedDoc = $docs | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $docsVersion } | Select-Object -First 1
        $docsAction = "Update-TerraformProviderDocCache -Provider $address -Version $version; $refreshAction"
        # Get-TerraformDocPack can only help when a docs pack exists for this version.
        $docPackHint = if ($docsPacks.Contains("$address|$docsVersion")) { ", or Get-TerraformDocPack -Provider $address -Version $docsVersion" } else { '' }
        if ($repoScope) {
            # Docs live in the user cache: nothing in the repo to check.
        }
        elseif (-not $docsVersion) {
            & $add "docs $address" 'Missing' "No docs were harvested. Run $harvest, then refresh the bundle." $docsAction $docsInspect
        }
        elseif (-not $cachedDoc) {
            & $add "docs $address" 'Missing' "Docs $docsVersion are not in the docs cache. Run $harvest$docPackHint." $docsAction $docsInspect
        }
        elseif ($docsVersion -ne $version) {
            & $add "docs $address" 'Stale' "Docs $docsVersion; the entry version is $version. Run $harvest, then refresh the bundle." $docsAction $docsInspect
        }
        elseif ([string]$cachedDoc.HarvestedOn -ne [string]$entry['harvestedOn']) {
            & $add "docs $address" 'Stale' "The docs cache was harvested $($cachedDoc.HarvestedOn); the entry records $($entry['harvestedOn']). $refresh" $refreshAction $refreshInspect
        }
        else {
            & $add "docs $address" 'Fresh' "Docs $docsVersion, $($cachedDoc.DocCount) pages, harvested $($cachedDoc.HarvestedOn)."
        }

        $schemaVersion = [string]$entry['schemaVersion']
        if ($schemaVersion -and -not $repoScope) {
            $schemaInspect = "Get-TerraformSchemaCache -Provider $(& $quote $address)"
            if (-not ($schemas | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $schemaVersion })) {
                $action = if ($bundled) { & $buildSchemaPack $address } else { "Get-TerraformSchemaPack -Provider $address -Version $schemaVersion" }
                & $add "schema $address" 'Missing' "Schema $schemaVersion is not in the schema cache. Run Get-TerraformSchemaPack -Provider $address -Version $schemaVersion, or Invoke-Build BuildSchemaPack." $action $schemaInspect
            }
            elseif ($schemaVersion -ne $version) {
                $action = if ($bundled) { "$(& $buildSchemaPack $address); $refreshAction" } else { "Get-TerraformProviderSchema -Provider $address -Version '= $version' -SaveToCache; $refreshAction" }
                & $add "schema $address" 'Stale' "Schema $schemaVersion; the entry version is $version. Run Invoke-Build BuildSchemaPack." $action $schemaInspect
            }
            else {
                & $add "schema $address" 'Fresh' "Schema $schemaVersion is cached."
            }
        }

        $classifierVersion = [string]$entry['classifierVersion']
        if ($classifierVersion) {
            $bundledClassifier = $classifiers | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $classifierVersion } | Select-Object -First 1
            if (-not $bundledClassifier) {
                & $add "classifier $address" 'Missing' "No bundled classifier for $classifierVersion. Run Invoke-Build BuildClassifier." "Invoke-Build BuildClassifier -Provider $address; $refreshAction" (& $classifierInspect $address $version $null)
            }
            elseif ($classifierVersion -ne $version) {
                & $add "classifier $address" 'Stale' "The bundled classifier is $classifierVersion; the entry version is $version. Run Invoke-Build BuildSchemaPack and BuildClassifier." "$(& $buildSchemaPack $address); Invoke-Build BuildClassifier -Provider $address; $refreshAction" (& $classifierInspect $address $version $null)
            }
            else {
                & $add "classifier $address" 'Fresh' "Bundled classifier $classifierVersion."
            }
        }

        if ($Online) {
            $parsed = ConvertTo-TerraformProviderAddress -Provider $address
            $namespace = if ($registryProvider) { $registryProvider.Namespace } else { $parsed.Namespace }
            $name = if ($registryProvider) { $registryProvider.Name } else { $parsed.Name }
            try {
                $liveVersion = (Find-TerraformProviderDocVersion -Namespace $namespace -Name $name -Version '').Version
                if ($liveVersion -ne $version) {
                    & $add "online $address" 'Stale' "$($script:TerraformRegistrySource) has $liveVersion; the entry version is $version. Run Invoke-Build BuildRegistry, then HarvestBundleDocs." "$registryAction; $refreshAction" $registryInspect
                }
                else {
                    & $add "online $address" 'Fresh' "$version is the latest on $($script:TerraformRegistrySource)."
                }
            }
            catch {
                & $add "online $address" 'Missing' "Could not read $address from $($script:TerraformRegistrySource): $($_.Exception.Message)" "Test-TerraformGraphBundle -BundlePath $(& $quote $full) -Online" "Invoke-RestMethod -Uri 'https://$($script:TerraformRegistrySource)/v2/providers/$namespace/$name' | Select-Object -ExpandProperty data"
            }
        }
    }

    # Bundled classifiers against map.json.
    $mapVersion = $null
    try {
        $mapVersion = (Read-TerraformClassifierMap -Path $script:TerraformClassifierMapPath).MapVersion
    }
    catch {
        & $add 'map.json' 'Stale' $_.Exception.Message 'Invoke-Build BuildClassifier' "git diff -- $(& $quote $script:TerraformClassifierMapPath)"
    }
    if ($mapVersion) {
        foreach ($classifier in $classifiers) {
            $recordedMap = [string](Read-TerraformClassifierJson -Path $classifier.Path)['mapVersion']
            if ($recordedMap -ne $mapVersion) {
                & $add "mapVersion $($classifier.ProviderAddress) $($classifier.Version)" 'Stale' "mapVersion $recordedMap; map.json is $mapVersion. Run Invoke-Build BuildClassifier." "Invoke-Build BuildClassifier -Provider $($classifier.ProviderAddress)" (& $classifierInspect $classifier.ProviderAddress $classifier.Version $classifier.Path)
            }
            else {
                & $add "mapVersion $($classifier.ProviderAddress) $($classifier.Version)" 'Fresh' "mapVersion $mapVersion."
            }
        }
    }

    # Built packs, when there are any.
    if ($manifest) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($pack in @($manifest['packs'])) {
            $kind = if ($pack['kind']) { [string]$pack['kind'] } else { 'schema' }
            $address = [string]$pack['address']
            $packVersion = [string]$pack['version']
            $item = "pack $kind $address $packVersion"
            $null = $seen.Add("$kind|$address")
            $file = Join-Path $DistPath ([string]$pack['file'])
            $entry = $entries[$address]
            $expected = if (-not $entry) { $null } elseif ($kind -eq 'docs') { [string]$entry['docsVersion'] } else { [string]$entry['schemaVersion'] }
            $packAction = & $buildSchemaPack $address
            $packInspect = "(Get-Content -LiteralPath $(& $quote $manifestPath) -Raw | ConvertFrom-TerraformJson).packs | Where-Object address -eq $(& $quote $address) | Format-Table kind, address, version, file, sha256"
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                & $add $item 'Missing' "$file is listed in manifest.json but does not exist. Run Invoke-Build BuildSchemaPack." $packAction $packInspect
            }
            elseif ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$pack['sha256']) {
                & $add $item 'Stale' "$file does not match the sha256 in manifest.json. Run Invoke-Build BuildSchemaPack." $packAction $packInspect
            }
            elseif (-not $entry) {
                & $add $item 'Stale' "The bundle has no entry for $address. $refresh" $refreshAction $refreshInspect
            }
            elseif ($expected -ne $packVersion) {
                & $add $item 'Stale' "The bundle entry records $kind $expected. Run Invoke-Build BuildSchemaPack, then refresh the bundle." "$packAction; $refreshAction" $packInspect
            }
            else {
                & $add $item 'Fresh' "$([string]$pack['file']) matches the bundle entry."
            }
        }
        foreach ($address in $entries.Keys) {
            $schemaVersion = [string]$entries[$address]['schemaVersion']
            if ($schemaVersion -and -not $seen.Contains("schema|$address")) {
                & $add "pack schema $address $schemaVersion" 'Missing' "The bundle records schema $schemaVersion but $DistPath has no schema pack for it. Run Invoke-Build BuildSchemaPack." (& $buildSchemaPack $address) "Get-ChildItem -LiteralPath $(& $quote $DistPath)"
            }
        }
    }

    foreach ($row in $rows) { $row }
    $bad = @($rows | Where-Object Status -ne 'Fresh')
    if ($Strict -and $bad.Count) {
        $lines = @($bad | Select-Object -First 25 | ForEach-Object { "$($_.Item) [$($_.Status)]: $($_.Detail) Fix: $($_.RecommendedAction)" })
        $more = if ($bad.Count -gt 25) { "`n  ... and $($bad.Count - 25) more" } else { '' }
        Stop-TerraformGraphCommand -Id 'BundleNotFresh' -Category InvalidData -Target $full -Message "$($bad.Count) of $($rows.Count) bundle checks are not fresh ($full):`n  $($lines -join "`n  ")$more`nEach row's InspectAction shows the change first; its RecommendedAction makes it. Test-TerraformGraphBundle | Format-List Item, InspectAction, RecommendedAction lists them."
    }
}
