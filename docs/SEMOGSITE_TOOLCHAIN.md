# SemogSite offline toolchain

This profile builds a public Linux x64 dependency bundle for `Semogtw/SemogSite`. It contains tooling and public package caches only; it does not contain application source or runtime configuration.

## Baseline

The initial fixture follows the foundation plan at SemogSite commit `6b88e71591f0049fa2bb85099b770165f44940c4`. At that point the workspace had not yet been bootstrapped, so the workflow resolves the approved dependency families and includes the generated reference `pnpm-lock.yaml` in every artifact set.

When the real workspace manifests and lockfile exist, update the public fixture to match those exact dependency inputs and regenerate the toolchain.

## Contents

The reconstructed archive contains:

- Node.js 22 for Linux x64, including Node headers;
- pinned pnpm, pnpm store, and offline resolution metadata;
- reference `package.json` and generated `pnpm-lock.yaml`;
- Chromium downloaded by Playwright;
- Chromium shared libraries discovered through `ldd`;
- a `better-sqlite3` binary keyed by package version and Node ABI;
- activation, installation, native hydration, and doctor scripts;
- `MANIFEST.txt` and `SOFTWARE-BOM.json`.

The fixture covers TanStack Start/Router/Query, React, Hono, Zod, Drizzle, SQLite, Radix primitives, TypeScript, Vite, Vitest, Testing Library, Playwright, and Wrangler.

## Reconstruct

Find the newest successful receipt in issue `#8`, download the manifest and every `semogsite-toolchain-linux-x64-part-NN` artifact, and extract the artifact ZIPs into one directory.

```bash
sha256sum -c SHA256SUMS.parts
cat semogsite-toolchain-linux-x64.part-* \
  > semogsite-toolchain-linux-x64.tar.zst
sha256sum -c semogsite-toolchain-linux-x64.tar.zst.sha256

tar --zstd -xf semogsite-toolchain-linux-x64.tar.zst
```

## Activate and install

```bash
source ./semogsite-toolchain/scripts/activate.sh
bash ./semogsite-toolchain/scripts/doctor.sh

bash ./semogsite-toolchain/scripts/install-offline.sh \
  /path/to/SemogSite

bash ./semogsite-toolchain/scripts/doctor.sh \
  /path/to/SemogSite
```

The installer uses pnpm `--offline`, disables dependency lifecycle scripts, and restores the verified SQLite native binary from the bundle.

When changing dependency inputs intentionally, allow lockfile regeneration with:

```bash
SEMOGSITE_FROZEN_LOCKFILE=0 \
  bash ./semogsite-toolchain/scripts/install-offline.sh \
  /path/to/SemogSite
```

The wrapper below always uses the bundled store and offline mode:

```bash
./semogsite-toolchain/bin/pnpm-offline \
  --dir /path/to/SemogSite test
```

## Expected gates

```bash
pnpm -r typecheck
pnpm -r test
pnpm -r build
pnpm exec playwright test
```

Playwright uses the bundled browser through `PLAYWRIGHT_BROWSERS_PATH`.

## Regenerate when

Regenerate after changes to Node, pnpm, workspace manifests, `pnpm-lock.yaml`, pnpm build policy, Playwright, Wrangler, Drizzle, `better-sqlite3`, Node ABI, or native hydration logic. Update `triggers/semogsite-toolchain.json` or run the workflow manually.

Artifacts expire after one day and are split into 400 MiB parts.

## Validation boundary

A green fixture run proves that the dependency set resolves, a clean second workspace installs from the captured store with `--offline`, SQLite loads from the native asset, Chromium launches without a browser download, and the principal CLIs are present. It does not prove future application code until the real SemogSite manifests and lockfile are represented.
