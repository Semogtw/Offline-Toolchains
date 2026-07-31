#!/usr/bin/env python3
"""Normalize a public software inventory without leaking credentials or private URLs."""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path
TOKENISH = re.compile(
    r"(?i)(token|password|secret|authorization|github" r"_pat_|gh" r"p_)"
)

def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument('input', type=Path); parser.add_argument('output', type=Path); args=parser.parse_args()
    try:
        data=json.loads(args.input.read_text(encoding='utf-8'))
        if not isinstance(data,list): raise ValueError('inventory must be a list')
        normalized=[]
        for item in data:
            if not isinstance(item,dict): raise ValueError('inventory entries must be objects')
            rendered=json.dumps(item, sort_keys=True)
            if TOKENISH.search(rendered): raise ValueError('credential-like inventory content rejected')
            source=str(item.get('source','NOASSERTION'))
            if source != 'NOASSERTION' and not source.startswith(('https://pub.dev','https://repo.maven.apache.org','https://crates.io','registry+https://github.com/rust-lang/crates.io-index','https://adoptium.net')):
                source='NOASSERTION'
            normalized.append({'name':str(item.get('name','unknown')),'version':str(item.get('version','unknown')),'source':source,'license':str(item.get('license','NOASSERTION')),'evidence':str(item.get('evidence',''))})
        args.output.write_text(json.dumps(sorted(normalized,key=lambda x:(x['name'],x['version'])),indent=2,sort_keys=True)+'\n',encoding='utf-8')
    except (OSError,ValueError,json.JSONDecodeError) as error:
        print(f'inventory normalization failed: {error}',file=sys.stderr); return 2
    return 0
if __name__=='__main__': raise SystemExit(main())
