# TDD 도입 — 승인 지점 방식

> 상태: Implemented (2026-10-05 승인·구현)
> MVP: In scope
> 관련 BR: N/A

## 목표

사람이 승인한 지점에서만 "실패하는 테스트 먼저"를 돌리는 TDD(테스트 주도 개발)를 하네스에 넣고, 모든 테스트에 적용되는 테스트 원칙을 스택 무관 규칙으로 둔다.

## 배경

- 지금 하네스에는 테스트를 **쓰는** 절차가 없다. `debug` 스킬의 "TDD 메모" 절이 "전용 스킬은 없다"고 적고, 원칙은 "유의미한 테스트만" 한 줄뿐이다
- 2026-10-05 조사 결과, 비슷한 하네스 대부분이 무차별 TDD 대신 "합의한 지점만"(oh-my-claudecode `tdd` 스킬) 또는 "위험도 비례"(junhyeong9812/claude-code-harness) 방식을 쓴다. 결정론 차단 훅으로 TDD를 강제하는 곳은 없다. tdd-guard는 판정에 LLM을 쓰고 JVM(Java 계열) 테스트 결과 수집기가 없다
- 테스트 원칙은 사용자가 지정한 참고 저장소(Central-MakeUs/ssoss-server, 커밋 `f3ad791`)의 테스트 철학에서 가져온다. 코드 형식·라이브러리는 가져오지 않는다
- 결정 근거: 2026-10-05 `ask` 인터뷰 10문항(결정 1~10)과 스펙 초안 검토 중 나온 결정 2건(11·12). 아래 "결정 기록" 표

## 결정 기록

| # | 질문 | 결정 |
|---|---|---|
| 1 | TDD 범위 | 승인된 지점만. "유의미한 테스트만" 유지 |
| 2 | 지점 선정 | AI가 스펙 Must 항목마다 "테스트 먼저 / 아님"과 근거를 제안하고, 사람이 G2에서 고친다. 표시가 없으면 테스트 먼저가 아니다 |
| 3 | 절차 위치 | 새 `tdd` 스킬. `specify`·`preflight`·`debug`에서 연결 |
| 4 | 테스트 작성자 | 기본은 구현하는 에이전트가 규칙을 지키며 쓴다. 통제 영역(`core-gates.md` §1 왼쪽 열)에 닿는 지점만 별도 서브에이전트가 쓴다 |
| 5 | 분리 형태 | 새 에이전트 파일 `test-writer` |
| 6 | 증거 | 완료 보고(채팅)와 `report.md`(있을 때)에 "스펙 항목 → 테스트 → RED 사유 → GREEN" 표. `preflight`가 승인 지점 수와 줄 수를 대조 |
| 7 | 참고 저장소 반영 | 원칙만: TDD 정석 T1~T6 + 테스트 철학 S1~S8 |
| 8 | 원칙 위치 | S1~S8은 새 `core-testing.md`(테스트 파일 접근 시 로드), T1~T6은 `tdd` 스킬 |
| 9 | Java 씨앗 충돌 | 같은 변경에서 충돌 3줄을 고친다. 스택 표기는 유지 |
| 10 | 버그 수정(C 트랙) | 기본은 재현 실패 테스트 먼저 + 되돌리면 실패하는지 확인. 테스트로 재현할 수 없으면 G2 원인 가설에 사유를 붙이고 재현 절차로 대신 |
| 11 | always-load 예산 | 상한 52,000B 유지. 연결 문구만큼 같은 파일의 중복 서술을 줄인다. 줄이는 문장은 구현 diff로 확인받는다 |
| 12 | C4 패턴 충돌 | `scripts/portability-patterns.txt`의 `testing\.md`를 `local-testing\.md`로 좁힌다. 규칙 이름은 `core-testing.md` 유지 |

## 원칙 본문

원칙 문장의 SSOT는 구현 파일이다 — TDD 순서 T1~T6은 `.claude/skills/tdd/SKILL.md` "원칙" 표, 테스트 원칙 S1~S8은 `.claude/rules/core-testing.md`. 이 스펙에 같은 표를 두지 않는다. 승인 시점(2026-10-05)에 합의한 뜻은 아래 한 줄씩이다.

- **T1~T6:** 실패 테스트부터 · 실패 사유 확인 · 최소 구현 · 초록일 때만 정리 · 테스트를 고쳐 통과시키지 않음 · 버그 테스트는 되돌리면 실패
- **S1~S8:** 결과만 확인 · 흐름은 실제 경로로 · 통제 못 하는 경계만 가짜 대역 · "조건이면 결과" 이름 · 실패도 계약 · 상태 변화까지 · 테스트끼리 격리 · 비싼 테스트 분리

## 요구사항

### Must Have

- [ ] **`tdd` 스킬 신설** — `.claude/skills/tdd/SKILL.md`. T1~T6, 지점별 루프, 통제 영역 지점에서 `test-writer` 호출, 증거 표 형식, 금지 목록
- [ ] **`test-writer` 에이전트 신설** — `.claude/agents/test-writer.md`. 입력은 스펙 경로·지점(Must 항목)·테스트 규칙 경로. 이번 변경의 구현 계획을 받지 않는다. 테스트 파일만 쓰고 프로덕션 코드는 쓰지 않는다
- [ ] **`core-testing.md` 신설** — `.claude/rules/core-testing.md`. S1~S8. `paths:`로 여러 언어의 테스트 파일 패턴에만 로드. 표기는 lang 팩에 맡긴다고 명시
- [ ] **`specify` 연결** — 스펙 템플릿에 "테스트 먼저 지점" 표(Must 항목 · 테스트 먼저 여부 · 근거)를 추가하고, 스킬 Steps에 "AI가 제안 → G2에서 사람이 수정"을 넣는다. 근거 기준: "어떤 코드 변경이 이 테스트를 깨뜨리나" · "통제 영역에 닿나"
- [ ] **`preflight` 연결** — 사후 모드에 "승인 지점 수 = 증거 표 줄 수" 대조 단계 추가
- [ ] **`debug` 연결** — 재현 실패 테스트를 `tdd` 절차로 먼저 쓰고 T6 확인을 붙인다. 테스트로 재현할 수 없으면 G2에 사유 + 재현 절차. "TDD 메모" 절 삭제. (구현 시 위치 정정: 실패 테스트는 원인 가설 승인 뒤인 Steps 3에 둔다 — `tdd` 0단계가 "승인된 원인 가설 = 지점"을 전제하기 때문)
- [ ] **`core-workflow.md` 연결** — G2 승인 대상(A = 스펙, 테스트 먼저 지점 포함)과 "구현" 절에 `tdd`·`core-testing.md` 참조 (always-load 예산 안에서, 결정 11). (구현 시 위치 정정: 트랙 표·G3 대신 이 두 곳에 둔다 — G3 절차의 SSOT인 `preflight`가 증거 대조를 맡아 G3 절에 중복하지 않는다)
- [ ] **`report.md` 골격** — `docs/templates/reference-doc.md` 작업 보고서에 "TDD 증거" 표 자리 추가
- [ ] **Java 씨앗 충돌 5줄 수정** — `examples/seeds/java-spring/rules/local-testing.md`의 "mock repository" · 슬라이스 기본 · "통합 (최소화)", 그리고 "완료 기준"의 "service 메서드마다 단위 테스트" · "`@WebMvcTest`"를 S2·S3에 맞게 고친다(뒤의 2줄은 구현 중 같은 충돌로 확인돼 추가). 실행 명령·Testcontainers·위치 표기는 유지. 테스트 이름 절에 S4 표기(한글 `@DisplayName` 문장) 추가
- [ ] **`_template` 연결** — `examples/seeds/_template/rules/lang-conventions.md` 테스트 규칙 절에 "원칙은 `core-testing.md`, 여기는 표기만" 추가
- [ ] **기각 사유 갱신** — `docs/out-of-scope/README.md` Superpowers 행의 "전면 TDD 충돌"을 "TDD는 승인 지점 방식으로 자체 도입(이 스펙)"으로 고친다. 플러그인 미채택 결론은 유지
- [ ] **이식성 패턴 좁히기** — `scripts/portability-patterns.txt` C4 줄의 `testing\.md` → `local-testing\.md`. C1 인프라 줄의 단독 `S3`도 원칙 번호 S3과 겹쳐 제품 문맥(`Amazon S3`·`S3 버킷`·`s3://` 등)으로 좁힌다(구현 중 확인)
- [ ] **목록·지도 갱신** — 스킬·에이전트·규칙 개수와 목록이 적힌 곳: `AGENTS.md` · `CLAUDE.md` · `README.md` · `.claude/rules/README.md`(트리와 "Edit/Write 없음" 문구) · `docs/harness/component-map.md` · `docs/harness/layer2-workflow-skills.md` · `docs/harness/README.md`(현재동작 요약) · `docs/harness-engineering.md` · `docs/harness/architecture-diagrams.md` · `docs/references.md`(Superpowers 기각 사유)

### Nice to Have

- [ ] `docs/workflow-cycle.md` 입문 문서에 TDD 단계 한 줄

### Out of Scope (이번 스펙에서 하지 않음)

- TDD 차단 훅 — 판정에 의미 해석이 필요해 `deny-*` 결정론 규약과 맞지 않는다
- 참고 저장소의 코드 형식(어노테이션 형식·메서드 이름 규칙·라이브러리·기반 클래스 구조), Mockito 금지 여부, 예외 단언 방식 통일, DB 정리 기준 — 스택별 세부라 각 프로젝트의 lang 팩이 정한다
- B 트랙(감사·리팩터) 변경 — 기존 테스트 통과가 이미 불변 조건이다
- `.agents/`·`.codex/` 미러 동기화 — 추적되지 않는 사용자 작업 디렉터리였다. 구현 뒤 사용자가 Claude Code만 쓰기로 해 직접 삭제했다(2026-10-05)

## 테스트 먼저 지점

| Must 항목 | 테스트 먼저 | 근거 |
|---|---|---|
| 전부 | 아님 | 문서·지침 변경이라 깨뜨릴 동작이 없다. 판정은 `scripts/verify.sh`(이식성·훅·문서 문체)가 맡는다 |

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 기존 훅 케이스 전부 통과 | `scripts/test-hooks.sh` |
| core 부품 계약(C1~C4) 유지 — 새 core 파일·스킬·에이전트에 스택 식별자·경로 리터럴 없음 | `scripts/check-portability.sh` |
| always-load 예산 52,000B 이하 | `scripts/check-portability.sh` |
| 기존 스킬의 다른 절차(사전 모드·운영 재현 등) 불변 | diff 검토 |

## 검증 시나리오

### 정상

- [ ] `core-testing.md`가 `paths:` frontmatter를 가져 always-load 합계에 들어가지 않는다
- [ ] 스펙 템플릿에 "테스트 먼저 지점" 표가 있고, 이 스펙이 그 표를 쓴다
- [ ] `debug`에서 "전용 스킬은 없다" 문구가 사라졌다 (`grep`)

### 엣지 · 실패

- [ ] 새 core 파일 본문에 `@`어노테이션·언어 이름·`docs/` 리터럴이 없다 (`check-portability.sh` 통과)
- [ ] `core-testing.md`라는 이름이 C4 패턴 `testing\.md`에 걸리지 않는다 ("리스크" 표 2행)

## 완료 기준

- [ ] `scripts/verify.sh` 통과
- [ ] 새 문서 3개와 50줄 이상 고친 문서는 `doc-reviewer` 리뷰
- [ ] 스킬·에이전트·규칙 개수를 바꾼 뒤 옛 개수로 저장소를 검색해 남은 곳이 없음
- [ ] `report.md` 작성 (`docs/reports/2026-10-05-tdd-adoption.md`)

## 리스크·미결정

| 항목 | 상태 | 비고 |
|------|------|------|
| always-load 예산 여유가 약 600B뿐 | 확정 (결정 11) | 착수 전 51,387B / 52,000B(2026-10-05 측정). 연결 문구만큼 같은 파일의 중복 서술을 줄인다 |
| C4 패턴 `testing\.md`가 `core-testing.md`에 걸린다 | 확정 (결정 12) | 씨앗 파일이 모두 `local-`로 시작하므로 좁혀도 core→팩 참조 금지 의도는 유지된다 |
| **`test-writer`는 쓰기 권한이 있는 첫 에이전트** | 확정(설명 정정) | 테스트 파일을 써야 해서 Write·Edit가 필요하다. 에이전트 도구 설정으로는 "이 파일은 읽지 마라" 같은 경로 제한을 걸 수 없다(인터뷰 5번 설명 정정). 분리는 ① TDD 순서상 RED 시점엔 새 구현이 아직 없다 ② 호출자가 구현 계획을 넘기지 않는다 ③ Bash를 주지 않는다로 건다 |
| 통제 영역 판정이 경계에 걸칠 때 | 확정 | `core-gates.md` §1 "두 열에 걸치면 통제 쪽" 규칙을 그대로 쓴다 |

## 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-10-05 | 초안 — `ask` 인터뷰 10문항 결과 |
| 2026-10-05 | 결정 11(예산)·12(C4 패턴) 반영 |
| 2026-10-05 | 구현 중 정정 — `debug`·`core-workflow` 연결 위치, 씨앗 충돌 5줄, C1 `S3` 패턴, 원칙 표를 SSOT 참조로 교체 |
