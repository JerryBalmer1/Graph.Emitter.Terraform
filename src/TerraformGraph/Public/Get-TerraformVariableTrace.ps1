function Get-TerraformVariableTrace {
    <#
    .SYNOPSIS
        Follows a variable, local or output through a variable graph.

    .DESCRIPTION
        Get-TerraformVariableTrace starts at one node of a TerraformGraph.VariableGraph and
        walks its edges breadth-first. Upstream follows edges backwards (To to From) and
        answers where a value comes from; Downstream follows them forwards (From to To)
        and answers what a value feeds. Both does upstream first, then downstream.

        Each returned node is a copy of the graph's node with a Distance property: 0 for
        the start, 1, 2, ... downstream, and -1, -2, ... upstream when -Direction is Both
        (with Upstream alone distances are positive). A node is returned once, at the
        distance it was first reached. Cycles, such as locals that reference each other,
        terminate because no node is expanded twice.

    .PARAMETER VariableGraph
        A TerraformGraph.VariableGraph from ConvertTo-TerraformVariableGraph.

    .PARAMETER Id
        The Id of the start node, such as module.network/var/aws_region. An Id that is
        not in the graph is a terminating error that lists up to 10 nodes with the same
        Name in any module.

    .PARAMETER Direction
        Upstream, Downstream or Both (default).

    .PARAMETER MaxDepth
        Maximum number of edges from the start node. Default 50.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        ($graph | Get-TerraformVariableTrace -Id 'module.network/var/aws_region' -Direction Upstream).Nodes

        Where the network module's aws_region comes from: the root variable that the
        module call passes in.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        ($graph | Get-TerraformVariableTrace -Id 'root/var/aws_region' -Direction Downstream).Nodes

        Everything the root aws_region variable feeds: the root output that echoes it and
        the network module variable it is passed to.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        $trace = $graph | Get-TerraformVariableTrace -Id 'module.network.module.endpoint/output/address'
        $trace.Nodes
        $trace.Edges | Format-Table From, To, Kind, Via

        Both directions from a middle node: the host and port variables that build the
        endpoint address at Distance -1, the network output that re-exports it at 1,
        and the edges walked.

    .OUTPUTS
        TerraformGraph.VariableTrace with Start, Direction, Nodes and Edges. Nodes are
        TerraformGraph.VariableTraceNode (default view Distance, Kind, Module, Name,
        Binding, Literal); Edges are the TerraformGraph.VariableEdge objects walked.

    .LINK
        ConvertTo-TerraformVariableGraph

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $VariableGraph,

        [Parameter(Mandatory)]
        [string]
        $Id,

        [ValidateSet('Upstream', 'Downstream', 'Both')]
        [string]
        $Direction = 'Both',

        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $MaxDepth = 50
    )

    process {
        $byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($node in @($VariableGraph.Nodes)) { $byId[$node.Id] = $node }

        $start = $null
        if (-not $byId.TryGetValue($Id, [ref]$start)) {
            $name = $Id.Split('/')[-1]
            $near = @($VariableGraph.Nodes | Where-Object Name -ceq $name | Select-Object -First 10 -ExpandProperty Id)
            $hint = if ($near.Count) { " Nodes named '$name': $($near -join ', ')." } else { " No node is named '$name'." }
            Stop-TerraformGraphCommand -Id 'VariableNodeNotFound' -Category ObjectNotFound -Target $Id -ExceptionType ([System.ArgumentException]) -Message "Node '$Id' is not in the variable graph.$hint List every Id with `$graph.Nodes | Select-Object -ExpandProperty Id, then rerun Get-TerraformVariableTrace with one of them."
        }

        # Adjacency as indexes into Edges, in Edges order, so the walk is deterministic.
        # Indexes rather than the edges themselves: every PSCustomObject compares equal.
        $allEdges = @($VariableGraph.Edges)
        $outgoing = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new([System.StringComparer]::Ordinal)
        $incoming = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new([System.StringComparer]::Ordinal)
        for ($i = 0; $i -lt $allEdges.Count; $i++) {
            foreach ($pair in @(@($outgoing, $allEdges[$i].From), @($incoming, $allEdges[$i].To))) {
                if (-not $pair[0].ContainsKey($pair[1])) { $pair[0][$pair[1]] = [System.Collections.Generic.List[int]]::new() }
                $pair[0][$pair[1]].Add($i)
            }
        }

        $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $walkedEdges = [System.Collections.Generic.HashSet[int]]::new()
        $resultNodes = [System.Collections.Generic.List[object]]::new()
        $resultEdges = [System.Collections.Generic.List[object]]::new()

        $emit = {
            param($node, $distance)
            $copy = [pscustomobject]@{ PSTypeName = 'TerraformGraph.VariableTraceNode'; Distance = $distance }
            foreach ($property in $node.PSObject.Properties) {
                $copy.PSObject.Properties.Add([psnoteproperty]::new($property.Name, $property.Value))
            }
            $resultNodes.Add($copy)
        }

        $null = $visited.Add($start.Id)
        & $emit $start 0

        $passes = @(switch ($Direction) {
            'Upstream'   { , @('Upstream', 1) }
            'Downstream' { , @('Downstream', 1) }
            'Both'       { @('Upstream', -1), @('Downstream', 1) }
        })
        foreach ($pass in $passes) {
            $adjacency = ($pass[0] -eq 'Upstream') ? $incoming : $outgoing
            $sign = $pass[1]
            $frontier = [System.Collections.Generic.List[string]]::new()
            $frontier.Add($start.Id)
            $depth = 0
            while ($frontier.Count -gt 0 -and $depth -lt $MaxDepth) {
                $depth++
                $next = [System.Collections.Generic.List[string]]::new()
                foreach ($current in $frontier) {
                    $list = $null
                    if (-not $adjacency.TryGetValue($current, [ref]$list)) { continue }
                    foreach ($edgeIndex in $list) {
                        $edge = $allEdges[$edgeIndex]
                        if ($walkedEdges.Add($edgeIndex)) { $resultEdges.Add($edge) }
                        $neighbor = ($pass[0] -eq 'Upstream') ? $edge.From : $edge.To
                        if ($visited.Add($neighbor)) {
                            & $emit $byId[$neighbor] ($sign * $depth)
                            $next.Add($neighbor)
                        }
                    }
                }
                $frontier = $next
            }
        }

        [pscustomobject]@{
            PSTypeName = 'TerraformGraph.VariableTrace'
            Start      = $start
            Direction  = $Direction
            Nodes      = $resultNodes.ToArray()
            Edges      = $resultEdges.ToArray()
        }
    }
}
