function Read-TerraformClassifierJson {
    # Not exported. A classifier, map or drawers file as ordered dictionaries.
    param([string]$Path)

    [TerraformGraph.Json]::Deserialize([System.IO.File]::ReadAllText($Path), 64, $true)
}
