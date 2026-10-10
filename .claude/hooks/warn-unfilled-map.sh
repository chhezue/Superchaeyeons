#!/bin/bash
# Warns at session start when harness-map.md still has undecided flags (⬜) or slots left "(없음)" without a reason.
# Registered in .claude/settings.json (SessionStart). 경고만 한다 — SessionStart는 차단할 수 없다.
# 하네스를 붙인 뒤 `adopt`을 끝까지 돌리지 않으면 하네스가 절반만 작동한다는 사실을 매 세션 첫 줄에 보여 주는 장치다.
# Hook input: JSON (session_id, source) on stdin — 내용은 쓰지 않는다. stdout → 모델 컨텍스트에 추가된다.

# 훅은 프로젝트 루트에서 실행되지만, Claude Code가 주는 CLAUDE_PROJECT_DIR가 있으면 그것을 우선한다 (cwd 가정 제거).
map="${CLAUDE_PROJECT_DIR:-.}/.claude/rules/harness-map.md"
[ -f "$map" ] || exit 0

undecided=$(grep -c '| ⬜ |' "$map" 2>/dev/null || true)
# "(없음)" 뒤에 이유 없이 바로 셀이 끝나는 행만 센다 — "(없음) — DB 없음"처럼 이유가 붙은 것은 의도된 값이다
bare_none=$(grep -cE '\| \(없음\) \|' "$map" 2>/dev/null || true)
undecided=${undecided:-0}; bare_none=${bare_none:-0}

if [ "$undecided" -gt 0 ] || [ "$bare_none" -gt 0 ]; then
  echo "[하네스 · harness-map.md] 미결정 플래그(⬜) ${undecided}개, 이유 없는 (없음) 슬롯 ${bare_none}개가 남아 있습니다. 규칙이 그 슬롯·플래그를 요구하면 멈추고 사용자에게 물어야 합니다 (harness-map.md 규칙 2). 채우려면 \`adopt\` 스킬(재동기화)을 돌립니다."
fi
exit 0
