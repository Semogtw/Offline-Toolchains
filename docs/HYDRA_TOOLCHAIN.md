# Hydra offline toolchain and encrypted source export

Hydra uses two separate public-runner paths in `Offline-Toolchains`:

- `Build Hydra offline toolchain` creates a Linux x64 cache of **public third-party runtimes/dependencies** needed by the private project, while sanitizing private project metadata before upload.
- `Build encrypted private source bundle` exports Hydra source only as OpenPGP ciphertext through the shared private-source pipeline.

Private source is never intentionally published as a normal Actions artifact.

## Required secret

Both paths use:

```text
PRIVATE_REPOSITORIES_TOKEN
```

Use a fine-grained token with `Contents: Read-only` and repository access limited to the private projects served by this hub. Do not grant write access.

## Offline toolchain

Workflow:

```text
.github/workflows/build-hydra.yml
```

The job:

1. validates an allowlisted Hydra ref;
2. checks out only `Semogtw/HydraPersonalizado`, with `persist-credentials: false`, no LFS and no submodules;
3. installs pinned Node `22.23.1`, Yarn `1.22.22`, Rust and GTK4 Layer Shell prerequisites;
4. hydrates Yarn/Cargo/Electron/electron-builder/node-gyp caches from the exact private dependency inputs;
5. runs Hydra typechecks/tests online;
6. proves a second install with registries, mirrors, proxies and Cargo networking forced offline;
7. removes the private checkout;
8. replaces copied `package.json`, `yarn.lock` and both `Cargo.lock` files with SHA-256 fingerprints only;
9. redacts the selected private ref from the public manifest;
10. rebuilds the archive **after** sanitization and uploads the sanitized split transfer only.

The uploaded artifact is:

```text
hydra-toolchain-linux-x64-sanitized
```

It expires after one day and contains:

- `hydra-toolchain-linux-x64.part-*` — split sanitized archive;
- `SHA256SUMS.parts` — per-part integrity;
- `ARCHIVE.sha256` — reassembled archive hash;
- `PARTS.txt` — restore commands and compatibility fingerprints;
- `MANIFEST.txt` — runtime/toolchain versions with the private ref redacted;
- `INPUT-SHA256.txt` — fingerprints of the exact private dependency inputs, not their contents.

The exact private lockfiles/package manifest are **not** included in the public transfer anymore.

### Restore

Download/extract the single Actions artifact and run:

```bash
sha256sum -c SHA256SUMS.parts
cat hydra-toolchain-linux-x64.part-* > hydra-toolchain-linux-x64.tar.zst
sha256sum hydra-toolchain-linux-x64.tar.zst
tar --zstd -xf hydra-toolchain-linux-x64.tar.zst

source ./hydra-toolchain/scripts/activate.sh
./hydra-toolchain/scripts/doctor.sh
./hydra-toolchain/scripts/install-offline.sh /path/to/HydraPersonalizado
```

`install-offline.sh` hashes the target project's `package.json`, `yarn.lock` and Cargo lockfiles locally and compares them to `INPUT-SHA256.txt`. A mismatch fails closed without needing the original private input files inside the toolchain.

The host still needs distribution-specific system libraries checked by `doctor.sh`, notably Python 3, `pkg-config`, GTK 4 and GTK4 Layer Shell development metadata.

## Encrypted private source

Use the canonical workflow:

```text
.github/workflows/build-private-source-bundle.yml
```

Select:

```text
project=hydra
mode=full | ref | snapshot
ref=<optional validated branch/tag/SHA>
```

The workflow packages private Git/source data in temporary storage, encrypts it to the committed OpenPGP public key, deletes the plaintext archive/private checkout/keyring before upload and publishes only ciphertext plus sanitized transport metadata with one-day retention.

Recipient fingerprint:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

The private OpenPGP key never enters GitHub Actions.

## Security invariants

- Private checkout token is read-only and repository-scoped.
- Checkout credentials are never persisted.
- Private source is removed in cleanup paths.
- Toolchain artifacts contain public runtime/dependency caches plus one-way compatibility fingerprints, not raw private package/lock inputs.
- Exact private ref/commit details are omitted from public toolchain transfer metadata wherever they are not required.
- Source export is ciphertext-only and expires after one day.
- Any future write/deploy capability must use a separate narrowly scoped credential rather than expanding `PRIVATE_REPOSITORIES_TOKEN`.
