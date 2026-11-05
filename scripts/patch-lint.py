#!/usr/bin/env python3
"""patch-lint.py - structural check of .patch files, without applying them.

    scripts/patch-lint.py [--headers] FILE...

Fails a file whose diff is cut short: a `---` line with no `+++`, a file header with no hunk,
a hunk with fewer lines than its @@ header counts, or no hunk at all. GNU patch applies the
hunks before a truncation and exits 0, so an apply check alone passes such a file.
--headers also requires the mail headers a contributed patch carries (From:, Subject:).
Prints one line per problem; exit 1 if any.
"""
import re
import sys

HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")


def lint(path, headers):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError as e:
        return [f"{path}: cannot read ({e.strerror})"]
    if lines and lines[-1] == "":
        lines.pop()
    problems, hunks, i, n = [], 0, 0, len(lines)
    preamble = []
    while i < n:
        line = lines[i]
        if line.startswith("--- ") and not (i + 1 < n and lines[i + 1].startswith("+++ ")):
            # a commit message line starting "--- " is legal only before the first file header
            if hunks or (i + 1 >= n) or lines[i - 1].startswith(("index ", "diff ")):
                problems.append(f"{path}:{i + 1}: '{line[:70]}' has no '+++' line: the patch is cut short")
                break
        if line.startswith("--- ") and i + 1 < n and lines[i + 1].startswith("+++ "):
            target = lines[i + 1][4:].split("\t")[0]
            i += 2
            if i >= n or not HUNK.match(lines[i]):
                problems.append(f"{path}:{i}: {target} has a file header but no hunk")
                continue
            while i < n and HUNK.match(lines[i]):
                m = HUNK.match(lines[i])
                start = i + 1
                old = int(m.group(1)) if m.group(1) is not None else 1
                new = int(m.group(2)) if m.group(2) is not None else 1
                i += 1
                while (old > 0 or new > 0) and i < n:
                    c = lines[i][:1]
                    if c in (" ", "", "\t"):  # GNU patch reads a space-stripped context line
                        old, new = old - 1, new - 1
                    elif c == "-":
                        old -= 1
                    elif c == "+":
                        new -= 1
                    elif c != "\\":
                        break
                    i += 1
                if old > 0 or new > 0:
                    problems.append(f"{path}:{start}: hunk in {target} is cut short ({max(old, 0)} old / {max(new, 0)} new lines missing)")
                    return problems
                while i < n and lines[i].startswith("\\"):
                    i += 1
                hunks += 1
            continue
        if not hunks:
            preamble.append(line)
        i += 1
    if not hunks and not problems:
        problems.append(f"{path}: no diff hunk: the file changes nothing")
    if headers:
        head = "\n".join(preamble)
        for key in ("From", "Subject"):
            if not re.search(rf"^{key}: \S", head, re.M):
                problems.append(f"{path}: missing the '{key}:' header (export it with git format-patch)")
    return problems


def main():
    args = sys.argv[1:]
    headers = "--headers" in args
    files = [a for a in args if a != "--headers"]
    problems = [p for f in files for p in lint(f, headers)]
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
