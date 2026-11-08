#!/usr/bin/env bash
# Codex 등록 검사 계약 테스트 — 임시 플러그인만 검사하고 Claude 등록은 바꾸지 않는다.
# 사용: scripts/test-codex-plugin.sh
# exit 0 = 전부 통과 · exit 1 = 실패 · exit 2 = 환경 오류
# 근거: codex-harness-delivery 스펙 M3, check-plugin.sh --codex <plugin-root> 계약.
set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'FAIL: python3 없음' >&2; exit 2; }
python3 -I - "$repo_root" <<'PY'
import copy
import json
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(sys.argv[1])
CHECKER = REPO / 'scripts/check-plugin.sh'
SKILLS = ('init-harness', 'ask-decisions', 'write-spec', 'test-first',
          'refactor-safely', 'fix-bug', 'verify-work', 'improve-harness')
CLAUDE_PATHS = ('.claude-plugin/plugin.json', 'hooks/hooks.json')
passed = failed = 0


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding='utf-8')


def fixture(base):
    root = base / 'plugin with spaces'
    manifest = {'name': 'superchaeyeons', 'skills': './skills/',
                'hooks': './hooks/codex.json'}
    handler = {'type': 'command',
               'command': '"${PLUGIN_ROOT}/hooks/deny-codex-tool.sh"'}
    hooks = {'hooks': {'PreToolUse': [{'matcher': 'apply_patch',
                                     'hooks': [handler]}]}}
    write_json(root / '.codex-plugin/plugin.json', manifest)
    write_json(root / 'hooks/codex.json', hooks)
    # Claude 등록에는 ask가 있어도 Codex는 별도 파일만 읽어야 한다.
    write_json(root / '.claude-plugin/plugin.json', {'name': 'superchaeyeons'})
    write_json(root / 'hooks/hooks.json', {'hooks': {'PreToolUse': [
        {'matcher': 'Bash', 'hooks': [{'type': 'command',
         'command': '"${CLAUDE_PLUGIN_ROOT}/hooks/ask-approval.sh"'}]}]}})
    for name in SKILLS:
        path = root / 'skills' / name / 'SKILL.md'
        path.parent.mkdir(parents=True)
        path.write_text('---\nname: ' + name + '\ndescription: fixture\n---\n', encoding='utf-8')
    for name in ('deny-codex-tool.sh', 'ask-approval.sh'):
        path = root / 'hooks' / name
        path.write_text('#!/bin/sh\nexit 0\n', encoding='utf-8')
        path.chmod(0o755)
    return root, manifest, hooks


def case(title, expected, mutate=None, args=None):
    global passed, failed
    with tempfile.TemporaryDirectory(prefix='codex-registry-') as tmp:
        base = pathlib.Path(tmp)
        root, manifest, hooks = fixture(base)
        if mutate:
            mutate(root, manifest, hooks, base)
        before = {name: (root / name).read_bytes() for name in CLAUDE_PATHS}
        result = subprocess.run([str(CHECKER), *(args if args is not None else ['--codex', str(root)])],
                                capture_output=True, text=True)
        after = {name: (root / name).read_bytes() for name in CLAUDE_PATHS}
        # 오류는 원인 한 줄을 보장하되 원인 문구를 고정하지 않는다.
        error_lines = [line for line in (result.stdout + result.stderr).splitlines() if line.strip()]
        reason_ok = expected != 1 or len(error_lines) == 1
        if result.returncode == expected and before == after and reason_ok:
            passed += 1
            print('  ok    ' + title)
        else:
            failed += 1
            print('  FAIL  ' + title + ' (실제 exit ' + str(result.returncode) + ', 기대 ' + str(expected) + ')')
            print('        ' + (result.stdout + result.stderr).strip().replace('\n', '\n        '))
            if before != after:
                print('        Claude 등록 파일이 변경됨')


def change_manifest(key, value):
    def mutate(root, manifest, hooks, base):
        manifest[key] = value
        write_json(root / '.codex-plugin/plugin.json', manifest)
    return mutate


def change_hooks(value):
    def mutate(root, manifest, hooks, base):
        write_json(root / 'hooks/codex.json', value(hooks))
    return mutate


case('Claude ask 등록이 별도 파일에 있고 Codex가 8개 원본 스킬을 참조하면 통과한다', 0)
case('Codex 매니페스트가 없으면 거절한다', 1,
     lambda r, m, h, b: (r / '.codex-plugin/plugin.json').unlink())
case('Codex 매니페스트 JSON이 깨지면 거절한다', 1,
     lambda r, m, h, b: (r / '.codex-plugin/plugin.json').write_text('{'))
case('필수 스킬 하나가 없으면 거절한다', 1,
     lambda r, m, h, b: (r / 'skills/test-first/SKILL.md').unlink())
case('훅 등록 파일이 없으면 거절한다', 1,
     lambda r, m, h, b: (r / 'hooks/codex.json').unlink())
case('훅 이벤트가 하나도 없으면 등록 누락으로 거절한다', 1,
     change_hooks(lambda h: {'hooks': {}}))
case('PreToolUse 핸들러가 없으면 등록 누락으로 거절한다', 1,
     change_hooks(lambda h: {'hooks': {'PreToolUse': []}}))
case('훅 경로가 절대 경로이면 거절한다', 1,
     change_manifest('hooks', '/tmp/codex.json'))


def outside(root, manifest, hooks, base):
    write_json(base / 'outside.json', hooks)
    manifest['hooks'] = '../outside.json'
    write_json(root / '.codex-plugin/plugin.json', manifest)


case('존재하는 훅 파일이어도 루트 밖 상대 경로이면 거절한다', 1, outside)


def symlink_outside(root, manifest, hooks, base):
    write_json(base / 'outside.json', hooks)
    (root / 'hooks/codex.json').unlink()
    (root / 'hooks/codex.json').symlink_to(base / 'outside.json')


case('훅 경로가 심볼릭 링크로 루트 밖을 가리키면 거절한다', 1, symlink_outside)
case('같은 훅 파일 경로를 두 번 등록하면 거절한다', 1,
     change_manifest('hooks', ['./hooks/codex.json', './hooks/codex.json']))


def duplicate_handler(hooks):
    group = hooks['hooks']['PreToolUse'][0]
    group['hooks'].append(copy.deepcopy(group['hooks'][0]))
    return hooks


case('같은 매처에서 같은 핸들러를 두 번 등록하면 거절한다', 1, change_hooks(duplicate_handler))


def duplicate_group(hooks):
    hooks['hooks']['PreToolUse'].append(copy.deepcopy(hooks['hooks']['PreToolUse'][0]))
    return hooks


case('매처 그룹을 나눠도 같은 핸들러가 중복이면 거절한다', 1, change_hooks(duplicate_group))
case('Codex가 Claude 기본 훅 등록을 직접 참조하면 거절한다', 1,
     change_manifest('hooks', './hooks/hooks.json'))


def ask_handler(hooks):
    hooks['hooks']['PreToolUse'][0]['hooks'][0]['command'] = '"${PLUGIN_ROOT}/hooks/ask-approval.sh"'
    return hooks


case('Codex 전용 파일에서도 Claude ask-approval 훅을 직접 연결하면 거절한다', 1,
     change_hooks(ask_handler))
case('Codex 검사 대상 인자가 없으면 사용법 오류다', 2, args=['--codex'])
case('Codex 검사 인자가 남으면 사용법 오류다', 2, args=['--codex', '/tmp', 'extra'])
case('명령이 참조하는 훅 실행 파일이 없으면 거절한다', 1,
     lambda r, m, h, b: (r / 'hooks/deny-codex-tool.sh').unlink())


def command_outside(root, manifest, hooks, base):
    outside = base / 'outside.py'
    outside.write_text('print("fixture only")\n', encoding='utf-8')
    hooks['hooks']['PreToolUse'][0]['hooks'][0]['command'] = 'python3 -I "${PLUGIN_ROOT}/../outside.py"'
    write_json(root / 'hooks/codex.json', hooks)


case('명령이 참조하는 파일이 존재해도 플러그인 루트 밖이면 거절한다', 1, command_outside)


def unregistered_python(root, manifest, hooks, base):
    path = root / 'hooks/unregistered.py'
    path.write_text('#!/usr/bin/env python3\nprint("unregistered fixture")\n', encoding='utf-8')
    path.chmod(0o755)


case('Codex Python 훅 파일이 등록에 빠지면 거절한다', 1, unregistered_python)

print('Codex 등록 케이스 ' + str(passed + failed) + ' · 통과 ' + str(passed) + ' · 실패 ' + str(failed))
sys.exit(1 if failed else 0)
PY
