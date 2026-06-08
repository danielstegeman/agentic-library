---
name: git-worktree
description: 'Create a git worktree for a feature branch without causing branching or PR issues. Use when asked to "create a worktree", "work in a new worktree", "set up a worktree from a branch", or any task that should be done in an isolated working directory on a separate branch. Ensures the remote branch exists before the worktree is created, preventing fast-forward accidents where commits land directly on the target branch.'
argument-hint: 'Describe the work to do and the base branch to start from'
---

# Git Worktree Setup

## The Safe Sequence

Always follow this order — the remote branch must exist **before** any changes are committed.

### 1. Create and push the empty branch first

```powershell
# Push an empty branch to the remote, starting from the base branch
$base   = 'origin/main'                  # replace with your base branch
$branch = 'feature/my-feature'           # replace with your branch name

git push origin "$base`:refs/heads/$branch"
```

This creates the branch on the remote with no extra commits, giving Azure DevOps a clean diff target.

### 2. Create the worktree from the now-remote branch

```powershell
git worktree add ../my-worktree $branch
```

The worktree path (`../my-worktree`) is sibling to the main repo by convention.

### 3. Work inside the worktree

```powershell
cd ../my-worktree
# edit files
git add <files>
git commit -m "..."
```

### 4. Push changes

```powershell
git push
```

The tracking is already set up (from step 1), so no `-u` flags needed.

### 5. Open the PR in Azure DevOps

- **Source**: `feature/platform/my-feature`
- **Target**: the base branch from step 1
- There will be a clean diff because the base branch has not moved.

---

## Why Order Matters

Creating a worktree with `git worktree add -b <new-branch> <path> origin/<base>` sets the **starting commit** but does not push the branch. If the new branch tip matches an existing remote branch, a subsequent `git push` can fast-forward the target through an already-open PR — landing your commits directly on the target with no diff remaining for a new PR.

Pushing the empty branch first guarantees the remote has a distinct ref for your work before any commits exist on it.

---

## Cleanup

When the PR is merged, remove the worktree and prune the local branch:

```powershell
git worktree remove ../my-worktree
git branch -d feature/platform/my-feature
git remote prune origin
```
