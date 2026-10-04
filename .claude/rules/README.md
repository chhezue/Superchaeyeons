---
paths:
  - ".claude/agents/**"
  - ".claude/skills/**"
  - ".claude/hooks/**"
  - ".claude/settings*.json"
  - ".claude/rules/README.md"
---

# `.claude/` — 하네스 구성 요소 목록

하네스 구성 요소(규칙·스킬·에이전트·훅)의 **목록 SSOT**다. 행동 규칙이 아니라 인덱스라서 `.claude/`의 구성 요소를 열 때만 로드된다. 구성 요소를 추가·삭제·개명하면 이 파일을 같은 턴에 고친다 — `scripts/check-portability.sh`가 실제 파일과 이 목록을 대조하고, 살아 있는 문서가 없는 규칙·훅·스킬·에이전트를 가리키면 실패한다. 각 구성 요소의 상세 동작은 그 파일 머리가 SSOT다.

## 3층 — 누가 고치나

파일마다 수정 권한이 다르고, 이 구분이 이식성의 근거다.

| 층 | 파일 | 수정 | 이유 |
|----|------|------|------|
| **core** | `rules/core-*.md` · `skills/` · `agents/` · `hooks/` · `settings.json` | 금지 — `check-portability.sh`가 고유명사·스택 식별자·경로 리터럴·팩 참조를 막는다. 예외: `adopt`이 플래그에 따라 `settings.json`에 씨앗 훅 등록을 추가·해제 | 모든 프로젝트에서 같아야 개선이 함께 전파된다 |
| **map** | `rules/harness-map.md` | `adopt`이 채운다 | 이 프로젝트의 축·슬롯·플래그 값 |
| **local** | `.claude/` 안의 `local-*` 전부 | 자유 | 저장소 고유 사실·복사한 lang 팩. 검사기가 접두사로 이 층을 뺀다 |

스택 규칙(lang 팩)은 배달물에 없다. `adopt`이 `examples/seeds/{스택}/`에서 `local-*` 이름 그대로 복사하거나 `_template/`을 채운다.

## 목록

로드 시점과 한 줄 역할이다. 스킬·에이전트는 description만 항상 실리고 본문은 호출될 때 실린다.

```text
.claude/
├── settings.json                     훅 등록 + permissions.deny(.env 읽기·쓰기 · force push · hard reset · rm -rf · --no-verify — 훅과 이중)
├── settings.local.json               개인 allowlist — 커밋 안 함
├── rules/
│   ├── core-guardrails.md            항상 — ⛔ STOP: 문서·구현 정합 · [미정] · 레거시 즉시 삭제 · 현재동작 요약 갱신
│   ├── core-gates.md                 항상 — 통제/위임 영역 · 멈추는 신호 · 자동으로 하지 않는 것
│   ├── core-workflow.md              항상 — 트랙 4 × 규모 3 × 게이트 4
│   ├── core-reporting.md             항상 — 사용자 보고 문체
│   ├── harness-map.md                항상 — 축·슬롯·플래그 값
│   ├── core-code-comments.md         소스 파일을 열 때 — 주석 원칙
│   ├── core-testing.md               테스트 파일을 열 때 — 테스트 원칙 S1~S8
│   ├── doc-writing.md                마크다운을 열 때 — 문서 유형·구조·문장
│   ├── README.md                     .claude/ 구성 요소를 열 때 — 이 파일
│   └── local-*.md                    저장소 고유 (있을 때만)
├── skills/
│   ├── adopt/                        D 트랙 — 실측 → 슬롯·플래그 제안 → 채움 (사용자 호출)
│   ├── ask/                          G2 앞 — 열린 요청 라운드 인터뷰
│   ├── specify/                      A 트랙 — 스펙 → 승인. 범위를 다른 이슈로 미룰 때도
│   ├── tdd/                          구현 — 승인된 테스트 먼저 지점 · 버그 재현 테스트
│   ├── safe-refactor/                B 트랙 — 감사 → 승인 → 구현 → 기계 검증 (사용자 호출)
│   ├── debug/                        C 트랙 — 재현 → 원인 분리 → 최소 수정
│   ├── preflight/                    G2 직후 · G3 — 실행 결과만 보고 (G3 절차 SSOT)
│   └── retro/                        G4 — 하네스 개선 후보를 회고 백로그에
├── agents/
│   ├── researcher.md                 G1 — 외부 문서 조사, 결론·근거만 반환
│   ├── test-writer.md                tdd 1단계 — 통제 영역 지점의 테스트를 스펙만 보고 작성 (Bash 없음)
│   └── doc-reviewer.md               G3 — 문서 유형·구조·문장 리뷰 (advisory)
└── hooks/
    ├── deny-dangerous-bash.sh        PreToolUse Bash — 파괴·우회·시크릿 명령 차단 (목록은 PATTERNS)
    ├── deny-out-of-scope-write.sh    PreToolUse Write|Edit|MultiEdit|NotebookEdit — 범위 밖 쓰기 · (자기 수정 ❌) 훅·settings 쓰기 차단
    └── deny-unverified-completion.sh Stop — 코드 편집 뒤 TEST_CMD 미실행·실패인데 완료 선언이면 한 번 되돌림
```

우선순위는 `core-guardrails` ⛔ > `core-gates` > `core-workflow` > 스킬 > 일반 관례다. 같은 주제를 여러 파일에 쓰지 않고, 아래쪽 파일은 위쪽을 가리킨다.

## 훅 공통 규약

`scripts/test-hooks.sh`가 `scripts/hook-cases.txt`로 판정한다.

- `deny-*`는 정상 범위 통과 · 위반 exit 2 · **판정 불가(JSON 깨짐·키 없음·빈 입력·python3 없음)도 exit 2**. 경로는 실경로로 정규화한다
- `Stop` 훅만 판정 불가와 재진입(`stop_hook_active`)이면 통과한다 — 대화가 끝나지 못하는 피해가 더 크다
- 훅 경로는 `$CLAUDE_PROJECT_DIR` 기준이다. `.claude/hooks/*.sh`는 전부 `settings.json`에 등록돼야 하고, 쓰기 도구 매처는 `Write`·`Edit`·`MultiEdit`·`NotebookEdit`를 모두 덮어야 한다 — 매처는 정확한 이름 목록이라 `Write|Edit`만 두면 나머지 둘이 훅을 건너뛴다
- "확인받았으면 통과" 통로는 없다. 승인은 사용자가 `harness-map.md` 값과 짝인 훅 상수를 바꾸는 것이다 (`core-gates.md` §3)
- 훅은 명령 문자열만 본다. 변수·`eval`·별도 스크립트 간접 실행과 Bash로 하네스 파일을 고치는 것은 못 보므로 규칙으로만 막는다
- 판단이 필요한 것은 훅에 넣지 않는다. advisory 훅이 필요하면 `command`-type으로 — `agent`-type 훅이 "막지 마라"는 지시에도 커밋을 막은 사고가 있었다
- 씨앗 훅(`local-*`)은 플래그가 ☑일 때 `adopt`이 복사·등록한다. 복사하지 않은 씨앗의 케이스는 `test-hooks.sh`가 건너뛴다

## 작명

구성 요소를 추가할 때 이름을 정하는 기준이다.

| 종류 | 규칙 | 예 |
|------|------|-----|
| 스킬 | 짧은 동사 하나 | `specify`, `preflight` |
| 규칙 | 적용 시점·대상 명사구. 부품은 `core-`, 고유는 `local-` | `core-gates`, `local-release` |
| 훅 | 동작 접두사 — 차단 `deny-` · 경고 `warn-` · 자동 실행 `auto-` | `deny-dangerous-bash.sh` |
| 에이전트 | 역할 명사, 20자 이내 | `researcher`, `{스택}-reviewer` |
| 씨앗에서 복사한 파일 | 파일명 맨 앞에 `local-` (에이전트 `name:`은 접두사 없이) | `local-deny-db-migration.sh` |

새 이름은 저장소에서 그 단어가 몇 번 쓰이는지 먼저 센다 — 흔한 단어면 일괄 치환이 불가능해진다.

## 유지보수 체크리스트

- 구성 요소 추가·삭제·개명 → 이 목록 · `core-workflow.md` 트랙 표 · 산출물이 md면 `{{문서 루트}}/templates/README.md` 등록부. 새 개념은 기존 개념을 대체할 때만 들인다
- 훅 추가·수정 → `scripts/hook-cases.txt` 케이스 먼저 → `scripts/test-hooks.sh`
- 규칙 수정 → `scripts/check-portability.sh` (always-load 예산은 래칫 — 낮추기만 한다)
- 문서 신설·50줄 이상 수정 → `scripts/check-doc-style.sh` 오류 0 + `doc-reviewer`
- 안 하기로 한 것 → `{{문서 루트}}/out-of-scope/README.md`에 이유와 함께
- 끝나면 `scripts/verify.sh`
