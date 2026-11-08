#!/usr/bin/env bash
# 플러그인 검사기 — `claude plugin validate --json` 결과에서 매니페스트의 `version` 경고만 허용한다.
# plugin.json에 version을 적지 않아 커밋 SHA를 버전으로 쓰기 때문에 이 경고는 늘 나온다. `--strict`는 이 경고까지 실패로 쳐서 쓰지 않는다.
# 스펙: docs/specs/cross-cutting/harness-plugin-delivery.md (리스크 11). 이 저장소 전용이라 plugin/에 넣지 않는다.
#
# 사용:
#   scripts/check-plugin.sh            # plugin/ 과 저장소 루트의 마켓플레이스를 claude로 검사
#   scripts/check-plugin.sh --codex <plugin-root>  # Codex 등록 정적 검사 (실행·신뢰는 별도)
#   scripts/check-plugin.sh --stdin    # claude를 부르지 않고 stdin의 validate 결과 하나만 판정 (scripts/hook-cases.txt)
#
# exit 0 = 통과 · exit 1 = 다른 경고·오류 · success:false · 결과를 해석하지 못함 · claude 없음 · exit 2 = 사용법 오류
# 허용하는 path: 플러그인 검사의 `version`, 마켓플레이스 검사의 `plugins[N] plugin.json → version` — 둘 다 매니페스트 경고일 때만.

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# stdin의 validate 결과 하나를 판정한다. 실패 이유는 stderr로
judge() {
	python3 -I -c '
import json, re, sys
try:
    r = json.load(sys.stdin)
    m = r["manifest"]
    items = [("manifest", "error", e) for e in m["errors"]] + [("manifest", "warning", w) for w in m["warnings"]]
    for c in r["contents"]:
        items += [(c.get("file", "?"), "error", e) for e in c["errors"]] + [(c.get("file", "?"), "warning", w) for w in c["warnings"]]
    success = r["success"]
    paths = [(where, kind, i["path"], i.get("message", "")) for where, kind, i in items]
except Exception as e:
    print("validate 결과를 해석하지 못했습니다 (%s: %s) — Claude Code 출력 형식이 바뀌었는지 확인하세요" % (type(e).__name__, e), file=sys.stderr)
    sys.exit(1)
allowed = re.compile(r"^(version|plugins\[\d+\] plugin\.json → version)$")
bad = [p for p in paths if not (p[0] == "manifest" and p[1] == "warning" and allowed.match(str(p[2])))]
for where, kind, path, msg in bad:
    print("%s %s: %s — %s" % (where, kind, path, msg), file=sys.stderr)
if success is not True:
    print("success가 true가 아닙니다", file=sys.stderr)
    sys.exit(1)
sys.exit(1 if bad else 0)
'
}

# Codex 전용 등록만 정적으로 검사한다. 훅 실행·신뢰 검증을 대신하지 않는다.
judge_codex() {
 python3 -I - "$1" <<'CODEX_PY'
import json, pathlib, re, sys

SKILLS = ("init-harness", "ask-decisions", "write-spec", "test-first",
          "refactor-safely", "fix-bug", "verify-work", "improve-harness")
try:
    root = pathlib.Path(sys.argv[1]).resolve(strict=True)

    def local_path(value):
        if not isinstance(value, str) or not value.startswith("./"):
            raise ValueError("경로는 ./로 시작해야 합니다")
        path = (root / value).resolve(strict=True)
        if not path.is_relative_to(root):
            raise ValueError("플러그인 루트 밖 경로입니다")
        return path

    manifest_path = root / ".codex-plugin/plugin.json"
    if not manifest_path.resolve(strict=True).is_relative_to(root):
        raise ValueError("매니페스트가 루트 밖을 가리킵니다")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("name") != "superchaeyeons":
        raise ValueError("플러그인 이름이 다릅니다")
    skills = local_path(manifest["skills"])
    if skills != (root / "skills").resolve():
        raise ValueError("공통 skills 원본을 참조해야 합니다")
    for name in SKILLS:
        skill = (skills / name / "SKILL.md").resolve(strict=True)
        if not skill.is_file() or not skill.is_relative_to(root):
            raise ValueError("스킬 원본이 없거나 루트 밖입니다: " + name)

    paths = manifest["hooks"]
    paths = [paths] if isinstance(paths, str) else paths
    if not isinstance(paths, list) or not paths:
        raise ValueError("Codex 훅 파일 경로가 필요합니다")
    seen_files, seen_handlers, referenced = set(), set(), set()
    claude_hooks = (root / "hooks/hooks.json").resolve()
    for value in paths:
        path = local_path(value)
        if path == claude_hooks:
            raise ValueError("Claude 기본 훅을 Codex에 연결할 수 없습니다")
        if path in seen_files:
            raise ValueError("훅 파일 중복 등록입니다")
        seen_files.add(path)
        events = json.loads(path.read_text())["hooks"]
        if not isinstance(events, dict) or not events:
            raise ValueError("hooks는 이벤트 객체여야 합니다")
        for event, groups in events.items():
            if not isinstance(groups, list) or not groups:
                raise ValueError("이벤트 그룹은 배열이어야 합니다")
            for group in groups:
                matcher = group.get("matcher", "")
                handlers = group["hooks"]
                if not isinstance(matcher, str) or not isinstance(handlers, list) or not handlers:
                    raise ValueError("잘못된 매처 또는 핸들러입니다")
                for handler in handlers:
                    command = handler.get("command")
                    if handler.get("type") != "command" or not isinstance(command, str) or not command.strip():
                        raise ValueError("명령 핸들러가 필요합니다")
                    if "ask-approval.sh" in command:
                        raise ValueError("Claude ask-approval 훅을 Codex에 연결할 수 없습니다")
                    for ref in re.findall(r"\$\{(?:PLUGIN_ROOT|CLAUDE_PLUGIN_ROOT)\}/([^\s\"';]+)", command):
                        target = local_path("./" + ref)
                        if not target.is_file():
                            raise ValueError("훅 실행 파일이 없습니다")
                        referenced.add(target)
                    key = (event, matcher, command.strip())
                    if key in seen_handlers:
                        raise ValueError("같은 매처의 핸들러 중복 등록입니다")
                    seen_handlers.add(key)
    for hook in (root / "hooks").glob("*.py"):
        if hook.resolve() not in referenced:
            raise ValueError("Codex Python 훅이 등록돼 있지 않습니다: " + hook.name)
except Exception as error:
    # 파일·JSON 오류도 한 줄로 보고하고 실패한다. 입력 원문은 출력하지 않는다.
    reason = str(error).replace("\n", " ").replace("\r", " ")
    print("Codex 등록 오류: " + reason, file=sys.stderr)
    sys.exit(1)
print("Codex 등록 검사 통과 (정적 검사 · 실행/신뢰는 별도)")
CODEX_PY
}

case "${1:-}" in
--codex)
 [ "$#" -eq 2 ] || { echo "사용법: scripts/check-plugin.sh --codex <plugin-root>" >&2; exit 2; }
 judge_codex "$2"
 ;;
--stdin)
	judge || exit 1
	echo "플러그인 검사 통과 (version 경고만)"
	;;
'')
	command -v claude >/dev/null 2>&1 || { echo "FAIL: claude 명령이 없어 플러그인을 검사하지 못했습니다" >&2; exit 1; }
	cd "$repo_root"
	for target in plugin .; do
		# validate는 문제가 있으면 exit 1이지만 판정은 JSON으로 한다 — 경고만 있을 때도 exit 0이라 종료 코드로는 가를 수 없다
		claude plugin validate "$target" --json 2>/dev/null | judge || { echo "FAIL: claude plugin validate $target" >&2; exit 1; }
	done
	echo "플러그인 검사 통과 — plugin/ · 마켓플레이스 (version 경고만)"
	;;
*)
	echo "사용법: scripts/check-plugin.sh [--stdin | --codex <plugin-root>]" >&2
	exit 2
	;;
esac
