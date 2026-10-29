# lang 팩·씨앗 제거

> 상태: Approved (2026-10-29 사용자 승인)
> MVP: In scope
> 관련 BR: N/A

## 목표

스택별 규칙 묶음(lang 팩)과 그것을 복사해 주던 씨앗(`examples/seeds/`)을 없앤다. core 규칙이 프로젝트에 있을지 모르는 파일을 가리키지 않게 하고, 플러그인으로 배달할 하네스가 어느 프로젝트에서나 같은 뜻으로 읽히게 한다. 스택 훅이 하던 일은 [플러그인 배달](harness-plugin-delivery.md)의 설정 값으로 도는 공통 훅이 맡는다.

## 배경

- **플러그인 배달 스펙의 리스크 12가 [미정]이었다.** 씨앗은 `examples/`에 있어 플러그인에 실리지 않는다. 그러면 붙이는 프로젝트의 `init-harness`가 복사할 씨앗을 찾지 못한다
- **씨앗은 다른 프로젝트의 사본이다.** `java-spring` 씨앗은 원본 백엔드 프로젝트의 전제를 담고 있다. baro-farm-be에 대조 없이 복사해 같은 실수를 세 번 했고, 그 뒤로 붙일 때마다 "씨앗 대조" 표를 한 행씩 확인해야 한다([`harness-engineering.md`](../../harness-engineering.md) 2026-09-06 행)
- **복사한 뒤에는 갱신되지 않는다.** 이 저장소의 씨앗을 고쳐도 이미 붙인 프로젝트에는 전달되지 않는다. 플러그인 자동 업데이트의 목적과 맞지 않는다
- **실제 내용이 있는 lang 씨앗은 하나뿐이다.** 다른 스택은 `_template`으로 시작한다. 검증되지 않은 스택의 씨앗을 미리 짓는 일은 이미 기각됐다([`out-of-scope/README.md`](../../out-of-scope/README.md))
- **lang 팩의 두 역할 중 하나는 이미 다른 곳에 있다.** 코딩 관례(패키지 구조·표기·주석·테스트 이름)는 `core-workflow.md` "기존 스타일을 따른다"와 프로젝트 층(`AGENTS.md`·`local-*.md`)이 맡을 수 있다. 다른 역할인 능력 플래그 본문은 아래 "플래그 정리"로 옮긴다
- **2026-10-29 사용자 결정.** 씨앗을 빼고 lang 팩 개념도 지운다. `java-spring` 씨앗은 지우고, 트래커 안내 씨앗 `tracker-github`는 배달하지 않는 참고 자료로 남긴다. 이 스펙을 플러그인 배달 3단계(규칙 주입)보다 먼저 구현한다 — 규칙을 `plugin/rules/`로 옮긴 뒤 고치면 같은 파일을 두 번 고친다

### 지금 lang 팩·씨앗을 가리키는 곳 (2026-10-29 실측)

lang 팩·lang 축·스택 팩 언급은 22개 파일 46곳이다. 씨앗 언급은 아래 "변경 범위"에 파일별로 적었다.

| 층 | 파일 |
|---|---|
| core 규칙 | `core-guardrails.md` · `core-workflow.md` · `core-testing.md` · `core-code-comments.md` · `core-reporting.md` · `doc-writing.md` |
| map·목록 | `harness-map.md` · `.claude/rules/README.md` |
| 스킬 | `init-harness` · `verify-work` · `test-first` · `refactor-safely`(본문·`references/` 2개) · `write-spec/references/spec-template.md` |
| 에이전트 | `researcher` · `test-writer` |
| 검사기 | `check-portability.sh` · `portability-patterns.txt` · `test-hooks.sh` · `hook-cases.txt` |
| 견본·문서 | `AGENTS.template.md` · `AGENTS.md` · `README.md` · `docs/README.md` · `docs/harness-engineering.md` · `examples/baro/harness-map.md` |

### 고쳐야 하는 기존 결정

| 기존 기록 | 내용 | 이 스펙의 제안 |
|---|---|---|
| [`harness-slot-system-v2.md`](harness-slot-system-v2.md) (Implemented) | 4축 팩 · lang 팩 · 씨앗 · C4 팩 참조 검사 | 본문은 당시 기록으로 두고, 변경 이력에 "lang 팩·씨앗은 [`lang-pack-seed-removal.md`](lang-pack-seed-removal.md)로 제거" 한 줄을 더한다 |
| [`issue-tracker-neutral.md`](issue-tracker-neutral.md) | 트래커 안내 씨앗(`examples/seeds/tracker-github/`·`_template`) | 변경 이력에 골격과 참고 자료의 새 위치를 적는다. 트래커 안내 스킬 `local-track-issues`라는 구조는 그대로다 |
| [`harness-plugin-delivery.md`](harness-plugin-delivery.md) 리스크 12 · Must "씨앗을 플러그인에 실을지 정한다" | [미정] | "확정 — 씨앗 없음. 이 스펙 참고"로 고치고, 아래 "플러그인 배달 스펙에 더할 것"을 Must에 넣는다 |
| [`out-of-scope/README.md`](../../out-of-scope/README.md) "검증되지 않은 스택의 씨앗" 행 | 미리 짓지 않는다 | 행은 기록으로 두고 "씨앗 개념 자체를 2026-10-29 제거"를 덧붙인다 |

## 변경 범위

### ADDED

- `.claude/skills/init-harness/references/` 골격 2개 — 트래커 안내 골격(지금 `examples/seeds/_template/skills/local-track-issues/SKILL.md`)과 `dev.conf` 골격(지금 `examples/seeds/_template/dev.conf`). 스킬 폴더라 플러그인과 함께 배달된다
- `examples/tracker-github/` — 지금 `examples/seeds/tracker-github/`를 옮긴 참고 자료. 배달하지 않는다

### MODIFIED

- core 규칙·스킬·에이전트의 "lang 팩" 참조 → "프로젝트 관례(기존 코드, 있으면 `AGENTS.md`·`local-*.md`)". 아래 "참조 바꾸기" 표
- 능력 플래그 9개 → 3개(하네스 자기 수정 · Gemini 다듬기 · 생성 문서 검증). 아래 "플래그 정리" 표
- `init-harness` — 씨앗 복사·씨앗 대조 단계를 지운다. 트래커 안내와 `dev.conf`는 `references/` 골격에서 시작해 실측으로 채운다. 스택 규칙은 쓰지 않는다
- `check-portability.sh` — 씨앗 경로(`examples/seeds/**`)를 검사 대상과 훅 목록에서 뺀다. `portability-patterns.txt`의 C4(팩 참조) 분류를 지우고, C2·C3 머리의 "→ lang 팩"을 "→ 슬롯 또는 `local-*.md`"로 고친다
- `test-hooks.sh` — 씨앗 훅을 찾는 경로와 "복사하지 않은 씨앗 훅 건너뜀"을 지운다
- `examples/baro/harness-map.md` — 지운 플래그 행과 씨앗 문장을 뺀다. 채운 예로서 지금 map 모양과 같게 둔다

### REMOVED

- `examples/seeds/` 전체 — `java-spring/`(규칙 5 · 리뷰어 1 · 훅 3 · `dev.conf` · README) · `_template/`의 `rules/lang-conventions.md` · `agents/stack-reviewer.md` · `README.md` · `seeds/README.md`. 골격 2개는 ADDED 위치로 옮긴다
- `scripts/hook-cases.txt`의 씨앗 훅 케이스 12개
- 능력 플래그 7개 — 아래 "플래그 정리"의 삭제 행
- `.claude/rules/README.md`의 "스택 규칙(lang 팩)은 배달물에 없다" 문단 · 유지보수 7번 · "플래그를 켜거나 끌 때 할 일"의 씨앗 행 2개 · 작명 표 "씨앗에서 복사한 파일" 행
- `AGENTS.md` "씨앗 파일은 `local-*` 이름을 유지한다" 줄

## 요구사항

### Must Have

**플래그 정리**

| 플래그 | 정리 | 대신 맡는 곳 |
|---|---|---|
| DB 마이그레이션 금지 | 삭제 | 플러그인 배달의 `ASK_PATHS` — `init-harness`가 마이그레이션 폴더를 후보로 제안한다(그 스펙에 이미 있는 "마이그레이션 폴더 후보"). 막는 대신 승인 창을 띄운다. `core-guardrails.md` §2의 "(“DB 마이그레이션 금지” ❌)"는 "운영 데이터가 있는 프로젝트"로 쓴다 |
| 에러 코드 카탈로그 동시갱신 | 삭제 | `core-guardrails.md` §1.7 본문. 괄호의 "스택별 체크 표: lang 팩" 참조를 지운다 |
| 권한 게이트·활동 기록 동시갱신 | 삭제 | 같은 §1.7 |
| API 계약 보호 | 삭제 | 플러그인 배달의 커밋 승인 창 — `harness.conf` `CONTRACT_PATHS`에 맞는 파일이 스테이징돼 있으면 창의 이유에 적는다. `verify-work` 4단계는 `{{API 문서}}` 동기화로 남긴다 |
| 생성 문서 검증 | 유지 | `core-guardrails.md` §1.6에서 "(lang 팩 … 절)" 참조를 지우고 문장만으로 뜻이 통하게 한다 |
| 스택 함정 메모 | 삭제 | `core-workflow.md` G1 — 버전을 확인한 공식 문서를 보는 문장이 이미 있다 |
| 스택 리뷰어 | 삭제 | `verify-work` 7단계 → "프로젝트에 리뷰어 에이전트가 있으면 부른다" |

- [ ] 위 표대로 `harness-map.md` 능력 플래그 표와 그 플래그를 부르는 core·스킬 문장을 고친다
- [ ] `check-portability.sh`의 슬롯·플래그 정의-사용 대조가 통과한다(지운 플래그를 부르는 곳이 남지 않는다)

**참조 바꾸기**

| 지금 | 바꾼 뒤 |
|---|---|
| "패키지 구조·표기는 lang 팩"(`core-workflow.md` 구현) | "패키지 구조·표기는 기존 코드를 따른다" |
| lang 팩 "주석 규칙"(`core-reporting.md` · `core-code-comments.md`) | `core-code-comments.md`만. 언어별 문법은 기존 코드를 따른다 |
| lang 팩 테스트 규칙(`core-testing.md` · `test-first` · `test-writer`) | 프로젝트 관례 — 기존 테스트, 있으면 `local-*.md` |
| "파일 이름은 lang 팩 규칙이 알려 준다"(`researcher`) | "호출자 프롬프트가 알려 주거나 저장소에서 찾는다" |
| lang 팩이 정한 메커니즘·관례(`refactor-safely` 점검표·감사 템플릿) | 프로젝트가 이미 쓰는 메커니즘·관례 |
| "계약 diff 도구(lang 팩)"(`refactor-safely` · 스펙 템플릿) | "계약 diff 도구가 있으면" |
| `AGENTS.template.md` "주석·테스트 표기: {lang 팩 파일}" | 줄 삭제. 프로젝트 관례는 견본의 다른 절에 직접 적는다 |

- [ ] 위 표대로 고친 뒤 `.claude/`·`scripts/`·`AGENTS*.md`·`README.md`에 "lang 팩"·"스택 팩"·"씨앗"이 남지 않는다. 축 이름 "lang"(`harness-map.md` **축:** 줄)은 실측 기록이라 남긴다

**`init-harness`**

- [ ] 씨앗 복사(2단계)·트래커 씨앗(2-1단계)·`dev.conf` 씨앗(4단계)·체크리스트 "씨앗 대조" 행·보고의 "지운 스택 팩"을 지운다
- [ ] 트래커 안내는 `references/` 골격을 `.claude/skills/local-track-issues/`로 복사해 실측으로 채운다. 확인하지 못한 항목은 지금처럼 "(확인 못 함 — 이유)"로 남긴다
- [ ] `dev.conf`는 `references/` 골격을 복사해 CI 워크플로의 실제 명령으로 채운다
- [ ] 프로젝트 고유 관례를 적을 곳이 필요하면 `local-*.md`를 만들 수 있다는 한 줄을 남긴다. `init-harness`가 스택 규칙을 지어 쓰지는 않는다

**같은 변경에서 고칠 문서**

- [ ] 위 "고쳐야 하는 기존 결정" 네 곳
- [ ] `{{현재동작 요약}}`(`docs/harness/README.md`) — 플래그가 줄었고 스택 규칙이 자동으로 들어가지 않는다는 것을 쉬운 말로 (`core-guardrails.md` §3)
- [ ] `README.md` 9단계 행 · "디렉터리 안내" 표 · `docs/README.md` 붙이는 순서 · `docs/harness-engineering.md` 씨앗 문단과 "숫자로 보는 현재" · `doc-writing.md` "씨앗은 `init-harness`의 씨앗 대조 표가" 문장

**플러그인 배달 스펙에 더할 것** (이 스펙 구현과 같은 PR에서 amend만 한다. 훅 구현은 그 스펙의 단계에서 한다)

- [ ] 리스크 12 확정과 Must "씨앗" 항목 교체
- [ ] 커밋 승인 창 범주에 `CONTRACT_PATHS` 표시(위 "플래그 정리")
- [ ] 공통 포맷 훅 — `PostToolUse`에서 고친 파일이 `FORMAT_PATHS`에 맞으면 `FORMAT_CMD`를 돌린다. 그 스펙이 git 훅 `pre-commit`을 지우면서 포맷을 맡을 곳이 비어 있다
- [ ] `harness.conf` 키 목록에 `CONTRACT_PATHS` 추가

### Nice to Have

- (없음)

### Out of Scope (이번 스펙에서 하지 않음)

- 이미 씨앗을 복사해 쓰는 프로젝트(baro-farm-be)의 `local-*` 파일 정리 — 그 프로젝트가 소유한다. 플러그인 전환 때 `init-harness` 재동기화에서 지운 플래그만 정리한다
- 공통 훅(승인 창·포맷) 구현 — 플러그인 배달 스펙이 한다
- 축 이름 "lang"을 없애는 것 — 슬롯 값을 고르는 근거로 남는다

## 테스트 먼저 지점

| Must 항목 | 테스트 먼저 | 근거 |
|---|---|---|
| 플래그 정리 | 아님 | `check-portability.sh`의 정의-사용 대조가 판정한다. 지운 플래그를 부르는 문장이 남으면 이미 실패한다 |
| 참조 바꾸기 | 아님 | 문서 문장 교체다. 남은 언급은 완료 기준의 `grep`이 판정한다 |
| `init-harness` | 아님 | 스킬 문서다. 통제 영역에 닿지 않는다 |
| 검사기·훅 테스트에서 씨앗 경로 빼기 | 아님 | 지우는 변경이다. `scripts/dev.sh test` 통과와 케이스 수 감소(12개)로 판정한다 |
| 플러그인 배달 스펙 amend | 아님 | 문서다 |

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 이 저장소의 훅 동작이 바뀌지 않는다 — 씨앗 훅은 이 저장소에 등록돼 있지 않다 | `scripts/test-hooks.sh`의 배달 훅 케이스 결과가 전과 같다(씨앗 케이스만 빠진다) |
| core에 프로젝트 고유 사실이 없다 | `scripts/check-portability.sh` |
| `deny-*` 훅의 판정 불가 = 차단 규약 | `scripts/test-hooks.sh` |
| 남는 플래그 3개의 동작이 바뀌지 않는다 | 해당 절 diff 리뷰 |

## API / 인터페이스

API 없음. 바뀌는 접점은 `harness-map.md` 능력 플래그 표(행 9개 → 3개)와 `init-harness`가 읽는 골격 위치(`examples/seeds/_template/` → `.claude/skills/init-harness/references/`)다.

## 검증 시나리오

### 정상

- [ ] `scripts/dev.sh test` 통과
- [ ] `grep -rn "lang 팩\|스택 팩\|씨앗\|examples/seeds" .claude scripts AGENTS.md AGENTS.template.md README.md docs/README.md`가 아무것도 찾지 않는다
- [ ] `init-harness` 본문만 읽고 트래커 안내와 `dev.conf`를 어디서 시작하는지 알 수 있다(`references/` 경로가 실제로 있다)

### 엣지 · 실패

- [ ] 지운 플래그 이름 하나를 core에 다시 써 넣으면 `check-portability.sh`가 실패한다
- [ ] `hook-cases.txt`에서 씨앗 케이스가 빠진 뒤 "건너뜀" 줄이 출력되지 않는다

## 완료 기준

- [ ] `scripts/dev.sh test` 통과
- [ ] 위 검증 시나리오 전부
- [ ] `REMOVED` 항목 실제 삭제 확인 — `examples/seeds/` 없음 · 씨앗 케이스 0개 · 지운 플래그 행 없음
- [ ] "고쳐야 하는 기존 결정"과 "같은 변경에서 고칠 문서"가 같은 PR에 있다

## 리스크·미결정

| 항목 | 상태 | 비고 |
|------|------|------|
| 1. 검증된 스택 지침을 잃는다 | 확정 (2026-10-29 사용자 · 감수) | Spring의 `ErrorCode` 작성법 같은 지침이 새 프로젝트에 자동으로 들어가지 않는다. 필요한 프로젝트는 `local-*.md`에 직접 적는다. 지운 파일은 git 이력에서 꺼낼 수 있다 |
| 2. 마이그레이션 쓰기가 차단에서 승인 창으로 바뀐다 | 확정 (이 스펙 제안) | 씨앗 훅의 차단 메시지도 "정말 필요하면 사용자에게 먼저 확인"이었다. 승인 창이 그 확인을 사용자가 직접 누르는 것으로 바꾼다. 플러그인 배달 전까지는 이 장치가 없지만, 지금 이 저장소와 새 프로젝트에도 씨앗 훅은 등록돼 있지 않아 줄어드는 보호는 없다 |
| 3. 플러그인 배달 전 공백 | 확정 (2026-10-29 사용자 · 감수) | 이 스펙과 플러그인 배달 5단계(승인 창) 사이에 새로 붙이는 프로젝트는 마이그레이션·계약 경로 알림을 받지 못한다. 그 사이 새 프로젝트를 붙일 계획이 없다 |

## 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-10-29 | 승인 — 리스크 3을 감수로 확정했다 |
| 2026-10-29 | 초안 — 사용자가 씨앗·lang 팩 제거 방향을 승인했다. 플래그 정리 표 · 참조 바꾸기 표 · 플러그인 배달 스펙에 더할 것 |
