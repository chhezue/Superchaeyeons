# 프로젝트 설정 파일 `.claude/harness.conf`

하네스를 붙인 프로젝트마다 다른 값(경로·명령·형식·정책)을 담는 프로젝트 설정 파일이다. 이 문서는 값을 적고 고칠 때의 규칙을 정한다. 키 목록과 뜻은 같은 플러그인의 `scripts/harness-keys.txt`가 SSOT이고, `init-harness`가 이 두 파일을 보고 값을 채운다.

**언제 보는가:** `init-harness`로 값을 채우거나 재동기화할 때, 훅이 설정이 깨졌다며 막았을 때, 새 키를 더할 때.

키는 종류가 넷이다 — `slot`(규칙이 슬롯 이름으로 부르는 경로·명령·형식), `flag`(규칙의 `[플래그: 이름]` 절을 켜고 끄는 1·0), `hook`(훅이 판정에 쓰는 값), `info`(설명용 — `AXES`는 붙이는 시점에 실측한 언어·저장소 모양·배포·단계 네 축).

## 누가 읽나

| 읽는 쪽 | 무엇을 | 언제 |
|---|---|---|
| 설정 값 주입 훅 `auto-inject-config.sh` | slot·flag 키를 이름(`{{테스트 명령}}`·플래그 이름)과 값의 표로 넣는다 | 세션 시작·`/clear`·요약 뒤·서브에이전트 시작 |
| `deny-out-of-scope-write.sh` | `SCOPE` · `HARNESS_SELF_EDIT` | 파일 쓰기 직전 |
| `deny-dangerous-bash.sh` | `BLOCK_*` 6개 | Bash 실행 직전 |
| `deny-unverified-completion.sh` | `TEST_CMD` | 턴 종료 |
| `auto-correction-notice.sh` · `analyze-corrections.sh` · `polish-with-gemini.sh` | `AUTO_ANALYZE` · `DOC_ROOT` · `POLISH_ENABLED` | 세션 시작 · 분석 · 다듬기 |
| 규칙(`core-*.md`)·스킬 | 주입된 표의 `{{슬롯}}` 값 · `[플래그: 이름]` 적용 여부 | 작업 중 |

훅은 값을 본문에 적지 않고 이 파일을 읽는다. 플러그인은 모든 프로젝트가 같은 파일을 쓰므로, 프로젝트 값이 훅 본문에 있으면 프로젝트마다 다르게 둘 수 없다.

## 형식

한 줄에 `키=값`이다. `#`으로 시작하는 줄과 빈 줄은 건너뛰고, 값은 적힌 그대로 쓰이며 따옴표로 감싸지 않는다. 예시(설명용 — 최신이 아닐 수 있다):

```text
DOC_ROOT=docs
TEST_CMD={테스트 명령}
API_DOCS=(없음) — API 없음
HARNESS_SELF_EDIT=0
ASK_PATHS={승인이 필요한 경로 패턴}
COMMIT_RE=^(Feat|Fix|Docs): .+
```

| 값 | 뜻 |
|---|---|
| `{…}` (중괄호 한 쌍뿐) | 빈칸 — 아직 정하지 않았다. slot·flag 키에 남아 있으면 세션 시작 훅이 표 대신 "하네스 설정이 비어 있다"와 `init-harness` 제안을 넣는다 |
| `(없음) — 이유` | 이 프로젝트에는 없다. "안 정했다"(빈칸)와 가르기 위해 이유를 붙인다 |
| `1` · `0` | flag와 `ASK_*`·`BLOCK_*`·`AUTO_ANALYZE` — 적용 · 무시 |
| 빈 값 | hook 키만 — 그 검사를 하지 않는다(예: `COMMIT_RE=`면 커밋 메시지 형식을 보지 않는다) |

`{type}/{issue-number}-{description}`처럼 중괄호가 여러 개인 값은 빈칸이 아니라 형식 표기다.

## 파일이 없거나 깨졌을 때

| 상태 | `deny-*` 훅 | 설정 값 주입 훅 |
|---|---|---|
| 파일 없음(init 전) | 가장 엄격한 기본값으로 판정한다 — `SCOPE=.` · `HARNESS_SELF_EDIT=0` · `BLOCK_*`=1. `init-harness`가 설정을 만들 수 있게 `.claude/harness.conf`·`.claude/settings.json` 쓰기만은 막지 않는다 | "하네스 설정이 비어 있다"와 `init-harness` 제안 |
| 그 훅이 쓰는 키가 없음 | 그 키만 엄격한 기본값 — 플러그인 업데이트로 새 키가 생겨도 기존 프로젝트가 막히지 않게 | 빈칸과 같다 |
| 깨짐 — `키=값`이 아닌 줄 · 쓰는 키가 빈칸 · 허용되지 않는 값(0/1 자리에 다른 값, 빈 `SCOPE`) | 막는다(판정 불가 = 차단) | "하네스 설정이 비어 있다"와 빈칸 키 이름 |

Stop 훅(`TEST_CMD`)은 훅 공통 규약의 예외라, 설정이 없거나 깨지면 통과한다.

## 값을 적고 고칠 때의 규칙

1. 해당 없는 slot은 `(없음) — 이유`로 적는다
2. `(없음)`인 slot을 규칙이 요구하면 멈추고 사용자에게 묻는다
3. slot·flag는 `core-*.md`가 실제로 쓸 때만 둔다 — `scripts/check-portability.sh`가 `harness-keys.txt`의 slot 이름과 규칙·스킬이 쓰는 `{{…}}`를 대조한다
4. 옵션을 끄려고 규칙 절을 지우지 않는다 — flag가 0이면 `[플래그: 이름]` 절을 무시한다
5. `core-*.md`는 손대지 않는다. 고유 사실은 이 파일(값)과 `.claude/` 안의 `local-*`(규칙·스킬)에만 둔다. 클라이언트 전제·배포 토폴로지처럼 스택이 아닌 고유 사실은 `local-*.md`로 쓴다
6. `AXES`(축)는 붙이는 시점에 실측해 적는다. 규칙은 축을 직접 부르지 않는다 — slot·flag 값을 고르는 근거다. 기존 저장소에 붙일 때 명령·형식 slot은 기본값을 물려받지 않고 `init-harness`가 이력에서 실측한다
7. 하네스 자기 수정(`HARNESS_SELF_EDIT`)은 하네스 원본 저장소만 1이다. 붙여 쓰는 프로젝트는 0이 기본이다
8. `BLOCK_BULK_DELETE`(폴더 통째 삭제 막기)는 `init-harness`가 묻는다. 나머지 `BLOCK_*`는 묻지 않고 1(막기)로 둔다. 0으로 두면 그 묶음은 프로젝트 `settings.json`의 `permissions.deny`에 맡긴다
9. `DEPS_FILES`·`DEPS_ADD_CMD`·`ASK_PATHS`·`CONTRACT_PATHS`는 `init-harness`가 저장소를 확인해 후보를 제안하고, 승인 전에는 비워 둔다

## `harness-map.md`에서 옮기기

복사 배달 시절에는 같은 값이 `.claude/rules/harness-map.md`(표)와 훅 상수·git 훅 상수·루트 `harness.conf`에 나뉘어 있었다. `init-harness` 재동기화는 그 값들을 이 파일의 키로 옮기고 옛 파일과 상수를 지운다. 표의 `☑`·`❌`·`⬜`는 `1`·`0`·`{…}`(빈칸)로 옮긴다.

## 관련 문서

- `scripts/harness-keys.txt`(같은 플러그인) — 키 목록·종류·뜻
- `init-harness` 스킬 본문 — 값을 실측해 채우는 절차
- 하네스 원본 저장소의 `.claude/rules/README.md` "훅 공통 규약" — 판정 불가 = 차단·승인 창 규약
