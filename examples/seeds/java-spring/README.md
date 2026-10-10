# 씨앗 — Java · Spring Boot

Java 21 / Spring Boot / JPA / Gradle 백엔드용 lang 팩 **씨앗**이다. 하네스 배달물(`.claude/`)에는 들어 있지 않고, `adopt` 3단계가 실측한 lang 축이 이 스택과 맞을 때만 복사해서 시작한다. 복사한 뒤에는 그 프로젝트가 소유한다 — 마음껏 고쳐도 core는 갈라지지 않는다.

이 씨앗은 TripFit(2026-07~09)에서 실제로 굴린 규칙이라 **그 저장소의 전제가 박혀 있다.** 그래서 복사 직후 아래 "씨앗 대조" 표를 빌드 파일·코드와 맞춰 보고 다른 것은 고친다. baro-farm-be에서 이 대조 없이 복사해 세 번 같은 실수(therapi 의존성 없음 · Spring AI 버전 다름 · `ErrorCode` 기반 클래스 다름)를 한 것이 이 표가 있는 이유다.

## 무엇을 어디에 복사하나

`adopt` 3단계가 이 표대로 복사한다. 훅 행은 플래그가 ☑일 때만.

| 씨앗 파일 | 복사 위치 | 켜는 플래그 |
|---|---|---|
| `rules/local-spring-boot-java.md` | `.claude/rules/` | 에러 코드 카탈로그 동시갱신 · 권한 게이트·활동 기록 동시갱신 · DB 마이그레이션 금지 |
| `rules/local-openapi-conventions.md` | `.claude/rules/` | API 계약 보호 · 생성 문서 검증 |
| `rules/local-java-comments.md` · `rules/local-testing.md` | `.claude/rules/` | — |
| `rules/local-g1-stack-trap.md` | `.claude/rules/` (본문을 lang 규칙에 합쳐도 된다) | 스택 함정 메모 |
| `agents/local-spring-reviewer.md` | `.claude/agents/` | 스택 리뷰어 |
| `hooks/local-deny-db-migration.sh` | `.claude/hooks/` + `settings.json` `PreToolUse`/`Write\|Edit` 등록 | DB 마이그레이션 금지 (❌면 복사하지 않는다) |
| `hooks/local-auto-format-java.sh` | `.claude/hooks/` + `settings.json` `PostToolUse`/`Edit\|Write` 등록 | — (`{{포맷 명령}}`이 있을 때만) |

훅을 복사하면 `scripts/hook-cases.txt`의 해당 케이스도 살아난다 — `test-hooks.sh`는 `.claude/hooks/`와 `examples/seeds/*/hooks/` 둘 다에서 훅을 찾는다.

## 씨앗 대조 — 복사 직후 확인할 전제

다음 표를 프로젝트 실물과 한 행씩 대조한다. 같으면 "일치 — 근거 파일"을, 다르면 씨앗 본문을 고친 뒤 "수정 — 근거 파일"을 "이 프로젝트" 열에 적는다. 빈 칸으로 남은 전제는 확인하지 않은 것이다.

| 씨앗이 전제하는 것 | 어디에 박혀 있나 | 확인 방법 | 이 프로젝트 |
|---|---|---|---|
| Spring Boot 4.x / Java 21 | `local-spring-boot-java.md` 머리 · `local-g1-stack-trap.md` | 빌드 파일의 플러그인·toolchain 버전 | |
| `springdoc` + `therapi-runtime-javadoc`으로 Javadoc → OpenAPI 설명 | `local-openapi-conventions.md` | 빌드 파일 의존성에 `therapi` 존재 여부 | |
| 에러 코드가 `ErrorCode` 인터페이스 구현 enum이고 상수마다 `@Schema` | `local-spring-boot-java.md` "ErrorCode enum" 절 | 실제 에러 코드 클래스 하나를 열어 기반 타입·어노테이션 확인 | |
| 권한 게이트가 `@…Only` 인터셉터, 활동 시각이 AOP `@…Activity` | `local-spring-boot-java.md` "교차관심사" 절 | 인터셉터·Aspect 클래스 존재 여부 | |
| 스키마 SSOT = 엔티티 + `ddl-auto`, 마이그레이션 도구 없음 | `local-spring-boot-java.md` "DB 스키마 정책" 절 · `local-deny-db-migration.sh` | `src/main/resources/db/migration/` 존재 여부 · 빌드 파일에 `flyway`·`liquibase` 의존성 · 설정의 `ddl-auto` 값. **운영 데이터가 있으면 플래그 ❌** | |
| `oasdiff`로 OpenAPI 스냅샷 diff, 프론트가 스냅샷을 계약으로 씀 | `local-openapi-conventions.md` "API 계약 변경" 절 · `local-testing.md` | `docs/api/openapi.json`(또는 다른 스냅샷 경로) 존재 · CI 워크플로에 `oasdiff` 단계 · `OpenApiSpecExportTest` 클래스. 없으면 플래그 ❌ | |
| Spotless(Eclipse 포맷터) | `local-auto-format-java.sh` · `local-spring-boot-java.md` | 빌드 파일 spotless 플러그인 | |
| 아키텍처 규칙을 ArchUnit 테스트가 검증 | `local-spring-boot-java.md` · `local-spring-reviewer.md` 제외 목록 | `src/test/java/**/architecture/*Test.java` 존재 · 빌드 파일에 `archunit` 의존성. 없으면 리뷰어 제외 목록을 비운다 | |
| 테스트: JUnit 5 + Testcontainers, 프로필 `test` | `local-testing.md` | 빌드 파일에 `testcontainers` 의존성 · `src/test/resources/application-test.yml` 존재 | |

## 이 씨앗이 채우는 lang 팩 절

`../_template/README.md`가 모든 lang 팩에 요구하는 절과 이 씨앗의 대응이다. 절마다 한 행씩, 1:1이다.

| 템플릿 절 | 이 씨앗 |
|---|---|
| 패키지 · 모듈 구조 | `local-spring-boot-java.md` "Package Layout" 절 |
| 레이어 규칙 | `local-spring-boot-java.md` "레이어" 절 |
| 주석 규칙 | `local-java-comments.md` |
| 테스트 규칙 | `local-testing.md` |
| API 계약 변경 | `local-openapi-conventions.md` "API 계약 변경" 절 |
| 생성 문서 검증 | `local-openapi-conventions.md` "생성 문서 검증" 절 |
| 같은 턴 즉시 갱신 (에러 코드 · 권한·활동) | `local-spring-boot-java.md` "같은 턴 즉시 갱신" 절 |
| DB 스키마 정책 | `local-spring-boot-java.md` "DB 스키마 정책" 절 |
| 스택 함정 메모 | `local-g1-stack-trap.md` |
| 스택 리뷰어 | `agents/local-spring-reviewer.md` |
