---
name: devcontainer
description: 'Create a devcontainer.json configuration for any project using the open Dev Container Specification (containers.dev). Use when the user asks to "create a devcontainer", "add devcontainer", "setup dev container", "containerized development environment", "devcontainer.json", "dev container config", or wants to set up container-based development. Supports VS Code, GitHub Codespaces, IntelliJ, DevPod, and any spec-compliant tool. For custom Dockerfiles use devcontainer-dockerfile; for multi-container setups use devcontainer-compose.'
---

# Create Dev Container Configuration

Generate a `.devcontainer/devcontainer.json` using an official base image. Follows the open [Dev Container Specification](https://containers.dev/) with optional VS Code customizations.

## Step 1 — Detect Project Stack

Run the detection script to auto-discover the project's language, package manager, and ports:

```powershell
& "<skill-path>/scripts/Detect-ProjectStack.ps1" -WorkspaceRoot "<workspace-root>"
```

The script outputs structured fields:
- `Language:` — primary detected language (e.g., `typescript`, `python`, `go`)
- `AdditionalLanguages:` — other detected languages in the workspace
- `Image:` — recommended base image from `mcr.microsoft.com/devcontainers/*`
- `PostCreate:` — recommended post-create command (e.g., `npm install`)
- `Ports:` — detected ports to forward
- `PackageManager:` — detected package manager
- `Existing:` — path to existing devcontainer config, or `none`

If `Existing:` is not `none`, warn the user that a devcontainer config already exists and ask whether to overwrite or update it.

## Step 2 — Interview

Present the detected values as defaults and ask the user to confirm or adjust. Use the ask-questions tool with these questions:

### Question 1: Language & Image

Show the detected language and recommended image. Ask if this is correct, or if they want a different base image.

Consult [images.md](./references/images.md) for the full list of official images.

**Always look up the latest available tags** before recommending a pinned version by fetching:
`https://mcr.microsoft.com/v2/devcontainers/<image-name>/tags/list`

Prefer `-noble` (Ubuntu) variants over `-bookworm` (Debian) to avoid stale apt repository issues (e.g., expired Yarn GPG keys in Bookworm-based images).

### Question 2: Additional Features

Ask which additional tools to install as Dev Container Features. Common choices:
- GitHub CLI, Azure CLI, AWS CLI
- Docker-in-Docker or Docker-outside-of-Docker
- Additional language runtimes (e.g., add Python to a Node image)
- Terraform, kubectl, PowerShell

Consult [features.md](./references/features.md) for the full list.

### Question 3: Ports

Show the detected ports. Ask if there are additional ports to forward.

### Question 4: Post-Create Command

Show the detected post-create command. Ask if they want to add additional setup steps (e.g., database migrations, tool installations).

### Question 5: VS Code Extensions

Ask which VS Code extensions should be pre-installed in the container. Suggest relevant extensions based on the detected language:
- TypeScript/JavaScript: `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`
- Python: `ms-python.python`, `ms-python.vscode-pylance`
- Go: `golang.go`
- Rust: `rust-lang.rust-analyzer`
- .NET: `ms-dotnettools.csdevkit`
- Java: `vscjava.vscode-java-pack`

### Question 6: Complexity Check

Ask whether the user needs:
- **A custom Dockerfile** (custom system packages, multi-stage builds, specific base image) → recommend the `devcontainer-dockerfile` skill instead
- **Multiple containers** (database, cache, message queue alongside the dev container) → recommend the `devcontainer-compose` skill instead

If either is selected, stop here and tell the user to invoke the appropriate skill.

## Step 3 — Generate

Create `.devcontainer/devcontainer.json` with the following structure:

```jsonc
// For reference only — use actual values from the interview
{
    "name": "<project-name> Dev Container",
    "image": "<selected-image>",

    // Additional tools
    "features": {
        // from interview step 2
    },

    // Ports
    "forwardPorts": [/* from interview step 3 */],

    // Lifecycle
    "postCreateCommand": "<from interview step 4>",

    // Tool-specific customizations (open spec — not VS Code specific)
    "customizations": {
        "vscode": {
            "extensions": [/* from interview step 5 */],
            "settings": {}
        }
    },

    // Run as non-root user (security best practice)
    "remoteUser": "vscode"
}
```

### Generation Rules

1. **Always set `remoteUser`** to `"vscode"` — all official images create this user.
2. **Omit empty properties** — don't include `"features": {}` if no features were selected.
3. **Use JSONC** (JSON with comments) — devcontainer.json supports `//` comments.
4. **Add a brief comment** above non-obvious properties explaining their purpose.
5. **Port numbers** go in `forwardPorts` as integers, not strings.
6. **`postCreateCommand`** can be a string or an object for named commands:
   ```jsonc
   "postCreateCommand": {
       "install": "npm install",
       "setup-db": "npm run db:migrate"
   }
   ```
7. **Multi-language projects**: if `AdditionalLanguages` were detected, add those as Features rather than switching the base image. For example, a TypeScript project that also has Python scripts → use the TypeScript-Node image + `ghcr.io/devcontainers/features/python:1`.

## Step 4 — Verify

After generating, tell the user:
1. The file was created at `.devcontainer/devcontainer.json`
2. They can open the folder in a container with **Dev Containers: Reopen in Container** (VS Code) or by pushing to a GitHub Codespaces-enabled repo
3. The configuration follows the open Dev Container Specification and works with VS Code, GitHub Codespaces, IntelliJ IDEA, DevPod, and other supporting tools
