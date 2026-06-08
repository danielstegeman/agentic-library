---
name: copilot-docs-lookup
description: Look up information in official GitHub Copilot documentation. Use when asked to find documentation about Copilot, search Copilot features, or answer questions about Copilot capabilities and usage.
---

# Copilot Docs Lookup

## Goal

Provide quick access to official Copilot documentation from https://code.visualstudio.com/docs/copilot/overview.

## Steps

### Step 1: Fetch Documentation

Use `fetch_webpage` to retrieve content from the Copilot documentation URL with the user's query as the search parameter.

```
urls: https://code.visualstudio.com/docs/copilot/overview
query: [user's question or search term]
```

### Step 2: Return Relevant Results

Extract and return relevant sections from the documentation that match the user's query, including links to specific documentation pages if available.

## Troubleshooting

- If the main overview page doesn't have the answer, suggest searching related docs at https://code.visualstudio.com/docs/copilot/
- For issues, direct users to the official troubleshooting guides in the documentation
