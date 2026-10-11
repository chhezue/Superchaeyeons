# Superchaeyeons

Claude Code용 **AI 하네스 템플릿** — 규칙·스킬·훅·에이전트 한 벌을 새 프로젝트에 복사해 붙이는 저장소입니다. [TripFit 백엔드](https://github.com/Central-MakeUs/TripFit-server)에서 두 달간 굴린 하네스가 [baro-farm-be](https://github.com/dogs-team/baro-farm-be)로 옮겨 붙이는 과정에서 갈라졌습니다. 그 경험으로 프로젝트 고유 사실을 전부 걷어내, **어느 저장소에 붙여도 규칙 파일을 고치지 않는** 부품으로 만든 것이 이 저장소입니다. 무엇을 어디서 참고했는지는 [`docs/references.md`](docs/references.md)에 있습니다.

## 하는 일

에이전트가 **혼자 판단하면 안 되는 지점에서 멈추게** 만듭니다. 멈추는 지점은 다음과 같습니다.

- 문서와 구현이 어긋나면 → 조용히 맞추지 않고 **질문**
- 요청이 "알아서·적당히"처럼 열려 있으면 → 구현 전에 **라운드 인터뷰**(`ask`)
- API 계약·에러코드·권한이 바뀌면 → **같은 턴에** 스펙·enum까지 갱신 (미루기 금지)
- 위험한 shell 명령·범위 밖 쓰기 → 훅이 **결정적으로 차단** (판단에 맡기지 않음)
- 코드를 고치고 테스트를 안 돌린 채 "완료"라고 하면 → `Stop` 훅이 **되돌림**
- 커밋·이슈·PR 생성 → **항상 먼저 확인**

강제력이 다른 4개 레이어(규칙 → 스킬·에이전트 → 훅 → 기계 검증)로 나뉘어 있습니다. **구성 요소 하나하나가 언제 실행되고 무엇을 묻고 검사하는지, 고치려면 어디를 건드리는지**는 [`docs/harness/component-map.md`](docs/harness/component-map.md)에 있습니다. 설계 근거는 [`docs/harness/`](docs/harness/README.md), 왜 이렇게 만들었는지 긴 글은 [`docs/harness-engineering.md`](docs/harness-engineering.md).

## 붙이는 순서

배달물은 `.claude/`·`docs/templates/`·`scripts/` 셋이고, 그대로 복사하는 것으로 시작합니다.

```bash
cp -R .claude docs/templates scripts <새-프로젝트>/   # .github/CONTRIBUTING.md 는 루트에 둘 수 있을 때만
```

그다음 새 프로젝트에서 **`adopt` 스킬을 돌립니다.** 저장소를 실측해(`scripts/adopt-probe.sh`) [`.claude/rules/harness-map.md`](.claude/rules/harness-map.md)의 축 4개 · 슬롯 22개 · 능력 플래그 7개를 **제안**하고, 승인하면 채웁니다. 스택에 맞는 씨앗이 `examples/seeds/`에 있으면 `local-*` 이름 그대로 복사해 실물과 대조하고, 없으면 `_template/`을 실측으로 채웁니다. `AGENTS.template.md` → `AGENTS.md`도 이 단계에서 만듭니다. 규칙 파일(`core-*.md`)은 건드리지 않습니다.

마지막으로 git 훅을 설치합니다. 커밋 형식과 부품 계약·문서 스타일·훅 규약을 커밋 전에 검사합니다.

```bash
./scripts/install-git-hooks.sh
```

전체 순서와 각 단계의 근거: [`AGENTS.md`](AGENTS.md) "새 프로젝트에 붙이는 순서".

## 디렉터리 구조

경로별로 무엇이 들어 있고 새 프로젝트에 배달되는지의 표입니다.

| 경로 | 내용 |
|------|------|
| `.claude/rules/` | `harness-map`(축·슬롯·플래그 값) + `core-*` 8개(프로젝트 무관 — 7개 always-load, `core-code-comments`는 소스 파일 접근 시) + `doc-writing` + `README`(구조 인덱스). 스택 규칙 없음 |
| `.claude/skills/` | `adopt` · `ask` · `specify` · `safe-refactor` · `debug` · `preflight` · `defer` · `retro` |
| `.claude/agents/` | `researcher`(G1 외부 문서 조사) · `doc-reviewer`(G3 문서 리뷰) |
| `.claude/hooks/` | 스택 무관 5개 — `deny-*` 3 · `warn-*` 1 · `ask-*` 1. 규약은 `scripts/test-hooks.sh`가 판정 |
| `scripts/` | 검사기 3개(`check-portability` · `test-hooks` · `check-doc-style`)와 그 래퍼 `verify.sh`, 실측 `adopt-probe.sh`, git 훅 |
| `examples/seeds/` | 검증된 lang 팩 씨앗(`java-spring/`) + 스택 무관 골격(`_template/`). 파일명이 전부 `local-*`라 복사 뒤에도 검사기가 core로 오인하지 않음 |
| `examples/tripfit/` · `examples/baro/` | 실제로 채운 모습 두 가지 (참고용, 이 저장소의 규칙 아님) |
| `docs/templates/` | 산출물 등록부 + 유형별 문서 템플릿 (함께 배달) |
| `docs/harness/` · `docs/out-of-scope/` · `docs/references.md` | 설계 설명 · 안 하기로 한 것 · 참조한 저장소와 차용한 것 (이 저장소 이력, 배달 안 함) |

## 수정 권한 3층

위 "4개 레이어"가 **강제력**의 축이라면, 이 표는 **누가 고칠 수 있는가**의 축입니다. 서로 다른 구분이고, 이 구분이 이식성의 근거입니다.

| 층 | 파일 | 수정 |
|----|------|------|
| **core (부품)** | `core-*.md` · 스킬 · 에이전트 · 훅 · `settings.json` | 금지 — `scripts/check-portability.sh`가 고유명사·스택 식별자·경로 리터럴을 exit code로 막음 |
| **map (값)** | `harness-map.md` | `adopt`이 채움 |
| **local (고유)** | `.claude/` 안의 `local-*` 파일 | 자유 — 복사한 씨앗과 저장소 고유 규칙 |

## 이 저장소의 검증 명령

부품 계약·always-load 예산(`check-portability`), 훅 규약 케이스 파일과 python3 부재 케이스(`test-hooks`), 문서 스타일(`check-doc-style --all`)을 한 번에 돌리는 명령입니다. 이것이 이 저장소의 `{{테스트 명령}}`이고, `Stop` 훅은 코드를 고친 턴에 이 명령의 실행 기록이 있는지 봅니다.

```bash
scripts/verify.sh
```

## 규칙 본문의 언어

규칙 본문은 한국어입니다. 영어로 옮겨도 되지만, 실측 결과 토큰 차이는 크지 않았습니다 — 근거는 [`docs/harness/layer1-human-gate.md`](docs/harness/layer1-human-gate.md).
