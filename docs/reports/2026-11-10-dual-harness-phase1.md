# 공동 지원 설치·차단 연결 — 보고서

Claude 플러그인을 유지한 채 Codex 연결을 추가하는 스펙을 승인 상태로 기록하고, 격리된 임시 환경에서 설치·활성화·훅 발견·캐시 갱신을 확인했다. Codex 차단 연결을 추가하고 독립 테스트를 검증했다. 이 문서는 설치·차단 단계 당시의 결과이며, 이후 전체 검증과 남은 항목은 [최종 연결 보고서](2026-11-10-dual-harness-runtime.md)를 따른다.

## 무엇을 했나

- 공동 지원 스펙 최종 검수 후 2026-11-10 사용자 진행 승인을 기록했다.
- 사용자 전역 설정 대신 `/private/tmp/harness-codex-phase1-u1x57ibn/home`을 CODEX_HOME으로 사용했다. 사용자 인증 파일은 복사하지 않았다.
- 원격 main과 작업 브랜치 게시 상태를 읽기 전용으로 확인했다.
- production Claude 등록·settings·기존 사용자 변경은 보존했다. 승인 후 Codex 차단 연결과 공통 경로 판정의 Codex 자기 수정 보호를 추가했다.
- 등록 정적 검사 모드와 독립 테스트를 추가하고 전체 검사에 연결했다.

## 결정

실험 결과로 아래 형식을 선택했다. 사용자에게 쉬운 말로 차단 연결을 설명한 뒤 “응, 추가해줘” 승인을 받아 적용했다.

| 결정 | 근거 | 대안 |
|---|---|---|
| Codex 전용 호환 매니페스트 사용 | 현재 CLI는 루트 plugin.json만으로 설치하면 missing plugin.json. .codex-plugin/plugin.json 추가 시 성공 | 최신 문서의 루트 확장은 현재 설치본에서 사용 보류 |
| Codex 훅 등록 파일 별도 지정 | hooks/list에서 지정 파일만 발견. 기본 hooks/hooks.json의 별도 훅은 발견되지 않음 | Claude 기본 등록 교체는 하지 않음 |
| 설치와 신뢰를 별도 상태로 유지 | installed/enabled true인데 trustStatus untrusted | 자동 신뢰·우회 옵션 사용 금지 |

## 검증

공식 근거와 설치본 결과를 구분했다. CLI 버전은 공동 지원 스펙에 기록돼 있다.

| 검증 | 실행한 명령·방법 | 결과 |
|---|---|---|
| 원격 상태 | git ls-remote origin refs/heads/main refs/heads/feat/harness-plugin-delivery | main은 62a5d94, 작업 브랜치는 결과 없음. 1~7단계 커밋은 원격 main에 없음 |
| 임시 마켓플레이스 | codex plugin marketplace add 임시경로 --json | 성공 |
| 루트 형식 | codex plugin add harness-phase1@harness-phase1-market --json | missing plugin.json 실패 |
| 호환 형식 | .codex-plugin/plugin.json 추가 뒤 같은 설치 명령 | 성공, 별도 설치 캐시 생성 |
| 활성화 | codex plugin list --json | installed true, enabled true |
| 실제 플러그인 설치 | 저장소 plugin/ 복사본을 임시 마켓플레이스에서 설치 후 hooks/list | version local로 성공. superchaeyeons의 Bash 및 apply_patch 등록 발견, untrusted 유지 |
| 훅 발견 | 설치본 생성 JSON Schema의 hooks/list를 app-server stdio로 호출 | 지정한 hooks/codex.json 하나만 발견, warnings/errors 없음 |
| 신뢰 | 같은 hooks/list 결과 | untrusted. 설치 성공과 다름 |
| 소스 변경 | 원본 명령만 변경 후 캐시 파일 확인 | 재설치 전 기존 캐시 유지 |
| 같은 버전 재설치 | plugin add 재실행 후 캐시·hooks/list 대조 | 변경 명령 반영, hash 변경, 여전히 untrusted |

설치 실험 원본과 RPC 출력은 임시 폴더에서 확인했다. 이 문서에 결과를 남기고 임시 검수 파일은 마무리 때 삭제한다. 원본 소스 변경 뒤 캐시 갱신과 해시 변경을 확인했지만, 이미 신뢰한 훅의 신뢰 철회는 시험하지 않았다.

## 승인받아 적용한 등록 diff

이 절은 승인받아 적용한 등록 값이다. 입력 판정 테스트의 실패를 먼저 확인하고 연결 코드와 함께 적용했다.

`plugin/.codex-plugin/plugin.json`을 새로 만든다. 기존 Claude 매니페스트와 marketplace는 바꾸지 않는다.

```json
{
  "name": "superchaeyeons",
  "description": "공통 하네스의 Codex 연결",
  "skills": "./skills/",
  "hooks": "./hooks/codex.json"
}
```

`plugin/hooks/codex.json`에 적용한 diff는 아래와 같다. 승인 후 적용했다. Codex의 실제 도구 입력은 공식 문서 기준 Bash와 apply_patch 모두 tool_input.command다. 이벤트 매처는 Bash|apply_patch를 사용한다.

```diff
--- /dev/null
+++ plugin/hooks/codex.json
@@ -0,0 +1,16 @@
+{
+  "hooks": {
+    "PreToolUse": [
+      {
+        "matcher": "Bash|apply_patch",
+        "hooks": [
+          {
+            "type": "command",
+            "command": "python3 -I \"${PLUGIN_ROOT}/hooks/deny-codex-tool.py\" || exit 2"
+          }
+        ]
+      }
+    ]
+  }
+}
```

단계 2는 차단 연결만 다룬다. ask 훅과 Claude 입력 전용 스크립트를 Codex에 직접 등록하지 않는다. python3 부재·실행 실패는 shell에서 exit 2로 바꾼다. 최초 제안의 존재 확인만으로는 실행 불가를 놓칠 수 있어 보완했다. 실제 런타임 자체 오류가 차단되는지는 별도 검증한다. 등록은 추가했으며 사용자 전역 설치·활성화·훅 신뢰는 변경하지 않았다.

추가·수정 파일은 다음과 같다. 위험 명령 판정 본문은 바꾸지 않고 기존 스크립트를 그대로 호출한다.

| 파일 | 작업 |
|---|---|
| scripts/hook-cases.txt | Codex 정상·깨진 입력·다중 패치·경로 이탈·이동 대상·명령의 케이스 먼저 추가 |
| plugin/hooks/deny-codex-tool.py | Codex 입력을 공통 작업으로 바꾸고 기존 정책을 호출하는 연결 추가 |
| plugin/hooks/deny-out-of-scope-write.sh | 필요한 경우에만 기존 판정을 공통 호출로 추출, Claude 입력·출력 보존 |
| plugin/hooks/deny-dangerous-bash.sh | 필요한 경우에만 명령 판정을 공유, Claude 입력·출력 보존 |
| plugin/.codex-plugin/plugin.json | 위 값으로 설치 등록 추가 |
| plugin/hooks/codex.json | 검증된 차단 연결 등록 추가 |
| scripts/test-hooks.sh·scripts/check-plugin.sh | 도구별 등록·판정 검사 추가, 기존 Claude 검사 유지 |
| .claude/rules/README.md·docs/harness/README.md | 새 연결 목록과 실제 보호 범위 기록 |

등록 검사 계약은 [스펙의 등록 검사 계약](../specs/cross-cutting/codex-harness-delivery.md#등록-검사-계약)을 따른다. 최초 요청 때 계약이 없어 test-writer가 작성을 보류했고, 검사 도구의 호출 계약을 명시한 뒤 테스트 작성을 재개했다. Codex 차단 등록은 이후 사용자 승인으로 적용했고 Claude settings는 변경하지 않았다.

이동·삭제는 없다. `.claude/settings.json`과 사용자 전역 설정은 변경하지 않는다. 이 단계는 M3·M4 테스트 먼저 지점에 해당한다. 독립 test-writer가 케이스를 작성했고 RED 확인 후 구현했다.

## TDD 증거

M3 등록 검사와 M4 입력·패치 차단 지점을 검증했다. 규칙·역할 연결을 포함한 M3 전체와 M5 이후는 완료하지 않았다.

| 지점 | 테스트 | 작성자 | RED 사유 | GREEN | 되돌림 |
|---|---|---|---|---|---|
| M3 등록 검사 | scripts/test-codex-plugin.sh 17개 fixture | test-writer | --codex 모드 부재, 기능 13개 실패·사용법 2개 통과. 주 에이전트가 재실행 확인 | 17개 통과 | A 트랙 해당 없음 |
| M4 차단 연결 | scripts/hook-cases.txt 47개 + 등록·Python 부재 2개 | test-writer 43개, 직접 경계 4개 | 연결 파일 없음으로 최초 43개 실패 | 49개 통과 | A 트랙 해당 없음 |

독립 리뷰에서 빈 이벤트·빈 그룹을 놓친 결함을 찾았다. 두 테스트를 먼저 추가해 2개 실패를 확인한 뒤 거절하도록 보완했고 17개 모두 통과했다.

`check-plugin.sh --codex`는 등록만 읽고 훅을 실행하거나 신뢰를 부여하지 않는다. 명령이 간접 호출하는 스크립트까지 분석하지 않으므로 미지원 ask를 동적으로 반환하는 모든 명령을 정적 검사로 증명하지 않는다.

독립 코드 리뷰에서 경로 끝 공백 보호 우회와 다른 프로젝트 설정 상속을 재현했다. 각각 회귀 케이스를 먼저 추가해 실패를 확인한 뒤, 모호한 경로 공백 거절과 cwd의 루트 설정 강제 사용으로 수정했다. 심볼릭 링크의 루트 밖 이탈도 임시 프로젝트에서 검증했다.

## 검증하지 못한 것

| 무엇 | 이유 | 확인 시점 |
|---|---|---|
| 신뢰 후 실제 훅 실행·이벤트 입력 | 신뢰 조작과 인증된 실행을 하지 않음 | 단계 2 통합 검증 |
| 이미 신뢰한 훅 변경 시 재검토 | 처음부터 untrusted인 환경만 사용 | 실제 신뢰 검증 시 |
| Codex 앱 화면의 설치·신뢰 | CLI와 app-server 목록만 검사 | 최종 통합 검증 |
| Claude 실제 플러그인 실행 | 현재 PATH에 claude 없음 | 최종 검증 전 |
| 전체 검사 통과 | 기존 이식성·deps·Claude CLI 실패 | 기준선 수정 범위 승인 후 |

## 남은 것

- 규칙 주입·역할·승인 대체·후처리·도구별 기록·초기화 선택 연결이 남았다.
- Claude 실제 실행 환경과 기존 검사 실패를 해결해야 공동 지원 완료를 보고할 수 있다.
- 커밋·push·PR·전역 설정 변경은 실행하지 않았다.

## 최종 전체 검사

`plugin/scripts/dev.sh test`를 제한 밖에서 실행했다. 전체 exit 1이며 기존 실패는 그대로 남아 있다. 실행 중 수정하던 이전 검사 결과 대신 마지막 고정된 코드 상태의 결과를 기록했다.

| 항목 | 결과 |
|---|---|
| 훅 회귀 | 데이터 610개·등록 보조 검사 포함 612개 통과, 실패 0 |
| Codex 등록 계약 | 17개 통과 |
| 문서 | 이번 수정 4파일 오류 0, 약어 경고 15 |
| 이식성 | 기존 harness-conf.md 3건 실패 |
| dev.sh | 26개 중 25개 통과, 기존 deps 출력 형식 1건 실패 |
| Claude 매니페스트 | CLI 없음으로 검사 불가 |
| 변경 공백 검사 | git diff --check 통과 |
| Gemini | 키 없음으로 생략 |

커밋은 실행하지 않았다. 추후 제안할 분할은 공동 지원 스펙·설치 실험·등록 검사 1개, Codex 차단 연결·회귀·현재동작 문서 1개다. 기존 사용자 변경은 제외한다. 현재 전체 검사가 실패하므로 이 분할안은 실행 가능한 커밋 승인을 요청하는 상태가 아니다.

## 실행 비용

상시 규칙·스킬 description은 바꾸지 않아 상시 비용 증가는 0이다. Codex가 Bash 또는 apply_patch를 호출할 때 Python 연결 1회와 기존 판정 프로세스가 실행된다. 패치는 경로 수만큼 기존 쓰기 판정기를 호출한다. 실행 시간 실측은 하지 않았다.

## 관련 문서

- [공동 지원 스펙](../specs/cross-cutting/codex-harness-delivery.md)
- [공식 플러그인 형식](https://developers.openai.com/plugins/build/plugins)
- [공식 훅 신뢰 절차](https://learn.chatgpt.com/docs/hooks)

## 기준선 실패 수정

2026-11-10 후속 진행에서 기존 이식성 위반 3건과 deps 실패를 수정했다. 이 절은 앞의 당시 실패 기록 이후 상태다.

| 수정 | 근거 | 확인 |
|---|---|---|
| harness-conf.md 예시·자리표시자 | 프로젝트 명령·경로 리터럴과 미등록 슬롯 예시가 검사에 걸림 | 문서 설명 보존, 자리표시자로 수정 후 이식성 위반 0 |
| dev.sh deps 출력 | `$log` 뒤 한글이 변수명에 포함되어 unbound variable 발생 | `${log}`로 경계 명시, 기존 테스트 유지 |

| 지점 | 테스트 | 작성자 | RED | GREEN | 되돌림 |
|---|---|---|---|---|---|
| 기존 deps 버그 | 기존 test-dev.sh deps 케이스·임시 dev.conf 재현 | 기존 테스트 | deps exit 1, unbound variable | deps exit 0, 로그 경로 출력 | 수정 한 줄 되돌리면 exit 1, 복구하면 exit 0 |

Claude CLI는 현재 PATH·기본 설치 위치·npm 로컬 캐시에서 찾지 못했다. 사용자 전역 설치나 새 의존성 설치는 실행하지 않았으며, 매니페스트·실제 Claude 실행 검증을 통과 처리하지 않는다.

수정 후 `plugin/scripts/dev.sh test` 재실행 결과: 이식성 위반 0, 훅 검사 612개 통과, 문서 72파일 오류 0, dev.sh 26개 통과, Codex 등록 17개 통과다. 전체는 Claude CLI 부재에 따른 매니페스트 검사 1단계만 실패했다. CLI 임시 설치는 사용자 확인을 요청했고 아직 실행하지 않았다.

## 임시 Claude CLI 검사

사용자가 검사용 프로그램의 임시 다운로드와 검사 후 삭제를 승인했다. 전역 설치·로그인·프로젝트 플러그인 설치는 하지 않고, 패키지·캐시·CLI 설정을 임시 폴더에 뒀다.

| 검증 | 결과 |
|---|---|
| npm 공식 패키지 | 2.1.197 다운로드. 일반 validate는 플러그인·마켓플레이스 모두 통과(version 경고만) |
| npm 버전의 JSON 검사 | --json 옵션 미지원. 검사 기준을 낮추지 않고 최신 공식 실행 파일로 재검증 |
| 공식 직접 배포 | 2.1.322. downloads.claude.ai의 latest·manifest.json으로 파일 선택, SHA256 일치 확인 |
| 최신 CLI JSON 검사 | scripts/check-plugin.sh 통과. 플러그인·마켓플레이스 모두 version 경고만 |
| macOS 코드 서명 검사 | 제한 환경에서는 invalid signature였으나 제한 밖 읽기 전용 재검사에서 valid on disk 및 satisfies its Designated Requirement로 통과. gpg가 없어 manifest 서명의 별도 검사는 미실행 |

공식 CLI 문서는 [validate의 --json이 2.1.259 이상을 요구](https://code.claude.com/docs/en/plugins/cli-reference#plugin-validate)한다고 명시한다. 실제 받은 두 버전의 차이와 일치한다. 이 검증은 플러그인 정적 검사이며 로그인한 Claude 세션에서 승인 창·스킬 실행까지 확인한 것은 아니다.

임시 최신 CLI를 이번 프로세스의 PATH에만 연결한 `plugin/scripts/dev.sh test`가 exit 0으로 끝났다. 이식성 위반 0, 훅 검사 612개, dev.sh 26개, Codex 등록 17개, Claude 플러그인·마켓플레이스 검사가 모두 통과했다. 문서 72파일 오류 0이며 경고는 남아 있다.

검사 종료 후 임시 CLI·npm 패키지·다운로드 캐시·설정 폴더를 전부 삭제하고 경로가 없음을 확인했다. 전역 CLI나 로그인 정보는 만들지 않았다. 따라서 이후 같은 전체 검사를 다시 실행하려면 별도의 Claude CLI가 필요하다. 이번 통과는 임시 실행 환경에서 확인한 결과이며, 양쪽 로그인 세션의 실제 기능 검증이나 배포 완료를 뜻하지 않는다.
