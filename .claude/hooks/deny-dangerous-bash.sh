#!/bin/bash
# Blocks destructive shell commands. Registered in .claude/settings.json (PreToolUse/Bash, onFailure: block).
# Hook input: JSON with "tool_input.command" field on stdin (Claude Code PreToolUse schema).
# 실제로 실행되는 부분만 검사한다 — 따옴표·heredoc·주석 안의 글자는 데이터로 보고, 그 글자가 실행되는 자리
# (bash/sh -c 인자 · eval · ssh 뒤 · SQL 클라이언트 인자 · $(…)·백틱 · 셸·SQL·런타임이 받는 heredoc·파이프 · 런타임 코드의 셸 호출 줄)는 다시 검사한다.
# 셸 문법을 해석하지 못하면(닫히지 않은 따옴표 등) 명령 원문 전체를 대조한다 — 지금보다 덜 막는 경로가 생기지 않게.

# 훅 공통 규약: 판정 불가(JSON 깨짐·command 키 없음·빈 입력·python3 없음) = 차단. scripts/test-hooks.sh가 케이스 파일로 판정한다.

# 묶음별 처리 — 1: 이 훅이 막는다 · 0: 이 훅은 보지 않고 Claude Code 권한 체계(permissions.deny · 권한 확인 · auto mode 판정기)에 맡긴다.
# 0으로 바꾸면 .claude/settings.json permissions.deny의 같은 묶음 줄도 빼야 실제로 풀린다. 값은 사용자가 정한다.
BLOCK_FORCE_PUSH="1"    # 원격 이력 덮어쓰기 — force push
BLOCK_BULK_DELETE="0"   # 파일 대량 삭제 — rm -rf · find -delete · find -exec rm (0이어도 루트·홈·현재 폴더 통째 삭제는 막는다)
BLOCK_GIT_DISCARD="1"   # 로컬 git 이력·작업 트리 버리기 — reset --hard · clean -f · branch -D · stash drop/clear · filter-branch · update-ref -d/--stdin
BLOCK_CHECK_BYPASS="1"  # 검사 우회·시크릿 커밋 — commit --no-verify · .env add/commit
BLOCK_DATA_DELETE="1"   # 데이터 저장소 삭제 — SQL DROP · compose down -v · 볼륨 삭제
BLOCK_SYSTEM="1"        # 시스템 위험 — curl|sh · chmod -R 777 · dd of=/dev/

input=$(cat)

# 판정기. 출력: ok · block<TAB>상수<TAB>묶음 이름 · __UNPARSEABLE__. python3가 없거나 죽으면(exit ≠ 0) 판정 불가로 본다.
# `python3 -I`: 작업 폴더의 json.py 같은 파일·PYTHON* 환경 변수가 판정기에 섞이지 않게 한다.
# 여기서 막지 못하는 것(규칙으로만 금지): 변수에 담은 명령·플래그, 파일 간접 실행(`bash x.sh`), 함수·별칭, 글자를 조립해 셸에 넘기기,
# 런타임의 리스트형 호출(`subprocess.run(["git", …])`), `truncate`·`: > file`.
IFS= read -r -d '' JUDGE <<'PY'
import json, os, re, sys

GROUPS = [
    ("BLOCK_FORCE_PUSH", "원격 이력 덮어쓰기(force push)", [
        r"git\s+push(\s+\S+)*\s+(--force\S*|-[a-zA-Z]*f[a-zA-Z]*|\+\S+)(\s|$)",
    ]),
    ("BLOCK_BULK_DELETE", "파일 대량 삭제(rm -rf · find -delete)", [
        r"rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*\b|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*\b|-[a-zA-Z]*[rR][a-zA-Z]*\s+-[a-zA-Z]*[fF][a-zA-Z]*\b|-[a-zA-Z]*[fF][a-zA-Z]*\s+-[a-zA-Z]*[rR][a-zA-Z]*\b|--recursive\s+--force|--force\s+--recursive)",
        r"find\s+[^|;&]*(-delete(\s|$)|-exec\s+rm(\s|$))",
    ]),
    ("BLOCK_GIT_DISCARD", "로컬 git 이력·작업 트리 버리기", [
        r"git\s+reset\s+--hard",
        r"git\s+clean(\s+\S+)*\s+(-[a-zA-Z]*f[a-zA-Z]*|--force)(\s|$)",
        r"git\s+branch(\s+\S+)*\s+-[a-zA-Z]*D[a-zA-Z]*(\s|$)",
        r"git\s+stash\s+(drop|clear)(\s|$)",
        r"git\s+filter-branch",
        r"git\s+update-ref(\s+\S+)*\s+(-d|--stdin)(\s|$)",
    ]),
    ("BLOCK_CHECK_BYPASS", "검사 우회·시크릿 커밋", [
        r"git\s+commit(\s+\S+)*\s+(--no-verify|-[a-zA-Z]*n[a-zA-Z]*)(\s|$)",
        r"git\s+(add|commit)(\s+\S+)*\s+\S*\.env(\.(local|prod|production|dev|development|staging|test))?(\s|$)",
    ]),
    ("BLOCK_DATA_DELETE", "데이터 저장소 삭제(SQL DROP · 볼륨)", [
        r"(?i:drop)\s+(?i:database|table|schema)\s",
        r"docker(-compose|\s+compose)\s+down(\s+\S+)*\s+(-v|--volumes)(\s|$)",
        r"docker\s+(system\s+prune(\s+\S+)*\s+--volumes|volume\s+(rm|prune))",
    ]),
    ("BLOCK_SYSTEM", "시스템 위험(curl|sh · chmod 777 · dd)", [
        r"(curl|wget)[^|]*\|\s*(sudo\s+)?(ba|z|da)?sh(\s|$)",
        r"chmod(\s+\S+)*\s+-[a-zA-Z]*R[a-zA-Z]*(\s+\S+)*\s+[0-7]*777(\s|$)",
        r"dd\s+[^|;&]*of=/dev/",
    ]),
]
# 삭제 묶음을 맡겨도 막는 바닥 — 루트·홈·현재·상위 폴더·.git 통째 재귀 삭제
FLOOR = ("BLOCK_BULK_DELETE", "파일 대량 삭제 — 루트·홈·현재 폴더·.git 통째 삭제(묶음 값과 무관)")
FLOOR_TARGETS = {"/", "/*", "~", "~/*", "$HOME", "$HOME/*", "${HOME}", "${HOME}/*", ".", "./*", "..", ".git", "./.git"}  # 끝의 / 는 떼고 비교
FLOOR_RAW = re.compile(r"(^|\s)rm\s+(\S+\s+)*?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\s+(\S+\s+)*?(/|/\*|~/?|\$HOME/?|\$\{HOME\}/?|\.{1,2}/?|(\./)?\.git/?)(\s|$)|--no-preserve-root")

SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
SQL_CLIENTS = {"psql", "mysql", "mariadb", "sqlite3", "sqlcmd", "clickhouse-client", "duckdb"}
RUNTIME = re.compile(r"^(python[0-9.]*|node|nodejs|deno|bun|perl|ruby|php)$")
SHELL_CALL = re.compile(r"os\.system|os\.popen|subprocess|Popen|pty\.spawn|commands\.getoutput|child_process|execSync|spawnSync|\bexec\s*\(|\bspawn\s*\(|\bsystem\s*\(|`|%x|shell_exec|passthru|proc_open")
# 뒤에 오는 다른 명령을 실행하는 명령 — 이것으로 시작하는 세그먼트는 어느 자리의 셸·SQL·런타임이든 실행기로 본다
LAUNCHERS = {"sudo", "doas", "env", "command", "exec", "nohup", "time", "nice", "ionice", "timeout", "stdbuf", "xargs", "parallel",
             "docker", "podman", "kubectl", "ssh", "su", "runuser", "chroot", "setsid", "flock", "watch", "unbuffer", "fakeroot", "systemd-run"}
# 런타임별 코드를 받는 짧은 옵션 글자 · 값을 받는 짧은 옵션 글자
CODE_FLAGS = {"python": "c", "node": "ep", "deno": "ep", "bun": "ep", "perl": "eE", "ruby": "e", "php": "r"}
ARG_FLAGS = {"python": "WXm", "node": "r", "deno": "", "bun": "r", "perl": "", "ruby": "rI", "php": "dcf"}
SHELL_LONG_ARG = {"--rcfile", "--init-file"}
SSH_ARG_FLAGS = "BbcDEeFIiJLlmOoPpQRSWw"
MAX_DEPTH = 8

enabled = [(k, label, [re.compile(p) for p in pats]) for k, label, pats in GROUPS if os.environ.get(k, "1") != "0"]


class Unparseable(Exception):
    pass


class Seg:
    def __init__(self, pipe_in):
        self.words = []      # (글자, 따옴표 포함 여부) — 리다이렉션과 그 대상은 빼고 담는다
        self.bodies = []     # heredoc·here-string 본문: [(글자, 셸 확장 여부)]
        self.subs = []       # $(…)·백틱·<(…) 안에서 해석한 Seg 목록들
        self.procsubs = []   # <(…)·>(…) 원문 — 셸에 스크립트로 넘기면 원문을 대조한다
        self.pipe_in = pipe_in


def ansi_c(s, i):
    """$'…' 안을 읽는다. i는 여는 ' 다음. (글자, 닫는 ' 다음 위치)"""
    out = []
    table = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "'": "'", '"': '"', "e": "\x1b", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            out.append(table.get(s[i + 1], "\\" + s[i + 1]))
            i += 2
            continue
        if c == "'":
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise Unparseable


class Parser:
    def __init__(self, s, depth):
        self.s, self.depth, self.pending, self.in_sub = s, depth, [], False

    def parse(self, i=0, closing=False):
        s, segs = self.s, []
        seg = Seg(False)
        word, quoted, in_word = [], False, False
        paren = case_depth = 0

        def end_word():
            nonlocal word, quoted, in_word, case_depth
            if in_word:
                text = "".join(word)
                if not quoted and text == "case" and not seg.words:
                    case_depth += 1
                elif not quoted and text == "esac" and case_depth:
                    case_depth -= 1
                seg.words.append((text, quoted))
            word, quoted, in_word = [], False, False

        def new_seg(pipe):
            nonlocal seg
            end_word()
            segs.append(seg)
            seg = Seg(pipe)

        while i < len(s):
            c = s[i]
            if c == "\\":
                if i + 1 < len(s) and s[i + 1] == "\n":
                    i += 2
                    continue
                word.append(s[i + 1] if i + 1 < len(s) else "")
                in_word = True
                i += 2
                continue
            if c == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    raise Unparseable
                word.append(s[i + 1:j])
                quoted = in_word = True
                i = j + 1
                continue
            if c == "$" and s.startswith("$'", i):
                text, i = ansi_c(s, i + 2)
                word.append(text)
                quoted = in_word = True
                continue
            if c == '"':
                i = self.dquote(i + 1, word, seg)
                quoted = in_word = True
                continue
            if c == "`":
                i = self.backtick(i + 1, seg)
                word.append("$()")
                in_word = True
                continue
            if c == "$" and s.startswith("$(", i):
                sub, i = Parser(s, self.depth + 1).parse_sub(i + 2, self)
                seg.subs.append(sub)
                word.append("$()")
                in_word = True
                continue
            if c in "<>" and s.startswith("(", i + 1) and not in_word:
                start = i
                sub, i = Parser(s, self.depth + 1).parse_sub(i + 2, self)
                seg.subs.append(sub)
                seg.procsubs.append(s[start + 2:i - 1])
                word.append("$()")
                in_word = True
                continue
            if c == "#" and not in_word:
                j = s.find("\n", i)
                i = len(s) if j < 0 else j
                continue
            if c in " \t":
                end_word()
                i += 1
                continue
            if c == "\n":
                new_seg(False)
                i = self.read_heredocs(i + 1)
                continue
            if c == "<" and s.startswith("<<", i) and not s.startswith("<<<", i):
                end_word()
                i += 2
                strip = s.startswith("-", i)
                if strip:
                    i += 1
                while i < len(s) and s[i] in " \t":
                    i += 1
                delim, dq, i = self.read_word(i)
                body = []
                seg.bodies.append(body)
                self.pending.append((delim, strip, dq, body))
                continue
            if c == "<" and s.startswith("<<<", i):
                end_word()
                i += 3
                while i < len(s) and s[i] in " \t":
                    i += 1
                text, _, i = self.read_word(i)
                seg.bodies.append([(text, False)])
                continue
            if c in "<>" or (c == "&" and s.startswith(">", i + 1)):
                # 리다이렉션 — 앞의 숫자(파일 번호)와 대상은 명령 인자가 아니다
                if in_word and not quoted and "".join(word).isdigit():
                    word, in_word = [], False
                else:
                    end_word()
                j = i
                while j < len(s) and s[j] in "<>&":
                    j += 1
                if j < len(s) and s[j] == "|" and s[j - 1] == ">":
                    j += 1
                while j < len(s) and s[j] in " \t":
                    j += 1
                _, _, i = self.read_word(j)
                continue
            if c in ";&|()":
                op = s[i:i + 2] if s[i:i + 2] in ("&&", "||", ";;", "|&") else c
                if op == "(":
                    paren += 1
                elif op == ")":
                    if paren == 0 and case_depth == 0 and closing:
                        new_seg(False)
                        return [x for x in segs if x.words or x.bodies or x.subs], i + 1
                    if paren:
                        paren -= 1
                new_seg(op in ("|", "|&"))
                i += len(op)
                continue
            word.append(c)
            in_word = True
            i += 1
        if closing or self.pending:
            raise Unparseable
        new_seg(False)
        return [x for x in segs if x.words or x.bodies or x.subs], i

    def parse_sub(self, i, outer):
        if self.depth > MAX_DEPTH:
            raise Unparseable
        self.pending, self.in_sub = outer.pending, True
        return self.parse(i, closing=True)

    def read_word(self, i):
        s, out, q = self.s, [], False
        while i < len(s) and s[i] not in " \t\n;&|()<>":
            if s[i] == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    raise Unparseable
                out.append(s[i + 1:j])
                q, i = True, j + 1
            elif s.startswith("$'", i):
                text, i = ansi_c(s, i + 2)
                out.append(text)
                q = True
            elif s[i] == '"':
                i += 1
                while i < len(s) and s[i] != '"':
                    if s[i] == "\\" and i + 1 < len(s):
                        out.append(s[i + 1] if s[i + 1] in '$`"\\' else s[i:i + 2])
                        i += 2
                        continue
                    out.append(s[i])
                    i += 1
                if i >= len(s):
                    raise Unparseable
                q, i = True, i + 1
            elif s[i] == "\\" and i + 1 < len(s):
                out.append(s[i + 1])
                q, i = True, i + 2
            else:
                out.append(s[i])
                i += 1
        if not out and not q:
            raise Unparseable
        return "".join(out), q, i

    def read_heredocs(self, i):
        s = self.s
        while self.pending:
            delim, strip, quoted, body = self.pending.pop(0)
            lines = []
            while True:
                if i >= len(s):
                    raise Unparseable
                j = s.find("\n", i)
                line = s[i:] if j < 0 else s[i:j]
                head = line.lstrip("\t") if strip else line
                if self.in_sub and head.startswith(delim + ")"):
                    # $(cat <<'EOF' … EOF) — 끝 표시 뒤 `)`는 $(…)를 닫는다
                    i += len(line) - len(head) + len(delim)
                    break
                i = len(s) if j < 0 else j + 1
                if head == delim:
                    break
                lines.append(line)
            body.append(("\n".join(lines), not quoted))
        return i

    def dquote(self, i, word, seg):
        s = self.s
        while i < len(s):
            c = s[i]
            if c == '"':
                return i + 1
            if c == "\\" and i + 1 < len(s):
                word.append(s[i + 1] if s[i + 1] in '$`"\\\n' else s[i:i + 2])
                i += 2
                continue
            if c == "$" and s.startswith("$(", i):
                sub, i = Parser(s, self.depth + 1).parse_sub(i + 2, self)
                seg.subs.append(sub)
                word.append("$()")
                continue
            if c == "`":
                i = self.backtick(i + 1, seg)
                word.append("$()")
                continue
            word.append(c)
            i += 1
        raise Unparseable

    def backtick(self, i, seg):
        s, out = self.s, []
        while i < len(s):
            if s[i] == "\\" and i + 1 < len(s):
                out.append(s[i + 1])
                i += 2
                continue
            if s[i] == "`":
                seg.subs.append(parse_text("".join(out), self.depth + 1))
                return i + 1
            out.append(s[i])
            i += 1
        raise Unparseable


def parse_text(text, depth):
    if depth > MAX_DEPTH:
        raise Unparseable
    return Parser(text, depth).parse()[0]


def match(text, relaxed=False):
    if relaxed:
        text = text + "\n" + re.sub(r"[\"'`();&|]", " ", text)
    for key, label, pats in enabled:
        if any(p.search(text) for p in pats):
            return key, label
    return None


def floor(text):
    return FLOOR if FLOOR_RAW.search(re.sub(r"[\"'`();&|]", " ", text)) else None


def base(w):
    w = w.rsplit("/", 1)[-1]
    return "python" if re.match(r"^python[0-9.]*$", w) else ("node" if w == "nodejs" else w)


def first_command(words):
    k = 0
    while k < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[k]):
        k += 1
    return k


def normalize(words):
    out, k = [], 0
    while k < len(words):
        w = words[k]
        out.append(w)
        k += 1
        if base(w) == "git":
            while k < len(words) and words[k].startswith("-"):
                opt = words[k]
                k += 1
                if opt in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") and k < len(words):
                    k += 1
    # 따옴표 안에 공백이 있는 인자(메시지·검색어)는 한 덩어리 데이터 — 경로 패턴(.env 등)이 그 끝에 맞지 않게 자리표시자로
    return " ".join("Q" if re.search(r"\s", x) else x for x in out)


def code_lines(code):
    return [line for line in code.split("\n") if SHELL_CALL.search(line)]


def check_code(code):
    for line in code_lines(code):
        hit = match(line, relaxed=True) or floor(line)
        if hit:
            return hit
    return None


def shell_args(words, k):
    """셸 이름 뒤 인자에서 (-c 코드 또는 None, 표준입력을 코드로 받는지)."""
    j, stdin_flag = k + 1, False
    while j < len(words):
        a = words[j]
        if a == "--":
            j += 1
            break
        if a.startswith("--"):
            j += 2 if a in SHELL_LONG_ARG else 1
            continue
        if len(a) > 1 and a[0] in "-+":
            flags = a[1:]
            takes = sum(1 for f in flags if f in "oO")
            if a[0] == "-" and "c" in flags:
                code_at = j + 1 + takes
                return (words[code_at] if code_at < len(words) else ""), False
            stdin_flag = stdin_flag or "s" in flags
            j += 1 + takes
            continue
        break
    positional = words[j] if j < len(words) else None
    return None, positional is None or stdin_flag or positional in ("-", "/dev/stdin")


def runtime_args(name, words, k):
    """런타임 이름 뒤 인자에서 (코드 또는 None, 표준입력을 코드로 받는지)."""
    j, code_flags, arg_flags = k + 1, CODE_FLAGS.get(name, ""), ARG_FLAGS.get(name, "")
    while j < len(words):
        a = words[j]
        if a in ("--eval", "--print", "--command"):
            return (words[j + 1] if j + 1 < len(words) else ""), False
        if a == "-":
            return None, True
        if a.startswith("--"):
            j += 1
            continue
        if len(a) > 1 and a[0] == "-":
            flags = a[1:]
            for n, f in enumerate(flags):
                if f in code_flags:
                    rest = flags[n + 1:]
                    return (rest if rest else (words[j + 1] if j + 1 < len(words) else "")), False
                if f in arg_flags:
                    if name == "python" and f == "m":
                        return None, False
                    j += 0 if flags[n + 1:] else 1
                    break
            j += 1
            continue
        return None, False
    return None, True


def ssh_remote(words, k):
    j = k + 1
    while j < len(words) and words[j].startswith("-"):
        a = words[j]
        j += 2 if len(a) == 2 and a[1] in SSH_ARG_FLAGS else 1
    return words[j + 1:]


def receiver(words):
    """이 세그먼트의 표준입력(파이프·heredoc)을 무엇이 코드로 실행하나 — shell · sql · runtime · None."""
    k = first_command(words)
    if k >= len(words):
        return None
    launched = base(words[k]) in LAUNCHERS
    for idx in range(k, len(words)):
        if idx > k and not launched:
            break
        b = base(words[idx])
        if b in SHELLS:
            code, stdin = shell_args(words, idx)
            if code is None and stdin:
                return "shell"
            if code is not None and base(words[k]) in ("xargs", "parallel"):
                return "shell"   # 파이프로 받은 글자가 -c 코드의 인자로 들어간다
        elif b in SQL_CLIENTS:
            return "sql"
        elif RUNTIME.match(b) or b in CODE_FLAGS:
            code, stdin = runtime_args(b, words, idx)
            if code is None and stdin:
                return "runtime"
        elif b == "ssh":
            remote = ssh_remote(words, idx)
            return "shell" if not remote else receiver(remote)
    return None


def floor_words(words):
    for idx, w in enumerate(words):
        if base(w) != "rm":
            continue
        args = words[idx + 1:]
        if "--no-preserve-root" in args:
            return FLOOR
        flags = [a for a in args if a.startswith("-") and a != "--"]
        recursive = any(a == "--recursive" or (not a.startswith("--") and re.search(r"[rR]", a)) for a in flags)
        targets = [a.rstrip("/") or "/" for a in args if not a.startswith("-")]
        if recursive and any(t in FLOOR_TARGETS for t in targets):
            return FLOOR
    return None


def check_inner(words, depth):
    """세그먼트 안에서 다른 코드가 실행되는 자리 — 셸 -c · su -c · eval · ssh · SQL 인자 · 런타임 코드."""
    for idx, w in enumerate(words):
        b = base(w)
        hit = None
        if b in SHELLS:
            code, _ = shell_args(words, idx)
            if code is not None:
                hit = check_shell(code, depth + 1)
        elif b in ("su", "runuser"):
            for j in range(idx + 1, len(words)):
                a = words[j]
                if a.startswith("--command="):
                    hit = check_shell(a.split("=", 1)[1], depth + 1)
                elif a == "--command" or (a.startswith("-") and not a.startswith("--") and "c" in a[1:]):
                    hit = check_shell(words[j + 1] if j + 1 < len(words) else "", depth + 1)
                if hit:
                    break
        elif b == "eval":
            hit = check_shell(" ".join(words[idx + 1:]), depth + 1)
        elif b == "ssh":
            hit = check_shell(" ".join(words[idx + 1:]), depth + 1)
        elif b in SQL_CLIENTS:
            for a in words[idx + 1:]:
                hit = match(a, relaxed=True)
                if hit:
                    break
        elif RUNTIME.match(b) or b in CODE_FLAGS:
            code, _ = runtime_args(b, words, idx)
            if code is not None:
                hit = check_code(code)
        if hit:
            return hit
    return None


def check_segs(segs, whole, depth):
    for seg in segs:
        words = [w for w, _ in seg.words]
        hit = match(normalize(words)) or floor_words(words) or check_inner(words, depth)
        if hit:
            return hit
        for sub in seg.subs:
            hit = check_segs(sub, whole, depth + 1)
            if hit:
                return hit
        receives = receiver(words)
        if seg.procsubs and (receives == "shell" or any(base(w) in SHELLS | {"source", "."} for w in words[:1])):
            # 셸에 스크립트로 넘긴 <(…)는 그 출력이 실행된다 — 원문을 대조한다
            for text in seg.procsubs:
                hit = match(text, relaxed=True) or floor(text)
                if hit:
                    return hit
        for body in seg.bodies:
            for text, expands in body:
                if receives == "shell":
                    hit = check_shell(text, depth + 1)
                elif receives == "sql":
                    hit = match(text, relaxed=True)
                elif receives == "runtime":
                    hit = check_code(text)
                else:
                    hit = check_expansions(text, depth + 1) if expands else None
                if hit:
                    return hit
        if seg.pipe_in and receives:
            # 앞 명령의 출력이 코드로 실행된다 — 따옴표 안 글자까지 원문 전체를 대조하고, 내려받은 글을 셸이 받으면 시스템 위험이다
            if receives == "shell" and re.search(r"(^|[\s/])(curl|wget)\s", whole):
                hit = next(((k, label) for k, label, _ in enabled if k == "BLOCK_SYSTEM"), None)
                if hit:
                    return hit
            hit = check_code(whole) if receives == "runtime" else (match(whole, relaxed=True) or floor(whole))
            if hit:
                return hit
    return None


def check_expansions(text, depth):
    """확장되는 heredoc 본문 — 데이터지만 $(…)·백틱은 실행된다."""
    s, i = text, 0
    while i < len(s):
        if s[i] == "\\":
            i += 2
            continue
        if s.startswith("$(", i):
            p = Parser(s, depth)
            sub, i = p.parse_sub(i + 2, p)
            hit = check_segs(sub, text, depth)
            if hit:
                return hit
            continue
        if s[i] == "`":
            j = s.find("`", i + 1)
            if j < 0:
                raise Unparseable
            hit = check_shell(s[i + 1:j], depth)
            if hit:
                return hit
            i = j + 1
            continue
        i += 1
    return None


def check_shell(text, depth=0):
    if depth > MAX_DEPTH:
        return match(text, relaxed=True) or floor(text)
    try:
        segs = parse_text(text, depth)
        return check_segs(segs, text, depth)
    except (Unparseable, RecursionError):
        return match(text, relaxed=True) or floor(text)


try:
    data = json.load(sys.stdin)
    command = (data.get("tool_input", {}) or {}).get("command")
except Exception:
    command = None
if not isinstance(command, str) or not command.strip():
    print("__UNPARSEABLE__")
    sys.exit(0)
hit = check_shell(command)
print("ok" if hit is None else "block\t%s\t%s" % hit)
PY

verdict=$(BLOCK_FORCE_PUSH="$BLOCK_FORCE_PUSH" BLOCK_BULK_DELETE="$BLOCK_BULK_DELETE" BLOCK_GIT_DISCARD="$BLOCK_GIT_DISCARD" \
  BLOCK_CHECK_BYPASS="$BLOCK_CHECK_BYPASS" BLOCK_DATA_DELETE="$BLOCK_DATA_DELETE" BLOCK_SYSTEM="$BLOCK_SYSTEM" \
  python3 -I -c "$JUDGE" <<< "$input" 2>/dev/null) || verdict="__UNPARSEABLE__"

case "$verdict" in
ok)
  exit 0
  ;;
block$'\t'*)
  rest="${verdict#block$'\t'}"
  const="${rest%%$'\t'*}"; label="${rest#*$'\t'}"
  echo "위험한 명령이 차단되었습니다 — 묶음: ${label} (훅 상수 ${const}). 훅은 구두 승인을 모릅니다 — 변수·eval·별도 스크립트로 감싸 다시 실행하지 말고, 더 안전한 방법을 쓰거나 사용자에게 직접 실행을 요청하세요. 이 묶음을 풀지는 사용자가 정하고 훅 상수를 직접 바꿉니다. 따옴표·heredoc 안의 글자는 검사하지 않으니, 실행할 뜻이 없는 문자열이 bash -c·eval·ssh·셸 파이프에 들어가지 않았는지 보세요. Blocked by .claude/hooks/deny-dangerous-bash.sh." >&2
  exit 2
  ;;
*)
  echo "실행할 명령을 판정할 수 없어 차단합니다 (입력 JSON 또는 command 없음, 또는 python3 없음). 훅 공통 규약: 판정 불가(빈 입력·python3 없음 포함) = 차단. Blocked by .claude/hooks/deny-dangerous-bash.sh." >&2
  exit 2
  ;;
esac
