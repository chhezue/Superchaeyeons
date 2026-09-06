# Harness Map — 이 프로젝트의 슬롯

하네스 규칙(`core-*.md`)은 **경로·명령을 직접 부르지 않는다.** 대신 `{{역할 이름}}`으로 부르고, 이 파일이 역할 → 실제 경로·명령을 잇는다.

**새 프로젝트에 하네스를 붙일 때 채우는 건 이 파일 하나다.** 규칙 파일은 건드리지 않는다.

채운 예시: [`examples/tripfit/harness-map.md`](../../examples/tripfit/harness-map.md)

## 규칙

1. **빈 슬롯은 `(없음)`으로 명시한다.** 비워두지 않는다 — 에이전트가 "아직 안 정했다"와 "이 프로젝트엔 그 개념이 없다"를 구분해야 한다.
2. `(없음)`인 슬롯을 규칙이 요구하면 **에이전트는 멈추고 사용자에게 묻는다** (`core-guardrails.md` ⛔ §1.4와 동일).
3. 슬롯을 추가하려면 `core-*.md`에서 실제로 `{{...}}`를 쓰는 곳이 있어야 한다. 쓰지 않는 슬롯은 만들지 않는다.

## 경로 슬롯

하네스와 **함께 배달되는** 문서(`.github/CONTRIBUTING.md`, `docs/harness/`, `docs/templates/`, `docs/audits/harness-retro.md`)는 슬롯이 아니다 — 경로가 고정이므로 규칙이 직접 부른다.

| 슬롯 | 이 프로젝트의 경로 | 쓰는 곳 |
|------|-------------------|---------|
| `{{스펙 저장소}}` | (없음) | `core-workflow` A 트랙 · `specify` 스킬 |
| `{{현재동작 요약}}` | (없음) | `core-guardrails` ⛔ §6 |
| `{{우선순위 SSOT}}` | (없음) | `core-workflow` 진입 · `core-scope` |
| `{{아키텍처 개요}}` | (없음) | `core-guardrails` ⛔ §1·§3 |
| `{{스키마 SSOT}}` | (없음) | `core-followup` 💡 ERD |
| `{{API 응답 규격}}` | (없음) | `core-guardrails` ⛔ §2 |
| `{{API 문서}}` | (없음) | `core-guardrails` ⛔ §5 |
| `{{제품 범위}}` | (없음) | `core-workflow` 진입 |
| `{{클라이언트 전제}}` | (없음) | `core-workflow` 진입 · `specify` 스킬 |
| `{{용어집}}` | (없음) | `core-scope` |
| `{{결정 기록}}` | (없음) | `core-guardrails` ⛔ §1 · `core-workflow` 진입 |
| `{{감사 로그}}` | (없음) | `core-workflow` G4 · `safe-refactor` 스킬 |
| `{{배포 SSOT}}` | (없음) | `core-guardrails` ⛔ §1 |

## 명령 슬롯

| 슬롯 | 이 프로젝트의 명령 | 쓰는 곳 |
|------|-------------------|---------|
| `{{테스트 명령}}` | (없음) | `core-workflow` 구현·G3 · `preflight` 스킬 |
| `{{빌드 명령}}` | (없음) | `preflight` 스킬 |
| `{{포맷 명령}}` | (없음) | `auto-format-*` 훅 — **훅 스크립트는 명령을 직접 박아 쓴다.** 여기 적은 값과 `.claude/hooks/auto-format-*.sh` 본문을 함께 고칠 것 |
| `{{의존성 조회}}` | (없음) | `core-workflow` G1 |

## 스택 옵션

경로로 뺄 수 없는 것들. **프로젝트 상황을 전제한 정책**이라 켜고 끄는 판단이 필요하다.

| 옵션 | 이 프로젝트 | 켜면 적용 | 끄면 |
|------|-------------|-----------|------|
| **DB 마이그레이션 금지** | ⬜ | `core-guardrails` ⛔ §3 전체 + `deny-db-migration.sh` 훅 | §3 삭제, 훅 해제 — **운영 DB가 있으면 반드시 끈다** |
| **에러코드 enum 동시갱신** | ⬜ | `core-guardrails` ⛔ §2 앞 2행 | §2에서 해당 행 삭제 |
| **권한·활동 어노테이션(AOP)** | ⬜ | `core-guardrails` ⛔ §2 뒤 2행 | §2에서 해당 행 삭제 |
| **OpenAPI 계약 보호** | ⬜ | `core-guardrails` ⛔ §5 + `warn-breaking-change.sh` 훅 | §5 삭제, 훅 해제 |
| **생성 문서 검증** | ⬜ | `core-guardrails` ⛔ §1.6 | §1.6 삭제 |
| **스택 함정 메모** | ⬜ | `core-workflow` G1 ⚠️ 절 | ⚠️ 절 삭제 |
| **스택 리뷰어** | ⬜ | `core-workflow` G3 리뷰어 행 + 해당 에이전트 | 해당 행·에이전트 삭제 |

**⬜ = 미결정.** 하나라도 ⬜로 남아 있으면 하네스가 절반만 작동한다. 붙이는 첫 턴에 전부 ☑/❌로 바꾼다.

## 스택 팩

특정 언어·프레임워크 전용 규칙. 해당 스택이 아니면 **파일째 지운다.**

| 팩 | 파일 | 대상 |
|----|------|------|
| Java · Spring Boot | `spring-boot-java.md` · `java-comments.md` · `openapi-conventions.md` · `testing.md` · `agents/spring-reviewer.md` | Java 21 / Spring Boot / JPA / Gradle |

인프라 성격 규칙(클라이언트 전제·배포 토폴로지)은 스택이 아니라 **저장소 고유 사실**이라 팩에 넣지 않았다 — 견본 `examples/tripfit/client-platform.md`·`deployment.md`를 보고 프로젝트별로 새로 쓴다.

## 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-09-05 | 초안 — TripFit 하네스에서 슬롯 17개(경로 13·명령 4)·옵션 7개 추출 |
