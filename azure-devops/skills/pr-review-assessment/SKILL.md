---
name: pr-review-assessment
description: >
  Assess pull request review comments on an Azure DevOps PR, categorize each comment
  (Correct-as-is / Needs-fix / Discuss), and draft reply text for every comment that
  the PR author wants to push back on. Offers to post the drafted replies back to the PR
  threads via MCP.
  Use when someone says: "assess the review comments on my PR", "help me respond to PR
  feedback", "which review comments are valid?", "draft replies to the reviewer",
  "go through the PR comments", "Alex left some comments — tell me what to fix",
  or any similar phrasing that involves evaluating or replying to PR review feedback.
  Also trigger when a PR URL is provided and the user asks for help responding to it —
  even if the words "assess" or "review" are never used.
---

# PR Review Assessment

Help the PR author work through incoming review comments: understand the code context,
judge each comment on its merits, draft persuasive replies for push-backs, and optionally
post them straight back to Azure DevOps.

---

## Step 1 — Identify the PR

Accept the PR in any of these forms:

- **Full URL**: `https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}`
  → extract `org`, `project`, `repo`, `prId`
- **PR ID only** with an implied repo (e.g. "PR 42 in my-repo")
  → ask the user for `org`, `project`, and `repo` if not inferable from context

---

## Step 2 — Fetch PR Metadata, Diff, and Threads

Run the following in parallel:

### 2a — PR metadata + diff

Follow the [azure-devops-pr-context skill](../azure-devops-pr-context/SKILL.md) to obtain full
PR context. The skill runs `Get-PrContext.ps1` which retrieves metadata via `az devops` and the
diff via local git in a single call:

```powershell
.\Get-PrContext.ps1 -PrId <prId> [-Org <org>] [-Project <project>] [-Repo <repo>]
```

The output contains:
- PR title, author, status, source branch, target branch, commit SHAs, reviewer votes
- Full git diff (or file-filtered subset for large PRs — see the skill for the guard)

### 2b — Review threads

```
mcp_microsoft_azu_repo_list_pull_request_threads
  repositoryId: <repo GUID>
  pullRequestId: <prId>
```

The response is large (50–100 KB) because Azure DevOps injects dozens of TFS system threads
for every push to the branch. **Immediately filter it** using the script in this skill folder:

```powershell
.\Filter-PrThreads.ps1 -Path "<content.json path from the MCP result>"
```

The script drops all TFS system threads (those with no `status` field) and formats the
remaining reviewer threads as compact plain text. Status labels in the output:

| Label | Meaning |
|---|---|
| `active` | Open — needs assessment |
| `fixed` | Reviewer's concern was addressed |
| `wontfix` | Author responded and reviewer accepted |

Use the **plain-text output** for all subsequent steps.
Focus assessment on `active` threads. `fixed` and `wontfix` threads provide context but are
already handled — include them in the summary table but skip reply drafting for them.

---

## Step 3 — Enrich Each Thread with Code Context

For each thread:

1. Locate the file path and line number referenced in the thread's `threadContext` field.
2. Extract the relevant code snippet from the diff (the changed hunk around those lines).
   If the thread has no file reference (general PR comment), mark it as "general".
3. Present a compact view:

```
## Thread <N> — <file>:<line>
**Reviewer**: <displayName>
**Comment**: "<comment text>"

**Code context**:
```<language>
<relevant hunk>
```

---

## Step 4 — Assess Each Thread

For every thread, reason about:
- Is the reviewer's concern technically correct?
- Does it reflect a style rule, safety issue, or factual error?
- Is there a defensible reason to keep the code as-is (performance, contract, business rule)?
- Is the concern ambiguous or subjective?

Then assign one of three verdicts:

| Verdict | Meaning |
|---|---|
| **Code-is-correct** | The code is right; the reviewer's concern does not apply or is based on a misreading |
| **Needs-fix** | The reviewer has a valid point; the code should change |
| **Discuss** | Reasonable people could disagree, or more information is needed |

State the verdict clearly, then give a one-sentence rationale.

---

## Step 5 — Draft Replies for Correct-as-is Verdicts

For every **Correct-as-is** thread, draft a reply that:
- Acknowledges the reviewer's concern respectfully (don't be dismissive)
- Explains concisely *why* the code is correct as written
- Points to the specific line, contract, or reasoning that supports the decision
- Stays professional and collegial in tone — this is a conversation, not a debate

Keep replies to 2–4 sentences unless a longer explanation is truly needed.

**Example reply pattern** (adapt to context):
> Thanks for flagging this. The `X` is intentional here because `<reason>`. Keeping it this way
> ensures `<benefit>`, which is why we chose `<approach>`. Happy to discuss further if that
> doesn't address the concern!

---

## Step 6 — Present the Summary

Output a structured assessment:

```
# PR Review Assessment — PR <ID>: <title>

## Summary
| # | File | Reviewer | Verdict | One-liner |
|---|------|----------|---------|-----------|
| 1 | ... | ... | Correct-as-is | ... |
| 2 | ... | ... | Needs-fix | ... |

## Correct-as-is — Drafted Replies
### Thread 1 — <file>:<line>
<drafted reply>

## Needs-fix — Action Items
### Thread N — <file>:<line>
**What to change**: <description>

## Discuss — Open Questions
### Thread N — <file>:<line>
**Why it's unclear**: <explanation>
```

## step 6b - Save report in the correct artifacts directory
---

## Step 7 — Offer to Post Replies

After presenting the summary, ask:

> "Would you like me to post any of these replies to the PR? I can post individual replies or
> all Correct-as-is replies at once. Just say which ones (e.g. 'post threads 1 and 3' or 'post
> all correct-as-is')."

For each confirmed reply, post it using:

```
mcp_microsoft_azu_repo_reply_to_comment
  repositoryId: <repo GUID>
  pullRequestId: <prId>
  threadId: <threadId>
  content: <drafted reply text>
```

Confirm each post with "✓ Reply posted to thread <N>".

---

## Notes

- If the diff is not available locally (branch deleted), rely on the thread's `threadContext`
  (file path + line numbers) and note that full code context is limited.
- Do not change the thread status (e.g. mark as "fixed") unless the user explicitly asks.
- If the user disagrees with a **Correct-as-is** verdict, revise the draft or change the verdict
  — the user knows the business context better than you do.
- For **Needs-fix** items, do not implement the fix in this skill — offer to hand off to the
  normal code editor flow.
