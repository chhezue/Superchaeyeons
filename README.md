# Superchaeyeons

Claude Code용 **AI 하네스 템플릿** — 규칙·스킬·훅·에이전트 한 벌.

[TripFit 백엔드](https://github.com/Central-MakeUs/TripFit-server)에서 두 달간 굴리며 다듬은 하네스를, 다른 프로젝트에 붙일 수 있게 프로젝트 고유 사실을 걷어내고 분리한 것입니다.

## 무엇을 하는가

에이전트가 **혼자 판단하면 안 되는 지점에서 멈추게** 만듭니다.

- 문서와 구현이 어긋나면 → 조용히 맞추지 않고 **질문**
- API 계약·에러코드·권한이 바뀌면 → **같은 턴에** 스펙·enum까지 갱신 (미루기 금지)
- 위험한 shell 명령 → 훅이 **결정적으로 차단** (판단에 맡기지 않음)
- 커밋·이슈·PR 생성 → **항상 먼저 확인**

4개 레이어로 나뉘어 있습니다 — 자세한 설계는 [`docs/harness/`](docs/harness/README.md).

## 붙이는 법

```bash
cp -R .claude docs/harness docs/templates .github scripts <새-프로젝트>/
```

그다음 **[`.claude/rules/harness-map.md`](.claude/rules/harness-map.md) 하나만 채우면 됩니다** — 경로 슬롯 13개, 명령 슬롯 4개, 스택 옵션 7개. 규칙 파일은 건드리지 않습니다.

`AGENTS.template.md` → `AGENTS.md`로 복사해 프로젝트 정보를 채우고, 안 쓰는 스택 팩은 파일째 지웁니다.

전체 순서: [`AGENTS.md`](AGENTS.md) "새 프로젝트에 붙이는 순서"

## 구조

| 경로 | 내용 |
|------|------|
| `.claude/rules/` | `harness-map`(슬롯) + `core-*` 6개(프로젝트 무관) + Java·Spring 팩 4개 |
| `.claude/skills/` | `specify` · `safe-refactor` · `debug` · `preflight` · `defer` · `retro` |
| `.claude/agents/` | `researcher` · `doc-reviewer` · `spring-reviewer` |
| `.claude/hooks/` | `deny-*` 2 · `warn-*` 1 · `auto-*` 1 |
| `docs/harness/` | 레이어별 설계 설명 |
| `examples/tripfit/` | 실제로 채운 모습 (참고용, 규칙 아님) |

## 언어

규칙 본문은 한국어입니다. 영어로 옮겨도 되지만, 실측 결과 토큰 차이는 크지 않았습니다 — 자세한 근거는 [`docs/harness/layer1-human-gate.md`](docs/harness/layer1-human-gate.md).
