function Get-TerraformProviderSchema {
    <#
    .SYNOPSIS
        Runs `terraform providers schema -json` and returns the result.

    .DESCRIPTION
        Get-TerraformProviderSchema wraps `terraform providers schema -json` for a
        Terraform working directory. The directory must already be initialized
        (`terraform init`) for any provider other than the built-in one.

        With -Provider it fetches one provider's schema on demand instead: it writes a
        throwaway main.tf that requires only that provider, runs `terraform init` there,
        and reads the schema. The working directory is kept by default so repeat calls
        skip the download.

        Provider schemas (AWS in particular) nest deeper than ConvertFrom-Json and
        ConvertTo-Json handle, so the output goes through ConvertFrom-TerraformJson and
        ConvertTo-TerraformJson.

        -OutputFormat OrderedHashtable (the default) returns nested ordered dictionaries
        all the way down. -OutputFormat Json returns indented JSON text.

    .PARAMETER Path
        Terraform working directory. Defaults to the current location.

    .PARAMETER Provider
        Provider to fetch: 'aws', 'hashicorp/aws', or 'registry.terraform.io/hashicorp/aws'.
        A bare name means the hashicorp namespace.
        The source written to required_providers drops the host only when it is
        registry.terraform.io; any other host is kept, as in 'example.com/acme/thing'.
        A value with a wildcard, such as 'aws*' or 'hashicorp/google*', is resolved against
        the provider registry cache (see Get-TerraformRegistryProvider) before anything
        runs; it must match exactly one provider, or the command stops with an error that
        lists every match. A value without a wildcard needs no cache.

    .PARAMETER NoBundledData
        When -Provider has a wildcard, ignore the registry cache bundled with the module and
        read only the user cache.

    .PARAMETER Version
        Version constraint written verbatim into required_providers, such as '~> 5.0',
        '= 5.60.0', or '>= 4'. Omit it to let terraform init pick the latest release.

    .PARAMETER WorkingDirectory
        Directory for the throwaway configuration. Created if missing. Defaults to
        $env:TEMP\TerraformGraph\providers\<namespace>-<name>-<version> for
        registry.terraform.io, and $env:TEMP\TerraformGraph\providers\<host>-<namespace>-<name>-<version>
        for any other host, with '.' and ':' in <host> replaced by '_'. <version> is the
        constraint with every character other than letters, digits, and dots replaced
        by '_', or 'latest' when -Version is omitted.

    .PARAMETER Cleanup
        Remove -WorkingDirectory after reading the schema, even when a step fails.
        Without it the directory is kept so the next call skips terraform init.

    .PARAMETER Force
        Run terraform init even when .terraform.lock.hcl already exists. The lock file
        is deleted first so terraform selects versions again, which picks up a newer
        release for an omitted or ranged -Version.

    .PARAMETER SaveToCache
        After reading the schema, also write it to the local schema cache
        ($env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz) at the
        version terraform selected, read from the lock file. ConvertTo-TerraformSchemaGraph
        -Provider and ConvertTo-TerraformResourceGraph -Provider or -AutoSchema read that
        cache. The schema is still returned as usual. If the selected version cannot be
        determined, the command stops with an error and writes nothing.

    .PARAMETER OutputFormat
        OrderedHashtable (default) or Json.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Path .\infra
        $schema.provider_schemas['registry.terraform.io/hashicorp/aws'].resource_schemas['aws_s3_bucket']

        Look up one resource schema.

    .EXAMPLE
        Get-TerraformProviderSchema -Path .\infra -OutputFormat Json | Set-Content .\schema.json

        Save the schema as indented JSON.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Provider null -Cleanup
        $schema.provider_schemas['registry.terraform.io/hashicorp/null'].resource_schemas.Keys

        Fetch the latest hashicorp/null schema without an existing configuration, then
        remove the working directory.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Provider hashicorp/aws -Version '= 5.60.0' -Verbose

        Fetch a pinned AWS provider schema. The working directory is kept, so running
        the same command again skips terraform init and only reads the schema.

    .EXAMPLE
        $null = Get-TerraformProviderSchema -Provider hashicorp/null -Version '= 3.2.3' -SaveToCache -Cleanup
        ConvertTo-TerraformSchemaGraph -Provider null

        Harvest one provider version into the local schema cache, then build its schema
        graph from the cache without running terraform again.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
        System.String

    .NOTES
        The Provider set needs terraform on PATH and network access to the provider
        registry whenever it runs terraform init.

    .LINK
        ConvertFrom-TerraformJson

    .LINK
        ConvertTo-TerraformJson
    #>
    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    [OutputType([System.Collections.Specialized.OrderedDictionary], [string])]
    param(
        [Parameter(ParameterSetName = 'Directory', Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
                throw "Path '$_' is not an existing directory."
            }
            $true
        })]
        [string]
        $Path = './',

        [Parameter(ParameterSetName = 'Provider', Mandatory)]
        [ValidateScript({
            # A wildcard is resolved against the registry cache in the body.
            if (-not [WildcardPattern]::ContainsWildcardCharacters($_)) {
                $null = ConvertTo-TerraformProviderAddress -Provider $_
            }
            $true
        })]
        [string]
        $Provider,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $Version,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $WorkingDirectory,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $Cleanup,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $Force,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $NoBundledData,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $SaveToCache,

        [ValidateSet('OrderedHashtable', 'Json')]
        [string]
        $OutputFormat = 'OrderedHashtable'
    )

    # Before anything else, so an ambiguous or unknown pattern fails without running terraform.
    if ($PSCmdlet.ParameterSetName -eq 'Provider' -and [WildcardPattern]::ContainsWildcardCharacters($Provider)) {
        try {
            $resolved = Resolve-TerraformRegistryProvider -Name $Provider -NoBundledData:$NoBundledData
        }
        catch {
            # A missing bundle or registry cache keeps its own id (DECISIONS 50).
            if ((Get-TerraformGraphErrorId $_) -in 'RegistryCacheNotFound') { $PSCmdlet.ThrowTerminatingError($_) }
            Stop-TerraformGraphCommand -Id 'RegistryProviderNotResolved' -Category InvalidArgument -Target $Provider -ExceptionType ([System.ArgumentException]) -Message ($_.Exception.Message)
        }
        Write-Verbose "Provider '$Provider' resolved to $($resolved.ProviderAddress) from the registry cache"
        $Provider = $resolved.ProviderAddress
    }

    if (-not (Get-Command terraform -CommandType Application -ErrorAction SilentlyContinue)) {
        Stop-TerraformGraphCommand -Id 'TerraformNotOnPath' -Category NotInstalled -Target 'terraform' -Message "terraform is not on PATH. Install Terraform (https://developer.hashicorp.com/terraform/install) or add its folder to PATH, then rerun Get-TerraformProviderSchema."
    }

    if ($PSCmdlet.ParameterSetName -eq 'Directory') {
        $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        return Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat $OutputFormat
    }

    # The lock file keys on host/namespace/name; required_providers drops the host only
    # when it is the public registry. Both comparisons below are case-insensitive, as
    # terraform lowercases the address it writes to the lock file.
    $providerAddress = ConvertTo-TerraformProviderAddress -Provider $Provider
    $hostName  = $providerAddress.Host
    $namespace = $providerAddress.Namespace
    $name      = $providerAddress.Name
    $address   = $providerAddress.Address
    $source    = $providerAddress.Source

    if (-not $WorkingDirectory) {
        $slug = if ($Version) { $Version -replace '[^A-Za-z0-9.]', '_' } else { 'latest' }
        $tempRoot = $env:TEMP ?? [System.IO.Path]::GetTempPath()
        # Public-registry directories keep the unprefixed name so existing ones still work.
        $prefix = if ($hostName -eq 'registry.terraform.io') { '' } else { ($hostName -replace '[.:]', '_') + '-' }
        $WorkingDirectory = Join-Path $tempRoot "TerraformGraph\providers\$prefix$namespace-$name-$slug"
    }

    try {
        $directory = (New-Item -ItemType Directory -Path $WorkingDirectory -Force -ErrorAction Stop).FullName

        $requirement = if ($Version) {
            "      source  = `"$source`"", "      version = `"$Version`""
        }
        else {
            "      source = `"$source`""
        }
        $mainTf = @(
            'terraform {'
            '  required_providers {'
            "    $name = {"
            $requirement
            '    }'
            '  }'
            '}'
        )
        Set-Content -LiteralPath (Join-Path $directory 'main.tf') -Value $mainTf -ErrorAction Stop

        $lockFile = Join-Path $directory '.terraform.lock.hcl'
        if ($Force -and (Test-Path -LiteralPath $lockFile)) {
            # terraform init leaves an up-to-date lock file alone; remove it so versions are selected again.
            Remove-Item -LiteralPath $lockFile -Force -ErrorAction Stop
        }

        if (Test-Path -LiteralPath $lockFile) {
            Write-Verbose "Skipping terraform init; $lockFile exists. Use -Force to run it again."
        }
        else {
            Write-Verbose "terraform -chdir=$directory init -backend=false -input=false -no-color"
            $init = Invoke-TerraformCli -ArgumentList "-chdir=$directory", 'init', '-backend=false', '-input=false', '-no-color'
            if ($init.ExitCode -ne 0) {
                $message = (@($init.Stderr) | ForEach-Object { "$_" }) -join [Environment]::NewLine
                Stop-TerraformGraphCommand -Id 'TerraformInitFailed' -Category InvalidResult -Target $directory -Message "terraform init failed with exit code $($init.ExitCode) for provider '$namespace/$name' in '$directory'. Check the address and version with Get-TerraformRegistryProvider -Name '$namespace/$name', then rerun Get-TerraformProviderSchema -Provider '$namespace/$name' -Force.$([Environment]::NewLine)$message"
            }
        }

        $resolvedVersion = $null
        if (Test-Path -LiteralPath $lockFile) {
            $inProvider = $false
            foreach ($line in Get-Content -LiteralPath $lockFile) {
                if ($line -match '^\s*provider\s+"([^"]+)"') {
                    $inProvider = $Matches[1] -eq $address
                }
                elseif ($inProvider -and $line -match '^\s*version\s*=\s*"([^"]+)"') {
                    $resolvedVersion = $Matches[1]
                    break
                }
            }
        }
        if (-not $resolvedVersion -and $SaveToCache) {
            # No lock file entry: ask terraform which version this directory selected.
            $versionResult = Invoke-TerraformCli -ArgumentList "-chdir=$directory", 'version', '-json'
            if ($versionResult.ExitCode -eq 0) {
                $selections = ($versionResult.Stdout | ConvertFrom-TerraformJson -AsHashtable -ErrorAction SilentlyContinue).provider_selections
                if ($selections) {
                    $key = @($selections.Keys) | Where-Object { $_ -eq $address } | Select-Object -First 1
                    if ($key) { $resolvedVersion = [string]$selections[$key] }
                }
            }
        }
        Write-Verbose "Provider $address $($resolvedVersion ?? '(version not in lock file)') in $directory"

        if (-not $SaveToCache) {
            return Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat $OutputFormat
        }

        if (-not $resolvedVersion) {
            Stop-TerraformGraphCommand -Id 'TerraformVersionUnreadable' -Category InvalidResult -Target $directory -Message "Could not determine the selected version of $address in '$directory'; the schema was not saved to the cache. Rerun Get-TerraformProviderSchema -Provider '$address' -Version <version> -SaveToCache -Force with an explicit version."
        }
        $schema = Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat OrderedHashtable
        $cachePath = Write-TerraformSchemaCache -Provider $address -Version $resolvedVersion -Document $schema
        Write-Verbose "Saved $address $resolvedVersion to $cachePath"
        switch ($OutputFormat) {
            'OrderedHashtable' { $schema }
            'Json'             { $schema | ConvertTo-TerraformJson -ErrorAction Stop }
        }
    }
    finally {
        if ($Cleanup -and (Test-Path -LiteralPath $WorkingDirectory)) {
            Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force
        }
    }
}
