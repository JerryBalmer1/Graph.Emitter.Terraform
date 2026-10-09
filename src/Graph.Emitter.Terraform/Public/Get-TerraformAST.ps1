function Get-TerraformAST {
    <#
    .SYNOPSIS
        Parses Terraform .tf files into an HCL abstract syntax tree.

    .DESCRIPTION
        Get-TerraformAST walks one file or a directory of Terraform configuration and
        returns the HCL blocks produced by HashiCorp HCL v2 (the language library
        Terraform uses). It is the AST layer of Graph.Emitter.Terraform; the module and provider
        relationship graph is built on top of these blocks.

        Use -FilePath for a single .tf file. Use -Path for a directory. Add -Recurse
        to include .tf files in subdirectories.

        Default display is Type, Name, Line, Column, and File. Source ranges and Body
        stay on the object; use Format-List * when you need the full tree.

    .PARAMETER Path
        Directory that contains Terraform .tf files.

    .PARAMETER Recurse
        When -Path is used, include .tf files in child directories.

    .PARAMETER FilePath
        A single Terraform .tf file.

    .EXAMPLE
        Get-TerraformAST -Path .\infra

        Parse every .tf file in the infra directory (not recursive).

    .EXAMPLE
        Get-TerraformAST -Path .\infra -Recurse

        Parse every .tf file under infra, including nested modules.

    .EXAMPLE
        Get-TerraformAST -FilePath .\infra\main.tf

        Parse one Terraform file.

    .EXAMPLE
        Get-ChildItem .\infra -Filter *.tf | Get-TerraformAST

        Pipeline input binds to -FilePath via the FullName alias.

    .OUTPUTS
        TerraformGraph.Block

    .LINK
        https://github.com/JerryBalmer1/Graph.Emitter.Terraform
    #>
    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    param(
        [Parameter(
            Mandatory,
            ParameterSetName = 'Directory',
            Position = 0,
            HelpMessage = 'Directory that contains .tf files.'
        )]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
                throw "Path '$_' is not an existing directory."
            }
            $true
        })]
        [string]
        $Path,

        [Parameter(ParameterSetName = 'Directory')]
        [switch]
        $Recurse,

        [Parameter(
            Mandatory,
            ParameterSetName = 'File',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            HelpMessage = 'Path to a single .tf file.'
        )]
        [Alias('FullName')]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
                throw "FilePath '$_' is not an existing file."
            }
            if (-not ([System.IO.FileInfo]$_).Extension.Equals('.tf', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "FilePath '$_' must have a .tf extension."
            }
            $true
        })]
        [string]
        $FilePath
    )

    begin {
        Write-Verbose "[ $($MyInvocation.InvocationName) ] $($PSCmdlet.ParameterSetName)"
        Assert-TerraformGraphParser
    }

    process {
        $files = switch ($PSCmdlet.ParameterSetName) {
            'File' {
                Get-Item -LiteralPath $FilePath
            }
            'Directory' {
                $gci = @{
                    LiteralPath = $Path
                    Filter      = '*.tf'
                    File        = $true
                    ErrorAction = 'Stop'
                }
                if ($Recurse) {
                    $gci.Recurse = $true
                }
                Get-ChildItem @gci
            }
        }

        if (-not $files) {
            Write-Error "No .tf files found."
            return
        }

        foreach ($file in $files) {
            foreach ($item in ConvertFrom-TerraformHclFile -LiteralPath $file.FullName) {
                if ($item -is [System.Management.Automation.ErrorRecord]) {
                    $PSCmdlet.WriteError($item)
                }
                else {
                    $item
                }
            }
        }
    }
}
