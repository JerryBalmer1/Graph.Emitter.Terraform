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
            $null = ConvertTo-TerraformProviderAddress -Provider $_
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

        [ValidateSet('OrderedHashtable', 'Json')]
        [string]
        $OutputFormat = 'OrderedHashtable'
    )

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
        Write-Verbose "Provider $address $($resolvedVersion ?? '(version not in lock file)') in $directory"

        Read-TerraformProviderSchemaFromDirectory -WorkingDirectory $directory -OutputFormat $OutputFormat
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
        [string]$Segment
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

    $node = [pscustomobject]@{
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

    .PARAMETER Provider
        Only include these providers: 'aws', 'hashicorp/aws', or
        'registry.terraform.io/hashicorp/aws', normalized the same way as
        Get-TerraformProviderSchema -Provider. Matched against the provider_schemas keys
        without regard to case. A provider that is not in the document is a terminating
        error that lists the providers that are. Default: every provider in the document.

    .PARAMETER IncludeFunctions
        Add provider functions (the functions map in newer schemas) as Function nodes
        under their provider. Off by default.

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

    .OUTPUTS
        TerraformGraph.SchemaGraph. Default view is Providers, NodeCount, EdgeCount; Summary
        is an ordered Kind -> count table. Nodes are TerraformGraph.SchemaNode (default view
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
        https://github.com/JerryBalmer1/TerraformGraph
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]
        $Schema,

        [ValidateScript({
            $null = ConvertTo-TerraformProviderAddress -Provider $_
            $true
        })]
        [string[]]
        $Provider,

        [switch]
        $IncludeFunctions
    )

    begin {
        $wanted = @(foreach ($p in $Provider) { (ConvertTo-TerraformProviderAddress -Provider $p).Address })
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
                Nodes = [System.Collections.Generic.List[object]]::new()
                Edges = [System.Collections.Generic.List[object]]::new()
            }

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
                $graph.Nodes.Add($providerNode)
                Add-TerraformSchemaChildNodes -Graph $graph -Container $config -Parent $providerNode -Segment config

                foreach ($section in @(
                        @{ Key = 'resource_schemas';    Kind = 'Resource' }
                        @{ Key = 'data_source_schemas'; Kind = 'DataSource' }
                    )) {
                    $schemas = Get-TerraformSchemaMember -InputObject $entry -Name $section.Key
                    foreach ($type in Get-TerraformSchemaKeys -InputObject $schemas -Sort) {
                        $resource = Get-TerraformSchemaMember -InputObject $schemas -Name $type
                        $block = Get-TerraformSchemaMember -InputObject $resource -Name 'block'
                        $node = New-TerraformSchemaNode -Graph $graph -Kind $section.Kind -Name $type -Parent $providerNode -Raw $resource `
                            -Description (Get-TerraformSchemaMember -InputObject $block -Name 'description') `
                            -Deprecated ([bool](Get-TerraformSchemaMember -InputObject $block -Name 'deprecated')) `
                            -SchemaVersion (Get-TerraformSchemaMember -InputObject $resource -Name 'version')
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

            [pscustomobject]@{
                PSTypeName = 'TerraformGraph.SchemaGraph'
                Providers  = [string[]]$addresses
                Nodes      = $graph.Nodes.ToArray()
                Edges      = $graph.Edges.ToArray()
            }
        }
    }

    process {
        # JSON text is collected and parsed once in end, so piped lines work.
        if ($Schema -is [string]) {
            $jsonLines.Add($Schema)
            return
        }
        & $convert $Schema
    }

    end {
        if ($jsonLines.Count -eq 0) { return }
        $document = ($jsonLines -join [Environment]::NewLine) | ConvertFrom-TerraformJson -AsHashtable -ErrorAction Stop
        & $convert $document
    }
}
