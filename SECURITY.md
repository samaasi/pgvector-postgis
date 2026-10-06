# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| `latest` / `pg18` | ✅ Active |
| `pg17` | ✅ Active |
| Older tags | ❌ Not maintained |

We only support the most recent release. Please upgrade to the latest image before reporting issues.

## Reporting a Vulnerability

If you discover a security vulnerability in this project, **please report it responsibly**.

### Do

- Email **[dev.bensonsamaasi@gmail.com](mailto:dev.bensonsamaasi@gmail.com)** with details
- Include steps to reproduce the issue
- Allow reasonable time for a fix before public disclosure

### Don't

- Open a public GitHub issue for security vulnerabilities
- Exploit the vulnerability on production systems

## What Qualifies

- Vulnerabilities in the Dockerfile build process
- Insecure defaults in the image configuration
- Exposed secrets or credentials in the image layers
- Vulnerabilities in the init scripts

## What Doesn't Qualify

- CVEs in upstream packages (PostgreSQL, PostGIS, pgvector, TimescaleDB) — report these to the respective upstream projects
- Issues requiring physical access to the host machine
- Denial of service via resource exhaustion (expected for database workloads)

## Response Timeline

| Stage | Timeframe |
|---|---|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 1 week |
| Fix or mitigation | Within 2 weeks |
| Public disclosure | After fix is released |

## Security Practices

This image follows security best practices as documented in the [README](README.md#security):

- GPG-verified package installation (pinned signing-key fingerprint)
- Weekly rebuilds that re-apply OS security patches
- Build dependency cleanup
- No secrets baked into the image
- Non-root runtime via official PostgreSQL image
- Trivy scan gate in CI: a fixable CRITICAL vulnerability blocks publishing
- GitHub Actions pinned to commit SHAs
