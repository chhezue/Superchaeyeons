#!/bin/sh
# 가짜 분석 모델 — 프롬프트를 읽고 result-mixed.json(후보 10건)을 그대로 낸다
cat >/dev/null
cat "$(dirname "$0")/result-mixed.json"
