# Changelog

Graph.Emitter.Terraform (formerly TerraformGraph) release notes, newest first. The psd1 `ReleaseNotes` holds only the current version and links here.

## 0.17.0

Renamed from TerraformGraph; module and manifest follow the repo name; no functional change. The repository is now https://github.com/JerryBalmer1/Graph.Emitter.Terraform and the module `Graph.Emitter.Terraform`: the same 26 commands with the same parameters, parameter sets, output types and error ids; messages and help that named the module now say Graph.Emitter.Terraform.

- The module folder is `src/Graph.Emitter.Terraform` and its files are `Graph.Emitter.Terraform.psd1`, `Graph.Emitter.Terraform.psm1` and `Graph.Emitter.Terraform.Format.ps1xml`; `Import-Module Graph.Emitter.Terraform`, `Install-Module Graph.Emitter.Terraform` (once published), `InModuleScope Graph.Emitter.Terraform`. `Invoke-Build AssembleModule` writes `dist/module/Graph.Emitter.Terraform` and `Package` writes `dist/Graph.Emitter.Terraform.<version>.zip`. The test file is `tests/Graph.Emitter.Terraform.Tests.ps1`.
- Kept on purpose: function names (`Install-TerraformGraphSkill`, `New-TerraformGraphBundle` and the rest), PSTypeNames (`TerraformGraph.*`), the C# and Go names (`TerraformGraph.Json`, `TerraformGraph.Utf8Parser`, `TerraformGraph.dll`), `TERRAFORMGRAPH_*` variables, error ids, the skill `terraformgraph`, the Docker image and container names, and the cache, log and temp folders (`$env:LOCALAPPDATA\TerraformGraph`, `$env:TEMP\TerraformGraph`), so existing caches keep working.
- URLs point at the renamed repository: the default schema and docs pack `-Source`, the psd1 ProjectUri and LicenseUri, and the bundle sources (`$script:TerraformGraphBundleSources`, `data/bundle.json`).
- Pester "drawers are semver-safe" reads the previous release's drawers.json from `src/Graph.Emitter.Terraform`, else from `src/TerraformGraph` (tags before 0.17.0).
- Planned features move one release: view 0.18.0, compare 0.19.0, eras 0.20.0.

## 0.16.0

The module graph contract: every module node and edge carries its Kind, Ids are unique under both `-GroupBy` modes, and edges record their file. A contract change for `-GroupBy Source` Ids.

- `TerraformGraph.ModuleNode` properties are now `Id`, `Kind` (always `Module`), `Name`, `Key`, `ModuleAddress`, `Source`, `SourceKind`, `Dir`, `Resolved`, `Reason`, `ParentKey`, `Depth`, `Block`, `Blocks`, `Callers`. `SourceKind` is unchanged and is not the discriminator.
- `TerraformGraph.ModuleEdge` properties are now `From`, `To`, `Kind` (always `Calls`), `Call`, `Label`, `File` (the module block's bare file name, as on `ResourceNode`), `Line`.
- Both have table views led by `Id`, `Kind` and `From`, `To`, `Kind` (TerraformGraph.Format.ps1xml).
- `-GroupBy Source` (breaking): one node per module source, Id `source:<normalised source>`, with `Callers` listing the ModuleAddress of every call it stands for. A local source is normalised to its directory relative to the root module, a registry source is lowercased without a `registry.terraform.io/` host. A non-literal source is `source:<ModuleAddress>`, Resolved `$false`. Edges stay one per call. Before, two calls to one source were two nodes sharing an Id, and the Id was the bare source string. `-GroupBy Call` Ids are unchanged. Build resource and variable graphs from a Call graph (DECISIONS 53).
- `TerraformGraph.ModuleGraph` gains `Findings`, the same list as `Unresolved`, under the name `ResourceGraph` uses. `ResourceGraph.Findings` is still a count.
- docs/graph-shape.md holds the property tables and the Id rules per `-GroupBy` mode. CLAUDE.md states the graph contract: every node has `Id` first and `Kind` second, every edge `From`, `To`, `Kind` in that order (the schema, resource and variable graphs already did).
- Planned features move one release: view 0.17.0, compare 0.18.0, eras 0.19.0.

## 0.15.0

The module source split one function per file. No behaviour change: the same 26 commands with the same parameters, parameter sets, aliases, output, error ids and messages.

- `src/TerraformGraph/TerraformGraph.psm1` (7,955 lines) is wiring only (464 lines): module-scope state, the parser DLL and Json.dll loads, type data, argument completers, then the dot-source of `Private/` (82 files, one helper each) and `Public/` (26 files, one exported command each). `Classes/` is reserved; there are no classes or enums. To change a function, edit the file named for it.
- The psm1 calls `Export-ModuleMember` with the psd1 `FunctionsToExport` list. Importing the psd1 is unchanged; importing the psm1 directly now exports those 26 commands instead of every function.
- `Invoke-Build AssembleModule` builds the shipped psm1 by splicing the files into the wiring, so the published module is still one psm1 and the psd1 `FileList` is unchanged.
- Proof (dist/split-proof, not committed): before the split and after it, from `src/` and from the assembled `dist/`, the exported commands, their parameters, parameter sets and aliases, the psd1 export list, the AssembleModule file list, the default test run, every module-scope variable name and a hash of every function body (108) match. The only differences are the shipped psm1's size and the six new tests.
- Tests: the error-id contract and the ONTOLOGY.md terminology test read every source file, and a `RequiresBuild` twin of each reads the assembled psm1. New tests hold the layout: one function per file, named for it; Private functions are not exported; `FunctionsToExport` equals `Public/`; no function is defined twice; the psm1 defines none. `$env:TERRAFORMGRAPH_TEST_MANIFEST` runs the suite against another copy of the module.
- Planned features move one release: view 0.16.0, compare 0.17.0, eras 0.18.0.

## 0.14.1

Day-one fixes from the 0.14.0 audit. No new features.

- Non-ASCII HCL round-trips: the parser is called with UTF-8 marshalling both ways (it used the Windows code page, which mangled `café – 東京` and could not open a path such as `enc-日本`).
- The module imports on any platform. Off Windows x64, or when the DLL was never built, `Get-TerraformAST` and `Get-TerraformModuleGraph` throw `ParserUnavailable`; every schema, registry, docs, classifier and bundle command works without the parser.
- Licensed under the Apache License 2.0 (LICENSE, NOTICE).
- Every terminating error goes through one private helper with a documented id and a message that names its fix. The eight bare throws are gone: `TerraformNotOnPath`, `TerraformInitFailed`, `TerraformVersionUnreadable`, `TerraformProvidersSchemaFailed`, `ProviderAddressInvalid`, `ProviderVersionInvalid`, `RegistryRequestFailed`, `PackAssetNotFound` and `ParserUnavailable` are new ids. A missing bundle is `BundleNotFound` and a missing registry cache `RegistryCacheNotFound` everywhere. The sixth-429 message no longer recommends a `-Resume` that `Update-TerraformRegistryCache` does not have.
- A `required_providers` source that is not a provider address, and a classifier map that does not read, are warnings instead of silent fallbacks.
- `Test-TerraformGraphBundle -Scope Repo|Machine` (default Machine). Repo reads only the bundle's folder, the bundled classifiers and `dist/schema-packs`, never a user cache; `Invoke-Build CheckBundle` uses it. A Missing docs row names `Get-TerraformDocPack` only when a docs pack exists.
- `Get-TerraformGraphBundle -Document` gains `PackedEntryCount`, `ClassifiedEntryCount` and `RegistryOnlyEntryCount`.
- Tests: `Live` and `RequiresTerraform` tags replace the ICMP ping; `tests/Invoke-Tests.ps1` (`-Live`, `-All`).
- Build: `AssembleModule` (dist/module/TerraformGraph, the psd1 FileList), `BuildJson` (precompiled `TerraformGraph.Json.dll`), `GenerateDocTables`; `Release` and `Publish` run on main, tag `v<version>` and publish the assembled tree with `Publish-PSResource`. The Dockerfile builds with `golang:1.24` as go.mod asks.

## 0.14.0

Hardening and contracts. One registry rate state per session: the first 429 stops every worker, waits 30/60/120/240/300 s (Retry-After honoured, 600 s cap), resumes at one worker and climbs one per 25 successes; docs harvests checkpoint to `<version>.partial.json` and `-Resume` continues them; DocHarvestSummary gains RateLimitHits, SecondsBlocked, PartialResumes and LogPath (`harvest-<timestamp>.log`); bundle.json names its sources (`Get-TerraformGraphBundle -Sources`); every non-Fresh Test-TerraformGraphBundle row carries RecommendedAction and InspectAction; every terminating error names its fix; classifier precedence for the same provider version (mapVersion, then generatedOn) with `Get-TerraformClassifier -Shadowed`; drawers semver gate.

## 0.13.0

Bundle and survey: data/bundle.json names the shipped provider set (official tier plus microsoft/azuredevops and vmware/vsphere) with per-provider versions; Get-TerraformGraphBundle, New-TerraformGraphBundle, Test-TerraformGraphBundle (Fresh/Stale/Missing, -Strict, -Online); Update-TerraformProviderDocCache -BundlePath and -Resume with a DocHarvestSummary; Get-TerraformSubcategorySurvey; registry 429s retried for minutes; integration drawer (21 drawers) graded against the survey; map.json prefix rows place types of providers with no labels (azuredevops: 177 of 177 classified); Invoke-Build HarvestBundleDocs and CheckBundle; README and ONTOLOGY.md.

## 0.12.0

Classifier drawers: an optional overlay grouping resource and data source types into drawers (network, compute, storage, ..., unclassified) from the providers own doc subcategories through a reasoned map; New-TerraformClassifier, Get-TerraformClassifier, Get-TerraformClassifierFinding; -Classify and -ClassifierPath on ConvertTo-TerraformSchemaGraph and ConvertTo-TerraformResourceGraph (Drawer, Subcategory, Drawers summary; same Ids, nodes and edges); bundled classifiers for azurerm 5.8.0, azuredevops 1.16.0 and vsphere 2.17.1 with drawers.json, map.json and DECISIONS.md.

## 0.11.0

Provider docs sidecar: Update-TerraformProviderDocCache, Get-TerraformProviderDoc (by provider, Id, type, category, -Examples, or piped SchemaNode/ResourceNode), Get-TerraformDocPack, Get-TerraformDocCache; docs keyed on schema node Ids; manifest.json entries carry kind schema|docs; pack downloads from private GitHub releases with GH_TOKEN.

## 0.10.0

Schema packs and a local provider schema cache: Get-TerraformSchemaPack, Get-TerraformSchemaCache, Get-TerraformProviderSchema -SaveToCache, ConvertTo-TerraformSchemaGraph -Provider/-Version from the cache, ConvertTo-TerraformResourceGraph -Provider and -AutoSchema.

## 0.9.0

Provider registry cache: Update-TerraformRegistryCache, Get-TerraformRegistryProvider, bundled data/registry.json, wildcard -Provider and argument completers for Get-TerraformProviderSchema.

## 0.8.0

Ship the terraformgraph agent skill; add Install-TerraformGraphSkill and Test-TerraformGraphSkill; import hint for detected agent tools.

## 0.7.0

Add ConvertTo-TerraformResourceGraph.

## 0.6.0

Add ConvertTo-TerraformVariableGraph and Get-TerraformVariableTrace.

## 0.5.1

Provider config nodes in ConvertTo-TerraformSchemaGraph; performance.

## 0.5.0

Add ConvertTo-TerraformSchemaGraph.

## 0.4.0

Get-TerraformProviderSchema -Provider set fetches a provider schema on demand.

## 0.3.0

Add Get-TerraformModuleGraph.

## 0.2.0

Breaking. Expression nodes now carry Kind, Raw and values.

## 0.1.0

Initial release. Get-TerraformAST, ConvertTo-TerraformJson, ConvertFrom-TerraformJson, Get-TerraformProviderSchema.
