---
name: readme
description: Keep README.md, the sysadmin door to TerraformGraph, in step with the code. Use whenever a public function, parameter, parameter set, pack, bundled data file, or Invoke-Build task is added, changed, or removed, and before reporting any task that touched one.
---

# README

`README.md` is the door for people who run Terraform: sysadmins, platform engineers, CI authors. It says what each command does, shows a pasteable example, and states numbers that were measured. The agent and ontology story lives in `ONTOLOGY.md` (kept by the `ontology-doc` skill), not here.

## When to update it

In the same task as any change to:
- an exported function (add, rename, remove) or its parameters, parameter sets, defaults or output type
- packs, caches or bundled data (`data/registry.json`, `data/bundle.json`, `classifiers/`)
- an Invoke-Build task (`BuildRegistry`, `BuildSchemaPack`, `BuildClassifier`, `HarvestBundleDocs`, `CheckBundle`, ...)
- a number the README quotes (provider counts, page counts, drawer counts, elapsed times)

If the task touches none of these, leave the file alone.

## Rules

- Line 1 is the ontology callout and nothing else: one `>` line that says the module was built as an ontology layer for AI agents and links `ONTOLOGY.md`. Keep it to one line. Never move it below the banner.
- After line 1, never mention ontology. No "ontology", "semantic layer", "knowledge graph" prose. If a change needs that kind of explanation, it goes in `ONTOLOGY.md`. Pester ("keeps the two doors") fails if `ontolog` appears after line 1.
- The CI example stays on the first screen: one line that exits non-zero when module depth exceeds 3, with the exit codes stated. If `Get-TerraformModuleGraph` or `ModuleNode.Depth` changes, fix and rerun it.
- Each public function is shown in the section for its area (parse, graphs, registry, packs, docs, classifiers, bundle, skills) with at least one example you have run. Use exact command and parameter names; never paraphrase a parameter.
- Numbers are measured, dated and attributed to the run that produced them (for example "HarvestBundleDocs on 2026-10-07"). Never round a count you can state exactly.
- "Source version" matches `ModuleVersion` in the psd1.
- Release steps are stated in the order CLAUDE.md gives them; README links to the task names, CLAUDE.md is the source of truth for the order.

## Procedure

1. Read the psd1 `FunctionsToExport` and the parameter blocks of whatever changed.
2. Edit the matching README section. Run every example you add or change in a fresh `pwsh -NoProfile` process and paste only output you saw.
3. Check line 1 and that `ontolog` appears nowhere else: `Select-String -Path README.md -Pattern 'ontolog' | Select-Object LineNumber`.
4. Run `Test-TerraformGraphBundle -BundlePath .\src\TerraformGraph\data\bundle.json` and read the rows that are not Fresh. If the README quotes bundled data that is stale, say so in your report instead of quoting it as current.
5. Stage README.md. Do not commit.
6. In your report, list the README sections you changed, one line each, and the Test-TerraformGraphBundle counts (Fresh, Stale, Missing).

## Do not

- Do not add ontology prose, terminology tables, or the facts/opinions discussion here.
- Do not put manual checklist items here; link to `manual-check-list.md` by item number if needed.
- Do not edit `.claude/skills/terraformgraph/` by hand; it is generated.
