function Sort-TerraformRegistryVersion {
    # Not exported. Version records newest first by semantic version; strings that do not
    # parse sort after every parsed version, ordinal descending.
    param([object[]]$Versions)

    $keyed = foreach ($version in $Versions) {
        $semver = $null
        $null = [System.Management.Automation.SemanticVersion]::TryParse([string]$version.Version, [ref]$semver)
        [pscustomobject]@{ Semver = $semver; Record = $version }
    }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $keyed) { $list.Add($entry) }
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            if ($a.Semver -and $b.Semver) { return $b.Semver.CompareTo($a.Semver) }
            if ($a.Semver) { return -1 }
            if ($b.Semver) { return 1 }
            [string]::CompareOrdinal([string]$b.Record.Version, [string]$a.Record.Version)
        })
    foreach ($entry in $list) {
        [pscustomobject]@{
            Record     = $entry.Record
            PreRelease = if ($entry.Semver) { [bool]$entry.Semver.PreReleaseLabel } else { ([string]$entry.Record.Version).Contains('-') }
        }
    }
}
