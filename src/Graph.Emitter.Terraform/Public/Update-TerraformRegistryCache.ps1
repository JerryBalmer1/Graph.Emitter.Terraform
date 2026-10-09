function Update-TerraformRegistryCache {
    <#
    .SYNOPSIS
        Downloads the list of Terraform providers and their versions into the registry cache.

    .DESCRIPTION
        Update-TerraformRegistryCache lists providers from the public registry
        (registry.terraform.io, v2 API, 100 per page), then fetches every provider's
        versions with ForEach-Object -Parallel: the v1 versions endpoint for protocols and
        the v2 provider-versions include for publish dates, two calls per provider. Calls
        that return 5xx are retried five times with a short backoff. The first 429 (the
        registry's rate limit) stops every worker for 30 s, then 60, 120, 240 and 300 s on
        further 429s, and the run resumes with one worker and adds one per 25 successful
        requests; that rate state is shared with Update-TerraformProviderDocCache for the
        whole session. If any provider still fails, nothing is written.

        The file is written atomically: a temporary file in the same folder, then Move-Item.
        Providers are sorted by address; versions newest first, pre-releases included. Each
        provider's latest is its newest version that is not a pre-release.

        This is the only Graph.Emitter.Terraform command that reads the registry list over the
        network. Get-TerraformRegistryProvider, the -Provider wildcards of
        Get-TerraformProviderSchema and the argument completers only read the cache.

    .PARAMETER Scope
        OfficialPartner (default): official and partner providers. All: every tier,
        including community, which is many times larger and slower.

    .PARAMETER Path
        Cache file to write. Defaults to the user cache,
        $env:LOCALAPPDATA\TerraformGraph\registry.json, which takes precedence over the
        bundled copy.

    .PARAMETER ThrottleLimit
        Concurrent provider requests. Default 6.

    .PARAMETER PassThru
        Return a TerraformGraph.RegistryCache summary.

    .EXAMPLE
        Update-TerraformRegistryCache -Verbose

        Refresh the user cache with official and partner providers.

    .EXAMPLE
        Update-TerraformRegistryCache -Scope All -Path .\registry-all.json -PassThru

        Harvest every tier into a separate file and show the counts.

    .OUTPUTS
        None, or TerraformGraph.RegistryCache with -PassThru: Path, HarvestedOn, Scope,
        ProviderCount, VersionCount, Elapsed.

    .LINK
        Get-TerraformRegistryProvider
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('OfficialPartner', 'All')]
        [string]
        $Scope = 'OfficialPartner',

        [string]
        $Path = $script:TerraformRegistryUserCachePath,

        [ValidateRange(1, 64)]
        [int]
        $ThrottleLimit = 6,

        [switch]
        $PassThru
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $fetched = Get-TerraformRegistryHarvest -Scope $Scope -ThrottleLimit $ThrottleLimit
    }
    catch {
        Stop-TerraformGraphCommand -Id 'RegistryHarvestFailed' -Category ConnectionError -Target $script:TerraformRegistrySource -InnerException $_.Exception -Message "$($_.Exception.Message) Rerun Update-TerraformRegistryCache; after a 429 (rate limit), wait 10 minutes first."
    }

    $versionCount = 0
    $providers = foreach ($entry in $fetched) {
        $provider = $entry.Provider
        $sorted = @(Sort-TerraformRegistryVersion -Versions $entry.Versions)
        $versionCount += $sorted.Count
        $latest = $sorted | Where-Object { -not $_.PreRelease } | Select-Object -First 1
        [ordered]@{
            address     = "$($script:TerraformRegistrySource)/$($provider.Namespace)/$($provider.Name)".ToLowerInvariant()
            namespace   = $provider.Namespace
            name        = $provider.Name
            tier        = $provider.Tier
            description = $provider.Description
            latest      = if ($latest) { $latest.Record.Version } else { $null }
            versions    = [object[]]@(foreach ($version in $sorted) {
                    [ordered]@{
                        version   = $version.Record.Version
                        protocols = [object[]]@($version.Record.Protocols)
                        published = $version.Record.Published
                    }
                })
        }
    }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($provider in $providers) { $list.Add($provider) }
    $list.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.address, $b.address) })

    $harvestedOn = [datetime]::UtcNow
    $document = [ordered]@{
        harvestedOn = $harvestedOn.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        scope       = if ($Scope -eq 'OfficialPartner') { 'official,partner' } else { 'all' }
        source      = $script:TerraformRegistrySource
        providers   = $list.ToArray()
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path, (Get-Location -PSProvider FileSystem).ProviderPath)
    $directory = Split-Path -Path $fullPath -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporary = Join-Path $directory ".registry.$([guid]::NewGuid().ToString('n')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, [TerraformGraph.Json]::Serialize($document, 1024, $false) + "`n")
        Move-Item -LiteralPath $temporary -Destination $fullPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    $stopwatch.Stop()
    Write-Verbose "Wrote $($list.Count) providers and $versionCount versions to $fullPath in $($stopwatch.Elapsed)"

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName    = 'TerraformGraph.RegistryCache'
            Path          = $fullPath
            HarvestedOn   = $harvestedOn
            Scope         = $document.scope
            ProviderCount = $list.Count
            VersionCount  = $versionCount
            Elapsed       = $stopwatch.Elapsed
        }
    }
}
