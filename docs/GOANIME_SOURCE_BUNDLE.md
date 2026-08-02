# GoAnime-Mobile private source bundle

## Purpose

This workflow exports an encrypted source snapshot of `Semogtw/goanime-mobile` for offline validation environments. It is a transport mechanism, not a test runner and not a substitute for repository gates.

## Isolated request flow

GoAnime-Mobile uses a dedicated workflow file:

```text
.github/workflows/request-goanime-source-bundle.yml
```

It intentionally keeps the workflow display name expected by the trusted builder:

```text
Request private source bundle
```

The generic request workflow no longer runs on `build/source-bundles`; it remains limited to SemogSite and Hydra request branches. This prevents unrelated requests from racing or replacing the GoAnime request observed by the builder.

The GoAnime request path is:

```text
push triggers/private-source-bundle.json on build/source-bundles
  -> validate request schema and project=goanime
  -> verify the tracked public OpenPGP fingerprint
  -> workflow_run on trusted main builder
  -> checkout private repository with PRIVATE_REPOSITORIES_TOKEN
  -> resolve exact ref
  -> archive, encrypt and split
  -> upload one-day artifacts and public receipt metadata
```

## Security boundary

The branch workflow has only:

```yaml
permissions:
  contents: read
```

It never receives `PRIVATE_REPOSITORIES_TOKEN` or any private OpenPGP key. The secret-bearing builder remains versioned on the default branch and accepts the request only when all of these are true:

- request workflow concluded successfully;
- head branch is exactly `build/source-bundles`;
- event is a push;
- actor is the repository owner;
- request schema is valid;
- project is in the builder allowlist.

The repository tracks only the public encryption key. The private key must stay outside Git, be imported into a temporary `GNUPGHOME`, and be deleted after use.

## Request format

For an exact commit:

```json
{
  "project": "goanime",
  "mode": "ref",
  "ref": "FULL_40_CHARACTER_COMMIT_SHA"
}
```

Use a full commit SHA for validation checkpoints. Branch names are supported by the schema, but a branch can move between request and later comparison.

## Required consumer validation

Never trust an artifact only because its name contains `goanime`.

Before extraction or testing:

1. download the public artifact manifest and all encrypted parts;
2. verify every part size and SHA-256 from the public manifest;
3. import the private key into a temporary `GNUPGHOME`;
4. decrypt and concatenate exactly the listed parts;
5. verify the plaintext archive SHA-256;
6. extract into a new directory;
7. read `PRIVATE-MANIFEST.json` inside the archive;
8. require `project == goanime`;
9. require both requested and resolved refs to match the intended commit;
10. reject the bundle before running gates when any value differs.

A successful workflow run with the wrong resolved commit is not valid evidence for the requested head.

## Local gates after restoration

The source bundle does not contain or prove the Flutter toolchain. Run every gate available in the consumer environment.

Without Flutter/Dart:

```bash
python3 -m unittest discover -s tools/tests -p 'test_*.py'
python3 -m compileall -q tools
python3 tools/validate_repository_guards.py
bash tools/validate_release_workflows.sh
bash tools/validate_project_health.sh
git diff --check
```

With the exact GoAnime toolchain:

```bash
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
(cd packages/goanime_core && dart test)
```

Native Android SAF and Android/Windows HLS proofs still require appropriate target environments. A restored source archive or generated APK cannot replace those observations.

## Static validation

Run:

```bash
bash scripts/validate-private-source-workflows.sh
```

The guard verifies that:

- the generic request excludes the GoAnime branch;
- the dedicated request accepts only `project=goanime`;
- the public-key fingerprint is fixed;
- the trusted builder still checks branch, actor and event;
- secret material is not tracked;
- artifact splitting, retention and cleanup invariants remain present.
