# TerraformGraph manual check list

Module version: 0.16.0
Last updated: 2026-10-07

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

Expect: `0.15.0`, then twenty-six names (none added in 0.15.0; since 0.15.0 each is defined in src\TerraformGraph\Public\<name>.ps1), and no other output: ConvertFrom-TerraformJson, ConvertTo-TerraformJson, ConvertTo-TerraformResourceGraph, ConvertTo-TerraformSchemaGraph, ConvertTo-TerraformVariableGraph, Get-TerraformAST, Get-TerraformClassifier, Get-TerraformClassifierFinding, Get-TerraformDocCache, Get-TerraformDocPack, Get-TerraformGraphBundle, Get-TerraformModuleGraph, Get-TerraformProviderDoc, Get-TerraformProviderSchema, Get-TerraformRegistryProvider, Get-TerraformSchemaCache, Get-TerraformSchemaPack, Get-TerraformSubcategorySurvey, Get-TerraformVariableTrace, Install-TerraformGraphSkill, New-TerraformClassifier, New-TerraformGraphBundle, Test-TerraformGraphBundle, Test-TerraformGraphSkill, Update-TerraformProviderDocCache, Update-TerraformRegistryCache.

Pester: "is exported", "resolves to the TerraformGraph module", "are exported", "is exported from TerraformGraph", "exports both variable graph functions from TerraformGraph", "exports Install-TerraformGraphSkill and Test-TerraformGraphSkill from TerraformGraph", "exports Update-TerraformRegistryCache and Get-TerraformRegistryProvider from TerraformGraph", "exports Get-TerraformSchemaPack and Get-TerraformSchemaCache from TerraformGraph", "exports the four docs commands from TerraformGraph", "exports the three classifier commands from TerraformGraph", "exports the bundle commands and ships a bundled manifest with the official tier and two extras"

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

Expect: exactly one error, attributed to `Get-TerraformAST:`, and no other console output: `Error parsing HCL file: <temp>\tg-check-badhcl\main.tf:1,31-32: Unclosed configuration block; There is no closing brace for this block before the end of the file. ...` then `(<temp>\tg-check-badhcl\main.tf) Fix the file, then rerun Get-TerraformAST -FilePath '<temp>\tg-check-badhcl\main.tf' (terraform validate in its folder reports the same error).`

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

Expect: `Object nesting exceeds -Depth 50. Rerun ConvertTo-TerraformJson with a larger -Depth, or break the circular reference first.`

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

Expect: `Circular reference detected at depth 1 (System.Management.Automation.PSObject). Rerun ConvertTo-TerraformJson with a larger -Depth, or break the circular reference first.`

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

Expect: `Key 'name' is empty or collides with another key (PSCustomObject keys are case-insensitive). Use -AsHashtable. Rerun ConvertFrom-TerraformJson with a larger -Depth, or with -AsHashtable for keys that differ only by case.`

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

Expect: `The maximum configured depth of 2 has been exceeded. Cannot read next JSON array. LineNumber: 0 | BytePositionInLine: 2. Rerun ConvertFrom-TerraformJson with a larger -Depth, or with -AsHashtable for keys that differ only by case.`

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

Root and its direct module calls; children are resolved but not parsed. Shows the three default displays: graph, node table and edge table.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra
$graph | Format-Table
$graph.Nodes | Format-Table
$graph.Edges | Format-Table
```

Expect: graph row `C:\__Code\TerraformGraph\infra  Call  2  1  0`; node table headed `Id  Kind  SourceKind  Depth  Resolved  Dir` with `root` (Module, Root, Depth 0) and `module.network` (Module, Local, Depth 1, Dir ...\infra\modules\network), both Resolved True; edge table headed `From  To  Kind  Call  File  Line` with one row `root  module.network  Calls  module.network  main.tf  38`.

Pester: "stops at direct children without -Recurse", "sets the default display properties"

### 5.2 -Recurse

Follows every call down the tree and parses each child.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse
$graph | Format-Table
$graph.Nodes | Format-Table Id, Kind, Depth, ParentKey, Resolved, @{ n = 'Blocks'; e = { @($_.Blocks).Count } }
$graph.Edges | Format-Table
```

Expect: NodeCount 3, EdgeCount 2, UnresolvedCount 0; Ids `root`, `module.network`, `module.network.module.endpoint`, all Kind `Module`; Blocks 18, 9, 4; `module.network.module.endpoint` has Depth 2 and ParentKey `network`; edges Kind `Calls` in `main.tf` at Line 38 (root to module.network) and Line 17 (module.network to the endpoint).

Pester: "follows nested calls with -Recurse", "links edges by Id and records the module block line"

### 5.3 -GroupBy Source

One node per module source, Id `source:` plus the source relative to the root module; Callers names the calls each node stands for, and ModuleAddress is unchanged.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse -GroupBy Source
$graph.Nodes | Format-Table Id, ModuleAddress, Callers
$graph.Edges | Format-Table
```

Expect: Ids `root`, `source:./modules/network`, `source:./modules/network/modules/endpoint` (the endpoint's `./modules/endpoint` resolved from the network module and written relative to infra), with Callers `{}`, `{module.network}`, `{module.network.module.endpoint}`; edges `root` to `source:./modules/network` (Calls, main.tf, Line 38) and `source:./modules/network` to `source:./modules/network/modules/endpoint` (Calls, main.tf, Line 17).

Pester: "uses source: and the root-relative source as Id with -GroupBy Source and ModuleAddress with -GroupBy Call"

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
    "Findings: $($graph.Findings.Id -join ', ')"
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: UnresolvedCount 1; `module.gone  ./does-not-exist  Local  False  LocalPathMissing`; then `Findings: module.gone` (Findings is the same list as Unresolved).

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

### 5.8 -GroupBy Source with one source called twice

Two calls to the same local source, written two ways, collapse into one node; Ids stay unique under both modes, and edges stay one per call.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-duplicate-source'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value "module `"a`" {`n  source = `"./shared`"`n}`nmodule `"b`" {`n  source = `"./shared/`"`n}" -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $dir 'shared\main.tf') -Value 'module "leaf" { source = "./leaf" }' -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $dir 'shared\leaf\main.tf') -Value 'locals {}' -Force | Out-Null
try {
    foreach ($groupBy in 'Call', 'Source') {
        $graph = Get-TerraformModuleGraph -Path $dir -Recurse -GroupBy $groupBy
        "$groupBy`: $($graph.NodeCount) nodes, $(@($graph.Nodes.Id | Sort-Object -Unique -CaseSensitive).Count) unique Ids, $($graph.EdgeCount) edges"
    }
    $graph.Nodes | Format-Table Id, Kind, Resolved, Callers
    $graph.Edges | Format-Table
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `Call: 5 nodes, 5 unique Ids, 4 edges`, then `Source: 3 nodes, 3 unique Ids, 4 edges`; Source nodes `root` (Callers `{}`), `source:./shared` (Callers `{module.a, module.b}`) and `source:./shared/leaf` (Callers `{module.a.module.leaf, module.b.module.leaf}`), all Kind `Module` and Resolved True; four `Calls` edges, two from `root` to `source:./shared` (Lines 1 and 4) and two from `source:./shared` to `source:./shared/leaf`, told apart by Call.

Pester: "keeps Ids unique under both -GroupBy modes when one source is called twice", "collapses calls to one source into one node with Callers under -GroupBy Source"

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

Expect: `12`, then the terminating error `Provider 'registry.terraform.io/hashicorp/null' is not in provider_schemas. Available: terraform.io/builtin/terraform. Fetch it with Get-TerraformProviderSchema -Provider registry.terraform.io/hashicorp/null -SaveToCache, then ConvertTo-TerraformSchemaGraph -Provider registry.terraform.io/hashicorp/null.`

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

## 7 ConvertTo-TerraformVariableGraph

### 7.1 infra -Recurse and Summary

Builds the variable graph for the whole infra tree and counts nodes by Kind.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
$graph | Format-Table
$graph.Summary
```

Expect: Root `C:\__Code\TerraformGraph\infra`, NodeCount 20, EdgeCount 8, UnresolvedCount 0; Summary lists Variable 13, Local 2, Output 5 in that order.

Pester: "has one node per variable, local and output in root, network and endpoint", "gives every edge a From and To that exist in Nodes", "has no Unresolved or Skipped entries for infra"

### 7.2 Variables bound by a module call argument

Lists the child module variables whose value comes from the parent's module call.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
$graph.Nodes | Where-Object Binding -eq 'Argument' | Format-Table Module, Name, @{ n = 'Argument'; e = { $_.ArgumentExpr.Raw } }, ArgumentLiteral
```

Expect: Five rows: module.network aws_region, instance_count and tags with Argument `var.aws_region`, `var.instance_count`, `var.tags` and no ArgumentLiteral; module.network.module.endpoint host `"localhost"` (ArgumentLiteral localhost) and port `8080` (ArgumentLiteral 8080).

Pester: "binds module.network var.aws_region to the root call argument", "keeps literal module call arguments on the endpoint variables"

### 7.3 Unresolved: undeclared argument

A module call passes an argument the child does not declare.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-vargraph'
New-Item -ItemType File -Path (Join-Path $dir 'm\main.tf') -Value 'variable "known" {}' -Force | Out-Null
Set-Content -Path (Join-Path $dir 'main.tf') -Value "module `"m`" {`n  source = `"./m`"`n  known  = 1`n  nope   = 2`n}"
try {
    (Get-TerraformModuleGraph -Path $dir -Recurse | ConvertTo-TerraformVariableGraph).Unresolved | Format-Table
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: One row: Module `module.m`, Root `var.nope`, Reason `UndeclaredArgument`, File `main.tf`, Line 4.

Pester: "reports an argument the child does not declare as UndeclaredArgument"

## 8 Get-TerraformVariableTrace

### 8.1 Upstream from a child variable

Traces where the network module's aws_region comes from.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
($graph | Get-TerraformVariableTrace -Id 'module.network/var/aws_region' -Direction Upstream).Nodes | Format-Table
```

Expect: Two rows: Distance 0 Variable module.network aws_region Binding Argument; Distance 1 Variable root aws_region Binding Default Literal us-east-1.

Pester: "traces module.network var.aws_region upstream to the root variable at Distance 1"

### 8.2 Downstream from a root variable

Traces what the root aws_region variable feeds.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
($graph | Get-TerraformVariableTrace -Id 'root/var/aws_region' -Direction Downstream).Nodes | Format-Table
```

Expect: Three rows: Distance 0 Variable root aws_region (Default, us-east-1); Distance 1 Output root region; Distance 1 Variable module.network aws_region (Argument).

Pester: "traces root var.aws_region downstream to the root output and the network variable, and no further"

### 8.3 Error: unknown Id

An Id that is not in the graph is rejected with the same-named nodes.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
$graph | Get-TerraformVariableTrace -Id 'module.network.module.endpoint/var/aws_region'
```

Expect: `Node 'module.network.module.endpoint/var/aws_region' is not in the variable graph. Nodes named 'aws_region': root/var/aws_region, module.network/var/aws_region. List every Id with $graph.Nodes | Select-Object -ExpandProperty Id, then rerun Get-TerraformVariableTrace with one of them.`

Pester: "throws for an unknown Id and names the same-named nodes"

## 9 ConvertTo-TerraformResourceGraph

### 9.1 Inventory with no schema

Lists every resource and data source in the infra tree with its resolved provider.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph
$graph | Format-Table
$graph.Nodes | Format-Table Kind, ResourceAddress, ProviderAddress, SchemaMatched, Reason
$graph.Providers
```

Expect: Root `C:\__Code\TerraformGraph\infra`, NodeCount 5, MatchedCount 0, UnmatchedCount 5, Findings 0; five rows null_resource.marker, terraform_data.placeholder, data.local_file.readme (DataSource), module.network.null_resource.subnet, module.network.module.endpoint.terraform_data.listener, all SchemaMatched False with Reason NoSchemaGraph; Providers lists registry.terraform.io/hashicorp/null 2, terraform.io/builtin/terraform 2, registry.terraform.io/hashicorp/local 1.

Pester: "has one node per resource and data block in infra, in module then source order", "marks every node NoSchemaGraph without -SchemaGraph", "counts nodes per provider address"

### 9.2 Join with the builtin schema and show unmatched

Joins infra with the built-in provider schema and lists the nodes that did not match, with the Reason.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-resgraph-builtin'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}' -Force | Out-Null
try {
    $null = terraform "-chdir=$dir" init -input=false -no-color
    $schema = Get-TerraformProviderSchema -Path $dir | ConvertTo-TerraformSchemaGraph
    $graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schema
    $graph | Format-Table
    $graph.Nodes | Where-Object { -not $_.SchemaMatched } | Format-Table ResourceAddress, ProviderAddress, Reason
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: NodeCount 5, MatchedCount 2, UnmatchedCount 3, Findings 0; three rows null_resource.marker, data.local_file.readme and module.network.null_resource.subnet, each with Reason ProviderNotInSchemaGraph.

Pester: "matches terraform_data.placeholder to the builtin schema", "reports null_resource.marker as ProviderNotInSchemaGraph with only the builtin graph"

### 9.3 Findings: unknown attribute

A resource sets an argument the schema does not declare.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-resgraph-finding'
New-Item -ItemType File -Path (Join-Path $dir 'main.tf') -Value "resource `"terraform_data`" `"x`" {`n  bogus = 1`n}" -Force | Out-Null
try {
    $null = terraform "-chdir=$dir" init -input=false -no-color
    $schema = Get-TerraformProviderSchema -Path $dir | ConvertTo-TerraformSchemaGraph
    $graph = Get-TerraformModuleGraph -Path $dir | ConvertTo-TerraformResourceGraph -SchemaGraph $schema
    $graph | Format-Table
    $graph.Nodes | Format-List ResourceAddress, SchemaMatched, UnknownAttributes, UnknownBlocks, MissingRequired
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: NodeCount 1, MatchedCount 1, UnmatchedCount 0, Findings 1; terraform_data.x with SchemaMatched True, UnknownAttributes {bogus}, UnknownBlocks {} and MissingRequired {}.

Pester: "lists an attribute the schema does not declare in UnknownAttributes"

## 10 Install-TerraformGraphSkill and Test-TerraformGraphSkill

### 10.1 Install to a temp directory

Copies the bundled skill into a fake repo that uses Claude.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
try {
    Install-TerraformGraphSkill -Path $dir -PassThru
    Get-ChildItem -LiteralPath (Join-Path $dir '.claude\skills') -Recurse -File | Select-Object -ExpandProperty FullName
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: One row: Tool Claude, Status Installed, Files 1, SkillPath ending `\tg-check-skill\.claude\skills`; then one file, `...\tg-check-skill\.claude\skills\terraformgraph\SKILL.md`.

Pester: "installs SKILL.md for Claude identical to the bundled file"

### 10.2 Test-TerraformGraphSkill output

Reports every tool for a repo that has .claude and .cursor, with the skill installed for Claude only.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dir '.cursor') -Force | Out-Null
try {
    Install-TerraformGraphSkill -Path $dir
    Test-TerraformGraphSkill -Path $dir | Format-Table Tool, Detected, Installed, Stale
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: Five rows in order Claude, Codex, Cursor, Gemini, Copilot; Claude Detected True, Installed True, Stale False; Cursor Detected True, Installed False; Codex, Gemini and Copilot all False.

Pester: "reports Claude Detected, Installed and not Stale after install", "reports Detected false for every tool in a directory with no markers"

### 10.3 Idempotent re-run

Installs twice; the second run writes nothing.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
try {
    Install-TerraformGraphSkill -Path $dir -PassThru | Format-Table Tool, Status, Files
    Install-TerraformGraphSkill -Path $dir -PassThru | Format-Table Tool, Status, Files
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: Two tables: Claude Installed 1, then Claude Unchanged 0. No error.

Pester: "returns Unchanged on a second install without -Force"

### 10.4 Stale, then -Force

Edits the installed copy, shows it as Stale, then restores it.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
try {
    Install-TerraformGraphSkill -Path $dir
    Add-Content -LiteralPath (Join-Path $dir '.claude\skills\terraformgraph\SKILL.md') -Value 'local edit'
    Test-TerraformGraphSkill -Path $dir -Tool Claude | Format-Table Tool, Installed, Stale
    Install-TerraformGraphSkill -Path $dir -PassThru -Verbose | Format-Table Tool, Status, Files
    Install-TerraformGraphSkill -Path $dir -Force -PassThru | Format-Table Tool, Status, Files
    Test-TerraformGraphSkill -Path $dir -Tool Claude | Format-Table Tool, Installed, Stale
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: Claude Installed True Stale True; a VERBOSE line `Skipping ...\SKILL.md; it differs from the bundled skill. Use -Force to overwrite.` and Claude Skipped 0; then Claude Updated 1; then Claude Installed True Stale False.

Pester: "reports an edited copy as Stale, skips it without -Force and restores it with -Force"

### 10.5 AGENTS.md marker count

Installs twice into a repo that already has an AGENTS.md.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value '# Existing rules'
try {
    Install-TerraformGraphSkill -Path $dir
    Install-TerraformGraphSkill -Path $dir -Force
    (Select-String -LiteralPath (Join-Path $dir 'AGENTS.md') -SimpleMatch '<!-- terraformgraph-skill -->').Count
    Get-Content -LiteralPath (Join-Path $dir 'AGENTS.md')
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: `1`, then AGENTS.md: `# Existing rules`, a blank line, `<!-- terraformgraph-skill -->`, `## TerraformGraph skill`, the load sentence, `- .claude/skills/terraformgraph/SKILL.md` (in backticks) and the re-run sentence.

Pester: "creates AGENTS.md with the marker and never appends it twice", "appends to an existing AGENTS.md without changing its content"

### 10.6 Import hint visible

Imports the module in a new process from a directory with .claude and no skill.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
try {
    pwsh -NoProfile -Command "Remove-Item Env:TERRAFORMGRAPH_SKILL_HINT -ErrorAction SilentlyContinue; Set-Location -LiteralPath '$dir'; Import-Module C:\__Code\TerraformGraph\src\TerraformGraph\TerraformGraph.psd1"
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: One line: `TerraformGraph: detected Claude in this directory. Run Install-TerraformGraphSkill -Tool Claude to give them the TerraformGraph skill.`

Pester: "prints the install hint on import where .claude exists without the skill"

### 10.7 Import hint silenced

Same directory with TERRAFORMGRAPH_SKILL_HINT set to 0.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-skill'
New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
try {
    pwsh -NoProfile -Command "`$env:TERRAFORMGRAPH_SKILL_HINT = '0'; Set-Location -LiteralPath '$dir'; Import-Module C:\__Code\TerraformGraph\src\TerraformGraph\TerraformGraph.psd1; 'imported'"
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}
```

Expect: Only `imported`; no TerraformGraph line.

Pester: "prints nothing on import when TERRAFORMGRAPH_SKILL_HINT is 0"

## 11 Update-TerraformRegistryCache and Get-TerraformRegistryProvider

Items 11.1 to 11.5 read the bundled cache (harvested 2026-10-07). If a user cache exists at `$env:LOCALAPPDATA\TerraformGraph
egistry.json` it is read instead, and counts and versions can differ.

### 11.1 Wildcard

Bare-name wildcard across every namespace.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformRegistryProvider aws*
```

Expect: Four rows: hashicorp/aws official 6.67.0 509, hashicorp/awscc official 1.104.0 188, nullstone-io/awsex partner 0.1.3 4, traceableai/awsapigateway partner 0.7.0 7 (full registry.terraform.io addresses), columns ProviderAddress, Tier, Latest, VersionCount.

Pester: "matches a wildcard against the bare name in every namespace", "computes VersionCount and sets the default display properties"

### 11.2 Bare name

A name with no slash matches that name in any namespace.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformRegistryProvider google | Format-Table ProviderAddress, Source, Tier, Latest
```

Expect: One row: registry.terraform.io/hashicorp/google, Source hashicorp/google, official, Latest 8.6.0.

Pester: "matches a bare name in any namespace", "matches namespace/name and the full address"

### 11.3 -Tier

Counts official providers, then filters them by namespace/name.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformRegistryProvider -Tier official | Measure-Object | Select-Object -ExpandProperty Count
Get-TerraformRegistryProvider -Tier official -Name 'hashicorp/a*'
```

Expect: `34`, then seven official rows: hashicorp/ad, archive, aws, awscc, azuread, azurerm, azurestack.

Pester: "filters by -Tier"

### 11.4 Ambiguous schema call

A wildcard -Provider that matches several providers stops before terraform runs.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformProviderSchema -Provider 'aws*'
```

Expect: An error, no terraform output: `'aws*' matches 4 providers: hashicorp/aws, hashicorp/awscc, nullstone-io/awsex, Traceableai/awsapigateway. Specify one; Get-TerraformRegistryProvider -Name 'aws*' lists them.`

Pester: "throws for an ambiguous pattern and lists every match, official first", "stops Get-TerraformProviderSchema -Provider 'aws*' with the ambiguous message before running terraform"

### 11.5 Argument completers (interactive)

Run the block, then follow the keystrokes in its comments in the same interactive pwsh window. The last lines print the same completions without a keyboard.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
# Interactive: in this same pwsh window, type the text below without pressing Enter,
# then press Ctrl+Space (or Tab to cycle):
#   Get-TerraformProviderSchema -Provider aws
# Then clear the line and type, then press Ctrl+Space:
#   Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2
# The same completions, non-interactively:
$line = 'Get-TerraformProviderSchema -Provider aws'
(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText
$line = 'Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2'
(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText -join ', '
```

Expect: Typing `Get-TerraformProviderSchema -Provider aws` and pressing Ctrl+Space lists hashicorp/aws, hashicorp/awscc, nullstone-io/awsex, Traceableai/awsapigateway (official first; the tooltip shows the full address, tier and latest). `-Version 3.2` then Ctrl+Space lists 3.2.4, 3.2.4-alpha.2, 3.2.3, 3.2.2, 3.2.1, 3.2.0. The printed lines show the same values.

Pester: "completes -Provider with cached addresses, official first", "completes -Version newest first for the provider already given", "completes Get-TerraformRegistryProvider -Name"

### 11.6 -NoBundledData with no user cache

A child process whose LOCALAPPDATA has no cache, reading without the bundled file.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$empty = Join-Path $env:TEMP 'tg-check-no-appdata'
try {
    pwsh -NoProfile -Command "`$env:LOCALAPPDATA = '$empty'; Import-Module C:\__Code\TerraformGraph\src\TerraformGraph\TerraformGraph.psd1; `$r = @(Get-TerraformRegistryProvider -NoBundledData); 'Providers: ' + `$r.Count"
}
finally {
    Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
}
```

Expect: `WARNING: No provider registry cache found. Run Update-TerraformRegistryCache to create one.` then `Providers: 0`.

Pester: "warns and returns nothing with -NoBundledData and no user cache"

### 11.7 Update to a temp path

Harvests official and partner providers from registry.terraform.io (network, about 15 to 30 seconds).

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$dir = Join-Path $env:TEMP 'tg-check-registry'
try {
    Update-TerraformRegistryCache -Path (Join-Path $dir 'registry.json') -PassThru | Format-List ProviderCount, VersionCount, Scope, Elapsed
    Get-ChildItem -LiteralPath $dir -Force | Select-Object Name
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
```

Expect: ProviderCount about 428, VersionCount about 25,000 (25056 on 2026-10-07), Scope `official,partner`, Elapsed under a minute (36.8 s on 2026-10-07); the folder holds only registry.json (no leftover temp file). This is a live official+partner registry harvest: never run it while another harvest is going.

Pester: "harvests official and partner providers to a TestDrive path", "writes versions newest first and a Latest that skips pre-releases"

## 12 Schema packs: Get-TerraformSchemaPack, Get-TerraformSchemaCache, -SaveToCache, cached schema graphs

These items write to the real schema cache, `$env:LOCALAPPDATA\TerraformGraph\schemas`. Items 12.1 to 12.4 harvest hashicorp/null 3.2.3 first (network, a few seconds, 1 KB in the cache). Rows from other providers you have cached also appear in 12.2 and can change the match counts in 12.4.

### 12.1 -SaveToCache for null 3.2.3

Fetches the schema with terraform and also writes it to the cache at the version from the lock file.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2.3 -SaveToCache -Cleanup -Verbose | Out-Null
Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'TerraformGraph\schemas\registry.terraform.io-hashicorp-null\3.2.3.json.gz') | Format-Table Name, Length
```

Expect: Verbose lines for terraform init and providers schema, then `VERBOSE: Saved registry.terraform.io/hashicorp/null 3.2.3 to ...\TerraformGraph\schemas\registry.terraform.io-hashicorp-null\3.2.3.json.gz`, then one row: `3.2.3.json.gz` with Length 1028.

Pester: "writes one file into the redirected cache for hashicorp/null 3.2.3", "writes registry.terraform.io-hashicorp-null/3.2.3.json.gz and reads back byte-identical JSON"

### 12.2 Get-TerraformSchemaCache

Lists cached schemas, then shows every property of one provider.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$null = Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2.3 -SaveToCache -Cleanup
Get-TerraformSchemaCache
Get-TerraformSchemaCache -Provider null | Format-List *
```

Expect: A table with columns ProviderAddress, Version, Bytes, CachedOn that includes `registry.terraform.io/hashicorp/null 3.2.3 1028`, plus any other cached providers (after 12.6: azurerm 5.8.0, azuredevops 1.16.0, vsphere 2.17.1). Then a list with ProviderAddress, Version `3.2.3`, Path ending in `registry.terraform.io-hashicorp-null\3.2.3.json.gz`, Bytes `1028`, CachedOn (UTC).

Pester: "lists cached schemas with Get-TerraformSchemaCache"

### 12.3 ConvertTo-TerraformSchemaGraph -Provider null

Builds the schema graph from the cache, with no schema document in the pipeline.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$null = Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2.3 -SaveToCache -Cleanup
$graph = ConvertTo-TerraformSchemaGraph -Provider null -Version 3.2.3
$graph
$graph.Nodes | Format-Table Kind, Path, Type, Required, Depth
```

Expect: Providers `{registry.terraform.io/hashicorp/null}`, NodeCount 10, EdgeCount 9; then ten nodes: Provider null, Resource null_resource with id and triggers (`map(string)`), DataSource null_data_source with has_computed_default, id, inputs, outputs, random.

Pester: "builds the same graph from ConvertTo-TerraformSchemaGraph -Provider null as from the piped document", "throws for an uncached ConvertTo-TerraformSchemaGraph -Provider and names both ways to fill the cache"

### 12.4 ConvertTo-TerraformResourceGraph -AutoSchema on infra

Joins infra with whatever the cache holds for the providers it resolves to. Nothing is downloaded.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$null = Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2.3 -SaveToCache -Cleanup
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema
$graph
$graph.Nodes | Format-Table ResourceAddress, ProviderAddress, SchemaMatched, Reason
```

Expect: NodeCount 5, MatchedCount 2, UnmatchedCount 3, Findings 0. The two null_resource nodes are SchemaMatched True; terraform_data.placeholder, data.local_file.readme and the endpoint's terraform_data.listener show ProviderNotInSchemaGraph. If you have also cached hashicorp/local or the built-in terraform provider, those nodes match too.

Pester: "loads every cached provider with -AutoSchema", "matches nothing with -AutoSchema and an empty cache, marks every node ProviderNotInSchemaGraph, and never downloads", "matches the same 5 infra nodes with ConvertTo-TerraformResourceGraph -Provider null,local,terraform as with -SchemaGraph"

### 12.5 Get-TerraformSchemaPack -Source dist\schema-packs for vsphere

Installs the vsphere pack from the folder BuildSchemaPack writes, forces it again, then asks for a provider the manifest does not have. Builds the folder first (as in 12.6) if it is missing.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
if (-not (Test-Path -LiteralPath .\dist\schema-packs\manifest.json)) { Invoke-Build BuildSchemaPack }
Get-TerraformSchemaPack -Provider vsphere -Source .\dist\schema-packs -PassThru
Get-TerraformSchemaPack -Provider vsphere -Source .\dist\schema-packs -Force -PassThru
Get-TerraformSchemaPack -Provider hashicorp/aws -Source .\dist\schema-packs
```

Expect: `registry.terraform.io/vmware/vsphere 2.17.1 Cached 34740` (BuildSchemaPack already cached it), then the same row with Status `Updated`, then the error `Get-TerraformSchemaPack found no pack for registry.terraform.io/hashicorp/aws in 'C:\__Code\TerraformGraph\dist\schema-packs' (packs: registry.terraform.io/hashicorp/azurerm 5.8.0, registry.terraform.io/microsoft/azuredevops 1.16.0, registry.terraform.io/vmware/vsphere 2.17.1). Harvest it locally instead with Get-TerraformProviderSchema -Provider hashicorp/aws -SaveToCache.`

Pester: "downloads a pack from a directory Source, then reports Cached, then Updated with -Force", "throws for a provider with no manifest entry and names Get-TerraformSchemaPack and Get-TerraformProviderSchema -SaveToCache", "throws on a sha256 mismatch and leaves nothing in the cache"

### 12.6 Invoke-Build BuildSchemaPack elapsed

Harvests hashicorp/azurerm, microsoft/azuredevops and vmware/vsphere at their latest version in the registry cache and writes dist\schema-packs. Needs the network; the first run downloads about 220 MB for azurerm.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build BuildSchemaPack
Get-ChildItem .\dist\schema-packs | Format-Table Name, Length
```

Expect: One line per provider, `registry.terraform.io/hashicorp/azurerm 5.8.0: 217,891 bytes, 33,699 nodes, 1106 resources, 396 data sources`, `registry.terraform.io/microsoft/azuredevops 1.16.0: 16,955 bytes, 2,583 nodes, 131 resources, 46 data sources` and `registry.terraform.io/vmware/vsphere 2.17.1: 34,740 bytes, 1,512 nodes, 52 resources, 35 data sources`, each with harvest and total times. Then `Wrote 3 packs and manifest.json ... in` about 25 s on a first run, or 19 s when the provider working directories already exist. The folder holds manifest.json (1172 bytes) and the three .json.gz files. Versions follow the registry cache, so they change after Update-TerraformRegistryCache.

Pester: none

### 12.7 Get-TerraformSchemaPack -Provider vsphere from the real release

Downloads the vsphere schema pack from the latest GitHub release again. With no GH_TOKEN this uses the anonymous releases/latest/download URL. This repository is public, so no token is needed. With $env:GH_TOKEN (or $env:GITHUB_TOKEN) set, it goes through the GitHub releases API, which is what a private fork needs. Needs the network.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformSchemaPack -Provider vsphere -Force -PassThru
```

Expect: One row, `registry.terraform.io/vmware/vsphere 2.17.1 Updated 34740` (Status `Downloaded` if vsphere was not cached before). With GH_TOKEN set and -Verbose, the WebRequest lines show api.github.com/repos/JerryBalmer1/TerraformGraph/releases/latest, then two releases/assets/<id> downloads.

Pester: "uses the releases API with a Bearer token when GH_TOKEN is set", "uses the anonymous download URL when no token is set", "names GH_TOKEN for a private fork on a 404 without a token"

## 13 Provider docs: Update-TerraformProviderDocCache, Get-TerraformProviderDoc, Get-TerraformDocPack, Get-TerraformDocCache

Docs live in $env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz, keyed on schema node Ids. Items 13.1 to 13.4 write the null (and local) docs into the real docs cache.

### 13.1 Update-TerraformProviderDocCache for null 3.2.3

Harvests the hashicorp/null 3.2.3 docs from the registry and matches them against the cached null schema. Needs the network.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3 -Force -PassThru
```

Expect: A list with ProviderAddress `registry.terraform.io/hashicorp/null`, Version `3.2.3`, Status `Harvested` the first time (`Updated` after that), DocCount `4`, UnmatchedCount `0` and Elapsed about 2 s. If the null schema is not cached, a warning names Get-TerraformSchemaPack and UnmatchedCount is empty.

Pester: "harvests hashicorp/null 3.2.3 into the redirected docs cache"

### 13.2 Get-TerraformProviderDoc -Type wildcard

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3
Get-TerraformProviderDoc -Provider null -Type 'null_*'
```

Expect: Two rows with columns Id, Category, Title, Subcategory: `registry.terraform.io/hashicorp/null/resource/null_resource` (resources, resource) and `registry.terraform.io/hashicorp/null/data/null_data_source` (data-sources, data_source). The overview and the guide have no Type, so they are not listed.

Pester: "gets docs by -Id, -Type wildcard and -Category"

### 13.3 Get-TerraformProviderDoc -Examples

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3
Get-TerraformProviderDoc -Provider null -Type null_resource -Examples | Format-List Id, ExampleCount, Content
```

Expect: Id `registry.terraform.io/hashicorp/null/resource/null_resource`, ExampleCount `1`, and Content is the HCL only: `resource "aws_instance" "cluster" {` through the `resource "null_resource" "cluster"` block with its `provisioner "remote-exec"`. No ``` fences, front matter or prose.

Pester: "returns only hcl and terraform code blocks with -Examples"

### 13.4 The agent pipeline on infra

The resource graph's nodes piped into Get-TerraformProviderDoc: the pages for the types infra uses, once each, from the caches only. The first two lines fill the null and local schema cache with terraform only when it is missing.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
if (-not (Get-TerraformSchemaCache -Provider hashicorp/null)) { $null = Get-TerraformProviderSchema -Provider hashicorp/null -Version '= 3.2.3' -SaveToCache -Cleanup }
if (-not (Get-TerraformSchemaCache -Provider hashicorp/local)) { $null = Get-TerraformProviderSchema -Provider hashicorp/local -Version '= 2.5.2' -SaveToCache -Cleanup }
Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3
Update-TerraformProviderDocCache -Provider hashicorp/local -Version 2.5.2
Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema |
    Select-Object -ExpandProperty Nodes | Get-TerraformProviderDoc
```

Expect: Two rows and no warnings: `registry.terraform.io/hashicorp/null/resource/null_resource` (one page for the two null_resource blocks) and `registry.terraform.io/hashicorp/local/data/local_file` (data-sources, file). The two terraform_data blocks use the built-in provider and are skipped.

Pester: "returns one doc per distinct matched null/local schema type for a ResourceGraph of infra piped in"

### 13.5 Get-TerraformDocPack -Source dist\schema-packs for vsphere

Needs dist\schema-packs from item 13.6 (or 12.6).

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformDocPack -Provider vsphere -Source .\dist\schema-packs -Force -PassThru | Format-Table
Get-TerraformDocCache -Provider vsphere | Format-Table
```

Expect: `registry.terraform.io/vmware/vsphere 2.17.1 Updated 104225` (Status `Downloaded` if the docs were not cached), then the cache row `registry.terraform.io/vmware/vsphere 2.17.1` with DocCount `87`, UnmatchedCount `0`, Bytes `104225`.

Pester: "downloads only the docs entry with Get-TerraformDocPack from a manifest with both kinds"

### 13.6 Invoke-Build BuildSchemaPack elapsed with docs

Replaces the Expect of 12.6 from 0.11.0: each provider now gets a schema pack and a docs pack. Needs the network.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build BuildSchemaPack
Get-ChildItem .\dist\schema-packs | Format-Table Name, Length
```

Expect: After each schema line, a docs line: `registry.terraform.io/hashicorp/azurerm 5.8.0 docs: 1518 pages, 1 unmatched, 1,182,564 bytes; harvest 00:44; unmatched e.g. data-sources/container_app_environment_dapr_component`, `registry.terraform.io/microsoft/azuredevops 1.16.0 docs: 183 pages, 1 unmatched, 91,929 bytes; ... unmatched e.g. resources/environment_kubernetes_resource` and `registry.terraform.io/vmware/vsphere 2.17.1 docs: 87 pages, 0 unmatched, 104,225 bytes`. Then `Wrote 6 packs (schema and docs) and manifest.json ... in` about 1:17. The folder holds manifest.json (2342 bytes, every entry with a kind), the three schema .json.gz files and three docs.*.json.gz files. Versions and counts follow the registry, so they change over time.

Pester: none

## 14 Classifiers: New-TerraformClassifier, Get-TerraformClassifier, Get-TerraformClassifierFinding, -Classify

Classifiers group resource and data source types into drawers from the providers' own doc subcategories through src\TerraformGraph\classifiers\map.json. The module ships classifiers for azurerm, azuredevops and vsphere. New-TerraformClassifier writes to $env:LOCALAPPDATA\TerraformGraph\classifiers, which is searched before the bundled folder. Items 14.1 to 14.3 and 14.5 need the azurerm, azuredevops and vsphere schemas and docs cached (Get-TerraformSchemaPack and Get-TerraformDocPack, or item 13.6). Items 14.2 and 14.4 write into the real user classifier folder.

### 14.1 Probe: subcategories per provider

The docs cache keeps each page's subcategory. This is the probe the default classifier is built on.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
foreach ($p in 'hashicorp/azurerm', 'microsoft/azuredevops', 'vmware/vsphere') {
    $pages = Get-TerraformProviderDoc -Provider $p -Category resources, data-sources
    $labels = @($pages | Where-Object Subcategory | Group-Object Subcategory)
    "{0}: {1} pages, {2} subcategories, {3} empty" -f $p, $pages.Count, $labels.Count, @($pages | Where-Object { -not $_.Subcategory }).Count
    $labels | Sort-Object Count -Descending | Select-Object -First 5 | Format-Table Count, Name
}
```

Expect: `hashicorp/azurerm: 1503 pages, 112 subcategories, 0 empty`, led by Network 152, Messaging 75, API Management 64, Compute 56 and Data Factory 54. Then `microsoft/azuredevops: 177 pages, 0 subcategories, 177 empty` with no table, because azuredevops publishes no subcategories. Then `vmware/vsphere: 86 pages, 9 subcategories, 0 empty`, led by Host and Cluster Management 22, Virtual Machine 14, Inventory 13, Storage 12 and Networking 7.

Pester: none

### 14.2 New-TerraformClassifier for vsphere

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
New-TerraformClassifier -Provider vmware/vsphere -PassThru
New-TerraformClassifier -Provider vmware/vsphere -PassThru
(Get-TerraformClassifier -Provider vsphere).Types | Group-Object Drawer | Format-Table Count, Name
```

Expect: Two lists, both with ProviderAddress `registry.terraform.io/vmware/vsphere`, Version `2.17.1`, TypeCount `87` and FindingCount `1`. Status is `Written` the first time (`Unchanged` if the file was already there) and `Unchanged` the second time, because the rerun is byte-identical. Then the drawers: compute 36, containers 7, identity 7, management 17, network 7, storage 12, unclassified 1.

Pester: "writes a deterministic classifier: reruns are byte-identical and Unchanged, even after a CRLF checkout", "puts NoDocPage, NoSubcategory and UnmappedSubcategory types in the unclassified drawer; a provider row beats a * row"

### 14.3 Get-TerraformClassifierFinding for azurerm

Reads the bundled azurerm classifier (or your own, if the user folder has one).

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformClassifier -Provider azurerm
Get-TerraformClassifierFinding -Provider azurerm | Group-Object Subcategory | Sort-Object Count -Descending | Format-Table Count, Name
Get-TerraformClassifierFinding -Provider azurerm | Select-Object -First 3
```

Expect: A list with ProviderAddress `registry.terraform.io/hashicorp/azurerm`, Version `5.8.0`, DocsVersion `5.8.0`, TypeCount `1502`, FindingCount `34`. Then the ten unmapped subcategories: Healthcare 11, App Configuration 6, Search 3, Workloads 3, then 2 each for Confidential Ledger, Databox Edge, Extended Location, Graph Services and Maps, and Fluid Relay 1. (In 0.12.0 it was 101 findings: API Management 64 and Connections 3 are now in the integration drawer, DECISIONS 41 and 42.) Then a table with columns Type, Kind, Subcategory, Finding: azurerm_app_configuration (data-source, then resource) and azurerm_app_configuration_feature (resource), all `UnmappedSubcategory`.

Pester: "puts NoDocPage, NoSubcategory and UnmappedSubcategory types in the unclassified drawer; a provider row beats a * row", "keeps the bundled classifiers in step with map.json"

### 14.4 -Classify on infra with the Drawers summary

The first four lines fill the null and local caches only when they are missing, like 13.4.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
if (-not (Get-TerraformSchemaCache -Provider hashicorp/null)) { $null = Get-TerraformProviderSchema -Provider hashicorp/null -Version '= 3.2.3' -SaveToCache -Cleanup }
if (-not (Get-TerraformSchemaCache -Provider hashicorp/local)) { $null = Get-TerraformProviderSchema -Provider hashicorp/local -Version '= 2.5.2' -SaveToCache -Cleanup }
Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3
Update-TerraformProviderDocCache -Provider hashicorp/local -Version 2.5.2
New-TerraformClassifier -Provider hashicorp/null, hashicorp/local
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema -Classify
$graph.Drawers
$graph.Nodes | Format-Table Drawer, Subcategory, ResourceAddress
```

Expect: No warnings. One Drawers row, `unclassified 3 5`: three types (null_resource, local_file, terraform_data) and five blocks. Then the five blocks, all `unclassified` with an empty Subcategory. The null and local providers publish no subcategories, so their classifiers place nothing. terraform_data is the built-in provider, which is unclassified without a warning.

Pester: "leaves resource graph Ids and edges unchanged with -Classify and counts types and instances per drawer", "leaves schema graph Ids, node count and edges unchanged with -Classify and adds Drawer, Subcategory and Drawers"

### 14.5 -ClassifierPath override with your own map

A copy of the bundled map with one row changed (vsphere Workload Management moved from containers to compute), classified into a temp folder and passed as -ClassifierPath. The bundled classifier is shown after it for comparison.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$work = Join-Path $env:TEMP "classifier-check-$([guid]::NewGuid().ToString('n'))"
New-Item -ItemType Directory -Path $work | Out-Null
$map = Get-Content .\src\TerraformGraph\classifiers\map.json -Raw | ConvertFrom-TerraformJson -AsHashtable
$row = $map.rows | Where-Object { $_.provider -eq 'registry.terraform.io/vmware/vsphere' -and $_.subcategory -eq 'Workload Management' }
$row.drawer = 'compute'; $row.reason = 'Our view: supervisors and namespaces are part of the compute estate.'; $row.addedBy = 'jerry'
$map | ConvertTo-TerraformJson | Set-Content (Join-Path $work 'map.json')
New-TerraformClassifier -Provider vmware/vsphere -MapPath (Join-Path $work 'map.json') -OutputPath (Join-Path $work 'classifiers') -PassThru | Format-Table
(ConvertTo-TerraformSchemaGraph -Provider vsphere -ClassifierPath (Join-Path $work 'classifiers')).Drawers | Format-Table
(ConvertTo-TerraformSchemaGraph -Provider vsphere -Classify).Drawers | Format-Table
Remove-Item -LiteralPath $work -Recurse -Force
```

Expect: `registry.terraform.io/vmware/vsphere 2.17.1 Written 87 1`. Then the override drawers: network 7, compute 43, storage 12, identity 7, management 17, unclassified 1, with no containers row and InstanceCount empty. Then the default drawers: network 7, compute 36, storage 12, identity 7, management 17, containers 7, unclassified 1.

Pester: "uses -ClassifierPath over the user folder, and the user folder over a newer bundled classifier"

### 14.6 Invoke-Build BuildClassifier

Regenerates the bundled classifiers from the local caches with no network, then prints the findings per provider.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$before = (Get-FileHash .\src\TerraformGraph\classifiers\*.json).Hash
Invoke-Build BuildClassifier
"unchanged: $(-not (Compare-Object $before (Get-FileHash .\src\TerraformGraph\classifiers\*.json).Hash))"
```

Expect: `registry.terraform.io/hashicorp/azurerm 5.8.0 (docs 5.8.0): Unchanged, 1502 types, 34 findings`, a drawers line (network 178, compute 175, storage 121, database 122, identity 20, security 95, messaging 81, integration 86, ... unclassified 34; no serverless entry, since Logic App moved to integration) and a table of ten `UnmappedSubcategory` rows. Then `registry.terraform.io/microsoft/azuredevops 1.16.0 (docs 1.16.0): Unchanged, 177 types, 0 findings` with `drawers: identity 27, management 1, devops 149` and no table. Then `registry.terraform.io/vmware/vsphere 2.17.1 (docs 2.17.1): Unchanged, 87 types, 1 findings` with `NoDocPage 1`. About 6 s in all. Status is `Updated` only after map.json or the caches change. Then `unchanged: True`, because no file was rewritten.

Pester: "keeps the bundled classifiers in step with map.json"

## 15 Bundle and survey: Get-TerraformGraphBundle, New-TerraformGraphBundle, Test-TerraformGraphBundle, Get-TerraformSubcategorySurvey, Update-TerraformProviderDocCache -BundlePath

Data for 15.1, 15.5 and 15.6 comes from the HarvestBundleDocs run of 2026-10-07; counts and dates move when the bundle is harvested again.

### 15.1 Get-TerraformGraphBundle

Reads the bundled manifest. The default view is a table of entries.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformGraphBundle -Path .\src\TerraformGraph\data\bundle.json
Get-TerraformGraphBundle -Path .\src\TerraformGraph\data\bundle.json -Document | Format-List Tiers, Providers, Exclude, RegistryHarvestedOn, RegistryProviderCount, EntryCount
```

Expect: a table of 36 rows, ProviderAddress, Version, DocsVersion, SchemaVersion, ClassifierVersion, HarvestedOn, sorted by address from `registry.terraform.io/ansible/aap` to `registry.terraform.io/vmware/vsphere`. Every DocsVersion equals Version. Only azurerm 5.8.0, azuredevops 1.16.0 and vsphere 2.17.1 have SchemaVersion and ClassifierVersion. Then the list: Tiers `{official}`, Providers `{registry.terraform.io/microsoft/azuredevops, registry.terraform.io/vmware/vsphere}`, Exclude `{}`, RegistryHarvestedOn `2026-10-07T02:55:12Z`, RegistryProviderCount `428`, EntryCount `36`. Versions and dates follow the last HarvestBundleDocs run.

Pester: "exports the bundle commands and ships a bundled manifest with the official tier and two extras", "takes unbound -Tier, -Provider and -Exclude from the bundled manifest, and reads the user copy first"

### 15.2 New-TerraformGraphBundle to a temp path

Resolves a wildcard and an exclusion against the bundled registry cache, rewrites byte-identically, and rejects a pattern that matches nothing. Never touches the network.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$out = Join-Path $env:TEMP 'tg-bundle-15-2.json'
New-TerraformGraphBundle -Tier @() -Provider 'hashicorp/azure*', vmware/vsphere -Exclude hashicorp/azurestack -OutputPath $out -PassThru | Format-List Tiers, Providers, Exclude, EntryCount
Get-TerraformGraphBundle -Path $out | Format-Table ProviderAddress, Version, DocsVersion, SchemaVersion, ClassifierVersion
$hash = (Get-FileHash $out).Hash
New-TerraformGraphBundle -Tier @() -Provider 'hashicorp/azure*', vmware/vsphere -Exclude hashicorp/azurestack -OutputPath $out
(Get-FileHash $out).Hash -eq $hash
New-TerraformGraphBundle -Tier @() -Provider 'nosuchnamespace/x*' -OutputPath $out
Remove-Item $out
```

Expect: Tiers `{}`, Providers listing the four addresses the wildcard and vsphere matched (azuread, azurerm, azurestack, vsphere: `providers` keeps the expansion, the exclusion applies when resolving), Exclude `{hashicorp/azurestack}`, EntryCount `3`. Then three rows: azuread 3.10.0 with DocsVersion 3.10.0 and no schema or classifier, azurerm 5.8.0 and vsphere 2.17.1 with all four versions. Then `True` (the rewrite is byte-identical). Then the error `'nosuchnamespace/x*' matches no provider in the registry cache C:\__Code\TerraformGraph\src\TerraformGraph\data\registry.json (harvested 2026-10-07T02:55:12Z). Run Update-TerraformRegistryCache, or fix the pattern.`

Pester: "resolves tiers, extra providers and exclusions against the registry cache in New-TerraformGraphBundle"

### 15.3 Update-TerraformProviderDocCache -BundlePath -Resume on the two extras

A bundle of just azuredevops and vsphere, both already cached, so -Resume makes no network call.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$out = Join-Path $env:TEMP 'tg-bundle-15-3.json'
New-TerraformGraphBundle -Tier @() -Provider microsoft/azuredevops, vmware/vsphere -Exclude @() -OutputPath $out
$summary = Update-TerraformProviderDocCache -BundlePath $out -Resume
$summary | Format-List ProviderCount, PageCount, UnmatchedCount, FailureCount, Elapsed
$summary.Providers | Format-Table ProviderAddress, Version, Status, DocCount, UnmatchedCount
Remove-Item $out
```

Expect: ProviderCount `2`, PageCount `270`, UnmatchedCount `1`, FailureCount `0`, Elapsed well under a second. Then `registry.terraform.io/microsoft/azuredevops 1.16.0 Cached 183 1` and `registry.terraform.io/vmware/vsphere 2.17.1 Cached 87 0`. Without -Resume the same call harvests both again over the network (7 s for the two in the 2026-10-07 run).

Pester: "harvests a bundle provider by provider: a failure is a warning and a Failed row, and -Resume skips cached versions offline"

### 15.4 Get-TerraformSubcategorySurvey for vsphere

One row per label from the docs cache only.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformSubcategorySurvey -Provider vsphere
```

Expect: a table of nine rows, ProviderAddress, Subcategory, ResourceCount, DataSourceCount, Status, all `Labeled`: Administration 1 1, Host and Cluster Management 14 8, Inventory 6 7, Lifecycle 1 1, Networking 5 2, Security 4 3, Storage 7 5, Virtual Machine 8 6, Workload Management 5 2. No NoSubcategory row: every vsphere page is labelled.

Pester: "returns one row per provider and label, with a NoSubcategory row for unlabelled pages"

### 15.5 azuredevops drawers after the prefix map

Reads the bundled classifier directly, so a classifier in your user folder cannot shadow it.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$devops = Get-TerraformClassifier -Provider microsoft/azuredevops -ClassifierPath .\src\TerraformGraph\classifiers
$devops | Format-List Version, Source, TypeCount, FindingCount
$devops.Types | Group-Object Drawer | Sort-Object Count -Descending | Format-Table Count, Name
$devops.Types | Where-Object Type -like 'azuredevops_git*' | Format-Table Type, Kind, Drawer, Source
```

Expect: Version `1.16.0`, Source `subcategory,prefix`, TypeCount `177`, FindingCount `0`. Then devops 149, identity 27, management 1 (in 0.12.0 all 177 were unclassified: 176 NoSubcategory, 1 NoDocPage). Then seven git rows, from azuredevops_git_permissions to azuredevops_git_repository_file, all `devops` with Source `prefix`.

Pester: "keeps every bundled prefix row matching a type of its provider's bundled classifier", "places only unlabelled types by prefix, longest prefix first, and records the row kind per type"

### 15.6 Test-TerraformGraphBundle -Strict

The release gate on the shipped data, then on a copy with one deliberate change. Run from the repo root so dist\schema-packs is checked too.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Test-TerraformGraphBundle -BundlePath .\src\TerraformGraph\data\bundle.json -Strict | Group-Object Status | Format-Table Count, Name
Test-TerraformGraphBundle -BundlePath .\src\TerraformGraph\data\bundle.json | Where-Object Item -like '*azuredevops*' | Format-Table -AutoSize -Wrap
$stale = Join-Path $env:TEMP 'tg-bundle-15-6.json'
(Get-Content .\src\TerraformGraph\data\bundle.json -Raw).Replace('"providerCount": 428', '"providerCount": 427') | Set-Content $stale
Test-TerraformGraphBundle -BundlePath $stale -Strict | Out-Null
pwsh -NoProfile -Command "Import-Module .\src\TerraformGraph\TerraformGraph.psd1; Test-TerraformGraphBundle -BundlePath $stale -Strict | Out-Null"; "exit $LASTEXITCODE"
Remove-Item $stale
```

Expect: `89 Fresh` (no Stale or Missing, no error; the 89th is the `sources` row added in 0.14.0). Then seven azuredevops rows, all Fresh, as a table of Item, Status and an empty RecommendedAction: entry, docs, schema, classifier, mapVersion, pack schema and pack docs. Then the -Strict error `1 of 89 bundle checks are not fresh (...tg-bundle-15-6.json): registry [Stale]: The bundle was resolved against a registry cache harvested 2026-10-07T02:55:12Z (427 providers); ...data\registry.json was harvested 2026-10-07T02:55:12Z (428 providers). Rerun New-TerraformGraphBundle ... Fix: New-TerraformGraphBundle -Tier 'official' -Provider 'registry.terraform.io/microsoft/azuredevops','registry.terraform.io/vmware/vsphere' -Exclude @() -OutputPath '...tg-bundle-15-6.json'`, ending `Each row's InspectAction shows the change first; its RecommendedAction makes it.`, the same error from the child process, and `exit 1`. Without dist\schema-packs there are 83 rows (no pack rows).

Pester: "reports Fresh, Stale and Missing rows in Test-TerraformGraphBundle and throws with -Strict", "checks each bundled classifier's mapVersion against map.json"

### 15.7 Invoke-Build HarvestBundleDocs elapsed

With -Resume and every provider cached this takes seconds and shows the task's full output. Without -Resume it harvests all 36 providers again (network). It ends by refreshing data\bundle.json and writing dist\survey\subcategories.json, both byte-identical when nothing changed.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build HarvestBundleDocs -Resume
git status --short -- src\TerraformGraph\data
```

Expect: 36 rows, all `Cached`, the largest awscc 1.104.0 4521, aws 6.67.0 2414, google and google-beta 8.6.0 1685, azurerm 5.8.0 1518 and ibm 2.6.2 1445. The task first prints `Harvest log: ...\TerraformGraph\logs\harvest-<yyyyMMdd-HHmmss>.log`. Then `Providers 36, pages 14,686, unmatched 3, failures 0, rate-limit hits 0 (0 s blocked), partial resumes 0, elapsed 00:00:03`, `Log: ...harvest-<timestamp>.log`, `Refreshed ...data\bundle.json`, `Survey: 36 providers (0 missing), 661 distinct labels, 893 rows, 28 providers with unlabelled pages`, and the top 20 labels, led by nine labels with providerCount 3 (Agent Registry, API Gateway, Base, Cloud IAM, Cloud Platform, Container Registry, License Manager, Service Networking, Storage). About 25 s (2026-10-07). git status shows no change to data\ beyond what is already staged: the rewrite is byte-identical, `sources` included. Measured full runs on 2026-10-07: without -Resume, 12 min 28 s, 3,374 pages, 17 providers failed with 429 (backoff before 0.13.0); then -Resume with the 0.13.0 backoff, 12 min 17 s, the 17 harvested, 0 failures.

Pester: none

## 16 Hardening and contracts (0.14.0): harvest resume, shadowed classifiers, RecommendedAction, sources, drawer semver

Cross-cutting checks for 0.14.0. Each block is self-contained; the network is used only by 16.1 (six pages of hashicorp/local).

### 16.1 Kill a docs harvest and resume it

A harvest stopped part-way keeps its pages in `<version>.partial.json`; `-Resume` fetches only the rest and removes the file. Uses local 2.9.0 so the bundled 2.9.1 docs are not touched, and removes 2.9.0 again at the end. Do not run it while another harvest is going.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$folder = Join-Path $env:LOCALAPPDATA 'TerraformGraph\docs\registry.terraform.io-hashicorp-local'
# 1. Harvest local 2.9.0 and stop it after its first page.
#    By hand: run  Update-TerraformProviderDocCache -Provider hashicorp/local -Version 2.9.0 -ThrottleLimit 1 -Force -Verbose
#    and press Ctrl+C right after the first "GET .../v2/provider-docs/..." line. local has six
#    pages and finishes in about a second, so this block stops it from a second PowerShell
#    instead: PowerShell.Stop() is the call Ctrl+C makes. (Stop-Job on a Start-Job, or killing
#    the process, does not run the cleanup that writes the file; only the every-100-pages
#    checkpoint survives that.)
$ps = [powershell]::Create().AddScript({
        Set-Location 'C:\__Code\TerraformGraph'
        Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
        Update-TerraformProviderDocCache -Provider hashicorp/local -Version 2.9.0 -ThrottleLimit 1 -Force -Verbose
    })
$run = $ps.BeginInvoke()
while (@($ps.Streams.Verbose | Where-Object { "$_" -like 'WebResponse*' }).Count -lt 3 -and -not $run.IsCompleted) { Start-Sleep -Milliseconds 10 }
$ps.Stop(); $ps.Dispose()
# 2. The partial file: the pages fetched before the stop, and no 2.9.0 cache file.
Get-ChildItem -LiteralPath $folder | Format-Table Name, Length
Get-Content -LiteralPath (Join-Path $folder '2.9.0.partial.json') -Raw | ConvertFrom-TerraformJson | Format-List address, version, versionId, pageCount
# 3. Resume: only the missing pages are fetched, the cache is written and the partial file is gone.
Update-TerraformProviderDocCache -Provider hashicorp/local -Version 2.9.0 -Resume -PassThru -WarningAction SilentlyContinue | Format-Table ProviderAddress, Version, Status, DocCount, ResumedPages
Get-ChildItem -LiteralPath $folder | Format-Table Name, Length
Remove-Item -LiteralPath (Join-Path $folder '2.9.0.json.gz')
```

Expect: first `2.5.2.json.gz`, `2.9.0.partial.json` (about 6.7 KB) and `2.9.1.json.gz`, and no `2.9.0.json.gz`. Then the partial file's head: address `registry.terraform.io/hashicorp/local`, version `2.9.0`, versionId `96611`, pageCount `1` (one page was in before the stop; a slower machine may show 2). Then the resumed row `registry.terraform.io/hashicorp/local 2.9.0 Harvested 6 1` (DocCount 6, ResumedPages equal to the pageCount above), and the folder now holds `2.5.2.json.gz`, `2.9.0.json.gz` and `2.9.1.json.gz` with no partial file.

Pester: "keeps the pages of a harvest killed after page 3 of 6 in a partial file, and -Resume finishes from it"

### 16.2 Shadowed classifiers

A stale user copy of a bundled classifier at the same version loses to the bundled one, with a warning, and `-Shadowed` lists the collision. Writes one file to your user classifiers folder and removes it.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
# A stale user copy of the bundled vsphere 2.17.1 classifier: built from an older map, a day earlier.
$bundled = Join-Path (Split-Path (Get-Module TerraformGraph).Path) 'classifiers\registry.terraform.io-vmware-vsphere.2.17.1.json'
$userFolder = Join-Path $env:LOCALAPPDATA 'TerraformGraph\classifiers'
$null = New-Item -ItemType Directory -Path $userFolder -Force
$stale = Join-Path $userFolder 'registry.terraform.io-vmware-vsphere.2.17.1.json'
$text = Get-Content -LiteralPath $bundled -Raw
$text = [regex]::Replace($text, '"mapVersion": "[0-9a-f]+"', '"mapVersion": "000000000000"')
$text = [regex]::Replace($text, '"generatedOn": "[^"]+"', '"generatedOn": "2026-10-01T00:00:00Z"')
Set-Content -LiteralPath $stale -Value $text -NoNewline
Get-TerraformClassifier -Provider vsphere | Format-Table ProviderAddress, Version, TypeCount, Path -Wrap
Get-TerraformClassifier -Shadowed
Get-TerraformClassifier -Shadowed | Format-List ShadowedPath
Remove-Item -LiteralPath $stale
Get-TerraformClassifier -Shadowed
'after cleanup: no rows above this line'
```

Expect: `WARNING: Classifier registry.terraform.io/vmware/vsphere 2.17.1: using ...\src\TerraformGraph\classifiers\registry.terraform.io-vmware-vsphere.2.17.1.json (mapVersion 8edf85177cf6 matches map.json); ...\AppData\Local\TerraformGraph\classifiers\registry.terraform.io-vmware-vsphere.2.17.1.json (mapVersion 000000000000, generatedOn 2026-10-01T00:00:00Z) is shadowed. Remove-Item -LiteralPath '...' removes it.` Then the classifier row (87 types) with the bundled Path. Then one `-Shadowed` row: `registry.terraform.io/vmware/vsphere 2.17.1 Bundled mapVersion 8edf85177cf6 matches map.json`, ShadowedPath the user file, and after the cleanup no rows before the last line.

Pester: "uses the bundled classifier over an older-map user classifier of the same version, warns naming the shadowed file, and lists it with -Shadowed", "uses the newer generatedOn when both match the map, keeps an older user version over a newer bundled one, and lets -ClassifierPath win"

### 16.3 Test-TerraformGraphBundle RecommendedAction on a stale temp bundle

A temp bundle whose registry cache moved on after it was written: Stale rows carry a pasteable InspectAction and RecommendedAction; running them shows the diff, then fixes it.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
# A temp bundle for hashicorp/null resolved against a registry.json beside it; then that
# registry cache "moves on" (its harvestedOn changes) and the bundle is not refreshed.
$tmp = Join-Path $env:TEMP 'tg-bundle-16-3'
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Ignore
$null = New-Item -ItemType Directory -Path $tmp
Copy-Item -LiteralPath .\src\TerraformGraph\data\registry.json -Destination $tmp
New-TerraformGraphBundle -Tier @() -Provider hashicorp/null -Exclude @() -OutputPath "$tmp\bundle.json"
$registry = "$tmp\registry.json"
(Get-Content -LiteralPath $registry -Raw).Replace('"harvestedOn": "2026-10-07T02:55:12Z"', '"harvestedOn": "2026-10-08T00:00:00Z"') | Set-Content -LiteralPath $registry
Test-TerraformGraphBundle -BundlePath "$tmp\bundle.json" -DistPath $tmp | Format-Table -Wrap
$row = Test-TerraformGraphBundle -BundlePath "$tmp\bundle.json" -DistPath $tmp | Where-Object Item -eq 'registry'
$row | Format-List Item, Status, Detail, InspectAction, RecommendedAction
Invoke-Expression $row.InspectAction
Invoke-Expression $row.RecommendedAction
Test-TerraformGraphBundle -BundlePath "$tmp\bundle.json" -DistPath $tmp | Group-Object Status | Format-Table Count, Name
Remove-Item -LiteralPath $tmp -Recurse -Force
```

Expect: a table of Item, Status, RecommendedAction with `registry` and `sources` Stale, both with `New-TerraformGraphBundle -Tier @() -Provider 'registry.terraform.io/hashicorp/null' -Exclude @() -OutputPath '...\tg-bundle-16-3\bundle.json'`, and entry, docs and three mapVersion rows Fresh with no action. Then the registry row in full: Detail `The bundle was resolved against a registry cache harvested 2026-10-07T02:55:12Z (428 providers); ...\tg-bundle-16-3\registry.json was harvested 2026-10-08T00:00:00Z (428 providers). ...`, an InspectAction that copies registry.json into `$env:TEMP\TerraformGraph-inspect`, writes a candidate bundle there and ends `git diff --no-index -- '...\tg-bundle-16-3\bundle.json' "$env:TEMP\TerraformGraph-inspect\bundle.json"`, and the RecommendedAction above. Then the diff: registry `harvestedOn` and the registry source's `lastPulled` change from `2026-10-07T02:55:12Z` to `2026-10-08T00:00:00Z` (two LF/CRLF warnings from git first). Then `7 Fresh`.

Pester: "reports Fresh, Stale and Missing rows in Test-TerraformGraphBundle and throws with -Strict", "checks each bundled classifier's mapVersion against map.json"

### 16.4 Get-TerraformGraphBundle -Sources

Where each kind of bundled data comes from, from the shipped manifest.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformGraphBundle -Sources
Get-TerraformGraphBundle -Sources | Where-Object Kind -eq docs | Format-List Kind, Urls, RelatedUrls, HarvestedBy, LastPulled
```

Expect: six rows, Kind, HarvestedBy, LastPulled, Urls: registry `Update-TerraformRegistryCache` 2026-10-07T02:55:12Z; schemas `Get-TerraformProviderSchema` 2026-10-07T03:58:00Z; docs `Update-TerraformProviderDocCache` 2026-10-07T05:19:53Z; classifiers `New-TerraformClassifier` 2026-10-07T05:22:55Z; skills `Install-TerraformGraphSkill` with no LastPulled; cmdb with nothing but its kind and `{}` Urls. Then the docs row in full: Urls `https://registry.terraform.io/v2/provider-versions/{id}?include=provider-docs` and `https://registry.terraform.io/v2/provider-docs/{id}`, RelatedUrls `https://developer.hashicorp.com/terraform/registry/providers/docs`.

Pester: "names the sources of a bundle: written by New-TerraformGraphBundle, shown by -Document and -Sources"

### 16.5 Drawer semver gate

The Pester test "drawers are semver-safe" passes an added drawer and fails a renamed one at 0.15.0. `$env:TERRAFORMGRAPH_DRAWERS_PATH` points the test at a temp copy of drawers.json.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$drawers = Join-Path $env:TEMP 'tg-drawers-16-5.json'
$json = Get-Content -LiteralPath .\src\TerraformGraph\classifiers\drawers.json -Raw
# An added drawer (before unclassified): minor, passes.
$json.Replace('    { "name": "unclassified"', "    { `"name`": `"desktop`", `"label`": `"Desktop`", `"description`": `"Virtual desktops.`" },`n    { `"name`": `"unclassified`"") | Set-Content -LiteralPath $drawers
$env:TERRAFORMGRAPH_DRAWERS_PATH = $drawers
(Invoke-Pester -Path .\tests -FullNameFilter 'Contracts.drawers are semver-safe' -PassThru -Output None) | Format-Table PassedCount, FailedCount
# A renamed drawer (devops -> developer): major, fails at 0.15.0.
$json.Replace('"name": "devops"', '"name": "developer"') | Set-Content -LiteralPath $drawers
$result = Invoke-Pester -Path .\tests -FullNameFilter 'Contracts.drawers are semver-safe' -PassThru -Output None
$result | Format-Table PassedCount, FailedCount
$result.Failed[0].ErrorRecord[0].Exception.Message
Remove-Item Env:\TERRAFORMGRAPH_DRAWERS_PATH
Remove-Item -LiteralPath $drawers
```

Expect: `1 0` (passed, failed) for the added drawer, then `0 1` for the rename and the message `Expected $null or empty, because drawers devops of 0.14.1 are renamed or removed in 0.15.0, which needs a major version (ModuleVersion 1.0.0), but got 'devops'.` (0.14.1 is the newest tag below the psd1 version; seen on 2026-10-07.)

Pester: "drawers are semver-safe"

## 17 Day-one fixes (0.14.1): UTF-8, parser guard, test tags, Repo-scope gate, module tree, import time, publish

### 17.1 UTF-8 fixture round-trips

A non-ASCII string literal comes back unchanged, and a folder with a non-ASCII name parses.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$value = (Get-TerraformAST -FilePath .\tests\fixtures\hcl\utf8\main.tf).Body.Attributes.description.Expr.Value
$value
$value -ceq "caf$([char]0xE9) $([char]0x2013) $([char]0x6771)$([char]0x4EAC)"
$folder = Get-ChildItem .\tests\fixtures\hcl -Directory -Filter 'enc-*'
$folder.Name
Get-TerraformAST -Path $folder.FullName | Format-Table Type, Name, File
```

Expect: `café – 東京`, `True`, `enc-日本`, then one row: `variable`, `region`, `main.tf`. (Before 0.14.1 the string came back as `cafÃ© â€“ æ±äº¬` and the folder failed with `open …\enc-??\main.tf`.)

Pester: "returns a non-ASCII string literal unchanged", "parses -Path on a folder with a non-ASCII name"

### 17.2 Get-TerraformAST under the forced-unavailable parser

What a Linux or Windows ARM user sees: the parser commands stop with ParserUnavailable, the rest of the module works.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
& (Get-Module TerraformGraph) {
    $script:TerraformGraphParserAvailable = $false
    $script:TerraformGraphParserUnavailableReason = "TerraformGraph's HCL parser ships for Windows x64 only; Test OS Arm64 detected. Schema, registry, docs, classifier and bundle commands work without it."
}
try { Get-TerraformAST -Path .\infra -ErrorAction Stop } catch { $_.FullyQualifiedErrorId; $_.Exception.Message }
(Get-TerraformRegistryProvider -Name hashicorp/null).ProviderAddress
Remove-Module TerraformGraph -Force
```

Expect: `ParserUnavailable,Get-TerraformAST`, then `TerraformGraph's HCL parser ships for Windows x64 only; Test OS Arm64 detected. Schema, registry, docs, classifier and bundle commands work without it.`, then `registry.terraform.io/hashicorp/null`.

Pester: "throws ParserUnavailable from Get-TerraformAST and Get-TerraformModuleGraph", "leaves the commands that do not parse working"

### 17.3 Default Pester run with terraform removed from PATH

The default run needs no network and no terraform: RequiresTerraform tests are skipped, not failed, and Live tests are excluded.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$path = (($env:PATH -split ';') | Where-Object { $_ -and -not (Test-Path (Join-Path $_ 'terraform.exe')) }) -join ';'
pwsh -NoProfile -Command "`$env:PATH = '$path'; 'terraform on PATH: ' + [bool](Get-Command terraform -ErrorAction SilentlyContinue); .\tests\Invoke-Tests.ps1" 2>&1 | Select-String 'terraform on PATH|Tests Passed'
"exit code $LASTEXITCODE"
```

Expect: `terraform on PATH: False`, then `Tests Passed: 176, Failed: 0, Skipped: 53, Inconclusive: 0, NotRun: 17` (53 RequiresTerraform tests skipped, 17 Live tests excluded; with both DLLs built), then `exit code 0`.

Pester: none (the item is the suite itself)

### 17.4 Test-TerraformGraphBundle -Scope Repo with the user cache present and absent

Repo scope reads no user cache, so its rows are identical with the cache and without it; Machine scope differs.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$empty = Join-Path $env:TEMP 'tg-check-emptycache'
$null = New-Item -ItemType Directory -Path $empty -Force
$rows = { param($Scope) pwsh -NoProfile -Command "Import-Module .\src\TerraformGraph\TerraformGraph.psd1; Test-TerraformGraphBundle -BundlePath .\src\TerraformGraph\data\bundle.json -Scope $Scope | ForEach-Object { `$_.Item + '|' + `$_.Status + '|' + `$_.Detail }" }
$repoWith = & $rows Repo; $machineWith = & $rows Machine
$saved = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $empty
$repoWithout = & $rows Repo; $machineWithout = & $rows Machine
$env:LOCALAPPDATA = $saved
"Repo:    $($repoWith.Count) rows with the cache, $($repoWithout.Count) without, identical $(-not (Compare-Object $repoWith $repoWithout -SyncWindow 0))"
"Machine: $($machineWith.Count) rows with the cache, $($machineWithout.Count) without, identical $(-not (Compare-Object $machineWith $machineWithout -SyncWindow 0))"
$repoWith | ForEach-Object { ($_ -split '\|')[1] } | Group-Object -NoElement | Format-Table Name, Count
Remove-Item -LiteralPath $empty -Recurse -Force
```

Expect: `Repo:    50 rows with the cache, 50 without, identical True`, `Machine: 89 rows with the cache, 89 without, identical False`, then one group: `Fresh 50`.

Pester: "returns the same -Scope Repo rows with a populated user cache as with an empty one"

### 17.5 AssembleModule tree matches FileList

The publishable tree holds exactly the files the psd1 FileList names, and Test-ModuleManifest passes on it.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build AssembleModule
$tree = '.\dist\module\TerraformGraph'
$files = Get-ChildItem $tree -File -Recurse | ForEach-Object { [IO.Path]::GetRelativePath((Resolve-Path $tree), $_.FullName).Replace('\', '/') } | Sort-Object
$list = (Import-PowerShellDataFile "$tree\TerraformGraph.psd1").FileList | Sort-Object
"tree $($files.Count) files, FileList $($list.Count), identical $(-not (Compare-Object $files $list))"
$files
```

Expect: `Assembled TerraformGraph 0.15.0: 16 files, ...` (14,029,070 bytes on 2026-10-07) and `Build succeeded`, then `tree 16 files, FileList 16, identical True`, then the 16 paths: six under classifiers/, data/bundle.json, data/registry.json, lib/TerraformGraph.dll, lib/TerraformGraph.Json.dll, LICENSE, NOTICE, skills/terraformgraph/SKILL.md, TerraformGraph.Format.ps1xml, TerraformGraph.psd1, TerraformGraph.psm1. No .old, .h or .cs file.

Pester: "lists in the psd1 FileList exactly what tools/Copy-TerraformGraphModule.ps1 assembles", "assembles a tree that holds exactly the FileList and passes Test-ModuleManifest"

### 17.6 Import time

Three fresh imports, with lib\TerraformGraph.Json.dll from Invoke-Build BuildJson (without it the module compiles TerraformGraph.Json.cs, about half a second more).

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Test-Path .\src\TerraformGraph\lib\TerraformGraph.Json.dll
1..3 | ForEach-Object { pwsh -NoProfile -Command '$sw = [Diagnostics.Stopwatch]::StartNew(); Import-Module .\src\TerraformGraph\TerraformGraph.psd1; "{0} ms" -f $sw.ElapsedMilliseconds' }
```

Expect: `True`, then three times of about half a second (537, 449 and 524 ms on 2026-10-07). Without lib\TerraformGraph.Json.dll the same runs took 1,521 to 3,236 ms on a busier machine the same day.

Pester: none

### 17.7 Publish-PSResource to a temporary local repository

A dry run of the Gallery publish: the package holds the assembled tree and no `.old` or `.h` file. Run 17.5 first (it needs dist\module\TerraformGraph).

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
$repo = Join-Path $env:TEMP 'tg-check-psrepo'
$null = New-Item -ItemType Directory -Path $repo -Force
Register-PSResourceRepository -Name TGCheckLocal -Uri $repo -Trusted
Publish-PSResource -Path .\dist\module\TerraformGraph -Repository TGCheckLocal
$package = Get-ChildItem $repo -Filter *.nupkg
"$($package.Name) $($package.Length) bytes"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($package.FullName)
$zip.Entries.FullName | Where-Object { $_ -notmatch '^(_rels|package)/|\[Content_Types\]|\.nuspec$' } | Sort-Object
"old or h files: $(@($zip.Entries.FullName | Where-Object { $_ -like '*.old' -or $_ -like '*.h' }).Count)"
$zip.Dispose()
Unregister-PSResourceRepository -Name TGCheckLocal
Remove-Item -LiteralPath $repo -Recurse -Force
```

Expect: `TerraformGraph.0.15.0.nupkg` of about 3.4 MB (3,446,066 bytes on 2026-10-07), the same 16 paths as 17.5, then `old or h files: 0`. The repository is unregistered and the folder removed at the end.

Pester: none

## 18 Module split (0.15.0): one function per file, the assembled psm1

### 18.1 Three-way diff: v0.14.1, src and dist

The surface and the code are the same before and after the split: every exported command's parameter sets, parameters, types, positions, pipeline binding and aliases, then a SHA-256 of every function body in the module (public and private), from three fresh processes: the v0.14.1 psm1 (from git) in a copy of the assembled tree, the split src tree, and the assembled dist tree.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build AssembleModule | Out-Null
$work = Join-Path $env:TEMP 'tg-check-split'
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item .\dist\module\TerraformGraph -Destination (Join-Path $work 'TerraformGraph') -Recurse
git show v0.14.1:src/TerraformGraph/TerraformGraph.psm1 | Set-Content -LiteralPath (Join-Path $work 'TerraformGraph' 'TerraformGraph.psm1') -Encoding utf8NoBOM
$surface = Join-Path $env:TEMP 'tg-check-surface.ps1'
Set-Content -LiteralPath $surface -Encoding utf8NoBOM -Value @'
param($Psd1)
$env:TERRAFORMGRAPH_SKILL_HINT = '0'
$module = Import-Module $Psd1 -PassThru
$common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters
foreach ($command in Get-Command -Module TerraformGraph | Sort-Object Name) {
    foreach ($set in $command.ParameterSets | Sort-Object Name) {
        foreach ($p in $set.Parameters | Where-Object Name -notin $common | Sort-Object Name) {
            "$($command.Name) $($set.Name) default=$($set.IsDefault) -$($p.Name) [$($p.ParameterType.Name)] mandatory=$($p.IsMandatory) position=$($p.Position) pipeline=$($p.ValueFromPipeline)/$($p.ValueFromPipelineByPropertyName) aliases=$(@($p.Aliases | Sort-Object) -join ',')"
        }
    }
}
& $module {
    Get-ChildItem Function: | Where-Object { $_.Module.Name -eq 'TerraformGraph' } | Sort-Object Name | ForEach-Object {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($_.ScriptBlock.Ast.Extent.Text -replace "`r`n", "`n"))
        "function $($_.Name) $([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))"
    }
}
'@
try {
    $v0141 = pwsh -NoProfile -File $surface (Join-Path $work 'TerraformGraph' 'TerraformGraph.psd1')
    $src = pwsh -NoProfile -File $surface (Resolve-Path .\src\TerraformGraph\TerraformGraph.psd1).Path
    $dist = pwsh -NoProfile -File $surface (Resolve-Path .\dist\module\TerraformGraph\TerraformGraph.psd1).Path
    "lines: v0.14.1 $($v0141.Count), src $($src.Count), dist $($dist.Count); functions $(@($src -like 'function *').Count)"
    "v0.14.1 vs src:  $(@(Compare-Object $v0141 $src -SyncWindow 0).Count) differences"
    "v0.14.1 vs dist: $(@(Compare-Object $v0141 $dist -SyncWindow 0).Count) differences"
    "src vs dist:     $(@(Compare-Object $src $dist -SyncWindow 0).Count) differences"
}
finally {
    Remove-Item -LiteralPath $surface -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force
}
```

Expect: the AssembleModule line (`Assembled TerraformGraph 0.15.0: 16 files, ...`), then `lines: v0.14.1 239, src 239, dist 239; functions 108`, then `0 differences` on all three comparison lines (seen on 2026-10-07 with the surface script run by `pwsh -File`). The temp script and folder are removed at the end. The full proof of the split (the default test run, the AssembleModule file list and the module-scope variables as well) is in dist\split-proof from the 0.15.0 task; the only differences there are the shipped psm1's size and the six new tests.

Pester: "names a documented fixing command for every terminating error id in the assembled dist psm1", "resolves every term in ONTOLOGY.md's terminology table against the assembled dist psm1"

### 18.2 Import time, src and dist

Three fresh imports each of the split source tree (108 files dot-sourced) and the assembled module (one psm1), with lib\TerraformGraph.Json.dll present.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build AssembleModule | Out-Null
foreach ($psd1 in '.\src\TerraformGraph\TerraformGraph.psd1', '.\dist\module\TerraformGraph\TerraformGraph.psd1') {
    1..3 | ForEach-Object { pwsh -NoProfile -Command "`$env:TERRAFORMGRAPH_SKILL_HINT = '0'; `$sw = [Diagnostics.Stopwatch]::StartNew(); Import-Module '$psd1'; '{0}  {1} ms' -f '$psd1', `$sw.ElapsedMilliseconds" }
}
```

Expect: the AssembleModule line, then three src times and three dist times. On 2026-10-07: src 1,207, 1,180 and 1,331 ms; dist 441, 431 and 451 ms. Dot-sourcing 108 files costs src about 0.7 s over dist; the release imports dist.

Pester: none

### 18.3 File counts

One file per function: 26 under Public (the exported commands), 82 under Private, no Classes folder, and a psm1 that is wiring only. Every exported command is defined in a Public file.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-ChildItem .\src\TerraformGraph\Public | Measure-Object | ForEach-Object Count
Get-ChildItem .\src\TerraformGraph\Private | Measure-Object | ForEach-Object Count
Test-Path .\src\TerraformGraph\Classes
(Get-Content .\src\TerraformGraph\TerraformGraph.psm1).Count
@(Get-Command -Module TerraformGraph | Where-Object { $_.ScriptBlock.File -notlike '*\Public\*' }).Count
```

Expect: `26`, `82`, `False`, `464` (the psm1's lines), `0` (exported commands defined outside Public).

Pester: "every Public file defines exactly the function it is named for", "every Private file defines exactly one function and it is not exported", "psd1 FunctionsToExport equals the Public/ listing", "no function is defined twice across the tree, and the psm1 defines none"

### 18.4 The default test run against the assembled module

The whole default suite, importing dist\module\TerraformGraph instead of src (TERRAFORMGRAPH_TEST_MANIFEST). Takes about a minute and a half.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Invoke-Build AssembleModule | Out-Null
$env:TERRAFORMGRAPH_TEST_MANIFEST = (Resolve-Path .\dist\module\TerraformGraph\TerraformGraph.psd1).Path
pwsh -NoProfile -File (Resolve-Path ./tests/Invoke-Tests.ps1).Path
"exit $LASTEXITCODE"
Remove-Item Env:TERRAFORMGRAPH_TEST_MANIFEST
```

Expect: the AssembleModule line (`Assembled TerraformGraph 0.15.0: 16 files, ...`), Pester's summary `Tests Passed: 235, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 17`, then `exit 0`, the child pwsh's own exit code (Invoke-Tests.ps1 exits 1 on any failure; checked on 2026-10-07 by setting `$LASTEXITCODE = 99` before the child call and seeing it become 0).

Pester: none (this runs Pester)
