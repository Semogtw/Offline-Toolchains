# Offline Toolchains

Public repository for reproducible development toolchains, offline dependency caches, environment bootstrap helpers, integrity manifests, and compatibility validation.

The goal is to make development environments easier to reproduce across machines and projects while keeping generated assets verifiable and maintenance scripts versioned.

## What lives here

- Android, Flutter, Java, Node, Rust, and Linux environment helpers;
- offline dependency caches and small incremental cache deltas;
- restore/activation scripts for prepared environments;
- manifests, checksums, and integrity validation;
- build-environment smoke tests and compatibility checks;
- utilities used to generate, inspect, or validate toolchain artifacts.

Large artifacts may be split into multiple parts. Always validate the accompanying manifest and checksums before using restored content.

## Repository layout

| Path | Purpose |
| --- | --- |
| `.github/workflows/` | Automation and validation workflows |
| `scripts/` | Build, restore, validation, and maintenance scripts |
| `manifests/` | Versioned metadata for reproducible artifacts |
| `packages/` | Packaged toolchain helpers and related assets |
| `fixtures/` | Test and validation fixtures |
| `tests/` | Repository-level checks |
| `docs/` | Public technical documentation |

## Security

This is a public repository. Do not commit credentials, signing material, private source code, private configuration, access tokens, or operational handoff notes.

Workflows that need credentials must consume them through GitHub's secret mechanisms and should follow least-privilege principles. Logs and generated public metadata must be treated as publicly visible.

Operational details that are only useful to maintainers or automated agents should live in a private source of truth rather than in this repository.

## Documentation policy

Public documentation should explain the reusable toolchains, artifact formats, restoration process, and validation behavior needed by users of this repository.

It should not contain:

- access-token names or permission maps;
- private repository inventory;
- production deployment or signing procedures;
- internal handoff notes, run IDs, private commit references, or incident notes;
- detailed credential topology;
- project-management history that is not required to use the public tooling.

## Validation

Repository-level validation scripts live under `scripts/` and `tests/`. Run the checks relevant to the component being changed before publishing a new artifact or modifying its contract.

When changing a toolchain format, keep its manifest, restore logic, tests, and public documentation synchronized.

## Scope

This repository is primarily infrastructure: reproducible environments, caches, packaging, and validation. Consumer-specific application documentation belongs with the corresponding project, not here.
