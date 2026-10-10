#!/bin/bash
# Blocks ending the turn with a "done/passed" claim when code was edited but the test command never ran.
# Registered in .claude/settings.json (Stop). core-workflow.md G3 "실행 없이 통과했을 것이라고 보고 금지"를
# 처음으로 결정론적으로 강제한다.
#
# TEST_CMD는 harness-map.md의 {{테스트 명령}}과 같은 값이어야 한다 — 훅은 슬롯을 읽지 못하므로 여기 직접 적는다.
# 슬롯을 바꾸면 이 줄도 함께 고칠 것. "(없음)"이나 빈 값이면 아무것도 막지 않는다 (테스트 없는 저장소를 영구히 막지 않기 위해).
TEST_CMD="scripts/verify.sh"
#
# 판정: 마지막 사용자 메시지 이후에 (a) 문서(.md/.txt/.rst)가 아닌 파일에 Write/Edit이 있었고 (b) TEST_CMD를 담은 Bash 실행이
# 없었고 (c) 마지막 어시스턴트 텍스트에 완료 단정("완료·통과·끝났·마쳤·done·passed")이 있으면 exit 2 — 모델이 이어서 테스트를
# 돌리거나 문구를 고친다. 문서만 고친 턴에는 발화하지 않는다.
# 완료 단정에서 제외하는 것: "완료 조건·기준·선언·보고"처럼 규칙을 인용하는 명사구, "미완료", "통과하지/못", 영어는 단어 경계
# (abandoned·undone은 잡지 않는다). 오탐이 나도 stop_hook_active로 한 번만 되돌리므로 피해는 한 턴이다.
#
# 훅 공통 규약의 명시적 예외: Stop 훅은 판정 불가(transcript 없음·형식 변경)면 **통과**시킨다 — 대화가 끝나지 못하는 것이
# 미검증 완료 선언보다 큰 피해다. stop_hook_active=true(이 훅이 이미 한 번 되돌린 뒤)에도 통과시켜 무한 루프를 막는다.
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
test_key = os.path.basename(test_cmd.split()[0])
DOC_EXT = (".md", ".txt", ".rst")
CLAIM = re.compile(
    r"(?<!미)완료(?!\s?(조건|기준|선언|보고))"
    r"|통과(?!\s?(하지|시키지|못|하지 못))"
    r"|끝났|마쳤"
    r"|\bdone\b|\bpassed\b",
    re.I,
)

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

# 마지막 사람 메시지(텍스트가 있는 user 턴) 찾기 — tool_result만 있는 user 턴은 경계가 아니다
last_user = -1
for i, t in enumerate(turns):
    if t.get("type") == "user" and any(b.get("type") == "text" for b in blocks(t)):
        last_user = i
if last_user < 0:
    print("SKIP"); sys.exit(0)

code_edit = test_ran = False
last_text = ""
for t in turns[last_user + 1:]:
    if t.get("type") != "assistant":
        continue
    for b in blocks(t):
        if b.get("type") == "tool_use":
            name = b.get("name", ""); inp = b.get("input") or {}
            if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                p = (inp.get("file_path") or inp.get("notebook_path") or "").lower()
                if p and not p.endswith(DOC_EXT):
                    code_edit = True
            elif name == "Bash" and test_key in (inp.get("command") or ""):
                test_ran = True
        elif b.get("type") == "text" and b.get("text", "").strip():
            last_text = b["text"]

if code_edit and not test_ran and CLAIM.search(last_text):
    print("BLOCK")
else:
    print("OK")
' <<< "$input")

if [ "$verdict" = "BLOCK" ]; then
  echo "[하네스 · G3] 이 턴에 코드 파일을 고쳤는데 \`$TEST_CMD\`를 실행한 기록이 없는 채로 완료·통과를 선언했습니다. 지금 \`$TEST_CMD\`를 실제로 돌리고 결과를 보고하세요. 돌릴 수 없는 환경이면 완료 선언 대신 \"검증하지 못한 것\"으로 남기세요 (core-gates.md §3). Blocked by .claude/hooks/deny-unverified-completion.sh." >&2
  exit 2
fi
exit 0
