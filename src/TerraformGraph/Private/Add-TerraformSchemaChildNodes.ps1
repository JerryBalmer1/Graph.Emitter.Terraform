function Add-TerraformSchemaChildNodes {
    # Not exported. Walks a schema block, or an attribute's nested_type, depth-first:
    # attributes sorted by name, then blocks sorted by name, each followed by its subtree.
    # -Segment applies to the direct children only (see New-TerraformSchemaNode). Not an
    # advanced function, for the same reason as New-TerraformSchemaNode.
    param(
        $Graph,

        $Container,

        $Parent,

        [string]
        $Segment
    )

    if ($null -eq $Container) { return }

    # Dictionary input (the default) is read inline; Get-TerraformSchemaMember per key
    # dominated large schemas such as aws. PSCustomObject input still goes through it.
    $attributes = $Container -is [System.Collections.IDictionary] ? $Container['attributes'] : (Get-TerraformSchemaMember -InputObject $Container -Name 'attributes')
    $attributesAreDictionary = $attributes -is [System.Collections.IDictionary]
    if ($attributesAreDictionary) {
        [string[]]$names = @($attributes.Keys)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
    }
    else {
        $names = Get-TerraformSchemaKeys -InputObject $attributes -Sort
    }
    foreach ($name in $names) {
        $attribute = $attributesAreDictionary ? $attributes[$name] : (Get-TerraformSchemaMember -InputObject $attributes -Name $name)
        if ($attribute -is [System.Collections.IDictionary]) {
            $nested = $attribute['nested_type']
            $type = $attribute['type']
            $description = $attribute['description']
            $deprecated = [bool]$attribute['deprecated']
        }
        else {
            $nested = Get-TerraformSchemaMember -InputObject $attribute -Name 'nested_type'
            $type = Get-TerraformSchemaMember -InputObject $attribute -Name 'type'
            $description = Get-TerraformSchemaMember -InputObject $attribute -Name 'description'
            $deprecated = [bool](Get-TerraformSchemaMember -InputObject $attribute -Name 'deprecated')
        }
        $typeJson = ($null -ne $nested) ? (ConvertTo-TerraformNestedTypeJson -NestedType $nested) : $type

        $node = New-TerraformSchemaNode -Graph $Graph -Kind Attribute -Name $name -Parent $Parent -Raw $attribute `
            -Description $description -Deprecated $deprecated -TypeJson $typeJson -Segment $Segment

        if ($null -ne $nested) {
            Add-TerraformSchemaChildNodes -Graph $Graph -Container $nested -Parent $node
        }
    }

    $blockTypes = $Container -is [System.Collections.IDictionary] ? $Container['block_types'] : (Get-TerraformSchemaMember -InputObject $Container -Name 'block_types')
    $blockTypesAreDictionary = $blockTypes -is [System.Collections.IDictionary]
    if ($blockTypesAreDictionary) {
        [string[]]$names = @($blockTypes.Keys)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
    }
    else {
        $names = Get-TerraformSchemaKeys -InputObject $blockTypes -Sort
    }
    foreach ($name in $names) {
        $blockType = $blockTypesAreDictionary ? $blockTypes[$name] : (Get-TerraformSchemaMember -InputObject $blockTypes -Name $name)
        if ($blockType -is [System.Collections.IDictionary]) {
            $inner = $blockType['block']
            $nestingMode = $blockType['nesting_mode']
            $minItems = $blockType['min_items']
            $maxItems = $blockType['max_items']
        }
        else {
            $inner = Get-TerraformSchemaMember -InputObject $blockType -Name 'block'
            $nestingMode = Get-TerraformSchemaMember -InputObject $blockType -Name 'nesting_mode'
            $minItems = Get-TerraformSchemaMember -InputObject $blockType -Name 'min_items'
            $maxItems = Get-TerraformSchemaMember -InputObject $blockType -Name 'max_items'
        }
        if ($inner -is [System.Collections.IDictionary]) {
            $description = $inner['description']
            $deprecated = [bool]$inner['deprecated']
        }
        else {
            $description = Get-TerraformSchemaMember -InputObject $inner -Name 'description'
            $deprecated = [bool](Get-TerraformSchemaMember -InputObject $inner -Name 'deprecated')
        }

        $node = New-TerraformSchemaNode -Graph $Graph -Kind Block -Name $name -Parent $Parent -Raw $blockType `
            -Description $description -Deprecated $deprecated `
            -NestingMode $nestingMode -MinItems $minItems -MaxItems $maxItems -Segment $Segment

        Add-TerraformSchemaChildNodes -Graph $Graph -Container $inner -Parent $node
    }
}
