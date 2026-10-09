function Get-TerraformDocExample {
    # Not exported. The bodies of the ```hcl and ```terraform fenced code blocks in -Content,
    # in order. Other fences (shell, json, untagged) are left out.
    param([string]$Content)

    $pattern = '(?ms)^[ \t]*(`{3,}|~{3,})[ \t]*(?:hcl|terraform)\b[^\r\n]*\r?\n(.*?)\r?\n[ \t]*\1[ \t]*$'
    foreach ($match in [regex]::Matches($Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $match.Groups[2].Value
    }
}
