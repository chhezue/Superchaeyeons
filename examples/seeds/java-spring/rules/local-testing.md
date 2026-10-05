---
paths:
  - "**/*Test.java"
  - "**/src/test/**"
---

# Testing

테스트를 어떻게 돌리고, 어디에 두고, 어떻게 표기하는지 정한 규칙이다. 무엇을 확인하는 테스트인가(S1~S8)는 `core-testing.md`, 테스트 먼저 순서는 `tdd` 스킬이 SSOT이고, 이 파일은 그 원칙의 이 스택 표기만 갖는다.

## 실행

```bash
./gradlew test          # 전체
./gradlew test --tests {루트패키지}.auth.service.FooServiceTest   # tdd RED 단계: 테스트 하나만
```

## 프로필

- 테스트는 `application-test.yml` — `ddl-auto: create-drop`
- `@SpringBootTest`(DB 붙는 통합 테스트)는 `@ActiveProfiles("test")` + `@Import(TestcontainersConfig.class)`로 실제 MySQL 8 컨테이너(Testcontainers `@ServiceConnection`)를 붙인다 — 로컬 Docker 필요, CI(GitHub Actions ubuntu-latest)는 기본 내장 Docker로 별도 설정 없이 동작
- MySQL·운영 DB에 테스트가 붙지 않도록 `@DataJpaTest` 등은 test 프로필 확인

## 구조

- `src/test/java/` — main과 동일 패키지 경로
- **통합(주력):** `@SpringBootTest` — 비즈니스 흐름은 실제 HTTP 진입점부터 DB까지 거쳐 확인한다(S2). 응답과 함께 저장된 상태도 확인한다(S6)
- **단위:** 도메인 모델·값 객체·계산 유틸처럼 입력과 출력만으로 판정되는 순수 로직만. 협력 객체가 필요하면 우리 코드는 실제 객체를 쓴다
- **슬라이스**(`@WebMvcTest`, `@DataJpaTest`)는 기본이 아니다 — 통합 테스트가 실측으로 너무 느려졌을 때만
- **경계 대역:** 가짜로 바꾸는 것은 외부 API 클라이언트·`Clock`·비동기 실행기뿐이다(S3). `@MockitoBean`을 쓰더라도 입력 고정에만 쓰고 `verify()`로 호출 횟수를 단언하지 않는다(S1)

## 네이밍·패턴

```java
@Test
void create{Domain}_whenInvalidRequest_throwsBadRequest() { ... }
```

- `given_when_then` 또는 `method_condition_expected` 스타일
- `@DisplayName`에 "조건이면 결과" 한글 문장(S4). 실패 케이스는 상태와 에러 코드를 문장에 넣는다. 같은 대상 메서드·엔드포인트는 `@Nested`로 묶는다
- 실패 케이스는 상태 코드와 함께 에러 코드를 `ErrorCode` enum 상수에서 꺼내 비교한다(S5)
- BR-* 규칙이 있으면 테스트 메서드명·`@DisplayName`에 BR 번호 참조 가능

## 완료 기준

- 스펙 "테스트 먼저 지점"은 `tdd` 증거 표로 확인한다
- 새 REST endpoint → `@SpringBootTest` 통합 테스트로 성공·거절 케이스 (단순 위임만 하는 service 메서드에 별도 단위 테스트를 만들지 않는다)
- `./gradlew test` 통과 후 PR/완료 보고
