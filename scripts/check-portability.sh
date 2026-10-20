#!/usr/bin/env bash
# 부품 계약 검사기 — core 규칙에 프로젝트 고유 사실이 없는지, always-load 규칙이 토큰 예산 안인지 판정한다.
#
# 사용:
#   scripts/check-portability.sh                 # 배달물 전체(.claude/ 규칙·스킬·에이전트·훅·settings, git 훅, 견본) 검사 + 예산 판정 (기본)
#   scripts/check-portability.sh --scope core    # core-*.md 만 (P0~P5 시절의 좁은 범위)
#   scripts/check-portability.sh --skip C3       # 특정 분류 제외 (콤마 구분, 이행 중에만 사용)
#   scripts/check-portability.sh --budget 30000  # always-load 상한(바이트) 변경
#   PORTABILITY_BUDGET_STRICT=0 scripts/check-portability.sh   # 예산 초과를 경고로만 (기본은 차단)
#
# exit 0 = 통과 · exit 1 = 위반 있음 · exit 2 = 사용법·환경 오류
# 패턴은 scripts/portability-patterns.txt 한 파일에 데이터로 둔다 (부품성 원칙: bash 하나 + 데이터 파일 하나).
# 계약 원문: docs/specs/cross-cutting/harness-slot-system-v2.md "부품 계약" · "비즈니스 규칙" C1~C4

set -u
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

patterns_file="scripts/portability-patterns.txt"
scope="all"
# 이행 중 특정 분류를 잠시 빼야 할 때: PORTABILITY_SKIP=C3 (pre-commit도 이 변수를 그대로 물려받는다)
skip="${PORTABILITY_SKIP:-}"
# always-load 합계 상한(바이트). 한국어 UTF-8 기준 바이트/2.5 ≈ 토큰.
# 래칫: 실측 합계를 상한으로 못 박아 늘어나는 커밋은 막고, 줄이는 작업은 이 값을 낮추며 진행한다. 이유 없이 올리지 않는다.
# 이력: 2026-09-06 65,000B(P6 실측 63,096B) → 같은 날 토큰 최적화(라우터 통합·요약 표 제거·priority 절 local화) 뒤 52,000B.
budget_bytes="${PORTABILITY_BUDGET_BYTES:-52000}"
# 상한이 확정됐으므로 초과는 기본 차단이다. 이행 중 한 번 넘겨야 하면 PORTABILITY_BUDGET_STRICT=0.
strict_budget="${PORTABILITY_BUDGET_STRICT:-1}"

while [ $# -gt 0 ]; do
	case "$1" in
	--strict-budget)
		strict_budget=1
		shift
		;;
	--scope)
		scope="${2:-}"
		shift 2
		;;
	--skip)
		skip="${2:-}"
		shift 2
		;;
	--budget)
		budget_bytes="${2:-}"
		shift 2
		;;
	-h | --help)
		sed -n '2,13p' "$0"
		exit 0
		;;
	*)
		echo "알 수 없는 옵션: $1" >&2
		exit 2
		;;
	esac
done

if [ ! -f "$patterns_file" ]; then
	echo "FAIL: 패턴 파일이 없습니다 — $patterns_file" >&2
	exit 2
fi

# ---- 1. 검사 대상 수집 -------------------------------------------------------
# 배달물 = 새 프로젝트로 그대로 복사되는 것 전부. 프로젝트가 고유 사실을 적는 자리(harness-map.md · .claude/ 안의 local-* 파일)와
# 견본(examples/)만 제외한다. 스택 씨앗은 examples/seeds/ 에 살고, adopt이 .claude/rules·agents·hooks로 복사할 때도 local- 접두사를
# 유지하므로(씨앗 파일명이 이미 local-*) 복사 뒤에도 검사 밖이다 — 접두사가 곧 층 표시다.
targets=""
for f in .claude/rules/core-*.md; do
	[ -f "$f" ] && targets="$targets $f"
done
if [ "$scope" = "all" ]; then
	for f in .claude/rules/*.md .claude/skills/*/SKILL.md .claude/skills/*/references/*.md .claude/agents/*.md .claude/hooks/*.sh .claude/settings.json scripts/git-hooks/* AGENTS.template.md .github/CONTRIBUTING.md; do
		[ -f "$f" ] || continue
		case "$f" in
		.claude/rules/core-*.md | .claude/rules/harness-map.md | .claude/*/local-*) continue ;;
		esac
		targets="$targets $f"
	done
elif [ "$scope" != "core" ]; then
	echo "--scope 는 core 또는 all 이어야 합니다" >&2
	exit 2
fi

if [ -z "$targets" ]; then
	echo "FAIL: 검사할 core-*.md 가 없습니다" >&2
	exit 2
fi

# ---- 2. 금지 패턴 스캔 -------------------------------------------------------
# awk 하나로 끝낸다: 패턴 파일을 먼저 읽고(FNR==NR), 이어지는 파일들을 줄 단위로 대조한다.
# 오탐 방지: `채운 예`(견본 인용)·`다스택 예시`(여러 스택을 나열하는 실측 안내) 줄과 YAML frontmatter(`paths:` glob)는 건너뛴다.
violations="$(
	# shellcheck disable=SC2086
	awk -v skip="$skip" '
		BEGIN { FS = "\t"; n = 0; split(skip, s, ","); for (i in s) skipc[s[i]] = 1 }
		FNR == NR {
			if ($0 ~ /^[ \t]*(#|$)/) next
			if (NF < 3) next
			if ($1 in skipc) next
			n++; cls[n] = $1; re[n] = $2; msg[n] = $3
			next
		}
		FNR == 1 { infm = ($0 == "---") ? 1 : 0 }
		infm && FNR > 1 && $0 == "---" { infm = 0; next }
		infm { next }
		{
			if (index($0, "채운 예") > 0 || index($0, "다스택 예시") > 0) next
			for (i = 1; i <= n; i++) {
				if (match($0, re[i])) {
					printf "%s\t%s:%d\t%s\t%s\n", cls[i], FILENAME, FNR, substr($0, RSTART, RLENGTH), msg[i]
				}
			}
		}
	' "$patterns_file" $targets
)"

# ---- 3. always-load 토큰 예산 -----------------------------------------------
# always-load = frontmatter에 paths:가 없는 .claude/rules/*.md + CLAUDE.md + CLAUDE.md가 @로 불러오는 파일.
# 예산은 배달물(core·map·AGENTS·CLAUDE)의 래칫이다 — 프로젝트가 스스로 얹는 local-*.md는 합계에 넣지 않고 참고로만 보여 준다.
# (넣으면 이 저장소 실측으로 정한 상한이 씨앗 하나 복사한 프로젝트에서 곧바로 깨진다.)
always_files=""
local_files=""
for f in .claude/rules/*.md; do
	[ -f "$f" ] || continue
	if ! awk 'NR==1 && $0!="---" {exit 1} NR>1 && $0=="---" {exit 1} /^paths:/ {found=1; exit 0} END {exit found?0:1}' "$f"; then
		case "$f" in
		.claude/rules/local-*) local_files="$local_files $f" ;;
		*) always_files="$always_files $f" ;;
		esac
	fi
done
if [ -f CLAUDE.md ]; then
	always_files="$always_files CLAUDE.md"
	while IFS= read -r inc; do
		[ -f "$inc" ] && always_files="$always_files $inc"
	done < <(awk '/^@[^ \t]+$/ { print substr($0, 2) }' CLAUDE.md)
fi

total_bytes=0
budget_table=""
for f in $always_files; do
	b=$(wc -c <"$f" | tr -d ' ')
	total_bytes=$((total_bytes + b))
	budget_table="$budget_table$(printf '  %7d  %s' "$b" "$f")
"
done

# ---- 4. 보고 ---------------------------------------------------------------
status=0

if [ -n "$violations" ]; then
	status=1
	echo "## 부품 계약 위반 (scope=$scope)"
	echo
	printf '%s\n' "$violations" | awk -F'\t' '{ printf "  %s  %-44s  %-28s  %s\n", $1, $2, "\"" $3 "\"", $4 }'
	echo
	printf '%s\n' "$violations" | awk -F'\t' '{ c[$1]++ } END { for (k in c) printf "  %s: %d건\n", k, c[k] }' | sort
	echo
else
	echo "## 부품 계약: 위반 없음 (scope=$scope)"
	echo
fi

echo "## always-load 예산 (상한 ${budget_bytes}B ≈ $((budget_bytes / 25 * 10)) 토큰 추정)"
echo
printf '%s' "$budget_table"
printf '  %7d  합계 (≈ %d 토큰 추정)\n' "$total_bytes" "$((total_bytes / 25 * 10))"
for f in $local_files; do
	printf '  %7d  %s  (local 층 — 예산 밖, 참고)\n' "$(wc -c <"$f" | tr -d ' ')" "$f"
done
if [ "$total_bytes" -gt "$budget_bytes" ]; then
	if [ "$strict_budget" = "1" ]; then
		status=1
		echo "  → FAIL: 상한 초과 $((total_bytes - budget_bytes))B"
	else
		echo "  → WARN: 상한 초과 $((total_bytes - budget_bytes))B (PORTABILITY_BUDGET_STRICT=0 — 경고만)"
	fi
else
	echo "  → OK"
fi

exit "$status"
