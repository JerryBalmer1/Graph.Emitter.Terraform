function ConvertTo-TerraformGraphBundleSourceObject {
    # Not exported. A bundle's sources block as TerraformGraph.BundleSource rows.
    param([object[]]$Source)

    foreach ($item in $Source) {
        if ($item -isnot [System.Collections.IDictionary]) { continue }
        [pscustomobject]@{
            PSTypeName  = 'TerraformGraph.BundleSource'
            Kind        = [string]$item['kind']
            Urls        = [string[]]@($item['urls'] | Where-Object { $null -ne $_ })
            RelatedUrls = [string[]]@($item['relatedUrls'] | Where-Object { $null -ne $_ })
            HarvestedBy = $item['harvestedBy']
            LastPulled  = $item['lastPulled']
        }
    }
}
