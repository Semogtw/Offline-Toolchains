#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, *, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one {label} anchor, found {count}")
    return text.replace(old, new, 1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo_root.resolve()

    build = repo / "tools/scrapling_provider_pipeline/build_provider_cache.py"
    tests = repo / "tools/scrapling_provider_pipeline/tests/test_provider_config_preflight.py"

    build_text = build.read_text(encoding="utf-8")
    build_text = replace_once(
        build_text,
        "import argparse\nimport importlib.metadata\nimport math\n",
        "import argparse\nimport importlib.metadata\nimport ipaddress\nimport math\nimport re\n",
        label="imports",
    )
    build_text = replace_once(
        build_text,
        "def _require_owned_provider_url(\n",
        '''_HOST_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")\n_PRIVATE_HOST_SUFFIXES = (\n    ".internal",\n    ".lan",\n    ".local",\n    ".localdomain",\n    ".localhost",\n    ".home.arpa",\n)\n\n\ndef _validate_owned_host(provider_id: str, raw_host: str) -> str:\n    host = raw_host.strip().lower().rstrip(".")\n    invalid = (\n        not host\n        or host != raw_host.strip().lower()\n        or "*" in host\n        or "://" in host\n        or "/" in host\n        or "@" in host\n        or ":" in host\n        or "." not in host\n        or len(host) > 253\n        or host == "localhost"\n        or host.endswith(_PRIVATE_HOST_SUFFIXES)\n        or any(not _HOST_LABEL_RE.fullmatch(label) for label in host.split("."))\n    )\n    if not invalid:\n        try:\n            ipaddress.ip_address(host)\n        except ValueError:\n            pass\n        else:\n            invalid = True\n    if invalid:\n        raise SystemExit(\n            f"Provider {provider_id} has invalid ownedHost: {raw_host!r}"\n        )\n    return host\n\n\ndef _validate_owned_host_scopes(configs: list[ProviderConfig]) -> None:\n    owners: list[tuple[str, str]] = []\n    for config in configs:\n        seen: set[str] = set()\n        for raw_host in config.owned_hosts:\n            host = _validate_owned_host(config.id, raw_host)\n            if host in seen:\n                raise SystemExit(\n                    f"Provider {config.id} declares duplicate ownedHost: {host}"\n                )\n            seen.add(host)\n            for other_provider, other_host in owners:\n                if other_provider == config.id:\n                    continue\n                if host == other_host or host.endswith("." + other_host) or other_host.endswith("." + host):\n                    raise SystemExit(\n                        "Provider ownedHost scopes overlap across providers: "\n                        f"{other_provider}={other_host}, {config.id}={host}"\n                    )\n            owners.append((config.id, host))\n\n\ndef _require_owned_provider_url(\n''',
        label="owned URL function",
    )
    build_text = replace_once(
        build_text,
        '''        if not config.roots and not config.sitemap:\n            raise SystemExit(\n                f"Provider {config.id} must declare at least one root or sitemap"\n            )\n\n        _require_owned_provider_url(config, config.base_url, label="baseUrl")\n''',
        '''        if not config.roots and not config.sitemap:\n            raise SystemExit(\n                f"Provider {config.id} must declare at least one root or sitemap"\n            )\n\n        # Validate the trust boundary itself before using it to validate URLs.\n        # Include already accepted providers so cross-provider overlaps also fail\n        # before any fetcher/network state can exist.\n        _validate_owned_host_scopes(configs + [config])\n\n        _require_owned_provider_url(config, config.base_url, label="baseUrl")\n''',
        label="pre-URL host validation",
    )
    build.write_text(build_text, encoding="utf-8")

    test_text = tests.read_text(encoding="utf-8")
    anchor = '''    def test_owned_hosts_are_required(self):\n        raw = provider_config(owned_hosts=[])\n        with self.assertRaisesRegex(\n            SystemExit,\n            "Provider animefire must declare ownedHosts",\n        ):\n            provider_cache._parse_provider_configs(\n                {"schemaVersion": 1, "providers": [raw]}\n            )\n\n'''
    addition = anchor + '''    def test_owned_hosts_reject_unsafe_or_overbroad_values(self):\n        invalid_hosts = (\n            "com",\n            "*.animefire.example",\n            "animefire.example:443",\n            "https://animefire.example",\n            "user@animefire.example",\n            "localhost",\n            "animefire.local",\n            "127.0.0.1",\n            "animefire.example.",\n        )\n        for owned_host in invalid_hosts:\n            raw = provider_config(owned_hosts=[owned_host])\n            with self.subTest(owned_host=owned_host):\n                with self.assertRaisesRegex(SystemExit, "invalid ownedHost"):\n                    provider_cache._parse_provider_configs(\n                        {"schemaVersion": 1, "providers": [raw]}\n                    )\n\n    def test_duplicate_owned_host_is_rejected(self):\n        raw = provider_config(\n            owned_hosts=["animefire.example", "animefire.example"]\n        )\n        with self.assertRaisesRegex(SystemExit, "duplicate ownedHost"):\n            provider_cache._parse_provider_configs(\n                {"schemaVersion": 1, "providers": [raw]}\n            )\n\n    def test_same_provider_may_own_parent_and_subdomain(self):\n        raw = provider_config(\n            owned_hosts=["animefire.example", "www.animefire.example"]\n        )\n        configs = provider_cache._parse_provider_configs(\n            {"schemaVersion": 1, "providers": [raw]}\n        )\n        self.assertEqual(len(configs), 1)\n\n    def test_owned_host_overlap_across_providers_is_rejected(self):\n        first = provider_config()\n        second = {\n            "id": "mirror",\n            "baseUrl": "https://cdn.animefire.example",\n            "ownedHosts": ["cdn.animefire.example"],\n            "strategy": "animefire",\n            "roots": ["https://cdn.animefire.example/catalog"],\n            "catalogSelectors": ["article"],\n            "paginationSelectors": [".pagination a[href]"],\n        }\n        with self.assertRaisesRegex(SystemExit, "ownedHost scopes overlap"):\n            provider_cache._parse_provider_configs(\n                {"schemaVersion": 1, "providers": [first, second]}\n            )\n\n'''
    test_text = replace_once(
        test_text,
        anchor,
        addition,
        label="owned-host tests",
    )
    tests.write_text(test_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
