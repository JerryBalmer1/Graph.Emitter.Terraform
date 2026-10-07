function Save-TerraformSchemaPackFile {
    # Not exported. Copies <Source>/<Name> to -Destination: a download for an http(s)
    # Source, a file copy for a directory. The only network call in the pack code.
    #
    # A GitHub release Source (https://github.com/<owner>/<repo>/releases/latest/download or
    # .../releases/download/<tag>) with $env:GH_TOKEN or $env:GITHUB_TOKEN set goes through
    # the API instead, because releases/.../download/<file> is 404 for a private repo even
    # with a token: GET api.github.com/repos/<owner>/<repo>/releases/latest (or
    # /releases/tags/<tag>) with Authorization: Bearer, find the asset by name, then GET its
    # api url with Accept: application/octet-stream. -State is a hashtable the caller keeps
    # for one pack run so the release is looked up once. Without a token the anonymous URL is
    # used, and a 404 names GH_TOKEN for a private fork.
    param([string]$Source, [string]$Name, [string]$Destination, [hashtable]$State = @{})

    if ($Source -notmatch '^https?://') {
        Copy-Item -LiteralPath (Join-Path $Source $Name) -Destination $Destination -ErrorAction Stop
        return
    }

    $token = if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
    $github = [regex]::Match($Source.TrimEnd('/'), '^https://github\.com/([^/]+)/([^/]+)/releases/(?:latest/download|download/([^/]+))$', 'IgnoreCase')

    if ($github.Success -and $token) {
        $owner = $github.Groups[1].Value
        $repo = $github.Groups[2].Value
        $tag = if ($github.Groups[3].Success) { $github.Groups[3].Value } else { $null }
        $headers = @{ Authorization = "Bearer $token"; 'X-GitHub-Api-Version' = '2022-11-28' }
        $releaseUri = if ($tag) { "https://api.github.com/repos/$owner/$repo/releases/tags/$([uri]::EscapeDataString($tag))" } else { "https://api.github.com/repos/$owner/$repo/releases/latest" }
        if (-not $State.ContainsKey($releaseUri)) {
            $State[$releaseUri] = Invoke-RestMethod -Uri $releaseUri -Headers ($headers + @{ Accept = 'application/vnd.github+json' }) -TimeoutSec 60 -ErrorAction Stop
        }
        $release = $State[$releaseUri]
        $asset = @($release.assets) | Where-Object { $_.name -ceq $Name } | Select-Object -First 1
        if (-not $asset) {
            Stop-TerraformGraphCommand -Throw -Id 'PackAssetNotFound' -Category ObjectNotFound -Target $Name -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "Release $($release.tag_name) of $owner/$repo has no asset named $Name. Pass -Source with a release or folder that has it (Get-TerraformSchemaPack -Source <url-or-folder>)."
        }
        $null = Invoke-WebRequest -Uri $asset.url -Headers ($headers + @{ Accept = 'application/octet-stream' }) -OutFile $Destination -TimeoutSec 600 -ErrorAction Stop
        return
    }

    try {
        $null = Invoke-WebRequest -Uri "$($Source.TrimEnd('/'))/$Name" -OutFile $Destination -TimeoutSec 600 -ErrorAction Stop
    }
    catch {
        $status = [int]$_.Exception.Response.StatusCode
        if ($status -eq 404 -and $github.Success) {
            Stop-TerraformGraphCommand -Throw -Id 'PackAssetNotFound' -Category ObjectNotFound -Target $Name -InnerException $_.Exception -Message "$Name was not found at $Source (404). For a private fork, set `$env:GH_TOKEN (or `$env:GITHUB_TOKEN) to a token that can read it, and the download goes through the GitHub API."
        }
        throw
    }
}
