# `git clean` 강제 삭제 차단

> 상태: Implemented (2026-09-07 감사 canonical task로 구현, 같은 날 사용자가 "전부 수정" 지시로 채택)
> MVP: In scope
> 관련 BR: N/A

## 목표

에이전트가 `git clean -f` 계열(추적되지 않은 파일을 되돌릴 수 없이 지우는 명령)을 실행하지 못하게 `deny-dangerous-bash.sh`가 결정론적으로 차단한다.

## 배경

- `docs/harness/component-map.md` "예시 — 훅 하나를 추가하는 순서"가 이 변경을 견본으로 들지만 실제 훅에는 반영돼 있지 않다
- `git clean -fdx`는 `rm -rf`와 같은 수준의 비가역 삭제인데 현재 통과한다(2026-09-07 실측: exit 0)

## 요구사항

### Must Have

- [ ] `git clean`에 `-f`가 포함된 플래그 묶음(`-f`·`-fd`·`-fdx`·`-xdf`·`-d -f`) 또는 `--force`가 있으면 exit 2
- [ ] `git clean -n`·`--dry-run`처럼 강제 플래그가 없으면 exit 0
- [ ] `scripts/hook-cases.txt`에 차단 5건·통과 2건 이상 추가
- [ ] `.claude/rules/README.md` Hooks 표와 `docs/harness/component-map.md` 훅 표의 해당 행 갱신

### Out of Scope (이번 스펙에서 하지 않음)

- `find -delete`·`git branch -D`·`git stash drop` 등 이번 감사에서 드러난 다른 미차단 명령 — 별도 스펙

## 불변 조건 (Invariant)

| 불변 조건 | 검증 방법 |
|---|---|
| 기존 훅 케이스 전부 통과 (오탐 증가 없음) | `scripts/test-hooks.sh` |
| 훅 공통 규약 유지 — 판정 불가·python3 부재 시 차단 | `scripts/test-hooks.sh` 내장 케이스 |
| 부품 계약·always-load 예산 유지 | `scripts/check-portability.sh` |

## 완료 기준

- [ ] `scripts/verify.sh` 통과
- [ ] 새 케이스 7건이 케이스 파일에 있고 전부 통과
- [ ] 변경 파일이 4개(훅·케이스·README·component-map)를 넘지 않는다

## 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-09-07 | 초안 (하네스 감사 canonical task) |
