# azure-devops-pr-context

Copilot skill that retrieves full pull request context from Azure DevOps: PR metadata, linked PBI contents, and the complete git diff.

---

## Requirements

| Requirement | Notes |
|---|---|
| Azure CLI (`az`) | v2.30.0 or higher |
| `azure-devops` CLI extension | Install once: `az extension add --name azure-devops` |
| Authenticated session | Run `az login` before using the skill |
| Local git clone | The repo must be cloned locally; pass `-RepoPath` if not running from inside it |

---

## How it works

1. **Copilot detects a PR URL or ID** in your message and invokes this skill automatically.
2. `Get-PrContext.ps1` is run with the extracted PR ID and optional filters.
3. The script calls `az repos pr show` to fetch PR metadata and reviewer votes, then `az boards work-item show` for each linked PBI (description + acceptance criteria).
4. It uses local `git diff` between the source and target commit SHAs recorded by Azure DevOps.
5. Output is written to **stdout**. Copilot captures it and saves it to `/memories/session/pr-context.md` via the `memory` tool so it is available for follow-up tasks.

---

## Running manually

```powershell
# Minimal — from inside the repo
.\Get-PrContext.ps1 -PrId 43235

# With explicit repo path
.\Get-PrContext.ps1 -PrId 43235 -RepoPath C:\repos\myproject

# Scope the diff to specific folders (useful for large PRs)
.\Get-PrContext.ps1 -PrId 43235 -PathFilter 'SRC/Frontend', 'Inra/pipelines'

# Write output to a custom file instead of the default session memory path
.\Get-PrContext.ps1 -PrId 43235 -OutputFile C:\Temp\pr43235.md

# Suppress file output entirely
.\Get-PrContext.ps1 -PrId 43235 -OutputFile ''
```

---

## Large PRs

If a PR has more than 50 changed files and no `-PathFilter` is specified, the script stops after the file list and prints:

```
LARGE_PR: <N> files changed. Re-run with -PathFilter to scope the diff, or confirm to proceed.
```

Tell Copilot which paths you care about and it will re-run with `-PathFilter`.

---

## Session memory

After the script runs, Copilot saves the captured stdout to `/memories/session/pr-context.md` using `memory create` (or `memory str_replace` on subsequent runs). The `memory` tool is a logical abstraction — it does not expose physical filesystem paths, so the script always writes to stdout only.

---

## Files

| File | Purpose |
|---|---|
| `SKILL.md` | Copilot skill definition — tells the agent when and how to use the skill |
| `Get-PrContext.ps1` | PowerShell script that does the actual fetching |
| `README.md` | This file |
