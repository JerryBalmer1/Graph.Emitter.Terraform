function ConvertTo-TerraformProviderDocDocument {
    # Not exported. The docs cache document for harvested -Docs records: Ids resolved
    # against -Index, sorted overview, guides, resources, data-sources, then by slug.
    # address, version and the counts come first so listing reads them from the head.
    param([string]$Address, [string]$Version, [object[]]$Docs, $Index, [string]$Prefix)

    $rank = @{ 'overview' = 0; 'guides' = 1; 'resources' = 2; 'data-sources' = 3 }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($doc in $Docs) {
        $resolved = Resolve-TerraformProviderDocId -Address $Address -Category $doc.Category -Slug $doc.Slug -Index $Index -Prefix $Prefix
        $list.Add([pscustomobject]@{ Doc = $doc; Resolved = $resolved })
    }
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            $byCategory = ([int]$rank[$a.Doc.Category]).CompareTo([int]$rank[$b.Doc.Category])
            if ($byCategory) { return $byCategory }
            [string]::CompareOrdinal($a.Doc.Slug, $b.Doc.Slug)
        })

    $unmatched = @($list | Where-Object { $_.Resolved.Matched -eq $false })
    [ordered]@{
        address        = $Address
        version        = $Version
        harvestedOn    = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        schemaVersion  = if ($Index) { $Index.SchemaVersion } else { $null }
        docCount       = $list.Count
        unmatchedCount = if ($Index) { $unmatched.Count } else { $null }
        docs           = [object[]]@(foreach ($item in $list) {
                [ordered]@{
                    id          = $item.Resolved.Id
                    category    = $item.Doc.Category
                    title       = $item.Doc.Title
                    subcategory = $item.Doc.Subcategory
                    slug        = $item.Doc.Slug
                    content     = $item.Doc.Content
                }
            })
    }
}
