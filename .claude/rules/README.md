---
paths:
  - ".claude/agents/**"
  - ".claude/skills/**"
  - ".claude/hooks/**"
  - ".claude/settings*.json"
  - ".claude/rules/README.md"
---

# `.claude/rules` — 하네스 구성 요소 지도

에이전트가 이 저장소에서 작업할 때 참조하는 **하네스**(규칙·스킬·에이전트·훅)의 구조 인덱스다. 루트 `CLAUDE.md`(AGENTS.md를 import)는 프로젝트 지도, `.claude/`는 에이전트 행동·워크플로·안전장치를 담는다. 이 파일은 사람이 보는 디렉터리 맵이라 행동 규칙이 아니며, 구성 요소를 추가·삭제할 때만 로드된다(`paths:`).

하네스가 왜 이렇게 됐는지(설계 근거·사고 이력)는 이 저장소의 `{{문서 루트}}/harness/`가 갖고, 새 프로젝트에는 배달하지 않는다. 구성 요소별로 언제 실행되고 무엇을 묻고 검사하는지, 고치려면 어디를 건드리는지는 같은 폴더의 `component-map.md`가 표로 갖는다 — 구성 요소를 추가·삭제·개명하면 그 문서도 같은 턴에 갱신한다.

## 3층 구조

파일마다 누가 고칠 수 있는지가 다르다. 이 구분이 이식성의 근거다.

| 층 | 파일 | 수정 권한 | 이유 |
|----|------|-----------|------|
| **core (부품)** | `rules/core-*.md` · `skills/` · `agents/` · `hooks/` · `settings.json` | **금지** — `scripts/check-portability.sh`가 고유명사·스택 식별자·경로 리터럴·팩 참조를 exit code로 막는다. 예외: `settings.json`의 훅 등록 행은 `adopt`이 플래그에 따라 씨앗 훅을 추가·해제한다 | 모든 프로젝트에서 바이트 단위로 같아야 개선이 함께 전파된다 |
| **map (값)** | `rules/harness-map.md` | 채우기 — `adopt` 스킬 | 축·슬롯·플래그의 이 프로젝트 값 |
| **local (고유)** | `.claude/` 안의 `local-*` 파일 전부 — `rules/local-*.md` · `agents/local-*.md` · `hooks/local-*.sh` | 자유 | 이 저장소에서만 사는 사실·복사한 lang 팩. 검사기는 접두사로 이 층을 식별해 검사에서 뺀다 |

스택 규칙(lang 팩)은 배달물에 없다. `adopt`이 `examples/seeds/{스택}/`에서 복사하거나 `_template/`을 채운다 — 씨앗 파일명이 이미 `local-*`이므로 복사한 그대로 local 층이다.

## 디렉터리 구조

배달물 그대로의 트리다. 스택 규칙은 없고 `local-*.md`는 프로젝트가 만들 때만 생긴다.

```
.claude/
├── settings.json          ← 훅 등록 (버전 관리) — 스택 무관 훅만
├── settings.local.json    ← 개인 권한 allowlist (커밋 안 됨)
├── hooks/                 ← 결정론적 하한선. 규약: scripts/test-hooks.sh 가 판정
│   ├── deny-dangerous-bash.sh        # 파괴적 shell 명령 차단
│   ├── deny-out-of-scope-write.sh    # {{작업 범위}} 밖 쓰기 차단 (SCOPE=. 이면 무동작)
│   ├── deny-unverified-completion.sh # Stop: 코드 고치고 테스트 안 돌린 완료 선언 되돌림
│   ├── ask-open-request.sh           # UserPromptSubmit: 열린 요청이면 ask 스킬 알림 주입
│   └── warn-unfilled-map.sh          # SessionStart: harness-map ⬜·이유 없는 (없음) 경고
├── agents/                ← 조사·리뷰 전용 서브에이전트 (Edit/Write 없음)
│   ├── researcher.md                 # G1 외부 문서 조사
│   └── doc-reviewer.md               # G3 문서 품질 리뷰 (advisory)
├── rules/
│   ├── README.md                     ← 이 파일
│   ├── core-guardrails.md            # ⛔ STOP §1~§3 · 플래그 판정 (always-load)
│   ├── core-gates.md                 # 통제/위임 · 멈추는 신호 · 자동으로 하지 않는 것 (always-load)
│   ├── core-workflow.md              # 4 트랙 × 4 게이트 (always-load)
│   ├── core-scope.md                 # [미정] 처리 · 라벨은 local-priority (always-load)
│   ├── core-followup.md              # 후속 제안 · Defer · ERD (always-load)
│   ├── core-tools.md                 # 서브에이전트 규약 · 별도 컨텍스트 리뷰 · 도구 채택 기준 (always-load)
│   ├── core-reporting.md             # 비전공자용 보고 문체 (always-load)
│   ├── harness-map.md                # 축·슬롯·플래그 값 — 프로젝트가 채우는 유일한 파일 (always-load)
│   ├── doc-writing.md                # 문서 작성 규칙 (paths: 마크다운)
│   ├── core-code-comments.md         # 코드 주석 원칙 — 언어 무관 (paths: 소스 파일)
│   └── local-*.md                    # 이 저장소 고유 (있을 때만)
└── skills/                ← 승인 게이트가 있는 반복 워크플로
    ├── adopt/ · ask/ · specify/ · safe-refactor/ · debug/ · preflight/ · defer/ · retro/
    └── */references/                 # 스킬이 읽는 골격 (spec-template · audit-template · audit-checklist)
```

## 파일별 역할

종류마다 언제 로드·실행되는지가 다르다.

| 경로 | 역할 | 적용 시점 |
|------|------|-----------|
| `settings.json` | **이벤트 → 훅 스크립트** 매핑 | 에이전트가 도구를 호출하기 직전·직후, 프롬프트 제출, 턴 종료, 세션 시작 |
| `hooks/*.sh` | 훅 본문 — 차단·경고·주입 | `settings.json`이 지정한 이벤트 |
| `rules/*.md` (frontmatter 없음) | **항상** 로드되는 규칙 | 세션 시작 시 |
| `rules/*.md` (`paths:` frontmatter) | **glob에 매칭되는 파일**을 읽을 때만 로드되는 규칙 | 해당 파일 접근 시 |
| `skills/*/SKILL.md` | 다단계 워크플로 | 에이전트가 해당 상황을 인식할 때 (`core-workflow.md` 트랙 표·게이트 절이 라우터) |
| `agents/*.md` | 서브에이전트 정의 (`tools`·`model` + 본문=시스템 프롬프트) | 파일을 만들면 등록 |

## Rules

`paths`가 없으면 세션 시작 시 항상 로드되고, 있으면 매칭 파일을 읽을 때만 로드된다. always-load 합계는 `scripts/check-portability.sh`가 예산과 대조한다.

### Always-load

| 파일 | 요약 | SSOT 범위 |
|------|------|-----------|
| `core-guardrails.md` | ⛔ 문서 정합(계약에 닿는 변경은 같은 턴) · 레거시 즉시 삭제 · `{{현재동작 요약}}` 갱신 · 플래그 판정 원칙 | **하지 말 것** |
| `core-gates.md` | 통제 영역 vs 위임 영역 · 멈추는 신호 · 자동으로 하지 않는 것 · 승인 통로 = 설정 변경 | **언제 멈추는가** |
| `core-workflow.md` | 진입(트랙 분류) · 4 트랙 × 4 게이트 · 불변 조건 · 구현 중 지킬 것 · `report.md` | **어떤 순서로** |
| `core-scope.md` | `[미정]` 표기만 · 우선순위 라벨은 `local-priority.md`(견본은 `examples/`) | 범위 미확정 |
| `core-followup.md` | 후속 제안 · Defer · ERD 제안 | 완료 후 |
| `core-tools.md` | 서브에이전트 호출 규약 · 별도 컨텍스트 리뷰 · 서드파티 도구 채택 기준 (트랙·게이트별 도구는 `core-workflow`가 직접 적는다) | 도구 규약 |
| `core-reporting.md` | 사용자 보고는 쉬운 말로 (코드 주석 제외) | 보고 문체 |
| `harness-map.md` | 축 4 · 슬롯 22 · 능력 플래그 8의 **이 프로젝트 값** | 값 |
| `local-*.md` | 이 저장소에서만 사는 사실 (릴리즈 게이트·도메인 용어 등) | 프로젝트 고유 — 검사 대상 아님 |

우선순위: `core-guardrails` ⛔ > `core-gates` > `core-workflow` > 스킬 > 일반 관례

### Path-scoped

| 파일 | `paths` | 요약 |
|------|---------|------|
| `core-code-comments.md` | 소스 파일 확장자(다스택) | 코드 주석 원칙 — 실행 줄 위 단계 주석 · 필드·의존성 해설 · 실물 대조 · 이유. 언어별 표기는 lang 팩 |
| `doc-writing.md` | 문서 루트·`.claude/` 마크다운 · 이슈·PR 템플릿 | 문서 유형 → 정보 구조 → 문장. 기계 판정은 `scripts/check-doc-style.sh` |
| lang 팩 (복사 후, `local-{스택}.md`) | 그 언어 확장자 | 씨앗 README 참고 |
| `README.md`(이 파일) | `agents/**`·`skills/**`·`hooks/**`·`settings*.json`·이 파일 | 구조 인덱스 |

### 규칙 추가·분리 가이드

1. **한 규칙 = 한 관심사.** 새 파일보다 기존 파일의 절을 먼저 검토한다 (부품성 원칙 2 — 새 개념은 기존 개념을 대체해야 한다)
2. 전역 STOP → `core-guardrails` · 멈추는 신호 → `core-gates` · 작업 순서 → `core-workflow`
3. 프로젝트 고유 사실은 `core-*`에 넣지 않는다 — 경로면 슬롯, 정책이면 플래그, 둘 다 아니면 `local-*.md`
4. 파일 타입별 규칙 → `paths:` frontmatter. 같은 glob으로 파일을 둘로 나누는 것은 토큰 효과가 없다
5. 반복 실수 → 해당 규칙에 짧게 추가 (`retro` 스킬 절차)

## 작명 규칙

구성요소를 추가할 때 이름을 정하는 기준이다.

| 종류 | 규칙 | 예 |
|------|------|-----|
| **스킬** | 짧은 **동사** 하나 | `specify`, `preflight`, `adopt`, `ask` |
| **규칙** | 적용 시점·대상이 드러나는 명사구. 부품은 `core-`, 고유는 `local-` (접두사로 층이 갈려 검사기가 기계적으로 구분) | `core-gates`, `harness-map`, `local-release` |
| **훅** | 동작을 접두사로 — 차단 `deny-`, 경고 `warn-`, 자동 실행 `auto-`, 질문 유도(주입) `ask-` | `deny-out-of-scope-write.sh`, `ask-open-request.sh` |
| **에이전트** | 역할 명사, 20자 이내 | `researcher`, `doc-reviewer`, `{스택}-reviewer` |
| **씨앗에서 복사한 파일** | 종류 무관하게 파일명 맨 앞에 `local-` — 그 뒤는 위 규칙대로. 에이전트의 `name:` frontmatter는 접두사 없이 둔다 | `local-{스택}.md`, `local-{스택}-reviewer.md`(name: `{스택}-reviewer`), `local-deny-db-migration.sh` |

이미 짧고 뜻이 통하면 개명하지 않는다. 흔한 영어 단어를 이름으로 쓰면 코드의 일반 용법과 섞여 일괄 치환이 불가능해지므로, 새 이름을 고를 때 저장소 전체에서 그 단어가 몇 번 쓰이는지 먼저 센다.

## Skills

호출 주체를 표에 적는다 — 사용자가 이름을 부르는 것과 에이전트가 상황을 보고 스스로 부르는 것을 구분한다.

| 스킬 | 언제 | 호출 | 산출물 |
|------|------|------|--------|
| `adopt` | **D 트랙** — 하네스를 붙일 때 · `harness-map.md` 재동기화 | 사용자 | `harness-map.md` 값 · lang 팩 복사/채움 · `local-*.md` · `AGENTS.md`. 코드 불변 |
| `ask` | **G2 앞** — 열린 요청·미명시 기본값·해석이 갈리는 범위 | 에이전트 (`ask-open-request.sh`가 알림) | 없음 — 라운드 인터뷰, 사실은 조사·결정만 질문 |
| `specify` | **A 트랙** — 기능·API·DB·정책 변경 | 에이전트 | `{{스펙 저장소}}/{unit}/{name}.md` (불변 조건 절 포함) |
| `safe-refactor` | **B 트랙** — 기존 코드 감사·리팩터 | 사용자 | 감사 문서 `{{감사 로그}}/{unit}/{NNN}-*.md` · `refactor-log.md` |
| `debug` | **C 트랙** — 버그·테스트 실패 | 에이전트 | 없음 — 재현·원인 분리 절차 |
| `preflight` | **G2 직후(사전) · G3(사후)** | 에이전트 | 없음 — 검증 절차. 미검증은 `report.md`로 |
| `defer` | **G4** — 「다른 이슈로」 | 에이전트 | Draft 스펙 + Approved amend + (확인 후) 이슈 |
| `retro` | **G4** — 하네스 개선 후보 | 사용자·에이전트 | `{{문서 루트}}/audits/harness-retro.md` append. 메인 컨텍스트 실행 |

각 SKILL.md는 첫 줄에 **"이 스킬이 기본 동작과 다른 단 하나"**, 끝에 **"It's working if"**(파일을 열지 않고 확인 가능한 신호)를 둔다.

## Agents

게이트에서 호출하는 조사·리뷰 전용 서브에이전트다. `tools`에서 `Edit`/`Write`를 뺐지만 **`Bash`가 있어 물리적으로 막혀 있지는 않다** — 마지막 한 겹은 각 지침의 "수정하지 않는다" 규범이다. 결정론적 차단으로 오해하지 않는다.

| 에이전트 | 게이트 | 역할 |
|----------|--------|------|
| `researcher` | G1 | 외부 문서 조사. 로컬 실물 버전 → 공식 문서(버전 확인) → 릴리즈 노트 순서 강제. 규칙 파일에 박힌 버전을 믿지 않는다 |
| `doc-reviewer` | G3 | 문서 유형·정보 구조·문장 3단계 리뷰 (기준 `doc-writing.md`). advisory |
| `{스택}-reviewer` | G3 | **[플래그: 스택 리뷰어]** lang 팩이 지정. 정적 검사가 못 잡는 결함만 (씨앗 예: `examples/seeds/java-spring/agents/`) |

**호출 규약:** 대상은 경로 목록으로만 넘기고 읽기 범위는 에이전트 지침에 맡긴다. "전문을 읽어라"는 신규 파일에만. 대상이 10개를 넘으면 나눠 부른다.

## Hooks

배달물에 등록된 훅 5개다. 전부 스택 무관이다.

| 이벤트 | 매처 | 훅 | 동작 |
|--------|------|-----|------|
| `PreToolUse` | `Bash` | `deny-dangerous-bash.sh` | 파괴·우회·시크릿 명령 차단 (exit 2) — force push · `rm -rf`·`find -delete` · `git reset --hard`·`clean -f`·`branch -D`·`stash drop`·`filter-branch` · `git commit --no-verify` · `.env` add/commit · SQL DROP · 컨테이너 볼륨 삭제 · `curl \| sh` · `chmod -R 777` · `dd of=/dev`. 정확한 목록은 훅의 `PATTERNS` 배열. 알려진 오탐: 명령 문자열 전체에서 패턴을 찾아 문자열로만 언급해도 막힌다 — fail-closed 의도라 유지. 못 보는 것: 변수·`eval`·별도 스크립트 간접 실행 |
| `PreToolUse` | `Write\|Edit` | `deny-out-of-scope-write.sh` | (1) **[플래그: 하네스 자기 수정]** ❌면 `.claude/hooks/`·`settings.json` 쓰기 차단 (2) `{{작업 범위}}` 밖 쓰기 차단 (exit 2). 훅 상수 `HARNESS_SELF_EDIT`·`SCOPE` = 플래그·슬롯 값. 저장소 밖 절대경로는 통과 |
| `UserPromptSubmit` | — | `ask-open-request.sh` | 열린 표현(한국어·영어)이면 `ask` 알림 주입 (항상 exit 0 — 차단하면 프롬프트가 지워진다) |
| `Stop` | — | `deny-unverified-completion.sh` | 코드 수정(도구 편집 + Bash `sed -i`·리다이렉션·`tee`) 뒤 `TEST_CMD`(= `{{테스트 명령}}`)를 **그 다음에** 실행한 기록이 없거나 결과가 실패인데 완료 단정이면 되돌림 (exit 2). 문서만·재진입·판정 불가는 통과 |
| `SessionStart` | — | `warn-unfilled-map.sh` | `harness-map.md`에 ⬜·이유 없는 `(없음)`이 남았으면 경고 주입 |

lang 팩 훅(포맷 자동 실행 · 마이그레이션 파일 차단 · 계약 변경 경고)은 씨앗에 있고, 해당 플래그가 ☑일 때 `adopt`이 복사·등록한다.

**훅 공통 규약:** `deny-*`는 정상 범위 통과, 위반 exit 2, **판정 불가(JSON 깨짐·키 없음·빈 입력·python3 없음)도 exit 2**. 경로는 실경로로 정규화한다. `settings.json`의 훅 경로는 `$CLAUDE_PROJECT_DIR` 기준이라 cwd에 기대지 않는다. `Stop` 훅만 판정 불가면 통과(대화가 끝나지 못하는 피해가 더 크다). [`scripts/test-hooks.sh`](../../scripts/test-hooks.sh)가 [`scripts/hook-cases.txt`](../../scripts/hook-cases.txt)로 판정하고, 훅·케이스가 stage되면 pre-commit이 같은 테스트를 돌린다. 새 우회 경로를 발견하면 케이스를 먼저 추가한다. 훅에 "확인받았으면 통과" 통로는 없다 — 승인은 사용자가 `harness-map.md` 값과 훅 상수를 바꾸는 행위다 (`core-gates.md` §3).

**훅이 슬롯·플래그 값을 읽는 방법:** 훅 본문 상수(`SCOPE`·`HARNESS_SELF_EDIT`·`TEST_CMD`·`FORMAT_CMD`)에 직접 적고, `harness-map.md` 해당 행이 "함께 고칠 것"이라고 가리킨다. 별도 설정 파일은 SSOT를 둘로 가른다. 훅 스크립트는 고친 즉시 다음 도구 호출부터 효력이 생긴다 — 그래서 "하네스 자기 수정" 플래그가 ❌인 프로젝트에서는 훅이 자기 자신에 대한 쓰기를 막는다.

**advisory 훅은 `command`-type으로:** 서브에이전트가 판단하는 `agent`-type 훅은 "절대 막지 마라"는 지시에도 커밋을 막은 사고가 있었다. 판단은 LLM에게, "항상 이렇게 동작해야 한다"는 결정론적 스크립트에게.

## 설정 파일

`settings.json`은 훅 등록과 **`permissions.deny`**(도구 권한 층의 차단 목록 — `.env` 읽기·쓰기, `git push --force`·`git reset --hard`·`rm -rf`·`git commit --no-verify` 접두사)를 담아 버전 관리한다. deny는 allow보다 먼저 판정되므로 개인 allowlist로 풀리지 않는다. 훅과 같은 항목을 두 층에 두는 이유는 훅이 문자열을 보는 하한선이고 권한 규칙은 도구 호출 자체를 막기 때문이다. `settings.local.json`은 개인 권한 allowlist라 커밋되지 않는다.

## 유지보수 체크리스트

- [ ] 스킬·에이전트를 추가·삭제·개명하면 **같은 턴에** `core-workflow.md` 트랙 표·게이트 절과 이 README의 Skills·Agents 표, `{{문서 루트}}/harness/component-map.md`를 갱신 — 없어진 스킬로 안내하는 라우터는 거짓말을 한다
- [ ] 훅을 추가·삭제·수정하면 `scripts/hook-cases.txt`에 케이스를 먼저 넣고 `scripts/test-hooks.sh` 통과 → 이 README Hooks 표 + 디렉터리 구조 갱신
- [ ] 규칙 파일을 고쳤으면 `scripts/check-portability.sh` exit 0 (배달물 전체가 판정 대상)
- [ ] 문서를 새로 만들거나 크게 고쳤으면 `scripts/check-doc-style.sh` 오류 0 + `doc-reviewer`
- [ ] 슬롯·플래그를 늘리는 문턱: `core-*.md`에서 실제로 그 `{{슬롯}}`·`[플래그]`를 쓰는 곳이 있을 때만
- [ ] 안 하기로 한 것은 `{{문서 루트}}/out-of-scope/README.md`에 이유와 함께
