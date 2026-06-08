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

## Notes

- **Tag `:1`** = latest patch for the major version; auto-updates. Recommended for most projects.
- **Pinned tags** (e.g., `:1-3.12`) = specific language version. Use when version matters.
- **`universal`** image is large (~8 GB) but includes everything. Good for polyglot or quick-start projects.
- All images are based on Debian Bookworm unless noted otherwise.
- All images include `git`, `curl`, `wget`, `zsh`, and a non-root `vscode` user.
- Alpine images may have compatibility issues with some extensions that depend on `glibc`.
