function Get-TerraformClassifierDrawerName {
    # Not exported. Drawer names in drawers.json order from -Path, default the bundled file.
    param([string]$Path = $script:TerraformClassifierDrawersPath)

    [string[]]@(foreach ($drawer in @((Read-TerraformClassifierJson -Path $Path)['drawers'])) { [string]$drawer['name'] })
}
