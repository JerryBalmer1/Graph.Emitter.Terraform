function Read-TerraformProviderSchemaFromDirectory {
    # Not exported. The Directory-set body of Get-TerraformProviderSchema; the
    # Provider set calls it against its own working directory.
    param(
        [Parameter(Mandatory)]
        [string]
        $WorkingDirectory,

        [string]
        $OutputFormat = 'OrderedHashtable'
    )

    Write-Verbose "terraform -chdir=$WorkingDirectory providers schema -json"

    $result = Invoke-TerraformCli -ArgumentList "-chdir=$WorkingDirectory", 'providers', 'schema', '-json'

    if ($result.ExitCode -ne 0) {
        $message = (@($result.Stderr) + @($result.Stdout) | ForEach-Object { "$_" }) -join [Environment]::NewLine
        Stop-TerraformGraphCommand -Throw -Id 'TerraformProvidersSchemaFailed' -Category InvalidResult -Target $WorkingDirectory -Message "terraform providers schema failed with exit code $($result.ExitCode) in '$WorkingDirectory'. Run terraform init in that folder first if providers are not installed, then rerun Get-TerraformProviderSchema.$([Environment]::NewLine)$message"
    }

    $schema = $result.Stdout | ConvertFrom-TerraformJson -AsHashtable -ErrorAction Stop

    switch ($OutputFormat) {
        'OrderedHashtable' { $schema }
        'Json'             { $schema | ConvertTo-TerraformJson -ErrorAction Stop }
    }
}
