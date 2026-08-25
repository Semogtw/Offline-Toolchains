# SemogSite offline toolchain

This profile provides a public Linux x64 dependency bundle for reproducible SemogSite development and validation.

The bundle is intended to contain public tooling and dependency caches only. Application source, credentials, and runtime configuration are outside the artifact contract.

## Contents

A toolchain generation can include:

- Node.js for Linux x64;
- pinned pnpm and a populated pnpm store;
- Playwright browser assets;
- native runtime support needed by bundled dependencies;
- activation, installation, hydration, and doctor scripts;
- `MANIFEST.txt`, integrity files, and a software bill of materials.

## Dependency build policy

Lifecycle scripts should be restricted to an explicit allowlist during toolchain generation. Offline consumers should avoid rerunning arbitrary dependency lifecycle scripts when a verified native artifact can be restored from the bundle instead.

This keeps cache generation auditable and reduces unexpected code execution during restoration.

## Reconstruct

Download every part belonging to the same generation and verify the provided checksums before extraction.

```bash
sha256sum -c SHA256SUMS.parts
cat semogsite-toolchain-linux-x64.part-* > semogsite-toolchain-linux-x64.tar.zst
sha256sum -c semogsite-toolchain-linux-x64.tar.zst.sha256

tar --zstd -xf semogsite-toolchain-linux-x64.tar.zst
```

## Activate and install

```bash
source ./semogsite-toolchain/scripts/activate.sh
bash ./semogsite-toolchain/scripts/doctor.sh

bash ./semogsite-toolchain/scripts/install-offline.sh /path/to/project

bash ./semogsite-toolchain/scripts/doctor.sh /path/to/project
```

The installer should use the bundled package store in offline mode and validate compatibility with the target dependency inputs.

## Expected validation

Representative validation can include:

```bash
pnpm -r typecheck
pnpm -r test
pnpm -r build
pnpm exec playwright test
```

Browser tests should use the bundled browser assets rather than downloading a browser during the offline validation phase.

## Regenerate when

Regenerate after material changes to inputs such as:

- Node or pnpm versions;
- workspace manifests or lockfile compatibility;
- dependency build policy;
- Playwright/browser requirements;
- native module ABI requirements;
- restore or hydration logic.

## Validation boundary

A successful toolchain validation proves that the captured public dependency environment can be restored and exercised under the supported conditions. It does not by itself prove future application behavior, deployment correctness, or production configuration.
