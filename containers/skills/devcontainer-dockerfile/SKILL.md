---
name: devcontainer-dockerfile
description: 'Create a devcontainer with a custom Dockerfile for projects that need system packages, custom base images, or multi-stage builds. Use when the user asks for "devcontainer with dockerfile", "custom dockerfile devcontainer", "devcontainer from dockerfile", "devcontainer with custom base image", "devcontainer with system packages", or needs to customize the container image beyond what features provide. Also use when the devcontainer skill redirects here.'
---

# Create Dev Container with Custom Dockerfile

Generate a `.devcontainer/Dockerfile` and `.devcontainer/devcontainer.json` for projects that need image customizations beyond what Features provide.

## When to Use This Skill

- Custom system packages (`apt-get install ...`)
- Non-standard base images (company registry, specialized distros)
- Multi-stage builds for smaller images
- Custom build arguments
- An existing Dockerfile that should be reused

## Step 1 — Interview

### Question 1: Base Image or Existing Dockerfile

Ask whether the user wants to:
- **Start from an official devcontainer image** (consult the main skill's [images.md](../devcontainer/references/images.md))
- **Use a custom base image** (e.g., company registry image) — ask for the full image reference
- **Reuse an existing Dockerfile** in the project — ask for its path

### Question 2: System Packages

Ask which additional system packages to install via `apt-get`. Common examples:
- Build tools: `build-essential`, `cmake`, `pkg-config`
- Libraries: `libssl-dev`, `libpq-dev`, `libsqlite3-dev`
- Tools: `graphviz`, `ffmpeg`, `imagemagick`

### Question 3: Build Arguments

Ask if any build arguments are needed (e.g., `VARIANT` for selecting a specific language version). These map to `build.args` in `devcontainer.json`.

### Question 4: Additional Features, Ports, Post-Create, Extensions

Same interview as the main `devcontainer` skill:
- Dev Container Features to add (consult [features.md](../devcontainer/references/features.md))
- Ports to forward
- Post-create command
- VS Code extensions

## Step 2 — Generate Dockerfile

Create `.devcontainer/Dockerfile`:

```dockerfile
# Reference structure — use actual values from interview
ARG VARIANT="1"
FROM mcr.microsoft.com/devcontainers/python:${VARIANT}

# System packages
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        <packages-from-interview> \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Optional: additional setup as non-root user
# USER vscode
# RUN <user-level setup>
```

### Dockerfile Rules

1. **Always combine** `apt-get update` and `apt-get install` in a single `RUN` to avoid layer caching issues.
2. **Always add** `--no-install-recommends` to keep the image small.
3. **Always clean up** apt caches in the same `RUN` layer.
4. **Use `ARG`** for any value that should be configurable via `build.args`.
5. **Set `DEBIAN_FRONTEND=noninteractive`** as an environment variable in the `RUN` command (not as `ENV` — it shouldn't persist).
6. If reusing an existing Dockerfile, ensure it ends with a non-root user matching the `remoteUser` in `devcontainer.json`.

## Step 3 — Generate devcontainer.json

Create `.devcontainer/devcontainer.json`:

```jsonc
// Reference structure — use actual values from interview
{
    "name": "<project-name> Dev Container",
    "build": {
        "dockerfile": "Dockerfile",
        "context": "..",
        "args": {
            // from interview step 3
        }
    },

    "features": {
        // from interview step 4
    },

    "forwardPorts": [/* from interview step 4 */],
    "postCreateCommand": "<from interview step 4>",

    "customizations": {
        "vscode": {
            "extensions": [/* from interview step 4 */]
        }
    },

    "remoteUser": "vscode"
}
```

### Generation Rules

1. **`build.context`** should be `".."` (parent of `.devcontainer/`) so the Dockerfile can access project files if needed.
2. **`build.dockerfile`** is relative to the `.devcontainer/` folder.
3. **Omit `build.args`** if no build arguments were specified.
4. **Omit empty properties** — don't include `"features": {}` if none selected.
5. If the user chose to reuse an existing Dockerfile outside `.devcontainer/`, set `build.dockerfile` to a relative path from `.devcontainer/` (e.g., `"../Dockerfile"`).

## Step 4 — Verify

After generating, tell the user:
1. Two files were created: `.devcontainer/Dockerfile` and `.devcontainer/devcontainer.json`
2. The container will be built from the Dockerfile when they reopen in a container
3. To rebuild after Dockerfile changes: **Dev Containers: Rebuild Container**
