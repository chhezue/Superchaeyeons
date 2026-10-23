# 이슈 트래커 중립화

> 상태: Approved (2026-10-28 사용자 승인)
> MVP: In scope
> 관련 BR: N/A

하네스가 이슈를 읽고 생성하고 연결하는 동작을 GitHub Issues에 종속시키지 않고, 프로젝트별 트래커(Jira, Notion, Redmine, Linear, GitLab 등)를 그대로 활용할 수 있게 하는 스펙이다. core 규칙에서 트래커 전용 표기를 제거하고, 트래커 관련 정보는 프로젝트 층의 트래커 안내 스킬 하나에 모은다.

## 목표

어느 트래커를 사용하는 프로젝트에 하네스를 연동해도, 에이전트가 해당 트래커 방식으로 이슈를 확인·생성하고 커밋·브랜치에 연결하며, 이슈 글도 동일한 흐름으로 다듬는다.

## 이 스펙의 용어

| 용어 | 뜻 |
|---|---|
| 트래커 | 이슈를 관리하는 서비스. GitHub Issues, Jira, Notion 데이터베이스, Redmine 등 |
| 다루는 수단 | 에이전트가 트래커에 접근하는 수단. CLI(`gh`·`glab`·`acli` 등) 또는 MCP(Model Context Protocol) 서버 |
| 이슈 키 | 이슈를 가리키는 표기. `#12`, `PROJ-123` 등 |
| 트래커 안내 | 해당 프로젝트의 트래커 사용법을 작성한 프로젝트 층 스킬 `local-track-issues` |

## 배경

- 하네스의 core 규칙은 이미 트래커를 `{{이슈 연결}}` 슬롯으로 지칭한다. 그러나 단일 값("GitHub Issues · `Closes #n`")에 트래커 종류와 연결 표기가 혼재되어 있으며, `core-workflow.md`와 `write-spec`에는 `#n` 형태의 GitHub식 표기가 남아 있다.
- [Gemini 글 다듬기](gemini-text-polish.md)는 이슈·PR 글을 만들기 전에 다듬는다. 어떤 수단으로 만드는지는 트래커마다 달라서 트래커 안내에 포함한다.

### 조사로 확인한 것 (2026-10-28)

열 순서는 확인한 사실, 이 스펙에 미치는 영향, 근거다.

| 사실 | 이 스펙에 주는 영향 | 근거 |
|---|---|---|
| GitHub·GitLab·Jira는 공식 CLI와 공식 MCP가 모두 있다. Notion·Linear는 공식 호스팅 MCP만 존재한다. Redmine은 공식 수단이 없으며 커뮤니티 MCP가 7개 이상 존재하고 서버마다 도구명이 다르다 | 처리 수단은 프로젝트에서 선택하며, core는 특정 수단을 전제하지 않는다 | [github-mcp-server](https://github.com/github/github-mcp-server) · [GitLab MCP 도구](https://docs.gitlab.com/user/model_context_protocol/mcp_server_tools/) · [Atlassian Rovo MCP](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/) · [Notion MCP](https://developers.notion.com/guides/mcp/mcp-supported-tools) · [Linear MCP](https://linear.app/docs/mcp) |
| MCP 도구 이름이 버전마다 변경된다. GitLab은 19.4에서 `create_issue`를 `save_work_item`으로 대체했다 | 도구 이름을 core나 배포 대상에 고정하지 않는다 | GitLab MCP 도구 문서 |
| 훅은 `mcp__<서버>__<도구>` 형태의 이름으로 MCP 호출도 가로챌 수 있다 | MCP 트래커 글을 훅으로 다듬는 방식의 확장 가능성은 열려 있다(이번 범위 제외) | [Hooks reference](https://code.claude.com/docs/en/hooks) |
| 트래커 차이를 추상화한 하네스 공개 사례는 확인되지 않았다. CCPM(Claude Code 프로젝트 관리 도구)은 GitHub 전용이며, Anthropic 플러그인은 MCP 설정 파일을 교체하는 방식을 사용한다 | 직접 설계한다 | [CCPM](https://github.com/automazeio/ccpm) · [knowledge-work-plugins](https://github.com/anthropics/knowledge-work-plugins) |
| 이 저장소는 "검증되지 않은 스택의 씨앗을 미리 작성하지 않는다"라는 기각 기록이 있다 | 트래커 씨앗도 검증된 GitHub 하나와 기본 골격만 유지한다 | [`out-of-scope/README.md`](../../out-of-scope/README.md) |
| always-load 규칙 용량이 24,951B로 상한선인 25,000B까지 49B 남았다. 상한선은 축소만 가능한 래칫 구조다 | 슬롯은 단일 항목을 유지하고 값을 간결하게 작성한다. 증가 바이트는 약 22B다 | `scripts/check-portability.sh` 실측 |

## 요구사항

### Must Have

**슬롯과 core 표기**

- [ ] `{{이슈 연결}}` 슬롯 항목을 유지한다. 값에는 트래커 이름과 트래커 안내만 명시한다. 이 저장소의 값은 "GitHub Issues · 안내 `local-track-issues`"다. 처리 수단·이슈 키 형식·연결 표기는 트래커 안내에만 작성한다
- [ ] core 규칙 및 스킬의 GitHub식 표기(`#n`)를 "이슈 키"로 변경한다 — `core-workflow.md` 진입 1번, `write-spec` "범위를 미룰 때" 2·5번, 기타 실측으로 확인된 위치
- [ ] 이슈를 처리하는 core 단계(`core-workflow.md` 진입 1번, `write-spec` "범위를 미룰 때" 4번, `verify-work` 2·4단계)에서는 "`{{이슈 연결}}`이 가리키는 안내를 따른다"로 기재한다 — Claude가 트래커 안내 스킬을 누락할 때를 대비한 보완책

**트래커 안내 스킬**

- [ ] 트래커 안내는 프로젝트 층 스킬 `.claude/skills/local-track-issues/SKILL.md`다. 설명은 "이슈를 확인하거나 만들거나 댓글을 달거나 커밋·브랜치에 연결할 때"이며, 본문은 해당 시점에 불러온다
- [ ] 본문 구성 항목: 처리 수단(CLI 명령 또는 MCP 서버·도구 이름), 이슈 키 형식 및 브랜치·커밋 연결 표기, 이슈 조회·완료 기준 확인 방법, 이슈 생성·댓글 작성, 라벨 미부여 원칙(`core-guardrails.md` §1.8)
- [ ] 이슈 글 다듬기: 이슈·PR 글은 수단(CLI·MCP)과 상관없이 생성 전에 `scripts/polish-with-gemini.sh message`로 다듬고 원문과 대조·검수한 뒤 만든다. "Gemini 다듬기" 플래그가 ❌이거나 실패하면 원문으로 진행한다

**씨앗과 붙이기**

- [ ] 씨앗은 GitHub 트래커 안내 하나(`examples/seeds/tracker-github/`)와 골격(`examples/seeds/_template/`의 트래커 안내 골격)만 둔다. 골격은 위 본문 항목으로 구성한다
- [ ] `examples/seeds/README.md`에 트래커 씨앗 표를 더한다. 올리는 조건은 lang 씨앗과 같다(실제 프로젝트에서 한 사이클 이상)
- [ ] `init-harness`가 트래커를 실측한다: 커밋 이력의 이슈 키, 연결된 MCP 서버, 설치된 CLI. GitHub면 씨앗을 복사하고, 아니면 골격을 실측값으로 채운다. `{{이슈 연결}}` 값을 같은 실측으로 채운다
- [ ] 이 저장소에 GitHub 씨앗을 `.claude/skills/local-track-issues/`로 복사한다. 동작은 지금과 같다

**목록**

- [ ] `.claude/rules/README.md` 목록에 프로젝트 층 트래커 안내 스킬을 추가한다.

### Nice to Have

- [ ] 두 번째 트래커를 실제 프로젝트에 적용해 운용한 후, 해당 트래커 안내를 씨앗으로 추가하기

### Out of Scope (이번 스펙에서 하지 않음)

- 훅으로 MCP 트래커 호출을 가로채 다듬는 기능 — 도구 이름 변경이 빈번해 대응표가 쉽게 구식이 된다. 실제 사용하는 트래커가 확정된 후 별도로 다룬다
- 검증되지 않은 트래커 씨앗(Jira·Notion·Linear·GitLab·Redmine) — 기각 기록 원칙을 준수한다
- 트래커 간 이슈 이전, 라벨·우선순위 체계 통일

## 테스트 먼저 지점

Must 항목별로 실패하는 테스트를 먼저 작성할지 제안한다. G2 단계에서 사람이 결정한다.

| Must 항목 | 테스트 먼저 | 근거 |
|---|---|---|
| core 표기를 "이슈 키"로 | 아님 | 문서 변경 항목이다. 기존 이식성 검사(C1)와 always-load 예산 검사로 확인한다 |
| 트래커 안내 스킬과 씨앗 | 아님 | 문서 항목이다. 문서 형식 검사와 이식성 검사(`local-` 접두사 프로젝트 층)로 확인한다 |
| 이슈 글 다듬기 단계 | 아님 | 스킬 본문 절차다. 다듬기 스크립트 자체에는 이미 테스트 케이스가 존재한다 |
| `init-harness` 실측 | 아님 | 스킬 절차다. 실측 결과는 사람이 G2 단계에서 승인한다 |

통제 영역(`core-gates.md` §1)에 해당하는 코드 변경이 없어 테스트 먼저 적용 대상은 없다.

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 기존 훅 테스트 케이스와 검사기가 모두 통과한다 | `scripts/dev.sh test` |
| always-load 예산을 초과하지 않는다 | `scripts/check-portability.sh` |
| core 규칙·스킬에 트래커 고유 이름이나 문법이 없다 | `scripts/check-portability.sh` C1 |
| 이 저장소의 이슈 확인·연결·메시지 다듬기 동작이 기존과 같다 | 트래커 안내 본문 대조 |

## API / 인터페이스

API 없음 — 외부 클라이언트와의 계약이 없다. 변경되는 구성 요소는 다음과 같다.

| 구성 | 변경 사항 |
|---|---|
| `.claude/rules/harness-map.md` | `{{이슈 연결}}` 값 변경 |
| `.claude/rules/core-workflow.md` | 진입 1번 표기 수정 |
| `.claude/skills/write-spec/SKILL.md` · `verify-work/SKILL.md` · `init-harness/SKILL.md` | 이슈 키 표기, 안내 적용, 트래커 실측 |
| `examples/seeds/tracker-github/` · `examples/seeds/_template/` | 트래커 안내 씨앗 및 골격 추가 (신규) |
| `.claude/skills/local-track-issues/SKILL.md` | 이 저장소의 트래커 안내 (신규, 씨앗 복사) |
| `examples/seeds/README.md` · `.claude/rules/README.md` · `gemini-text-polish.md` | 목록 및 설명 업데이트 |

## 토큰 비용

| 층 | 늘거나 주는 것 | 크기 |
|---|---|---|
| 항상 실리는 규칙 | `{{이슈 연결}}` 값 +16B, `core-workflow.md` 진입 1번 +6B | 약 +22B (여유 49B 안) |
| 항상 실리는 설명 | 트래커 안내 스킬 설명 한두 줄 | 약 200B (프로젝트 층, 예산 검사 밖) |
| 호출될 때 실리는 글 | 트래커 안내 본문 · 스킬 본문의 한 줄씩 | 약 1~2KB, 이슈 일을 할 때만 |

## 완료 기준

- [ ] `scripts/dev.sh test` 통과
- [ ] `grep` 검사 시 core 규칙·스킬에 `#n` 표기가 남아 있지 않음
- [ ] 이 저장소의 스킬 목록에 트래커 안내 스킬이 표시됨
- [ ] `init-harness` 체크리스트에 트래커 실측 항목 추가

## 리스크·미결정

| 항목 | 상태 | 비고 |
|---|---|---|
| 1. 트래커 씨앗을 무엇까지 주나 | 확정 (2026-10-28 사용자) | 검증된 GitHub 씨앗과 골격만 둔다. 다른 트래커는 `init-harness`가 실측으로 골격을 채우고, 그 프로젝트에서 한 사이클 굴린 뒤 씨앗으로 올린다. 기각 기록 "검증되지 않은 씨앗 금지"를 그대로 따른다 |
| 2. 슬롯 모양 — 둘로 나누나, 한 칸에 담나 | 확정 (2026-10-28 사용자) | `{{이슈 연결}}` 한 칸을 유지하고 값이 트래커 안내를 가리킨다. 수단·이슈 키·연결 표기는 트래커 안내 한 곳에만 둔다. 행이 늘지 않아 always-load 상한 안이다 |
| 3. 트래커 안내의 위치와 실리는 시점 | 확정 (2026-10-28 사용자) | 프로젝트 층 스킬(`.claude/skills/local-track-issues/`). 설명만 항상 실리고 본문은 이슈 작업을 할 때 읽는다. Claude가 부르지 않을 수 있어, 이슈를 다루는 스킬 단계에 "`{{이슈 연결}}`이 가리키는 안내를 따른다"를 둔다 |
| 4. MCP 트래커의 이슈 글 다듬기 | 확정 (2026-10-28 사용자) | 트래커 안내 스킬에서 생성 전에 다듬기를 직접 부른다. 훅이 아니라 강제력은 없다 |
| 5. 스킬을 Claude가 고르지 않을 때 | 감수 | core 단계의 "안내를 따른다" 한 줄로 보완한다. 그래도 빠지면 이슈 글이 다듬어지지 않거나 연결 표기가 틀릴 수 있다 — 커밋 메시지는 커밋을 묻을 때 보이는 목록에서 다시 보인다 |

## 변경 이력

| 날짜 | 변경 사항 |
|------|------|
| 2026-10-28 | 초안 작성. 조사 결과 및 [미정] 4개 항목 |
| 2026-10-28 | 리스크 1~4 확정 — 씨앗은 GitHub 및 골격만 유지, 슬롯은 단일 항목 유지, 트래커 안내는 프로젝트 층 스킬로 구현, MCP 트래커 본문은 안내 스킬에서 다듬기 호출 |
| 2026-10-28 | 다듬기 단순화에 맞춤 — 메시지 훅과 `TRACKER_COMMANDS`가 없어져서, 이슈 글은 수단과 상관없이 트래커 안내가 만들기 전에 다듬기를 부른다 |
