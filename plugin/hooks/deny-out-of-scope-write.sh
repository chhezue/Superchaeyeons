#!/bin/bash
# Blocks Write/Edit outside the harness's write scope, and blocks the agent from rewriting the harness's own hooks/settings
# unless the project explicitly allows it. Registered in plugin/hooks/hooks.json (PreToolUse, Write|Edit|MultiEdit|NotebookEdit —
# 매처는 정확한 이름 목록이라 `Write|Edit`만 두면 MultiEdit·NotebookEdit 쓰기가 이 훅을 거치지 않는다. test-hooks.sh가 대조한다).
# 모노레포처럼 저장소 일부만 이 하네스가 소유하는 프로젝트(shape 축)에서, 다른 모듈을 참조·조사하는 건 자유지만
# 쓰기는 소유 범위로 제한한다. .claude/의 규칙·스킬·에이전트는 하네스 유지보수를 위해 항상 허용한다.
#
# 설정 키 SCOPE({{작업 범위}})와 HARNESS_SELF_EDIT(플래그 "하네스 자기 수정", 1·0)를 .claude/harness.conf에서 읽는다.
# HARNESS_SELF_EDIT=0이면 플러그인 폴더(CLAUDE_PLUGIN_ROOT — 훅·도구 본문)와 프로젝트의 `.claude/hooks/`(local 훅)·`.claude/settings.json`
# 쓰기를 SCOPE와 무관하게 막는다. 플러그인 폴더는 저장소 밖이어도 막는다 — 훅 스크립트는 고친 즉시 다음 도구 호출부터 효력이 생기므로,
# 에이전트가 자기 훅을 exit 0으로 바꾸는 경로를 닫는다 (2026-09-07 감사). 하네스 자체를 고치는 저장소(이 템플릿)만 1.
# 설정 파일이 없으면(init 전) SCOPE=. · HARNESS_SELF_EDIT=0으로 판정하되, init-harness가 설정을 만들 수 있게
# `.claude/harness.conf`·`.claude/settings.json` 쓰기만은 막지 않는다.
#
# 훅 공통 규약 (scripts/test-hooks.sh가 케이스 파일로 판정한다):
#   1. 판정 불가 = 차단 — JSON이 깨졌거나 경로 키가 없거나 입력이 비어 있으면 exit 2. 이전 판(baro)은 이 경우 통과시켜
#      "fail-closed 백스톱이 한 번 열린" 사고가 났다.
#   2. 경로는 실경로로 정규화 — `sub/../other`·심볼릭 링크 경유 절대경로로 범위를 벗어나는 것을 막는다.
#   3. 승인 통로는 없다 — 막혔으면 사용자에게 보고한다. 승인이란 사용자가 설정 SCOPE·플래그를 바꾸거나 그 파일을 직접 고치는 행위다.
#   4. 설정 파일이 깨졌으면(아래) 판정 불가로 막는다.
# Hook input: JSON with "tool_input.file_path" (Write/Edit/MultiEdit) or "tool_input.notebook_path" (NotebookEdit) on stdin.

# ---- 프로젝트 설정 .claude/harness.conf -------------------------------------------
# 값은 훅 본문이 아니라 프로젝트 설정 파일에 있다 — 플러그인은 모든 프로젝트가 같은 훅 파일을 쓴다. 키·뜻은 플러그인
# scripts/harness-keys.txt, 값 규칙은 skills/init-harness/references/harness-conf.md. 파일이 없으면(init 전) 가장 엄격한
# 기본값, 쓰는 키가 없으면 그 키만 기본값, 깨졌으면(키=값이 아닌 줄 · 쓰는 키가 빈칸 {…}이거나 허용 밖 값) conf_bad에 이유를 둔다.
conf_path="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")}/.claude/harness.conf"
conf_keys=" "; conf_bad=""; conf_found=0
if [ -f "$conf_path" ]; then
	conf_found=1
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		if [[ $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
			printf -v "conf_${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"; conf_keys="$conf_keys${BASH_REMATCH[1]} "
		else
			conf_bad="키=값이 아닌 줄 (${line:0:40})"
		fi
	done <"$conf_path"
fi
# conf_use <키> <기본값> <허용 정규식> — 키 값을 같은 이름의 변수에 둔다. 빈칸이거나 허용 밖이면 conf_bad
conf_use() {
	local name="conf_$1" v="$2"
	case "$conf_keys" in *" $1 "*) v="${!name}" ;; esac
	if [[ $v =~ ^\{[^{}]*\}$ ]] || ! [[ $v =~ $3 ]]; then conf_bad="$1 값이 빈칸이거나 허용되지 않는다 ($v)"; fi
	printf -v "$1" '%s' "$v"
}
conf_use SCOPE "." '^.+$'
conf_use HARNESS_SELF_EDIT 0 '^[01]$'
if [ -n "$conf_bad" ]; then
  echo "하네스 설정(.claude/harness.conf)을 해석하지 못해 쓰기를 막습니다 — $conf_bad. 훅 공통 규약: 판정 불가 = 차단. 다른 도구로 우회하지 말고, 사용자에게 그 파일을 고치거나 init-harness로 다시 채우도록 보고하고 멈추세요. Blocked by superchaeyeons 플러그인 hooks/deny-out-of-scope-write.sh." >&2
  exit 2
fi

# 범위 전체 + 자기 수정 허용이면 볼 것이 없다
[ "$SCOPE" = "." ] && [ "$HARNESS_SELF_EDIT" = "1" ] && exit 0

input=$(cat)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="$PWD"

verdict=$(SCOPE="$SCOPE" SELF_EDIT="$HARNESS_SELF_EDIT" CONF_FOUND="$conf_found" REPO_ROOT="$repo_root" python3 -I -c '
import json, os, sys
scope = os.environ["SCOPE"].rstrip("/")
self_edit = os.environ["SELF_EDIT"] == "1"
root = os.path.realpath(os.environ["REPO_ROOT"])
plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT") or ""
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
# 1-a. 하네스 자기 수정 — 플러그인 폴더는 저장소 밖(플러그인 캐시)이라 저장소 밖 통과보다 먼저 본다
if not self_edit and plugin_root:
    pr = os.path.realpath(plugin_root)
    if real == pr or real.startswith(pr + os.sep):
        print("DENY_HARNESS:" + real); sys.exit(0)
if not (real == root or real.startswith(root + os.sep)):
    print("OUTSIDE_REPO"); sys.exit(0)   # 저장소 밖(세션 파일 등) — 이 하네스의 관심사가 아니다
rel = os.path.relpath(real, root)
# 0. 설정 파일이 없으면(init 전) 설정을 만드는 쓰기만은 허용한다 — 막으면 init-harness가 하네스를 채울 수 없다
if os.environ["CONF_FOUND"] != "1" and rel in (os.path.join(".claude", "harness.conf"), os.path.join(".claude", "settings.json")):
    print("ALLOW"); sys.exit(0)
# 1-b. 하네스 자기 수정 — 프로젝트의 local 훅 본문·훅 등록은 플래그가 ❌면 어느 범위에서도 막는다
if not self_edit:
    hooks_dir = os.path.realpath(os.path.join(root, ".claude", "hooks"))
    settings = os.path.realpath(os.path.join(root, ".claude", "settings.json"))
    if real == settings or real == hooks_dir or real.startswith(hooks_dir + os.sep):
        print("DENY_HARNESS:" + rel); sys.exit(0)
# 1-c. Codex 연결의 실행 설정·명령 규칙·역할도 같은 자기 수정 정책으로 보호한다.
if not self_edit:
    for protected in (".codex/config.toml", ".codex/hooks.json", ".codex/rules", ".codex/agents", ".codex/harness-state"):
        target = os.path.realpath(os.path.join(root, protected))
        if real == target or real.startswith(target + os.sep):
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
    echo "쓰기 대상 경로를 판정할 수 없어 차단합니다 (입력 JSON 또는 file_path/notebook_path 없음). 훅 공통 규약: 판정 불가 = 차단. Blocked by superchaeyeons 플러그인 hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  DENY_HARNESS:*)
    rel="${verdict#DENY_HARNESS:}"
    echo "'$rel'는 하네스의 훅·도구 본문(플러그인 폴더·.claude/hooks/) 또는 훅 등록 파일입니다. 이 프로젝트는 능력 플래그 \"하네스 자기 수정\"이 0이라 에이전트가 고칠 수 없습니다 (.claude/harness.conf). 훅은 구두 승인을 모릅니다 — Bash 등 다른 도구로도 고치지 말고, 고칠 내용을 diff로 제안한 뒤 멈추세요. 사용자가 직접 반영하거나 .claude/harness.conf의 HARNESS_SELF_EDIT를 바꿉니다. Blocked by superchaeyeons 플러그인 hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  DENY:*)
    rel="${verdict#DENY:}"
    echo "'$rel'는 이 하네스의 쓰기 범위(${SCOPE}/ + .claude/) 밖입니다 (.claude/harness.conf의 SCOPE = {{작업 범위}}). 훅은 구두 승인을 모릅니다 — 다른 도구로 우회하지 말고, 막힌 사실과 이유, 사용자가 바꿀 것(설정 SCOPE를 넓히거나 그 파일을 직접 고치기)을 한 줄로 보고하고 멈추세요. Blocked by superchaeyeons 플러그인 hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
  *)
    echo "훅 내부 오류로 판정할 수 없어 차단합니다 ($verdict). Blocked by superchaeyeons 플러그인 hooks/deny-out-of-scope-write.sh." >&2
    exit 2 ;;
esac
