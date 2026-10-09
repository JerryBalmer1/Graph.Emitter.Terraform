function Find-TerraformProviderDocVersion {
    # Not exported. The registry's provider-versions record for -Version of
    # <Namespace>/<Name>, or for its newest version that is not a pre-release when -Version
    # is empty: [pscustomobject]@{ Version; VersionId }. Network. See
    # Get-TerraformProviderDocHarvest for the endpoints.
    param([string]$Namespace, [string]$Name, [string]$Version)

    $registry = "https://$($script:TerraformRegistrySource)"
    $response = Invoke-TerraformRegistryRequest -Uri "$registry/v2/providers/$Namespace/${Name}?include=provider-versions"
    $versions = @($response.included | Where-Object { $_.type -eq 'provider-versions' } |
            ForEach-Object { [pscustomobject]@{ Version = [string]$_.attributes.version; VersionId = [string]$_.id } })
    if (-not $versions.Count) {
        Stop-TerraformGraphCommand -Throw -Id 'ProviderDocHarvestFailed' -Category ObjectNotFound -Target "$Namespace/$Name" -Message "The registry lists no versions for $Namespace/$Name."
    }
    if ($Version) {
        $found = $versions | Where-Object Version -eq $Version | Select-Object -First 1
        if (-not $found) {
            Stop-TerraformGraphCommand -Throw -Id 'ProviderDocHarvestFailed' -Category ObjectNotFound -Target "$Namespace/$Name" -Message "The registry has no version $Version of $Namespace/$Name."
        }
        return $found
    }
    $sorted = @(Sort-TerraformRegistryVersion -Versions $versions)
    $newest = $sorted | Where-Object { -not $_.PreRelease } | Select-Object -First 1
    if (-not $newest) { $newest = $sorted[0] }
    $newest.Record
}
