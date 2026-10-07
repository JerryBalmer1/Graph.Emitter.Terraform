function Invoke-TerraformRegistryRequestSet {
    # Not exported. GETs every -Request (records with Key and Uri) from the registry under the
    # process rate state above, and writes one result per request to the pipeline as soon as
    # it completes: [pscustomobject]@{ Key; Uri; Value (parsed with TerraformGraph.Json, which
    # keeps date strings as strings); Error }. A request that fails for good (a 4xx other than
    # 429, no response, a sixth 429, JSON that does not parse) is a result with Error; the
    # caller decides whether that stops it. Requests run in chunks: up to -ThrottleLimit
    # workers (ForEach-Object -Parallel) when not throttled, one chunk per worker count while
    # climbing back, and in this runspace when the count is 1 or an invoker is injected.
    param([object[]]$Request, [int]$ThrottleLimit = 6)

    $state = $script:TerraformRegistryThrottle
    $invoker = $script:TerraformRegistryInvoker
    $queue = [System.Collections.Generic.LinkedList[object]]::new()
    foreach ($item in $Request) { $null = $queue.AddLast([pscustomobject]@{ Key = $item.Key; Uri = $item.Uri; Waits = 0 }) }
    $httpDefinition = ${function:Invoke-TerraformRegistryHttp}.ToString()

    while ($queue.Count) {
        $workers = if ($state.Workers -gt 0) { [math]::Min($state.Workers, $ThrottleLimit) } else { $ThrottleLimit }
        $climbing = $state.Workers -gt 0 -and $state.Workers -lt $ThrottleLimit
        $size = if ($climbing) { $workers } else { [math]::Max($workers, $script:TerraformRegistryChunkSize) }
        $chunk = [System.Collections.Generic.List[object]]::new()
        while ($queue.Count -and $chunk.Count -lt $size) {
            $chunk.Add($queue.First.Value)
            $queue.RemoveFirst()
        }
        $state.History.Add($workers)

        # Each outcome is handled as it arrives, so a caller that is stopped (Ctrl+C) has every
        # page that completed before the stop, not only whole chunks.
        $again = [System.Collections.Generic.List[object]]::new()
        $limited = [System.Collections.Generic.List[double]]::new()
        $handle = {
            param($Item, $Response)
            if ($null -eq $Response) { $again.Add($Item); return }
            $status = [int]$Response.StatusCode
            if ($status -eq 429) {
                $state.Hits++
                $Item.Waits++
                $limited.Add([double]($Response.RetryAfter ?? 0))
                Write-TerraformGraphLog "429 $($Item.Uri)$(if ($Response.RetryAfter) { " (Retry-After $($Response.RetryAfter) s)" })"
                if ($Item.Waits -gt $script:TerraformRegistryBackoffSeconds.Count) {
                    [pscustomobject]@{ Key = $Item.Key; Uri = $Item.Uri; Value = $null; Error = "GET $($Item.Uri) was rate limited (429) $($Item.Waits) times in a row; the registry is still blocking this address. Wait 10 minutes, then run the same command again." }
                }
                else {
                    $again.Add($Item)
                }
                return
            }
            if ($status -ge 200 -and $status -lt 300) {
                $value = $null
                $parseError = $null
                try { $value = [TerraformGraph.Json]::Deserialize([string]$Response.Content, 1024, $false) }
                catch { $parseError = "GET $($Item.Uri) returned JSON that does not parse: $($_.Exception.Message)" }
                if (-not $parseError) {
                    $state.Step = 0
                    if ($state.Workers -gt 0 -and $state.Workers -lt $ThrottleLimit) {
                        $state.Climb++
                        if ($state.Climb -ge $script:TerraformRegistryClimbAfter) {
                            $state.Climb = 0
                            $state.Workers++
                        }
                    }
                }
                [pscustomobject]@{ Key = $Item.Key; Uri = $Item.Uri; Value = $value; Error = $parseError }
                return
            }
            $message = if ($status -eq 0) { "GET $($Item.Uri) failed: $($Response.Error)" } else { "GET $($Item.Uri) returned HTTP $status." }
            [pscustomobject]@{ Key = $Item.Key; Uri = $Item.Uri; Value = $null; Error = $message }
        }

        if ($workers -le 1 -or $invoker) {
            foreach ($item in $chunk) {
                if ($state.Blocked) { $again.Add($item); continue }
                $response = try {
                    if ($invoker) { & $invoker $item.Uri } else { Invoke-TerraformRegistryHttp -Uri $item.Uri }
                }
                catch {
                    @{ StatusCode = 0; Content = $null; RetryAfter = $null; Error = $_.Exception.Message }
                }
                if ([int]$response.StatusCode -eq 429) { $state.Blocked = $true }
                & $handle $item $response
            }
        }
        else {
            $chunk | ForEach-Object -ThrottleLimit $workers -Parallel {
                $shared = $using:state
                $item = $_
                # A worker that starts after another worker's 429 does not send its request.
                if ($shared.Blocked) { return [pscustomobject]@{ Item = $item; Response = $null } }
                Set-Item -Path function:Invoke-TerraformRegistryHttp -Value $using:httpDefinition
                $response = Invoke-TerraformRegistryHttp -Uri $item.Uri
                if ([int]$response.StatusCode -eq 429) { $shared.Blocked = $true }
                [pscustomobject]@{ Item = $item; Response = $response }
            } | ForEach-Object { & $handle $_.Item $_.Response }
        }

        # Back to the front of the queue in their original order.
        for ($i = $again.Count - 1; $i -ge 0; $i--) { $null = $queue.AddFirst($again[$i]) }
        if ($limited.Count) {
            if ($queue.Count) { Wait-TerraformRegistryRateLimit -RetryAfter ([System.Linq.Enumerable]::Max($limited)) }
            else { $state.Blocked = $false }
        }
    }
}
