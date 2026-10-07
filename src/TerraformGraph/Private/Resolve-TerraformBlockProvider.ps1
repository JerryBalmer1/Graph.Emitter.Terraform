function Resolve-TerraformBlockProvider {
    # Not exported. LocalName, Alias and ProviderAddress for one resource or data block,
    # given its module's Get-TerraformModuleProviderMap.
    param($Block, $Declared)

    $type = [string]$Block.Labels[0]
    $attributes = $Block.Body.Attributes
    $localName = $type.Split('_')[0]
    $alias = $null
    $providerAttribute = if ($null -ne $attributes) { $attributes.PSObject.Properties['provider'] }
    if ($providerAttribute) {
        $expr = $providerAttribute.Value.Expr
        $parts = ([string]($expr.Traversal ?? $expr.Raw)).Split('.', 2)
        $localName = $parts[0]
        if ($parts.Count -gt 1) { $alias = $parts[1] }
    }

    $providerAddress = $null
    if (-not $Declared.TryGetValue($localName, [ref]$providerAddress)) {
        $providerAddress = if ($localName -eq 'terraform') {
            'terraform.io/builtin/terraform'
        }
        else {
            "registry.terraform.io/hashicorp/$localName".ToLowerInvariant()
        }
    }

    [pscustomobject]@{ LocalName = $localName; Alias = $alias; ProviderAddress = $providerAddress }
}
