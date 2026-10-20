#!/bin/bash
# Blocks destructive shell commands. Registered in .claude/settings.json (PreToolUse/Bash).
# Hook input: JSON with "tool_input.command" field on stdin (Claude Code PreToolUse schema).
# 알려진 오탐: 패턴을 명령 문자열 전체에서 찾으므로 `grep "rm -rf" file`·`echo "git push --force"`처럼 문자열로만 언급해도 막힌다.
# fail-closed가 의도라 그대로 둔다 — 그런 명령은 사용자가 직접 실행한다. 패턴은 아래 PATTERNS 배열에 한 줄씩 둔다.

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

# 패턴 목록 — 한 줄에 하나, 전부 POSIX ERE. 늘리면 scripts/hook-cases.txt에 차단 케이스와 오탐 방지 케이스를 먼저 넣는다.
# 여기서 막지 못하는 것(규칙으로만 금지): 변수·eval·파일 간접 실행(`bash x.sh`), `truncate`, `: > file`, 언어 런타임의 삭제 호출.
# 이 훅은 문자열을 보는 하한선이고, 같은 값이 .claude/settings.json permissions.deny에도 있다(도구 권한 층 — 이중 방어).
PATTERNS=(
  # force push — 플래그가 remote·branch 뒤에 와도, +refspec도, --force-with-lease도 (안전한 변형이지만 사용자가 직접 실행하는 편이 낫다)
  'git push([[:space:]]+[^[:space:]]+)*[[:space:]]+(--force([^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*|\+[^[:space:]]+)([[:space:]]|$)'
  # 재귀 강제 삭제 — 플래그 순서·묶음·긴 형식 무관
  'rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*\b|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*\b|-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+-[a-zA-Z]*[fF][a-zA-Z]*\b|-[a-zA-Z]*[fF][a-zA-Z]*[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*\b|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
  # find 로 지우기 — -delete · -exec rm
  'find[[:space:]]+[^|;&]*(-delete([[:space:]]|$)|-exec[[:space:]]+rm([[:space:]]|$))'
  # git 이력·작업 트리 파괴 — hard reset · 강제 clean(dry-run -n 제외) · 브랜치 강제 삭제 · stash 폐기 · filter-branch
  'git reset --hard'
  'git clean([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)'
  'git[[:space:]]+branch([[:space:]]+[^[:space:]]+)*[[:space:]]+-[a-zA-Z]*D[a-zA-Z]*([[:space:]]|$)'
  'git[[:space:]]+stash[[:space:]]+(drop|clear)([[:space:]]|$)'
  'git[[:space:]]+filter-branch'
  # git 훅 우회 — pre-commit·commit-msg 검사를 건너뛰는 커밋
  'git[[:space:]]+commit([[:space:]]+[^[:space:]]+)*[[:space:]]+(--no-verify|-[a-zA-Z]*n[a-zA-Z]*)([[:space:]]|$)'
  # 시크릿 파일을 git에 넣기 — .env · .env.{local,production,...} (.env.example 같은 견본은 통과)
  'git[[:space:]]+(add|commit)([[:space:]]+[^[:space:]]+)*[[:space:]]+[^[:space:]]*\.env(\.(local|prod|production|dev|development|staging|test))?([[:space:]]|$)'
  # DB 파괴 — SQL DROP
  '[Dd][Rr][Oo][Pp][[:space:]]+([Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]|[Tt][Aa][Bb][Ll][Ee]|[Ss][Cc][Hh][Ee][Mm][Aa])[[:space:]]'
  # 컨테이너 볼륨 삭제
  'docker(-compose|[[:space:]]+compose)[[:space:]]+down([[:space:]]+[^[:space:]]+)*[[:space:]]+(-v|--volumes)([[:space:]]|$)'
  'docker[[:space:]]+(system[[:space:]]+prune([[:space:]]+[^[:space:]]+)*[[:space:]]+--volumes|volume[[:space:]]+(rm|prune))'
  # 원격 스크립트를 셸에 파이프 · 권한 전체 개방 · 블록 디바이스 덮어쓰기
  '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)'
  'chmod([[:space:]]+[^[:space:]]+)*[[:space:]]+-[a-zA-Z]*R[a-zA-Z]*([[:space:]]+[^[:space:]]+)*[[:space:]]+[0-7]*777([[:space:]]|$)'
  'dd[[:space:]]+[^|;&]*of=/dev/'
)
joined=$(printf '%s|' "${PATTERNS[@]}"); joined="${joined%|}"
if echo "$command" | grep -qE "$joined"; then
  echo "위험한 명령이 차단되었습니다 (force push · rm -rf · find -delete · git reset --hard/clean -f/branch -D/stash drop/filter-branch · git commit --no-verify · .env 커밋 · SQL DROP · 컨테이너 볼륨 삭제 · curl|sh · chmod -R 777 · dd of=/dev). Blocked by .claude/hooks/deny-dangerous-bash.sh — use safer alternatives or ask the user explicitly." >&2
  exit 2
fi

exit 0
