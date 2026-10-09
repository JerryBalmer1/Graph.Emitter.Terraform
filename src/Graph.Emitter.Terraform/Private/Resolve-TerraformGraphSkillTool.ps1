function Resolve-TerraformGraphSkillTool {
    # Not exported. Expands 'All' and removes duplicates, in tool-map order.
    param([string[]]$Tool)
    $all = $Tool -contains 'All'
    foreach ($name in $script:TerraformGraphSkillTools.Keys) {
        if ($all -or $Tool -contains $name) { $name }
    }
}
