function ConvertTo-TerraformNestedTypeJson {
    # Not exported. Builds the cty type JSON an attribute's nested_type implies, with
    # optional members listed the way cty lists them, so a nested attribute renders and
    # serializes exactly like a plain typed one.
    param(
        [Parameter(Mandatory)]
        $NestedType
    )

    $members = [ordered]@{}
    $optional = [System.Collections.Generic.List[string]]::new()
    $attributes = Get-TerraformSchemaMember -InputObject $NestedType -Name 'attributes'
    foreach ($name in Get-TerraformSchemaKeys -InputObject $attributes) {
        $attribute = Get-TerraformSchemaMember -InputObject $attributes -Name $name
        $nested = Get-TerraformSchemaMember -InputObject $attribute -Name 'nested_type'
        $members[$name] = if ($null -ne $nested) {
            ConvertTo-TerraformNestedTypeJson -NestedType $nested
        }
        else {
            Get-TerraformSchemaMember -InputObject $attribute -Name 'type'
        }
        if (Get-TerraformSchemaMember -InputObject $attribute -Name 'optional') {
            $optional.Add($name)
        }
    }

    $object = if ($optional.Count) {
        [object[]]('object', $members, $optional.ToArray())
    }
    else {
        [object[]]('object', $members)
    }

    $mode = [string](Get-TerraformSchemaMember -InputObject $NestedType -Name 'nesting_mode')
    if ($mode -in 'list', 'set', 'map') {
        return , [object[]]($mode, $object)
    }
    , $object
}
