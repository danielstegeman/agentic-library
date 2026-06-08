---
name: git-squash
description: Squash all commits on the current branch into a single commit, then force-push to the remote. Use when the user says "squash commits", "clean up branch history", "squash before PR", "combine my commits", "flatten commits", "squash my branch", or wants to tidy up a messy commit history before merging or opening a pull request.
---

# Git Squash

Squash all commits on the current branch (since it diverged from the base branch) into a single clean commit, then optionally force-push to the remote.

## Overview

This skill uses `git reset --soft` to collapse all branch-only commits into a single staged change, then creates one new commit with a message supplied by the user. It is safer and simpler than interactive rebase for whole-branch squashing.

## Workflow

Work through these steps in order. Never mutate history before completing all pre-flight checks.

### Step 1 — Detect context

```bash
git branch --show-current
git symbolic-ref refs/remotes/origin/HEAD
```

Determine:
- **Current branch** (`BRANCH`)
- **Base branch** (typically `main`, `master`, or `develop` — extract from the symbolic ref output, e.g. `refs/remotes/origin/main` → `main`)

If `git symbolic-ref` fails (no remote or detached HEAD), ask the user to specify the base branch explicitly.

### Step 2 — List commits to squash

```bash
git log <base-branch>..HEAD --oneline
```

Show the output to the user so they know exactly what will be squashed.

If the output is **empty** (branch has no unique commits), abort and tell the user there is nothing to squash.

### Step 3 — Pre-flight checks

Run all checks before making any changes.

#### 3a. Refuse to squash a protected branch

If `BRANCH` is `main`, `master`, `develop`, or `trunk`, abort immediately:

> "Squashing is not allowed on protected branches. Switch to a feature branch first."

#### 3b. Check for uncommitted changes

```bash
git status --porcelain
```

If the working tree is dirty, warn the user:

> "You have uncommitted changes. These will be included in the squash commit as staged changes. Consider stashing or committing them first."

Ask whether to continue or abort.

> ⚠️ **Data loss risk**: If the user proceeds with uncommitted changes and later undoes the squash using `git reset --hard ORIG_HEAD`, those uncommitted working-tree changes **will be permanently destroyed**. If there is any chance they will undo, insist they stash (`git stash`) or commit first.

#### 3c. Check for child branches

The goal is to find branches that diverged from a commit **unique to BRANCH** — commits that will be rewritten by the squash. This must not flag branches that diverged from upstream history that BRANCH merely includes (e.g. when BRANCH is rebased on top of another feature branch).

**Correct approach — check against unique commits only:**

First, collect the SHAs of commits unique to BRANCH (not reachable from `<base-branch>`):

```bash
git log <base-branch>..HEAD --format=%H
```

This is the **unique set**. Store it as `UNIQUE_COMMITS`.

Then, for each local branch `B` ≠ `BRANCH`:

```bash
MERGE_BASE=$(git merge-base <B> HEAD)
# Only flag B if its merge-base is in UNIQUE_COMMITS
if UNIQUE_COMMITS contains MERGE_BASE:
    # True child — branched from a commit that will be squashed
```

**Do NOT** compare against `BASE_TIP = git rev-parse <base-branch>`. That check is incorrect when BRANCH itself was rebased on top of another feature branch: other branches may have their merge-base inside that upstream history (included in BRANCH's history but not unique to it), causing false positives.

In PowerShell:

```powershell
$uniqueCommits = git log <base-branch>..HEAD --format="%H"
git for-each-ref --format="%(refname:short)" refs/heads/ |
  Where-Object { $_ -ne "<BRANCH>" } |
  ForEach-Object {
    $b = $_
    $mergeBase = git merge-base $b HEAD 2>$null
    if ($mergeBase -and $uniqueCommits -contains $mergeBase) {
      "CHILD BRANCH: $b"
    }
  }
```

If any child branches are found, **warn the user explicitly** before proceeding:

> "⚠️ The following branches were created from commits that will be squashed:
>
> - `feature/child-branch`
> - `hotfix/other-branch`
>
> After squashing, these branches will no longer share history with `BRANCH`. You will need to rebase each one manually:
>
> ```bash
> git rebase --onto <BRANCH> <old-parent-commit> <child-branch>
> ```
>
> Do you want to continue with the squash anyway?"

Wait for the user to confirm before continuing.

> ⚠️ **If the child-branch detection script errors or produces unexpected output**, fall back to a manual check before proceeding:
> ```bash
> git branch -v
> git log <base-branch>..HEAD --oneline
> ```
> If any branch tip matches a commit in the squash range, treat it as a child. When in doubt, warn the user.

### Step 4 — Get commit message from the user

Present the list of commits again (from Step 2) and ask:

> "Please provide the commit message for the squashed commit:"

Wait for the user's message before proceeding. Do not auto-generate it.

### Step 5 — Perform the squash

```bash
git reset --soft $(git merge-base HEAD <base-branch>)
git commit -m "<user-provided message>"
```

This collapses all branch-only commits into a single staged snapshot and creates one new commit. The working tree is unchanged.

### Step 6 — Verify the result

Show the user the new state before touching the remote:

```bash
git log --oneline -5
git diff <base-branch>..HEAD --stat
```

Ask explicitly:

> "Does this look correct? Type 'yes' to push to the remote, or 'no' to abort."

If the user says no, explain they can run `git reflog` to recover the previous state (the pre-squash tip is still in the reflog).

### Step 7 — Force push

Before pushing, check whether anyone else may have pushed to this branch:

```bash
git fetch origin
git log origin/<BRANCH>..HEAD --oneline    # outgoing (local-only) commits
git log HEAD..origin/<BRANCH> --oneline    # incoming (remote-only) commits
```

If there are **incoming** commits (others pushed since you last fetched): **do not push**. Tell the user to review those remote commits and decide whether to incorporate them before force-pushing, since force-pushing will permanently discard them from the remote.

On confirmation:

```bash
git push --force-with-lease origin <BRANCH>
```

`--force-with-lease` is safer than `--force`: it refuses to push if the remote has commits that you haven't fetched, protecting against overwriting someone else's work.

If the push fails because the remote has new commits, tell the user to `git fetch` first and review what changed before retrying.

## Safety Rules

- **Never** use `git push --force`. Always use `--force-with-lease`.
- **Never** squash on main/master/develop/trunk.
- **Never** skip the verification step — always show the result before pushing.
- **Always** mention reflog recovery if anything goes wrong: `git reflog` shows the pre-squash state for 30+ days.
- If the user asks to undo after a local squash (before pushing), run: `git reset --hard ORIG_HEAD` — **but warn them first**: this destroys any uncommitted working-tree changes. Only safe if the working tree was clean before the squash, or if changes were stashed.
