# GoAnime deterministic offline cache design

## Goal

Keep the public GoAnime base toolchain portable while allowing the private repository's hosted `pubspec.lock` entries to be supplied exactly through a small incremental artifact.

## Design

The base Flutter/Gradle/PowerShell toolchain changes only when SDK or build-tool versions change. A separate exact-lock delta changes whenever GoAnime's hosted lock changes. The delta contains a sanitized package/version manifest, an exact Pub cache, a verifier, the relocatable Flutter repair helper, and an idempotent installer that overlays the cache onto an extracted base toolchain and creates `activate-exact.sh`.

A standard-library Python helper extracts hosted entries from a private lock, validates conservative package/version alphabets, generates a synthetic Flutter pubspec, and verifies every exact package directory. GitHub Actions hydrates that graph, packages only the delta, splits it into connector-safe 400 MiB parts, and validates it with both download endpoints pointed at unreachable loopback.

## Security

The public manifest contains no lock descriptions, hosted URLs, path or Git dependencies, repository ref, private commit, token, signing data, or source code. The private OpenPGP key is used only in a temporary local keyring to recover the source bundle and is never copied into either repository or an artifact.

## Testing

Python tests cover sanitization, exact pubspec generation, and cache diagnostics. Shell tests cover repair after relocation and safe application of the delta. A static contract validates workflow integration, 400 MiB segmentation, one-day retention, and air-gapped locked resolution.
