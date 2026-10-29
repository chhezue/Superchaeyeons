# GitHub Issues 트래커 안내 — 채운 예

GitHub Issues를 쓰는 프로젝트의 트래커 안내 `local-track-issues`를 채운 예다. 이 저장소(하네스 원본)에서 `gh` CLI로 이슈·PR을 다루며 검증했다. 배달하지 않는 참고 자료다 — 붙이는 프로젝트에서는 `init-harness`가 스킬 폴더의 골격(`references/track-issues-skeleton.md`)을 실측으로 채운다.

## 이 예를 볼 때 확인할 전제

이 예를 본떠 채울 때 그 저장소에서 확인할 전제다.

| 전제 | 확인 방법 |
|---|---|
| `gh`가 설치·인증돼 있다 | `gh auth status` |
| 연결 표기가 `Closes #n`이다 | PR 이력에서 이슈를 닫은 표기를 본다(`gh pr list --state merged --limit 20 --json body`) |
| 이슈 템플릿 유무 | `.github/ISSUE_TEMPLATE/` |
