"""Synthetic policy regression tests for the reviewed personal MangaBaka SQL."""
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'scripts' / 'validate_goanime_similar_sql_asset.py'
spec = importlib.util.spec_from_file_location('verify', MODULE)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class AssetValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.catalog = self.root / 'catalog.db'
        self.version = self.root / 'catalog.version'
        self.index = self.root / 'index.db'
        self.legacy = self.root / 'legacy.db'
        with sqlite3.connect(self.catalog) as db:
            db.executescript('''
            CREATE TABLE works(workId TEXT PRIMARY KEY, hasAdultContent INTEGER);
            CREATE TABLE source_links(workId TEXT, availabilityState TEXT);
            INSERT INTO works VALUES('a',0),('b',0),('adult',1);
            INSERT INTO source_links VALUES('a','listed'),('b','listed'),('adult','listed');
            ''')
        self.digest = verify.sha256(self.catalog)
        self.version.write_text(self.digest)
        with sqlite3.connect(self.index) as db:
            db.executescript('''
            CREATE TABLE index_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE manga_similar_ids(id INTEGER PRIMARY KEY, workId TEXT UNIQUE);
            CREATE TABLE manga_similar_works(
                sourceId INTEGER NOT NULL REFERENCES manga_similar_ids(id),
                targetId INTEGER NOT NULL REFERENCES manga_similar_ids(id),
                rankPosition INTEGER NOT NULL,
                score REAL NOT NULL,
                PRIMARY KEY(sourceId,rankPosition),
                UNIQUE(sourceId,targetId)
            );
            INSERT INTO manga_similar_ids VALUES(1,'a'),(2,'b'),(3,'adult');
            INSERT INTO manga_similar_works VALUES(1,2,1,0.8);
            ''')
            db.executemany('INSERT INTO index_metadata VALUES(?,?)', [
                ('schemaVersion','1'),('catalogSha256',self.digest),
                ('rankingPolicy',verify.AUTHORITY_POLICY),
                ('edgeCount','1'),('sourceCount','1'),
                ('mangabakaEdgeCount','1'),('fallbackEdgeCount','0'),
                ('mangabakaSourceRoots','1'),('mangabakaConflictedExternalIds','0'),
            ])
        self.stats = dict(edgeCount=1,sourceCount=1,mangabakaEdgeCount=1,
                          fallbackEdgeCount=0,mangabakaSourceRoots=1,
                          mangabakaConflictedExternalIds=0)

    def check(self, **kwargs):
        return verify.validate_asset(
            catalog=self.catalog,version=self.version,
            asset=self.index,legacy_rebuilt=self.legacy,
            expected_authority_sha=kwargs.pop('expected_authority_sha',verify.sha256(self.index)),
            expected_stats=self.stats,**kwargs)

    def test_valid_top_ten_with_no_catalog_scan_in_reader(self):
        self.assertEqual(self.check()['mode'], 'mangabaka_top10')

    def test_legacy_requires_byte_identical_output(self):
        with sqlite3.connect(self.index) as db:
            db.execute("DELETE FROM index_metadata WHERE key='rankingPolicy'")
        self.legacy.write_bytes(self.index.read_bytes())
        self.assertEqual(self.check()['mode'], 'legacy_octen')
        self.legacy.write_bytes(b'different old graph')
        with self.assertRaisesRegex(ValueError,'Legacy shipped SQL differs'):
            self.check()

    def test_sha_pin_is_mandatory(self):
        with self.assertRaisesRegex(ValueError,'hash-pinned artifact'):
            self.check(expected_authority_sha='0'*64)

    def test_adult_candidate_fails_closed(self):
        with sqlite3.connect(self.index) as db:
            db.execute("UPDATE manga_similar_works SET targetId=3")
        with self.assertRaisesRegex(ValueError,'ineligible'):
            self.check()

    def test_noncontiguous_ranks_fail(self):
        with sqlite3.connect(self.index) as db:
            db.execute('UPDATE manga_similar_works SET rankPosition=2')
        with self.assertRaisesRegex(ValueError,'Non-contiguous'):
            self.check()

    def test_wrong_catalog_version_fails(self):
        self.version.write_text('b'*64)
        with self.assertRaisesRegex(ValueError,'Catalog SHA'):
            self.check()

    def test_bad_score_fails(self):
        with sqlite3.connect(self.index) as db:
            db.execute('UPDATE manga_similar_works SET score=0')
        with self.assertRaisesRegex(ValueError,'invalid scores'):
            self.check()


if __name__=='__main__':
    unittest.main()