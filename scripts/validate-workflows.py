#!/usr/bin/env python3
"""Static workflow contract checks that require no private credentials."""
from __future__ import annotations
import argparse, re, subprocess, sys
from pathlib import Path

EXPECTED = {
    'build-android-base.yml': 'Build Android base',
    'build-jdk21.yml': 'Build portable JDK 21',
    'build-goanime.yml': 'Build GoAnime toolchain',
    'build-zapzap.yml': 'Build ZapZap toolchain',
    'build-exact-toolchain.yml': 'Build exact private-lock toolchain',
    'request-toolchain-build.yml': 'Request exact toolchain build',
    'report-toolchain-runs.yml': 'Report toolchain runs',
}
PUBLIC = {'build-android-base.yml','build-jdk21.yml','build-goanime.yml','build-zapzap.yml'}

def require(text: str, needle: str, file: Path, errors: list[str]) -> None:
    if needle not in text:
        errors.append(f'{file}: missing {needle!r}')

def validate(root: Path) -> list[str]:
    errors=[]
    for name, workflow_name in EXPECTED.items():
        path=root/name
        if not path.is_file():
            errors.append(f'missing workflow {path}')
            continue
        text=path.read_text(encoding='utf-8')
        require(text,f'name: {workflow_name}',path,errors)
        for match in re.finditer(r'retention-days:\s*(\d+)',text):
            if int(match.group(1)) > 1:
                errors.append(f'{path}: retention exceeds one day')
        if name in PUBLIC:
            for needle in ('scripts/find-reusable-set.sh','scripts/build_artifact_set.py','toolchain-receipt-','artifact-set.json','SBOM.spdx.json','retention-days: 1'):
                require(text,needle,path,errors)
            if 'secrets.' in text or 'PRIVATE_REPOSITORIES_TOKEN' in text:
                errors.append(f'{path}: public builder must not use private secrets')
        if name == 'request-toolchain-build.yml':
            require(text,'build/toolchains',path,errors)
            require(text,'validate-toolchain-request.py',path,errors)
            if 'secrets.' in text or 'PRIVATE_REPOSITORIES_TOKEN' in text:
                errors.append(f'{path}: request workflow must not receive secrets')
        if name == 'build-exact-toolchain.yml':
            for needle in (
                "github.event.workflow_run.head_branch == 'build/toolchains'",
                'github.event.workflow_run.actor.login == github.repository_owner',
                'PRIVATE_REPOSITORIES_TOKEN',
                "'goanime':'Semogtw/goanime-mobile'",
                "'zapzap':'Semogtw/Zapzap'",
                'fetch-depth: 0','persist-credentials: false','lfs: false','submodules: false',
                'flutter pub get --offline --enforce-lockfile','./gradlew --no-daemon --offline',
                'rm -rf private-source request-source','Upload part 15','retention-days: 1',
            ):
                require(text,needle,path,errors)
        if name == 'report-toolchain-runs.yml':
            for needle in ('actions: write','issues: write','issueNumber = 8','deleteArtifact','report-plan'):
                require(text,needle,path,errors)
    for path in root.glob('*.yml'):
        text=path.read_text(encoding='utf-8')
        for match in re.finditer(r'split\s+(?:--bytes=|-b\s*)(\d+)([MG])',text):
            value=int(match.group(1))*(1024 if match.group(2)=='G' else 1)
            if value>400:
                errors.append(f'{path}: split part exceeds 400 MiB')
    ruby=subprocess.run(['ruby','-e','require "yaml"; ARGV.each { |f| YAML.load_file(f, aliases: true) }',*[str(path) for path in root.glob('*.yml')]],text=True,capture_output=True)
    if ruby.returncode:
        errors.append('YAML parse failed: '+ruby.stderr.strip())
    return errors

def main()->int:
    parser=argparse.ArgumentParser(); parser.add_argument('root',nargs='?',type=Path,default=Path('.github/workflows')); args=parser.parse_args()
    errors=validate(args.root)
    if errors:
        print('\n'.join(errors),file=sys.stderr); return 2
    print('Workflow contract validation passed.'); return 0
if __name__=='__main__': raise SystemExit(main())
