#!/bin/bash
# Blocks Write/Edit outside the harness's write scope, and blocks the agent from rewriting the harness's own hooks/settings
# unless the project explicitly allows it. Registered in .claude/settings.json (PreToolUse, Write|Edit).
# 모노레포처럼 저장소 일부만 이 하네스가 소유하는 프로젝트(shape 축)에서, 다른 모듈을 참조·조사하는 건 자유지만
# 쓰기는 소유 범위로 제한한다. .claude/의 규칙·스킬·에이전트는 하네스 유지보수를 위해 항상 허용한다.
#
# SCOPE는 harness-map.md의 {{작업 범위}} 슬롯과 같은 값이어야 한다 — 훅은 슬롯을 읽지 못하므로 여기 직접 적는다.
# 슬롯을 바꾸면 이 줄도 함께 고칠 것. "." 이면 저장소 전체가 범위라 범위 검사는 하지 않는다.
SCOPE="."
# HARNESS_SELF_EDIT는 harness-map.md 능력 플래그 "하네스 자기 수정"과 같은 값이어야 한다 (☑=1 · ❌=0).
# 0이면 `.claude/hooks/`와 `.claude/settings.json` 쓰기를 SCOPE와 무관하게 막는다 — 훅 스크립트는 고친 즉시 다음 도구 호출부터
# 효력이 생기므로, 에이전트가 자기 훅을 exit 0으로 바꾸는 경로를 닫는다 (2026-09-07 감사). 하네스 자체를 고치는 저장소(이 템플릿)만 1.
HARNESS_SELF_EDIT="1"
#
# 훅 공통 규약 (scripts/test-hooks.sh가 케이스 파일로 판정한다):
#   1. 판정 불가 = 차단 — JSON이 깨졌거나 경로 키가 없거나 입력이 비어 있으면 exit 2. 이전 판(baro)은 이 경우 통과시켜
#      "fail-closed 백스톱이 한 번 열린" 사고가 났다.
#   2. 경로는 실경로로 정규화 — `sub/../other`·심볼릭 링크 경유 절대경로로 범위를 벗어나는 것을 막는다.
#   3. 승인 통로는 없다 — 막혔으면 사용자에게 보고한다. 승인이란 사용자가 SCOPE·플래그를 바꾸거나 그 파일을 직접 고치는 행위다.
# Hook input: JSON with "tool_input.file_path" (Write/Edit/MultiEdit) or "tool_input.notebook_path" (NotebookEdit) on stdin.

# 범위 전체 + 자기 수정 허용이면 볼 것이 없다
[ "$SCOPE" = "." ] && [ "$HARNESS_SELF_EDIT" = "1" ] && exit 0

input=$(cat)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="$PWD"

verdict=$(SCOPE="$SCOPE" SELF_EDIT="$HARNESS_SELF_EDIT" REPO_ROOT="$repo_root" python3 -c '
import json, os, sys
scope = os.environ["SCOPE"].rstrip("/")
self_edit = os.environ["SELF_EDIT"] == "1"
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
# 1. 하네스 자기 수정 — 훅 본문·훅 등록은 플래그가 ❌면 어느 범위에서도 막는다
if not self_edit:
    hooks_dir = os.path.realpath(os.path.join(root, ".claude", "hooks"))
    settings = os.path.realpath(os.path.join(root, ".claude", "settings.json"))
    if real == settings or real == hooks_dir or real.startswith(hooks_dir + os.sep):
        print("DENY_HARNESS:" + rel); sys.exit(0)
# 2. 작업 범위 — "."이면 저장소 전체
if scope == ".":
    print("ALLOW"); sys.exit(0)
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
  DENY_HARNESS:*)
    rel="${verdict#DENY_HARNESS:}"
    echo "'$rel'는 하네스의 훅 본문 또는 훅 등록 파일입니다. 이 프로젝트는 능력 플래그 \"하네스 자기 수정\"이 ❌라 에이전트가 고칠 수 없습니다 (harness-map.md). 고칠 내용을 diff로 제안하고 사용자가 직접 반영하거나, 사용자가 플래그와 훅 상수 HARNESS_SELF_EDIT를 바꿉니다. Blocked by .claude/hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  DENY:*)
    rel="${verdict#DENY:}"
    echo "'$rel'는 이 하네스의 쓰기 범위(${SCOPE}/ + .claude/) 밖입니다 (harness-map.md {{작업 범위}}). 우회하지 말고 사용자에게 보고하세요 — 승인은 사용자가 SCOPE를 넓히거나 그 파일을 직접 고치는 것으로 이뤄집니다. Blocked by .claude/hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  *)
    echo "훅 내부 오류로 판정할 수 없어 차단합니다 ($verdict). Blocked by .claude/hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
esac
