# GitHub Issues 트래커 씨앗

GitHub Issues를 쓰는 프로젝트에 하네스를 붙일 때 `init-harness`가 복사하는 트래커 안내다. 이 저장소(하네스 원본)에서 `gh` CLI로 이슈·PR을 다루며 검증했다.

## 무엇을 어디에 복사하나

| 파일 | 복사 위치 |
|---|---|
| `skills/local-track-issues/SKILL.md` | `.claude/skills/local-track-issues/SKILL.md` (이름 그대로) |

복사한 뒤 `harness-map.md`의 `{{이슈 연결}}`을 "GitHub Issues · 안내 `local-track-issues`"로 채운다.

## 씨앗 대조

복사 직후 저장소에서 확인할 전제다.

| 전제 | 확인 방법 |
|---|---|
| `gh`가 설치·인증돼 있다 | `gh auth status` |
| 연결 표기가 `Closes #n`이다 | PR 이력에서 이슈를 닫은 표기를 본다(`gh pr list --state merged --limit 20 --json body`) |
| 이슈 템플릿 유무 | `.github/ISSUE_TEMPLATE/` |
