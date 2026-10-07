function Read-TerraformClassifierMap {
    # Not exported. map.json at -Path, checked with Get-TerraformClassifierMapProblem against
    # drawers.json beside it (else the bundled drawers.json); throws listing every problem.
    # Lookup is keyed "<provider>`n<subcategory>" ignoring case. MapVersion is the first 12
    # hex digits of the sha256 of the map's compact JSON, so it follows the rows and not
    # whitespace or line endings.
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-TerraformGraphCommand -Throw -Id 'ClassifierMapInvalid' -Category ObjectNotFound -Target $Path -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "Classifier map '$Path' does not exist. Pass an existing -MapPath, or leave it out to use the bundled classifiers/map.json."
    }
    $map = Read-TerraformClassifierJson -Path $Path
    $drawersPath = Join-Path (Split-Path -Path $Path -Parent) 'drawers.json'
    if (-not (Test-Path -LiteralPath $drawersPath -PathType Leaf)) { $drawersPath = $script:TerraformClassifierDrawersPath }
    $drawers = Get-TerraformClassifierDrawerName -Path $drawersPath

    $problems = @(Get-TerraformClassifierMapProblem -Map $map -Drawer $drawers)
    if ($problems.Count) {
        Stop-TerraformGraphCommand -Throw -Id 'ClassifierMapInvalid' -Category InvalidData -Target $Path -ExceptionType ([System.IO.InvalidDataException]) -Message "Classifier map '$Path' has $($problems.Count) problem(s):`n  $($problems -join "`n  ")`nFix those rows, then rerun New-TerraformClassifier (Invoke-Build BuildClassifier for the bundled map)."
    }

    $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $prefix = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($row in @($map['rows'])) {
        if ($row.Contains('source') -and [string]$row['source'] -ceq 'prefix') {
            $list = $null
            if (-not $prefix.TryGetValue([string]$row['provider'], [ref]$list)) {
                $list = [System.Collections.Generic.List[object]]::new()
                $prefix[[string]$row['provider']] = $list
            }
            $list.Add($row)
            continue
        }
        $lookup["$($row['provider'])`n$($row['subcategory'])"] = $row
    }
    foreach ($list in $prefix.Values) {
        $list.Sort([System.Comparison[object]] {
                param($a, $b)
                $byLength = ([string]$b['subcategory']).Length.CompareTo(([string]$a['subcategory']).Length)
                if ($byLength) { return $byLength }
                [string]::CompareOrdinal([string]$a['subcategory'], [string]$b['subcategory'])
            })
    }
    $compact = [System.Text.Encoding]::UTF8.GetBytes([TerraformGraph.Json]::Serialize($map, 64, $true))
    $hash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($compact)).ToLowerInvariant()
    [pscustomobject]@{
        Path       = (Resolve-Path -LiteralPath $Path).ProviderPath
        MapVersion = $hash.Substring(0, 12)
        Drawers    = $drawers
        Lookup     = $lookup
        Prefix     = $prefix
    }
}
