# TerraformGraph

PowerShell module that parses Terraform `.tf` files into an HCL AST via a Go `c-shared` DLL (`hashicorp/hcl/v2`) and builds graphs of module calls and provider schemas on top of it.

Requires PowerShell 7.4+, Pester 6.1.0+, Terraform CLI (fixture/dev check), and a running Docker engine to build the DLL.

## Layout

```
src/go/                 Go parser (hcl_parser.go) — buildmode=c-shared
src/TerraformGraph/       PowerShell module root
  TerraformGraph.psd1
  TerraformGraph.psm1     P/Invoke + ConvertFrom-TerraformHclFile + exported functions
  TerraformGraph.Json.cs  System.Text.Json serializer/deserializer (TerraformGraph.Json)
  TerraformGraph.Format.ps1xml  Table views for BundleEntry and SubcategorySurveyRow (more than four default columns)
  lib/                  TerraformGraph.dll (build artifact, gitignored) + TerraformGraph.h
  skills/terraformgraph/SKILL.md  Canonical agent skill (shipped with the module)
  data/registry.json    Bundled provider registry cache (Invoke-Build BuildRegistry; shipped)
  data/bundle.json      Bundle manifest: provider set and per-provider versions (Invoke-Build HarvestBundleDocs; shipped)
  classifiers/          drawers.json, map.json, DECISIONS.md and <address-slug>.<version>.json classifiers (Invoke-Build BuildClassifier; committed and shipped)
dist/schema-packs/      Schema and docs packs from Invoke-Build BuildSchemaPack (gitignored; attached to GitHub releases)
dist/survey/            subcategories.json from Invoke-Build HarvestBundleDocs (gitignored)
README.md               Sysadmin door; line 1 is the only ontology mention (repo skill readme)
ONTOLOGY.md             Agent/ontology door; banner, then backlink to README (repo skill ontology-doc)
.claude/skills/terraformgraph/  Generated copy of the skill (Install-TerraformGraphSkill)
.claude/skills/readme, ontology-doc, manual-check-list  Repo-development skills (not shipped)
AGENTS.md               Generated pointer section (Install-TerraformGraphSkill) plus a hand-kept Repository skills section
infra/                  Fixture modules used by tests and README examples
tests/                  Pester 6.1+ (*.Tests.ps1); fixtures/schemas holds real null 3.2.3 and local 2.5.2 schemas, fixtures/docs their harvested docs, fixtures/classifiers a map, a bad map, a prefix map, subcategories applied to those docs, an override classifier, and drawers.0.13.0.json (the semver gate's fallback when git is unavailable)
Dockerfile              Cross-compile Windows DLL with mingw from Linux
.build.ps1              InvokeBuild: CheckDependencies, BuildDLL, Test, Package, BuildRegistry, BuildSchemaPack, BuildClassifier, HarvestBundleDocs, CheckBundle
```

Module name is **TerraformGraph**. Do not reintroduce `PS.Util.Terraform`.

Exported functions:
- `Get-TerraformAST` — parse `.tf` files into HCL blocks; `-Path` directory (optional `-Recurse`) or `-FilePath` one `.tf` file.
- `ConvertTo-TerraformJson` — serialize objects to JSON with no 100-level depth cap (`-Depth`, `-Compress`, `-AsArray`).
- `ConvertFrom-TerraformJson` — parse deep JSON into PSCustomObjects or ordered dictionaries (`-Depth`, `-AsHashtable`, `-NoEnumerate`).
- `Get-TerraformProviderSchema` — run `terraform providers schema -json` in `-Path`, or fetch one provider on demand with `-Provider` (`-Version`, `-WorkingDirectory`, `-Cleanup`, `-Force`; init only when no lock file; `-SaveToCache` also writes the schema cache at the lock-file version, else `terraform version -json`); `-OutputFormat OrderedHashtable|Json`.
- `Get-TerraformModuleGraph` — module-call graph (Nodes, Edges, Unresolved) from `module` blocks in `-Path`; `-Recurse`, `-GroupBy Call|Source`; non-local sources via `.terraform/modules/modules.json`, never runs init.
- `ConvertTo-TerraformSchemaGraph` — provider schema (dictionary, Json text, or PSCustomObject) to a graph of SchemaNodes (Providers, Nodes, Edges, Summary); `-Provider` filter (throws if absent; no wildcards with `-Schema`), `-IncludeFunctions`; attribute `Type` rendered by private `ConvertTo-TerraformTypeString`. Default parameter set is `Cache`: `-Provider` patterns alone (`-Version`, default newest cached) load from the schema cache as if piped; not cached is a terminating error naming `Get-TerraformSchemaPack` and `-SaveToCache`. `-Classify` / `-ClassifierPath` (implies `-Classify`, every set): Drawer and Subcategory on every node (set inside `New-TerraformSchemaNode`, inherited from the parent below a type; Provider/config/Function `$null`), `Drawers` summary.
- `ConvertTo-TerraformVariableGraph` — ModuleGraph to a graph of variables, locals and outputs (Nodes, Edges, Unresolved, Skipped, Summary); edges Reference, Argument, OutputReference from declaration expressions and module call arguments only; references found by private `Get-TerraformExpressionReferences`; never reparses.
- `Get-TerraformVariableTrace` — breadth-first walk of a VariableGraph from `-Id` (`-Direction Upstream|Downstream|Both`, `-MaxDepth`); nodes copied with `Distance`, negative upstream under Both.
- `ConvertTo-TerraformResourceGraph` — ModuleGraph (plus optional `-SchemaGraph` array) to an inventory of resource/data blocks (Nodes, Edges, Skipped, Providers, MatchedCount, UnmatchedCount, Findings); `InstanceOf` edge to the schema node when matched; top-level-only `UnknownAttributes`, `UnknownBlocks`, `MissingRequired`; Reason `NoSchemaGraph|ProviderNotInSchemaGraph|TypeNotInProvider`; never reparses. Parameter sets `SchemaGraph` (default), `Provider` (schema graphs from the cache), `AutoSchema` (cached schemas for the resolved addresses; uncached ones are ProviderNotInSchemaGraph; never downloads). `-Classify` / `-ClassifierPath` in every set: Drawer and Subcategory per node, `Drawers` with TypeCount (distinct SchemaIds) and InstanceCount.
- `Install-TerraformGraphSkill` — copy `skills/*` into `<Path>/<tool skills folder>/` (`-Tool Claude|Codex|Cursor|Gemini|Copilot|All`, default Claude; `-Force`, `-PassThru` → SkillInstall); creates or appends once to `AGENTS.md` behind `<!-- terraformgraph-skill -->`; no network.
- `Test-TerraformGraphSkill` — per tool SkillStatus (Detected, Installed, Stale, SkillPath); read only. Private `Show-TerraformGraphSkillHint` runs it at import and prints one host line for detected-but-not-installed tools; `TERRAFORMGRAPH_SKILL_HINT=0` silences it. Tool paths live only in the private `$script:TerraformGraphSkillTools` table.
- `Update-TerraformRegistryCache` — harvest registry.terraform.io (v2 list, 100/page; per provider v1 `/versions` for protocols + v2 `include=provider-versions` for dates, `Invoke-TerraformRegistryRequestSet`, the process rate state in "Registry cache") into `-Path` (default user cache), atomic write; `-Scope OfficialPartner|All`, `-ThrottleLimit`, `-PassThru` → RegistryCache.
- `Get-TerraformSchemaPack` — read `manifest.json` from `-Source` (default `https://github.com/JerryBalmer1/TerraformGraph/releases/latest/download`, or a local folder), pick each `-Provider` entry (wildcards via `Resolve-TerraformRegistryProvider`; default every entry; `-Version` default newest in manifest), download via private `Save-TerraformSchemaPackFile`, verify sha256, move into the schema cache; skips cached unless `-Force`; no entry → terminating error naming `Get-TerraformProviderSchema -SaveToCache`; `-PassThru` → SchemaPack (Status `Downloaded|Cached|Updated`).
- `Get-TerraformSchemaCache` — CachedSchema (ProviderAddress, Version, Path, Bytes, CachedOn) per cached file, `-Provider` patterns; read only.
- `Update-TerraformProviderDocCache` — harvest registry provider docs into the docs cache. Set `Provider`: `-Provider` (wildcards via the registry), `-Version` (default registry-cache latest), `-Force` (also deletes the partial file first), `-PassThru` → DocCache (ProviderAddress, Version, Path, Status `Harvested|Cached|Updated`, DocCount, UnmatchedCount, SchemaVersion, ResumedPages, Elapsed, Error); a failure is terminating. Set `Bundle`: `-BundlePath` harvests every provider of the bundle's set at its registry-cache latest, one after another, and returns one DocHarvestSummary (BundlePath, ProviderCount, PageCount, UnmatchedCount, FailureCount, RateLimitHits, SecondsBlocked, PartialResumes, Elapsed, LogPath, Providers, Failures); a failing provider is a warning and a `Failed` row, never a stop; without `-Resume` every provider is harvested again; writes `$env:LOCALAPPDATA\TerraformGraph\logs\harvest-<yyyyMMdd-HHmmss>.log` (UTC; `$script:TerraformGraphLogRoot`, repointed by tests): a start line, one line per provider, one per 429 and per wait, an end line; prints the path. Both: `-ThrottleLimit` 6, `-Resume` (skip a version already cached, before any network call, else continue from `<version>.partial.json`; with `-Force` is `ResumeWithForce`). Page checkpoint: `docs\<slug>\<version>.partial.json` (`{ address, version, versionId, savedOn, pageCount, pages: [ { docId, content } ] }`, plain JSON so the `*.json.gz` cache listing never reads it) is written every M = 100 pages (`$script:TerraformDocCheckpointPages`) and in a `finally` when the harvest stops part-way (failed page, Ctrl+C); a finished harvest deletes it; a partial for another registry version id is ignored. v2 `include=provider-versions` for the version id, `/v2/provider-versions/<id>?include=provider-docs` for the listing, `/v2/provider-docs/<id>` per page (`Invoke-TerraformRegistryRequestSet`). Keeps overview, guides, resources, data-sources in hcl only. Per-provider work is private `Invoke-TerraformProviderDocUpdate`.
- `Get-TerraformProviderDoc` — ProviderDoc (Id, ProviderAddress, Version, Category, Title, Subcategory, Slug, Type, Content, ExampleCount) from the docs cache only: `-Provider` patterns (default every cached provider), `-Version`, `-Id`/`-Type` wildcards, `-Category`, `-Examples` (hcl/terraform fences only), or piped SchemaNode (Id) / ResourceNode (SchemaId); nested nodes map to their resource/data page, Provider/config nodes to the overview; each page once per call; uncached provider in the pipeline → one warning, builtin skipped; `-Provider` not cached → terminating error naming `Get-TerraformDocPack` and `Update-TerraformProviderDocCache`.
- `Get-TerraformDocPack` — `Get-TerraformSchemaPack` for manifest `docs` entries (same parameters; DocPack output). Both wrap private `Install-TerraformPack -Kind Schema|Docs`.
- `Get-TerraformDocCache` — CachedDoc (ProviderAddress, Version, Path, Bytes, CachedOn, DocCount, UnmatchedCount, HarvestedOn) per cached docs file, `-Provider` patterns; read only. Chosen over a Kind column on `Get-TerraformSchemaCache` so CachedSchema and its callers stay unchanged.
- `New-TerraformClassifier` — one provider version's classifier from the schema cache (types) and docs cache (subcategories) through `-MapPath` (default bundled `classifiers/map.json`, validated first by private `Get-TerraformClassifierMapProblem`) into `-OutputPath` (default `$env:LOCALAPPDATA\TerraformGraph\classifiers`) as `<address-slug>.<version>.json`; `-Provider` wildcards via `Resolve-TerraformRegistryProvider`, `-Version` default newest cached schema (docs same version else newest with a warning); findings `NoDocPage|NoSubcategory|UnmappedSubcategory`; sorted, `generatedOn` kept when content is unchanged (byte-identical reruns); `-PassThru` → ClassifierBuild (Status `Written|Updated|Unchanged`).
- `Get-TerraformClassifier` — Classifier (Types, Findings, TypeCount, FindingCount, Path) per provider; `-Provider` shape patterns, `-Version`, `-ClassifierPath` (file or folder). Lookup: `-ClassifierPath`, user root, bundled root; the first root holding the provider picks the version (DECISIONS 4); for that same version in several roots, `-ClassifierPath` always wins, else the file whose mapVersion matches map.json, then newer generatedOn (DECISIONS 48; private `Select-TerraformClassifierWinner`), with a warning naming each shadowed file. `-Shadowed` → ClassifierShadow (ProviderAddress, Version, Location `ClassifierPath|User|Bundled`, Path, Reason, ShadowedPath) per provider version in more than one location.
- `Get-TerraformClassifierFinding` — same parameters; ClassifierFinding rows (table Type, Kind, Subcategory, Finding).
- `Get-TerraformGraphBundle` — BundleEntry rows (ProviderAddress, Version, DocsVersion, SchemaVersion, ClassifierVersion, HarvestedOn; table) from `-Path` (alias BundlePath; default user copy `$env:LOCALAPPDATA\TerraformGraph\bundle.json`, else bundled `data/bundle.json`); `-Document` → Bundle (Path, FormatVersion, Tiers, Providers, Exclude, RegistryHarvestedOn, RegistryProviderCount, Sources, Entries, EntryCount); `-Sources` → BundleSource rows (Kind, Urls, RelatedUrls, HarvestedBy, LastPulled). Errors `BundleNotFound`, `BundleInvalid`.
- `New-TerraformGraphBundle` — write a bundle manifest (`-OutputPath`, default the user copy; a folder gets bundle.json) for `-Tier` + `-Provider` patterns − `-Exclude` patterns, resolved against the registry.json beside the output, else the registry cache; unbound `-Tier`/`-Provider`/`-Exclude` come from the bundled manifest; patterns stored expanded to addresses; entries from the caches and the bundled classifiers; sorted, no timestamp, byte-identical reruns; `-PassThru` → Bundle. Never networks.
- `Test-TerraformGraphBundle` — BundleCheck rows (Item, Status `Fresh|Stale|Missing`, Detail, RecommendedAction, InspectAction; table Item, Status, RecommendedAction): every non-Fresh row has both pasteable commands, Fresh rows neither; RecommendedAction promotes (Invoke-Build tasks for the bundled manifest, else user-side commands), InspectAction writes only to `$env:TEMP\TerraformGraph-inspect` or the user caches and shows the diff (`git diff --no-index`) or the cache state; rows: registry, sources, entry/docs/schema/classifier per entry, mapVersion per bundled classifier, pack per `-DistPath` (default `.\dist\schema-packs`) manifest entry when it exists; `-Online` adds the live registry count and each entry's live latest; `-Strict` writes the rows, then throws `BundleNotFresh`.
- `Get-TerraformSubcategorySurvey` — SubcategorySurveyRow (ProviderAddress, Version, Subcategory, ResourceCount, DataSourceCount, Status `Labeled|NoSubcategory`) per provider and doc label from the docs cache only; set `Bundle` (`-BundlePath`, default as Get-TerraformGraphBundle; uncached providers: one warning, listed as missing) or `Provider` (`-Provider` patterns, `-Version`); `-OutputPath` writes JSON with provenance (bundle, providers with harvestedOn and schemaVersion, missing, labels with providerCount, noSubcategory, rows), sorted, no timestamp; rows then only with `-PassThru`.
- `Get-TerraformRegistryProvider` — RegistryProvider objects from the cache, never the network; `-Name` patterns (no slash = bare name in any namespace, one = namespace/name, two = address), `-Tier`, `-NoBundledData`. No cache: one warning, no output. `Get-TerraformProviderSchema -Provider` with a wildcard resolves through private `Resolve-TerraformRegistryProvider` (exactly one match, else a terminating error listing matches); without a wildcard it needs no cache.

Planned: view (0.15.0), compare (0.16.0), eras (0.17.0, derived from compares); see ONTOLOGY.md "Not here yet".

Every terminating error's message names the command that fixes it. The ids and their fixing commands are the maintained list in Pester "names a documented fixing command for every terminating error id in the psm1"; a new id fails it until listed.

## Canonical ids

`ConvertTo-TerraformSchemaGraph` node Ids, where `<address>` is the provider_schemas key: Provider `<address>`; provider config Attribute/Block `<address>/config/<name>` (Path `<provider short name>.<name>`, Depth 1, emitted before resources); Resource `<address>/resource/<type>`; DataSource `<address>/data/<type>`; Function `<address>/function/<name>`; Block `<parent Id>/<block name>`; Attribute `<parent Id>/<attribute name>`. `ConvertTo-TerraformVariableGraph` node Ids, where `<module>` is the ModuleAddress (`root` for the root module): Variable `<module>/var/<name>`; Local `<module>/local/<name>`; Output `<module>/output/<name>`. `ConvertTo-TerraformResourceGraph` node Ids: Resource `<module>/resource/<type>.<name>`; DataSource `<module>/data/<type>.<name>` (one per block, no provider in the Id; `SchemaId` holds the schema graph's `<address>/resource/<type>` or `/data/<type>`). Provider docs key on the schema Id: overview `<address>`; guide `<address>/guide/<slug>`; resource `<address>/resource/<type>`; data source `<address>/data/<type>`; a resource/data page whose type is not in the cached schema `<address>/unmatched/<category>/<slug>` (counted in UnmatchedCount, a finding). Type = `<prefix>_<slug>` with the prefix the cached schema uses, else the slug itself when it already carries the prefix (vsphere). `Id` is unique per document; `Path` (`<type>.<block>.<attr>`) is display only and may collide across providers.

## Provider resolution

`ConvertTo-TerraformResourceGraph` resolves each block per module, as Terraform does: local name = type up to the first underscore, or the part before the dot of a `provider = name.alias` argument (sets `ProviderAlias`). It maps through that module's own `terraform { required_providers }` `source` via `ConvertTo-TerraformProviderAddress` (lowercased); undeclared names fall back to `terraform.io/builtin/terraform` for `terraform`, else `registry.terraform.io/hashicorp/<name>`. Child modules never inherit the parent's `required_providers`.

## Classifiers

Optional overlay grouping resource and data source types into drawers. Never changes Ids, node count or edges (Pester asserts it). `src/TerraformGraph/classifiers/` holds `drawers.json` (fixed list, `unclassified` last), `map.json` (`{ rows: [ { provider: <address>|"*", source?: subcategory|prefix, subcategory, drawer, reason, addedOn, addedBy: agent|jerry } ] }`; subcategory rows: provider row beats `*`, label matched exactly ignoring case; prefix rows (`source: "prefix"`, provider address only, `subcategory` holds the type prefix after the provider token, e.g. `git` for `azuredevops_git_*`): match at underscore boundaries, longest wins, and apply only to types with no label (no doc page or empty subcategory); a labelled type the map does not place stays `UnmappedSubcategory`; a prefix row must match a type in the provider's cached schema or New-TerraformClassifier throws `ClassifierMapInvalid`), `DECISIONS.md` (append-only numbered entries: Question / Call / Rejected / Why / Cost if wrong; never edit an earlier one) and the bundled classifiers. Classifier file: `{ provider, version, docsVersion, generatedOn, mapVersion, source: "subcategory"|"subcategory,prefix", types: [ { type, kind: resource|data-source, subcategory, drawer, source: subcategory|prefix|null } ], findings: [ { type, kind, subcategory, finding } ] }`, provider and version first so listing reads the head; `mapVersion` = first 12 hex of sha256 of the map's compact JSON. `$script:TerraformClassifierUserRoot` / `$script:TerraformClassifierBundledRoot` are repointed by tests; `$script:TerraformClassifierDrawersPath` and `$script:TerraformClassifierMapPath` are not. Before any classifier work read DECISIONS.md and append an entry for every judgement; no map row without a reason; after a map change run `Invoke-Build BuildClassifier` (same default providers as BuildSchemaPack, version from the registry cache, no network) and stage `classifiers/`. A test fails when a bundled classifier's mapVersion is stale.

Semver (DECISIONS 47): data refreshes, new map rows and added drawers are minor; renaming or removing a drawer or another class name agents filter on is major. Pester "drawers are semver-safe" compares drawers.json with the previous release (`git show v<x.y.z>:src/TerraformGraph/classifiers/drawers.json`, newest tag below the psd1 version; fixture fallback) and fails a removed or renamed drawer unless the psd1 major is higher.

## Bundle and release

`data/bundle.json` (`{ formatVersion: 1, tiers, providers, exclude, registry: { harvestedOn, providerCount }, sources: [ { kind, urls, relatedUrls, harvestedBy, lastPulled } ], entries: [ { provider, version, docsVersion, schemaVersion, classifierVersion, harvestedOn } ] }`) is the provider set the shipped data covers: official tier + microsoft/azuredevops + vmware/vsphere. A bundle resolves against the `registry.json` in its own folder, else the registry cache; entry `version` = registry-cache latest, `docsVersion` = docs cached at that version else newest, `schemaVersion` = only when the schema cache holds exactly `version`, `classifierVersion` = newest bundled classifier (never the user folder). `sources` has one entry per bundled data kind (registry, schemas, docs, classifiers, skills, cmdb reserved) from `$script:TerraformGraphBundleSources`; `lastPulled` comes from the data (registry harvestedOn, newest CachedOn of recorded schemas, newest entry harvestedOn, newest generatedOn of recorded classifiers), never the clock, so reruns stay byte-identical. `$script:TerraformGraphBundleBundledPath` / `$script:TerraformGraphBundleUserPath` are repointed by tests. `Invoke-Build HarvestBundleDocs [-Resume]` (not in the default build; network, 30–60 min) runs `Update-TerraformProviderDocCache -BundlePath` on the bundled manifest, refreshes its entries with `New-TerraformGraphBundle`, and writes `dist/survey/subcategories.json`; stage `data/bundle.json`, never `dist/`. `Invoke-Build CheckBundle [-Online]` is `Test-TerraformGraphBundle -Strict`.

Promote or leave: harvests and `New-*` commands write to the user caches (development); `src/` is production. When Test-TerraformGraphBundle returns Stale or Missing, an agent runs the row's InspectAction and puts the diff in its report, and runs the RecommendedAction only if its task is about that data; otherwise it reports the row and leaves it. Nothing moves into `src/` except through an Invoke-Build task, and an agent commits nothing. The report gives the human both commands, pasteable.

Release block, in order: `Invoke-Build BuildRegistry`; `Invoke-Build BuildSchemaPack`; `Invoke-Build BuildClassifier`; `Invoke-Build HarvestBundleDocs`; `Invoke-Build CheckBundle` (must pass); stage `data/`, `classifiers/`; then the author runs `gh release create` and attaches `dist/schema-packs/*`. CheckBundle runs before `gh release create`, never after.

## Naming

Node types never have a property named `Address`, `Count`, `Length`, or any other member of `System.Array` (member access on an array of nodes would hit the array's own member); use a qualified name (`ModuleAddress`, `ResourceAddress`).

## Skills

`src/TerraformGraph/skills/` is canonical and ships with the module. `.claude/skills/terraformgraph/` is a generated copy: after editing the canonical `SKILL.md`, re-run `Install-TerraformGraphSkill -Path . -Tool Claude -Force` and stage both. Never edit the copy by hand. `.claude/skills/manual-check-list` is a repo-development skill and is not shipped.

## Registry cache

Private `Get-TerraformRegistryCache` reads `$script:TerraformRegistryUserCachePath` (`$env:LOCALAPPDATA\TerraformGraph\registry.json`), else `$script:TerraformRegistryBundledPath` (`data/registry.json`), memoized per file version; tests repoint both with `InModuleScope` and never touch the real paths. `Invoke-Build BuildRegistry` regenerates the bundled file; it is not in the default build and is run when cutting a release (stage the result). Argument completers (`-Provider`, `-Version`, `Get-TerraformRegistryProvider -Name`) never touch the network: they read the cache only and swallow every error.

Registry rate state: every registry request (registry cache harvest, docs harvest, version lookups, `-Online`) goes through private `Invoke-TerraformRegistryRequestSet` and one process-wide `$script:TerraformRegistryThrottle`. The registry sits behind AWS WAF (429, `x-amzn-waf-reason: rate-limit`, no Retry-After); on 2026-10-07 the first 429 came at 22:06 and the block lifted about 9 minutes later. The first 429 stops every worker (a shared flag parallel workers read before each request), waits one ladder step (30/60/120/240/300 s, reset by any success; the five sum to 750 s, past the observed block; a sixth 429 for one request fails it), or the Retry-After when sent, capped at 600 s (the observed block rounded up to 10 minutes), then resumes at one worker and adds one per N = 25 successful requests (about 10 s of evidence at one worker; 1 → 6 in 125 requests). 5xx retries inside the request at 2–32 s and never touches the state. The state survives across calls in a session, so the next provider starts throttled. Tests call `Reset-TerraformRegistryThrottle`, mock `Start-Sleep`, and inject `$script:TerraformRegistryInvoker` (a scriptblock returning `@{ StatusCode; Content; RetryAfter }`). Live terraform init tests share the registry's rate budget: never run them during a harvest.

## Schema cache

Provider schemas are never bundled. Private `Get-TerraformSchemaCachePath`, `Write-TerraformSchemaCache` (compact JSON, GZipStream, temp file + Move-Item; other providers in the document dropped) and `Read-TerraformSchemaCache` work on `$script:TerraformSchemaCacheRoot` (`$env:LOCALAPPDATA\TerraformGraph\schemas`), laid out `<address-slug>\<version>.json.gz`, address-slug = lowercase address with `/` → `-` (via `ConvertTo-TerraformProviderAddress`). Listing reads the address from the first `provider_schemas` key in the first 4 KB, never the slug (namespaces and names contain `-`). Tests repoint the root with `InModuleScope` and never touch the real path. `Save-TerraformSchemaPackFile` is the only pack network call; `-AutoSchema`, `Get-TerraformProviderDoc` and completers never download. With `$env:GH_TOKEN` (or `GITHUB_TOKEN`) set and a github.com release `-Source` (`.../releases/latest/download` or `.../releases/download/<tag>`), it calls `api.github.com/repos/<owner>/<repo>/releases/latest` (or `/tags/<tag>`) with Bearer auth, once per pack run, and downloads the asset's api url with `Accept: application/octet-stream`, because release download URLs 404 on private repos. Without a token it uses the anonymous URL, and a 404 names GH_TOKEN.

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

`CheckDependencies` runs once per `Invoke-Build` invocation. `BuildDLL` and `Test` both depend on it.

Paths that must stay aligned:

| Role | Path |
|---|---|
| `go build -o` | `/app/src/TerraformGraph/lib/TerraformGraph.dll` |
| Docker `COPY --from=builder` | `/app/src/TerraformGraph/lib/TerraformGraph.dll` → `/TerraformGraph.dll` |
| `docker cp` in BuildDLL | `TerraformGraph-tmp:/TerraformGraph.dll` → `src\TerraformGraph\lib\TerraformGraph.dll` |
| Module loader | `Join-Path $PSScriptRoot "lib\TerraformGraph.dll"` |

Image tag is `terraformgraph`. Temporary container is `TerraformGraph-tmp`.

`mkdir -p` the lib directory in the builder stage before `go build`.

## Testing

After any Go rebuild, run tests in a fresh pwsh process (pwsh -NoProfile -Command 'Invoke-Pester -Path .\tests'); P/Invoke pins the DLL for the life of the process, so an open shell will keep running the old parser.

## Conventions

- Work on `main` only for now.
- Keep changes scoped. No drive-by refactors.
- Do not commit secrets, `.tfstate`, compiled `.dll` files, `TerraformGraph.zip`, or `dist/` (gitignored).
- PowerShell 7.4+. Go module is `hcl_parser`.
- Fixtures live under `infra/`. Do not resurrect root `test.tf`.

## Do not

- Invent cloud credentials or real provider configs for fixtures.
- Change export names `ParseHCL` / `FreeString` without updating the P/Invoke signatures.
- Put `terraform.exe` in `ExternalModuleDependencies` — that field is PowerShell modules only.
