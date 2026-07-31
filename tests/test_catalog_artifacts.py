from __future__ import annotations
import datetime as dt, unittest
import scripts.catalog_artifacts as catalog
from scripts.catalog_artifacts import candidate_manifests, render_catalog, select_cleanup, verify_reusable
from tests.test_artifact_contract import valid_manifest

def artifact(id,name,run,created='2026-07-31T10:00:00Z',expired=False,size=100):
 return {'id':id,'name':name,'expired':expired,'created_at':created,'expires_at':'2026-08-01T10:00:00Z','size_in_bytes':size,'workflow_run':{'id':run}}

class CatalogTests(unittest.TestCase):
 def test_finds_and_verifies_complete_reusable_set(self):
  m=valid_manifest(); m['run_id']=10; m['set_fingerprint']='a'*64; m['artifact_set_id']='goanime-analysis-'+'a'*16+'-10'; m['parts'][0]['artifact_name']=m['artifact_set_id']+'-part-00'
  artifacts=[artifact(1,m['artifact_set_id']+'-manifest',10),artifact(2,m['parts'][0]['artifact_name'],10)]
  self.assertEqual(candidate_manifests(artifacts,'goanime-analysis','a'*64)[0]['id'],1)
  self.assertEqual(verify_reusable(m,artifacts)['artifact_ids'],[1,2])
  self.assertIsNone(verify_reusable(m,artifacts[:1]))
 def test_cleanup_preserves_current_source_and_different_fingerprint(self):
  current=valid_manifest(); current['run_id']=20; current['set_fingerprint']='b'*64; current['artifact_set_id']='goanime-analysis-'+'b'*16+'-20'; current['parts'][0]['artifact_name']=current['artifact_set_id']+'-part-00'
  old_prefix='goanime-analysis-'+'b'*16+'-19'
  other='goanime-analysis-'+'c'*16+'-18'
  artifacts=[artifact(1,current['artifact_set_id']+'-manifest',20),artifact(2,current['parts'][0]['artifact_name'],20),artifact(3,old_prefix+'-manifest',19),artifact(4,old_prefix+'-part-00',19),artifact(5,other+'-manifest',18),artifact(6,other+'-part-00',18),artifact(7,'private-source-goanime-full-manifest',17)]
  deleted=select_cleanup(artifacts,[current],dt.datetime(2026,7,31,20,tzinfo=dt.timezone.utc))
  self.assertEqual([a['id'] for a in deleted],[3,4])
 def test_cleanup_removes_old_incomplete_group_only_after_six_hours(self):
  orphan='jdk21-'+'d'*16+'-2'
  artifacts=[artifact(8,orphan+'-manifest',2,created='2026-07-31T10:00:00Z')]
  early=select_cleanup(artifacts,[],dt.datetime(2026,7,31,15,tzinfo=dt.timezone.utc))
  late=select_cleanup(artifacts,[],dt.datetime(2026,7,31,16,tzinfo=dt.timezone.utc))
  self.assertEqual(early,[]); self.assertEqual([a['id'] for a in late],[8])
 def test_catalog_contains_connector_ids(self):
  m=valid_manifest(); text=render_catalog(m['profile'],{'id':1,'html_url':'x','conclusion':'success'},[artifact(9,'x',1)],[m],None,[])
  self.assertIn('ID `9`',text); self.assertIn('toolchain-profile:goanime-analysis',text)
if __name__=='__main__': unittest.main()

class ReportPlanTests(unittest.TestCase):
    def test_report_plan_uses_receipt_and_selects_old_equivalent(self):
        manifest={"profile":"jdk21","artifact_set_id":"jdk21-aaaaaaaaaaaaaaaa-2","set_fingerprint":"a"*64,"run_id":2,"lock_mode":"not-applicable","lock_fingerprint":"0"*64,"parts":[{"artifact_name":"jdk21-aaaaaaaaaaaaaaaa-2-part-00"}]}
        artifacts=[
            artifact(1,"jdk21-aaaaaaaaaaaaaaaa-1-manifest",1,created="2026-07-31T00:00:00Z"),
            artifact(2,"jdk21-aaaaaaaaaaaaaaaa-1-part-00",1,created="2026-07-31T00:00:00Z"),
            artifact(3,"jdk21-aaaaaaaaaaaaaaaa-2-manifest",2,created="2026-07-31T01:00:00Z"),
            artifact(4,"jdk21-aaaaaaaaaaaaaaaa-2-part-00",2,created="2026-07-31T01:00:00Z"),
        ]
        plan=catalog.build_report_plan({"id":2,"html_url":"x","conclusion":"success"},artifacts,[{"result":"built","manifest":manifest}],catalog.parse_time("2026-07-31T02:00:00Z"))
        self.assertEqual(plan["delete_artifact_ids"],[1,2])
        self.assertIn("ID `3`",plan["comments"][0]["body"])
