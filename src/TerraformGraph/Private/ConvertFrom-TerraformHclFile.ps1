function ConvertFrom-TerraformHclFile {
    <#
    .SYNOPSIS
        Parses one Terraform .tf file through the native HCL DLL and emits its blocks.

    .DESCRIPTION
        ConvertFrom-TerraformHclFile is the single-file parser used by Get-TerraformAST.
        It resolves a literal path, calls ParseHCL on TerraformGraph.dll (HashiCorp HCL v2),
        converts the JSON payload to objects, and writes each top-level block from
        Body.Blocks to the pipeline.

        Prefer Get-TerraformAST for directories, recursion, and validation. This function
        assumes the path already exists.

    .PARAMETER LiteralPath
        Full or relative path to a single .tf file. Wildcards are not expanded.

    .EXAMPLE
        ConvertFrom-TerraformHclFile -LiteralPath .\infra\variables.tf

        Parse one file and emit its HCL blocks.

    .EXAMPLE
        Get-TerraformAST -FilePath .\infra\main.tf

        Public wrapper that validates the path, then calls this function.

    .OUTPUTS
        TerraformGraph.Block. Default view is Type, Name, Line, Column, File.
        TypeRange, LabelRanges, Body, and brace ranges remain on the object.

    .NOTES
        Not exported. Get-TerraformAST is the supported entry point.
        Parse failures are returned as an ErrorRecord instead of thrown. Any throw inside
        the module lands in the caller's -ErrorVariable even when caught, so the caller
        writes the record once and decides whether it terminates.

    .LINK
        Get-TerraformAST

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $LiteralPath
    )

    $absPath = (Resolve-Path -LiteralPath $LiteralPath -ErrorAction Stop).Path
    Write-Verbose "Parsing $absPath"

    $astJsonPtr = [TerraformGraph.Utf8Parser]::ParseHCL($absPath)
    if ($astJsonPtr -eq [IntPtr]::Zero) {
        return New-TerraformHclParseError -Message "Failed to parse HCL file: Null pointer returned ($absPath)" -Path $absPath
    }

    try {
        $astJson = [System.Runtime.InteropServices.Marshal]::PtrToStringUTF8($astJsonPtr)
    }
    finally {
        [TerraformGraph.Utf8Parser]::FreeString($astJsonPtr)
    }

    if (-not $astJson) {
        return New-TerraformHclParseError -Message "Failed to convert AST JSON to string ($absPath)" -Path $absPath
    }

    if ($astJson.StartsWith("Error ")) {
        return New-TerraformHclParseError -Message "$astJson ($absPath)" -Path $absPath
    }

    # System.Text.Json reader with no practical depth limit; ConvertFrom-Json caps nesting.
    $ast = [TerraformGraph.Json]::Deserialize($astJson, [int]::MaxValue, $false)

    $ast.Body.Blocks | ForEach-Object { ConvertTo-TerraformGraphBlock -Block $_ }
}
