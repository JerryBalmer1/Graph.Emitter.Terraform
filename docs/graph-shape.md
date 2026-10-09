# Graph shape

The property contract of Graph.Emitter.Terraform's graph objects. Every node has `Id` first and `Kind` second; every edge has `From`, `To` and `Kind` first, in that order. This file covers the module graph (`Get-TerraformModuleGraph`, 0.16.0); the schema, variable and resource graphs are described in their command help and in the canonical Id table in [README.md](../README.md#schema-graph-convertto-terraformschemagraph).

## ModuleGraph

`TerraformGraph.ModuleGraph`, one per call to `Get-TerraformModuleGraph`.

| Property | Type | Meaning |
|---|---|---|
| Root | string | The root module directory, resolved. |
| GroupBy | string | `Call` or `Source`: the Id scheme of the nodes (below). |
| Recurse | bool | Whether calls beyond the root's direct children were followed. |
| Nodes | ModuleNode[] | The root first, then calls breadth-first. |
| Edges | ModuleEdge[] | One per module call, in the order the calls were found. |
| Unresolved | ModuleNode[] | Nodes with `Resolved` `$false`. |
| Findings | ModuleNode[] | The same list as `Unresolved`, under the name `ResourceGraph` uses. |
| NodeCount, EdgeCount, UnresolvedCount | int | Script properties: counts of the three lists. |

## ModuleNode

`TerraformGraph.ModuleNode`. Table view: `Id`, `Kind`, `SourceKind`, `Depth`, `Resolved`, `Dir`.

| # | Property | Type | Meaning |
|---|---|---|---|
| 1 | Id | string | Unique in the graph; the scheme depends on `-GroupBy` (below). |
| 2 | Kind | string | Always `Module`. |
| 3 | Name | string | The module block label; `root` for the root. |
| 4 | Key | string | Labels joined with `.` from the root (`network.endpoint`); `''` for the root. Matches the `Key` in `.terraform/modules/modules.json`. |
| 5 | ModuleAddress | string | Terraform's address (`module.network.module.endpoint`); `root` for the root. |
| 6 | Source | string | The literal `source` argument; `$null` for the root and for a non-literal source. |
| 7 | SourceKind | string | `Root`, `Local`, `Registry`, `Git`, `Http`, `S3`, `Gcs` or `Unknown`. Describes the source; it is not the node discriminator (`Kind` is). |
| 8 | Dir | string | The resolved module directory, or `$null`. |
| 9 | Resolved | bool | `$true` when `Dir` was found. |
| 10 | Reason | string | `NonLiteralSource`, `LocalPathMissing`, `NotInitialized`, `Cycle` (Resolved stays `$true`), or `$null`. |
| 11 | ParentKey | string | The calling module's `Key`; `$null` at depth 0 and 1. |
| 12 | Depth | int | 0 for the root, 1 for its direct calls. |
| 13 | Block | Block | The `module` block in the caller's AST; `$null` for the root. |
| 14 | Blocks | Block[] | This module's own parsed blocks; `$null` when not parsed (no `-Recurse`, unresolved, or `Cycle`). |
| 15 | Callers | string[] | The `ModuleAddress` of every call the node stands for: one under `-GroupBy Call`, one or more under `-GroupBy Source`, none for the root. |

## ModuleEdge

`TerraformGraph.ModuleEdge`, one per module call. Table view: `From`, `To`, `Kind`, `Call`, `File`, `Line`.

| # | Property | Type | Meaning |
|---|---|---|---|
| 1 | From | string | The caller's node `Id`. |
| 2 | To | string | The called node's `Id`. |
| 3 | Kind | string | Always `Calls`. |
| 4 | Call | string | The call's `ModuleAddress`; unique per edge under both modes. |
| 5 | Label | string | The module block label. |
| 6 | File | string | The bare file name of the module block (`main.tf`), as on `ResourceNode`. |
| 7 | Line | int | The module block's line in that file. |

## Id rules per -GroupBy mode

The root's Id is `root` in both modes. Ids are unique in every graph (Pester: "keeps Ids unique under both -GroupBy modes when one source is called twice").

| -GroupBy | Nodes | Id |
|---|---|---|
| `Call` (default) | One per module call. | `ModuleAddress`, e.g. `module.network.module.endpoint`. |
| `Source` | One per module source. Calls to the same source collapse into one node; `Callers` lists them. | `source:` + the normalised source (below). A non-literal source: `source:<ModuleAddress>`, one node per call, `Resolved` `$false`, `Reason` `NonLiteralSource`. |

Normalising a source for `-GroupBy Source`:

| SourceKind | Normalised as | Example |
|---|---|---|
| Local | Joined to the caller's directory, made absolute lexically (no existence check), then written relative to the root module with forward slashes and a `./` prefix (`../` when outside the root; an absolute path on another drive stays absolute). Two calls that reach the same directory share a node; the same text from different callers may not. | `./modules/endpoint` called from `modules/network` → `source:./modules/network/modules/endpoint` |
| Registry | Lowercased, with a leading `registry.terraform.io/` dropped; a `//subdir` keeps its case. | `Registry.Terraform.io/Terraform-AWS-Modules/vpc/aws` → `source:terraform-aws-modules/vpc/aws` |
| Git, Http, S3, Gcs, Unknown | Trimmed. | `git::https://example.com/m.git` → `source:git::https://example.com/m.git` |

A collapsed node keeps the first call's (breadth-first) `Name`, `Key`, `ModuleAddress`, `Source`, `Dir`, `ParentKey`, `Depth`, `Block` and `Blocks`. It is `Resolved` `$false`, with that call's `Reason`, when any of its calls is unresolved. Every call is still walked with `-Recurse`, so edges stay one per call and `Call` tells them apart.

`ConvertTo-TerraformResourceGraph` and `ConvertTo-TerraformVariableGraph` read one node per call. Build them from a `-GroupBy Call` graph: a `Source` graph gives them only the first call to each source. The choice is recorded in DECISIONS.md entry 53.
