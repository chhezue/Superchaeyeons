#!/bin/sh
# ask-approval.sh 케이스용 견본 git 저장소를 만든다 (scripts/hook-cases.txt가 먼저 부른다).
# 사용: setup.sh <폴더> <기본 설정 파일|-> [덮어쓸 설정 파일]
#   기본 설정 파일이 `-`면 .claude/harness.conf를 만들지 않는다(설정 없음). 덮어쓸 파일의 키는 기본 설정의 같은 키를 대체한다.
# 만드는 상태:
#   추적 중: tracked.txt · src/a.ts · lib/x.txt · lib/y.txt · package.json · api/openapi.yaml · docs/specs/{draft,approved,two}.md · docs/decisions/adr.md
#   스테이징됨(커밋 전): staged.txt (새 파일) · api/openapi.yaml (수정)  → 스테이징 파일 2개
#   추적 안 됨: untracked.txt · build/out.o · .claude/harness.conf
#   draft.md = 상태 Draft · [미정] 0개 / approved.md = 상태 Approved / two.md = 상태 Draft · [미정] 2개 / adr.md = 상태 Draft · [미정] 1개
d="$1"; base="$2"; ov="$3"
[ -n "$d" ] && [ -n "$base" ] || { echo "usage: setup.sh <dir> <base.conf|-> [override.conf]" >&2; exit 2; }
rm -rf "$d"; mkdir -p "$d" || exit 1
cd "$d" || exit 1
git init -q . || exit 1
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
mkdir -p src lib api build docs/specs docs/decisions
echo a >tracked.txt
echo b >src/a.ts
echo c >lib/x.txt
echo d >lib/y.txt
echo '{}' >package.json
echo 'openapi: 3' >api/openapi.yaml
printf '%s\n' '# Draft' '' '> 상태: Draft' '' '초안 문장입니다.' >docs/specs/draft.md
printf '%s\n' '# Approved' '' '> 상태: Approved' '' '승인된 문장입니다.' >docs/specs/approved.md
printf '%s\n' '# Two' '' '> 상태: Draft' '' '- [미정] 첫째' '- [미정] 둘째' >docs/specs/two.md
printf '%s\n' '# ADR' '' '> 상태: Draft' '' '- [미정] 하나' >docs/decisions/adr.md
git add -A
git commit -q -m "Chore: seed" || exit 1
echo e >untracked.txt
echo o >build/out.o
echo s >staged.txt
echo 'openapi: 4' >api/openapi.yaml
git add staged.txt api/openapi.yaml
if [ "$base" != "-" ]; then
	mkdir -p .claude
	conf=.claude/harness.conf
	cp "$base" "$conf"
	if [ -n "$ov" ] && [ -f "$ov" ]; then
		: >"$conf.new"
		while IFS= read -r line; do
			k="${line%%=*}"
			grep -q "^$k=" "$ov" && continue
			printf '%s\n' "$line" >>"$conf.new"
		done <"$conf"
		cat "$ov" >>"$conf.new"
		mv "$conf.new" "$conf"
	fi
fi
exit 0
