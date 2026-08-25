# GoAnime MegaPlay cache

This document describes the public cache contract used by the optional MegaPlay integration.

The cache is independent from the normal provider data and is only relevant when the corresponding application mode is enabled.

## Public artifacts

The published cache consists of:

- `manifest.json` — active cache metadata;
- a content-addressed SQLite catalog asset;
- optional aggregate statistics for diagnostics.

Consumers should resolve the active database through the manifest rather than hard-coding an asset filename.

## Publication contract

A new generation is considered active only after its database asset has been uploaded and validated and the corresponding manifest has been published.

The manifest should include enough information for a consumer to verify that it downloaded the intended generation, including the asset name, digest, schema/version metadata, and generation timestamp where applicable.

## Refresh modes

The collector supports two logical modes:

- `recent` — refreshes the newest catalog window;
- `backfill` — advances historical coverage incrementally.

Backfill progress is persisted in cache metadata so a complete historical refresh can be performed over multiple bounded runs rather than one very large crawl.

## Reliability behavior

The collector should preserve the previous known-good generation when a refresh cannot be completed safely.

Expected behavior includes:

- rate-limit aware retry/backoff;
- bounded request cadence;
- fail-closed handling for provider rejection or malformed responses;
- validation before publication;
- atomic generation switching through the manifest;
- no replacement of a valid cache with an empty or materially invalid result.

## Consumer behavior

Consumers should:

1. fetch the manifest;
2. validate the supported schema/version;
3. download the referenced database asset;
4. verify its digest before use;
5. retain the previous valid generation until the new one has been validated locally.

The public cache contract intentionally does not document maintainer credentials, deployment topology, private repository state, or internal automation handoffs.
