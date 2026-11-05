#!/bin/bash
# 승인 창 — 되돌리기 어려운 행동에 사용자 승인 창(permissionDecision "ask")을 띄운다. 에이전트가 흉내 낼 수 없는 승인 통로다.
# Registered in plugin/hooks/hooks.json (PreToolUse Bash|Write|Edit|MultiEdit|NotebookEdit).
# harness-plugin-delivery 스펙 "행동 강제 — 승인 창". 범주마다 설정(.claude/harness.conf)의 플래그로 켜고 끈다.
#   커밋·원격 반영(ASK_COMMIT) — git commit · git push · gh pr create · gh pr merge. git commit은 창 전에 검사한다:
#       메시지 첫 줄이 COMMIT_RE에 맞는가(Merge·Revert 제외) · 바뀐 마크다운의 문서 스타일(플러그인 check-doc-style.sh, 오류만) ·
#       COMMIT_CHECK 명령. 하나라도 실패하면 이유와 함께 막는다(deny). 이유에 스테이징된 파일 수·첫 줄·CONTRACT_PATHS에 맞는 파일
#   삭제(ASK_DELETE) — rm · git rm 대상, mv가 덮어쓰는 대상이 git이 추적하는 파일이면(폴더는 그 아래 추적 파일이 있으면)
#   의존성(ASK_DEPS) — DEPS_FILES glob에 맞는 파일 쓰기 · DEPS_ADD_CMD 접두사(| 구분)로 시작하는 명령 세그먼트
#   민감한 경로(ASK_SENSITIVE) — ASK_PATHS glob에 맞는 파일 쓰기
#   스펙 승인·[미정] 확정(ASK_SPEC) — SPEC_DIR·DECISIONS_DIR 아래 .md의 상태 줄이 Approved로 바뀌거나 [미정] 개수가 주는 편집
#   설정 파일 — 채워진(빈칸 없는) .claude/harness.conf를 고치면 늘 창(이유에 바뀌는 키와 값). 없거나 빈칸이 남았으면(init 중) 띄우지 않는다
# 띄우지 않는 경우도 케이스로 판정한다(scripts/hook-cases.txt) — 창이 잦으면 사람이 보지 않고 누르게 된다.
# 설정이 없으면 엄격한 기본값(범주 전부 켬 · 목록 비움), 설정이 깨졌거나 입력을 해석하지 못하면(python3 없음 포함) 판정 불가로 ask.
# 한계: 명령 문자열만 본다. 같은 명령 안의 `git add`는 아직 반영되기 전이라 스테이징 파일 수는 지금 기준이다.
# Hook input: JSON with "tool_name", "tool_input" on stdin.

ask_raw() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"; exit 0; }
command -v python3 >/dev/null 2>&1 || ask_raw "판정 불가 — python3가 없어 하네스 승인 창 훅이 명령을 해석하지 못했다"

input=$(cat)
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")}"
root="${CLAUDE_PLUGIN_ROOT:-${0%/*}/..}"

IFS= read -r -d '' JUDGE <<'PY'
import fnmatch, json, os, re, shlex, subprocess, sys

PROJ, ROOT = os.environ["PROJ"], os.environ["PLUGIN"]

def out(decision, reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                             "permissionDecisionReason": reason}}, ensure_ascii=False))
    sys.exit(0)

# ---- 입력 ----
try:
    data = json.loads(sys.stdin.read())
    tool, ti = data["tool_name"], data["tool_input"]
    if not isinstance(ti, dict):
        raise ValueError
except Exception:
    out("ask", "판정 불가 — 훅 입력을 해석하지 못했다")

# ---- 설정 ----
CONF_PATH = os.path.join(PROJ, ".claude", "harness.conf")
BLANK = re.compile(r"^\{[^{}]*\}$")
conf, conf_found = {}, os.path.isfile(CONF_PATH)
if conf_found:
    for line in open(CONF_PATH, encoding="utf-8"):
        line = line.rstrip("\r\n")
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", line)
        if not m:
            out("ask", f"판정 불가 — .claude/harness.conf에 키=값이 아닌 줄이 있다 ({line[:40]})")
        conf[m.group(1)] = m.group(2)
def flag(key):
    v = conf.get(key, "1")
    if v not in ("0", "1"):
        out("ask", f"판정 불가 — .claude/harness.conf의 {key} 값이 0/1이 아니다 ({v})")
    return v == "1"
def value(key):
    v = conf.get(key, "").strip()
    return "" if BLANK.match(v) or v.startswith("(없음)") else v
ASK = {k: flag(k) for k in ("ASK_COMMIT", "ASK_DELETE", "ASK_DEPS", "ASK_SENSITIVE", "ASK_SPEC")}

def rel(path):
    p = path if os.path.isabs(path) else os.path.join(PROJ, path)
    p = os.path.normpath(p)
    root = os.path.normpath(PROJ)
    return os.path.relpath(p, root) if p == root or p.startswith(root + os.sep) else None

def glob_match(path, globs):
    for g in globs.split():
        cands = {g, g[3:] if g.startswith("**/") else g, g.replace("/**/", "/")}
        for c in cands:
            if fnmatch.fnmatchcase(path, c) or (c.endswith("/**") and (path + "/").startswith(c[:-2])):
                return True
    return False

def git(*args):
    return subprocess.run(["git", "-C", PROJ, *args], capture_output=True, text=True)

def tracked(path):
    r = git("ls-files", "--", path)
    return r.returncode == 0 and r.stdout.strip() != ""

def plugin_cmd(cmd):
    first = cmd.split()[0] if cmd.split() else ""
    if first and not os.path.isabs(first) and not os.path.exists(os.path.join(PROJ, first)) \
            and os.path.exists(os.path.join(ROOT, first)):
        return os.path.join(ROOT, cmd)
    return cmd

# ---- 파일 쓰기 도구 ----
if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
    raw = ti.get("file_path") or ti.get("notebook_path") or ""
    if not raw:
        out("ask", "판정 불가 — 쓰기 대상 경로가 없다")
    r = rel(raw)
    if r is None:
        sys.exit(0)
    full = os.path.join(PROJ, r)
    old = open(full, encoding="utf-8").read() if os.path.isfile(full) else None
    def new_content():
        if tool == "Write":
            return ti.get("content", "")
        if tool == "NotebookEdit":
            return None
        text = old or ""
        edits = ti.get("edits") if tool == "MultiEdit" else [ti]
        for e in edits or []:
            o, n = e.get("old_string", ""), e.get("new_string", "")
            text = text.replace(o, n) if e.get("replace_all") else text.replace(o, n, 1)
        return text
    # 설정 파일 — 채워진 뒤에는 늘 창
    if r == os.path.join(".claude", "harness.conf"):
        if old is None or any(BLANK.match(v.strip()) for v in conf.values()):
            sys.exit(0)
        new = new_content() or ""
        parse = lambda t: dict(m.groups() for m in re.finditer(r"^([A-Z][A-Z0-9_]*)=(.*)$", t, re.M))
        a, b = parse(old), parse(new)
        changes = [f"`{k}`: {a.get(k, '(없음)')} → {b.get(k, '(지움)')}" for k in list(a) + [k for k in b if k not in a]
                   if a.get(k) != b.get(k)]
        out("ask", "설정 변경 — " + (" · ".join(changes) if changes else "키 값은 그대로(주석·형식만)"))
    reasons = []
    if ASK["ASK_DEPS"] and value("DEPS_FILES") and glob_match(r, value("DEPS_FILES")):
        reasons.append(f"의존성 — `{r}` 수정")
    if ASK["ASK_SENSITIVE"] and value("ASK_PATHS") and glob_match(r, value("ASK_PATHS")):
        reasons.append(f"민감한 경로 — `{r}` 쓰기")
    if ASK["ASK_SPEC"] and r.endswith(".md"):
        dirs = [d.strip("/") for d in (value("SPEC_DIR"), value("DECISIONS_DIR")) if d]
        if any(r.startswith(d + "/") for d in dirs):
            new = new_content() or ""
            status = lambda t: (re.search(r"^>\s*상태:\s*(\S+)", t or "", re.M) or [None, ""])[1]
            count = lambda t: (t or "").count("[미정]")
            name = os.path.basename(r)
            if status(new).startswith("Approved") and not status(old).startswith("Approved"):
                reasons.append(f"스펙 승인 — `{name}` · [미정] {count(new)}개")
            elif old is not None and count(new) < count(old):
                reasons.append(f"[미정] 확정 — `{name}` · [미정] {count(old)}→{count(new)}개")
    if reasons:
        out("ask", " / ".join(reasons))
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = ti.get("command")
if not isinstance(cmd, str):
    out("ask", "판정 불가 — 명령이 없다")

# ---- 명령 해석: heredoc 본문을 떼어 두고, 따옴표를 지키며 세그먼트로 나눈다 ----
heredocs, lines, i = [], cmd.split("\n"), 0
kept = []
while i < len(lines):
    line = lines[i]; kept.append(line); i += 1
    for m in re.finditer(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line):
        body = []
        while i < len(lines) and lines[i].strip() != m.group(2):
            body.append(lines[i]); i += 1
        i += 1
        heredocs.append("\n".join(body))
try:
    lex = shlex.shlex("\n".join(kept), posix=True, punctuation_chars=";&|()\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    out("ask", "판정 불가 — 명령의 따옴표를 해석하지 못했다")
segs, cur = [], []
for t in toks:
    if t and set(t) <= set(";&|()\n"):
        if cur: segs.append(cur)
        cur = []
    else:
        cur.append(t)
if cur: segs.append(cur)

def strip_env(seg):
    while seg and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[0]):
        seg = seg[1:]
    return seg

def git_sub(seg):
    k = 1
    while k < len(seg) and seg[k].startswith("-"):
        k += 2 if seg[k] in ("-C", "-c") else 1
    return (seg[k], seg[k + 1:]) if k < len(seg) else (None, [])

reasons, hd = [], 0
for seg in map(strip_env, segs):
    if not seg:
        continue
    words = seg
    head = os.path.basename(words[0])
    text = " ".join(words)
    if "<<" in text:
        hd_here = hd; hd += text.count("<<")
    else:
        hd_here = None
    if head == "git":
        sub, args = git_sub(words)
        if sub == "commit" and ASK["ASK_COMMIT"]:
            msg, known = None, True
            for k, a in enumerate(args):
                if a in ("-m", "--message") and k + 1 < len(args):
                    msg = args[k + 1]; break
                if a.startswith("--message="):
                    msg = a.split("=", 1)[1]; break
                if a.startswith("-m") and len(a) > 2:
                    msg = a[2:]; break
                if a in ("-F", "--file") and k + 1 < len(args):
                    src = args[k + 1]
                    if src == "-" and hd_here is not None and hd_here < len(heredocs):
                        msg = heredocs[hd_here]
                    elif src != "-" and os.path.isfile(os.path.join(PROJ, src)):
                        msg = open(os.path.join(PROJ, src), encoding="utf-8").read()
                    break
            first = (msg or "").split("\n", 1)[0].strip()
            if msg is None:
                known = False
            pattern = value("COMMIT_RE")
            if known and pattern and not first.startswith(("Merge ", "Revert ")):
                try:
                    ok = re.search(pattern, first) is not None
                except re.error:
                    out("ask", f"판정 불가 — COMMIT_RE를 정규식으로 해석하지 못했다 ({pattern})")
                if not ok:
                    out("deny", f"커밋 막힘 — 메시지 첫 줄이 COMMIT_RE({pattern})와 맞지 않는다: `{first}`. 형식을 고쳐 다시 커밋한다")
            # 바뀐 마크다운의 문서 스타일 — 오류만 막는다
            style = os.path.join(ROOT, "scripts", "check-doc-style.sh")
            changed = set(git("diff", "--name-only", "HEAD").stdout.split()) | set(git("diff", "--name-only", "--cached").stdout.split()) \
                      | set(git("ls-files", "--others", "--exclude-standard").stdout.split())
            md = sorted(f for f in changed if f.endswith(".md") and os.path.isfile(os.path.join(PROJ, f)))
            if md and os.path.isfile(style):
                r = subprocess.run([style, *md], cwd=PROJ, capture_output=True, text=True)
                if r.returncode == 1:
                    errs = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("E ")][:3]
                    out("deny", "커밋 막힘 — 문서 스타일 오류: " + " / ".join(errs or ["check-doc-style.sh 실패"]))
            check = value("COMMIT_CHECK")
            if check:
                r = subprocess.run(["sh", "-c", plugin_cmd(check)], cwd=PROJ, capture_output=True, text=True)
                if r.returncode != 0:
                    tail = " ".join((r.stdout + r.stderr).strip().splitlines()[-3:])[:300]
                    out("deny", f"커밋 막힘 — 커밋 전 검사 `{check}` 실패(exit {r.returncode}): {tail}")
            staged = [f for f in git("diff", "--cached", "--name-only").stdout.split("\n") if f]
            note = [f"파일 {len(staged)}개", f"`{first}`" if known else "메시지 확인 못 함"]
            contract = [f for f in staged if value("CONTRACT_PATHS") and glob_match(f, value("CONTRACT_PATHS"))]
            if contract:
                note.append("API 계약 " + ", ".join(f"`{f}`" for f in contract))
            reasons.append("커밋 — " + " · ".join(note))
        elif sub == "push" and ASK["ASK_COMMIT"]:
            reasons.append("원격 반영 — " + text)
        elif sub == "rm" and ASK["ASK_DELETE"]:
            hit = [a for a in args if not a.startswith("-") and tracked(a)]
            if hit:
                reasons.append("삭제 — 추적 중인 " + ", ".join(f"`{h}`" for h in hit))
    elif head == "gh" and len(words) > 2 and words[1] == "pr" and words[2] in ("create", "merge") and ASK["ASK_COMMIT"]:
        reasons.append("원격 반영 — " + " ".join(words[:3]))
    elif head == "rm" and ASK["ASK_DELETE"]:
        targets = [a for a in words[1:] if a != "--" and not a.startswith("-")]
        hit = [t for t in targets if tracked(t)]
        if hit:
            reasons.append("삭제 — 추적 중인 " + ", ".join(f"`{h}`" for h in hit))
    elif head == "mv" and ASK["ASK_DELETE"]:
        args = [a for a in words[1:] if not a.startswith("-")]
        if len(args) >= 2:
            dest = args[-1]
            dests = [os.path.join(dest, os.path.basename(s)) for s in args[:-1]] if os.path.isdir(os.path.join(PROJ, dest)) else [dest]
            hit = [d for d in dests if os.path.isfile(os.path.join(PROJ, d)) and tracked(d)]
            if hit:
                reasons.append("삭제 — 추적 중인 " + ", ".join(f"`{h}`" for h in hit) + " 덮어쓰기")
    if ASK["ASK_DEPS"] and value("DEPS_ADD_CMD"):
        for prefix in (p.strip() for p in value("DEPS_ADD_CMD").split("|")):
            pw = prefix.split()
            if pw and words[:len(pw)] == pw:
                reasons.append("의존성 추가 — " + text)
                break
if reasons:
    out("ask", " / ".join(reasons))
PY

PROJ="$proj" PLUGIN="$root" python3 -I -c "$JUDGE" <<<"$input" || ask_raw "판정 불가 — 하네스 승인 창 훅 내부 오류"
exit 0
