#!/usr/bin/env python3
"""Codex 실행 전 승인 사전 검사. 대상 작업을 실행하거나 승인 표식을 만들지 않는다."""
import json
import os
from pathlib import Path
import subprocess
import sys


def report(decision, reason):
    print(json.dumps({'decision': decision, 'reason': reason}, ensure_ascii=False))
    return {'allow': 0, 'confirm': 3, 'deny': 2}[decision]


def main():
    plugin = Path(os.environ.get('PLUGIN_ROOT') or os.environ.get('CLAUDE_PLUGIN_ROOT')
                  or Path(__file__).resolve().parent.parent).resolve()
    project = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.getcwd()).resolve()
    data = json.load(sys.stdin)
    if data.get('tool_name') not in ('Bash', 'Write', 'Edit', 'MultiEdit', 'NotebookEdit'):
        raise ValueError('지원하는 공통 입력으로 제안 내용을 전달해야 합니다')
    tool, ti = data['tool_name'], data.get('tool_input')
    if not isinstance(ti, dict):
        raise ValueError('tool_input 객체가 필요합니다')
    if tool == 'Bash':
        if not isinstance(ti.get('command'), str) or not ti['command'].strip():
            raise ValueError('제안 명령이 필요합니다')
    else:
        path = ti.get('file_path') or ti.get('notebook_path')
        if not isinstance(path, str) or not path:
            raise ValueError('제안 파일 경로가 필요합니다')
        if tool == 'Write' and not isinstance(ti.get('content'), str):
            raise ValueError('변경 후 전체 파일 내용이 필요합니다')
        if tool == 'Edit' and not all(isinstance(ti.get(k), str) for k in ('old_string', 'new_string')):
            raise ValueError('변경 전후 문자열이 필요합니다')
        if tool == 'MultiEdit' and (not isinstance(ti.get('edits'), list) or not ti['edits']
                or not all(isinstance(e, dict) and all(isinstance(e.get(k), str)
                           for k in ('old_string', 'new_string')) for e in ti['edits'])):
            raise ValueError('모든 편집의 변경 전후 문자열이 필요합니다')
        if tool == 'NotebookEdit':
            raise ValueError('노트북 변경 내용은 명시적으로 확인해야 합니다')
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(project), CLAUDE_PLUGIN_ROOT=str(plugin))
    result = subprocess.run(['/bin/bash', str(plugin / 'hooks/ask-approval.sh')],
                            input=json.dumps(data), capture_output=True, text=True,
                            cwd=project, env=env, timeout=600)
    if result.returncode:
        raise ValueError('공통 승인 판정 실행 실패')
    if not result.stdout.strip():
        return report('allow', '')
    value = json.loads(result.stdout)['hookSpecificOutput']
    decision = value['permissionDecision']
    if decision not in ('allow', 'ask', 'deny'):
        raise ValueError('알 수 없는 공통 승인 판정')
    return report({'allow': 'allow', 'ask': 'confirm', 'deny': 'deny'}[decision],
                  value.get('permissionDecisionReason', ''))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        sys.exit(report('confirm', '판정 불가 — ' + str(error).replace('\n', ' ')))
