# Private Source Bundles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build connector-downloadable, encrypted Git exports of the private GoAnime Mobile and ZapZap repositories while keeping private source, credentials and decryption keys outside the public repository.

**Architecture:** A secret-free request workflow validates a strict JSON request on a dedicated branch. A privileged default-branch `workflow_run` maps the allowlisted project to a fixed private repository, creates a full/ref bundle or snapshot, encrypts it with a committed OpenPGP public key, splits the ciphertext into 400 MiB artifacts, and uploads them for one day. A public assembly script verifies and reconstructs ciphertext; decryption remains an explicit local GPG operation outside the repository.

**Tech Stack:** GitHub Actions, Bash, Python 3, Git bundle/archive, GnuPG, zstd, SHA-256.

## Global Constraints

- Supported projects are exactly `goanime` and `zapzap`.
- Supported modes are exactly `full`, `ref` and `snapshot`.
- The private PAT secret is named `PRIVATE_REPOSITORIES_TOKEN` and must be contents-read-only.
- The committed public-key fingerprint is `2DE29DC31427CF0A911AB96175679291435059B0`.
- Private source must be encrypted before upload; no plaintext fallback is allowed.
- Each downloadable artifact must remain below the connector's 512 MiB limit; split size is 400 MiB.
- Artifacts expire after one day.
- Maximum encrypted transfer size is 16 parts.
- Git LFS, submodule repositories, untracked files, stashes and local-only commits are out of scope.
- The public repository must never import, store or upload the private decryption key.

---

### Task 1: Encryption identity and request schema

**Files:**
- Create: `keys/source-bundles-public.asc`
- Create: `triggers/private-source-bundle.json`
- Create: `scripts/validate-source-bundle-request.py`

**Interfaces:**
- Consumes: JSON request fields `project`, `mode`, and `ref`.
- Produces: normalized JSON on stdout and a non-zero exit code for invalid input.

- [x] Commit only the generated OpenPGP public key with fingerprint `2DE29DC31427CF0A911AB96175679291435059B0`.
- [x] Add the default request:

```json
{
  "project": "goanime",
  "mode": "full",
  "ref": ""
}
```

- [x] Reject unknown fields, non-string values, unsupported projects/modes and Git revision expressions while accepting ordinary branch paths.
- [x] Verify valid, invalid-project and invalid-revision cases in the static guard.

### Task 2: Secret-free request workflow

**Files:**
- Create: `.github/workflows/request-private-source-bundle.yml`

**Interfaces:**
- Consumes: `triggers/private-source-bundle.json` on branch `build/source-bundles`.
- Produces: successful workflow conclusion only after schema, key and static-security validation.

- [x] Trigger `push` only for branch `build/source-bundles` and request-file changes.
- [x] Trigger PR validation only for files that own the feature.
- [x] Check out with `persist-credentials: false`.
- [x] Validate the request and exact public-key fingerprint without secrets.
- [x] Run `scripts/validate-private-source-workflows.sh`.

### Task 3: Privileged encrypted export workflow

**Files:**
- Create: `.github/workflows/build-private-source-bundle.yml`

**Interfaces:**
- Consumes: a successful trusted `workflow_run`, or manual `workflow_dispatch` inputs.
- Produces: one manifest artifact and up to 16 encrypted part artifacts.

- [x] Require successful request workflow, branch `build/source-bundles`, event `push`, and actor equal to `github.repository_owner`.
- [x] Map projects internally:

```text
goanime -> Semogtw/goanime-mobile
zapzap  -> Semogtw/Zapzap
```

- [x] Checkout private source with `fetch-depth: 0`, `persist-credentials: false`, `lfs: false`, `submodules: false`, and `${{ secrets.PRIVATE_REPOSITORIES_TOKEN }}`.
- [x] For `full`, materialize fetched remote branches under `refs/heads/*`, create `repository.bundle --all`, and verify it.
- [x] For `ref`, resolve only an exact branch, tag or hexadecimal commit, create `refs/heads/offline-export`, bundle it and verify it.
- [x] For `snapshot`, archive tracked files from the exact resolved commit.
- [x] Package a private manifest and refs list, verify the public-key fingerprint, encrypt with GPG, delete plaintext checkout/package data, split at `400M`, and fail above 16 parts.
- [x] Upload manifest and conditional parts `000` through `015` with `compression-level: 0` and `retention-days: 1`.

### Task 4: Ciphertext assembly utility

**Files:**
- Create: `scripts/assemble-source-bundle.sh`

**Interfaces:**
- Consumes: artifact ZIP wrappers or extracted artifact files and an output ciphertext path.
- Produces: one checksum-verified `private-source.gpg` file.

- [x] Extract ZIP wrappers into an isolated temporary directory.
- [x] Validate `TRANSFER.json` schema and part count.
- [x] Require every numbered part from `000` through the declared count.
- [x] Verify `SHA256SUMS.parts` before concatenation.
- [x] Concatenate using version ordering and verify `ENCRYPTED.sha256`.
- [x] Verify shell syntax with:

```bash
bash -n scripts/assemble-source-bundle.sh
```

Decryption intentionally remains outside the repository:

```bash
export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
gpg --import /secure/path/offline-toolchains-source-bundles-private.asc
gpg --output private-source-package.tar.zst --decrypt private-source.gpg
```

### Task 5: Documentation and static security validation

**Files:**
- Modify: `README.md`
- Create: `scripts/validate-private-source-workflows.sh`

**Interfaces:**
- Consumes: committed workflows, key, request and scripts.
- Produces: exit 0 only when the documented security invariants remain present.

- [x] Document PAT scope, public/private key split, browser and connector triggers, artifact expiry, unsupported LFS/submodules, assembly, local decryption, Git restoration and key rotation.
- [x] Guard workflow files, fixed repository mappings, trusted `workflow_run` conditions, `persist-credentials: false`, exact fingerprint, `400M`, one-day retention and maximum part `015`.
- [x] Reject tracked private-key block headers and token-looking values.
- [x] Run the guard in secret-free PR validation.

### Task 6: Pull request validation and activation

**Files:**
- No new implementation files.

**Interfaces:**
- Consumes: completed feature branch.
- Produces: merged default-branch workflows and a persistent connector trigger branch.

- [x] Open draft PR #2 and inspect the complete diff.
- [x] Observe secret-free schema, fingerprint and static guard validation passing.
- [ ] Merge after the final diff review.
- [ ] Create `build/source-bundles` from updated `main` and keep a draft PR open as the connector-controlled request surface.
- [ ] Add the read-only PAT secret before attempting the first encrypted source export.

## Verification record

Executed on GitHub-hosted Ubuntu 24.04 without private-repository credentials:

```text
Validate request schema: passed
Verify committed encryption key: passed
Run static security guards: passed
```

Runtime private checkout and encrypted artifact generation remain intentionally unverified until `PRIVATE_REPOSITORIES_TOKEN` is configured.