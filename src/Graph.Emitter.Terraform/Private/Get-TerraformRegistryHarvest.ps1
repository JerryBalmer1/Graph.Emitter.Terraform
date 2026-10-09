function Get-TerraformRegistryHarvest {
    # Not exported. Lists providers and fetches every provider's versions from the public
    # registry. Probed 2026-10-06:
    #
    #   List: GET https://registry.terraform.io/v2/providers?filter[tier]=official,partner&page[size]=100&page[number]=N
    #     page[size] is capped at 100; meta.pagination has total-pages, total-count,
    #     next-page (null on the last page). Without filter[tier] it lists every tier
    #     (7418 providers on 2026-10-06; official,partner 428). Tier is attributes.tier:
    #     official | partner | community. One data[] element:
    #       { "type": "providers", "id": "5246",
    #         "attributes": { "alias": null, "description": "Management of Ansible ...",
    #           "downloads": 573672, "featured": false, "full-name": "ansible/aap",
    #           "logo-url": "/images/providers/hashicorp.svg", "name": "aap",
    #           "namespace": "ansible", "owner-name": "", "repository-id": 702581735,
    #           "robots-noindex": false, "source": "https://github.com/ansible/terraform-provider-aap",
    #           "tier": "official", "unlisted": false, "warning": "" },
    #         "links": { "self": "/v2/providers/5246" } }
    #     (v1 /v1/providers?limit=&offset= also pages and carries tier, but lists one row
    #     per provider version, so v2 is used.)
    #
    #   Versions, two calls per provider because neither has every field:
    #   GET https://registry.terraform.io/v1/providers/<namespace>/<name>/versions
    #     protocols, no publish date. One versions[] element:
    #       { "version": "1.0.0", "protocols": [ "4" ], "platforms": [ { "os": "linux", "arch": "386" }, ... ] }
    #   GET https://registry.terraform.io/v2/providers/<namespace>/<name>?include=provider-versions
    #     publish date, no protocols; included[] is complete (509 for hashicorp/aws). One element:
    #       { "type": "provider-versions", "id": "2672",
    #         "attributes": { "description": "terraform-provider-null", "downloads": 394605,
    #           "published-at": "2019-04-11T23:12:14Z", "tag": "v2.1.1", "version": "2.1.1" },
    #         "links": { "self": "/v2/provider-versions/2672" } }
    param(
        [ValidateSet('OfficialPartner', 'All')]
        [string]
        $Scope,

        [int]
        $ThrottleLimit
    )

    $registry = "https://$($script:TerraformRegistrySource)"
    $filter = if ($Scope -eq 'OfficialPartner') { '&filter[tier]=official,partner' } else { '' }

    $listed = [System.Collections.Generic.List[object]]::new()
    $page = 1
    while ($page) {
        $response = Invoke-TerraformRegistryRequest -Uri "$registry/v2/providers?page[size]=100&page[number]=$page$filter"
        $pagination = $response.meta.pagination
        $total = [int]$pagination.'total-pages'
        Write-Progress -Id 1 -Activity 'Listing registry providers' -Status "Page $page of $total" -PercentComplete ([math]::Min(100, 100 * $page / [math]::Max(1, $total)))
        foreach ($item in @($response.data)) {
            $attributes = $item.attributes
            $listed.Add([pscustomobject]@{
                Namespace   = [string]$attributes.namespace
                Name        = [string]$attributes.name
                Tier        = [string]$attributes.tier
                Description = [string]$attributes.description
            })
        }
        $page = $pagination.'next-page'
    }
    Write-Progress -Id 1 -Activity 'Listing registry providers' -Completed
    Write-Verbose "Listed $($listed.Count) providers"

    # Two requests per provider through the shared rate state; results by Key.
    $requests = foreach ($provider in $listed) {
        $path = "$($provider.Namespace)/$($provider.Name)"
        [pscustomobject]@{ Key = "v1|$path"; Uri = "$registry/v1/providers/$path/versions" }
        [pscustomobject]@{ Key = "v2|$path"; Uri = "$registry/v2/providers/${path}?include=provider-versions" }
    }
    $results = @{}
    Invoke-TerraformRegistryRequestSet -Request @($requests) -ThrottleLimit $ThrottleLimit | ForEach-Object {
        $results[$_.Key] = $_
        Write-Progress -Id 1 -Activity 'Fetching provider versions' -Status "$($results.Count) of $(2 * $listed.Count) requests" -PercentComplete (50 * $results.Count / [math]::Max(1, $listed.Count))
    }
    Write-Progress -Id 1 -Activity 'Fetching provider versions' -Completed

    $fetched = foreach ($provider in $listed) {
        $path = "$($provider.Namespace)/$($provider.Name)"
        $v1 = $results["v1|$path"]
        $v2 = $results["v2|$path"]
        $errorText = if ($v1.Error) { $v1.Error } elseif ($v2.Error) { $v2.Error } else { $null }
        if ($errorText) {
            [pscustomobject]@{ Provider = $provider; Versions = $null; Error = $errorText }
            continue
        }
        $published = @{}
        foreach ($included in @($v2.Value.included)) {
            if ($included.type -eq 'provider-versions') { $published[[string]$included.attributes.version] = $included.attributes.'published-at' }
        }
        $versions = foreach ($version in @($v1.Value.versions)) {
            [pscustomobject]@{
                Version   = [string]$version.version
                Protocols = [string[]]@($version.protocols)
                Published = $published[[string]$version.version]
            }
        }
        [pscustomobject]@{ Provider = $provider; Versions = @($versions); Error = $null }
    }

    $failed = @($fetched | Where-Object Error)
    if ($failed.Count) {
        $names = @($failed | Select-Object -First 10 | ForEach-Object { "$($_.Provider.Namespace)/$($_.Provider.Name) ($($_.Error))" })
        Stop-TerraformGraphCommand -Throw -Id 'RegistryHarvestFailed' -Category ConnectionError -Target $script:TerraformRegistrySource -Message "Failed to fetch versions for $($failed.Count) providers: $($names -join '; ')$(if ($failed.Count -gt 10) { '; ...' }). The cache was not written."
    }

    $fetched
}
