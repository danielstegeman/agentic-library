---
name: code-review
description: >
  Review the changes since a fixed point (commit, branch, tag, PR, or merge-base) along two
  independent axes — Standards (does the code follow this repo's documented conventions,
  instruction files, and skills, plus a code-smell baseline?) and Spec (does the code match what
  the originating PBI / wiki spec asked for?). Runs both axes as parallel subagents and reports
  them side by side without reranking. Use when the user wants to review a branch, a pull request,
  work-in-progress changes, asks to "review my PR", "review these changes", "review since <ref>",
  "do a code review", or provides a dev.azure.com pull request URL.
---

# Code Review

Two-axis review of the diff between `HEAD` (or a PR's source branch) and a fixed point the user
supplies:

- **Standards** — does the code conform to this repo's documented conventions? This means the
  repo's own docs (`CONTRIBUTING.md`, `copilot-instructions.md`), its **instruction files**
  (`.github/instructions/*.md`), and its **skills** — plus a code-smell baseline that applies
  even when nothing is documented.
- **Spec** — does the code faithfully implement what the originating work item / wiki spec asked
  for?

Both axes run as **parallel subagents** so they don't pollute each other's context, then this
skill aggregates their findings. The two axes are reported **separately and never reranked** —
see [Why two axes](#why-two-axes).

---

## Process

### 1. Pin the fixed point

Resolve exactly one input:

- **Azure DevOps PR URL or ID** (contains `dev.azure.com` or the user says "PR 41032"): use the
  **`azure-devops-pr-context`** skill to fetch PR metadata, the linked PBI, reviewer threads, and
  the full diff. Use the **`org-info`** skill to supply the org/project/repo when only an ID is
  given. The PR's source branch is `HEAD`; its target branch is the fixed point.
- **A git ref** (commit SHA, branch, tag, `main`, `HEAD~5`): the user's ref is the fixed point.
  Capture the diff once with `git diff <fixed-point>...HEAD` (three-dot, against the merge-base)
  and the commit list with `git log <fixed-point>..HEAD --oneline`.
- **Nothing specified**: ask for the fixed point or a PR reference. Do not guess.

Before going further, confirm the ref resolves (`git rev-parse <fixed-point>`) and the diff is
non-empty. A bad ref or empty diff must fail **here** — not inside a subagent.

### 2. Identify the spec source

Find what the change was supposed to do, in this order:

1. **Linked PBI** — when reviewing a PR, `azure-devops-pr-context` already returns the linked
   work item's title, description, and acceptance criteria. Use that as the spec.
2. **Work-item references in commit messages** (e.g. `AB#12345`) — resolve the work item via the
   Azure DevOps skills / MCP.
3. **Wiki spec** — use the **`wiki-search`** skill to look up the feature or component the change
   touches. This is the primary spec source for behaviour that isn't captured in a single PBI.
4. **A path the user passed** as an argument.
5. If nothing is found, ask the user where the spec is. If they say there isn't one, the **Spec**
   subagent skips and reports "no spec available".

### 3. Identify the standards sources

Gather everything in the repo that documents *how code should be written or behave*, and which
of it **applies to the changed files**:

- **Repo docs**: `CONTRIBUTING.md`, `.github/copilot-instructions.md`, any architecture/design
  docs.
- **Instruction files**: read `.github/instructions/*.md`. Each has an `applyTo` glob in its
  frontmatter — only apply an instruction file to a changed file when its glob matches that
  file's path. Adherence to these instruction files **is** a Standards concern.
- **Skills**: identify skills whose domain covers the changed files (by their `description`
  trigger conditions) and treat their documented rules as standards. Skill adherence **is** a
  Standards concern — a change that ignores a directly-applicable skill's guidance is a finding.

On top of whatever the repo documents, the Standards axis always carries the **smell baseline**
below — a fixed set of code smells that applies even when a repo documents nothing. Two rules
bind it:

- **The repo overrides.** A documented repo standard, instruction file, or skill always wins;
  where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"),
  never a hard violation. Skip anything tooling already enforces (Black, PSScriptAnalyzer,
  linters, formatters).

**Smell baseline** — match each against the diff; report only what the change introduces:

- **Mysterious Name** — a name that doesn't reveal what it does or holds. → rename it.
- **Duplicated Code** — the same logic shape in more than one hunk or file. → extract and share.
- **Long Function / Long Parameter List** — a unit doing too much or taking too many inputs. →
  split it; bundle related params into a type.
- **Feature Envy** — a method that reaches into another object's data more than its own. → move
  the method onto the data it envies.
- **Data Clumps** — the same few fields/params keep travelling together. → bundle them into one
  type.
- **Primitive Obsession** — a primitive or string standing in for a domain concept. → give the
  concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs. → replace with
  polymorphism or one shared map.
- **Shotgun Surgery** — one logical change forces scattered edits across many files. → gather
  what changes together into one module.
- **Divergent Change** — one module edited for several unrelated reasons. → split it.
- **Speculative Generality** — abstraction or hooks added for needs the spec doesn't have. →
  delete it; inline until a real need shows.
- **Message Chains / Middle Man** — long `a.b().c().d()` walks, or a unit that only delegates
  onward. → hide the walk behind one method; cut the middle man.
- **Refused Bequest** — a subclass/implementer that ignores most of what it inherits. → drop the
  inheritance, use composition.
- **Agent induced documentation** - A comment that reflects the agent's reasoning rather than the code's intent. → remove it; write a comment that explains the code's intent.

### 4. Spawn both subagents in parallel

Send a single message with two `runSubagent` calls (use the default/general agent for both).
Each subagent gets the diff and the axis-specific brief below. Keeping the axes in separate
subagents is what stops one axis's findings from colouring the other's.

**Standards subagent brief** — include:

- The full diff command and commit list (or the fetched PR diff).
- The list of standards-source files from step 3 — repo docs, the **matching** instruction files
  (with their `applyTo` globs), and the applicable skills — **plus the smell baseline from step 3
  pasted in full** (the subagent has no other access to it).
- The instruction: *"Report — per file/hunk where relevant — (a) every place the diff violates a
  documented standard, instruction file, or skill: cite the source (file + the specific rule);
  and (b) any baseline smell you spot: name it and quote the hunk. Distinguish hard violations
  (documented standard, instruction, or skill breaches) from judgement calls (baseline smells,
  always judgement calls). A documented repo standard overrides the baseline. Skip anything
  tooling enforces. Findings only, no praise. Under 500 words."*

**Spec subagent brief** — include:

- The diff command / PR diff and commit list.
- The path or fetched contents of the spec (linked PBI, wiki page, or spec file).
- The instruction: *"Report: (a) requirements the spec asked for that are missing or partial;
  (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look
  implemented but where the implementation looks wrong. Quote the spec line for each finding.
  Findings only. Under 500 words."*

If the spec is missing, skip the Spec subagent and note this in the final report.

#### Using subagents for larger reference work

The two review subagents above are always separate. Spawn **additional** subagents whenever an
axis needs reference material too large to inline without drowning the review context:

- **Broad standards** — when many instruction files, a large `copilot-instructions.md`, or
  several applicable skills apply, have a subagent read them and return a distilled ruleset
  scoped to the changed files, rather than pasting everything into the Standards brief.
- **Multi-page wiki specs** — when the spec spans several wiki pages or a deep component doc,
  have a subagent run `wiki-search`, read the relevant pages, and return a condensed
  requirement list for the Spec brief.
- **Cross-file impact tracing** — when a finding needs the callers/callees of a changed symbol
  across the repo, delegate that trace to a subagent (e.g. via the `codebase-explorer` skill) so
  the aggregation context stays focused.

Give each reference subagent a tight, single-purpose brief and ask it to return **only** the
distilled result, not raw file dumps.

### 5. Aggregate

Present the two reports under `## Standards` and `## Spec` headings, verbatim or lightly cleaned.
Do **not** merge or rerank findings across axes — the separation is deliberate.

End with a one-line summary: total findings per axis, and the worst issue *within each axis* (if
any). Do not pick a single winner across axes — that reranking is exactly what the separation
exists to prevent.

---

## Why two axes

A change can pass one axis and fail the other:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the PBI asked but breaks the repo's conventions → **Spec pass,
  Standards fail.**

Reporting them separately stops one axis from masking the other.
