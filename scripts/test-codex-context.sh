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
import subprocess
import sys
import tempfile

REPO = Path(sys.argv[1])
HOOK = REPO / 'plugin/hooks/codex-context.py'
TEST_CMD = 'scripts/dev.sh test'
BASE_CONF = (REPO / 'scripts/hook-fixtures/conf/full.conf').read_text()
CORE = ('core-gates', 'core-guardrails', 'core-workflow', 'core-reporting')
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
    def __init__(self, base):
        self.base = Path(base)
        self.root = self.base / 'project with spaces'
        (self.root / '.claude').mkdir(parents=True)
        self.conf = self.root / '.claude/harness.conf'
        self.conf.write_text(BASE_CONF)
        self.set_conf('TEST_CMD', TEST_CMD)
        self.set_conf('FORMAT_CMD', '(없음) — 포맷 안 함')
        self.set_conf('FORMAT_PATHS', '')
        (self.root / 'app.py').write_text('after=2\n')
        (self.root / 'docs').mkdir()
        (self.root / 'docs/note.md').write_text('# Example\n\nText.\n')
        self.env = dict(os.environ, PLUGIN_ROOT=str(REPO / 'plugin'),
                        CLAUDE_PLUGIN_ROOT=str(REPO / 'plugin'))
        # 다른 프로젝트의 설정을 실수로 물려받지 않게 이벤트 cwd를 판정의 기준으로 쓴다.
        self.env.pop('CLAUDE_PROJECT_DIR', None)
        self.test_sequence = 0

    def set_conf(self, key, value):
        lines = [line for line in self.conf.read_text().splitlines() if not line.startswith(key + '=')]
        self.conf.write_text('\n'.join(lines) + '\n' + key + '=' + value + '\n')

    def call(self, mode, fields=None, sid='session-a', raw=None):
        payload = {'cwd': str(self.root), 'session_id': sid}
        payload.update(fields or {})
        data = json.dumps(payload) if raw is None else raw
        run = subprocess.run([sys.executable, '-I', str(HOOK), mode], input=data,
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


def case(title, body):
    global passed, failed
    with tempfile.TemporaryDirectory(prefix='codex-context-') as tmp:
        fixture = Fixture(tmp)
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

print('Codex 세션 연결 케이스 ' + str(passed + failed) + ' · 통과 ' + str(passed) + ' · 실패 ' + str(failed))
sys.exit(1 if failed else 0)
PY
