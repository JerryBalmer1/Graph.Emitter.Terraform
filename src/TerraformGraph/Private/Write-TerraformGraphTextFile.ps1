function Write-TerraformGraphTextFile {
    # Not exported. Writes -Text (UTF-8, no BOM) to -Path atomically: a temporary file in the
    # same folder, then Move-Item.
    param([string]$Path, [string]$Text)

    $directory = Split-Path -Path $Path -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporary = Join-Path $directory ".$([guid]::NewGuid().ToString('n')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, $Text, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
