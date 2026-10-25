# 하네스 플러그인 배달

> 상태: Draft (2026-10-27 초안)
> MVP: In scope
> 관련 BR: N/A

## 목표

하네스를 Claude Code 플러그인으로 배달해서, 이 저장소를 고치면 하네스를 붙인 모든 프로젝트가 복사 없이 자동으로 업데이트를 받게 한다. 프로젝트마다 다른 값(경로·명령·언어·정책)은 프로젝트의 설정 파일에만 두고, 처음 붙일 때 `harness-init`이 저장소를 확인해 채우며 모자라면 사용자에게 묻는다. core 규칙 중 기계가 판정할 수 있는 행동(커밋·삭제·의존성 추가·민감한 경로 수정)은 훅이 사용자 승인 창으로 강제하고, 규칙에는 판단만 남긴다.

## 배경

- **지금 배달 방식은 복사다.** 새 프로젝트에 `.claude/`·`scripts/`를 복사하고 `harness-init`으로 값을 채운다. 이 저장소를 고쳐도 이미 붙인 프로젝트에는 전파되지 않아서, 프로젝트마다 다시 복사하고 차이를 맞춰야 한다
- **이 문제는 [미정]으로 남아 있었다.** [`harness-slot-system-v2.md`](harness-slot-system-v2.md) 리스크·미결정 표의 "하네스 배달 방식 — 복사 vs 별도 저장소"가 "플러그인이 `rules/`를 배달할 수 있는지 미확인"으로 멈춰 있다. 이 스펙이 그 질문에 답하고 결정을 제안한다

### 공식 문서로 확인한 것 (2026-10-27)

| 사실 | 이 스펙에 주는 영향 | 근거 |
|---|---|---|
| 플러그인은 스킬·명령어·에이전트·훅·MCP(Model Context Protocol) 서버·출력 스타일·`bin/` 실행 파일을 담는다. `rules/`는 구성 요소가 아니고, 플러그인 루트의 `CLAUDE.md`는 맥락에 싣지 않는다 | core 규칙은 플러그인 파일로 실어 보낼 수 없다 | [Plugin manifest reference](https://code.claude.com/docs/en/plugins-reference) "Standard layout" |
| 플러그인 `settings.json`은 `agent`·`subagentStatusLine`만 적용한다 | `permissions.deny`는 플러그인으로 배달되지 않는다. 프로젝트 `settings.json`에 남는다 | 같은 문서 "settings" |
| 훅 명령은 `${CLAUDE_PLUGIN_ROOT}`(설치된 버전 경로)로 플러그인 파일을 부른다. 이 경로는 버전마다 바뀐다 | 훅 경로는 문제없다. 버전마다 바뀌는 경로를 git 훅이 따라갈 수는 없다 | 같은 문서 "Environment variables" |
| `bin/`의 파일은 플러그인이 켜져 있는 동안 Bash 도구의 `PATH`에 들어간다. `bin/`이 있으면 claude.ai·Cowork는 플러그인을 설치하지 않는다 | `dev.sh` 같은 명령을 경로 없이 부를 수 있다. 대신 터미널 전용이 된다 | 같은 문서 "Standard layout" |
| `plugin.json`에 `version`을 적지 않으면 커밋 SHA(커밋마다 붙는 고유 해시)가 버전이 된다. 직접 만든 마켓플레이스는 자동 업데이트가 기본으로 꺼져 있고, 설정의 `extraKnownMarketplaces` 항목에 `autoUpdate`를 적어 켤 수 있다 | `main`에 커밋할 때마다 새 버전이 된다. 프로젝트 설정에서 자동 업데이트를 켠다 | [Plugin loading reference](https://code.claude.com/docs/en/plugins/loading.md) "Versions and updates" |
| 마켓플레이스 저장소 안의 상대 경로 플러그인은 프로젝트 `.claude/settings.json`에서 켜기만 해도 받아진다. 로컬 경로로 추가한 마켓플레이스의 상대 경로 플러그인은 복사 없이 제자리에서 로드된다 | 붙이는 프로젝트는 설정 파일만 커밋하면 된다. 이 저장소는 자기 플러그인을 고치는 즉시 써 볼 수 있다 | 같은 문서 "Enabled in project settings but not installed" · "In-place and copied plugins" |
| 클라우드 세션은 저장소의 `extraKnownMarketplaces`를 추가하지 않는다 | 클라우드 세션에서는 하네스가 실리지 않는다 | 같은 문서 "Plugins shared through a repository" |
| `SessionStart` 훅의 출력은 첫 질문 전에 Claude만 보는 맥락으로 들어간다. 시작·`/clear`·요약 뒤에 다시 돈다. 훅 하나의 출력은 1만 자가 상한이고, 넘으면 앞 2,000자만 남는다 | 규칙을 훅으로 넣을 수 있다. 넣는 글은 훅 하나당 1만 자 안이어야 한다 | [Hooks reference](https://code.claude.com/docs/en/hooks.md) "SessionStart" |
| `SessionStart` 훅이 실패해도 세션은 그대로 진행된다. 사용자에게 오류가 보이는 것은 종료 코드 2일 때뿐이다. `systemMessage` 필드는 사용자에게 경고를 보여 준다 | 아무 장치가 없으면 규칙이 조용히 빠진다. 경고는 스크립트가 직접 내야 한다 | 같은 문서 "Exit code" · "JSON output" |
| `PreToolUse` 훅이 `permissionDecision: "ask"`를 내면 사용자 화면에 승인 창이 뜨고, 훅이 적은 이유가 창에 보인다. 플러그인 훅이면 창에 `[plugin:<이름>]`이 붙는다. 자동 모드에서도 창이 뜬다. 여러 훅의 판정은 `deny` > `ask` > `allow` 순으로 이긴다 | 에이전트가 흉내 낼 수 없는 승인 통로가 생긴다. 행동 규칙을 훅으로 옮길 수 있다 | 같은 문서 "PreToolUse decision control" |
| 스킬 머리에 `paths`(glob 목록)를 적으면 그 패턴에 맞는 파일로 작업할 때 Claude가 스킬을 자동으로 싣는다. 플러그인 스킬도 같은 필드를 쓴다 | 경로 조건부 규칙을 같은 동작의 스킬로 옮길 수 있다 | [Skills](https://code.claude.com/docs/en/skills.md) "Frontmatter reference" |
| 공식 문서는 "매번 지켜져야 하는 규칙은 스킬이 아니라 훅으로" 넣으라고 권한다. 훅이 부르는 스크립트는 플러그인 안에 두고 `${CLAUDE_PLUGIN_ROOT}`로 부른다. 스킬 본문의 `${CLAUDE_PLUGIN_ROOT}`도 실제 경로로 바뀐다 | 행동 강제는 훅으로, 도구 상자는 플러그인 안에 | [Add components to a plugin](https://code.claude.com/docs/en/plugins/components.md) "Skills" · "Reference plugin paths" |
| 플러그인 스킬은 `/<플러그인>:<스킬>`로 부르고, 다른 명령이 쓰지 않는 이름이면 짧은 `/<스킬>`도 된다. 이름이 같은 플러그인 둘이 켜지면 한쪽의 훅이 빠진다 | 스킬 이름을 `init`으로 바꾸면 짧은 `/init`은 기본 명령이 그대로 갖는다. 플러그인 이름은 남과 겹치지 않아야 한다 | 같은 문서 · [Plugin loading reference](https://code.claude.com/docs/en/plugins/loading.md) "Name conflicts" |
| `SessionStart`는 서브에이전트 안에서 돌지 않는다. `SubagentStart`가 같은 `additionalContext`를 받는다 | 서브에이전트에는 따로 넣어야 한다 | 같은 문서 "SubagentStart" |

### 벤치마킹 — Superpowers

[obra/superpowers](https://github.com/obra/superpowers) `hooks/hooks.json`·`hooks/session-start` (2026-10-27 `main`)를 읽었다.

- `SessionStart`(시작·`/clear`·요약 뒤)에서 스크립트 하나가 안내 스킬 하나(`using-superpowers`)의 본문을 `additionalContext`로 넣는다. 나머지 지침은 전부 스킬에 있다
- 환경 변수 `PATH`가 망가져도 돌도록 `dirname`·`cat` 같은 외부 명령을 피하고 bash 내장 기능만 쓴다
- 안내 파일을 못 읽으면 "읽기 실패" 문장만 Claude에게 넣는다. **사용자에게는 경고가 보이지 않는다**
- 이 저장소가 가져올 것: 짧은 안내문 + 나머지는 스킬 · 내장 기능만 쓰는 스크립트. 보완할 것: 실패를 사용자에게 알리는 경로
- Anthropic 공식 플러그인 `explanatory-output-style`·`learning-output-style`([anthropics/claude-code `plugins/`](https://github.com/anthropics/claude-code/tree/main/plugins))도 `SessionStart` 훅으로 지침을 넣는다
- 커밋 검사는 git 훅 대신 `PreToolUse` 훅이 `git commit`을 가로채 검사를 돌리고 실패하면 막는 방식이 쓰인다([예시 1](https://www.morphllm.com/claude-code-hooks-examples) · [예시 2](https://dev.to/anand_rathnas_d5b608cc3de/how-i-tamed-claude-code-with-pre-tool-hooks-and-you-should-too-53cm)). 플러그인이 git 훅을 설치하는 사례는 찾지 못했다

### 고쳐야 하는 기존 결정

| 기존 기록 | 내용 | 이 스펙의 제안 |
|---|---|---|
| [`harness-slot-system-v2.md`](harness-slot-system-v2.md) "부품성 원칙" 1번 | "플러그인 매니페스트를 요구하는 장치는 채택하지 않는다" | 원칙의 목적(별도 런타임·무거운 장치 금지)은 유지하고, 플러그인 매니페스트는 금지 목록에서 뺀다. 매니페스트는 JSON 파일 하나이고 실행할 런타임이 없다 |
| [`out-of-scope/README.md`](../../out-of-scope/README.md) "`inject-rules.sh`" 행 | 주입이 실패하면 규칙이 조용히 사라진다는 이유로 기각 | 기각 당시에 없던 이유(플러그인은 규칙 파일을 배달할 수 없음)가 생겼다. "조용히"를 Must Have의 실패 경고로 막고 채택으로 바꾼다 |
| `harness-slot-system-v2.md` 리스크·미결정 "하네스 배달 방식" | [미정] | 이 스펙이 승인되면 "결정: 플러그인 + 세션 시작 훅"으로 고치고 이 스펙을 가리킨다 |
| [`core-gates.md`](../../../.claude/rules/core-gates.md) §3 "훅 승인 통로는 설정 변경뿐이다" | 훅은 구두 승인을 모르므로 승인은 사용자가 설정을 바꾸는 것뿐이다 | 승인 창(`ask`)을 두 번째 통로로 더한다. 사용자가 창에서 직접 누르는 것이라 에이전트가 열 수 없다는 원칙은 그대로다. 환경 변수·마커 파일 통로를 금지한 [`out-of-scope/README.md`](../../out-of-scope/README.md) "훅 승인 우회 통로" 행과도 어긋나지 않는다 |

`out-of-scope/README.md`의 "서드파티 워크플로 플러그인" 행은 Superpowers를 **설치해 쓰는 것**을 기각한 기록이다. 이 스펙은 방식만 참고하므로 그 행은 바꾸지 않는다.

## 요구사항

### Must Have

**플러그인 골격**

- [ ] 저장소 루트에 마켓플레이스 파일 `.claude-plugin/marketplace.json`을 두고, 플러그인 하나(`plugin/`, 상대 경로)를 등록한다. 플러그인 이름은 `superchaeyeons`
- [ ] `plugin/.claude-plugin/plugin.json`에 `version`을 적지 않는다 — 커밋 SHA를 버전으로 쓴다
- [ ] 스킬 8개·에이전트 3개·훅 3개를 `plugin/` 아래로 옮긴다. 훅 등록은 `plugin/hooks/hooks.json`이 하고 경로는 `${CLAUDE_PLUGIN_ROOT}`로 쓴다. 스킬 이름은 그대로 둔다(`harness-init` — 짧은 `/harness-init`이 다른 명령과 겹치지 않는다)
- [ ] 도구 상자(`dev.sh`·`verify.sh`·검사기·`harness-init-probe.sh`)를 `plugin/scripts/`로 옮긴다. 스킬·주입 규칙은 `${CLAUDE_PLUGIN_ROOT}/scripts/…`로 부른다. `bin/`은 쓰지 않는다 — claude.ai·Cowork 설치를 막지 않기 위해서다
- [ ] git 훅(`pre-commit`·`commit-msg`)과 `install-git-hooks.sh`를 지운다. 같은 검사는 아래 "행동 강제"의 커밋 훅이 맡는다
- [ ] `claude plugin validate plugin --strict`가 통과한다

**규칙 주입**

- [ ] core 규칙 4개(`core-gates`·`core-guardrails`·`core-workflow`·`core-reporting`) 원문을 `plugin/rules/`로 옮긴다. Claude Code는 이 폴더를 직접 읽지 않는다
- [ ] 아래 "행동 강제" 훅이 맡은 문장(승인 없는 커밋 금지·삭제와 의존성 추가 전 확인 등)은 규칙에서 "훅이 승인 창을 띄운다" 한 줄로 줄인다. 규칙에는 판단만 남긴다
- [ ] `SessionStart`(시작·`/clear`·요약 뒤) 훅이 core 규칙을 `additionalContext`로 넣는다. 지금 네 파일의 합은 8,499자다
- [ ] 같은 이벤트의 **두 번째 훅**이 프로젝트 설정 값(아래 "프로젝트 설정 파일")을 표로 넣는다. 훅 하나당 1만 자 상한을 나눠 쓰기 위해서다
- [ ] `SubagentStart` 훅이 같은 글을 서브에이전트에 넣는다
- [ ] 검사기가 훅마다 넣는 글의 길이를 재서 9,000자를 넘으면 실패한다. 지금 always-load 예산(25,000B)을 이 검사로 바꾼다
- [ ] 경로 조건부 규칙 3개(`core-testing`·`core-code-comments`·`doc-writing`)는 지금 `paths:` 값을 그대로 옮긴 `paths` 스킬로 바꾼다. 수동 검증에서 파일을 열 때 확실히 실리지 않으면 `PostToolUse` 훅이 경로를 보고 넣는 방식으로 바꾼다
- [ ] `.claude/rules/README.md`(하네스 파일을 열 때 싣는 구성 요소 목록)는 이 저장소 전용이라 플러그인에 넣지 않고 이 저장소의 `.claude/rules/`에 남긴다

**실패하면 사용자에게 알린다**

- [ ] 주입 훅은 bash 내장 기능만 쓴다(Superpowers 방식)
- [ ] 규칙 파일을 못 읽거나 중간에 오류가 나면, `trap`으로 잡아 `systemMessage`에 "하네스 규칙을 싣지 못했다 — 이 세션은 가드레일 없이 진행된다"를 담아 출력하고 종료 코드 0으로 끝낸다. 같은 문장을 `additionalContext`에도 넣어 Claude도 알게 한다
- [ ] 위 동작을 `scripts/hook-cases.txt` 케이스로 판정한다 — 정상 · 규칙 파일 없음 · 설정 파일 없음 · 설정 파일 빈칸 남음

**행동 강제 — 승인 창**

승인 창이 자주 뜨면 사람이 내용을 보지 않고 누르게 된다(`core-gates.md` 머리의 "모든 것에서 멈추면 멈춤은 무시된다"). 그래서 창을 띄우는 조건을 좁고 결정적으로 정하고, **띄우지 않아야 하는 경우도 테스트로 판정한다.**

- [ ] `PreToolUse` 훅 `ask-*` 하나가 아래 범주에서만 `ask`를 낸다. 범주마다 설정 파일의 플래그로 켜고 끈다

| 범주 | 창을 띄우는 조건 | 띄우지 않는 경우 |
|---|---|---|
| 커밋·원격 반영 | `git commit` · `git push` · `gh pr create` · `gh pr merge`. `git commit`은 먼저 지금 git 훅이 하던 검사(커밋 메시지 형식 `COMMIT_RE` · `verify.sh`)를 돌려 실패하면 이유와 함께 막고(`deny`), 통과하면 창을 띄운다 | `git status`·`diff`·`log`·`add` 같은 읽기와 스테이징 |
| 삭제 | git이 추적하는 파일을 지우는 `rm`·`git rm`·`mv` 덮어쓰기 | 추적되지 않는 파일(임시 파일·빌드 산출물) · 이미 `deny-dangerous-bash.sh`가 막는 명령 |
| 의존성 추가 | 설정 파일 `DEPS_FILES`에 적힌 파일(예: 빌드 선언 파일) 수정 · `DEPS_ADD_CMD`에 적힌 설치 명령 | 의존성 조회·빌드·테스트 명령 |
| 민감한 경로 | 설정 파일 `ASK_PATHS`(glob 목록)에 맞는 파일 쓰기 | 목록이 비어 있으면 아무것도 묻지 않는다 — 기본값은 빈 목록 |
| 스펙 승인·[미정] 확정 | `{{스펙 저장소}}`·`{{결정 기록}}` 문서를 고칠 때 **상태 줄이 `Approved`로 바뀌거나 `[미정]` 개수가 줄어드는** 편집 | 상태와 `[미정]` 개수가 그대로인 편집(초안 작성·문장 수정) |

- [ ] 창에 보일 이유(`permissionDecisionReason`)는 한 줄로, 사용자가 무엇을 승인하는지 바로 알게 쓴다. 예: "커밋 — 파일 3개 · `Refactor: …`", "삭제 — 추적 중인 `src/a.ts`"
- [ ] 채팅으로 받던 같은 승인을 없앤다. 커밋은 분할안을 보여 준 뒤 바로 실행하고, 승인 창이 승인이다. 스펙도 채팅에서 "승인해 주세요"를 기다리지 않고, 상태 줄을 `Approved`로 고치는 편집을 시도하면 창이 승인이다. 같은 일을 채팅과 창에서 두 번 승인하게 하지 않는다
- [ ] 스펙 승인 창의 이유에는 스펙 경로와 남은 `[미정]` 개수를 적는다. 예: "스펙 승인 — `harness-plugin-delivery.md` · [미정] 0개"
- [ ] `DEPS_FILES`·`DEPS_ADD_CMD`·`ASK_PATHS`는 `harness-init`이 저장소를 확인해 제안한다(빌드 선언 파일 · 인증·결제·마이그레이션 폴더 후보). 승인 전에는 비워 둔다
- [ ] 판정 불가(입력 JSON 깨짐·설정 파일 없음)면 `ask`를 낸다. 막지도 그냥 통과시키지도 않고 사람에게 넘긴다

**프로젝트 설정 파일**

- [ ] 프로젝트 값은 `.claude/harness.conf`(`키=값`, `dev.conf`와 같은 형식)에 둔다. 경로 슬롯·형식 슬롯·능력 플래그·승인 창 범주 플래그·지금 훅 상수(`SCOPE`·`HARNESS_SELF_EDIT`·`TEST_CMD`·`COMMIT_RE`·`FORMAT_CMD`·`FORMAT_PATHS`)가 대상이다. 빌드·실행 명령은 지금처럼 `dev.conf`에 남는다
- [ ] 훅은 상수를 본문에 적지 않고 이 파일을 읽는다. 파일이 없거나 깨졌으면 지금 규약대로 `deny-*`는 차단한다
- [ ] 설정이 채워진 뒤에는 Claude가 `harness.conf`를 고치려 하면 승인 창이 뜬다. 창의 이유에 바뀌는 키와 값을 적는다. 사용자가 누르면 반영되고, 에이전트가 설정을 바꿔 훅을 몰래 푸는 통로는 닫힌다(`core-gates.md` §3)
- [ ] `harness-map.md`는 이 파일로 대체하고 지운다. 사람이 읽는 슬롯 설명은 플러그인 쪽 문서(주입 규칙이 가리키는 스킬 또는 참조 문서)로 옮긴다

**init 자동 시작**

- [ ] 설정 파일이 없거나 빈칸이 남아 있으면, 설정 값 훅이 규칙 대신 "하네스 설정이 비어 있다. 다른 작업 전에 `harness-init`을 제안하라"를 넣는다
- [ ] `harness-init`은 확인으로 정해지지 않는 값만 한 번에 하나씩 묻는다(`ask` 스킬의 라운드 방식). 권장 답을 함께 보인다
- [ ] `harness-init`이 프로젝트 `.claude/settings.json`에 마켓플레이스(`extraKnownMarketplaces`, `autoUpdate: true`)·`enabledPlugins`·`permissions.deny`를 쓴다

**이 저장소 자신**

- [ ] 이 저장소는 자기 마켓플레이스를 로컬 경로로 추가해 `plugin/`을 제자리에서 쓴다. 고친 내용은 `/reload-plugins`나 새 세션부터 반영된다
- [ ] `.claude/`에는 이 저장소 전용 파일(설정 파일·`settings.json`·`local-*.md`)만 남는다

**같은 변경에서 고칠 문서**

- [ ] 위 "고쳐야 하는 기존 결정" 세 곳
- [ ] `{{현재동작 요약}}`(`docs/harness/README.md`) — 규칙이 실리는 방식과 실패 경고를 쉬운 말로 (`core-guardrails.md` §3)
- [ ] `README.md` "빠른 시작" · `AGENTS.md` "무엇이 들어 있나" 표 · `.claude/rules/README.md` 목록 · `docs/harness-engineering.md` "숫자로 보는 현재"

### Nice to Have

- [ ] `dev.conf`와 `harness.conf`를 한 파일로 합치기

### Out of Scope (이번 스펙에서 하지 않음)

- 사람이 터미널에서 직접 하는 커밋 검사 — git 훅을 없애므로 Claude가 하는 커밋만 검사한다(2026-10-27 사용자 결정)
- 질문 창 하나에 질문을 여러 개 넣지 못하게 막는 훅 — `ask` 스킬 지침만 둔다. 지침이 생긴 뒤에도 묶어 묻는 일이 다시 생기면 `retro`로 기록하고 그때 추가한다. 추가하면 이 훅만 "판단 불가 = 통과"로 둬야 한다(막으면 모든 질문 창이 막힌다)
- 클라우드 세션 지원 — 플랫폼이 저장소의 마켓플레이스를 추가하지 않는다
- 공개 디렉터리(Anthropic 플러그인 목록) 등록
- 이미 하네스를 복사해 쓰는 다른 프로젝트의 이전 — 이 스펙이 구현된 뒤 프로젝트마다 `harness-init` 재동기화로 한다

## 테스트 먼저 지점

| Must 항목 | 테스트 먼저 | 근거 |
|---|---|---|
| 실패하면 사용자에게 알린다 | 테스트 먼저 | 기각 사유를 뒤집는 근거가 이 동작이다. `trap`이나 출력 형식이 바뀌면 바로 깨져야 한다 |
| 훅이 설정 파일을 읽고, 없거나 깨지면 차단 | 테스트 먼저 | 판정 불가 = 차단 규약(통제 영역 — 장애 시 동작). 읽기 로직이 바뀌면 깨진다 |
| 설정 파일 쓰기 승인 창 | 테스트 먼저 | 승인 통로를 지키는 장치다(`core-gates.md` §3). 경로 정규화가 바뀌면 깨진다 |
| 커밋 전 검사(메시지 형식·`verify.sh`) | 테스트 먼저 | git 훅을 대체한다. 검사 실패가 막히지 않으면 깨져야 한다 |
| 승인 창 — 띄우는 조건 | 테스트 먼저 | 커밋·삭제·의존성은 통제 영역 변경의 마지막 관문이다. 명령 파싱이 바뀌면 깨져야 한다 |
| 승인 창 — 띄우지 않는 경우 | 테스트 먼저 | 과잉 경보가 이 장치를 무력하게 만든다. 흔한 읽기·스테이징 명령이 창을 띄우기 시작하면 깨져야 한다 |
| init 자동 시작 문구 | 아님 | 문구 출력 한 줄이다. 위 실패 케이스 표에 "설정 파일 없음"으로 함께 판정된다 |
| 주입 글 길이 검사 | 아님 | 검사기 자체가 판정이다 |
| 플러그인 골격·파일 이동·문서 | 아님 | `claude plugin validate`와 `check-portability.sh` 목록 대조가 판정한다 |

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 어느 단계에서도 이 저장소에서 하네스(규칙·훅)가 동작한다 — 옮기는 중에 규칙이 빠진 커밋을 만들지 않는다 | 단계마다 새 세션에서 주입 확인 + `scripts/dev.sh test` |
| `deny-*` 훅의 판정 불가 = 차단 규약 | `scripts/test-hooks.sh` |
| core(플러그인 쪽)에 프로젝트 고유 사실이 없다 | `scripts/check-portability.sh` |
| 훅 승인 통로는 사용자가 설정 파일을 직접 고치는 것과 승인 창에서 누르는 것뿐이다 | 쓰기 잠금 케이스 · 환경 변수·파일로 `ask`를 건너뛰는 경로가 없는지 리뷰 |
| 규칙 주입이 실패해도 커밋·삭제·의존성 추가는 승인 창을 거친다 | 승인 창 케이스는 주입 훅과 독립으로 판정 |

## API / 인터페이스

API 없음. 바뀌는 접점은 아래 셋이다.

| 접점 | 형식 | 읽는 쪽 |
|---|---|---|
| `.claude-plugin/marketplace.json` · `plugin/.claude-plugin/plugin.json` | Claude Code 플러그인 규격 | Claude Code |
| `.claude/harness.conf` | `키=값` — 승인 창 범주 플래그·`DEPS_FILES`·`DEPS_ADD_CMD`·`ASK_PATHS` 포함 | 훅 · 세션 시작 훅 · `harness-init` |
| 프로젝트 `.claude/settings.json` | `extraKnownMarketplaces` · `enabledPlugins` · `permissions.deny` | Claude Code |

옮긴 뒤의 구성(설명용 — 확정은 G2):

```text
Superchaeyeons/
├── .claude-plugin/marketplace.json   마켓플레이스 — plugin/ 하나를 등록
├── plugin/                           배달물 (모든 프로젝트가 같은 파일)
│   ├── .claude-plugin/plugin.json
│   ├── skills/ · agents/             경로 조건부 규칙 3개는 paths 스킬로
│   ├── hooks/                        hooks.json · deny-* 3개 · ask-* 1개 · 주입 훅 2개
│   ├── rules/                        주입할 core 규칙 원문
│   └── scripts/                      dev.sh · verify.sh · 검사기 · harness-init-probe.sh
├── .claude/                          이 저장소 전용 — harness.conf · settings.json · rules/README.md · local-*
└── scripts/ · docs/ · examples/      scripts/에는 이 저장소 전용 도구(test-hooks.sh 등)만 남는다
```

## 검증 시나리오

### 정상

- [ ] 빈 저장소에 설정만 커밋하고 새 세션을 열면 플러그인이 받아지고, 첫 응답 전에 `harness-init` 제안이 나온다
- [ ] 설정을 채운 저장소에서 새 세션을 열면 core 규칙과 설정 값이 맥락에 있다(Claude에게 "멈추는 신호"를 물어 확인)
- [ ] 대화를 요약시킨 뒤에도 규칙이 다시 들어간다
- [ ] 서브에이전트에게 같은 질문을 해도 답한다
- [ ] 이 저장소에서 `main`에 커밋한 뒤, 붙인 프로젝트에서 자동 업데이트를 거쳐 새 버전이 실린다

### 엣지 · 실패

- [ ] `plugin/rules/` 파일 하나를 지우고 세션을 열면 사용자 화면에 경고가 보인다
- [ ] 설정 파일의 `HARNESS_SELF_EDIT=0`에서 에이전트가 그 파일을 고치려 하면 막힌다
- [ ] 설정 파일이 깨졌으면 `deny-*` 훅이 차단한다
- [ ] `git commit`은 승인 창이 뜨고, 거절하면 커밋되지 않는다. `git status`·`git add`는 창이 뜨지 않는다
- [ ] 추적되지 않는 임시 파일 삭제는 창이 뜨지 않고, 추적 중인 파일 삭제는 뜬다
- [ ] 자동 모드에서도 커밋 승인 창이 뜬다
- [ ] 스펙 상태 줄을 `Draft`→`Approved`로 고치면 창이 뜨고, 거절하면 파일이 바뀌지 않는다. 같은 스펙의 문장만 고치면 창이 뜨지 않는다
- [ ] `[미정]`을 지우고 값을 적는 편집은 창이 뜬다
- [ ] 형식이 틀린 커밋 메시지로 `git commit`을 하면 창이 뜨기 전에 이유와 함께 막힌다
- [ ] 설정이 채워진 `harness.conf`를 Claude가 고치려 하면 바뀌는 키·값이 적힌 창이 뜬다
- [ ] 테스트 파일을 열면 테스트 규칙 스킬이 실린다 (`paths` 스킬 확인)
- [ ] 이 저장소에서 평소 크기의 작업(M 규모) 하나를 끝까지 했을 때 하네스 승인 창이 커밋 횟수 + 삭제 횟수를 넘지 않는다

### 수동 / 통합

- [ ] 구현 전에 `claude --plugin-dir plugin`으로 위 정상 1~4, 실패 1, 자동 모드 승인 창, `paths` 스킬 자동 로드, 리스크 9·10을 먼저 확인한다 — 공식 문서와 실제 동작이 다르면 이 스펙을 고친 뒤 진행한다

## 완료 기준

- [ ] `scripts/dev.sh test` 통과
- [ ] `claude plugin validate plugin --strict` 통과
- [ ] 위 검증 시나리오 전부
- [ ] "고쳐야 하는 기존 결정" 세 곳과 "같은 변경에서 고칠 문서"가 같은 PR에 있다

## 리스크·미결정

| 항목 | 상태 | 비고 |
|------|------|------|
| **1. 경로 조건부 규칙 3개** | 확정 (2026-10-27 사용자) | `paths` 스킬로 바꾼다. 처음 제안은 스킬화(Claude가 안 부르면 빠짐)와 `PostToolUse` 훅 두 가지였는데, 사용자가 다른 방법을 찾아보라고 해 스킬의 `paths` 필드를 찾았다. 자동 로드가 확실하지 않으면 훅으로 바꾼다 |
| **2. 설정 파일 형식·위치** | 확정 (2026-10-27 사용자) | `.claude/harness.conf`(`키=값`). `harness-map.md` 표를 훅이 해석하는 안은 표 모양이 바뀌면 깨져서 버렸다 |
| **3. `scripts/`와 git 훅** | 확정 (2026-10-27 사용자) | 도구 상자는 `plugin/scripts/`, git 훅은 지우고 Claude 커밋 훅이 대신 검사한다. 사람이 터미널에서 하는 커밋은 검사하지 않는다. 처음 권장(복사 유지 + 옛 버전 경고)은 사용자가 다른 플러그인 사례를 찾아보라고 해 바뀌었다 |
| **4. 플러그인 이름과 스킬 이름** | 확정 (2026-10-27 사용자) | 플러그인 `superchaeyeons`. 스킬은 `harness-init` 유지 — `init`으로 바꾸면 짧은 `/init`을 기본 명령이 그대로 가져 헷갈린다. 작명 규칙("스킬은 짧은 동사 하나")과는 어긋나니 `.claude/rules/README.md` 작명 표에 예외로 적는다 |
| **5. 잠근 뒤 설정을 바꾸는 경로** | 확정 (2026-10-27 사용자) | Claude가 고치려 하면 승인 창이 뜨고 사용자가 누르면 반영된다. 사용자가 손으로 고치는 안은 재동기화마다 번거로워서 버렸다 |
| **6. 훅이 아예 실행되지 않는 경우** | 확정 (감수) | bash가 없거나 훅이 시간 초과되면 경고도 나지 않는다. Superpowers도 같은 위험을 지고 있다. 스크립트를 내장 기능만으로 짧게 유지하고, 정상 케이스를 `hook-cases.txt`로 매 커밋 판정해 줄인다 |
| **7. 클라우드 세션** | 확정 (미지원) | Out of Scope 참고 |
| **8. 승인 창 범주의 기본값** | 확정 (2026-10-27 사용자) | 다섯 범주 전부 ☑(민감한 경로는 빈 목록으로 시작). 커밋을 여러 개로 나누면 커밋마다 창이 뜬다 — 분할안 최대 5개라 한 작업에 최대 5번이다 |
| **9. 승인 창이 뜨지 않는 실행 방식** | [미정] | `-p` 비대화형 실행과 권한 확인을 전부 건너뛰는 모드에서 `ask`가 어떻게 처리되는지 문서에 명확하지 않다. 비대화형은 답할 사람이 없어 거절될 가능성이 크다. 수동 검증 단계에서 확인하고 결과를 이 행에 적는다 |
| **10. 기본 권한 창과 겹침** | [미정] | 허용 목록에 없는 Bash 명령은 원래도 권한 창이 뜬다. 훅의 `ask`와 합쳐져 창이 한 번 뜨는지 두 번 뜨는지 수동 검증 단계에서 확인한다. 두 번이면 이유 한 줄로 합치는 방법을 찾는다 |

## 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-10-27 | 초안 — 공식 문서 확인 결과 · Superpowers 벤치마킹 · 기존 결정 개정 제안 |
| 2026-10-27 | 행동 강제(승인 창 훅) 추가 — 범주 4개 · 띄우지 않는 경우 테스트 · 채팅 승인 대체 · `core-gates.md` §3 개정 제안 |
| 2026-10-27 | 승인 창 범주에 "스펙 승인·[미정] 확정" 추가 |
| 2026-10-27 | 사용자 결정 반영 — [미정] 1·2·3·4·5·8 확정. 경로 조건부 규칙은 `paths` 스킬, 도구 상자는 플러그인 안, git 훅은 Claude 커밋 훅으로 대체, 설정 잠금은 승인 창. 질문 하나씩 막는 훅은 보류 |
