#!/usr/bin/env bash
# dev.sh 엔진 테스트 — 가짜 명령을 가리키는 임시 dev.conf로 동사·종료 코드·출력 형식을 판정한다.
# 실제 빌드 도구·컨테이너는 쓰지 않는다. 앱 기동은 python3 내장 HTTP 서버로 대신한다.
#
# 사용:
#   scripts/test-dev.sh
#
# exit 0 = 전부 통과 · exit 1 = 실패 있음 · exit 2 = 환경 오류(python3 없음)
# 계약 원문: scripts/dev.sh 머리. 스펙: docs/specs/cross-cutting/dev-script.md

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
dev="$repo_root/scripts/dev.sh"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 없음" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dev-test.XXXXXX")"
cleanup() {
	# 테스트가 띄운 앱이 남아 있으면 끈다 — pid 파일에 적힌 프로세스 그룹만
	for f in "$tmp"/*/logs/app.pid; do
		[ -f "$f" ] && kill -TERM -- "-$(cat "$f")" 2>/dev/null
	done
	[ -n "${blocker_pid:-}" ] && kill "$blocker_pid" 2>/dev/null
	rm -r -- "$tmp"
}
trap cleanup EXIT

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
ng() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /' | head -15; }

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }

# 케이스마다 디렉터리 하나: fake/(가짜 명령) · logs/(LOG_DIR) · dev.conf
# conf <이름> <KEY=VALUE…> — 지정하지 않은 키는 "없음 — 테스트"로 채운다
KEYS="BUILD_CMD TEST_CMD TEST_REPORT FMT_CMD DEPS_CMD RUN_ENV SERVICES EXTRA_CONTAINERS WAIT_SERVICES START_CMD APP_PORT HEALTH_URL WAIT_HEALTH LOG_DIR"
conf() {
	local name="$1"; shift
	local d="$tmp/$name"; mkdir -p "$d/fake" "$d/logs"
	local f="$d/dev.conf"; : >"$f"
	for k in $KEYS; do
		local v="없음 — 테스트"
		[ "$k" = "LOG_DIR" ] && v="$d/logs"
		for kv in "$@"; do [ "${kv%%=*}" = "$k" ] && v="${kv#*=}"; done
		printf '%s=%s\n' "$k" "$v" >>"$f"
	done
	echo "$f"
}
run() { # run <conf> <동사…> → out·rc 전역
	out="$(DEV_CONF="$1" "$dev" "${@:2}" 2>&1)"; rc=$?
}
lines() { printf '%s\n' "$out" | grep -c .; }

# ---- 설정 파일 ----
run "$tmp/none.conf" build
[ "$rc" = 2 ] && ok "설정 파일 없음 → exit 2" || ng "설정 파일 없음 → exit 2 (실제 $rc)" "$out"

c="$(conf missing)"; grep -v '^FMT_CMD=' "$c" >"$c.x" && mv "$c.x" "$c"
run "$c" build
[ "$rc" = 2 ] && ok "필수 키 없음 → exit 2" || ng "필수 키 없음 → exit 2 (실제 $rc)" "$out"

c="$(conf unknown)"; echo "BUIDL_CMD=true" >>"$c"
run "$c" build
[ "$rc" = 2 ] && ok "모르는 키(오타) → exit 2" || ng "모르는 키(오타) → exit 2 (실제 $rc)" "$out"

run "$(conf placeholder "BUILD_CMD={빌드 명령}")" build
[ "$rc" = 2 ] && ok "채우지 않은 자리표시자 {…} → exit 2" || ng "채우지 않은 자리표시자 {…} → exit 2 (실제 $rc)" "$out"

run "$(conf verb)" deploy
[ "$rc" = 2 ] && ok "모르는 동사 → exit 2" || ng "모르는 동사 → exit 2 (실제 $rc)" "$out"

# ---- 없음 ----
run "$(conf nothing)" start
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && [[ "$out" == "dev start: 없음 — 테스트" ]] \
	&& ok "값이 없음인 동사 → 이유 한 줄 · exit 0" || ng "값이 없음인 동사 → 이유 한 줄 · exit 0 (실제 $rc)" "$out"

# ---- build · fmt · deps ----
run "$(conf build-ok "BUILD_CMD=echo compiling; echo done")" build
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && [[ "$out" == "dev build: 통과 — "* ]] \
	&& ok "build 성공 → 한 줄 · exit 0" || ng "build 성공 → 한 줄 · exit 0 (실제 $rc)" "$out"

d="$tmp/build-fail"
run "$(conf build-fail "BUILD_CMD=for i in \$(seq 1 40); do echo line\$i; done; echo 'error: x' >&2; exit 3")" build
[ "$rc" = 1 ] && [[ "$out" == "dev build: 실패 1"* ]] && [ "$(lines)" -le 13 ] \
	&& printf '%s' "$out" | grep -q "error: x" && printf '%s' "$out" | grep -q "전체 로그: $d/logs/build.log" \
	&& [ "$(grep -c line "$d/logs/build.log")" = 40 ] \
	&& ok "build 실패 → 실패 줄 · 마지막 줄들 · 전체 로그 경로 · exit 1" || ng "build 실패 → 실패 줄 · 마지막 줄들 · 전체 로그 경로 · exit 1 (실제 $rc)" "$out"

run "$(conf deps "DEPS_CMD=for i in \$(seq 1 300); do echo dep\$i; done")" deps
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && printf '%s' "$out" | grep -q "300줄" \
	&& ok "deps → 줄 수와 로그 경로 한 줄" || ng "deps → 줄 수와 로그 경로 한 줄 (실제 $rc)" "$out"

# ---- test ----
d="$tmp/junit-fail"; mkdir -p "$d/fake/results"
cat >"$d/fake/test.sh" <<'EOF'
#!/usr/bin/env bash
cat >"$(dirname "$0")/results/TEST-a.xml" <<'X'
<testsuite name="a" tests="3" failures="1" errors="0" skipped="1">
  <testcase classname="pkg.OrderTest" name="pays_once()"><failure message="expected 1 but was 2">stack line 1
stack line 2</failure></testcase>
  <testcase classname="pkg.OrderTest" name="cancels()"/>
  <testcase classname="pkg.OrderTest" name="later()"><skipped/></testcase>
</testsuite>
X
for i in $(seq 1 200); do echo "noise $i"; done
exit 1
EOF
chmod +x "$d/fake/test.sh"
# 이전 실행에서 남은 결과 파일은 세지 않는다 (실행 시작 전 파일)
cat >"$d/fake/results/TEST-old.xml" <<'X'
<testsuite name="old" tests="1" failures="1"><testcase classname="pkg.Old" name="stale()"><failure message="old"/></testcase></testsuite>
X
touch -t 202001010000 "$d/fake/results/TEST-old.xml"
run "$(conf junit-fail "TEST_CMD=$d/fake/test.sh" "TEST_REPORT=junit:$d/fake/results/*.xml")" test
[ "$rc" = 1 ] && [[ "$out" == "dev test: 실패 1"* ]] && [ "$(lines)" -le 15 ] \
	&& printf '%s' "$out" | grep -q "pkg.OrderTest.pays_once() — expected 1 but was 2" \
	&& ! printf '%s' "$out" | grep -q "stale" && ! printf '%s' "$out" | grep -q "noise" \
	&& ok "test 실패(결과 파일) → 실패한 테스트 이름과 원인만 · 이전 결과 무시 · exit 1" || ng "test 실패(결과 파일) → 실패한 테스트 이름과 원인만 · 이전 결과 무시 · exit 1 (실제 $rc)" "$out"

d="$tmp/junit-ok"; mkdir -p "$d/fake/results"
cat >"$d/fake/test.sh" <<'EOF'
#!/usr/bin/env bash
echo "args:$*" >"$(dirname "$0")/args.txt"
cat >"$(dirname "$0")/results/TEST-a.xml" <<'X'
<testsuite name="a" tests="2" failures="0" errors="0" skipped="0"><testcase classname="p.A" name="x()"/><testcase classname="p.A" name="y()"/></testsuite>
X
exit 0
EOF
chmod +x "$d/fake/test.sh"
c="$(conf junit-ok "TEST_CMD=$d/fake/test.sh" "TEST_REPORT=junit:$d/fake/results/*.xml")"
run "$c" test
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && [[ "$out" == "dev test: 통과 — 테스트 2개"* ]] \
	&& ok "test 성공(결과 파일) → 개수 한 줄 · exit 0" || ng "test 성공(결과 파일) → 개수 한 줄 · exit 0 (실제 $rc)" "$out"
run "$c" test --tests "p.A with space"
[ "$rc" = 0 ] && [ "$(cat "$d/fake/args.txt")" = "args:--tests p.A with space" ] \
	&& ok "test 인자 → 명령 뒤에 그대로 전달" || ng "test 인자 → 명령 뒤에 그대로 전달 (실제 $(cat "$d/fake/args.txt" 2>/dev/null))" "$out"

# 이번 실행이 결과 파일을 쓰지 않았는데(빌드 도구가 최신 상태라 건너뜀 · 경로 오타) 성공으로 보고하면 안 된다
d="$tmp/junit-none"; mkdir -p "$d/fake/results"
run "$(conf junit-none "TEST_CMD=echo up-to-date" "TEST_REPORT=junit:$d/fake/results/*.xml")" test
[ "$rc" = 1 ] && [[ "$out" == "dev test: 실패 1"* ]] && printf '%s' "$out" | grep -q "결과 파일" \
	&& ok "test 결과 파일 없음 → 통과가 아니라 실패 · exit 1" || ng "test 결과 파일 없음 → 통과가 아니라 실패 · exit 1 (실제 $rc)" "$out"

run "$(conf lastline "TEST_CMD=echo step1; echo 'suite: all 12 ok'" "TEST_REPORT=last-line")" test
[ "$rc" = 0 ] && [ "$out" = "dev test: 통과 — suite: all 12 ok" ] \
	&& ok "test 성공(last-line) → 마지막 줄이 요약" || ng "test 성공(last-line) → 마지막 줄이 요약 (실제 $rc)" "$out"

# ---- 위험 명령 사전 검사 — 설정 파일로 훅을 거치지 않는 실행을 막는다 ----
d="$tmp/danger"
run "$(conf danger "BUILD_CMD=touch $d/ran; git push --force origin main")" build
[ "$rc" = 2 ] && [ ! -e "$d/ran" ] \
	&& ok "설정 명령이 위험 명령 패턴에 걸림 → 실행하지 않고 exit 2" || ng "설정 명령이 위험 명령 패턴에 걸림 → 실행하지 않고 exit 2 (실제 $rc)" "$out"

# ---- start · status · logs · stop ----
port="$(free_port)"; d="$tmp/app"
c="$(conf app "START_CMD=cd $d/fake && echo 'ERROR boot warning' && exec python3 -m http.server $port --bind 127.0.0.1" \
	"APP_PORT=$port" "HEALTH_URL=http://127.0.0.1:$port/" "WAIT_HEALTH=20")"
run "$c" start
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && [[ "$out" == "dev start: 통과 — "* ]] && [ -f "$d/logs/app.pid" ] \
	&& ok "start → 헬스 성공까지 기다림 · 한 줄 · pid 파일" || ng "start → 헬스 성공까지 기다림 · 한 줄 · pid 파일 (실제 $rc)" "$out"
pid1="$(cat "$d/logs/app.pid" 2>/dev/null)"
run "$c" start
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "이미 실행 중 (PID $pid1)" \
	&& ok "start 두 번 → 이미 실행 중 · 같은 PID" || ng "start 두 번 → 이미 실행 중 · 같은 PID (실제 $rc)" "$out"
run "$c" status
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && printf '%s' "$out" | grep -q "실행 중 (PID $pid1)" \
	&& ok "status → 한 줄" || ng "status → 한 줄 (실제 $rc)" "$out"
run "$c" logs 5
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "ERROR boot warning" && [ "$(lines)" -le 20 ] \
	&& ok "logs → 에러 줄과 마지막 N줄" || ng "logs → 에러 줄과 마지막 N줄 (실제 $rc)" "$out"
run "$c" stop
closed=1; (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && closed=0
[ "$rc" = 0 ] && [ ! -f "$d/logs/app.pid" ] && [ "$closed" = 1 ] \
	&& ok "stop → PID로 종료 · 포트 닫힘 · pid 파일 지움" || ng "stop → PID로 종료 · 포트 닫힘 · pid 파일 지움 (실제 $rc)" "$out"
run "$c" stop
[ "$rc" = 0 ] && ok "stop 두 번 → exit 0" || ng "stop 두 번 → exit 0 (실제 $rc)" "$out"

port="$(free_port)"; d="$tmp/timeout"
run "$(conf timeout "START_CMD=echo 'Caused by: boom'; exec sleep 60" "APP_PORT=$port" "HEALTH_URL=http://127.0.0.1:$port/" "WAIT_HEALTH=2")" start
[ "$rc" = 1 ] && [[ "$out" == "dev start: 실패 1"* ]] && printf '%s' "$out" | grep -q "Caused by: boom" && [ ! -f "$d/logs/app.pid" ] \
	&& ok "헬스 시간 초과 → 앱 종료 · 에러 줄 · exit 1" || ng "헬스 시간 초과 → 앱 종료 · 에러 줄 · exit 1 (실제 $rc)" "$out"

port="$(free_port)"
python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
blocker_pid=$!
for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; sleep 0.1; done
run "$(conf busy "START_CMD=sleep 60" "APP_PORT=$port" "HEALTH_URL=http://127.0.0.1:$port/" "WAIT_HEALTH=5")" start
[ "$rc" = 2 ] && ok "앱 포트가 이미 사용 중 → exit 2" || ng "앱 포트가 이미 사용 중 → exit 2 (실제 $rc)" "$out"

echo
echo "dev.sh 케이스 $((pass + fail)) · 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
