<#
.SYNOPSIS
    Assembles the publishable TerraformGraph module tree, or lists what it would contain.

.DESCRIPTION
    The one definition of what ships. Invoke-Build AssembleModule calls it to build
    dist/module/TerraformGraph, and Pester compares its -ListOnly output with the psd1
    FileList, so the manifest, the tree and this script cannot drift apart.

    The tree holds the manifest, the psm1, the format file, LICENSE and NOTICE (from the repo
    root), lib/TerraformGraph.dll (Invoke-Build BuildDLL) and lib/TerraformGraph.Json.dll
    (Invoke-Build BuildJson), and every file under data/, classifiers/ and skills/. Nothing
    else: no lib/*.old, no C header, no TerraformGraph.Json.cs, no tests or repo docs.

.PARAMETER RepoRoot
    Repository root. Default: the parent of this script's folder.

.PARAMETER OutputPath
    Module folder to create, such as dist/module/TerraformGraph. Deleted first when it exists.

.PARAMETER ListOnly
    Return the relative paths the tree would hold (sorted, '/' separators) and copy nothing.
    Works on a clean clone: the two DLLs are build outputs and need not exist.

.EXAMPLE
    ./tools/Copy-TerraformGraphModule.ps1 -ListOnly

.EXAMPLE
    ./tools/Copy-TerraformGraphModule.ps1 -OutputPath ./dist/module/TerraformGraph
#>
[CmdletBinding(DefaultParameterSetName = 'Copy')]
param(
    [string]
    $RepoRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter(Mandatory, ParameterSetName = 'Copy')]
    [string]
    $OutputPath,

    [Parameter(Mandatory, ParameterSetName = 'List')]
    [switch]
    $ListOnly
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $RepoRoot 'src' 'TerraformGraph'

# Relative destination path -> absolute source path.
$plan = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
foreach ($name in 'TerraformGraph.psd1', 'TerraformGraph.psm1', 'TerraformGraph.Format.ps1xml') {
    $plan[$name] = Join-Path $source $name
}
foreach ($name in 'LICENSE', 'NOTICE') {
    $plan[$name] = Join-Path $RepoRoot $name
}
$plan['lib/TerraformGraph.dll'] = Join-Path $source 'lib' 'TerraformGraph.dll'
$plan['lib/TerraformGraph.Json.dll'] = Join-Path $source 'lib' 'TerraformGraph.Json.dll'
foreach ($folder in 'data', 'classifiers', 'skills') {
    $root = Join-Path $source $folder
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse) {
        $relative = [System.IO.Path]::GetRelativePath($source, $file.FullName).Replace('\', '/')
        $plan[$relative] = $file.FullName
    }
}

if ($ListOnly) {
    return [string[]]@($plan.Keys)
}

$missing = @($plan.GetEnumerator() | Where-Object { -not (Test-Path -LiteralPath $_.Value -PathType Leaf) })
if ($missing.Count) {
    $fixes = foreach ($item in $missing) {
        switch ($item.Key) {
            'lib/TerraformGraph.dll' { "$($item.Value) is missing: run Invoke-Build BuildDLL (needs Docker)." }
            'lib/TerraformGraph.Json.dll' { "$($item.Value) is missing: run Invoke-Build BuildJson (needs a .NET 8 SDK)." }
            default { "$($item.Value) is missing." }
        }
    }
    throw "Cannot assemble the module:`n  $($fixes -join "`n  ")"
}

$destination = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
foreach ($item in $plan.GetEnumerator()) {
    $target = Join-Path $destination $item.Key
    $null = New-Item -ItemType Directory -Path (Split-Path -Path $target -Parent) -Force
    Copy-Item -LiteralPath $item.Value -Destination $target
}

$written = @(Get-ChildItem -LiteralPath $destination -File -Recurse | ForEach-Object { [System.IO.Path]::GetRelativePath($destination, $_.FullName).Replace('\', '/') } | Sort-Object -Culture '')
$extra = @($written | Where-Object { -not $plan.ContainsKey($_) })
if ($extra.Count) { throw "The assembled tree holds files outside the plan: $($extra -join ', ')" }
[string[]]@($plan.Keys)
