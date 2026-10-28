#!/bin/sh
# 가짜 분석 모델 — 프롬프트를 읽고 result-tidy.json(근거 정리 후보 4건)을 그대로 낸다
cat >/dev/null
cat "$(dirname "$0")/result-tidy.json"
