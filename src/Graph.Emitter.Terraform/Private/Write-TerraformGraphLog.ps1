function Write-TerraformGraphLog {
    # Not exported. Appends one timestamped line to the open harvest log, if any.
    param([string]$Line)

    if (-not $script:TerraformGraphLogPath) { return }
    $stamp = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    [System.IO.File]::AppendAllText($script:TerraformGraphLogPath, "$stamp $Line`n", [System.Text.UTF8Encoding]::new($false))
}
