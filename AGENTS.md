# Superchaeyeons — Claude Code 하네스 템플릿

Claude Code용 **하네스**(규칙·스킬·훅·에이전트) 템플릿 저장소입니다. 새 프로젝트에 복사해 붙여 쓰는 것이 목적입니다.

이 저장소 자체에는 애플리케이션 코드가 없습니다. 여기서 하는 작업은 **하네스를 고치는 일**입니다.

## 무엇이 들어 있나

| 경로 | 내용 |
|------|------|
| `.claude/rules/harness-map.md` | **슬롯 SSOT** — 규칙이 부르는 `{{역할}}` → 프로젝트의 실제 경로·명령 |
| `.claude/rules/core-*.md` | 프로젝트 무관 규칙 8개 — 7개 always-load + `core-code-comments.md`(소스 파일 접근 시) |
| `examples/seeds/` | **씨앗** — 검증된 lang 팩(`java-spring/`)과 스택 무관 골격(`_template/`). `adopt`이 복사하거나 채운다. 배달물 아님 |
| `.claude/skills/` | `adopt` · `ask` · `specify` · `safe-refactor` · `debug` · `preflight` · `defer` · `retro` |
| `.claude/agents/` | `researcher`(G1) · `doc-reviewer`(G3). 스택 리뷰어는 씨앗 |
| `.claude/hooks/` | `deny-*` 3 · `warn-*` 1 · `ask-*` 1 — 스택 무관. 규약과 `settings.json` 등록은 `scripts/test-hooks.sh`가 판정 |
| `.claude/settings.json` | 훅 등록 + `permissions.deny`(훅과 이중) |
| `docs/harness/` | 하네스 4개 레이어 설명 (이 저장소 이력 — 배달 안 함) |
| `docs/out-of-scope/` | 검토 후 안 하기로 한 것과 이유 |
| `docs/harness-engineering.md` | 왜 이렇게 만들었는지 (긴 글) |
| `AGENTS.template.md` | 새 프로젝트가 채우는 `AGENTS.md` 견본 |
| `examples/tripfit/` | 실제 프로젝트(TripFit)에서 채운 모습 — **이 저장소의 규칙이 아님** |

## 새 프로젝트에 붙이는 순서

1. `.claude/` · `docs/templates/` · `scripts/` 복사 (`docs/harness/`·`harness-engineering.md`는 이 저장소의 이력이라 배달하지 않는다 — 새 프로젝트 `AGENTS.md`에서 이 저장소를 링크만). `.github/CONTRIBUTING.md`는 저장소 루트에 파일을 둘 수 있을 때만 — 못 두면 `{{Git 컨벤션 SSOT}}`를 `(없음)`으로 두고 `core-workflow.md` G2·G4가 그 역할을 한다
2. **`adopt` 스킬을 돌린다** — 하네스를 붙이는 유일한 경로다. 저장소를 실측해 축 4개 · 슬롯 22개 · 능력 플래그 7개를 **제안**하고, 승인 후 `harness-map.md`를 채우고, 스택에 맞는 씨앗(`examples/seeds/`)을 `local-*` 이름 그대로 복사해 실물과 대조하고, `AGENTS.template.md` → `AGENTS.md`를 만든다. 커밋·브랜치 형식은 기본값을 물려받지 않고 이력에서 실측한다. **`(없음)`·⬜가 이유 없이 남아 있으면 하네스는 절반만 작동한다**
3. 저장소 고유 사실이 `AGENTS.md`로 안 끝나면 `local-*.md`로 따로 만든다 (견본: `examples/tripfit/tripfit-release.md`)
4. `./scripts/install-git-hooks.sh`

## 이 저장소에서 작업할 때

- **슬롯을 늘리지 않는다** — `core-*.md`에서 실제로 `{{...}}`를 쓰는 곳이 있을 때만 `harness-map.md`에 행을 추가한다 (`harness-map.md` 규칙 3)
- **`core-*.md`에 프로젝트 고유 사실을 넣지 않는다** — 경로면 슬롯, 정책이면 능력 플래그, 둘 다 아니면 `local-*.md`
- **"완료·통과"를 말하기 전에 `scripts/verify.sh`를 돌린다** — 이 저장소의 `{{테스트 명령}}`이며 아래 검사기 3개를 한 번에 돌린다. Stop 훅이 이 명령의 실행 기록을 본다
- **`core-*.md`를 고쳤으면 `scripts/check-portability.sh`** — 고유명사·언어 식별자·경로 리터럴·팩 참조(C1~C4)와 always-load 예산을 exit code로 판정한다. `.claude/` 안의 `local-*` 파일은 검사하지 않는다. pre-commit도 같은 검사를 한다. 패턴은 `scripts/portability-patterns.txt`
- **문서를 새로 만들거나 크게 고쳤으면 `scripts/check-doc-style.sh <파일>`** — 개요 없음·H4·번역투는 오류, 긴 제목·약어는 경고. pre-commit이 stage된 `.md`에 같은 검사를 한다. 패턴은 `scripts/doc-style-patterns.txt`
- **훅을 고쳤거나 우회 경로를 발견했으면 `scripts/hook-cases.txt`에 케이스를 먼저 추가하고 `scripts/test-hooks.sh`** — 모든 `deny-*` 훅은 판정 불가 입력(python3 없음 포함)도 차단해야 한다(훅 공통 규약). pre-commit도 같은 테스트를 한다
- **씨앗 파일은 `local-*` 이름을 유지한다** — `examples/seeds/`의 규칙·에이전트·훅 파일명 접두사가 복사 뒤 검사기에 층을 알린다
- **`examples/`는 참고 자료다** — 여기 적힌 값을 규칙으로 삼지 않는다
- 커밋: `{Type}: {한글}` — 목적·주제별 **최대 5개**. **절대 마음대로 커밋하지 않는다** (`.github/CONTRIBUTING.md`)

## 출처

TripFit 백엔드(`Central-MakeUs/TripFit-server`)에서 2026-09-05 분리했습니다. 개명·관심사 분리 경위는 `docs/harness/layer1-human-gate.md` §4에 있습니다.
