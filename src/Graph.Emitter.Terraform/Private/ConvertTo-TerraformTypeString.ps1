function ConvertTo-TerraformTypeString {
    # Not exported. Renders cty type JSON as Terraform type syntax:
    # ["set",["object",{"a":"string"},["a"]]] -> set(object({ a = optional(string) })).
    # "dynamic" renders as any. An unknown shape comes back as compact JSON.
    param(
        [AllowNull()]
        $Type
    )

    if ($null -eq $Type) { return $null }
    if ($Type -is [string]) {
        if ($Type -eq 'dynamic') { return 'any' }
        return $Type
    }

    $kind = [string]$Type[0]
    switch ($kind) {
        { $_ -in 'list', 'set', 'map' } {
            return "$kind($(ConvertTo-TerraformTypeString -Type $Type[1]))"
        }
        'tuple' {
            $elements = foreach ($element in @($Type[1])) { ConvertTo-TerraformTypeString -Type $element }
            return "tuple([$(@($elements) -join ', ')])"
        }
        'object' {
            $optional = if ($Type.Count -gt 2) { @($Type[2]) } else { @() }
            $members = foreach ($name in Get-TerraformSchemaKeys -InputObject $Type[1]) {
                $rendered = ConvertTo-TerraformTypeString -Type (Get-TerraformSchemaMember -InputObject $Type[1] -Name $name)
                if ($optional -ccontains $name) { $rendered = "optional($rendered)" }
                "$name = $rendered"
            }
            if (-not $members) { return 'object({})' }
            return "object({ $(@($members) -join ', ') })"
        }
    }

    [TerraformGraph.Json]::Serialize($Type, 1024, $true)
}
