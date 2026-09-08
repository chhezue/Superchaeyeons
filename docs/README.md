# Docs — 문서 SSOT

이 저장소는 **하네스 템플릿**이다. 아래 폴더는 새 프로젝트에 붙일 때 채우는 골격이다.

| 폴더 | 용도 | 하네스 슬롯 |
|------|------|-------------|
| [`workflow-cycle.md`](workflow-cycle.md) | **작업 한 사이클 따라가기** — 트랙 판정부터 커밋 분할안까지 10단계. 각 단계의 이유와 "이러면 성공" 기준 | 이 저장소 이력 — 배달하지 않음 |
| [`harness/`](harness/README.md) | **하네스 자체 설명** — 4개 레이어 구조·설계 근거. [`component-map.md`](harness/component-map.md)는 구성 요소별 실행 시점·질문·검사·수정 로드맵 | 이 저장소 이력 — **배달하지 않음** (링크만) |
| [`out-of-scope/`](out-of-scope/README.md) | 검토 후 안 하기로 한 장치와 이유 | 이 저장소 이력 — 배달하지 않음 |
| `reports/` | Must Have급 작업 보고서 (`report.md`) — 검증하지 못한 것 포함 | `{{문서 루트}}/reports/` |
| [`templates/`](templates/README.md) | **산출물 등록부** + 유형별(학습·문제 해결·참조·설명) 템플릿 | `{{문서 루트}}/templates/` (함께 배달됨) |
| [`specs/`](specs/README.md) | 기능 설계 | `{{스펙 저장소}}` |
| [`decisions/`](decisions/README.md) | 아키텍처 결정 기록 | `{{결정 기록}}` |
| [`audits/`](audits/README.md) | 감사·리팩터·하네스 회고 | `{{감사 로그}}` |
| [`product/`](product/README.md) | 기획·범위·용어 | `{{제품 범위}}` 외 3개 |
| [`harness-engineering.md`](harness-engineering.md) | 하네스를 왜 이렇게 만들었는지 (긴 글) | 이 저장소 이력 — 배달하지 않음 |
| [`references.md`](references.md) | 참조한 저장소·문서와 거기서 차용한 것·자른 것 | 이 저장소 이력 — 배달하지 않음 |

## 여기 없는 슬롯

`{{아키텍처 개요}}`·`{{스키마 SSOT}}`·`{{API 응답 규격}}`·`{{API 문서}}`·`{{현재동작 요약}}`·`{{배포 SSOT}}`는 프로젝트마다 위치가 갈려서 골격을 만들지 않았다. 파일을 만든 뒤 [`.claude/rules/harness-map.md`](../.claude/rules/harness-map.md)에 경로를 적는다.

## 시작하기

1. `adopt` 스킬을 돌린다 — 저장소를 실측해 [`harness-map.md`](../.claude/rules/harness-map.md)의 축 4개·슬롯 22개·능력 플래그 8개를 제안하고, 승인 후 채운다. 스택 씨앗 복사(`local-*` 이름 유지)와 `AGENTS.md` 채움도 이 단계에서 한다
2. 새 문서를 만들 때는 [`templates/README.md`](templates/README.md) 산출물 등록부에서 유형과 저장 경로를 먼저 찾는다
3. `./scripts/install-git-hooks.sh` — 커밋 메시지·pre-commit(부품 계약·문서 스타일 검사) 훅 설치
