# Superchaeyeons

Claude Code·Codex용 **AI 하네스 템플릿** — 공통 규칙·스킬·검사와 도구별 안전장치를 프로젝트에 붙입니다. 두 도구의 승인 방식과 보호 범위는 아래 빠른 시작에서 설명합니다.

## 왜 필요한가

AI 코딩 에이전트에게 말로만 "주의하라"고 당부하면 같은 실수를 반복합니다. Superchaeyeons는 프롬프트 엔지니어링 대신 **규칙·스킬·훅·기계 검증**의 4개 레이어로 에이전트의 실행 경로 자체를 통제합니다.

아래 훅의 효과는 설치된 훅이 신뢰되어 실행되는 로컬 환경 기준입니다. Codex의 실제 실행 검증 범위는 뒤의 검증 상태와 작동 확인 절을 따릅니다.

| 흔한 AI 에이전트의 사고 | Superchaeyeons의 통제 방식 |
|-------------------------|---------------------------|
| 위험한 명령 실행 (`git push -f`, `git reset --hard`, `DROP TABLE`) | **훅(`deny-*`)이 셸 레벨에서 결정적으로 차단** |
| 테스트도 안 돌리고 "구현 완료했습니다" 거짓말 | **`Stop` 훅이 테스트 미실행 시 작업을 강제 되돌림** |
| 기획·스펙 문서와 코드가 다를 때 임의 구현 | **스스로 판단하지 않고 작업을 멈춘 뒤 질문(`ask-decisions`)** |
| "알아서 적당히 만들어줘" 같은 모호한 지시로 폭주 | **결정이 빈 요청이면 멈추고 질문하는 규칙 + 인터뷰 스킬(`ask-decisions`)** |
| 방금 수정한 자기 훅이나 설정을 스스로 해제 | **붙여 쓰는 프로젝트는 파일 쓰기 도구로 플러그인 훅·설정 등록을 고치지 못하게 훅이 막고, 설정 값 변경은 Claude 승인 창·Codex 명시적 확인** (Bash 편집은 규칙으로만 금지) |
| 승인 없이 커밋·삭제·의존성 추가 | **Claude는 승인 창(`ask-approval.sh`), Codex는 공통 사전 검사 후 명시적 확인** |

## 지원 범위와 검증 상태

공통 원본은 규칙 7개·스킬 8개·역할 3개입니다. 도구마다 호출·승인·기록 연결을 따로 둡니다. 2026-11-10 검수 결과는 다음과 같습니다.

| 항목 | 확인한 범위 |
|---|---|
| Claude Code | 기존 훅 회귀와 플러그인·마켓플레이스 정적 검사 통과. 로그인한 세션의 승인 창은 별도 확인 필요 |
| Codex 로컬 앱·CLI(명령줄 도구) | CLI에서 훅 12개 신뢰 후 위험 명령·보호 파일 차단, 패치·포맷 후처리, 테스트 없는 완료 차단·성공 후 허용, 메시지 기록 확인. test-writer의 셸 비활성화·모델 상속 확인. 앱 화면 검수는 별도 |
| Codex 승인 | 공통 사전 검사와 명시적 확인 절차. Claude 승인 창과 같은 강제력을 보장하지 않음 |
| 회고 | 현재 프로젝트 메시지 기록·분석·후보 검토 연결. 실제 유료 분석은 검수에서 실행하지 않음 |
| 전체 검사 | 9단계 통과. 입력 기반 검사와 설치 로딩 결과이며 실제 사용 환경의 실행 검증과 구분 |

세부 근거와 미검증 항목은 [연결 검수 보고서](docs/reports/2026-11-10-dual-harness-runtime.md)에 있습니다. 검수용 Claude CLI는 임시로 사용하며 검수 완료 후 삭제합니다. 배포는 `main` 반영 뒤 원격 새 설치 결과로 확인합니다. 로컬 검수와 원격 배포는 아래 절차에서 구분합니다.

## Claude Code 빠른 시작

원격 설치에는 marketplace와 plugin/이 해당 저장소 main에 반영돼 있어야 합니다. 작업 브랜치만 고친 상태에서는 로컬 경로 마켓플레이스로 검증합니다.

하네스는 Claude Code 플러그인 `superchaeyeons`로 배달됩니다. main에 반영하면 자동 업데이트를 선택한 Claude 프로젝트가 새 버전을 받습니다 — 복사하지 않습니다.

### 1단계: 플러그인 켜기

새 프로젝트의 `.claude/settings.json`에 아래를 넣고 커밋합니다. 폴더를 신뢰한 뒤 세션을 열면 Claude Code가 마켓플레이스를 받아 오고, 다음 세션(또는 `/reload-plugins`)부터 규칙·스킬·훅이 실립니다. 클라우드 세션은 저장소의 마켓플레이스를 추가하지 않아 하네스가 실리지 않습니다.

```json
{
  "extraKnownMarketplaces": {
    "superchaeyeons": { "source": { "source": "github", "repo": "chhezue/Superchaeyeons" }, "autoUpdate": true }
  },
  "enabledPlugins": { "superchaeyeons@superchaeyeons": true }
}
```

문서 템플릿(`docs/templates/`)을 쓰려면 그 폴더만 복사합니다.

### 2단계: 자동 환경 측정과 설정

플러그인이 실리면 세션 시작에 "하네스 설정이 비어 있다"는 알림이 뜨고, 에이전트가 `init-harness` 스킬을 먼저 제안합니다.

```text
/superchaeyeons:init-harness
```

저장소를 자동으로 실측해 언어·스택·테스트 명령을 파악하고 `.claude/harness.conf`의 설정값(축·슬롯·능력 플래그·승인 창 후보)을 제안합니다. 실측으로 정해지지 않는 것만 한 번에 하나씩 묻습니다. 승인하면 설정 파일과 `settings.json`의 권한 차단 목록까지 채워집니다.

### 3단계: 커밋 검사

따로 설치할 것이 없습니다. Claude가 커밋하면 하네스 승인 창 훅이 커밋 메시지 형식·문서 스타일·설정 `COMMIT_CHECK`를 먼저 검사하고, 통과하면 승인 창을 띄웁니다. 사람이 터미널에서 직접 하는 커밋은 검사하지 않습니다.

## Codex 빠른 시작

로컬 Codex 앱·CLI에서 사용할 수 있습니다. Codex 연결 도구에는 Python 3.11 이상이 필요합니다. 저장소 전체 검사에는 `plugin validate --json`을 지원하는 Claude Code CLI 2.1.259 이상도 필요합니다. 아래 명령은 사용자가 자신의 환경에서 플러그인을 설치할 때 실행합니다.

### 1단계: 설치와 프로젝트 연결

이 저장소의 변경이 원격 `main`에 반영된 뒤 터미널에서 실행합니다. 배포 전 검수는 GitHub 경로 대신 이 저장소의 로컬 경로를 마켓플레이스로 등록한 별도 실험 환경에서 진행합니다.

```bash
codex plugin marketplace add chhezue/Superchaeyeons
codex plugin add superchaeyeons@superchaeyeons
```

새 세션에서 `init-harness`를 요청하고 Claude / Codex / 둘 다를 선택합니다. 기존 Claude 프로젝트에 Codex를 더할 때도 같은 스킬을 사용하며, 공통 값은 `.claude/harness.conf` 한 개로 유지합니다. 프로젝트 설정·역할·명령 규칙은 변경안을 검토한 뒤 반영합니다. 도구를 다시 선택해도 다른 도구의 연결을 자동 삭제하지 않습니다.

### 2단계: 프로젝트와 훅 신뢰

**설치·프로젝트 신뢰·훅 신뢰는 별개입니다.** 연습용 프로젝트부터 아래 순서로 확인합니다.

1. Codex에서 해당 폴더를 열고 프로젝트 신뢰를 확인합니다. 신뢰되지 않은 프로젝트의 `.codex/config.toml`은 적용되지 않습니다.
2. CLI에서는 `/hooks`, 데스크톱 앱에서는 작성창의 **Review hooks** 또는 **Settings > Hooks**를 엽니다.
3. `superchaeyeons`의 훅 출처·명령·스크립트를 검토하고 사용자가 신뢰합니다. 현재 등록은 핸들러 12개이며 `untrusted`·검토 필요 상태로 남아 있으면 실행되지 않습니다.
4. 새 세션을 열어 시작 훅도 실행되게 한 뒤, 아래 작동 확인 표를 진행합니다.

훅 신뢰는 현재 정의와 스크립트의 해시를 기준으로 합니다. 업데이트로 훅이 달라지면 다시 검토해야 합니다. [공식 훅 신뢰 안내](https://learn.chatgpt.com/docs/hooks)를 따릅니다.

Claude는 기존 승인 창을 유지합니다. Codex에서는 공통 승인 사전 검사 뒤 구체적인 작업을 보여 주고 사용자 답을 기다립니다. Codex 명령 규칙은 지원하는 권한 경계에서만 보조하므로 두 도구의 승인 강제력이 같지는 않습니다. 로컬 훅이 지원되지 않는 클라우드 오케스트레이션은 이 보호 범위에 포함하지 않습니다.

### 3단계: 회고 루프

회고는 **기록 → 분석 → 후보 검토 → 승인된 개선 → 재발 확인** 순서입니다. 현재 프로젝트의 사용자 메시지 원문을 `.codex/corrections/sessions/`에 로컬 기록하고 버전 관리에서 제외합니다. 수집 훅은 정정 여부를 미리 분류하거나 모델을 호출하지 않습니다.

분석을 실행하면 추출·길이 제한한 메시지가 기존 Claude 분석기로 전달됩니다. 분석에는 Claude CLI가 별도로 필요하며 기존 모델·1달러 제한 설정을 유지합니다. 첫 분석은 사용자가 직접 실행하고, 이후에는 `AUTO_ANALYZE=1`·7일 경과·새 기록 등 기존 조건을 따릅니다. 개선 후보는 `improve-harness`로 근거를 검토한 뒤 승인된 것만 반영합니다.

## 신뢰 후 Codex 작동 확인

실제 코드와 전체 테스트 명령이 있는 연습용 저장소에서 확인합니다. Codex의 전체 테스트는 설정 `TEST_CMD`를 프로젝트 루트에서 단독 명령으로 실행합니다. 실제 종료 코드·작업 폴더·호출 ID·편집 세대를 대조하며 출력의 OK만으로 성공을 추측하지 않습니다. `init-harness`로 `HARNESS_SELF_EDIT=0`과 실제 테스트 명령을 설정하고, 원격 저장소는 연결하지 않습니다. 훅 입력을 직접 넣는 자동 검사와 달리, 이 단계는 Codex가 도구를 호출했을 때 실제 훅이 실행되는지 확인합니다.

| 확인할 것 | 연습용 프로젝트에서 할 일 | 통과 기준 |
|---|---|---|
| 규칙·스킬 로드 | 새 세션을 열고 `init-harness` 등 플러그인 스킬 확인 | 공통 규칙·프로젝트 설정이 로드되고 스킬을 사용할 수 있음 |
| 위험 명령 차단 | `BLOCK_FORCE_PUSH=1`에서 에이전트의 Bash 도구로 `git push --force --dry-run harness-probe HEAD` 호출 | 명령 실행 전에 하네스 차단 메시지가 나옴. 원격 없는 연습 저장소와 dry-run으로 검수 |
| 보호 파일 차단 | 에이전트의 apply_patch로 `.codex/config.toml`에 주석 추가 시도 | 훅이 차단하고 파일 내용이 그대로 유지됨 |
| 완료 검증 | 코드 수정 뒤 미실행 / 실패 / 성공 / 성공 후 재수정을 각각 별도 시나리오로 확인 | 미실행·실패·재수정 뒤 완료는 Stop이 막고, 마지막 수정 후 전체 테스트 성공만 인정 |
| 회고 기록 | 새 사용자 메시지를 보낸 뒤 자체 JSONL(줄마다 JSON 객체를 담는 형식) 기록 확인 | `.codex/corrections/sessions/`에 메시지가 기록되고 Claude 기록과 섞이지 않음 |
| 역할 제한 | 생성한 test-writer를 실제 호출해 도구 목록 확인 | 셸 도구가 비활성화되고 모델 설정을 별도로 덮어쓰지 않음 |

이 표의 명령·패치는 **Codex가 도구로 호출**해야 훅 검증이 됩니다. 사람이 터미널에서 실행하거나, 모델이 호출 자체를 거절하거나, 플랫폼 권한이 먼저 막은 결과는 하네스 차단 성공으로 세지 않습니다. 전체 테스트가 성공했는데도 완료를 막거나 결과 형식 경고가 나오면 미검증 상태로 두고 이벤트 입력과 응답 연결을 확인합니다.

## GitHub 배포와 업데이트

이 저장소의 배포는 **검증된 변경을 원격 `main`에 반영하고, GitHub 경로로 새로 설치해 확인하는 것**입니다. 별도 서버 배포는 없습니다. 저장소가 공개이면 다른 사용자도 경로로 설치할 수 있고, 비공개이면 접근 권한이 필요합니다. 공식 플러그인 디렉터리 등록은 별도 절차입니다. [마켓플레이스 배포 안내](https://developers.openai.com/plugins/build/plugins)를 참고합니다.

1. **배포 전 검수** — `plugin/scripts/dev.sh test`와 연습용 프로젝트의 양쪽 실제 실행을 확인합니다. 미검증 항목은 보고서에 남깁니다.
2. **검토 후 main 반영** — 기본 절차는 파일·커밋 검토 후 작업 브랜치를 push하고 변경 검토 요청(PR)을 거쳐 merge하는 것입니다. 사용자가 PR 없는 직접 반영을 명시적으로 승인했다면 그 범위에서 main에 반영합니다. 이번 반영은 2026-11-10 사용자의 직접 반영 승인을 따릅니다. 개인 설정 변경은 분리합니다.
3. **원격 새 설치** — 로컬 경로 대신 `chhezue/Superchaeyeons`에서 새로 설치해 스킬·훅·설정이 도착하는지 확인합니다. 로컬 소스만 검사한 것으로 배포를 완료 처리하지 않습니다.
4. **사용 환경에서 재확인** — Codex 훅 신뢰와 위 작동 확인을 진행하고, 배포한 커밋과 결과를 기록합니다. Claude도 새 세션에서 스킬·규칙·승인 창을 확인합니다.

기존 Codex 설치를 갱신할 때는 터미널에서 마켓플레이스와 설치 캐시를 차례로 갱신합니다. 명령은 현재 설치본의 도움말과 재설치 실험으로 확인했습니다.

```bash
codex plugin marketplace upgrade superchaeyeons
codex plugin add superchaeyeons@superchaeyeons
```

갱신 뒤 새 세션에서 훅 신뢰를 다시 확인합니다. 생성 역할은 플러그인 업데이트 뒤 `init-harness`로 재동기화합니다.

Claude는 자동 업데이트를 선택했다면 시작 때 갱신 여부를 확인합니다. 수동 갱신은 아래 명령을 터미널에서 실행하고 새 세션을 열거나 세션 안에서 `/reload-plugins`를 실행합니다. [Claude 플러그인 명령 안내](https://code.claude.com/docs/en/plugins/cli-reference)를 따릅니다.

```bash
claude plugin marketplace update superchaeyeons
claude plugin update superchaeyeons@superchaeyeons --scope project
```

## 에이전트의 작업 순서 (12단계 워크플로)

Superchaeyeons를 장착한 에이전트는 프롬프트 한마디에 바로 코드를 건드리지 않습니다. 아래 표는 AI 개발 워크플로 12단계(`AI_Harness_Guide` 기반)마다 하네스의 어떤 장치가 맡는지 대조한 것입니다. 9단계만 하네스 공통 부품이 맡지 않습니다. 모든 작업이 12단계를 다 거치지는 않습니다 — 오타·한 줄 수정(S)은 바로 고치고 검증 명령만 돌리며, 3개 이상 파일이나 API·DB를 건드리는 작업(L)만 독립 리뷰와 작업 보고서까지 남깁니다(`core-workflow.md` 규모 표).

| 단계 | 작업 내용 | 하네스의 통제 장치 |
|:---:|---|---|
| **0** | **저장소 탐색 (Exploration)**<br>구조·스택·컨벤션을 읽어 멘탈 모델 수립 | `init-harness` 자동 실측 및 진입 문서 확인 순서 |
| **1** | **요구사항 분석 (Requirements)**<br>모호한 부분을 질문하고 범위 확정 | `ask-decisions` 스킬 (라운드 인터뷰) |
| **2** | **불변 조건 정의 (Invariant & Acceptance Criteria)**<br>절대 깨지면 안 되는 조건과 완료 기준 확정 | G2 승인 게이트 & `write-spec` 스펙 문서 |
| **3** | **외부 지식 조사 (Research)**<br>최신 라이브러리 문서·공식 사양 확인 | G1 리서치 게이트 & `researcher` 에이전트 |
| **4** | **결정 기록 (ADR)**<br>설계 대안 비교 및 트레이드오프 기록 | `{{결정 기록}}` 슬롯 (ADR 템플릿) |
| **5** | **컨텍스트 갱신 (Rules Update)**<br>새로 합의된 결정을 규칙 문서에 동기화 | G4 문서 갱신 점검 |
| **6** | **작업 분해 (Task Breakdown)**<br>독립 검증 가능한 단위로 태스크 쪼개기 | G2 다단계 계획 (`1. [단계] → verify: [확인]`) — 강제 수단은 없음 |
| **7** | **실행 환경 사전 검증 (Preflight)**<br>구현 전 빌드·의존성·테스트 동작 확인 | `verify-work` 사전 모드 |
| **8** | **핵심 구현 루프 (Task Loop)**<br>계획 ➜ 선행 테스트 ➜ 구현 ➜ 실행 ➜ 셀프리뷰 ➜ 커밋 | `test-first` 스킬(승인된 테스트 먼저 지점·버그 수정) · `core-testing.md` · 커밋 전 승인 |
| **9** | **동시성·부하·실패 테스트**<br>단위 테스트로 잡히지 않는 한계 검증 | 공통 부품에는 없음. 프로젝트에 리뷰어 에이전트가 있으면 `verify-work`가 부른다 |
| **10**| **독립 코드 리뷰 (Independent Review)**<br>확증 편향 없는 제3의 시선으로 검토 | 구현 대화를 모르는 별도 컨텍스트 리뷰 — 코드는 `code-review`·`simplify`, 문서는 `doc-reviewer` |
| **11**| **문서화 및 작업 보고 (Report)**<br>사용자 문서와 작업 한계·결정사항 기록 | `report.md` (검증하지 못한 것 명시) |

## 핵심 구조: 4개 레이어와 3층 권한

하네스는 **강제력**을 기준으로 4개 레이어로 나뉘고, **수정 권한**을 기준으로 3개 층으로 나뉩니다.

```text
[ 4개 강제력 레이어 ]
1. 규칙 (Rules)      : 행동 원칙 규정 (모호하면 멈추고 질문)
2. 스킬 (Skills)     : 표준 절차 강제 (사양 확정 → 안전 리팩터링 → 검증)
3. 훅 (Hooks)        : 위험 명령과 거짓 완료를 셸 레벨에서 차단
4. 기계 검증 (Tests) : 이식성·문서 스타일·훅 규약을 스크립트로 판정
```

```text
[ 수정 권한 3층 구조 ]
- Core (부품) : core-*.md, 공통 훅, 공통 스킬 (붙여 쓰는 프로젝트에서 수정 금지)
- 설정 (연결) : .claude/harness.conf (init-harness 스킬이 프로젝트 실측값으로 채움)
- Local (고유): local-*.md (각 프로젝트 고유의 도메인·기술 스택 규칙)
```

이 구조 덕분에 새 프로젝트에 붙일 때 **Core 규칙 파일을 단 한 줄도 고치지 않고** 그대로 재사용합니다.

## 디렉터리 안내

저장소 구성과 새 프로젝트 배달 여부입니다.

| 경로 | 내용 | 배달 여부 |
|------|------|:---------:|
| `.claude/harness.conf` | 프로젝트 설정 — 슬롯·플래그·훅 판정 값. 붙이는 프로젝트는 `init-harness`가 채운다 | 프로젝트 값 |
| `.claude/rules/README.md` | 구성 요소 목록 SSOT — 이 저장소 전용 | 저장소 전용 |
| `.claude-plugin/marketplace.json` · `plugin/` | 플러그인 `superchaeyeons` — 규칙(`plugin/rules/`, 훅이 주입) · 스킬(`plugin/skills/`) · 에이전트(`plugin/agents/`) · 훅(`plugin/hooks/`, 등록 `hooks.json`) · 도구(`plugin/scripts/`: 빌드·실행 엔진 `dev.sh`, 이식성·문서 검사기, `init-harness-probe.sh`, 회고 분석 `analyze-corrections.sh`, 글 다듬기 `polish-with-gemini.sh`) | 배달 (플러그인) |
| `plugin/.codex-plugin/plugin.json` · `plugin/hooks/codex.json` | Codex 등록. 같은 skills/·rules/·검사 도구를 읽고 도구별 입력·출력을 연결 | 플러그인 |
| `plugin/codex/INSTRUCTIONS.md` | Codex 호출·승인·기록 연결 안내 | 플러그인 |
| `.codex/config.toml` · `.codex/agents/` · `.codex/rules/` | init-harness가 생성하는 프로젝트 연결. 전역 설정·훅 신뢰는 자동 변경하지 않음 | 프로젝트 값 |
| `scripts/` | 이 저장소 전용 — `verify.sh`(검사 묶음) · 훅 케이스 `test-hooks.sh` · 엔진 테스트 `test-dev.sh` · 플러그인 검사기 `check-plugin.sh` | 저장소 전용 |
| `docs/templates/` | 산출물 등록부 및 문서 템플릿 | 배달 |
| `examples/` | 채운 예 — 옛 복사 배달 형식 `harness-map.md`(`baro/`)·GitHub 트래커 안내(`tracker-github/`) | 참고 자료 |
| `AGENTS.template.md` · `.github/CONTRIBUTING.md` | 새 프로젝트 `AGENTS.md` 견본 · Git 컨벤션 견본 | 견본 |
| `docs/harness/` | 4개 레이어 설명과 현재 동작 요약 | 저장소 전용 |
| `docs/` 나머지 | 이 저장소의 스펙·보고서·설계 기록·안 하기로 한 것 | 저장소 전용 |

## 자체 검증 명령

이 저장소 자체의 부품 계약, 훅 규약, 문서 스타일을 한 번에 검증하는 명령입니다.

```bash
./plugin/scripts/dev.sh test   # scripts/verify.sh를 부른다
```

## 더 읽어보기

- [구성 요소 목록](.claude/rules/README.md): 규칙·스킬·에이전트·훅의 로드 시점과 수정 가이드
- [하네스 레이어와 현재 동작](docs/harness/README.md): 4개 레이어와 지금 실제로 일어나는 일
- [하네스 엔지니어링 기록](docs/harness-engineering.md): 설계 철학과 실제 인시던트 해결 과정
- [참고 자료 및 출처](docs/references.md): 영감을 받은 선행 연구와 차용한 개념
- [상세 적용 순서](plugin/skills/init-harness/SKILL.md): init-harness의 측정·승인·도구별 설정 절차
