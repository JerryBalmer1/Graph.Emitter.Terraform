# TerraformGraph manual check list

Module version: 0.5.1
Last updated: 2026-10-06

## 0 Setup

### 0.1 Fresh import

Imports the module from source and lists its version and exported commands.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
(Get-Module TerraformGraph).Version.ToString()
(Get-Command -Module TerraformGraph).Name
```

Expect: `0.5.1`, then six names: ConvertFrom-TerraformJson, ConvertTo-TerraformJson, ConvertTo-TerraformSchemaGraph, Get-TerraformAST, Get-TerraformModuleGraph, Get-TerraformProviderSchema.

Pester: "is exported", "resolves to the TerraformGraph module", "are exported", "is exported from TerraformGraph"

## 1 Get-TerraformAST

### 1.1 -Path (Directory set)

Parses the .tf files in one directory; subdirectories are skipped. Shows the default display.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -Path .\infra
```

Expect: 18 blocks in list view with only Type, Name, Line, Column, File: 9 from main.tf (first `terraform` at line 1, `module network` at line 38), 2 from outputs.tf, 7 from variables.tf. Nothing from modules\.

Pester: "parses infra with -Path"

### 1.2 -Path -Recurse

Parses the directory and every subdirectory.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -Path .\infra -Recurse |
    Group-Object { Resolve-Path -Relative $_.TypeRange.Filename } |
    Select-Object Count, Name
```

Expect: eight files listed, 31 blocks in all, including `.\infra\modules\network\modules\endpoint\main.tf` with Count 2.

Pester: "parses infra with -Path -Recurse and includes nested modules"

### 1.3 -FilePath (File set)

Parses one .tf file.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -FilePath .\infra\main.tf
```

Expect: nine blocks, every File is main.tf, from `terraform` at line 1 to `check region_set` at line 45.

Pester: "parses a file with -FilePath"

### 1.4 Pipeline input to -FilePath

FileInfo objects bind to -FilePath through the FullName alias.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-ChildItem .\infra -Filter *.tf | Get-TerraformAST | Group-Object File | Select-Object Count, Name
```

Expect: three groups: 9 main.tf, 2 outputs.tf, 7 variables.tf.

Pester: "binds pipeline FileInfo input to -FilePath"

### 1.5 Error: missing file

A -FilePath that does not exist fails parameter validation.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -FilePath .\does-not-exist.tf
```

Expect: `Cannot validate argument on parameter 'FilePath'. FilePath '.\does-not-exist.tf' is not an existing file.`

Pester: "rejects a missing file"

### 1.6 Error: non-.tf file

A -FilePath without a .tf extension fails parameter validation.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -FilePath .\README.md
```

Expect: `Cannot validate argument on parameter 'FilePath'. FilePath '.\README.md' must have a .tf extension.`

Pester: "rejects a non-.tf FilePath"

### 1.7 Error: missing directory

A -Path that does not exist fails parameter validation.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -Path .\does-not-exist-dir
```

Expect: `Cannot validate argument on parameter 'Path'. Path '.\does-not-exist-dir' is not an existing directory.`

Pester: "rejects a missing directory" (Get-TerraformAST context)

### 1.8 Error: directory with no .tf files

An existing directory with nothing to parse writes a non-terminating error.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-empty'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
try {
    Get-TerraformAST -Path $dir
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `Get-TerraformAST: ... No .tf files found.` and the temp directory is removed.

Pester: "writes a non-terminating error for a directory with no .tf files"

### 1.9 Error: HCL syntax error

A file the HCL parser rejects surfaces the parser diagnostic with the file path.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-badhcl'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {' -Force | Out-Null
try {
    Get-TerraformAST -Path $dir
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: exactly one error, attributed to `Get-TerraformAST:`, and no other console output: `Error parsing HCL file: <temp>\tg-check-badhcl\main.tf:1,31-32: Unclosed configuration block; There is no closing brace for this block before the end of the file. ...` ending in `(<temp>\tg-check-badhcl\main.tf)`.

Pester: "writes a non-terminating parse error for an unclosed block"

## 2 ConvertTo-TerraformJson

### 2.1 Default output

Indented JSON with two spaces; HTML characters are not escaped.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
[pscustomobject]@{ a = 1; b = '<x & y>' } | ConvertTo-TerraformJson
```

Expect: four lines, `{`, `  "a": 1,`, `  "b": "<x & y>"`, `}`.

Pester: "writes indented JSON without escaping HTML characters"

### 2.2 -Compress

Writes the JSON on one line.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
[ordered]@{ a = 1; b = @(1, 2) } | ConvertTo-TerraformJson -Compress
```

Expect: `{"a":1,"b":[1,2]}`

Pester: "writes one line with -Compress"

### 2.3 -AsArray and multiple inputs

More than one pipeline input, or -AsArray, writes a JSON array.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
1, 2 | ConvertTo-TerraformJson -Compress
1 | ConvertTo-TerraformJson -Compress -AsArray
```

Expect: `[1,2]` then `[1]`.

Pester: "writes multiple pipeline inputs or -AsArray as an array"

### 2.4 Error: -Depth exceeded

An object nested deeper than -Depth throws instead of truncating.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$deep = [pscustomobject]@{ value = 'leaf' }
1..200 | ForEach-Object { $deep = [pscustomobject]@{ child = $deep } }
$deep | ConvertTo-TerraformJson -Depth 50
```

Expect: `Object nesting exceeds -Depth 50.`

Pester: "throws when nesting exceeds -Depth"

### 2.5 Error: circular reference

A self-referencing object throws.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$a = [pscustomobject]@{ name = 'a' }
$a | Add-Member -NotePropertyName self -NotePropertyValue $a
$a | ConvertTo-TerraformJson
```

Expect: `Circular reference detected at depth 1 (System.Management.Automation.PSObject).`

Pester: "throws on a circular reference"

### 2.6 Deeper than ConvertTo-Json allows

A 200-level object round-trips intact; ConvertTo-Json stops at 100.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$deep = [pscustomobject]@{ value = 'leaf' }
1..200 | ForEach-Object { $deep = [pscustomobject]@{ child = $deep } }
$node = $deep | ConvertTo-TerraformJson | ConvertFrom-TerraformJson
1..200 | ForEach-Object { $node = $node.child }
$node.value
```

Expect: `leaf`

Pester: "round-trips an object deeper than ConvertTo-Json allows"

### 2.7 Get-TerraformAST output

Serializes parsed blocks and reads them back.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$json = Get-TerraformAST -FilePath .\infra\main.tf | ConvertTo-TerraformJson
($json | ConvertFrom-TerraformJson).Type -join ', '
```

Expect: `terraform, provider, provider, locals, resource, resource, data, module, check`

Pester: "serializes Get-TerraformAST output"

## 3 ConvertFrom-TerraformJson

### 3.1 Default output

Objects become PSCustomObjects; numbers keep the narrowest exact type.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$o = '{"n":123456789012345678901234567890,"i":2,"f":1.5,"s":"x","a":[1,2]}' | ConvertFrom-TerraformJson
$o.PSObject.Properties | Format-Table Name, Value, @{ n = 'Type'; e = { $_.Value.GetType().Name } }
```

Expect: n `123456789012345678901234567890` BigInteger, i `2` Int32, f `1.50` Double, s `x` String, a `{1, 2}` Object[].

Pester: "keeps large integers exact"

### 3.2 -AsHashtable

Returns ordered, case-sensitive dictionaries.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$h = '{"Name":1,"name":2}' | ConvertFrom-TerraformJson -AsHashtable
$h.GetType().FullName
$h
```

Expect: `System.Collections.Specialized.OrderedDictionary`, then two keys, `Name` = 1 and `name` = 2.

Pester: "parses -AsHashtable with case-sensitive keys"

### 3.3 Error: case-colliding keys

Keys that differ only by case cannot become a PSCustomObject.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
'{"Name":1,"name":2}' | ConvertFrom-TerraformJson
```

Expect: `Key 'name' is empty or collides with another key (PSCustomObject keys are case-insensitive). Use -AsHashtable.`

Pester: "throws on case-colliding keys without -AsHashtable"

### 3.4 -NoEnumerate

A top-level array is enumerated unless -NoEnumerate is set.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
@('[1,2,3]' | ConvertFrom-TerraformJson).Count
@('[1,2,3]' | ConvertFrom-TerraformJson -NoEnumerate).Count
```

Expect: `3` then `1`.

Pester: "enumerates top-level arrays unless -NoEnumerate"

### 3.5 Pipeline lines

Strings from the pipeline are joined before parsing, as Get-Content without -Raw sends them.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
"{", '  "a": 1', "}" | ConvertFrom-TerraformJson
```

Expect: one object with property `a` = 1.

Pester: "joins Get-Content lines from the pipeline"

### 3.6 Error: -Depth exceeded

JSON nested deeper than -Depth throws.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
'[[[[1]]]]' | ConvertFrom-TerraformJson -Depth 2
```

Expect: `The maximum configured depth of 2 has been exceeded. Cannot read next JSON array. LineNumber: 0 | BytePositionInLine: 2.`

Pester: "throws when JSON nesting exceeds -Depth"

## 4 Get-TerraformProviderSchema

### 4.1 Default output (OrderedHashtable)

Runs terraform init on a temp directory that uses only the builtin terraform provider, then reads its schema.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schema'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    terraform "-chdir=$dir" init -input=false -no-color | Out-Null
    $schema = Get-TerraformProviderSchema -Path $dir
    $schema.GetType().FullName
    $schema['provider_schemas'].Keys
    $schema['provider_schemas']['terraform.io/builtin/terraform']['resource_schemas']['terraform_data']['block']['attributes'].Keys -join ', '
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `System.Collections.Specialized.OrderedDictionary`, `terraform.io/builtin/terraform`, then `id, input, output, triggers_replace`.

Pester: "returns nested ordered dictionaries by default"

### 4.2 -OutputFormat Json

Same temp setup; returns indented JSON text.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schema-json'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    terraform "-chdir=$dir" init -input=false -no-color | Out-Null
    $json = Get-TerraformProviderSchema -Path $dir -OutputFormat Json
    $json.GetType().FullName
    ($json -split '\r?\n')[0..2]
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `System.String`, then `{`, `  "format_version": "1.0",`, `  "provider_schemas": {`.

Pester: "returns indented JSON with -OutputFormat Json"

### 4.3 -Path defaults to the current location

Same temp setup, run from inside the directory with no -Path.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schema-cwd'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
Push-Location $dir
try {
    terraform init -input=false -no-color | Out-Null
    (Get-TerraformProviderSchema)['provider_schemas'].Keys
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `terraform.io/builtin/terraform`

Pester: "defaults -Path to the current location"

### 4.4 Error: providers not installed

A configuration that needs a downloaded provider, without terraform init.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schema-noinit'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "null_resource" "x" {}' -Force | Out-Null
try {
    Get-TerraformProviderSchema -Path $dir
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `terraform providers schema failed with exit code 1 in '<temp>\tg-check-schema-noinit'. Run terraform init first if providers are not installed.` followed by terraform's Inconsistent dependency lock file message for hashicorp/null; the temp directory is still removed.

Pester: "throws when providers are not installed"

### 4.5 Error: missing directory

A -Path that does not exist fails parameter validation.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformProviderSchema -Path .\does-not-exist-dir
```

Expect: `Cannot validate argument on parameter 'Path'. Path '.\does-not-exist-dir' is not an existing directory.`

Pester: "rejects a missing directory" (Get-TerraformProviderSchema context)

### 4.6 -Provider -Cleanup (quick fetch)

Fetches the latest hashicorp/null schema with no configuration and removes the working directory afterwards. Needs registry access.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$schema = Get-TerraformProviderSchema -Provider null -Cleanup
$schema.provider_schemas.Keys
$schema.provider_schemas['registry.terraform.io/hashicorp/null'].resource_schemas.Keys
Test-Path (Join-Path $env:TEMP 'TerraformGraph\providers\hashicorp-null-latest')
```

Expect: `registry.terraform.io/hashicorp/null`, then `null_resource`, then `False`.

Pester: "removes the working directory with -Cleanup and still returns the schema"

### 4.7 -Provider -Version (pinned, kept for reuse)

The default working directory is kept, so the second identical call skips terraform init. The block removes the directory at the end.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'TerraformGraph\providers\hashicorp-null-__3.2.3'
try {
    Measure-Command { Get-TerraformProviderSchema -Provider hashicorp/null -Version '= 3.2.3' -Verbose } | Select-Object TotalSeconds
    Measure-Command { Get-TerraformProviderSchema -Provider hashicorp/null -Version '= 3.2.3' -Verbose } | Select-Object TotalSeconds
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
```

Expect: the first run shows `VERBOSE: terraform -chdir=<temp>\TerraformGraph\providers\hashicorp-null-__3.2.3 init ...` and `VERBOSE: Provider registry.terraform.io/hashicorp/null 3.2.3 in ...`. The second run shows `VERBOSE: Skipping terraform init; ...\.terraform.lock.hcl exists. Use -Force to run it again.` instead of init and is much faster (about 1.4 s, then about 0.2 s).

Pester: "writes the resolved version with -Verbose", "skips terraform init when the lock file exists"

### 4.8 -Provider -Force

-Force deletes the lock file and runs terraform init again even though the working directory is already initialized.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schema-force'
try {
    $null = Get-TerraformProviderSchema -Provider null -Version '= 3.2.3' -WorkingDirectory $dir
    $before = (Get-Item (Join-Path $dir '.terraform.lock.hcl')).LastWriteTime
    $null = Get-TerraformProviderSchema -Provider null -Version '= 3.2.3' -WorkingDirectory $dir -Force -Verbose
    $after = (Get-Item (Join-Path $dir '.terraform.lock.hcl')).LastWriteTime
    "Lock file rewritten: $($after -ne $before)"
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
```

Expect: `VERBOSE: terraform -chdir=<temp>\tg-check-schema-force init -backend=false -input=false -no-color` (no "Skipping terraform init" line), the `Provider registry.terraform.io/hashicorp/null 3.2.3` verbose line, then `Lock file rewritten: True`.

Pester: "re-runs terraform init with -Force"

### 4.9 Error: invalid -Provider

A malformed provider address fails parameter validation before terraform runs.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformProviderSchema -Provider 'not//valid'
```

Expect: `Cannot validate argument on parameter 'Provider'. Provider 'not//valid' is not a provider address. Use 'name', 'namespace/name', or 'host/namespace/name'.`

Pester: "rejects an invalid -Provider before running terraform"

### 4.10 Error: nonexistent provider

terraform init fails; its stderr is in the error and -Cleanup still removes the working directory.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schema-missing'
try {
    Get-TerraformProviderSchema -Provider hashicorp/definitely-not-a-provider-xyz -WorkingDirectory $dir -Cleanup
}
finally {
    "Working directory left behind: $(Test-Path -LiteralPath $dir)"
}
```

Expect: `Working directory left behind: False`, then `terraform init failed with exit code 1 for provider 'hashicorp/definitely-not-a-provider-xyz' in '<temp>\tg-check-schema-missing'.` followed by terraform's `Error: Failed to query available provider packages ... provider registry registry.terraform.io does not have a provider named registry.terraform.io/hashicorp/definitely-not-a-provider-xyz`.

Pester: "throws terraform's stderr for a nonexistent provider and cleans up"

## 5 Get-TerraformModuleGraph

### 5.1 -Path (direct calls only)

Root and its direct module calls; children are resolved but not parsed. Shows both default displays.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra
$graph | Format-Table
$graph.Nodes | Format-Table
```

Expect: graph row `C:\__Code\TerraformGraph\infra  Call  2  1  0`; nodes `root` (Root, Depth 0) and `module.network` (Local, Depth 1, Dir ...\infra\modules\network), both Resolved True.

Pester: "stops at direct children without -Recurse", "sets the default display properties"

### 5.2 -Recurse

Follows every call down the tree and parses each child.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse
$graph | Format-Table
$graph.Nodes | Format-Table ModuleAddress, Depth, ParentKey, Resolved, @{ n = 'Blocks'; e = { @($_.Blocks).Count } }
$graph.Edges | Format-Table
```

Expect: NodeCount 3, EdgeCount 2, UnresolvedCount 0; Blocks 18, 9, 4; `module.network.module.endpoint` has Depth 2 and ParentKey `network`; edges at Line 38 (root to module.network) and Line 17 (module.network to the endpoint).

Pester: "follows nested calls with -Recurse", "links edges by Id and records the module block line"

### 5.3 -GroupBy Source

Node Ids and edge From/To are source strings; ModuleAddress is unchanged.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse -GroupBy Source
$graph.Nodes | Format-Table Id, ModuleAddress
$graph.Edges | Format-Table
```

Expect: Ids `root`, `./modules/network`, `./modules/endpoint`; edges `root` to `./modules/network` (Line 38) and `./modules/network` to `./modules/endpoint` (Line 17).

Pester: "uses Source as Id with -GroupBy Source and ModuleAddress with -GroupBy Call"

### 5.4 Unresolved: LocalPathMissing

A local source that points at a missing directory.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-missing-local'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'module "gone" { source = "./does-not-exist" }' -Force | Out-Null
try {
    $graph = Get-TerraformModuleGraph -Path $dir
    $graph | Format-Table
    $graph.Unresolved | Format-Table ModuleAddress, Source, SourceKind, Resolved, Reason
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: UnresolvedCount 1; `module.gone  ./does-not-exist  Local  False  LocalPathMissing`.

Pester: "marks a missing local source as LocalPathMissing"

### 5.5 Unresolved: NotInitialized

A registry source with no .terraform/modules/modules.json; terraform init is not run.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-registry'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'module "vpc" { source = "terraform-aws-modules/vpc/aws" }' -Force | Out-Null
try {
    $graph = Get-TerraformModuleGraph -Path $dir
    $graph | Format-Table
    $graph.Unresolved | Format-Table ModuleAddress, Source, SourceKind, Resolved, Reason
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: UnresolvedCount 1; `module.vpc  terraform-aws-modules/vpc/aws  Registry  False  NotInitialized`.

Pester: "marks a registry source without .terraform as NotInitialized"

### 5.6 Cycle

root calls ./x, x calls ../y, y calls ../x back into its own ancestor; the walk stops there.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-cycle'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'module "x" { source = "./x" }' -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $dir 'x\main.tf') -Value 'module "y" { source = "../y" }' -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $dir 'y\main.tf') -Value 'module "x" { source = "../x" }' -Force | Out-Null
try {
    $graph = Get-TerraformModuleGraph -Path $dir -Recurse
    $graph | Format-Table
    $graph.Nodes | Format-Table ModuleAddress, Source, Resolved, Reason, @{ n = 'Parsed'; e = { $null -ne $_.Blocks } }
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: NodeCount 4, EdgeCount 3, UnresolvedCount 0; only `module.x.module.y.module.x` has Reason `Cycle`, with Resolved True and Parsed False.

Pester: "stops at a call whose Dir is one of its own ancestors"

### 5.7 Error: missing directory

A -Path that does not exist fails parameter validation.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformModuleGraph -Path .\does-not-exist-dir
```

Expect: `Cannot validate argument on parameter 'Path'. Path '.\does-not-exist-dir' is not an existing directory.`

Pester: "rejects a missing directory" (Get-TerraformModuleGraph context)

## 6 ConvertTo-TerraformSchemaGraph

### 6.1 Builtin fixture and Summary

Converts the builtin terraform provider schema into a graph and counts nodes by Kind.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schemagraph'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    terraform "-chdir=$dir" init -input=false -no-color | Out-Null
    $graph = Get-TerraformProviderSchema -Path $dir | ConvertTo-TerraformSchemaGraph
    $graph | Format-Table
    $graph.Summary
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: Providers `{terraform.io/builtin/terraform}`, NodeCount 12, EdgeCount 11; Summary lists Provider 1, Resource 1, DataSource 1, Attribute 9 in that order.

Pester: "lists only the built-in provider", "summarizes counts by Kind", "gives every non-Provider node exactly one incoming edge from its ParentId"

### 6.2 One resource's attributes

Lists the attribute nodes of the terraform_remote_state data source with their rendered Type and flags.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schemagraph'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    terraform "-chdir=$dir" init -input=false -no-color | Out-Null
    $graph = Get-TerraformProviderSchema -Path $dir | ConvertTo-TerraformSchemaGraph
    $graph.Nodes | Where-Object { $_.Kind -eq 'Attribute' -and $_.Path -like 'terraform_remote_state.*' } | Format-Table Path, Type, Required, Optional, Computed, Depth
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: Five rows at Depth 2: backend `string` Required True; config and defaults `any` Optional True; outputs `any` Computed True; workspace `string` Optional True.

Pester: "builds the terraform_data Attribute nodes with types and flags", "puts terraform_remote_state under /data/ as a DataSource"

### 6.3 -Provider filter

Filters to a provider that is in the document, then to one that is not.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schemagraph'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    terraform "-chdir=$dir" init -input=false -no-color | Out-Null
    $schema = Get-TerraformProviderSchema -Path $dir
    ($schema | ConvertTo-TerraformSchemaGraph -Provider 'terraform.io/builtin/terraform').NodeCount
    $schema | ConvertTo-TerraformSchemaGraph -Provider hashicorp/null
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `12`, then the terminating error `Provider 'registry.terraform.io/hashicorp/null' is not in provider_schemas. Available: terraform.io/builtin/terraform.`

Pester: "returns the same graph with -Provider 'terraform.io/builtin/terraform'", "throws for a -Provider that is not in the document"

### 6.4 JSON string input

Pipes the -OutputFormat Json text, and the same text through ConvertFrom-TerraformJson, into the converter.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-schemagraph'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    terraform "-chdir=$dir" init -input=false -no-color | Out-Null
    $json = Get-TerraformProviderSchema -Path $dir -OutputFormat Json
    $json.GetType().FullName
    ($json | ConvertTo-TerraformSchemaGraph).NodeCount
    ($json | ConvertFrom-TerraformJson | ConvertTo-TerraformSchemaGraph).NodeCount
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `System.String`, then `12` and `12`.

Pester: "gives the same NodeCount for -OutputFormat Json text and for its PSCustomObject form"

### 6.5 Error: no provider_schemas

Input without a top-level provider_schemas is rejected.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
@{} | ConvertTo-TerraformSchemaGraph
```

Expect: `Schema has no top-level provider_schemas. Pass the output of Get-TerraformProviderSchema, its -OutputFormat Json text, or that text through ConvertFrom-TerraformJson.`

Pester: "throws when the input has no provider_schemas"

### 6.6 Provider config nodes

Converts the hashicorp/tls schema and lists the nodes built from the provider's own configuration block. Needs registry access.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformProviderSchema -Provider tls -Version '= 4.0.6' -Cleanup | ConvertTo-TerraformSchemaGraph
$graph.Nodes | Where-Object Id -like 'registry.terraform.io/hashicorp/tls/config/*' | Format-Table Id, Kind, Path, Type, Depth
```

Expect: Five rows: `registry.terraform.io/hashicorp/tls/config/proxy` Block `tls.proxy` Depth 1, then Attributes from_env `bool`, password `string`, url `string`, username `string` at Depth 2 with Ids under `.../config/proxy/` and Paths `tls.proxy.<name>`.

Pester: "adds the proxy config Block under the Provider node", "adds the proxy config Attributes one level deeper", "emits the config subtree right after the Provider node, before resources"
