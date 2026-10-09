function Write-TerraformSchemaCache {
    # Not exported. Writes a document (dictionary, PSCustomObject or JSON text) for one
    # provider version as compact gzipped JSON, atomically: a temporary file in the same
    # folder, then Move-Item. Returns the path. -Kind Schema: other providers in the schema
    # document are dropped. -Kind Docs: the docs document is written as given.
    param([string]$Provider, [string]$Version, $Document, [ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    $address = (ConvertTo-TerraformProviderAddress -Provider $Provider).Address
    $path = Get-TerraformSchemaCachePath -Provider $address -Version $Version -Kind $Kind
    if ($Document -is [string]) { $Document = [TerraformGraph.Json]::Deserialize($Document, 1024, $true) }

    if ($Kind -eq 'Schema') {
        $schemas = Get-TerraformSchemaMember -InputObject $Document -Name 'provider_schemas'
        $keys = @(Get-TerraformSchemaKeys -InputObject $schemas)
        $key = $keys | Where-Object { $_ -eq $address } | Select-Object -First 1
        if (-not $key) {
            Stop-TerraformGraphCommand -Throw -Id 'SchemaProviderNotFound' -Category ObjectNotFound -Target $address -ExceptionType ([System.ArgumentException]) -Message "The schema document has no provider_schemas entry for $address. Fetch it with Get-TerraformProviderSchema -Provider '$address' -SaveToCache."
        }
        if ($keys.Count -gt 1) {
            $Document = [ordered]@{
                format_version   = Get-TerraformSchemaMember -InputObject $Document -Name 'format_version'
                provider_schemas = [ordered]@{ $key = Get-TerraformSchemaMember -InputObject $schemas -Name $key }
            }
        }
    }

    $directory = Split-Path -Path $path -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporary = Join-Path $directory ".$([guid]::NewGuid().ToString('n')).tmp"
    try {
        $file = [System.IO.File]::Create($temporary)
        try {
            $gzip = [System.IO.Compression.GZipStream]::new($file, [System.IO.Compression.CompressionLevel]::Optimal)
            $writer = [System.IO.StreamWriter]::new($gzip, [System.Text.UTF8Encoding]::new($false))
            $writer.Write([TerraformGraph.Json]::Serialize($Document, 1024, $true))
            $writer.Dispose()
        }
        finally {
            $file.Dispose()
        }
        Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    $path
}
