#!/bin/bash
# 공통 포맷 — 고친 파일이 설정 FORMAT_PATHS(glob)에 맞으면 설정 FORMAT_CMD({{포맷 명령}})를 프로젝트 폴더에서 돌린다.
# Registered in plugin/hooks/hooks.json (PostToolUse Write|Edit|MultiEdit|NotebookEdit). git pre-commit이 하던 포맷을 맡는다
# (harness-plugin-delivery 스펙 — git 훅은 버전마다 바뀌는 플러그인 경로를 따라갈 수 없어 지웠다).
# FORMAT_CMD가 비어 있거나 (없음)·빈칸이면 아무것도 하지 않는다. 첫 단어가 프로젝트에 없는 상대 경로인데 플러그인 폴더에 있으면
# 플러그인 쪽을 부른다(예: scripts/dev.sh fmt — 엔진은 플러그인에, 실제 포맷 명령은 프로젝트 dev.conf에 있다).
# 막지 않는다 — 어떤 입력에도 exit 0. 포맷이 실패하면 systemMessage로 알린다.
# Hook input: JSON with "tool_input.file_path"/"notebook_path" on stdin.

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-${0%/*}/..}"
conf="$proj/.claude/harness.conf"
[ -f "$conf" ] || exit 0

cmd=""; paths=""
while IFS= read -r line || [ -n "$line" ]; do
	line="${line%$'\r'}"
	case "$line" in FORMAT_CMD=*) cmd="${line#FORMAT_CMD=}" ;; FORMAT_PATHS=*) paths="${line#FORMAT_PATHS=}" ;; esac
done <"$conf"
case "$cmd" in '' | '(없음)'* | '{'*'}') exit 0 ;; esac
[ -n "$paths" ] || exit 0

input=""
IFS= read -r -d '' input || :
path=""
[[ $input =~ \"(file_path|notebook_path)\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && path="${BASH_REMATCH[2]}"
[ -n "$path" ] || exit 0
case "$path" in "$proj"/*) rel="${path#"$proj"/}" ;; /*) exit 0 ;; *) rel="$path" ;; esac

hit=0
p='/**/'; r='/'
set -f  # glob 목록을 단어로 나눌 때 현재 폴더 파일로 펼치지 않게
for g in $paths; do
	for c in "$g" "${g#"**/"}" "${g//"$p"/$r}"; do
		[[ $rel == $c ]] && { hit=1; break 2; }
	done
done
set +f
[ "$hit" = 1 ] || exit 0

first="${cmd%% *}"
if [[ $first != /* ]] && [ ! -e "$proj/$first" ] && [ -e "$root/$first" ]; then
	cmd="$root/$cmd"
fi
if ! out="$(cd "$proj" && sh -c "$cmd" 2>&1)"; then
	out="${out//\\/\\\\}"; out="${out//\"/\\\"}"; out="${out//$'\n'/ }"
	printf '{"systemMessage":"포맷 실패 — %s (%s)"}\n' "${cmd//\"/\\\"}" "${out:0:300}"
fi
exit 0
