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
    crawler = repo / "tools/scrapling_provider_pipeline/provider_crawlers.py"
    tests = repo / "tools/scrapling_provider_pipeline/tests/test_provider_crawlers.py"

    text = crawler.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import re\nfrom collections import deque\n",
        "import re\nimport xml.etree.ElementTree as ET\nfrom collections import deque\n",
        label="XML import",
    )
    text = replace_once(
        text,
        "\ndef _is_pagination_url(url: str) -> bool:\n",
        '''\ndef _validated_xml_locs(content: str) -> tuple[list[str], bool]:\n    """Return sitemap locs plus whether the XML parsed structurally.\n\n    Regex recovery remains available for diagnostics/partial evidence, but\n    callers must not use recovered locs as proof that a sitemap crawl is\n    complete.\n    """\n    try:\n        root = ET.fromstring(content)\n    except ET.ParseError:\n        return xml_locs(content), False\n    return (\n        [\n            node.text.strip()\n            for node in root.iter()\n            if node.tag.rsplit("}", 1)[-1].lower() == "loc"\n            and node.text\n            and node.text.strip()\n        ],\n        True,\n    )\n\n\ndef _is_pagination_url(url: str) -> bool:\n''',
        label="validated XML helper",
    )
    old_animefire = '''                locations = [\n                    loc for loc in xml_locs(response_text(page)) if provider.owns(loc)\n                ]\n                entries = parse_animefire_sitemap_locations(locations)\n                if entries:\n                    return ProviderCrawl(\n                        provider.id,\n                        True,\n                        entries,\n                        "complete sitemap episode audit",\n                        attempted,\n                        successful,\n                        [],\n                    )\n                series_entries = parse_animefire_series_locations(locations)\n                if series_entries:\n                    sitemap_failure = (\n                        "sitemap exposed series but no numbered episode proof"\n                    )\n                else:\n                    sitemap_failure = "sitemap returned no anime entries"\n'''
    new_animefire = '''                raw_locations, sitemap_xml_valid = _validated_xml_locs(\n                    response_text(page)\n                )\n                locations = [loc for loc in raw_locations if provider.owns(loc)]\n                if not sitemap_xml_valid:\n                    sitemap_failure = "sitemap XML malformed"\n                else:\n                    entries = parse_animefire_sitemap_locations(locations)\n                    if entries:\n                        return ProviderCrawl(\n                            provider.id,\n                            True,\n                            entries,\n                            "complete sitemap episode audit",\n                            attempted,\n                            successful,\n                            [],\n                        )\n                    series_entries = parse_animefire_series_locations(locations)\n                    if series_entries:\n                        sitemap_failure = (\n                            "sitemap exposed series but no numbered episode proof"\n                        )\n                    else:\n                        sitemap_failure = "sitemap returned no anime entries"\n'''
    text = replace_once(text, old_animefire, new_animefire, label="AnimeFire sitemap validity")

    old_index = '''    sitemap_urls = list(\n        dict.fromkeys(\n            url\n            for url in xml_locs(response_text(index))\n            if provider.owns(url)\n'''
    new_index = '''    index_locations, index_xml_valid = _validated_xml_locs(response_text(index))\n    if not index_xml_valid:\n        return ProviderCrawl(\n            provider.id,\n            False,\n            {},\n            "sitemap index XML malformed",\n            attempted,\n            successful,\n            [],\n        )\n\n    sitemap_urls = list(\n        dict.fromkeys(\n            url\n            for url in index_locations\n            if provider.owns(url)\n'''
    text = replace_once(text, old_index, new_index, label="AnimesOnline index validity")

    old_child = '''        locations = [\n            loc for loc in xml_locs(response_text(page)) if provider.owns(loc)\n        ]\n        path = urlparse(sitemap).path.lower()\n        sitemap_entries: dict[str, CatalogEntry] = {}\n        if "episodes-sitemap" in path:\n            sitemap_entries = parse_animesonline_episode_locations(locations)\n        elif "tvshows-sitemap" in path:\n            sitemap_entries = parse_animesonline_tvshow_locations(locations)\n        if sitemap_entries:\n            parsed_sitemaps += 1\n            merge_catalogs(entries, sitemap_entries)\n'''
    new_child = '''        raw_locations, sitemap_xml_valid = _validated_xml_locs(response_text(page))\n        locations = [loc for loc in raw_locations if provider.owns(loc)]\n        if not sitemap_xml_valid:\n            failures += 1\n        path = urlparse(sitemap).path.lower()\n        sitemap_entries: dict[str, CatalogEntry] = {}\n        if "episodes-sitemap" in path:\n            sitemap_entries = parse_animesonline_episode_locations(locations)\n        elif "tvshows-sitemap" in path:\n            sitemap_entries = parse_animesonline_tvshow_locations(locations)\n        if sitemap_entries:\n            if sitemap_xml_valid:\n                parsed_sitemaps += 1\n            merge_catalogs(entries, sitemap_entries)\n'''
    text = replace_once(text, old_child, new_child, label="AnimesOnline child validity")
    crawler.write_text(text, encoding="utf-8")

    test_text = tests.read_text(encoding="utf-8")
    anchor = '''    def test_all_known_sitemaps_are_required_for_complete(self) -> None:\n'''
    addition = '''    def test_malformed_index_never_fans_out_or_marks_complete(self) -> None:\n        malformed_index = TextPage(\n            "<sitemapindex>"\n            f"<sitemap><loc>{self.episodes_url}</loc></sitemap>"\n            f"<sitemap><loc>{self.tvshows_url}</loc></sitemap>"\n        )\n        result = crawl_animesonline(\n            self.provider,\n            SitemapFetcher(\n                self.index_url,\n                malformed_index,\n                {\n                    self.episodes_url: self.episodes,\n                    self.tvshows_url: self.tvshows,\n                },\n            ),\n            workers=4,\n        )\n        self.assertFalse(result.complete)\n        self.assertEqual(result.attempted_urls, 1)\n        self.assertEqual(result.successful_urls, 1)\n        self.assertEqual(result.entries, {})\n        self.assertIn("index XML malformed", result.detail)\n\n    def test_malformed_child_can_recover_entries_but_never_complete(self) -> None:\n        malformed_episodes = TextPage(\n            "<urlset>"\n            "<url><loc>https://animesonline.example/episodio/anime-one-episodio-01/</loc></url>"\n        )\n        result = crawl_animesonline(\n            self.provider,\n            SitemapFetcher(\n                self.index_url,\n                self.index,\n                {\n                    self.episodes_url: malformed_episodes,\n                    self.tvshows_url: self.tvshows,\n                },\n            ),\n            workers=4,\n        )\n        self.assertFalse(result.complete)\n        self.assertEqual(result.attempted_urls, 3)\n        self.assertEqual(result.successful_urls, 3)\n        self.assertEqual(set(result.entries), {"anime one", "anime two"})\n        self.assertIn("failures=1", result.detail)\n\n''' + anchor
    test_text = replace_once(test_text, anchor, addition, label="AnimesOnline XML tests")

    footer = '''\n\nif __name__ == "__main__":\n    unittest.main()\n'''
    animefire_test = '''\n\nclass AnimeFireXmlIntegrityTests(unittest.TestCase):\n    def test_malformed_sitemap_cannot_prove_complete(self) -> None:\n        host = "animefire.example"\n        sitemap_url = f"https://{host}/sitemap.xml"\n        malformed = TextPage(\n            "<urlset>"\n            f"<url><loc>https://{host}/animes/anime-one/1</loc></url>"\n        )\n        provider = ProviderConfig(\n            id="animefire",\n            base_url=f"https://{host}",\n            owned_hosts=(host,),\n            strategy="animefire",\n            roots=(),\n            sitemap=sitemap_url,\n            catalog_selectors=(),\n            pagination_selectors=(),\n        )\n        result = crawl_animefire(\n            provider,\n            SitemapFetcher(sitemap_url, malformed, {}),\n        )\n        self.assertFalse(result.complete)\n        self.assertEqual(result.entries, {})\n        self.assertIn("sitemap XML malformed", result.detail)\n'''
    test_text = replace_once(test_text, footer, animefire_test + footer, label="test footer")
    tests.write_text(test_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
