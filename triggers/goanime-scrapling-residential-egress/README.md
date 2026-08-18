# Retired GoAnime residential trigger path

The standalone residential workflow was retired on 2026-08-18.

Residential fallback is now part of `.github/workflows/goanime-scrapling-provider-cache.yml`, which owns the complete trusted flow: source-bound request validation, MAL input preflight, deterministic tests, direct crawl, selective phone/Tailscale retry, public-egress-change verification, cache validation, cache-only diff enforcement, immutable-source race check, and publication.

Do not add new `.request` files in this directory. Historical request files are retained only as provenance for the earlier plumbing work.

New refresh requests belong in `triggers/goanime-scrapling-provider-cache/` and must include:

```text
target_branch=feat/scrapling-provider-pipeline
source_hint=<full 40-character GoAnime commit SHA>
reason=<short human-readable reason>
```
