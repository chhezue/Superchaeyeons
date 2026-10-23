#!/usr/bin/env bash
# Gemini 글 다듬기 — 사람에게 남는 글(문서·커밋·PR·이슈)을 Gemini가 다듬고, 보존 목록을 기계로 대조해 통과한 것만 넘긴다.
# 스펙: docs/specs/cross-cutting/gemini-text-polish.md (종료 코드·출력·상수 표가 계약이다)
#
# 사용:
#   scripts/polish-with-gemini.sh enabled                 # 켜짐 0 · 꺼짐 2
#   scripts/polish-with-gemini.sh docs <파일…>            # 기준판과 비교해 바뀐 문단만 다듬어 반영하고 차이를 출력 (새 문서는 전체)
#   scripts/polish-with-gemini.sh done <파일…>            # 검수를 마친 지금 판을 기준판으로 기록 — 이후 그 판의 문단은 다시 다듬지 않는다
#   scripts/polish-with-gemini.sh message                 # 표준 입력 {"kind","fields"} → 표준 출력 {"fields"} · 성공 0 · 실패 1(원인 한 줄) · 꺼짐 2
#
# docs·done은 항상 exit 0이다(사용법 오류만 2). 꺼져 있으면 출력이 없고, 실패하면 `다듬기 건너뜀(<원인>)` 한 줄을 내고 파일을 바꾸지 않는다.
# 기준판은 STATE_DIR/base/<경로>에 두고, 없으면 마지막 커밋의 판, 그것도 없으면 새 문서로 보고 전체를 보낸다.
# 기준 글은 실행할 때마다 ROOT의 doc-writing.md 3절 · core-reporting.md · doc-style-patterns.txt를 읽는다 — 기준을 따로 두지 않는다.
#
# 키는 파일에 두지 않는다. KEY_ENV_NAME 환경 변수 → (macOS면) 키체인 KEYCHAIN_SERVICE 순으로 찾고, 출력·경고·상태 폴더 어디에도 쓰지 않는다.
# 모델은 환경 변수 GEMINI_MODEL, 없으면 DEFAULT_MODEL. 그 모델이 503(사용량 몰림)이면 FALLBACK_MODEL(환경 변수 GEMINI_FALLBACK_MODEL로 바꿈,
# 빈 값이면 안 함)로 한 번만 더 시도한다. 한도 초과(429)·시간 초과는 다시 시도하지 않는다 — 기다림이 두 배가 되기 때문이다.
#
# 아래 상수는 훅 상수처럼 본문에 직접 적는다. 테스트는 scripts/hook-cases.txt의 상수 바꾸기로 값을 바꾼다.
#   POLISH_ENABLED — harness-map.md "Gemini 다듬기" 플래그의 기본값. 배달본은 꺼짐(0)이다 — 원본 저장소의 켜짐이 복사본에 실려
#                    init-harness 없이 복사한 프로젝트의 글이 밖으로 나가지 않게. 켜는 값은 프로젝트 루트 harness.conf의
#                    `POLISH_ENABLED=1`에 둔다(복사되지 않는 자리 — 플러그인 배달에서는 .claude/harness.conf로 옮긴다).
#   DOC_ROOT       — {{문서 루트}}의 짝
set -u
POLISH_ENABLED="0"
DOC_ROOT="docs"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_DIR=".claude/polish"
GEMINI_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
DEFAULT_MODEL="gemini-3.5-flash"
FALLBACK_MODEL="gemini-3.5-flash-lite"
TIMEOUT_DOCS="60"
TIMEOUT_MESSAGE="30"
KEY_ENV_NAME="GEMINI_API_KEY"
KEYCHAIN_SERVICE="gemini-api-key"

if [ -f "$ROOT/harness.conf" ]; then
	conf_value="$(sed -n 's/^POLISH_ENABLED=//p' "$ROOT/harness.conf" | tail -n 1 | tr -d ' \r')"
	[ -n "$conf_value" ] && POLISH_ENABLED="$conf_value"
fi

cmd="${1:-}"
case "$cmd" in
enabled | docs | done | message) ;;
*) echo "사용법: $0 enabled | docs <파일…> | done <파일…> | message" >&2; exit 2 ;;
esac
if [ "$POLISH_ENABLED" != "1" ]; then
	case "$cmd" in enabled | message) exit 2 ;; *) exit 0 ;; esac
fi
[ "$cmd" = "enabled" ] && exit 0
if ! command -v python3 >/dev/null 2>&1; then
	[ "$cmd" = "message" ] && { echo "python3 없음"; exit 1; }
	echo "다듬기 건너뜀(python3 없음)"; exit 0
fi

key=""
if [ "$cmd" = "docs" ] || [ "$cmd" = "message" ]; then
	key="${!KEY_ENV_NAME:-}"
	if [ -z "$key" ] && command -v security >/dev/null 2>&1; then
		key="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
	fi
	# 끝에 붙은 줄바꿈은 요청 헤더 검사에서 예외가 되고, 예외 메시지에 키가 그대로 찍힌다
	key="$(printf '%s' "$key" | tr -d '\r\n')"
fi

# $(cat <<…)로 읽으면 bash 3.2가 본문의 백틱을 명령 치환으로 읽어 깨진다 — read로 읽는다
read -r -d '' PY <<'PY'
import collections, difflib, json, os, re, shutil, signal, socket, subprocess, sys, urllib.error, urllib.request

E = os.environ
ROOT = os.path.realpath(E["P_ROOT"])
DOC_ROOT = E["P_DOC_ROOT"].strip("/")
STATE = os.path.join(ROOT, E["P_STATE_DIR"])
BASE = os.path.join(STATE, "base")
KEY = E.get("P_KEY", "")
MODEL = E.get("GEMINI_MODEL") or E["P_DEFAULT_MODEL"]
FALLBACK = E.get("GEMINI_FALLBACK_MODEL", E["P_FALLBACK_MODEL"])
DIFF_LIMIT = 9000
cmd, args = sys.argv[1], sys.argv[2:]


class Skip(Exception):
    """다듬기를 건너뛸 원인. 원인 종류만 담는다 — 서버 메시지는 키를 되풀이할 수 있어 옮기지 않는다."""

    def __init__(self, reason, code=None):
        super().__init__(reason)
        self.code = code


# ---- 대상 판정 ----------------------------------------------------------------
def rel_of(path):
    real = os.path.realpath(path)
    rel = os.path.relpath(real, ROOT)
    return None if rel == ".." or rel.startswith("../") else rel


def is_target(rel):
    if rel is None or not rel.endswith(".md"):
        return False
    if rel == "README.md" or rel.startswith(".github/"):
        return True
    return rel.startswith(DOC_ROOT + "/") and not rel.startswith(DOC_ROOT + "/templates/")


# ---- 문단 ----------------------------------------------------------------------
FENCE = re.compile(r"\s*(`{3,}|~{3,})")


def read_doc(path):
    """(LF로 맞춘 글, CRLF였는지). 쓸 때 원래 줄바꿈으로 되돌린다."""
    raw = open(path, encoding="utf-8", newline="").read()
    return raw.replace("\r\n", "\n"), "\r\n" in raw


def write_doc(path, text, crlf):
    open(path, "w", encoding="utf-8", newline="").write(text.replace("\n", "\r\n") if crlf else text)


def blocks_of(text):
    """빈 줄로 나눈 문단 목록 [(종류, 시작 줄, 끝 줄)]. 코드 블록·머리 메타데이터는 한 덩어리로 두고 보내지 않는다."""
    lines = text.split("\n")
    out, i, n = [], 0, len(lines)
    if n and lines[0].strip() == "---":
        j = next((k for k in range(1, n) if lines[k].strip() == "---"), None)
        if j is not None:
            out.append(("meta", 0, j + 1)); i = j + 1
    while i < n:
        if not lines[i].strip():
            i += 1; continue
        start = i
        fence = FENCE.match(lines[i])
        if fence:
            # 닫는 펜스는 같은 문자로 여는 펜스 이상 길이여야 한다 — 백틱 4개 펜스 안의 ``` 는 코드의 일부다
            mark = fence.group(1)
            close = re.compile(r"\s*" + re.escape(mark[0]) + "{" + str(len(mark)) + r",}\s*$")
            i += 1
            while i < n and not close.match(lines[i]):
                i += 1
            out.append(("code", start, min(i + 1, n))); i += 1; continue
        while i < n and lines[i].strip() and not FENCE.match(lines[i]):
            i += 1
        kind = "heading" if all(l.lstrip().startswith("#") for l in lines[start:i]) else "text"
        out.append((kind, start, i))
    return lines, out


def block_text(lines, b):
    return "\n".join(lines[b[1]:b[2]])


# ---- 보존 목록 대조 --------------------------------------------------------------
PATTERNS = {
    "code": r"`[^`\n]+`",
    "slot": r"\{\{[^}\n]+\}\}",
    "link": r"\]\([^)\s]+\)|https?://[^\s)>\]]+",
    "checkbox": r"\[[ xX]\]",
    "number": r"\d+(?:[.,]\d+)*",
    "path": r"(?<![\w/])[\w.-]+(?:/[\w.-]+)+|\b[\w-]+\.(?:md|sh|txt|json|py|conf|cfg|ya?ml|toml|js|ts|java|kt|xml)\b",
    "issue": r"(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#\d+",
}


def preserved(orig, new, message=False):
    if not new.strip():
        return False
    for pat in PATTERNS.values():
        if collections.Counter(re.findall(pat, orig)) != collections.Counter(re.findall(pat, new)):
            return False
    ol, nl = orig.split("\n"), new.split("\n")
    # 체크 상태는 순서까지 같아야 한다 — 개수만 같으면 [x]와 [ ]가 자리를 바꿔도 통과한다
    if re.findall(PATTERNS["checkbox"], orig) != re.findall(PATTERNS["checkbox"], new):
        return False
    # 제목·`> 키: 값` 메타데이터 줄은 그대로, 빈 줄(문단 경계)·펜스 줄은 개수가 같아야 한다
    fixed = lambda ls: [l.strip() for l in ls if l.lstrip().startswith("#") or re.match(r"\s*>\s*[^:\s]+:", l)]
    if fixed(ol) != fixed(nl):
        return False
    count = lambda ls, f: sum(1 for l in ls if f(l))
    if count(ol, lambda l: not l.strip()) != count(nl, lambda l: not l.strip()) or \
            count(ol, FENCE.match) != count(nl, FENCE.match):
        return False
    if [l.count("|") for l in ol if l.lstrip().startswith("|")] != [l.count("|") for l in nl if l.lstrip().startswith("|")]:
        return False
    if message:
        head = re.match(r"[A-Za-z]+(?:\([^)]*\))?!?:\s", ol[0])
        if head and not nl[0].startswith(head.group(0)):
            return False
        trailer = lambda ls: [l.strip() for l in ls if re.match(r"\s*([\w-]+-By:|Signed-off-by:|🤖)", l)]
        if trailer(ol) != trailer(nl):
            return False
    return True


# ---- Gemini 호출 ----------------------------------------------------------------
def section(path, heading=None):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return ""
    if heading:
        m = re.search(r"^## " + re.escape(heading) + r".*?(?=^## |\Z)", text, re.M | re.S)
        if m:
            return m.group(0)
    return text


def guide():
    parts = [
        section(os.path.join(ROOT, ".claude/rules/doc-writing.md"), "3."),
        section(os.path.join(ROOT, ".claude/rules/core-reporting.md")),
        section(os.path.join(ROOT, "scripts/doc-style-patterns.txt")),
    ]
    return "\n\n".join(p for p in parts if p.strip())


INSTRUCTION = """너는 Claude가 쓴 한국어 글을 사람이 읽기 쉽게 다듬는 교정자다.
- 뜻과 사실은 그대로 두고 문장만 고친다. 내용을 더하거나 빼지 않는다. 고칠 것이 없으면 원문을 그대로 돌려준다
- 아래 '기준'의 문장 규칙과 보고 문체를 따른다. 내부 용어는 풀어 쓰고, 번역투와 딱딱한 명사 나열을 줄인다
- 바꾸면 안 되는 것: 경로와 파일 이름, 숫자와 단위, {{슬롯}} 표기, 백틱 안의 코드 표기, 링크 주소, 섹션 제목(#으로 시작하는 줄), 표의 열 구성,
  커밋 머리말(예: `Docs:`), 이슈 연결(예: Closes #12), Co-Authored-By 같은 끝 줄
- '앞 문단'·'뒤 문단'은 말투를 맞추는 참고일 뿐이다. 고쳐서 돌려주지 않는다
- 응답은 {"items": [{"id": 받은 id, "text": 다듬은 글}]} JSON 하나다. 받은 id를 하나도 빠뜨리지 않는다"""


def call(items, timeout, model=MODEL):
    if not KEY:
        raise Skip("키 없음")
    body = {
        "systemInstruction": {"parts": [{"text": INSTRUCTION + "\n\n## 기준\n\n" + guide()}]},
        "contents": [{"role": "user", "parts": [{"text": json.dumps({"items": items}, ensure_ascii=False)}]}],
        "generationConfig": {
            "temperature": 0.3,
            "responseMimeType": "application/json",
            "responseSchema": {
                "type": "OBJECT",
                "properties": {"items": {"type": "ARRAY", "items": {
                    "type": "OBJECT",
                    "properties": {"id": {"type": "STRING"}, "text": {"type": "STRING"}},
                    "required": ["id", "text"]}}},
                "required": ["items"]},
        },
    }
    req = urllib.request.Request(E["P_ENDPOINT"].replace("{model}", model), data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "x-goog-api-key": KEY})
    # urlopen의 timeout은 연결·읽기 한 번마다라, 전체 시간 상한은 알람으로 건다
    def expire(*_):
        raise TimeoutError()
    signal.signal(signal.SIGALRM, expire)
    signal.alarm(max(1, int(timeout)))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        raise Skip("한도 초과" if e.code == 429 else f"API 오류 {e.code}", e.code)
    except (socket.timeout, TimeoutError):
        raise Skip("시간 초과")
    except urllib.error.URLError as e:
        raise Skip("시간 초과" if isinstance(e.reason, (socket.timeout, TimeoutError)) else "네트워크 오류")
    except OSError:
        raise Skip("네트워크 오류")
    except Exception:
        # 예외 메시지는 요청 헤더(키)를 담을 수 있어 옮기지 않는다
        raise Skip("요청 실패")
    finally:
        signal.alarm(0)
    try:
        outer = json.loads(raw)
    except ValueError:
        raise Skip("응답 형식 깨짐")
    if isinstance(outer, dict) and "error" in outer:
        err = outer.get("error") or {}
        raise Skip("한도 초과" if err.get("code") == 429 or err.get("status") == "RESOURCE_EXHAUSTED" else f"API 오류 {err.get('code', '')}".strip(), err.get("code"))
    try:
        inner = json.loads(outer["candidates"][0]["content"]["parts"][0]["text"])
        return {str(it["id"]): str(it["text"]) for it in inner["items"]}
    except (KeyError, IndexError, TypeError, ValueError):
        raise Skip("응답 형식 깨짐")


def polish(items, timeout):
    """기본 모델이 503(사용량 몰림)이면 대체 모델로 한 번만 더 시도한다."""
    try:
        return call(items, timeout)
    except Skip as s:
        if s.code == 503 and FALLBACK and FALLBACK != MODEL:
            return call(items, timeout, FALLBACK)
        raise


# ---- 명령 ----------------------------------------------------------------------
def base_text(rel):
    p = os.path.join(BASE, rel)
    if os.path.isfile(p):
        return read_doc(p)[0]
    r = subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + rel], capture_output=True)
    return r.stdout.decode("utf-8", "replace").replace("\r\n", "\n") if r.returncode == 0 else None


def settled(block):
    """승인 뒤 바뀌는 체크 상태와 `> 키: 값` 메타데이터 줄을 지운 판 — 이것만 바뀐 문단은 다시 보내지 않는다."""
    block = re.sub(PATTERNS["checkbox"], "[ ]", block)
    return "\n".join("> :" if re.match(r"\s*>\s*[^:\s]+:", l) else l for l in block.split("\n"))


def docs():
    targets, seen = [], set()
    for a in args:
        rel = rel_of(a)
        if is_target(rel) and os.path.isfile(a):
            if rel not in seen:
                seen.add(rel); targets.append((a, rel))
        else:
            print(f"건너뜀(대상 아님): {a}")
    if not targets:
        return
    items, plan = [], {}
    for path, rel in targets:
        text = read_doc(path)[0]
        lines, blocks = blocks_of(text)
        cur = [block_text(lines, b) for b in blocks]
        base = base_text(rel)
        if base is None:
            changed = set(range(len(blocks)))
        else:
            blines, bblocks = blocks_of(base)
            sm = difflib.SequenceMatcher(a=[settled(block_text(blines, b)) for b in bblocks], b=[settled(c) for c in cur], autojunk=False)
            same = {j for tag, _, _, j1, j2 in sm.get_opcodes() if tag == "equal" for j in range(j1, j2)}
            changed = set(range(len(blocks))) - same
        for i in sorted(changed):
            if blocks[i][0] != "text":
                continue
            ctx = lambda k: cur[k] if 0 <= k < len(blocks) and blocks[k][0] != "code" else ""
            bid = f"{rel}:{i}"
            items.append({"id": bid, "text": cur[i], "앞 문단": ctx(i - 1), "뒤 문단": ctx(i + 1)})
            plan[bid] = (path, i)
    if not items:
        print("바뀐 문단 없음 — 보낼 것이 없다")
        return
    try:
        got = polish(items, float(E["P_TIMEOUT_DOCS"]))
    except Skip as s:
        print(f"다듬기 건너뜀({s})")
        return
    accepted, kept = collections.defaultdict(dict), []
    for it in items:
        new = got.get(it["id"])
        if new is None or new == it["text"]:
            continue
        if preserved(it["text"], new):
            path, i = plan[it["id"]]
            accepted[path][i] = new
        else:
            kept.append(it["id"])
    diffs = []
    for path, rel in targets:
        if path not in accepted:
            continue
        text, crlf = read_doc(path)
        lines, blocks = blocks_of(text)
        new_lines = list(lines)
        for i in sorted(accepted[path], reverse=True):
            _, s, e = blocks[i]
            new_lines[s:e] = accepted[path][i].split("\n")
        new_text = "\n".join(new_lines)
        write_doc(path, new_text, crlf)
        diffs.append("".join(difflib.unified_diff(text.splitlines(True), new_text.splitlines(True), "a/" + rel, "b/" + rel)))
        print(f"다듬음: {rel} {len(accepted[path])}문단")
    if kept:
        print("보존 목록 대조에 걸려 원문 유지: " + ", ".join(kept))
    if not diffs:
        print("바뀐 문장 없음")
        return
    diff = "\n".join(diffs)
    if len(diff) > DIFF_LIMIT:
        os.makedirs(STATE, exist_ok=True)
        p = os.path.join(STATE, "review.diff")
        open(p, "w", encoding="utf-8").write(diff)
        print(f"차이가 길어 파일에 두었다: {p}")
    else:
        print(diff)
    print("검수: 원문과 대조해 틀린 곳만 최소로 고친 뒤 `scripts/polish-with-gemini.sh done <파일…>`로 확정한다")


def done():
    n = 0
    for a in args:
        rel = rel_of(a)
        if not (is_target(rel) and os.path.isfile(a)):
            print(f"건너뜀(대상 아님): {a}")
            continue
        dst = os.path.join(BASE, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(a, dst)
        n += 1
    print(f"기준판 기록: {n}개")


def message():
    try:
        data = json.load(sys.stdin)
        fields = {str(k): str(v) for k, v in data["fields"].items()}
    except (ValueError, KeyError, AttributeError, TypeError):
        print("입력 형식 깨짐"); sys.exit(1)
    try:
        got = polish([{"id": k, "text": v} for k, v in fields.items()], float(E["P_TIMEOUT_MESSAGE"]))
    except Skip as s:
        print(s); sys.exit(1)
    out = {k: (got[k] if k in got and preserved(v, got[k], message=True) else v) for k, v in fields.items()}
    print(json.dumps({"fields": out}, ensure_ascii=False))


# 뜻밖의 예외는 원인 종류만 남긴다 — traceback이 표준 오류로 나가면 예외 값에 든 키·문서가 대화 기록에 남는다
try:
    {"docs": docs, "done": done, "message": message}[cmd]()
except SystemExit:
    raise
except BaseException:
    print("스크립트 오류" if cmd == "message" else "다듬기 건너뜀(스크립트 오류)")
    sys.exit(1 if cmd == "message" else 0)
PY

P_ROOT="$ROOT" P_DOC_ROOT="$DOC_ROOT" P_STATE_DIR="$STATE_DIR" P_KEY="$key" P_DEFAULT_MODEL="$DEFAULT_MODEL" P_FALLBACK_MODEL="$FALLBACK_MODEL" \
	P_ENDPOINT="$GEMINI_ENDPOINT" P_TIMEOUT_DOCS="$TIMEOUT_DOCS" P_TIMEOUT_MESSAGE="$TIMEOUT_MESSAGE" \
	python3 -c "$PY" "$@"
rc=$?
case "$cmd" in
message) exit "$rc" ;;
*) exit 0 ;;
esac
