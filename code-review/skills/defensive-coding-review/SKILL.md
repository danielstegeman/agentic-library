---
name: defensive-coding-review
description: >
  Review guidance for detecting defensive coding anti-patterns in PowerShell:
  redundant guards, weak validation, unnecessary return values, and
  warn-instead-of-throw patterns. Use when the code-review agent fans out
  a Defensive Coding dimension, or when reviewing PowerShell modules and
  scripts for unnecessary complexity. Also trigger when asked to check for
  redundant code, over-defensive patterns, or unnecessary error handling.
---

# Defensive Coding Review

Review standards for detecting code that works but adds unnecessary complexity
through over-cautious guards, weak validation, and superfluous return values.

These patterns make functions longer, harder to read, and harder to maintain
without adding safety. They often signal that the author is uncertain about
the function's contract or its callers' expectations.

---

## 1. Redundant Guards

A guard is redundant when the operation it protects already handles the
guarded case, or when a subsequent operation would fail with a clearer
error anyway.

**Flag when you see:**

- `Test-Path` before `New-Item -Force` — the `-Force` flag already creates
  the item if it doesn't exist and is a no-op if it does. The `Test-Path`
  adds a line of code and a filesystem call for no benefit.

- `Test-Path` before an operation that will throw on the next line anyway —
  e.g. checking whether a file exists before calling `Start-Process` on it.
  The process call already throws `FileNotFoundException` with a clear message.
  The manual guard just adds code that duplicates the runtime check.

- Existence checks before `Copy-Item -Force`, `Remove-Item -ErrorAction
  SilentlyContinue`, or other cmdlets that already handle the missing case.

- Null checks before operations on variables that were already validated by
  `[ValidateNotNullOrEmpty()]` on the parameter — the validation attribute
  already guarantees non-null at invocation time.

**The principle:** if the next operation already handles the edge case (via
`-Force`, by throwing, or by design), don't add a guard before it. Trust the
tools. Redundant guards are noise, not safety.

---

## 2. Weak Validation

Validation is weak when it checks one failure case but ignores equally
invalid states, giving a false sense of safety.

**Flag when you see:**

- Checking `Count -eq 0` but not checking for other invalid states (e.g.,
  a hashtable with 1 entry when the minimum is 5, or a collection with
  `` entries). Either validate thoroughly or don't validate at all.

- Type-checking a parameter that already has a type constraint on the
  `param()` block — PowerShell enforces the type at binding time.

- Validating a parameter's format when a `[ValidatePattern()]` or
  `[ValidateScript()]` attribute would catch it at binding time with a
  better error message.

- Range checks on values that are already constrained by
  `[ValidateRange()]`.

**The principle:** validation should be complete or absent. Partial validation
is worse than no validation because it suggests the remaining cases are
covered when they aren't. Prefer parameter attributes over manual checks.

---

## 3. Warn-and-Continue vs Throw

When a function detects a condition that prevents it from doing its job,
it should throw — not warn and return a fallback value. Warning and
continuing pushes the failure downstream where it's harder to diagnose.

**Flag when you see:**

- `Write-Warning` followed by `return $null` (or `return $false`) when
  the condition means the function cannot fulfil its contract. If the
  caller asked you to create a registry file and there are no settings,
  that's a failure — throw.

- Functions that return `` as a "soft failure" signal, forcing every
  caller to check for ``. Prefer throwing and letting the caller
  wrap in `try/catch` if they want to handle it.

- Warning about a missing prerequisite but continuing execution anyway —
  if the prerequisite matters, stop; if it doesn't, remove the warning.

**The principle:** a function's contract is either fulfilled or an exception
is thrown. `Write-Warning` + `return ` is not a contract — it's an
ambiguous signal that callers will forget to check.

---

## 4. Unnecessary Return Values

Functions that return status objects (`@{ Success = True; Message = '...' }`)
or boolean success flags when PowerShell's exception model already
communicates failure.

**Flag when you see:**

- Returning `True` on success when the function could simply return
  nothing (success is implied by not throwing).

- Returning a hashtable with `Success` and `Message` keys when `throw`
  on failure and silent return on success conveys the same information
  without forcing callers to inspect a return value.

- Returning a count of work done (e.g., "N files copied") when no caller
  uses the count. If the count matters, document it in the function
  contract; if it doesn't, remove it.

**The principle:** in PowerShell, the absence of an exception means success.
Don't invent a second signalling channel (return values) unless the caller
genuinely needs structured data from the operation.

---

## 5. Counting and Reporting Work

Functions that count operations (files copied, services started, entries
processed) and report the count without any caller using it.

**Flag when you see:**

- A counter variable (`++`) that is only used in a final
  `Write-Information` message and never returned or acted upon.

- Logging the number of items processed when the function doesn't
  validate the count against an expected value — if you don't check
  it, don't count it.

- Iterator variables maintained solely for progress reporting in
  non-interactive scripts.

**The principle:** if an operation succeeds, trust it. Counting work items
is useful when the count is validated (e.g., expected N files, got M) or
returned to the caller. Counting only to log the number is noise.

---

## Applying These Standards

When reviewing code, work through each section above. Severity classification:

| Severity | When to use |
|----------|-------------|
| **Critical** | Warn-and-continue on a condition that should stop execution (Section 3); validation that masks a real failure |
| **Major** | Redundant guards that add significant code bulk (Section 1); unnecessary return values that create a misleading API contract (Section 4) |
| **Minor** | Single redundant `Test-Path`; counting without using the count (Section 5); weak validation on non-critical paths (Section 2) |

For each finding, reference the specific file and line, state what the issue is,
and cite which section above it violates (e.g., "Section 1: Redundant Guards —
Test-Path before New-Item -Force is unnecessary").
