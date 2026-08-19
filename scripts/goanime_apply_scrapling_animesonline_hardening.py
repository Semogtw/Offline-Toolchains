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

    crawler_text = crawler.read_text(encoding="utf-8")
    crawler_text = replace_once(
        crawler_text,
        "ANIMEFIRE_MIN_TOTAL_PAGE_BUDGET = 4096\nGOYABU_MAX_PAGES = 512\n",
        "ANIMEFIRE_MIN_TOTAL_PAGE_BUDGET = 4096\nANIMESONLINE_MAX_SITEMAPS = 512\nGOYABU_MAX_PAGES = 512\n",
        label="crawler limits",
    )
    old = '''    sitemap_urls = [\n        url\n        for url in xml_locs(response_text(index))\n        if provider.owns(url)\n        and (\n            "episodes-sitemap" in urlparse(url).path.lower()\n            or "tvshows-sitemap" in urlparse(url).path.lower()\n        )\n    ]\n    if not sitemap_urls:\n        return ProviderCrawl(\n            provider.id,\n            False,\n            {},\n            "sitemap index exposed no episode/tvshow maps",\n            attempted,\n            successful,\n            [],\n        )\n\n'''
    new = '''    sitemap_urls = list(\n        dict.fromkeys(\n            url\n            for url in xml_locs(response_text(index))\n            if provider.owns(url)\n            and (\n                "episodes-sitemap" in urlparse(url).path.lower()\n                or "tvshows-sitemap" in urlparse(url).path.lower()\n            )\n        )\n    )\n    if not sitemap_urls:\n        return ProviderCrawl(\n            provider.id,\n            False,\n            {},\n            "sitemap index exposed no episode/tvshow maps",\n            attempted,\n            successful,\n            [],\n        )\n\n    episode_sitemaps = [\n        url for url in sitemap_urls if "episodes-sitemap" in urlparse(url).path.lower()\n    ]\n    tvshow_sitemaps = [\n        url for url in sitemap_urls if "tvshows-sitemap" in urlparse(url).path.lower()\n    ]\n    if not episode_sitemaps or not tvshow_sitemaps:\n        return ProviderCrawl(\n            provider.id,\n            False,\n            {},\n            (\n                "sitemap index missing required families: "\n                f"episodes={len(episode_sitemaps)}, tvshows={len(tvshow_sitemaps)}"\n            ),\n            attempted,\n            successful,\n            [],\n        )\n    if len(sitemap_urls) > ANIMESONLINE_MAX_SITEMAPS:\n        return ProviderCrawl(\n            provider.id,\n            False,\n            {},\n            (\n                "sitemap index exceeds child-map budget: "\n                f"{len(sitemap_urls)} > {ANIMESONLINE_MAX_SITEMAPS}"\n            ),\n            attempted,\n            successful,\n            [],\n        )\n\n'''
    crawler_text = replace_once(crawler_text, old, new, label="AnimesOnline sitemap index")
    old_goyabu = '''def _goyabu_pagination(page: object, root: str) -> tuple[int, str]:\n    """Return last page and the URL style exposed by the current Goyabu HTML."""\n    last_page = 1\n    style = "paged"\n    style_priority = 0\n    root_path = urlparse(root).path.rstrip("/")\n    try:\n        nodes = list(page.css("a[href]"))\n    except Exception:\n        nodes = []\n    for node in nodes:\n        href = anchor_href(node, root)\n        parsed = urlparse(href)\n        path = parsed.path.rstrip("/")\n'''
    new_goyabu = '''def _goyabu_pagination(page: object, root: str) -> tuple[int, str]:\n    """Return last page and the URL style exposed by the current Goyabu HTML."""\n    last_page = 1\n    style = "paged"\n    style_priority = 0\n    root_parsed = urlparse(root)\n    root_scheme = root_parsed.scheme.lower()\n    root_host = (root_parsed.hostname or "").lower()\n    root_port = root_parsed.port or (443 if root_scheme == "https" else 80)\n    root_path = root_parsed.path.rstrip("/")\n    try:\n        nodes = list(page.css("a[href]"))\n    except Exception:\n        nodes = []\n    for node in nodes:\n        href = anchor_href(node, root)\n        try:\n            parsed = urlparse(href)\n            candidate_scheme = parsed.scheme.lower()\n            candidate_host = (parsed.hostname or "").lower()\n            candidate_port = parsed.port or (443 if candidate_scheme == "https" else 80)\n        except ValueError:\n            continue\n        if (candidate_scheme, candidate_host, candidate_port) != (\n            root_scheme,\n            root_host,\n            root_port,\n        ):\n            continue\n        path = parsed.path.rstrip("/")\n'''
    crawler_text = replace_once(crawler_text, old_goyabu, new_goyabu, label="Goyabu pagination origin")
    crawler.write_text(crawler_text, encoding="utf-8")

    test_text = tests.read_text(encoding="utf-8")
    test_text = replace_once(
        test_text,
        "    ANIMEFIRE_MIN_TOTAL_PAGE_BUDGET,\n",
        "    ANIMEFIRE_MIN_TOTAL_PAGE_BUDGET,\n    ANIMESONLINE_MAX_SITEMAPS,\n",
        label="test imports",
    )
    test_text = replace_once(
        test_text,
        "    crawl_animefire,\n    crawl_animesonline,\n",
        "    crawl_animefire,\n    crawl_animesonline,\n    _goyabu_pagination,\n",
        label="Goyabu test import",
    )
    anchor = '''    def test_all_known_sitemaps_are_required_for_complete(self) -> None:\n'''
    addition = '''    def test_both_sitemap_families_are_required_before_child_fetch(self) -> None:\n        episodes_only = TextPage(\n            "<sitemapindex>"\n            f"<sitemap><loc>{self.episodes_url}</loc></sitemap>"\n            "</sitemapindex>"\n        )\n        result = crawl_animesonline(\n            self.provider,\n            SitemapFetcher(\n                self.index_url,\n                episodes_only,\n                {self.episodes_url: self.episodes},\n            ),\n            workers=4,\n        )\n        self.assertFalse(result.complete)\n        self.assertEqual(result.attempted_urls, 1)\n        self.assertEqual(result.successful_urls, 1)\n        self.assertEqual(result.entries, {})\n        self.assertIn("missing required families", result.detail)\n\n    def test_duplicate_child_sitemaps_are_deduplicated(self) -> None:\n        duplicate_index = TextPage(\n            "<sitemapindex>"\n            f"<sitemap><loc>{self.episodes_url}</loc></sitemap>"\n            f"<sitemap><loc>{self.episodes_url}</loc></sitemap>"\n            f"<sitemap><loc>{self.tvshows_url}</loc></sitemap>"\n            f"<sitemap><loc>{self.tvshows_url}</loc></sitemap>"\n            "</sitemapindex>"\n        )\n        result = crawl_animesonline(\n            self.provider,\n            SitemapFetcher(\n                self.index_url,\n                duplicate_index,\n                {\n                    self.episodes_url: self.episodes,\n                    self.tvshows_url: self.tvshows,\n                },\n            ),\n            workers=4,\n        )\n        self.assertTrue(result.complete)\n        self.assertEqual(result.attempted_urls, 3)\n        self.assertEqual(result.successful_urls, 3)\n\n    def test_child_sitemap_budget_fails_before_fanout(self) -> None:\n        host = "animesonline.example"\n        episode_urls = [\n            f"https://{host}/episodes-sitemap{index}.xml"\n            for index in range(ANIMESONLINE_MAX_SITEMAPS)\n        ]\n        oversized_index = TextPage(\n            "<sitemapindex>"\n            + "".join(\n                f"<sitemap><loc>{url}</loc></sitemap>" for url in episode_urls\n            )\n            + f"<sitemap><loc>{self.tvshows_url}</loc></sitemap>"\n            + "</sitemapindex>"\n        )\n        result = crawl_animesonline(\n            self.provider,\n            SitemapFetcher(self.index_url, oversized_index, {}),\n            workers=4,\n        )\n        self.assertFalse(result.complete)\n        self.assertEqual(result.attempted_urls, 1)\n        self.assertEqual(result.successful_urls, 1)\n        self.assertIn("exceeds child-map budget", result.detail)\n\n''' + anchor
    test_text = replace_once(test_text, anchor, addition, label="AnimesOnline tests")
    footer = '''\n\nif __name__ == "__main__":\n    unittest.main()\n'''
    goyabu_tests = '''\n\nclass GoyabuPaginationOriginTests(unittest.TestCase):\n    def test_external_pagination_links_do_not_inflate_last_page(self) -> None:\n        root = "https://goyabu.example/lista-de-animes"\n        page = MappedPage(\n            {\n                "a[href]": [\n                    FakeNode(\n                        "999 external",\n                        "https://evil.example/lista-de-animes/page/999",\n                    ),\n                    FakeNode(\n                        "999 external query",\n                        "https://evil.example/lista-de-animes?paged=999",\n                    ),\n                    FakeNode("5", f"{root}/page/5"),\n                ]\n            }\n        )\n\n        self.assertEqual(_goyabu_pagination(page, root), (5, "path"))\n'''
    test_text = replace_once(test_text, footer, goyabu_tests + footer, label="test footer")
    tests.write_text(test_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
