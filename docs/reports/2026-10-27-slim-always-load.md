# always-load 규칙 줄이기 — 작업 보고서

매 요청에 항상 실리는 규칙(always-load)을 27,960B에서 24,460B로 3,500B(약 1,400토큰) 줄이고, 예산 상한을 28,000B에서 25,000B로 낮췄다. 내용은 지우지 않고 필요할 때만 실리는 곳으로 옮겼고, `core-guardrails.md`는 규칙을 그대로 두고 예시 문장만 줄였다.

## 무엇을 했나

하네스를 붙인 백엔드 저장소에서는 그 저장소의 `AGENTS.md`·map까지 합친 always-load가 상한에 61B 앞까지 차서 프로젝트 `AGENTS.md`에 한 줄도 더 쓸 수 없었다. 파일별로 아래처럼 바꿨다.

| 파일 | 전 | 후 | 무엇을 옮겼나 |
|------|----|----|---------------|
| `core-workflow.md` | 7,365B | 6,223B | G4 상세(분할 기준·중간 커밋 테스트·PR 체크리스트·L 보고서·후속 제안·`retro`·refactor-log·브랜치 정리) → `preflight` "마무리" 절. G3에서 `preflight` 7·8단계와 겹치는 bullet 두 개를 본문 한 문장으로 |
| `harness-map.md` | 6,369B | 4,673B | 값이 아닌 설명(옛 map 규칙 1·3·4·5, 축·명령 슬롯·스택 팩 표 앞의 작성 안내, 훅 상수 짝 목록, 플래그 표 "켜거나 끌 때 할 일" 열) → `.claude/rules/README.md` "harness-map.md 고치기" |
| `core-guardrails.md` | 5,512B | 4,850B | 예시 나열(문서 쌍·삭제 대상·민감 로직 종류·훅이 막는 명령)을 줄이고, map과 겹치던 ☑/❌/⬜ 판정 설명을 map 한 곳으로 |
| `core-gates.md` · `core-reporting.md` | 4,024B · 1,560B | 그대로 | 다른 세션이 고치는 중이라 건드리지 않았다 |
| `CLAUDE.md` · `AGENTS.md` | 462B · 2,668B | 그대로 | — |
| **합계** | **27,960B** | **24,460B** | 상한 28,000B → 25,000B |

함께 고친 곳:

- `.claude/rules/README.md` — `paths:`에 `.claude/rules/harness-map.md`·`scripts/git-hooks/**`를 더해 map이나 git 훅을 열 때도 실리게 했다. 목록 줄(README·`preflight`)과 3층 표의 "훅 상수와 짝" 위치를 고쳤다
- `preflight` — "마무리" 절 신설, When to Use에 마무리 시점, 8단계에 L 리뷰 이유를 옮겼다
- 참조 갱신 — `adopt`(map 규칙 5·훅 상수 짝 위치, 재동기화 때 옛 모양 map 정리 제안), `retro`·`specify`·`templates/reference-doc.md`(후속 제안 형식 위치), `check-portability.sh` 주석 3곳
- 기록 — `check-portability.sh` 머리 주석 이력, `harness-engineering.md` 예산 문단·인시던트 표·숫자, `docs/harness/README.md` G4 행

## 결정

| 결정 | 근거 | 대안 |
|------|------|------|
| 진행 범위는 후보 1·1b·2·3 전부, 상한은 실측 + 약 500B | 사용자가 판단을 맡겼다 (2026-10-27 "알아서 최선으로") | 범위를 일부만 — 절감이 1,000B대에 그친다 |
| G4 상세는 새 스킬이 아니라 `preflight`로 | `preflight` 사후 모드가 이미 완료 보고 바로 앞에서 불린다. 새 구성 요소를 늘리지 않는다(새 개념은 기존 개념을 대체할 때만) | 새 스킬 — 스킬 설명이 매번 실리고 목록·트랙 표가 늘어난다 |
| G4에는 커밋 분할안·승인 뒤 커밋·이슈·브랜치·PR 확인·규칙 제안·Git 슬롯 4개를 남긴다 | S 규모는 `preflight`를 1단계만 쓰므로 S에도 필요한 규칙은 항상 실려야 한다. `{{Git 컨벤션 SSOT}}`가 `(없음)`이면 G2·G4가 Git 규칙의 기준이라 슬롯이 남아야 한다 | 전부 옮기기 — S 커밋에서 분할안 규칙이 빠진다 |
| map 설명은 별도 파일이 아니라 기존 `.claude/rules/README.md`로 | 이미 path-scoped인 유지보수 문서다. 설명이 core 층으로 와서, 프로젝트가 소유하는 map과 달리 하네스 개선이 붙인 프로젝트에도 전파된다 | 새 path-scoped 파일 — 구성 요소가 하나 늘고 3층 표에 map 층 파일이 둘이 된다 |
| 옛 map 규칙 2(`(없음)` 슬롯이면 멈추기)와 ☑/❌/⬜ 판정은 map에 남긴다 | 매 작업 중에 쓰는 행동 규칙이다 | 옮기기 — README가 실리지 않은 작업에서 판정 근거가 사라진다 |
| 상한 25,000B | 실측 24,460B + 540B. 다른 세션이 `core-gates.md`·`core-reporting.md`를 조금 늘려도 버틴다 | 실측 그대로 — 병행 세션 변경이 1바이트만 늘어도 실패 |

`docs/out-of-scope/README.md`의 "규칙 파일 분리 4건"은 나뉜 두 파일이 같은 조건에서 실려 효과가 없어서 기각됐다. 이번에는 옮겨 간 곳(스킬 본문·path-scoped README)의 로드 조건이 always-load와 달라 그 사유에 해당하지 않는다.

## 검증

| 검증 | 실행한 명령 | 결과 |
|------|-------------|------|
| 전체 | `scripts/dev.sh test` | `dev test: 통과 — verify: 전부 통과` |
| 예산·슬롯 대조·구성 요소 목록 | `scripts/check-portability.sh` | 위반 0 · 대조 위반 0 · always-load 24,460B / 상한 25,000B |
| 옮긴 문장 누락 | 옛 G4·G3·map 문장 20개를 grep으로 새 위치에서 확인 | 20개 전부 `preflight` 또는 README에 있음 |

## 검증하지 못한 것

| 무엇 | 왜 못 했나 | 누가·언제 확인하나 |
|------|-----------|-------------------|
| `harness-map.md`를 열면 README가 실제로 함께 실리는가 | `paths:` 로드는 Claude Code 런타임 동작이라 이 저장소의 검사기로 판정할 수 없다. 기존 path-scoped 규칙과 같은 방식이다 | 다음 세션에서 map을 Read한 뒤 README 내용이 컨텍스트에 있는지 확인 |
| 이미 붙인 프로젝트가 core만 갱신했을 때 | 그 프로젝트의 map은 옛 모양이라 map 설명 약 1,700B가 남는다. 추정 합계 약 26,100B로 새 상한 25,000B를 넘는다 | 그 프로젝트에서 `adopt` 재동기화로 "옛 모양 map 정리"를 한 뒤 `scripts/dev.sh test` |
| 병행 세션과 합쳤을 때의 합계 | `core-gates.md`·`core-reporting.md`를 다른 세션이 고치는 중이다 | 두 브랜치를 합친 뒤 `scripts/check-portability.sh` |

## 남은 것

- 이미 붙인 프로젝트의 map 정리 — README "옛 모양 map 정리" 절차대로
- `check-portability.sh`의 "2026-10-16 … 사본에 붙였을 때" 주석과 `harness-engineering.md` 인시던트 표에 특정 프로젝트 이름이 남아 있다. 이번 범위 밖이라 그대로 뒀다
