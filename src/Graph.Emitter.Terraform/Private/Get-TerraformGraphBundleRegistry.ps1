function Get-TerraformGraphBundleRegistry {
    # Not exported. The registry cache a bundle resolves against: registry.json in the same
    # folder as -BundlePath (data\registry.json for the bundled bundle.json, the user registry
    # cache for the user copy), else the one Get-TerraformRegistryCache returns.
    param([string]$BundlePath)

    $beside = Join-Path (Split-Path -Path $BundlePath -Parent) 'registry.json'
    if (Test-Path -LiteralPath $beside -PathType Leaf) { return Read-TerraformRegistryCacheFile -Path $beside }
    $cache = Get-TerraformRegistryCache
    if (-not $cache) { Stop-TerraformGraphCommand -Throw -Id 'RegistryCacheNotFound' -Category ObjectNotFound -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message 'There is no registry cache to resolve the bundle against. Run Update-TerraformRegistryCache.' }
    $cache
}
