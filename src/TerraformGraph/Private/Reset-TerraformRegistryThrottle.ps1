function Reset-TerraformRegistryThrottle {
    # Not exported. Starts the process rate state over: no block, no throttle, no counts.
    # History holds the worker count of every chunk dispatched, for tests and -Verbose.
    $script:TerraformRegistryThrottle = [hashtable]::Synchronized(@{
            Workers        = 0
            Climb          = 0
            Step           = 0
            Blocked        = $false
            Hits           = 0
            SecondsBlocked = 0.0
            History        = [System.Collections.Generic.List[int]]::new()
        })
}
