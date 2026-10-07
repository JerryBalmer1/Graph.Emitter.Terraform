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

Source version **0.8.0**. Not yet published to the PowerShell Gallery.

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
| Variable | `<module>/var/<name>`, where `<module>` is the ModuleAddress (`root` for the root module), e.g. `module.network/var/aws_region` |
| Local | `<module>/local/<name>` |
| Output | `<module>/output/<name>` |
| Resource instance | `<module>/resource/<type>.<name>`, e.g. `root/resource/null_resource.marker` |
| DataSource instance | `<module>/data/<type>.<name>`, e.g. `root/data/local_file.readme` |

Variable, Local and Output are `ConvertTo-TerraformVariableGraph` node Ids; the two instance rows are `ConvertTo-TerraformResourceGraph` node Ids; the rest are `ConvertTo-TerraformSchemaGraph` node Ids. A schema Id names a resource *type* under a provider (`<address>/resource/null_resource`), so it appears once per document; a resource graph Id names one *block* in one module (`module.network/resource/null_resource.subnet`) and has no provider in it. Each resource node's `SchemaId` holds the schema Id it joins to.

### Variable graph (`ConvertTo-TerraformVariableGraph`)

Turn a module graph into a graph of values: every variable, local and output in every parsed module becomes a `TerraformGraph.VariableNode`, and edges follow where each value comes from. A declaration that reads `var.x` or `local.x` gets a `Reference` edge; a module call argument `a = var.x` gets an `Argument` edge to the child's `var/a`; reading `module.c.o` gets an `OutputReference` edge from the child's output. Child variables carry `Binding` — `Argument` (with `ArgumentExpr` and `ArgumentLiteral`), `Default`, or `Unset` — and every node keeps `Expr`, `Literal` and `References`. Nothing is parsed again; modules the module graph did not parse are listed in `Skipped`.

```powershell
# Whole tree; Summary counts nodes by Kind.
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
$graph.Summary

# Arguments that name a variable the child does not declare.
$graph.Unresolved | Where-Object Reason -eq 'UndeclaredArgument'

# Variables nothing sets and that have no default.
$graph.Nodes | Where-Object Binding -eq 'Unset'
```

Only declaration expressions (variable default, local value, output value) and module call arguments make edges; references from resources, data sources and other blocks do not. A reference binds by its root with index and attribute suffixes dropped (`var.tags["a"]` binds `var.tags`; the full traversal is the edge's `Via`). `Unresolved` lists `UndeclaredReference` (a `var.` or `local.` with no such node in its module), `UndeclaredArgument` and `UndeclaredOutput`.

### Variable trace (`Get-TerraformVariableTrace`)

Walk a variable graph breadth-first from one node Id. `Upstream` answers where a value comes from, `Downstream` what it feeds, `Both` (default) does both, with upstream nodes at negative `Distance`. `-MaxDepth` (default 50) caps the walk and cycles terminate. An unknown Id throws and names the nodes with the same Name in other modules.

```powershell
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph

# Where the network module's aws_region comes from.
($graph | Get-TerraformVariableTrace -Id 'module.network/var/aws_region' -Direction Upstream).Nodes

# What the root aws_region feeds.
($graph | Get-TerraformVariableTrace -Id 'root/var/aws_region' -Direction Downstream).Nodes

# Both directions from a middle node, with the edges walked.
$trace = $graph | Get-TerraformVariableTrace -Id 'module.network.module.endpoint/output/address'
$trace.Nodes
$trace.Edges | Format-Table From, To, Kind, Via
```

### Resource graph (`ConvertTo-TerraformResourceGraph`)

Inventory every `resource` and `data` block in a module graph and, optionally, join each one to its provider schema. Every block becomes a `TerraformGraph.ResourceNode` with `ResourceAddress` (`module.network.null_resource.subnet`, `data.local_file.readme`), the provider it resolves to (`ProviderLocalName`, `ProviderAlias`, `ProviderAddress`) and `SchemaId`, the `ConvertTo-TerraformSchemaGraph` Id it should be an instance of. `Providers` counts nodes per provider address. Nothing is parsed again; modules the module graph did not parse are listed in `Skipped`.

Pass one or more schema graphs with `-SchemaGraph` and each node whose `SchemaId` is present gets `SchemaMatched` `$true` and an `InstanceOf` edge, and its top-level arguments are checked: `UnknownAttributes` and `UnknownBlocks` (a `dynamic "x"` block counts as `x`) list what the schema does not declare, `MissingRequired` lists required attributes and `min_items >= 1` blocks that are not set. `Findings` counts nodes with any of the three. Unmatched nodes carry `Reason` `NoSchemaGraph`, `ProviderNotInSchemaGraph` or `TypeNotInProvider`.

```powershell
# Inventory with no schema.
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph
$graph.Nodes
$graph.Providers

# Join with a directory's schema and list what did not match.
$schema = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schema
$graph.Nodes | Where-Object { -not $_.SchemaMatched } | Format-Table ResourceAddress, ProviderAddress, Reason

# Join with several schema graphs and show the nodes counted in Findings.
$schemas = @(
    Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph
    Get-TerraformProviderSchema -Provider local -Cleanup | ConvertTo-TerraformSchemaGraph
)
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schemas
$graph.Nodes | Where-Object { $_.UnknownAttributes -or $_.UnknownBlocks -or $_.MissingRequired } |
    Format-List ResourceAddress, UnknownAttributes, UnknownBlocks, MissingRequired
```

The provider is resolved per module, the way Terraform does it: the local name is the type up to its first underscore (`aws_instance` → `aws`), or the name in a `provider = aws.west` argument (which also sets `ProviderAlias`). It maps through that module's own `required_providers` sources; an undeclared name falls back to `terraform.io/builtin/terraform` for `terraform` and `registry.terraform.io/hashicorp/<name>` otherwise. Child modules do not inherit their parent's `required_providers`. Only the top level of each block is checked, not the contents of nested blocks; the meta-arguments `count`, `for_each`, `provider`, `depends_on` and the `lifecycle`, `connection`, `provisioner` blocks are never reported.

## Agent skills

The module ships an agent skill at `skills/terraformgraph/SKILL.md` inside the module folder. It follows the open Agent Skills format: YAML front matter with `name` and `description` (when an agent should load it), then a Markdown body. The body covers importing the module, the functions in pipeline order with their input and output types, the canonical Id scheme, the `ModuleAddress`/`ResourceAddress` naming rule, and three example pipelines.

`Install-TerraformGraphSkill` copies that folder into a repository's project skills folder for each agent tool you name, and makes sure `AGENTS.md` at the repository root points at it. `Test-TerraformGraphSkill` reports, per tool, whether the repository uses it (`Detected`), whether the skill is there (`Installed`), and whether the copy differs from the module's (`Stale`). Neither touches the network.

```powershell
# Claude (the default) in the current directory.
Install-TerraformGraphSkill

# Several tools in another repository, with a result per tool.
Install-TerraformGraphSkill -Path C:\src\infra-live -Tool Claude, Cursor -PassThru

# What is detected and installed; refresh stale copies after a module upgrade.
Test-TerraformGraphSkill
Test-TerraformGraphSkill | Where-Object Stale | ForEach-Object { Install-TerraformGraphSkill -Tool $_.Tool -Force }
```

Files are copied, not linked. Without `-Force`, an identical file is left alone and a file that differs (a local edit) is skipped with a verbose message; `-Force` overwrites it. `-PassThru` returns `Tool`, `Status` (`Installed`, `Updated`, `Unchanged`, `Skipped`), `Files` written and `SkillPath`. A missing `AGENTS.md` is created; an existing one gets the section appended once, guarded by the marker line `<!-- terraformgraph-skill -->`, and its existing content is never rewritten.

On import, the module checks the current directory. If an agent tool is detected there without the skill, it prints one line:

```
TerraformGraph: detected Claude in this directory. Run Install-TerraformGraphSkill -Tool Claude to give them the TerraformGraph skill.
```

It is silent when nothing is detected or everything is installed. Set `$env:TERRAFORMGRAPH_SKILL_HINT = '0'` before importing to turn it off.

| Tool | Skills folder | Detected by |
|---|---|---|
| Claude | `.claude/skills` | `.claude` |
| Codex | `.codex/skills` | `.codex` |
| Cursor | `.cursor/skills` | `.cursor` |
| Gemini | `.gemini/skills` | `.gemini` |
| Copilot | `.github/skills` | `.github/copilot-instructions.md` |

These paths are the convention as of 2026-10. Only Claude is tested: Claude Code is what the author uses; the other tools' paths use the same copy mechanism but are untested.

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
