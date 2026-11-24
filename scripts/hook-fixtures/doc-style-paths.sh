#!/usr/bin/env bash
set -eu
checker="$(cd "$(dirname "$0")/../../plugin/scripts" && pwd)/check-doc-style.sh"
mkdir -p "$1"
cd "$1"
git init -q
good='guide.md'
tracked=' 등록 한글.md'
untracked=$'메모\n초안.md'
printf '# 안내\n\n본문\n' > "$good"
printf '# 안내\n\n본문\n#### 위반\n' > "$tracked"
cp "$tracked" "$untracked"
git add -- "$good" "$tracked"
case "$2" in
prepare) mkdir -p .claude; cp "$(dirname "$checker")/../../scripts/hook-fixtures/ask/base.conf" .claude/harness.conf ;;
explicit) exec "$checker" "$tracked" "$untracked" ;;
*) exec "$checker" "$2" ;;
esac
