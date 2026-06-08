---
name: agent-artifacts
description: 'Manage a .agent-artifacts/ folder in the current repository branch as shared working memory for AI agents. The folder is committed to the branch, survives for the life of the branch, and MUST be deleted before completing the pull request. USE FOR: "create agent artifacts folder", "initialize .agent-artifacts", "set up working memory in the repo", "save this plan to artifacts", "save artifact", "add to agent artifacts", "save this report to artifacts", "store intermediate results", "show artifacts", "list artifacts", "what is in .agent-artifacts", "what have we saved so far". DO NOT USE FOR: session memory (use /memories/session/ for conversation-scoped notes), user memory (use /memories/ for persistent cross-workspace notes), commits (use git-commit skill).'
---

# Agent Artifacts

## Overview

`.agent-artifacts/` is a git-tracked folder that lives on the current branch and acts as **shared working memory** — visible to every agent, every session, and every team member working on that branch.

Use it to store plans, research reports, and intermediate notes that outlive a single conversation.

**Critical rule: delete the folder before completing the pull request.** It must never be merged into the main/master branch.

### When to use `.agent-artifacts/` vs. session memory

| Where | Scope | Use for |
|---|---|---|
| `.agent-artifacts/` | Branch (git-tracked) | Plans, reports, notes shared across sessions and agents |
| `/memories/session/` | Current conversation | In-progress working state for this session only |
| `/memories/` | All workspaces | Personal preferences and patterns |

---

## Folder Structure

```
.agent-artifacts/
├── README.md          ← always present, explains purpose + deletion rule
├── plans/             ← implementation plans, design decisions
├── reports/           ← research, analysis, and assessment outputs
└── notes/             ← scratch notes, open questions, context dumps
```

Files are named with a date prefix: `YYYY-MM-DD-<descriptive-name>.md`

---

## Operations

### Initialize

Use when `.agent-artifacts/` does not yet exist on the current branch.

**Steps:**

1. Determine the skill's own folder path (this SKILL.md lives inside it). Call the setup script from that folder:
   ```powershell
   & 'c:\Users\Stegeman\.personalcopilot\skills\agent-artifacts\references\init-agent-artifacts.ps1'
   ```
   Pass `-RepoRoot` explicitly when the current working directory is not inside the target repository:
   ```powershell
   & 'c:\Users\Stegeman\.personalcopilot\skills\agent-artifacts\references\init-agent-artifacts.ps1' -RepoRoot 'C:\path\to\repo'
   ```

   The script is **idempotent**: running it again on a branch that already has `.agent-artifacts/` is safe — existing directories, `.gitkeep` files, and `README.md` are never overwritten.

2. Confirm to the user: folder created (or already present) and staged. Remind them that it should not be merged into main/master.

---

### Save Artifact

Use when the user wants to persist a plan, report, or note into `.agent-artifacts/`.

**Steps:**

1. Confirm `.agent-artifacts/` exists. If not, run **Initialize** first.

2. Infer the artifact type from context:

   | If the content is... | Save to |
   |---|---|
   | An implementation plan, design decision, task breakdown | `plans/` |
   | A research result, analysis, assessment, audit output | `reports/` |
   | A scratch note, open question, raw context, reminder | `notes/` |

   If unsure, default to `notes/` and tell the user.

3. Generate a filename: `YYYY-MM-DD-<descriptive-name>.md`
   - Use today's date (get it with `Get-Date -Format 'yyyy-MM-dd'` if needed)
   - Make the name kebab-case and descriptive (e.g., `2026-03-25-implementation-plan.md`)

4. Write the file content to the appropriate subfolder.

5. Stage the file:
   ```powershell
   git add .agent-artifacts/<subdir>/<filename>
   ```

6. Confirm the save location and filename to the user.

---

### List Artifacts

Use when the user wants to see what has been saved.

**Steps:**

1. Check if `.agent-artifacts/` exists. If not, report "No agent artifacts folder found on this branch."

2. Show the tree grouped by subfolder, skipping `.gitkeep` files:
   ```powershell
   Get-ChildItem .agent-artifacts -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' } | Select-Object DirectoryName, Name | Format-Table -AutoSize
   ```

3. Present a clean, readable summary. If all subdirs are empty, say so explicitly.

---

## Pre-PR Cleanup

Before completing the pull request, the `.agent-artifacts/` folder **must be removed**:

```powershell
git rm -r .agent-artifacts/
git commit -m "chore: remove agent artifacts before PR completion"
```

This is a manual step — no automation enforces it, but the `README.md` inside the folder contains this reminder, and team members reviewing the PR should flag any `.agent-artifacts/` content lingering in the diff.
