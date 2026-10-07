function New-TerraformSchemaNode {
    # Not exported. Builds one TerraformGraph.SchemaNode under $Parent, derives Id, Path and
    # Depth from it, and records the Contains edge. Every kind-specific property is set on
    # every node; the ones that do not apply stay $null. -Segment inserts an Id segment
    # between the parent and the name (config, for provider configuration children).
    # Deliberately not an advanced function: no [Parameter()] attributes, since binding
    # cost per call dominated large schemas such as aws.
    param(
        $Graph,

        [string]
        $Kind,

        [string]
        $Name,

        $Parent,
        $Raw,
        $Description,
        [bool]$Deprecated,
        $SchemaVersion,
        $NestingMode,
        $MinItems,
        $MaxItems,
        $TypeJson,
        [string]$Segment,
        $Drawer,
        $Subcategory
    )

    switch ($Kind) {
        'Resource'   { $id = "$($Parent.Id)/resource/$Name"; $path = $Name }
        'DataSource' { $id = "$($Parent.Id)/data/$Name";     $path = $Name }
        'Function'   { $id = "$($Parent.Id)/function/$Name"; $path = $Name }
        default      { $id = if ($Segment) { "$($Parent.Id)/$Segment/$Name" } else { "$($Parent.Id)/$Name" }; $path = "$($Parent.Path).$Name" }
    }

    $isAttribute = $Kind -eq 'Attribute'
    # Flags are read inline for the dictionary case; a call per key dominated large schemas.
    $flags = @{}
    if ($isAttribute) {
        $isDictionary = $Raw -is [System.Collections.IDictionary]
        foreach ($key in 'required', 'optional', 'computed', 'sensitive', 'write_only') {
            $flags[$key] = [bool]($isDictionary ? $Raw[$key] : (Get-TerraformSchemaMember -InputObject $Raw -Name $key))
        }
    }

    $properties = [ordered]@{
        PSTypeName    = 'TerraformGraph.SchemaNode'
        Id            = $id
        Kind          = $Kind
        Name          = $Name
        Path          = $path
        Provider      = $Parent.Provider
        ParentId      = $Parent.Id
        Depth         = $Parent.Depth + 1
        Description   = $Description
        Deprecated    = $Deprecated
        SchemaVersion = $SchemaVersion
        NestingMode   = $NestingMode
        MinItems      = $MinItems
        MaxItems      = $MaxItems
        Type          = if ($isAttribute) { ConvertTo-TerraformTypeString -Type $TypeJson } else { $null }
        TypeJson      = if ($isAttribute -and $null -ne $TypeJson) { [TerraformGraph.Json]::Serialize($TypeJson, 1024, $true) } else { $null }
        Required      = $flags['required']
        Optional      = $flags['optional']
        Computed      = $flags['computed']
        Sensitive     = $flags['sensitive']
        WriteOnly     = $flags['write_only']
        Raw           = $Raw
    }
    # -Classify: set here rather than added afterwards, which cost seconds on azurerm. A
    # Resource or DataSource gets its classifier's values, a Function none, and a Block or
    # Attribute the values of its parent, so everything under a type is in its drawer.
    if ($Graph.Classify) {
        if ($Kind -in 'Resource', 'DataSource') { $properties.Drawer = $Drawer; $properties.Subcategory = $Subcategory }
        elseif ($Kind -eq 'Function') { $properties.Drawer = $null; $properties.Subcategory = $null }
        else { $properties.Drawer = $Parent.Drawer; $properties.Subcategory = $Parent.Subcategory }
    }
    $node = [pscustomobject]$properties

    $Graph.Nodes.Add($node)
    $Graph.Edges.Add([pscustomobject]@{
        PSTypeName = 'TerraformGraph.SchemaEdge'
        From       = $Parent.Id
        To         = $id
        Kind       = 'Contains'
    })
    $node
}
