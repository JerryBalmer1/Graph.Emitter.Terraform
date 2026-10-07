function Install-TerraformPack {
    # Not exported. The body of Get-TerraformSchemaPack (-Kind Schema) and
    # Get-TerraformDocPack (-Kind Docs). Reads manifest.json from -Source, keeps the entries
    # of -Kind (an entry with no kind is a schema entry, as manifests before 0.11.0 wrote
    # them), resolves every provider to an entry before downloading anything, downloads,
    # checks sha256 and moves each file into the -Kind cache. Terminating errors go through
    # -Cmdlet, the calling function's $PSCmdlet, so they carry its name.
    param(
        [System.Management.Automation.PSCmdlet]$Cmdlet,
        [ValidateSet('Schema', 'Docs')][string]$Kind,
        [string[]]$Provider,
        [string]$Version,
        [string]$Source,
        [switch]$Force,
        [switch]$PassThru
    )

    $isDocs = $Kind -eq 'Docs'
    $errorPrefix = if ($isDocs) { 'DocPack' } else { 'SchemaPack' }
    $commandName = if ($isDocs) { 'Get-TerraformDocPack' } else { 'Get-TerraformSchemaPack' }
    $what = if ($isDocs) { 'docs pack' } else { 'pack' }

    $isUrl = $Source -match '^https?://'
    if (-not $isUrl) {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            Stop-TerraformGraphCommand -Id "$($errorPrefix)SourceNotFound" -Category ObjectNotFound -Target $Source -ExceptionType ([System.IO.DirectoryNotFoundException]) -Message "Source '$Source' is not an http(s) URL or an existing directory. Pass a folder that holds manifest.json, or leave -Source out to use the release: $commandName -Provider <name>."
        }
        $Source = (Resolve-Path -LiteralPath $Source).ProviderPath
    }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "TerraformGraph-pack-$([guid]::NewGuid().ToString('n'))"
    $null = New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop
    $downloadState = @{}
    try {
        $manifestPath = Join-Path $staging 'manifest.json'
        try {
            Save-TerraformSchemaPackFile -Source $Source -Name 'manifest.json' -Destination $manifestPath -State $downloadState
            $manifest = [TerraformGraph.Json]::Deserialize([System.IO.File]::ReadAllText($manifestPath), 1024, $false)
        }
        catch {
            Stop-TerraformGraphCommand -Id "$($errorPrefix)ManifestUnavailable" -Category ConnectionError -Target $Source -InnerException $_.Exception -Message "Could not read manifest.json from '$Source': $($_.Exception.Message) Check -Source (set `$env:GH_TOKEN for a private fork), then rerun $commandName."
        }
        $manifestKind = if ($isDocs) { 'docs' } else { 'schema' }
        $packs = @($manifest.packs | Where-Object { $_ -and ([string]$_.kind -eq $manifestKind -or (-not $isDocs -and -not $_.kind)) })

        # Every provider is resolved to a manifest entry before anything is downloaded.
        $targets = [System.Collections.Generic.List[string]]::new()
        if (-not $Provider) {
            # ForEach-Object, not $packs.address: that member access hits System.Array.Address.
            foreach ($address in @($packs | ForEach-Object { [string]$_.address } | Select-Object -Unique)) { $targets.Add($address) }
        }
        foreach ($name in $Provider) {
            if ([WildcardPattern]::ContainsWildcardCharacters($name)) {
                try {
                    $address = (Resolve-TerraformRegistryProvider -Name $name).ProviderAddress
                }
                catch {
                    # A missing bundle or registry cache keeps its own id (DECISIONS 50).
                    if ((Get-TerraformGraphErrorId $_) -in 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
                    Stop-TerraformGraphCommand -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $name -ExceptionType ([System.ArgumentException]) -Message ($_.Exception.Message)
                }
            }
            else {
                $address = (ConvertTo-TerraformProviderAddress -Provider $name).Address
                if (-not ($packs | Where-Object address -eq $address) -and -not $name.Contains('/')) {
                    $byName = @($packs | Where-Object { ([string]$_.address).Split('/')[-1] -eq $name } | ForEach-Object address | Select-Object -Unique)
                    if ($byName.Count -eq 1) { $address = [string]$byName[0] }
                }
            }
            if (-not ($targets | Where-Object { $_ -eq $address })) { $targets.Add($address) }
        }

        $selected = foreach ($address in $targets) {
            $candidates = @($packs | Where-Object address -eq $address)
            $entry = if ($Version) {
                $candidates | Where-Object version -eq $Version | Select-Object -First 1
            }
            elseif ($candidates.Count) {
                (Sort-TerraformRegistryVersion -Versions @($candidates | ForEach-Object { [pscustomobject]@{ Version = [string]$_.version; Pack = $_ } }) |
                    Select-Object -First 1).Record.Pack
            }
            if (-not $entry) {
                $available = if ($packs.Count) { @($packs | ForEach-Object { "$($_.address) $($_.version)" }) -join ', ' } else { '(none)' }
                # Not $source: variable names ignore case, so that would overwrite -Source.
                $providerSource = (ConvertTo-TerraformProviderAddress -Provider $address).Source
                $versionText = if ($Version) { " $Version" } else { '' }
                $instead = if ($isDocs) {
                    "Harvest them from the registry instead with Update-TerraformProviderDocCache -Provider $providerSource$(if ($Version) { " -Version $Version" })."
                }
                else {
                    "Harvest it locally instead with Get-TerraformProviderSchema -Provider $providerSource$(if ($Version) { " -Version '= $Version'" }) -SaveToCache."
                }
                Stop-TerraformGraphCommand -Id "$($errorPrefix)NotFound" -Category ObjectNotFound -Target $address -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "$commandName found no $what for $address$versionText in '$Source' ($($what)s: $available). $instead"
            }
            $entry
        }

        foreach ($entry in @($selected)) {
            $address = [string]$entry.address
            $packVersion = [string]$entry.version
            $cachePath = Get-TerraformSchemaCachePath -Provider $address -Version $packVersion -Kind $Kind
            $existed = Test-Path -LiteralPath $cachePath -PathType Leaf

            if ($existed -and -not $Force) {
                Write-Verbose "$address $packVersion is already cached at $cachePath. Use -Force to download it again."
                $status = 'Cached'
            }
            else {
                $fileName = [string]$entry.file
                if (-not $fileName -or $fileName -ne [System.IO.Path]::GetFileName($fileName) -or $fileName -in '.', '..') {
                    Stop-TerraformGraphCommand -Id "$($errorPrefix)InvalidManifest" -Category InvalidData -Target $address -ExceptionType ([System.IO.InvalidDataException]) -Message "The manifest entry for $address $packVersion has an invalid file name '$fileName'. Rebuild the packs with Invoke-Build BuildSchemaPack."
                }
                $download = Join-Path $staging $fileName
                Write-Verbose "Downloading $fileName from $Source"
                try {
                    Save-TerraformSchemaPackFile -Source $Source -Name $fileName -Destination $download -State $downloadState
                }
                catch {
                    Stop-TerraformGraphCommand -Id "$($errorPrefix)DownloadFailed" -Category ConnectionError -Target $address -InnerException $_.Exception -Message "Could not download $fileName from '$Source': $($_.Exception.Message) Rerun $commandName -Provider $address (set `$env:GH_TOKEN for a private fork)."
                }

                $hash = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash
                if ($hash -ne [string]$entry.sha256) {
                    Stop-TerraformGraphCommand -Id "$($errorPrefix)HashMismatch" -Category InvalidData -Target $address -ExceptionType ([System.IO.InvalidDataException]) -Message "sha256 mismatch for $fileName ($address $packVersion): expected $($entry.sha256), got $($hash.ToLowerInvariant()). Nothing was written to the cache. Rerun $commandName -Provider $address; if it repeats, the release is out of step with its manifest: Invoke-Build BuildSchemaPack."
                }

                # Verified: move it into the cache folder under a temporary name, then into place.
                $directory = Split-Path -Path $cachePath -Parent
                $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
                $temporary = Join-Path $directory ".$([guid]::NewGuid().ToString('n')).tmp"
                try {
                    Move-Item -LiteralPath $download -Destination $temporary -ErrorAction Stop
                    Move-Item -LiteralPath $temporary -Destination $cachePath -Force -ErrorAction Stop
                }
                finally {
                    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
                }
                Write-Verbose "Cached $address $packVersion at $cachePath"
                $status = if ($existed) { 'Updated' } else { 'Downloaded' }
            }

            if ($PassThru) {
                [pscustomobject]@{
                    PSTypeName      = if ($isDocs) { 'TerraformGraph.DocPack' } else { 'TerraformGraph.SchemaPack' }
                    ProviderAddress = $address
                    Version         = $packVersion
                    Path            = $cachePath
                    Bytes           = (Get-Item -LiteralPath $cachePath).Length
                    Status          = $status
                }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
