<#
.SYNOPSIS
    Runs the Graph.Emitter.Terraform Pester suite in the current process.

.DESCRIPTION
    The default run excludes tests tagged Live (registry calls and terraform init that
    downloads providers), so it needs no network. Tests tagged RequiresTerraform need the
    terraform binary but no network; they are skipped, not failed, when terraform is not on
    PATH.

    -Live runs only the Live tests; -All runs everything. Both set TERRAFORMGRAPH_LIVE=1 for
    the run, and both spend the registry's rate budget: never run them while a harvest
    (Invoke-Build HarvestBundleDocs, Update-TerraformRegistryCache) is going.

    The native parser DLL is pinned for the life of a process, so after a Go rebuild run this
    in a fresh one: pwsh -NoProfile -File .\tests\Invoke-Tests.ps1

.PARAMETER Live
    Only the Live tests.

.PARAMETER All
    Every test, Live included.

.PARAMETER Output
    Pester output verbosity. Default Normal.

.EXAMPLE
    pwsh -NoProfile -File .\tests\Invoke-Tests.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tests\Invoke-Tests.ps1 -Live
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Live')]
    [switch]$Live,

    [Parameter(ParameterSetName = 'All')]
    [switch]$All,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Normal'
)

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = $Output
$configuration.TestResult.Enabled = $false

$previous = $env:TERRAFORMGRAPH_LIVE
try {
    switch ($PSCmdlet.ParameterSetName) {
        'Live' {
            $env:TERRAFORMGRAPH_LIVE = '1'
            $configuration.Filter.Tag = 'Live'
        }
        'All' {
            $env:TERRAFORMGRAPH_LIVE = '1'
        }
        default {
            $env:TERRAFORMGRAPH_LIVE = $null
            $configuration.Filter.ExcludeTag = 'Live'
        }
    }
    $result = Invoke-Pester -Configuration $configuration
}
finally {
    $env:TERRAFORMGRAPH_LIVE = $previous
}
if ($result.FailedCount -or $result.FailedBlocksCount -or $result.FailedContainersCount) { exit 1 }
