# Layer 3 — 훅 (LLM 판단 없는 강제 통제)

에이전트의 판단을 거치지 않고 shell 스크립트의 exit code로 도구 호출을 막거나 되돌리는 훅을 설명한다. 읽고 나면 어떤 훅이 언제 발동하는지, 왜 어떤 훅은 막고 어떤 훅은 경고만 하는지, 훅이 막은 것을 어떻게 푸는지 알 수 있다.

> 분류: **hook** (`.claude/settings.json` + `.claude/hooks/*.sh`) · 강제 수단: **shell exit code** · 현행 목록 SSOT: [`.claude/rules/README.md`](../../.claude/rules/README.md) Hooks 절

## 훅 레이어 소개

**훅**은 Claude Code가 특정 이벤트(도구 호출 직전, 프롬프트 제출, 턴 종료, 세션 시작)에 실행하는 스크립트다. exit 2를 돌려주면 그 동작이 막히거나 되돌려진다. [Layer 1 규칙](layer1-human-gate.md)과 [Layer 2 스킬](layer2-workflow-skills.md)은 에이전트가 읽고 따라줘야 작동하지만, 훅은 에이전트가 무엇을 믿든 똑같이 동작한다.

핵심 설계 명제: **판단이 필요한 곳엔 LLM을, 항상 똑같이 동작해야 하는 곳엔 스크립트를.**

## 등장 배경

되돌리기 어려운 명령(강제 푸시, 폴더 통째 삭제)은 "규칙에 금지라고 적었다"로 충분하지 않다. 한 번 통과하면 복구 비용이 크다. 테스트 없이 "완료"라고 말하는 것도 규칙과 스킬로 여러 번 금지했지만, 막는 장치가 없으면 결국 반복된다. 그래서 exit code로 판정 가능한 것만 골라 훅으로 내렸다.

## 훅 목록

| 훅 | 이벤트 · 매처 | 동작 |
|---|---|---|
| [`deny-dangerous-bash.sh`](../../.claude/hooks/deny-dangerous-bash.sh) | `PreToolUse` · `Bash` | **exit 2 (차단)** — 파괴·우회·시크릿 명령 |
| [`deny-out-of-scope-write.sh`](../../.claude/hooks/deny-out-of-scope-write.sh) | `PreToolUse` · `Write\|Edit` | **exit 2 (차단)** — 하네스 자기 수정(플래그 ❌일 때) · `{{작업 범위}}` 밖 쓰기 |
| [`ask-open-request.sh`](../../.claude/hooks/ask-open-request.sh) | `UserPromptSubmit` | **항상 exit 0** — 열린 요청이면 `ask` 알림 주입 |
| [`deny-unverified-completion.sh`](../../.claude/hooks/deny-unverified-completion.sh) | `Stop` | **exit 2 (되돌림)** — 파일을 고치고 검증 명령을 안 돌렸거나 실패했는데 완료 단정 |
| [`warn-unfilled-map.sh`](../../.claude/hooks/warn-unfilled-map.sh) | `SessionStart` | **항상 exit 0** — `harness-map.md` 미결정 칸 경고 |
| `local-deny-db-migration.sh` (씨앗) | `PreToolUse` · `Write\|Edit` | **exit 2** — **[플래그: DB 마이그레이션 금지]** ☑일 때만 복사·등록 |
| `local-warn-breaking-change.sh` (씨앗) | `PreToolUse` · `Bash` | **항상 exit 0** — **[플래그: API 계약 보호]** ☑일 때만 |
| `local-auto-format-java.sh` (씨앗) | `PostToolUse` · `Edit\|Write` | **항상 exit 0** — `{{포맷 명령}}`이 있을 때만 |

배달물에 등록된 훅은 위 다섯 개이고 전부 스택 무관이다. 씨앗 훅 세 개는 [`examples/seeds/java-spring/hooks/`](../../examples/seeds/java-spring/hooks/)에 있고, `adopt`이 플래그를 보고 복사·등록한다.

**파일명이 강도를 말한다.** 차단은 `deny-`, 경고는 `warn-`, 질문 유도는 `ask-`, 자동 실행은 `auto-`. 그 훅이 커밋을 막는지 도와주기만 하는지를 파일명만 보고 안다.

## 훅 공통 규약

모든 훅은 stdin으로 JSON을 받고, 필요한 필드만 `python3`로 뽑는다. 규약은 [`scripts/test-hooks.sh`](../../scripts/test-hooks.sh)가 [`scripts/hook-cases.txt`](../../scripts/hook-cases.txt)로 판정한다.

- `deny-*`는 정상이면 exit 0, 위반이면 exit 2, **판정 불가(JSON 깨짐·키 없음·빈 입력·python3 없음)도 exit 2**다. 판정을 못 했다고 통과시키면 입력을 망가뜨리는 것이 우회 경로가 된다.
- 경로는 실경로로 정규화한다. `../`나 심볼릭 링크로 범위를 빠져나가지 못하게 하려는 것이다.
- `Stop` 훅만 판정 불가면 통과한다. 대화가 끝나지 못하는 피해가 더 크기 때문이다.
- `.claude/hooks/*.sh` 전부가 `settings.json`에 등록돼 있고 경로가 실존·실행 가능한지도 같은 테스트가 대조한다.

## 흐름 — 도구 호출 직전

```text
에이전트가 Bash 도구 호출
  ↓
deny-dangerous-bash.sh
  tool_input.command 를 PATTERNS 배열과 대조
  force push(플래그 위치 무관·+refspec·--force-with-lease) · rm -rf(플래그 조합 무관)
  · find -delete · git reset --hard · clean -f · branch -D · stash drop · filter-branch
  · git commit --no-verify · .env add/commit · SQL DROP · 컨테이너 볼륨 삭제
  · curl|sh · chmod -R 777 · dd of=/dev
  매칭 → stderr에 사유 + exit 2 → 명령 실행 안 됨

에이전트가 Write 또는 Edit 도구 호출
  ↓
deny-out-of-scope-write.sh
  file_path 를 실경로로 정규화
  (1) HARNESS_SELF_EDIT=0 이고 .claude/hooks/ · settings.json 이면 → exit 2
  (2) SCOPE/ 와 .claude/ 밖이면 → exit 2   (SCOPE=. 이면 이 검사 생략)
  저장소 밖 절대경로(세션 파일)는 통과
```

`deny-dangerous-bash.sh`는 명령 문자열 전체에서 패턴을 찾는다. 그래서 `grep 'rm -rf'`처럼 문자열로만 언급해도 막힌다. 놓치는 것보다 오탐이 싸다고 보고 그대로 둔다. 반대로 변수·`eval`·별도 스크립트로 감싼 간접 실행은 못 본다 — 그건 규칙으로만 금지한다.

같은 차단 항목을 `settings.json` `permissions.deny`에도 넣었다. 훅은 문자열을 보는 하한선이고, 권한 규칙은 도구 호출 자체를 막는다. 두 층에 두면 한쪽이 놓친 것을 다른 쪽이 잡는다.

## 흐름 — 턴 종료

```text
에이전트가 응답을 끝내려 함
  ↓
deny-unverified-completion.sh
  transcript 에서 마지막 사용자 메시지 이후를 본다
  (a) 문서가 아닌 파일을 고쳤는가 — Write/Edit + Bash sed -i · > · >> · tee
  (b) 마지막 편집 "뒤에" TEST_CMD 를 명령으로 실행했는가, 결과가 성공인가
  (c) 마지막 텍스트가 완료를 단정하는가 ("완료·통과·반영했" 등, 부정형 제외)
  (a) ∧ ¬(b) ∧ (c) → exit 2 → 에이전트에게 되돌아감 (미실행·실패 메시지 구분)
  stop_hook_active 면 통과 — 한 번만 되돌려 무한 루프를 막는다
```

이 훅이 G3(검증 게이트)를 처음으로 결정론적으로 강제한 장치다. `TEST_CMD`는 `{{테스트 명령}}` 슬롯 값이고, 이 저장소에서는 `scripts/verify.sh`다.

## fail-closed와 fail-open

차단 강도는 일부러 비대칭이다. 기준은 되돌리기 비용이다.

| 훅 | 판정 불가·오류 시 | 이유 |
|---|---|---|
| `deny-dangerous-bash.sh` · `deny-out-of-scope-write.sh` | **막는다** | 오탐으로 한 번 막히는 비용 < 파괴 명령이 한 번 통과하는 비용 |
| `deny-unverified-completion.sh` | **통과** | 대화가 끝나지 못하는 피해가 크다 |
| `ask-open-request.sh` · `warn-unfilled-map.sh` | **통과** | 주입만 한다. `UserPromptSubmit`에서 막으면 사용자 프롬프트가 지워진다 |
| `local-warn-breaking-change.sh` (씨앗) | **통과** | 계약 변경은 막을 일이 아니라 알릴 일이다 |
| `local-auto-format-java.sh` (씨앗) | **통과** | 포맷 실패로 작업을 막을 이유가 없다 |

**advisory 훅은 `command`-type으로 만든다.** 서브에이전트가 판단하는 `agent`-type 훅은 "절대 막지 마라"는 지시에도 커밋을 막은 사고가 있었다. "경고만 한다"는 판단이 아니라 불변식이라, LLM에 맡기면 프롬프트로 아무리 못 박아도 보장되지 않는다.

## 훅이 막은 것을 푸는 방법

훅에는 "확인받았으면 통과" 같은 통로가 없다. 훅은 사용자의 구두 승인을 알 수 없고, 알게 만들면(환경 변수·마커 파일) 그 통로를 에이전트도 연다. 승인은 사용자가 `harness-map.md`의 슬롯·플래그 값과 훅 상수(`SCOPE`·`HARNESS_SELF_EDIT`·`TEST_CMD`)를 바꾸거나, 막힌 파일을 직접 고치는 행위다(`core-gates.md` §3). 에이전트는 막힌 사실과 이유, 무엇을 바꾸면 되는지를 보고하는 데서 멈춘다.

훅 스크립트는 고친 즉시 다음 도구 호출부터 효력이 생긴다. 그래서 에이전트가 자기 훅을 `exit 0`으로 바꾸면 스스로 풀 수 있다. **[플래그: 하네스 자기 수정]** 이 ❌면 `deny-out-of-scope-write.sh`가 `.claude/hooks/`·`settings.json` 쓰기를 막는다. 새 프로젝트에 붙이면 ❌가 기본이고, 하네스를 고치는 곳인 이 저장소만 ☑이다.

## 이 저장소에서의 적용

2026-09-07 감사([보고서](../reports/2026-09-07-harness-audit-baseline.md))가 이 레이어의 "겉과 속"이 다른 지점을 찾았고, 전부 훅·테스트로 고쳤다.

| 발견 | 무엇이 문제였나 | 고친 것 |
|---|---|---|
| `Stop` 훅 사각 | Write/Edit 도구만 편집으로 세서 Bash(`sed -i`·heredoc)로 고치면 통과. 검증 명령을 **언급**만 해도, 실패해도 통과 | Bash 편집 검출 · 마지막 편집 **뒤의** 실행만 인정 · 실행 결과 실패 대조 · 완료 동의어 추가. 픽스처로 판정 |
| 훅 등록 해제 미검출 | `settings.json`에서 훅 등록만 지운 커밋이 pre-commit을 통과 | `test-hooks.sh`에 등록 대조 — 모든 훅이 등록·실존·실행 가능한지 |
| 훅 자기 변조 | `.claude/`는 항상 쓰기 허용이라 에이전트가 자기 훅을 풀 수 있음 | "하네스 자기 수정" 플래그와 `HARNESS_SELF_EDIT` 상수 |
| 파괴 명령 커버리지 | `find -delete`·변수 경유 삭제·브랜치 강제 삭제 등 우회 25종이 통과 | 패턴 13종 추가 · `permissions.deny` 이중화. 케이스 파일에 우회·정상 케이스를 먼저 넣고 고쳤다 |

순서가 중요했다. 새 우회 경로를 발견하면 `hook-cases.txt`에 케이스부터 넣어 테스트가 실패하는 것을 확인하고, 그다음 훅을 고친다. 케이스가 먼저 있어야 같은 우회가 다시 열렸을 때 커밋 시점에 잡힌다.

## 관련 문서

- [`.claude/rules/README.md`](../../.claude/rules/README.md) — 훅 목록·공통 규약 SSOT
- [`component-map.md`](component-map.md) — 훅별 입력·판정·상수·고칠 때, "훅 하나를 추가하는 순서" 예시
- [`layer1-human-gate.md`](layer1-human-gate.md) — 훅이 아닌 규칙으로만 금지하는 것
