# lang 팩·씨앗 제거 — 작업 보고서

스택별 규칙 묶음(lang 팩)과 그것을 복사해 주던 씨앗(`examples/seeds/`)을 지웠다. core 규칙이 프로젝트에 있을지 모르는 파일을 더는 가리키지 않고, 능력 플래그는 9개에서 3개로 줄었다. 매 요청에 실리는 규칙(always-load)은 24,918B에서 23,777B로 1,141B 줄었다. 스펙은 [`lang-pack-seed-removal.md`](../specs/cross-cutting/lang-pack-seed-removal.md)다.

## 무엇을 했나

플러그인 배달 스펙의 리스크 12(씨앗을 플러그인에 실을지)를 정하다가, 사용자가 씨앗과 lang 팩을 아예 빼기로 했다. 씨앗은 다른 프로젝트의 사본이라 붙일 때마다 전제를 대조해야 했고, 복사한 뒤에는 갱신되지 않았다.

| 영역 | 바꾼 것 |
|------|---------|
| 씨앗 | `examples/seeds/` 삭제. 트래커 안내 골격과 `dev.conf` 골격은 `.claude/skills/init-harness/references/`로 옮겨 스킬과 함께 배달한다. GitHub 트래커 안내는 배달하지 않는 채운 예 `examples/tracker-github/`로 옮겼다 |
| 능력 플래그 | `DB 마이그레이션 금지`·`에러 코드 카탈로그 동시갱신`·`권한 게이트·활동 기록 동시갱신`·`API 계약 보호`·`스택 함정 메모`·`스택 리뷰어`를 지웠다. 남은 것은 `생성 문서 검증`·`하네스 자기 수정`·`Gemini 다듬기` |
| core 규칙 6개 | "lang 팩" 참조를 "기존 코드를 따른다(있으면 `local-*.md`)"로 바꿨다. §1.6·§1.7은 괄호 안 참조만 지웠다 |
| 스킬·에이전트 | `init-harness`는 씨앗 복사·대조 단계를 지우고 골격을 실측으로 채운다. `verify-work` 7단계는 "프로젝트 리뷰어 에이전트가 있으면 부른다". `test-first`·`refactor-safely`·`researcher`·`test-writer`·스펙 템플릿의 참조를 바꿨다 |
| 검사기 | `check-portability.sh`·`test-hooks.sh`에서 씨앗 경로를 빼고, `portability-patterns.txt`의 C4(팩 참조) 분류와 씨앗 훅 케이스 10개를 지웠다 |
| 견본 | `AGENTS.template.md`의 lang 팩 줄, `.github/CONTRIBUTING.md`의 "계약 변경 사유 트레일러" 절(지운 플래그를 부르던 절), `examples/baro/harness-map.md`의 지운 플래그 행 |
| 다른 스펙 | 플러그인 배달 스펙 — 리스크 12 확정, 커밋 승인 창의 `CONTRACT_PATHS` 표시와 공통 포맷 훅 `auto-format.sh`를 Must에 더했다. v2 스펙·트래커 스펙 — 변경 이력 한 줄 |
| 문서 | `README.md`·`AGENTS.md`·`docs/README.md`·`docs/harness-engineering.md`·`docs/harness/README.md`(현재동작 요약)·`docs/out-of-scope/README.md`·`docs/templates/README.md` |

## 결정

| 결정 | 근거 | 대안 |
|------|------|------|
| 씨앗을 플러그인에 싣지 않고 지운다 | 사본이라 대조 비용이 들고, 복사한 뒤 갱신되지 않아 플러그인 자동 업데이트의 목적과 맞지 않는다(2026-10-29 사용자) | 플러그인에 `seeds/`로 싣기 — 모든 프로젝트가 안 쓰는 스택까지 받고 검사기를 고쳐야 한다 |
| lang 팩 개념도 지운다 | 코딩 관례는 "기존 코드를 따른다"와 프로젝트 층(`local-*.md`)이 맡는다. 플래그 본문은 §1.6·§1.7 문장과 플러그인 배달의 설정 값 훅이 맡는다(2026-10-29 사용자) | `_template` 골격만 남기고 실측으로 lang 규칙 쓰기 — 처음 붙일 때마다 토큰이 들고 검증이 덜 된 규칙이 된다 |
| 마이그레이션 쓰기는 차단 대신 승인 창 | 씨앗 훅의 차단 메시지도 "정말 필요하면 사용자에게 먼저 확인"이었다. 새 설정 키를 만들지 않고 플러그인 배달의 `ASK_PATHS`를 쓴다 | `DENY_PATHS` 신설 — 설정 키가 하나 늘어난다 |
| `.github/CONTRIBUTING.md` 트레일러 절 삭제 | 지운 "API 계약 보호" 플래그를 부르던 견본 절이다. 남기면 없는 플래그를 가리킨다(`core-guardrails.md` §2). 구현 중 찾아 스펙 REMOVED에 더했다 | 플래그 표시만 빼고 남기기 — 견본에 Java 프로젝트 관례가 남는다 |

## 검증

| 검증 | 실행한 명령 | 결과 |
|------|-------------|------|
| 전체 | `scripts/dev.sh test` | `dev test: 통과 — verify: 전부 통과` |
| 부품 계약·예산 | `scripts/check-portability.sh` | 위반 0 · 대조 위반 0 · always-load 23,777B / 상한 25,000B |
| 예산 기준선 | 변경 전 커밋(`3711656`)을 임시 작업 폴더로 꺼내 `scripts/check-portability.sh` | 24,918B |
| 훅 규약 | `scripts/test-hooks.sh` | 케이스 394 · 통과 394 · 실패 0. "건너뜀" 줄 없음 |
| 남은 언급 | `grep -rn "lang 팩\|스택 팩\|씨앗\|examples/seeds"`(`.claude`·`scripts`·`AGENTS*.md`·`README.md`·`docs/README.md`·`docs/harness`·`docs/templates`·`examples`·`.github`) | 0건 |
| 지운 플래그 이름 | 같은 범위에서 플래그 이름 6개 `grep` | `.claude/rules/README.md` "옛 모양 map 정리" 한 곳 — 재동기화 때 그 행들을 지우라는 안내라 의도한 것이다 |
| 별도 컨텍스트 리뷰 | `code-review` (low) | 지적 0건 |

## 검증하지 못한 것

| 무엇 | 왜 못 했나 | 누가·언제 확인하나 |
|------|-----------|-------------------|
| 새 프로젝트에서 `init-harness`가 `references/` 골격으로 트래커 안내와 `dev.conf`를 채우는가 | 스킬 실행은 다른 저장소에 붙여 봐야 확인된다 | 플러그인 배달 뒤 첫 프로젝트를 붙일 때 |
| baro-farm-be처럼 씨앗을 이미 복사한 프로젝트의 재동기화 | 그 저장소가 이 세션에 없다 | 그 프로젝트에서 `init-harness` 재동기화로 "옛 모양 map 정리"를 한 뒤 `scripts/dev.sh test` |

## 남은 것

- 마이그레이션 폴더·API 계약 파일 알림은 플러그인 배달 5단계(승인 창)가 들어올 때까지 없다. 그 사이 새 프로젝트를 붙일 계획이 없어 감수했다(스펙 리스크 3)
- 플러그인 배달 1단계(골격)부터 진행한다
