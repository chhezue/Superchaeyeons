# Superchaeyeons — Claude Code 하네스 템플릿

Claude Code용 **하네스**(규칙·스킬·에이전트·훅·검사 스크립트) 템플릿 저장소다. 새 프로젝트에 복사해 `adopt` 스킬로 붙여 쓰는 것이 목적이고, 애플리케이션 코드는 없다. 여기서 하는 작업은 **하네스를 고치는 일**이다.

## 무엇이 들어 있나

| 경로 | 내용 | 새 프로젝트로 |
|------|------|---------------|
| `.claude/` | 규칙·스킬·에이전트·훅·`settings.json` — 목록 SSOT는 `.claude/rules/README.md` | 복사 |
| `scripts/` | `verify.sh`와 검사기 3개 · `adopt-probe.sh` · git 훅 | 복사 |
| `docs/templates/` | 산출물 등록부·문서 템플릿 | 복사 |
| `examples/seeds/` | 스택별 lang 팩 씨앗 — `adopt`이 맞는 것만 `local-*` 이름으로 복사 | 필요한 것만 |
| `AGENTS.template.md` · `.github/CONTRIBUTING.md` | 새 프로젝트 `AGENTS.md` 견본 · Git 컨벤션 견본 | 견본 |
| `docs/` 나머지 | 이 저장소의 스펙·보고서·설계 기록·안 하기로 한 것 | 안 함 |

붙이는 순서는 `README.md` "빠른 시작"이 SSOT다. 하네스를 붙이는 경로는 `adopt` 스킬 하나다.

## 이 저장소에서 작업할 때

- **완료·통과를 말하기 전에 항상 `scripts/verify.sh`** — 이 저장소의 `{{테스트 명령}}`이다. 문서도 검사 대상이라 문서만 고친 작업도 돌린다 (`preflight`의 "문서 전용은 생략 가능"보다 이 줄이 우선)
- **`core-*.md`에 프로젝트 고유 사실을 넣지 않는다** — 경로면 슬롯, 정책이면 플래그, 둘 다 아니면 `local-*.md`. 슬롯·플래그는 core가 실제로 쓸 때만 늘린다
- **구성 요소를 추가·삭제·개명하면 `.claude/rules/README.md`를 같은 턴에** 고친다 — `check-portability.sh`가 실물과 대조한다
- **훅을 고치거나 우회 경로를 찾으면 `scripts/hook-cases.txt`에 케이스부터** 넣는다 — `deny-*`는 판정 불가(python3 없음 포함)도 막아야 하고, 새 훅은 `settings.json`에 등록해야 통과한다
- **이 저장소만 "하네스 자기 수정" ☑** — 붙여 쓰는 프로젝트는 `adopt`이 ❌ + `HARNESS_SELF_EDIT="0"`으로 둔다
- **씨앗 파일은 `local-*` 이름을 유지**한다 — 접두사가 검사기에 층을 알린다. `examples/`는 참고 자료이고 규칙이 아니다
- 커밋은 `{Type}: {한글}`, 목적·주제별 최대 5개. **승인 없이 커밋하지 않는다** (`core-workflow.md` G4 · `.github/CONTRIBUTING.md`)
