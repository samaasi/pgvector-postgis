# Contributing to pgvector-postgis

Thank you for your interest in contributing! This guide will help you get started.

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](../../issues) to report bugs or request features
- Include your Docker version, host OS, and architecture (amd64/arm64)
- Paste the full error output if reporting a build failure

### Submitting Changes

1. **Fork** the repository
2. **Create a branch** from `develop`:
   ```bash
   git checkout develop
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** and test locally:
   ```bash
   docker build -t pgvector-postgis:test .
   ./scripts/smoke-test.sh pgvector-postgis:test   # starts the image and verifies every extension
   ```
4. **Commit** with a clear message:
   ```bash
   git commit -m "feat: add support for pg_cron extension"
   ```
5. **Push** and open a Pull Request against `develop`

### Branch Strategy

| Branch | Purpose |
|---|---|
| `master` | Production — triggers Docker Hub publish |
| `develop` | Integration — CI build validation only |

### Commit Message Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature or extension
- `fix:` — bug fix
- `docs:` — documentation changes
- `ci:` — CI/CD workflow changes
- `chore:` — maintenance tasks

## Local Development

### Prerequisites

- Docker 20.10+ with Buildx
- (Optional) [Trivy](https://trivy.dev) to run the same vulnerability scan as CI

### Build and test

```bash
# Build for your current platform
docker build -t pgvector-postgis:test .

# Run
docker run --name test-db -e POSTGRES_PASSWORD=test -d pgvector-postgis:test

# Verify all extensions
docker exec test-db psql -U postgres -c "\dx"

# Cleanup
docker rm -f test-db
```

## Code of Conduct

Be respectful and constructive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/).

## Continuous Integration

Every push and pull request builds each image (PostgreSQL 17 and 18, on native amd64 and arm64 runners), runs `scripts/smoke-test.sh` and a Trivy scan (`trivy.yaml`). A fixable CRITICAL vulnerability or a failing smoke test fails the build. Images are only published from `master` and `v*.*.*` tags, and `master` is rebuilt weekly so tags pick up OS security patches.

Repository secrets used by the publish job:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_PASSWORD` | A Docker Hub **access token** with read/write scope (Account settings → Personal access tokens) — not the account password |

GitHub Actions are pinned to commit SHAs; Dependabot updates them. The pgvector base-image version is updated by [Renovate](renovate.json), which needs the Renovate GitHub App installed on the repository.
