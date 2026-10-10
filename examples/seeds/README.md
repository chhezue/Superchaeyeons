# 씨앗 (`examples/seeds/`)

lang 축별 **검증된 lang 팩**을 모아 둔 곳이다. 하네스 배달물(`.claude/`)은 스택을 모른다 — `adopt` 3단계가 저장소를 실측한 뒤 맞는 씨앗을 여기서 복사하거나, 없으면 `_template/`을 실측으로 채운다. 씨앗은 실제 프로젝트에서 굴린 규칙만 둔다. 검증되지 않은 스택의 씨앗을 미리 지어 두지 않는 이유는 `docs/out-of-scope/README.md`에 있다.

## 목록

`adopt`이 실측한 lang 축과 대조하는 표다.

| 씨앗 | 스택 | 검증된 곳 | 상태 |
|------|------|-----------|------|
| [`_template/`](_template/README.md) | (스택 무관 골격) | — | 모든 lang 팩이 갖춰야 할 절의 목록 |
| [`java-spring/`](java-spring/README.md) | Java 21 · Spring Boot · JPA · Gradle | TripFit(2026-07~09) · baro-farm-be(2026-09) | 씨앗 대조 표 있음 — 복사 직후 전제를 대조한다 |

## 씨앗을 새로 올리는 조건

1. 그 스택의 실제 저장소에서 하네스를 한 사이클 이상 굴렸다
2. `_template/README.md`가 요구하는 절을 전부 갖췄다 (해당 없는 절은 "없음 — 이유")
3. 그 저장소에서 검증 없이 물려받으면 틀리는 전제를 "씨앗 대조" 표로 적었다
4. `scripts/check-doc-style.sh` 오류 0 · 훅이 있으면 `scripts/hook-cases.txt`에 케이스 추가

씨앗은 `check-portability.sh`의 판정 대상이 아니다 — 스택 사실이 있어야 하는 자리다. 그래서 씨앗 파일명은 전부 `local-*`이고, `.claude/`로 복사한 뒤에도 그 접두사가 검사기에 local 층임을 알린다 (접두사를 떼면 복사 직후부터 검사기가 막는다).
