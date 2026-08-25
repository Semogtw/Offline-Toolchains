# Codex offline toolchain

This package provides a reproducible Linux x64 development environment for Codex-compatible projects without requiring a preinstalled compiler/toolchain stack on the consumer machine.

## Contents

A toolchain generation can include:

- Rust and Cargo;
- `rustfmt` and Clippy;
- hydrated Cargo caches;
- Ruff and uv;
- `just`;
- `protoc` and required native libraries/headers;
- portable activation helpers;
- integrity manifests and compatibility metadata.

Large or expensive components such as prebuilt V8-related artifacts may be distributed separately so they can be refreshed independently from the main bundle.

## Reconstruct the main bundle

Download all parts belonging to the same generation and validate their checksums before extraction:

```bash
sha256sum --check SHA256SUMS.parts
cat codex-toolchain-linux-x64.part-* > codex-toolchain-linux-x64.tar.zst
sha256sum codex-toolchain-linux-x64.tar.zst
```

Compare the reconstructed archive digest with the supplied manifest, then extract and activate it:

```bash
mkdir -p /tmp/codex-offline
tar --zstd -xf codex-toolchain-linux-x64.tar.zst -C /tmp/codex-offline
source /tmp/codex-offline/codex-toolchain/activate.sh
```

Activation should configure the bundled caches and native dependencies for the current shell without mutating unrelated global Git configuration.

## Offline validation

A valid generation should support representative Cargo operations with networking disabled, such as:

```bash
cargo check --offline
cargo test --offline
cargo clippy --offline
```

Projects with additional native or prebuilt dependencies should validate those artifacts separately before running the corresponding build.

## Compatibility

Manifests should record the versions and compatibility fingerprints needed to determine whether a toolchain generation matches the intended dependency graph.

Consumers should fail closed when required compatibility metadata does not match rather than silently falling back to network resolution.

## Regeneration policy

Regenerate when material inputs change, including:

- Rust/Cargo version;
- dependency-lock compatibility;
- native compiler/library requirements;
- protobuf tooling;
- prebuilt runtime artifacts;
- restore/activation behavior.

## Public boundary

This document covers only the reusable toolchain, restoration, integrity, and offline validation contract. Active development refs, internal trigger files, repository-routing rules, migration history, and privileged operational procedures are intentionally outside the public documentation.
