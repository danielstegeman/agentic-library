# Official Dev Container Images

Curated list of images from `mcr.microsoft.com/devcontainers/`. Use these as the `image` property in `devcontainer.json`.

## Language-Specific Images

| Image | Languages / Frameworks | Tag Pattern |
|-------|----------------------|-------------|
| `mcr.microsoft.com/devcontainers/typescript-node` | TypeScript, Node.js | `:1`, `:1-22`, `:1-20` |
| `mcr.microsoft.com/devcontainers/javascript-node` | JavaScript, Node.js | `:1`, `:1-22`, `:1-20` |
| `mcr.microsoft.com/devcontainers/python` | Python | `:1`, `:1-3.13`, `:1-3.12` |
| `mcr.microsoft.com/devcontainers/go` | Go | `:1`, `:1-1.23`, `:1-1.22` |
| `mcr.microsoft.com/devcontainers/rust` | Rust | `:1`, `:1-bookworm` |
| `mcr.microsoft.com/devcontainers/dotnet` | C#, F#, .NET | `:1`, `:1-9.0`, `:1-8.0` |
| `mcr.microsoft.com/devcontainers/java` | Java, Maven, Gradle | `:1`, `:1-21`, `:1-17` |
| `mcr.microsoft.com/devcontainers/php` | PHP | `:1`, `:1-8.3`, `:1-8.2` |
| `mcr.microsoft.com/devcontainers/ruby` | Ruby | `:1`, `:1-3.3`, `:1-3.2` |
| `mcr.microsoft.com/devcontainers/cpp` | C, C++, CMake | `:1`, `:1-bookworm` |

## Base Images (No Language Pre-installed)

| Image | Use Case | Tag Pattern |
|-------|----------|-------------|
| `mcr.microsoft.com/devcontainers/base:ubuntu` | Generic Ubuntu base | `:ubuntu`, `:ubuntu-24.04`, `:ubuntu-22.04` |
| `mcr.microsoft.com/devcontainers/base:debian` | Generic Debian base | `:debian`, `:debian-bookworm` |
| `mcr.microsoft.com/devcontainers/base:alpine` | Minimal Alpine base | `:alpine`, `:alpine-3.20` |
| `mcr.microsoft.com/devcontainers/universal` | Multi-language (Python, Node, .NET, Java, Go, PHP, Ruby) | `:2` |

## Looking Up Available Tags

The tag examples above are illustrative. **Always look up current tags** before recommending a pinned version by fetching:
`https://mcr.microsoft.com/v2/devcontainers/<image-name>/tags/list`

## OS Variant Selection

Most images are available in multiple OS variants:

| Variant | Base OS | Suffix | Notes |
|---------|---------|--------|-------|
| Bookworm | Debian 12 | `-bookworm` | Default for `:1` tags. **Known issue**: ships with a stale Yarn apt repo (expired GPG key) that breaks `apt-get update` during feature installation. |
| Bookworm Slim | Debian 12 (minimal) | `-bookworm-slim` | Same Yarn issue as Bookworm. |
| Noble | Ubuntu 24.04 | `-noble` | **Recommended**. No stale apt repos. |
| Jammy | Ubuntu 22.04 | `-jammy` | Older Ubuntu LTS. No stale apt repos. |

**Prefer `-noble` variants** (e.g., `2-9.0-noble`) to avoid apt repository issues during container builds.

## Notes

- **Tag `:1`** = latest patch for the major version; auto-updates. May resolve to a Bookworm image with known issues.
- **Pinned tags** (e.g., `:1-3.12`) = specific language version. Use when version matters.
- **Version 2 images** (`:2-*`) are the latest major revision where available.
- **`universal`** image is large (~8 GB) but includes everything. Good for polyglot or quick-start projects.
- All images include `git`, `curl`, `wget`, `zsh`, and a non-root `vscode` user.
- Alpine images may have compatibility issues with some extensions that depend on `glibc`.
