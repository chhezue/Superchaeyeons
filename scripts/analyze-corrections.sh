#!/usr/bin/env bash
# 회고 루프의 "분석" 단계 — 마지막 분석 뒤 바뀐 이 프로젝트의 대화 기록을 세션마다 요약하고, 정정 대기열·장부와 묶어
# `claude -p`로 하네스 개선 후보를 뽑는다. 근거 없는 후보는 버리고, 분석이 성공했을 때만 "마지막 분석" 시각을 옮긴다.
# 스펙: docs/specs/cross-cutting/harness-retro-loop.md · 분석 지시문: .claude/skills/improve-harness/references/analyze.md
#
# 사용:
#   scripts/analyze-corrections.sh [run] [--model M] [--budget USD]   # 정기 실행 — 마지막 분석 뒤 바뀐 세션 전부
#   scripts/analyze-corrections.sh run --model M --session ID [--session ID]...
#                                 # 시험 실행 — 고른 세션만. 결과는 trials/에 쓰고 마지막 분석 시각은 건드리지 않는다
#                                 # (모델 비교처럼 같은 입력을 여러 번 돌릴 때)
#   scripts/analyze-corrections.sh digest <대화 기록.jsonl>          # 요약 하나만 출력 (추출 실패면 exit 1)
#
# exit 0 = 성공 또는 새 세션 없음(모델을 부르지 않음) · exit 1 = 분석 실패·비용 상한·추출 실패 · exit 2 = 사용법 오류
#
# 상태 폴더(STORE, .gitignore 대상 — 대화 원문 일부가 들어간다):
#   queue.tsv       정정 대기열 — auto-correction-queue.sh 훅이 쓴다. 정기 분석이 성공하면 분석한 줄을 지운다
#   digests/        세션별 요약 <세션 ID>.json
#   input.md        마지막으로 모델에 넣은 입력 전문
#   candidates.md   후보 파일 — 검토할 후보는 `### `로 시작하는 줄 하나씩. 덧붙이기만 하고 다시 쓰지 않는다
#   trials/         시험 실행의 후보
#   runs.tsv        실행 기록 — 시각 · 종류 · 모델 · 세션 수 · 입력 바이트 · 입력 토큰 · 출력 토큰 · 비용(USD) · 결과 · 후보 · 버림 · 추출 실패
#   last-analysis   마지막 정기 분석 시각 — 파일 수정 시각을 분석 시작 시각에 맞춘다. 알림 훅과 다음 실행이 이것보다 늦게 바뀐 기록을 센다
#
# 분석 세션은 프로젝트 훅을 돌리지 않고(--setting-sources user) 대화 기록도 남기지 않으며(--no-session-persistence)
# 읽기 도구만 쓴다(--tools). 파일 쓰기는 이 스크립트가 결과를 받아서 한다 — 규칙·스킬은 사람 승인 없이 바뀌지 않는다.
#
# 아래 상수는 훅 상수처럼 본문에 직접 적는다. MODEL·BUDGET은 첫 실행 결과로 정한다(스펙 "분석 모델"·"비용 상한"):
#   MODEL  — 기준 사례로 sonnet·opus를 한 번씩 돌려, 둘 다 그 증상을 후보로 내면 sonnet, sonnet만 놓치면 opus — 2026-10-28 첫 실행: sonnet만 기준 증상을 잡아 sonnet
#   BUDGET — 첫 실행 2달러, 그 뒤 runs.tsv의 실제 비용의 2배. 응답 하나가 끝난 뒤 확인해 조금 넘을 수 있다 — 2026-10-28 첫 실행 실측 $0.43(세션 1개). 첫 정기 분석이 쌓인 세션을 한꺼번에 보므로 2배($0.86)를 올려 1달러
# LEDGER는 {{문서 루트}}/audits/harness-retro.md다 — 문서 루트가 다르면 이 줄을 고친다.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="$ROOT/.claude/corrections"
TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$ROOT" | sed 's/[^A-Za-z0-9]/-/g')"
LEDGER="$ROOT/docs/audits/harness-retro.md"
CLAUDE_BIN="claude"
MODEL="sonnet"
BUDGET="1"

command -v python3 >/dev/null 2>&1 || { echo "python3가 필요합니다" >&2; exit 2; }

export ROOT STORE TRANSCRIPTS LEDGER CLAUDE_BIN MODEL BUDGET
python3 - "$@" <<'PY'
import datetime, json, os, re, subprocess, sys, time

ENV = os.environ
ROOT, STORE, TRANSCRIPTS, LEDGER = ENV["ROOT"], ENV["STORE"], ENV["TRANSCRIPTS"], ENV["LEDGER"]
PROMPT = os.path.join(ROOT, ".claude/skills/improve-harness/references/analyze.md")
CAP = 500  # 메시지마다 바이트 상한 — 긴 붙여넣기 하나가 입력을 다 먹지 않게 (스펙 실험: 상한이 없으면 세션 10개에 166KB)

# ---- 요약 추출 ---------------------------------------------------------------------
# 대화 기록 형식은 Claude Code 내부 형식이라 버전마다 바뀔 수 있다. 바뀌어서 사용자 메시지를 하나도 못 뽑으면
# 조용히 빈 요약으로 넘어가지 않고 extract_failed로 알린다.
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
# 사람이 쓴 말이 아니라 명령·도구가 사용자 줄에 남긴 감싸개
WRAPPER = re.compile(r"^\s*<(command-name|command-message|command-args|local-command-stdout|local-command-stderr|"
                     r"local-command-caveat|bash-input|bash-stdout|bash-stderr|task-notification)>")
HOOK_ERROR = re.compile(r"^(Error: )?\w+(:\S+)? hook error")
REJECTED = "The user doesn't want to proceed"

def tool_result_text(part):
    c = part.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""

def digest(path):
    msgs, bad, lines = [], 0, 0
    sig = {"rejected": 0, "hook_blocked": 0, "stop_hook": 0, "interrupted": 0}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            if not raw.strip():
                continue
            lines += 1
            try:
                d = json.loads(raw)
            except ValueError:
                bad += 1
                continue
            if not isinstance(d, dict):
                bad += 1
                continue
            if d.get("type") != "user":
                continue
            content = (d.get("message") or {}).get("content")
            parts = [content] if isinstance(content, str) else content if isinstance(content, list) else []
            texts, rejected, blocked = [], False, False
            for p in parts:
                if isinstance(p, str):
                    texts.append(p)
                elif isinstance(p, dict) and p.get("type") == "text":
                    texts.append(p.get("text") or "")
                elif isinstance(p, dict) and p.get("type") == "tool_result":
                    t = tool_result_text(p)
                    rejected = rejected or t.startswith(REJECTED)
                    blocked = blocked or bool(HOOK_ERROR.match(t))
            pd = d.get("permissionDecision") or {}
            blocked = blocked or (pd.get("source") == "hook" and pd.get("decision") == "reject")
            sig["rejected"] += rejected or d.get("toolUseResult") == "User rejected tool use"
            sig["hook_blocked"] += blocked
            for t in texts:
                head = t.lstrip()
                # 신호는 메타 줄에서도 센다 — Stop 훅 되돌림은 메타 줄로 남는다
                if head.startswith("Stop hook feedback"):
                    sig["stop_hook"] += 1
                    continue
                if head.startswith("[Request interrupted"):
                    sig["interrupted"] += 1
                    continue
                if d.get("isMeta") or d.get("isCompactSummary") or WRAPPER.match(t):
                    continue
                t = REMINDER.sub("", t).strip()
                if not t:
                    continue
                b = t.encode("utf-8")
                if len(b) > CAP:
                    t = b[:CAP].decode("utf-8", "ignore") + " …"
                msgs.append({"n": len(msgs) + 1, "text": t})
    sid = os.path.basename(path)[:-len(".jsonl")] if path.endswith(".jsonl") else os.path.basename(path)
    return {"session": sid, "date": datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat(),
            "message_count": len(msgs), "messages": msgs, "signals": sig, "unparsed_lines": bad,
            "extract_failed": lines > 0 and not msgs}

# ---- 장부 --------------------------------------------------------------------------
def ledger_rows():
    """장부 표의 행을 {ID: {"상태": …, "효과": …}}로. 머리 줄의 열 이름으로 위치를 찾는다."""
    rows, cols = {}, None
    try:
        lines = open(LEDGER, encoding="utf-8").read().splitlines()
    except OSError:
        return rows
    for line in lines:
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] == "ID":
            cols = {name: i for i, name in enumerate(cells)}
            continue
        if cols and re.fullmatch(r"R-\d+", cells[0] if cells else ""):
            get = lambda name: next((cells[i] for n, i in cols.items() if n.startswith(name) and i < len(cells)), "")
            rows[cells[0]] = {"상태": get("상태"), "효과": get("효과")}
    return rows

# ---- 후보 판정 ---------------------------------------------------------------------
KINDS = {"new": "새 행", "update": "값 변경", "revert": "되돌리기"}
EFFECTS = {"", "미확인", "도움됨", "해로움", "효과 없음", "판정 불가"}

def judge(c, digests, rows):
    """후보를 남길지 판정한다. 버리면 이유, 남기면 None."""
    if not isinstance(c, dict) or c.get("kind") not in KINDS:
        return "모르는 종류"
    kind, lid = c["kind"], (c.get("ledger_id") or "").strip()
    if lid and lid not in rows:
        return f"장부에 없는 행 {lid}"
    ev = c.get("evidence") or []
    for e in ev:
        d = digests.get(str((e or {}).get("session", "")))
        n = (e or {}).get("message")
        if d is None:
            return f"이번 분석에 없는 세션 {(e or {}).get('session')}"
        if not isinstance(n, int) or not 1 <= n <= d["message_count"]:
            return f"세션 {d['session']}에 없는 메시지 번호 {n}"
    if c.get("effect", "") not in EFFECTS:
        return f"모르는 효과 값 {c.get('effect')}"
    if kind == "new" and len(ev) < 2:
        return "근거가 2건보다 적음"
    if kind in ("update", "revert"):
        if not lid:
            return "장부 행 ID 없음"
        if not rows[lid]["상태"].startswith("반영"):
            return f"{lid}가 반영 상태가 아님"
    if kind == "update" and not ev:
        return "재발 근거 없음"
    if kind == "revert" and rows[lid]["효과"] not in ("효과 없음", "해로움"):
        return f"{lid}의 효과가 효과 없음·해로움으로 확정되지 않음"
    return None

def render(c, digests):
    lid = (c.get("ledger_id") or "").strip()
    label = KINDS[c["kind"]] if c["kind"] == "new" else f"{lid} {KINDS[c['kind']]}"
    out = [f"### [{label}] {c.get('symptom', '').strip()}", ""]
    if c.get("action"):
        out.append(f"- 후보 조치: {c['action'].strip()}")
    if c.get("layer"):
        out.append(f"- 고칠 층: {c['layer']}")
    if c.get("token_cost"):
        out.append(f"- 토큰 비용: {c['token_cost'].strip()}")
    if c["kind"] == "new" and lid:
        out.append(f"- 관련 장부 행: {lid}")
    ev = c.get("evidence") or []
    if c["kind"] == "update":
        sessions = {e["session"] for e in ev}
        last = max(digests[s]["date"] for s in sessions)
        out.append(f"- 재발: 이번 분석에서 세션 {len(sessions)}개 · 마지막 {last}")
    if c.get("effect"):
        out.append(f"- 효과 제안: {c['effect']}")
    for e in ev:
        d = digests[e["session"]]
        quote = d["messages"][e["message"] - 1]["text"].replace("\n", " ")[:100]
        out.append(f"- 근거: `{e['session']}` #{e['message']} ({d['date']}) — {quote}")
    return "\n".join(out) + "\n"

SCHEMA = {
    "type": "object", "required": ["candidates"],
    "properties": {"candidates": {"type": "array", "items": {
        "type": "object", "required": ["kind", "symptom", "evidence"],
        "properties": {
            "kind": {"enum": list(KINDS)},
            "symptom": {"type": "string"}, "action": {"type": "string"},
            "layer": {"enum": ["규칙", "스킬·에이전트", "훅", "문서"]},
            "token_cost": {"type": "string"}, "ledger_id": {"type": "string"},
            "effect": {"enum": sorted(EFFECTS)},
            "evidence": {"type": "array", "items": {
                "type": "object", "required": ["session", "message"],
                "properties": {"session": {"type": "string"}, "message": {"type": "integer"}}}},
        }}}},
}

def parse_output(res):
    out = res.get("structured_output")
    if isinstance(out, dict):
        return out
    text = res.get("result") or ""
    m = re.search(r"\{.*\}", text, re.S)
    if m:
        try:
            out = json.loads(m.group(0))
            if isinstance(out, dict):
                return out
        except ValueError:
            pass
    return None

# ---- 실행 --------------------------------------------------------------------------
def log_run(**f):
    cols = ["at", "kind", "model", "sessions", "input_bytes", "input_tokens", "output_tokens", "cost", "result",
            "kept", "dropped", "failed"]
    with open(os.path.join(STORE, "runs.tsv"), "a", encoding="utf-8") as fh:
        fh.write("\t".join(str(f.get(k, "")) for k in cols) + "\n")

def run(argv):
    model, budget, picked = ENV.get("MODEL", ""), ENV.get("BUDGET", ""), []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--model", "--budget", "--session") and i + 1 < len(argv):
            if a == "--model": model = argv[i + 1]
            elif a == "--budget": budget = argv[i + 1]
            else: picked.append(argv[i + 1])
            i += 2
        else:
            print(f"모르는 인자: {a}", file=sys.stderr); return 2
    if not model:
        print("모델을 정하지 않았다 — 첫 실행은 --model sonnet과 --model opus로 비교하고, 고른 모델을 이 스크립트의 MODEL에 적는다", file=sys.stderr)
        return 2
    trial = bool(picked)
    kind = "시험" if trial else "정기"
    os.makedirs(os.path.join(STORE, "digests"), exist_ok=True)
    started = time.time()
    at = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    state = os.path.join(STORE, "last-analysis")

    if trial:
        files = [os.path.join(TRANSCRIPTS, s + ".jsonl") for s in picked]
        missing = [f for f in files if not os.path.isfile(f)]
        if missing:
            print("대화 기록이 없다: " + " ".join(missing), file=sys.stderr); return 2
    else:
        since = os.path.getmtime(state) if os.path.isfile(state) else None
        names = sorted(os.listdir(TRANSCRIPTS)) if os.path.isdir(TRANSCRIPTS) else []
        files = [os.path.join(TRANSCRIPTS, n) for n in names if n.endswith(".jsonl")
                 and os.path.isfile(os.path.join(TRANSCRIPTS, n))
                 and (since is None or os.path.getmtime(os.path.join(TRANSCRIPTS, n)) > since)]
    print(f"[{kind}] 세션 {len(files)}개")
    if not files:
        log_run(at=at, kind=kind, model=model, sessions=0, result="새 세션 없음")
        print("마지막 분석 뒤 새 세션이 없다 — 모델을 부르지 않는다")
        return 0

    digests = {}
    for f in files:
        d = digest(f)
        digests[d["session"]] = d
        with open(os.path.join(STORE, "digests", d["session"] + ".json"), "w", encoding="utf-8") as fh:
            json.dump(d, fh, ensure_ascii=False, indent=1)
    failed = [s for s, d in digests.items() if d["extract_failed"]]
    if failed:
        log_run(at=at, kind=kind, model=model, sessions=len(files), result="추출 실패", failed=len(failed))
        print("추출 실패 — 줄은 있는데 사용자 메시지를 하나도 뽑지 못했다(대화 기록 형식이 바뀌었을 수 있다): " + " ".join(failed))
        print("모델을 부르지 않고 마지막 분석 시각도 옮기지 않는다. 요약 추출(digest)을 고친 뒤 다시 돌린다")
        return 1

    queue_path = os.path.join(STORE, "queue.tsv")
    queue = open(queue_path, encoding="utf-8").read().splitlines() if os.path.isfile(queue_path) else []
    ledger = open(LEDGER, encoding="utf-8").read() if os.path.isfile(LEDGER) else ""
    payload = {"sessions": list(digests.values()),
               "correction_queue": [dict(zip(["date", "session", "file", "description", "count"], q.split("\t"))) for q in queue],
               "ledger": ledger}
    prompt = open(PROMPT, encoding="utf-8").read() + "\n\n## 입력\n\n```json\n" + json.dumps(payload, ensure_ascii=False, indent=1) + "\n```\n"
    with open(os.path.join(STORE, "input.md"), "w", encoding="utf-8") as fh:
        fh.write(prompt)
    size = len(prompt.encode("utf-8"))
    print(f"입력 {size // 1024}KB · 모델 {model} · 비용 상한 ${budget}")

    cmd = [ENV["CLAUDE_BIN"], "-p", "--setting-sources", "user", "--no-session-persistence",
           "--output-format", "json", "--max-budget-usd", str(budget), "--model", model,
           "--tools", "Read,Grep,Glob", "--json-schema", json.dumps(SCHEMA, ensure_ascii=False)]
    try:
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=ROOT)
        res = json.loads(p.stdout) if p.stdout.strip() else {}
    except (OSError, ValueError) as e:
        p, res = None, {"_error": str(e)}
    usage = res.get("usage") or {}
    tok_in = sum(int(usage.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    tok_out = int(usage.get("output_tokens") or 0)
    cost = res.get("total_cost_usd", "")
    common = dict(at=at, kind=kind, model=model, sessions=len(files), input_bytes=size,
                  input_tokens=tok_in, output_tokens=tok_out, cost=cost)

    if res.get("subtype") == "error_max_budget_usd":
        log_run(result="비용 상한", **common)
        print(f"비용 상한(${budget})에 걸렸다 — 쓴 비용 ${cost}. 후보를 쓰지 않고 마지막 분석 시각도 옮기지 않는다")
        return 1
    out = None if res.get("is_error") or "_error" in res else parse_output(res)
    if out is None or not isinstance(out.get("candidates"), list):
        log_run(result="실패", **common)
        detail = res.get("_error") or res.get("subtype") or (p.stderr.strip()[:200] if p else "") or "결과 형식을 읽지 못함"
        print(f"분석 실패 — {detail}. 마지막 분석 시각을 옮기지 않는다 (쓴 비용 ${cost or 0})")
        return 1

    rows = ledger_rows()
    kept, dropped = [], []
    for c in out["candidates"]:
        why = judge(c, digests, rows)
        (dropped.append((c, why)) if why else kept.append(c))

    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    if trial:
        os.makedirs(os.path.join(STORE, "trials"), exist_ok=True)
        target = os.path.join(STORE, "trials", f"{datetime.datetime.now():%Y%m%d-%H%M%S}-{model}.md")
    else:
        target = os.path.join(STORE, "candidates.md")
    new_file = not os.path.isfile(target)
    with open(target, "a", encoding="utf-8") as fh:
        if new_file:
            fh.write("# 검토할 회고 후보\n\n`improve-harness` 스킬이 `### ` 후보를 하나씩 검토한다. 검토를 마친 후보는 이 파일에서 지운다.\n")
        fh.write(f"\n## {stamp} {kind} 분석 — {model} · 세션 {len(files)}개 · 후보 {len(kept)}건 · 버림 {len(dropped)}건\n\n")
        reflected = [rid for rid, r in rows.items() if r["상태"].startswith("반영")]
        if reflected:
            hits = {c.get("ledger_id") for c in kept if c["kind"] == "update"}
            fh.write("장부 점검(반영된 행의 이번 재발): " + " · ".join(f"{r} {'있음' if r in hits else '0'}" for r in reflected) + "\n\n")
        for c in kept:
            fh.write(render(c, digests) + "\n")
        for c, why in dropped:
            fh.write(f"- 버림: {str((c or {}).get('symptom', ''))[:80]} — {why}\n")

    if not trial:
        # 다음 실행과 알림 훅은 이 파일보다 늦게 바뀐 기록을 센다. 분석 시작 시각에 맞춰, 분석하는 동안 바뀐 기록은 다음에 다시 본다
        with open(state, "w", encoding="utf-8") as fh:
            fh.write(at + "\n")
        os.utime(state, (started, started))
        # 분석에 넣은 정정 대기열 줄만 지운다 — 그 사이 훅이 더한 줄은 남는다
        if queue and os.path.isfile(queue_path):
            seen = set(queue)
            rest = [q for q in open(queue_path, encoding="utf-8").read().splitlines() if q not in seen]
            with open(queue_path, "w", encoding="utf-8") as fh:
                fh.write("".join(q + "\n" for q in rest))

    log_run(result="성공", kept=len(kept), dropped=len(dropped), **common)
    print(f"토큰 입력 {tok_in} / 출력 {tok_out} · 비용 ${cost}")
    print(f"후보 {len(kept)}건 · 버림 {len(dropped)}건 → {os.path.relpath(target, ROOT)}")
    for c, why in dropped:
        print(f"  버림: {str((c or {}).get('symptom', ''))[:60]} — {why}")
    return 0

def main(argv):
    if argv and argv[0] == "digest":
        if len(argv) != 2 or not os.path.isfile(argv[1]):
            print("사용: analyze-corrections.sh digest <대화 기록.jsonl>", file=sys.stderr); return 2
        d = digest(argv[1])
        print(json.dumps(d, ensure_ascii=False))
        if d["extract_failed"]:
            print(f"추출 실패: {argv[1]}", file=sys.stderr)
            return 1
        return 0
    if argv and argv[0] == "run":
        argv = argv[1:]
    return run(argv)

sys.exit(main(sys.argv[1:]))
PY
