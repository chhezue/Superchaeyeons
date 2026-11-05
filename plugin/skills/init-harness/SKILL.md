---
name: init-harness
description: 하네스를 붙이거나(설정이 비어 있다는 알림) .claude/harness.conf가 실제와 다를 때(재동기화) 사용. 저장소를 실측해 설정 값을 제안하고, 승인 후 harness.conf·settings.json·local-*.md를 채운다. 코드는 바꾸지 않는다.
---

# Harness Init — 하네스를 프로젝트에 붙이는 유일한 경로

**이 스킬이 기본 동작과 다른 단 하나:** 축·슬롯·형식 값을 **물려받지 않고 저장소에서 실측한다.** 플러그인은 프로젝트 값을 갖고 오지 않는다 — 기존 저장소는 실측으로, 그린필드는 질문으로 채운다.

**이 스킬은 `core-workflow.md` 사이클의 D 트랙이다.** 실측이 진입, 제안이 **G2 승인**, 채움 뒤 아래 산출물 체크리스트가 **G3 검증**이다. Invariant(작업 내내 참이어야 하는 것): **애플리케이션 코드를 한 줄도 바꾸지 않는다** — 산출물은 `.claude/harness.conf`·`.claude/settings.json`·`local-*`·`scripts/dev.conf`·`AGENTS.md`·`.gitignore`뿐이다.

설정 키 목록은 `${CLAUDE_PLUGIN_ROOT}/scripts/harness-keys.txt`, 값을 적는 규칙(빈칸 `{…}`·`(없음) — 이유`·파일이 없거나 깨졌을 때)은 이 스킬 폴더의 `references/harness-conf.md`가 SSOT다. 먼저 둘을 읽는다.

## When to Use

- **처음 붙일 때:** 프로젝트 `.claude/settings.json`에서 플러그인을 켠 뒤 세션을 열면 설정 값 훅이 "하네스 설정이 비어 있다"를 띄운다. 그때 다른 작업보다 먼저 이 스킬을 제안한다. 그린필드도 이 경로로 들어온다 — 1·4단계가 짧아질 뿐이다
- **재동기화:** 문서 위치·빌드 명령·커밋 관례 등 프로젝트 사실이 바뀌어 `.claude/harness.conf` 값이 실제와 다를 때. 1단계를 다시 돌려 현재 값과 실측의 diff 표를 만들고 승인 후 갱신한다. 채워진 설정 파일을 고치면 훅이 바뀌는 키와 값을 적은 승인 창을 띄운다 — 그 창이 승인이다
- **복사 배달에서 옮길 때:** 예전 방식(`.claude/`·`scripts/`를 복사)으로 붙인 프로젝트면 아래 "복사 배달에서 옮기기"를 함께 한다

**생략 불가:** "앞의 프로젝트와 비슷하니 그 값을 쓰자"는 이 스킬을 깨뜨리는 것이다. 커밋 형식을 물려받았다가 963개 커밋을 세어보고서야 실제 관례가 다르다는 걸 안 사례가 계기다.

## Steps

### 1. 실측 — 사람을 기다리지 않는다

`{{작업 범위}}`(기본 `.`) 안에서 아래를 코드·이력으로 확인한다. `${CLAUDE_PLUGIN_ROOT}/scripts/init-harness-probe.sh [저장소] [범위]`가 이 표의 대부분을 한 번에 뽑아 준다 — 출력을 그대로 2단계 제안의 근거로 붙인다. 각 항목은 **사실 + 근거(명령 또는 파일)** 로 표에 적는다. 환경이 답할 수 있는 것은 직접 본다.

| 축 | 확인할 것 | 근거를 얻는 방법 (예) |
|----|-----------|----------------------|
| **lang** | 언어·프레임워크·버전, 빌드·테스트·포맷·의존성 조회 명령, 정적 검사 도구, **의존성 선언 파일·설치 명령** | 빌드 선언 파일(`build.gradle*`·`pom.xml`·`package.json`·`pyproject.toml`·`go.mod` 등) · 확장자별 파일 수 `git ls-files \| sed 's/.*\.//' \| sort \| uniq -c` · CI 워크플로의 실제 명령 (다스택 예시) |
| **shape** | 저장소 루트 vs 하위 경로, 문서 루트, `.github/`에 파일을 둘 수 있는가(소유권), 모듈 경계, **커밋·브랜치 형식 · 기본 브랜치 · 머지 방식 · 이슈 트래커** | `git log --format=%s`를 패턴별로 집계 · `git branch -r` 이름 패턴 · 기본 브랜치 첫 부모의 merge 커밋 수와 PR 이력 · 브랜치·커밋의 이슈 키 · 트래커를 다루는 수단(설치된 CLI `which` · 연결된 MCP 서버 `claude mcp list`) · 기존 `CONTRIBUTING`·`docs/` 위치 · 모노레포면 하위 패키지 목록 (다스택 예시) |
| **deploy** | 외부 클라이언트 유무(앱·별도 프론트), 인증 위치(게이트웨이·앱), 배포 SSOT 파일, **API 계약 파일**(OpenAPI·proto·GraphQL 스키마) | `deploy/`·`docker-compose*`·`k8s/`·`.github/workflows/` · OpenAPI export 흔적 · 클라이언트 저장소 참조 (다스택 예시) |
| **stage** | 운영 보존 데이터 유무, **마이그레이션 폴더**, 인증·결제 코드 폴더, 기능 완성도(커밋 수·릴리즈 태그), 계약 동결 여부 | 마이그레이션 파일(`V*__*.sql` 등) `find` · `git tag` · 커밋 수 · 운영 환경 설정 유무 |

**슬롯 후보**도 같은 표에서 나온다 — 스펙 폴더·결정 기록·감사 로그·용어집·제품 범위 문서가 실제로 어디 있는지, 없으면 `(없음) — 이유`로.

### 2. 설정 값 제안 → **승인 (G2)**

실측표를 근거로 `harness-keys.txt`의 **키 전부**를 채운 제안을 만든다. 각 값에 근거를 한 줄 붙인다.

- **실측으로 정해지는 값**은 표 하나로 한 번에 보인다 — 축·슬롯 대부분과 `COMMIT_RE`(최근 커밋 형식을 맞추는 정규식), `FORMAT_PATHS`
- **실측으로 정해지지 않는 값만** `ask-decisions` 스킬의 라운드 방식으로 **한 번에 하나씩** 묻는다. 질문마다 선택지별 결과와 권장 답을 함께 보인다. 아래가 보통 남는 질문이다
  - **하네스 자기 수정**(`HARNESS_SELF_EDIT`) — 붙여 쓰는 프로젝트는 0을 권한다. 1은 하네스 자체를 고치는 저장소에만 둔다
  - **Gemini 다듬기**(`POLISH_ENABLED`) — 0을 권한다. 켜면 사람용 문서와 커밋·PR 글이 Gemini 무료 등급으로 나가고, Google이 그 글을 모델 개선에 쓸 수 있다는 점을 함께 보인다
  - **폴더 통째 삭제를 훅이 막을까요**(`BLOCK_BULK_DELETE`) — 막기(1)를 권한다. 막으면 git에 없는 파일(로컬 데이터·설정·산출물)을 지우는 `rm -rf`·`find -delete`가 막히고, 맡기면(0) 임시 폴더 정리가 막히지 않는 대신 Claude Code 기본 권한 확인에만 맡겨진다. 어느 쪽이든 루트·홈·현재 폴더·`.git` 통째 삭제는 훅이 막는다. 0이면 `settings.json` `permissions.deny`에 `Bash(rm -rf:*)`가 없어야 효과가 난다
  - **승인 창 후보** — 실측에서 찾은 후보를 보이고 고르게 한다. 승인 전에는 비워 둔다
    - `DEPS_FILES`(의존성 선언 파일) · `DEPS_ADD_CMD`(설치 명령 접두사, `|`로 구분)
    - `ASK_PATHS`(민감한 경로 — 인증·결제·마이그레이션 폴더 후보)
    - `CONTRACT_PATHS`(API 계약 파일 — 커밋 승인 창이 이유에 적는다)
    - `COMMIT_CHECK`(커밋 전 검사 명령 — 보통 비워 두거나 빠른 검사 하나)
  - 운영 데이터를 앞으로 보존할지, 외부 클라이언트를 붙일 계획인지처럼 이력에 없는 계획
- `ASK_*` 범주 플래그 다섯 개는 묻지 않고 1로 둔다(스펙 리스크 8). 나머지 `BLOCK_*`도 묻지 않고 1로 둔다
- `(없음)`은 "아직 모름"이 아니라 "이 프로젝트엔 그 개념이 없음"일 때만 남기고 이유를 붙인다
- **사용자 승인 없이 3단계로 넘어가지 않는다**

### 3. 채움 → **승인 (G3)**

승인된 값으로 아래를 만든다. 플러그인 파일(`${CLAUDE_PLUGIN_ROOT}` 아래)과 `core-*.md`는 손대지 않는다.

1. **`.claude/harness.conf`** — `harness-keys.txt`의 키 순서대로 `키=값`. 아직 없을 때는 훅이 이 파일 쓰기를 막지 않는다. 채운 뒤에는 고칠 때마다 승인 창이 뜬다
2. **`.claude/settings.json`** — 아래 셋을 쓴다. 기존 값은 지우지 않고 합친다
   - `extraKnownMarketplaces`: `"superchaeyeons": {"source": {"source": "github", "repo": "chhezue/Superchaeyeons"}, "autoUpdate": true}` — 하네스 원본 저장소에 커밋할 때마다 새 버전이 되고, 세션 시작 뒤 뒤에서 받아 다음 세션부터 실린다
   - `enabledPlugins`: `"superchaeyeons@superchaeyeons": true`
   - `permissions.deny`: `.env` 읽기·쓰기(`Read(./.env)`·`Read(./.env.*)`·`Read(**/.env)`·`Edit(./.env)`·`Write(./.env)`) · `Bash(git push --force:*)` · `Bash(git push -f:*)` · `Bash(git reset --hard:*)` · `Bash(git commit --no-verify:*)` · `BLOCK_BULK_DELETE=1`일 때만 `Bash(rm -rf:*)`
3. **트래커 안내** — 이 스킬 폴더의 `references/track-issues-skeleton.md`를 `.claude/skills/local-track-issues/SKILL.md`로 복사해 실측값으로 채운다 — 확인하지 못한 항목은 지어내지 않고 "(확인 못 함 — 이유)"로 남긴다. `ISSUE_LINK`는 "트래커 이름 · 안내 `local-track-issues`"로 채운다. 플러그인 도구는 세션 시작에 들어오는 규칙 머리 줄의 플러그인 폴더 경로로 부른다고 적는다
4. **`local-*.md`** — 설정 키로 빠지지 않는 **그 저장소만의 사실**이 있을 때만. 기존 코드만 봐서는 알 수 없는 관례(표기·테스트 도구)도 여기에 적을 수 있다. 스택 규칙을 지어 쓰지는 않는다. `AGENTS.md`와 중복이면 만들지 않는다
5. **`scripts/dev.conf`** — 이 스킬 폴더의 `references/dev.conf`(골격)를 복사해 1단계 CI 워크플로의 실제 명령으로 채운다. 실행 엔진(플러그인 `scripts/dev.sh`)은 고치지 않는다. 키를 채운 근거를 2단계 표에 붙이고, 실측으로 정해지지 않는 것(로컬에서 띄울 의존 서비스·헬스 판정 주소)만 묻는다. 값이 있는 명령 슬롯(`TEST_CMD` 등)은 `scripts/dev.sh <동사>`로 적는다 — 규칙 머리 줄이 이 `scripts/`가 플러그인 폴더라고 알린다
6. **`AGENTS.md`** — 플러그인의 견본이 없으면 하네스 원본 저장소의 `AGENTS.template.md`를 참고해 채운다
7. **`.gitignore`** — `.claude/corrections/`와 `.claude/polish/`가 없으면 더한다. 회고 루프가 정정 기억 설명과 대화 원문 일부를, Gemini 다듬기가 문서 기준판을 쓰는 폴더라 커밋되면 안 된다

**산출물 체크리스트** — 전부 통과해야 완료다.

- [ ] 새 세션(또는 `/reload-plugins` 뒤)에서 "하네스 설정이 비어 있다"가 뜨지 않고 설정 값 표가 들어온다
- [ ] `.claude/harness.conf`에 빈칸이 0개 — `grep -cE '=\{[^{}]*\}$' .claude/harness.conf`가 `0`
- [ ] `(없음)` 값마다 이유가 붙었다 — `grep -cE '=\(없음\)$' .claude/harness.conf`가 `0`
- [ ] `{{문서 루트}}/templates/README.md` 산출물 등록부의 "프로젝트 문서" 행이 이 저장소 값으로 채워졌다(등록부가 있을 때)
- [ ] `AGENTS.md`에 `{…}` 자리표시자가 0개
- [ ] `COMMIT_RE`가 최근 커밋 20개(`git log -20 --format=%s`)에 맞는다 — 형식이 `(없음)`이면 빈 값
- [ ] 저장소 루트에 `dev.conf`가 없다 — 있으면 `dev.sh`가 `scripts/dev.conf`보다 먼저 읽는다
- [ ] 플러그인 `scripts/dev.sh test`·`build`를 한 번씩 실행해 종료 코드가 0 또는 1이다 — 2(환경 없음)면 `dev.conf` 값이나 실행 환경을 고친다. 앱이 있으면 `start`→`stop`도 한 번
- [ ] `BASE_BRANCH`·`MERGE_METHOD`·`ISSUE_LINK`가 실측(첫 부모 merge 커밋 수·PR 이력·이슈 키)과 맞는다
- [ ] `.claude/skills/local-track-issues/SKILL.md`가 있고 `{…}` 자리표시자가 0개다
- [ ] `git check-ignore -q .claude/corrections/x`가 성공한다

### 4. 역스펙·초기 백로그 (기존 코드가 있을 때) → **승인 (G2 — Draft 스펙·감사 후보 목록)**

기능이 이미 완성된 저장소라면 하네스가 처음부터 있었던 것처럼 문서를 갖춘다 — **구현하지 않는다.**

- 주요 도메인의 **현재 동작**을 `{{스펙 저장소}}`에 Draft 스펙으로 (상태 `Implemented`·`Draft(역스펙)` 표기)
- 감사 후보를 `{{감사 로그}}`에 남긴다 — 실제 감사·리팩터는 `refactor-safely`(B 트랙)가 승인 후 진행

## 복사 배달에서 옮기기

예전에는 하네스를 `.claude/`·`scripts/`에 복사해 붙였다. 재동기화 때 아래를 한 번에 제안하고, 승인 뒤 같은 변경에서 옮긴다. 옛 파일을 "호환용"으로 남기지 않는다(`core-guardrails.md` §2).

| 옛 자리 | 옮길 곳 · 할 일 |
|---|---|
| `.claude/rules/harness-map.md`의 축·슬롯·플래그 표 | `.claude/harness.conf`의 키로 옮기고 파일을 지운다. `☑`·`❌`·`⬜`는 `1`·`0`·`{…}` |
| 훅 상수(`deny-out-of-scope-write.sh`의 `SCOPE`·`HARNESS_SELF_EDIT` · `deny-unverified-completion.sh`의 `TEST_CMD` · `deny-dangerous-bash.sh`의 `BLOCK_*`) · git 훅 상수(`COMMIT_RE`·`FORMAT_CMD`·`FORMAT_PATHS`) · 루트 `harness.conf`(`POLISH_ENABLED`) | 같은 이름의 키로 옮긴다 |
| 복사해 온 `.claude/rules/core-*.md`·`doc-writing.md`·`README.md` · `.claude/skills/`(`local-*` 빼고) · `.claude/agents/` · `.claude/hooks/`(`local-*` 빼고) · `scripts/`의 하네스 도구(`dev.sh`·`check-*.sh`·`*-patterns.txt`·`init-harness-probe.sh`·`analyze-corrections.sh`·`polish-with-gemini.sh`·`test-hooks.sh`·`hook-cases.txt`·`verify.sh`·`install-git-hooks.sh`·`git-hooks/`) | 지운다 — 플러그인이 싣는다. `.git/hooks/`에 설치된 `pre-commit`·`commit-msg`도 지운다(커밋 검사는 승인 창 훅이 한다) |
| `.claude/settings.json`의 `hooks` 블록(복사한 훅 등록) | 지우고 2단계 3번의 마켓플레이스·플러그인 켜기로 바꾼다 — 남기면 같은 훅이 두 번 돈다 |
| `scripts/dev.conf` · `local-*` | 그대로 둔다(프로젝트 값) |

## 보고

`core-reporting.md` 문체로 짧게: 축 4개 값, 채운 슬롯 수와 남긴 `(없음)` 수, 켠 플래그, 승인 창 후보로 넣은 경로, 만든 `local-*.md`, 체크리스트 결과.

## 금지

- 실측 없이 기본값이나 다른 프로젝트 값을 채움
- 승인 전에 `.claude/harness.conf`·`local-*.md`를 쓰기 시작함
- 플러그인 파일·`core-*.md` 수정 · 애플리케이션 코드 수정
- 빈칸·이유 없는 `(없음)`을 남기고 완료 선언
- 질문 여러 개를 한 메시지에 묶어 묻기

## It's working if

- 새 세션에서 설정 값 표가 들어오고, 에이전트가 `{{테스트 명령}}`을 물어보지 않고 바로 실행한다
- 커밋하면 승인 창이 뜨고, 메시지가 저장소의 기존 관례와 같은 모양으로 나온다
