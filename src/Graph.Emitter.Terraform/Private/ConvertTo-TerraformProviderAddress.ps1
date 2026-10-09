function ConvertTo-TerraformProviderAddress {
    # Not exported. Normalizes 'name', 'namespace/name' or 'host/namespace/name' to the
    # address terraform keys provider_schemas and the lock file on. A bare name means the
    # hashicorp namespace; a missing host means registry.terraform.io. Source is what
    # required_providers takes: the host is dropped only for registry.terraform.io.
    param(
        [Parameter(Mandatory)]
        [string]
        $Provider
    )

    $trimmed = $Provider.Trim()
    if ($trimmed -notmatch '^([\w.-]+/)?[\w-]+/[\w-]+$|^[\w-]+$') {
        Stop-TerraformGraphCommand -Throw -Id 'ProviderAddressInvalid' -Category InvalidArgument -Target $Provider -ExceptionType ([System.ArgumentException]) -Message "Provider '$Provider' is not a provider address. Use 'name', 'namespace/name', or 'host/namespace/name'; Get-TerraformRegistryProvider -Name '<name>' lists the addresses the registry knows."
    }

    $segments = $trimmed.Split('/')
    switch ($segments.Count) {
        1 { $hostName = 'registry.terraform.io'; $namespace = 'hashicorp';   $name = $segments[0] }
        2 { $hostName = 'registry.terraform.io'; $namespace = $segments[0]; $name = $segments[1] }
        3 { $hostName = $segments[0];            $namespace = $segments[1]; $name = $segments[2] }
    }
    $address = "$hostName/$namespace/$name"

    [pscustomobject]@{
        Host      = $hostName
        Namespace = $namespace
        Name      = $name
        Address   = $address
        Source    = if ($hostName -eq 'registry.terraform.io') { "$namespace/$name" } else { $address }
    }
}
