function Get-TerraformModuleGraph {
    <#
    .SYNOPSIS
        Builds a graph of module calls for a Terraform root module.

    .DESCRIPTION
        Get-TerraformModuleGraph parses the root module directory with Get-TerraformAST
        (one directory, never its subtree), reads the source of every module block and
        resolves each call to a directory. Each call becomes a TerraformGraph.ModuleNode
        and an edge from its parent.

        Local sources (./ or ../) resolve against the calling module's directory.
        Registry, git, http, s3 and gcs sources resolve through
        .terraform/modules/modules.json in the root module. terraform init is never run.

        Without -Recurse only the root's direct calls are returned; their directories are
        resolved but not parsed. With -Recurse every resolved child is parsed and its own
        module calls are followed. Every call is its own node and is walked in full, even
        when another call already reached the same directory, because Keys and arguments
        differ per call.

        Calls that cannot be resolved stay in the graph with Resolved $false and a Reason:
        NonLiteralSource, LocalPathMissing or NotInitialized. They are also listed in
        Unresolved and Findings (the same list). A call whose Dir is already one of its
        own ancestors (root -> ... -> parent) keeps Resolved $true and its Dir, gets Reason
        Cycle and Blocks $null, and is not followed.

        Every node keeps Block, the module block from its parent's AST, so module
        arguments are available for later variable tracing.

        Every node has Id first and Kind ('Module') second; every edge has From, To and
        Kind ('Calls') first, then Call, Label, File (the bare file name of the module
        block) and Line.

    .PARAMETER Path
        Root module directory. Defaults to the current location.

    .PARAMETER Recurse
        Follow module calls beyond the root's direct children.

    .PARAMETER GroupBy
        Call (default) or Source. Sets each node's Id, and so the From and To of each
        edge. The root's Id is always 'root', and Ids are unique under both modes.

        Call: one node per module call, Id = ModuleAddress (module.network.module.endpoint).

        Source: one node per module source, Id = 'source:' + the normalised source. A local
        source is resolved against its caller's directory and written relative to the root
        with forward slashes (source:./modules/network/modules/endpoint), so two calls that
        reach the same directory share a node; a registry source is lowercased with any
        registry.terraform.io/ host dropped; any other source is trimmed. A call whose
        source is not a literal gets its own node, Id 'source:' + its ModuleAddress, with
        Resolved $false and Reason NonLiteralSource. Callers lists the ModuleAddress of
        every call a node stands for; the node keeps the first call's (breadth-first)
        Key, ModuleAddress, Name, Dir, Block and Blocks, and is Resolved $false, with that
        call's Reason, if any of its calls is unresolved. Edges stay one per call. Build
        ConvertTo-TerraformResourceGraph and ConvertTo-TerraformVariableGraph from a Call
        graph: they read one node per call, so a Source graph gives them only the first
        call to each source.

    .EXAMPLE
        Get-TerraformModuleGraph -Path .\infra

        Root module and its direct module calls, without parsing the children.

    .EXAMPLE
        (Get-TerraformModuleGraph -Path .\infra -Recurse).Nodes

        Every module call in the tree, parsed, with Depth and ParentKey.

    .EXAMPLE
        (Get-TerraformModuleGraph -Path .\infra -Recurse -GroupBy Source).Nodes |
            Format-Table Id, Callers

        One node per module source, with Callers naming the calls it stands for; edges
        stay one per call.

    .OUTPUTS
        TerraformGraph.ModuleGraph with Root, GroupBy, Recurse, Nodes, Edges, Unresolved
        and Findings. Default view is Root, GroupBy, NodeCount, EdgeCount, UnresolvedCount.
        Nodes are TerraformGraph.ModuleNode (table Id, Kind, SourceKind, Depth, Resolved,
        Dir), edges TerraformGraph.ModuleEdge (table From, To, Kind, Call, File, Line).

    .NOTES
        .terraform/modules/modules.json is read at most once, and only when the first
        non-local source is found. A configuration whose sources are all local never
        touches it and needs no terraform init. Non-local calls are looked up by Key
        (parent Key + '.' + label); if the file or the Key is missing the call is
        NotInitialized.

    .LINK
        Get-TerraformAST

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
                throw "Path '$_' is not an existing directory."
            }
            $true
        })]
        [string]
        $Path = './',

        [switch]
        $Recurse,

        [ValidateSet('Call', 'Source')]
        [string]
        $GroupBy = 'Call'
    )

    Assert-TerraformGraphParser
    $rootDir = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $modulesJsonPath = Join-Path $rootDir '.terraform' 'modules' 'modules.json'

    $nodes = [System.Collections.Generic.List[object]]::new()
    $edges = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()

    # Dirs on the path root -> ... -> node, keyed by node Key. A call is only refused
    # as a cycle when its Dir is already on its own chain, so a module called from two
    # places is walked once per call.
    $chains = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)

    # modules.json entries keyed by module Key. Loaded on the first non-local source.
    $manifest = $null

    # -GroupBy Source: the node already emitted for each Id. Later calls to the same
    # source add to its Callers instead of adding a node.
    $bySourceId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

    $root = [pscustomobject]@{
        PSTypeName    = 'TerraformGraph.ModuleNode'
        Id            = 'root'
        Kind          = 'Module'
        Name          = 'root'
        Key           = ''
        ModuleAddress = 'root'
        Source        = $null
        SourceKind    = 'Root'
        Dir           = $rootDir
        Resolved      = $true
        Reason        = $null
        ParentKey     = $null
        Depth         = 0
        Block         = $null
        Blocks        = @(Get-TerraformAST -Path $rootDir)
        Callers       = @()
    }
    $nodes.Add($root)
    $chains[''] = @($rootDir)
    $queue.Enqueue($root)

    while ($queue.Count -gt 0) {
        $parent = $queue.Dequeue()
        $parentChain = $chains[$parent.Key]

        foreach ($block in @($parent.Blocks | Where-Object Type -eq 'module')) {
            $label         = [string]$block.Labels[0]
            $key           = if ($parent.Key) { "$($parent.Key).$label" } else { $label }
            $moduleAddress = 'module.' + $key.Replace('.', '.module.')
            $source        = $null
            $dir           = $null
            $reason        = $null

            $expr = $block.Body.Attributes.source.Expr
            if ($expr -and $expr.IsLiteral) {
                $source = [string]$expr.Value
            }
            else {
                $reason = 'NonLiteralSource'
            }

            $sourceKind = Get-TerraformModuleSourceKind -Source $source

            if (-not $reason) {
                if ($sourceKind -eq 'Local') {
                    $candidate = Join-Path $parent.Dir $source
                    if (Test-Path -LiteralPath $candidate -PathType Container) {
                        $dir = (Resolve-Path -LiteralPath $candidate).ProviderPath
                    }
                    else {
                        $reason = 'LocalPathMissing'
                    }
                }
                else {
                    if ($null -eq $manifest) {
                        $manifest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
                        if (Test-Path -LiteralPath $modulesJsonPath -PathType Leaf) {
                            Write-Verbose "Reading $modulesJsonPath"
                            $installed = Get-Content -LiteralPath $modulesJsonPath -Raw | ConvertFrom-TerraformJson -ErrorAction Stop
                            foreach ($entry in @($installed.Modules)) {
                                $manifest[[string]$entry.Key] = $entry
                            }
                        }
                    }

                    $entry = $null
                    $candidate = $null
                    if ($manifest.TryGetValue($key, [ref]$entry) -and $entry.Dir) {
                        $candidate = Join-Path $rootDir $entry.Dir
                    }
                    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
                        $dir = (Resolve-Path -LiteralPath $candidate).ProviderPath
                    }
                    else {
                        $reason = 'NotInitialized'
                    }
                }
            }

            # Parse only with -Recurse, and never a Dir already on this call's own chain.
            $blocks = $null
            if ($dir) {
                if ($parentChain -contains $dir) {
                    $reason = 'Cycle'
                }
                elseif ($Recurse) {
                    Write-Verbose "Parsing $moduleAddress in $dir"
                    $blocks = @(Get-TerraformAST -Path $dir)
                }
            }

            $id = $moduleAddress
            if ($GroupBy -eq 'Source') {
                $normalised = if ($null -eq $source) {
                    $moduleAddress
                }
                elseif ($sourceKind -eq 'Local') {
                    # Lexical, so a missing directory still gets the same Id as its callers'.
                    $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($parent.Dir, $source)).TrimEnd('\', '/')
                    $relative = [System.IO.Path]::GetRelativePath($rootDir, $full).Replace('\', '/')
                    if ($relative -eq '.') { './' }
                    elseif ($relative -eq '..' -or $relative.StartsWith('../') -or [System.IO.Path]::IsPathRooted($relative)) { $relative }
                    else { "./$relative" }
                }
                elseif ($sourceKind -eq 'Registry') {
                    $parts = $source.Trim() -split '//', 2
                    $address = $parts[0].ToLowerInvariant() -replace '^registry\.terraform\.io/', ''
                    if ($parts.Count -gt 1) { "$address//$($parts[1])" } else { $address }
                }
                else {
                    $source.Trim()
                }
                $id = "source:$normalised"
            }

            $node = [pscustomobject]@{
                PSTypeName    = 'TerraformGraph.ModuleNode'
                Id            = $id
                Kind          = 'Module'
                Name          = $label
                Key           = $key
                ModuleAddress = $moduleAddress
                Source        = $source
                SourceKind    = $sourceKind
                Dir           = $dir
                Resolved      = $null -ne $dir
                Reason        = $reason
                ParentKey     = if ($parent.Key) { $parent.Key } else { $null }
                Depth         = $key.Split('.').Count
                Block         = $block
                Blocks        = $blocks
                Callers       = @($moduleAddress)
            }

            $existing = $null
            if ($GroupBy -eq 'Source' -and $bySourceId.TryGetValue($id, [ref]$existing)) {
                $existing.Callers = @($existing.Callers) + $moduleAddress
                if ($existing.Resolved -and -not $node.Resolved) {
                    $existing.Resolved = $false
                    $existing.Reason   = $node.Reason
                }
            }
            else {
                $bySourceId[$id] = $node
                $nodes.Add($node)
            }

            $edges.Add([pscustomobject]@{
                PSTypeName = 'TerraformGraph.ModuleEdge'
                From       = $parent.Id
                To         = $id
                Kind       = 'Calls'
                Call       = $moduleAddress
                Label      = $label
                File       = $block.File
                Line       = $block.Line
            })

            if ($blocks) {
                $chains[$key] = @($parentChain) + $dir
                $queue.Enqueue($node)
            }
        }
    }

    # Findings is the same list as Unresolved, under the name ResourceGraph uses.
    $unresolved = @($nodes | Where-Object { -not $_.Resolved })
    [pscustomobject]@{
        PSTypeName = 'TerraformGraph.ModuleGraph'
        Root       = $rootDir
        GroupBy    = $GroupBy
        Recurse    = $Recurse.IsPresent
        Nodes      = $nodes.ToArray()
        Edges      = $edges.ToArray()
        Unresolved = $unresolved
        Findings   = $unresolved
    }
}
