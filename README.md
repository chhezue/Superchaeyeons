# Superchaeyeons

Claude Code용 **AI 하네스 템플릿** — 에이전트의 임의 판단과 위험한 행동을 물리적으로 차단하고, 어느 프로젝트에나 규칙 수정 없이 붙여 쓰는 개발 환경을 제공합니다.

## 왜 필요한가

AI 코딩 에이전트에게 말로만 "주의하라"고 당부하면 같은 실수를 반복합니다. Superchaeyeons는 프롬프트 엔지니어링 대신 **규칙·스킬·훅·기계 검증**의 4개 레이어로 에이전트의 실행 경로 자체를 통제합니다.

| 흔한 AI 에이전트의 사고 | Superchaeyeons의 통제 방식 |
|-------------------------|---------------------------|
| 위험한 명령 실행 (`git push -f`, `git reset --hard`, `DROP TABLE`) | **훅(`deny-*`)이 셸 레벨에서 결정적으로 차단** |
| 테스트도 안 돌리고 "구현 완료했습니다" 거짓말 | **`Stop` 훅이 테스트 미실행 시 작업을 강제 되돌림** |
| 기획·스펙 문서와 코드가 다를 때 임의 구현 | **스스로 판단하지 않고 작업을 멈춘 뒤 질문(`ask-decisions`)** |
| "알아서 적당히 만들어줘" 같은 모호한 지시로 폭주 | **결정이 빈 요청이면 멈추고 질문하는 규칙 + 인터뷰 스킬(`ask-decisions`)** |
| 방금 수정한 자기 훅이나 설정을 스스로 해제 | **붙여 쓰는 프로젝트는 파일 쓰기 도구로 플러그인 훅·설정 등록을 고치지 못하게 훅이 막고, 설정 값을 고치면 승인 창** (Bash 편집은 규칙으로만 금지) |
| 승인 없이 커밋·삭제·의존성 추가 | **훅(`ask-approval.sh`)이 사용자 화면에 승인 창 — 자동 모드에서도 뜬다** |

## 3단계 빠른 시작

하네스는 Claude Code 플러그인 `superchaeyeons`로 배달됩니다. 이 저장소에 커밋하면 붙인 프로젝트가 자동 업데이트로 새 버전을 받습니다 — 복사하지 않습니다.

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
- Core (부품) : core-*.md, 공통 훅, 공통 스킬 (수정 금지, 100% 이식성 보장)
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
| `scripts/` | 이 저장소 전용 — `verify.sh`(검사 묶음) · 훅 케이스 `test-hooks.sh` · 엔진 테스트 `test-dev.sh` · 플러그인 검사기 `check-plugin.sh` · git 훅과 설치기 | 저장소 전용 |
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
- [상세 적용 순서](AGENTS.md): init-harness 단계별 상세 동작 원리
