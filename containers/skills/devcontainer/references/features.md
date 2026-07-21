# Popular Dev Container Features

Features are installable units from `ghcr.io/devcontainers/features/`. Add them to the `features` property in `devcontainer.json`.

## Syntax

```jsonc
"features": {
    "ghcr.io/devcontainers/features/<name>:<version>": {
        // optional configuration
    }
}
```

## Common Features

### Developer Tools

| Feature | Description | Example Config |
|---------|-------------|----------------|
| `ghcr.io/devcontainers/features/github-cli:1` | GitHub CLI (`gh`) | `{}` |
| `ghcr.io/devcontainers/features/azure-cli:1` | Azure CLI (`az`) | `{}` |
| `ghcr.io/devcontainers/features/aws-cli:1` | AWS CLI (`aws`) | `{}` |
| `ghcr.io/devcontainers/features/terraform:1` | Terraform and tflint | `{ "version": "latest" }` |
| `ghcr.io/devcontainers/features/kubectl-helm-minikube:1` | Kubernetes tools | `{}` |
| `ghcr.io/devcontainers/features/git-lfs:1` | Git Large File Storage | `{}` |

### Container / Docker

| Feature | Description | Example Config |
|---------|-------------|----------------|
| `ghcr.io/devcontainers/features/docker-in-docker:2` | Docker daemon inside the container | `{}` |
| `ghcr.io/devcontainers/features/docker-outside-of-docker:1` | Reuse host Docker socket | `{}` |

### Languages (add to base images)

| Feature | Description | Example Config |
|---------|-------------|----------------|
| `ghcr.io/devcontainers/features/node:1` | Node.js runtime | `{ "version": "lts" }` |
| `ghcr.io/devcontainers/features/python:1` | Python runtime | `{ "version": "3.12" }` |
| `ghcr.io/devcontainers/features/go:1` | Go runtime | `{ "version": "latest" }` |
| `ghcr.io/devcontainers/features/rust:1` | Rust toolchain | `{}` |
| `ghcr.io/devcontainers/features/java:1` | Java (SDKMAN-based) | `{ "version": "21" }` |
| `ghcr.io/devcontainers/features/dotnet:2` | .NET SDK | `{ "version": "9.0" }` |

### Shell / Utilities

| Feature | Description | Example Config |
|---------|-------------|----------------|
| `ghcr.io/devcontainers/features/common-utils:2` | zsh, Oh My Zsh, common packages | `{}` |
| `ghcr.io/devcontainers/features/sshd:1` | SSH server | `{}` |
| `ghcr.io/devcontainers/features/powershell:1` | PowerShell Core | `{}` |

## Notes

- Feature version `:1` = latest compatible; `:2` where a v2 exists.
- Features are installed **after** the base image is built, in declaration order.
- Use language features to add a **secondary** language to a language-specific image (e.g., add Python to the Node image).
- Browse all available features at [containers.dev/features](https://containers.dev/features).
