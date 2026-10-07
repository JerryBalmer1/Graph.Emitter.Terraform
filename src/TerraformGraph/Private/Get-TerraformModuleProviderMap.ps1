function Get-TerraformModuleProviderMap {
    # Not exported. Local name -> lowercase provider address from one module's own
    # terraform { required_providers } sources.
    param($Blocks, [string]$ModuleAddress)

    $declared = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($terraform in @($Blocks | Where-Object Type -eq 'terraform')) {
        foreach ($required in @($terraform.Body.Blocks | Where-Object Type -eq 'required_providers')) {
            if ($null -eq $required.Body.Attributes) { continue }
            foreach ($attribute in @($required.Body.Attributes.PSObject.Properties.Value)) {
                $source = $null
                foreach ($item in @($attribute.Expr.Items)) {
                    if ($null -ne $item -and ([string]$item.Key.Raw).Trim('"') -ceq 'source') {
                        $source = Get-TerraformExpressionLiteral -Expr $item.Value
                    }
                }
                if ($source -isnot [string]) { continue }
                try {
                    $declared[[string]$attribute.Name] = (ConvertTo-TerraformProviderAddress -Provider $source).Address.ToLowerInvariant()
                }
                catch {
                    # Not silent: the blocks that use this name bind to the fallback address.
                    $fallback = if ([string]$attribute.Name -ceq 'terraform') { 'terraform.io/builtin/terraform' } else { "registry.terraform.io/hashicorp/$($attribute.Name)" }
                    Write-Warning "$ModuleAddress terraform { required_providers } '$($attribute.Name)': source '$source' is not a provider address, so its blocks resolve to $fallback. Fix the source ('namespace/name' or 'host/namespace/name'). $($_.Exception.Message)"
                }
            }
        }
    }
    , $declared
}
