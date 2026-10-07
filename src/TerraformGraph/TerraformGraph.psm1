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

# Module graph views. Every property stays on the object; these only pick the table columns.
Update-TypeData -TypeName 'TerraformGraph.ModuleNode' -DefaultDisplayPropertySet ModuleAddress, SourceKind, Depth, Resolved, Dir -Force

$moduleGraphTypeName = 'TerraformGraph.ModuleGraph'
Update-TypeData -TypeName $moduleGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $moduleGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $moduleGraphTypeName -MemberType ScriptProperty -MemberName UnresolvedCount -Value {
    @($this.Unresolved).Count
} -Force
Update-TypeData -TypeName $moduleGraphTypeName -DefaultDisplayPropertySet Root, GroupBy, NodeCount, EdgeCount, UnresolvedCount -Force

# Schema graph views.
Update-TypeData -TypeName 'TerraformGraph.SchemaNode' -DefaultDisplayPropertySet Kind, Path, Type, Required, Depth -Force

$schemaGraphTypeName = 'TerraformGraph.SchemaGraph'
Update-TypeData -TypeName $schemaGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $schemaGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $schemaGraphTypeName -MemberType ScriptProperty -MemberName Summary -Value {
    # Kinds in a fixed order; only kinds present in the graph.
    $counts = @{}
    foreach ($node in $this.Nodes) { $counts[$node.Kind] = 1 + [int]$counts[$node.Kind] }
    $summary = [ordered]@{}
    foreach ($kind in 'Provider', 'Resource', 'DataSource', 'Function', 'Block', 'Attribute') {
        if ($counts.ContainsKey($kind)) { $summary[$kind] = $counts[$kind] }
    }
    $summary
} -Force
Update-TypeData -TypeName $schemaGraphTypeName -DefaultDisplayPropertySet Providers, NodeCount, EdgeCount -Force

# Variable graph views.
Update-TypeData -TypeName 'TerraformGraph.VariableNode' -DefaultDisplayPropertySet Kind, Module, Name, Binding, Literal -Force
Update-TypeData -TypeName 'TerraformGraph.VariableTraceNode' -DefaultDisplayPropertySet Distance, Kind, Module, Name, Binding, Literal -Force

$variableGraphTypeName = 'TerraformGraph.VariableGraph'
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName UnresolvedCount -Value {
    @($this.Unresolved).Count
} -Force
Update-TypeData -TypeName $variableGraphTypeName -MemberType ScriptProperty -MemberName Summary -Value {
    # Kinds in a fixed order; only kinds present in the graph.
    $counts = @{}
    foreach ($node in $this.Nodes) { $counts[$node.Kind] = 1 + [int]$counts[$node.Kind] }
    $summary = [ordered]@{}
    foreach ($kind in 'Variable', 'Local', 'Output') {
        if ($counts.ContainsKey($kind)) { $summary[$kind] = $counts[$kind] }
    }
    $summary
} -Force
Update-TypeData -TypeName $variableGraphTypeName -DefaultDisplayPropertySet Root, NodeCount, EdgeCount, UnresolvedCount -Force

# Resource graph views.
Update-TypeData -TypeName 'TerraformGraph.ResourceNode' -DefaultDisplayPropertySet Kind, ResourceAddress, ProviderAddress, SchemaMatched, Reason -Force

$resourceGraphTypeName = 'TerraformGraph.ResourceGraph'
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName NodeCount -Value {
    @($this.Nodes).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName EdgeCount -Value {
    @($this.Edges).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName MatchedCount -Value {
    @($this.Nodes | Where-Object SchemaMatched).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName UnmatchedCount -Value {
    @($this.Nodes | Where-Object { -not $_.SchemaMatched }).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -MemberType ScriptProperty -MemberName Findings -Value {
    @($this.Nodes | Where-Object { @($_.UnknownAttributes).Count -or @($_.UnknownBlocks).Count -or @($_.MissingRequired).Count }).Count
} -Force
Update-TypeData -TypeName $resourceGraphTypeName -DefaultDisplayPropertySet Root, NodeCount, MatchedCount, UnmatchedCount, Findings -Force

function ConvertTo-TerraformGraphBlock {
    param($Block)
    $Block.PSObject.TypeNames.Insert(0, 'TerraformGraph.Block')
    $Block
}

function New-TerraformHclParseError {
    param([string]$Message, [string]$Path)
    [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($Message),
        'HclParseError',
        [System.Management.Automation.ErrorCategory]::ParserError,
        $Path)
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

    $astJsonPtr = [TerraformGraph.HCLParser]::ParseHCL($absPath)
    if ($astJsonPtr -eq [IntPtr]::Zero) {
        return New-TerraformHclParseError -Message "Failed to parse HCL file: Null pointer returned ($absPath)" -Path $absPath
    }

    try {
        $astJson = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($astJsonPtr)
    }
    finally {
        [TerraformGraph.HCLParser]::FreeString($astJsonPtr)
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

function Get-TerraformAST {
    <#
    .SYNOPSIS
        Parses Terraform .tf files into an HCL abstract syntax tree.

    .DESCRIPTION
        Get-TerraformAST walks one file or a directory of Terraform configuration and
        returns the HCL blocks produced by HashiCorp HCL v2 (the language library
        Terraform uses). It is the AST layer of TerraformGraph; the module and provider
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

function Invoke-TerraformCli {
    # Not exported. Runs terraform with stdout read as UTF-8 (schema descriptions
    # contain non-ASCII text) and splits stdout from stderr.
    param(
        [Parameter(Mandatory)]
        [string[]]
        $ArgumentList
    )

    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $output = & terraform @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Stdout   = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        Stderr   = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
}

function Read-TerraformProviderSchemaFromDirectory {
    # Not exported. The Directory-set body of Get-TerraformProviderSchema; the
    # Provider set calls it against its own working directory.
    param(
        [Parameter(Mandatory)]
        [string]
        $WorkingDirectory,

        [string]
        $OutputFormat = 'OrderedHashtable'
    )

    Write-Verbose "terraform -chdir=$WorkingDirectory providers schema -json"

    $result = Invoke-TerraformCli -ArgumentList "-chdir=$WorkingDirectory", 'providers', 'schema', '-json'

    if ($result.ExitCode -ne 0) {
        $message = (@($result.Stderr) + @($result.Stdout) | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "terraform providers schema failed with exit code $($result.ExitCode) in '$WorkingDirectory'. Run terraform init first if providers are not installed.$([Environment]::NewLine)$message"
    }

    $schema = $result.Stdout | ConvertFrom-TerraformJson -AsHashtable -ErrorAction Stop

    switch ($OutputFormat) {
        'OrderedHashtable' { $schema }
        'Json'             { $schema | ConvertTo-TerraformJson -ErrorAction Stop }
    }
}

function ConvertTo-TerraformProviderAddress {
    # Not exported. Normalizes 'name', 'namespace/name' or 'host/namespace/name' to the
    # address terraform keys provider_schemas and the lock file on. A bare name means the
    # hashicorp namespace; a missing host means registry.terraform.io. Source is what
    # required_providers takes: the host is dropped only for registry.terraform.io.
    param(
        [Parameter(Mandatory)]
        [string]
        $Provider
    )

    $trimmed = $Provider.Trim()
    if ($trimmed -notmatch '^([\w.-]+/)?[\w-]+/[\w-]+$|^[\w-]+$') {
        throw "Provider '$Provider' is not a provider address. Use 'name', 'namespace/name', or 'host/namespace/name'."
    }

    $segments = $trimmed.Split('/')
    switch ($segments.Count) {
        1 { $hostName = 'registry.terraform.io'; $namespace = 'hashicorp';   $name = $segments[0] }
        2 { $hostName = 'registry.terraform.io'; $namespace = $segments[0]; $name = $segments[1] }
        3 { $hostName = $segments[0];            $namespace = $segments[1]; $name = $segments[2] }
    }
    $address = "$hostName/$namespace/$name"

    [pscustomobject]@{
        Host      = $hostName
        Namespace = $namespace
        Name      = $name
        Address   = $address
        Source    = if ($hostName -eq 'registry.terraform.io') { "$namespace/$name" } else { $address }
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

        With -Provider it fetches one provider's schema on demand instead: it writes a
        throwaway main.tf that requires only that provider, runs `terraform init` there,
        and reads the schema. The working directory is kept by default so repeat calls
        skip the download.

        Provider schemas (AWS in particular) nest deeper than ConvertFrom-Json and
        ConvertTo-Json handle, so the output goes through ConvertFrom-TerraformJson and
        ConvertTo-TerraformJson.

        -OutputFormat OrderedHashtable (the default) returns nested ordered dictionaries
        all the way down. -OutputFormat Json returns indented JSON text.

    .PARAMETER Path
        Terraform working directory. Defaults to the current location.

    .PARAMETER Provider
        Provider to fetch: 'aws', 'hashicorp/aws', or 'registry.terraform.io/hashicorp/aws'.
        A bare name means the hashicorp namespace.
        The source written to required_providers drops the host only when it is
        registry.terraform.io; any other host is kept, as in 'example.com/acme/thing'.
        A value with a wildcard, such as 'aws*' or 'hashicorp/google*', is resolved against
        the provider registry cache (see Get-TerraformRegistryProvider) before anything
        runs; it must match exactly one provider, or the command stops with an error that
        lists every match. A value without a wildcard needs no cache.

    .PARAMETER NoBundledData
        When -Provider has a wildcard, ignore the registry cache bundled with the module and
        read only the user cache.

    .PARAMETER Version
        Version constraint written verbatim into required_providers, such as '~> 5.0',
        '= 5.60.0', or '>= 4'. Omit it to let terraform init pick the latest release.

    .PARAMETER WorkingDirectory
        Directory for the throwaway configuration. Created if missing. Defaults to
        $env:TEMP\TerraformGraph\providers\<namespace>-<name>-<version> for
        registry.terraform.io, and $env:TEMP\TerraformGraph\providers\<host>-<namespace>-<name>-<version>
        for any other host, with '.' and ':' in <host> replaced by '_'. <version> is the
        constraint with every character other than letters, digits, and dots replaced
        by '_', or 'latest' when -Version is omitted.

    .PARAMETER Cleanup
        Remove -WorkingDirectory after reading the schema, even when a step fails.
        Without it the directory is kept so the next call skips terraform init.

    .PARAMETER Force
        Run terraform init even when .terraform.lock.hcl already exists. The lock file
        is deleted first so terraform selects versions again, which picks up a newer
        release for an omitted or ranged -Version.

    .PARAMETER SaveToCache
        After reading the schema, also write it to the local schema cache
        ($env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz) at the
        version terraform selected, read from the lock file. ConvertTo-TerraformSchemaGraph
        -Provider and ConvertTo-TerraformResourceGraph -Provider or -AutoSchema read that
        cache. The schema is still returned as usual. If the selected version cannot be
        determined, the command stops with an error and writes nothing.

    .PARAMETER OutputFormat
        OrderedHashtable (default) or Json.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Path .\infra
        $schema.provider_schemas['registry.terraform.io/hashicorp/aws'].resource_schemas['aws_s3_bucket']

        Look up one resource schema.

    .EXAMPLE
        Get-TerraformProviderSchema -Path .\infra -OutputFormat Json | Set-Content .\schema.json

        Save the schema as indented JSON.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Provider null -Cleanup
        $schema.provider_schemas['registry.terraform.io/hashicorp/null'].resource_schemas.Keys

        Fetch the latest hashicorp/null schema without an existing configuration, then
        remove the working directory.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Provider hashicorp/aws -Version '= 5.60.0' -Verbose

        Fetch a pinned AWS provider schema. The working directory is kept, so running
        the same command again skips terraform init and only reads the schema.

    .EXAMPLE
        $null = Get-TerraformProviderSchema -Provider hashicorp/null -Version '= 3.2.3' -SaveToCache -Cleanup
        ConvertTo-TerraformSchemaGraph -Provider null

        Harvest one provider version into the local schema cache, then build its schema
        graph from the cache without running terraform again.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
        System.String

    .NOTES
        The Provider set needs terraform on PATH and network access to the provider
        registry whenever it runs terraform init.

    .LINK
        ConvertFrom-TerraformJson

    .LINK
        ConvertTo-TerraformJson
    #>
    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    [OutputType([System.Collections.Specialized.OrderedDictionary], [string])]
    param(
        [Parameter(ParameterSetName = 'Directory', Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
                throw "Path '$_' is not an existing directory."
            }
            $true
        })]
        [string]
        $Path = './',

        [Parameter(ParameterSetName = 'Provider', Mandatory)]
        [ValidateScript({
            # A wildcard is resolved against the registry cache in the body.
            if (-not [WildcardPattern]::ContainsWildcardCharacters($_)) {
                $null = ConvertTo-TerraformProviderAddress -Provider $_
            }
            $true
        })]
        [string]
        $Provider,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $Version,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $WorkingDirectory,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $Cleanup,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $Force,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $NoBundledData,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $SaveToCache,

        [ValidateSet('OrderedHashtable', 'Json')]
        [string]
        $OutputFormat = 'OrderedHashtable'
    )

    # Before anything else, so an ambiguous or unknown pattern fails without running terraform.
    if ($PSCmdlet.ParameterSetName -eq 'Provider' -and [WildcardPattern]::ContainsWildcardCharacters($Provider)) {
        try {
            $resolved = Resolve-TerraformRegistryProvider -Name $Provider -NoBundledData:$NoBundledData
        }
        catch {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new($_.Exception.Message),
                'RegistryProviderNotResolved',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $Provider))
        }
        Write-Verbose "Provider '$Provider' resolved to $($resolved.ProviderAddress) from the registry cache"
        $Provider = $resolved.ProviderAddress
    }

    if (-not (Get-Command terraform -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "terraform is not on PATH."
    }

    if ($PSCmdlet.ParameterSetName -eq 'Directory') {
        $directory = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        return Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat $OutputFormat
    }

    # The lock file keys on host/namespace/name; required_providers drops the host only
    # when it is the public registry. Both comparisons below are case-insensitive, as
    # terraform lowercases the address it writes to the lock file.
    $providerAddress = ConvertTo-TerraformProviderAddress -Provider $Provider
    $hostName  = $providerAddress.Host
    $namespace = $providerAddress.Namespace
    $name      = $providerAddress.Name
    $address   = $providerAddress.Address
    $source    = $providerAddress.Source

    if (-not $WorkingDirectory) {
        $slug = if ($Version) { $Version -replace '[^A-Za-z0-9.]', '_' } else { 'latest' }
        $tempRoot = $env:TEMP ?? [System.IO.Path]::GetTempPath()
        # Public-registry directories keep the unprefixed name so existing ones still work.
        $prefix = if ($hostName -eq 'registry.terraform.io') { '' } else { ($hostName -replace '[.:]', '_') + '-' }
        $WorkingDirectory = Join-Path $tempRoot "TerraformGraph\providers\$prefix$namespace-$name-$slug"
    }

    try {
        $directory = (New-Item -ItemType Directory -Path $WorkingDirectory -Force -ErrorAction Stop).FullName

        $requirement = if ($Version) {
            "      source  = `"$source`"", "      version = `"$Version`""
        }
        else {
            "      source = `"$source`""
        }
        $mainTf = @(
            'terraform {'
            '  required_providers {'
            "    $name = {"
            $requirement
            '    }'
            '  }'
            '}'
        )
        Set-Content -LiteralPath (Join-Path $directory 'main.tf') -Value $mainTf -ErrorAction Stop

        $lockFile = Join-Path $directory '.terraform.lock.hcl'
        if ($Force -and (Test-Path -LiteralPath $lockFile)) {
            # terraform init leaves an up-to-date lock file alone; remove it so versions are selected again.
            Remove-Item -LiteralPath $lockFile -Force -ErrorAction Stop
        }

        if (Test-Path -LiteralPath $lockFile) {
            Write-Verbose "Skipping terraform init; $lockFile exists. Use -Force to run it again."
        }
        else {
            Write-Verbose "terraform -chdir=$directory init -backend=false -input=false -no-color"
            $init = Invoke-TerraformCli -ArgumentList "-chdir=$directory", 'init', '-backend=false', '-input=false', '-no-color'
            if ($init.ExitCode -ne 0) {
                $message = (@($init.Stderr) | ForEach-Object { "$_" }) -join [Environment]::NewLine
                throw "terraform init failed with exit code $($init.ExitCode) for provider '$namespace/$name' in '$directory'.$([Environment]::NewLine)$message"
            }
        }

        $resolvedVersion = $null
        if (Test-Path -LiteralPath $lockFile) {
            $inProvider = $false
            foreach ($line in Get-Content -LiteralPath $lockFile) {
                if ($line -match '^\s*provider\s+"([^"]+)"') {
                    $inProvider = $Matches[1] -eq $address
                }
                elseif ($inProvider -and $line -match '^\s*version\s*=\s*"([^"]+)"') {
                    $resolvedVersion = $Matches[1]
                    break
                }
            }
        }
        if (-not $resolvedVersion -and $SaveToCache) {
            # No lock file entry: ask terraform which version this directory selected.
            $versionResult = Invoke-TerraformCli -ArgumentList "-chdir=$directory", 'version', '-json'
            if ($versionResult.ExitCode -eq 0) {
                $selections = ($versionResult.Stdout | ConvertFrom-TerraformJson -AsHashtable -ErrorAction SilentlyContinue).provider_selections
                if ($selections) {
                    $key = @($selections.Keys) | Where-Object { $_ -eq $address } | Select-Object -First 1
                    if ($key) { $resolvedVersion = [string]$selections[$key] }
                }
            }
        }
        Write-Verbose "Provider $address $($resolvedVersion ?? '(version not in lock file)') in $directory"

        if (-not $SaveToCache) {
            return Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat $OutputFormat
        }

        if (-not $resolvedVersion) {
            throw "Could not determine the selected version of $address in '$directory'; the schema was not saved to the cache."
        }
        $schema = Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat OrderedHashtable
        $cachePath = Write-TerraformSchemaCache -Provider $address -Version $resolvedVersion -Document $schema
        Write-Verbose "Saved $address $resolvedVersion to $cachePath"
        switch ($OutputFormat) {
            'OrderedHashtable' { $schema }
            'Json'             { $schema | ConvertTo-TerraformJson -ErrorAction Stop }
        }
    }
    finally {
        if ($Cleanup -and (Test-Path -LiteralPath $WorkingDirectory)) {
            Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force
        }
    }
}

function Get-TerraformModuleSourceKind {
    # Not exported. Classifies a module source string by prefix, the way Terraform's
    # module installer does. Local is checked first so ./ and ../ never look like Registry.
    param(
        [AllowNull()]
        [string]
        $Source
    )

    if ([string]::IsNullOrEmpty($Source)) { return 'Unknown' }

    switch -Regex ($Source) {
        '^\.\.?/'                                { return 'Local' }
        '^(git::|github\.com/|bitbucket\.org/)'  { return 'Git' }
        '^https?://'                             { return 'Http' }
        '^s3::'                                  { return 'S3' }
        '^gcs::'                                 { return 'Gcs' }
        # [host/]namespace/name/provider, optional //subdir.
        '^([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?/)?[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+(//.*)?$' { return 'Registry' }
    }

    'Unknown'
}

function Get-TerraformModuleGraph {
    <#
    .SYNOPSIS
        Builds a graph of module calls for a Terraform root module.

    .DESCRIPTION
        Get-TerraformModuleGraph parses the root module directory with Get-TerraformAST
        (one directory, never its subtree), reads the source of every module block and
        resolves each call to a directory. Each call becomes a TerraformGraph.ModuleNode
        and an edge from its parent.

        Local sources (./ or ../) resolve against the calling module's directory.
        Registry, git, http, s3 and gcs sources resolve through
        .terraform/modules/modules.json in the root module. terraform init is never run.

        Without -Recurse only the root's direct calls are returned; their directories are
        resolved but not parsed. With -Recurse every resolved child is parsed and its own
        module calls are followed. Every call is its own node and is walked in full, even
        when another call already reached the same directory, because Keys and arguments
        differ per call.

        Calls that cannot be resolved stay in the graph with Resolved $false and a Reason:
        NonLiteralSource, LocalPathMissing or NotInitialized. They are also listed in
        Unresolved. A call whose Dir is already one of its own ancestors (root -> ... ->
        parent) keeps Resolved $true and its Dir, gets Reason Cycle and Blocks $null, and
        is not followed.

        Every node keeps Block, the module block from its parent's AST, so module
        arguments are available for later variable tracing.

    .PARAMETER Path
        Root module directory. Defaults to the current location.

    .PARAMETER Recurse
        Follow module calls beyond the root's direct children.

    .PARAMETER GroupBy
        Call (default) or Source. Sets each node's Id, and so the From and To of each
        edge: ModuleAddress for Call, the source string for Source. The root's Id
        is always 'root'. Every other property is populated either way.

    .EXAMPLE
        Get-TerraformModuleGraph -Path .\infra

        Root module and its direct module calls, without parsing the children.

    .EXAMPLE
        (Get-TerraformModuleGraph -Path .\infra -Recurse).Nodes

        Every module call in the tree, parsed, with Depth and ParentKey.

    .EXAMPLE
        (Get-TerraformModuleGraph -Path .\infra -Recurse -GroupBy Source).Edges

        Edges keyed by source string, so calls to the same module share an Id.

    .OUTPUTS
        TerraformGraph.ModuleGraph. Default view is Root, GroupBy, NodeCount, EdgeCount,
        UnresolvedCount. Nodes are TerraformGraph.ModuleNode, edges TerraformGraph.ModuleEdge.

    .NOTES
        .terraform/modules/modules.json is read at most once, and only when the first
        non-local source is found. A configuration whose sources are all local never
        touches it and needs no terraform init. Non-local calls are looked up by Key
        (parent Key + '.' + label); if the file or the Key is missing the call is
        NotInitialized.

    .LINK
        Get-TerraformAST

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
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

        [switch]
        $Recurse,

        [ValidateSet('Call', 'Source')]
        [string]
        $GroupBy = 'Call'
    )

    $rootDir = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $modulesJsonPath = Join-Path $rootDir '.terraform' 'modules' 'modules.json'

    $nodes = [System.Collections.Generic.List[object]]::new()
    $edges = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()

    # Dirs on the path root -> ... -> node, keyed by node Key. A call is only refused
    # as a cycle when its Dir is already on its own chain, so a module called from two
    # places is walked once per call.
    $chains = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)

    # modules.json entries keyed by module Key. Loaded on the first non-local source.
    $manifest = $null

    $root = [pscustomobject]@{
        PSTypeName    = 'TerraformGraph.ModuleNode'
        Key           = ''
        ModuleAddress = 'root'
        Name          = 'root'
        Source        = $null
        SourceKind    = 'Root'
        Dir           = $rootDir
        Resolved      = $true
        Reason        = $null
        ParentKey     = $null
        Depth         = 0
        Id            = 'root'
        Block         = $null
        Blocks        = @(Get-TerraformAST -Path $rootDir)
    }
    $nodes.Add($root)
    $chains[''] = @($rootDir)
    $queue.Enqueue($root)

    while ($queue.Count -gt 0) {
        $parent = $queue.Dequeue()
        $parentChain = $chains[$parent.Key]

        foreach ($block in @($parent.Blocks | Where-Object Type -eq 'module')) {
            $label         = [string]$block.Labels[0]
            $key           = if ($parent.Key) { "$($parent.Key).$label" } else { $label }
            $moduleAddress = 'module.' + $key.Replace('.', '.module.')
            $source        = $null
            $dir           = $null
            $reason        = $null

            $expr = $block.Body.Attributes.source.Expr
            if ($expr -and $expr.IsLiteral) {
                $source = [string]$expr.Value
            }
            else {
                $reason = 'NonLiteralSource'
            }

            $sourceKind = Get-TerraformModuleSourceKind -Source $source

            if (-not $reason) {
                if ($sourceKind -eq 'Local') {
                    $candidate = Join-Path $parent.Dir $source
                    if (Test-Path -LiteralPath $candidate -PathType Container) {
                        $dir = (Resolve-Path -LiteralPath $candidate).ProviderPath
                    }
                    else {
                        $reason = 'LocalPathMissing'
                    }
                }
                else {
                    if ($null -eq $manifest) {
                        $manifest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
                        if (Test-Path -LiteralPath $modulesJsonPath -PathType Leaf) {
                            Write-Verbose "Reading $modulesJsonPath"
                            $installed = Get-Content -LiteralPath $modulesJsonPath -Raw | ConvertFrom-TerraformJson -ErrorAction Stop
                            foreach ($entry in @($installed.Modules)) {
                                $manifest[[string]$entry.Key] = $entry
                            }
                        }
                    }

                    $entry = $null
                    $candidate = $null
                    if ($manifest.TryGetValue($key, [ref]$entry) -and $entry.Dir) {
                        $candidate = Join-Path $rootDir $entry.Dir
                    }
                    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
                        $dir = (Resolve-Path -LiteralPath $candidate).ProviderPath
                    }
                    else {
                        $reason = 'NotInitialized'
                    }
                }
            }

            # Parse only with -Recurse, and never a Dir already on this call's own chain.
            $blocks = $null
            if ($dir) {
                if ($parentChain -contains $dir) {
                    $reason = 'Cycle'
                }
                elseif ($Recurse) {
                    Write-Verbose "Parsing $moduleAddress in $dir"
                    $blocks = @(Get-TerraformAST -Path $dir)
                }
            }

            $id = $moduleAddress
            if ($GroupBy -eq 'Source' -and $null -ne $source) {
                $id = $source
            }

            $node = [pscustomobject]@{
                PSTypeName    = 'TerraformGraph.ModuleNode'
                Key           = $key
                ModuleAddress = $moduleAddress
                Name          = $label
                Source        = $source
                SourceKind    = $sourceKind
                Dir           = $dir
                Resolved      = $null -ne $dir
                Reason        = $reason
                ParentKey     = if ($parent.Key) { $parent.Key } else { $null }
                Depth         = $key.Split('.').Count
                Id            = $id
                Block         = $block
                Blocks        = $blocks
            }
            $nodes.Add($node)

            $edges.Add([pscustomobject]@{
                PSTypeName = 'TerraformGraph.ModuleEdge'
                From       = $parent.Id
                To         = $id
                Call       = $moduleAddress
                Label      = $label
                Line       = $block.Line
            })

            if ($blocks) {
                $chains[$key] = @($parentChain) + $dir
                $queue.Enqueue($node)
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'TerraformGraph.ModuleGraph'
        Root       = $rootDir
        GroupBy    = $GroupBy
        Recurse    = $Recurse.IsPresent
        Nodes      = $nodes.ToArray()
        Edges      = $edges.ToArray()
        Unresolved = @($nodes | Where-Object { -not $_.Resolved })
    }
}

function Get-TerraformSchemaMember {
    # Not exported. Reads one key from a schema fragment, whether it is a dictionary
    # (Get-TerraformProviderSchema, ConvertFrom-TerraformJson -AsHashtable) or a
    # PSCustomObject (ConvertFrom-TerraformJson). A missing key returns $null. The
    # leading comma keeps array values (cty types) from being unrolled.
    param(
        [AllowNull()]
        $InputObject,

        [string]
        $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return , $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return , $property.Value }
    $null
}

function Get-TerraformSchemaKeys {
    # Not exported. Keys of a schema map in document order, or sorted ordinally with -Sort
    # so the order never depends on culture.
    param(
        [AllowNull()]
        $InputObject,

        [switch]
        $Sort
    )

    if ($null -eq $InputObject) { return }
    [string[]]$keys = if ($InputObject -is [System.Collections.IDictionary]) {
        @($InputObject.Keys)
    }
    else {
        @($InputObject.PSObject.Properties.Name)
    }
    if ($Sort) { [Array]::Sort($keys, [System.StringComparer]::Ordinal) }
    $keys
}

function ConvertTo-TerraformTypeString {
    # Not exported. Renders cty type JSON as Terraform type syntax:
    # ["set",["object",{"a":"string"},["a"]]] -> set(object({ a = optional(string) })).
    # "dynamic" renders as any. An unknown shape comes back as compact JSON.
    param(
        [AllowNull()]
        $Type
    )

    if ($null -eq $Type) { return $null }
    if ($Type -is [string]) {
        if ($Type -eq 'dynamic') { return 'any' }
        return $Type
    }

    $kind = [string]$Type[0]
    switch ($kind) {
        { $_ -in 'list', 'set', 'map' } {
            return "$kind($(ConvertTo-TerraformTypeString -Type $Type[1]))"
        }
        'tuple' {
            $elements = foreach ($element in @($Type[1])) { ConvertTo-TerraformTypeString -Type $element }
            return "tuple([$(@($elements) -join ', ')])"
        }
        'object' {
            $optional = if ($Type.Count -gt 2) { @($Type[2]) } else { @() }
            $members = foreach ($name in Get-TerraformSchemaKeys -InputObject $Type[1]) {
                $rendered = ConvertTo-TerraformTypeString -Type (Get-TerraformSchemaMember -InputObject $Type[1] -Name $name)
                if ($optional -ccontains $name) { $rendered = "optional($rendered)" }
                "$name = $rendered"
            }
            if (-not $members) { return 'object({})' }
            return "object({ $(@($members) -join ', ') })"
        }
    }

    [TerraformGraph.Json]::Serialize($Type, 1024, $true)
}

function ConvertTo-TerraformNestedTypeJson {
    # Not exported. Builds the cty type JSON an attribute's nested_type implies, with
    # optional members listed the way cty lists them, so a nested attribute renders and
    # serializes exactly like a plain typed one.
    param(
        [Parameter(Mandatory)]
        $NestedType
    )

    $members = [ordered]@{}
    $optional = [System.Collections.Generic.List[string]]::new()
    $attributes = Get-TerraformSchemaMember -InputObject $NestedType -Name 'attributes'
    foreach ($name in Get-TerraformSchemaKeys -InputObject $attributes) {
        $attribute = Get-TerraformSchemaMember -InputObject $attributes -Name $name
        $nested = Get-TerraformSchemaMember -InputObject $attribute -Name 'nested_type'
        $members[$name] = if ($null -ne $nested) {
            ConvertTo-TerraformNestedTypeJson -NestedType $nested
        }
        else {
            Get-TerraformSchemaMember -InputObject $attribute -Name 'type'
        }
        if (Get-TerraformSchemaMember -InputObject $attribute -Name 'optional') {
            $optional.Add($name)
        }
    }

    $object = if ($optional.Count) {
        [object[]]('object', $members, $optional.ToArray())
    }
    else {
        [object[]]('object', $members)
    }

    $mode = [string](Get-TerraformSchemaMember -InputObject $NestedType -Name 'nesting_mode')
    if ($mode -in 'list', 'set', 'map') {
        return , [object[]]($mode, $object)
    }
    , $object
}

function New-TerraformSchemaNode {
    # Not exported. Builds one TerraformGraph.SchemaNode under $Parent, derives Id, Path and
    # Depth from it, and records the Contains edge. Every kind-specific property is set on
    # every node; the ones that do not apply stay $null. -Segment inserts an Id segment
    # between the parent and the name (config, for provider configuration children).
    # Deliberately not an advanced function: no [Parameter()] attributes, since binding
    # cost per call dominated large schemas such as aws.
    param(
        $Graph,

        [string]
        $Kind,

        [string]
        $Name,

        $Parent,
        $Raw,
        $Description,
        [bool]$Deprecated,
        $SchemaVersion,
        $NestingMode,
        $MinItems,
        $MaxItems,
        $TypeJson,
        [string]$Segment,
        $Drawer,
        $Subcategory
    )

    switch ($Kind) {
        'Resource'   { $id = "$($Parent.Id)/resource/$Name"; $path = $Name }
        'DataSource' { $id = "$($Parent.Id)/data/$Name";     $path = $Name }
        'Function'   { $id = "$($Parent.Id)/function/$Name"; $path = $Name }
        default      { $id = if ($Segment) { "$($Parent.Id)/$Segment/$Name" } else { "$($Parent.Id)/$Name" }; $path = "$($Parent.Path).$Name" }
    }

    $isAttribute = $Kind -eq 'Attribute'
    # Flags are read inline for the dictionary case; a call per key dominated large schemas.
    $flags = @{}
    if ($isAttribute) {
        $isDictionary = $Raw -is [System.Collections.IDictionary]
        foreach ($key in 'required', 'optional', 'computed', 'sensitive', 'write_only') {
            $flags[$key] = [bool]($isDictionary ? $Raw[$key] : (Get-TerraformSchemaMember -InputObject $Raw -Name $key))
        }
    }

    $properties = [ordered]@{
        PSTypeName    = 'TerraformGraph.SchemaNode'
        Id            = $id
        Kind          = $Kind
        Name          = $Name
        Path          = $path
        Provider      = $Parent.Provider
        ParentId      = $Parent.Id
        Depth         = $Parent.Depth + 1
        Description   = $Description
        Deprecated    = $Deprecated
        SchemaVersion = $SchemaVersion
        NestingMode   = $NestingMode
        MinItems      = $MinItems
        MaxItems      = $MaxItems
        Type          = if ($isAttribute) { ConvertTo-TerraformTypeString -Type $TypeJson } else { $null }
        TypeJson      = if ($isAttribute -and $null -ne $TypeJson) { [TerraformGraph.Json]::Serialize($TypeJson, 1024, $true) } else { $null }
        Required      = $flags['required']
        Optional      = $flags['optional']
        Computed      = $flags['computed']
        Sensitive     = $flags['sensitive']
        WriteOnly     = $flags['write_only']
        Raw           = $Raw
    }
    # -Classify: set here rather than added afterwards, which cost seconds on azurerm. A
    # Resource or DataSource gets its classifier's values, a Function none, and a Block or
    # Attribute the values of its parent, so everything under a type is in its drawer.
    if ($Graph.Classify) {
        if ($Kind -in 'Resource', 'DataSource') { $properties.Drawer = $Drawer; $properties.Subcategory = $Subcategory }
        elseif ($Kind -eq 'Function') { $properties.Drawer = $null; $properties.Subcategory = $null }
        else { $properties.Drawer = $Parent.Drawer; $properties.Subcategory = $Parent.Subcategory }
    }
    $node = [pscustomobject]$properties

    $Graph.Nodes.Add($node)
    $Graph.Edges.Add([pscustomobject]@{
        PSTypeName = 'TerraformGraph.SchemaEdge'
        From       = $Parent.Id
        To         = $id
        Kind       = 'Contains'
    })
    $node
}

function Add-TerraformSchemaChildNodes {
    # Not exported. Walks a schema block, or an attribute's nested_type, depth-first:
    # attributes sorted by name, then blocks sorted by name, each followed by its subtree.
    # -Segment applies to the direct children only (see New-TerraformSchemaNode). Not an
    # advanced function, for the same reason as New-TerraformSchemaNode.
    param(
        $Graph,

        $Container,

        $Parent,

        [string]
        $Segment
    )

    if ($null -eq $Container) { return }

    # Dictionary input (the default) is read inline; Get-TerraformSchemaMember per key
    # dominated large schemas such as aws. PSCustomObject input still goes through it.
    $attributes = $Container -is [System.Collections.IDictionary] ? $Container['attributes'] : (Get-TerraformSchemaMember -InputObject $Container -Name 'attributes')
    $attributesAreDictionary = $attributes -is [System.Collections.IDictionary]
    if ($attributesAreDictionary) {
        [string[]]$names = @($attributes.Keys)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
    }
    else {
        $names = Get-TerraformSchemaKeys -InputObject $attributes -Sort
    }
    foreach ($name in $names) {
        $attribute = $attributesAreDictionary ? $attributes[$name] : (Get-TerraformSchemaMember -InputObject $attributes -Name $name)
        if ($attribute -is [System.Collections.IDictionary]) {
            $nested = $attribute['nested_type']
            $type = $attribute['type']
            $description = $attribute['description']
            $deprecated = [bool]$attribute['deprecated']
        }
        else {
            $nested = Get-TerraformSchemaMember -InputObject $attribute -Name 'nested_type'
            $type = Get-TerraformSchemaMember -InputObject $attribute -Name 'type'
            $description = Get-TerraformSchemaMember -InputObject $attribute -Name 'description'
            $deprecated = [bool](Get-TerraformSchemaMember -InputObject $attribute -Name 'deprecated')
        }
        $typeJson = ($null -ne $nested) ? (ConvertTo-TerraformNestedTypeJson -NestedType $nested) : $type

        $node = New-TerraformSchemaNode -Graph $Graph -Kind Attribute -Name $name -Parent $Parent -Raw $attribute `
            -Description $description -Deprecated $deprecated -TypeJson $typeJson -Segment $Segment

        if ($null -ne $nested) {
            Add-TerraformSchemaChildNodes -Graph $Graph -Container $nested -Parent $node
        }
    }

    $blockTypes = $Container -is [System.Collections.IDictionary] ? $Container['block_types'] : (Get-TerraformSchemaMember -InputObject $Container -Name 'block_types')
    $blockTypesAreDictionary = $blockTypes -is [System.Collections.IDictionary]
    if ($blockTypesAreDictionary) {
        [string[]]$names = @($blockTypes.Keys)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
    }
    else {
        $names = Get-TerraformSchemaKeys -InputObject $blockTypes -Sort
    }
    foreach ($name in $names) {
        $blockType = $blockTypesAreDictionary ? $blockTypes[$name] : (Get-TerraformSchemaMember -InputObject $blockTypes -Name $name)
        if ($blockType -is [System.Collections.IDictionary]) {
            $inner = $blockType['block']
            $nestingMode = $blockType['nesting_mode']
            $minItems = $blockType['min_items']
            $maxItems = $blockType['max_items']
        }
        else {
            $inner = Get-TerraformSchemaMember -InputObject $blockType -Name 'block'
            $nestingMode = Get-TerraformSchemaMember -InputObject $blockType -Name 'nesting_mode'
            $minItems = Get-TerraformSchemaMember -InputObject $blockType -Name 'min_items'
            $maxItems = Get-TerraformSchemaMember -InputObject $blockType -Name 'max_items'
        }
        if ($inner -is [System.Collections.IDictionary]) {
            $description = $inner['description']
            $deprecated = [bool]$inner['deprecated']
        }
        else {
            $description = Get-TerraformSchemaMember -InputObject $inner -Name 'description'
            $deprecated = [bool](Get-TerraformSchemaMember -InputObject $inner -Name 'deprecated')
        }

        $node = New-TerraformSchemaNode -Graph $Graph -Kind Block -Name $name -Parent $Parent -Raw $blockType `
            -Description $description -Deprecated $deprecated `
            -NestingMode $nestingMode -MinItems $minItems -MaxItems $maxItems -Segment $Segment

        Add-TerraformSchemaChildNodes -Graph $Graph -Container $inner -Parent $node
    }
}

function ConvertTo-TerraformSchemaGraph {
    <#
    .SYNOPSIS
        Converts a provider schema into a graph of canonical schema nodes.

    .DESCRIPTION
        ConvertTo-TerraformSchemaGraph walks the output of Get-TerraformProviderSchema and
        returns one TerraformGraph.SchemaGraph per input document. Every provider, resource,
        data source, block and attribute becomes a TerraformGraph.SchemaNode, and every
        node other than a provider gets one Contains edge from its parent. The provider's
        own configuration block (provider_schemas[address].provider.block) becomes
        Attribute and Block nodes directly under the Provider node, with /config/ in
        their Id and Paths such as aws.region.

        Each node has two names. Id is canonical and unique within the document: it starts
        with the full provider address and adds one segment per level, such as
        registry.terraform.io/hashicorp/null/resource/null_resource/triggers. Use it to
        join nodes and edges. Path is the short dotted form a configuration author writes,
        such as null_resource.triggers. It drops the provider, so two providers can share
        a Path; it is for reading and filtering, not for joins.

        Attributes declared with nested_type are rendered as the type they imply and also
        get child Attribute nodes, exactly like block_types get child nodes, so the graph
        has the same shape whether a provider used blocks or nested attributes.

        Nodes are ordered depth-first and the same input always gives the same order:
        each provider, then its configuration attributes (sorted) and blocks (sorted)
        and their subtrees, then its resources sorted by type, each followed by its
        attributes (sorted) and blocks (sorted) and their subtrees, then data sources,
        then functions.

    .PARAMETER Schema
        The provider schema document. Accepts the ordered dictionary Get-TerraformProviderSchema
        returns by default, the -OutputFormat Json text (piped lines are joined), or that text
        passed through ConvertFrom-TerraformJson. It must have a top-level provider_schemas.

        Without -Schema, -Provider names providers to load from the local schema cache
        instead (see Get-TerraformSchemaPack and Get-TerraformProviderSchema -SaveToCache).
        The cached documents are combined and converted exactly as if that document had
        been piped in, giving one graph.

    .PARAMETER Provider
        With -Schema: only include these providers: 'aws', 'hashicorp/aws', or
        'registry.terraform.io/hashicorp/aws', normalized the same way as
        Get-TerraformProviderSchema -Provider. Matched against the provider_schemas keys
        without regard to case. A provider that is not in the document is a terminating
        error that lists the providers that are. Default: every provider in the document.
        Wildcards are not allowed with -Schema.

        Without -Schema: the cached providers to load. Patterns match by shape, as in
        Get-TerraformSchemaCache: 'azurerm' or 'azure*' match the bare name in any
        namespace, 'hashicorp/azure*' namespace/name, and a full address the address. A
        wildcard can match several providers; a name without one that matches cached
        providers in several namespaces must be the hashicorp one or is an error. A
        pattern with no cached schema is a terminating error that names
        Get-TerraformSchemaPack and Get-TerraformProviderSchema -SaveToCache.

    .PARAMETER Version
        Without -Schema: the cached version to load for every -Provider. Default: the
        newest cached version of each.

    .PARAMETER IncludeFunctions
        Add provider functions (the functions map in newer schemas) as Function nodes
        under their provider. Off by default.

    .PARAMETER Classify
        Overlay classifier drawers (see New-TerraformClassifier). Every SchemaNode gets
        Drawer and Subcategory: Resource and DataSource nodes from their provider's
        classifier, their Block and Attribute descendants the same values as the type they
        belong to, Provider, provider config and Function nodes $null. A type the
        classifier lacks, or a provider with no classifier (one warning), is in the
        unclassified drawer. The graph gets Drawers: one TerraformGraph.DrawerSummary per
        drawer (Drawer, TypeCount, InstanceCount empty). Ids, nodes and edges are exactly
        the same as without -Classify. Reads local files only.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before
        $env:LOCALAPPDATA\TerraformGraph\classifiers and the classifiers bundled with the
        module. Implies -Classify.

    .EXAMPLE
        Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph

        Fetch the hashicorp/null schema and convert it. The default view is Providers,
        NodeCount and EdgeCount.

    .EXAMPLE
        $graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph -Provider aws
        $graph.Nodes | Where-Object Path -like 'aws_s3_bucket.*'

        Keep only registry.terraform.io/hashicorp/aws out of a directory that uses several
        providers, then list one resource's attributes and blocks.

    .EXAMPLE
        $graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
        $graph.Summary
        $graph.Nodes | Where-Object Kind -eq 'Resource' | Select-Object Path, Id

        Count nodes by Kind, then list every resource with its canonical Id.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider hashicorp/azurerm
        ConvertTo-TerraformSchemaGraph -Provider azurerm

        Download the azurerm schema pack into the local cache once, then build the graph
        from the cache with no terraform and no network.

    .EXAMPLE
        $graph = ConvertTo-TerraformSchemaGraph -Provider vsphere -Classify
        $graph.Drawers
        $graph.Nodes | Where-Object { $_.Kind -eq 'Resource' -and $_.Drawer -eq 'storage' } | Select-Object Path, Subcategory

        Group the cached vsphere schema into drawers with the bundled classifier, then list
        the storage resources.

    .OUTPUTS
        TerraformGraph.SchemaGraph. Default view is Providers, NodeCount, EdgeCount; Summary
        is an ordered Kind -> count table; with -Classify, Drawers is a
        TerraformGraph.DrawerSummary array. Nodes are TerraformGraph.SchemaNode (default view
        Kind, Path, Type, Required, Depth), edges TerraformGraph.SchemaEdge.

    .NOTES
        Id scheme, where <address> is the provider_schemas key:
            Provider    <address>
            Config      <address>/config/<name>  (Attribute or Block; Path <provider>.<name>)
            Resource    <address>/resource/<type>
            DataSource  <address>/data/<type>
            Function    <address>/function/<name>
            Block       <parent Id>/<block name>
            Attribute   <parent Id>/<attribute name>

    .LINK
        Get-TerraformProviderSchema

    .LINK
        Get-TerraformSchemaPack

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    # Cache is the default set so that -Provider alone binds to it; piped or positional
    # -Schema still selects Document.
    [CmdletBinding(DefaultParameterSetName = 'Cache')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ParameterSetName = 'Document')]
        [object]
        $Schema,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(Mandatory, ParameterSetName = 'Cache')]
        [ValidateScript({
            # A wildcard is matched against the schema cache in the body.
            if (-not [WildcardPattern]::ContainsWildcardCharacters($_)) {
                $null = ConvertTo-TerraformProviderAddress -Provider $_
            }
            $true
        })]
        [string[]]
        $Provider,

        [Parameter(ParameterSetName = 'Cache')]
        [string]
        $Version,

        [switch]
        $IncludeFunctions,

        [switch]
        $Classify,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    begin {
        $classifyGraph = $Classify -or $PSBoundParameters.ContainsKey('ClassifierPath')
        # Address -> schema version, when the graph comes from the cache, so -Classify
        # prefers the classifier generated from the same version.
        $schemaVersions = @{}
        $wanted = @()
        if ($PSCmdlet.ParameterSetName -eq 'Document') {
            $wildcards = @($Provider | Where-Object { [WildcardPattern]::ContainsWildcardCharacters($_) })
            if ($wildcards.Count) {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("Provider '$($wildcards -join "', '")' has a wildcard. Wildcards are only allowed without -Schema, where -Provider reads the schema cache."),
                    'SchemaProviderWildcard',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $wildcards))
            }
            $wanted = @(foreach ($p in $Provider) { (ConvertTo-TerraformProviderAddress -Provider $p).Address })
        }
        $jsonLines = [System.Collections.Generic.List[string]]::new()

        $convert = {
            param($Document)

            $providerSchemas = Get-TerraformSchemaMember -InputObject $Document -Name 'provider_schemas'
            if ($null -eq $providerSchemas) {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new('Schema has no top-level provider_schemas. Pass the output of Get-TerraformProviderSchema, its -OutputFormat Json text, or that text through ConvertFrom-TerraformJson.'),
                    'SchemaMissingProviderSchemas',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $Document))
            }

            $addresses = @(Get-TerraformSchemaKeys -InputObject $providerSchemas -Sort)
            if ($wanted.Count) {
                $missing = @($wanted | Where-Object { $addresses -notcontains $_ })
                if ($missing.Count) {
                    $available = if ($addresses.Count) { $addresses -join ', ' } else { '(none)' }
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new("Provider '$($missing -join "', '")' is not in provider_schemas. Available: $available."),
                        'SchemaProviderNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $missing))
                }
                $addresses = @($addresses | Where-Object { $wanted -contains $_ })
            }

            $graph = [pscustomobject]@{
                Nodes    = [System.Collections.Generic.List[object]]::new()
                Edges    = [System.Collections.Generic.List[object]]::new()
                Classify = $classifyGraph
            }
            $overlay = if ($classifyGraph) { Get-TerraformClassifierOverlay -Address $addresses -Version $schemaVersions -ClassifierPath $ClassifierPath }

            foreach ($address in $addresses) {
                $entry = Get-TerraformSchemaMember -InputObject $providerSchemas -Name $address
                $config = Get-TerraformSchemaMember -InputObject (Get-TerraformSchemaMember -InputObject $entry -Name 'provider') -Name 'block'
                $shortName = $address.Split('/')[-1]

                $providerNode = [pscustomobject]@{
                    PSTypeName    = 'TerraformGraph.SchemaNode'
                    Id            = $address
                    Kind          = 'Provider'
                    Name          = $shortName
                    Path          = $shortName
                    Provider      = $address
                    ParentId      = $null
                    Depth         = 0
                    Description   = Get-TerraformSchemaMember -InputObject $config -Name 'description'
                    Deprecated    = [bool](Get-TerraformSchemaMember -InputObject $config -Name 'deprecated')
                    SchemaVersion = $null
                    NestingMode   = $null
                    MinItems      = $null
                    MaxItems      = $null
                    Type          = $null
                    TypeJson      = $null
                    Required      = $null
                    Optional      = $null
                    Computed      = $null
                    Sensitive     = $null
                    WriteOnly     = $null
                    Raw           = $entry
                }
                if ($classifyGraph) {
                    $providerNode.PSObject.Properties.Add([psnoteproperty]::new('Drawer', $null))
                    $providerNode.PSObject.Properties.Add([psnoteproperty]::new('Subcategory', $null))
                }
                $graph.Nodes.Add($providerNode)
                Add-TerraformSchemaChildNodes -Graph $graph -Container $config -Parent $providerNode -Segment config

                $lookup = if ($classifyGraph) { $overlay.ByAddress[$address] }
                foreach ($section in @(
                        @{ Key = 'resource_schemas';    Kind = 'Resource';   ClassifierKind = 'resource' }
                        @{ Key = 'data_source_schemas'; Kind = 'DataSource'; ClassifierKind = 'data-source' }
                    )) {
                    $schemas = Get-TerraformSchemaMember -InputObject $entry -Name $section.Key
                    foreach ($type in Get-TerraformSchemaKeys -InputObject $schemas -Sort) {
                        $resource = Get-TerraformSchemaMember -InputObject $schemas -Name $type
                        $block = Get-TerraformSchemaMember -InputObject $resource -Name 'block'
                        # -Classify: a type the classifier lacks, or a provider with none, is unclassified.
                        $classified = $null
                        if ($lookup) { $null = $lookup.TryGetValue("$($section.ClassifierKind)|$type", [ref]$classified) }
                        $node = New-TerraformSchemaNode -Graph $graph -Kind $section.Kind -Name $type -Parent $providerNode -Raw $resource `
                            -Description (Get-TerraformSchemaMember -InputObject $block -Name 'description') `
                            -Deprecated ([bool](Get-TerraformSchemaMember -InputObject $block -Name 'deprecated')) `
                            -SchemaVersion (Get-TerraformSchemaMember -InputObject $resource -Name 'version') `
                            -Drawer $(if ($classified) { $classified.Drawer } else { 'unclassified' }) `
                            -Subcategory $(if ($classified) { $classified.Subcategory } else { $null })
                        Add-TerraformSchemaChildNodes -Graph $graph -Container $block -Parent $node
                    }
                }

                if ($IncludeFunctions) {
                    $functions = Get-TerraformSchemaMember -InputObject $entry -Name 'functions'
                    foreach ($name in Get-TerraformSchemaKeys -InputObject $functions -Sort) {
                        $function = Get-TerraformSchemaMember -InputObject $functions -Name $name
                        $null = New-TerraformSchemaNode -Graph $graph -Kind Function -Name $name -Parent $providerNode -Raw $function `
                            -Description (Get-TerraformSchemaMember -InputObject $function -Name 'description') `
                            -Deprecated ($null -ne (Get-TerraformSchemaMember -InputObject $function -Name 'deprecation_message'))
                    }
                }
            }

            $result = [pscustomobject]@{
                PSTypeName = 'TerraformGraph.SchemaGraph'
                Providers  = [string[]]$addresses
                Nodes      = $graph.Nodes.ToArray()
                Edges      = $graph.Edges.ToArray()
            }
            if ($classifyGraph) {
                $items = foreach ($node in $result.Nodes) {
                    if ($node.Kind -in 'Resource', 'DataSource') { [pscustomobject]@{ Drawer = $node.Drawer; TypeKey = $node.Id } }
                }
                $result.PSObject.Properties.Add([psnoteproperty]::new('Drawers', [object[]]@(New-TerraformDrawerSummary -Item @($items) -Order $overlay.Order)))
            }
            $result
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Cache') { return }
        # JSON text is collected and parsed once in end, so piped lines work.
        if ($Schema -is [string]) {
            $jsonLines.Add($Schema)
            return
        }
        & $convert $Schema
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Cache') {
            try {
                $cached = @(Resolve-TerraformSchemaCacheProvider -Name $Provider -Version $Version)
            }
            catch {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
                    'SchemaNotCached',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Provider))
            }
            $wanted = @($cached.ProviderAddress)
            foreach ($item in $cached) { $schemaVersions[$item.ProviderAddress] = $item.Version }
            & $convert (Get-TerraformSchemaCacheDocument -Entry $cached)
            return
        }

        if ($jsonLines.Count -eq 0) { return }
        $document = ($jsonLines -join [Environment]::NewLine) | ConvertFrom-TerraformJson -AsHashtable -ErrorAction Stop
        & $convert $document
    }
}

function Get-TerraformExpressionReferences {
    # Not exported. Walks an expression object from the Go parser and returns every
    # ScopeTraversalExpr Traversal in source order, deduplicated, as {Traversal, Root}.
    # Root is the binding root: var.<name>, local.<name> or module.<name>.<output>, with
    # index and attribute suffixes stripped; $null for anything else (resources, data,
    # path, terraform, each, count, self, for-expression variables).
    param(
        [AllowNull()]
        $Expr
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $found = [System.Collections.Generic.List[object]]::new()

    $walk = {
        param($e)
        if ($null -eq $e) { return }
        switch ([string]$e.Kind) {
            'ScopeTraversalExpr' {
                $traversal = [string]$e.Traversal
                if ($seen.Add($traversal)) {
                    # One index step is [key]; a quoted key may contain ] or an escaped ".
                    $index = '\[(?:"(?:[^"\\]|\\.)*"|[^\]"]*)\]'
                    $root = $null
                    if ($traversal -match '^(var|local)\.([A-Za-z_][\w-]*)') {
                        $root = "$($Matches[1]).$($Matches[2])"
                    }
                    elseif ($traversal -match "^module\.([A-Za-z_][\w-]*)(?:$index)*\.([A-Za-z_][\w-]*)") {
                        $root = "module.$($Matches[1]).$($Matches[2])"
                    }
                    $found.Add([pscustomobject]@{ Traversal = $traversal; Root = $root })
                }
            }
            'TemplateExpr'          { foreach ($p in @($e.Parts)) { & $walk $p } }
            'FunctionCallExpr'      { foreach ($a in @($e.Args)) { & $walk $a } }
            'ObjectConsExpr'        { foreach ($i in @($e.Items)) { & $walk $i.Key; & $walk $i.Value } }
            'TupleConsExpr'         { foreach ($x in @($e.Exprs)) { & $walk $x } }
            'ConditionalExpr'       { & $walk $e.Condition; & $walk $e.TrueResult; & $walk $e.FalseResult }
            'BinaryOpExpr'          { & $walk $e.LHS; & $walk $e.RHS }
            'UnaryOpExpr'           { & $walk $e.Val }
            'IndexExpr'             { & $walk $e.Collection; & $walk $e.Key }
            'SplatExpr'             { & $walk $e.Source; & $walk $e.Each }
            'ForExpr'               { & $walk $e.CollExpr; & $walk $e.KeyExpr; & $walk $e.ValExpr; & $walk $e.CondExpr }
            'ParenthesesExpr'       { & $walk $e.Expression }
            'TemplateWrapExpr'      { & $walk $e.Wrapped }
            # A RelativeTraversalExpr's Traversal is relative to Source (.id), not a scope.
            'RelativeTraversalExpr' { & $walk $e.Source }
        }
    }
    & $walk $Expr

    , $found.ToArray()
}

function Get-TerraformExpressionLiteral {
    # Not exported. Value of a literal expression (a LiteralValueExpr, or a TemplateExpr with
    # IsLiteral), else $null. The leading comma keeps a list value from being unrolled.
    param(
        [AllowNull()]
        $Expr
    )

    if ($null -eq $Expr) { return $null }
    if ($Expr.Kind -eq 'LiteralValueExpr' -or $Expr.IsLiteral) { return , $Expr.Value }
    $null
}

function ConvertTo-TerraformVariableGraph {
    <#
    .SYNOPSIS
        Builds a graph of variables, locals and outputs across a module tree.

    .DESCRIPTION
        ConvertTo-TerraformVariableGraph reads the blocks Get-TerraformModuleGraph already
        parsed and returns one TerraformGraph.VariableGraph. Every variable, every local
        (one per attribute of a locals block) and every output in every parsed module
        becomes a TerraformGraph.VariableNode. Nothing is parsed again.

        Edges follow values. A declaration whose expression reads var.x or local.x gets a
        Reference edge from that node. A module call argument a = expr gets an Argument
        edge from each var. or local. it reads in the calling module to the child's
        variable a. Reading module.c.o, in a declaration or a call argument, gets an
        OutputReference edge from the child's output o.

        Variables in a child module carry Binding: Argument when the parent's module call
        sets them (ArgumentExpr and ArgumentLiteral hold what it passed), Default when
        it does not and the variable has a default, Unset otherwise. Root variables are
        Default or Unset; their values come from tfvars or the command line, which this
        does not read.

        Module nodes whose Blocks are $null (not parsed without -Recurse, unresolved, or
        Cycle) contribute nothing and are listed in Skipped. Arguments to, and outputs
        of, a skipped module make no edges and are not reported as unresolved.

    .PARAMETER ModuleGraph
        A TerraformGraph.ModuleGraph from Get-TerraformModuleGraph. Use -Recurse there to
        include every module in the tree.

    .EXAMPLE
        Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph

        Variable graph for the whole infra tree. The default view is Root, NodeCount,
        EdgeCount and UnresolvedCount; Summary counts nodes by Kind.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        $graph.Unresolved | Where-Object Reason -eq 'UndeclaredArgument'

        List module call arguments that name a variable the child does not declare.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        $graph.Nodes | Where-Object Binding -eq 'Unset'

        Variables that no caller sets and that have no default: in the root they must
        come from tfvars or -var; in a child module Terraform rejects the call.

    .OUTPUTS
        TerraformGraph.VariableGraph with Root, Nodes, Edges, Unresolved and Skipped, plus
        NodeCount, EdgeCount, UnresolvedCount and Summary (ordered Kind -> count). Default
        view is Root, NodeCount, EdgeCount, UnresolvedCount. Nodes are
        TerraformGraph.VariableNode (default view Kind, Module, Name, Binding, Literal),
        edges TerraformGraph.VariableEdge.

    .NOTES
        Id scheme, where <module> is the ModuleAddress ('root' for the root module):
            Variable    <module>/var/<name>
            Local       <module>/local/<name>
            Output      <module>/output/<name>

        Only declaration expressions (variable default, local value, output value) and
        module call arguments are read; resource, data, check and other blocks make no
        edges. The module call meta-arguments source, version, count, for_each,
        providers and depends_on are not arguments.

        Every reference is listed on its node (References), but only roots that name a
        node make an edge: var.<name>, local.<name> and module.<call>.<output>. Index
        and attribute suffixes are dropped (var.tags["a"] binds var.tags) and kept in
        Via. Resources, data sources, path., terraform., each., count., self. and
        for-expression variables are references only, and so is a bare module.<call>,
        which names no single output.

        Unresolved records, each with Module, Root, Reason, File and Line:
            UndeclaredReference  var. or local. with no such node in its module
            UndeclaredArgument   a call argument the child does not declare
                                 (Module is the child, Root var.<argument>)
            UndeclaredOutput     module.<call>.<output> where the parsed child has no
                                 such output, or there is no such call

    .LINK
        Get-TerraformModuleGraph

    .LINK
        Get-TerraformVariableTrace

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $ModuleGraph
    )

    process {
        $metaArguments = 'source', 'version', 'count', 'for_each', 'providers', 'depends_on'

        $nodes = [System.Collections.Generic.List[object]]::new()
        $edges = [System.Collections.Generic.List[object]]::new()
        $unresolved = [System.Collections.Generic.List[object]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

        $leaf = { param($range) if ($range -and $range.Filename) { Split-Path -Path $range.Filename -Leaf } }
        # Literal value of an attribute, else its source text; $null when absent.
        $attributeValue = {
            param($attribute)
            if ($null -eq $attribute) { return $null }
            $literal = Get-TerraformExpressionLiteral -Expr $attribute.Expr
            if ($null -ne $literal) { return , $literal }
            $attribute.Expr.Raw
        }
        # Attributes of a body in source order (the parser keys them by name).
        $sortedAttributes = {
            param($body)
            if ($null -eq $body -or $null -eq $body.Attributes) { return }
            @($body.Attributes.PSObject.Properties.Value) | Sort-Object { $_.SrcRange.Start.Byte }
        }
        $childAddressOf = {
            param($address, $label)
            if ($address -eq 'root') { "module.$label" } else { "$address.module.$label" }
        }

        $moduleNodes = @($ModuleGraph.Nodes)
        $byAddress = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($module in $moduleNodes) { $byAddress[[string]$module.ModuleAddress] = $module }

        $newNode = {
            param($Kind, $Name, $Module, $File, $Line, $Expr, $Raw)
            $segment = @{ Variable = 'var'; Local = 'local'; Output = 'output' }[$Kind]
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.VariableNode'
                Id              = "$Module/$segment/$Name"
                Kind            = $Kind
                Name            = $Name
                Module          = $Module
                File            = $File
                Line            = $Line
                Expr            = $Expr
                Literal         = Get-TerraformExpressionLiteral -Expr $Expr
                References      = Get-TerraformExpressionReferences -Expr $Expr
                Type            = $null
                Description     = $null
                Sensitive       = $null
                Nullable        = $null
                HasDefault      = $null
                Binding         = $null
                ArgumentExpr    = $null
                ArgumentLiteral = $null
                Raw             = $Raw
            }
        }

        # Pass 1: every node, so edge targets exist before any edge is built.
        foreach ($module in $moduleNodes) {
            $address = [string]$module.ModuleAddress
            if ($null -eq $module.Blocks) {
                $skipped.Add($address)
                continue
            }
            $blocks = @($module.Blocks)
            $callArguments = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            if ($module.Block) {
                foreach ($attribute in & $sortedAttributes $module.Block.Body) {
                    if ($metaArguments -cnotcontains $attribute.Name) { $callArguments[[string]$attribute.Name] = $attribute }
                }
            }

            $variables = foreach ($block in @($blocks | Where-Object Type -eq 'variable')) {
                $attributes = $block.Body.Attributes
                $default = $attributes.PSObject.Properties['default']
                $node = & $newNode Variable ([string]$block.Labels[0]) $address $block.File $block.Line ($default ? $default.Value.Expr : $null) $block
                $sensitive = & $attributeValue $attributes.sensitive
                $nullable = & $attributeValue $attributes.nullable
                $node.Type        = $attributes.PSObject.Properties['type'] ? $attributes.type.Expr.Raw : $null
                $node.Description = & $attributeValue $attributes.description
                $node.Sensitive   = ($null -ne $sensitive) ? $sensitive : $false
                $node.Nullable    = ($null -ne $nullable) ? $nullable : $true
                $node.HasDefault  = $null -ne $default
                $argument = $null
                if ($callArguments.TryGetValue($node.Name, [ref]$argument)) {
                    $node.Binding         = 'Argument'
                    $node.ArgumentExpr    = $argument.Expr
                    $node.ArgumentLiteral = Get-TerraformExpressionLiteral -Expr $argument.Expr
                }
                else {
                    $node.Binding = $node.HasDefault ? 'Default' : 'Unset'
                }
                $node
            }
            $locals = foreach ($block in @($blocks | Where-Object Type -eq 'locals')) {
                foreach ($attribute in & $sortedAttributes $block.Body) {
                    & $newNode Local ([string]$attribute.Name) $address (& $leaf $attribute.NameRange) $attribute.NameRange.Start.Line $attribute.Expr $attribute
                }
            }
            $outputs = foreach ($block in @($blocks | Where-Object Type -eq 'output')) {
                $attributes = $block.Body.Attributes
                $node = & $newNode Output ([string]$block.Labels[0]) $address $block.File $block.Line $attributes.value.Expr $block
                $sensitive = & $attributeValue $attributes.sensitive
                $node.Sensitive = ($null -ne $sensitive) ? $sensitive : $false
                $node
            }

            foreach ($group in @(, @($variables)) + @(, @($locals)) + @(, @($outputs))) {
                # Ordinal by name, so the order never depends on culture.
                $sorted = [System.Collections.Generic.List[object]]::new()
                foreach ($node in $group) { if ($null -ne $node) { $sorted.Add($node) } }
                $sorted.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
                foreach ($node in $sorted) {
                    $nodes.Add($node)
                    $byId[$node.Id] = $node
                }
            }
        }

        # Edges for one expression in module $address toward node Id $to. $to is $null
        # when the target is in a skipped module or undeclared: references are still
        # checked, but no edge is made.
        $connect = {
            param($address, $expr, $to, $kind)
            $file = & $leaf $expr.SrcRange
            $line = $expr.SrcRange.Start.Line
            # Assigned first: the helper returns one array, which foreach would not unroll.
            $references = Get-TerraformExpressionReferences -Expr $expr
            foreach ($reference in $references) {
                $root = $reference.Root
                if ($null -eq $root) { continue }
                $parts = $root.Split('.')
                $edgeKind = $kind
                if ($parts[0] -eq 'module') {
                    $childAddress = & $childAddressOf $address $parts[1]
                    $child = $null
                    if ($byAddress.TryGetValue($childAddress, [ref]$child) -and $null -eq $child.Blocks) { continue }
                    $from = "$childAddress/output/$($parts[2])"
                    if (-not $byId.ContainsKey($from)) {
                        $unresolved.Add([pscustomobject]@{ Module = $address; Root = $root; Reason = 'UndeclaredOutput'; File = $file; Line = $line })
                        continue
                    }
                    $edgeKind = 'OutputReference'
                }
                else {
                    $from = "$address/$($parts[0])/$($parts[1])"
                    if (-not $byId.ContainsKey($from)) {
                        $unresolved.Add([pscustomobject]@{ Module = $address; Root = $root; Reason = 'UndeclaredReference'; File = $file; Line = $line })
                        continue
                    }
                }
                if ($null -eq $to) { continue }
                $edges.Add([pscustomobject]@{
                    PSTypeName = 'TerraformGraph.VariableEdge'
                    From       = $from
                    To         = $to
                    Kind       = $edgeKind
                    Via        = $reference.Traversal
                    File       = $file
                    Line       = $line
                })
            }
        }

        # Pass 2: edges, per module in ModuleGraph order: declarations in node order, then
        # module call arguments, calls in source order and arguments in source order.
        $index = 0
        foreach ($module in $moduleNodes) {
            if ($null -eq $module.Blocks) { continue }
            $address = [string]$module.ModuleAddress

            while ($index -lt $nodes.Count -and $nodes[$index].Module -ceq $address) {
                $node = $nodes[$index++]
                if ($null -ne $node.Expr) { & $connect $address $node.Expr $node.Id 'Reference' }
            }

            foreach ($call in @($module.Blocks | Where-Object Type -eq 'module')) {
                $childAddress = & $childAddressOf $address ([string]$call.Labels[0])
                $child = $null
                $childParsed = $byAddress.TryGetValue($childAddress, [ref]$child) -and $null -ne $child.Blocks
                foreach ($attribute in & $sortedAttributes $call.Body) {
                    $name = [string]$attribute.Name
                    if ($metaArguments -ccontains $name) { continue }
                    $to = $null
                    if ($childParsed) {
                        $to = "$childAddress/var/$name"
                        if (-not $byId.ContainsKey($to)) {
                            $unresolved.Add([pscustomobject]@{
                                Module = $childAddress
                                Root   = "var.$name"
                                Reason = 'UndeclaredArgument'
                                File   = & $leaf $attribute.NameRange
                                Line   = $attribute.NameRange.Start.Line
                            })
                            $to = $null
                        }
                    }
                    & $connect $address $attribute.Expr $to 'Argument'
                }
            }
        }

        [pscustomobject]@{
            PSTypeName = 'TerraformGraph.VariableGraph'
            Root       = $ModuleGraph.Root
            Nodes      = $nodes.ToArray()
            Edges      = $edges.ToArray()
            Unresolved = $unresolved.ToArray()
            Skipped    = $skipped.ToArray()
        }
    }
}

function Get-TerraformVariableTrace {
    <#
    .SYNOPSIS
        Follows a variable, local or output through a variable graph.

    .DESCRIPTION
        Get-TerraformVariableTrace starts at one node of a TerraformGraph.VariableGraph and
        walks its edges breadth-first. Upstream follows edges backwards (To to From) and
        answers where a value comes from; Downstream follows them forwards (From to To)
        and answers what a value feeds. Both does upstream first, then downstream.

        Each returned node is a copy of the graph's node with a Distance property: 0 for
        the start, 1, 2, ... downstream, and -1, -2, ... upstream when -Direction is Both
        (with Upstream alone distances are positive). A node is returned once, at the
        distance it was first reached. Cycles, such as locals that reference each other,
        terminate because no node is expanded twice.

    .PARAMETER VariableGraph
        A TerraformGraph.VariableGraph from ConvertTo-TerraformVariableGraph.

    .PARAMETER Id
        The Id of the start node, such as module.network/var/aws_region. An Id that is
        not in the graph is a terminating error that lists up to 10 nodes with the same
        Name in any module.

    .PARAMETER Direction
        Upstream, Downstream or Both (default).

    .PARAMETER MaxDepth
        Maximum number of edges from the start node. Default 50.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        ($graph | Get-TerraformVariableTrace -Id 'module.network/var/aws_region' -Direction Upstream).Nodes

        Where the network module's aws_region comes from: the root variable that the
        module call passes in.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        ($graph | Get-TerraformVariableTrace -Id 'root/var/aws_region' -Direction Downstream).Nodes

        Everything the root aws_region variable feeds: the root output that echoes it and
        the network module variable it is passed to.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
        $trace = $graph | Get-TerraformVariableTrace -Id 'module.network.module.endpoint/output/address'
        $trace.Nodes
        $trace.Edges | Format-Table From, To, Kind, Via

        Both directions from a middle node: the host and port variables that build the
        endpoint address at Distance -1, the network output that re-exports it at 1,
        and the edges walked.

    .OUTPUTS
        TerraformGraph.VariableTrace with Start, Direction, Nodes and Edges. Nodes are
        TerraformGraph.VariableTraceNode (default view Distance, Kind, Module, Name,
        Binding, Literal); Edges are the TerraformGraph.VariableEdge objects walked.

    .LINK
        ConvertTo-TerraformVariableGraph

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $VariableGraph,

        [Parameter(Mandatory)]
        [string]
        $Id,

        [ValidateSet('Upstream', 'Downstream', 'Both')]
        [string]
        $Direction = 'Both',

        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $MaxDepth = 50
    )

    process {
        $byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($node in @($VariableGraph.Nodes)) { $byId[$node.Id] = $node }

        $start = $null
        if (-not $byId.TryGetValue($Id, [ref]$start)) {
            $name = $Id.Split('/')[-1]
            $near = @($VariableGraph.Nodes | Where-Object Name -ceq $name | Select-Object -First 10 -ExpandProperty Id)
            $hint = if ($near.Count) { " Nodes named '$name': $($near -join ', ')." } else { " No node is named '$name'." }
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new("Node '$Id' is not in the variable graph.$hint"),
                'VariableNodeNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Id))
        }

        # Adjacency as indexes into Edges, in Edges order, so the walk is deterministic.
        # Indexes rather than the edges themselves: every PSCustomObject compares equal.
        $allEdges = @($VariableGraph.Edges)
        $outgoing = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new([System.StringComparer]::Ordinal)
        $incoming = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new([System.StringComparer]::Ordinal)
        for ($i = 0; $i -lt $allEdges.Count; $i++) {
            foreach ($pair in @(@($outgoing, $allEdges[$i].From), @($incoming, $allEdges[$i].To))) {
                if (-not $pair[0].ContainsKey($pair[1])) { $pair[0][$pair[1]] = [System.Collections.Generic.List[int]]::new() }
                $pair[0][$pair[1]].Add($i)
            }
        }

        $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $walkedEdges = [System.Collections.Generic.HashSet[int]]::new()
        $resultNodes = [System.Collections.Generic.List[object]]::new()
        $resultEdges = [System.Collections.Generic.List[object]]::new()

        $emit = {
            param($node, $distance)
            $copy = [pscustomobject]@{ PSTypeName = 'TerraformGraph.VariableTraceNode'; Distance = $distance }
            foreach ($property in $node.PSObject.Properties) {
                $copy.PSObject.Properties.Add([psnoteproperty]::new($property.Name, $property.Value))
            }
            $resultNodes.Add($copy)
        }

        $null = $visited.Add($start.Id)
        & $emit $start 0

        $passes = @(switch ($Direction) {
            'Upstream'   { , @('Upstream', 1) }
            'Downstream' { , @('Downstream', 1) }
            'Both'       { @('Upstream', -1), @('Downstream', 1) }
        })
        foreach ($pass in $passes) {
            $adjacency = ($pass[0] -eq 'Upstream') ? $incoming : $outgoing
            $sign = $pass[1]
            $frontier = [System.Collections.Generic.List[string]]::new()
            $frontier.Add($start.Id)
            $depth = 0
            while ($frontier.Count -gt 0 -and $depth -lt $MaxDepth) {
                $depth++
                $next = [System.Collections.Generic.List[string]]::new()
                foreach ($current in $frontier) {
                    $list = $null
                    if (-not $adjacency.TryGetValue($current, [ref]$list)) { continue }
                    foreach ($edgeIndex in $list) {
                        $edge = $allEdges[$edgeIndex]
                        if ($walkedEdges.Add($edgeIndex)) { $resultEdges.Add($edge) }
                        $neighbor = ($pass[0] -eq 'Upstream') ? $edge.From : $edge.To
                        if ($visited.Add($neighbor)) {
                            & $emit $byId[$neighbor] ($sign * $depth)
                            $next.Add($neighbor)
                        }
                    }
                }
                $frontier = $next
            }
        }

        [pscustomobject]@{
            PSTypeName = 'TerraformGraph.VariableTrace'
            Start      = $start
            Direction  = $Direction
            Nodes      = $resultNodes.ToArray()
            Edges      = $resultEdges.ToArray()
        }
    }
}

function Get-TerraformModuleProviderMap {
    # Not exported. Local name -> lowercase provider address from one module's own
    # terraform { required_providers } sources.
    param($Blocks, [string]$ModuleAddress)

    $declared = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($terraform in @($Blocks | Where-Object Type -eq 'terraform')) {
        foreach ($required in @($terraform.Body.Blocks | Where-Object Type -eq 'required_providers')) {
            if ($null -eq $required.Body.Attributes) { continue }
            foreach ($attribute in @($required.Body.Attributes.PSObject.Properties.Value)) {
                $source = $null
                foreach ($item in @($attribute.Expr.Items)) {
                    if ($null -ne $item -and ([string]$item.Key.Raw).Trim('"') -ceq 'source') {
                        $source = Get-TerraformExpressionLiteral -Expr $item.Value
                    }
                }
                if ($source -isnot [string]) { continue }
                try {
                    $declared[[string]$attribute.Name] = (ConvertTo-TerraformProviderAddress -Provider $source).Address.ToLowerInvariant()
                }
                catch {
                    Write-Verbose "$ModuleAddress required_providers $($attribute.Name): $($_.Exception.Message)"
                }
            }
        }
    }
    , $declared
}

function Resolve-TerraformBlockProvider {
    # Not exported. LocalName, Alias and ProviderAddress for one resource or data block,
    # given its module's Get-TerraformModuleProviderMap.
    param($Block, $Declared)

    $type = [string]$Block.Labels[0]
    $attributes = $Block.Body.Attributes
    $localName = $type.Split('_')[0]
    $alias = $null
    $providerAttribute = if ($null -ne $attributes) { $attributes.PSObject.Properties['provider'] }
    if ($providerAttribute) {
        $expr = $providerAttribute.Value.Expr
        $parts = ([string]($expr.Traversal ?? $expr.Raw)).Split('.', 2)
        $localName = $parts[0]
        if ($parts.Count -gt 1) { $alias = $parts[1] }
    }

    $providerAddress = $null
    if (-not $Declared.TryGetValue($localName, [ref]$providerAddress)) {
        $providerAddress = if ($localName -eq 'terraform') {
            'terraform.io/builtin/terraform'
        }
        else {
            "registry.terraform.io/hashicorp/$localName".ToLowerInvariant()
        }
    }

    [pscustomobject]@{ LocalName = $localName; Alias = $alias; ProviderAddress = $providerAddress }
}

function ConvertTo-TerraformResourceGraph {
    <#
    .SYNOPSIS
        Builds an inventory of resources and data sources and joins it to provider schemas.

    .DESCRIPTION
        ConvertTo-TerraformResourceGraph reads the blocks Get-TerraformModuleGraph already
        parsed and returns one TerraformGraph.ResourceGraph. Every resource and data block in
        every parsed module becomes a TerraformGraph.ResourceNode with its Terraform address,
        the provider it resolves to and the schema node it should be an instance of
        (SchemaId). Nothing is parsed again.

        With -SchemaGraph, each node is joined to the schema: a node whose SchemaId is in one
        of the schema graphs gets SchemaMatched $true and one InstanceOf edge to it, and its
        top-level arguments are checked against the schema. UnknownAttributes lists
        arguments the schema does not declare, UnknownBlocks lists nested blocks it does not
        declare (a dynamic block is checked by its label), and MissingRequired lists required
        attributes and blocks with min_items of 1 or more that the block does not set. Only
        the top level of each block is checked; the contents of nested blocks are not.

        Instead of -SchemaGraph, -Provider builds the schema graphs from the local schema
        cache for the named providers, and -AutoSchema loads from the cache whatever
        providers the module graph resolves to. Neither downloads anything.

        An unmatched node has a Reason: NoSchemaGraph when no schema was given (no
        -SchemaGraph, -Provider or -AutoSchema), ProviderNotInSchemaGraph when no schema
        graph has its provider, TypeNotInProvider when the provider is there but has no
        such resource or data source type.

        Module nodes whose Blocks are $null (not parsed without -Recurse, unresolved, or
        Cycle) contribute nothing and are listed in Skipped.

    .PARAMETER ModuleGraph
        A TerraformGraph.ModuleGraph from Get-TerraformModuleGraph. Use -Recurse there to
        include every module in the tree.

    .PARAMETER SchemaGraph
        Zero or more TerraformGraph.SchemaGraph objects from ConvertTo-TerraformSchemaGraph,
        from one call or several. Their nodes are indexed by Id together, so a configuration
        that uses several providers can be checked against one graph per provider. When
        omitted, every node gets SchemaMatched $false and Reason NoSchemaGraph.

    .PARAMETER Provider
        Providers to load from the local schema cache instead of passing -SchemaGraph, as
        ConvertTo-TerraformSchemaGraph -Provider does: patterns match by shape and may use
        wildcards, and the newest cached version of each is used. A pattern with no cached
        schema is a terminating error that names Get-TerraformSchemaPack and
        Get-TerraformProviderSchema -SaveToCache.

    .PARAMETER AutoSchema
        Load the schema of every provider address the module graph resolves to from the
        local schema cache (newest cached version), and leave the rest unmatched with
        Reason ProviderNotInSchemaGraph. Reads the cache only: never downloads and never
        runs terraform.

    .PARAMETER Classify
        Overlay classifier drawers (see New-TerraformClassifier). Every ResourceNode gets
        Drawer and Subcategory from its provider's classifier by type; a type the
        classifier lacks, or a provider with no classifier (one warning; built-in
        providers are skipped silently), is in the unclassified drawer. The graph gets
        Drawers: one TerraformGraph.DrawerSummary per drawer with TypeCount (distinct
        types) and InstanceCount (blocks). Ids, nodes and edges are exactly the same as
        without -Classify. Works in every parameter set and reads local files only.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before
        $env:LOCALAPPDATA\TerraformGraph\classifiers and the classifiers bundled with the
        module. Implies -Classify.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph
        $graph.Nodes
        $graph.Providers

        Inventory with no schema: every resource and data source with its address and
        resolved provider, and how many nodes each provider has.

    .EXAMPLE
        $schema = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schema
        $graph.Nodes | Where-Object { -not $_.SchemaMatched } | Format-Table ResourceAddress, ProviderAddress, Reason

        Join with the schema of an initialized directory and list the nodes that did not
        match, with the Reason. With only the built-in provider installed, null_resource and
        local_file show ProviderNotInSchemaGraph.

    .EXAMPLE
        $schemas = @(
            Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph
            Get-TerraformProviderSchema -Provider local -Cleanup | ConvertTo-TerraformSchemaGraph
        )
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schemas
        $graph.Nodes | Where-Object { $_.UnknownAttributes -or $_.UnknownBlocks -or $_.MissingRequired } |
            Format-List ResourceAddress, UnknownAttributes, UnknownBlocks, MissingRequired

        Join with two schema graphs fetched on demand and show the nodes counted in
        Findings.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema
        $graph.Nodes | Format-Table ResourceAddress, ProviderAddress, SchemaMatched, Reason

        Join with whatever schemas the local cache holds for the providers infra uses;
        providers that are not cached show ProviderNotInSchemaGraph.

    .EXAMPLE
        $graph = Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema -Classify
        $graph.Drawers
        $graph.Nodes | Sort-Object Drawer | Format-Table Drawer, Subcategory, ResourceAddress

        How many resource types and blocks a configuration has per drawer, then every block
        with its drawer.

    .OUTPUTS
        TerraformGraph.ResourceGraph with Root, Nodes, Edges, Skipped and Providers (ordered
        ProviderAddress -> node count), plus NodeCount, EdgeCount, MatchedCount,
        UnmatchedCount and Findings (nodes with any UnknownAttributes, UnknownBlocks or
        MissingRequired). Default view is Root, NodeCount, MatchedCount, UnmatchedCount,
        Findings. With -Classify, Drawers is a TerraformGraph.DrawerSummary array and each
        node has Drawer and Subcategory. Nodes are TerraformGraph.ResourceNode (default view Kind, ResourceAddress,
        ProviderAddress, SchemaMatched, Reason), edges TerraformGraph.ResourceEdge.

    .NOTES
        Id scheme, where <module> is the ModuleAddress ('root' for the root module):
            Resource    <module>/resource/<type>.<name>
            DataSource  <module>/data/<type>.<name>
        SchemaId is <ProviderAddress>/resource/<type> or <ProviderAddress>/data/<type>, the
        ConvertTo-TerraformSchemaGraph Id, and is set even when it does not match.

        Provider resolution, per module: the local name is the type up to its first
        underscore (aws_instance -> aws), or the part of a provider = <name>.<alias>
        argument before the dot, which also sets ProviderAlias. The local name maps to an
        address through that module's own terraform { required_providers } sources. A
        local name not declared there is terraform.io/builtin/terraform for 'terraform',
        otherwise registry.terraform.io/hashicorp/<name>. A child module does not inherit
        its parent's required_providers, as in Terraform.

        Only top-level attributes and blocks are checked. The meta-arguments count,
        for_each, provider, depends_on, lifecycle, connection and provisioner are never
        unknown, and lifecycle, connection and provisioner blocks are not checked.

    .LINK
        Get-TerraformModuleGraph

    .LINK
        ConvertTo-TerraformSchemaGraph

    .LINK
        Get-TerraformSchemaCache

    .LINK
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding(DefaultParameterSetName = 'SchemaGraph')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $ModuleGraph,

        [Parameter(ParameterSetName = 'SchemaGraph')]
        [object[]]
        $SchemaGraph,

        [Parameter(Mandatory, ParameterSetName = 'Provider')]
        [ValidateScript({
            if (-not [WildcardPattern]::ContainsWildcardCharacters($_)) {
                $null = ConvertTo-TerraformProviderAddress -Provider $_
            }
            $true
        })]
        [string[]]
        $Provider,

        [Parameter(Mandatory, ParameterSetName = 'AutoSchema')]
        [switch]
        $AutoSchema,

        [switch]
        $Classify,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    begin {
        $classifyGraph = $Classify -or $PSBoundParameters.ContainsKey('ClassifierPath')
        # Address -> cached schema version for -Provider and -AutoSchema, so -Classify
        # prefers the classifier generated from the same version.
        $schemaVersions = @{}
        $metaAttributes = 'count', 'for_each', 'provider', 'depends_on', 'lifecycle', 'connection', 'provisioner'
        $metaBlocks = 'lifecycle', 'connection', 'provisioner', 'dynamic'

        # Every schema node by Id, the provider addresses present, and the direct children
        # of each Resource and DataSource node in schema order. Built once for all input;
        # -AutoSchema adds to it as module graphs name new providers.
        $schemaById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $schemaProviders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $schemaChildren = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::Ordinal)
        $addSchemaGraph = {
            param($Graph)
            foreach ($node in @($Graph.Nodes)) {
                $schemaById[[string]$node.Id] = $node
                if ($node.Kind -eq 'Provider') { $null = $schemaProviders.Add([string]$node.Id) }
                $parent = $null
                if ($null -ne $node.ParentId -and $schemaById.TryGetValue([string]$node.ParentId, [ref]$parent) -and
                    $parent.Kind -in 'Resource', 'DataSource') {
                    if (-not $schemaChildren.ContainsKey($parent.Id)) {
                        $schemaChildren[$parent.Id] = [System.Collections.Generic.List[object]]::new()
                    }
                    $schemaChildren[$parent.Id].Add($node)
                }
            }
        }

        switch ($PSCmdlet.ParameterSetName) {
            'SchemaGraph' {
                $hasSchema = @($SchemaGraph | Where-Object { $null -ne $_ }).Count -gt 0
                foreach ($graph in @($SchemaGraph)) {
                    if ($null -ne $graph) { & $addSchemaGraph $graph }
                }
            }
            'Provider' {
                $hasSchema = $true
                try {
                    $cached = @(Resolve-TerraformSchemaCacheProvider -Name $Provider)
                }
                catch {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
                        'SchemaNotCached',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Provider))
                }
                foreach ($item in $cached) { $schemaVersions[$item.ProviderAddress] = $item.Version }
                & $addSchemaGraph (ConvertTo-TerraformSchemaGraph -Schema (Get-TerraformSchemaCacheDocument -Entry $cached) -ErrorAction Stop)
            }
            'AutoSchema' {
                # Every provider counts as looked up, so an uncached one is ProviderNotInSchemaGraph.
                $hasSchema = $true
                $autoTried = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
    }

    process {
        $nodes = [System.Collections.Generic.List[object]]::new()
        $edges = [System.Collections.Generic.List[object]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $providers = [ordered]@{}

        if ($AutoSchema) {
            # Provider addresses this module graph resolves to, then the newest cached schema
            # of each one not looked up yet. Cache reads only; nothing is downloaded.
            $needed = [System.Collections.Generic.List[string]]::new()
            foreach ($module in @($ModuleGraph.Nodes)) {
                if ($null -eq $module.Blocks) { continue }
                $blocks = @($module.Blocks)
                $declared = Get-TerraformModuleProviderMap -Blocks $blocks -ModuleAddress ([string]$module.ModuleAddress)
                foreach ($block in $blocks) {
                    if ($block.Type -notin 'resource', 'data') { continue }
                    $providerAddress = (Resolve-TerraformBlockProvider -Block $block -Declared $declared).ProviderAddress
                    if ($autoTried.Add($providerAddress)) { $needed.Add($providerAddress) }
                }
            }
            if ($needed.Count) {
                $entries = @(Get-TerraformSchemaCacheEntry)
                $found = foreach ($providerAddress in $needed) {
                    $entry = $entries | Where-Object ProviderAddress -eq $providerAddress | Select-Object -First 1
                    if ($entry) { $entry } else { Write-Verbose "No cached schema for $providerAddress" }
                }
                if ($found) {
                    Write-Verbose "Loading cached schemas: $(@($found | ForEach-Object { "$($_.ProviderAddress) $($_.Version)" }) -join ', ')"
                    foreach ($item in @($found)) { $schemaVersions[$item.ProviderAddress] = $item.Version }
                    & $addSchemaGraph (ConvertTo-TerraformSchemaGraph -Schema (Get-TerraformSchemaCacheDocument -Entry @($found)) -ErrorAction Stop)
                }
            }
        }

        foreach ($module in @($ModuleGraph.Nodes)) {
            $address = [string]$module.ModuleAddress
            if ($null -eq $module.Blocks) {
                $skipped.Add($address)
                continue
            }
            $blocks = @($module.Blocks)

            # Local name -> provider address from this module's own required_providers.
            $declared = Get-TerraformModuleProviderMap -Blocks $blocks -ModuleAddress $address

            # Resource and data blocks in source order: file, then line.
            $sorted = [System.Collections.Generic.List[object]]::new()
            foreach ($block in $blocks) { if ($block.Type -in 'resource', 'data') { $sorted.Add($block) } }
            $sorted.Sort([System.Comparison[object]] {
                    param($a, $b)
                    $byFile = [string]::CompareOrdinal([string]$a.File, [string]$b.File)
                    if ($byFile) { return $byFile }
                    ([int]$a.Line).CompareTo([int]$b.Line)
                })

            foreach ($block in $sorted) {
                $isData = $block.Type -eq 'data'
                $kind = $isData ? 'DataSource' : 'Resource'
                $segment = $isData ? 'data' : 'resource'
                $type = [string]$block.Labels[0]
                $name = [string]$block.Labels[1]
                $attributes = $block.Body.Attributes

                $resolved = Resolve-TerraformBlockProvider -Block $block -Declared $declared
                $localName = $resolved.LocalName
                $alias = $resolved.Alias
                $providerAddress = $resolved.ProviderAddress
                $providers[$providerAddress] = 1 + [int]$providers[$providerAddress]

                $id = "$address/$segment/$type.$name"
                $schemaId = "$providerAddress/$segment/$type"
                $terraformAddress = ($isData ? 'data.' : '') + "$type.$name"
                if ($address -ne 'root') { $terraformAddress = "$address.$terraformAddress" }

                $reason = if (-not $hasSchema) { 'NoSchemaGraph' }
                elseif (-not $schemaProviders.Contains($providerAddress)) { 'ProviderNotInSchemaGraph' }
                elseif (-not $schemaById.ContainsKey($schemaId)) { 'TypeNotInProvider' }
                $matched = $null -eq $reason

                $unknownAttributes = [System.Collections.Generic.List[string]]::new()
                $unknownBlocks = [System.Collections.Generic.List[string]]::new()
                $missingRequired = [System.Collections.Generic.List[string]]::new()
                if ($matched) {
                    $children = $null
                    if (-not $schemaChildren.TryGetValue($schemaId, [ref]$children)) { $children = @() }
                    $childByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
                    foreach ($child in $children) { $childByName[[string]$child.Name] = $child }

                    # Attributes in source order (the parser keys them by name).
                    $setAttributes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    if ($null -ne $attributes) {
                        foreach ($attribute in @($attributes.PSObject.Properties.Value) | Sort-Object { $_.SrcRange.Start.Byte }) {
                            $attributeName = [string]$attribute.Name
                            $null = $setAttributes.Add($attributeName)
                            if ($metaAttributes -ccontains $attributeName) { continue }
                            $child = $null
                            if (-not ($childByName.TryGetValue($attributeName, [ref]$child) -and $child.Kind -eq 'Attribute')) {
                                $unknownAttributes.Add($attributeName)
                            }
                        }
                    }

                    # A dynamic "x" block stands for an x block.
                    $setBlocks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    foreach ($nested in @($block.Body.Blocks)) {
                        if ($null -eq $nested) { continue }
                        $blockName = [string]$nested.Type
                        if ($blockName -ceq 'dynamic') { $blockName = [string]$nested.Labels[0] }
                        elseif ($metaBlocks -ccontains $blockName) { continue }
                        $null = $setBlocks.Add($blockName)
                        $child = $null
                        $known = $childByName.TryGetValue($blockName, [ref]$child) -and (
                            $child.Kind -eq 'Block' -or
                            ($child.Kind -eq 'Attribute' -and $null -ne (Get-TerraformSchemaMember -InputObject $child.Raw -Name 'nested_type')))
                        if (-not $known -and -not $unknownBlocks.Contains($blockName)) { $unknownBlocks.Add($blockName) }
                    }

                    foreach ($child in $children) {
                        $childName = [string]$child.Name
                        if ($child.Kind -eq 'Attribute' -and $child.Required -and -not $setAttributes.Contains($childName)) {
                            $missingRequired.Add($childName)
                        }
                        elseif ($child.Kind -eq 'Block' -and [int]$child.MinItems -ge 1 -and -not $setBlocks.Contains($childName)) {
                            $missingRequired.Add($childName)
                        }
                    }

                    $edges.Add([pscustomobject]@{
                        PSTypeName = 'TerraformGraph.ResourceEdge'
                        From       = $id
                        To         = $schemaId
                        Kind       = 'InstanceOf'
                    })
                }

                $nodes.Add([pscustomobject]@{
                    PSTypeName        = 'TerraformGraph.ResourceNode'
                    Id                = $id
                    Kind              = $kind
                    Module            = $address
                    Type              = $type
                    Name              = $name
                    ResourceAddress   = $terraformAddress
                    ProviderLocalName = $localName
                    ProviderAlias     = $alias
                    ProviderAddress   = $providerAddress
                    SchemaId          = $schemaId
                    SchemaMatched     = $matched
                    Reason            = $reason
                    UnknownAttributes = $unknownAttributes.ToArray()
                    UnknownBlocks     = $unknownBlocks.ToArray()
                    MissingRequired   = $missingRequired.ToArray()
                    File              = $block.File
                    Line              = $block.Line
                    Block             = $block
                })
            }
        }

        $result = [pscustomobject]@{
            PSTypeName = 'TerraformGraph.ResourceGraph'
            Root       = $ModuleGraph.Root
            Nodes      = $nodes.ToArray()
            Edges      = $edges.ToArray()
            Skipped    = $skipped.ToArray()
            Providers  = $providers
        }
        if ($classifyGraph) {
            Add-TerraformResourceGraphClassification -Graph $result -Version $schemaVersions -ClassifierPath $ClassifierPath
        }
        $result
    }
}

# Provider registry cache. The user file wins over the bundled one; tests point these at
# fixtures with InModuleScope. Nothing below touches the network except
# Update-TerraformRegistryCache.
$script:TerraformRegistrySource = 'registry.terraform.io'
$script:TerraformRegistryBundledPath = Join-Path $PSScriptRoot 'data' 'registry.json'
$script:TerraformRegistryUserCachePath = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'registry.json'
$script:TerraformRegistryCacheMemo = $null
$script:TerraformRegistryTierRank = @{ official = 0; partner = 1; community = 2 }

Update-TypeData -TypeName 'TerraformGraph.RegistryProvider' -DefaultDisplayPropertySet ProviderAddress, Tier, Latest, VersionCount -Force
Update-TypeData -TypeName 'TerraformGraph.RegistryCache' -DefaultDisplayPropertySet Path, HarvestedOn, Scope, ProviderCount, VersionCount, Elapsed -Force

function Get-TerraformRegistryCache {
    # Not exported. The user cache if present, else the bundled file (unless
    # -NoBundledData), else $null. Parsed once per file version and kept in memory, so
    # argument completers stay fast after the first Tab.
    param([switch]$NoBundledData)

    $paths = @($script:TerraformRegistryUserCachePath)
    if (-not $NoBundledData) { $paths += $script:TerraformRegistryBundledPath }
    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $path
        $key = "$($item.FullName)|$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
        if ($script:TerraformRegistryCacheMemo -and $script:TerraformRegistryCacheMemo.Key -ceq $key) {
            return $script:TerraformRegistryCacheMemo.Value
        }

        $cache = Read-TerraformRegistryCacheFile -Path $item.FullName
        $script:TerraformRegistryCacheMemo = @{ Key = $key; Value = $cache }
        return $cache
    }
    $null
}

function Read-TerraformRegistryCacheFile {
    # Not exported. One registry.json as the object Get-TerraformRegistryCache returns, not
    # memoized: Path, HarvestedOn, Scope, Source, Providers (TerraformGraph.RegistryProvider).
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    $document = [TerraformGraph.Json]::Deserialize([System.IO.File]::ReadAllText($item.FullName), 1024, $false)
    $providers = foreach ($entry in @($document.providers)) {
        $versions = @($entry.versions)
        [pscustomobject]@{
            PSTypeName      = 'TerraformGraph.RegistryProvider'
            ProviderAddress = [string]$entry.address
            Source          = "$($entry.namespace)/$($entry.name)"
            Namespace       = [string]$entry.namespace
            Name            = [string]$entry.name
            Tier            = [string]$entry.tier
            Description     = [string]$entry.description
            Latest          = $entry.latest
            VersionCount    = $versions.Count
            Versions        = $versions
        }
    }
    [pscustomobject]@{
        Path        = $item.FullName
        HarvestedOn = [string]$document.harvestedOn
        Scope       = [string]$document.scope
        Source      = [string]$document.source
        Providers   = @($providers)
    }
}

function Select-TerraformRegistryProvider {
    # Not exported. Providers matching any -Name pattern (all when none): a pattern with
    # two slashes matches ProviderAddress, one slash namespace/name, none the bare name in
    # any namespace. -like, so wildcards work and case is ignored. -ByTier sorts official
    # first, then by namespace/name; otherwise cache order (by address).
    param($Cache, [string[]]$Name, [string[]]$Tier, [switch]$ByTier)

    $selected = foreach ($provider in $Cache.Providers) {
        if ($Tier -and $Tier -notcontains $provider.Tier) { continue }
        if (-not $Name) { $provider; continue }
        foreach ($pattern in $Name) {
            $value = switch ($pattern.Split('/').Count) {
                1       { $provider.Name }
                2       { $provider.Source }
                default { $provider.ProviderAddress }
            }
            if ($value -like $pattern) { $provider; break }
        }
    }
    if (-not $ByTier) { return $selected }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($provider in $selected) { $list.Add($provider) }
    $rank = $script:TerraformRegistryTierRank
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            $byTier = ($rank[$a.Tier] ?? 9).CompareTo(($rank[$b.Tier] ?? 9))
            if ($byTier) { return $byTier }
            [string]::CompareOrdinal($a.Source.ToLowerInvariant(), $b.Source.ToLowerInvariant())
        })
    $list.ToArray()
}

function Resolve-TerraformRegistryProvider {
    # Not exported. Exactly one cached provider for -Name, or a throw whose message lists
    # every match. Callers turn the throw into their own terminating error.
    param([string]$Name, [switch]$NoBundledData)

    $cache = Get-TerraformRegistryCache -NoBundledData:$NoBundledData
    if (-not $cache) {
        throw "'$Name' matches no provider: there is no registry cache. Run Update-TerraformRegistryCache or pass a full address."
    }
    $found = @(Select-TerraformRegistryProvider -Cache $cache -Name $Name -ByTier)
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -eq 0) {
        $date = if ($cache.HarvestedOn.Length -ge 10) { $cache.HarvestedOn.Substring(0, 10) } else { $cache.HarvestedOn }
        throw "'$Name' matches no provider in the registry cache (harvested $date). Run Update-TerraformRegistryCache or pass a full address."
    }
    throw "'$Name' matches $($found.Count) providers: $(@($found.Source) -join ', '). Specify one."
}

function Invoke-TerraformRegistryRequest {
    # Not exported. GET one registry URL and parse it with TerraformGraph.Json, which keeps
    # date strings as strings (Invoke-RestMethod would turn them into DateTime). 429 and 5xx
    # are retried up to five times: a 5xx after 2, 4, 8, 16 and 32 s; a 429 after its
    # Retry-After, else after 30, 60, 120, 240 and 300 s (about 12 minutes in all). The
    # registry sits behind an AWS WAF rate-based rule (429, x-amzn-waf-reason: rate-limit, no
    # Retry-After) that blocks an address for minutes once a sustained run passes its limit:
    # the first bundle harvest (2026-10-07) hit it right after aws's 2,700 pages, and the old
    # two retries at 1 s and 2 s failed every provider after that within seconds. Also defined
    # inside the ForEach-Object -Parallel runspaces of Update-TerraformRegistryCache and the
    # docs harvest, from this text, so keep it self-contained.
    param([string]$Uri)
    for ($attempt = 0; ; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 60 -ErrorAction Stop
            # application/vnd.api+json (v2) comes back as bytes, application/json (v1) as text.
            $content = $response.Content
            if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
            return [TerraformGraph.Json]::Deserialize([string]$content, 1024, $false)
        }
        catch {
            $failed = $_.Exception.Response
            $status = [int]$failed.StatusCode
            if ($attempt -ge 5 -or ($status -ne 429 -and $status -lt 500)) { throw }
            $delay = if ($status -eq 429) { @(30, 60, 120, 240, 300)[$attempt] } else { [math]::Pow(2, $attempt + 1) }
            $retryAfter = if ($failed -is [System.Net.Http.HttpResponseMessage]) { $failed.Headers.RetryAfter } else { $null }
            if ($retryAfter -and $retryAfter.Delta) { $delay = $retryAfter.Delta.TotalSeconds }
            elseif ($retryAfter -and $retryAfter.Date) { $delay = ($retryAfter.Date - [System.DateTimeOffset]::UtcNow).TotalSeconds }
            Start-Sleep -Milliseconds ([int](1000 * [math]::Min(300, [math]::Max(1, $delay))))
        }
    }
}

function Get-TerraformRegistryHarvest {
    # Not exported. Lists providers and fetches every provider's versions from the public
    # registry. Probed 2026-10-06:
    #
    #   List: GET https://registry.terraform.io/v2/providers?filter[tier]=official,partner&page[size]=100&page[number]=N
    #     page[size] is capped at 100; meta.pagination has total-pages, total-count,
    #     next-page (null on the last page). Without filter[tier] it lists every tier
    #     (7418 providers on 2026-10-06; official,partner 428). Tier is attributes.tier:
    #     official | partner | community. One data[] element:
    #       { "type": "providers", "id": "5246",
    #         "attributes": { "alias": null, "description": "Management of Ansible ...",
    #           "downloads": 573672, "featured": false, "full-name": "ansible/aap",
    #           "logo-url": "/images/providers/hashicorp.svg", "name": "aap",
    #           "namespace": "ansible", "owner-name": "", "repository-id": 702581735,
    #           "robots-noindex": false, "source": "https://github.com/ansible/terraform-provider-aap",
    #           "tier": "official", "unlisted": false, "warning": "" },
    #         "links": { "self": "/v2/providers/5246" } }
    #     (v1 /v1/providers?limit=&offset= also pages and carries tier, but lists one row
    #     per provider version, so v2 is used.)
    #
    #   Versions, two calls per provider because neither has every field:
    #   GET https://registry.terraform.io/v1/providers/<namespace>/<name>/versions
    #     protocols, no publish date. One versions[] element:
    #       { "version": "1.0.0", "protocols": [ "4" ], "platforms": [ { "os": "linux", "arch": "386" }, ... ] }
    #   GET https://registry.terraform.io/v2/providers/<namespace>/<name>?include=provider-versions
    #     publish date, no protocols; included[] is complete (509 for hashicorp/aws). One element:
    #       { "type": "provider-versions", "id": "2672",
    #         "attributes": { "description": "terraform-provider-null", "downloads": 394605,
    #           "published-at": "2019-04-11T23:12:14Z", "tag": "v2.1.1", "version": "2.1.1" },
    #         "links": { "self": "/v2/provider-versions/2672" } }
    param(
        [ValidateSet('OfficialPartner', 'All')]
        [string]
        $Scope,

        [int]
        $ThrottleLimit
    )

    $registry = "https://$($script:TerraformRegistrySource)"
    $filter = if ($Scope -eq 'OfficialPartner') { '&filter[tier]=official,partner' } else { '' }

    $listed = [System.Collections.Generic.List[object]]::new()
    $page = 1
    while ($page) {
        $response = Invoke-TerraformRegistryRequest -Uri "$registry/v2/providers?page[size]=100&page[number]=$page$filter"
        $pagination = $response.meta.pagination
        $total = [int]$pagination.'total-pages'
        Write-Progress -Id 1 -Activity 'Listing registry providers' -Status "Page $page of $total" -PercentComplete ([math]::Min(100, 100 * $page / [math]::Max(1, $total)))
        foreach ($item in @($response.data)) {
            $attributes = $item.attributes
            $listed.Add([pscustomobject]@{
                Namespace   = [string]$attributes.namespace
                Name        = [string]$attributes.name
                Tier        = [string]$attributes.tier
                Description = [string]$attributes.description
            })
        }
        $page = $pagination.'next-page'
    }
    Write-Progress -Id 1 -Activity 'Listing registry providers' -Completed
    Write-Verbose "Listed $($listed.Count) providers"

    $requestDefinition = ${function:Invoke-TerraformRegistryRequest}.ToString()
    $done = 0
    $fetched = $listed | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        Set-Item -Path function:Invoke-TerraformRegistryRequest -Value $using:requestDefinition
        $provider = $_
        $base = "$($using:registry)"
        try {
            $v1 = Invoke-TerraformRegistryRequest -Uri "$base/v1/providers/$($provider.Namespace)/$($provider.Name)/versions"
            $v2 = Invoke-TerraformRegistryRequest -Uri "$base/v2/providers/$($provider.Namespace)/$($provider.Name)?include=provider-versions"
            $published = @{}
            foreach ($included in @($v2.included)) {
                if ($included.type -eq 'provider-versions') { $published[[string]$included.attributes.version] = $included.attributes.'published-at' }
            }
            $versions = foreach ($version in @($v1.versions)) {
                [pscustomobject]@{
                    Version   = [string]$version.version
                    Protocols = [string[]]@($version.protocols)
                    Published = $published[[string]$version.version]
                }
            }
            [pscustomobject]@{ Provider = $provider; Versions = @($versions); Error = $null }
        }
        catch {
            [pscustomobject]@{ Provider = $provider; Versions = $null; Error = $_.Exception.Message }
        }
    } | ForEach-Object {
        $done++
        Write-Progress -Id 1 -Activity 'Fetching provider versions' -Status "$done of $($listed.Count)" -PercentComplete (100 * $done / [math]::Max(1, $listed.Count))
        $_
    }
    Write-Progress -Id 1 -Activity 'Fetching provider versions' -Completed

    $failed = @($fetched | Where-Object Error)
    if ($failed.Count) {
        $names = @($failed | Select-Object -First 10 | ForEach-Object { "$($_.Provider.Namespace)/$($_.Provider.Name) ($($_.Error))" })
        throw "Failed to fetch versions for $($failed.Count) providers: $($names -join '; ')$(if ($failed.Count -gt 10) { '; ...' }). The cache was not written."
    }

    $fetched
}

function Sort-TerraformRegistryVersion {
    # Not exported. Version records newest first by semantic version; strings that do not
    # parse sort after every parsed version, ordinal descending.
    param([object[]]$Versions)

    $keyed = foreach ($version in $Versions) {
        $semver = $null
        $null = [System.Management.Automation.SemanticVersion]::TryParse([string]$version.Version, [ref]$semver)
        [pscustomobject]@{ Semver = $semver; Record = $version }
    }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $keyed) { $list.Add($entry) }
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            if ($a.Semver -and $b.Semver) { return $b.Semver.CompareTo($a.Semver) }
            if ($a.Semver) { return -1 }
            if ($b.Semver) { return 1 }
            [string]::CompareOrdinal([string]$b.Record.Version, [string]$a.Record.Version)
        })
    foreach ($entry in $list) {
        [pscustomobject]@{
            Record     = $entry.Record
            PreRelease = if ($entry.Semver) { [bool]$entry.Semver.PreReleaseLabel } else { ([string]$entry.Record.Version).Contains('-') }
        }
    }
}

function Update-TerraformRegistryCache {
    <#
    .SYNOPSIS
        Downloads the list of Terraform providers and their versions into the registry cache.

    .DESCRIPTION
        Update-TerraformRegistryCache lists providers from the public registry
        (registry.terraform.io, v2 API, 100 per page), then fetches every provider's
        versions with ForEach-Object -Parallel: the v1 versions endpoint for protocols and
        the v2 provider-versions include for publish dates, two calls per provider. Calls
        that return 5xx are retried five times with a short backoff, and a 429 (the registry's rate limit) for up to about 12 minutes. If any provider still
        fails, nothing is written.

        The file is written atomically: a temporary file in the same folder, then Move-Item.
        Providers are sorted by address; versions newest first, pre-releases included. Each
        provider's latest is its newest version that is not a pre-release.

        This is the only TerraformGraph command that reads the registry list over the
        network. Get-TerraformRegistryProvider, the -Provider wildcards of
        Get-TerraformProviderSchema and the argument completers only read the cache.

    .PARAMETER Scope
        OfficialPartner (default): official and partner providers. All: every tier,
        including community, which is many times larger and slower.

    .PARAMETER Path
        Cache file to write. Defaults to the user cache,
        $env:LOCALAPPDATA\TerraformGraph\registry.json, which takes precedence over the
        bundled copy.

    .PARAMETER ThrottleLimit
        Concurrent provider requests. Default 6.

    .PARAMETER PassThru
        Return a TerraformGraph.RegistryCache summary.

    .EXAMPLE
        Update-TerraformRegistryCache -Verbose

        Refresh the user cache with official and partner providers.

    .EXAMPLE
        Update-TerraformRegistryCache -Scope All -Path .\registry-all.json -PassThru

        Harvest every tier into a separate file and show the counts.

    .OUTPUTS
        None, or TerraformGraph.RegistryCache with -PassThru: Path, HarvestedOn, Scope,
        ProviderCount, VersionCount, Elapsed.

    .LINK
        Get-TerraformRegistryProvider
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('OfficialPartner', 'All')]
        [string]
        $Scope = 'OfficialPartner',

        [string]
        $Path = $script:TerraformRegistryUserCachePath,

        [ValidateRange(1, 64)]
        [int]
        $ThrottleLimit = 6,

        [switch]
        $PassThru
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $fetched = Get-TerraformRegistryHarvest -Scope $Scope -ThrottleLimit $ThrottleLimit
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($_.Exception.Message, $_.Exception),
            'RegistryHarvestFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $script:TerraformRegistrySource))
    }

    $versionCount = 0
    $providers = foreach ($entry in $fetched) {
        $provider = $entry.Provider
        $sorted = @(Sort-TerraformRegistryVersion -Versions $entry.Versions)
        $versionCount += $sorted.Count
        $latest = $sorted | Where-Object { -not $_.PreRelease } | Select-Object -First 1
        [ordered]@{
            address     = "$($script:TerraformRegistrySource)/$($provider.Namespace)/$($provider.Name)".ToLowerInvariant()
            namespace   = $provider.Namespace
            name        = $provider.Name
            tier        = $provider.Tier
            description = $provider.Description
            latest      = if ($latest) { $latest.Record.Version } else { $null }
            versions    = [object[]]@(foreach ($version in $sorted) {
                    [ordered]@{
                        version   = $version.Record.Version
                        protocols = [object[]]@($version.Record.Protocols)
                        published = $version.Record.Published
                    }
                })
        }
    }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($provider in $providers) { $list.Add($provider) }
    $list.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.address, $b.address) })

    $harvestedOn = [datetime]::UtcNow
    $document = [ordered]@{
        harvestedOn = $harvestedOn.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        scope       = if ($Scope -eq 'OfficialPartner') { 'official,partner' } else { 'all' }
        source      = $script:TerraformRegistrySource
        providers   = $list.ToArray()
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path, (Get-Location -PSProvider FileSystem).ProviderPath)
    $directory = Split-Path -Path $fullPath -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporary = Join-Path $directory ".registry.$([guid]::NewGuid().ToString('n')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, [TerraformGraph.Json]::Serialize($document, 1024, $false) + "`n")
        Move-Item -LiteralPath $temporary -Destination $fullPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    $stopwatch.Stop()
    Write-Verbose "Wrote $($list.Count) providers and $versionCount versions to $fullPath in $($stopwatch.Elapsed)"

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName    = 'TerraformGraph.RegistryCache'
            Path          = $fullPath
            HarvestedOn   = $harvestedOn
            Scope         = $document.scope
            ProviderCount = $list.Count
            VersionCount  = $versionCount
            Elapsed       = $stopwatch.Elapsed
        }
    }
}

function Get-TerraformRegistryProvider {
    <#
    .SYNOPSIS
        Lists Terraform providers and their versions from the registry cache.

    .DESCRIPTION
        Get-TerraformRegistryProvider reads the provider registry cache, never the network.
        The cache is the user file ($env:LOCALAPPDATA\TerraformGraph\registry.json, written
        by Update-TerraformRegistryCache) when present, else the copy bundled with the
        module. With no cache it writes one warning naming Update-TerraformRegistryCache
        and returns nothing.

        -Name patterns allow wildcards and match by shape: 'aws' or 'aws*' matches the bare
        name in any namespace, 'hashicorp/aws*' matches namespace/name, and
        'registry.terraform.io/hashicorp/aws' matches the full address. Case is ignored.

    .PARAMETER Name
        One or more name patterns. Default: every provider.

    .PARAMETER Tier
        Only these tiers: official, partner, community.

    .PARAMETER NoBundledData
        Ignore the bundled cache; read only the user cache.

    .EXAMPLE
        Get-TerraformRegistryProvider aws*

        Every cached provider whose name starts with aws, in any namespace.

    .EXAMPLE
        Get-TerraformRegistryProvider -Tier partner -Name 'datadog/*'

        Partner providers in the datadog namespace.

    .EXAMPLE
        (Get-TerraformRegistryProvider hashicorp/aws).Versions | Select-Object -First 5

        The five newest hashicorp/aws versions with protocols and publish dates.

    .OUTPUTS
        TerraformGraph.RegistryProvider: ProviderAddress, Source (namespace/name), Namespace,
        Name, Tier, Description, Latest, VersionCount, Versions (newest first: Version,
        Protocols, Published). Default view is ProviderAddress, Tier, Latest, VersionCount.

    .LINK
        Update-TerraformRegistryCache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Name,

        [ValidateSet('official', 'partner', 'community')]
        [string[]]
        $Tier,

        [switch]
        $NoBundledData
    )

    $cache = Get-TerraformRegistryCache -NoBundledData:$NoBundledData
    if (-not $cache) {
        Write-Warning 'No provider registry cache found. Run Update-TerraformRegistryCache to create one.'
        return
    }
    Select-TerraformRegistryProvider -Cache $cache -Name $Name -Tier $Tier
}

# Argument completers read the cache only and never throw.
$script:TerraformRegistryProviderCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        $cache = Get-TerraformRegistryCache -NoBundledData:([bool]$fakeBoundParameters['NoBundledData'])
        if (-not $cache) { return }
        $word = ([string]$wordToComplete).Trim('''', '"')
        $pattern = "$([WildcardPattern]::Escape($word))*"
        foreach ($provider in Select-TerraformRegistryProvider -Cache $cache -ByTier) {
            if ($provider.Name -like $pattern -or $provider.Source -like $pattern -or $provider.ProviderAddress -like $pattern) {
                [System.Management.Automation.CompletionResult]::new($provider.Source, $provider.Source, 'ParameterValue',
                    "$($provider.ProviderAddress) ($($provider.Tier), latest $($provider.Latest))")
            }
        }
    }
    catch { }
}

$script:TerraformRegistryVersionCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        $name = [string]$fakeBoundParameters['Provider']
        if (-not $name) { return }
        $cache = Get-TerraformRegistryCache -NoBundledData:([bool]$fakeBoundParameters['NoBundledData'])
        if (-not $cache) { return }
        $provider = if ([WildcardPattern]::ContainsWildcardCharacters($name)) {
            $found = @(Select-TerraformRegistryProvider -Cache $cache -Name $name)
            if ($found.Count -eq 1) { $found[0] }
        }
        else {
            $address = (ConvertTo-TerraformProviderAddress -Provider $name).Address
            $cache.Providers | Where-Object ProviderAddress -eq $address | Select-Object -First 1
        }
        if (-not $provider) { return }
        $word = ([string]$wordToComplete).Trim('''', '"')
        foreach ($version in $provider.Versions) {
            if ([string]$version.version -like "$([WildcardPattern]::Escape($word))*") {
                [System.Management.Automation.CompletionResult]::new($version.version, $version.version, 'ParameterValue',
                    "$($version.version) (published $($version.published))")
            }
        }
    }
    catch { }
}

Register-ArgumentCompleter -CommandName Get-TerraformProviderSchema -ParameterName Provider -ScriptBlock $script:TerraformRegistryProviderCompleter
Register-ArgumentCompleter -CommandName Get-TerraformProviderSchema -ParameterName Version -ScriptBlock $script:TerraformRegistryVersionCompleter
Register-ArgumentCompleter -CommandName Get-TerraformRegistryProvider -ParameterName Name -ScriptBlock $script:TerraformRegistryProviderCompleter

# Provider schema and docs caches: one gzipped document per provider version, at
# <root>\<address-slug>\<version>.json.gz, where address-slug is the lowercase address with
# '/' -> '-'. The schema root is ...\schemas, the docs root ...\docs; the helpers below take
# -Kind Schema|Docs to pick one. Nothing is bundled. Get-TerraformSchemaPack,
# Get-TerraformDocPack, Get-TerraformProviderSchema -SaveToCache and
# Update-TerraformProviderDocCache write them; everything else only reads them. Tests repoint
# both roots with InModuleScope. Save-TerraformSchemaPackFile is the only pack network call.
$script:TerraformSchemaCacheRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'schemas'
$script:TerraformDocCacheRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'docs'
$script:TerraformSchemaPackSource = 'https://github.com/JerryBalmer1/TerraformGraph/releases/latest/download'

Update-TypeData -TypeName 'TerraformGraph.SchemaPack' -DefaultDisplayPropertySet ProviderAddress, Version, Status, Bytes -Force
Update-TypeData -TypeName 'TerraformGraph.DocPack' -DefaultDisplayPropertySet ProviderAddress, Version, Status, Bytes -Force
Update-TypeData -TypeName 'TerraformGraph.CachedSchema' -DefaultDisplayPropertySet ProviderAddress, Version, Bytes, CachedOn -Force
Update-TypeData -TypeName 'TerraformGraph.CachedDoc' -DefaultDisplayPropertySet ProviderAddress, Version, DocCount, UnmatchedCount, Bytes -Force

function Get-TerraformSchemaCachePath {
    # Not exported. Cache file for one provider version under the -Kind root. The address is
    # normalized with ConvertTo-TerraformProviderAddress and lowercased, as terraform keys
    # provider_schemas.
    param([string]$Provider, [string]$Version, [ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+_-]*$') {
        throw "Version '$Version' is not a provider version such as 3.2.3."
    }
    $slug = (ConvertTo-TerraformProviderAddress -Provider $Provider).Address.ToLowerInvariant().Replace('/', '-')
    $root = if ($Kind -eq 'Docs') { $script:TerraformDocCacheRoot } else { $script:TerraformSchemaCacheRoot }
    Join-Path $root $slug "$Version.json.gz"
}

function Write-TerraformSchemaCache {
    # Not exported. Writes a document (dictionary, PSCustomObject or JSON text) for one
    # provider version as compact gzipped JSON, atomically: a temporary file in the same
    # folder, then Move-Item. Returns the path. -Kind Schema: other providers in the schema
    # document are dropped. -Kind Docs: the docs document is written as given.
    param([string]$Provider, [string]$Version, $Document, [ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    $address = (ConvertTo-TerraformProviderAddress -Provider $Provider).Address
    $path = Get-TerraformSchemaCachePath -Provider $address -Version $Version -Kind $Kind
    if ($Document -is [string]) { $Document = [TerraformGraph.Json]::Deserialize($Document, 1024, $true) }

    if ($Kind -eq 'Schema') {
        $schemas = Get-TerraformSchemaMember -InputObject $Document -Name 'provider_schemas'
        $keys = @(Get-TerraformSchemaKeys -InputObject $schemas)
        $key = $keys | Where-Object { $_ -eq $address } | Select-Object -First 1
        if (-not $key) {
            throw "The schema document has no provider_schemas entry for $address."
        }
        if ($keys.Count -gt 1) {
            $Document = [ordered]@{
                format_version   = Get-TerraformSchemaMember -InputObject $Document -Name 'format_version'
                provider_schemas = [ordered]@{ $key = Get-TerraformSchemaMember -InputObject $schemas -Name $key }
            }
        }
    }

    $directory = Split-Path -Path $path -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporary = Join-Path $directory ".$([guid]::NewGuid().ToString('n')).tmp"
    try {
        $file = [System.IO.File]::Create($temporary)
        try {
            $gzip = [System.IO.Compression.GZipStream]::new($file, [System.IO.Compression.CompressionLevel]::Optimal)
            $writer = [System.IO.StreamWriter]::new($gzip, [System.Text.UTF8Encoding]::new($false))
            $writer.Write([TerraformGraph.Json]::Serialize($Document, 1024, $true))
            $writer.Dispose()
        }
        finally {
            $file.Dispose()
        }
        Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    $path
}

function Read-TerraformSchemaCacheText {
    # Not exported. Decompressed text of a cache file; with -MaxChars, only that many
    # characters from the start.
    param([string]$Path, [int]$MaxChars)

    $file = [System.IO.File]::OpenRead($Path)
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($file, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = [System.IO.StreamReader]::new($gzip, [System.Text.Encoding]::UTF8)
        try {
            if ($MaxChars -le 0) { return $reader.ReadToEnd() }
            $buffer = [char[]]::new($MaxChars)
            $read = $reader.ReadBlock($buffer, 0, $MaxChars)
            [string]::new($buffer, 0, $read)
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $file.Dispose()
    }
}

function Read-TerraformSchemaCache {
    # Not exported. A cache file (either kind) as ordered dictionaries, the shape
    # Get-TerraformProviderSchema returns.
    param([string]$Path)

    [TerraformGraph.Json]::Deserialize((Read-TerraformSchemaCacheText -Path $Path), 1024, $true)
}

function Get-TerraformSchemaCacheEntry {
    # Not exported. Every cached file of -Kind, by address, newest version first:
    # TerraformGraph.CachedSchema or TerraformGraph.CachedDoc. Schema: the address is the
    # first provider_schemas key. Docs: address, docCount and unmatchedCount are the first
    # members. Both are read from the first few KB, so listing never decompresses a whole
    # file; a file that does not start that way is parsed in full.
    param([ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    $root = if ($Kind -eq 'Docs') { $script:TerraformDocCacheRoot } else { $script:TerraformSchemaCacheRoot }
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { return }

    $entries = foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json.gz' -File -Recurse -Depth 1) {
        try {
            $head = Read-TerraformSchemaCacheText -Path $file.FullName -MaxChars 4096
            $version = $file.Name.Substring(0, $file.Name.Length - '.json.gz'.Length)
            if ($Kind -eq 'Docs') {
                if ($head -match '^\s*\{\s*"address"\s*:\s*"([^"]+)"' -and $head -match '"docCount"\s*:\s*(\d+)') {
                    $address = $head -replace '(?s)^\s*\{\s*"address"\s*:\s*"([^"]+)".*$', '$1'
                    $docCount = [int]$Matches[1]
                    $unmatchedCount = if ($head -match '"unmatchedCount"\s*:\s*(\d+)') { [int]$Matches[1] } else { $null }
                    $harvestedOn = if ($head -match '"harvestedOn"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }
                }
                else {
                    $document = Read-TerraformSchemaCache -Path $file.FullName
                    $address = $document['address']
                    $docCount = @($document['docs']).Count
                    $unmatchedCount = $document['unmatchedCount']
                    $harvestedOn = $document['harvestedOn']
                }
                if (-not $address) { continue }
                [pscustomobject]@{
                    PSTypeName      = 'TerraformGraph.CachedDoc'
                    ProviderAddress = [string]$address
                    Version         = $version
                    Path            = $file.FullName
                    Bytes           = $file.Length
                    CachedOn        = $file.LastWriteTimeUtc
                    DocCount        = $docCount
                    UnmatchedCount  = $unmatchedCount
                    HarvestedOn     = $harvestedOn
                }
                continue
            }
            $address = if ($head -match '"provider_schemas"\s*:\s*\{\s*"([^"]+)"') {
                $Matches[1]
            }
            else {
                @(Get-TerraformSchemaKeys -InputObject (Read-TerraformSchemaCache -Path $file.FullName).provider_schemas)[0]
            }
            if (-not $address) { continue }
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.CachedSchema'
                ProviderAddress = [string]$address
                Version         = $version
                Path            = $file.FullName
                Bytes           = $file.Length
                CachedOn        = $file.LastWriteTimeUtc
            }
        }
        catch {
            Write-Verbose "Skipping $($file.FullName): $($_.Exception.Message)"
        }
    }

    foreach ($group in @($entries | Group-Object { $_.ProviderAddress.ToLowerInvariant() } | Sort-Object Name -Culture '')) {
        foreach ($sorted in Sort-TerraformRegistryVersion -Versions @($group.Group)) { $sorted.Record }
    }
}

function Select-TerraformSchemaCacheEntry {
    # Not exported. Cached schemas matching any -Name pattern (all when none), by shape as
    # in Select-TerraformRegistryProvider: no slash matches the bare name, one slash
    # namespace/name, two the full address. -like, so wildcards work and case is ignored.
    param($Entry, [string[]]$Name)

    foreach ($candidate in $Entry) {
        if (-not $Name) { $candidate; continue }
        $segments = $candidate.ProviderAddress.Split('/')
        foreach ($pattern in $Name) {
            $value = switch ($pattern.Split('/').Count) {
                1       { $segments[-1] }
                2       { ($segments | Select-Object -Last 2) -join '/' }
                default { $candidate.ProviderAddress }
            }
            if ($value -like $pattern) { $candidate; break }
        }
    }
}

function Resolve-TerraformSchemaCacheProvider {
    # Not exported. One cached schema per provider the -Name patterns select, at -Version or
    # the newest cached version. A name without a wildcard that matches several namespaces
    # resolves to the hashicorp one, else is an error. Throws when anything is not cached,
    # naming both ways to fill the -Kind cache; callers turn that into their own terminating
    # error.
    param([string[]]$Name, [string]$Version, [ValidateSet('Schema', 'Docs')][string]$Kind = 'Schema')

    $entries = @(Get-TerraformSchemaCacheEntry -Kind $Kind)
    $addresses = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $Name) {
        $found = @(Select-TerraformSchemaCacheEntry -Entry $entries -Name $pattern | ForEach-Object ProviderAddress | Select-Object -Unique)
        if ($found.Count -gt 1 -and -not [WildcardPattern]::ContainsWildcardCharacters($pattern)) {
            $normalized = (ConvertTo-TerraformProviderAddress -Provider $pattern).Address
            $preferred = @($found | Where-Object { $_ -eq $normalized })
            if (-not $preferred.Count) {
                throw "'$pattern' matches $($found.Count) cached providers: $($found -join ', '). Specify one."
            }
            $found = $preferred
        }
        if (-not $found.Count) {
            if ($Kind -eq 'Docs') {
                throw "No cached provider docs match '$pattern'. Download a docs pack with Get-TerraformDocPack -Provider $pattern, or harvest them from the registry with Update-TerraformProviderDocCache -Provider $pattern."
            }
            throw "No cached schema matches '$pattern'. Download a schema pack with Get-TerraformSchemaPack -Provider $pattern, or harvest it locally with Get-TerraformProviderSchema -Provider $pattern -SaveToCache."
        }
        foreach ($address in $found) {
            if (-not ($addresses | Where-Object { $_ -eq $address })) { $addresses.Add($address) }
        }
    }

    foreach ($address in $addresses) {
        $versions = @($entries | Where-Object ProviderAddress -eq $address)
        if (-not $Version) { $versions[0]; continue }
        $entry = $versions | Where-Object Version -eq $Version | Select-Object -First 1
        if (-not $entry) {
            if ($Kind -eq 'Docs') {
                throw "Docs for $address $Version are not cached (cached: $(@($versions.Version) -join ', ')). Download them with Get-TerraformDocPack -Provider $address -Version $Version, or harvest them with Update-TerraformProviderDocCache -Provider $address -Version $Version."
            }
            throw "$address $Version is not cached (cached: $(@($versions.Version) -join ', ')). Download it with Get-TerraformSchemaPack -Provider $address -Version $Version, or harvest it locally with Get-TerraformProviderSchema -Provider $address -Version '= $Version' -SaveToCache."
        }
        $entry
    }
}

function Get-TerraformSchemaCacheDocument {
    # Not exported. One schema document holding every -Entry's provider, in the shape
    # terraform providers schema -json prints, for ConvertTo-TerraformSchemaGraph.
    param([object[]]$Entry)

    $providerSchemas = [ordered]@{}
    $formatVersion = '1.0'
    foreach ($item in $Entry) {
        Write-Verbose "Reading $($item.ProviderAddress) $($item.Version) from $($item.Path)"
        $document = Read-TerraformSchemaCache -Path $item.Path
        if ($document['format_version']) { $formatVersion = $document['format_version'] }
        foreach ($key in @($document['provider_schemas'].Keys)) {
            $providerSchemas[$key] = $document['provider_schemas'][$key]
        }
    }
    [ordered]@{ format_version = $formatVersion; provider_schemas = $providerSchemas }
}

function Save-TerraformSchemaPackFile {
    # Not exported. Copies <Source>/<Name> to -Destination: a download for an http(s)
    # Source, a file copy for a directory. The only network call in the pack code.
    #
    # A GitHub release Source (https://github.com/<owner>/<repo>/releases/latest/download or
    # .../releases/download/<tag>) with $env:GH_TOKEN or $env:GITHUB_TOKEN set goes through
    # the API instead, because releases/.../download/<file> is 404 for a private repo even
    # with a token: GET api.github.com/repos/<owner>/<repo>/releases/latest (or
    # /releases/tags/<tag>) with Authorization: Bearer, find the asset by name, then GET its
    # api url with Accept: application/octet-stream. -State is a hashtable the caller keeps
    # for one pack run so the release is looked up once. Without a token the anonymous URL is
    # used, and a 404 says the repository may be private and names GH_TOKEN.
    param([string]$Source, [string]$Name, [string]$Destination, [hashtable]$State = @{})

    if ($Source -notmatch '^https?://') {
        Copy-Item -LiteralPath (Join-Path $Source $Name) -Destination $Destination -ErrorAction Stop
        return
    }

    $token = if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
    $github = [regex]::Match($Source.TrimEnd('/'), '^https://github\.com/([^/]+)/([^/]+)/releases/(?:latest/download|download/([^/]+))$', 'IgnoreCase')

    if ($github.Success -and $token) {
        $owner = $github.Groups[1].Value
        $repo = $github.Groups[2].Value
        $tag = if ($github.Groups[3].Success) { $github.Groups[3].Value } else { $null }
        $headers = @{ Authorization = "Bearer $token"; 'X-GitHub-Api-Version' = '2022-11-28' }
        $releaseUri = if ($tag) { "https://api.github.com/repos/$owner/$repo/releases/tags/$([uri]::EscapeDataString($tag))" } else { "https://api.github.com/repos/$owner/$repo/releases/latest" }
        if (-not $State.ContainsKey($releaseUri)) {
            $State[$releaseUri] = Invoke-RestMethod -Uri $releaseUri -Headers ($headers + @{ Accept = 'application/vnd.github+json' }) -TimeoutSec 60 -ErrorAction Stop
        }
        $release = $State[$releaseUri]
        $asset = @($release.assets) | Where-Object { $_.name -ceq $Name } | Select-Object -First 1
        if (-not $asset) {
            throw "Release $($release.tag_name) of $owner/$repo has no asset named $Name."
        }
        $null = Invoke-WebRequest -Uri $asset.url -Headers ($headers + @{ Accept = 'application/octet-stream' }) -OutFile $Destination -TimeoutSec 600 -ErrorAction Stop
        return
    }

    try {
        $null = Invoke-WebRequest -Uri "$($Source.TrimEnd('/'))/$Name" -OutFile $Destination -TimeoutSec 600 -ErrorAction Stop
    }
    catch {
        $status = [int]$_.Exception.Response.StatusCode
        if ($status -eq 404 -and $github.Success) {
            throw [System.InvalidOperationException]::new("$Name was not found at $Source (404). The repository may be private: set `$env:GH_TOKEN (or `$env:GITHUB_TOKEN) to a token that can read it, and the download goes through the GitHub API.", $_.Exception)
        }
        throw
    }
}

function Install-TerraformPack {
    # Not exported. The body of Get-TerraformSchemaPack (-Kind Schema) and
    # Get-TerraformDocPack (-Kind Docs). Reads manifest.json from -Source, keeps the entries
    # of -Kind (an entry with no kind is a schema entry, as manifests before 0.11.0 wrote
    # them), resolves every provider to an entry before downloading anything, downloads,
    # checks sha256 and moves each file into the -Kind cache. Terminating errors go through
    # -Cmdlet, the calling function's $PSCmdlet, so they carry its name.
    param(
        [System.Management.Automation.PSCmdlet]$Cmdlet,
        [ValidateSet('Schema', 'Docs')][string]$Kind,
        [string[]]$Provider,
        [string]$Version,
        [string]$Source,
        [switch]$Force,
        [switch]$PassThru
    )

    $isDocs = $Kind -eq 'Docs'
    $errorPrefix = if ($isDocs) { 'DocPack' } else { 'SchemaPack' }
    $commandName = if ($isDocs) { 'Get-TerraformDocPack' } else { 'Get-TerraformSchemaPack' }
    $what = if ($isDocs) { 'docs pack' } else { 'pack' }

    $isUrl = $Source -match '^https?://'
    if (-not $isUrl) {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.IO.DirectoryNotFoundException]::new("Source '$Source' is not an http(s) URL or an existing directory."),
                "$($errorPrefix)SourceNotFound",
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Source))
        }
        $Source = (Resolve-Path -LiteralPath $Source).ProviderPath
    }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "TerraformGraph-pack-$([guid]::NewGuid().ToString('n'))"
    $null = New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop
    $downloadState = @{}
    try {
        $manifestPath = Join-Path $staging 'manifest.json'
        try {
            Save-TerraformSchemaPackFile -Source $Source -Name 'manifest.json' -Destination $manifestPath -State $downloadState
            $manifest = [TerraformGraph.Json]::Deserialize([System.IO.File]::ReadAllText($manifestPath), 1024, $false)
        }
        catch {
            $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("Could not read manifest.json from '$Source': $($_.Exception.Message)", $_.Exception),
                "$($errorPrefix)ManifestUnavailable",
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $Source))
        }
        $manifestKind = if ($isDocs) { 'docs' } else { 'schema' }
        $packs = @($manifest.packs | Where-Object { $_ -and ([string]$_.kind -eq $manifestKind -or (-not $isDocs -and -not $_.kind)) })

        # Every provider is resolved to a manifest entry before anything is downloaded.
        $targets = [System.Collections.Generic.List[string]]::new()
        if (-not $Provider) {
            # ForEach-Object, not $packs.address: that member access hits System.Array.Address.
            foreach ($address in @($packs | ForEach-Object { [string]$_.address } | Select-Object -Unique)) { $targets.Add($address) }
        }
        foreach ($name in $Provider) {
            if ([WildcardPattern]::ContainsWildcardCharacters($name)) {
                try {
                    $address = (Resolve-TerraformRegistryProvider -Name $name).ProviderAddress
                }
                catch {
                    $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new($_.Exception.Message),
                        'RegistryProviderNotResolved',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $name))
                }
            }
            else {
                $address = (ConvertTo-TerraformProviderAddress -Provider $name).Address
                if (-not ($packs | Where-Object address -eq $address) -and -not $name.Contains('/')) {
                    $byName = @($packs | Where-Object { ([string]$_.address).Split('/')[-1] -eq $name } | ForEach-Object address | Select-Object -Unique)
                    if ($byName.Count -eq 1) { $address = [string]$byName[0] }
                }
            }
            if (-not ($targets | Where-Object { $_ -eq $address })) { $targets.Add($address) }
        }

        $selected = foreach ($address in $targets) {
            $candidates = @($packs | Where-Object address -eq $address)
            $entry = if ($Version) {
                $candidates | Where-Object version -eq $Version | Select-Object -First 1
            }
            elseif ($candidates.Count) {
                (Sort-TerraformRegistryVersion -Versions @($candidates | ForEach-Object { [pscustomobject]@{ Version = [string]$_.version; Pack = $_ } }) |
                    Select-Object -First 1).Record.Pack
            }
            if (-not $entry) {
                $available = if ($packs.Count) { @($packs | ForEach-Object { "$($_.address) $($_.version)" }) -join ', ' } else { '(none)' }
                # Not $source: variable names ignore case, so that would overwrite -Source.
                $providerSource = (ConvertTo-TerraformProviderAddress -Provider $address).Source
                $versionText = if ($Version) { " $Version" } else { '' }
                $instead = if ($isDocs) {
                    "Harvest them from the registry instead with Update-TerraformProviderDocCache -Provider $providerSource$(if ($Version) { " -Version $Version" })."
                }
                else {
                    "Harvest it locally instead with Get-TerraformProviderSchema -Provider $providerSource$(if ($Version) { " -Version '= $Version'" }) -SaveToCache."
                }
                $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.Management.Automation.ItemNotFoundException]::new("$commandName found no $what for $address$versionText in '$Source' ($($what)s: $available). $instead"),
                    "$($errorPrefix)NotFound",
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $address))
            }
            $entry
        }

        foreach ($entry in @($selected)) {
            $address = [string]$entry.address
            $packVersion = [string]$entry.version
            $cachePath = Get-TerraformSchemaCachePath -Provider $address -Version $packVersion -Kind $Kind
            $existed = Test-Path -LiteralPath $cachePath -PathType Leaf

            if ($existed -and -not $Force) {
                Write-Verbose "$address $packVersion is already cached at $cachePath. Use -Force to download it again."
                $status = 'Cached'
            }
            else {
                $fileName = [string]$entry.file
                if (-not $fileName -or $fileName -ne [System.IO.Path]::GetFileName($fileName) -or $fileName -in '.', '..') {
                    $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.IO.InvalidDataException]::new("The manifest entry for $address $packVersion has an invalid file name '$fileName'."),
                        "$($errorPrefix)InvalidManifest",
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $address))
                }
                $download = Join-Path $staging $fileName
                Write-Verbose "Downloading $fileName from $Source"
                try {
                    Save-TerraformSchemaPackFile -Source $Source -Name $fileName -Destination $download -State $downloadState
                }
                catch {
                    $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new("Could not download $fileName from '$Source': $($_.Exception.Message)", $_.Exception),
                        "$($errorPrefix)DownloadFailed",
                        [System.Management.Automation.ErrorCategory]::ConnectionError,
                        $address))
                }

                $hash = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash
                if ($hash -ne [string]$entry.sha256) {
                    $Cmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.IO.InvalidDataException]::new("sha256 mismatch for $fileName ($address $packVersion): expected $($entry.sha256), got $($hash.ToLowerInvariant()). Nothing was written to the cache."),
                        "$($errorPrefix)HashMismatch",
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $address))
                }

                # Verified: move it into the cache folder under a temporary name, then into place.
                $directory = Split-Path -Path $cachePath -Parent
                $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
                $temporary = Join-Path $directory ".$([guid]::NewGuid().ToString('n')).tmp"
                try {
                    Move-Item -LiteralPath $download -Destination $temporary -ErrorAction Stop
                    Move-Item -LiteralPath $temporary -Destination $cachePath -Force -ErrorAction Stop
                }
                finally {
                    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
                }
                Write-Verbose "Cached $address $packVersion at $cachePath"
                $status = if ($existed) { 'Updated' } else { 'Downloaded' }
            }

            if ($PassThru) {
                [pscustomobject]@{
                    PSTypeName      = if ($isDocs) { 'TerraformGraph.DocPack' } else { 'TerraformGraph.SchemaPack' }
                    ProviderAddress = $address
                    Version         = $packVersion
                    Path            = $cachePath
                    Bytes           = (Get-Item -LiteralPath $cachePath).Length
                    Status          = $status
                }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-TerraformSchemaPack {
    <#
    .SYNOPSIS
        Downloads provider schema packs into the local schema cache.

    .DESCRIPTION
        Get-TerraformSchemaPack fills the local schema cache from a pack source instead of
        running terraform. A pack source holds manifest.json and one gzipped schema file per
        provider version; packs built for each module release are attached to its GitHub
        release, which is the default -Source.

        It reads manifest.json, picks the entry for each provider (at -Version, or the
        newest version in the manifest), downloads the file, checks its sha256 against the
        manifest and only then moves it into the cache at
        $env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz. A file
        whose hash does not match is a terminating error and nothing is written.

        A version that is already cached is skipped unless -Force is given. Every provider
        is checked against the manifest before anything is downloaded; one that has no
        entry is a terminating error that names Get-TerraformProviderSchema -SaveToCache,
        which harvests any provider locally.

        Once cached, ConvertTo-TerraformSchemaGraph -Provider and
        ConvertTo-TerraformResourceGraph -Provider or -AutoSchema read the schema with no
        terraform and no network.

        Only manifest entries with kind schema (or no kind, as manifests before 0.11.0
        wrote them) are considered; docs entries are for Get-TerraformDocPack.

        For a GitHub release -Source, set $env:GH_TOKEN (or $env:GITHUB_TOKEN) when the
        repository is private: the files are then fetched through the GitHub releases API
        with that token, since the plain releases/.../download URL is 404 for a private
        repository. Without a token the anonymous URL is used.

    .PARAMETER Provider
        Providers to download: 'azurerm', 'hashicorp/azurerm', or
        'registry.terraform.io/hashicorp/azurerm'. A name that is not in the manifest as
        written is also matched against the manifest by bare name, so 'azuredevops' finds
        microsoft/azuredevops. A value with a wildcard is resolved against the provider
        registry cache first and must match exactly one provider (see
        Get-TerraformRegistryProvider). Default: every provider in the manifest.

    .PARAMETER Version
        Version to download, such as 4.40.0. Default: the newest version in the manifest
        for each provider.

    .PARAMETER Source
        Where manifest.json and the pack files are: an http(s) URL, or a local directory
        such as the dist\schema-packs folder Invoke-Build BuildSchemaPack writes. Default:
        https://github.com/JerryBalmer1/TerraformGraph/releases/latest/download. A
        https://github.com/<owner>/<repo>/releases/download/<tag> URL names one release.

    .PARAMETER Force
        Download and replace a version that is already cached.

    .PARAMETER PassThru
        Return one TerraformGraph.SchemaPack per provider.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere -PassThru

        Download three packs from the latest release and show where they were cached.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider vsphere -Source .\dist\schema-packs -PassThru

        Install a pack built locally with Invoke-Build BuildSchemaPack.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider 'hashicorp/azure*' -Force

        Resolve the wildcard through the registry cache, then download that provider's
        pack again even though it is cached.

    .OUTPUTS
        None, or TerraformGraph.SchemaPack with -PassThru: ProviderAddress, Version, Path,
        Bytes, Status (Downloaded, Cached, or Updated). Default view is ProviderAddress,
        Version, Status, Bytes.

    .NOTES
        Status: Downloaded when the version was not cached before; Cached when it was and
        nothing was downloaded; Updated when -Force replaced a cached file.

    .LINK
        Get-TerraformSchemaCache

    .LINK
        Get-TerraformProviderSchema
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string]
        $Source = $script:TerraformSchemaPackSource,

        [switch]
        $Force,

        [switch]
        $PassThru
    )

    Install-TerraformPack -Cmdlet $PSCmdlet -Kind Schema -Provider $Provider -Version $Version -Source $Source -Force:$Force -PassThru:$PassThru
}

function Get-TerraformSchemaCache {
    <#
    .SYNOPSIS
        Lists the provider schemas in the local schema cache.

    .DESCRIPTION
        Get-TerraformSchemaCache lists the files in the local schema cache,
        $env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz, one
        TerraformGraph.CachedSchema per provider version. It only reads, and never
        decompresses more than the start of each file.

        The cache is filled by Get-TerraformSchemaPack (downloaded packs) and
        Get-TerraformProviderSchema -SaveToCache (harvested locally), and read by
        ConvertTo-TerraformSchemaGraph -Provider and ConvertTo-TerraformResourceGraph
        -Provider or -AutoSchema.

    .PARAMETER Provider
        Only these providers. Patterns match by shape and may use wildcards: 'azurerm' or
        'azure*' match the bare name in any namespace, 'hashicorp/azure*' namespace/name,
        and a full address the address. Case is ignored. Default: every cached schema.

    .EXAMPLE
        Get-TerraformSchemaCache

        Every cached provider version, newest version first within each provider.

    .EXAMPLE
        Get-TerraformSchemaCache 'azure*' | Measure-Object Bytes -Sum

        Disk used by the cached azurerm and azuredevops schemas.

    .OUTPUTS
        TerraformGraph.CachedSchema: ProviderAddress, Version, Path, Bytes, CachedOn (UTC).
        Default view is ProviderAddress, Version, Bytes, CachedOn.

    .LINK
        Get-TerraformSchemaPack
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider
    )

    Select-TerraformSchemaCacheEntry -Entry @(Get-TerraformSchemaCacheEntry) -Name $Provider
}

# Provider docs: the registry's markdown pages for a provider version, keyed on the schema
# node Id they document, in the docs cache (<docs root>\<address-slug>\<version>.json.gz).
# Update-TerraformProviderDocCache harvests from the registry and Get-TerraformDocPack
# downloads packs; Get-TerraformProviderDoc and Get-TerraformDocCache only read the cache.
# Doc Ids:
#   <address>                    overview
#   <address>/guide/<slug>       guides
#   <address>/resource/<type>    resources (the schema Resource node Id)
#   <address>/data/<type>        data-sources (the schema DataSource node Id)
#   <address>/unmatched/<category>/<slug>  a resource or data source page whose type is not
#                                in the cached schema
$script:TerraformDocCategories = @('overview', 'guides', 'resources', 'data-sources')
$script:TerraformDocCacheMemo = @{}

Update-TypeData -TypeName 'TerraformGraph.ProviderDoc' -DefaultDisplayPropertySet Id, Category, Title, Subcategory -Force
Update-TypeData -TypeName 'TerraformGraph.DocCache' -DefaultDisplayPropertySet ProviderAddress, Version, Status, DocCount, UnmatchedCount, Elapsed -Force

function Find-TerraformProviderDocVersion {
    # Not exported. The registry's provider-versions record for -Version of
    # <Namespace>/<Name>, or for its newest version that is not a pre-release when -Version
    # is empty: [pscustomobject]@{ Version; VersionId }. Network. See
    # Get-TerraformProviderDocHarvest for the endpoints.
    param([string]$Namespace, [string]$Name, [string]$Version)

    $registry = "https://$($script:TerraformRegistrySource)"
    $response = Invoke-TerraformRegistryRequest -Uri "$registry/v2/providers/$Namespace/${Name}?include=provider-versions"
    $versions = @($response.included | Where-Object { $_.type -eq 'provider-versions' } |
            ForEach-Object { [pscustomobject]@{ Version = [string]$_.attributes.version; VersionId = [string]$_.id } })
    if (-not $versions.Count) {
        throw "The registry lists no versions for $Namespace/$Name."
    }
    if ($Version) {
        $found = $versions | Where-Object Version -eq $Version | Select-Object -First 1
        if (-not $found) {
            throw "The registry has no version $Version of $Namespace/$Name."
        }
        return $found
    }
    $sorted = @(Sort-TerraformRegistryVersion -Versions $versions)
    $newest = $sorted | Where-Object { -not $_.PreRelease } | Select-Object -First 1
    if (-not $newest) { $newest = $sorted[0] }
    $newest.Record
}

function Get-TerraformProviderDocHarvest {
    # Not exported. Lists one provider version's docs and fetches every page's markdown from
    # the public registry. Probed 2026-10-06:
    #
    #   Version id: GET https://registry.terraform.io/v2/providers/<namespace>/<name>?include=provider-versions
    #     included[] holds every version (see Get-TerraformRegistryHarvest). hashicorp/null
    #     3.2.3 is { "type": "provider-versions", "id": "59862", "attributes": { "version": "3.2.3", ... } }.
    #
    #   Listing: GET https://registry.terraform.io/v2/provider-versions/<id>?include=provider-docs
    #     The listing endpoint in the task, /v2/provider-versions/<id>/provider-docs, is 404.
    #     The include returns every doc in one response (1645 for azurerm 5.8.0, no paging).
    #     /v2/provider-docs?filter[provider-version]=<id> also lists, but ignores page[size]
    #     and pages by 1, so it is not used. One included[] element (null 3.2.3):
    #       { "type": "provider-docs", "id": "6794557",
    #         "attributes": { "category": "resources", "language": "hcl",
    #           "path": "docs/resources/resource.md", "slug": "resource", "subcategory": null,
    #           "title": "resource", "truncated": false },
    #         "links": { "self": "/v2/provider-docs/6794557" } }
    #     Categories seen: overview, guides, resources, data-sources, plus functions,
    #     ephemeral-resources, list-resources and actions (azurerm 5.8.0, local 2.9.1). Only
    #     the first four are kept. Languages other than hcl (cdktf) are skipped. The slug is
    #     usually the type without the provider prefix (resource_pool for
    #     vsphere_resource_pool) but some providers keep it (vsphere_sso_group).
    #
    #   Content: GET https://registry.terraform.io/v2/provider-docs/<doc id>
    #     data.attributes has category, content (raw markdown, front matter included),
    #     language, path, slug, subcategory, title, truncated. null 3.2.3 resource starts:
    #       ---\n# generated by https://github.com/hashicorp/terraform-plugin-docs\n
    #       page_title: "null_resource Resource - terraform-provider-null"\nsubcategory: ""\n...
    #
    # Returns one record per kept doc: Category, Title, Subcategory, Slug, Content.
    # Content requests run with ForEach-Object -Parallel and Invoke-TerraformRegistryRequest's
    # retry; if any page still fails, it throws and nothing is returned.
    param([string]$VersionId, [int]$ThrottleLimit)

    $registry = "https://$($script:TerraformRegistrySource)"
    $listing = Invoke-TerraformRegistryRequest -Uri "$registry/v2/provider-versions/${VersionId}?include=provider-docs"
    $listed = [System.Collections.Generic.List[object]]::new()
    $skipped = [ordered]@{}
    foreach ($item in @($listing.included)) {
        if ($item.type -ne 'provider-docs') { continue }
        $attributes = $item.attributes
        $category = [string]$attributes.category
        if ([string]$attributes.language -ne 'hcl' -or $script:TerraformDocCategories -notcontains $category) {
            $key = "$category ($($attributes.language))"
            $skipped[$key] = 1 + [int]$skipped[$key]
            continue
        }
        $listed.Add([pscustomobject]@{
            DocId       = [string]$item.id
            Category    = $category
            Title       = [string]$attributes.title
            Subcategory = if ([string]::IsNullOrEmpty([string]$attributes.subcategory)) { $null } else { [string]$attributes.subcategory }
            Slug        = [string]$attributes.slug
        })
    }
    foreach ($key in $skipped.Keys) { Write-Verbose "Skipped $($skipped[$key]) docs in category $key" }
    Write-Verbose "Listed $($listed.Count) docs"

    $requestDefinition = ${function:Invoke-TerraformRegistryRequest}.ToString()
    $done = 0
    $fetched = $listed | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        Set-Item -Path function:Invoke-TerraformRegistryRequest -Value $using:requestDefinition
        $doc = $_
        try {
            $response = Invoke-TerraformRegistryRequest -Uri "$($using:registry)/v2/provider-docs/$($doc.DocId)"
            [pscustomobject]@{ Doc = $doc; Content = [string]$response.data.attributes.content; Error = $null }
        }
        catch {
            [pscustomobject]@{ Doc = $doc; Content = $null; Error = $_.Exception.Message }
        }
    } | ForEach-Object {
        $done++
        Write-Progress -Id 2 -Activity 'Fetching provider docs' -Status "$done of $($listed.Count)" -PercentComplete (100 * $done / [math]::Max(1, $listed.Count))
        $_
    }
    Write-Progress -Id 2 -Activity 'Fetching provider docs' -Completed

    $failed = @($fetched | Where-Object Error)
    if ($failed.Count) {
        $names = @($failed | Select-Object -First 10 | ForEach-Object { "$($_.Doc.Category)/$($_.Doc.Slug) ($($_.Error))" })
        throw "Failed to fetch $($failed.Count) docs: $($names -join '; ')$(if ($failed.Count -gt 10) { '; ...' }). The cache was not written."
    }

    foreach ($entry in $fetched) {
        [pscustomobject]@{
            Category    = $entry.Doc.Category
            Title       = $entry.Doc.Title
            Subcategory = $entry.Doc.Subcategory
            Slug        = $entry.Doc.Slug
            Content     = $entry.Content
        }
    }
}

function Get-TerraformProviderDocSchemaIndex {
    # Not exported. The resource and data source types of one provider from the schema
    # cache, for joining docs to schema node Ids: the schema cached at -Version, else the
    # newest cached version, else $null. Prefix is the most common text before the first
    # underscore across those types (azurerm, azuredevops, vsphere, null).
    param([string]$Address, [string]$Version)

    $entries = @(Get-TerraformSchemaCacheEntry | Where-Object ProviderAddress -eq $Address)
    if (-not $entries.Count) { return $null }
    $entry = $entries | Where-Object Version -eq $Version | Select-Object -First 1
    if (-not $entry) {
        $entry = $entries[0]
        Write-Verbose "No cached schema for $Address $Version; matching docs against the cached $($entry.Version) schema"
    }

    $document = Read-TerraformSchemaCache -Path $entry.Path
    $schemas = $document['provider_schemas']
    $key = @($schemas.Keys) | Where-Object { $_ -eq $Address } | Select-Object -First 1
    $schema = $schemas[$key]
    $resource = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $data = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($schema['resource_schemas']) { foreach ($type in $schema['resource_schemas'].Keys) { $null = $resource.Add([string]$type) } }
    if ($schema['data_source_schemas']) { foreach ($type in $schema['data_source_schemas'].Keys) { $null = $data.Add([string]$type) } }

    $prefix = @(@($resource) + @($data) | ForEach-Object { $_.Split('_')[0] } | Group-Object -NoElement |
            Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
            Select-Object -First 1).Name
    [pscustomobject]@{
        SchemaVersion = $entry.Version
        Prefix        = if ($prefix) { $prefix } else { $Address.Split('/')[-1] }
        Resource      = $resource
        Data          = $data
    }
}

function Resolve-TerraformProviderDocId {
    # Not exported. The doc Id for one registry doc. Resources and data sources are joined
    # to the schema: the type is <Prefix>_<slug>, or the slug itself when it already starts
    # with <Prefix>_ and only that form is in the schema (vsphere_sso_group). A type in
    # neither form is unmatched: <address>/unmatched/<category>/<slug>, Matched $false. With
    # no -Index (no cached schema) the type is built the same way without checking and
    # Matched is $null.
    param([string]$Address, [string]$Category, [string]$Slug, $Index, [string]$Prefix)

    switch ($Category) {
        'overview' { return [pscustomobject]@{ Id = $Address; Type = $null; Matched = $true } }
        'guides'   { return [pscustomobject]@{ Id = "$Address/guide/$Slug"; Type = $null; Matched = $true } }
    }
    $segment = if ($Category -eq 'data-sources') { 'data' } else { 'resource' }
    $candidates = @("$($Prefix)_$Slug")
    if ($Slug.StartsWith("$($Prefix)_", [System.StringComparison]::Ordinal)) { $candidates += $Slug }

    if ($null -eq $Index) {
        $type = $candidates[-1]
        return [pscustomobject]@{ Id = "$Address/$segment/$type"; Type = $type; Matched = $null }
    }
    $types = if ($segment -eq 'data') { $Index.Data } else { $Index.Resource }
    foreach ($type in $candidates) {
        if ($types.Contains($type)) {
            return [pscustomobject]@{ Id = "$Address/$segment/$type"; Type = $type; Matched = $true }
        }
    }
    [pscustomobject]@{ Id = "$Address/unmatched/$Category/$Slug"; Type = $null; Matched = $false }
}

function ConvertTo-TerraformProviderDocDocument {
    # Not exported. The docs cache document for harvested -Docs records: Ids resolved
    # against -Index, sorted overview, guides, resources, data-sources, then by slug.
    # address, version and the counts come first so listing reads them from the head.
    param([string]$Address, [string]$Version, [object[]]$Docs, $Index, [string]$Prefix)

    $rank = @{ 'overview' = 0; 'guides' = 1; 'resources' = 2; 'data-sources' = 3 }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($doc in $Docs) {
        $resolved = Resolve-TerraformProviderDocId -Address $Address -Category $doc.Category -Slug $doc.Slug -Index $Index -Prefix $Prefix
        $list.Add([pscustomobject]@{ Doc = $doc; Resolved = $resolved })
    }
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            $byCategory = ([int]$rank[$a.Doc.Category]).CompareTo([int]$rank[$b.Doc.Category])
            if ($byCategory) { return $byCategory }
            [string]::CompareOrdinal($a.Doc.Slug, $b.Doc.Slug)
        })

    $unmatched = @($list | Where-Object { $_.Resolved.Matched -eq $false })
    [ordered]@{
        address        = $Address
        version        = $Version
        harvestedOn    = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        schemaVersion  = if ($Index) { $Index.SchemaVersion } else { $null }
        docCount       = $list.Count
        unmatchedCount = if ($Index) { $unmatched.Count } else { $null }
        docs           = [object[]]@(foreach ($item in $list) {
                [ordered]@{
                    id          = $item.Resolved.Id
                    category    = $item.Doc.Category
                    title       = $item.Doc.Title
                    subcategory = $item.Doc.Subcategory
                    slug        = $item.Doc.Slug
                    content     = $item.Doc.Content
                }
            })
    }
}

function Read-TerraformProviderDocFile {
    # Not exported. Every doc in one docs cache file as TerraformGraph.ProviderDoc, plus an
    # Id index: @{ Docs; ById }. Parsed once per file version and kept in memory, so a
    # pipeline of many nodes reads each file once. Callers copy before changing a doc.
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    $key = "$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
    $memo = $script:TerraformDocCacheMemo[$item.FullName]
    if ($memo -and $memo.Key -ceq $key) { return $memo.Value }

    $document = Read-TerraformSchemaCache -Path $item.FullName
    $address = [string]$document['address']
    $version = [string]$document['version']
    $byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $docs = foreach ($doc in @($document['docs'])) {
        $id = [string]$doc['id']
        $type = if ($id -match '^[^/]+/[^/]+/[^/]+/(?:resource|data)/([^/]+)$') { $Matches[1] } else { $null }
        $node = [pscustomobject]@{
            PSTypeName      = 'TerraformGraph.ProviderDoc'
            Id              = $id
            ProviderAddress = $address
            Version         = $version
            Category        = [string]$doc['category']
            Title           = [string]$doc['title']
            Subcategory     = $doc['subcategory']
            Slug            = [string]$doc['slug']
            Type            = $type
            Content         = [string]$doc['content']
            ExampleCount    = $null
        }
        $byId[$id] = $node
        $node
    }
    $value = @{ Docs = @($docs); ById = $byId }
    $script:TerraformDocCacheMemo[$item.FullName] = @{ Key = $key; Value = $value }
    $value
}

function Get-TerraformDocExample {
    # Not exported. The bodies of the ```hcl and ```terraform fenced code blocks in -Content,
    # in order. Other fences (shell, json, untagged) are left out.
    param([string]$Content)

    $pattern = '(?ms)^[ \t]*(`{3,}|~{3,})[ \t]*(?:hcl|terraform)\b[^\r\n]*\r?\n(.*?)\r?\n[ \t]*\1[ \t]*$'
    foreach ($match in [regex]::Matches($Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $match.Groups[2].Value
    }
}

function Invoke-TerraformProviderDocUpdate {
    # Not exported. The harvest of one provider for Update-TerraformProviderDocCache: returns
    # its TerraformGraph.DocCache row, or throws an ErrorRecord carrying the command's error
    # id (RegistryProviderNotResolved, ProviderDocNotOnRegistry, ProviderDocHarvestFailed),
    # which the Provider set rethrows as terminating and the Bundle set turns into a warning
    # and a Failed row. -RegistryProvider (a registry cache record) skips resolving -Name.
    # -Version empty means the registry cache's latest, else the newest non-prerelease on the
    # registry. -Resume returns a version that is already cached before any network call
    # when the version is known locally; -Force harvests a cached version again. -Quiet makes
    # the no-cached-schema warning verbose, for bundle runs where most providers have none.
    param([string]$Name, $RegistryProvider, [string]$Version, [int]$ThrottleLimit, [switch]$Force, [switch]$Resume, [switch]$Quiet)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $fail = {
        param($Exception, [string]$ErrorId, [System.Management.Automation.ErrorCategory]$Category, $Target)
        [System.Management.Automation.ErrorRecord]::new($Exception, $ErrorId, $Category, $Target)
    }
    $cachedRow = {
        param([string]$Address, [string]$DocVersion, [string]$Path)
        $entry = Get-TerraformSchemaCacheEntry -Kind Docs | Where-Object Path -eq ([System.IO.Path]::GetFullPath($Path)) | Select-Object -First 1
        $stopwatch.Stop()
        [pscustomobject]@{
            PSTypeName      = 'TerraformGraph.DocCache'
            ProviderAddress = $Address
            Version         = $DocVersion
            Path            = $Path
            Status          = 'Cached'
            DocCount        = $entry.DocCount
            UnmatchedCount  = $entry.UnmatchedCount
            SchemaVersion   = $null
            Elapsed         = $stopwatch.Elapsed
            Error           = $null
        }
    }

    if ($RegistryProvider) {
        $parsed = ConvertTo-TerraformProviderAddress -Provider $RegistryProvider.ProviderAddress
        $registryProvider = $RegistryProvider
        $Name = $RegistryProvider.ProviderAddress
    }
    else {
        try {
            if ([WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $registryProvider = Resolve-TerraformRegistryProvider -Name $Name
                $parsed = ConvertTo-TerraformProviderAddress -Provider $registryProvider.ProviderAddress
            }
            else {
                $parsed = ConvertTo-TerraformProviderAddress -Provider $Name
                $registryCache = Get-TerraformRegistryCache
                $registryProvider = if ($registryCache) {
                    $registryCache.Providers | Where-Object ProviderAddress -eq $parsed.Address.ToLowerInvariant() | Select-Object -First 1
                }
            }
        }
        catch {
            throw (& $fail ([System.ArgumentException]::new($_.Exception.Message)) 'RegistryProviderNotResolved' InvalidArgument $Name)
        }
    }
    if ($parsed.Host -ne $script:TerraformRegistrySource) {
        throw (& $fail ([System.ArgumentException]::new("$($parsed.Address) is not on $($script:TerraformRegistrySource); only registry providers have docs to harvest.")) 'ProviderDocNotOnRegistry' InvalidArgument $Name)
    }
    $address = $parsed.Address.ToLowerInvariant()
    # The registry record keeps the namespace's own case (IBM-Cloud), which the API is given.
    $namespace = if ($registryProvider) { $registryProvider.Namespace } else { $parsed.Namespace }
    $providerName = if ($registryProvider) { $registryProvider.Name } else { $parsed.Name }
    $wanted = if ($Version) { $Version } elseif ($registryProvider -and $registryProvider.Latest) { [string]$registryProvider.Latest } else { $null }

    if ($Resume -and $wanted) {
        $path = Get-TerraformSchemaCachePath -Provider $address -Version $wanted -Kind Docs
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Write-Verbose "Docs for $address $wanted are already cached at $path; -Resume skips them."
            return (& $cachedRow $address $wanted $path)
        }
    }

    try {
        $found = Find-TerraformProviderDocVersion -Namespace $namespace -Name $providerName -Version $wanted
    }
    catch {
        throw (& $fail ([System.InvalidOperationException]::new($_.Exception.Message, $_.Exception)) 'ProviderDocHarvestFailed' ConnectionError $address)
    }
    $docVersion = $found.Version
    $path = Get-TerraformSchemaCachePath -Provider $address -Version $docVersion -Kind Docs
    $existed = Test-Path -LiteralPath $path -PathType Leaf

    if ($existed -and -not $Force) {
        Write-Verbose "Docs for $address $docVersion are already cached at $path. Use -Force to harvest them again."
        return (& $cachedRow $address $docVersion $path)
    }

    Write-Verbose "Harvesting docs for $address $docVersion (registry version id $($found.VersionId))"
    try {
        $docs = @(Get-TerraformProviderDocHarvest -VersionId $found.VersionId -ThrottleLimit $ThrottleLimit)
    }
    catch {
        throw (& $fail ([System.InvalidOperationException]::new($_.Exception.Message, $_.Exception)) 'ProviderDocHarvestFailed' ConnectionError $address)
    }

    $index = Get-TerraformProviderDocSchemaIndex -Address $address -Version $docVersion
    if (-not $index) {
        $message = "No cached schema for $address, so resource and data source doc Ids are built from the '$($parsed.Name)_' prefix without checking. Run Get-TerraformSchemaPack -Provider $($parsed.Source) (or Get-TerraformProviderSchema -Provider $($parsed.Source) -SaveToCache), then Update-TerraformProviderDocCache -Force, to match them to schema nodes."
        if ($Quiet) { Write-Verbose $message } else { Write-Warning $message }
    }
    $prefix = if ($index) { $index.Prefix } else { $parsed.Name }
    $document = ConvertTo-TerraformProviderDocDocument -Address $address -Version $docVersion -Docs $docs -Index $index -Prefix $prefix
    foreach ($doc in $document.docs) {
        if ($doc.id.StartsWith("$address/unmatched/", [System.StringComparison]::Ordinal)) { Write-Verbose "Unmatched: $($doc.category)/$($doc.slug)" }
    }
    $path = Write-TerraformSchemaCache -Provider $address -Version $docVersion -Document $document -Kind Docs
    $stopwatch.Stop()
    Write-Verbose "Wrote $($document.docCount) docs for $address $docVersion ($(if ($index) { "$($document.unmatchedCount) unmatched against schema $($index.SchemaVersion)" } else { 'not matched: no cached schema' })) to $path in $($stopwatch.Elapsed)"

    [pscustomobject]@{
        PSTypeName      = 'TerraformGraph.DocCache'
        ProviderAddress = $address
        Version         = $docVersion
        Path            = $path
        Status          = if ($existed) { 'Updated' } else { 'Harvested' }
        DocCount        = $document.docCount
        UnmatchedCount  = $document.unmatchedCount
        SchemaVersion   = $document.schemaVersion
        Elapsed         = $stopwatch.Elapsed
        Error           = $null
    }
}

function Update-TerraformProviderDocCache {
    <#
    .SYNOPSIS
        Harvests provider documentation from the public registry into the docs cache, for named providers or a whole bundle.

    .DESCRIPTION
        Update-TerraformProviderDocCache lists the docs of one provider version on
        registry.terraform.io, fetches every page's markdown with ForEach-Object -Parallel
        (5xx is retried five times with a short backoff; a 429, the registry's rate limit, is retried for up to about 12 minutes) and writes them atomically to
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz. If any page
        still fails, nothing is written for that provider.

        Only the overview, guides, resources and data-sources categories are kept, in the
        hcl language. Each doc gets the Id of the schema node it documents, so docs join to
        ConvertTo-TerraformSchemaGraph and ConvertTo-TerraformResourceGraph output:
            <address>                    overview
            <address>/guide/<slug>       guides
            <address>/resource/<type>    resources
            <address>/data/<type>        data-sources
        The registry slug is the type without the provider prefix (virtual_machine for
        vsphere_virtual_machine), so the type is rebuilt as <prefix>_<slug>, where prefix
        is the one the provider's cached schema uses; a slug that already carries the
        prefix is also tried. Matching uses the cached schema at the same version, else
        the newest cached schema of that provider. A page whose type is in neither form is
        kept with Id <address>/unmatched/<category>/<slug> and counted in UnmatchedCount:
        a finding, not an error. With no cached schema at all, Ids are built from the
        provider name without checking, UnmatchedCount is empty, and a warning names
        Get-TerraformSchemaPack.

        -Provider: a version that is already cached is skipped unless -Force is given, and a
        provider that fails is a terminating error.

        -BundlePath: every provider of the bundle's set (its registry tiers plus extra
        providers, less exclusions, resolved against the registry cache beside the bundle
        file, else the usual registry cache) is harvested at its latest version in that
        registry cache, one after another, and the result is one
        TerraformGraph.DocHarvestSummary. A provider that fails is a warning and a Failed
        row in the summary, never a stop. Without -Resume every provider is harvested
        again; with it, providers already cached at that version are skipped.

        This command and Get-TerraformDocPack are the only ones that fill the docs cache;
        completers and Get-TerraformProviderDoc never touch the network.

    .PARAMETER Provider
        Providers to harvest: 'null', 'hashicorp/null' or
        'registry.terraform.io/hashicorp/null'. A value with a wildcard is resolved against
        the provider registry cache and must match exactly one provider.

    .PARAMETER Version
        Version to harvest, such as 3.2.3. Default: the provider's latest version in the
        registry cache, else the newest version that is not a pre-release on the registry.

    .PARAMETER BundlePath
        A bundle manifest (src\TerraformGraph\data\bundle.json, or a copy written by
        New-TerraformGraphBundle). Harvests every provider in its set and returns a summary.

    .PARAMETER ThrottleLimit
        Concurrent page requests per provider. Default 6.

    .PARAMETER Resume
        Skip a provider whose docs are already cached at the wanted version, without any
        network call (the version must be known from -Version or the registry cache). Use it
        to finish an interrupted bundle run.

    .PARAMETER Force
        Harvest and replace a version that is already cached. -Provider only.

    .PARAMETER PassThru
        Return one TerraformGraph.DocCache per provider. -Provider only; a bundle run always
        returns its summary.

    .EXAMPLE
        Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3 -PassThru

        Harvest the five null 3.2.3 pages and show the counts.

    .EXAMPLE
        Get-TerraformSchemaPack -Provider vmware/vsphere
        Update-TerraformProviderDocCache -Provider vmware/vsphere -PassThru -Verbose

        Cache the schema first so every resource and data source page is matched to a
        schema node Id, then harvest the docs at the latest version.

    .EXAMPLE
        $summary = Update-TerraformProviderDocCache -BundlePath .\src\TerraformGraph\data\bundle.json -Resume
        $summary.Failures | Format-Table ProviderAddress, Version, Error

        Harvest every provider in the bundled set that is not cached yet, then list the
        ones that failed and why.

    .OUTPUTS
        -Provider: none, or TerraformGraph.DocCache with -PassThru: ProviderAddress, Version,
        Path, Status (Harvested, Cached or Updated), DocCount, UnmatchedCount, SchemaVersion,
        Elapsed, Error. Default view is ProviderAddress, Version, Status, DocCount,
        UnmatchedCount, Elapsed.

        -BundlePath: TerraformGraph.DocHarvestSummary: BundlePath, ProviderCount, PageCount,
        UnmatchedCount, FailureCount, Elapsed, Providers (one DocCache row per provider,
        Status Failed with Error for a failure), Failures. Default view is ProviderCount,
        PageCount, UnmatchedCount, FailureCount, Elapsed.

    .LINK
        Get-TerraformProviderDoc

    .LINK
        Get-TerraformDocPack

    .LINK
        Get-TerraformGraphBundle
    #>
    [CmdletBinding(DefaultParameterSetName = 'Provider')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Provider')]
        [string[]]
        $Provider,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $Version,

        [Parameter(Mandatory, ParameterSetName = 'Bundle')]
        [string]
        $BundlePath,

        [ValidateRange(1, 64)]
        [int]
        $ThrottleLimit = 6,

        [switch]
        $Resume,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $Force,

        [Parameter(ParameterSetName = 'Provider')]
        [switch]
        $PassThru
    )

    if ($Resume -and $Force) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new('-Resume skips cached versions and -Force replaces them; pass one or the other.'),
            'ResumeWithForce',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null))
    }

    if ($PSCmdlet.ParameterSetName -eq 'Provider') {
        foreach ($name in $Provider) {
            try {
                $row = Invoke-TerraformProviderDocUpdate -Name $name -Version $Version -ThrottleLimit $ThrottleLimit -Force:$Force -Resume:$Resume
            }
            catch {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new($_.Exception, $_.FullyQualifiedErrorId, $_.CategoryInfo.Category, $_.TargetObject))
            }
            if ($PassThru) { $row }
        }
        return
    }

    $total = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $bundlePath = Resolve-TerraformGraphBundlePath -Path $BundlePath
        $bundle = Read-TerraformGraphBundle -Path $bundlePath
        $registry = Get-TerraformGraphBundleRegistry -BundlePath $bundlePath
        $selected = @(Resolve-TerraformGraphBundleProvider -Tier $bundle['tiers'] -Provider $bundle['providers'] -Exclude $bundle['exclude'] -Cache $registry)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.InvalidDataException]::new($_.Exception.Message),
            'BundleInvalid',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $BundlePath))
    }
    Write-Verbose "Bundle $bundlePath`: $($selected.Count) providers against the registry cache $($registry.Path) (harvested $($registry.HarvestedOn))"

    $rows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $selected.Count; $i++) {
        $registryProvider = $selected[$i]
        Write-Progress -Id 3 -Activity 'Harvesting bundle docs' -Status "$($registryProvider.Source) $($registryProvider.Latest) ($($i + 1) of $($selected.Count))" -PercentComplete (100 * $i / [math]::Max(1, $selected.Count))
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $row = Invoke-TerraformProviderDocUpdate -RegistryProvider $registryProvider -ThrottleLimit $ThrottleLimit -Force:(-not $Resume) -Resume:$Resume -Quiet
        }
        catch {
            $stopwatch.Stop()
            Write-Warning "Docs for $($registryProvider.ProviderAddress) $($registryProvider.Latest) failed: $($_.Exception.Message)"
            $row = [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.DocCache'
                ProviderAddress = $registryProvider.ProviderAddress
                Version         = [string]$registryProvider.Latest
                Path            = $null
                Status          = 'Failed'
                DocCount        = $null
                UnmatchedCount  = $null
                SchemaVersion   = $null
                Elapsed         = $stopwatch.Elapsed
                Error           = $_.Exception.Message
            }
        }
        Write-Verbose "$($row.ProviderAddress) $($row.Version): $($row.Status), $($row.DocCount) pages in $($row.Elapsed)"
        $rows.Add($row)
    }
    Write-Progress -Id 3 -Activity 'Harvesting bundle docs' -Completed
    $total.Stop()

    $failures = [object[]]@($rows | Where-Object Status -eq 'Failed')
    $pages = 0
    $unmatched = 0
    foreach ($row in $rows) { $pages += [int]$row.DocCount; $unmatched += [int]$row.UnmatchedCount }
    [pscustomobject]@{
        PSTypeName     = 'TerraformGraph.DocHarvestSummary'
        BundlePath     = $bundlePath
        ProviderCount  = $rows.Count
        PageCount      = $pages
        UnmatchedCount = $unmatched
        FailureCount   = $failures.Length
        Elapsed        = $total.Elapsed
        Providers      = $rows.ToArray()
        Failures       = $failures
    }
}

function Get-TerraformProviderDoc {
    <#
    .SYNOPSIS
        Gets provider documentation pages from the docs cache, by provider, Id, type or pipeline node.

    .DESCRIPTION
        Get-TerraformProviderDoc reads the local docs cache, never the network. Each page
        is a TerraformGraph.ProviderDoc whose Id is the schema node Id it documents:
        <address>/resource/<type>, <address>/data/<type>, <address> for the overview,
        <address>/guide/<slug> for guides, <address>/unmatched/<category>/<slug> for pages
        whose type is not in the schema.

        By provider: -Provider patterns (wildcards, matched by shape as in
        Get-TerraformSchemaCache) select cached providers at -Version or their newest cached
        version; with no -Provider every cached provider is read. A pattern with no cached
        docs is a terminating error that names Get-TerraformDocPack and
        Update-TerraformProviderDocCache.

        By pipeline: pipe SchemaNode objects (looked up by Id) or ResourceNode objects
        (looked up by SchemaId). A nested Block or Attribute node returns the page of its
        resource or data source; a Provider or provider config node returns the overview.
        Each page is returned once per call however many nodes point to it, so a resource
        graph's nodes give exactly the pages a configuration uses. A provider with no cached
        docs gets one warning; terraform.io/builtin providers have no registry docs and are
        skipped.

        -Id, -Type and -Category filter either way.

    .PARAMETER Provider
        Cached providers to read: 'azurerm', 'azure*', 'hashicorp/azurerm' or a full
        address. Default: every provider in the docs cache.

    .PARAMETER Version
        Cached version to read. Default: the newest cached version of each provider.

    .PARAMETER Id
        Only pages whose Id matches one of these patterns (wildcards allowed), such as
        'registry.terraform.io/hashicorp/azurerm/resource/azurerm_virtual_network'.

    .PARAMETER Type
        Only resource and data source pages whose type matches one of these patterns, such
        as 'azurerm_virtual_*'.

    .PARAMETER Category
        Only these categories: resources, data-sources, guides, overview.

    .PARAMETER Examples
        Return only the ```hcl and ```terraform code blocks of each page: Content holds
        them joined by a blank line and ExampleCount says how many there were (0 leaves
        Content empty).

    .PARAMETER InputObject
        A TerraformGraph.SchemaNode or TerraformGraph.ResourceNode (or anything with a
        SchemaId or Id property, or an Id string). Accepts pipeline input.

    .EXAMPLE
        Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema |
            Select-Object -ExpandProperty Nodes | Get-TerraformProviderDoc

        The pages for every resource and data source type the configuration uses, once
        each, from the cache only.

    .EXAMPLE
        Get-TerraformProviderDoc -Provider azurerm -Type 'azurerm_virtual_*' -Examples

        The HCL examples of every azurerm resource and data source whose type starts with
        azurerm_virtual_.

    .EXAMPLE
        Get-TerraformProviderDoc -Provider vsphere -Category guides, overview

        The vsphere overview and guides.

    .EXAMPLE
        Get-TerraformProviderDoc -Provider vsphere -Id '*/unmatched/*'

        Pages the registry has for vsphere whose type is not in the cached schema.

    .OUTPUTS
        TerraformGraph.ProviderDoc: Id, ProviderAddress, Version, Category, Title,
        Subcategory, Slug, Type (resources and data sources only), Content (raw markdown, or
        the joined examples with -Examples), ExampleCount (with -Examples). Default view is
        Id, Category, Title, Subcategory.

    .LINK
        Update-TerraformProviderDocCache

    .LINK
        Get-TerraformDocPack

    .LINK
        ConvertTo-TerraformResourceGraph
    #>
    [CmdletBinding(DefaultParameterSetName = 'Provider')]
    param(
        [Parameter(ParameterSetName = 'Provider', Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string[]]
        $Id,

        [string[]]
        $Type,

        [ValidateSet('resources', 'data-sources', 'guides', 'overview')]
        [string[]]
        $Category,

        [switch]
        $Examples,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [object]
        $InputObject
    )

    begin {
        $emitted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $emit = {
            param($Doc)
            if ($Category -and $Category -notcontains $Doc.Category) { return }
            if ($Id) {
                $hit = $false
                foreach ($pattern in $Id) { if ($Doc.Id -like $pattern) { $hit = $true; break } }
                if (-not $hit) { return }
            }
            if ($Type) {
                if (-not $Doc.Type) { return }
                $hit = $false
                foreach ($pattern in $Type) { if ($Doc.Type -like $pattern) { $hit = $true; break } }
                if (-not $hit) { return }
            }
            if (-not $emitted.Add($Doc.Id)) { return }
            $out = $Doc.PSObject.Copy()
            if ($Examples) {
                $blocks = @(Get-TerraformDocExample -Content $Doc.Content)
                $out.Content = $blocks -join "`n`n"
                $out.ExampleCount = $blocks.Count
            }
            $out
        }

        # Piped input with no -Provider is pipeline mode even if begin still sees the default
        # parameter set, which happens before the first object is bound.
        $pipelineMode = $PSCmdlet.ParameterSetName -eq 'InputObject' -or ($MyInvocation.ExpectingInput -and -not $PSBoundParameters.ContainsKey('Provider'))
        if (-not $pipelineMode) {
            if ($Provider) {
                try {
                    $entries = @(Resolve-TerraformSchemaCacheProvider -Name $Provider -Version $Version -Kind Docs)
                }
                catch {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
                        'ProviderDocNotCached',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Provider))
                }
            }
            else {
                $all = @(Get-TerraformSchemaCacheEntry -Kind Docs)
                $entries = @(foreach ($group in @($all | Group-Object { $_.ProviderAddress.ToLowerInvariant() })) {
                        if ($Version) { $group.Group | Where-Object Version -eq $Version | Select-Object -First 1 }
                        else { $group.Group[0] }
                    })
                if (-not $entries.Count) {
                    $versionText = if ($Version) { " at version $Version" } else { '' }
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Management.Automation.ItemNotFoundException]::new("No provider docs are cached$versionText. Download a docs pack with Get-TerraformDocPack -Provider <name>, or harvest them from the registry with Update-TerraformProviderDocCache -Provider <name>."),
                        'ProviderDocNotCached',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $null))
                }
            }
            foreach ($entry in $entries) {
                Write-Verbose "Reading docs for $($entry.ProviderAddress) $($entry.Version) from $($entry.Path)"
                foreach ($doc in (Read-TerraformProviderDocFile -Path $entry.Path).Docs) { & $emit $doc }
            }
        }
        else {
            $cachedEntries = $null
            $loaded = @{}
        }
    }

    process {
        if (-not $pipelineMode -or $null -eq $InputObject) { return }

        $key = if ($InputObject -is [string]) { $InputObject }
        elseif ($InputObject.PSObject.Properties['SchemaId'] -and $InputObject.SchemaId) { [string]$InputObject.SchemaId }
        elseif ($InputObject.PSObject.Properties['Id']) { [string]$InputObject.Id }
        if (-not $key) {
            Write-Verbose 'Skipping an input object with no SchemaId or Id'
            return
        }
        $segments = $key.Split('/')
        if ($segments.Count -lt 3) {
            Write-Verbose "Skipping '$key': not a schema node Id"
            return
        }
        # Doc Ids carry the lowercase address, as provider_schemas keys do.
        $address = ($segments[0..2] -join '/').ToLowerInvariant()
        $key = $address + $key.Substring($address.Length)
        if ($segments[0] -eq 'terraform.io' -and $segments[1] -eq 'builtin') {
            Write-Verbose "Skipping '$key': built-in providers have no registry docs"
            return
        }

        if (-not $loaded.ContainsKey($address)) {
            if ($null -eq $cachedEntries) { $cachedEntries = @(Get-TerraformSchemaCacheEntry -Kind Docs) }
            $versions = @($cachedEntries | Where-Object { $_.ProviderAddress.ToLowerInvariant() -eq $address })
            $entry = if ($Version) { $versions | Where-Object Version -eq $Version | Select-Object -First 1 } else { $versions | Select-Object -First 1 }
            if ($entry) {
                Write-Verbose "Reading docs for $($entry.ProviderAddress) $($entry.Version) from $($entry.Path)"
                $loaded[$address] = Read-TerraformProviderDocFile -Path $entry.Path
            }
            else {
                $versionText = if ($Version) { " $Version" } else { '' }
                $providerSource = (ConvertTo-TerraformProviderAddress -Provider $address).Source
                Write-Warning "No cached docs for $address$versionText. Download a docs pack with Get-TerraformDocPack -Provider $providerSource, or harvest them with Update-TerraformProviderDocCache -Provider $providerSource."
                $loaded[$address] = $null
            }
        }
        $file = $loaded[$address]
        if (-not $file) { return }

        # Exact Id, else the resource or data source a nested node belongs to, else the
        # overview for the provider and its config nodes.
        $doc = $null
        $candidates = @($key)
        if ($segments.Count -ge 5 -and $segments[3] -in 'resource', 'data') { $candidates += "$address/$($segments[3])/$($segments[4])" }
        if ($segments.Count -gt 3 -and $segments[3] -eq 'config') { $candidates += $address }
        foreach ($candidate in $candidates) {
            if ($file.ById.TryGetValue($candidate, [ref]$doc)) { break }
        }
        if ($doc) { & $emit $doc } else { Write-Verbose "No doc for '$key'" }
    }
}

function Get-TerraformDocPack {
    <#
    .SYNOPSIS
        Downloads provider docs packs into the local docs cache.

    .DESCRIPTION
        Get-TerraformDocPack is Get-TerraformSchemaPack for docs: it reads manifest.json
        from -Source, keeps the entries whose kind is docs, picks the entry for each
        provider (at -Version, or the newest version in the manifest), downloads the file,
        checks its sha256 and only then moves it into
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz. Pack files
        are named docs.<address-slug>.<version>.json.gz.

        A version that is already cached is skipped unless -Force is given. A provider with
        no docs entry is a terminating error that names Update-TerraformProviderDocCache,
        which harvests any registry provider's docs. For a private GitHub release source,
        set $env:GH_TOKEN (or $env:GITHUB_TOKEN), as for Get-TerraformSchemaPack.

    .PARAMETER Provider
        Providers to download, as for Get-TerraformSchemaPack: a name, namespace/name or
        full address; a bare name not in the manifest as written is matched by bare name; a
        wildcard resolves through the registry cache. Default: every docs entry.

    .PARAMETER Version
        Version to download. Default: the newest docs version in the manifest per provider.

    .PARAMETER Source
        Where manifest.json and the pack files are: an http(s) URL or a local directory.
        Default: https://github.com/JerryBalmer1/TerraformGraph/releases/latest/download.

    .PARAMETER Force
        Download and replace a version that is already cached.

    .PARAMETER PassThru
        Return one TerraformGraph.DocPack per provider.

    .EXAMPLE
        Get-TerraformDocPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere -PassThru

        Download three docs packs from the latest release.

    .EXAMPLE
        Get-TerraformDocPack -Provider vsphere -Source .\dist\schema-packs -PassThru

        Install a docs pack built locally with Invoke-Build BuildSchemaPack.

    .OUTPUTS
        None, or TerraformGraph.DocPack with -PassThru: ProviderAddress, Version, Path,
        Bytes, Status (Downloaded, Cached, or Updated). Default view is ProviderAddress,
        Version, Status, Bytes.

    .LINK
        Get-TerraformProviderDoc

    .LINK
        Update-TerraformProviderDocCache

    .LINK
        Get-TerraformSchemaPack
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string]
        $Source = $script:TerraformSchemaPackSource,

        [switch]
        $Force,

        [switch]
        $PassThru
    )

    Install-TerraformPack -Cmdlet $PSCmdlet -Kind Docs -Provider $Provider -Version $Version -Source $Source -Force:$Force -PassThru:$PassThru
}

function Get-TerraformDocCache {
    <#
    .SYNOPSIS
        Lists the provider docs in the local docs cache.

    .DESCRIPTION
        Get-TerraformDocCache lists the files in
        $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz, one
        TerraformGraph.CachedDoc per provider version, newest version first within each
        provider. It only reads, and never decompresses more than the start of each file.

    .PARAMETER Provider
        Only these providers. Patterns match by shape and may use wildcards, as for
        Get-TerraformSchemaCache. Default: every cached provider.

    .EXAMPLE
        Get-TerraformDocCache

        Every cached docs version with its page and unmatched counts.

    .OUTPUTS
        TerraformGraph.CachedDoc: ProviderAddress, Version, Path, Bytes, CachedOn (UTC),
        DocCount, UnmatchedCount (empty when the docs were not matched to a schema),
        HarvestedOn (as the file records it). Default view is ProviderAddress, Version,
        DocCount, UnmatchedCount, Bytes.

    .LINK
        Get-TerraformProviderDoc

    .LINK
        Get-TerraformSchemaCache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider
    )

    Select-TerraformSchemaCacheEntry -Entry @(Get-TerraformSchemaCacheEntry -Kind Docs) -Name $Provider
}

Register-ArgumentCompleter -CommandName Update-TerraformProviderDocCache -ParameterName Provider -ScriptBlock $script:TerraformRegistryProviderCompleter
Register-ArgumentCompleter -CommandName Update-TerraformProviderDocCache -ParameterName Version -ScriptBlock $script:TerraformRegistryVersionCompleter

# Classifier drawers: an optional overlay that groups resource and data source types into
# drawers (network, compute, storage, ...) so a view can collapse. Classifiers are opinions
# layered on facts: they never change a node's Id, the node count or the edges.
#   classifiers\drawers.json     the fixed drawer list map rows target
#   classifiers\map.json         provider subcategory label -> drawer, every row with a reason
#   classifiers\DECISIONS.md     append-only record of every judgement behind the two above
#   <root>\<address-slug>.<version>.json  one provider version's classifier, written by
#                                New-TerraformClassifier from the schema and docs caches
# Classifier lookup order: -ClassifierPath, then the user root, then the root bundled with
# the module; the first root that holds a provider wins. Nothing here touches the network.
# Tests repoint both roots with InModuleScope; the drawer list and default map paths stay.
$script:TerraformClassifierBundledRoot = Join-Path $PSScriptRoot 'classifiers'
$script:TerraformClassifierDrawersPath = Join-Path $PSScriptRoot 'classifiers' 'drawers.json'
$script:TerraformClassifierMapPath = Join-Path $PSScriptRoot 'classifiers' 'map.json'
$script:TerraformClassifierUserRoot = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'classifiers'

Update-TypeData -TypeName 'TerraformGraph.Classifier' -DefaultDisplayPropertySet ProviderAddress, Version, DocsVersion, TypeCount, FindingCount -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifiedType' -DefaultDisplayPropertySet Type, Kind, Subcategory, Drawer -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifierFinding' -DefaultDisplayPropertySet Type, Kind, Subcategory, Finding -Force
Update-TypeData -TypeName 'TerraformGraph.ClassifierBuild' -DefaultDisplayPropertySet ProviderAddress, Version, Status, TypeCount, FindingCount -Force
Update-TypeData -TypeName 'TerraformGraph.DrawerSummary' -DefaultDisplayPropertySet Drawer, TypeCount, InstanceCount -Force

function Read-TerraformClassifierJson {
    # Not exported. A classifier, map or drawers file as ordered dictionaries.
    param([string]$Path)

    [TerraformGraph.Json]::Deserialize([System.IO.File]::ReadAllText($Path), 64, $true)
}

function Format-TerraformClassifierJson {
    # Not exported. Indented JSON with LF line endings and a final newline, so a classifier
    # file is the same bytes on every machine and rerun.
    param($Document)

    ([TerraformGraph.Json]::Serialize($Document, 64, $false)).Replace("`r`n", "`n") + "`n"
}

function Get-TerraformClassifierDrawerName {
    # Not exported. Drawer names in drawers.json order from -Path, default the bundled file.
    param([string]$Path = $script:TerraformClassifierDrawersPath)

    [string[]]@(foreach ($drawer in @((Read-TerraformClassifierJson -Path $Path)['drawers'])) { [string]$drawer['name'] })
}

function Get-TerraformClassifierMapProblem {
    # Not exported. Lint for a parsed map.json: one message per problem, nothing when the map
    # is clean. Every row needs a provider ('*' or a full lowercase address), a subcategory, a
    # reason, a drawer from -Drawer other than unclassified (unclassified is the fallback, not
    # a target: leave the row out and record why in DECISIONS.md), addedOn as yyyy-MM-dd and
    # addedBy agent or jerry. source is optional: subcategory (the default) or prefix. A prefix
    # row names one provider (not '*') and its subcategory field holds a type prefix after the
    # provider token: lowercase words joined by single underscores, such as git or
    # branch_policy. The same provider, source and subcategory may appear once.
    param($Map, [string[]]$Drawer)

    if ($Map -isnot [System.Collections.IDictionary] -or -not $Map.Contains('rows')) {
        'map has no top-level rows array.'
        return
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rows = @($Map['rows'])
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $provider = [string]$row['provider']
        $subcategory = [string]$row['subcategory']
        $source = if ($row.Contains('source')) { [string]$row['source'] } else { 'subcategory' }
        $label = if ($source -ceq 'prefix') { "row $($i + 1) ($provider / prefix $subcategory)" } else { "row $($i + 1) ($provider / $subcategory)" }
        if ($provider -cne '*' -and ($provider -notmatch '^[^/\s]+/[^/\s]+/[^/\s]+$' -or $provider -cne $provider.ToLowerInvariant())) {
            "$label`: provider must be '*' or a full lowercase address such as registry.terraform.io/hashicorp/azurerm."
        }
        if ($source -cnotin 'subcategory', 'prefix') {
            "$label`: source '$source' must be subcategory or prefix."
        }
        elseif ($source -ceq 'prefix') {
            if ($provider -ceq '*') { "$label`: a prefix row needs a provider address; a type prefix means something only within one provider." }
            if ($subcategory -and $subcategory -cnotmatch '^[a-z0-9]+(_[a-z0-9]+)*$') {
                "$label`: prefix '$subcategory' must be lowercase words joined by single underscores, without the provider token (git, not azuredevops_git_)."
            }
        }
        if ([string]::IsNullOrWhiteSpace($subcategory)) { "$label has no subcategory." }
        if ([string]::IsNullOrWhiteSpace([string]$row['reason'])) { "$label has no reason." }
        $drawerName = [string]$row['drawer']
        if ($drawerName -ceq 'unclassified') {
            "$label`: unclassified is the fallback drawer, not a map target. Leave the row out and record why in DECISIONS.md."
        }
        elseif ($Drawer -cnotcontains $drawerName) {
            "$label`: drawer '$drawerName' is not in drawers.json."
        }
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$row['addedOn'], 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
            "$label`: addedOn '$($row['addedOn'])' is not a yyyy-MM-dd date."
        }
        if ([string]$row['addedBy'] -cnotin 'agent', 'jerry') {
            "$label`: addedBy '$($row['addedBy'])' must be agent or jerry."
        }
        if (-not $seen.Add("$provider`n$source`n$subcategory")) {
            "$label repeats an earlier row for the same provider and subcategory."
        }
    }
}

function Get-TerraformClassifierPrefixRow {
    # Not exported. The prefix row that places -Type of -Address, or $null: the type without
    # its provider token (the text before the first underscore) must equal the row's prefix
    # or start with the prefix and an underscore, so git matches azuredevops_git and
    # azuredevops_git_repository but not azuredevops_github. The longest matching prefix
    # wins; Read-TerraformClassifierMap keeps each provider's rows longest first.
    param($Map, [string]$Address, [string]$Type)

    $rows = $null
    if (-not $Map.Prefix.TryGetValue($Address, [ref]$rows)) { return $null }
    $cut = $Type.IndexOf('_')
    if ($cut -lt 0) { return $null }
    $rest = $Type.Substring($cut + 1)
    foreach ($row in $rows) {
        $prefix = [string]$row['subcategory']
        if ($rest -ceq $prefix -or $rest.StartsWith("$($prefix)_", [System.StringComparison]::Ordinal)) { return $row }
    }
    $null
}

function Get-TerraformClassifierPrefixProblem {
    # Not exported. Lint for -Address's prefix rows against its schema types: one message per
    # row whose prefix matches no type, so a typo or a renamed type cannot sit in the map
    # unnoticed.
    param($Map, [string]$Address, [string[]]$Type)

    $rows = $null
    if (-not $Map.Prefix.TryGetValue($Address, [ref]$rows)) { return }
    foreach ($row in $rows) {
        $prefix = [string]$row['subcategory']
        $hit = $false
        foreach ($name in $Type) {
            $cut = $name.IndexOf('_')
            if ($cut -lt 0) { continue }
            $rest = $name.Substring($cut + 1)
            if ($rest -ceq $prefix -or $rest.StartsWith("$($prefix)_", [System.StringComparison]::Ordinal)) { $hit = $true; break }
        }
        if (-not $hit) { "prefix row '$prefix' for $Address matches no resource or data source type in its schema." }
    }
}

function Read-TerraformClassifierMap {
    # Not exported. map.json at -Path, checked with Get-TerraformClassifierMapProblem against
    # drawers.json beside it (else the bundled drawers.json); throws listing every problem.
    # Lookup is keyed "<provider>`n<subcategory>" ignoring case. MapVersion is the first 12
    # hex digits of the sha256 of the map's compact JSON, so it follows the rows and not
    # whitespace or line endings.
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Classifier map '$Path' does not exist."
    }
    $map = Read-TerraformClassifierJson -Path $Path
    $drawersPath = Join-Path (Split-Path -Path $Path -Parent) 'drawers.json'
    if (-not (Test-Path -LiteralPath $drawersPath -PathType Leaf)) { $drawersPath = $script:TerraformClassifierDrawersPath }
    $drawers = Get-TerraformClassifierDrawerName -Path $drawersPath

    $problems = @(Get-TerraformClassifierMapProblem -Map $map -Drawer $drawers)
    if ($problems.Count) {
        throw "Classifier map '$Path' has $($problems.Count) problem(s):`n  $($problems -join "`n  ")"
    }

    $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $prefix = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($row in @($map['rows'])) {
        if ($row.Contains('source') -and [string]$row['source'] -ceq 'prefix') {
            $list = $null
            if (-not $prefix.TryGetValue([string]$row['provider'], [ref]$list)) {
                $list = [System.Collections.Generic.List[object]]::new()
                $prefix[[string]$row['provider']] = $list
            }
            $list.Add($row)
            continue
        }
        $lookup["$($row['provider'])`n$($row['subcategory'])"] = $row
    }
    foreach ($list in $prefix.Values) {
        $list.Sort([System.Comparison[object]] {
                param($a, $b)
                $byLength = ([string]$b['subcategory']).Length.CompareTo(([string]$a['subcategory']).Length)
                if ($byLength) { return $byLength }
                [string]::CompareOrdinal([string]$a['subcategory'], [string]$b['subcategory'])
            })
    }
    $compact = [System.Text.Encoding]::UTF8.GetBytes([TerraformGraph.Json]::Serialize($map, 64, $true))
    $hash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($compact)).ToLowerInvariant()
    [pscustomobject]@{
        Path       = (Resolve-Path -LiteralPath $Path).ProviderPath
        MapVersion = $hash.Substring(0, 12)
        Drawers    = $drawers
        Lookup     = $lookup
        Prefix     = $prefix
    }
}

function ConvertTo-TerraformClassifierDocument {
    # Not exported. The classifier document for one provider version. Types come from the
    # schema entry (resource_schemas, data_source_schemas), so a type with no doc page is a
    # NoDocPage finding rather than missing. Each type's subcategory is its doc page's; a
    # provider row in -Map wins over a '*' row. Doc pages with unmatched Ids document no
    # schema type and are left out. Types and findings are sorted by type, then kind
    # (data-source before resource), so the same inputs always give the same document.
    param([string]$Address, [string]$Version, [string]$DocsVersion, $SchemaEntry, [object[]]$Docs, $Map, [string]$GeneratedOn)

    $docById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($doc in $Docs) {
        if ($doc.Category -in 'resources', 'data-sources') { $docById[[string]$doc.Id] = $doc }
    }

    $types = [System.Collections.Generic.List[object]]::new()
    foreach ($section in @(
            @{ Key = 'resource_schemas';    Kind = 'resource';    Segment = 'resource' }
            @{ Key = 'data_source_schemas'; Kind = 'data-source'; Segment = 'data' }
        )) {
        $schemas = $SchemaEntry[$section.Key]
        if ($null -eq $schemas) { continue }
        foreach ($type in @($schemas.Keys)) {
            $doc = $null
            $null = $docById.TryGetValue("$Address/$($section.Segment)/$type", [ref]$doc)
            $subcategory = if ($doc -and -not [string]::IsNullOrEmpty([string]$doc.Subcategory)) { [string]$doc.Subcategory } else { $null }
            $row = $null
            $source = $null
            if ($subcategory) {
                if (-not $Map.Lookup.TryGetValue("$Address`n$subcategory", [ref]$row)) {
                    $null = $Map.Lookup.TryGetValue("*`n$subcategory", [ref]$row)
                }
                if ($row) { $source = 'subcategory' }
            }
            else {
                # Prefix rows place only types with no label: no doc page, or an empty
                # subcategory. A label the map does not place stays UnmappedSubcategory.
                $row = Get-TerraformClassifierPrefixRow -Map $Map -Address $Address -Type ([string]$type)
                if ($row) { $source = 'prefix' }
            }
            $finding = if ($row) { $null } elseif (-not $doc) { 'NoDocPage' } elseif (-not $subcategory) { 'NoSubcategory' } else { 'UnmappedSubcategory' }
            $types.Add([pscustomobject]@{
                Type        = [string]$type
                Kind        = $section.Kind
                Subcategory = $subcategory
                Drawer      = if ($row) { [string]$row['drawer'] } else { 'unclassified' }
                Source      = $source
                Finding     = $finding
            })
        }
    }
    $types.Sort([System.Comparison[object]] {
            param($a, $b)
            $byType = [string]::CompareOrdinal($a.Type, $b.Type)
            if ($byType) { return $byType }
            [string]::CompareOrdinal($a.Kind, $b.Kind)
        })

    [ordered]@{
        provider    = $Address
        version     = $Version
        docsVersion = $DocsVersion
        generatedOn = $GeneratedOn
        mapVersion  = $Map.MapVersion
        source      = if ($types | Where-Object Source -ceq 'prefix') { 'subcategory,prefix' } else { 'subcategory' }
        types       = [object[]]@(foreach ($item in $types) {
                [ordered]@{ type = $item.Type; kind = $item.Kind; subcategory = $item.Subcategory; drawer = $item.Drawer; source = $item.Source }
            })
        findings    = [object[]]@(foreach ($item in $types) {
                if ($item.Finding) { [ordered]@{ type = $item.Type; kind = $item.Kind; subcategory = $item.Subcategory; finding = $item.Finding } }
            })
    }
}

function Get-TerraformClassifierEntry {
    # Not exported. Every classifier file in lookup order, highest precedence first:
    # -ClassifierPath (a file, or the *.json files in a folder), the user root, the bundled
    # root. Rank is that position, 0 highest. provider and version are read from the start
    # of each file, never its name (address slugs contain dots and dashes); files that do
    # not start with them, such as drawers.json and map.json, are skipped.
    param([string]$ClassifierPath)

    $rank = 0
    foreach ($source in @($ClassifierPath, $script:TerraformClassifierUserRoot, $script:TerraformClassifierBundledRoot)) {
        $files = if (-not $source) { @() }
        elseif (Test-Path -LiteralPath $source -PathType Leaf) { @(Get-Item -LiteralPath $source) }
        elseif (Test-Path -LiteralPath $source -PathType Container) { @(Get-ChildItem -LiteralPath $source -Filter '*.json' -File | Sort-Object Name) }
        else { @() }
        foreach ($file in $files) {
            try {
                $reader = [System.IO.StreamReader]::new($file.FullName, [System.Text.Encoding]::UTF8)
                try {
                    $buffer = [char[]]::new(1024)
                    $head = [string]::new($buffer, 0, $reader.ReadBlock($buffer, 0, 1024))
                }
                finally {
                    $reader.Dispose()
                }
            }
            catch {
                Write-Verbose "Skipping $($file.FullName): $($_.Exception.Message)"
                continue
            }
            if ($head -match '^\s*\{\s*"provider"\s*:\s*"([^"]+)"\s*,\s*"version"\s*:\s*"([^"]+)"') {
                [pscustomobject]@{ ProviderAddress = $Matches[1]; Version = $Matches[2]; Path = $file.FullName; Rank = $rank }
            }
        }
        $rank++
    }
}

function Find-TerraformClassifierEntry {
    # Not exported. The classifier entry for -Address: with -Version, the highest-ranked file
    # at that version; without, the newest version in the highest-ranked root that holds the
    # provider at all, so an override folder wins even over a newer bundled version. $null
    # when there is none.
    param([object[]]$Entry, [string]$Address, [string]$Version)

    $mine = @($Entry | Where-Object { $_.ProviderAddress -eq $Address } | Sort-Object Rank -Stable)
    if (-not $mine.Count) { return $null }
    if ($Version) { return $mine | Where-Object Version -eq $Version | Select-Object -First 1 }
    $top = $mine[0].Rank
    @(Sort-TerraformRegistryVersion -Versions @($mine | Where-Object Rank -eq $top))[0].Record
}

function Resolve-TerraformClassifier {
    # Not exported. One classifier entry per provider the -Name patterns select (every
    # provider with a classifier when there are none), matched by shape as in
    # Get-TerraformSchemaCache, sorted by address. Throws when a pattern matches nothing or
    # -Version is not there; callers turn that into their own terminating error.
    param([string[]]$Name, [string]$Version, [string]$ClassifierPath)

    $entries = @(Get-TerraformClassifierEntry -ClassifierPath $ClassifierPath)
    $addresses = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Name) {
        foreach ($pattern in $Name) {
            $found = @(Select-TerraformSchemaCacheEntry -Entry $entries -Name $pattern)
            if (-not $found.Count) {
                throw "No classifier matches '$pattern'. Generate one with New-TerraformClassifier -Provider $pattern, or pass -ClassifierPath."
            }
            foreach ($item in $found) { $null = $addresses.Add($item.ProviderAddress) }
        }
    }
    else {
        foreach ($item in $entries) { $null = $addresses.Add($item.ProviderAddress) }
    }

    foreach ($address in $addresses) {
        $entry = Find-TerraformClassifierEntry -Entry $entries -Address $address -Version $Version
        if (-not $entry) {
            $available = @($entries | Where-Object ProviderAddress -eq $address | ForEach-Object Version | Select-Object -Unique)
            throw "No classifier for $address $Version (available: $($available -join ', ')). Generate it with New-TerraformClassifier -Provider $address -Version $Version."
        }
        $entry
    }
}

function Read-TerraformClassifierFile {
    # Not exported. One classifier file as TerraformGraph.Classifier with
    # TerraformGraph.ClassifiedType Types and TerraformGraph.ClassifierFinding Findings.
    param([string]$Path)

    $document = Read-TerraformClassifierJson -Path $Path
    $address = [string]$document['provider']
    $version = [string]$document['version']
    $types = [object[]]@(foreach ($item in @($document['types'])) {
            [pscustomobject]@{
                PSTypeName  = 'TerraformGraph.ClassifiedType'
                Type        = [string]$item['type']
                Kind        = [string]$item['kind']
                Subcategory = $item['subcategory']
                Drawer      = [string]$item['drawer']
                Source      = $item['source']
            }
        })
    $findings = [object[]]@(foreach ($item in @($document['findings'])) {
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.ClassifierFinding'
                ProviderAddress = $address
                Version         = $version
                Type            = [string]$item['type']
                Kind            = [string]$item['kind']
                Subcategory     = $item['subcategory']
                Finding         = [string]$item['finding']
            }
        })
    [pscustomobject]@{
        PSTypeName      = 'TerraformGraph.Classifier'
        ProviderAddress = $address
        Version         = $version
        DocsVersion     = [string]$document['docsVersion']
        GeneratedOn     = [string]$document['generatedOn']
        MapVersion      = [string]$document['mapVersion']
        Source          = [string]$document['source']
        Types           = $types
        Findings        = $findings
        TypeCount       = $types.Length
        FindingCount    = $findings.Length
        Path            = $Path
    }
}

function Get-TerraformClassifierOverlay {
    # Not exported. For -Classify on a graph: per provider address, a lookup
    # "<kind>|<type>" -> ClassifiedType (kind resource or data-source), or $null when no
    # classifier is found, which gets one warning (terraform.io/builtin providers have no
    # registry docs and are skipped silently). -Version maps an address to the schema
    # version the graph came from; that classifier version is preferred, else the one the
    # lookup order gives. Order is the drawers.json order, for the Drawers summary.
    param([string[]]$Address, [hashtable]$Version = @{}, [string]$ClassifierPath)

    $entries = @(Get-TerraformClassifierEntry -ClassifierPath $ClassifierPath)
    $byAddress = @{}
    foreach ($providerAddress in @($Address | Select-Object -Unique)) {
        $wanted = $Version[$providerAddress]
        $entry = if ($wanted) { Find-TerraformClassifierEntry -Entry $entries -Address $providerAddress -Version $wanted }
        if (-not $entry) {
            $entry = Find-TerraformClassifierEntry -Entry $entries -Address $providerAddress
            if ($entry -and $wanted) { Write-Verbose "No classifier for $providerAddress $wanted; using $($entry.Version) from $($entry.Path)" }
        }
        if (-not $entry) {
            if (-not $providerAddress.StartsWith('terraform.io/builtin/', [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Warning "No classifier for $providerAddress, so its types are in the unclassified drawer. Generate one with New-TerraformClassifier -Provider $providerAddress, or pass -ClassifierPath."
            }
            $byAddress[$providerAddress] = $null
            continue
        }
        Write-Verbose "Classifying $providerAddress with $($entry.Path)"
        $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($type in (Read-TerraformClassifierFile -Path $entry.Path).Types) { $lookup["$($type.Kind)|$($type.Type)"] = $type }
        $byAddress[$providerAddress] = $lookup
    }
    [pscustomobject]@{ ByAddress = $byAddress; Order = Get-TerraformClassifierDrawerName }
}

function New-TerraformDrawerSummary {
    # Not exported. TerraformGraph.DrawerSummary rows from -Item records (Drawer, TypeKey),
    # in -Order with unknown drawers after it by name. TypeCount is the distinct TypeKeys;
    # InstanceCount is the record count with -Instances, else $null (not known).
    param([object[]]$Item, [string[]]$Order, [switch]$Instances)

    $groups = @{}
    foreach ($record in $Item) {
        $group = $groups[$record.Drawer]
        if (-not $group) {
            $group = @{ Types = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal); Instances = 0 }
            $groups[$record.Drawer] = $group
        }
        $null = $group.Types.Add([string]$record.TypeKey)
        $group.Instances++
    }
    $names = @($groups.Keys) | Sort-Object { $index = [array]::IndexOf($Order, $_); if ($index -lt 0) { [int]::MaxValue } else { $index } }, { $_ }
    foreach ($name in $names) {
        [pscustomobject]@{
            PSTypeName    = 'TerraformGraph.DrawerSummary'
            Drawer        = $name
            TypeCount     = $groups[$name].Types.Count
            InstanceCount = if ($Instances) { $groups[$name].Instances } else { $null }
        }
    }
}

function Add-TerraformResourceGraphClassification {
    # Not exported. -Classify for ConvertTo-TerraformResourceGraph: every ResourceNode gets
    # Drawer and Subcategory from its provider's classifier by Type and Kind (unclassified
    # when the classifier lacks the type or there is none), and the graph gets Drawers with
    # TypeCount (distinct SchemaIds) and InstanceCount (blocks). Ids, nodes and edges are
    # untouched.
    param($Graph, [hashtable]$Version, [string]$ClassifierPath)

    $overlay = Get-TerraformClassifierOverlay -Address @($Graph.Providers.Keys) -Version $Version -ClassifierPath $ClassifierPath
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($node in $Graph.Nodes) {
        $kind = $node.Kind -eq 'DataSource' ? 'data-source' : 'resource'
        $lookup = $overlay.ByAddress[[string]$node.ProviderAddress]
        $classified = $null
        if ($lookup) { $null = $lookup.TryGetValue("$kind|$($node.Type)", [ref]$classified) }
        $drawer = if ($classified) { $classified.Drawer } else { 'unclassified' }
        $node.PSObject.Properties.Add([psnoteproperty]::new('Drawer', $drawer))
        $node.PSObject.Properties.Add([psnoteproperty]::new('Subcategory', $(if ($classified) { $classified.Subcategory } else { $null })))
        $items.Add([pscustomobject]@{ Drawer = $drawer; TypeKey = $node.SchemaId })
    }
    $Graph.PSObject.Properties.Add([psnoteproperty]::new('Drawers', [object[]]@(New-TerraformDrawerSummary -Item $items -Order $overlay.Order -Instances)))
}

function New-TerraformClassifier {
    <#
    .SYNOPSIS
        Writes a provider version's classifier: every resource and data source type with its subcategory and drawer.

    .DESCRIPTION
        New-TerraformClassifier reads one provider version from the local schema cache and
        the docs cache, takes each resource and data source type from the schema, looks up
        its doc page's subcategory (the provider's own label, such as "Key Vault" or
        "Host and Cluster Management") and maps that label to a drawer through the map
        file. A row for the provider wins over a '*' row. A type with no label (no doc page
        or an empty subcategory) can still be placed by a prefix row: a map row with
        source "prefix" whose subcategory field is a type prefix after the provider token
        (git places azuredevops_git and azuredevops_git_*; the longest prefix wins). It
        never touches the network.

        A type the map cannot place is in the unclassified drawer and is listed in findings:
            NoDocPage            the schema has the type but the docs have no page for it
            NoSubcategory        the page has an empty subcategory
            UnmappedSubcategory  the map has no row for the page's subcategory
        unclassified is a legitimate drawer, not an error.

        The file is <OutputPath>\<address-slug>.<version>.json:
            { provider, version, docsVersion, generatedOn, mapVersion,
              source: "subcategory" (or "subcategory,prefix" when a prefix row placed a type),
              types: [ { type, kind, subcategory, drawer, source: subcategory|prefix|null } ],
              findings: [ { type, kind, subcategory, finding } ] }
        version is the schema version. Docs are read at the same version, else the newest
        cached docs with a warning, and docsVersion says which. mapVersion is a hash of the
        map's rows. Types and findings are sorted by type, then kind. When a rerun gives
        the same content, the file and its generatedOn are left as they are, so reruns are
        byte-identical.

        The map is checked first: a row with no reason, a drawer not in drawers.json, a
        row targeting unclassified, a source other than subcategory or prefix, a '*' prefix
        row, or a repeated provider, source and subcategory stops the command before
        anything is read; a prefix row that matches no type in the provider's cached schema
        stops it once the schema is read. Judgements behind the map are in
        classifiers\DECISIONS.md.

    .PARAMETER Provider
        Providers to classify: 'vsphere', 'vmware/vsphere' or a full address. A value with
        a wildcard is resolved against the provider registry cache and must match exactly
        one provider. The schema and docs must be cached.

    .PARAMETER Version
        Schema version to classify. Default: the newest cached schema of each provider.

    .PARAMETER MapPath
        Map file. Default: classifiers\map.json in the module folder. drawers.json beside
        it is the drawer list, else the bundled one.

    .PARAMETER OutputPath
        Folder to write to. Default: $env:LOCALAPPDATA\TerraformGraph\classifiers, which
        Get-TerraformClassifier and -Classify search before the classifiers bundled with the
        module.

    .PARAMETER PassThru
        Return one TerraformGraph.ClassifierBuild per provider.

    .EXAMPLE
        New-TerraformClassifier -Provider vmware/vsphere -PassThru

        Classify the newest cached vsphere schema into the user classifier folder and show
        the type and finding counts.

    .EXAMPLE
        New-TerraformClassifier -Provider azurerm -MapPath .\my-map.json -OutputPath .\classifiers -PassThru

        Classify with your own map into a folder you then pass as -ClassifierPath.

    .OUTPUTS
        None, or TerraformGraph.ClassifierBuild with -PassThru: ProviderAddress, Version,
        DocsVersion, Path, Status (Written, Updated or Unchanged), TypeCount, FindingCount,
        Drawers (ordered drawer -> type count). Default view is ProviderAddress, Version,
        Status, TypeCount, FindingCount.

    .LINK
        Get-TerraformClassifier

    .LINK
        Get-TerraformClassifierFinding
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [string]
        $MapPath = $script:TerraformClassifierMapPath,

        [string]
        $OutputPath = $script:TerraformClassifierUserRoot,

        [switch]
        $PassThru
    )

    try {
        $map = Read-TerraformClassifierMap -Path $MapPath
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.InvalidDataException]::new($_.Exception.Message),
            'ClassifierMapInvalid',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $MapPath))
    }
    Write-Verbose "Map $($map.Path), mapVersion $($map.MapVersion)"

    foreach ($name in $Provider) {
        try {
            $parsed = if ([WildcardPattern]::ContainsWildcardCharacters($name)) {
                ConvertTo-TerraformProviderAddress -Provider (Resolve-TerraformRegistryProvider -Name $name).ProviderAddress
            }
            else {
                ConvertTo-TerraformProviderAddress -Provider $name
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new($_.Exception.Message),
                'RegistryProviderNotResolved',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $name))
        }
        $address = $parsed.Address.ToLowerInvariant()

        $schemaEntries = @(Get-TerraformSchemaCacheEntry | Where-Object { $_.ProviderAddress -eq $address })
        $schemaEntry = if ($Version) { $schemaEntries | Where-Object Version -eq $Version | Select-Object -First 1 } else { $schemaEntries | Select-Object -First 1 }
        if (-not $schemaEntry) {
            $cachedText = if ($schemaEntries.Count) { " (cached: $(@($schemaEntries.Version) -join ', '))" } else { '' }
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.Management.Automation.ItemNotFoundException]::new("No cached schema for $address$(if ($Version) { " $Version" })$cachedText. Download a schema pack with Get-TerraformSchemaPack -Provider $($parsed.Source), or harvest it with Get-TerraformProviderSchema -Provider $($parsed.Source) -SaveToCache."),
                'SchemaNotCached',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $name))
        }
        $docEntries = @(Get-TerraformSchemaCacheEntry -Kind Docs | Where-Object { $_.ProviderAddress -eq $address })
        $docEntry = $docEntries | Where-Object Version -eq $schemaEntry.Version | Select-Object -First 1
        if (-not $docEntry) {
            $docEntry = $docEntries | Select-Object -First 1
            if (-not $docEntry) {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.Management.Automation.ItemNotFoundException]::new("No cached docs for $address. Download a docs pack with Get-TerraformDocPack -Provider $($parsed.Source), or harvest them with Update-TerraformProviderDocCache -Provider $($parsed.Source) -Version $($schemaEntry.Version)."),
                    'ProviderDocNotCached',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $name))
            }
            Write-Warning "Docs for $address $($schemaEntry.Version) are not cached; classifying with the cached $($docEntry.Version) docs. Run Update-TerraformProviderDocCache -Provider $($parsed.Source) -Version $($schemaEntry.Version) to match the schema."
        }

        Write-Verbose "Classifying $address $($schemaEntry.Version) with docs $($docEntry.Version)"
        $schemas = (Read-TerraformSchemaCache -Path $schemaEntry.Path)['provider_schemas']
        $key = @($schemas.Keys) | Where-Object { $_ -eq $address } | Select-Object -First 1
        $docs = (Read-TerraformProviderDocFile -Path $docEntry.Path).Docs
        $schemaTypes = [string[]]@(
            foreach ($section in 'resource_schemas', 'data_source_schemas') { if ($schemas[$key][$section]) { $schemas[$key][$section].Keys } }
        )
        $prefixProblems = @(Get-TerraformClassifierPrefixProblem -Map $map -Address $address -Type $schemaTypes)
        if ($prefixProblems.Count) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.IO.InvalidDataException]::new("Classifier map '$($map.Path)' has $($prefixProblems.Count) problem(s) against the cached $address $($schemaEntry.Version) schema:`n  $($prefixProblems -join "`n  ")"),
                'ClassifierMapInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $MapPath))
        }
        $document = ConvertTo-TerraformClassifierDocument -Address $address -Version $schemaEntry.Version -DocsVersion $docEntry.Version `
            -SchemaEntry $schemas[$key] -Docs $docs -Map $map -GeneratedOn $null

        $slug = $address.Replace('/', '-')
        $path = Join-Path $OutputPath "$slug.$($schemaEntry.Version).json"
        $now = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        $status = 'Written'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $status = 'Updated'
            $existingText = [System.IO.File]::ReadAllText($path)
            try {
                $document.generatedOn = [string]([TerraformGraph.Json]::Deserialize($existingText, 64, $true))['generatedOn']
                # A git checkout with core.autocrlf may have turned LF into CRLF; that is not a change.
                if ((Format-TerraformClassifierJson -Document $document) -ceq $existingText.Replace("`r`n", "`n")) { $status = 'Unchanged' }
            }
            catch {
                Write-Verbose "Replacing unreadable $path`: $($_.Exception.Message)"
            }
        }

        if ($status -ne 'Unchanged') {
            $document.generatedOn = $now
            $null = New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop
            $temporary = Join-Path $OutputPath ".$([guid]::NewGuid().ToString('n')).tmp"
            try {
                [System.IO.File]::WriteAllText($temporary, (Format-TerraformClassifierJson -Document $document), [System.Text.UTF8Encoding]::new($false))
                Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
            }
            finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
            }
        }
        Write-Verbose "$status $path`: $(@($document.types).Count) types, $(@($document.findings).Count) findings"

        if ($PassThru) {
            $drawers = [ordered]@{}
            foreach ($drawerName in $map.Drawers) {
                $count = @($document.types | Where-Object { $_.drawer -ceq $drawerName }).Count
                if ($count) { $drawers[$drawerName] = $count }
            }
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.ClassifierBuild'
                ProviderAddress = $address
                Version         = $schemaEntry.Version
                DocsVersion     = $docEntry.Version
                Path            = (Resolve-Path -LiteralPath $path).ProviderPath
                Status          = $status
                TypeCount       = @($document.types).Count
                FindingCount    = @($document.findings).Count
                Drawers         = $drawers
            }
        }
    }
}

function Get-TerraformClassifier {
    <#
    .SYNOPSIS
        Gets provider classifiers: each resource and data source type with its subcategory and drawer.

    .DESCRIPTION
        Get-TerraformClassifier reads classifier files written by New-TerraformClassifier
        (or Invoke-Build BuildClassifier) and returns one TerraformGraph.Classifier per
        provider. It never touches the network.

        Classifiers are looked up in order: -ClassifierPath, then
        $env:LOCALAPPDATA\TerraformGraph\classifiers, then the classifiers folder bundled
        with the module. Without -Version, the first of those that holds a provider at all
        supplies it, at its newest version there, so your own classifier wins over a newer
        bundled one. With -Version, the first file at that version wins.

    .PARAMETER Provider
        Providers to return. Patterns match by shape and may use wildcards, as for
        Get-TerraformSchemaCache: 'azurerm', 'azure*', 'hashicorp/azurerm' or a full
        address. Default: every provider with a classifier. A pattern with no classifier is
        a terminating error that names New-TerraformClassifier.

    .PARAMETER Version
        Classifier version (the schema version it was generated from). Default: the newest
        in the first folder that has the provider.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before the user and bundled
        folders.

    .EXAMPLE
        Get-TerraformClassifier -Provider vsphere

        The bundled vsphere classifier: ProviderAddress, Version, DocsVersion, TypeCount,
        FindingCount.

    .EXAMPLE
        (Get-TerraformClassifier -Provider azurerm).Types | Group-Object Drawer | Sort-Object Count -Descending

        How many azurerm types fall in each drawer.

    .OUTPUTS
        TerraformGraph.Classifier: ProviderAddress, Version, DocsVersion, GeneratedOn,
        MapVersion, Source, Types (TerraformGraph.ClassifiedType: Type, Kind, Subcategory,
        Drawer, Source: subcategory or prefix, the kind of map row that placed the type),
        Findings (TerraformGraph.ClassifierFinding), TypeCount, FindingCount, Path.
        Default view is ProviderAddress, Version, DocsVersion, TypeCount, FindingCount.

    .LINK
        New-TerraformClassifier

    .LINK
        Get-TerraformClassifierFinding
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    try {
        $entries = @(Resolve-TerraformClassifier -Name $Provider -Version $Version -ClassifierPath $ClassifierPath)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
            'ClassifierNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Provider))
    }
    foreach ($entry in $entries) { Read-TerraformClassifierFile -Path $entry.Path }
}

function Get-TerraformClassifierFinding {
    <#
    .SYNOPSIS
        Gets the types a classifier could not place in a drawer, and why.

    .DESCRIPTION
        Get-TerraformClassifierFinding returns the findings of the classifiers
        Get-TerraformClassifier selects, one TerraformGraph.ClassifierFinding per type in
        the unclassified drawer:
            NoDocPage            the schema has the type but the docs have no page for it
            NoSubcategory        the page has an empty subcategory
            UnmappedSubcategory  the map has no row for the page's subcategory
        Findings are what to look at before adding map rows (with a reason) or recording a
        decision in classifiers\DECISIONS.md not to.

    .PARAMETER Provider
        Providers, as for Get-TerraformClassifier. Default: every provider with a
        classifier.

    .PARAMETER Version
        Classifier version. Default: as for Get-TerraformClassifier.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before the user and bundled
        folders.

    .EXAMPLE
        Get-TerraformClassifierFinding -Provider azurerm

        The azurerm types in the unclassified drawer as a table of Type, Kind, Subcategory,
        Finding.

    .EXAMPLE
        Get-TerraformClassifierFinding -Provider azurerm | Group-Object Subcategory | Sort-Object Count -Descending

        Which unmapped subcategories hold the most types.

    .OUTPUTS
        TerraformGraph.ClassifierFinding: ProviderAddress, Version, Type, Kind,
        Subcategory, Finding. Default view is a table of Type, Kind, Subcategory, Finding.

    .LINK
        Get-TerraformClassifier

    .LINK
        New-TerraformClassifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    try {
        $entries = @(Resolve-TerraformClassifier -Name $Provider -Version $Version -ClassifierPath $ClassifierPath)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
            'ClassifierNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Provider))
    }
    foreach ($entry in $entries) { (Read-TerraformClassifierFile -Path $entry.Path).Findings }
}

Register-ArgumentCompleter -CommandName New-TerraformClassifier -ParameterName Provider -ScriptBlock $script:TerraformRegistryProviderCompleter

# Bundle manifest: data\bundle.json names the provider set the bundled data covers (registry
# tiers, extra provider addresses, exclusions), the registry cache it was resolved against,
# and one entry per provider recording what the local docs and schema caches and the bundled
# classifiers held when it was written:
#   { formatVersion, tiers, providers, exclude, registry: { harvestedOn, providerCount },
#     entries: [ { provider, version, docsVersion, schemaVersion, classifierVersion, harvestedOn } ] }
# New-TerraformGraphBundle writes one, Update-TerraformProviderDocCache -BundlePath and
# Get-TerraformSubcategorySurvey -BundlePath read its provider set, and
# Test-TerraformGraphBundle checks it against its sources. A bundle resolves against the
# registry.json in its own folder (data\registry.json for the bundled file), else the registry
# cache Get-TerraformRegistryCache returns. Tests repoint both paths with InModuleScope.
$script:TerraformGraphBundleBundledPath = Join-Path $PSScriptRoot 'data' 'bundle.json'
$script:TerraformGraphBundleUserPath = Join-Path ($env:LOCALAPPDATA ?? [Environment]::GetFolderPath('LocalApplicationData')) 'TerraformGraph' 'bundle.json'
$script:TerraformGraphBundleFormatVersion = 1
$script:TerraformGraphBundleTiers = @('official', 'partner', 'community')

Update-TypeData -TypeName 'TerraformGraph.Bundle' -DefaultDisplayPropertySet Path, Tiers, Providers, Exclude, RegistryHarvestedOn, EntryCount -Force
Update-TypeData -TypeName 'TerraformGraph.BundleEntry' -DefaultDisplayPropertySet ProviderAddress, Version, DocsVersion, SchemaVersion, ClassifierVersion, HarvestedOn -Force
Update-TypeData -TypeName 'TerraformGraph.BundleCheck' -DefaultDisplayPropertySet Item, Status, Detail -Force
Update-TypeData -TypeName 'TerraformGraph.DocHarvestSummary' -DefaultDisplayPropertySet ProviderCount, PageCount, UnmatchedCount, FailureCount, Elapsed -Force
Update-TypeData -TypeName 'TerraformGraph.SubcategorySurveyRow' -DefaultDisplayPropertySet ProviderAddress, Subcategory, ResourceCount, DataSourceCount, Status -Force

function Resolve-TerraformGraphBundlePath {
    # Not exported. The bundle file to read: -Path (which must exist), else the user copy when
    # there is one, else the bundled file. Throws when there is none.
    param([string]$Path)

    if ($Path) {
        $full = [System.IO.Path]::GetFullPath($Path, (Get-Location -PSProvider FileSystem).ProviderPath)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Bundle '$Path' does not exist." }
        return $full
    }
    foreach ($candidate in @($script:TerraformGraphBundleUserPath, $script:TerraformGraphBundleBundledPath)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    throw 'No bundle manifest found. Pass -BundlePath, or write one with New-TerraformGraphBundle.'
}

function Get-TerraformGraphBundleProblem {
    # Not exported. Lint for a parsed bundle: one message per problem, nothing when clean.
    param($Bundle)

    if ($Bundle -isnot [System.Collections.IDictionary]) {
        'the bundle is not a JSON object.'
        return
    }
    if ([string]$Bundle['formatVersion'] -ne [string]$script:TerraformGraphBundleFormatVersion) {
        "formatVersion '$($Bundle['formatVersion'])' is not $($script:TerraformGraphBundleFormatVersion)."
    }
    foreach ($tier in @($Bundle['tiers'])) {
        if ($null -ne $tier -and $script:TerraformGraphBundleTiers -cnotcontains [string]$tier) { "tier '$tier' is not official, partner or community." }
    }
    foreach ($key in 'providers', 'exclude') {
        foreach ($value in @($Bundle[$key])) {
            if ($null -ne $value -and [string]::IsNullOrWhiteSpace([string]$value)) { "$key has an empty value." }
        }
    }
    foreach ($entry in @($Bundle['entries'])) {
        if ($null -ne $entry -and ($entry -isnot [System.Collections.IDictionary] -or [string]::IsNullOrWhiteSpace([string]$entry['provider']))) { 'an entry has no provider.' }
    }
}

function Read-TerraformGraphBundle {
    # Not exported. A bundle file as an ordered dictionary with tiers, providers and exclude
    # as string arrays and entries as an array; throws listing every problem.
    param([string]$Path)

    $document = Read-TerraformClassifierJson -Path $Path
    $problems = @(Get-TerraformGraphBundleProblem -Bundle $document)
    if ($problems.Count) {
        throw "Bundle '$Path' has $($problems.Count) problem(s):`n  $($problems -join "`n  ")"
    }
    foreach ($key in 'tiers', 'providers', 'exclude') {
        $document[$key] = [string[]]@($document[$key] | Where-Object { $null -ne $_ })
    }
    $document['entries'] = [object[]]@($document['entries'] | Where-Object { $null -ne $_ })
    $document
}

function Get-TerraformGraphBundleRegistry {
    # Not exported. The registry cache a bundle resolves against: registry.json in the same
    # folder as -BundlePath (data\registry.json for the bundled bundle.json, the user registry
    # cache for the user copy), else the one Get-TerraformRegistryCache returns.
    param([string]$BundlePath)

    $beside = Join-Path (Split-Path -Path $BundlePath -Parent) 'registry.json'
    if (Test-Path -LiteralPath $beside -PathType Leaf) { return Read-TerraformRegistryCacheFile -Path $beside }
    $cache = Get-TerraformRegistryCache
    if (-not $cache) { throw 'There is no registry cache to resolve the bundle against. Run Update-TerraformRegistryCache.' }
    $cache
}

function Resolve-TerraformGraphBundleProvider {
    # Not exported. The registry providers a bundle covers, sorted by address: every provider
    # in -Tier, plus every match of each -Provider pattern (matched by shape, as
    # Get-TerraformRegistryProvider -Name; a pattern with no match throws), less any provider
    # an -Exclude pattern matches.
    param([string[]]$Tier, [string[]]$Provider, [string[]]$Exclude, $Cache)

    $selected = [System.Collections.Generic.SortedDictionary[string, object]]::new([System.StringComparer]::Ordinal)
    if ($Tier) {
        foreach ($item in @(Select-TerraformRegistryProvider -Cache $Cache -Tier $Tier)) { $selected[$item.ProviderAddress] = $item }
    }
    foreach ($pattern in $Provider) {
        $found = @(Select-TerraformRegistryProvider -Cache $Cache -Name $pattern)
        if (-not $found.Count) {
            throw "'$pattern' matches no provider in the registry cache $($Cache.Path) (harvested $($Cache.HarvestedOn)). Run Update-TerraformRegistryCache, or fix the pattern."
        }
        foreach ($item in $found) { $selected[$item.ProviderAddress] = $item }
    }
    if ($Exclude) {
        foreach ($item in @($selected.Values)) {
            if (@(Select-TerraformRegistryProvider -Cache ([pscustomobject]@{ Providers = @($item) }) -Name $Exclude).Count) {
                $null = $selected.Remove($item.ProviderAddress)
            }
        }
    }
    @($selected.Values)
}

function Get-TerraformGraphBundleClassifierEntry {
    # Not exported. The classifier files bundled with the module (never the user folder: a
    # bundle describes what ships).
    Get-TerraformClassifierEntry -ClassifierPath $script:TerraformClassifierBundledRoot | Where-Object Rank -eq 0
}

function New-TerraformGraphBundleEntry {
    # Not exported. One entry per -RegistryProvider record: version is the registry cache's
    # latest; docsVersion the docs cached at that version, else the newest cached docs, and
    # harvestedOn when they were harvested; schemaVersion the version when the schema cache
    # holds exactly that version, else null; classifierVersion the newest bundled classifier.
    param([object[]]$RegistryProvider)

    $docs = @(Get-TerraformSchemaCacheEntry -Kind Docs)
    $schemas = @(Get-TerraformSchemaCacheEntry)
    $classifiers = @(Get-TerraformGraphBundleClassifierEntry)
    foreach ($provider in $RegistryProvider) {
        $address = $provider.ProviderAddress
        $version = if ($provider.Latest) { [string]$provider.Latest } else { $null }
        $mineDocs = @($docs | Where-Object ProviderAddress -eq $address)
        $doc = $mineDocs | Where-Object Version -eq $version | Select-Object -First 1
        if (-not $doc) { $doc = $mineDocs | Select-Object -First 1 }
        $schema = $schemas | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $version } | Select-Object -First 1
        $mineClassifiers = @($classifiers | Where-Object ProviderAddress -eq $address)
        $classifier = if ($mineClassifiers.Count) { @(Sort-TerraformRegistryVersion -Versions $mineClassifiers)[0].Record } else { $null }
        [ordered]@{
            provider          = $address
            version           = $version
            docsVersion       = if ($doc) { $doc.Version } else { $null }
            schemaVersion     = if ($schema) { $schema.Version } else { $null }
            classifierVersion = if ($classifier) { $classifier.Version } else { $null }
            harvestedOn       = if ($doc) { $doc.HarvestedOn } else { $null }
        }
    }
}

function ConvertTo-TerraformGraphBundleObject {
    # Not exported. A parsed bundle as TerraformGraph.Bundle with TerraformGraph.BundleEntry
    # Entries.
    param([System.Collections.IDictionary]$Document, [string]$Path)

    $registry = $Document['registry']
    $entries = [object[]]@(foreach ($entry in @($Document['entries'])) {
            [pscustomobject]@{
                PSTypeName        = 'TerraformGraph.BundleEntry'
                ProviderAddress   = [string]$entry['provider']
                Version           = $entry['version']
                DocsVersion       = $entry['docsVersion']
                SchemaVersion     = $entry['schemaVersion']
                ClassifierVersion = $entry['classifierVersion']
                HarvestedOn       = $entry['harvestedOn']
            }
        })
    [pscustomobject]@{
        PSTypeName            = 'TerraformGraph.Bundle'
        Path                  = $Path
        FormatVersion         = $Document['formatVersion']
        Tiers                 = [string[]]@($Document['tiers'])
        Providers             = [string[]]@($Document['providers'])
        Exclude               = [string[]]@($Document['exclude'])
        RegistryHarvestedOn   = if ($registry -is [System.Collections.IDictionary]) { $registry['harvestedOn'] } else { $null }
        RegistryProviderCount = if ($registry -is [System.Collections.IDictionary]) { $registry['providerCount'] } else { $null }
        Entries               = $entries
        EntryCount            = $entries.Length
    }
}

function Write-TerraformGraphTextFile {
    # Not exported. Writes -Text (UTF-8, no BOM) to -Path atomically: a temporary file in the
    # same folder, then Move-Item.
    param([string]$Path, [string]$Text)

    $directory = Split-Path -Path $Path -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporary = Join-Path $directory ".$([guid]::NewGuid().ToString('n')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, $Text, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Get-TerraformGraphBundle {
    <#
    .SYNOPSIS
        Gets the bundle manifest: the provider set the bundled data covers and what was harvested for each provider.

    .DESCRIPTION
        Get-TerraformGraphBundle reads a bundle manifest and returns one
        TerraformGraph.BundleEntry per provider, shown as a table. It never touches the
        network.

        A bundle manifest is JSON:
            { formatVersion, tiers, providers, exclude,
              registry: { harvestedOn, providerCount },
              entries: [ { provider, version, docsVersion, schemaVersion, classifierVersion,
                           harvestedOn } ] }
        tiers, providers (extra full addresses) and exclude define the provider set,
        resolved against the registry cache recorded in registry. Each entry records the
        provider's latest version in that registry cache, the docs and schema versions in
        the local caches, the newest bundled classifier, and when the docs were harvested.
        Test-TerraformGraphBundle checks the entries against those sources.

        The bundled manifest (data\bundle.json in the module) covers the official tier plus
        microsoft/azuredevops and vmware/vsphere. New-TerraformGraphBundle writes your own
        copy, which this command reads first.

    .PARAMETER Path
        Bundle file. Default: $env:LOCALAPPDATA\TerraformGraph\bundle.json when it exists,
        else the bundled data\bundle.json.

    .PARAMETER Document
        Return the whole manifest as one TerraformGraph.Bundle instead of its entries.

    .EXAMPLE
        Get-TerraformGraphBundle

        The bundle entries as a table of ProviderAddress, Version, DocsVersion,
        SchemaVersion, ClassifierVersion, HarvestedOn.

    .EXAMPLE
        Get-TerraformGraphBundle -Document | Select-Object Tiers, Providers, RegistryHarvestedOn, EntryCount

        The provider set and the registry cache it was resolved against.

    .OUTPUTS
        TerraformGraph.BundleEntry: ProviderAddress, Version, DocsVersion, SchemaVersion,
        ClassifierVersion, HarvestedOn. With -Document, TerraformGraph.Bundle: Path,
        FormatVersion, Tiers, Providers, Exclude, RegistryHarvestedOn,
        RegistryProviderCount, Entries, EntryCount.

    .LINK
        New-TerraformGraphBundle

    .LINK
        Test-TerraformGraphBundle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias('BundlePath')]
        [string]
        $Path,

        [switch]
        $Document
    )

    try {
        $full = Resolve-TerraformGraphBundlePath -Path $Path
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
            'BundleNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Path))
    }
    try {
        $bundle = Read-TerraformGraphBundle -Path $full
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.InvalidDataException]::new($_.Exception.Message),
            'BundleInvalid',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $full))
    }
    $view = ConvertTo-TerraformGraphBundleObject -Document $bundle -Path $full
    if ($Document) { $view } else { $view.Entries }
}

function New-TerraformGraphBundle {
    <#
    .SYNOPSIS
        Writes a bundle manifest for a provider set, resolved against the registry cache.

    .DESCRIPTION
        New-TerraformGraphBundle resolves a provider set against the registry cache: every
        provider in -Tier, plus every provider each -Provider pattern matches, less any an
        -Exclude pattern matches. Patterns match by shape and may use wildcards, as for
        Get-TerraformRegistryProvider -Name. It writes the manifest with the patterns
        expanded to full addresses and one entry per provider: its latest version in the
        registry cache, the docs and schema versions in the local caches, the newest
        bundled classifier and when the docs were harvested. It never touches the network.

        Each of -Tier, -Provider and -Exclude that is not given is taken from the bundled
        manifest, so New-TerraformGraphBundle alone refreshes your copy of the bundled set.
        The registry cache used is registry.json in the output folder when there is one,
        else the usual registry cache (your own, else the bundled one). The output is
        sorted and has no timestamp of its own, so the same inputs give the same bytes.

    .PARAMETER Tier
        Registry tiers whose every provider is included: official, partner, community.
        Pass @() for none.

    .PARAMETER Provider
        Extra providers: 'vsphere', 'vmware/vsphere', a full address, or a wildcard. A
        pattern that matches nothing is a terminating error.

    .PARAMETER Exclude
        Providers to leave out, as patterns.

    .PARAMETER OutputPath
        File to write (a folder gets bundle.json). Default:
        $env:LOCALAPPDATA\TerraformGraph\bundle.json, which Get-TerraformGraphBundle reads
        before the bundled copy.

    .PARAMETER PassThru
        Return the written manifest as a TerraformGraph.Bundle.

    .EXAMPLE
        New-TerraformGraphBundle -PassThru

        Refresh your copy of the bundled set (official tier, azuredevops, vsphere) against
        the current registry cache and caches.

    .EXAMPLE
        New-TerraformGraphBundle -Tier @() -Provider hashicorp/azurerm, 'vmware/*' -Exclude vmware/wavefront -OutputPath .\bundle.json

        A bundle of azurerm and every vmware provider except wavefront.

    .OUTPUTS
        None, or TerraformGraph.Bundle with -PassThru.

    .LINK
        Get-TerraformGraphBundle

    .LINK
        Update-TerraformProviderDocCache
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('official', 'partner', 'community')]
        [AllowEmptyCollection()]
        [string[]]
        $Tier,

        [AllowEmptyCollection()]
        [string[]]
        $Provider,

        [AllowEmptyCollection()]
        [string[]]
        $Exclude,

        [string]
        $OutputPath = $script:TerraformGraphBundleUserPath,

        [switch]
        $PassThru
    )

    $defaults = $null
    $unbound = @('Tier', 'Provider', 'Exclude' | Where-Object { -not $PSBoundParameters.ContainsKey($_) })
    if ($unbound.Count -and (Test-Path -LiteralPath $script:TerraformGraphBundleBundledPath -PathType Leaf)) {
        $defaults = Read-TerraformGraphBundle -Path $script:TerraformGraphBundleBundledPath
    }
    $tiers = if ($PSBoundParameters.ContainsKey('Tier')) { [string[]]@($Tier) } elseif ($defaults) { $defaults['tiers'] } else { [string[]]@() }
    $patterns = if ($PSBoundParameters.ContainsKey('Provider')) { [string[]]@($Provider) } elseif ($defaults) { $defaults['providers'] } else { [string[]]@() }
    $excludes = if ($PSBoundParameters.ContainsKey('Exclude')) { [string[]]@($Exclude) } elseif ($defaults) { $defaults['exclude'] } else { [string[]]@() }

    $fullPath = [System.IO.Path]::GetFullPath($OutputPath, (Get-Location -PSProvider FileSystem).ProviderPath)
    if (Test-Path -LiteralPath $fullPath -PathType Container) { $fullPath = Join-Path $fullPath 'bundle.json' }

    try {
        $registry = Get-TerraformGraphBundleRegistry -BundlePath $fullPath
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
            'RegistryCacheNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $fullPath))
    }
    try {
        $selected = @(Resolve-TerraformGraphBundleProvider -Tier $tiers -Provider $patterns -Exclude $excludes -Cache $registry)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new($_.Exception.Message),
            'RegistryProviderNotResolved',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $Provider))
    }

    $expanded = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pattern in $patterns) {
        foreach ($item in @(Select-TerraformRegistryProvider -Cache $registry -Name $pattern)) { $null = $expanded.Add($item.ProviderAddress) }
    }
    $document = [ordered]@{
        formatVersion = $script:TerraformGraphBundleFormatVersion
        tiers         = [object[]]@($script:TerraformGraphBundleTiers | Where-Object { $tiers -contains $_ })
        providers     = [object[]]@($expanded)
        exclude       = [object[]]@($excludes)
        registry      = [ordered]@{ harvestedOn = $registry.HarvestedOn; providerCount = @($registry.Providers).Count }
        entries       = [object[]]@(New-TerraformGraphBundleEntry -RegistryProvider $selected)
    }
    Write-TerraformGraphTextFile -Path $fullPath -Text (Format-TerraformClassifierJson -Document $document)
    Write-Verbose "Wrote $($selected.Count) entries to $fullPath (registry cache $($registry.Path), harvested $($registry.HarvestedOn))"

    if ($PassThru) { ConvertTo-TerraformGraphBundleObject -Document (Read-TerraformGraphBundle -Path $fullPath) -Path $fullPath }
}

function Test-TerraformGraphBundle {
    <#
    .SYNOPSIS
        Checks the bundle manifest and the bundled data against their sources: Fresh, Stale or Missing per item.

    .DESCRIPTION
        Test-TerraformGraphBundle returns one TerraformGraph.BundleCheck (Item, Status,
        Detail) per thing it checks. Status is Fresh, Stale (the source moved on) or Missing
        (something the bundle records is not there). Offline unless -Online:
            registry               bundle registry.harvestedOn and providerCount against the
                                   registry cache it resolves against (registry.json beside
                                   the bundle, else the usual cache)
            entry <address>        the entry is in the bundle's provider set, and its version
                                   is the registry cache's latest; every provider in the set
                                   has an entry
            docs <address>         docsVersion is in the docs cache, equals the entry
                                   version, and harvestedOn matches the cached file
            schema <address>       when the entry has a schemaVersion: it is in the schema
                                   cache and equals the entry version
            classifier <address>   when the entry has a classifierVersion: that bundled
                                   classifier exists and equals the entry version
            mapVersion <address> <version>
                                   each bundled classifier's mapVersion against map.json
            pack <kind> <address> <version>
                                   when -DistPath holds manifest.json: each pack file's
                                   sha256, and its version against the entry's schemaVersion
                                   or docsVersion; an entry with a schemaVersion and no
                                   schema pack is Missing
        -Online adds the live registry's provider count and each entry's latest version on
        registry.terraform.io (one request per entry).

        -Strict writes every row, then throws a terminating error (BundleNotFresh) when any
        row is Stale or Missing. Invoke-Build CheckBundle runs it with -Strict before a
        release.

    .PARAMETER BundlePath
        Bundle file. Default: as for Get-TerraformGraphBundle.

    .PARAMETER DistPath
        Folder of built packs to check when it holds manifest.json. Default:
        dist\schema-packs under the current folder.

    .PARAMETER Online
        Also compare against the live registry.

    .PARAMETER Strict
        Throw when any row is Stale or Missing.

    .EXAMPLE
        Test-TerraformGraphBundle | Where-Object Status -ne Fresh

        What is out of date, offline.

    .EXAMPLE
        Test-TerraformGraphBundle -BundlePath .\src\TerraformGraph\data\bundle.json -Online -Strict

        The release gate, including the live registry.

    .OUTPUTS
        TerraformGraph.BundleCheck: Item, Status (Fresh, Stale, Missing), Detail.

    .LINK
        Get-TerraformGraphBundle

    .LINK
        New-TerraformGraphBundle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]
        $BundlePath,

        [string]
        $DistPath = (Join-Path (Get-Location -PSProvider FileSystem).ProviderPath 'dist' 'schema-packs'),

        [switch]
        $Online,

        [switch]
        $Strict
    )

    try {
        $full = Resolve-TerraformGraphBundlePath -Path $BundlePath
        $bundle = Read-TerraformGraphBundle -Path $full
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.InvalidDataException]::new($_.Exception.Message),
            'BundleInvalid',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $BundlePath))
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string]$Item, [string]$Status, [string]$Detail)
        $rows.Add([pscustomobject]@{ PSTypeName = 'TerraformGraph.BundleCheck'; Item = $Item; Status = $Status; Detail = $Detail })
    }
    $refresh = "Rerun New-TerraformGraphBundle -OutputPath $full (Invoke-Build HarvestBundleDocs refreshes the bundled one)."

    # Registry cache.
    $registry = $null
    try {
        $registry = Get-TerraformGraphBundleRegistry -BundlePath $full
    }
    catch {
        & $add 'registry' 'Missing' $_.Exception.Message
    }
    if ($registry) {
        $recorded = $bundle['registry']
        $count = @($registry.Providers).Count
        if ($recorded -isnot [System.Collections.IDictionary]) {
            & $add 'registry' 'Missing' "The bundle has no registry block. $refresh"
        }
        elseif ([string]$recorded['harvestedOn'] -ne $registry.HarvestedOn -or [int]$recorded['providerCount'] -ne $count) {
            & $add 'registry' 'Stale' "The bundle was resolved against a registry cache harvested $($recorded['harvestedOn']) ($($recorded['providerCount']) providers); $($registry.Path) was harvested $($registry.HarvestedOn) ($count providers). $refresh"
        }
        else {
            & $add 'registry' 'Fresh' "Harvested $($registry.HarvestedOn), $count providers ($($registry.Path))."
        }
        if ($Online) {
            $filter = if ($registry.Scope -eq 'all') { '' } else { "&filter[tier]=$($registry.Scope)" }
            try {
                $live = Invoke-TerraformRegistryRequest -Uri "https://$($script:TerraformRegistrySource)/v2/providers?page[size]=1&page[number]=1$filter"
                $liveCount = [int]$live.meta.pagination.'total-count'
                if ($liveCount -ne $count) {
                    & $add 'registry (online)' 'Stale' "$($script:TerraformRegistrySource) lists $liveCount $($registry.Scope) providers; the registry cache has $count. Run Invoke-Build BuildRegistry (or Update-TerraformRegistryCache)."
                }
                else {
                    & $add 'registry (online)' 'Fresh' "$($script:TerraformRegistrySource) lists $liveCount $($registry.Scope) providers, as cached."
                }
            }
            catch {
                & $add 'registry (online)' 'Missing' "Could not reach $($script:TerraformRegistrySource): $($_.Exception.Message)"
            }
        }
    }

    # Entries against the provider set and the caches.
    $selected = @{}
    if ($registry) {
        try {
            foreach ($item in @(Resolve-TerraformGraphBundleProvider -Tier $bundle['tiers'] -Provider $bundle['providers'] -Exclude $bundle['exclude'] -Cache $registry)) {
                $selected[$item.ProviderAddress] = $item
            }
        }
        catch {
            & $add 'provider set' 'Stale' $_.Exception.Message
        }
    }
    $entries = [ordered]@{}
    foreach ($entry in $bundle['entries']) { $entries[[string]$entry['provider']] = $entry }
    foreach ($address in @($selected.Keys | Sort-Object -Culture '')) {
        if (-not $entries.Contains($address)) { & $add "entry $address" 'Missing' "In the bundle's provider set but has no entry. $refresh" }
    }

    $docs = @(Get-TerraformSchemaCacheEntry -Kind Docs)
    $schemas = @(Get-TerraformSchemaCacheEntry)
    $classifiers = @(Get-TerraformGraphBundleClassifierEntry)
    $harvest = "Update-TerraformProviderDocCache -BundlePath $full -Resume"
    foreach ($address in $entries.Keys) {
        $entry = $entries[$address]
        $version = [string]$entry['version']
        $registryProvider = $selected[$address]
        if ($registry -and -not $registryProvider) {
            & $add "entry $address" 'Stale' "Not in the bundle's provider set (tiers, providers, exclude). $refresh"
        }
        elseif ($registryProvider -and $version -ne [string]$registryProvider.Latest) {
            & $add "entry $address" 'Stale' "Version $version; the registry cache's latest is $($registryProvider.Latest). $refresh"
        }
        else {
            & $add "entry $address" 'Fresh' "Version $version."
        }

        $docsVersion = [string]$entry['docsVersion']
        $cachedDoc = $docs | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $docsVersion } | Select-Object -First 1
        if (-not $docsVersion) {
            & $add "docs $address" 'Missing' "No docs were harvested. Run $harvest, then refresh the bundle."
        }
        elseif (-not $cachedDoc) {
            & $add "docs $address" 'Missing' "Docs $docsVersion are not in the docs cache. Run $harvest, or Get-TerraformDocPack."
        }
        elseif ($docsVersion -ne $version) {
            & $add "docs $address" 'Stale' "Docs $docsVersion; the entry version is $version. Run $harvest, then refresh the bundle."
        }
        elseif ([string]$cachedDoc.HarvestedOn -ne [string]$entry['harvestedOn']) {
            & $add "docs $address" 'Stale' "The docs cache was harvested $($cachedDoc.HarvestedOn); the entry records $($entry['harvestedOn']). $refresh"
        }
        else {
            & $add "docs $address" 'Fresh' "Docs $docsVersion, $($cachedDoc.DocCount) pages, harvested $($cachedDoc.HarvestedOn)."
        }

        $schemaVersion = [string]$entry['schemaVersion']
        if ($schemaVersion) {
            if (-not ($schemas | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $schemaVersion })) {
                & $add "schema $address" 'Missing' "Schema $schemaVersion is not in the schema cache. Run Get-TerraformSchemaPack -Provider $address -Version $schemaVersion, or Invoke-Build BuildSchemaPack."
            }
            elseif ($schemaVersion -ne $version) {
                & $add "schema $address" 'Stale' "Schema $schemaVersion; the entry version is $version. Run Invoke-Build BuildSchemaPack."
            }
            else {
                & $add "schema $address" 'Fresh' "Schema $schemaVersion is cached."
            }
        }

        $classifierVersion = [string]$entry['classifierVersion']
        if ($classifierVersion) {
            if (-not ($classifiers | Where-Object { $_.ProviderAddress -eq $address -and $_.Version -eq $classifierVersion })) {
                & $add "classifier $address" 'Missing' "No bundled classifier for $classifierVersion. Run Invoke-Build BuildClassifier."
            }
            elseif ($classifierVersion -ne $version) {
                & $add "classifier $address" 'Stale' "The bundled classifier is $classifierVersion; the entry version is $version. Run Invoke-Build BuildSchemaPack and BuildClassifier."
            }
            else {
                & $add "classifier $address" 'Fresh' "Bundled classifier $classifierVersion."
            }
        }

        if ($Online) {
            $parsed = ConvertTo-TerraformProviderAddress -Provider $address
            $namespace = if ($registryProvider) { $registryProvider.Namespace } else { $parsed.Namespace }
            $name = if ($registryProvider) { $registryProvider.Name } else { $parsed.Name }
            try {
                $liveVersion = (Find-TerraformProviderDocVersion -Namespace $namespace -Name $name -Version '').Version
                if ($liveVersion -ne $version) {
                    & $add "online $address" 'Stale' "$($script:TerraformRegistrySource) has $liveVersion; the entry version is $version. Run Invoke-Build BuildRegistry, then HarvestBundleDocs."
                }
                else {
                    & $add "online $address" 'Fresh' "$version is the latest on $($script:TerraformRegistrySource)."
                }
            }
            catch {
                & $add "online $address" 'Missing' "Could not read $address from $($script:TerraformRegistrySource): $($_.Exception.Message)"
            }
        }
    }

    # Bundled classifiers against map.json.
    $mapVersion = $null
    try {
        $mapVersion = (Read-TerraformClassifierMap -Path $script:TerraformClassifierMapPath).MapVersion
    }
    catch {
        & $add 'map.json' 'Stale' $_.Exception.Message
    }
    if ($mapVersion) {
        foreach ($classifier in $classifiers) {
            $recordedMap = [string](Read-TerraformClassifierJson -Path $classifier.Path)['mapVersion']
            if ($recordedMap -ne $mapVersion) {
                & $add "mapVersion $($classifier.ProviderAddress) $($classifier.Version)" 'Stale' "mapVersion $recordedMap; map.json is $mapVersion. Run Invoke-Build BuildClassifier."
            }
            else {
                & $add "mapVersion $($classifier.ProviderAddress) $($classifier.Version)" 'Fresh' "mapVersion $mapVersion."
            }
        }
    }

    # Built packs, when there are any.
    $manifestPath = if ($DistPath) { Join-Path $DistPath 'manifest.json' } else { $null }
    if ($manifestPath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $manifest = Read-TerraformClassifierJson -Path $manifestPath
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($pack in @($manifest['packs'])) {
            $kind = if ($pack['kind']) { [string]$pack['kind'] } else { 'schema' }
            $address = [string]$pack['address']
            $packVersion = [string]$pack['version']
            $item = "pack $kind $address $packVersion"
            $null = $seen.Add("$kind|$address")
            $file = Join-Path $DistPath ([string]$pack['file'])
            $entry = $entries[$address]
            $expected = if (-not $entry) { $null } elseif ($kind -eq 'docs') { [string]$entry['docsVersion'] } else { [string]$entry['schemaVersion'] }
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                & $add $item 'Missing' "$file is listed in manifest.json but does not exist. Run Invoke-Build BuildSchemaPack."
            }
            elseif ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$pack['sha256']) {
                & $add $item 'Stale' "$file does not match the sha256 in manifest.json. Run Invoke-Build BuildSchemaPack."
            }
            elseif (-not $entry) {
                & $add $item 'Stale' "The bundle has no entry for $address. $refresh"
            }
            elseif ($expected -ne $packVersion) {
                & $add $item 'Stale' "The bundle entry records $kind $expected. Run Invoke-Build BuildSchemaPack, then refresh the bundle."
            }
            else {
                & $add $item 'Fresh' "$([string]$pack['file']) matches the bundle entry."
            }
        }
        foreach ($address in $entries.Keys) {
            $schemaVersion = [string]$entries[$address]['schemaVersion']
            if ($schemaVersion -and -not $seen.Contains("schema|$address")) {
                & $add "pack schema $address $schemaVersion" 'Missing' "The bundle records schema $schemaVersion but $DistPath has no schema pack for it. Run Invoke-Build BuildSchemaPack."
            }
        }
    }

    foreach ($row in $rows) { $row }
    $bad = @($rows | Where-Object Status -ne 'Fresh')
    if ($Strict -and $bad.Count) {
        $lines = @($bad | Select-Object -First 25 | ForEach-Object { "$($_.Item) [$($_.Status)]: $($_.Detail)" })
        $more = if ($bad.Count -gt 25) { "`n  ... and $($bad.Count - 25) more" } else { '' }
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("$($bad.Count) of $($rows.Count) bundle checks are not fresh ($full):`n  $($lines -join "`n  ")$more"),
            'BundleNotFresh',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $full))
    }
}

function Get-TerraformSubcategorySurvey {
    <#
    .SYNOPSIS
        Counts the doc subcategory labels each provider publishes: one row per provider and label.

    .DESCRIPTION
        Get-TerraformSubcategorySurvey reads the docs cache, never the network, and counts
        resource and data source pages by the subcategory label the registry publishes for
        them (the provider's own grouping, such as "Key Vault" or "Host and Cluster
        Management"). It returns one TerraformGraph.SubcategorySurveyRow per provider and
        label, sorted by provider address then label, and one NoSubcategory row per
        provider whose pages have an empty label. It is the evidence for the drawer list in
        classifiers\drawers.json: a label many providers share is a candidate drawer.

        -BundlePath surveys the bundle's provider set at each provider's latest version in
        its registry cache (else the newest cached docs); providers with no cached docs
        are left out with one warning and listed under missing in the output file.
        -Provider surveys cached providers by pattern instead.

        -OutputPath writes the survey as JSON with its provenance: the bundle's provider
        set and registry cache, each provider's docs version, harvest time and schema
        version, every label with the number of providers using it, and the rows. The file
        has no timestamp of its own and is sorted, so the same caches give the same bytes.

    .PARAMETER BundlePath
        Bundle file. Default: as for Get-TerraformGraphBundle.

    .PARAMETER Provider
        Cached providers to survey instead of a bundle; patterns as for
        Get-TerraformDocCache.

    .PARAMETER Version
        Docs version with -Provider. Default: the newest cached.

    .PARAMETER OutputPath
        JSON file to write (a folder gets subcategories.json). Rows are then returned only
        with -PassThru.

    .PARAMETER PassThru
        With -OutputPath, also return the rows.

    .EXAMPLE
        Get-TerraformSubcategorySurvey -Provider vsphere

        vsphere's labels with their resource and data source page counts.

    .EXAMPLE
        Get-TerraformSubcategorySurvey -OutputPath .\dist\survey\subcategories.json

        Survey the bundle's providers and write the file Invoke-Build HarvestBundleDocs
        writes.

    .EXAMPLE
        Get-TerraformSubcategorySurvey | Group-Object Subcategory | Sort-Object Count -Descending | Select-Object -First 20 Name, Count

        The labels the most bundle providers share.

    .OUTPUTS
        TerraformGraph.SubcategorySurveyRow: ProviderAddress, Version, Subcategory (empty on
        the NoSubcategory row), ResourceCount, DataSourceCount, Status (Labeled or
        NoSubcategory). Default view is ProviderAddress, Subcategory, ResourceCount,
        DataSourceCount, Status.

    .LINK
        Update-TerraformProviderDocCache

    .LINK
        New-TerraformClassifier
    #>
    [CmdletBinding(DefaultParameterSetName = 'Bundle')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Bundle')]
        [string]
        $BundlePath,

        [Parameter(Mandatory, ParameterSetName = 'Provider')]
        [string[]]
        $Provider,

        [Parameter(ParameterSetName = 'Provider')]
        [string]
        $Version,

        [string]
        $OutputPath,

        [switch]
        $PassThru
    )

    $targets = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[object]]::new()
    $bundleInfo = $null
    if ($PSCmdlet.ParameterSetName -eq 'Bundle') {
        try {
            $full = Resolve-TerraformGraphBundlePath -Path $BundlePath
            $bundle = Read-TerraformGraphBundle -Path $full
            $registry = Get-TerraformGraphBundleRegistry -BundlePath $full
            $selected = @(Resolve-TerraformGraphBundleProvider -Tier $bundle['tiers'] -Provider $bundle['providers'] -Exclude $bundle['exclude'] -Cache $registry)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.IO.InvalidDataException]::new($_.Exception.Message),
                'BundleInvalid',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $BundlePath))
        }
        $cached = @(Get-TerraformSchemaCacheEntry -Kind Docs)
        foreach ($item in $selected) {
            $mine = @($cached | Where-Object ProviderAddress -eq $item.ProviderAddress)
            $entry = $mine | Where-Object Version -eq ([string]$item.Latest) | Select-Object -First 1
            if (-not $entry -and $mine.Count) {
                $entry = $mine[0]
                Write-Verbose "No cached docs for $($item.ProviderAddress) $($item.Latest); surveying the cached $($entry.Version)"
            }
            if ($entry) { $targets.Add($entry) }
            else { $missing.Add([ordered]@{ provider = $item.ProviderAddress; version = [string]$item.Latest; reason = 'no cached docs' }) }
        }
        if ($missing.Count) {
            Write-Warning "No cached docs for $($missing.Count) of $($selected.Count) providers in the bundle, so the survey leaves them out: $(@($missing | ForEach-Object { $_.provider }) -join ', '). Run Update-TerraformProviderDocCache -BundlePath $full -Resume."
        }
        $bundleInfo = [ordered]@{
            formatVersion = $bundle['formatVersion']
            tiers         = [object[]]$bundle['tiers']
            providers     = [object[]]$bundle['providers']
            exclude       = [object[]]$bundle['exclude']
            registry      = [ordered]@{ harvestedOn = $registry.HarvestedOn; providerCount = @($registry.Providers).Count }
        }
    }
    else {
        try {
            foreach ($entry in @(Resolve-TerraformSchemaCacheProvider -Name $Provider -Version $Version -Kind Docs)) { $targets.Add($entry) }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.Management.Automation.ItemNotFoundException]::new($_.Exception.Message),
                'ProviderDocNotCached',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Provider))
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $providers = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($targets | Sort-Object { $_.ProviderAddress } -Culture '')) {
        Write-Verbose "Surveying $($entry.ProviderAddress) $($entry.Version) from $($entry.Path)"
        $document = Read-TerraformSchemaCache -Path $entry.Path
        $counts = [System.Collections.Generic.Dictionary[string, int[]]]::new([System.StringComparer]::Ordinal)
        $none = [int[]]@(0, 0)
        foreach ($doc in @($document['docs'])) {
            $slot = switch ([string]$doc['category']) { 'resources' { 0 } 'data-sources' { 1 } default { -1 } }
            if ($slot -lt 0) { continue }
            $label = [string]$doc['subcategory']
            if ([string]::IsNullOrWhiteSpace($label)) { $none[$slot]++; continue }
            if (-not $counts.ContainsKey($label)) { $counts[$label] = [int[]]@(0, 0) }
            $counts[$label][$slot]++
        }
        $labels = [System.Collections.Generic.List[string]]::new()
        foreach ($label in $counts.Keys) { $labels.Add($label) }
        $labels.Sort([System.Comparison[string]] {
                param($a, $b)
                $byText = [string]::Compare($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
                if ($byText) { return $byText }
                [string]::CompareOrdinal($a, $b)
            })
        $resourceTotal = $none[0]
        $dataTotal = $none[1]
        foreach ($label in $labels) {
            $resourceTotal += $counts[$label][0]
            $dataTotal += $counts[$label][1]
            $rows.Add([pscustomobject]@{
                PSTypeName      = 'TerraformGraph.SubcategorySurveyRow'
                ProviderAddress = $entry.ProviderAddress
                Version         = $entry.Version
                Subcategory     = $label
                ResourceCount   = $counts[$label][0]
                DataSourceCount = $counts[$label][1]
                Status          = 'Labeled'
            })
        }
        if ($none[0] + $none[1]) {
            $rows.Add([pscustomobject]@{
                PSTypeName      = 'TerraformGraph.SubcategorySurveyRow'
                ProviderAddress = $entry.ProviderAddress
                Version         = $entry.Version
                Subcategory     = $null
                ResourceCount   = $none[0]
                DataSourceCount = $none[1]
                Status          = 'NoSubcategory'
            })
        }
        $providers.Add([ordered]@{
            provider        = $entry.ProviderAddress
            version         = $entry.Version
            harvestedOn     = $document['harvestedOn']
            schemaVersion   = $document['schemaVersion']
            pageCount       = $document['docCount']
            resourceCount   = $resourceTotal
            dataSourceCount = $dataTotal
            labelCount      = $labels.Count
        })
    }

    if ($OutputPath) {
        # Labels across providers, matched ignoring case as map rows are; each is shown in the
        # spelling most providers use (ties: ordinal order).
        $byLabel = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $noLabel = @{ Providers = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal); Resource = 0; Data = 0 }
        foreach ($row in $rows) {
            if ($row.Status -eq 'NoSubcategory') {
                $null = $noLabel.Providers.Add($row.ProviderAddress)
                $noLabel.Resource += $row.ResourceCount
                $noLabel.Data += $row.DataSourceCount
                continue
            }
            $group = $null
            if (-not $byLabel.TryGetValue($row.Subcategory, [ref]$group)) {
                $group = @{
                    Spellings = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
                    Providers = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
                    Resource  = 0
                    Data      = 0
                }
                $byLabel[$row.Subcategory] = $group
            }
            $group.Spellings[$row.Subcategory] = 1 + $(if ($group.Spellings.ContainsKey($row.Subcategory)) { $group.Spellings[$row.Subcategory] } else { 0 })
            $null = $group.Providers.Add($row.ProviderAddress)
            $group.Resource += $row.ResourceCount
            $group.Data += $row.DataSourceCount
        }
        $labelList = [System.Collections.Generic.List[object]]::new()
        foreach ($group in $byLabel.Values) {
            $spelling = @($group.Spellings.Keys | Sort-Object -Property @{ Expression = { $group.Spellings[$_] }; Descending = $true }, @{ Expression = { $_ }; Descending = $false } -Culture '')[0]
            $labelList.Add([pscustomobject]@{ Label = $spelling; Group = $group })
        }
        $labelList.Sort([System.Comparison[object]] {
                param($a, $b)
                $byProviders = $b.Group.Providers.Count.CompareTo($a.Group.Providers.Count)
                if ($byProviders) { return $byProviders }
                $byText = [string]::Compare($a.Label, $b.Label, [System.StringComparison]::OrdinalIgnoreCase)
                if ($byText) { return $byText }
                [string]::CompareOrdinal($a.Label, $b.Label)
            })

        $document = [ordered]@{
            formatVersion = 1
            source        = 'docs cache: resources and data-sources pages counted by the subcategory label the registry publishes'
            bundle        = $bundleInfo
            summary       = [ordered]@{
                providerCount              = $providers.Count
                missingCount               = $missing.Count
                labelCount                 = $labelList.Count
                rowCount                   = $rows.Count
                noSubcategoryProviderCount = $noLabel.Providers.Count
            }
            providers     = [object[]]$providers.ToArray()
            missing       = [object[]]$missing.ToArray()
            labels        = [object[]]@(foreach ($item in $labelList) {
                    [ordered]@{
                        subcategory     = $item.Label
                        providerCount   = $item.Group.Providers.Count
                        resourceCount   = $item.Group.Resource
                        dataSourceCount = $item.Group.Data
                        providers       = [object[]]@($item.Group.Providers)
                    }
                })
            noSubcategory = [ordered]@{
                providerCount   = $noLabel.Providers.Count
                resourceCount   = $noLabel.Resource
                dataSourceCount = $noLabel.Data
                providers       = [object[]]@($noLabel.Providers)
            }
            rows          = [object[]]@(foreach ($row in $rows) {
                    [ordered]@{
                        provider        = $row.ProviderAddress
                        version         = $row.Version
                        subcategory     = $row.Subcategory
                        resourceCount   = $row.ResourceCount
                        dataSourceCount = $row.DataSourceCount
                        status          = $row.Status
                    }
                })
        }
        $fullPath = [System.IO.Path]::GetFullPath($OutputPath, (Get-Location -PSProvider FileSystem).ProviderPath)
        if ((Test-Path -LiteralPath $fullPath -PathType Container) -or -not [System.IO.Path]::GetExtension($fullPath)) { $fullPath = Join-Path $fullPath 'subcategories.json' }
        Write-TerraformGraphTextFile -Path $fullPath -Text (Format-TerraformClassifierJson -Document $document)
        Write-Verbose "Wrote $($rows.Count) rows, $($labelList.Count) labels across $($providers.Count) providers to $fullPath"
        if (-not $PassThru) { return }
    }
    foreach ($row in $rows) { $row }
}

# Agent tools that read project skills: the project-relative folder skills are copied
# into, and the path whose presence means the tool is used in a repo. These paths are
# the convention as of 2026-10; this table is the only place to correct them.
$script:TerraformGraphSkillTools = [ordered]@{
    Claude  = @{ SkillsDir = '.claude/skills'; Marker = '.claude' }
    Codex   = @{ SkillsDir = '.codex/skills';  Marker = '.codex' }
    Cursor  = @{ SkillsDir = '.cursor/skills'; Marker = '.cursor' }
    Gemini  = @{ SkillsDir = '.gemini/skills'; Marker = '.gemini' }
    Copilot = @{ SkillsDir = '.github/skills'; Marker = '.github/copilot-instructions.md' }
}

# Skill views. SkillPath is long, so it comes last.
Update-TypeData -TypeName 'TerraformGraph.SkillInstall' -DefaultDisplayPropertySet Tool, Status, Files, SkillPath -Force
Update-TypeData -TypeName 'TerraformGraph.SkillStatus' -DefaultDisplayPropertySet Tool, Detected, Installed, Stale, SkillPath -Force

# The canonical skills shipped with the module; Install-TerraformGraphSkill copies this folder.
$script:TerraformGraphSkillSource = Join-Path $PSScriptRoot 'skills'

function Resolve-TerraformGraphSkillTool {
    # Not exported. Expands 'All' and removes duplicates, in tool-map order.
    param([string[]]$Tool)
    $all = $Tool -contains 'All'
    foreach ($name in $script:TerraformGraphSkillTools.Keys) {
        if ($all -or $Tool -contains $name) { $name }
    }
}

function Get-TerraformGraphSkillFile {
    # Not exported. Every bundled skill file as {Source, Relative}, Relative using the
    # platform separator, in ordinal order so installs are deterministic.
    $root = (Resolve-Path -LiteralPath $script:TerraformGraphSkillSource -ErrorAction Stop).ProviderPath
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object { $_.FullName } -Culture '')
    foreach ($file in $files) {
        [pscustomobject]@{
            Source   = $file.FullName
            Relative = [System.IO.Path]::GetRelativePath($root, $file.FullName)
        }
    }
}

function Test-TerraformGraphSkillFileEqual {
    # Not exported. True when both files exist with the same bytes.
    param([string]$Left, [string]$Right)
    if (-not (Test-Path -LiteralPath $Right -PathType Leaf)) { return $false }
    (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
}

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
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.DirectoryNotFoundException]::new("Path '$Path' is not an existing directory."),
            'SkillPathNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Path))
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

function Test-TerraformGraphSkill {
    <#
    .SYNOPSIS
        Reports which agent tools a repository uses and whether the TerraformGraph skill is installed for them.

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
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.DirectoryNotFoundException]::new("Path '$Path' is not an existing directory."),
            'SkillPathNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Path))
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

Show-TerraformGraphSkillHint
