#!/usr/bin/env bash
# 문서 스타일 검사기 — `doc-writing.md`에서 패턴으로 잡히는 것만 exit code로 판정한다.
#
# 사용:
#   plugin/scripts/check-doc-style.sh <file.md> [...]      # 지정한 마크다운 파일 검사
#   plugin/scripts/check-doc-style.sh --all                # docs/ · .claude/ · 루트 *.md 전부
#   plugin/scripts/check-doc-style.sh --staged             # git stage에 있는 *.md만
#
# 판정 (E = exit 1 · W = 경고만):
#   E  H4(####) 이상 제목 — 문서를 나눌 신호            (doc-writing "한 문서는 하나의 주제")
#   E  H1 바로 아래 개요 없음 — 곧바로 다음 제목이 옴     (doc-writing "H1 바로 아래에 개요")
#   E/W 문장 패턴 — plugin/scripts/doc-style-patterns.txt      (메타 담화·번역투·한자어·명사형)
#   W  제목 30자 초과                                   (doc-writing "제목은 검색 가능하게")
#   W  약어 첫 등장에 풀어쓰기 없음 (허용 목록 제외)     (doc-writing "용어를 일관되게")
#   W  상대 링크가 가리키는 파일이 없음                  (doc-reviewer "근거·출처 없는 참조")
#      없어진 파일로 안내하는 링크를 따라가면 규칙이 없고, 없으면 에이전트가 스스로 판단해 버린다.
#      외부 URL·앵커·슬롯(`{{…}}`)이 든 경로는 대상이 아니다. 오탐이면 경고이므로 커밋을 막지 않는다.
#
# 검사하지 않는 것: 코드 블록·인라인 코드·따옴표 안 문자열·`채운 예` 줄·frontmatter. 판단이 필요한 항목
# (유형 적합성·개요가 실제 요약인지·근거 없는 단정)은 doc-reviewer 에이전트가 advisory로 맡는다.
# 패턴은 데이터 파일 하나에 두어 언어가 다른 프로젝트는 그 파일만 갈아끼운다 (부품성 원칙: bash 하나 + 데이터 파일 하나).
# JSON 훅들과 같은 이유로 python3에 의존한다 (BSD awk는 한글 글자 수를 세지 못한다).

set -u
# 패턴은 플러그인 폴더, 검사할 문서는 프로젝트 — Bash 도구에는 CLAUDE_PROJECT_DIR가 없어 git 최상위(없으면 현재 폴더)로 잡는다
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

patterns_file="$plugin_root/scripts/doc-style-patterns.txt"
[ -f "$patterns_file" ] || { echo "FAIL: 패턴 파일이 없습니다 — $patterns_file" >&2; exit 2; }

case "${1:-}" in
"" | -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
esac

python3 -I - "$patterns_file" "$@" <<'PYTHON'
import os, re, subprocess, sys

patterns_file, *args = sys.argv[1:]
if args[0] in ('--all', '--staged'):
    git_args = (['ls-files', '-co', '--exclude-standard'] if args[0] == '--all'
                else ['diff', '--cached', '--name-only', '--diff-filter=ACMRT'])
    listing = subprocess.run(['git', *git_args, '-z', '--', '*.md'], stdout=subprocess.PIPE)
    if listing.returncode:
        sys.exit(2)
    paths = sorted({os.fsdecode(item) for item in listing.stdout.split(b'\0') if item})
else:
    paths = args
    for path in paths:
        if not os.path.isfile(path):
            print(f"FAIL: 파일이 없습니다 — {path}", file=sys.stderr)
            sys.exit(2)

files = [path for path in paths if os.path.isfile(path)
         and not path.startswith(('examples/', 'scripts/hook-fixtures/'))]
if not files:
    print("검사할 마크다운 파일이 없습니다.")
    sys.exit(0)

TITLE_MAX = 30
rules, allow = [], set()
for raw in open(patterns_file, encoding="utf-8"):
    line = raw.rstrip("\n")
    if not line or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if parts[0] == "ALLOW" and len(parts) >= 2:
        allow.add(parts[1].strip())
        continue
    if len(parts) < 4:
        continue
    cls, sev, regex, msg = parts[0], parts[1], parts[2], parts[3]
    rules.append((cls, sev, re.compile(regex), msg))

ACRO = re.compile(r"(?<![A-Za-z])([A-Z]{2,6})(?![A-Za-z])")
INLINE_CODE = re.compile(r"`[^`]*`")
QUOTED = re.compile(r"\"[^\"]*\"|“[^”]*”|「[^」]*」|'[^']*'")
LINK_TARGET = re.compile(r"\]\([^)]*\)")
# 상대 링크 실존 검사용 — 링크 표기에서 대상만 뽑는다. 외부 URL·앵커·슬롯은 아래에서 걸러낸다.
MD_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
SKIP_LINK = ("http://", "https://", "mailto:", "#", "<")

def strip_for_prose(s: str) -> str:
    s = INLINE_CODE.sub(" ", s)
    s = QUOTED.sub(" ", s)
    s = LINK_TARGET.sub("]", s)
    return s

def heading_text(s: str) -> str:
    s = INLINE_CODE.sub(lambda m: m.group(0)[1:-1], s)
    s = re.sub(r"[*_]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

errors = warnings = 0

def report(sev, path, lineno, cls, found, msg):
    global errors, warnings
    if sev == "E":
        errors += 1
    else:
        warnings += 1
    print(f"  {sev}  {cls:<8} {path}:{lineno}  \"{found}\"  {msg}")

for path in files:
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except Exception as e:  # noqa
        print(f"  E  READ     {path}  {e}")
        errors += 1
        continue

    # frontmatter 건너뛰기
    i = 0
    if lines and lines[0].strip() == "---":
        i = 1
        while i < len(lines) and lines[i].strip() != "---":
            i += 1
        i += 1

    doc_dir = os.path.dirname(path) or "."
    in_fence = False
    fence_open_line = None
    seen_acro = set()
    h1_line = None
    overview_checked = False

    for lineno in range(i, len(lines)):
        line = lines[lineno]
        if line.startswith("```") or line.startswith("~~~"):
            in_fence = not in_fence
            fence_open_line = lineno + 1 if in_fence else None
            continue
        if in_fence:
            continue
        if "채운 예" in line:
            continue

        for lm in MD_LINK.finditer(line):
            target = lm.group(1)
            if target.startswith(SKIP_LINK) or "{{" in target:
                continue
            rel = target.split("#")[0].split("?")[0]
            if not rel:
                continue
            if not os.path.exists(os.path.normpath(os.path.join(doc_dir, rel))):
                report("W", path, lineno + 1, "LINK", target[:40],
                       "링크 대상이 없다 — 경로를 고치거나, 다른 저장소 것이면 링크 대신 이름으로 적는다")

        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            level, text = len(m.group(1)), heading_text(m.group(2))
            if level >= 4:
                report("E", path, lineno + 1, "H4", text[:40], "H4 이상 — 문서를 나눌 신호 (표·체크리스트 안 묶음은 굵은 글씨로)")
            if len(text) > TITLE_MAX:
                report("W", path, lineno + 1, "TITLE", text[:40] + "…", f"제목 {len(text)}자 — {TITLE_MAX}자 이내로")
            if level == 1 and h1_line is None:
                h1_line = lineno
            elif h1_line is not None and not overview_checked:
                # H1 다음 비어 있지 않은 첫 줄이 제목이면 개요가 없다
                nxt = h1_line + 1
                while nxt < len(lines) and lines[nxt].strip() == "":
                    nxt += 1
                if nxt == lineno:
                    report("E", path, h1_line + 1, "OVERVIEW", heading_text(lines[h1_line][2:])[:40], "H1 바로 아래에 개요가 없다 — 이 문서가 무엇인지 한 문단 먼저")
                overview_checked = True
            continue

        if h1_line is not None and not overview_checked and line.strip():
            overview_checked = True  # H1 뒤에 본문이 왔으니 개요 있음

        prose = strip_for_prose(line)

        for cls, sev, rx, msg in rules:
            mm = rx.search(prose)
            if mm:
                report(sev, path, lineno + 1, cls, mm.group(0).strip(), msg)

        for am in ACRO.finditer(prose):
            acro = am.group(1)
            if acro in allow or acro in seen_acro:
                continue
            seen_acro.add(acro)
            tail = prose[am.end():am.end() + 2]
            if not tail.lstrip().startswith("("):
                report("W", path, lineno + 1, "ACRONYM", acro, "약어 첫 등장 — 풀어쓰기 `약어(뜻)` 또는 patterns.txt ALLOW에 추가")

    if in_fence:
        # 코드 펜스가 닫히지 않으면 그 아래 전부가 코드로 렌더링된다 — 발췌를 교체하다 여는 펜스를 지운 사고가 계기
        report("E", path, fence_open_line or 0, "FENCE", "```", "코드 펜스가 닫히지 않았다 — 이 줄 이후 문서 전체가 코드 블록으로 렌더링된다")

print()
print(f"파일 {len(files)}개 · 오류 {errors} · 경고 {warnings}")
sys.exit(1 if errors else 0)
PYTHON
