$dllPath = Join-Path $PSScriptRoot "lib\TerraformGraph.dll"
if (-not (Test-Path $dllPath)) {
    throw "DLL not found: $dllPath"
}

$signature = @"
    [DllImport(@"$dllPath", EntryPoint = "ParseHCL", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr ParseHCL(string filePath);

    [DllImport(@"$dllPath", EntryPoint = "FreeString", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.Cdecl)]
    public static extern void FreeString(IntPtr str);
"@

$typeName = 'TerraformGraph.HCLParser'
$alreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object { try { $_.GetType($typeName, $false, $false) } catch { $null } } |
    Where-Object { $_ }

if (-not $alreadyLoaded) {
    Add-Type -MemberDefinition $signature -Name HCLParser -Namespace TerraformGraph
}

if (-not ('TerraformGraph.Json' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'TerraformGraph.Json.cs')
}

# Default view: Type, Name, Line, Column, File.
# Everything else is still on the object — use Format-List * or Select-Object *.
$blockTypeName = 'TerraformGraph.Block'
Update-TypeData -TypeName $blockTypeName -DefaultDisplayPropertySet Type, Name, Line, Column, File -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName Name -Value {
    if ($this.Labels) { $this.Labels -join '.' }
} -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName Line -Value {
    $this.TypeRange.Start.Line
} -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName Column -Value {
    $this.TypeRange.Start.Column
} -Force
Update-TypeData -TypeName $blockTypeName -MemberType ScriptProperty -MemberName File -Value {
    if ($this.TypeRange.Filename) {
        Split-Path -Path $this.TypeRange.Filename -Leaf
    }
} -Force

function ConvertTo-TerraformGraphBlock {
    param($Block)
    $Block.PSObject.TypeNames.Insert(0, 'TerraformGraph.Block')
    $Block
}

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
        Parse failures throw so a 7.4+ agent with ErrorAction Stop can correct them.

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

    $astJsonPtr = [TerraformGraph.HCLParser]::ParseHCL($absPath)
    if ($astJsonPtr -eq [IntPtr]::Zero) {
        throw "Failed to parse HCL file: Null pointer returned ($absPath)"
    }

    try {
        $astJson = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($astJsonPtr)
    }
    finally {
        [TerraformGraph.HCLParser]::FreeString($astJsonPtr)
    }

    if (-not $astJson) {
        throw "Failed to convert AST JSON to string ($absPath)"
    }

    if ($astJson.StartsWith("Error ")) {
        throw "$astJson ($absPath)"
    }

    # System.Text.Json reader with no practical depth limit; ConvertFrom-Json caps nesting.
    $ast = [TerraformGraph.Json]::Deserialize($astJson, [int]::MaxValue, $false)

    $ast.Body.Blocks | ForEach-Object { ConvertTo-TerraformGraphBlock -Block $_ }
}

function Get-TerraformAST {
    <#
    .SYNOPSIS
        Parses Terraform .tf files into an HCL abstract syntax tree.

    .DESCRIPTION
        Get-TerraformAST walks one file or a directory of Terraform configuration and
        returns the HCL blocks produced by HashiCorp HCL v2 (the language library
        Terraform uses). It is the AST layer of TerraformGraph; the module and provider
        relationship graph is built on top of these blocks (graph layer in progress).

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
        https://github.com/JerryBalmer1/TerraformGraph
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
            try {
                ConvertFrom-TerraformHclFile -LiteralPath $file.FullName
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}

function ConvertTo-TerraformJson {
    <#
    .SYNOPSIS
        Converts objects to indented JSON using System.Text.Json.

    .DESCRIPTION
        ConvertTo-TerraformJson is a ConvertTo-Json replacement for deep documents
        such as Terraform provider schemas. ConvertTo-Json stops at -Depth 100 and
        silently truncates anything deeper; this cmdlet serializes the whole graph
        and throws if it goes past -Depth or finds a circular reference.

        Output is indented with two spaces. Characters such as <, >, & and non-ASCII
        text are written as-is instead of \u escapes.

        Pipeline input is collected. One input object becomes one JSON value; more
        than one becomes a JSON array.

    .PARAMETER InputObject
        The object to convert. Accepts pipeline input.

    .PARAMETER Depth
        Maximum nesting depth of objects and arrays. Defaults to 1024.

    .PARAMETER Compress
        Write the JSON on one line with no indentation.

    .PARAMETER AsArray
        Always write a JSON array, even for a single input object.

    .EXAMPLE
        terraform providers schema -json | ConvertFrom-TerraformJson | ConvertTo-TerraformJson

        Pretty-print a provider schema too deep for ConvertTo-Json.

    .EXAMPLE
        Get-TerraformAST -Path .\infra | ConvertTo-TerraformJson | Set-Content .\infra.ast.json

        Save the parsed blocks as indented JSON.

    .OUTPUTS
        System.String

    .LINK
        ConvertFrom-TerraformJson
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [object]
        $InputObject,

        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $Depth = 1024,

        [switch]
        $Compress,

        [switch]
        $AsArray
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        $items.Add($InputObject)
    }

    end {
        if ($items.Count -eq 0 -and -not $AsArray) {
            return
        }

        $value = $items
        if ($items.Count -eq 1 -and -not $AsArray) {
            $value = $items[0]
        }

        try {
            [TerraformGraph.Json]::Serialize($value, $Depth, $Compress.IsPresent)
        }
        catch {
            $exception = $_.Exception.InnerException ?? $_.Exception
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new($exception, 'TerraformJsonSerializeFailed', 'InvalidData', $null)
            )
        }
    }
}

function ConvertFrom-TerraformJson {
    <#
    .SYNOPSIS
        Converts JSON to PowerShell objects using System.Text.Json.

    .DESCRIPTION
        ConvertFrom-TerraformJson is a ConvertFrom-Json replacement for deep documents
        such as `terraform providers schema -json`. Objects become PSCustomObjects (or
        ordered, case-sensitive dictionaries with -AsHashtable), arrays become object[],
        and numbers become int, long, BigInteger or double. Strings are left as strings;
        dates are not converted.

        Pipeline strings are joined with newlines before parsing, so Get-Content output
        works with or without -Raw. Comments and trailing commas are allowed.

    .PARAMETER InputObject
        JSON text. Accepts pipeline input.

    .PARAMETER Depth
        Maximum nesting depth allowed in the JSON. Defaults to 1024.

    .PARAMETER AsHashtable
        Return ordered dictionaries instead of PSCustomObjects. Needed when keys differ
        only by case, or a key is empty.

    .PARAMETER NoEnumerate
        Write a top-level JSON array as a single object instead of enumerating it.

    .EXAMPLE
        $schema = terraform providers schema -json | ConvertFrom-TerraformJson

        Load a provider schema that ConvertFrom-Json and ConvertTo-Json cannot handle.

    .EXAMPLE
        Get-Content .\infra.ast.json -Raw | ConvertFrom-TerraformJson -AsHashtable

        Read JSON into ordered dictionaries.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        System.Collections.Specialized.OrderedDictionary

    .LINK
        ConvertTo-TerraformJson
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]
        $InputObject,

        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $Depth = 1024,

        [switch]
        $AsHashtable,

        [switch]
        $NoEnumerate
    )

    begin {
        $builder = [System.Text.StringBuilder]::new()
    }

    process {
        [void]$builder.AppendLine($InputObject)
    }

    end {
        $json = $builder.ToString()
        if ([string]::IsNullOrWhiteSpace($json)) {
            return
        }

        try {
            $result = [TerraformGraph.Json]::Deserialize($json, $Depth, $AsHashtable.IsPresent)
        }
        catch {
            $exception = $_.Exception.InnerException ?? $_.Exception
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new($exception, 'TerraformJsonDeserializeFailed', 'InvalidData', $null)
            )
        }

        Write-Output -InputObject $result -NoEnumerate:$NoEnumerate
    }
}

function Get-TerraformProviderSchema {
    <#
    .SYNOPSIS
        Runs `terraform providers schema -json` and returns the result.

    .DESCRIPTION
        Get-TerraformProviderSchema wraps `terraform providers schema -json` for a
        Terraform working directory. The directory must already be initialized
        (`terraform init`) for any provider other than the built-in one.

        Provider schemas (AWS in particular) nest deeper than ConvertFrom-Json and
        ConvertTo-Json handle, so the output goes through ConvertFrom-TerraformJson and
        ConvertTo-TerraformJson.

        -OutputFormat OrderedHashtable (the default) returns nested ordered dictionaries
        all the way down. -OutputFormat Json returns indented JSON text.

    .PARAMETER Path
        Terraform working directory. Defaults to the current location.

    .PARAMETER OutputFormat
        OrderedHashtable (default) or Json.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Path .\infra
        $schema.provider_schemas['registry.terraform.io/hashicorp/aws'].resource_schemas['aws_s3_bucket']

        Look up one resource schema.

    .EXAMPLE
        Get-TerraformProviderSchema -Path .\infra -OutputFormat Json | Set-Content .\schema.json

        Save the schema as indented JSON.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
        System.String

    .LINK
        ConvertFrom-TerraformJson

    .LINK
        ConvertTo-TerraformJson
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary], [string])]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
                throw "Path '$_' is not an existing directory."
            }
            $true
        })]
        [string]
        $Path = './',

        [ValidateSet('OrderedHashtable', 'Json')]
        [string]
        $OutputFormat = 'OrderedHashtable'
    )

    $workingDirectory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath

    if (-not (Get-Command terraform -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "terraform is not on PATH."
    }

    Write-Verbose "terraform -chdir=$workingDirectory providers schema -json"

    # Schema descriptions contain non-ASCII text; read terraform's stdout as UTF-8.
    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $output = & terraform "-chdir=$workingDirectory" providers schema -json 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }

    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

    if ($exitCode -ne 0) {
        $message = (@($stderr) + @($stdout) | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "terraform providers schema failed with exit code $exitCode in '$workingDirectory'. Run terraform init first if providers are not installed.$([Environment]::NewLine)$message"
    }

    $schema = $stdout | ConvertFrom-TerraformJson -AsHashtable -ErrorAction Stop

    switch ($OutputFormat) {
        'OrderedHashtable' { $schema }
        'Json'             { $schema | ConvertTo-TerraformJson -ErrorAction Stop }
    }
}
