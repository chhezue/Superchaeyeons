# 하네스 구성 요소 지도

규칙·스킬·에이전트·훅·검사기 **하나하나가 언제 실행되고, 무엇을 묻고, 무엇을 검사하고, 고치려면 어디를 건드리는지**를 한 파일에 모았다. 하네스를 수정하기 전에 이 파일에서 해당 행을 찾아 "고칠 때" 열을 따르면 된다. 구조 인덱스(`.claude/rules/README.md`)가 "무엇이 있나"라면, 이 문서는 "그것이 어떻게 움직이나"다. 두 문서가 어긋나면 `.claude/rules/README.md`와 각 파일 본문이 맞다 — 이 문서는 이 저장소 이력이라 새 프로젝트에 배달하지 않는다.

## 언제 이 문서를 보는가

- 하네스를 고치려는데 어느 층(규칙·스킬·훅)을 건드려야 할지 모를 때 — 맨 아래 "수정 로드맵"
- 에이전트가 왜 멈췄는지, 왜 질문했는지, 왜 되돌렸는지 알고 싶을 때 — "한 턴의 흐름"
- 새 구성 요소를 추가한 뒤 갱신해야 할 표가 어디인지 확인할 때

## 한 턴의 흐름

사용자 메시지 하나가 처리되는 동안 무엇이 어느 순서로 끼어드는지다. 왼쪽은 시점, 가운데는 개입하는 장치, 오른쪽은 그 장치가 하는 일이다.

| 시점 | 장치 | 하는 일 |
|------|------|---------|
| 세션 시작 | 훅 `warn-unfilled-map.sh` | `harness-map.md`에 ⬜·이유 없는 `(없음)`이 남았으면 경고 주입 |
| 세션 시작 | always-load 규칙 8개 | `core-*` 7개 + `harness-map.md`가 컨텍스트에 실림 (`CLAUDE.md` → `AGENTS.md` 포함) |
| 프롬프트 제출 | 훅 `ask-open-request.sh` | "알아서·적당히·최적화·개선" 류가 있으면 `ask` 스킬 알림 주입 (차단 안 함) |
| 진입 | `core-workflow.md` 진입 절 | 트랙 판정 A(기능)·B(감사)·C(버그)·D(이식) + 문서 확인 순서 |
| 진입 | `core-gates.md` | 변경이 통제 영역(도메인 규칙·인증·과금·계약·스키마)에 닿는지 판정 → G2 대상 여부 |
| G1 리서치 | 에이전트 `researcher` | 외부 라이브러리·SDK 지식이 필요하면 로컬 실물 → 공식 문서 순으로 조사 |
| G2 승인 | 스킬 `ask` → `specify`/`safe-refactor`/`debug`/`adopt` | 열린 요청이면 라운드 인터뷰, 그다음 트랙별 승인 산출물(스펙·감사 문서·원인 가설·슬롯 제안) |
| G2 직후 | 스킬 `preflight` 사전 모드 | 빌드·테스트가 현재 상태에서 도는지 먼저 확인 |
| 구현 중 | 훅 `deny-dangerous-bash.sh` · `deny-out-of-scope-write.sh` | 도구 호출 직전에 위험 명령·범위 밖 쓰기 차단 |
| 구현 중 | `core-guardrails.md` ⛔ · 파일 접근 시 로드되는 규칙 | 문서 충돌·레거시 잔존·계약 변경 미루기 금지. 소스 파일을 열면 `core-code-comments.md`, 마크다운을 열면 `doc-writing.md` |
| G3 검증 | 스킬 `preflight` 사후 모드 + 에이전트 `doc-reviewer`·스택 리뷰어 + `code-review`/`simplify` | 테스트 실행 · 체크리스트를 코드와 대조 · 문서 품질 · 3파일+면 별도 컨텍스트 리뷰 |
| G4 회고 | 스킬 `retro` · `defer` · `report.md` | 하네스 개선 후보 · 범위 미루기 · Must Have급 작업 보고서 · 커밋 분할안 제안 |
| 턴 종료 | 훅 `deny-unverified-completion.sh` | 코드를 고쳤는데 `{{테스트 명령}}` 실행 없이 "완료"라 했으면 되돌림 |
| 커밋 | git 훅 `pre-commit` · `commit-msg` | 부품 계약·훅 규약·문서 스타일 검사, 커밋 메시지 형식 검사 |

## 규칙 (`.claude/rules/`)

규칙은 프롬프트로 작동하는 소프트 가드레일이다. 강제력은 없고, 에이전트가 읽고 따르는 것이 전부다. 그래서 "무엇을 묻는가" 열이 중요하다 — 규칙의 실제 효과는 질문으로 나타난다.

| 파일 | 로드 | 강제하는 것 | 에이전트가 묻는 것 | 고칠 때 |
|------|------|-------------|-------------------|---------|
| `core-guardrails.md` | 항상 | ⛔ STOP §1 문서·구현 정합 · §2 레거시 즉시 삭제 · §3 보안 변경 시 `{{현재동작 요약}}` 갱신 · 플래그 판정 원칙 | 문서끼리 값이 다를 때 어느 쪽이 맞는지 · 문서와 다른 값을 쓰려 할 때 승인 | 다른 모든 규칙보다 우선하므로 절을 늘리기보다 기존 절에 붙인다. `[플래그: X]` 배지를 새로 달면 `harness-map.md` 플래그 표에도 행 |
| `core-gates.md` | 항상 | §1 통제/위임 영역 · §2 멈추는 신호(기본값·열린 표현·파일 3개+·의존성 추가·트랙 변경·훅 차단) · §3 자동으로 하지 않는 것 | 기본값 후보와 권장값 · 새 파일·삭제·의존성 목록 승인 · 트랙 승격 여부 | 멈추는 신호를 추가·삭제하는 곳. 훅이 막은 것의 승인 통로는 설정 변경뿐이라는 원칙도 여기 |
| `core-workflow.md` | 항상 | 4 트랙 × 4 게이트 순서 · 불변 조건 · 구현 중 지킬 것 · 이슈·브랜치·PR 생성 전 확인 · 커밋 분할 최대 5개 | 트랙별 승인 대상(스펙·감사 항목·가설·슬롯 제안) · 이슈·브랜치·PR을 만들지 · 커밋 분할안 | 게이트 내용의 SSOT. 스킬 본문에 게이트를 중복 정의하지 않는다 — 스킬은 여기를 가리킨다 |
| `core-scope.md` | 항상 | `[미정]`은 문서에 표기만 · 중앙 트래커 금지 · 라벨은 `{{우선순위 SSOT}}`가 정한 것만 | `[미정]`을 확정해도 되는지 · 라벨을 붙여도 되는지 | 우선순위 라벨 정책(must/could)은 부품에 없다 — 라벨 체계가 있는 프로젝트가 `local-priority.md`를 둔다(견본 `examples/tripfit/local-priority.md`) |
| `core-followup.md` | 항상 | 완료 후 💡 후속 제안 형식(3~8개) · Defer는 `defer` 스킬 · ERD 적극 제안 | 후속 제안을 진행할지 (같은 턴에 구현 금지) | 코드·설계 개선 제안의 형식. 하네스 자체 개선은 `retro` 몫 — 경계를 흐리지 않는다 |
| `core-tools.md` | 항상 | 서브에이전트 호출 규약 · 별도 컨텍스트 리뷰(`code-review`/`simplify`) · 서드파티 도구 채택·배제 기준 | — | 트랙·게이트별 도구 라우팅은 `core-workflow.md` 트랙 표("Claude Code 도구" 열)와 게이트 절이 직접 적는다 — 스킬·에이전트를 추가·삭제·개명하면 그쪽을 갱신 |
| `core-reporting.md` | 항상 | 사용자 보고는 비전공자 문체(용어 풀어쓰기·결과 중심·과장 금지) | — | 코드 주석·문서 본문에는 적용하지 않는다 |
| `harness-map.md` | 항상 | 축 4 · 슬롯 22 · 플래그 8의 **값**. 규칙 5개(빈 슬롯 `(없음)` 명시 · `(없음)` 요구 시 질문 · 슬롯 문턱 · 절 삭제 금지 · core 불가침) | `(없음)` 슬롯을 규칙이 요구할 때 값 | 새 프로젝트가 채우는 유일한 파일. 슬롯·플래그 추가는 `core-*`에서 실제로 쓰는 곳이 생겼을 때만. 훅 상수(`SCOPE`·`TEST_CMD`·`commit-msg` 정규식)와 같이 고친다 |
| `core-code-comments.md` | 소스 파일 접근 시 | 실행 줄 위 단계 주석 · 필드·의존성 해설 · 주석도 실물 대조 · 이유 평문 | — | 언어별 표기는 lang 팩 "주석 규칙" 절. 여기는 원칙만 |
| `doc-writing.md` | 마크다운 접근 시 | 문서 유형 4개 → 정보 구조 → 문장. 기계 판정은 `check-doc-style.sh`, 판단은 `doc-reviewer` | — | 패턴으로 잡히는 항목은 `scripts/doc-style-patterns.txt`에, 판단 항목은 `doc-reviewer` 기준에 |
| `README.md` | `.claude/` 구성 요소 접근 시 | 구조 인덱스 · 3층 · 작명 규칙 · 유지보수 체크리스트 | — | 구성 요소를 추가·삭제하면 디렉터리 트리와 표를 같이 갱신 |
| `local-*.md` | 파일이 있을 때만 | 저장소 고유 사실 · 복사한 lang 팩 | — | 검사기가 보지 않는 층. 자유롭게 고친다 |

**규칙을 고친 뒤 돌릴 것:** `scripts/check-portability.sh` (고유명사·스택 식별자·경로 리터럴·팩 참조, always-load 52,000B 예산). pre-commit이 같은 검사를 한다.

## 스킬 (`.claude/skills/`)

스킬은 다단계 절차이고 중간에 승인 게이트가 있다. 에이전트가 상황을 보고 부르거나(`core-workflow.md` 트랙 표·게이트 절이 라우터) 사용자가 이름을 부른다. 각 `SKILL.md`는 첫 줄에 "기본 동작과 다른 단 하나", 끝에 "It's working if"를 둔다.

| 스킬 | 언제 (누가) | 묻는 것 (승인 게이트) | 검사하는 것 | 산출물 | 고칠 때 |
|------|-------------|----------------------|-------------|--------|---------|
| `adopt` | D 트랙 — 하네스를 붙일 때·map 재동기화 (사용자) | 2단계: 실측표 근거의 축·슬롯·플래그 제안 승인 (실측으로 안 정해지는 것만 번호 질문) · 3단계: 채움 결과 승인 · 4단계: 역스펙 Draft 승인 | 산출물 체크리스트 8개 — 검사기 exit 0 · `(없음)`·⬜에 이유 · 스택 팩 표 = 실제 파일 · 씨앗 대조 표 빈 칸 0 · 등록부 채움 · 훅 등록 = 플래그 · `AGENTS.md` 자리표시자 0 · 커밋 형식 = 최근 20개 | `harness-map.md` 값 · 복사한 씨앗(`local-*`) · `local-*.md` · `AGENTS.md` | 1단계 실측 항목을 늘리면 `scripts/adopt-probe.sh`도 같이. 체크리스트는 `pack.md` 계약을 대신하는 유일한 품질 장치 |
| `ask` | G2 앞 — 열린 표현·미명시 기본값·해석이 갈릴 때 (에이전트, 훅이 알림) | 라운드마다 프론티어(선행 결정이 끝난 질문)만, 번호 + 권장 답. 프론티어가 비면 "이해가 공유됐는지" 한 문장 확인 | 사실(코드·설정·버전)은 묻지 않고 직접 조사했는지 | 없음 — 답이 스펙·감사 항목의 근거로 들어감 | 트리거 표현을 바꾸면 `ask-open-request.sh`의 `OPEN_PATTERNS`도 같이 |
| `specify` | A 트랙 — 기능·API·DB·정책 변경 (에이전트) | 모호함은 `AskUserQuestion` · 스펙 작성 후 **Approved 승인** 전 구현 금지 | `{{제품 범위}}` 포함 여부 · `{{클라이언트 전제}}` 충돌 · `{{아키텍처 개요}}`·`{{스키마 SSOT}}`·기존 스펙과 충돌 · G1 근거 URL·버전 | `{{스펙 저장소}}/{unit}/{name}.md` (불변 조건 절 포함) | 스펙 골격은 `references/spec-template.md`. 도메인 폴더는 `{{스펙 저장소}}` README 표가 SSOT — 스킬에 폴더 이름을 적지 않는다 |
| `safe-refactor` | B 트랙 — 기존 코드 감사·리팩터 (사용자) | 2단계: 불변 조건 목록 확정 + 감사 A/B 항목별 승인, 승격 후보 별도 · 6단계: 다음 작업 단위 진행 여부 | 4단계 `preflight`로 불변 조건마다 기계 검증(테스트 전부 통과 · 계약 diff 0) | `{{감사 로그}}/{unit}/{NNN}-*.md` · `refactor-log.md` | 점검 항목은 `references/audit-checklist.md`, 분류·포맷은 `audit-template.md`. 감사는 반드시 새 서브에이전트(self-grading 편향) |
| `debug` | C 트랙 — 버그·테스트 실패 (에이전트) | 수정 범위 합의(G2) · 운영 접속 정보가 없으면 요청 | 재현이 먼저 — 재현 못 한 버그는 고치지 않음 · 회귀 확인 `{{테스트 명령}}` | 없음 | 운영 접속 정보는 규칙에 적지 않고 에이전트 메모리에만 |
| `preflight` | G2 직후(사전) · 완료 보고 전(사후) (에이전트) | 사전: 기존 실패를 고칠지 무시할지 | 사전: 빌드·테스트가 현재 상태에서 도는가 · 사후: 테스트 실행 · 스펙·이슈 체크리스트를 **코드**와 대조 · 불변 조건 · 계약 diff · 레거시 잔존(**고친 문서 안의 자기모순 포함** — 상수·개수를 바꿨으면 그 숫자로 저장소 검색) · 문서 품질 · 리뷰어 | 없음 — 미검증 항목은 `report.md` "검증하지 못한 것" | `deny-unverified-completion.sh`가 이 스킬을 건너뛴 완료 선언을 되돌린다 |
| `defer` | G4 — "다른 이슈로" (에이전트) | 4단계 `gh issue create` 전 확인 (사용자가 "이슈 만들어줘"까지 말했으면 생략) | Draft 스펙·Approved amend·README 갱신·구현 트림이 같은 턴에 전부 있는지 | Draft 스펙 + 이슈 | 이슈 양식은 `{{Git 컨벤션 SSOT}}`·이슈 템플릿이 SSOT — 스킬에 라벨 이름을 적지 않는다 |
| `retro` | G4 — Must Have급 완료 후·회고 요청 시 (사용자·에이전트) | 5단계: 후보 3~8개 승인 후에만 기록 · 7단계: 규칙 실제 반영은 별도 승인 | "같은 실수 2회+" 근거 2건 · exit code 판정 가능한 것만 훅 후보 | `{{문서 루트}}/audits/harness-retro.md` append | 메인 컨텍스트에서만 실행 — 서브에이전트는 대화 이력에 접근 못 함 |

**스킬을 고친 뒤 돌릴 것:** `scripts/check-portability.sh` (스킬 본문도 배달물이라 검사 대상). 스킬을 추가·삭제·개명하면 `core-workflow.md` 트랙 표·게이트 절 + `.claude/rules/README.md` Skills 표를 같은 턴에.

## 에이전트 (`.claude/agents/`)

조사·리뷰 전용 서브에이전트다. `Edit`/`Write`는 없지만 `Bash`가 있어 물리적으로 수정이 막혀 있지는 않다 — "수정하지 않는다"는 각 지침의 규범이다. 대상은 경로 목록으로만 넘기고, 10개를 넘으면 나눠 부른다.

| 에이전트 | 호출 시점 | 보는 것 | 출력 | 하지 않는 것 | 고칠 때 |
|----------|-----------|---------|------|--------------|---------|
| `researcher` (sonnet) | G1 — 외부 라이브러리·SDK·provider 지식, 특히 문서 2개 이상 비교 (단일 페이지면 인라인 `WebFetch`) | ① 로컬 실물 버전 → ② 공식 문서(버전 확인) → ③ 릴리즈 노트 → ④ provider 문서 | 결론 · 우리 버전 적용 여부 · 근거(URL+버전+확인일) · 달라진 점 · 확인하지 못한 것 | 블로그·StackOverflow 인용 · 규칙 파일에 박힌 버전 신뢰 · 요청 밖 파일 수정안 | 스택 사실(프레임워크·URL)은 여기 적지 않는다 — lang 팩 "스택 함정 메모"와 호출자 프롬프트가 준다 |
| `doc-reviewer` (sonnet) | G3 — 새 문서 또는 50줄+ 수정 (advisory, 커밋 안 막음) | 1단계 **소유권**(이 저장소 것인가 · 이력인가 지시인가 · 이력 문서에 배너가 있는가)과 유형(4유형 필수 섹션) · 2단계 정보 구조(개요·H4·제목 30자·표 앞 설명) · 3단계 문장(메타 담화·약어·피동) | 요약 · 반드시 고칠 것 · 고치면 좋을 것 · 용어 일관성 · 좋았던 점 | 기술적 사실·설계 판단 · 문서 수정 · 기준(`doc-writing.md`)에 없는 취향 | 심각도 등급 표가 이 파일에 있다 — 같은 문서를 두 번 리뷰해도 흔들리지 않게 |
| `{스택}-reviewer` (씨앗) | G3 — **[플래그: 스택 리뷰어]** ☑이고 스택 코드 3파일+·API·DB 변경 | 정적 검사(아키텍처 테스트·린터)가 못 잡는 결함 — 트랜잭션 경계·N+1·에러 코드·권한 게이트 누락 | 결함 목록 (서버 개발자 독자) | 정적 검사가 이미 잡는 규칙 중복 지적 · 트레일러 유무 판정 | 배달물에 없다. `examples/seeds/{스택}/agents/local-*-reviewer.md`를 복사해 `name:`은 접두사 없이 |

**에이전트를 고친 뒤 돌릴 것:** `scripts/check-portability.sh`. 추가·삭제하면 `core-workflow.md` G1·G3 절 + `.claude/rules/README.md` Agents 표.

## 훅 (`.claude/hooks/`)

`.claude/settings.json`이 이벤트 → 스크립트를 잇는다. 훅은 LLM 판단과 무관하게 exit code로 작동하는 결정론적 하한선이다. `deny-`는 차단(exit 2), `warn-`은 경고 주입, `ask-`는 질문 유도 주입. 공통 규약: 모든 `deny-*`는 **판정 불가(JSON 깨짐·키 없음·빈 입력·python3 없음)도 차단**한다. 훅에는 "확인받았으면 통과" 통로가 없다 — 승인은 사용자가 `harness-map.md` 값과 훅 상수를 바꾸는 행위다.

| 훅 | 이벤트 · 매처 | 입력 | 판정 | 결과 | 상수 (슬롯과 함께 고침) | 고칠 때 |
|----|---------------|------|------|------|-------------------------|---------|
| `deny-dangerous-bash.sh` | `PreToolUse` · `Bash` | `tool_input.command` | `PATTERNS` 배열 — force push(플래그 위치 무관·`+refspec`·`--force-with-lease`) · `rm -rf`(플래그 조합 무관)·`find -delete/-exec rm` · `git reset --hard`·`clean -f`(dry-run 제외)·`branch -D`·`stash drop/clear`·`filter-branch` · `git commit --no-verify/-n` · `.env` add/commit(`.env.example`은 통과) · SQL `DROP DATABASE/TABLE/SCHEMA` · 컨테이너 볼륨 삭제(`down -v/--volumes`·`system prune --volumes`·`volume rm`) · `curl\|wget … \| sh` · `chmod -R 777` · `dd of=/dev/` | 차단. 알려진 오탐: 명령 문자열 전체를 보므로 `grep 'rm -rf'`도 막힘 — fail-closed 의도. 못 보는 것: 변수·`eval`·별도 스크립트 간접 실행(규칙으로만 금지) | 없음 | 패턴을 늘리면 `scripts/hook-cases.txt`에 우회 케이스·정상 케이스를 먼저. 같은 항목을 `settings.json` `permissions.deny`에도 |
| `deny-out-of-scope-write.sh` | `PreToolUse` · `Write\|Edit` | `tool_input.file_path` 또는 `notebook_path` | 실경로 정규화 후 (1) `HARNESS_SELF_EDIT=0`이면 `.claude/hooks/`·`settings.json`인가 → 차단 (2) `SCOPE/` 또는 `.claude/` 안인가. 저장소 밖 절대경로(세션 파일)는 통과 | 차단 | `SCOPE` = `{{작업 범위}}` (`.`이면 범위 검사 생략) · `HARNESS_SELF_EDIT` = 플래그 "하네스 자기 수정" | 케이스는 `SCOPE=sub`·`;self=0`으로 치환해 돈다 |
| `ask-open-request.sh` | `UserPromptSubmit` | `prompt` | `OPEN_PATTERNS`(한국어·영어)에 걸리고 `SMALL_FIX_PATTERNS`에 안 걸리는가 | 컨텍스트 주입만 (차단하면 프롬프트가 지워짐) | `OPEN_PATTERNS`·`SMALL_FIX_PATTERNS` (언어별) | `ask` 스킬의 트리거 표현과 같이 고친다 |
| `deny-unverified-completion.sh` | `Stop` | `transcript_path`·`stop_hook_active` | 마지막 사용자 메시지 이후 (a) 비문서 파일 편집 있음 — 도구 Write/Edit + Bash `sed -i`·`>`/`>>`·`tee` (b) 마지막 편집 **뒤에** `TEST_CMD`를 명령으로 실행한 기록이 없거나(문자열 언급은 실행 아님) 그 tool_result가 실패(is_error·"실패 있음"·FAIL) (c) 마지막 텍스트에 완료 단정("완료·통과·끝났·마쳤·성공·정상 동작·구현/적용/반영/수정했·done·passed·fixed·complete·works", 부정형·"완료 조건" 제외) | 되돌림(exit 2, 미실행·실패 메시지 구분). 재진입·transcript 없음·`TEST_CMD` `(없음)`이면 통과 — Stop 훅만의 예외 | `TEST_CMD` = `{{테스트 명령}}` | 픽스처 `scripts/hook-fixtures/*.jsonl` 9종으로 판정. 완료 단정 정규식을 바꾸면 픽스처 문장도 확인 |
| `warn-unfilled-map.sh` | `SessionStart` | (안 씀) | `harness-map.md`에 `\| ⬜ \|`·`\| (없음) \|`(이유 없는) 행 수 | 경고 주입 (SessionStart는 차단 불가) | 없음 | `harness-map.md` 표 형식을 바꾸면 grep 패턴도 |
| `local-deny-db-migration.sh` (씨앗) | `PreToolUse` · `Write\|Edit` | 경로 | `/db/migration/` 또는 `V1__x.sql`·`R__x.sql` 이름 | 차단 | 없음 | **[플래그: DB 마이그레이션 금지]** ☑일 때만 복사·등록. 운영 DB가 있으면 반드시 ❌ |
| `local-warn-breaking-change.sh` (씨앗) | `PreToolUse` · `Bash` (git commit) | 명령 | 계약 변경 커밋에 사유 트레일러가 있는지 | 경고만 (advisory는 반드시 command-type — agent-type이 커밋을 막은 사고) | 없음 | **[플래그: API 계약 보호]** |
| `local-auto-format-java.sh` (씨앗) | `PostToolUse` · `Edit\|Write` | 경로 | 소스 파일이면 포맷터 실행 | 자동 실행 | 포맷 명령 직접 박음 = `{{포맷 명령}}` | `{{포맷 명령}}`이 있을 때만 |

**훅을 고친 뒤 돌릴 것:** `scripts/hook-cases.txt`에 케이스를 **먼저** 추가 → `scripts/test-hooks.sh` (케이스 파일 + python3 부재 내장 케이스). pre-commit이 훅·케이스·settings가 stage되면 같은 테스트를 돌린다. `.claude/rules/README.md` Hooks 표 + 디렉터리 트리 갱신.

## 검사기와 git 훅 (`scripts/`)

훅이 "에이전트의 한 동작"을 막는다면, 검사기는 "저장소 상태"를 판정한다. 셋 다 bash 하나 + 데이터 파일 하나다.

| 스크립트 | 언제 | 판정 | 데이터 파일 | 실패 시 |
|----------|------|------|-------------|---------|
| `check-portability.sh` | 규칙·스킬·에이전트·훅을 고친 뒤 · pre-commit(배달물 stage 시) | 배달물에 C1 고유명사 · C2 스택 식별자 · C3 경로 리터럴·버전 · C4 팩 참조가 없는가. always-load 합계 ≤ 52,000B(래칫). `harness-map.md`·`.claude/*/local-*`·`examples/`는 제외 | `portability-patterns.txt` | exit 1 — 위반 줄과 대신 쓸 것(슬롯·lang 팩)을 출력 |
| `test-hooks.sh` | 훅을 고친 뒤 · pre-commit(훅·케이스 stage 시) | 케이스마다 기대 exit와 실제 exit 비교. 씨앗 훅도 찾는다. 내장: `deny-*` 전부에 python3 부재 → exit 2 · 훅 등록 대조(`.claude/hooks/*.sh` 전부가 `settings.json`에 등록·실존·실행 가능) | `hook-cases.txt` · `hook-fixtures/` | exit 1 — 실패 케이스와 stderr 3줄 |
| `check-doc-style.sh` | 문서를 새로 쓰거나 크게 고친 뒤 · pre-commit(`.md` stage 시) | E(차단): 개요 없음·H4·메타 담화·이중 피동·닫히지 않은 펜스 · W(경고): 제목 30자·약어 첫 등장·한자어·명사형·**깨진 상대 링크**(외부 URL·앵커·슬롯 제외) | `doc-style-patterns.txt` | E가 있으면 exit 1. 오탐이면 스크립트가 아니라 패턴 파일을 고친다 |
| `verify.sh` | "완료·통과"를 말하기 전 — 이 저장소의 `{{테스트 명령}}` | 위 셋을 순서대로 | — | 하나라도 실패하면 exit 1 |
| `adopt-probe.sh` | `adopt` 1단계 | 축 4개·커밋/브랜치 형식 집계·슬롯 후보를 마크다운 표로 (판단 없음, 읽기 전용) | — | — |
| `git-hooks/pre-commit` | 커밋 직전 (`install-git-hooks.sh`로 설치) | 위 검사기 3개를 stage 내용에 따라 조건부 실행 · `FORMAT_CMD`가 있으면 자동 포맷 | — | 커밋 차단 |
| `git-hooks/commit-msg` | 커밋 메시지 작성 후 | `{Type}: {설명}` 정규식 (= `{{커밋 메시지 형식}}`, 훅 본문에 직접) | — | 커밋 차단 |

## 수정 로드맵 — 상황별로 어디를 고치나

하네스를 바꾸고 싶을 때 상황에서 시작해 파일과 검증으로 내려간다. 원칙 하나: **판정 가능한 것은 훅·검사기로, 판단이 필요한 것은 규칙·에이전트로.** 판단을 훅에 넣으면 오탐으로 막히고, 막히는 훅은 우회된다.

| 하고 싶은 것 | 고치는 곳 | 같이 고칠 것 | 검증 |
|--------------|-----------|--------------|------|
| 에이전트가 특정 상황에서 **멈추고 묻게** | `core-gates.md` §2 멈추는 신호에 행 추가 | 상황이 표현(단어)으로 잡히면 `ask-open-request.sh` 패턴도 | `check-portability.sh` |
| 특정 명령·쓰기를 **무조건 막게** | 기존 `deny-*` 훅에 패턴 추가, 또는 새 `deny-*.sh` + `settings.json` 등록 | `hook-cases.txt` 케이스 먼저 · `.claude/rules/README.md` Hooks 표·트리 · 훅 공통 규약(판정 불가 = 차단) 준수 | `test-hooks.sh` |
| 완료 선언 전 **다른 검증**도 강제 | `{{테스트 명령}}`을 그 검증까지 포함하는 래퍼로 (이 저장소는 `verify.sh`) | `harness-map.md` 명령 슬롯 · `deny-unverified-completion.sh`의 `TEST_CMD` · 픽스처의 Bash 명령 | `test-hooks.sh` |
| 새 **워크플로 절차** (여러 단계 + 승인) | `.claude/skills/{동사}/SKILL.md` — 첫 줄 "기본 동작과 다른 단 하나", 끝 "It's working if", 어느 트랙·게이트인지 | `core-workflow.md` 트랙 표·게이트 절 · `.claude/rules/README.md` Skills 표 · 산출물이 md면 `docs/templates/README.md` 등록부 행 | `check-portability.sh` |
| 새 **조사·리뷰 역할** | `.claude/agents/{역할}.md` — `tools`에서 `Edit`/`Write` 제외, 출력 포맷 고정 | `core-workflow.md` G1/G3 절 · README Agents 표 | `check-portability.sh` |
| 규칙에 **프로젝트 경로·명령**이 필요 | `core-*.md`에 `{{슬롯}}`으로 쓰고 `harness-map.md`에 행 추가 (실제로 쓰는 곳이 있을 때만 — 규칙 3) | 훅이 그 값을 쓰면 훅 상수 + "함께 고칠 것" 표기 · `examples/*/harness-map.md` 견본 | `check-portability.sh` |
| 규칙에 **켜고 끌 정책**이 필요 | `core-*.md` 절에 `[플래그: X]` 배지 + `harness-map.md` 플래그 표 행 (절은 절대 지우지 않는다) | lang 팩이 구현하는 절이면 `_template/rules/lang-conventions.md`에 같은 이름의 절 | `check-portability.sh` |
| **스택 규칙** 추가·변경 | `examples/seeds/{스택}/`의 `local-*` 파일 (배달물 아님). 새 스택은 `_template/`을 채운 뒤 실제 프로젝트에서 한 사이클 굴린 후에만 씨앗으로 | 씨앗 README "무엇을 어디에 복사하나"·"씨앗 대조" 표 · `examples/seeds/README.md` 목록 | `check-doc-style.sh` · 훅이 있으면 `test-hooks.sh` |
| 문서 문체 규칙 추가 | 패턴으로 잡히면 `scripts/doc-style-patterns.txt` (E/W 등급 선택) · 판단이 필요하면 `doc-writing.md` + `doc-reviewer.md` 심각도 표 | 오탐이 나면 패턴 파일만 고친다 | `check-doc-style.sh --all` 오류 0 |
| 규칙이 **너무 길어** 컨텍스트 압박 | 파일 접근 시에만 필요하면 `paths:` frontmatter로 · 스택 사실이면 씨앗으로 · 중복이면 SSOT 하나만 남기고 가리키기 | `check-portability.sh`의 예산 상한을 **낮춘다** (래칫 — 올리지 않는다) | `check-portability.sh` 예산 표 |
| 하네스를 **새 프로젝트에** | `adopt` 스킬 (유일한 경로) — 실측 → 제안 승인 → 채움 승인 | `./scripts/install-git-hooks.sh` · `commit-msg` 정규식 = 실측 커밋 형식 | `adopt` 산출물 체크리스트 8개 |
| 이 저장소 사실이 바뀜 (문서 위치·명령) | `adopt` 재동기화 (1단계 diff 표 → 승인 → `harness-map.md`) | 훅 상수 | `verify.sh` |
| 안 하기로 한 것을 기록 | `docs/out-of-scope/README.md` 행 (이유·다시 볼 조건·결정일) | 출처가 외부면 `docs/references.md` "자른 것" | `check-doc-style.sh` |
| 이번 세션에서 하네스 결함을 발견 | `retro` 스킬 → 승인 후 `docs/audits/harness-retro.md` → 반영은 다시 승인 | 반영 층(규칙/스킬/훅/문서 SSOT)을 `retro` 4단계 표로 고른다 | 반영한 층의 검증 |

**구성 요소를 추가·삭제·개명한 뒤 반드시 확인하는 표 세 곳:** `core-workflow.md` 트랙 표·게이트 절 · `.claude/rules/README.md`(트리·Skills·Agents·Hooks) · 이 문서. 라우터가 없어진 스킬로 안내하면 거짓말을 한다.

## 예시 — 훅 하나를 추가하는 순서

"`git clean -fdx`도 막고 싶다"를 로드맵 둘째 행으로 따라가면 이렇게 된다.

1. `scripts/hook-cases.txt`의 `deny-dangerous-bash.sh` 절에 케이스를 먼저 넣는다 — 막을 입력(`git clean -fdx` → 2)과 막으면 안 되는 입력(`git clean -n` → 0). 이 시점에 `scripts/test-hooks.sh`는 실패해야 정상이다.
2. `.claude/hooks/deny-dangerous-bash.sh`의 grep 패턴에 `git clean -[a-zA-Z]*f`를 더한다. 새 파일을 만드는 게 아니라 기존 훅에 붙이는 이유는 이벤트·매처가 같기 때문이다.
3. `scripts/test-hooks.sh`를 돌려 새 케이스 둘과 기존 케이스 전부, python3 부재 내장 케이스가 통과하는지 본다.
4. `.claude/rules/README.md` Hooks 표의 그 행 설명에 "작업 트리 정리 삭제"를 추가한다. 이 문서의 훅 표도 같은 행을 고친다.
5. `scripts/verify.sh`를 돌린 뒤 커밋 분할안을 낸다. 훅과 케이스는 한 커밋이다.

새 이벤트(예: `PostToolUse`)가 필요한 경우만 새 파일 `.claude/hooks/{deny|warn|ask|auto}-*.sh`를 만들고 `.claude/settings.json`에 등록하며, 그때는 4단계에서 디렉터리 트리도 갱신한다.

## 관련 문서

- [`.claude/rules/README.md`](../../.claude/rules/README.md) — 구조 인덱스 (현행 목록의 SSOT)
- [`.claude/rules/harness-map.md`](../../.claude/rules/harness-map.md) — 축·슬롯·플래그 값
- [`README.md`](README.md) — 강제력 4개 레이어와 사이클의 관계
- [`../specs/cross-cutting/harness-slot-system-v2.md`](../specs/cross-cutting/harness-slot-system-v2.md) — 왜 이 구조인지 (설계·결정 이력)
- [`../references.md`](../references.md) — 각 장치를 어디서 가져왔나
