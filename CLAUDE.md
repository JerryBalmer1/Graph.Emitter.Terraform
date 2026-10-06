# TerraformGraph

PowerShell module that parses Terraform `.tf` files into an HCL AST via a Go `c-shared` DLL (`hashicorp/hcl/v2`) and will build a graph of module and provider relationships on top of it (graph layer in progress).

Requires PowerShell 7.4+, Pester 6.1.0+, Terraform CLI (fixture/dev check), and a running Docker engine to build the DLL.

## Layout

```
src/go/                 Go parser (hcl_parser.go) — buildmode=c-shared
src/TerraformGraph/       PowerShell module root
  TerraformGraph.psd1
  TerraformGraph.psm1     P/Invoke + ConvertFrom-TerraformHclFile + exported functions
  TerraformGraph.Json.cs  System.Text.Json serializer/deserializer (TerraformGraph.Json)
  lib/                  TerraformGraph.dll (build artifact, gitignored) + TerraformGraph.h
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
- `Get-TerraformProviderSchema` — run `terraform providers schema -json` in `-Path` (`-OutputFormat OrderedHashtable|Json`).

Planned: `Get-TerraformGraph` (module dependency graph, `-Recurse` via `.terraform/modules/modules.json`) is not implemented yet.

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
