#!/usr/bin/env bash
# init-harness의 설치 설정 작성 계약 — 임시 프로젝트만 대상으로 변경안과 적용 결과를 검증한다.
# 사용: scripts/test-harness-config.sh
# exit 0 = 전부 통과 · exit 1 = 실패 · exit 2 = 테스트 환경 오류
# 근거: 공동 지원 스펙 M8 초기화 계약. 실제 플러그인 설치·신뢰·전역 설정 변경은 하지 않는다.
set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo 'FAIL: python3 없음' >&2; exit 2; }
python3 -I - "$repo_root" <<'PY'
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

REPO = Path(sys.argv[1])
CONFIGURE = REPO / 'plugin/scripts/configure-harness.py'
ROLES = ('researcher', 'test-writer', 'doc-reviewer')
COMMON_FILES = ('.claude/harness.conf', 'scripts/dev.conf')
CODEX_FILES = ('.codex/config.toml', '.codex/rules/harness.rules',
               *('.codex/agents/' + role + '.toml' for role in ROLES))
passed = failed = 0


def require(value, reason):
    if not value:
        raise AssertionError(reason)


def snapshot(root):
    return {str(path.relative_to(root)): path.read_bytes()
            for path in root.rglob('*') if path.is_file() and not path.is_symlink()}


def role_source(role):
    text = (REPO / 'plugin/agents' / (role + '.md')).read_text()
    require(text.startswith('---\n'), '공통 역할 frontmatter 없음: ' + role)
    frontmatter, delimiter, body = text[4:].partition('\n---\n')
    require(bool(delimiter), '공통 역할 본문 구분자 없음: ' + role)
    description = next(line[len('description:'):].strip() for line in frontmatter.splitlines()
                       if line.startswith('description:'))
    return description, body.strip()


class Fixture:
    def __init__(self, base):
        self.base = Path(base)
        self.root = self.base / 'project with spaces'
        self.root.mkdir()
        # 실행한 도구가 홈 설정을 만들더라도 임시 영역 밖에는 쓰지 못하도록 테스트 환경을 분리한다.
        self.env = dict(os.environ, CODEX_HOME=str(self.base / 'codex-home'),
                        CLAUDE_CONFIG_DIR=str(self.base / 'claude-home'))

    def write(self, rel, content):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
        return path

    def run(self, target='both', apply=False, expected=0, project=None, parse=True):
        args = [sys.executable, '-I', str(CONFIGURE), '--project', str(project or self.root),
                '--target', target]
        if apply:
            args.append('--apply')
        run = subprocess.run(args, cwd=self.root, env=self.env, text=True, capture_output=True)
        require(run.returncode == expected,
                'exit ' + str(run.returncode) + ', 기대 ' + str(expected) + ': ' + run.stderr[:220])
        require(not (self.base / 'codex-home').exists() and not (self.base / 'claude-home').exists(),
                '프로젝트 작성 도구가 전역 설치·신뢰용 홈을 만듦')
        if not parse:
            return None
        try:
            result = json.loads(run.stdout)
        except Exception as error:
            raise AssertionError('JSON 변경안 하나가 아님: ' + run.stdout[:200]) from error
        require(isinstance(result, dict), '변경안이 객체가 아님')
        require(isinstance(result.get('files'), list), 'files 배열이 없음')
        require(isinstance(result.get('conflicts'), list), 'conflicts 배열이 없음')
        return result


def case(title, body):
    global passed, failed
    with tempfile.TemporaryDirectory(prefix='harness-config-') as tmp:
        fixture = Fixture(tmp)
        try:
            body(fixture)
            passed += 1
            print('  ok    ' + title)
        except Exception as error:
            failed += 1
            print('  FAIL  ' + title + ' — ' + str(error))


def dryrun(f):
    plan = f.run()
    require(plan['files'] and not plan['conflicts'], '새 프로젝트 변경안이 비었거나 충돌함')
    paths = set()
    for entry in plan['files']:
        require(isinstance(entry.get('content'), str), '생성할 내용이 문자열이 아님')
        value = Path(entry['path'])
        resolved = (f.root / value).resolve() if not value.is_absolute() else value.resolve()
        require(resolved.is_relative_to(f.root.resolve()), '프로젝트 밖 생성 경로: ' + str(value))
        paths.add(str(resolved.relative_to(f.root.resolve())))
    require(set(COMMON_FILES + CODEX_FILES + ('.claude/settings.json',)).issubset(paths),
            'both 변경안에 필요한 파일이 빠짐')
    require(not list(f.root.iterdir()), 'dry-run이 프로젝트에 파일·폴더를 만듦')


case('기본 실행이면 프로젝트를 변경하지 않고 전체 변경안을 출력한다', dryrun)


def common_scaffold(f):
    f.run(target='claude', apply=True)
    harness = (f.root / '.claude/harness.conf').read_text()
    actual_keys = {line.split('=', 1)[0] for line in harness.splitlines()
                   if line and not line.startswith('#') and '=' in line}
    required_keys = {line.split('\t')[0] for line in (REPO / 'plugin/scripts/harness-keys.txt').read_text().splitlines()
                     if line and not line.startswith('#')}
    require(required_keys.issubset(actual_keys), '공통 설정 골격에 키 목록의 키가 빠짐')
    require('{' in harness and '}' in harness, '공통 설정을 실측 전 실제 값으로 임의 채움')
    dev = (f.root / 'scripts/dev.conf').read_text()
    require('TEST_CMD={' in dev, 'dev.conf에 테스트 명령 빈칸 골격이 없음')


case('공통 설정이 없는 프로젝트면 키 목록과 dev.conf의 빈칸 골격을 만든다', common_scaffold)


def claude_only(f):
    f.run(target='claude', apply=True)
    require((f.root / '.claude/settings.json').is_file(), 'Claude 설정이 없음')
    require(not (f.root / '.codex').exists(), 'Claude만 선택했는데 Codex 파일을 만듦')
    settings = json.loads((f.root / '.claude/settings.json').read_text())
    require(settings.get('enabledPlugins', {}).get('superchaeyeons@superchaeyeons') is True,
            'Claude 플러그인 활성화 설정이 없음')
    require('superchaeyeons' in settings.get('extraKnownMarketplaces', {}), 'Claude marketplace 설정이 없음')


case('Claude만 선택하면 Claude 설정만 생성한다', claude_only)


def codex_only(f):
    f.run(target='codex', apply=True)
    for rel in COMMON_FILES + CODEX_FILES:
        require((f.root / rel).is_file(), 'Codex 설정 파일 누락: ' + rel)
    require(not (f.root / '.claude/settings.json').exists(), 'Codex만 선택했는데 Claude 실행 설정을 만듦')
    config = (f.root / '.codex/config.toml').read_text()
    tomllib.loads(config)
    require('superchaeyeons' in config, 'Codex 프로젝트 플러그인 설정이 없음')


case('Codex만 선택하면 공통 값과 Codex 연결 파일만 생성한다', codex_only)


def both(f):
    f.run(apply=True)
    for rel in COMMON_FILES + CODEX_FILES + ('.claude/settings.json',):
        require((f.root / rel).is_file(), '양쪽 선택의 파일 누락: ' + rel)
    require(not (f.root / '.codex/harness.conf').exists(), '공통 설정을 Codex 쪽에 중복 생성함')


case('양쪽을 선택하면 공통 값은 한 벌로 두고 도구별 연결을 만든다', both)


def preserve_common(f):
    harness = b'# user config\r\nSCOPE=sub\r\nHARNESS_SELF_EDIT=0\r\n'
    dev = b'# custom runner\r\nTEST_CMD=custom verify\r\n'
    f.write('.claude/harness.conf', harness)
    f.write('scripts/dev.conf', dev)
    f.run(apply=True)
    require((f.root / '.claude/harness.conf').read_bytes() == harness, '기존 공통 설정 바이트가 바뀜')
    require((f.root / 'scripts/dev.conf').read_bytes() == dev, '기존 dev.conf 바이트가 바뀜')


case('공통 설정이 이미 있으면 내용과 줄바꿈까지 보존한다', preserve_common)


def preserve_claude(f):
    deny = ['Read(custom.secret)', 'Bash(custom check:*)']
    original = {'permissions': {'deny': deny, 'allow': ['Bash(git status:*)']},
                'env': {'USER_FLAG': 'keep'}, 'unrelated': {'enabled': True}}
    f.write('.claude/settings.json', json.dumps(original, indent=2))
    f.run(target='claude', apply=True)
    settings = json.loads((f.root / '.claude/settings.json').read_text())
    require(settings['permissions']['deny'] == deny, '기존 deny 배열을 덮어쓰거나 항목을 복원함')
    require('Bash(rm -rf:*)' not in settings['permissions']['deny'], '사용자가 지운 rm -rf 차단을 복원함')
    require(settings['permissions']['allow'] == original['permissions']['allow'], '기존 allow를 바꿈')
    require(settings['env'] == original['env'] and settings['unrelated'] == original['unrelated'],
            '관련 없는 Claude 설정을 바꿈')


case('Claude 설정을 합칠 때 기존 권한 배열과 다른 설정을 보존한다', preserve_claude)


def preserve_codex(f):
    original = '# 사용자 주석 유지\nmodel = "user-model"\n\n[features]\nweb_search_request = false\n'
    f.write('.codex/config.toml', original)
    f.run(target='codex', apply=True)
    text = (f.root / '.codex/config.toml').read_text()
    config = tomllib.loads(text)
    require(config['model'] == 'user-model' and config['features']['web_search_request'] is False,
            '관련 없는 Codex 설정을 바꿈')
    require('# 사용자 주석 유지' in text, '기존 TOML 주석을 없앰')


case('Codex 설정을 합칠 때 기존 값과 주석을 보존한다', preserve_codex)


def roles(f):
    f.run(target='codex', apply=True)
    for role in ROLES:
        data = tomllib.loads((f.root / '.codex/agents' / (role + '.toml')).read_text())
        description, body = role_source(role)
        require(data.get('name') == role, '역할 이름이 다름: ' + role)
        require(data.get('description') == description, '공통 역할 설명을 사용하지 않음: ' + role)
        require(body in data.get('developer_instructions', ''), '공통 역할 본문이 빠짐: ' + role)
        require('model' not in data, '역할 모델을 부모에게서 상속하지 않음: ' + role)
        if role == 'test-writer':
            require(data.get('features', {}).get('shell_tool') is False, 'test-writer의 shell 도구가 열려 있음')


case('Codex 역할은 공통 본문을 사용하고 모델 상속과 test-writer 도구 제한을 선언한다', roles)


def command_rules(f):
    f.run(target='codex', apply=True)
    text = (f.root / '.codex/rules/harness.rules').read_text()
    patterns = set()
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'prefix_rule':
            values = {item.arg: ast.literal_eval(item.value) for item in node.keywords
                      if item.arg in ('pattern', 'decision')}
            if values.get('decision') == 'prompt':
                patterns.add(tuple(values.get('pattern', ())))
    required = {('git', 'commit'), ('git', 'push'), ('gh', 'pr', 'create'), ('gh', 'pr', 'merge')}
    require(required.issubset(patterns), '커밋·원격 반영의 유효한 prompt 규칙이 빠짐')


case('Codex 명령 규칙이면 커밋과 원격 반영에 prompt를 선언한다', command_rules)


def conflict_atomic(f):
    f.write('.codex/agents/researcher.toml', 'name = "custom-researcher"\ndeveloper_instructions = "Keep me"\n')
    f.write('keep.txt', 'unchanged\n')
    before = snapshot(f.root)
    plan = f.run(apply=True, expected=1)
    require(plan['conflicts'], '다른 역할 내용을 충돌로 알리지 않음')
    require(snapshot(f.root) == before, '충돌인데 일부 파일을 적용함')


case('기존 다른 역할과 충돌하면 전체 적용을 거절하고 아무 파일도 바꾸지 않는다', conflict_atomic)


def idempotent(f):
    f.run(apply=True)
    before = snapshot(f.root)
    f.run(apply=True)
    require(snapshot(f.root) == before, '같은 설정을 다시 적용하면 내용이 달라짐')


case('같은 도구 선택을 반복 적용해도 파일 내용이 달라지지 않는다', idempotent)


def no_delete_other_target(f):
    f.run(apply=True)
    before = {rel: (f.root / rel).read_bytes() for rel in CODEX_FILES}
    f.run(target='claude', apply=True)
    require(all((f.root / rel).read_bytes() == content for rel, content in before.items()),
            'Claude로 재선택하면서 기존 Codex 설정을 삭제하거나 바꿈')


case('도구를 다시 선택해도 다른 도구의 기존 연결을 삭제하지 않는다', no_delete_other_target)


def symlink_escape(f):
    outside = f.base / 'outside'
    outside.mkdir()
    (outside / 'keep.txt').write_text('outside data\n')
    (f.root / '.codex').symlink_to(outside, target_is_directory=True)
    before_root, before_outside = snapshot(f.root), snapshot(outside)
    plan = f.run(target='codex', apply=True, expected=1)
    require(plan['conflicts'], '프로젝트 밖으로 이어지는 경로를 충돌로 알리지 않음')
    require(snapshot(f.root) == before_root and snapshot(outside) == before_outside,
            '심볼릭 링크를 따라 프로젝트 밖에 적용함')


case('설정 경로가 심볼릭 링크로 외부를 가리키면 외부에 쓰지 않고 전체 적용을 거절한다', symlink_escape)


def ignores(f):
    original = '# 사용자 제외 목록\nlocal-data/\n'
    f.write('.gitignore', original)
    f.run(apply=True)
    text = (f.root / '.gitignore').read_text()
    require(text.startswith(original), '기존 gitignore 내용을 바꿈')
    paths = {line.strip().lstrip('/') for line in text.splitlines() if line and not line.startswith('#')}
    for rel in ('.claude/corrections/', '.claude/polish/', '.codex/harness-state/',
                '.codex/corrections/', '.codex/polish/'):
        require(rel in paths, '도구별 상태 제외가 빠짐: ' + rel)


case('기존 gitignore를 보존하며 도구별 기록과 다듬기 상태를 제외한다', ignores)


def invalid_target(f):
    f.run(target='invalid', expected=2, parse=False)
    require(not list(f.root.iterdir()), '잘못된 target인데 프로젝트를 변경함')


case('지원하지 않는 도구 선택이면 사용법 오류로 끝낸다', invalid_target)


def missing_project(f):
    missing = f.base / 'does-not-exist'
    f.run(project=missing, apply=True, expected=2, parse=False)
    require(not missing.exists(), '없는 프로젝트를 임의로 만듦')


case('프로젝트가 없으면 사용법 오류로 끝내고 폴더를 만들지 않는다', missing_project)

def bulk_delete_delegated(f):
    f.write('.claude/harness.conf', 'BLOCK_BULK_DELETE=0\n')
    f.run(target='claude', apply=True)
    settings = json.loads((f.root / '.claude/settings.json').read_text())
    require('Bash(rm -rf:*)' not in settings.get('permissions', {}).get('deny', []),
            '공통 설정에서 맡긴 대량 삭제를 새 Claude 설정이 다시 차단함')


case('대량 삭제를 맡긴 기존 설정이면 새 Claude deny에 rm -rf 차단을 넣지 않는다', bulk_delete_delegated)


def internal_settings_symlink(f):
    target = f.write('shared-settings.json', '{"unrelated": "keep"}\n')
    link = f.root / '.claude/settings.json'
    link.parent.mkdir(parents=True)
    link.symlink_to(target)
    before = snapshot(f.root)
    link_target = os.readlink(link)
    plan = f.run(target='claude', apply=True, expected=1)
    require(plan['conflicts'], '내부 파일로 이어지는 설정 링크를 충돌로 알리지 않음')
    require(link.is_symlink() and os.readlink(link) == link_target, '기존 설정 링크를 바꿈')
    require(snapshot(f.root) == before, '설정 링크 충돌인데 원본이나 다른 파일을 바꿈')


case('설정 파일이 내부 심볼릭 링크여도 링크와 원본을 보존하고 적용을 거절한다', internal_settings_symlink)

def non_boolean_enabled(f):
    for value in ('1', '1.0'):
        text = ('[marketplaces.superchaeyeons]\nsource_type = "git"\n'
                'source = "https://github.com/chhezue/Superchaeyeons.git"\nref = "main"\n\n'
                '[plugins."superchaeyeons@superchaeyeons"]\nenabled = ' + value + '\n')
        f.write('.codex/config.toml', text)
        before = snapshot(f.root)
        plan = f.run(target='codex', apply=True, expected=1)
        require(plan['conflicts'], 'enabled의 숫자 값을 bool로 간주함: ' + value)
        require(snapshot(f.root) == before, '잘못된 enabled 값인데 파일을 변경함: ' + value)


case('Codex enabled가 정수나 실수면 bool과 구분해 전체 적용을 거절한다', non_boolean_enabled)

print('하네스 설정 케이스 ' + str(passed + failed) + ' · 통과 ' + str(passed) + ' · 실패 ' + str(failed))
sys.exit(1 if failed else 0)
PY
