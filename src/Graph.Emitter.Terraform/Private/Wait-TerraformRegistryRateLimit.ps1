function Wait-TerraformRegistryRateLimit {
    # Not exported. The pause after a 429: Retry-After when given, else the ladder step, at
    # most $script:TerraformRegistryMaxWaitSeconds; then one worker, climbing again.
    param([double]$RetryAfter)

    $state = $script:TerraformRegistryThrottle
    $ladder = $script:TerraformRegistryBackoffSeconds
    $wait = if ($RetryAfter -gt 0) { $RetryAfter } else { $ladder[[math]::Min($state.Step, $ladder.Count - 1)] }
    $wait = [math]::Min($script:TerraformRegistryMaxWaitSeconds, [math]::Max(1, $wait))
    $state.Step++
    $state.Workers = 1
    $state.Climb = 0
    $state.SecondsBlocked += $wait
    Write-TerraformGraphLog "wait $wait s (block $($state.Step) in a row), then 1 worker"
    Write-Warning "$($script:TerraformRegistrySource) is rate limiting this address (429). Waiting $wait s, then resuming with one worker."
    Start-Sleep -Milliseconds ([int](1000 * $wait))
    $state.Blocked = $false
}
