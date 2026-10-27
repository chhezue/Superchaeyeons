#!/bin/bash
# At session start, shows one line — sessions since the last retro analysis · correction memories queued · candidates to review.
# Registered in .claude/settings.json (SessionStart). 회고 루프가 사람의 기억에 기대지 않게 하는 알림이다.
#
# 한 줄을 사용자 화면(systemMessage)과 Claude(additionalContext)에 함께 낸다. 세 값이 모두 0이면 아무것도 내지 않는다 — 매 세션 토큰이 들지 않게.
#   세션 = 이 프로젝트 대화 기록 폴더(입력 transcript_path가 있는 폴더)에서 last-analysis보다 늦게 바뀐 *.jsonl 수, 지금 세션 제외
#   정정 기억 = 정정 대기열(queue.tsv) 줄 수 · 후보 = 후보 파일(candidates.md)에서 `### `로 시작하는 줄 수
# 대화 기록은 수정 시각만 보고 내용은 읽지 않는다. last-analysis가 없으면 분석을 한 번도 돌리지 않은 것이라 첫 실행 안내를 낸다.
# 상태 파일 형식은 scripts/analyze-corrections.sh 머리가 SSOT다.
#
# 훅 공통 규약의 예외: 알림용 훅이라 어떤 경우에도 exit 0. bash 3.2 내장 기능과 macOS 기본 명령만 쓴다.
# Hook input: JSON with "transcript_path" on stdin.
STORE="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/.claude/corrections"

input=$(cat)
dir=""; cur=""
if [[ $input =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
	dir="${BASH_REMATCH[1]%/*}"; cur="${BASH_REMATCH[1]##*/}"
fi
state="$STORE/last-analysis"

sessions=0
if [ -n "$dir" ] && [ -d "$dir" ]; then
	if [ -f "$state" ]; then
		list="$(find "$dir" -maxdepth 1 -type f -name '*.jsonl' ! -name "$cur" -newer "$state" 2>/dev/null)"
	else
		list="$(find "$dir" -maxdepth 1 -type f -name '*.jsonl' ! -name "$cur" 2>/dev/null)"
	fi
	[ -n "$list" ] && sessions="$(printf '%s\n' "$list" | grep -c '')"
fi
queued=0
[ -f "$STORE/queue.tsv" ] && queued="$(grep -c '' "$STORE/queue.tsv" 2>/dev/null)"
candidates=0
[ -f "$STORE/candidates.md" ] && candidates="$(grep -c '^### ' "$STORE/candidates.md" 2>/dev/null)"

[ "$sessions" = 0 ] && [ "$queued" = 0 ] && [ "$candidates" = 0 ] && exit 0

counts="세션 ${sessions}개 · 정정 기억 ${queued}건 · 검토할 후보 ${candidates}건"
if [ -f "$state" ]; then
	when="$(head -1 "$state" 2>/dev/null)"; when="${when%%T*}"; when="${when//[^0-9-]/}"
	line="[회고] 마지막 회고 분석(${when:-날짜 모름}) 뒤 $counts"
else
	line="[회고] 회고 분석을 한 번도 돌리지 않았다 — $counts"
fi
if [ "$candidates" != 0 ]; then
	line="$line — improve-harness 스킬로 검토"
	hint="검토할 후보가 있으니 사용자에게 improve-harness 스킬을 제안한다."
else
	line="$line — scripts/analyze-corrections.sh로 분석"
	hint="분석은 사용자가 따로 돌린다. 이 세션에서 돌리지 않는다."
fi
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s %s"}}\n' "$line" "$line" "$hint"
exit 0
