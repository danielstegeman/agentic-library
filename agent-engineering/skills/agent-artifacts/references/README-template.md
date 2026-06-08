# Agent Artifacts

This folder contains **AI agent working memory** for the current branch. It is committed to the branch so that plans, reports, and notes are shared across sessions and agents working on the same task.

## Structure

| Folder | Contents |
|---|---|
| `plans/` | Implementation plans, design decisions, task breakdowns |
| `reports/` | Research results, analysis outputs, assessment reports |
| `notes/` | Scratch notes, open questions, context dumps |

Files are named with a date prefix: `YYYY-MM-DD-<descriptive-name>.md`

---

## ⚠️ IMPORTANT: Delete before completing the pull request

This folder is **temporary**. It must not be merged into `main` or `master`.

Before completing the PR, run:

```powershell
git rm -r .agent-artifacts/
git commit -m "chore: remove agent artifacts before PR completion"
```

Reviewers: if you see `.agent-artifacts/` in a PR diff, request that it be removed before approving.
