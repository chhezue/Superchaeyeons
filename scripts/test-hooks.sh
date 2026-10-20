#!/usr/bin/env bash
# 훅 테스트 — .claude/hooks/*.sh 가 훅 공통 규약(정상 통과 · 위반 차단 · 판정 불가 차단)을 지키는지 케이스 파일로 판정하고,
# 훅이 .claude/settings.json 에 실제로 등록돼 있는지(등록 파일이 실존·실행 가능한지) 대조한다.
#
# 사용:
#   scripts/test-hooks.sh                  # scripts/hook-cases.txt 전부 + python3 부재 내장 케이스 + 등록 대조
#   scripts/test-hooks.sh local-deny-db-migration.sh   # 그 훅의 케이스만 (케이스가 0건이면 exit 2 — 이름 오타를 무음 통과로 두지 않는다)
#
# exit 0 = 전부 통과 · exit 1 = 실패 있음 · exit 2 = 사용법·환경 오류
# 케이스 형식은 scripts/hook-cases.txt 머리에 있다. 훅을 고치거나 새 우회 경로를 발견하면 케이스를 먼저 추가한다.
# (부품성 원칙: bash 하나 + 데이터 파일 하나. 훅 본문에 테스트용 분기를 넣지 않는다 — SCOPE·HARNESS_SELF_EDIT는 임시 복사본에서 치환한다.)

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

cases_file="scripts/hook-cases.txt"
hooks_dir=".claude/hooks"
settings_file=".claude/settings.json"
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
	# scope 열: `-` 원본 · `값` SCOPE 치환 · `값;self=N` HARNESS_SELF_EDIT도 치환
	scope_val="${scope%%;*}"; extra=""; [ "$scope" != "$scope_val" ] && extra="${scope#*;}"
	if [ "$scope" != "-" ]; then
		run="$tmpdir/$hook.$n"
		sed "s|^SCOPE=\".*\"|SCOPE=\"$scope_val\"|" "$src" >"$run"
		case "$extra" in
		self=*) sed -i.bak "s|^HARNESS_SELF_EDIT=\".*\"|HARNESS_SELF_EDIT=\"${extra#self=}\"|" "$run" && rm -f "$run.bak" ;;
		esac
		chmod +x "$run"
	fi
	stdin="${stdin//\$REPO/$repo_root}"
	stdin="${stdin//\$HOME/$HOME}"
	printf '%s' "$stdin" | "$run" >/dev/null 2>"$tmpdir/err"
	actual=$?
	label="$stdin"; [ -z "$label" ] && label="(빈 입력)"
	if [ "$actual" = "$expected" ]; then
		pass=$((pass + 1))
		printf '  ok    %-28s scope=%-8s exit=%s  %s\n' "$hook" "$scope" "$actual" "${label:0:70}"
	else
		fail=$((fail + 1))
		printf '  FAIL  %-28s scope=%-8s exit=%s (기대 %s)  %s\n' "$hook" "$scope" "$actual" "$expected" "${label:0:70}"
		sed 's/^/          stderr: /' "$tmpdir/err" | head -3
	fi
done <"$cases_file"

if [ -n "$only" ] && [ "$n" -eq 0 ]; then
	echo "FAIL: '$only' 케이스가 0건입니다 — 훅 이름 오타이거나 케이스 파일에 절이 없습니다. 통과로 치지 않습니다." >&2
	exit 2
fi

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
			pass=$((pass + 1)); printf '  ok    %-28s scope=-        exit=%s  (python3 없음 → 차단)\n' "$hook" "$actual"
		else
			fail=$((fail + 1)); printf '  FAIL  %-28s scope=-        exit=%s (기대 2)  (python3 없음인데 통과 — fail-open)\n' "$hook" "$actual"
			sed 's/^/          stderr: /' "$tmpdir/err" | head -3
		fi
	done
fi

# ---- 내장 케이스: 훅 등록 대조 ---------------------------------------------------
# 훅은 settings.json에 등록돼야 존재한다. (1) .claude/hooks/*.sh 전부가 등록돼 있고 (2) 등록된 command 경로가 실존·실행 가능해야 한다.
# 등록만 지운 커밋이 검사기를 통과했던 사고(2026-09-07 감사 실험 B)가 계기다. 씨앗 훅은 복사 전이라 대상이 아니다.
if [ -z "$only" ]; then
	n=$((n + 1))
	registry_out="$(HOOKS_DIR="$hooks_dir" python3 - "$settings_file" <<'PY'
import glob, json, os, re, sys
settings_path = sys.argv[1]
hooks_dir = os.environ["HOOKS_DIR"]
problems = []
try:
    cfg = json.load(open(settings_path, encoding="utf-8"))
except Exception as e:
    print(f"settings.json 을 읽지 못함: {e}"); sys.exit(1)
registered = set()
for event, entries in (cfg.get("hooks") or {}).items():
    for entry in entries or []:
        for h in entry.get("hooks") or []:
            cmd = h.get("command") or ""
            m = re.search(r"\.claude/hooks/([^\s\"']+)", cmd)
            if not m:
                continue
            name = m.group(1)
            registered.add(name)
            p = os.path.join(hooks_dir, name)
            if not os.path.isfile(p):
                problems.append(f"{event}: 등록된 훅 파일이 없음 — {p}")
            elif not os.access(p, os.X_OK):
                problems.append(f"{event}: 등록된 훅에 실행 권한이 없음 — {p}")
for p in sorted(glob.glob(os.path.join(hooks_dir, "*.sh"))):
    name = os.path.basename(p)
    if name not in registered:
        problems.append(f"훅 파일이 settings.json 에 등록돼 있지 않음 — {p}")
for line in problems:
    print(line)
sys.exit(1 if problems else 0)
PY
)"
	if [ $? -eq 0 ]; then
		pass=$((pass + 1)); printf '  ok    %-28s scope=-        exit=0  (settings.json 등록 = 훅 파일)\n' "(등록 대조)"
	else
		fail=$((fail + 1)); printf '  FAIL  %-28s scope=-        (settings.json 등록과 훅 파일이 어긋남)\n' "(등록 대조)"
		printf '%s\n' "$registry_out" | sed 's/^/          /'
	fi
fi

echo
echo "케이스 $n · 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
