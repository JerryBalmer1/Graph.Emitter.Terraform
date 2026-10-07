function Add-TerraformResourceGraphClassification {
    # Not exported. -Classify for ConvertTo-TerraformResourceGraph: every ResourceNode gets
    # Drawer and Subcategory from its provider's classifier by Type and Kind (unclassified
    # when the classifier lacks the type or there is none), and the graph gets Drawers with
    # TypeCount (distinct SchemaIds) and InstanceCount (blocks). Ids, nodes and edges are
    # untouched.
    param($Graph, [hashtable]$Version, [string]$ClassifierPath)

    $overlay = Get-TerraformClassifierOverlay -Address @($Graph.Providers.Keys) -Version $Version -ClassifierPath $ClassifierPath
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($node in $Graph.Nodes) {
        $kind = $node.Kind -eq 'DataSource' ? 'data-source' : 'resource'
        $lookup = $overlay.ByAddress[[string]$node.ProviderAddress]
        $classified = $null
        if ($lookup) { $null = $lookup.TryGetValue("$kind|$($node.Type)", [ref]$classified) }
        $drawer = if ($classified) { $classified.Drawer } else { 'unclassified' }
        $node.PSObject.Properties.Add([psnoteproperty]::new('Drawer', $drawer))
        $node.PSObject.Properties.Add([psnoteproperty]::new('Subcategory', $(if ($classified) { $classified.Subcategory } else { $null })))
        $items.Add([pscustomobject]@{ Drawer = $drawer; TypeKey = $node.SchemaId })
    }
    $Graph.PSObject.Properties.Add([psnoteproperty]::new('Drawers', [object[]]@(New-TerraformDrawerSummary -Item $items -Order $overlay.Order -Instances)))
}
