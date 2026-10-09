function New-TerraformDrawerSummary {
    # Not exported. TerraformGraph.DrawerSummary rows from -Item records (Drawer, TypeKey),
    # in -Order with unknown drawers after it by name. TypeCount is the distinct TypeKeys;
    # InstanceCount is the record count with -Instances, else $null (not known).
    param([object[]]$Item, [string[]]$Order, [switch]$Instances)

    $groups = @{}
    foreach ($record in $Item) {
        $group = $groups[$record.Drawer]
        if (-not $group) {
            $group = @{ Types = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal); Instances = 0 }
            $groups[$record.Drawer] = $group
        }
        $null = $group.Types.Add([string]$record.TypeKey)
        $group.Instances++
    }
    $names = @($groups.Keys) | Sort-Object { $index = [array]::IndexOf($Order, $_); if ($index -lt 0) { [int]::MaxValue } else { $index } }, { $_ }
    foreach ($name in $names) {
        [pscustomobject]@{
            PSTypeName    = 'TerraformGraph.DrawerSummary'
            Drawer        = $name
            TypeCount     = $groups[$name].Types.Count
            InstanceCount = if ($Instances) { $groups[$name].Instances } else { $null }
        }
    }
}
