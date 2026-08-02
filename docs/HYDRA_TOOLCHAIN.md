# Hydra offline toolchain and encrypted checkout

The Hydra integration provides two independent GitHub Actions in this public repository:

- `Build Hydra offline toolchain` creates a Linux x64 bundle with portable Node.js, Yarn Classic, Rust, Cargo registries and the exact dependency caches required by `Semogtw/HydraPersonalizado`.
- `Build encrypted Hydra source bundle` exports one exact Git ref from the private repository, encrypts it with the committed OpenPGP public key and uploads only ciphertext.

The source checkout is never included in the public toolchain archive.

## Required secret

Both workflows need the existing Actions secret:

```text
PRIVATE_REPOSITORIES_TOKEN
```

Use a fine-grained token with `Contents: Read-only` and access limited to `Semogtw/HydraPersonalizado` plus the other private repositories already served by this hub. Do not grant write access.

## Toolchain workflow

Workflow:

```text
.github/workflows/build-hydra.yml
```

It can be started manually with a branch, tag or commit, or by updating:

```text
triggers/hydra-toolchain.json
```

The build performs these gates before publishing:

1. validates the requested Git ref;
2. checks out the fixed private repository without persisted credentials, LFS or submodules;
3. installs the pinned Node `22.23.1` and Yarn `1.22.22`;
4. installs a portable Rust toolchain;
5. hydrates Yarn, Cargo, Electron, electron-builder and node-gyp caches from the exact Hydra lockfiles;
6. runs Hydra type checking and tests online;
7. removes generated dependencies and proves a second install from a fresh `HOME`, with package registries, Electron mirrors, proxies and Cargo networking forced offline;
8. reruns type checking and tests;
9. deletes the private checkout before creating the archive.

The isolated second installation is important: Electron binaries and native headers normally live outside Yarn's cache. Keeping those directories inside the archive and changing `HOME` prevents the proof from passing accidentally because of files already present on the GitHub runner.

Artifacts expire after one day:

```text
hydra-toolchain-linux-x64-manifest
hydra-toolchain-linux-x64-part-00
hydra-toolchain-linux-x64-part-01
...
```

Parts are limited to 400 MiB so they can be downloaded through the connector.

### Restore

Extract every artifact ZIP into one directory, then:

```bash
sha256sum -c SHA256SUMS.parts
cat hydra-toolchain-linux-x64.part-* > hydra-toolchain-linux-x64.tar.zst
sha256sum hydra-toolchain-linux-x64.tar.zst
tar --zstd -xf hydra-toolchain-linux-x64.tar.zst

source ./hydra-toolchain/scripts/activate.sh
./hydra-toolchain/scripts/doctor.sh
./hydra-toolchain/scripts/install-offline.sh /path/to/HydraPersonalizado
```

The portable bundle supplies Node, Yarn, Rust and dependency caches. The host still needs the Linux system libraries checked by `doctor.sh`, notably Python 3, `pkg-config`, GTK 4 and GTK4 Layer Shell development metadata. Those packages are distribution-specific and are intentionally not copied from Ubuntu into the portable archive.

## Encrypted checkout workflow

Trusted workflow:

```text
.github/workflows/build-private-hydra-source-bundle.yml
```

Connector request branch:

```text
build/hydra-source-bundles
```

Request file:

```text
triggers/hydra-source-bundle.json
```

The request is intentionally restricted to:

```json
{
  "project": "hydra",
  "mode": "ref",
  "ref": "main"
}
```

Only a non-empty exact branch, tag or commit is accepted. The privileged job runs from the workflow implementation on `main`, accepts only successful requests pushed by the repository owner to the fixed request branch and checks out only `Semogtw/HydraPersonalizado`.

The output artifact is:

```text
private-source-hydra-ref
```

It contains:

```text
private-source.gpg
ENCRYPTED.sha256
TRANSFER.json
```

The decrypted package contains `repository.bundle`, `REFS.txt` and `PRIVATE-MANIFEST.json`. It excludes Git LFS objects, submodule repositories, untracked files, stashes and commits that were never pushed.

### Decrypt and restore

Use the private key corresponding to fingerprint:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

Then:

```bash
sha256sum -c ENCRYPTED.sha256

export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
gpg --import /secure/path/offline-toolchains-source-bundles-private.asc
gpg --output private-source-package.tar.zst --decrypt private-source.gpg

mkdir private-source-package
tar --zstd -xf private-source-package.tar.zst -C private-source-package

git bundle verify private-source-package/repository.bundle
git init HydraPersonalizado
git -C HydraPersonalizado fetch \
  ../private-source-package/repository.bundle \
  refs/heads/offline-export:refs/remotes/origin/offline-export
git -C HydraPersonalizado switch -c offline-export --track origin/offline-export
```

## Security invariants

- No private key is stored in GitHub.
- The private token is read-only and repository-scoped.
- Request-branch code never executes with the private token.
- Checkouts do not persist credentials.
- The public toolchain artifact contains runtimes, caches, lockfiles and hashes, but no Hydra source tree.
- The encrypted checkout artifact has one-day retention and is useless without the external private key.
- Logs and transfer manifests omit the resolved private commit wherever practical; the commit remains inside the encrypted private manifest.
