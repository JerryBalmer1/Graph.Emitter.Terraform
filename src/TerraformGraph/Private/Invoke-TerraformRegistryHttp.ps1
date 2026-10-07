function Invoke-TerraformRegistryHttp {
    # Not exported. One GET with 5xx retried after 2, 4, 8, 16 and 32 s. Never throws for an
    # HTTP status: returns @{ StatusCode; Content; RetryAfter (seconds or $null); Error }, and
    # 429 goes back to Invoke-TerraformRegistryRequestSet, which owns the rate state.
    # StatusCode 0 with Error is a failure with no response (DNS, TLS, timeout). Also defined
    # inside ForEach-Object -Parallel runspaces from this text, so keep it self-contained.
    param([string]$Uri)

    for ($attempt = 0; ; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 60 -SkipHttpErrorCheck -ErrorAction Stop
        }
        catch {
            return @{ StatusCode = 0; Content = $null; RetryAfter = $null; Error = $_.Exception.Message }
        }
        $status = [int]$response.StatusCode
        if ($status -ge 500 -and $attempt -lt 5) {
            Start-Sleep -Seconds ([math]::Pow(2, $attempt + 1))
            continue
        }
        # application/vnd.api+json (v2) comes back as bytes, application/json (v1) as text.
        $content = $response.Content
        if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
        $retryAfter = $null
        $values = $null
        if ($response.Headers -and $response.Headers.TryGetValue('Retry-After', [ref]$values)) {
            $header = [string]@($values)[0]
            $seconds = 0
            $date = [System.DateTimeOffset]::MinValue
            if ([int]::TryParse($header, [ref]$seconds)) { $retryAfter = [double]$seconds }
            elseif ([System.DateTimeOffset]::TryParse($header, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
                $retryAfter = ($date - [System.DateTimeOffset]::UtcNow).TotalSeconds
            }
        }
        return @{ StatusCode = $status; Content = [string]$content; RetryAfter = $retryAfter; Error = $null }
    }
}
