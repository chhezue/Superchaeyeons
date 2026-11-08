#!/bin/bash
# Blocks ending the turn with a "done/passed" claim when code was edited but the test command never ran (or failed).
# Registered in plugin/hooks/hooks.json (Stop). core-workflow.md G3 "실행 없이 통과했을 것이라고 보고 금지"를
# 결정론적으로 강제한다.
#
# TEST_CMD는 설정 키 TEST_CMD({{테스트 명령}}, .claude/harness.conf)다. 하네스 기본은 플러그인 scripts/dev.sh test이고, 프로젝트마다
# 다른 실제 테스트 명령은 dev.conf가 갖는다. 설정이 없거나 깨졌거나 값이 "(없음)"·빈 값이면 아무것도 막지 않는다(Stop 훅은 판정 불가 = 통과).
# ---- 프로젝트 설정 .claude/harness.conf -------------------------------------------
# 값은 훅 본문이 아니라 프로젝트 설정 파일에 있다 — 플러그인은 모든 프로젝트가 같은 훅 파일을 쓴다. 키·뜻은 플러그인
# scripts/harness-keys.txt, 값 규칙은 skills/init-harness/references/harness-conf.md. 파일이 없으면(init 전) 가장 엄격한
# 기본값, 쓰는 키가 없으면 그 키만 기본값, 깨졌으면(키=값이 아닌 줄 · 쓰는 키가 빈칸 {…}이거나 허용 밖 값) conf_bad에 이유를 둔다.
conf_path="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")}/.claude/harness.conf"
conf_keys=" "; conf_bad=""; conf_found=0
if [ -f "$conf_path" ]; then
	conf_found=1
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		if [[ $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
			printf -v "conf_${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"; conf_keys="$conf_keys${BASH_REMATCH[1]} "
		else
			conf_bad="키=값이 아닌 줄 (${line:0:40})"
		fi
	done <"$conf_path"
fi
# conf_use <키> <기본값> <허용 정규식> — 키 값을 같은 이름의 변수에 둔다. 빈칸이거나 허용 밖이면 conf_bad
conf_use() {
	local name="conf_$1" v="$2"
	case "$conf_keys" in *" $1 "*) v="${!name}" ;; esac
	if [[ $v =~ ^\{[^{}]*\}$ ]] || ! [[ $v =~ $3 ]]; then conf_bad="$1 값이 빈칸이거나 허용되지 않는다 ($v)"; fi
	printf -v "$1" '%s' "$v"
}
conf_use TEST_CMD "" '.*'
[ -n "$conf_bad" ] && exit 0
#
# 판정: 마지막 사용자 메시지 이후에
#   (a) 문서(.md/.txt/.rst)가 아닌 파일을 고쳤고 — Write/Edit/MultiEdit/NotebookEdit 도구뿐 아니라 Bash의 `sed -i`·`tee`·
#       `>`/`>>` 리다이렉션도 편집으로 센다 (2026-09-07 감사: Bash 편집이 보이지 않아 게이트가 무동작이던 사각),
#       heredoc 본문(`<<EOF` 다음 줄부터 구분자 줄까지)은 명령이 아니라 데이터라 보지 않는다 — 커밋 메시지 서명의 `<…@…>`가
#       리다이렉션으로 오판되던 사각(2026-10-23 실세션). 따옴표 안·주석의 `>`도 같은 이유로 보지 않는다(2026-10-26 실세션).
#       `sed -i`는 식이 아니라 파일 피연산자만 보고, 저장소 밖 절대 경로(스크래치·/tmp·홈) 쓰기는 편집으로 치지 않는다 —
#       식 안의 `com.a.b`와 스크래치 임시 파일을 코드 편집으로 세던 오판(2026-10-26 붙여 쓴 저장소 실세션),
#   (b) 그 **마지막 편집 이후에** TEST_CMD를 — 한 명령 안에서도 편집보다 뒤에 있어야 한다 — 명령으로 실행한 기록이 없거나(`cat plugin/scripts/dev.sh`처럼 문자열로 언급한 것은 실행이
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

case "$TEST_CMD" in '' | '(없음)'*) exit 0 ;; esac

input=$(cat)
verdict=$(COMPLETION_POLICY="${0%/*}/../scripts/completion-policy.py" TEST_CMD="$TEST_CMD" python3 -I -c '
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
import runpy
try:
    policy = runpy.run_path(os.environ["COMPLETION_POLICY"], init_globals={"test_words": test_words})
    DOC_EXT, CLAIM = policy["DOC_EXT"], policy["CLAIM"]
    strip_heredocs, data_mask = policy["strip_heredocs"], policy["data_mask"]
    last_code_edit, last_test_run = policy["last_code_edit"], policy["last_test_run"]
    is_code_target, FAILED = policy["is_code_target"], policy["FAILED"]
except Exception:
    print("SKIP"); sys.exit(0)
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
                    edit_at = 0 if is_code_target(p) else -1
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

# 안내할 명령 — TEST_CMD가 플러그인 도구(plugin/scripts/dev.sh)면 플러그인 경로를 붙인다. Bash 도구에는 CLAUDE_PLUGIN_ROOT가 없어
# Claude가 경로를 알 수 없다. 판정은 TEST_CMD 그대로 한다 — 첫 단어는 파일 이름만 맞춰 보므로 경로가 붙어도 실행으로 인정된다
show_cmd="$TEST_CMD"
case "$TEST_CMD" in scripts/dev.sh*) [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && show_cmd="$CLAUDE_PLUGIN_ROOT/$TEST_CMD" ;; esac

case "$verdict" in
  BLOCK_NOT_RUN)
    echo "[하네스 · G3] 이 턴에 코드 파일을 고쳤는데(도구 편집 또는 Bash의 sed -i·리다이렉션·tee) 그 뒤 \`$show_cmd\`를 실행한 기록이 없는 채로 완료·통과를 선언했습니다. 지금 \`$show_cmd\`를 실제로 돌리고 결과를 보고하세요. 돌릴 수 없는 환경이면 완료 선언 대신 \"검증하지 못한 것\"으로 남기세요 (core-workflow.md G3). Blocked by superchaeyeons 플러그인 hooks/deny-unverified-completion.sh." >&2
    exit 2 ;;
  BLOCK_FAILED)
    echo "[하네스 · G3] \`$show_cmd\`를 돌렸지만 결과가 실패였는데 완료·통과를 선언했습니다. 실패 원인을 고치고 다시 돌리거나, 완료 선언 대신 실패 내용을 그대로 보고하세요 (verify-work 스킬 사후 모드 1단계). Blocked by superchaeyeons 플러그인 hooks/deny-unverified-completion.sh." >&2
    exit 2 ;;
esac
exit 0
