#!/usr/bin/env bash
# adopt 1단계(실측) — 저장소에서 축 4개의 값과 슬롯 후보를 읽어 표로 출력한다. 읽기 전용이다.
#
# 사용:
#   scripts/adopt-probe.sh [저장소 경로] [작업 범위]     # 기본: 현재 저장소 · 범위 "."
#
# 출력은 마크다운이다 — adopt 2단계(제안)의 입력으로 그대로 붙인다. (sed 규칙은 각각 `t`로 끝나 앞 규칙의 결과를 뒤 규칙이 덮어쓰지 않는다.) 판단은 하지 않는다: 값이 있으면 값을, 없으면 "없음"을
# 근거 명령과 함께 적는다. 어느 스택에도 묶이지 않도록 흔한 흔적을 여러 개 나열한다 (다스택 예시).
# (부품성 원칙: bash 하나. 데이터 파일 없음 — 스택 힌트 목록이 늘어나면 그때 파일로 뺀다.)

set -u
root="${1:-.}"
scope="${2:-.}"
cd "$root" || { echo "FAIL: 경로 없음 — $root" >&2; exit 2; }
root="$(pwd)"
target="$root/${scope#./}"; [ "$scope" = "." ] && target="$root"

have() { [ -e "$1" ] && echo "있음 (\`$1\`)" || echo "없음"; }
count_ext() { git ls-files -- "${scope}" 2>/dev/null | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | sort | uniq -c | sort -rn | head -6 | awk '{printf "%s %s · ", $2, $1}'; }

echo "# adopt 실측표 — $(basename "$root") (범위 \`$scope\`)"
echo
echo "생성: $(date +%Y-%m-%d) · \`scripts/adopt-probe.sh\`. 값은 관례를 물려받지 않고 여기서 읽은 것만 적는다."
echo
echo "## lang"
echo
echo "| 항목 | 값 | 근거 |"
echo "|------|-----|------|"
echo "| 확장자 상위 | $(count_ext) | \`git ls-files\` 집계 |"
# 빌드 선언 파일 (다스택 예시)
found=""
for f in build.gradle build.gradle.kts pom.xml package.json pyproject.toml requirements.txt go.mod Cargo.toml Gemfile composer.json mix.exs Package.swift; do
	for p in "$target/$f" "$target"/*/"$f"; do [ -f "$p" ] && found="$found \`${p#$root/}\`"; done
done
echo "| 빌드·의존성 선언 | ${found:-없음} | 파일 존재 |"
found=""
for f in .eslintrc* biome.json .prettierrc* pyproject.toml ruff.toml .rubocop.yml .golangci.yml .editorconfig; do
	for p in "$target"/$f; do [ -f "$p" ] && found="$found \`${p#$root/}\`"; done
done
echo "| 포맷·린트 설정 | ${found:-없음} | 파일 존재 |"
ci=$(ls "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml "$root"/.gitlab-ci.yml 2>/dev/null | head -5 | sed "s|$root/||" | tr '\n' ' ')
echo "| CI 워크플로 | ${ci:-없음} | 파일 존재 — 테스트·빌드·포맷 **실제 명령**은 이 파일에서 읽는다 |"
tests=$(git ls-files -- "${scope}" 2>/dev/null | grep -ciE '(test|spec)s?[./_-]' )
echo "| 테스트 파일 수 | ${tests:-0} | 경로에 test/spec 포함 |"
echo
echo "## shape"
echo
echo "| 항목 | 값 | 근거 |"
echo "|------|-----|------|"
echo "| 저장소 루트 = 작업 범위? | $([ "$scope" = "." ] && echo "예" || echo "아니오 — 범위 \`$scope\`") | 인자 |"
docs=""
for d in docs doc documentation; do if [ -d "$target/$d" ]; then rel="${target#$root}"; rel="${rel#/}"; docs="$docs \`${rel:+$rel/}$d/\`"; fi; done
[ -z "$docs" ] && for d in docs doc; do [ -d "$root/$d" ] && docs="$docs \`$d/\` (저장소 루트)"; done
echo "| 문서 루트 후보 | ${docs:-없음} | 디렉터리 존재 |"
echo "| \`.github/\`에 파일 둘 수 있나 | $(have .github/CONTRIBUTING.md) · 이슈 템플릿 $(have .github/ISSUE_TEMPLATE) | 파일 존재 — 소유권은 사람이 확인 |"
subs=$(find "$root" -maxdepth 2 \( -name 'build.gradle*' -o -name package.json -o -name pom.xml -o -name go.mod -o -name pyproject.toml \) 2>/dev/null | grep -v node_modules | sed "s|$root/||" | xargs -n1 dirname 2>/dev/null | sort -u | grep -v '^\.$' | tr '\n' ' ')
echo "| 하위 패키지(모노레포 신호) | ${subs:-없음} | 깊이 2 안의 빌드 파일 |"
echo
echo "### 커밋 형식 실측 (최근 200개, Merge 제외)"
echo
echo "| 패턴 | 건수 |"
echo "|------|------|"
git log -200 --format=%s 2>/dev/null | grep -v '^Merge' | LC_ALL=C sed -E \
	-e 's/^\[([A-Za-z]+)\] #[0-9]+ .*/[Type] #n {설명}/' -e t \
	-e 's/^\[([A-Za-z]+)\] .*/[Type] {설명}/' -e t \
	-e 's/^([A-Z][a-z]+)(\([^)]*\))?!?: .*/Type: {설명}/' -e t \
	-e 's/^([a-z]+)(\([^)]*\))?!?: .*/type: {설명}/' -e t \
	-e 's/^[^:\[]{1,}$/(형식 없음)/' | sort | uniq -c | sort -rn | head -6 | awk '{c=$1; $1=""; printf "| `%s` | %s |\n", substr($0,2), c}'
echo
echo "### 브랜치 이름 실측 (원격)"
echo
echo "| 패턴 | 건수 |"
echo "|------|------|"
git branch -r 2>/dev/null | sed 's|.*origin/||' | grep -v '^HEAD\|^main$\|^master$\|^develop$' | LC_ALL=C sed -E \
	-e 's|^([a-z]+)/[0-9]+-.*|{type}/{issue}-{desc}|' -e t \
	-e 's|^([a-z]+)/.*|{type}/{desc}|' -e t \
	-e 's|^[^/]+$|(구분자 없음)|' | sort | uniq -c | sort -rn | head -5 | awk '{c=$1; $1=""; printf "| `%s` | %s |\n", substr($0,2), c}'
echo
echo "## deploy"
echo
echo "| 항목 | 값 | 근거 |"
echo "|------|-----|------|"
found=""
for f in deploy docker-compose.yml docker-compose.yaml compose.yml compose.yaml Dockerfile k8s helm serverless.yml vercel.json fly.toml render.yaml Procfile; do
	[ -e "$root/$f" ] && found="$found \`$f\`"
done
echo "| 배포 흔적 | ${found:-없음} | 파일·디렉터리 존재 |"
found=""
for f in openapi.json openapi.yaml swagger.json; do p=$(find "$root" -maxdepth 3 -name "$f" -not -path '*/node_modules/*' 2>/dev/null | head -1); [ -n "$p" ] && found="$found \`${p#$root/}\`"; done
echo "| API 계약 스냅샷 | ${found:-없음} | 파일 존재 — 있으면 외부 클라이언트가 소비할 가능성 |"
echo
echo "## stage"
echo
echo "| 항목 | 값 | 근거 |"
echo "|------|-----|------|"
echo "| 커밋 수 · 태그 수 | $(git rev-list --count HEAD 2>/dev/null) · $(git tag 2>/dev/null | wc -l | tr -d ' ') | \`git rev-list\` · \`git tag\` |"
mig=$(find "$target" -type d \( -name migration -o -name migrations -o -name migrate -o -name flyway -o -name liquibase \) -not -path '*/node_modules/*' 2>/dev/null | head -3 | sed "s|$root/||" | tr '\n' ' ')
echo "| 마이그레이션 디렉터리 | ${mig:-없음} | 디렉터리 이름 — 있으면 \"DB 마이그레이션 금지\" 플래그는 ❌ 후보 |"
prod=$(find "$target" -maxdepth 4 \( -name '*prod*' -o -name '*production*' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -3 | sed "s|$root/||" | tr '\n' ' ')
echo "| 운영 환경 설정 흔적 | ${prod:-없음} | 파일 이름에 prod — 운영 보존 데이터 유무는 사람이 확인 |"
echo
echo "## 슬롯 후보 (문서 위치)"
echo
echo "| 슬롯 | 후보 | 근거 |"
echo "|------|------|------|"
for pair in "스펙 저장소:specs" "결정 기록:decisions adr ADR" "감사 로그:audits" "제품 범위:product prd PRD" "용어집:glossary GLOSSARY" "아키텍처 개요:architecture ARCHITECTURE" "API 문서:api"; do
	name="${pair%%:*}"; hits=""
	for kw in ${pair#*:}; do
		for p in $(find "$root" -maxdepth 4 -iname "*$kw*" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/examples/*' 2>/dev/null | head -2); do case "$hits" in *"\`${p#$root/}\`"*) ;; *) hits="$hits \`${p#$root/}\`" ;; esac; done
	done
	echo "| \`{{$name}}\` | ${hits:-없음} | 이름 검색 (\`$(echo ${pair#*:} | tr ' ' '|')\`) |"
done
echo
echo "다음: 이 표를 근거로 축 4개·슬롯 22개·플래그 8개를 **제안**하고 사용자 승인을 받는다 (\`adopt\` 2단계). 실측으로 정해지지 않는 것(운영 데이터 보존 계획·외부 클라이언트 계획·\`.github/\` 소유권)은 질문으로 낸다."
