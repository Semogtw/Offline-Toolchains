# CodexGemini CI and toolchain ownership

Updated: **2026-08-06**

`Semogtw/Offline-Toolchains` is the sole owner of CodexGemini-specific GitHub Actions workflows, composite actions, CI orchestration, source-bundle jobs, release diagnostics and artifact publication.

## Product repositories

The product repositories are source repositories:

- core: `Semogtw/codex-gemini-agents`, active ref `feature/native-harness-local-tools-mcp`;
- Linux wrapper: `Semogtw/codex-desktop-linux-gemini-`, active ref `feature/linux-packaging`.

Do not add CodexGemini-specific files under `.github/workflows/` or `.github/actions/` in either product repository. Local developer scripts and deterministic test fixtures may stay beside the source when they are usable without GitHub Actions. CI-only wrappers, artifact transport and release diagnostics belong here.

Upstream workflows inherited from the original Codex or Linux wrapper repositories may remain unchanged to reduce merge drift. They are not CodexGemini project infrastructure and must not be extended with fork-specific behavior. When an inherited workflow needs fork-specific behavior, implement that behavior in this repository instead.

## Canonical workflow

`.github/workflows/verify-codex-gemini.yml` is the canonical manual verification entry point. It accepts exact repository/ref inputs and provides these suites:

- `core-local-tools`: direct MCP native runtime, sandbox, filesystem, protocol, Clippy and formatting gates;
- `core-external-agents`: deterministic Python/Rust external-agent integration and native CLI build;
- `core-native-equivalence`: Linux and Windows Luna/native fast-path and backend-equivalence gates;
- `wrapper-integration`: wrapper contracts, exact core release build, staging and installation verification;
- `wrapper-release-diagnostic`: exact core release build with a retained full log;
- `all`: all suites.

Default source refs are the current cumulative project branches. Prefer immutable commit SHAs when recording release or acceptance evidence.

Example with GitHub CLI:

```bash
gh workflow run verify-codex-gemini.yml \
  --repo Semogtw/Offline-Toolchains \
  -f suite=all \
  -f core_repository=Semogtw/codex-gemini-agents \
  -f core_ref=feature/native-harness-local-tools-mcp \
  -f wrapper_repository=Semogtw/codex-desktop-linux-gemini- \
  -f wrapper_ref=feature/linux-packaging
```

## Migration map

The canonical workflow replaces fork-specific product-repository workflows for:

- local-tools MCP verification;
- external-agent integration and reports;
- Luna/native equivalence;
- wrapper integration;
- release-build diagnostics.

The former one-shot `apply-external-agent-read-projection` workflow is not migrated as an active workflow. It was patch transport for one historical checkpoint, not durable CI. Its resulting source state and checkpoint documentation remain in the core history.

## Rules for future agents

1. Never solve a missing gate by adding a workflow to a product repository.
2. Add or modify the workflow in `Offline-Toolchains` and accept product repo/ref as inputs.
3. Keep source-facing test commands runnable locally without Actions where feasible.
4. Record exact core, wrapper and toolchain commits in artifacts.
5. Do not treat an unavailable gate as an implementation blocker: document it, preserve the command and continue with code that can be completed.
6. Do not claim a gate passed unless its exact source identity and result are available.

## Scope boundary

Moving CI does not authorize changes to the Codex Harness, Luna prompts, tool selection, context management, retry behavior or inference loop. The toolchain validates source; it does not define agent behavior.
