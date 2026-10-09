function Invoke-TerraformCli {
    # Not exported. Runs terraform with stdout read as UTF-8 (schema descriptions
    # contain non-ASCII text) and splits stdout from stderr.
    param(
        [Parameter(Mandatory)]
        [string[]]
        $ArgumentList
    )

    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $output = & terraform @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Stdout   = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        Stderr   = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
}
