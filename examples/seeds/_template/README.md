# lang 팩 템플릿

`adopt` 3단계가 실측한 lang 축에 **맞는 씨앗이 없을 때** 채우는 골격이다. 씨앗은 특정 스택에서 검증된 규칙이고, 이 템플릿은 어느 스택이든 lang 팩이 갖춰야 할 **절의 목록**이다. Node·Python·Go 프로젝트에 하네스를 붙이면 `adopt`이 이 골격을 복사해 실측값으로 채운다 — 검증되지 않은 스택의 씨앗을 미리 지어 두지 않는 이유는 `docs/out-of-scope/README.md`에 있다.

## 파일

복사할 파일과 그 안에 채울 것이다.

| 파일 | 복사 위치 | 채우는 것 |
|---|---|---|
| `rules/lang-conventions.md` | `.claude/rules/local-{스택 이름}.md` | 아래 절 전부. `paths:` frontmatter를 그 언어 확장자로 |
| `agents/stack-reviewer.md` | `.claude/agents/local-{스택}-reviewer.md` (`name:`은 `{스택}-reviewer`) | 스택 리뷰어 — 정적 검사가 못 잡는 결함 목록. 플래그 "스택 리뷰어"를 켤 때만 |

복사 위치의 `local-` 접두사는 필수다 — `scripts/check-portability.sh`가 그 접두사로 local 층을 식별해 검사에서 뺀다. 훅은 템플릿에 없다. 포맷 훅(`local-auto-format-*.sh`)과 마이그레이션 차단 훅은 `{{포맷 명령}}`·"DB 마이그레이션 금지" 플래그가 실제로 있을 때 `java-spring/hooks/`를 본떠 만든다(역시 `local-` 접두사).

## lang 팩이 갖춰야 할 절

core 규칙이 `[플래그: X]` 배지로 부르는 절은 **이름을 그대로** 써야 한다. 아래 표의 절 이름은 `rules/lang-conventions.md`의 H2와 글자 단위로 같다. 배지가 가리키는 절이 없으면 플래그를 켤 수 없다.

| 절 | 왜 필요한가 | 부르는 core 절 |
|---|---|---|
| 패키지 · 모듈 구조 | 새 코드가 들어갈 자리 | `core-workflow` 구현 |
| 레이어 규칙 | 계층별 하는 일·하지 않는 일, 정적 검사가 이미 잡는 것 | `core-workflow` 구현 · 스택 리뷰어 |
| 주석 규칙 | 이 언어의 문서화 주석 문법·필드 주석 위치 (원칙은 `core-code-comments.md`) | `core-code-comments` · `core-reporting` 적용 안 함 표 |
| 테스트 규칙 | 실행 명령 · 위치 · "유의미한 테스트만" 기준 | `core-workflow` G3 · `preflight` |
| **같은 턴 즉시 갱신** — 에러 코드 · 권한 게이트·활동 기록 | 계약에 닿는 변경을 같은 턴에 끝내는 스택별 체크 표 | `core-guardrails` §1.7 · 플래그 2개 |
| **DB 스키마 정책** | 운영 데이터 유무에 따른 스키마 SSOT | 플래그 "DB 마이그레이션 금지" · `core-followup` ERD |
| **API 계약 변경** | 계약 diff 도구 · 사유 트레일러 · 프론트 알림 | 플래그 "API 계약 보호" · `core-workflow` G3 |
| **생성 문서 검증** | 소스 표기 ≠ 생성 문서 노출인 함정 | 플래그 "생성 문서 검증" · `core-guardrails` §1.6 |
| **스택 함정 메모** | 웹 예제 대다수와 다른 주 버전 등 | 플래그 "스택 함정 메모" · `core-workflow` G1 |

## 채우는 법

1. `rules/lang-conventions.md`를 복사해 대괄호 안내문을 실측값으로 바꾼다 — 추측이 아니라 빌드 파일·코드·CI에서 읽은 값만
2. 해당 없는 절은 지우지 않고 "이 프로젝트엔 없음 — 이유"를 한 줄 적는다 (플래그 ❌와 짝)
3. `harness-map.md` 스택 팩 표에 파일 이름을 적고, 능력 플래그 표의 "배지가 붙은 절" 열에 이 파일의 절 이름을 적는다
4. `scripts/check-doc-style.sh <파일>` 오류 0
