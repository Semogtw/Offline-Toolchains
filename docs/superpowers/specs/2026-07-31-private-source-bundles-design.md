# Encrypted private source bundles

## Goal

Allow connector-only development sessions to obtain a complete offline Git checkout of `Semogtw/goanime-mobile` or `Semogtw/Zapzap` without publishing private source code in clear text and without consuming private-repository Actions minutes.

## Approved scope

The public `Offline-Toolchains` repository creates encrypted exports for two fixed private repositories:

- `goanime` → `Semogtw/goanime-mobile`;
- `zapzap` → `Semogtw/Zapzap`.

Three export modes are supported:

- `full`: all fetched branches, tags and reachable history in a Git bundle;
- `ref`: one validated branch, tag or commit in a Git bundle;
- `snapshot`: tracked files for one validated ref, without Git history.

Git LFS objects, submodule repositories, local-only commits, stashes and untracked files are intentionally excluded.

## Security model

The privileged workflow uses a fine-grained PAT stored as the Actions secret `PRIVATE_REPOSITORIES_TOKEN`. The token must have `Contents: read-only` access only to the two private repositories and should have an expiration date.

The public repository stores only an OpenPGP public encryption key. The matching private key never enters GitHub and is required only in the isolated environment that decrypts a bundle.

Plaintext private source is never uploaded. The workflow creates the export on an ephemeral runner, packages it, encrypts it with GPG, deletes the plaintext checkout and package, splits the ciphertext, and uploads only ciphertext plus public transfer checksums.

The committed public-key fingerprint is:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

The workflow verifies this fingerprint after importing the public key and fails closed on mismatch.

## Trigger architecture

The connector cannot invoke `workflow_dispatch`, so automated requests use two workflows:

1. `Request private source bundle` runs without secrets after a push to `build/source-bundles` that changes `triggers/private-source-bundle.json`. It validates the public request file only.
2. `Build encrypted private source bundle` runs from the default branch through `workflow_run`. It accepts only a successful request from branch `build/source-bundles`, created by the repository owner. Because the privileged workflow definition comes from `main`, request-branch changes cannot modify the code that receives the PAT.

The privileged workflow also supports manual `workflow_dispatch` for browser use.

Request schema:

```json
{
  "project": "goanime",
  "mode": "full",
  "ref": ""
}
```

`project` is allowlisted to `goanime` or `zapzap`. `mode` is allowlisted to `full`, `ref` or `snapshot`. `ref` may be empty; otherwise it is interpreted only as an exact branch, exact tag or hexadecimal commit ID, never as an arbitrary Git revision expression.

## Export construction

For `full`, remote-tracking branches fetched by `actions/checkout` are copied to local `refs/heads/*` before `git bundle create --all`, ensuring the export carries every fetched branch and tag.

For `ref`, the workflow resolves only one of:

- `refs/heads/<ref>`;
- `refs/remotes/origin/<ref>`;
- `refs/tags/<ref>`;
- a hexadecimal commit ID.

It then creates a deterministic `refs/heads/offline-export` head and bundles that head.

For `snapshot`, `git archive` exports tracked files from the resolved commit.

The encrypted package contains `PRIVATE-MANIFEST.json`, `REFS.txt` and either `repository.bundle` or `snapshot.tar.zst`.

## Transport format

The ciphertext is split into 400 MiB files so every artifact remains below the connector's observed 512 MiB download limit. The maximum supported transfer is 16 parts, approximately 6.25 GiB of ciphertext.

Artifacts are retained for one day:

- `private-source-<project>-<mode>-manifest`;
- `private-source-<project>-<mode>-part-000` through `part-015` as needed.

The public manifest artifact contains only transfer metadata, the encryption fingerprint and SHA-256 checksums. Commit, branch and repository metadata remain inside the encrypted package.

## Local assembly and restore flow

The public repository deliberately does not contain code that imports or stores the private key.

`scripts/assemble-source-bundle.sh` accepts a directory containing downloaded artifact ZIPs or already-extracted artifact files and an output ciphertext path. It:

1. extracts artifact wrappers;
2. validates the public transfer manifest;
3. verifies per-part SHA-256 checksums;
4. requires every numbered part;
5. concatenates ciphertext parts in numeric order;
6. verifies the complete ciphertext checksum.

Decryption is an explicit local operation performed with a temporary GPG keyring prepared outside the repository:

```bash
export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
gpg --import /secure/path/offline-toolchains-source-bundles-private.asc
gpg --output private-source-package.tar.zst --decrypt private-source.gpg
```

After extraction, a Git bundle is verified and fetched into a new repository, or a snapshot is extracted. The encrypted private manifest supplies the repository, commit, mode and requested ref needed for restoration.

## Failure handling

The workflows fail before upload when:

- the request schema is invalid;
- the triggering branch or actor is not trusted;
- the PAT cannot read the selected repository;
- the selected ref does not resolve exactly;
- the public-key fingerprint differs;
- bundle verification fails;
- ciphertext exceeds 16 parts;
- an expected artifact part is missing.

The local assembly script fails when a wrapper, manifest, part or checksum is missing or invalid. No fallback may upload or reconstruct unverified plaintext.

## Validation

Pull requests run secret-free validation covering:

- JSON request schema and ref rejection cases;
- shell syntax for the assembly script;
- public-key fingerprint;
- required workflow guards, retention and 400 MiB segmentation;
- fixed private-repository mappings;
- absence of private-key blocks and token-looking values from tracked files.

A real encrypted export cannot be runtime-tested until `PRIVATE_REPOSITORIES_TOKEN` is configured. A successful static validation is not evidence that the token can access either private repository.