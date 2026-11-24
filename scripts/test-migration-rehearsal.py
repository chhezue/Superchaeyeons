"""Codex 이전 픽스처. 인자 없이 실행하면 실제 조사 스크립트의 계약을 검사한다.

prepare <새 디렉터리>로 수용 시험 저장소를 만든다. 실제 이전안에서 OLD → NEW
한 건과 이에 따르는 참조 변경만 승인하고, verify <디렉터리>로 결과를 대조한다.
출처 판정의 근거, 사람이 커밋할 때 쓰는 훅의 처리, 승인 표의 각 열,
기존 훅 충돌에 대한 설명, 재제안 때 같은 이동이 없는지는 실제 제안으로 검수한다.
"""
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

PROBE = Path(__file__).resolve().parents[1] / 'plugin/scripts/init-harness-probe.sh'
OLD = '.claude/skills/local-release/assets/spec.md'
NEW = 'docs/templates/spec.md'
HOOKS = 'team-git-hooks'
HOOK_SOURCE = '.claude/hooks/team-pre-commit.sh'
MANUAL_HOOK = '.claude/hooks/check-message.sh'
UNKNOWN = '.claude/rules/core-undated.md'
GUIDE = 'docs/release-guide.md'
REFERENCES = {
    'AGENTS.md': '릴리스 문서는 {} 양식을 따른다.\n',
    'scripts/release-notes.sh': '#!/bin/sh\n# Generate the release notes from {}\n',
    '.github/PULL_REQUEST_TEMPLATE/release.md': '<!-- 릴리스 양식 {} -->\n',
    GUIDE: '[릴리스 양식]({})\n',
}
RULE = 'docs/policy.md'
TEMPLATE = '# 팀 스펙\n\n[팀 규칙]({})\n'
ACTIVE_HOOK = '''#!/bin/sh
set -eu
git stash push --quiet --keep-index -m fixture-unstaged
case "${FIXTURE_FORMAT_MODE:?}" in
    failure) git stash pop --quiet && exit 17 ;;
    rewrite) sed 's/format=staged/format=formatted/' partial.txt > partial.tmp
             mv partial.tmp partial.txt
             git add -- partial.txt ;;
esac
git stash pop --quiet
'''
BASE = 'format=base\n' + 'separate line\n' * 12 + 'note=base\n'
STAGED = BASE.replace('format=base', 'format=staged')
UNSTAGED = STAGED.replace('note=base', 'note=unstaged')


def check(condition, reason):
    if not condition:
        raise AssertionError(reason)


def run(root, *args, check_exit=True, **env):
    # 외부 Git 설정이나 현재 저장소의 Git 훅 환경 변수가 픽스처로 전달되지 않게 한다.
    isolated = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    isolated.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1', **env)
    result = subprocess.run(args, cwd=root, env=isolated, capture_output=True)
    if check_exit and result.returncode:
        raise AssertionError(f'{args!r}: {result.stderr.decode(errors="replace")}')
    return result


def git(root, *args):
    return run(root, 'git', *args).stdout


def write(root, rel, text):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def init_git(root):
    git(root, 'init', '--quiet', '--template=')
    git(root, 'config', 'user.name', 'Rehearsal')
    git(root, 'config', 'user.email', 'fixture@example.invalid')


def prepare(root):
    root.mkdir()
    init_git(root)
    write(root, RULE, '릴리스 규칙\n')
    write(root, OLD, TEMPLATE.format('../../../../' + RULE))
    for rel, template in REFERENCES.items():
        write(root, rel, template.format('../' + OLD if rel == GUIDE else OLD))
    write(root, HOOK_SOURCE, '#!/bin/sh\nexit 0\n').chmod(0o755)
    write(root, MANUAL_HOOK, '#!/bin/sh\ntest -s "$1"\n').chmod(0o755)
    hooks = root / HOOKS
    hooks.mkdir()
    for name, source in [('pre-commit', HOOK_SOURCE), ('commit-msg', MANUAL_HOOK)]:
        (hooks / name).symlink_to('../' + source)
    write(root, 'partial.txt', BASE)
    write(root, 'other.txt', 'old\n')
    git(root, 'add', '.')
    git(root, 'commit', '-qm', 'Install fixture harness originals')
    git(root, 'tag', 'fixture-install')
    git(root, 'config', 'core.hooksPath', HOOKS)
    write(root, HOOK_SOURCE, ACTIVE_HOOK)
    write(root, UNKNOWN, '팀이 보관 중인 기록. 출처 미확인.\n')
    write(root, 'partial.txt', STAGED)
    git(root, 'add', '--', 'partial.txt')
    write(root, 'partial.txt', UNSTAGED)
    write(root, 'other.txt', 'unsaved working change\n')


def tree(root):
    files = {}
    for path in root.rglob('*'):
        rel = path.relative_to(root)
        if rel.parts[0] == '.git':
            continue
        if path.is_symlink():
            files[str(rel)] = ('link', os.readlink(path))
        elif path.is_file():
            files[str(rel)] = (stat.S_IMODE(path.stat().st_mode), path.read_bytes())
    return files


def probe(root, migration):
    args = [str(PROBE), str(root), '.']
    if migration:
        args.append('--migration')
    before = tree(root), (root / '.git/index').read_bytes(), (root / '.git/config').read_bytes()
    output = run(root, *args).stdout.decode()
    after = tree(root), (root / '.git/index').read_bytes(), (root / '.git/config').read_bytes()
    check(after == before, '조사가 작업 파일·실행 권한·링크·인덱스·Git 설정을 바꿈')
    return output


def test_probe(root):
    prepare(root)
    report = probe(root, True)
    for rel in [HOOK_SOURCE, MANUAL_HOOK, UNKNOWN, OLD, HOOKS + '/pre-commit', *REFERENCES]:
        check(rel in report, '이전 조사에서 경로 누락: ' + rel)
    # 파일명이 단순 목록에 우연히 나온 경우와 실제 옛 경로 참조를 구분한다.
    for rel, template in REFERENCES.items():
        write(root, rel, template.format('no-template-configured'))
    without_references = probe(root, True)
    removed_rows = set(report.splitlines()) - set(without_references.splitlines())
    for rel in REFERENCES:
        check(any(rel in line for line in removed_rows), '일반 텍스트·링크·주석에서 참조 누락: ' + rel)
    normal = probe(root, False)
    check(UNKNOWN not in normal and HOOKS + '/pre-commit' not in normal,
          '기본 실측에 복사본 이전 점검을 추가함')
    external = root.parent / 'installed team hooks'
    external.mkdir()
    installed = write(external, 'pre-commit', '#!/bin/sh\nexec ' + MANUAL_HOOK + ' "$@"\n')
    installed.chmod(0o755)
    git(root, 'config', 'core.hooksPath', str(external))
    check(any(str(installed) in line and MANUAL_HOOK in line for line in probe(root, True).splitlines()),
          '저장소 밖에 실제 설치된 Git 훅의 본문 참조 누락')


def hook_result(project, root, mode):
    # 각 실행은 독립된 Git 저장소에서 시작한다. 충돌·stash를 실제 수용 시험 저장소에 남기지 않는다.
    shutil.copytree(project, root, symlinks=True, ignore=shutil.ignore_patterns('.git'))
    init_git(root)
    write(root, 'partial.txt', BASE)
    write(root, 'other.txt', 'old\n')
    git(root, 'add', '.')
    git(root, 'commit', '-qm', 'Isolated hook rehearsal')
    hooks = git(project, 'config', '--get', 'core.hooksPath').decode().strip()
    git(root, 'config', 'core.hooksPath', hooks)
    write(root, 'partial.txt', STAGED)
    git(root, 'add', '--', 'partial.txt')
    write(root, 'partial.txt', UNSTAGED)
    write(root, 'other.txt', 'unstaged\n')
    result = run(root, 'git', 'hook', 'run', 'pre-commit', check_exit=False, FIXTURE_FORMAT_MODE=mode)
    return (result.returncode, git(root, 'ls-files', '--stage', '--', 'partial.txt', 'other.txt'),
            git(root, 'ls-files', '--unmerged'), (root / 'partial.txt').read_bytes(),
            (root / 'other.txt').read_bytes(), git(root, 'stash', 'list', '--format=%gs'))


def verify_approved_move(project, tmp):
    original = tmp / 'original'
    prepare(original)
    expected = tree(original)
    mode, _ = expected.pop(OLD)

    def reference_bytes(rel, template, base, destination):
        # 상대 경로의 표기는 여러 가지일 수 있다. 같은 문맥에서 승인한 파일이 열리는지 확인한다.
        content = (project / rel).read_bytes()
        prefix, suffix = (s.encode() for s in template.split('{}'))
        check(content.startswith(prefix) and content.endswith(suffix), '참조 바깥 문구가 바뀜: ' + rel)
        path = Path(content[len(prefix):-len(suffix)].decode())
        check(not path.is_absolute() and (base / path).resolve(strict=True) == project / destination,
              '승인한 경로로 연결되지 않음: ' + rel)
        return content

    expected[NEW] = (mode, reference_bytes(NEW, TEMPLATE, (project / NEW).parent, RULE))
    for rel, template in REFERENCES.items():
        base = (project / rel).parent if rel == GUIDE else project
        expected[rel] = (expected[rel][0], reference_bytes(rel, template, base, NEW))
    actual = tree(project)
    differences = sorted(rel for rel in set(expected) | set(actual) if expected.get(rel) != actual.get(rel))
    check(not differences, '승인한 이동·참조 이외의 차이 또는 참조 누락: ' + ', '.join(differences))
    check(git(original, 'ls-files', '--stage') == git(project, 'ls-files', '--stage'), '인덱스가 바뀜')
    for mode in ['success', 'failure', 'rewrite']:
        before = hook_result(original, tmp / ('before-' + mode), mode)
        after = hook_result(project, tmp / ('after-' + mode), mode)
        if mode == 'rewrite':
            check(before[0] != 0 and before[2] and before[5], '기존 훅 충돌과 남은 stash 재현 실패')
        else:
            expected_exit = 0 if mode == 'success' else 17
            check(before[0] == expected_exit and not before[2] and not before[5], '기존 훅 동작 재현 실패: ' + mode)
        check(before == after, '이전 뒤 훅 종료 코드·인덱스·충돌·작업 파일·stash가 달라짐: ' + mode)
        print(f'{mode} 전후 일치 · exit {before[0]} · 충돌 {bool(before[2])} · stash {bool(before[5])}')
    probe(project, True)


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='migration-rehearsal-') as directory:
        tmp = Path(directory)
        if len(sys.argv) == 1:
            test_probe(tmp / 'project with spaces')
            print('이전 조사 · 읽기 전용과 경로 참조 검증 통과')
        elif len(sys.argv) == 3 and sys.argv[1] == 'prepare':
            project = Path(sys.argv[2]).resolve()
            prepare(project)
            print(f'{project} · 승인 대상 {OLD} → {NEW}')
        elif len(sys.argv) == 3 and sys.argv[1] == 'verify':
            verify_approved_move(Path(sys.argv[2]).resolve(), tmp)
        else:
            sys.exit('사용: test-migration-rehearsal.py [prepare 새_저장소 | verify 적용한_저장소]')
