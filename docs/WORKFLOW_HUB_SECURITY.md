# Workflow and artifact security

This repository is public. Workflows, logs, committed metadata, artifacts, and documentation should therefore be designed with public visibility in mind.

## Core rules

1. **Use least privilege.** Workflows should request only the permissions required for their task.
2. **Do not persist credentials.** Authentication material must not be committed, printed, cached, or embedded in generated artifacts.
3. **Treat logs as public.** Avoid environment dumps, verbose credential-bearing commands, private source output, and sensitive diagnostic payloads.
4. **Validate artifacts before reuse.** Toolchain bundles and cache packages should ship with integrity metadata such as checksums or manifests.
5. **Keep generated state scoped.** Temporary build directories, working copies, and credential helpers should be removed when they are no longer needed.
6. **Bound artifact retention.** Public generated artifacts should use explicit retention appropriate to their purpose rather than relying on implicit defaults.
7. **Separate privileged operations.** Signing, deployment, production credentials, and other privileged actions should use narrowly scoped workflows and credentials.
8. **Do not accept arbitrary execution input.** Reusable automation should validate inputs and avoid turning user-controlled strings into unrestricted repository names, shell commands, or artifact destinations.

## Public documentation boundary

Documentation committed here should describe reusable public behavior: toolchain formats, cache restoration, validation, reproducibility, and supported environments.

Internal operational details are not part of the public contract. Do not commit credential inventories, permission maps, private project state, production topology, incident notes, internal handoffs, or private source references merely for maintainer convenience.

## Toolchain integrity

When publishing or restoring a generated toolchain:

- pin or record relevant versions;
- verify checksums/manifests before extraction or execution;
- keep restore scripts deterministic where practical;
- fail closed when required integrity metadata does not match;
- update validation tests when the artifact contract changes.

## Workflow changes

When a workflow gains new permissions, credentials, write access, external publication, or a new artifact class, review that change as a security boundary change rather than a routine refactor.

Prefer narrowly scoped credentials and isolated publish steps over broad repository-wide permissions.

## Validation

Security and workflow validators live under `scripts/` and `tests/`. Run the relevant checks after changing permissions, artifact handling, restoration logic, or workflow input contracts.
