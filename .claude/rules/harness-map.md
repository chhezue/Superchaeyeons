# Harness Map — 이 프로젝트의 슬롯

규칙(`core-*.md`)은 경로·명령을 `{{역할 이름}}`으로 부르고, 이 파일이 역할 → 실제 값을 잇는다. **새 프로젝트가 채우는 파일은 이것 하나다** (`adopt` 스킬). 채운 예: `examples/tripfit/harness-map.md` · `examples/baro/harness-map.md`

## 규칙

1. 빈 슬롯은 `(없음)`으로 명시한다 — "안 정했다"와 "이 프로젝트엔 없다"를 구분하기 위해
2. `(없음)`인 슬롯을 규칙이 요구하면 **멈추고 사용자에게 묻는다**
3. 슬롯·플래그는 `core-*.md`에서 실제로 쓰는 곳이 있을 때만 추가한다
4. **옵션을 끄려고 규칙 절을 지우지 않는다** — ❌면 `[플래그: X]` 배지 절을 무시한다 (`core-guardrails.md` "플래그 판정")
5. `core-*.md`는 손대지 않는다. 고유 사실은 이 파일(값)과 `.claude/` 안의 `local-*`(규칙·복사한 씨앗)에만 — 검사기가 그 둘만 검사에서 뺀다

## 축 — 이 프로젝트가 서 있는 자리

축의 값은 붙이는 시점에 **실측**해서 적는다. 값은 자유 서술이고, 규칙이 참조하는 것은 슬롯과 능력 플래그뿐이다.

| 축 | 무엇이 달라지나 | 이 프로젝트 |
|----|----------------|-------------|
| **lang** | 코딩 컨벤션·테스트·포맷 명령·리뷰어 · 실행 환경 전제 | **없음** — 애플리케이션 코드가 없는 문서·스크립트 저장소(md·sh). 훅·검사기는 `bash`·`python3`를 전제한다(macOS·Linux 셸 환경) |
| **shape** | 경로·쓰기 범위·빌드 단위·문서 루트·Git 컨벤션 소유권 | 단일 저장소 · 문서 루트 `docs/` · `.github/` 쓰기 가능 · 작업 범위 = 저장소 전체 |
| **deploy** | 인증 위치·API 계약 보호·배포 SSOT | **없음** — 배포·외부 클라이언트 없음 |
| **stage** | 마이그레이션·계약 동결·레거시 삭제 강도 | 초기(커밋 4·태그 0) · 운영 데이터 없음 · 계약은 core 부품 계약 하나(`scripts/check-portability.sh`) |

## 경로 슬롯

함께 배달되는 문서도 `{{문서 루트}}` 기준 상대 경로다.

| 슬롯 | 이 프로젝트의 경로 | 쓰는 곳 |
|------|-------------------|---------|
| `{{문서 루트}}` | `docs/` (기본값) | `core-workflow` G4 · `core-followup` · `core-tools` — 함께 배달되는 문서의 상위 경로 |
| `{{작업 범위}}` | `.` (기본값 = 저장소 전체) | `adopt` 스킬 실측 범위 · `deny-out-of-scope-write.sh` 훅 — **훅 본문의 `SCOPE=`를 여기 값과 함께 고칠 것** (`.`이면 범위 검사 생략) |
| `{{Git 컨벤션 SSOT}}` | `.github/CONTRIBUTING.md` | `core-guardrails` · `core-workflow` G2·G4. **`(없음)`이면 `core-workflow` G2·G4가 SSOT다** — 저장소 루트에 파일을 둘 수 없는 프로젝트를 위해 |
| `{{스펙 저장소}}` | `docs/specs/` — README가 기본값으로 선언, v2 스펙이 실제로 여기 있음 | `core-workflow` A 트랙 · `specify` 스킬 |
| `{{현재동작 요약}}` | `docs/harness/README.md` — 이 저장소에서 "보안·아키텍처 성격 변경"은 훅·규칙 동작 변경이고, 그걸 쉬운 말로 설명하는 곳 | `core-guardrails` ⛔ §3 |
| `{{우선순위 SSOT}}` | (없음) — 이슈 우선순위 라벨 체계가 없다. 작업 순서는 v2 스펙의 `단계(Phase)` 표 | `core-workflow` 진입 · `core-scope` · `local-priority.md`(라벨 체계가 있을 때) |
| `{{아키텍처 개요}}` | `docs/harness/README.md` — 하네스 4개 레이어 | `core-guardrails` ⛔ §1 · lang 팩 DB 절 |
| `{{스키마 SSOT}}` | (없음) — DB 없음 | `core-followup` 💡 ERD · lang 팩 DB 절 |
| `{{API 응답 규격}}` | (없음) — API 없음 | lang 팩 "같은 턴 즉시 갱신" 절 |
| `{{API 문서}}` | (없음) — API 없음 | `core-guardrails` ⛔ §1.6 · `core-workflow` G3 · lang 팩 "API 계약 변경" 절 |
| `{{제품 범위}}` | `AGENTS.md` — "무엇이 들어 있나"·"이 저장소에서 작업할 때" | `core-workflow` 진입 · `core-scope` |
| `{{클라이언트 전제}}` | (없음) — 클라이언트 없음 | `core-workflow` 진입 · `specify` 스킬 |
| `{{용어집}}` | (없음) — 하네스 용어(축·슬롯·플래그·트랙·게이트)는 이 파일과 `core-workflow.md`가 정의 | `doc-reviewer` 에이전트 |
| `{{결정 기록}}` | `docs/decisions/` — ADR 0개, 이번 결정들은 v2 스펙 `미결정` 표에 있음 | `core-guardrails` ⛔ §1 · `core-workflow` 진입 |
| `{{감사 로그}}` | `docs/audits/` — `harness-retro.md` | `core-workflow` G4 · `safe-refactor` 스킬 |
| `{{배포 SSOT}}` | (없음) — 배포 없음 | `core-guardrails` ⛔ §1 |

## 명령 슬롯

| 슬롯 | 이 프로젝트의 명령 | 쓰는 곳 |
|------|-------------------|---------|
| `{{테스트 명령}}` | `scripts/verify.sh` — 기계 검증 3개(`check-portability` · `test-hooks` · `check-doc-style --all`)를 한 번에 돌리는 래퍼. 개별 검사기는 진단용이고 "통과" 판정은 이 명령으로 한다 | `core-workflow` 구현·G3 · `preflight` 스킬 · `deny-unverified-completion.sh` 훅 — **훅 본문의 `TEST_CMD=`를 여기 값과 함께 고칠 것** |
| `{{빌드 명령}}` | (없음) — 빌드 없음 | `preflight` 스킬 |
| `{{포맷 명령}}` | (없음) — 포맷 도구 없음 (포맷 훅은 씨앗에 있고 값이 생길 때 복사한다) | `auto-format-*` 훅 — **훅 스크립트는 명령을 직접 박아 쓴다.** 여기 적은 값과 `.claude/hooks/auto-format-*.sh` 본문을 함께 고칠 것 |
| `{{의존성 조회}}` | (없음) — 의존성 없음 | `core-workflow` G1 |

## 형식 슬롯

Git 규율은 `core-workflow.md` G2·G4가 담고, **형식 문자열만** 여기서 읽는다. 기존 저장소에 붙일 때는 기본값을 물려받지 않고 `adopt`이 커밋·브랜치 이력에서 **실측**해 채운다.

| 슬롯 | 이 프로젝트의 형식 | 쓰는 곳 |
|------|-------------------|---------|
| `{{브랜치명 형식}}` | `{type}/{issue-number}-{description}` (기본값) | `core-workflow` G2 |
| `{{커밋 메시지 형식}}` | `{Type}: {한글}` (기본값) | `core-workflow` G4 · `commit-msg` git 훅 — **훅 스크립트는 정규식을 직접 박아 쓴다.** 여기 적은 값과 `scripts/git-hooks/commit-msg` 본문을 함께 고칠 것 |

## 능력 플래그

프로젝트 상황을 전제한 정책. 규칙 본문은 `[플래그: X]` 배지로 이 표를 부르고, 이 표가 ☑/❌를 판정한다. 끌 때 절을 지우지 않고(규칙 4) 훅만 `settings.json`에서 해제한다.

| 플래그 | 이 프로젝트 | 배지가 붙은 절 (☑면 적용) | ❌일 때 추가 조치 |
|--------|-------------|---------------------------|-------------------|
| **DB 마이그레이션 금지** | ❌ | lang 팩 "DB 스키마 정책" 절 (씨앗 java-spring: `local-spring-boot-java.md`) | ☑이면 씨앗의 `local-deny-db-migration.sh`를 `.claude/hooks/`에 복사·등록. **운영 DB가 있으면 반드시 ❌** |
| **에러 코드 카탈로그 동시갱신** | ❌ | lang 팩 "같은 턴 즉시 갱신" 절 앞 2행 (씨앗 java-spring: `local-spring-boot-java.md`) — 원칙은 `core-guardrails` §1.7 | 없음 |
| **권한 게이트·활동 기록 동시갱신** | ❌ | lang 팩 "같은 턴 즉시 갱신" 절 뒤 2행 (씨앗 java-spring: `local-spring-boot-java.md`) | 없음 |
| **API 계약 보호** | ❌ | lang 팩 "API 계약 변경" 절 (씨앗 java-spring: `local-openapi-conventions.md`) · `core-workflow` G3 API 행 | ☑이면 씨앗의 `local-warn-breaking-change.sh`를 복사·등록 |
| **생성 문서 검증** | ❌ | `core-guardrails` §1.6 · lang 팩 "생성 문서 검증" 절 (씨앗 java-spring: `local-openapi-conventions.md`) | 없음 |
| **스택 함정 메모** | ❌ | `core-workflow` G1 배지 절 — 본문은 lang 팩 (씨앗 java-spring: `local-g1-stack-trap.md`) | 없음 |
| **스택 리뷰어** | ❌ | `core-workflow` G3 리뷰어 행 — 리뷰어 에이전트 (씨앗 java-spring: `agents/local-spring-reviewer.md`) | 없음 |
| **하네스 자기 수정** | ☑ | `core-gates` §3 훅·`settings.json` 수정 행 | ❌이면 `deny-out-of-scope-write.sh`의 `HARNESS_SELF_EDIT="0"` — 에이전트가 `.claude/hooks/`·`settings.json`을 못 쓴다. **붙여 쓰는 프로젝트는 ❌가 기본** |

**⬜ = 미결정.** 하나라도 남으면 하네스가 절반만 작동한다. 붙이는 첫 턴에 전부 ☑/❌로 바꾼다.

**이 저장소의 판정:** DB·API·애플리케이션 코드가 없어 스택 플래그 7개는 전부 ❌, "하네스 자기 수정"만 ☑(이 저장소의 작업이 곧 훅 수정이라). 훅 5개는 스택 무관이라 항상 등록. 플래그에 묶인 훅은 씨앗에만 있고 `adopt`이 ☑인 것만 복사·등록한다.

## 스택 팩 (= lang 팩)

언어·프레임워크 전용 규칙·에이전트·훅. 배달물에 없고 `adopt`이 씨앗(`examples/seeds/{스택}/`)을 `local-*` 이름 그대로 복사하거나 `_template/`을 채운다. 이 표는 **이 저장소 `.claude/`에 실제로 있는 lang 팩 파일**이다.

| 팩 | 이 저장소의 파일 | 출처 씨앗 | 대상 |
|----|------------------|-----------|------|
| (없음) — lang 축이 "없음"인 문서·스크립트 저장소 | — | — | — |

인프라 성격 규칙(클라이언트 전제·배포 토폴로지)은 스택이 아니라 저장소 고유 사실이라 `local-*.md`로 쓴다 (견본 `examples/tripfit/client-platform.md`·`deployment.md`). 이 파일의 변경 이력은 `{{문서 루트}}/specs/cross-cutting/harness-slot-system-v2.md` 변경 이력에 있다.
