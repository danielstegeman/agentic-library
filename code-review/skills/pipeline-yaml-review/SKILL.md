---
name: pipeline-yaml-review
description: >
  Review guidance for Azure DevOps pipeline YAML files: template referencing,
  naming conventions, parameter design, DRY patterns, and operational hygiene.
  Use when the code-review agent reviews Azure DevOps pipeline YAML files,
  or when asked to check pipeline structure, template usage, or YAML conventions.
  Complements infrastructure-review (which covers generic IaC patterns) with
  ADO-pipeline-specific rules.
---

# Azure DevOps Pipeline YAML Review

Review standards specific to Azure DevOps pipeline YAML files. These rules
complement the generic infrastructure-as-code review with team and platform
conventions for pipeline definitions.

---

## 1. Template Path References

Templates must be referenced by absolute path from the repository root,
not by relative path with parent traversal.

**Flag when you see:**

- Relative template references using `../` (e.g.,
  `template: ../../shared/ServerSetup.yml`). These are fragile — they
  break when the calling file is moved and are hard to follow in review.

- Inconsistent referencing: some templates referenced absolutely, others
  relatively within the same pipeline. Pick one style; absolute is
  preferred.

**Correct:**
`yaml
- template: /pipelines/shared/server-setup.yml
`

**Incorrect:**
`yaml
- template: ../../shared/ServerSetup.yml
`

**The principle:** absolute paths from the repo root are self-documenting
and resilient to file moves. Relative paths with `../` create coupling
between the file's location and its template references.

---

## 2. File Naming Conventions

Pipeline YAML files must use kebab-case (lowercase with hyphens).

**Flag when you see:**

- PascalCase or camelCase YAML filenames (e.g., `ServerSetup.yml`,
  `installArena.yml`). These should be `server-setup.yml`,
  `install-arena.yml`.

- Underscores in file names except for template files that start with `_`
  (e.g., `_Build.yml`) — the underscore prefix convention for templates
  is an accepted exception.

- Mixed naming styles across related pipeline files in the same directory.

**The principle:** consistent naming reduces cognitive load. Kebab-case
is the established convention for YAML configuration files.

---

## 3. Parameter Design

Pipeline parameters must be typed and designed for reusability.

**Flag when you see:**

- Parameters without explicit type declarations (e.g., missing `type: string`
  or `type: boolean`). Type declarations enable pipeline UI validation and
  make the contract explicit.

- Opaque compound parameters (e.g. a single `environmentConfig` string)
  when the value contains multiple distinct pieces that should be separate
  parameters (e.g., `azureServiceConnection` and `keyVaultName`).

- Parameters that are only used once in the template but could be derived
  from other parameters — avoid redundancy.

- Hard-coded values in templates that should be parameters (e.g., a module
  name or path baked into a step when the template is meant to be reusable).

**Correct:**
`yaml
parameters:
  - name: azureServiceConnection
    type: string
  - name: keyVaultName
    type: string
`

**Incorrect:**
`yaml
parameters:
  - name: environment
    # no type declaration
`

**The principle:** parameters are the template's API. They should be typed,
granular, and documented.

---

## 4. DRY Pipeline Patterns

Repeated blocks within or across pipeline files should be extracted into
templates.

**Flag when you see:**

- The same sequence of steps appearing in multiple stages or jobs within
  the same pipeline — extract into a step template.

- Near-identical pipeline files for different components that differ only
  in parameter values — extract the shared structure into a template and
  pass component-specific values as parameters.

- Variable groups or variable blocks that are copy-pasted across stages
  instead of using a template with parameter-driven variable selection.

- Conditionally included steps that could be replaced with a template
  loop or `each` expression.

**DRY technique for stage repetition:**
`yaml
# Use each-expression to iterate over environments
- ${{ each env in parameters.environments }}:
  - stage: Deploy_${{ env.name }}
    ...
`

**The principle:** if you're copy-pasting YAML blocks and changing a few
values, you need a template. Pipeline YAML has `each` expressions and
template parameters to eliminate repetition.

---

## 5. Section Comments

Step groupings within jobs should be marked with clear section comments
that describe the purpose, not the implementation.

**Flag when you see:**

- Missing section comments between logical groups of steps (e.g., all
  service installation steps should be introduced by a comment like
  `# Install MyService`).

- Comments that describe what (`# Run PowerShell script`) instead of why
  or what purpose (`# Install ATS services`).

- Excessive per-step comments when a single section header would suffice.

**The principle:** section comments create scannable structure. They should
mark boundaries between logical phases of a pipeline job.

---

## 6. Operational Hygiene

General operational patterns that prevent silent failures and improve
debuggability.

**Flag when you see:**

- `condition: succeeded()` explicitly stated — this is the default in
  Azure DevOps and adds noise. Remove it unless overriding a different
  parent condition.

- Missing `failOnStderr: true` on PowerShell tasks — unexpected stderr
  output often indicates problems. If stderr is expected, add a comment
  explaining why `failOnStderr` is `false` or absent.

- Artifact downloads without version pinning — pulling "latest" in
  production deployments is risky.

- Manual steps described in comments instead of automated in the pipeline
  (e.g., "manually restart the service after this step").

- Stage or job `displayName` values that don't clearly indicate what the
  stage or job does.

**The principle:** pipelines are executable documentation. They should be
readable, self-contained, and leave no room for manual variance between runs.

---

## Applying These Standards

When reviewing Azure DevOps pipeline YAML files, work through each section
above. Severity classification:

| Severity | When to use |
|----------|-------------|
| **Critical** | Hard-coded credentials or secrets in YAML; missing failOnStderr on tasks that modify system state |
| **Major** | Relative template paths with `../`; untyped parameters; significant duplication across stages/files; compound parameters hiding multiple values |
| **Minor** | Explicit `condition: succeeded()`; naming convention violations; missing section comments; unsorted parameters |

For each finding, reference the specific file and line, state what the issue
is, and cite which section above it violates (e.g., "Section 1: Template Paths —
relative reference with ../../ should use absolute path from repo root").
