#!/bin/bash
# 설정 값 주입 — 세션 시작(시작·/clear·요약 뒤)과 서브에이전트 시작에 프로젝트 설정(.claude/harness.conf)의 slot·flag 값을 표로 넣는다.
# Registered in plugin/hooks/hooks.json (SessionStart matcher startup|clear|compact · SubagentStart).
# 규칙은 경로·명령을 {{슬롯}}, 정책을 [플래그: 이름]으로 부르고, 이 표가 실제 값을 잇는다. 규칙 주입(auto-inject-rules.sh)과 훅을
# 나눈 것은 훅 하나의 출력 상한(1만 자)을 나눠 쓰기 위해서다 — 두 훅은 서로의 출력에 기대지 않는다(같은 이벤트 훅은 순서가 없다).
# 키 목록·이름·종류는 플러그인 scripts/harness-keys.txt가 SSOT다(slot·flag·info만 표에 넣는다. hook 키는 훅이 직접 읽는다).
#
# init 자동 시작: 설정 파일이 없거나 slot·flag 키가 빈칸({…} 한 쌍)이거나 빠졌으면 표 대신 "하네스 설정이 비어 있다"와
# init-harness 제안을 넣고, 같은 알림을 systemMessage(사용자 화면)에도 낸다. 빈칸이면 어느 키인지 적는다.
# 서브에이전트: 에이전트 파일 머리에 omitClaudeMd: true가 있는 플러그인 에이전트는 뺀다(auto-inject-rules.sh와 같다).
# 막지 않는다 — 어떤 입력에도 exit 0. 입력을 해석하지 못하면 systemMessage만 낸다. bash 3.2 내장 기능만 쓴다.
# Hook input: JSON with "hook_event_name", "agent_type"(SubagentStart) on stdin.
EMPTY="하네스 설정이 비어 있다"

esc() {
	local s=$1
	s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
	printf '%s' "$s"
}
field() {
	[[ $input =~ \"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}" || :
}
say() { # say <사용자에게 보일 글> <Claude에게 넣을 글>
	printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$(esc "$1")" "$event" "$(esc "$2")"
	exit 0
}

input=""
IFS= read -r -d '' input || :
event="$(field hook_event_name)"
case "$event" in
SessionStart | SubagentStart) ;;
*) printf '{"systemMessage":"%s"}\n' "하네스 설정을 싣지 못했다 — 훅 입력을 해석하지 못했다"; exit 0 ;;
esac

root="${CLAUDE_PLUGIN_ROOT:-${0%/*}/..}"
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
fi

keys_file="$root/scripts/harness-keys.txt"
[ -f "$keys_file" ] || say "하네스 설정을 싣지 못했다 — 키 목록이 없다 ($keys_file)" "하네스 설정을 싣지 못했다 — 키 목록(scripts/harness-keys.txt)이 없어 {{슬롯}} 값을 알 수 없다. 사용자에게 알린다."

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
conf="$proj/.claude/harness.conf"
hint="다른 작업 전에 사용자에게 init-harness 스킬로 하네스 설정(.claude/harness.conf)을 채우자고 제안하라."
[ -f "$conf" ] || say "$EMPTY — .claude/harness.conf가 없다. init-harness로 채운다" "$EMPTY (.claude/harness.conf 없음). $hint"

# 설정 읽기 — 키=값 줄만 값으로 본다(깨진 줄은 deny-* 훅이 막고, 여기서는 표에 넣지 않는다)
keys=" "
while IFS= read -r line || [ -n "$line" ]; do
	line="${line%$'\r'}"
	[[ $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
	printf -v "v_${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
	keys="$keys${BASH_REMATCH[1]} "
done <"$conf"

table="| 이름 | 값 |$nl|---|---|"
blank=""
while IFS=$'\t' read -r key kind label _; do
	case "$key" in '' | '#'*) continue ;; esac
	case "$kind" in slot | flag | info) ;; *) continue ;; esac
	name="v_$key"
	case "$keys" in *" $key "*) val="${!name}" ;; *) val="{없음}" ;; esac
	if [[ $val =~ ^\{[^{}]*\}$ ]]; then
		[ "$kind" = "info" ] || blank="$blank $key"
		continue
	fi
	case "$kind" in
	slot) table="$table$nl| \`$label\` | $val |" ;;
	flag) table="$table$nl| 플래그 $label | $val |" ;;
	info) table="$table$nl| $label | $val |" ;;
	esac
done <"$keys_file"

[ -z "$blank" ] || say "$EMPTY — 빈칸:$blank. init-harness로 채운다" "$EMPTY (빈칸:$blank). $hint"

text="[하네스 설정 — .claude/harness.conf. 규칙의 {{슬롯}}은 아래 값이고, [플래그: 이름] 절은 값이 1일 때만 적용한다. 값이 \"(없음)\"인 슬롯을 규칙이 요구하면 멈추고 묻는다]$nl$table"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$(esc "$text")"
exit 0
