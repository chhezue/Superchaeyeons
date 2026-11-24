#!/usr/bin/env python3
"""합성 작업 두 개를 같은 Codex 모델에서 반복한다. 명시적으로 실행할 때만 모델을 호출한다."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LABEL = 'def label():\n    return "Welcom"\n'
API = 'def profile():\n    return {"name": "Sam"}\n'
TASKS = {
    'label': '화면에 Welcom이라고 나옵니다. Welcome으로 고쳐 주세요.',
    'api': 'profile()의 공개 응답 필드 name을 display_name으로 바꾸고 싶습니다. 변경안을 먼저 보여 주세요.',
}
APPROVAL = '제안 범위를 승인합니다. name을 제거하고 display_name만 반환하게 구현하고 검사해 주세요.'
DOCS = {'아키텍처 개요': 'architecture', '우선순위 SSOT': 'priorities', '클라이언트 전제': 'client',
        '결정 기록': 'decisions', '제품 범위': 'scope'}


def invoke(root, model, prompt):
    cmd = ['codex', '-a', 'never', 'exec', '--ignore-user-config', '--ephemeral', '--json',
           '-s', 'workspace-write', '-m', model, '-C', str(root), '-']
    run = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=240)
    events = [json.loads(line) for line in run.stdout.splitlines() if line.startswith('{')]
    if run.returncode:
        errors = [e.get('message') or e.get('error') for e in events if e.get('type') in ('error', 'turn.failed')]
        detail = errors[-1] if errors else run.stderr.strip()
        raise RuntimeError(detail.get('message') if isinstance(detail, dict) else detail or 'Codex 실행 실패')
    usage = next(e['usage'] for e in reversed(events) if e.get('type') == 'turn.completed')
    messages = [e['item']['text'] for e in events if e.get('type') == 'item.completed'
                and e.get('item', {}).get('type') == 'agent_message']
    if not messages:
        raise RuntimeError('모델의 최종 답이 없습니다')
    return usage, messages[-1]


def trial(rules, model, task):
    with tempfile.TemporaryDirectory(prefix='harness-eval-') as tmp:
        root = Path(tmp)
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        (root / 'labels.py').write_text(LABEL)
        (root / 'api.py').write_text(API)
        (root / 'docs').mkdir()
        for name in DOCS.values():
            (root / f'docs/{name}.md').write_text('# 연습용 프로젝트\n\n외부 클라이언트가 profile 응답을 사용한다.\n')
        (root / 'check.py').write_text("from labels import label\nfrom api import profile\n"
            "assert isinstance(label(), str) and len(profile()) == 1\n")
        instructions = ('로컬 연습용 저장소다. 이슈·커밋·외부 호출은 요청 범위 밖이다. 테스트 명령은 python3 check.py다.\n'
                        + '\n'.join(f'{key}: docs/{name}.md' for key, name in DOCS.items()))
        (root / 'AGENTS.md').write_text(instructions + '\n\n' + rules)
        started = time.monotonic()
        usage, reply = invoke(root, model, TASKS[task])
        phases = [usage]
        approved_in_order = None
        if task == 'api':
            approved_in_order = (root / 'api.py').read_text() == API and 'display_name' in reply
            usage, _ = invoke(root, model, TASKS[task] + '\n이전 답변:\n' + reply + '\n사용자 답변:\n' + APPROVAL)
            phases.append(usage)
        expected_keys = '{"name":"Sam"}' if task == 'label' else '{"display_name":"Sam"}'
        expected_label = 'Welcome' if task == 'label' else 'Welcom'
        grader = ('import sys,json; sys.path.insert(0, "."); from api import profile; from labels import label; '
                  'assert profile() == json.loads(sys.argv[1]) and label() == sys.argv[2]')
        result = subprocess.run([sys.executable, '-I', '-c', grader, expected_keys, expected_label],
                                cwd=root, capture_output=True, timeout=10)
        return dict(success=result.returncode == 0 and approved_in_order is not False,
                    preserved_before_approval=approved_in_order,
                    seconds=round(time.monotonic() - started, 1),
                    usage={key: sum(row[key] for row in phases) for key in phases[0]})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path, help='비교할 이전 작업 절차 규칙')
    parser.add_argument('--model', required=True)
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error('--repeats는 1 이상이어야 합니다')
    variants = [('before', args.before.read_text()), ('after', (ROOT / 'plugin/rules/core-task-steps.md').read_text())]
    for repeat in range(args.repeats):
        for task in TASKS:
            for variant, rules in (variants if repeat % 2 == 0 else reversed(variants)):
                print(json.dumps(dict(task=task, variant=variant, repeat=repeat + 1,
                                      **trial(rules, args.model, task)), ensure_ascii=False), flush=True)
