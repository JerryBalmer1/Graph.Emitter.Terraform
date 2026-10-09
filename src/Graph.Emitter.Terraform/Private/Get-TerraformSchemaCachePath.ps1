function Get-TerraformSchemaCachePath {
    # Not exported. Cache file for one provider version under the -Kind root. The address is
    # normalized with ConvertTo-TerraformProviderAddress and lowercased, as terraform keys
    # provider_schemas.
    param([string]$Provider, [string]$Version, [ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+_-]*$') {
        Stop-TerraformGraphCommand -Throw -Id 'ProviderVersionInvalid' -Category InvalidArgument -Target $Version -ExceptionType ([System.ArgumentException]) -Message "Version '$Version' is not a provider version such as 3.2.3. List the versions with Get-TerraformRegistryProvider -Name '$Provider' | Select-Object -ExpandProperty Versions."
    }
    $slug = (ConvertTo-TerraformProviderAddress -Provider $Provider).Address.ToLowerInvariant().Replace('/', '-')
    $root = if ($Kind -eq 'Docs') { $script:TerraformDocCacheRoot } else { $script:TerraformSchemaCacheRoot }
    Join-Path $root $slug "$Version.json.gz"
}
