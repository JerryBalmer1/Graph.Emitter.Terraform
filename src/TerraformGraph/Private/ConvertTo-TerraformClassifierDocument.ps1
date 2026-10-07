function ConvertTo-TerraformClassifierDocument {
    # Not exported. The classifier document for one provider version. Types come from the
    # schema entry (resource_schemas, data_source_schemas), so a type with no doc page is a
    # NoDocPage finding rather than missing. Each type's subcategory is its doc page's; a
    # provider row in -Map wins over a '*' row. Doc pages with unmatched Ids document no
    # schema type and are left out. Types and findings are sorted by type, then kind
    # (data-source before resource), so the same inputs always give the same document.
    param([string]$Address, [string]$Version, [string]$DocsVersion, $SchemaEntry, [object[]]$Docs, $Map, [string]$GeneratedOn)

    $docById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($doc in $Docs) {
        if ($doc.Category -in 'resources', 'data-sources') { $docById[[string]$doc.Id] = $doc }
    }

    $types = [System.Collections.Generic.List[object]]::new()
    foreach ($section in @(
            @{ Key = 'resource_schemas';    Kind = 'resource';    Segment = 'resource' }
            @{ Key = 'data_source_schemas'; Kind = 'data-source'; Segment = 'data' }
        )) {
        $schemas = $SchemaEntry[$section.Key]
        if ($null -eq $schemas) { continue }
        foreach ($type in @($schemas.Keys)) {
            $doc = $null
            $null = $docById.TryGetValue("$Address/$($section.Segment)/$type", [ref]$doc)
            $subcategory = if ($doc -and -not [string]::IsNullOrEmpty([string]$doc.Subcategory)) { [string]$doc.Subcategory } else { $null }
            $row = $null
            $source = $null
            if ($subcategory) {
                if (-not $Map.Lookup.TryGetValue("$Address`n$subcategory", [ref]$row)) {
                    $null = $Map.Lookup.TryGetValue("*`n$subcategory", [ref]$row)
                }
                if ($row) { $source = 'subcategory' }
            }
            else {
                # Prefix rows place only types with no label: no doc page, or an empty
                # subcategory. A label the map does not place stays UnmappedSubcategory.
                $row = Get-TerraformClassifierPrefixRow -Map $Map -Address $Address -Type ([string]$type)
                if ($row) { $source = 'prefix' }
            }
            $finding = if ($row) { $null } elseif (-not $doc) { 'NoDocPage' } elseif (-not $subcategory) { 'NoSubcategory' } else { 'UnmappedSubcategory' }
            $types.Add([pscustomobject]@{
                Type        = [string]$type
                Kind        = $section.Kind
                Subcategory = $subcategory
                Drawer      = if ($row) { [string]$row['drawer'] } else { 'unclassified' }
                Source      = $source
                Finding     = $finding
            })
        }
    }
    $types.Sort([System.Comparison[object]] {
            param($a, $b)
            $byType = [string]::CompareOrdinal($a.Type, $b.Type)
            if ($byType) { return $byType }
            [string]::CompareOrdinal($a.Kind, $b.Kind)
        })

    [ordered]@{
        provider    = $Address
        version     = $Version
        docsVersion = $DocsVersion
        generatedOn = $GeneratedOn
        mapVersion  = $Map.MapVersion
        source      = if ($types | Where-Object Source -ceq 'prefix') { 'subcategory,prefix' } else { 'subcategory' }
        types       = [object[]]@(foreach ($item in $types) {
                [ordered]@{ type = $item.Type; kind = $item.Kind; subcategory = $item.Subcategory; drawer = $item.Drawer; source = $item.Source }
            })
        findings    = [object[]]@(foreach ($item in $types) {
                if ($item.Finding) { [ordered]@{ type = $item.Type; kind = $item.Kind; subcategory = $item.Subcategory; finding = $item.Finding } }
            })
    }
}
