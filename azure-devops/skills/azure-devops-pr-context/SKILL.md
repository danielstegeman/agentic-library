---
name: azure-devops-pr-context
description: >
  Retrieve full context for an Azure DevOps pull request: metadata (title, author, status,
  branches, commit SHAs, reviewer votes), linked PBI contents (title, description, acceptance
  criteria), reviewer comment threads (all non-system threads with status active/fixed/wontfix),
  and the complete git diff. Use when asked to
  "get the PR context", "get the PR diff", "show me what changed in PR <URL or ID>",
  "fetch the diff for PR <ID>", "what files are in this PR", "get PR metadata",
  or any task that requires inspecting the contents of an Azure DevOps pull request.
  Also triggers when a PR URL is provided alongside a request for code review, analysis,
  impact assessment, or stacking — even if the words "diff" or "context" are never used.
---

# Azure DevOps PR Context

Retrieve full pull request context (metadata + linked PBI contents + diff) from Azure DevOps
using `az repos pr` and local git. `az repos pr` reuses the existing `az login` session — no PAT
or separate credentials required.

---

## Step 1: Parse the Input

Accept the PR in any of these forms:

- **Full URL**: `https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}`
  → extract `Org`, `Project`, `Repo`, `PrId`
- **PR ID only**: e.g. "PR 41032 in my-repo"
  → default ask the user.

---

## Step 2: Run `Get-PrContext.ps1`

The script handles all metadata fetching and diff retrieval in a single call.

```powershell
.\Get-PrContext.ps1 -PrId <id> [-Org <org>] [-Project <project>] [-Repo <repo>] [-RepoPath <path>] [-PathFilter <file1>, <file2>] [-OutputFile <path>]
```

| Parameter | Default | Purpose |
|---|---|---|
| `-PrId` | *(required)* | Pull request ID |
| `-Org` | *(required)* | Azure DevOps organisation |
| `-Project` | *(required)* | Azure DevOps project |
| `-Repo` | *(required)* | Repository name |
| `-RepoPath` | `.` | Path to the local git clone |
| `-PathFilter` | *(none)* | Limit diff to specific paths |
| `-OutputFile` | `$env:TEMP\pr-<id>.md` | Path for the output file; override to write elsewhere |

The script is located in the same folder as this SKILL.md:

```
.\azure-devops-pr-context\Get-PrContext.ps1
```

Run the script — it writes the full output to a file and prints the path:

```powershell
.\Get-PrContext.ps1 -PrId <id>
```

The script prints a single line: `Output written to: <path>`. Use `read_file` on that path to load the PR context.

**Large diffs**: If the diff is large (e.g. contains generated or binary-like files such as XSD schemas), note the output file path and re-run with `-PathFilter` to scope the diff to relevant files.

---

## Step 3: Interpret the Output

The script writes a structured block followed by the diff:

```
## PR #<id> — <title>
- **Author**: <displayName>
- **Status**: Draft | Active | Completed
- **Source**: `<sourceBranch>` → **Target**: `<targetBranch>`
- **Commits**: `<sourceCommit[:8]>` ← `<targetCommit[:8]>`
- **Work items**: #12345, #12346
- **Reviewers**: <name> (<vote>), ...

### PBI #12345 — <title>
- **Type**: Product Backlog Item
- **State**: Active
**Description**: <plain-text description>
**Acceptance criteria**: <plain-text acceptance criteria>

### PR Comments (<N>)
THREAD <id> | status:<label> | <file>:<line>
  [<reviewerDisplayName>] <comment text>
  [<replyAuthorDisplayName>] <reply text>

THREAD <id> | status:active | general
  [<reviewerDisplayName>] <comment text>

### Changed files (<N>)
A  path/to/added.py
M  path/to/modified.py
D  path/to/deleted.py
```

Followed by the full diff in a fenced ` ```diff ` block.

HTML tags and non-breaking spaces in the work item description and acceptance criteria are
stripped to plain text by the script.

**PR comments** (`### PR Comments`): reviewer threads only. TFS system threads (push
notifications, auto-merge events) are dropped. Status labels:

| Label | Meaning |
|---|---|
| `active` | Open reviewer thread |
| `fixed` | Reviewer's concern was addressed |
| `wontfix` | Author responded and reviewer accepted |

If thread fetching fails (e.g. permission issue), a warning is emitted and the section is
omitted — the rest of the output is still written.

**Large PRs** (>50 changed files): the script exits after the file list and prints:

```
LARGE_PR: <N> files changed. Re-run with -PathFilter to scope the diff, or confirm to proceed.
```

In that case, ask the user which paths to include and re-run with `-PathFilter`.

---

## Error Handling

| Situation | Action |
|---|---|
| `az devops pr show` fails (not logged in) | Ask user to run `az login` and retry |
| PR not found | Confirm PR ID and repo name with the user |
| `git fetch` fails (branch deleted) | Script falls back to fetch-by-commit SHA automatically |
| Commits not reachable locally | Report which SHA is missing; suggest `git fetch --all` |
| Diff is empty | Report "No changes between the two commits" — do not invent changes |
| Repo GUID needed by other MCP calls | Extract from `az devops repo show` or ask the user |
