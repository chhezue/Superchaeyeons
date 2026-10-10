#!/bin/bash
# Blocks destructive shell commands. Registered in .claude/settings.json (PreToolUse/Bash).
# Hook input: JSON with "tool_input.command" field on stdin (Claude Code PreToolUse schema).
# 알려진 오탐: 패턴을 명령 문자열 전체에서 찾으므로 `grep "rm -rf" file`·`echo "git push --force"`처럼 문자열로만 언급해도 막힌다.
# fail-closed가 의도라 그대로 둔다 — 그런 명령은 사용자가 직접 실행한다.

# 훅 공통 규약: 판정 불가(JSON 깨짐·command 키 없음·빈 입력) = 차단. scripts/test-hooks.sh가 케이스 파일로 판정한다.

input=$(cat)

# python3 자체가 없거나 죽으면(exit ≠ 0) command가 빈 문자열이 되어 통과해 버린다 — 그 경우도 판정 불가로 본다.
command=$(python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print((data.get('tool_input', {}) or {}).get('command') or '__UNPARSEABLE__')
except Exception:
    print('__UNPARSEABLE__')
" <<< "$input" 2>/dev/null) || command="__UNPARSEABLE__"

if [ "$command" = "__UNPARSEABLE__" ] || [ -z "$command" ]; then
  echo "실행할 명령을 판정할 수 없어 차단합니다 (입력 JSON 또는 command 없음, 또는 python3 없음). 훅 공통 규약: 판정 불가 = 차단. Blocked by .claude/hooks/deny-dangerous-bash.sh." >&2
  exit 2
fi

# Patterns: force push (플래그가 remote·branch 뒤에 와도, +refspec 강제 푸시도), recursive delete (any flag order/combination),
# hard reset, prod DB wipe. --force-with-lease도 막는다 — 안전한 변형이지만 사용자가 직접 실행하는 편이 낫다.
if echo "$command" | grep -qE \
  'git push([[:space:]]+[^[:space:]]+)*[[:space:]]+(--force([^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*|\+[^[:space:]]+)([[:space:]]|$)|rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*\b|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*\b|-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+-[a-zA-Z]*[fF][a-zA-Z]*\b|-[a-zA-Z]*[fF][a-zA-Z]*[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*\b|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)|git reset --hard|docker compose down -v|docker-compose down -v'; then
  echo "위험한 명령이 차단되었습니다 (force push, rm -rf, hard reset, docker compose down -v). Blocked by .claude/hooks/deny-dangerous-bash.sh — use safer alternatives or ask the user explicitly." >&2
  exit 2
fi

exit 0
