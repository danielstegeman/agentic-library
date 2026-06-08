---
name: wiki-search
description: Search wiki documentation for information. Use when asked to search a wiki, look something up in documentation, find wiki pages, or answer questions from wiki content. First checks for a local wiki folder in the workspace, then falls back to Azure DevOps wiki via MCP.
---

# Wiki Search

## Goal

Find information in wiki documentation using the fastest available source.

## Steps

### Step 1: Search for a Local Wiki Folder

Use `file_search` to look for a local wiki directory in the workspace (e.g. `**/wiki/**`, `**/.wiki/**`, `**/docs/**`).

If found, use `semantic_search` or `grep_search` to find relevant content within those files and return the results.

**Stop here if local wiki content was found.**

### Step 2: Search Azure DevOps Wiki

If no local wiki folder was found, use `mcp_microsoft_azu_search_wiki` with the user's query as `searchText`.

- Optionally filter by `project` if the user specifies one
- Return the page titles, paths, and relevant content snippets from the results
- If a specific page looks relevant, retrieve its full content with `mcp_microsoft_azu_wiki_get_page_content`
