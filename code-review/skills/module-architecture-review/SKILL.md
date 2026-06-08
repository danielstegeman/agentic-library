---
name: module-architecture-review
description: >
  Review guidance for PowerShell module structure: forced-export conventions,
  duplicate utility detection across modules, and FunctionsToExport manifest
  consistency. Use when the code-review agent reviews PowerShell modules (.psm1/.psd1),
  or when asked to check module boundaries, export lists, or cross-module duplication.
---

# Module Architecture Review

Review standards for PowerShell module structure, export hygiene, and
cross-module consistency. These rules apply to any PowerShell module in
the repository.

---

## 1. Forced-Export Section Convention

Some private helper functions must be exported solely so that Pester can
mock them with `-ModuleName`. These "forced-exports" are not public API —
they should never be called directly by pipeline scripts or other modules.

**Structural requirement:**

Forced-export functions must be placed in a clearly marked section of the
`.psm1` file, separated from genuine public functions:

`powershell
# ── Public functions ─────────────────────────────────────────────

function Invoke-ServiceInstallation { ... }
function Install-ServiceLibrary { ... }

# ── Exported for testing ─────────────────────────────────────────
# Functions below are internal helpers exported only so Pester can
# mock them via -ModuleName. Do not call directly from scripts or
# other modules.

function Get-ServiceConfiguration { ... }
function New-RequiredDirectory { ... }
`

**Flag when you see:**

- A function listed in `FunctionsToExport` that is only called by other
  functions within the same module (never by a pipeline script or external
  caller) and is not in a marked "Exported for testing" section.

- A forced-export function that contains `Write-Information`,
  `Write-Verbose`, or `Write-Warning` calls — forced-exports must be
  silent. Logging belongs in the calling public function.

- A forced-export function with extensive comment-based help (`.SYNOPSIS`,
  `.DESCRIPTION`, `.EXAMPLE`) — keep documentation minimal for internal
  helpers. A single `.SYNOPSIS` line is sufficient.

**The principle:** the reader should be able to look at the module file and
immediately know which functions are the real public API and which exist
only for testability.


---

## 2. Duplicate Utility Detection

When two or more modules contain near-identical helper functions, it signals
either a missing shared module or an incomplete refactor.

**Flag when you see:**

- Two functions in different modules that perform the same logical operation
  (e.g., creating a directory if it doesn't exist, formatting a service name,
  building a path from config values) with only cosmetic differences in
  variable names or logging.

- Copy-pasted code blocks that appear in the `process` bodies of functions
  across different `.psm1` files — even if the function names differ.

- A helper function that is generic (not component-specific) living inside
  a component module. Examples: directory creation helpers, config path
  builders, string formatting utilities. These are candidates for a shared
  module even if they currently have only one caller.

**Review technique:** when reviewing a component module, search the workspace
for the core operation of each helper (e.g., `New-Item -ItemType Directory`,
`Get-ServiceConfig`, `Copy-Item ... -Recurse`). If the same pattern exists
in another module, flag the duplication.

**The principle:** utilities used by multiple components should exist in
exactly one place. Duplication across modules is a maintenance hazard.

---

## 3. FunctionsToExport Consistency

The `.psd1` manifest's `FunctionsToExport` array must exactly match the
functions that should be accessible from outside the module.

**Flag when you see:**

- Functions defined in the `.psm1` that are missing from `FunctionsToExport`
  but are called by pipeline scripts or other modules — they work by accident
  (PowerShell exports all functions when `FunctionsToExport` is `'*'` or missing)
  but will break if the manifest is tightened.

- `FunctionsToExport = '*'` — this disables export control entirely. All
  manifests must list functions explicitly.

- Functions listed in `FunctionsToExport` that don't exist in the `.psm1` —
  stale entries from renamed or deleted functions.

- `FunctionsToExport` entries that are not sorted alphabetically — sorting
  makes diffs cleaner and prevents merge conflicts.

**The principle:** the manifest is the module's contract. It must be explicit,
accurate, and sorted.

---

## Applying These Standards

When reviewing PowerShell module files, work through each section above.
Severity classification:

| Severity | When to use |
|----------|-------------|
| **Critical** | `FunctionsToExport = '*'`; functions called externally but not exported explicitly |
| **Major** | Forced-export function that logs or has full doc; duplicate utility across modules; stale `FunctionsToExport` entries |
| **Minor** | Missing "Exported for testing" section header; unsorted `FunctionsToExport`; generic helper in a component module with only one current caller |

For each finding, reference the specific file and line, state what the issue is,
and cite which section above it violates (e.g., "Section 1: Forced-Export Convention —
Get-ATSConfiguration is a forced-export but contains Write-Information calls").
