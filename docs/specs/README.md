# Specs — 기능 설계

`specify` 스킬이 만드는 기능 스펙을 도메인 폴더로 나눠 둔다. 이 폴더가 `{{스펙 저장소}}` 슬롯의 기본값이다.

- 파일명: kebab-case, 한 파일 = 한 기능 또는 한 리팩터 단위
- 템플릿: [`.claude/skills/specify/references/spec-template.md`](../../.claude/skills/specify/references/spec-template.md)
- 상태: `Draft` → `Approved` → `Implemented`

## 도메인 폴더 ↔ 코드 패키지

프로젝트를 붙일 때 아래 표를 채운다. 두 도메인에 걸치는 스펙은 **주로 바뀌는 상태가 속한 도메인**에 둔다.

| 폴더 | 코드 패키지 |
|------|-------------|
| `cross-cutting/` | (도메인 무관) |
