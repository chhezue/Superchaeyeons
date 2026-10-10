# Harness Map — 이 프로젝트의 슬롯

하네스 규칙(`core-*.md`)은 **경로·명령을 직접 부르지 않는다.** 대신 `{{역할 이름}}`으로 부르고, 이 파일이 역할 → 실제 경로·명령을 잇는다.

**새 프로젝트에 하네스를 붙일 때 채우는 건 이 파일 하나다.** 규칙 파일은 건드리지 않는다.

채운 예시: [`examples/tripfit/harness-map.md`](../../examples/tripfit/harness-map.md)

## 규칙

1. **빈 슬롯은 `(없음)`으로 명시한다.** 비워두지 않는다 — 에이전트가 "아직 안 정했다"와 "이 프로젝트엔 그 개념이 없다"를 구분해야 한다.
2. `(없음)`인 슬롯을 규칙이 요구하면 **에이전트는 멈추고 사용자에게 묻는다** (`core-guardrails.md` ⛔ §1.4와 동일).
3. 슬롯을 추가하려면 `core-*.md`에서 실제로 `{{...}}`를 쓰는 곳이 있어야 한다. 쓰지 않는 슬롯은 만들지 않는다.
4. **옵션을 끄려고 규칙 파일을 수정하지 않는다.** 플래그가 ❌면 `[플래그: X]` 배지가 붙은 절을 에이전트가 무시한다. 절을 지우면 부품이 갈라져 이후 개선을 함께 받을 수 없다 (`core-guardrails.md` "플래그 판정").
5. `core-*.md`는 프로젝트가 손대지 않는다. 고유 사실은 이 파일(값)과 `local-*`(규칙·복사한 씨앗)에만 적는다 — `scripts/check-portability.sh`가 이 파일과 `.claude/` 안의 `local-*` 파일을 검사에서 빼는 이유다. 씨앗은 파일명이 이미 `local-*`라 복사한 뒤에도 접두사가 층을 표시한다.

## 축 — 이 프로젝트가 서 있는 자리

프로젝트마다 달라지는 것을 네 축으로 본다. 축의 값은 붙이는 시점에 **실측**해서 적는다 (관례를 물려받지 않는다). 값 자체는 자유 서술이고, 규칙이 참조하는 것은 아래 능력 플래그와 슬롯뿐이다.

| 축 | 무엇이 달라지나 | 이 프로젝트 |
|----|----------------|-------------|
| **lang** | 코딩 컨벤션·테스트·포맷 명령·리뷰어 · 실행 환경 전제 | **없음** — 애플리케이션 코드가 없는 문서·스크립트 저장소(md·sh). 훅·검사기는 `bash`·`python3`를 전제한다(macOS·Linux 셸 환경) |
| **shape** | 경로·쓰기 범위·빌드 단위·문서 루트·Git 컨벤션 소유권 | 단일 저장소 · 문서 루트 `docs/` · `.github/` 쓰기 가능 · 작업 범위 = 저장소 전체 |
| **deploy** | 인증 위치·API 계약 보호·배포 SSOT | **없음** — 배포·외부 클라이언트 없음 |
| **stage** | 마이그레이션·계약 동결·레거시 삭제 강도 | 초기(커밋 4·태그 0) · 운영 데이터 없음 · 계약은 core 부품 계약 하나(`scripts/check-portability.sh`) |

## 경로 슬롯

하네스와 **함께 배달되는** 문서(`docs/templates/`·`docs/audits/harness-retro.md`·`docs/reports/`)도 고정 경로가 아니다 — 문서 루트가 저장소 루트의 `docs/`가 아닌 프로젝트(모노레포 하위 경로 등)가 있어, 규칙은 전부 `{{문서 루트}}` 기준 상대 경로로 부른다. 기본값이 있는 슬롯은 대부분의 프로젝트가 그대로 두면 된다.

| 슬롯 | 이 프로젝트의 경로 | 쓰는 곳 |
|------|-------------------|---------|
| `{{문서 루트}}` | `docs/` (기본값) | `core-workflow` G4 · `core-followup` · `core-tools` — 함께 배달되는 문서의 상위 경로 |
| `{{작업 범위}}` | `.` (기본값 = 저장소 전체) | `adopt` 스킬 실측 범위 · `deny-out-of-scope-write.sh` 훅 — **훅 본문의 `SCOPE=`를 여기 값과 함께 고칠 것** (`.`이면 훅은 무동작) |
| `{{Git 컨벤션 SSOT}}` | `.github/CONTRIBUTING.md` | `core-guardrails` · `core-workflow` G2·G4 · `core-tools`. **`(없음)`이면 `core-workflow` G2·G4가 SSOT다** — 저장소 루트에 파일을 둘 수 없는 프로젝트를 위해 |
| `{{스펙 저장소}}` | `docs/specs/` — README가 기본값으로 선언, v2 스펙이 실제로 여기 있음 | `core-workflow` A 트랙 · `specify` 스킬 |
| `{{현재동작 요약}}` | `docs/harness/README.md` — 이 저장소에서 "보안·아키텍처 성격 변경"은 훅·규칙 동작 변경이고, 그걸 쉬운 말로 설명하는 곳 | `core-guardrails` ⛔ §3 |
| `{{우선순위 SSOT}}` | (없음) — 이슈 우선순위 체계가 없다. 작업 순서는 v2 스펙의 `단계(Phase)` 표 | `core-workflow` 진입 · `core-scope` |
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

Git 규율(이슈 번호 필수 · merge commit 유지 · 커밋 최대 5개 · 이슈·브랜치·PR 생성 전 확인)은 `core-workflow.md` G2·G4가 담고, **형식 문자열만** 여기서 읽는다. 기존 저장소에 붙일 때는 기본값을 물려받지 않고 `adopt`이 커밋·브랜치 이력에서 **실측**해 채운다 — 실측 없이 물려받았다가 963개 커밋을 세어보고서야 실제 관례(`[Type] #n - {한글}`)가 다르다는 걸 안 사례가 있다.

| 슬롯 | 이 프로젝트의 형식 | 쓰는 곳 |
|------|-------------------|---------|
| `{{브랜치명 형식}}` | `{type}/{issue-number}-{description}` (기본값) | `core-workflow` G2 |
| `{{커밋 메시지 형식}}` | `{Type}: {한글}` (기본값) | `core-workflow` G4 · `commit-msg` git 훅 — **훅 스크립트는 정규식을 직접 박아 쓴다.** 여기 적은 값과 `scripts/git-hooks/commit-msg` 본문을 함께 고칠 것 |

## 능력 플래그

경로로 뺄 수 없는 것들. **프로젝트 상황을 전제한 정책**이라 켜고 끄는 판단이 필요하다. 규칙 본문은 `[플래그: X]` 배지로 이 표를 부르고, 이 표가 ☑/❌를 판정한다. **끌 때 규칙 절을 지우지 않는다** (규칙 4) — 훅만 `settings.json`에서 해제한다.

| 플래그 | 이 프로젝트 | 배지가 붙은 절 (☑면 적용) | ❌일 때 추가 조치 |
|--------|-------------|---------------------------|-------------------|
| **DB 마이그레이션 금지** | ❌ | lang 팩 "DB 스키마 정책" 절 (씨앗 java-spring: `local-spring-boot-java.md`) | ☑이면 씨앗의 `local-deny-db-migration.sh`를 `.claude/hooks/`에 복사·등록. **운영 DB가 있으면 반드시 ❌** |
| **에러 코드 카탈로그 동시갱신** | ❌ | lang 팩 "같은 턴 즉시 갱신" 절 앞 2행 (씨앗 java-spring: `local-spring-boot-java.md`) — 원칙은 `core-guardrails` §1.7 | 없음 |
| **권한 게이트·활동 기록 동시갱신** | ❌ | lang 팩 "같은 턴 즉시 갱신" 절 뒤 2행 (씨앗 java-spring: `local-spring-boot-java.md`) | 없음 |
| **API 계약 보호** | ❌ | lang 팩 "API 계약 변경" 절 (씨앗 java-spring: `local-openapi-conventions.md`) · `core-workflow` G3 API 행 | ☑이면 씨앗의 `local-warn-breaking-change.sh`를 복사·등록 |
| **생성 문서 검증** | ❌ | `core-guardrails` §1.6 · lang 팩 "생성 문서 검증" 절 (씨앗 java-spring: `local-openapi-conventions.md`) | 없음 |
| **스택 함정 메모** | ❌ | `core-workflow` G1 배지 절 — 본문은 lang 팩 (씨앗 java-spring: `local-g1-stack-trap.md`) | 없음 |
| **스택 리뷰어** | ❌ | `core-workflow` G3 리뷰어 행 · `core-tools` G3 행 — 리뷰어 에이전트 (씨앗 java-spring: `agents/local-spring-reviewer.md`) | 없음 |

**⬜ = 미결정.** 하나라도 ⬜로 남아 있으면 하네스가 절반만 작동한다. 붙이는 첫 턴에 전부 ☑/❌로 바꾼다.

**이 저장소의 판정 (2026-09-05 `adopt` 자기 채움):** DB·API·애플리케이션 코드가 없어 7개 전부 ❌다. `settings.json`의 훅 5개는 전부 스택 무관이라 플래그와 관계없이 등록을 유지하며, 이 저장소에서도 실제로 발화한다. 플래그에 묶인 훅은 씨앗에만 있고 `adopt`이 ☑인 것만 복사·등록한다. 플래그를 새로 늘리는 문턱은 슬롯과 같다 — `core-*.md`에서 실제로 그 배지를 다는 절이 있을 때만.

## 스택 팩 (= lang 팩)

특정 언어·프레임워크 전용 규칙·에이전트·훅. **배달물(`.claude/`)에는 들어 있지 않다** — `adopt` 3단계가 실측한 lang 축에 맞는 **씨앗**(`examples/seeds/{스택}/`)을 복사하거나, 없으면 `examples/seeds/_template/`을 실측으로 채운다. 복사한 뒤에는 이 프로젝트가 소유한다. **파일명은 종류(규칙·에이전트·훅) 무관하게 `local-` 접두사를 유지한다** — 검사기가 그 접두사로 local 층을 식별해 검사에서 뺀다. 이 표는 그 결과, 즉 **이 저장소 `.claude/`에 실제로 있는 lang 팩 파일**을 적는다.

| 팩 | 이 저장소의 파일 | 출처 씨앗 | 대상 |
|----|------------------|-----------|------|
| (없음) — lang 축이 "없음"인 문서·스크립트 저장소 | — | — | — |

검증된 씨앗 목록은 `examples/seeds/README.md`. 인프라 성격 규칙(클라이언트 전제·배포 토폴로지)은 스택이 아니라 **저장소 고유 사실**이라 팩에 넣지 않는다 — `local-*.md`로 쓴다 (견본 `examples/tripfit/client-platform.md`·`deployment.md`).

## 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-09-05 | 초안 — TripFit 하네스에서 슬롯 17개(경로 13·명령 4)·옵션 7개 추출 |
| 2026-09-05 | P6 — 스택 규칙·에이전트·훅을 배달물에서 빼 `examples/seeds/java-spring/`로 이동, `_template/` 신설. 플래그 어휘 탈스택("에러 코드 카탈로그 동시갱신"·"권한 게이트·활동 기록 동시갱신"). 실행 환경 전제(bash·python3)를 lang 축에 기록 |
| 2026-09-05 | `adopt` 자기 채움 — 축 4개·슬롯 22개·플래그 7개를 이 저장소 실측값으로 채움. `(없음)` 11개는 전부 "이 저장소엔 그 개념이 없음"이며 이유를 값 칸에 적었다. 새 프로젝트에 붙일 때는 `adopt`이 이 값을 덮어쓴다 |
| 2026-09-05 | v2 — 축 4개 표 · 규칙 4(절 삭제 금지)·5(core 불가침) · "스택 옵션" → "능력 플래그" · 슬롯 5개 추가(`문서 루트`·`작업 범위`·`Git 컨벤션 SSOT`·`브랜치명 형식`·`커밋 메시지 형식`) — "함께 배달되는 문서는 고정 경로" 전제 폐기 |
| 2026-09-06 | 검수 반영 — `{{테스트 명령}}` = `scripts/verify.sh` · 씨앗 파일명 `local-*` 통일 · 훅 단락 정정 (상세: v2 스펙 변경 이력) |
