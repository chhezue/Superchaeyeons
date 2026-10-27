#!/bin/bash
# Appends a line to the correction queue when the agent saves a correction memory (an agent memory whose header says `type: feedback`).
# Registered in .claude/settings.json (PostToolUse Write|Edit|MultiEdit|NotebookEdit). 회고 루프의 "기록" 단계 — 모델에 아무것도 넣지 않는다(비용 0).
#
# 대기열 한 줄: 날짜<TAB>세션 ID<TAB>기억 파일 이름<TAB>그 파일의 description<TAB>횟수.
# 같은 파일이 다시 쓰이면 새 줄을 더하지 않고 횟수만 올린다. scripts/analyze-corrections.sh가 이 파일을 읽고, 정기 분석이 성공하면 분석한 줄을 지운다.
# 기억 폴더는 경로 모양(`…/.claude/projects/<프로젝트>/memory/*.md`)과 파일 머리로 판정한다 — 사용자 표현에 기대지 않는다.
#
# 훅 공통 규약의 예외: 기록용 훅이라 어떤 경우에도 작업을 막지 않는다(exit 0). 대신 입력을 읽지 못하거나 대기열에 쓰지 못하면
# systemMessage로 알린다 — 조용히 빠지면 루프 입력이 빈다.
# bash 3.2 내장 기능과 macOS 기본 명령만 쓴다(python3 없는 컴퓨터에서도 기록이 빠지지 않게).
# STORE는 .gitignore 대상이다(정정 기억 설명이 들어간다).
# Hook input: JSON with "session_id", "tool_input.file_path" on stdin.
STORE="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/.claude/corrections"

warn() {
	printf '{"systemMessage":"[회고 기록] 정정 대기열에 쓰지 못했다 — %s"}\n' "$1"
	exit 0
}

input=$(cat)
if [[ $input =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
	path="${BASH_REMATCH[1]}"
elif [[ $input =~ \"notebook_path\" ]]; then
	exit 0
else
	warn "훅 입력에서 파일 경로를 읽지 못함"
fi

case "$path" in */.claude/projects/*/memory/*.md) ;; *) exit 0 ;; esac
[ "${path##*/}" = "MEMORY.md" ] && exit 0
[ -f "$path" ] || exit 0

# 파일 머리(첫 줄 `---`부터 다음 `---`까지)에서 type·description을 읽는다. type은 최상위든 metadata 아래든 받는다
type=""; desc=""; n=0
while IFS= read -r line || [ -n "$line" ]; do
	n=$((n + 1))
	if [ "$n" -eq 1 ]; then
		[ "$line" = "---" ] || break
		continue
	fi
	[ "$line" = "---" ] && break
	if [[ $line =~ ^[[:space:]]*type:[[:space:]]*([A-Za-z_-]+)[[:space:]]*$ ]]; then
		type="${BASH_REMATCH[1]}"
	elif [[ $line =~ ^description:[[:space:]]*(.*)$ ]]; then
		desc="${BASH_REMATCH[1]}"
	fi
done <"$path"
[ "$type" = "feedback" ] || exit 0

name="${path##*/}"
sid="-"
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid="${BASH_REMATCH[1]}"
desc="${desc//$'\t'/ }"
[ -n "$desc" ] || desc="-"   # 빈 칸이 있으면 탭으로 나눌 때 열이 당겨진다
today="$(date +%Y-%m-%d)"

mkdir -p "$STORE" 2>/dev/null || warn "폴더를 만들지 못함: $STORE"
queue="$STORE/queue.tsv"
tmp="$(mktemp "$STORE/.queue.XXXXXX" 2>/dev/null)" || warn "임시 파일을 만들지 못함: $STORE"
found=0
if [ -f "$queue" ]; then
	while IFS=$'\t' read -r d s f de c; do
		[ -n "$d" ] || continue
		if [ "$f" = "$name" ] && [ "$found" -eq 0 ]; then
			case "$c" in '' | *[!0-9]*) c=0 ;; esac
			c=$((c + 1)); found=1
		fi
		printf '%s\t%s\t%s\t%s\t%s\n' "$d" "$s" "$f" "$de" "$c"
	done <"$queue" >"$tmp" || { rm -f "$tmp"; warn "대기열을 읽지 못함: $queue"; }
fi
[ "$found" -eq 1 ] || printf '%s\t%s\t%s\t%s\t1\n' "$today" "$sid" "$name" "$desc" >>"$tmp"
mv "$tmp" "$queue" 2>/dev/null || { rm -f "$tmp"; warn "대기열을 바꾸지 못함: $queue"; }
exit 0
