#!/bin/bash
# Injects a reminder to run the `ask` skill when the user's prompt is an open-ended request. Registered in
# .claude/settings.json (UserPromptSubmit). 주입만 하고 차단하지 않는다 — UserPromptSubmit에서 exit 2는 프롬프트를
# 지워 버려 오탐 대가가 너무 크다. core-gates.md "멈추는 신호 — 열린 표현"의 결정론적 알림 장치다.
#
# 언어가 다른 프로젝트는 아래 두 변수만 바꾼다. (훅 공통 규약의 예외: 이 훅은 deny-가 아니라 ask-라 판정 불가면 조용히 통과)
OPEN_PATTERNS='알아서|적당히|최적화(해|하|좀)|개선(해|하|좀)|정리(해|좀) ?줘|리팩터(링)? ?(좀|해)|더 (낫|좋)게|깔끔하게|전반적으로|보기 좋게'
SMALL_FIX_PATTERNS='오타|typo|한 줄|한줄|이름만|주석만|로그 한|버전만'
#
# Hook input: JSON with "prompt" on stdin. stdout → 모델 컨텍스트에 추가된다.

input=$(cat)
prompt=$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('prompt', '') or '')
except Exception:
    print('')
" <<< "$input")

[ -z "$prompt" ] && exit 0
echo "$prompt" | grep -qE "$SMALL_FIX_PATTERNS" && exit 0
echo "$prompt" | grep -qE "$OPEN_PATTERNS" || exit 0

cat <<'EOF'
[하네스 · core-gates.md] 이 요청에는 열린 표현이 있습니다("알아서·적당히·최적화·개선" 류). 구현을 시작하기 전에 `ask` 스킬로 한 라운드를 먼저 돕니다 — 코드·설정으로 확인할 수 있는 사실은 직접 조사하고, 사용자만 답할 수 있는 결정만 번호를 붙여 묻습니다. 이미 Approved 스펙이 있는 작업이거나 사용자가 "질문 없이 진행"이라고 했으면 이 알림을 무시합니다.
EOF
exit 0
