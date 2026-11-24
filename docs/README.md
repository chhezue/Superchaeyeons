# Docs — 문서 SSOT

이 저장소는 **하네스 템플릿**이다. 설치와 업데이트는 [루트 README](../README.md), 도구별 실행 방식은 [현재 동작](harness/README.md), 검수 당시의 결과와 한계는 [Claude·Codex 연결 검수 보고서](reports/2026-11-10-dual-harness-runtime.md)에서 확인한다. 아래 표는 이 저장소의 문서와 프로젝트별 저장 위치를 연결한다.

| 폴더 | 용도 | 하네스 슬롯 |
|------|------|-------------|
| [`harness/`](harness/README.md) | **하네스 자체 설명** — 4개 레이어와 지금의 실제 동작(`{{현재동작 요약}}`). 구성 요소 목록은 `.claude/rules/README.md` | 이 저장소 이력 — **배달하지 않음** (링크만) |
| [`out-of-scope/`](out-of-scope/README.md) | 검토 후 안 하기로 한 장치와 이유 | 이 저장소 이력 — 배달하지 않음 |
| `reports/` | L 규모 작업에 기존 스펙·감사 기록이 없을 때 쓰는 보고서 (`report.md`) — 검증하지 못한 것 포함 | `{{문서 루트}}/reports/` |
| [`templates/`](templates/README.md) | **산출물 등록부** + 유형별(학습·문제 해결·참조·설명) 템플릿 | `{{문서 루트}}/templates/` (필요 시 수동 복사) |
| [`specs/`](specs/README.md) | 기능 설계 | `{{스펙 저장소}}` |
| [`decisions/`](decisions/README.md) | 아키텍처 결정 기록 | `{{결정 기록}}` |
| [`audits/`](audits/README.md) | 감사·리팩터·하네스 회고 | `{{감사 로그}}` |
| [`product/`](product/README.md) | 기획·범위·용어 | `{{제품 범위}}` 외 3개 |
| [`harness-engineering.md`](harness-engineering.md) | 하네스를 왜 이렇게 만들었는지 (긴 글) | 이 저장소 이력 — 배달하지 않음 |
| [`references.md`](references.md) | 참조한 저장소·문서와 거기서 차용한 것·자른 것 | 이 저장소 이력 — 배달하지 않음 |

## 프로젝트별 문서 경로

이 저장소의 `{{아키텍처 개요}}`와 `{{현재동작 요약}}`은 모두 [하네스 동작 문서](harness/README.md)를 가리킨다. `{{스키마 SSOT}}`·`{{API 응답 규격}}`·`{{API 문서}}`·`{{배포 SSOT}}`는 프로젝트마다 위치가 갈려서 골격을 만들지 않았다. 파일을 만든 뒤 [`.claude/harness.conf`](../.claude/harness.conf)에 경로를 적는다.

## 시작하기

1. `init-harness` 스킬을 돌린다 — 저장소를 실측해 [`.claude/harness.conf`](../.claude/harness.conf)의 축·슬롯·능력 플래그를 제안하고, 승인 후 채운다. 트래커 안내·`dev.conf` 채움과 `AGENTS.md` 채움도 이 단계에서 한다
2. 새 문서를 만들 때는 [`templates/README.md`](templates/README.md) 산출물 등록부에서 유형과 저장 경로를 먼저 찾는다
