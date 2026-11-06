#!/usr/bin/env python3
# Build-time gate for hash-gated retirements: an install script that deletes an old image-overlay
# file only when it is unedited lists the sha256 of every version the overlay shipped. A typo there
# leaves the file on every fielded device with no log line, so each script's list must equal the
# versions git history holds for its rows in retired-hashes.list, and a script with sha256s and no
# row fails too. Needs full history (CI checks out with fetch-depth 0).
import hashlib
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LIST = os.path.join(ROOT, "scripts", "retired-hashes.list")
SHA = re.compile(r"\b[0-9a-f]{64}\b")


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, check=False)


def shipped(path):
    commits = git("log", "--format=%H", "HEAD", "--", path).stdout.decode().split()
    hashes = set()
    for c in commits:
        blob = git("show", f"{c}:{path}")
        if blob.returncode == 0:
            hashes.add(hashlib.sha256(blob.stdout).hexdigest())
    return hashes


def read(rel):
    return open(os.path.join(ROOT, rel), encoding="utf-8").read()


def problems(read):
    rows = {}
    for line in open(LIST, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = [p.strip() for p in line.split("::")]
        rows.setdefault(fields[0], []).append(fields[1])

    bad = []
    for script in git("ls-files", "*.install").stdout.decode().split():
        if SHA.search(read(script)) and script not in rows:
            bad.append(f"{script}: embeds sha256s but has no row in scripts/retired-hashes.list")
    for script, paths in rows.items():
        if not os.path.isfile(os.path.join(ROOT, script)):
            bad.append(f"{script}: listed in retired-hashes.list but missing")
            continue
        found = set(SHA.findall(read(script)))
        want = set()
        for p in paths:
            h = {p[len("sha256="):]} if p.startswith("sha256=") else shipped(p)
            if not h:
                bad.append(f"{script}: {p} has no version in git history")
            want |= h
        for h in sorted(found - want):
            bad.append(f"{script}: {h[:16]}... matches no shipped version of its rows")
        for h in sorted(want - found):
            bad.append(f"{script}: a shipped version ({h[:16]}...) is missing from its list")
    return bad


# Flips one digit of the first listed hash: the typo must be reported twice (unknown + missing).
def selftest():
    target = next(l.split("::")[0].strip() for l in open(LIST, encoding="utf-8")
                  if l.strip() and not l.startswith("#"))
    text = read(target)
    h = SHA.search(text).group(0)
    typo = ("1" if h[0] != "1" else "2") + h[1:]
    planted = lambda rel: text.replace(h, typo) if rel == target else read(rel)
    return 0 if len(problems(planted)) == 2 and not problems(read) else 1


def main():
    if git("rev-parse", "--is-shallow-repository").stdout.decode().strip() == "true":
        print("shallow clone: history needed")
        return 1
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    bad = problems(read)
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
