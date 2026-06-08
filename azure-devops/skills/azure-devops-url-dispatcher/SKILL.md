---
name: azure-devops-url-dispatcher
description: "Automatically identify Azure DevOps URL type and route to the correct domain skill. Use when presented with any dev.azure.com URL."
---

## Goal

Extract organization, project, and resource ID from Azure DevOps URLs; determine domain type (build, work item, repo, test); direct agents to invoke the appropriate domain skill. Before parsing, verify that the Azure DevOps MCP is activated — if it is not, stop and ask the user to activate it.

## Context Gathering

**When to Use This Skill**
- Agent receives an Azure DevOps URL in any format
- Need to route URL context to a domain-specific skill
- URL components must be parsed and validated before domain routing

**Related Skills**
- [azure-devops-discovery](../azure-devops-discovery/SKILL.md) – Default fallback
- [azure-devops-pipeline-runner](../azure-devops-pipeline-runner/SKILL.md) – Build/pipeline URLs

## Planning

**URL Detection Algorithm:**
1. Parse dev.azure.com URL to extract: organization, project, path components
2. Match path pattern to identify domain type
3. Extract resource ID (buildId, workItemId, repositoryId, etc.)
4. Route to appropriate domain skill with extracted parameters

## Execution

**Workflow 1: Detect Azure DevOps URL and Route to Domain Skill**
0. Check if the Azure DevOps MCP is activated. If not, STOP and ask the user to activate it before continuing.
1. Input: Azure DevOps URL (e.g., `https://dev.azure.com/myorg/MyProject/_build/results?buildId=12345`)
2. Parse organization and project from URL path
3. Match URL pattern against detection map (see Tool Reference below)
4. Extract domain-specific ID parameter (buildId, workItemId, repositoryName/pullRequestId, testPlanId). If a required ID parameter cannot be found in the URL, stop and respond: "The URL matches the [domain] pattern but is missing the required [parameter] value. Please provide a complete URL including [parameter]."
5. Invoke targeted domain skill with extracted `{organization}`, `{project}`, and the domain-specific parameter(s)
6. Return the domain skill's response to the user without modification. Do not summarize or reformat unless the domain skill explicitly instructs otherwise.


## Tool Reference

**URL Pattern Detection Map**

| URL Pattern | Domain Type | Extracted Resource | Target Skill | Example |
|---|---|---|---|---|
| `_build/results?buildId=` | Build | `buildId` | pipeline-runner | `https://dev.azure.com/org/proj/_build/results?buildId=304483` |
| `_workitems/edit/{id}` or `_workitems?id=` | Work Item | `workItemId` | azure-devops-work-items | `https://dev.azure.com/org/proj/_workitems/edit/1234` |
| `_git/{repo}/pullrequest/` | Pull Request | `pullRequestId`, `repositoryName` | azure-devops-repos | `https://dev.azure.com/org/proj/_git/repo/pullrequest/42` |
| `_git/` | Repository | `repositoryName` | azure-devops-repos | `https://dev.azure.com/org/proj/_git/repo` |
| `_testManagement/` | Test Plan | `testPlanId` | azure-devops-testing | `https://dev.azure.com/org/proj/_testManagement/` |
| Default/root | Discovery | `organization`, `project` | azure-devops-discovery | `https://dev.azure.com/org/proj` |

> **Unrecognized paths**: If the URL path contains a segment starting with `_` that does not match any pattern above, do not fall back to azure-devops-discovery. Instead, inform the user: "This URL references an unsupported Azure DevOps resource type ([path segment]). Supported types are: build, work item, git repository, pull request, and test plan."

> **Edge cases**:
> - **URL with query-string-only project**: Some shortened URLs omit the project segment (e.g., `https://dev.azure.com/org/_build?...`). Treat the project as unknown and ask the user to confirm the project before routing.
> - **Trailing slashes / fragments**: Normalize the URL by stripping trailing slashes and ignoring `#` fragments before pattern matching.
> - **Non-numeric IDs**: If an expected numeric ID (buildId, workItemId, pullRequestId) is present but non-numeric, do not attempt routing; respond: "The [parameter] value '[value]' is not a valid numeric ID. Please verify the URL."
> - **Multiple matching patterns**: If a URL simultaneously matches more than one pattern (e.g., a `_git/` URL that also contains `?buildId=`), prefer the more specific pattern (pull request > git repository; work item query param only when path contains `_workitems`).
> - **Old visualstudio.com hostnames**: URLs with the format `https://{org}.visualstudio.com/{project}/...` follow the same path-based routing rules. Strip the org from the hostname and treat the remaining path identically to a `dev.azure.com` URL.
> - **Percent-encoded characters**: Decode percent-encoded characters in the URL before pattern matching and ID extraction.

**Extraction Parameters**
- Organization: Path segment 1 after `dev.azure.com/`
- Project: Path segment 2
- Build ID: value of the `buildId` query parameter
- Work Item ID: numeric segment after `_workitems/edit/`, or value of `id` query parameter when path contains `_workitems`
- Repository name: path segment immediately following `_git/`
- Pull Request ID: numeric segment after `pullrequest/`; also extract the repository name from the preceding `_git/{repo}` segment
- Test Plan ID: value of the `planId` query parameter in `_testManagement/` URLs; if absent, pass `null` and let `azure-devops-testing` handle discovery
