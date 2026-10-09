function ConvertTo-TerraformSchemaGraph {
    <#
    .SYNOPSIS
        Converts a provider schema into a graph of canonical schema nodes.

    .DESCRIPTION
        ConvertTo-TerraformSchemaGraph walks the output of Get-TerraformProviderSchema and
        returns one TerraformGraph.SchemaGraph per input document. Every provider, resource,
        data source, block and attribute becomes a TerraformGraph.SchemaNode, and every
        node other than a provider gets one Contains edge from its parent. The provider's
        own configuration block (provider_schemas[address].provider.block) becomes
        Attribute and Block nodes directly under the Provider node, with /config/ in
        their Id and Paths such as aws.region.

        Each node has two names. Id is canonical and unique within the document: it starts
        with the full provider address and adds one segment per level, such as
        registry.terraform.io/hashicorp/null/resource/null_resource/triggers. Use it to
        join nodes and edges. Path is the short dotted form a configuration author writes,
        such as null_resource.triggers. It drops the provider, so two providers can share
        a Path; it is for reading and filtering, not for joins.

        Attributes declared with nested_type are rendered as the type they imply and also
        get child Attribute nodes, exactly like block_types get child nodes, so the graph
        has the same shape whether a provider used blocks or nested attributes.

        Nodes are ordered depth-first and the same input always gives the same order:
        each provider, then its configuration attributes (sorted) and blocks (sorted)
        and their subtrees, then its resources sorted by type, each followed by its
        attributes (sorted) and blocks (sorted) and their subtrees, then data sources,
        then functions.

    .PARAMETER Schema
        The provider schema document. Accepts the ordered dictionary Get-TerraformProviderSchema
        returns by default, the -OutputFormat Json text (piped lines are joined), or that text
        passed through ConvertFrom-TerraformJson. It must have a top-level provider_schemas.

        Without -Schema, -Provider names providers to load from the local schema cache
        instead (see Get-TerraformSchemaPack and Get-TerraformProviderSchema -SaveToCache).
        The cached documents are combined and converted exactly as if that document had
        been piped in, giving one graph.

    .PARAMETER Provider
        With -Schema: only include these providers: 'aws', 'hashicorp/aws', or
        'registry.terraform.io/hashicorp/aws', normalized the same way as
        Get-TerraformProviderSchema -Provider. Matched against the provider_schemas keys
        without regard to case. A provider that is not in the document is a terminating
        error that lists the providers that are. Default: every provider in the document.
        Wildcards are not allowed with -Schema.

        Without -Schema: the cached providers to load. Patterns match by shape, as in
        Get-TerraformSchemaCache: 'azurerm' or 'azure*' match the bare name in any
        namespace, 'hashicorp/azure*' namespace/name, and a full address the address. A
        wildcard can match several providers; a name without one that matches cached
        providers in several namespaces must be the hashicorp one or is an error. A
        pattern with no cached schema is a terminating error that names
        Get-TerraformSchemaPack and Get-TerraformProviderSchema -SaveToCache.

    .PARAMETER Version
        Without -Schema: the cached version to load for every -Provider. Default: the
        newest cached version of each.

    .PARAMETER IncludeFunctions
        Add provider functions (the functions map in newer schemas) as Function nodes
        under their provider. Off by default.

    .PARAMETER Classify
        Overlay classifier drawers (see New-TerraformClassifier). Every SchemaNode gets
        Drawer and Subcategory: Resource and DataSource nodes from their provider's
        classifier, their Block and Attribute descendants the same values as the type they
        belong to, Provider, provider config and Function nodes $null. A type the
        classifier lacks, or a provider with no classifier (one warning), is in the
        unclassified drawer. The graph gets Drawers: one TerraformGraph.DrawerSummary per
        drawer (Drawer, TypeCount, InstanceCount empty). Ids, nodes and edges are exactly
        the same as without -Classify. Reads local files only.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before
        $env:LOCALAPPDATA\TerraformGraph\classifiers and the classifiers bundled with the
        module. Implies -Classify.

    .EXAMPLE
        Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph

        Fetch the hashicorp/null schema and convert it. The default view is Providers,
        NodeCount and EdgeCount.

    .EXAMPLE
        $graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph -Provider aws
        $graph.Nodes | Where-Object Path -like 'aws_s3_bucket.*'

        Keep only registry.terraform.io/hashicorp/aws out of a directory that uses several
        providers, then list one resource's attributes and blocks.

    .EXAMPLE
        $graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
        $graph.Summary
        $graph.Nodes | Where-Object Kind -eq 'Resource' | Select-Object Path, Id

        Count nodes by Kind, then list every resource with its canonical Id.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider hashicorp/azurerm
        ConvertTo-TerraformSchemaGraph -Provider azurerm

        Download the azurerm schema pack into the local cache once, then build the graph
        from the cache with no terraform and no network.

    .EXAMPLE
        $graph = ConvertTo-TerraformSchemaGraph -Provider vsphere -Classify
        $graph.Drawers
        $graph.Nodes | Where-Object { $_.Kind -eq 'Resource' -and $_.Drawer -eq 'storage' } | Select-Object Path, Subcategory

        Group the cached vsphere schema into drawers with the bundled classifier, then list
        the storage resources.

    .OUTPUTS
        TerraformGraph.SchemaGraph. Default view is Providers, NodeCount, EdgeCount; Summary
        is an ordered Kind -> count table; with -Classify, Drawers is a
        TerraformGraph.DrawerSummary array. Nodes are TerraformGraph.SchemaNode (default view
        Kind, Path, Type, Required, Depth), edges TerraformGraph.SchemaEdge.

    .NOTES
        Id scheme, where <address> is the provider_schemas key:
            Provider    <address>
            Config      <address>/config/<name>  (Attribute or Block; Path <provider>.<name>)
            Resource    <address>/resource/<type>
            DataSource  <address>/data/<type>
            Function    <address>/function/<name>
            Block       <parent Id>/<block name>
            Attribute   <parent Id>/<attribute name>

    .LINK
        Get-TerraformProviderSchema

    .LINK
        Get-TerraformSchemaPack

    .LINK
        https://github.com/JerryBalmer1/Graph.Emitter.Terraform
    #>
    # Cache is the default set so that -Provider alone binds to it; piped or positional
    # -Schema still selects Document.
    [CmdletBinding(DefaultParameterSetName = 'Cache')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ParameterSetName = 'Document')]
        [object]
        $Schema,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(Mandatory, ParameterSetName = 'Cache')]
        [ValidateScript({
            # A wildcard is matched against the schema cache in the body.
            if (-not [WildcardPattern]::ContainsWildcardCharacters($_)) {
                $null = ConvertTo-TerraformProviderAddress -Provider $_
            }
            $true
        })]
        [string[]]
        $Provider,

        [Parameter(ParameterSetName = 'Cache')]
        [string]
        $Version,

        [switch]
        $IncludeFunctions,

        [switch]
        $Classify,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    begin {
        $classifyGraph = $Classify -or $PSBoundParameters.ContainsKey('ClassifierPath')
        # Address -> schema version, when the graph comes from the cache, so -Classify
        # prefers the classifier generated from the same version.
        $schemaVersions = @{}
        $wanted = @()
        if ($PSCmdlet.ParameterSetName -eq 'Document') {
            $wildcards = @($Provider | Where-Object { [WildcardPattern]::ContainsWildcardCharacters($_) })
            if ($wildcards.Count) {
                Stop-TerraformGraphCommand -Id 'SchemaProviderWildcard' -Category InvalidArgument -Target $wildcards -ExceptionType ([System.ArgumentException]) -Message "Provider '$($wildcards -join "', '")' has a wildcard. Wildcards are only allowed without -Schema, where -Provider reads the schema cache: ConvertTo-TerraformSchemaGraph -Provider '$($wildcards[0])'."
            }
            $wanted = @(foreach ($p in $Provider) { (ConvertTo-TerraformProviderAddress -Provider $p).Address })
        }
        $jsonLines = [System.Collections.Generic.List[string]]::new()

        $convert = {
            param($Document)

            $providerSchemas = Get-TerraformSchemaMember -InputObject $Document -Name 'provider_schemas'
            if ($null -eq $providerSchemas) {
                Stop-TerraformGraphCommand -Id 'SchemaMissingProviderSchemas' -Category InvalidData -Target $Document -ExceptionType ([System.ArgumentException]) -Message 'Schema has no top-level provider_schemas. Pass the output of Get-TerraformProviderSchema, its -OutputFormat Json text, or that text through ConvertFrom-TerraformJson.'
            }

            $addresses = @(Get-TerraformSchemaKeys -InputObject $providerSchemas -Sort)
            if ($wanted.Count) {
                $missing = @($wanted | Where-Object { $addresses -notcontains $_ })
                if ($missing.Count) {
                    $available = if ($addresses.Count) { $addresses -join ', ' } else { '(none)' }
                    Stop-TerraformGraphCommand -Id 'SchemaProviderNotFound' -Category ObjectNotFound -Target $missing -ExceptionType ([System.ArgumentException]) -Message "Provider '$($missing -join "', '")' is not in provider_schemas. Available: $available. Fetch it with Get-TerraformProviderSchema -Provider $($missing[0]) -SaveToCache, then ConvertTo-TerraformSchemaGraph -Provider $($missing[0])."
                }
                $addresses = @($addresses | Where-Object { $wanted -contains $_ })
            }

            $graph = [pscustomobject]@{
                Nodes    = [System.Collections.Generic.List[object]]::new()
                Edges    = [System.Collections.Generic.List[object]]::new()
                Classify = $classifyGraph
            }
            $overlay = if ($classifyGraph) { Get-TerraformClassifierOverlay -Address $addresses -Version $schemaVersions -ClassifierPath $ClassifierPath }

            foreach ($address in $addresses) {
                $entry = Get-TerraformSchemaMember -InputObject $providerSchemas -Name $address
                $config = Get-TerraformSchemaMember -InputObject (Get-TerraformSchemaMember -InputObject $entry -Name 'provider') -Name 'block'
                $shortName = $address.Split('/')[-1]

                $providerNode = [pscustomobject]@{
                    PSTypeName    = 'TerraformGraph.SchemaNode'
                    Id            = $address
                    Kind          = 'Provider'
                    Name          = $shortName
                    Path          = $shortName
                    Provider      = $address
                    ParentId      = $null
                    Depth         = 0
                    Description   = Get-TerraformSchemaMember -InputObject $config -Name 'description'
                    Deprecated    = [bool](Get-TerraformSchemaMember -InputObject $config -Name 'deprecated')
                    SchemaVersion = $null
                    NestingMode   = $null
                    MinItems      = $null
                    MaxItems      = $null
                    Type          = $null
                    TypeJson      = $null
                    Required      = $null
                    Optional      = $null
                    Computed      = $null
                    Sensitive     = $null
                    WriteOnly     = $null
                    Raw           = $entry
                }
                if ($classifyGraph) {
                    $providerNode.PSObject.Properties.Add([psnoteproperty]::new('Drawer', $null))
                    $providerNode.PSObject.Properties.Add([psnoteproperty]::new('Subcategory', $null))
                }
                $graph.Nodes.Add($providerNode)
                Add-TerraformSchemaChildNodes -Graph $graph -Container $config -Parent $providerNode -Segment config

                $lookup = if ($classifyGraph) { $overlay.ByAddress[$address] }
                foreach ($section in @(
                        @{ Key = 'resource_schemas';    Kind = 'Resource';   ClassifierKind = 'resource' }
                        @{ Key = 'data_source_schemas'; Kind = 'DataSource'; ClassifierKind = 'data-source' }
                    )) {
                    $schemas = Get-TerraformSchemaMember -InputObject $entry -Name $section.Key
                    foreach ($type in Get-TerraformSchemaKeys -InputObject $schemas -Sort) {
                        $resource = Get-TerraformSchemaMember -InputObject $schemas -Name $type
                        $block = Get-TerraformSchemaMember -InputObject $resource -Name 'block'
                        # -Classify: a type the classifier lacks, or a provider with none, is unclassified.
                        $classified = $null
                        if ($lookup) { $null = $lookup.TryGetValue("$($section.ClassifierKind)|$type", [ref]$classified) }
                        $node = New-TerraformSchemaNode -Graph $graph -Kind $section.Kind -Name $type -Parent $providerNode -Raw $resource `
                            -Description (Get-TerraformSchemaMember -InputObject $block -Name 'description') `
                            -Deprecated ([bool](Get-TerraformSchemaMember -InputObject $block -Name 'deprecated')) `
                            -SchemaVersion (Get-TerraformSchemaMember -InputObject $resource -Name 'version') `
                            -Drawer $(if ($classified) { $classified.Drawer } else { 'unclassified' }) `
                            -Subcategory $(if ($classified) { $classified.Subcategory } else { $null })
                        Add-TerraformSchemaChildNodes -Graph $graph -Container $block -Parent $node
                    }
                }

                if ($IncludeFunctions) {
                    $functions = Get-TerraformSchemaMember -InputObject $entry -Name 'functions'
                    foreach ($name in Get-TerraformSchemaKeys -InputObject $functions -Sort) {
                        $function = Get-TerraformSchemaMember -InputObject $functions -Name $name
                        $null = New-TerraformSchemaNode -Graph $graph -Kind Function -Name $name -Parent $providerNode -Raw $function `
                            -Description (Get-TerraformSchemaMember -InputObject $function -Name 'description') `
                            -Deprecated ($null -ne (Get-TerraformSchemaMember -InputObject $function -Name 'deprecation_message'))
                    }
                }
            }

            $result = [pscustomobject]@{
                PSTypeName = 'TerraformGraph.SchemaGraph'
                Providers  = [string[]]$addresses
                Nodes      = $graph.Nodes.ToArray()
                Edges      = $graph.Edges.ToArray()
            }
            if ($classifyGraph) {
                $items = foreach ($node in $result.Nodes) {
                    if ($node.Kind -in 'Resource', 'DataSource') { [pscustomobject]@{ Drawer = $node.Drawer; TypeKey = $node.Id } }
                }
                $result.PSObject.Properties.Add([psnoteproperty]::new('Drawers', [object[]]@(New-TerraformDrawerSummary -Item @($items) -Order $overlay.Order)))
            }
            $result
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Cache') { return }
        # JSON text is collected and parsed once in end, so piped lines work.
        if ($Schema -is [string]) {
            $jsonLines.Add($Schema)
            return
        }
        & $convert $Schema
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Cache') {
            try {
                $cached = @(Resolve-TerraformSchemaCacheProvider -Name $Provider -Version $Version)
            }
            catch {
                Stop-TerraformGraphCommand -Id 'SchemaNotCached' -Category ObjectNotFound -Target $Provider -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
            }
            $wanted = @($cached.ProviderAddress)
            foreach ($item in $cached) { $schemaVersions[$item.ProviderAddress] = $item.Version }
            & $convert (Get-TerraformSchemaCacheDocument -Entry $cached)
            return
        }

        if ($jsonLines.Count -eq 0) { return }
        $document = ($jsonLines -join [Environment]::NewLine) | ConvertFrom-TerraformJson -AsHashtable -ErrorAction Stop
        & $convert $document
    }
}
