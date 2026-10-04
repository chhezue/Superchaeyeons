# 하네스 구조 감사와 경량화 — 작업 보고서

이 저장소의 하네스(규칙·스킬·에이전트·훅·검사 스크립트·문서) 전체를 "이것이 없으면 실제로 어떤 사고가 나는가"라는 기준으로 감사하고, 그 결과대로 중복을 지우고 통합한 기록이다. 앞 절(전체 맵 ~ 목표 구조)은 **수정 전에** 쓴 감사 결과라 그 안의 수치·목록은 수정 전 상태이고, "적용 결과" 절부터는 수정 뒤에 덧붙였다. 지금 값(always-load 27,341B · 상한 28,000B · 규칙 always-load 5개 · 훅 3개 · 스킬 8개)은 "적용 결과"에 있다. 감사 기준 커밋은 `b6ef624`, 이전 감사는 [`2026-09-07-harness-audit-baseline.md`](2026-09-07-harness-audit-baseline.md)다.

## 언제 이 문서를 보는가

- 하네스 구성 요소를 다시 늘리거나 되살리려 할 때 — 무엇을 왜 지웠는지 확인
- always-load 예산·훅 목록이 왜 지금 값인지 확인할 때

## 측정 방법

수치는 전부 이 저장소에서 직접 잰 값이다.

| 무엇 | 어떻게 쟀나 |
|------|-------------|
| 항상 실리는 컨텍스트 | `scripts/check-portability.sh` 예산 표 (바이트, 한국어 기준 바이트/2.5 ≈ 토큰) |
| 파일 접근 시 실리는 규칙 | `wc -c` |
| 스킬·에이전트 설명 | frontmatter `description:` 줄 길이 |
| 검증 한 번의 출력량 | `scripts/verify.sh` 출력을 파일로 받아 `wc` |
| 중복 | 같은 문구를 `grep -rl`로 센 파일 수 (기록 문서 `docs/reports/`·`docs/specs/` 제외) |
| 훅 동작 | 훅에 직접 입력을 넣어 실행 · 매처 해석은 [Claude Code 훅 공식 문서](https://code.claude.com/docs/en/hooks)(2026-10-05 확인) |

## 전체 맵 — 수정 전 실행 순서

요청 하나가 처리되는 동안 끼어드는 장치를 실행 순서대로 그렸다. 수정 뒤 구조는 "최종 Architecture" 절에 있다. 괄호 안은 실행 시점이다.

```text
사용자 요청
   │
   ├─ [UserPromptSubmit] ask-open-request.sh — 열린 표현이면 ask 알림을 컨텍스트에 주입 (차단 없음)
   ▼
세션 컨텍스트 (세션 시작 때 한 번)
   ├─ CLAUDE.md → @AGENTS.md
   ├─ always-load 규칙 8개: core-guardrails · core-gates · core-workflow · core-scope ·
   │                       core-followup · core-tools · core-reporting · harness-map
   ├─ 스킬 9개 · 에이전트 3개의 description
   └─ [SessionStart] warn-unfilled-map.sh — harness-map에 ⬜·이유 없는 (없음)이 있으면 경고 주입
   ▼
파일을 읽을 때 (paths: frontmatter)
   ├─ 소스 파일                          → core-code-comments.md
   ├─ 테스트 파일                        → core-testing.md
   ├─ docs/·.claude/·examples/·.github/ md → doc-writing.md
   └─ .claude/agents·skills·hooks·settings → .claude/rules/README.md
   ▼
트랙 판정 (core-workflow 진입) → 스킬 → 에이전트
   ├─ A 기능    specify ─(테스트 먼저 지점)→ tdd ─(통제 영역 지점)→ test-writer
   ├─ B 리팩터  safe-refactor ─(감사)→ Explore/general-purpose 서브에이전트 · researcher
   ├─ C 버그    debug → tdd
   ├─ D 이식    adopt → scripts/adopt-probe.sh
   ├─ G1        researcher
   ├─ G3        preflight → doc-reviewer · (플래그) 스택 리뷰어 · code-review/simplify
   └─ G4        retro · defer · report.md
   ▼
도구 호출마다
   ├─ [PreToolUse Bash]       deny-dangerous-bash.sh  + settings.json permissions.deny
   └─ [PreToolUse Write|Edit] deny-out-of-scope-write.sh  (이 저장소: SCOPE=. · 자기 수정 허용 → 즉시 통과)
   ▼
턴 종료
   └─ [Stop] deny-unverified-completion.sh — 코드 편집 뒤 scripts/verify.sh를 안 돌렸거나 실패했는데 완료를 말하면 되돌림
   ▼
검증 · 커밋
   ├─ scripts/verify.sh = check-portability + test-hooks + check-doc-style --all
   └─ git pre-commit (같은 검사기 3개, stage 내용에 따라) · commit-msg (형식)
```

## Executive Summary

가장 큰 문제 다섯 가지다.

1. **같은 내용이 여러 파일에 반복된다.** 하네스 구성 요소 목록을 설명하는 살아 있는 문서가 13개(약 141KB)다. `tdd` 스킬 하나를 추가할 때 [TDD 도입 스펙](../specs/cross-cutting/tdd-adoption.md)의 Must Have에 "목록·지도 갱신" 대상으로 10개 파일이 적혔다. 규칙 안에서도 `core-workflow.md` G3 절이 `preflight` 사후 모드 8단계를 거의 그대로 되풀이하고, `core-gates.md` §3은 스스로 "다른 규칙에 흩어진 금지를 모은 목록"이라고 밝힌다. "Must Have급" 정의는 10개 파일에 있다.
2. **항상 실리는 컨텍스트가 예산 상한에 붙어 있다.** always-load 합계 51,384B(약 20.5k 토큰 추정)로 래칫 상한 52,000B의 98.8%다. 래칫(합계가 늘면 커밋을 막고 줄일 때만 상한을 내리는 방식)이라 사실상 더 넣을 자리가 없다. 이 안에 판단에 쓰이지 않는 정보가 섞여 있다 — 슬롯이 어디서 쓰이는지 적은 유지보수용 열, 이 저장소에서 꺼진(❌) 플래그 절의 설명, 설계 이력, 그리고 안전과 무관하거나 다른 파일과 겹치는 규칙 파일 3개(`core-scope`·`core-followup`·`core-tools`, 합계 7,693B).
3. **검증 한 번의 출력이 22,430B다.** `scripts/verify.sh`는 성공해도 훅 케이스 108줄과 문서 스타일 경고 62줄을 그대로 출력한다. Stop 훅이 코드 편집 뒤마다 이 명령을 돌리게 하므로, 같은 출력이 한 세션에 여러 번 컨텍스트에 쌓인다. 경고 62건은 지금 아무도 처리하지 않는 상태다.
4. **훅 5개 중 2개는 실제로 하는 일이 없거나 LLM이 할 판단을 정규식으로 하고, 1개는 매처에 구멍이 있다.**
   - `ask-open-request.sh` — "개선해줘" 같은 단어만 보고 알림을 붙인다. 14개 절로 요구사항을 못 박은 이 감사 요청 프롬프트에도, "캐시 TTL 60초" 같은 값을 다 준 요청에도 붙었다. 모호성 판단은 LLM이 할 일이고, 같은 신호가 이미 `core-gates.md` §2와 `ask` 스킬 설명에 있다.
   - `warn-unfilled-map.sh` — 배달되는 `harness-map.md`에 ⬜와 이유 없는 `(없음)`이 0개라서, 이 저장소에서도 새 프로젝트에 복사한 직후에도 출력이 없다(실행해서 0바이트 확인).
   - `deny-out-of-scope-write.sh` — 매처 `Write|Edit`는 공식 문서상 두 도구에만 정확히 일치한다. `MultiEdit`·`NotebookEdit`로 쓰면 훅이 불리지 않는다. 붙여 쓰는 프로젝트(자기 수정 ❌)에서 훅·`settings.json` 보호가 이 두 도구로 뚫린다.
5. **지시끼리 충돌하거나 강제력을 부풀린 문장이 있다.**
   - `core-reporting.md` 원칙 2는 "비유·결과 중심으로 설명"하라고 하는데, 사용자가 Claude에 설정한 개인 응답 지침은 "비유·의인화를 쓰지 말라"다(저장소 밖 설정).
   - `doc-reviewer`의 "설명" 유형 필수 섹션(맥락·결정·고려한 대안·트레이드오프)이 기준 문서 `doc-writing.md`(개념 소개·등장 배경·어떻게 동작하는가·관련 문서)와 다르다.
   - `core-workflow.md`는 "트랙이 달라도 G1~G4를 모두 통과한다"고 하면서 생략 조건은 스킬 6곳에 흩어 두었다. 작업 규모별로 어떤 게이트를 건너뛰는지 한 곳에서 알 수 없다.
   - `README.md`는 자기 수정 금지를 "원천 차단", 열린 요청 인터뷰를 "강제"라고 적는다. 실제로는 Bash 편집과 위 매처 구멍으로 우회되고, 인터뷰는 알림 주입뿐이다.

## Architecture Findings

구조 차원에서 본 문제다.

| # | 발견 | 근거 |
|---|------|------|
| A1 | **구성 요소 목록의 SSOT가 선언만 있고 강제가 없다.** `.claude/rules/README.md`가 SSOT라고 적혀 있지만 `component-map.md`·레이어 문서 3개·`architecture-diagrams.md`·`workflow-cycle.md`·`harness-engineering.md`·`README.md`·`AGENTS.md`·`CLAUDE.md`·`docs/README.md`가 같은 목록과 개수를 다시 적는다. 유지보수 체크리스트가 "같은 턴에 갱신"을 사람과 에이전트의 기억에 맡긴다 | 이전 감사 `ROT-2`·`ROT-3`·`ROT-5`가 전부 이 문서들의 불일치였다 |
| A2 | **개수가 산문에 박혀 있다.** "슬롯 22개" 9개 파일, "플래그 8개" 10개 파일. 개수는 바뀔 때마다 전부 틀린다 | `grep` 결과 |
| A3 | **`core-*` 규칙 3개가 독립 관심사가 아니다.** `core-scope`(1,712B)는 `core-guardrails` §1.4 "불확실하면 질문"의 한 사례다. `core-followup`(2,964B)은 완료 뒤 제안 형식이라 안전과 무관하고, 그 안의 ERD 절은 이 저장소에서 꺼진 플래그 절이다. `core-tools`(3,017B)의 호출 규약은 `.claude/rules/README.md`와, 별도 컨텍스트 리뷰는 `core-workflow` G3·`preflight` 8단계와, 도입 기준은 `docs/out-of-scope/README.md`와 겹친다 | 본문 대조 |
| A4 | **꺼진 플래그 절도 항상 실린다.** "절을 지우지 않는다"는 이식성 원칙은 맞지만, `core-guardrails` §1.6·`core-workflow` G1 인용 블록·G3 두 행·`core-followup` ERD 절이 플래그 ❌인 이 저장소에서도 설명 전문으로 실린다. 상세는 이미 lang 팩에 있으므로 core에는 배지 한 줄이면 된다 | 플래그 표 7개 ❌ |
| A5 | **`harness-map.md`의 "쓰는 곳" 열은 `grep`으로 얻을 수 있는 정보다.** 매 세션 실리지만 에이전트 판단에 쓰이지 않는다. 같은 파일의 규칙 3("슬롯은 core에서 실제로 쓰는 곳이 있을 때만")은 산문으로만 지켜진다 | 22개 슬롯 모두 사용처가 있음을 `grep`으로 확인 |
| A6 | **자기 수정 보호는 Write·Edit만 본다.** Bash `sed -i`로 훅을 고치는 경로는 `deny-dangerous-bash.sh`가 보지 않는다. 문서는 이 한계를 적지 않고 "원천 차단"이라고 쓴다 | 두 훅 본문 |
| A7 | **`.claude/rules/README.md`가 너무 크다.** 19,677B로 `.claude/` 하위 파일을 열 때마다 실린다. 훅 표 한 칸이 훅 본문 머리 주석을 그대로 옮긴 수준이다 | `wc -c` |

## Token Optimization

컨텍스트에 실리는 양을 시점별로 쟀다.

| 시점 | 무엇 | 수정 전 바이트 | 줄이는 방법 |
|------|------|------------:|-------------|
| 매 세션 | always-load 규칙 8개 + `CLAUDE.md` + `AGENTS.md` | 51,384 | 규칙 3개 통합 삭제 · `core-workflow` G1·G3을 스킬 포인터로 · `harness-map` 유지보수 열 삭제 · `AGENTS.md`·`CLAUDE.md`의 목록 반복 삭제 · 꺼진 플래그 절은 배지 한 줄 |
| 매 세션 | 스킬 9개 + 에이전트 3개 description | 3,448 | `defer`를 `specify`로 통합 · 설명 안의 이력("Superpowers 대체") 삭제 |
| 열린 표현이 있는 요청마다 | `ask-open-request.sh` 주입 | 약 430 | 훅 삭제 |
| `verify.sh` 실행마다 | 검사기 3개 출력 | 22,430 | 성공한 단계는 요약 한 줄, 실패한 단계만 전체 출력 |
| `.claude/` 하위 파일을 열 때 | `.claude/rules/README.md` | 19,677 | 목록 인덱스로 축소 (훅 상세는 훅 머리 주석이 SSOT) |
| 마크다운을 열 때 | `doc-writing.md` | 12,547 | 이력 예시 절·중복 표 삭제, 검사기가 잡는 항목은 한 줄로 |
| 소스 파일을 열 때 | `core-code-comments.md` | 8,320 | 개정 배경 문단·중복 표·"금지" 되풀이 삭제 |

반복 정보의 대표 사례다.

| 내용 | 반복된 곳 |
|------|-----------|
| G3 검증 절차 | `core-workflow` G3 8줄 ≈ `preflight` 사후 모드 1~8단계 |
| 외부 문서 소스 우선순위 ①~④ | `core-workflow` G1 ≈ `researcher` 본문 |
| 서브에이전트 호출 규약 | `core-tools` · `.claude/rules/README.md` · `component-map` · `layer2` |
| 커밋·PR 규율 | `core-workflow` G2·G4 · `core-gates` §3 · `AGENTS.md` · `AGENTS.template.md` · `CONTRIBUTING.md` |
| 문서 유형 표 | `doc-writing` · `doc-reviewer` · `docs/templates/README.md` (doc-reviewer 판은 내용도 다름) |
| 독자별 규칙 표 | `doc-writing` · `core-code-comments` ("두 곳을 함께 고친다"고 스스로 적음) |

## Rule Findings

판단 기준 다섯 가지(사고 가능성 · 다른 규칙과 중복 · 결정적 검증 가능 · 매번 전달할 가치 · 프로젝트 고유 정보)로 분류했다. `KEEP`은 남기되 압축, `MERGE`는 다른 파일로 옮기고 이 파일은 삭제, `REMOVE`는 옮기지 않고 삭제다. 바이트는 수정 전 값이다.

| 규칙 | 로드 | 바이트 | 판정 | 근거 |
|------|------|-------:|------|------|
| `core-guardrails.md` | 항상 | 7,777 | `KEEP` 압축 | 문서와 다른 값을 조용히 구현하는 사고, 레거시를 남기는 사고를 막는 유일한 규칙. §1.6은 플래그 배지 한 줄로, 끝의 "환경 금지" 목록은 훅 `PATTERNS`가 SSOT라 한 줄로 줄인다. `core-scope` 핵심 두 줄을 §1에 흡수 |
| `core-gates.md` | 항상 | 5,107 | `KEEP` 압축 | 통제/위임 영역과 멈추는 신호는 판단 기준이라 매번 필요. §3 표는 위치만 가리키는 목록으로 줄이고 끝의 "금지"는 본문 되풀이라 삭제. 서드파티 도입은 "의존성 추가" 신호에 한 줄로 |
| `core-workflow.md` | 항상 | 11,830 | `KEEP` 재작성 | 트랙·게이트 순서의 SSOT. G1은 `researcher`, G3는 `preflight`를 가리키는 두세 줄로. 흩어진 생략 조건을 규모 단계(S·M·L) 표 하나로 모은다. `core-followup`·`core-tools`의 남길 내용을 흡수 |
| `core-scope.md` | 항상 | 1,712 | `MERGE` → `core-guardrails` §1 | `[미정]` 임의 확정 금지는 §1.4의 한 사례. 라벨 금지는 `core-gates` §3에 이미 있음 |
| `core-followup.md` | 항상 | 2,964 | `MERGE` → `core-workflow` G4 · lang 팩 | 후속 제안은 안전과 무관하다. 형식 한 줄만 G4로. ERD 제안은 DB 플래그 절이라 lang 팩 "DB 스키마 정책" 절로. Defer 절은 스킬 포인터뿐 |
| `core-tools.md` | 항상 | 3,017 | `MERGE` → `core-workflow` · `core-gates` · out-of-scope | 호출 규약 한 줄과 별도 컨텍스트 리뷰 한 줄만 `core-workflow`로. 도구 도입 기준은 도구를 제안할 때만 필요하므로 `docs/out-of-scope/README.md`로. "금지" 4개는 전부 다른 곳에 있음 |
| `core-reporting.md` | 항상 | 2,485 | `KEEP` 압축 | 사용자가 정한 보고 문체. "비유" 지시를 사용자 설정과 맞게 고친다 |
| `harness-map.md` | 항상 | 9,616 | `KEEP` 압축 | 슬롯 값은 매번 필요. "쓰는 곳" 열은 지우고 훅 상수와 같이 고칠 네 곳만 남긴다. 규칙 3은 `check-portability.sh`의 결정적 검사로 옮긴다 |
| `core-code-comments.md` | 소스 파일 | 8,320 | `KEEP` 압축 | 개정 배경 문단·독자 표·"금지" 되풀이 삭제 |
| `core-testing.md` | 테스트 파일 | 6,462 | `KEEP` | 2026-10-05 승인된 스펙의 산출물이고 S1~S8이 겹치지 않는다. 손대지 않는다 |
| `doc-writing.md` | md 파일 | 12,547 | `KEEP` 압축 | 이력 예시 절, 독자 표, 검사기와 같은 내용의 검증 표를 줄인다 |
| `.claude/rules/README.md` | `.claude/` 파일 | 19,677 | `KEEP` 압축 | 구성 요소 목록의 단일 SSOT로 남긴다. 다른 목록 문서는 지우고, `check-portability.sh`가 이 목록과 실물을 대조하게 한다 |

## Skill Findings

스킬 본문은 호출될 때만 실린다. 항상 실리는 것은 description뿐이다.

| 스킬 | 목적 | 호출 조건 | 실제 효과 | 중복 | 토큰 비용 (desc / 본문) | 판정 |
|------|------|-----------|-----------|------|-------------------------|------|
| `adopt` | 하네스 이식·재동기화 (D 트랙) | 사용자 | 실측 기반 슬롯 채움, 산출물 체크리스트 | 없음 | 311 / 9,018 | `KEEP` — 지운 훅 언급·개수 문구만 고침. ⬜ 확인을 체크리스트의 `grep` 한 줄로 (훅 삭제 대체) |
| `ask` | 열린 요청 라운드 인터뷰 | 에이전트 | 사실은 조사, 결정만 질문 | `specify` 4단계 "모호함 해소"와 일부 | 396 / 5,067 | `KEEP` — 훅이 사라지므로 트리거는 `core-gates` §2와 description |
| `specify` | 스펙 작성·승인 (A 트랙) | 에이전트 | 승인 전 코드 금지 | `defer` 1~3단계가 스펙 작업 | 177 / 4,496 | `KEEP` + `defer` 흡수 |
| `tdd` | 승인 지점 실패 테스트 먼저 | 에이전트 | 증거 표 | 없음 | 359 / 8,277 | `KEEP` — 지운 `core-tools` 참조만 고침 |
| `safe-refactor` | 감사 → 승인 → 구현 (B 트랙) | 사용자 | 감사 문서·불변 조건 | 게이트 대응 표가 `core-workflow`와 겹침 | 330 / 7,740 (+참고 7,587) | `KEEP` — 대응 표를 한 줄로 |
| `debug` | 재현 → 원인 → 수정 (C 트랙) | 에이전트 | 재현 없는 수정 금지 | 없음 | 262 / 3,399 | `KEEP` — description의 이력 문구, 지운 파일 참조, 오타("手patch") 수정 |
| `preflight` | G2 직후·완료 전 검증 | 에이전트 | 실행 결과만 보고 | `core-workflow` G3와 1:1 | 355 / 5,924 | `KEEP` — G3의 SSOT로 남기고 `core-workflow` 쪽 사본을 지운다 |
| `defer` | 범위를 다른 이슈로 미루기 | 에이전트 | Draft 스펙 + Approved amend + 이슈 | 1~3단계가 `specify` 템플릿·amend 작업 | 220 / 3,141 | `MERGE` → `specify`의 "범위를 미룰 때" 절. 트리거 문구는 `specify` description으로 |
| `retro` | 하네스 회고 백로그 | 사용자·에이전트 | `harness-retro.md`에 실제 5건 기록 | G4·`core-followup` "반복 주제"와 같은 말 | 267 / 5,772 | `KEEP` — 설계 이유 문단 압축 |

**스킬 간 호출 중복:** `specify → tdd → test-writer`와 `debug → tdd` 경로에서 같은 파일을 두 번 읽는 곳은 없었다. `test-writer`는 스펙 경로만 받고 `core-testing.md`를 읽는데, 같은 대화가 아니라 별도 컨텍스트라서 중복이 아니다. 반대로 `safe-refactor` 감사 서브에이전트에게 넘기는 목록(체크리스트·템플릿 전체)은 의도된 입력이다.

**과도한 스킬:** 하나가 요구사항부터 문서화까지 전부 하는 스킬은 없었다. 가장 넓은 `safe-refactor`도 단계마다 승인을 받는다.

## Hook Findings

각 훅을 여덟 가지 질문(무엇을 막나 · 이벤트 · 실제 위험 · 중복 · 오탐 · 정상 작업 방해 · 스크립트로 옮길 수 있나 · 실시간이어야 하나)으로 봤다. `BLOCKING`은 실시간 차단이 필요해 유지, `REDUNDANT`는 다른 장치가 같은 일을 하거나 하는 일이 없어 삭제 대상이다.

| 훅 | 이벤트 | 막는 것 | 분류 | 오탐·문제 | 판정 |
|----|--------|---------|------|-----------|------|
| `deny-dangerous-bash.sh` | PreToolUse · Bash | force push · 재귀 삭제 · hard reset · 강제 clean · `--no-verify` · `.env` 커밋 · SQL `DROP` 등 16종 | `BLOCKING` | 문자열로만 언급해도 막힘(의도된 fail-closed). 커밋 메시지 안의 `-n`으로 시작하는 단어도 걸릴 수 있음 | 유지. 되돌릴 수 없는 명령은 실행 전에 막아야 한다 |
| `deny-out-of-scope-write.sh` | PreToolUse · Write\|Edit | 범위 밖 쓰기 · (자기 수정 ❌일 때) 훅·settings 쓰기 | `BLOCKING` | **매처가 `MultiEdit`·`NotebookEdit`를 놓친다** — 훅 본문은 `notebook_path`까지 처리하지만 불리지 않는다 | 유지 + 매처를 `Write\|Edit\|MultiEdit\|NotebookEdit`로. `test-hooks.sh` 등록 대조에 매처 검사 추가 |
| `deny-unverified-completion.sh` | Stop | 코드 편집 뒤 검증 미실행·실패인데 완료 선언 | `BLOCKING` (한 번만 되돌림) | 완료 단어 정규식이 넓어 한 턴짜리 오탐 가능. `.txt` 데이터 파일 편집은 코드로 안 셈 | 유지. "실행했는가"는 exit code로 판정되는 대표 항목 |
| `ask-open-request.sh` | UserPromptSubmit | 없음 — 알림 주입 | `REDUNDANT` | 단어만 보고 판단해 구체적 요청에도 붙는다. 같은 신호가 always-load 규칙과 스킬 설명에 이미 있다 | 삭제. 모호성 판단은 LLM 몫이다 |
| `warn-unfilled-map.sh` | SessionStart | 없음 — 경고 주입 | `REDUNDANT` | 배달본 map이 이미 채워져 있어 어떤 상황에서도 출력이 없다 | 삭제. 같은 확인은 `adopt` 체크리스트의 `grep` 한 줄로 |

`permissions.deny`는 훅과 겹치지만 유지한다. `.env` 읽기 차단은 훅에 없는 항목이고, 도구 권한 층은 컨텍스트를 쓰지 않는다.

## Agent Findings

세 에이전트 모두 "같은 컨텍스트를 다시 읽고 같은 결론을 내는" 구조는 아니었다.

| 에이전트 | 독립성 | 결과가 쓰이나 | 판정 |
|----------|--------|---------------|------|
| `researcher` | 웹 문서 원문을 메인 컨텍스트 밖에서 소비하고 결론만 돌려준다 — 토큰 절약 효과가 실제로 있다 | G1 근거로 스펙에 남는다 | `KEEP`. `core-workflow` G1의 소스 우선순위 사본은 지운다 (에이전트 본문이 SSOT) |
| `test-writer` | 구현 계획을 받지 않고 스펙 문장만 본다 — 메인 대화와 입력이 다르다 | `tdd` 증거 표(실패 → 통과)의 근거 | `KEEP` (2026-10-05 승인) |
| `doc-reviewer` | 문서를 쓴 대화의 맥락이 없다 | advisory 지적 | `KEEP` 압축. 본문의 유형 표가 기준 문서와 **충돌**하므로 지우고 `doc-writing.md`를 가리킨다. H4·제목 30자·약어 같은 검사기 항목은 점검 목록에서 뺀다 — 검사기가 이미 결정적으로 잡는다 |

## Workflow Findings

수정 전 규칙은 "진입 → G1 → G2 → 구현 → G3 → G4"를 모든 트랙에 적용한다고 적고, 작업이 작을 때 무엇을 건너뛰는지는 6곳에 나뉘어 있다.

| 생략 조건이 적힌 곳 | 내용 |
|---------------------|------|
| `specify` | 오타·단일 테스트·로그 한 줄·명확한 버그 핫픽스는 생략 |
| `ask` | 오타·한 줄 수정·핫픽스·Approved 스펙이 있으면 쓰지 않음 |
| `preflight` | 오타·문서 전용·로그 문구는 생략 |
| `retro` | 오타·단일 파일 핫픽스는 생략, Must Have급에서 사용 |
| `core-followup` | 한 줄·단일 파일·핫픽스는 생략, Must Have급은 권장 |
| `core-tools` | 별도 컨텍스트 리뷰는 Must Have급 커밋 전, 핫픽스는 강제 안 함 |

이 조건들을 의미 변경 없이 규모 단계 표 하나로 모은다.

| 단계 | 조건 | 거치는 것 |
|------|------|-----------|
| **S 단순** | 오타·문구·로그 한 줄·단일 파일 핫픽스이면서 통제 영역(`core-gates` §1)에 닿지 않음 | 바로 구현 → 코드를 고쳤으면 `{{테스트 명령}}` → 커밋 분할안 |
| **M 표준** | S도 L도 아님 | 트랙 스킬 → G2 승인 → 구현 → `preflight` → 커밋 분할안·문서 갱신 점검 |
| **L 강화** | 3파일 이상 · API · DB (기존 "Must Have급") | M + 별도 컨텍스트 리뷰 · `report.md` · 후속 제안 · `retro` 검토 |

G1은 단계와 무관하게 외부 라이브러리·API 지식이 필요할 때만이다. 통제 영역에 닿으면 S가 될 수 없다 — 지금 규칙(`core-gates` §1)과 같다.

**LLM 호출을 줄일 수 있는 곳:** `doc-reviewer`가 검사기 항목까지 다시 보는 것, `verify.sh` 성공 출력을 매번 읽는 것.

## Prompt 품질

always-load 파일에서 "적절히·충분히·필요하면" 같은 모호한 표현은 2곳뿐이었다(`core-guardrails` §1.5 "필요하면 `gh issue view`", `core-scope` "필요 시 별도 작업으로"). 둘 다 행동을 정하는 조건이 아니라 보조 수단이다. 대신 "금지"가 40회 나오고 그 다수가 같은 파일 본문의 되풀이다.

| 종류 | 위치 | 처리 |
|------|------|------|
| 충돌 | `core-reporting` "비유·결과 중심" ↔ 사용자 설정 "비유 금지" | "결과 중심"으로 고친다 |
| 충돌 | `doc-reviewer` 설명 유형 섹션 ↔ `doc-writing` | `doc-reviewer`의 표 삭제 |
| 충돌 | `core-workflow` "모든 게이트 통과" ↔ 스킬 6곳의 생략 조건 | 규모 단계 표 |
| 우선순위 불명확 | `AGENTS.md`(이 저장소: 완료 전 항상 `verify.sh`) ↔ `preflight`(문서 전용은 생략 가능) | 이 저장소에서는 문서가 검사 대상이라 `AGENTS.md`가 더 엄격한 프로젝트 규칙으로 우선한다고 `AGENTS.md`에 명시 |
| 설명을 강제로 오인 | `README.md` "원천 차단"·"강제" · `core-gates` 금지 표의 훅 우회 | 실제 동작대로 고쳐 적는다 |
| 이력이 지시 사이에 섞임 | `core-code-comments` 개정 배경 · `doc-writing` "실제로 고친 예시" · `adopt`·`retro`의 계기 문장 | 규칙에서 빼고 필요한 것은 스펙·보고서에 둔다 |

## 결정적 검증과 LLM 판단의 경계

반대로 놓인 곳과 옮길 곳이다.

| 지금 | 문제 | 옮길 곳 |
|------|------|---------|
| `ask-open-request.sh`가 정규식으로 요청의 모호성을 판단 | LLM이 할 판단을 결정적 시스템이 하고 있다 | 훅 삭제 — `core-gates` §2 신호를 LLM이 판단 |
| `harness-map` 규칙 3 "슬롯은 실제로 쓰는 곳이 있을 때만" | 산문 규칙 + 수동 "쓰는 곳" 열 | `check-portability.sh`가 정의된 슬롯 ↔ 사용된 슬롯을 대조 |
| "구성 요소를 바꾸면 README·component-map·core-workflow를 같은 턴에 갱신" | 기억에 맡긴 동기화 | `check-portability.sh`가 실제 스킬·에이전트·훅·규칙 파일 ↔ `.claude/rules/README.md` 언급을 대조. 목록 문서 수는 줄인다 |
| `doc-reviewer`가 H4·제목 길이·약어를 점검 | 검사기가 이미 판정하는 항목을 LLM이 다시 본다 | 리뷰어 점검 목록에서 삭제 |
| 개수("슬롯 22개") 산문 | 바뀔 때마다 틀린다 | 개수 문구 삭제 |

이미 맞게 놓인 것(유지): 위험 명령 차단(훅) · 테스트 실행 여부(Stop 훅) · 부품 계약(검사기) · 문서 구조(검사기) · 커밋 형식(git 훅) · 요구사항 해석·설계 비교·리뷰(스킬·에이전트).

## Priority

위 발견을 고칠 순서로 묶었다. P0는 실제 보호 구멍, P1은 매 세션 비용·충돌, P2는 유지보수 비용, P3는 기능 추가이거나 영향이 작은 것이다.

| 우선순위 | 항목 |
|----------|------|
| **P0** | `Write\|Edit` 매처 구멍 수정 (`MultiEdit`·`NotebookEdit`) · 등록 대조에 매처 검사 · `README.md`의 과장된 강제력 문구 정정 |
| **P1** | always-load 규칙 3개 통합 삭제 · `core-workflow` 규모 단계와 G1·G3 포인터화 · `harness-map` 유지보수 열 삭제 · `verify.sh` 출력 축소 · 효과 없는 훅 2개 삭제 · 충돌 2건(`core-reporting`·`doc-reviewer`) 해소 |
| **P2** | 목록 문서 6개 삭제 + 구성 요소 목록 대조 검사 · 슬롯 사용 대조 검사 · `defer` → `specify` 통합 · `.claude/rules/README.md`·`doc-writing`·`core-code-comments` 압축 · `AGENTS.template.md`에서 core 규칙 되풀이 삭제 · 개수 문구 삭제 · 예산 래칫 하향 |
| **P3** | Bash 편집으로 훅을 고치는 경로 차단 (자기 수정 ❌ 프로젝트) · Stop 훅의 `.txt` 예외 재검토 · `CONTRIBUTING.md` 에이전트 규율 절 축소 · `learning-doc`·`how-to-doc` 템플릿 사용처 재검토 |

P3는 이번에 적용하지 않고 "남은 것"에 둔다. 앞의 둘은 기능 추가에 해당하고, 뒤의 둘은 영향이 작다.

## 목표 구조 — 수정 전과 개선

감사 시점에 정한 목표다. 실제 결과 수치는 "적용 결과"의 "토큰 최적화" 표에 있다.

| 영역 | 수정 전 | 개선 | 무엇을 |
|------|------|------|--------|
| always-load 규칙 | 8개 (51,384B, 문서 2개 포함) | 5개 (목표 ≤ 32,000B) | `core-scope`·`core-followup`·`core-tools` 통합 삭제 |
| 파일 접근 시 규칙 | 4개 (47,006B) | 4개 (목표 ≤ 30,000B) | 압축. `core-testing`은 그대로 |
| 스킬 | 9개 | 8개 | `defer` → `specify` |
| 에이전트 | 3개 | 3개 | `doc-reviewer` 충돌·검사기 중복 제거 |
| 훅 | 5개 | 3개 | `ask-open-request`·`warn-unfilled-map` 삭제, 매처 수정 |
| 스크립트 | verify + 검사기 3 + probe + git 훅 2 | 같음 | `verify.sh` 조용한 성공 출력 · `check-portability`에 슬롯·목록 대조 · 예산 하향 · `test-hooks` 매처 검사 |
| 하네스를 설명하는 살아 있는 문서 | 13개 (약 141KB) | 7개 | `component-map`·레이어 문서 3개·`architecture-diagrams`·`workflow-cycle` 삭제 |
| 워크플로 | 모든 트랙 4게이트 + 생략 조건 6곳 | 규모 단계 S·M·L 한 표 | 의미 변경 없이 모음 |

**바꾸지 않는 것(불변 조건):** 위험 명령 차단 패턴 16종 · 훅 공통 규약(판정 불가 = 차단, Stop만 예외) · Stop 훅 판정 로직 · 부품 계약 C1~C4 · 문서 스타일 오류 판정 · 커밋 형식 · 승인 게이트(G2)가 필요한 조건 · `core-testing`·`tdd`·`test-writer` 본문(2026-10-05 승인).

## 적용 결과

여기부터는 감사 결과를 실제로 적용한 뒤에 쓴 절이다. P0~P2를 적용했고, P3 중 `CONTRIBUTING.md` 축소는 사용자 요청으로 뒤이어 적용했다. 나머지 P3는 "남은 것"에 뒀다. 적용 중에 감사 때 보지 못한 결함 1건과 리뷰가 찾은 결함 5건을 함께 고쳤다.

### 제거한 것

| 무엇 | 이유 |
|------|------|
| `.claude/hooks/ask-open-request.sh` | 단어만 보고 알림을 붙여 구체적인 요청에도 붙었다. 같은 신호가 `core-gates.md` §2와 `ask` 설명에 있고, 차단을 못 하는 훅이라 지워도 막히던 동작이 없다 |
| `.claude/hooks/warn-unfilled-map.sh` | 배달본 `harness-map.md`가 채워져 있어 출력하는 상황이 없었다. 같은 확인은 `adopt` 체크리스트의 `grep` 한 줄로 옮겼다 |
| `.claude/rules/core-scope.md` · `core-followup.md` · `core-tools.md` | 아래 "통합한 것" |
| `.claude/skills/defer/` | 아래 "통합한 것" |
| `docs/harness/component-map.md` · `layer1-human-gate.md` · `layer2-workflow-skills.md` · `layer3-deterministic-hooks.md` · `architecture-diagrams.md` · `docs/workflow-cycle.md` | 구성 요소 목록을 다시 적은 문서다. 목록 SSOT(`.claude/rules/README.md`) 하나와 결정적 대조 검사로 대체했다 |
| `hook-cases.txt`의 지운 훅 케이스 6개 | 훅이 없어졌다 |
| `doc-reviewer`의 유형 표·검사기 중복 항목 | 기준 문서와 충돌했고, 검사기가 이미 판정한다 |
| 규칙 안의 설계 이력·개정 배경·"실제로 고친 예시" 절 | 판단에 쓰이지 않는다. 이력은 보고서·스펙·git에 있다 |
| 산문 속 개수("슬롯 22개"·"플래그 8개"·"스킬 9개" 등) | 바뀔 때마다 틀린다. 날짜를 밝힌 `harness-engineering.md` "숫자로 보는 현재"만 남겼다 |

### 통합한 것

| 기존 | 새 위치 |
|------|---------|
| `core-scope` — `[미정]` 표기·라벨 금지 | `core-guardrails.md` §1.8 |
| `core-followup` — 후속 제안 형식 | `core-workflow.md` G4 (L 규모) |
| `core-followup` — ERD 제안 | lang 팩 "DB 스키마 정책" 절 (`java-spring` 씨앗 본문 · `_template` 안내) |
| `core-tools` — 서브에이전트 호출 규약 | `core-workflow.md` "구현" |
| `core-tools` — 별도 컨텍스트 리뷰 | `core-workflow.md` G3 (L 규모) |
| `core-tools` — 서드파티 도입 기준 | `docs/out-of-scope/README.md` "도입 기준" + `core-gates.md` §2 "의존성 추가" |
| `defer` 스킬 | `specify` 스킬 "범위를 미룰 때" 절 (트리거 문구는 `specify` 설명) |
| 스킬 6곳에 흩어진 생략 조건 | `core-workflow.md` 규모 표 S·M·L |
| `CONTRIBUTING.md`의 에이전트 주의 2곳·"커밋 분할 (에이전트)" 표 | 머리의 SSOT 문장 한 줄(`core-workflow.md` G2·G4). 표에만 있던 "파일 단위로 쪼개지 않기"·"중간 커밋도 테스트 통과"는 G4로 옮겼다. 없는 `examples/` 견본을 가리키던 라벨 행도 고쳤다 |
| `core-workflow` G1 소스 우선순위 사본 | `researcher` 에이전트 (G1에는 한 줄) |
| `core-workflow` G3 8줄 | `preflight` 스킬 (G3에는 포인터와 L 규모 리뷰만). G3에만 있던 "`{{API 문서}}` 동기화·이슈 갱신"은 `preflight` 4단계로 옮겼다 |

### 변경한 것

| 무엇 | 이유 |
|------|------|
| 쓰기 훅 매처 `Write\|Edit` → `Write\|Edit\|MultiEdit\|NotebookEdit` | 공식 문서상 정확한 이름 목록이라 두 도구가 훅을 건너뛰었다 (P0) |
| `test-hooks.sh` 등록 대조에 매처 검사 | 같은 구멍이 다시 생기면 실패한다. `"*"`·빈 매처는 전체로, 해석할 수 없는 정규식은 문제로 보고한다 |
| `test-hooks.sh`가 복사하지 않은 씨앗 훅 케이스를 건너뜀 | **적용 중 발견:** 새 프로젝트는 `examples/`를 복사하지 않는데 씨앗 훅 케이스 10개가 "훅 파일 없음"으로 실패해 `verify.sh`가 처음부터 실패했다. 배달물 훅(접두사 없음)이 없으면 여전히 실패이고, 이름을 직접 지정했는데 0건이면 exit 2다 |
| `verify.sh` — 통과한 단계는 요약 한 줄 | 통과 출력 22,430B가 코드 편집 뒤마다 컨텍스트에 쌓였다. 실패한 단계는 전체 출력을 그대로 보인다. `VERIFY_VERBOSE=1`이면 전부 |
| `check-portability.sh` — 슬롯 대조(S)·구성 요소 대조(I) 추가 | `harness-map` 규칙 3과 "구성 요소를 바꾸면 목록을 같은 턴에" 유지보수 규칙을 산문에서 검사로 옮겼다. 적용 중 이 검사가 지운 규칙·훅을 가리키는 문장 26곳을 찾았다 |
| always-load 예산 52,000B → 28,000B | 래칫 — 실측 27,341B |
| `core-reporting.md` 원칙 2 | "비유·결과 중심"을 "결과 중심, 비유 대신 실제로 일어난 일"로. 사용자 설정과 충돌했다 |
| `README.md`의 강제력 문구 | "원천 차단"·"강제"를 실제 동작(파일 쓰기 도구만 차단 · 규칙과 스킬로 질문)으로. 작업 분해 행도 "강제 수단 없음"으로 고쳤다 |
| `AGENTS.template.md` | core 규칙을 되풀이하던 줄을 지웠다. 이 파일은 붙여 쓰는 프로젝트마다 매 세션 실린다 |
| `adopt` 3단계 | "`{{작업 범위}}`는 같은 훅의 `SCOPE`"가 엉뚱한 훅을 가리켰다 — `harness-map.md` "훅 상수와 짝" 목록으로 |
| `debug` | 설명의 이력 문구 삭제, 오타("手patch") 수정 |

**리뷰가 찾은 결함 (모두 재현 후 수정):** 별도 컨텍스트 `code-review`가 새 검사에서 오탐 5건을 찾았다. ① 프로젝트 문서의 "core-domain 모듈" 같은 이름을 규칙 참조로 봄 ② 복사한 `local-*` 에이전트를 없다고 봄 ③ 내장·플러그인 스킬(`security-review` 등)을 없다고 봄 ④ `--scope core`에서 슬롯을 미사용으로 봄 ⑤ 매처 `"*"`에서 등록 대조가 멈춤. 하네스가 쓰는 파일과 프로젝트가 쓰는 파일을 나눠 보고, 스킬·에이전트는 git 이력에서 **지워진** 이름만 잡고, 슬롯 사용은 범위 옵션과 무관하게 배달물 전체에서 세도록 고쳤다. 다섯 경우를 다시 돌려 오탐이 없고, 진짜 남은 참조는 여전히 잡는 것을 확인했다.

### 유지한 것

| 무엇 | 없으면 생기는 일 |
|------|------------------|
| `deny-dangerous-bash.sh` + `permissions.deny` | force push·재귀 삭제·hard reset·`.env` 커밋이 실행된다. 되돌릴 수 없다 |
| `deny-out-of-scope-write.sh` | 붙여 쓰는 프로젝트에서 에이전트가 자기 훅을 `exit 0`으로 바꿀 수 있다. 모노레포에서 다른 모듈을 쓴다 |
| `deny-unverified-completion.sh` | 테스트를 안 돌리고 "완료"라고 말해도 턴이 끝난다 — 이 하네스가 결정적으로 막는 유일한 거짓 보고 |
| 검사기 3개 + git 훅 2개 | core에 프로젝트 사실이 새고, 문서 구조가 깨지고, 훅이 열린 채 커밋된다 |
| `core-guardrails` · `core-gates` · `core-workflow` · `core-reporting` · `harness-map` | 문서와 다른 값 구현, 승인 없는 통제 영역 변경, 순서 없는 작업, 사용자가 못 읽는 보고 |
| 스킬 8개 · 에이전트 3개 | 각각 트랙 진입·승인 절차·별도 컨텍스트 판단의 유일한 위치 — 겹치던 `defer`만 합쳤다 |
| `core-testing` · `tdd` · `test-writer` | 2026-10-05 승인된 스펙의 산출물이고 겹치는 곳이 없다. 참조 한 줄만 고쳤다 |

### 토큰 최적화

| 시점 | 전 | 후 | 변화 |
|------|---:|---:|---:|
| 매 세션 — always-load 규칙 + `CLAUDE.md` + `AGENTS.md` | 51,384B (≈20.5k 토큰) | 27,341B (≈10.9k 토큰) | −47% |
| 매 세션 — 스킬·에이전트 description | 3,448B | 3,343B | −3% |
| 열린 표현 요청마다 — 훅 주입 | 약 430B | 0 | 훅 삭제 |
| `verify.sh` 통과 1회 | 22,430B | 307B | −99% |
| 파일 접근 시 규칙 4개 합계 | 47,006B | 26,211B | −44% |
| ├ `.claude/rules/README.md` | 19,677B | 7,881B | −60% |
| ├ `doc-writing.md` | 12,547B | 5,029B | −60% |
| └ `core-code-comments.md` | 8,320B | 6,839B | −18% |
| 하네스를 설명하는 살아 있는 문서 | 13개 · 141,056B | 7개 · 43,566B | −69% |
| 새 프로젝트의 always-load (`AGENTS.md`·`CLAUDE.md` 제외) | 44,508B | 24,212B | −46% |

저장소 전체 diff는 55개 파일이다(삽입·삭제 줄 수는 커밋 기록에 있다).

### 안전성 영향

| 바뀐 것 | 새로 생길 수 있는 위험 | 판단 |
|---------|------------------------|------|
| 열린 요청 알림 훅 삭제 | 에이전트가 열린 요청을 바로 구현할 가능성이 조금 늘 수 있다 | 판단 주체는 원래 LLM이었다. 규칙(`core-gates` §2)과 스킬 설명은 그대로 실린다 |
| 미결정 설정 경고 훅 삭제 | ⬜를 남긴 map을 세션마다 알려 주지 않는다 | 배달 흐름에서 원래 출력이 없었다. `adopt` 체크리스트가 `grep`으로 확인한다 |
| 목록 문서 삭제 | 사람이 읽을 그림·입문 자료가 줄었다 | git 이력에 남아 있다. 목록 정확성은 오히려 검사로 강제된다 |
| `verify.sh` 출력 축소 | 통과 시 경고(W)를 못 본다 | 경고는 차단 기준이 아니었고 59건이 처리되지 않은 채 있었다. 개별 파일 검사는 전체를 보여 준다 |
| 씨앗 훅 케이스 건너뛰기 | 씨앗 훅 이름을 잘못 적으면 건너뛸 수 있다 | `local-*` 접두사에만 적용되고, 이름을 지정해 돌리면 0건이 exit 2다 |
| 규칙 압축 | 지운 문장에 담긴 판단 기준이 사라졌을 수 있다 | 지운 문장은 다른 파일의 같은 내용이거나 이력이었다. `core-scope`의 "구현된 기능을 문서가 stale하다고 Out으로 두지 않는다"와 `core-followup`의 후속 제안 "점검 축" 목록은 옮기지 않고 지웠다 — 규칙이 아니라 예시였다 |

**보호 수준이 올라간 곳:** 쓰기 훅 매처, 등록 대조의 매처 검사, 지운 구성 요소를 가리키는 문장 차단, 새 프로젝트에서 `verify.sh`가 처음부터 통과.

### 검증 결과

| 검증 | 실행한 명령 | 결과 |
|------|-------------|------|
| 이 저장소 전체 | `scripts/verify.sh` | 통과 — 부품 계약 위반 0 · 대조 위반 0 · always-load 27,341B / 28,000B · 훅 케이스 102/102 · 문서 오류 0 |
| 새 프로젝트 이식 | `.claude`·`scripts`·`docs/templates`만 빈 git 저장소에 복사 → `scripts/verify.sh` | 통과 — 케이스 91/91, 씨앗 10개 건너뜀. 수정 전에는 10개 실패 |
| git 훅 설치 | 위 저장소에서 `scripts/install-git-hooks.sh` → 형식 틀린 메시지·맞는 메시지로 커밋 | 틀린 메시지 exit 1로 차단 · 맞는 메시지 커밋 성공 (pre-commit 통과) |
| 매처 검사 | `settings.json`을 `Write\|Edit`로 되돌린 사본에서 `test-hooks.sh` | 실패 — "MultiEdit, NotebookEdit를 덮지 않음" · `Edit.*\|Write` 정규식은 통과 |
| 대조 검사 음성 시험 | 사본에 지운 규칙 참조·목록에 없는 스킬·정의 안 된 슬롯·안 쓰는 슬롯·지운 훅 참조·예산 초과를 각각 넣음 | 여섯 경우 모두 실패로 판정 |
| `verify.sh` 실패 경로 | 사본에 H4를 넣고 실행 | exit 1, 실패 단계만 전체 출력 |
| 리뷰 | `code-review` (별도 컨텍스트, 변경 스크립트 대상) | 5건 — 전부 재현 후 수정·재시험 |
| 문서 리뷰 | `doc-reviewer` (신규 1 · 50줄 이상 수정 7) | 반드시 고칠 것 5건 — 이 보고서가 끝나지 않았음 · 같은 보고서 안의 모순 1문장 · `docs/harness/README.md`의 개수 문구 · 스킬 4곳의 생략 조건이 규모 표와 다름 · "Must Have급"과 "L 규모" 혼용. 전부 반영. 고치면 좋을 것 중 표 앞 설명·열 이름·용어 풀이·근거 링크·제목 길이도 반영. 영어·한국어 제목 혼용은 사용자가 요청한 절 이름을 따른 것이라 그대로 뒀다 |

### 검증하지 못한 것

| 무엇 | 왜 못 했나 | 누가·언제 확인하나 |
|------|-----------|-------------------|
| 실제 Claude Code 세션에서 `MultiEdit`·`NotebookEdit` 호출이 훅을 거치는지 | 이 세션은 자기 수정 ☑·범위 `.`라 훅이 즉시 통과한다. 매처 해석은 공식 문서로만 확인했다 | 자기 수정 ❌ 프로젝트에서 `.claude/settings.json`에 `NotebookEdit`·`MultiEdit`로 쓰기를 시도해 차단되는지 본다 |
| 토큰 수 | 바이트/2.5 추정이다. 토크나이저로 세지 않았다 | 필요하면 실제 세션의 컨텍스트 사용량으로 비교 |
| 규모 단계(S·M·L)가 실제 작업에서 덜 묻고 덜 읽게 하는지 | 행동 변화는 다음 작업들에서만 관찰된다 | 다음 몇 작업의 `retro` |

### 최종 Architecture

```text
CLAUDE.md → @AGENTS.md                       (항상 · 이 저장소 지도)
.claude/
├── settings.json                            훅 3개 등록 + permissions.deny
├── rules/
│   ├── core-guardrails.md                   항상 — ⛔ STOP (§1 정합 · §1.8 [미정] · §2 레거시 · §3 현재동작)
│   ├── core-gates.md                        항상 — 통제/위임 · 멈추는 신호 · 자동으로 하지 않는 것
│   ├── core-workflow.md                     항상 — 트랙 4 × 규모 S·M·L × 게이트 4
│   ├── core-reporting.md                    항상 — 보고 문체
│   ├── harness-map.md                       항상 — 축·슬롯·플래그 값 · 훅 상수 짝
│   ├── core-code-comments.md                소스 파일
│   ├── core-testing.md                      테스트 파일
│   ├── doc-writing.md                       마크다운
│   └── README.md                            .claude/ 구성 요소 — 목록 SSOT
├── skills/  adopt · ask · specify(+범위 미루기) · tdd · safe-refactor · debug · preflight · retro
├── agents/  researcher · test-writer · doc-reviewer
└── hooks/
    ├── deny-dangerous-bash.sh               PreToolUse Bash
    ├── deny-out-of-scope-write.sh           PreToolUse Write|Edit|MultiEdit|NotebookEdit
    └── deny-unverified-completion.sh        Stop
scripts/
├── verify.sh                                {{테스트 명령}} — 통과는 한 줄씩, 실패는 전체
├── check-portability.sh                     부품 계약 C1~C4 · 슬롯 대조 S · 구성 요소 대조 I · 예산 28,000B
├── test-hooks.sh                            훅 규약 · 등록·매처 대조 · 씨앗 케이스 건너뛰기
├── check-doc-style.sh                       문서 구조·문장
├── adopt-probe.sh                           adopt 1단계 실측
└── git-hooks/  pre-commit · commit-msg
docs/
├── harness/README.md                        4개 레이어 · 현재동작 요약
├── harness-engineering.md · references.md   설계 이유 · 출처
├── out-of-scope/README.md                   안 하기로 한 것 + 도구 도입 기준
├── templates/                               산출물 등록부 · 유형별 템플릿 (배달)
└── specs/ · reports/ · audits/ · decisions/ 기록
examples/  baro/ (채운 map 견본) · seeds/{_template, java-spring}/
```

### 남은 것

- **P3 — Bash로 하네스 파일 고치기:** 자기 수정 ❌ 프로젝트에서 `sed -i .claude/hooks/...`는 여전히 훅이 막지 않는다(규칙으로만 금지). 막으려면 `deny-dangerous-bash.sh`가 플래그 값을 알아야 해서 훅 두 개가 상수를 나눠 갖게 된다 — 기능 추가라 이번에 하지 않았다
- **P3 — Stop 훅의 `.txt` 예외:** `scripts/*.txt`·`requirements.txt`처럼 동작을 바꾸는 데이터 파일 편집을 코드 편집으로 세지 않는다
- **P3 — 템플릿 사용처:** `learning-doc.md`·`how-to-doc.md`는 이 저장소에서 지금 쓰는 문서가 없다. 유형 체계의 일부라 뒀다

## 관련 문서

- [`2026-09-07-harness-audit-baseline.md`](2026-09-07-harness-audit-baseline.md) — 이전 전수 감사 (기준선)
- [`../out-of-scope/README.md`](../out-of-scope/README.md) — 이번에 지운 장치와 다시 볼 조건
- [`../harness/README.md`](../harness/README.md) — 수정 뒤 현재 동작 요약
- [`../../.claude/rules/README.md`](../../.claude/rules/README.md) — 수정 뒤 구성 요소 목록 (SSOT)
