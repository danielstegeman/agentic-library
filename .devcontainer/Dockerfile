FROM mcr.microsoft.com/devcontainers/dotnet:1-9.0

# Remove the Yarn apt repo that has an expired GPG key, which causes apt-get update to fail
RUN rm -f /etc/apt/sources.list.d/yarn.list 2>/dev/null; \
    rm -f /etc/apt/keyrings/yarn.gpg 2>/dev/null; \
    true
