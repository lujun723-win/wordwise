"""Compare every index row with a saved baseline; no spelling or grade inference."""
import collections,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
old={r['word']:r for r in json.loads(Path(sys.argv[1]).read_text())}
new=json.loads((root/'wordwise.koplugin/data/level-audit.json').read_text())
assert len(new)==len(old)==len({r['word'] for r in new})==30000
assert {r['word'] for r in new}==set(old)
changes=[{'word':r['word'],'before':old[r['word']]['level'],'after':r['level'],'origin':r['origin']} for r in new if old[r['word']]['level']!=r['level']]
report={'baseline':sys.argv[2] if len(sys.argv)>2 else '0.4.1-preview','version':json.loads((root/'wordwise.koplugin/manifest.json').read_text())['version'],'checked':len(new),'changed':len(changes),
    'multi_stage_memberships':sum(r['multiple_stage_memberships'] for r in new),
    'uncovered_policy_words':sum(r['origin']=='extension-policy' for r in new),
    'groups':dict(collections.Counter(r['level'] for r in new)),'changes':changes}
(root/'wordwise.koplugin/data/level-comparison-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print({k:v for k,v in report.items() if k!='changes'})
