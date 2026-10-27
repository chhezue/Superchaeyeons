#!/bin/sh
# 가짜 분석 모델 — 비용 상한에 걸린 결과(error_max_budget_usd, 2.07달러)를 내고 실패 코드로 끝난다
cat >/dev/null
cat "$(dirname "$0")/result-budget.json"
exit 1
