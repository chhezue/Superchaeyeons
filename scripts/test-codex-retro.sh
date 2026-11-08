#!/usr/bin/env bash
# Codex 회고·다듬기 연결 계약 — 임시 기록과 가짜 외부 분석 실행기로 도구별 격리를 검증한다.
# 사용: scripts/test-codex-retro.sh
# exit 0 = 전부 통과 · exit 1 = 실패 · exit 2 = 환경 오류
# 실제 LLM·Gemini 네트워크 호출이나 개인 Claude 메모리 접근은 하지 않는다.
set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'FAIL: python3 없음' >&2; exit 2; }
python3 -I - "$repo_root" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REPO = Path(sys.argv[1])
CONTEXT = REPO / 'plugin/hooks/codex-context.py'
ANALYZE = REPO / 'plugin/scripts/analyze-corrections.sh'
POLISH = REPO / 'plugin/scripts/polish-with-gemini.sh'
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
        (self.root / '.claude/harness.conf').write_text('DOC_ROOT=docs\nPOLISH_ENABLED=1\nAUTO_ANALYZE=1\n')
        (self.root / 'docs').mkdir()
        (self.root / 'docs/a.md').write_text('# Fixture\n\n정정 fixture.\n')
        self.store = self.root / '.codex/corrections'
        self.bin = self.base / 'fake-bin'
        self.bin.mkdir()
        self.backend_log = self.base / 'fake-claude-argv.jsonl'
        fake = self.bin / 'claude'
        fake.write_text('#!' + sys.executable + '\n'
                        'import json, os, sys\n'
                        'with open(os.environ["FAKE_CLAUDE_LOG"], "a") as stream:\n'
                        '    stream.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                        'print(json.dumps({"structured_output": {"candidates": []}, '
                        '"usage": {}, "total_cost_usd": 0}))\n'
                        'sys.exit(int(os.environ.get("FAKE_CLAUDE_EXIT", "0")))\n')
        fake.chmod(0o755)
        self.env = dict(os.environ, HARNESS_RUNTIME='codex',
                        PATH=str(self.bin) + os.pathsep + os.environ.get('PATH', ''),
                        CODEX_HOME=str(self.base / 'codex-home'),
                        CLAUDE_CONFIG_DIR=str(self.base / 'claude-home'),
                        FAKE_CLAUDE_LOG=str(self.backend_log))
        for name in ('CLAUDE_PROJECT_DIR', 'CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA',
                     'PLUGIN_ROOT', 'PLUGIN_DATA', 'GEMINI_API_KEY'):
            self.env.pop(name, None)

    def run(self, script, args, expected=0, extra_env=None):
        env = dict(self.env)
        env.update(extra_env or {})
        result = subprocess.run(['/bin/bash', str(script), *args], cwd=self.root,
                                env=env, capture_output=True, text=True)
        require(result.returncode == expected,
                str(script.name) + ' exit ' + str(result.returncode) + ', 기대 ' + str(expected)
                + ': ' + (result.stdout + result.stderr)[:300])
        return result

    def session(self, lines):
        folder = self.store / 'sessions'
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / ('a' * 64 + '.jsonl')
        path.write_text('\n'.join(json.dumps(line, ensure_ascii=False) for line in lines) + '\n')
        return path

    def feedback(self, text='Codex-only correction fixture'):
        return {'type': 'harness_feedback', 'text': text, 'timestamp': '2026-11-10T00:00:00Z'}

    def call(self, mode, fields=None):
        payload = {'cwd': str(self.root), 'session_id': 'retro-fixture-session'}
        payload.update(fields or {})
        result = subprocess.run([sys.executable, '-I', str(CONTEXT), mode], cwd=self.root,
                                env=self.env, input=json.dumps(payload), capture_output=True, text=True)
        require(result.returncode == 0, '회고 훅이 작업을 차단함: ' + result.stderr[:200])
        try:
            value = json.loads(result.stdout)
        except Exception as error:
            raise AssertionError('회고 훅 출력이 JSON 하나가 아님: ' + result.stdout[:200]) from error
        require(isinstance(value, dict), '회고 훅 출력이 객체가 아님')
        return value

    def post_path(self, rel):
        command = '*** Begin Patch\n*** Update File: ' + rel + '\n@@\n-old\n+new\n*** End Patch'
        return self.call('post', {'hook_event_name': 'PostToolUse', 'tool_name': 'apply_patch',
                                 'tool_input': {'command': command}, 'tool_response': {'exit_code': 0}})

    def write_feedback(self):
        path = self.store / 'feedback/note.md'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('---\ntype: feedback\ndescription: 정정 fixture\n---\n\n정정 본문 fixture.\n')
        return path


def case(title, body):
    global passed, failed
    with tempfile.TemporaryDirectory(prefix='codex-retro-') as tmp:
        fixture = Fixture(tmp)
        try:
            body(fixture)
            passed += 1
            print('  ok    ' + title)
        except Exception as error:
            failed += 1
            print('  FAIL  ' + title + ' — ' + str(error))


def digest(f):
    path = f.session([f.feedback()])
    result = f.run(ANALYZE, ['digest', str(path)])
    value = json.loads(result.stdout)
    require('Codex-only correction fixture' in strings(value), 'Codex 정정 기록을 요약하지 않음')
    require(not (f.root / '.claude/corrections').exists(), 'Codex 요약이 Claude 회고 상태를 만듦')
    require(not f.backend_log.exists(), 'digest만 했는데 외부 분석 실행기를 호출함')


case('Codex digest이면 자체 정정 기록만 요약한다', digest)


def bad_digest(f):
    path = f.session([])
    path.write_text('{"type":"harness_feedback","text":"broken"\n')
    result = f.run(ANALYZE, ['digest', str(path)], expected=1)
    require('extract_failed' in result.stdout + result.stderr, '깨진 정정 기록의 추출 실패를 표시하지 않음')


case('Codex 정정 기록이 깨지면 추출 실패로 끝낸다', bad_digest)


def claude_transcript_not_codex(f):
    path = f.session([{'type': 'user', 'message': {'content': 'private Claude memory fixture'}}])
    result = f.run(ANALYZE, ['digest', str(path)], expected=1)
    require('extract_failed' in result.stdout + result.stderr, 'Claude transcript를 Codex 정정 기록으로 해석함')


case('Codex digest에서는 Claude 대화 형식을 정정 기록으로 재해석하지 않는다', claude_transcript_not_codex)


def run_analysis(f):
    f.session([f.feedback()])
    ledgers = f.root / 'docs/audits'
    ledgers.mkdir()
    (ledgers / 'harness-retro-codex.md').write_text('# Codex ledger\n\nCODEX_LEDGER_MARKER_84\n')
    (ledgers / 'harness-retro.md').write_text('# Claude ledger\n\nCLAUDE_LEDGER_MARKER_25\n')
    f.run(ANALYZE, ['run'])
    require((f.store / 'last-analysis').is_file(), 'Codex 분석 성공 시각을 기록하지 않음')
    require(not (f.root / '.claude/corrections').exists(), 'Codex 분석이 Claude 회고 상태를 만듦')
    require(f.backend_log.is_file(), '가짜 외부 분석 실행기를 호출하지 않음')
    calls = [json.loads(line) for line in f.backend_log.read_text().splitlines()]
    require(bool(calls), '분석 실행기 인자 기록이 없음')
    argv = next((call for call in calls if '--max-budget-usd' in call), [])
    require('--max-budget-usd' in argv and argv[argv.index('--max-budget-usd') + 1] == '1',
            '기존 분석 비용 상한 1을 전달하지 않음')
    require('--model' in argv and argv[argv.index('--model') + 1] == 'sonnet',
            '기존 분석 실행기의 기본 모델을 보존하지 않음')
    analysis_input = (f.store / 'input.md').read_text()
    require('Codex-only correction fixture' in analysis_input,
            'Codex 세션에서 추출한 기록이 분석 입력에 없음')
    require('CODEX_LEDGER_MARKER_84' in analysis_input, 'Codex 전용 회고 장부가 분석 입력에 없음')
    require('CLAUDE_LEDGER_MARKER_25' not in analysis_input, 'Claude 회고 장부가 Codex 분석 입력에 섞임')


case('Codex 분석은 자체 세션과 상태를 쓰며 기존 분석 실행기의 모델과 비용 상한을 지킨다', run_analysis)


def backend_failure(f):
    f.session([f.feedback()])
    state = f.store / 'last-analysis'
    state.write_text('2020-01-01T00:00:00Z\n')
    os.utime(state, (1, 1))
    before, modified = state.read_bytes(), state.stat().st_mtime_ns
    f.run(ANALYZE, ['run'], expected=1, extra_env={'FAKE_CLAUDE_EXIT': '1'})
    require(state.read_bytes() == before and state.stat().st_mtime_ns == modified,
            '분석 실행기 실패에도 마지막 분석 상태를 갱신함')
    require(not (f.root / '.claude/corrections').exists(), '실패한 Codex 분석이 Claude 상태를 만듦')


case('분석 실행기가 실패하면 마지막 분석 상태를 갱신하지 않는다', backend_failure)


def queue_feedback(f):
    f.write_feedback()
    f.post_path('.codex/corrections/feedback/note.md')
    queue = f.store / 'queue.tsv'
    require(queue.is_file(), 'Codex 피드백 대기열이 없음')
    lines = queue.read_text().splitlines()
    require(len(lines) == 1 and 'note.md' in lines[0], '피드백 파일을 대기열에 기록하지 않음')
    require(lines[0].split('\t')[-1] == '1', '피드백 첫 기록 횟수가 1이 아님')
    sessions = list((f.store / 'sessions').glob('*.jsonl'))
    require(len(sessions) == 1, '자체 세션 정정 기록이 없거나 중복 파일로 나뉨')
    records = [json.loads(line) for line in sessions[0].read_text().splitlines()]
    require(any(row.get('type') == 'harness_feedback' and '정정' in row.get('text', '')
                and row.get('timestamp') for row in records), '자체 정정 기록 계약이 아님')
    require(not (f.root / '.claude/corrections').exists(), 'Codex 피드백이 Claude 대기열에 섞임')


case('Codex 피드백 파일을 편집하면 자체 대기열과 정정 세션 기록을 만든다', queue_feedback)


def repeated_feedback(f):
    f.write_feedback()
    f.post_path('.codex/corrections/feedback/note.md')
    f.post_path('.codex/corrections/feedback/note.md')
    lines = (f.store / 'queue.tsv').read_text().splitlines()
    require(len(lines) == 1 and lines[0].split('\t')[-1] == '2',
            '같은 피드백 재편집이 새 대기열 행이 되거나 횟수가 늘지 않음')


case('같은 Codex 피드백을 다시 편집하면 기존 대기열의 횟수만 올린다', repeated_feedback)


def normal_document(f):
    f.post_path('docs/a.md')
    require(not (f.store / 'queue.tsv').exists(), '일반 문서를 피드백으로 수집함')
    require(not list((f.store / 'sessions').glob('*.jsonl')), '일반 문서를 자체 정정 세션에 저장함')


case('일반 문서를 편집하면 회고 피드백으로 수집하지 않는다', normal_document)


def no_claude_memory(f):
    path = f.root / '.claude/projects/private/memory/note.md'
    path.parent.mkdir(parents=True)
    path.write_text('---\ntype: feedback\ndescription: 개인 Claude 기억\n---\n\nPrivate.\n')
    f.post_path('.claude/projects/private/memory/note.md')
    require(not (f.store / 'queue.tsv').exists(), '개인 Claude 메모리를 Codex 대기열로 수집함')
    require(not list((f.store / 'sessions').glob('*.jsonl')), '개인 Claude 메모리를 Codex 세션에 저장함')


case('Claude 개인 메모리 형식의 파일은 Codex 회고로 자동 수집하지 않는다', no_claude_memory)


def notice(f):
    f.store.mkdir(parents=True)
    (f.store / 'queue.tsv').write_text('2026-11-10\ts1\ta.md\t정정 a\t1\n'
                                      '2026-11-10\ts2\tb.md\t정정 b\t1\n')
    (f.store / 'candidates.md').write_text('### 후보 한 건\n')
    result = f.call('notice', {'hook_event_name': 'SessionStart', 'source': 'startup'})
    text = strings(result)
    require(bool(result.get('systemMessage')), '회고 대기열·후보를 사용자에게 알리지 않음')
    require(re.search(r'(정정|대기|queue)[^0-9]{0,40}2', text), '자체 대기열 2건을 알리지 않음')
    require(re.search(r'(후보|candidate)[^0-9]{0,40}1', text), '자체 후보 1건을 알리지 않음')
    require(not f.backend_log.exists(), '첫 분석 전 알림이 외부 분석 실행기를 호출함')


case('첫 분석 전 세션 알림은 자체 대기열과 후보 수만 알리고 분석을 실행하지 않는다', notice)


def polish_done(f):
    f.run(POLISH, ['done', 'docs/a.md'])
    base = f.root / '.codex/polish/base/docs/a.md'
    require(base.is_file(), 'Codex 다듬기 기준판을 만들지 않음')
    require(base.read_bytes() == (f.root / 'docs/a.md').read_bytes(), '기준판이 현재 문서 내용과 다름')
    require(not (f.root / '.claude/polish').exists(), 'Codex 다듬기 기준판이 Claude 상태에 섞임')
    require(not f.backend_log.exists(), '기준판 저장이 외부 분석 실행기를 호출함')


case('Codex에서 다듬기 기준판만 저장하면 네트워크 없이 Codex 전용 상태를 쓴다', polish_done)

def notice_command_runtime(f):
    f.write_feedback()
    f.post_path('.codex/corrections/feedback/note.md')
    require((f.store / 'queue.tsv').is_file(), '첫 분석 안내를 검증할 자체 대기열이 없음')
    require(not (f.store / 'candidates.md').exists() and not (f.store / 'last-analysis').exists(),
            '첫 분석 전 fixture가 아님')
    result = f.call('notice', {'hook_event_name': 'SessionStart', 'source': 'startup'})
    require('HARNESS_RUNTIME=codex' in strings(result),
            '분석 명령 안내가 Codex 모드를 지정하지 않아 Claude 기록을 분석할 수 있음')
    require(not f.backend_log.exists(), '첫 분석 명령을 안내하면서 분석 실행기를 호출함')


case('Codex 첫 분석 안내에는 복사해도 기록이 섞이지 않도록 실행 모드를 명시한다', notice_command_runtime)

def polish_link_to_claude(f):
    claude = f.root / '.claude/polish'
    (claude / 'base/docs').mkdir(parents=True)
    (claude / 'base/docs/a.md').write_text('# Existing Claude base\n')
    (claude / 'state.txt').write_text('existing Claude state\n')
    before = {str(path.relative_to(claude)): path.read_bytes() for path in claude.rglob('*')
              if path.is_file()}
    link = f.root / '.codex/polish'
    link.parent.mkdir(parents=True)
    link.symlink_to(claude, target_is_directory=True)
    result = f.run(POLISH, ['done', 'docs/a.md'])
    require(bool((result.stdout + result.stderr).strip()), '도구별 다듬기 상태 링크 충돌을 알리지 않음')
    after = {str(path.relative_to(claude)): path.read_bytes() for path in claude.rglob('*')
             if path.is_file()}
    require(after == before, 'Codex 상태 링크를 따라 기존 Claude 기준판·상태를 변경함')
    require(link.is_symlink() and link.resolve() == claude.resolve(), '기존 상태 링크를 임의로 바꿈')


case('Codex 다듬기 상태가 Claude 상태를 가리키면 경고하고 Claude 데이터를 보존한다', polish_link_to_claude)


def analysis_link_outside(f):
    outside = f.base / 'outside-feedback.jsonl'
    outside.write_text(json.dumps(f.feedback('outside correction fixture')) + '\n')
    sessions = f.store / 'sessions'
    sessions.mkdir(parents=True)
    (sessions / 'linked.jsonl').symlink_to(outside)
    state = f.store / 'last-analysis'
    state.write_text('2020-01-01T00:00:00Z\n')
    os.utime(state, (1, 1))
    before, modified = state.read_bytes(), state.stat().st_mtime_ns
    f.run(ANALYZE, ['run'], expected=1)
    require(not f.backend_log.exists(), '외부 세션 링크의 내용을 분석 실행기에 전송함')
    require(state.read_bytes() == before and state.stat().st_mtime_ns == modified,
            '외부 세션 링크를 거절하면서 마지막 분석 상태를 갱신함')


case('Codex 세션이 외부 정정 파일의 링크면 분석 실행 전에 거절하고 성공 상태를 보존한다', analysis_link_outside)

def user_prompt_record(f):
    message = '틀렸어요, 명령이 실제로 실행되기 전에 확인해야 해요.'
    f.call('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': message})
    sessions = list((f.store / 'sessions').glob('*.jsonl'))
    require(len(sessions) == 1, '사용자 메시지를 자체 세션 하나에 기록하지 않음')
    records = [json.loads(line) for line in sessions[0].read_text().splitlines()]
    require(len(records) == 1 and records[0].get('type') == 'harness_user_message',
            '사용자 메시지를 자동으로 피드백 유형으로 분류함')
    require(records[0].get('text') == message and records[0].get('timestamp'),
            '사용자 메시지의 텍스트 또는 시각을 보존하지 않음')
    require(not (f.store / 'queue.tsv').exists(), '사용자 메시지를 정정 대기열로 자동 분류함')
    require(not (f.root / '.claude/corrections').exists(), '사용자 메시지가 Claude 회고 상태에 섞임')
    require(not f.backend_log.exists(), '사용자 메시지 기록이 외부 분석 실행기를 호출함')


case('Codex 사용자 메시지는 피드백으로 추정하지 않고 자체 세션에 원문으로 기록한다', user_prompt_record)


def user_prompt_digest(f):
    message = '이전 구현에서 중요한 조건을 놓쳤어요.'
    path = f.session([{'type': 'harness_user_message', 'text': message,
                       'timestamp': '2026-11-10T00:00:00Z'}])
    result = f.run(ANALYZE, ['digest', str(path)])
    require(message in strings(json.loads(result.stdout)), '자체 사용자 메시지 유형을 분석 입력에서 놓침')
    require(not (f.root / '.claude/corrections').exists(), '사용자 메시지 digest가 Claude 상태를 만듦')
    require(not f.backend_log.exists(), '사용자 메시지 digest만 했는데 분석 실행기를 호출함')


case('Codex digest는 자체 사용자 메시지도 읽으며 피드백 판정은 분석 단계에 맡긴다', user_prompt_digest)


def repeated_user_prompts(f):
    messages = ('첫 번째 사용자 메시지 원문.', '두 번째 사용자 메시지도 보존해 주세요.')
    for message in messages:
        f.call('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': message})
    sessions = list((f.store / 'sessions').glob('*.jsonl'))
    require(len(sessions) == 1, '같은 세션 메시지를 여러 기록 파일로 나눔')
    records = [json.loads(line) for line in sessions[0].read_text().splitlines()]
    require([row.get('text') for row in records] == list(messages),
            '같은 세션의 이전 메시지를 덮어쓰거나 현재 텍스트를 잃음')
    require(all(row.get('type') == 'harness_user_message' and row.get('timestamp') for row in records),
            '연속 사용자 메시지가 자체 기록 계약을 따르지 않음')
    require(not (f.store / 'queue.tsv').exists(), '연속 사용자 메시지를 정정 대기열로 자동 분류함')
    require(not f.backend_log.exists(), '연속 메시지 기록이 분석 실행기를 호출함')


case('같은 Codex 세션의 사용자 메시지 두 개를 한 JSONL에 순서대로 보존한다', repeated_user_prompts)

def tighten_existing_session_permissions(f):
    f.write_feedback()
    f.post_path('.codex/corrections/feedback/note.md')
    sessions = list((f.store / 'sessions').glob('*.jsonl'))
    require(len(sessions) == 1, '업그레이드 검증용 기존 세션 파일이 없음')
    session = sessions[0]
    before = session.read_bytes()
    session.chmod(0o644)
    message = '권한을 좁히면서 기존 메시지도 보존해 주세요.'
    f.call('prompt', {'hook_event_name': 'UserPromptSubmit', 'prompt': message})
    require(session.stat().st_mode & 0o777 == 0o600,
            '기존 0644 세션에 원문을 추가하면서 권한을 0600으로 좁히지 않음')
    after = session.read_bytes()
    require(after.startswith(before), '권한을 좁히는 과정에서 기존 세션 기록을 바꿈')
    records = [json.loads(line) for line in after.decode().splitlines()]
    require(records[-1].get('type') == 'harness_user_message' and records[-1].get('text') == message,
            '기존 기록을 보존하면서 새 사용자 메시지를 추가하지 못함')


case('기존 공개 범위 세션에 메시지를 추가하면 기록을 보존하며 권한을 0600으로 좁힌다', tighten_existing_session_permissions)

print('Codex 회고 연결 케이스 ' + str(passed + failed) + ' · 통과 ' + str(passed) + ' · 실패 ' + str(failed))
sys.exit(1 if failed else 0)
PY
