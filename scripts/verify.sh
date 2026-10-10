#!/usr/bin/env bash
# 이 저장소의 {{테스트 명령}} — 기계 검증 3개를 순서대로 돌리고 하나라도 실패하면 exit 1.
#   1. scripts/check-portability.sh   배달물 부품 계약 · always-load 예산
#   2. scripts/test-hooks.sh          훅 공통 규약 (케이스 파일 + python3 부재 fail-closed)
#   3. scripts/check-doc-style.sh     문서 스타일 (추적·미추적 .md 전부, 오류만 판정)
# harness-map.md {{테스트 명령}}과 deny-unverified-completion.sh의 TEST_CMD가 이 파일을 가리킨다.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
status=0
for step in "scripts/check-portability.sh" "scripts/test-hooks.sh" "scripts/check-doc-style.sh --all"; do
	echo "▶ $step"
	# shellcheck disable=SC2086
	if ! $step; then status=1; echo "  ✗ 실패: $step"; fi
	echo
done
[ "$status" -eq 0 ] && echo "verify: 전부 통과" || echo "verify: 실패 있음"
exit "$status"
