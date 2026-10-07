function Update-TerraformProviderDocCache {
    <#
    .SYNOPSIS
        Harvests provider documentation from the public registry into the docs cache, for named providers or a whole bundle.

    .DESCRIPTION
        Update-TerraformProviderDocCache lists the docs of one provider version on
        registry.terraform.io, fetches every page's markdown with ForEach-Object -Parallel
        and writes them atomically to
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz. If any page
        still fails, nothing is written for that provider.

        Rate limit: 5xx is retried five times with a short backoff. The registry answers a
        sustained run with 429 for several minutes; the first 429 stops every worker, the run
        waits 30 s (then 60, 120, 240, 300 s on further 429s, or the Retry-After when one is
        sent, at most 600 s), resumes with one worker and adds one per 25 successful
        requests. That state is kept for the whole session, so the next provider (or
        command) starts where the last one left off.

        Checkpoint: every 100 pages, and when a harvest stops part-way (a failed page,
        Ctrl+C), the pages fetched so far are saved to
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.partial.json. -Resume
        continues from that file; a finished harvest deletes it, and -Force deletes it before
        starting. The partial file is never read as cached docs.

        Only the overview, guides, resources and data-sources categories are kept, in the
        hcl language. Each doc gets the Id of the schema node it documents, so docs join to
        ConvertTo-TerraformSchemaGraph and ConvertTo-TerraformResourceGraph output:
            <address>                    overview
            <address>/guide/<slug>       guides
            <address>/resource/<type>    resources
            <address>/data/<type>        data-sources
        The registry slug is the type without the provider prefix (virtual_machine for
        vsphere_virtual_machine), so the type is rebuilt as <prefix>_<slug>, where prefix
        is the one the provider's cached schema uses; a slug that already carries the
        prefix is also tried. Matching uses the cached schema at the same version, else
        the newest cached schema of that provider. A page whose type is in neither form is
        kept with Id <address>/unmatched/<category>/<slug> and counted in UnmatchedCount:
        a finding, not an error. With no cached schema at all, Ids are built from the
        provider name without checking, UnmatchedCount is empty, and a warning names
        Get-TerraformSchemaPack.

        -Provider: a version that is already cached is skipped unless -Force is given, and a
        provider that fails is a terminating error.

        -BundlePath: every provider of the bundle's set (its registry tiers plus extra
        providers, less exclusions, resolved against the registry cache beside the bundle
        file, else the usual registry cache) is harvested at its latest version in that
        registry cache, one after another, and the result is one
        TerraformGraph.DocHarvestSummary. A provider that fails is a warning and a Failed
        row in the summary, never a stop. Without -Resume every provider is harvested
        again; with it, providers already cached at that version are skipped.

        This command and Get-TerraformDocPack are the only ones that fill the docs cache;
        completers and Get-TerraformProviderDoc never touch the network.

    .PARAMETER Provider
        Providers to harvest: 'null', 'hashicorp/null' or
        'registry.terraform.io/hashicorp/null'. A value with a wildcard is resolved against
        the provider registry cache and must match exactly one provider.

    .PARAMETER Version
        Version to harvest, such as 3.2.3. Default: the provider's latest version in the
        registry cache, else the newest version that is not a pre-release on the registry.

    .PARAMETER BundlePath
        A bundle manifest (src\TerraformGraph\data\bundle.json, or a copy written by
        New-TerraformGraphBundle). Harvests every provider in its set and returns a summary.

    .PARAMETER ThrottleLimit
        Concurrent page requests per provider. Default 6.

    .PARAMETER Resume
        Skip a provider whose docs are already cached at the wanted version, without any
        network call (the version must be known from -Version or the registry cache), and
        continue a provider from its partial file. Use it to finish an interrupted run.

    .PARAMETER Force
        Harvest and replace a version that is already cached, and delete its partial file
        first. -Provider only.

    .PARAMETER PassThru
        Return one TerraformGraph.DocCache per provider. -Provider only; a bundle run always
        returns its summary.

    .EXAMPLE
        Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3 -PassThru

        Harvest the five null 3.2.3 pages and show the counts.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider vmware/vsphere
        Update-TerraformProviderDocCache -Provider vmware/vsphere -PassThru -Verbose

        Cache the schema first so every resource and data source page is matched to a
        schema node Id, then harvest the docs at the latest version.

    .EXAMPLE
        $summary = Update-TerraformProviderDocCache -BundlePath .\src\TerraformGraph\data\bundle.json -Resume
        $summary.Failures | Format-Table ProviderAddress, Version, Error

        Harvest every provider in the bundled set that is not cached yet, then list the
        ones that failed and why.

    .OUTPUTS
        -Provider: none, or TerraformGraph.DocCache with -PassThru: ProviderAddress, Version,
        Path, Status (Harvested, Cached or Updated), DocCount, UnmatchedCount, SchemaVersion,
        ResumedPages (pages taken from a partial file), Elapsed, Error. Default view is
        ProviderAddress, Version, Status, DocCount, UnmatchedCount, Elapsed.

        -BundlePath: TerraformGraph.DocHarvestSummary: BundlePath, ProviderCount, PageCount,
        UnmatchedCount, FailureCount, RateLimitHits (429 responses), SecondsBlocked (time
        spent waiting them out), PartialResumes (providers continued from a partial file),
        Elapsed, LogPath, Providers (one DocCache row per provider, Status Failed with Error
        for a failure), Failures. Default view is ProviderCount, PageCount, UnmatchedCount,
        FailureCount, RateLimitHits, Elapsed. The run also writes
        $env:LOCALAPPDATA\TerraformGraph\logs\harvest-<yyyyMMdd-HHmmss>.log (UTC), one line
        per provider and one per 429, and prints its path at the end.

    .LINK
        Get-TerraformProviderDoc

    .LINK
        Get-TerraformDocPack

    .LINK
        Get-TerraformGraphBundle
    #>
    [CmdletBinding(DefaultParameterSetName = 'Provider')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Provider')]
        [string[]]
        $Provider,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $Version,

        [Parameter(Mandatory, ParameterSetName = 'Bundle')]
        [string]
        $BundlePath,

        [ValidateRange(1, 64)]
        [int]
        $ThrottleLimit = 6,

        [switch]
        $Resume,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $Force,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $PassThru
    )

    if ($Resume -and $Force) {
        Stop-TerraformGraphCommand -Id 'ResumeWithForce' -Category InvalidArgument -ExceptionType ([System.ArgumentException]) -Message '-Resume skips cached versions and -Force replaces them; pass one or the other, such as Update-TerraformProviderDocCache -Provider hashicorp/null -Resume.'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Provider') {
        foreach ($name in $Provider) {
            try {
                $row = Invoke-TerraformProviderDocUpdate -Name $name -Version $Version -ThrottleLimit $ThrottleLimit -Force:$Force -Resume:$Resume
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            if ($PassThru) { $row }
        }
        return
    }

    $total = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $bundlePath = Resolve-TerraformGraphBundlePath -Path $BundlePath
        $bundle = Read-TerraformGraphBundle -Path $bundlePath
        $registry = Get-TerraformGraphBundleRegistry -BundlePath $bundlePath
        $selected = @(Resolve-TerraformGraphBundleProvider -Tier $bundle['tiers'] -Provider $bundle['providers'] -Exclude $bundle['exclude'] -Cache $registry)
    }
    catch {
        # A missing bundle or registry cache keeps its own id (DECISIONS 50).
        if ((Get-TerraformGraphErrorId $_) -in 'BundleNotFound', 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
        Stop-TerraformGraphCommand -Id 'BundleInvalid' -Category InvalidData -Target $BundlePath -ExceptionType ([System.IO.InvalidDataException]) -Message ($_.Exception.Message)
    }
    Write-Verbose "Bundle $bundlePath`: $($selected.Count) providers against the registry cache $($registry.Path) (harvested $($registry.HarvestedOn))"

    $throttle = $script:TerraformRegistryThrottle
    $hitsBefore = $throttle.Hits
    $blockedBefore = $throttle.SecondsBlocked
    $null = New-Item -ItemType Directory -Path $script:TerraformGraphLogRoot -Force -ErrorAction Stop
    $logPath = Join-Path $script:TerraformGraphLogRoot "harvest-$([datetime]::UtcNow.ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture)).log"
    $script:TerraformGraphLogPath = $logPath
    Write-TerraformGraphLog "start bundle $bundlePath, $($selected.Count) providers, throttle $ThrottleLimit$(if ($Resume) { ', -Resume' })"

    $rows = [System.Collections.Generic.List[object]]::new()
    try {
        for ($i = 0; $i -lt $selected.Count; $i++) {
            $registryProvider = $selected[$i]
            Write-Progress -Id 3 -Activity 'Harvesting bundle docs' -Status "$($registryProvider.Source) $($registryProvider.Latest) ($($i + 1) of $($selected.Count))" -PercentComplete (100 * $i / [math]::Max(1, $selected.Count))
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $row = Invoke-TerraformProviderDocUpdate -RegistryProvider $registryProvider -ThrottleLimit $ThrottleLimit -Force:(-not $Resume) -Resume:$Resume -Quiet
            }
            catch {
                $stopwatch.Stop()
                Write-Warning "Docs for $($registryProvider.ProviderAddress) $($registryProvider.Latest) failed: $($_.Exception.Message)"
                $row = [pscustomobject]@{
                    PSTypeName      = 'TerraformGraph.DocCache'
                    ProviderAddress = $registryProvider.ProviderAddress
                    Version         = [string]$registryProvider.Latest
                    Path            = $null
                    Status          = 'Failed'
                    DocCount        = $null
                    UnmatchedCount  = $null
                    SchemaVersion   = $null
                    ResumedPages    = 0
                    Elapsed         = $stopwatch.Elapsed
                    Error           = $_.Exception.Message
                }
            }
            Write-Verbose "$($row.ProviderAddress) $($row.Version): $($row.Status), $($row.DocCount) pages in $($row.Elapsed)"
            Write-TerraformGraphLog "$($row.ProviderAddress) $($row.Version) $($row.Status) $([int]$row.DocCount) pages$(if ($row.ResumedPages) { " ($($row.ResumedPages) from a partial file)" }) $($row.Elapsed.ToString('hh\:mm\:ss'))$(if ($row.Error) { " error: $($row.Error)" })"
            $rows.Add($row)
        }
    }
    finally {
        Write-Progress -Id 3 -Activity 'Harvesting bundle docs' -Completed
        $total.Stop()
        Write-TerraformGraphLog "end $($rows.Count) of $($selected.Count) providers, $($throttle.Hits - $hitsBefore) rate-limit hits, $($throttle.SecondsBlocked - $blockedBefore) s blocked, elapsed $($total.Elapsed.ToString('hh\:mm\:ss'))"
        $script:TerraformGraphLogPath = $null
        Write-Host "Harvest log: $logPath"
    }

    $failures = [object[]]@($rows | Where-Object Status -eq 'Failed')
    $pages = 0
    $unmatched = 0
    foreach ($row in $rows) { $pages += [int]$row.DocCount; $unmatched += [int]$row.UnmatchedCount }
    [pscustomobject]@{
        PSTypeName     = 'TerraformGraph.DocHarvestSummary'
        BundlePath     = $bundlePath
        ProviderCount  = $rows.Count
        PageCount      = $pages
        UnmatchedCount = $unmatched
        FailureCount   = $failures.Length
        RateLimitHits  = $throttle.Hits - $hitsBefore
        SecondsBlocked = $throttle.SecondsBlocked - $blockedBefore
        PartialResumes = @($rows | Where-Object { $_.ResumedPages -gt 0 }).Count
        Elapsed        = $total.Elapsed
        LogPath        = $logPath
        Providers      = $rows.ToArray()
        Failures       = $failures
    }
}
