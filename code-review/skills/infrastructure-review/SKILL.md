---
name: infrastructure-review
description: >
  Review guidance for infrastructure-as-code files: Azure DevOps pipelines (YAML),
  PowerShell deployment scripts, Ansible playbooks, and configuration templates.
  Provides review standards covering hardcoding detection, parameterization,
  idempotency, security, consistency, and IaC best practices.
  Use when reviewing PRs or files involving deployment automation, pipeline YAML,
  infrastructure scripts, server provisioning, or component installation — even if
  the user just says "review my PR" and the changed files happen to be infrastructure
  code. Also trigger when the code-review agent needs review standards for pipeline,
  Ansible, or infrastructure dimensions.
---

# Infrastructure-as-Code Review

Review standards for deployment automation, pipelines, and infrastructure code.
These guidelines apply to Azure DevOps pipeline YAML, PowerShell deployment scripts,
Ansible playbooks/roles, and configuration templates used in server provisioning
and component installation.

The goal is to catch the kinds of issues that commonly slip through infrastructure PRs:
values that should be parameterized, operations that aren't safe to re-run, inconsistent
patterns across similar files, and security gaps in privilege handling.

---

## 1. Hardcoding & Parameterization

Infrastructure code is particularly prone to embedding environment-specific values
directly in scripts and templates. These become maintenance traps and deployment hazards.

**Flag when you see:**
- File paths containing version numbers, server names, or environment identifiers
  baked into the code rather than sourced from variables or parameters
- Port numbers, database names, or service URLs written as literals instead of
  drawn from configuration
- Values that differ between environments (dev/test/acceptance/production) appearing
  as constants rather than parameters
- Credentials, connection strings, or API keys present in any form other than
  secure variable references (Key Vault, variable groups, encrypted secrets)

**The principle:** any value that could change between environments, instances,
or versions should come from a parameter, variable, or configuration file —
never from a literal in the code. When in doubt, parameterize.

---

## 2. Idempotency

Infrastructure operations frequently run multiple times — during retries, re-deployments,
or configuration drift correction. Code that assumes it runs exactly once causes failures
on the second run or creates duplicates.

**Flag when you see:**
- Create/add operations without a preceding existence check (e.g., creating a Windows
  service that may already exist, adding a registry key without checking first)
- File operations that fail if the target already exists (copy without overwrite,
  directory creation without `-Force` or equivalent)
- Database operations like INSERT without upsert semantics or existence guards
- Resource provisioning that doesn't handle the "already exists" case gracefully
- Scripts that append to files without checking whether the content is already present

**The principle:** every operation should produce the same end state whether it runs
once or ten times. If re-running a step would fail or create duplicates, it needs
a guard.

---

## 3. Security & Privilege

Infrastructure code runs with elevated permissions and manages sensitive resources.
Missing privilege declarations or exposed secrets are critical findings.

**Flag when you see:**
- Tasks that modify system state (services, registry, system files) without explicit
  privilege escalation declarations (e.g., `become: true` in Ansible, `RunAs` in
  PowerShell, elevated agent pools in pipelines)
- Secrets passed as plain-text command-line arguments (visible in process listings
  and logs) rather than environment variables or secure files
- Service accounts or credentials with broader permissions than the task requires
- Missing or overly permissive file/folder ACLs on deployed artifacts
- Pipeline tasks downloading artifacts over HTTP instead of HTTPS

**The principle:** infrastructure code should declare the minimum required privileges
explicitly and never expose secrets in logs, process arguments, or source control.

---

## 4. Consistency Across Similar Components

Infrastructure codebases often have parallel structures — multiple components installed
the same way, multiple environments configured with the same pattern. Inconsistency
between these parallel structures signals either a bug or an unfinished refactor.
This applies both **across files** (sibling components) and **within a single file**
(repeated blocks inside the same script or pipeline).

**Flag cross-file inconsistency when you see:**
- Structurally similar files (e.g., component install scripts) that handle the same
  concern differently without a documented reason
- Task/step naming conventions that vary across files (e.g., some use
  `"Component - Action"` while others use `"Action for Component"`)
- Parameter sets that differ between similar components when they logically shouldn't
- Error handling present in some component scripts but missing in structurally
  equivalent ones
- Shared templates or modules that are used by some components but bypassed by others
  doing the same thing inline
- Template reference styles that differ between components (e.g., relative paths in
  one file, absolute paths in another for the same shared template)

**Flag intra-file duplication when you see:**
- The same block of steps or code appearing two or more times in a single file
  with only minor variation (e.g., PSModulePath setup copy-pasted in multiple tasks
  within the same pipeline)
- Identical validation, setup, or teardown logic repeated inside multiple functions
  or steps in the same script/YAML file rather than extracted to a shared helper
  or a pipeline step template
- Variables initialized the same way in multiple places within the same file

**The principle:** similar things should look similar, and repeated things should be
extracted. When reviewing a component, compare it against its siblings *and* scan the
file itself for copy-pasted blocks. Divergence across files should be intentional and
documented; duplication within a file should be refactored.

---

## 5. Error Handling & Resilience

Infrastructure operations interact with external systems (databases, registries,
network services) that can fail. Silent failures during deployment lead to
partially configured systems that are hard to diagnose.

**Flag when you see:**
- Tasks or commands with error suppression (`ignore_errors`, `continueOnError`,
  `-ErrorAction SilentlyContinue`) without a comment explaining why the error
  is expected and safe to ignore
- Missing `errorActionPreference: 'stop'` in PowerShell pipeline tasks (the
  default is `Continue`, which swallows errors)
- No validation step after critical operations (e.g., installing a service without
  verifying it started, writing a config file without checking the result)
- Catch blocks that swallow exceptions without logging or re-throwing
- Long scripts with no intermediate checkpoints — if step 15 of 20 fails, is the
  state recoverable?

**The principle:** errors during infrastructure operations should be loud and visible.
Suppressing errors is sometimes necessary but should always be an explicit, documented
decision with a specific reason.

---

## 6. Module & Abstraction Usage

Most infrastructure tools provide declarative modules or cmdlets for common operations.
Falling back to raw shell commands when a module exists leads to more fragile,
harder-to-maintain code.

**Flag when you see:**
- Shell/command execution (`win_shell`, `Invoke-Expression`, `cmd /c`) for operations
  that have a dedicated module or cmdlet (e.g., using `net stop` instead of
  `Stop-Service` or the `win_service` Ansible module)
- String concatenation to build command lines instead of using structured parameters
- Manual file manipulation (regex replacements on config files) when a template
  module or configuration-as-data approach is available
- Custom reimplementation of functionality already provided by a shared module
  or template in the codebase

**The principle:** prefer declarative, structured operations over imperative shell
commands. Modules handle edge cases (quoting, error codes, idempotency) that raw
commands miss.

---

## Applying These Standards

When reviewing infrastructure files, work through each section above and flag
violations. For Azure DevOps pipeline YAML files, use the dedicated
`pipeline-yaml-review` skill which covers pipeline-specific patterns
(template paths, naming, parameter design, DRY, operational hygiene).

Severity classification:

| Severity | When to use |
|----------|-------------|
| **Critical** | Security gaps (exposed secrets, missing privilege controls), operations that will fail on re-run in production |
| **Major** | Hardcoded environment-specific values, missing error handling on critical operations, significant inconsistency with sibling components |
| **Minor** | Naming inconsistencies, redundant conditions, style deviations, opportunities to use modules instead of shell commands |

For each finding, reference the specific file and line, state what the issue is,
and cite which section above it violates (e.g., "Section 2: Idempotency — service
creation has no existence check").
