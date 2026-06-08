---
name: pr-stacking
description: 'Split large pull requests into a stack of smaller, reviewable PRs with correct base branches. Use when asked to "split this PR", "stack PRs", "this PR is too large", "break up these changes", or when a PR mixes many different kinds of changes. Creates stacked branches with proper 3-way merge delta extraction, opens PRs in Azure DevOps with correct stacked targets, and leaves a retargeting checklist for post-merge steps.'
---

# PR Stacking

## When to Use This Skill

- A PR is too large for effective code review
- Changes naturally layer: shared infrastructure → new feature → tests
- A PR mixes unrelated concerns (config, code, tests)
- A reviewer asks to split a PR before they will approve it

## Core Concept

**PR stacking** means each PR in a series targets the *previous PR's branch* rather than trunk:

```
trunk
  └── branch-A        PR 1  (targets trunk)
        └── branch-B      PR 2  (targets branch-A)
              └── branch-C    PR 3  (targets branch-B)
```

Reviewers see each layer in isolation. The diff for PR 2 only shows what branch-B adds on top of branch-A — not the combined change.

## ⚠️ Critical: Never Use `git checkout <branch> -- <path>`

This copies the **full file state** from the source branch, silently reverting any changes that landed on trunk *after* the source branch was created. Always use a 3-way merge to extract deltas (see Workflow 1).

---

## Workflow 1: Split an Existing PR

Use this when a PR already exists and you need to split it.

### Step 0: Gather Information

**If starting from a PR URL or PR ID**, first load the
[azure-devops-pr-context skill](../azure-devops-pr-context/SKILL.md) and run `Get-PrContext.ps1`
to resolve the source branch, target branch, and exact merge-commit SHAs:

```powershell
.\Get-PrContext.ps1 -PrId <id>
```

Use the `sourceBranch` as `<source-branch>` and `targetBranch` as `<trunk-branch>` in all
subsequent steps. The commit SHAs from the script output are the authoritative diff boundary.

**If working from local branches directly**, skip the above and proceed with:

```powershell
# Identify what changed vs trunk
git diff --name-status <trunk-branch>...<source-branch>

# Find the common ancestor of trunk and source branch
git merge-base origin/<trunk-branch> origin/<source-branch>
# Note the commit hash — this is the MERGE BASE
```

Use the change list to decide how many slices make sense. Good split points:
- Shared modules / infrastructure changes (no new features)
- New production code (depends on slice 1)
- Tests (depends on slice 2)

**Create a backup tag before touching anything:**

```powershell
git tag backup/<source-branch>-presplit origin/<source-branch>
```

This preserves the original state. If anything goes wrong mid-split, `git checkout -b recovery backup/<source-branch>-presplit` restores a clean starting point.

### Step 1: Create a Clean 3-Way Merged Reference

```powershell
# Create a temp branch at the tip of trunk
git checkout -b temp/merged origin/<trunk-branch>

# Merge the source branch using 3-way merge (no commit yet)
git merge origin/<source-branch> --no-ff --no-commit
# Git resolves conflicts automatically where possible.
# Resolve any remaining conflicts manually, then: git add <file>

git commit -m "temp: 3-way merge of <source-branch> onto <trunk-branch>"
```

This branch represents the correct final state — all source changes applied on top of the latest trunk.

### Step 2: Create Each Slice Branch

For each slice, branch off the **previous slice** (or trunk for the first), then apply only the relevant file paths from `temp/merged`:

```powershell
# Slice 1 — branch from trunk
git checkout -b feature/<slice-1-name> origin/<trunk-branch>
git diff origin/<trunk-branch> temp/merged -- <paths-for-slice-1> | git apply --index
git commit -m "feat(<scope>): <description of slice 1>"
git push -u origin feature/<slice-1-name>

# Slice 2 — branch from slice 1
git checkout -b feature/<slice-2-name> feature/<slice-1-name>
git diff origin/<trunk-branch> temp/merged -- <paths-for-slice-2> | git apply --index
git commit -m "feat(<scope>): <description of slice 2>"
git push -u origin feature/<slice-2-name>

# Repeat for additional slices...
```

**Verify each slice contains only the expected files:**
```powershell
git diff origin/<trunk-branch>...feature/<slice-n-name> --stat
```

### Step 3: Open PRs in Azure DevOps

Create PRs in order, each targeting the **previous slice's branch**:

| PR | Source branch | Target branch |
|----|---------------|---------------|
| 1/N | `feature/<slice-1>` | `<trunk-branch>` |
| 2/N | `feature/<slice-2>` | `feature/<slice-1>` |
| 3/N | `feature/<slice-3>` | `feature/<slice-2>` |

Use `mcp_microsoft_azu_repo_create_pull_request` for each. Include in the description:
- "Split from PR #XXXXX — PR N of N"
- Which PR it is stacked on (e.g. "Stacked on PR #41331")
- What the subsequent PRs contain, so reviewers have context

```json
{
  "repositoryId": "<repo-id>",
  "sourceRefName": "refs/heads/feature/<slice-2>",
  "targetRefName": "refs/heads/feature/<slice-1>",
  "title": "feat(<scope>): <description> [2/3]",
  "description": "Split from PR #XXXXX. PR 2 of 3 — stacked on PR #YYYYY.\n\n..."
}
```

### Step 4: Add Reviewers and Link Work Items

```json
// mcp_microsoft_azu_repo_update_pull_request_reviewers
{ "repositoryId": "...", "pullRequestId": <id>, "reviewerIds": ["<id>"], "action": "add" }

// mcp_microsoft_azu_wit_link_work_item_to_pull_request (if needed)
```

### Step 5: Abandon the Original PR

Update the original PR's title to indicate it is superseded, then set status to Abandoned:

```json
// mcp_microsoft_azu_repo_update_pull_request
{
  "repositoryId": "...",
  "pullRequestId": <original-id>,
  "status": "Abandoned",
  "title": "<original title> [SUPERSEDED by #A, #B, #C]"
}
```

### Step 6: Clean Up

Verify all slices are pushed and correct before deleting the temp branch:

```powershell
# Confirm each slice has the expected diff vs trunk
git diff origin/<trunk-branch>...feature/<slice-n-name> --stat
```

Only delete once all slices are verified:

```powershell
git branch -d temp/merged
```

> ⚠️ Use `-d` (safe delete), **not** `-D` (force delete). If `temp/merged` has unmerged content, `-d` will refuse — this is your safety net that content was not lost. Investigate before overriding.

### Step 7: Leave the Retargeting Checklist

Print the following for the user to keep — **this cannot be automated in this session**:

---

**📋 Retargeting checklist — action required after each merge**

Azure DevOps does NOT automatically retarget stacked PRs when a base branch merges.

> ⚠️ **Rebase conflict risk**: When running `git rebase origin/<trunk-branch>`, Git may encounter conflicts. Resolve them carefully — accept your **slice's version** for changes unique to the slice, and the **trunk version** for changes that belong to trunk. Resolving conflicts in the wrong direction (accepting the wrong side) will silently lose content after the force-push. Always run `git diff origin/<trunk-branch>..HEAD --stat` after the rebase to sanity-check the file list before pushing.

After **PR 1/N (`feature/<slice-1>`) merges**:
1. In AzDO: edit PR 2/N → change target branch from `feature/<slice-1>` → `<trunk-branch>`
2. In terminal:
   ```powershell
   git fetch origin
   git checkout feature/<slice-2>
   git rebase origin/<trunk-branch>
   git push --force-with-lease origin feature/<slice-2>
   ```

After **PR 2/N (`feature/<slice-2>`) merges**:
1. In AzDO: edit PR 3/N → change target branch from `feature/<slice-2>` → `<trunk-branch>`
2. In terminal:
   ```powershell
   git fetch origin
   git checkout feature/<slice-3>
   git rebase origin/<trunk-branch>
   git push --force-with-lease origin feature/<slice-3>
   ```

*(Repeat for each subsequent PR in the stack.)*

Do NOT delete source branches of intermediate PRs until the downstream PR has been retargeted.

---

## Workflow 2: Build a Stack Proactively

Use this when starting new work that you know will be layered.

```powershell
# Slice 1 off trunk
git checkout -b feature/<slice-1> origin/<trunk-branch>
# ... make changes ...
git push -u origin feature/<slice-1>

# Slice 2 off slice 1
git checkout -b feature/<slice-2> feature/<slice-1>
# ... make changes ...
git push -u origin feature/<slice-2>
```

Open PRs with the same stacked targeting as Workflow 1, Step 3. No temp branch needed since you control the delta from the start.

---

## Pitfalls

| Pitfall | What happens | Fix |
|---------|-------------|-----|
| `git checkout <branch> -- <path>` | Copies full file state, reverts concurrent trunk changes | Use `git diff trunk temp/merged -- <paths> \| git apply --index` |
| Force-pushing without `--force-with-lease` | Silently overwrites remote commits you haven't seen | Always use `--force-with-lease` |
| Deleting the base branch before retargeting downstream PR | AzDO marks downstream PR as broken | Retarget first, then delete |
| Forgetting `--no-commit` on the temp merge | Auto-commits with a merge commit, confusing the temp branch purpose | Always include `--no-commit` |
| Not verifying each slice's diff | Accidentally including files from the wrong slice | Run `git diff <trunk>...<slice> --stat` after every push |

## Tool Reference

| Tool | Purpose |
|------|---------|
| `mcp_microsoft_azu_repo_get_pull_request_by_id` | Retrieve existing PR details (reviewers, work items, source/target) |
| `mcp_microsoft_azu_repo_create_pull_request` | Create a new PR with specified source/target |
| `mcp_microsoft_azu_repo_update_pull_request` | Abandon a PR or update its title/target |
| `mcp_microsoft_azu_repo_update_pull_request_reviewers` | Add reviewers to PRs |
| `mcp_microsoft_azu_repo_list_repos_by_project` | Resolve repository ID from name |
| `mcp_microsoft_azu_wit_link_work_item_to_pull_request` | Link work items to PRs |

Requires the `activate_pull_request_management` tool to be called first if PR tools are not yet available.
