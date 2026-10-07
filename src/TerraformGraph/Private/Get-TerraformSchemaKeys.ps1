function Get-TerraformSchemaKeys {
    # Not exported. Keys of a schema map in document order, or sorted ordinally with -Sort
    # so the order never depends on culture.
    param(
        [AllowNull()]
        $InputObject,

        [switch]
        $Sort
    )

    if ($null -eq $InputObject) { return }
    [string[]]$keys = if ($InputObject -is [System.Collections.IDictionary]) {
        @($InputObject.Keys)
    }
    else {
        @($InputObject.PSObject.Properties.Name)
    }
    if ($Sort) { [Array]::Sort($keys, [System.StringComparer]::Ordinal) }
    $keys
}
