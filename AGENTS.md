# Project Instructions for AI Agents

This is a public infrastructure repository. Keep all changes compatible with that boundary.

## Working rules

- Identify the toolchain, artifact, manifest, or validation path affected before changing shared infrastructure.
- Prefer small, coherent changes with validation at each meaningful checkpoint.
- Keep unrelated consumer-specific changes separate when they do not share one atomic infrastructure change.
- Validate generated artifacts and manifests whenever practical before committing them.
- Keep public documentation focused on reusable tooling, formats, restoration, and validation behavior.
- Do not add private source code, credentials, signing material, production configuration, internal runbooks, private commit references, operational handoffs, or secret names to this repository.
- Do not record sensitive infrastructure topology or permission maps in public documentation.
- If work requires consumer-specific or privileged operational context, use that project's private source of truth rather than documenting it here.
- Treat logs, workflow summaries, committed reports, manifests, and generated metadata as public unless proven otherwise.
- Keep documentation and tests synchronized with material changes to public artifact contracts.
- Use frequent coherent commits so useful work is not lost, without splitting one logical change into unnecessary micro-commits.

## Public documentation rule

Anything committed here should be safe to expose to an unauthenticated reader. Internal agent notes belong outside this public repository.
