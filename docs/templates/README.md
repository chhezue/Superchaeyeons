# 문서 산출물 등록부 (`docs/templates/`)

이 저장소의 **모든 마크다운 문서가 어디에 쌓이고 어떤 형식을 따르는지**를 한 곳에 모은 표다. 스킬이 자동으로 만드는 산출물뿐 아니라 사람이 직접 쓰는 문서도 전부 포함한다 — 어느 쪽이든 `{{문서 루트}}` 밖에 두거나 등록부에 없는 형식으로 쓰지 않는다. 새 문서를 쓸 때는 여기서 유형을 찾아 해당 템플릿을 복사하고, 새 산출물을 만드는 스킬을 추가할 때는 여기에 행을 먼저 추가한다.

문서 루트는 `harness-map.md`의 `{{문서 루트}}` 슬롯 하나다(기본 `docs/`). 모노레포처럼 저장소 루트 `docs/`를 하네스가 소유하지 않는 프로젝트는 슬롯을 하위 경로로 바꾸고, 그 밖으로의 쓰기는 `deny-out-of-scope-write.sh` 훅이 막는다.

유형 판정 순서와 문장·구조 작성 기준은 [`.claude/rules/doc-writing.md`](../../.claude/rules/doc-writing.md)가 SSOT다.

## 언제 이 문서를 보는가

- 새 문서를 만들기 전에 어떤 템플릿을 쓸지 정할 때
- 스킬이 만든 산출물이 어디에 저장돼야 하는지 확인할 때
- md를 새로 만드는 스킬·에이전트를 추가할 때 (등록부에 행 추가가 먼저다)

## 산출물 등록부

위쪽은 하네스가 배달하는 산출물이라 **경로 패턴이 모든 프로젝트에 같다** — `{{슬롯}}`만 `harness-map.md` 값으로 읽으면 된다. 아래쪽 "프로젝트 문서" 행은 **값 자체가 저장소마다 다르다** — `adopt`이 채우며, 여기엔 이 저장소(하네스 템플릿 자체)의 `harness-map.md` 값을 그대로 옮겨 적었다.

| 산출물 | 만드는 것 | 저장 경로 | 유형 | 템플릿 |
|--------|-----------|-----------|------|--------|
| 기능 스펙 | `specify` · `defer` 스킬 | `{{스펙 저장소}}/{unit}/{kebab-case}.md` | 참조 | 골격은 [`spec-template.md`](../../.claude/skills/specify/references/spec-template.md) (참조 유형의 작업 산출물 판) |
| 아키텍처 감사 | `safe-refactor` 스킬 (Audit 단계) | `{{감사 로그}}/{unit}/{NNN}-{kebab-topic}.md` (작업 단위 안에서 001부터 증가) | 문제 해결 | 골격은 [`audit-template.md`](../../.claude/skills/safe-refactor/references/audit-template.md) (문제 해결 유형의 작업 산출물 판) |
| 리팩터 반영 이력 | `safe-refactor` 스킬 (G4 Report) | `{{감사 로그}}/{unit}/refactor-log.md` | 참조 | [`reference-doc.md`](reference-doc.md) |
| 하네스 회고 백로그 | `retro` 스킬 | `{{문서 루트}}/audits/harness-retro.md` | 참조 | [`reference-doc.md`](reference-doc.md) |
| 아키텍처 결정 (ADR) | 사용자 승인 후 수동 작성 | `{{결정 기록}}/{번호}-{kebab-case}.md` | 설명 | [`explanation-doc.md`](explanation-doc.md) "작업 산출물로 쓸 때" |
| 하네스 슬롯 값 | `adopt` 스킬 | `.claude/rules/harness-map.md` | 참조 | 파일 자체가 골격 |
| 작업 보고서 (`report.md`) | G4 — Must Have급 작업 끝에 | `{{문서 루트}}/reports/{YYYY-MM-DD}-{kebab-topic}.md` | 참조 | [`reference-doc.md`](reference-doc.md) "작업 보고서" |
| 안 하기로 한 것 | 검토 후 기각 결정이 날 때 (G4·`retro`) | `{{문서 루트}}/out-of-scope/README.md` — 이 저장소 이력, 배달 안 함 | 참조 | [`reference-doc.md`](reference-doc.md) |
| 하네스 설계 배경 | 사용자 승인 후 수동 작성 | `{{문서 루트}}/harness/` · `harness-engineering.md` | 설명 | [`explanation-doc.md`](explanation-doc.md) |
| 하네스 구성 요소 지도 | 구성 요소를 추가·삭제·개명할 때 같은 턴에 갱신 | `{{문서 루트}}/harness/component-map.md` — 이 저장소 이력, 배달 안 함 | 참조 | [`reference-doc.md`](reference-doc.md) |
| 폴더 인덱스 | 사용자 승인 후 수동 작성 | `{{문서 루트}}/README.md` · 하위 `README.md` | 참조 | [`reference-doc.md`](reference-doc.md) |
| 참조 자료 (차용 출처) | 외부 저장소·문서를 참고해 하네스를 바꿀 때 | `{{문서 루트}}/references.md` — 이 저장소 이력, 배달 안 함 | 참조 | [`reference-doc.md`](reference-doc.md) |
| 온보딩·개념 입문 | 사용자 승인 후 수동 작성 | `{{문서 루트}}/` — 이 저장소: `workflow-cycle.md` | 학습 | [`learning-doc.md`](learning-doc.md) |
| *프로젝트 문서 — `adopt`이 채운다* | | | | |
| 제품 범위 | 사용자 승인 후 수동 작성 | `{{제품 범위}}` — 이 저장소: `AGENTS.md` | 참조 | [`reference-doc.md`](reference-doc.md) |
| 용어집 | 사용자 승인 후 수동 작성 | `{{용어집}}` — 이 저장소: (없음) | 참조 | [`reference-doc.md`](reference-doc.md) |
| 클라이언트 전제 | 사용자 승인 후 수동 작성 | `{{클라이언트 전제}}` — 이 저장소: (없음) | 설명 | [`explanation-doc.md`](explanation-doc.md) |
| 현재동작 요약 | 보안·아키텍처 변경과 같은 턴 | `{{현재동작 요약}}` — 이 저장소: `docs/harness/README.md` | 설명 | [`explanation-doc.md`](explanation-doc.md) |

**마크다운을 만들지 않는 것들.** 훅은 stderr 메시지만 내보내고 파일을 쓰지 않는다. `preflight`·`debug` 스킬과 `doc-reviewer`·`researcher`·스택 리뷰어 에이전트는 결과를 채팅으로만 보고한다. 이들의 결과를 문서로 남겨야 한다고 판단되면 위 등록부에 행을 추가하는 것이 먼저다 — 임의 경로에 파일을 만들지 않는다.

## 유형별 템플릿

toss의 [테크니컬 라이팅 가이드](https://github.com/toss/technical-writing)가 나눈 네 가지 유형을 그대로 쓴다. 이 저장소가 만드는 산출물은 전부 이 넷 중 하나에 속하며, **유형 밖의 전용 템플릿은 두지 않는다.** 스펙·감사 골격은 그걸 만드는 스킬 옆에 두지만 유형은 각각 참조·문제 해결이다.

| 유형 | 독자의 목적 | 템플릿 |
|------|-------------|--------|
| **학습** | 처음 접해서 전체 흐름을 알고 싶다 | [`learning-doc.md`](learning-doc.md) |
| **문제 해결** | 지금 막힌 것을 풀고 싶다 | [`how-to-doc.md`](how-to-doc.md) |
| **참조** | 값·계약·목록을 정확히 확인하고 싶다 | [`reference-doc.md`](reference-doc.md) |
| **설명** | 왜 이렇게 됐는지 이해하고 싶다 | [`explanation-doc.md`](explanation-doc.md) |

원칙과 구조만 참고하고 **원문 문장은 옮기지 않는다.** toss 가이드는 CC BY-NC-SA 4.0이라 문장을 그대로 복사하면 라이선스가 이 저장소로 전염된다.

## 쓰는 법

1. `doc-writing.md`의 판정 순서로 유형을 정한다.
2. 위 등록부에 이미 있는 산출물이면 해당 템플릿의 **"작업 산출물로 쓸 때"** 절이나 스킬의 골격을 복사한다. 없으면 **"골격"** 절을 복사한다.
3. 대괄호 `[...]` 안내문을 실제 내용으로 바꾼다 — 안내문이 남아 있으면 미완성이다.
4. `scripts/check-doc-style.sh <파일>`로 구조·문장 검사를 통과한다 (pre-commit도 같은 검사를 한다).
5. 새 문서이므로 **G3 문서 품질 게이트** 대상이다 — `doc-reviewer`로 확인한다.

## 관련 문서

- [`.claude/rules/doc-writing.md`](../../.claude/rules/doc-writing.md) — 유형 판정·정보 구조·문장 기준
- [`.claude/rules/harness-map.md`](../../.claude/rules/harness-map.md) — `{{문서 루트}}` 등 경로 슬롯
- [`.claude/agents/doc-reviewer.md`](../../.claude/agents/doc-reviewer.md) — 문서 품질 리뷰 기준
