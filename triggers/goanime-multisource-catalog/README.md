# Retired GoAnime multi-provider trigger path

The Dart multi-provider catalog refresh was retired on 2026-08-18 after the provider refresh responsibility moved to the source-bound Scrapling pipeline.

Historical `.request` files remain only as provenance. Do not add new requests here.

Use:

```text
triggers/goanime-scrapling-provider-cache/<identifier>.request
```

with a full GoAnime `source_hint`, and let `.github/workflows/goanime-scrapling-provider-cache.yml` own provider crawl, validation, residential fallback and cache publication.
