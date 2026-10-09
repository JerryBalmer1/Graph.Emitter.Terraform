function ConvertTo-TerraformResourceGraph {
    <#
    .SYNOPSIS
        Builds an inventory of resources and data sources and joins it to provider schemas.

    .DESCRIPTION
        ConvertTo-TerraformResourceGraph reads the blocks Get-TerraformModuleGraph already
        parsed and returns one TerraformGraph.ResourceGraph. Every resource and data block in
        every parsed module becomes a TerraformGraph.ResourceNode with its Terraform address,
        the provider it resolves to and the schema node it should be an instance of
        (SchemaId). Nothing is parsed again.

        With -SchemaGraph, each node is joined to the schema: a node whose SchemaId is in one
        of the schema graphs gets SchemaMatched $true and one InstanceOf edge to it, and its
        top-level arguments are checked against the schema. UnknownAttributes lists
        arguments the schema does not declare, UnknownBlocks lists nested blocks it does not
        declare (a dynamic block is checked by its label), and MissingRequired lists required
        attributes and blocks with min_items of 1 or more that the block does not set. Only
        the top level of each block is checked; the contents of nested blocks are not.

        Instead of -SchemaGraph, -Provider builds the schema graphs from the local schema
        cache for the named providers, and -AutoSchema loads from the cache whatever
        providers the module graph resolves to. Neither downloads anything.

        An unmatched node has a Reason: NoSchemaGraph when no schema was given (no
        -SchemaGraph, -Provider or -AutoSchema), ProviderNotInSchemaGraph when no schema
        graph has its provider, TypeNotInProvider when the provider is there but has no
        such resource or data source type.

        Module nodes whose Blocks are $null (not parsed without -Recurse, unresolved, or
        Cycle) contribute nothing and are listed in Skipped.

    .PARAMETER ModuleGraph
        A TerraformGraph.ModuleGraph from Get-TerraformModuleGraph. Use -Recurse there to
        include every module in the tree.

    .PARAMETER SchemaGraph
        Zero or more TerraformGraph.SchemaGraph objects from ConvertTo-TerraformSchemaGraph,
        from one call or several. Their nodes are indexed by Id together, so a configuration
        that uses several providers can be checked against one graph per provider. When
        omitted, every node gets SchemaMatched $false and Reason NoSchemaGraph.

    .PARAMETER Provider
        Providers to load from the local schema cache instead of passing -SchemaGraph, as
        ConvertTo-TerraformSchemaGraph -Provider does: patterns match by shape and may use
        wildcards, and the newest cached version of each is used. A pattern with no cached
        schema is a terminating error that names Get-TerraformSchemaPack and
        Get-TerraformProviderSchema -SaveToCache.

    .PARAMETER AutoSchema
        Load the schema of every provider address the module graph resolves to from the
        local schema cache (newest cached version), and leave the rest unmatched with
        Reason ProviderNotInSchemaGraph. Reads the cache only: never downloads and never
        runs terraform.

    .PARAMETER Classify
        Overlay classifier drawers (see New-TerraformClassifier). Every ResourceNode gets
        Drawer and Subcategory from its provider's classifier by type; a type the
        classifier lacks, or a provider with no classifier (one warning; built-in
        providers are skipped silently), is in the unclassified drawer. The graph gets
        Drawers: one TerraformGraph.DrawerSummary per drawer with TypeCount (distinct
        types) and InstanceCount (blocks). Ids, nodes and edges are exactly the same as
        without -Classify. Works in every parameter set and reads local files only.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before
        $env:LOCALAPPDATA\TerraformGraph\classifiers and the classifiers bundled with the
        module. Implies -Classify.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph
        $graph.Nodes
        $graph.Providers

        Inventory with no schema: every resource and data source with its address and
        resolved provider, and how many nodes each provider has.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schema
        $graph.Nodes | Where-Object { -not $_.SchemaMatched } | Format-Table ResourceAddress, ProviderAddress, Reason

        Join with the schema of an initialized directory and list the nodes that did not
        match, with the Reason. With only the built-in provider installed, null_resource and
        local_file show ProviderNotInSchemaGraph.

    .EXAMPLE
        $schemas = @(
            Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph
            Get-TerraformProviderSchema -Provider local -Cleanup | ConvertTo-TerraformSchemaGraph
        )
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schemas
        $graph.Nodes | Where-Object { $_.UnknownAttributes -or $_.UnknownBlocks -or $_.MissingRequired } |
            Format-List ResourceAddress, UnknownAttributes, UnknownBlocks, MissingRequired

        Join with two schema graphs fetched on demand and show the nodes counted in
        Findings.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema
        $graph.Nodes | Format-Table ResourceAddress, ProviderAddress, SchemaMatched, Reason

        Join with whatever schemas the local cache holds for the providers infra uses;
        providers that are not cached show ProviderNotInSchemaGraph.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema -Classify
        $graph.Drawers
        $graph.Nodes | Sort-Object Drawer | Format-Table Drawer, Subcategory, ResourceAddress

        How many resource types and blocks a configuration has per drawer, then every block
        with its drawer.

    .OUTPUTS
        TerraformGraph.ResourceGraph with Root, Nodes, Edges, Skipped and Providers (ordered
        ProviderAddress -> node count), plus NodeCount, EdgeCount, MatchedCount,
        UnmatchedCount and Findings (nodes with any UnknownAttributes, UnknownBlocks or
        MissingRequired). Default view is Root, NodeCount, MatchedCount, UnmatchedCount,
        Findings. With -Classify, Drawers is a TerraformGraph.DrawerSummary array and each
        node has Drawer and Subcategory. Nodes are TerraformGraph.ResourceNode (default view Kind, ResourceAddress,
        ProviderAddress, SchemaMatched, Reason), edges TerraformGraph.ResourceEdge.

    .NOTES
        Id scheme, where <module> is the ModuleAddress ('root' for the root module):
            Resource    <module>/resource/<type>.<name>
            DataSource  <module>/data/<type>.<name>
        SchemaId is <ProviderAddress>/resource/<type> or <ProviderAddress>/data/<type>, the
        ConvertTo-TerraformSchemaGraph Id, and is set even when it does not match.

        Provider resolution, per module: the local name is the type up to its first
        underscore (aws_instance -> aws), or the part of a provider = <name>.<alias>
        argument before the dot, which also sets ProviderAlias. The local name maps to an
        address through that module's own terraform { required_providers } sources. A
        local name not declared there is terraform.io/builtin/terraform for 'terraform',
        otherwise registry.terraform.io/hashicorp/<name>. A child module does not inherit
        its parent's required_providers, as in Terraform.

        Only top-level attributes and blocks are checked. The meta-arguments count,
        for_each, provider, depends_on, lifecycle, connection and provisioner are never
        unknown, and lifecycle, connection and provisioner blocks are not checked.

    .LINK
        Get-TerraformModuleGraph

    .LINK
        ConvertTo-TerraformSchemaGraph

    .LINK
        Get-TerraformSchemaCache

    .LINK
        https://github.com/JerryBalmer1/Graph.Emitter.Terraform
    #>
    [CmdletBinding(DefaultParameterSetName = 'SchemaGraph')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $ModuleGraph,

        [Parameter(ParameterSetName = 'SchemaGraph')]
        [object[]]
        $SchemaGraph,

        [Parameter(Mandatory, ParameterSetName = 'Provider')]
        [ValidateScript({
            if (-not [WildcardPattern]::ContainsWildcardCharacters($_)) {
                $null = ConvertTo-TerraformProviderAddress -Provider $_
            }
            $true
        })]
        [string[]]
        $Provider,

        [Parameter(Mandatory, ParameterSetName = 'AutoSchema')]
        [switch]
        $AutoSchema,

        [switch]
        $Classify,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    begin {
        $classifyGraph = $Classify -or $PSBoundParameters.ContainsKey('ClassifierPath')
        # Address -> cached schema version for -Provider and -AutoSchema, so -Classify
        # prefers the classifier generated from the same version.
        $schemaVersions = @{}
        $metaAttributes = 'count', 'for_each', 'provider', 'depends_on', 'lifecycle', 'connection', 'provisioner'
        $metaBlocks = 'lifecycle', 'connection', 'provisioner', 'dynamic'

        # Every schema node by Id, the provider addresses present, and the direct children
        # of each Resource and DataSource node in schema order. Built once for all input;
        # -AutoSchema adds to it as module graphs name new providers.
        $schemaById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $schemaProviders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $schemaChildren = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::Ordinal)
        $addSchemaGraph = {
            param($Graph)
            foreach ($node in @($Graph.Nodes)) {
                $schemaById[[string]$node.Id] = $node
                if ($node.Kind -eq 'Provider') { $null = $schemaProviders.Add([string]$node.Id) }
                $parent = $null
                if ($null -ne $node.ParentId -and $schemaById.TryGetValue([string]$node.ParentId, [ref]$parent) -and
                    $parent.Kind -in 'Resource', 'DataSource') {
                    if (-not $schemaChildren.ContainsKey($parent.Id)) {
                        $schemaChildren[$parent.Id] = [System.Collections.Generic.List[object]]::new()
                    }
                    $schemaChildren[$parent.Id].Add($node)
                }
            }
        }

        switch ($PSCmdlet.ParameterSetName) {
            'SchemaGraph' {
                $hasSchema = @($SchemaGraph | Where-Object { $null -ne $_ }).Count -gt 0
                foreach ($graph in @($SchemaGraph)) {
                    if ($null -ne $graph) { & $addSchemaGraph $graph }
                }
            }
            'Provider' {
                $hasSchema = $true
                try {
                    $cached = @(Resolve-TerraformSchemaCacheProvider -Name $Provider)
                }
                catch {
                    Stop-TerraformGraphCommand -Id 'SchemaNotCached' -Category ObjectNotFound -Target $Provider -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
                }
                foreach ($item in $cached) { $schemaVersions[$item.ProviderAddress] = $item.Version }
                & $addSchemaGraph (ConvertTo-TerraformSchemaGraph -Schema (Get-TerraformSchemaCacheDocument -Entry $cached) -ErrorAction Stop)
            }
            'AutoSchema' {
                # Every provider counts as looked up, so an uncached one is ProviderNotInSchemaGraph.
                $hasSchema = $true
                $autoTried = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
    }

    process {
        $nodes = [System.Collections.Generic.List[object]]::new()
        $edges = [System.Collections.Generic.List[object]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $providers = [ordered]@{}

        if ($AutoSchema) {
            # Provider addresses this module graph resolves to, then the newest cached schema
            # of each one not looked up yet. Cache reads only; nothing is downloaded.
            $needed = [System.Collections.Generic.List[string]]::new()
            foreach ($module in @($ModuleGraph.Nodes)) {
                if ($null -eq $module.Blocks) { continue }
                $blocks = @($module.Blocks)
                $declared = Get-TerraformModuleProviderMap -Blocks $blocks -ModuleAddress ([string]$module.ModuleAddress)
                foreach ($block in $blocks) {
                    if ($block.Type -notin 'resource', 'data') { continue }
                    $providerAddress = (Resolve-TerraformBlockProvider -Block $block -Declared $declared).ProviderAddress
                    if ($autoTried.Add($providerAddress)) { $needed.Add($providerAddress) }
                }
            }
            if ($needed.Count) {
                $entries = @(Get-TerraformSchemaCacheEntry)
                $found = foreach ($providerAddress in $needed) {
                    $entry = $entries | Where-Object ProviderAddress -eq $providerAddress | Select-Object -First 1
                    if ($entry) { $entry } else { Write-Verbose "No cached schema for $providerAddress" }
                }
                if ($found) {
                    Write-Verbose "Loading cached schemas: $(@($found | ForEach-Object { "$($_.ProviderAddress) $($_.Version)" }) -join ', ')"
                    foreach ($item in @($found)) { $schemaVersions[$item.ProviderAddress] = $item.Version }
                    & $addSchemaGraph (ConvertTo-TerraformSchemaGraph -Schema (Get-TerraformSchemaCacheDocument -Entry @($found)) -ErrorAction Stop)
                }
            }
        }

        foreach ($module in @($ModuleGraph.Nodes)) {
            $address = [string]$module.ModuleAddress
            if ($null -eq $module.Blocks) {
                $skipped.Add($address)
                continue
            }
            $blocks = @($module.Blocks)

            # Local name -> provider address from this module's own required_providers.
            $declared = Get-TerraformModuleProviderMap -Blocks $blocks -ModuleAddress $address

            # Resource and data blocks in source order: file, then line.
            $sorted = [System.Collections.Generic.List[object]]::new()
            foreach ($block in $blocks) { if ($block.Type -in 'resource', 'data') { $sorted.Add($block) } }
            $sorted.Sort([System.Comparison[object]] {
                    param($a, $b)
                    $byFile = [string]::CompareOrdinal([string]$a.File, [string]$b.File)
                    if ($byFile) { return $byFile }
                    ([int]$a.Line).CompareTo([int]$b.Line)
                })

            foreach ($block in $sorted) {
                $isData = $block.Type -eq 'data'
                $kind = $isData ? 'DataSource' : 'Resource'
                $segment = $isData ? 'data' : 'resource'
                $type = [string]$block.Labels[0]
                $name = [string]$block.Labels[1]
                $attributes = $block.Body.Attributes

                $resolved = Resolve-TerraformBlockProvider -Block $block -Declared $declared
                $localName = $resolved.LocalName
                $alias = $resolved.Alias
                $providerAddress = $resolved.ProviderAddress
                $providers[$providerAddress] = 1 + [int]$providers[$providerAddress]

                $id = "$address/$segment/$type.$name"
                $schemaId = "$providerAddress/$segment/$type"
                $terraformAddress = ($isData ? 'data.' : '') + "$type.$name"
                if ($address -ne 'root') { $terraformAddress = "$address.$terraformAddress" }

                $reason = if (-not $hasSchema) { 'NoSchemaGraph' }
                elseif (-not $schemaProviders.Contains($providerAddress)) { 'ProviderNotInSchemaGraph' }
                elseif (-not $schemaById.ContainsKey($schemaId)) { 'TypeNotInProvider' }
                $matched = $null -eq $reason

                $unknownAttributes = [System.Collections.Generic.List[string]]::new()
                $unknownBlocks = [System.Collections.Generic.List[string]]::new()
                $missingRequired = [System.Collections.Generic.List[string]]::new()
                if ($matched) {
                    $children = $null
                    if (-not $schemaChildren.TryGetValue($schemaId, [ref]$children)) { $children = @() }
                    $childByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
                    foreach ($child in $children) { $childByName[[string]$child.Name] = $child }

                    # Attributes in source order (the parser keys them by name).
                    $setAttributes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    if ($null -ne $attributes) {
                        foreach ($attribute in @($attributes.PSObject.Properties.Value) | Sort-Object { $_.SrcRange.Start.Byte }) {
                            $attributeName = [string]$attribute.Name
                            $null = $setAttributes.Add($attributeName)
                            if ($metaAttributes -ccontains $attributeName) { continue }
                            $child = $null
                            if (-not ($childByName.TryGetValue($attributeName, [ref]$child) -and $child.Kind -eq 'Attribute')) {
                                $unknownAttributes.Add($attributeName)
                            }
                        }
                    }

                    # A dynamic "x" block stands for an x block.
                    $setBlocks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    foreach ($nested in @($block.Body.Blocks)) {
                        if ($null -eq $nested) { continue }
                        $blockName = [string]$nested.Type
                        if ($blockName -ceq 'dynamic') { $blockName = [string]$nested.Labels[0] }
                        elseif ($metaBlocks -ccontains $blockName) { continue }
                        $null = $setBlocks.Add($blockName)
                        $child = $null
                        $known = $childByName.TryGetValue($blockName, [ref]$child) -and (
                            $child.Kind -eq 'Block' -or
                            ($child.Kind -eq 'Attribute' -and $null -ne (Get-TerraformSchemaMember -InputObject $child.Raw -Name 'nested_type')))
                        if (-not $known -and -not $unknownBlocks.Contains($blockName)) { $unknownBlocks.Add($blockName) }
                    }

                    foreach ($child in $children) {
                        $childName = [string]$child.Name
                        if ($child.Kind -eq 'Attribute' -and $child.Required -and -not $setAttributes.Contains($childName)) {
                            $missingRequired.Add($childName)
                        }
                        elseif ($child.Kind -eq 'Block' -and [int]$child.MinItems -ge 1 -and -not $setBlocks.Contains($childName)) {
                            $missingRequired.Add($childName)
                        }
                    }

                    $edges.Add([pscustomobject]@{
                        PSTypeName = 'TerraformGraph.ResourceEdge'
                        From       = $id
                        To         = $schemaId
                        Kind       = 'InstanceOf'
                    })
                }

                $nodes.Add([pscustomobject]@{
                    PSTypeName        = 'TerraformGraph.ResourceNode'
                    Id                = $id
                    Kind              = $kind
                    Module            = $address
                    Type              = $type
                    Name              = $name
                    ResourceAddress   = $terraformAddress
                    ProviderLocalName = $localName
                    ProviderAlias     = $alias
                    ProviderAddress   = $providerAddress
                    SchemaId          = $schemaId
                    SchemaMatched     = $matched
                    Reason            = $reason
                    UnknownAttributes = $unknownAttributes.ToArray()
                    UnknownBlocks     = $unknownBlocks.ToArray()
                    MissingRequired   = $missingRequired.ToArray()
                    File              = $block.File
                    Line              = $block.Line
                    Block             = $block
                })
            }
        }

        $result = [pscustomobject]@{
            PSTypeName = 'TerraformGraph.ResourceGraph'
            Root       = $ModuleGraph.Root
            Nodes      = $nodes.ToArray()
            Edges      = $edges.ToArray()
            Skipped    = $skipped.ToArray()
            Providers  = $providers
        }
        if ($classifyGraph) {
            Add-TerraformResourceGraphClassification -Graph $result -Version $schemaVersions -ClassifierPath $ClassifierPath
        }
        $result
    }
}
