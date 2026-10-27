#!/usr/bin/env bash
# 훅 테스트 — .claude/hooks/*.sh 가 훅 공통 규약(정상 통과 · 위반 차단 · 판정 불가 차단)을 지키는지 케이스 파일로 판정하고,
# 훅이 .claude/settings.json 에 실제로 등록돼 있는지(등록 파일이 실존·실행 가능한지, 쓰기 도구 매처가 빠짐없는지) 대조한다.
#
# 사용:
#   scripts/test-hooks.sh                  # scripts/hook-cases.txt 전부 + python3 부재 내장 케이스 + 등록 대조
#   scripts/test-hooks.sh local-deny-db-migration.sh   # 그 훅의 케이스만 (케이스가 0건이면 exit 2 — 이름 오타를 무음 통과로 두지 않는다)
#
# exit 0 = 전부 통과 · exit 1 = 실패 있음 · exit 2 = 사용법·환경 오류
# 케이스 형식은 scripts/hook-cases.txt 머리에 있다. 훅을 고치거나 새 우회 경로를 발견하면 케이스를 먼저 추가한다.
# (부품성 원칙: bash 하나 + 데이터 파일 하나. 훅 본문에 테스트용 분기를 넣지 않는다 — SCOPE·HARNESS_SELF_EDIT·TEST_CMD와 대문자 상수는 임시 복사본에서 치환한다.)
# 훅과 짝으로 도는 scripts/의 도구(analyze-corrections.sh)도 같은 케이스 파일로 판정한다.

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

pass=0; fail=0; n=0; skip=0
# 케이스 값 안의 $REPO·$HOME·$TMP를 실제 경로로 바꾼다 ($TMP는 이 실행 동안 케이스끼리 공유하는 임시 폴더라 앞 케이스가 남긴 상태를 뒤 케이스가 본다)
expand() { local v="$1"; v="${v//\$REPO/$repo_root}"; v="${v//\$HOME/$HOME}"; v="${v//\$TMP/$tmpdir}"; printf '%s' "$v"; }
# 기대 열의 `;` 뒤 검사 하나를 판정한다. 실패하면 이유를 출력하고 1
check() {
	local c="$1" path pat want got
	case "$c" in
	out=) [ ! -s "$tmpdir/out" ] || { echo "출력이 비어야 하는데 있음: $(head -c 120 "$tmpdir/out")"; return 1; } ;;
	out~*) grep -Eq -- "${c#out~}" "$tmpdir/out" || { echo "출력에 /${c#out~}/ 없음: $(head -c 120 "$tmpdir/out")"; return 1; } ;;
	'out!~'*) ! grep -Eq -- "${c#out!~}" "$tmpdir/out" || { echo "출력에 /${c#out!~}/ 가 있으면 안 됨"; return 1; } ;;
	file:*) path="$(expand "${c#file:}")"; pat="${path#*~}"; path="${path%%~*}"
		grep -Eq -- "$pat" "$path" 2>/dev/null || { echo "$path 에 /$pat/ 없음"; return 1; } ;;
	lines:*) path="$(expand "${c#lines:}")"; want="${path##*=}"; path="${path%=*}"
		got=0; [ -f "$path" ] && got="$(grep -c '' "$path")"
		[ "$got" = "$want" ] || { echo "$path 줄 수 $got (기대 $want)"; return 1; } ;;
	nofile:*) path="$(expand "${c#nofile:}")"; [ ! -e "$path" ] || { echo "$path 가 없어야 함"; return 1; } ;;
	*) echo "모르는 검사: $c"; return 1 ;;
	esac
}
while IFS=$'\t' read -r spec scope expected stdin; do
	case "$spec" in ''|'#'*) continue ;; esac
	# 첫 열은 `파일 [인자…]` — 훅은 인자 없이, scripts/의 도구는 인자를 붙여 부른다
	hook="${spec%% *}"; args=""; [ "$hook" != "$spec" ] && args="${spec#* }"
	[ -n "$only" ] && [ "$hook" != "$only" ] && continue
	n=$((n + 1))
	src="$hooks_dir/$hook"
	if [ ! -f "$src" ]; then
		# 배달물에 없으면 씨앗(examples/seeds/*/hooks/)에서 찾는다 — 씨앗 훅도 같은 규약을 지켜야 한다
		for cand in examples/seeds/*/hooks/"$hook"; do [ -f "$cand" ] && src="$cand" && break; done
	fi
	# 훅이 아닌 도구(scripts/)도 같은 형식으로 판정한다 — 회고 루프의 분석 스크립트처럼 훅과 짝으로 도는 것
	[ ! -f "$src" ] && [ -f "scripts/$hook" ] && src="scripts/$hook"
	if [ ! -f "$src" ]; then
		# 씨앗 훅(local-*)은 플래그가 ☑일 때만 복사되고 examples/는 배달하지 않는다 — 어디에도 없으면 건너뛴다.
		# 배달물 훅(접두사 없음)이 없으면 실패다. 이름을 직접 지정했는데 없으면 아래 0건 검사가 잡는다.
		case "$hook" in
		local-*) n=$((n - 1)); skip=$((skip + 1)); continue ;;
		esac
		printf '  FAIL  %-28s (훅 파일 없음)\n' "$hook"; fail=$((fail + 1)); continue
	fi
	run="$src"
	# scope 열: `-` 원본 · `값` SCOPE 치환 · 뒤에 `;self=N`·`;test=CMD`를 붙이면 HARNESS_SELF_EDIT·TEST_CMD도 치환
	# (배달본은 TEST_CMD가 비어 있어 Stop 훅 판정을 시험하려면 값을 넣은 복사본이 필요하다)
	# `;대문자이름=값`은 본문의 `대문자이름=…` 줄을 `대문자이름="값"`으로 바꾼다 (예: `-;STORE=$TMP/q` — SCOPE는 그대로)
	scope_val="${scope%%;*}"; extras=""; [ "$scope" != "$scope_val" ] && extras="${scope#*;}"
	if [ "$scope" != "-" ]; then
		run="$tmpdir/$hook.$n"
		cp "$src" "$run"
		if [ "$scope_val" != "-" ]; then
			sed -i.bak "s|^SCOPE=\".*\"|SCOPE=\"$scope_val\"|" "$run" && rm -f "$run.bak"
		fi
		IFS=';' read -r -a extra_list <<<"$extras"
		for extra in "${extra_list[@]+"${extra_list[@]}"}"; do
			case "$extra" in
			self=*) sed -i.bak "s|^HARNESS_SELF_EDIT=\".*\"|HARNESS_SELF_EDIT=\"${extra#self=}\"|" "$run" && rm -f "$run.bak" ;;
			test=*) sed -i.bak "s|^TEST_CMD=\".*\"|TEST_CMD=\"${extra#test=}\"|" "$run" && rm -f "$run.bak" ;;
			[A-Z]*=*) name="${extra%%=*}"; val="$(expand "${extra#*=}")"
				sed -i.bak "s|^$name=.*|$name=\"$val\"|" "$run" && rm -f "$run.bak" ;;
			esac
		done
		chmod +x "$run"
	fi
	stdin="$(expand "$stdin")"
	argv=(); [ -n "$args" ] && read -r -a argv <<<"$(expand "$args")"
	printf '%s' "$stdin" | "$run" "${argv[@]+"${argv[@]}"}" >"$tmpdir/out" 2>"$tmpdir/err"
	actual=$?
	label="$stdin"; [ -z "$label" ] && label="${args:-(빈 입력)}"
	# 기대 열: `exit` 또는 `exit;검사;검사…` — 검사 형식은 scripts/hook-cases.txt 머리
	want_exit="${expected%%;*}"; checks=""; [ "$expected" != "$want_exit" ] && checks="${expected#*;}"
	why=""
	[ "$actual" = "$want_exit" ] || why="exit=$actual (기대 $want_exit)"
	if [ -z "$why" ] && [ -n "$checks" ]; then
		IFS=';' read -r -a check_list <<<"$checks"
		for c in "${check_list[@]}"; do why="$(check "$c")" || break; why=""; done
	fi
	if [ -z "$why" ]; then
		pass=$((pass + 1))
		printf '  ok    %-28s scope=%-8s exit=%s  %s\n' "$hook" "${scope:0:8}" "$actual" "${label:0:70}"
	else
		fail=$((fail + 1))
		printf '  FAIL  %-28s scope=%-8s %s  %s\n' "$hook" "${scope:0:8}" "$why" "${label:0:70}"
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

# ---- 내장 케이스: 회고 기록 폴더는 커밋되지 않는다 -----------------------------------
# 회고 루프 훅·분석 스크립트가 .claude/corrections/에 정정 기억 설명과 대화 원문 일부를 쓴다. .gitignore에서 빠지면 그대로 커밋될 수 있다
# (harness-retro-loop 스펙 불변 조건). 케이스 파일로는 git 설정을 볼 수 없어 여기 둔다.
if [ -z "$only" ]; then
	n=$((n + 1))
	if git check-ignore -q .claude/corrections/x 2>/dev/null; then
		pass=$((pass + 1)); printf '  ok    %-28s scope=-        exit=0  (.claude/corrections/ 는 git이 무시)\n' "(기록 폴더 무시)"
	else
		fail=$((fail + 1)); printf '  FAIL  %-28s scope=-        (.claude/corrections/ 가 .gitignore에 없다 — 대화 원문이 커밋될 수 있다)\n' "(기록 폴더 무시)"
	fi
fi

# ---- 내장 케이스: 훅 등록 대조 ---------------------------------------------------
# 훅은 settings.json에 등록돼야 존재한다. (1) .claude/hooks/*.sh 전부가 등록돼 있고 (2) 등록된 command 경로가 실존·실행 가능해야 한다.
# 등록만 지운 커밋이 검사기를 통과했던 사고(2026-09-07 감사 실험 B)가 계기다. 씨앗 훅은 복사 전이라 대상이 아니다.
# (3) 파일 쓰기 도구에 걸린 매처는 Write·Edit·MultiEdit·NotebookEdit를 모두 덮어야 한다 (2026-10-05 감사: MultiEdit·NotebookEdit 우회).
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
# 파일 쓰기 도구 매처는 쓰기 도구 네 개를 모두 덮어야 한다. 매처가 글자·숫자·`|`·`,`·공백뿐이면 정확한 이름 목록,
# 그 밖이면 정규식(부분 일치)으로 해석된다(Claude Code 훅 문서). `Write|Edit`만 두면 MultiEdit·NotebookEdit가 훅을 건너뛴다.
WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
def matches(matcher, tool):
    if matcher.strip() in ("", "*"):          # 빈 값·"*"·생략 = 모든 도구
        return True
    if re.fullmatch(r"[A-Za-z0-9_\-|, ]*", matcher):
        return tool in [t.strip() for t in re.split(r"[|,]", matcher)]
    try:
        return re.search(matcher, tool) is not None
    except re.error:
        msg = f"매처 '{matcher}'를 정규식으로 해석할 수 없음"
        if msg not in problems:
            problems.append(msg)
        return True                            # 해석 불가는 위에서 문제로 남기고, 누락 판정은 하지 않는다
for event, entries in (cfg.get("hooks") or {}).items():
    for entry in entries or []:
        matcher = entry.get("matcher") or ""
        if event in ("PreToolUse", "PostToolUse") and any(matches(matcher, t) for t in WRITE_TOOLS):
            missing = [t for t in WRITE_TOOLS if not matches(matcher, t)]
            if missing:
                problems.append(f"{event}: 매처 '{matcher}'가 쓰기 도구 {', '.join(missing)}를 덮지 않음")
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
echo "케이스 $n · 통과 $pass · 실패 $fail$([ "$skip" -gt 0 ] && echo " · 건너뜀 $skip (복사하지 않은 씨앗 훅)")"
[ "$fail" -eq 0 ]
