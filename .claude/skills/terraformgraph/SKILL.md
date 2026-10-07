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
- `Get-TerraformProviderSchema` — `-Path` initialized dir, or `-Provider` fetched on demand (`-Version`, `-WorkingDirectory`, `-Cleanup`, `-Force`, `-NoBundledData`, `-SaveToCache`) → `OrderedDictionary` (default) or JSON string (`-OutputFormat Json`). Needs `terraform` on PATH; `-Provider` needs registry access. `-SaveToCache` also writes the schema to the local schema cache at the version terraform selected.
- `Get-TerraformSchemaPack` — `-Provider` (wildcards via the registry cache; default every manifest entry), `-Version`, `-Source` (URL, default the latest GitHub release, or a local folder), `-Force`, `-PassThru` → downloads `manifest.json` and pack files, checks sha256, writes them into the schema cache; `TerraformGraph.SchemaPack` (ProviderAddress, Version, Path, Bytes, Status `Downloaded|Cached|Updated`) with `-PassThru`.
- `Get-TerraformSchemaCache` — `-Provider` patterns → `TerraformGraph.CachedSchema` (ProviderAddress, Version, Path, Bytes, CachedOn). Read only.
- `Update-TerraformProviderDocCache` — `-Provider` (wildcards via the registry cache), `-Version` (default latest in the registry cache), `-ThrottleLimit`, `-Force`, `-PassThru` → harvests a provider version's registry docs into the docs cache, Ids matched against the cached schema; `TerraformGraph.DocCache` (ProviderAddress, Version, Path, Status `Harvested|Cached|Updated`, DocCount, UnmatchedCount, Elapsed) with `-PassThru`. Network.
- `Get-TerraformDocPack` — same parameters as `Get-TerraformSchemaPack`, for the manifest's `docs` entries → `TerraformGraph.DocPack` with `-PassThru`.
- `Get-TerraformDocCache` — `-Provider` patterns → `TerraformGraph.CachedDoc` (ProviderAddress, Version, Path, Bytes, CachedOn, DocCount, UnmatchedCount). Read only.
- `Get-TerraformProviderDoc` — `-Provider` patterns (default every cached provider), `-Version`, `-Id` and `-Type` wildcards, `-Category resources|data-sources|guides|overview`, `-Examples`, or piped SchemaNode (by `Id`) / ResourceNode (by `SchemaId`) → `TerraformGraph.ProviderDoc` (Id, ProviderAddress, Version, Category, Title, Subcategory, Slug, Type, Content markdown, ExampleCount with `-Examples`). Each page once per call. Cache only.
- `ConvertTo-TerraformSchemaGraph` — provider schema (dictionary, JSON text, or PSCustomObject) (`-Provider` filter, `-IncludeFunctions`), or with no schema `-Provider` patterns (`-Version`, default newest cached) loaded from the schema cache → `TerraformGraph.SchemaGraph` (Providers, Nodes `TerraformGraph.SchemaNode`, Edges `Contains`, Summary). `-Classify` (or `-ClassifierPath`) adds Drawer and Subcategory to every node and a `Drawers` summary.
- `ConvertTo-TerraformResourceGraph` — `TerraformGraph.ModuleGraph` + one of: optional `-SchemaGraph` array, `-Provider` (schema graphs from the cache for those providers), or `-AutoSchema` (cached schemas for every provider the module graph resolves to) → `TerraformGraph.ResourceGraph` (Nodes `TerraformGraph.ResourceNode`, `InstanceOf` Edges, Skipped, Providers, MatchedCount, UnmatchedCount, Findings). `-Classify` (or `-ClassifierPath`) adds Drawer and Subcategory to every node and a `Drawers` summary with TypeCount and InstanceCount.
- `New-TerraformClassifier` — `-Provider` (wildcards via the registry cache), `-Version` (default newest cached schema), `-MapPath` (default the bundled `classifiers/map.json`), `-OutputPath` (default `$env:LOCALAPPDATA\TerraformGraph\classifiers`), `-PassThru` → writes `<address-slug>.<version>.json` from the schema and docs caches; `TerraformGraph.ClassifierBuild` (Status `Written|Updated|Unchanged`, TypeCount, FindingCount) with `-PassThru`. No network.
- `Get-TerraformClassifier` — `-Provider` patterns, `-Version`, `-ClassifierPath` → `TerraformGraph.Classifier` (Types: Type, Kind, Subcategory, Drawer; Findings; TypeCount, FindingCount, Path).
- `Get-TerraformClassifierFinding` — same parameters → `TerraformGraph.ClassifierFinding` rows (Type, Kind, Subcategory, Finding `NoDocPage|NoSubcategory|UnmappedSubcategory`).
- `ConvertTo-TerraformJson` — any object → JSON string with no 100-level depth cap (`-Depth`, `-Compress`, `-AsArray`).
- `ConvertFrom-TerraformJson` — JSON string → PSCustomObject, or ordered dictionaries with `-AsHashtable` (`-Depth`, `-NoEnumerate`).

Use `ConvertTo-TerraformJson` / `ConvertFrom-TerraformJson` instead of the built-in cmdlets for provider schemas: `ConvertTo-Json` silently truncates past depth 100.

## Provider names and wildcards

Name patterns match by shape: `aws` or `aws*` matches the bare name in any namespace, `hashicorp/aws*` matches namespace/name, and `registry.terraform.io/hashicorp/aws` matches the full address. `Get-TerraformProviderSchema -Provider` with a wildcard resolves against the registry cache and must match exactly one provider; otherwise it stops before running terraform, with every match listed (`'aws*' matches 4 providers: hashicorp/aws, hashicorp/awscc, ... Specify one.`). A `-Provider` without a wildcard needs no cache. Tab completion of `-Provider`, `-Version` and `Get-TerraformRegistryProvider -Name` reads the cache only.

## Schema cache

Provider schemas are not bundled. They live in `$env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz`, where address-slug is the lowercase provider address with `/` → `-` (`registry.terraform.io-hashicorp-azurerm\5.8.0.json.gz`). Fill it with `Get-TerraformSchemaPack` (release packs, no terraform needed) or `Get-TerraformProviderSchema -Provider <p> -SaveToCache` (any provider and version, needs terraform and the registry). Then `ConvertTo-TerraformSchemaGraph -Provider <p>` and `ConvertTo-TerraformResourceGraph -Provider <p>` or `-AutoSchema` work offline. A provider that is not cached is a terminating error naming both fill commands. With `-AutoSchema`, providers that are not cached are marked `ProviderNotInSchemaGraph`. Check with `Get-TerraformSchemaCache` before assuming a schema is there.

Rule: never download inside a completer or `-AutoSchema`. Both read local caches only. `Get-TerraformSchemaPack` and `Get-TerraformDocPack` are the only commands that fetch packs, and only when called explicitly. For a private GitHub release source, set `$env:GH_TOKEN` (or `$env:GITHUB_TOKEN`) and they go through the GitHub API with it; without a token a 404 says the repo may be private.

## Provider docs

Registry markdown pages live in `$env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz`, keyed on schema node Ids: overview `<address>`, guide `<address>/guide/<slug>`, resource `<address>/resource/<type>`, data source `<address>/data/<type>`. A page whose type is not in the cached schema keeps `<address>/unmatched/<category>/<slug>` and counts in `UnmatchedCount`. That is a finding about the provider docs, not an error. Fill with `Get-TerraformDocPack` (release packs) or `Update-TerraformProviderDocCache` (registry; cache the schema first so Ids are checked). Check with `Get-TerraformDocCache`. `Get-TerraformProviderDoc -Provider <p>` for something not cached is a terminating error naming both fill commands; in the pipeline, an uncached provider gets one warning and built-in providers are skipped. Read the page's `Content` (markdown), or use `-Examples` for only the ```hcl / ```terraform blocks.

## Classifiers

Classifier drawers group resource and data source types into drawers (network, compute, storage, ..., unclassified) so a view can collapse. They are opinions layered on facts. They never change a node's Id, the node count or the edges, and they ship as data with provenance in the module's `classifiers/` folder:

- `drawers.json` is the fixed drawer list.
- `map.json` has rows `{ provider (address or "*"), subcategory, drawer, reason, addedOn, addedBy }`. A provider row beats a `*` row.
- `DECISIONS.md` is the append-only record of every judgement.
- `<address-slug>.<version>.json` is one classifier per provider version.

The default classifier comes from the provider's own doc `subcategory` labels, not from hand-sorting. A type with no doc page, an empty subcategory or an unmapped subcategory is in `unclassified` and is listed as a finding. That is a legitimate drawer, not an error. Lookup order is `-ClassifierPath`, then `$env:LOCALAPPDATA\TerraformGraph\classifiers`, then the bundled folder.

```powershell
$graph = Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema -Classify
$graph.Drawers                                   # Drawer, TypeCount, InstanceCount
Get-TerraformClassifierFinding -Provider azurerm # what the map could not place
```

Rules when asked to classify, or to touch anything under `classifiers/`:

1. Read `classifiers/DECISIONS.md` first. Do not reopen a call recorded there without appending an entry that supersedes it.
2. Append a numbered entry (Question / Call / Rejected / Why / Cost if wrong) for every judgement you make, including every subcategory you leave unmapped. Never edit an earlier entry.
3. Never add or change a `map.json` row without a non-empty `reason`. Cite the DECISIONS entry in the reason when the call is arguable. Never target `unclassified`: leave the row out and record why. The Pester lint and `New-TerraformClassifier` both reject a row with an empty reason.
4. After changing `map.json`, rerun `Invoke-Build BuildClassifier` and stage the regenerated classifiers. A Pester test fails when a bundled classifier's `mapVersion` no longer matches the map.

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
| Docs | Overview / Guide | `<address>` / `<address>/guide/<slug>` |
| Docs | Resource / DataSource page | the schema Id: `<address>/resource/<type>` / `<address>/data/<type>` |
| Docs | Unmatched page | `<address>/unmatched/<category>/<slug>` |

A schema Id names a resource *type* under a provider; a resource-graph Id names one *block* in one module. A ResourceNode's `SchemaId` holds the schema Id it joins to. Schema nodes also have `Path` (`null_resource.triggers`), which is for display only and can repeat across providers.

## Naming

Node types never have a property named `Address`, `Count`, `Length` or any other member of `System.Array`: on an array of nodes, `.Address` resolves to the array's own method and returns garbage. Use the qualified names: `ModuleAddress` on ModuleNode, `ResourceAddress` on ResourceNode, `ProviderAddress` for providers. `$graph.Nodes.ResourceAddress` works.

## Examples

Start here when you need provider documentation for a repository. The docs for exactly the resource and data source types the repository uses, each page once, from the local caches with no network:

```powershell
Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema |
    Select-Object -ExpandProperty Nodes | Get-TerraformProviderDoc
```

If it warns that a provider has no cached docs, fill the caches once (`Get-TerraformSchemaPack` and `Get-TerraformDocPack` for the pack providers, or `Update-TerraformProviderDocCache -Provider <p>` for any registry provider). Then narrow it down: `Get-TerraformProviderDoc -Provider azurerm -Type 'azurerm_key_vault*' -Examples`.

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

Same check against the schema cache, with no terraform and no network:

```powershell
Get-TerraformSchemaPack -Provider hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere   # once
$graph = Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema
$graph.Nodes | Where-Object { -not $_.SchemaMatched } | Format-Table ResourceAddress, ProviderAddress, Reason
```

Only the top level of each resource block is checked against the schema. Unmatched nodes carry `Reason` `NoSchemaGraph`, `ProviderNotInSchemaGraph` or `TypeNotInProvider`.
