> **Built as an ontology layer for AI agents.** If that is why you are here, read [ONTOLOGY.md](ONTOLOGY.md).

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=220&section=header&color=0:1B1030,45:5C4EE5,100:844FBA&text=Graph.Emitter.Terraform&fontSize=52&fontColor=FFFFFF&fontAlignY=38&desc=Parse%20Terraform%20into%20an%20HCL%20AST%20and%20a%20module%20and%20provider%20graph&descSize=16&descAlignY=62&animation=fadeIn" alt="Graph.Emitter.Terraform" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 7.4+" />
  <img src="https://img.shields.io/badge/Pester-6.1%2B-0078D4?style=for-the-badge" alt="Pester 6.1+" />
  <img src="https://img.shields.io/badge/HCL-v2-844FBA?style=for-the-badge" alt="HashiCorp HCL v2" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-D22128?style=for-the-badge" alt="Apache License 2.0" />
</p>

<p align="center">
  <sub><a href="https://github.com/kyechan99/capsule-render">Above was created by capsule-render</a></sub>
</p>

Parse Terraform configurations into an HCL AST and build graphs of module calls and provider schemas.

**In CI**, one line fails the build when any module call is nested deeper than 3:

```powershell
pwsh -NoProfile -Command "Import-Module Graph.Emitter.Terraform; if ((Get-TerraformModuleGraph -Path . -Recurse).Nodes | Where-Object Depth -gt 3) { exit 1 }"
```

Exit code 0: every module call is at depth 3 or less (the root module is depth 0). Exit code 1: at least one is deeper. A parse error or an unreadable path is a terminating error, which also exits 1. `Get-TerraformModuleGraph` never runs `terraform init`.

> **Requires PowerShell 7.4+.** Agents, skills, and tool runners should use 7.4 (or later) so `$ErrorActionPreference = 'Stop'` is a first-class default you can rely on. On older hosts a failed parse is often a *non-terminating* error: the pipeline keeps going, the agent reads “success,” and it never gets a chance to correct the path or the HCL. 7.4 is the line this module draws so an agent actually *sees* the failure and can fix it.

There was no Terraform AST cmdlet I could drop into a pipeline, so this module exists. The native parser is a `c-shared` DLL built from [HashiCorp HCL v2](https://github.com/hashicorp/hcl) — the same language library Terraform uses — not from the `hashicorp/terraform` application repository.

Source version **0.17.1**. Not yet published to the PowerShell Gallery: install from a clone (see [Install](#install)).

---

## Requirements

- OS: the HCL parser (`Get-TerraformAST`, `Get-TerraformModuleGraph`) runs on **Windows x64 only**, because its native DLL is a Windows x64 build. On Linux, macOS or Windows on ARM the module still imports, those two commands stop with `ParserUnavailable`, and every other command (registry, schema, docs, classifier, bundle, JSON and graph commands fed from them) works.
- PowerShell **7.4 or later** (enforced by the module manifest)
- ~100 MB free space if you are compiling the DLL yourself (Go + Docker)

## Setup

- Clone this repo and build the DLL (see [Build the DLL](#build-the-dll-contributors)); the module is not on the PowerShell Gallery yet.
- Install for your user account — no admin required.
- Import the module and point `Get-TerraformAST` at `infra` or a `.tf` file.

## Downloads & Links

- Homepage: https://github.com/JerryBalmer1/Graph.Emitter.Terraform
- Parser library: https://github.com/hashicorp/hcl
- Changelog: [CHANGELOG.md](CHANGELOG.md)

---

## Install

From a clone, after `Invoke-Build BuildDLL` (see [Build the DLL](#build-the-dll-contributors)):

```powershell
Import-Module .\src\Graph.Emitter.Terraform\Graph.Emitter.Terraform.psd1
```

<!--
### Once on the Gallery

Restore this, and the Gallery badge and link at the top, when Graph.Emitter.Terraform is published:

```powershell
Install-Module -Name Graph.Emitter.Terraform -Scope CurrentUser
Import-Module Graph.Emitter.Terraform
```

<a href="https://www.powershellgallery.com/packages/Graph.Emitter.Terraform"><img src="https://img.shields.io/powershellgallery/v/Graph.Emitter.Terraform?style=for-the-badge&label=Gallery" alt="PowerShell Gallery" /></a>
- Gallery: https://www.powershellgallery.com/packages/Graph.Emitter.Terraform
-->

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
Type            : variable
Labels          : {aws_region}
Body            : @{Attributes=; Blocks=; SrcRange=; EndRange=}
TypeRange       : @{Filename=C:\__Code\Graph.Emitter.Terraform\infra\variables.tf; Start=; End=}
LabelRanges     : {@{Filename=C:\__Code\Graph.Emitter.Terraform\infra\variables.tf; Start=; End=}}
OpenBraceRange  : @{Filename=C:\__Code\Graph.Emitter.Terraform\infra\variables.tf; Start=; End=}
CloseBraceRange : @{Filename=C:\__Code\Graph.Emitter.Terraform\infra\variables.tf; Start=; End=}
Name            : aws_region
Line            : 1
Column          : 1
File            : variables.tf
```

`$block.TypeRange.Start.Line` is the same value as `$block.Line`. Types at the root of `.\infra`:

```powershell
Get-TerraformAST -Path .\infra |
    Select-Object -ExpandProperty Type -Unique
```

```text
terraform
provider
locals
resource
data
module
check
output
variable
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

Build a graph of module calls from the `module` blocks in a root module (`-Path`, default current location). Each call is a `TerraformGraph.ModuleNode` with `Id` first and `Kind` (`Module`) second, then `Name`, `Key`, `ModuleAddress`, `Source`, `SourceKind`, `Dir`, `Resolved`, `Reason`, `ParentKey`, `Depth`, the calling `Block`, once parsed its own `Blocks`, and `Callers`. Each call also gets one `TerraformGraph.ModuleEdge` from its parent: `From`, `To`, `Kind` (`Calls`), `Call`, `Label`, `File` (the module block's file name) and `Line`. The full property tables are in [docs/graph-shape.md](docs/graph-shape.md).

```powershell
# Root and its direct calls; children are resolved but not parsed.
Get-TerraformModuleGraph -Path .\infra

# Follow every call down the tree.
(Get-TerraformModuleGraph -Path .\infra -Recurse).Nodes

# One node per module source; Callers names the calls each one stands for.
(Get-TerraformModuleGraph -Path .\infra -Recurse -GroupBy Source).Nodes | Format-Table Id, Callers
```

`-GroupBy` decides `Id`, and so the `From`/`To` of each edge; Ids are unique either way and the root is always `root`. `Call` (default) gives one node per call, Id = `ModuleAddress` such as `module.network.module.endpoint`. `Source` gives one node per module source, Id = `source:` plus the normalised source: a local source written relative to the root module (`source:./modules/network/modules/endpoint`, so two calls that reach the same directory share a node), a registry source lowercased without a `registry.terraform.io/` host, anything else trimmed. A non-literal source keeps its own node, `source:<ModuleAddress>`, with `Resolved` `$false`. `Callers` lists every call a Source node stands for; edges stay one per call. Build variable and resource graphs from a `Call` graph: they read one node per call, so a `Source` graph gives them only the first call to each source. Calls that cannot be resolved stay in the graph with `Resolved` `$false` and a `Reason` — `NonLiteralSource`, `LocalPathMissing`, or `NotInitialized` for a registry, git, http, s3 or gcs source with no entry in `.terraform/modules/modules.json` — and are collected in `Unresolved` (and `Findings`, the same list) for a quick check. A call whose directory is already one of its own ancestors keeps `Resolved` `$true` and its `Dir`, gets `Reason` `Cycle`, and is not followed; a module called from two places is otherwise walked once per call. `terraform init` is never run; local sources need no init at all.

### Schema graph (`ConvertTo-TerraformSchemaGraph`)

Turn the output of `Get-TerraformProviderSchema` into a graph: every provider, resource, data source, block and attribute becomes a `TerraformGraph.SchemaNode` with one `Contains` edge from its parent. Attributes carry `Type` rendered in Terraform syntax (`map(string)`, `set(object({ a = string }))`, `dynamic` as `any`) plus `Required`, `Optional`, `Computed`, `Sensitive`, `WriteOnly`. Attributes declared with `nested_type` get child Attribute nodes just like blocks do. Input can be the default dictionary, the `-OutputFormat Json` text, or that text through `ConvertFrom-TerraformJson`.

```powershell
# Fetch hashicorp/null and convert it.
Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph

# Keep one provider out of a multi-provider directory schema (infra declares null and local).
$graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph -Provider null
$graph.Nodes | Where-Object Path -like 'null_resource.*'

# Count by Kind, then list resources with their canonical Id.
$graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph
$graph.Summary
$graph.Nodes | Where-Object Kind -eq 'Resource' | Select-Object Path, Id
```

`Id` is canonical and unique within the document; `Path` is the short dotted form (`null_resource.triggers`) and can repeat across providers. `-Provider` that is not in the document throws and lists the providers that are. `-IncludeFunctions` adds provider functions as Function nodes.

| Kind | Id |
|---|---|
| Module | `ModuleAddress` with `-GroupBy Call` (`root` for the root module), e.g. `module.network.module.endpoint`; `source:<normalised source>` with `-GroupBy Source`, e.g. `source:./modules/network` |
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

Module is the `Get-TerraformModuleGraph` node Id; Variable, Local and Output are `ConvertTo-TerraformVariableGraph` node Ids; the two instance rows are `ConvertTo-TerraformResourceGraph` node Ids; the rest are `ConvertTo-TerraformSchemaGraph` node Ids. A schema Id names a resource *type* under a provider (`<address>/resource/null_resource`), so it appears once per document; a resource graph Id names one *block* in one module (`module.network/resource/null_resource.subnet`) and has no provider in it. Each resource node's `SchemaId` holds the schema Id it joins to.

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

## Provider registry cache

A local list of Terraform providers and their versions, so names can be searched, wildcards resolved and arguments tab-completed without calling the registry. Two files, read in this order:

1. User cache: `$env:LOCALAPPDATA\TerraformGraph\registry.json`, written by `Update-TerraformRegistryCache`.
2. Bundled: `data/registry.json` inside the module, official and partner providers harvested on **2026-10-07** (UTC): 428 providers, 25,052 versions.

The first file that exists wins. `-NoBundledData` skips the bundled file, so only the user cache counts. Each provider has `ProviderAddress`, `Source` (`namespace/name`), `Tier` (`official`, `partner`, `community`), `Description`, `Latest` (newest version that is not a pre-release), `VersionCount` and `Versions` (newest first, pre-releases included, each with `version`, `protocols` and `published`).

```powershell
# Refresh the user cache (official and partner; -Scope All adds community, much larger).
Update-TerraformRegistryCache -PassThru

# Search the cache: never the network.
Get-TerraformRegistryProvider aws*                 # bare name, any namespace
Get-TerraformRegistryProvider 'hashicorp/google*'  # namespace/name
Get-TerraformRegistryProvider -Tier partner
(Get-TerraformRegistryProvider hashicorp/aws).Versions | Select-Object -First 5

# A wildcard -Provider must match exactly one provider.
Get-TerraformProviderSchema -Provider 'hashicorp/awsc*' -Cleanup
```

Patterns match by shape: no slash matches the bare name in any namespace, one slash matches `namespace/name`, two slashes match the full address; case is ignored. With a wildcard, `Get-TerraformProviderSchema -Provider` resolves against the cache before running anything, and stops if the pattern is ambiguous or unknown:

```
'aws*' matches 4 providers: hashicorp/aws, hashicorp/awscc, nullstone-io/awsex, Traceableai/awsapigateway. Specify one; Get-TerraformRegistryProvider -Name 'aws*' lists them.
'foo*' matches no provider in the registry cache (harvested 2026-10-07). Run Update-TerraformRegistryCache or pass a full address.
```

Matches are listed official first, then partner, then community. A `-Provider` without a wildcard keeps working with no cache at all.

Tab completion reads the cache only and never touches the network: `Get-TerraformProviderSchema -Provider` and `Get-TerraformRegistryProvider -Name` complete `namespace/name` sources (official first), and `-Version` completes the versions of the provider already typed, newest first. With no cache they complete nothing.

`Update-TerraformRegistryCache` lists providers from the v2 API (100 per page), then makes two calls per provider in parallel (`-ThrottleLimit`, default 6): v1 `/versions` for protocols and v2 `include=provider-versions` for publish dates. 5xx responses are retried five times with a short backoff. A 429 is the registry's rate limit, handled as described under [Bulk docs harvest](#bulk-docs-harvest); the registry cache harvest and the docs harvest share that state for the whole session. If any provider still fails, nothing is written; otherwise the file is replaced atomically.

The bundled file is refreshed when cutting a release, not in the default build:

```powershell
Invoke-Build BuildRegistry   # writes src/Graph.Emitter.Terraform/data/registry.json, prints ProviderCount, VersionCount, Elapsed
```

## Schema packs

A provider schema is the dictionary: every resource, data source, block and attribute the provider accepts. A resource graph only opens the pages a repository touches, meaning the providers its blocks resolve to. Getting the dictionary normally means `terraform init` for the provider (a provider binary download, about 220 MB for azurerm 5.8.0) and then `terraform providers schema -json`. Schema packs skip that. They keep the schema in a local cache, so building a schema graph or checking a repository needs neither terraform nor the network.

Schemas are **not** bundled with the module, which stays small. They live in a local cache:

```
$env:LOCALAPPDATA\TerraformGraph\schemas\
  registry.terraform.io-hashicorp-azurerm\5.8.0.json.gz
  registry.terraform.io-microsoft-azuredevops\1.16.0.json.gz
  registry.terraform.io-vmware-vsphere\2.17.1.json.gz
```

Each file is one provider version's `terraform providers schema -json` document as compact, gzipped JSON. The folder name is the lowercase provider address with `/` replaced by `-`. There are two ways to fill the cache:

| | `Get-TerraformSchemaPack` | `Get-TerraformProviderSchema -Provider … -SaveToCache` |
|---|---|---|
| Source | Packs cut at release time (default: the latest GitHub release), or a local folder | Harvested on your machine |
| Needs | HTTPS to GitHub (or nothing, for a folder) | terraform on PATH, registry access, the provider download |
| Providers | Whatever the manifest lists | Any provider and any version |
| Integrity | sha256 from `manifest.json`, checked before anything is written | What terraform reports |

The packs shipped for a release match that module release and are attached to its GitHub release as `manifest.json` plus one `<address-slug>.<version>.json.gz` per provider (and, from 0.11.0, one `docs.<address-slug>.<version>.json.gz` per provider; see [Provider docs](#provider-docs)). Each manifest entry has a `kind`, `schema` or `docs`. `Get-TerraformSchemaPack` reads only `schema` entries, and treats an entry with no `kind` (manifests before 0.11.0) as `schema`. The author publishes the release separately. The latest release (v0.14.0) has the packs for azurerm 5.8.0, azuredevops 1.16.0 and vsphere 2.17.1 attached; for any other provider use `-SaveToCache`, or point `-Source` at a folder you built (see below).

This repository is public, so the default `-Source` needs no token. For a private fork: a private repository's release download URLs return 404 even to someone who can read the repository. Set `$env:GH_TOKEN` (or `$env:GITHUB_TOKEN`) to a token that can read it, and `Get-TerraformSchemaPack` / `Get-TerraformDocPack` fetch the release through the GitHub API instead (`releases/latest`, or `releases/tags/<tag>` for a `-Source` of `https://github.com/<owner>/<repo>/releases/download/<tag>`). They find each file among the release assets by name and download it with that token. Without a token the anonymous URL is used, and a 404 names `GH_TOKEN` for a private fork.

Worked example with azurerm, azuredevops and vsphere:

```powershell
# 1. Fill the cache: three packs, about 270 KB in total. A cached version is skipped (Status Cached) unless -Force.
Get-TerraformSchemaPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere -PassThru

# ...or harvest one locally instead of downloading the pack.
$null = Get-TerraformProviderSchema -Provider vmware/vsphere -SaveToCache -Cleanup

# 2. What is cached: ProviderAddress, Version, Bytes, CachedOn.
Get-TerraformSchemaCache
Get-TerraformSchemaCache 'azure*'

# 3. Schema graphs straight from the cache. Wildcards match the bare name in any namespace.
$azure = ConvertTo-TerraformSchemaGraph -Provider 'azure*'     # azurerm + azuredevops, one graph
$azure.Summary
ConvertTo-TerraformSchemaGraph -Provider vsphere -Version 2.17.1

# 4. Check a repository against whatever is cached for the providers it uses.
$graph = Get-TerraformModuleGraph -Path C:\src\platform -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema
$graph.Nodes | Format-Table ResourceAddress, ProviderAddress, SchemaMatched, Reason
$graph.Nodes | Where-Object { $_.UnknownAttributes -or $_.UnknownBlocks -or $_.MissingRequired } |
    Format-List ResourceAddress, UnknownAttributes, UnknownBlocks, MissingRequired
```

In step 3 the `azure*` graph has 36,282 nodes (1,237 resources, 442 data sources) and builds in 9 to 13 s (three fresh processes on the author's machine, 2026-10-07: 9.0, 12.4 and 10.2 s). In step 4, a root module that declares the three providers in `required_providers` and also uses `random_pet` matches every azurerm, azuredevops and vsphere block. `random_pet` is not cached, so it shows `Reason` `ProviderNotInSchemaGraph`. A mistyped `colour` argument on `vsphere_folder` shows up in `UnknownAttributes`.

- `ConvertTo-TerraformSchemaGraph -Provider` (no `-Schema`) loads the newest cached version of each provider, or `-Version`, and behaves exactly as if that document had been piped in. A provider that is not cached is a terminating error that names both `Get-TerraformSchemaPack` and `Get-TerraformProviderSchema -SaveToCache`.
- `ConvertTo-TerraformResourceGraph -Provider` builds the schema graphs from the cache for the providers you name, as an alternative to `-SchemaGraph`. `-AutoSchema` takes the provider addresses the module graph resolves to, loads whichever are cached and marks the rest `ProviderNotInSchemaGraph`.
- Neither `-AutoSchema` nor any argument completer downloads anything. Only `Get-TerraformSchemaPack` reads packs over the network, and only `-SaveToCache` runs terraform.

### Cut your own pack

`BuildSchemaPack` harvests providers at their latest version from the registry cache, saves them to your schema cache, harvests the same version's docs into your docs cache, and writes `dist/schema-packs/` (gitignored). The folder holds one schema `.json.gz` and one `docs.*.json.gz` per provider, plus `manifest.json`: `builtOn`, then per pack `kind`, `address`, `version`, `file`, `sha256` and `bytes`. Schema entries add `nodeCount`, `resourceCount` and `dataSourceCount`; docs entries add `docCount` and `unmatchedCount`. It is not part of the default build. With no `-Provider` it packs the three providers above. The folder is recreated on every run.

```powershell
Invoke-Build BuildSchemaPack                                       # hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere
Invoke-Build BuildSchemaPack -Provider hashicorp/aws, hashicorp/google

# Install from the folder on this or another machine (copy dist\schema-packs over, or serve it over HTTPS).
Get-TerraformSchemaPack -Source .\dist\schema-packs -PassThru      # every schema pack in the manifest
Get-TerraformDocPack -Source .\dist\schema-packs -PassThru         # every docs pack in the manifest
```

The vsphere provider moved from `hashicorp/vsphere` (frozen at 2.12.0, April 2025, and no longer in the registry's provider list) to `vmware/vsphere`, so the default packs `vmware/vsphere`. A provider that is not in the registry cache is still packed, at whatever version `terraform init` selects.

## Provider docs

The schema says which arguments a resource takes. The registry docs say what they mean, with examples. Graph.Emitter.Terraform keeps the registry's markdown pages in a local cache next to the schemas. Each page is keyed on the Id of the schema node it documents, so docs join to schema graphs and resource graphs with no lookup tables.

| Page | Doc Id | Joins to |
|---|---|---|
| Overview | `<address>` | the schema Provider node |
| Guide | `<address>/guide/<slug>` | (no schema node) |
| Resource | `<address>/resource/<type>` | the schema Resource node; a ResourceNode's `SchemaId` |
| Data source | `<address>/data/<type>` | the schema DataSource node; a ResourceNode's `SchemaId` |
| Unmatched | `<address>/unmatched/<category>/<slug>` | nothing: the type is not in the schema |

The registry names a page by its type without the provider prefix (`virtual_machine` for `vsphere_virtual_machine`). The harvest rebuilds the type as `<prefix>_<slug>`, where the prefix is the one the provider's cached schema uses, and checks it against that schema. A slug that already carries the prefix (some vsphere pages, such as `vsphere_sso_group`) is also tried. A page whose type is in neither form keeps an `unmatched` Id and is counted in `UnmatchedCount`. That is a finding about the provider's docs, not an error: usually a page for a type that was renamed, removed, or not yet in the schema. Only the overview, guides, resources and data-sources categories are kept, in the hcl language. The registry also has functions, ephemeral-resources, list-resources and actions pages for some providers; those are skipped.

Cache layout, the same shape as the schema cache:

```
$env:LOCALAPPDATA\TerraformGraph\docs\
  registry.terraform.io-hashicorp-azurerm\5.8.0.json.gz
  registry.terraform.io-vmware-vsphere\2.17.1.json.gz
```

Each file is `{ address, version, harvestedOn, schemaVersion, docCount, unmatchedCount, docs: [ { id, category, title, subcategory, slug, content } ] }`, where `content` is the raw markdown and `schemaVersion` is the cached schema the Ids were checked against. There are two ways to fill it:

| | `Get-TerraformDocPack` | `Update-TerraformProviderDocCache` |
|---|---|---|
| Source | `docs` entries in a pack manifest (default: the latest GitHub release), or a local folder | registry.terraform.io, harvested on your machine |
| Needs | HTTPS to GitHub (or nothing, for a folder) | registry access; a cached schema to match Ids against |
| Providers | Whatever the manifest lists | Any registry provider and version |
| Integrity | sha256 from `manifest.json` | What the registry returns |

`Update-TerraformProviderDocCache` lists the pages, fetches them in parallel (`-ThrottleLimit`, default 6, with the 429 and 5xx handling under [Bulk docs harvest](#bulk-docs-harvest)) and writes the file atomically. For a whole set of providers, see [Bulk docs harvest](#bulk-docs-harvest). If the provider has no cached schema, it still writes the docs, but builds Ids from the provider name without checking, leaves `UnmatchedCount` empty, and warns. Fill the schema cache first.

The default packs, as of 2026-10-07 (UTC): azurerm 5.8.0 has 1,518 pages (1.18 MB gzipped, harvested in 44 s), 1 of them unmatched: a `container_app_environment_dapr_component` data source page with no such type in the schema. azuredevops 1.16.0 has 183 pages (92 KB), 1 unmatched: `environment_kubernetes_resource`. vsphere 2.17.1 has 87 pages (104 KB), none unmatched; 7 of its slugs already carry the `vsphere_` prefix. `BuildSchemaPack` with docs takes about 80 s for the three.

```powershell
# Fill both caches: schemas, then docs (packs, or harvest).
Get-TerraformSchemaPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere
Get-TerraformDocPack    -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere
Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3 -PassThru   # ProviderAddress, Version, Status, DocCount, UnmatchedCount, Elapsed

# What is cached.
Get-TerraformDocCache

# By type, Id or category. -Type and -Id take wildcards.
Get-TerraformProviderDoc -Provider azurerm -Type 'azurerm_virtual_*'
Get-TerraformProviderDoc -Id 'registry.terraform.io/vmware/vsphere/resource/vsphere_virtual_machine' | Select-Object -ExpandProperty Content
Get-TerraformProviderDoc -Provider vsphere -Category guides, overview

# Only the ```hcl / ```terraform code blocks: Content holds them joined, ExampleCount says how many.
Get-TerraformProviderDoc -Provider azurerm -Type azurerm_key_vault -Examples | Format-List Id, ExampleCount, Content

# The unmatched pages, as a finding.
Get-TerraformProviderDoc -Provider vsphere -Id '*/unmatched/*' | Format-Table Category, Slug
```

### The agent pipeline

Pipe resource graph nodes in and you get the pages for exactly the resource and data source types the configuration uses, each page once. Everything comes from the local caches:

```powershell
Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema |
    Select-Object -ExpandProperty Nodes | Get-TerraformProviderDoc
```

A ResourceNode is looked up by its `SchemaId`, and a SchemaNode by its `Id`. A nested Block or Attribute node returns its resource's page, and a Provider or provider config node returns the overview. On `infra/`, with the null and local docs cached, that gives two pages: `.../hashicorp/null/resource/null_resource` for the two `null_resource` blocks, and `.../hashicorp/local/data/local_file`. The `terraform_data` blocks resolve to the built-in provider, which has no registry docs, and are skipped. A provider with no cached docs gets one warning naming `Get-TerraformDocPack` and `Update-TerraformProviderDocCache`. `Get-TerraformProviderDoc -Provider` for something that is not cached is a terminating error naming both.

Nothing here downloads except `Get-TerraformDocPack` and `Update-TerraformProviderDocCache`, and only when called. `Get-TerraformProviderDoc`, `Get-TerraformDocCache`, `-AutoSchema` and the argument completers read local files only.

## Bundle: which providers ship, and is it current

`data/bundle.json` in the module names the providers the shipped data covers and records what was harvested for each. As shipped it is the registry's **official** tier (34 providers) plus `microsoft/azuredevops` and `vmware/vsphere`: 36 providers indexed, 3 with packs attached (azurerm, azuredevops and vsphere have a schema pack, a docs pack and a bundled classifier; the other 33 are indexed from the registry only, and their docs exist only where someone harvested them). `Get-TerraformGraphBundle -Document` reports the split as `PackedEntryCount`, `ClassifiedEntryCount` and `RegistryOnlyEntryCount`.

```json
{ "formatVersion": 1, "tiers": ["official"],
  "providers": ["registry.terraform.io/microsoft/azuredevops", "registry.terraform.io/vmware/vsphere"],
  "exclude": [],
  "registry": { "harvestedOn": "...", "providerCount": 428 },
  "sources": [ { "kind": "docs", "urls": [ "https://registry.terraform.io/v2/provider-docs/{id}", "..." ],
                 "relatedUrls": [ "https://developer.hashicorp.com/terraform/registry/providers/docs" ],
                 "harvestedBy": "Update-TerraformProviderDocCache", "lastPulled": "..." } ],
  "entries": [ { "provider": "registry.terraform.io/hashicorp/azurerm", "version": "5.8.0", "docsVersion": "5.8.0",
                 "schemaVersion": "5.8.0", "classifierVersion": "5.8.0", "harvestedOn": "..." } ] }
```

Each entry's `version` is the provider's latest in that registry cache. `docsVersion` and `harvestedOn` come from the docs cache, and `schemaVersion` only when the schema cache holds exactly that version. `classifierVersion` is the newest classifier bundled with the module.

`sources` says where each kind of shipped data comes from: the upstream URLs, the pages that document them, the command that pulls it, and when it last did. `lastPulled` is taken from the data itself (the registry cache's `harvestedOn`, the newest docs harvest, and so on), never the clock. The registry's v2 API has no published reference, so its endpoints are listed as used. `cmdb` is reserved and empty.

```powershell
Get-TerraformGraphBundle                     # one row per provider: ProviderAddress, Version, DocsVersion, SchemaVersion, ClassifierVersion, HarvestedOn
Get-TerraformGraphBundle -Document           # the whole manifest: Tiers, Providers, Exclude, RegistryHarvestedOn, Sources, Entries, PackedEntryCount, RegistryOnlyEntryCount
Get-TerraformGraphBundle -Sources            # Kind, HarvestedBy, LastPulled, Urls (and RelatedUrls)
```

The shipped `-Sources`, 0.14.0:

```
Kind        HarvestedBy                      LastPulled           Urls
----        -----------                      ----------           ----
registry    Update-TerraformRegistryCache    2026-10-07T02:55:12Z {https://registry.terraform.io/v2/providers?filter[tier]=official,partner&page[size]=100, https://registry.terraform.io/v1/providers/.
schemas     Get-TerraformProviderSchema      2026-10-07T03:58:00Z {https://github.com/JerryBalmer1/Graph.Emitter.Terraform/releases/latest/download/manifest.json}
docs        Update-TerraformProviderDocCache 2026-10-07T05:19:53Z {https://registry.terraform.io/v2/provider-versions/{id}?include=provider-docs, https://registry.terraform.io/v2/provider-docs/{id}}
classifiers New-TerraformClassifier          2026-10-07T05:22:55Z {https://github.com/JerryBalmer1/Graph.Emitter.Terraform/tree/main/src/Graph.Emitter.Terraform/classifiers}
skills      Install-TerraformGraphSkill                           {https://github.com/JerryBalmer1/Graph.Emitter.Terraform/tree/main/src/Graph.Emitter.Terraform/skills}
cmdb                                                              {}
```

```powershell

# Your own set, written to $env:LOCALAPPDATA\TerraformGraph\bundle.json (read before the bundled copy).
New-TerraformGraphBundle -Tier official -Provider 'vmware/*' -Exclude hashicorp/hcs -PassThru
New-TerraformGraphBundle -Tier @() -Provider hashicorp/azurerm, hashicorp/azuread -OutputPath .\bundle.json
```

Each of `-Tier`, `-Provider` and `-Exclude` you leave out comes from the bundled manifest. Patterns match by shape and take wildcards, as for `Get-TerraformRegistryProvider`. `-Provider` patterns are stored expanded to full addresses; `-Exclude` patterns are stored as given, so they keep excluding providers that appear in the registry later. The registry cache used is `registry.json` in the output folder when there is one, else the usual one. The file is sorted and has no timestamp of its own, so rewriting it from the same caches gives the same bytes.

### Bulk docs harvest

```powershell
$summary = Update-TerraformProviderDocCache -BundlePath .\bundle.json -Resume
$summary                                       # ProviderCount, PageCount, UnmatchedCount, FailureCount, RateLimitHits, Elapsed
$summary | Format-List SecondsBlocked, PartialResumes, LogPath
$summary.Failures | Format-Table ProviderAddress, Version, Error
```

`-BundlePath` harvests every provider in the bundle's set at its latest version, one provider after another. Pages are fetched in parallel (`-ThrottleLimit`, default 6). A provider that fails is a warning and a `Failed` row with its `Error`, never a stop, and nothing is written for it. Without `-Resume` every provider is harvested again; with it, a provider already cached at that version is skipped without any network call, which is how an interrupted run is finished. `-Resume` also works with `-Provider`.

A harvest that stops part-way (a failed page, Ctrl+C) keeps the pages it fetched in `$env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.partial.json`, also saved every 100 pages in case the process dies. Rerun the same command with `-Resume` and it fetches only the missing pages (`ResumedPages` on the row, `PartialResumes` on the summary); a finished harvest deletes the file, `-Force` deletes it and starts over, and the file is never read as cached docs.

Every bundle run writes `$env:LOCALAPPDATA\TerraformGraph\logs\harvest-<yyyyMMdd-HHmmss>.log` (UTC): a start line, one line per provider (address, version, status, pages, elapsed, error), one per 429 and per wait, and an end line with the rate-limit totals. The path is printed at the end and returned as `LogPath`.

The registry sits behind a rate limit that answers a sustained run with 429 for several minutes, with no Retry-After. The block was observed once, lasting about 9 minutes, during the 2026-10-06 (local time) harvest; it was not logged, so the waits below are a working assumption. The first 429 stops every worker, waits 30 seconds (then 60, 120, 240 and 300 on repeated 429s, or the Retry-After when one is sent, at most 600), and resumes with one worker, adding one per 25 successful requests; the throttle carries over to the next provider and the next command in the same session.

The bundled set, harvested on 2026-10-07 with `Invoke-Build HarvestBundleDocs`: 36 providers, 14,686 pages, 3 unmatched. The largest were awscc 1.104.0 (4,521 pages), aws 6.67.0 (2,414), google and google-beta 8.6.0 (1,685 each), azurerm 5.8.0 (1,518) and ibm 2.6.2 (1,445). The first run (12 min 28 s) got 3,374 pages from 19 providers. The registry started answering 429 just after aws, and 17 providers failed, because the backoff then was two retries at 1 and 2 seconds. The second run, `-Resume` with the backoff above, harvested 16 of them in 12 min 17 s with no failures; the 17th, azurerm, was already cached at 5.8.0 by `BuildSchemaPack` and was skipped.

```powershell
Invoke-Build HarvestBundleDocs            # harvest, refresh data/bundle.json, write dist/survey/subcategories.json
Invoke-Build HarvestBundleDocs -Resume    # finish an interrupted run
```

### Subcategory survey

The registry docs carry each provider's own grouping of its types (`subcategory`: "Key Vault", "S3 (Simple Storage)", "Host and Cluster Management"). The survey counts resource and data source pages per provider and label, from the docs cache only:

```powershell
Get-TerraformSubcategorySurvey -Provider vsphere                          # ProviderAddress, Subcategory, ResourceCount, DataSourceCount, Status
Get-TerraformSubcategorySurvey -OutputPath .\dist\survey\subcategories.json   # the bundle's providers, written with provenance
```

There is one row per provider and label, plus a `NoSubcategory` row for a provider whose pages have no label. The JSON file adds provenance: the bundle's provider set and registry cache, each provider's docs version, harvest time and schema version, the providers with no cached docs (`missing`), and every label with the number of providers that use it. It is the evidence behind the drawer list (see Classifiers).

On the bundled set (2026-10-07): 661 distinct labels in 893 rows. Only 11 of the 36 providers label their pages: aws 260, google and google-beta 181 each (the same list), azurerm 112, ibm 56, kubernetes 24, azuread 17, hcp 12, vsphere 9, azurestack 8 and turbonomic 5. The other 25 publish no labels, awscc's 4,521 pages included. Nine labels appear in three providers, none in more: Agent Registry, API Gateway, Base, Cloud IAM, Cloud Platform, Container Registry, License Manager, Service Networking and Storage.

### Freshness gate

`Test-TerraformGraphBundle` checks the bundled data against its sources and returns one row per check. `-Scope` says what the rows certify: `Machine` (the default) checks the bundle against this machine's caches as well, so its docs and schema rows describe your `$env:LOCALAPPDATA`; `Repo` reads only the bundle's own folder (the `registry.json` beside it), the module's bundled classifiers and `-DistPath`, never a user cache, so it gives the same rows on any machine with the same checkout. Each row: `Item`, `Status` (`Fresh`, `Stale`, `Missing`), `Detail`, and for every row that is not Fresh two pasteable commands. `InspectAction` shows what would change (a `git diff --no-index` of a candidate written under `$env:TEMP\TerraformGraph-inspect`, or the cache's state) without touching the module; `RecommendedAction` makes the change. For the bundled manifest the actions are Invoke-Build tasks (`BuildRegistry`, `BuildSchemaPack -Provider`, `BuildClassifier -Provider`, `HarvestBundleDocs -Resume`); for your own copy they are the commands that rewrite it. The default table shows `Item`, `Status` and `RecommendedAction`. It is offline unless you pass `-Online`.

| Item | Checks |
|---|---|
| `registry` | The bundle's `registry.harvestedOn` and provider count against the registry cache it resolves against. |
| `sources` | The bundle has a `sources` block, and it is what rewriting the bundle from the same caches would write. |
| `entry <address>` | The entry is in the bundle's provider set, and its version is that cache's latest. Every provider in the set has an entry. |
| `docs <address>` | `-Scope Machine` only: `docsVersion` is cached, equals the entry version, and `harvestedOn` matches the cached file. A Missing row names `Get-TerraformDocPack` only when a docs pack exists for that version. |
| `schema <address>` | `-Scope Machine` only, when the entry records one: cached, and at the entry version. |
| `classifier <address>` | When the entry records one: bundled, and at the entry version. |
| `mapVersion <address> <version>` | Each bundled classifier's `mapVersion` against `classifiers/map.json`. |
| `pack <kind> <address> <version>` | When `-DistPath` (default `.\dist\schema-packs`) has a `manifest.json`: each file's sha256 and its version against the entry. |
| `registry (online)`, `online <address>` | With `-Online`: the live registry's provider count and each entry's live latest version. |

```powershell
Test-TerraformGraphBundle | Where-Object Status -ne Fresh
Test-TerraformGraphBundle | Where-Object Status -ne Fresh | Format-List Item, Detail, InspectAction, RecommendedAction
pwsh -NoProfile -Command "Import-Module Graph.Emitter.Terraform; Test-TerraformGraphBundle -Strict | Out-Null"   # exit 1 when anything is Stale or Missing
```

A bundle for `hashicorp/null`, written against a `registry.json` beside it that has since been refreshed (`-DistPath` pointed at a folder with no packs):

```
Item                                                          Status RecommendedAction
----                                                          ------ -----------------
registry                                                      Stale  New-TerraformGraphBundle -Tier @() -Provider 'registry.terraform.io/hashicorp/null' -Exclude @() -OutputPath
                                                                     'C:\Users\jlbal\AppData\Local\Temp\tg-stale-446215794\bundle.json'
sources                                                       Stale  New-TerraformGraphBundle -Tier @() -Provider 'registry.terraform.io/hashicorp/null' -Exclude @() -OutputPath
                                                                     'C:\Users\jlbal\AppData\Local\Temp\tg-stale-446215794\bundle.json'
entry registry.terraform.io/hashicorp/null                    Fresh
docs registry.terraform.io/hashicorp/null                     Fresh
mapVersion registry.terraform.io/hashicorp/azurerm 5.8.0      Fresh
mapVersion registry.terraform.io/microsoft/azuredevops 1.16.0 Fresh
mapVersion registry.terraform.io/vmware/vsphere 2.17.1        Fresh
```

Run the `InspectAction` first, read the diff, then run the `RecommendedAction` if you want the change. Data you harvest lands in your user caches; the module's own files change only through the Invoke-Build tasks.

`-Strict` writes every row, then throws `BundleNotFresh`, whose message lists each row with its fix. The release build runs it as `Invoke-Build CheckBundle` (`-Scope Repo -Strict`) before a release is created; that task prints each row's inspect and fix commands.

On the shipped data (0.14.1, 2026-10-07), with `dist\schema-packs` from `BuildSchemaPack` present: `-Scope Repo` gives 50 checks, all Fresh, with or without a user cache. `-Scope Machine` gives 89 checks, all Fresh on the author's machine; on a machine with empty caches the same 89 are 49 Fresh, 39 Missing (36 docs, 3 schemas) and 1 Stale (sources).
## Classifiers: what ships / how to cut your own

A provider schema is flat: azurerm alone has 1,502 resource and data source types. Classifier drawers are an optional overlay that groups types into drawers (network, compute, storage, database, identity, security, ...) so a view can collapse to twenty-one rows. They never change a node's Id, the node count or the edges, and every placement can be traced to a map row with a reason.

### What ships

The module's `classifiers/` folder (committed, unlike `dist/`):

| File | What it is |
|---|---|
| `drawers.json` | The fixed drawer list: network, compute, storage, database, identity, security, messaging, integration, observability, management, devops, containers, serverless, dns, cdn, analytics, ai, iot, media, migration, unclassified. Each has `name`, `label` and `description`. `integration` was added in 0.13.0 after the subcategory survey (DECISIONS 41). |
| `map.json` | Rows `{ provider, source, subcategory, drawer, reason, addedOn, addedBy }`. `source` is optional: `subcategory` (the default) maps a doc label, and `prefix` maps a type-name prefix (see below). `provider` is an address or `*` (subcategory rows only), and a provider row beats a `*` row. Every row has a one-sentence `reason`. |
| `DECISIONS.md` | Append-only, numbered record of every judgement behind the drawers and the map, including every subcategory left unmapped and why. |
| `<address-slug>.<version>.json` | One classifier per provider version: azurerm 5.8.0, azuredevops 1.16.0 and vsphere 2.17.1. |

The default classifier is not hand-sorted. Each type's subcategory is the label the provider itself puts on the type's registry doc page ("Key Vault", "Host and Cluster Management"), and `map.json` maps that label to a drawer.

Some providers publish no labels at all; azuredevops is one. For those, **prefix rows** place types by name. A prefix row names one provider, and its `subcategory` field holds the type prefix after the provider token: `{ "provider": "registry.terraform.io/microsoft/azuredevops", "source": "prefix", "subcategory": "git", "drawer": "devops", ... }` places `azuredevops_git_repository` and every other `azuredevops_git` and `azuredevops_git_*` type, but not a hypothetical `azuredevops_github_*`. Prefixes match at underscore boundaries, the longest match wins, and a prefix row applies only to a type with no label (no doc page, or an empty subcategory). A label the map does not place stays a finding, whatever its prefix. Each classified type records the `source` of the row that placed it. `New-TerraformClassifier` refuses a prefix row that matches no type in the provider's cached schema.

A type no row places goes in `unclassified` and is listed as a finding:

| Finding | Meaning |
|---|---|
| `NoDocPage` | The schema has the type, but the docs have no page for it. |
| `NoSubcategory` | The page's subcategory is empty. |
| `UnmappedSubcategory` | The map has no row for the label: deliberately, see DECISIONS.md. |

`unclassified` is a legitimate drawer, not an error. As shipped in 0.13.0 (`Invoke-Build BuildClassifier`, 2026-10-07):

| Provider | Types | Unclassified | Notes |
|---|---|---|---|
| azurerm 5.8.0 | 1,502 | 34 | 10 labels left unmapped, Healthcare (11 types) the largest. API Management (64), Connections (3) and Logic App (19) are in `integration`. |
| azuredevops 1.16.0 | 177 | 0 | No labels; 41 prefix rows place everything: devops 149, identity 27, management 1. In 0.12.0 all 177 were unclassified. |
| vsphere 2.17.1 | 87 | 1 | A type with no doc page. |

```powershell
Get-TerraformClassifier                                     # ProviderAddress, Version, DocsVersion, TypeCount, FindingCount
(Get-TerraformClassifier -Provider vsphere).Types | Group-Object Drawer
Get-TerraformClassifierFinding -Provider azurerm            # Type, Kind, Subcategory, Finding

# The overlay: Drawer and Subcategory on every node, plus a Drawers summary. Same Ids, nodes and edges.
$schema = ConvertTo-TerraformSchemaGraph -Provider vsphere -Classify
$schema.Drawers                                             # Drawer, TypeCount (InstanceCount is empty on a schema graph)
$graph = Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema -Classify
$graph.Drawers                                              # Drawer, TypeCount, InstanceCount
$graph.Nodes | Sort-Object Drawer | Format-Table Drawer, Subcategory, ResourceAddress
```

On a schema graph, Block and Attribute nodes take the drawer of the resource or data source they belong to, so collapsing a drawer takes the whole subtree. Provider, provider config and Function nodes have no drawer. A provider with no classifier gets one warning, and its types are unclassified. The built-in `terraform` provider is unclassified with no warning.

### How to cut your own

Classifiers are looked up in this order: `-ClassifierPath` (a file or a folder), then `$env:LOCALAPPDATA\TerraformGraph\classifiers`, then the bundled folder. The first that holds a provider picks the version, even over a newer bundled version. When more than one folder holds that same version, a file from `-ClassifierPath` wins; otherwise the one built from the current `map.json` (its `mapVersion`) wins, then the newer `generatedOn`, and a warning names the file left out and how to remove or promote it. `Get-TerraformClassifier -Shadowed` lists those collisions (ProviderAddress, Version, Location, Reason; Path and ShadowedPath in the object); on a clean install it returns nothing.

```powershell
# Any provider whose schema and docs are cached (packs, -SaveToCache, Update-TerraformProviderDocCache).
# Before adding a row or a drawer, see how many providers share the label: Get-TerraformSubcategorySurvey.
New-TerraformClassifier -Provider hashicorp/null, hashicorp/local -PassThru    # into the user folder

# Your own opinions: copy map.json, add rows (each with a reason), classify into a folder, point the graphs at it.
Copy-Item (Join-Path (Split-Path (Get-Module Graph.Emitter.Terraform).Path) 'classifiers\map.json') .\my-map.json
New-TerraformClassifier -Provider azurerm -MapPath .\my-map.json -OutputPath .\my-classifiers -PassThru
ConvertTo-TerraformSchemaGraph -Provider azurerm -ClassifierPath .\my-classifiers | Select-Object -ExpandProperty Drawers
```

`New-TerraformClassifier` checks the map first. A row with an empty reason, a drawer not in `drawers.json` (taken from beside the map, else the bundled one), a row targeting `unclassified`, a `source` other than `subcategory` or `prefix`, a `*` prefix row, or a repeated provider, source and subcategory stops it before anything is read. A prefix row that matches none of the provider's schema types stops it once the schema is read. Output is sorted by type, then kind. When a rerun produces the same content, the file and its `generatedOn` are left alone, so reruns are byte-identical. `mapVersion` is a hash of the map's rows. `-ClassifierPath` implies `-Classify`.

To change the shipped classifiers: read `DECISIONS.md`, append an entry for each judgement, edit `map.json` (never without a reason), then run `Invoke-Build BuildClassifier` (default azurerm, azuredevops, vsphere at their latest version in the registry cache, from your local caches, no network). It prints the findings per provider. Stage `src/Graph.Emitter.Terraform/classifiers/`. Pester fails if a bundled classifier's `mapVersion` no longer matches `map.json`.

Drawer names are versioned like an API: adding a drawer or map rows is a minor release, renaming or removing a drawer is a major one. Pester ("drawers are semver-safe") compares `drawers.json` with the previous release's and fails a rename or removal unless the module's major version went up.

## Agent skills

The module ships an agent skill at `skills/terraformgraph/SKILL.md` inside the module folder. It follows the open Agent Skills format: YAML front matter with `name` and `description` (when an agent should load it), then a Markdown body. The body covers importing the module, the functions in pipeline order with their input and output types, the canonical Id scheme, the `ModuleAddress`/`ResourceAddress` naming rule, and example pipelines, led by the provider docs pipeline.

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
Graph.Emitter.Terraform: detected Claude in this directory. Run Install-TerraformGraphSkill -Tool Claude to give them the Graph.Emitter.Terraform skill.
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
Invoke-Build BuildDLL         # Docker: golang 1.24 + mingw -> src/Graph.Emitter.Terraform/lib/TerraformGraph.dll (and the generated .h)
Invoke-Build BuildJson        # optional, a .NET 8 SDK: lib/TerraformGraph.Json.dll, so import does not compile C#
Invoke-Build                  # the default test run, no network: pwsh -NoProfile -File .\tests\Invoke-Tests.ps1
Invoke-Build AssembleModule   # dist/module/Graph.Emitter.Terraform: exactly the files the psd1 FileList names, with one psm1 built from Private/ and Public/
```

Function code is one function per file, named for the function: `src/Graph.Emitter.Terraform/Public/<Verb-Noun>.ps1` for an exported command, `src/Graph.Emitter.Terraform/Private/<Verb-Noun>.ps1` for a helper. Edit the file named for the function, never `Graph.Emitter.Terraform.psm1`: it is wiring only, and `Invoke-Build AssembleModule` builds the single psm1 that ships.

`BuildDLL` cross-compiles `src/go` with `github.com/hashicorp/hcl/v2` and copies `TerraformGraph.dll` into `src/Graph.Emitter.Terraform/lib/`. `pwsh -NoProfile -File .\tests\Invoke-Tests.ps1 -Live` runs the tests that call the registry; never run it while a harvest is going.

## Disclaimer

This project is independent. It is not affiliated with HashiCorp.

## License

Graph.Emitter.Terraform is licensed under the [Apache License 2.0](LICENSE).

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer&color=0:844FBA,55:5C4EE5,100:1B1030&text=Graph.Emitter.Terraform&fontSize=28&fontColor=FFFFFF&fontAlignY=70&animation=fadeIn" alt="" />
</p>
