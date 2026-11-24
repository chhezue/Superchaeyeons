"""독립 문서 작성 시험. prepare DIR 후 work-a … work-e에서 각각 TASK.md를 수행한다.

작성자의 최종 응답은 각 저장소 밖 DIR/work-X.response.txt에 저장한다.
verify DIR은 문서와 오류 보고를 읽는다. 모형 문서를 생성하거나 모델을 호출하지 않는다.
"""
import os
from pathlib import Path
import re
import subprocess
import sys

SPEC = 'docs/specs/retry-delay.md'
AUDIT = 'docs/audits/retry-policy.md'
KINDS = ('스펙 양식', '감사 체크리스트', '감사 결과 양식')
FILES = ('spec.md', 'checks.md', 'audit.md')
SPEC_HEAD = {'team': '운영 인계', 'desk': '배포 기록'}
AUDIT_HEAD = {'team': '당직 전달', 'desk': '운영 기록'}

TASK = f"""pay-relay의 결제 알림 재시도 정책을 검토해 주세요. 산출물은 한국어로 작성해 주세요.

1. write-spec으로 대기 시간 상한만 18초에서 24초로 올리는 Draft 스펙을 `{SPEC}`에 작성해 주세요.
   호출자 이름은 pay-relay입니다. 현재 3초씩 증가하는 규칙과 시도 횟수 제한은 유지해야 합니다.
2. refactor-safely의 감사 단계로 `retry_policy.py`와 현재 계약을 대조해 `{AUDIT}`에 기록해 주세요.
   아직 승인되지 않은 상한 변경은 현재 계약과 구분해 주세요. 확인한 함수와 경곗값을 근거로 남겨 주세요.

두 문서 작성은 각각 요청합니다. 진행할 수 없는 작업이 있으면 원인과 해당 경로를 최종 응답에 적어 주세요.
코드 수정이나 구현 승인은 요청 범위 밖입니다.
"""
CONTRACT = """# 현재 운영 계약

pay-relay가 사용하는 시도 번호는 1부터 시작한다. 응답 대기 시간은 시도 번호당 3초이며 최대 18초다.
6번째 시도를 마친 시점에는 다음 재시도를 예약할 수 없다.
"""
SOURCE = """def delay_seconds(attempt):
    return min(attempt * 3, 18)


def should_retry(attempt):
    return attempt <= 6
"""


def put(root, rel, content):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


def git(root, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    return subprocess.check_output(['git', *args], cwd=root,
                                   env=dict(env, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1'))


def forms(root, owner, indices):
    prefix = owner.upper()
    texts = (
        f'# 변경 요청\n\n## {SPEC_HEAD[owner]}\n호출자 식별자와 요청받은 상한을 기록한다.\n',
        f'# 당직 점검\n\n- {prefix}-LIMIT · 마지막 시도 뒤 추가 예약이 운영 계약과 맞는가?\n'
        f'- {prefix}-CAP · 충분히 큰 시도 번호에서 기존 대기 상한이 지켜지는가?\n\n'
        '각 점검은 한 행에 점검 ID, OK 또는 FIX, 소스 함수와 확인한 경곗값을 기록한다.\n',
        f'# 운영 검토\n\n## {AUDIT_HEAD[owner]}\n호출자 식별자와 확인된 현행 경계 동작을 기록한다.\n',
    )
    for index in indices:
        put(root, f'forms/{owner}/{FILES[index]}', texts[index])


def links(owner, indices, prefix=''):
    return ''.join(f'- {KINDS[i]} [{FILES[i]}]({prefix}forms/{owner}/{FILES[i]})\n' for i in indices)


def prepare(base):
    base.mkdir()
    for case in 'abcde':
        root = base / ('work-' + case)
        root.mkdir()
        git(root, 'init', '-q', '--template=')
        put(root, 'TASK.md', TASK)
        put(root, 'README.md', CONTRACT)
        put(root, 'retry_policy.py', SOURCE)
        instructions = '# 저장소 지침\n\n운영 계약은 [README](README.md)에 기록한다.\n'
        if case in 'abd':
            selected = (1,) if case == 'b' else range(3)
            forms(root, 'desk', selected)
            put(root, 'docs/forms-index.md', '# 문서 등록부\n\n' + links('desk', selected, '../'))
            instructions += '팀 문서의 양식은 [문서 등록부](docs/forms-index.md)에서 확인한다.\n'
        if case == 'a':
            forms(root, 'team', range(3))
            instructions += links('team', range(3))
        if case == 'd':
            instructions += '- 스펙 양식 [변경 요청](forms/retired-spec.md)\n'
        if case == 'e':
            forms(root, 'team', range(3))
            forms(root, 'desk', (1,))
            instructions += links('team', range(3)) + links('desk', (1,))
        put(root, 'AGENTS.md', instructions)
        git(root, 'add', '.')
        git(root, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
            'commit', '-qm', 'Document input')
    print(f'{base} · 각 work-*에서 TASK.md 수행 · 응답은 형제 경로 work-*.response.txt에 저장')


def require(condition, reason):
    if not condition:
        raise AssertionError(reason)


def section(document, title):
    match = re.search(r'^#{1,6}\s+' + re.escape(title) + r'[^\n]*\n(.*?)(?=^#{1,6}\s|\Z)',
                      document, re.MULTILINE | re.DOTALL)
    require(match, '양식 고유 절 누락 · ' + title)
    return match.group(1)


def contains(text, *values):
    for value in values:
        require(value in text, '내용 누락 · ' + value)


def check_spec(text, owner):
    require(re.search(r'^>\s*상태:\s*Draft\b', text, re.MULTILINE), 'Draft 승인 상태 줄 누락')
    contains(text, '불변', '완료', '테스트 먼저', '24', 'pay-relay')
    if owner:
        contains(section(text, SPEC_HEAD[owner]), 'pay-relay', '24')
    else:
        contains(text, '요구사항', '검증 시나리오')
    for other, title in SPEC_HEAD.items():
        require(other == owner or title not in text, '선택되지 않은 스펙 양식 사용 · ' + title)


def check_audit(text, checks_owner, form_owner):
    contains(text, 'should_retry', '6', '불변', '승인', '구현 결과')
    for category in 'ABCD':
        require(re.search(r'\b' + category + r'\b', text), '감사 분류 누락 · ' + category)
    if form_owner:
        handoff = section(text, AUDIT_HEAD[form_owner])
        contains(handoff, 'pay-relay')
        require('6' in handoff or '18' in handoff, '당직 전달에 확인한 경곗값이 없음')
    else:
        contains(text, '범위', '승인 대기')
    if checks_owner:
        for check_id, verdict, function, boundary in [('LIMIT', 'FIX', 'should_retry', '6'),
                                                       ('CAP', 'OK', 'delay_seconds', '18')]:
            item = checks_owner.upper() + '-' + check_id
            rows = [line for line in text.splitlines() if item in line]
            require(any(all(part in row for part in (verdict, function, boundary)) for row in rows),
                    '체크 항목별 판정·함수·경곗값 누락 · ' + item)
    else:
        require('중복' in text and '테스트' in text, '기본 체크리스트의 중복·테스트 점검 누락')
    for other, title in AUDIT_HEAD.items():
        require(other == form_owner or title not in text, '선택되지 않은 감사 양식 사용 · ' + title)
        require(other == checks_owner or other.upper() + '-LIMIT' not in text,
                '선택되지 않은 체크리스트 사용 · ' + other)


def verify(base):
    failures = []
    for case in 'abcde':
        root = base / ('work-' + case)
        try:
            original = set(git(root, 'ls-tree', '-r', '--name-only', 'HEAD').decode().splitlines())
            changed = set(git(root, 'diff', '--name-only', 'HEAD').decode().splitlines())
            require(not original.intersection(changed), '기존 입력·코드를 변경함')
            paths = changed | set(git(root, 'ls-files', '--others', '--exclude-standard').decode().splitlines())
            wanted = {SPEC, AUDIT} - ({SPEC} if case == 'd' else {AUDIT} if case == 'e' else set())
            require(paths == wanted, f'요청한 문서와 생성 경로 차이 · {sorted(paths ^ wanted)}')
            if SPEC in wanted:
                check_spec((root / SPEC).read_text(), 'team' if case in 'ae' else None)
            if AUDIT in wanted:
                checks = {'a': 'team', 'b': 'desk', 'd': 'desk'}.get(case)
                form = {'a': 'team', 'd': 'desk'}.get(case)
                check_audit((root / AUDIT).read_text(), checks, form)
            if case in 'de':
                response = (base / f'work-{case}.response.txt').read_text()
                if case == 'd':
                    contains(response, 'forms/retired-spec.md')
                else:
                    contains(response, 'forms/team/checks.md', 'forms/desk/checks.md')
            print(f'{root.name} · 문서와 경로 대조 통과')
        except (AssertionError, OSError, subprocess.CalledProcessError) as error:
            failures.append(f'{root.name} · {error}')
    if failures:
        sys.exit('\n'.join(failures))


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('prepare', 'verify'):
        sys.exit('사용: test-project-templates.py prepare 새_디렉터리 | verify 작성_디렉터리')
    action, directory = sys.argv[1:]
    (prepare if action == 'prepare' else verify)(Path(directory).resolve())
