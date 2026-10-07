---
name: terraformgraph
description: Load when working with Terraform code or provider schemas in PowerShell using the TerraformGraph module (parse .tf files, graph module calls, variables, provider schemas and resources).
---

# TerraformGraph

PowerShell 7.4+ module that parses Terraform `.tf` files into an HCL AST (HashiCorp HCL v2, through a native DLL) and builds graphs of module calls, variables, provider schemas and resources on top of it. The parser DLL is a Windows x64 build: elsewhere the module still imports and every command except `Get-TerraformAST` and `Get-TerraformModuleGraph` (which throw `ParserUnavailable`) works.

## Import

```powershell
Import-Module TerraformGraph                                  # installed copy
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force # from a clone of the repo
```

Fresh-process rule: the parser DLL is loaded with P/Invoke and stays pinned for the life of the process. After the DLL is rebuilt, an open shell keeps running the old parser, so run tests in a new process:

```powershell
pwsh -NoProfile -File .\tests\Invoke-Tests.ps1         # default run, no network (-Live: registry tests; never during a harvest)
```

## Functions, in pipeline order

<!-- generated:functions (Invoke-Build GenerateDocTables) -->
- `Get-TerraformAST` — Parses Terraform .tf files into an HCL abstract syntax tree. Directory (default): `-Path [-Recurse]`; File: `-FilePath`. Output: `TerraformGraph.Block`.
- `Get-TerraformModuleGraph` — Builds a graph of module calls for a Terraform root module. `[-Path] [-Recurse] [-GroupBy]`. Output: `TerraformGraph.ModuleGraph`, `TerraformGraph.ModuleNode`, `TerraformGraph.ModuleEdge`.
- `ConvertTo-TerraformVariableGraph` — Builds a graph of variables, locals and outputs across a module tree. `-ModuleGraph`. Output: `TerraformGraph.VariableGraph`, `TerraformGraph.VariableNode`, `TerraformGraph.VariableEdge`.
- `Get-TerraformVariableTrace` — Follows a variable, local or output through a variable graph. `-VariableGraph -Id [-Direction] [-MaxDepth]`. Output: `TerraformGraph.VariableTrace`, `TerraformGraph.VariableTraceNode`, `TerraformGraph.VariableEdge`.
- `Update-TerraformRegistryCache` — Downloads the list of Terraform providers and their versions into the registry cache. `[-Scope] [-Path] [-ThrottleLimit] [-PassThru]`. Output: `TerraformGraph.RegistryCache`.
- `Get-TerraformRegistryProvider` — Lists Terraform providers and their versions from the registry cache. `[-Name] [-Tier] [-NoBundledData]`. Output: `TerraformGraph.RegistryProvider`.
- `Get-TerraformProviderSchema` — Runs `terraform providers schema -json` and returns the result. Directory (default): `[-Path] [-OutputFormat]`; Provider: `-Provider [-Version] [-WorkingDirectory] [-Cleanup] [-Force] [-NoBundledData] [-SaveToCache] [-OutputFormat]`. Output: `System.Collections.Specialized.OrderedDictionary`, `System.String`.
- `Get-TerraformSchemaPack` — Downloads provider schema packs into the local schema cache. `[-Provider] [-Version] [-Source] [-Force] [-PassThru]`. Output: `TerraformGraph.SchemaPack`.
- `Get-TerraformSchemaCache` — Lists the provider schemas in the local schema cache. `[-Provider]`. Output: `TerraformGraph.CachedSchema`.
- `Update-TerraformProviderDocCache` — Harvests provider documentation from the public registry into the docs cache, for named providers or a whole bundle. Provider (default): `-Provider [-Version] [-ThrottleLimit] [-Resume] [-Force] [-PassThru]`; Bundle: `-BundlePath [-ThrottleLimit] [-Resume]`. Output: `TerraformGraph.DocCache`, `TerraformGraph.DocHarvestSummary`.
- `Get-TerraformDocPack` — Downloads provider docs packs into the local docs cache. `[-Provider] [-Version] [-Source] [-Force] [-PassThru]`. Output: `TerraformGraph.DocPack`.
- `Get-TerraformDocCache` — Lists the provider docs in the local docs cache. `[-Provider]`. Output: `TerraformGraph.CachedDoc`.
- `Get-TerraformProviderDoc` — Gets provider documentation pages from the docs cache, by provider, Id, type or pipeline node. Provider (default): `[-Provider] [-Version] [-Id] [-Type] [-Category] [-Examples]`; InputObject: `[-Version] [-Id] [-Type] [-Category] [-Examples] -InputObject`. Output: `TerraformGraph.ProviderDoc`.
- `ConvertTo-TerraformSchemaGraph` — Converts a provider schema into a graph of canonical schema nodes. Cache (default): `-Provider [-Version] [-IncludeFunctions] [-Classify] [-ClassifierPath]`; Document: `-Schema [-Provider] [-IncludeFunctions] [-Classify] [-ClassifierPath]`. Output: `TerraformGraph.SchemaGraph`, `TerraformGraph.DrawerSummary`, `TerraformGraph.SchemaNode`, `TerraformGraph.SchemaEdge`.
- `ConvertTo-TerraformResourceGraph` — Builds an inventory of resources and data sources and joins it to provider schemas. SchemaGraph (default): `-ModuleGraph [-SchemaGraph] [-Classify] [-ClassifierPath]`; Provider: `-ModuleGraph -Provider [-Classify] [-ClassifierPath]`; AutoSchema: `-ModuleGraph -AutoSchema [-Classify] [-ClassifierPath]`. Output: `TerraformGraph.ResourceGraph`, `TerraformGraph.DrawerSummary`, `TerraformGraph.ResourceNode`, `TerraformGraph.ResourceEdge`.
- `New-TerraformClassifier` — Writes a provider version's classifier: every resource and data source type with its subcategory and drawer. `-Provider [-Version] [-MapPath] [-OutputPath] [-PassThru]`. Output: `TerraformGraph.ClassifierBuild`.
- `Get-TerraformClassifier` — Gets provider classifiers: each resource and data source type with its subcategory and drawer. `[-Provider] [-Version] [-ClassifierPath] [-Shadowed]`. Output: `TerraformGraph.Classifier`, `TerraformGraph.ClassifiedType`, `TerraformGraph.ClassifierFinding`, `TerraformGraph.ClassifierShadow`.
- `Get-TerraformClassifierFinding` — Gets the types a classifier could not place in a drawer, and why. `[-Provider] [-Version] [-ClassifierPath]`. Output: `TerraformGraph.ClassifierFinding`.
- `Get-TerraformGraphBundle` — Gets the bundle manifest: the provider set the bundled data covers and what was harvested for each provider. Entries (default): `[-Path]`; Document: `[-Path] -Document`; Sources: `[-Path] -Sources`. Output: `TerraformGraph.BundleEntry`, `TerraformGraph.Bundle`, `TerraformGraph.BundleSource`.
- `New-TerraformGraphBundle` — Writes a bundle manifest for a provider set, resolved against the registry cache. `[-Tier] [-Provider] [-Exclude] [-OutputPath] [-PassThru]`. Output: `TerraformGraph.Bundle`.
- `Test-TerraformGraphBundle` — Checks the bundle manifest and the bundled data against their sources: Fresh, Stale or Missing per item. `[-BundlePath] [-DistPath] [-Scope] [-Online] [-Strict]`. Output: `TerraformGraph.BundleCheck`.
- `Get-TerraformSubcategorySurvey` — Counts the doc subcategory labels each provider publishes: one row per provider and label. Bundle (default): `[-BundlePath] [-OutputPath] [-PassThru]`; Provider: `-Provider [-Version] [-OutputPath] [-PassThru]`. Output: `TerraformGraph.SubcategorySurveyRow`.
- `ConvertTo-TerraformJson` — Converts objects to indented JSON using System.Text.Json. `-InputObject [-Depth] [-Compress] [-AsArray]`. Output: `System.String`.
- `ConvertFrom-TerraformJson` — Converts JSON to PowerShell objects using System.Text.Json. `-InputObject [-Depth] [-AsHashtable] [-NoEnumerate]`. Output: `System.Management.Automation.PSCustomObject`, `System.Collections.Specialized.OrderedDictionary`.
- `Install-TerraformGraphSkill` — Copies the TerraformGraph agent skill into a repository for one or more agent tools. `[-Path] [-Tool] [-Force] [-PassThru]`. Output: `TerraformGraph.SkillInstall`.
- `Test-TerraformGraphSkill` — Reports which agent tools a repository uses and whether the TerraformGraph skill is installed for them. `[-Path] [-Tool]`. Output: `TerraformGraph.SkillStatus`.
<!-- /generated:functions -->

Each line is the command's synopsis, its parameter sets (`[-Name]` is optional) and its output types; `Get-Help <command> -Full` has the rest. Behaviour worth knowing before you call them:

- `Get-TerraformModuleGraph` never runs `terraform init`; non-local module sources come from `.terraform/modules/modules.json`. `ConvertTo-TerraformVariableGraph` and `ConvertTo-TerraformResourceGraph` never reparse.
- `Get-TerraformProviderSchema` needs `terraform` on PATH, and `-Provider` needs the registry. Every `Get-*` cache and pack reader works offline; `Get-TerraformSchemaPack` and `Get-TerraformDocPack` are the only commands that download packs.
- `Update-TerraformRegistryCache`, `Update-TerraformProviderDocCache` and `Test-TerraformGraphBundle -Online` share one registry rate state per session. The registry rate-limits sustained runs for minutes: the first 429 stops every worker, waits 30 s then 60, 120, 240, 300 s, and resumes at one worker, climbing one per 25 successes. An interrupted docs harvest keeps its pages in `docs\<address-slug>\<version>.partial.json`; rerun the same command with `-Resume` to continue (`-Force` starts over). Never run the Live tests while a harvest is going: they share the rate budget.
- `Test-TerraformGraphBundle -Scope Repo` certifies the checkout (the bundle's folder, bundled classifiers and `dist/schema-packs`) and reads no user cache; `-Scope Machine` (default) also checks this machine's caches. Every non-Fresh row carries a pasteable RecommendedAction (promotes it) and InspectAction (shows the change first, never writing to the module's `src`).
- The HCL parser ships for Windows x64 only. Elsewhere the module still imports; `Get-TerraformAST` and `Get-TerraformModuleGraph` throw `ParserUnavailable`.

Use `ConvertTo-TerraformJson` / `ConvertFrom-TerraformJson` instead of the built-in cmdlets for provider schemas: `ConvertTo-Json` silently truncates past depth 100.

## Provider names and wildcards

Name patterns match by shape: `aws` or `aws*` matches the bare name in any namespace, `hashicorp/aws*` matches namespace/name, and `registry.terraform.io/hashicorp/aws` matches the full address. `Get-TerraformProviderSchema -Provider` with a wildcard resolves against the registry cache and must match exactly one provider; otherwise it stops before running terraform, with every match listed (`'aws*' matches 4 providers: hashicorp/aws, hashicorp/awscc, ... Specify one; Get-TerraformRegistryProvider -Name 'aws*' lists them.`). A `-Provider` without a wildcard needs no cache. Tab completion of `-Provider`, `-Version` and `Get-TerraformRegistryProvider -Name` reads the cache only.

## Schema cache

Provider schemas are not bundled. They live in `$env:LOCALAPPDATA\TerraformGraph\schemas\<address-slug>\<version>.json.gz`, where address-slug is the lowercase provider address with `/` → `-` (`registry.terraform.io-hashicorp-azurerm\5.8.0.json.gz`). Fill it with `Get-TerraformSchemaPack` (release packs, no terraform needed) or `Get-TerraformProviderSchema -Provider <p> -SaveToCache` (any provider and version, needs terraform and the registry). Then `ConvertTo-TerraformSchemaGraph -Provider <p>` and `ConvertTo-TerraformResourceGraph -Provider <p>` or `-AutoSchema` work offline. A provider that is not cached is a terminating error naming both fill commands. With `-AutoSchema`, providers that are not cached are marked `ProviderNotInSchemaGraph`. Check with `Get-TerraformSchemaCache` before assuming a schema is there.

Rule: never download inside a completer or `-AutoSchema`. Both read local caches only. `Get-TerraformSchemaPack` and `Get-TerraformDocPack` are the only commands that fetch packs, and only when called explicitly. The default source is this public repository's latest release, which needs no token. For a private fork's release, set `$env:GH_TOKEN` (or `$env:GITHUB_TOKEN`) and they go through the GitHub API with it; without a token a 404 names GH_TOKEN for a private fork.

## Provider docs

Registry markdown pages live in `$env:LOCALAPPDATA\TerraformGraph\docs\<address-slug>\<version>.json.gz`, keyed on schema node Ids: overview `<address>`, guide `<address>/guide/<slug>`, resource `<address>/resource/<type>`, data source `<address>/data/<type>`. A page whose type is not in the cached schema keeps `<address>/unmatched/<category>/<slug>` and counts in `UnmatchedCount`. That is a finding about the provider docs, not an error. Fill with `Get-TerraformDocPack` (release packs) or `Update-TerraformProviderDocCache` (registry; cache the schema first so Ids are checked). Check with `Get-TerraformDocCache`. `Get-TerraformProviderDoc -Provider <p>` for something not cached is a terminating error naming both fill commands; in the pipeline, an uncached provider gets one warning and built-in providers are skipped. Read the page's `Content` (markdown), or use `-Examples` for only the ```hcl / ```terraform blocks.

## Classifiers

Classifier drawers group resource and data source types into drawers (network, compute, storage, ..., unclassified) so a view can collapse. They are opinions layered on facts. They never change a node's Id, the node count or the edges, and they ship as data with provenance in the module's `classifiers/` folder:

- `drawers.json` is the fixed drawer list.
- `map.json` has rows `{ provider (address or "*"), source, subcategory, drawer, reason, addedOn, addedBy }`. `source` is `subcategory` (default: `subcategory` is the provider's doc label; a provider row beats a `*` row) or `prefix` (provider address only; `subcategory` holds the type prefix after the provider token, e.g. `git` matches `azuredevops_git` and `azuredevops_git_*` but not `azuredevops_github_*`; longest prefix wins). Prefix rows place only types with no label, which is how azuredevops, a provider that publishes no labels, gets drawers. Each classified type records the `source` of the row that placed it.
- `DECISIONS.md` is the append-only record of every judgement.
- `<address-slug>.<version>.json` is one classifier per provider version.

The default classifier comes from the provider's own doc `subcategory` labels (type-name prefixes only where a provider has no labels), not from hand-sorting. A type with no doc page, an empty subcategory or an unmapped subcategory is in `unclassified` and is listed as a finding. That is a legitimate drawer, not an error. Lookup order is `-ClassifierPath`, then `$env:LOCALAPPDATA\TerraformGraph\classifiers`, then the bundled folder.

```powershell
$graph = Get-TerraformModuleGraph -Path . -Recurse | ConvertTo-TerraformResourceGraph -AutoSchema -Classify
$graph.Drawers                                   # Drawer, TypeCount, InstanceCount
Get-TerraformClassifierFinding -Provider azurerm # what the map could not place
```

Rules when asked to classify, or to touch anything under `classifiers/`:

1. Read `classifiers/DECISIONS.md` first. Do not reopen a call recorded there without appending an entry that supersedes it.
2. Append a numbered entry (Question / Call / Rejected / Why / Cost if wrong) for every judgement you make, including every subcategory you leave unmapped. Never edit an earlier entry.
3. Never add or change a `map.json` row without a non-empty `reason`. Cite the DECISIONS entry in the reason when the call is arguable. Never target `unclassified`: leave the row out and record why. The Pester lint and `New-TerraformClassifier` both reject a row with an empty reason.
4. After changing `map.json`, rerun `Invoke-Build BuildClassifier` and stage the regenerated classifiers. A Pester test fails when a bundled classifier's `mapVersion` no longer matches the map, and `New-TerraformClassifier` throws when a prefix row matches no type in the provider's cached schema.
5. Before proposing a new drawer or label row, read the survey: `Get-TerraformSubcategorySurvey -OutputPath .\dist\survey` (after `Update-TerraformProviderDocCache -BundlePath ... -Resume`) and count how many providers use the label.
6. Adding a drawer is a minor release; renaming or removing one is major (DECISIONS 47, and the Pester test "drawers are semver-safe").
7. When the same provider version has a classifier in more than one folder, `-ClassifierPath` wins, else the one built from the current map.json, else the newer one; the others are named in a warning. `Get-TerraformClassifier -Shadowed` lists them.

## Promote or leave

Harvests and `New-*` commands write to the user caches under `$env:LOCALAPPDATA\TerraformGraph` (development). The module's `src/` folder is production. When `Test-TerraformGraphBundle` returns a Stale or Missing row:

1. Run the row's `InspectAction` and put its output (the diff, or the cache state) in your report.
2. Run the row's `RecommendedAction` only if the task you were given is about that data. Otherwise report the row and leave it.
3. Nothing moves into `src/` except through an `Invoke-Build` task, and you commit nothing.
4. Give the human both commands in your report, pasteable, so they can make the call.

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
$graph = Get-TerraformProviderSchema -Path .\infra | ConvertTo-TerraformSchemaGraph -Provider null   # infra declares null and local; terraform init it first
$graph.Nodes | Where-Object Path -like 'null_resource.*'
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
