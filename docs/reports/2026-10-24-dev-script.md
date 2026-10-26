# 빌드·실행 환경 분리 — 작업 보고서

프로젝트의 빌드·테스트·실행을 모든 프로젝트가 같이 쓰는 실행 엔진 `scripts/dev.sh`와 프로젝트별 설정 `scripts/dev.conf`로 나눴다. TripFit-server 클론에서 테스트·빌드·기동·종료를 실제로 돌려 확인했고, 이 저장소의 테스트 명령도 `scripts/dev.sh test`로 바꿨다. 스펙은 `docs/specs/cross-cutting/dev-script.md`다.

## 무엇을 했나

- **실행 엔진** `scripts/dev.sh` — 동사 8개(`build`·`test`·`fmt`·`deps`·`start`·`stop`·`status`·`logs`), 종료 코드 3개(0 성공 · 1 실패 · 2 환경 없음), 출력 형식(성공 한 줄 · 실패는 원인 몇 줄 + 전체 로그 경로). 설정 명령은 실행 전에 위험한 명령 차단 훅으로 판정받는다. 기동한 앱은 새 프로세스 그룹으로 띄우고 그 번호로만 끈다
- **엔진 테스트** `scripts/test-dev.sh` — 가짜 명령으로 23개 케이스. `scripts/verify.sh`의 4번째 단계이고, `pre-commit`이 `dev.sh`·`test-dev.sh`·`dev.conf`가 stage됐을 때 돌린다
- **설정 파일** — 이 저장소 `scripts/dev.conf`(테스트만 있음) · 씨앗 `examples/seeds/java-spring/dev.conf`(TripFit에서 확인한 값) · `examples/seeds/_template/dev.conf`(자리표시자)
- **완료 검사 훅** `deny-unverified-completion.sh` — `TEST_CMD`를 `scripts/dev.sh test`로 바꾸고, 명령의 모든 단어가 그대로 나와야 테스트 실행으로 친다. 데이터로 넘긴 heredoc 본문은 명령으로 보지 않는다(here-string `<<<`·닫는 줄 없는 경우·셸에 넘긴 본문은 제외). 케이스 8개를 먼저 추가했다(`scripts/hook-cases.txt`·`scripts/hook-fixtures/`)
- **규칙·스킬·문서** — `core-workflow.md` 구현 절 한 줄 · `harness-map.md` 테스트 슬롯 값과 명령 슬롯 규칙 · `debug`·`preflight`·`adopt` 스킬 · `AGENTS.md`·`AGENTS.template.md`·`README.md` · 씨앗 README 3개 · `docs/harness/README.md` 현재동작 요약 · `check-portability.sh` 검사 대상에 `dev.sh` 추가 · `pre-commit` 포맷 주석 · `.gitignore`(`.dev/`)

## 결정

| 결정 | 근거 | 대안 |
|------|------|------|
| 실행 순서는 core `dev.sh`, 프로젝트 값은 `dev.conf` | 사용자 목표 "빌드·실행 환경도 프로젝트별로 분리". 엔진을 고치면 모든 프로젝트에 반영된다 | 스택별 스크립트 씨앗 — 복사한 뒤 프로젝트마다 갈라진다 |
| `dev.conf`를 source하지 않고 줄 단위로 읽음 | 설정 파일에 로직이 들어가지 않아 값이 적힌 그대로 쓰인다 | `source` — 조건문·치환이 들어갈 수 있다 |
| 설정 명령을 위험 명령 훅으로 사전 판정 | 설정 파일의 명령은 엔진 안에서 실행되어 PreToolUse 훅이 보지 못한다 | 판정 없음 — 설정 파일 한 줄로 훅을 거치지 않게 된다 |
| 기동 판정은 Redis까지 띄운 뒤 전체 헬스 | 사용자 승인(스펙 결정 8). `readiness`만 보면 Redis 없이 성공으로 나온다 | `/actuator/health/readiness` |
| 연관 배열 대신 `CONF_<키>` 변수 | macOS 기본 bash 3.2에 연관 배열이 없다 | `declare -A` |
| 포트 확인은 python으로 `localhost` 연결 | `127.0.0.1` 표기가 이식성 검사에서 버전 번호로 잡혔고, `localhost`는 IPv4·IPv6를 모두 시도한다 | bash `/dev/tcp` |
| 시작 명령은 `--no-daemon` | Gradle 데몬이 앱을 띄우면 앱이 엔진의 프로세스 그룹 밖에 남는다 | 데몬 사용 |

## 검증

TripFit-server 클론(`Central-MakeUs/TripFit-server` 커밋 `e2a2ee7`)에 엔진과 씨앗 설정을 복사해 돌렸다. 클론에 `.env`가 없어 `RUN_ENV`에만 TripFit `application-local.yml`의 로컬 기본값(`MYSQL_ROOT_PASSWORD=tripfit MYSQL_DATABASE=tripfit`)을 넣었다.

| 검증 | 실행한 명령 | 결과 |
|------|-------------|------|
| 전체 테스트 (실패 1개 있음) | `scripts/dev.sh test` | exit 1 · 3줄 363B — 실패한 테스트 이름과 데드락 원인. 기존 방식은 콘솔 5,656B + 원인을 보려고 연 XML(테스트 결과 파일) 13,745B = 19,401B (약 98% 감소) |
| 테스트 일부 | `scripts/dev.sh test --tests …ArchitectureTest` | exit 0 · 한 줄 `테스트 9개 · 19초` |
| 빌드 | `scripts/dev.sh build` | 첫 실행은 포맷 도구 파일 다운로드 실패로 exit 1(아래 "검증하지 못한 것"), 다시 실행해 exit 0 · 한 줄 |
| 기동 | `scripts/dev.sh start` | exit 0 · 한 줄 — MySQL healthy · Redis running · 헬스 200 · 27초 |
| 두 번 기동 · 상태 · 로그 | `start` · `status` · `logs 5` | `이미 실행 중 (PID n)` · 한 줄 · 에러 줄 0개 + 마지막 5줄 |
| 종료 · 두 번 종료 | `stop` · `stop` | exit 0 · 포트 8080 닫힘 · 남은 Gradle·앱 프로세스 없음 |
| 반복 | `start → stop` 3회 | 6번 모두 exit 0 · 한 줄 · 같은 형식 |
| 포트 점유 | 8080에 다른 서버를 띄우고 `start` | exit 2 `포트 8080을 다른 프로세스가 사용 중` |
| 헬스 시간 초과 | `WAIT_HEALTH=5` 설정 복사본으로 `start` | exit 1 · 앱 종료 · pid 파일 지움 · 포트 닫힘 |
| 컨테이너 데몬 꺼짐 | 데몬을 끄고 `start` | exit 2 `컨테이너 런타임에 연결할 수 없음` |
| TripFit 무변경 | `git status` · `git log -1` | 미추적 파일 2개(`scripts/dev.sh`·`dev.conf`)뿐, 커밋 `e2a2ee7` 그대로 |
| 반복 테스트 | `--rerun` 없는 설정과 있는 설정으로 `test --tests …` 두 번씩 | 없으면 두 번 다 `실패 1 — 이번 실행에서 쓴 결과 파일이 없음`(Gradle이 건너뜀), 있으면 두 번 다 `통과 — 테스트 9개` |
| 설정이 바뀐 컨테이너 | 라벨 없이 만들어진 Redis 컨테이너가 있는 상태에서 `start` | 지우고 `dev.spec` 라벨을 붙여 새로 만든 뒤 헬스 200 |
| 실패한 start 정리 | `WAIT_HEALTH=3`으로 `start` | exit 1 · 앱과 MySQL·Redis 컨테이너 모두 정지 · pid 파일 없음 |
| 이 저장소 | `scripts/dev.sh test` | `dev test: 통과 — verify: 전부 통과` — 부품 계약 위반 0 · 훅 케이스 110/110 · 문서 오류 0 · 엔진 케이스 23/23 · always-load 27,801B / 28,000B |

별도 컨텍스트 코드 리뷰(`code-review`, medium)가 10건을 냈고 모두 확인 후 고쳤다.

| 리뷰 지적 | 조치 |
|---|---|
| heredoc 판정이 here-string(`<<<`)과 따옴표 속 `<<`에도 걸려 뒤 줄의 편집을 놓침 | `<<<` 제외 · 닫는 줄이 있을 때만 본문 제외 · 케이스 추가 |
| `bash <<EOF`처럼 셸에 넘긴 본문의 편집을 놓침 | 셸·인터프리터에 넘긴 본문은 남김 · 케이스 추가 |
| `scripts/dev.sh test 2>/dev/null`을 실행으로 안 침 | 명령 뒤 리다이렉션 허용 · 케이스 추가 |
| 결과 파일이 하나도 없어도 `통과 — 테스트 0개` | 실패로 보고 · 엔진 케이스 추가 · 씨앗에 `--rerun` |
| 실패한 start가 서비스를 남김 | 앱과 서비스를 함께 정지 |
| 멈춘 추가 컨테이너를 설정 비교·위험 검사 없이 `docker start` | 만들 때의 설정을 라벨로 남겨 다르면 새로 만들고, `docker start`도 위험 검사 |
| `pre-commit`이 엔진 테스트를 안 돌림 | stage된 파일에 따라 `test-dev.sh` 실행 |
| `.claude/rules/README.md`·`docs/harness/README.md`·`harness-engineering.md`·`how-to-doc.md`가 아직 `verify.sh`를 검증 명령으로 안내 | `scripts/dev.sh test`로 고침 |

TripFit 검증 중 엔진 버그 2개를 찾아 고쳤다. 컨테이너 이름을 만드는 `tr` 문자 목록의 `-` 위치가 틀려 오류 문구가 출력에 섞였고, 헬스 시간 초과 출력에 빈 줄이 들어갔다. 둘 다 컨테이너·실제 앱이 있어야 드러나서 엔진 테스트로는 잡히지 않았다.

## TDD 증거

| 지점 (스펙 항목) | 테스트 | 작성자 | RED 사유 | GREEN | 되돌림(C) |
|---|---|---|---|---|---|
| 완료 검사 훅 — 여러 단어 `TEST_CMD` | `hook-cases.txt`의 `stop-devsh-build-only` · `stop-devsh-test-partial` · `stop-old-test-cmd` | 구현 에이전트 | 상수만 바꾼 상태에서 `build`·`test --tests`가 exit 0(파일 이름 `dev.sh`만 비교) | 단어 전체 비교 후 exit 2 | — |
| 완료 검사 훅 — heredoc 오판 | `stop-heredoc-commit-after-test` · `stop-heredoc-write-no-test` | 구현 에이전트 | 커밋 메시지의 `<…@…>`를 쓰기로 보고 exit 2 | heredoc 본문 제외 후 exit 0, `cat > 파일 <<EOF`는 여전히 exit 2 | — |
| 엔진 — 종료 코드·출력 형식·`stop` | `scripts/test-dev.sh` 21개 | 구현 에이전트 | `dev.sh`가 없어 전부 실패(exit 127) | 21/21 | — |
| 엔진 — 위험 명령 사전 검사 | `test-dev.sh` "설정 명령이 위험 명령 패턴에 걸림" | 구현 에이전트 | 위와 같음 | 통과. 검사 함수를 임시로 끈 엔진에서 이 케이스만 실패하는 것을 확인 | — |
| 엔진 — 채우지 않은 `{…}` 값 | `test-dev.sh` "채우지 않은 자리표시자" | 구현 에이전트 | exit 1(빈 명령이 실행됨) | exit 2 | — |
| 리뷰 — heredoc 판정 보완 | `stop-herestring-then-edit` · `stop-heredoc-shell-edit` · `stop-test-stderr-devnull` | 구현 에이전트 | 각각 exit 0 · 0 · 2(기대 2 · 2 · 0) | 기대대로 | — |
| 리뷰 — 결과 파일 없음 | `test-dev.sh` "test 결과 파일 없음" | 구현 에이전트 | `통과 — 테스트 0개` exit 0 | `실패 1` exit 1 | — |

## 검증하지 못한 것

| 무엇 | 왜 못 했나 | 누가·언제 확인하나 |
|------|-----------|-------------------|
| macOS 기본 bash 3.2에서의 실행 | 이 환경(Linux)에 bash 3.2가 없다. 연관 배열은 걷어냈지만 실제로 돌려 보지 않았다 | macOS에서 하네스를 붙일 때 `scripts/test-dev.sh` 한 번 |
| `.env`가 있는 실제 개발 환경의 TripFit 기동 | 클론에 `.env`가 없어 `RUN_ENV`로 로컬 기본값을 넣어 돌렸다. 씨앗은 `RUN_ENV=없음 — 값은 .env` | 사용자 로컬에서 `scripts/dev.sh start` 한 번 |
| 빌드 첫 실행의 실패 원인 | 포맷 도구(spotless)가 처음 받는 파일 하나를 받지 못했다. 같은 명령에 상세 로그를 켜 다시 돌리자 성공했고, 프록시 차단 기록도 없었다. 이 클라우드 세션의 다운로드 문제로 보지만 원인 파일은 확정하지 못했다 | 다시 나면 `build/dev/build.log`에서 실패한 주소를 확인 |
| 도입 전후 토큰·도구 호출 수 비교 | 스펙에서 Nice to Have로 미뤘다(결정 10). 위 바이트 수는 같은 상황의 출력 크기 비교일 뿐 세션 전체 측정이 아니다 | 이력서에 숫자로 쓰기 전 별도 작업 |
| Node·Python 등 다른 스택 | TripFit(Java)과 이 저장소만 돌렸다 | 그 스택에 하네스를 붙일 때 `adopt` 체크리스트의 `dev.sh test`·`build` 실행 |
| 앱이 여러 개인 저장소 | `dev.conf` 하나에 앱 하나만 적을 수 있다 | 필요해질 때 엔진 확장 |

## 남은 것

- TripFit의 `NotificationLockOrderIntegrationTest`가 실행마다 데드락 수가 다르게(2건 → 1건) 실패한다. 이 작업과 관계없는 TripFit 쪽 문제다
- `TEST_CMD`가 모든 프로젝트에서 `scripts/dev.sh test`로 같아졌다. 명령 슬롯 4개를 지우고 core 문장에 직접 쓰는 정리는 스펙 Out of Scope로 남겼다
