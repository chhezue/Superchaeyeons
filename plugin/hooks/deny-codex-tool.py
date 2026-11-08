#!/usr/bin/env python3
"""Codex 명령·패치 입력을 공통 Claude 판정기에 전달한다. 등록 명령이 오류를 exit 2로 바꾼다."""
import json
import os
from pathlib import Path
import subprocess
import sys


def patch_paths(command):
    """전체 패치를 먼저 읽어 삭제·이동 양쪽을 포함한 경로를 돌려준다."""
    lines = command.splitlines()
    if not lines or lines[0] != '*** Begin Patch' or lines[-1] != '*** End Patch':
        raise ValueError('패치 시작·끝 표식이 잘못됐습니다')
    paths, index = [], 1
    end = len(lines) - 1
    while index < end:
        header = lines[index]
        kind = next((k for k in ('Add', 'Update', 'Delete')
                     if header.startswith('*** ' + k + ' File: ')), None)
        if kind is None:
            raise ValueError('알 수 없는 패치 헤더입니다')
        path = header[len('*** ' + kind + ' File: '):]
        if not path.strip() or path != path.strip() or '\x00' in path:
            raise ValueError('패치 경로가 비어 있거나 잘못됐습니다')
        paths.append(path)
        index += 1
        if kind == 'Delete':
            continue
        if kind == 'Update' and index < end and lines[index].startswith('*** Move to: '):
            target = lines[index][len('*** Move to: '):]
            if not target.strip() or target != target.strip() or '\x00' in target:
                raise ValueError('이동 대상이 잘못됐습니다')
            paths.append(target)
            index += 1
        count, section = 0, False
        while index < end and not lines[index].startswith(('*** Add File: ', '*** Update File: ', '*** Delete File: ')):
            line = lines[index]
            if kind == 'Add':
                if not line.startswith('+'):
                    raise ValueError('추가 파일 본문이 잘못됐습니다')
            elif line == '@@' or line.startswith('@@ '):
                section = True
                index += 1
                continue
            elif line == '*** End of File':
                if not section or not count:
                    raise ValueError('파일 끝 표식이 잘못됐습니다')
                index += 1
                break
            elif not section or not line.startswith((' ', '+', '-')):
                raise ValueError('수정 파일 본문이 잘못됐습니다')
            count += 1
            index += 1
        if not count:
            raise ValueError('패치 본문이 비어 있습니다')
    if not paths:
        raise ValueError('패치 작업이 없습니다')
    return paths


def judge(script, payload, root, env, plugin):
    """기존 정책의 판정·이유를 유지하며 예상 밖 오류도 차단한다."""
    result = subprocess.run(['/bin/bash', str(plugin / 'hooks' / script)],
                            input=json.dumps(payload), text=True, capture_output=True,
                            cwd=root, env=env, timeout=30)
    if result.returncode:
        raise ValueError(result.stderr.strip() or '공통 판정기를 실행하지 못했습니다')


def main():
    data = json.load(sys.stdin)
    cwd = Path(data['cwd'])
    if not cwd.is_absolute() or not cwd.is_dir():
        raise ValueError('작업 디렉터리가 잘못됐습니다')
    command = data['tool_input']['command']
    if not isinstance(command, str) or not command.strip() or '\x00' in command:
        raise ValueError('command가 없거나 잘못됐습니다')
    tool = data['tool_name']
    if tool not in ('Bash', 'apply_patch'):
        raise ValueError('지원하지 않는 도구 입력입니다')
    git = subprocess.run(['git', '-C', str(cwd), 'rev-parse', '--show-toplevel'],
                         text=True, capture_output=True, timeout=5)
    root = Path(git.stdout.strip()).resolve() if git.returncode == 0 else cwd.resolve()
    plugin = Path(os.environ.get('PLUGIN_ROOT') or os.environ.get('CLAUDE_PLUGIN_ROOT')
                  or Path(__file__).resolve().parent.parent).resolve()
    env = dict(os.environ)
    env['CLAUDE_PROJECT_DIR'] = str(root)
    env['CLAUDE_PLUGIN_ROOT'] = str(plugin)
    if tool == 'Bash':
        judge('deny-dangerous-bash.sh', data, root, env, plugin)
        return
    # Codex 상대 경로는 도구의 cwd 기준이다. 공통 판정에는 절대 경로를 넘긴다.
    paths = []
    for raw in patch_paths(command):
        path = Path(raw)
        absolute = (cwd / path).absolute() if not path.is_absolute() else path
        real = absolute.resolve()
        if not real.is_relative_to(root):
            raise ValueError('저장소 밖 패치 경로입니다')
        paths.append(str(absolute))
    for path in paths:
        judge('deny-out-of-scope-write.sh', {'tool_input': {'file_path': path}}, root, env, plugin)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Codex 차단: ' + str(error).replace('\n', ' ').replace('\r', ' '), file=sys.stderr)
        sys.exit(2)
