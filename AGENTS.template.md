# {프로젝트 이름}

{한 줄 설명}. AI 에이전트가 작업할 때 참고하는 프로젝트 지도입니다.

> **이 파일은 템플릿입니다.** `AGENTS.md`로 복사한 뒤 `{...}` 자리를 채우고 이 인용문을 지우세요.
> 함께 채울 것: [`.claude/rules/harness-map.md`](.claude/rules/harness-map.md) (축·슬롯·능력 플래그 — "하네스 자기 수정"은 ❌가 기본).
> 이 파일에는 **이 프로젝트에만 있는 사실**만 적는다. 작업 순서·멈추는 조건·커밋 규율은 `.claude/rules/`가 이미 매 세션 싣기 때문에 여기 다시 적으면 같은 내용이 두 번 실린다.

## How We Build

**계획 축**은 `{{우선순위 SSOT}}`, **기획**은 `{{제품 범위}}`, **기능 설계**는 `{{스펙 저장소}}`, **아키텍처 선택**은 `{{결정 기록}}`에 둡니다. 작업 순서는 `.claude/rules/core-workflow.md`, 멈추는 조건은 `core-guardrails.md`·`core-gates.md`가 정합니다.

## Tech Stack

- {언어·버전}
- {프레임워크·버전}
- {빌드 도구}
- {DB — 런타임·테스트}
- {테스트 프레임워크}
- {배포}

## Conventions

- 패키지: `{루트 패키지}` — {레이어 구조 한 줄}
- DB/API 네이밍은 `{{아키텍처 개요}}` 기준
- 주석·테스트 표기: {lang 팩 파일 — 예: `.claude/rules/local-{스택}.md`}
- **DB:** {마이그레이션 정책 — `harness-map.md`의 "DB 마이그레이션 금지" 플래그와 일치시킬 것}
- 비밀값(`.env`, API 키)은 코드·커밋에 포함하지 않음
- {그 밖에 이 프로젝트에서만 지키는 규칙 — 없으면 이 줄을 지운다}

## Important Paths

| 경로 | 용도 |
|------|------|
| `{소스 루트}` | 애플리케이션·도메인 코드 |
| `{설정 루트}` | 환경별 설정 |
| `{테스트 루트}` | 단위·통합 테스트 |
| [`.claude/rules/harness-map.md`](.claude/rules/harness-map.md) | **슬롯 SSOT** — 규칙이 부르는 역할 → 실제 경로 |
| `{{문서 루트}}/README.md` | **문서 SSOT** |
| [`.claude/rules/README.md`](.claude/rules/README.md) | 규칙·스킬·에이전트·훅 목록 |
| `{{Git 컨벤션 SSOT}}` | **Git SSOT** — 브랜치·커밋·PR (없으면 `core-workflow.md` G2·G4) |

## Product Context

- **클라이언트**: {누가 무엇으로 붙는지} — `{{클라이언트 전제}}`
- 용어는 `{{용어집}}`, DB 설계는 `{{스키마 SSOT}}` 기준

## Commands

```bash
{최초 셋업}
./scripts/install-git-hooks.sh   # 최초 1회 — pre-commit·commit-msg 훅 설치
{로컬 실행}
{{테스트 명령}}
{{빌드 명령}}
```
