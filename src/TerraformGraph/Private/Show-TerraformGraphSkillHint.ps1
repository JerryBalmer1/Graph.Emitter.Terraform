function Show-TerraformGraphSkillHint {
    # Not exported. Runs once at import: one host line when the current directory uses an
    # agent tool that does not have the skill. Silent otherwise, and when
    # TERRAFORMGRAPH_SKILL_HINT is '0'. Reads a few local paths; never throws.
    try {
        if ($env:TERRAFORMGRAPH_SKILL_HINT -eq '0') { return }
        $location = Get-Location -PSProvider FileSystem -ErrorAction Stop
        $missing = @(Test-TerraformGraphSkill -Path $location.ProviderPath -ErrorAction Stop |
            Where-Object { $_.Detected -and -not $_.Installed } |
            ForEach-Object Tool)
        if ($missing.Count -eq 0) { return }
        Write-Host "TerraformGraph: detected $($missing -join ', ') in this directory. Run Install-TerraformGraphSkill -Tool $($missing -join ',') to give them the TerraformGraph skill."
    }
    catch {
        Write-Verbose "TerraformGraph skill hint skipped: $($_.Exception.Message)"
    }
}
