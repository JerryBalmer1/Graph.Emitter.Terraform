function Install-TerraformGraphSkill {
    <#
    .SYNOPSIS
        Copies the TerraformGraph agent skill into a repository for one or more agent tools.

    .DESCRIPTION
        Install-TerraformGraphSkill copies the skills folder that ships with the module
        (skills/terraformgraph/SKILL.md, an Agent Skills SKILL.md) into the project skills
        folder of each agent tool under -Path, such as .claude/skills/terraformgraph for
        Claude. Files are copied, never linked.

        Without -Force, a file that already exists with the same content is left alone and
        a file that exists with different content is skipped with a verbose message, so a
        local edit is never lost. With -Force, differing files are overwritten. Running it
        again is safe.

        It also makes sure AGENTS.md at -Path points at the installed skill: a missing
        AGENTS.md is created with a short section, and an existing one gets that section
        appended once. The section starts with the marker line
        <!-- terraformgraph-skill -->; when the marker is already there AGENTS.md is not
        touched. Existing AGENTS.md content is never rewritten.

        Never touches the network.

    .PARAMETER Path
        Repository root. Defaults to the current location.

    .PARAMETER Tool
        Claude (default), Codex, Cursor, Gemini, Copilot, or All. Skills folders:
        .claude/skills, .codex/skills, .cursor/skills, .gemini/skills, .github/skills.

    .PARAMETER Force
        Overwrite installed files whose content differs from the bundled skill.

    .PARAMETER PassThru
        Return one TerraformGraph.SkillInstall per tool.

    .EXAMPLE
        Install-TerraformGraphSkill

        Copy the skill to .claude/skills/terraformgraph in the current directory and add
        the AGENTS.md section.

    .EXAMPLE
        Install-TerraformGraphSkill -Path C:\src\infra-live -Tool Claude, Cursor -PassThru

        Install for two tools and report what was written.

    .EXAMPLE
        Test-TerraformGraphSkill | Where-Object Stale | ForEach-Object { Install-TerraformGraphSkill -Tool $_.Tool -Force }

        Refresh every installed copy that no longer matches the module's skill, such as
        after a module upgrade.

    .OUTPUTS
        None, or TerraformGraph.SkillInstall with -PassThru: Tool, Path, SkillPath (the
        tool's skills folder), Status (Installed, Updated, Unchanged or Skipped) and Files
        (the number of files written).

    .NOTES
        Status: Installed when files were written and none existed before; Updated when
        files were written over or next to an earlier install; Unchanged when every file
        already matched; Skipped when nothing was written because files differ and -Force
        was not given.

    .LINK
        Test-TerraformGraphSkill
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]
        $Path = $PWD,

        [ValidateSet('Claude', 'Codex', 'Cursor', 'Gemini', 'Copilot', 'All')]
        [string[]]
        $Tool = 'Claude',

        [switch]
        $Force,

        [switch]
        $PassThru
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Stop-TerraformGraphCommand -Id 'SkillPathNotFound' -Category ObjectNotFound -Target $Path -ExceptionType ([System.IO.DirectoryNotFoundException]) -Message "Path '$Path' is not an existing directory. Create it with New-Item -ItemType Directory -Path '$Path', or pass an existing -Path."
    }
    $root = (Resolve-Path -LiteralPath $Path).ProviderPath
    $files = @(Get-TerraformGraphSkillFile)
    $tools = @(Resolve-TerraformGraphSkillTool -Tool $Tool)
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($name in $tools) {
        $skillsDir = Join-Path $root $script:TerraformGraphSkillTools[$name].SkillsDir
        $written = 0
        $existed = 0
        $skipped = 0
        foreach ($file in $files) {
            $target = Join-Path $skillsDir $file.Relative
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $existed++
                if (Test-TerraformGraphSkillFileEqual -Left $file.Source -Right $target) { continue }
                if (-not $Force) {
                    Write-Verbose "Skipping $target; it differs from the bundled skill. Use -Force to overwrite."
                    $skipped++
                    continue
                }
            }
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $target -Parent) -Force -ErrorAction Stop
            Copy-Item -LiteralPath $file.Source -Destination $target -Force -ErrorAction Stop
            Write-Verbose "Wrote $target"
            $written++
        }

        $status = if ($written -gt 0) { ($existed -gt 0) ? 'Updated' : 'Installed' }
        elseif ($skipped -gt 0) { 'Skipped' }
        else { 'Unchanged' }

        $results.Add([pscustomobject]@{
            PSTypeName = 'TerraformGraph.SkillInstall'
            Tool       = $name
            Path       = $root
            SkillPath  = $skillsDir
            Status     = $status
            Files      = $written
        })
    }

    # AGENTS.md: create, or append the section once. The marker guards repeat runs.
    $marker = '<!-- terraformgraph-skill -->'
    $agentsPath = Join-Path $root 'AGENTS.md'
    $existing = if (Test-Path -LiteralPath $agentsPath -PathType Leaf) { [System.IO.File]::ReadAllText($agentsPath) }
    if ($null -eq $existing -or -not $existing.Contains($marker)) {
        $section = @(
            $marker
            '## TerraformGraph skill'
            ''
            'This repository has the TerraformGraph agent skill (PowerShell module for parsing Terraform and graphing modules, variables, provider schemas and resources). Load it from:'
            ''
            foreach ($name in $tools) { "- ``$($script:TerraformGraphSkillTools[$name].SkillsDir)/terraformgraph/SKILL.md``" }
            ''
            'The copies are generated by Install-TerraformGraphSkill; re-run it to update them.'
        ) -join "`n"
        if ($null -eq $existing) {
            [System.IO.File]::WriteAllText($agentsPath, "# AGENTS.md`n`n$section`n")
        }
        else {
            $separator = if ($existing.Length -eq 0) { '' } elseif ($existing.EndsWith("`n")) { "`n" } else { "`n`n" }
            [System.IO.File]::AppendAllText($agentsPath, "$separator$section`n")
        }
        Write-Verbose "Wrote the TerraformGraph section to $agentsPath"
    }

    if ($PassThru) { $results.ToArray() }
}
