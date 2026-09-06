# Harness Map — 채운 예 (TripFit)

`.claude/rules/harness-map.md`를 실제 프로젝트에서 채우면 이런 모양이 된다. TripFit은 Java 21 / Spring Boot 4.1.0 / MySQL / Gradle 백엔드다.

## 경로 슬롯

| 슬롯 | TripFit 경로 |
|------|-------------|
| `{{스펙 저장소}}` | `docs/specs/{domain}/` |
| `{{현재동작 요약}}` | `docs/how-it-works.md` |
| `{{우선순위 SSOT}}` | `docs/product/release-milestones.md` |
| `{{아키텍처 개요}}` | `docs/architecture.md` |
| `{{스키마 SSOT}}` | `docs/architecture/erd.md` |
| `{{API 응답 규격}}` | `docs/architecture/api-response.md` |
| `{{API 문서}}` | `docs/api/README.md` |
| `{{제품 범위}}` | `docs/product/mvp.md` |
| `{{클라이언트 전제}}` | `docs/product/platform.md` |
| `{{용어집}}` | `docs/product/glossary.md` |
| `{{결정 기록}}` | `docs/decisions/` |
| `{{감사 로그}}` | `docs/audits/{domain}/` |
| `{{배포 SSOT}}` | `deploy/README.md` |

## 명령 슬롯

| 슬롯 | TripFit 명령 |
|------|-------------|
| `{{테스트 명령}}` | `./gradlew test` |
| `{{빌드 명령}}` | `./gradlew build` |
| `{{포맷 명령}}` | `./gradlew spotlessApply` |
| `{{의존성 조회}}` | `./gradlew dependencies` |

## 스택 옵션

| 옵션 | TripFit | 근거 |
|------|---------|------|
| DB 마이그레이션 금지 | ☑ 켬 | 상용 보존 데이터 없음 → 엔티티 + `ddl-auto`가 스키마 SSOT. Flyway 작성 금지 |
| 에러코드 enum 동시갱신 | ☑ 켬 | `{Domain}ErrorCode` + `TripFitException` |
| 권한·활동 어노테이션(AOP) | ☑ 켬 | `@TripActivity`(last_activity_at touch) · `@TripMemberOnly` / `@TripOwnerOnly` |
| OpenAPI 계약 보호 | ☑ 켬 | `oasdiff` + 커밋 트레일러 `Breaking-Change-Reason:` + Discord 알림 |
| 생성 문서 검증 | ☑ 켬 | springdoc — `@Schema` 존재만으로 노출을 단정하지 않고 `/v3/api-docs` 실물 확인 |
| 스택 함정 메모 | ☑ 켬 | Spring Boot 4.1.0 — 웹 예제 대다수가 3.x ([`g1-stack-trap.md`](g1-stack-trap.md)) |
| 스택 리뷰어 | ☑ 켬 | `spring-reviewer` — Java 3파일+·API·DB 변경 시 |

## 저장소 고유 규칙

슬롯으로도 옵션으로도 안 빠지는 **그 저장소만의 사실**은 `{프로젝트}-release.md`로 따로 뺀다. TripFit 판이 [`tripfit-release.md`](tripfit-release.md)다 — 스토어 심사 게이트, 릴리즈 축 3질문, 여행 일정 도메인 용어, 배포 도메인이 들어 있다.

이 파일은 `.claude/rules/`에 두면 always-load 된다. **다른 프로젝트로 옮길 때 가져가지 않는 유일한 규칙 파일**이다.
