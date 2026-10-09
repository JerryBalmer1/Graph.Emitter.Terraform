function Resolve-TerraformProviderDocId {
    # Not exported. The doc Id for one registry doc. Resources and data sources are joined
    # to the schema: the type is <Prefix>_<slug>, or the slug itself when it already starts
    # with <Prefix>_ and only that form is in the schema (vsphere_sso_group). A type in
    # neither form is unmatched: <address>/unmatched/<category>/<slug>, Matched $false. With
    # no -Index (no cached schema) the type is built the same way without checking and
    # Matched is $null.
    param([string]$Address, [string]$Category, [string]$Slug, $Index, [string]$Prefix)

    switch ($Category) {
        'overview' { return [pscustomobject]@{ Id = $Address; Type = $null; Matched = $true } }
        'guides'   { return [pscustomobject]@{ Id = "$Address/guide/$Slug"; Type = $null; Matched = $true } }
    }
    $segment = if ($Category -eq 'data-sources') { 'data' } else { 'resource' }
    $candidates = @("$($Prefix)_$Slug")
    if ($Slug.StartsWith("$($Prefix)_", [System.StringComparison]::Ordinal)) { $candidates += $Slug }

    if ($null -eq $Index) {
        $type = $candidates[-1]
        return [pscustomobject]@{ Id = "$Address/$segment/$type"; Type = $type; Matched = $null }
    }
    $types = if ($segment -eq 'data') { $Index.Data } else { $Index.Resource }
    foreach ($type in $candidates) {
        if ($types.Contains($type)) {
            return [pscustomobject]@{ Id = "$Address/$segment/$type"; Type = $type; Matched = $true }
        }
    }
    [pscustomobject]@{ Id = "$Address/unmatched/$Category/$Slug"; Type = $null; Matched = $false }
}
