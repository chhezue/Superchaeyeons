#!/usr/bin/env python3
"""Codex 이벤트를 공통 정책에 연결하고 현재 프로젝트의 사용자 메시지를 기록한다."""
import fcntl
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import secrets
import shlex
import subprocess
import sys


def merge(target, value):
    if value.get('systemMessage'):
        target['systemMessage'] = '\n'.join(filter(None, (target.get('systemMessage'), value['systemMessage'])))
    context = value.get('hookSpecificOutput', {}).get('additionalContext')
    if context:
        output = target.setdefault('hookSpecificOutput', {'hookEventName': 'PostToolUse'})
        output['additionalContext'] = '\n'.join(filter(None, (output.get('additionalContext'), context)))


def exit_status(response, tool):
    # 확인한 구조화 응답과 apply_patch의 native 응답 머리만 인정한다. 진행 중은 성공이 아니다.
    if isinstance(response, dict):
        if response.get('is_error') or response.get('session_id') or response.get('sessionId'):
            return None
        value = response.get('exit_code')
        if type(value) is int:
            return value
    if tool == 'apply_patch' and isinstance(response, str):
        envelope = re.match(r'\AExit code: ([0-9]{1,3})\nWall time: [0-9.]+ seconds?\nOutput:\n', response)
        if envelope:
            return int(envelope[1])
    return None


def main():
    mode = sys.argv[1]
    data = json.load(sys.stdin)
    cwd = Path(data['cwd'])
    if not cwd.is_absolute() or not cwd.is_dir():
        raise ValueError('유효한 cwd가 필요합니다')
    result = subprocess.run(['git', '-C', str(cwd), 'rev-parse', '--show-toplevel'],
                            capture_output=True, text=True, timeout=5)
    root = Path(result.stdout.strip()).resolve() if not result.returncode else cwd.resolve()
    plugin = Path(os.environ.get('PLUGIN_ROOT') or os.environ.get('CLAUDE_PLUGIN_ROOT')
                  or Path(__file__).resolve().parent.parent).resolve()
    def own_directory(path, scan=False):
        current = root
        for part in path.relative_to(root).parts:
            current /= part
            if current.is_symlink():
                raise ValueError('도구별 상태 경로가 심볼릭 링크입니다')
        if scan and path.is_dir():
            for folder, dirs, files in os.walk(path, followlinks=False):
                if any((Path(folder) / item).is_symlink() for item in dirs + files):
                    raise ValueError('도구별 상태에 심볼릭 링크가 있습니다')
        return path

    store = own_directory(root / '.codex/harness-state')
    if not store.resolve().is_relative_to(root):
        raise ValueError('상태 경로가 프로젝트 밖입니다')
    store.mkdir(parents=True, exist_ok=True)
    # 세션·agent 문자열을 파일 경로로 사용하지 않는다.
    sid = hashlib.sha256(str(data['session_id']).encode()).hexdigest()
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root), CLAUDE_PLUGIN_ROOT=str(plugin),
               TMPDIR=str(store) + os.sep)
    normalized = dict(data, session_id=sid)
    if data.get('agent_id'):
        normalized['agent_id'] = hashlib.sha256(str(data['agent_id']).encode()).hexdigest()
    if normalized.get('agent_type') in ('researcher', 'test-writer', 'doc-reviewer'):
        normalized['agent_type'] = 'superchaeyeons:' + normalized['agent_type']

    def common(script, event):
        response = subprocess.run(['/bin/bash', str(plugin / 'hooks' / script)],
                                  input=json.dumps(event), capture_output=True, text=True,
                                  cwd=root, env=env, timeout=600)
        if response.returncode:
            raise ValueError(script + ' 실행 실패')
        return json.loads(response.stdout) if response.stdout.strip() else {}

    def append_record(kind, text):
        corrections = own_directory(root / '.codex/corrections', scan=True)
        sessions = own_directory(corrections / 'sessions')
        sessions.mkdir(parents=True, exist_ok=True, mode=0o700)
        record = own_directory(sessions / (sid + '.jsonl'))
        descriptor = os.open(record, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, 'a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            os.fchmod(stream.fileno(), 0o600)
            stream.write(json.dumps({'type': kind, 'text': text,
                'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()},
                ensure_ascii=False) + '\n')

    if mode == 'prompt':
        prompt = data.get('prompt')
        if not isinstance(prompt, str) or not prompt.strip():
            raise ValueError('사용자 메시지를 읽지 못했습니다')
        append_record('harness_user_message', prompt)
        return {}
    if mode in ('rules', 'config'):
        script = 'auto-inject-rules.sh' if mode == 'rules' else 'auto-inject-config.sh'
        return common(script, normalized)
    if mode == 'runtime':
        if normalized.get('hook_event_name') == 'SubagentStart' and normalized.get('agent_type') in (
                'superchaeyeons:researcher', 'superchaeyeons:test-writer', 'superchaeyeons:doc-reviewer'):
            return {}
        text = (plugin / 'codex/INSTRUCTIONS.md').read_text().replace('__PLUGIN_ROOT__', str(plugin))
        return {'hookSpecificOutput': {'hookEventName': data['hook_event_name'], 'additionalContext': text}}
    if mode == 'notice':
        corrections = own_directory(root / '.codex/corrections', scan=True)
        if not corrections.resolve().is_relative_to(root):
            raise ValueError('회고 상태가 프로젝트 밖입니다')
        env['HARNESS_RUNTIME'] = 'codex'
        return common('auto-correction-notice.sh', dict(normalized,
                      transcript_path=str(corrections / 'sessions' / (sid + '.jsonl'))))
    if mode not in ('pre', 'post', 'stop'):
        raise ValueError('지원하지 않는 이벤트 연결')
    conf = {}
    conf_path = root / '.claude/harness.conf'
    if conf_path.is_file():
        for line in conf_path.read_text().splitlines():
            if line and not line.startswith('#'):
                key, sep, value = line.partition('=')
                if not sep:
                    raise ValueError('공통 설정 형식 오류')
                conf[key] = value
    state_path = store / (sid + '.json')
    lock_path = store / (sid + '.lock')
    if any(p.is_symlink() for p in (state_path, lock_path)):
        raise ValueError('세션 상태가 심볼릭 링크입니다')
    out = {}
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads(state_path.read_text()) if state_path.exists() else {'edited': False, 'tested': False}
        state.setdefault('generation', 0)
        state.setdefault('pending', {})
        if mode == 'stop':
            if data.get('stop_hook_active'):
                return {}
            message = data.get('last_assistant_message')
            if not isinstance(message, str):
                raise ValueError('Stop 완료 문구를 읽지 못했습니다')
            claim = runpy.run_path(str(plugin / 'scripts/completion-policy.py'))['CLAIM']
            configured = conf.get('TEST_CMD', '')
            if state['edited'] and not state['tested'] and configured and not configured.startswith(('(없음)', '{')) and claim.search(message):
                return {'decision': 'block', 'reason': '마지막 코드 편집 뒤 전체 테스트 성공을 확인하지 못했습니다. ' + configured + '를 실행하고 결과를 확인하세요.'}
            return {}
        tool = data.get('tool_name')
        command = data.get('tool_input', {}).get('command')
        if not isinstance(command, str):
            raise ValueError('도구 명령을 읽지 못했습니다')
        status = exit_status(data.get('tool_response'), tool)
        if mode == 'pre':
            if tool == 'Bash':
                policy = runpy.run_path(str(plugin / 'scripts/completion-policy.py'),
                                       init_globals={'test_words': conf.get('TEST_CMD', '').split()})
                stripped = policy['strip_heredocs'](command)
                mask = policy['data_mask'](stripped)
                if policy['last_test_run'](stripped, mask) >= 0:
                    tool_id = data.get('tool_use_id')
                    if not isinstance(tool_id, str) or not tool_id:
                        raise ValueError('전체 테스트 시작 ID를 읽지 못했습니다')
                    pending = {'generation': state['generation'], 'command': command}
                    state['pending'][tool_id] = pending
                    configured = conf.get('TEST_CMD', '').strip()
                    if configured and command.strip() == configured:
                        # native Bash는 stdout만 전달한다. 단독 전체 테스트의 실제 종료 코드를
                        # 별도 셸에서 받은 뒤 호출별 표식으로 돌려받는다. 출력의 OK를 추측하지 않는다.
                        nonce = secrets.token_hex(16)
                        reporter = ('import json,os,sys; print("\\n__HARNESS_TEST_' + nonce
                            + '__:" + json.dumps({"exit_code": int(sys.argv[1]), "cwd": os.getcwd()}))')
                        wrapped = ('/bin/bash -c ' + shlex.quote(command)
                            + '; harness_test_status=$?; python3 -I -c ' + shlex.quote(reporter)
                            + ' "$harness_test_status"; exit "$harness_test_status"')
                        pending.update(nonce=nonce, wrapped=wrapped)
                        out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                            'permissionDecision': 'allow', 'updatedInput': dict(data['tool_input'], command=wrapped)}}
            state_path.write_text(json.dumps(state))
            return out
        if tool == 'apply_patch':
            paths = runpy.run_path(str(plugin / 'hooks/deny-codex-tool.py'))['patch_paths'](command)
            docs = runpy.run_path(str(plugin / 'scripts/completion-policy.py'))['DOC_EXT']
            absolute = [(cwd / p).resolve() for p in paths]
            if not all(p.resolve().is_relative_to(root) for p in absolute):
                raise ValueError('후처리 대상이 프로젝트 밖입니다')
            if status != 1 and any(p.suffix not in docs for p in absolute):
                state['edited'], state['tested'] = True, False
                state['generation'] += 1
            if status == 0:
                for path in dict.fromkeys(absolute):
                    event = dict(normalized, tool_input={'file_path': str(path)})
                    merge(out, common('auto-inject-path-rules.sh', event))
                    if path.exists():
                        merge(out, common('auto-format.sh', event))
                        feedback = root / '.codex/corrections/feedback'
                        if path.suffix == '.md' and path.is_relative_to(feedback):
                            text = path.read_text()
                            front, sep, body = text[4:].partition('\n---\n') if text.startswith('---\n') else ('', '', '')
                            kind = next((line.split(':', 1)[1].strip() for line in front.splitlines()
                                         if line.strip().startswith('type:')), '')
                            if sep and kind == 'feedback':
                                corrections = own_directory(root / '.codex/corrections', scan=True)
                                if not corrections.resolve().is_relative_to(root):
                                    raise ValueError('회고 상태가 프로젝트 밖입니다')
                                env['HARNESS_RUNTIME'] = 'codex'
                                merge(out, common('auto-correction-queue.sh', event))
                                description = next((line.split(':', 1)[1].strip() for line in front.splitlines()
                                                    if line.startswith('description:')), '')
                                append_record('harness_feedback', description + '\n' + body)
            elif status is None:
                merge(out, {'systemMessage': 'Codex 편집 결과 형식을 확인하지 못했습니다. 후처리와 검증은 직접 확인하세요.'})
        elif tool == 'Bash':
            tool_id = data.get('tool_use_id')
            pending = state['pending'].get(tool_id) if isinstance(tool_id, str) else None
            response = data.get('tool_response')
            text = response if isinstance(response, str) else response.get('output', '') if isinstance(response, dict) else ''
            started = pending if type(pending) is int else None
            if isinstance(pending, dict) and command in (pending.get('command'), pending.get('wrapped')):
                started = pending['generation']
                command = pending['command']
                nonce = pending.get('nonce')
                if status is None and nonce and isinstance(response, str):
                    proof = re.search(r'\n__HARNESS_TEST_' + re.escape(nonce) + r'__:(\{[^\n]+\})\n?\Z', response)
                    if proof:
                        try:
                            receipt = json.loads(proof[1])
                            if (type(receipt.get('exit_code')) is int
                                    and isinstance(receipt.get('cwd'), str)
                                    and Path(receipt['cwd']).is_absolute()
                                    and Path(receipt['cwd']).resolve() == root):
                                status = receipt['exit_code']
                                text = response[:proof.start()]
                        except (ValueError, OSError):
                            pass
            policy = runpy.run_path(str(plugin / 'scripts/completion-policy.py'),
                                   init_globals={'test_words': conf.get('TEST_CMD', '').split()})
            stripped = policy['strip_heredocs'](command)
            mask = policy['data_mask'](stripped)
            edit_at = policy['last_code_edit'](stripped, mask)
            test_at = policy['last_test_run'](stripped, mask)
            before_generation = state['generation']
            if edit_at >= 0:
                state['edited'], state['tested'] = True, False
                state['generation'] += 1
            if test_at >= 0 and test_at > edit_at:
                failed = isinstance(text, str) and policy['FAILED'].search(text)
                state['tested'] = status == 0 and not failed and started == before_generation
                if status is not None:
                    state['pending'].pop(tool_id, None)
                if status is None or started is None:
                    merge(out, {'systemMessage': '전체 테스트가 실행 중이거나 시작·결과 증거를 확인하지 못했습니다. 성공으로 기록하지 않습니다.'})
        # 저장 중 중단돼도 다음 호출에서 반쪽 JSON을 읽지 않게 같은 폴더에서 교체한다.
        temp = state_path.with_suffix('.tmp')
        if temp.is_symlink():
            raise ValueError('임시 상태가 심볼릭 링크입니다')
        temp.write_text(json.dumps(state))
        os.replace(temp, state_path)
    return out


if __name__ == '__main__':
    try:
        output = main()
    except Exception as error:
        output = {'systemMessage': 'Codex 세션 연결 경고 — ' + str(error).replace('\n', ' ')}
    print(json.dumps(output, ensure_ascii=False))
