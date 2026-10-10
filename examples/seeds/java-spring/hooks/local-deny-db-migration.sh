#!/bin/bash
# Blocks creating DB migration files. Gated by harness-map.md 능력 플래그 'DB 마이그레이션 금지'.
# [플래그: DB 마이그레이션 금지] local-spring-boot-java.md "DB 스키마 정책" — no prod-preserved data; schema SSOT is JPA entities + ddl-auto, not migration files.
# 플래그를 끄면 .claude/settings.json에서 이 훅 등록을 지운다 (규칙 절은 지우지 않는다).
# Hook input: JSON with "tool_input.file_path" (Write/Edit) or "tool_input.notebook_path" on stdin.
# 훅 공통 규약: 판정 불가(JSON 깨짐·경로 키 없음·빈 입력) = 차단. scripts/test-hooks.sh가 케이스 파일로 판정한다.

input=$(cat)

# python3 자체가 없거나 죽으면(exit ≠ 0) file_path가 빈 문자열이 되어 통과해 버린다 — 그 경우도 판정 불가로 본다.
file_path=$(python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    ti = data.get('tool_input', {}) or {}
    print(ti.get('file_path') or ti.get('notebook_path') or '__UNPARSEABLE__')
except Exception:
    print('__UNPARSEABLE__')
" <<< "$input" 2>/dev/null) || file_path="__UNPARSEABLE__"

if [ "$file_path" = "__UNPARSEABLE__" ] || [ -z "$file_path" ]; then
  echo "쓰기 대상 경로를 판정할 수 없어 차단합니다 (입력 JSON 또는 file_path 없음, 또는 python3 없음). 훅 공통 규약: 판정 불가 = 차단. Blocked by .claude/hooks/local-deny-db-migration.sh." >&2
  exit 2
fi

# Patterns: Flyway/Liquibase migration dir, or Flyway naming convention (V1__x.sql, R__x.sql) anywhere
if echo "$file_path" | grep -qE '/db/migration/|/(V[0-9]+(\.[0-9]+)*|R)__[^/]*\.sql$'; then
  echo "Flyway/Liquibase 마이그레이션 파일 생성이 차단되었습니다 (local-spring-boot-java.md 'DB 스키마 정책' 절 — 상용 보존 데이터 없음, 스키마 SSOT는 JPA 엔티티 + ddl-auto). Blocked by .claude/hooks/local-deny-db-migration.sh — 정말 필요하면 사용자에게 먼저 확인하세요." >&2
  exit 2
fi

exit 0
