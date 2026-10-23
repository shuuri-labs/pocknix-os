#!/usr/bin/env python3
# Build-time gate for code comments: a comment must stay true about the code next to it and short,
# so this fails on (1) a repo path that no longer exists, (2) lineage or validation-status wording,
# which belongs in PATCHES.md, (3) a version, pkgrel, commit hash or date a ledger owns, (4) a
# pointer into the maintainer's notes: repo files are the only thing a comment may point at, and
# (5) a block over 2 lines outside the file's leading header. Exceptions go in check-comments.allow
# as "<path glob> :: <regex>" or "<path glob> :: <kind> :: <regex>", one per line.
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ALLOW_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-comments.allow")
KINDS = ("dead path", "notes pointer", "provenance/status", "version", "long comment")
LONG_CAP = 2   # lines per block; a line wider than WIDE counts as two
WIDE = 100
# Section rules ("# --- lockfile ---") are structure, not prose: they do not count toward the cap.
DIVIDER = re.compile(r"^(#+|//)\s*[-=]{3,}")

# Tracked text we author. Upstream or generated text is out: patch bodies, synced DTS/configs,
# vendored binaries, built JS, build output, docs (check.sh's doc checks own those).
EXCLUDE = re.compile(
    r"(\.(md|patch|diff|png|svg|jpg|ico|lock|txt|dts|dtsi|gpg|efi|dat|map|json|qml|policy|desktop"
    r"|template|cmake|slangp|opt)$)"
    r"|^(\.github|docs|vendor|build)/|/patches/|/dist/|/dts/|README|provenance|rocknix-reference"
    r"|linux\.aarch64\.conf$|kernel-firmware\.dat$|package-lock|LICENSE"
)
SLASH = re.compile(r"\.(ts|tsx|js|vdf|cpp|h)$|polkit-1/rules\.d/")
XML = re.compile(r"\.xml$")
PYTHON = re.compile(r"\.py$")

REPO_DIRS = ("scripts", "packages", "devices", "kernel", "config", "overlay")
PATH_RE = re.compile(r"(?<![\w/.\-])(" + "|".join(REPO_DIRS) + r")/[A-Za-z0-9_./<>{}$*\-]+")
# ROCKNIX-tree paths quoted on purpose (their package.mk, device dirs, kernel scripts).
FOREIGN_PATH = re.compile(r"^(packages/(linux|tools)/|devices/SM8|scripts/(config|unpack)|config/arch\.)")

PROVENANCE_RE = re.compile(
    r"\b(modell?ed on|ported from|borrowed from|adapted from|verbatim from|lifted from|copied from"
    r"|same as (armada|ROCKNIX|Valve|SteamOS)|like (armada|ROCKNIX|Valve|SteamOS) (does|do)"
    r"|(armada|ROCKNIX|Valve|SteamOS) (does|do) (this|the same|it)|(armada|ROCKNIX|SteamOS)'s)\b"
    r"|\b(from|per|follows?|mirrors?) (armada|ROCKNIX)\b"
)
STATUS_RE = re.compile(
    r"\b(UNVERIFIED|unverified|untested|VALIDATE on|validated on|validated by|tested on|verified on"
    r"|tune on device|bitten|learned the hard way|for now\b|TODO|FIXME|XXX)\b"
)
NOTES_RE = re.compile(
    r"pocknix-notes|\bdev/[a-z0-9-]+\.md|\bplans/[a-z0-9-]+\.md|maintainer-guide|learnings\.md"
    r"|progress\.md|conventions\.md"
    # the notes' dev/ file names on their own: an aside naming one is still a pointer
    r"|\b(building|claude-setup|cruft|desktop|emulation|fex-version-bump|graphics|issue-intake|kernel"
    r"|pacman-repo|patch-rebase|steam|steam-client-bump|tester-program|testing-fedora-vm)\.md\b"
)
VERSION_RE = re.compile(
    r"(?<![\w.])\d+\.\d+\.\d+(?!\.\d)(-\d+)?\b"           # 1.2.3 or 1.2.3-4, not an IPv4
    r"|\b\d+\.\d+-\d+\b"                                   # 0.2-6 style pkgver-pkgrel
    r"|\bv\d+\.\d+(\.\d+)?\b"                              # v0.8.3
    r"|(?:\b(since|before|until|kernel|mesa|gamescope|Qt|scx|FEX|polkit)\s+|[<>]=\s*)\d+\.\d+\b"
    r"|\bFEX-\d{4}\b"
    r"|\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b"  # a commit hash: hex, 7+, mixed
    r"|\b20\d{2}-\d{2}-\d{2}\b"                            # a date
)


def all_tracked(root):
    """git's view, or a plain walk when git is missing or refuses the checkout (sudo in the VM)."""
    if os.path.exists(os.path.join(root, ".git")):
        try:
            out = subprocess.run(["git", "-C", root, "ls-files", "-z"], check=True,
                                 capture_output=True).stdout
            return [n for n in out.decode().split("\0") if n]
        except (OSError, subprocess.CalledProcessError):
            pass
    names = []
    for d, dirs, fs in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "build")]
        for f in fs:
            names.append(os.path.relpath(os.path.join(d, f), root))
    return names


def tracked_files(root):
    return sorted(n for n in all_tracked(root) if not EXCLUDE.search(n))


def comment_lines(path, text):
    """Full-line comments and python docstrings as (lineno, text); Makefile `##` is make-help."""
    # Trailing comments are skipped: they are about the value beside them.
    base = os.path.basename(path)
    first = text.split("\n", 1)[0]
    python = PYTHON.search(path) or (first.startswith("#!") and "python" in first)
    if SLASH.search(path):
        starts, block = ("//", "/*", "*"), ("/*", "*/")
    elif XML.search(path):
        starts, block = ("<!--",), ("<!--", "-->")
    elif python:
        starts, block = ("#", '"""'), ('"""', '"""')
    else:
        if "." not in base and not first.startswith("#") and base not in ("PKGBUILD", "Makefile"):
            return
        starts, block = ("#",), None
    inside = in_str = False
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if n == 1 and s.startswith("#!"):
            continue
        # A string opened mid-line (x = """) is code: without this its closing quote reads as
        # the start of a docstring and the rest of the file as comment.
        if in_str:
            in_str = s.count('"""') % 2 == 0
            continue
        if block and inside:
            yield n, s
            if block[1] in s:
                inside = False
            continue
        if s.startswith(starts):
            if base == "Makefile" and s.startswith("##"):
                continue
            if block and s.startswith(block[0]) and block[1] not in s[len(block[0]):]:
                inside = True
            yield n, s
        elif python and s.count('"""') % 2:
            in_str = True


def path_exists(root, token):
    token = token.rstrip(".,:;)]'\"")
    if FOREIGN_PATH.match(token):
        return True
    pattern = re.sub(r"<[^>]*>|\$\{[^}]*\}|\$[A-Za-z_]+", "*", token)
    if pattern.endswith("-") or pattern.endswith("/"):
        pattern += "*"
    if "*" in pattern:
        parts = pattern.split("/")
        cands = [root]
        for part in parts:
            nxt = []
            for c in cands:
                if not os.path.isdir(c):
                    continue
                for e in os.listdir(c):
                    if fnmatch.fnmatch(e, part):
                        nxt.append(os.path.join(c, e))
            cands = nxt
            if not cands:
                return False
        return True
    return os.path.exists(os.path.join(root, pattern))


def load_allow(path):
    """(glob, kind or None, regex). A malformed line is an error, not a blanket exemption."""
    rules = []
    if not os.path.exists(path):
        return rules
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [f.strip() for f in line.split(" :: ")]
        if len(fields) == 2:
            glob, kind, regex = fields[0], None, fields[1]
        elif len(fields) == 3 and fields[1] in KINDS:
            glob, kind, regex = fields
        else:
            sys.exit("%s:%d: expected '<glob> :: <regex>' or '<glob> :: <kind> :: <regex>'" % (path, n))
        if not glob or not regex:
            sys.exit("%s:%d: empty glob or regex" % (path, n))
        rules.append((glob, kind, re.compile(regex)))
    return rules


def allowed(rules, path, kind, text):
    return any(fnmatch.fnmatch(path, g) and (k is None or k == kind) and r.search(text)
               for g, k, r in rules)


def long_blocks(text, lines):
    """(first lineno, its text, "N lines") per block of adjacent comment lines over LONG_CAP."""
    raw = text.splitlines()
    # The leading header may run long: it starts on line 1, or after a shebang / XML prolog.
    header_at = 2 if raw and raw[0].startswith(("#!", "<?xml")) else 1
    blocks = []
    for n, s in lines:
        if blocks and n == blocks[-1][-1][0] + 1:
            blocks[-1].append((n, s))
        else:
            blocks.append([(n, s)])
    for i, b in enumerate(blocks):
        if i == 0 and b[0][0] <= header_at:
            continue
        weight = sum(0 if DIVIDER.match(s) else 2 if len(raw[n - 1].rstrip()) > WIDE else 1
                     for n, s in b)
        if weight > LONG_CAP:
            yield b[0][0], b[0][1], "%d lines" % weight


def scan(root, allow_rules):
    hits = []
    for rel in tracked_files(root):
        full = os.path.join(root, rel)
        try:
            text = open(full, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        lines = list(comment_lines(rel, text))
        hits.extend((rel, n, "long comment", what) for n, s, what in long_blocks(text, lines)
                    if not allowed(allow_rules, rel, "long comment", s))
        for n, s in lines:
            found = []
            for m in PATH_RE.finditer(s):
                if not path_exists(root, m.group(0)):
                    found.append(("dead path", m.group(0).rstrip(".,:;)]'\"")))
            m = NOTES_RE.search(s)
            if m:
                found.append(("notes pointer", m.group(0)))
            m = PROVENANCE_RE.search(s) or STATUS_RE.search(s)
            if m:
                found.append(("provenance/status", m.group(0)))
            m = VERSION_RE.search(s)
            if m:
                found.append(("version", m.group(0)))
            hits.extend((rel, n, kind, what) for kind, what in found
                        if not allowed(allow_rules, rel, kind, s))
    return hits


def selftest(allow_rules):
    """Plant comments of each kind in a scratch copy of the tree: each must fail, nothing else."""
    tmp = tempfile.mkdtemp(prefix="check-comments-")
    try:
        for rel in all_tracked(ROOT):  # every file: the dead-path rule must see the whole tree
            dst = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(os.path.join(ROOT, rel), dst)
        planted = [
            "# see scripts/does-not-exist.sh for the helper",
            "# the full story is in pocknix-notes dev/kernel.md",
            "# ported from ROCKNIX's SM8550 quirk 096-cpuidle",
            "# pinned at mesa 26.2.3 until the base moves",
        ]
        with open(os.path.join(tmp, "scripts/lib.sh"), "a", encoding="utf-8") as f:
            f.write("\n" + "\n".join(planted) + "\n")
        # New files (an existing one may be allowed). Long hits expected: the 3-line block (7) and
        # the wide pair (15), never the header, the ruled pair or the python string.
        long_sh = ["#!/bin/sh", "# header", "# runs", "# long", "# fine", "true",
                   "# a body comment", "# that runs to", "# three lines", "true",
                   "# --- section ---", "# two lines under a rule", "# pass", "true",
                   "# " + "wide " * 20, "# second line", "true"]
        tpl_py = ["X = \"\"\"", "# inside a string", "\"\"\"", "", "", "def f():", "    pass"]
        for rel, body in (("scripts/selftest-long.sh", long_sh),
                          ("scripts/selftest_tpl.py", tpl_py)):
            with open(os.path.join(tmp, rel), "w", encoding="utf-8") as f:
                f.write("\n".join(body) + "\n")
        hits = scan(tmp, allow_rules)
        for h in hits:
            print("  planted -> %s:%d: %s: %s" % h)
        caught = ("scripts/does-not-exist.sh", "pocknix-notes", "ported from", "26.2.3", "mesa 26.2")
        kinds = {h[2] for h in hits if h[0] == "scripts/lib.sh" and h[3] in caught}
        kinds |= {h[2] for h in hits if h[0] == "scripts/selftest-long.sh"}
        longs = sorted(h[1] for h in hits if h[0] == "scripts/selftest-long.sh")
        stray = [h for h in hits if h[0] not in ("scripts/lib.sh", "scripts/selftest-long.sh")]
        if kinds != set(KINDS) or longs != [7, 15] or stray:
            print("selftest FAILED: caught %s at long lines %s, wanted %s at [7, 15]; stray %s"
                  % (sorted(kinds), longs, list(KINDS), stray))
            return 1
        print("selftest: each planted comment caught, nothing else flagged")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    allow_rules = load_allow(ALLOW_FILE)
    if "--selftest" in argv:
        return selftest(allow_rules)
    hits = scan(ROOT, allow_rules)
    for rel, n, kind, what in hits:
        print("%s:%d: %s: %s" % (rel, n, kind, what))
    if hits:
        print("%d stale-looking comment(s); fix the comment or add a line to scripts/check-comments.allow"
              % len(hits))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
