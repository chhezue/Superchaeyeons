#!/usr/bin/env bash
# 이 저장소의 {{테스트 명령}} — 기계 검증 3개를 순서대로 돌리고 하나라도 실패하면 exit 1.
#   1. scripts/check-portability.sh   배달물 부품 계약 · 슬롯·구성 요소 목록 대조 · always-load 예산
#   2. scripts/test-hooks.sh          훅 공통 규약 (케이스 파일 + python3 부재 fail-closed + 등록·매처 대조)
#   3. scripts/check-doc-style.sh     문서 스타일 (추적·미추적 .md 전부, 오류만 판정)
# harness-map.md {{테스트 명령}}과 deny-unverified-completion.sh의 TEST_CMD가 이 파일을 가리킨다.
#
# 출력: 통과한 단계는 마지막 요약 줄만, 실패한 단계는 전체 출력을 보인다. 이 명령은 코드 편집 뒤마다 돌기 때문에
# 통과 출력(케이스 100여 줄 · 문서 경고 수십 줄)이 매번 컨텍스트에 쌓이지 않게 한다. 전체를 보려면 VERIFY_VERBOSE=1.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
verbose="${VERIFY_VERBOSE:-0}"
status=0
for step in "scripts/check-portability.sh" "scripts/test-hooks.sh" "scripts/check-doc-style.sh --all"; do
	# shellcheck disable=SC2086
	out="$($step 2>&1)"
	rc=$?
	if [ "$rc" -eq 0 ]; then
		if [ "$verbose" = "1" ]; then
			echo "▶ $step"; printf '%s\n\n' "$out"
		else
			echo "  ✓ $step — $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)"
		fi
	else
		status=1
		echo "▶ $step"
		printf '%s\n' "$out"
		echo "  ✗ 실패: $step"
		echo
	fi
done
[ "$status" -eq 0 ] && echo "verify: 전부 통과" || echo "verify: 실패 있음"
exit "$status"
