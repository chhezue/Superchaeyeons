#!/usr/bin/env bash
# 플러그인 검사기 — `claude plugin validate --json` 결과에서 매니페스트의 `version` 경고만 허용한다.
# plugin.json에 version을 적지 않아 커밋 SHA를 버전으로 쓰기 때문에 이 경고는 늘 나온다. `--strict`는 이 경고까지 실패로 쳐서 쓰지 않는다.
# 스펙: docs/specs/cross-cutting/harness-plugin-delivery.md (리스크 11). 이 저장소 전용이라 plugin/에 넣지 않는다.
#
# 사용:
#   scripts/check-plugin.sh            # plugin/ 과 저장소 루트의 마켓플레이스를 claude로 검사
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

case "${1:-}" in
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
	echo "사용법: scripts/check-plugin.sh [--stdin]" >&2
	exit 2
	;;
esac
