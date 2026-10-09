function ConvertTo-TerraformVariableGraph {
    <#
    .SYNOPSIS
        Builds a graph of variables, locals and outputs across a module tree.

    .DESCRIPTION
        ConvertTo-TerraformVariableGraph reads the blocks Get-TerraformModuleGraph already
        parsed and returns one TerraformGraph.VariableGraph. Every variable, every local
        (one per attribute of a locals block) and every output in every parsed module
        becomes a TerraformGraph.VariableNode. Nothing is parsed again.

        Edges follow values. A declaration whose expression reads var.x or local.x gets a
        Reference edge from that node. A module call argument a = expr gets an Argument
        edge from each var. or local. it reads in the calling module to the child's
        variable a. Reading module.c.o, in a declaration or a call argument, gets an
        OutputReference edge from the child's output o.

        Variables in a child module carry Binding: Argument when the parent's module call
        sets them (ArgumentExpr and ArgumentLiteral hold what it passed), Default when
        it does not and the variable has a default, Unset otherwise. Root variables are
        Default or Unset; their values come from tfvars or the command line, which this
        does not read.

        Module nodes whose Blocks are $null (not parsed without -Recurse, unresolved, or
        Cycle) contribute nothing and are listed in Skipped. Arguments to, and outputs
        of, a skipped module make no edges and are not reported as unresolved.

    .PARAMETER ModuleGraph
        A TerraformGraph.ModuleGraph from Get-TerraformModuleGraph. Use -Recurse there to
        include every module in the tree.

    .EXAMPLE
        Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph

        Variable graph for the whole infra tree. The default view is Root, NodeCount,
        EdgeCount and UnresolvedCount; Summary counts nodes by Kind.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        $graph.Unresolved | Where-Object Reason -eq 'UndeclaredArgument'

        List module call arguments that name a variable the child does not declare.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        $graph.Nodes | Where-Object Binding -eq 'Unset'

        Variables that no caller sets and that have no default: in the root they must
        come from tfvars or -var; in a child module Terraform rejects the call.

    .OUTPUTS
        TerraformGraph.VariableGraph with Root, Nodes, Edges, Unresolved and Skipped, plus
        NodeCount, EdgeCount, UnresolvedCount and Summary (ordered Kind -> count). Default
        view is Root, NodeCount, EdgeCount, UnresolvedCount. Nodes are
        TerraformGraph.VariableNode (default view Kind, Module, Name, Binding, Literal),
        edges TerraformGraph.VariableEdge.

    .NOTES
        Id scheme, where <module> is the ModuleAddress ('root' for the root module):
            Variable    <module>/var/<name>
            Local       <module>/local/<name>
            Output      <module>/output/<name>

        Only declaration expressions (variable default, local value, output value) and
        module call arguments are read; resource, data, check and other blocks make no
        edges. The module call meta-arguments source, version, count, for_each,
        providers and depends_on are not arguments.

        Every reference is listed on its node (References), but only roots that name a
        node make an edge: var.<name>, local.<name> and module.<call>.<output>. Index
        and attribute suffixes are dropped (var.tags["a"] binds var.tags) and kept in
        Via. Resources, data sources, path., terraform., each., count., self. and
        for-expression variables are references only, and so is a bare module.<call>,
        which names no single output.

        Unresolved records, each with Module, Root, Reason, File and Line:
            UndeclaredReference  var. or local. with no such node in its module
            UndeclaredArgument   a call argument the child does not declare
                                 (Module is the child, Root var.<argument>)
            UndeclaredOutput     module.<call>.<output> where the parsed child has no
                                 such output, or there is no such call

    .LINK
        Get-TerraformModuleGraph

    .LINK
        Get-TerraformVariableTrace

    .LINK
        https://github.com/JerryBalmer1/Graph.Emitter.Terraform
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $ModuleGraph
    )

    process {
        $metaArguments = 'source', 'version', 'count', 'for_each', 'providers', 'depends_on'

        $nodes = [System.Collections.Generic.List[object]]::new()
        $edges = [System.Collections.Generic.List[object]]::new()
        $unresolved = [System.Collections.Generic.List[object]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

        $leaf = { param($range) if ($range -and $range.Filename) { Split-Path -Path $range.Filename -Leaf } }
        # Literal value of an attribute, else its source text; $null when absent.
        $attributeValue = {
            param($attribute)
            if ($null -eq $attribute) { return $null }
            $literal = Get-TerraformExpressionLiteral -Expr $attribute.Expr
            if ($null -ne $literal) { return , $literal }
            $attribute.Expr.Raw
        }
        # Attributes of a body in source order (the parser keys them by name).
        $sortedAttributes = {
            param($body)
            if ($null -eq $body -or $null -eq $body.Attributes) { return }
            @($body.Attributes.PSObject.Properties.Value) | Sort-Object { $_.SrcRange.Start.Byte }
        }
        $childAddressOf = {
            param($address, $label)
            if ($address -eq 'root') { "module.$label" } else { "$address.module.$label" }
        }

        $moduleNodes = @($ModuleGraph.Nodes)
        $byAddress = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($module in $moduleNodes) { $byAddress[[string]$module.ModuleAddress] = $module }

        $newNode = {
            param($Kind, $Name, $Module, $File, $Line, $Expr, $Raw)
            $segment = @{ Variable = 'var'; Local = 'local'; Output = 'output' }[$Kind]
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.VariableNode'
                Id              = "$Module/$segment/$Name"
                Kind            = $Kind
                Name            = $Name
                Module          = $Module
                File            = $File
                Line            = $Line
                Expr            = $Expr
                Literal         = Get-TerraformExpressionLiteral -Expr $Expr
                References      = Get-TerraformExpressionReferences -Expr $Expr
                Type            = $null
                Description     = $null
                Sensitive       = $null
                Nullable        = $null
                HasDefault      = $null
                Binding         = $null
                ArgumentExpr    = $null
                ArgumentLiteral = $null
                Raw             = $Raw
            }
        }

        # Pass 1: every node, so edge targets exist before any edge is built.
        foreach ($module in $moduleNodes) {
            $address = [string]$module.ModuleAddress
            if ($null -eq $module.Blocks) {
                $skipped.Add($address)
                continue
            }
            $blocks = @($module.Blocks)
            $callArguments = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            if ($module.Block) {
                foreach ($attribute in & $sortedAttributes $module.Block.Body) {
                    if ($metaArguments -cnotcontains $attribute.Name) { $callArguments[[string]$attribute.Name] = $attribute }
                }
            }

            $variables = foreach ($block in @($blocks | Where-Object Type -eq 'variable')) {
                $attributes = $block.Body.Attributes
                $default = $attributes.PSObject.Properties['default']
                $node = & $newNode Variable ([string]$block.Labels[0]) $address $block.File $block.Line ($default ? $default.Value.Expr : $null) $block
                $sensitive = & $attributeValue $attributes.sensitive
                $nullable = & $attributeValue $attributes.nullable
                $node.Type        = $attributes.PSObject.Properties['type'] ? $attributes.type.Expr.Raw : $null
                $node.Description = & $attributeValue $attributes.description
                $node.Sensitive   = ($null -ne $sensitive) ? $sensitive : $false
                $node.Nullable    = ($null -ne $nullable) ? $nullable : $true
                $node.HasDefault  = $null -ne $default
                $argument = $null
                if ($callArguments.TryGetValue($node.Name, [ref]$argument)) {
                    $node.Binding         = 'Argument'
                    $node.ArgumentExpr    = $argument.Expr
                    $node.ArgumentLiteral = Get-TerraformExpressionLiteral -Expr $argument.Expr
                }
                else {
                    $node.Binding = $node.HasDefault ? 'Default' : 'Unset'
                }
                $node
            }
            $locals = foreach ($block in @($blocks | Where-Object Type -eq 'locals')) {
                foreach ($attribute in & $sortedAttributes $block.Body) {
                    & $newNode Local ([string]$attribute.Name) $address (& $leaf $attribute.NameRange) $attribute.NameRange.Start.Line $attribute.Expr $attribute
                }
            }
            $outputs = foreach ($block in @($blocks | Where-Object Type -eq 'output')) {
                $attributes = $block.Body.Attributes
                $node = & $newNode Output ([string]$block.Labels[0]) $address $block.File $block.Line $attributes.value.Expr $block
                $sensitive = & $attributeValue $attributes.sensitive
                $node.Sensitive = ($null -ne $sensitive) ? $sensitive : $false
                $node
            }

            foreach ($group in @(, @($variables)) + @(, @($locals)) + @(, @($outputs))) {
                # Ordinal by name, so the order never depends on culture.
                $sorted = [System.Collections.Generic.List[object]]::new()
                foreach ($node in $group) { if ($null -ne $node) { $sorted.Add($node) } }
                $sorted.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
                foreach ($node in $sorted) {
                    $nodes.Add($node)
                    $byId[$node.Id] = $node
                }
            }
        }

        # Edges for one expression in module $address toward node Id $to. $to is $null
        # when the target is in a skipped module or undeclared: references are still
        # checked, but no edge is made.
        $connect = {
            param($address, $expr, $to, $kind)
            $file = & $leaf $expr.SrcRange
            $line = $expr.SrcRange.Start.Line
            # Assigned first: the helper returns one array, which foreach would not unroll.
            $references = Get-TerraformExpressionReferences -Expr $expr
            foreach ($reference in $references) {
                $root = $reference.Root
                if ($null -eq $root) { continue }
                $parts = $root.Split('.')
                $edgeKind = $kind
                if ($parts[0] -eq 'module') {
                    $childAddress = & $childAddressOf $address $parts[1]
                    $child = $null
                    if ($byAddress.TryGetValue($childAddress, [ref]$child) -and $null -eq $child.Blocks) { continue }
                    $from = "$childAddress/output/$($parts[2])"
                    if (-not $byId.ContainsKey($from)) {
                        $unresolved.Add([pscustomobject]@{ Module = $address; Root = $root; Reason = 'UndeclaredOutput'; File = $file; Line = $line })
                        continue
                    }
                    $edgeKind = 'OutputReference'
                }
                else {
                    $from = "$address/$($parts[0])/$($parts[1])"
                    if (-not $byId.ContainsKey($from)) {
                        $unresolved.Add([pscustomobject]@{ Module = $address; Root = $root; Reason = 'UndeclaredReference'; File = $file; Line = $line })
                        continue
                    }
                }
                if ($null -eq $to) { continue }
                $edges.Add([pscustomobject]@{
                    PSTypeName = 'TerraformGraph.VariableEdge'
                    From       = $from
                    To         = $to
                    Kind       = $edgeKind
                    Via        = $reference.Traversal
                    File       = $file
                    Line       = $line
                })
            }
        }

        # Pass 2: edges, per module in ModuleGraph order: declarations in node order, then
        # module call arguments, calls in source order and arguments in source order.
        $index = 0
        foreach ($module in $moduleNodes) {
            if ($null -eq $module.Blocks) { continue }
            $address = [string]$module.ModuleAddress

            while ($index -lt $nodes.Count -and $nodes[$index].Module -ceq $address) {
                $node = $nodes[$index++]
                if ($null -ne $node.Expr) { & $connect $address $node.Expr $node.Id 'Reference' }
            }

            foreach ($call in @($module.Blocks | Where-Object Type -eq 'module')) {
                $childAddress = & $childAddressOf $address ([string]$call.Labels[0])
                $child = $null
                $childParsed = $byAddress.TryGetValue($childAddress, [ref]$child) -and $null -ne $child.Blocks
                foreach ($attribute in & $sortedAttributes $call.Body) {
                    $name = [string]$attribute.Name
                    if ($metaArguments -ccontains $name) { continue }
                    $to = $null
                    if ($childParsed) {
                        $to = "$childAddress/var/$name"
                        if (-not $byId.ContainsKey($to)) {
                            $unresolved.Add([pscustomobject]@{
                                Module = $childAddress
                                Root   = "var.$name"
                                Reason = 'UndeclaredArgument'
                                File   = & $leaf $attribute.NameRange
                                Line   = $attribute.NameRange.Start.Line
                            })
                            $to = $null
                        }
                    }
                    & $connect $address $attribute.Expr $to 'Argument'
                }
            }
        }

        [pscustomobject]@{
            PSTypeName = 'TerraformGraph.VariableGraph'
            Root       = $ModuleGraph.Root
            Nodes      = $nodes.ToArray()
            Edges      = $edges.ToArray()
            Unresolved = $unresolved.ToArray()
            Skipped    = $skipped.ToArray()
        }
    }
}
