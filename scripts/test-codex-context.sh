#!/usr/bin/env bash
# Codex 세션 연결 계약 — 실제 임시 프로젝트에서 이벤트의 관찰 가능한 결과를 확인한다.
# 사용: scripts/test-codex-context.sh
# exit 0 = 전부 통과 · exit 1 = 실패 · exit 2 = 환경 오류
# 근거: 공동 지원 스펙 M6, 후속 연결 계약. 구현 파일을 읽지 않고 이벤트 입출력으로 검증한다.
set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'FAIL: python3 없음' >&2; exit 2; }
python3 -I - "$repo_root" <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

REPO = Path(sys.argv[1])
TEST_CMD = 'scripts/dev.sh test'
BASE_CONF = (REPO / 'scripts/hook-fixtures/conf/full.conf').read_text()
CORE = ('core-approval-triggers', 'core-stop-conditions', 'core-task-steps', 'core-reporting')
DOC_HEADING = next(line for line in (REPO / 'plugin/rules/doc-writing.md').read_text().splitlines()
                   if line.startswith('# '))
passed = failed = 0


def require(condition, reason):
    if not condition:
        raise AssertionError(reason)


def strings(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return '\n'.join(strings(item) for item in value.values())
    if isinstance(value, list):
        return '\n'.join(strings(item) for item in value)
    return ''


class Fixture:
    def __init__(self, base, fresh=False):
        self.base = Path(base).resolve()
        self.root = self.base / 'project with spaces'
        self.root.mkdir()
        self.conf = self.root / '.claude/harness.conf'
        self.env = dict(os.environ, PLUGIN_ROOT=str(REPO / 'plugin'),
                        CLAUDE_PLUGIN_ROOT=str(REPO / 'plugin'))
        # 다른 프로젝트의 설정을 실수로 물려받지 않게 이벤트 cwd를 판정의 기준으로 쓴다.
        self.env.pop('CLAUDE_PROJECT_DIR', None)
        self.test_sequence = 0
        if fresh:
            return
        self.conf.parent.mkdir()
        self.conf.write_text(BASE_CONF)
        self.set_conf('TEST_CMD', TEST_CMD)
        self.set_conf('FORMAT_CMD', '(없음) — 포맷 안 함')
        self.set_conf('FORMAT_PATHS', '')
        (self.root / 'app.py').write_text('after=2\n')
        (self.root / 'docs').mkdir()
        (self.root / 'docs/note.md').write_text('# Example\n\nText.\n')

    def set_conf(self, key, value):
        lines = [line for line in self.conf.read_text().splitlines() if not line.startswith(key + '=')]
        self.conf.write_text('\n'.join(lines) + '\n' + key + '=' + value + '\n')

    def call(self, mode, fields=None, sid='session-a', raw=None):
        payload = {'cwd': str(self.root), 'session_id': sid}
        payload.update(fields or {})
        data = json.dumps(payload) if raw is None else raw
        hook = Path(self.env['PLUGIN_ROOT']) / 'hooks/codex-context.py'
        run = subprocess.run([sys.executable, '-I', str(hook), mode], input=data,
                             text=True, capture_output=True, cwd=self.root, env=self.env)
        require(run.returncode == 0,
                mode + '는 비차단 exit 0이어야 함: ' + str(run.returncode) + ' ' + run.stderr[:250])
        try:
            result = json.loads(run.stdout)
        except Exception as error:
            raise AssertionError(mode + '는 JSON 하나를 출력해야 함: ' + run.stdout[:200]) from error
        require(isinstance(result, dict), mode + ' 출력은 JSON 객체여야 함')
        return result

    def edit(self, path='app.py', sid='session-a', response=None):
        command = '*** Begin Patch\n*** Update File: ' + path + '\n@@\n-old\n+new\n*** End Patch'
        return self.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'apply_patch',
                                 'tool_input': {'command': command},
                                 'tool_response': {'exit_code': 0} if response is None else response}, sid)

    def test(self, response=None, sid='session-a', command=TEST_CMD):
        # unified exec는 최종 PostToolUse만 보낼 수 있어 시작 세대는 PreToolUse에서 고정한다.
        self.test_sequence += 1
        tool_id = 'fixture-test-' + str(self.test_sequence)
        self.call('pre', {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                          'tool_use_id': tool_id, 'tool_input': {'command': command}}, sid)
        return self.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                                 'tool_use_id': tool_id, 'tool_input': {'command': command},
                                 'tool_response': {'exit_code': 0} if response is None else response}, sid)

    def stop(self, sid='session-a', active=False):
        return self.call('stop', {'hook_event_name': 'Stop', 'last_assistant_message': '구현 완료',
                                 'stop_hook_active': active}, sid)


def case(title, body, fresh=False):
    global passed, failed
    with tempfile.TemporaryDirectory(prefix='codex-context-') as tmp:
        fixture = Fixture(tmp, fresh=fresh)
        try:
            body(fixture)
            passed += 1
            print('  ok    ' + title)
        except Exception as error:
            failed += 1
            print('  FAIL  ' + title + ' — ' + str(error))


def is_blocked(result):
    return result.get('decision') == 'block'


def rules(f):
    result = f.call('rules', {'hook_event_name': 'SessionStart', 'source': 'startup'})
    text = strings(result)
    for name in CORE:
        body = (REPO / 'plugin/rules' / (name + '.md')).read_text()
        require(body in text, '공통 규칙 원문이 빠짐: ' + name)


case('세션 시작이면 4개 공통 규칙 원문을 주입한다', rules)


def missing_config(f):
    f.conf.unlink()
    result = f.call('config', {'hook_event_name': 'SessionStart', 'source': 'startup'})
    require('init-harness' in strings(result), '설정 없을 때 초기화 안내가 없음')


case('공통 설정이 없으면 init-harness를 안내한다', missing_config)


def configured(f):
    f.set_conf('TEST_CMD', 'make fixture-check')
    result = f.call('config', {'hook_event_name': 'SessionStart', 'source': 'startup'})
    require('make fixture-check' in strings(result), '공통 설정의 실제 값이 주입되지 않음')


case('설정 주입이면 단일 공통 설정의 값을 사용한다', configured)


def runtime(f):
    text = strings(f.call('runtime', {'hook_event_name': 'SessionStart'}))
    require('check-codex-approval.py' in text and '승인' in text and '확인' in text,
            'Codex 사전 승인 검사와 명시적 확인 차이 안내가 없음')


case('Codex 실행 안내이면 승인 사전 검사와 명시적 확인을 알린다', runtime)


def pending(f):
    f.edit()
    require(is_blocked(f.stop()), '편집 후 테스트가 없는데 완료를 허용함')
    require((f.root / '.codex/harness-state').is_dir(), 'Codex 증거 폴더가 없음')


case('코드 편집 후 테스트가 없으면 완료를 되돌린다', pending)


def completed(f):
    f.edit()
    f.test()
    require(f.stop() == {}, '마지막 편집 뒤 테스트 성공이면 빈 JSON이어야 함')


case('마지막 코드 편집 뒤 테스트가 성공하면 완료를 허용한다', completed)


def failed_test(f):
    f.edit()
    f.test({'exit_code': 1})
    require(is_blocked(f.stop()), '테스트 실패를 성공으로 인정함')


case('테스트가 실패하면 완료를 되돌린다', failed_test)


def running_test(f):
    f.edit()
    f.test({'session_id': 12})
    require(is_blocked(f.stop()), '실행 중인 테스트를 성공으로 인정함')


case('테스트가 실행 중이면 성공 증거로 인정하지 않는다', running_test)


def mention_test(f):
    f.edit()
    f.test(command='echo "' + TEST_CMD + '"')
    require(is_blocked(f.stop()), '명령 문자열 언급을 테스트 실행으로 인정함')


case('테스트 명령을 출력만 하면 실행 증거로 인정하지 않는다', mention_test)


def bash_redirect_edit(f):
    f.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                    'tool_input': {'command': 'printf code > app.py'},
                    'tool_response': {'exit_code': 0}})
    require(is_blocked(f.stop()), 'Bash 리다이렉션의 코드 편집을 놓침')


case('Bash로 코드 파일에 출력하면 테스트 전 완료를 되돌린다', bash_redirect_edit)


def bash_sed_after_test(f):
    f.edit()
    f.test()
    require(f.stop() == {}, '재편집 전 테스트 성공 증거가 없음')
    f.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                    'tool_input': {'command': "sed -i 's/old/new/' app.py"},
                    'tool_response': {'exit_code': 0}})
    require(is_blocked(f.stop()), '테스트 성공 뒤 Bash sed 편집을 놓침')


case('성공한 테스트 뒤 Bash sed로 편집하면 이전 성공을 무효로 한다', bash_sed_after_test)


def reedit(f):
    f.edit()
    f.test()
    f.edit()
    require(is_blocked(f.stop()), '성공한 테스트 이후 편집을 놓침')


case('테스트 성공 뒤 다시 편집하면 이전 성공을 무효로 한다', reedit)


def reentry(f):
    f.edit()
    require(f.stop(active=True) == {}, 'Stop 재진입은 빈 JSON으로 통과해야 함')


case('Stop이 재진입하면 무한 반복 없이 통과한다', reentry)


def sessions(f):
    f.edit(sid='session-a')
    f.test(sid='session-b')
    require(is_blocked(f.stop(sid='session-a')), '다른 세션 테스트가 현재 편집을 승인함')
    require(f.stop(sid='session-b') == {}, '편집 없는 다른 세션을 차단함')


case('서로 다른 세션의 편집과 테스트 증거를 섞지 않는다', sessions)


def malformed(f):
    for mode in ('rules', 'config', 'runtime', 'pre', 'post', 'stop'):
        result = f.call(mode, raw='not json')
        require(bool(result.get('systemMessage')), mode + ' 입력 오류를 조용히 무시함')
        require(not is_blocked(result), mode + ' 입력 오류로 작업을 차단함')


case('훅 입력을 해석하지 못하면 경고하고 통과한다', malformed)


def path_rules(f):
    first = strings(f.edit('docs/note.md'))
    second = strings(f.edit('docs/note.md'))
    require(DOC_HEADING in first, '마크다운 경로 규칙이 주입되지 않음')
    require(DOC_HEADING not in second, '같은 세션에 경로 규칙을 중복 주입함')


case('마크다운 편집이면 문서 규칙을 한 세대에 한 번만 주입한다', path_rules)


def reset_path_rules(f):
    for source in ('clear', 'compact'):
        f.edit('docs/note.md')
        f.call('rules', {'hook_event_name': 'SessionStart', 'source': source})
        require(DOC_HEADING in strings(f.edit('docs/note.md')), source + ' 이후 경로 규칙이 복구되지 않음')


case('clear나 compact 뒤에는 경로 규칙을 다시 주입한다', reset_path_rules)


def formatting(f):
    marker = f.base / 'format-marker'
    f.set_conf('FORMAT_CMD', 'touch "' + str(marker) + '"')
    f.set_conf('FORMAT_PATHS', '*.py')
    f.edit('docs/note.md')
    require(not marker.exists(), '포맷 대상 아닌 파일에 포맷을 실행함')
    f.edit('app.py')
    require(marker.is_file(), '포맷 대상 파일에 포맷을 실행하지 않음')


case('포맷 경로에 맞는 파일을 편집할 때만 공통 포맷 명령을 실행한다', formatting)


def format_failure(f):
    f.set_conf('FORMAT_CMD', 'false')
    f.set_conf('FORMAT_PATHS', '*.py')
    result = f.edit('app.py')
    require(bool(result.get('systemMessage')), '포맷 실패를 알리지 않음')
    require(not is_blocked(result), '포맷 실패가 작업을 차단함')


case('포맷 명령이 실패하면 알리고 작업은 계속한다', format_failure)


def file_formatter(f):
    runner = f.root / 'tools' / '파일 formatter'
    runner.parent.mkdir()
    runner.write_text(
        '#!/usr/bin/env python3\n'
        'import json, os, sys\n'
        'from pathlib import Path\n'
        'with Path(os.environ["FORMAT_LOG"]).open("a") as log:\n'
        '    print(json.dumps([os.getcwd(), sys.argv[1:]]), file=log)\n'
        'if len(sys.argv) != 2:\n'
        '    raise SystemExit(2)\n'
        'with Path(sys.argv[1]).open("ab") as target:\n'
        '    target.write(b"# formatted\\n")\n')
    runner.chmod(0o755)
    f.env['FORMAT_LOG'] = str(f.base / 'format.jsonl')
    f.set_conf('FORMAT_FILE_EXEC', str(runner.relative_to(f.root)))
    f.set_conf('FORMAT_PATHS', '*.py *.ts')
    f.set_conf('FORMAT_CMD', 'touch whole-ran')
    return runner


def require_formatted(f, *paths):
    log = Path(f.env['FORMAT_LOG'])
    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    expected = [[str(f.root), [str(f.root / path)]] for path in paths]
    require(sorted(calls) == sorted(expected), '포매터 작업 폴더와 경로 인자 불일치: ' + repr(calls))


def format_patch(f, patch, exit_code=0):
    return f.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'apply_patch',
                           'tool_input': {'command': '*** Begin Patch\n' + patch + '\n*** End Patch'},
                           'tool_response': {'exit_code': exit_code}})


def format_multi_file(f):
    file_formatter(f)
    added = "한글 '따옴표'와 공백.ts"
    moved = '새 이름 "둘".py'
    other = f.root / 'unfinished.py'
    other.write_bytes(b'staged bytes\n')
    subprocess.run(['git', 'init', '-q'], cwd=f.root, check=True)
    subprocess.run(['git', 'add', '--', 'app.py', other.name], cwd=f.root, check=True)
    index = f.root / '.git/index'
    original_index = index.read_bytes()
    other.write_bytes(b'work in progress\r\n')
    (f.root / 'app.py').write_text('answer=42\n')
    (f.root / added).write_text('let n=1\n')
    (f.root / moved).write_text('moved=1\n')
    patch = (f'*** Add File: {added}\n+let n=1\n'
             '*** Update File: app.py\n@@\n-old\n+intermediate\n'
             '*** Update File: app.py\n@@\n-intermediate\n+answer=42\n'
             f'*** Update File: old.py\n*** Move to: {moved}\n@@\n-old\n+moved=1\n'
             '*** Delete File: deleted.ts\n'
             '*** Update File: docs/note.md\n@@\n-old\n+Text.')
    format_patch(f, patch)
    require_formatted(f, added, 'app.py', moved)
    for name in (added, 'app.py', moved):
        require((f.root / name).read_bytes().endswith(b'# formatted\n'), '포맷 결과가 없음: ' + name)
    require(other.read_bytes() == b'work in progress\r\n', '다른 작업 파일이 바뀜')
    require(index.read_bytes() == original_index, 'Git 인덱스가 바뀜')
    require(not (f.root / 'whole-ran').exists(), '여러 파일 편집에서 전체 포맷이 실행됨')


case('여러 파일을 편집하면 추가·수정·이동된 대상만 한 번씩 포맷하고 다른 작업 및 인덱스를 보존한다',
     format_multi_file)


def format_without_whole(f):
    file_formatter(f)
    f.set_conf('FORMAT_CMD', '')
    f.edit()
    require_formatted(f, 'app.py')


case('전체 명령이 비어 있어도 일치하는 파일은 파일별로 포맷한다', format_without_whole)


def format_digit_pattern(f):
    file_formatter(f)
    f.set_conf('FORMAT_PATHS', 'src/test[[:digit:]].py')
    (f.root / 'src').mkdir()
    names = ('src/test7.py', 'src/testA.py', 'src/test77.py')
    for name in names:
        (f.root / name).write_text('edited\n')
    format_patch(f, '\n'.join(f'*** Add File: {name}\n+edited' for name in names))
    require_formatted(f, 'src/test7.py')
    require(not (f.root / 'whole-ran').exists(), '숫자 패턴으로 편집한 뒤 전체 명령이 실행됨')


case('FORMAT_PATHS의 Bash 숫자 문자 클래스에 맞는 한 자리 숫자 파일만 포맷한다', format_digit_pattern)


def failed_format_patch(f):
    file_formatter(f)
    f.edit(response={'exit_code': 1})
    require_formatted(f)
    require(not (f.root / 'whole-ran').exists(), '실패한 패치에서 전체 포맷을 실행함')


case('패치가 실패하면 파일별 포맷과 전체 포맷을 모두 건너뛴다', failed_format_patch)


def non_file_format_targets(f):
    file_formatter(f)
    (f.root / 'directory.py').mkdir()
    f.edit('directory.py')
    f.edit('missing.ts')
    require_formatted(f)
    require(not (f.root / 'whole-ran').exists(), '일반 파일이 아닌 경로에서 전체 포맷을 실행함')


case('패턴이 맞아도 디렉터리나 없는 파일이면 포맷을 건너뛴다', non_file_format_targets)


def rejected_formatter(f, problem, reason):
    runner = file_formatter(f)
    target = f.root / 'app.py'
    if problem == 'missing':
        runner.unlink()
    elif problem == 'not-executable':
        runner.chmod(0o644)
    elif problem == 'failure':
        target.write_bytes(b'first edited line\r\nlast edited line')
        runner.write_text('#!/bin/sh\nprintf partial > "$1" || exit 2\necho "invalid source" >&2\nexit 17\n')
    elif problem == 'outside-runner':
        external = runner.rename(f.base / 'external-formatter')
        runner.symlink_to(external)
    elif problem == 'outside-target':
        external = target.rename(f.base / 'external-target.py')
        target.symlink_to(external)
    before = target.read_bytes()
    result = f.edit()
    warning = result.get('systemMessage', '')
    require('app.py' in warning and re.search(reason, warning, re.I),
            '편집한 파일 및 원인을 알리는 경고가 없음: ' + repr(warning))
    require(not is_blocked(result), '파일별 포맷 오류가 편집을 차단함')
    require(target.read_bytes() == before, '포맷 오류 후 편집 파일이 바뀜')
    require_formatted(f)
    require(not (f.root / 'whole-ran').exists(), '파일별 포맷 오류 후 전체 명령을 실행함')


for problem, label, reason in (
    ('missing', '실행 파일이 없으면', '없|찾|존재|missing|not found|no such'),
    ('not-executable', '실행 권한이 없으면', '권한|실행.*(없|못|불가|않)|permission|executable|access'),
    ('failure', '포매터가 편집 파일을 일부 덮어쓰고 exit 17로 끝나면', '17|invalid source'),
    ('outside-runner', '실행 파일 링크가 저장소 밖을 가리키면', '밖|외부|벗어|경계|범위|outside|escape'),
    ('outside-target', '대상 파일 링크가 저장소 밖을 가리키면', '밖|외부|벗어|경계|범위|outside|escape'),
):
    case(label + ' 대상과 원인을 알리고 편집을 유지하며 전체 포맷을 건너뛴다',
         lambda f: rejected_formatter(f, problem, reason))


def legacy_empty_file_key(f):
    f.set_conf('FORMAT_FILE_EXEC', '')
    formatting(f)


case('파일별 실행 파일 설정이 빈 값이면 기존 전체 포맷 동작을 유지한다', legacy_empty_file_key)


def unsafe_session(f):
    before = {path.resolve() for path in f.base.rglob('*') if path.is_file()}
    f.edit(sid='../../escaped-session')
    require(is_blocked(f.stop(sid='../../escaped-session')), '특수 세션 ID의 증거를 잃어버림')
    state = (f.root / '.codex/harness-state').resolve()
    after = {path.resolve() for path in f.base.rglob('*') if path.is_file()}
    for created in after - before:
        require(created.is_relative_to(state), '세션 ID가 상태 폴더 밖에 파일을 만듦: ' + str(created))


case('세션 ID에 상위 경로 문자가 있어도 상태 폴더 밖에 쓰지 않는다', unsafe_session)

def old_test_completion(f):
    f.edit()
    f.call('pre', {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                   'tool_use_id': 't1', 'tool_input': {'command': TEST_CMD}})
    started = {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
               'tool_use_id': 't1', 'tool_input': {'command': TEST_CMD},
               'tool_response': {'session_id': 12}}
    f.call('post', started)
    f.edit()
    finished = {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                'tool_use_id': 't1', 'tool_input': {'command': TEST_CMD},
                'tool_response': {'exit_code': 0}}
    f.call('post', finished)
    require(is_blocked(f.stop()), '후속 편집 전에 시작한 테스트 완료를 최신 성공으로 인정함')


case('테스트 실행 중 재편집하면 나중에 도착한 성공도 완료 증거로 쓰지 않는다', old_test_completion)

def failed_output_with_zero_exit(f):
    f.edit()
    f.test({'exit_code': 0, 'output': 'Tests failed\n3 failed'})
    require(is_blocked(f.stop()), '실패 요약이 있는 테스트 출력을 exit 0만 보고 성공으로 인정함')


case('exit 0이어도 테스트 실패 요약이 있으면 완료를 되돌린다', failed_output_with_zero_exit)


def unknown_test_origin(f):
    f.edit()
    for tool_id in (None, 'orphan-t2'):
        finished = {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                    'tool_input': {'command': TEST_CMD}, 'tool_response': {'exit_code': 0}}
        if tool_id is not None:
            finished['tool_use_id'] = tool_id
        f.call('post', finished)
        require(is_blocked(f.stop()), '시작 증거가 없는 테스트 성공을 인정함: ' + str(tool_id))


case('도구 ID나 PreToolUse 시작 기록이 없는 성공은 완료 증거로 쓰지 않는다', unknown_test_origin)

def install_native_test_command(f, code=0):
    scripts = f.root / 'scripts'
    scripts.mkdir(exist_ok=True)
    command = scripts / 'dev.sh'
    command.write_text("#!/bin/sh\nprintf 'OK\\n'\nexit " + str(code) + '\n')
    command.chmod(0o755)


def native_pre_command(f, tool_id):
    result = f.call('pre', {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                            'tool_use_id': tool_id, 'tool_input': {'command': TEST_CMD}})
    command = result.get('hookSpecificOutput', {}).get('updatedInput', {}).get('command')
    require(isinstance(command, str) and command and command != TEST_CMD,
            '정확한 테스트 명령의 실제 종료 코드 확인용 updatedInput.command가 없음')
    return command


def execute_native_wrapper(f, command, expected):
    run = subprocess.run(['/bin/bash', '-c', command], cwd=f.root, env=f.env,
                         capture_output=True, text=True)
    require(run.returncode == expected, '테스트 감싼 명령이 원래 종료 코드를 바꿈: ' + str(run.returncode))
    require('OK' in run.stdout, '테스트 감싼 명령이 원래 stdout을 없앰')
    return run.stdout


def native_bash_post(f, tool_id, command, stdout):
    return f.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                          'tool_use_id': tool_id, 'tool_input': {'command': command},
                          'tool_response': stdout})


def native_string_success(f):
    install_native_test_command(f)
    f.edit()
    command = native_pre_command(f, 'native-success')
    stdout = execute_native_wrapper(f, command, 0)
    native_bash_post(f, 'native-success', command, stdout)
    require(f.stop() == {}, '실제 종료 코드가 확인된 native 문자열 성공 결과를 인정하지 않음')


case('native Bash stdout만 도착해도 호출별 감싼 명령의 성공이면 완료를 허용한다', native_string_success)


def native_string_failure(f):
    install_native_test_command(f, 1)
    f.edit()
    command = native_pre_command(f, 'native-failure')
    stdout = execute_native_wrapper(f, command, 1)
    native_bash_post(f, 'native-failure', command, stdout)
    require(is_blocked(f.stop()), 'OK를 출력했어도 실제 exit 1인 테스트를 성공으로 인정함')


case('native Bash가 OK를 출력해도 실제 종료 코드가 실패면 완료를 되돌린다', native_string_failure)


def native_unproven_output(f):
    install_native_test_command(f)
    for index, variant in enumerate(('plain-ok', 'other-call', 'fake-envelope')):
        f.edit()
        tool_id = 'native-unproven-' + str(index)
        command = native_pre_command(f, tool_id)
        if variant == 'other-call':
            other_command = native_pre_command(f, 'native-other-call')
            stdout = execute_native_wrapper(f, other_command, 0)
        elif variant == 'fake-envelope':
            stdout = 'Exit code: 0\nWall time: 0 seconds\nOutput:\nOK\n'
        else:
            stdout = 'OK\n'
        native_bash_post(f, tool_id, command, stdout)
        require(is_blocked(f.stop()), '해당 호출의 종료 표식이 없는 Bash 출력을 성공으로 인정함: ' + variant)


case('단순 OK나 다른 호출의 표식 또는 Bash가 출력한 가짜 envelope는 성공 증거가 아니다', native_unproven_output)


def native_string_old_generation(f):
    install_native_test_command(f)
    f.edit()
    command = native_pre_command(f, 'native-old-generation')
    stdout = execute_native_wrapper(f, command, 0)
    f.edit()
    native_bash_post(f, 'native-old-generation', command, stdout)
    require(is_blocked(f.stop()), '시작 뒤 재편집했는데 늦게 도착한 native 성공을 인정함')


case('native 종료 표식이 맞아도 테스트 시작 뒤 새 편집이 있으면 성공을 무효로 한다', native_string_old_generation)


def native_patch_success(f):
    stdout = ('Exit code: 0\nWall time: 0 seconds\nOutput:\n'
              'Success. Updated the following files:\nM ' + str(f.root / 'docs/note.md') + '\n')
    result = f.edit('docs/note.md', response=stdout)
    require(not result.get('systemMessage'), '정상 apply_patch native envelope를 해석하지 못해 경고함')
    require(DOC_HEADING in strings(result), '정상 apply_patch native envelope 뒤 문서 규칙을 주입하지 않음')


case('apply_patch의 native 성공 envelope이면 경고 없이 경로 후처리를 실행한다', native_patch_success)


def native_patch_failure(f):
    stdout = 'Exit code: 1\nWall time: 0 seconds\nOutput:\nPatch failed.\n'
    f.edit(response=stdout)
    require(f.stop() == {}, '실패한 apply_patch native envelope를 편집 성공 증거로 기록함')


case('apply_patch의 native 실패 envelope이면 편집 성공으로 기록하지 않는다', native_patch_failure)

def native_string_wrong_workdir(f):
    install_native_test_command(f)
    other = f.base / 'other-root'
    (other / 'scripts').mkdir(parents=True)
    other_command = other / 'scripts/dev.sh'
    other_command.write_text("#!/bin/sh\nprintf 'OTHER_OK\\n'\nexit 0\n")
    other_command.chmod(0o755)
    f.edit()
    command = native_pre_command(f, 'native-other-workdir')
    run = subprocess.run(['/bin/bash', '-c', command], cwd=other, env=f.env,
                         capture_output=True, text=True)
    require(run.returncode == 0 and 'OTHER_OK' in run.stdout,
            '다른 작업 디렉터리에서 성공한 테스트라는 재현 조건을 만족하지 않음')
    native_bash_post(f, 'native-other-workdir', command, run.stdout)
    require(is_blocked(f.stop()), '다른 작업 디렉터리의 테스트 성공을 루트 검증 증거로 인정함')


case('같은 테스트 문자열이어도 다른 물리 작업 디렉터리에서 실행한 성공은 인정하지 않는다', native_string_wrong_workdir)


def configure_consumer(f, plugin, format_cmd='없음 — 사용하지 않음'):
    f.env.pop('DEV_CONF', None)
    subprocess.run([sys.executable, '-I', str(plugin / 'scripts/configure-harness.py'),
                    '--project', str(f.root), '--target', 'both', '--apply'],
                   cwd=f.root, env=f.env, capture_output=True, check=True)
    for line in BASE_CONF.splitlines():
        if line and not line.startswith('#'):
            f.set_conf(*line.split('=', 1))
    f.set_conf('TEST_CMD', TEST_CMD)
    f.set_conf('FORMAT_CMD', '(없음) — 포맷 안 함')
    f.set_conf('POLISH_ENABLED', '0')

    dev = f.root / 'scripts/dev.conf'
    values = {'TEST_CMD': 'python3 scripts/check_answer.py', 'TEST_REPORT': 'last-line', 'FMT_CMD': format_cmd,
              'LOG_DIR': '.logs'}
    lines = []
    for line in dev.read_text().splitlines():
        if line and not line.startswith('#'):
            key = line.split('=', 1)[0]
            line = key + '=' + values.get(key, '없음 — 사용하지 않음')
        lines.append(line)
    dev.write_text('\n'.join(lines) + '\n')
    (f.root / 'scripts/check_answer.py').write_text(
        'from pathlib import Path\n'
        'actual = Path("app.py").read_text().strip()\n'
        'if actual != "answer = 42":\n'
        '    raise SystemExit("consumer answer incorrect")\n'
        'print("consumer answer correct")\n')
    require(not (f.root / 'scripts/dev.sh').exists(), '소비 프로젝트에 dev.sh가 복사됨')


def manual_format(f):
    plugin = REPO / 'plugin'
    configure_consumer(f, plugin, format_cmd='touch whole-ran')
    file_formatter(f)
    dev = plugin / 'scripts/dev.sh'
    f.set_conf('FORMAT_CMD', shlex.quote(str(dev)) + ' fmt')
    f.set_conf('FORMAT_PATHS', '')
    (f.root / 'app.py').write_text('answer=42\n')
    f.edit()
    marker = f.root / 'whole-ran'
    require(not marker.exists(), '대상 패턴이 비었는데 전체 포맷이 실행됨')
    require_formatted(f)
    run = subprocess.run([str(dev), 'fmt'], cwd=f.root, env=f.env, text=True, capture_output=True)
    require(run.returncode == 0 and marker.is_file(), '수동 전체 포맷 실패: ' + run.stdout + run.stderr)
    require_formatted(f)


case('대상 패턴이 비어 있으면 자동 포맷을 건너뛰고 수동 dev.sh fmt는 전체 명령을 실행한다',
     manual_format, fresh=True)


def consumer_command(f, host, plugin):
    event = {'hook_event_name': 'SessionStart', 'source': 'startup'}
    if host == 'Codex':
        result = f.call('config', event)
    else:
        run = subprocess.run([str(plugin / 'hooks/auto-inject-config.sh')], input=json.dumps(event),
                             cwd=f.root, env=f.env, text=True, capture_output=True, check=True)
        result = json.loads(run.stdout)
    context = result['hookSpecificOutput']['additionalContext']
    fields = [line.strip().strip('|').split('|') for line in context.splitlines()]
    command = next((row[1].strip().strip('`') for row in fields
                    if len(row) == 2 and row[0].strip().strip('`') == '{{테스트 명령}}'), '')
    require(str(plugin / 'scripts/dev.sh') in shlex.split(command),
            host + ' 세션의 테스트 명령이 현재 설치된 실행 파일을 가리키지 않음: ' + repr(command))
    return command


def claude_consumer_stop(f, plugin, edit, command=None, run=None):
    turns = [('user', '코드를 고치고 테스트해 주세요.'),
             ('assistant', [{'type': 'tool_use', 'id': 'edit', 'name': 'Bash',
                             'input': {'command': edit}}]),
             ('user', [{'type': 'tool_result', 'tool_use_id': 'edit', 'content': ''}])]
    if run is not None:
        turns.extend([('assistant', [{'type': 'tool_use', 'id': 'test', 'name': 'Bash',
                                      'input': {'command': command}}]),
                      ('user', [{'type': 'tool_result', 'tool_use_id': 'test',
                                 'is_error': run.returncode != 0, 'content': run.stdout}])])
    turns.append(('assistant', '구현 완료'))
    transcript = f.base / 'claude-session.jsonl'
    transcript.write_text(''.join(json.dumps({'type': kind, 'message': {'content': content}}) + '\n'
                                  for kind, content in turns))
    return subprocess.run([str(plugin / 'hooks/deny-unverified-completion.sh')], cwd=f.root,
                          input=json.dumps({'transcript_path': str(transcript), 'stop_hook_active': False}),
                          env=f.env, text=True, capture_output=True).returncode


def installed_consumer(f, host):
    plugin = f.base / 'plugin v1'
    shutil.copytree(REPO / 'plugin', plugin)
    configure_consumer(f, plugin)
    for version in (1, 2):
        if version == 2:
            plugin = plugin.rename(f.base / "team's plugin v2")
        f.env.update(PLUGIN_ROOT=str(plugin), CLAUDE_PLUGIN_ROOT=str(plugin))
        command = consumer_command(f, host, plugin)
        for answer, expected_exit in ((41, 1), (42, 0)):
            edit = 'echo "answer = ' + str(answer) + '" > app.py'
            subprocess.run(['/bin/bash', '-c', edit], cwd=f.root, check=True)
            effective_command = command
            if host == 'Codex':
                f.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash',
                                'tool_input': {'command': edit}, 'tool_response': {'exit_code': 0}})
                require(is_blocked(f.stop()), '새 편집 직후 전체 테스트 전 완료가 허용됨')
                tool_id = f'v{version}-answer-{answer}'
                pre = f.call('pre', {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                                     'tool_use_id': tool_id, 'tool_input': {'command': command}})
                effective_command = pre.get('hookSpecificOutput', {}).get('updatedInput', {}).get('command', command)
            else:
                require(claude_consumer_stop(f, plugin, edit) == 2, 'Claude가 실행 전 완료를 허용함')
            # Bash 도구에 설치 환경 변수가 없어도 세션에서 읽은 명령을 그대로 실행할 수 있어야 한다.
            shell_env = {k: v for k, v in f.env.items() if k not in ('PLUGIN_ROOT', 'CLAUDE_PLUGIN_ROOT')}
            run = subprocess.run(['/bin/bash', '-c', effective_command], cwd=f.root,
                                 env=shell_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            require(run.returncode == expected_exit and 'consumer answer' in run.stdout,
                    f'{host} 실제 전체 테스트 exit {run.returncode}, 기대 {expected_exit}: ' + run.stdout)
            if host == 'Codex':
                native_bash_post(f, tool_id, effective_command, run.stdout)
                result = f.stop()
                require(is_blocked(result) if expected_exit else result == {},
                        'Codex가 실제 전체 테스트 결과와 다르게 완료를 판정함: ' + repr(result))
            else:
                expected_stop = 2 if expected_exit else 0
                require(claude_consumer_stop(f, plugin, edit, command, run) == expected_stop,
                        'Claude가 실제 전체 테스트 결과와 다르게 완료를 판정함')


for host in ('Claude', 'Codex'):
    case(host + ' 설치 경로가 바뀌어도 세션의 전체 테스트 명령을 실행해 완료 여부를 판정한다',
         lambda f: installed_consumer(f, host), fresh=True)

def quoted_project_test(f):
    script = f.root / "project tests.sh"
    script.write_text("#!/bin/sh\nprintf 'OK\\n'\n")
    script.chmod(0o755)
    command = "'./project tests.sh'"
    f.set_conf('TEST_CMD', command)
    f.edit()
    pre = f.call('pre', {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                         'tool_use_id': 'custom-path', 'tool_input': {'command': command}})
    wrapped = pre['hookSpecificOutput']['updatedInput']['command']
    stdout = execute_native_wrapper(f, wrapped, 0)
    native_bash_post(f, 'custom-path', wrapped, stdout)
    require(f.stop() == {}, '공백이 있는 프로젝트 고유 테스트의 성공을 인정하지 않음')
    run = subprocess.run(['/bin/bash', '-c', command], cwd=f.root, capture_output=True, text=True, check=True)
    f.env['CLAUDE_PROJECT_DIR'] = str(f.root)
    require(claude_consumer_stop(f, REPO / 'plugin', 'echo a > app.py', command, run) == 0,
            'Claude가 인용된 프로젝트 고유 테스트의 성공을 인정하지 않음')


case('프로젝트 고유 테스트 실행 파일 이름에 공백이 있어도 두 호스트가 결과를 확인한다', quoted_project_test)

print('Codex 세션 연결 케이스 ' + str(passed + failed) + ' · 통과 ' + str(passed) + ' · 실패 ' + str(failed))
sys.exit(1 if failed else 0)
PY
