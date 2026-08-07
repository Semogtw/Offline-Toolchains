# Project Instructions for AI Agents

This repository provides shared offline toolchains, artifact workflows, caches, restoration helpers, and validation support for multiple consumer repositories. Keep consumer-specific state isolated and do not let work for one project silently change another project's artifact contract.

<!-- auto-preference-learner:start -->
## Learned working preferences

- Before changing shared infrastructure, identify the consumer project, active branch or PR, exact artifact/profile being served, and the current live Git/GitHub state. Do not revive an older consumer workflow merely because its branch still exists.
- Continue useful independent work while the current infrastructure objective has safe, resolvable tasks; do not stop after a trivial checkpoint solely because one consumer-specific gate is unavailable.
- Create and push frequent coherent checkpoints so ephemeral environments do not erase useful infrastructure work. Keep unrelated GoAnime, FicharioVirtual, SemogSite, Zapzap, or other consumer changes in separate checkpoints when they do not share one atomic infrastructure change.
- Prefer validation in the agent environment when practical. Install missing tooling when reasonable; when a consumer gate cannot run in the current environment, record the exact limitation, preserve any safely produced workspace/artifact needed for later validation, and continue independent resolvable work.
- Treat GitHub Actions as infrastructure that must be justified by this repository's artifact/CI purpose, not as the default substitute for local development checks in consumer repositories.
- Keep documentation, artifact manifests, continuation notes, and security boundaries synchronized with material workflow changes, especially source provenance, credentials, retention, restoration, and consumer compatibility.
- Use available plugins and integrations when they materially improve correctness, verification, artifact handling, or development efficiency; do not invoke them merely for ceremony.
<!-- auto-preference-learner:end -->
