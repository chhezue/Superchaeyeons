"""복사 설치 이전 때 Git 훅과 파일 경로를 참조하는 위치를 읽는다."""
import fnmatch
import os
from pathlib import Path
import re
import subprocess


def git(*args, **kwargs):
    return subprocess.run(["git", *args], stdout=subprocess.PIPE, check=True, **kwargs).stdout


def show(path):
    text = str(path)
    return text if text.isprintable() else ascii(text)


def describe(path):
    if path.is_symlink():
        return f"{show(path)} -> {show(os.readlink(path))}"
    return show(path)


def copied_path(path):
    folders = (".claude/rules", ".claude/skills", ".claude/hooks", ".claude/agents",
               ".agents/skills", ".agents/rules", "scripts/git-hooks")
    if any(path == Path(folder) or Path(folder) in path.parents for folder in folders):
        return True
    if str(path) in (".claude/settings.json", ".claude/harness.conf", "harness.conf"):
        return True
    if path.parent == Path("scripts"):
        patterns = ("dev.sh", "check-*.sh", "*-patterns.txt", "init-harness-probe.sh",
                    "analyze-corrections.sh", "polish-with-gemini.sh", "test-hooks.sh",
                    "hook-cases.txt", "verify.sh", "install-git-hooks.sh")
        return any(fnmatch.fnmatchcase(path.name, pattern) for pattern in patterns)
    return "templates" in path.parts and path.suffix == ".md"


def main():
    root = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).rstrip("\n")).resolve()
    os.chdir(root)
    hook_dir = Path(os.fsdecode(git("rev-parse", "--path-format=absolute", "--git-path", "hooks")).rstrip("\n"))
    print("## Codex 이전 조사")
    print("Git 훅 디렉터리 (core.hooksPath 반영):", describe(hook_dir))
    names = set()
    installed = []
    if hook_dir.is_dir():
        for hook in sorted(hook_dir.iterdir()):
            if hook.name.endswith(".sample") or not (hook.is_file() or hook.is_symlink()):
                continue
            state = "실행 가능" if hook.is_file() and os.access(hook, os.X_OK) else "실행 불가"
            print(f"- {describe(hook)} ({state})")
            if hook.is_file():
                installed.append(hook)
            if hook.is_relative_to(root):
                names.add(hook.relative_to(root))

    paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    for raw in paths.split(b"\0"):
        if raw:
            path = Path(os.fsdecode(raw))
            if copied_path(path) and (path.is_file() or path.is_symlink()):
                names.add(path)
    print("\n이전 후보 (파일 이름만으로 출처를 정하지 않음):")
    patterns = set()
    for path in sorted(names):
        print("-", describe(path))
        patterns.add(os.fsencode(path))
        if path.name in {"README.md", "SKILL.md", "settings.json", "harness.conf"}:
            patterns.add(os.fsencode(Path(path.parent.name) / path.name))
        else:
            patterns.add(os.fsencode(path.name))
    print("\n경로·파일명 참조 후보 (파일:줄, 이름이 같으면 실제 대상 확인):")
    needles = [word for word in sorted(patterns) if b"\n" not in word]
    if not needles:
        return
    # Git의 작업 트리 검색에는 .git/hooks, 외부 hooksPath와 링크 본문이 포함되지 않는다.
    literal = re.compile(b"|".join(re.escape(n) for n in sorted(needles, key=len, reverse=True)))
    for hook in installed:
        try:
            with hook.open("rb") as stream:
                if b"\0" in stream.read(8192):
                    print(f"- {show(hook)} (바이너리 훅, 호출 대상 직접 확인)")
                    continue
                stream.seek(0)
                for number, line in enumerate(stream, 1):
                    for match in dict.fromkeys(literal.findall(line)):
                        print(f"- {show(hook)}:{number} → {show(os.fsdecode(match))}")
        except OSError as error:
            print(f"- {show(hook)} (본문 확인 실패: {error})")
    result = subprocess.run(["git", "grep", "--no-color", "--no-textconv", "--untracked",
                             "--exclude-standard", "-n", "-z", "-I", "-o", "-F", "-f", "-"],
                            input=b"\n".join(needles) + b"\n", stdout=subprocess.PIPE)
    if result.returncode not in (0, 1):
        raise SystemExit(result.returncode)
    # With -z Git uses NUL between path, line number, and match; paths can contain newlines.
    for path, number, match in re.findall(rb"([^\0]+)\0(\d+)\0([^\n]+)\n", result.stdout):
        print(f"- {show(os.fsdecode(path))}:{number.decode('ascii')} → {show(os.fsdecode(match))}")


if __name__ == "__main__":
    main()
