#!/bin/sh
# 가짜 분석 모델 — JSON 없이 stderr 메시지만 내고 죽는다
cat >/dev/null
echo "model crashed" >&2
exit 1
