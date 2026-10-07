---
name: terraformgraph
description: Load when working with Terraform code or provider schemas in PowerShell using the TerraformGraph module (parse .tf files, graph module calls, variables, provider schemas and resources).
---

# TerraformGraph

PowerShell 7.4+ module that parses Terraform `.tf` files into an HCL AST (HashiCorp HCL v2, through a native DLL) and builds graphs of module calls, variables, provider schemas and resources on top of it. Windows only (the DLL is a Windows build).

## Import

```powershell
Import-Module TerraformGraph                                  # installed copy
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force # from a clone of the repo
```

Fresh-process rule: the parser DLL is loaded with P/Invoke and stays pinned for the life of the process. After the DLL is rebuilt, an open shell keeps running the old parser, so run tests in a new process:

```powershell
pwsh -NoProfile -Command 'Invoke-Pester -Path .\tests'
```

## Functions, in pipeline order

- `Get-TerraformAST` — `-Path` dir (`-Recurse`) or `-FilePath` one `.tf` → `TerraformGraph.Block` (Type, Labels, Body, ranges; expressions carry `Kind`, `Raw`, `SrcRange`).
- `Get-TerraformModuleGraph` — `-Path` root module (`-Recurse`, `-GroupBy Call|Source`) → `TerraformGraph.ModuleGraph` (Nodes `TerraformGraph.ModuleNode`, Edges, Unresolved). Never runs `terraform init`; non-local sources come from `.terraform/modules/modules.json`.
- `ConvertTo-TerraformVariableGraph` — `TerraformGraph.ModuleGraph` → `TerraformGraph.VariableGraph` (variables, locals, outputs; edges Reference, Argument, OutputReference; Unresolved, Skipped). Never reparses.
- `Get-TerraformVariableTrace` — `TerraformGraph.VariableGraph` + `-Id` (`-Direction Upstream|Downstream|Both`, `-MaxDepth`) → `TerraformGraph.VariableTrace` (Nodes `TerraformGraph.VariableTraceNode` with `Distance`, Edges).
- `Update-TerraformRegistryCache` — (`-Scope OfficialPartner|All`, `-Path`, `-ThrottleLimit`, `-PassThru`) harvests the public registry's provider list and versions into the user cache `$env:LOCALAPPDATA\TerraformGraph\registry.json` → nothing, or `TerraformGraph.RegistryCache` with `-PassThru`. The only command that reads the provider list over the network.
- `Get-TerraformRegistryProvider` — `-Name` patterns (`-Tier official|partner|community`, `-NoBundledData`) → `TerraformGraph.RegistryProvider` (ProviderAddress, Source, Tier, Latest, VersionCount, Versions newest first) from the cache, never the network. The user cache wins over the copy bundled with the module.
- `Get-TerraformProviderSchema` — `-Path` initialized dir, or `-Provider` fetched on demand (`-Version`, `-WorkingDirectory`, `-Cleanup`, `-Force`, `-NoBundledData`) → `OrderedDictionary` (default) or JSON string (`-OutputFormat Json`). Needs `terraform` on PATH; `-Provider` needs registry access.
- `ConvertTo-TerraformSchemaGraph` — provider schema (dictionary, JSON text, or PSCustomObject) (`-Provider`, `-IncludeFunctions`) → `TerraformGraph.SchemaGraph` (Providers, Nodes `TerraformGraph.SchemaNode`, Edges `Contains`, Summary).
- `ConvertTo-TerraformResourceGraph` — `TerraformGraph.ModuleGraph` + optional `-SchemaGraph` array → `TerraformGraph.ResourceGraph` (Nodes `TerraformGraph.ResourceNode`, `InstanceOf` Edges, Skipped, Providers, MatchedCount, UnmatchedCount, Findings).
- `ConvertTo-TerraformJson` — any object → JSON string with no 100-level depth cap (`-Depth`, `-Compress`, `-AsArray`).
- `ConvertFrom-TerraformJson` — JSON string → PSCustomObject, or ordered dictionaries with `-AsHashtable` (`-Depth`, `-NoEnumerate`).

Use `ConvertTo-TerraformJson` / `ConvertFrom-TerraformJson` instead of the built-in cmdlets for provider schemas: `ConvertTo-Json` silently truncates past depth 100.

## Provider names and wildcards

Name patterns match by shape: `aws` or `aws*` matches the bare name in any namespace, `hashicorp/aws*` matches namespace/name, and `registry.terraform.io/hashicorp/aws` matches the full address. `Get-TerraformProviderSchema -Provider` with a wildcard resolves against the registry cache and must match exactly one provider; otherwise it stops before running terraform, with every match listed (`'aws*' matches 4 providers: hashicorp/aws, hashicorp/awscc, ... Specify one.`). A `-Provider` without a wildcard needs no cache. Tab completion of `-Provider`, `-Version` and `Get-TerraformRegistryProvider -Name` reads the cache only.

## Canonical Ids

`Id` is unique per document and is what you join on. `<module>` is the ModuleAddress (`root` for the root module, else e.g. `module.network.module.endpoint`); `<address>` is the provider address (e.g. `registry.terraform.io/hashicorp/aws`, `terraform.io/builtin/terraform`).

| Graph | Kind | Id |
|---|---|---|
| Module | ModuleNode | ModuleAddress (`-GroupBy Call`) or source string (`-GroupBy Source`); the root is `root` |
| Variable | Variable | `<module>/var/<name>` |
| Variable | Local | `<module>/local/<name>` |
| Variable | Output | `<module>/output/<name>` |
| Schema | Provider | `<address>` |
| Schema | Provider config | `<address>/config/<name>` |
| Schema | Resource | `<address>/resource/<type>` |
| Schema | DataSource | `<address>/data/<type>` |
| Schema | Function | `<address>/function/<name>` |
| Schema | Block / Attribute | `<parent Id>/<name>` |
| Resource | Resource | `<module>/resource/<type>.<name>` |
| Resource | DataSource | `<module>/data/<type>.<name>` |

A schema Id names a resource *type* under a provider; a resource-graph Id names one *block* in one module. A ResourceNode's `SchemaId` holds the schema Id it joins to. Schema nodes also have `Path` (`null_resource.triggers`), which is for display only and can repeat across providers.

## Naming

Node types never have a property named `Address`, `Count`, `Length` or any other member of `System.Array`: on an array of nodes, `.Address` resolves to the array's own method and returns garbage. Use the qualified names: `ModuleAddress` on ModuleNode, `ResourceAddress` on ResourceNode, `ProviderAddress` for providers. `$graph.Nodes.ResourceAddress` works.

## Examples

Module graph to variable trace: where does the network module's `aws_region` come from?

```powershell
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformVariableGraph
($graph | Get-TerraformVariableTrace -Id 'module.network/var/aws_region' -Direction Upstream).Nodes
```

Provider schema to schema graph, filtered to one provider:

```powershell
$graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph -Provider aws
$graph.Nodes | Where-Object Path -like 'aws_s3_bucket.*'
```

Module graph plus schema graphs to a resource graph, then the nodes counted in Findings:

```powershell
$schemas = @(
    Get-TerraformProviderSchema -Provider null -Cleanup | ConvertTo-TerraformSchemaGraph
    Get-TerraformProviderSchema -Provider local -Cleanup | ConvertTo-TerraformSchemaGraph
)
$graph = Get-TerraformModuleGraph -Path .\infra -Recurse | ConvertTo-TerraformResourceGraph -SchemaGraph $schemas
$graph   # Root, NodeCount, MatchedCount, UnmatchedCount, Findings
$graph.Nodes | Where-Object { $_.UnknownAttributes -or $_.UnknownBlocks -or $_.MissingRequired } |
    Format-List ResourceAddress, UnknownAttributes, UnknownBlocks, MissingRequired
```

Only the top level of each resource block is checked against the schema. Unmatched nodes carry `Reason` `NoSchemaGraph`, `ProviderNotInSchemaGraph` or `TypeNotInProvider`.
