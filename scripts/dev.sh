#!/usr/bin/env bash
# 프로젝트 빌드·테스트·실행 엔진 — 모든 프로젝트가 같은 이 파일을 쓰고, 프로젝트마다 다른 값은 scripts/dev.conf에만 둔다.
# 이 파일을 프로젝트에서 고치지 않는다. 특별한 절차가 필요하면 그 절차를 프로젝트 스크립트로 만들어 dev.conf 명령 자리에 적는다.
# 스펙: {{스펙 저장소}}의 cross-cutting/dev-script.md (이 머리가 동사·종료 코드·출력·설정 키의 SSOT)
#
# 사용:
#   scripts/dev.sh build | test [인자…] | fmt | deps | start | stop | status | logs [N]
#   DEV_CONF=<경로> scripts/dev.sh …      # 다른 설정 파일 (scripts/test-dev.sh가 쓴다)
#
# 종료 코드: 0 성공(값이 "없음"인 동사 포함) · 1 실패 · 2 환경 없음(설정 파일·키 · 컨테이너 런타임 · 포트 점유 · 위험 명령 차단)
#
# 출력 — 대화에 들어가는 양을 줄이려고 고정한다. 전체 출력은 <LOG_DIR>/<동사>.log에 덮어쓰고, 필요할 때만 그 파일을 본다.
#   성공: `dev <동사>: 통과 — <요약>` 한 줄
#   실패: `dev <동사>: 실패 <개수>` 한 줄 + 항목마다 한 줄(최대 10개, 줄당 300자) + `  전체 로그: <경로>`
#         실패 줄은 deny-unverified-completion.sh의 실패 판정("실패 [1-9]")에 걸리고, 성공 줄은 걸리지 않는다
#   없음: `dev <동사>: 없음 — <이유>` 한 줄
#
# dev.conf — 한 줄에 `키=값`. `#` 줄과 빈 줄은 건너뛴다. source하지 않고 줄 단위로 읽으므로 값은 적힌 그대로 쓰인다.
# 아래 키가 모두 있어야 하고(모르는 키·중복·채우지 않은 `{…}` 값도 exit 2), 해당 없는 키는 `없음 — <이유>`로 적는다.
#   BUILD_CMD · FMT_CMD · DEPS_CMD   빌드 · 포맷 · 의존성 조회 명령
#   TEST_CMD                          전체 테스트 명령. `test` 뒤 인자는 이 명령 뒤에 그대로 붙는다
#   TEST_REPORT                       `junit:<경로 패턴>`(여러 언어 테스트 도구가 내보내는 junit XML 결과) · `last-line`(출력 마지막 줄을 요약으로)
#   RUN_ENV                           모든 명령에 넘길 환경 변수 `K=V K2=V2` — 비밀값은 적지 않는다
#   SERVICES                          앱보다 먼저 띄울 compose 서비스 이름(공백 구분)
#   EXTRA_CONTAINERS                  compose에 없는 의존 서비스 `이름,이미지,포트`(공백 구분)
#   WAIT_SERVICES · WAIT_HEALTH       서비스 준비 · 앱 헬스 성공까지 기다릴 최대 초
#   START_CMD · APP_PORT · HEALTH_URL 앱 기동 명령(포그라운드로 도는 명령) · 앱 포트 · 2xx면 기동 성공으로 보는 주소
#   LOG_DIR                           전체 로그와 app.pid를 둘 곳(저장소 루트 기준, 버전 관리에서 제외된 폴더)
#
# 안전: dev.conf의 명령은 이 스크립트 안에서 실행되어 PreToolUse 훅이 보지 못한다. 그래서 실행 전에 명령 문자열마다
# .claude/hooks/deny-dangerous-bash.sh에 넣어 판정을 받고, 막히거나 훅이 없으면 실행하지 않는다(exit 2).
# 종료: start는 앱을 새 프로세스 그룹으로 띄워 그 번호를 app.pid에 적고, stop은 그 그룹에만 신호를 보낸다 — 이름 패턴으로 끄지 않는다.
# start가 실패하면 그 start가 띄운 앱과 서비스를 모두 정지한다. junit 결과 파일이 이번 실행에서 하나도 쓰이지 않았으면 통과가 아니라 실패다.

set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
conf="${DEV_CONF:-scripts/dev.conf}"
guard="$root/.claude/hooks/deny-dangerous-bash.sh"
KEYS="BUILD_CMD TEST_CMD TEST_REPORT FMT_CMD DEPS_CMD RUN_ENV SERVICES EXTRA_CONTAINERS WAIT_SERVICES START_CMD APP_PORT HEALTH_URL WAIT_HEALTH LOG_DIR"
verb="${1:-}"; [ $# -gt 0 ] && shift

env_missing() { echo "dev ${verb:-?}: 환경 없음 — $1"; exit 2; }
command -v python3 >/dev/null 2>&1 || env_missing "python3 없음"

case "$verb" in
build | test | fmt | deps | start | stop | status | logs) ;;
*) echo "사용: scripts/dev.sh build | test [인자…] | fmt | deps | start | stop | status | logs [N]"; exit 2 ;;
esac

# ---- 설정 읽기 ----
[ -f "$conf" ] || env_missing "설정 파일 없음 ($conf)"
# 키마다 변수 CONF_<키>에 담는다 (연관 배열은 macOS 기본 bash 3.2에 없다)
seen=" "
while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in '' | '#'*) continue ;; esac
	key="${line%%=*}"; val="${line#*=}"
	key="${key//[[:space:]]/}"
	case " $KEYS " in *" $key "*) ;; *) env_missing "모르는 키 $key ($conf)" ;; esac
	case "$seen" in *" $key "*) env_missing "키 중복 $key ($conf)" ;; esac
	seen="$seen$key "
	val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
	[[ "$val" == \{*\} ]] && env_missing "채우지 않은 값 $key=$val ($conf)"
	printf -v "CONF_$key" '%s' "$val"
done <"$conf"
for k in $KEYS; do case "$seen" in *" $k "*) ;; *) env_missing "필수 키 없음 $k ($conf)" ;; esac; done
c() { local v="CONF_$1"; printf '%s' "${!v}"; }

none() { [[ "$1" == 없음* ]]; }
num() { [[ "$1" =~ ^[0-9]+$ ]] || env_missing "$2 값이 숫자가 아님 ($1)"; }
log_dir="$(c LOG_DIR)"; none "$log_dir" && env_missing "LOG_DIR는 없음일 수 없음"
mkdir -p "$log_dir" 2>/dev/null || env_missing "LOG_DIR를 만들 수 없음 ($log_dir)"
log="$log_dir/$verb.log"
pidfile="$log_dir/app.pid"

if ! none "$(c RUN_ENV)"; then
	for kv in $(c RUN_ENV); do
		[[ "$kv" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]] || env_missing "RUN_ENV 형식이 K=V가 아님 ($kv)"
		export "${kv?}"
	done
fi

# ---- 공통 ----
# 줄 끝을 300자로 자르고 빈 줄을 뺀 마지막 N줄 (멀티바이트 안전)
tail_lines() { python3 - "$1" "$2" "${3:-}" <<'PY'
import re, sys
path, n, pat = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    rows = [l.rstrip("\n") for l in open(path, encoding="utf-8", errors="replace") if l.strip()]
except OSError:
    rows = []
if pat:
    rows = [l for l in rows if re.search(pat, l)]
for l in rows[-n:]:
    print("  " + (l if len(l) <= 300 else l[:300] + "…"))
PY
}

# 설정 명령을 위험 명령 훅에 넣어 판정받는다. 통과면 0.
guard_check() {
	[ -x "$guard" ] || env_missing "위험 명령 검사 훅 없음 ($guard)"
	local payload
	payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$1")"
	if ! printf '%s' "$payload" | "$guard" >/dev/null 2>&1; then
		echo "dev $verb: 환경 없음 — 설정 명령이 위험 명령 검사에 막힘: $1"
		exit 2
	fi
}

fail_out() { # fail_out <개수> <본문 줄들(이미 들여씀)>
	echo "dev $verb: 실패 $1"
	[ -n "$2" ] && printf '%s\n' "$2" | grep -v '^[[:space:]]*$'
	echo "  전체 로그: $log"
	exit 1
}

secs() { echo "$(($(date +%s) - $1))초"; }

# localhost가 가리키는 주소(IPv4·IPv6)를 모두 시도한다 — 앱이 한쪽에만 열려 있어도 잡는다
port_open() { python3 -c 'import socket,sys; socket.create_connection(("localhost", int(sys.argv[1])), timeout=1).close()' "$1" 2>/dev/null; }

# ---- build · fmt · deps · test ----
run_simple() { # run_simple <키>
	local cmd; cmd="$(c "$1")"
	none "$cmd" && { echo "dev $verb: $cmd"; exit 0; }
	guard_check "$cmd"
	local t0; t0=$(date +%s)
	bash -c "$cmd" >"$log" 2>&1 </dev/null
	local rc=$?
	[ "$rc" -eq 0 ] || fail_out 1 "$(tail_lines "$log" 10)"
	if [ "$verb" = "deps" ]; then
		echo "dev deps: 통과 — $(grep -c '' "$log")줄 · 내용은 $log에서 찾는다"
	else
		echo "dev $verb: 통과 — $(secs "$t0")"
	fi
	exit 0
}

run_test() {
	local cmd="$(c TEST_CMD)" report="$(c TEST_REPORT)"
	none "$cmd" && { echo "dev test: $cmd"; exit 0; }
	local a; for a in "$@"; do cmd+=" $(printf '%q' "$a")"; done
	guard_check "$cmd"
	local t0; t0=$(date +%s)
	bash -c "$cmd" >"$log" 2>&1 </dev/null
	local rc=$?
	case "$report" in
	junit:*)
		# 이번 실행이 쓴 결과 파일만 센다 — 이전 실행이 남긴 파일을 섞지 않는다
		local summary
		summary="$(python3 - "${report#junit:}" "$t0" <<'PY'
import glob, os, sys, xml.etree.ElementTree as ET
pattern, t0 = sys.argv[1], int(sys.argv[2])
total = failed = skipped = 0; rows = []
for f in sorted(glob.glob(pattern, recursive=True)):
    if os.path.getmtime(f) < t0 - 1:
        continue
    try:
        root = ET.parse(f).getroot()
    except ET.ParseError:
        continue
    for tc in root.iter("testcase"):
        total += 1
        if tc.find("skipped") is not None:
            skipped += 1
        for bad in [x for x in tc if x.tag in ("failure", "error")][:1]:
            failed += 1
            msg = (bad.get("message") or (bad.text or "").strip().splitlines()[0:1] or [""])
            msg = msg if isinstance(msg, str) else msg[0]
            msg = " ".join(msg.split())
            name = f'{tc.get("classname", "")}.{tc.get("name", "")}'.lstrip(".")
            line = f"{name} — {msg}"
            rows.append(line if len(line) <= 300 else line[:300] + "…")
print(total, failed, skipped)
for r in rows[:10]:
    print("  " + r)
PY
)"
		local total failed skipped
		read -r total failed skipped <<<"$(printf '%s\n' "$summary" | head -1)"
		if [ -z "${total:-}" ] || [ "${total:-0}" -eq 0 ]; then
			# 빌드 도구가 최신 상태라 테스트를 건너뛰었거나 TEST_REPORT 경로가 틀렸다 — 통과로 보고하지 않는다
			fail_out 1 "  이번 실행에서 쓴 결과 파일이 없음: ${report#junit:} (테스트를 건너뛰었거나 경로가 다름)"
		elif [ "${failed:-0}" -gt 0 ]; then
			fail_out "$failed" "$(printf '%s\n' "$summary" | tail -n +2)"
		elif [ "$rc" -ne 0 ]; then
			fail_out 1 "$(tail_lines "$log" 10)"   # 결과 파일이 없을 만큼 일찍 실패(컴파일 오류 등)
		fi
		local skip=""; [ "${skipped:-0}" -gt 0 ] && skip=" · 건너뜀 $skipped"
		echo "dev test: 통과 — 테스트 ${total}개${skip} · $(secs "$t0")"
		;;
	*)
		[ "$rc" -eq 0 ] || fail_out 1 "$(tail_lines "$log" 10)"
		echo "dev test: 통과 — $(tail_lines "$log" 1 | sed 's/^  //')"
		;;
	esac
	exit 0
}

# ---- 서비스 ----
container_name() { echo "dev-$(basename "$root" | tr -c 'A-Za-z0-9_.\n-' '-')-$1"; }
services_on() { ! none "$(c SERVICES)" || ! none "$(c EXTRA_CONTAINERS)"; }

service_states() { # "이름=상태" 목록
	local s id st spec
	if ! none "$(c SERVICES)"; then
		for s in $(c SERVICES); do
			id="$(docker compose ps -q "$s" 2>/dev/null | head -1)"
			st="없음"; [ -n "$id" ] && st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null)"
			printf '%s=%s ' "$s" "$st"
		done
	fi
	if ! none "$(c EXTRA_CONTAINERS)"; then
		for spec in $(c EXTRA_CONTAINERS); do
			s="${spec%%,*}"
			st="$(docker inspect -f '{{.State.Status}}' "$(container_name "$s")" 2>/dev/null || echo 없음)"
			printf '%s=%s ' "$s" "$st"
		done
	fi
}

start_services() {
	services_on || return 0
	docker info >/dev/null 2>&1 || env_missing "컨테이너 런타임에 연결할 수 없음"
	local slog="$log_dir/services.log" spec name image port cname
	: >"$slog"
	if ! none "$(c SERVICES)"; then
		guard_check "docker compose up -d $(c SERVICES)"
		# shellcheck disable=SC2086
		docker compose up -d $(c SERVICES) >>"$slog" 2>&1 || { log="$slog"; fail_out 1 "$(tail_lines "$slog" 10)"; }
	fi
	if ! none "$(c EXTRA_CONTAINERS)"; then
		for spec in $(c EXTRA_CONTAINERS); do
			IFS=, read -r name image port <<<"$spec"
			[ -n "$name" ] && [ -n "$image" ] && [[ "$port" =~ ^[0-9]+$ ]] || env_missing "EXTRA_CONTAINERS 형식이 이름,이미지,포트가 아님 ($spec)"
			cname="$(container_name "$name")"
			# 예전 설정으로 만든 컨테이너면(이미지·포트가 바뀜) 지우고 새로 만든다 — 라벨에 만들 때의 설정을 적어 둔다
			if [ -n "$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null)" ] \
				&& [ "$(docker inspect -f '{{index .Config.Labels "dev.spec"}}' "$cname" 2>/dev/null)" != "$spec" ]; then
				guard_check "docker rm -f $cname"
				docker rm -f "$cname" >>"$slog" 2>&1
			fi
			case "$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null)" in
			running) ;;
			'') guard_check "docker run -d --name $cname --label dev.spec=$spec -p $port:$port $image"
				docker run -d --name "$cname" --label "dev.spec=$spec" -p "$port:$port" "$image" >>"$slog" 2>&1 || { log="$slog"; fail_out 1 "$(tail_lines "$slog" 10)"; } ;;
			*) guard_check "docker start $cname"
				docker start "$cname" >>"$slog" 2>&1 || { log="$slog"; fail_out 1 "$(tail_lines "$slog" 10)"; } ;;
			esac
		done
	fi
	local wait="$(c WAIT_SERVICES)"; num "$wait" WAIT_SERVICES
	local t0 states pending
	t0=$(date +%s)
	while :; do
		states="$(service_states)"; pending=""
		for st in $states; do
			case "${st#*=}" in healthy | running) ;; *) pending="$pending $st" ;; esac
		done
		[ -z "$pending" ] && break
		if [ $(($(date +%s) - t0)) -ge "$wait" ]; then
			log="$slog"; stop_services; fail_out 1 "  서비스가 ${wait}초 안에 준비되지 않음:$pending"
		fi
		sleep 1
	done
}

stop_services() {
	services_on || return 0
	docker info >/dev/null 2>&1 || return 0
	local spec
	if ! none "$(c SERVICES)"; then
		guard_check "docker compose stop $(c SERVICES)"
		# shellcheck disable=SC2086
		docker compose stop $(c SERVICES) >>"$log" 2>&1
	fi
	if ! none "$(c EXTRA_CONTAINERS)"; then
		for spec in $(c EXTRA_CONTAINERS); do docker stop "$(container_name "${spec%%,*}")" >>"$log" 2>&1; done
	fi
}

# ---- 앱 ----
app_pid() { # 살아 있는 앱 PID, 없으면 빈 값 (죽은 pid 파일은 지운다)
	[ -f "$pidfile" ] || return 0
	local p; p="$(cat "$pidfile")"
	if [[ "$p" =~ ^[0-9]+$ ]] && kill -0 -- "-$p" 2>/dev/null; then echo "$p"; else rm -f "$pidfile"; fi
}

health_code() { python3 - "$1" <<'PY'
import sys, urllib.request, urllib.error
try:
    print(urllib.request.urlopen(sys.argv[1], timeout=2).status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print(0)
PY
}

stop_app() { # stop_app <pid> — 그룹에 TERM, 최대 30초 뒤 KILL
	local p="$1" i
	kill -TERM -- "-$p" 2>/dev/null
	for i in $(seq 1 30); do kill -0 -- "-$p" 2>/dev/null || break; sleep 1; done
	kill -0 -- "-$p" 2>/dev/null && kill -KILL -- "-$p" 2>/dev/null
	rm -f "$pidfile"
}

ERR_PAT='ERROR|FATAL|Exception|Caused by|[Ee]rror:'

app_needs() {
	num "$(c APP_PORT)" APP_PORT; num "$(c WAIT_HEALTH)" WAIT_HEALTH
	none "$(c HEALTH_URL)" && env_missing "START_CMD가 있으면 HEALTH_URL이 필요함"
	return 0
}

do_start() {
	local cmd="$(c START_CMD)"
	none "$cmd" && { echo "dev start: $cmd"; exit 0; }
	app_needs
	local p; p="$(app_pid)"
	[ -n "$p" ] && { echo "dev start: 통과 — 이미 실행 중 (PID $p)"; exit 0; }
	port_open "$(c APP_PORT)" && env_missing "포트 $(c APP_PORT)을 다른 프로세스가 사용 중"
	guard_check "$cmd"
	local t0; t0=$(date +%s)
	start_services
	local applog="$log_dir/app.log"
	set -m   # 앱을 새 프로세스 그룹으로 — stop이 그 그룹만 끈다
	bash -c "$cmd" >"$applog" 2>&1 </dev/null &
	p=$!
	# 작업 표에서 뺀다 — 남겨 두면 stop_app으로 끈 뒤 bash 3.2가 "Terminated: 15" 줄을 출력 맨 앞에 끼워 넣는다
	disown 2>/dev/null || true
	set +m
	echo "$p" >"$pidfile"
	log="$applog"
	local code=0
	while :; do
		if ! kill -0 -- "-$p" 2>/dev/null; then
			rm -f "$pidfile"; stop_services
			fail_out 1 "  앱 프로세스가 먼저 종료됨
$(tail_lines "$applog" 8 "$ERR_PAT")"
		fi
		code="$(health_code "$(c HEALTH_URL)")"
		[[ "$code" == 2* ]] && break
		if [ $(($(date +%s) - t0)) -ge "$(c WAIT_HEALTH)" ]; then
			stop_app "$p"; stop_services
			fail_out 1 "  헬스 응답 없음: $(c HEALTH_URL) (마지막 상태 $code, $(c WAIT_HEALTH)초)
$(tail_lines "$applog" 8 "$ERR_PAT")"
		fi
		sleep 1
	done
	local svc=""; services_on && svc="서비스 $(service_states | tr -s ' ' | sed 's/ $//') · "
	echo "dev start: 통과 — ${svc}앱 PID $p · 헬스 $code · $(secs "$t0")"
	exit 0
}

do_stop() {
	none "$(c START_CMD)" && { echo "dev stop: $(c START_CMD)"; exit 0; }
	: >"$log"
	local p msg; p="$(app_pid)"
	if [ -n "$p" ]; then stop_app "$p"; msg="앱 PID $p 종료"; else msg="실행 중인 앱 없음"; fi
	stop_services
	if [[ "$(c APP_PORT)" =~ ^[0-9]+$ ]] && port_open "$(c APP_PORT)"; then
		fail_out 1 "  포트 $(c APP_PORT)이 아직 열려 있음 — 앱이 다른 프로세스 그룹으로 떨어져 나갔을 수 있다(START_CMD가 백그라운드 데몬을 띄우는지 확인)"
	fi
	services_on && msg="$msg · 서비스 정지"
	echo "dev stop: 통과 — $msg"
	exit 0
}

do_status() {
	none "$(c START_CMD)" && { echo "dev status: $(c START_CMD)"; exit 0; }
	local p svc=""; p="$(app_pid)"
	services_on && docker info >/dev/null 2>&1 && svc=" · 서비스 $(service_states | sed 's/ $//')"
	if [ -n "$p" ]; then
		echo "dev status: 실행 중 (PID $p) · 헬스 $(health_code "$(c HEALTH_URL)")$svc"
	else
		echo "dev status: 꺼짐$svc"
	fi
	exit 0
}

do_logs() {
	local n="${1:-20}" applog="$log_dir/app.log"
	[[ "$n" =~ ^[0-9]+$ ]] || env_missing "logs 인자가 숫자가 아님 ($n)"
	[ -f "$applog" ] || { echo "dev logs: 없음 — 앱 로그가 아직 없음(start를 실행한 적 없음)"; exit 0; }
	local errs; errs="$(tail_lines "$applog" 5 "$ERR_PAT")"
	echo "dev logs: $applog · $(grep -c '' "$applog")줄 · 에러 줄 $(grep -cE "$ERR_PAT" "$applog")개"
	[ -n "$errs" ] && { echo "  [에러 줄 마지막 5개]"; printf '%s\n' "$errs"; }
	echo "  [마지막 ${n}줄]"
	tail_lines "$applog" "$n"
	exit 0
}

case "$verb" in
build) run_simple BUILD_CMD ;;
fmt) run_simple FMT_CMD ;;
deps) run_simple DEPS_CMD ;;
test) run_test "$@" ;;
start) do_start ;;
stop) do_stop ;;
status) do_status ;;
logs) do_logs "$@" ;;
esac
