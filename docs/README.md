# Docs — 문서 SSOT

이 저장소는 **하네스 템플릿**이다. 아래 폴더는 새 프로젝트에 붙일 때 채우는 골격이다.

| 폴더 | 용도 | 하네스 슬롯 |
|------|------|-------------|
| [`harness/`](harness/README.md) | **하네스 자체 설명** — 4개 레이어 구조·설계 근거 | (고정 — 함께 배달됨) |
| [`templates/`](templates/README.md) | 문서 유형별 작성 템플릿 | (고정 — 함께 배달됨) |
| [`specs/`](specs/README.md) | 기능 설계 | `{{스펙 저장소}}` |
| [`decisions/`](decisions/README.md) | 아키텍처 결정 기록 | `{{결정 기록}}` |
| [`audits/`](audits/README.md) | 감사·리팩터·하네스 회고 | `{{감사 로그}}` |
| [`product/`](product/README.md) | 기획·범위·용어 | `{{제품 범위}}` 외 3개 |
| [`harness-engineering.md`](harness-engineering.md) | 하네스를 왜 이렇게 만들었는지 (긴 글) | (고정) |

## 여기 없는 슬롯

`{{아키텍처 개요}}`·`{{스키마 SSOT}}`·`{{API 응답 규격}}`·`{{API 문서}}`·`{{현재동작 요약}}`·`{{배포 SSOT}}`는 프로젝트마다 위치가 갈려서 골격을 만들지 않았다. 파일을 만든 뒤 [`.claude/rules/harness-map.md`](../.claude/rules/harness-map.md)에 경로를 적는다.

## 시작하기

1. [`.claude/rules/harness-map.md`](../.claude/rules/harness-map.md) — 슬롯 17개·스택 옵션 7개를 채운다
2. [`AGENTS.template.md`](../AGENTS.template.md) → `AGENTS.md`로 복사해 프로젝트 정보를 채운다
3. 쓰지 않는 스택 팩은 파일째 지운다 (`harness-map.md` 스택 팩 표)
4. `./scripts/install-git-hooks.sh` — 커밋 메시지·pre-commit 훅 설치
