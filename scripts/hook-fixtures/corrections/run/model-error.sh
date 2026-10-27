#!/bin/sh
# 가짜 분석 모델 — 실행 중 오류 결과(error_during_execution)를 내고 실패 코드로 끝난다
cat >/dev/null
cat "$(dirname "$0")/result-error.json"
exit 1
