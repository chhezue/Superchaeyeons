#!/bin/bash
# check-portability.sh 예산 케이스용 — 견본 저장소(root/)를 $1에 만들고 검사기를 거기서 돌려 예산 절만 출력한다.
# 견본에는 README·harness-map이 없어 다른 검사는 위반을 내지만 이 케이스는 예산 줄만 본다. $2 = 상한(바이트)
# 검사기는 플러그인 모양(plugin/scripts/)으로 복사하고, 검사 대상은 현재 폴더(git 밖이라 그대로 프로젝트)라 견본 폴더에서 부른다.
d="$1"; here="$(cd "$(dirname "$0")" && pwd)"; src="$(cd "$here/../../.." && pwd)"
mkdir -p "$d/plugin/scripts"
cp -R "$here/root/." "$d/"
cp "$src/plugin/scripts/check-portability.sh" "$src/plugin/scripts/portability-patterns.txt" "$d/plugin/scripts/"
(cd "$d" && "$d/plugin/scripts/check-portability.sh" --budget "${2:-25000}" 2>&1) | sed -n '/always-load 예산/,$p'
exit 0
