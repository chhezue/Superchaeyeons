# 참조 자료 — 어디서 무엇을 가져왔나

이 하네스를 만들며 참고한 저장소·문서와, 각각에서 **차용한 것**과 **일부러 자른 것**의 목록이다. 새 장치를 제안하기 전에 이미 검토한 출처인지 확인하고, 라이선스가 걸린 출처(toss)는 원문을 옮기지 않는다는 조건을 여기서 다시 본다. 안 쓰기로 한 결정의 SSOT는 [`out-of-scope/README.md`](out-of-scope/README.md), 설계 경위는 [`specs/cross-cutting/harness-slot-system-v2.md`](specs/cross-cutting/harness-slot-system-v2.md) "외부 참조" 절이다 — 이 문서는 그 둘을 출처 기준으로 다시 묶은 색인이다.

## 언제 이 문서를 보는가

- 외부 도구·저장소를 참고해 규칙·스킬·훅을 바꾸려 할 때 — 이미 검토한 출처면 무엇을 왜 잘랐는지부터 본다
- "이 장치는 어디서 왔나"라는 질문을 받았을 때
- 참조 출처가 새로 생겼을 때 — 아래 표에 행을 추가한다 (출처 · 가져온 것 · 자른 것 · 반영 위치)

## 출처 저장소 — 하네스가 자란 곳

하네스는 실제 프로젝트 두 곳에서 굴리며 만들어졌다. 부품(`core-*`)은 여기서 나왔고, 두 곳의 차이가 축 4개(lang·shape·deploy·stage)의 근거가 됐다.

| 출처 | 기간 | 가져온 것 | 반영 위치 |
|------|------|-----------|-----------|
| [Central-MakeUs/TripFit-server](https://github.com/Central-MakeUs/TripFit-server) — Java·Spring 백엔드, 앱 클라이언트 | 2026-07 ~ 09 | 하네스 v1 전부 — STOP 규칙·4 게이트 워크플로·스킬 6개(`specify`·`safe-refactor`·`debug`·`preflight`·`defer`·`retro`)·에이전트(`researcher`·`doc-reviewer`·스택 리뷰어)·훅(위험 명령·마이그레이션 차단·계약 변경 경고·자동 포맷)·API 계약 3중 검증·레이어 4개 서술·인시던트 기록(agent-type 훅 사고, Redis 문서 드리프트, priority 오판) | `.claude/` 전부의 원형 · `examples/seeds/java-spring/`(스택 규칙·에이전트·훅) · `examples/tripfit/` · `docs/harness/` · `docs/harness-engineering.md` · `.github/CONTRIBUTING.md` 견본 |
| [dogs-team/baro-farm-be](https://github.com/dogs-team/baro-farm-be) — 모노레포 안의 Java 서비스 `baro-ai`, k8s, 외부 클라이언트 없음 | 2026-09 | v1을 옮겨 붙이자 파일 21개를 고쳐야 했다는 **실측** — 축 4개와 슬롯 v2(`{{문서 루트}}`·`{{작업 범위}}`·`{{Git 컨벤션 SSOT}}`·형식 슬롯)의 직접 근거. 거기서 고친 것 중 프로젝트와 무관한 개선은 아래 목록대로 회수했다 | `harness-map.md` 축·슬롯 표 · `examples/baro/` · 아래 목록의 각 위치 |

baro에서 **회수한 것** (프로젝트 사정과 무관한 개선만):

- 산출물 등록부와 toss 4유형 + 설명 유형 템플릿 → `docs/templates/`
- 훅 버그 2건 — `paths:` glob의 `**/` 누락, 저장소 밖 절대경로 오탐 → 규칙 frontmatter · `.claude/hooks/deny-out-of-scope-write.sh`(범위 슬롯 연동 일반형)
- 감사 문서 `{NNN}-{topic}` 네이밍 → `safe-refactor` 스킬
- 에이전트 `tools` 화이트리스트가 `Bash`로 우회된다는 경고 → `researcher`·`doc-reviewer` 머리
- 씨앗 대조 표 — 검증 없이 물려받은 전제로 같은 실수를 세 번 한 사례 → `examples/seeds/java-spring/README.md`
- 회고 8건 → 훅 공통 규약(판정 불가 = 차단)·`scripts/test-hooks.sh`·`report.md` "검증하지 못한 것" 절
- 코드 주석 원칙(실행 줄 위 단계 주석·필드 해설·실물 대조·이유) → `.claude/rules/core-code-comments.md`

baro에서 **가져오지 않은 것:** baro 고유 규칙(`local-baro-ai-performance-refactor.md`, 검색 엔진·AI 라이브러리 버전)은 `local-` 층 예시로만 남겼고, 규칙 파일 분리 4건은 같은 `paths:` glob이라 토큰 효과가 없어 회수하지 않았다.

## 참조한 저장소·문서 — 설계에 차용한 것

2026-09-05 v2 설계 전에 읽은 것들이다. 가져올 때의 잣대는 부품성 원칙 3조(장치 하나는 bash 하나 + 데이터 파일 하나 · 새 개념은 기존 개념을 대체해야 함 · 스택에 묶이는 것은 팩으로)였다.

| 출처 | 가져온 것 | 자른 것과 이유 | 반영 위치 |
|------|-----------|----------------|-----------|
| [mattpocock/skills](https://github.com/mattpocock/skills) | **라운드·프론티어 인터뷰**(지금 답할 수 있는 질문만 한 라운드에) · **사실/결정 분리**(환경이 답할 수 있는 건 묻지 않는다) · `.out-of-scope/`(안 하기로 한 것을 이유와 함께 파일로) · 스킬 문서 프레임(첫 줄 "기본 동작과 다른 단 하나", 끝에 "It's working if") · 라우터 갱신 강제(스킬을 추가·삭제하면 같은 턴에 라우터 표 갱신) | 버킷 5개·promoted 개념 — 이 저장소의 스킬 수(8)에는 층이 하나면 충분. 플러그인 마켓플레이스 매니페스트 — 복사로 배달하므로 불필요 | `.claude/skills/ask/` · `docs/out-of-scope/` · 모든 `SKILL.md`의 머리·꼬리 · `.claude/rules/README.md` 유지보수 체크리스트 |
| [Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) | **`Stop` 훅으로 워크플로 이탈 감지** → 코드 수정 후 테스트 없이 완료 선언을 되돌리는 `deny-unverified-completion.sh` · 규칙 주입 방식(검토 후 `paths:` frontmatter로 대체) · **의존성 사다리**(표준 라이브러리 → 플랫폼 → 설치된 의존성 → 직접 작성) | 훅 이벤트 11종 + Node 스크립트 20여 개(별도 런타임 전제 — 부품성 원칙 1) · 모호성 점수 게이팅(점수 기준이 자의적, 라운드 인터뷰로 대체) · 산출물 검증 훅(에이전트가 파일을 안 만듦) · 스킬 30여 개 배달(카탈로그는 완성되지 않는다) | `.claude/hooks/deny-unverified-completion.sh` · `core-gates.md` 의존성 사다리 · `docs/out-of-scope/` 4행 |
| [obra/superpowers](https://github.com/obra/superpowers) | 직접 가져온 장치는 없다. `brainstorming`·`writing-plans`·`systematic-debugging`이 무엇을 해결하려는지를 보고 **같은 자리를 Claude Code 기본 기능과 자체 스킬로 채웠다** — Plan Mode + `ask`·`specify`가 계획을, `debug` 스킬이 systematic-debugging을 대체. "기능이 있다는 이유만으로 쓰지 않는다"는 도구 채택 기준의 계기 | 플러그인 설치 자체 — 설치본은 수정할 수 없고 영어이며, 전면 TDD(Test-Driven Development, 테스트 선행 개발) 원칙이 이 하네스의 "유의미한 테스트만"과 충돌. 2026-07-23 감사, 2026-09-05 재확인 | `core-tools.md` 도구 우선순위·채택 기준 · `.claude/skills/debug/` · `docs/out-of-scope/` 1행 |
| [toss/technical-writing](https://github.com/toss/technical-writing) (CC BY-NC-SA 4.0) | 문서 유형 4개(학습·문제 해결·참조·설명)와 유형별 필수 섹션 · 정보 구조 원칙(H1 아래 개요, 가치 먼저, H4면 분할, 검색 가능한 제목) · 문장 원칙(한 문장 한 생각, 주체, 명사 대신 동사, 번역투·한자어, 메타 담화) | **원문 문장** — 라이선스가 저장소로 전염되므로 원칙과 구조만 재작성. `doc-writing.md`·템플릿·패턴 파일 어디에도 원문을 옮기지 않는다 | `.claude/rules/doc-writing.md` · `docs/templates/*.md` · `scripts/doc-style-patterns.txt` · `.claude/agents/doc-reviewer.md` |
| 하네스 가이드 문서 (PDF, 파일명 `AI_Harness_Guide`) — 저자·URL `[미정]`: 원본 출처가 기록돼 있지 않다. 아는 사람이 이 칸을 채운다 | **통제/위임 영역 분리**(멈추는 근거를 표현이 아니라 변경이 닿는 영역에 둠) · **Invariant**(완료 기준과 다른 "작업 내내 참인 조건") · 실행 환경 검증(`preflight` 사전 모드) · `report.md`(무엇을·어떤 결정·**검증하지 못한 것**) · 워크플로 12단계 커버리지 대조 · 리서치 → 리뷰 → 정책 승격(handover)은 `specify` Draft → Approved로 흡수 · "안정화된 도구 위에 자기 하네스를 쌓는다"는 채택 기준 | 흐름 팩·스타일 팩을 별도 플러그인으로 쪼개는 구성(4축과 목적이 겹침) · Facade·멀티모듈 아키텍처 권고(core가 아니라 씨앗 후보) · `ship` 자동 배송 스킬과 AI 서명 차단 훅(이 저장소의 Stop & Ask·`Co-Authored-By` 정책과 반대) · 하네스를 코드와 분리된 별도 저장소로 두는 방식(배달 방식 `[미정]`으로 보류) | `core-gates.md` §1·§2 · `core-workflow.md` G2 불변 조건 · `.claude/skills/preflight/` 사전 모드 · `docs/reports/` · v2 스펙 §17 |
| [Claude Code 훅 문서](https://code.claude.com/docs/en/hooks) | 훅 이벤트별로 할 수 있는 것 — `UserPromptSubmit`은 차단과 컨텍스트 주입 둘 다, `Stop`은 exit 2로 턴 종료 저지, `SessionStart`는 주입만. 이 확인이 훅 3개(`ask-open-request`·`deny-unverified-completion`·`warn-unfilled-map`)의 강도(주입/차단/경고)를 정했다 | — | `.claude/settings.json` · 훅 3개 머리 주석 |

**검토했지만 참조하지 않은 것:** `read4ai` — 2026-09-05 조사에서 하네스가 아님을 확인하고 제외했다.

**도구:** 레이어 다이어그램은 [Eraser.io](https://app.eraser.io/)로 그렸다(`docs/harness/architecture-diagrams.md`). 참조 지식이 아니라 그림 도구다.

## 관련 문서

- [`out-of-scope/README.md`](out-of-scope/README.md) — 위 "자른 것"의 결정 SSOT (다시 볼 조건 포함)
- [`specs/cross-cutting/harness-slot-system-v2.md`](specs/cross-cutting/harness-slot-system-v2.md) "외부 참조"·"부품성 원칙" — 무엇을 어떤 잣대로 가져왔는지의 원 기록
- [`harness-engineering.md`](harness-engineering.md) §12 — 외부 도구 채택 기준의 첫 적용(2026-07-23)
- [`.claude/rules/core-tools.md`](../.claude/rules/core-tools.md) "도구 우선순위" — 서드파티 채택·배제 조건
