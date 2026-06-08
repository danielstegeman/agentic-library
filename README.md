# agentic-library

Generic, reusable agent skills and agents for GitHub Copilot (and other APM-compatible harnesses).

## Packages

| Package | Contents |
|---------|----------|
| [`git-tools`](git-tools/) | Conventional commit generation, branch squash, safe worktree setup |
| [`azure-devops`](azure-devops/) | Pipeline runner, PR context, PR review assessment, PR stacking, URL dispatcher, org discovery |
| [`code-review`](code-review/) | Code review orchestration agent, defensive coding, infrastructure, module architecture, pipeline YAML review |
| [`agent-engineering`](agent-engineering/) | Skill creator, agent artifacts, planning agent, context improver, design challenger, logging guidelines, wiki search, Copilot docs lookup |

## Install with APM

```yaml
# apm.yml
dependencies:
  apm:
    - Stegeman/agentic-library/git-tools
    - Stegeman/agentic-library/azure-devops
    - Stegeman/agentic-library/code-review
    - Stegeman/agentic-library/agent-engineering
```

## Philosophy

- **Generic by design** — no organisation, project, or team names baked in
- **Composable** — install only the packages you need
- **Project-specific context** lives separately (e.g. an `org-info` skill in your project's own package)
