<#
.SYNOPSIS
    Writes the generated function tables in CLAUDE.md and the shipped SKILL.md from the module.

.DESCRIPTION
    The first step at shrinking the hand-kept copies of the command list. Each table sits
    between two HTML comment markers:

        <!-- generated:functions (Invoke-Build GenerateDocTables) -->
        ...
        <!-- /generated:functions -->

    and is rebuilt from Get-Command (parameter sets, mandatory and optional parameters) and
    comment-based help read from the AST (.SYNOPSIS, the type names in .OUTPUTS). Prose outside the markers is
    hand-written and never touched. CLAUDE.md lists the functions in FunctionsToExport order;
    SKILL.md in pipeline order (the list below; a function missing from it goes last).

    Invoke-Build GenerateDocTables writes both files (then re-run
    Install-TerraformGraphSkill -Path . -Tool Claude -Force for the .claude copy). -Check
    writes nothing and returns one line per file whose table differs; Pester fails on any.

.PARAMETER RepoRoot
    Repository root. Default: the parent of this script's folder.

.PARAMETER Check
    Compare only; return the files that are out of date.

.EXAMPLE
    ./tools/Update-TerraformGraphDocTables.ps1 -Check
#>
[CmdletBinding()]
param(
    [string]
    $RepoRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [switch]
    $Check
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $RepoRoot 'src' 'Graph.Emitter.Terraform' 'Graph.Emitter.Terraform.psd1'
if (-not (Get-Module Graph.Emitter.Terraform)) {
    $env:TERRAFORMGRAPH_SKILL_HINT = '0'
    Import-Module $manifestPath -Verbose:$false
}
$exported = @((Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport)

$pipelineOrder = @(
    'Get-TerraformAST', 'Get-TerraformModuleGraph', 'ConvertTo-TerraformVariableGraph', 'Get-TerraformVariableTrace',
    'Update-TerraformRegistryCache', 'Get-TerraformRegistryProvider', 'Get-TerraformProviderSchema',
    'Get-TerraformSchemaPack', 'Get-TerraformSchemaCache', 'Update-TerraformProviderDocCache', 'Get-TerraformDocPack',
    'Get-TerraformDocCache', 'Get-TerraformProviderDoc', 'ConvertTo-TerraformSchemaGraph', 'ConvertTo-TerraformResourceGraph',
    'New-TerraformClassifier', 'Get-TerraformClassifier', 'Get-TerraformClassifierFinding', 'Get-TerraformGraphBundle',
    'New-TerraformGraphBundle', 'Test-TerraformGraphBundle', 'Get-TerraformSubcategorySurvey', 'ConvertTo-TerraformJson',
    'ConvertFrom-TerraformJson', 'Install-TerraformGraphSkill', 'Test-TerraformGraphSkill'
)
$common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters

$tick = '`'
$describe = {
    param([string]$Name)
    $command = Get-Command -Name $Name -Module Graph.Emitter.Terraform
    # Comment-based help straight from the AST: no help system, so no Update-Help prompt.
    $help = $command.ScriptBlock.Ast.GetHelpContent()
    $synopsis = ($help.Synopsis -replace '\s+', ' ').Trim()
    $outputText = @($help.Outputs) -join ' '
    $outputs = @([regex]::Matches($outputText, '\b(?:TerraformGraph|System)\.[A-Za-z.]*[A-Za-z]') | ForEach-Object Value | Select-Object -Unique)
    $sets = foreach ($set in $command.ParameterSets) {
        $parameters = foreach ($parameter in $set.Parameters) {
            if ($parameter.Name -in $common) { continue }
            if ($parameter.IsMandatory) { "-$($parameter.Name)" } else { "[-$($parameter.Name)]" }
        }
        $label = if ($command.ParameterSets.Count -gt 1) {
            $default = if ($set.IsDefault) { ' (default)' } else { '' }
            "$($set.Name)$default`: "
        }
        else { '' }
        $label + $tick + (@($parameters) -join ' ') + $tick
    }
    $line = '- ' + $tick + $Name + $tick + " — $synopsis " + (@($sets) -join '; ') + '.'
    if ($outputs.Count) { $line += ' Output: ' + (@($outputs | ForEach-Object { $tick + $_ + $tick }) -join ', ') + '.' }
    $line
}

$tables = [ordered]@{
    (Join-Path $RepoRoot 'CLAUDE.md')                                                = @($exported | ForEach-Object { & $describe $_ })
    (Join-Path $RepoRoot 'src' 'Graph.Emitter.Terraform' 'skills' 'terraformgraph' 'SKILL.md') = @(@($pipelineOrder | Where-Object { $_ -in $exported }) + @($exported | Where-Object { $_ -notin $pipelineOrder }) | ForEach-Object { & $describe $_ })
}

$begin = '<!-- generated:functions (Invoke-Build GenerateDocTables) -->'
$end = '<!-- /generated:functions -->'
foreach ($path in $tables.Keys) {
    $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $start = $text.IndexOf($begin)
    $stop = $text.IndexOf($end)
    if ($start -lt 0 -or $stop -lt $start) { throw "$path has no '$begin' ... '$end' block." }
    $generated = "$begin`n$($tables[$path] -join "`n")`n$end"
    $current = $text.Substring($start, $stop + $end.Length - $start)
    if ($Check) {
        if ($current -cne $generated) { "$path`: the generated function table is out of date. Run Invoke-Build GenerateDocTables." }
        continue
    }
    if ($current -cne $generated) {
        $updated = $text.Substring(0, $start) + $generated + $text.Substring($stop + $end.Length)
        [System.IO.File]::WriteAllText($path, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "Updated $path"
    }
}
