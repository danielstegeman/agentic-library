---
name: apm
description: >
  Manage Agent Package Manager (APM) packages and workspace configuration. Use when the
  user asks to install, add, remove, or update APM dependencies; fix apm.yml structure
  errors; author or scaffold a new APM package; or run apm compile/pack/publish. Also
  handles questions about package types (.apm/, skill bundles, skill collections) and
  the apm.lock.yaml lockfile.
---

# Agent Package Manager (APM)

## Overview

APM is a dependency manager for AI agent context — like npm but for skills, prompts, instructions, agents, and MCP servers. One `apm.yml` manifest drives installs across GitHub Copilot, Claude Code, Cursor, Codex, Gemini, and Windsurf.

Docs: https://microsoft.github.io/apm

---

## Package Types

Choose the layout that matches the package's intent. APM detects the type automatically.

| Layout | What it means | When to use |
|---|---|---|
| `.apm/skills/`, `.apm/instructions/`, etc. | Classic APM package — independent primitives | Multiple primitives that consumers can override individually |
| `SKILL.md` at root (+ optional `apm.yml`) | Skill bundle / HYBRID | One cohesive skill with its own agents, assets, scripts |
| `skills/<name>/SKILL.md` at root | Skill collection | Many independent skills in one repo (consumers can cherry-pick) |
| `dependencies.apm` lists local paths | Curated aggregator | Root package that composes other sub-packages |

### Minimal valid package (APM layout)

```
my-pkg/
├── apm.yml
└── .apm/
    └── skills/
        └── my-skill/
            └── SKILL.md
```

### Minimal valid package (skill collection — no `.apm/` needed)

```
my-pkg/
├── apm.yml          # optional; APM synthesizes metadata from dirname if absent
└── skills/
    ├── skill-one/
    │   └── SKILL.md
    └── skill-two/
        └── SKILL.md
```

---

## `apm.yml` — Key Fields

```yaml
name: my-package          # REQUIRED
version: 1.0.0            # REQUIRED (semver)
description: Short tagline
author: Your Name
license: MIT

# Pin output targets (omit to auto-detect from existing folders)
targets:
  - copilot
  - claude

# "auto" = publish all .apm/ content; omit includes when using local path deps only
includes: auto

dependencies:
  apm:
    - owner/repo#v1.0.0                    # GitHub shorthand, pinned tag
    - owner/repo/skills/one-skill          # single skill from a repo
    - ./sub-package                        # local path (curated aggregator)
    - path: ./packages/shared              # local path, object form
  mcp:
    - io.github.github/github-mcp-server   # MCP server from public registry

devDependencies:
  apm:
    - owner/test-helpers                   # excluded from apm pack output
```

---

## Common Workflows

### Install dependencies

```bash
apm install                        # install / update from apm.yml + lockfile
apm install owner/repo#v1.0.0      # add a new dependency and install
apm install --frozen               # CI: fail on lockfile drift, no writes
apm install --dry-run              # preview what would be installed
apm install --target copilot       # deploy to one harness only
```

### Add / remove dependencies

```bash
# Add (edits apm.yml, resolves, writes lockfile, deploys)
apm install owner/repo
apm install --dev owner/test-helpers        # devDependency

# Remove
apm uninstall owner/repo

# Upgrade all to latest matching refs
apm update

# Show what's outdated
apm outdated
```

### Inspect installed packages

```bash
apm list                           # scripts declared in apm.yml
apm view owner/repo                # details for one installed package
apm view owner/repo versions       # available remote tags/branches
```

### Compile and pack

```bash
apm compile                        # write per-target output (.github/, .claude/, …)
apm pack                           # produce distributable bundle in ./build/
apm pack --archive                 # produce .tar.gz
apm preview owner/repo             # dry-run preview of what a package installs
```

### Diagnostics

```bash
apm doctor                         # environment checks (git, auth, network)
apm audit                          # scan for hidden Unicode in installed packages
apm audit --ci                     # exit non-zero if findings exist (CI gate)
apm lock                           # resolve deps and write lockfile only, no deploy
```

---

## Fixing Common Errors

### "missing the required .apm/ directory"

The package has `apm.yml` but APM can't identify its type. Fix by choosing one of:

1. **Curated aggregator** — declare sub-packages as local path dependencies:

   ```yaml
   dependencies:
     apm:
       - ./git-tools
       - ./agent-engineering
   ```

2. **Skill collection** — ensure `skills/<name>/SKILL.md` exists at the repo root.

3. **APM package** — add `.apm/skills/<name>/SKILL.md` (or another primitive type under `.apm/`).

### Testing an aggregator package locally (without pushing to GitHub)

Remote packages cannot reference local paths (`./sub-package`). If a root `apm.yml` uses GitHub references (e.g. `owner/repo/sub-package`), local changes won't be picked up until pushed. To test the full aggregator install locally:

```bash
# 1. Pack the root package into a local bundle
apm pack                              # writes ./build/<package-name> (directory bundle)
apm pack --archive                    # alternatively, writes ./build/<package-name>.tar.gz

# 2. Install from the local bundle into a consumer project
apm install ./path/to/build/<package-name> --target copilot
apm install ./path/to/build/<package-name>.tar.gz --target copilot
```

Re-pack after each change. The bundle install is fully offline and reproduces exactly what a remote consumer would get.

For development on individual sub-packages, work inside the sub-package directory instead — each sub-package is independently installable:

```bash
cd git-tools
apm install --target copilot
```

---

### Lockfile drift in CI

```bash
apm install --frozen     # reproduces the lockfile exactly; fails if apm.yml changed
apm audit --ci           # verifies content hashes of deployed files
```

### Auth failure on private repo

Set the appropriate token environment variable:

```bash
$env:GITHUB_APM_PAT = "<token>"   # GitHub private repos
```

---

## Where Files Are Deployed

| Target | Skills | Instructions | Agents |
|---|---|---|---|
| copilot / vscode | `.github/skills/` | `.github/instructions/` | `.github/agents/` |
| claude | `.claude/skills/` | `CLAUDE.md` | `.claude/agents/` |
| cursor | `.cursor/skills/` | `.cursor/rules/` | `.cursor/agents/` |
| codex | `.agents/skills/` | `AGENTS.md` | `.codex/agents/` |
| all | all of the above | | |

Cross-tool shared path: `.agents/skills/<name>/`

---

## Authoring a New Package

### Scaffold

```bash
# In the new package directory:
apm init                           # writes apm.yml

# For a skill collection, just create skills/<name>/SKILL.md manually
```

### SKILL.md frontmatter

```markdown
---
name: my-skill
description: >
  One-sentence agent-facing description. This is what the runtime uses to
  decide when to invoke the skill.
---
```

### Validate before publishing

```bash
apm compile --dry-run              # check what would be compiled
apm preview                        # preview deployed output for each target
apm pack --dry-run                 # verify the bundle without writing it
```
