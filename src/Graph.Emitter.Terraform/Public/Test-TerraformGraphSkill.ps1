function Test-TerraformGraphSkill {
    <#
    .SYNOPSIS
        Reports which agent tools a repository uses and whether the Graph.Emitter.Terraform skill is installed for them.

    .DESCRIPTION
        Test-TerraformGraphSkill checks -Path for each agent tool: Detected when the tool's
        marker exists (.claude, .codex, .cursor, .gemini, or .github/copilot-instructions.md),
        Installed when every bundled skill file is in the tool's skills folder, and Stale
        when it is installed but at least one file differs from the skill shipped with the
        module. It only reads.

    .PARAMETER Path
        Repository root. Defaults to the current location.

    .PARAMETER Tool
        Claude, Codex, Cursor, Gemini, Copilot, or All (default).

    .EXAMPLE
        Test-TerraformGraphSkill

        Status of every tool in the current directory.

    .EXAMPLE
        Test-TerraformGraphSkill -Path C:\src\infra-live | Where-Object { $_.Detected -and -not $_.Installed }

        Tools the repository uses that do not have the skill yet.

    .OUTPUTS
        TerraformGraph.SkillStatus: Tool, Detected, Installed, Stale, SkillPath (the tool's
        skills folder).

    .LINK
        Install-TerraformGraphSkill
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]
        $Path = $PWD,

        [ValidateSet('Claude', 'Codex', 'Cursor', 'Gemini', 'Copilot', 'All')]
        [string[]]
        $Tool = 'All'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Stop-TerraformGraphCommand -Id 'SkillPathNotFound' -Category ObjectNotFound -Target $Path -ExceptionType ([System.IO.DirectoryNotFoundException]) -Message "Path '$Path' is not an existing directory. Create it with New-Item -ItemType Directory -Path '$Path', or pass an existing -Path."
    }
    $root = (Resolve-Path -LiteralPath $Path).ProviderPath
    $files = @(Get-TerraformGraphSkillFile)

    foreach ($name in Resolve-TerraformGraphSkillTool -Tool $Tool) {
        $entry = $script:TerraformGraphSkillTools[$name]
        $skillsDir = Join-Path $root $entry.SkillsDir
        $installed = $files.Count -gt 0
        $stale = $false
        foreach ($file in $files) {
            $target = Join-Path $skillsDir $file.Relative
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { $installed = $false; break }
            if (-not $stale -and -not (Test-TerraformGraphSkillFileEqual -Left $file.Source -Right $target)) { $stale = $true }
        }

        [pscustomobject]@{
            PSTypeName = 'TerraformGraph.SkillStatus'
            Tool       = $name
            Detected   = Test-Path -LiteralPath (Join-Path $root $entry.Marker)
            Installed  = $installed
            Stale      = $installed -and $stale
            SkillPath  = $skillsDir
        }
    }
}
