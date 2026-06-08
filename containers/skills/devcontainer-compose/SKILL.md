---
name: devcontainer-compose
description: 'Create a multi-container devcontainer with Docker Compose for projects that need additional services (database, cache, message queue). Use when the user asks for "devcontainer with docker compose", "multi-container devcontainer", "devcontainer with database", "devcontainer with postgres", "devcontainer with redis", "devcontainer with services", "devcontainer with multiple containers", or needs to run services alongside the dev container. Also use when the devcontainer skill redirects here.'
---

# Create Dev Container with Docker Compose

Generate a `.devcontainer/docker-compose.yml` and `.devcontainer/devcontainer.json` for projects that need additional services (databases, caches, message queues) alongside the development container.

## When to Use This Skill

- Project needs a database (PostgreSQL, MySQL, MongoDB, SQL Server)
- Project needs a cache (Redis, Memcached)
- Project needs a message queue (RabbitMQ, Kafka)
- Project needs multiple interconnected containers
- Existing `docker-compose.yml` should be extended for dev use

## Step 1 — Interview

### Question 1: Primary Dev Container

Ask about the primary development container:
- Language/framework (consult [images.md](../devcontainer/references/images.md) for base image selection)
- Whether they need a custom Dockerfile (if yes, create one as part of generation)

### Question 2: Services

Ask which additional services are needed. For each service, ask for configuration:

| Service | Common Images | Default Port | Config Questions |
|---------|--------------|--------------|------------------|
| PostgreSQL | `postgres:16` | 5432 | Database name, user, password |
| MySQL | `mysql:8` | 3306 | Database name, user, root password |
| MongoDB | `mongo:7` | 27017 | — |
| SQL Server | `mcr.microsoft.com/mssql/server:2022-latest` | 1433 | SA password, accept EULA |
| Redis | `redis:7` | 6379 | — |
| Memcached | `memcached:1` | 11211 | — |
| RabbitMQ | `rabbitmq:3-management` | 5672, 15672 | — |
| Elasticsearch | `elasticsearch:8` | 9200 | — |
| MinIO | `minio/minio` | 9000, 9001 | Root user, root password |
| Mailpit | `axllent/mailpit` | 1025, 8025 | — |

### Question 3: Volumes

Ask whether database data should persist across container rebuilds:
- **Yes** → use named volumes (data survives `docker compose down`)
- **No** → use anonymous volumes (clean state on every rebuild)

### Question 4: Ports, Post-Create, Extensions

Same as the main `devcontainer` skill:
- Additional ports to forward (beyond the service ports)
- Post-create command
- VS Code extensions

## Step 2 — Generate docker-compose.yml

Create `.devcontainer/docker-compose.yml`:

```yaml
# Reference structure — use actual values from interview
services:
  app:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile  # if custom Dockerfile needed
    # OR use image directly:
    # image: mcr.microsoft.com/devcontainers/typescript-node:1
    volumes:
      - ..:/workspaces/${localWorkspaceFolderBasename}:cached
    command: sleep infinity
    network_mode: service:db  # OR use depends_on + custom network

  db:
    image: postgres:16
    restart: unless-stopped
    volumes:
      - postgres-data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app_dev

  redis:
    image: redis:7
    restart: unless-stopped

volumes:
  postgres-data:
```

### Compose Rules

1. **Dev container service** must have `command: sleep infinity` to keep it running.
2. **Workspace mount**: use `..:/workspaces/${localWorkspaceFolderBasename}:cached` for the source code volume.
3. **Service passwords** in dev environments: use simple defaults (e.g., `postgres`/`postgres`). Add a comment noting these are dev-only values.
4. **`restart: unless-stopped`** for all service containers.
5. **Named volumes** for data persistence when requested.
6. **Don't expose service ports to the host** — the dev container can access services directly via the Docker network using service names as hostnames (e.g., `db:5432`). Only add ports to `forwardPorts` in `devcontainer.json` if the user needs to access services from the host.

## Step 3 — Generate Dockerfile (if needed)

If the user needs a custom Dockerfile for the dev container (custom packages, etc.), create `.devcontainer/Dockerfile` following the same rules as the `devcontainer-dockerfile` skill.

If using a plain image, skip this step — the `docker-compose.yml` references the image directly.

## Step 4 — Generate devcontainer.json

Create `.devcontainer/devcontainer.json`:

```jsonc
// Reference structure — use actual values from interview
{
    "name": "<project-name> Dev Container",
    "dockerComposeFile": "docker-compose.yml",
    "service": "app",
    "workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}",

    "features": {
        // from interview
    },

    "forwardPorts": [/* service ports the user wants accessible from host */],
    "postCreateCommand": "<from interview>",

    "customizations": {
        "vscode": {
            "extensions": [/* from interview */]
        }
    },

    "remoteUser": "vscode"
}
```

### Generation Rules

1. **`service`** must match the dev container service name in `docker-compose.yml` (typically `app`).
2. **`workspaceFolder`** must match the mount target in the compose file.
3. **`forwardPorts`** — include service ports the user wants to access from the host (e.g., database admin UIs). Service-to-service communication uses Docker networking and doesn't need forwarding.
4. **Omit empty properties**.

## Step 5 — Verify

After generating, tell the user:
1. Files created: `.devcontainer/devcontainer.json`, `.devcontainer/docker-compose.yml`, and optionally `.devcontainer/Dockerfile`
2. Services are accessible from the dev container by hostname (e.g., `db`, `redis`)
3. Connection strings: provide example connection strings for each service (e.g., `postgresql://postgres:postgres@db:5432/app_dev`)
4. Data persistence: explain whether data survives container rebuilds based on their volume choice
5. To add/remove services later: edit `docker-compose.yml` and run **Dev Containers: Rebuild Container**
