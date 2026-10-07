function Get-TerraformSchemaCacheEntry {
    # Not exported. Every cached file of -Kind, by address, newest version first:
    # TerraformGraph.CachedSchema or TerraformGraph.CachedDoc. Schema: the address is the
    # first provider_schemas key. Docs: address, docCount and unmatchedCount are the first
    # members. Both are read from the first few KB, so listing never decompresses a whole
    # file; a file that does not start that way is parsed in full.
    param([ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    $root = if ($Kind -eq 'Docs') { $script:TerraformDocCacheRoot } else { $script:TerraformSchemaCacheRoot }
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { return }

    $entries = foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json.gz' -File -Recurse -Depth 1) {
        try {
            $head = Read-TerraformSchemaCacheText -Path $file.FullName -MaxChars 4096
            $version = $file.Name.Substring(0, $file.Name.Length - '.json.gz'.Length)
            if ($Kind -eq 'Docs') {
                if ($head -match '^\s*\{\s*"address"\s*:\s*"([^"]+)"' -and $head -match '"docCount"\s*:\s*(\d+)') {
                    $address = $head -replace '(?s)^\s*\{\s*"address"\s*:\s*"([^"]+)".*$', '$1'
                    $docCount = [int]$Matches[1]
                    $unmatchedCount = if ($head -match '"unmatchedCount"\s*:\s*(\d+)') { [int]$Matches[1] } else { $null }
                    $harvestedOn = if ($head -match '"harvestedOn"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }
                }
                else {
                    $document = Read-TerraformSchemaCache -Path $file.FullName
                    $address = $document['address']
                    $docCount = @($document['docs']).Count
                    $unmatchedCount = $document['unmatchedCount']
                    $harvestedOn = $document['harvestedOn']
                }
                if (-not $address) { continue }
                [pscustomobject]@{
                    PSTypeName      = 'TerraformGraph.CachedDoc'
                    ProviderAddress = [string]$address
                    Version         = $version
                    Path            = $file.FullName
                    Bytes           = $file.Length
                    CachedOn        = $file.LastWriteTimeUtc
                    DocCount        = $docCount
                    UnmatchedCount  = $unmatchedCount
                    HarvestedOn     = $harvestedOn
                }
                continue
            }
            $address = if ($head -match '"provider_schemas"\s*:\s*\{\s*"([^"]+)"') {
                $Matches[1]
            }
            else {
                @(Get-TerraformSchemaKeys -InputObject (Read-TerraformSchemaCache -Path $file.FullName).provider_schemas)[0]
            }
            if (-not $address) { continue }
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.CachedSchema'
                ProviderAddress = [string]$address
                Version         = $version
                Path            = $file.FullName
                Bytes           = $file.Length
                CachedOn        = $file.LastWriteTimeUtc
            }
        }
        catch {
            Write-Verbose "Skipping $($file.FullName): $($_.Exception.Message)"
        }
    }

    foreach ($group in @($entries | Group-Object { $_.ProviderAddress.ToLowerInvariant() } | Sort-Object Name -Culture '')) {
        foreach ($sorted in Sort-TerraformRegistryVersion -Versions @($group.Group)) { $sorted.Record }
    }
}
