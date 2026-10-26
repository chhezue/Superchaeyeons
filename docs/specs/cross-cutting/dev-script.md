# 빌드·실행 환경 분리 — `dev.sh`·`dev.conf`

> 상태: Implemented (2026-10-24 승인·구현)
> MVP: In scope
> 관련 BR: N/A

## 목표

하네스를 붙인 프로젝트의 빌드·테스트·실행 작업을 두 부분으로 나눈다. 실행 로직(`scripts/dev.sh`)은 모든 프로젝트가 같은 파일을 쓰는 core로 배포한다. 프로젝트의 환경 정보(명령, 의존 서비스, 헬스 주소, 테스트 결과 경로)는 프로젝트마다 갖는 설정 파일(`scripts/dev.conf`)로 분리한다. 그러면 AI가 세션마다 명령을 새로 조합하지 않아서, 같은 입력이면 같은 명령이 같은 순서로 실행된다. 출력은 성공하면 한 줄, 실패하면 원인 몇 줄로 줄여서 대화에 들어가는 토큰도 줄인다. 실행 로직을 개선하면 하네스를 붙인 모든 프로젝트에 같이 반영된다.

## 배경

- 2026-10-23 이력서 피드백: "프로젝트별 수행하는 동작들을 별도로 스크립트화해 토큰 비용 감소와 결정적 동작으로 개선 (빌드·실행을 `start.sh`로 관리하는 등)". 사용자 목표는 "실행 환경·빌드 환경도 경로·언어·정책처럼 프로젝트별로 분리"다
- **지금 있는 것:** 하네스 자체 검사는 `scripts/verify.sh`로 묶여 있고 출력도 줄인다. 2026-10-23 실측에서 모두 통과할 때 기본 출력은 307B, 전체 출력(`VERIFY_VERBOSE=1`)은 21,017B였다. 경로·언어·정책은 core 규칙과 `harness-map.md`(값)로 이미 나뉘어 있다
- **없는 것:** 프로젝트 명령은 `harness-map.md`에 문자열로만 적혀 있다. 실행·종료·로그는 적을 자리도 없다. 여러 단계로 된 작업(DB 컨테이너 기동 → 대기 → 앱 기동 → 헬스 체크)은 AI가 매번 새로 짠다
- **TripFit-server 실측 (2026-10-23, `Central-MakeUs/TripFit-server` 커밋 `e2a2ee7`, 읽기 전용 클론):**

| 항목 | 실측 | `dev.sh`가 맡을 것 |
|---|---|---|
| `./gradlew test` | 테스트 543개 중 1개 실패, 2분 56초 걸림. 콘솔 출력(5,656B)에는 원인 없이 `AssertionError at …:175`만 나온다. 원인은 XML(태그로 구조를 적는 텍스트 형식) 결과 파일에 있다(그 클래스 하나가 13,745B, 전체 4.9MB) | 실패한 테스트 이름과 원인 메시지를 결과 파일에서 뽑아 몇 줄로 보여 준다 |
| 로컬 기동 | `docker compose up -d`는 MySQL만 띄운다. 그 상태에서 `bootRun`을 하면 앱은 9초 만에 뜨지만, Redis가 없어서 `/actuator/health`는 계속 503(`DOWN`)이다. `readiness`는 `UP`이다 | 의존 서비스를 띄우는 것과 헬스 판정 기준을 설정 파일에 고정한다 |
| 기동 로그 | 3분 동안 424,079B(4,590줄)가 쌓였다. Redis 재연결 실패가 243회, SQL 출력이 52회다 | `logs`는 에러 줄과 마지막 N줄만 보여 준다 |
| 종료 | 프로세스 이름 패턴으로 `pkill`을 하자 그 명령을 실행한 셸도 패턴에 걸려 같이 종료됐다(exit 144) | 기동할 때 PID(프로세스 번호)를 파일에 남기고, 그 번호로만 종료한다 |
| 의존성 다운로드 | 첫 실행에서 Maven Central이 429(요청 과다)를 반환했다. 간격을 두고 다시 시도해 4회 만에 받았다 | 범위 밖이다. 환경 문제로 보고 "검증하지 못한 것"에 남긴다 |

- 실패한 테스트(`NotificationLockOrderIntegrationTest.activationAndOwnerWithdrawal_neverDeadlock`)는 실제 MySQL에서 데드락이 2건 났다는 TripFit 코드 쪽 문제다. 이 스펙과 관계없어 기록만 한다
- **하네스 쪽 결함:** `deny-unverified-completion.sh`는 `TEST_CMD`의 첫 단어에서 파일 이름만 떼어 비교한다(`test_key`). `TEST_CMD`가 `scripts/dev.sh test`가 되면 `scripts/dev.sh build`나 `scripts/dev.sh test --tests 하나`를 실행해도 전체 테스트를 돌린 것으로 판정된다
- **새로 생기는 위험:** `dev.conf`에 적힌 명령은 `dev.sh` 안에서 실행되므로 `deny-dangerous-bash.sh`가 보지 못한다(훅은 `scripts/dev.sh build`라는 문자열만 본다). 설정 파일에 위험한 명령을 적으면 훅을 거치지 않고 실행된다
- 관련 문서: `docs/specs/cross-cutting/harness-slot-system-v2.md` "부품성 원칙" · `examples/seeds/README.md` "씨앗을 새로 올리는 조건"

## 결정 기록

| # | 질문 | 결정 |
|---|---|---|
| 1 | 진입점 | `scripts/dev.sh <동사>` 하나다. 2026-10-23 사용자가 이름 결정을 위임했다 |
| 2 | 씨앗 근거 | TripFit-server에서 실측·검증한 결과를 `java-spring` 씨앗으로 올린다(A안). TripFit 저장소에는 커밋하지 않는다. 2026-10-23 사용자 결정 |
| 3 | 실행 로직과 환경 정보 | 분리한다. `dev.sh`는 core로 배포하고 프로젝트는 고치지 않는다. 프로젝트 고유 값은 전부 `dev.conf`에 둔다. 씨앗은 스크립트가 아니라 `dev.conf`다. 2026-10-23 사용자 결정 |
| 4 | 설정 파일 형식 | 한 줄에 `KEY=VALUE` 하나다. `dev.sh`는 이 파일을 `source`하지 않고 줄 단위로 읽는다. 그래서 설정 파일 안에 조건문·변수 치환 같은 로직을 넣을 수 없고, 값은 읽은 그대로 쓰인다. 부품성 원칙 1(bash 하나 + 데이터 파일 하나)과 맞는다 |
| 5 | 명령 슬롯 | 슬롯 이름(`{{테스트 명령}}`·`{{빌드 명령}}`·`{{포맷 명령}}`·`{{의존성 조회}}`)은 그대로 둔다. 대신 모든 프로젝트에서 값이 `scripts/dev.sh <동사>`가 된다. 프로젝트마다 다른 실제 명령은 `dev.conf`로 옮긴다. 슬롯을 지우면 core 17개 파일의 문장을 바꿔야 해서, 이번에는 값만 바꾼다. 실행용 슬롯은 추가하지 않는다(`dev.sh start`가 모든 프로젝트에서 같기 때문이다) |
| 6 | 이 저장소에도 적용 | 적용한다. (2026-10-26 amend: `scripts/dev.conf`는 배달본이라 빈칸으로 두고 이 저장소 값은 배달되지 않는 루트 `dev.conf`로 옮겼다. `dev.sh`는 `DEV_CONF` → 루트 `dev.conf` → `scripts/dev.conf` 순으로 찾는다. 사용자 결정) 이 저장소 설정의 `TEST_CMD`를 `scripts/verify.sh`로 하고, 나머지 동사는 "없음 — 이유"로 둔다. `{{테스트 명령}}`·훅 `TEST_CMD`는 `scripts/dev.sh test`가 된다. 이 저장소가 매 턴 `dev.sh`를 실제로 쓰므로, 엔진이 깨지면 바로 드러난다 |
| 7 | 설정 명령의 위험 검사 | `dev.sh`는 `dev.conf`의 명령을 실행하기 전에 그 문자열을 `deny-dangerous-bash.sh`에 넣어 판정을 받는다. 차단되면 실행하지 않고 exit 2로 끝낸다. 패턴 목록은 훅 하나에만 두고 복사하지 않는다 |
| 8 | 씨앗 기본값 3개 | 권장안 그대로: 의존 서비스(Redis 포함)를 모두 띄우고 전체 헬스 URL로 판정 · 로그 `build/dev/` · 대기 서비스 60초·앱 120초. 2026-10-24 사용자 승인 |
| 9 | 커밋 서명 오판 | 완료 검사 훅이 heredoc 본문의 `>`(커밋 서명의 이메일 꺾쇠)를 파일 쓰기로 오판한다(2026-10-23 실제 발생). 같은 훅을 고치는 이번 변경에 픽스처와 수정을 넣는다 |
| 10 | 효과 측정 | 이번 구현에서 하지 않는다(Nice to Have 유지). 2026-10-24 |

## 요구사항

### Must Have

- [x] **`scripts/dev.sh` (core)** — 스택에 묶이지 않는 실행 엔진이다. 동사·종료 코드·출력 형식·설정 키 목록의 SSOT는 이 파일 머리다
  - 동사: `build` · `test [인자…]` · `fmt` · `deps` · `start` · `stop` · `status` · `logs [N]`. 설정 값이 `없음 — 이유`인 동사는 그 이유를 한 줄로 출력하고 exit 0으로 끝낸다
  - 종료 코드: `0` 성공 · `1` 실패 · `2` 환경 없음(설정 파일 없음 · 필수 키 없음 · 컨테이너 런타임 없음 · 포트 점유 · 위험 명령 차단). `2`는 `preflight`의 "검증하지 못한 것"으로 넘긴다
  - 출력: 성공하면 `dev <동사>: 통과 — <요약>` 한 줄이다. 실패하면 `dev <동사>: 실패 <개수>` 한 줄, 실패 항목마다 이름과 원인 한 줄(최대 10개, 줄당 최대 300자), 마지막에 전체 로그 경로를 쓴다. 실패 줄은 `deny-unverified-completion.sh`의 `FAILED` 정규식에 걸리고, 성공 줄은 걸리지 않는다
  - 테스트 요약: `TEST_REPORT` 값이 `junit:<경로 패턴>`이면 JUnit XML(여러 언어의 테스트 도구가 내보내는 공통 결과 형식)을 `python3`으로 읽어 실패 항목을 만든다. `last-line`이면 명령 출력의 마지막 줄을 요약으로 쓴다
  - 전체 로그: 동사마다 `<LOG_DIR>/<동사>.log`에 덮어쓴다. 에이전트는 필요할 때만 이 파일을 grep한다
  - `start`는 여러 번 실행해도 결과가 같다: 이미 떠 있으면 PID만 보여 주고 exit 0으로 끝낸다. 의존 서비스가 healthy가 될 때까지 기다린 뒤 앱을 백그라운드로 띄우고, 헬스 URL이 성공할 때까지 `WAIT_HEALTH`초 동안 기다린다. 시간 안에 성공하지 못하면 앱을 종료하고, exit 1과 함께 로그의 에러 줄을 보여 준다
  - `stop`은 PID 파일의 번호로만 종료한다. 이름 패턴은 쓰지 않는다. 떠 있는 것이 없으면 exit 0으로 끝낸다
  - 결정 7의 위험 명령 사전 검사
- [x] **엔진 테스트** — `scripts/test-dev.sh`를 둔다. 가짜 명령(성공·실패하는 작은 셸 스크립트, 가짜 JUnit XML, `python3 -m http.server`로 띄운 헬스 응답)을 가리키는 임시 `dev.conf`로 동사·종료 코드·출력 형식을 판정한다. `scripts/verify.sh`의 4번째 단계로 넣는다
- [x] **이 저장소의 `scripts/dev.conf`** — 결정 6대로 둔다. `LOG_DIR`은 `.dev/`(`.gitignore`에 추가)
- [x] **`java-spring` 씨앗** — `examples/seeds/java-spring/dev.conf`. 키마다 한 줄 주석으로 무엇을 적는지 설명한다. 도메인·프로젝트 이름은 넣지 않는다
- [x] **`_template` 씨앗** — `examples/seeds/_template/dev.conf`. 키 목록과 `{…}` 자리표시자만 둔다(구현 시 추가: `dev.sh`는 `{…}` 값이 남아 있으면 exit 2로 멈춘다 — 빈 값이면 빈 명령이 성공으로 지나가기 때문이다). 씨앗이 없는 스택은 `adopt`이 CI 워크플로의 실제 명령으로 채운다
- [x] **TripFit에서 검증** — core `dev.sh`와 `java-spring` 씨앗 `dev.conf`를 TripFit 클론에 복사하고, 아래 "검증 시나리오"를 모두 실행한다. TripFit에 커밋하지 않는다
- [x] **완료 검사 훅 수정** — `deny-unverified-completion.sh`가 파일 이름이 아니라 `TEST_CMD` 전체(모든 단어)와 비교하게 한다. `TEST_CMD` 뒤에 인자가 더 붙은 실행은 전체 테스트로 보지 않는다. 훅의 `TEST_CMD` 값은 `scripts/dev.sh test`로 바꾼다
- [x] **훅 케이스** — 위 훅 수정 전에 픽스처를 먼저 추가한다: `dev.sh test` 실행 → 통과 · `dev.sh build`만 실행 → 차단 · `dev.sh test --tests X`만 실행 → 차단 · 예전 값(`scripts/verify.sh`)만 실행 → 차단 · 테스트 뒤 heredoc 커밋 메시지에 `>`가 있음 → 통과(결정 9). 기존 픽스처의 테스트 실행 명령은 새 `TEST_CMD`로 바꾸고 판정(기대 종료 코드)은 그대로 둔다
- [x] **슬롯 값** — `harness-map.md` 명령 슬롯 4개의 값을 `scripts/dev.sh <동사>`로 바꾼다. "훅 상수와 짝" 목록의 설명도 그에 맞게 고친다. `scripts/git-hooks/pre-commit`의 `FORMAT_CMD` 짝 설명도 고친다(이 저장소는 포맷 명령이 없으므로 값은 비운 채로 둔다). (구현 시 정정: 이 저장소는 빌드·포맷·의존성 조회 슬롯을 `(없음)`으로 둔다 — `dev.conf`에도 값이 없기 때문이다. 규칙은 "값이 있으면 `scripts/dev.sh <동사>`"로 `harness-map.md` 명령 슬롯 절 머리에 적었다)
- [x] **이식성 검사 대상** — `check-portability.sh`의 배달물 목록에 `scripts/dev.sh`를 추가해서, core 엔진에 스택 이름·경로가 들어오지 않게 한다
- [x] **행동 규칙 한 줄** — `core-workflow.md` "구현" 절에 "빌드·테스트·실행은 `scripts/dev.sh`로만 부르고, 같은 일을 하는 명령을 직접 조합하지 않는다. 명령을 바꿀 일이 생기면 `dev.conf`를 고친다"를 넣는다. always-load 예산(현재 27,362B / 상한 28,000B) 안에서 넣는다
- [x] **`debug` 연결** — "로컬 재현" 단계에 "앱을 띄워 재현할 때는 `scripts/dev.sh start`, 끝나면 `stop`"을 넣는다
- [x] **`adopt` 연결** — 1단계 실측표의 CI 명령으로 `dev.conf`를 채운다(씨앗이 있으면 씨앗 `dev.conf`에서 시작한다). 산출물 체크리스트에 "`scripts/dev.sh test`·`build`의 종료 코드가 0 또는 1이다(2가 아니다)"를 추가한다
- [x] **문서 갱신** — `AGENTS.md`(배달물 표의 `scripts/` 행, "항상 `scripts/verify.sh`" 줄) · `AGENTS.template.md` Commands 블록 · `README.md` 배달물 표 · `examples/seeds/README.md`·`java-spring/README.md`(복사 표와 "씨앗 대조" 표에 `dev.conf` 행) · `docs/harness/README.md` "지금의 실제 동작"(완료 검사 훅 판정 변경을 쉬운 말로 설명 — STOP §3)

### Nice to Have

- [ ] **효과 측정 보고서** — 같은 과제("앱을 띄우고 헬스 체크까지", "실패한 테스트 원인 찾기")를 도입 전후로 N회씩 반복한다. 도구 호출 수, 대화에 들어간 출력 바이트, 세션마다 다르게 나온 명령의 종류 수를 비교한다. 형식은 `docs/reports/2026-10-16-harness-effect-measurement.md`를 따른다

### Out of Scope (이번 스펙에서 하지 않음)

- 실행 환경 자체의 재현(런타임 버전 고정, 개발용 컨테이너 이미지). 2026-10-23 사용자 확인 결과 이번 목표가 아니다
- `setup` 동사(`.env` 생성·비밀값 채우기). 비밀값을 다루는 일이라 스크립트로 자동화하지 않는다
- 명령 슬롯 4개를 지우고 core 문장에 `scripts/dev.sh`를 직접 쓰는 정리(결정 5). 값이 모든 프로젝트에서 같아진 뒤에 별도 작업으로 검토한다
- 스크립트를 거치지 않는 직접 명령(`./gradlew bootRun` 등)을 막는 훅. 정상적인 변형까지 막을 수 있다. 규칙 한 줄로 시작하고, 우회 사례가 반복되면 다시 검토한다(`docs/out-of-scope/README.md`에 행 추가)
- TripFit의 데드락 테스트 실패와 Maven Central 429 대응

## 테스트 먼저 지점

| Must 항목 | 테스트 먼저 | 근거 |
|---|---|---|
| 완료 검사 훅 수정 · 훅 케이스 | 테스트 먼저 | "테스트를 돌렸는가"를 판정하는 검증 게이트다. 비교 방식을 바꾸면 기존 픽스처 판정이 달라질 수 있다. `AGENTS.md`도 훅 수정 전에 케이스부터 넣으라고 한다 |
| `scripts/dev.sh` 엔진 — 종료 코드·출력 형식·`stop`·위험 명령 사전 검사 | 테스트 먼저 | 출력 형식이 `FAILED` 정규식과 맞지 않으면 완료 검사 훅이 실패를 놓친다. 위험 명령 사전 검사가 빠지면 설정 파일로 훅을 우회할 수 있다. 둘 다 가짜 명령으로 이 저장소에서 깨뜨려 볼 수 있다 |
| `start` 대기·헬스 판정 | 아님 | 실제 컨테이너와 앱이 있어야 의미가 있다. TripFit 실행(검증 시나리오)으로 확인한다. 엔진 테스트는 가짜 헬스 서버로 성공·시간 초과 두 경로만 본다 |
| 씨앗 `dev.conf` · 슬롯 값 · 규칙 · 스킬 · 문서 | 아님 | 데이터와 문서다. `scripts/verify.sh`(슬롯 대조, 구성 요소 목록 대조, 문서 스타일)와 TripFit 실행으로 확인한다 |

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 기존 훅 케이스(102개) 판정이 바뀌지 않는다 | `scripts/test-hooks.sh` |
| core(`dev.sh` 포함)에 스택·프로젝트 이름이 들어오지 않는다 | `scripts/check-portability.sh` 부품 계약 위반 0 |
| always-load 합계가 28,000B를 넘지 않는다 | `scripts/check-portability.sh` 예산 줄 |
| 이 저장소의 검사 결과가 `dev.sh`를 거쳐도 같다 | `scripts/dev.sh test`와 `scripts/verify.sh`의 종료 코드가 같다 |
| TripFit 저장소에 아무것도 커밋·푸시하지 않는다 | 클론의 `git status`에 미추적 파일만 있고 `git log`가 `e2a2ee7`에서 그대로다 |

## API / 인터페이스

API 없음. 인터페이스는 `dev.sh`의 동사·종료 코드·출력 형식과 `dev.conf`의 키 목록이고, `dev.sh` 머리가 SSOT다.

`dev.conf` 키 초안이다(TripFit 실측 기준, 구현 중 바뀌면 `dev.sh` 머리를 먼저 고친다).

| 키 | 뜻 | TripFit 값(씨앗) |
|---|---|---|
| `BUILD_CMD` | 빌드 | `./gradlew build -x test --no-daemon` |
| `TEST_CMD` | 전체 테스트(인자는 뒤에 붙는다) | `./gradlew test --no-daemon` |
| `TEST_REPORT` | 결과 형식과 위치 | `junit:build/test-results/test/*.xml` |
| `FMT_CMD` · `DEPS_CMD` | 포맷 · 의존성 조회 | `./gradlew spotlessApply --no-daemon` · `./gradlew dependencies --configuration runtimeClasspath --no-daemon` |
| `SERVICES` | 먼저 띄울 compose 서비스 | `mysql` |
| `EXTRA_CONTAINERS` | compose에 없는 의존 서비스(`이름,이미지,포트` — 이미지 이름에 `:`가 있어 쉼표로 나눈다) | `redis,redis:7-alpine,6379` |
| `START_CMD` · `APP_PORT` | 앱 기동 · 포트 | `./gradlew bootRun` · `8080` |
| `HEALTH_URL` | 기동 성공 판정 주소 | 아래 미결정 1에 따른다 |
| `WAIT_SERVICES` · `WAIT_HEALTH` | 대기 시간(초) | 아래 미결정 3에 따른다 |
| `LOG_DIR` | 전체 로그·PID 파일 위치 | 아래 미결정 2에 따른다 |

## 검증 시나리오

### 정상 (TripFit 클론)

- [x] `dev.sh test` → 현재 TripFit 상태라 exit 1. 출력은 15줄 이하이고, 실패한 테스트 이름과 데드락 원인 한 줄이 있다. 바이트 수를 기존 방식(콘솔 5,656B + 원인을 보려고 연 XML 13,745B)과 비교해 보고서에 적는다
- [x] `dev.sh test --tests <통과하는 클래스>` → exit 0, 한 줄
- [x] `dev.sh build` → exit 0, 한 줄
- [x] `dev.sh start` → 의존 서비스 healthy 확인 → 앱 헬스 성공 → exit 0. 다시 `start` → "이미 실행 중 (PID n)", exit 0
- [x] `dev.sh status` → 실행 여부·PID·헬스 결과 한 줄
- [x] `dev.sh logs` → 에러 줄과 마지막 N줄만, 그리고 전체 로그 경로
- [x] `dev.sh stop` → 포트가 닫히고 PID 파일이 지워진다. 다시 `stop` → exit 0
- [x] `start → stop`을 3회 반복해도 출력 형식과 종료 코드가 같다

### 엣지 · 실패

- [x] 컨테이너 런타임 데몬이 꺼져 있다 → `start`가 exit 2, "환경 없음" 한 줄
- [x] 앱 포트를 다른 프로세스가 이미 쓰고 있다 → `start`가 exit 2
- [x] 헬스가 대기 시간 안에 성공하지 못한다 → 앱을 종료하고 exit 1, 에러 줄을 보여 준다
- [x] `dev.conf`의 명령에 차단 패턴(예: 재귀 삭제)이 있다 → 실행하지 않고 exit 2 (엔진 테스트)
- [x] `dev.conf`가 없거나 필수 키가 없다 → exit 2 (엔진 테스트)

### 이 저장소

- [x] `scripts/dev.sh test` → `scripts/verify.sh`와 같은 종료 코드로 끝나고, 성공하면 한 줄을 출력한다
- [x] 여러 단어 `TEST_CMD` 픽스처 4개, heredoc 픽스처 2개(커밋 메시지 → 통과 · `cat > 파일 <<EOF` → 여전히 편집)와 기존 102개 케이스가 `scripts/test-hooks.sh`에서 모두 통과한다

## 완료 기준

- [x] `scripts/dev.sh test` 통과(이 저장소의 새 `{{테스트 명령}}`)
- [x] TripFit 검증 시나리오의 실행 결과(명령 → 종료 코드 → 출력 바이트)가 작업 보고서에 있다
- [x] `{{빌드 명령}}` — 이 저장소는 빌드가 없어 `dev.sh build`가 "없음"을 출력하고 exit 0
- [x] 작업 보고서 `docs/reports/2026-10-24-dev-script.md`(L 규모 — "검증하지 못한 것" 포함)

## 리스크·미결정

| 항목 | 상태 | 비고 |
|---|---|---|
| 1. `start`의 헬스 판정 기준 (씨앗 기본값) | 확정 — 결정 8 | **채택: 의존 서비스(Redis 포함)를 모두 띄우고, 전체 `/actuator/health`가 성공할 때 기동 성공으로 본다.** TripFit compose에는 Redis가 없으므로 `EXTRA_CONTAINERS`에 운영과 같은 이미지(`redis:7-alpine`)를 둔다. 대안: `/actuator/health/readiness`만 본다. Redis 없이도 성공하지만, 이후 AI가 전체 헬스 `DOWN`을 보고 원인을 다시 찾게 된다 |
| 2. 로그 디렉터리 (씨앗 기본값) | 확정 — 결정 8 | **채택: `build/dev/`** — Gradle 빌드 산출물 폴더라 TripFit `.gitignore`에 이미 있고, `clean`을 하면 같이 지워진다. 대안: `.dev/logs/`(TripFit에 `.dev/`가 있지만 세션 기록용이다) |
| 3. 대기 시간 (씨앗 기본값) | 확정 — 결정 8 | **채택: 의존 서비스 60초, 앱 헬스 120초.** 실측에서 MySQL은 약 8초, 앱 기동은 9초였다(컴파일 캐시가 있을 때). 첫 실행의 컴파일 시간을 고려해 여유를 두었다 |
| 4. Maven Central 429 | 확정 — 범위 밖 | 클라우드 세션에서만 났고 다시 시도해 해결했다. 보고서 "검증하지 못한 것"에 남긴다 |

## 변경 이력

| 날짜 | 변경 |
|---|---|
| 2026-10-23 | 초안 — TripFit-server 실측 반영 |
| 2026-10-26 | 배달본에서 프로젝트 값 제거 — `scripts/dev.conf`를 `{…}` 빈칸으로, 이 저장소 값은 루트 `dev.conf`로. `dev.sh` 설정 탐색 순서와 엔진 테스트 3건, 검사기의 배달본 빈칸 검사 추가. 헬스 시간 초과 뒤 `Terminated: 15` 줄이 출력에 섞이던 문제 수정(`disown`) |
| 2026-10-23 | 사용자 목표("빌드·실행 환경도 프로젝트별로 분리") 확인 후 구조 변경: 스택별 스크립트 씨앗 → core 엔진 `dev.sh` + 프로젝트 설정 `dev.conf`. 위험 명령 사전 검사, 이 저장소 적용, 엔진 테스트 추가 |
| 2026-10-24 | 승인. 기본값 3개 확정(결정 8), 커밋 서명 오판 픽스처 추가(결정 9), 효과 측정 보류(결정 10) |
| 2026-10-24 | 별도 컨텍스트 리뷰 10건 반영 — heredoc 판정 보완(`<<<`·셸에 넘긴 본문·닫는 줄), 리다이렉션 뒤 테스트 실행 인정, 결과 파일 0개는 실패(씨앗 `--rerun`), 실패한 start의 서비스 정리, 추가 컨테이너 설정 라벨, `pre-commit` 엔진 테스트, 남은 `verify.sh` 안내 수정 |
| 2026-10-24 | 구현. 정정: 이 저장소의 빌드·포맷·의존성 슬롯은 `(없음)` 유지 · `EXTRA_CONTAINERS` 구분자 쉼표 · `{…}` 자리표시자 차단 추가 · 시작 명령은 데몬 없이(`--no-daemon`). 결과는 `docs/reports/2026-10-24-dev-script.md` |
