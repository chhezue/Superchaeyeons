# Superchaeyeons

Superchaeyeons는 Claude Code와 Codex가 프로젝트의 개발 절차를 따르도록 돕는 플러그인입니다. 로그 문구 한 줄은 에이전트가 직접 고쳐도 됩니다. 반면 데이터베이스 스키마를 바꿀 때는 기존 데이터에 어떤 영향을 줄지 사람이 먼저 확인해야 합니다. 두 작업 모두 코드를 고친 뒤에는 테스트 결과를 확인해야 합니다.

이렇게 **에이전트가 판단할 일, 사람이 승인할 일, 코드로 검사할 조건**을 정해 둔 개발 환경을 이 프로젝트에서는 **하네스**라고 부릅니다.

[Claude Code 빠른 시작](#claude-code-빠른-시작) · [Codex 빠른 시작](#codex-빠른-시작) · [디렉터리 안내](#디렉터리-안내)

## 어디까지 에이전트에게 맡길까

에이전트는 요청을 받으면 **무슨 작업인지, 무엇을 바꾸는지**부터 살핍니다. 작업 종류에 따라 사람이 결정할 내용이 달라지고, 변경 범위에 따라 검증에 들이는 노력이 달라집니다.

| 요청 | 에이전트와 사람이 하는 일 |
|---|---|
| 로그 메시지의 오타를 고쳐 주세요 | 에이전트가 문구를 고치고 테스트합니다. |
| 결제 내역에 새 필드를 저장해 주세요 | 데이터베이스 스키마를 바꿔야 한다면 에이전트가 변경 범위와 검증 방법을 적습니다. 사람이 승인한 뒤 구현하고, 구현 대화를 보지 않은 에이전트가 결과를 리뷰합니다. |
| 결제 내역 조회 오류를 고쳐 주세요 | 에이전트가 오류를 재현하고 원인 가설과 수정 범위를 제시합니다. 사람이 수정 범위를 승인하면 에이전트가 버그를 재현하는 테스트를 작성하고 코드를 고칩니다. |

승인을 요청하는 기준은 변경의 영향입니다. 결제 정책이나 외부 API 계약을 바꾸면 호출자에게도 영향이 가므로 사람이 결정합니다. 구현 후에는 외부 계약·데이터 스키마·인증처럼 변경 영향이 큰 작업은 독립 리뷰를 한 번 거칩니다. 같은 문구를 여러 파일에서 수정하는 작업은 대상과 관련 검사만 확인합니다. 구현하면서 세운 가정을 리뷰에서도 그대로 받아들일 가능성을 줄이기 위해서입니다. [승인이 필요한 변경](plugin/rules/core-approval-triggers.md) · [작업별 절차](plugin/rules/core-task-steps.md)

## 무엇을 코드로 검사할까

“작업을 마치면 테스트하세요”라는 규칙은 에이전트가 기억하고 따라야 합니다. 그래서 **완료를 보고하는 순간**에 실행 기록을 확인하는 훅을 뒀습니다. 훅은 도구를 호출하거나 대화를 끝내려 할 때 자동으로 실행되는 코드입니다.

예를 들어 에이전트가 전체 테스트를 통과한 뒤 코드 한 줄을 더 고쳤다고 해 보겠습니다. 앞선 테스트는 수정 전 코드의 결과입니다. 에이전트가 그대로 완료를 보고하면 종료 훅이 이를 막습니다. 마지막 수정 뒤 전체 테스트가 성공해야 완료 검사를 통과합니다. 명령 실행 전에는 별도의 훅이 동작합니다. 예를 들어 프로젝트가 강제 푸시를 금지하면 에이전트가 원격 이력을 덮어쓰기 전에 명령을 막습니다. [도구별 훅 동작](docs/harness/README.md)

**스펙을 해석하는 일은 에이전트에게 남겨 뒀습니다.** 초기 Claude 실험에서 스펙에 적힌 만료 시간은 15분이었습니다. 하네스 없이 “알아서 정해 달라”고 하자 에이전트는 세 번 모두 30분을 골랐습니다. 규칙까지 제공한 조건에서는 세 번 모두 스펙을 지켰습니다. 훅만 켠 조건에서는 금지한 명령 시도 다섯 번을 모두 막았지만, 만료 시간은 세 번 중 한 번 잘못 정했습니다. 이 사례에서 명령을 막는 일과 스펙에 맞는 값을 고르는 일에는 서로 다른 장치가 필요했습니다. [실험 조건과 결과](docs/reports/2026-10-16-harness-effect-measurement.md)

커밋처럼 사람의 승인이 필요한 행동은 도구에 맞게 처리합니다. Claude Code는 커밋 메시지와 프로젝트 검사를 확인한 뒤 승인 창을 띄웁니다. Codex는 같은 기준으로 사전 검사한 뒤 실행할 내용을 보여 주고 사용자의 답을 기다립니다. 이 절차는 로컬에서 에이전트가 실행하는 커밋에 적용됩니다.

## 같은 실수를 다음 작업에서 줄이려면

사용자가 같은 문제를 여러 번 지적해도 새 대화에서는 그 이유가 사라지기 쉽습니다. 하네스는 작업 중 받은 피드백을 기록하고, 회고할 때 반복된 지적과 근거가 된 대화를 함께 보여 줍니다. 사람은 그 근거를 보고 규칙이나 검사를 고칠지 결정합니다. 바꾼 뒤에는 같은 지적이 다시 나오는지도 확인합니다. [회고 절차와 기록 방식](docs/harness/README.md)

## 다른 프로젝트에서도 쓰려면

처음 하네스를 다른 저장소에 옮겼을 때는 파일 21개를 고쳐야 했습니다. 원래 프로젝트의 경로와 빌드 방식이 공통 규칙 안에 들어 있었기 때문입니다. 지금은 **마지막 코드 수정 뒤 전체 테스트를 확인한다**는 기준을 플러그인에 두고, **무슨 명령으로 전체 테스트를 돌릴지**는 각 프로젝트의 설정에 둡니다. [설계 변경 기록](docs/harness-engineering.md)

새 프로젝트에서는 초기 설정 도구인 `init-harness`가 저장소를 읽고 테스트 명령과 문서 경로를 제안합니다. 사용자가 승인하면 설정을 채웁니다. Claude Code와 Codex를 함께 쓰는 프로젝트도 공통 설정 한 벌을 사용합니다. [초기 설정 절차](plugin/skills/init-harness/SKILL.md)

## Claude Code 빠른 시작

로컬 Claude Code 세션에서 설정합니다. 처음 써 본다면 코드와 테스트가 있는 연습용 저장소에서 시작하세요.

1. 프로젝트의 `.claude/settings.json`에 아래 두 항목을 추가하고 커밋합니다. 기존 설정이 있으면 해당 항목에 합칩니다.

   ```json
   {
     "extraKnownMarketplaces": {
       "superchaeyeons": { "source": { "source": "github", "repo": "chhezue/Superchaeyeons" }, "autoUpdate": true }
     },
     "enabledPlugins": { "superchaeyeons@superchaeyeons": true }
   }
   ```

2. Claude Code에서 프로젝트 폴더를 신뢰하고 세션을 엽니다. 플러그인이 로드되면 `/superchaeyeons:init-harness`를 실행합니다. 이미 열린 세션이라면 `/reload-plugins`로 다시 불러올 수 있습니다.
3. 제안된 테스트 명령, 작업 범위, 승인이 필요한 행동을 검토합니다. 승인하면 프로젝트에 `.claude/harness.conf`가 생깁니다.

## Codex 빠른 시작

로컬 Codex 앱 또는 Codex CLI(명령줄 도구)를 사용합니다. 프로젝트 설정을 생성하려면 Python 3.11 이상이 필요합니다. 처음에는 전체 테스트 명령이 있는 연습용 저장소를 준비하세요.

1. 터미널에서 마켓플레이스를 등록하고 플러그인을 설치합니다.

   ```bash
   codex plugin marketplace add chhezue/Superchaeyeons
   codex plugin add superchaeyeons@superchaeyeons
   ```

2. 프로젝트를 열고 폴더를 신뢰합니다. 새 대화에서 `init-harness`를 요청한 뒤 Codex 또는 두 도구 모두를 선택합니다. 기존 Claude 프로젝트에 Codex를 추가할 때도 같은 절차를 따릅니다.
3. CLI에서는 `/hooks`, 앱에서는 **Settings > Hooks**를 엽니다. `superchaeyeons`의 훅을 검토하고 신뢰합니다. Codex는 사용자가 신뢰한 훅만 실행합니다.
4. 같은 프로젝트에서 새 대화를 열고 에이전트에게 작은 코드 수정을 요청합니다. 프로젝트 루트에서 세션의 설정 표에 표시된 전체 테스트 명령을 단독으로 실행한 뒤 완료를 보고하는지 확인합니다. [설치 후 실행 검수 사례](docs/reports/2026-11-10-dual-harness-runtime.md)

회고 훅을 신뢰하면 Codex는 메시지를 보낼 때마다 현재 프로젝트의 사용자 메시지 원문을 `.codex/corrections/sessions/`에 로컬로 저장합니다. 첫 분석은 사용자가 직접 시작합니다. 분석 시 길이를 제한한 메시지를 Claude CLI에 전달하며 실행당 비용 상한은 1달러입니다. 이후에는 `AUTO_ANALYZE=1`이고 마지막 분석에서 7일이 지났으며 새 기록이 있을 때 자동 분석합니다.

## 검증 범위

2026년 11월 10일, 연습용 저장소의 Codex CLI에서 훅을 신뢰한 뒤 실제 도구 호출로 검증했습니다. 위험 명령과 보호 파일 수정을 차단했고, 코드 수정 후 테스트 없이 완료를 보고하면 종료를 막았습니다. 같은 대화에서 전체 테스트가 성공하자 완료를 허용했습니다. Claude는 매니페스트와 기존 훅 회귀 검사를 수행했습니다. 로그인한 Claude의 승인 창과 Codex 앱 화면은 당시 검수 범위 밖이었습니다. [검수 환경과 결과](docs/reports/2026-11-10-dual-harness-runtime.md)

이 저장소 자체를 수정했다면 루트에서 아래 명령을 실행합니다. 플러그인 등록 검사에는 Claude Code CLI 2.1.259 이상이 필요합니다.

```bash
plugin/scripts/dev.sh test
```

## GitHub 배포와 업데이트

검사한 변경을 검토 후 원격 `main`에 반영합니다. 배포를 확인할 때는 GitHub 경로로 새로 설치하고 연습용 프로젝트에서 스킬과 훅을 확인합니다.

<details>
<summary>설치한 플러그인 업데이트하기</summary>

Claude Code는 위 설정에서 자동 업데이트를 사용합니다. 수동으로 갱신하려면 아래 명령을 실행한 뒤 새 세션을 열거나 `/reload-plugins`를 실행합니다.

```bash
claude plugin marketplace update superchaeyeons
claude plugin update superchaeyeons@superchaeyeons --scope project
```

Codex는 마켓플레이스를 갱신한 뒤 플러그인을 다시 추가합니다.

```bash
codex plugin marketplace upgrade superchaeyeons
codex plugin add superchaeyeons@superchaeyeons
```

새 대화에서 변경된 훅을 다시 검토하고, `init-harness`로 프로젝트의 에이전트 역할 설정도 갱신합니다.

이전 버전의 호출 이름을 직접 쓴 프로젝트는 아래 표에 맞춰 로컬 지침과 단축 명령을 갱신합니다. `init-harness`는 같은 이름으로 실행합니다.

| 이전 이름 | 현재 이름 | 언제 여나 |
|---|---|---|
| `core-workflow` | [core-task-steps.md](plugin/rules/core-task-steps.md) | 작업 종류·규모를 고르고 구현·검증 순서를 정할 때 |
| `core-gates` | [core-approval-triggers.md](plugin/rules/core-approval-triggers.md) | 어떤 결정을 사용자가 승인해야 하는지 볼 때 |
| `core-guardrails` | [core-stop-conditions.md](plugin/rules/core-stop-conditions.md) | 문서 충돌이나 계약 불일치로 작업을 멈춰야 하는지 볼 때 |
| `ask-decisions` | [clarify-requirements](plugin/skills/clarify-requirements/SKILL.md) | 구현 결과를 바꾸는 요구사항을 확인할 때 |
| `improve-harness` | [review-harness-feedback](plugin/skills/review-harness-feedback/SKILL.md) | 회고에서 수집한 개선 후보를 검토할 때 |


</details>

## 디렉터리 안내

| 위치 | 용도 | 새 프로젝트에서 쓰는 방식 |
|---|---|---|
| [plugin/](plugin/) | 작업 규칙, 스킬, 리뷰 등 역할별 에이전트, 훅, 실행·검사 스크립트 | 플러그인으로 설치 |
| [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) · [Codex 매니페스트](plugin/.codex-plugin/plugin.json) | 플러그인 검색과 도구별 등록 | 마켓플레이스와 설치 도구가 읽음 |
| [.claude/harness.conf](.claude/harness.conf) · `scripts/dev.conf` | 프로젝트의 승인 정책, 문서 경로, 빌드·테스트 명령 | `init-harness`가 프로젝트에 맞게 작성 |
| `.codex/config.toml` · `.codex/agents/` · `.codex/rules/` | Codex 프로젝트 설정, 역할, 명령 규칙 | Codex를 선택하면 프로젝트에 생성 |
| [docs/templates/](docs/templates/) · [AGENTS.template.md](AGENTS.template.md) · [기여 안내](.github/CONTRIBUTING.md) | 문서 템플릿과 프로젝트 지침 견본 | 필요할 때 복사해 사용 |
| [구성 요소 목록](.claude/rules/README.md) · [scripts/](scripts/) | 부품 목록과 하네스 자체 검사 | 이 저장소에서 유지보수할 때 사용 |
| [docs/](docs/) · [examples/](examples/) | 설계 결정, 실험 보고서, 프로젝트별 설정 예시 | 참고 자료 |
