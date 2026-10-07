function Get-TerraformRegistryCache {
    # Not exported. The user cache if present, else the bundled file (unless
    # -NoBundledData), else $null. Parsed once per file version and kept in memory, so
    # argument completers stay fast after the first Tab.
    param([switch]$NoBundledData)

    $paths = @($script:TerraformRegistryUserCachePath)
    if (-not $NoBundledData) { $paths += $script:TerraformRegistryBundledPath }
    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $path
        $key = "$($item.FullName)|$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
        if ($script:TerraformRegistryCacheMemo -and $script:TerraformRegistryCacheMemo.Key -ceq $key) {
            return $script:TerraformRegistryCacheMemo.Value
        }

        $cache = Read-TerraformRegistryCacheFile -Path $item.FullName
        $script:TerraformRegistryCacheMemo = @{ Key = $key; Value = $cache }
        return $cache
    }
    $null
}
