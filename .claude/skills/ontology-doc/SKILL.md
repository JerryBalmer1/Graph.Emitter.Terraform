---
name: ontology-doc
description: Keep ONTOLOGY.md, the agent and ontology door to TerraformGraph, in step with the code. Use whenever the Id scheme, a node or edge type, a finding kind, a terminating error id, a bundled data shape (registry.json, bundle.json, packs, docs cache, drawers.json, map.json, classifier files), or a planned ontology feature changes.
---

# ONTOLOGY.md

`ONTOLOGY.md` at the repo root is the door for readers who came for the agent story: one Id across code, schema, docs and drawers. It is dense and must explain in one screen what the module is. `README.md` (kept by the `readme` skill) is the sysadmin door and never repeats this material.

## When to update it

In the same task as any change to:
- the canonical Id scheme (any node Id format in CLAUDE.md "Canonical ids")
- a node or edge type (`TerraformGraph.*Node`, `TerraformGraph.*Edge`) or a property the terminology table names
- a finding kind (`NoDocPage`, `NoSubcategory`, `UnmappedSubcategory`, resource `Reason` values, `unmatched` docs)
- a terminating error id (`FullyQualifiedErrorId`) the "What agents get" section lists, or a new one an agent would branch on
- the shape or provenance fields of bundled data: `data/registry.json`, `data/bundle.json`, pack `manifest.json`, the docs cache document, `classifiers/drawers.json`, `classifiers/map.json`, classifier files
- a "Not here yet" item shipping, slipping or changing target version

## Rules

- First non-blank line: the banner, one `>` line in the same style as README's line 1. Second non-blank line: the backlink to `README.md`. Keep both first; Pester ("keeps the two doors") checks them.
- Sections stay in this order: What this is; Why Terraform is an unusually good ontology source; What agents get; Terminology; Facts and opinions; Not here yet.
- Terminology names match exported names exactly. The "In the module" column holds only backticked names of three kinds: an exported command (`Get-TerraformGraphBundle`), a typed object or one of its properties (`TerraformGraph.ClassifiedType.Drawer`), or a data file path relative to the module or repo root (`classifiers/map.json`). Pester ("resolves every term in ONTOLOGY.md's terminology table") resolves every one and fails on anything else, so rename the table in the same task as the code.
- The term list is Id, node, edge, finding, pack, bundle, drawer, classifier, map row, source, era, in that order. Adding a term means updating the Pester expectation in the same task.
- Facts versus opinions: registry, schema, docs and parsed code are facts; drawers, map rows, classifiers and DECISIONS.md are opinions held as data with reasons. A new data file goes in one list or the other, never both.
- Every claim about errors, exit codes or provenance must be true of the current code. Check the error id with `Select-String` in the psm1 before naming it.
- Dense, plain sentences. No marketing words. A table beats a paragraph.

## Procedure

1. Read the change (psm1, CLAUDE.md "Canonical ids", the data file) and the current ONTOLOGY.md.
2. Edit the affected sections. Keep the banner and backlink first.
3. Run the two Ontology tests in a fresh process: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -FullNameFilter 'Ontology*' -CI"`.
4. Stage ONTOLOGY.md. Do not commit.
5. In your report, list the sections and terminology rows you changed.

## Do not

- Do not copy README material (install, examples, parameter tables) into ONTOLOGY.md; link README instead.
- Do not list a term the module has no name for; if a concept is planned, put it under "Not here yet" with a target version and point the term at the closest existing name.
