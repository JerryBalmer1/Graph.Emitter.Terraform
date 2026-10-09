[CmdletBinding()]
Param(
    # BuildSchemaPack and BuildClassifier: providers to pack or classify, as namespace/name or a full address.
    [string[]]
    $Provider = @('hashicorp/azurerm', 'microsoft/azuredevops', 'vmware/vsphere'),

    # HarvestBundleDocs: skip providers whose docs are already cached at their latest version.
    [switch]
    $Resume,

    # CheckBundle: also compare against the live registry.
    [switch]
    $Online
)

# InvokeBuild must already be installed (Install-Module InvokeBuild -Scope CurrentUser); this
# script never installs anything when it is loaded.

######################################################################################################
# InvokeBuild - ArgumentCompleters
######################################################################################################

Register-ArgumentCompleter -CommandName Invoke-Build.ps1 -ParameterName Task -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $boundParameters)

    (Invoke-Build -Task ?? -File ($boundParameters['File'])).get_Keys() -like "$wordToComplete*" | .{process{
        New-Object System.Management.Automation.CompletionResult $_, $_, 'ParameterValue', $_
    }}
}

Register-ArgumentCompleter -CommandName Invoke-Build.ps1 -ParameterName File -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $boundParameters)

    Get-ChildItem -Directory -Name "$wordToComplete*" | .{process{
        New-Object System.Management.Automation.CompletionResult $_, $_, 'ProviderContainer', $_
    }}

    if (!($boundParameters['Task'] -eq '**')) {
        Get-ChildItem -File -Name "$wordToComplete*.ps1" | .{process{
            New-Object System.Management.Automation.CompletionResult $_, $_, 'Command', $_
        }}
    }
}

######################################################################################################
# Helpers
######################################################################################################

function Get-RepoBranch {
    $name = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $name) {
        throw "Not a git repository (or git is not on PATH)."
    }
    $name.Trim()
}

function Assert-GitClean {
    $status = git status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed."
    }
    if ($status) {
        throw "Working tree is not clean. Commit or stash first.`n$status"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]
        $Arguments
    )
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-ModuleManifestPath {
    Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'Graph.Emitter.Terraform.psd1'
}

function Get-ManifestVersion {
    $manifestPath = Get-ModuleManifestPath
    $data = Import-PowerShellDataFile -Path $manifestPath
    [version]$data.ModuleVersion
}

function Get-LatestReleaseTag {
    # Release tags are v<major>.<minor>.<patch> (v0.10.0 ... v0.14.0).
    $raw = git tag --list 'v*' 2>$null
    if (-not $raw) {
        return $null
    }
    $versions = foreach ($tag in @($raw)) {
        if ($tag.Trim() -match '^v(\d+\.\d+\.\d+)$') {
            [version]$Matches[1]
        }
    }
    if (-not $versions) {
        return $null
    }
    $versions | Sort-Object | Select-Object -Last 1
}

function Assert-ReleaseReady {
    # Release and Publish: on main, a clean tree, and the drawers semver test passing (in a
    # fresh process, as every test run should be).
    $branch = Get-RepoBranch
    if ($branch -ne 'main') {
        throw "Release and Publish run on main. Current branch is '$branch'."
    }
    Assert-GitClean
    $filter = 'Contracts.drawers are semver-safe'
    $command = "`$c = New-PesterConfiguration; `$c.Run.Path = '$(Join-Path $PSScriptRoot 'tests')'; `$c.Filter.FullName = '$filter'; `$c.Run.Exit = `$true; Invoke-Pester -Configuration `$c"
    & pwsh -NoProfile -Command $command
    if ($LASTEXITCODE -ne 0) {
        throw "Pester '$filter' failed: a drawer was renamed or removed without a major version (DECISIONS 47)."
    }
}

######################################################################################################
# InvokeBuild - Tasks
######################################################################################################

# Runs at most once per Invoke-Build invocation. Later tasks that list it as a
# dependency reuse the result; they do not probe again.
task CheckDependencies {

    $failures = [System.Collections.Generic.List[string]]::new()

    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion -lt [version]'7.4') {
        $failures.Add("PowerShell 7.4+ is required. This session is $psVersion. Install pwsh 7.4 or later and rerun.")
    }
    else {
        Write-Host "OK  PowerShell $psVersion" -ForegroundColor Green
    }

    $minPester = [version]'6.1.0'
    $pesterMod = Get-Module -ListAvailable -Name Pester |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $pesterMod) {
        $failures.Add("Pester $minPester+ is required. Install-Module Pester -MinimumVersion 6.1.0 -Scope CurrentUser -Force")
    }
    elseif ($pesterMod.Version -lt $minPester) {
        $failures.Add("Pester $($pesterMod.Version) is installed; $minPester or later is required. Update-Module Pester -Force")
    }
    else {
        Write-Host "OK  Pester $($pesterMod.Version)" -ForegroundColor Green
    }

    $terraform = Get-Command terraform -ErrorAction SilentlyContinue
    if (-not $terraform) {
        $failures.Add("terraform is not on PATH. Install Terraform and ensure `terraform version` works.")
    }
    else {
        $tfOut = & terraform version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("terraform was found but `terraform version` failed:`n$tfOut")
        }
        else {
            $tfLine = ($tfOut -split "`r?`n" | Where-Object { $_ } | Select-Object -First 1)
            Write-Host "OK  $tfLine ($($terraform.Source))" -ForegroundColor Green
        }
    }

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        $failures.Add("docker is not on PATH. Install Docker Desktop (or the Docker CLI) and ensure `docker version` works.")
    }
    else {
        Write-Host "OK  docker CLI ($($docker.Source))" -ForegroundColor Green

        $null = & docker info --format '{{.ServerVersion}}' 2>&1
        if ($LASTEXITCODE -ne 0) {
            $infoOut = & docker info 2>&1 | Out-String
            $failures.Add("Docker CLI is present but the Docker engine is not running. Start Docker Desktop and wait until it is ready.`n$infoOut")
        }
        else {
            Write-Host "OK  Docker engine is up" -ForegroundColor Green
        }
    }

    if ($failures.Count -gt 0) {
        throw (@('CheckDependencies failed:', $failures) -join "`n - ")
    }

}

# What Test needs: PowerShell and Pester. terraform is optional (RequiresTerraform tests are
# skipped without it) and Docker is only for BuildDLL.
task CheckTestDependencies {
    if ($PSVersionTable.PSVersion -lt [version]'7.4') {
        throw "PowerShell 7.4+ is required. This session is $($PSVersionTable.PSVersion)."
    }
    $pester = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester -or $pester.Version -lt [version]'6.1.0') {
        throw "Pester 6.1.0+ is required. Install-Module Pester -MinimumVersion 6.1.0 -Scope CurrentUser -Force"
    }
    Write-Host "OK  PowerShell $($PSVersionTable.PSVersion), Pester $($pester.Version)" -ForegroundColor Green
}

# The Go parser as a Windows x64 c-shared DLL, cross-compiled in Docker (golang image pinned to
# go.mod's Go version). Copies out TerraformGraph.dll and the TerraformGraph.h that go build
# generates from the //export lines (gitignored: never tracked by hand).
task BuildDLL CheckDependencies, {

    $libDirectory  = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'lib'
    $libPath       = Join-Path $libDirectory 'TerraformGraph.dll'
    $headerPath    = Join-Path $libDirectory 'TerraformGraph.h'
    $imageName     = 'terraformgraph'
    $containerName = 'TerraformGraph-tmp'

    if (-not (Test-Path $libDirectory)) {
        New-Item -Path $libDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    Remove-Module -Name Graph.Emitter.Terraform, TerraformGraph -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $libPath) {
        try {
            Remove-Item -LiteralPath $libPath -Force -ErrorAction Stop
        }
        catch {
            # Pinned by a pwsh that loaded it: move it aside (gitignored, never assembled).
            $stale = "$libPath.old"
            if (Test-Path -LiteralPath $stale) {
                Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $libPath -Destination $stale -Force -ErrorAction Stop
        }
    }

    docker rm -f $containerName 2>$null | Out-Null

    docker build -t $imageName .
    if ($LASTEXITCODE -ne 0) {
        throw "docker build failed with exit code $LASTEXITCODE"
    }

    docker create --name $containerName $imageName
    if ($LASTEXITCODE -ne 0) {
        throw "docker create failed with exit code $LASTEXITCODE"
    }

    try {
        docker cp "${containerName}:/TerraformGraph.dll" $libPath
        if ($LASTEXITCODE -ne 0) { throw "docker cp TerraformGraph.dll failed with exit code $LASTEXITCODE" }
        docker cp "${containerName}:/TerraformGraph.h" $headerPath
        if ($LASTEXITCODE -ne 0) { throw "docker cp TerraformGraph.h failed with exit code $LASTEXITCODE" }
    }
    finally {
        docker rm -f $containerName 2>$null | Out-Null
    }

    if (-not (Test-Path -LiteralPath $libPath)) {
        throw "BuildDLL did not produce $libPath"
    }

}

# TerraformGraph.Json.cs compiled to src/Graph.Emitter.Terraform/lib/TerraformGraph.Json.dll (net8.0, the
# runtime of PowerShell 7.4), so an import loads an assembly instead of compiling C#. Needs a
# .NET 8 or later SDK: `dotnet` on PATH, or $env:TERRAFORMGRAPH_DOTNET pointing at dotnet.exe.
# Without one it says so and stops without failing; the psm1 then compiles the source at import.
task BuildJson {
    $dotnet = if ($env:TERRAFORMGRAPH_DOTNET) { $env:TERRAFORMGRAPH_DOTNET } else { (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
    $sdks = if ($dotnet) { @(& $dotnet --list-sdks 2>$null | ForEach-Object { if ($_ -match '^(\d+)\.') { [int]$Matches[1] } }) } else { @() }
    if (-not ($sdks | Where-Object { $_ -ge 8 })) {
        $found = if ($dotnet) { "$dotnet has SDKs $(@(& $dotnet --list-sdks 2>$null) -join '; ')" } else { 'no dotnet on PATH' }
        Write-Warning "BuildJson: no .NET 8 or later SDK ($found). Install one (winget install Microsoft.DotNet.SDK.8) or set `$env:TERRAFORMGRAPH_DOTNET; until then the module compiles TerraformGraph.Json.cs at import, and AssembleModule cannot run."
        return
    }
    $project = Join-Path $PSScriptRoot 'src' 'json' 'TerraformGraph.Json.csproj'
    $output = Join-Path ([System.IO.Path]::GetTempPath()) "TerraformGraph-json-$([guid]::NewGuid().ToString('n'))"
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_NOLOGO = '1'
    try {
        & $dotnet build $project -c Release -o $output
        if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
        $target = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'lib' 'TerraformGraph.Json.dll'
        Copy-Item -LiteralPath (Join-Path $output 'TerraformGraph.Json.dll') -Destination $target -Force -ErrorAction Stop
        Write-Host "Wrote $target ($((Get-Item -LiteralPath $target).Length) bytes)"
    }
    finally {
        Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue
    }
}

task RemoveModule {
    Remove-Module -Name Graph.Emitter.Terraform, TerraformGraph -Force -ErrorAction SilentlyContinue
}

task ImportModule {
    $modulePath = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform'
    Import-Module $modulePath -Force -ErrorAction Stop
}

# The default run, in a fresh process (the parser DLL is pinned for the life of a process):
# every test except those tagged Live. tests/Invoke-Tests.ps1 -Live runs the network ones.
task Test CheckTestDependencies, {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'tests' 'Invoke-Tests.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw "Pester failed (exit code $LASTEXITCODE)."
    }
}

# The CLAUDE.md function list and the shipped SKILL.md function table, regenerated from
# Get-Command and comment-based help (between the generated:functions markers), then the
# .claude copy of the skill. Pester fails when the committed tables differ.
task GenerateDocTables RemoveModule, ImportModule, {
    & (Join-Path $PSScriptRoot 'tools' 'Update-TerraformGraphDocTables.ps1') -RepoRoot $PSScriptRoot -Verbose
    Install-TerraformGraphSkill -Path $PSScriptRoot -Tool Claude -Force
    Write-Host 'Regenerated the function tables in CLAUDE.md and skills/terraformgraph/SKILL.md (and its .claude copy).'
}

# The publishable tree: dist/module/Graph.Emitter.Terraform holds exactly the psd1 FileList
# (tools/Copy-TerraformGraphModule.ps1), then Test-ModuleManifest checks it. Its psm1 is built,
# not copied: the wiring psm1 with Classes/, Private/ and Public/ spliced into its dot-source
# region, so the release imports one file. Needs both DLLs (BuildDLL, BuildJson); dist/ is
# gitignored.
task AssembleModule {
    $tree = Join-Path $PSScriptRoot 'dist' 'module' 'Graph.Emitter.Terraform'
    $files = & (Join-Path $PSScriptRoot 'tools' 'Copy-TerraformGraphModule.ps1') -RepoRoot $PSScriptRoot -OutputPath $tree
    $manifest = Test-ModuleManifest -Path (Join-Path $tree 'Graph.Emitter.Terraform.psd1') -ErrorAction Stop
    $bytes = (Get-ChildItem -LiteralPath $tree -File -Recurse | Measure-Object -Property Length -Sum).Sum
    Write-Host "Assembled Graph.Emitter.Terraform $($manifest.Version): $(@($files).Count) files, $bytes bytes -> $tree"
}

# Not part of the default build. Run when cutting a release: refreshes the provider
# registry cache that ships with the module (network, a few minutes), then stage it.
task BuildRegistry RemoveModule, ImportModule, {
    $path = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'data' 'registry.json'
    $result = Update-TerraformRegistryCache -Scope OfficialPartner -Path $path -PassThru -ErrorAction Stop
    Write-Host "ProviderCount: $($result.ProviderCount)"
    Write-Host "VersionCount:  $($result.VersionCount)"
    Write-Host "Elapsed:       $($result.Elapsed)"
    Write-Host "Size:          $((Get-Item -LiteralPath $path).Length) bytes ($path)"
}

# Not part of the default build. Run when cutting a release, then attach everything in
# dist/schema-packs to the GitHub release: harvests each -Provider at its latest version
# from the registry cache (terraform init, network), saves it to the local schema cache,
# copies the cached file to dist/schema-packs/<address-slug>.<version>.json.gz, harvests
# the same version's registry docs (Update-TerraformProviderDocCache) into
# docs.<address-slug>.<version>.json.gz, and writes manifest.json with a kind (schema |
# docs) per entry. dist/ is gitignored; the folder is recreated on every run.
task BuildSchemaPack RemoveModule, ImportModule, {
    $total = [System.Diagnostics.Stopwatch]::StartNew()
    $dist = Join-Path $PSScriptRoot 'dist' 'schema-packs'
    if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction Stop }
    $null = New-Item -ItemType Directory -Path $dist -Force -ErrorAction Stop

    $packs = foreach ($name in $Provider) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $found = @(Get-TerraformRegistryProvider -Name $name -WarningAction SilentlyContinue)
        if ($found.Count -gt 1) {
            throw "'$name' matches $($found.Count) providers in the registry cache: $(@($found.Source) -join ', '). Use namespace/name."
        }
        $schemaArgs = @{ Provider = $name; SaveToCache = $true; ErrorAction = 'Stop' }
        if ($found.Count -eq 1 -and $found[0].Latest) {
            $schemaArgs.Provider = $found[0].ProviderAddress
            $schemaArgs.Version = "= $($found[0].Latest)"
            Write-Host "$name -> $($found[0].ProviderAddress) $($found[0].Latest) (registry cache)"
        }
        else {
            Write-Warning "$name is not in the registry cache; terraform init picks the version."
        }

        $null = Get-TerraformProviderSchema @schemaArgs
        $cached = @(Get-TerraformSchemaCache -Provider $schemaArgs.Provider)
        $entry = if ($schemaArgs.Version) {
            $cached | Where-Object Version -eq $found[0].Latest | Select-Object -First 1
        }
        else {
            $cached | Sort-Object CachedOn -Descending | Select-Object -First 1
        }
        if (-not $entry) { throw "No cached schema for $name after Get-TerraformProviderSchema -SaveToCache." }
        $harvested = $stopwatch.Elapsed

        $slug = Split-Path -Path (Split-Path -Path $entry.Path -Parent) -Leaf
        $file = "$slug.$($entry.Version).json.gz"
        $target = Join-Path $dist $file
        Copy-Item -LiteralPath $entry.Path -Destination $target -ErrorAction Stop

        $graph = ConvertTo-TerraformSchemaGraph -Provider $entry.ProviderAddress -Version $entry.Version -ErrorAction Stop
        $summary = $graph.Summary
        $stopwatch.Stop()

        [ordered]@{
            kind            = 'schema'
            address         = $entry.ProviderAddress
            version         = $entry.Version
            file            = $file
            sha256          = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes           = (Get-Item -LiteralPath $target).Length
            nodeCount       = $graph.NodeCount
            resourceCount   = [int]$summary['Resource']
            dataSourceCount = [int]$summary['DataSource']
        }
        Write-Host ("{0} {1}: {2:N0} bytes, {3:N0} nodes, {4} resources, {5} data sources; harvest {6:mm\:ss}, total {7:mm\:ss}" -f
            $entry.ProviderAddress, $entry.Version, (Get-Item -LiteralPath $target).Length, $graph.NodeCount,
            [int]$summary['Resource'], [int]$summary['DataSource'], $harvested, $stopwatch.Elapsed)

        # Docs for the same provider version, matched against the schema just cached.
        $docs = Update-TerraformProviderDocCache -Provider $entry.ProviderAddress -Version $entry.Version -Force -PassThru -ErrorAction Stop
        $docFile = "docs.$slug.$($entry.Version).json.gz"
        $docTarget = Join-Path $dist $docFile
        Copy-Item -LiteralPath $docs.Path -Destination $docTarget -ErrorAction Stop
        $docBytes = (Get-Item -LiteralPath $docTarget).Length
        [ordered]@{
            kind           = 'docs'
            address        = $entry.ProviderAddress
            version        = $entry.Version
            file           = $docFile
            sha256         = (Get-FileHash -LiteralPath $docTarget -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes          = $docBytes
            docCount       = $docs.DocCount
            unmatchedCount = $docs.UnmatchedCount
        }
        $unmatched = @(Get-TerraformProviderDoc -Provider $entry.ProviderAddress -Version $entry.Version -Id '*/unmatched/*' | ForEach-Object { "$($_.Category)/$($_.Slug)" })
        Write-Host ("{0} {1} docs: {2} pages, {3} unmatched, {4:N0} bytes; harvest {5:mm\:ss}{6}" -f
            $entry.ProviderAddress, $entry.Version, $docs.DocCount, $docs.UnmatchedCount, $docBytes, $docs.Elapsed,
            $(if ($unmatched.Count) { "; unmatched e.g. $(@($unmatched | Select-Object -First 5) -join ', ')" }))
    }

    $manifest = [ordered]@{
        builtOn = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        packs   = [object[]]@($packs)
    }
    $manifest | ConvertTo-TerraformJson | Set-Content -LiteralPath (Join-Path $dist 'manifest.json') -Encoding utf8NoBOM -ErrorAction Stop
    $total.Stop()
    Write-Host "Wrote $(@($packs).Count) packs (schema and docs) and manifest.json to $dist in $($total.Elapsed)"
}

# Not part of the default build. Run after BuildSchemaPack when cutting a release, then
# stage src/Graph.Emitter.Terraform/classifiers: writes each -Provider's classifier
# (<address-slug>.<version>.json) at its latest version in the registry cache from the
# local schema and docs caches with classifiers/map.json, and prints the findings per
# provider. No network. Unlike dist/, these files are committed: they ship with the module.
task BuildClassifier RemoveModule, ImportModule, {
    $out = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'classifiers'
    foreach ($name in $Provider) {
        $found = @(Get-TerraformRegistryProvider -Name $name -WarningAction SilentlyContinue)
        if ($found.Count -gt 1) {
            throw "'$name' matches $($found.Count) providers in the registry cache: $(@($found.Source) -join ', '). Use namespace/name."
        }
        $classifierArgs = @{ Provider = $name; OutputPath = $out; PassThru = $true; ErrorAction = 'Stop' }
        if ($found.Count -eq 1 -and $found[0].Latest) {
            $classifierArgs.Provider = $found[0].ProviderAddress
            $classifierArgs.Version = [string]$found[0].Latest
        }
        else {
            Write-Warning "$name is not in the registry cache; classifying its newest cached schema."
        }
        $result = New-TerraformClassifier @classifierArgs
        Write-Host ("{0} {1} (docs {2}): {3}, {4} types, {5} findings -> {6}" -f
            $result.ProviderAddress, $result.Version, $result.DocsVersion, $result.Status, $result.TypeCount, $result.FindingCount, (Split-Path -Path $result.Path -Leaf))
        Write-Host "  drawers: $(@($result.Drawers.Keys | ForEach-Object { "$_ $($result.Drawers[$_])" }) -join ', ')"
        $findings = @(Get-TerraformClassifierFinding -Provider $result.ProviderAddress -Version $result.Version -ClassifierPath $result.Path)
        if ($findings.Count) {
            $findings | Group-Object Finding, Subcategory | Sort-Object Name |
                Format-Table @{ Name = 'Finding'; Expression = { $_.Group[0].Finding } }, @{ Name = 'Subcategory'; Expression = { $_.Group[0].Subcategory } }, Count -AutoSize |
                Out-String -Width 200 | Write-Host
        }
    }
}

# Not part of the default build. Run when cutting a release, after BuildSchemaPack and
# BuildClassifier, then stage src/Graph.Emitter.Terraform/data/bundle.json: harvests the docs of every
# provider in the bundled manifest (data/bundle.json: the official tier plus
# microsoft/azuredevops and vmware/vsphere, resolved against data/registry.json) at its
# latest version, one provider after another (network; 30-60 minutes at throttle 6),
# refreshes the manifest's entries from the caches and the bundled classifiers, and writes
# the subcategory survey to dist/survey/subcategories.json. A provider that fails is a
# warning and a Failed row, never a stop. -Resume skips providers already cached at their
# latest version and continues a provider from its <version>.partial.json. The run writes
# $env:LOCALAPPDATA\TerraformGraph\logs\harvest-<timestamp>.log and prints its path.
task HarvestBundleDocs RemoveModule, ImportModule, {
    $bundlePath = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'data' 'bundle.json'
    $summary = Update-TerraformProviderDocCache -BundlePath $bundlePath -Resume:$Resume -ErrorAction Stop
    $summary.Providers |
        Format-Table ProviderAddress, Version, Status, DocCount, UnmatchedCount, SchemaVersion, @{ Name = 'Elapsed'; Expression = { $_.Elapsed.ToString('hh\:mm\:ss') } } -AutoSize |
        Out-String -Width 250 | Write-Host
    Write-Host ("Providers {0}, pages {1:N0}, unmatched {2}, failures {3}, rate-limit hits {4} ({5} s blocked), partial resumes {6}, elapsed {7:hh\:mm\:ss}" -f
        $summary.ProviderCount, $summary.PageCount, $summary.UnmatchedCount, $summary.FailureCount,
        $summary.RateLimitHits, $summary.SecondsBlocked, $summary.PartialResumes, $summary.Elapsed)
    Write-Host "Log: $($summary.LogPath)"
    foreach ($failure in $summary.Failures) {
        Write-Host "FAILED $($failure.ProviderAddress) $($failure.Version): $($failure.Error)" -ForegroundColor Yellow
    }

    $bundle = Get-TerraformGraphBundle -Path $bundlePath -Document -ErrorAction Stop
    New-TerraformGraphBundle -Tier $bundle.Tiers -Provider $bundle.Providers -Exclude $bundle.Exclude -OutputPath $bundlePath -ErrorAction Stop
    Write-Host "Refreshed $bundlePath"

    $surveyPath = Join-Path $PSScriptRoot 'dist' 'survey' 'subcategories.json'
    Get-TerraformSubcategorySurvey -BundlePath $bundlePath -OutputPath $surveyPath -ErrorAction Stop
    $survey = Get-Content -LiteralPath $surveyPath -Raw | ConvertFrom-TerraformJson
    Write-Host ("Survey: {0} providers ({1} missing), {2} distinct labels, {3} rows, {4} providers with unlabelled pages -> {5}" -f
        $survey.summary.providerCount, $survey.summary.missingCount, $survey.summary.labelCount, $survey.summary.rowCount,
        $survey.summary.noSubcategoryProviderCount, $surveyPath)
    $survey.labels | Select-Object -First 20 subcategory, providerCount, resourceCount, dataSourceCount |
        Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}

# Not part of the default build. The release gate: Test-TerraformGraphBundle -Scope Repo
# -Strict on the bundled manifest. Repo scope reads only src/ (data/registry.json beside the
# bundle, the bundled classifiers and map.json) and dist/schema-packs, never the user caches,
# so it certifies the checkout rather than this machine (DECISIONS 51). Prints the rows that
# are not Fresh and fails if there are any. -Online also checks the live registry.
task CheckBundle RemoveModule, ImportModule, {
    $bundlePath = Join-Path $PSScriptRoot 'src' 'Graph.Emitter.Terraform' 'data' 'bundle.json'
    $counts = @{ Fresh = 0; Stale = 0; Missing = 0 }
    Test-TerraformGraphBundle -BundlePath $bundlePath -DistPath (Join-Path $PSScriptRoot 'dist' 'schema-packs') -Scope Repo -Online:$Online -Strict -ErrorAction Stop |
        ForEach-Object {
            $counts[$_.Status]++
            if ($_.Status -ne 'Fresh') {
                Write-Host "$($_.Status.PadRight(7)) $($_.Item): $($_.Detail)" -ForegroundColor Yellow
                Write-Host "        inspect: $($_.InspectAction)"
                Write-Host "        fix:     $($_.RecommendedAction)"
            }
        }
    Write-Host "Bundle is fresh: $($counts.Fresh) checks (-Scope Repo)." -ForegroundColor Green
}

# A zip of the assembled module tree, for hand installs: dist/Graph.Emitter.Terraform.<version>.zip.
task Package AssembleModule, {
    $tree = Join-Path $PSScriptRoot 'dist' 'module' 'Graph.Emitter.Terraform'
    $zipPath = Join-Path $PSScriptRoot 'dist' "Graph.Emitter.Terraform.$(Get-ManifestVersion).zip"
    Compress-Archive -Path $tree -DestinationPath $zipPath -Force
    Write-Host "Module packaged: $zipPath" -ForegroundColor Green
}

# main only, clean tree, drawers semver test passing. Tags the psd1 ModuleVersion as
# v<version> (annotated) and pushes main and the tag. Bump ModuleVersion in a commit first:
# the task refuses a version that is not above the newest v* tag.
task Release {
    Assert-ReleaseReady
    Invoke-Git fetch, origin, '--tags'

    $version = Get-ManifestVersion
    $latest = Get-LatestReleaseTag
    if ($latest -and $version -le $latest) {
        throw "ModuleVersion $version is not above the newest tag v$latest. Raise ModuleVersion in Graph.Emitter.Terraform.psd1 (and CHANGELOG.md), commit, then rerun Release."
    }
    $tag = "v$version"
    Invoke-Git tag, -a, $tag, -m, "Release $version"
    Invoke-Git push, origin, main
    Invoke-Git push, origin, $tag
    Write-Host "Tagged $tag on main and pushed it. Then: Invoke-Build Publish, and gh release create $tag with dist/schema-packs/*." -ForegroundColor Green
}

# main only, clean tree, drawers semver test passing. Publishes dist/module/Graph.Emitter.Terraform (the
# assembled tree, never src/) with Publish-PSResource. The key comes from
# $env:PSGALLERY_API_KEY, else a prompt.
task Publish AssembleModule, {
    Assert-ReleaseReady

    if (-not $env:PSGALLERY_API_KEY) {
        $secure = Read-Host "PowerShell Gallery API key" -AsSecureString
        if (-not $secure -or $secure.Length -eq 0) {
            throw "A PowerShell Gallery API key is required."
        }
        $env:PSGALLERY_API_KEY = [System.Net.NetworkCredential]::new('', $secure).Password
        Write-Host "PSGALLERY_API_KEY is set for this process only." -ForegroundColor Yellow
    }
    else {
        Write-Host "Using existing PSGALLERY_API_KEY from the environment." -ForegroundColor Yellow
    }

    $tree = Join-Path $PSScriptRoot 'dist' 'module' 'Graph.Emitter.Terraform'
    Publish-PSResource -Path $tree -Repository PSGallery -ApiKey $env:PSGALLERY_API_KEY -ErrorAction Stop
    Write-Host "Published Graph.Emitter.Terraform $(Get-ManifestVersion) to the PowerShell Gallery." -ForegroundColor Green
}

task . Test
