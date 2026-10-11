# 하네스 v2 범용성 증명 — 작업 보고서

하네스 v2(P0~P7)가 서로 다른 네 저장소에 core 변경 없이 붙는지 실측으로 확인한 보고서다. 결과는 네 경우 모두 슬롯·플래그·훅 상수·씨앗/템플릿만으로 표현됐고, `core-*.md`·스킬·에이전트·훅 본문을 고쳐야 하는 항목은 0건이다. 검증하지 못한 것은 아래에 이유와 함께 남겼다.

## 무엇을 했나

- `scripts/adopt-probe.sh` — `adopt` 1단계 실측을 스크립트로. 축 4개(lang·shape·deploy·stage), 커밋·브랜치 형식 집계, 슬롯 후보를 마크다운 표로 출력한다. 읽기 전용이고 판단은 하지 않는다
- 네 저장소에 실행: 이 저장소 · `TripFit-server`(원본) · `baro-farm-be`(범위 `baro-ai`) · Node·TypeScript·Prisma 가상 저장소(임시 디렉터리, 커밋 7·브랜치 3·`prisma/migrations`·`.env.production`)
- 결과로 `examples/baro/harness-map.md` 견본을 만들고, `docs/harness/` 5개와 `harness-engineering.md`에 v2 반영 노트를 달았다
- always-load 상한을 65,000B로 확정하고 `check-portability.sh`를 기본 차단으로 바꿨다

## 결정

| 결정 | 근거 | 대안 |
|------|------|------|
| 상한 65,000B 래칫 | P6 종료 실측 63,096B. 스펙 초안의 30,000B는 규칙 본문을 절반으로 줄여야 하는 값이라 현실적이지 않고, 상한이 없으면 계속 늘어난다. 래칫은 "늘리는 커밋만 막는다" | 30,000B 차단(즉시 커밋 불가) · 상한 없음(예산 개념 무의미) |
| 비 JVM 케이스는 가상 저장소 | 세 저장소 어디에도 없는 조합이어야 "카탈로그 밖"을 증명한다. 실제 Node 저장소는 없다 | 실제 Node 저장소를 구해 실행 — 있으면 그때 재실행 |
| 서술 문서는 노트만, 본문 보존 | `docs/harness/`는 배달 안 하는 이 저장소 이력이라 v1 서술을 지울 이유가 없다. 현행 SSOT는 `.claude/rules/README.md` | 전면 재작성(비용 대비 효과 낮음) |

## 실측 — 네 저장소가 네 축에서 어디에 서 있나

| 축 | Superchaeyeons | TripFit-server | baro-farm-be (`baro-ai`) | Node 가상 |
|----|---|---|---|---|
| lang | 없음 (md·sh) | Java·Gradle — 씨앗 일치 | Java·Gradle — 씨앗 + **대조 필수** | TypeScript·Node — 씨앗 없음 → `_template` |
| shape | 단일, `docs/`, `.github/` 가능 | 단일, `docs/`, `.github/` 가능 | **모노레포 13패키지**, `baro-ai/docs/`, `.github/` 불가 | 단일, `docs/`, `.github/` 없음 |
| deploy | 없음 | `deploy/`·compose·계약 스냅샷 있음 | k8s, 스냅샷 없음 | 없음 |
| stage | 커밋 4 | 커밋 649, 마이그레이션 없음 | 커밋 1,475·태그 4 | 커밋 7, **`prisma/migrations` 있음** |
| 커밋 형식 | `Type: {설명}` 3/3 | `Type: {설명}` 173/175 | **`[Type] #n - {설명}` 126/188** | `type: {설명}` 7/7 (소문자) |
| 브랜치 | `main`만 | 이슈 번호 형식 | `{type}/{desc}`·구분자 없음 반반 | `{type}/{issue}-{desc}` 2 |

## 결과 — 무엇이 바뀌고 무엇이 안 바뀌나

| 케이스 | 바뀌는 것 | core 변경 |
|--------|-----------|-----------|
| TripFit | 없음 — 기본값과 일치 | 0 |
| baro-ai | `harness-map.md` 값 · `SCOPE="baro-ai"` · `commit-msg` 정규식 `[Type] #n - ` · 씨앗 복사 후 대조(therapi·에러 코드 기반 타입·아키텍처 테스트) · `{{Git 컨벤션 SSOT}}`=(없음) | 0 |
| Node 가상 | `harness-map.md` 값 · `commit-msg` 정규식 소문자 `type:` · `_template` 채움 · DB 마이그레이션 금지 ❌ · 스택 훅 없음 | 0 |

v1(2026-09-05 이전)에서 baro는 `core-*.md`를 포함해 하네스 파일 21개를 고쳤다. v2에서 같은 저장소는 값 파일 하나와 훅 상수 두 개, 복사한 씨앗 본문만 바꾼다.

## 검증

| 검증 | 실행한 명령 | 결과 |
|------|-------------|------|
| 배달물 부품 계약 | `scripts/check-portability.sh` | 위반 0 · always-load 63,099B ≤ 65,000B · exit 0 |
| 훅 규약 | `scripts/test-hooks.sh` | 44/44 |
| 문서 스타일 | `scripts/check-doc-style.sh --all` | 오류 0 · 경고 55 |
| 실측 스크립트 | `scripts/adopt-probe.sh` × 4 | 네 저장소 모두 표 출력. 발견한 결함: `sed` 규칙 연쇄 적용(첫 규칙 결과를 둘째 규칙이 덮어씀) → 규칙마다 `t` 분기로 수정 후 baro `[Type] #n` 126건 정상 집계 |

## 검증하지 못한 것

| 무엇 | 왜 못 했나 | 누가·언제 확인하나 |
|------|-----------|-------------------|
| 세 저장소에 v2 `.claude/`를 실제로 복사해 바이트 `diff` 0 확인 | baro·TripFit 역이식은 스펙 Out of Scope. 원본 저장소를 건드리지 않았다 | 역이식 작업을 결정할 때 — `cp -R .claude` 후 `diff -r` |
| `adopt` 2~4단계(제안·승인·채움)의 실제 대화 흐름을 baro·Node에서 끝까지 | 승인 게이트가 있는 대화라 이 세션에서는 1단계(실측)까지만 기계로 돌렸다. 이 저장소 자기 채움(P3)은 4단계까지 완료 | 다음 실제 이식 때 |
| always-load 상한 값의 적정성 | 65,000B는 현 실측의 래칫이지 "적정 토큰"의 근거가 아니다 | 규칙을 줄이는 작업(후보: `core-tools` 트랙 표 중복, `harness-map` 설명 문단)마다 값을 낮춘다 |
| Node 가상 저장소에서 `_template` 채움 결과의 품질 | 템플릿을 실측으로 채우는 것은 `adopt` 3단계이고, 실제 Node 코드베이스가 없어 채울 값이 없다 | 실제 비 JVM 프로젝트에 붙일 때 — 그 결과가 검증되면 씨앗으로 승격 |

## 남은 것

- 작업 트리에 P0~P7 변경이 커밋 없이 쌓여 있다(약 75개 파일). 커밋 분할안은 채팅 보고에
- `docs/harness/`·`harness-engineering.md` 본문은 v1 이력 그대로다. 전면 재작성은 하지 않기로 했다(위 결정)
- always-load 축소는 별도 작업. 첫 후보는 `core-tools.md` 트랙 표(`core-workflow`와 중복, 약 1.5KB)
