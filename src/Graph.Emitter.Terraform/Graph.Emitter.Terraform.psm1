# Graph.Emitter.Terraform module wiring. Function code lives one function per file, the file named for
# the function: Public/<Verb-Noun>.ps1 for the exported commands, Private/<Verb-Noun>.ps1 for
# the helpers, Classes/ for any class or enum. To change a function, edit the file named for
# it, never this one. This file holds only what runs at import: module-scope state, the parser
# and JSON assembly loads, type data and argument completers, then the dot-source of those
# folders and the calls that need the functions. Invoke-Build AssembleModule builds the single
# psm1 that ships (dist/module/Graph.Emitter.Terraform) by splicing the files into the region below.

# The HCL parser is a Go c-shared DLL built for Windows x64 only. Anywhere else (or when the
# DLL was never built) the module still imports: the parser commands throw ParserUnavailable
# and every schema, registry, docs, classifier and bundle command works without it.
$dllPath = Join-Path $PSScriptRoot 'lib' 'TerraformGraph.dll'
$script:TerraformGraphParserAvailable = $false
$script:TerraformGraphParserUnavailableReason = $null
$processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
if (-not ($IsWindows -and $processArchitecture -eq [System.Runtime.InteropServices.Architecture]::X64)) {
    $platform = "$([System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()) $processArchitecture"
    $script:TerraformGraphParserUnavailableReason = "Graph.Emitter.Terraform's HCL parser ships for Windows x64 only; $platform detected. Schema, registry, docs, classifier and bundle commands work without it."
}
elseif (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    $script:TerraformGraphParserUnavailableReason = "Graph.Emitter.Terraform's HCL parser is not built: $dllPath does not exist. Build it with Invoke-Build BuildDLL (needs Docker). Schema, registry, docs, classifier and bundle commands work without it."
}
else {
    # UTF-8 both ways: Go reads the path and returns the JSON as UTF-8 (CharSet.Ansi would
    # decode it with the Windows code page and mangle every non-ASCII character).
    $signature = @"
    [DllImport(@"$dllPath", EntryPoint = "ParseHCL", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr ParseHCL([MarshalAs(UnmanagedType.LPUTF8Str)] string filePath);

    [DllImport(@"$dllPath", EntryPoint = "FreeString", CallingConvention = CallingConvention.Cdecl)]
    public static extern void FreeString(IntPtr str);
"@
    # Utf8Parser, not HCLParser: a session that imported 0.14.0 still holds the old ANSI type.
    if (-not ('TerraformGraph.Utf8Parser' -as [type])) {
        Add-Type -MemberDefinition $signature -Name Utf8Parser -Namespace TerraformGraph
    }
    $script:TerraformGraphParserAvailable = $true
}

# TerraformGraph.Json: the precompiled lib/TerraformGraph.Json.dll (Invoke-Build BuildJson)
# when it is there and loads, else compiled from source (about half a second per import).
if (-not ('TerraformGraph.Json' -as [type])) {
    $jsonAssembly = Join-Path $PSScriptRoot 'lib' 'TerraformGraph.Json.dll'
    $jsonLoaded = $false
    if (Test-Path -LiteralPath $jsonAssembly -PathType Leaf) {
        try {
            Add-Type -LiteralPath $jsonAssembly -ErrorAction Stop
            $jsonLoaded = $true
        }
        catch {
            Write-Verbose "Graph.Emitter.Terraform: $jsonAssembly did not load ($($_.Exception.Message)); compiling TerraformGraph.Json.cs instead."
        }
    }
    if (-not $jsonLoaded) {
        Add-Type -LiteralPath (Join-Path $PSScriptRoot 'TerraformGraph.Json.cs')
    }
}

# Default view: Type, Name, Line, Column, File.
# Everything else is still on the object — use Format-List * or Select-Object *.
$blockTypeName = 'TerraformGraph.Block'
Update-TypeData -TypeName $blockTypeName -DefaultDisplayPropertySet Type, Name, Line, Column, File -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName Name -Value {
    if ($this.Labels) { $this.Labels -join '.' }
} -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName Line -Value {
    $this.TypeRange.Start.Line
} -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName Column -Value {
    $this.TypeRange.Start.Column
} -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName File -Value {
    if ($this.TypeRange.Filename) {
        Split-Path -Path $this.TypeRange.Filename -Leaf
    }
} -Force

# Module graph views. Every property stays on the object; these only pick the table columns.
# ModuleNode and ModuleEdge have more than four columns, so their table views are in Graph.Emitter.Terraform.Format.ps1xml.
Update-TypeData -TypeName 'TerraformGraph.ModuleNode' -DefaultDisplayPropertySet Id, Kind, SourceKind, Depth, Resolved, Dir -Force
Update-TypeData -TypeName 'TerraformGraph.ModuleEdge' -DefaultDisplayPropertySet From, To, Kind, Call, File, Line -Force

$moduleGraphTypeName = 'TerraformGraph.ModuleGraph'
Update-TypeData -TypeName $moduleGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $moduleGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $moduleGraphTypeName -MemberType ScriptProperty -MemberName UnresolvedCount -Value {
    @($this.Unresolved).Count
} -Force
Update-TypeData -TypeName $moduleGraphTypeName -DefaultDisplayPropertySet Root, GroupBy, NodeCount, EdgeCount, UnresolvedCount -Force

# Schema graph views.
Update-TypeData -TypeName 'TerraformGraph.SchemaNode' -DefaultDisplayPropertySet Kind, Path, Type, Required, Depth -Force

$schemaGraphTypeName = 'TerraformGraph.SchemaGraph'
Update-TypeData -TypeName $schemaGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $schemaGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $schemaGraphTypeName -MemberType ScriptProperty -MemberName Summary -Value {
    # Kinds in a fixed order; only kinds present in the graph.
    $counts = @{}
    foreach ($node in $this.Nodes) { $counts[$node.Kind] = 1 + [int]$counts[$node.Kind] }
    $summary = [ordered]@{}
    foreach ($kind in 'Provider', 'Resource', 'DataSource', 'Function', 'Block', 'Attribute') {
        if ($counts.ContainsKey($kind)) { $summary[$kind] = $counts[$kind] }
    }
    $summary
} -Force
Update-TypeData -TypeName $schemaGraphTypeName -DefaultDisplayPropertySet Providers, NodeCount, EdgeCount -Force

# Variable graph views.
Update-TypeData -TypeName 'TerraformGraph.VariableNode' -DefaultDisplayPropertySet Kind, Module, Name, Binding, Literal -Force
Update-TypeData -TypeName 'TerraformGraph.VariableTraceNode' -DefaultDisplayPropertySet Distance, Kind, Module, Name, Binding, Literal -Force

$variableGraphTypeName = 'TerraformGraph.VariableGraph'
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName UnresolvedCount -Value {
    @($this.Unresolved).Count
} -Force
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName Summary -Value {
    # Kinds in a fixed order; only kinds present in the graph.
    $counts = @{}
    foreach ($node in $this.Nodes) { $counts[$node.Kind] = 1 + [int]$counts[$node.Kind] }
    $summary = [ordered]@{}
    foreach ($kind in 'Variable', 'Local', 'Output') {
        if ($counts.ContainsKey($kind)) { $summary[$kind] = $counts[$kind] }
    }
    $summary
} -Force
Update-TypeData -TypeName $variableGraphTypeName -DefaultDisplayPropertySet Root, NodeCount, EdgeCount, UnresolvedCount -Force

# Resource graph views.
Update-TypeData -TypeName 'TerraformGraph.ResourceNode' -DefaultDisplayPropertySet Kind, ResourceAddress, ProviderAddress, SchemaMatched, Reason -Force

$resourceGraphTypeName = 'TerraformGraph.ResourceGraph'
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName MatchedCount -Value {
    @($this.Nodes | Where-Object SchemaMatched).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName UnmatchedCount -Value {
    @($this.Nodes | Where-Object { -not $_.SchemaMatched }).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName Findings -Value {
    @($this.Nodes | Where-Object { @($_.UnknownAttributes).Count -or @($_.UnknownBlocks).Count -or @($_.MissingRequired).Count }).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -DefaultDisplayPropertySet Root, NodeCount, MatchedCount, UnmatchedCount, Findings -Force

# Provider registry cache. The user file wins over the bundled one; tests point these at
# fixtures with InModuleScope. Nothing below touches the network except
# Update-TerraformRegistryCache.
$script:TerraformRegistrySource = 'registry.terraform.io'
$script:TerraformRegistryBundledPath = Join-Path $PSScriptRoot 'data' 'registry.json'
$script:TerraformRegistryUserCachePath = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'registry.json'
$script:TerraformRegistryCacheMemo = $null
$script:TerraformRegistryTierRank = @{ official = 0; partner = 1; community = 2 }

Update-TypeData -TypeName 'TerraformGraph.RegistryProvider' -DefaultDisplayPropertySet ProviderAddress, Tier, Latest, VersionCount -Force
Update-TypeData -TypeName 'TerraformGraph.RegistryCache' -DefaultDisplayPropertySet Path, HarvestedOn, Scope, ProviderCount, VersionCount, Elapsed -Force

# Registry rate state: one per process (module scope), shared by every registry call site:
# the registry cache harvest, the docs harvest, version lookups and Test-TerraformGraphBundle
# -Online. registry.terraform.io sits behind an AWS WAF rate-based rule: once a sustained run
# passes its limit, every request from the address gets 429 with x-amzn-waf-reason: rate-limit
# and no Retry-After, for minutes. A block was observed once, at about 22:06 local time on
# 2026-10-06 (05:06Z on 2026-10-07), lifting about 9 minutes later. It was not logged (the
# harvest log came in 0.14.0), so the numbers below are a working assumption, not a
# measurement:
#   - The first 429 stops every worker (Blocked, a flag the parallel workers read before each
#     request), the run sleeps one step of the ladder, then resumes with one worker.
#   - Ladder 30, 60, 120, 240, 300 s: one step per block, reset by any success. The five steps
#     sum to 750 s, past the observed 9-minute block; a request that gets a sixth 429 fails.
#   - Retry-After, when the registry sends one, replaces the step. Any single wait is capped
#     at 600 s, the observed block rounded up to 10 minutes: a longer Retry-After is not one a
#     harvest should sit through silently, so it waits 600 s and lets the next 429 decide.
#   - After a block, one worker is added per N = 25 successful requests, up to the caller's
#     ThrottleLimit. At one worker a docs page takes about 0.3 s, so 25 is roughly 10 s of
#     evidence the block has lifted before the load doubles, and climbing from 1 to 6 costs
#     125 requests (under a minute) against a 9-minute block that a fast climb would trigger
#     again.
#   - 5xx is retried inside the request after 2, 4, 8, 16 and 32 s and never touches this
#     state: a server error is not a rate limit.
# The state outlives the call, so the second provider of a bundle run (or the next command in
# the same session) starts as throttled as the first one left it. Reset-TerraformRegistryThrottle
# starts over; tests call it, and inject $script:TerraformRegistryInvoker, a scriptblock that
# stands in for Invoke-TerraformRegistryHttp and returns @{ StatusCode; Content; RetryAfter }.
$script:TerraformRegistryBackoffSeconds = @(30, 60, 120, 240, 300)
$script:TerraformRegistryMaxWaitSeconds = 600
$script:TerraformRegistryClimbAfter = 25
# Requests per ForEach-Object -Parallel invocation while not throttled: big enough that
# runspace start-up is noise, small enough that a 429 stops the run within one chunk.
$script:TerraformRegistryChunkSize = 50
$script:TerraformRegistryInvoker = $null
$script:TerraformRegistryThrottle = $null

# Harvest logs: Update-TerraformProviderDocCache -BundlePath writes one line per provider and
# one per 429 to <root>\harvest-<yyyyMMdd-HHmmss>.log. Tests repoint the root.
$script:TerraformGraphLogRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'logs'
$script:TerraformGraphLogPath = $null

# Argument completers read the cache only and never throw.
$script:TerraformRegistryProviderCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        $cache = Get-TerraformRegistryCache -NoBundledData:([bool]$fakeBoundParameters['NoBundledData'])
        if (-not $cache) { return }
        $word = ([string]$wordToComplete).Trim('''', '"')
        $pattern = "$([WildcardPattern]::Escape($word))*"
        foreach ($provider in Select-TerraformRegistryProvider -Cache $cache -ByTier) {
            if ($provider.Name -like $pattern -or $provider.Source -like $pattern -or $provider.ProviderAddress -like $pattern) {
                [System.Management.Automation.CompletionResult]::new($provider.Source, $provider.Source, 'ParameterValue',
                    "$($provider.ProviderAddress) ($($provider.Tier), latest $($provider.Latest))")
            }
        }
    }
    catch { }
}

$script:TerraformRegistryVersionCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        $name = [string]$fakeBoundParameters['Provider']
        if (-not $name) { return }
        $cache = Get-TerraformRegistryCache -NoBundledData:([bool]$fakeBoundParameters['NoBundledData'])
        if (-not $cache) { return }
        $provider = if ([WildcardPattern]::ContainsWildcardCharacters($name)) {
            $found = @(Select-TerraformRegistryProvider -Cache $cache -Name $name)
            if ($found.Count -eq 1) { $found[0] }
        }
        else {
            $address = (ConvertTo-TerraformProviderAddress -Provider $name).Address
            $cache.Providers | Where-Object ProviderAddress -eq $address | Select-Object -First 1
        }
        if (-not $provider) { return }
        $word = ([string]$wordToComplete).Trim('''', '"')
        foreach ($version in $provider.Versions) {
            if ([string]$version.version -like "$([WildcardPattern]::Escape($word))*") {
                [System.Management.Automation.CompletionResult]::new($version.version, $version.version, 'ParameterValue',
                    "$($version.version) (published $($version.published))")
            }
        }
    }
    catch { }
}

Register-ArgumentCompleter -CommandName Get-TerraformProviderSchema -ParameterName Provider -ScriptBlock $script:TerraformRegistryProviderCompleter
Register-ArgumentCompleter -CommandName Get-TerraformProviderSchema -ParameterName Version -ScriptBlock $script:TerraformRegistryVersionCompleter
Register-ArgumentCompleter -CommandName Get-TerraformRegistryProvider -ParameterName Name -ScriptBlock $script:TerraformRegistryProviderCompleter

# Provider schema and docs caches: one gzipped document per provider version, at
# <root>\<address-slug>\<version>.json.gz, where address-slug is the lowercase address with
# '/' -> '-'. The schema root is ...\schemas, the docs root ...\docs; the helpers below take
# -Kind Schema|Docs to pick one. Nothing is bundled. Get-TerraformSchemaPack,
# Get-TerraformDocPack, Get-TerraformProviderSchema -SaveToCache and
# Update-TerraformProviderDocCache write them; everything else only reads them. Tests repoint
# both roots with InModuleScope. Save-TerraformSchemaPackFile is the only pack network call.
$script:TerraformSchemaCacheRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'schemas'
$script:TerraformDocCacheRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'docs'
$script:TerraformSchemaPackSource = 'https://github.com/JerryBalmer1/Graph.Emitter.Terraform/releases/latest/download'

Update-TypeData -TypeName 'TerraformGraph.SchemaPack' -DefaultDisplayPropertySet ProviderAddress, Version, Status, Bytes -Force
Update-TypeData -TypeName 'TerraformGraph.DocPack' -DefaultDisplayPropertySet ProviderAddress, Version, Status, Bytes -Force
Update-TypeData -TypeName 'TerraformGraph.CachedSchema' -DefaultDisplayPropertySet ProviderAddress, Version, Bytes, CachedOn -Force
Update-TypeData -TypeName 'TerraformGraph.CachedDoc' -DefaultDisplayPropertySet ProviderAddress, Version, DocCount, UnmatchedCount, Bytes -Force

# Provider docs: the registry's markdown pages for a provider version, keyed on the schema
# node Id they document, in the docs cache (<docs root>\<address-slug>\<version>.json.gz).
# Update-TerraformProviderDocCache harvests from the registry and Get-TerraformDocPack
# downloads packs; Get-TerraformProviderDoc and Get-TerraformDocCache only read the cache.
# Doc Ids:
#   <address>                    overview
#   <address>/guide/<slug>       guides
#   <address>/resource/<type>    resources (the schema Resource node Id)
#   <address>/data/<type>        data-sources (the schema DataSource node Id)
#   <address>/unmatched/<category>/<slug>  a resource or data source page whose type is not
#                                in the cached schema
$script:TerraformDocCategories = @('overview', 'guides', 'resources', 'data-sources')
$script:TerraformDocCacheMemo = @{}
# Pages between checkpoints of a docs harvest (M). Each checkpoint rewrites every page fetched
# so far, so for aws (about 2,700 pages) M = 100 means 27 rewrites, and a run killed outright
# loses at most 100 pages, well under a minute at 6 workers. An interrupted run (a failed page,
# Ctrl+C) also writes one on the way out, so M only matters when the process dies.
$script:TerraformDocCheckpointPages = 100

Update-TypeData -TypeName 'TerraformGraph.ProviderDoc' -DefaultDisplayPropertySet Id, Category, Title, Subcategory -Force
Update-TypeData -TypeName 'TerraformGraph.DocCache' -DefaultDisplayPropertySet ProviderAddress, Version, Status, DocCount, UnmatchedCount, Elapsed -Force

Register-ArgumentCompleter -CommandName Update-TerraformProviderDocCache -ParameterName Provider -ScriptBlock $script:TerraformRegistryProviderCompleter
Register-ArgumentCompleter -CommandName Update-TerraformProviderDocCache -ParameterName Version -ScriptBlock $script:TerraformRegistryVersionCompleter

# Classifier drawers: an optional overlay that groups resource and data source types into
# drawers (network, compute, storage, ...) so a view can collapse. Classifiers are opinions
# layered on facts: they never change a node's Id, the node count or the edges.
#   classifiers\drawers.json     the fixed drawer list map rows target
#   classifiers\map.json         provider subcategory label -> drawer, every row with a reason
#   classifiers\DECISIONS.md     append-only record of every judgement behind the two above
#   <root>\<address-slug>.<version>.json  one provider version's classifier, written by
#                                New-TerraformClassifier from the schema and docs caches
# Classifier lookup order: -ClassifierPath, then the user root, then the root bundled with
# the module; the first root that holds a provider wins. Nothing here touches the network.
# Tests repoint both roots with InModuleScope; the drawer list and default map paths stay.
$script:TerraformClassifierBundledRoot = Join-Path $PSScriptRoot 'classifiers'
$script:TerraformClassifierDrawersPath = Join-Path $PSScriptRoot 'classifiers' 'drawers.json'
$script:TerraformClassifierMapPath = Join-Path $PSScriptRoot 'classifiers' 'map.json'
$script:TerraformClassifierUserRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'classifiers'

Update-TypeData -TypeName 'TerraformGraph.Classifier' -DefaultDisplayPropertySet ProviderAddress, Version, DocsVersion, TypeCount, FindingCount -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifiedType' -DefaultDisplayPropertySet Type, Kind, Subcategory, Drawer -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifierFinding' -DefaultDisplayPropertySet Type, Kind, Subcategory, Finding -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifierBuild' -DefaultDisplayPropertySet ProviderAddress, Version, Status, TypeCount, FindingCount -Force
Update-TypeData -TypeName 'TerraformGraph.DrawerSummary' -DefaultDisplayPropertySet Drawer, TypeCount, InstanceCount -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifierShadow' -DefaultDisplayPropertySet ProviderAddress, Version, Location, Reason -Force

$script:TerraformClassifierMapVersionMemo = $null

Register-ArgumentCompleter -CommandName New-TerraformClassifier -ParameterName Provider -ScriptBlock $script:TerraformRegistryProviderCompleter

# Bundle manifest: data\bundle.json names the provider set the bundled data covers (registry
# tiers, extra provider addresses, exclusions), the registry cache it was resolved against,
# and one entry per provider recording what the local docs and schema caches and the bundled
# classifiers held when it was written:
#   { formatVersion, tiers, providers, exclude, registry: { harvestedOn, providerCount },
#     entries: [ { provider, version, docsVersion, schemaVersion, classifierVersion, harvestedOn } ] }
# New-TerraformGraphBundle writes one, Update-TerraformProviderDocCache -BundlePath and
# Get-TerraformSubcategorySurvey -BundlePath read its provider set, and
# Test-TerraformGraphBundle checks it against its sources. A bundle resolves against the
# registry.json in its own folder (data\registry.json for the bundled file), else the registry
# cache Get-TerraformRegistryCache returns. Tests repoint both paths with InModuleScope.
$script:TerraformGraphBundleBundledPath = Join-Path $PSScriptRoot 'data' 'bundle.json'
$script:TerraformGraphBundleUserPath = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'bundle.json'
$script:TerraformGraphBundleFormatVersion = 1
$script:TerraformGraphBundleTiers = @('official', 'partner', 'community')

Update-TypeData -TypeName 'TerraformGraph.Bundle' -DefaultDisplayPropertySet Path, Tiers, Providers, Exclude, RegistryHarvestedOn, EntryCount, PackedEntryCount, RegistryOnlyEntryCount -Force
Update-TypeData -TypeName 'TerraformGraph.BundleEntry' -DefaultDisplayPropertySet ProviderAddress, Version, DocsVersion, SchemaVersion, ClassifierVersion, HarvestedOn -Force
Update-TypeData -TypeName 'TerraformGraph.BundleCheck' -DefaultDisplayPropertySet Item, Status, RecommendedAction -Force
Update-TypeData -TypeName 'TerraformGraph.BundleSource' -DefaultDisplayPropertySet Kind, HarvestedBy, LastPulled, Urls -Force

# The sources block of a bundle: one entry per bundled data kind, naming the upstream
# endpoints it is pulled from (urls), the pages that explain them (relatedUrls), the
# function that pulls it (harvestedBy) and when it last was (lastPulled, computed by
# New-TerraformGraphBundleSource). The registry's v2 API has no published reference; its
# endpoints are listed as probed (see Get-TerraformRegistryHarvest and
# Get-TerraformProviderDocHarvest). cmdb is reserved: no harvester yet, so every field but
# kind is empty.
$script:TerraformGraphBundleSources = @(
    [ordered]@{
        kind        = 'registry'
        urls        = @(
            'https://registry.terraform.io/v2/providers?filter[tier]=official,partner&page[size]=100'
            'https://registry.terraform.io/v1/providers/{namespace}/{name}/versions'
            'https://registry.terraform.io/v2/providers/{namespace}/{name}?include=provider-versions'
        )
        relatedUrls = @(
            'https://developer.hashicorp.com/terraform/internals/provider-registry-protocol'
            'https://developer.hashicorp.com/terraform/registry/providers'
        )
        harvestedBy = 'Update-TerraformRegistryCache'
    }
    [ordered]@{
        kind        = 'schemas'
        urls        = @(
            'https://github.com/JerryBalmer1/Graph.Emitter.Terraform/releases/latest/download/manifest.json'
        )
        relatedUrls = @(
            'https://developer.hashicorp.com/terraform/cli/commands/providers/schema'
            'https://developer.hashicorp.com/terraform/cli/commands/init'
        )
        harvestedBy = 'Get-TerraformProviderSchema'
    }
    [ordered]@{
        kind        = 'docs'
        urls        = @(
            'https://registry.terraform.io/v2/provider-versions/{id}?include=provider-docs'
            'https://registry.terraform.io/v2/provider-docs/{id}'
        )
        relatedUrls = @(
            'https://developer.hashicorp.com/terraform/registry/providers/docs'
        )
        harvestedBy = 'Update-TerraformProviderDocCache'
    }
    [ordered]@{
        kind        = 'classifiers'
        urls        = @(
            'https://github.com/JerryBalmer1/Graph.Emitter.Terraform/tree/main/src/Graph.Emitter.Terraform/classifiers'
        )
        relatedUrls = @(
            'https://github.com/JerryBalmer1/Graph.Emitter.Terraform/blob/main/src/Graph.Emitter.Terraform/classifiers/DECISIONS.md'
        )
        harvestedBy = 'New-TerraformClassifier'
    }
    [ordered]@{
        kind        = 'skills'
        urls        = @(
            'https://github.com/JerryBalmer1/Graph.Emitter.Terraform/tree/main/src/Graph.Emitter.Terraform/skills'
        )
        relatedUrls = @(
            'https://agentskills.io'
            'https://agentskills.io/specification'
        )
        harvestedBy = 'Install-TerraformGraphSkill'
    }
    [ordered]@{
        kind        = 'cmdb'
        urls        = @()
        relatedUrls = @()
        harvestedBy = $null
    }
)
Update-TypeData -TypeName 'TerraformGraph.DocHarvestSummary' -DefaultDisplayPropertySet ProviderCount, PageCount, UnmatchedCount, FailureCount, RateLimitHits, Elapsed -Force
Update-TypeData -TypeName 'TerraformGraph.SubcategorySurveyRow' -DefaultDisplayPropertySet ProviderAddress, Subcategory, ResourceCount, DataSourceCount, Status -Force

# Agent tools that read project skills: the project-relative folder skills are copied
# into, and the path whose presence means the tool is used in a repo. These paths are
# the convention as of 2026-10; this table is the only place to correct them.
$script:TerraformGraphSkillTools = [ordered]@{
    Claude  = @{ SkillsDir = '.claude/skills'; Marker = '.claude' }
    Codex   = @{ SkillsDir = '.codex/skills';  Marker = '.codex' }
    Cursor  = @{ SkillsDir = '.cursor/skills'; Marker = '.cursor' }
    Gemini  = @{ SkillsDir = '.gemini/skills'; Marker = '.gemini' }
    Copilot = @{ SkillsDir = '.github/skills'; Marker = '.github/copilot-instructions.md' }
}

# Skill views. SkillPath is long, so it comes last.
Update-TypeData -TypeName 'TerraformGraph.SkillInstall' -DefaultDisplayPropertySet Tool, Status, Files, SkillPath -Force
Update-TypeData -TypeName 'TerraformGraph.SkillStatus' -DefaultDisplayPropertySet Tool, Detected, Installed, Stale, SkillPath -Force

# The canonical skills shipped with the module; Install-TerraformGraphSkill copies this folder.
$script:TerraformGraphSkillSource = Join-Path $PSScriptRoot 'skills'

# Function code: Classes, Private, Public, one function per file. Invoke-Build AssembleModule
# (tools/Copy-TerraformGraphModule.ps1) replaces this region with the files' contents, in this
# order, so the shipped psm1 dot-sources nothing.
#region Graph.Emitter.Terraform source files
foreach ($terraformGraphSourceFolder in 'Classes', 'Private', 'Public') {
    $terraformGraphSourceFolder = Join-Path $PSScriptRoot $terraformGraphSourceFolder
    if (-not (Test-Path -LiteralPath $terraformGraphSourceFolder -PathType Container)) { continue }
    foreach ($terraformGraphSourceFile in Get-ChildItem -LiteralPath $terraformGraphSourceFolder -Filter '*.ps1' -File | Sort-Object Name) {
        . $terraformGraphSourceFile.FullName
    }
}
Remove-Variable -Name terraformGraphSourceFolder, terraformGraphSourceFile, foreach -ErrorAction SilentlyContinue
#endregion Graph.Emitter.Terraform source files

# At import, once the functions exist: the registry rate state starts empty, the psd1 list is
# exported, and the skill hint prints its one line (or nothing).
Reset-TerraformRegistryThrottle

Export-ModuleMember -Function (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Graph.Emitter.Terraform.psd1')).FunctionsToExport

Show-TerraformGraphSkillHint
