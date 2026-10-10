#!/usr/bin/env bash
# 훅 테스트 — .claude/hooks/*.sh 가 훅 공통 규약(정상 통과 · 위반 차단 · 판정 불가 차단)을 지키는지 케이스 파일로 판정한다.
#
# 사용:
#   scripts/test-hooks.sh                  # scripts/hook-cases.txt 전부
#   scripts/test-hooks.sh local-deny-db-migration.sh   # 그 훅의 케이스만
#
# exit 0 = 전부 통과 · exit 1 = 실패 있음 · exit 2 = 사용법·환경 오류
# 케이스 형식은 scripts/hook-cases.txt 머리에 있다. 훅을 고치거나 새 우회 경로를 발견하면 케이스를 먼저 추가한다.
# (부품성 원칙: bash 하나 + 데이터 파일 하나. 훅 본문에 테스트용 분기를 넣지 않는다 — SCOPE는 임시 복사본에서 치환한다.)

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

cases_file="scripts/hook-cases.txt"
hooks_dir=".claude/hooks"
only="${1:-}"
[ -f "$cases_file" ] || { echo "FAIL: 케이스 파일이 없습니다 — $cases_file" >&2; exit 2; }

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/hook-test.XXXXXX")"
trap 'rm -r -- "$tmpdir"' EXIT

pass=0; fail=0; n=0
while IFS=$'\t' read -r hook scope expected stdin; do
	case "$hook" in ''|'#'*) continue ;; esac
	[ -n "$only" ] && [ "$hook" != "$only" ] && continue
	n=$((n + 1))
	src="$hooks_dir/$hook"
	if [ ! -f "$src" ]; then
		# 배달물에 없으면 씨앗(examples/seeds/*/hooks/)에서 찾는다 — 씨앗 훅도 같은 규약을 지켜야 한다
		for cand in examples/seeds/*/hooks/"$hook"; do [ -f "$cand" ] && src="$cand" && break; done
	fi
	if [ ! -f "$src" ]; then
		printf '  FAIL  %-28s (훅 파일 없음)\n' "$hook"; fail=$((fail + 1)); continue
	fi
	run="$src"
	if [ "$scope" != "-" ]; then
		run="$tmpdir/$hook.$n"
		sed "s|^SCOPE=\".*\"|SCOPE=\"$scope\"|" "$src" >"$run"
		chmod +x "$run"
	fi
	stdin="${stdin//\$REPO/$repo_root}"
	stdin="${stdin//\$HOME/$HOME}"
	printf '%s' "$stdin" | "$run" >/dev/null 2>"$tmpdir/err"
	actual=$?
	label="$stdin"; [ -z "$label" ] && label="(빈 입력)"
	if [ "$actual" = "$expected" ]; then
		pass=$((pass + 1))
		printf '  ok    %-28s scope=%-4s exit=%s  %s\n' "$hook" "$scope" "$actual" "${label:0:70}"
	else
		fail=$((fail + 1))
		printf '  FAIL  %-28s scope=%-4s exit=%s (기대 %s)  %s\n' "$hook" "$scope" "$actual" "$expected" "${label:0:70}"
		sed 's/^/          stderr: /' "$tmpdir/err" | head -3
	fi
done <"$cases_file"

# ---- 내장 케이스: python3 부재 ---------------------------------------------------
# 모든 deny-* 훅은 python3가 없어도(= 판정 불가) 차단해야 한다. PATH 맨 앞에 exit 127 하는 python3 가짜를 두고 위반 입력을 넣는다.
# Stop 훅(deny-unverified-completion)은 판정 불가 = 통과가 명시적 예외라 제외한다. 케이스 파일로는 PATH를 바꿀 수 없어 여기 둔다.
if [ -z "$only" ] || [[ "$only" == *deny-* ]]; then
	mkdir -p "$tmpdir/nopy"
	printf '#!/bin/sh\nexit 127\n' >"$tmpdir/nopy/python3"; chmod +x "$tmpdir/nopy/python3"
	for src in "$hooks_dir"/deny-*.sh "$hooks_dir"/local-deny-*.sh examples/seeds/*/hooks/local-deny-*.sh examples/seeds/*/hooks/deny-*.sh; do
		[ -f "$src" ] || continue
		hook="$(basename "$src")"
		case "$hook" in deny-unverified-completion.sh) continue ;; esac
		[ -n "$only" ] && [ "$hook" != "$only" ] && continue
		n=$((n + 1))
		run="$tmpdir/$hook.nopy"
		sed 's|^SCOPE="\.\"|SCOPE="sub"|' "$src" >"$run"; chmod +x "$run"
		printf '%s' '{"tool_input":{"command":"rm -rf /","file_path":"other/V1__x.sql"}}' | PATH="$tmpdir/nopy:$PATH" "$run" >/dev/null 2>"$tmpdir/err"
		actual=$?
		if [ "$actual" = "2" ]; then
			pass=$((pass + 1)); printf '  ok    %-28s scope=-    exit=%s  (python3 없음 → 차단)\n' "$hook" "$actual"
		else
			fail=$((fail + 1)); printf '  FAIL  %-28s scope=-    exit=%s (기대 2)  (python3 없음인데 통과 — fail-open)\n' "$hook" "$actual"
			sed 's/^/          stderr: /' "$tmpdir/err" | head -3
		fi
	done
fi

echo
echo "케이스 $n · 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
