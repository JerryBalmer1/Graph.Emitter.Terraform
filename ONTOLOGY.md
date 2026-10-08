> **TerraformGraph is an ontology layer for AI agents over Terraform.** One Id names a thing in your code, in the provider's schema, in its docs and in its drawer.

Here for the PowerShell module, install steps and examples? Read [README.md](README.md).

## The ontology was already there

If you build ontologies or agent memory, Terraform has probably never been on your list of sources. Look at what is already in place.

Every Terraform provider publishes a typed schema for every version it releases: each resource type, each attribute with its type, whether it is required, optional or computed, and how blocks nest. The registry serves those versions for 428 official and partner providers (registry harvest of 2026-10-07), alongside a documentation page per type, written by the provider's authors and filed under a label they chose. The whole stack pins to that vocabulary: `required_providers` names the provider's address, the lock file pins its exact version and checksums, and `terraform validate` rejects any block that does not fit the schema.

So your infrastructure code is already a set of instances. `resource "azurerm_key_vault" "main"` is one individual of exactly one class, `azurerm_key_vault`, at exactly one schema version, checked against that class by the tool before anything is deployed. The classes, their properties, their versions and their instances exist and are kept correct every day, by the people who ship providers and by the people who run plans.

Nobody built a Terraform ontology because nobody had to: it was already there. What was missing was the join. TerraformGraph adds one Id that names the same thing in your code, in the schema, in the docs and in a reviewable grouping, and a record of where each fact came from and how fresh it is. The rest of this page is that join.

## What this is

A PowerShell module that turns Terraform into named, typed, joined data an agent can query instead of guess at. Four layers share one key:

| Layer | Where it comes from | Example for one Azure key vault |
|---|---|---|
| Code | your `.tf` files, parsed with HashiCorp's own HCL library | `module.app/resource/azurerm_key_vault.main` (a `TerraformGraph.ResourceNode`) |
| Schema | `terraform providers schema -json`, cached per provider version | `registry.terraform.io/hashicorp/azurerm/resource/azurerm_key_vault` (a `TerraformGraph.SchemaNode`) |
| Docs | the registry's markdown page for that type | the same Id (a `TerraformGraph.ProviderDoc`) |
| Drawer | the provider's own doc label ("Key Vault") through a reasoned map | `security` (a `TerraformGraph.ClassifiedType`) |

The resource node's `SchemaId` is the schema node's `Id`, which is the doc page's `Id`, which is what the classifier keys on. No lookup tables, no fuzzy matching: a join either holds or is reported.

## Why Terraform is an unusually good ontology source

- **Typed.** Every resource, data source, block and attribute a provider accepts is declared with a type, required/optional/computed flags and nesting rules. The vocabulary is a schema, not prose.
- **Versioned.** Each provider version publishes its own schema and docs. `azurerm 5.8.0` means one exact vocabulary; a change is a new version, not a silent edit.
- **Registry-published.** registry.terraform.io lists every provider, tier, version and publish date, and serves each version's docs. Everything downstream (lock files, `required_providers`, modules) pins to those addresses and versions, so the ontology's keys are the ones your code already uses.
- **Already joined in practice.** A `resource "azurerm_key_vault"` block is an instance of exactly one schema type at exactly one provider version. TerraformGraph only has to make that edge explicit (`InstanceOf`).

## What agents get

Named things, not guesses:

- **Stable Ids.** Schema `<address>/resource/<type>`, `<address>/data/<type>`, `<address>/config/<name>`, `<parent Id>/<block or attribute>`; code `<module>/resource/<type>.<name>`, `<module>/var/<name>`, `<module>/local/<name>`, `<module>/output/<name>`; docs on the schema Id, `<address>/guide/<slug>`, `<address>/unmatched/<category>/<slug>`.
- **Stable error ids.** Terminating errors carry a `FullyQualifiedErrorId` you can branch on, never a message to parse: `SchemaNotCached`, `ProviderDocNotCached`, `ProviderDocHarvestFailed`, `RegistryProviderNotResolved`, `ClassifierMapInvalid`, `ClassifierNotFound`, `BundleNotFound`, `BundleInvalid`, `BundleNotFresh`, `ParserUnavailable`, among others (42 in 0.14.1; `HclParseError` is the one non-terminating id, one per file that does not parse). Each message names the command that fixes it; every one is raised through a single helper, and Pester keeps the full list of ids with their fixing commands and fails on an id that is not in it or on any bare `throw`.
- **Exit codes.** Gates are one line: `pwsh -NoProfile -Command "Import-Module TerraformGraph; Test-TerraformGraphBundle -Strict | Out-Null"` exits 1 when anything is stale; a depth or findings check exits with whatever `exit` you give it. PowerShell 7.4+ is required so a failure is terminating and visible.
- **Findings, not errors.** What the data cannot place is data: a resource whose type is not in the schema (`Reason` `TypeNotInProvider`), an unknown argument (`UnknownAttributes`), a doc page with no schema type (`unmatched`), a type no drawer takes (`NoDocPage`, `NoSubcategory`, `UnmappedSubcategory`). Graphs still build; findings are counted.
- **Provenance on bundled data.** The registry cache carries `harvestedOn`; schema and docs packs carry sha256 in `manifest.json`; docs carry `harvestedOn` and the `schemaVersion` their Ids were checked against; classifiers carry `docsVersion` and `mapVersion` (a hash of the map rows); `data/bundle.json` records which versions of each were present and, in `sources`, the upstream endpoints each kind of data comes from, the pages that document them, the command that pulls it and when it last did; `Test-TerraformGraphBundle` says which are Fresh, Stale or Missing, and every row that is not Fresh carries a command that shows the change (`InspectAction`) and one that makes it (`RecommendedAction`).
- **Promote or leave.** Harvests write to the user's caches; the module's shipped data changes only through a build task. An agent that finds stale data shows the diff and refreshes it only when its task is about that data.
- **Nothing hidden on the network.** Reading never downloads. Only `Update-TerraformRegistryCache`, `Update-TerraformProviderDocCache`, the two pack commands, `Get-TerraformProviderSchema` (it runs `terraform init`) and `Test-TerraformGraphBundle -Online` go out, and only when called.

## Terminology

| Term | In the module | What it is |
|---|---|---|
| Id | `TerraformGraph.SchemaNode.Id`, `TerraformGraph.ResourceNode.SchemaId`, `TerraformGraph.ProviderDoc.Id` | The canonical string for one thing. Unique per document; the join key across code, schema, docs and drawers. `Path` is display only. |
| node | `TerraformGraph.SchemaNode`, `TerraformGraph.ResourceNode`, `TerraformGraph.VariableNode`, `TerraformGraph.ModuleNode` | One named thing in a graph, with `Id` first and `Kind` second. Kinds: `Provider`, `Resource`, `DataSource`, `Function`, `Block`, `Attribute` (a schema type, block or attribute); `Resource`, `DataSource` (a block in one module); `Variable`, `Local`, `Output`; `Module` (a module call, or one module source with `-GroupBy Source`). |
| edge | `TerraformGraph.SchemaEdge`, `TerraformGraph.ResourceEdge`, `TerraformGraph.VariableEdge`, `TerraformGraph.ModuleEdge` | A typed relation between two Ids, with `From`, `To` and `Kind` first: `Contains`, `InstanceOf`, `Reference`, `Argument`, `OutputReference`, `Calls` (a module call). |
| finding | `TerraformGraph.ClassifierFinding.Finding`, `TerraformGraph.ResourceNode.Reason`, `TerraformGraph.CachedDoc.UnmatchedCount` | Something the data cannot place, reported as data rather than thrown. |
| pack | `Get-TerraformSchemaPack`, `Get-TerraformDocPack` | A gzipped schema or docs file for one provider version, attached to a release with its sha256 in `manifest.json`. |
| bundle | `Get-TerraformGraphBundle`, `TerraformGraph.BundleEntry`, `data/bundle.json` | The provider set the shipped data covers (registry tiers, extra addresses, exclusions) and what was harvested for each. |
| sources | `Get-TerraformGraphBundle`, `TerraformGraph.BundleSource`, `TerraformGraph.BundleSource.HarvestedBy`, `data/bundle.json` | Where each kind of bundled data (registry, schemas, docs, classifiers, skills; cmdb reserved) is pulled from: upstream URLs, the pages that explain them, the command that pulls it and when it last did. `Get-TerraformGraphBundle -Sources` lists them. |
| drawer | `TerraformGraph.ClassifiedType.Drawer`, `TerraformGraph.DrawerSummary`, `classifiers/drawers.json` | One of a fixed list of top-level groups (network, compute, storage, ..., unclassified) a type falls into so a view can collapse. |
| classifier | `New-TerraformClassifier`, `Get-TerraformClassifier`, `TerraformGraph.Classifier` | One provider version's type-to-drawer table, generated from its schema and docs through the map. |
| map row | `classifiers/map.json`, `classifiers/DECISIONS.md` | One judgement: a provider label (or type prefix) to a drawer, with a one-sentence reason, a date and who added it. |
| source | `TerraformGraph.ClassifiedType.Source`, `TerraformGraph.Classifier.Source` | Which kind of map row placed a type: `subcategory` (the provider's own doc label) or `prefix` (a type-name prefix, for providers that publish no labels). |
| era | `TerraformGraph.RegistryProvider.Versions`, `Get-TerraformRegistryProvider` | A span of provider versions treated as one vocabulary. Not modelled yet; the raw material (every version with its publish date) is in the registry cache. |

## Facts and opinions

**Facts** are copied from their source and never edited: the registry list and versions, provider schemas, registry docs and their subcategory labels, and your parsed code. When a fact is missing or does not join, that is a finding.

**Opinions** are data too, with reasons:

- `classifiers/drawers.json` is the fixed drawer list.
- `classifiers/map.json` maps labels and type prefixes to drawers; every row has a `reason`, `addedOn` and `addedBy`, and the map is linted before use.
- `classifiers/DECISIONS.md` is an append-only log: Question, Call, Rejected, Why, Cost if wrong, for every judgement including each label left unmapped.
- Classifiers never change an Id, a node count or an edge. Pester asserts it. Swap in your own map with `-MapPath` and `-ClassifierPath` and the facts stay the same.

## Not here yet

| Planned | What it adds | Target |
|---|---|---|
| view | A collapsed graph: drawers as nodes, types and instances folded inside, for diagrams and agent context windows. | 0.17.0 |
| compare | Two schema versions side by side: added, removed and changed types and attributes, as findings. | 0.18.0 |
| eras | Provider version spans as first-class nodes, derived from compares (an era ends where a compare finds a breaking change), so "which schema era does this repository target" is a query. | 0.19.0 |

Shipped in 0.14.0: the harvest and sources contract. Registry harvests survive the registry's rate limit and resume from a partial file, `data/bundle.json` names its sources, and every stale bundle check names the command that fixes it. Shipped in 0.14.1: the error contract made true (every terminating error through one helper, checked by Pester), `Test-TerraformGraphBundle -Scope Repo` as the release gate, and a module that imports on any platform, with the parser commands throwing `ParserUnavailable` off Windows x64. Shipped in 0.15.0, the release before view: the module source split one function per file, with no change to any command, Id, node, edge or error. Shipped in 0.16.0: the module graph contract. `ModuleNode` has `Id` first and `Kind` `Module` second, `ModuleEdge` has `From`, `To`, `Kind` `Calls` and a `File`, Ids are unique under both `-GroupBy` modes (`-GroupBy Source` collapses calls to one source into one `source:` node with `Callers`), and the envelope carries `Findings`; property tables in [docs/graph-shape.md](docs/graph-shape.md).
