# TerraformGraph

PowerShell module that parses Terraform `.tf` files into an HCL AST via a Go `c-shared` DLL (`hashicorp/hcl/v2`) and builds graphs of module calls and provider schemas on top of it.

Requires PowerShell 7.4+ and Pester 6.1.0+. Terraform CLI for the RequiresTerraform tests (skipped without it), a running Docker engine to build the DLL, and a .NET 8+ SDK to build `TerraformGraph.Json.dll` (BuildJson; without it the module compiles `TerraformGraph.Json.cs` at import). Licensed under Apache 2.0 (LICENSE, NOTICE); release history in CHANGELOG.md.

The HCL parser DLL is Windows x64 only. The module imports anywhere: off Windows x64 (or with no DLL built) `$script:TerraformGraphParserAvailable` is `$false` and `Get-TerraformAST` and `Get-TerraformModuleGraph` throw `ParserUnavailable` (private `Assert-TerraformGraphParser`); everything else works. The P/Invoke marshals UTF-8 both ways (`LPUTF8Str`, `PtrToStringUTF8`; type `TerraformGraph.Utf8Parser`).

## Layout

```
src/go/                 Go parser (hcl_parser.go) — buildmode=c-shared
src/TerraformGraph/       PowerShell module root
  TerraformGraph.psd1
  TerraformGraph.psm1     P/Invoke + ConvertFrom-TerraformHclFile + exported functions
  TerraformGraph.Json.cs  System.Text.Json serializer/deserializer (TerraformGraph.Json)
  TerraformGraph.Format.ps1xml  Table views for BundleEntry and SubcategorySurveyRow (more than four default columns)
  lib/                  Build outputs, gitignored: TerraformGraph.dll and TerraformGraph.h (BuildDLL), TerraformGraph.Json.dll (BuildJson)
  skills/terraformgraph/SKILL.md  Canonical agent skill (shipped with the module)
  data/registry.json    Bundled provider registry cache (Invoke-Build BuildRegistry; shipped)
  data/bundle.json      Bundle manifest: provider set and per-provider versions (Invoke-Build HarvestBundleDocs; shipped)
  classifiers/          drawers.json, map.json, DECISIONS.md and <address-slug>.<version>.json classifiers (Invoke-Build BuildClassifier; committed and shipped)
src/json/               TerraformGraph.Json.csproj (net8.0) and nuget.config for BuildJson
tools/                  Copy-TerraformGraphModule.ps1 (the shipped file set; AssembleModule, Pester) and Update-TerraformGraphDocTables.ps1 (GenerateDocTables, Pester -Check)
dist/schema-packs/      Schema and docs packs from Invoke-Build BuildSchemaPack (gitignored; attached to GitHub releases)
dist/survey/            subcategories.json from Invoke-Build HarvestBundleDocs (gitignored)
dist/module/            The publishable module tree from Invoke-Build AssembleModule (gitignored)
LICENSE, NOTICE         Apache License 2.0; shipped in the module tree
CHANGELOG.md            Full release history (the psd1 ReleaseNotes holds the current version only)
README.md               Sysadmin door; line 1 is the only ontology mention (repo skill readme)
ONTOLOGY.md             Agent/ontology door; banner, then backlink to README (repo skill ontology-doc)
.claude/skills/terraformgraph/  Generated copy of the skill (Install-TerraformGraphSkill)
.claude/skills/readme, ontology-doc, manual-check-list  Repo-development skills (not shipped)
AGENTS.md               Generated pointer section (Install-TerraformGraphSkill) plus a hand-kept Repository skills section
infra/                  Fixture modules used by tests and README examples
tests/                  Pester 6.1+ (*.Tests.ps1) run by Invoke-Tests.ps1; fixtures/hcl holds the UTF-8 fixture and the enc-日本 folder; fixtures/schemas holds real null 3.2.3 and local 2.5.2 schemas, fixtures/docs their harvested docs, fixtures/classifiers a map, a bad map, a prefix map, subcategories applied to those docs, an override classifier, and drawers.0.13.0.json (the semver gate's fallback when git is unavailable)
Dockerfile              Cross-compile the Windows DLL with mingw (golang:1.24, as go.mod); .dockerignore keeps the context to src/go
.build.ps1              InvokeBuild: CheckDependencies, CheckTestDependencies, BuildDLL, BuildJson, RemoveModule, ImportModule, Test (default), GenerateDocTables, AssembleModule, BuildRegistry, BuildSchemaPack, BuildClassifier, HarvestBundleDocs, CheckBundle, Package, Release, Publish
```

Module name is **TerraformGraph**. Do not reintroduce `PS.Util.Terraform`.

Exported functions (generated from Get-Command and comment-based help by Invoke-Build GenerateDocTables; edit the help, not this list):

<!-- generated:functions (Invoke-Build GenerateDocTables) -->
- `Get-TerraformAST` — Parses Terraform .tf files into an HCL abstract syntax tree. Directory (default): `-Path [-Recurse]`; File: `-FilePath`. Output: `TerraformGraph.Block`.
- `ConvertTo-TerraformJson` — Converts objects to indented JSON using System.Text.Json. `-InputObject [-Depth] [-Compress] [-AsArray]`. Output: `System.String`.
- `ConvertFrom-TerraformJson` — Converts JSON to PowerShell objects using System.Text.Json. `-InputObject [-Depth] [-AsHashtable] [-NoEnumerate]`. Output: `System.Management.Automation.PSCustomObject`, `System.Collections.Specialized.OrderedDictionary`.
- `Get-TerraformProviderSchema` — Runs `terraform providers schema -json` and returns the result. Directory (default): `[-Path] [-OutputFormat]`; Provider: `-Provider [-Version] [-WorkingDirectory] [-Cleanup] [-Force] [-NoBundledData] [-SaveToCache] [-OutputFormat]`. Output: `System.Collections.Specialized.OrderedDictionary`, `System.String`.
- `Get-TerraformModuleGraph` — Builds a graph of module calls for a Terraform root module. `[-Path] [-Recurse] [-GroupBy]`. Output: `TerraformGraph.ModuleGraph`, `TerraformGraph.ModuleNode`, `TerraformGraph.ModuleEdge`.
- `ConvertTo-TerraformSchemaGraph` — Converts a provider schema into a graph of canonical schema nodes. Cache (default): `-Provider [-Version] [-IncludeFunctions] [-Classify] [-ClassifierPath]`; Document: `-Schema [-Provider] [-IncludeFunctions] [-Classify] [-ClassifierPath]`. Output: `TerraformGraph.SchemaGraph`, `TerraformGraph.DrawerSummary`, `TerraformGraph.SchemaNode`, `TerraformGraph.SchemaEdge`.
- `ConvertTo-TerraformVariableGraph` — Builds a graph of variables, locals and outputs across a module tree. `-ModuleGraph`. Output: `TerraformGraph.VariableGraph`, `TerraformGraph.VariableNode`, `TerraformGraph.VariableEdge`.
- `Get-TerraformVariableTrace` — Follows a variable, local or output through a variable graph. `-VariableGraph -Id [-Direction] [-MaxDepth]`. Output: `TerraformGraph.VariableTrace`, `TerraformGraph.VariableTraceNode`, `TerraformGraph.VariableEdge`.
- `ConvertTo-TerraformResourceGraph` — Builds an inventory of resources and data sources and joins it to provider schemas. SchemaGraph (default): `-ModuleGraph [-SchemaGraph] [-Classify] [-ClassifierPath]`; Provider: `-ModuleGraph -Provider [-Classify] [-ClassifierPath]`; AutoSchema: `-ModuleGraph -AutoSchema [-Classify] [-ClassifierPath]`. Output: `TerraformGraph.ResourceGraph`, `TerraformGraph.DrawerSummary`, `TerraformGraph.ResourceNode`, `TerraformGraph.ResourceEdge`.
- `Install-TerraformGraphSkill` — Copies the TerraformGraph agent skill into a repository for one or more agent tools. `[-Path] [-Tool] [-Force] [-PassThru]`. Output: `TerraformGraph.SkillInstall`.
- `Test-TerraformGraphSkill` — Reports which agent tools a repository uses and whether the TerraformGraph skill is installed for them. `[-Path] [-Tool]`. Output: `TerraformGraph.SkillStatus`.
- `Update-TerraformRegistryCache` — Downloads the list of Terraform providers and their versions into the registry cache. `[-Scope] [-Path] [-ThrottleLimit] [-PassThru]`. Output: `TerraformGraph.RegistryCache`.
- `Get-TerraformRegistryProvider` — Lists Terraform providers and their versions from the registry cache. `[-Name] [-Tier] [-NoBundledData]`. Output: `TerraformGraph.RegistryProvider`.
- `Get-TerraformSchemaPack` — Downloads provider schema packs into the local schema cache. `[-Provider] [-Version] [-Source] [-Force] [-PassThru]`. Output: `TerraformGraph.SchemaPack`.
- `Get-TerraformSchemaCache` — Lists the provider schemas in the local schema cache. `[-Provider]`. Output: `TerraformGraph.CachedSchema`.
- `Update-TerraformProviderDocCache` — Harvests provider documentation from the public registry into the docs cache, for named providers or a whole bundle. Provider (default): `-Provider [-Version] [-ThrottleLimit] [-Resume] [-Force] [-PassThru]`; Bundle: `-BundlePath [-ThrottleLimit] [-Resume]`. Output: `TerraformGraph.DocCache`, `TerraformGraph.DocHarvestSummary`.
- `Get-TerraformProviderDoc` — Gets provider documentation pages from the docs cache, by provider, Id, type or pipeline node. Provider (default): `[-Provider] [-Version] [-Id] [-Type] [-Category] [-Examples]`; InputObject: `[-Version] [-Id] [-Type] [-Category] [-Examples] -InputObject`. Output: `TerraformGraph.ProviderDoc`.
- `Get-TerraformDocPack` — Downloads provider docs packs into the local docs cache. `[-Provider] [-Version] [-Source] [-Force] [-PassThru]`. Output: `TerraformGraph.DocPack`.
- `Get-TerraformDocCache` — Lists the provider docs in the local docs cache. `[-Provider]`. Output: `TerraformGraph.CachedDoc`.
- `New-TerraformClassifier` — Writes a provider version's classifier: every resource and data source type with its subcategory and drawer. `-Provider [-Version] [-MapPath] [-OutputPath] [-PassThru]`. Output: `TerraformGraph.ClassifierBuild`.
- `Get-TerraformClassifier` — Gets provider classifiers: each resource and data source type with its subcategory and drawer. `[-Provider] [-Version] [-ClassifierPath] [-Shadowed]`. Output: `TerraformGraph.Classifier`, `TerraformGraph.ClassifiedType`, `TerraformGraph.ClassifierFinding`, `TerraformGraph.ClassifierShadow`.
- `Get-TerraformClassifierFinding` — Gets the types a classifier could not place in a drawer, and why. `[-Provider] [-Version] [-ClassifierPath]`. Output: `TerraformGraph.ClassifierFinding`.
- `Get-TerraformGraphBundle` — Gets the bundle manifest: the provider set the bundled data covers and what was harvested for each provider. Entries (default): `[-Path]`; Document: `[-Path] -Document`; Sources: `[-Path] -Sources`. Output: `TerraformGraph.BundleEntry`, `TerraformGraph.Bundle`, `TerraformGraph.BundleSource`.
- `New-TerraformGraphBundle` — Writes a bundle manifest for a provider set, resolved against the registry cache. `[-Tier] [-Provider] [-Exclude] [-OutputPath] [-PassThru]`. Output: `TerraformGraph.Bundle`.
- `Test-TerraformGraphBundle` — Checks the bundle manifest and the bundled data against their sources: Fresh, Stale or Missing per item. `[-BundlePath] [-DistPath] [-Scope] [-Online] [-Strict]`. Output: `TerraformGraph.BundleCheck`.
- `Get-TerraformSubcategorySurvey` — Counts the doc subcategory labels each provider publishes: one row per provider and label. Bundle (default): `[-BundlePath] [-OutputPath] [-PassThru]`; Provider: `-Provider [-Version] [-OutputPath] [-PassThru]`. Output: `TerraformGraph.SubcategorySurveyRow`.
<!-- /generated:functions -->

Planned: view (0.15.0), compare (0.16.0), eras (0.17.0, derived from compares); see ONTOLOGY.md "Not here yet".

Every terminating error goes through private `Stop-TerraformGraphCommand -Id -Message -Category -Target` (DECISIONS 50): it builds the ErrorRecord and calls the calling command's `$PSCmdlet.ThrowTerminatingError`, so the FullyQualifiedErrorId reads `<Id>,<command>`; a private helper whose caller catches and rewraps passes `-Throw` (that call cannot be caught otherwise). Messages name the command that fixes them. The ids and their fixing commands are the maintained list in Pester "names a documented fixing command for every terminating error id in the psm1", which reads the psm1 AST: a new id fails it until listed, a `throw "..."` outside a ValidateScript fails it, an ErrorRecord built or ThrowTerminatingError called anywhere but the helper fails it (`$PSCmdlet.ThrowTerminatingError($_)` passes a record on), and a user-facing literal message that names no command fails it. A missing bundle is `BundleNotFound` and a missing registry cache `RegistryCacheNotFound` in every command (`Get-TerraformGraphErrorId` lets a catch pass them on).

## Canonical ids

`ConvertTo-TerraformSchemaGraph` node Ids, where `<address>` is the provider_schemas key: Provider `<address>`; provider config Attribute/Block `<address>/config/<name>` (Path `<provider short name>.<name>`, Depth 1, emitted before resources); Resource `<address>/resource/<type>`; DataSource `<address>/data/<type>`; Function `<address>/function/<name>`; Block `<parent Id>/<block name>`; Attribute `<parent Id>/<attribute name>`. `ConvertTo-TerraformVariableGraph` node Ids, where `<module>` is the ModuleAddress (`root` for the root module): Variable `<module>/var/<name>`; Local `<module>/local/<name>`; Output `<module>/output/<name>`. `ConvertTo-TerraformResourceGraph` node Ids: Resource `<module>/resource/<type>.<name>`; DataSource `<module>/data/<type>.<name>` (one per block, no provider in the Id; `SchemaId` holds the schema graph's `<address>/resource/<type>` or `/data/<type>`). Provider docs key on the schema Id: overview `<address>`; guide `<address>/guide/<slug>`; resource `<address>/resource/<type>`; data source `<address>/data/<type>`; a resource/data page whose type is not in the cached schema `<address>/unmatched/<category>/<slug>` (counted in UnmatchedCount, a finding). Type = `<prefix>_<slug>` with the prefix the cached schema uses, else the slug itself when it already carries the prefix (vsphere). `Id` is unique per document; `Path` (`<type>.<block>.<attr>`) is display only and may collide across providers.

## Provider resolution

`ConvertTo-TerraformResourceGraph` resolves each block per module, as Terraform does: local name = type up to the first underscore, or the part before the dot of a `provider = name.alias` argument (sets `ProviderAlias`). It maps through that module's own `terraform { required_providers }` `source` via `ConvertTo-TerraformProviderAddress` (lowercased); undeclared names fall back to `terraform.io/builtin/terraform` for `terraform`, else `registry.terraform.io/hashicorp/<name>`. Child modules never inherit the parent's `required_providers`.

## Classifiers

Optional overlay grouping resource and data source types into drawers. Never changes Ids, node count or edges (Pester asserts it). `src/TerraformGraph/classifiers/` holds `drawers.json` (fixed list, `unclassified` last), `map.json` (`{ rows: [ { provider: <address>|"*", source?: subcategory|prefix, subcategory, drawer, reason, addedOn, addedBy: agent|jerry } ] }`; subcategory rows: provider row beats `*`, label matched exactly ignoring case; prefix rows (`source: "prefix"`, provider address only, `subcategory` holds the type prefix after the provider token, e.g. `git` for `azuredevops_git_*`): match at underscore boundaries, longest wins, and apply only to types with no label (no doc page or empty subcategory); a labelled type the map does not place stays `UnmappedSubcategory`; a prefix row must match a type in the provider's cached schema or New-TerraformClassifier throws `ClassifierMapInvalid`), `DECISIONS.md` (append-only numbered entries: Question / Call / Rejected / Why / Cost if wrong; never edit an earlier one) and the bundled classifiers. Classifier file: `{ provider, version, docsVersion, generatedOn, mapVersion, source: "subcategory"|"subcategory,prefix", types: [ { type, kind: resource|data-source, subcategory, drawer, source: subcategory|prefix|null } ], findings: [ { type, kind, subcategory, finding } ] }`, provider and version first so listing reads the head; `mapVersion` = first 12 hex of sha256 of the map's compact JSON. `$script:TerraformClassifierUserRoot` / `$script:TerraformClassifierBundledRoot` are repointed by tests; `$script:TerraformClassifierDrawersPath` and `$script:TerraformClassifierMapPath` are not. Before any classifier work read DECISIONS.md and append an entry for every judgement; no map row without a reason; after a map change run `Invoke-Build BuildClassifier` (same default providers as BuildSchemaPack, version from the registry cache, no network) and stage `classifiers/`. A test fails when a bundled classifier's mapVersion is stale.

Semver (DECISIONS 47): data refreshes, new map rows and added drawers are minor; renaming or removing a drawer or another class name agents filter on is major. Pester "drawers are semver-safe" compares drawers.json with the previous release (`git show v<x.y.z>:src/TerraformGraph/classifiers/drawers.json`, newest tag below the psd1 version; fixture fallback) and fails a removed or renamed drawer unless the psd1 major is higher.

## Bundle and release

`data/bundle.json` (`{ formatVersion: 1, tiers, providers, exclude, registry: { harvestedOn, providerCount }, sources: [ { kind, urls, relatedUrls, harvestedBy, lastPulled } ], entries: [ { provider, version, docsVersion, schemaVersion, classifierVersion, harvestedOn } ] }`) is the provider set the shipped data covers: official tier + microsoft/azuredevops + vmware/vsphere. A bundle resolves against the `registry.json` in its own folder, else the registry cache; entry `version` = registry-cache latest, `docsVersion` = docs cached at that version else newest, `schemaVersion` = only when the schema cache holds exactly `version`, `classifierVersion` = newest bundled classifier (never the user folder). `sources` has one entry per bundled data kind (registry, schemas, docs, classifiers, skills, cmdb reserved) from `$script:TerraformGraphBundleSources`; `lastPulled` comes from the data (registry harvestedOn, newest CachedOn of recorded schemas, newest entry harvestedOn, newest generatedOn of recorded classifiers), never the clock, so reruns stay byte-identical. `$script:TerraformGraphBundleBundledPath` / `$script:TerraformGraphBundleUserPath` are repointed by tests. `Invoke-Build HarvestBundleDocs [-Resume]` (not in the default build; network, 30–60 min) runs `Update-TerraformProviderDocCache -BundlePath` on the bundled manifest, refreshes its entries with `New-TerraformGraphBundle`, and writes `dist/survey/subcategories.json`; stage `data/bundle.json`, never `dist/`. `Get-TerraformGraphBundle -Document` reports `PackedEntryCount` (entries with a schemaVersion: BuildSchemaPack attaches a schema and a docs pack for exactly those), `ClassifiedEntryCount` and `RegistryOnlyEntryCount`; the shipped bundle indexes 36 providers, 3 with packs attached.

`Test-TerraformGraphBundle -Scope` (DECISIONS 51): `Machine` (default) checks the bundle against this machine's caches too (docs and schema rows, the user registry cache when no registry.json sits beside the bundle), so it certifies one machine. `Repo` reads only the bundle's folder (`data/registry.json` beside `data/bundle.json`), the bundled classifiers and map.json, and `-DistPath`; it emits no docs or schema rows and leaves the sources block's schemas `lastPulled` (a schema cache file time) unchecked, so its rows are the same with any user cache or none (Pester asserts it). `Invoke-Build CheckBundle [-Online]` is `Test-TerraformGraphBundle -Scope Repo -Strict`, the release gate. A Missing docs row names `Get-TerraformDocPack` only when `-DistPath`'s manifest has a docs pack for that version.

Promote or leave: harvests and `New-*` commands write to the user caches (development); `src/` is production. When Test-TerraformGraphBundle returns Stale or Missing, an agent runs the row's InspectAction and puts the diff in its report, and runs the RecommendedAction only if its task is about that data; otherwise it reports the row and leaves it. Nothing moves into `src/` except through an Invoke-Build task, and an agent commits nothing. The report gives the human both commands, pasteable.

Release block, in order: `Invoke-Build BuildRegistry`; `Invoke-Build BuildSchemaPack`; `Invoke-Build BuildClassifier`; `Invoke-Build HarvestBundleDocs`; `Invoke-Build CheckBundle` (must pass); stage `data/`, `classifiers/`; raise ModuleVersion and add the CHANGELOG.md section; `Invoke-Build GenerateDocTables`; the default test run; the author commits. Then `Invoke-Build BuildDLL`, `Invoke-Build BuildJson` and `Invoke-Build AssembleModule` (dist/module/TerraformGraph); `Invoke-Build Release` (main, clean tree, drawers semver test passing; tags `v<version>` and pushes main and the tag); the author runs `gh release create v<version>` and attaches `dist/schema-packs/*`; `Invoke-Build Publish` (same checks; `Publish-PSResource` of dist/module/TerraformGraph). CheckBundle runs before `gh release create`, never after.

## Naming

Node types never have a property named `Address`, `Count`, `Length`, or any other member of `System.Array` (member access on an array of nodes would hit the array's own member); use a qualified name (`ModuleAddress`, `ResourceAddress`).

## Skills

`src/TerraformGraph/skills/` is canonical and ships with the module. Its function list, like the one above, is generated between `generated:functions` markers by `Invoke-Build GenerateDocTables` (tools/Update-TerraformGraphDocTables.ps1, from Get-Command and comment-based help read from the AST); change the command's help, never the generated lines, and Pester fails when they are out of date. `.claude/skills/terraformgraph/` is a generated copy: after editing the canonical `SKILL.md`, re-run `Install-TerraformGraphSkill -Path . -Tool Claude -Force` (GenerateDocTables does) and stage both. Never edit the copy by hand. `.claude/skills/manual-check-list` is a repo-development skill and is not shipped.

## Registry cache

Private `Get-TerraformRegistryCache` reads `$script:TerraformRegistryUserCachePath` (`$env:LOCALAPPDATA\TerraformGraph\registry.json`), else `$script:TerraformRegistryBundledPath` (`data/registry.json`), memoized per file version; tests repoint both with `InModuleScope` and never touch the real paths. `Invoke-Build BuildRegistry` regenerates the bundled file; it is not in the default build and is run when cutting a release (stage the result). Argument completers (`-Provider`, `-Version`, `Get-TerraformRegistryProvider -Name`) never touch the network: they read the cache only and swallow every error.

Registry rate state: every registry request (registry cache harvest, docs harvest, version lookups, `-Online`) goes through private `Invoke-TerraformRegistryRequestSet` and one process-wide `$script:TerraformRegistryThrottle`. The registry sits behind AWS WAF (429, `x-amzn-waf-reason: rate-limit`, no Retry-After). A block was observed once, at about 22:06 local time on 2026-10-06 (05:06Z on 2026-10-07), lifting about 9 minutes later; it was not logged (harvest logs start in 0.14.0), so the ladder below is a working assumption, not a measurement. The first 429 stops every worker (a shared flag parallel workers read before each request), waits one ladder step (30/60/120/240/300 s, reset by any success; the five sum to 750 s, past the observed block; a sixth 429 for one request fails it), or the Retry-After when sent, capped at 600 s (the observed block rounded up to 10 minutes), then resumes at one worker and adds one per N = 25 successful requests (about 10 s of evidence at one worker; 1 → 6 in 125 requests). 5xx retries inside the request at 2–32 s and never touches the state. The state survives across calls in a session, so the next provider starts throttled. Tests call `Reset-TerraformRegistryThrottle`, mock `Start-Sleep`, and inject `$script:TerraformRegistryInvoker` (a scriptblock returning `@{ StatusCode; Content; RetryAfter }`). Live terraform init tests share the registry's rate budget: never run them during a harvest.

## Schema cache

Provider schemas are never bundled. Private `Get-TerraformSchemaCachePath`, `Write-TerraformSchemaCache` (compact JSON, GZipStream, temp file + Move-Item; other providers in the document dropped) and `Read-TerraformSchemaCache` work on `$script:TerraformSchemaCacheRoot` (`$env:LOCALAPPDATA\TerraformGraph\schemas`), laid out `<address-slug>\<version>.json.gz`, address-slug = lowercase address with `/` → `-` (via `ConvertTo-TerraformProviderAddress`). Listing reads the address from the first `provider_schemas` key in the first 4 KB, never the slug (namespaces and names contain `-`). Tests repoint the root with `InModuleScope` and never touch the real path. `Save-TerraformSchemaPackFile` is the only pack network call; `-AutoSchema`, `Get-TerraformProviderDoc` and completers never download. With `$env:GH_TOKEN` (or `GITHUB_TOKEN`) set and a github.com release `-Source` (`.../releases/latest/download` or `.../releases/download/<tag>`), it calls `api.github.com/repos/<owner>/<repo>/releases/latest` (or `/tags/<tag>`) with Bearer auth, once per pack run, and downloads the asset's api url with `Accept: application/octet-stream`, because release download URLs 404 on private repos. This repository is public, so the default `-Source` needs no token; the token path is for private forks. Without a token it uses the anonymous URL, and a 404 names GH_TOKEN for a private fork.

Docs cache: the same helpers with `-Kind Docs` (`Get-TerraformSchemaCachePath`, `Write-TerraformSchemaCache`, `Get-TerraformSchemaCacheEntry`, `Resolve-TerraformSchemaCacheProvider`) on `$script:TerraformDocCacheRoot` (`$env:LOCALAPPDATA\TerraformGraph\docs`), same `<address-slug>\<version>.json.gz` layout. Content `{ address, version, harvestedOn, schemaVersion, docCount, unmatchedCount, docs: [ { id, category, title, subcategory, slug, content } ] }`; address and counts come first so listing reads only the head; content is raw markdown. Tests repoint both roots.

`Invoke-Build BuildSchemaPack [-Provider ...]` (default hashicorp/azurerm, microsoft/azuredevops, vmware/vsphere; hashicorp/vsphere is frozen at 2.12.0) resolves latest via the registry cache, runs `Get-TerraformProviderSchema -SaveToCache`, copies the cached files to `dist/schema-packs/<address-slug>.<version>.json.gz`, harvests the same version's docs to `docs.<address-slug>.<version>.json.gz`, and writes `manifest.json` (`builtOn`, `packs[]`: kind `schema|docs`, address, version, file, sha256, bytes; schema entries add nodeCount, resourceCount, dataSourceCount; docs entries add docCount, unmatchedCount). An entry with no kind is a schema entry (pre-0.11.0 manifests); `Get-TerraformSchemaPack` reads only schema entries, `Get-TerraformDocPack` only docs. Not in the default build. Release step: run it, then attach everything in `dist/schema-packs/` to the GitHub release (the author does this). Never stage `dist/`.

## AST

`hcl_parser.go` parses with `hclsyntax.ParseConfig` and walks the body explicitly instead of `json.Marshal`ing the `hcl.File` (which turned every `cty.Value` into `{}`). The output is `{ "Body": ... }`; blocks keep `Type`, `Labels`, `Body`, `TypeRange`, `LabelRanges`, `OpenBraceRange`, `CloseBraceRange`, bodies keep `Attributes` (map keyed by name), `Blocks`, `SrcRange`, `EndRange`, and attributes keep `Name`, `Expr`, `SrcRange`, `NameRange`, `EqualsRange`. Every expression is an object starting with `Kind` (hclsyntax type name, e.g. `TemplateExpr`), `Raw` (exact source text) and `SrcRange`, plus kind-specific fields: `LiteralValueExpr` has `Value` (cty JSON) and `ValueType`; `TemplateExpr` has `Parts`, `IsLiteral` and, when literal, the joined string `Value`; `ScopeTraversalExpr` has `Traversal` (e.g. `var.region`, `aws_instance.web[0].id`); `RelativeTraversalExpr` has `Source`, `Traversal`; `FunctionCallExpr` has `Name`, `Args`, `ExpandFinal`; `ObjectConsExpr` has `Items` of `{Key, Value}`; `TupleConsExpr` has `Exprs`; `ConditionalExpr` has `Condition`, `TrueResult`, `FalseResult`; `BinaryOpExpr` has `Op` (symbol), `LHS`, `RHS`; `UnaryOpExpr` has `Op`, `Val`; `IndexExpr` has `Collection`, `Key`; `SplatExpr` has `Source`, `Each`; `ForExpr` has `KeyVar`, `ValVar`, `CollExpr`, `KeyExpr`, `ValExpr`, `CondExpr`, `Group`; `ParenthesesExpr` has `Expression`; `TemplateWrapExpr` has `Wrapped`. Any other kind (e.g. `ObjectConsKeyExpr`, `AnonSymbolExpr`) carries only `Kind`, `Raw`, `SrcRange`. Go tests live in `src/go/hcl_parser_test.go` (`go test ./...`).

## Build

DLL is not committed (`*.dll` in `.gitignore`). Produce it with:

```powershell
Invoke-Build CheckDependencies
Invoke-Build BuildDLL
Invoke-Build
```

`CheckDependencies` (PowerShell, Pester, terraform, Docker) runs once per `Invoke-Build` invocation; `BuildDLL` depends on it. `Test` depends only on `CheckTestDependencies` (PowerShell and Pester). `BuildJson` needs a .NET 8+ SDK (`dotnet` on PATH or `$env:TERRAFORMGRAPH_DOTNET`); without one it warns and stops, and the psm1 compiles `TerraformGraph.Json.cs` at import instead. `AssembleModule` needs both DLLs.

Paths that must stay aligned:

| Role | Path |
|---|---|
| Docker builder image | `golang:1.24-bookworm`, matching go.mod's `go 1.24.0` |
| `go build -o` | `/out/TerraformGraph.dll` (c-shared also writes `/out/TerraformGraph.h`) |
| Docker `COPY --from=builder` | `/out/TerraformGraph.dll`, `/out/TerraformGraph.h` → `/` of a `scratch` image |
| `docker cp` in BuildDLL | `TerraformGraph-tmp:/TerraformGraph.dll` and `/TerraformGraph.h` → `src/TerraformGraph/lib/` |
| Module loader | `Join-Path $PSScriptRoot 'lib' 'TerraformGraph.dll'` |
| JSON assembly | `src/json/TerraformGraph.Json.csproj` → `src/TerraformGraph/lib/TerraformGraph.Json.dll` |

Image tag is `terraformgraph`. Temporary container is `TerraformGraph-tmp`.

## Testing

The default run, in a fresh process (P/Invoke pins the DLL for the life of the process, so an open shell keeps running the old parser after a Go rebuild): `pwsh -NoProfile -File .\tests\Invoke-Tests.ps1` (`Invoke-Build Test` runs the same). It excludes tests tagged `Live`. Tests tagged `RequiresTerraform` need the terraform binary but no network and are skipped, not failed, without it; `RequiresBuild` tests need both DLLs in `lib/` and are skipped without them.

The Live run, separately: `pwsh -NoProfile -File .\tests\Invoke-Tests.ps1 -Live` (`-All` for everything). Live tests call registry.terraform.io and run terraform init that downloads providers; they spend the registry's rate budget, so never run them during a harvest. A bare `Invoke-Pester` skips them unless `TERRAFORMGRAPH_LIVE=1`.

## Conventions

- Work on `main` only for now.
- Keep changes scoped. No drive-by refactors.
- Do not commit secrets, `.tfstate`, compiled `.dll` files, the generated `lib/TerraformGraph.h`, zips, or `dist/` (gitignored).
- PowerShell 7.4+. Go module is `hcl_parser`.
- Fixtures live under `infra/`. Do not resurrect root `test.tf`.

## Do not

- Invent cloud credentials or real provider configs for fixtures.
- Change export names `ParseHCL` / `FreeString` without updating the P/Invoke signatures.
- Put `terraform.exe` in `ExternalModuleDependencies` — that field is PowerShell modules only.
