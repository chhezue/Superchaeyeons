#!/bin/sh
# 키 문자열이 파일에 남았는지 검사하는 시험 보조 — 사용: assert-no-key.sh <ROOT 복사본> <키 문자열>
# 상태 폴더(.claude/polish)가 비어 있으면 검사가 의미 없으므로 실패로 본다. 키가 한 파일이라도 있으면 파일 이름만 출력하고(키는 출력하지 않는다) exit 1
dir="${1:-}"; key="${2:-}"
[ -n "$dir" ] && [ -n "$key" ] || { echo "사용법: assert-no-key.sh <폴더> <키>"; exit 2; }
[ -n "$(ls -A "$dir/.claude/polish" 2>/dev/null)" ] || { echo "상태 폴더가 비어 있거나 없음 — 검사가 의미 없음: $dir/.claude/polish"; exit 1; }
if grep -rqF -- "$key" "$dir"; then
	echo "키 문자열이 남아 있음:"
	grep -rlF -- "$key" "$dir" | head -3
	exit 1
fi
exit 0
