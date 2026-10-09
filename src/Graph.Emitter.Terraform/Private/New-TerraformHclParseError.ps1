function New-TerraformHclParseError {
    param([string]$Message, [string]$Path)
    [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new("$Message Fix the file, then rerun Get-TerraformAST -FilePath '$Path' (terraform validate in its folder reports the same error)."),
        'HclParseError',
        [System.Management.Automation.ErrorCategory]::ParserError,
        $Path)
}
