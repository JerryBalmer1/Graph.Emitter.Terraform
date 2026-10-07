function Get-TerraformClassifierOverlay {
    # Not exported. For -Classify on a graph: per provider address, a lookup
    # "<kind>|<type>" -> ClassifiedType (kind resource or data-source), or $null when no
    # classifier is found, which gets one warning (terraform.io/builtin providers have no
    # registry docs and are skipped silently). -Version maps an address to the schema
    # version the graph came from; that classifier version is preferred, else the one the
    # lookup order gives. Order is the drawers.json order, for the Drawers summary.
    param([string[]]$Address, [hashtable]$Version = @{}, [string]$ClassifierPath)

    $entries = @(Get-TerraformClassifierEntry -ClassifierPath $ClassifierPath)
    $byAddress = @{}
    foreach ($providerAddress in @($Address | Select-Object -Unique)) {
        $wanted = $Version[$providerAddress]
        $entry = if ($wanted) { Find-TerraformClassifierEntry -Entry $entries -Address $providerAddress -Version $wanted }
        if (-not $entry) {
            $entry = Find-TerraformClassifierEntry -Entry $entries -Address $providerAddress
            if ($entry -and $wanted) { Write-Verbose "No classifier for $providerAddress $wanted; using $($entry.Version) from $($entry.Path)" }
        }
        if (-not $entry) {
            if (-not $providerAddress.StartsWith('terraform.io/builtin/', [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Warning "No classifier for $providerAddress, so its types are in the unclassified drawer. Generate one with New-TerraformClassifier -Provider $providerAddress, or pass -ClassifierPath."
            }
            $byAddress[$providerAddress] = $null
            continue
        }
        Write-Verbose "Classifying $providerAddress with $($entry.Path)"
        $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($type in (Read-TerraformClassifierFile -Path $entry.Path).Types) { $lookup["$($type.Kind)|$($type.Type)"] = $type }
        $byAddress[$providerAddress] = $lookup
    }
    [pscustomobject]@{ ByAddress = $byAddress; Order = Get-TerraformClassifierDrawerName }
}
