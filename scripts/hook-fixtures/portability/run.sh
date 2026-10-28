#!/bin/bash
# check-portability.sh 예산 케이스용 — 견본 저장소(root/)를 $1에 만들고 검사기를 거기서 돌려 예산 절만 출력한다.
# 견본에는 README·harness-map이 없어 다른 검사는 위반을 내지만 이 케이스는 예산 줄만 본다. $2 = 상한(바이트)
d="$1"; here="$(cd "$(dirname "$0")" && pwd)"; src="$(cd "$here/../../.." && pwd)"
mkdir -p "$d/scripts"
cp -R "$here/root/." "$d/"
cp "$src/scripts/check-portability.sh" "$src/scripts/portability-patterns.txt" "$d/scripts/"
"$d/scripts/check-portability.sh" --budget "${2:-25000}" 2>&1 | sed -n '/always-load 예산/,$p'
exit 0
