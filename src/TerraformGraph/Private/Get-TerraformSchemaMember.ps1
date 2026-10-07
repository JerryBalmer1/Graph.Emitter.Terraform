function Get-TerraformSchemaMember {
    # Not exported. Reads one key from a schema fragment, whether it is a dictionary
    # (Get-TerraformProviderSchema, ConvertFrom-TerraformJson -AsHashtable) or a
    # PSCustomObject (ConvertFrom-TerraformJson). A missing key returns $null. The
    # leading comma keeps array values (cty types) from being unrolled.
    param(
        [AllowNull()]
        $InputObject,

        [string]
        $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return , $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return , $property.Value }
    $null
}
