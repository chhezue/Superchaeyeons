"""두 도구가 공유하는 문서 확장자와 완료 선언 판정."""
import re, os

test_words = globals().get("test_words") or ["__no_test_configured__"]

DOC_EXT = (".md", ".txt", ".rst")
CLAIM = re.compile(
    r"(?<!미)완료(?!\s?(조건|기준|선언|보고))"
    r"|통과(?!\s?(하지|시키지|못|하지 못))"
    r"|끝났|마쳤|성공|정상 ?(동작|작동)"
    r"|(구현|적용|반영|수정)(했|됐|되었|완료)"
    r"|\bdone\b|\bpassed\b|\bfixed\b|\bcomplete[d]?\b|\bimplemented\b|\bworks\b",
    re.I,
)
# TEST_CMD "실행" = 명령의 시작, 또는 ; && || | ( 뒤에 (bash|sh|source|.) 접두사와 경로를 붙여 부른 것. 인용·cat·grep은 실행이 아니다.
# 첫 단어는 파일 이름만, 나머지 단어는 그대로 맞춰 보고, 그 뒤에는 리다이렉션(2>&1 · 2>/dev/null · > 파일)과
# 명령 끝(; & | ) 줄바꿈)만 허용한다. 파일로 보내는 리다이렉션은 아래 편집 판정이 먼저 잡는다.
TEST_RUN = re.compile(
    r"(^|[;&|(\n]\s*)((bash|sh|source|\.)\s+)?(\S*/)?" + re.escape(os.path.basename(test_words[0]))
    + "".join(r"\s+" + re.escape(w) for w in test_words[1:])
    + r"(?=(?:\s*(?:[0-9]*>&[0-9]+|&>>?\s*\S+|[0-9]*>>?\s*\S+))*\s*(?:$|[;&|)\n]))"
)
# heredoc 본문은 데이터로 보고 뺀다. 단 here-string(<<<)은 heredoc이 아니고, 닫는 줄이 없으면 heredoc으로 보지 않으며,
# 셸·인터프리터에 넘긴 본문(bash <<EOF)은 실행되는 코드라 남긴다 — 빼면 그 안의 편집을 놓친다 (2026-10-24 리뷰)
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*([\"\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1")
EXEC_FEED = re.compile(r"(^|[;&|(\s])(bash|sh|zsh|dash|ksh|python3?|node|ruby|perl)(\s|$)")

def strip_heredocs(cmd):
    lines = cmd.split("\n"); out = []; i = 0
    while i < len(lines):
        cur = lines[i]; out.append(cur); i += 1
        for m in HEREDOC.finditer(cur):
            if EXEC_FEED.search(cur[:m.start()]):
                continue
            j = i
            while j < len(lines) and lines[j].strip() != m.group(2):
                j += 1
            if j < len(lines):
                i = j + 1
    return "\n".join(out)
# 따옴표 안·주석·백슬래시로 이스케이프한 글자는 데이터다 — 커밋 메시지 -m "… <a@b.com>…"의 `>`를 리다이렉션으로 오판하던
# 사각(2026-10-26 실세션). 단 셸에 넘긴 문자열(bash -c "…" · eval "…")은 실행되는 코드라 그 안을 다시 따진다.
# $"…" 안의 $(…)는 코드지만 데이터로 본다 — 그 안의 편집은 놓친다.
EXEC_STR = re.compile(r"(?:(?:^|[;&|(\s])(?:bash|sh|zsh|dash|ksh)(?:\s+-[a-zA-Z]+)*\s+-[a-zA-Z]*c[a-zA-Z]*|(?:^|[;&|(\s])eval)\s+$")

def data_mask(cmd):
    n = len(cmd); mask = [False] * n; i = 0
    while i < n:
        c = cmd[i]
        if c == "\\":
            mask[i:i + 2] = [True] * len(cmd[i:i + 2]); i += 2
        elif c == "#" and (i == 0 or cmd[i - 1] in " \t\n;&|("):
            j = cmd.find("\n", i); j = n if j < 0 else j
            mask[i:j] = [True] * (j - i); i = j
        elif c in "\"\x27":
            ansi = c == "\x27" and i > 0 and cmd[i - 1] == "$"
            j = i + 1
            while j < n and cmd[j] != c:
                j += 2 if cmd[j] == "\\" and (c == "\"" or ansi) else 1
            j = min(j, n)
            mask[i:j + 1] = [True] * len(cmd[i:j + 1])
            if EXEC_STR.search(cmd[:i]):
                mask[i + 1:j] = data_mask(cmd[i + 1:j])
            i = j + 1
        else:
            i += 1
    return mask
# Bash 편집 검출 — 리다이렉션 대상, tee 대상, sed -i 의 파일 피연산자. /dev/null·&1·문서 확장자·저장소 밖 절대 경로는 편집이 아니다.
REDIRECT = re.compile(r"(?<![<>&0-9])>{1,2}\s*[\"\x27]?([^\s\"\x27&|;<>]+)")
TEE = re.compile(r"\btee\s+(?:-[a-zA-Z]+\s+)*[\"\x27]?([^\s\"\x27&|;<>]+)")
SED = re.compile(r"(?:^|(?<=[;&|(\s]))sed\s")
ASSIGN = re.compile(r"(?:^|(?<=[;&|(\s]))(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"]*\"|\x27[^\x27]*\x27|[^\s;&|()]*)")
VAR = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
# 저장소 = CLAUDE_PROJECT_DIR · git 최상위 · 현재 폴더 중 어디든 — 워크트리처럼 셋이 다를 때 하나라도 안이면 편집으로 본다
def _roots():
    cands = [os.environ.get("CLAUDE_PROJECT_DIR") or "", os.getcwd()]
    try:
        import subprocess
        cands.append(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=5).stdout.strip())
    except Exception:
        pass
    return [os.path.realpath(c) for c in cands if c]
ROOTS = _roots()
# 실패 판정은 좁게 — 테스트 러너의 요약 줄만 본다. "0 failed"·"error" 같은 일반어는 통과 출력에도 흔해 오탐이 났다(2026-09-07 실세션).
FAILED = re.compile(
    r"실패 있음|실패 [1-9]|오류 [1-9]|\bFAIL(ED|URE)?\b|BUILD FAILED|Tests? failed"
    r"|[1-9][0-9]* (failed|failures?|errors?)\b|\bexit code [1-9]"
)

def is_doc(p):
    p = p.lower()
    return p.endswith(DOC_EXT)

# 쓰기 대상이 저장소 안 코드 파일인가. `$VAR`는 같은 명령에서 그 앞에 대입한 값(S=… &&)과 환경 변수로 푼다.
# 풀지 못한 변수(반복문 변수 등)는 저장소 안으로 본다 — `for f in *.sh; do … > "$f"` 같은 편집을 놓치지 않으려고.
def is_code_target(t, assigns=None):
    if not t or t.startswith(("/dev/", "&")) or is_doc(t):
        return False
    env = dict(os.environ); env.update(assigns or {})
    t = VAR.sub(lambda m: env.get(m.group(1) or m.group(2), m.group(0)), t)
    t = os.path.expanduser(t)
    if is_doc(t):
        return False
    if t.startswith("/") and "$" not in t:
        real = os.path.realpath(t)
        return any(real == r or real.startswith(r.rstrip("/") + "/") for r in ROOTS)
    return True

def assigns_before(cmd, mask, pos):
    out = {}
    for m in ASSIGN.finditer(cmd, 0, pos):
        if mask[m.start()]:
            continue
        v = m.group(2)
        if v[:1] in "\"\x27":
            v = v[1:-1]
        out[m.group(1)] = VAR.sub(lambda x: out.get(x.group(1) or x.group(2), os.environ.get(x.group(1) or x.group(2), x.group(0))), v)
    return out

# sed 한 명령의 낱말에서 파일 피연산자를 고른다. 식(-e 인자 · 첫 번째 비옵션 인자)과 -f 스크립트 파일은 대상이 아니다.
# -i 접미사는 붙여 쓰거나(-i.bak) BSD식으로 따로 쓴다(-i '' · -i .bak). 반환: (제자리 편집인가, 피연산자 목록), 못 나누면 None
def sed_operands(words):
    in_place = False; script = False; files = []; i = 1; opts_done = False
    while i < len(words):
        w = words[i]; i += 1
        if re.match(r"^[0-9]*[<>]", w):
            if re.fullmatch(r"[0-9]*[<>]{1,2}&?", w):
                i += 1
            continue
        if not opts_done and w == "--":
            opts_done = True
        elif not opts_done and w.startswith("--"):
            name, eq, _ = w[2:].partition("=")
            if name == "in-place":
                in_place = True
            elif name in ("expression", "file"):
                script = True; i += 0 if eq else 1
            elif name == "line-length" and not eq:
                i += 1
        elif not opts_done and w.startswith("-") and len(w) > 1:
            k = 1
            while k < len(w):
                c = w[k]; rest = w[k + 1:]
                if c == "i":
                    in_place = True
                    if not rest and i < len(words) and (words[i] == "" or words[i].startswith(".")):
                        i += 1
                    break
                if c in "ef":
                    script = True
                    if not rest:
                        i += 1
                    break
                if c == "l":
                    if not rest:
                        i += 1
                    break
                k += 1
        elif not script:
            script = True
        else:
            files.append(w)
    return in_place, files

def sed_edit(cmd, mask, start, assigns):
    end = start
    while end < len(cmd) and (mask[end] or cmd[end] not in ";&|\n)"):
        end += 1
    try:
        import shlex
        words = shlex.split(cmd[start:end], comments=True)
    except ValueError:
        return True
    in_place, files = sed_operands(words)
    if not in_place:
        return False
    # 피연산자가 없으면(xargs·find로 넘김) 무엇을 고치는지 모른다 — 편집으로 본다
    return not files or any(is_code_target(f, assigns) for f in files)

# 둘 다 명령 안에서의 마지막 위치를 돌려준다(없으면 -1) — 한 명령 안의 편집과 테스트 실행은 순서로 판정한다.
def last_code_edit(cmd, mask):
    at = -1
    for rx in (REDIRECT, TEE):
        for m in rx.finditer(cmd):
            if not mask[m.start()] and is_code_target(m.group(1), assigns_before(cmd, mask, m.start())):
                at = max(at, m.start())
    for m in SED.finditer(cmd):
        if not mask[m.start()] and sed_edit(cmd, mask, m.start(), assigns_before(cmd, mask, m.start())):
            at = max(at, m.start())
    return at

def last_test_run(cmd, mask):
    at = -1
    for m in TEST_RUN.finditer(cmd):
        if not mask[m.end(1)]:
            at = m.end(1)
    return at
