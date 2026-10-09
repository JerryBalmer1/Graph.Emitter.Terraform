function Test-TerraformGraphSkillFileEqual {
    # Not exported. True when both files exist with the same bytes.
    param([string]$Left, [string]$Right)
    if (-not (Test-Path -LiteralPath $Right -PathType Leaf)) { return $false }
    (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
}
