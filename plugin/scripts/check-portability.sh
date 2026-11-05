#!/usr/bin/env bash
# 부품 계약 검사기 — core 규칙에 프로젝트 고유 사실이 없는지, always-load 규칙이 토큰 예산 안인지 판정한다.
#
# 사용:
#   plugin/scripts/check-portability.sh                 # 배달물 전체(.claude/ 규칙·스킬·에이전트·훅·settings, git 훅, dev.sh 엔진, 견본) 검사 + 예산 판정 (기본)
#   plugin/scripts/check-portability.sh --scope core    # core-*.md 만 (P0~P5 시절의 좁은 범위)
#   plugin/scripts/check-portability.sh --skip C3       # 특정 분류 제외 (콤마 구분, 이행 중에만 사용)
#   plugin/scripts/check-portability.sh --budget 30000  # always-load 상한(바이트) 변경
#   PORTABILITY_BUDGET_STRICT=0 plugin/scripts/check-portability.sh   # 예산 초과를 경고로만 (기본은 차단)
#
# 대조 검사 2개 (산문 규칙을 결정적 검사로 옮긴 것):
#   S  슬롯 — 배달물이 쓰는 {{슬롯}} = 플러그인 scripts/harness-keys.txt가 정의한 slot (정의 안 된 슬롯 사용 · 아무도 안 쓰는 슬롯 정의)
#   I  구성 요소 목록 — 실제 규칙·스킬·에이전트·훅 = .claude/rules/README.md 언급, 그리고 살아 있는 문서가 가리키는
#      core-*.md · 훅 *.sh · `이름` 스킬/에이전트가 실제로 있는가 (지운 구성 요소로 안내하는 문장 차단)
#
# exit 0 = 통과 · exit 1 = 위반 있음 · exit 2 = 사용법·환경 오류
# 패턴은 plugin/scripts/portability-patterns.txt 한 파일에 데이터로 둔다 (부품성 원칙: bash 하나 + 데이터 파일 하나).
# 계약 원문: docs/specs/cross-cutting/harness-slot-system-v2.md "부품 계약" · "비즈니스 규칙" C1~C3

set -u
export LC_ALL=C

# 도구(이 파일·패턴·훅)는 플러그인 폴더, 검사 대상은 프로젝트 — Bash 도구에는 CLAUDE_PROJECT_DIR가 없어 git 최상위(없으면 현재 폴더)로 잡는다
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

patterns_file="$plugin_root/scripts/portability-patterns.txt"
scope="all"
# 이행 중 특정 분류를 잠시 빼야 할 때: PORTABILITY_SKIP=C3 (pre-commit도 이 변수를 그대로 물려받는다)
skip="${PORTABILITY_SKIP:-}"
# always-load 합계 상한(바이트). 한국어 UTF-8 기준 바이트/2.5 ≈ 토큰.
# 래칫: 실측 합계를 상한으로 못 박아 늘어나는 커밋은 막고, 줄이는 작업은 이 값을 낮추며 진행한다. 이유 없이 올리지 않는다.
# 이력: 2026-09-06 65,000B(P6 실측 63,096B) → 같은 날 토큰 최적화(라우터 통합·요약 표 제거·priority 절 local화) 뒤 52,000B
#       → 2026-10-05 경량화 감사(규칙 3개 통합·워크플로 규모 단계·유지보수 열 삭제, 실측 27,341B) 뒤 28,000B
#       → 2026-10-27 G4 상세를 verify-work로·map 설명을 rules/README.md로·guardrails 예시 축소(실측 24,460B) 뒤 25,000B
#       → 2026-11-05 core 규칙 4개를 플러그인 주입 훅으로 옮김(실측 9,048B — 규칙은 아래 주입 글 길이 검사가 맡는다) 뒤 9,100B
#       → 같은 날 harness-map.md를 .claude/harness.conf(설정 값 주입 훅)로 바꿈(실측 5,668B) 뒤 5,700B.
budget_bytes="${PORTABILITY_BUDGET_BYTES:-5700}"
# 주입 훅 하나가 넣는 글의 상한(글자 수). 훅 출력은 1만 자에서 잘리고 넘으면 앞 2,000자만 남는다.
inject_limit="${PORTABILITY_INJECT_LIMIT:-9000}"
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
# 배달물 = 새 프로젝트로 그대로 복사되는 것 전부. 프로젝트가 고유 사실을 적는 자리(.claude/harness.conf · .claude/ 안의 local-* 파일)와
# 견본(examples/)만 제외한다. local- 접두사가 곧 층 표시다.
# 붙여 쓰는 프로젝트(하네스 자기 수정 ❌ = HARNESS_SELF_EDIT "0")에서는 두 가지가 프로젝트 값 자리라 검사 밖이다.
#   .github/CONTRIBUTING.md — 그 프로젝트의 {{Git 컨벤션 SSOT}}. 원본 저장소(☑)에서는 견본이라 검사한다
#   git 훅 상수 대입 줄의 값(COMMIT_RE·FORMAT_*) — 원본 저장소에서는 기본값도 견본이라 검사한다 (아래 awk)
# 2026-10-16 TripFit 사본에 붙였을 때 이 둘이 위반 21건(CONTRIBUTING 17 · 상수 4)으로 잡혀 verify.sh가 처음부터 실패했다.
# 값을 읽지 못하면 원본 저장소로 보고 더 많이 검사한다 — 놓치는 쪽보다 오탐이 보이는 쪽이 낫다.
# 붙여 쓰는 프로젝트인지는 프로젝트 설정(.claude/harness.conf)의 HARNESS_SELF_EDIT가 정한다
self_edit="$(sed -n -E "s/^HARNESS_SELF_EDIT=([01])[[:space:]]*$/\1/p" .claude/harness.conf 2>/dev/null | tail -n 1)"
adopted=0
if [ "$self_edit" = "0" ]; then
	adopted=1
elif [ -z "$self_edit" ]; then
	echo "경고: .claude/harness.conf에서 HARNESS_SELF_EDIT를 읽지 못해 원본 저장소로 보고 CONTRIBUTING·git 훅 상수까지 검사합니다" >&2
fi
targets=""
for f in plugin/rules/core-*.md; do
	[ -f "$f" ] && targets="$targets $f"
done
if [ "$scope" = "all" ]; then
	for f in plugin/rules/*.md .claude/rules/*.md plugin/skills/*/SKILL.md plugin/skills/*/references/*.md plugin/skills/*/references/*.conf plugin/agents/*.md plugin/hooks/*.sh plugin/hooks/hooks.json .claude/settings.json scripts/git-hooks/* plugin/scripts/dev.sh AGENTS.template.md .github/CONTRIBUTING.md; do
		[ -f "$f" ] || continue
		case "$f" in
		plugin/rules/core-*.md | .claude/*/local-*) continue ;;
		.github/CONTRIBUTING.md) [ "$adopted" = 1 ] && continue ;;
		esac
		targets="$targets $f"
	done
elif [ "$scope" != "core" ]; then
	echo "--scope 는 core 또는 all 이어야 합니다" >&2
	exit 2
fi

if [ -z "$targets" ]; then
	echo "FAIL: 검사할 plugin/rules/core-*.md 가 없습니다" >&2
	exit 2
fi

# ---- 2. 금지 패턴 스캔 -------------------------------------------------------
# awk 하나로 끝낸다: 패턴 파일을 먼저 읽고(FNR==NR), 이어지는 파일들을 줄 단위로 대조한다.
# 오탐 방지: `채운 예`(견본 인용)·`다스택 예시`(여러 스택을 나열하는 실측 안내) 줄과 YAML frontmatter(`paths:` glob)는 건너뛴다.
# 붙여 쓰는 프로젝트에서는 git 훅 상수 대입 줄에서 값만 지우고 나머지(줄 끝 주석)를 검사한다.
violations="$(
	# shellcheck disable=SC2086
	awk -v skip="$skip" -v adopted="$adopted" '
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
			if (adopted == 1 && ((FILENAME == "scripts/git-hooks/pre-commit" && $0 ~ /^FORMAT_(CMD|PATHS)=/) ||
			    (FILENAME == "scripts/git-hooks/commit-msg" && $0 ~ /^COMMIT_RE=/)))
				sub(/^[A-Z_]+=("[^"]*"|\047[^\047]*\047|[^ \t]*)/, "")
			for (i = 1; i <= n; i++) {
				if (match($0, re[i])) {
					printf "%s\t%s:%d\t%s\t%s\n", cls[i], FILENAME, FNR, substr($0, RSTART, RLENGTH), msg[i]
				}
			}
		}
	' "$patterns_file" $targets
)"

# ---- 3. always-load 토큰 예산 · 주입 글 길이 ------------------------------------
# core 규칙은 플러그인 주입 훅이 넣으므로 예산이 둘로 나뉜다 (harness-plugin-delivery 스펙).
#   주입 글 — 훅 하나가 넣는 글이 INJECT_LIMIT자(9,000) 이하. 훅 출력은 1만 자에서 잘리므로 여유를 둔다. 아래 3c
#   always-load — Claude Code가 직접 싣는 것: frontmatter에 paths:가 없는 .claude/rules/*.md + CLAUDE.md + @로 불러오는 파일
#     + 스킬·에이전트 설명 줄. 플러그인으로 옮긴 뒤에도 매 세션 실리므로 래칫을 남긴다.
# 예산은 배달물(map·AGENTS·CLAUDE·설명 줄)의 래칫이다 — 프로젝트가 스스로 얹는 local-*.md는 합계에 넣지 않고 참고로만 보여 준다.
# (넣으면 이 저장소 실측으로 정한 상한이 local 규칙을 둔 프로젝트에서 곧바로 깨진다.)
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
# 스킬·에이전트 설명 줄(description·when_to_use)도 세션마다 목록으로 읽힌다. local-*(프로젝트 층)는 규칙처럼 빼고,
# disable-model-invocation 스킬은 목록에 실리지 않아 뺀다. 한 줄로 쓴 값만 센다 — 여러 줄 YAML이면 적게 잡힌다.
desc_bytes=0; desc_n=0
for f in plugin/skills/*/SKILL.md plugin/agents/*.md .claude/skills/*/SKILL.md .claude/agents/*.md; do
	[ -f "$f" ] || continue
	case "$f" in .claude/skills/local-*|.claude/agents/local-*) continue ;; esac
	b=$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} /^disable-model-invocation:[ \t]*true/ {off=1}
		/^(description|when_to_use):/ { sub(/^[a-z_]+:[ \t]*/, ""); n += length($0) } END { print off ? -1 : n+0 }' "$f")
	[ "$b" -lt 0 ] && continue
	desc_bytes=$((desc_bytes + b)); desc_n=$((desc_n + 1))
done
total_bytes=$((total_bytes + desc_bytes))
budget_table="$budget_table$(printf '  %7d  스킬·에이전트 설명 줄 %d개' "$desc_bytes" "$desc_n")
"

# ---- 3c. 주입 글 길이 -------------------------------------------------------------
# 주입 훅을 실제로 돌려 additionalContext 글자 수를 잰다 — 규칙 파일 합계가 아니라 머리 줄까지 붙은 실제 출력이 상한을 넘는지 본다.
# 경로 규칙은 규칙마다 첫 glob에 맞는 견본 경로를 만들어 경로 훅에 넣는다(실행마다 세션 id를 바꿔 한 번만 넣기 기록에 걸리지 않게).
inject_out="$(PLUGIN_ROOT="$plugin_root" PROJECT_ROOT="$repo_root" python3 -I - <<'PY_INJECT'
import glob, json, os, re, subprocess
root, project = os.environ["PLUGIN_ROOT"], os.environ["PROJECT_ROOT"]
env = dict(os.environ, CLAUDE_PLUGIN_ROOT=root, CLAUDE_PROJECT_DIR=project)
def run(hook, payload):
    r = subprocess.run([os.path.join(root, "hooks", hook)], input=json.dumps(payload), capture_output=True,
                       text=True, env=env, timeout=30)
    return json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
try:
    ctx = run("auto-inject-rules.sh", {"session_id": "portability", "hook_event_name": "SessionStart", "source": "startup"})
    print(f"{len(ctx)}\tauto-inject-rules.sh — core 규칙")
except Exception as e:
    print(f"ERR\tauto-inject-rules.sh 출력을 재지 못함 ({type(e).__name__}: {e})")
# 설정 값 표 — 이 프로젝트 설정으로 잰다. 설정이 없으면 init 안내 한 줄이라 짧다
try:
    ctx = run("auto-inject-config.sh", {"session_id": "portability", "hook_event_name": "SessionStart", "source": "startup"})
    print(f"{len(ctx)}\tauto-inject-config.sh — 설정 값 표")
except Exception as e:
    print(f"ERR\tauto-inject-config.sh 출력을 재지 못함 ({type(e).__name__}: {e})")
for i, p in enumerate(sorted(glob.glob(os.path.join(root, "rules", "*.md")))):
    m = re.match(r"---\n(.*?)\n---\n", open(p, encoding="utf-8").read(), re.S)
    globs = re.findall(r'^\s*-\s*"([^"]+)"', m.group(1), re.M) if m and "paths:" in m.group(1) else []
    if not globs:
        continue
    sample = globs[0].replace("**/", "x/").replace("**", "x").replace("*", "x")
    name = os.path.basename(p)
    try:
        ctx = run("auto-inject-path-rules.sh", {"session_id": f"portability-{os.getpid()}-{i}", "hook_event_name": "PostToolUse",
                  "tool_name": "Read", "tool_input": {"file_path": os.path.join(project, sample)}})
        print(f"{len(ctx)}\tauto-inject-path-rules.sh — {name} ({sample})")
    except Exception as e:
        print(f"ERR\tauto-inject-path-rules.sh — {name} 출력을 재지 못함 ({type(e).__name__}: {e})")
PY_INJECT
)" || { echo "FAIL: 주입 글 길이 검사 실행 실패 (python3 필요)" >&2; exit 2; }

# ---- 3b. 대조 검사 (S 슬롯 · I 구성 요소 목록) ---------------------------------
# --scope와 무관하게 배달물 전체를 본다(슬롯이 스킬·훅에서만 쓰여도 "쓰는 곳"이다).
# 참조 검사는 두 종류 파일을 다르게 본다.
#   하네스가 쓰는 파일(배달물·템플릿): `core-x`·`core-x.md`·`deny-x.sh` 표기가 실제 규칙·훅을 가리켜야 한다.
#   프로젝트가 쓰는 파일(AGENTS.md·README.md·CONTRIBUTING 등): 프로젝트 고유 이름("core-domain 모듈")과 겹치므로
#     `.md`·`.sh`까지 쓴 표기만 보고, 저장소 어딘가에 같은 이름의 파일이 있으면 통과시킨다.
# 스킬·에이전트는 이름이 내장·플러그인과 겹치므로 git 이력에서 **지워진** 하네스 스킬·에이전트를 가리킬 때만 잡는다.
# 기록 문서(reports·specs·audits·out-of-scope·references·harness-engineering)는 지운 것을 이력으로 말하는 게 정상이라 대상이 아니다.
cross_out="$(ADOPTED="$adopted" PLUGIN_ROOT="$plugin_root" python3 - <<'PY_CROSS'
import glob, os, re, subprocess
out = []
def files(patterns):
    seen = []
    for pat in patterns:
        for f in sorted(glob.glob(pat, recursive=True)):
            if os.path.isfile(f) and f not in seen:
                seen.append(f)
    return seen
def is_local(f):
    return os.path.basename(f).startswith("local-")
harness_files = [f for f in files(["plugin/rules/*.md", ".claude/rules/*.md", "plugin/skills/*/SKILL.md", "plugin/skills/*/references/*.md",
                                   "plugin/agents/*.md", "plugin/hooks/*.sh", "scripts/git-hooks/*", "AGENTS.template.md",
                                   "docs/templates/*.md"])
                 if not (f.startswith(".claude/") and is_local(f))]
project_files = files(["AGENTS.md", "CLAUDE.md", "README.md", ".github/CONTRIBUTING.md", "docs/README.md", "docs/harness/README.md"])
# --- S: 슬롯 ---
META = {"{{슬롯}}", "{{역할 이름}}", "{{…}}", "{{역할}}"}
keys_file = os.path.join(os.environ["PLUGIN_ROOT"], "scripts", "harness-keys.txt")
defined = {cols[2] for cols in (l.rstrip("\n").split("\t") for l in open(keys_file, encoding="utf-8"))
           if len(cols) >= 3 and cols[1] == "slot"}
used = {}
# 붙여 쓰는 프로젝트의 CONTRIBUTING은 프로젝트 문서라 슬롯 사용처로 보지 않는다 (금지 패턴 검사와 같은 조건)
contributing = [] if os.environ.get("ADOPTED") == "1" else files([".github/CONTRIBUTING.md"])
for f in [f for f in harness_files if not f.startswith("examples/")] + contributing:
    for m in re.finditer(r"\{\{[^}]+\}\}", open(f, encoding="utf-8").read()):
        used.setdefault(m.group(0), f)
for slot in sorted(set(used) - defined - META):
    out.append(f"S\t{used[slot]}\t{slot}\tharness-keys.txt에 없는 슬롯을 쓴다 — 키를 추가하거나 기존 슬롯으로")
for slot in sorted(defined - set(used)):
    out.append(f"S\tplugin/scripts/harness-keys.txt\t{slot}\t배달물 어디에서도 쓰지 않는 슬롯 — 지운다 (init-harness references/harness-conf.md 규칙 3)")
# --- I: 구성 요소 목록 ---
readme = open(".claude/rules/README.md", encoding="utf-8").read()
# 배달 구성 요소는 plugin/, 프로젝트 층(local-*)은 .claude/에 있다
skills = {os.path.basename(os.path.dirname(p)) for d in ("plugin", ".claude") for p in glob.glob(d + "/skills/*/SKILL.md")}
agents_all = {os.path.basename(p)[:-3] for d in ("plugin", ".claude") for p in glob.glob(d + "/agents/*.md")}
hooks_all = {os.path.basename(p) for d in ("plugin", ".claude") for p in glob.glob(d + "/hooks/*.sh")}
rules_all = {os.path.basename(p) for d in ("plugin", ".claude") for p in glob.glob(d + "/rules/*.md")}
# 목록 SSOT에는 배달물(local-* 제외)이 전부 있어야 한다
hooks_here = hooks_all
for name in sorted(skills | {a for a in agents_all if not a.startswith("local-")}
                   | {h for h in hooks_here if not h.startswith("local-")}
                   | {r for r in rules_all if r != "README.md" and not r.startswith("local-")}):
    if not re.search(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", readme):
        out.append(f"I\t.claude/rules/README.md\t{name}\t실제로 있는 구성 요소가 목록 SSOT에 없다")
try:
    tracked = {os.path.basename(p) for p in subprocess.run(["git", "ls-files", "-co", "--exclude-standard"],
               capture_output=True, text=True, check=True).stdout.split("\n") if p}
    def deleted(pattern, take):
        log = subprocess.run(["git", "log", "--diff-filter=D", "--name-only", "--format=", "--", pattern],
                             capture_output=True, text=True).stdout.split("\n")
        return {take(p) for p in log if p}
    gone_skills = (deleted(".claude/skills/*/SKILL.md", lambda p: p.split("/")[2]) | deleted("plugin/skills/*/SKILL.md", lambda p: p.split("/")[2])) - skills
    gone_agents = (deleted(".claude/agents/*.md", lambda p: os.path.basename(p)[:-3]) | deleted("plugin/agents/*.md", lambda p: os.path.basename(p)[:-3])) - agents_all
except Exception:
    tracked, gone_skills, gone_agents = set(), set(), set()
RULE_ANY = re.compile(r"(?<![\w-])core-[a-z]+(?:-[a-z]+)*(?:\.md)?")
RULE_MD = re.compile(r"(?<![\w-])core-[a-z]+(?:-[a-z]+)*\.md")
HOOK = re.compile(r"(?<![\w{-])((?:deny|warn|auto)-[a-z0-9-]*\.sh)")
NAMED = re.compile(r"`([a-z][a-z-]+)` (스킬|서브에이전트|에이전트)")
for f in harness_files + project_files:
    project = f in project_files
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        for m in (RULE_MD if project else RULE_ANY).finditer(line):
            n = m.group(0) if m.group(0).endswith(".md") else m.group(0) + ".md"
            if n not in rules_all and not (project and n in tracked):
                out.append(f"I\t{f}:{i}\t{m.group(0)}\t없는 규칙 파일을 가리킨다")
        for m in HOOK.finditer(line):
            n = m.group(1)
            if n not in hooks_all and not (project and n in tracked):
                out.append(f"I\t{f}:{i}\t{n}\t없는 훅을 가리킨다")
        for m in NAMED.finditer(line):
            n, kind = m.group(1), m.group(2)
            if n in (gone_skills if kind == "스킬" else gone_agents):
                out.append(f"I\t{f}:{i}\t{n}\t지워진 {kind}의 이름이 남았다")
print("\n".join(out))
PY_CROSS
)" || { echo "FAIL: 대조 검사 실행 실패 (python3 필요)" >&2; exit 2; }

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

if [ -n "$cross_out" ]; then
	status=1
	echo "## 대조 위반 (S 슬롯 · I 구성 요소 목록)"
	echo
	printf '%s\n' "$cross_out" | awk -F'\t' '{ printf "  %s  %-44s  %-28s  %s\n", $1, $2, "\"" $3 "\"", $4 }'
	echo
else
	echo "## 대조: 슬롯 정의 = 사용 · 구성 요소 = 목록 SSOT"
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

echo
echo "## 주입 글 길이 (훅 하나당 상한 ${inject_limit}자)"
echo
inject_max=0
while IFS=$'\t' read -r n label; do
	[ -n "$n" ] || continue
	if [ "$n" = "ERR" ]; then
		status=1; echo "  → FAIL: $label"; continue
	fi
	printf '  %7d  %s\n' "$n" "$label"
	[ "$n" -gt "$inject_max" ] && inject_max="$n"
	if [ "$n" -gt "$inject_limit" ]; then status=1; echo "  → FAIL: 상한 초과 $((n - inject_limit))자 — $label"; fi
done <<<"$inject_out"
[ -z "$inject_out" ] && { status=1; echo "  → FAIL: 잰 주입 글이 없다"; }

n_viol=0; [ -n "$violations" ] && n_viol=$(printf '%s\n' "$violations" | wc -l | tr -d ' ')
n_cross=0; [ -n "$cross_out" ] && n_cross=$(printf '%s\n' "$cross_out" | wc -l | tr -d ' ')
echo
echo "portability: 부품 계약 위반 ${n_viol} · 대조 위반 ${n_cross} · always-load ${total_bytes}B / 상한 ${budget_bytes}B · 주입 최대 ${inject_max}자 / 상한 ${inject_limit}자"
exit "$status"
