#!/usr/bin/env python3
"""빈 회고 상태와 같은 설정으로 두 호스트의 실제 SessionStart 추가 지시를 합산한다."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def measure(plugin, project, runtime):
    registry = 'hooks.json' if runtime == 'Claude' else 'codex.json'
    groups = json.loads((plugin / 'hooks' / registry).read_text())['hooks']['SessionStart']
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(project), CLAUDE_PLUGIN_ROOT=str(plugin),
               PLUGIN_ROOT=str(plugin), TMPDIR=str(project), HARNESS_RUNTIME=runtime.lower())
    payload = dict(session_id='measure', hook_event_name='SessionStart', source='startup',
                   cwd=str(project), transcript_path=str(project / 'sessions/measure.jsonl'))
    total = stable = 0
    for group in groups:
        if not re.fullmatch(group.get('matcher', '.*'), payload['source']):
            continue
        for hook in group['hooks']:
            result = subprocess.run(['/bin/sh', '-c', hook['command']], input=json.dumps(payload),
                                    cwd=project, env=env, capture_output=True, text=True, check=True, timeout=30)
            output = json.loads(result.stdout) if result.stdout.strip() else {}
            if output.get('systemMessage'):
                raise ValueError(output['systemMessage'])
            context = output.get('hookSpecificOutput', {}).get('additionalContext', '')
            total += len(context.encode())
            stable += len(context.replace(str(plugin), '/plugin').encode())
    if not total:
        raise ValueError(runtime + ' 시작 규칙을 읽지 못했습니다')
    return total, stable


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugin', type=Path, default=root / 'plugin')
    parser.add_argument('--check', action='store_true', help='설치 경로 길이를 통일한 바이트 상한 검사')
    args = parser.parse_args()
    exceeded = False
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp).resolve()
        subprocess.run(['git', 'init', '-q', str(project)], check=True)
        (project / '.claude').mkdir()
        (project / 'sessions').mkdir()
        shutil.copyfile(root / '.claude/harness.conf', project / '.claude/harness.conf')
        for runtime, limit in [('Claude', 16000), ('Codex', 20000)]:
            total, stable = measure(args.plugin.resolve(), project, runtime)
            print(f'{runtime} 시작 훅 {total} B · 설치 경로 정규화 {stable} B / 상한 {limit} B')
            exceeded |= stable > limit
    raise SystemExit(int(args.check and exceeded))
