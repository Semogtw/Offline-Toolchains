# Artifact Platform v2 Design

## Status

Approved for implementation by the repository owner on 2026-07-31.

## Goal

Turn `Semogtw/Offline-Toolchains` from a collection of independent builders into a reproducible artifact platform that can restore a private workspace, select the smallest compatible toolchain profile, verify every transport and compatibility boundary, reuse equivalent live artifacts, remove superseded artifacts, and expose connector-discoverable run receipts.

## Non-goals

- Do not publish private source, plaintext source packages, signing material, Firebase configuration, TURN credentials, private keys or repository credentials.
- Do not accept arbitrary private repository names.
- Do not create a single multi-gigabyte artifact.
- Do not require Docker in the restoring environment.
- Do not treat a public toolchain build as product-test evidence for GoAnime or ZapZap.
- Do not place the OpenPGP private key in GitHub, even in a private repository.

## Security invariants

1. `PRIVATE_REPOSITORIES_TOKEN` remains a fine-grained PAT with `Contents: read-only` access only to `Semogtw/goanime-mobile` and `Semogtw/Zapzap`.
2. Workflows receiving the PAT are loaded only from the default branch through a validated `workflow_run` boundary.
3. Request branches contain data only; request-branch workflow code is never executed with private credentials.
4. Private checkouts, generated plaintext packages and temporary credentials are deleted before artifact upload.
5. Source artifacts are always encrypted to fingerprint `2DE29DC31427CF0A911AB96175679291435059B0` before upload.
6. Toolchain artifacts may contain public dependencies and their versions, but never private repository files.
7. Artifact reuse is permitted only when profile, platform, architecture, schema, builder revision and lock fingerprint all match.
8. Cleanup never deletes the current run, artifacts with a different fingerprint, source-bundle artifacts, or artifacts whose grouping cannot be proven.
9. Every extraction path is validated against traversal and every checksum is verified before extraction or decryption.

## Architecture

The platform has six bounded components.

### 1. Profile registry

Machine-readable JSON descriptors in `profiles/` define logical capabilities rather than one giant archive.

Concrete profiles:

- `android-base`: JDK 17, Android SDK 35/36, build-tools, platform-tools, NDK and CMake.
- `jdk21`: Temurin JDK 21.
- `goanime-analysis`: Flutter/Dart, exact Pub cache, PowerShell and analysis/test capability.
- `goanime-android`: exact Android Gradle cache for the GoAnime lock/configuration; requires `android-base` and `goanime-analysis`.
- `zapzap-pure`: JDK 21 plus exact Gradle/JVM dependency cache for pure/unit gates.
- `zapzap-android`: exact Android/Compose/Gradle dependency cache; requires `android-base`, `jdk21` and `zapzap-pure`.
- `goanime-full`: logical aggregate of `android-base`, `goanime-analysis` and `goanime-android`.
- `zapzap-full`: logical aggregate of `android-base`, `jdk21`, `zapzap-pure` and `zapzap-android`.

Aggregate profiles publish no mega-archive. The local resolver expands `requires` and downloads only missing package families.

Each descriptor records project, package families, required host OS/architecture, activation order, doctor checks and lock inputs.

### 2. Uniform artifact contract

Every package set publishes a small manifest artifact and zero or more part artifacts. The manifest contains:

- `schema_version` fixed at `2`;
- `artifact_set_id` containing profile, fingerprint prefix and run ID;
- profile and package names;
- builder workflow and exact workflow commit;
- runner OS and architecture;
- creation and expiry timestamps;
- lock fingerprint and builder fingerprint;
- archive name, size and SHA-256;
- ordered part names, sizes, SHA-256 values and artifact names;
- activation script path;
- doctor script path;
- required profiles;
- software inventory entries with name, version, source and license when known;
- compatibility requirements;
- source-export metadata only when the manifest itself is encrypted.

The human-readable `PARTS.txt`, `SHA256SUMS.parts` and SPDX 2.3 JSON inventory remain alongside `artifact-set.json`.

Artifact names include the profile, a 16-character fingerprint prefix, the run ID and role. This makes grouping and cleanup unambiguous while keeping each ZIP below the connector's 512 MiB limit. Archive parts remain 400 MiB.

### 3. Deterministic private-lock builders

A connector request in `triggers/toolchain-build.json` selects one concrete or aggregate profile. A secret-free request workflow validates the JSON. A privileged default-branch workflow then:

1. maps the profile to one of the two fixed private repositories;
2. performs a full read-only checkout with credentials not persisted;
3. computes the lock fingerprint from an explicit allowlist of project files;
4. resolves the exact public dependency graph on the private checkout;
5. proves an offline gate against that checkout;
6. extracts only SDKs and public caches into package roots;
7. creates the uniform manifest and software inventory;
8. removes the private checkout before upload;
9. reuses a live artifact set when the complete fingerprint matches;
10. otherwise uploads one-day manifest and part artifacts.

GoAnime lock inputs:

- `pubspec.yaml`;
- `pubspec.lock`;
- `packages/*/pubspec.yaml`;
- `packages/*/pubspec.lock` when present;
- `android/gradle/wrapper/gradle-wrapper.properties`;
- Android settings/build files that pin AGP, Kotlin and plugins.

The online phase runs `flutter pub get --enforce-lockfile`; the offline proof runs `flutter pub get --offline --enforce-lockfile` on the same checkout. Android profiles also execute a focused Gradle dependency/build gate offline.

ZapZap lock inputs:

- Gradle wrapper properties;
- settings and root/module Gradle files;
- version catalogs and dependency lock files;
- `Cargo.toml` and `Cargo.lock` for profiles that include native dependencies.

The online phase resolves the requested tasks; the offline proof reruns the profile's Gradle tasks with `--offline` and a project-scoped `GRADLE_USER_HOME`.

The public synthetic builders remain available as bootstrap/fallback builders. Their manifests use `lock_mode: synthetic`; the deterministic builder uses `lock_mode: private-exact`. The restoring client rejects synthetic artifacts when exact-lock mode is required.

### 4. Catalog, reuse and cleanup

Issue `Toolchain artifact catalog` is the connector-facing status panel. A reporter workflow triggered after all toolchain workflows:

- records workflow/run IDs, conclusion, profile, fingerprints, artifact IDs, sizes and expiry;
- reports whether the run built or reused an existing set;
- updates one marker-delimited comment per profile rather than growing unbounded duplicate comments;
- records cleanup actions and bytes removed;
- never prints private refs or file contents.

Before a build, the privileged workflow queries repository artifacts by exact artifact-set prefix. Reuse is allowed only when every expected artifact exists, is unexpired and matches the manifest contract. A reuse receipt points to those existing artifact IDs and avoids rebuilding.

After a successful new upload, the reporter deletes older complete sets for the same profile and full fingerprint while preserving the newest set. It also deletes incomplete orphan sets older than six hours. Source-bundle artifacts are excluded by prefix and never touched.

### 5. Local restore and diagnostics

`scripts/restore-workspace.sh` is the primary user interface. It accepts:

- project (`goanime` or `zapzap`);
- downloads directory containing connector-downloaded ZIPs;
- OpenPGP private-key path;
- destination checkout path;
- optional branch/ref;
- requested logical profile;
- optional exact-lock requirement;
- optional cleanup suppression.

It performs:

1. dependency/tool preflight;
2. safe ZIP extraction;
3. manifest-schema validation;
4. part and final-archive checksum validation;
5. encrypted source assembly and fingerprint validation;
6. temporary-keyring decryption;
7. Git-bundle verification and offline checkout restoration;
8. profile dependency expansion;
9. platform/architecture/schema/fingerprint compatibility checks;
10. toolchain extraction and activation-file generation;
11. package and aggregate doctor checks;
12. `git fsck --full --no-dangling`;
13. a machine-readable restoration report;
14. deletion of ZIPs, ciphertext, plaintext package, keyring and temporary extraction directories by default.

The script never sources an artifact-provided activation script during validation. It reads paths from manifests, validates them, then writes a local `activate-workspace.sh` that sources the validated scripts in registry order.

`scripts/doctor.sh` supports human text and `--json`. It checks manifest compatibility, required executables, declared versions, cache directories and optional project-specific offline commands. It returns nonzero for `incompatible` or `missing`, and distinguishes `ready`, `partial` and `not_applicable`.

### 6. Validation and governance

The repository gains tests that run without private credentials:

- JSON schema validation for profiles, requests and manifests;
- fixture-based restore tests with tiny split archives and a temporary GPG key;
- malicious ZIP/path traversal rejection;
- mixed-run part rejection;
- architecture/schema/fingerprint mismatch rejection;
- aggregate-profile dependency ordering;
- doctor JSON contract;
- catalog comment rendering;
- cleanup dry-run selection;
- workflow guards for PAT boundaries, fixed repository mappings, one-day retention, 400 MiB parts and source checkout deletion.

A privileged integration run is required to claim exact-lock success. Secret-free PR checks validate everything else.

## Data flow

### Toolchain build

`toolchain-build.json` → secret-free validator → default-branch privileged builder → fixed private checkout → lock fingerprint → existing-artifact lookup → reuse receipt or exact dependency hydration/offline proof → source deletion → package/manifest/SBOM upload → reporter/catalog → safe cleanup.

### Workspace restoration

Connector downloads source/toolchain manifest and part artifacts → `restore-workspace.sh` validates and assembles → temporary GPG keyring decrypts source → Git bundle restores checkout → profile resolver validates and extracts toolchains → doctor verifies → local activation/report generated → transient sensitive files deleted.

## Failure handling

- Invalid request: fail before any privileged workflow starts.
- Missing PAT: fail with a generic setup message and no repository details beyond the fixed project key.
- Exact offline proof failure: upload no toolchain artifact; reporter records failure.
- Existing artifact incomplete or expired: do not reuse; build fresh.
- Catalog/report failure: must not invalidate a successfully built artifact, but is surfaced as a separate failed reporter run.
- Cleanup failure: report and continue; never delete uncertain sets.
- Restore checksum/schema/compatibility failure: stop before extraction or decryption where possible and preserve a diagnostic report without secret material.
- Restore cleanup trap runs on success, failure and interruption.

## Acceptance criteria

1. A fixture workspace can be restored end-to-end by one command with no network access.
2. Every package family emits schema-v2 manifest, SPDX inventory, checksums, doctor and 400 MiB-or-smaller artifacts.
3. Aggregate profiles resolve into ordered package families without producing a mega-archive.
4. A second identical profile request reuses an unexpired set instead of rebuilding.
5. A changed lock input produces a different fingerprint and cannot reuse the old set.
6. Superseded equivalent artifacts are deleted without touching source bundles or unrelated profiles.
7. GoAnime exact builder proves `flutter pub get --offline --enforce-lockfile` on the private checkout.
8. ZapZap exact builder proves the configured Gradle gates with `--offline` and JDK 21.
9. Catalog issue entries expose connector-downloadable artifact IDs and expiry.
10. Restore rejects mixed parts, wrong architecture, unsupported schema, wrong encryption key and incompatible lock fingerprints.
11. No private key, PAT, private source or plaintext source package is committed or uploaded.
