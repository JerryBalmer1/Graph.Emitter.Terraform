function Get-TerraformGraphBundleClassifierEntry {
    # Not exported. The classifier files bundled with the module (never the user folder: a
    # bundle describes what ships).
    Get-TerraformClassifierEntry -ClassifierPath $script:TerraformClassifierBundledRoot | Where-Object Rank -eq 0
}
