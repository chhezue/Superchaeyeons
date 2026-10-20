# 하네스 전수 감사 — BASELINE FULL AUDIT (2026-09-07)

이 저장소의 AI 에이전트 하네스(규칙·스킬·에이전트·훅·검사기)가 실제 코딩 에이전트에게 컨텍스트·통제·검증·복구·증거를 얼마나 제공하는지를 문서가 아니라 실행으로 검증한 기준선 보고서다. 같은 프롬프트로 다시 감사하면 이 파일과 비교한다(REPEAT AUDIT). 감사 대상 커밋은 `0ebceb8`, 실행 환경은 Claude Code 2.1.x(desktop), macOS, python3 3.14, bash, gh 2.86이다. 검증하지 못한 항목은 UNVERIFIED로 표시했다.

## 요약 (Executive Summary)

이 하네스는 "판단은 LLM에게, 불변식은 스크립트에게"라는 원칙을 실제로 구현한 드문 사례다. 부품 계약 검사기·훅 규약 테스트·문서 스타일 검사기·`verify.sh` 래퍼·git 훅이 전부 실행되고 exit code로 판정하며, 이번 감사에서 항상 통과했다(케이스 54 → 작업 후 62). 컨텍스트 예산은 실측 14.8k 토큰(o200k 프록시)으로 상한 래칫이 커밋을 막는다. 규칙은 항상 로드 8개와 파일 접근 시 로드 3개로 나뉘어 실제로 그렇게 전달되는 것을 이 세션의 시스템 프롬프트로 확인했다.

가장 큰 약점은 통제의 "겉과 속"이 다른 지점 세 곳이다. 첫째, `Stop` 훅은 Write/Edit 도구 호출만 코드 수정으로 세므로 Bash(`sed -i`·heredoc)로 고친 뒤 "완료"라고 하면 그대로 통과한다 — 이 세션처럼 Bash 편집을 권장하는 모드에서는 사실상 무동작이다. 둘째, `core-guardrails.md`는 ".env·API 키 커밋, 운영 DB 파괴를 훅이 차단한다"고 적지만 훅에는 그 패턴이 없다. 셋째, `settings.json`에서 훅 등록을 지우는 커밋을 pre-commit이 잡지 못한다(약화·삭제는 잡는다). 그 밖에 훅 스크립트 본문은 세션 중 수정 즉시 효력이 생겨 에이전트가 스스로 풀 수 있고, `docs/harness/` 서술 문서는 배달하지 않는다고 못 박았지만 저장소 안에서 v1 시절 CI·oasdiff·훅 4개를 현재형으로 말한다.

canonical task(하네스가 스스로 예시로 든 `git clean -f` 차단 추가)는 인간 개입 없이 끝났고 독립 검증을 통과했다. 다만 하네스 규칙대로면 G2 승인(스펙)과 커밋 승인 두 번은 사람이 끊어야 한다 — 이것은 결함이 아니라 설계다.

## 1. 하네스 인벤토리

`Repository file → Runtime → Agent context` 전달 경로를 이 세션에서 실측한 표다. "전달 확인"은 시스템 프롬프트·훅 발화·transcript로 직접 관측한 것이다.

| Path | Type | Purpose | Auto-loaded? | Invocation | Criticality | 전달 확인 |
|------|------|---------|--------------|------------|-------------|-----------|
| `CLAUDE.md` | instruction | `@AGENTS.md` import + Claude Code 보충 | 예 | 세션 시작 | High | 시스템 프롬프트에 본문 있음 |
| `AGENTS.md` | instruction | 프로젝트 지도·작업 규칙 | 예 (`@` import) | 세션 시작 | High | 시스템 프롬프트에 본문 있음 |
| `.claude/rules/core-*.md` 7개 + `harness-map.md` | rule | STOP·게이트·워크플로·범위·후속·도구·보고·슬롯 값 | 예 | 세션 시작 | High | 8개 전부 시스템 프롬프트에 있음 |
| `.claude/rules/core-code-comments.md` | rule (`paths:` 소스 확장자) | 주석 원칙 | 조건부 | 소스 파일 접근 | Medium | 이 세션엔 미로드(소스 없음) — 설계대로 |
| `.claude/rules/doc-writing.md` | rule (`paths:` md) | 문서 작성 규칙 | 조건부 | md 접근 | Medium | 미로드 확인(항상 로드 목록에 없음) |
| `.claude/rules/README.md` | rule (`paths:` .claude/**) | 구조 인덱스 | 조건부 | 하네스 파일 접근 | Low | 미로드 확인 |
| `.claude/skills/*/SKILL.md` 8개 | skill | adopt·ask·specify·safe-refactor·debug·preflight·defer·retro | description만 | 모델·사용자 | High | 스킬 목록에 8개 전부 등록됨 |
| `.claude/agents/researcher.md`·`doc-reviewer.md` | subagent | G1 조사 · G3 문서 리뷰 | description만 | `Agent` 툴 | Medium | 에이전트 목록에 2개 등록됨 |
| `.claude/hooks/deny-dangerous-bash.sh` | hook PreToolUse/Bash | 파괴 명령 차단 | 항상 | 도구 호출 전 | High | 이 세션에서 8회 차단 관측 |
| `.claude/hooks/deny-out-of-scope-write.sh` | hook PreToolUse/Write\|Edit | 범위 밖 쓰기 차단 | 항상 | 도구 호출 전 | Low (SCOPE=. 무동작) | 무동작 실측(`/etc/hosts`도 exit 0) |
| `.claude/hooks/ask-open-request.sh` | hook UserPromptSubmit | 열린 요청 알림 주입 | 항상 | 프롬프트 제출 | Medium | 이 감사 프롬프트에 주입 관측 |
| `.claude/hooks/deny-unverified-completion.sh` | hook Stop | 미검증 완료 선언 되돌림 | 항상 | 턴 종료 | High | 실 transcript로 실행 확인(exit 0) |
| `.claude/hooks/warn-unfilled-map.sh` | hook SessionStart | 미결정 슬롯 경고 | 항상 | 세션 시작 | Low | 모의 map으로 경고 문구 확인 |
| `.claude/settings.json` | config | 이벤트→훅 매핑 5개, permissions 없음 | 예 | — | High | 훅 발화로 간접 확인 |
| `.claude/settings.local.json` | config | 개인 allowlist 2건 (gitignored) | 예 (로컬만) | — | Low | 배달되지 않음 |
| `scripts/verify.sh` | script | `{{테스트 명령}}` 래퍼 | 아니오 | 에이전트 Bash | High | 실행 exit 0 |
| `scripts/check-portability.sh` + `portability-patterns.txt` | script | 부품 계약·예산 래칫 | 아니오 | verify·pre-commit | High | 실행 확인 |
| `scripts/test-hooks.sh` + `hook-cases.txt` + `hook-fixtures/` | script | 훅 규약 테스트 | 아니오 | verify·pre-commit | High | 실행 확인 |
| `scripts/check-doc-style.sh` + `doc-style-patterns.txt` | script | 문서 스타일 | 아니오 | verify·pre-commit | Medium | 실행 확인 |
| `scripts/adopt-probe.sh` | script | adopt 1단계 실측 | 아니오 | adopt 스킬 | Medium | 실행 exit 0, 64줄 출력 |
| `scripts/git-hooks/pre-commit`·`commit-msg` | git hook | 커밋 전 검사·메시지 형식 | 설치 후 | git commit | High | 격리 클론에서 차단 확인 |
| `.github/CONTRIBUTING.md` | knowledge | Git 컨벤션 견본 | 아니오 | 슬롯 참조 | Medium | — |
| `docs/templates/`·`docs/README.md`·하위 README | knowledge | 산출물 등록부·폴더 인덱스 | 아니오 | 규칙 참조 | Medium | — |
| `docs/harness/*`·`harness-engineering.md`·`docs/specs/cross-cutting/harness-slot-system-v2.md` | knowledge (이력) | 설계 근거 | 아니오 | 사람 | Low (배달 안 함) | — |
| `examples/seeds/`·`examples/tripfit/`·`examples/baro/` | seed/example | lang 팩 씨앗·채운 예 | 아니오 | adopt | Medium | — |
| CI workflows / MCP(`.mcp.json`) / `permissions.deny` | — | 없음 | — | — | — | 부재 확인 |

**Constraint Propagation Failure 후보:** 문서상 존재하나 런타임에 전달되지 않는 것은 없다. 반대로 문서가 "훅이 차단한다"고 말하는데 훅에 없는 항목이 있다(§3 ROT-1).

## 2. 컨텍스트와 발견 가능성

**진입점.** `CLAUDE.md`(1.8KB)가 `@AGENTS.md`를 불러오고 Claude Code 전용 보충 6줄만 갖는다. `AGENTS.md`는 표 하나로 경로→내용을 잇는 navigation map이고, 세부는 `harness-map.md`·`.claude/rules/README.md`·`docs/harness/component-map.md`로 progressive disclosure 한다. 문서 확인 순서(`core-workflow.md` 진입 4)가 명시돼 있다. 적절하다.

**중복·충돌.** (1) `core-workflow.md`는 "3파일+ → `specify` 스펙 → 승인"인데 `docs/harness/component-map.md` "훅 하나 추가 순서" 예시는 4파일을 스펙 없이 5단계로 고친다 — 같은 작업에 두 절차. (2) `core-gates.md` §3과 `core-guardrails.md` "환경 금지" 목록이 겹치되 후자는 훅에 없는 항목을 포함한다. (3) `retro` 스킬이 `.claude/rules/README.md`의 "agent-type 훅 관련 교훈" 절을 가리키지만 그 이름의 절은 없다(내용은 "advisory 훅은 command-type으로" 문단에 있음). (4) `harness-map.md` 9.5KB 중 `(없음)` 슬롯 10행과 설명 문단이 항상 로드된다.

**컨텍스트 예산 (tokenizer: tiktoken `o200k_base` — Claude 토크나이저는 비공개라 프록시. 저장소 자체 추정은 bytes/2.5).**

| File | Tokens(o200k) | Bytes | Auto-loaded | Necessity |
|------|---:|---:|---|---|
| `core-workflow.md` | 3,505 | 11,984 | 예 | High — 트랙·게이트 SSOT. 트랙 표 "Claude Code 도구" 열과 G3 항목은 압축 여지 |
| `harness-map.md` | 2,960 | 9,554 | 예 | Medium — 값 표는 필수, 규칙 5개·축 설명·"쓰는 곳" 열은 README로 이동 가능 (~1,000 토큰) |
| `core-guardrails.md` | 2,180 | 7,464 | 예 | High |
| `AGENTS.md` | 1,464 | 4,914 | 예 | High |
| `core-gates.md` | 1,368 | 4,870 | 예 | High |
| `core-followup.md` | 865 | 2,964 | 예 | Low-Medium — 완료 후에만 필요. `paths:` 없이도 스킬로 옮길 수 있음 |
| `core-tools.md` | 797 | 3,017 | 예 | Medium |
| `core-reporting.md` | 648 | 2,485 | 예 | Medium |
| `CLAUDE.md` | 534 | 1,768 | 예 | High |
| `core-scope.md` | 491 | 1,804 | 예 | Low-Medium — `[미정]` 처리 3문단 |
| **합계 always-load** | **14,812** | **50,824** | | 상한 52,000B(≈ 20,800 토큰 추정치와 대비 o200k 실측은 그보다 낮음) |
| `.claude/rules/README.md` | 4,827 | 16,701 | 조건부 | Medium |
| `doc-writing.md` | 3,200 | 11,618 | 조건부 | Medium |
| `core-code-comments.md` | 2,271 | 8,320 | 조건부 | Medium |
| 스킬 11파일 (본문) | 14,666 | 52,541 | 호출 시만 | — (description 합계 572 토큰만 상시) |
| 에이전트 2 | 2,959 | 10,947 | 서브에이전트만 | — |

- Total auto-loaded: **14,812 토큰** (o200k) · Total harness tokens(규칙+스킬+에이전트): **42,735**
- Potentially removable from always-load: 약 **2,000~2,500 토큰** — `harness-map.md` 설명·"쓰는 곳" 열, `core-followup.md`·`core-scope.md`를 스킬/조건부로, `core-workflow.md` 트랙 표의 도구 열
- High-value: `core-guardrails`·`core-gates`·`core-workflow` 게이트 절·`harness-map` 값 표. Low-value: `(없음)` 10행의 이유 서술, `harness-map.md` 규칙 5개(README 중복)
- UNVERIFIED: Claude 실제 토크나이저 기준 수치. 한국어는 o200k보다 토큰이 많이 잡힐 수 있어 상한 20,800 추정이 보수적 근사로는 타당하다

## 3. 무결성·rot

검사 방법: 모든 md·sh·json·txt에서 백틱 경로·마크다운 링크 1,732건을 추출해 존재 여부를 기계 검사했고, 설계 문서 8개는 서브에이전트가 전문을 읽어 현재 저장소 실물과 대조했다.

**ROT-1 (High)** — File: `.claude/rules/core-guardrails.md` · Line: 62 · Claim: "환경 금지 (훅이 차단): `git push --force` · `rm -rf` 류 · `git reset --hard` · 운영 DB 파괴 · `.env`·API 키 커밋" · Actual: 훅 정규식에 `.env`·API 키·DB 파괴 패턴 없음. 실측 `git add .env && git commit` → exit 0, `psql -c 'DROP DATABASE prod'` → exit 0, `docker compose down --volumes` → exit 0 · Evidence: `.claude/hooks/deny-dangerous-bash.sh:29`, 감사 probe 52건 · Impact: 항상 로드되는 규칙이 존재하지 않는 결정론적 보호를 약속한다. 에이전트는 "훅이 잡을 것"이라 믿고 덜 조심한다.

**ROT-2 (Medium)** — File: `docs/harness/component-map.md` · Line: 105 vs 51 · Claim: "always-load 합계 ≤ 65,000B(래칫)" · Actual: `scripts/check-portability.sh:28` 기본값 52,000B; 같은 문서 51행은 52,000B · Evidence: 두 행 인용 · Impact: 현행 지도 문서 안에서 상수가 둘. 같은 값이 `docs/specs/cross-cutting/harness-slot-system-v2.md` 110·562·588행과 `scripts/check-portability.sh:26` 주석에도 65,000으로 남아 있다.

**ROT-3 (Medium)** — File: `docs/harness/README.md` · Line: 20, 32, 44, 61 · Claim: Layer 4 = "CI + script (`.github/workflows/`)", "L4 CI(계약 diff)", "oasdiff 3중 감지 구축" (현재형) · Actual: `.github/workflows/` 없음, `oasdiff` 없음, `scripts/notify-api-breaking-change.sh` 없음 · Evidence: `ls .github/workflows` → No such file · Impact: 배달하지 않는 문서라 낮지만 저장소 안에서 에이전트가 읽으면 CI가 검증한다고 오판한다. `layer4-api-contract-safety.md` 21~24행 링크 4개, `layer1:82`, `layer2:132,135`, `harness-engineering.md:66,100,102,130` 링크가 깨져 있다.

**ROT-4 (Medium)** — File: `docs/harness/layer3-deterministic-hooks.md` · Line: 19-26, 53-96 · Claim: 훅 8개가 `settings.json`에 등록, `PostToolUse` 자동 포맷 흐름 · Actual: 등록 5개, `"PostToolUse": []` · Evidence: `.claude/settings.json` · Impact: 흐름도가 실제 등록 훅(`deny-out-of-scope-write.sh`)을 빠뜨리고 미등록 훅을 그린다.

**ROT-5 (Medium)** — File: `docs/harness/architecture-diagrams.md` · Line: 1, 82, 112-115, 203-204 · Claim: 스킬 5·훅 4·트랙 3·규칙 7+8, EC2·MySQL·Redis 배포, "100% 팩트" · Actual: 스킬 8·훅 5·트랙 4·규칙 8+3, 배포 없음 · Evidence: 인벤토리 표 · Impact: v2 반영 노트가 없는 유일한 설계 문서. 외부 공개용 다이어그램이 저장소 실물과 전부 다르다.

**ROT-6 (Low)** — File: `docs/harness-engineering.md` · Line: 58, 70, 106, 142 · Claim: "서브에이전트 3개", "훅 현재 4개", "`deny-db-migration.sh`가 물리적으로 차단", "2026-09-04 기준 스킬 6·에이전트 3·훅 4" · Actual: 에이전트 2, 훅 5, 마이그레이션 훅은 씨앗이며 플래그 ❌ · Impact: 5행 배너가 v1 이력이라고 밝혀 낮음.

**ROT-7 (Low)** — File: `.claude/skills/specify/references/spec-template.md` · Line: 76-77 · Claim: 실패 예시 `"code": "TRIP_NOT_FOUND", "message": "여행방을 찾을 수 없습니다."` · Actual: TripFit 도메인 용어("여행방")가 배달물 템플릿에 남아 있고 `check-portability.sh`의 C1 패턴(`Trip[A-Z]`·`TripFit`)이 대문자 `TRIP_`·한글 도메인어를 잡지 못한다 · Impact: 부품 계약 검사기의 사각지대 증거.

**ROT-8 (Low)** — File: `docs/specs/cross-cutting/harness-slot-system-v2.md` · Line: 119, 540, 544, 591, 142-192, 419-429 · Claim: `(없음)` 11개, 훅 케이스 44, `pack.md`·`packs/`·`inject-rules.sh`를 현재형 설계로 서술 · Actual: `(없음)` 10, 케이스 54(작업 전), 셋 다 `out-of-scope`로 기각 · Impact: 스펙이 자기 결정 이력과 어긋난다.

**ROT-9 (Low)** — File: `.claude/skills/retro/SKILL.md` · Line: 58 · Claim: 사고 SSOT가 `.claude/rules/README.md`의 "agent-type 훅 관련 교훈" 절 · Actual: 그 제목의 절 없음(내용은 174행 문단) · Impact: 배달물 안의 매달린 포인터. `docs/harness-engineering.md:74`·`layer3:118`도 같음.

기계 검사에서 배달물(`.claude/`·`scripts/`·루트 md)의 실존 경로 참조는 전부 해소됐다. 깨진 링크는 `docs/harness/`·`harness-engineering.md`에만 있다.

## 4. 아키텍처와 불변 조건

이 저장소의 실제 아키텍처는 애플리케이션이 아니라 하네스 자체다.

```
CLAUDE.md → @AGENTS.md → .claude/rules/(always 8 · paths 3) → harness-map.md 슬롯 값
   ↓ 행동                  ↓ 절차                    ↓ 강제                     ↓ 저장소 상태 판정
규칙(core-*)          스킬 8 · 에이전트 2       훅 5 (settings.json)      scripts/{check-portability,test-hooks,check-doc-style} ← verify.sh ← pre-commit
```

핵심 불변 조건은 셋이다: (1) `core-*`·스킬·에이전트·훅에 프로젝트 고유 사실이 없다(부품 계약 C1~C4), (2) always-load 합계 ≤ 52,000B, (3) 모든 `deny-*` 훅은 판정 불가·python3 부재에도 차단한다(훅 공통 규약). 셋 다 `verify.sh`와 pre-commit이 exit code로 판정하며 격리 클론에서 실제 차단을 확인했다.

| Rule | Current Mechanism | 분류 | Risk |
|------|-------------------|------|------|
| core에 고유명사·스택 식별자·경로 리터럴 금지 | `check-portability.sh` (verify + pre-commit) | DETERMINISTIC-BLOCKED | Low (도메인 한글어·대문자 상수는 놓침 — ROT-7) |
| always-load 예산 래칫 | 같은 검사기 | DETERMINISTIC-BLOCKED | Low |
| 훅 fail-closed 규약 | `test-hooks.sh` 54케이스 + python3 부재 내장 | DETERMINISTIC-BLOCKED | Low |
| 훅이 `settings.json`에 등록돼 있어야 함 | adopt 체크리스트(수동) | DOCUMENTED | **High** — 등록 삭제 커밋이 통과함(실측) |
| 파괴적 shell 명령 금지 | `deny-dangerous-bash.sh` | DETERMINISTIC-BLOCKED (범위 좁음) | Medium — §8 우회 목록 |
| 범위 밖 쓰기 금지 | `deny-out-of-scope-write.sh` | DETERMINISTIC-BLOCKED (SCOPE≠. 일 때만) | Low (이 저장소 무동작) |
| 코드 수정 후 테스트 없이 완료 선언 금지 | `deny-unverified-completion.sh` | DETERMINISTIC-BLOCKED (Write/Edit만) | **High** — Bash 편집·동의어·실패 결과 통과 |
| 문서·구현 정합, 임의 개선 금지 (STOP §1) | 규칙 | AI-ADVISORY | Medium |
| 레거시 즉시 삭제 (STOP §2) | 규칙 | AI-ADVISORY | Medium |
| 커밋·이슈·브랜치·PR 생성 전 확인 | 규칙 | AI-ADVISORY | Medium (훅은 `git commit`을 막지 않음) |
| 커밋 메시지 형식 | `commit-msg` git 훅 | DETERMINISTIC-BLOCKED | Low (`--no-verify`로 우회 가능, 훅은 이를 안 막음) |
| 문서 구조(개요·H4·펜스) | `check-doc-style.sh` | DETERMINISTIC-BLOCKED | Low |
| 문서 문체·유형 적합성 | `doc-reviewer` | AI-ADVISORY | Low (의도된 분리) |
| 훅·규칙 구성 요소 변경 시 README·component-map 동시 갱신 | 체크리스트 | DOCUMENTED | Medium — 개수 drift가 실제로 발생(§3) |
| 에이전트 `tools`에 Edit/Write 없음 | frontmatter | DOCUMENTED (Bash로 우회 가능, README가 인정) | Medium |

AI 판단과 기계 검증의 분리 자체는 잘 설계돼 있다("판정 가능한 것만 훅으로"). 문제는 기계가 본다고 문서가 말하는 것 중 실제로 안 보는 것 3건(등록 drift · Bash 편집 · .env/DB)이다.

## 5. 도구

| Tool | Purpose | Input | Output | Failure Handling | Permission Risk |
|------|---------|-------|--------|------------------|-----------------|
| `scripts/verify.sh` | 검증 3종 래퍼 | 없음 | 3단계 출력·요약 줄 | 하나라도 실패 exit 1, 다른 cwd에서도 동작 확인 | 없음 (읽기) |
| `check-portability.sh` | 부품 계약·예산 | `--scope core\|all`, `--skip`, `--budget` | 위반 표 + 예산 표 | 잘못된 옵션 exit 2 + 메시지 | 없음 |
| `test-hooks.sh` | 훅 규약 | 케이스 파일, 선택적 훅 이름 | ok/FAIL 줄 + 요약 | **훅 이름 오타 시 "케이스 0 · 통과 0" exit 0 — 무음 거짓 통과** | 없음 |
| `check-doc-style.sh` | 문서 스타일 | 파일·`--all`·`--staged` | E/W 줄 + 요약 | 없는 파일 → "검사할 파일 없음" exit 0 (거짓 통과) | 없음 |
| `adopt-probe.sh` | 실측 표 | 저장소·범위 | 마크다운 표 64줄 | 경로 없음 exit 2 | 없음 |
| `install-git-hooks.sh` | git 훅 복사 | 없음 | installed 줄 | `.git/hooks` 없으면 exit 1 | 로컬 git 설정 |
| 훅 5개 | 차단·주입 | stdin JSON | stderr 메시지(원인·파일·다음 행동 포함) | 판정 불가=차단(deny) / 통과(Stop·ask·warn) | — |
| `researcher` 에이전트 | 외부 문서 조사 | 경로·질문 | 고정 포맷 | 규범만 | WebFetch·Bash 있음 → 쓰기 가능 |
| `doc-reviewer` 에이전트 | 문서 리뷰 | 경로 | 고정 포맷 | 규범만 | Bash 있음 → 쓰기 가능 |
| `gh` CLI | 이슈·PR | — | — | 인증 확인됨(chhezue) | 규칙으로만 "먼저 확인" |

발견 가능성·조합성은 좋다 — `component-map.md` 수정 로드맵이 상황→파일→검증을 잇고, 훅 stderr가 "Blocked by 파일명 — 무엇을 하라"를 담아 에이전트가 고칠 수 있는 형태다. 출력은 결정론적이다. 권한은 `settings.json`에 `permissions` 자체가 없어 전부 세션 모드에 맡겨진다. `settings.local.json`은 allowlist 2건뿐이라 `AGENTS.md`의 "자주 쓰는 안전한 명령 allowlist"라는 설명과 거리가 있다(gitignored라 배달도 안 됨).

## 6. 검증

이 저장소에는 컴파일·단위·통합·API 계층이 없다. 그 자리를 검사기 3개가 채운다.

| Verification | Exists | Automatically Run | Blocking | Agent Can Interpret Failure |
|---|---|---|---|---|
| Level 1 문법 (`bash -n`·shellcheck) | 부분 — shellcheck 설치돼 있으나 어떤 스크립트도 호출 안 함 | 아니오 | 아니오 | 예 |
| Level 2 단위 (훅 케이스 54) | 예 | verify·pre-commit(훅 stage 시) | 예 | 예 — 기대/실제 exit + stderr 3줄 |
| Level 3 통합 (실제 Claude Code 훅 발화) | 아니오 — 픽스처만 | 아니오 | — | — |
| Level 4 계약 (부품 계약 C1~C4·예산) | 예 | verify·pre-commit | 예 | 예 — 위반 줄과 대체 안내 |
| Level 5 아키텍처 (훅 규약 fail-closed·훅 등록) | 규약 예 / 등록 **아니오** | 규약만 | 규약만 | 예 |
| Level 6 런타임 (실세션 훅 동작) | 아니오 | — | — | — |
| Level 7 diff (unintended change·generated) | 아니오 — 규칙 문장만 | 아니오 | 아니오 | — |
| 완료 선언 게이트 (Stop 훅) | 예 | 턴 종료마다 | 예 (Write/Edit만) | 예 |
| CI | **없음** | — | — | — |

"테스트가 존재한다"와 "에이전트가 실제로 돌린다"의 차이: `deny-unverified-completion.sh`가 후자를 강제하려는 유일한 장치인데 (a) Bash 편집을 못 보고 (b) `cat scripts/verify.sh`처럼 문자열만 있어도 "실행"으로 세며 (c) 테스트가 실패해도 실행 기록만 있으면 통과하고 (d) 편집 전에 돌린 기록도 인정한다 — 픽스처 5종으로 전부 재현했다(모두 exit 0).

## 7. 실패 복구

| Scenario | Detection | Diagnosis | Context Retrieval | Correction → Re-run → Verify | 평가 |
|---|---|---|---|---|---|
| A Build failure | 해당 없음(빌드 없음). `preflight` 사전 모드가 `(없음)`이면 건너뜀 | — | — | — | N/A |
| B Unit(훅 케이스) failure | `test-hooks.sh` FAIL 줄 + stderr 3줄 | 케이스 파일·훅 본문 | `component-map.md` 훅 표 | 케이스 먼저 → 훅 수정 → 재실행 (canonical task에서 실제 수행) | 존재 |
| C Integration failure | 없음 | — | — | — | 없음 |
| D Contract(부품 계약) failure | 위반 줄 + 대체 안내(슬롯/lang 팩) | 즉시 | 패턴 파일 | 문자열 수정 → 재실행 | 존재, 우수 |
| E Lint(doc-style) failure | E/W 줄 + 파일:줄 | 즉시 | `doc-writing.md`(md 접근 시 로드) | 수정 → 재실행 | 존재 |
| F Tool execution failure (훅 차단) | stderr에 원인·파일·다음 행동 | 즉시 | `core-gates.md` §3 "우회 금지·보고" | 사용자 보고로 종료 | 존재, 설계 의도 |
| G 잘못된 가정 | STOP §1.5·§1.6 "코드를 확인하라" 규칙 · `debug` 스킬 "재현 없이 안 고침" | AI-ADVISORY | `researcher` | 규칙 | 약함 |
| H Context 부족 | `harness-map.md` 규칙 2 "(없음)이면 묻기" · `warn-unfilled-map` | 경고 | `ask` 스킬 | 사용자 질문 | 존재 |

- retry limit: Stop 훅은 `stop_hook_active`로 1회만 되돌린다 → 무한 루프 불가(설계·픽스처 확인). 다른 훅은 차단만 하고 재시도 개념 없음
- 같은 잘못 반복 가능성: 훅 차단 메시지가 컨텍스트에 남아 낮음. 단 `deny-dangerous-bash`의 문자열 오탐(`grep 'rm -rf'`)은 에이전트가 우회 표현을 찾게 만든다 — 이 감사에서 실제로 3회 차단당해 문자열 조립으로 우회했다
- human escalation: G2·훅 차단·`(없음)` 슬롯·트랙 승격에서 멈춘다. 조건이 표로 명시돼 재현 가능(`core-gates.md`)

## 8. 안전·보안

**실측 우회 목록 (`deny-dangerous-bash.sh`, 2=차단 0=통과):** 차단 — `rm -rf`류 5형·`sudo rm -rf`·`bash -c 'rm -rf'`·force push 3형·`git reset --hard`·`docker compose down -v`. **통과** — `find -delete`, `rm $R`(변수), `git push origin :branch`·`--delete`, `git branch -D main`, `git checkout -- .`, `git restore .`, `git clean -fdx`(작업 후 차단), `git stash drop|clear`, `git rebase -i`, `git filter-branch`, `git commit --no-verify`, `.env` add/commit, 시크릿을 파일로 echo, `cat ~/.ssh/id_rsa`, `printenv`, `curl | sh`, `chmod -R 777 /`, `dd of=/dev/disk1`, `docker compose down --volumes`, `docker system prune --volumes`, `DROP DATABASE`, `truncate`, `: > file`, `bash probes.sh`(파일 간접 실행), `eval "$CMD"`, `python3 -c shutil.rmtree`. 오탐 — `grep -rn 'rm -rf' docs/`, `echo '... git push --force'` 차단(문서화된 의도).

**자기 변조.** 훅 스크립트 본문을 세션 중 고치면 다음 도구 호출부터 즉시 적용된다(canonical task 뒤 새 오류 문구로 관측). `deny-out-of-scope-write.sh`는 `.claude/`를 항상 허용하므로 에이전트가 자기 훅을 `exit 0`으로 바꾸는 것을 막는 결정론적 장치는 없다 — pre-commit의 `test-hooks.sh`가 커밋 시점에 잡을 뿐이고(A 실험), 등록 삭제는 그마저 통과한다(B 실험). `settings.json` 스냅샷 여부는 공식 문서에서 UNVERIFIED.

**시크릿·운영.** 이 저장소엔 운영 자원·DB·배포가 없어 실제 피해 반경은 작다. 그러나 템플릿으로 배달되는 순간 위 통과 목록이 그대로 새 프로젝트의 하한선이 된다. `permissions.deny`(deny > ask > allow, 공식 문서 확인)를 전혀 쓰지 않는다.

Critical 판정: "security check가 AI 판단에만 의존" — 해당(시크릿 커밋). "git history destructive 보호 안 됨" — 부분(`filter-branch`·`rebase -i`·브랜치 삭제 통과). "production destructive 무방비" — 이 저장소엔 production 없음.

## 9. 관측 가능성·증거

- transcript(`~/.claude/projects/<proj>/<session>.jsonl`)가 프롬프트·도구 호출·결과·훅 차단 메시지(이 세션 8건)·UserPromptSubmit 주입(2건)·`verify.sh` 실행(2건)을 전부 담는다. 30분 뒤 사람이 "왜 이렇게 바꿨나"를 재구성할 수 있다 — 단 형식은 비공식이라 버전마다 바뀔 수 있음(공식 문서)
- 하네스가 남기는 증거: `report.md`(검증하지 못한 것 포함), 스펙 Draft/Approved, 감사 문서, `harness-retro.md`, 커밋 분할안. 훅 자체는 파일을 쓰지 않는다
- 없는 것: 훅 실행 로그(공식 기능도 없음), 검증 결과의 파일 기록(verify 출력은 채팅에만), diff 증거 자동 첨부
- "성공 주장을 독립 확인할 evidence": `verify.sh` exit code와 케이스 수가 있다. 그러나 Stop 훅이 실행 사실만 보고 결과를 안 보므로 "돌렸다 ≠ 통과했다"

## 10. 유지보수·drift

자동으로 함께 검증되는 것: 부품 계약·예산·훅 규약·문서 구조(pre-commit). 검증되지 않는 것: 훅 등록 상태, 문서 안 개수·파일명 주장(훅 5/스킬 8/트랙 4), README·component-map 동시 갱신, 링크 실존. 결과적으로 배달물은 건강하고 설계 문서는 v1 화석이 됐다(§3). `docs/out-of-scope/README.md`가 기각 결정을 이유·재검토 조건과 함께 남기는 것은 drift 방지에 실제로 기여한다.

## 11. 모듈 커버리지

| Module | Has Context | Has Constraints | Has Verification | Has Skills/Tools | Coverage |
|--------|-------------|-----------------|------------------|------------------|----------|
| `.claude/rules/` | README(조건부 로드)·component-map | 부품 계약·예산 | check-portability | adopt·retro | High |
| `.claude/hooks/` | README Hooks 표·훅 머리 주석 | 훅 공통 규약 | test-hooks(54 케이스) | component-map 로드맵 | High (등록 drift 제외) |
| `.claude/skills/` | README Skills 표·각 SKILL 머리 | 부품 계약 | check-portability·doc-style | — | Medium |
| `.claude/agents/` | README Agents 표 | 부품 계약 | 없음(에이전트 동작 테스트 없음) | — | Medium |
| `scripts/` | 각 스크립트 머리 주석·component-map | 없음(shellcheck 미호출) | 자기 자신이 테스트 대상이 아님 | — | Medium |
| `examples/seeds/` | 씨앗 README·대조 표 | doc-style만 | test-hooks(씨앗 훅 포함) | adopt | Medium |
| `docs/harness/`·`harness-engineering.md` | 배너 | doc-style | 없음 | — | Low (rot) |
| `docs/templates/`·`specs/`·`decisions/`·`audits/` | 등록부 | doc-style | 없음 | specify·safe-refactor·retro | Medium |

## 12. Canonical Task 시뮬레이션

**Task.** `docs/harness/component-map.md` "예시 — 훅 하나를 추가하는 순서"가 견본으로 든 작업을 그대로 수행: `git clean -f` 계열을 `deny-dangerous-bash.sh`가 차단하도록 훅·케이스·README·component-map을 고치고 `verify.sh`를 통과시킨다. 비즈니스 로직(정규식)·테스트(케이스 파일)·계약(훅 공통 규약 fail-closed)·문서 동시 갱신을 포함한다.

**Initial state.** HEAD `0ebceb8`, 작업 트리 clean, `verify.sh` 통과(케이스 54, 문서 오류 0/경고 72, always-load 50,824B), `git clean -fdx` → exit 0.

**Acceptance.** `-f`·`-fd`·`-fdx`·`-xdf`·`-d -f`·`--force`·`<path> -f` exit 2, `-n`·`--dry-run` exit 0, 케이스 추가, 문서 2곳 갱신, `verify.sh` 통과, 변경 파일 4개 이내, python3 부재 차단 유지.

**수행 기록.** First files read: `component-map.md` 136-146행, 훅 본문, 케이스 파일. Context retrieved: 로드맵 5단계가 정확히 필요한 파일·순서·검증을 알려 줬다. Tools: Write(스펙) · Edit ×5 · Bash(test-hooks·verify·shellcheck·probe) · `code-review` 스킬(low). Files modified: `.claude/hooks/deny-dangerous-bash.sh`·`scripts/hook-cases.txt`·`.claude/rules/README.md`·`docs/harness/component-map.md` + 신규 `docs/specs/cross-cutting/deny-git-clean.md`(Draft). Tests run: `test-hooks.sh deny-dangerous-bash.sh`(red 5 FAIL → green 26) · `verify.sh` ×2 · shellcheck · doc-style. Failures: 첫 정규식이 `git clean build -f`(경로가 플래그 앞)를 놓침 — `code-review` 서브에이전트가 지적. Recovery: 케이스 1건 추가 → 정규식 수정 → 재실행 통과(케이스 62). Human intervention: **0회 실제 개입.** 하네스 규칙상 멈춰야 했던 지점 2곳 — G2 스펙 승인(`core-workflow` A 트랙 3파일+), 커밋 승인 — 은 감사 모드라 "Draft·미커밋"으로 남겼다. 하네스 자체 오탐 3회: 감사 probe 명령이 문자열 때문에 차단돼 문자열 조립으로 우회했다.

**독립 검증.** 훅 스크립트에 직접 stdin을 넣어 8개 명령 exit 확인(verify.sh 경유 아님) · 문서 2곳 grep · python3 가짜로 fail-closed 확인 · `git diff --stat` 4 files, 15+/5- 이외 변경 없음 · shellcheck 경고 0 · 편집 직후 실세션에서 새 오류 문구로 차단 관측(런타임 반영). 보안: 새 패턴은 dry-run을 통과시키며 기존 케이스 전부 유지. Repository state: 미커밋 변경 4 + 신규 2(스펙, 이 보고서).

## 13. Before / After 행동 기준선

| 항목 | 이번 세션 |
|------|-----------|
| First file selection | `component-map.md` 로드맵 → 훅 → 케이스 (하네스 안내 그대로) |
| Context discovery | 시스템 프롬프트 규칙 8개로 충분, 추가 탐색 1회(로드맵 절) |
| 불필요한 도구 호출 | 3 (훅 오탐으로 재작성) |
| 실패한 명령 | 3 (전부 훅 오탐 차단) |
| Retry | 1 (정규식 재수정) |
| Verification count | verify.sh 2 · test-hooks 3 · 직접 probe 2 · shellcheck 1 · code-review 1 |
| Human interventions | 0 (규칙상 2곳 필요) |
| Final success | 예 (독립 검증 통과) |
| Token usage (감사 전체, 서브에이전트 제외) | 약 350k 컨텍스트 소비 · 서브에이전트 3개 약 354k |

## 14. 점수

| Dimension | Score | Max | 근거 |
|-----------|------:|----:|------|
| Context & Discoverability | 11 | 15 | 진입점·progressive disclosure·예산 래칫 우수. 항상 로드 안의 저가치 2k 토큰, 설계 문서 rot |
| Constraints & Invariants | 11 | 20 | 부품 계약·훅 규약은 결정론. 훅 등록 drift 미검출, 규칙이 약속한 차단 3건 부재, 대부분 규칙이 advisory |
| Tooling | 7 | 10 | 명확·결정론·오류 메시지 우수. 무음 거짓 통과 2건, permissions 미사용 |
| Verification | 10 | 20 | verify.sh가 실재 계층 전부 커버. Stop 훅 사각 4종, CI·diff 검증·shellcheck 부재 |
| Recovery | 6 | 10 | 차단 메시지·재시도 상한·에스컬레이션 조건 명확. 통합·런타임 루프 없음 |
| Safety & Security | 4 | 10 | 우회 25종, 시크릿 커밋·간접 실행 미차단, 훅 자기 변조 가능, `permissions.deny` 미사용 |
| Observability & Evidence | 6 | 10 | transcript·report.md·스펙 상태. 훅 로그·검증 결과 파일 없음 |
| Maintainability & Drift | 3 | 5 | 래칫·케이스·out-of-scope 우수. 개수·링크·등록 drift 자동 검출 없음 |
| **Total** | **58** | **100** | |

## 15. Critical Failure Gate

해당: **verification 없이 success 선언 가능**(Bash 편집·동의어·실패 결과 통과 — 재현 픽스처 5종), **security check가 AI 판단에만 의존**(시크릿 커밋), **Harness instruction과 실제 불일치**(`core-guardrails.md` 62행의 훅 차단 약속). `docs/harness/` rot는 배달 안 하는 이력이라 심각 불일치로 보지 않는다. → verdict 상한 **CONDITIONAL PASS**.

## 16-17. Findings

**[CRITICAL GAP] Stop 훅이 Bash 편집·실패 결과·동의어를 보지 못한다** · Severity: High · Category: verification · Problem: `deny-unverified-completion.sh`는 Write/Edit/MultiEdit/NotebookEdit만 코드 수정으로 세고, `TEST_CMD` 문자열이 Bash 명령에 들어 있기만 하면 실행으로 보며, 결과·순서를 안 본다 · Evidence: 훅 75-84행; 픽스처 `bash-edit-no-test`·`edit-synonym-claim`·`edit-test-failed-claim`·`test-before-edit`·`mention-not-run` 전부 exit 0 · Why: 이 세션의 하네스 지시("Bash로 편집")처럼 흔한 모드에서 게이트가 무동작이 되고, "돌렸다"가 "통과했다"로 둔갑한다 · Current: 위 5경우 통과 · Expected: `sed -i`·`>`·`tee`·heredoc이 비문서 파일을 가리키면 code_edit=true; 마지막 코드 편집 **이후**의 `TEST_CMD` 실행만 인정; 그 tool_result의 `is_error`·"실패" 문자열이면 차단; 완료 단정에 "성공·정상 동작·구현했·적용했" 추가 · Fix: 파서에 Bash 명령의 리다이렉션·sed·tee 검출과 tool_result 대조 추가, 픽스처 5종을 `hook-fixtures/`에 넣고 케이스 등록 · Automation: 예 (같은 훅) · Confidence: HIGH

**[ROT] 규칙이 존재하지 않는 훅 차단을 약속한다** · Severity: High · Category: integrity · Problem: `core-guardrails.md:62` "환경 금지 (훅이 차단): … 운영 DB 파괴 · `.env`·API 키 커밋" · Evidence: 훅 29행 정규식에 해당 패턴 없음; `git add .env && git commit` exit 0 · Why: 항상 로드되는 규칙이 잘못된 안전감을 준다 · Fix: 문장을 훅이 실제로 막는 4종으로 고치거나, 훅에 `git (add|commit).*\.env`·`DROP (DATABASE|TABLE)`·`down --volumes` 패턴과 케이스를 추가 · Automation: 예 · Confidence: HIGH

**[CRITICAL GAP] 훅 등록 해제 커밋이 검출되지 않는다** · Severity: High · Category: constraints · Problem: `settings.json`에서 `PreToolUse` 배열을 비운 커밋이 pre-commit을 통과했다(격리 클론 실험 B, 커밋 `bb65677`). 약화(A)·삭제(C)는 `test-hooks.sh`가 잡는다 · Evidence: 실험 로그 · Why: 훅은 등록돼야 존재한다. 등록 상태는 adopt 체크리스트(수동)에만 있다 · Fix: `test-hooks.sh`(또는 새 `check-hook-registry.sh`)가 `.claude/hooks/*.sh` 중 `deny-*`·`ask-*`·`warn-*`가 `settings.json`에 등록돼 있는지, 등록된 경로가 실존하는지 exit code로 판정; `verify.sh`·pre-commit에 포함 · Automation: 예 · Confidence: HIGH

**[CRITICAL GAP] 에이전트가 자기 훅을 즉시 무력화할 수 있다** · Severity: High · Category: safety · Problem: 훅 스크립트 편집은 다음 호출부터 즉시 적용되고(관측), `deny-out-of-scope-write.sh`는 `.claude/`를 항상 허용한다 · Evidence: canonical task 직후 새 오류 문구로 차단됨; 훅 39행 `for allowed in (scope, ".claude")` · Why: 규칙(`core-gates.md` §3)만이 "훅·settings 수정 금지"를 말한다 · Fix: `deny-out-of-scope-write.sh`에서 `.claude/hooks/`·`.claude/settings.json`을 예외 없이 차단하고(하네스 유지보수는 사람이 직접 또는 별도 승인 브랜치), `permissions.deny`에 `Edit(.claude/hooks/**)`·`Write(.claude/settings.json)`을 병행 · Automation: 예 · Confidence: HIGH (settings.json 스냅샷 여부는 UNVERIFIED)

**[LARGER IMPROVEMENT] `deny-dangerous-bash.sh` 커버리지와 `permissions.deny` 병행** · Severity: Medium · Category: safety · Problem: §8 통과 목록 25종 — 특히 간접 실행(`bash file.sh`·`eval`·변수)과 `--no-verify`·브랜치 삭제·`stash drop`·`filter-branch`·`curl \| sh` · Evidence: probe 52건 · Why: 템플릿의 하한선이 그대로 새 프로젝트로 간다 · Fix: 패턴 확장은 케이스 먼저(이번 `git clean` 절차 그대로); 정규식으로 못 막는 간접 실행은 `permissions.deny`(`Bash(eval *)`, `Bash(curl *|*sh)`)와 규칙 문장으로 분담; 오탐(문자열 언급)을 줄이려면 첫 토큰·파이프 경계 기준 매칭 검토 · Automation: 부분 · Confidence: HIGH

**[QUICK FIX] `test-hooks.sh`·`check-doc-style.sh`의 무음 거짓 통과** · Severity: Medium · Category: tooling · Problem: `test-hooks.sh no-such.sh` → "케이스 0" exit 0, `check-doc-style.sh docs/nope.md` → exit 0 · Fix: 케이스 0건 또는 지정 파일 부재면 exit 2 · Automation: 예 · Confidence: HIGH

**[QUICK FIX] `ask-open-request.sh` 패턴 누락** · Severity: Low · Category: context · Problem: "리팩토링해줘"·"다듬어줘"·"간단하게"·영어 "clean up / refactor / make it better" 무음 · Evidence: probe 7건 중 1건만 주입 · Fix: `리팩토링|다듬|간단하게|clean ?up|refactor|improve|make it better` 추가 + 케이스 · Confidence: HIGH

**[QUICK FIX] 상수 65,000B 잔존** · Severity: Low · Category: rot · `docs/harness/component-map.md:105`, `scripts/check-portability.sh:26` 주석, v2 스펙 110·562·588행 → 52,000 · Confidence: HIGH

**[LARGER IMPROVEMENT] 설계 문서 rot 자동 검출** · Severity: Medium · Category: drift · Problem: `docs/harness/`·`harness-engineering.md`·`architecture-diagrams.md`가 v1 개수·CI·훅 이름을 현재형으로 말하고 링크 11개가 깨져 있다 · Fix: (1) `architecture-diagrams.md`에 v2 배너, (2) 링크 실존 검사를 `check-doc-style.sh`에 W 등급으로 추가(감사에서 쓴 1,732건 검사 로직 재사용), (3) "훅 N개·스킬 N개" 숫자를 문서에서 지우고 README 표를 가리키기 · Automation: 링크는 예, 숫자는 부분 · Confidence: HIGH

**[TOKEN OPTIMIZATION] always-load 2k 토큰** · `harness-map.md` 규칙 5개·축 설명·"쓰는 곳" 열(README로), `core-followup.md`·`core-scope.md`를 조건부/스킬로. 래칫을 48,000B로 낮춘다 · Confidence: MEDIUM

**[ROT] 배달 템플릿의 TripFit 도메인 잔재** · `spec-template.md:76-77` "TRIP_NOT_FOUND / 여행방" → `RESOURCE_NOT_FOUND / 대상을 찾을 수 없습니다`; 검사기 C1에 `여행방|TRIP_` 추가 · Confidence: HIGH

**[QUICK FIX] 절차 충돌** · `core-workflow.md` A 트랙 "3파일+ → 스펙"과 `component-map.md` "훅 추가 5단계(스펙 없음)" — 하네스 파일 변경은 D 트랙 또는 B 트랙으로 분류를 명시 · Confidence: MEDIUM

**[QUICK FIX] 매달린 포인터** · `retro/SKILL.md:58`·`harness-engineering.md:74`·`layer3:118`의 "agent-type 훅 관련 교훈" 절 → README "Hooks" 절 "advisory 훅은 command-type으로" 문단으로 · Confidence: HIGH

## 18. 최종 판정

**Critical Findings (위험 순):** Stop 훅 사각(Bash 편집·실패 결과) → 규칙의 거짓 차단 약속(.env·DB) → 훅 등록 해제 미검출 → 훅 자기 변조 가능 → 파괴 명령 커버리지 부족.

**Strengths (evidence):** 부품 계약 검사기가 격리 클론에서 실제로 커밋을 막았다 · 훅 규약 테스트가 약화·삭제 커밋을 잡았다(A·C) · 훅 5개가 이 세션에서 실제 발화했다(차단 8·주입 2) · 항상 로드 8/조건부 3 분리가 시스템 프롬프트로 확인됐다 · `component-map.md` 로드맵이 canonical task를 인간 개입 없이 끝내게 했다 · `out-of-scope`·`references`가 기각 이유와 재검토 조건을 남긴다 · 훅 stderr가 "무엇이·왜·다음에 무엇을"을 담는다 · 예산 래칫이 늘어나는 커밋만 막는 실용적 설계다.

**Weaknesses (우선순위):** 1 Stop 훅 사각 · 2 규칙-훅 불일치 · 3 등록 drift · 4 자기 변조 · 5 파괴 명령 커버리지 · 6 설계 문서 rot · 7 도구 무음 통과 · 8 항상 로드 저가치 토큰.

**Canonical Task Result:** Task: `git clean -f` 차단 추가(훅·케이스·문서 2) · Success: 예 · Human Intervention: 0 (규칙상 G2·커밋 2곳 필요) · Verification: verify.sh 62/62·직접 probe 8·shellcheck·code-review·런타임 관측 · Failures: 정규식 1건(경로 선행) · Recovery: 케이스 추가 → 수정 → 재검증 · Final Diff: 4 files, +15/−5, 스펙 Draft 1 신규, 미커밋.

**Top 5 Improvements:**
1. Stop 훅 파서 확장(Bash 편집·순서·결과·동의어) — Impact: 검증 게이트가 실제로 닫힘 — Implementation: 훅 75-84행 + 픽스처 5종 + 케이스 — Why: 유일한 "실행 강제" 장치가 흔한 모드에서 무동작이다.
2. 훅 등록 검사기 + `.claude/hooks`·`settings.json` 쓰기 차단 — Impact: 훅이 조용히 사라지는 경로 두 개를 닫음 — Implementation: `test-hooks.sh` 등록 대조 + scope 훅 예외 제거 + `permissions.deny` — Why: 등록 삭제 커밋이 통과했고 스크립트 편집이 즉시 적용된다.
3. `core-guardrails.md:62`를 사실로 맞추고 시크릿·DB 패턴을 훅에 추가 — Impact: 규칙과 훅의 약속 일치 — Implementation: 문장 수정 + 패턴 3종 + 케이스 — Why: 항상 로드되는 거짓 보호.
4. 파괴 명령 커버리지·간접 실행 대응(`permissions.deny` 병행) — Impact: 템플릿 하한선 상승 — Implementation: 케이스 먼저, 패턴 8종, deny 규칙 3종 — Why: 25종 통과.
5. 링크 실존 검사 + `architecture-diagrams.md` v2 배너 + 숫자 제거 — Impact: 설계 문서가 에이전트를 오도하지 않음 — Implementation: `check-doc-style.sh` W 규칙 1개, 배너 1개 — Why: 링크 11개 파손·개수 전부 불일치.

**Harness Maturity: LEVEL 3 — Guardrailed Agent.** 근거: 결정론적 훅·검사기·git 훅이 존재하고 실제 발화하며(L3 조건), 케이스 기반 회귀 테스트와 예산 래칫이 있다. L4(Autonomous Development Loop)가 아닌 이유: CI가 없고, 완료 게이트가 편집 경로에 따라 무동작이며, 훅 등록·자기 변조에 대한 결정론적 보호가 없어 "사람이 지켜보지 않아도 되는 루프"가 아직 아니다. `retro` 스킬과 `harness-retro.md`는 L5의 씨앗이지만 기록이 0건이다.

**Final Verdict: CONDITIONAL PASS** — 총점 58/100, Critical gate 3건 해당(모두 하네스 자체 파일 수정으로 닫을 수 있음).

**"현재 하네스만으로 실제 feature/bug-fix/refactor 작업을 인간의 최소 개입으로 안전하게 끝까지 수행할 수 있는가?" → PARTIALLY.** 이 저장소 안의 작업(훅·검사기·규칙 수정)은 canonical task가 보여주듯 로드맵·케이스·verify.sh로 인간 개입 없이 끝나고 독립 검증된다. 그러나 (1) "안전하게"는 Bash 편집 경로에서 완료 게이트가 열려 있고 시크릿·간접 실행이 통과하는 한 보장되지 않으며, (2) 하네스 설계상 G2 승인과 커밋·PR 승인은 사람이 끊도록 만들어져 "최소 개입"은 세션당 2~3회가 하한이고, (3) 애플리케이션 코드가 있는 프로젝트에서는 lang 팩 씨앗 대조·CI가 없으면 검증 층 1~6이 비어 있으므로 이 저장소의 결과를 그대로 일반화할 수 없다.

## 조치 결과 (같은 날, 사용자 지시 "전부 수정")

감사 뒤 사용자가 발견 사항 전부를 고치라고 해서 같은 세션에서 반영했다. 다음 REPEAT AUDIT은 이 상태를 기준으로 비교한다.

| 발견 | 조치 | 검증 |
|------|------|------|
| Stop 훅 사각 4종 | `deny-unverified-completion.sh` — Bash `sed -i`·`>`/`>>`·`tee` 편집 검출, 마지막 편집 **이후** 실행만 인정, tool_result 실패 대조, 완료 동의어 추가, 실행/실패 메시지 구분 | 픽스처 6종 추가(차단 5·통과 1), 케이스 107/107, 실세션 transcript exit 0 |
| 규칙의 거짓 차단 약속 | `core-guardrails.md` 환경 금지를 훅이 실제로 막는 목록으로 교체하고 "훅이 못 보는 것"을 분리 | 부품 계약 통과 |
| 훅 등록 해제 미검출 | `test-hooks.sh` 내장 "등록 대조" — `.claude/hooks/*.sh` 전부가 `settings.json`에 등록·실존·실행 가능한지 | `verify.sh`·pre-commit 포함 |
| 훅 자기 변조 | 능력 플래그 **하네스 자기 수정**(8번째) 신설, `deny-out-of-scope-write.sh` 상수 `HARNESS_SELF_EDIT` — ❌면 `.claude/hooks/`·`settings.json` 쓰기 차단. 이 저장소만 ☑ | 케이스 7건(`;self=0` 치환) |
| 파괴 명령 커버리지 | `PATTERNS` 배열로 재구성 — `find -delete`·`branch -D`·`stash drop/clear`·`filter-branch`·`--no-verify`·`.env` add/commit·SQL DROP·`--volumes`·`system prune`·`volume rm`·`curl\|sh`·`chmod -R 777`·`dd of=/dev` 추가. `settings.json`에 `permissions.deny` 10건 병행 | 케이스 31건 추가(차단·오탐 방지 짝) |
| 도구 무음 통과 | `test-hooks.sh` 케이스 0건 → exit 2, `check-doc-style.sh` 없는 파일 → exit 2 | 실행 확인 |
| `ask` 패턴 누락 | 리팩토링·다듬·간단하게·영어(clean up·refactor·improve·make it better·tidy·optimize·simplify) 추가 | 7문장 probe |
| 상수 65,000B 잔존 | `component-map.md`·`check-portability.sh` 주석·v2 스펙 현재형 행 → 52,000B | grep |
| 설계 문서 rot | `architecture-diagrams.md` v2 배너, 깨진 링크 11개 → "(TripFit — 이 저장소에 없음)" 문자열, `docs/harness/README.md` 트랙 4·L4 주석·개수, 매달린 포인터 3곳, `harness-engineering.md` SSOT 포인터 | 링크 검사 0건 |
| 템플릿의 TripFit 잔재 | `spec-template.md` `RESOURCE_NOT_FOUND`, 검사기 C1에 `TRIP_`·`여행방` | 부품 계약 통과 |
| 문서 개수 | 플래그 7 → 8을 README·AGENTS·AGENTS.template·docs/README·rules README·adopt·adopt-probe·component-map·spec에 반영 | grep |

`verify.sh` 최종: 부품 계약 위반 0 · always-load 52,000B 이하(래칫이 도중 세 번 막아 규칙 문장을 줄였다) · 케이스 107/107 · 문서 오류 0.

## 검증하지 못한 것

| 무엇 | 왜 | 확인 방법 |
|------|-----|-----------|
| Claude 실제 토크나이저 기준 토큰 수 | 비공개, API 키 없음 | `count_tokens` API |
| `settings.json` 훅 스냅샷 여부(세션 중 등록 변경이 즉시 적용되는지) | 공식 문서에 명시 없음 | 세션 중 등록 변경 후 발화 관측 |
| `.claude/rules` `paths:` glob 라이브러리 시맨틱(`**/docs/**/*.md`가 루트 `docs/`에 매칭되는지) | 문서에 라이브러리 미명시 | `InstructionsLoaded` 훅으로 로드 이유 관측 |
| `Write\|Edit` 매처가 `MultiEdit`·`NotebookEdit`을 잡는지 | 문서상 "정확 일치" — 훅 본문은 notebook_path를 처리하지만 매처가 안 잡으면 dead code | 실세션 NotebookEdit 호출 |
| `doc-reviewer`·`researcher` 에이전트의 실제 출력 품질 | 이번 감사에서 호출하지 않음 | 문서 50줄+ 변경 후 호출 |
| 애플리케이션 코드가 있는 저장소에서의 canonical task | 이 저장소에 코드 없음 | `examples/seeds/java-spring/` 대상 저장소에서 반복 감사 |
