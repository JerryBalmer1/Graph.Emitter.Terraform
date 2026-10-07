function New-TerraformClassifier {
    <#
    .SYNOPSIS
        Writes a provider version's classifier: every resource and data source type with its subcategory and drawer.

    .DESCRIPTION
        New-TerraformClassifier reads one provider version from the local schema cache and
        the docs cache, takes each resource and data source type from the schema, looks up
        its doc page's subcategory (the provider's own label, such as "Key Vault" or
        "Host and Cluster Management") and maps that label to a drawer through the map
        file. A row for the provider wins over a '*' row. A type with no label (no doc page
        or an empty subcategory) can still be placed by a prefix row: a map row with
        source "prefix" whose subcategory field is a type prefix after the provider token
        (git places azuredevops_git and azuredevops_git_*; the longest prefix wins). It
        never touches the network.

        A type the map cannot place is in the unclassified drawer and is listed in findings:
            NoDocPage            the schema has the type but the docs have no page for it
            NoSubcategory        the page has an empty subcategory
            UnmappedSubcategory  the map has no row for the page's subcategory
        unclassified is a legitimate drawer, not an error.

        The file is <OutputPath>\<address-slug>.<version>.json:
            { provider, version, docsVersion, generatedOn, mapVersion,
              source: "subcategory" (or "subcategory,prefix" when a prefix row placed a type),
              types: [ { type, kind, subcategory, drawer, source: subcategory|prefix|null } ],
              findings: [ { type, kind, subcategory, finding } ] }
        version is the schema version. Docs are read at the same version, else the newest
        cached docs with a warning, and docsVersion says which. mapVersion is a hash of the
        map's rows. Types and findings are sorted by type, then kind. When a rerun gives
        the same content, the file and its generatedOn are left as they are, so reruns are
        byte-identical.

        The map is checked first: a row with no reason, a drawer not in drawers.json, a
        row targeting unclassified, a source other than subcategory or prefix, a '*' prefix
        row, or a repeated provider, source and subcategory stops the command before
        anything is read; a prefix row that matches no type in the provider's cached schema
        stops it once the schema is read. Judgements behind the map are in
        classifiers\DECISIONS.md.

    .PARAMETER Provider
        Providers to classify: 'vsphere', 'vmware/vsphere' or a full address. A value with
        a wildcard is resolved against the provider registry cache and must match exactly
        one provider. The schema and docs must be cached.

    .PARAMETER Version
        Schema version to classify. Default: the newest cached schema of each provider.

    .PARAMETER MapPath
        Map file. Default: classifiers\map.json in the module folder. drawers.json beside
        it is the drawer list, else the bundled one.

    .PARAMETER OutputPath
        Folder to write to. Default: $env:LOCALAPPDATA\TerraformGraph\classifiers, which
        Get-TerraformClassifier and -Classify search before the classifiers bundled with the
        module.

    .PARAMETER PassThru
        Return one TerraformGraph.ClassifierBuild per provider.

    .EXAMPLE
        New-TerraformClassifier -Provider vmware/vsphere -PassThru

        Classify the newest cached vsphere schema into the user classifier folder and show
        the type and finding counts.

    .EXAMPLE
        New-TerraformClassifier -Provider azurerm -MapPath .\my-map.json -OutputPath .\classifiers -PassThru

        Classify with your own map into a folder you then pass as -ClassifierPath.

    .OUTPUTS
        None, or TerraformGraph.ClassifierBuild with -PassThru: ProviderAddress, Version,
        DocsVersion, Path, Status (Written, Updated or Unchanged), TypeCount, FindingCount,
        Drawers (ordered drawer -> type count). Default view is ProviderAddress, Version,
        Status, TypeCount, FindingCount.

    .LINK
        Get-TerraformClassifier

    .LINK
        Get-TerraformClassifierFinding
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string]
        $MapPath = $script:TerraformClassifierMapPath,

        [string]
        $OutputPath = $script:TerraformClassifierUserRoot,

        [switch]
        $PassThru
    )

    try {
        $map = Read-TerraformClassifierMap -Path $MapPath
    }
    catch {
        Stop-TerraformGraphCommand -Id 'ClassifierMapInvalid' -Category InvalidData -Target $MapPath -ExceptionType ([System.IO.InvalidDataException]) -Message ($_.Exception.Message)
    }
    Write-Verbose "Map $($map.Path), mapVersion $($map.MapVersion)"

    foreach ($name in $Provider) {
        try {
            $parsed = if ([WildcardPattern]::ContainsWildcardCharacters($name)) {
                ConvertTo-TerraformProviderAddress -Provider (Resolve-TerraformRegistryProvider -Name $name).ProviderAddress
            }
            else {
                ConvertTo-TerraformProviderAddress -Provider $name
            }
        }
        catch {
            # A missing bundle or registry cache keeps its own id (DECISIONS 50).
            if ((Get-TerraformGraphErrorId $_) -in 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
            Stop-TerraformGraphCommand -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $name -ExceptionType ([System.ArgumentException]) -Message ($_.Exception.Message)
        }
        $address = $parsed.Address.ToLowerInvariant()

        $schemaEntries = @(Get-TerraformSchemaCacheEntry | Where-Object { $_.ProviderAddress -eq $address })
        $schemaEntry = if ($Version) { $schemaEntries | Where-Object Version -eq $Version | Select-Object -First 1 } else { $schemaEntries | Select-Object -First 1 }
        if (-not $schemaEntry) {
            $cachedText = if ($schemaEntries.Count) { " (cached: $(@($schemaEntries.Version) -join ', '))" } else { '' }
            Stop-TerraformGraphCommand -Id 'SchemaNotCached' -Category ObjectNotFound -Target $name -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No cached schema for $address$(if ($Version) { " $Version" })$cachedText. Download a schema pack with Get-TerraformSchemaPack -Provider $($parsed.Source), or harvest it with Get-TerraformProviderSchema -Provider $($parsed.Source) -SaveToCache."
        }
        $docEntries = @(Get-TerraformSchemaCacheEntry -Kind Docs | Where-Object { $_.ProviderAddress -eq $address })
        $docEntry = $docEntries | Where-Object Version -eq $schemaEntry.Version | Select-Object -First 1
        if (-not $docEntry) {
            $docEntry = $docEntries | Select-Object -First 1
            if (-not $docEntry) {
                Stop-TerraformGraphCommand -Id 'ProviderDocNotCached' -Category ObjectNotFound -Target $name -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "No cached docs for $address. Download a docs pack with Get-TerraformDocPack -Provider $($parsed.Source), or harvest them with Update-TerraformProviderDocCache -Provider $($parsed.Source) -Version $($schemaEntry.Version)."
            }
            Write-Warning "Docs for $address $($schemaEntry.Version) are not cached; classifying with the cached $($docEntry.Version) docs. Run Update-TerraformProviderDocCache -Provider $($parsed.Source) -Version $($schemaEntry.Version) to match the schema."
        }

        Write-Verbose "Classifying $address $($schemaEntry.Version) with docs $($docEntry.Version)"
        $schemas = (Read-TerraformSchemaCache -Path $schemaEntry.Path)['provider_schemas']
        $key = @($schemas.Keys) | Where-Object { $_ -eq $address } | Select-Object -First 1
        $docs = (Read-TerraformProviderDocFile -Path $docEntry.Path).Docs
        $schemaTypes = [string[]]@(
            foreach ($section in 'resource_schemas', 'data_source_schemas') { if ($schemas[$key][$section]) { $schemas[$key][$section].Keys } }
        )
        $prefixProblems = @(Get-TerraformClassifierPrefixProblem -Map $map -Address $address -Type $schemaTypes)
        if ($prefixProblems.Count) {
            Stop-TerraformGraphCommand -Id 'ClassifierMapInvalid' -Category InvalidData -Target $MapPath -ExceptionType ([System.IO.InvalidDataException]) -Message "Classifier map '$($map.Path)' has $($prefixProblems.Count) problem(s) against the cached $address $($schemaEntry.Version) schema:`n  $($prefixProblems -join "`n  ")`nFix or remove those prefix rows, then rerun New-TerraformClassifier -Provider $address."
        }
        $document = ConvertTo-TerraformClassifierDocument -Address $address -Version $schemaEntry.Version -DocsVersion $docEntry.Version `
            -SchemaEntry $schemas[$key] -Docs $docs -Map $map -GeneratedOn $null

        $slug = $address.Replace('/', '-')
        $path = Join-Path $OutputPath "$slug.$($schemaEntry.Version).json"
        $now = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        $status = 'Written'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $status = 'Updated'
            $existingText = [System.IO.File]::ReadAllText($path)
            try {
                $document.generatedOn = [string]([TerraformGraph.Json]::Deserialize($existingText, 64, $true))['generatedOn']
                # A git checkout with core.autocrlf may have turned LF into CRLF; that is not a change.
                if ((Format-TerraformClassifierJson -Document $document) -ceq $existingText.Replace("`r`n", "`n")) { $status = 'Unchanged' }
            }
            catch {
                Write-Verbose "Replacing unreadable $path`: $($_.Exception.Message)"
            }
        }

        if ($status -ne 'Unchanged') {
            $document.generatedOn = $now
            $null = New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop
            $temporary = Join-Path $OutputPath ".$([guid]::NewGuid().ToString('n')).tmp"
            try {
                [System.IO.File]::WriteAllText($temporary, (Format-TerraformClassifierJson -Document $document), [System.Text.UTF8Encoding]::new($false))
                Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
            }
            finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
            }
        }
        Write-Verbose "$status $path`: $(@($document.types).Count) types, $(@($document.findings).Count) findings"

        if ($PassThru) {
            $drawers = [ordered]@{}
            foreach ($drawerName in $map.Drawers) {
                $count = @($document.types | Where-Object { $_.drawer -ceq $drawerName }).Count
                if ($count) { $drawers[$drawerName] = $count }
            }
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.ClassifierBuild'
                ProviderAddress = $address
                Version         = $schemaEntry.Version
                DocsVersion     = $docEntry.Version
                Path            = (Resolve-Path -LiteralPath $path).ProviderPath
                Status          = $status
                TypeCount       = @($document.types).Count
                FindingCount    = @($document.findings).Count
                Drawers         = $drawers
            }
        }
    }
}
