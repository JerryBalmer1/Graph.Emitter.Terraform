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
  lib/                  TerraformGraph.dll (build artifact, gitignored) + TerraformGraph.h
  skills/terraformgraph/SKILL.md  Canonical agent skill (shipped with the module)
  data/registry.json    Bundled provider registry cache (Invoke-Build BuildRegistry; shipped)
  classifiers/          drawers.json, map.json, DECISIONS.md and <address-slug>.<version>.json classifiers (Invoke-Build BuildClassifier; committed and shipped)
dist/schema-packs/      Schema and docs packs from Invoke-Build BuildSchemaPack (gitignored; attached to GitHub releases)
.claude/skills/terraformgraph/  Generated copy of the skill (Install-TerraformGraphSkill)
AGENTS.md               Generated pointer section (Install-TerraformGraphSkill)
infra/                  Fixture modules used by tests and README examples
tests/                  Pester 6.1+ (*.Tests.ps1); fixtures/schemas holds real null 3.2.3 and local 2.5.2 schemas, fixtures/docs their harvested docs, fixtures/classifiers a map, a bad map, subcategories applied to those docs, and an override classifier
Dockerfile              Cross-compile Windows DLL with mingw from Linux
.build.ps1              InvokeBuild: CheckDependencies, BuildDLL, Test, Package, BuildRegistry, BuildSchemaPack, BuildClassifier
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
- `Update-TerraformRegistryCache` — harvest registry.terraform.io (v2 list, 100/page; per provider v1 `/versions` for protocols + v2 `include=provider-versions` for dates, `ForEach-Object -Parallel`, 2 retries on 429/5xx) into `-Path` (default user cache), atomic write; `-Scope OfficialPartner|All`, `-ThrottleLimit`, `-PassThru` → RegistryCache.
- `Get-TerraformSchemaPack` — read `manifest.json` from `-Source` (default `https://github.com/JerryBalmer1/TerraformGraph/releases/latest/download`, or a local folder), pick each `-Provider` entry (wildcards via `Resolve-TerraformRegistryProvider`; default every entry; `-Version` default newest in manifest), download via private `Save-TerraformSchemaPackFile`, verify sha256, move into the schema cache; skips cached unless `-Force`; no entry → terminating error naming `Get-TerraformProviderSchema -SaveToCache`; `-PassThru` → SchemaPack (Status `Downloaded|Cached|Updated`).
- `Get-TerraformSchemaCache` — CachedSchema (ProviderAddress, Version, Path, Bytes, CachedOn) per cached file, `-Provider` patterns; read only.
- `Update-TerraformProviderDocCache` — harvest one registry provider version's docs into the docs cache (`-Provider` wildcards via the registry, `-Version` default registry-cache latest, `-ThrottleLimit` 6, `-Force`, `-PassThru` → DocCache: ProviderAddress, Version, Path, Status `Harvested|Cached|Updated`, DocCount, UnmatchedCount, SchemaVersion, Elapsed). v2 `include=provider-versions` for the version id, `/v2/provider-versions/<id>?include=provider-docs` for the listing, `/v2/provider-docs/<id>` per page (`ForEach-Object -Parallel`, `Invoke-TerraformRegistryRequest` retries). Keeps overview, guides, resources, data-sources in hcl only.
- `Get-TerraformProviderDoc` — ProviderDoc (Id, ProviderAddress, Version, Category, Title, Subcategory, Slug, Type, Content, ExampleCount) from the docs cache only: `-Provider` patterns (default every cached provider), `-Version`, `-Id`/`-Type` wildcards, `-Category`, `-Examples` (hcl/terraform fences only), or piped SchemaNode (Id) / ResourceNode (SchemaId); nested nodes map to their resource/data page, Provider/config nodes to the overview; each page once per call; uncached provider in the pipeline → one warning, builtin skipped; `-Provider` not cached → terminating error naming `Get-TerraformDocPack` and `Update-TerraformProviderDocCache`.
- `Get-TerraformDocPack` — `Get-TerraformSchemaPack` for manifest `docs` entries (same parameters; DocPack output). Both wrap private `Install-TerraformPack -Kind Schema|Docs`.
- `Get-TerraformDocCache` — CachedDoc (ProviderAddress, Version, Path, Bytes, CachedOn, DocCount, UnmatchedCount) per cached docs file, `-Provider` patterns; read only. Chosen over a Kind column on `Get-TerraformSchemaCache` so CachedSchema and its callers stay unchanged.
- `New-TerraformClassifier` — one provider version's classifier from the schema cache (types) and docs cache (subcategories) through `-MapPath` (default bundled `classifiers/map.json`, validated first by private `Get-TerraformClassifierMapProblem`) into `-OutputPath` (default `$env:LOCALAPPDATA\TerraformGraph\classifiers`) as `<address-slug>.<version>.json`; `-Provider` wildcards via `Resolve-TerraformRegistryProvider`, `-Version` default newest cached schema (docs same version else newest with a warning); findings `NoDocPage|NoSubcategory|UnmappedSubcategory`; sorted, `generatedOn` kept when content is unchanged (byte-identical reruns); `-PassThru` → ClassifierBuild (Status `Written|Updated|Unchanged`).
- `Get-TerraformClassifier` — Classifier (Types, Findings, TypeCount, FindingCount, Path) per provider; `-Provider` shape patterns, `-Version`, `-ClassifierPath` (file or folder). Lookup: `-ClassifierPath`, user root, bundled root; first root holding the provider wins.
- `Get-TerraformClassifierFinding` — same parameters; ClassifierFinding rows (table Type, Kind, Subcategory, Finding).
- `Get-TerraformRegistryProvider` — RegistryProvider objects from the cache, never the network; `-Name` patterns (no slash = bare name in any namespace, one = namespace/name, two = address), `-Tier`, `-NoBundledData`. No cache: one warning, no output. `Get-TerraformProviderSchema -Provider` with a wildcard resolves through private `Resolve-TerraformRegistryProvider` (exactly one match, else a terminating error listing matches); without a wildcard it needs no cache.

Planned: none.

## Canonical ids

`ConvertTo-TerraformSchemaGraph` node Ids, where `<address>` is the provider_schemas key: Provider `<address>`; provider config Attribute/Block `<address>/config/<name>` (Path `<provider short name>.<name>`, Depth 1, emitted before resources); Resource `<address>/resource/<type>`; DataSource `<address>/data/<type>`; Function `<address>/function/<name>`; Block `<parent Id>/<block name>`; Attribute `<parent Id>/<attribute name>`. `ConvertTo-TerraformVariableGraph` node Ids, where `<module>` is the ModuleAddress (`root` for the root module): Variable `<module>/var/<name>`; Local `<module>/local/<name>`; Output `<module>/output/<name>`. `ConvertTo-TerraformResourceGraph` node Ids: Resource `<module>/resource/<type>.<name>`; DataSource `<module>/data/<type>.<name>` (one per block, no provider in the Id; `SchemaId` holds the schema graph's `<address>/resource/<type>` or `/data/<type>`). Provider docs key on the schema Id: overview `<address>`; guide `<address>/guide/<slug>`; resource `<address>/resource/<type>`; data source `<address>/data/<type>`; a resource/data page whose type is not in the cached schema `<address>/unmatched/<category>/<slug>` (counted in UnmatchedCount, a finding). Type = `<prefix>_<slug>` with the prefix the cached schema uses, else the slug itself when it already carries the prefix (vsphere). `Id` is unique per document; `Path` (`<type>.<block>.<attr>`) is display only and may collide across providers.

## Provider resolution

`ConvertTo-TerraformResourceGraph` resolves each block per module, as Terraform does: local name = type up to the first underscore, or the part before the dot of a `provider = name.alias` argument (sets `ProviderAlias`). It maps through that module's own `terraform { required_providers }` `source` via `ConvertTo-TerraformProviderAddress` (lowercased); undeclared names fall back to `terraform.io/builtin/terraform` for `terraform`, else `registry.terraform.io/hashicorp/<name>`. Child modules never inherit the parent's `required_providers`.

## Classifiers

Optional overlay grouping resource and data source types into drawers. Never changes Ids, node count or edges (Pester asserts it). `src/TerraformGraph/classifiers/` holds `drawers.json` (fixed list, `unclassified` last), `map.json` (`{ rows: [ { provider: <address>|"*", subcategory, drawer, reason, addedOn, addedBy: agent|jerry } ] }`, provider row beats `*`, subcategory matched exactly ignoring case), `DECISIONS.md` (append-only numbered entries: Question / Call / Rejected / Why / Cost if wrong; never edit an earlier one) and the bundled classifiers. Classifier file: `{ provider, version, docsVersion, generatedOn, mapVersion, source: "subcategory", types: [ { type, kind: resource|data-source, subcategory, drawer } ], findings: [ { type, kind, subcategory, finding } ] }`, provider and version first so listing reads the head; `mapVersion` = first 12 hex of sha256 of the map's compact JSON. `$script:TerraformClassifierUserRoot` / `$script:TerraformClassifierBundledRoot` are repointed by tests; `$script:TerraformClassifierDrawersPath` and `$script:TerraformClassifierMapPath` are not. Before any classifier work read DECISIONS.md and append an entry for every judgement; no map row without a reason; after a map change run `Invoke-Build BuildClassifier` (same default providers as BuildSchemaPack, version from the registry cache, no network) and stage `classifiers/`. A test fails when a bundled classifier's mapVersion is stale.

## Naming

Node types never have a property named `Address`, `Count`, `Length`, or any other member of `System.Array` (member access on an array of nodes would hit the array's own member); use a qualified name (`ModuleAddress`, `ResourceAddress`).

## Skills

`src/TerraformGraph/skills/` is canonical and ships with the module. `.claude/skills/terraformgraph/` is a generated copy: after editing the canonical `SKILL.md`, re-run `Install-TerraformGraphSkill -Path . -Tool Claude -Force` and stage both. Never edit the copy by hand. `.claude/skills/manual-check-list` is a repo-development skill and is not shipped.

## Registry cache

Private `Get-TerraformRegistryCache` reads `$script:TerraformRegistryUserCachePath` (`$env:LOCALAPPDATA\TerraformGraph\registry.json`), else `$script:TerraformRegistryBundledPath` (`data/registry.json`), memoized per file version; tests repoint both with `InModuleScope` and never touch the real paths. `Invoke-Build BuildRegistry` regenerates the bundled file; it is not in the default build and is run when cutting a release (stage the result). Argument completers (`-Provider`, `-Version`, `Get-TerraformRegistryProvider -Name`) never touch the network: they read the cache only and swallow every error.

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
