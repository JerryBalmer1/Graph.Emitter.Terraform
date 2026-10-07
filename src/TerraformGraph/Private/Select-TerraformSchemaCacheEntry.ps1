function Select-TerraformSchemaCacheEntry {
    # Not exported. Cached schemas matching any -Name pattern (all when none), by shape as
    # in Select-TerraformRegistryProvider: no slash matches the bare name, one slash
    # namespace/name, two the full address. -like, so wildcards work and case is ignored.
    param($Entry, [string[]]$Name)

    foreach ($candidate in $Entry) {
        if (-not $Name) { $candidate; continue }
        $segments = $candidate.ProviderAddress.Split('/')
        foreach ($pattern in $Name) {
            $value = switch ($pattern.Split('/').Count) {
                1       { $segments[-1] }
                2       { ($segments | Select-Object -Last 2) -join '/' }
                default { $candidate.ProviderAddress }
            }
            if ($value -like $pattern) { $candidate; break }
        }
    }
}
