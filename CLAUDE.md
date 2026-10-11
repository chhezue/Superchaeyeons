@AGENTS.md

## Claude Code 보충

이 파일은 `AGENTS.md`(프로젝트 지도)를 그대로 불러온다. `AGENTS.md`는 CLAUDE.md 전용이 아니라 다른 코딩 에이전트와도 공유하는 캐노니컬 문서이므로, Claude Code 전용 세부사항은 아래와 `.claude/`에 둔다.

- **슬롯(map):** `.claude/rules/harness-map.md` — 규칙이 부르는 `{{역할}}` → 이 프로젝트의 실제 경로·명령. **새 프로젝트에 붙일 때 채우는 건 이 파일 하나다**
- **행동 규칙(rules):** `.claude/rules/` — `core-guardrails.md`(⛔ STOP)·`core-gates.md`(멈추는 신호) 등 always-load 규칙 7개 + `paths:` frontmatter로 파일 접근 시에만 로드되는 규칙(`core-code-comments.md`, `doc-writing.md`, 복사한 lang 팩). 구조: [`.claude/rules/README.md`](.claude/rules/README.md)
- **스킬(skills):** `.claude/skills/` — `adopt`(하네스 붙이기) · `ask`(열린 요청 인터뷰) · `specify`(스펙 승인 게이트) · `safe-refactor` · `debug` · `preflight` · `defer` · `retro`
- **훅(hooks):** `.claude/settings.json`이 스택 무관 훅 5개(`deny-dangerous-bash`·`deny-out-of-scope-write`·`deny-unverified-completion`·`ask-open-request`·`warn-unfilled-map`)를 등록한다. 스택 훅은 씨앗(`examples/seeds/`)에 있고 `adopt`이 플래그에 따라 복사한다 — 목록·역할은 [`.claude/rules/README.md`](.claude/rules/README.md) Hooks 표가 SSOT, 규약은 `scripts/test-hooks.sh`가 판정
- **권한(permissions):** `.claude/settings.local.json` — 자주 쓰는 안전한 명령 allowlist
- **견본(examples):** `examples/tripfit/` — 실제 프로젝트에서 슬롯·옵션을 어떻게 채웠는지 보여주는 참고용. 이 저장소의 규칙이 아니다
