# GoAnime full CI request files

`run-private-goanime-ci.yml` supports exact-ref validation without requiring a manual `workflow_dispatch` call.

## Trigger

Create or update exactly one file under:

```text
triggers/goanime-full-ci/*.request
```

The entire file body is the GoAnime ref to validate. Prefer an immutable commit SHA:

```text
cd4d55fccbac26d8f0118d6a387e4ea6d01f1b8a
```

A push that changes one request file triggers the full CI workflow. The workflow reads the changed path from the GitHub push event, loads the file from the trusted Toolchains checkout and passes the value through `scripts/private_ci_request.py` before checkout.

It does not accept repository names from the request. The repository mapping remains fixed to `Semogtw/goanime-mobile`.

## Gates

The full CI performs, on the requested private ref:

- private read-only checkout;
- pinned Flutter 3.44.1 and JDK 17 setup;
- app/core dependency resolution;
- project-health validation;
- Python tooling tests;
- repository guards;
- Dart formatting check;
- Flutter analyze;
- Flutter application tests;
- `goanime_core` tests;
- release-workflow invariants;
- Android debug APK build without publication;
- private checkout/request cleanup.

The workflow summary omits private repository/ref/commit details and discards the debug APK after verification.

## Pushes that change workflow infrastructure

For backward compatibility, pushes that modify only `run-private-goanime-ci.yml` or `scripts/private_ci_request.py` still validate `main` when no request file is part of the head commit.

The workflow uses concurrency group `private-goanime-full-ci` with `cancel-in-progress: true`. A subsequent exact-ref request supersedes an infrastructure-triggered `main` run rather than wasting a second full validation.

## Safety rules

- A request-file push may add/modify at most one `goanime-full-ci` request file.
- Empty request files fail normalization.
- The trigger path accepts only `[A-Za-z0-9._-]+.request` names.
- Newline-containing refs are rejected before checkout.
- `PRIVATE_REPOSITORIES_TOKEN` remains read-only checkout material and is never written into the private checkout.
- Do not put tokens, credentials or repository URLs in request files.
