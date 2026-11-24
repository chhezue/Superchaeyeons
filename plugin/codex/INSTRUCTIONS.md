# Codex 연결 안내

공통 규칙·8개 스킬·검사 도구는 같은 플러그인 원본을 사용한다. 이 문서는 Codex에서 호출·승인·기록을 연결하는 방법이다. Claude Code의 동작과 설정을 바꾸지 않는다.

## 승인 사전 검사

공통 규칙·스킬의 “훅 승인 창”은 Claude Code에 해당한다. Codex에서는 승인 대상 작업의 구체적인 내용과 영향·검사 이유를 보여 주고 사용자 답을 기다린다. 이 절차는 행동 규칙이며 Claude 승인 창과 같은 강제력을 보장하지 않는다.

행동 전에 `python3 -I __PLUGIN_ROOT__/scripts/check-codex-approval.py`로 제안 내용을 검사한다. 입력은 표준 입력의 JSON이며 tool_name과 tool_input을 포함한다. 명령은 Bash/command, 파일은 Write/file_path/content 또는 Edit/file_path/old_string/new_string으로 전달한다. 패치는 변경 후 파일 내용으로 파일마다 검사하고 추적 파일 삭제·이동 원본은 `git rm -- 경로`를 사전 검사한다. 사전 검사는 제안한 명령이나 편집을 실행하지 않는다.

- allow(exit 0): 승인 대상이 아니거나 해당 플래그가 꺼져 있다.
- confirm(exit 3): 사용자에게 내용을 보여 주고 실행 전에 명시적 답을 기다린다. 이미 같은 구체적 작업을 승인받았으면 반복해서 묻지 않는다.
- deny(exit 2): 커밋 전 검사 등 선행 조건을 해결한다. 사용자 확인을 이유로 차단을 우회하지 않는다.

Codex 훅에 permissionDecision ask를 반환하지 않는다. 명령 규칙의 prompt는 지원하는 샌드박스 밖 실행 승인에만 적용되며 모든 편집의 승인을 강제하지 않는다. 훅이 차단한 일을 환경 변수·승인 파일·다른 도구로 우회하지 않는다.

## 공통 절차 호출

공통 규칙·스킬·역할의 `${CLAUDE_PLUGIN_ROOT}`와 scripts/ 경로는 `__PLUGIN_ROOT__`를 기준으로 해석한다. 현재 도구에서 지원하는 역할 호출로 researcher·test-writer·doc-reviewer를 사용한다. 역할은 초기 설정이 공통 agents/ 원본에서 생성한다. model·effort를 정하지 않고 부모 설정을 상속하며, Claude의 omitClaudeMd와 같은 격리를 가정하지 않는다. test-writer에는 shell_tool을 끈다. 읽기 전용 지시는 별도의 권한 경계와 다르다.

## 검증과 기록

완료 전에 verify-work로 실제 전체 테스트 결과를 직접 확인한다. Codex에서는 세션의 설정 값 표에 표시된 전체 테스트 명령을 프로젝트 루트에서 단독 Bash 명령으로 실행한다. PreToolUse 연결이 명령을 감싸 실제 종료 코드·작업 폴더를 호출별 표식으로 확인한다. 복합 명령이나 표식 없는 문자열 출력은 성공 증거로 추측하지 않는다. Codex Stop 연결은 확인할 수 있는 PostToolUse 실행 결과만 성공 증거로 인정한다. 진행 중인 실행과 알 수 없는 응답을 성공으로 간주하지 않는다. JSON 기록 파싱 경고가 있으면 훅만 믿고 완료를 선언하지 않는다.

회고는 `.codex/corrections/`, 다듬기는 `.codex/polish/`를 쓰고 공통 도구에는 `HARNESS_RUNTIME=codex`를 전달한다. 사용자 메시지 원문은 로컬 기록에 보관한다.
