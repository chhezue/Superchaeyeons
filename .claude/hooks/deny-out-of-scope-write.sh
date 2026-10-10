#!/bin/bash
# Blocks Write/Edit outside the harness's write scope. Registered in .claude/settings.json (PreToolUse, Write|Edit).
# 모노레포처럼 저장소 일부만 이 하네스가 소유하는 프로젝트(shape 축)에서, 다른 모듈을 참조·조사하는 건 자유지만
# 쓰기는 소유 범위로 제한한다. .claude/ 자체는 하네스 유지보수를 위해 항상 허용한다.
#
# SCOPE는 harness-map.md의 {{작업 범위}} 슬롯과 같은 값이어야 한다 — 훅은 슬롯을 읽지 못하므로 여기 직접 적는다.
# 슬롯을 바꾸면 이 줄도 함께 고칠 것. "." 이면 저장소 전체가 범위라 아무것도 막지 않는다.
SCOPE="."
#
# 훅 공통 규약 (scripts/test-hooks.sh가 케이스 파일로 판정한다):
#   1. 판정 불가 = 차단 — JSON이 깨졌거나 경로 키가 없거나 입력이 비어 있으면 exit 2. 이전 판(baro)은 이 경우 통과시켜
#      "fail-closed 백스톱이 한 번 열린" 사고가 났다.
#   2. 경로는 실경로로 정규화 — `sub/../other`·심볼릭 링크 경유 절대경로로 범위를 벗어나는 것을 막는다.
#   3. 승인 통로는 없다 — 막혔으면 사용자에게 보고한다. 승인이란 사용자가 SCOPE를 넓히거나 그 파일을 직접 고치는 행위다.
# Hook input: JSON with "tool_input.file_path" (Write/Edit/MultiEdit) or "tool_input.notebook_path" (NotebookEdit) on stdin.

[ "$SCOPE" = "." ] && exit 0

input=$(cat)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="$PWD"

verdict=$(SCOPE="$SCOPE" REPO_ROOT="$repo_root" python3 -c '
import json, os, sys
scope = os.environ["SCOPE"].rstrip("/")
root = os.path.realpath(os.environ["REPO_ROOT"])
try:
    data = json.load(sys.stdin)
    ti = data.get("tool_input", {}) or {}
    raw = ti.get("file_path") or ti.get("notebook_path") or ""
except Exception:
    print("UNPARSEABLE"); sys.exit(0)
if not raw:
    print("UNPARSEABLE"); sys.exit(0)
path = raw if os.path.isabs(raw) else os.path.join(root, raw)
real = os.path.realpath(path)          # ".." · 심볼릭 링크 해소
if not (real == root or real.startswith(root + os.sep)):
    print("OUTSIDE_REPO"); sys.exit(0)   # 저장소 밖(세션 파일 등) — 이 하네스의 관심사가 아니다
rel = os.path.relpath(real, root)
for allowed in (scope, ".claude"):
    a = os.path.realpath(os.path.join(root, allowed))
    if real == a or real.startswith(a + os.sep):
        print("ALLOW"); sys.exit(0)
print("DENY:" + rel)
' <<< "$input")

case "$verdict" in
  ALLOW|OUTSIDE_REPO) exit 0 ;;
  UNPARSEABLE)
    echo "쓰기 대상 경로를 판정할 수 없어 차단합니다 (입력 JSON 또는 file_path/notebook_path 없음). 훅 공통 규약: 판정 불가 = 차단. Blocked by .claude/hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  DENY:*)
    rel="${verdict#DENY:}"
    echo "'$rel'는 이 하네스의 쓰기 범위(${SCOPE}/ + .claude/) 밖입니다 (harness-map.md {{작업 범위}}). 우회하지 말고 사용자에게 보고하세요 — 승인은 사용자가 SCOPE를 넓히거나 그 파일을 직접 고치는 것으로 이뤄집니다. Blocked by .claude/hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  *)
    echo "훅 내부 오류로 판정할 수 없어 차단합니다 ($verdict). Blocked by .claude/hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
esac
