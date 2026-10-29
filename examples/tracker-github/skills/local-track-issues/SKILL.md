---
name: track-issues
description: 이 프로젝트의 이슈 트래커(GitHub Issues)를 다룰 때 사용 — 이슈에서 범위·완료 기준 확인, 이슈 만들기·고치기·댓글, 브랜치·커밋·PR에 이슈 연결. 다루는 수단·이슈 키·연결 표기의 SSOT.
---

# 트래커 안내 — GitHub Issues

이 프로젝트에서 이슈를 확인하고 만들고 연결하는 법이다. `harness-map.md`의 `{{이슈 연결}}`이 이 스킬을 가리키고, core 규칙·스킬은 트래커를 모른 채 이 안내를 따른다. 원칙(만들기 전에 확인·라벨 부여 금지)은 core가 갖고, 여기는 이 트래커의 방법만 적는다.

## 다루는 수단

GitHub CLI(명령줄 도구) `gh`를 쓴다. 인증 상태는 `gh auth status`로 본다. 인증이 안 돼 있으면 멈추고 사용자에게 알린다 — 에이전트가 로그인하지 않는다.

## 이슈 키와 연결 표기

| 자리 | 표기 | 예 |
|---|---|---|
| 이슈 키 | `#` + 번호 | `#12` |
| 브랜치 이름 | `{{브랜치명 형식}}`의 `{issue-number}` 자리에 번호만 | `docs/12-tracker-guide` |
| PR 본문 | `Closes #n` — 합치면 이슈가 닫힌다 | `Closes #12` |

## 이슈 읽기

- 본문과 댓글: `gh issue view <번호> --comments`
- 완료 기준은 본문의 체크리스트와 "완료 기준" 절이다. 댓글에서 범위가 바뀌었으면 그쪽이 최신이다

## 이슈 만들기·고치기·댓글

- 만들기 전에 사용자에게 확인한다(`core-workflow.md` G4). 라벨·마일스톤은 붙이지 않는다(`core-guardrails.md` §1.8)
- 만들기: `gh issue create --title "<제목>" --body-file <본문 파일>`. 저장소에 `.github/ISSUE_TEMPLATE/`이 있으면 그 순서를 따른다
- 댓글: `gh issue comment <번호> --body-file <본문 파일>`
- 고치기: `gh issue edit <번호> --title … --body-file …`

## 글 다듬기

"Gemini 다듬기" 플래그가 ☑이면 적용된다(`harness-map.md`).

- 이슈·PR 제목과 본문, 댓글은 만들기 전에 `scripts/polish-with-gemini.sh message`로 다듬는다. 원문과 대조해 틀린 곳만 고친 뒤 그 글로 만든다
- 입력은 `{"kind": "issue" 또는 "pr", "fields": {"title": …, "body": …}}` JSON이고, 출력의 `fields`가 다듬은 글이다. 실패하면 원문으로 만든다
