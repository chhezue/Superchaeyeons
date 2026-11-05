#!/bin/bash
# core 규칙 주입 — 세션 시작(시작·/clear·요약 뒤)과 서브에이전트 시작에 core 규칙 4개를 additionalContext로 넣는다.
# Registered in plugin/hooks/hooks.json (SessionStart matcher startup|clear|compact · SubagentStart).
# 플러그인은 rules/를 배달할 수 없고 플러그인 루트의 CLAUDE.md도 싣지 않아, 규칙 원문(플러그인 rules/)을 이 훅이 넣는다
# (harness-plugin-delivery 스펙 "규칙 주입"). 훅 하나의 출력은 1만 자에서 잘린다 — check-portability.sh가 9,000자 이하를 확인한다.
#
# 머리 줄: 플러그인 폴더의 실제 경로를 알린다. Bash 도구에는 CLAUDE_PLUGIN_ROOT가 없어 규칙·스킬의 scripts/…를 부를 경로를 모른다.
# 서브에이전트: 에이전트 파일 머리에 omitClaudeMd: true가 있는 플러그인 에이전트는 뺀다(규칙 없이 시작하게 만든 에이전트).
# 요약·/clear: 경로 규칙 훅(auto-inject-path-rules.sh)의 "한 번만 넣기" 세대를 올려, 그 규칙들도 다시 들어가게 한다.
#
# 실패하면 알린다: 규칙 파일을 못 읽거나(일부만 읽혀도) 입력을 해석하지 못하거나 중간에 오류가 나면 규칙을 넣지 않고
# systemMessage(사용자 화면)와 additionalContext(Claude)에 같은 경고를 담고 exit 0으로 끝낸다. 이벤트 이름을 모르면 systemMessage만 낸다.
# 아무 장치가 없으면 규칙이 조용히 빠진다 — SessionStart 훅이 실패해도 세션은 그대로 진행되기 때문이다.
# 세션마다 도는 훅이라 bash 3.2 내장 기능만 쓴다(macOS 기본 bash는 3.2 — bash 4·5 기능은 조용히 빈 값이 된다).
# Hook input: JSON with "hook_event_name", "session_id", "source"(SessionStart), "agent_type"(SubagentStart) on stdin.
STATE_DIR="${TMPDIR:-/tmp}/superchaeyeons-inject"
RULES="core-gates core-guardrails core-workflow core-reporting"
WARN="하네스 규칙을 싣지 못했다 — 이 세션은 가드레일 없이 진행된다"

event=""
esc() {
	local s=$1
	s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
	printf '%s' "$s"
}
fail() { # fail <이유> — 규칙을 넣지 않고 사용자와 Claude 양쪽에 알린다
	trap - ERR
	local msg
	msg="$(esc "$WARN ($1)")"
	if [ -n "$event" ]; then
		printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$msg" "$event" "$msg"
	else
		printf '{"systemMessage":"%s"}\n' "$msg"
	fi
	exit 0
}
trap 'fail "훅 내부 오류"' ERR
field() { # field <이름> — 입력 JSON의 문자열 값 하나
	[[ $input =~ \"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}" || :
}

input=""
IFS= read -r -d '' input || :
event="$(field hook_event_name)"
case "$event" in
SessionStart | SubagentStart) ;;
*) event=""; fail "훅 입력을 해석하지 못했다" ;;
esac

root="${CLAUDE_PLUGIN_ROOT:-${0%/*}/..}"
root="$(cd "$root" 2>/dev/null && pwd)" || fail "플러그인 폴더를 찾지 못했다"
[ -n "$root" ] || fail "플러그인 폴더를 찾지 못했다"
nl=$'\n'

if [ "$event" = "SubagentStart" ]; then
	agent="$(field agent_type)"
	case "$agent" in
	*:*)
		f="$root/agents/${agent#*:}.md"
		if [ -f "$f" ]; then
			body=""; IFS= read -r -d '' body <"$f" || :
			if [[ $body == "---$nl"* ]]; then
				fm="${body#"---$nl"}"; fm="${fm%%"$nl---$nl"*}"
				[[ $fm =~ (^|$nl)omitClaudeMd:[[:space:]]*true([[:space:]]|$) ]] && exit 0
			fi
		fi
		;;
	esac
else
	session="$(field session_id)"
	if [ -n "$session" ]; then
		gen=0
		[ -f "$STATE_DIR.$session.gen" ] && { IFS= read -r gen <"$STATE_DIR.$session.gen" || :; }
		[[ $gen =~ ^[0-9]+$ ]] || gen=0
		printf '%s\n' "$((gen + 1))" >"$STATE_DIR.$session.gen" 2>/dev/null || :
	fi
fi

text="[하네스 규칙 — superchaeyeons 플러그인. 규칙·스킬이 말하는 scripts/…(dev.sh·검사기·도구)는 플러그인 폴더 ${root}/scripts에 있다. Bash로 부를 때는 이 절대 경로를 쓴다]"
for r in $RULES; do
	f="$root/rules/$r.md"
	[ -f "$f" ] || fail "rules/$r.md 없음"
	body=""; IFS= read -r -d '' body <"$f" || :
	[ -n "$body" ] || fail "rules/$r.md를 읽지 못했다"
	text="$text$nl$nl$body"
done

printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$(esc "$text")"
exit 0
