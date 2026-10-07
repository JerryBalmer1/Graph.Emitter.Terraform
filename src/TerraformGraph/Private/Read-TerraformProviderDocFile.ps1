function Read-TerraformProviderDocFile {
    # Not exported. Every doc in one docs cache file as TerraformGraph.ProviderDoc, plus an
    # Id index: @{ Docs; ById }. Parsed once per file version and kept in memory, so a
    # pipeline of many nodes reads each file once. Callers copy before changing a doc.
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    $key = "$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
    $memo = $script:TerraformDocCacheMemo[$item.FullName]
    if ($memo -and $memo.Key -ceq $key) { return $memo.Value }

    $document = Read-TerraformSchemaCache -Path $item.FullName
    $address = [string]$document['address']
    $version = [string]$document['version']
    $byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $docs = foreach ($doc in @($document['docs'])) {
        $id = [string]$doc['id']
        $type = if ($id -match '^[^/]+/[^/]+/[^/]+/(?:resource|data)/([^/]+)$') { $Matches[1] } else { $null }
        $node = [pscustomobject]@{
            PSTypeName      = 'TerraformGraph.ProviderDoc'
            Id              = $id
            ProviderAddress = $address
            Version         = $version
            Category        = [string]$doc['category']
            Title           = [string]$doc['title']
            Subcategory     = $doc['subcategory']
            Slug            = [string]$doc['slug']
            Type            = $type
            Content         = [string]$doc['content']
            ExampleCount    = $null
        }
        $byId[$id] = $node
        $node
    }
    $value = @{ Docs = @($docs); ById = $byId }
    $script:TerraformDocCacheMemo[$item.FullName] = @{ Key = $key; Value = $value }
    $value
}
