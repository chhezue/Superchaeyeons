# Superchaeyeons — Claude Code 하네스 템플릿

Claude Code용 **하네스**(규칙·스킬·훅·에이전트) 템플릿 저장소입니다. 새 프로젝트에 복사해 붙여 쓰는 것이 목적입니다.

이 저장소 자체에는 애플리케이션 코드가 없습니다. 여기서 하는 작업은 **하네스를 고치는 일**입니다.

## 무엇이 들어 있나

| 경로 | 내용 |
|------|------|
| `.claude/rules/harness-map.md` | **슬롯 SSOT** — 규칙이 부르는 `{{역할}}` → 프로젝트의 실제 경로·명령 |
| `.claude/rules/core-*.md` | 프로젝트 무관 규칙 6개 (always-load) |
| `.claude/rules/{스택 팩}` | Java·Spring 전용 규칙 6개 + `README.md` (`paths:` 스코프) |
| `.claude/skills/` | `specify` · `safe-refactor` · `debug` · `preflight` · `defer` · `retro` |
| `.claude/agents/` | `researcher`(G1) · `doc-reviewer`(G3) · `spring-reviewer`(G3, 스택 팩) |
| `.claude/hooks/` | `deny-*` 2개(차단) · `warn-*` 1개(경고) · `auto-*` 1개(자동) |
| `docs/harness/` | 하네스 4개 레이어 설명 |
| `docs/harness-engineering.md` | 왜 이렇게 만들었는지 (긴 글) |
| `AGENTS.template.md` | 새 프로젝트가 채우는 `AGENTS.md` 견본 |
| `examples/tripfit/` | 실제 프로젝트(TripFit)에서 채운 모습 — **이 저장소의 규칙이 아님** |

## 새 프로젝트에 붙이는 순서

1. `.claude/` · `docs/harness/` · `docs/templates/` · `.github/CONTRIBUTING.md` · `scripts/` 복사
2. `.claude/rules/harness-map.md` — 경로 슬롯 13개 + 명령 슬롯 4개 + 스택 옵션 7개를 채운다. **`(없음)`·⬜가 남아 있으면 하네스는 절반만 작동한다**
3. `AGENTS.template.md` → `AGENTS.md`로 복사해 채운다
4. 안 쓰는 스택 팩은 **파일째 삭제** (`harness-map.md` 스택 팩 표)
5. 저장소 고유 사실이 있으면 `{프로젝트}-release.md`로 따로 만든다 (견본: `examples/tripfit/tripfit-release.md`)
6. `./scripts/install-git-hooks.sh`

## 이 저장소에서 작업할 때

- **슬롯을 늘리지 않는다** — `core-*.md`에서 실제로 `{{...}}`를 쓰는 곳이 있을 때만 `harness-map.md`에 행을 추가한다 (`harness-map.md` 규칙 3)
- **`core-*.md`에 프로젝트 고유 사실을 넣지 않는다** — 경로면 슬롯, 정책이면 스택 옵션, 둘 다 아니면 `{프로젝트}-release.md`
- **`examples/`는 참고 자료다** — 여기 적힌 값을 규칙으로 삼지 않는다
- 커밋: `{Type}: {한글}` — 목적·주제별 **최대 5개**. **절대 마음대로 커밋하지 않는다** (`.github/CONTRIBUTING.md`)

## 출처

TripFit 백엔드(`Central-MakeUs/TripFit-server`)에서 2026-09-05 분리했습니다. 개명·관심사 분리 경위는 `docs/harness/layer1-human-gate.md` §4에 있습니다.
