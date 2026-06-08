---
name: azure-devops-discovery
description: Discover Azure DevOps organization structure including projects, teams, wikis, and manage team capacity for sprint planning
---

# Azure DevOps Discovery & Organization

## Tools

| Task | Tool |
|------|------|
| List projects | `mcp_microsoft_azu_core_list_projects` |
| List teams in a project | `mcp_microsoft_azu_core_list_project_teams` |
| Search wiki | `mcp_microsoft_azu_search_wiki` |
| Get sprint capacity | `mcp_microsoft_azu_work_get_team_capacity` |
| Update sprint capacity | `mcp_microsoft_azu_work_update_team_capacity` |

## Notes

- Wiki `top` defaults to 10 — increase it when searching broadly.
- Get `teamMemberId` from `get_team_capacity` results before calling `update_team_capacity`.
- Capacity is in hours per day (typically 6-8 for full-time).
- For other operations: work items → `azure-devops-work-items` | code → `azure-devops-repos` | testing → `azure-devops-testing`
