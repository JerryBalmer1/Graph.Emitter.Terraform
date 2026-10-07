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
