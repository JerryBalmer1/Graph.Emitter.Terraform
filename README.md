<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=220&section=header&color=0:1B1030,45:5C4EE5,100:844FBA&text=TerraformGraph&fontSize=52&fontColor=FFFFFF&fontAlignY=38&desc=Parse%20Terraform%20into%20an%20HCL%20AST%20and%20a%20module%20and%20provider%20graph&descSize=16&descAlignY=62&animation=fadeIn" alt="TerraformGraph" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 7.4+" />
  <img src="https://img.shields.io/badge/Pester-6.1%2B-0078D4?style=for-the-badge" alt="Pester 6.1+" />
  <img src="https://img.shields.io/badge/HCL-v2-844FBA?style=for-the-badge" alt="HashiCorp HCL v2" />
  <a href="https://www.powershellgallery.com/packages/TerraformGraph"><img src="https://img.shields.io/powershellgallery/v/TerraformGraph?style=for-the-badge&label=Gallery" alt="PowerShell Gallery" /></a>
</p>

<p align="center">
  <sub><a href="https://github.com/kyechan99/capsule-render">Above was created by capsule-render</a></sub>
</p>

Parse Terraform configurations into an HCL AST and build graphs of module calls and provider schemas.

> **Requires PowerShell 7.4+.** Agents, skills, and tool runners should use 7.4 (or later) so `$ErrorActionPreference = 'Stop'` is a first-class default you can rely on. On older hosts a failed parse is often a *non-terminating* error: the pipeline keeps going, the agent reads “success,” and it never gets a chance to correct the path or the HCL. 7.4 is the line this module draws so an agent actually *sees* the failure and can fix it.

There was no Terraform AST cmdlet I could drop into a pipeline, so this module exists. The native parser is a `c-shared` DLL built from [HashiCorp HCL v2](https://github.com/hashicorp/hcl) — the same language library Terraform uses — not from the `hashicorp/terraform` application repository.

Source version **0.5.1**. Not yet published to the PowerShell Gallery.

---

## Requirements

- OS: Windows (native DLL is a Windows build)
- PowerShell **7.4 or later** (enforced by the module manifest)
- ~100 MB free space if you are compiling the DLL yourself (Go + Docker)

## Setup

- Clone this repo and build the DLL (see below); Gallery install will work once the module is published.
- Install for your user account — no admin required.
- Import the module and point `Get-TerraformAST` at `infra` or a `.tf` file.

## Downloads & Links

- Homepage: https://github.com/JerryBalmer1/TerraformGraph
- Gallery: https://www.powershellgallery.com/packages/TerraformGraph
- Parser library: https://github.com/hashicorp/hcl

---

## Install

```powershell
Install-Module -Name TerraformGraph -Scope CurrentUser
Import-Module TerraformGraph
```

## Examples

The repo ships an `infra/` fixture: a root module, a `network` child module, and a nested `endpoint` module. No cloud credentials.

### Directory (`-Path`)

Parse `.tf` files in one folder. Subfolders are skipped. The default view is `Type`, `Name`, `Line`, `Column`, and `File` — set with `DefaultDisplayPropertySet` on `TerraformGraph.Block`.

```powershell
Get-TerraformAST -Path .\infra
```

```text
Type   : terraform
Name   :
Line   : 1
Column : 1
File   : main.tf

Type   : provider
Name   : null
Line   : 16
Column : 1
File   : main.tf

Type   : provider
Name   : local
Line   : 17
Column : 1
File   : main.tf

...
```

### Directory, recursive (`-Path -Recurse`)

Include nested modules and child directories.

```powershell
Get-TerraformAST -Path .\infra -Recurse
```

### Single file (`-FilePath`)

```powershell
Get-TerraformAST -FilePath .\infra\main.tf
```

### Full object

Ranges and `Body` are still on the object. `Format-List *` is the long view:

```powershell
Get-TerraformAST -FilePath .\infra\variables.tf |
    Where-Object Name -eq 'aws_region' |
    Select-Object -First 1 |
    Format-List *
```

```text
Name            : aws_region
Line            : 1
Column          : 1
File            : variables.tf
Type            : variable
Labels          : {aws_region}
Body            : @{Attributes=System.Collections.Hashtable; Blocks=System.Object[]}
TypeRange       : @{Filename=C:\__Code\TerraformGraph\infra\variables.tf; Start=; End=}
LabelRanges     : {@{Filename=C:\__Code\TerraformGraph\infra\variables.tf; Start=; End=}}
OpenBraceRange  : @{Filename=C:\__Code\TerraformGraph\infra\variables.tf; Start=; End=}
CloseBraceRange : @{Filename=C:\__Code\TerraformGraph\infra\variables.tf; Start=; End=}
```

`$block.TypeRange.Start.Line` is the same value as `$block.Line`. Types at the root of `.\infra`:

```powershell
Get-TerraformAST -Path .\infra |
    Select-Object -ExpandProperty Type -Unique
```

```text
terraform
provider
variable
locals
resource
data
module
output
check
```

### JSON (`ConvertTo-TerraformJson`)

Serialize objects to indented JSON with no 100-level depth cap. `-Compress` writes one line; `-AsArray` always writes an array; `-Depth` (default 1024) sets the limit.

```powershell
Get-TerraformAST -Path .\infra | ConvertTo-TerraformJson | Set-Content .\infra.ast.json
```

### JSON (`ConvertFrom-TerraformJson`)

Parse JSON into PSCustomObjects, or ordered case-sensitive dictionaries with `-AsHashtable`. `-NoEnumerate` keeps a top-level array as one object.

```powershell
Get-Content .\infra.ast.json -Raw | ConvertFrom-TerraformJson -AsHashtable
```

### Provider schema (`Get-TerraformProviderSchema`)

Run `terraform providers schema -json` in an initialized working directory (`-Path`, default current location). Returns ordered dictionaries by default, or indented JSON with `-OutputFormat Json`.

```powershell
$schema = Get-TerraformProviderSchema -Path .\infra
$schema['provider_schemas'].Keys

Get-TerraformProviderSchema -Path .\infra -OutputFormat Json | Set-Content .\schema.json
```

#### On demand (`-Provider`)

Fetch one provider's schema without an existing configuration. It writes a throwaway `main.tf`, runs `terraform init` (needs registry access), and reads the schema. The working directory under `$env:TEMP\TerraformGraph\providers` is kept so repeat calls skip init; `-Cleanup` removes it, `-Force` runs init again.

```powershell
# Latest hashicorp/null, working directory removed afterwards.
$schema = Get-TerraformProviderSchema -Provider null -Cleanup
$schema.provider_schemas['registry.terraform.io/hashicorp/null'].resource_schemas.Keys

# Pinned version, kept for reuse; the second run skips terraform init.
$schema = Get-TerraformProviderSchema -Provider hashicorp/aws -Version '= 5.60.0' -Verbose
```

### Module graph (`Get-TerraformModuleGraph`)

Build a graph of module calls from the `module` blocks in a root module (`-Path`, default current location). Each call is a `TerraformGraph.ModuleNode` with `Key`, `ModuleAddress`, `Source`, `SourceKind`, `Dir`, `Depth`, the calling `Block` and, once parsed, its own `Blocks`; each call also gets one `TerraformGraph.ModuleEdge` from its parent.

```powershell
# Root and its direct calls; children are resolved but not parsed.
Get-TerraformModuleGraph -Path .\infra

# Follow every call down the tree.
(Get-TerraformModuleGraph -Path .\infra -Recurse).Nodes

# Node and edge Ids are source strings instead of ModuleAddress.
(Get-TerraformModuleGraph -Path .\infra -Recurse -GroupBy Source).Edges
```

`-GroupBy` only decides `Id`, and so the `From`/`To` of each edge: `Call` (default) uses `ModuleAddress` such as `module.network.module.endpoint`, `Source` uses the source string such as `./modules/endpoint`, so calls to the same module share an Id (edges are not deduplicated). Calls that cannot be resolved stay in the graph with `Resolved` `$false` and a `Reason` — `NonLiteralSource`, `LocalPathMissing`, or `NotInitialized` for a registry, git, http, s3 or gcs source with no entry in `.terraform/modules/modules.json` — and are collected in `Unresolved` for a quick check. A call whose directory is already one of its own ancestors keeps `Resolved` `$true` and its `Dir`, gets `Reason` `Cycle`, and is not followed; a module called from two places is otherwise walked once per call. `terraform init` is never run; local sources need no init at all.

### Schema graph (`ConvertTo-TerraformSchemaGraph`)

Turn the output of `Get-TerraformProviderSchema` into a graph: every provider, resource, data source, block and attribute becomes a `TerraformGraph.SchemaNode` with one `Contains` edge from its parent. Attributes carry `Type` rendered in Terraform syntax (`map(string)`, `set(object({ a = string }))`, `dynamic` as `any`) plus `Required`, `Optional`, `Computed`, `Sensitive`, `WriteOnly`. Attributes declared with `nested_type` get child Attribute nodes just like blocks do. Input can be the default dictionary, the `-OutputFormat Json` text, or that text through `ConvertFrom-TerraformJson`.

```powershell
# Fetch hashicorp/null and convert it.
Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph

# Keep one provider out of a multi-provider directory schema.
$graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph -Provider aws
$graph.Nodes | Where-Object Path -like 'aws_s3_bucket.*'

# Count by Kind, then list resources with their canonical Id.
$graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
$graph.Summary
$graph.Nodes | Where-Object Kind -eq 'Resource' | Select-Object Path, Id
```

`Id` is canonical and unique within the document; `Path` is the short dotted form (`null_resource.triggers`) and can repeat across providers. `-Provider` that is not in the document throws and lists the providers that are. `-IncludeFunctions` adds provider functions as Function nodes.

| Kind | Id |
|---|---|
| Provider | `<address>`, e.g. `registry.terraform.io/hashicorp/aws` |
| Config | `<address>/config/<name>`: the provider's own configuration attributes and blocks (Kind Attribute or Block), Path `<provider>.<name>`, e.g. `aws.region` |
| Resource | `<address>/resource/<type>` |
| DataSource | `<address>/data/<type>` |
| Function | `<address>/function/<name>` |
| Block | `<parent Id>/<block name>` |
| Attribute | `<parent Id>/<attribute name>` |

---

## Build the DLL (contributors)

If `TerraformGraph.dll` is already loaded in this PowerShell process, Windows will refuse to delete it. `BuildDLL` unloads the module first and, if the file is still locked, renames it to `TerraformGraph.dll.old` before writing the new one. A brand-new `pwsh` session is still the cleanest option.

```powershell
Invoke-Build CheckDependencies
Invoke-Build BuildDLL
Invoke-Build
```

`BuildDLL` cross-compiles `src/go` with `github.com/hashicorp/hcl/v2` and copies `TerraformGraph.dll` into `src/TerraformGraph/lib/`.

## Disclaimer

This project is independent. It is not affiliated with HashiCorp.

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer&color=0:844FBA,55:5C4EE5,100:1B1030&text=TerraformGraph&fontSize=28&fontColor=FFFFFF&fontAlignY=70&animation=fadeIn" alt="" />
</p>
