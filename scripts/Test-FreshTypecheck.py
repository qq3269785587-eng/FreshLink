"""Run complete vue-tsc and compare every diagnostic with a captured baseline.
No dependencies are installed. All output stays under FreshLink work/.
"""
import argparse, collections, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(r'^(.+?)\((\d+),(\d+)\): error (TS\d+): (.*)$', re.M)
def diagnostics(text):
    return [dict(file=m[0].replace('\\', '/'), line=int(m[1]), column=int(m[2]), code=m[3], message=m[4]) for m in PATTERN.findall(text)]
def main():
    p = argparse.ArgumentParser()
    p.add_argument('--evidence', required=True, type=Path)
    p.add_argument('--reference', required=True, type=Path, help='A previous raw vue-tsc log')
    p.add_argument('--existing-log', type=Path, help='Compare an already executed full check without re-running it')
    a=p.parse_args(); out=a.evidence.resolve(); out.relative_to(ROOT/'work'); out.mkdir(parents=True, exist_ok=True)
    if a.existing_log:
        log=a.existing_log; code=None
    else:
        log=out/'typecheck.log'
        if log.exists(): raise RuntimeError('Use a fresh evidence directory')
        with log.open('w',encoding='utf-8') as stream:
            process=subprocess.run(['node','--max-old-space-size=8192','--stack_size=8192','node_modules/vue-tsc/bin/vue-tsc.js','--noEmit','--pretty','false'],cwd=ROOT/'apps/web',stdout=stream,stderr=subprocess.STDOUT,timeout=900)
        code=process.returncode
    before=diagnostics(a.reference.read_text(encoding='utf-8-sig')); after=diagnostics(log.read_text(encoding='utf-8-sig'))
    if not after: raise RuntimeError('No diagnostics: verify successful checker exit before accepting an empty baseline')
    keyed=lambda rows: {json.dumps(row,sort_keys=True,ensure_ascii=False) for row in rows}
    result=dict(reference=str(a.reference),log=str(log),checkerExitCode=code,before=len(before),after=len(after),byCode=dict(collections.Counter(r['code'] for r in after)),added=[json.loads(r) for r in sorted(keyed(after)-keyed(before))],removed=[json.loads(r) for r in sorted(keyed(before)-keyed(after))])
    (out/'comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(before=len(before),after=len(after),added=len(result['added']),removed=len(result['removed']),checkerExitCode=code)))
    return 1 if result['added'] else 0
if __name__=='__main__': raise SystemExit(main())
