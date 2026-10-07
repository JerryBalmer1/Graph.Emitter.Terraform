---
name: manual-check-list
description: Maintain manual-check-list.md at the repo root, the paste-and-verify checklist for every exported function and parameter set. Use whenever an exported function, parameter, parameter set, default display, or documented example is added, changed, or removed.
---

# Manual check list

`manual-check-list.md` at the repo root is the human-run companion to Pester. Pester proves the code works; the checklist proves the documented way of using the module works when a person pastes it into a terminal. Every item is something Jerry copies, runs, and eyeballs against an Expect line.

## When to update it

In the same task as any change to:
- an exported function (add, rename, remove)
- a parameter, parameter set, alias, default value, or ValidateSet
- default display properties (Update-TypeData)
- an example in comment-based help or README

If the task touches none of these, leave the file alone. Never update it in a separate task; the checklist and the code land together.

## File layout

```
# TerraformGraph manual check list

Module version: <ModuleVersion from psd1>
Last updated: <YYYY-MM-DD>

## 0 Setup
### 0.1 Fresh import
...

## 1 Get-TerraformAST
### 1.1 -Path (default set)
### 1.2 -Path -Recurse
...

## 2 ConvertTo-TerraformJson
...
```

One `##` section per exported function, numbered in FunctionsToExport order. Section 0 is always Setup. Within a section, one `###` item per parameter set or distinct behaviour worth seeing, numbered `N.M`. Never renumber existing items; append new ones and leave removed items' numbers unused with a one-line note "(removed in 0.x.0)" so references stay stable.

## Item format

Every item has exactly these parts, in this order:

```
### 1.2 -Path -Recurse

Parses the directory and every subdirectory.

```powershell
Set-Location 'C:\__Code\TerraformGraph'
Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
Import-Module .\src\TerraformGraph\TerraformGraph.psd1 -Force
Get-TerraformAST -Path .\infra -Recurse | Group-Object File | Select-Object Count, Name
```

Expect: four files listed, including modules\network\modules\endpoint\main.tf.

Pester: "parses infra with -Path -Recurse and includes nested modules"
```

Rules:
- The code block is self-contained. It always starts with the three setup lines above so it works in any shell and can never resolve to the installed TerraformAST module. No item depends on a previous item having run.
- Expect is one or two sentences describing what appears on screen: counts, property names, a specific value, or the exact error text. Not "it works".
- Pester names the test(s) in tests/TerraformGraph.Tests.ps1 that cover the same behaviour, by their It description in quotes. If none exists, write `Pester: none` so the gap is visible. Do not write a test just to fill this line; report the gap instead.
- Error cases are items too (missing path, wrong extension, modules.json absent). Expect states the error text.
- Use the infra/ fixture for everything that can use it. If an item needs a throwaway directory, create it under $env:TEMP inside the block and remove it at the end of the same block.

## Procedure

1. Read manual-check-list.md and the current psd1 FunctionsToExport.
2. For each function you added or changed, read its parameter block and help examples from the psm1.
3. Add or edit items. Run every block you add or edit in a fresh process (`pwsh -NoProfile -File` on a temp script, or `pwsh -NoProfile -Command`) and confirm the output matches Expect before writing it down. Fix the Expect line, not the output.
4. Update Module version and Last updated at the top.
5. Stage the file. Do not commit.
6. In your task report, list the item numbers added, changed, or marked removed, one line each.

## Do not

- Do not put checklist items anywhere else (README, CLAUDE.md, help). Link to them by number if needed.
- Do not paraphrase Pester test names; copy them.
- Do not write an Expect you have not seen.