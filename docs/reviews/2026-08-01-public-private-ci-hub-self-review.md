# Public private-CI hub pre-merge review

## Review range

- Base: `ba090c43765be22cb99f253a8dfe16e1b8cbea1e`
- Head before this review note: `39e0d01d9745e8db7a32c0c3f7f2290d170199db`

## Requirements checked

- The real project commands execute in native jobs of the public repository.
- Exactly three private repositories are allowlisted.
- Payloads cannot select repositories, commands, scripts, runners, secrets, or artifacts.
- Private checkout credentials are not persisted.
- No private build artifact or project-derived cache is uploaded.
- Connector requests are validated in a no-secret workflow before the privileged workflow accepts them.
- Manual and API dispatches require the repository owner as actor.
- Every private checkout is removed in an `always()` step.

## Verification performed

- `python3 scripts/test_private_ci_request.py`: 8 tests passed.
- YAML parsing with Ruby Psych: all three new workflow files parsed successfully.
- `python3 scripts/validate-private-ci-workflows.py`: passed after correcting the guard to recognize `shell: pwsh` semantics.
- Branch comparison: implementation branch was ahead of `main` with no divergence and only planned files changed.

## Security observations

- `PRIVATE_REPOSITORIES_TOKEN` is visible only to token-presence checks and `actions/checkout`; project commands do not receive it as a declared environment variable.
- The token must remain fine-grained, read-only, and scoped only to `goanime-mobile`, `Zapzap`, and `SemogSite`.
- Public logs can expose filenames, test names, diagnostics, and stack traces. This is documented and is inherent to running private project checks in a public repository.
- A malicious private ref can execute code on the public runner, but cannot override the fixed public repository permissions or retain the checkout token through Git configuration. Only owner-triggered refs are accepted.
- Build outputs are intentionally discarded. Publishing them later requires a separate design with a private destination and separately scoped write credential.

## Result

No critical or important issue was found in the reviewed implementation. Full end-to-end verification still requires the merged workflows, the permanent `build/private-ci` branch, and a configured `PRIVATE_REPOSITORIES_TOKEN` whose repository selection includes the requested project.
