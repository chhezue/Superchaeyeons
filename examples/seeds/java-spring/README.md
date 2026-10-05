# 씨앗 — Java · Spring Boot

Java 21 / Spring Boot / JPA / Gradle 백엔드용 lang 팩 **씨앗**이다. 하네스 배달물(`.claude/`)에는 들어 있지 않고, `adopt` 3단계가 실측한 lang 축이 이 스택과 맞을 때만 복사해서 시작한다. 복사한 뒤에는 그 프로젝트가 소유한다 — 마음껏 고쳐도 core는 갈라지지 않는다.

이 씨앗은 원본 백엔드 프로젝트(2026-07~09)에서 실제로 굴린 규칙이라 **그 저장소의 전제가 박혀 있다.** 도메인 이름과 도메인에 묶인 예시 값(상태 상수·기능·컬럼 이름 등)만은 자리표시자로 비워 두었다. 그래서 복사 직후 아래 "씨앗 대조" 표를 빌드 파일·코드와 맞춰 보고 다른 것은 고친다. baro-farm-be에서 이 대조 없이 복사해 세 번 같은 실수(therapi 의존성 없음 · Spring AI 버전 다름 · `ErrorCode` 기반 클래스 다름)를 한 것이 이 표가 있는 이유다.

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
| `hooks/local-warn-breaking-change.sh` | `.claude/hooks/` + `settings.json` `PreToolUse`/`Bash` 등록 | API 계약 보호 (❌면 복사하지 않는다) |
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
| 모든 PK·FK가 UUID v4(`CHAR(36)`), `Long`·`IDENTITY` PK 금지 | `local-spring-boot-java.md` "Entity Conventions" 절 | 엔티티 하나를 열어 `@Id` 타입·생성 전략과 DB 컬럼 타입 확인. 숫자 자동 증가 PK를 쓰는 프로젝트면 이 행을 고친다 | |
| 성공 응답이 `SuccessResponse<T>`로 감싸이고, 실패는 `GlobalExceptionHandler`가 `ErrorCode`로 변환 | `local-spring-boot-java.md` "레이어"·"API" 절 · `local-openapi-conventions.md` | 컨트롤러 반환 타입 하나와 전역 예외 처리기 확인 | |
| 로그인 사용자를 `@AuthorizedUser UUID userId`로 주입, 사용자 조회는 `UserLookupService.requireUser` 하나로 | `local-spring-boot-java.md` "레이어"·"교차관심사" 절 · `local-openapi-conventions.md` · `local-java-comments.md` | 인자 리졸버와 사용자 조회 서비스 존재 여부. 이름이 다르면 네 파일의 예시를 함께 고친다 | |
| Service는 facade + Command/Query로 나누고, 풀 DDD(도메인 주도 설계)·포트 인터페이스는 쓰지 않음 | `local-spring-boot-java.md` "Package Layout"·"SOLID / OOP 원칙" 절 | `{{결정 기록}}`의 아키텍처 결정과 기존 Service 구성. 결정 기록이 없으면 사용자에게 묻는다 | |
| Lombok은 Entity·`@ConfigurationProperties`·Service에만, Controller·DTO(record)에는 쓰지 않음 | `local-spring-boot-java.md` "Style" 절 | 빌드 파일 `lombok` 의존성과 기존 클래스 몇 개 | |
| DB가 MySQL 8이고 사용자 테이블명이 `users`(예약어 회피) | `local-spring-boot-java.md` "Entity Conventions" 절 · `local-testing.md` | 설정의 datasource URL·방언, 테스트 컨테이너 이미지 | |
| 프로필이 `application-{local\|dev\|test}.yml` 셋 | `local-spring-boot-java.md` "Configuration" 절 | `src/main/resources/`의 프로필 파일 목록 | |
| 도메인 이름·예시 값이 자리표시자로 비어 있음 — `{Domain}`·`{domain}`·`{DOMAIN}`·`{도메인}`, 상태 `{STATE_PENDING}`·`{STATE_ACTIVE}`, `{Feature}`·`{기능}`·`{column}`·`{선행 단계}` 등 | 규칙 4개와 `local-spring-reviewer.md`의 예시·표 | `grep -nE '(^\|[^{])\{(Domain\|domain\|DOMAIN\|STATE_\|Feature\|feature\|SubResource\|sub-resource\|Step\|column\|table\|derivedField\|[가-힣])' .claude/rules/local-*.md .claude/agents/local-*.md`로 찾아(`{{…}}` 슬롯은 제외된다), 예시 코드·어노테이션·Service 이름 속 자리표시자를 핵심 도메인의 실제 이름으로 바꾼다. `{domain}/dto/` 같은 경로 규약 표기는 그대로 둔다. 대응물이 없는 예시(권한 게이트 어노테이션 등)는 실물 쪽 이름으로 고치거나 해당 플래그를 ❌로 둔다 | |

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
