#!/bin/bash
# Blocks ending the turn with a "done/passed" claim when code was edited but the test command never ran (or failed).
# Registered in .claude/settings.json (Stop). core-workflow.md G3 "실행 없이 통과했을 것이라고 보고 금지"를
# 결정론적으로 강제한다.
#
# TEST_CMD는 harness-map.md의 {{테스트 명령}}과 같은 값이어야 한다 — 훅은 슬롯을 읽지 못하므로 여기 직접 적는다.
# 슬롯을 바꾸면 이 줄도 함께 고칠 것. "(없음)"이나 빈 값이면 아무것도 막지 않는다 (테스트 없는 저장소를 영구히 막지 않기 위해).
TEST_CMD="scripts/dev.sh test"
#
# 판정: 마지막 사용자 메시지 이후에
#   (a) 문서(.md/.txt/.rst)가 아닌 파일을 고쳤고 — Write/Edit/MultiEdit/NotebookEdit 도구뿐 아니라 Bash의 `sed -i`·`tee`·
#       `>`/`>>` 리다이렉션도 편집으로 센다 (2026-09-07 감사: Bash 편집이 보이지 않아 게이트가 무동작이던 사각),
#       heredoc 본문(`<<EOF` 다음 줄부터 구분자 줄까지)은 명령이 아니라 데이터라 보지 않는다 — 커밋 메시지 서명의 `<…@…>`가
#       리다이렉션으로 오판되던 사각(2026-10-23 실세션). 따옴표 안·주석의 `>`도 같은 이유로 보지 않는다(2026-10-26 실세션),
#   (b) 그 **마지막 편집 이후에** TEST_CMD를 — 한 명령 안에서도 편집보다 뒤에 있어야 한다 — 명령으로 실행한 기록이 없거나(`cat scripts/dev.sh`처럼 문자열로 언급한 것은 실행이
#       아니다. TEST_CMD의 모든 단어가 그대로 나와야 하고, 뒤에 인자가 더 붙은 `… test --tests X`나 다른 동사는 전체 테스트가
#       아니라 실행으로 치지 않는다), 실행했지만 그 tool_result가 실패(is_error 또는 러너 요약 줄 "실패 있음·FAIL·N failed")였고,
#   (c) 마지막 어시스턴트 텍스트에 완료 단정("완료·통과·끝났·마쳤·성공·정상 동작·구현했·적용했·반영했·수정했·done·passed·fixed·
#       complete·implemented·works")이 있으면 exit 2 — 모델이 이어서 테스트를 돌리거나 문구를 고친다. 문서만 고친 턴에는 발화하지 않는다.
# 완료 단정에서 제외하는 것: "완료 조건·기준·선언·보고"처럼 규칙을 인용하는 명사구, "미완료", "통과하지/못", 영어는 단어 경계
# (abandoned·undone은 잡지 않는다). 오탐이 나도 stop_hook_active로 한 번만 되돌리므로 피해는 한 턴이다.
#
# 훅 공통 규약의 명시적 예외: Stop 훅은 판정 불가(transcript 없음·형식 변경)면 **통과**시킨다 — 대화가 끝나지 못하는 것이
# 미검증 완료 선언보다 큰 피해다. stop_hook_active=true(이 훅이 이미 한 번 되돌린 뒤)에도 통과시켜 무한 루프를 막는다.
# transcript 형식은 Claude Code 내부 형식이라 버전마다 바뀔 수 있다 — 바뀌면 판정 불가로 떨어져 통과한다(fail-open이 이 훅의 설계).
# Hook input: JSON with "transcript_path", "stop_hook_active" on stdin.

case "$TEST_CMD" in ''|'(없음)') exit 0 ;; esac

input=$(cat)
verdict=$(TEST_CMD="$TEST_CMD" python3 -c '
import json, os, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("SKIP"); sys.exit(0)
if data.get("stop_hook_active"):
    print("SKIP"); sys.exit(0)
path = data.get("transcript_path") or ""
if not path or not os.path.isfile(path):
    print("SKIP"); sys.exit(0)
test_cmd = os.environ["TEST_CMD"]
test_words = test_cmd.split()
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
# Bash 편집 검출 — 리다이렉션 대상, tee 대상, sed -i 의 경로 토큰. /dev/null·&1·문서 확장자는 편집이 아니다.
REDIRECT = re.compile(r"(?<![<>&0-9])>{1,2}\s*[\"\x27]?([^\s\"\x27&|;<>]+)")
TEE = re.compile(r"\btee\s+(?:-[a-zA-Z]+\s+)*[\"\x27]?([^\s\"\x27&|;<>]+)")
SED_I = re.compile(r"\bsed\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*i")
PATH_TOKEN = re.compile(r"[\w./-]+\.[A-Za-z0-9]+")
# 실패 판정은 좁게 — 테스트 러너의 요약 줄만 본다. "0 failed"·"error" 같은 일반어는 통과 출력에도 흔해 오탐이 났다(2026-09-07 실세션).
FAILED = re.compile(
    r"실패 있음|실패 [1-9]|오류 [1-9]|\bFAIL(ED|URE)?\b|BUILD FAILED|Tests? failed"
    r"|[1-9][0-9]* (failed|failures?|errors?)\b|\bexit code [1-9]"
)

def is_doc(p):
    p = p.lower()
    return p.endswith(DOC_EXT)

# 둘 다 명령 안에서의 마지막 위치를 돌려준다(없으면 -1) — 한 명령 안의 편집과 테스트 실행은 순서로 판정한다.
def last_code_edit(cmd, mask):
    at = -1
    for m in REDIRECT.finditer(cmd):
        t = m.group(1)
        if mask[m.start()] or t.startswith(("/dev/", "&")) or is_doc(t):
            continue
        at = max(at, m.start())
    for m in TEE.finditer(cmd):
        if not mask[m.start()] and not is_doc(m.group(1)) and not m.group(1).startswith("/dev/"):
            at = max(at, m.start())
    for m in SED_I.finditer(cmd):
        if not mask[m.start()] and any(not is_doc(t) for t in PATH_TOKEN.findall(cmd)):
            at = max(at, m.start())
    return at

def last_test_run(cmd, mask):
    at = -1
    for m in TEST_RUN.finditer(cmd):
        if not mask[m.end(1)]:
            at = m.end(1)
    return at

turns = []
for line in open(path, encoding="utf-8", errors="replace"):
    try:
        turns.append(json.loads(line))
    except Exception:
        continue

def blocks(t):
    m = t.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return [{"type": "text", "text": c}]
    return c if isinstance(c, list) else []

def result_text(b):
    c = b.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""

# 마지막 사람 메시지(텍스트가 있는 user 턴) 찾기 — tool_result만 있는 user 턴은 경계가 아니다
last_user = -1
for i, t in enumerate(turns):
    if t.get("type") == "user" and any(b.get("type") == "text" for b in blocks(t)):
        last_user = i
if last_user < 0:
    print("SKIP"); sys.exit(0)

code_edit = False
test_ran = False          # 마지막 코드 편집 **이후**의 실행만 참
test_failed = False
pending_test_ids = set()  # 실행한 TEST_CMD tool_use id — 그 tool_result를 대조한다
last_text = ""
for t in turns[last_user + 1:]:
    kind = t.get("type")
    if kind == "assistant":
        for b in blocks(t):
            if b.get("type") == "tool_use":
                name = b.get("name", ""); inp = b.get("input") or {}
                edit_at = run_at = -1
                if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                    p = (inp.get("file_path") or inp.get("notebook_path") or "")
                    edit_at = 0 if p and not is_doc(p) else -1
                elif name == "Bash":
                    cmd = strip_heredocs(inp.get("command") or "")
                    mask = data_mask(cmd)
                    edit_at = last_code_edit(cmd, mask)
                    run_at = last_test_run(cmd, mask)
                if edit_at >= 0:
                    code_edit = True
                    test_ran = False; test_failed = False; pending_test_ids.clear()
                if run_at > edit_at:
                    test_ran = True; test_failed = False
                    pending_test_ids.add(b.get("id"))
            elif b.get("type") == "text" and b.get("text", "").strip():
                last_text = b["text"]
    elif kind == "user":
        for b in blocks(t):
            if b.get("type") == "tool_result" and b.get("tool_use_id") in pending_test_ids:
                if b.get("is_error") or FAILED.search(result_text(b)):
                    test_failed = True

if code_edit and CLAIM.search(last_text):
    if not test_ran:
        print("BLOCK_NOT_RUN")
    elif test_failed:
        print("BLOCK_FAILED")
    else:
        print("OK")
else:
    print("OK")
' <<< "$input")

case "$verdict" in
  BLOCK_NOT_RUN)
    echo "[하네스 · G3] 이 턴에 코드 파일을 고쳤는데(도구 편집 또는 Bash의 sed -i·리다이렉션·tee) 그 뒤 \`$TEST_CMD\`를 실행한 기록이 없는 채로 완료·통과를 선언했습니다. 지금 \`$TEST_CMD\`를 실제로 돌리고 결과를 보고하세요. 돌릴 수 없는 환경이면 완료 선언 대신 \"검증하지 못한 것\"으로 남기세요 (core-gates.md §3). Blocked by .claude/hooks/deny-unverified-completion.sh." >&2
    exit 2 ;;
  BLOCK_FAILED)
    echo "[하네스 · G3] \`$TEST_CMD\`를 돌렸지만 결과가 실패였는데 완료·통과를 선언했습니다. 실패 원인을 고치고 다시 돌리거나, 완료 선언 대신 실패 내용을 그대로 보고하세요 (preflight 스킬 사후 모드 1단계). Blocked by .claude/hooks/deny-unverified-completion.sh." >&2
    exit 2 ;;
esac
exit 0
