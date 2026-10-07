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
.claude/skills/terraformgraph/  Generated copy of the skill (Install-TerraformGraphSkill)
AGENTS.md               Generated pointer section (Install-TerraformGraphSkill)
infra/                  Fixture modules used by tests and README examples
tests/                  Pester 6.1+ (*.Tests.ps1)
Dockerfile              Cross-compile Windows DLL with mingw from Linux
.build.ps1              InvokeBuild: CheckDependencies, BuildDLL, Test, Package
```

Module name is **TerraformGraph**. Do not reintroduce `PS.Util.Terraform`.

Exported functions:
- `Get-TerraformAST` — parse `.tf` files into HCL blocks; `-Path` directory (optional `-Recurse`) or `-FilePath` one `.tf` file.
- `ConvertTo-TerraformJson` — serialize objects to JSON with no 100-level depth cap (`-Depth`, `-Compress`, `-AsArray`).
- `ConvertFrom-TerraformJson` — parse deep JSON into PSCustomObjects or ordered dictionaries (`-Depth`, `-AsHashtable`, `-NoEnumerate`).
- `Get-TerraformProviderSchema` — run `terraform providers schema -json` in `-Path`, or fetch one provider on demand with `-Provider` (`-Version`, `-WorkingDirectory`, `-Cleanup`, `-Force`; init only when no lock file); `-OutputFormat OrderedHashtable|Json`.
- `Get-TerraformModuleGraph` — module-call graph (Nodes, Edges, Unresolved) from `module` blocks in `-Path`; `-Recurse`, `-GroupBy Call|Source`; non-local sources via `.terraform/modules/modules.json`, never runs init.
- `ConvertTo-TerraformSchemaGraph` — provider schema (dictionary, Json text, or PSCustomObject) to a graph of SchemaNodes (Providers, Nodes, Edges, Summary); `-Provider` filter (throws if absent), `-IncludeFunctions`; attribute `Type` rendered by private `ConvertTo-TerraformTypeString`.
- `ConvertTo-TerraformVariableGraph` — ModuleGraph to a graph of variables, locals and outputs (Nodes, Edges, Unresolved, Skipped, Summary); edges Reference, Argument, OutputReference from declaration expressions and module call arguments only; references found by private `Get-TerraformExpressionReferences`; never reparses.
- `Get-TerraformVariableTrace` — breadth-first walk of a VariableGraph from `-Id` (`-Direction Upstream|Downstream|Both`, `-MaxDepth`); nodes copied with `Distance`, negative upstream under Both.
- `ConvertTo-TerraformResourceGraph` — ModuleGraph (plus optional `-SchemaGraph` array) to an inventory of resource/data blocks (Nodes, Edges, Skipped, Providers, MatchedCount, UnmatchedCount, Findings); `InstanceOf` edge to the schema node when matched; top-level-only `UnknownAttributes`, `UnknownBlocks`, `MissingRequired`; Reason `NoSchemaGraph|ProviderNotInSchemaGraph|TypeNotInProvider`; never reparses.
- `Install-TerraformGraphSkill` — copy `skills/*` into `<Path>/<tool skills folder>/` (`-Tool Claude|Codex|Cursor|Gemini|Copilot|All`, default Claude; `-Force`, `-PassThru` → SkillInstall); creates or appends once to `AGENTS.md` behind `<!-- terraformgraph-skill -->`; no network.
- `Test-TerraformGraphSkill` — per tool SkillStatus (Detected, Installed, Stale, SkillPath); read only. Private `Show-TerraformGraphSkillHint` runs it at import and prints one host line for detected-but-not-installed tools; `TERRAFORMGRAPH_SKILL_HINT=0` silences it. Tool paths live only in the private `$script:TerraformGraphSkillTools` table.

Planned: none.

## Canonical ids

`ConvertTo-TerraformSchemaGraph` node Ids, where `<address>` is the provider_schemas key: Provider `<address>`; provider config Attribute/Block `<address>/config/<name>` (Path `<provider short name>.<name>`, Depth 1, emitted before resources); Resource `<address>/resource/<type>`; DataSource `<address>/data/<type>`; Function `<address>/function/<name>`; Block `<parent Id>/<block name>`; Attribute `<parent Id>/<attribute name>`. `ConvertTo-TerraformVariableGraph` node Ids, where `<module>` is the ModuleAddress (`root` for the root module): Variable `<module>/var/<name>`; Local `<module>/local/<name>`; Output `<module>/output/<name>`. `ConvertTo-TerraformResourceGraph` node Ids: Resource `<module>/resource/<type>.<name>`; DataSource `<module>/data/<type>.<name>` (one per block, no provider in the Id; `SchemaId` holds the schema graph's `<address>/resource/<type>` or `/data/<type>`). `Id` is unique per document; `Path` (`<type>.<block>.<attr>`) is display only and may collide across providers.

## Provider resolution

`ConvertTo-TerraformResourceGraph` resolves each block per module, as Terraform does: local name = type up to the first underscore, or the part before the dot of a `provider = name.alias` argument (sets `ProviderAlias`). It maps through that module's own `terraform { required_providers }` `source` via `ConvertTo-TerraformProviderAddress` (lowercased); undeclared names fall back to `terraform.io/builtin/terraform` for `terraform`, else `registry.terraform.io/hashicorp/<name>`. Child modules never inherit the parent's `required_providers`.

## Naming

Node types never have a property named `Address`, `Count`, `Length`, or any other member of `System.Array` (member access on an array of nodes would hit the array's own member); use a qualified name (`ModuleAddress`, `ResourceAddress`).

## Skills

`src/TerraformGraph/skills/` is canonical and ships with the module. `.claude/skills/terraformgraph/` is a generated copy: after editing the canonical `SKILL.md`, re-run `Install-TerraformGraphSkill -Path . -Tool Claude -Force` and stage both. Never edit the copy by hand. `.claude/skills/manual-check-list` is a repo-development skill and is not shipped.

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
- Do not commit secrets, `.tfstate`, compiled `.dll` files, or `TerraformGraph.zip`.
- PowerShell 7.4+. Go module is `hcl_parser`.
- Fixtures live under `infra/`. Do not resurrect root `test.tf`.

## Do not

- Invent cloud credentials or real provider configs for fixtures.
- Change export names `ParseHCL` / `FreeString` without updating the P/Invoke signatures.
- Put `terraform.exe` in `ExternalModuleDependencies` — that field is PowerShell modules only.
