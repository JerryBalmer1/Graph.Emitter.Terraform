function Invoke-TerraformRegistryRequest {
    # Not exported. GET one registry URL through Invoke-TerraformRegistryRequestSet, so it
    # shares the process rate state; returns the parsed JSON or throws the failure.
    param([string]$Uri)

    $result = Invoke-TerraformRegistryRequestSet -Request @([pscustomobject]@{ Key = $Uri; Uri = $Uri }) -ThrottleLimit 1
    if ($result.Error) { Stop-TerraformGraphCommand -Throw -Id 'RegistryRequestFailed' -Category ConnectionError -Target $Uri -Message $result.Error }
    $result.Value
}
