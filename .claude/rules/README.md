---
paths:
  - "plugin/**"
  - ".claude-plugin/**"
  - ".claude/agents/**"
  - ".claude/skills/**"
  - ".claude/hooks/**"
  - ".claude/settings*.json"
  - ".claude/rules/README.md"
  - ".claude/rules/harness-map.md"
  - "scripts/git-hooks/**"
---

# `.claude/` — 하네스 구성 요소 목록

하네스 구성 요소(규칙·스킬·에이전트·훅)의 **목록 SSOT**이자 `harness-map.md`를 고치는 규칙이다. 매 작업에 필요한 행동 규칙이 아니라서 플러그인(`plugin/`)·`.claude/`의 구성 요소·`harness-map.md`·git 훅을 열 때만 로드된다.

구성 요소를 추가·삭제·개명하면 이 파일을 같은 턴에 고친다 — `plugin/scripts/check-portability.sh`가 실제 파일과 이 목록을 대조하고, 살아 있는 문서가 없는 규칙·훅·스킬·에이전트를 가리키면 실패한다. 각 구성 요소의 상세 동작은 그 파일 머리가 SSOT다.

## 3층 — 누가 고치나

파일마다 수정 권한이 다르고, 이 구분이 이식성의 근거다.

| 층 | 파일 | 수정 | 이유 |
|----|------|------|------|
| **core** | `plugin/` 전부(규칙·스킬·에이전트·훅·도구) | 금지 — `check-portability.sh`가 고유명사·스택 식별자·경로 리터럴을 막는다. 예외: 붙여 쓰는 프로젝트(하네스 자기 수정 ❌)에서는 아래 "훅 상수와 짝"의 대입 값과 `{{Git 컨벤션 SSOT}}`인 `CONTRIBUTING.md`가 프로젝트 값 자리라 검사 밖 | 모든 프로젝트에서 같아야 개선이 함께 전파된다 |
| **map** | `rules/harness-map.md` | `init-harness`가 채운다 | 이 프로젝트의 축·슬롯·플래그 값 |
| **local** | `.claude/` 안의 `local-*` 전부 | 자유 | 저장소 고유 사실·관례. 검사기가 접두사로 이 층을 뺀다 |

스택 규칙은 배달물에 없다. 프로젝트가 따로 적을 관례는 `local-*.md`에 쓴다.

## 목록

로드 시점과 한 줄 역할이다. 스킬·에이전트는 description만 항상 실리고 본문은 호출될 때 실린다.

```text
.claude-plugin/marketplace.json       마켓플레이스 — 플러그인 superchaeyeons(plugin/) 하나를 등록
plugin/                               배달물 — 붙인 프로젝트는 플러그인으로 받는다. 이 저장소는 로컬 경로 마켓플레이스로 제자리 로드
├── .claude-plugin/plugin.json        매니페스트 — version 없음(커밋 SHA가 버전). scripts/check-plugin.sh가 검사
├── rules/                            Claude Code가 직접 읽지 않는다 — 주입 훅이 넣는다 (훅 하나당 9,000자 이하, check-portability.sh)
│   ├── core-guardrails.md            세션 시작·서브에이전트 — ⛔ STOP: 문서·구현 정합 · [미정] · 레거시 즉시 삭제 · 현재동작 요약 갱신
│   ├── core-gates.md                 세션 시작·서브에이전트 — 통제/위임 영역 · 멈추는 신호 · 자동으로 하지 않는 것
│   ├── core-workflow.md              세션 시작·서브에이전트 — 트랙 4 × 규모 3 × 게이트 4
│   ├── core-reporting.md             세션 시작·서브에이전트 — 사용자 보고 문체
│   ├── core-code-comments.md         소스 파일을 다룰 때(paths:) — 주석 원칙
│   ├── core-testing.md               테스트 파일을 다룰 때(paths:) — 테스트 원칙 S1~S8
│   └── doc-writing.md                마크다운을 다룰 때(paths:) — 문서 유형·구조·문장
├── skills/
│   ├── init-harness/                 D 트랙 — 실측 → 슬롯·플래그 제안 → 채움 (사용자 호출)
│   ├── ask-decisions/                G2 앞 — 사용자 결정을 하나씩 묻는 인터뷰
│   ├── write-spec/                   A 트랙 — 스펙 → 승인. 범위를 다른 이슈로 미룰 때도
│   ├── test-first/                   구현 — 승인된 테스트 먼저 지점 · 버그 재현 테스트
│   ├── refactor-safely/              B 트랙 — 감사 → 승인 → 구현 → 기계 검증 (사용자 호출)
│   ├── fix-bug/                      C 트랙 — 재현 → 원인 분리 → 최소 수정
│   ├── verify-work/                  G2 직후 · G3 · G4 마무리 — 실행 결과만 보고 (G3 절차 · G4 상세 SSOT)
│   └── improve-harness/              G4 — 회고 분석이 낸 하네스 개선 후보를 사람과 검토해 장부에 (분석 지시문 references/analyze.md)
├── agents/                           셋 다 omitClaudeMd — 매번 읽히는 규칙 없이 시작, 슬롯 값은 harness-map.md를 읽는다
│   ├── researcher.md                 G1 — 외부 문서 조사, 결론·근거만 반환
│   ├── test-writer.md                test-first 1단계 — 통제 영역 지점의 테스트를 스펙만 보고 작성 (Bash 없음)
│   └── doc-reviewer.md               G3 — 문서 유형·구조·문장 리뷰 (advisory)
├── hooks/
│   ├── hooks.json                    훅 등록 — 명령은 "${CLAUDE_PLUGIN_ROOT}/hooks/…"
│   ├── deny-dangerous-bash.sh        PreToolUse Bash — 파괴·우회·시크릿 명령 차단, 실행되는 부분만 검사 (묶음별 막기·맡기기는 맨 위 상수)
│   ├── deny-out-of-scope-write.sh    PreToolUse Write|Edit|MultiEdit|NotebookEdit — 범위 밖 쓰기 · (자기 수정 ❌) 플러그인 폴더·local 훅·settings 쓰기 차단
│   ├── deny-unverified-completion.sh Stop — 코드 편집 뒤 TEST_CMD 미실행·실패인데 완료 선언이면 한 번 되돌림
│   ├── auto-inject-rules.sh          SessionStart(startup|clear|compact)·SubagentStart — core 규칙 4개 주입 · 못 읽으면 경고 (omitClaudeMd 에이전트는 뺌)
│   ├── auto-inject-path-rules.sh     PostToolUse Read|Write|Edit|MultiEdit|NotebookEdit — 다룬 파일이 paths: glob에 맞으면 그 규칙을 세션당 한 번 주입
│   ├── auto-correction-queue.sh      PostToolUse Write|Edit|MultiEdit|NotebookEdit — 정정 기억(type: feedback) 저장을 정정 대기열에 기록
│   └── auto-correction-notice.sh     SessionStart — 마지막 회고 분석 뒤 세션·정정 기억·검토할 후보 수를 한 줄로 (셋 다 0이면 출력 없음) · 7일 지나면 분석을 뒤에서 띄움
└── scripts/                          도구 — 스킬·에이전트 본문은 ${CLAUDE_PLUGIN_ROOT}/scripts/…로 부른다. 프로젝트 루트는 git 최상위(없으면 현재 폴더)
    ├── dev.sh                        빌드·테스트·실행 엔진 (프로젝트 값은 dev.conf)
    ├── check-portability.sh          부품 계약 · 슬롯·구성 요소 목록 대조 · always-load 예산 (패턴 portability-patterns.txt)
    ├── check-doc-style.sh            문서 스타일 (패턴 doc-style-patterns.txt)
    ├── init-harness-probe.sh         init-harness 1단계 실측
    ├── analyze-corrections.sh        회고 분석 (별도 실행)
    └── polish-with-gemini.sh         글 다듬기 (스킬 단계에서 부름)
.claude/                              이 저장소 전용·프로젝트 층
├── settings.json                     마켓플레이스 등록(extraKnownMarketplaces)·플러그인 켜기(enabledPlugins) + permissions.deny(.env 읽기·쓰기 · force push · hard reset · --no-verify — 훅이 막는 묶음과 이중)
├── settings.local.json               개인 allowlist — 커밋 안 함
├── rules/
│   ├── harness-map.md                항상 — 축·슬롯·플래그 값
│   ├── README.md                     플러그인·.claude/ 구성 요소·harness-map·git 훅을 열 때 — 이 파일 (목록 · map 고치기)
│   └── local-*.md                    저장소 고유 (있을 때만)
└── skills/
    └── local-track-issues/           프로젝트 층 트래커 안내 — 이슈 확인·만들기·연결의 수단·키·표기. `{{이슈 연결}}`이 가리킨다 (골격 plugin/skills/init-harness/references/)
```

회고 루프의 분석은 훅이 아니라 `plugin/scripts/analyze-corrections.sh`가 별도 실행으로 한다. 기록·분석 상태는 `.claude/corrections/`(git이 무시)에 있고, 형식은 그 스크립트 머리가 SSOT다. 문서 다듬기도 훅이 아니라 스킬 단계에서 `plugin/scripts/polish-with-gemini.sh`를 부르고, 상태는 `.claude/polish/`(git이 무시)에 둔다.

우선순위는 `core-guardrails` ⛔ > `core-gates` > `core-workflow` > 스킬 > 일반 관례다. 같은 주제를 여러 파일에 쓰지 않고, 아래쪽 파일은 위쪽을 가리킨다.

## 훅 공통 규약

`scripts/test-hooks.sh`가 `scripts/hook-cases.txt`로 판정한다.

- `deny-*`는 정상 범위 통과 · 위반 exit 2 · **판정 불가(JSON 깨짐·키 없음·빈 입력·python3 없음)도 exit 2**. 경로는 실경로로 정규화한다
- 훅 안의 python3는 **`python3 -I`**로 부른다 — 훅은 작업 폴더에서 도는데 `-I` 없이는 그 폴더가 모듈 경로 맨 앞에 들어가, 폴더에 있는 `json.py` 같은 파일이 표준 라이브러리 대신 불려 판정이 뒤집힌다. `test-hooks.sh`가 가짜 `json.py`를 둔 폴더에서 `deny-*`를 돌려 확인한다
- `Stop` 훅만 판정 불가와 재진입(`stop_hook_active`)이면 통과한다 — 대화가 끝나지 못하는 피해가 더 크다
- `auto-*`(기록·알림)는 막지 않는다 — 어떤 입력에도 exit 0이고, 기록하지 못하면 `systemMessage`로 알린다. 세션마다 도니 bash 3.2 내장 기능과 macOS 기본 명령만 쓴다(python3 없음). 출력과 남긴 파일은 케이스의 `out~`·`file:` 검사로 판정한다
- 배달 훅은 `"${CLAUDE_PLUGIN_ROOT}/hooks/…"`로 등록하고 `plugin/hooks/*.sh`는 전부 `plugin/hooks/hooks.json`에 등록돼야 한다. 프로젝트 층 local 훅은 `$CLAUDE_PROJECT_DIR` 기준 `.claude/hooks/`에 두고 `settings.json`에 등록한다(플러그인 훅을 `settings.json`에도 적으면 두 번 돈다). 프로젝트 루트는 훅이면 `CLAUDE_PROJECT_DIR`, Bash로 부르는 도구면 git 최상위로 잡는다 — Bash 도구에는 두 변수가 모두 없다. 쓰기 도구 매처는 `Write`·`Edit`·`MultiEdit`·`NotebookEdit`를 모두 덮어야 한다 — 매처는 정확한 이름 목록이라 `Write|Edit`만 두면 나머지 둘이 훅을 건너뛴다
- "확인받았으면 통과" 통로는 없다. 승인은 사용자가 `harness-map.md` 값과 짝인 훅 상수를 바꾸는 것이다. 막힐 때 각 `deny-*` 훅의 차단 메시지가 이 안내를 Claude에게 준다
- 훅은 명령 문자열만 본다. 변수·별도 스크립트 간접 실행과 Bash로 하네스 파일을 고치는 것은 못 보므로 규칙으로만 막는다 (`eval`·`bash -c` 안은 `deny-dangerous-bash.sh`가 다시 검사한다)
- 판단이 필요한 것은 훅에 넣지 않는다. advisory 훅이 필요하면 `command`-type으로 — `agent`-type 훅이 "막지 마라"는 지시에도 커밋을 막은 사고가 있었다

## harness-map.md 고치기

`harness-map.md`는 값만 담고, 값을 고칠 때의 규칙은 여기 둔다. map은 프로젝트가 소유해 하네스를 갱신해도 바뀌지 않으므로, 모든 프로젝트에 같이 적용돼야 하는 설명은 이 파일(core)에 있어야 함께 전파된다.

**map 규칙**

1. 빈 슬롯은 `(없음) — 이유`로 적는다 — "안 정했다"와 "이 프로젝트엔 없다"를 가르기 위해
2. `(없음)`인 슬롯을 규칙이 요구하면 멈추고 사용자에게 묻는다 (map 머리에도 있다)
3. 슬롯·플래그는 `core-*.md`가 실제로 쓸 때만 둔다 — `plugin/scripts/check-portability.sh`가 슬롯 정의와 사용을 대조한다
4. 옵션을 끄려고 규칙 절을 지우지 않는다 — ❌면 `[플래그: X]` 절을 무시한다
5. `core-*.md`는 손대지 않는다. 고유 사실은 map(값)과 `.claude/` 안의 `local-*`(규칙·스킬)에만. 클라이언트 전제·배포 토폴로지처럼 스택이 아닌 고유 사실은 `local-*.md`로 쓴다
6. 축은 붙이는 시점에 실측해 적는다. 규칙은 축을 직접 부르지 않는다 — 슬롯·플래그 값을 고르는 근거다. 기존 저장소에 붙일 때 명령·형식 슬롯은 기본값을 물려받지 않고 `init-harness`가 이력에서 실측한다

**훅 상수와 짝:** 훅·git 훅은 map을 읽지 못해 값을 본문에 직접 적는다. 아래 값을 바꾸면 짝을 같은 턴에 고친다.

- `{{작업 범위}}` ↔ `deny-out-of-scope-write.sh`의 `SCOPE`
- "하네스 자기 수정" ↔ 같은 훅의 `HARNESS_SELF_EDIT`
- `{{테스트 명령}}` ↔ `deny-unverified-completion.sh`의 `TEST_CMD`
- `{{커밋 메시지 형식}}` ↔ `scripts/git-hooks/commit-msg`의 `COMMIT_RE`
- `{{포맷 명령}}` ↔ `scripts/git-hooks/pre-commit`의 `FORMAT_CMD`·`FORMAT_PATHS`
- `{{문서 루트}}` ↔ `plugin/scripts/analyze-corrections.sh`의 `LEDGER`(장부 경로) · `plugin/scripts/polish-with-gemini.sh`의 `DOC_ROOT`
- 폴더 통째 삭제 막기(map에 없음 — `init-harness` 2단계 질문) ↔ `deny-dangerous-bash.sh`의 `BLOCK_BULK_DELETE`. 나머지 `BLOCK_*` 묶음 상수는 묻지 않고 배달 기본값 `1`(막기)로 둔다
- "Gemini 다듬기" ↔ 프로젝트 루트 `harness.conf`의 `POLISH_ENABLED=1`(☑일 때만 둔다). `plugin/scripts/polish-with-gemini.sh`의 같은 이름 상수는 배달 기본값 `0`이라 고치지 않는다 — 원본의 켜짐이 복사본에 실리지 않게

**플래그를 켜거나 끌 때 할 일** — 표에 없는 플래그는 값만 바꾼다.

| 플래그 | 할 일 |
|--------|-------|
| 하네스 자기 수정 | ❌면 `HARNESS_SELF_EDIT="0"`. **붙여 쓰는 프로젝트는 ❌가 기본** |

**옛 모양 map 정리:** map에 `## 규칙` 절 · 훅 상수 짝 목록 · 플래그 표 "켜거나 끌 때 할 일" 열이 들어 있으면 옛 모양이다. 하네스를 갱신하면 always-load 예산을 넘으니 `init-harness` 재동기화에서 그 셋과 축·명령 슬롯 표 앞의 작성 안내를 지우고, 머리에 `(없음)` 슬롯 문장과 이 절을 가리키는 문장만 남긴다. 값 표는 건드리지 않는다. 2026-10-28 뒤로는 축 표·스택별 규칙 파일 표·플래그 표 아래 설명 문단도 옛 모양이다 — 축은 값 그대로 `**축:**` 한 줄로 옮기고, 나머지 둘은 지운다. 2026-10-29 뒤로는 능력 플래그 표의 `DB 마이그레이션 금지`·`에러 코드 카탈로그 동시갱신`·`권한 게이트·활동 기록 동시갱신`·`API 계약 보호`·`스택 함정 메모`·`스택 리뷰어` 행도 옛 모양이라 지운다.

## 작명

구성 요소를 추가할 때 이름을 정하는 기준이다.

| 종류 | 규칙 | 예 |
|------|------|-----|
| 스킬 | 동사-목적어(필요하면 동사-부사). 이름만 보고 하는 일을 알 수 있게 | `write-spec`, `refactor-safely` |
| 규칙 | 적용 시점·대상 명사구. 부품은 `core-`, 고유는 `local-` | `core-gates`, `local-release` |
| 훅 | 동작 접두사 — 차단 `deny-` · 경고 `warn-` · 자동 실행 `auto-` | `deny-dangerous-bash.sh` |
| 에이전트 | 역할 명사, 20자 이내 | `researcher`, `{스택}-reviewer` |

새 이름은 저장소에서 그 단어가 몇 번 쓰이는지 먼저 센다 — 흔한 단어면 일괄 치환이 불가능해진다.

## 유지보수 체크리스트

- 구성 요소 추가·삭제·개명 → 이 목록 · `core-workflow.md` 트랙 표 · 산출물이 md면 `{{문서 루트}}/templates/README.md` 등록부. 새 개념은 기존 개념을 대체할 때만 들인다
- 훅 추가·수정 → `scripts/hook-cases.txt` 케이스 먼저 → `scripts/test-hooks.sh`
- 규칙 수정 → `plugin/scripts/check-portability.sh` (always-load 예산은 래칫 — 낮추기만 한다. 스킬·에이전트 설명 줄도 합계에 든다)
- **새 규칙을 넣을 곳** → 종료 코드로 판정되면 훅 → 끝난 뒤 확인해도 되면 `verify-work` 점검표 → 특정 파일을 다룰 때만 필요하면 `paths:` 규칙 → 구현 도중 늘 지켜야 할 때만 매번 읽히는 규칙. 앞 층으로 안 되는 이유가 있어야 다음 층으로 간다
- 토큰 비용 → 하네스를 고치면 항상 실리는 글(규칙·스킬·에이전트 description) · 호출될 때 실리는 본문 · 실행 비용(훅 출력·별도 모델 실행)이 각각 얼마나 늘거나 주는지 바이트나 토큰으로 적는다. 늘리는 쪽이면 더 싼 층에 둘 수 없는지 먼저 본다
- 문서 신설·50줄 이상 수정 → `plugin/scripts/check-doc-style.sh` 오류 0 + `doc-reviewer`
- 안 하기로 한 것 → `{{문서 루트}}/out-of-scope/README.md`에 이유와 함께
- 끝나면 `plugin/scripts/dev.sh test`
