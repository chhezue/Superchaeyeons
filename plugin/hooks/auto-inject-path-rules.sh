#!/bin/bash
# 경로 조건부 규칙 주입 — 다룬 파일이 규칙의 paths: glob에 맞으면 그 규칙 본문을 additionalContext로 넣는다.
# Registered in plugin/hooks/hooks.json (PostToolUse Read|Write|Edit|MultiEdit|NotebookEdit).
# 규칙 원문과 glob은 플러그인 rules/*.md가 갖는다 — frontmatter에 paths:가 있는 파일만 대상이고, 머리(frontmatter)는 빼고 넣는다.
# 스킬의 paths: 필드는 본문이 자동으로 들어오지 않아 쓰지 않는다 (harness-plugin-delivery 스펙 "실험으로 확인한 것").
#
# 한 번만 넣기: 규칙마다 세션(서브에이전트는 agent_id별)에 한 번만 넣는다 — 마크다운을 읽을 때마다 같은 규칙이 다시 들어가지 않게.
#   기록은 "$STATE_DIR.<세션>.g<세대>.<agent>.<규칙>" 빈 파일이다. 세대는 auto-inject-rules.sh가 요약·/clear 때 올린다
#   ("$STATE_DIR.<세션>.gen") — 그러면 이 훅이 같은 규칙을 다시 넣는다. 지난 세대 파일은 지우지 않는다(임시 폴더가 정리한다).
# glob: 프로젝트 기준 경로에 맞춘다. bash [[ == ]] 패턴이라 *가 /도 넘는다. `**/`로 시작하는 glob은 맨 위 경로에도, `/**/`는
#   바로 아래 경로에도 맞게 그 부분을 뺀 모양도 함께 본다 (예: **/a/**/*.md → a/x.md).
#
# 훅 공통 규약의 예외: 넣기만 하는 훅이라 어떤 입력에도 exit 0이고, 규칙을 못 읽으면 systemMessage로 알린다.
# 세션마다 여러 번 도는 훅이라 bash 3.2 내장 기능만 쓴다 — PATH가 망가져도 돌고, 외부 명령을 띄우는 비용이 없다.
# Hook input: JSON with "session_id", "agent_id"(서브에이전트), "tool_input.file_path"/"notebook_path" on stdin.
STATE_DIR="${TMPDIR:-/tmp}/superchaeyeons-inject"

root="${CLAUDE_PLUGIN_ROOT:-${0%/*}/..}"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"

warn() {
	printf '{"systemMessage":"경로 규칙을 싣지 못했다 — %s"}\n' "$1"
	exit 0
}
esc() {
	local s=$1
	s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
	printf '%s' "$s"
}
field() { # field <이름> — 입력 JSON의 문자열 값 하나 (따옴표가 든 값은 다루지 않는다)
	[[ $input =~ \"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}"
}
matches() { # matches <상대 경로> <glob>
	local rel=$1 g=$2 p='/**/' r='/' c
	for c in "$g" "${g#"**/"}" "${g//"$p"/$r}" "${g#"**/"}"; do
		[[ $rel == $c ]] && return 0
	done
	c="${g#"**/"}"; c="${c//"$p"/$r}"
	[[ $rel == $c ]]
}

IFS= read -r -d '' input
path="$(field file_path)"; [ -n "$path" ] || path="$(field notebook_path)"
[ -n "$path" ] || exit 0
case "$path" in "$proj"/*) rel="${path#"$proj"/}" ;; *) exit 0 ;; esac
session="$(field session_id)"; agent="$(field agent_id)"
gen=0
[ -n "$session" ] && [ -f "$STATE_DIR.$session.gen" ] && IFS= read -r gen <"$STATE_DIR.$session.gen"
mark="$STATE_DIR.${session:-none}.g${gen:-0}.${agent:-main}"

shopt -s nullglob
rules=("$root"/rules/*.md)
[ "${#rules[@]}" -gt 0 ] || warn "플러그인 rules/ 폴더에 규칙이 없다 ($root/rules)"

out=""
nl=$'\n'
for f in "${rules[@]}"; do
	body=""; IFS= read -r -d '' body <"$f"
	[ -n "$body" ] || warn "규칙 파일을 읽지 못했다 (${f##*/})"
	[[ $body == "---$nl"* ]] || continue
	rest="${body#"---$nl"}"
	fm="${rest%%"$nl---$nl"*}"
	[[ $fm == *"paths:"* ]] || continue
	text="${rest#*"$nl---$nl"}"
	name="${f##*/}"; name="${name%.md}"
	[ -n "$session" ] && [ -f "$mark.$name" ] && continue
	hit=0
	while IFS= read -r line; do
		[[ $line =~ ^[[:space:]]*-[[:space:]]*\"(.*)\"[[:space:]]*$ ]] || continue
		matches "$rel" "${BASH_REMATCH[1]}" && { hit=1; break; }
	done <<<"$fm"
	[ "$hit" = 1 ] || continue
	out="$out[하네스 경로 규칙 ${name} — ${rel}에 적용. 규칙의 scripts/…는 플러그인 폴더 ${root}/scripts 기준이다]$nl$text$nl"
	[ -n "$session" ] && : >"$mark.$name" 2>/dev/null
done

[ -n "$out" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(esc "$out")"
exit 0
