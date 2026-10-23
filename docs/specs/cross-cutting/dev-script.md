# 프로젝트 동작 스크립트화 — `scripts/dev.sh`

> 상태: Draft
> MVP: In scope
> 관련 BR: N/A

## 목표

하네스를 붙인 프로젝트의 빌드·테스트·실행·종료·로그 확인을 `scripts/dev.sh <동사>` 하나로 묶는다. 그러면 AI가 세션마다 명령을 새로 조합하지 않고, 같은 입력에는 같은 명령이 같은 순서로 실행된다. 성공 출력은 한 줄로, 실패 출력은 원인이 보이는 몇 줄로 줄여 대화 컨텍스트에 들어가는 토큰도 줄인다.

## 배경

- 2026-10-23 이력서 피드백: "프로젝트별 수행하는 동작들을 별도로 스크립트화해 토큰 비용 감소와 결정적 동작으로 개선 (빌드·실행을 `start.sh`로 관리하는 등)"
- **지금 있는 것:** 하네스 자체 검사는 `scripts/verify.sh`가 스크립트로 묶고 출력도 줄인다. 2026-10-23 실측 결과 모두 통과할 때 기본 출력은 307B이고, 전체 출력(`VERIFY_VERBOSE=1`)은 21,017B다
- **없는 것:** 붙여 쓰는 프로젝트의 명령은 `harness-map.md`에 문자열로만 적혀 있다. 실행·종료·로그 슬롯이 없고, `AGENTS.template.md`의 `{로컬 실행}`도 자유 서술 칸이다. 여러 단계로 된 작업(DB 컨테이너 기동 → 대기 → 앱 기동 → 헬스 체크)은 AI가 매번 새로 짠다
- **TripFit-server 실측 (2026-10-23, `Central-MakeUs/TripFit-server` 커밋 `e2a2ee7`, 읽기 전용 클론):**

| 항목 | 실측 | 스크립트가 맡을 것 |
|---|---|---|
| `./gradlew test` | 테스트 543개 중 1개 실패, 2분 56초 걸림. 콘솔 출력은 5,656B인데 실패 원인이 없고 `AssertionError at …:175`만 나온다. 원인은 결과 XML(그 클래스 하나가 13,745B, 전체 4.9MB)에 있다 | 실패한 테스트의 이름과 원인 메시지를 XML에서 뽑아 몇 줄로 보여 준다 |
| 로컬 기동 | `docker compose up -d`는 MySQL만 띄운다. 그 상태로 `bootRun`을 하면 앱은 9초 만에 뜨지만, Redis가 없어서 `/actuator/health`가 계속 503(`DOWN`)이다. `readiness`는 `UP`이다 | 의존 서비스 기동과 헬스 판정 기준을 한 번 정해 고정한다 |
| 기동 로그 | 3분 동안 424,079B(4,590줄)가 쌓였다. Redis 재연결 실패가 243회, SQL 출력이 52회다 | `logs`는 에러 줄과 마지막 N줄만 보여 준다 |
| 종료 | 프로세스 이름 패턴으로 `pkill`을 하자 그 명령을 실행한 셸도 패턴에 걸려 같이 종료됐다(exit 144) | 기동할 때 PID(프로세스 번호)를 파일에 남기고, 그 번호로만 종료한다 |
| 의존성 다운로드 | 첫 실행에서 Maven Central이 429(요청 과다)를 반환했다. 간격을 두고 다시 시도해 4회 만에 받았다 | 이 스펙의 범위 밖이다. 환경 문제로 보고 "검증하지 못한 것"에 남긴다 |

- 실패한 테스트(`NotificationLockOrderIntegrationTest.activationAndOwnerWithdrawal_neverDeadlock`)는 실제 MySQL에서 데드락이 2건 났다는 TripFit 코드 쪽 문제다. 이 스펙과는 관계없어 기록만 한다
- **하네스 쪽 결함:** `deny-unverified-completion.sh`는 `TEST_CMD`의 첫 단어에서 파일 이름만 떼어 비교한다(`test_key`). `TEST_CMD`를 `scripts/dev.sh test`로 바꾸면 `scripts/dev.sh build`나 `scripts/dev.sh test --tests 하나`를 실행해도 전체 테스트를 돌린 것으로 판정된다
- 관련 문서: `docs/specs/cross-cutting/harness-slot-system-v2.md` "부품성 원칙" · `examples/seeds/README.md` "씨앗을 새로 올리는 조건"

## 결정 기록

| # | 질문 | 결정 |
|---|---|---|
| 1 | 진입점 이름·형태 | `scripts/dev.sh <동사>` 하나. 동사별로 파일을 나누지 않는다(부품성 원칙 1: 장치 하나는 bash 하나). 2026-10-23 사용자가 위임 |
| 2 | 씨앗 근거 | TripFit-server에서 실측하고 검증한 결과를 `java-spring` 씨앗으로 올린다(A안). TripFit 저장소에는 커밋하지 않는다. 2026-10-23 사용자 결정 |
| 3 | 씨앗 파일 이름 | `examples/seeds/java-spring/scripts/dev.sh`, 복사 위치는 `scripts/dev.sh`로 이름을 바꾸지 않는다. `local-` 접두사는 `.claude/` 안의 층을 검사기에 알리는 표시이고, 검사기는 프로젝트의 `scripts/dev.sh`를 보지 않는다(`check-portability.sh`의 대상은 `scripts/git-hooks/*`뿐이다) |
| 4 | 기존 슬롯과의 관계 | 새 개념을 더하지 않고 대체한다. `{{테스트 명령}}`·`{{빌드 명령}}`·`{{포맷 명령}}`·`{{의존성 조회}}`의 값이 `scripts/dev.sh <동사>`가 된다. 슬롯 이름은 그대로 둔다 |

## 요구사항

### Must Have

- [ ] **`dev.sh` 계약** — `examples/seeds/_template/README.md`에 "`scripts/dev.sh` 계약" 절을 추가한다. 스택과 관계없는 규약이라 씨앗이 없는 스택도 이 계약대로 쓴다
  - 동사: `build` · `test [인자…]` · `fmt` · `deps` · `start` · `stop` · `status` · `logs [N]`. 프로젝트에 해당하는 일이 없는 동사는 "없음 — 이유"를 출력하고 exit 0으로 끝낸다
  - 종료 코드: `0` 성공 · `1` 실패 · `2` 환경 없음(컨테이너 런타임·런타임 버전·포트 점유). `2`는 `preflight`의 "검증하지 못한 것"으로 넘긴다
  - 출력: 성공하면 `dev <동사>: 통과 — <요약>` 한 줄만 쓴다. 실패하면 `dev <동사>: 실패 <개수>` 한 줄, 실패 항목마다 이름과 원인 한 줄(최대 10개, 줄당 최대 300자), 마지막에 전체 로그 경로를 쓴다. 실패 줄은 `deny-unverified-completion.sh`의 `FAILED` 정규식에 걸리고, 성공 줄은 걸리지 않는다
  - 전체 로그: 동사마다 `<로그 디렉터리>/<동사>.log`에 덮어쓴다. 에이전트는 필요할 때만 이 파일을 grep한다
  - `start`는 여러 번 실행해도 결과가 같다: 이미 떠 있으면 PID만 보여 주고 exit 0으로 끝낸다. 의존 서비스가 healthy가 될 때까지 기다린 뒤 앱을 백그라운드로 띄우고, 헬스 URL이 성공할 때까지 정해진 시간만큼 기다린다. 시간 안에 성공하지 못하면 앱을 종료하고 exit 1과 함께 로그의 에러 줄을 보여 준다
  - `stop`은 PID 파일의 번호로만 종료한다. 프로세스 이름 패턴은 쓰지 않는다. 떠 있는 것이 없으면 exit 0으로 끝낸다
- [ ] **`java-spring` 씨앗 스크립트** — `examples/seeds/java-spring/scripts/dev.sh`. 머리에 프로젝트 값 변수(의존 서비스 이름, 헬스 URL, 포트, 대기 시간, 로그 디렉터리)를 모아 두고, 본문은 계약만 구현한다. 테스트 실패 요약은 JUnit XML 결과를 `python3`으로 읽어 만든다(하네스가 이미 `python3`을 전제한다). 도메인·프로젝트 이름은 넣지 않는다
- [ ] **TripFit에서 검증** — 위 씨앗을 TripFit 클론에 복사해 아래 "검증 시나리오"를 모두 실행한다. 클론에만 두고 TripFit에 커밋하지 않는다
- [ ] **씨앗 README 갱신** — `examples/seeds/java-spring/README.md` "무엇을 어디에 복사하나" 표에 `scripts/dev.sh` 행을 추가하고, "씨앗 대조" 표에 dev.sh가 전제하는 것(의존 서비스 compose 이름, 헬스 경로, 테스트 결과 경로, 기동 태스크)을 행으로 추가한다. `examples/seeds/README.md`의 "씨앗 파일명은 전부 `local-*`" 문장에 결정 3의 예외를 적는다
- [ ] **완료 검사 훅 수정** — `deny-unverified-completion.sh`가 파일 이름이 아니라 `TEST_CMD` 전체(모든 단어)와 비교하게 하고, 그 뒤에 인자가 더 붙으면 전체 테스트로 보지 않게 한다. 이 저장소의 `TEST_CMD`(`scripts/verify.sh`)는 결과가 바뀌지 않는다
- [ ] **훅 케이스** — `scripts/hook-cases.txt`에 여러 단어로 된 `TEST_CMD` 케이스를 먼저 추가한다. `test-hooks.sh`가 `self=`로 `HARNESS_SELF_EDIT`를 바꿔 넣는 기존 방식대로 `test=`로 `TEST_CMD`를 바꿔 넣는다(테스트 실행에서만 바꾸는 값이라 실제 훅에 우회 경로가 생기지 않는다). 픽스처: `dev.sh test` 실행 → 통과, `dev.sh build`만 실행 → 차단, `dev.sh test --tests X`만 실행 → 차단
- [ ] **`{{실행 명령}}` 슬롯** — `harness-map.md` 명령 슬롯 표에 추가한다. 이 저장소 값은 `(없음) — 실행할 앱 없음`. core가 실제로 쓰는 곳은 `debug` 스킬 "로컬 재현" 단계("앱을 띄워 재현할 때는 `{{실행 명령}}`, 끝나면 같은 스크립트의 `stop`")다. 슬롯 규칙 3(core가 쓸 때만 둔다)을 지킨다
- [ ] **행동 규칙 한 줄** — `core-workflow.md` "구현" 절에 "빌드·테스트·실행은 명령 슬롯으로만 부르고, 같은 일을 하는 명령을 직접 조합하지 않는다"를 추가한다. always-load 예산(현재 27,362B / 상한 28,000B) 안에서 넣는다
- [ ] **`adopt` 연결** — 3단계에 "씨앗의 `scripts/dev.sh`를 복사하거나 `_template` 계약대로 CI 워크플로의 실제 명령으로 작성 → 명령 슬롯과 `TEST_CMD`를 `scripts/dev.sh <동사>`로" 항목을 추가하고, 산출물 체크리스트에 "`scripts/dev.sh test`·`build`를 한 번씩 실행해 종료 코드가 0 또는 1이다(2가 아니다)"를 추가한다
- [ ] **`AGENTS.template.md`** — Commands 블록의 `{로컬 실행}`·`{{테스트 명령}}`·`{{빌드 명령}}`을 `scripts/dev.sh` 동사 목록으로 바꾼다
- [ ] **현재동작 요약** — 훅 판정이 바뀌므로 `docs/harness/README.md` "지금의 실제 동작"에서 완료 검사 훅 설명을 쉬운 말로 고친다(STOP §3)

### Nice to Have

- [ ] **효과 측정 보고서** — 같은 과제("앱을 띄우고 헬스 체크까지", "실패한 테스트 원인 찾기")를 dev.sh 도입 전후로 N회씩 반복한다. 도구 호출 수, 대화에 들어간 출력 바이트, 세션마다 다르게 나온 명령의 종류 수를 비교한다. 형식은 `docs/reports/2026-10-16-harness-effect-measurement.md`를 따른다

### Out of Scope (이번 스펙에서 하지 않음)

- `setup` 동사(`.env` 생성·비밀값 채우기). 비밀값을 다루는 일이라 스크립트로 자동화하지 않는다
- 스크립트를 거치지 않는 직접 명령(`./gradlew bootRun` 등)을 막는 훅. 정상적인 변형까지 막을 수 있다. 규칙 한 줄로 시작하고, 우회 사례가 반복되면 다시 검토한다(`docs/out-of-scope/README.md`에 행 추가)
- TripFit의 데드락 테스트 실패와 Maven Central 429 대응
- 이 저장소(Superchaeyeons)에 `scripts/dev.sh`를 두는 것. 빌드·실행할 앱이 없고, 테스트는 `scripts/verify.sh`가 이미 맡는다

## 테스트 먼저 지점

| Must 항목 | 테스트 먼저 | 근거 |
|---|---|---|
| 완료 검사 훅 수정 · 훅 케이스 | 테스트 먼저 | 훅이 "테스트를 돌렸는가"를 판정하는 검증 게이트다. 비교 방식을 바꾸면 기존 픽스처 판정이 달라질 수 있다. `AGENTS.md`도 훅 수정 전에 케이스부터 넣으라고 한다 |
| `java-spring` 씨앗 스크립트 | 아님 | Gradle·컨테이너·포트가 있어야 동작하므로 이 저장소에서는 단위 테스트로 깨뜨릴 수 없다. TripFit 실행(검증 시나리오)으로 확인한다 |
| `dev.sh` 계약 · 씨앗 README · 슬롯 · 규칙 · `adopt` · 템플릿 · 현재동작 요약 | 아님 | 문서다. `scripts/verify.sh`(슬롯 정의·사용 대조, 구성 요소 목록 대조, 문서 스타일)가 검사한다 |

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 기존 훅 케이스(102개) 판정이 바뀌지 않는다 | `scripts/test-hooks.sh` |
| core에 스택·프로젝트 이름이 들어오지 않는다 | `scripts/check-portability.sh` 부품 계약 위반 0 |
| always-load 합계가 28,000B를 넘지 않는다 | `scripts/check-portability.sh` 예산 줄 |
| TripFit 저장소에 아무것도 커밋·푸시하지 않는다 | 클론의 `git status`에 미추적 파일만 있고 `git log`가 `e2a2ee7`에서 그대로다 |

## API / 인터페이스

API 없음. 인터페이스는 `dev.sh`의 동사·종료 코드·출력 형식이고, 위 "`dev.sh` 계약"이 정의한다.

## 검증 시나리오

### 정상 (TripFit 클론)

- [ ] `dev.sh test` → 현재 TripFit 상태라 exit 1. 출력은 15줄 이하이고 실패한 테스트 이름과 데드락 원인 한 줄이 있다. 바이트 수를 기존 방식(콘솔 5,656B + 원인을 보려고 연 XML 13,745B)과 비교해 보고서에 적는다
- [ ] `dev.sh test --tests <통과하는 클래스>` → exit 0, 한 줄
- [ ] `dev.sh build` → exit 0, 한 줄
- [ ] `dev.sh start` → 의존 서비스 healthy 확인 → 앱 헬스 성공 → exit 0. 다시 `start` → "이미 실행 중 (PID n)" exit 0
- [ ] `dev.sh status` → 실행 중·PID·헬스 결과 한 줄
- [ ] `dev.sh logs` → 에러 줄과 마지막 N줄만, 전체 로그 경로
- [ ] `dev.sh stop` → 포트가 닫히고 PID 파일이 지워진다. 다시 `stop` → exit 0
- [ ] `start → stop`을 3회 반복해도 출력 형식과 종료 코드가 같다

### 엣지 · 실패

- [ ] 컨테이너 런타임 데몬이 꺼져 있다 → `start`가 exit 2, "환경 없음" 한 줄
- [ ] 앱 포트를 다른 프로세스가 이미 쓰고 있다 → `start`가 exit 2
- [ ] 헬스가 대기 시간 안에 성공하지 못한다 → 앱을 종료하고 exit 1, 에러 줄을 보여 준다

### 훅 (이 저장소)

- [ ] 여러 단어 `TEST_CMD` 픽스처 3개(통과 1 · 차단 2)와 기존 102개 케이스가 `scripts/test-hooks.sh`에서 모두 통과한다

## 완료 기준

- [ ] `scripts/verify.sh` 통과
- [ ] 위 TripFit 검증 시나리오의 실행 결과(명령 → 종료 코드 → 출력 바이트)가 작업 보고서에 있다
- [ ] `{{빌드 명령}}` — 이 저장소는 `(없음)`이라 해당 없음
- [ ] 작업 보고서 `docs/reports/2026-10-23-dev-script.md`(L 규모 — "검증하지 못한 것" 포함)

## 리스크·미결정

| 항목 | 상태 | 비고 |
|---|---|---|
| `start`의 헬스 판정 기준 | [미정] — 사용자 결정 | **권장: 의존 서비스(Redis 포함)를 모두 띄우고 전체 `/actuator/health`가 `UP`일 때 성공.** TripFit compose에는 Redis가 없으므로 씨앗 머리 변수에 "추가로 띄울 컨테이너"를 두고, TripFit 값은 운영과 같은 이미지(`redis:7-alpine`)로 한다. 대안: `readiness`만 본다. Redis 없이도 성공하지만, 그 뒤에 AI가 전체 헬스 `DOWN`을 보고 원인을 다시 찾게 된다 |
| 로그 디렉터리 기본값 | [미정] — 사용자 결정 | **권장: `build/dev/`** — Gradle 빌드 산출물 폴더라 이미 `.gitignore`에 들어 있고 `clean`으로 함께 지워진다. 대안: `.dev/logs/`(TripFit에 `.dev/`가 이미 있지만 세션 기록용이다) |
| `start` 대기 시간 기본값 | [미정] — 사용자 결정 | **권장: 의존 서비스 60초, 앱 헬스 120초.** 실측에서 MySQL은 약 8초, 앱 기동은 9초였다(컴파일 캐시가 있을 때). 첫 실행의 컴파일 시간까지 고려해 넉넉히 잡았다 |
| Maven Central 429 | 확정 — 범위 밖 | 클라우드 세션에서만 났고, 다시 시도해 해결했다. 보고서 "검증하지 못한 것"에 남긴다 |

## 변경 이력

| 날짜 | 변경 |
|---|---|
| 2026-10-23 | 초안 — TripFit-server 실측 반영 |
